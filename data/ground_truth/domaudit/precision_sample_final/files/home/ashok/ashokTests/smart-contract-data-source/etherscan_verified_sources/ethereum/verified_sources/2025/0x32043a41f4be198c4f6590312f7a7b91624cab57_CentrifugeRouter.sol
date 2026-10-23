// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x32043a41f4be198c4f6590312f7a7b91624cab57
// Contract Name: CentrifugeRouter



// ============================================================
// FILE: src/CentrifugeRouter.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {IERC20, IERC20Permit, IERC20Wrapper} from "src/interfaces/IERC20.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {ICentrifugeRouter} from "src/interfaces/ICentrifugeRouter.sol";
import {IPoolManager, Domain} from "src/interfaces/IPoolManager.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {IGateway} from "src/interfaces/gateway/IGateway.sol";
import {TransientStorage} from "src/libraries/TransientStorage.sol";
import {IRecoverable} from "src/interfaces/IRoot.sol";
import {ITransferProxy} from "src/interfaces/factories/ITransferProxy.sol";

/// @title  CentrifugeRouter
/// @notice This is a helper contract, designed to be the entrypoint for EOAs.
///         It removes the need to know about all other contracts and simplifies the way to interact with the protocol.
///         It also adds the need to fully pay for each step of the transaction execution. CentrifugeRouter allows
///         the caller to execute multiple function into a single transaction by taking advantage of
///         the multicall functionality which batches message calls into a single one.
/// @dev    It is critical to ensure that at the end of any transaction, no funds remain in the
///         CentrifugeRouter. Any funds that do remain are at risk of being taken by other users.
contract CentrifugeRouter is Auth, ICentrifugeRouter {
    using CastLib for address;
    using TransientStorage for bytes32;

    /// @dev Requests for Centrifuge pool are non-fungible and all have ID = 0
    uint256 private constant REQUEST_ID = 0;

    bytes32 public constant INITIATOR_SLOT = bytes32(uint256(keccak256("Centrifuge/initiator")) - 1);

    IEscrow public immutable escrow;
    IGateway public immutable gateway;
    IPoolManager public immutable poolManager;

    /// @inheritdoc ICentrifugeRouter
    mapping(address controller => mapping(address vault => uint256 amount)) public lockedRequests;

    constructor(address escrow_, address gateway_, address poolManager_) Auth(msg.sender) {
        escrow = IEscrow(escrow_);
        gateway = IGateway(gateway_);
        poolManager = IPoolManager(poolManager_);
    }

    modifier protected() {
        address currentInitiator = INITIATOR_SLOT.tloadAddress();
        if (currentInitiator == address(0)) {
            // Single call re-entrancy lock
            INITIATOR_SLOT.tstore(msg.sender);
            _;
            INITIATOR_SLOT.tstore(0);
        } else {
            // Multicall re-entrancy lock
            require(msg.sender == currentInitiator, "CentrifugeRouter/unauthorized-sender");
            _;
        }
    }

    // --- Administration ---
    /// @inheritdoc IRecoverable
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Enable interactions with the vault ---
    function enable(address vault) public payable protected {
        IERC7540Vault(vault).setEndorsedOperator(msg.sender, true);
    }

    function disable(address vault) external payable protected {
        IERC7540Vault(vault).setEndorsedOperator(msg.sender, false);
    }

    // --- Deposit ---
    /// @inheritdoc ICentrifugeRouter
    function requestDeposit(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable
        protected
    {
        require(owner == msg.sender || owner == address(this), "CentrifugeRouter/invalid-owner");

        (address asset,) = poolManager.getVaultAsset(vault);
        if (owner == address(this)) {
            _approveMax(asset, vault);
        }

        _pay(topUpAmount);
        IERC7540Vault(vault).requestDeposit(amount, controller, owner);
    }

    /// @inheritdoc ICentrifugeRouter
    function lockDepositRequest(address vault, uint256 amount, address controller, address owner)
        public
        payable
        protected
    {
        require(owner == msg.sender || owner == address(this), "CentrifugeRouter/invalid-owner");

        lockedRequests[controller][vault] += amount;
        (address asset,) = poolManager.getVaultAsset(vault);
        SafeTransferLib.safeTransferFrom(asset, owner, address(escrow), amount);

        emit LockDepositRequest(vault, controller, owner, msg.sender, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function enableLockDepositRequest(address vault, uint256 amount) external payable protected {
        enable(vault);

        (address asset, bool isWrapper) = poolManager.getVaultAsset(vault);
        uint256 assetBalance = IERC20(asset).balanceOf(msg.sender);
        if (isWrapper && assetBalance < amount) {
            wrap(asset, amount, address(this), msg.sender);
            lockDepositRequest(vault, amount, msg.sender, address(this));
        } else {
            lockDepositRequest(vault, amount, msg.sender, msg.sender);
        }
    }

    /// @inheritdoc ICentrifugeRouter
    function unlockDepositRequest(address vault, address receiver) external payable protected {
        uint256 lockedRequest = lockedRequests[msg.sender][vault];
        require(lockedRequest != 0, "CentrifugeRouter/no-locked-balance");
        lockedRequests[msg.sender][vault] = 0;

        (address asset,) = poolManager.getVaultAsset(vault);
        escrow.approveMax(asset, address(this));
        SafeTransferLib.safeTransferFrom(asset, address(escrow), receiver, lockedRequest);

        emit UnlockDepositRequest(vault, msg.sender, receiver);
    }

    /// @inheritdoc ICentrifugeRouter
    function executeLockedDepositRequest(address vault, address controller, uint256 topUpAmount)
        external
        payable
        protected
    {
        uint256 lockedRequest = lockedRequests[controller][vault];
        require(lockedRequest != 0, "CentrifugeRouter/no-locked-request");
        lockedRequests[controller][vault] = 0;

        (address asset,) = poolManager.getVaultAsset(vault);

        escrow.approveMax(asset, address(this));
        SafeTransferLib.safeTransferFrom(asset, address(escrow), address(this), lockedRequest);

        _pay(topUpAmount);
        _approveMax(asset, vault);
        IERC7540Vault(vault).requestDeposit(lockedRequest, controller, address(this));
        emit ExecuteLockedDepositRequest(vault, controller, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimDeposit(address vault, address receiver, address controller) external payable protected {
        _canClaim(vault, receiver, controller);
        uint256 maxMint = IERC7540Vault(vault).maxMint(controller);
        IERC7540Vault(vault).mint(maxMint, receiver, controller);
    }

    /// @inheritdoc ICentrifugeRouter
    function cancelDepositRequest(address vault, uint256 topUpAmount) external payable protected {
        _pay(topUpAmount);
        IERC7540Vault(vault).cancelDepositRequest(REQUEST_ID, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimCancelDepositRequest(address vault, address receiver, address controller)
        external
        payable
        protected
    {
        _canClaim(vault, receiver, controller);
        IERC7540Vault(vault).claimCancelDepositRequest(REQUEST_ID, receiver, controller);
    }

    // --- Redeem ---
    /// @inheritdoc ICentrifugeRouter
    function requestRedeem(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable
        protected
    {
        require(owner == msg.sender || owner == address(this), "CentrifugeRouter/invalid-owner");
        _pay(topUpAmount);
        IERC7540Vault(vault).requestRedeem(amount, controller, owner);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimRedeem(address vault, address receiver, address controller) external payable protected {
        _canClaim(vault, receiver, controller);
        uint256 maxWithdraw = IERC7540Vault(vault).maxWithdraw(controller);

        (address asset, bool isWrapper) = poolManager.getVaultAsset(vault);
        if (isWrapper && controller != msg.sender) {
            // Auto-unwrap if permissionlessly claiming for another controller
            IERC7540Vault(vault).withdraw(maxWithdraw, address(this), controller);
            unwrap(asset, maxWithdraw, receiver);
        } else {
            IERC7540Vault(vault).withdraw(maxWithdraw, receiver, controller);
        }
    }

    /// @inheritdoc ICentrifugeRouter
    function cancelRedeemRequest(address vault, uint256 topUpAmount) external payable protected {
        _pay(topUpAmount);
        IERC7540Vault(vault).cancelRedeemRequest(REQUEST_ID, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimCancelRedeemRequest(address vault, address receiver, address controller) external payable protected {
        _canClaim(vault, receiver, controller);
        IERC7540Vault(vault).claimCancelRedeemRequest(REQUEST_ID, receiver, controller);
    }

    // --- Transfer ---
    /// @inheritdoc ICentrifugeRouter
    function transferAssets(address asset, bytes32 recipient, uint128 amount, uint256 topUpAmount)
        public
        payable
        protected
    {
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(this), amount);
        _approveMax(asset, address(poolManager));
        _pay(topUpAmount);
        poolManager.transferAssets(asset, recipient, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function transferAssets(address asset, address recipient, uint128 amount, uint256 topUpAmount)
        external
        payable
        protected
    {
        transferAssets(asset, recipient.toBytes32(), amount, topUpAmount);
    }

    /// @inheritdoc ICentrifugeRouter
    function transferAssetsFromProxy(address transferProxy, address asset, uint256 topUpAmount)
        external
        payable
        protected
    {
        _pay(topUpAmount);
        ITransferProxy(transferProxy).transfer(asset);
    }

    /// @inheritdoc ICentrifugeRouter
    function transferTrancheTokens(
        address vault,
        Domain domain,
        uint64 chainId,
        bytes32 recipient,
        uint128 amount,
        uint256 topUpAmount
    ) public payable protected {
        SafeTransferLib.safeTransferFrom(IERC7540Vault(vault).share(), msg.sender, address(this), amount);
        _approveMax(IERC7540Vault(vault).share(), address(poolManager));
        _pay(topUpAmount);
        IPoolManager(poolManager).transferTrancheTokens(
            IERC7540Vault(vault).poolId(), IERC7540Vault(vault).trancheId(), domain, chainId, recipient, amount
        );
    }

    /// @inheritdoc ICentrifugeRouter
    function transferTrancheTokens(
        address vault,
        Domain domain,
        uint64 chainId,
        address recipient,
        uint128 amount,
        uint256 topUpAmount
    ) external payable protected {
        transferTrancheTokens(vault, domain, chainId, recipient.toBytes32(), amount, topUpAmount);
    }

    // --- ERC20 permits ---
    /// @inheritdoc ICentrifugeRouter
    function permit(address asset, address spender, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        protected
    {
        try IERC20Permit(asset).permit(msg.sender, spender, assets, deadline, v, r, s) {} catch {}
    }

    // --- ERC20 wrapping ---
    function wrap(address wrapper, uint256 amount, address receiver, address owner) public payable protected {
        require(owner == msg.sender || owner == address(this), "CentrifugeRouter/invalid-owner");
        address underlying = IERC20Wrapper(wrapper).underlying();

        amount = MathLib.min(amount, IERC20(underlying).balanceOf(owner));
        require(amount != 0, "CentrifugeRouter/zero-balance");
        SafeTransferLib.safeTransferFrom(underlying, owner, address(this), amount);

        _approveMax(underlying, wrapper);
        require(IERC20Wrapper(wrapper).depositFor(receiver, amount), "CentrifugeRouter/wrap-failed");
    }

    function unwrap(address wrapper, uint256 amount, address receiver) public payable protected {
        amount = MathLib.min(amount, IERC20(wrapper).balanceOf(address(this)));
        require(amount != 0, "CentrifugeRouter/zero-balance");

        require(IERC20Wrapper(wrapper).withdrawTo(receiver, amount), "CentrifugeRouter/unwrap-failed");
    }

    // --- Batching ---
    /// @inheritdoc ICentrifugeRouter
    function multicall(bytes[] memory data) external payable {
        require(INITIATOR_SLOT.tloadAddress() == address(0), "CentrifugeRouter/already-initiated");

        INITIATOR_SLOT.tstore(msg.sender);
        uint256 totalBytes = data.length;
        for (uint256 i; i < totalBytes; ++i) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                uint256 length = returnData.length;
                require(length != 0, "CentrifugeRouter/call-failed");

                assembly ("memory-safe") {
                    revert(add(32, returnData), length)
                }
            }
        }
        INITIATOR_SLOT.tstore(0);
    }

    // --- View Methods ---
    /// @inheritdoc ICentrifugeRouter
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address) {
        return ITranche(IPoolManager(poolManager).getTranche(poolId, trancheId)).vault(asset);
    }

    /// @inheritdoc ICentrifugeRouter
    function estimate(bytes calldata payload) external view returns (uint256 amount) {
        (, amount) = IGateway(gateway).estimate(payload);
    }

    /// @inheritdoc ICentrifugeRouter
    function hasPermissions(address vault, address controller) external view returns (bool) {
        return IERC7540Vault(vault).isPermissioned(controller);
    }

    /// @inheritdoc ICentrifugeRouter
    function isEnabled(address vault, address controller) public view returns (bool) {
        return IERC7540Vault(vault).isOperator(controller, address(this));
    }

    /// @notice Gives the max approval to `to` to spend the given `asset` if not already approved.
    /// @dev    Assumes that `type(uint256).max` is large enough to never have to increase the allowance again.
    function _approveMax(address token, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            SafeTransferLib.safeApprove(token, spender, type(uint256).max);
        }
    }

    /// @notice Send native tokens to the gateway for transaction payment.
    function _pay(uint256 amount) internal {
        require(amount <= address(this).balance, "CentrifugeRouter/insufficient-funds");
        gateway.topUp{value: amount}();
    }

    /// @notice Ensures msg.sender is either the controller, or can permissionlessly claim
    ///         on behalf of the controller.
    function _canClaim(address vault, address receiver, address controller) internal view {
        require(
            controller == msg.sender || (controller == receiver && isEnabled(vault, controller)),
            "CentrifugeRouter/invalid-sender"
        );
    }
}



// ============================================================
// FILE: src/Auth.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {IAuth} from "src/interfaces/IAuth.sol";

/// @title  Auth
/// @notice Simple authentication pattern
/// @author Based on code from https://github.com/makerdao/dss
abstract contract Auth is IAuth {
    /// @inheritdoc IAuth
    mapping(address => uint256) public wards;

    constructor(address initialWard) {
        wards[initialWard] = 1;
        emit Rely(initialWard);
    }

    /// @dev Check if the msg.sender has permissions
    modifier auth() {
        require(wards[msg.sender] == 1, "Auth/not-authorized");
        _;
    }

    /// @inheritdoc IAuth
    function rely(address user) external auth {
        wards[user] = 1;
        emit Rely(user);
    }

    /// @inheritdoc IAuth
    function deny(address user) external auth {
        wards[user] = 0;
        emit Deny(user);
    }
}



// ============================================================
// FILE: src/libraries/MathLib.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

/// @title  Math Lib
/// @dev    Standard math utilities missing in the Solidity language.
/// @author Modified from OpenZeppelin Contracts v4.9.3 (utils/math/Math.sol)
library MathLib {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero

    }

    /// @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or
    ///         denominator == 0
    /// @dev    Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv)
    ///         with further edits by Uniswap Labs also under MIT license.
    // slither-disable-start divide-before-multiply
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1, "Math: mulDiv overflow");

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
            // Always >= 1.
            // See https://cs.stackexchange.com/q/138556/92363.

            // Does not overflow because the denominator cannot be zero at this stage in the function.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }
    // slither-disable-end divide-before-multiply

    /// @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /// @notice Safe type conversion from uint256 to uint8.
    function toUint8(uint256 value) internal pure returns (uint8) {
        if (value > type(uint8).max) {
            revert("MathLib/uint8-overflow");
        }
        return uint8(value);
    }

    /// @notice Safe type conversion from uint256 to uint128.
    function toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert("MathLib/uint128-overflow");
        } else {
            value = uint128(_value);
        }
    }

    /// @notice Returns the smallest of two numbers.
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }
}



// ============================================================
// FILE: src/libraries/SafeTransferLib.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {IERC20} from "src/interfaces/IERC20.sol";

/// @title  Safe Transfer Lib
/// @author Modified from Uniswap v3 Periphery (libraries/TransferHelper.sol)
library SafeTransferLib {
    /// @notice Transfers tokens from the targeted address to the given destination
    /// @notice Errors if transfer fails
    /// @param token The contract address of the token to be transferred
    /// @param from The originating address from which the tokens will be transferred
    /// @param to The destination address of the transfer
    /// @param value The amount to be transferred
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeCall(IERC20.transferFrom, (from, to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeTransferLib/safe-transfer-from-failed");
    }

    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Errors if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeCall(IERC20.transfer, (to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeTransferLib/safe-transfer-failed");
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev Errors if approval fails
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeCall(IERC20.approve, (to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeTransferLib/safe-approve-failed");
    }

    /// @notice Transfers ETH to the recipient address
    /// @dev Fails with `STE`
    /// @dev Make sure that method that is using this function is protected from reentrancy
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "SafeTransferLib/safe-transfer-eth-failed");
    }
}



// ============================================================
// FILE: src/libraries/CastLib.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

/// @title  CastLib
library CastLib {
    function toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(bytes20(addr));
    }

    /// @dev Adds zero padding
    function toBytes32(string memory source) internal pure returns (bytes32) {
        return bytes32(bytes(source));
    }

    /// @dev Removes zero padding
    function bytes128ToString(bytes memory _bytes128) internal pure returns (string memory) {
        require(_bytes128.length == 128, "Input should be 128 bytes");

        uint8 i = 0;
        while (i < 128 && _bytes128[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);

        for (uint8 j; j < i; j++) {
            bytesArray[j] = _bytes128[j];
        }

        return string(bytesArray);
    }

    function toString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}



// ============================================================
// FILE: src/interfaces/IERC20.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

/// @title  IERC20
/// @dev    Interface of the ERC20 standard as defined in the EIP.
/// @author Modified from OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/IERC20.sol)
interface IERC20 {
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
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 */
interface IERC20Metadata is IERC20 {
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
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 *
 * ==== Security Considerations
 *
 * There are two important considerations concerning the use of `permit`. The first is that a valid permit signature
 * expresses an allowance, and it should not be assumed to convey additional meaning. In particular, it should not be
 * considered as an intention to spend the allowance in any specific way. The second is that because permits have
 * built-in replay protection and can be submitted by anyone, they can be frontrun. A protocol that uses permits should
 * take this into consideration and allow a `permit` call to fail. Combining these two aspects, a pattern that may be
 * generally recommended is:
 *
 * ```solidity
 * function doThingWithPermit(..., uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
 *     try token.permit(msg.sender, address(this), value, deadline, v, r, s) {} catch {}
 *     doThing(..., value);
 * }
 *
 * function doThing(..., uint256 value) public {
 *     token.safeTransferFrom(msg.sender, address(this), value);
 *     ...
 * }
 * ```
 *
 * Observe that: 1) `msg.sender` is used as the owner, leaving no ambiguity as to the signer intent, and 2) the use of
 * `try/catch` allows the permit to fail and makes the code tolerant to frontrunning. (See also
 * {SafeERC20-safeTransferFrom}).
 *
 * Additionally, note that smart contract wallets (such as Argent or Safe) are not able to produce permit signatures, so
 * contracts should have entry points that don't rely on permit.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     *
     * CAUTION: See Security Considerations above.
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface IERC20Wrapper {
    /**
     * @dev Returns the address of the underlying ERC-20 token that is being wrapped.
     */
    function underlying() external view returns (address);

    /**
     * @dev Allow a user to deposit underlying tokens and mint the corresponding number of wrapped tokens.
     */
    function depositFor(address account, uint256 value) external returns (bool);

    /**
     * @dev Allow a user to burn a number of wrapped tokens and withdraw the corresponding number of underlying tokens.
     */
    function withdrawTo(address account, uint256 value) external returns (bool);
}



// ============================================================
// FILE: src/interfaces/IERC7540.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IERC7575} from "src/interfaces/IERC7575.sol";
import {IRecoverable} from "src/interfaces/IRoot.sol";

interface IERC7540Operator {
    /**
     * @dev The event emitted when an operator is set.
     *
     * @param controller The address of the controller.
     * @param operator The address of the operator.
     * @param approved The approval status.
     */
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /**
     * @dev Sets or removes an operator for the caller.
     *
     * @param operator The address of the operator.
     * @param approved The approval status.
     * @return Whether the call was executed successfully or not
     */
    function setOperator(address operator, bool approved) external returns (bool);

    /**
     * @dev Returns `true` if the `operator` is approved as an operator for an `controller`.
     *
     * @param controller The address of the controller.
     * @param operator The address of the operator.
     * @return status The approval status
     */
    function isOperator(address controller, address operator) external view returns (bool status);
}

interface IERC7540Deposit is IERC7540Operator {
    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );
    /**
     * @dev Transfers assets from sender into the Vault and submits a Request for asynchronous deposit.
     *
     * - MUST support ERC-20 approve / transferFrom on asset as a deposit Request flow.
     * - MUST revert if all of assets cannot be requested for deposit.
     * - owner MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from owner to sender is NOT enough.
     *
     * @param assets the amount of deposit assets to transfer from owner
     * @param controller the controller of the request who will be able to operate the request
     * @param owner the source of the deposit assets
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's underlying asset token.
     */

    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);

    /**
     * @dev Returns the amount of requested assets in Pending state.
     *
     * - MUST NOT include any assets in Claimable state for deposit or mint.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 pendingAssets);

    /**
     * @dev Returns the amount of requested assets in Claimable state for the controller to deposit or mint.
     *
     * - MUST NOT include any assets in Pending state.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function claimableDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableAssets);

    /**
     * @dev Mints shares Vault shares to receiver by claiming the Request of the controller.
     *
     * - MUST emit the Deposit event.
     * - controller MUST equal msg.sender unless the controller has approved the msg.sender as an operator.
     */
    function deposit(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    /**
     * @dev Mints exactly shares Vault shares to receiver by claiming the Request of the controller.
     *
     * - MUST emit the Deposit event.
     * - controller MUST equal msg.sender unless the controller has approved the msg.sender as an operator.
     */
    function mint(uint256 shares, address receiver, address controller) external returns (uint256 assets);
}

interface IERC7540Redeem is IERC7540Operator {
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );

    /**
     * @dev Assumes control of shares from sender into the Vault and submits a Request for asynchronous redeem.
     *
     * - MUST support a redeem Request flow where the control of shares is taken from sender directly
     *   where msg.sender has ERC-20 approval over the shares of owner.
     * - MUST revert if all of shares cannot be requested for redeem.
     *
     * @param shares the amount of shares to be redeemed to transfer from owner
     * @param controller the controller of the request who will be able to operate the request
     * @param owner the source of the shares to be redeemed
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's share token.
     */
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    /**
     * @dev Returns the amount of requested shares in Pending state.
     *
     * - MUST NOT include any shares in Claimable state for redeem or withdraw.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 pendingShares);

    /**
     * @dev Returns the amount of requested shares in Claimable state for the controller to redeem or withdraw.
     *
     * - MUST NOT include any shares in Pending state for redeem or withdraw.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function claimableRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableShares);
}

interface IERC7540CancelDeposit {
    event CancelDepositRequest(address indexed controller, uint256 indexed requestId, address sender);
    event CancelDepositClaim(
        address indexed controller, address indexed receiver, uint256 indexed requestId, address sender, uint256 assets
    );

    /**
     * @dev Submits a Request for cancelling the pending deposit Request
     *
     * - controller MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from controller to sender is NOT enough.
     * - MUST set pendingCancelDepositRequest to `true` for the returned requestId after request
     * - MUST increase claimableCancelDepositRequest for the returned requestId after fulfillment
     * - SHOULD be claimable using `claimCancelDepositRequest`
     * Note: while `pendingCancelDepositRequest` is `true`, `requestDeposit` cannot be called
     */
    function cancelDepositRequest(uint256 requestId, address controller) external;

    /**
     * @dev Returns whether the deposit Request is pending cancelation
     *
     * - MUST NOT show any variations depending on the caller.
     */
    function pendingCancelDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (bool isPending);

    /**
     * @dev Returns the amount of assets that were canceled from a deposit Request, and can now be claimed.
     *
     * - MUST NOT show any variations depending on the caller.
     */
    function claimableCancelDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableAssets);

    /**
     * @dev Claims the canceled deposit assets, and removes the pending cancelation Request
     *
     * - controller MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from controller to sender is NOT enough.
     * - MUST set pendingCancelDepositRequest to `false` for the returned requestId after request
     * - MUST set claimableCancelDepositRequest to 0 for the returned requestId after fulfillment
     */
    function claimCancelDepositRequest(uint256 requestId, address receiver, address controller)
        external
        returns (uint256 assets);
}

interface IERC7540CancelRedeem {
    event CancelRedeemRequest(address indexed controller, uint256 indexed requestId, address sender);
    event CancelRedeemClaim(
        address indexed controller, address indexed receiver, uint256 indexed requestId, address sender, uint256 shares
    );

    /**
     * @dev Submits a Request for cancelling the pending redeem Request
     *
     * - controller MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from controller to sender is NOT enough.
     * - MUST set pendingCancelRedeemRequest to `true` for the returned requestId after request
     * - MUST increase claimableCancelRedeemRequest for the returned requestId after fulfillment
     * - SHOULD be claimable using `claimCancelRedeemRequest`
     * Note: while `pendingCancelRedeemRequest` is `true`, `requestRedeem` cannot be called
     */
    function cancelRedeemRequest(uint256 requestId, address controller) external;

    /**
     * @dev Returns whether the redeem Request is pending cancelation
     *
     * - MUST NOT show any variations depending on the caller.
     */
    function pendingCancelRedeemRequest(uint256 requestId, address controller) external view returns (bool isPending);

    /**
     * @dev Returns the amount of shares that were canceled from a redeem Request, and can now be claimed.
     *
     * - MUST NOT show any variations depending on the caller.
     */
    function claimableCancelRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableShares);

    /**
     * @dev Claims the canceled redeem shares, and removes the pending cancelation Request
     *
     * - controller MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from controller to sender is NOT enough.
     * - MUST set pendingCancelRedeemRequest to `false` for the returned requestId after request
     * - MUST set claimableCancelRedeemRequest to 0 for the returned requestId after fulfillment
     */
    function claimCancelRedeemRequest(uint256 requestId, address receiver, address controller)
        external
        returns (uint256 shares);
}

interface IERC7741 {
    /**
     * @dev Grants or revokes permissions for `operator` to manage Requests on behalf of the
     *      `msg.sender`, using an [EIP-712](./eip-712.md) signature.
     */
    function authorizeOperator(
        address controller,
        address operator,
        bool approved,
        bytes32 nonce,
        uint256 deadline,
        bytes memory signature
    ) external returns (bool);

    /**
     * @dev Revokes the given `nonce` for `msg.sender` as the `owner`.
     */
    function invalidateNonce(bytes32 nonce) external;

    /**
     * @dev Returns whether the given `nonce` has been used for the `controller`.
     */
    function authorizations(address controller, bytes32 nonce) external view returns (bool used);

    /**
     * @dev Returns the `DOMAIN_SEPARATOR` as defined according to EIP-712. The `DOMAIN_SEPARATOR
     *      should be unique to the contract and chain to prevent replay attacks from other domains,
     *      and satisfy the requirements of EIP-712, but is otherwise unconstrained.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface IERC7714 {
    /**
     * @dev Returns `true` if the `user` is permissioned to interact with the contract.
     */
    function isPermissioned(address controller) external view returns (bool);
}

/**
 * @title  IERC7540Vault
 * @dev    This is the specific set of interfaces used by the Centrifuge impelmentation of ERC7540,
 *         as a fully asynchronous Vault, with cancelation support, and authorize operator signature support.
 */
interface IERC7540Vault is
    IERC7540Deposit,
    IERC7540Redeem,
    IERC7540CancelDeposit,
    IERC7540CancelRedeem,
    IERC7575,
    IERC7741,
    IERC7714,
    IRecoverable
{
    event DepositClaimable(address indexed controller, uint256 indexed requestId, uint256 assets, uint256 shares);
    event RedeemClaimable(address indexed controller, uint256 indexed requestId, uint256 assets, uint256 shares);
    event CancelDepositClaimable(address indexed controller, uint256 indexed requestId, uint256 assets);
    event CancelRedeemClaimable(address indexed controller, uint256 indexed requestId, uint256 shares);

    /// @notice Identifier of the Centrifuge pool
    function poolId() external view returns (uint64);

    /// @notice Identifier of the tranche of the Centrifuge pool
    function trancheId() external view returns (bytes16);

    /// @notice Set msg.sender as operator of owner, to `approved` status
    /// @dev    MUST be called by endorsed sender
    function setEndorsedOperator(address owner, bool approved) external;

    /// @notice Callback when a redeem Request is triggered externally;
    function onRedeemRequest(address controller, address owner, uint256 shares) external;

    /// @notice Callback when a deposit Request becomes claimable
    function onDepositClaimable(address owner, uint256 assets, uint256 shares) external;

    /// @notice Callback when a redeem Request becomes claimable
    function onRedeemClaimable(address owner, uint256 assets, uint256 shares) external;

    /// @notice Callback when a claim deposit Request becomes claimable
    function onCancelDepositClaimable(address owner, uint256 assets) external;

    /// @notice Callback when a claim redeem Request becomes claimable
    function onCancelRedeemClaimable(address owner, uint256 shares) external;

    /// @notice Price of 1 unit of share, quoted in the decimals of the asset.
    function pricePerShare() external view returns (uint256);

    /// @notice Returns timestamp of the last share price update.
    function priceLastUpdated() external view returns (uint64);
}



// ============================================================
// FILE: src/interfaces/ICentrifugeRouter.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {Domain} from "src/interfaces/IPoolManager.sol";
import {IRecoverable} from "src/interfaces/IRoot.sol";

interface ICentrifugeRouter is IRecoverable {
    // --- Events ---
    event LockDepositRequest(
        address indexed vault, address indexed controller, address indexed owner, address sender, uint256 amount
    );
    event UnlockDepositRequest(address indexed vault, address indexed controller, address indexed receiver);
    event ExecuteLockedDepositRequest(address indexed vault, address indexed controller, address sender);

    /// @notice Check how much of the `vault`'s asset is locked for the current `controller`.
    /// @dev    This is a getter method
    function lockedRequests(address controller, address vault) external view returns (uint256 amount);

    // --- Manage permissionless claiming ---
    /// @notice Enable permissionless claiming
    /// @dev    After this is called, anyone can claim tokens to msg.sender.
    ///         Even any requests submitted directly to the vault (not through the CentrifugeRouter) will be
    ///         permissionlessly claimable through the CentrifugeRouter, until `disable()` is called.
    function enable(address vault) external payable;

    /// @notice Disable permissionless claiming
    function disable(address vault) external payable;

    // --- Deposit ---
    /// @notice Check `IERC7540Deposit.requestDeposit`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault to deposit into
    /// @param  amount Check @param IERC7540Deposit.requestDeposit.assets
    /// @param  controller Check @param IERC7540Deposit.requestDeposit.controller
    /// @param  owner Check @param IERC7540Deposit.requestDeposit.owner
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function requestDeposit(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable;

    /// @notice Locks `amount` of `vault`'s asset in an escrow before actually sending a deposit LockDepositRequest
    ///         There are users that would like to interact with the protocol but don't have permissions yet. They can
    ///         lock the funds they would like to deposit beforehand.
    ///         Once permissions are granted, anyone can deposit on
    ///         their behalf by calling `executeLockedDepositRequest`.
    ///
    ///         Example: DAO with onchain governance, that wants to invest their treasury
    ///             The process that doesn't include calling this method is as follows:
    ///
    ///                 1. The DAO signs the legal agreements for the pool => no onchain action,
    ///                    but only after this the issuer can call update_member to add them as a whitelisted investor
    ///                 2. Call `requestDeposit` to lock funds
    ///                 3. After the pool has fulfilled their request, call `deposit` to claim their tranche tokens
    ///
    ///
    ///             With the new router function the steps are as follows:
    ///
    ///                 1. DAO signs the legal agreement + calls  `openLockDepositRequest`  in 1 governance proposal
    ///
    ///                 2. Issuer then gives them permissions, then calls `executeLockDepositFunds` for them,
    ///                    then fulfills the request, then calls `claimDeposit` for them
    ///
    /// @dev    For initial interaction better use `openLockDepositRequest` which includes some of the message calls
    ///         that the caller must do execute before calling `lockDepositRequest`
    ///
    /// @param  vault The address of the vault to invest in
    /// @param  amount Amount to invest
    /// @param  controller Address of the owner of the position
    /// @param  owner Where the  funds to be deposited will be take from
    function lockDepositRequest(address vault, uint256 amount, address controller, address owner) external payable;

    /// @notice Helper method to lock a deposit request, and enable permissionless claiming of that vault in 1 call.
    /// @dev    It starts interaction with the vault by calling `open`.
    ///         Vaults support assets that are wrapped one. When user calls this method
    ///         and the vault's asset is a wrapped one, first the balance of the wrapped asset is checked.
    ///         If balance >= `amount`, then this asset is used
    ///         else  amount is treat as an underlying asset one and it is wrapped.
    /// @param  vault Address of the vault
    /// @param  amount Amount to be deposited
    function enableLockDepositRequest(address vault, uint256 amount) external payable;

    /// @notice Unlocks all deposited assets of the current caller for a given vault
    ///
    /// @param  vault Address of the vault for which funds were locked
    /// @param  receiver Address of the received of the unlocked funds
    function unlockDepositRequest(address vault, address receiver) external payable;

    /// @notice After the controller is given permissions, anyone can call this method and
    ///         actually request a deposit with the locked funds on the behalf of the `controller`
    /// @param  vault The vault for which funds are locked
    /// @param  controller Owner of the deposit position
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function executeLockedDepositRequest(address vault, address controller, uint256 topUpAmount) external payable;

    /// @notice Check IERC7540Deposit.mint
    /// @param  vault Address of the vault
    /// @param  receiver Check IERC7540Deposit.mint.receiver
    /// @param  controller Check IERC7540Deposit.mint.owner
    function claimDeposit(address vault, address receiver, address controller) external payable;

    // --- Redeem ---
    /// @notice Check `IERC7540CancelDeposit.cancelDepositRequest`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault where the deposit was initiated
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function cancelDepositRequest(address vault, uint256 topUpAmount) external payable;

    /// @notice Check IERC7540CancelDeposit.claimCancelDepositRequest
    ///
    /// @param  vault Address of the vault
    /// @param  receiver Check  IERC7540CancelDeposit.claimCancelDepositRequest.receiver
    /// @param  controller Check  IERC7540CancelDeposit.claimCancelDepositRequest.controller
    function claimCancelDepositRequest(address vault, address receiver, address controller) external payable;

    // --- Redeem ---
    /// @notice Check `IERC7540Redeem.requestRedeem`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault to deposit into
    /// @param  amount Check @param IERC7540Redeem.requestRedeem.shares
    /// @param  controller Check @param IERC7540Redeem.requestRedeem.controller
    /// @param  owner Check @param IERC7540Redeem.requestRedeem.owner
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function requestRedeem(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable;

    /// @notice Check IERC7575.withdraw
    /// @dev    If the underlying vault asset is a wrapped one,
    ///         `CentrifugeRouter.unwrap` is called and the unwrapped
    ///         asset is sent to the receiver
    /// @param  vault Address of the vault
    /// @param  receiver Check IERC7575.withdraw.receiver
    /// @param  controller Check IERC7575.withdraw.owner
    function claimRedeem(address vault, address receiver, address controller) external payable;

    /// @notice Check `IERC7540CancelRedeem.cancelRedeemRequest`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault where the deposit was initiated
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function cancelRedeemRequest(address vault, uint256 topUpAmount) external payable;

    /// @notice Check IERC7540CancelRedeem.claimableCancelRedeemRequest
    ///
    /// @param  vault Address of the vault
    /// @param  receiver Check  IERC7540CancelRedeem.claimCancelRedeemRequest.receiver
    /// @param  controller Check  IERC7540CancelRedeem.claimCancelRedeemRequest.controller
    function claimCancelRedeemRequest(address vault, address receiver, address controller) external payable;

    // --- Transfer ---
    /// @notice Check `IPoolManager.transferAssets`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  asset Check `IPoolManager.transferAssets.asset`
    /// @param  recipient Check `IPoolManager.transferAssets.recipient`
    /// @param  amount Check `IPoolManager.transferAssets.amount`
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function transferAssets(address asset, bytes32 recipient, uint128 amount, uint256 topUpAmount) external payable;

    /// @notice This is a more friendly version where the recipient is and EVM address
    /// @dev the recipient address is padded to 32 bytes internally
    function transferAssets(address asset, address recipient, uint128 amount, uint256 topUpAmount) external payable;

    /// @notice Trigger a transfer of assets from a TransferProxy contract.
    function transferAssetsFromProxy(address transferProxy, address asset, uint256 topUpAmount) external payable;

    /// @notice Check `IPoolManager.transferTrancheTokens`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault for the corresponding tranche token
    /// @param  domain Check `IPoolManager.transferTrancheTokens.domain`
    /// @param  id Check `IPoolManager.transferTrancheTokens.destinationId`
    /// @param  recipient Check `IPoolManager.transferTrancheTokens.recipient`
    /// @param  amount Check `IPoolManager.transferTrancheTokens.amount`
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function transferTrancheTokens(
        address vault,
        Domain domain,
        uint64 id,
        bytes32 recipient,
        uint128 amount,
        uint256 topUpAmount
    ) external payable;

    /// @notice This is a more friendly version where the recipient is and EVM address
    /// @dev    The recipient address is padded to 32 bytes internally
    function transferTrancheTokens(
        address vault,
        Domain domain,
        uint64 chainId,
        address recipient,
        uint128 amount,
        uint256 topUpAmount
    ) external payable;

    // --- ERC20 permit ---
    /// @notice Check IERC20.permit
    function permit(address asset, address spender, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable;

    // --- ERC20 wrapping ---
    /// @notice There are vault which underlying asset is actuall a wrapped one.
    ///
    /// @param  wrapper The address of the wrapper
    /// @param  amount  Amount to be wrapped
    /// @param  receiver Receiver of the wrapped tokens
    /// @param  owner The address from which `amount` is taken from
    function wrap(address wrapper, uint256 amount, address receiver, address owner) external payable;

    /// @notice There are vault which underlying asset is actuall a wrapped one.
    /// @dev    Wrapped tokens need to be held by the CentrifugeRouter to be unwrapped.
    /// @param  wrapper The address of the wrapper
    /// @param  amount  Amount to be wrapped
    /// @param  receiver Receiver of the unwrapped tokens
    function unwrap(address wrapper, uint256 amount, address receiver) external payable;

    // --- Batching ---
    /// @notice Allows caller to execute multiple ( batched ) messages calls in one transaction.
    /// @dev    Messages calls that can be executed are only part of the CentrifugeRouter itself.
    ///         No reentrant execution is allowed.
    ///         In order to provide the correct value for functions that require top up,
    ///         the caller must estimate separate, in advance, how much each of the message call will cost.
    ///         The `msg.value` when calling this method must be the sum of all estimates.
    ///
    ///         Example: An investor would like to make 2 consecutive deposit requests in a single batch.
    ///         address investor            = // Investor's address
    ///         address vault               = // Vault's address
    ///         uint256 amount1             = 100 * 10 ** 18
    ///         uint256 amount2             = 50 * 10 ** 18
    ///         uint256 requestDepositCost  = 10 gwei
    ///
    ///         address router              = // CentrifugeRouter's address
    ///
    ///         bytes[] memory calls = new bytes[](2);
    ///         calls[0] = abi.encodeCall(
    ///             router.requestDeposit, (vault, amount1, investor, investor, requestDepositCost)
    ///         );
    ///         calls[1] = abi.encodeCall(
    ///             router.requestDeposit, (vault, amount2, investor, investor, requestDepositCost)
    ///         );
    ///         uint256 msgValue = 2 * requestDepositCost;

    ///         router.multicall{value: msgValue}(calls);
    ///
    ///         The `msg.value` MUST be at least 20 gwei. `multicall{value: 20 gwei}()`
    /// @param  data An array of all encoded messages calls and their arguments
    function multicall(bytes[] memory data) external payable;

    // --- View Methods ---
    /// @notice Check IPoolManager.getVault
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address);

    /// @notice Check IGateway.estimate
    function estimate(bytes calldata payload) external view returns (uint256 amount);

    /// @notice Called to check if `user` has permissions on `vault` to execute requests
    ///
    /// @param vault Address of the `vault` the `user` wants to operate on
    /// @param user Address of the `user` that will operates on the `vault`
    /// @return Whether `user` has permissions to operate on `vault`
    function hasPermissions(address vault, address user) external view returns (bool);

    /// @notice Returns whether the controller has called `enable()` for the given `vault`
    function isEnabled(address vault, address controller) external view returns (bool);
}



// ============================================================
// FILE: src/interfaces/IPoolManager.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IMessageHandler} from "src/interfaces/gateway/IGateway.sol";
import {IRecoverable} from "src/interfaces/IRoot.sol";

/// @dev Centrifuge pools
struct Pool {
    uint256 createdAt;
    mapping(bytes16 trancheId => TrancheDetails) tranches;
    mapping(address asset => bool) allowedAssets;
}

/// @dev Each Centrifuge pool is associated to 1 or more tranches
struct TrancheDetails {
    address token;
    /// @dev Each tranche can have multiple vaults deployed,
    ///      each linked to a unique asset
    mapping(address asset => address vault) vaults;
    /// @dev Each tranche has a price per vault
    mapping(address vault => TranchePrice) prices;
}

struct TranchePrice {
    uint128 price;
    uint64 computedAt;
}

/// @dev Temporary storage that is only present between addTranche and deployTranche
struct UndeployedTranche {
    /// @dev The decimals of the leading pool asset. Vault shares have
    ///      to be denomatimated with the same precision.
    uint8 decimals;
    /// @dev Metadata of the to be deployed erc20 token
    string tokenName;
    string tokenSymbol;
    /// @dev Address of the hook
    address hook;
}

struct VaultAsset {
    /// @dev Address of the asset
    address asset;
    /// @dev Whether this wrapper conforms to the IERC20Wrapper interface
    bool isWrapper;
}

enum Domain {
    Centrifuge,
    EVM
}

interface IPoolManager is IMessageHandler, IRecoverable {
    event File(bytes32 indexed what, address data);
    event AddAsset(uint128 indexed assetId, address indexed asset);
    event AddPool(uint64 indexed poolId);
    event AllowAsset(uint64 indexed poolId, address indexed asset);
    event DisallowAsset(uint64 indexed poolId, address indexed asset);
    event AddTranche(uint64 indexed poolId, bytes16 indexed trancheId);
    event DeployTranche(uint64 indexed poolId, bytes16 indexed trancheId, address indexed tranche);
    event DeployVault(uint64 indexed poolId, bytes16 indexed trancheId, address indexed asset, address vault);
    event RemoveVault(uint64 indexed poolId, bytes16 indexed trancheId, address indexed asset, address vault);
    event PriceUpdate(
        uint64 indexed poolId, bytes16 indexed trancheId, address indexed asset, uint256 price, uint64 computedAt
    );
    event TransferAssets(address indexed asset, address indexed sender, bytes32 indexed recipient, uint128 amount);
    event TransferTrancheTokens(
        uint64 indexed poolId,
        bytes16 indexed trancheId,
        address indexed sender,
        Domain destinationDomain,
        uint64 destinationId,
        bytes32 destinationAddress,
        uint128 amount
    );

    /// @notice returns the investmentManager address
    /// @dev    can be set using file
    function investmentManager() external view returns (address);

    /// @notice returns the asset address associated with a given asset id
    function idToAsset(uint128 assetId) external view returns (address asset);

    /// @notice returns the asset id associated with a given address
    function assetToId(address) external view returns (uint128 assetId);

    /// @notice Updates a contract parameter
    /// @param what Accepts a bytes32 representation of 'gateway', 'investmentManager', 'trancheFactory',
    ///                'vaultFactory', or 'gasService'
    function file(bytes32 what, address data) external;

    /// @notice transfers assets to a cross-chain recipient address
    /// @dev    Addresses on centrifuge chain are represented as bytes32
    function transferAssets(address asset, bytes32 recipient, uint128 amount) external;

    /// @notice transfers tranche tokens to a cross-chain recipient address
    /// @dev    To transfer to evm chains, pad a 20 byte evm address with 12 bytes of 0
    /// @param  poolId The centrifuge pool id
    /// @param  trancheId The tranche id
    /// @param  destinationDomain an enum representing the destination domain (Centrifuge or EVM)
    /// @param  destinationId The destination chain id
    /// @param  recipient A bytes32 representation of the recipient address
    /// @param  amount The amount of tokens to transfer
    function transferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        Domain destinationDomain,
        uint64 destinationId,
        bytes32 recipient,
        uint128 amount
    ) external;

    /// @notice    New pool details from an existing Centrifuge pool are added.
    /// @dev       The function can only be executed by the gateway contract.
    function addPool(uint64 poolId) external;

    /// @notice     Centrifuge pools can support multiple currencies for investing. this function adds
    ///             a new supported asset to the pool details.
    ///             Adding new currencies allow the creation of new vaults for the underlying Centrifuge pool.
    /// @dev        The function can only be executed by the gateway contract.
    function allowAsset(uint64 poolId, uint128 assetId) external;

    /// @notice    Centrifuge pools can support multiple currencies for investing. this function removes
    ///            a supported asset from the pool details.
    /// @dev       The function can only be executed by the gateway contract.
    function disallowAsset(uint64 poolId, uint128 assetId) external;

    /// @notice     New tranche details from an existing Centrifuge pool are added.
    /// @dev        The function can only be executed by the gateway contract.
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        address hook
    ) external;

    /// @notice   Updates the tokenName and tokenSymbol of a tranche token
    /// @dev      The function can only be executed by the gateway contract.
    function updateTrancheMetadata(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
        external;

    /// @notice  Updates the price of a tranche token
    /// @dev     The function can only be executed by the gateway contract.
    function updateTranchePrice(uint64 poolId, bytes16 trancheId, uint128 assetId, uint128 price, uint64 computedAt)
        external;

    /// @notice Updates the restrictions on a tranche token for a specific user
    /// @param  poolId The centrifuge pool id
    /// @param  trancheId The tranche id
    /// @param  update The restriction update in the form of a bytes array indicating
    ///                the restriction to be updated, the user to be updated, and a validUntil timestamp.
    function updateRestriction(uint64 poolId, bytes16 trancheId, bytes memory update) external;

    /// @notice Updates the hook of a tranche token
    /// @param  poolId The centrifuge pool id
    /// @param  trancheId The tranche id
    /// @param  hook The new hook addres
    function updateTrancheHook(uint64 poolId, bytes16 trancheId, address hook) external;

    /// @notice A global chain agnostic asset index is maintained on Centrifuge. This function maps
    ///         a asset from the Centrifuge index to its corresponding address on the evm chain.
    ///         The chain agnostic asset id has to be used to pass asset information to the Centrifuge.
    /// @dev    This function can only be executed by the gateway contract.
    function addAsset(uint128 assetId, address asset) external;

    /// @notice Executes a message from the gateway
    /// @dev    The function can only be executed by the gateway contract.
    function handle(bytes calldata message) external;

    /// @notice Transfers assets to a recipient from the escrow contract
    /// @dev    The function can only be executed internally or by the gateway contract.
    function handleTransfer(uint128 assetId, address recipient, uint128 amount) external;

    /// @notice Mints tranche tokens to a recipient
    /// @dev    The function can only be executed internally or by the gateway contract.
    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        external;

    /// @notice Deploys a created tranche
    /// @dev    The function can only be executed by the gateway contract.
    function deployTranche(uint64 poolId, bytes16 trancheId) external returns (address);

    /// @notice Deploys a vault for a given asset and tranche token
    /// @dev    The function can only be executed by the gateway contract.
    function deployVault(uint64 poolId, bytes16 trancheId, address asset) external returns (address);

    /// @notice Removes a vault for a given asset and tranche token
    /// @dev    The function can only be executed by the gateway contract.
    function removeVault(uint64 poolId, bytes16 trancheId, address asset) external;

    /// @notice Returns whether the given pool id is active
    function isPoolActive(uint64 poolId) external view returns (bool);

    /// @notice Returns the tranche token for a given pool and tranche id
    function getTranche(uint64 poolId, bytes16 trancheId) external view returns (address);

    /// @notice Returns whether the tranche token for a given pool and tranche id can be deployed
    function canTrancheBeDeployed(uint64 poolId, bytes16 trancheId) external view returns (bool);

    /// @notice Returns the vault for a given pool, tranche id, and asset id
    function getVault(uint64 poolId, bytes16 trancheId, uint128 assetId) external view returns (address);

    /// @notice Returns the vault for a given pool, tranche id, and asset address
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address);

    /// @notice Retuns the latest tranche token price for a given pool, tranche id, and asset id
    function getTranchePrice(uint64 poolId, bytes16 trancheId, address asset)
        external
        view
        returns (uint128 price, uint64 computedAt);

    /// @notice Function to get the vault's underlying asset
    /// @dev    Function vaultToAsset which is a state variable getter could be used
    ///         but in that case each caller MUST make sure they handle the case
    ///         where a 0 address is returned. Using this method, that handling is done
    ///         on the behalf the caller.
    function getVaultAsset(address vault) external view returns (address asset, bool isWrapper);

    /// @notice Checks whether a given asset is allowed for a given pool
    function isAllowedAsset(uint64 poolId, address asset) external view returns (bool);
}



// ============================================================
// FILE: src/interfaces/IEscrow.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IEscrow {
    // --- Events ---
    event Approve(address indexed token, address indexed spender, uint256 value);

    // --- Token approvals ---
    /// @notice sets the allowance of `spender` to `type(uint256).max` if it is currently 0
    function approveMax(address token, address spender) external;

    /// @notice sets the allowance of `spender` to 0
    function unapprove(address token, address spender) external;
}



// ============================================================
// FILE: src/interfaces/token/ITranche.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IERC7575Share} from "src/interfaces/IERC7575.sol";

interface IERC1404 {
    /// @notice Detects if a transfer will be reverted and if so returns an appropriate reference code
    /// @param from Sending address
    /// @param to Receiving address
    /// @param value Amount of tokens being transferred
    /// @return Code by which to reference message for rejection reasoning
    /// @dev Overwrite with your custom transfer restriction logic
    function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);

    /// @notice Returns a human-readable message for a given restriction code
    /// @param restrictionCode Identifier for looking up a message
    /// @return Text showing the restriction's reasoning
    /// @dev Overwrite with your custom message and restrictionCode handling
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
}

