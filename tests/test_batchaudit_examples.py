"""The synthetic examples encode the paper's constraint model: each mutant violates exactly one check."""
from pathlib import Path

import pytest

from ercaudit.batchaudit.analyzer import analyze_source
from ercaudit.batchaudit.taxonomy import classify_file

EX = Path(__file__).resolve().parents[1] / "examples" / "batch"

EXPECTED = {
    "compliant.sol": [],
    "vuln_missing_access_control.sol": ["missing_access_control"],
    "vuln_missing_address_validation.sol": ["missing_address_validation"],
    "vuln_missing_array_length_check.sol": ["missing_array_length_check"],
    # the receiver-hook check is only evaluated after a TransferBatch event is found (legacy coupling),
    # so omitting the event is also reported as a missing interface check
    "vuln_missing_event.sol": ["event_emission_inconsistency", "missing_interface_check"],
    "vuln_missing_receiver_hook.sol": ["missing_interface_check"],
}


@pytest.mark.parametrize("name,expected", sorted(EXPECTED.items()))
def test_example(name, expected):
    result = analyze_source((EX / name).read_text())
    assert "error" not in result, result
    assert sorted(classify_file(result)) == sorted(expected)
    impl = result["all_implementations"][0]
    assert impl["all_requirements_met"] == (not expected)


def test_leaf_function_error_is_paper_compatible_and_switchable():
    src = """contract C { function safeBatchTransferFrom(address from,address to,uint256[] memory ids,
        uint256[] memory amounts,bytes memory data) public { require(to != address(0)); } }"""
    assert analyze_source(src)["error"] == "Error processing file: 'NoneType' object is not iterable"
    assert "all_implementations" in analyze_source(src, include_leaf_functions=True)


def test_assembly_entry_point_is_skipped():
    src = """contract C { function safeBatchTransferFrom(address from,address to,uint256[] memory ids,
        uint256[] memory amounts,bytes memory data) public { assembly { let x := 1 } } }"""
    assert "No valid implementations" in analyze_source(src)["error"]
