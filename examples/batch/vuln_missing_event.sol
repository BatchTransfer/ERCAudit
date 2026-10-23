// SPDX-License-Identifier: MIT
// Synthetic example for ERCAudit: TransferBatch never emitted
pragma solidity ^0.8.20;

interface IERC1155Receiver {
    function onERC1155BatchReceived(
        address operator, address from, uint256[] calldata ids,
        uint256[] calldata values, bytes calldata data) external returns (bytes4);
}

contract Example1155 {
    mapping(uint256 => mapping(address => uint256)) private _balances;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event TransferBatch(address indexed operator, address indexed from, address indexed to,
                        uint256[] ids, uint256[] values);

    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function safeBatchTransferFrom(
        address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data
    ) public {
        require(from == msg.sender || isApprovedForAll(from, msg.sender), "not owner nor approved");
        require(to != address(0), "transfer to zero address");
        require(ids.length == amounts.length, "length mismatch");
        _update(from, to, ids, amounts);
        _doSafeBatchTransferAcceptanceCheck(msg.sender, from, to, ids, amounts, data);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory amounts) internal {
        for (uint256 i = 0; i < ids.length; i++) {
            require(_balances[ids[i]][from] >= amounts[i], "insufficient balance");
            _balances[ids[i]][from] -= amounts[i];
            _balances[ids[i]][to] += amounts[i];
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator, address from, address to, uint256[] memory ids,
        uint256[] memory amounts, bytes memory data
    ) private {
        if (to.code.length > 0) {
            require(
                IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data)
                    == IERC1155Receiver.onERC1155BatchReceived.selector,
                "receiver rejected");
        }
    }
}
