"""Command-line interface: ``ercaudit <analyzer> <command> ...``.

    ercaudit batch analyze  PATH [-o out.json] [--jobs N] [--timeout S]
    ercaudit batch summarize RESULTS.json
    ercaudit batch evaluate --ground-truth GT.json --sources DIR [DIR ...] [--results RES.json]
    ercaudit tx    analyze  TXS.(csv|json) [-o out.csv]
    ercaudit tx    fetch    --results RES.json --chain ethereum -o raw.csv     (needs ETHERSCAN_API_KEY)
    ercaudit dom   analyze  PATH --output-json OUT.json --output-summary SUM.json
    ercaudit dom   summarize RESULTS.json
    ercaudit select BYTECODE_HEX_FILE
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import List, Optional

from . import __version__


# --------------------------------------------------------------------------
# batch
# --------------------------------------------------------------------------

def _print_file_report(result: dict) -> None:
    from .batchaudit.taxonomy import CLASS_TITLES, CLASS_SEVERITY, classify

    name = result.get("file", "<source>")
    if "error" in result:
        print(f"{name}\n  no verdict: {result['error']}")
        return
    for impl in result["all_implementations"]:
        req = impl["requirements"]
        failed = [k for k, v in req.items() if not v]
        classes = classify(req)
        verdict = "COMPLIANT" if impl["all_requirements_met"] else "NON-COMPLIANT"
        print(f"{name}\n  {impl['function']}() @ {impl['implementation_location']}: {verdict}")
        for flag, ok in req.items():
            print(f"    [{'ok' if ok else '!!'}] {flag}")
        for cls in classes:
            print(f"    -> {CLASS_TITLES[cls]} ({CLASS_SEVERITY[cls]})")
        if failed and not classes:
            print(f"    (unmet without a risk class: {', '.join(failed)})")


def _cmd_batch(args: argparse.Namespace) -> int:
    from .batchaudit import analyzer, evaluation, taxonomy

    if args.command == "analyze":
        target = Path(args.path)
        if target.is_file():
            res = analyzer._analyze_file((str(target), args.signature, args.include_leaf, args.timeout, not args.no_ternary_resets))
            _print_file_report(res)
            if args.output:
                analyzer.save_results([res], args.output)
            return 0 if res.get("all_implementations") and all(i["all_requirements_met"] for i in res["all_implementations"]) else 1

        def progress(i: int, n: int) -> None:
            if i % 500 == 0 or i == n:
                print(f"  {i}/{n}", file=sys.stderr)

        results = analyzer.analyze_directory(
            str(target), args.output, args.signature, jobs=args.jobs, timeout=args.timeout,
            include_leaf_functions=args.include_leaf, ternary_resets=not args.no_ternary_resets,
            limit=args.limit, progress=progress, file_list=args.file_list)
        print(json.dumps(taxonomy.summarize(results), indent=2))
        return 0

    if args.command == "summarize":
        with open(args.results, encoding="utf-8") as fh:
            print(json.dumps(taxonomy.summarize(json.load(fh)), indent=2))
        return 0

    if args.command == "evaluate":
        gt = evaluation.load_ground_truth(args.ground_truth)
        stored = evaluation.confusion(gt, evaluation.stored_verdicts(gt))
        tp, ann_fp, unann_fp = evaluation.split_flagged_by_annotation(gt)
        print(f"labelled contracts: {len(gt)}")
        print(f"stored labelling-time verdicts : {stored.as_dict()}")
        print(f"  flagged & confirmed (TP)={tp}, annotated FP={ann_fp}, flagged but not annotated as FP={unann_fp}")
        if args.sources:
            found = evaluation.locate_sources(gt, args.sources)
            print(f"sources located: {len(found)}/{len(gt)}")
            if args.results:
                with open(args.results, encoding="utf-8") as fh:
                    by_name = {Path(r["file"]).name: r for r in json.load(fh)}
                flags = {n: evaluation.tool_flags(by_name.get(Path(p).name)) for n, p in found.items()}
            else:
                flags = {}
                for n, p in found.items():
                    r = analyzer._analyze_file((p, args.signature, args.include_leaf, args.timeout, not args.no_ternary_resets))
                    flags[n] = evaluation.tool_flags(r)
            print(f"fresh re-run of this version    : {evaluation.confusion(gt, flags).as_dict()}")
        return 0
    return 2


# --------------------------------------------------------------------------
# tx
# --------------------------------------------------------------------------

def _cmd_tx(args: argparse.Namespace) -> int:
    import pandas as pd

    from .txaudit import patterns

    if args.command == "analyze":
        path = Path(args.input)
        txs = (pd.read_csv(path, low_memory=False).fillna({"functionName": ""}).to_dict("records")
               if path.suffix == ".csv" else json.loads(path.read_text()))
        df = patterns.analyse_transactions(txs, strict_authorization=args.strict)
        print(json.dumps(patterns.summarize_transactions(df), indent=2))
        if args.output:
            df.to_csv(args.output, index=False)
        return 0

    if args.command == "fetch":
        from .txaudit import etherscan

        key = etherscan.load_api_key()
        addresses = etherscan.addresses_from_batchaudit_json(args.results, args.limit)
        rows: List[dict] = []
        for addr in addresses:
            txs = etherscan.fetch_transactions(addr, key, chain=args.chain, start_block=args.start_block)
            for tx in txs:
                tx["contract_address"] = addr
            rows.extend(txs)
            print(f"  {addr}: {len(txs)} transactions", file=sys.stderr)
        pd.DataFrame(rows).to_csv(args.output, index=False)
        return 0
    return 2


# --------------------------------------------------------------------------
# dom
# --------------------------------------------------------------------------

def _cmd_dom(args: argparse.Namespace) -> int:
    from .domaudit import analyzer, rules

    if args.command == "analyze":
        analyzer.main(["--input-dir", args.path, "--output-json", args.output_json,
                       "--output-summary", args.output_summary] + (["--max-files", str(args.max_files)] if args.max_files else []))
        with open(args.output_json, encoding="utf-8") as fh:
            print("paper view:", json.dumps(rules.summarize_paper_view(json.load(fh)), indent=2))
        return 0
    if args.command == "summarize":
        with open(args.results, encoding="utf-8") as fh:
            print(json.dumps(rules.summarize_paper_view(json.load(fh)), indent=2))
        return 0
    return 2


def _cmd_run(args: argparse.Namespace) -> int:
    from . import pipeline

    return pipeline.main(["--size", str(args.size), "--jobs", str(args.jobs)] + (["--out", args.out] if args.out else []))


def _cmd_audit(args: argparse.Namespace) -> int:
    from . import pipeline

    return pipeline.audit(args.path, as_json=args.json)


def _cmd_select(args: argparse.Namespace) -> int:
    from .spec import selectors

    code = Path(args.bytecode).read_text().strip()
    print(json.dumps({"features": selectors.identify(code, strict=args.strict),
                      "batch_candidate": selectors.is_batch_candidate(code, strict=args.strict)}))
    return 0


# --------------------------------------------------------------------------
# parser
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    from .solidity import SAFE_BATCH_TRANSFER_SIG

    p = argparse.ArgumentParser(prog="ercaudit", description="Specification-guided auditing of ERC implementations.")
    p.add_argument("--version", action="version", version=f"ercaudit {__version__}")
    top = p.add_subparsers(dest="tool", required=True)

    # batch
    b = top.add_parser("batch", help="batch-transfer rules: ERC-1155 safeBatchTransferFrom constraints")
    bs = b.add_subparsers(dest="command", required=True)
    a = bs.add_parser("analyze", help="analyse a .sol file or a directory of them")
    a.add_argument("path")
    a.add_argument("-o", "--output")
    a.add_argument("--jobs", type=int, default=1)
    a.add_argument("--timeout", type=float, default=None, help="per-file timeout in seconds")
    a.add_argument("--limit", type=int, default=None)
    a.add_argument("--file-list", help="text file with one .sol path per line (PATH is then ignored)")
    a.add_argument("--include-leaf", action="store_true",
                   help="also analyse safeBatchTransferFrom bodies that call no other function "
                        "(default reproduces the published runs, which report those as errors)")
    a.add_argument("--no-ternary-resets", action="store_true",
                   help="reproduce the stored Ethereum results (see docs/AUDIT_REPORT.md, F3)")
    a.add_argument("--signature", default=SAFE_BATCH_TRANSFER_SIG)
    s = bs.add_parser("summarize")
    s.add_argument("results")
    e = bs.add_parser("evaluate", help="precision/recall against a manually labelled ground truth")
    e.add_argument("--ground-truth", required=True)
    e.add_argument("--sources", nargs="*")
    e.add_argument("--results", help="re-use a results JSON instead of re-analysing")
    e.add_argument("--signature", default=SAFE_BATCH_TRANSFER_SIG)
    e.add_argument("--include-leaf", action="store_true")
    e.add_argument("--no-ternary-resets", action="store_true")
    e.add_argument("--timeout", type=float, default=None)
    b.set_defaults(func=_cmd_batch)

    # tx
    t = top.add_parser("tx", help="on-chain transaction validation")
    ts = t.add_subparsers(dest="command", required=True)
    ta = ts.add_parser("analyze", help="flag zero-address / length-mismatch / unauthorised calls and approval chains")
    ta.add_argument("input")
    ta.add_argument("-o", "--output")
    ta.add_argument("--strict", action="store_true", help="strict authorisation (owner==from, ordered)")
    tf = ts.add_parser("fetch", help="download transactions of flagged contracts (needs ETHERSCAN_API_KEY)")
    tf.add_argument("--results", required=True)
    tf.add_argument("--chain", default="ethereum")
    tf.add_argument("--start-block", type=int, default=0)
    tf.add_argument("--limit", type=int, default=None)
    tf.add_argument("-o", "--output", required=True)
    t.set_defaults(func=_cmd_tx)

    # dom
    d = top.add_parser("dom", help="signing-domain rules R1-R9: EIP-712 / ERC-2612 domain construction")
    ds = d.add_subparsers(dest="command", required=True)
    da = ds.add_parser("analyze")
    da.add_argument("path")
    da.add_argument("--output-json", required=True)
    da.add_argument("--output-summary", required=True)
    da.add_argument("--max-files", type=int, default=None)
    dsum = ds.add_parser("summarize")
    dsum.add_argument("results")
    d.set_defaults(func=_cmd_dom)

    au = top.add_parser("audit", help="audit a .sol file or directory with every applicable rule set (exit 1 if findings)")
    au.add_argument("path")
    au.add_argument("--json", action="store_true")
    au.set_defaults(func=_cmd_audit)

    run = top.add_parser("run", help="unified run: batch + tx + domain rules and on-chain verdicts on the shipped sample")
    run.add_argument("--size", type=int, choices=(100, 200), default=100)
    run.add_argument("--jobs", type=int, default=4)
    run.add_argument("--out", default=None)
    run.set_defaults(func=_cmd_run)

    sel = top.add_parser("select", help="Phase 1: identify features from runtime bytecode (hex file)")
    sel.add_argument("bytecode")
    sel.add_argument("--strict", action="store_true")
    sel.set_defaults(func=_cmd_select)
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
