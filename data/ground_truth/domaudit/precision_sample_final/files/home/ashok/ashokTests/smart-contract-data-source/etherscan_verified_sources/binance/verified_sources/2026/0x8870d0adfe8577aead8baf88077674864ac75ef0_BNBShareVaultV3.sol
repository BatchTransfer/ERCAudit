// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x8870d0adfe8577aead8baf88077674864ac75ef0
// Contract Name: BNBShareVaultV3
// File: contracts/interfaces/VaultBase.sol


pragma solidity 0.8.19;

/// @title VaultBase
/// @notice Abstract base contract for all vault implementations (from Flap spec)
/// @author The Flap Team
abstract contract VaultBase {
    /// @notice Error thrown when the current chain is not supported
    error UnsupportedChain(uint256 chainId);

    /// @notice Get the Portal address for the current chain
    function _getPortal() internal view returns (address portal) {
        uint256 chainId = block.chainid;
        if (chainId == 56) {
            return 0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0; // BNB Chain
        } else if (chainId == 97) {
            return 0x5bEacaF7ABCbB3aB280e80D007FD31fcE26510e9; // BNB Testnet
        }
        revert UnsupportedChain(chainId);
    }

    /// @notice Get the Guardian address for the current chain
    function _getGuardian() internal view returns (address guardian) {
        uint256 chainId = block.chainid;
        if (chainId == 56) {
            return 0x9e27098dcD8844bcc6287a557E0b4D09C86B8a4b; // BNB Chain
        } else if (chainId == 97) {
            return 0x76Fa8C526f8Bc27ba6958B76DeEf92a0dbE46950; // BNB Testnet
        }
        revert UnsupportedChain(chainId);
    }

    /// @notice Returns a description of the vault
    function description() public view virtual returns (string memory);
}

// File: contracts/BNBShareVaultV3.sol


pragma solidity 0.8.19;


/// @title IVaultFactoryV3
/// @notice Minimal interface to read relayer and snowballer from factory
interface IVaultFactoryV3 {
    function relayer() external view returns (address);
    function snowballer() external view returns (address);
}

/// @notice Describes a single field for UI generation (Flap VaultFactoryBaseV2 spec)
struct FieldDescriptor {
    string name;        // Machine-readable name (e.g. "recipient")
    string fieldType;   // Solidity ABI type string (e.g. "address", "string", "time")
    string description; // Human-readable explanation
    uint8 decimals;     // Decimal precision hint for numeric fields
}

/// @notice An ERC-20 approve action the UI must execute before calling a write method
struct ApproveAction {
    string tokenType;       // "taxToken" or "lpToken"
    string amountFieldName; // Name of the input field whose value is the approve amount
}

/// @notice Describes a single view or write method the UI should render
struct VaultMethodSchema {
    string name;                   // Solidity method name
    string description;            // Human-readable explanation
    FieldDescriptor[] inputs;      // Ordered input parameters
    FieldDescriptor[] outputs;     // Ordered return values
    ApproveAction[] approvals;     // ERC-20 approvals required before a write
    bool isInputArray;             // true = input is tuple[]
    bool isOutputArray;            // true = output is tuple[]
    bool isWriteMethod;            // true = state-changing, false = view
}

/// @notice Top-level schema describing the vault's entire UI surface
struct VaultUISchema {
    string vaultType;              // e.g. "BNBShareVaultV3"
    string description;            // Overall explanation of the vault
    VaultMethodSchema[] methods;   // All methods the UI should render (ordered)
}

/// @title IPancakeRouter
/// @notice Minimal interface for PancakeSwap V2 Router
interface IPancakeRouter {
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
    
    function WETH() external pure returns (address);
}

/// @title ECDSA
/// @notice Minimal ECDSA library for signature recovery
library ECDSA {
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) return address(0);
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);
        
        return ecrecover(hash, v, r, s);
    }
}

