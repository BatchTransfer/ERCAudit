#!/usr/bin/env python3
"""On-chain verification of R1 (permit without a proper EIP-712 domain / EIP-191 framing) by simulating `permit`.

For every contract the analyzer flagged R1 that exposes an ERC-2612 `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)`:
  * make a THROWAWAY private key (the "owner"; never a real user's key), read nonces(owner) (0) and DOMAIN_SEPARATOR() if present;
  * sign the standard Permit struct under several digests and run `eth_call permit(...)` (read-only: nothing is sent or changed):
        proper   = keccak256(0x1901 || DOMAIN_SEPARATOR || structHash)          (only if a separator getter exists)
        flawed   = structHash | keccak256(structHash) | keccak256(0x1901 || structHash) | keccak256(DOMAIN_SEPARATOR || structHash)
  * control: a garbage signature must revert (otherwise the contract "accepts anything" and the result is discarded).
Verdicts: R1_confirmed (a flawed digest is accepted), R1_refuted (only the proper digest is accepted),
          inconclusive (every digest rejected: custom permit scheme, paused token, ...), no_standard_permit, accepts_anything, ...

Stdlib only; re-uses helpers from onchain_r31_verify.py / onchain_domain_verify.py (keep them together).
Usage:
    python3 onchain_r1_verify.py --selftest
    python3 onchain_r1_verify.py --results <dir with out_*.json> --out r1_verify.jsonl [--limit N]
    python3 onchain_r1_verify.py --summarize --out r1_verify.jsonl
"""
import argparse
import json
import os
import re
import sys
import threading
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import onchain_domain_verify as dv  # noqa: E402

base, keccak256, eth_call, EXPECTED = dv.base, dv.keccak256, dv.eth_call, dv.EXPECTED
from ercaudit.domaudit.analyzer import extract_balanced_block  # noqa: E402

# ---------------------------------------------------------------- secp256k1 (pure python, test key only)
P = 2 ** 256 - 2 ** 32 - 977
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)


def _add(p1, p2):
    if p1 is None: return p2
    if p2 is None: return p1
    (x1, y1), (x2, y2) = p1, p2
    if x1 == x2 and (y1 + y2) % P == 0: return None
    m = (3 * x1 * x1) * pow(2 * y1, -1, P) % P if p1 == p2 else (y2 - y1) * pow(x2 - x1, -1, P) % P
    x3 = (m * m - x1 - x2) % P
    return x3, (m * (x1 - x3) - y1) % P


def _mul(k, pt):
    r = None
    while k:
        if k & 1: r = _add(r, pt)
        pt = _add(pt, pt); k >>= 1
    return r


def address_of(priv):
    x, y = _mul(priv, G)
    return keccak256(x.to_bytes(32, "big") + y.to_bytes(32, "big"))[12:]


def sign(msg32, priv):
    z = int.from_bytes(msg32, "big")
    k = int.from_bytes(keccak256(priv.to_bytes(32, "big") + msg32), "big") % (N - 1) + 1
    rx, ry = _mul(k, G)
    r = rx % N
    s = pow(k, -1, N) * (z + r * priv) % N
    v = 27 + (ry & 1)
    if s > N // 2:                       # low-s normalisation flips the recovery parity
        s, v = N - s, (28 if v == 27 else 27)
    return v, r, s


