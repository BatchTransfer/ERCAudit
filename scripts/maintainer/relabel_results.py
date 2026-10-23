#!/usr/bin/env python3
"""Convert out_*.json files to the paper's R1..R9 numbering, in place.

Accepts the historical analyzer labels and the interim R1..R10 scheme.
historical -> paper: R1 R2 R3 | R3.1->R4 | R4->R5 | R5->R6 (R5.1->R7) | R6->R8 | R7 dropped | R8->R9
interim R1..R10 -> paper: R9 (missing logical disambiguator) dropped, R10 (salt) -> R9
Idempotent: files already tagged "label_scheme": "R1-R9" are skipped.
Usage: python3 relabel_results.py out_20*_*.json
"""
import json
import sys

HISTORICAL = {"R1": "R1", "R2": "R2", "R3": "R3", "R3.1": "R4", "R4": "R5", "R5": "R6", "R5.1": "R7",
              "R6": "R8", "R7": None, "R8": "R9"}
INTERIM = {"R1": "R1", "R2": "R2", "R3": "R3", "R4": "R4", "R5": "R5", "R6": "R6", "R7": "R7",
           "R8": "R8", "R9": None, "R10": "R9"}
ORDER = [f"R{i}" for i in range(1, 10)]


def main(paths):
    for p in paths:
        d = json.load(open(p))
        scheme = d.get("label_scheme")
        if scheme == "R1-R9":
            print("skip (already R1-R9):", p)
            continue
        mapping = INTERIM if scheme == "R1-R10" else HISTORICAL
        for r in d["results"]:
            r["rules"] = sorted({mapping[x] for x in r.get("rules", []) if mapping[x]}, key=ORDER.index)
            r["risk_category"] = [c for c in r.get("risk_category", []) if c != "missing_logical_domain_disambiguator"]
        obs = {k: 0 for k in ORDER}
        for r in d["results"]:
            for x in r["rules"]:
                obs[x] += 1
        d.setdefault("summary", {})["rule_observations"] = obs
        d["label_scheme"] = "R1-R9"
        json.dump(d, open(p, "w"), indent=2)
        print("relabelled:", p)


if __name__ == "__main__":
    main(sys.argv[1:])
