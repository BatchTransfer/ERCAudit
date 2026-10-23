// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x6626a60c28a796fea0ea7324a1bac058fc4c7828
// Contract Name: PermitFacet



// ============================================================
// FILE: @openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/extensions/IERC20Permit.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[ERC-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC-20 allowance (see {IERC20-allowance}) by
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
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

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



// ============================================================
// FILE: contracts/facets/PermitFacet.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import {TermMulticallProtection} from "./base/TermMulticallProtection.sol";
import {ITermController} from "../interfaces/ITermController.sol";

import {LibTermStorage, TermStorage} from "../libraries/LibTermStorage.sol";


import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @author TermLabs
/// @title PermitFacet
/// @notice Provides EIP-2612 permit functionality for gasless token approvals
/// @dev Enables users to approve token spending via signatures instead of transactions
contract PermitFacet is TermMulticallProtection {

    // ========================================================================
    // = Errors  ==============================================================
    // ========================================================================

    /// @notice Thrown when deadline has expired
    error Expired();

    /// @notice Thrown when the owner address is invalid
    error InvalidOwner();

    /// @notice Thrown when the spender address is invalid
    error InvalidSpender();

    /// @notice Thrown when the asset address is invalid
    error InvalidAsset();

    /// @notice Thrown when signature components are invalid
    error InvalidSignature();

    // ========================================================================
    // = APIs =================================================================
    // ========================================================================

    /// @notice Calls the permit function on an ERC20 token that supports EIP-2612 permits
    /// @param asset The address of the ERC20 token
    /// @param amount The amount of tokens to approve
    /// @param spender The address which will be approved to spend the tokens
    /// @param deadline The timestamp after which the permit is no longer valid
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @param skipRevert If true, the function will not revert on failure
    function permit(
        address asset,
        uint256 amount,
        address spender,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bool skipRevert
    ) external onlyMulticallInitiator {
        if (deadline <= block.timestamp) revert Expired();
        if (asset == address(0)) revert InvalidAsset();
        if (spender == address(0)) revert InvalidSpender();
        address owner = initiator();
        if (owner == address(0)) revert InvalidOwner();
        if (r == bytes32(0) || s == bytes32(0)) revert InvalidSignature();
        if (v != 27 && v != 28) revert InvalidSignature();
        try IERC20Permit(asset).permit(owner, spender, amount, deadline, v, r, s) {}
        catch (bytes memory returnData) {
            if (!skipRevert) _revert(returnData);
        }
    }

    /// @notice Calls the permit function on an ERC20 token that supports EIP-2612 permits, approving TermDiamond to spend tokens on behalf of the initiator
    /// @param asset The address of the ERC20 token
    /// @param amount The amount of tokens to approve
    /// @param owner The address which owns the tokens
    /// @param deadline The timestamp after which the permit is no longer valid
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @param skipRevert If true, the function will not revert on failure
    function permitDiamond(
        address asset,
        uint256 amount,
        address owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bool skipRevert
    ) external onlyMulticallInitiator {
        if (deadline <= block.timestamp) revert Expired();
        if (asset == address(0)) revert InvalidAsset();
        if (owner == address(0)) revert InvalidOwner();
        if (r == bytes32(0) || s == bytes32(0)) revert InvalidSignature();
        if (v != 27 && v != 28) revert InvalidSignature();
        try IERC20Permit(asset).permit(owner, address(this), amount, deadline, v, r, s) {}
        catch (bytes memory returnData) {
            if (!skipRevert) _revert(returnData);
        }
    }

    /// @notice Calls the permit function on an ERC20 token that supports EIP-2612 permits, approving a term contract to spend tokens on behalf of the owner
    /// @param asset The address of the ERC20 token
    /// @param amount The amount of tokens to approve
    /// @param owner The address which owns the tokens
    /// @param termContractAddress The address of the term contract to approve as spender
    /// @param deadline The timestamp after which the permit is no longer valid
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @param skipRevert If true, the function will not revert on failure
    function permitTermContract(
        address asset,
        uint256 amount,
        address owner,
        address termContractAddress,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bool skipRevert
    ) external onlyMulticallInitiator {
        if (deadline <= block.timestamp) revert Expired();
        if (asset == address(0)) revert InvalidAsset();
        if (owner == address(0)) revert InvalidOwner();
        if (r == bytes32(0) || s == bytes32(0)) revert InvalidSignature();
        if (v != 27 && v != 28) revert InvalidSignature();
        TermStorage storage ts = LibTermStorage.termStorage();
        bool isValidTermContract;
        for (uint256 i = 0; i < ts.approvedTermControllerList.length; ++i) {
            ITermController termController = ITermController(ts.approvedTermControllerList[i]);
            if (termController.isTermDeployed(termContractAddress) || termController.isFactoryDeployed(termContractAddress)) {
                isValidTermContract = true;
                break;
            }
        }
        if (!isValidTermContract) revert InvalidSpender();
        try IERC20Permit(asset).permit(owner, termContractAddress, amount, deadline, v, r, s) {}
        catch (bytes memory returnData) {
            if (!skipRevert) _revert(returnData);
        }
    }
}



// ============================================================
// FILE: contracts/facets/base/TermMulticallProtection.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import {LibTermStorage, TermStorage} from "../../libraries/LibTermStorage.sol";

/// @title Term Multicall Protection Base Contract
/// @notice Provides protection mechanisms for multicall operations in Term Finance protocol
/// @dev Abstract base contract that prevents unauthorized multicall execution and reentrancy
abstract contract TermMulticallProtection {
    
    address constant UNSET_MULTICALL_INITIATOR = address(0);
    
    modifier onlyMulticallInitiator() {
        LibTermStorage.requireMulticallInitiator();
        _;
    }

    modifier initiateMulticallProtection() {
        TermStorage storage ts = LibTermStorage.termStorage();
        require(ts.multicallInitiator == UNSET_MULTICALL_INITIATOR, "Multicall already initiated");
        ts.multicallInitiator = msg.sender;
        _;
        ts.multicallInitiator = UNSET_MULTICALL_INITIATOR;
    }

    function initiator() internal view returns (address) {
        TermStorage storage ts = LibTermStorage.termStorage();
        return ts.multicallInitiator;
    }

    /// @dev Bubbles up the revert reason / custom error encoded in `returnData`.
    /// @dev Assumes `returnData` is the return data of any kind of failing CALL to a contract.
    function _revert(bytes memory returnData) internal pure {
        uint256 length = returnData.length;
        require(length > 0, "call reverted");

        assembly ("memory-safe") {
            revert(add(32, returnData), length)
        }
    }
}


// ============================================================
// FILE: contracts/interfaces/ITermAuctionBidLockerEvents.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @notice ITermAuctionBidLockerEvents is an interface that defines all events emitted by the Term Auction Bid Locker.
interface ITermAuctionBidLockerEvents {
    event TermAuctionBidLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionBidLocker,
        uint256 auctionStartTime,
        uint256 revealTime,
        uint256 maxBidPrice,
        uint256 minimumTenderAmount,
        uint256 dayCountFractionMantissa
    );

    event BidLocked(
        bytes32 termAuctionId,
        bytes32 id,
        address bidder,
        bytes32 bidPrice,
        uint256 amount,
        address token,
        address[] collateralTokens,
        uint256[] collateralAmounts,
        bool isRollover,
        address rolloverPairOffTermRepoServicer,
        address referralAddress
    );

    event BidRevealed(bytes32 termAuctionId, bytes32 id, uint256 bidPrice);

    event BidUnlocked(bytes32 termAuctionId, bytes32 id);

    event BidInShortfall(bytes32 termAuctionId, bytes32 id);

    event BidLockingPaused(bytes32 termAuctionId, bytes32 termRepoId);

    event BidLockingUnpaused(bytes32 termAuctionId, bytes32 termRepoId);

    event BidUnlockingPaused(bytes32 termAuctionId, bytes32 termRepoId);

    event BidUnlockingUnpaused(bytes32 termAuctionId, bytes32 termRepoId);
}



