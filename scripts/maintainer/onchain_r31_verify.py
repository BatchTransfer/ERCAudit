#!/usr/bin/env python3
"""On-chain verification of R4 ("dynamic chainId") contracts.

For every contract the analyzer flagged R4 (chain id supplied by the deployer/caller), find the
chain id that was actually passed and compare it with the chain the contract lives on:

  1. Etherscan V2 `getsourcecode` -> ABI + ConstructorArguments. If the constructor has a
     chain-id-like uint parameter, decode its value straight from the constructor arguments.
  2. Otherwise, if the ABI has an initializer (initialize/init/__*init*) with a chain-id-like
     parameter, scan the contract's earliest transactions (Etherscan `txlist`) for the call to
     that initializer and decode the argument from the calldata.

Verdict per contract: correct | MISMATCH | zero | no_chainid_param | unverified | no_init_tx |
plan_blocked (Etherscan plan does not cover txlist on that chain) | error.

Stdlib only. Keys come from .env (ETHERSCAN_API_KEY1..ETHERSCAN_API_KEY8); they are never printed.

Usage:
    python3 onchain_r31_verify.py --results <dir with out_*.json> --out r31_verify.jsonl [--limit N]
    python3 onchain_r31_verify.py --dry-run --results <dir>     # just count targets
    python3 onchain_r31_verify.py --summarize --out r31_verify.jsonl
The run is resumable: addresses already in --out are skipped.
"""
import argparse
import glob
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

EXPECTED_CHAIN_ID = {"ethereum": 1, "binance": 56, "polygon": 137, "avalanche": 43114}
API = "https://api.etherscan.io/v2/api"
ADDR_RE = re.compile(r"0x[0-9a-fA-F]{40}")


# ---------------------------------------------------------------- keccak-256 (pure python)
_RC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
       0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
       0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
       0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
       0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
       0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]
_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
_M = (1 << 64) - 1


def _rol(x, n):
    n %= 64
    return ((x << n) | (x >> (64 - n))) & _M if n else x


def _f(a):
    for rc in _RC:
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
        a = [[a[x][y] ^ d[x] for y in range(5)] for x in range(5)]
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rol(a[x][y], _ROT[x][y])
        a = [[b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y]) for y in range(5)] for x in range(5)]
        a[0][0] ^= rc
    return a


