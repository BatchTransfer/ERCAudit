// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x07bc727c90103f471e493a0c9803ec48558dd3c2
// Contract Name: PrintrTelecoin



// ============================================================
// FILE: src/telecoin/PrintrTeleportingTelecoin.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPrintrTeleportingTelecoin } from "../interfaces/telecoin/IPrintrTeleportingTelecoin.sol";

import { Printed } from "./Printed.sol";
import { TeleportingTelecoin } from "./Teleporting.sol";

/**
 * @title PrintrTeleportingTelecoin
 * @notice Implementation of a Teleporting Telecoin with teleport capabilities and interchain functionality
 * @dev Extends Telecoin and InterchainStandard to provide cross-chain functionality
 */
contract PrintrTelecoin is IPrintrTeleportingTelecoin, Printed, TeleportingTelecoin {

    /**
     * @notice Initializes a PrintrTelecoin token with teleporting capabilities
     * @dev Combines Printed restrictions with TeleportingTelecoin functionality for multi-chain deployments.
     *      This token supports mint/burn teleportation across chains via ITS.
     * @param params Deployment parameters containing token configuration and ITS integration details
     * @param treasury Address of the treasury to receive initial token supply
     * @param initialSupply Initial token supply to mint to treasury (chain's portion of total supply)
     */
    constructor(
        TelecoinDeployParams memory params,
        address treasury,
        uint256 initialSupply
    ) Printed(params.printr, treasury, initialSupply, true) TeleportingTelecoin(params) { }

    /**
     * @notice Internal function to handle token transfers with teleporting capabilities and restrictions
     * @dev Override of TeleportingTelecoin._update that includes Printed contract restrictions.
     *      First checks if the transfer violates bonding curve completion rules,
     *      then performs the actual balance update with teleporting functionality.
     *      This ensures tokens cannot be added to liquidity pools before curve completion
     *      while maintaining cross-chain teleportation capabilities.
     * @param from The address tokens are being transferred from (address(0) for minting)
     * @param to The address tokens are being transferred to (address(0) for burning)
     * @param amount The amount of tokens being transferred
     * @custom:throws CurveIsNotComplete if attempting to add tokens to restricted pool before completion
     */
    function _update(address from, address to, uint256 amount) internal override(Printed, TeleportingTelecoin) {
        // Check POOL position opening restrictions
        Printed._update(from, to, amount);
        // Update balances
        TeleportingTelecoin._update(from, to, amount);
    }

}



// ============================================================
// FILE: src/interfaces/telecoin/IPrintrTeleportingTelecoin.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPrinted } from "./IPrinted.sol";
import { ITeleportingTelecoin } from "./ITeleporting.sol";

/**
 * @title IPrintrTeleportingTelecoin
 * @notice Interface for the PrintrTelecoin contract with teleport and curve completion functionality
 * @dev Extends ITelecoin interface with additional token management functions
 */
interface IPrintrTeleportingTelecoin is IPrinted, ITeleportingTelecoin { }



// ============================================================
// FILE: src/telecoin/Printed.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPrinted } from "../interfaces/telecoin/IPrinted.sol";
import { ITelecoin } from "../interfaces/telecoin/ITelecoin.sol";

import { TeleportingTelecoin } from "./Teleporting.sol";

/**
 * @title PrintrTelecoin
 * @notice Implementation of a Telecoin with teleport capabilities and interchain functionality
 * @dev Extends Telecoin and InterchainStandard to provide cross-chain functionality
 */
abstract contract Printed is IPrinted {

    /// @notice Whether this is a main telecoin (uses lock/unlock) or teleporting telecoin
    bool public immutable isTeleporting;

    /// @notice Address of the Printr contract that created this token
    address private immutable printr;

    /**
     * @notice Enum representing the different states of curve completion
     * @dev Used to track the progression of the bonding curve
     * @custom:value NotInitialized - Initial state before any completion actions
     * @custom:value Restricted - State where transfers are restricted to a specific pool
     * @custom:value Completed - Final state where curve is completed and unrestricted
     */
    enum CompletionState {
        NotInitialized, // Not yet initialized
        Restricted, // Restricted to specific pool
        Completed // Curve completed

    }

    /**
     * @notice Struct to pack pool address and state in single storage slot
     * @dev Packs address (160 bits) and state (8 bits) into 256 bits for gas optimization
     * @param pool The address of the liquidity pool (160 bits)
     * @param state The current completion state of the curve (8 bits)
     */
    struct CompletionStatus {
        address pool; // Pool address (160 bits)
        CompletionState state; // Completion state (8 bits)
    }

    /// @notice Tracks the completion status and restricted pool address
    CompletionStatus public completionStatus;

    /**
     * @notice Initializes the token with its basic parameters
     * @param _printr Address of the Printr contract that created this token
     * @param _treasury Address to receive the initial token supply
     * @param _initialSupply The initial supply to mint to treasury
     * @param _isTeleporting Whether this is a main telecoin (true) or wrapped telecoin (false)
     */
    constructor(address _printr, address _treasury, uint256 _initialSupply, bool _isTeleporting) {
        printr = _printr;
        isTeleporting = _isTeleporting;

        // Mint the chain total supply directly to the treasury
        _update(address(0), _treasury, _initialSupply);
    }

    /**
     * @notice Sets the restricted pool address during curve initialization
     * @dev Can only be called by Printr before completion. Updates the completion status
     *      to restrict transfers to the specified pool address until curve is marked complete.
     *      Uses atomic storage writes for gas efficiency.
     * @param poolAddress The pool address to restrict transfers to during curve completion phase
     * @custom:throws UnauthorizedAccount if caller is not Printr or curve is already complete
     * @custom:throws ZeroAddress if pool address is zero
     */
    function setRestrictedPool(
        address poolAddress
    ) external {
        if (poolAddress == address(0)) {
            revert ITelecoin.ZeroAddress();
        }
        if (msg.sender != printr || completionStatus.state == CompletionState.Completed) {
            revert ITelecoin.UnauthorizedAccount(msg.sender);
        }

        // Write the entire struct atomically in a single SSTORE
        completionStatus = CompletionStatus({ pool: poolAddress, state: CompletionState.Restricted });
    }

    /**
     * @notice Marks the bonding curve as completed, removing transfer restrictions
     * @dev Can only be called by Printr when curve is not already completed.
     *      Clears the restricted pool address and sets state to Completed, allowing
     *      unrestricted token transfers. Uses atomic storage writes for gas efficiency.
     * @custom:throws UnauthorizedAccount if caller is not Printr or curve is already completed
     */
    function markCurveComplete() external {
        if (msg.sender != printr || completionStatus.state == CompletionState.Completed) {
            revert ITelecoin.UnauthorizedAccount(msg.sender);
        }

        // Write the entire struct atomically in a single SSTORE
        // Clear pool address when marking complete
        completionStatus = CompletionStatus({ pool: address(0), state: CompletionState.Completed });
    }

    /**
     * @notice Internal hook to handle token transfers
     * @dev Prevents adding tokens to liquidity pool before curve completion
     * param from Address tokens are transferred from
     * @param to Address tokens are transferred to
     * param value Amount of tokens being transferred
     * @custom:dev Inheriting contract must call super._update()
     * @custom:throws CurveIsNotComplete if attempting to add to pool before completion
     */
    function _update(address, /*from*/ address to, uint256 /*value*/ ) internal virtual {
        // Read entire struct from storage once
        CompletionStatus memory status = completionStatus;

        // Disable adding token to liquidity pool before completion
        if (status.state == CompletionState.Restricted && to == status.pool) {
            revert CurveIsNotComplete();
        }

        /// @DEV: Make sure inheriting contract calls ERC20._update()
    }

}



// ============================================================
// FILE: src/telecoin/Teleporting.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPrintrTeleport } from "../interfaces/printr/IPrintrTeleport.sol";
import { ITeleportingTelecoin } from "../interfaces/telecoin/ITeleporting.sol";

import { ERC20 } from "./ERC20.sol";
import { InterchainStandard } from "./InterchainStandard.sol";
import { Telecoin } from "./Telecoin.sol";

/**
 * @title Teleporting
 * @notice Base ERC20 token with teleport capabilities
 * @dev Extends ERC20 and InterchainStandard to provide cross-chain teleport functionality
 */
contract TeleportingTelecoin is ITeleportingTelecoin, Telecoin {

    /**
     * @notice Constructor for TeleportingTelecoin
     * @param params Deployment parameters struct containing token configuration
     */
    constructor(
        TelecoinDeployParams memory params
    ) Telecoin(params) { }

    /**
     * @notice Teleports tokens into existence for cross-chain transfers
     * @dev Can only be called by the ITS token manager or Printr
     * @param to Address to receive the teleported tokens
     * @param value Amount of tokens to teleport in
     */
    function teleportIn(address to, uint256 value) public {
        if (msg.sender != itsTokenManager && msg.sender != printr) {
            revert UnauthorizedAccount(msg.sender);
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }

        emit TeleportIn(telecoinId, to, value);
        _update(address(this), to, value);
    }

    /**
     * @notice Teleports tokens out of existence for cross-chain transfers
     * @dev Can be called by ITS, ITS Token Manager, or Printr
     * @param from Address to teleport tokens from
     * @param value Amount of tokens to teleport out
     */
    function teleportOut(address from, uint256 value) public {
        if (msg.sender != address(interchainTokenService) && msg.sender != itsTokenManager && msg.sender != printr) {
            revert UnauthorizedAccount(msg.sender);
        }
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }

        if (msg.sender == address(interchainTokenService) || msg.sender == itsTokenManager) {
            IPrintrTeleport(printr).processInterchainTransfer(telecoinId, from, value);
        }

        emit TeleportOut(telecoinId, from, value);
        _decreaseAllowance(from, msg.sender, value);
        _update(from, address(this), value);
    }

    /**
     * @notice Internal function to update balances and total supply
     * @dev Overrides ERC20 _update to handle teleporting via teleportIn/teleportOut
     * @param from Address tokens are transferred from (address(this) for teleporting in)
     * @param to Address tokens are transferred to (address(this) for teleporting out)
     * @param value Amount of tokens to transfer
     * @custom:throws ERC20InsufficientBalance if 'from' has insufficient balance
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(this) || from == address(0)) {
            // Teleporting in - increase total supply
            totalSupply += value;
        } else {
            // Transfer or teleport out - decrease from balance
            uint256 fromBalance = balanceOf[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                balanceOf[from] = fromBalance - value;
            }
        }

        if (to == address(this) || to == address(0)) {
            // Teleporting out - decrease total supply
            unchecked {
                totalSupply -= value;
            }
        } else {
            // Transfer or teleport in - increase to balance
            unchecked {
                balanceOf[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @notice Fallback function that handles teleport operations for backwards compatibility
     * @dev Decodes calldata and routes to teleportIn/teleportOut functions
     */
    fallback() external {
        if (msg.data.length < 4) {
            revert InvalidFunctionSelector();
        }

        bytes4 selector = bytes4(msg.data[:4]);
        (address account, uint256 amount) = abi.decode(msg.data[4:], (address, uint256));

        // teleportIn selector: 0x40c10f19 (mint))
        if (selector == 0x40c10f19) {
            teleportIn(account, amount);
            return;
        }
        // teleportOut selector: 0x9dc29fac (burn) or 0x79cc6790 (burnFrom)
        if (selector == 0x9dc29fac || selector == 0x79cc6790) {
            teleportOut(account, amount);
            return;
        }

        revert InvalidFunctionSelector();
    }

}



// ============================================================
// FILE: src/interfaces/telecoin/IPrinted.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IPrintrTeleportingTelecoin
 * @notice Interface for the PrintrTelecoin contract with teleport and curve completion functionality
 * @dev Extends ITelecoin interface with additional token management functions
 */
interface IPrinted {

    /**
     * @notice Error thrown when attempting to interact with an incomplete curve
     * @dev This error is typically thrown when trying to add liquidity before curve completion
     */
    error CurveIsNotComplete();

    /**
     * @notice Returns whether this is a main telecoin (uses lock/unlock) or teleporting telecoin
     * @return True if this is a main telecoin, false if it's a teleporting telecoin
     */
    function isTeleporting() external view returns (bool);

    /**
     * @notice Sets the restricted pool address during curve initialization
     * @dev Can only be called by Printr before completion
     * @param poolAddress The pool address to restrict transfers to
     * @custom:throws UnauthorizedAccount if caller is not Printr or curve is already complete
     * @custom:throws ZeroAddress if pool address is zero
     */
    function setRestrictedPool(
        address poolAddress
    ) external;

    /**
     * @notice Marks the curve as completed, removing transfer restrictions
     * @dev Can only be called by Printr when curve is not already completed
     * @custom:throws UnauthorizedAccount if caller is not Printr or curve is already completed
     */
    function markCurveComplete() external;

}



// ============================================================
// FILE: src/interfaces/telecoin/ITeleporting.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ITelecoin } from "./ITelecoin.sol";

/**
 * @title ITeleportingTelecoin
 * @notice Interface for the TeleportingTelecoin contract with teleporting capabilities
 * @dev Extends ITelecoin for teleport functionality with ITS integration
 */
