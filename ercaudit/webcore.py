"""Entry point used by the web front ends: audit one Solidity source given as text.

Pure Python without third-party imports, so the same code runs in a browser through Pyodide (GitHub Pages site) and
in the Flask service. It applies every rule set that fits the source and returns findings with plain-language
explanations.
"""
from __future__ import annotations

import re
import time
from typing import Any, Dict

from .batchaudit.analyzer import analyze_source
from .batchaudit.taxonomy import CLASS_RULES, CLASS_SEVERITY, CLASS_TITLES, classify, normalize_requirements
from .domaudit.analyzer import analyze_domain_separator_construction
from .domaudit.rules import CATEGORY_TO_PAPER, RULE_TITLES, paper_rules

CONSTRAINT_TEXT = {
    "sender_check": "the caller must be the token holder or an approved operator",
    "approval_check": "an operator must be approved by the holder",
    "zero_address_check": "the recipient must not be the zero address",
    "length_matching_check": "ids and amounts must have the same length",
    "transfer_batch_event_found": "a TransferBatch event must be emitted",
    "event_emission_order": "TransferBatch must be emitted after the transfer",
    "to_isContract_check": "a contract recipient must be detected",
    "on_received_check": "a contract recipient must acknowledge the transfer (onERC1155BatchReceived)",
}
RULE_REQ = {
    "R1": "the signed digest must contain a domain separator and the 0x1901 typed-data prefix",
    "R2": "the domain must include the chain ID",
    "R3": "the chain ID must not be a fixed constant",
    "R4": "a chain ID passed at deployment must equal the deployed chain (decided on chain)",
    "R5": "the domain must include the verifying contract address",
    "R6": "the verifier must be address(this), not a hard-coded address",
    "R7": "a verifier passed at deployment must be the contract itself (decided on chain)",
    "R8": "a stored domain separator must be recomputed when the chain or verifier changes",
    "R9": "the salt must not be zero or shared by all deployments",
}


def applicability(code: str) -> Dict[str, bool]:
    return {
        "batch": "safeBatchTransferFrom" in code,
        "domain": bool(re.search(r"DOMAIN_SEPARATOR|EIP712|permit\s*\(|domainSeparator|eip712Domain", code, re.I)),
    }


def audit_text(code: str) -> Dict[str, Any]:
    t0 = time.perf_counter()
    findings = []
    if "safeBatchTransferFrom" in code:
        res = analyze_source(code)
        for impl in res.get("all_implementations", []):
            req = normalize_requirements(impl["requirements"])
            for cls in classify(req):
                failed = [x for x in CLASS_RULES[cls] if not req.get(x, True)]
                findings.append({
                    "module": "batch", "severity": CLASS_SEVERITY[cls], "risk": CLASS_TITLES[cls],
                    "constraint": "+".join(failed), "lines": f"{impl.get('line_start')}-{impl.get('line_end')}",
                    "explanation": "; ".join(CONSTRAINT_TEXT.get(c, c) for c in failed)})
    dom = analyze_domain_separator_construction(code)
    for rule in paper_rules(dom):
        findings.append({
            "module": "domain", "severity": dom.get("risk_level", ""), "rule": rule,
            "class": next(v[1] for v in CATEGORY_TO_PAPER.values() if v[0] == rule),
            "risk": RULE_TITLES[rule], "explanation": RULE_REQ.get(rule, RULE_TITLES[rule])})
    return {"findings": findings, "exit_status": 1 if findings else 0, "applicable": applicability(code),
            "elapsed_ms": round((time.perf_counter() - t0) * 1000)}
