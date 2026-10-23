from pathlib import Path

from ercaudit.domaudit.analyzer import analyze_file
from ercaudit.domaudit.rules import paper_rules, summarize_paper_view

EX = Path(__file__).resolve().parents[1] / "examples" / "domain"


def test_safe_permit_has_no_findings():
    r = analyze_file(EX / "permit_safe.sol")
    assert r["status"] == "ok" and paper_rules(r) == []


def test_listing1_style_permit_hits_chain_verifier_and_freshness_rules():
    r = analyze_file(EX / "permit_replayable.sol")
    assert paper_rules(r) == ["R3", "R6", "R8"]
    view = summarize_paper_view([r])
    assert view["replay_risk_candidates"] == 1
