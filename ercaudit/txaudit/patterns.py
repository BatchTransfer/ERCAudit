"""Transaction-level validation of batch-transfer risks (paper Sec. VI-A).

Three patterns are discernible from calldata alone and are checked per
``safeBatchTransferFrom`` transaction; one relational pattern is checked across
``setApprovalForAll`` transactions:

* ``zero_address``     -- the decoded ``to`` is ``0x0``.
* ``length_mismatch``  -- ``len(ids) != len(amounts)``.
* ``unauthorized``     -- the caller is not ``from`` and was never approved.
* *secondary approvals* -- an approved operator later approves further operators
  (chains of up to ``max_depth`` levels).

Cleaned from ``analyse_transactions`` in ``erc1155_safeBatch_TXNanalysis.py``.
The published semantics are preserved by default; see the notes on
:func:`analyse_transactions` for the two places where they are deliberately
permissive, and the ``strict_authorization`` switch.
"""
from __future__ import annotations

from typing import Any, Dict, List, Tuple

import pandas as pd

from .decoding import (
    ZERO_ADDRESS,
    decode_safeBatchTransferFrom_input,
    decode_setApprovalForAll_input,
)

Approval = Tuple[str, str, bool, int, int, Any]  # owner, operator, approved, timestamp, block, row index


def _func_name(row: pd.Series) -> str:
    return (row.get("functionName", "") or "").split("(")[0].strip()


def approval_chain(
    approvals: List[Approval],
    operator: str,
    timestamp: int,
    block: int,
    max_depth: int = 5,
    depth: int = 1,
) -> List[Tuple[int, str, bool, int, int, Any]]:
    """Follow ``operator`` -> operators it approved *later*, recursively.

    ``approvals`` must be sorted by ``(timestamp, block)``. Only ``approved=True``
    grants are followed. Returns ``(depth, operator, approved, ts, block, idx)`` tuples.
    """
    if depth > max_depth:
        return []

    chain: List[Tuple[int, str, bool, int, int, Any]] = []
    for owner, op, approved, ts, blk, idx in approvals:
        later = ts > timestamp or (ts == timestamp and blk > block)
        if owner.lower() == operator.lower() and later and approved:
            chain.append((depth, op, approved, ts, blk, idx))
            chain.extend(approval_chain(approvals, op, ts, blk, max_depth, depth + 1))
    return chain


