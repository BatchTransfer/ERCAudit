"""End-to-end check of the unified run on the shipped 100-file sample (offline, a few seconds)."""
import json

from ercaudit import pipeline
from ercaudit.domaudit.rules import PAPER_RULES


def test_unified_run_on_sample_100(tmp_path):
    assert pipeline.main(["--size", "100", "--jobs", "1", "--out", str(tmp_path)]) == 0
    rep = json.loads((tmp_path / "report.json").read_text())
    b, t, d = rep["batchaudit"], rep["txaudit"], rep["domaudit"]
    assert (b["files"], b["analysable"], b["flagged_contracts"]) == (100, 88, 36)
    assert (b["confusion"]["tp"], b["confusion"]["fp"], b["confusion"]["fn"], b["confusion"]["tn"]) == (25, 4, 7, 57)
    assert t["transactions"] == 100 and t["unauthorized"] == 2 and t["zero_address"] == 0
    assert all(t["parity_with_stored_analysis"].values())
    assert (d["files"], d["flagged_contracts"]) == (100, 89)
    assert set(d["rule_observations"]) == set(PAPER_RULES)
    assert (d["true_positives"], d["labelled_still_flagged"]) == (63, 72)
    findings = (tmp_path / "findings.csv").read_text().splitlines()
    assert len(findings) == 1 + 59 + 2 + 132
    assert {"module", "rule", "severity", "onchain"} <= set(findings[0].split(","))


def test_sample_200_extends_sample_100():
    import pandas as pd
    for name in ("manifest_batch.csv", "manifest_dom.csv"):
        m = pd.read_csv(pipeline.ROOT / "data" / "sample" / name)
        assert len(m) == 200 and list(m["rank"]) == list(range(200))


def test_audit_command_on_examples(capsys):
    from pathlib import Path
    ex = pipeline.ROOT / "examples"
    assert pipeline.audit(str(ex / "batch" / "compliant.sol")) == 0
    assert pipeline.audit(str(ex / "domain" / "permit_safe.sol")) == 0
    capsys.readouterr()
    assert pipeline.audit(str(ex / "domain" / "permit_replayable.sol")) == 1
    out = capsys.readouterr().out
    assert all(rule in out for rule in ("R3", "R6", "R8"))
    assert pipeline.audit(str(ex / "batch" / "vuln_missing_address_validation.sol")) == 1
    assert "Missing Address Validation" in capsys.readouterr().out
