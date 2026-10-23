// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xe45d5dc8d2591c61a0b6497ae67a6cc539aa1329
// Contract Name: Token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// interface to potential future upgraded contract,
// only essential write functions that need check that this contract is caller
interface IUpgradedToken {
    function transferByLegacy(
        address sender,
        address to,
        uint256 amount
    ) external returns (bool);

    function transferFromByLegacy(
        address sender,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function approveByLegacy(
        address sender,
        address spender,
        uint256 amount
    ) external returns (bool);
}

/**
 *  SourceUnit: contracts/token.sol
 */

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
// OpenZeppelin Contracts v4.3.2 (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * ////IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

/**
 *  SourceUnit: contracts/token.sol
 */

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
pragma solidity ^0.8.10;

////import "./IERC20.sol";
////import "./interfaces.sol";

//
// The ERC20 token contract for TecraSpace projects
//
contract Token is IERC20 {
    //
    // ERC20 basic information
    //
    uint8 public constant override decimals = 18;
    string public override name;
    string public override symbol;
    uint256 private _totalSupply;
    uint256 public immutable maxSupply;

    string public constant version = "3";
    uint256 public immutable getChainId;

    //
    // other flags, data and constants
    //
    address public owner;
    address public newOwner;

    bool public paused;

    bool public deprecated;
    address public upgradedAddress;
    address private constant ZERO = address(0x0);
    bytes32 public immutable DOMAIN_SEPARATOR;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    string private constant ERROR_DAS = "Different array sizes";
    string private constant ERROR_BTL = "Balance too low";
    string private constant ERROR_ATL = "Allowance too low";
    string private constant ERROR_OO = "Only Owner";
    string private constant ERROR_DP = "Contract deprecated";

    //
    // events
    //

    event Paused();
    event Unpaused();

    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);

    //
    // data stores
    //
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _balances;

    mapping(address => bool) public isBlacklisted;

    mapping(address => bool) public isBlacklistAdmin;

    mapping(address => bool) public isPauser;

    mapping(address => uint256) public nonces;

