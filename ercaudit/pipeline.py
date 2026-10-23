#!/usr/bin/env python3
"""ERCAudit unified pipeline (``ercaudit run``, or ``python combine_run.py``): one command, one report.

Runs the three analysis modules of ERCAudit on the shipped demonstration sample and merges their output:

  BatchAudit  static constraint checks on ERC-1155 ``safeBatchTransferFrom`` (risk classes, severity)
  TxAudit     calldata-level validation of batch-transfer transactions (zero address, length mismatch,
              unauthorised caller, secondary-approval chains)
  DomAudit    EIP-712 / ERC-2612 signing-domain rules R1-R9 in five authority boundaries (C1-C5)
  on-chain    stored on-chain verdicts (confirmed / refuted / unresolved) attached to the DomAudit findings

Usage:  python combine_run.py --size 100          # 100 ERC-1155 + 100 permit sources + 100 transactions
        python combine_run.py --size 200 --jobs 8
Outputs (results/run_<size>/): findings.csv (one row per finding, all modules), report.json, report.md,
batchaudit.json, domaudit.json, txaudit.csv. No network access is needed.
"""
from __future__ import annotations

import argparse
import json
import platform
import sys
import time
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import pandas as pd

from . import onchain
from .batchaudit import evaluation as bev
from .batchaudit.analyzer import analyze_source
from .batchaudit.taxonomy import CLASS_RULES, CLASS_SEVERITY, CLASS_TITLES, classify
from .domaudit.analyzer import analyze_file
from .domaudit.rules import CATEGORY_TO_PAPER, PAPER_RULES, RULE_TITLES, paper_classes, paper_rules
from .txaudit.patterns import analyse_transactions, summarize_transactions

ROOT = Path(__file__).resolve().parents[1]

SAMPLE = ROOT / "data" / "sample"
FINDING_COLUMNS = ["module", "subject", "address", "rule", "class", "severity", "evidence", "onchain", "manual"]


# ----------------------------------------------------------------------------- workers (top level: picklable)
def _batch_one(path: str) -> dict:
    t0 = time.perf_counter()
    res = analyze_source(Path(path).read_text(errors="ignore"))
    res["file"] = Path(path).name
    res["ms"] = round((time.perf_counter() - t0) * 1000, 2)
    return res


def _dom_one(path: str) -> dict:
    t0 = time.perf_counter()
    res = analyze_file(Path(path))
    res["file"] = Path(path).name
    res["ms"] = round((time.perf_counter() - t0) * 1000, 2)
    return res


def _pmap(fn, items, jobs):
    if jobs <= 1:
        return [fn(i) for i in items]
    with ProcessPoolExecutor(max_workers=jobs) as ex:
        return list(ex.map(fn, items, chunksize=8))


# ----------------------------------------------------------------------------- modules
def run_batch(size: int, jobs: int):
    man = pd.read_csv(SAMPLE / "manifest_batch.csv").head(size)
    results = _pmap(_batch_one, [str(SAMPLE / "batch" / f) for f in man["file"]], jobs)
    rows, flags = [], {}
    for (_, m), res in zip(man.iterrows(), results):
        flagged = bev.tool_flags(res)
        flags[m["file"]] = flagged
        if "error" in res:
            continue
        for impl in res["all_implementations"]:
            req = impl["requirements"]
            for cls in classify(req):
                failed = [f for f in CLASS_RULES[cls] if not bev.normalize_requirements(req).get(f, True)]
                rows.append({"module": "batch", "subject": m["file"], "address": m["address"],
                             "rule": "+".join(failed), "class": CLASS_TITLES[cls], "severity": CLASS_SEVERITY[cls],
                             "evidence": f"safeBatchTransferFrom lines {impl.get('line_start')}-{impl.get('line_end')}: "
                                         f"{', '.join(failed)} not satisfied",
                             "onchain": "", "manual": ""})
    labelled = {m["file"]: {bev.LABEL_KEY: bool(m["manual_compliant"])}
                for _, m in man.iterrows() if str(m["manual_compliant"]) in ("True", "False", "true", "false", True, False)}
    conf = bev.confusion(labelled, flags)
    summary = {
        "files": len(man), "analysable": sum("error" not in r for r in results),
        "flagged_contracts": sum(flags.values()),
        "errors": dict(Counter(r["error"][:60] for r in results if "error" in r)),
        "class_observations": dict(Counter(r["class"] for r in rows if r["class"])),
        "labelled": len(labelled), "confusion": conf.as_dict(),
    }
    # distinct contracts per class (a contract may violate several flags of one class)
    per_class = defaultdict(set)
    for r in rows:
        per_class[r["class"]].add(r["subject"])
    summary["class_contracts"] = {c: len(v) for c, v in per_class.items()}
    return results, rows, summary, {m["address"].lower() for _, m in man.iterrows() if flags[m["file"]]}