interface ITranche is IERC20Metadata, IERC7575Share, IERC1404 {
    // --- Events ---
    event File(bytes32 indexed what, address data);
    event SetHookData(address indexed user, bytes16 data);

    struct Balance {
        /// @dev The user balance is limited to uint128. This is safe because the decimals are limited to 18,
        ///      thus the max balance is 2^128-1 / 10**18 = 3.40 * 10**20. This is also enforced on mint.
        uint128 amount;
        /// @dev There are 16 bytes that are used to store hook data (e.g. restrictions for users).
        bytes16 hookData;
    }

    // --- Administration ---
    /// @notice returns the hook that transfers perform callbacks to
    /// @dev    MUST comply to `IHook` interface
    function hook() external view returns (address);

    /// @notice Updates a contract parameter
    /// @param what Accepts a bytes32 representation of 'name', 'symbol'
    function file(bytes32 what, string memory data) external;

    /// @notice Updates a contract parameter
    /// @param what Accepts a bytes32 representation of 'hook'
    function file(bytes32 what, address data) external;

    /// @notice updates the vault for a given `asset`
    function updateVault(address asset, address vault_) external;

    // --- ERC20 overrides ---
    /// @notice returns the 16 byte hook data of the given `user`.
    /// @dev    Stored in the 128 most significant bits of the user balance
    function hookDataOf(address user) external view returns (bytes16);

