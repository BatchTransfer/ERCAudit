"""Phase 1 -- selector-based contract identification (paper Sec. IV-A, Listing 6).

A deployed contract is a *batch-transfer candidate* when its runtime bytecode
contains ``bytes4(keccak256("safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)"))``
= ``0x2eb2c2d6``. The same mechanism selects the signature-related contracts of the
DomAudit adoption study. Matching is a substring test on the lower-case hex
bytecode, as in ``GetSelectors.py`` / ``ERCclassification.py`` of the research code;
``strict=True`` additionally requires a ``PUSH4`` (``0x63``) immediately before the
selector, which removes accidental byte-pattern matches.
"""
from __future__ import annotations

from typing import Dict, List

#: function signature -> 4-byte selector (verified against keccak256 in the test-suite)
SELECTORS: Dict[str, str] = {
    "safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)": "2eb2c2d6",
    "setApprovalForAll(address,bool)": "a22cb465",
    "isApprovedForAll(address,address)": "e985e9c5",
    "safeTransferFrom(address,address,uint256,uint256,bytes)": "f242432a",
    "balanceOfBatch(address[],uint256[])": "4e1273f4",
    "onERC1155Received(address,address,uint256,uint256,bytes)": "f23a6e61",
    "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)": "bc197c81",
    "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)": "d505accf",
    "DOMAIN_SEPARATOR()": "3644e515",
    "eip712Domain()": "84b0196e",
    "isValidSignature(bytes32,bytes)": "1626ba7e",
    "isValidSignature(bytes,bytes)": "20c13b0b",
}

#: ERC-165 interface ids. NOTE: 0x4e2312e0 is the *interface id* of IERC1155Receiver
#: (onERC1155Received ^ onERC1155BatchReceived), not the acceptance magic value that
#: a receiver must return (0xf23a6e61 / 0xbc197c81).
INTERFACE_IDS = {"IERC1155": "d9b67a26", "IERC1155Receiver": "4e2312e0"}
ACCEPTANCE_MAGIC = {"onERC1155Received": "f23a6e61", "onERC1155BatchReceived": "bc197c81"}

FEATURES = {
    "batch_transfer": ["2eb2c2d6"],
    "erc2612_permit": ["d505accf"],
    "eip712_domain_separator": ["3644e515"],
    "erc5267": ["84b0196e"],
    "erc1271": ["1626ba7e", "20c13b0b"],
}


def selector_of(signature: str) -> str:
    """Compute ``bytes4(keccak256(signature))`` (requires ``eth-utils``)."""
    from eth_utils import keccak
    return keccak(text=signature)[:4].hex()


def has_selector(bytecode_hex: str, selector: str, strict: bool = False) -> bool:
    code = bytecode_hex.lower().replace("0x", "")
    sel = selector.lower().replace("0x", "")
    return (("63" + sel) in code) if strict else (sel in code)


def identify(bytecode_hex: str, strict: bool = False) -> List[str]:
    """Names of the features whose selector(s) appear in ``bytecode_hex``."""
    return [name for name, sels in FEATURES.items()
            if any(has_selector(bytecode_hex, s, strict) for s in sels)]


def is_batch_candidate(bytecode_hex: str, strict: bool = False) -> bool:
    return has_selector(bytecode_hex, SELECTORS["safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)"], strict)