/// @title BNBShareVaultV3
/// @notice Single-recipient vault with gasless claims, fixed math, and balance-based snowball
/// @author BNBShare Team
/// @dev V3 vault improvements:
///      - Fixed math: tracks platform fees exactly (no rounding bug)
///      - Gasless claims: claimFor() with EIP-712 signatures
///      - Snowball: uses actual balance instead of tracked amount
///      - Emergency withdraw: guardian can rescue stuck funds
contract BNBShareVaultV3 is VaultBase {
    using ECDSA for bytes32;

    /* ========== CONSTANTS ========== */

    /// @notice Platform fee in basis points (25% = 2500)
    uint16 public constant PLATFORM_FEE_BPS = 2500;

    /// @notice Total BPS
    uint16 public constant TOTAL_BPS = 10000;

    /// @notice Grace period before snowball can start (7 days)
    uint256 public constant GRACE_PERIOD = 7 days;

    /// @notice Minimum interval between snowball calls (24 hours)
    uint256 public constant SNOWBALL_INTERVAL = 24 hours;

    /// @notice $SHARE token address for buyback & burn
    address public constant SHARE_TOKEN = 0x1646980A0e0EBeA85DB014807205aa4d9bF87777;

    /// @notice PancakeSwap V2 Router
    address public constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    /// @notice Dead address for burning tokens
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice EIP-712 domain separator components
    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    
    /// @notice Claim typehash for EIP-712 signature
    bytes32 public constant CLAIM_TYPEHASH = keccak256(
        "Claim(address recipient,address vault,uint256 deadline)"
    );

    /* ========== IMMUTABLES ========== */

    /// @notice The factory that created this vault
    address public immutable factory;

    /// @notice The platform wallet that receives the 25% fee
    address public immutable platformWallet;

    /// @notice The tax token this vault is associated with
    address public immutable taxToken;

    /// @notice The single recipient of the 75% share
    address public immutable recipient;

    /// @notice Timestamp when the vault was created
    uint256 public immutable createdAt;

    /// @notice Cached domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    /* ========== STATE ========== */

    /// @notice Social handle of the recipient (e.g., "@alice")
    string public recipientHandle;

    /// @notice Platform type (e.g., "twitter", "github", "tiktok", "twitch")
    string public handleType;

    /// @notice Whether the recipient has claimed (switches to auto-send mode)
    bool public isVerified;

    /// @notice Accumulated BNB pending for recipient (only used before verified)
    uint256 public pendingForRecipient;

    /// @notice Total BNB earned by recipient (for display)
    uint256 public totalEarned;

    /// @notice Total BNB received by this vault (for display)
    uint256 public totalReceived;

    /// @notice Last time snowball was called
    uint256 public lastSnowballTime;

    /// @notice Total BNB burned via snowball
    uint256 public totalSnowballed;

    /// @notice Platform fees accumulated (V3: tracked exactly, not recalculated)
    uint256 public platformPendingAmount;

    /// @notice Amount already released to the platform wallet
    uint256 public platformReleased;

    /* ========== EVENTS ========== */

    event BNBReceived(uint256 amount);
    event PlatformFeeSent(uint256 amount);
    event RecipientFeeSent(uint256 amount);
    event FundsAccumulated(uint256 amount);
    event Claimed(address indexed recipient, uint256 amount);
    event ClaimedFor(address indexed recipient, address indexed relayer, uint256 amount);
    event Verified(address indexed recipient);
    event Snowballed(uint256 bnbAmount, uint256 sharesBurned);
    event TransferFailed(address indexed to, uint256 amount);
    event DispatchFailed(address indexed to, uint256 amount);
    event EmergencyWithdraw(address indexed recipient, uint256 amount);

    /* ========== ERRORS ========== */

    error ZeroAddress();
    error NotRecipient();
    error AlreadyVerified();
    error NothingToClaim();
    error GracePeriodNotOver();
    error SnowballTooSoon();
    error NothingToSnowball();
    error AlreadyVerifiedNoSnowball();
    error TransferFailedError(address to, uint256 amount);
    error InvalidSignature();
    error SignatureExpired();
    error OnlyGuardian();
    error OnlyRelayer();
    error OnlySnowballerOrGuardian();

    /* ========== CONSTRUCTOR ========== */

    /// @param _factory The factory that created this vault
    /// @param _platformWallet The wallet that receives the 25% platform fee
    /// @param _taxToken The tax token address this vault is for
    /// @param _recipient The single recipient of the 75% share
    /// @param _recipientHandle Social handle of the recipient
    /// @param _handleType Platform type (twitter, github, etc.)
    constructor(
        address _factory,
        address _platformWallet,
        address _taxToken,
        address _recipient,
        string memory _recipientHandle,
        string memory _handleType
    ) {
        if (_factory == address(0)) revert ZeroAddress();
        if (_platformWallet == address(0)) revert ZeroAddress();
        if (_taxToken == address(0)) revert ZeroAddress();
        if (_recipient == address(0)) revert ZeroAddress();

        factory = _factory;
        platformWallet = _platformWallet;
        taxToken = _taxToken;
        recipient = _recipient;
        recipientHandle = _recipientHandle;
        handleType = _handleType;
        createdAt = block.timestamp;

        // Cache domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256("BNBShareVault"),
                keccak256("3"),
                block.chainid,
                address(this)
            )
        );
    }

    /* ========== RECEIVE ========== */

    /// @notice Accepts BNB from the tax token
    /// @dev 25% goes to platform (tracked exactly), 75% to recipient
    receive() external payable {
        totalReceived += msg.value;
        emit BNBReceived(msg.value);

        // Calculate shares - V3: track platform share exactly
        uint256 platformShare = (msg.value * PLATFORM_FEE_BPS) / TOTAL_BPS;
        uint256 recipientShare = msg.value - platformShare;
        
        totalEarned += recipientShare;
        platformPendingAmount += platformShare; // V3: Track exact amount

        // Handle recipient share based on state
        if (isVerified) {
            // VERIFIED: Auto-send to recipient
            (bool recipientSuccess, ) = payable(recipient).call{value: recipientShare}("");
            if (recipientSuccess) {
                emit RecipientFeeSent(recipientShare);
            } else {
                pendingForRecipient += recipientShare;
                emit TransferFailed(recipient, recipientShare);
            }
        } else {
            // ACCUMULATING: Store in vault until claimed
            pendingForRecipient += recipientShare;
            emit FundsAccumulated(recipientShare);
        }

        // Try to dispatch platform share (with gas limit, never reverts)
        try this.dispatchPlatform{gas: 50000}() {
            // Success
        } catch {
            // Fail silently — funds remain for claimPlatform()
        }
    }

    /* ========== DISPATCH ========== */

    /// @notice Distribute pending BNB to platform wallet
    /// @dev V3: Uses tracked amount instead of recalculating
    function dispatchPlatform() external {
        uint256 toSend = platformPendingAmount;
        if (toSend == 0) return;

        platformPendingAmount = 0;
        platformReleased += toSend;
        
        (bool success, ) = payable(platformWallet).call{value: toSend}("");
        if (!success) {
            platformPendingAmount = toSend;
            platformReleased -= toSend;
            emit DispatchFailed(platformWallet, toSend);
        } else {
            emit PlatformFeeSent(toSend);
        }
    }

    /* ========== CLAIM ========== */

    /// @notice Claim accumulated BNB and switch to VERIFIED state
    /// @dev Only callable by the recipient. After this, fees auto-send.
    function claim() external {
        if (msg.sender != recipient) revert NotRecipient();
        _executeClaim();
    }

    /// @notice Gasless claim - only factory relayer can call with valid signature from recipient
    /// @dev Allows relayer to pay gas on behalf of users
    /// @param deadline Timestamp after which signature is invalid
    /// @param signature EIP-712 signature from recipient
    function claimFor(uint256 deadline, bytes calldata signature) external {
        // Only the factory's relayer can call this
        address authorizedRelayer = IVaultFactoryV3(factory).relayer();
        if (msg.sender != authorizedRelayer) revert OnlyRelayer();
        
        if (block.timestamp > deadline) revert SignatureExpired();
        
        // Build EIP-712 digest
        bytes32 structHash = keccak256(
            abi.encode(CLAIM_TYPEHASH, recipient, address(this), deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        
        // Recover signer
        address signer = digest.recover(signature);
        if (signer != recipient) revert InvalidSignature();
        
        // Execute claim
        _executeClaim();
        
        emit ClaimedFor(recipient, msg.sender, pendingForRecipient);
    }

    /// @notice Internal claim logic shared by claim() and claimFor()
    function _executeClaim() internal {
        if (isVerified) revert AlreadyVerified();

        // V3: Use actual balance to avoid rounding issues
        uint256 recipientBalance = address(this).balance - platformPendingAmount;
        if (recipientBalance == 0) revert NothingToClaim();

        // Clear pending and set verified
        pendingForRecipient = 0;
        isVerified = true;

        // Send accumulated BNB to recipient
        (bool success, ) = payable(recipient).call{value: recipientBalance}("");
        if (!success) {
            // Revert on failure - user should retry
            pendingForRecipient = recipientBalance;
            isVerified = false;
            revert TransferFailedError(recipient, recipientBalance);
        }

        emit Claimed(recipient, recipientBalance);
        emit Verified(recipient);
    }

    /// @notice Allow the platform to claim its pending BNB
    /// @dev Only platform wallet or guardian can call
    function claimPlatform() external {
        address guardian = _getGuardian();
        require(msg.sender == platformWallet || msg.sender == guardian, "Not authorized");

        uint256 toSend = platformPendingAmount;
        if (toSend == 0) revert NothingToClaim();

        platformPendingAmount = 0;
        platformReleased += toSend;

        (bool success, ) = payable(platformWallet).call{value: toSend}("");
        if (!success) {
            platformPendingAmount = toSend;
            platformReleased -= toSend;
            revert TransferFailedError(platformWallet, toSend);
        }

        emit PlatformFeeSent(toSend);
    }

    /* ========== SNOWBALL ========== */

    /// @notice Buy back $SHARE tokens and burn them using unclaimed BNB
    /// @dev V3: Uses actual balance instead of tracked amount. Only snowballer or guardian can call.
    function snowball() external {
        // Access control: only snowballer or guardian can trigger snowball
        address authorizedSnowballer = IVaultFactoryV3(factory).snowballer();
        address guardian = _getGuardian();
        if (msg.sender != authorizedSnowballer && msg.sender != guardian) {
            revert OnlySnowballerOrGuardian();
        }

        // Can't snowball if user already claimed
        if (isVerified) revert AlreadyVerifiedNoSnowball();

        // Must be past grace period
        if (block.timestamp < createdAt + GRACE_PERIOD) revert GracePeriodNotOver();

        // Must wait 24h between snowball calls
        if (lastSnowballTime > 0 && block.timestamp < lastSnowballTime + SNOWBALL_INTERVAL) {
            revert SnowballTooSoon();
        }

        // V3: Use actual balance minus platform pending (avoids rounding bug)
        uint256 amountBNB = address(this).balance - platformPendingAmount;
        if (amountBNB == 0) revert NothingToSnowball();

        // Update state before external calls
        pendingForRecipient = 0;
        lastSnowballTime = block.timestamp;
        totalSnowballed += amountBNB;

        // Swap BNB → SHARE on PancakeSwap and send to dead address
        IPancakeRouter router = IPancakeRouter(PANCAKE_ROUTER);
        address[] memory path = new address[](2);
        path[0] = router.WETH(); // WBNB
        path[1] = SHARE_TOKEN;

        // Use supportingFeeOnTransferTokens for tax tokens
        try router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountBNB}(
            0, // Accept any amount of SHARE (no slippage protection needed for burn)
            path,
            DEAD_ADDRESS, // Send directly to burn address
            block.timestamp
        ) {
            emit Snowballed(amountBNB, 0); // Can't get exact output with this function
        } catch {
            // If swap fails, restore pending balance
            pendingForRecipient = amountBNB;
            lastSnowballTime = 0;
            totalSnowballed -= amountBNB;
            revert("Snowball swap failed");
        }
    }

    /* ========== EMERGENCY ========== */

    /// @notice Emergency withdraw - guardian can rescue stuck funds to recipient
    /// @dev Only callable by guardian, sends all recipient funds to recipient
    function emergencyWithdraw() external {
        if (msg.sender != _getGuardian()) revert OnlyGuardian();
        
        uint256 recipientBalance = address(this).balance - platformPendingAmount;
        if (recipientBalance == 0) revert NothingToClaim();
        
        pendingForRecipient = 0;
        
        (bool success, ) = payable(recipient).call{value: recipientBalance}("");
        if (!success) revert TransferFailedError(recipient, recipientBalance);
        
        emit EmergencyWithdraw(recipient, recipientBalance);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Get platform pending amount (V3: returns tracked amount)
    function platformPending() public view returns (uint256) {
        return platformPendingAmount;
    }

    /// @notice Check if snowball can be called
    function canSnowball() external view returns (bool) {
        if (isVerified) return false;
        if (block.timestamp < createdAt + GRACE_PERIOD) return false;
        if (lastSnowballTime > 0 && block.timestamp < lastSnowballTime + SNOWBALL_INTERVAL) return false;
        uint256 recipientBalance = address(this).balance - platformPendingAmount;
        if (recipientBalance == 0) return false;
        return true;
    }

    /// @notice Get time remaining until snowball is available
    function timeUntilSnowball() external view returns (uint256) {
        if (isVerified) return type(uint256).max; // Never

        uint256 graceEnd = createdAt + GRACE_PERIOD;
        if (block.timestamp < graceEnd) {
            return graceEnd - block.timestamp;
        }

        if (lastSnowballTime > 0) {
            uint256 nextSnowball = lastSnowballTime + SNOWBALL_INTERVAL;
            if (block.timestamp < nextSnowball) {
                return nextSnowball - block.timestamp;
            }
        }

        return 0; // Available now
    }

    /// @notice Get the Unix timestamp when snowball becomes available
    /// @dev Returns absolute timestamp for Flap UI "time" type countdown display
    /// @return timestamp Unix timestamp when grace period ends, 0 after grace period (hides timer)
    function nextSnowballTimestamp() external view returns (uint256) {
        if (isVerified) return 0; // Claimed - no countdown needed

        uint256 graceEnd = createdAt + GRACE_PERIOD;
        if (block.timestamp < graceEnd) {
            return graceEnd; // Returns when 7-day grace period ends
        }

        return 0; // Grace period over, snowball mode active - hide timer
    }

    /// @notice Get recipient info for display
    function getRecipientInfo() external view returns (
        address recipientAddr,
        string memory handle,
        string memory platform,
        bool verified,
        uint256 pending,
        uint256 earned
    ) {
        return (
            recipient,
            recipientHandle,
            handleType,
            isVerified,
            pendingForRecipient,
            totalEarned
        );
    }

    /// @notice Returns the UI schema for Flap to render vault methods
    /// @dev Implements Flap vaultUISchema spec for automatic UI generation
    /// @return schema The complete UI schema for this vault
    function vaultUISchema() public pure returns (VaultUISchema memory schema) {
        schema.vaultType = "BNBShareVaultV3";
        schema.description = "Claim your fees within 7 days on bnbshare.fun/claim. If unclaimed, it buys & burns $SHARE. You can still claim later - this stops snowball mode and future fees go directly to you.";
        schema.methods = new VaultMethodSchema[](2);

        // Method 0: getRecipientInfo (view)
        schema.methods[0].name = "getRecipientInfo";
        schema.methods[0].description = "Recipient details and earnings.";
        schema.methods[0].inputs = new FieldDescriptor[](0);
        schema.methods[0].outputs = new FieldDescriptor[](6);
        schema.methods[0].outputs[0] = FieldDescriptor("recipientAddr", "address", "Recipient wallet", 0);
        schema.methods[0].outputs[1] = FieldDescriptor("handle", "string", "Social handle", 0);
        schema.methods[0].outputs[2] = FieldDescriptor("platform", "string", "Platform", 0);
        schema.methods[0].outputs[3] = FieldDescriptor("verified", "bool", "Claimed", 0);
        schema.methods[0].outputs[4] = FieldDescriptor("pending", "uint256", "Pending BNB", 18);
        schema.methods[0].outputs[5] = FieldDescriptor("earned", "uint256", "Total earned", 18);
        schema.methods[0].approvals = new ApproveAction[](0);
        schema.methods[0].isInputArray = false;
        schema.methods[0].isOutputArray = false;
        schema.methods[0].isWriteMethod = false;

        // Method 1: nextSnowballTimestamp (view) - uses "time" for countdown
        schema.methods[1].name = "nextSnowballTimestamp";
        schema.methods[1].description = "Time until snowball mode activates.";
        schema.methods[1].inputs = new FieldDescriptor[](0);
        schema.methods[1].outputs = new FieldDescriptor[](1);
        schema.methods[1].outputs[0] = FieldDescriptor("timestamp", "time", "Countdown to snowball", 0);
        schema.methods[1].approvals = new ApproveAction[](0);
        schema.methods[1].isInputArray = false;
        schema.methods[1].isOutputArray = false;
        schema.methods[1].isWriteMethod = false;
    }

    /// @notice Returns a dynamic description of the vault's state (required by VaultBase)
    function description() public view override returns (string memory) {
        string memory state = isVerified ? "VERIFIED" : "ACCUMULATING";
        uint256 pendingBNB = address(this).balance - platformPendingAmount;
        uint256 bnbWhole = pendingBNB / 1e18;
        uint256 bnbDecimals = (pendingBNB % 1e18) / 1e14;

        return string(
            abi.encodePacked(
                "BNBShare V3 Vault - ", state, ". ",
                "Recipient: ", recipientHandle, " (", handleType, "). ",
                "Pending: ", _toString(bnbWhole), ".", _padZeros(_toString(bnbDecimals), 4), " BNB. ",
                "Total earned: ", _toString(totalEarned / 1e18), " BNB."
            )
        );
    }

    /* ========== INTERNAL ========== */

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _padZeros(string memory str, uint256 targetLength) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= targetLength) return str;
        bytes memory padded = new bytes(targetLength);
        uint256 paddingCount = targetLength - strBytes.length;
        for (uint256 i = 0; i < paddingCount; i++) padded[i] = "0";
        for (uint256 i = 0; i < strBytes.length; i++) padded[paddingCount + i] = strBytes[i];
        return string(padded);
    }
}