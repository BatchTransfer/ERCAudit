"""ABI calldata decoders for the four call types the transaction validator inspects.

Cleaned from ``erc1155_safeBatch_TXNanalysis.py``. All decoders take the ``input``
field of an Etherscan ``txlist`` row and raise :class:`ValueError` on malformed
payloads.
"""
from __future__ import annotations

from typing import List, Tuple

#: 4-byte selectors (``bytes4(keccak256(signature))``).
SELECTORS = {
    "safeBatchTransferFrom": "0x2eb2c2d6",  # (address,address,uint256[],uint256[],bytes)
    "setApprovalForAll": "0xa22cb465",      # (address,bool)
    "approve": "0x095ea7b3",                # (address,uint256)
    "transferFrom": "0x23b872dd",           # (address,address,uint256)
}

ZERO_ADDRESS = "0x" + "0" * 40


def _params(input_hex: str, min_words: int) -> str:
    data = input_hex[2:] if input_hex.startswith("0x") else input_hex
    if len(data) < 8 + 64 * min_words:  # 4-byte selector + N 32-byte words
        raise ValueError("Input too short")
    return data[8:]


def _address(word: str) -> str:
    return "0x" + word[-40:]


def decode_transferFrom_input(input_hex: str) -> Tuple[str, str, int]:
    """``transferFrom(from, to, value)``."""
    p = _params(input_hex, 3)
    return _address(p[0:64]), _address(p[64:128]), int(p[128:192], 16)


def decode_safeBatchTransferFrom_input(input_hex: str) -> Tuple[str, str, List[int], List[int]]:
    """``safeBatchTransferFrom(from, to, ids[], amounts[], data)`` -> ``(from, to, ids, amounts)``."""
    p = _params(input_hex, 5)
    ids_off = int(p[128:192], 16)
    amts_off = int(p[192:256], 16)

    def decode_array(offset: int) -> List[int]:
        start = offset * 2
        length = int(p[start:start + 64], 16)
        ptr = start + 64
        items = []
        for _ in range(length):
            items.append(int(p[ptr:ptr + 64], 16))
            ptr += 64
        return items

    return _address(p[0:64]), _address(p[64:128]), decode_array(ids_off), decode_array(amts_off)


def decode_setApprovalForAll_input(input_hex: str) -> Tuple[str, bool]:
    """``setApprovalForAll(operator, approved)``."""
    p = _params(input_hex, 2)
    return _address(p[0:64]), int(p[64:128], 16) != 0


def decode_approve_input(input_hex: str) -> Tuple[str, bool]:
    """``approve(spender, value)`` -> ``(spender, value != 0)``."""
    p = _params(input_hex, 2)
    return _address(p[0:64]), int(p[64:128], 16) != 0


def encode_safeBatchTransferFrom(from_addr: str, to_addr: str, ids: List[int], amounts: List[int]) -> str:
    """Build calldata for tests and examples (``data`` is encoded as empty ``bytes``)."""
    def word(v: int) -> str:
        return format(v, "064x")

    def addr(a: str) -> str:
        return a.lower().replace("0x", "").rjust(64, "0")

    head = [addr(from_addr), addr(to_addr)]
    ids_off = 5 * 32
    amts_off = ids_off + 32 + 32 * len(ids)
    data_off = amts_off + 32 + 32 * len(amounts)
    head += [word(ids_off), word(amts_off), word(data_off)]
    body = [word(len(ids))] + [word(i) for i in ids] + [word(len(amounts))] + [word(a) for a in amounts] + [word(0)]
    return "0x" + SELECTORS["safeBatchTransferFrom"][2:] + "".join(head + body)