def run_tx(size: int, flagged_addresses: set):
    raw = pd.read_csv(SAMPLE / "tx_sample.csv", low_memory=False).head(size)
    df = analyse_transactions(raw.drop(columns=["rank"]).to_dict("records"))
    stored = pd.read_csv(SAMPLE / "tx_sample_stored_analysis.csv", low_memory=False).set_index("hash")
    parity = {}
    for col in ("unauthorized", "zero_address", "length_mismatch"):
        cur = df.set_index("hash")[col].astype(bool)
        parity[col] = bool((cur == stored.loc[cur.index, col].astype(bool)).all())
    rows = []
    for _, t in df.iterrows():
        addr = str(t["contract_address"]).lower()
        for pat, sev in (("unauthorized", "Critical"), ("zero_address", "High"), ("length_mismatch", "High")):
            if bool(t[pat]):
                rows.append({"module": "tx", "subject": t["hash"], "address": addr, "rule": pat,
                             "class": "on-chain pattern", "severity": sev,
                             "evidence": f"caller {t['from']} -> from {t['decoded_from']} (block {t['blockNumber']})",
                             "onchain": "", "manual": ""})
        if bool(t["operator_provides_further_approvals"]):
            rows.append({"module": "tx", "subject": t["hash"], "address": addr, "rule": "secondary_approval",
                         "class": "on-chain pattern", "severity": "Medium",
                         "evidence": f"approval chain depth {t.get('approval_chain_depth')}, "
                                     f"{t.get('total_chain_approvals')} further approvals",
                         "onchain": "", "manual": ""})
    summary = summarize_transactions(df)
    summary.update(contracts=int(df["contract_address"].nunique()), parity_with_stored_analysis=parity,
                   transactions_to_statically_flagged_contracts=int(
                       df["contract_address"].str.lower().isin(flagged_addresses).sum()))
    return df, rows, summary


def run_dom(size: int, jobs: int):
    man = pd.read_csv(SAMPLE / "manifest_dom.csv").fillna("").head(size)
    results = _pmap(_dom_one, [str(SAMPLE / "dom" / f) for f in man["file"]], jobs)
    chain_records = [r for r in onchain.load_records(SAMPLE / "onchain_dom_sample.jsonl")]
    best = onchain.best_per_contract(chain_records)
    by_file_rule = {(d.get("file"), d["rule"]): d for (_r, _c, _a), d in best.items()}
    rows, obs = [], Counter()
    flagged_files, class_hit = 0, {}
    for (_, m), res in zip(man.iterrows(), results):
        rules = paper_rules(res)
        flagged_files += bool(rules)
        class_hit[m["file"]] = set(paper_classes(res))
        for rule in rules:
            obs[rule] += 1
            cls = next(v[1] for v in CATEGORY_TO_PAPER.values() if v[0] == rule)
            ev = by_file_rule.get((m["file"], rule))
            rows.append({"module": "domain", "subject": m["file"], "address": m["address"], "rule": rule,
                         "class": cls, "severity": res.get("risk_level", ""),
                         "evidence": RULE_TITLES[rule] + "; " + "; ".join(
                             c for c in res.get("risk_category", []) if CATEGORY_TO_PAPER.get(c, ("",))[0] == rule),
                         "onchain": ev["outcome"] if ev else "not probed",
                         "manual": m["manual_label"] if m["manual_rule"] == rule else ""})
    # manual precision (paper method): among labelled contracts still flagged in the labelled class
    per_class = defaultdict(lambda: [0, 0])
    for _, m in man.iterrows():
        if m["manual_label"] and any(c.startswith(m["class"]) for c in class_hit[m["file"]]):
            per_class[m["class"]][1] += 1
            per_class[m["class"]][0] += m["manual_label"] == "TP"
    tp = sum(v[0] for v in per_class.values())
    flagged_lab = sum(v[1] for v in per_class.values())
    # on-chain verdicts attached to the findings of this run (rule x outcome)
    chain_by_rule = {r: Counter() for r in PAPER_RULES}
    for row in rows:
        chain_by_rule[row["rule"]][row["onchain"]] += 1
    summary = {
        "files": len(man), "flagged_contracts": flagged_files, "rule_observations": {r: obs.get(r, 0) for r in PAPER_RULES},
        "labelled": int((man["manual_label"] != "").sum()), "labelled_still_flagged": flagged_lab, "true_positives": tp,
        "precision": round(tp / flagged_lab, 4) if flagged_lab else None,
        "precision_by_class": {c: {"tp": v[0], "flagged": v[1]} for c, v in sorted(per_class.items())},
        "onchain_on_findings": {r: dict(c) for r, c in chain_by_rule.items()},
    }
    return results, rows, summary


