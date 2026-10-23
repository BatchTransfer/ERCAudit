#!/usr/bin/env python3
"""Reproduce the DomAudit artifacts that can be rebuilt from the shipped data.

1. Table II  -- adoption of signature standards, re-aggregated from results/paper/adoption/*.csv.
2. Samples   -- run the DomAudit analyzer on the 200-file precision sample, the 200-file recall
                sample and the 180-file category benchmark, and report rule/class distributions.
3. Labels    -- report whether the manual TP/FP labels behind paper Table V are present.

The 148,517-file verified-source corpus behind paper Tables III/IV is *not* part of this checkout;
``docs/AUDIT_REPORT.md`` (F6) lists what is needed to regenerate them.
"""
import csv
import json
import sys
from collections import Counter
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ercaudit.domaudit.analyzer import analyze_file  # noqa: E402
from ercaudit.domaudit.rules import paper_classes, paper_rules, summarize_paper_view  # noqa: E402

PAPER_TABLE_II = {  # paper Table II
    "ethereum": (65036, 61215, 46238, 21095, 7324),
    "polygon": (131583, 122699, 91780, 31953, 12876),
    "binance": (105025, 102341, 84029, 40857, 4720),
    "avalanche": (21289, 20361, 17289, 6197, 1725),
}


def table_ii():
    rows = ["| Chain | Contracts | EIP-712 | ERC-2612 | ERC-5267 | ERC-1271 | differs from paper |", "|---|---:|---:|---:|---:|---:|---|"]
    for chain, paper in PAPER_TABLE_II.items():
        df = pd.read_csv(ROOT / f"results/paper/adoption/{chain}_allium_yearly_trend_2020_2026.csv")
        got = tuple(int(df[c].sum()) for c in ("matched_contracts_with_timestamp", "EIP712_count", "EIP2612_count",
                                              "EIP5267_count", "EIP1271_count"))
        diff = ", ".join(f"{n}: {g} vs {p}" for n, g, p in zip(("contracts", "EIP-712", "ERC-2612", "ERC-5267", "ERC-1271"), got, paper) if g != p) or "-"
        rows.append(f"| {chain} | " + " | ".join(f"{g:,}" for g in got) + f" | {diff} |")
    return "\n".join(rows)


def run_dir(path, label):
    files = sorted(path.rglob("*.sol"))
    results = [analyze_file(f) for f in files]
    view = summarize_paper_view(results)
    print(f"\n[{label}] {len(files)} files -> candidates {view['replay_risk_candidates']} ({view['candidate_rate_pct']}%)")
    print("  rules  :", view["rule_observations"])
    print("  classes:", view["class_observations"])
    return files, results


def main():
    out = ROOT / "results/tables"
    out.mkdir(parents=True, exist_ok=True)
    md = table_ii()
    (out / "table_ii_adoption_rebuilt.md").write_text(md + "\n")
    print(md)

    gt = ROOT / "data/ground_truth/domaudit"
    _, precision_results = run_dir(gt / "precision_sample_200/files", "precision sample (200, stratified C1-C5)")
    run_dir(gt / "recall_sample_200/files", "recall sample (200, non-flagged permit/EIP-712 candidates)")
    run_dir(gt / "category_benchmark_180", "category benchmark (180, categories assigned by an earlier analyzer version)")

    manifest = list(csv.DictReader(open(gt / "precision_sample_200/manifest.csv")))
    labelled = sum(1 for r in manifest if r["manual_label_TP_FP_FN_TN"].strip())
    print(f"\nmanual labels present in precision manifest: {labelled}/{len(manifest)}"
          "  (paper Table V reports 164 TP / 36 FP; the per-sample labels are not in this checkout)")

    # The manifest numbers its classes like the *analyzer's* taxonomy (T4 = logical domain, T5 = freshness),
    # while the paper's Table I names them C4 = freshness, C5 = logical domain. Map accordingly (finding F7).
    manifest_to_paper = {"C1": "C1 Domain Separation", "C2": "C2 Chain Binding", "C3": "C3 Verifier Binding",
                         "C4": "C5 Logical Domain", "C5": "C4 Domain Freshness"}
    by_id = {Path(r["file"]).name: r for r in precision_results}
    supported, sampled = Counter(), Counter()
    for row in manifest:
        res = by_id.get(Path(row["copied_path"]).name)
        sampled[manifest_to_paper[row["class"]]] += 1
        if res and manifest_to_paper[row["class"]] in paper_classes(res):
            supported[manifest_to_paper[row["class"]]] += 1
    print("sampled findings still reproduced by this analyzer version (paper class naming):")
    for cls in sorted(sampled):
        print(f"  {cls}: {supported[cls]}/{sampled[cls]}")


if __name__ == "__main__":
    main()