    /// @notice update the 16 byte hook data of the given `user`
    function setHookData(address user, bytes16 hookData) external;

    /// @notice Function to mint tokens
    function mint(address user, uint256 value) external;

    /// @notice Function to burn tokens
    function burn(address user, uint256 value) external;

    /// @notice Checks if the tokens can be transferred given the input values
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);

    /// @notice Performs an authorized transfer, with `sender` as the given sender.
    /// @dev    Requires allowance if `sender` != `from`
    function authTransferFrom(address sender, address from, address to, uint256 amount) external returns (bool);
}



// ============================================================
// FILE: src/interfaces/gateway/IGateway.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

uint8 constant MAX_ADAPTER_COUNT = 8;

interface IGateway {
    /// @dev Each adapter struct is packed with the quorum to reduce SLOADs on handle
    struct Adapter {
        /// @notice Starts at 1 and maps to id - 1 as the index on the adapters array
        uint8 id;
        /// @notice Number of votes required for a message to be executed
        uint8 quorum;
        /// @notice Each time the quorum is decreased, a new session starts which invalidates old votes
        uint64 activeSessionId;
    }

    struct Message {
        /// @dev Counts are stored as integers (instead of boolean values) to accommodate duplicate
        ///      messages (e.g. two investments from the same user with the same amount) being
        ///      processed in parallel. The entire struct is packed in a single bytes32 slot.
        ///      Max uint16 = 65,535 so at most 65,535 duplicate messages can be processed in parallel.
        uint16[MAX_ADAPTER_COUNT] votes;
        /// @notice Each time adapters are updated, a new session starts which invalidates old votes
        uint64 sessionId;
        bytes pendingMessage;
    }

