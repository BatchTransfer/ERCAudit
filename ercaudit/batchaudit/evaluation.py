"""Precision / recall against the manually labelled ground truth (paper Sec. V-B).

A contract is *positive* when it is **non-compliant** (violates at least one of
the eight constraints). The ground-truth file maps ``ERC1155_0x....sol`` to the
manual label ``ground_truth_label:is_contract_compliant`` and (in older
result files) the tool's verdict at labelling time (``tool_results``).

Files on which the tool finds no ``safeBatchTransferFrom`` (an ``error``
result) count as *not flagged*.
"""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, asdict
from typing import Dict, Iterable, Optional, Tuple

from .taxonomy import normalize_requirements
from .constraints import REQUIREMENTS

LABEL_KEY = "ground_truth_label:is_contract_compliant"


@dataclass
class Confusion:
    tp: int = 0
    fp: int = 0
    fn: int = 0
    tn: int = 0

    @property
    def precision(self) -> float:
        return self.tp / (self.tp + self.fp) if (self.tp + self.fp) else 0.0

    @property
    def recall(self) -> float:
        return self.tp / (self.tp + self.fn) if (self.tp + self.fn) else 0.0

    @property
    def f1(self) -> float:
        p, r = self.precision, self.recall
        return 2 * p * r / (p + r) if (p + r) else 0.0

    def as_dict(self) -> Dict[str, float]:
        d = asdict(self)
        d.update(precision=round(self.precision, 4), recall=round(self.recall, 4), f1=round(self.f1, 4))
        return d


def load_ground_truth(path: str) -> Dict[str, dict]:
    """Return only the *labelled* entries of a ground-truth JSON file."""
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    return {k: v for k, v in data.items() if v.get(LABEL_KEY) is not None}


def verdict_from_requirements(requirements: Dict[str, bool]) -> bool:
    """``True`` = tool flags the implementation as non-compliant."""
    req = normalize_requirements(requirements)
    return not all(req.get(r, False) for r in REQUIREMENTS)


def tool_flags(result: Optional[Dict]) -> bool:
    """Non-compliant verdict for a per-file analyzer result (errors -> not flagged)."""
    if not result or "error" in result:
        return False
    return any(verdict_from_requirements(i["requirements"]) for i in result["all_implementations"])


def confusion(ground_truth: Dict[str, dict], flags: Dict[str, bool]) -> Confusion:
    """Compare tool verdicts (``name -> flagged``) with manual labels."""
    c = Confusion()
    for name, entry in ground_truth.items():
        if name not in flags:
            continue
        positive = not entry[LABEL_KEY]
        flagged = flags[name]
        if flagged and positive:
            c.tp += 1
        elif flagged:
            c.fp += 1
        elif positive:
            c.fn += 1
        else:
            c.tn += 1
    return c


def stored_verdicts(ground_truth: Dict[str, dict]) -> Dict[str, bool]:
    """Verdicts recorded in the ground-truth file itself (labelling-time tool output)."""
    return {n: verdict_from_requirements(e["tool_results"]) for n, e in ground_truth.items() if e.get("tool_results")}


_FP_TEXT = re.compile(r"false\s+pos", re.IGNORECASE)


def split_flagged_by_annotation(ground_truth: Dict[str, dict]) -> Tuple[int, int, int]:
    """Break stored tool-flagged, manually-compliant entries into annotated / unannotated FPs.

    Returns ``(tp, annotated_fp, unannotated_fp)``. An *unannotated* FP is an entry
    whose manual label is compliant and whose stored tool verdict is "flagged", but
    whose free-text ``manual_evaluation`` does not describe a false positive.
    """
    tp = annotated = unannotated = 0
    for entry in ground_truth.values():
        if not entry.get("tool_results"):
            continue
        flagged = verdict_from_requirements(entry["tool_results"])
        positive = not entry[LABEL_KEY]
        if not flagged:
            continue
        if positive:
            tp += 1
        elif _FP_TEXT.search(entry.get("manual_evaluation") or ""):
            annotated += 1
        else:
            unannotated += 1
    return tp, annotated, unannotated


def locate_sources(names: Iterable[str], roots: Iterable[str]) -> Dict[str, str]:
    """Find each ground-truth file below ``roots``, by name and then by address.

    Sources were collected under several naming schemes
    (``ERC1155_0x..``, ``bsc_ERC1155_0x..``, ``..#code.sol``); the 40-hex
    address is the stable key.
    """
    by_name: Dict[str, str] = {}
    by_addr: Dict[str, str] = {}
    for root in roots:
        for dirpath, _dirs, files in os.walk(root):
            for f in files:
                if not f.endswith(".sol"):
                    continue
                full = os.path.join(dirpath, f)
                by_name.setdefault(f, full)
                m = re.search(r"0x[a-fA-F0-9]{40}", f)
                if m:
                    by_addr.setdefault(m.group(0).lower(), full)
    found: Dict[str, str] = {}
    for n in names:
        if n in by_name:
            found[n] = by_name[n]
            continue
        m = re.search(r"0x[a-fA-F0-9]{40}", n)
        if m and m.group(0).lower() in by_addr:
            found[n] = by_addr[m.group(0).lower()]
    return found
