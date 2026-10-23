#!/usr/bin/env python3
"""Replay the transaction validator on the 1,094 stored safeBatchTransferFrom transactions and
compare every derived column with the stored analysis (data/transactions/analysed_txs_1094_stored.csv)."""
import ast
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ercaudit.txaudit.patterns import analyse_transactions, summarize_transactions  # noqa: E402


def main():
    raw = pd.read_csv(ROOT / "data/transactions/raw_txs_1094.csv", low_memory=False)
    stored = pd.read_csv(ROOT / "data/transactions/analysed_txs_1094_stored.csv", low_memory=False)
    fresh = analyse_transactions(raw.to_dict("records"))
    print("summary:", summarize_transactions(fresh))
    ok = True
    for col in ("unauthorized", "zero_address", "length_mismatch"):
        same = bool((fresh[col].astype(bool).values == stored[col].astype(bool).values).all())
        ok &= same
        print(f"  {col:16s} identical to stored: {same}")
    for col in ("decoded_from", "decoded_to"):
        same = bool((fresh[col].str.lower().values == stored[col].str.lower().values).all())
        ok &= same
        print(f"  {col:16s} identical to stored: {same}")
    same = all(list(a) == ast.literal_eval(b) for a, b in zip(fresh["decoded_ids"], stored["decoded_ids"]))
    ok &= same
    print(f"  {'decoded_ids':16s} identical to stored: {same}")
    print("RESULT:", "all columns reproduced" if ok else "MISMATCH")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
