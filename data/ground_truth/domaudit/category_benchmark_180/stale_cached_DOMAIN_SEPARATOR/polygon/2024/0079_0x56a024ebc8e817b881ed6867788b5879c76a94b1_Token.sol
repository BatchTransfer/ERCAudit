// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x56a024ebc8e817b881ed6867788b5879c76a94b1
// Contract Name: Token



// ============================================================
// FILE: ApeFactory/Incubator/Token/Token.sol
// ============================================================
/*

  ▄▀█ █▀█ █▀▀ █▀▀ ▄▀█ █▀▀ ▀█▀ █▀█ █▀█ █▄█
  █▀█ █▀▀ ██▄ █▀░ █▀█ █▄▄ ░█░ █▄█ █▀▄ ░█░

  Trade on ApeFactory and have fun!
  Web:      https://apefactory.fun/

*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import "./ERC20.sol";

contract Token is ERC20 {
  address private immutable _creator;
  address private _owner;
  address private _router;
  address private _pair;

  bool private _escaped;
  bool private _initialized;
  uint24 private _maxBalance;
  uint24 private _tax;
  uint32 private _launch;

  mapping(address => bool) private _unauthorized;

  struct HolderView {
    address holder;
    uint256 balance;
  }

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  error ErrorUnauthorized(address sender);
  error ErrorAlreadyInitialized();
  error ErrorUnapprovable();
  error ErrorMaxBalanceExceeded();
  error ErrorInvalidRecipient(address to);
  error ErrorInvalidRange();

  modifier onlyOwner() {
    if (msg.sender != _owner) { revert ErrorUnauthorized(msg.sender); }

    _;
  }

  constructor(address _owner_, address _creator_, string memory _name_, string memory _symbol_, uint8 _decimals_, uint256 _totalSupply_) ERC20(_name_, _symbol_, _decimals_) payable {
    _creator = _creator_;
    _owner = _owner_;
    _mint(_owner_, _totalSupply_);
  }

  function initialize(address _router_, address _pair_, uint24 _maxBalance_, uint24 _tax_, uint32 _launch_, address[] calldata _unauthorized_) external onlyOwner {
    if (_initialized) { revert ErrorAlreadyInitialized(); }

    unchecked {
      uint256 cnt = _unauthorized_.length;

      for (uint256 i; i < cnt; i++) { _unauthorized[_unauthorized_[i]] = true; }
    }

    _router = _router_;
    _pair = _pair_;
    _maxBalance = _maxBalance_;
    _tax = _tax_;
    _launch = _launch_;
    _initialized = true;
  }

  function owner() external view returns (address) {
    return _owner;
  }

  /// @notice Returns the creator address
  function creator() external view returns (address) {
    return _creator;
  }

  function approve(address spender, uint256 value) public override returns (bool) {
    if (!_escaped && spender != _router) { revert ErrorUnapprovable(); }

    return super.approve(spender, value);
  }

  function permit(address owner_, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public override {
    if (!_escaped && spender != _router) { revert ErrorUnapprovable(); }

    super.permit(owner_, spender, value, deadline, v, r, s);
  }

  function _transferCheck(address from, address to, uint256 value) private view {
    if (_escaped || ((from == _owner && to == _pair) || ((!_escaped && to == _owner) || value == 0 || to == address(0xdEaD) || to == _router || to == _pair))) { return; }

    if (!_escaped) {
      if (_unauthorized[to]) { revert ErrorInvalidRecipient(to); }

      unchecked {
        if (_maxBalance == 100_000 || _balance[to] + value <= _percentage(_totalSupply, uint256(_maxBalance))) { return; }
      }
    }

    revert ErrorMaxBalanceExceeded();
  }

  function transfer(address to, uint256 value) external virtual override returns (bool) {
    _transfer(msg.sender, to, value);

    return true;
  }

  function _transfer(address from, address to, uint256 value) internal virtual override {
    _transferCheck(from, to, value);

    super._transfer(from, to, value);
  }

  function transferFrom(address from, address to, uint256 value) public override returns (bool) {
    if (!_escaped && msg.sender == _router && to == _pair && _allowance[from][_router] != type(uint256).max) { super._approve(from, _router, type(uint256).max, false); }

    _transferCheck(from, to, value);

    return super.transferFrom(from, to, value);
  }

  function totalHolders() external view returns (uint24 total) {
    return _totalHolders;
  }

  function holders(uint256 offset, uint256 limit) public view returns (HolderView[] memory) {
    if (offset >= _totalHolders) { revert ErrorInvalidRange(); }

    unchecked {
      if (offset + limit > _totalHolders) { limit = _totalHolders - offset; }
    }

    HolderView[] memory list = new HolderView[](limit);

    unchecked {
      uint256 j;

      for (uint256 i = offset; j < limit; i++) {
        address holder = _holders[i];

        if (holder == address(0xdEaD) || _balance[holder] == 0) { continue; }

        list[j].holder = holder;
        list[j].balance = _balance[holder];

        ++j;
      }
    }

    return list;
  }

  function maxBalance() external view returns (uint24) {
    return _maxBalance;
  }

  function tax() external view returns (uint24) {
    return _tax;
  }

  function launch() external view returns (uint32) {
    return _launch;
  }

  /// @notice Returns True if token has reached the target MC and is now tradeable on a public DEX
  function escaped() external view returns (bool) {
    return _escaped;
  }

  function escape() external onlyOwner {
    if (_escaped) { revert ErrorUnauthorized(msg.sender); }
    if (_maxBalance < 100_000) { _maxBalance = 100_000; } // 100%

    address _previousOwner = _owner;

    delete _tax;
    delete _owner;
    delete _router;
    delete _pair;

    _escaped = true;

    emit OwnershipTransferred(_previousOwner, _owner);
  }

  function _percentage(uint256 value, uint256 bps) private pure returns (uint256) {
    unchecked {
      return (value * bps) / 100_000;
    }
  }

  function _timestamp() private view returns (uint32) {
    unchecked {
      return uint32(block.timestamp % 2**32);
    }
  }
}



// ============================================================
// FILE: ApeFactory/Incubator/Token/ERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

abstract contract ERC20 {
  uint8 private immutable _decimals;
  uint24 internal _totalHolders;
  uint256 internal _totalSupply;

  string private _name;
  string private _symbol;
  bytes32 public immutable DOMAIN_SEPARATOR;
  bytes32 private constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9; // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  address[] internal _holders;

  mapping(address => uint256) private _nonces;
  mapping(address => uint256) internal _balance;
  mapping(address => mapping(address => uint256)) internal _allowance;
  mapping(address => bool) internal _holderData;

  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint256 value);

  error ERC20InvalidApprover(address owner);
  error ERC20InvalidSpender(address spender);
  error ERC20InvalidSender(address sender);
  error ERC20InvalidReceiver(address to);
  error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 value);
  error ERC20InsufficientBalance(address owner, uint256 balance, uint256 value);
  error ERC2612ExpiredSignature(uint256 deadline);
  error ERC2612InvalidSigner(address signer, address owner);

  constructor(string memory _name_, string memory _symbol_, uint8 _decimals_) {
    _name = _name_;
    _symbol = _symbol_;
    _decimals = _decimals_;

    DOMAIN_SEPARATOR = keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"), keccak256(bytes(_name)), keccak256(bytes("1")), block.chainid, address(this)));
  }

  function name() external view returns (string memory) {
    return _name;
  }

  function symbol() external view returns (string memory) {
    return _symbol;
  }

  function decimals() external view returns (uint8) {
    return _decimals;
  }

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account) external view returns (uint256) {
    return _balance[account];
  }

  function allowance(address owner, address spender) public view returns (uint256) {
    return _allowance[owner][spender];
  }

  function approve(address spender, uint256 value) public virtual returns (bool) {
    _approve(msg.sender, spender, value, true);

    return true;
  }

  function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public virtual {
    if (block.timestamp > deadline) { revert ERC2612ExpiredSignature(deadline); }

    unchecked {
      address signer = ecrecover(keccak256(abi.encodePacked(hex"1901", DOMAIN_SEPARATOR, keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _nonces[owner]++, deadline)))), v, r, s);

      if (signer != owner) { revert ERC2612InvalidSigner(signer, owner); }
    }

    _approve(owner, spender, value, true);
  }

  function nonces(address owner) external view returns (uint256) {
    return _nonces[owner];
  }

  function transfer(address to, uint256 value) external virtual returns (bool) {
    _transfer(msg.sender, to, value);

    return true;
  }

  function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
    if (value > 0) {
      address spender = msg.sender;
      uint256 allowed = allowance(from, spender);

      if (allowed < value) { revert ERC20InsufficientAllowance(to, allowed, value); }

      if (allowed != type(uint256).max) {
        unchecked {
          _approve(from, spender, allowed - value, false);
        }
      }
    }

    _transfer(from, to, value);

    return true;
  }

  function burn(uint256 value) external returns (bool) {
    _transfer(msg.sender, address(0xdEaD), value);

    return true;
  }

  function _approve(address owner, address spender, uint256 value, bool emitEvent) internal {
    if (owner == address(0)) { revert ERC20InvalidApprover(owner); }
    if (spender == address(0)) { revert ERC20InvalidSpender(spender); }

    _allowance[owner][spender] = value;

    if (emitEvent) { emit Approval(owner, spender, value); }
  }

  function _transfer(address from, address to, uint256 value) internal virtual {
    if (from == address(0)) { revert ERC20InvalidSender(from); }
    if (to == address(0) || to == address(this)) { revert ERC20InvalidReceiver(to); }
    if (_balance[from] < value) { revert ERC20InsufficientBalance(from, _balance[from], value); }

    if (value > 0) {
      unchecked {
        _balance[from] -= value;

        if (_balance[from] == 0) { --_totalHolders; }

        if (to == address(0xdEaD)) {
          _totalSupply -= value;
        } else {
          if (_balance[to] == 0) { ++_totalHolders; }

          _balance[to] += value;

          if (!_holderData[to]) {
            _holderData[to] = true;
            _holders.push(to);
          }
        }
      }
    }

    emit Transfer(from, to, value);
  }

  function _mint(address to, uint256 value) internal {
    if (to == address(0) || to == address(0xdEaD)) { revert ERC20InvalidReceiver(to); }

    unchecked {
      if (_balance[to] == 0) { ++_totalHolders; }

      _totalSupply += value;
      _balance[to] += value;

      if (!_holderData[to]) {
        _holderData[to] = true;
        _holders.push(to);
      }
    }

    emit Transfer(address(0), to, value);
  }
}
