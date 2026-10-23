"""Pins the facts about the shipped labelled set that the artifact documentation relies on."""
from pathlib import Path

import pytest

from ercaudit.batchaudit import evaluation

GT = Path(__file__).resolve().parents[1] / "data/ground_truth/batchaudit/ground_truth.json"
pytestmark = pytest.mark.skipif(not GT.exists(), reason="ground truth not present")


def test_labelled_set_and_stored_verdicts():
    gt = evaluation.load_ground_truth(str(GT))
    assert len(gt) == 941
    stored = evaluation.confusion(gt, evaluation.stored_verdicts(gt))
    assert (stored.tp, stored.fn) == (37, 4)          # 41 true non-compliant contracts, 37 found
    assert stored.tp + stored.fp == 57                 # flagged in the stored file


def test_paper_46_flagged_is_37_plus_9_annotated_fps():
    gt = evaluation.load_ground_truth(str(GT))
    tp, annotated_fp, unannotated = evaluation.split_flagged_by_annotation(gt)
    assert (tp, annotated_fp, unannotated) == (37, 9, 11)
    assert round(tp / (tp + annotated_fp), 3) == 0.804   # the published precision