interface ITeleportingTelecoin is ITelecoin {

    /**
     * @notice Error thrown when invalid function selector is provided
     */
    error InvalidFunctionSelector();

    /**
     * @notice Teleports tokens into existence for cross-chain transfers
     * @param to Address to receive the tokens
     * @param value Amount of tokens to teleport in
     */
    function teleportIn(address to, uint256 value) external;

    /**
     * @notice Teleports tokens out of existence for cross-chain transfers
     * @param from Address whose tokens are being teleported out
     * @param value Amount of tokens to teleport out
     */
    function teleportOut(address from, uint256 value) external;

}



// ============================================================
// FILE: src/interfaces/telecoin/ITelecoin.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IOFT } from "../layerzero/IOFT.sol";
import { IPrintrTeleport } from "../printr/IPrintrTeleport.sol";
import { IERC20Witness } from "./IERC20Witness.sol";
import { IInterchainStandard } from "./IInterchainStandard.sol";

/**
 * @title ITelecoin
 * @notice Interface for the Telecoin base contract
 * @dev Extends IERC20 for base teleport functionality
 */
interface ITelecoin is IERC20Witness, IInterchainStandard, IOFT {

    /**
     * @notice Struct containing deployment parameters for telecoin contracts
     * @param name Token name
     * @param symbol Token symbol
     * @param maxSupply Maximum supply of the token
     * @param treasury Treasury address to receive initial supply
     * @param interchainTokenService Interchain Token Service address
     * @param itsTokenManager Token manager address
     * @param telecoinId Universal telecoin ID
     * @param interchainTokenId Interchain token ID for ITS compatibility
     */
    struct TelecoinDeployParams {
        bytes32 telecoinId;
        string name;
        string symbol;
        uint256 maxSupply;
        address printr;
        address interchainTokenService;
        address itsTokenManager;
        bytes32 interchainTokenId;
    }

    /**
     * @notice Error thrown when a zero address is provided where not allowed
     */
    error ZeroAddress();

    /**
     * @notice Error thrown when an unauthorized account attempts a restricted operation
     * @param account The address that attempted the unauthorized operation
     */
    error UnauthorizedAccount(address account);

    /**
     * @notice Error thrown when an invalid protocol is specified
     */
    error InvalidProtocol();

    /**
     * @notice Emitted when tokens are teleported in from another chain
     * @param telecoinId The universal token ID
     * @param to The address receiving the tokens
     * @param value The amount of tokens teleported in
     */
    event TeleportIn(bytes32 indexed telecoinId, address indexed to, uint256 value);

    /**
     * @notice Emitted when tokens are teleported out to another chain
     * @param telecoinId The universal token ID
     * @param from The address from which tokens are teleported
     * @param value The amount of tokens teleported out
     */
    event TeleportOut(bytes32 indexed telecoinId, address indexed from, uint256 value);

    /**
     * @notice Returns the universal token ID (deploySalt)
     * @dev This value is immutable and set during contract construction
     * @return The universal token ID based on deployment salt
     */
    function telecoinId() external view returns (bytes32);

    /**
     * @notice Returns the address of the Printr contract that created this token
     * @dev This value is immutable and set during contract construction
     * @return The address of the Printr contract
     */
    function printr() external view returns (address);

    /**
     * @notice Returns the address of the ITS token manager for minting and burning
     * @dev This value is immutable and set during contract construction
     * @return The address of the ITS token manager
     */
    function itsTokenManager() external view returns (address);

    /**
     * @notice Quotes the total teleport fee for any protocol
     * @dev Delegates to PrintrTeleport's quoteTeleportFee for fee calculation
     * @param params The teleport parameters struct (includes protocol)
     * @return totalNativeFee The total fee in native currency (protocol fee + bridge fee)
     * @return basePairFee The fee in base pair tokens (0 if base pair is native)
     * @return basePair The base pair address (address(0) if native)
     * @return bridgeFee The bridge-specific gas fee (ITS gas fee or LZ messaging fee)
     */
    function quoteTeleportFee(
        IPrintrTeleport.TeleportParams memory params
    ) external returns (uint256 totalNativeFee, uint256 basePairFee, address basePair, uint256 bridgeFee);

    /**
     * @notice Teleports tokens from sender to a destination chain
     * @param params The teleport parameters struct (includes protocol)
     */
    function teleport(
        IPrintrTeleport.TeleportParams calldata params
    ) external payable;

    /**
     * @notice Teleports tokens from a specified sender to a destination chain
     * @param sender The sender of the tokens (must have approved msg.sender)
     * @param params The teleport parameters struct (includes protocol)
     */
    function teleportFrom(address sender, IPrintrTeleport.TeleportParams calldata params) external payable;

}



// ============================================================
// FILE: src/interfaces/printr/IPrintrTeleport.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPrintrStorage } from "../printr/IPrintrStorage.sol";

/**
 * @title IPrintrTeleport
 * @notice Interface for PrintrTeleport contract that handles cross-chain messaging with Solana
 * @dev This interface defines the functionality for sending and receiving messages between EVM and Solana
 *      using the Teleport message protocol for token transfers
 */
interface IPrintrTeleport is IPrintrStorage {

    /**
     * @notice Error thrown when payload has invalid length
     */
    error InvalidPayloadLength();

    /**
     * @notice Error thrown when message kind is unexpected
     */
    error UnexpectedMessageKind();

    /**
     * @notice Error thrown when endpoint address is invalid
     */
    error InvalidEndpoint();

    /**
     * @notice Error thrown when solana program address is invalid
     */
    error InvalidSolanaProgram();

    /**
     * @notice Error thrown when sender is not authorized
     */
    error UnauthorizedSender();

    /**
     * @notice Error thrown when contract has insufficient fee balance
     */
    error InsufficientFee();

    /**
     * @notice Error thrown when fee transfer fails
     */
    error FeeTransferFailed();

    /**
     * @notice Error thrown when an invalid protocol is specified
     */
    error InvalidProtocol();

    /**
     * @notice Error thrown when the chain ID length is invalid
     */
    error InvalidChainIdLength();

    /**
     * @notice Error thrown when a non-numeric character is found in chain ID
     */
    error InvalidNumericCharacter();

    /**
     * @notice Error thrown when the endpoint ID is invalid
     */
    error InvalidEndpointId();

    /**
     * @notice Error thrown when calldata is invalid
     */
    error InvalidCalldata();

    /**
     * @notice Error thrown when security level is invalid
     */
    error InvalidSecurityLevel();

    /**
     * @notice Error thrown when protocol is not in global whitelist
     */
    error ProtocolNotWhitelisted();

    /**
     * @notice Error thrown when protocol is in token blacklist
     */
    error ProtocolBlacklisted();

    /**
     * @notice Error thrown when invalid protocol bit position used
     */
    error InvalidProtocolBitPosition();

    /**
     * @notice Error thrown when teleport amount exceeds maximum supported value
     * @dev Maximum supported amount is type(uint64).max * 1e9 (in 18 decimals)
     * @param requestedAmount The amount that was requested to teleport
     * @param maxAmount The maximum amount that can be teleported
     */
    error TeleportAmountOverflow(uint256 requestedAmount, uint256 maxAmount);

    /**
     * @notice Protocol enum for teleportation methods
     * @dev Must match the Protocol enum in ITelecoin for compatibility
     */
    enum TeleportProtocol {
        UNSPECIFIED, // 0 - Used to catch malformed transactions
        ITS, // 1 - Interchain Token Service
        LZ_FAST, // 2 - Fast LayerZero channel with minimal confirmations
        LZ_SECURE, // 3 - Secure LayerZero channel with balanced confirmations
        LZ_SLOW // 4 - Slow LayerZero channel with maximum confirmations

    }

    /**
     * @notice Struct containing constructor parameters for LayerZero deployment
     * @param itsFlatFee Flat fee for ITS transfers
     * @param itsBipsFee Basis points fee for ITS transfers
     * @param lzFlatFee Flat fee for LayerZero transfers
     * @param lzBipsFee Basis points fee for LayerZero transfers
     * @param lzEndpoint LayerZero endpoint address for this chain
     * @param fastSolanaLzPeer Solana LayerZero peer address for fast/low security channel
     * @param secureSolanaLzPeer Solana LayerZero peer address for secure/medium security channel
     * @param slowSolanaLzPeer Solana LayerZero peer address for slow/high security channel
     * @param lzReceiveGasLimit Gas limit for LayerZero receive operations
     * @param lzReceiveNativeDrop Native drop amount for LayerZero receive operations
     */
    struct TeleportDeployParams {
        uint256 itsFlatFee;
        uint16 itsBipsFee;
        uint256 lzFlatFee;
        uint16 lzBipsFee;
        address lzEndpoint;
        bytes32 fastSolanaLzPeer;
        bytes32 secureSolanaLzPeer;
        bytes32 slowSolanaLzPeer;
        uint128 lzReceiveGasLimit;
        uint128 lzReceiveNativeDrop;
    }

    /**
     * @notice Struct containing teleport parameters
     * @param destChain The destination chain identifier
     * @param destAddress The bytes representation of the address of the recipient
     * @param amount The amount of tokens to be transferred
     * @param metadata Additional data for the cross-chain transfer
     * @param protocol The teleportation protocol to use (ITS, LZ_FAST, LZ_SECURE, LZ_SLOW)
     */
    struct TeleportParams {
        string destChain;
        bytes destAddress;
        uint256 amount;
        bytes metadata;
        TeleportProtocol protocol;
    }

    /**
     * @notice Event emitted when a new LayerZero delegate is set for a channel
     * @param protocol The teleport protocol (LZ_FAST, LZ_SECURE, LZ_SLOW)
     * @param delegate Address of the new LayerZero delegate
     */
    event LzDelegateUpdated(TeleportProtocol indexed protocol, address indexed delegate);

    /**
     * @notice Event emitted when global protocol whitelist is updated
     * @param newWhitelist The new whitelist bitmap
     */
    event TeleportProtocolWhitelistUpdated(bytes32 indexed newWhitelist);

    /**
     * @notice Event emitted when a token's protocol blacklist is updated
     * @param telecoinId The telecoin ID
     * @param newBlacklist The new blacklist bitmap
     */
    event TelecoinProtocolBlacklistUpdated(bytes32 indexed telecoinId, bytes32 indexed newBlacklist);

    /**
     * @notice Event emitted when tokens are teleported to another chain
     * @param telecoinId The ID of the token being transferred
     * @param tokenAddress The address of the token contract
     * @param sourceAddress The address initiating the transfer
     * @param destChain The target chain for the transfer
     * @param destAddress The address on the destination chain
     * @param amount The amount of tokens being transferred
     */
    event Teleporting(
        bytes32 indexed telecoinId,
        address indexed tokenAddress,
        address indexed sourceAddress,
        string destChain,
        bytes destAddress,
        uint256 amount
    );

    // ============================================
    // EXTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Calculates the universal token ID based on token parameters
     * @dev Returns the telecoinId as a universal token ID that's vendor-agnostic
     * @param tokenParams Parameters for the token deployment
     * @return telecoinId The universal token ID
     */
    function getTelecoinId(
        TelecoinParams calldata tokenParams
    ) external pure returns (bytes32 telecoinId);

    /**
     * @notice Sets the LayerZero delegate address for a specific channel
     * @dev Only callable by the contract owner or authorized account
     * @param protocol The teleport protocol to configure (LZ_FAST, LZ_SECURE, LZ_SLOW)
     * @param delegate Address of the new LayerZero delegate
     */
    function setLzDelegate(TeleportProtocol protocol, address delegate) external;

    /**
     * @notice Gets the LZChannel address for a specific protocol
     * @param protocol The teleport protocol (LZ_FAST, LZ_SECURE, LZ_SLOW)
     * @return channel Address of the LZChannel contract for this protocol
     */
    function getLzChannel(
        TeleportProtocol protocol
    ) external view returns (address channel);

    /**
     * @notice Updates the global protocol whitelist by enabling and/or disabling protocols
     * @dev Only callable by the contract owner. Processes disable array first, then enable array.
     * @param enable Array of protocols to enable globally
     * @param disable Array of protocols to disable globally
     */
    function updateGlobalProtocols(TeleportProtocol[] calldata enable, TeleportProtocol[] calldata disable) external;

    /**
     * @notice Gets the global protocol whitelist bitmap
     * @return whitelist Bitmap of enabled protocols
     */
    function getTeleportProtocolWhitelist() external view returns (bytes32 whitelist);

    /**
     * @notice Updates the protocol blacklist for a specific telecoin
     * @dev Only callable by the contract owner. Processes enable array first (removes from blacklist), then disable
     * array (adds to blacklist).
     * @param telecoinId The ID of the telecoin
     * @param enable Array of protocols to enable for this telecoin (remove from blacklist)
     * @param disable Array of protocols to disable for this telecoin (add to blacklist)
     */
    function updateTelecoinProtocols(
        bytes32 telecoinId,
        TeleportProtocol[] calldata enable,
        TeleportProtocol[] calldata disable
    ) external;

    /**
     * @notice Gets a token's protocol blacklist bitmap
     * @param telecoinId The telecoin ID
     * @return blacklist Bitmap of disabled protocols for this token
     */
    function getTelecoinProtocolBlacklist(
        bytes32 telecoinId
    ) external view returns (bytes32 blacklist);