// ============================================================
// FILE: contracts/interfaces/ITermAuctionEvents.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @title ITermAuctionEvents defines all events emitted by the TermAuctionContract.
interface ITermAuctionEvents {
    /// Event emitted when a new auction is initialized
    /// @param termRepoId The term ID
    /// @param termAuctionId The term auction Id
    /// @param termAuction auction contract address
    /// @param auctionEndTime The auction end time
    /// @param version The version tag of the smart contract deployed
    event TermAuctionInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuction,
        uint256 auctionEndTime,
        address deployerWallet,
        string version
    );

    /// Event emitted when a bid is assigned
    /// @param termAuctionId The auction ID
    /// @param id The bid ID
    /// @param amount The amount assigned
    event BidAssigned(bytes32 termAuctionId, bytes32 id, uint256 amount);

    /// Event emitted when an offer is assigned
    /// @param termAuctionId The term ID
    /// @param id The offer ID
    /// @param amount The amount assigned
    event OfferAssigned(bytes32 termAuctionId, bytes32 id, uint256 amount);

    /// Event emitted when an auction is completed
    /// @param termAuctionId The ID of the auction
    /// @param timestamp The timestamp of the auction completion
    /// @param block The block of the auction completion
    /// @param totalAssignedBids The total amount of bids assigned
    /// @param totalAssignedOffers The total amount of offers assigned
    /// @param clearingPrice The clearing price of the auction
    event AuctionCompleted(
        bytes32 termAuctionId,
        uint256 timestamp,
        uint256 block,
        uint256 totalAssignedBids,
        uint256 totalAssignedOffers,
        uint256 clearingPrice
    );

    /// Event emitted when an auction is cancelled.
    /// @param termAuctionId The ID of the auction.
    /// @param nonViableAuction Auction not viable due to bid and offer prices not intersecting
    /// @param auctionCancelledforWithdrawal Auction has been cancelled for manual fund withdrawal
    event AuctionCancelled(
        bytes32 termAuctionId,
        bool nonViableAuction,
        bool auctionCancelledforWithdrawal
    );

    /// Event emitted when an auction is paused.
    /// @param termAuctionId The ID of the auction.
    /// @param termRepoId The ID of the repo.
    event CompleteAuctionPaused(bytes32 termAuctionId, bytes32 termRepoId);

    /// Event emitted when an auction is unpaused.
    /// @param termAuctionId The ID of the auction.
    /// @param termRepoId The ID of the repo.
    event CompleteAuctionUnpaused(bytes32 termAuctionId, bytes32 termRepoId);
}



// ============================================================
// FILE: contracts/interfaces/ITermAuctionOfferLockerEvents.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @notice ITermAuctionOfferLockerEvents is an interface that defines all events emitted by the Term Auction Offer Locker.
interface ITermAuctionOfferLockerEvents {
    event TermAuctionOfferLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionOfferLocker,
        uint256 auctionStartTime,
        uint256 revealTime,
        uint256 maxOfferPrice,
        uint256 minimumTenderAmount
    );

    event OfferLocked(
        bytes32 termAuctionId,
        bytes32 id,
        address offeror,
        bytes32 offerPrice,
        uint256 amount,
        address token,
        address referralAddress
    );

    event OfferRevealed(bytes32 termAuctionId, bytes32 id, uint256 offerPrice);

    event OfferUnlocked(bytes32 termAuctionId, bytes32 id);

    event OfferLockingPaused(bytes32 termAuctionId, bytes32 termRepoId);

    event OfferLockingUnpaused(bytes32 termAuctionId, bytes32 termRepoId);

    event OfferUnlockingPaused(bytes32 termAuctionId, bytes32 termRepoId);

    event OfferUnlockingUnpaused(bytes32 termAuctionId, bytes32 termRepoId);
}



// ============================================================
// FILE: contracts/interfaces/ITermController.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import {AuctionMetadata} from "../lib/AuctionMetadata.sol";

/// @notice ITermController is an interface that defines events and functions of the Controller contract.
interface ITermController {
    // ========================================================================
    // = Interface/API ========================================================
    // ========================================================================

    /// @notice External view function which returns contract address of treasury wallet
    function getTreasuryAddress() external view returns (address);

    /// @notice External view function which returns contract address of protocol reserve
    function getProtocolReserveAddress() external view returns (address);

    /// @notice External view function which returns if contract address is a Term Finance contract or not
    /// @param contractAddress input contract address
    function isTermDeployed(
        address contractAddress
    ) external view returns (bool);

    /// @notice External view function which returns whether contract address is deployed by a Term Finance factory
    /// @param contractAddress The input contract address to query
    /// @return Whether the given address is deployed by a Term Finance factory
    function isFactoryDeployed(
        address contractAddress
    ) external view returns (bool);

    /// @notice External view function which returns if term repo id is registered in Controller
    /// @param repoId input term repo id
    /// @return Whether the given term repo id is registered in Controller
    function registeredRepoIds(bytes32 repoId) external view returns (bool);

    ///@notice External view function which returns if term auction id is registered in Controller
    /// @param auctionId input term auction id
    /// @return Whether the given term auction id is registered in Controller
    function registeredAuctionIds(bytes32 auctionId) external view returns (bool);

    /// @notice External view function which returns if external contract address is approved for integration
    /// @param contractAddress input contract address
    function isTermApproved(
        address contractAddress
    ) external view returns (bool);

    /// @notice Returns history of all completed auctions within a term
    /// @param termRepoId term repo id to look up
    function getTermAuctionResults(
        bytes32 termRepoId
    )
        external
        view
        returns (AuctionMetadata[] memory auctionMetadata, uint8 numOfAuctions);

    /// @notice Returns whether all Term Finance contracts are currently paused
    /// @return True if contracts are paused, false otherwise
    function termContractsPaused() external view returns (bool);

    // ========================================================================
    // = Admin Functions ======================================================
    // ========================================================================

    /// @notice Initializer function to pair a new Term Auction with the controller
    /// @param auction    new auction address
    function pairAuction(address auction) external;

    /// @notice Admin function to update the Term Finance treasury wallet address
    /// @param treasuryWallet    new treasury address
    function updateTreasuryAddress(address treasuryWallet) external;

    /// @notice Admin function to update the Term Finance protocol reserve wallet address
    /// @param protocolReserveAddress    new protocol reserve wallet address
    function updateProtocolReserveAddress(
        address protocolReserveAddress
    ) external;

    /// @notice Admin function to add a new Term Finance contract to Controller
    /// @param termContract    new term contract address
    function markTermDeployed(address termContract) external;

    /// @notice Admin function to remove a contract from Controller
    /// @param termContract    term contract address to remove
    function unmarkTermDeployed(address termContract) external;

    /// @notice Admin function to add a new factory-deployed contract to Controller
    /// @param factoryDeployedContract The factory-deployed contract address
    function markTermFactoryDeployed(
        address factoryDeployedContract
    ) external;

    /// @notice Admin function to remove a factory-deployed contract from Controller
    /// @param factoryDeployedContract The factory-deployed contract address
    function unmarkTermFactoryDeployed(
        address factoryDeployedContract
    ) external;

    /// @notice Pauses all Term Finance contracts
    function pauseTermContracts() external;

    /// @notice Registers a new repo ID
    /// @param repoId    repo ID to register
    function registerRepoId(bytes32 repoId) external;

    /// @notice Registers a new auction ID
    /// @param auctionId auction ID to register
    function registerAuctionId(bytes32 auctionId) external;

    /// @notice Unpauses all Term Finance contracts
    function unpauseTermContracts() external;

    /// @notice Admin function to add an external contract approved for integration
    /// @param termContract    new external contract address
    function markTermApproved(address termContract) external;

    /// @notice Admin function to add an external contract approved for integration
    /// @param termContract    external contract address to remove
    function unmarkTermApproved(address termContract) external;

    /// @notice View Function to lookup if authedUser is granted mint exposure access
    /// @param authedUser    address to check for mint exposure access
    function verifyMintExposureAccess(
        address authedUser
    ) external view returns (bool);

    /// @notice Function for auction to add new auction completion information
    /// @param termId    term Id auction belongs to
    /// @param auctionId auction Id for auction
    /// @param auctionClearingRate auction clearing rate
    function recordAuctionResult(
        bytes32 termId,
        bytes32 auctionId,
        uint256 auctionClearingRate
    ) external;
}



// ============================================================
// FILE: contracts/interfaces/ITermEventEmitter.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import {ITermAuctionEvents} from "./ITermAuctionEvents.sol";
import {ITermAuctionBidLockerEvents} from "./ITermAuctionBidLockerEvents.sol";
import {ITermAuctionOfferLockerEvents} from "./ITermAuctionOfferLockerEvents.sol";
import {ITermRepoCollateralManagerEvents} from "./ITermRepoCollateralManagerEvents.sol";
import {ITermRepoServicerEvents} from "./ITermRepoServicerEvents.sol";
import {ITermRepoRolloverManagerEvents} from "./ITermRepoRolloverManagerEvents.sol";
import {ITermRepoLockerEvents} from "./ITermRepoLockerEvents.sol";
import {ITermRepoTokenEvents} from "./ITermRepoTokenEvents.sol";
import {ITermIntentEvents} from "./ITermIntentEvents.sol";
import {ITermEventEmitterEvents} from "./ITermEventEmitterEvents.sol";
import {TermAuctionBid} from "../lib/TermAuctionBid.sol";

