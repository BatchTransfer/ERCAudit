#!/usr/bin/env python3
"""Compare the verifier rules before and after a targeted re-run (files only_out_*.json next to out_*.json).
R6 = hardcoded verifier, R7 = externally supplied verifier."""
import glob, json, os
from collections import Counter
c = Counter()
for f in sorted(glob.glob("out_20*_*.json")):
    g = "only_" + f
    if not os.path.exists(g):
        continue
    prev = {r["file"]: set(r.get("rules", [])) for r in json.load(open(f))["results"]}
    for r in json.load(open(g))["results"]:
        o, n = prev.get(r["file"], set()), set(r.get("rules", []))
        c["files re-analyzed"] += 1
        c["R6 before"] += "R6" in o
        c["R6 after"] += "R6" in n
        c["R7 after"] += "R7" in n
        c["R6 dropped, no R7"] += ("R6" in o and "R6" not in n and "R7" not in n)
for k, v in c.items():
    print(f"  {k}: {v}")
