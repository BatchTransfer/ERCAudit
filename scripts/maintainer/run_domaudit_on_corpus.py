#!/usr/bin/env python3
"""Run the DomAudit analyzer (ercaudit/domaudit) over an arbitrary directory of .sol files
and write a JSON report plus a paper-vocabulary summary (rule/class observation counts).

Self-contained: only needs ercaudit/domaudit/{analyzer.py,rules.py} and their empty
__init__.py's (no pandas, no other ercaudit subpackages) -- see "Deploying to a server"
below for what to copy.

Usage:
    python3 scripts/run_domaudit_on_corpus.py <corpus_dir> <output.json> [max_files]

Example (one chain/year on the research server):
    python3 scripts/run_domaudit_on_corpus.py \
        ~/ashokTests/smart-contract-data-source/etherscan_verified_sources/ethereum/verified_sources/2026 \
        results/domaudit_2026_ethereum.json

Deploying to a server that only has the raw verified-source corpus (not this whole repo):
    rsync -av ercaudit/domaudit/ ercaudit/__init__.py scripts/run_domaudit_on_corpus.py \
        user@server:~/domaudit_run/
    # then on the server, from ~/domaudit_run, with ercaudit/__init__.py and
    # ercaudit/domaudit/{__init__.py,analyzer.py,rules.py} in place:
    python3 run_domaudit_on_corpus.py <corpus_dir> out.json
    # copy the result back:
    rsync -av user@server:~/domaudit_run/out.json results/
"""
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ercaudit.domaudit.analyzer import analyze_file  # noqa: E402
from ercaudit.domaudit.rules import paper_rules, paper_classes, summarize_paper_view  # noqa: E402


# paper rule -> label stored in out_*.json
PAPER_TO_LABEL = {f"R{i}": f"R{i}" for i in range(1, 10)}   # result files use the paper numbering R1..R9


def main():
    import argparse
    ap = argparse.ArgumentParser(description="Run DomAudit over a directory of .sol files.")
    ap.add_argument("corpus_dir")
    ap.add_argument("output")
    ap.add_argument("max_files", nargs="?", type=int, default=None)
    ap.add_argument("--only", default="", help="comma list of paper rules (e.g. R6); re-analyze only files that the "
                    "previous run flagged with one of them (needs --prev)")
    ap.add_argument("--prev", default="", help="previous out_*.json for the same corpus_dir, used by --only")
    ap.add_argument("--merge", action="store_true", help="with --only/--prev: write the full previous result with the re-analyzed files replaced")
    args = ap.parse_args()

    corpus_dir = Path(args.corpus_dir)
    out_path = Path(args.output)
    limit = args.max_files

    files = sorted(corpus_dir.rglob("*.sol"))
    if args.only:
        if not args.prev:
            sys.exit("--only needs --prev <previous out_*.json for this corpus_dir>")
        want = {PAPER_TO_LABEL.get(x.strip(), x.strip()) for x in args.only.split(",") if x.strip()}
        prev = json.load(open(args.prev))["results"]
        keep = {r["file"] for r in prev if want & set(r.get("rules", []))}
        files = [f for f in files if str(f.relative_to(corpus_dir)) in keep]
        print(f"--only {args.only} (labels {sorted(want)}): {len(files)} files flagged in {args.prev}")
    if limit:
        files = files[:limit]
    print(f"Found {len(files)} .sol files under {corpus_dir}")

    results = []
    t0 = time.time()
    for i, f in enumerate(files, 1):
        r = analyze_file(f)
        rules = paper_rules(r) if r.get("status") == "ok" else []
        results.append({
            "file": str(f.relative_to(corpus_dir)),
            "status": r.get("status"),
            "rules": rules,
            "risk_category": r.get("risk_category", []),
        })
        if i % 500 == 0 or i == len(files):
            print(f"  [{i}/{len(files)}] {time.time() - t0:.1f}s elapsed", flush=True)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    n_files = len(files)
    if args.merge:
        if not (args.only and args.prev):
            sys.exit("--merge needs --only and --prev")
        prev_payload = json.load(open(args.prev))
        replaced = {r["file"]: r for r in results}
        results = [replaced.get(r["file"], r) for r in prev_payload["results"]]
        n_files = prev_payload.get("files", len(results))
        print(f"merged {len(replaced)} re-analyzed files into {len(results)} previous results")
    view = summarize_paper_view(
        {"risk_category": r["risk_category"], "status": r["status"]} for r in results
    )
    payload = {
        "corpus_dir": str(corpus_dir),
        "files": n_files,
        "elapsed_s": time.time() - t0,
        "label_scheme": "R1-R9",
        "summary": view,
        "results": results,
    }
    tmp = out_path.with_suffix(out_path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2))
    tmp.replace(out_path)

    print(f"\nDone in {payload['elapsed_s']:.1f}s -> {out_path}")
    print(f"candidates: {view['replay_risk_candidates']}/{view['analysed_files']} "
          f"({view['candidate_rate_pct']}%)")
    print("rules  :", view["rule_observations"])
    print("classes:", view["class_observations"])


if __name__ == "__main__":
    main()