# ----------------------------------------------------------------------------- report
def markdown(rep: dict) -> str:
    b, t, d = rep["batchaudit"], rep["txaudit"], rep["domaudit"]
    L = [f"# ERCAudit combined run (sample {rep['size']})", "",
         f"{rep['size']} ERC-1155 sources, {rep['size']} permit sources, {t['transactions']} transactions.", "",
         "## Batch transfers (ERC-1155 `safeBatchTransferFrom`)", "",
         f"{b['analysable']}/{b['files']} analysable, {b['flagged_contracts']} contracts violate at least one of the eight constraints.",
         "", "| Risk class | Severity | Contracts |", "|---|---|---:|"]
    for cls, title in CLASS_TITLES.items():
        if cls == "gas_related":
            continue
        L.append(f"| {title} | {CLASS_SEVERITY[cls]} | {b['class_contracts'].get(title, 0)} |")
    c = b["confusion"]
    L += ["", f"Against the {b['labelled']} manually labelled contracts of the sample: TP {c['tp']}, FP {c['fp']}, FN {c['fn']}, "
          f"TN {c['tn']} (precision {c['precision']:.3f}, recall {c['recall']:.3f}).", "",
          "## On-chain transactions (calldata of the batch transfers)", "",
          f"{t['safeBatchTransferFrom']} `safeBatchTransferFrom` and {t['setApprovalForAll']} `setApprovalForAll` transactions "
          f"of {t['contracts']} contracts: {t['unauthorized']} unauthorised, {t['zero_address']} zero-address, "
          f"{t['length_mismatch']} length-mismatch (the shipped transactions contain no `setApprovalForAll`, so approval chains are not exercised here). "
          f"Derived columns identical to the stored analysis: {all(t['parity_with_stored_analysis'].values())}.", "",
          "## Signing domains (rules R1-R9)", "",
          f"{d['flagged_contracts']}/{d['files']} contracts violate at least one rule.", "",
          "| Rule | Violation | Obs. | On-chain confirmed | refuted | unresolved | not probed |", "|---|---|---:|---:|---:|---:|---:|"]
    for r in PAPER_RULES:
        oc = d["onchain_on_findings"].get(r, {})
        L.append(f"| {r} | {RULE_TITLES[r]} | {d['rule_observations'][r]} | {oc.get('confirmed', 0)} | "
                 f"{oc.get('refuted', 0)} | {oc.get('unresolved', 0)} | {oc.get('not probed', 0)} |")
    L += ["", f"Manual precision (class level, labelled contracts that are still flagged): "
          f"{d['true_positives']}/{d['labelled_still_flagged']}"
          + (f" = {d['precision']:.3f}" if d["precision"] is not None else "") + ". On-chain columns are the stored "
          "verdicts joined to this run's findings ('not probed': no record in the artifact, e.g. R4).", ""]
    return "\n".join(L)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--size", type=int, choices=(100, 200), default=100)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--out", default=None)
    a = ap.parse_args(argv)
    out = Path(a.out) if a.out else ROOT / "results" / f"run_{a.size}"
    out.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()

    b_res, b_rows, b_sum, flagged_addr = run_batch(a.size, a.jobs)
    tx_df, t_rows, t_sum = run_tx(a.size, flagged_addr)
    d_res, d_rows, d_sum = run_dom(a.size, a.jobs)
    # static -> dynamic link: attach the transaction evidence of the sample to each flagged ERC-1155 contract
    per_addr = tx_df.assign(addr=tx_df["contract_address"].str.lower()).groupby("addr")["unauthorized"].agg(["size", "sum"])
    for row in b_rows:
        if row["address"].lower() in per_addr.index:
            n, bad = per_addr.loc[row["address"].lower()]
            row["onchain"] = f"{int(n)} txs replayed, {int(bad)} unauthorized"
        else:
            row["onchain"] = "not probed"

    rep = {"size": a.size, "batchaudit": b_sum, "txaudit": t_sum, "domaudit": d_sum}
    info = {"seconds": round(time.perf_counter() - t0, 2),
            "host": f"{platform.system()} {platform.machine()}, Python {platform.python_version()}",
            "ms_per_contract_median": {
                "batchaudit": float(pd.Series([r["ms"] for r in b_res]).median()),
                "domaudit": float(pd.Series([r["ms"] for r in d_res]).median())}}
    (out / "run_info.json").write_text(json.dumps(info, indent=2))
    pd.DataFrame(b_rows + t_rows + d_rows, columns=FINDING_COLUMNS).to_csv(out / "findings.csv", index=False)
    (out / "batchaudit.json").write_text(json.dumps(b_res, indent=1))
    (out / "domaudit.json").write_text(json.dumps(d_res, indent=1, default=str))
    tx_df.to_csv(out / "txaudit.csv", index=False)
    (out / "report.json").write_text(json.dumps(rep, indent=2, default=str))
    md = markdown(rep)
    (out / "report.md").write_text(md)
    print(md)
    print(f"\n{info['seconds']} s on {info['host']}")
    print(f"findings: {len(b_rows)} batch, {len(t_rows)} tx, {len(d_rows)} domain  ->  {out}/")
    return 0