    // --- Events ---
    event ProcessMessage(bytes message, address adapter);
    event ProcessProof(bytes32 messageHash, address adapter);
    event ExecuteMessage(bytes message, address adapter);
    event SendMessage(bytes message);
    event RecoverMessage(address adapter, bytes message);
    event RecoverProof(address adapter, bytes32 messageHash);
    event InitiateMessageRecovery(bytes32 messageHash, address adapter);
    event DisputeMessageRecovery(bytes32 messageHash, address adapter);
    event ExecuteMessageRecovery(bytes message, address adapter);
    event File(bytes32 indexed what, address[] adapters);
    event File(bytes32 indexed what, address instance);
    event File(bytes32 indexed what, uint8 messageId, address manager);
    event File(bytes32 indexed what, address caller, bool isAllowed);
    event ReceiveNativeTokens(address indexed sender, uint256 amount);

    /// @notice Returns the address of the adapter at the given id.
    function adapters(uint256 id) external view returns (address);

    /// @notice Returns the address of the contract that handles the given message id.
    function messageHandlers(uint8 messageId) external view returns (address);

    /// @notice Returns the timestamp when the given recovery can be executed.
    function recoveries(address adapter, bytes32 messageHash) external view returns (uint256 timestamp);

    // --- Administration ---
    /// @notice Used to update an array of addresses ( state variable ) on very rare occasions.
    /// @dev    Currently it is used to update the supported adapters.
    /// @param  what The name of the variable to be updated.
    /// @param  value New addresses.
    function file(bytes32 what, address[] calldata value) external;

