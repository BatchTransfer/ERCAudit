import pytest

from ercaudit.spec import selectors


def test_known_selectors_and_interface_id_note():
    assert selectors.is_batch_candidate("0x6080" + "63" + "2eb2c2d6" + "14")
    assert not selectors.is_batch_candidate("0x6080604052")
    assert selectors.INTERFACE_IDS["IERC1155Receiver"] == "4e2312e0"
    assert selectors.ACCEPTANCE_MAGIC["onERC1155BatchReceived"] == "bc197c81"


def test_selectors_match_keccak():
    pytest.importorskip("eth_utils")
    for sig, sel in selectors.SELECTORS.items():
        assert selectors.selector_of(sig) == sel, sig
    xor = int(selectors.selector_of("onERC1155Received(address,address,uint256,uint256,bytes)"), 16) ^ \
        int(selectors.selector_of("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"), 16)
    assert format(xor, "08x") == selectors.INTERFACE_IDS["IERC1155Receiver"]
