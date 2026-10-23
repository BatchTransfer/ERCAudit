// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x528a64f1e687f41857a881f8e96e6affcc9943cd
// Contract Name: SignGenerator



// ============================================================
// FILE: tests/EVM/SignGenerator.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SignGenerator {
    event MessageToSign(bytes32 messageHash);
    event SignatureResult(bytes signature);
    
    // Store the last generated message hash
    bytes32 public lastMessageHash;
    
    // Generate and sign message
    function signMessage(
        uint256 amount,
        uint256 expiration,
        address to
    ) external {
        bytes32 data = 0x0000000000000000000000000000000000000000000000000000000000000000;
        
        bytes32 messageHash = getMessageHash(
            amount,
            data,
            expiration,
            to
        );
        
        // Store the message hash
        lastMessageHash = messageHash;
        
        // Emit the message hash event
        emit MessageToSign(messageHash);
        
        // Trigger wallet signature
        bytes memory signature = abi.encodePacked(msg.sender, messageHash);
        emit SignatureResult(signature);
    }

    // Generate message hash for POL transfer
    function getMessageHash(
        uint256 amount,
        bytes32 data,
        uint256 expiration,
        address to
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            getDomainSeparator(),
            keccak256(abi.encode(
                keccak256("TransferWithSig(uint256 amount,bytes32 data,uint256 expiration,address to)"),
                amount,
                data,
                expiration,
                to
            ))
        ));
    }

    // Get domain separator
    function getDomainSeparator() public pure returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("Polygon"),
            keccak256("1"),
            137,
            address(0x0000000000000000000000000000000000001010)
        ));
    }

    // View function to get personal message hash
    function getPersonalMessageHash(bytes32 messageHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));
    }
} 