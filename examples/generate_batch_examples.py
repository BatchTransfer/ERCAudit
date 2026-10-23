#!/usr/bin/env python3
"""Generate the synthetic BatchAudit examples (one compliant template + single-defect mutants).

The template follows Listing 1 of the BatchAudit paper. Each mutant removes exactly
one check, so the analyzer must report exactly the corresponding constraint.
These are *test inputs written for this artifact*, not deployed contracts.
"""
from pathlib import Path

TEMPLATE = """// SPDX-License-Identifier: MIT
// Synthetic example for ERCAudit: {title}
pragma solidity ^0.8.20;

interface IERC1155Receiver {{
    function onERC1155BatchReceived(
        address operator, address from, uint256[] calldata ids,
        uint256[] calldata values, bytes calldata data) external returns (bytes4);
}}

contract Example1155 {{
    mapping(uint256 => mapping(address => uint256)) private _balances;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event TransferBatch(address indexed operator, address indexed from, address indexed to,
                        uint256[] ids, uint256[] values);

    function isApprovedForAll(address account, address operator) public view returns (bool) {{
        return _operatorApprovals[account][operator];
    }}

    function safeBatchTransferFrom(
        address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data
    ) public {{
{auth}{zero}{length}        _update(from, to, ids, amounts);
{event}{hook}    }}

    function _update(address from, address to, uint256[] memory ids, uint256[] memory amounts) internal {{
        for (uint256 i = 0; i < ids.length; i++) {{
            require(_balances[ids[i]][from] >= amounts[i], "insufficient balance");
            _balances[ids[i]][from] -= amounts[i];
            _balances[ids[i]][to] += amounts[i];
        }}
    }}

    function _doSafeBatchTransferAcceptanceCheck(
        address operator, address from, address to, uint256[] memory ids,
        uint256[] memory amounts, bytes memory data
    ) private {{
        if (to.code.length > 0) {{
            require(
                IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data)
                    == IERC1155Receiver.onERC1155BatchReceived.selector,
                "receiver rejected");
        }}
    }}
}}
"""

PARTS = dict(
    auth='        require(from == msg.sender || isApprovedForAll(from, msg.sender), "not owner nor approved");\n',
    zero='        require(to != address(0), "transfer to zero address");\n',
    length='        require(ids.length == amounts.length, "length mismatch");\n',
    event='        emit TransferBatch(msg.sender, from, to, ids, amounts);\n',
    hook='        _doSafeBatchTransferAcceptanceCheck(msg.sender, from, to, ids, amounts, data);\n',
)

VARIANTS = {
    "compliant.sol": ("compliant implementation (all eight constraints hold)", {}),
    "vuln_missing_access_control.sol": ("no sender / operator authorisation", {"auth": ""}),
    "vuln_missing_address_validation.sol": ("recipient may be the zero address", {"zero": ""}),
    "vuln_missing_array_length_check.sol": ("ids/amounts lengths never compared", {"length": ""}),
    "vuln_missing_event.sol": ("TransferBatch never emitted", {"event": ""}),
    "vuln_missing_receiver_hook.sol": ("recipient contracts are never asked to accept", {"hook": ""}),
}

out = Path(__file__).parent / "batch"
out.mkdir(exist_ok=True)
for name, (title, drop) in VARIANTS.items():
    parts = {k: ("" if k in drop else v) for k, v in PARTS.items()}
    (out / name).write_text(TEMPLATE.format(title=title, **parts))
print(f"wrote {len(VARIANTS)} examples to {out}")