interface ITermEventEmitter is
    ITermAuctionEvents,
    ITermAuctionBidLockerEvents,
    ITermAuctionOfferLockerEvents,
    ITermRepoCollateralManagerEvents,
    ITermRepoServicerEvents,
    ITermRepoRolloverManagerEvents,
    ITermRepoLockerEvents,
    ITermRepoTokenEvents,
    ITermIntentEvents,
    ITermEventEmitterEvents
{
    //@param termContract New term contract to pair to event emitter.
    function pairTermContract(address termContract) external;

    // ========================================================================
    // = TermAuction Events ===================================================
    // ========================================================================

    /// @param termRepoId The id of the current Term Repo deployment being initialized
    /// @param termAuctionId The id of the auction being initialized
    /// @param termAuction The address of the auction contract being initialized
    /// @param auctionEndTime The end time of the auction being initialized
    /// @param version The version tag of the smart contract deployed
    function emitTermAuctionInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuction,
        uint256 auctionEndTime,
        address deployerWallet,
        string calldata version
    ) external;

    /// @param termAuctionId A Term Auction id
    /// @param id A bid id
    /// @param amount The amount assigned to this bid
    function emitBidAssigned(
        bytes32 termAuctionId,
        bytes32 id,
        uint256 amount
    ) external;

    /// @param termAuctionId A Term Auction id
    /// @param id An offer id
    /// @param amount The amount assigned to this offer
    function emitOfferAssigned(
        bytes32 termAuctionId,
        bytes32 id,
        uint256 amount
    ) external;

    /// @param termAuctionId The Term Auction id of auction completed
    /// @param timestamp The timestamp of the current block
    /// @param blockNumber The number of the current block
    /// @param totalAssignedBids The number of assigned bids in the auction
    /// @param totalAssignedOffers The number of assigned offers in the auction
    /// @param clearingPrice The clearing price of the auction
    function emitAuctionCompleted(
        bytes32 termAuctionId,
        uint256 timestamp,
        uint256 blockNumber,
        uint256 totalAssignedBids,
        uint256 totalAssignedOffers,
        uint256 clearingPrice
    ) external;

    /// @param nonViableAuction Auction not viable due to bid and offer prices not intersecting
    /// @param auctionCancelledforWithdrawal Auction has been cancelled for withdrawal
    function emitAuctionCancelled(
        bytes32 termAuctionId,
        bool nonViableAuction,
        bool auctionCancelledforWithdrawal
    ) external;

    /// @param termAuctionId The id of the auction paused
    /// @param termRepoId The Term Repo id associated with auction paused
    function emitCompleteAuctionPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    /// @param termAuctionId The id of the auction unpaused
    /// @param termRepoId The Term Repo id associated with auction unpaused
    function emitCompleteAuctionUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    // ========================================================================
    // = TermAuctionBidLocker Events ==========================================
    // ========================================================================

    /// @param termRepoId The Term Repo id associated with BidLocker initialized
    /// @param termAuctionId The Term Auction id associated with BidLocker initialized
    /// @param termAuctionBidLocker The address of the TermAuctionBidLocker contract being intialized
    /// @param auctionStartTime The time at which auction bids will be accepted for submission
    /// @param revealTime The time at which sealed auction bids can be revealed
    /// @param maxBidPrice The maximum tender price (interest rate) in percentage
    /// @param minimumTenderAmount The minimum amount of borrowed purchase token that will be accepted
    /// @param dayCountFractionMantissa The day count fraction remainder
    function emitTermAuctionBidLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionBidLocker,
        uint256 auctionStartTime,
        uint256 revealTime,
        uint256 maxBidPrice,
        uint256 minimumTenderAmount,
        uint256 dayCountFractionMantissa
    ) external;

    /// @param termAuctionId A Term Auction id
    /// @param bid A struct containing details of the locked bid
    /// @param referralAddress The address of the referrer. Zero Address if none.
    function emitBidLocked(
        bytes32 termAuctionId,
        TermAuctionBid calldata bid,
        address referralAddress
    ) external;

    /// @param termAuctionId A Term Auction id
    /// @param id The bid id
    /// @param bidPrice The revealed price of the bid
    function emitBidRevealed(
        bytes32 termAuctionId,
        bytes32 id,
        uint256 bidPrice
    ) external;

    /// @param termAuctionId A Term Auction id
    /// @param id A bid id
    function emitBidUnlocked(bytes32 termAuctionId, bytes32 id) external;

    /// @param termAuctionId A Term Auction id
    /// @param id A bid id
    function emitBidInShortfall(bytes32 termAuctionId, bytes32 id) external;

    /// @param termAuctionId The id of Term Auction where bid locking is paused
    /// @param termRepoId The Term Repo id where bid locking is paused
    function emitBidLockingPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    /// @param termAuctionId The id of Term Auction where bid locking is unpaused
    /// @param termRepoId The Term Repo id where bid locking is unpaused
    function emitBidLockingUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    /// @param termAuctionId The id of Term Auction where bid unlocking is paused
    /// @param termRepoId The Term Repo id where bid unlocking is paused
    function emitBidUnlockingPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    /// @param termAuctionId The id of Term Auction where bid unlocking is unpaused
    /// @param termRepoId The Term Repo id where bid unlocking is unpaused
    function emitBidUnlockingUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    // ========================================================================
    // = TermAuctionOfferLocker Events ========================================
    // ========================================================================

    /// @param termRepoId The Term Repo id associated with OfferLocker initialized
    /// @param termAuctionId The Term Auction id associated with OfferLocker initialized
    /// @param termAuctionOfferLocker The address of the TermAuctionOfferLocker contract being intialized
    /// @param auctionStartTime The time at which auction bids will be accepted for submission
    /// @param revealTime The time at which sealed auction bids can be revealed
    function emitTermAuctionOfferLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionOfferLocker,
        uint256 auctionStartTime,
        uint256 revealTime,
        uint256 maxOfferPrice,
        uint256 minimumTenderAmount
    ) external;

    /// @param termAuctionId A Term Auction id
    /// @param id An offer id
    /// @param offeror The address of the offeror
    /// @param offerPrice The offer price
    /// @param amount The amount of purchase tokens offered
    /// @param purchaseToken The address of the purchase token being offered
    /// @param referralAddress The address of the referrer. Zero Address if none.
    function emitOfferLocked(
        bytes32 termAuctionId,
        bytes32 id,
        address offeror,
        bytes32 offerPrice,
        uint256 amount,
        address purchaseToken,
        address referralAddress
    ) external;

    /// @param termAuctionId A Term Auction id
    /// @param id An offer id
    /// @param offerPrice The offer price revealed
    function emitOfferRevealed(
        bytes32 termAuctionId,
        bytes32 id,
        uint256 offerPrice
    ) external;

    /// @param termAuctionId A Term Auction id
    /// @param id An offer id
    function emitOfferUnlocked(bytes32 termAuctionId, bytes32 id) external;

    /// @param termAuctionId The id of Term Auction where offer locking is paused
    /// @param termRepoId The Term Repo id where offer locking is paused
    function emitOfferLockingPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    /// @param termAuctionId The id of Term Auction where offer locking is unpaused
    /// @param termRepoId The Term Repo id where offer locking is unpaused
    function emitOfferLockingUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    /// @param termAuctionId The id of Term Auction where offer unlocking is paused
    /// @param termRepoId The Term Repo id where offer unlocking is paused
    function emitOfferUnlockingPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    /// @param termAuctionId The id of Term Auction where offer unlocking is unpaused
    /// @param termRepoId The Term Repo id where offer unlocking is unpaused
    function emitOfferUnlockingUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    // ========================================================================
    // = TermRepoCollateralManager Events =========================================
    // ========================================================================

    /// @param termRepoId The Term Repo id associated with collateral manger being initialized
    /// @param termRepoCollateralManager The address of the TermRepoCollateralManager contract being intialized
    /// @param collateralTokens An array containing a list of the addresses of all accepted collateral tokens
    /// @param initialCollateralRatios An array containing the initial collateral ratios for each collateral token
    /// @param maintenanceCollateralRatios An array containing the maintenance collateral ratios for each collateral token
    /// @param liquidatedDamagesSchedule An array containing the liquidated damages applicable to each collateral token
    function emitTermRepoCollateralManagerInitialized(
        bytes32 termRepoId,
        address termRepoCollateralManager,
        address[] calldata collateralTokens,
        uint256[] calldata initialCollateralRatios,
        uint256[] calldata maintenanceCollateralRatios,
        uint256[] calldata liquidatedDamagesSchedule
    ) external;

    /// @param termRepoId The Term Repo id for the Term Repo being reopened
    /// @param termRepoCollateralManager The TermRepoCollateralManager address for the Term Repo being reopened
    /// @param termAuctionBidLocker New TermAuctionBidLocker to be paired for reopening
    function emitPairReopeningBidLocker(
        bytes32 termRepoId,
        address termRepoCollateralManager,
        address termAuctionBidLocker
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param borrower The address of the borrower
    /// @param collateralToken The address of the collateral token locked
    /// @param amount The amount of collateral being locked
    function emitCollateralLocked(
        bytes32 termRepoId,
        address borrower,
        address collateralToken,
        uint256 amount
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param borrower The address of the borrower
    /// @param collateralToken The address of the collateral token locked
    /// @param amount The amount of collateral being unlocked
    function emitCollateralUnlocked(
        bytes32 termRepoId,
        address borrower,
        address collateralToken,
        uint256 amount
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param borrower The address of the borrower
    /// @param liquidator The address of the liquidator
    /// @param closureAmount The amount of repurchase exposure covered
    /// @param collateralToken The address of the collateral tokens liquidated
    /// @param amountLiquidated The amount of collateral tokens liquidated
    function emitLiquidation(
        bytes32 termRepoId,
        address borrower,
        address liquidator,
        uint256 closureAmount,
        address collateralToken,
        uint256 amountLiquidated,
        uint256 protocolSeizureAmount,
        bool defaultLiquidation
    ) external;

    /// @param termRepoId The id of Term Repo where liquidations are paused
    function emitLiquidationPaused(bytes32 termRepoId) external;

    /// @param termRepoId The id of Term Repo where liquidation is unpaused
    function emitLiquidationUnpaused(bytes32 termRepoId) external;

    // ========================================================================
    // = TermRepoServicer Events ===============================================
    // ========================================================================

    /// @param termRepoId The Term Repo id associated with TermRepoServicer being initialized
    /// @param termRepoServicer The address of the TermRepoServicer contract being initialized
    /// @param purchaseToken The address of the purchase token
    /// @param maturityTimestamp The time at which repurchase is due
    /// @param endOfRepurchaseWindow The time at which the repurchase window ends
    /// @param redemptionTimestamp The time when redemption of Term Repo Tokens begins
    /// @param servicingFee percentage share of bid amounts charged to bidder
    /// @param version The version tag of the smart contract deployed
    function emitTermRepoServicerInitialized(
        bytes32 termRepoId,
        address termRepoServicer,
        address purchaseToken,
        uint256 maturityTimestamp,
        uint256 endOfRepurchaseWindow,
        uint256 redemptionTimestamp,
        uint256 servicingFee,
        address deployerWallet,
        string calldata version
    ) external;

    /// @param termRepoId The Term Repo id for the Term Repo being reopened
    /// @param termRepoServicer The address of the TermRepoServicer contract for the Term Repo being reopened
    /// @param termAuctionOfferLocker The TermAuctionOfferLocker to be paired for reopening
    /// @param termAuction The address of the TermAuction contract to be paired for reopening
    function emitReopeningOfferLockerPaired(
        bytes32 termRepoId,
        address termRepoServicer,
        address termAuctionOfferLocker,
        address termAuction
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param offeror The address of the offeror
    /// @param amount The offer amount to be locked
    /// @notice This event is not to be confused with OfferLocked by TermOfferLocker
    /// @notice Both will be triggered, this one specifically refers to corresponding action taken by Term Servicer
    function emitOfferLockedByServicer(
        bytes32 termRepoId,
        address offeror,
        uint256 amount
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param offeror The address of the offeror
    /// @param amount The offer amount to be unlocked
    /// @notice This event is not to be confused with OfferUnlocked by TermOfferLocker
    /// @notice Both will be triggered, this one specifically refers to corresponding action taken by Term Servicer
    function emitOfferUnlockedByServicer(
        bytes32 termRepoId,
        address offeror,
        uint256 amount
    ) external;

    /// @param offerId Unique id for offer
    /// @param offeror The address of the offeror
    /// @param purchasePrice The offer amount fulfilled
    /// @param repurchasePrice The repurchase price due to offeror at maturity
    /// @param repoTokensMinted The amount of Term Repo Tokens minted to offeror
    function emitOfferFulfilled(
        bytes32 offerId,
        address offeror,
        uint256 purchasePrice,
        uint256 repurchasePrice,
        uint256 repoTokensMinted
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param redeemer The address of the redeemer
    /// @param redemptionAmount The amount of TermRepoTokens redeemed
    /// @param redemptionHaircut The haircut applied to redemptions (if any) due to unrecoverable repo exposure
    function emitTermRepoTokensRedeemed(
        bytes32 termRepoId,
        address redeemer,
        uint256 redemptionAmount,
        uint256 redemptionHaircut
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param bidder The address of the bidder
    /// @param purchasePrice The bid amount fulfilled in auction
    /// @param repurchasePrice The repurchase price due at maturity
    /// @param servicingFees The fees earned by the protocol
    function emitBidFulfilled(
        bytes32 termRepoId,
        address bidder,
        uint256 purchasePrice,
        uint256 repurchasePrice,
        uint256 servicingFees
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param borrower The address of the borrower
    /// @param purchasePrice The purchase price received from new TermRepo
    /// @param repurchasePrice The new repurchase price due at maturity of new TermRepo
    /// @param servicingFees The fees earned by the protocol
    function emitExposureOpenedOnRolloverNew(
        bytes32 termRepoId,
        address borrower,
        uint256 purchasePrice,
        uint256 repurchasePrice,
        uint256 servicingFees
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param borrower The address of the borrower
    /// @param amountRolled The repurchase exposure balance closed on old Term Repo
    function emitExposureClosedOnRolloverExisting(
        bytes32 termRepoId,
        address borrower,
        uint256 amountRolled
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param borrower The address of the borrower
    /// @param amount The amount submitted for repurchase
    function emitRepurchasePaymentSubmitted(
        bytes32 termRepoId,
        address borrower,
        uint256 amount
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param authedUser User granted mint exposure access
    function emitMintExposureAccessGranted(
        bytes32 termRepoId,
        address authedUser
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param minter The address of the minter
    /// @param netTokensReceived The amount of Term Repo Tokens received by minter net of servicing fees
    /// @param servicingFeeTokens The number of Term Repo Tokens retained by protocol in servicing fees
    /// @param repurchasePrice The repurchase exposure opened by minter against Term Repo Token mint
    function emitMintExposure(
        bytes32 termRepoId,
        address minter,
        uint256 netTokensReceived,
        uint256 servicingFeeTokens,
        uint256 repurchasePrice
    ) external;

    /// @param termRepoId A Term Repo id
    /// @param borrower The address of the borrower
    /// @param closeAmount The amount of repurchase exposure to close
    function emitBurnCollapseExposure(
        bytes32 termRepoId,
        address borrower,
        uint256 closeAmount
    ) external;

    // ========================================================================
    // = TermRepoRolloverManager Events ===========================================
    // ========================================================================

    /// @param termRepoId The Term Repo id associated with TermRepoRolloverManager being initialized
    /// @param rolloverManager The address of the TermRepoRolloverManager contract being initialized
    function emitTermRepoRolloverManagerInitialized(
        bytes32 termRepoId,
        address rolloverManager
    ) external;

    /// @param termRepoId The Term Repo id of existing Term Repo
    /// @param rolloverTermAuctionId The Term Auction Id that rollover bid will be submitted into
    function emitRolloverTermApproved(
        bytes32 termRepoId,
        bytes32 rolloverTermAuctionId
    ) external;

    /// @param termRepoId The Term Repo id of existing Term Repo
    /// @param rolloverTermAuctionId The Term Auction Id whose rollover approval is revoked
    function emitRolloverTermApprovalRevoked(
        bytes32 termRepoId,
        bytes32 rolloverTermAuctionId
    ) external;

    /// @param termRepoId The Term Repo id of existing Term Repo
    /// @param rolloverTermRepoId Term Repo Id of Rollover Term Repo
    /// @param borrower The address of the borrower
    /// @param rolloverAuction The address of the auction being rolled over to
    /// @param rolloverAmount The repurchase amount being rolled over
    /// @param hashedBidPrice The hash of the rollover bid price
    function emitRolloverElection(
        bytes32 termRepoId,
        bytes32 rolloverTermRepoId,
        address borrower,
        address rolloverAuction,
        uint256 rolloverAmount,
        bytes32 hashedBidPrice
    ) external;

    /// @param termRepoId The Term Repo id of existing Term Repo
    /// @param borrower The address of the borrower
    function emitRolloverCancellation(
        bytes32 termRepoId,
        address borrower
    ) external;

    /// @param termRepoId The Term Repo id of existing Term Repo
    /// @param borrower The address of the borrower
    function emitRolloverProcessed(
        bytes32 termRepoId,
        address borrower
    ) external;

    // ========================================================================
    // = TermRepoLocker Events ======================================================
    // ========================================================================

    /// @param termRepoId The Term Repo id associated with TermRepoLocker contract being initialized
    /// @param termRepoLocker The address of the TermRepoLocker contract being initialized
    function emitTermRepoLockerInitialized(
        bytes32 termRepoId,
        address termRepoLocker
    ) external;

    /// @param termRepoId A Term Repo id
    function emitTermRepoLockerTransfersPaused(bytes32 termRepoId) external;

    /// @param termRepoId A Term Repo id
    function emitTermRepoLockerTransfersUnpaused(bytes32 termRepoId) external;

    // ========================================================================
    // = TermRepoToken Events =====================================================
    // ========================================================================

    /// @param termRepoId The Term Repo id associated with the TermRepoToken being initalized
    /// @param termRepoToken The address of the TermRepoToken contract being initialized
    /// @param redemptionRatio The number of purchase tokens redeemable per unit of Term Repo Token at par
    function emitTermRepoTokenInitialized(
        bytes32 termRepoId,
        address termRepoToken,
        uint256 redemptionRatio
    ) external;

    /// @param termRepoId The Term Repo id associated with the TermRepoToken where minting is paused
    function emitTermRepoTokenMintingPaused(bytes32 termRepoId) external;

    /// @param termRepoId The Term Repo id associated with the TermRepoToken where minting is unpaused
    function emitTermRepoTokenMintingUnpaused(bytes32 termRepoId) external;

    /// @param termRepoId The Term Repo id associated with the TermRepoToken where burning is paused
    function emitTermRepoTokenBurningPaused(bytes32 termRepoId) external;

    /// @param termRepoId The Term Repo id associated with the TermRepoToken where burning is unpaused
    function emitTermRepoTokenBurningUnpaused(bytes32 termRepoId) external;

    // ========================================================================
    // = TermIntent Events ====================================================
    // ========================================================================

    /// @param orderHash The hash of the order that was filled
    /// @param termRepoId The Term Repo id associated with the intent
    /// @param purchaseToken The address of the purchase token
    /// @param maker The address of the maker
    /// @param taker The address of the taker
    /// @param makerToken The address of the maker's token
    /// @param takerToken The address of the taker's token
    /// @param offerRate The rate of the offer
    /// @param makerTokenAmountFilled The amount of maker tokens filled
    /// @param takerTokenAmountFilled The amount of taker tokens filled
    /// @param proratedBorrowFee The prorated fee for borrow
    /// @param feeRecipient The address that receives the fees
    /// @param originalOrderAmount The original purchaseTokenAmount of the maker provided by the Maker
    /// @param expiry The expiration date of the order
    /// @param salt The user generated value for order uniqueness and replay protection
    function emitIntentFilled(
        bytes32 orderHash,
        bytes32 termRepoId,
        address purchaseToken,
        address maker,
        address taker,
        address makerToken,
        address takerToken,
        uint256 offerRate,
        uint256 makerTokenAmountFilled,
        uint256 takerTokenAmountFilled,
        uint256 proratedBorrowFee,
        address feeRecipient,
        uint256 originalOrderAmount,
        uint256 expiry,
        uint256 salt
    ) external;

    /// @param orderHash The hash of the order that was cancelled
    function emitIntentCancelled(bytes32 orderHash) external;

    /// @param orderHash The hash of the order that was filled
    /// @param swapData The swap data containing all swap details
    function emitRepoTokenSwapFilled(
        bytes32 orderHash,
        RepoTokenSwapData calldata swapData
    ) external;


    /**
     * @notice Emits an event for the minimum salt value required for limit order token pairs
     * @dev This function is used to emit events when a minimum salt value is set for a specific token pair by a maker
     * @param maker The address of the order maker who set the minimum salt value
     * @param makerToken The address of the token being offered by the maker
     * @param takerToken The address of the token being requested by the maker
     * @param minSaltValue The minimum salt value required for orders with this token pair
     */
    function emitLimitOrderTokenPairMinSaltValue(
        address maker,
        address makerToken,
        address takerToken,
        uint256 minSaltValue
    ) external;

    /**
     * @notice Emits an event for the minimum salt value required for swap order token pairs
     * @dev This function is used to emit events when a minimum salt value is set for a specific token pair by a maker
     * @param maker The address of the order maker who set the minimum salt value
     * @param makerToken The address of the token being offered by the maker
     * @param takerToken The address of the token being requested by the maker
     * @param minSaltValue The minimum salt value required for orders with this token pair
     */
    function emitSwapOrderTokenPairMinSaltValue(
        address maker,
        address makerToken,
        address takerToken,
        uint256 minSaltValue
    ) external;

    // ========================================================================
    // = TermEventEmitter Events ==============================================
    // ========================================================================

    /// @param termRepoId The id of the Term Repo being delisted
    function emitDelistTermRepo(bytes32 termRepoId) external;

    /// @param termAuctionId The id of the Term Auction being delisted
    function emitDelistTermAuction(bytes32 termAuctionId) external;

    /// @param proxy address of proxy contract
    /// @param implementation address of new impl contract proxy has been upgraded to
    function emitTermContractUpgraded(
        address proxy,
        address implementation
    ) external;
}



// ============================================================
// FILE: contracts/interfaces/ITermEventEmitterEvents.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

interface ITermEventEmitterEvents {
    /// @notice Event emitted when a new Term Repo is delisted on Term Finance
    /// @param termRepoId unique identifier for a Term Repo
    event DelistTermRepo(bytes32 termRepoId);

    /// @notice Event emitted when a new Term Auction is delisted on Term Finance
    /// @param termAuctionId unique identifier for a Term Auction
    event DelistTermAuction(bytes32 termAuctionId);

    /// @notice Event emitted when a Term contract is upgraded to a new implementation
    /// @param proxy address of proxy contract
    /// @param implementation address of new impl contract proxy has been upgraded to
    event TermContractUpgraded(address proxy, address implementation);
}



// ============================================================
// FILE: contracts/interfaces/ITermIntent.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @title ITermIntent Term Intent Interface
/// @notice Interface for settlement operations including limit orders and repo token swaps
interface ITermIntent {
    // ========================================================================
    // = Enums ================================================================
    // ========================================================================
    enum OrderStatus {
        UNFILLED,
        PARTIALLY_FILLED,
        FILLED,
        CANCELLED
    }

    enum OrderType {
        LEND,
        BORROW,
        SWAP
    }

    enum SignatureType {
        EIP712,
        PRESIGN
    }

    // ========================================================================
    // = Structs ==============================================================
    // ========================================================================

    /**
     * @notice Represents a limit order for lending in a term repo auction
     * @dev Used for off-chain order creation and on-chain settlement
     * @param repoServicer Address of the repo servicer contract
     * @param purchaseTokenAmount Amount of purchase tokens to lend, in native purchase token decimals
     * @param offerRate Interest rate offered, percentage in 1e18 format (1e18 = 100%, 1e17 = 10%, 1e16 = 1%)
     * @param maker Address of the order creator (lender)
     * @param taker Address of the order taker (borrower), zero address for any taker
     * @param borrowFee Fee charged to the borrower, percentage in 1e18 format (1e18 = 100%, 1e17 = 10%, 1e16 = 1%)
     * @param feeRecipient Address that receives the fees
     * @param expiry Order expiration timestamp (Unix timestamp)
     * @param salt Random value for order uniqueness and replay protection
     * @param retrieveFunds Instructions for fund retrieval after settlement
     */
    struct LimitLendOrder {
        address repoServicer;
        uint256 purchaseTokenAmount;
        uint256 offerRate; 
        address maker;
        address taker;
        uint256 borrowFee;
        address feeRecipient; 
        uint256 expiry;
        uint256 salt;
        RetrieveFundsStruct retrieveFunds;
    }

    /**
     * @notice Represents a limit order for borrowing in a term repo auction
     * @dev Used for off-chain order creation and on-chain settlement
     * @param repoServicer Address of the repo servicer contract
     * @param purchaseTokenAmount Amount of purchase tokens to borrow, in native purchase token decimals
     * @param collateralAmounts Array of collateral token amounts, each in native collateral token decimals
     * @param offerRate Interest rate offered, percentage in 1e18 format (1e18 = 100%, 1e17 = 10%, 1e16 = 1%)
     * @param maker Address of the order creator (borrower)
     * @param taker Address of the order taker (lender), zero address for any taker
     * @param borrowFee Fee charged to the borrower, percentage in 1e18 format (1e18 = 100%, 1e17 = 10%, 1e16 = 1%)
     * @param feeRecipient Address that receives the fees
     * @param expiry Order expiration timestamp (Unix timestamp)
     * @param salt User generated value for order uniqueness and replay protection
     * @param retrieveFundsList Array of instructions for fund retrieval after settlement
     */
    struct LimitBorrowOrder {
        address repoServicer;
        uint256 purchaseTokenAmount;
        uint256[] collateralAmounts;
        uint256 offerRate;
        address maker;
        address taker;
        uint256 borrowFee;
        address feeRecipient;
        uint256 expiry;
        uint256 salt;
        RetrieveFundsStruct[] retrieveFundsList;
    }

    /**
     * @notice Represents an order for swapping repo tokens for purchase tokens or vice versa
     * @dev Used for trading repo tokens at a discount to their underlying value
     * @param repoToken Address of the repo token contract
     * @param makerAssetIsPurchaseToken True if maker is offering purchase tokens, false if offering repo tokens
     * @param purchaseTokenAmount Amount of purchase tokens involved in the swap, in native purchase token decimals
     * @param discountRate Discount rate applied to the swap, percentage in 1e18 format (1e18 = 100%, 1e17 = 10%, 1e16 = 1%)
     * @param maker Address of the order creator
     * @param taker Address of the order taker, zero address for any taker
     * @param makerFee Fee charged to the maker, percentage in 1e18 format (1e18 = 100%, 1e17 = 10%, 1e16 = 1%)
     * @param takerFee Fee charged to the taker, percentage in 1e18 format (1e18 = 100%, 1e17 = 10%, 1e16 = 1%)
     * @param feeRecipient Address that receives the fees
     * @param expiry Order expiration timestamp (Unix timestamp)
     * @param salt User generated value for order uniqueness and replay protection
     * @param retrieveFunds Instructions for fund retrieval after settlement
     */
    struct RepoTokenSwapOrder {
        address repoToken;
        bool makerAssetIsPurchaseToken;
        uint256 purchaseTokenAmount; 
        uint256 discountRate; 
        address maker;
        address taker;
        uint256 makerFee; 
        uint256 takerFee; 
        address feeRecipient;
        uint256 expiry; 
        uint256 salt;
        RetrieveFundsStruct retrieveFunds;
    }

    /**
     * @notice Defines instructions for retrieving funds after order settlement
     * @dev Used to specify custom fund retrieval logic via external contract calls
     * @param method Function selector (bytes4) of the method to call for fund retrieval
     * @param target Address of the contract to call for fund retrieval
     * @param additionalCalldata Additional calldata to used to encode the function call
     */
    struct RetrieveFundsStruct{
        bytes4 method;
        address target;
        bytes additionalCalldata;
    }

    /**
     * @notice Represents a signature for order authorization
     * @dev Supports multiple signature types for flexible order authentication
     * @param sigType Type of signature (EIP712 or PRESIGN)
     * @param sigData Raw signature data, format depends on sigType
     */
    struct Signature {
        SignatureType sigType;
        bytes sigData;
    }

    /**
     * @notice Tracks the execution state and filled amount for an order
     * @dev Used to prevent double-spending and track partial fills
     * @param filledAmount Total amount filled for this order (in purchase token units)
     * @param status Current execution status of the order
     */
    struct OrderContext {
        uint128 filledAmount;
        OrderStatus status;
    }

    // ========================================================================
    // = Errors ===============================================================
    // ========================================================================

    /// @notice Thrown when operation attempted after maturity
    error AfterMaturity();
    /// @notice Thrown when TermIntent storage is already initialized
    error AlreadyInitialized();
    /// @notice Notice when setting signer for already presigned order
    error AlreadyPreSigned(address signer);
    /// @notice Thrown when fee recipient is already approved
    error FeeRecipientAlreadyApproved();
    /// @notice Thrown when there is insufficient capacity remaining to fill the order
    error InsufficientRemainingCapacity(uint256 capacityRemaining);
    /// @notice Thrown when collateral amounts list does not match collateral manager tokens array
    error InvalidCollateralAmountsInput();
    /// @notice Thrown when discount rate is invalid
    error InvalidDiscountRate();
    /// @notice Thrown when fee value is invalid
    error InvalidFee();
    /// @notice Thrown when fee recipient is not approved
    error InvalidFeeRecipient();
    /// @notice Thrown when fill amount is invalid
    error InvalidFillAmount();
    /// @notice Thrown when insufficient funds are retrieved before settlement
    error InsufficientFundsRetrieved();
    /// @notice Thrown when minimum salt value is invalid
    error InvalidMinSalt();
    /// @notice Thrown when offer rate is invalid
    error InvalidOfferRate();
    /// @notice Thrown when order status is invalid for the operation
    error InvalidOrderStatus();
    /// @notice Thrown when invalid parameters are provided
    error InvalidParameters(string message);
    /// @notice Thrown when purchase token amount is invalid
    error InvalidPurchaseTokenAmount();
    /// @notice Thrown when repo ID is invalid
    error InvalidRepoId();
    /// @notice Thrown when retrieve funds function selector is not diamond cut
    error InvalidRetrieveFundsFunction();
    /// @notice Thrown when retrieve funds list does not match collateral amounts list
    error InvalidRetrieveFundsListLength();
    /// @notice Thrown when sender address doesn't match expected address
    error InvalidSender(address expected, address actual);
    /// @notice Thrown when signature verification fails
    error InvalidSignature();
    /// @notice Thrown when taker address doesn't match expected address
    error InvalidTaker(address expected, address actual);
    /// @notice Thrown when term controller is invalid
    error InvalidTermController();
    /// @notice Thrown when order has expired
    error OrderExpired();
    /// @notice Thrown when order has been cancelled
    error OrderCancelled();
    /// @notice Thrown when order maker matches taker
    error MakerCannotBeTaker();
    /// @notice Thrown when retrieve funds parameter not specified for hook execution
    error RetrieveFundsNotSpecified();
    /// @notice Thrown when term controller is already approved
    error TermControllerAlreadyApproved(); 
    /// @notice Thrown when selector is not supported for preview or execution
    error UnsupportedSelector();

}



// ============================================================
// FILE: contracts/interfaces/ITermIntentEvents.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @notice ITermIntentEvents is an interface that defines all events emitted by the Term Intent contracts.
interface ITermIntentEvents {
    // ========================================================================
    // = Structs ==============================================================
    // ========================================================================

    /// @notice Data structure containing all information about a repo token swap transaction
    /// @dev Used in RepoTokenSwapFilled event to provide comprehensive swap details
    /// @param repoToken The repo token being swapped
    /// @param purchaseToken The purchase token involved in the swap
    /// @param maker The address of the order maker (initiator of the swap)
    /// @param taker The address of the order taker (counterparty of the swap)
    /// @param makerToken The token provided by the maker
    /// @param takerToken The token provided by the taker
    /// @param discountRate The discount rate applied to the swap (in basis points or similar unit)
    /// @param makerTokenAmountFilled The amount of maker tokens that were filled in the swap
    /// @param takerTokenAmountFilled The amount of taker tokens that were filled in the swap
    /// @param makerFee The fee paid by the maker for the swap
    /// @param takerFee The fee paid by the taker for the swap
    /// @param feeRecipient The address that receives the swap fees
    /// @param originalOrderAmount The original purchaseTokenAmount of the maker provided by the Maker
    /// @param expiry The expiration date of the order
    /// @param salt The user generated value for order uniqueness and replay protection
    struct RepoTokenSwapData {
        address repoToken;
        address purchaseToken;
        address maker;
        address taker;
        address makerToken;
        address takerToken;
        uint256 discountRate;
        uint256 makerTokenAmountFilled;
        uint256 takerTokenAmountFilled;
        uint256 makerFee;
        uint256 takerFee;
        address feeRecipient;
        uint256 originalOrderAmount;
        uint256 expiry;
        uint256 salt;
    }

    // ========================================================================
    // = Events ===============================================================
    // ========================================================================

    /// @notice Event emitted when an intent is successfully filled
    /// @param orderHash The hash of the order that was filled
    /// @param termRepoId The ID of the term repo
    /// @param purchaseToken The token being purchased
    /// @param maker The address of the order maker
    /// @param taker The address of the order taker
    /// @param makerToken The token provided by the maker
    /// @param takerToken The token provided by the taker
    /// @param offerRate The rate of the offer
    /// @param makerTokenAmountFilled The amount of maker tokens filled
    /// @param takerTokenAmountFilled The amount of taker tokens filled
    /// @param proratedBorrowFee The prorated fee for borrow
    /// @param feeRecipient The address that receives the fees
    /// @param originalOrderAmount The original purchaseTokenAmount of the maker provided by the Maker
    /// @param expiry The expiration date of the order
    /// @param salt The user generated value for order uniqueness and replay protection
    event IntentFilled(
        bytes32 orderHash,
        bytes32 termRepoId,
        address purchaseToken,
        address maker,
        address taker,
        address makerToken,
        address takerToken,
        uint256 offerRate,
        uint256 makerTokenAmountFilled,
        uint256 takerTokenAmountFilled,
        uint256 proratedBorrowFee,
        address feeRecipient,
        uint256 originalOrderAmount,
        uint256 expiry,
        uint256 salt
    );

    /// @notice Event emitted when an intent is successfully cancelled
    /// @param orderHash The hash of the order that was cancelled
    event IntentCancelled(
        bytes32 orderHash
    );

    /// @notice Event emitted when a repo token swap order is filled
    /// @param orderHash The hash of the order that was filled
    /// @param swapData The swap data containing all swap details
    event RepoTokenSwapFilled(
        bytes32 orderHash,
        RepoTokenSwapData swapData
    );

    /// @notice Event emitted when a minimum salt value is set for limit orders of a specific token pair by a maker
    /// @dev This event is used to track the minimum salt requirements for order creation
    /// @param maker The address of the maker setting the minimum salt value
    /// @param makerToken The address of the token being offered by the maker
    /// @param takerToken The address of the token being requested by the maker
    /// @param minSaltValue The minimum salt value required for orders with this token pair
    event LimitOrderTokenPairMinSalt(
        address maker,
        address makerToken,
        address takerToken,
        uint256 minSaltValue
    );

    /// @notice Event emitted when a minimum salt value is set for swap orders of a specific token pair by a maker
    /// @dev This event is used to track the minimum salt requirements for order creation
    /// @param maker The address of the maker setting the minimum salt value
    /// @param makerToken The address of the token being offered by the maker
    /// @param takerToken The address of the token being requested by the maker
    /// @param minSaltValue The minimum salt value required for orders with this token pair
    event SwapOrderTokenPairMinSalt(
        address maker,
        address makerToken,
        address takerToken,
        uint256 minSaltValue
    );
}


// ============================================================
// FILE: contracts/interfaces/ITermRepoCollateralManagerEvents.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @notice ITermRepoCollateralManagerEvents is an interface that defines all events emitted by Term Repo Collateral Manager.
interface ITermRepoCollateralManagerEvents {
    /// @notice Event emitted when a Term Repo Collateral Manager is initialized.
    /// @param termRepoId                  term identifier
    /// @param collateralTokens        addresses of accepted collateral tokens
    /// @param initialCollateralRatios list of initial collateral ratios for each collateral token in the same order as collateral tokens list
    /// @param maintenanceCollateralRatios       list of maintenance ratios for each collateral token in the same order as collateral tokens list
    /// @param liquidatedDamagesSchedule    liquidation discounts for collateral tokens
    event TermRepoCollateralManagerInitialized(
        bytes32 termRepoId,
        address termRepoCollateralManager,
        address[] collateralTokens,
        uint256[] initialCollateralRatios,
        uint256[] maintenanceCollateralRatios,
        uint256[] liquidatedDamagesSchedule
    );

    /// @notice Event emitted when existing Term Repo Locker is reopened to another auction group
    /// @param termRepoId                     term identifier
    /// @param termRepoCollateralManager          address of collateral manager
    /// @param termAuctionBidLocker       address of auction bid locker paired through reopening
    event PairReopeningBidLocker(
        bytes32 termRepoId,
        address termRepoCollateralManager,
        address termAuctionBidLocker
    );

    /// @notice Event emitted when collateral is locked.
    /// @param termRepoId             term identifier
    /// @param borrower           address of borrower who locked collateral
    /// @param collateralToken    address of collateral token
    /// @param amount             amount of collateral token locked
    event CollateralLocked(
        bytes32 termRepoId,
        address borrower,
        address collateralToken,
        uint256 amount
    );

    /// @notice Event emitted when collateral is locked.
    /// @param termRepoId             term identifier
    /// @param borrower           address of borrower who locked collateral
    /// @param collateralToken    address of collateral token
    /// @param amount             amount of collateral token unlocked
    event CollateralUnlocked(
        bytes32 termRepoId,
        address borrower,
        address collateralToken,
        uint256 amount
    );

    /// @notice Event emitted when a liquidation occurs
    /// @param termRepoId                term identifier
    /// @param borrower              address of borrower being liquidated
    /// @param liquidator            address of liquidator
    /// @param closureAmount       amount of loan repaid by liquidator
    /// @param collateralToken       address of collateral token liquidated
    /// @param amountLiquidated      amount of collateral liquidated
    /// @param protocolSeizureAmount amount of collateral liquidated and seized by protocol as fee
    /// @param defaultLiquidation    boolean indicating if liquidation is a default or not
    event Liquidation(
        bytes32 termRepoId,
        address borrower,
        address liquidator,
        uint256 closureAmount,
        address collateralToken,
        uint256 amountLiquidated,
        uint256 protocolSeizureAmount,
        bool defaultLiquidation
    );

    /// @notice Event emitted when a Liquidations are paused for a term
    /// @param termRepoId                     term identifier
    event LiquidationsPaused(bytes32 termRepoId);

    /// @notice Event emitted when a Liquidations are unpaused for a term
    /// @param termRepoId                     term identifier
    event LiquidationsUnpaused(bytes32 termRepoId);
}



// ============================================================
// FILE: contracts/interfaces/ITermRepoLockerEvents.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @notice ITermRepoLockerEvents is an interface that defines all events emitted by the TermRepoLocker.
interface ITermRepoLockerEvents {
    /// @notice Event emitted when a TermRepoLocker is initialized.
    /// @param termRepoId term identifier
    /// @param termRepoLocker address of initialized term repo locker
    event TermRepoLockerInitialized(bytes32 termRepoId, address termRepoLocker);

    /// @notice Event emitted transfers for a TermRepoLocker are paused.
    /// @param termRepoId term identifier
    event TermRepoLockerTransfersPaused(bytes32 termRepoId);

    /// @notice Event emitted transfers for a TermRepoLocker are unpaused.
    /// @param termRepoId term identifier
    event TermRepoLockerTransfersUnpaused(bytes32 termRepoId);
}



// ============================================================
// FILE: contracts/interfaces/ITermRepoRolloverManagerEvents.sol
// ============================================================
//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.22;

/// @notice ITermRepoCollateralManagerEvents is an interface that defines all events emitted by Term Repo Collateral Manager.
interface ITermRepoRolloverManagerEvents {
    /// @notice Event emitted when a rollover manager is initialized
    /// @param termRepoId A Term Repo id
    /// @param rolloverManager Address of rollover manager
    event TermRepoRolloverManagerInitialized(
        bytes32 termRepoId,
        address rolloverManager
    );

    /// @notice Event emitted when a rollover manager approves a future term as a destination for borrows
    /// @param termRepoId A Term Repo id
    /// @param rolloverTermAuctionId The Term Auction Id that rollover bid will be submitted into
    event RolloverTermApproved(
        bytes32 termRepoId,
        bytes32 rolloverTermAuctionId
    );

    /// @notice Event emitted when a rollover manager revokes approval for a future term as a destination for borrows
    /// @param termRepoId A Term Repo id
    /// @param rolloverTermAuctionId The Term Auction Id that rollover bid will be submitted into
    event RolloverTermApprovalRevoked(
        bytes32 termRepoId,
        bytes32 rolloverTermAuctionId
    );

    /// @notice Event emitted when a borrower elects a rollover contract
    /// @param termRepoId A Term Repo id
    /// @param rolloverTermRepoId Term Repo Id of Rollover Term Repo
    /// @param borrower The address of the borrower
    /// @param rolloverAuction The address of rollover term contract
    /// @param rolloverAmount Amount of purchase currency borrower is rolling over
    /// @param hashedBidPrice The hash of rollover bid price
    event RolloverElection(
        bytes32 termRepoId,
        bytes32 rolloverTermRepoId,
        address borrower,
        address rolloverAuction,
        uint256 rolloverAmount,
        bytes32 hashedBidPrice
    );

    /// @notice Event emitted when a borrower cancels a rollover election
    /// @param termRepoId A Term Repo id
    /// @param borrower The address of the borrower
    event RolloverCancellation(bytes32 termRepoId, address borrower);

    /// @notice Event emitted when a rollover is processed completely
    /// @param termRepoId A Term Repo id
    /// @param borrower The address of borrower
    event RolloverProcessed(bytes32 termRepoId, address borrower);
}



// ============================================================
// FILE: contracts/interfaces/ITermRepoServicerEvents.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @notice ITermRepoServicerEvents is an interface that defines all events emitted by the Term Repo Servicer.
interface ITermRepoServicerEvents {
    /// @notice Event emitted when a Term Loan Manager is initialized.
    /// @param termRepoId A Term Repo id
    /// @param purchaseToken The address of purchase token used for loans and repay
    /// @param maturityTimestamp The timestamp at which term reaches maturity
    /// @param endOfRepurchaseWindow The timestamp at which Term Repo is closed to repurchase
    /// @param redemptionTimestamp The timestamp at which loaners can redeem term repo tokens
    /// @param servicingFee percentage share of bid amounts charged to bidder
    /// @param version The version tag of the smart contract deployed
    event TermRepoServicerInitialized(
        bytes32 termRepoId,
        address termRepoServicer,
        address purchaseToken,
        uint256 maturityTimestamp,
        uint256 endOfRepurchaseWindow,
        uint256 redemptionTimestamp,
        uint256 servicingFee,
        address deployerWallet,
        string version
    );

    /// @notice Event emitted when a TermRepoLocker is reopened to another auction group
    /// @param termRepoId A Term Repo id
    /// @param termRepoServicer The address of loan manager
    /// @param termAuctionOfferLocker The address of auction offer locker paired through reopening
    /// @param termAuction The address of auction  paired through reopening
    event ReopeningOfferLockerPaired(
        bytes32 termRepoId,
        address termRepoServicer,
        address termAuctionOfferLocker,
        address termAuction
    );

    /// @notice Event emitted when a loan offer is locked.
    /// @param termRepoId A Term Repo id
    /// @param offeror The address who submitted offer
    /// @param amount The amount of purchase token locked for offer
    event OfferLockedByServicer(
        bytes32 termRepoId,
        address offeror,
        uint256 amount
    );

    /// @notice Event emitted when a loan offer is unlocked.
    /// @param termRepoId A Term Repo id
    /// @param offeror The address who submitted offer
    /// @param amount The amount of purchase token unlocked for offer
    event OfferUnlockedByServicer(
        bytes32 termRepoId,
        address offeror,
        uint256 amount
    );

    /// @notice Event emitted when a loan offer is fulfilled.
    /// @param offerId A unique offer id
    /// @param offeror The address whose offer is fulfilled
    /// @param purchasePrice The purchasePrice of loan offer fulfilled
    /// @param repurchasePrice The repurchasePrice of loan offer fulfilled
    /// @param repoTokensMinted The amount of Term Repo Tokens minted to offeror
    event OfferFulfilled(
        bytes32 offerId,
        address offeror,
        uint256 purchasePrice,
        uint256 repurchasePrice,
        uint256 repoTokensMinted
    );

    /// @notice Event emitted when a term repo token is redeemed.
    /// @param termRepoId A Term Repo id
    /// @param redeemer The address who is redeeming term repo tokens
    /// @param redemptionAmount The amount of loan offer redeemed by term repo tokens
    /// @param redemptionHaircut The haircut applied to redemptions (if any) due to unrecoverable repo exposure
    event TermRepoTokensRedeemed(
        bytes32 termRepoId,
        address redeemer,
        uint256 redemptionAmount,
        uint256 redemptionHaircut
    );

    /// @notice Event emitted when a loan is processed to a borrower
    /// @param termRepoId A Term Repo id
    /// @param bidder The address who is receiving the loan
    /// @param purchasePrice The purchasePrice transferred to borrower
    /// @param repurchasePrice The repurchasePrice owed by borrower at maturity
    /// @param servicingFees The protocol fees paid for loan
    event BidFulfilled(
        bytes32 termRepoId,
        address bidder,
        uint256 purchasePrice,
        uint256 repurchasePrice,
        uint256 servicingFees
    );

    /// @notice Event emitted when mint exposure access is granted
    /// @param termRepoId A Term Repo id
    /// @param authedUser User granted mint exposure access
    event MintExposureAccessGranted(bytes32 termRepoId, address authedUser);

    /// @notice Event emitted when a rollover from a previous loan opens a position in this new term
    /// @param termRepoId A Term Repo id
    /// @param borrower The borrower who has loan position opened in new term
    /// @param purchasePrice The purchasePrice transferred to previous term
    /// @param repurchasePrice The repurchasePrice owed by borrower at maturity
    /// @param servicingFees The protocol fees paid for loan
    event ExposureOpenedOnRolloverNew(
        bytes32 termRepoId,
        address borrower,
        uint256 purchasePrice,
        uint256 repurchasePrice,
        uint256 servicingFees
    );

    /// @notice Event emitted when a rollover from a previous loan opens a position in this new term
    /// @param termRepoId A Term Repo id
    /// @param borrower The borrower who has loan position opened in new term
    /// @param amountRolled The amount of borrower loan collapsed by rollover opening
    event ExposureClosedOnRolloverExisting(
        bytes32 termRepoId,
        address borrower,
        uint256 amountRolled
    );

    /// @notice Event emitted when term repo tokens are minted for a loan
    /// @param termRepoId A Term Repo id
    /// @param minter The address who is opening the loan
    /// @param netTokensReceived The amount of Term Repo Tokens received by minter net of servicing fees
    /// @param servicingFeeTokens The number of Term Repo Tokens retained by protocol in servicing fees
    /// @param repurchasePrice The repurchase exposure opened by minter against Term Repo Token mint
    event TermRepoTokenMint(
        bytes32 termRepoId,
        address minter,
        uint256 netTokensReceived,
        uint256 servicingFeeTokens,
        uint256 repurchasePrice
    );

    /// @notice Event emitted when a loan is collapsed by burning term repo tokens
    /// @param termRepoId A Term Repo id
    /// @param borrower The address who is repaying the loan
    /// @param amountToClose The amount repaid by borrower
    event BurnCollapseExposure(
        bytes32 termRepoId,
        address borrower,
        uint256 amountToClose
    );

    /// @notice Event emitted when a loan is repaid by borrower
    /// @param termRepoId A Term Repo id
    /// @param borrower The address who is repaying the loan
    /// @param repurchaseAmount The amount repaid by borrower
    event RepurchasePaymentSubmitted(
        bytes32 termRepoId,
        address borrower,
        uint256 repurchaseAmount
    );
}



// ============================================================
// FILE: contracts/interfaces/ITermRepoTokenEvents.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @notice ITermRepoTokenEvents is an interface that defines all events emitted by the Term Repo Token
interface ITermRepoTokenEvents {
    /// @notice Event emitted when a Term Repo Servicer is initialized.
    /// @param termRepoId term identifier
    /// @param termRepoToken   address of initialized term repo token
    /// @param redemptionRatio The number of purchase tokens redeemable per unit of Term Repo Token at par
    event TermRepoTokenInitialized(
        bytes32 termRepoId,
        address termRepoToken,
        uint256 redemptionRatio
    );

    /// @notice Event emitted when a Term Repo Token Minting is Paused
    /// @param termRepoId A Term Repo id
    event TermRepoTokenMintingPaused(bytes32 termRepoId);

    /// @notice Event emitted when a Term Repo Token Minting is Unpaused
    /// @param termRepoId A Term Repo id
    event TermRepoTokenMintingUnpaused(bytes32 termRepoId);

    /// @notice Event emitted when a Term Repo Token Burning is Paused
    /// @param termRepoId A Term Repo id
    event TermRepoTokenBurningPaused(bytes32 termRepoId);

    /// @notice Event emitted when a Term Repo Token Burning is Unpaused
    /// @param termRepoId A Term Repo id
    event TermRepoTokenBurningUnpaused(bytes32 termRepoId);
}



// ============================================================
// FILE: contracts/lib/AuctionMetadata.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

struct AuctionMetadata {
    bytes32 termAuctionId;
    uint256 auctionClearingRate;
    uint256 auctionClearingBlockTimestamp;
}



// ============================================================
// FILE: contracts/lib/TermAuctionBid.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

/// @dev TermAuctionBid represents a bid to borrow a specific amount of tokens at a specific interest rate (or better)
struct TermAuctionBid {
    /// @dev Unique identifier for this bid
    bytes32 id;
    /// @dev The address of the bidder
    address bidder;
    /// @dev Hash of the offered price as a percentage of the initial loaned amount vs amount returned at maturity. This stores 9 decimal places
    bytes32 bidPriceHash;
    /// @dev Revealed bid price; this is only a valid value if isRevealed is true; this stores 18 decimal places
    uint256 bidPriceRevealed;
    /// @dev The maximum amount of purchase tokens that can be borrowed
    uint256 amount;
    /// @dev The amount of collateral tokens initially locked
    uint256[] collateralAmounts;
    /// @dev The address of the ERC20 purchase token
    address purchaseToken;
    /// @dev The addresses of the collateral ERC20 tokens in the bid
    address[] collateralTokens;
    /// @dev A boolean indicating if bid was submitted as rollover from previous term
    bool isRollover;
    /// @dev The address of term repo servicer whose bid is being rolled over
    address rolloverPairOffTermRepoServicer;
    /// @dev A boolean that is true if bid has been revealed
    bool isRevealed;
}



// ============================================================
// FILE: contracts/libraries/LibTermStorage.sol
// ============================================================
//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import {ITermEventEmitter} from "../interfaces/ITermEventEmitter.sol";
import { ITermIntent } from "../interfaces/ITermIntent.sol";

struct TermStorage {
    // initialization flag for TermIntent
    bool termIntentInitialized;

    // address that initiated multicall
    address multicallInitiator;

    // address of the maker in active settlement context (for retrieveFunds authorization)
    address activeSettlementMaker;

    // address of the atomic transaction sender
    address atomicTxInitiatior;

    // address of the taker in active atomic transaction settlement context
    address activeAtomicTxSettlementTaker;

    // EIP712 domain separator for signing limit orders
    bytes32 eip712DomainSeparator;

    // Global term controller whitelist mapping
    mapping(address => bool) approvedTermControllers;

    // List of approved term controllers for enumeration
    address[] approvedTermControllerList;

    // Approved Fee Recipient Mapping
    mapping(address => bool) approvedFeeRecipients;

    // Global term event emitter
    ITermEventEmitter emitter;

    /// Maps order hash to order execution status and filled amount
    mapping(bytes32 => ITermIntent.OrderContext) limitOrderContextMapping;
    /// Maps order hash to maker address for contract wallets that pre-authorize orders
    mapping(bytes32 => address) preSignedLimitOrders;

    /// Maps order hash to order execution status and filled amount
    mapping(bytes32 => ITermIntent.OrderContext) swapOrderContextMapping;
    /// Maps order hash to maker address for contract wallets that pre-authorize orders
    mapping(bytes32 => address) preSignedSwapOrders;

    /// Maps maker => makerToken => takerToken to minimum valid salt for bulk order cancellation
    mapping(address => mapping(address => mapping(address => uint256))) limitOrderMakerTokenPairMinSalt;
    /// Maps maker => makerToken => takerToken to minimum valid salt for bulk swap order cancellation
    mapping(address => mapping(address => mapping(address => uint256))) swapOrderMakerTokenPairMinSalt;
}

struct TermERC4626VaultManagement {
    mapping(address => mapping(address => bool)) userApprovedERC4626Vaults;
}

struct TermFlashLoanContext {
    // address of the borrower in active flashloan context
    address activeFlashLoanBorrower;
}

library LibTermStorage {

    bytes32 internal constant TERM_STORAGE_POSITION = keccak256("term.storage");
    bytes32 internal constant TERM_ERC4626_VAULT_MANAGEMENT_POSITION = keccak256("term.erc4626.vault.management");
    bytes32 internal constant TERM_FLASH_LOAN_CONTEXT_POSITION = keccak256("term.flash.loan.context");
    address internal constant UNSET_INITIATOR = address(0); 

    function termStorage() internal pure returns (TermStorage storage ts) {
        bytes32 position = TERM_STORAGE_POSITION;
        assembly {
            ts.slot := position
        }
    }

    function termERC4626VaultManagement() internal pure returns (TermERC4626VaultManagement storage tev) {
        bytes32 position = TERM_ERC4626_VAULT_MANAGEMENT_POSITION;
        assembly {
            tev.slot := position
        }
    }

    function termFlashLoanContext() internal pure returns (TermFlashLoanContext storage tfc) {
        bytes32 position = TERM_FLASH_LOAN_CONTEXT_POSITION;
        assembly {
            tfc.slot := position
        }
    }

    // Validation function that can be called from modifiers
    function requireMulticallInitiator() internal view {
        TermStorage storage ts = termStorage();
        address initiator = ts.multicallInitiator;
        require(initiator != UNSET_INITIATOR, "uninitialized");
        require(msg.sender == initiator, "unauthorized");
    }
}