def recover(msg32, v, r, s):
    z = int.from_bytes(msg32, "big")
    x = r
    y2 = (pow(x, 3, P) + 7) % P
    y = pow(y2, (P + 1) // 4, P)
    if (y & 1) != ((v - 27) & 1): y = P - y
    R = (x, y)
    rinv = pow(r, -1, N)
    q = _add(_mul(s * rinv % N, R), _mul((-z * rinv) % N, G))
    return keccak256(q[0].to_bytes(32, "big") + q[1].to_bytes(32, "big"))[12:]


def selftest():
    assert address_of(1).hex() == "7e5f4552091a69125d5dfcb7b8c2659029395bdf", "known vector (privkey 1) failed"
    priv = int.from_bytes(keccak256(b"domaudit-r1-test-key"), "big") % (N - 1) + 1
    seen_v = set()
    for i in range(40):
        msg = keccak256(b"message %d" % i)
        v, r, s = sign(msg, priv)
        assert v in (27, 28) and s <= N // 2, f"invalid v/s on message {i}: v={v}"
        assert recover(msg, v, r, s) == address_of(priv), f"sign/recover mismatch on message {i}"
        seen_v.add(v)
    assert seen_v == {27, 28}, f"both recovery ids should occur, saw {seen_v}"
    print("selftest ok: secp256k1 address vector + 40 sign/recover round trips (v in {27,28}, low-s, both parities seen)")


# ---------------------------------------------------------------- permit simulation
PERMIT_SEL = base.selector("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)")
PERMIT_TYPEHASH = keccak256(b"Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
TEST_PRIV = int.from_bytes(keccak256(b"domaudit-r1-test-key"), "big") % (N - 1) + 1
OWNER = address_of(TEST_PRIV)
SPENDER = bytes(12) + bytes.fromhex("00000000000000000000000000000000d0a0d0a0")[-20:]
W = lambda n: n.to_bytes(32, "big")
A32 = lambda b20: bytes(12) + b20
DEADLINE = 2 ** 64


def call_permit(chain, addr, v, r, s, owner=OWNER):
    data = "0x" + PERMIT_SEL + (A32(owner) + A32(bytes.fromhex("00" * 18 + "d0a0")) + W(1) + W(DEADLINE) + W(v) + W(r) + W(s)).hex()
    return eth_call(chain, addr, data)


def accepted(res):
    return res == "0x"                      # void function returned: no revert


def verify_r1(chain, addr):
    rec = {"chain": chain, "address": addr, "expected": EXPECTED[chain]}
    code, cname, abi_text = dv.fetch_source(chain, addr)
    if not abi_text or not abi_text.startswith("["):
        rec["verdict"] = "unverified"
        return rec
    abi = json.loads(abi_text)
    perm = [x for x in abi if x.get("type") == "function" and x.get("name") == "permit"]
    std = any([i["type"] for i in x.get("inputs", [])] == ["address", "address", "uint256", "uint256", "uint8", "bytes32", "bytes32"] for x in perm)
    has_ds = any(x.get("type") == "function" and x.get("name") in ("DOMAIN_SEPARATOR",) or (x.get("type") == "function" and dv.GETTER_RE.search(x.get("name", "")) and not x.get("inputs") and "type" not in x["name"].lower()) for x in abi)
    rec.update(contract=cname, has_permit_abi=bool(perm), standard_permit=std, has_separator_getter=has_ds)
    if not std:
        rec["verdict"] = "no_standard_permit"
        return rec
    codehex = dv.eth_rpc(chain, "eth_getCode", [addr, "latest"])
    if not codehex or codehex == "RPC_FAIL" or len(codehex) <= 2:
        rec["verdict"] = "no_code_or_rpc_fail"
        return rec
    # control: garbage signature must revert
    ctl = call_permit(chain, addr, 27, 1, 1)
    if ctl == "RPC_FAIL":
        rec["verdict"] = "rpc_fail"; return rec
    if accepted(ctl):
        # The garbage signature was accepted. If the permit body never verifies a signature, that is the strongest R1 case.
        text = dv.strip_comments(code) if dv.strip_comments else code
        body = ""
        for m in re.finditer(r"function\s+permit\s*\(", text):
            blk = extract_balanced_block(text, m.start())
            if "spender" in blk.split("{", 1)[0] and "{" in blk:
                body = blk; break
        if body and not re.search(r"ecrecover|ECDSA|recover\s*\(|isValidSignature|SignatureChecker|_verify|verify\s*\(|_hashTypedData|DOMAIN_SEPARATOR", body):
            rec.update(verdict="R1_confirmed_no_signature_check", flaw="permit never verifies the signature")
        else:
            rec["verdict"] = "accepts_anything"
        return rec
    nonce_raw = eth_call(chain, addr, "0x" + base.selector("nonces(address)") + A32(OWNER).hex())
    nonce = int(nonce_raw, 16) if nonce_raw and nonce_raw not in ("RPC_FAIL", "0x") else 0
    ds = None
    for g in ["DOMAIN_SEPARATOR"] + dv.alt_getters(abi_text):
        r = eth_call(chain, addr, "0x" + base.selector(g + "()"))
        if r and r != "RPC_FAIL" and len(r) == 66:
            ds = bytes.fromhex(r[2:]); rec["separator_getter"] = g; break
    struct = keccak256(PERMIT_TYPEHASH + A32(OWNER) + A32(bytes.fromhex("00" * 18 + "d0a0")) + W(1) + W(nonce) + W(DEADLINE))
    digests = []
    if ds is not None:
        digests.append(("proper", keccak256(b"\x19\x01" + ds + struct)))
    digests += [("flawed:struct-only", struct), ("flawed:hash(struct)", keccak256(struct)),
                ("flawed:1901+struct", keccak256(b"\x19\x01" + struct))]
    if ds is not None:
        digests.append(("flawed:no-1901 ds+struct", keccak256(ds + struct)))
    results = {}
    for label, dig in digests:
        v, r, s = sign(dig, TEST_PRIV)
        results[label] = accepted(call_permit(chain, addr, v, r, s))
    rec["accepted"] = [k for k, ok in results.items() if ok]
    flawed = [k for k in rec["accepted"] if k.startswith("flawed")]
    if flawed:
        rec["verdict"] = "R1_confirmed"; rec["flaw"] = flawed[0]
    elif results.get("proper"):
        rec["verdict"] = "R1_refuted"
    else:
        rec["verdict"] = "inconclusive"
    return rec


def summarize(path):
    rows = [json.loads(l) for l in open(path)]
    by = defaultdict(Counter)
    for r in rows:
        by[r["chain"]][r["verdict"]] += 1; by["ALL"][r["verdict"]] += 1
    cols = sorted({k for c in by.values() for k in c}, key=lambda k: (not k.startswith("R1_confirmed"), k != "R1_refuted", k))
    print("| Chain | Contracts | " + " | ".join(cols) + " |"); print("|---|---:|" + "---:|" * len(cols))
    for ch in ["ethereum", "binance", "polygon", "avalanche", "ALL"]:
        if ch in by:
            print(f"| {ch} | {sum(by[ch].values())} | " + " | ".join(str(by[ch][c]) for c in cols) + " |")
    print("\nflaw modes among confirmed:", dict(Counter(r.get("flaw") for r in rows if r["verdict"].startswith("R1_confirmed"))))
    print("separator getter present (all checked):", dict(Counter(r.get("has_separator_getter") for r in rows if "has_separator_getter" in r)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default="results")
    ap.add_argument("--out", default="r1_verify.jsonl")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--deadline", type=int, default=90)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--summarize", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.summarize:
        return summarize(a.out)
    selftest()
    base.load_env(); base.POOL = base.KeyPool()
    targets = base.collect_targets(a.results, "R1")
    print(f"R1: {len(targets)} unique flagged contracts", dict(Counter(c for c, _ in targets)))
    done = set()
    if os.path.exists(a.out):
        done = {(json.loads(l)["chain"], json.loads(l)["address"]) for l in open(a.out)}
    todo = [k for k in sorted(targets) if k not in done][: a.limit]
    print(f"{len(done)} already done, {len(todo)} to process")
    lock, n, t0 = threading.Lock(), [0], time.time()

    def work(k):
        dv.set_deadline(a.deadline)
        try:
            rec = verify_r1(*k)
        except dv.DeadlineExceeded:
            rec = {"chain": k[0], "address": k[1], "verdict": "timeout"}
        except Exception as e:
            rec = {"chain": k[0], "address": k[1], "verdict": "error", "note": repr(e)[:120]}
        rec.update(targets[k])
        with lock:
            with open(a.out, "a") as fh:
                fh.write(json.dumps(rec) + "\n")
            n[0] += 1
            if n[0] % 25 == 0 or n[0] == len(todo):
                print(f"  [{n[0]}/{len(todo)}] {time.time() - t0:.0f}s", flush=True)

    with ThreadPoolExecutor(a.threads) as ex:
        list(ex.map(work, todo))
    summarize(a.out)


if __name__ == "__main__":
    main()
