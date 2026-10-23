#!/usr/bin/env python3
"""On-chain verification of R8 (stored/cached domain separator without refresh) with a chain-id fork test.

Idea: a separator that is cached at deployment keeps its value when the chain identifier changes (a hard fork, or a
deployment moved to a chain with another id); a separator that is recomputed on read follows block.chainid. We fork the
chain twice at the SAME block with Foundry's anvil:
    anvil A keeps the real chain id,   anvil B reports a different chain id (default 777777).
and call DOMAIN_SEPARATOR() (or a differently named getter) on both. State is identical, so any difference comes from the
contract reading block.chainid.

Verdicts
  R8_refuted_refreshes        separator on B differs from A: the contract recomputes it, so the flag is a false positive.
  R8_confirmed_stale          separator identical on A and B and a layout WITH chainId reproduces it: the domain is chain-bound
                              but not refreshed, so after a chain-id change the contract still signs/verifies for the old chain.
  R8_unchanged_no_chainid     identical, and a layout WITHOUT chainId reproduces it: the domain never bound the chain (that is R2,
                              not a cache problem).
  R8_unchanged_unresolved     identical, but no known layout reproduces it (custom encoding or hardcoded constants).
  ds_unavailable / rpc_fail / error   no readable separator, or the fork could not serve the call.

Only eth_call is used, against local forks. No transaction is sent and no key is involved.

Usage:
    python3 onchain_r8_verify.py --results <dir with out_*.json> --out r8_verify.jsonl [--sample 40] [--chains ethereum,polygon]
    python3 onchain_r8_verify.py --summarize --out r8_verify.jsonl
Needs Foundry (anvil) on PATH. Optional env FORK_URL_<CHAIN> (e.g. FORK_URL_ETHEREUM) to use a private node instead of the
public RPCs. Resumable. Re-uses onchain_r31_verify.py and onchain_domain_verify.py (keep the three files together).
"""
import argparse
import json
import os
import random
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import onchain_r31_verify as base  # noqa: E402
import onchain_domain_verify as odv  # noqa: E402

REAL_ID = {"ethereum": 1, "binance": 56, "polygon": 137, "avalanche": 43114}
GETTERS = ["DOMAIN_SEPARATOR", "domainSeparator", "getDomainSeparator", "DOMAIN_SEPARATOR_V4", "EIP712_DOMAIN_SEPARATOR",
           "domainSeparatorV4", "_domainSeparator", "DOMAIN_SEPARATOR_"]
SELECTORS = [("0x" + base.selector(g + "()"), g) for g in GETTERS]
ALL_LAYOUTS = {**base.DOMAIN_LAYOUTS, **odv.NO_CHAINID_LAYOUTS}


def rpc_json(url, method, params, timeout=40):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "User-Agent": "domaudit/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def pick_fork_url(chain):
    env = os.environ.get("FORK_URL_" + chain.upper())
    urls = ([env] if env else []) + list(base.RPCS[chain])
    for u in urls:
        try:
            n = int(rpc_json(u, "eth_blockNumber", [], 15)["result"], 16)
            return u, n - 3
        except Exception:
            continue
    sys.exit(f"no healthy RPC for {chain}")


class Fork:
    """One anvil process forking `chain` at a pinned block, reporting `chain_id`."""

    def __init__(self, chain, chain_id, port, url, block):
        self.url_local = f"http://127.0.0.1:{port}"
        self.log = open(f"anvil_{chain}_{port}.log", "w")
        self.proc = subprocess.Popen(
            ["anvil", "--fork-url", url, "--fork-block-number", str(block), "--chain-id", str(chain_id), "--port", str(port),
             "--silent", "--no-rate-limit", "--retries", "8", "--timeout", "45000"], stdout=self.log, stderr=self.log)
        for _ in range(120):
            time.sleep(0.5)
            try:
                got = int(rpc_json(self.url_local, "eth_chainId", [], 3)["result"], 16)
                if got == chain_id:
                    return
            except Exception:
                pass
        self.close()
        sys.exit(f"anvil did not start for {chain} (see {self.log.name})")

    def call(self, to, data):
        """eth_call on the fork; a revert is None, a transport or upstream error is retried with backoff, then RPC_FAIL."""
        for attempt in range(4):
            try:
                out = rpc_json(self.url_local, "eth_call", [{"to": to, "data": data}, "latest"], 60)
            except Exception:
                time.sleep(2 * (attempt + 1))
                continue
            if "result" in out:
                return out["result"]
            msg = json.dumps(out.get("error", ""))[:200].lower()
            if "revert" in msg or "execution" in msg:
                return None
            time.sleep(2 * (attempt + 1))        # upstream node throttled the fork: back off and retry
        return "RPC_FAIL"

    def close(self):
        try:
            self.proc.terminate()
            self.proc.wait(10)
        except Exception:
            self.proc.kill()