    /**
     * @notice Checks if a protocol is allowed for a specific token
     * @dev Returns true if protocol is in global whitelist AND NOT in token blacklist
     * @param telecoinId The telecoin ID
     * @param protocol The protocol to check
     * @return allowed True if protocol is allowed for this token
     */
    function isProtocolAllowed(bytes32 telecoinId, TeleportProtocol protocol) external view returns (bool allowed);

    /**
     * @notice Quotes the total teleport fee for any protocol
     * @dev Consolidates fee calculation for ITS, LayerZero, and future protocols
     * @param token Token address to transfer
     * @param params The teleport parameters struct (includes protocol)
     * @return totalNativeFee The total fee in native currency (protocol fee + bridge fee)
     * @return basePairFee The fee in base pair tokens (0 if base pair is native)
     * @return basePair The base pair address (address(0) if native)
     * @return bridgeFee The bridge-specific gas fee (ITS gas fee or LZ messaging fee)
     */
    function quoteTeleportFee(
        address token,
        TeleportParams calldata params
    ) external returns (uint256 totalNativeFee, uint256 basePairFee, address basePair, uint256 bridgeFee);

    /**
     * @notice Universal teleport function that routes to ITS or LayerZero
     * @dev Routes tokens to the appropriate cross-chain protocol based on params.protocol
     * @param token The token address to teleport
     * @param params The teleport parameters struct (includes protocol)
     */
    function teleport(address token, TeleportParams calldata params) external payable;

    /**
     * @notice Universal teleport function with witness signature support
     * @dev Called via permitWitnessCall to enable signature-based teleportation
     * @dev Signer must be the first param to protect from permitWitnessCall attacks
     * @param signer Address initiating the teleport, must be first parameter
     * @param telecoinId The telecoin ID instead of token address
     * @param params The teleport parameters struct (includes protocol)
     */
    function witnessTeleport(address signer, bytes32 telecoinId, TeleportParams calldata params) external payable;

    /**
     * @notice Transmits a LayerZero cross-chain token transfer
     * @dev Called by token contracts to initiate LayerZero transfers
     * @dev telecoinId first param, to protect from permitWitnessCall calls
     * @param telecoinId Universal token ID (32 bytes)
     * @param sender Address initiating the transfer
     * @param params The teleport parameters struct
     */
    function transmitLzSend(bytes32 telecoinId, address sender, TeleportParams calldata params) external payable;

    /**
     * @notice Broadcasts an interchain transfer event
     * @dev Emits an InterchainTransfer event with the provided parameters
     * @dev telecoinId first param, to protect from permitWitnessCall calls
     * @param telecoinId The ID of the token being transferred
     * @param sourceAddress The address initiating the transfer
     * @param destChain The target chain for the transfer
     * @param destAddress The address on the destination chain
     * @param amount The amount of tokens being transferred
     */
    function broadcastInterchainTransfer(
        bytes32 telecoinId,
        address sourceAddress,
        string calldata destChain,
        bytes calldata destAddress,
        uint256 amount
    ) external;

    /**
     * @notice Processes an incoming interchain transfer from Solana
     * @dev Processes tokens for the specified sender based on the received message
     * @param telecoinId The ID of the token being transferred
     * @param sender The address receiving the tokens
     * @param amount The amount of tokens to process
     */
    function processInterchainTransfer(bytes32 telecoinId, address sender, uint256 amount) external;

    // ============================================
    // EXTERNAL VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Gets the LayerZero endpoint address
     * @return The LayerZero endpoint address
     */
    function lzEndpoint() external view returns (address);

    /**
     * @notice Gets the current gas limit for LayerZero receive operations
     * @return gasLimit Current gas limit
     */
    function lzReceiveGasLimit() external view returns (uint128 gasLimit);

    /**
     * @notice Gets the current native drop amount for LayerZero receive operations
     * @return nativeDrop Current native drop amount
     */
    function lzReceiveNativeDrop() external view returns (uint128 nativeDrop);

    /**
     * @notice Receives teleport messages from authorized channels
     * @dev Called by LZChannel contracts to forward processed messages
     * @param protocol The teleport protocol of the calling channel (LZ_FAST, LZ_SECURE, LZ_SLOW)
     * @param originSender The LayerZero origin sender address (Solana peer or self)
     * @param message The processed teleport payload
     */
    function receiveFromChannel(
        TeleportProtocol protocol,
        bytes32 originSender,
        bytes calldata message
    ) external payable;

}



// ============================================================
// FILE: src/telecoin/ERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Permit } from "../interfaces/telecoin/IERC20Permit.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
 * @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
 * @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
 */
