#!/usr/bin/env python3
"""Oracle-based recall check: sample contracts the analyzer did NOT flag and ask the on-chain oracles whether they violate.

For each sampled non-flagged contract with a readable domain separator we run
  * the R7 chain-id fork test (onchain_r8_verify.verify_one): unchanged separator bound to chainId -> missed R7;
                                                              unchanged separator with no chainId   -> missed R2;
  * a layout test without verifyingContract                                                           -> missed R5.
The share of such misses in the sample estimates the false-negative rate; no source code and no labels are needed.

Usage:  python3 onchain_recall_check.py --results <dir with out_*.json> --out recall_check.jsonl --per-chain 400
        python3 onchain_recall_check.py --summarize --out recall_check.jsonl --results <dir>
"""
import argparse
import glob
import json
import math
import os
import random
import re
import sys
import threading
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import onchain_r8_verify as m  # noqa: E402

base, odv = m.base, m.odv

NO_VERIFIER = {
    "name,version,chainId": ("EIP712Domain(string name,string version,uint256 chainId)", ("n", "v", "c")),
    "name,chainId": ("EIP712Domain(string name,uint256 chainId)", ("n", "c")),
}


def nonflagged(results_dir):
    out = defaultdict(list)
    for p in sorted(glob.glob(os.path.join(results_dir, "out_20*_*.json"))):
        year, chain = re.search(r"out_(\d+)_(\w+)\.json", p).groups()
        for r in json.load(open(p))["results"]:
            if r.get("status") == "ok" and not r.get("rules"):
                a = re.search(r"0x[0-9a-fA-F]{40}", r["file"])
                if a:
                    out[chain].append(a.group(0).lower())
    return {c: sorted(set(v)) for c, v in out.items()}


def check(real, alt, chain, addr):
    rec = m.verify_one(real, alt, chain, addr)
    rec["missed"] = []
    v = rec["verdict"]
    if v == "R8_confirmed_stale":
        rec["missed"].append("R8")
    elif v == "R8_unchanged_no_chainid":
        rec["missed"].append("R2")
    if "separator_real" in rec:
        ds = bytes.fromhex(rec["separator_real"][2:])
        nm, vr = real.call(addr, "0x06fdde03"), real.call(addr, "0x54fd4d50")
        names = [base.decode_string(nm)] if nm and nm != "RPC_FAIL" else []
        names = [n for n in names if n is not None] or [""]
        vers = ([base.decode_string(vr)] if vr and vr != "RPC_FAIL" else [])
        vers = [x for x in vers if x is not None] + ["1", "2", "1.0", "v1"]
        if odv.try_layouts(addr, {"onchain": ds, "names": names, "versions": vers}, NO_VERIFIER, [m.REAL_ID[chain]]):
            rec["missed"].append("R5")
    return rec


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0, c - h), min(1, c + h))


def summarize(path, results_dir):
    rows = [json.loads(l) for l in open(path)]
    pool = nonflagged(results_dir)
    pop = sum(len(v) for v in pool.values())
    readable = [r for r in rows if "separator_real" in r]
    print(f"sampled {len(rows)} non-flagged contracts of {pop:,}; readable separator: {len(readable)} ({100 * len(readable) / len(rows):.1f}%)")
    for rule in ("R8", "R2", "R5"):
        k = sum(1 for r in rows if rule in r["missed"])
        lo, hi = wilson(k, len(rows))
        print(f"  missed {rule}: {k}/{len(rows)}  rate {100 * k / len(rows):.2f}%  95% CI [{100 * lo:.2f}, {100 * hi:.2f}]  -> est. {k / len(rows) * pop:,.0f} contracts")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default="results")
    ap.add_argument("--out", default="recall_check.jsonl")
    ap.add_argument("--per-chain", type=int, default=400)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--threads", type=int, default=3)
    ap.add_argument("--port", type=int, default=19300)
    ap.add_argument("--summarize", action="store_true")
    a = ap.parse_args()
    if a.summarize:
        return summarize(a.out, a.results)
    pool = nonflagged(a.results)
    done = set()
    if os.path.exists(a.out):
        done = {(json.loads(l)["chain"], json.loads(l)["address"]) for l in open(a.out)}
    rng = random.Random(a.seed)
    lock = threading.Lock()
    t0 = time.time()
    for ci, chain in enumerate(["ethereum", "binance", "polygon", "avalanche"]):
        sample = rng.sample(pool[chain], min(a.per_chain, len(pool[chain])))
        todo = [x for x in sample if (chain, x) not in done]
        print(f"{chain}: sample {len(sample)}, to do {len(todo)} (non-flagged pool {len(pool[chain]):,})", flush=True)
        if not todo:
            continue
        url, block = m.pick_fork_url(chain)
        real = m.Fork(chain, m.REAL_ID[chain], a.port + 2 * ci, url, block)
        alt = m.Fork(chain, 777777, a.port + 2 * ci + 1, url, block)
        n = [0]

        def work(addr):
            try:
                rec = check(real, alt, chain, addr)
            except Exception as e:
                rec = {"verdict": "error", "missed": [], "note": repr(e)[:100]}
            rec.update(chain=chain, address=addr)
            with lock, open(a.out, "a") as fh:
                fh.write(json.dumps(rec) + "\n")
                n[0] += 1
                if n[0] % 50 == 0:
                    print(f"  [{chain} {n[0]}/{len(todo)}] {time.time() - t0:.0f}s", flush=True)

        try:
            with ThreadPoolExecutor(a.threads) as ex:
                list(ex.map(work, todo))
        finally:
            real.close()
            alt.close()
    summarize(a.out, a.results)


if __name__ == "__main__":
    main()
