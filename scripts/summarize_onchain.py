#!/usr/bin/env python3
"""Rebuild the on-chain verification table (rules R1-R9, whole corpus) from the shipped verdict files.

R1-R3 and R5-R9 are recomputed from results/onchain/*.jsonl; R4 comes from results/onchain/r4_summary.json (its
per-contract records are not shipped). The last columns show the published values for comparison.
Usage: python scripts/summarize_onchain.py [--out results/tables/onchain_verification.md]
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ercaudit import onchain  # noqa: E402
from ercaudit.domaudit.rules import RULE_TITLES  # noqa: E402

FILES = {"R1": "r1_verify_v4", "R2": "r2_verify_v3", "R3": "r3_verify", "R5": "r5_verify", "R6": "r6_verify_v2",
         "R7": "r7_verify_v2", "R8": "r8_verify", "R9": "r9_verify_v3"}
# published (flagged, confirmed, not violated, unresolved) -- DomAudit study, on-chain verification table
PUBLISHED = {"R1": (51, 26, 11, 14), "R2": (116, 76, 0, 40), "R3": (522, 284, 8, 230), "R4": (1151, 29, 979, 143),
             "R5": (58, 15, 0, 43), "R6": (170, 6, 32, 132), "R7": (262, 72, 13, 177), "R8": (16881, 7438, 213, 9230),
             "R9": (75, 3, 0, 72)}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "results/tables/onchain_verification.md"))
    a = ap.parse_args()
    records = []
    for rule, stem in FILES.items():
        records += onchain.load_records(ROOT / "results/onchain" / f"{stem}.jsonl", rule)
    table = onchain.summarise(records)
    r4 = json.loads((ROOT / "results/onchain/r4_summary.json").read_text())["by_chain"]
    table["R4"] = {"flagged": sum(c["flagged"] for c in r4.values()), "confirmed": sum(c["wrong_id"] for c in r4.values()),
                   "refuted": sum(c["correct"] for c in r4.values()), "unresolved": sum(c["unresolved"] for c in r4.values()),
                   "precision_on_decided": None}
    lines = ["| Rule | Violation | Flagged | Confirmed | Not violated | Unresolved | Precision | Published (F/C/N/U) | Same |",
             "|---|---|---:|---:|---:|---:|---:|---|:-:|"]
    for rule in sorted(table):
        t = table[rule]
        got = (t["flagged"], t["confirmed"], t["refuted"], t["unresolved"])
        prec = "n/a" if t["precision_on_decided"] is None else f"{100 * t['precision_on_decided']:.0f}%"
        pub = PUBLISHED[rule]
        lines.append(f"| {rule} | {RULE_TITLES[rule]} | {got[0]:,} | {got[1]:,} | {got[2]:,} | {got[3]:,} | {prec} | "
                     f"{'/'.join(map(str, pub))} | {'yes' if got == pub else 'NO'} |")
    lines += ["", "R4: 'Confirmed' = wrong chain ID at deployment, 'Not violated' = correct chain ID. "
              "R7: 'Confirmed' = the live domain binds a verifier other than the contract itself."]
    text = "\n".join(lines)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
