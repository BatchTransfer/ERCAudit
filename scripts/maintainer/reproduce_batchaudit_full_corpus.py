#!/usr/bin/env python3
"""Reproduce the BatchAudit evaluation artifacts (Tables IV/V, agreement with stored results, runtime).

    python scripts/reproduce_batchaudit.py [--jobs 8] [--chains ethereum bsc polygon avalanche]
                                          [--no-ternary-resets-for ethereum] [--timing]

Outputs (``results/rerun/`` and ``results/tables/``):
  batchaudit_<chain>.json        fresh per-file results of *this* checkout
  table_iv_rerun.md              corpus size / analysable / flagged per chain
  table_v_rerun.md               per-class counts next to the paper's Table V
  agreement_with_stored.md       per-file agreement with results/paper/batchaudit/*.json
  runtime.json                   (with --timing) per-contract wall-clock distribution
"""
import argparse
import json
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ercaudit.batchaudit import analyzer, taxonomy  # noqa: E402

STORED = {c: ROOT / f"results/paper/batchaudit/erc1155_SafeBatch_{c}_assembly_delete.json"
          for c in ("ethereum", "bsc", "polygon", "avalanche")}


def flags(result):
    if "error" in result:
        return ("error",)
    return tuple(sorted(
        (k, v) for k, v in taxonomy.normalize_requirements(result["all_implementations"][0]["requirements"]).items()
        if k != "gas_family_errors")) + (len(result["all_implementations"]),)


def agreement(fresh, stored):
    by_name = {Path(r["file"]).name: r for r in stored}
    same = sum(1 for r in fresh if Path(r["file"]).name in by_name and flags(r) == flags(by_name[Path(r["file"]).name]))
    return same, len(fresh)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--chains", nargs="*", default=list(STORED))
    ap.add_argument("--no-ternary-resets-for", nargs="*", default=[],
                    help="chains to analyse with the Ethereum-era logic (see docs/AUDIT_REPORT.md F3)")
    ap.add_argument("--timing", action="store_true", help="also measure per-contract latency (sequential)")
    args = ap.parse_args()

    cfg = json.loads((ROOT / "data/corpora.json").read_text())
    paper = cfg["paper_reported"]
    out_dir, tab_dir = ROOT / "results/rerun", ROOT / "results/tables"
    out_dir.mkdir(parents=True, exist_ok=True)
    tab_dir.mkdir(parents=True, exist_ok=True)

    fresh, wall = {}, {}
    for chain in args.chains:
        corpus = ROOT / cfg["batchaudit"][chain]
        if not corpus.exists():
            print(f"[skip] {chain}: corpus not found at {corpus}")
            continue
        t0 = time.time()
        fresh[chain] = analyzer.analyze_directory(
            str(corpus), str(out_dir / f"batchaudit_{chain}.json"), jobs=args.jobs, timeout=120,
            ternary_resets=chain not in args.no_ternary_resets_for)
        wall[chain] = time.time() - t0
        print(f"[{chain}] {len(fresh[chain])} contracts in {wall[chain]:.1f}s")

    # ---- Table IV analogue ---------------------------------------------------
    lines = ["| Chain | Verified sources (paper: available code) | Analysable | Errors | Flagged contracts (unique) | Wall-clock |",
             "|---|---:|---:|---:|---:|---:|"]
    for chain, res in fresh.items():
        s = taxonomy.summarize(res)
        lines.append(f"| {chain} | {s['files']} ({paper['table_iv_available_code'][chain]}) | {s['analysed']} | "
                     f"{sum(s['errors'].values())} | {s['flagged_contracts']} | {wall[chain]:.1f} s |")
    tot = {k: sum(taxonomy.summarize(r)[k] for r in fresh.values()) for k in ("files", "analysed", "flagged_contracts")}
    lines.append(f"| **total** | {tot['files']} | {tot['analysed']} | {tot['files'] - tot['analysed']} | {tot['flagged_contracts']} | {sum(wall.values()):.1f} s |")
    (tab_dir / "table_iv_rerun.md").write_text("\n".join(lines) + "\n")
    print("\n" + "\n".join(lines))

    # ---- Table V analogue ----------------------------------------------------
    chains = list(fresh)
    head = "| Class | " + " | ".join(f"{c} (this run / paper)" for c in chains) + " |"
    rows = [head, "|---|" + "---:|" * len(chains)]
    per_chain = taxonomy.per_chain_table(fresh)
    for cls in taxonomy.CLASS_RULES:
        cells = [f"{per_chain[cls][c]} / {paper['table_v_findings'][cls][c]}" for c in chains]
        rows.append(f"| {taxonomy.CLASS_TITLES[cls]} | " + " | ".join(cells) + " |")
    rows.append("| Gas-related (manual in paper) | " + " | ".join(f"n/a / {paper['table_v_findings']['gas_related'][c]}" for c in chains) + " |")
    (tab_dir / "table_v_rerun.md").write_text("\n".join(rows) + "\n")
    print("\n" + "\n".join(rows))

    # ---- agreement with stored files --------------------------------------------
    ag = ["| Chain | contracts | identical requirement flags vs stored result file |", "|---|---:|---:|"]
    for chain, res in fresh.items():
        if STORED[chain].exists():
            same, n = agreement(res, json.loads(STORED[chain].read_text()))
            ag.append(f"| {chain} | {n} | {same} ({100 * same / n:.2f}%) |")
    (tab_dir / "agreement_with_stored.md").write_text("\n".join(ag) + "\n")
    print("\n" + "\n".join(ag))

    # ---- runtime -------------------------------------------------------------------
    if args.timing:
        times = []
        for chain in fresh:
            for f in analyzer.iter_solidity_files(str(ROOT / cfg["batchaudit"][chain])):
                code = Path(f).read_text(encoding="utf-8")
                t0 = time.perf_counter()
                try:
                    analyzer.analyze_source(code)
                except Exception:
                    pass
                times.append(time.perf_counter() - t0)
        times.sort()
        q = lambda p: times[min(len(times) - 1, int(p * len(times)))]
        rt = {"contracts": len(times), "total_s": round(sum(times), 2), "median_ms": round(1000 * statistics.median(times), 2),
              "p90_ms": round(1000 * q(0.90), 2), "p99_ms": round(1000 * q(0.99), 2), "max_ms": round(1000 * times[-1], 2)}
        (out_dir / "runtime.json").write_text(json.dumps(rt, indent=2))
        print("\nruntime:", rt)


if __name__ == "__main__":
    main()
