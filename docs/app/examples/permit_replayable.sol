// SPDX-License-Identifier: MIT
// Synthetic example for ERCAudit, modelled on the signing-domain study:
// the domain hard-codes chainId (R3), binds a foreign verifier (R6) and is cached (R8).
pragma solidity ^0.8.20;

contract ReplayablePermitToken {
    string public name = "ReplayablePermitToken";
    uint256 private constant CHAIN_ID = 1;   // hard-coded: wrong after a fork or on another chain
    address public constant SOURCE_VERIFIER = 0x1111111111111111111111111111111111111111;
    mapping(address => uint256) public nonces;
    mapping(address => mapping(address => uint256)) public allowance;
    bytes32 public DOMAIN_SEPARATOR;

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            DOMAIN_TYPEHASH, keccak256(bytes(name)), CHAIN_ID, SOURCE_VERIFIER));
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline,
                    uint8 v, bytes32 r, bytes32 s) external {
        require(block.timestamp <= deadline, "expired");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        require(ecrecover(digest, v, r, s) == owner, "bad signature");
        allowance[owner][spender] = value;
    }
}
