#!/usr/bin/env python3
"""Build the shipped demonstration sample (data/sample/) from the full research tree.

Maintainer script: it needs the full research tree (``--src``), which is not part of this repository. The
generated sample IS committed, so users never need to run this. Selection is deterministic (fixed seed) and
nested: the 100-file sample is a prefix of the 200-file sample.

  batch/  ERC-1155 sources: the 10 contracts whose transactions are shipped first, then manually labelled
          contracts, one non-compliant for every two compliant until the non-compliant ones run out.
  dom/    the 200 flagged permit contracts of the DomAudit precision sample (40 per class C1-C5), 20 per class first.
  tx/     transactions of the 10 contracts above, unauthorised ones first, then round-robin over contracts.
  onchain stored on-chain verdicts (R1-R9) for the sampled DomAudit contracts.
"""
import argparse
import csv
import json
import random
import shutil
from collections import defaultdict
from pathlib import Path

import pandas as pd

ONCHAIN_FILES = {
    "R1": "r1_verify_v4.jsonl", "R2": "r2_verify_v3.jsonl", "R3": "r3_verify.jsonl", "R5": "r5_verify.jsonl",
    "R6": "r6_verify_v2.jsonl", "R7": "r7_verify_v2.jsonl", "R8": "r8_verify.jsonl", "R9": "r9_verify_v3.jsonl",
}
SEED = 2026


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="full research tree (ERC-Analysis-master-ICSE-tool)")
    ap.add_argument("--out", default=str(Path(__file__).resolve().parents[1] / "data" / "sample"))
    ap.add_argument("--n", type=int, default=200)
    a = ap.parse_args()
    src, out = Path(a.src), Path(a.out)
    for sub in ("batch", "dom"):
        shutil.rmtree(out / sub, ignore_errors=True)
        (out / sub).mkdir(parents=True)

    # ---------------- transactions: 10 contracts, ranked
    raw = pd.read_csv(src / "data/transactions/raw_txs_1094.csv", dtype=str)
    stored = pd.read_csv(src / "data/transactions/analysed_txs_1094_stored.csv", dtype=str)
    raw["contract_address"] = raw["contract_address"].str.lower()
    unauth = set(stored.loc[stored["unauthorized"].astype(str).str.lower() == "true", "hash"])
    per = defaultdict(list)
    for _, r in raw.iterrows():
        per[r["contract_address"]].append(r)
    for rows in per.values():
        rows.sort(key=lambda r: (r["hash"] not in unauth, int(r["blockNumber"])))
    order, i = [], 0
    while len(order) < len(raw):
        for addr in sorted(per):
            if i < len(per[addr]):
                order.append(per[addr][i])
        i += 1
    order.sort(key=lambda r: r["hash"] not in unauth)  # stable: unauthorised first, round-robin otherwise
    tx = pd.DataFrame(order[: a.n]).reset_index(drop=True)
    tx.insert(0, "rank", range(len(tx)))
    tx.to_csv(out / "tx_sample.csv", index=False)
    stored[stored["hash"].isin(tx["hash"])].to_csv(out / "tx_sample_stored_analysis.csv", index=False)
    tx_contracts = sorted(tx["contract_address"].unique())

    # ---------------- ERC-1155 sources
    gt = json.load(open(src / "data/ground_truth/batchaudit/ground_truth.json"))
    gt_dir = src / "data/ground_truth/batchaudit/sources"
    legacy = src / "legacy/erc-classify-original/DATA/ERC1155-ethereum/ERC1155"
    chosen = []
    for addr in tx_contracts:
        name = f"ERC1155_{addr}.sol"
        p = gt_dir / name if (gt_dir / name).exists() else legacy / name
        chosen.append((name, p, gt.get(name)))
    rng = random.Random(SEED)
    pool = sorted(k for k, v in gt.items() if v.get("ground_truth_label:is_contract_compliant") is not None
                  and (gt_dir / k).exists() and k not in {c[0] for c in chosen})
    bad = [k for k in pool if gt[k]["ground_truth_label:is_contract_compliant"] is False]
    good = [k for k in pool if gt[k]["ground_truth_label:is_contract_compliant"] is True]
    rng.shuffle(bad), rng.shuffle(good)
    while len(chosen) < a.n and (bad or good):
        for k in ([bad.pop()] if bad else []) + [good.pop() for _ in range(2 if good else 0)]:
            if len(chosen) < a.n:
                chosen.append((k, gt_dir / k, gt[k]))
    with open(out / "manifest_batch.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["rank", "file", "address", "manual_compliant", "manual_note", "has_tx_sample"])
        for rank, (name, p, g) in enumerate(chosen):
            shutil.copy(p, out / "batch" / name)
            addr = name.split("_")[1][:-4]
            w.writerow([rank, name, addr, "" if not g else g["ground_truth_label:is_contract_compliant"],
                        "" if not g else (g.get("manual_evaluation") or ""), addr in tx_contracts])

    # ---------------- DomAudit sources (+ manual labels; rule numbers follow manifest_labeled.csv = final R1-R9)
    base = src / "data/ground_truth/domaudit/precision_sample_final"
    man = pd.read_csv(base / "manifest.csv", dtype=str).fillna("")
    lab = pd.read_csv(base / "manifest_labeled.csv", dtype=str).fillna("").set_index("sample_id")
    files = {p.name: p for p in (base / "files").rglob("*.sol")}
    rows, rank_in_class = [], defaultdict(int)
    for _, m in man.iterrows():
        name = Path(m["server_path"]).name
        label = lab.loc[m["sample_id"]] if m["sample_id"] in lab.index else None
        rows.append({
            "sample_id": m["sample_id"], "file": name, "address": m["address"], "chain": m["chain"], "class": m["class"],
            "manual_rule": "" if label is None else label["rule"], "manual_label": "" if label is None else label["manual_label_TP_FP"],
            "manual_reason": "" if label is None else label["reason"],
        })
    # nested order: round-robin over classes so that the first 100 hold 20 per class
    by_class = defaultdict(list)
    for r in rows:
        by_class[r["class"]].append(r)
    ordered = []
    for k in range(max(len(v) for v in by_class.values())):
        for c in sorted(by_class):
            if k < len(by_class[c]):
                ordered.append(by_class[c][k])
    ordered = ordered[: a.n]
    for rank, r in enumerate(ordered):
        r["rank"] = rank
        shutil.copy(files[r["file"]], out / "dom" / r["file"])
    pd.DataFrame(ordered)[["rank", "sample_id", "file", "address", "chain", "class", "manual_rule", "manual_label",
                           "manual_reason"]].to_csv(out / "manifest_dom.csv", index=False)

    # ---------------- stored on-chain verdicts for the sampled DomAudit contracts
    wanted = {r["file"] for r in ordered}
    n = 0
    with open(out / "onchain_dom_sample.jsonl", "w") as fh:
        for rule, fname in ONCHAIN_FILES.items():
            for line in open(src / "results/onchain" / fname):
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("file") in wanted:
                    d["rule"] = rule
                    fh.write(json.dumps(d) + "\n")
                    n += 1
    print(f"batch={len(chosen)} dom={len(ordered)} tx={len(tx)} onchain_records={n}")


if __name__ == "__main__":
    main()