    /// @notice Used to update an address ( state variable ) on very rare occasions.
    /// @dev    Currently used to update addresses of contract instances.
    /// @param  what The name of the variable to be updated.
    /// @param  data New address.
    function file(bytes32 what, address data) external;

    /// @notice Used to update a mapping ( state variables ) on very rare occasions.
    /// @dev    Currently used to update any custom handlers for a specific message type.
    ///         data1 is the message id from MessagesLib.Call and data2 could be any
    ///         custom instance of a contract that will handle that call.
    /// @param  what The name of the variable to be updated.
    /// @param  data1 The key of the mapping.
    /// @param  data2 The value of the mapping
    function file(bytes32 what, uint8 data1, address data2) external;

    /// @notice Used to update a mapping ( state variables ) on very rare occasions.
    /// @dev    Manages who is allowed to call `this.topUp`
    ///
    /// @param what The name of the variable to be updated - `payers`
    /// @param caller Address of the payer allowed to top-up
    /// @param isAllower Whether the `caller` is allowed to top-up or not
    function file(bytes32 what, address caller, bool isAllower) external;

    // --- Incoming ---
    /// @notice Handles incoming messages, proofs, and recoveries.
    /// @dev    Assumes adapters ensure messages cannot be confirmed more than once.
    /// @param  payload Incoming message from the Centrifuge Chain passed through adapters.
    function handle(bytes calldata payload) external;

