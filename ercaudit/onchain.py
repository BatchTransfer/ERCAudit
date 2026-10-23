"""On-chain evidence for DomAudit findings (rules R1-R9 of the DomAudit paper).

The verifiers in ``scripts/onchain_*_verify.py`` probe deployed contracts (``eth_call`` on ``DOMAIN_SEPARATOR()``,
separator recomputation, chain-ID fork test, ``permit`` simulation) and append one JSON record per contract with a
rule-specific ``verdict``. This module only *reads* those records: it normalises the verdicts to three outcomes and
aggregates them, so that the same table can be rebuilt offline from the shipped files.

``confirmed``  the flagged pattern holds in the deployed contract
``refuted``    it does not (a static false positive)
``unresolved`` no readable separator, a custom layout, or an RPC failure
"""
from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, Iterable, List

CONFIRMED, REFUTED, UNRESOLVED = "confirmed", "refuted", "unresolved"
_STRENGTH = {CONFIRMED: 3, REFUTED: 2, UNRESOLVED: 1}

#: verdicts that count as "the flagged pattern holds" although their name does not say "confirmed"
_CONFIRMING = {"R3_matches_chain", "R3_differs_from_chain"}
_NOT_CONFIRMING = {"R8_unchanged_unresolved", "R8_unchanged_no_chainid"}
#: the contract has no standard ``permit``: R1 does not apply, so the record is not counted
_NOT_APPLICABLE = {"no_standard_permit"}


def normalise(verdict: str) -> str:
    v = verdict or ""
    if v in _CONFIRMING or ("confirmed" in v and v not in _NOT_CONFIRMING):
        return CONFIRMED
    if "refuted" in v:
        return REFUTED
    return UNRESOLVED


def load_records(path: Path, rule: str = "") -> List[Dict]:
    """Read a JSON-lines verification file; tolerate partial lines."""
    out = []
    for line in Path(path).read_text().splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if rule:
            d.setdefault("rule", rule)
        out.append(d)
    return out


def best_per_contract(records: Iterable[Dict]) -> Dict[tuple, Dict]:
    """One record per (rule, chain, address): a conclusive verdict beats an inconclusive one."""
    best: Dict[tuple, Dict] = {}
    for d in records:
        if d.get("verdict") in _NOT_APPLICABLE:
            continue
        d = dict(d, outcome=normalise(d.get("verdict", "")))
        key = (d.get("rule"), d.get("chain"), (d.get("address") or d.get("file") or "").lower())
        if key not in best or _STRENGTH[d["outcome"]] > _STRENGTH[best[key]["outcome"]]:
            best[key] = d
    return best


def summarise(records: Iterable[Dict]) -> Dict[str, Dict[str, int]]:
    """``{rule: {flagged, confirmed, refuted, unresolved, precision}}`` over distinct contracts."""
    counts: Dict[str, Counter] = defaultdict(Counter)
    for (rule, _chain, _addr), d in best_per_contract(records).items():
        counts[rule][d["outcome"]] += 1
    table = {}
    for rule in sorted(counts):
        c = counts[rule]
        decided = c[CONFIRMED] + c[REFUTED]
        table[rule] = {
            "flagged": sum(c.values()), CONFIRMED: c[CONFIRMED], REFUTED: c[REFUTED], UNRESOLVED: c[UNRESOLVED],
            "precision_on_decided": round(c[CONFIRMED] / decided, 4) if decided else None,
        }
    return table
