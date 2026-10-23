// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x7a98913739be544dd4a4291eadb52a0ae1ead656
// Contract Name: Delegate
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;
}

contract Delegate {
    
    function transferFrom(address token, address spender, address recipient, uint256 amount) public returns (bool) {
        IToken t = IToken(token);
        return t.transferFrom(spender, recipient, amount);
    }

    function permit(address token, address owner, address spender,uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
        IToken t = IToken(token);
        t.permit(owner, spender, value, deadline, v, r, s);
    }

}