def keccak256(data: bytes) -> bytes:
    rate = 136
    data = bytearray(data) + b"\x01"
    data += b"\x00" * (-len(data) % rate)
    data[-1] |= 0x80
    a = [[0] * 5 for _ in range(5)]
    for off in range(0, len(data), rate):
        block = data[off:off + rate]
        for i in range(rate // 8):
            a[i % 5][i // 5] ^= int.from_bytes(block[8 * i:8 * i + 8], "little")
        a = _f(a)
    out = b"".join(a[i % 5][i // 5].to_bytes(8, "little") for i in range(4))
    return out[:32]


def selector(signature: str) -> str:
    return keccak256(signature.encode()).hex()[:8]


# ---------------------------------------------------------------- .env + HTTP
def load_env():
    for p in (Path(__file__).resolve().parent / ".env", Path.cwd() / ".env", Path.home() / ".env",
              Path.home() / "domaudit_run" / ".env"):
        if p.is_file():
            for line in p.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


class KeyPool:
    """Round-robin Etherscan keys, each limited to ~4 requests/second."""

    def __init__(self):
        self.keys = [os.environ[k] for k in sorted(os.environ) if re.fullmatch(r"ETHERSCAN_API_KEY\d*", k)]
        if not self.keys:
            sys.exit("No ETHERSCAN_API_KEY* found in .env / environment.")
        self.last = [0.0] * len(self.keys)
        self.lock = threading.Lock()
        self.i = 0

    def get(self):
        with self.lock:
            idx = self.i % len(self.keys)
            self.i += 1
            wait = max(0.0, self.last[idx] + 0.25 - time.time())
            self.last[idx] = time.time() + wait
        if wait:
            time.sleep(wait)
        return self.keys[idx]


POOL = None


def etherscan(chain_id: int, **params):
    params.update(chainid=chain_id, apikey=POOL.get())
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=20) as r:
                data = json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            time.sleep(2 ** attempt)
            continue
        text = json.dumps(data)[:300].lower()
        if "rate limit" in text:
            time.sleep(1 + attempt)
            continue
        return data
    return {"status": "0", "message": "NETWORK_ERROR", "result": ""}


# ---------------------------------------------------------------- targets / decoding
def collect_targets(results_dir, rule):
    targets = {}
    for p in sorted(glob.glob(os.path.join(results_dir, "out_20*_*.json"))):
        year, chain = re.search(r"out_(\d+)_(\w+)\.json", p).groups()
        for r in json.load(open(p))["results"]:
            if rule in r.get("rules", []):
                m = ADDR_RE.search(os.path.basename(r["file"]))
                if m:
                    targets.setdefault((chain, m.group(0).lower()), {"year": year, "file": r["file"]})
    return targets


def chainlike(name):
    return bool(re.search(r"chain_?id", name or "", re.I))


def head_value(hexdata, abi_inputs, index):
    """Value of the static uint at ABI input position `index` (dynamic types only take an offset word)."""
    for inp in abi_inputs[:index]:
        if inp["type"].startswith("tuple") or re.search(r"\[\d+\]$", inp["type"]):
            return None  # static tuple/array widens the head; not handled
    words = [hexdata[i:i + 64] for i in range(0, len(hexdata), 64)]
    if index >= len(words) or len(words[index]) < 64:
        return None
    return int(words[index], 16)


def verify_one(chain, addr):
    chain_id = EXPECTED_CHAIN_ID[chain]
    rec = {"chain": chain, "address": addr, "expected": chain_id}
    src = etherscan(chain_id, module="contract", action="getsourcecode", address=addr)
    res = src.get("result")
    if not isinstance(res, list) or not res:
        rec.update(verdict="error", note=str(src.get("message")) + " " + str(res)[:120])
        return rec
    info = res[0]
    abi_text = info.get("ABI", "")
    if not abi_text.startswith("["):
        rec.update(verdict="unverified")
        return rec
    abi = json.loads(abi_text)
    rec["contract"] = info.get("ContractName")
    ctor = next((x for x in abi if x.get("type") == "constructor"), None)
    # 1) constructor argument
    if ctor:
        inputs = ctor.get("inputs", [])
        for i, inp in enumerate(inputs):
            if chainlike(inp["name"]) and inp["type"].startswith("uint"):
                if not (info.get("ConstructorArguments") or "").strip():
                    rec.update(verdict="args_unavailable", param=inp["name"],
                               note="ABI has the chain-id constructor param but Etherscan has no constructor args (factory-deployed?)")
                    return rec
                val = head_value((info.get("ConstructorArguments") or "").lower(), inputs, i)
                if val is not None:
                    rec.update(source="constructor", param=inp["name"], passed=val)
                    rec["verdict"] = "correct" if val == chain_id else ("zero" if val == 0 else "MISMATCH")
                    return rec
    # 2) initializer call
    inits = [x for x in abi if x.get("type") == "function"
             and re.fullmatch(r"(initialize\w*|init\w*|__\w*init\w*)", x["name"], re.I)
             and any(chainlike(i["name"]) and i["type"].startswith("uint") for i in x.get("inputs", []))]
    if not inits:
        rec["verdict"] = "no_chainid_param"
        return rec
    sels = {selector(f'{f["name"]}({",".join(i["type"] for i in f["inputs"])})'): f for f in inits}
    tx = etherscan(chain_id, module="account", action="txlist", address=addr, startblock=0,
                   endblock=99999999, page=1, offset=50, sort="asc")
    txs = tx.get("result")
    if not isinstance(txs, list):
        blocked = any(w in str(txs).lower() for w in ("not supported", "upgrade", "free api access"))
        rec["verdict"] = "plan_blocked" if blocked else "no_init_tx"
        rec["note"] = str(txs)[:120]
        return rec
    for t in txs:
        data = (t.get("input") or "")[2:].lower()
        if t.get("isError") == "0" and data[:8] in sels:
            f = sels[data[:8]]
            for i, inp in enumerate(f["inputs"]):
                if chainlike(inp["name"]) and inp["type"].startswith("uint"):
                    val = head_value(data[8:], f["inputs"], i)
                    if val is not None:
                        rec.update(source=f"{f['name']}() tx {t['hash']}", param=inp["name"], passed=val)
                        rec["verdict"] = "correct" if val == chain_id else ("zero" if val == 0 else "MISMATCH")
                        return rec
    rec["verdict"] = "no_init_tx"
    return rec


# ---------------------------------------------------------------- domain-separator recompute
RPCS = {
    "ethereum": ["https://ethereum-rpc.publicnode.com", "https://cloudflare-eth.com", "https://eth.drpc.org", "https://1rpc.io/eth"],
    "binance": ["https://bsc-dataseed.binance.org", "https://bsc-rpc.publicnode.com", "https://1rpc.io/bnb"],
    "polygon": ["https://polygon-bor-rpc.publicnode.com", "https://polygon.drpc.org", "https://1rpc.io/matic"],
    "avalanche": ["https://api.avax.network/ext/bc/C/rpc", "https://avalanche-c-chain-rpc.publicnode.com", "https://avalanche.drpc.org", "https://1rpc.io/avax/c"],
}
KNOWN_CHAIN_IDS = [1, 56, 137, 43114, 10, 42161, 8453, 100, 250, 324, 59144, 5, 11155111, 97, 80001, 80002, 43113, 3, 4, 42, 0]
DOMAIN_LAYOUTS = {  # name -> (typehash string, field order)
    "name,version,chainId,verifyingContract": ("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)", ("n", "v", "c", "a")),
    "name,chainId,verifyingContract": ("EIP712Domain(string name,uint256 chainId,address verifyingContract)", ("n", "c", "a")),
    "chainId,verifyingContract": ("EIP712Domain(uint256 chainId,address verifyingContract)", ("c", "a")),
    "name,version,verifyingContract,salt=chainId": ("EIP712Domain(string name,string version,address verifyingContract,bytes32 salt)", ("n", "v", "a", "c")),
    "name,version,chainId,verifyingContract,salt0": ("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)", ("n", "v", "c", "a", "z")),
}


def eth_call(chain, to, data):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "eth_call", "params": [{"to": to, "data": data}, "latest"]}).encode()
    for url in RPCS[chain]:
        try:
            req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "User-Agent": "domaudit/1.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                out = json.load(r)
            if "result" in out:
                return out["result"]
            if "error" in out:
                return None  # contract reverted / function missing
        except Exception:
            continue
    return "RPC_FAIL"


def decode_string(hexres):
    try:
        b = bytes.fromhex(hexres[2:])
        off = int.from_bytes(b[:32], "big")
        n = int.from_bytes(b[off:off + 32], "big")
        return b[off + 32:off + 32 + n].decode("utf-8", "replace")
    except Exception:
        return None


def recompute_check(chain, addr):
    ds_raw = eth_call(chain, addr, "0x3644e515")
    if ds_raw == "RPC_FAIL":
        return {"ds_verdict": "rpc_fail"}
    if not ds_raw or len(ds_raw) != 66:
        return {"ds_verdict": "ds_unavailable"}
    onchain = bytes.fromhex(ds_raw[2:])
    name_raw, ver_raw = eth_call(chain, addr, "0x06fdde03"), eth_call(chain, addr, "0x54fd4d50")
    names = [decode_string(name_raw)] if name_raw and name_raw != "RPC_FAIL" else []
    names = [n for n in names if n is not None] or [""]
    versions = [decode_string(ver_raw)] if ver_raw and ver_raw != "RPC_FAIL" else []
    versions = [x for x in versions if x is not None] + ["1", "2", "1.0", "v1"]
    expected = EXPECTED_CHAIN_ID[chain]
    a32 = bytes(12) + bytes.fromhex(addr[2:])
    for layout, (typestr, order) in DOMAIN_LAYOUTS.items():
        th = keccak256(typestr.encode())
        for name in names:
            for ver in (versions if "v" in order else [None]):
                for cid in [expected] + [c for c in KNOWN_CHAIN_IDS if c != expected]:
                    parts = {"n": keccak256(name.encode()), "v": keccak256((ver or "").encode()),
                             "c": cid.to_bytes(32, "big"), "a": a32, "z": bytes(32)}
                    if keccak256(th + b"".join(parts[k] for k in order)) == onchain:
                        return {"ds_verdict": "ds_correct" if cid == expected else "ds_other_chain",
                                "ds_chain_id": cid, "ds_layout": layout}
    return {"ds_verdict": "ds_no_match"}


def final_verdict(rec):
    v = rec["verdict"]
    if v in ("correct", "MISMATCH", "zero"):
        return v
    return {"ds_correct": "correct (via DOMAIN_SEPARATOR)", "ds_other_chain": "MISMATCH (via DOMAIN_SEPARATOR)"}.get(
        rec.get("ds_verdict"), (v if "ds_verdict" not in rec else rec["ds_verdict"]))


def recompute_all(path, threads):
    rows = [json.loads(l) for l in open(path)]
    todo = [r for r in rows if r["verdict"] in ("no_chainid_param", "no_init_tx", "args_unavailable", "error", "plan_blocked")
            and r.get("ds_verdict") in (None, "rpc_fail")]
    print(f"recomputing DOMAIN_SEPARATOR for {len(todo)} contracts (RPC only, no Etherscan keys)")

    def work(r):
        try:
            r.update(recompute_check(r["chain"], r["address"]))
        except Exception as e:
            r["ds_verdict"] = "rpc_fail"; r["note"] = repr(e)[:100]

    with ThreadPoolExecutor(threads) as ex:
        list(ex.map(work, todo))
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
    os.replace(tmp, path)


# ---------------------------------------------------------------- driver
def summarize(path):
    rows = [json.loads(l) for l in open(path)]
    by = defaultdict(Counter)
    for r in rows:
        fv = final_verdict(r)
        by[r["chain"]][fv] += 1
        by["ALL"][fv] += 1
    verdicts = sorted({k for c in by.values() for k in c},
                      key=lambda k: (not k.startswith("correct"), not k.startswith("MISMATCH"), k))
    print("| Chain | R4 contracts | " + " | ".join(verdicts) + " |")
    print("|---|---:|" + "---:|" * len(verdicts))
    for ch in ["ethereum", "binance", "polygon", "avalanche", "ALL"]:
        if ch in by:
            print(f"| {ch} | {sum(by[ch].values())} | " + " | ".join(str(by[ch][v]) for v in verdicts) + " |")
    bad = [r for r in rows if final_verdict(r).startswith(("MISMATCH", "zero"))]
    if bad:
        print("\nMismatches / zero chain ids:")
        for r in bad:
            print(f"  {r['chain']:9s} {r['address']} {r.get('contract')} passed={r.get('passed', r.get('ds_chain_id'))} expected={r['expected']} [{final_verdict(r)}]")


def main():
    global POOL
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default="results")
    ap.add_argument("--out", default="r31_verify.jsonl")
    ap.add_argument("--rule", default="R4")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--summarize", action="store_true")
    ap.add_argument("--recompute", action="store_true", help="add DOMAIN_SEPARATOR recompute to existing --out records (RPC only)")
    a = ap.parse_args()
    if a.recompute:
        recompute_all(a.out, a.threads)
        return summarize(a.out)
    if a.summarize:
        return summarize(a.out)
    targets = collect_targets(a.results, a.rule)
    cnt = Counter(c for c, _ in targets)
    print(f"{a.rule}: {len(targets)} unique contracts", dict(cnt))
    if a.dry_run:
        return
    load_env()
    POOL = KeyPool()
    print(f"using {len(POOL.keys)} Etherscan keys")
    done = set()
    if os.path.exists(a.out):
        done = {(json.loads(l)["chain"], json.loads(l)["address"]) for l in open(a.out)}
    todo = [k for k in sorted(targets) if k not in done][: a.limit]
    print(f"{len(done)} already done, {len(todo)} to process")
    lock = threading.Lock()
    t0 = time.time()
    n = [0]

    def work(k):
        try:
            rec = verify_one(*k)
        except Exception as e:  # keep the run alive; the record shows the failure
            rec = {"chain": k[0], "address": k[1], "expected": EXPECTED_CHAIN_ID[k[0]], "verdict": "error", "note": repr(e)[:150]}
        rec.update(targets[k])
        with lock:
            with open(a.out, "a") as fh:
                fh.write(json.dumps(rec) + "\n")
            n[0] += 1
            if n[0] % 50 == 0 or n[0] == len(todo):
                print(f"  [{n[0]}/{len(todo)}] {time.time() - t0:.0f}s", flush=True)

    with ThreadPoolExecutor(a.threads) as ex:
        list(ex.map(work, todo))
    summarize(a.out)


if __name__ == "__main__":
    main()