    /// @notice Governance on Centrifuge Chain can initiate message recovery. After the challenge period,
    ///         the recovery can be executed. If a malign adapter initiates message recovery, governance on
    ///         Centrifuge Chain can dispute and immediately cancel the recovery, using any other valid adapter.
    /// @param  adapter Adapter that the recovery was targeting
    /// @param  messageHash Hash of the message being disputed
    function disputeMessageRecovery(address adapter, bytes32 messageHash) external;

    /// @notice Governance on Centrifuge Chain can initiate message recovery. After the challenge period,
    ///         the recovery can be executed. If a malign adapter initiates message recovery, governance on
    ///         Centrifuge Chain can dispute and immediately cancel the recovery, using any other valid adapter.
    ///
    ///         Only 1 recovery can be outstanding per message hash. If multiple adapters fail at the same time,
    ///         these will need to be recovered serially (increasing the challenge period for each failed adapter).
    /// @param  adapter Adapter's address that the recovery is targeting
    /// @param  message Hash of the message to be recovered
    function executeMessageRecovery(address adapter, bytes calldata message) external;

    // --- Outgoing ---
    /// @notice Sends outgoing messages to the Centrifuge Chain.
    /// @dev    Sends 1 message to the first adapter with the full message,
    ///         and n-1 messages to the other adapters with proofs (hash of message).
    ///         This ensures message uniqueness (can only be executed on the destination once).
    ///         Source could be either Centrifuge router or EoA or any contract
    ///         that calls the ERC7540Vault contract directly.
    /// @param  message Message to be send. Either the message itself or a hash value of it ( proof ).
    /// @param  source Entry point of the transaction.
    ///         Used to determine whether it is eligible for TX cost payment.
    function send(bytes calldata message, address source) external payable;

