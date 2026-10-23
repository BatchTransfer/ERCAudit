from ercaudit import onchain


def test_verdicts_are_normalised():
    assert onchain.normalise("R2_confirmed") == "confirmed"
    assert onchain.normalise("R3_differs_from_chain") == "confirmed"
    assert onchain.normalise("R8_confirmed_stale") == "confirmed"
    assert onchain.normalise("R6_refuted") == "refuted"
    assert onchain.normalise("R8_unchanged_unresolved") == "unresolved"
    assert onchain.normalise("ds_unavailable") == "unresolved"


def test_conclusive_verdict_wins_and_not_applicable_is_dropped():
    recs = [
        {"rule": "R1", "chain": "ethereum", "address": "0xa", "verdict": "inconclusive"},
        {"rule": "R1", "chain": "ethereum", "address": "0xa", "verdict": "R1_confirmed_no_signature_check"},
        {"rule": "R1", "chain": "ethereum", "address": "0xb", "verdict": "no_standard_permit"},
    ]
    table = onchain.summarise(recs)
    assert table["R1"] == {"flagged": 1, "confirmed": 1, "refuted": 0, "unresolved": 0, "precision_on_decided": 1.0}