def audit(path: str, as_json: bool = False) -> int:
    """Audit one ``.sol`` file or a directory with every module that applies; exit status 1 if anything is found.

    BatchAudit applies to sources with an ERC-1155 ``safeBatchTransferFrom``, DomAudit to sources with a typed-data
    domain or ``permit``. Findings carry the rule ids and risk classes of the studies.
    """
    target = Path(path)
    files = [target] if target.is_file() else sorted(target.rglob("*.sol"))
    report, found = [], 0
    for f in files:
        code = f.read_text(errors="ignore")
        entry = {"file": str(f), "findings": []}
        if "safeBatchTransferFrom" in code:
            res = analyze_source(code)
            for impl in res.get("all_implementations", []):
                req = bev.normalize_requirements(impl["requirements"])
                for cls in classify(req):
                    failed = [x for x in CLASS_RULES[cls] if not req.get(x, True)]
                    entry["findings"].append({
                        "module": "batch", "severity": CLASS_SEVERITY[cls], "risk": CLASS_TITLES[cls],
                        "constraint": "+".join(failed), "lines": f"{impl.get('line_start')}-{impl.get('line_end')}"})
        dom = analyze_file(f)
        for rule in paper_rules(dom):
            entry["findings"].append({
                "module": "domain", "severity": dom.get("risk_level", ""), "rule": rule,
                "class": next(v[1] for v in CATEGORY_TO_PAPER.values() if v[0] == rule), "risk": RULE_TITLES[rule]})
        found += len(entry["findings"])
        report.append(entry)
    if as_json:
        print(json.dumps(report, indent=2))
    else:
        for e in report:
            print(e["file"] + ("" if e["findings"] else "  -- no finding"))
            for x in e["findings"]:
                what = f"{x['rule']} {x['risk']}" if x["module"] == "domain" else f"{x['risk']} ({x['constraint']}, lines {x['lines']})"
                print(f"  {x['module']:<7} {x['severity']:<8} {what}")
    return 1 if found else 0
