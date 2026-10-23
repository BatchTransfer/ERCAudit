#!/usr/bin/env python3
"""Draw a fresh stratified precision sample from the FINAL analyzer output.

The earlier 200-file sample was drawn from an older analyzer and an older class taxonomy, so it cannot measure the final
analyzer. This script samples from the final out_*.json files: 40 flagged contracts per class (C1..C5), split evenly over
the rules of that class, one finding per contract, seeded and reproducible.

Writes
  <out>/manifest.csv     sample_id, class, rule (paper numbering), chain, address, server_path, manual_label, notes
  <out>/server_files.txt absolute server paths, one per line, for:
        rsync -avz --files-from=server_files.txt ashok@<server>:/ <out>/files/

Usage: python3 make_precision_sample.py --results <dir with out_*.json> --out data/ground_truth/domaudit/precision_sample_final
"""
import argparse
import csv
import glob
import json
import os
import random
import re
from collections import defaultdict

# analyzer label (old numbering used inside out_*.json) -> (paper rule, class)
PAPER = {"R1": ("R1", "C1"), "R2": ("R2", "C2"), "R3": ("R3", "C2"), "R4": ("R4", "C2"), "R5": ("R5", "C3"),
         "R6": ("R6", "C3"), "R7": ("R7", "C3"), "R8": ("R8", "C4"), "R9": ("R9", "C5")}
CLASS_RULES = {"C1": ["R1"], "C2": ["R2", "R3", "R4"], "C3": ["R5", "R6", "R7"], "C4": ["R8"], "C5": ["R9"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default="results")
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-class", type=int, default=40)
    ap.add_argument("--seed", type=int, default=2026)
    a = ap.parse_args()
    pools = defaultdict(dict)                     # paper rule -> {(chain, address): record}
    for p in sorted(glob.glob(os.path.join(a.results, "out_20*_*.json"))):
        year, chain = re.search(r"out_(\d+)_(\w+)\.json", p).groups()
        data = json.load(open(p))
        for r in data["results"]:
            m = re.search(r"0x[0-9a-fA-F]{40}", r["file"])
            if not m:
                continue
            for label in r.get("rules", []):
                rule = PAPER[label][0]
                pools[rule].setdefault((chain, m.group(0).lower()), {
                    "chain": chain, "year": year, "address": m.group(0).lower(),
                    "server_path": f'{data["corpus_dir"]}/{r["file"]}'})
    rng = random.Random(a.seed)
    rows, used = [], set()
    for cls, rules in CLASS_RULES.items():
        quota = {r: a.per_class // len(rules) for r in rules}
        for r in rules[: a.per_class - sum(quota.values())]:
            quota[r] += 1
        for rule in rules:
            cand = sorted(k for k in pools[rule] if k not in used)
            take = rng.sample(cand, min(quota[rule], len(cand)))
            for k in take:
                used.add(k)
                rows.append({"class": cls, "rule": rule, **pools[rule][k]})
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "manifest.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["sample_id", "class", "rule", "chain", "address", "server_path", "manual_label_TP_FP", "reason", "notes"])
        for i, r in enumerate(rows, 1):
            w.writerow([f"F{i:03d}", r["class"], r["rule"], r["chain"], r["address"], r["server_path"], "", "", ""])
    with open(os.path.join(a.out, "server_files.txt"), "w") as fh:
        fh.write("\n".join(r["server_path"] for r in rows) + "\n")
    cnt = defaultdict(int)
    for r in rows:
        cnt[r["rule"]] += 1
    print(len(rows), "samples", dict(cnt))


if __name__ == "__main__":
    main()