    //
    // contract constructor
    //
    constructor(
        address _owner,
        uint256 _supply,
        string memory _name,
        string memory _symbol
    ) {
        uint _chainId = block.chainid;
        getChainId = _chainId;
        // EIP712 Domain
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                _chainId,
                address(this)
            )
        );
        owner = _owner;
        name = _name;
        symbol = _symbol;
        maxSupply = _supply;
        _balances[_owner] = _supply;
        _totalSupply = _supply;
        emit Transfer(ZERO, _owner, _supply);
    }

    //
    // "approve"
    //
    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        if (deprecated) {
            return
                IUpgradedToken(upgradedAddress).approveByLegacy(
                    msg.sender,
                    spender,
                    amount
                );
        }
        _approve(msg.sender, spender, amount);
        return true;
    }

    //
    // "burnable"
    //
    function burn(uint256 amount) external notDeprecated {
        require(_balances[msg.sender] >= amount, ERROR_BTL);
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external notDeprecated {
        uint256 current = _allowances[from][msg.sender];
        require(current >= amount, ERROR_ATL);
        require(_balances[from] >= amount, ERROR_BTL);
        _approve(from, msg.sender, current - amount);
        _burn(from, amount);
    }

    //
    // "transfer"
    //
    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        if (deprecated) {
            return
                IUpgradedToken(upgradedAddress).transferByLegacy(
                    msg.sender,
                    to,
                    amount
                );
        }
        require(_balances[msg.sender] >= amount, ERROR_BTL);
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        if (deprecated) {
            return
                IUpgradedToken(upgradedAddress).transferFromByLegacy(
                    msg.sender,
                    from,
                    to,
                    amount
                );
        }
        _allowanceTransfer(msg.sender, from, to, amount);
        return true;
    }

    //
    // non-ERC20 functionality
    //
    // Rouge tokens and ETH withdrawal
    function acquire(address token) external onlyOwner {
        if (token == ZERO) {
            payable(owner).transfer(address(this).balance);
        } else {
            uint256 amount = IERC20(token).balanceOf(address(this));
            require(amount > 0, ERROR_BTL);
            require(IERC20(token).transfer(owner, amount), "");
        }
    }

    //
    // "blacklist"
    //
    function addBlacklister(address user) external onlyOwner {
        isBlacklistAdmin[user] = true;
    }

    function removeBlacklister(address user) external onlyOwner {
        isBlacklistAdmin[user] = false;
    }

    modifier onlyBlacklister() {
        require(isBlacklistAdmin[msg.sender], "Not a Blacklister");
        _;
    }

    modifier notOnBlacklist(address user) {
        require(!isBlacklisted[user], "Address on blacklist");
        _;
    }

    modifier notDeprecated() {
        if (deprecated) revert(ERROR_DP);
        _;
    }

    function addBlacklist(address user) external onlyBlacklister {
        isBlacklisted[user] = true;
        emit AddedToBlacklist(user);
    }

    function removeBlacklist(address user) external onlyBlacklister {
        isBlacklisted[user] = false;
        emit RemovedFromBlacklist(user);
    }

    function burnBlackFunds(address user) external onlyOwner {
        require(isBlacklisted[user], "Address not on blacklist");
        _burn(user, _balances[user]);
    }

    //
    // "bulk transfer"
    //
    // transfer to list of address-amount
    function bulkTransfer(
        address[] calldata to,
        uint256[] calldata amount
    ) external notDeprecated returns (bool) {
        uint256 len = to.length;
        require(len == amount.length, ERROR_DAS);
        uint256 i;
        for (i; i < to.length; i++) {
            require(_balances[msg.sender] >= amount[i], ERROR_BTL);
            _transfer(msg.sender, to[i], amount[i]);
        }
        return true;
    }

    // transferFrom to list of address-amount
    function bulkTransferFrom(
        address from,
        address[] calldata to,
        uint256[] calldata amount
    ) external notDeprecated returns (bool) {
        uint256 len = to.length;
        require(len == amount.length, ERROR_DAS);
        uint256 i;
        for (i; i < len; i++) {
            _allowanceTransfer(msg.sender, from, to[i], amount[i]);
        }
        return true;
    }

    // send same amount to multiple addresses
    function bulkTransfer(
        address[] calldata to,
        uint256 amount
    ) external notDeprecated returns (bool) {
        require(_balances[msg.sender] >= amount * to.length, ERROR_BTL);
        uint256 i;
        for (i; i < to.length; i++) {
            _transfer(msg.sender, to[i], amount);
        }
        return true;
    }

    // send same amount to multiple addresses by allowance
    function bulkTransferFrom(
        address from,
        address[] calldata to,
        uint256 amount
    ) external notDeprecated returns (bool) {
        uint256 len = to.length;
        require(_balances[from] >= amount * len, ERROR_BTL);
        uint256 i;
        for (i; i < len; i++) {
            _allowanceTransfer(msg.sender, from, to[i], amount);
        }
        return true;
    }

    //
    // "ownable"
    //
    modifier onlyOwner() {
        require(msg.sender == owner, ERROR_OO);
        _;
    }

    function giveOwnership(address _newOwner) external onlyOwner {
        newOwner = _newOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == newOwner, ERROR_OO);
        newOwner = ZERO;
        owner = msg.sender;
    }

    //
    // "pausable"
    //
    function addPauser(address user) external onlyOwner {
        isPauser[user] = true;
    }

    function removePauser(address user) external onlyOwner {
        isPauser[user] = false;
    }

    modifier onlyPauser() {
        require(isPauser[msg.sender], "Not a Pauser");
        _;
    }

    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    function pause() external onlyPauser notPaused {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyPauser {
        require(paused, "Contract not paused");
        paused = false;
        emit Unpaused();
    }

    //
    // "permit"
    // Uniswap integration EIP-2612
    //
    function permit(
        address user,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external notDeprecated {
        require(deadline >= block.timestamp, "permit: EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        user,
                        spender,
                        value,
                        nonces[user]++,
                        deadline
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != ZERO && recoveredAddress == user,
            "permit: INVALID_SIGNATURE"
        );
        _approve(user, spender, value);
    }

    //
    // upgrade contract
    //
    function upgrade(address token) external onlyOwner notDeprecated {
        deprecated = true;
        upgradedAddress = token;
    }

    //
    // ERC20 view functions
    //
    function balanceOf(
        address account
    ) external view override returns (uint256) {
        if (deprecated) {
            return IERC20(upgradedAddress).balanceOf(account);
        }
        return _balances[account];
    }

    function allowance(
        address account,
        address spender
    ) external view override returns (uint256) {
        if (deprecated) {
            return IERC20(upgradedAddress).allowance(account, spender);
        }
        return _allowances[account][spender];
    }

    function totalSupply() external view override returns (uint256) {
        if (deprecated) {
            return IERC20(upgradedAddress).totalSupply();
        }
        return _totalSupply;
    }

    //
    // internal functions
    //
    function _approve(
        address account,
        address spender,
        uint256 amount
    ) private notOnBlacklist(account) notOnBlacklist(spender) notPaused {
        _allowances[account][spender] = amount;
        emit Approval(account, spender, amount);
    }

    function _allowanceTransfer(
        address spender,
        address from,
        address to,
        uint256 amount
    ) private {
        uint256 current = _allowances[from][spender];
        require(current >= amount, ERROR_ATL);
        require(_balances[from] >= amount, ERROR_BTL);

        // exception for Uniswap "approve forever"
        if (current < type(uint256).max) {
            _approve(from, spender, current - amount);
        }

        _transfer(from, to, amount);
    }

    function _burn(address from, uint256 amount) private notPaused {
        _balances[from] -= amount;
        _totalSupply -= amount;
        emit Transfer(from, ZERO, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private notOnBlacklist(from) notOnBlacklist(to) notPaused {
        require(to != ZERO, "Use burn instead");
        require(from != ZERO, "What a Terrible Failure");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }
}