def verify_one(real, alt, chain, addr):
    ds_a = ds_b = getter = None
    saw_fail = False
    for sel, name in SELECTORS:
        a = real.call(addr, sel)
        if a == "RPC_FAIL":
            saw_fail = True
            continue
        if a and len(a) == 66 and int(a, 16) != 0:
            ds_a, getter = a, name
            ds_b = alt.call(addr, sel)
            break
    if ds_a is None:
        return {"verdict": "rpc_fail" if saw_fail else "ds_unavailable"}
    if ds_b == "RPC_FAIL":
        return {"verdict": "rpc_fail", "getter": getter}
    rec = {"getter": getter, "separator_real": ds_a, "separator_alt": ds_b}
    if ds_b != ds_a:
        rec["verdict"] = "R8_refuted_refreshes"
        return rec
    nm, vr = real.call(addr, "0x06fdde03"), real.call(addr, "0x54fd4d50")
    names = [base.decode_string(nm)] if nm and nm != "RPC_FAIL" else []
    names = [n for n in names if n is not None] or [""]
    versions = ([base.decode_string(vr)] if vr and vr != "RPC_FAIL" else [])
    versions = [v for v in versions if v is not None] + ["1", "2", "1.0", "v1"]
    data = {"onchain": bytes.fromhex(ds_a[2:]), "names": names, "versions": versions}
    with_c = odv.try_layouts(addr, data, base.DOMAIN_LAYOUTS, [REAL_ID[chain]])
    if with_c:
        rec.update(verdict="R8_confirmed_stale", layout=with_c["layout"])
        return rec
    without_c = odv.try_layouts(addr, data, odv.NO_CHAINID_LAYOUTS, [])
    if without_c:
        rec.update(verdict="R8_unchanged_no_chainid", layout=without_c["layout"])
        return rec
    rec["verdict"] = "R8_unchanged_unresolved"
    return rec


def summarize(path):
    rows = [json.loads(l) for l in open(path)]
    per = defaultdict(Counter)
    for r in rows:
        per[r["chain"]][r["verdict"]] += 1
    verdicts = ["R8_confirmed_stale", "R8_refuted_refreshes", "R8_unchanged_no_chainid", "R8_unchanged_unresolved",
                "ds_unavailable", "rpc_fail", "timeout", "error"]
    print("| Chain | Checked | " + " | ".join(v.replace("R8_", "") for v in verdicts) + " | Precision |")
    print("|---|---:|" + "---:|" * (len(verdicts) + 1))
    tot = Counter()
    for chain in sorted(per):
        c = per[chain]
        tot.update(c)
        dec = c["R8_confirmed_stale"] + c["R8_refuted_refreshes"]
        prec = f"{100 * c['R8_confirmed_stale'] / dec:.0f}%" if dec else "-"
        print(f"| {chain} | {sum(c.values())} | " + " | ".join(str(c[v]) for v in verdicts) + f" | {prec} |")
    dec = tot["R8_confirmed_stale"] + tot["R8_refuted_refreshes"]
    prec = f"{100 * tot['R8_confirmed_stale'] / dec:.0f}%" if dec else "-"
    print(f"| ALL | {sum(tot.values())} | " + " | ".join(str(tot[v]) for v in verdicts) + f" | {prec} |")
    print("\nPrecision = confirmed_stale / (confirmed_stale + refuted_refreshes), over contracts the fork test could decide.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default="results")
    ap.add_argument("--out", default="r8_verify.jsonl")
    ap.add_argument("--rule", default="R8", help="paper rule for domain freshness (R8)")
    ap.add_argument("--chains", default="")
    ap.add_argument("--sample", type=int, help="random sample size per chain (seeded)")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--limit", type=int)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--alt-chain-id", type=int, default=777777)
    ap.add_argument("--port", type=int, default=19000)
    ap.add_argument("--shard", default="", help="i/n: process only every n-th target, offset i (for parallel runs on different nodes)")
    ap.add_argument("--summarize", action="store_true")
    a = ap.parse_args()
    if a.summarize:
        return summarize(a.out)
    if not shutil.which("anvil"):
        sys.exit("anvil not found; install Foundry (https://getfoundry.sh)")
    base.load_env()
    targets = base.collect_targets(a.results, a.rule)
    chains = [c for c in (a.chains.split(",") if a.chains else sorted(REAL_ID)) if c]
    done = set()
    if os.path.exists(a.out):
        done = {(json.loads(l)["chain"], json.loads(l)["address"]) for l in open(a.out)}
    rng = random.Random(a.seed)
    lock, t0 = threading.Lock(), time.time()
    for ci, chain in enumerate(chains):
        mine = sorted(k for k in targets if k[0] == chain)
        if a.sample:
            mine = rng.sample(mine, min(a.sample, len(mine)))
        todo = [k for k in mine if k not in done][: a.limit]
        if a.shard:
            si, sn = (int(x) for x in a.shard.split("/"))
            todo = todo[si::sn]
        print(f"{chain}: {len(mine)} targets, {len(todo)} to do", flush=True)
        if not todo:
            continue
        url, block = pick_fork_url(chain)
        print(f"  forking {chain} at block {block} (real id {REAL_ID[chain]} vs alt id {a.alt_chain_id})", flush=True)
        real = Fork(chain, REAL_ID[chain], a.port + 2 * ci, url, block)
        alt = Fork(chain, a.alt_chain_id, a.port + 2 * ci + 1, url, block)
        n = [0]

        def work(k):
            try:
                rec = verify_one(real, alt, *k)
            except Exception as e:
                rec = {"verdict": "error", "note": repr(e)[:120]}
            rec.update(chain=k[0], address=k[1], block=block, **targets[k])
            with lock:
                with open(a.out, "a") as fh:
                    fh.write(json.dumps(rec) + "\n")
                n[0] += 1
                if n[0] % 50 == 0 or n[0] == len(todo):
                    print(f"  [{chain} {n[0]}/{len(todo)}] {time.time() - t0:.0f}s", flush=True)

        try:
            with ThreadPoolExecutor(a.threads) as ex:
                list(ex.map(work, todo))
        finally:
            real.close()
            alt.close()
    summarize(a.out)


if __name__ == "__main__":
    main()