    /// @notice Prepays for the TX cost for sending through the adapters
    ///         and Centrifuge Chain
    /// @dev    It can be called only through endorsed contracts.
    ///         Currently being called from Centrifuge Router only.
    ///         In order to prepay, the method MUST be called with `msg.value`.
    ///         Called is assumed to have called IGateway.estimate before calling this.
    function topUp() external payable;

    // --- Helpers ---
    /// @notice A view method of the current quorum.abi
    /// @dev    Quorum shows the amount of votes needed in order for a message to be dispatched further.
    ///         The quorum is taken from the first adapter.
    ///         Current quorum is the amount of all adapters.
    /// return  Needed amount
    function quorum() external view returns (uint8);

    /// @notice Gets the current active routers session id.
    /// @dev    When the adapters are updated with new ones,
    ///         each new set of adapters has their own sessionId.
    ///         Currently it uses sessionId of the previous set and
    ///         increments it by 1. The idea of an activeSessionId is
    ///         to invalidate any incoming messages from previously used adapters.
    function activeSessionId() external view returns (uint64);

    /// @notice Counts how many times each incoming messages has been received per adapter.
    /// @dev    It supports parallel messages ( duplicates ). That means that the incoming messages could be
    ///         the result of two or more independ request from the user of the same type.
    ///         i.e. Same user would like to deposit same underlying asset with the same amount more then once.
    /// @param  messageHash The hash value of the incoming message.
    function votes(bytes32 messageHash) external view returns (uint16[MAX_ADAPTER_COUNT] memory);

    /// @notice Used to calculate overall cost for bridging a payload on the first adapter and settling
    ///         on the destination chain and bridging its payload proofs on n-1 adapter
    ///         and settling on the destination chain.
    /// @param  payload Used in gas cost calculations.
    /// @dev    Currenly the payload is not taken into consideration.
    /// @return perAdapter An array of cost values per adapter. Each value is how much it's going to cost
    ///         for a message / proof to be passed through one router and executed on Centrifuge Chain
    /// @return total Total cost for sending one message and corresponding proofs on through all adapters
    function estimate(bytes calldata payload) external view returns (uint256[] memory perAdapter, uint256 total);

    /// @notice Used to check current state of the `caller` and whether they are allowed to call
    ///         `this.topUp` or not.
    /// @param  caller Address to check
    /// @return isAllowed Whether the `caller` `isAllowed to call `this.topUp()`
    function payers(address caller) external view returns (bool isAllowed);
}

interface IMessageHandler {
    /// @notice Handling incoming messages from Centrifuge Chain.
    /// @param  message Incoming message
    function handle(bytes memory message) external;
}



// ============================================================
// FILE: src/libraries/TransientStorage.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

