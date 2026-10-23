"""Alignment between the analyzer's rule names and the DomAudit paper's rule system.

The analyzer (``analyzer.py``) grew organically: it reports twelve
requirement-level categories (``risk_category``) grouped into taxonomy ids
``T1..T5``. The DomAudit paper (Table I) consolidates them into nine rules
``R1..R9`` in five violation classes ``C1..C5`` and re-numbers the replay-risk
labels (paper T4 = domain freshness, paper T5 = logical domain; the analyzer has
these two swapped). This module is the single place that records the mapping so
that results can be reported in either vocabulary.

The mapping is an interpretation made while preparing this artifact
(``docs/AUDIT_REPORT.md`` lists it as something to confirm): in particular, the
paper's R1 is taken to cover both a missing separator and a missing EIP-191
typed-data prefix (paper Sec. VI-C mentions "omit EIP-191 framing" under C1),
and R6 to cover both plain cached separators and proxy-context staleness.
"""
from __future__ import annotations

from collections import Counter
from typing import Dict, Iterable, List

#: analyzer ``risk_category`` -> (paper rule, paper class, paper replay-risk label)
CATEGORY_TO_PAPER = {
    "missing_domain_separator":              ("R1", "C1 Domain Separation", "T1 Unseparated Authorization Domain"),
    "missing_eip191_prefix":                 ("R1", "C1 Domain Separation", "T1 Unseparated Authorization Domain"),
    "missing_chainId":                       ("R2", "C2 Chain Binding", "T2 Cross-Chain Authorization Replay"),
    "hardcoded_chainId":                     ("R3", "C2 Chain Binding", "T2 Cross-Chain Authorization Replay"),
    "dynamic_chainId_param":                 ("R4", "C2 Chain Binding", "T2 Cross-Chain Authorization Replay"),
    "missing_verifyingContract":             ("R5", "C3 Verifier Binding", "T3 Cross-Contract Authorization Replay"),
    "incorrect_verifyingContract":           ("R6", "C3 Verifier Binding", "T3 Cross-Contract Authorization Replay"),
    "hardcoded_verifier":                    ("R6", "C3 Verifier Binding", "T3 Cross-Contract Authorization Replay"),
    "dynamic_verifier_param":                ("R7", "C3 Verifier Binding", "T3 Cross-Contract Authorization Replay"),
    "stale_cached_DOMAIN_SEPARATOR":         ("R8", "C4 Domain Freshness", "T4 Domain Freshness Failure"),
    "proxy_stale_domain":                    ("R8", "C4 Domain Freshness", "T4 Domain Freshness Failure"),
    "hardcoded_salt":                        ("R9", "C5 Logical Domain", "T5 Logical-Domain Ambiguity"),
    "zero_salt_used":                        ("R9", "C5 Logical Domain", "T5 Logical-Domain Ambiguity"),
}

PAPER_RULES = ("R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9")
PAPER_CLASSES = ("C1 Domain Separation", "C2 Chain Binding", "C3 Verifier Binding",
                 "C4 Domain Freshness", "C5 Logical Domain")


def paper_rules(result: Dict) -> List[str]:
    """Distinct paper rules (R1..R9) triggered by one analyzer result."""
    rules = {CATEGORY_TO_PAPER[c][0] for c in result.get("risk_category", []) if c in CATEGORY_TO_PAPER}
    return sorted(rules)


def paper_classes(result: Dict) -> List[str]:
    classes = {CATEGORY_TO_PAPER[c][1] for c in result.get("risk_category", []) if c in CATEGORY_TO_PAPER}
    return sorted(classes)


def is_replay_risk_candidate(result: Dict) -> bool:
    """A verified file is a *replay-risk candidate* if it triggers at least one rule (paper Table III)."""
    return bool(paper_rules(result))


def summarize_paper_view(results: Iterable[Dict]) -> Dict:
    """Corpus statistics in the paper's vocabulary (rule-level observations, not exploits)."""
    rules: Counter = Counter()
    classes: Counter = Counter()
    candidates = analysed = 0
    for r in results:
        if r.get("status") == "error":
            continue
        analysed += 1
        pr = paper_rules(r)
        if pr:
            candidates += 1
        rules.update(pr)
        classes.update(paper_classes(r))
    return {
        "analysed_files": analysed,
        "replay_risk_candidates": candidates,
        "candidate_rate_pct": round(100.0 * candidates / analysed, 2) if analysed else 0.0,
        "rule_observations": {r: rules.get(r, 0) for r in PAPER_RULES},
        "class_observations": {c: classes.get(c, 0) for c in PAPER_CLASSES},
    }


#: Short titles of the nine rules (DomAudit paper, Table "Rules for signature-construction correctness").
RULE_TITLES = {
    "R1": "missing domain separator or EIP-191 framing",
    "R2": "missing chainId in the domain",
    "R3": "hardcoded chainId",
    "R4": "deployment-supplied chainId (conditional)",
    "R5": "missing verifyingContract in the domain",
    "R6": "hardcoded verifier",
    "R7": "externally supplied verifier (conditional)",
    "R8": "stored domain separator without refresh",
    "R9": "hardcoded or zero salt",
}
