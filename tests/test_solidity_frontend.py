from ercaudit.solidity import (SAFE_BATCH_TRANSFER_SIG, find_all_functions, find_functions_by_signature,
                               find_if_revert_control_flow, get_all_internal_calls, normalize_signature,
                               contains_assembly)


def test_normalize_signature_strips_names_and_locations():
    assert normalize_signature(SAFE_BATCH_TRANSFER_SIG) == \
        "safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)"
    assert normalize_signature("f(uint x, uint8 y)") == "f(uint256,uint8)"


def test_function_discovery_and_callees():
    src = """
    contract C {
        function a(uint x) public { b(x); require(x > 0); }
        function b(uint y) internal { c(y); }
        function c(uint z) internal pure {}
        function unrelated() public {}
    }"""
    funcs = find_all_functions(src)
    assert [f["name"] for f in funcs] == ["a", "b", "c", "unrelated"]
    callees = get_all_internal_calls(funcs[0]["body"], funcs)
    assert [f["name"] for f in callees] == ["b", "c"]
    assert get_all_internal_calls(funcs[3]["body"], funcs) is None  # published behaviour: None, not []


def test_if_revert_conditions():
    code = "if (a != b && !ok(a)) { revert(); } if (x) { y = 1; }"
    assert find_if_revert_control_flow(code) == ["a != b && !ok(a)"]


def test_signature_matching_and_assembly_detection():
    src = "contract C { function safeBatchTransferFrom(address from,address to,uint256[] calldata ids," \
          "uint256[] calldata amounts,bytes calldata data) external { assembly { let x := 1 } } }"
    funcs = find_functions_by_signature(find_all_functions(src), SAFE_BATCH_TRANSFER_SIG)
    assert len(funcs) == 1 and funcs[0]["parameters"]["ids"] == "uint256[] calldata"
    assert contains_assembly(funcs[0]["body"])