/// @title  TransientStorage
library TransientStorage {
    function tstore(bytes32 slot, address value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    function tstore(bytes32 slot, uint256 value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    function tloadAddress(bytes32 slot) internal view returns (address value) {
        assembly {
            value := tload(slot)
        }
    }

    function tloadUint256(bytes32 slot) internal view returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }
}



// ============================================================
// FILE: src/interfaces/IRoot.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IMessageHandler} from "src/interfaces/gateway/IGateway.sol";

interface IRecoverable {
    /// @notice Used to recover any ERC-20 token.
    /// @dev    This method is called only by authorized entities
    /// @param  token It could be 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
    ///         to recover locked native ETH or any ERC20 compatible token.
    /// @param  to Receiver of the funds
    /// @param  amount Amount to send to the receiver.
    function recoverTokens(address token, address to, uint256 amount) external;
}

interface IRoot is IMessageHandler {
    // --- Events ---
    event File(bytes32 indexed what, uint256 data);
    event Pause();
    event Unpause();
    event ScheduleRely(address indexed target, uint256 indexed scheduledTime);
    event CancelRely(address indexed target);
    event RelyContract(address indexed target, address indexed user);
    event DenyContract(address indexed target, address indexed user);
    event RecoverTokens(address indexed target, address indexed token, address indexed to, uint256 amount);
    event Endorse(address indexed user);
    event Veto(address indexed user);

    /// @notice Returns whether the root is paused
    function paused() external view returns (bool);

    /// @notice Returns the current timelock for adding new wards
    function delay() external view returns (uint256);

    /// @notice Trusted contracts within the system
    function endorsements(address target) external view returns (uint256);

    /// @notice Returns when `relyTarget` has passed the timelock
    function schedule(address relyTarget) external view returns (uint256 timestamp);

    // --- Administration ---
    /// @notice Updates a contract parameter
    /// @param what Accepts a bytes32 representation of 'delay'
    function file(bytes32 what, uint256 data) external;

    /// --- Endorsements ---
    /// @notice Endorses the `user`
    /// @dev    Endorsed users are trusted contracts in the system. They are allowed to bypass
    ///         token restrictions (e.g. the Escrow can automatically receive tranche tokens by being endorsed), and
    ///         can automatically set operators in ERC-7540 vaults (e.g. the CentrifugeRouter) is always an operator.
    function endorse(address user) external;

    /// @notice Removes the endorsed user
    function veto(address user) external;

    /// @notice Returns whether the user is endorsed
    function endorsed(address user) external view returns (bool);

    // --- Pause management ---
    /// @notice Pause any contracts that depend on `Root.paused()`
    function pause() external;

    /// @notice Unpause any contracts that depend on `Root.paused()`
    function unpause() external;

    /// --- Timelocked ward management ---
    /// @notice Schedule relying a new ward after the delay has passed
    function scheduleRely(address target) external;

    /// @notice Cancel a pending scheduled rely
    function cancelRely(address target) external;

    /// @notice Execute a scheduled rely
    /// @dev    Can be triggered by anyone since the scheduling is protected
    function executeScheduledRely(address target) external;

    /// --- Incoming message handling ---
    function handle(bytes calldata message) external;

    /// --- External contract ward management ---
    /// @notice Make an address a ward on any contract that Root is a ward on
    function relyContract(address target, address user) external;

    /// @notice Removes an address as a ward on any contract that Root is a ward on
    function denyContract(address target, address user) external;

    /// --- Token Recovery ---
    /// @notice Allows Governance to recover tokens sent to the wrong contract by mistake
    function recoverTokens(address target, address token, address to, uint256 amount) external;
}



// ============================================================
// FILE: src/interfaces/factories/ITransferProxy.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IRecoverable} from "src/interfaces/IRoot.sol";

interface ITransferProxy is IRecoverable {
    event File(bytes32 indexed what, address data);

    /// @notice Updates a contract parameter
    /// @param what Accepts a bytes32 representation of 'poolManager'
    function file(bytes32 what, address data) external;

    /// @notice Anyone can transfer tokens.
    function transfer(address asset) external;
}

interface ITransferProxyFactory {
    event File(bytes32 indexed what, address data);
    event DeployTransferProxy(bytes32 indexed destination, address proxy);

    /// @notice Updates a contract parameter
    /// @param what Accepts a bytes32 representation of 'poolManager'
    function file(bytes32 what, address data) external;

    /// @notice Returns the address of the linked pool manager
    function poolManager() external view returns (address);

    /// @notice Lookup proxy by destination address
    function proxies(bytes32 destination) external view returns (address proxy);

    /// @notice Deploy new transfer proxy
    function newTransferProxy(bytes32 destination) external returns (address);

    /// @notice Returns the predicted address (using CREATE2)
    function getAddress(bytes32 destination) external view returns (address);
}



// ============================================================
// FILE: src/interfaces/IAuth.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IAuth {
    event Rely(address indexed user);
    event Deny(address indexed user);

    /// @notice Returns whether the target is a ward (has admin access)
    function wards(address target) external view returns (uint256);

    /// @notice Make user a ward (give them admin access)
    function rely(address user) external;

    /// @notice Remove user as a ward (remove admin access)
    function deny(address user) external;
}



// ============================================================
// FILE: src/interfaces/IERC7575.sol
// ============================================================
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC7575 is IERC165 {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() external view returns (address assetTokenAddress);

    /**
     * @dev Returns the address of the share token
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function share() external view returns (address shareTokenAddress);

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT revert.
     */
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver,
     * through a deposit call.
     *
     * - MUST return a limited value if receiver is subject to some deposit limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be deposited.
     * - MUST NOT revert.
     */
    function maxDeposit(address receiver) external view returns (uint256 maxAssets);

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given
     * current on-chain conditions.
     *
     * - MUST return as close to and no more than the exact amount of Vault shares that would be minted in a deposit
     *   call in the same transaction. I.e. deposit should return the same or more shares as previewDeposit if called
     *   in the same transaction.
     * - MUST NOT account for deposit limits like those returned from maxDeposit and should always act as though the
     *   deposit would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewDeposit SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   deposit execution, and are accounted for during deposit.
     * - MUST revert if all of assets cannot be deposited (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @dev Returns the maximum amount of the Vault shares that can be minted for the receiver, through a mint call.
     * - MUST return a limited value if receiver is subject to some mint limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of shares that may be minted.
     * - MUST NOT revert.
     */
    function maxMint(address receiver) external view returns (uint256 maxShares);

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their mint at the current block, given
     * current on-chain conditions.
     *
     * - MUST return as close to and no fewer than the exact amount of assets that would be deposited in a mint call
     *   in the same transaction. I.e. mint should return the same or fewer assets as previewMint if called in the
     *   same transaction.
     * - MUST NOT account for mint limits like those returned from maxMint and should always act as though the mint
     *   would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewMint SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by minting.
     */
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the mint
     *   execution, and are accounted for during mint.
     * - MUST revert if all of shares cannot be minted (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /**
     * @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the
     * Vault, through a withdraw call.
     *
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block,
     * given current on-chain conditions.
     *
     * - MUST return as close to and no fewer than the exact amount of Vault shares that would be burned in a withdraw
     *   call in the same transaction. I.e. withdraw should return the same or fewer shares as previewWithdraw if
     *   called
     *   in the same transaction.
     * - MUST NOT account for withdrawal limits like those returned from maxWithdraw and should always act as though
     *   the withdrawal would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewWithdraw SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Burns shares from owner and sends exactly assets of underlying tokens to receiver.
     *
     * - MUST emit the Withdraw event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   withdraw execution, and are accounted for during withdraw.
     * - MUST revert if all of assets cannot be withdrawn (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * Note that some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /**
     * @dev Returns the maximum amount of Vault shares that can be redeemed from the owner balance in the Vault,
     * through a redeem call.
     *
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST return balanceOf(owner) if owner is not subject to any withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxRedeem(address owner) external view returns (uint256 maxShares);

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their redeemption at the current block,
     * given current on-chain conditions.
     *
     * - MUST return as close to and no more than the exact amount of assets that would be withdrawn in a redeem call
     *   in the same transaction. I.e. redeem should return the same or more assets as previewRedeem if called in the
     *   same transaction.
     * - MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the
     *   redemption would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewRedeem SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by redeeming.
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev Burns exactly shares from owner and sends assets of underlying tokens to receiver.
     *
     * - MUST emit the Withdraw event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   redeem execution, and are accounted for during redeem.
     * - MUST revert if all of shares cannot be redeemed (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * NOTE: some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

interface IERC7575Share is IERC165 {
    event VaultUpdate(address indexed asset, address vault);

    /**
     * @dev Returns the address of the Vault for the given asset.
     *
     * @param asset the ERC-20 token to deposit with into the Vault
     */
    function vault(address asset) external view returns (address);
}