contract ERC20 is IERC20Permit, IERC20Metadata, IERC20Errors {

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public immutable decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ERC20 token with metadata and EIP-2612 permit functionality
     * @dev Sets up the token name, symbol, decimals and initializes EIP-712 domain separator for permit signatures
     * @param _name The human-readable name of the token (e.g. "My Token")
     * @param _symbol The token symbol used on exchanges (e.g. "MTK")
     * @param _decimals Number of decimal places for token amounts (typically 18 for most ERC20 tokens)
     */
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves another account to spend tokens on behalf of the caller
     * @dev Implements the standard ERC20 approve function with unlimited allowance support
     * @param spender The address that will be allowed to spend the tokens
     * @param value The amount of tokens to approve for spending (in token's decimal units)
     * @return Always returns true to indicate successful approval
     */
    function approve(address spender, uint256 value) public virtual returns (bool) {
        allowance[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);

        return true;
    }

    /**
     * @notice Transfers tokens from the caller to another address
     * @dev Uses internal _update function to handle balance changes and emit Transfer event
     * @param to The recipient address to transfer tokens to
     * @param value The amount of tokens to transfer (in token's decimal units)
     * @return Always returns true to indicate successful transfer
     */
    function transfer(address to, uint256 value) public virtual returns (bool) {
        _update(msg.sender, to, value);
        return true;
    }

    /**
     * @notice Transfers tokens from one address to another using allowance mechanism
     * @dev Checks and updates allowance before transferring. Unlimited allowance (type(uint256).max) is not
     * decremented
     * @param from The address to transfer tokens from (must have sufficient balance)
     * @param to The recipient address to transfer tokens to
     * @param value The amount of tokens to transfer (in token's decimal units)
     * @return Always returns true to indicate successful transfer
     */
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = msg.sender;
        uint256 allowed = allowance[from][spender];

        if (allowed != type(uint256).max) {
            if (allowed < value) {
                revert ERC20InsufficientAllowance(spender, allowed, value);
            }
            allowance[from][spender] = allowed - value;
        }

        _update(from, to, value);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Permits an allowance to be set via signature, implementing EIP-2612
     * @dev Validates the signature against EIP-712 typed data and sets allowance without requiring a transaction from
     * owner
     * @param owner The address that owns the tokens and is granting the allowance
     * @param spender The address that will be allowed to spend the tokens
     * @param value The amount of tokens to approve for spending (in token's decimal units)
     * @param deadline The timestamp after which the permit signature is no longer valid
     * @param v The recovery identifier of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (deadline < block.timestamp) {
            revert ERC2612ExpiredSignature(deadline);
        }

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            bytes32 structHash =
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));

            bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

            address recoveredAddress = ecrecover(hash, v, r, s);

            if (recoveredAddress == address(0) || recoveredAddress != owner) {
                revert ERC2612InvalidSigner(recoveredAddress, owner);
            }

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    /**
     * @notice Returns the domain separator for EIP-712 signature validation
     * @dev Returns cached separator if chain ID hasn't changed, otherwise recomputes it
     * @return The EIP-712 domain separator hash for this contract and chain
     */
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    /**
     * @notice Computes the EIP-712 domain separator for the current chain and contract
     * @dev Used for EIP-712 signature validation in permit functions
     * @return The computed domain separator hash including contract name, version, chain ID, and address
     */
    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL UPDATE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to handle token transfers, mints, and burns
     * @dev Handles balance updates and total supply changes. Emits Transfer event for all operations
     * @param from The address to transfer from (address(0) for minting)
     * @param to The address to transfer to (address(0) for burning)
     * @param value The amount of tokens to transfer/mint/burn (in token's decimal units)
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            // Increase total supply
            totalSupply += value;
        } else {
            // Transfer - decrease from balance
            uint256 fromBalance = balanceOf[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                balanceOf[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            // Decrease total supply
            unchecked {
                totalSupply -= value;
            }
        } else {
            // Transfer or mint - increase to balance
            unchecked {
                balanceOf[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

}



// ============================================================
// FILE: src/telecoin/InterchainStandard.sol
// ============================================================
// SPDX-License-Identifier: MIT
// https://github.com/axelarnetwork/interchain-token-service/blob/main/contracts/interchain-token/InterchainTokenStandard.sol

pragma solidity ^0.8.0;

import { IInterchainTokenService } from "../interfaces/its/IInterchainTokenService.sol";
import { IInterchainStandard } from "../interfaces/telecoin/IInterchainStandard.sol";

/**
 * @title An example implementation of the IInterchainTokenStandard.
 * @notice The is an abstract contract that needs to be extended with an ERC20 implementation. See `InterchainToken` for
 * an example implementation.
 */
abstract contract InterchainStandard is IInterchainStandard {

    IInterchainTokenService public immutable interchainTokenService;
    bytes32 public immutable interchainTokenId;

    /**
     * @notice Constructor for InterchainStandard
     * @dev Initializes the ITS integration by setting the token service and token ID
     * @param _interchainTokenService Address of the Interchain Token Service contract
     * @param _interchainTokenId Unique identifier for this token in the ITS system
     */
    constructor(address _interchainTokenService, bytes32 _interchainTokenId) {
        interchainTokenService = IInterchainTokenService(_interchainTokenService);
        interchainTokenId = _interchainTokenId;
    }

    /**
     * @notice Implementation of the interchainTransfer method
     * @dev We chose to either pass `metadata` as raw data on a remote contract call, or if no data is passed, just do a
     * transfer.
     * A different implementation could use metadata to specify a function to invoke, or for other purposes as well.
     * @param destinationChain The destination chain identifier.
     * @param recipient The bytes representation of the address of the recipient.
     * @param amount The amount of token to be transferred.
     * @param metadata Either empty, just to facilitate an interchain transfer, or the data to be passed for an
     * interchain contract call with transfer
     * as per semantics defined by the token service.
     */
    function interchainTransfer(
        string calldata destinationChain,
        bytes calldata recipient,
        uint256 amount,
        bytes calldata metadata
    ) public payable {
        address sender = msg.sender;

        _beforeInterchainTransfer(msg.sender, destinationChain, recipient, amount, metadata);

        IInterchainTokenService(interchainTokenService).transmitInterchainTransfer{ value: address(this).balance }(
            interchainTokenId, sender, destinationChain, recipient, amount, metadata
        );
    }

    /**
     * @notice Transfers tokens from a sender to a recipient on a destination chain using allowance
     * @dev Requires prior approval from sender. Decreases allowance before executing cross-chain transfer
     * @param sender The address owning the tokens (must have approved msg.sender)
     * @param destinationChain The destination chain identifier (e.g., "ethereum", "arbitrum")
     * @param recipient The bytes representation of the recipient address on destination chain
     * @param amount The amount of tokens to transfer
     * @param metadata Additional data for the transfer, can be empty or contain call data
     */
    function interchainTransferFrom(
        address sender,
        string calldata destinationChain,
        bytes calldata recipient,
        uint256 amount,
        bytes calldata metadata
    ) public payable {
        _decreaseAllowance(sender, msg.sender, amount);

        _beforeInterchainTransfer(sender, destinationChain, recipient, amount, metadata);

        IInterchainTokenService(interchainTokenService).transmitInterchainTransfer{ value: address(this).balance }(
            interchainTokenId, sender, destinationChain, recipient, amount, metadata
        );
    }

    /**
     * @notice A method to be overwritten that will be called before an interchain transfer. One can approve the
     * tokenManager here if needed,
     * to allow users for a 1-call transfer in case of a lock-unlock token manager.
     * @param from The sender of the tokens. They need to have approved `msg.sender` before this is called.
     * @param destinationChain The string representation of the destination chain.
     * @param destinationAddress The bytes representation of the address of the recipient.
     * @param amount The amount of token to be transferred.
     * @param metadata Either empty, just to facilitate an interchain transfer, or the data to be passed to an
     * interchain contract call and transfer.
     */
    function _beforeInterchainTransfer(
        address from,
        string calldata destinationChain,
        bytes calldata destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) internal virtual { }

    /**
     * @notice Decreases the allowance of a spender for a sender's tokens
     * @dev Virtual function that must be implemented by inheriting contracts. Should preserve infinite allowance when
     * applicable
     * @param sender Address owning the tokens
     * @param spender Address spending the tokens
     * @param amount Amount to decrease the allowance by
     */
    function _decreaseAllowance(address sender, address spender, uint256 amount) internal virtual;

}



// ============================================================
// FILE: src/telecoin/Telecoin.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IInterchainTokenService } from "../interfaces/its/IInterchainTokenService.sol";
import { IPrintrTeleport } from "../interfaces/printr/IPrintrTeleport.sol";
import { ITelecoin } from "../interfaces/telecoin/ITelecoin.sol";

import { ERC20 } from "./ERC20.sol";
import { ERC20Witness } from "./ERC20Witness.sol";
import { InterchainStandard } from "./InterchainStandard.sol";
import { OftStandard } from "./OftStandard.sol";

/**
 * @title Telecoin
 * @notice Base ERC20 token with teleport capabilities and witness permit functionality
 * @dev Extends ERC20Witness and InterchainStandard to provide cross-chain teleport functionality
 */
contract Telecoin is ITelecoin, ERC20Witness, InterchainStandard, OftStandard {

    /// @notice Printr Telecoin ID
    bytes32 public immutable telecoinId;

    /// @notice Maximum total supply of the token
    uint256 public immutable maxSupply;

    /// @notice Address of the Printr contract that created this token
    address public immutable printr;

    /// @notice Address of the ITS token manager for minting and burning
    address public immutable itsTokenManager;

    /**
     * @notice Constructor for Telecoin
     * @param params Deployment parameters struct containing token configuration
     */
    constructor(
        TelecoinDeployParams memory params
    )
        ERC20Witness(params.name, params.symbol, 18)
        InterchainStandard(params.interchainTokenService, params.interchainTokenId)
    {
        if (
            params.printr == address(0) || params.interchainTokenService == address(0)
                || params.itsTokenManager == address(0)
        ) {
            revert ZeroAddress();
        }

        telecoinId = params.telecoinId;
        maxSupply = params.maxSupply;
        printr = params.printr;
        itsTokenManager = params.itsTokenManager;
    }

    /**
     * @notice Quotes the total teleport fee for any protocol (external interface)
     * @param params The teleport parameters struct (includes protocol)
     * @return totalNativeFee The total fee in native currency (protocol fee + bridge fee)
     * @return basePairFee The fee in base pair tokens (0 if base pair is native)
     * @return basePair The base pair address (address(0) if native)
     * @return bridgeFee The bridge-specific gas fee (ITS gas fee or LZ messaging fee)
     */
    function quoteTeleportFee(
        IPrintrTeleport.TeleportParams memory params
    )
        public
        override(ITelecoin)
        returns (uint256 totalNativeFee, uint256 basePairFee, address basePair, uint256 bridgeFee)
    {
        return _quoteTeleportFee(params);
    }

    /**
     * @notice Teleports tokens from sender to a destination chain
     * @dev Routes to ITS or LayerZero based on params.protocol
     * @param params The teleport parameters struct (includes protocol)
     */
    function teleport(
        IPrintrTeleport.TeleportParams calldata params
    ) public payable virtual {
        if (params.protocol == IPrintrTeleport.TeleportProtocol.UNSPECIFIED) {
            revert InvalidProtocol();
        }

        if (params.protocol == IPrintrTeleport.TeleportProtocol.ITS) {
            _itsTeleport(msg.sender, params);
            return;
        }

        _lzTeleport(msg.sender, params);
    }

    /**
     * @notice Teleports tokens from a specified address to a destination chain
     * @dev Routes to ITS or LayerZero based on params.protocol
     * @param from The sender of the tokens (must have approved msg.sender)
     * @param params The teleport parameters struct (includes protocol)
     */
    function teleportFrom(address from, IPrintrTeleport.TeleportParams calldata params) public payable virtual {
        if (params.protocol == IPrintrTeleport.TeleportProtocol.UNSPECIFIED) {
            revert InvalidProtocol();
        }

        if (params.protocol == IPrintrTeleport.TeleportProtocol.ITS) {
            _itsTeleport(from, params);
            return;
        }

        _lzTeleport(from, params);
    }

    /**
     * @notice Transfer tokens from one address to another with special ITS token manager handling
     * @dev If called by the ITS token manager, triggers Printr interchain transfer processing
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param value Amount to transfer
     * @return bool True if transfer succeeded
     */
    function transferFrom(address from, address to, uint256 value) public override(ERC20, IERC20) returns (bool) {
        if (msg.sender == itsTokenManager) {
            IPrintrTeleport(printr).processInterchainTransfer(telecoinId, to, value);
        }
        return super.transferFrom(from, to, value);
    }

    /**
     * @notice Internal function to decrease allowance
     * @dev Preserves infinite allowance when value is max uint256
     * @param sender Address owning the tokens
     * @param spender Address spending the tokens
     * @param value Amount to decrease allowance by
     */
    function _decreaseAllowance(address sender, address spender, uint256 value) internal override {
        uint256 _allowance = allowance[sender][spender];

        if (_allowance < value) {
            revert ERC20InsufficientAllowance(spender, _allowance, value);
        }

        if (_allowance != type(uint256).max) {
            allowance[sender][spender] = _allowance - value;
        }
    }

    /**
     * @notice Internal function to broadcast interchain transfer event
     * @dev Calls the printr contract (which is PrintrTeleport) to emit the transfer event
     * @param sourceAddress Address initiating the transfer
     * @param destChain Target chain for the transfer
     * @param destAddress Address on the destination chain
     * @param value Amount being transferred
     */
    function _beforeInterchainTransfer(
        address sourceAddress,
        string calldata destChain,
        bytes calldata destAddress,
        uint256 value,
        bytes calldata /*metadata*/
    ) internal override {
        IPrintrTeleport(printr).broadcastInterchainTransfer(
            telecoinId, // telecoinId first to protect from permitWitnessCall attacks
            sourceAddress,
            destChain,
            destAddress,
            value
        );
    }

    /**
     * @notice Internal fee quote implementation for OftStandard
     * @dev Overrides OftStandard's virtual function, delegates to PrintrTeleport
     * @param params The teleport parameters struct (includes protocol)
     * @return totalNativeFee The total fee in native currency (protocol fee + bridge fee)
     * @return basePairFee The fee in base pair tokens (0 if base pair is native)
     * @return basePair The base pair address (address(0) if native)
     * @return bridgeFee The bridge-specific gas fee (ITS gas fee or LZ messaging fee)
     */
    function _quoteTeleportFee(
        IPrintrTeleport.TeleportParams memory params
    ) internal override returns (uint256 totalNativeFee, uint256 basePairFee, address basePair, uint256 bridgeFee) {
        return IPrintrTeleport(printr).quoteTeleportFee(address(this), params);
    }

    /**
     * @notice Internal ITS teleport execution logic
     * @dev Handles ITS protocol fee payment and calls appropriate interchain transfer function
     * @param from The address sending the tokens
     * @param params The teleport parameters struct (includes protocol)
     */
    function _itsTeleport(address from, IPrintrTeleport.TeleportParams calldata params) internal {
        // Get the teleport fee using the unified function
        (uint256 totalNativeFee,,, uint256 bridgeFee) = IPrintrTeleport(printr).quoteTeleportFee(address(this), params);

        // Transfer only the protocol fee to printr (excluding bridge gas fee)
        uint256 protocolFee = totalNativeFee - bridgeFee;
        if (protocolFee > 0) {
            payable(printr).transfer(protocolFee);
        }

        // Keep the bridge fee in the contract for ITS to use
        // Use interchainTransfer if from == msg.sender, otherwise use interchainTransferFrom
        if (from == msg.sender) {
            interchainTransfer(params.destChain, params.destAddress, params.amount, params.metadata);
        } else {
            interchainTransferFrom(from, params.destChain, params.destAddress, params.amount, params.metadata);
        }
    }

    /**
     * @notice Internal LayerZero teleport execution logic
     * @dev Handles protocol routing for teleport(), teleportFrom(), and OftStandard's send()
     * @param from The address sending the tokens
     * @param params The teleport parameters (memory to support both calldata and memory callers)
     */
    function _lzTeleport(address from, IPrintrTeleport.TeleportParams memory params) internal override {
        // For LZ protocols
        if (
            params.protocol == IPrintrTeleport.TeleportProtocol.LZ_FAST
                || params.protocol == IPrintrTeleport.TeleportProtocol.LZ_SECURE
                || params.protocol == IPrintrTeleport.TeleportProtocol.LZ_SLOW
        ) {
            // Use LayerZero for teleportation via PrintrTeleport
            IPrintrTeleport(printr).transmitLzSend{ value: msg.value }(telecoinId, from, params);
            return;
        }

        revert InvalidProtocol();
    }

}



// ============================================================
// FILE: src/interfaces/layerzero/IOFT.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ILayerZeroEndpointV2 } from "./ILayerZeroEndpointV2.sol";

/**
 * @dev Struct representing token parameters for the OFT send() operation.
 */
struct SendParam {
    uint32 dstEid; // Destination endpoint ID
    bytes32 to; // Recipient address
    uint256 amountLD; // Amount to send in local decimals
    uint256 minAmountLD; // Minimum amount to send in local decimals
    bytes extraOptions; // Additional options for LayerZero message
    bytes composeMsg; // Composed message for send() operation
    bytes oftCmd; // OFT command (unused in default implementations)
}

/**
 * @dev Struct representing OFT limit information.
 */
struct OFTLimit {
    uint256 minAmountLD; // Minimum amount in local decimals
    uint256 maxAmountLD; // Maximum amount in local decimals
}

/**
 * @dev Struct representing OFT receipt information.
 */
struct OFTReceipt {
    uint256 amountSentLD; // Amount debited from sender
    uint256 amountReceivedLD; // Amount to be received on remote side
}

/**
 * @dev Struct representing OFT fee details.
 */
struct OFTFeeDetail {
    int256 feeAmountLD; // Amount of fee in local decimals
    string description; // Description of the fee
}

/**
 * @title IOFT
 * @dev Interface for the Omnichain Fungible Token (OFT) standard.
 * @dev Interface ID: 0x02e49c2c
 */
interface IOFT {

    // Custom errors
    error InvalidLocalDecimals();
    error SlippageExceeded(uint256 amountLD, uint256 minAmountLD);

    // Events
    event OFTSent(
        bytes32 indexed guid, uint32 dstEid, address indexed fromAddress, uint256 amountSentLD, uint256 amountReceivedLD
    );

    event OFTReceived(bytes32 indexed guid, uint32 srcEid, address indexed toAddress, uint256 amountReceivedLD);

    /**
     * @notice Retrieves interfaceID and version of the OFT.
     * @return interfaceId The interface ID (0x02e49c2c).
     * @return version The version.
     */
    function oftVersion() external view returns (bytes4 interfaceId, uint64 version);

    /**
     * @notice Retrieves the address of the token associated with the OFT.
     * @return token The address of the ERC20 token implementation.
     */
    function token() external view returns (address);

    /**
     * @notice Indicates whether the OFT contract requires approval of the 'token()' to send.
     * @return requiresApproval Whether approval is required.
     */
    function approvalRequired() external view returns (bool);

    /**
     * @notice Retrieves the shared decimals of the OFT.
     * @return sharedDecimals The shared decimals (typically 6).
     */
    function sharedDecimals() external view returns (uint8);

    /**
     * @notice Provides a quote for OFT-related operations.
     * @param _sendParam The parameters for the send operation.
     * @return limit The OFT limit information.
     * @return oftFeeDetails The details of OFT fees.
     * @return receipt The OFT receipt information.
     */
    function quoteOFT(
        SendParam calldata _sendParam
    ) external returns (OFTLimit memory limit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory receipt);

    /**
     * @notice Provides a quote for the send() operation.
     * @param _sendParam The parameters for the send() operation.
     * @param _payInLzToken Flag indicating whether the caller is paying in the LZ token.
     * @return fee The calculated LayerZero messaging fee.
     */
    function quoteSend(
        SendParam calldata _sendParam,
        bool _payInLzToken
    ) external returns (ILayerZeroEndpointV2.MessagingFee memory fee);

    /**
     * @notice Executes the send() operation.
     * @param _sendParam The parameters for the send operation.
     * @param _fee The fee information supplied by the caller.
     * @param _refundAddress The address to receive any excess funds.
     * @return receipt The LayerZero messaging receipt.
     * @return oftReceipt The OFT receipt information.
     */
    function send(
        SendParam calldata _sendParam,
        ILayerZeroEndpointV2.MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (ILayerZeroEndpointV2.MessagingReceipt memory receipt, OFTReceipt memory oftReceipt);

}



// ============================================================
// FILE: src/interfaces/telecoin/IERC20Witness.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IERC20Permit } from "./IERC20Permit.sol";

/// @title IERC20Witness Interface
/// @notice Interface for ERC20 tokens with witness-based permit functionality
/// @dev Extends standard ERC20 with permitWitness functions that include additional validation data
interface IERC20Witness is IERC20Permit, IERC20Metadata, IERC20Errors {

    /*//////////////////////////////////////////////////////////////
                          WITNESS-SPECIFIC ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when an invalid witness value is provided
     * @dev The witness data failed validation checks
     */
    error ERC20InvalidWitness();

    /**
     * @notice Thrown when attempting to call the contract itself
     * @dev Self-calls are not permitted for security reasons
     */
    error ERC20InvalidCallTarget();

    /**
     * @notice Thrown when invalid call data is provided
     * @dev The call data format or content is malformed
     */
    error ERC20InvalidCallData();

    /**
     * @notice Thrown when an external call fails during witness operations
     * @dev The target contract call returned failure or reverted
     */
    error ERC20CallFailed();

    struct ContractCall {
        address target;
        string method;
        bytes params;
    }

    /*//////////////////////////////////////////////////////////////
                      PERMIT WITNESS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the permit witness typehash for EIP-712 signature encoding
     * @dev Used for permitWitness function signature validation
     * @return The keccak256 hash of the permit witness type string
     */
    function PERMIT_WITNESS_TYPEHASH() external view returns (bytes32);

    /**
     * @notice Returns the base permit witness type string for EIP-712 structured data
     * @dev Used as a prefix to construct full type strings with witness data
     * @return The base permit witness type string stub
     */
    function PERMIT_WITNESS_TYPESTRING_STAB() external view returns (string memory);

    /**
     * @notice Returns the contract call witness type string completion
     * @dev Appended to PERMIT_WITNESS_TYPESTRING_STAB to form complete EIP-712 type string
     * @return The contract call type string completion
     */
    function WITNESS_CALL_TYPESTRING() external view returns (string memory);

    /**
     * @notice Returns the contract call typehash for EIP-712 signature encoding
     * @dev Used for ContractCall struct hashing in witness validation
     * @return The keccak256 hash of the ContractCall type string
     */
    function WITNESS_CALL_TYPEHASH() external view returns (bytes32);

    /**
     * @notice Returns the witness type identifier for transfer operations
     * @dev Used to validate witness data in transfer contexts
     * @return The bytes32 identifier for transfer witness operations
     */
    function TRANSFER_WITNESS() external view returns (bytes32);

    /**
     * @notice Sets allowance using signature with additional witness validation
     * @dev Extends standard permit functionality with witness data for enhanced security
     * @param owner The owner of the tokens
     * @param spender The address authorized to spend the tokens
     * @param value The amount of tokens to authorize for spending
     * @param deadline The timestamp at which the permit expires
     * @param witness Additional validation data to prevent certain attack vectors
     * @param v The recovery parameter of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function permitWitness(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes32 witness,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Sets allowance using signature with custom witness type string for free-form witness data
     * @dev Extends permitWitness with witnessTypeString parameter to support various witness structures
     * @param owner The owner of the tokens
     * @param spender The address authorized to spend the tokens
     * @param value The amount of tokens to authorize for spending
     * @param deadline The timestamp at which the permit expires
     * @param witness Additional validation data hash to prevent certain attack vectors
     * @param witnessTypeString The EIP-712 type string for the witness data structure
     * @param v The recovery parameter of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function permitWitness(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes32 witness,
        string calldata witnessTypeString,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Permits and executes a direct transfer using signature authorization
     * @dev Combines permit and transferFrom into a single operation with witness validation
     * @param owner The owner of the tokens to transfer
     * @param spender The recipient address for the transfer
     * @param value The amount of tokens to transfer
     * @param deadline The timestamp at which the permit expires
     * @param v The recovery parameter of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     * @return success Whether the transfer operation was successful
     */
    function permitTransferFrom(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool success);

    /**
     * @notice Permits token allowance and executes an external call in one transaction
     * @dev Combines permit functionality with external contract interaction using witness validation
     * @param owner The owner of the tokens
     * @param spender The address authorized to spend the tokens
     * @param value The amount of tokens to authorize for spending
     * @param deadline The timestamp at which the permit expires
     * @param call ContractCall struct containing target address, method signature, and parameters
     * @param v The recovery parameter of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     * @return returnData The return data from the executed external call
     */
    function permitWitnessCall(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        ContractCall calldata call,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable returns (bytes memory returnData);

}



// ============================================================
// FILE: src/interfaces/telecoin/IInterchainStandard.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IInterchainTokenService } from "../its/IInterchainTokenService.sol";

/**
 * @title IInterchainStandard Interface
 * @notice This interface defines functions for cross-chain token transfers.
 */
interface IInterchainStandard {

    /**
     * @notice Returns the Interchain Token Service instance.
     * @return The IInterchainTokenService contract instance.
     */
    function interchainTokenService() external view returns (IInterchainTokenService);

    /**
     * @notice Returns the interchain token identifier.
     * @return The bytes32 identifier of the interchain token.
     */
    function interchainTokenId() external view returns (bytes32);

    /**
     * @notice Implementation of the interchainTransfer method.
     * @dev We chose to either pass `metadata` as raw data on a remote contract call, or if no data is passed, just do a
     * transfer.
     * A different implementation could use metadata to specify a function to invoke, or for other purposes as well.
     * @param destinationChain The destination chain identifier.
     * @param recipient The bytes representation of the address of the recipient.
     * @param amount The amount of token to be transferred.
     * @param metadata Optional metadata for the call for additional effects (such as calling a destination contract).
     */
    function interchainTransfer(
        string calldata destinationChain,
        bytes calldata recipient,
        uint256 amount,
        bytes calldata metadata
    ) external payable;

    /**
     * @notice Implementation of the interchainTransferFrom method
     * @dev We chose to either pass `metadata` as raw data on a remote contract call, or, if no data is passed, just do
     * a transfer.
     * A different implementation could use metadata to specify a function to invoke, or for other purposes as well.
     * @param sender The sender of the tokens. They need to have approved `msg.sender` before this is called.
     * @param destinationChain The string representation of the destination chain.
     * @param recipient The bytes representation of the address of the recipient.
     * @param amount The amount of token to be transferred.
     * @param metadata Optional metadata for the call for additional effects (such as calling a destination contract.)
     */
    function interchainTransferFrom(
        address sender,
        string calldata destinationChain,
        bytes calldata recipient,
        uint256 amount,
        bytes calldata metadata
    ) external payable;

}



// ============================================================
// FILE: src/interfaces/printr/IPrintrStorage.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ITreasury } from "../ITreasury.sol";

/**
 * @title Printr Storage Interface
 * @notice Interface for the Printr contract, which manages tokens with linear bonding curves
 * @dev All price calculations use PRECISION_SCALAR (1e18) for accurate floating point math
 *      Implements cross-chain token deployment through ITelecoinFactory integration
 *      This interface defines the core storage and view functions for the Printr system
 */
interface IPrintrStorage {

    /// @notice Custom errors for the Printr contract
    error FeeIsTooHigh(uint256 fee);
    error WrongChainName();
    error InsufficientPayment();
    error InsufficientInitialBuy();
    error InvalidBasePairDecimals();
    error InvalidBasePrices();
    error InvalidBasePairs();
    error InvalidCreatorAddress();
    error InvalidInitialPrice();
    error InvalidLength();
    error TooHighThreshold();
    error ZeroAmount();
    error PoolCreationFailed();
    error TokenNotFound();
    error SwapFailed();
    error LiquidityAlreadyDeployed();
    error LiquidityDeploymentFailed();
    error InvalidQuoteResult();
    error PriceExceedsLimit();
    error RefundFailed();
    error RenounceOwnershipDisabled();
    error InvalidImplementation();
    error FeePercentagesMustSum();
    error UnauthorizedCaller();
    error Create2AddressMismatch();

    /**
     * @notice Parameters structure for telecoin deployment
     * @dev Uses bytes32 for efficient storage and cross-chain compatibility
     * @param salt Unique identifier for deployment
     * @param creatorAddresses Creator addresses for different chains encoded as bytes
     * @param name Telecoin name encoded as bytes32, 31 characters max
     * @param symbol Telecoin symbol encoded as bytes32, 31 characters max
     * @param packedParams Packed parameters bit layout:
     *                     [0-7]     uint8   maxTokenSupplyE (power of 10)
     *                     [8-23]    uint16  completionThreshold (basis points, max 10000)
     *                     [24-135]  uint112 initialPrice, assuming 18 decimal places for both tokens
     *                     [136-255] uint120 initialBuySpending, assuming 18 decimal places
     * @param chains Chain names encoded as bytes32, first chain is the home chain
     * @param basePairs Base currency token addresses encoded as bytes32
     * @param basePrices Initial prices in base currency per chain as uint128 packed in bytes, 18 decimals for both
     */
    struct TelecoinParams {
        bytes32 salt;
        bytes creatorAddresses;
        bytes32 name;
        bytes32 symbol;
        bytes32 packedParams;
        bytes32[] chains;
        bytes32[] basePairs;
        bytes basePrices;
    }

    /**
     * @notice Unpacked version of the packedParams for easier handling
     * @dev Packed bytes32 converted into individual parameters
     * @param maxTokenSupplyE Maximum token supply as power of 10
     * @param completionThreshold Completion threshold in basis points (max 10000) of max supply
     * @param initialPrice Initial token price, assuming 18 decimal places for both tokens
     * @param initialBuySpending Initial buy amount, assuming 18 decimal places
     */
    struct UnpackedParams {
        uint8 maxTokenSupplyE;
        uint256 completionThreshold;
        uint256 initialPrice;
        uint256 initialBuySpending;
    }

    /**
     * @notice Comprehensive information about a token's configuration and state
     * @dev Whole struct is packed into 2 storage slots for efficiency
     * @param basePair Address of the base currency token (160 bits)
     * @param totalCurves Number of curves across all chains (16 bits)
     * @param maxTokenSupplyE Maximum token supply as pow of 10 (8 bits)
     * @param virtualReserveE Precision scalar for virtualReserve (8 bits)
     * @param virtualReserve Compressed virtual reserve balance for bonding curve (64 bits)
     * @param reserve Current reserve balance of the base currency token (192 bits)
     * @param completionThreshold Threshold for curve completion as percentage of total supply (64 bits)
     */
    struct Curve {
        /// @dev Slot 1: immutable (160 + 16 + 8 + 8 + 64 = 256 bits, fits in 1 slot)
        address basePair;
        uint16 totalCurves;
        uint8 maxTokenSupplyE;
        uint8 virtualReserveE;
        uint64 virtualReserve;
        /// @dev Slot 2: mutable (192 + 64 = 256 bits)
        uint192 reserve;
        uint64 completionThreshold;
    }

    /**
     * @notice Readable format of curve information
     * @param basePair Base currency token address
     * @param totalCurves Total number of curves across chains
     * @param maxTokenSupply Maximum token supply
     * @param virtualReserve Virtual reserve for curve calculations (already scaled with virtualReserveE)
     * @param reserve Current base currency reserve
     * @param completionThreshold Completion threshold value
     */
    struct CurveInfo {
        address basePair;
        uint16 totalCurves;
        uint256 maxTokenSupply;
        uint256 virtualReserve;
        uint256 reserve;
        uint256 completionThreshold;
    }

    /**
     * @notice Parameters for deploying Printr contracts
     * @dev Used to avoid stack too deep errors in constructor
     * @param chainName Name of the blockchain network
     * @param treasury Address of the treasury contract
     * @param mainTelecoinFactory Address of the main token factory contract
     * @param teleportingTelecoinFactory Address of the teleporting token factory contract
     * @param its Address of the Interchain Token Service
     * @param itsFactory Address of the ITS factory
     * @param wrappedNativeToken Address of wrapped native token (e.g., WETH)
     * @param locker Address of the locker contract
     * @param liquidityModule Address of the liquidity module
     * @param growthFundFund Address of the growth fund
     * @param buybackFund Address of the buyback
     * @param teamTreasuryFund Address of the team treasury
     * @param stakingFund Address of the staking
     * @param printrDev Address of the dev NFT contract
     * @param feePercentGrowth Fee percentage for growth fund in basis points
     * @param feePercentBuyback Fee percentage for buyback in basis points
     * @param feePercentTeam Fee percentage for team treasury in basis points
     * @param feePercentCreator Fee percentage for creator in basis points
     * @param tradingFee Trading fee percentage in basis points
     */
    struct DeploymentParams {
        string chainName;
        address treasury;
        address mainTelecoinFactory;
        address teleportingTelecoinFactory;
        address its;
        address itsFactory;
        address wrappedNativeToken;
        address locker;
        address liquidityModule;
        address growthFund;
        address buybackFund;
        address teamTreasuryFund;
        address stakingFund;
        address printrDev;
        uint256 feePercentGrowth;
        uint256 feePercentBuyback;
        uint256 feePercentTeam;
        uint256 feePercentCreator;
        uint16 tradingFee;
    }

    /// @notice Returns the current chain's hash identifier
    function currentChainHash() external view returns (bytes32);

    /// @notice Returns the treasury contract address
    function treasury() external view returns (ITreasury);

    /// @notice Returns the main token factory contract address
    function mainTelecoinFactory() external view returns (address);

    /// @notice Returns the teleporting token factory contract address
    function teleportingTelecoinFactory() external view returns (address);

    /// @notice Returns the ITS contract address
    function interchainTokenService() external view returns (address);

    /// @notice Returns the ITS factory contract address
    function itsFactory() external view returns (address);

    /// @notice Returns the wrapped native token address
    function wrappedNativeToken() external view returns (address);

    /// @notice Returns the liquidity module contract address
    function liquidityModule() external view returns (address);

    /// @notice Returns the locker contract address
    function locker() external view returns (address);

    /// @notice Returns the growth fund address
    function growthFund() external view returns (address);

    /// @notice Returns the buyback address
    function buybackFund() external view returns (address);

    /// @notice Returns the team treasury address
    function teamTreasuryFund() external view returns (address);

    /// @notice Returns the staking address
    function stakingFund() external view returns (address);

    /// @notice Returns the creator NFT contract address
    function printrDev() external view returns (address);

    /// @notice Returns the fee percentage for growth fund
    function feePercentGrowth() external view returns (uint256);

    /// @notice Returns the fee percentage for buyback
    function feePercentBuyback() external view returns (uint256);

    /// @notice Returns the fee percentage for team treasury
    function feePercentTeam() external view returns (uint256);

    /// @notice Returns the fee percentage for creator
    function feePercentCreator() external view returns (uint256);

    /// @notice Returns the trading fee percentage in basis points
    function tradingFee() external view returns (uint16);

}



// ============================================================
// FILE: src/interfaces/telecoin/IERC20Permit.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IERC20Permit Interface with Errors
/// @notice Interface for ERC20 Permit extension with proper error definitions
/// @dev Extends the standard EIP-2612 permit functionality with error definitions
interface IERC20Permit {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when a permit signature has expired
     * @param deadline The timestamp at which the signature expired
     */
    error ERC2612ExpiredSignature(uint256 deadline);

    /**
     * @notice Thrown when the recovered signer does not match the expected owner
     * @param signer The address recovered from the signature
     * @param owner The expected owner address
     */
    error ERC2612InvalidSigner(address signer, address owner);

    /*//////////////////////////////////////////////////////////////
                          PERMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current nonce for the given owner
     * @dev This value must be included whenever a signature is generated for permit
     * @param owner The address to get the nonce for
     * @return The current nonce value for the owner
     */
    function nonces(
        address owner
    ) external view returns (uint256);

    /**
     * @notice Returns the domain separator used in the encoding of signatures
     * @dev Used to prevent signature replay attacks across different domains
     * @return The EIP-712 domain separator hash
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Returns the permit typehash used in EIP-712 signature encoding
     * @dev Constant value defining the structure of permit messages
     * @return The keccak256 hash of the permit type string
     */
    function PERMIT_TYPEHASH() external view returns (bytes32);

    /**
     * @notice Sets allowance using EIP-2612 signature-based authorization
     * @dev Allows setting allowance without requiring a separate transaction from the token owner
     * @param owner The owner of the tokens
     * @param spender The address authorized to spend the tokens
     * @param value The amount of tokens to authorize for spending
     * @param deadline The timestamp at which the permit expires
     * @param v The recovery parameter of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
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



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/draft-IERC6093.sol)
pragma solidity ^0.8.20;

/**
 * @dev Standard ERC20 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC20 tokens.
 */
interface IERC20Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC20InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC20InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC20InvalidSpender(address spender);
}

/**
 * @dev Standard ERC721 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC721 tokens.
 */
interface IERC721Errors {
    /**
     * @dev Indicates that an address can't be an owner. For example, `address(0)` is a forbidden owner in EIP-20.
     * Used in balance queries.
     * @param owner Address of the current owner of a token.
     */
    error ERC721InvalidOwner(address owner);

    /**
     * @dev Indicates a `tokenId` whose `owner` is the zero address.
     * @param tokenId Identifier number of a token.
     */
    error ERC721NonexistentToken(uint256 tokenId);

    /**
     * @dev Indicates an error related to the ownership over a particular token. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param tokenId Identifier number of a token.
     * @param owner Address of the current owner of a token.
     */
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC721InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC721InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param tokenId Identifier number of a token.
     */
    error ERC721InsufficientApproval(address operator, uint256 tokenId);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC721InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC721InvalidOperator(address operator);
}

/**
 * @dev Standard ERC1155 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC1155 tokens.
 */
interface IERC1155Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     * @param tokenId Identifier number of a token.
     */
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC1155InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC1155InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param owner Address of the current owner of a token.
     */
    error ERC1155MissingApprovalForAll(address operator, address owner);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC1155InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC1155InvalidOperator(address operator);

    /**
     * @dev Indicates an array length mismatch between ids and values in a safeBatchTransferFrom operation.
     * Used in batch transfers.
     * @param idsLength Length of the array of token identifiers
     * @param valuesLength Length of the array of token amounts
     */
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";

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



// ============================================================
// FILE: src/interfaces/its/IInterchainTokenService.sol
// ============================================================
// SPDX-License-Identifier: MIT
// https://github.com/axelarnetwork/interchain-token-service/blob/main/contracts/interfaces/IInterchainTokenService.sol

pragma solidity ^0.8.0;

type ITokenManager is address;

/**
 * @title IInterchainGasEstimation Interface
 * @notice This is an interface for the InterchainGasEstimation contract
 * which allows for estimating gas fees for cross-chain communication on the Axelar network.
 */
interface IInterchainGasEstimation {

    /**
     * @notice Estimates the gas fee for a cross-chain contract call.
     * @param destinationChain Axelar registered name of the destination chain
     * @param destinationAddress Destination contract address being called
     * @param executionGasLimit The gas limit to be used for the destination contract execution,
     *        e.g. pass in 200k if your app consumes needs upto 200k for this contract call
     * @param params Additional parameters for the gas estimation
     * @return gasEstimate The cross-chain gas estimate, in terms of source chain's native gas token that should be
     * forwarded to the gas service.
     */
    function estimateGasFee(
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        uint256 executionGasLimit,
        bytes calldata params
    ) external view returns (uint256 gasEstimate);

}

/**
 * @title IInterchainTokenService Interface
 * @notice Interface for the Interchain Token Service
 */
interface IInterchainTokenService {

    enum TokenManagerType {
        NATIVE_INTERCHAIN_TOKEN, // This type is reserved for interchain tokens deployed by ITS, and can't be used by
            // custom token managers.
        MINT_BURN_FROM, // The token will be minted/burned on transfers. The token needs to give mint permission to the
            // token manager, but burning happens via an approval.
        LOCK_UNLOCK, // The token will be locked/unlocked at the token manager.
        LOCK_UNLOCK_FEE, // The token will be locked/unlocked at the token manager, which will account for any
            // fee-on-transfer behaviour.
        MINT_BURN // The token will be minted/burned on transfers. The token needs to give mint and burn permission to
            // the token manager.

    }

    event InterchainTransfer(
        bytes32 indexed tokenId,
        address indexed sourceAddress,
        string destinationChain,
        bytes destinationAddress,
        uint256 amount,
        bytes32 indexed dataHash
    );
    event InterchainTransferReceived(
        bytes32 indexed commandId,
        bytes32 indexed tokenId,
        string sourceChain,
        bytes sourceAddress,
        address indexed destinationAddress,
        uint256 amount,
        bytes32 dataHash
    );
    event TokenMetadataRegistered(address indexed tokenAddress, uint8 decimals);
    event LinkTokenStarted(
        bytes32 indexed tokenId,
        string destinationChain,
        bytes sourceTokenAddress,
        bytes destinationTokenAddress,
        TokenManagerType indexed tokenManagerType,
        bytes params
    );
    event InterchainTokenDeploymentStarted(
        bytes32 indexed tokenId,
        string tokenName,
        string tokenSymbol,
        uint8 tokenDecimals,
        bytes minter,
        string destinationChain
    );
    event TokenManagerDeployed(
        bytes32 indexed tokenId, address tokenManager, TokenManagerType indexed tokenManagerType, bytes params
    );
    event InterchainTokenDeployed(
        bytes32 indexed tokenId,
        address tokenAddress,
        address indexed minter,
        string name,
        string symbol,
        uint8 decimals
    );
    event InterchainTokenIdClaimed(bytes32 indexed tokenId, address indexed deployer, bytes32 indexed salt);

    /**
     * @notice Returns the address of the interchain gas service contract.
     * @return gasService The instance of the IInterchainGasEstimation contract.
     */
    function gasService() external view returns (IInterchainGasEstimation);

    /**
     * @notice Returns the address of the ITS Hub contract.
     * @return hubAddress The address of the ITS Hub contract.
     */
    function itsHubAddress() external view returns (string memory hubAddress);

    /**
     * @notice Returns the address of the token manager deployer contract.
     * @return tokenManagerDeployerAddress The address of the token manager deployer contract.
     */
    function tokenManagerDeployer() external view returns (address tokenManagerDeployerAddress);

    /**
     * @notice Returns the address of the interchain token deployer contract.
     * @return interchainTokenDeployerAddress The address of the interchain token deployer contract.
     */
    function interchainTokenDeployer() external view returns (address interchainTokenDeployerAddress);

    /**
     * @notice Returns the address of TokenManager implementation.
     * @return tokenManagerAddress_ The address of the token manager contract.
     */
    function tokenManager() external view returns (address tokenManagerAddress_);

    /**
     * @notice Returns the address of TokenHandler implementation.
     * @return tokenHandlerAddress The address of the token handler contract.
     */
    function tokenHandler() external view returns (address tokenHandlerAddress);

    /**
     * @notice Returns the address of the interchain token factory.
     * @return address The address of the interchain token factory.
     */
    function interchainTokenFactory() external view returns (address);

    /**
     * @notice Returns the hash of the chain name.
     * @return bytes32 The hash of the chain name.
     */
    function chainNameHash() external view returns (bytes32);

    /**
     * @notice Returns the address of the token manager associated with the given tokenId.
     * @param tokenId The tokenId of the token manager.
     * @return tokenManagerAddress_ The address of the token manager.
     */
    function tokenManagerAddress(
        bytes32 tokenId
    ) external view returns (address tokenManagerAddress_);

    /**
     * @notice Returns the instance of ITokenManager from a specific tokenId.
     * @param tokenId The tokenId of the deployed token manager.
     * @return tokenManager_ The instance of ITokenManager associated with the specified tokenId.
     */
    function deployedTokenManager(
        bytes32 tokenId
    ) external view returns (ITokenManager tokenManager_);

    /**
     * @notice Returns the address of the token that an existing tokenManager points to.
     * @param tokenId The tokenId of the registered token.
     * @return tokenAddress The address of the token.
     */
    function registeredTokenAddress(
        bytes32 tokenId
    ) external view returns (address tokenAddress);

    /**
     * @notice Returns the address of the interchain token associated with the given tokenId.
     * @param tokenId The tokenId of the interchain token.
     * @return tokenAddress The address of the interchain token.
     */
    function interchainTokenAddress(
        bytes32 tokenId
    ) external view returns (address tokenAddress);

    /**
     * @notice Returns the custom tokenId associated with the given operator and salt.
     * @param operator_ The operator address.
     * @param salt The salt used for token id calculation.
     * @return tokenId The custom tokenId associated with the operator and salt.
     */
    function interchainTokenId(address operator_, bytes32 salt) external view returns (bytes32 tokenId);

    /**
     * @notice Registers metadata for a token on the ITS Hub. This metadata is used for scaling linked tokens.
     * The token metadata must be registered before linkToken can be called for the corresponding token.
     * @param tokenAddress The address of the token.
     * @param gasValue The cross-chain gas value for sending the registration message to ITS Hub.
     */
    function registerTokenMetadata(address tokenAddress, uint256 gasValue) external payable;

    /**
     * @notice Only to be used by the InterchainTokenFactory to register custom tokens to this chain. Then link token
     * can be used to register those tokens to other chains.
     * @param salt A unique salt to derive tokenId from.
     * @param tokenManagerType The type of the token manager to use for the token registration.
     * @param linkParams The operator for the token.
     */
    function registerCustomToken(
        bytes32 salt,
        address tokenAddress,
        TokenManagerType tokenManagerType,
        bytes calldata linkParams
    ) external payable returns (bytes32 tokenId);

    /**
     * @notice If `destinationChain` is an empty string, this function will register the token address on the current
     * chain.
     * Otherwise, it will link the token address on the destination chain with the token corresponding to the tokenId on
     * the current chain.
     * A token manager is deployed on EVM chains that's responsible for managing the linked token.
     * @dev This function replaces the prior `deployTokenManager` function.
     * @param salt A unique identifier to allow for multiple tokens registered per deployer.
     * @param destinationChain The chain to link the token to. Pass an empty string for this chain.
     * @param destinationTokenAddress The token address to link, as bytes.
     * @param tokenManagerType The type of the token manager to use to send and receive tokens.
     * @param linkParams Additional parameteres to use to link the token. Fow not it is just the address of the
     * operator.
     * @param gasValue Pass a non-zero value only for remote linking, which should be the gas to use to pay for the
     * contract call.
     * @return tokenId The tokenId associated with the token manager.
     */
    function linkToken(
        bytes32 salt,
        string calldata destinationChain,
        bytes memory destinationTokenAddress,
        TokenManagerType tokenManagerType,
        bytes memory linkParams,
        uint256 gasValue
    ) external payable returns (bytes32 tokenId);

    /**
     * @notice Deploys and registers an interchain token on a remote chain.
     * @param salt The salt used for token deployment.
     * @param destinationChain The name of the destination chain. Use '' for this chain.
     * @param name The name of the interchain tokens.
     * @param symbol The symbol of the interchain tokens.
     * @param decimals The number of decimals for the interchain tokens.
     * @param minter The minter data for mint/burn operations.
     * @param gasValue The gas value for deployment.
     * @return tokenId The tokenId corresponding to the deployed InterchainToken.
     */
    function deployInterchainToken(
        bytes32 salt,
        string calldata destinationChain,
        string memory name,
        string memory symbol,
        uint8 decimals,
        bytes memory minter,
        uint256 gasValue
    ) external payable returns (bytes32 tokenId);

    /**
     * @notice Initiates an interchain transfer of a specified token to a destination chain.
     * @param tokenId The unique identifier of the token to be transferred.
     * @param destinationChain The destination chain to send the tokens to.
     * @param destinationAddress The address on the destination chain to send the tokens to.
     * @param amount The amount of tokens to be transferred.
     * @param metadata Optional metadata for the call for additional effects (such as calling a destination contract).
     */
    function interchainTransfer(
        bytes32 tokenId,
        string calldata destinationChain,
        bytes calldata destinationAddress,
        uint256 amount,
        bytes calldata metadata,
        uint256 gasValue
    ) external payable;

    /**
     * @notice Sets the flow limits for multiple tokens.
     * @param tokenIds An array of tokenIds.
     * @param flowLimits An array of flow limits corresponding to the tokenIds.
     */
    function setFlowLimits(bytes32[] calldata tokenIds, uint256[] calldata flowLimits) external;

    /**
     * @notice Allows the owner to pause/unpause the token service.
     * @param paused whether to pause or unpause.
     */
    function setPauseStatus(
        bool paused
    ) external;

    /**
     * @notice Allows the owner to migrate legacy tokens that cannot be migrated automatically.
     * @param tokenId the tokenId of the registered token.
     */
    function migrateInterchainToken(
        bytes32 tokenId
    ) external;

    /**
     * @notice Transmit an interchain transfer for the given tokenId.
     * @dev Only callable by a token registered under a tokenId.
     * @param tokenId The tokenId of the token (which must be the msg.sender).
     * @param sourceAddress The address where the token is coming from.
     * @param destinationChain The name of the chain to send tokens to.
     * @param destinationAddress The destinationAddress for the interchainTransfer.
     * @param amount The amount of token to give.
     * @param metadata Optional metadata for the call for additional effects (such as calling a destination contract).
     */
    function transmitInterchainTransfer(
        bytes32 tokenId,
        address sourceAddress,
        string calldata destinationChain,
        bytes memory destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) external payable;

}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
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



// ============================================================
// FILE: src/telecoin/ERC20Witness.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../interfaces/telecoin/IERC20Witness.sol";

import "./ERC20.sol";

/**
 * @notice ERC20 extension with witness-based permit functionality for enhanced security
 * @dev Extends ERC20 with permitWitness functions that include additional validation data
 */
contract ERC20Witness is IERC20Witness, ERC20 {

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant PERMIT_WITNESS_TYPEHASH = keccak256(
        "PermitWitness(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline,bytes32 witness)"
    );

    string public constant PERMIT_WITNESS_TYPESTRING_STAB =
        "PermitWitness(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline,";

    string public constant WITNESS_CALL_TYPESTRING =
        "ContractCall call)ContractCall(address target,string method,bytes params)";

    bytes32 public constant WITNESS_CALL_TYPEHASH = keccak256("ContractCall(address target,string method,bytes params)");

    // Witness type prefixes to prevent signature collision between different witness functions
    bytes32 public constant TRANSFER_WITNESS = bytes32(0);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ERC20Witness token with metadata and witness-based permit functionality
     * @dev Calls parent ERC20 constructor to set up basic token functionality with added witness capabilities
     * @param _name The human-readable name of the token (e.g. "My Token")
     * @param _symbol The token symbol used on exchanges (e.g. "MTK")
     * @param _decimals Number of decimal places for token amounts (typically 18 for most ERC20 tokens)
     */
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) { }

    /*//////////////////////////////////////////////////////////////
                          PERMIT WITNESS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets allowance via signature with additional witness data for enhanced security
     * @dev Extends EIP-2612 permit with witness parameter to prevent signature replay across different contexts
     * @param owner The address that owns the tokens and is granting the allowance
     * @param spender The address that will be allowed to spend the tokens
     * @param value The amount of tokens to approve for spending (in token's decimal units)
     * @param deadline The timestamp after which the permit signature is no longer valid
     * @param witness Additional context data hash to prevent cross-context signature replay
     * @param v The recovery identifier of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function permitWitness(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes32 witness,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (witness == TRANSFER_WITNESS) {
            revert ERC20InvalidWitness();
        }

        _validatePermitWitness(owner, spender, value, deadline, witness, v, r, s);

        allowance[owner][spender] = value;

        emit Approval(owner, spender, value);
    }

    /**
     * @notice Sets allowance via signature with additional witness data for enhanced security
     * @dev Extends EIP-2612 permit with witness parameter to prevent signature replay across different contexts
     * @param owner The address that owns the tokens and is granting the allowance
     * @param spender The address that will be allowed to spend the tokens
     * @param value The amount of tokens to approve for spending (in token's decimal units)
     * @param deadline The timestamp after which the permit signature is no longer valid
     * @param witness Additional context data hash to prevent cross-context signature replay
     * @param v The recovery identifier of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function permitWitness(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes32 witness,
        string memory witnessTypeString,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (witness == TRANSFER_WITNESS) {
            revert ERC20InvalidWitness();
        }

        _validatePermitWitness(owner, spender, value, deadline, witness, witnessTypeString, v, r, s);

        allowance[owner][spender] = value;

        emit Approval(owner, spender, value);
    }

    /**
     * @notice Executes a direct transfer via signature without setting persistent allowance
     * @dev Uses witness-based permit with TRANSFER_WITNESS to authorize a one-time transfer
     * @param owner The address that owns the tokens and is authorizing the transfer
     * @param spender The address that will receive the tokens (typically msg.sender)
     * @param value The amount of tokens to transfer (in token's decimal units)
     * @param deadline The timestamp after which the permit signature is no longer valid
     * @param v The recovery identifier of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     * @return Always returns true to indicate successful transfer
     */
    function permitTransferFrom(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns (bool) {
        // Use permitWitness to set the allowance
        _validatePermitWitness(owner, spender, value, deadline, TRANSFER_WITNESS, v, r, s);

        // Execute the transfer
        _update(owner, spender, value);
        return true;
    }

    /**
     * @notice Executes an external contract call with permit-based authorization
     * @dev Sets allowance via witness permit then executes arbitrary call. Witness is derived from call data to
     * prevent replay
     * @param owner The address that owns the tokens and is authorizing the call
     * @param spender The address that will be allowed to spend the tokens (typically the target contract)
     * @param value The amount of tokens to approve for spending (in token's decimal units)
     * @param deadline The timestamp after which the permit signature is no longer valid
     * @param call ContractCall struct containing target, method, and encoded params with owner as first param
     * @param v The recovery identifier of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     * @return The return data from the external contract call
     */
    function permitWitnessCall(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        ContractCall calldata call,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable returns (bytes memory) {
        // Validate inputs before expensive signature operations
        if (call.target == address(0) || call.target == address(this)) {
            revert ERC20InvalidCallTarget();
        }

        // Validate method is non-empty
        if (bytes(call.method).length == 0) {
            revert ERC20InvalidCallData();
        }

        // CRITICAL: Validate owner is first parameter (32 bytes) in call.params
        if (call.params.length < 32 || bytes32(call.params[0:32]) != bytes32(uint256(uint160(owner)))) {
            revert ERC20InvalidCallData();
        }

        bytes32 witness = keccak256(
            abi.encode(WITNESS_CALL_TYPEHASH, call.target, keccak256(bytes(call.method)), keccak256(call.params))
        );

        // Use permitWitness to set the allowance
        permitWitness(owner, spender, value, deadline, witness, WITNESS_CALL_TYPESTRING, v, r, s);

        // Building the call data
        bytes memory callData = abi.encodePacked(bytes4(keccak256(bytes(call.method))), call.params);

        // Execute the external call
        (bool success, bytes memory returnData) = call.target.call{ value: msg.value }(callData);
        if (!success) {
            // Forward the revert reason if available
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            } else {
                revert ERC20CallFailed();
            }
        }

        return returnData;
    }

    /*//////////////////////////////////////////////////////////////
                   PERMIT WITNESS INTERNAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to validate witness-based permit signatures using default typeHash
     * @dev Validates EIP-712 signature for witness permit with PERMIT_WITNESS_TYPEHASH
     * @param owner The expected owner address that should have signed the permit
     * @param spender The spender address included in the signed message
     * @param value The token amount included in the signed message (in token's decimal units)
     * @param deadline The deadline timestamp included in the signed message
     * @param witness The witness data hash included in the signed message
     * @param v The recovery identifier of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function _validatePermitWitness(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes32 witness,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        _validatePermitWitnessSignature(owner, spender, value, deadline, witness, PERMIT_WITNESS_TYPEHASH, v, r, s);
    }

    /**
     * @notice Internal function to validate witness-based permit signatures with custom witness type
     * @dev Validates EIP-712 signature for witness permit with custom witnessTypeString
     * @param owner The expected owner address that should have signed the permit
     * @param spender The spender address included in the signed message
     * @param value The token amount included in the signed message (in token's decimal units)
     * @param deadline The deadline timestamp included in the signed message
     * @param witness The witness data hash included in the signed message
     * @param witnessTypeString Custom witness type string for EIP-712 type construction
     * @param v The recovery identifier of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function _validatePermitWitness(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes32 witness,
        string memory witnessTypeString,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        // Validate witnessTypeString is not empty and reasonable length
        if (bytes(witnessTypeString).length == 0 || bytes(witnessTypeString).length > 1024) {
            revert ERC20InvalidWitness();
        }

        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_WITNESS_TYPESTRING_STAB, witnessTypeString));
        _validatePermitWitnessSignature(owner, spender, value, deadline, witness, typeHash, v, r, s);
    }

    /**
     * @notice Core internal function to validate witness-based permit signatures with a given typeHash
     * @dev Validates EIP-712 signature, checking deadline, incrementing nonce, and recovering signer
     * @param owner The expected owner address that should have signed the permit
     * @param spender The spender address included in the signed message
     * @param value The token amount included in the signed message (in token's decimal units)
     * @param deadline The deadline timestamp included in the signed message
     * @param witness The witness data hash included in the signed message
     * @param typeHash The EIP-712 typeHash for the permit structure
     * @param v The recovery identifier of the signature (27 or 28)
     * @param r The first 32 bytes of the signature
     * @param s The second 32 bytes of the signature
     */
    function _validatePermitWitnessSignature(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes32 witness,
        bytes32 typeHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        if (deadline < block.timestamp) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 hash;
        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            uint256 nonce = nonces[owner]++;
            bytes32 structHash = keccak256(abi.encode(typeHash, owner, spender, value, nonce, deadline, witness));

            hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        }

        address recoveredAddress = ecrecover(hash, v, r, s);

        if (recoveredAddress == address(0) || recoveredAddress != owner) {
            revert ERC2612InvalidSigner(recoveredAddress, owner);
        }
    }

}



// ============================================================
// FILE: src/telecoin/OftStandard.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ILayerZeroEndpointV2 } from "../interfaces/layerzero/ILayerZeroEndpointV2.sol";
import { IOFT, OFTFeeDetail, OFTLimit, OFTReceipt, SendParam } from "../interfaces/layerzero/IOFT.sol";
import { IPrintrTeleport } from "../interfaces/printr/IPrintrTeleport.sol";

/**
 * @title OftStandard
 * @notice Abstract contract implementing LayerZero OFT standard for Telecoins
 * @dev Delegates to existing teleport infrastructure under the hood
 * @dev Expects inheriting contracts to provide _lzTeleport and quoteTeleportFee implementations from Telecoin
 */
abstract contract OftStandard is IOFT {

    /**
     * @notice Retrieves interfaceID and version of the OFT
     * @return interfaceId The interface ID (0x02e49c2c)
     * @return version The version (1)
     */
    function oftVersion() external pure returns (bytes4 interfaceId, uint64 version) {
        return (0x02e49c2c, 1);
    }

    /**
     * @notice Retrieves the address of the token associated with the OFT
     * @return token The address of the ERC20 token implementation (this contract)
     */
    function token() external view returns (address) {
        return address(this);
    }

    /**
     * @notice Indicates whether the OFT contract requires approval of the 'token()' to send
     * @return requiresApproval False, as the token itself implements the OFT interface
     */
    function approvalRequired() external pure returns (bool) {
        return false;
    }

    /**
     * @notice Retrieves the shared decimals of the OFT
     * @return sharedDecimals The shared decimals (9)
     */
    function sharedDecimals() external pure returns (uint8) {
        return 9;
    }

    /**
     * @notice Provides a quote for OFT-related operations
     * @param _sendParam The parameters for the send operation
     * @return limit The OFT limit information
     * @return oftFeeDetails The details of OFT fees
     * @return receipt The OFT receipt information
     */
    function quoteOFT(
        SendParam calldata _sendParam
    ) external returns (OFTLimit memory limit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory receipt) {
        // Convert SendParam to TeleportParams
        IPrintrTeleport.TeleportParams memory params = _sendParamToTeleportParams(_sendParam);

        // Get fee from PrintrTeleport
        (uint256 totalNativeFee,,, uint256 bridgeFee) = _quoteTeleportFee(params);

        // Calculate protocol fee
        uint256 protocolFee = totalNativeFee - bridgeFee;

        // Return limits (no hard limits on telecoin transfers)
        limit = OFTLimit({ minAmountLD: 0, maxAmountLD: type(uint256).max });

        // Return fee details array with protocol fee and bridge fee
        oftFeeDetails = new OFTFeeDetail[](2);
        oftFeeDetails[0] = OFTFeeDetail({ feeAmountLD: int256(protocolFee), description: "Protocol Fee" });
        oftFeeDetails[1] = OFTFeeDetail({ feeAmountLD: int256(bridgeFee), description: "Bridge Fee" });

        // Return receipt (1:1 transfer, no conversion)
        receipt = OFTReceipt({ amountSentLD: _sendParam.amountLD, amountReceivedLD: _sendParam.amountLD });
    }

    /**
     * @notice Provides a quote for the send() operation
     * @param _sendParam The parameters for the send() operation
     * @return fee The calculated LayerZero messaging fee
     */
    function quoteSend(
        SendParam calldata _sendParam,
        bool /* _payInLzToken */
    ) external returns (ILayerZeroEndpointV2.MessagingFee memory fee) {
        // Convert SendParam to TeleportParams
        IPrintrTeleport.TeleportParams memory params = _sendParamToTeleportParams(_sendParam);

        // Get fee from PrintrTeleport
        (uint256 totalNativeFee,,,) = _quoteTeleportFee(params);

        // Return MessagingFee (we don't support LZ token payments)
        fee = ILayerZeroEndpointV2.MessagingFee({ nativeFee: totalNativeFee, lzTokenFee: 0 });
    }

    /**
     * @notice Executes the send() operation
     * @param _sendParam The parameters for the send operation
     * @param _fee The fee information supplied by the caller
     * @return receipt The LayerZero messaging receipt
     * @return oftReceipt The OFT receipt information
     */
    function send(
        SendParam calldata _sendParam,
        ILayerZeroEndpointV2.MessagingFee calldata _fee,
        address /* _refundAddress */
    ) external payable returns (ILayerZeroEndpointV2.MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) {
        // Check slippage
        if (_sendParam.amountLD < _sendParam.minAmountLD) {
            revert SlippageExceeded(_sendParam.amountLD, _sendParam.minAmountLD);
        }

        // Convert SendParam to TeleportParams
        IPrintrTeleport.TeleportParams memory params = _sendParamToTeleportParams(_sendParam);

        // Call the LayerZero teleport function
        _lzTeleport(msg.sender, params);

        // Create a pseudo-GUID from sender and params
        bytes32 guid = keccak256(abi.encodePacked(msg.sender, _sendParam.dstEid, _sendParam.amountLD));

        // Emit OFTSent event
        emit OFTSent(guid, _sendParam.dstEid, msg.sender, _sendParam.amountLD, _sendParam.amountLD);

        // Return receipt (we don't have access to LayerZero's actual GUID and nonce, so we create synthetic values)
        receipt = ILayerZeroEndpointV2.MessagingReceipt({
            guid: guid,
            nonce: uint64(block.timestamp),
            fee: ILayerZeroEndpointV2.MessagingFee(_fee.nativeFee, 0)
        });

        // Return OFT receipt
        oftReceipt = OFTReceipt({ amountSentLD: _sendParam.amountLD, amountReceivedLD: _sendParam.amountLD });
    }

    function _quoteTeleportFee(
        IPrintrTeleport.TeleportParams memory params
    ) internal virtual returns (uint256 totalNativeFee, uint256 basePairFee, address basePair, uint256 bridgeFee);

    /**
     * @notice Internal abstract function for teleporting tokens
     * @dev Must be implemented by Telecoin to call its teleport() function
     * @param params The teleport parameters
     */
    function _lzTeleport(address from, IPrintrTeleport.TeleportParams memory params) internal virtual;

    /**
     * @notice Converts SendParam to TeleportParams
     * @param _sendParam The OFT SendParam struct
     * @return params The equivalent TeleportParams struct
     */
    function _sendParamToTeleportParams(
        SendParam calldata _sendParam
    ) internal pure returns (IPrintrTeleport.TeleportParams memory params) {
        // Map endpoint ID to chain name
        string memory destChain = _eidToString(_sendParam.dstEid);

        // Determine protocol based on extraOptions (default to LZ_FAST)
        IPrintrTeleport.TeleportProtocol protocol = _parseProtocolFromOptions(_sendParam.extraOptions);

        // Convert recipient from bytes32 to bytes
        bytes memory destAddress = abi.encodePacked(_sendParam.to);

        // Combine composeMsg and oftCmd into metadata if present
        bytes memory metadata;
        if (_sendParam.composeMsg.length > 0 || _sendParam.oftCmd.length > 0) {
            metadata = abi.encode(_sendParam.composeMsg, _sendParam.oftCmd);
        }

        params = IPrintrTeleport.TeleportParams({
            destChain: destChain,
            destAddress: destAddress,
            amount: _sendParam.amountLD,
            metadata: metadata,
            protocol: protocol
        });
    }

    /**
     * @notice Converts LayerZero endpoint ID to string representation
     * @param eid Endpoint ID
     * @return eidString The endpoint ID as a string (e.g., "30101")
     */
    function _eidToString(
        uint32 eid
    ) internal pure returns (string memory eidString) {
        // Convert uint32 to string
        if (eid == 0) {
            return "0";
        }

        uint32 temp = eid;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (eid != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint32(eid % 10)));
            eid /= 10;
        }

        return string(buffer);
    }

    /**
     * @notice Parses LayerZero extraOptions to determine protocol
     * @param extraOptions The extra options bytes (can encode security level)
     * @return protocol The teleport protocol to use
     */
    function _parseProtocolFromOptions(
        bytes calldata extraOptions
    ) internal pure returns (IPrintrTeleport.TeleportProtocol protocol) {
        // Default to LZ_FAST if no options provided
        if (extraOptions.length == 0) {
            return IPrintrTeleport.TeleportProtocol.LZ_FAST;
        }

        // Parse first byte as security level indicator if present
        // 1 = LZ_FAST, 2 = LZ_SECURE, 3 = LZ_SLOW
        uint8 securityLevel = uint8(extraOptions[0]);
        if (securityLevel == 1) {
            return IPrintrTeleport.TeleportProtocol.LZ_FAST;
        } else if (securityLevel == 2) {
            return IPrintrTeleport.TeleportProtocol.LZ_SECURE;
        } else if (securityLevel == 3) {
            return IPrintrTeleport.TeleportProtocol.LZ_SLOW;
        }

        // Default to LZ_FAST for any other value
        return IPrintrTeleport.TeleportProtocol.LZ_FAST;
    }

}



// ============================================================
// FILE: src/interfaces/layerzero/ILayerZeroEndpointV2.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title ILayerZeroEndpointV2
 * @notice Interface for LayerZero V2 endpoint contract
 * @dev Defines the core messaging functions for cross-chain communication
 */
interface ILayerZeroEndpointV2 {

    /**
     * @notice Struct containing messaging fee information
     * @param nativeFee Native fee amount to send
     * @param lzTokenFee LayerZero token fee amount
     */
    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    /**
     * @notice Struct containing messaging parameters
     * @param dstEid Destination endpoint ID
     * @param receiver Receiver address on destination chain (as bytes32)
     * @param message Message payload to send
     * @param options Execution options for the message
     * @param payInLzToken Whether to pay fees in LZ token
     */
    struct MessagingParams {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        bool payInLzToken;
    }

    /**
     * @notice Struct containing messaging receipt information
     * @param guid Globally unique identifier for the message
     * @param nonce Message nonce
     * @param fee Messaging fee paid
     */
    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    /**
     * @notice Send a message to another chain
     * @param params Messaging parameters
     * @param refundAddress Address to refund excess fees
     * @return receipt Message receipt containing guid and fee info
     */
    function send(
        MessagingParams calldata params,
        address refundAddress
    ) external payable returns (MessagingReceipt memory receipt);

    /**
     * @notice Quote the fee for sending a message
     * @param params Messaging parameters
     * @param sender The sender address
     * @return fee The messaging fee quote
     */
    function quote(MessagingParams calldata params, address sender) external view returns (MessagingFee memory fee);

    /**
     * @notice Struct for setting configuration parameters
     * @param eid Endpoint ID
     * @param configType Configuration type (1=Executor, 2=ULN)
     * @param config Encoded configuration data
     */
    struct SetConfigParam {
        uint32 eid;
        uint32 configType;
        bytes config;
    }

    /**
     * @notice Set configuration for an OApp
     * @param oapp The OApp address to configure
     * @param lib The library address (SendLib or ReceiveLib)
     * @param params Array of configuration parameters
     */
    function setConfig(address oapp, address lib, SetConfigParam[] calldata params) external;

    /**
     * @notice Set send library for an OApp
     * @param _oapp The OApp address
     * @param _eid Destination endpoint ID
     * @param _newLib Send library address
     */
    function setSendLibrary(address _oapp, uint32 _eid, address _newLib) external;

    /**
     * @notice Set receive library for an OApp
     * @param _oapp The OApp address
     * @param _eid Source endpoint ID
     * @param _newLib Receive library address
     * @param _gracePeriod Grace period for library switch
     */
    function setReceiveLibrary(address _oapp, uint32 _eid, address _newLib, uint256 _gracePeriod) external;

    /**
     * @notice Set delegate for message handling
     * @param delegate Address of the delegate
     */
    function setDelegate(
        address delegate
    ) external;

    /**
     * @notice Get the send library for an OApp and destination
     * @param _sender The sender address
     * @param _eid Destination endpoint ID
     * @return lib The send library address
     */
    function getSendLibrary(address _sender, uint32 _eid) external view returns (address lib);

    /**
     * @notice Get the receive library for an OApp and source
     * @param _receiver The receiver address
     * @param _eid Source endpoint ID
     * @return lib The receive library address
     */
    function getReceiveLibrary(address _receiver, uint32 _eid) external view returns (address lib, bool);

    /**
     * @notice Get the default send library for an endpoint
     * @param _eid Destination endpoint ID
     * @return The default send library address
     */
    function defaultSendLibrary(
        uint32 _eid
    ) external view returns (address);

    /**
     * @notice Get the default receive library for an endpoint
     * @param _eid Source endpoint ID
     * @return The default receive library address
     */
    function defaultReceiveLibrary(
        uint32 _eid
    ) external view returns (address);

}



// ============================================================
// FILE: src/interfaces/ITreasury.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title ITreasury
 * @notice Interface for managing protocol fee collection and token withdrawals
 * @dev Handles LP fee collection and controlled withdrawals of tokens/native currency
 */
interface ITreasury {

    /**
     * @notice Thrown when an unauthorized address attempts to access treasury functions
     */
    error WrongAccess();

    /**
     * @notice Thrown when a withdrawal of native currency fails
     */
    error FailedWithdrawal();

    /**
     * @notice Thrown when a zero address is provided where a valid address is required
     */
    error ZeroAddress();

    /**
     * @notice Emitted when fees are collected from a liquidity position
     * @param token0 Address of the first token in the pair
     * @param token1 Address of the second token in the pair
     * @param recipient Address receiving the collected fees
     * @param amount0 Amount of token0 collected
     * @param amount1 Amount of token1 collected
     * @param lockId ID of the locked liquidity position
     */
    event CollectedLiquidityFees(
        address indexed token0,
        address indexed token1,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 lockId
    );

    /**
     * @notice Collects accumulated fees from a locked liquidity position by delegating to the liquidity module
     * @dev Only callable by authorized addresses. Delegates to the appropriate liquidity module
     *      which handles locker-specific logic (GoPlus, generic, etc.) and token ordering.
     * @param liquidityModule Address of the liquidity module that manages this position's DEX
     * @param lockId ID of the locked liquidity position
     * @param token Address of the first token in the pair
     * @param basePair Address of the second token in the pair (base currency)
     * @param recipient Address to receive the collected fees
     * @custom:throws WrongAccess if caller is not authorized
     */
    function collectLiquidityFees(
        address liquidityModule,
        uint256 lockId,
        address token,
        address basePair,
        address recipient
    ) external;

    /**
     * @notice Withdraws tokens or native currency from the treasury
     * @dev Only callable by authorized addresses
     * @param token Address of token to withdraw (address(0) for native currency)
     * @param recipient Address to receive the withdrawal
     * @param amount Amount to withdraw
     * @custom:throws WrongAccess if caller is not authorized
     * @custom:throws FailedWithdrawal if native currency transfer fails
     */
    function withdraw(address token, address recipient, uint256 amount) external;

    /**
     * @notice Handles receipt of ERC721 tokens (LP position NFTs)
     * @dev Required for compatibility with ERC721 token transfers
     * @return bytes4 Function selector to indicate successful receipt
     */
    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256, /* tokenId */
        bytes calldata /* data */
    ) external pure returns (bytes4);

}