def analyse_transactions(
    txs: List[Dict[str, Any]],
    *,
    max_chain_depth: int = 5,
    strict_authorization: bool = False,
) -> pd.DataFrame:
    """Decode and flag ``safeBatchTransferFrom`` / ``setApprovalForAll`` transactions.

    Parameters
    ----------
    txs:
        Etherscan ``txlist`` rows (``input``, ``from``, ``functionName``,
        ``timeStamp``, ``blockNumber``, ...).
    strict_authorization:
        The published pipeline (default, ``False``) treats a caller as authorised
        if *any* recorded approval names the caller as operator **or** names
        ``from`` as operator, ignoring the granting owner and the ordering of
        blocks. This is deliberately conservative (it under-reports
        ``unauthorized``). ``True`` requires ``owner == from``,
        ``operator == caller``, ``approved`` and that the approval precedes the
        transfer.

    Notes
    -----
    Extra columns are added to the input rows: ``decoded_*``, ``unauthorized``,
    ``zero_address``, ``length_mismatch``, ``decoded_operator``,
    ``operator_permission``, ``operator_provides_further_approvals``,
    ``secondary_approvals_count`` and, for approvals that start a chain,
    ``approval_chain_depth``, ``total_chain_approvals``, ``level_1..5_approvals``
    and ``approval_chain_details``.
    """
    df = pd.DataFrame(txs)
    if df.empty:
        return df
    for col, default in (
        ("decoded_from", None), ("decoded_to", None), ("decoded_ids", None), ("decoded_amounts", None),
        ("unauthorized", False), ("unauthorized_addr", None), ("zero_address", False), ("length_mismatch", False),
        ("decoded_operator", None), ("operator_permission", False),
        ("operator_provides_further_approvals", False), ("secondary_approvals_count", 0),
    ):
        df[col] = default
    if "functionName" not in df.columns:
        df["functionName"] = ""

    # ---- pass 1: approval history ----------------------------------------
    approvals: List[Approval] = []
    for idx, row in df.iterrows():
        if _func_name(row) != "setApprovalForAll":
            continue
        try:
            operator, permission = decode_setApprovalForAll_input(row.get("input", ""))
        except Exception:  # malformed calldata: skip, as the published pipeline did
            continue
        df.at[idx, "decoded_operator"] = operator
        df.at[idx, "operator_permission"] = permission
        approvals.append((
            (row.get("from", "") or "").lower(), operator.lower(), permission,
            int(row.get("timeStamp", 0)), int(row.get("blockNumber", 0)), idx,
        ))

    approvals.sort(key=lambda a: (a[3], a[4]))  # chronological; stable

    # ---- secondary approvals ----------------------------------------------
    for owner, operator, permission, ts, blk, idx in approvals:
        if not permission:
            continue
        chain = approval_chain(approvals, operator, ts, blk, max_depth=max_chain_depth)
        if not chain:
            continue
        levels: Dict[int, int] = {}
        for depth, *_rest in chain:
            levels[depth] = levels.get(depth, 0) + 1
        df.at[idx, "operator_provides_further_approvals"] = True
        df.at[idx, "approval_chain_depth"] = max(levels)
        df.at[idx, "total_chain_approvals"] = len(chain)
        df.at[idx, "secondary_approvals_count"] = len(chain)
        for depth in range(1, 6):
            df.at[idx, f"level_{depth}_approvals"] = levels.get(depth, 0)
        df.at[idx, "approval_chain_details"] = ";".join(f"L{d}:{op}@{t}" for d, op, _a, t, _b, _i in chain)

    # ---- pass 2: batch transfers -------------------------------------------
    for idx, row in df.iterrows():
        if _func_name(row) != "safeBatchTransferFrom":
            continue
        try:
            from_addr, to_addr, ids, amounts = decode_safeBatchTransferFrom_input(row.get("input", ""))
        except Exception:
            continue
        df.at[idx, "decoded_from"] = from_addr
        df.at[idx, "decoded_to"] = to_addr
        df.at[idx, "decoded_ids"] = ids
        df.at[idx, "decoded_amounts"] = amounts

        caller = (row.get("from", "") or "").lower()
        owner = from_addr.lower()
        if caller != owner:
            if strict_authorization:
                ts, blk = int(row.get("timeStamp", 0)), int(row.get("blockNumber", 0))
                approved = any(
                    o == owner and op == caller and ok and (t < ts or (t == ts and b < blk))
                    for o, op, ok, t, b, _ in approvals)
            else:
                approved = any(ok and (op == owner or caller == op) for _o, op, ok, _t, _b, _i in approvals)
            if not approved:
                df.at[idx, "unauthorized"] = True
                df.at[idx, "unauthorized_addr"] = owner

        if to_addr.lower() in (ZERO_ADDRESS, "0x000000"):
            df.at[idx, "zero_address"] = True
        if len(ids) != len(amounts):
            df.at[idx, "length_mismatch"] = True

    return df


def summarize_transactions(df: pd.DataFrame) -> Dict[str, int]:
    """Headline counts for a result of :func:`analyse_transactions`."""
    if df.empty:
        return {}
    batch = df["functionName"].fillna("").str.startswith("safeBatchTransferFrom")
    approvals = df["functionName"].fillna("").str.startswith("setApprovalForAll")
    return {
        "transactions": int(len(df)),
        "safeBatchTransferFrom": int(batch.sum()),
        "setApprovalForAll": int(approvals.sum()),
        "unauthorized": int(df["unauthorized"].sum()),
        "zero_address": int(df["zero_address"].sum()),
        "length_mismatch": int(df["length_mismatch"].sum()),
        "secondary_approval_starts": int(df["operator_provides_further_approvals"].sum()),
    }
