#!/usr/bin/env python3
"""Combined ERCAudit run: BatchAudit + TxAudit + DomAudit + stored on-chain verdicts, one report.

Thin wrapper around ``ercaudit.pipeline`` (identical to ``ercaudit run``). Examples:
    python combine_run.py --size 100          # 100 ERC-1155 + 100 permit sources + 100 transactions
    python combine_run.py --size 200 --jobs 8
See ercaudit/pipeline.py for the outputs.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ercaudit.pipeline import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
