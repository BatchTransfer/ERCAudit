// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x00000976122a907cb19a509b58b7bc0e32b00000
// Contract Name: Antidrain



// ============================================================
// FILE: Antidrain.sol
// ============================================================
/* SPDX-License-Identifier: MIT */
pragma solidity ^0.8.34;

/**
 * @title  Antidrain
 * @author Zun
 * @notice EIP-7702 rescue relay. Compromised EOAs delegate to this contract;
 *         a sponsor relays the victim's signed intent, the account executes the
 *         claim or transfer, and a 20 % fee is collected.
 * @dev    Storage uses ERC-7201 namespacing so delegated EOAs never collide.
 *         Reentrancy is guarded via EIP-1153 transient storage.
 * @custom:version 1
 * @custom:website https://antidrain.dev
 * @custom:chrome-extension https://chromewebstore.google.com/detail/mfbelfelhpleekkcnhddkcnocglcgddm
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract Antidrain {

    /*//////////////////////////////////////////////////////////////
                          IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Canonical address of this deployment, embedded in bytecode.
     *      `address(this) == _SELF` → contract context; otherwise delegated EOA context.
     */
    address private immutable _SELF;

    /*//////////////////////////////////////////////////////////////
                          CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant FEE_BPS   = 2000;
    uint256 public constant BPS_DENOM = 10000;
    uint256 public constant MAX_TOKENS = 50;

    string public constant NAME    = "Antidrain";
    string public constant VERSION = "1";

    bytes32 private constant NAME_HASH    = keccak256(bytes(NAME));
    bytes32 private constant VERSION_HASH = keccak256(bytes(VERSION));

    /*//////////////////////////////////////////////////////////////
                           STORAGE
    //////////////////////////////////////////////////////////////*/

    /** @notice Per-(account, sponsor) nonce. Allows concurrent sponsors without conflicts. */
    mapping(address account => mapping(address sponsor => uint256)) public accountNonces;

    /*//////////////////////////////////////////////////////////////
                          EIP-712
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private constant CLAIM_TRANSFER_TYPEHASH = keccak256(
        "ClaimAndTransfer(address safeRecipient,address token,address claimTarget,bytes32 claimDataHash,address feeWallet,address antidrain,address sponsor,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant CLAIM_TRANSFER_NATIVE_TYPEHASH = keccak256(
        "ClaimAndTransferNative(address safeRecipient,address claimTarget,bytes32 claimDataHash,address feeWallet,address antidrain,address sponsor,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant TRANSFER_TOKEN_TYPEHASH = keccak256(
        "TransferToken(address safeRecipient,bytes32 tokensHash,address feeWallet,address antidrain,address sponsor,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant TRANSFER_NATIVE_TYPEHASH = keccak256(
        "TransferNative(address safeRecipient,address feeWallet,address antidrain,address sponsor,uint256 nonce,uint256 deadline)"
    );

    /*//////////////////////////////////////////////////////////////
                   ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    /** @custom:storage-location erc7201:Antidrain.storage.v1 */
    struct AntidrainStorage {
        address owner;
        address feeWallet;
        bool paused;
        mapping(address => bool) blocked;
    }

    /**
     * @dev keccak256(abi.encode(uint256(keccak256("erc7201:Antidrain.storage.v1")) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    bytes32 private constant STORAGE_SLOT =
        0xbbac9eadf5fb166423fcee9db3114a5e3a54170809e0b73067b27e1cedc1d400;

    function _getStorage() private pure returns (AntidrainStorage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly { $.slot := slot }
    }

    /*//////////////////////////////////////////////////////////////
                           EVENTS
    //////////////////////////////////////////////////////////////*/

    event Rescued(
        address indexed account,
        address indexed safeRecipient,
        address indexed token,
        uint256 userAmount,
        uint256 feeAmount
    );
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event AccountBlocked(address indexed account);
    event AccountUnblocked(address indexed account);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FeeWalletUpdated(address indexed previousFeeWallet, address indexed newFeeWallet);

    /*//////////////////////////////////////////////////////////////
                           ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRecipient();
    error InvalidToken();
    error InvalidClaimTarget();
    error SelfRecipient();
    error TooManyTokens();
    error InvalidSignature();
    error SignatureExpired();
    error ClaimFailed();
    error TransferFailed();
    error NoBalance();
    error ExecuteFailed(bytes reason);
    error Unauthorized();
    error ContractPaused();
    error AccountIsBlocked();
    error NotDelegatedToAntidrain();
    error Reentrancy();

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy the Antidrain contract with initial owner and fee wallet.
     * @param initialOwner The address that will own this contract.
     * @param initialFeeWallet The address that will receive fees.
     */
    constructor(address initialOwner, address initialFeeWallet) {
        if (initialOwner == address(0)) revert InvalidRecipient();
        if (initialFeeWallet == address(0)) revert InvalidRecipient();
        _SELF = address(this);
        AntidrainStorage storage $ = _getStorage();
        $.owner = initialOwner;
        $.feeWallet = initialFeeWallet;
    }

    /*//////////////////////////////////////////////////////////////
                         MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /** @dev EIP-1153 transient-storage reentrancy guard. Costs ~100 gas vs ~5 000 for SSTORE. */
    modifier nonReentrant() {
        bool entered;
        assembly { entered := tload(0) }
        if (entered) revert Reentrancy();
        assembly { tstore(0, 1) }
        _;
        assembly { tstore(0, 0) }
    }

    /** @dev Restricts to the contract owner stored in ERC-7201 namespaced storage. */
    modifier onlyOwner() {
        if (msg.sender != _getStorage().owner) revert Unauthorized();
        _;
    }

    /** @dev Restricts to contract context only. Reverts when called via delegated EOA. */
    modifier onlySelf() {
        if (address(this) != _SELF) revert Unauthorized();
        _;
    }

    /** @dev Reverts if the contract is paused. */
    modifier whenNotPaused() {
        if (_getStorage().paused) revert ContractPaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                       VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function owner() public view returns (address) { return _getStorage().owner; }
    function feeWallet() public view returns (address) { return _getStorage().feeWallet; }
    function paused() public view returns (bool) { return _getStorage().paused; }
    function blocked(address account) public view returns (bool) { return _getStorage().blocked[account]; }

    /**
     * @param account  The delegated EOA address.
     * @param sponsor  The sponsor (relayer) address.
     * @return         The current nonce for the (account, sponsor) pair.
     */
    function getNonce(address account, address sponsor) external view returns (uint256) {
        return accountNonces[account][sponsor];
    }

    /*//////////////////////////////////////////////////////////////
               TOKEN RECEIVER HOOKS (DELEGATED EOA)
    //////////////////////////////////////////////////////////////*/

    /** @dev Allows delegated EOAs to receive ERC-721 safe transfers. */
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (address(this) == _SELF) revert Unauthorized();
        return 0x150b7a02;
    }

    /** @dev Allows delegated EOAs to receive ERC-1155 safe transfers. */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        if (address(this) == _SELF) revert Unauthorized();
        return 0xf23a6e61;
    }

    /** @dev Allows delegated EOAs to receive ERC-1155 batch transfers. */
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external view returns (bytes4) {
        if (address(this) == _SELF) revert Unauthorized();
        return 0xbc197c81;
    }

    /**
     * @notice EIP-1271 signature validation for delegated EOAs.
     * @dev    Enables DeFi protocols to verify the EOA's ECDSA signature via the
     *         standard smart-contract-wallet interface. Reverts in contract context.
     * @param  hash      The hash that was signed.
     * @param  signature The 65-byte ECDSA signature (r, s, v).
     * @return           `0x1626ba7e` if valid, `0xffffffff` otherwise.
     */
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (address(this) == _SELF) revert Unauthorized();
        if (_recover(hash, signature) == address(this)) return 0x1626ba7e;
        return 0xffffffff;
    }

    /** @notice ERC-165 interface detection. */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7   /* ERC-165 */
            || interfaceId == 0x150b7a02   /* ERC-721 Receiver */
            || interfaceId == 0x4e2312e0   /* ERC-1155 Receiver */
            || interfaceId == 0x1626ba7e;  /* ERC-1271 */
    }

    /*//////////////////////////////////////////////////////////////
                  RELAY ENTRY POINTS (SPONSOR)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim an airdrop from `claimTarget`, then transfer the resulting
     *         ERC-20 balance to `safeRecipient` with a 20 % fee.
     * @dev    Runs in contract context → calls into the delegated EOA via `account.call`.
     * @param  account       The compromised EOA delegated to this contract.
     * @param  safeRecipient The victim's safe wallet that receives 80 % of the tokens.
     * @param  token         The ERC-20 token to rescue.
     * @param  claimTarget   The airdrop / vesting contract to call.
     * @param  claimData     The calldata for the claim call.
     * @param  deadline      Unix timestamp after which the signature is invalid.
     * @param  signature     The victim's 65-byte EIP-712 signature.
     */
    function rescueERC20(
        address account,
        address safeRecipient,
        address token,
        address claimTarget,
        bytes calldata claimData,
        uint256 deadline,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused {
        if (address(this) != _SELF) revert Unauthorized();
        if (safeRecipient == address(0)) revert InvalidRecipient();
        if (safeRecipient == account) revert SelfRecipient();
        if (token == address(0)) revert InvalidToken();
        if (claimTarget == address(0)) revert InvalidClaimTarget();
        if (deadline < block.timestamp) revert SignatureExpired();

        _verifyDelegation(account);
        address fw;
        {
            AntidrainStorage storage $ = _getStorage();
            if ($.blocked[account]) revert AccountIsBlocked();
            fw = $.feeWallet;
        }
        {
            uint256 nonce = accountNonces[account][msg.sender];
            bytes32 digest = keccak256(abi.encodePacked(
                "\x19\x01",
                _domainSeparator(account),
                keccak256(bytes.concat(
                    abi.encode(
                        CLAIM_TRANSFER_TYPEHASH,
                        safeRecipient,
                        token,
                        claimTarget,
                        keccak256(claimData)
                    ),
                    abi.encode(
                        fw,
                        _SELF,
                        msg.sender,
                        nonce,
                        deadline
                    )
                ))
            ));
            if (_recover(digest, signature) != account) revert InvalidSignature();
            accountNonces[account][msg.sender] = nonce + 1;
        }

        bytes memory payload = abi.encodeWithSelector(
            this.executeRescueERC20.selector,
            safeRecipient, token, claimTarget, claimData, fw
        );
        (bool success, bytes memory returndata) = account.call{value: msg.value}(payload);
        if (!success) _propagateRevert(returndata);
    }

    /**
     * @notice Claim an airdrop from `claimTarget`, then transfer the resulting
     *         native ETH balance to `safeRecipient` with a 20 % fee.
     * @dev    Runs in contract context → calls into the delegated EOA via `account.call`.
     * @param  account       The compromised EOA delegated to this contract.
     * @param  safeRecipient The victim's safe wallet that receives 80 % of ETH.
     * @param  claimTarget   The airdrop / vesting contract to call.
     * @param  claimData     The calldata for the claim call.
     * @param  deadline      Unix timestamp after which the signature is invalid.
     * @param  signature     The victim's 65-byte EIP-712 signature.
     */
    function rescueNative(
        address account,
        address safeRecipient,
        address claimTarget,
        bytes calldata claimData,
        uint256 deadline,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused {
        if (address(this) != _SELF) revert Unauthorized();
        if (safeRecipient == address(0)) revert InvalidRecipient();
        if (safeRecipient == account) revert SelfRecipient();
        if (claimTarget == address(0)) revert InvalidClaimTarget();
        if (deadline < block.timestamp) revert SignatureExpired();

        _verifyDelegation(account);
        address fw;
        {
            AntidrainStorage storage $ = _getStorage();
            if ($.blocked[account]) revert AccountIsBlocked();
            fw = $.feeWallet;
        }
        {
            uint256 nonce = accountNonces[account][msg.sender];
            bytes32 digest = keccak256(abi.encodePacked(
                "\x19\x01",
                _domainSeparator(account),
                keccak256(bytes.concat(
                    abi.encode(
                        CLAIM_TRANSFER_NATIVE_TYPEHASH,
                        safeRecipient,
                        claimTarget,
                        keccak256(claimData)
                    ),
                    abi.encode(
                        fw,
                        _SELF,
                        msg.sender,
                        nonce,
                        deadline
                    )
                ))
            ));
            if (_recover(digest, signature) != account) revert InvalidSignature();
            accountNonces[account][msg.sender] = nonce + 1;
        }

        bytes memory payload = abi.encodeWithSelector(
            this.executeRescueNative.selector,
            safeRecipient, claimTarget, claimData, fw
        );
        (bool success, bytes memory returndata) = account.call{value: msg.value}(payload);
        if (!success) _propagateRevert(returndata);
    }

    /**
     * @notice Transfer one or more ERC-20 tokens already held by the EOA to
     *         `safeRecipient` with a 20 % fee. No claim step.
     * @dev    Runs in contract context → calls into the delegated EOA via `account.call`.
     * @param  account       The compromised EOA delegated to this contract.
     * @param  safeRecipient The victim's safe wallet.
     * @param  tokens        Array of ERC-20 token addresses (max 50).
     * @param  deadline      Unix timestamp after which the signature is invalid.
     * @param  signature     The victim's 65-byte EIP-712 signature.
     */
    function moveERC20(
        address account,
        address safeRecipient,
        address[] calldata tokens,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        if (address(this) != _SELF) revert Unauthorized();
        if (safeRecipient == address(0)) revert InvalidRecipient();
        if (safeRecipient == account) revert SelfRecipient();
        if (tokens.length == 0) revert InvalidToken();
        if (tokens.length > MAX_TOKENS) revert TooManyTokens();
        if (deadline < block.timestamp) revert SignatureExpired();

        _verifyDelegation(account);
        address fw;
        {
            AntidrainStorage storage $ = _getStorage();
            if ($.blocked[account]) revert AccountIsBlocked();
            fw = $.feeWallet;
        }
        {
            uint256 nonce = accountNonces[account][msg.sender];

            for (uint256 i = 0; i < tokens.length;) {
                if (tokens[i] == address(0)) revert InvalidToken();
                unchecked { ++i; }
            }

            bytes32 digest = keccak256(abi.encodePacked(
                "\x19\x01",
                _domainSeparator(account),
                keccak256(bytes.concat(
                    abi.encode(
                        TRANSFER_TOKEN_TYPEHASH,
                        safeRecipient,
                        keccak256(abi.encodePacked(tokens)),
                        fw
                    ),
                    abi.encode(
                        _SELF,
                        msg.sender,
                        nonce,
                        deadline
                    )
                ))
            ));
            if (_recover(digest, signature) != account) revert InvalidSignature();
            accountNonces[account][msg.sender] = nonce + 1;
        }

        bytes memory payload = abi.encodeWithSelector(
            this.executeMoveERC20.selector,
            safeRecipient, tokens, fw
        );
        (bool success, bytes memory returndata) = account.call(payload);
        if (!success) _propagateRevert(returndata);
    }

    /**
     * @notice Transfer the EOA's entire native ETH balance to `safeRecipient`
     *         with a 20 % fee. No claim step.
     * @dev    Runs in contract context → calls into the delegated EOA via `account.call`.
     * @param  account       The compromised EOA delegated to this contract.
     * @param  safeRecipient The victim's safe wallet.
     * @param  deadline      Unix timestamp after which the signature is invalid.
     * @param  signature     The victim's 65-byte EIP-712 signature.
     */
    function moveNative(
        address account,
        address safeRecipient,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        if (address(this) != _SELF) revert Unauthorized();
        if (safeRecipient == address(0)) revert InvalidRecipient();
        if (safeRecipient == account) revert SelfRecipient();
        if (deadline < block.timestamp) revert SignatureExpired();

        _verifyDelegation(account);
        address fw;
        {
            AntidrainStorage storage $ = _getStorage();
            if ($.blocked[account]) revert AccountIsBlocked();
            fw = $.feeWallet;
        }
        {
            uint256 nonce = accountNonces[account][msg.sender];
            bytes32 digest = keccak256(abi.encodePacked(
                "\x19\x01",
                _domainSeparator(account),
                keccak256(abi.encode(
                    TRANSFER_NATIVE_TYPEHASH,
                    safeRecipient,
                    fw,
                    _SELF,
                    msg.sender,
                    nonce,
                    deadline
                ))
            ));
            if (_recover(digest, signature) != account) revert InvalidSignature();
            accountNonces[account][msg.sender] = nonce + 1;
        }

        bytes memory payload = abi.encodeWithSelector(
            this.executeMoveNative.selector,
            safeRecipient, fw
        );
        (bool success, bytes memory returndata) = account.call(payload);
        if (!success) _propagateRevert(returndata);
    }

    /*//////////////////////////////////////////////////////////////
              EXECUTE FUNCTIONS (DELEGATED EOA CONTEXT)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Executes claim + ERC-20 transfer in the delegated EOA's context.
     * @dev    Only callable by the Antidrain contract itself (via `account.call`).
     */
    function executeRescueERC20(
        address safeRecipient,
        address token,
        address claimTarget,
        bytes calldata claimData,
        address fw
    ) external payable {
        if (msg.sender != _SELF) revert Unauthorized();

        (bool success,) = claimTarget.call{value: msg.value}(claimData);
        if (!success) revert ClaimFailed();

        (uint256 remaining, uint256 feeAmount) = _transferERC20WithFee(token, safeRecipient, fw);
        if (remaining == 0 && feeAmount == 0) revert NoBalance();
        emit Rescued(address(this), safeRecipient, token, remaining, feeAmount);
    }

    /**
     * @notice Executes claim + native ETH transfer in the delegated EOA's context.
     * @dev    Only callable by the Antidrain contract itself (via `account.call`).
     */
    function executeRescueNative(
        address safeRecipient,
        address claimTarget,
        bytes calldata claimData,
        address fw
    ) external payable {
        if (msg.sender != _SELF) revert Unauthorized();

        (bool success,) = claimTarget.call{value: msg.value}(claimData);
        if (!success) revert ClaimFailed();

        (uint256 userAmount, uint256 feeAmount) = _sendNativeWithFee(safeRecipient, fw);
        emit Rescued(address(this), safeRecipient, address(0), userAmount, feeAmount);
    }

    /**
     * @notice Transfers multiple ERC-20 tokens in the delegated EOA's context.
     * @dev    Skips tokens with zero balance; reverts if no token had a balance.
     */
    function executeMoveERC20(
        address safeRecipient,
        address[] calldata tokens,
        address fw
    ) external {
        if (msg.sender != _SELF) revert Unauthorized();

        uint256 tokensTransferred = 0;
        for (uint256 i = 0; i < tokens.length;) {
            (uint256 remaining, uint256 feeAmount) = _transferERC20WithFee(tokens[i], safeRecipient, fw);
            if (remaining > 0 || feeAmount > 0) {
                emit Rescued(address(this), safeRecipient, tokens[i], remaining, feeAmount);
                unchecked { ++tokensTransferred; }
            }
            unchecked { ++i; }
        }

        if (tokensTransferred == 0) revert NoBalance();
    }

    /**
     * @notice Transfers native ETH in the delegated EOA's context.
     * @dev    Only callable by the Antidrain contract itself (via `account.call`).
     */
    function executeMoveNative(
        address safeRecipient,
        address fw
    ) external {
        if (msg.sender != _SELF) revert Unauthorized();

        (uint256 userAmount, uint256 feeAmount) = _sendNativeWithFee(safeRecipient, fw);
        emit Rescued(address(this), safeRecipient, address(0), userAmount, feeAmount);
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN (CONTRACT CONTEXT)
    //////////////////////////////////////////////////////////////*/

    /** @notice Replace the fee-collection wallet. Emits {FeeWalletUpdated}. */
    function setFeeWallet(address newFeeWallet) external onlySelf onlyOwner whenNotPaused {
        if (newFeeWallet == address(0)) revert InvalidRecipient();
        AntidrainStorage storage $ = _getStorage();
        address previousFeeWallet = $.feeWallet;
        $.feeWallet = newFeeWallet;
        emit FeeWalletUpdated(previousFeeWallet, newFeeWallet);
    }

    /** @notice Transfer contract ownership. Emits {OwnershipTransferred}. */
    function transferOwnership(address newOwner) external onlySelf onlyOwner whenNotPaused {
        if (newOwner == address(0)) revert InvalidRecipient();
        AntidrainStorage storage $ = _getStorage();
        address previousOwner = $.owner;
        $.owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /** @notice Pause all relay operations and fee-wallet / ownership changes. */
    function pause() external onlySelf onlyOwner whenNotPaused {
        _getStorage().paused = true;
        emit Paused(address(this));
    }

    /** @notice Unpause the contract. No-op if already unpaused. */
    function unpause() external onlySelf onlyOwner {
        AntidrainStorage storage $ = _getStorage();
        if (!$.paused) return;
        $.paused = false;
        emit Unpaused(address(this));
    }

    /**
     * @notice Block an account from all rescue operations.
     * @dev    Used when a malicious actor (e.g. the drainer themselves) delegates a
     *         victim's EOA to Antidrain and attempts to redirect funds to their own
     *         "safeRecipient". Blocking prevents any further rescue calls for this
     *         account until the situation is verified and resolved by the admin.
     * @param  account The EOA address to block.
     */
    function blockAccount(address account) external onlySelf onlyOwner whenNotPaused {
        _getStorage().blocked[account] = true;
        emit AccountBlocked(account);
    }

    /**
     * @notice Unblock a previously blocked account after verification.
     * @param  account The EOA address to unblock.
     */
    function unblockAccount(address account) external onlySelf onlyOwner whenNotPaused {
        _getStorage().blocked[account] = false;
        emit AccountUnblocked(account);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Verify that `account` has an EIP-7702 delegation pointing to this contract.
     *      The extcode of a delegated EOA is exactly 23 bytes: `0xef0100 || address`.
     * @param account The EOA whose delegation is being verified.
     */
    function _verifyDelegation(address account) internal view {
        address self = _SELF;
        bool valid;
        assembly {
            let size := extcodesize(account)
            switch eq(size, 23)
            case 1 {
                let ptr := mload(0x40)
                extcodecopy(account, ptr, 0, 23)
                /* first 3 bytes = EIP-7702 prefix, next 20 bytes = delegate address */
                let first3 := shr(232, mload(ptr))
                let codeAddr := shr(96, mload(add(ptr, 3)))
                valid := and(eq(first3, 0xef0100), eq(codeAddr, self))
                mstore(0x40, add(ptr, 0x20))
            }
            default { valid := 0 }
        }
        if (!valid) revert NotDelegatedToAntidrain();
    }

    /**
     * @dev  Split `amount` into user and fee portions using ceiling division.
     *       Guarantees `feeAmount >= 1` for any `amount >= 1` (fee cannot be zero).
     * @param  amount    The total balance to split.
     * @return userAmount The portion sent to the victim's safe wallet (80 %).
     * @return feeAmount  The portion sent to the fee wallet (20 %, rounded up).
     */
    function _splitAmounts(uint256 amount) internal pure returns (uint256 userAmount, uint256 feeAmount) {
        feeAmount = (amount * FEE_BPS + BPS_DENOM - 1) / BPS_DENOM;
        unchecked { userAmount = amount - feeAmount; }
    }

    /**
     * @dev  Transfer an ERC-20 token's full balance with fee split.
     *       Re-reads balance after the fee transfer to handle fee-on-transfer (FOT) tokens.
     * @return remaining The amount actually sent to `safeRecipient`.
     * @return feeAmount The amount sent to the fee wallet.
     */
    function _transferERC20WithFee(
        address token, address safeRecipient, address fw
    ) internal returns (uint256 remaining, uint256 feeAmount) {
        uint256 total = IERC20(token).balanceOf(address(this));
        if (total == 0) return (0, 0);
        (, feeAmount) = _splitAmounts(total);
        if (feeAmount > 0) _safeTransfer(token, fw, feeAmount);
        remaining = IERC20(token).balanceOf(address(this));
        if (remaining > 0) _safeTransfer(token, safeRecipient, remaining);
    }

    /**
     * @dev  Send the EOA's full native ETH balance with fee split.
     *       Fee transfer is capped at 30 000 gas to prevent reentrancy via the fee wallet.
     * @return userAmount The amount sent to `safeRecipient`.
     * @return feeAmount  The amount sent to the fee wallet.
     */
    function _sendNativeWithFee(
        address safeRecipient, address fw
    ) internal returns (uint256 userAmount, uint256 feeAmount) {
        uint256 total = address(this).balance;
        if (total == 0) revert NoBalance();
        (userAmount, feeAmount) = _splitAmounts(total);
        if (feeAmount > 0) {
            (bool feeOk,) = fw.call{gas: 30_000, value: feeAmount}("");
            if (!feeOk) revert TransferFailed();
        }
        if (userAmount > 0) {
            (bool userOk,) = safeRecipient.call{value: userAmount}("");
            if (!userOk) revert TransferFailed();
        }
    }

    /**
     * @dev  Solady-style safe ERC-20 transfer.
     *       Handles tokens that return nothing (USDT) as well as standard bool-returning tokens.
     */
    function _safeTransfer(address token, address to, uint256 amount) internal {
        assembly {
            let ptr := mload(0x40)
            /* selector: transfer(address,uint256) */
            mstore(ptr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), to)
            mstore(add(ptr, 0x24), amount)
            mstore(0x40, add(ptr, 0x60))
            let success := call(gas(), token, 0, ptr, 0x44, 0x00, 0x20)
            /* pass if call succeeded AND (no returndata OR returndata decodes to true) */
            if iszero(and(success, or(iszero(returndatasize()), and(gt(returndatasize(), 31), eq(mload(0x00), 1))))) {
                mstore(0x00, 0x90b8ec18) /* selector for TransferFailed() */
                revert(0x1c, 0x04)
            }
        }
    }

    /**
     * @dev  Build the EIP-712 domain separator using the delegated EOA as `verifyingContract`.
     *       This ensures signatures are scoped to a specific account and chain.
     */
    function _domainSeparator(address account) internal view returns (bytes32) {
        return keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            NAME_HASH,
            VERSION_HASH,
            block.chainid,
            account
        ));
    }

    /**
     * @dev  Recover the signer from an EIP-712 digest + 65-byte signature.
     *       Rejects malleable signatures by enforcing low-s (EIP-2).
     * @param  hash The EIP-712 digest.
     * @param  sig  The 65-byte packed signature (r ++ s ++ v).
     * @return      The recovered address, or `address(0)` on failure.
     */
    function _recover(bytes32 hash, bytes calldata sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);

        /* s must be in the lower half of secp256k1 order to prevent malleability */
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        return ecrecover(hash, v, r, s);
    }

    /** @dev Bubble up the revert reason from a failed low-level `.call()`. */
    function _propagateRevert(bytes memory returndata) internal pure {
        if (returndata.length > 0) {
            assembly {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
        revert ExecuteFailed(returndata);
    }

    /** @dev Accept plain ETH transfers only in delegated EOA context. */
    receive() external payable {
        if (address(this) == _SELF) revert Unauthorized();
    }

    /** @dev Accept unrecognized calls in delegated EOA context for ecosystem compatibility. */
    fallback() external payable {
        if (address(this) == _SELF) revert Unauthorized();
    }
}
