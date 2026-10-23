"""Mapping from failed requirements to the six batch-transfer risk classes.

Paper Sec. III-D groups the eight constraints of Table I into six classes.
The mapping below is what this artifact uses to aggregate results
(:func:`summarize`). It is *derived from the published numbers*: on the stored
per-chain result files the counts of ``sender_check`` and
``length_matching_check`` failures equal Table V's "Missing Access Control" and
"Missing Array Length Check" rows on all four chains (see
``docs/AUDIT_REPORT.md``).

The *Gas-related* class of the paper was triaged manually and is not a function
of the eight flags; only the "inefficient ``safeTransferFrom`` inside the batch"
sub-pattern is available automatically (``gas_iet_safetransferfrom_in_batch``).
"""
from __future__ import annotations

from collections import Counter, defaultdict
from typing import Dict, Iterable, List

#: class -> requirement flags whose violation places a contract in the class.
CLASS_RULES: Dict[str, tuple] = {
    "missing_access_control": ("sender_check",),
    "missing_address_validation": ("zero_address_check",),
    "missing_array_length_check": ("length_matching_check",),
    "event_emission_inconsistency": ("transfer_batch_event_found", "event_emission_order"),
    "missing_interface_check": ("to_isContract_check", "on_received_check"),
}

CLASS_TITLES = {
    "missing_access_control": "Missing Access Control",
    "missing_address_validation": "Missing Address Validation",
    "missing_array_length_check": "Missing Array Length Check",
    "event_emission_inconsistency": "Event Emit Inconsistencies",
    "missing_interface_check": "Missing Interface Check",
    "gas_related": "Gas-related Vulnerabilities",
}

#: Severity per class (paper Table III).
CLASS_SEVERITY = {
    "missing_access_control": "Critical",
    "missing_address_validation": "High",
    "missing_array_length_check": "High",
    "event_emission_inconsistency": "Medium",
    "missing_interface_check": "High",
    "gas_related": "Medium",
}

#: Older result files use different names for the same flags.
FLAG_ALIASES = {"event_emission_before_transfers": "event_emission_order"}


def normalize_requirements(requirements: Dict[str, bool]) -> Dict[str, bool]:
    return {FLAG_ALIASES.get(k, k): v for k, v in requirements.items()}


def classify(requirements: Dict[str, bool]) -> List[str]:
    """Risk classes violated by one implementation's requirement flags."""
    req = normalize_requirements(requirements)
    return [
        cls for cls, flags in CLASS_RULES.items()
        if any(f in req and not req[f] for f in flags)
    ]


def classify_file(result: Dict) -> List[str]:
    """Union of violated classes over all implementations in one file result."""
    classes: List[str] = []
    for impl in result.get("all_implementations", []):
        for cls in classify(impl["requirements"]):
            if cls not in classes:
                classes.append(cls)
    return classes


def summarize(results: Iterable[Dict]) -> Dict:
    """Aggregate a list of per-file results into corpus-level statistics."""
    total = analysed = flagged = 0
    errors: Counter = Counter()
    per_class: Counter = Counter()
    for res in results:
        total += 1
        if "error" in res:
            errors[res["error"].split(":")[0][:60]] += 1
            continue
        analysed += 1
        classes = classify_file(res)
        if classes:
            flagged += 1
        per_class.update(classes)
    return {
        "files": total,
        "analysed": analysed,
        "flagged_contracts": flagged,
        "class_observations": {c: per_class.get(c, 0) for c in CLASS_RULES},
        "errors": dict(errors),
    }


def per_chain_table(results_by_chain: Dict[str, List[Dict]]) -> Dict[str, Dict[str, int]]:
    """``{class: {chain: count}}`` -- the shape of paper Table V (without Gas)."""
    table: Dict[str, Dict[str, int]] = defaultdict(dict)
    for chain, results in results_by_chain.items():
        counts = summarize(results)["class_observations"]
        for cls, n in counts.items():
            table[cls][chain] = n
    return dict(table)
