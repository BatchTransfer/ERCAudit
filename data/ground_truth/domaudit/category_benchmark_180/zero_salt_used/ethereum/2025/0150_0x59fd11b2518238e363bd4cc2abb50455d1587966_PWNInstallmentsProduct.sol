// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x59fd11b2518238e363bd4cc2abb50455d1587966
// Contract Name: PWNInstallmentsProduct



// ============================================================
// FILE: src/periphery/product/PWNInstallmentsProduct.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";
import { LoanTerms as Terms } from "pwn/core/loan/LoanTerms.sol";
import { IPWNProduct } from "pwn/core/product/IPWNProduct.sol";
import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/periphery/lib/Chainlink.sol";
import { PWNRevokedNonce } from "pwn/periphery/auxiliary/PWNRevokedNonce.sol";
import { PWNUtilizedCredit } from "pwn/periphery/auxiliary/PWNUtilizedCredit.sol";


contract PWNInstallmentsProduct is IPWNProduct {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;
    using Math for uint256;
    using SafeCast for uint256;
    using Chainlink for Chainlink.Config;

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    string public constant NAME = "PWN Installments Product";
    string public constant VERSION = "1.5";

    /** @notice The minimum allowed duration (in seconds) for the default period.*/
    uint256 public constant MIN_DURATION = 10 minutes;
    /** @notice Number of decimals for the debt limit tangent precision.*/
    uint256 public constant DEBT_LIMIT_TANGENT_DECIMALS = 8;
    /** @notice Maximum number of intermediary denominations for price conversion.*/
    uint256 public constant MAX_INTERMEDIARY_DENOMINATIONS = 4;
    /** @notice Loan to value decimals (e.g., 6231 = 0.6231 = 62.31%).*/
    uint256 public constant LOAN_TO_VALUE_DECIMALS = 4;
    /** @notice Number of decimals for APR precision (e.g., 6231 = 0.6231 = 62.31%).*/
    uint256 public constant APR_DECIMALS = 4;

    /** @notice PWN Hub contract.*/
    PWNHub public immutable hub;
    /** @notice PWN Revoked Nonce contract.*/
    PWNRevokedNonce public immutable revokedNonce;
    /** @notice PWN Utilized Credit contract.*/
    PWNUtilizedCredit public immutable utilizedCredit;

    /** @dev Chainlink configuration struct for price feed operations.*/
    Chainlink.Config internal _chainlink;

    /** @dev EIP-712 domain separator for proposal contracts.*/
    bytes32 public immutable DOMAIN_SEPARATOR;
    /** @dev EIP-712 proposal type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(address collateralAddress,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 loanToValue,uint256 interestAPR,uint256 postponement,uint256 duration,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"
    );

    /**
     * @notice Struct representing a stable interest loan proposal.
     * @dev Contains all parameters required to define a loan proposal, including collateral, credit, interest, and proposal metadata.
     * @param collateralAddress The address of the collateral asset.
     * @param creditAddress The address of the credit asset (loan currency).
     * @param feedIntermediaryDenominations Array of intermediary denominations for price feed routing.
     * @param feedInvertFlags Array of flags indicating if the price feed should be inverted for each denomination.
     * @param acceptableLoanToValue The acceptable loan-to-value ratio (LTV), expressed in basis points (1e4 = 100%). For lender, it's the maxium acceptable LTV, for borrower it's the LTV they are willing to accept.
     * @param interestAPR The annual percentage rate (APR) for the loan interest, expressed in basis points (1e4 = 100%).
     * @param postponement The period (in seconds) before the debt limit starts decreasing.
     * @param duration The duration of the loan in seconds, after which it is considered defaulted if not repaid.
     * @param minCreditAmount The minimum amount of credit (loan) that can be drawn.
     * @param availableCreditLimit The total available credit limit for the proposal.
     * @param utilizedCreditId Identifier for utilized credit, if any.
     * @param nonceSpace Nonce space for replay protection.
     * @param nonce Nonce for replay protection.
     * @param expiration Expiration timestamp of the proposal.
     * @param proposerSpecHash Hash of proposer-specific data.
     * @param isProposerLender Boolean indicating if the proposer is the lender.
     * @param loanContract The address of the loan contract to be used.
     */
    struct Proposal {
        // Collateral
        address collateralAddress;
        // Credit
        address creditAddress;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
        uint256 loanToValue;
        // Interest
        uint256 interestAPR;
        // Default
        uint256 postponement;
        uint256 duration;
        // Proposal validity
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 expiration;
        // General proposal
        bytes32 proposerSpecHash;
        bool isProposerLender;
        address loanContract;
    }

    /**
     * @notice Construct defining values provided by an acceptor.
     * @param creditAmount Amount of credit to be borrowed.
     */
    struct AcceptorValues {
        uint256 creditAmount;
    }

    /**
     * @notice Struct containing loan data for interest, default, and liquidation logic.
     * @param apr Annual Percentage Rate (APR) for interest calculation, scaled by APR_DECIMALS.
     * @param defaultTimestamp Timestamp when the loan is considered defaulted.
     * @param debtLimitTangent The tangent (slope) of the linearly decreasing debt limit.
     */
    struct LoanData {
        uint40 apr;
        uint40 defaultTimestamp;
        uint176 debtLimitTangent;
    }

    /** @notice Mapping of loan contract and loan id to loan data for interest, default, and liquidation logic.*/
    mapping (address => mapping(uint256 => LoanData)) public loanData;


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when a proposal is expired.*/
    error Expired(uint256 current, uint256 expiration);
    /** @notice Thrown when a caller is missing a required hub tag.*/
    error CallerNotLoanContract(address caller, address loanContract);
    /** @notice Thrown when proposal has no minimum credit amount set.*/
    error MinCreditAmountNotSet();
    /** @notice Thrown when proposal credit amount is insufficient.*/
    error InsufficientCreditAmount(uint256 current, uint256 limit);
    /** @notice Thrown when the loan to value is above 1.0.*/
    error InvalidLoanToValue();
    /** @notice Thrown when the liquidation data is not empty.*/
    error LiquidationDataNotEmpty();
    /** @notice Thrown when liquidated loan is not initialized in this module.*/
    error LoanNotInitialized();
    /** @notice Thrown when the duration is less than the minimum allowed duration.*/
    error DurationTooShort();
    /** @notice Thrown when the postponement is greater than the duration.*/
    error PostponementBiggerThanDuration();
    /** @notice Thrown when loan to value is zero.*/
    error LoanToValueZero();
    /** @notice Thrown when the liquidator is not the LOAN token owner.*/
    error LiquidatorNotLoanOwner(address owner, address liquidator, address loanContract, uint256 loanId);



    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        PWNHub _hub,
        PWNRevokedNonce _revokedNonce,
        PWNUtilizedCredit _utilizedCredit,
        IChainlinkFeedRegistryLike _chainlinkFeedRegistry,
        IChainlinkAggregatorLike _chainlinkL2SequencerUptimeFeed,
        address _weth
    ) {
        hub = PWNHub(_hub);
        revokedNonce = PWNRevokedNonce(_revokedNonce);
        utilizedCredit = PWNUtilizedCredit(_utilizedCredit);
        _chainlink.l2SequencerUptimeFeed = _chainlinkL2SequencerUptimeFeed;
        _chainlink.feedRegistry = _chainlinkFeedRegistry;
        _chainlink.maxIntermediaryDenominations = MAX_INTERMEDIARY_DENOMINATIONS;
        _chainlink.weth = _weth;

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(abi.encodePacked(NAME)),
            keccak256(abi.encodePacked(VERSION)),
            block.chainid,
            address(this)
        ));
    }


    /*----------------------------------------------------------*|
    |*  # COLLATERAL AMOUNT                                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Calculates the required collateral amount for a given position.
     * @dev This function determines how much collateral is needed based on the product's parameters.
     * Feed direction is from credit denominator to collateral denominator.
     * @param creditAddress The address of the credit token.
     * @param creditAmount The amount of credit to be used in the calculation.
     * @param collateralAddress The address of the collateral token.
     * @param feedIntermediaryDenominations An array of intermediary token addresses used for multi-hop price feed conversions.
     * @param feedInvertFlags An array of boolean flags indicating if each corresponding price feed should be inverted.
     * @param loanToValue The loan-to-value ratio, scaled by LOAN_TO_VALUE_DECIMALS. This is the ratio of the loan amount to the collateral value.
     * @return The amount of collateral required.
     */
    function getCollateralAmount(
        address creditAddress,
        uint256 creditAmount,
        address collateralAddress,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags,
        uint256 loanToValue
    ) public view returns (uint256) {
        if (loanToValue == 0) revert LoanToValueZero();
        // throws if returned price from chainlink pracle is negative or zero
        return _chainlink.convertDenomination({
            amount: creditAmount,
            oldDenomination: creditAddress,
            newDenomination: collateralAddress,
            feedIntermediaryDenominations: feedIntermediaryDenominations,
            feedInvertFlags: feedInvertFlags
        }).mulDiv(10 ** LOAN_TO_VALUE_DECIMALS, loanToValue);
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL                                              *|
    |*----------------------------------------------------------*/

    function acceptProposal(
        uint256 loanId,
        address /* acceptor */,
        address proposer,
        bytes calldata proposalData
    ) external returns (Terms memory loanTerms) {
        // Decode proposal data
        (Proposal memory proposal, AcceptorValues memory acceptorValues) = decodeProposalData(proposalData);

        // Check loan contract
        if (msg.sender != proposal.loanContract) {
            revert CallerNotLoanContract({ caller: msg.sender, loanContract: proposal.loanContract });
        }
        if (!hub.hasTag(proposal.loanContract, PWNHubTags.ACTIVE_LOAN)) {
            revert AddressMissingHubTag({ addr: proposal.loanContract, tag: PWNHubTags.ACTIVE_LOAN });
        }

        // Check proposal is not expired
        if (block.timestamp >= proposal.expiration) {
            revert Expired({ current: block.timestamp, expiration: proposal.expiration });
        }

        if (proposal.loanToValue == 0) {
            // If LTV is zero, it is invalid
            revert InvalidLoanToValue();
        } else if (proposal.loanToValue > 10 ** LOAN_TO_VALUE_DECIMALS) {
            // If LTV is above 1.0, it is invalid
            revert InvalidLoanToValue();
        }

        // Check duration
        if (proposal.duration < MIN_DURATION) {
            revert DurationTooShort();
        }

        // TODO should here be >= or just >
        if (proposal.postponement >= proposal.duration) {
            revert PostponementBiggerThanDuration();
        }

        // Check min credit amount
        if (proposal.minCreditAmount == 0) {
            revert MinCreditAmountNotSet();
        }

        // Check sufficient credit amount
        if (acceptorValues.creditAmount < proposal.minCreditAmount) {
            revert InsufficientCreditAmount({ current: acceptorValues.creditAmount, limit: proposal.minCreditAmount });
        }

        // Check proposal is not revoked
        if (!revokedNonce.isNonceUsable(proposer, proposal.nonceSpace, proposal.nonce)) {
            revert PWNRevokedNonce.NonceNotUsable({
                addr: proposer,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce
            });
        }

        // Compute collateral amount required for the loan
        uint256 collateralAmount = getCollateralAmount(
            proposal.creditAddress,
            acceptorValues.creditAmount,
            proposal.collateralAddress,
            proposal.feedIntermediaryDenominations,
            proposal.feedInvertFlags,
            proposal.loanToValue
        );

        if (proposal.availableCreditLimit == 0) {
            // Revoke nonce if credit limit is 0, proposal can be accepted only once
            revokedNonce.revokeNonce(proposer, proposal.nonceSpace, proposal.nonce);
        } else {
            // Update utilized credit
            // Note: This will revert if utilized credit would exceed the available credit limit
            utilizedCredit.utilizeCredit(proposer, proposal.utilizedCreditId, acceptorValues.creditAmount, proposal.availableCreditLimit);
        }

        // Store data for the loan interest, default, and liquidation modules
        loanData[msg.sender][loanId] = LoanData({
            apr: proposal.interestAPR.toUint40(),
            defaultTimestamp: (block.timestamp + proposal.duration).toUint40(),
            debtLimitTangent: acceptorValues.creditAmount.mulDiv(10 ** DEBT_LIMIT_TANGENT_DECIMALS, proposal.duration - proposal.postponement).toUint176()
        });

        // Create loan terms object
        return Terms({
            isProposerLender: proposal.isProposerLender,
            proposerSpecHash: proposal.proposerSpecHash,
            collateral: proposal.collateralAddress.ERC20(collateralAmount),
            creditAddress: proposal.creditAddress,
            principal: acceptorValues.creditAmount
        });
    }

    function nameAndVersion() external pure returns (string memory name, string memory version) {
        return (NAME, VERSION);
    }

    function hashProposalTypedData(bytes calldata proposalData) external pure returns (bytes32) {
        Proposal memory proposal = abi.decode(proposalData, (Proposal));
        return keccak256(abi.encodePacked(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal)));
    }


    /*----------------------------------------------------------*|
    |*  # INTEREST                                              *|
    |*----------------------------------------------------------*/

    function interest(address loanContract, uint256 loanId) external view returns (uint256) {
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        if (block.timestamp < loan.lastUpdateTimestamp) return 0;

        return loan.principal.mulDiv(
            uint256(loanData[loanContract][loanId].apr).mulDiv(block.timestamp - loan.lastUpdateTimestamp, 365 days),
            10 ** APR_DECIMALS
        );
    }


    /*----------------------------------------------------------*|
    |*  # DEFAULT                                               *|
    |*----------------------------------------------------------*/

    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool) {
        return PWNLoan(loanContract).getLOANDebt(loanId) > getDefaultDebtLimit(loanContract, loanId, 0);
    }

    /**
     * @notice Return a default debt limit value.
     * @dev The default debt limit is a linear decreasing function of the total debt from the original debt amount
     * at the time of loan creation postponed by `DEBT_LIMIT_POSTPONEMENT` to 0 at the default timestamp.
     * @param loanId Id of a loan.
     * @param timestamp Timestamp to calculate the default debt limit. Use 0 for the current timestamp.
     * @return Default debt limit.
     */
    function getDefaultDebtLimit(address loanContract, uint256 loanId, uint256 timestamp) public view returns (uint256) {
        LoanData storage data = loanData[loanContract][loanId];

        timestamp = timestamp == 0 ? block.timestamp : timestamp;
        if (timestamp >= data.defaultTimestamp) {
            return 0;
        }

        return Math.mulDiv(
            uint256(data.debtLimitTangent), uint256(data.defaultTimestamp) - timestamp,
            10 ** DEBT_LIMIT_TANGENT_DECIMALS
        );
    }


    /*----------------------------------------------------------*|
    |*  # LIQUIDATION                                           *|
    |*----------------------------------------------------------*/

    function liquidate(
        uint256 loanId,
        address liquidator,
        address /* borrower */,
        uint256 /* debt */,
        address /* creditAddress */,
        MultiToken.Asset calldata collateral,
        bytes calldata liquidationData
    ) external returns (uint256 liquidationAmount) {
        if (liquidationData.length != 0) revert LiquidationDataNotEmpty();

        LoanData memory data = loanData[msg.sender][loanId];
        if (data.defaultTimestamp == 0) revert LoanNotInitialized();

        address loanOwner = PWNLoan(msg.sender).loanToken().ownerOf(loanId);
        if (loanOwner != liquidator) revert LiquidatorNotLoanOwner(loanOwner, liquidator, msg.sender, loanId);

        // Transfer collateral to liquidator
        collateral.transferAssetFrom(address(this), loanOwner);

        return 0;
    }


    /*----------------------------------------------------------*|
    |*  # EN/DECODE                                             *|
    |*----------------------------------------------------------*/

    /**
     * @notice Encode proposal data.
     * @param proposal Proposal struct to be encoded.
     * @param acceptorValues Acceptor values struct to be encoded.
     * @return Encoded proposal data.
     */
    function encodeProposalData(
        Proposal memory proposal,
        AcceptorValues memory acceptorValues
    ) external pure returns (bytes memory) {
        return abi.encode(proposal, acceptorValues);
    }

    /**
     * @notice Decode proposal data.
     * @param proposalData Encoded proposal data.
     * @return Decoded proposal struct.
     * @return Decoded acceptor values struct.
     */
    function decodeProposalData(bytes memory proposalData) public pure returns (Proposal memory, AcceptorValues memory) {
        return abi.decode(proposalData, (Proposal, AcceptorValues));
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    /** @notice Proposal struct that is typecasting dynamic values to bytes32 to enable easy EIP-712 encoding.*/
    struct ERC712Proposal {
        address collateralAddress;
        address creditAddress;
        bytes32 feedIntermediaryDenominationsHash;
        bytes32 feedInvertFlagsHash;
        uint256 loanToValue;
        uint256 interestAPR;
        uint256 postponement;
        uint256 duration;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 expiration;
        bytes32 proposerSpecHash;
        bool isProposerLender;
        address loanContract;
    }

    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        ERC712Proposal memory erc712Proposal = ERC712Proposal({
            collateralAddress: proposal.collateralAddress,
            creditAddress: proposal.creditAddress,
            feedIntermediaryDenominationsHash: keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            feedInvertFlagsHash: keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            loanToValue: proposal.loanToValue,
            interestAPR: proposal.interestAPR,
            postponement: proposal.postponement,
            duration: proposal.duration,
            minCreditAmount: proposal.minCreditAmount,
            availableCreditLimit: proposal.availableCreditLimit,
            utilizedCreditId: proposal.utilizedCreditId,
            nonceSpace: proposal.nonceSpace,
            nonce: proposal.nonce,
            expiration: proposal.expiration,
            proposerSpecHash: proposal.proposerSpecHash,
            isProposerLender: proposal.isProposerLender,
            loanContract: proposal.loanContract
        });
        return abi.encode(erc712Proposal);
    }

}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/math/Math.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/math/Math.sol)

pragma solidity ^0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv)
     * with further edits by Uniswap Labs also under MIT license.
     */
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

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
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

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
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

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded down.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (rounding == Rounding.Up && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (rounding == Rounding.Up && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (rounding == Rounding.Up && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256, rounded down, of a positive value.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (rounding == Rounding.Up && 1 << (result << 3) < value ? 1 : 0);
        }
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/SafeCast.sol)
// This file was procedurally generated from scripts/generate/templates/SafeCast.js.

pragma solidity ^0.8.0;

/**
 * @dev Wrappers over Solidity's uintXX/intXX casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256/int256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 *
 * Can be combined with {SafeMath} and {SignedSafeMath} to extend it to smaller types, by performing
 * all math on `uint256` and `int256` and then downcasting.
 */
library SafeCast {
    /**
     * @dev Returns the downcasted uint248 from uint256, reverting on
     * overflow (when the input is greater than largest uint248).
     *
     * Counterpart to Solidity's `uint248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     *
     * _Available since v4.7._
     */
    function toUint248(uint256 value) internal pure returns (uint248) {
        require(value <= type(uint248).max, "SafeCast: value doesn't fit in 248 bits");
        return uint248(value);
    }

    /**
     * @dev Returns the downcasted uint240 from uint256, reverting on
     * overflow (when the input is greater than largest uint240).
     *
     * Counterpart to Solidity's `uint240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     *
     * _Available since v4.7._
     */
    function toUint240(uint256 value) internal pure returns (uint240) {
        require(value <= type(uint240).max, "SafeCast: value doesn't fit in 240 bits");
        return uint240(value);
    }

    /**
     * @dev Returns the downcasted uint232 from uint256, reverting on
     * overflow (when the input is greater than largest uint232).
     *
     * Counterpart to Solidity's `uint232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     *
     * _Available since v4.7._
     */
    function toUint232(uint256 value) internal pure returns (uint232) {
        require(value <= type(uint232).max, "SafeCast: value doesn't fit in 232 bits");
        return uint232(value);
    }

    /**
     * @dev Returns the downcasted uint224 from uint256, reverting on
     * overflow (when the input is greater than largest uint224).
     *
     * Counterpart to Solidity's `uint224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     *
     * _Available since v4.2._
     */
    function toUint224(uint256 value) internal pure returns (uint224) {
        require(value <= type(uint224).max, "SafeCast: value doesn't fit in 224 bits");
        return uint224(value);
    }

    /**
     * @dev Returns the downcasted uint216 from uint256, reverting on
     * overflow (when the input is greater than largest uint216).
     *
     * Counterpart to Solidity's `uint216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     *
     * _Available since v4.7._
     */
    function toUint216(uint256 value) internal pure returns (uint216) {
        require(value <= type(uint216).max, "SafeCast: value doesn't fit in 216 bits");
        return uint216(value);
    }

    /**
     * @dev Returns the downcasted uint208 from uint256, reverting on
     * overflow (when the input is greater than largest uint208).
     *
     * Counterpart to Solidity's `uint208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     *
     * _Available since v4.7._
     */
    function toUint208(uint256 value) internal pure returns (uint208) {
        require(value <= type(uint208).max, "SafeCast: value doesn't fit in 208 bits");
        return uint208(value);
    }

    /**
     * @dev Returns the downcasted uint200 from uint256, reverting on
     * overflow (when the input is greater than largest uint200).
     *
     * Counterpart to Solidity's `uint200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     *
     * _Available since v4.7._
     */
    function toUint200(uint256 value) internal pure returns (uint200) {
        require(value <= type(uint200).max, "SafeCast: value doesn't fit in 200 bits");
        return uint200(value);
    }

    /**
     * @dev Returns the downcasted uint192 from uint256, reverting on
     * overflow (when the input is greater than largest uint192).
     *
     * Counterpart to Solidity's `uint192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     *
     * _Available since v4.7._
     */
    function toUint192(uint256 value) internal pure returns (uint192) {
        require(value <= type(uint192).max, "SafeCast: value doesn't fit in 192 bits");
        return uint192(value);
    }

    /**
     * @dev Returns the downcasted uint184 from uint256, reverting on
     * overflow (when the input is greater than largest uint184).
     *
     * Counterpart to Solidity's `uint184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     *
     * _Available since v4.7._
     */
    function toUint184(uint256 value) internal pure returns (uint184) {
        require(value <= type(uint184).max, "SafeCast: value doesn't fit in 184 bits");
        return uint184(value);
    }

    /**
     * @dev Returns the downcasted uint176 from uint256, reverting on
     * overflow (when the input is greater than largest uint176).
     *
     * Counterpart to Solidity's `uint176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     *
     * _Available since v4.7._
     */
    function toUint176(uint256 value) internal pure returns (uint176) {
        require(value <= type(uint176).max, "SafeCast: value doesn't fit in 176 bits");
        return uint176(value);
    }

    /**
     * @dev Returns the downcasted uint168 from uint256, reverting on
     * overflow (when the input is greater than largest uint168).
     *
     * Counterpart to Solidity's `uint168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     *
     * _Available since v4.7._
     */
    function toUint168(uint256 value) internal pure returns (uint168) {
        require(value <= type(uint168).max, "SafeCast: value doesn't fit in 168 bits");
        return uint168(value);
    }

    /**
     * @dev Returns the downcasted uint160 from uint256, reverting on
     * overflow (when the input is greater than largest uint160).
     *
     * Counterpart to Solidity's `uint160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     *
     * _Available since v4.7._
     */
    function toUint160(uint256 value) internal pure returns (uint160) {
        require(value <= type(uint160).max, "SafeCast: value doesn't fit in 160 bits");
        return uint160(value);
    }

    /**
     * @dev Returns the downcasted uint152 from uint256, reverting on
     * overflow (when the input is greater than largest uint152).
     *
     * Counterpart to Solidity's `uint152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     *
     * _Available since v4.7._
     */
    function toUint152(uint256 value) internal pure returns (uint152) {
        require(value <= type(uint152).max, "SafeCast: value doesn't fit in 152 bits");
        return uint152(value);
    }

    /**
     * @dev Returns the downcasted uint144 from uint256, reverting on
     * overflow (when the input is greater than largest uint144).
     *
     * Counterpart to Solidity's `uint144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     *
     * _Available since v4.7._
     */
    function toUint144(uint256 value) internal pure returns (uint144) {
        require(value <= type(uint144).max, "SafeCast: value doesn't fit in 144 bits");
        return uint144(value);
    }

    /**
     * @dev Returns the downcasted uint136 from uint256, reverting on
     * overflow (when the input is greater than largest uint136).
     *
     * Counterpart to Solidity's `uint136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     *
     * _Available since v4.7._
     */
    function toUint136(uint256 value) internal pure returns (uint136) {
        require(value <= type(uint136).max, "SafeCast: value doesn't fit in 136 bits");
        return uint136(value);
    }

    /**
     * @dev Returns the downcasted uint128 from uint256, reverting on
     * overflow (when the input is greater than largest uint128).
     *
     * Counterpart to Solidity's `uint128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v2.5._
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }

    /**
     * @dev Returns the downcasted uint120 from uint256, reverting on
     * overflow (when the input is greater than largest uint120).
     *
     * Counterpart to Solidity's `uint120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     *
     * _Available since v4.7._
     */
    function toUint120(uint256 value) internal pure returns (uint120) {
        require(value <= type(uint120).max, "SafeCast: value doesn't fit in 120 bits");
        return uint120(value);
    }

    /**
     * @dev Returns the downcasted uint112 from uint256, reverting on
     * overflow (when the input is greater than largest uint112).
     *
     * Counterpart to Solidity's `uint112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     *
     * _Available since v4.7._
     */
    function toUint112(uint256 value) internal pure returns (uint112) {
        require(value <= type(uint112).max, "SafeCast: value doesn't fit in 112 bits");
        return uint112(value);
    }

    /**
     * @dev Returns the downcasted uint104 from uint256, reverting on
     * overflow (when the input is greater than largest uint104).
     *
     * Counterpart to Solidity's `uint104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     *
     * _Available since v4.7._
     */
    function toUint104(uint256 value) internal pure returns (uint104) {
        require(value <= type(uint104).max, "SafeCast: value doesn't fit in 104 bits");
        return uint104(value);
    }

    /**
     * @dev Returns the downcasted uint96 from uint256, reverting on
     * overflow (when the input is greater than largest uint96).
     *
     * Counterpart to Solidity's `uint96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     *
     * _Available since v4.2._
     */
    function toUint96(uint256 value) internal pure returns (uint96) {
        require(value <= type(uint96).max, "SafeCast: value doesn't fit in 96 bits");
        return uint96(value);
    }

    /**
     * @dev Returns the downcasted uint88 from uint256, reverting on
     * overflow (when the input is greater than largest uint88).
     *
     * Counterpart to Solidity's `uint88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     *
     * _Available since v4.7._
     */
    function toUint88(uint256 value) internal pure returns (uint88) {
        require(value <= type(uint88).max, "SafeCast: value doesn't fit in 88 bits");
        return uint88(value);
    }

    /**
     * @dev Returns the downcasted uint80 from uint256, reverting on
     * overflow (when the input is greater than largest uint80).
     *
     * Counterpart to Solidity's `uint80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     *
     * _Available since v4.7._
     */
    function toUint80(uint256 value) internal pure returns (uint80) {
        require(value <= type(uint80).max, "SafeCast: value doesn't fit in 80 bits");
        return uint80(value);
    }

    /**
     * @dev Returns the downcasted uint72 from uint256, reverting on
     * overflow (when the input is greater than largest uint72).
     *
     * Counterpart to Solidity's `uint72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     *
     * _Available since v4.7._
     */
    function toUint72(uint256 value) internal pure returns (uint72) {
        require(value <= type(uint72).max, "SafeCast: value doesn't fit in 72 bits");
        return uint72(value);
    }

    /**
     * @dev Returns the downcasted uint64 from uint256, reverting on
     * overflow (when the input is greater than largest uint64).
     *
     * Counterpart to Solidity's `uint64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     *
     * _Available since v2.5._
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        require(value <= type(uint64).max, "SafeCast: value doesn't fit in 64 bits");
        return uint64(value);
    }

    /**
     * @dev Returns the downcasted uint56 from uint256, reverting on
     * overflow (when the input is greater than largest uint56).
     *
     * Counterpart to Solidity's `uint56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     *
     * _Available since v4.7._
     */
    function toUint56(uint256 value) internal pure returns (uint56) {
        require(value <= type(uint56).max, "SafeCast: value doesn't fit in 56 bits");
        return uint56(value);
    }

    /**
     * @dev Returns the downcasted uint48 from uint256, reverting on
     * overflow (when the input is greater than largest uint48).
     *
     * Counterpart to Solidity's `uint48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     *
     * _Available since v4.7._
     */
    function toUint48(uint256 value) internal pure returns (uint48) {
        require(value <= type(uint48).max, "SafeCast: value doesn't fit in 48 bits");
        return uint48(value);
    }

    /**
     * @dev Returns the downcasted uint40 from uint256, reverting on
     * overflow (when the input is greater than largest uint40).
     *
     * Counterpart to Solidity's `uint40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     *
     * _Available since v4.7._
     */
    function toUint40(uint256 value) internal pure returns (uint40) {
        require(value <= type(uint40).max, "SafeCast: value doesn't fit in 40 bits");
        return uint40(value);
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     *
     * _Available since v2.5._
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        require(value <= type(uint32).max, "SafeCast: value doesn't fit in 32 bits");
        return uint32(value);
    }

    /**
     * @dev Returns the downcasted uint24 from uint256, reverting on
     * overflow (when the input is greater than largest uint24).
     *
     * Counterpart to Solidity's `uint24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     *
     * _Available since v4.7._
     */
    function toUint24(uint256 value) internal pure returns (uint24) {
        require(value <= type(uint24).max, "SafeCast: value doesn't fit in 24 bits");
        return uint24(value);
    }

    /**
     * @dev Returns the downcasted uint16 from uint256, reverting on
     * overflow (when the input is greater than largest uint16).
     *
     * Counterpart to Solidity's `uint16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     *
     * _Available since v2.5._
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        require(value <= type(uint16).max, "SafeCast: value doesn't fit in 16 bits");
        return uint16(value);
    }

    /**
     * @dev Returns the downcasted uint8 from uint256, reverting on
     * overflow (when the input is greater than largest uint8).
     *
     * Counterpart to Solidity's `uint8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     *
     * _Available since v2.5._
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        require(value <= type(uint8).max, "SafeCast: value doesn't fit in 8 bits");
        return uint8(value);
    }

    /**
     * @dev Converts a signed int256 into an unsigned uint256.
     *
     * Requirements:
     *
     * - input must be greater than or equal to 0.
     *
     * _Available since v3.0._
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "SafeCast: value must be positive");
        return uint256(value);
    }

    /**
     * @dev Returns the downcasted int248 from int256, reverting on
     * overflow (when the input is less than smallest int248 or
     * greater than largest int248).
     *
     * Counterpart to Solidity's `int248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     *
     * _Available since v4.7._
     */
    function toInt248(int256 value) internal pure returns (int248 downcasted) {
        downcasted = int248(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 248 bits");
    }

    /**
     * @dev Returns the downcasted int240 from int256, reverting on
     * overflow (when the input is less than smallest int240 or
     * greater than largest int240).
     *
     * Counterpart to Solidity's `int240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     *
     * _Available since v4.7._
     */
    function toInt240(int256 value) internal pure returns (int240 downcasted) {
        downcasted = int240(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 240 bits");
    }

    /**
     * @dev Returns the downcasted int232 from int256, reverting on
     * overflow (when the input is less than smallest int232 or
     * greater than largest int232).
     *
     * Counterpart to Solidity's `int232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     *
     * _Available since v4.7._
     */
    function toInt232(int256 value) internal pure returns (int232 downcasted) {
        downcasted = int232(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 232 bits");
    }

    /**
     * @dev Returns the downcasted int224 from int256, reverting on
     * overflow (when the input is less than smallest int224 or
     * greater than largest int224).
     *
     * Counterpart to Solidity's `int224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     *
     * _Available since v4.7._
     */
    function toInt224(int256 value) internal pure returns (int224 downcasted) {
        downcasted = int224(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 224 bits");
    }

    /**
     * @dev Returns the downcasted int216 from int256, reverting on
     * overflow (when the input is less than smallest int216 or
     * greater than largest int216).
     *
     * Counterpart to Solidity's `int216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     *
     * _Available since v4.7._
     */
    function toInt216(int256 value) internal pure returns (int216 downcasted) {
        downcasted = int216(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 216 bits");
    }

    /**
     * @dev Returns the downcasted int208 from int256, reverting on
     * overflow (when the input is less than smallest int208 or
     * greater than largest int208).
     *
     * Counterpart to Solidity's `int208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     *
     * _Available since v4.7._
     */
    function toInt208(int256 value) internal pure returns (int208 downcasted) {
        downcasted = int208(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 208 bits");
    }

    /**
     * @dev Returns the downcasted int200 from int256, reverting on
     * overflow (when the input is less than smallest int200 or
     * greater than largest int200).
     *
     * Counterpart to Solidity's `int200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     *
     * _Available since v4.7._
     */
    function toInt200(int256 value) internal pure returns (int200 downcasted) {
        downcasted = int200(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 200 bits");
    }

    /**
     * @dev Returns the downcasted int192 from int256, reverting on
     * overflow (when the input is less than smallest int192 or
     * greater than largest int192).
     *
     * Counterpart to Solidity's `int192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     *
     * _Available since v4.7._
     */
    function toInt192(int256 value) internal pure returns (int192 downcasted) {
        downcasted = int192(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 192 bits");
    }

    /**
     * @dev Returns the downcasted int184 from int256, reverting on
     * overflow (when the input is less than smallest int184 or
     * greater than largest int184).
     *
     * Counterpart to Solidity's `int184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     *
     * _Available since v4.7._
     */
    function toInt184(int256 value) internal pure returns (int184 downcasted) {
        downcasted = int184(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 184 bits");
    }

    /**
     * @dev Returns the downcasted int176 from int256, reverting on
     * overflow (when the input is less than smallest int176 or
     * greater than largest int176).
     *
     * Counterpart to Solidity's `int176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     *
     * _Available since v4.7._
     */
    function toInt176(int256 value) internal pure returns (int176 downcasted) {
        downcasted = int176(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 176 bits");
    }

    /**
     * @dev Returns the downcasted int168 from int256, reverting on
     * overflow (when the input is less than smallest int168 or
     * greater than largest int168).
     *
     * Counterpart to Solidity's `int168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     *
     * _Available since v4.7._
     */
    function toInt168(int256 value) internal pure returns (int168 downcasted) {
        downcasted = int168(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 168 bits");
    }

    /**
     * @dev Returns the downcasted int160 from int256, reverting on
     * overflow (when the input is less than smallest int160 or
     * greater than largest int160).
     *
     * Counterpart to Solidity's `int160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     *
     * _Available since v4.7._
     */
    function toInt160(int256 value) internal pure returns (int160 downcasted) {
        downcasted = int160(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 160 bits");
    }

    /**
     * @dev Returns the downcasted int152 from int256, reverting on
     * overflow (when the input is less than smallest int152 or
     * greater than largest int152).
     *
     * Counterpart to Solidity's `int152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     *
     * _Available since v4.7._
     */
    function toInt152(int256 value) internal pure returns (int152 downcasted) {
        downcasted = int152(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 152 bits");
    }

    /**
     * @dev Returns the downcasted int144 from int256, reverting on
     * overflow (when the input is less than smallest int144 or
     * greater than largest int144).
     *
     * Counterpart to Solidity's `int144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     *
     * _Available since v4.7._
     */
    function toInt144(int256 value) internal pure returns (int144 downcasted) {
        downcasted = int144(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 144 bits");
    }

    /**
     * @dev Returns the downcasted int136 from int256, reverting on
     * overflow (when the input is less than smallest int136 or
     * greater than largest int136).
     *
     * Counterpart to Solidity's `int136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     *
     * _Available since v4.7._
     */
    function toInt136(int256 value) internal pure returns (int136 downcasted) {
        downcasted = int136(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 136 bits");
    }

    /**
     * @dev Returns the downcasted int128 from int256, reverting on
     * overflow (when the input is less than smallest int128 or
     * greater than largest int128).
     *
     * Counterpart to Solidity's `int128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v3.1._
     */
    function toInt128(int256 value) internal pure returns (int128 downcasted) {
        downcasted = int128(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 128 bits");
    }

    /**
     * @dev Returns the downcasted int120 from int256, reverting on
     * overflow (when the input is less than smallest int120 or
     * greater than largest int120).
     *
     * Counterpart to Solidity's `int120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     *
     * _Available since v4.7._
     */
    function toInt120(int256 value) internal pure returns (int120 downcasted) {
        downcasted = int120(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 120 bits");
    }

    /**
     * @dev Returns the downcasted int112 from int256, reverting on
     * overflow (when the input is less than smallest int112 or
     * greater than largest int112).
     *
     * Counterpart to Solidity's `int112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     *
     * _Available since v4.7._
     */
    function toInt112(int256 value) internal pure returns (int112 downcasted) {
        downcasted = int112(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 112 bits");
    }

    /**
     * @dev Returns the downcasted int104 from int256, reverting on
     * overflow (when the input is less than smallest int104 or
     * greater than largest int104).
     *
     * Counterpart to Solidity's `int104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     *
     * _Available since v4.7._
     */
    function toInt104(int256 value) internal pure returns (int104 downcasted) {
        downcasted = int104(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 104 bits");
    }

    /**
     * @dev Returns the downcasted int96 from int256, reverting on
     * overflow (when the input is less than smallest int96 or
     * greater than largest int96).
     *
     * Counterpart to Solidity's `int96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     *
     * _Available since v4.7._
     */
    function toInt96(int256 value) internal pure returns (int96 downcasted) {
        downcasted = int96(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 96 bits");
    }

    /**
     * @dev Returns the downcasted int88 from int256, reverting on
     * overflow (when the input is less than smallest int88 or
     * greater than largest int88).
     *
     * Counterpart to Solidity's `int88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     *
     * _Available since v4.7._
     */
    function toInt88(int256 value) internal pure returns (int88 downcasted) {
        downcasted = int88(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 88 bits");
    }

    /**
     * @dev Returns the downcasted int80 from int256, reverting on
     * overflow (when the input is less than smallest int80 or
     * greater than largest int80).
     *
     * Counterpart to Solidity's `int80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     *
     * _Available since v4.7._
     */
    function toInt80(int256 value) internal pure returns (int80 downcasted) {
        downcasted = int80(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 80 bits");
    }

    /**
     * @dev Returns the downcasted int72 from int256, reverting on
     * overflow (when the input is less than smallest int72 or
     * greater than largest int72).
     *
     * Counterpart to Solidity's `int72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     *
     * _Available since v4.7._
     */
    function toInt72(int256 value) internal pure returns (int72 downcasted) {
        downcasted = int72(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 72 bits");
    }

    /**
     * @dev Returns the downcasted int64 from int256, reverting on
     * overflow (when the input is less than smallest int64 or
     * greater than largest int64).
     *
     * Counterpart to Solidity's `int64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     *
     * _Available since v3.1._
     */
    function toInt64(int256 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 64 bits");
    }

    /**
     * @dev Returns the downcasted int56 from int256, reverting on
     * overflow (when the input is less than smallest int56 or
     * greater than largest int56).
     *
     * Counterpart to Solidity's `int56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     *
     * _Available since v4.7._
     */
    function toInt56(int256 value) internal pure returns (int56 downcasted) {
        downcasted = int56(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 56 bits");
    }

    /**
     * @dev Returns the downcasted int48 from int256, reverting on
     * overflow (when the input is less than smallest int48 or
     * greater than largest int48).
     *
     * Counterpart to Solidity's `int48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     *
     * _Available since v4.7._
     */
    function toInt48(int256 value) internal pure returns (int48 downcasted) {
        downcasted = int48(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 48 bits");
    }

    /**
     * @dev Returns the downcasted int40 from int256, reverting on
     * overflow (when the input is less than smallest int40 or
     * greater than largest int40).
     *
     * Counterpart to Solidity's `int40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     *
     * _Available since v4.7._
     */
    function toInt40(int256 value) internal pure returns (int40 downcasted) {
        downcasted = int40(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 40 bits");
    }

    /**
     * @dev Returns the downcasted int32 from int256, reverting on
     * overflow (when the input is less than smallest int32 or
     * greater than largest int32).
     *
     * Counterpart to Solidity's `int32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     *
     * _Available since v3.1._
     */
    function toInt32(int256 value) internal pure returns (int32 downcasted) {
        downcasted = int32(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 32 bits");
    }

    /**
     * @dev Returns the downcasted int24 from int256, reverting on
     * overflow (when the input is less than smallest int24 or
     * greater than largest int24).
     *
     * Counterpart to Solidity's `int24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     *
     * _Available since v4.7._
     */
    function toInt24(int256 value) internal pure returns (int24 downcasted) {
        downcasted = int24(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 24 bits");
    }

    /**
     * @dev Returns the downcasted int16 from int256, reverting on
     * overflow (when the input is less than smallest int16 or
     * greater than largest int16).
     *
     * Counterpart to Solidity's `int16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     *
     * _Available since v3.1._
     */
    function toInt16(int256 value) internal pure returns (int16 downcasted) {
        downcasted = int16(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 16 bits");
    }

    /**
     * @dev Returns the downcasted int8 from int256, reverting on
     * overflow (when the input is less than smallest int8 or
     * greater than largest int8).
     *
     * Counterpart to Solidity's `int8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     *
     * _Available since v3.1._
     */
    function toInt8(int256 value) internal pure returns (int8 downcasted) {
        downcasted = int8(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 8 bits");
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     *
     * _Available since v3.0._
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        require(value <= uint256(type(int256).max), "SafeCast: value doesn't fit in an int256");
        return int256(value);
    }
}



// ============================================================
// FILE: lib/MultiToken/src/MultiToken.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "openzeppelin/interfaces/IERC20.sol";
import { IERC721 } from "openzeppelin/interfaces/IERC721.sol";
import { IERC1155 } from "openzeppelin/interfaces/IERC1155.sol";
import { IERC20Permit } from "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { ERC165Checker } from "openzeppelin/utils/introspection/ERC165Checker.sol";

import { ICryptoKitties } from "multitoken/interfaces/ICryptoKitties.sol";
import { IMultiTokenCategoryRegistry } from "multitoken/interfaces/IMultiTokenCategoryRegistry.sol";


/**
 * @title MultiToken library
 * @dev Library for handling various token standards (ERC20, ERC721, ERC1155, CryptoKitties) in a single contract.
 */
library MultiToken {
    using ERC165Checker for address;
    using SafeERC20 for IERC20;

    bytes4 public constant ERC20_INTERFACE_ID = 0x36372b07;
    bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 public constant ERC1155_INTERFACE_ID = 0xd9b67a26;
    bytes4 public constant CRYPTO_KITTIES_INTERFACE_ID = 0x9a20483d;

    /**
    * @notice A reserved value for a category not registered.
    */
    uint8 public constant CATEGORY_NOT_REGISTERED = type(uint8).max;

    /**
     * @title Category
     * @dev Enum representation Asset category.
     */
    enum Category {
        ERC20,
        ERC721,
        ERC1155,
        CryptoKitties
    }

    /**
     * @title Asset
     * @param category Corresponding asset category.
     * @param assetAddress Address of the token contract defining the asset.
     * @param id TokenID of an NFT or 0.
     * @param amount Amount of fungible tokens or 0 -> 1.
     */
    struct Asset {
        Category category;
        address assetAddress;
        uint256 id;
        uint256 amount;
    }

    /**
     * @notice Thrown when unsupported category is used.
     * @param categoryValue Value of the unsupported category.
     */
    error UnsupportedCategory(uint8 categoryValue);

    /*----------------------------------------------------------*|
    |*  # FACTORY FUNCTIONS                                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Factory function for creating an ERC20 asset.
     * @param assetAddress Address of the token contract defining the asset.
     * @param amount Amount of fungible tokens.
     * @return Asset struct representing the ERC20 asset.
     */
    function ERC20(address assetAddress, uint256 amount) internal pure returns (Asset memory) {
        return Asset(Category.ERC20, assetAddress, 0, amount);
    }

    /**
     * @notice Factory function for creating an ERC721 asset.
     * @param assetAddress Address of the token contract defining the asset.
     * @param id Token id of an NFT.
     * @return Asset struct representing the ERC721 asset.
     */
    function ERC721(address assetAddress, uint256 id) internal pure returns (Asset memory) {
        return Asset(Category.ERC721, assetAddress, id, 0);
    }

    /**
     * @notice Factory function for creating an ERC1155 asset.
     * @param assetAddress Address of the token contract defining the asset.
     * @param id Token id of an SFT.
     * @param amount Amount of semifungible tokens.
     * @return Asset struct representing the ERC1155 asset.
     */
    function ERC1155(address assetAddress, uint256 id, uint256 amount) internal pure returns (Asset memory) {
        return Asset(Category.ERC1155, assetAddress, id, amount);
    }

    /**
     * @notice Factory function for creating an ERC1155 NFT asset.
     * @param assetAddress Address of the token contract defining the asset.
     * @param id Token id of an NFT.
     * @return Asset struct representing the ERC1155 NFT asset.
     */
    function ERC1155(address assetAddress, uint256 id) internal pure returns (Asset memory) {
        return Asset(Category.ERC1155, assetAddress, id, 0);
    }

    /**
     * @notice Factory function for creating a CryptoKitties asset.
     * @param assetAddress Address of the token contract defining the asset.
     * @param id Token id of a CryptoKitty.
     * @return Asset struct representing the CryptoKitties asset.
     */
    function CryptoKitties(address assetAddress, uint256 id) internal pure returns (Asset memory) {
        return Asset(Category.CryptoKitties, assetAddress, id, 0);
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER ASSET                                        *|
    |*----------------------------------------------------------*/

    /**
     * @notice Wrapping function for `transferFrom` calls on various token interfaces.
     * @dev If `source` is `address(this)`, function `transfer` is called instead of `transferFrom` for ERC20 category.
     * @param asset Struct defining all necessary context of a token.
     * @param source Account/address that provided the allowance.
     * @param dest Destination address.
     */
    function transferAssetFrom(Asset memory asset, address source, address dest) internal {
        _transferAssetFrom(asset, source, dest, false);
    }

    /**
     * @notice Wrapping function for `safeTransferFrom` calls on various token interfaces.
     * @dev If `source` is `address(this)`, function `transfer` is called instead of `transferFrom` for ERC20 category.
     * @param asset Struct defining all necessary context of a token.
     * @param source Account/address that provided the allowance.
     * @param dest Destination address.
     */
    function safeTransferAssetFrom(Asset memory asset, address source, address dest) internal {
        _transferAssetFrom(asset, source, dest, true);
    }

    function _transferAssetFrom(Asset memory asset, address source, address dest, bool isSafe) private {
        if (asset.category == Category.ERC20) {
            if (source == address(this))
                IERC20(asset.assetAddress).safeTransfer(dest, asset.amount);
            else
                IERC20(asset.assetAddress).safeTransferFrom(source, dest, asset.amount);

        } else if (asset.category == Category.ERC721) {
            if (!isSafe)
                IERC721(asset.assetAddress).transferFrom(source, dest, asset.id);
            else
                IERC721(asset.assetAddress).safeTransferFrom(source, dest, asset.id, "");

        } else if (asset.category == Category.ERC1155) {
            IERC1155(asset.assetAddress).safeTransferFrom(source, dest, asset.id, asset.amount == 0 ? 1 : asset.amount, "");

        } else if (asset.category == Category.CryptoKitties) {
            if (source == address(this))
                ICryptoKitties(asset.assetAddress).transfer(dest, asset.id);
            else
                ICryptoKitties(asset.assetAddress).transferFrom(source, dest, asset.id);

        } else {
            revert("MultiToken: Unsupported category");
        }
    }

    /**
     * @notice Get amount of asset that would be transferred.
     * @dev NFTs (ERC721, CryptoKitties & ERC1155 with amount 0) with return 1.
     *      Fungible tokens will return its amount (ERC20 with 0 amount is valid).
     *      In combination with `balanceOf` can be used to check successful asset transfer.
     * @param asset Struct defining all necessary context of a token.
     * @return Number of tokens that would be transferred of the asset.
     */
    function getTransferAmount(Asset memory asset) internal pure returns (uint256) {
        if (asset.category == Category.ERC20)
            return asset.amount;
        else if (asset.category == Category.ERC1155 && asset.amount > 0)
            return asset.amount;
        else // Return 1 for ERC721, CryptoKitties and ERC1155 used as NFTs (amount = 0)
            return 1;
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER ASSET CALLDATA                               *|
    |*----------------------------------------------------------*/

    /**
     * @notice Wrapping function for `transferFrom` calladata on various token interfaces.
     * @dev If `fromSender` is true, function `transfer` is returned instead of `transferFrom` for ERC20 category.
     * @param asset Struct defining all necessary context of a token.
     * @param source Account/address that provided the allowance.
     * @param dest Destination address.
     */
    function transferAssetFromCalldata(Asset memory asset, address source, address dest, bool fromSender) pure internal returns (bytes memory) {
        return _transferAssetFromCalldata(asset, source, dest, fromSender, false);
    }

    /**
     * @notice Wrapping function for `safeTransferFrom` calladata on various token interfaces.
     * @dev If `fromSender` is true, function `transfer` is returned instead of `transferFrom` for ERC20 category.
     * @param asset Struct defining all necessary context of a token.
     * @param source Account/address that provided the allowance.
     * @param dest Destination address.
     */
    function safeTransferAssetFromCalldata(Asset memory asset, address source, address dest, bool fromSender) pure internal returns (bytes memory) {
        return _transferAssetFromCalldata(asset, source, dest, fromSender, true);
    }

    function _transferAssetFromCalldata(Asset memory asset, address source, address dest, bool fromSender, bool isSafe) pure private returns (bytes memory) {
        if (asset.category == Category.ERC20) {
            if (fromSender) {
                return abi.encodeWithSignature(
                    "transfer(address,uint256)", dest, asset.amount
                );
            } else {
                return abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)", source, dest, asset.amount
                );
            }
        } else if (asset.category == Category.ERC721) {
            if (!isSafe) {
                return abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)", source, dest, asset.id
                );
            } else {
                return abi.encodeWithSignature(
                    "safeTransferFrom(address,address,uint256,bytes)", source, dest, asset.id, ""
                );
            }

        } else if (asset.category == Category.ERC1155) {
            return abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,uint256,bytes)", source, dest, asset.id, asset.amount == 0 ? 1 : asset.amount, ""
            );

        } else if (asset.category == Category.CryptoKitties) {
            if (fromSender) {
                return abi.encodeWithSignature(
                    "transfer(address,uint256)", dest, asset.id
                );
            } else {
                return abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)", source, dest, asset.id
                );
            }

        } else {
            revert("MultiToken: Unsupported category");
        }
    }


    /*----------------------------------------------------------*|
    |*  # PERMIT                                                *|
    |*----------------------------------------------------------*/

    /**
     * @notice Wrapping function for granting approval via permit signature.
     * @param asset Struct defining all necessary context of a token.
     * @param owner Account/address that signed the permit.
     * @param spender Account/address that would be granted approval to `asset`.
     * @param permitData Data about permit deadline (uint256) and permit signature (64/65 bytes).
     *                   Deadline and signature should be pack encoded together.
     *                   Signature can be standard (65 bytes) or compact (64 bytes) defined in EIP-2098.
     */
    function permit(Asset memory asset, address owner, address spender, bytes memory permitData) internal {
        if (asset.category == Category.ERC20) {

            // Parse deadline and permit signature parameters
            uint256 deadline;
            bytes32 r;
            bytes32 s;
            uint8 v;

            // Parsing signature parameters used from OpenZeppelins ECDSA library
            // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/83277ff916ac4f58fec072b8f28a252c1245c2f1/contracts/utils/cryptography/ECDSA.sol

            // Deadline (32 bytes) + standard signature data (65 bytes) -> 97 bytes
            if (permitData.length == 97) {
                assembly {
                    deadline := mload(add(permitData, 0x20))
                    r := mload(add(permitData, 0x40))
                    s := mload(add(permitData, 0x60))
                    v := byte(0, mload(add(permitData, 0x80)))
                }
            }
            // Deadline (32 bytes) + compact signature data (64 bytes) -> 96 bytes
            else if (permitData.length == 96) {
                bytes32 vs;

                assembly {
                    deadline := mload(add(permitData, 0x20))
                    r := mload(add(permitData, 0x40))
                    vs := mload(add(permitData, 0x60))
                }

                s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
                v = uint8((uint256(vs) >> 255) + 27);
            } else {
                revert("MultiToken::Permit: Invalid permit length");
            }

            // Call permit with parsed parameters
            IERC20Permit(asset.assetAddress).permit(owner, spender, asset.amount, deadline, v, r, s);

        } else {
            // Currently supporting only ERC20 signed approvals via ERC2612
            revert("MultiToken::Permit: Unsupported category");
        }
    }


    /*----------------------------------------------------------*|
    |*  # BALANCE OF                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Wrapping function for checking balances on various token interfaces.
     * @param asset Struct defining all necessary context of a token.
     * @param target Target address to be checked.
     */
    function balanceOf(Asset memory asset, address target) internal view returns (uint256) {
        if (asset.category == Category.ERC20) {
            return IERC20(asset.assetAddress).balanceOf(target);

        } else if (asset.category == Category.ERC721) {
            return IERC721(asset.assetAddress).ownerOf(asset.id) == target ? 1 : 0;

        } else if (asset.category == Category.ERC1155) {
            return IERC1155(asset.assetAddress).balanceOf(target, asset.id);

        } else if (asset.category == Category.CryptoKitties) {
            return ICryptoKitties(asset.assetAddress).ownerOf(asset.id) == target ? 1 : 0;

        } else {
            revert("MultiToken: Unsupported category");
        }
    }


    /*----------------------------------------------------------*|
    |*  # APPROVE ASSET                                         *|
    |*----------------------------------------------------------*/

    /**
     * @notice Wrapping function for `approve` calls on various token interfaces.
     * @dev By using `safeApprove` for ERC20, caller can set allowance to 0 or from 0.
     *      Cannot set non-zero value if allowance is also non-zero.
     * @param asset Struct defining all necessary context of a token.
     * @param target Account/address that would be granted approval to `asset`.
     */
    function approveAsset(Asset memory asset, address target) internal {
        if (asset.category == Category.ERC20) {
            IERC20(asset.assetAddress).safeApprove(target, asset.amount);

        } else if (asset.category == Category.ERC721) {
            IERC721(asset.assetAddress).approve(target, asset.id);

        } else if (asset.category == Category.ERC1155) {
            IERC1155(asset.assetAddress).setApprovalForAll(target, true);

        } else if (asset.category == Category.CryptoKitties) {
            ICryptoKitties(asset.assetAddress).approve(target, asset.id);

        } else {
            revert("MultiToken: Unsupported category");
        }
    }


    /*----------------------------------------------------------*|
    |*  # ASSET CHECKS                                          *|
    |*----------------------------------------------------------*/

    /**
     * @notice Checks that provided asset is contract, has correct format and stated category via MultiTokenCategoryRegistry and ERC165 checks.
     * @dev Fungible tokens (ERC20) have to have id = 0.
     *      NFT (ERC721, CryptoKitties) tokens have to have amount = 0.
     *      Correct asset category is determined via ERC165.
     *      The check assumes, that asset contract implements only one token standard at a time.
     * @param registry Category registry contract.
     * @param asset Asset that is examined.
     * @return True if asset has correct format and category.
     */
    function isValid(Asset memory asset, IMultiTokenCategoryRegistry registry) internal view returns (bool) {
        return _checkCategory(asset, registry) && _checkFormat(asset);
    }

    /**
     * @notice Checks that provided asset is contract, has correct format and stated category via ERC165 checks.
     * @dev Fungible tokens (ERC20) have to have id = 0.
     *      NFT (ERC721, CryptoKitties) tokens have to have amount = 0.
     *      Correct asset category is determined via ERC165.
     *      The check assumes, that asset contract implements only one token standard at a time.
     * @param asset Asset that is examined.
     * @return True if asset has correct format and category.
     */
    function isValid(Asset memory asset) internal view returns (bool) {
        return _checkCategoryViaERC165(asset) && _checkFormat(asset);
    }

    /**
     * @notice Checks that provided asset is contract and stated category is correct via MultiTokenCategoryRegistry and ERC165 checks.
     * @dev Will fallback to ERC165 checks if asset is not registered in the category registry.
     *      The check assumes, that asset contract implements only one token standard at a time.
     * @param registry Category registry contract.
     * @param asset Asset that is examined.
     * @return True if assets stated category is correct.
     */
    function _checkCategory(Asset memory asset, IMultiTokenCategoryRegistry registry) internal view returns (bool) {
        // Check if asset is registered in the category registry
        uint8 categoryValue = registry.registeredCategoryValue(asset.assetAddress);
        if (categoryValue != CATEGORY_NOT_REGISTERED)
            return uint8(asset.category) == categoryValue;

        return _checkCategoryViaERC165(asset);
    }

    /**
     * @notice Checks that provided asset is contract and stated category is correct via ERC165 checks.
     * @dev The check assumes, that asset contract implements only one token standard at a time.
     * @param asset Asset that is examined.
     * @return True if assets stated category is correct.
     */
    function _checkCategoryViaERC165(Asset memory asset) internal view returns (bool) {
        if (asset.category == Category.ERC20) {
            // ERC20 has optional ERC165 implementation
            if (asset.assetAddress.supportsERC165()) {
                // If contract implements ERC165 and returns true for ERC20 intefrace id, consider it a correct category
                if (asset.assetAddress.supportsERC165InterfaceUnchecked(ERC20_INTERFACE_ID))
                    return true;

                // If contract implements ERC165, it has to return false for ERC721, ERC1155, and CryptoKitties interface ids
                return
                    !asset.assetAddress.supportsERC165InterfaceUnchecked(ERC721_INTERFACE_ID) &&
                    !asset.assetAddress.supportsERC165InterfaceUnchecked(ERC1155_INTERFACE_ID) &&
                    !asset.assetAddress.supportsERC165InterfaceUnchecked(CRYPTO_KITTIES_INTERFACE_ID);

            } else {
                // In case token doesn't implement ERC165, its safe to assume that provided category is correct,
                // because any other category has to implement ERC165.

                // Check that asset address is contract
                // Note: Asset address will return code length 0, if this code is called from the constructor.
                return asset.assetAddress.code.length > 0;
            }

        } else if (asset.category == Category.ERC721) {
            // Check ERC721 via ERC165
            return asset.assetAddress.supportsInterface(ERC721_INTERFACE_ID);

        } else if (asset.category == Category.ERC1155) {
            // Check ERC1155 via ERC165
            return asset.assetAddress.supportsInterface(ERC1155_INTERFACE_ID);

        } else if (asset.category == Category.CryptoKitties) {
            // Check CryptoKitties via ERC165
            return asset.assetAddress.supportsInterface(CRYPTO_KITTIES_INTERFACE_ID);

        } else {
            revert UnsupportedCategory(uint8(asset.category));
        }
    }

    /**
     * @notice Checks that provided asset has correct format.
     * @dev Fungible tokens (ERC20) have to have id = 0.
     *      NFT (ERC721, CryptoKitties) tokens have to have amount = 0.
     *      Correct asset category is determined via ERC165.
     * @param asset Asset that is examined.
     * @return True asset struct has correct format.
     */
    function _checkFormat(Asset memory asset) internal pure returns (bool) {
        if (asset.category == Category.ERC20) {
            // Id must be 0 for ERC20
            if (asset.id != 0) return false;

        } else if (asset.category == Category.ERC721) {
            // Amount must be 0 for ERC721
            if (asset.amount != 0) return false;

        } else if (asset.category == Category.ERC1155) {
            // No format check for ERC1155

        } else if (asset.category == Category.CryptoKitties) {
            // Amount must be 0 for CryptoKitties
            if (asset.amount != 0) return false;

        } else {
            revert UnsupportedCategory(uint8(asset.category));
        }

        return true;
    }

    /**
     * @notice Compare two assets, ignoring their amounts.
     * @param asset First asset to examine.
     * @param otherAsset Second asset to examine.
     * @return True if both structs represents the same asset.
     */
    function isSameAs(Asset memory asset, Asset memory otherAsset) internal pure returns (bool) {
        return
            asset.category == otherAsset.category &&
            asset.assetAddress == otherAsset.assetAddress &&
            asset.id == otherAsset.id;
    }

}



// ============================================================
// FILE: src/core/hub/PWNHub.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Ownable2Step } from "openzeppelin/access/Ownable2Step.sol";


/**
 * @title PWN Hub
 * @notice Connects PWN contracts together into protocol via tags.
 */
contract PWNHub is Ownable2Step {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /** @dev Mapping of address tags. (contract address => tag => is tagged)*/
    mapping (address => mapping (bytes32 => bool)) private tags;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when tag is set for an address.*/
    event TagSet(address indexed _address, bytes32 indexed tag, bool hasTag);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when `PWNHub.setTags` inputs lengths are not equal.*/
    error InvalidInputData();


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor() Ownable2Step() {

    }


    /*----------------------------------------------------------*|
    |*  # TAG MANAGEMENT                                        *|
    |*----------------------------------------------------------*/

    /**
     * @notice Set tag to an address.
     * @dev Tag can be added or removed via this functions. Only callable by contract owner.
     * @param _address Address to which a tag is set.
     * @param tag Tag that is set to an `_address`.
     * @param _hasTag Bool value if tag is added or removed.
     */
    function setTag(address _address, bytes32 tag, bool _hasTag) public onlyOwner {
        tags[_address][tag] = _hasTag;
        emit TagSet(_address, tag, _hasTag);
    }

    /**
     * @notice Set list of tags to an address.
     * @dev Tags can be added or removed via this functions. Only callable by contract owner.
     * @param _addresses List of addresses to which tags are set.
     * @param _tags List of tags that are set to an `_address`.
     * @param _hasTag Bool value if tags are added or removed.
     */
    function setTags(address[] memory _addresses, bytes32[] memory _tags, bool _hasTag) external onlyOwner {
        if (_addresses.length != _tags.length)
            revert InvalidInputData();

        uint256 length = _tags.length;
        for (uint256 i; i < length;) {
            setTag(_addresses[i], _tags[i], _hasTag);
            unchecked { ++i; }
        }
    }


    /*----------------------------------------------------------*|
    |*  # TAG GETTER                                            *|
    |*----------------------------------------------------------*/

    /**
     * @dev Return if an address is associated with a tag.
     * @param _address Address that is examined for a `tag`.
     * @param tag Tag that should an `_address` be associated with.
     * @return True if given address has a tag.
     */
    function hasTag(address _address, bytes32 tag) external view returns (bool) {
        return tags[_address][tag];
    }

}



// ============================================================
// FILE: src/core/hub/PWNHubTags.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

library PWNHubTags {

    string internal constant VERSION = "1.5";

    /// @dev Address can mint LOAN tokens and create LOANs via loan factory contracts.
    bytes32 internal constant ACTIVE_LOAN = keccak256("PWN_ACTIVE_LOAN");
    /// @dev Address can call loan contracts to create and/or refinance a loan.
    bytes32 internal constant LOAN_PROPOSAL = keccak256("PWN_LOAN_PROPOSAL");
    /// @dev Address can revoke nonces on other addresses behalf.
    bytes32 internal constant NONCE_MANAGER = keccak256("PWN_NONCE_MANAGER");

}



// ============================================================
// FILE: src/core/loan/PWNLoan.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IMultiTokenCategoryRegistry } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

import { PWNConfig } from "pwn/core/config/PWNConfig.sol";
import { IPWNBorrowerCreateHook, BORROWER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNBorrowerCreateHook.sol";
import { IPWNBorrowerCollateralRepaymentHook, BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNBorrowerCollateralRepaymentHook.sol";
import { IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderCreateHook.sol";
import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderRepaymentHook.sol";
import { IPWNProduct } from "pwn/core/product/IPWNProduct.sol";
import { LOANStatus } from "pwn/core/loan/LOANStatus.sol";
import { LoanTerms as Terms } from "pwn/core/loan/LoanTerms.sol";
import { PWNProposalManager } from "pwn/core/loan/PWNProposalManager.sol";
import { PWNVault } from "pwn/core/loan/PWNVault.sol";
import { IERC5646 } from "pwn/core/token/IERC5646.sol";
import { IPWNLoanMetadataProvider } from "pwn/core/token/IPWNLoanMetadataProvider.sol";
import { PWNLOAN } from "pwn/core/token/PWNLOAN.sol";

/**
 * @title PWN Loan
 * @notice Contract managing loans in PWN protocol.
 * @dev Acts as a vault for every loan created by this contract.
 */
contract PWNLoan is PWNProposalManager, PWNVault, IERC5646, IPWNLoanMetadataProvider {
    using MultiToken for address;

    string public constant VERSION = "1.5";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes32 internal constant _EMPTY_LENDER_SPEC_HASH = keccak256(abi.encode(LenderSpec(IPWNLenderCreateHook(address(0)), "", IPWNLenderRepaymentHook(address(0)), "")));
    bytes32 internal constant _EMPTY_BORROWER_SPEC_HASH = keccak256(abi.encode(BorrowerSpec(IPWNBorrowerCreateHook(address(0)), "")));

    PWNLOAN public immutable loanToken;
    PWNConfig public immutable config;
    IMultiTokenCategoryRegistry public immutable categoryRegistry;

    /**
     * @notice Loan proposal specification during loan creation.
     * @param proposer Address of a proposer that signed the proposal.
     * @param product Address of a product contract.
     * @param proposalData Encoded proposal data that is passed to the loan proposal contract.
     * @param proposalInclusionProof Inclusion proof of the proposal in the proposal contract.
     * @param signature Signature of the proposal.
     */
    struct ProposalSpec {
        address proposer;
        IPWNProduct product;
        bytes proposalData;
        bytes32[] proposalInclusionProof;
        bytes signature;
    }

    /**
     * @notice Struct defining a lender specification.
     * @param createHook Lender create hook that is called during loan creation.
     * @param createHookData Data passed to the lender create hook.
     * @param repaymentHook Lender repayment hook that is called during loan repayment.
     * @param repaymentHookData Data passed to the lender repayment hook.
     */
    struct LenderSpec {
        IPWNLenderCreateHook createHook;
        bytes createHookData;
        IPWNLenderRepaymentHook repaymentHook;
        bytes repaymentHookData;
    }

    /**
     * @notice Struct defining a borrower specification.
     * @param createHook Borrower create hook that is called during loan creation.
     * @param createHookData Data passed to the borrower create hook.
     */
    struct BorrowerSpec {
        IPWNBorrowerCreateHook createHook;
        bytes createHookData;
    }

    /**
     * @notice Struct defining a loan.
     * @param borrower Address of a borrower.
     * @param lastUpdateTimestamp Unix timestamp (in seconds) of the last loan update.
     * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
     * @param creditAddress Address of an asset used as a loan credit.
     * @param principal Principal amount in credit asset tokens.
     * @param pastAccruedInterest Accrued interest amount in credit asset tokens before `lastUpdateTimestamp`.
     * @param unclaimedRepayment Amount of the credit asset that can be claimed by loan owner.
     * @param product Product contract associated with the loan.
     */
    struct LOAN {
        address borrower;
        uint40 lastUpdateTimestamp;
        MultiToken.Asset collateral;
        address creditAddress;
        uint256 principal;
        uint256 pastAccruedInterest;
        uint256 unclaimedRepayment;
        IPWNProduct product;
    }

    /** Mapping of all LOAN data by loan id.*/
    mapping (uint256 => LOAN) private LOANs;

    struct LenderRepaymentHookData {
        IPWNLenderRepaymentHook hook;
        bytes data;
    }

    /** @notice Mapping of lender repayment hook data per loan id.*/
    mapping (address => mapping (uint256 => LenderRepaymentHookData)) public lenderRepaymentHook;

    /** @notice Mapping of loan id to whether the loan context is locked.*/
    mapping (uint256 => bool) public loanLock;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when a new loan in created.*/
    event LOANCreated(uint256 indexed loanId, bytes32 indexed proposalHash, address indexed product, Terms terms, LenderSpec lenderSpec, BorrowerSpec borrowerSpec, bytes extra);
    /** @notice Emitted when a loan repayment is made.*/
    event LOANRepaid(uint256 indexed loanId, uint256 repaymentAmount, uint256 indexed newPrincipal);
    /** @notice Emitted when a loan repayment is claimed.*/
    event LOANRepaymentClaimed(uint256 indexed loanId, uint256 claimedAmount);
    /** @notice Emitted when a loan collateral is liquidated.*/
    event LOANLiquidated(uint256 indexed loanId, address indexed liquidator, uint256 liquidationAmount);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when a call tries to enter locked loan context.*/
    error LoanContextLocked(uint256 loanId);
    /** @notice Thrown when managed loan is not running.*/
    error LoanNotRunning();
    /** @notice Thrown when managed loan is not defaulted.*/
    error LoanNotDefaulted();
    /** @notice Thrown when caller is not a LOAN token holder.*/
    error CallerNotLOANTokenHolder();
    /** @notice Thrown when hash of provided proposer spec doesn't match the one in loan terms.*/
    error InvalidProposerSpecHash(bytes32 current, bytes32 expected);
    /** @notice Thrown when caller is not a vault.*/
    error CallerNotVault();
    /** @notice Thrown when MultiToken.Asset is invalid because of invalid category, address, id or amount.*/
    error InvalidMultiTokenAsset(uint8 category, address addr, uint256 id, uint256 amount);
    /** @notice Thrown when repayment amount is out of bounds.*/
    error InvalidRepaymentAmount(uint256 current, uint256 limit);
    /** @notice Thrown when nothing can be claimed.*/
    error NothingToClaim();
    /** @notice Thrown when hook returns an invalid value.*/
    error InvalidHookReturnValue(bytes32 expected, bytes32 current);
    /** @notice Thrown when caller is not a loan borrower.*/
    error CallerNotBorrower();
    /** @notice Thrown when hook is not set or is zero address.*/
    error HookZeroAddress();
    /** @notice Thrown when loan is defaulted on creation.*/
    error DefaultedOnCreation();
    /** @notice Thrown when a loan is created with zero principal.*/
    error ZeroPrincipal();
    /** @notice Thrown when proposal acceptor and proposer are the same.*/
    error AcceptorIsProposer(address addr);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        address _loanToken,
        address _config,
        address _categoryRegistry
    ) {
        loanToken = PWNLOAN(_loanToken);
        config = PWNConfig(_config);
        categoryRegistry = IMultiTokenCategoryRegistry(_categoryRegistry);
    }


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier nonLoanContextReentrant(uint256 loanId) {
        _lockLoanContext(loanId);
        _;
        _unlockLoanContext(loanId);
    }

    function _lockLoanContext(uint256 loanId) private {
        if (loanLock[loanId]) revert LoanContextLocked(loanId);
        loanLock[loanId] = true;
    }

    function _unlockLoanContext(uint256 loanId) private {
        loanLock[loanId] = false;
    }


    /*----------------------------------------------------------*|
    |*  # CREATE LOAN                                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Create a new loan.
     * @dev The function assumes a prior token approval to a contract address.
     * @param proposalSpec Proposal specification struct.
     * @param lenderSpec Lender specification struct.
     * @param borrowerSpec Borrower specification struct.
     * @param extra Auxiliary data that are emitted in the loan creation event. They are not used in the contract logic.
     * @return loanId Id of the created LOAN token.
     */
    function create(
        ProposalSpec calldata proposalSpec,
        LenderSpec calldata lenderSpec,
        BorrowerSpec calldata borrowerSpec,
        bytes calldata extra
    ) external returns (uint256 loanId) {
        if (msg.sender == proposalSpec.proposer) revert AcceptorIsProposer(msg.sender);

        // Mint LOAN token for lender
        loanId = loanToken.mint(address(this));

        // Lock loan context to prevent reentrancy
        _lockLoanContext(loanId);

        // Check proposal signature
        bytes32 proposalHash = hashProposal(proposalSpec.product, proposalSpec.proposalData);
        _checkProposalSignature(
            proposalSpec.proposer, proposalHash, proposalSpec.proposalInclusionProof, proposalSpec.signature
        );

        // Note: Both lender and borrower may utilize any proposal contract, provided mutual agreement.
        // The acceptor commits to the proposal contract by executing this transaction,
        // while the proposer commits by signing a proposal originating from the contract.

        // Accept proposal and get loan terms
        Terms memory loanTerms = proposalSpec.product.acceptProposal({
            loanId: loanId,
            acceptor: msg.sender,
            proposer: proposalSpec.proposer,
            proposalData: proposalSpec.proposalData
        });

        address lender = loanTerms.isProposerLender ? proposalSpec.proposer : msg.sender;
        address borrower = loanTerms.isProposerLender ? msg.sender : proposalSpec.proposer;

        // Transfer LOAN token to lender
        loanToken.safeTransferFrom(address(this), lender, loanId);

        // Check that provided proposer spec is correct
        bytes32 proposerSpecHash = loanTerms.isProposerLender
            ? getLenderSpecHash(lenderSpec)
            : getBorrowerSpecHash(borrowerSpec);
        if (proposerSpecHash != loanTerms.proposerSpecHash) {
            revert InvalidProposerSpecHash({ current: proposerSpecHash, expected: loanTerms.proposerSpecHash });
        }

        // Check loan credit and collateral validity
        if (loanTerms.principal == 0) revert ZeroPrincipal();
        _checkValidAsset(loanTerms.creditAddress.ERC20(loanTerms.principal));
        _checkValidAsset(loanTerms.collateral);

        // Store loan data under loan id
        LOAN storage loan = LOANs[loanId];
        loan.product = proposalSpec.product;
        loan.borrower = borrower;
        loan.lastUpdateTimestamp = uint40(block.timestamp);
        loan.creditAddress = loanTerms.creditAddress;
        loan.principal = loanTerms.principal;
        loan.collateral = loanTerms.collateral;

        // Emit event
        emit LOANCreated({
            loanId: loanId,
            proposalHash: proposalHash,
            product: address(proposalSpec.product),
            terms: loanTerms,
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: extra
        });

        // Store lender repayment hook
        // Note: hook tag check is not required here; would fail on repayment
        if (address(lenderSpec.repaymentHook) != address(0)) {
            lenderRepaymentHook[lender][loanId] = LenderRepaymentHookData({
                hook: lenderSpec.repaymentHook,
                data: lenderSpec.repaymentHookData
            });
        }

        // Check that loan is not defaulted on creation
        if (proposalSpec.product.isDefaulted(address(this), loanId)) {
            revert DefaultedOnCreation();
        }

        // Settle the loan
        _settleNewLoan(loanId, lender, borrower, loanTerms, lenderSpec, borrowerSpec);

        _unlockLoanContext(loanId);
    }

    /**
     * @notice Transfer collateral to Vault and credit to borrower.
     * @dev The function assumes a prior token approval to a contract address.
     * @param loanId Id of a loan that is being created.
     * @param lender Address of a lender.
     * @param borrower Address of a borrower.
     * @param loanTerms Loan terms struct.
     * @param lenderSpec Lender specification struct.
     * @param borrowerSpec Borrower specification struct.
     */
    function _settleNewLoan(
        uint256 loanId,
        address lender,
        address borrower,
        Terms memory loanTerms,
        LenderSpec calldata lenderSpec,
        BorrowerSpec calldata borrowerSpec
    ) private {
        // Call lender create hook
        if (address(lenderSpec.createHook) != address(0)) {
            bytes32 hookReturnValue = lenderSpec.createHook.onLoanCreated(
                loanId,
                lender,
                loanTerms.creditAddress,
                loanTerms.principal,
                lenderSpec.createHookData
            );
            if (hookReturnValue != LENDER_CREATE_HOOK_RETURN_VALUE) {
                revert InvalidHookReturnValue({ expected: LENDER_CREATE_HOOK_RETURN_VALUE, current: hookReturnValue });
            }
        }

        // Calculate fee amount and new loan amount
        (uint256 feeAmount, uint256 newLoanAmount) = _calculateFeeAmount(config.fee(), loanTerms.principal);

        // Note: `creditHelper` must not be used before updating the amount.
        MultiToken.Asset memory creditHelper = MultiToken.ERC20(loanTerms.creditAddress, loanTerms.principal);

        // Collect fees
        if (feeAmount > 0) {
            creditHelper.amount = feeAmount;
            _pushFrom(creditHelper, lender, config.feeCollector());
        }

        // Transfer credit to borrower
        creditHelper.amount = newLoanAmount;
        _pushFrom(creditHelper, lender, borrower);

        // Call borrower create hook
        if (address(borrowerSpec.createHook) != address(0)) {
            bytes32 hookReturnValue = borrowerSpec.createHook.onLoanCreated(
                loanId,
                borrower,
                loanTerms.collateral,
                loanTerms.creditAddress,
                newLoanAmount,
                borrowerSpec.createHookData
            );
            if (hookReturnValue != BORROWER_CREATE_HOOK_RETURN_VALUE) {
                revert InvalidHookReturnValue({ expected: BORROWER_CREATE_HOOK_RETURN_VALUE, current: hookReturnValue });
            }
        }

        // Transfer collateral to Vault
        _pull(loanTerms.collateral, borrower);
    }

    /**
     * @notice Calculate fee amount.
     * @param fee Fee value in basis points. Value of 100 is 1% fee.
     * @param loanAmount Amount of an asset used as a loan credit.
     * @return feeAmount Amount of a loan asset that represents a protocol fee.
     * @return newLoanAmount New amount of a loan credit asset, after deducting protocol fee.
     */
    function _calculateFeeAmount(
        uint16 fee,
        uint256 loanAmount
    ) internal pure returns (uint256 feeAmount, uint256 newLoanAmount) {
        if (fee == 0) return (0, loanAmount);

        feeAmount = Math.mulDiv(loanAmount, fee, 1e4);
        newLoanAmount = loanAmount - feeAmount;
    }


    /*----------------------------------------------------------*|
    |*  # REPAY LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Repay running loan.
     * @dev Any address can repay a running loan, but a collateral will be transferred to
     * a borrower address associated with the loan.
     * @dev The function assumes a prior token approval to Loan contract.
     * @param loanId Id of a loan that is being repaid.
     * @param repaymentAmount Amount of a credit asset to be repaid. Use 0 to repay the whole loan.
     */
    function repay(uint256 loanId, uint256 repaymentAmount) external nonLoanContextReentrant(loanId) {
        _repay(loanId, repaymentAmount, address(0), "");
    }

    /**
     * @notice Repay running loan with collateral.
     * @dev Only a borrower can repay a running loan with collateral.
     * @dev The function transfers collateral to repayment hook before calling it,
     * expecting approval and full repayment amount at the end of execution.
     * @param loanId Id of a loan that is being repaid.
     * @param borrowerHook Borrower repayment hook.
     * @param borrowerHookData Data passed to the borrower repayment hook.
     */
    function repayWithCollateral(
        uint256 loanId,
        IPWNBorrowerCollateralRepaymentHook borrowerHook,
        bytes calldata borrowerHookData
    ) external nonLoanContextReentrant(loanId) {
        LOAN storage loan = LOANs[loanId];

        // Caller must be borrower
        if (loan.borrower != msg.sender) revert CallerNotBorrower();
        // Check that hook is set
        if (address(borrowerHook) == address(0)) revert HookZeroAddress();

        _repay(loanId, 0, address(borrowerHook), borrowerHookData);
    }

    function _repay(
        uint256 loanId,
        uint256 repaymentAmount,
        address borrowerHook,
        bytes memory borrowerHookData
    ) internal {
        LOAN storage loan = LOANs[loanId];

        // Check that loan is running
        uint8 status = getLOANStatus(loanId);
        if (status != LOANStatus.RUNNING) revert LoanNotRunning();

        // Check repayment amount
        uint256 debt = getLOANDebt(loanId);
        if (repaymentAmount == 0) {
            repaymentAmount = debt;
        } else if (repaymentAmount > debt) {
            revert InvalidRepaymentAmount({ current: repaymentAmount, limit: debt });
        }

        // Note: The accrued interest is repaid first, then principal.

        // Decrease debt by the repayment amount
        uint256 interest = debt - loan.principal;
        loan.pastAccruedInterest = repaymentAmount < interest ? interest - repaymentAmount : 0;
        loan.principal -= repaymentAmount > interest ? repaymentAmount - interest : 0;
        loan.lastUpdateTimestamp = uint40(block.timestamp);

        emit LOANRepaid({ loanId: loanId, repaymentAmount: repaymentAmount, newPrincipal: loan.principal });

        // Note: Repayment is transferred from sender, or borrower hook if set
        address repaymentOrigin = msg.sender;

        // Settle collateral
        if (loan.principal == 0) {
            if (borrowerHook == address(0)) {
                _push(loan.collateral, loan.borrower);
            } else {
                repaymentOrigin = borrowerHook;
                _callBorrowerHook(loan, repaymentAmount, borrowerHook, borrowerHookData);
            }
        }

        // Settle repayment
        _settleRepayment(loanId, repaymentOrigin, loan.creditAddress, repaymentAmount);

        // Delete loan if fully repaid and claimed
        if (loan.principal == 0 && loan.unclaimedRepayment == 0) {
            _deleteLoan(loanId);
        }
    }

    function _callBorrowerHook(
        LOAN storage loan,
        uint256 repaymentAmount,
        address borrowerHook,
        bytes memory borrowerHookData
    ) internal {
        // Transfer collateral to borrower hook
        _push(loan.collateral, borrowerHook);

        // Call borrower collateral repayment hook
        bytes32 hookReturnValue = IPWNBorrowerCollateralRepaymentHook(borrowerHook).onLoanRepaid({
            borrower: loan.borrower,
            collateral: loan.collateral,
            creditAddress: loan.creditAddress,
            repayment: repaymentAmount,
            borrowerData: borrowerHookData
        });
        if (hookReturnValue != BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE) {
            revert InvalidHookReturnValue({ expected: BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE, current: hookReturnValue });
        }
    }

    function _settleRepayment(
        uint256 loanId,
        address repaymentOrigin,
        address creditAddress,
        uint256 repaymentAmount
    ) internal {
        // Note: Repayment is transferred into the Vault if the hook reverts.

        address loanOwner = loanToken.ownerOf(loanId);
        try this.tryCallLenderRepaymentHook({
            hookData: lenderRepaymentHook[loanOwner][loanId],
            repaymentOrigin: repaymentOrigin,
            loanOwner: loanOwner,
            creditAddress: creditAddress,
            repaymentAmount: repaymentAmount
        }) {} catch {
            // Update unclaimed repayment amount
            LOANs[loanId].unclaimedRepayment += repaymentAmount;
            // Transfer repayment amount to vault
            _pull(creditAddress.ERC20(repaymentAmount), repaymentOrigin);
        }
    }

    function tryCallLenderRepaymentHook(
        LenderRepaymentHookData memory hookData,
        address repaymentOrigin,
        address loanOwner,
        address creditAddress,
        uint256 repaymentAmount
    ) external {
        if (msg.sender != address(this)) revert CallerNotVault();
        if (address(hookData.hook) == address(0)) revert HookZeroAddress();

        // Transfer repayment to lender repayment hook
        _pushFrom(creditAddress.ERC20(repaymentAmount), repaymentOrigin, address(hookData.hook));

        // Call hook and check hooks return value
        bytes32 hookReturnValue = hookData.hook.onLoanRepaid(loanOwner, creditAddress, repaymentAmount, hookData.data);
        if (hookReturnValue != LENDER_REPAYMENT_HOOK_RETURN_VALUE) {
            revert InvalidHookReturnValue({ expected: LENDER_REPAYMENT_HOOK_RETURN_VALUE, current: hookReturnValue });
        }
    }


    /*----------------------------------------------------------*|
    |*  # CLAIM LOAN                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Claim a loan repayment.
     * @dev Only a loan owner can claim a loan repayment.
     * @param loanId Id of a loan that is being claimed.
     */
    function claimRepayment(uint256 loanId) external nonLoanContextReentrant(loanId) {
        // Check that caller is LOAN token holder
        if (loanToken.ownerOf(loanId) != msg.sender) revert CallerNotLOANTokenHolder();

        LOAN storage loan = LOANs[loanId];
        // Check that there is something to claim
        if (loan.unclaimedRepayment == 0) revert NothingToClaim();

        emit LOANRepaymentClaimed({ loanId: loanId, claimedAmount: loan.unclaimedRepayment });

        MultiToken.Asset memory unclaimedCredit = loan.creditAddress.ERC20(loan.unclaimedRepayment);

        if (loan.principal == 0) {
            // Loan is fully repaid, claiming the unclaimed amount deletes the loan
            _deleteLoan(loanId);
        } else {
            // Loan is still RUNNING or DEFAULTED
            loan.unclaimedRepayment = 0;
        }

        // Transfer unclaimed amount to the loan owner
        _push(unclaimedCredit, msg.sender);
    }

    /**
     * @notice Delete loan data and burn LOAN token.
     * @param loanId Id of a loan that is being deleted.
     */
    function _deleteLoan(uint256 loanId) private {
        loanToken.burn(loanId);
        delete LOANs[loanId];
    }


    /*----------------------------------------------------------*|
    |*  # LIQUIDATE LOAN                                        *|
    |*----------------------------------------------------------*/

    /**
     * @notice Liquidate a defaulted loan by a liquidation module.
     * @dev The liquidation module can use any amount of credit asset to be repaid to lender for the liquidation.
     * @param loanId Id of a loan that is being liquidated.
     * @param liquidationData Additional data passed to the liquidation module.
     */
    function liquidate(uint256 loanId, bytes calldata liquidationData) external nonLoanContextReentrant(loanId) {
        uint8 status = getLOANStatus(loanId);
        if (status != LOANStatus.DEFAULTED) revert LoanNotDefaulted();

        LOAN storage loan = LOANs[loanId];

        // Get debt before updating the loan
        uint256 debt = getLOANDebt(loanId);

        // Update loan data
        loan.pastAccruedInterest = 0;
        loan.principal = 0;
        loan.lastUpdateTimestamp = uint40(block.timestamp);

        IPWNProduct product = loan.product;

        // Execute liquidation
        _push(loan.collateral, address(product));
        uint256 liquidationAmount = product.liquidate({
            loanId: loanId,
            liquidator: msg.sender,
            borrower: loan.borrower,
            debt: debt,
            creditAddress: loan.creditAddress,
            collateral: loan.collateral,
            liquidationData: liquidationData
        });
        if (liquidationAmount > 0) {
            _settleRepayment(loanId, address(product), loan.creditAddress, liquidationAmount);
        }

        // Emit liquidation event
        emit LOANLiquidated({
            loanId: loanId,
            liquidator: msg.sender,
            liquidationAmount: liquidationAmount
        });

        // If the loan is fully claimed, delete it
        if (loan.unclaimedRepayment == 0) {
            _deleteLoan(loanId);
        }
    }


    /*----------------------------------------------------------*|
    |*  # GET LOAN                                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return a LOAN data struct associated with a loan id.
     * @param loanId Id of a loan.
     * @return loan LOAN data struct.
     */
    function getLOAN(uint256 loanId) external view returns (LOAN memory) {
        return LOANs[loanId];
    }

    /**
     * @notice Return a LOAN status associated with a loan id.
     * @param loanId Id of a loan.
     * @return status LOAN status.
     */
    function getLOANStatus(uint256 loanId) public view returns (uint8) {
        LOAN storage loan = LOANs[loanId];
        if (loan.principal == 0) {
            return loan.unclaimedRepayment == 0 ? LOANStatus.DEAD : LOANStatus.REPAID;
        } else {
            return _tryIsDefaulted(loanId) ? LOANStatus.DEFAULTED : LOANStatus.RUNNING;
        }
    }

    /**
     * @notice Calculate the total debt of a loan.
     * @dev The total debt is the sum of the principal amount and accrued interest.
     * @param loanId Id of a loan.
     * @return Total debt.
     */
    function getLOANDebt(uint256 loanId) public view returns (uint256) {
        LOAN storage loan = LOANs[loanId];
        if (address(loan.product) == address(0)) return 0; // Note: if loan doesn't exist, return 0
        return loan.principal + loan.pastAccruedInterest + _tryInterest(loanId);
    }


    /*----------------------------------------------------------*|
    |*  # LENDER & BORROWER SPEC                                *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get the hash of a lender specification.
     * @dev The hash is used to verify the lender specification in the loan terms.
     * @param lenderSpec Lender specification struct.
     * @return Hash of the lender specification.
     */
    function getLenderSpecHash(LenderSpec calldata lenderSpec) public pure returns (bytes32) {
        bytes32 specHash = keccak256(abi.encode(lenderSpec));
        return specHash == _EMPTY_LENDER_SPEC_HASH ? bytes32(0) : specHash;
    }

    /**
     * @notice Get the hash of a borrower specification.
     * @dev The hash is used to verify the borrower specification in the loan terms.
     * @param borrowerSpec Borrower specification struct.
     * @return Hash of the borrower specification.
     */
    function getBorrowerSpecHash(BorrowerSpec calldata borrowerSpec) public pure returns (bytes32) {
        bytes32 specHash = keccak256(abi.encode(borrowerSpec));
        return specHash == _EMPTY_BORROWER_SPEC_HASH ? bytes32(0) : specHash;
    }


    /*----------------------------------------------------------*|
    |*  # HOOKS                                                 *|
    |*----------------------------------------------------------*/

    /**
     * @notice Update the lender repayment hook for a loan.
     * @param loanId Id of a loan that is being updated.
     * @param newHook New lender repayment hook.
     * @param newHookData New lender repayment hook data.
     */
    function updateLenderRepaymentHook(
        uint256 loanId,
        IPWNLenderRepaymentHook newHook,
        bytes calldata newHookData
    ) external {
        if (address(newHook) == address(0)) {
            delete lenderRepaymentHook[msg.sender][loanId];
        } else {
            lenderRepaymentHook[msg.sender][loanId] = LenderRepaymentHookData(newHook, newHookData);
        }
    }


    /*----------------------------------------------------------*|
    |*  # MultiToken                                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Check if the asset is valid with the MultiToken dependency lib and the category registry.
     * @dev See MultiToken.isValid for more details.
     * @param asset Asset to be checked.
     * @return True if the asset is valid.
     */
    function isValidAsset(MultiToken.Asset memory asset) public view returns (bool) {
        return MultiToken.isValid(asset, categoryRegistry);
    }

    /**
     * @notice Check if the asset is valid with the MultiToken lib and the category registry.
     * @dev The function will revert if the asset is not valid.
     * @param asset Asset to be checked.
     */
    function _checkValidAsset(MultiToken.Asset memory asset) private view {
        if (!isValidAsset(asset)) {
            revert InvalidMultiTokenAsset({
                category: uint8(asset.category),
                addr: asset.assetAddress,
                id: asset.id,
                amount: asset.amount
            });
        }
    }


    /*----------------------------------------------------------*|
    |*  # IPWNLoanMetadataProvider                              *|
    |*----------------------------------------------------------*/

    /** @inheritdoc IPWNLoanMetadataProvider*/
    function loanMetadataUri() override external view returns (string memory) {
        return config.loanMetadataUri(address(this));
    }


    /*----------------------------------------------------------*|
    |*  # ERC5646                                               *|
    |*----------------------------------------------------------*/

    /** @inheritdoc IERC5646*/
    function getStateFingerprint(uint256 tokenId) external view virtual override returns (bytes32) {
        LOAN storage loan = LOANs[tokenId];
        uint8 status = getLOANStatus(tokenId);
        if (status == LOANStatus.DEAD)
            return bytes32(0);

        // The only mutable state properties are:
        // - status: updated for repaid or defaulted loans
        // - lastUpdateTimestamp: updated on every loan repayment
        // - pastAccruedInterest: used to store currently unpaid accrued interest on every loan repayment
        // - principal: decreased on every loan repayment
        // - unclaimedRepayment: increased on every loan repayment
        // Others don't have to be part of the state fingerprint as it does not act as a token identification.
        return keccak256(abi.encode(
            status,
            loan.lastUpdateTimestamp,
            loan.pastAccruedInterest,
            loan.principal,
            loan.unclaimedRepayment
        ));
    }


    /*----------------------------------------------------------*|
    |*  # UTILS                                                 *|
    |*----------------------------------------------------------*/

    function _tryIsDefaulted(uint256 loanId) internal view returns (bool) {
        try LOANs[loanId].product.isDefaulted(address(this), loanId) returns (bool isDefaulted) {
            return isDefaulted;
        } catch {
            return false; // If the call fails, assume the loan is not defaulted
        }
    }

    function _tryInterest(uint256 loanId) internal view returns (uint256) {
        try LOANs[loanId].product.interest(address(this), loanId) returns (uint256 interest) {
            return interest;
        } catch {
            return 0; // If the call fails, assume no interest
        }
    }

}



// ============================================================
// FILE: src/core/loan/LoanTerms.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

/**
 * @notice Struct defining loan terms.
 * @dev This struct is created by proposal contracts and never stored.
 * @param isProposerLender Indicates if the proposer is the lender.
 * @param proposerSpecHash Hash of a proposer specification.
 * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
 * @param creditAddress Address of an asset used as credit.
 * @param principal Amount of credit.
 */
struct LoanTerms {
    bool isProposerLender;
    bytes32 proposerSpecHash;
    MultiToken.Asset collateral;
    address creditAddress;
    uint256 principal;
}



// ============================================================
// FILE: src/core/product/IPWNProduct.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPWNProposalModule } from "pwn/core/loan/module/IPWNProposalModule.sol";
import { IPWNInterestModule } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { IPWNDefaultModule } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";

/**
 * @title IPWNProduct
 * @notice Interface for PWN products that define the complete lifecycle of a loan.
 *
 * @dev This interface combines proposal, interest, default, and liquidation modules into a single product.
 * Each product can have its own implementation of these modules, allowing for flexible loan terms and conditions.
 * The product is used to create loans with specific terms and conditions defined by the modules it implements.
 */
interface IPWNProduct is IPWNProposalModule, IPWNInterestModule, IPWNDefaultModule, IPWNLiquidationModule {}



// ============================================================
// FILE: src/periphery/lib/Chainlink.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";

import { IChainlinkAggregatorLike } from "pwn/periphery/interfaces/IChainlinkAggregatorLike.sol";
import { IChainlinkFeedRegistryLike } from "pwn/periphery/interfaces/IChainlinkFeedRegistryLike.sol";
import { safeFetchDecimals } from "pwn/periphery/utils/safeFetchDecimals.sol";


library Chainlink {
    using Math for uint256;

    /** @notice Maximum Chainlink feed price age.*/
    uint256 public constant MAX_CHAINLINK_FEED_PRICE_AGE = 1 days;
    /** @notice Grace period time for L2 Sequencer uptime feed.*/
    uint256 public constant L2_GRACE_PERIOD = 10 minutes;
    /** @notice Chainlink address of ETH asset.*/
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /** @notice Throw when Chainlink feed returns negative price.*/
    error ChainlinkFeedReturnedNegativePrice(address feed, int256 price, uint256 updatedAt);
    /** @notice Throw when Chainlink feed price is too old.*/
    error ChainlinkFeedPriceTooOld(address feed, uint256 updatedAt);
    /** @notice Throw when feed invert array is not exactly one item longer than intermediary feed array.*/
    error ChainlinkInvalidInputLenghts();
    /** @notice Throw when L2 Sequencer uptime feed returns that the sequencer is down.*/
    error L2SequencerDown();
    /** @notice Throw when L2 Sequencer uptime feed grace period is not over.*/
    error GracePeriodNotOver(uint256 timeSinceUp, uint256 gracePeriod);
    /** @notice Thrown when intermediary denominations are out of bounds.*/
    error IntermediaryDenominationsOutOfBounds(uint256 current, uint256 limit);


    struct Config {
        IChainlinkAggregatorLike l2SequencerUptimeFeed;
        IChainlinkFeedRegistryLike feedRegistry;
        uint256 maxIntermediaryDenominations;
        address weth;
    }

    /**
     * @notice Converts the amount with the old denomination to the new denomination.
     * @param amount The amount to convert.
     * @param oldDenomination The address of the old denomination.
     * @param newDenomination The address of the new denomination.
     * @param feedIntermediaryDenominations List of intermediary price feeds that will be fetched to get to the quote asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @param config The Chainlink configuration.
     * @return The amount in the new denomination.
     */
    function convertDenomination(
        Config memory config,
        uint256 amount,
        address oldDenomination,
        address newDenomination,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) internal view returns (uint256) {
        // check L2 sequencer uptime if necessary
        checkSequencerUptime(config.l2SequencerUptimeFeed);

        // don't allow more than max intermediary denominations
        if (feedIntermediaryDenominations.length > config.maxIntermediaryDenominations) {
            revert IntermediaryDenominationsOutOfBounds({
                current: feedIntermediaryDenominations.length,
                limit: config.maxIntermediaryDenominations
            });
        }

        // calculate price of base asset with quote asset as denomination
        // Note: use ETH price feed for WETH asset due to absence of WETH price feed
        (uint256 price, uint8 priceDecimals) = calculatePrice({
            feedRegistry: config.feedRegistry,
            baseAsset: oldDenomination == config.weth ? Chainlink.ETH : oldDenomination,
            quoteAsset: newDenomination == config.weth ? Chainlink.ETH : newDenomination,
            feedIntermediaryDenominations: feedIntermediaryDenominations,
            feedInvertFlags: feedInvertFlags
        });

        // fetch denomination decimals
        uint256 oldDenominationDecimals = safeFetchDecimals(oldDenomination);
        uint256 newDenominationDecimals = safeFetchDecimals(newDenomination);
        uint256 maxDecimals = Math.max(oldDenominationDecimals, newDenominationDecimals);

        // calculate amount in new denomination
        uint256 amount_ = amount; // yes, I know, it's just to avoid stack too deep error
        return (amount_ * 10 ** (maxDecimals - oldDenominationDecimals))
            .mulDiv(price, 10 ** priceDecimals)
            / 10 ** (maxDecimals - newDenominationDecimals);
    }

    /**
     * @notice Checks the uptime status of the L2 sequencer.
     * @dev This function reverts if the sequencer is down or if the grace period is not over.
     * @param l2SequencerUptimeFeed The Chainlink feed that provides the sequencer uptime status.
     */
    function checkSequencerUptime(IChainlinkAggregatorLike l2SequencerUptimeFeed) internal view {
        if (address(l2SequencerUptimeFeed) != address(0)) {
            (, int256 answer, uint256 startedAt,,) = l2SequencerUptimeFeed.latestRoundData();
            if (answer == 1) {
                // sequencer is down
                revert L2SequencerDown();
            }

            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= L2_GRACE_PERIOD) {
                // grace period is not over
                revert GracePeriodNotOver({ timeSinceUp: timeSinceUp, gracePeriod: L2_GRACE_PERIOD });
            }
        }
    }

    /**
     * @notice Fetches the prices of the base asset with quote asset as denomination.
     * @dev `feedInvertFlags` array must be exactly one item longer than `feedIntermediaryDenominations`.
     * @param feedRegistry The Chainlink feed registry contract that provides the price feeds.
     * @param baseAsset The address of the base asset.
     * @param quoteAsset The address of the quote asset.
     * @param feedIntermediaryDenominations List of intermediary price feeds that will be fetched to get to the quote asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @return The price of the base asset denominated in quote asset.
     * @return The price decimals.
     */
    function calculatePrice(
        IChainlinkFeedRegistryLike feedRegistry,
        address baseAsset,
        address quoteAsset,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags
    ) internal view returns (uint256, uint8) {
        if (feedInvertFlags.length != feedIntermediaryDenominations.length + 1) {
            revert ChainlinkInvalidInputLenghts();
        }

        // initial state
        uint256 price = 1;
        uint8 priceDecimals = 0;

        // iterate until quote asset is the denominator
        for (uint256 i; i < feedInvertFlags.length; ++i) {
            (price, priceDecimals) = convertPriceDenomination({
                feedRegistry: feedRegistry,
                currentPrice: price,
                currentDecimals: priceDecimals,
                currentDenomination: i == 0 ? baseAsset : feedIntermediaryDenominations[i - 1],
                nextDenomination: i == feedIntermediaryDenominations.length ? quoteAsset : feedIntermediaryDenominations[i],
                nextInvert: feedInvertFlags[i]
            });
        }

        return (price, priceDecimals);
    }

    /**
     * @notice Convert price denomination.
     * @param feedRegistry The Chainlink feed registry contract that provides the price feeds.
     * @param currentPrice Price of an asset denominated in `currentDenomination`.
     * @param currentDecimals Decimals of the current price.
     * @param currentDenomination Address of the current denomination.
     * @param nextDenomination Address of the denomination to convert the current price to.
     * @param nextInvert Flag, if intermediary price feed exists only with inverted base and quote assets.
     * @return nextPrice Price of an asset denomination in `nextDenomination`.
     * @return nextDecimals Decimals of the next price.
     */
    function convertPriceDenomination(
        IChainlinkFeedRegistryLike feedRegistry,
        uint256 currentPrice,
        uint8 currentDecimals,
        address currentDenomination,
        address nextDenomination,
        bool nextInvert
    ) internal view returns (uint256 nextPrice, uint8 nextDecimals) {
        // fetch convert price
        (uint256 intermediaryPrice, uint8 intermediaryDecimals) = fetchPrice({
            feedRegistry: feedRegistry,
            asset: nextInvert ? nextDenomination : currentDenomination,
            denomination: nextInvert ? currentDenomination : nextDenomination
        });

        // sync decimals
        (currentPrice, intermediaryPrice, nextDecimals)
            = syncDecimalsUp(currentPrice, currentDecimals, intermediaryPrice, intermediaryDecimals);

        // compute price with new denomination
        if (nextInvert) {
            nextPrice = Math.mulDiv(currentPrice, 10 ** nextDecimals, intermediaryPrice);
        } else {
            nextPrice = Math.mulDiv(currentPrice, intermediaryPrice, 10 ** nextDecimals);
        }

        return (nextPrice, nextDecimals);
    }

    /**
     * @notice Fetch price from Chainlink feed.
     * @param feedRegistry The Chainlink feed registry contract that provides the price feeds.
     * @param asset Address of an asset.
     * @param denomination Address of a denomination asset.
     * @return price Price of an asset.
     * @return decimals Decimals of a price.
     */
    function fetchPrice(IChainlinkFeedRegistryLike feedRegistry, address asset, address denomination)
        internal
        view
        returns (uint256, uint8)
    {
        IChainlinkAggregatorLike feed = feedRegistry.getFeed(asset, denomination);

        // Note: registry reverts with "Feed not found" for no registered feed

        (, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
        // TODO should we adjust this to <= also in other Product contracts?
        // TODO should we revert on any other place if encountered price is 0 or negative, or is this okay to do just here?
        if (price <= 0) {
            revert ChainlinkFeedReturnedNegativePrice({ feed: address(feed), price: price, updatedAt: updatedAt });
        }
        if (block.timestamp - updatedAt > MAX_CHAINLINK_FEED_PRICE_AGE) {
            revert ChainlinkFeedPriceTooOld({ feed: address(feed), updatedAt: updatedAt });
        }

        return (uint256(price), feed.decimals());
    }

    /**
     * @notice Sync price decimals to the higher one.
     * @param price1 Price one to be scaled.
     * @param decimals1 Decimals of the price one.
     * @param price2 Price two to be scaled.
     * @param decimals2 Decimals of the price two.
     * @return Synced price one.
     * @return Synced price two.
     * @return Synced price decimals.
     */
    function syncDecimalsUp(uint256 price1, uint8 decimals1, uint256 price2, uint8 decimals2)
        internal
        pure
        returns (uint256, uint256, uint8)
    {
        uint8 syncedDecimals = uint8(Math.max(decimals1, decimals2));
        return (
            price1 * 10 ** (syncedDecimals - decimals1),
            price2 * 10 ** (syncedDecimals - decimals2),
            syncedDecimals
        );
    }

}



// ============================================================
// FILE: src/periphery/auxiliary/PWNRevokedNonce.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";


/**
 * @title PWN Revoked Nonce
 * @notice Contract holding revoked nonces.
 */
contract PWNRevokedNonce {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Access tag that needs to be assigned to a caller in PWN Hub
     * to call functions that revoke nonces on behalf of an owner.
     */
    bytes32 public immutable accessTag;

    /**
     * @notice PWN Hub contract.
     * @dev Addresses revoking nonces on behalf of an owner need to have an access tag in PWN Hub.
     */
    PWNHub public immutable hub;

    /** @notice Mapping of revoked nonces by an address. Every address has its own nonce space.*/
    mapping (address => mapping (uint256 => mapping (uint256 => bool))) private _revokedNonce;

    /** @notice Mapping of current nonce space for an address.*/
    mapping (address => uint256) private _nonceSpace;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when a nonce is revoked.*/
    event NonceRevoked(address indexed owner, uint256 indexed nonceSpace, uint256 indexed nonce);
    /** @notice Emitted when a nonce is revoked.*/
    event NonceSpaceRevoked(address indexed owner, uint256 indexed nonceSpace);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when trying to revoke a nonce that is already revoked.*/
    error NonceAlreadyRevoked(address addr, uint256 nonceSpace, uint256 nonce);

    /**
     * @notice Thrown when nonce is currently not usable.
     * @dev Maybe nonce is revoked or not in the current nonce space.
     */
    error NonceNotUsable(address addr, uint256 nonceSpace, uint256 nonce);


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyWithHubTag() {
        if (!hub.hasTag(msg.sender, accessTag))
            revert AddressMissingHubTag({ addr: msg.sender, tag: accessTag });
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _hub, bytes32 _accessTag) {
        accessTag = _accessTag;
        hub = PWNHub(_hub);
    }


    /*----------------------------------------------------------*|
    |*  # NONCE                                                 *|
    |*----------------------------------------------------------*/

    /**
     * @notice Revoke callers nonce in the current nonce space.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(uint256 nonce) external {
        _revokeNonce(msg.sender, _nonceSpace[msg.sender], nonce);
    }

    /**
     * @notice Revoke multiple caller nonces in the current nonce space.
     * @param nonces List of nonces to be revoked.
     */
    function revokeNonces(uint256[] calldata nonces) external {
        uint256 nonceSpace = _nonceSpace[msg.sender];
        for (uint256 i; i < nonces.length; ++i) {
            _revokeNonce(msg.sender, nonceSpace, nonces[i]);
        }
    }

    /**
     * @notice Revoke caller nonce in a nonce space.
     * @param nonceSpace Nonce space where a nonce will be revoked.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(uint256 nonceSpace, uint256 nonce) external {
        _revokeNonce(msg.sender, nonceSpace, nonce);
    }

    /**
     * @notice Revoke a nonce in the current nonce space on behalf of an owner.
     * @dev Only an address with associated access tag in PWN Hub can call this function.
     * @param owner Owner address of a revoking nonce.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(address owner, uint256 nonce) external onlyWithHubTag {
        _revokeNonce(owner, _nonceSpace[owner], nonce);
    }

    /**
     * @notice Revoke a nonce in a nonce space on behalf of an owner.
     * @dev Only an address with associated access tag in PWN Hub can call this function.
     * @param owner Owner address of a revoking nonce.
     * @param nonceSpace Nonce space where a nonce will be revoked.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(address owner, uint256 nonceSpace, uint256 nonce) external onlyWithHubTag {
        _revokeNonce(owner, nonceSpace, nonce);
    }

    /**
     * @notice Internal function to revoke a nonce in a nonce space.
     */
    function _revokeNonce(address owner, uint256 nonceSpace, uint256 nonce) private {
        if (_revokedNonce[owner][nonceSpace][nonce]) {
            revert NonceAlreadyRevoked({ addr: owner, nonceSpace: nonceSpace, nonce: nonce });
        }
        _revokedNonce[owner][nonceSpace][nonce] = true;
        emit NonceRevoked(owner, nonceSpace, nonce);
    }

    /**
     * @notice Return true if owners nonce is revoked in the given nonce space.
     * @dev Do not use this function to check if nonce is usable.
     *      Use `isNonceUsable` instead, which checks nonce space as well.
     * @param owner Address of a nonce owner.
     * @param nonceSpace Value of a nonce space.
     * @param nonce Value of a nonce.
     * @return True if nonce is revoked.
     */
    function isNonceRevoked(address owner, uint256 nonceSpace, uint256 nonce) external view returns (bool) {
        return _revokedNonce[owner][nonceSpace][nonce];
    }

    /**
     * @notice Return true if owners nonce is usable. Nonce is usable if it is not revoked and in the current nonce space.
     * @param owner Address of a nonce owner.
     * @param nonceSpace Value of a nonce space.
     * @param nonce Value of a nonce.
     * @return True if nonce is usable.
     */
    function isNonceUsable(address owner, uint256 nonceSpace, uint256 nonce) external view returns (bool) {
        if (_nonceSpace[owner] != nonceSpace)
            return false;

        return !_revokedNonce[owner][nonceSpace][nonce];
    }


    /*----------------------------------------------------------*|
    |*  # NONCE SPACE                                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Revoke all nonces in the current nonce space and increment nonce space.
     * @dev Caller is used as a nonce owner.
     * @return New nonce space.
     */
    function revokeNonceSpace() external returns (uint256) {
        emit NonceSpaceRevoked(msg.sender, _nonceSpace[msg.sender]);
        return ++_nonceSpace[msg.sender];
    }

    /**
     * @notice Return current nonce space for an address.
     * @param owner Address of a nonce owner.
     * @return Current nonce space.
     */
    function currentNonceSpace(address owner) external view returns (uint256) {
        return _nonceSpace[owner];
    }

}



// ============================================================
// FILE: src/periphery/auxiliary/PWNUtilizedCredit.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHub } from "pwn/core/hub/PWNHub.sol";


/**
 * @title PWN Utilized Credit Contract
 * @notice Contract holding utilized credit.
 */
contract PWNUtilizedCredit {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Access tag that needs to be assigned to a caller in PWN Hub
     * to call functions that update utilized credit.
     */
    bytes32 public immutable accessTag;

    /**
     * @notice PWN Hub contract.
     * @dev Addresses updating utilized credit need to have an access tag in PWN Hub.
     */
    PWNHub public immutable hub;

    /**
     * @notice Mapping of credit utilized by an id with defined available credit limit.
     * (owner => id => utilized credit)
     */
    mapping (address => mapping (bytes32 => uint256)) public utilizedCredit;


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when an id would exceed the available credit limit.*/
    error AvailableCreditLimitExceeded(address owner, bytes32 id, uint256 utilized, uint256 limit);


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyWithHubTag() {
        if (!hub.hasTag(msg.sender, accessTag))
            revert AddressMissingHubTag({ addr: msg.sender, tag: accessTag });
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _hub, bytes32 _accessTag) {
        accessTag = _accessTag;
        hub = PWNHub(_hub);
    }


    /*----------------------------------------------------------*|
    |*  # UTILIZED CREDIT                                       *|
    |*----------------------------------------------------------*/

    /**
     * @notice Update utilized credit for an owner with an id.
     * @dev Function will revert if utilized credit would exceed the available credit limit.
     * @param owner Owner of the utilized credit.
     * @param id Id of the utilized credit.
     * @param amount Amount to update utilized credit.
     * @param limit Available credit limit.
     */
    function utilizeCredit(address owner, bytes32 id, uint256 amount, uint256 limit) external onlyWithHubTag {
        uint256 extendedAmount = utilizedCredit[owner][id] + amount;
        if (extendedAmount > limit) {
            revert AvailableCreditLimitExceeded({ owner: owner, id: id, utilized: extendedAmount, limit: limit });
        }

        utilizedCredit[owner][id] = extendedAmount;
    }

}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (interfaces/IERC20.sol)

pragma solidity ^0.8.0;

import "../token/ERC20/IERC20.sol";



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (interfaces/IERC721.sol)

pragma solidity ^0.8.0;

import "../token/ERC721/IERC721.sol";



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/interfaces/IERC1155.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (interfaces/IERC1155.sol)

pragma solidity ^0.8.0;

import "../token/ERC1155/IERC1155.sol";



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.4) (token/ERC20/extensions/IERC20Permit.sol)

pragma solidity ^0.8.0;

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
// FILE: lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.3) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../extensions/IERC20Permit.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, oldAllowance + value));
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, oldAllowance - value));
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeWithSelector(token.approve.selector, spender, value);

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, 0));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Use a ERC-2612 signature to set the `owner` approval toward `spender` on `token`.
     * Revert on invalid signature.
     */
    function safePermit(
        IERC20Permit token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = token.nonces(owner);
        token.permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = token.nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        require(returndata.length == 0 || abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return
            success && (returndata.length == 0 || abi.decode(returndata, (bool))) && Address.isContract(address(token));
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/introspection/ERC165Checker.sol)

pragma solidity ^0.8.0;

import "./IERC165.sol";

/**
 * @dev Library used to query support of an interface declared via {IERC165}.
 *
 * Note that these functions return the actual result of the query: they do not
 * `revert` if an interface is not supported. It is up to the caller to decide
 * what to do in these cases.
 */
library ERC165Checker {
    // As per the EIP-165 spec, no interface should ever match 0xffffffff
    bytes4 private constant _INTERFACE_ID_INVALID = 0xffffffff;

    /**
     * @dev Returns true if `account` supports the {IERC165} interface.
     */
    function supportsERC165(address account) internal view returns (bool) {
        // Any contract that implements ERC165 must explicitly indicate support of
        // InterfaceId_ERC165 and explicitly indicate non-support of InterfaceId_Invalid
        return
            supportsERC165InterfaceUnchecked(account, type(IERC165).interfaceId) &&
            !supportsERC165InterfaceUnchecked(account, _INTERFACE_ID_INVALID);
    }

    /**
     * @dev Returns true if `account` supports the interface defined by
     * `interfaceId`. Support for {IERC165} itself is queried automatically.
     *
     * See {IERC165-supportsInterface}.
     */
    function supportsInterface(address account, bytes4 interfaceId) internal view returns (bool) {
        // query support of both ERC165 as per the spec and support of _interfaceId
        return supportsERC165(account) && supportsERC165InterfaceUnchecked(account, interfaceId);
    }

    /**
     * @dev Returns a boolean array where each value corresponds to the
     * interfaces passed in and whether they're supported or not. This allows
     * you to batch check interfaces for a contract where your expectation
     * is that some interfaces may not be supported.
     *
     * See {IERC165-supportsInterface}.
     *
     * _Available since v3.4._
     */
    function getSupportedInterfaces(
        address account,
        bytes4[] memory interfaceIds
    ) internal view returns (bool[] memory) {
        // an array of booleans corresponding to interfaceIds and whether they're supported or not
        bool[] memory interfaceIdsSupported = new bool[](interfaceIds.length);

        // query support of ERC165 itself
        if (supportsERC165(account)) {
            // query support of each interface in interfaceIds
            for (uint256 i = 0; i < interfaceIds.length; i++) {
                interfaceIdsSupported[i] = supportsERC165InterfaceUnchecked(account, interfaceIds[i]);
            }
        }

        return interfaceIdsSupported;
    }

    /**
     * @dev Returns true if `account` supports all the interfaces defined in
     * `interfaceIds`. Support for {IERC165} itself is queried automatically.
     *
     * Batch-querying can lead to gas savings by skipping repeated checks for
     * {IERC165} support.
     *
     * See {IERC165-supportsInterface}.
     */
    function supportsAllInterfaces(address account, bytes4[] memory interfaceIds) internal view returns (bool) {
        // query support of ERC165 itself
        if (!supportsERC165(account)) {
            return false;
        }

        // query support of each interface in interfaceIds
        for (uint256 i = 0; i < interfaceIds.length; i++) {
            if (!supportsERC165InterfaceUnchecked(account, interfaceIds[i])) {
                return false;
            }
        }

        // all interfaces supported
        return true;
    }

    /**
     * @notice Query if a contract implements an interface, does not check ERC165 support
     * @param account The address of the contract to query for support of an interface
     * @param interfaceId The interface identifier, as specified in ERC-165
     * @return true if the contract at account indicates support of the interface with
     * identifier interfaceId, false otherwise
     * @dev Assumes that account contains a contract that supports ERC165, otherwise
     * the behavior of this method is undefined. This precondition can be checked
     * with {supportsERC165}.
     *
     * Some precompiled contracts will falsely indicate support for a given interface, so caution
     * should be exercised when using this function.
     *
     * Interface identification is specified in ERC-165.
     */
    function supportsERC165InterfaceUnchecked(address account, bytes4 interfaceId) internal view returns (bool) {
        // prepare call
        bytes memory encodedParams = abi.encodeWithSelector(IERC165.supportsInterface.selector, interfaceId);

        // perform static call
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly {
            success := staticcall(30000, account, add(encodedParams, 0x20), mload(encodedParams), 0x00, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0x00)
        }

        return success && returnSize >= 0x20 && returnValue > 0;
    }
}



// ============================================================
// FILE: lib/MultiToken/src/interfaces/ICryptoKitties.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title CryptoKitties Interface
 * @dev CryptoKitties Interface ID is 0x9a20483d.
 */
interface ICryptoKitties {
    // Required methods
    function totalSupply() external view returns (uint256 total);
    function balanceOf(address _owner) external view returns (uint256 balance);
    function ownerOf(uint256 _tokenId) external view returns (address owner);
    function approve(address _to, uint256 _tokenId) external;
    function transfer(address _to, uint256 _tokenId) external;
    function transferFrom(address _from, address _to, uint256 _tokenId) external;

    // Optional
    function name() external view returns (string memory name);
    function symbol() external view returns (string memory symbol);
    function tokensOfOwner(address _owner) external view returns (uint256[] memory tokenIds);
    function tokenMetadata(uint256 _tokenId, string memory _preferredTransport) external view returns (string memory infoUrl);

    // Events
    event Transfer(address from, address to, uint256 tokenId);
    event Approval(address owner, address approved, uint256 tokenId);

    // ERC-165 Compatibility (https://github.com/ethereum/EIPs/issues/165)
    // Is not part of the interface id
    function supportsInterface(bytes4 _interfaceID) external view returns (bool);
}



// ============================================================
// FILE: lib/MultiToken/src/interfaces/IMultiTokenCategoryRegistry.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
* @title MultiToken Category Registry Interface
* @notice Interface for the MultiToken Category Registry.
* @dev Category Registry Interface ID is 0xc37a4a01.
*/
interface IMultiTokenCategoryRegistry {

    /**
    * @notice Emitted when a category is registered for an asset address.
    * @param assetAddress Address of an asset to which category is registered.
    * @param category A raw value of a MultiToken Category registered for an asset.
    */
    event CategoryRegistered(address indexed assetAddress, uint8 indexed category);

    /**
    * @notice Emitted when a category is unregistered for an asset address.
    * @param assetAddress Address of an asset to which category is unregistered.
    */
    event CategoryUnregistered(address indexed assetAddress);

    /**
     * @notice Register a MultiToken Category value to an asset address.
     * @param assetAddress Address of an asset to which category is registered.
     * @param category A raw value of a MultiToken Category to register for an asset.
     */
    function registerCategoryValue(address assetAddress, uint8 category) external;

    /**
     * @notice Clear the stored category for the asset address.
     * @param assetAddress Address of an asset to which category is unregistered.
     */
    function unregisterCategoryValue(address assetAddress) external;

    /**
     * @notice Getter for a registered category value of a given asset address.
     * @param assetAddress Address of an asset to which category is requested.
     * @return Raw category value registered for the asset address.
     */
    function registeredCategoryValue(address assetAddress) external view returns (uint8);

}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (access/Ownable2Step.sol)

pragma solidity ^0.8.0;

import "./Ownable.sol";

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Ownable).
 */
abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public virtual {
        address sender = _msgSender();
        require(pendingOwner() == sender, "Ownable2Step: caller is not the new owner");
        _transferOwnership(sender);
    }
}



// ============================================================
// FILE: src/core/config/PWNConfig.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Ownable2StepUpgradeable } from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";

import { IStateFingerpringComputer } from "pwn/core/config/IStateFingerpringComputer.sol";


/**
 * @title PWN Config
 * @notice Contract holding configurable values of PWN protocol.
 * @dev Is intended to be used as a proxy via `TransparentUpgradeableProxy`.
 */
contract PWNConfig is Ownable2StepUpgradeable {

    string internal constant VERSION = "1.3";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    uint16 public constant MAX_FEE = 1000; // 10%

    /**
     * @notice Protocol fee value in basis points.
     * @dev Value of 100 is 1% fee.
     */
    uint16 public fee;

    /** @notice Address that collects protocol fees.*/
    address public feeCollector;

    /**
     * @notice Mapping of a loan contract address to LOAN token metadata uri.
     * @dev LOAN token minted by a loan contract will return metadata uri stored in this mapping.
     * If there is no metadata uri for a loan contract, default metadata uri will be used stored under address(0).
     */
    mapping (address => string) private _loanMetadataUri;

    /** @notice Mapping holding registered state fingerprint computer to an asset.*/
    mapping (address => address) private _sfComputerRegistry;

    /**
     * @notice Mapping holding registered pool adapter to a pool address.
     * @dev Deprecated.
     */
    mapping (address => address) private _poolAdapterRegistry;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when new fee value is set.*/
    event FeeUpdated(uint16 oldFee, uint16 newFee);
    /** @notice Emitted when new fee collector address is set.*/
    event FeeCollectorUpdated(address oldFeeCollector, address newFeeCollector);
    /** @notice Emitted when new LOAN token metadata uri is set.*/
    event LOANMetadataUriUpdated(address indexed loanContract, string newUri);
    /** @notice Emitted when new default LOAN token metadata uri is set.*/
    event DefaultLOANMetadataUriUpdated(string newUri);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when registering a computer which does not support the asset it is registered for.*/
    error InvalidComputerContract(address computer, address asset);
    /** @notice Thrown when trying to set a fee value higher than `MAX_FEE`.*/
    error InvalidFeeValue(uint256 fee, uint256 limit);
    /** @notice Thrown when trying to set a fee collector to zero address.*/
    error ZeroFeeCollector();
    /** @notice Thrown when trying to set a LOAN token metadata uri for zero address loan contract.*/
    error ZeroLoanContract();


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor() Ownable2StepUpgradeable() {
        // PWNConfig is used as a proxy. Use initializer to setup initial properties.
        _disableInitializers();
        _transferOwnership(address(0));
    }

    function initialize(address _owner, uint16 _fee, address _feeCollector) external initializer {
        require(_owner != address(0), "Owner is zero address");
        _transferOwnership(_owner);
        _setFeeCollector(_feeCollector);
        _setFee(_fee);
    }


    /*----------------------------------------------------------*|
    |*  # FEE MANAGEMENT                                        *|
    |*----------------------------------------------------------*/

    /**
     * @notice Set new protocol fee value.
     * @param _fee New fee value in basis points. Value of 100 is 1% fee.
     */
    function setFee(uint16 _fee) external onlyOwner {
        _setFee(_fee);
    }

    /**
     * @notice Internal implementation of setting new protocol fee value.
     * @param _fee New fee value in basis points. Value of 100 is 1% fee.
     */
    function _setFee(uint16 _fee) private {
        if (_fee > MAX_FEE)
            revert InvalidFeeValue({ fee: _fee, limit: MAX_FEE });

        uint16 oldFee = fee;
        fee = _fee;
        emit FeeUpdated(oldFee, _fee);
    }

    /**
     * @notice Set new fee collector address.
     * @param _feeCollector New fee collector address.
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        _setFeeCollector(_feeCollector);
    }

    /**
     * @notice Internal implementation of setting new fee collector address.
     * @param _feeCollector New fee collector address.
     */
    function _setFeeCollector(address _feeCollector) private {
        if (_feeCollector == address(0))
            revert ZeroFeeCollector();

        address oldFeeCollector = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(oldFeeCollector, _feeCollector);
    }


    /*----------------------------------------------------------*|
    |*  # LOAN METADATA                                         *|
    |*----------------------------------------------------------*/

    /**
     * @notice Set a LOAN token metadata uri for a specific loan contract.
     * @param loanContract Address of a loan contract.
     * @param metadataUri New value of LOAN token metadata uri for given `loanContract`.
     */
    function setLOANMetadataUri(address loanContract, string memory metadataUri) external onlyOwner {
        if (loanContract == address(0))
            // address(0) is used as a default metadata uri. Use `setDefaultLOANMetadataUri` to set default metadata uri.
            revert ZeroLoanContract();

        _loanMetadataUri[loanContract] = metadataUri;
        emit LOANMetadataUriUpdated(loanContract, metadataUri);
    }

    /**
     * @notice Set a default LOAN token metadata uri.
     * @param metadataUri New value of default LOAN token metadata uri.
     */
    function setDefaultLOANMetadataUri(string memory metadataUri) external onlyOwner {
        _loanMetadataUri[address(0)] = metadataUri;
        emit DefaultLOANMetadataUriUpdated(metadataUri);
    }

    /**
     * @notice Return a LOAN token metadata uri base on a loan contract that minted the token.
     * @param loanContract Address of a loan contract.
     * @return uri Metadata uri for given loan contract.
     */
    function loanMetadataUri(address loanContract) external view returns (string memory uri) {
        uri = _loanMetadataUri[loanContract];
        // If there is no metadata uri for a loan contract, use default metadata uri.
        if (bytes(uri).length == 0)
            uri = _loanMetadataUri[address(0)];
    }


    /*----------------------------------------------------------*|
    |*  # STATE FINGERPRINT COMPUTER                            *|
    |*----------------------------------------------------------*/

    /**
     * @notice Returns the state fingerprint computer for a given asset.
     * @param asset The asset for which the computer is requested.
     * @return The computer for the given asset.
     */
    function getStateFingerprintComputer(address asset) external view returns (IStateFingerpringComputer) {
        return IStateFingerpringComputer(_sfComputerRegistry[asset]);
    }

    /**
     * @notice Registers a state fingerprint computer for a given asset.
     * @param asset The asset for which the computer is registered.
     * @param computer The computer to be registered. Use address(0) to remove a computer.
     */
    function registerStateFingerprintComputer(address asset, address computer) external onlyOwner {
        if (computer != address(0))
            if (!IStateFingerpringComputer(computer).supportsToken(asset))
                revert InvalidComputerContract({ computer: computer, asset: asset });

        _sfComputerRegistry[asset] = computer;
    }

}



// ============================================================
// FILE: src/core/loan/hook/IPWNBorrowerCreateHook.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

bytes32 constant BORROWER_CREATE_HOOK_RETURN_VALUE = keccak256("PWNBorrowerCreateHook.onLoanCreated");

/**
 * @title IPWNBorrowerCreateHook
 * @notice Interface for borrower-side create hooks used by PWNLoan contracts.
 *
 * @dev This hook is called by the PWNLoan contract at loan origination to allow the borrower to execute custom logic
 * (e.g., collateral management, asset swaps, or additional setup) before the loan is finalized. This hook enables advanced flows
 * such as acquiring or "buying" the collateral with borrowed funds before it is locked as collateral in the loan. The hook must return
 * the keccak256 hash of "PWNBorrowerCreateHook.onLoanCreated" to confirm successful execution.
 */
interface IPWNBorrowerCreateHook {
    /**
     * @notice Called by PWNLoan at loan origination to execute borrower-side custom logic.
     * @param loanId The ID of the loan being created.
     * @param borrower The address of the borrower.
     * @param collateral The collateral asset being provided by the borrower.
     * @param creditAddress The address of the credit token used for the loan.
     * @param principal The principal amount of the loan.
     * @param borrowerData Additional data provided by the borrower for custom logic.
     * @return A keccak256 hash of "PWNBorrowerCreateHook.onLoanCreated".
     */
    function onLoanCreated(
        uint256 loanId,
        address borrower,
        MultiToken.Asset calldata collateral,
        address creditAddress,
        uint256 principal,
        bytes calldata borrowerData
    ) external returns (bytes32);
}



// ============================================================
// FILE: src/core/loan/hook/IPWNBorrowerCollateralRepaymentHook.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

bytes32 constant BORROWER_COLLATERAL_REPAYMENT_HOOK_RETURN_VALUE = keccak256("PWNBorrowerCollateralRepaymentHook.onLoanRepaid");

/**
 * @title IPWNBorrowerCollateralRepaymentHook
 * @notice Interface for borrower-side repayment hooks used by PWNLoan contracts.
 *
 * @dev This hook is called by the PWNLoan contract when the borrower decides to repay the full amount of a loan using their collateral.
 * At this point, the collateral is transferred into the hook contract, enabling advanced flows where the collateral itself is used to repay the loan.
 * The hook can implement logic to sell, unwrap, or otherwise utilize the accumulated value of the collateral to cover the outstanding debt.
 *
 * After the hook execution, the loan contract will transfer the full repayment amount from the hook contract. The hook must ensure
 * that the loan contract has the necessary approval to transfer the repayment amount in the credit token.
 *
 * The hook must return the keccak256 hash of "PWNBorrowerCollateralRepaymentHook.onLoanRepaid" to confirm successful execution.
 *
 * Implementing contracts must also implement the ERC721 and ERC1155 receiver interfaces, as the loan contract
 * transfers collateral using safe transfer functions. This ensures the hook can properly receive and handle NFT or multi-token collateral.
 */
interface IPWNBorrowerCollateralRepaymentHook {
    /**
     * @notice Called by PWNLoan when the borrower repays the full amount of a loan using their collateral.
     * @dev The collateral is transferred into the hook contract, enabling custom logic to sell, unwrap, or otherwise utilize
     * the collateral's value to cover the outstanding debt. After execution, the loan contract will transfer the full repayment
     * amount from the hook contract, so the hook must ensure the loan contract has approval for the repayment in the credit token.
     * @param borrower The address of the borrower.
     * @param collateral The collateral asset being received and managed by the hook.
     * @param creditAddress The address of the credit token used for the loan.
     * @param repayment The amount to be repaid by the borrower (must be approved for transfer by the loan contract).
     * @param borrowerData Additional data provided by the borrower for custom logic.
     * @return A keccak256 hash of "PWNBorrowerCollateralRepaymentHook.onLoanRepaid".
     */
    function onLoanRepaid(
        address borrower,
        MultiToken.Asset calldata collateral,
        address creditAddress,
        uint256 repayment,
        bytes calldata borrowerData
    ) external returns (bytes32);
}



// ============================================================
// FILE: src/core/loan/hook/IPWNLenderCreateHook.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

bytes32 constant LENDER_CREATE_HOOK_RETURN_VALUE = keccak256("PWNLenderCreateHook.onLoanCreated");

/**
 * @title IPWNLenderCreateHook
 * @notice Interface for lender-side create hooks used by PWNLoan contracts.
 *
 * @dev This hook is called by the PWNLoan contract at loan origination to allow the lender to execute custom logic
 * (e.g., on-deman funds withdrawal, asset swaps) before the loan is finalized. The hook must return
 * the keccak256 hash of "PWNLenderCreateHook.onLoanCreated" to confirm successful execution.
 */
interface IPWNLenderCreateHook {
    /**
     * @notice Called by PWNLoan at loan origination to execute lender-side custom logic.
     * @param loanId The ID of the loan being created.
     * @param lender The address of the lender.
     * @param creditAddress The address of the credit token used for the loan.
     * @param principal The principal amount of the loan.
     * @param lenderData Additional data provided by the lender for custom logic.
     * @return A keccak256 hash of "PWNLenderCreateHook.onLoanCreated".
     */
    function onLoanCreated(
        uint256 loanId,
        address lender,
        address creditAddress,
        uint256 principal,
        bytes calldata lenderData
    ) external returns (bytes32);
}



// ============================================================
// FILE: src/core/loan/hook/IPWNLenderRepaymentHook.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

bytes32 constant LENDER_REPAYMENT_HOOK_RETURN_VALUE = keccak256("PWNLenderRepaymentHook.onLoanRepaid");

/**
 * @title IPWNLenderRepaymentHook
 * @notice Interface for lender-side repayment hooks used by PWNLoan contracts.
 *
 * @dev This hook is called by the PWNLoan contract when a lender receives a repayment, allowing the lender to execute
 * custom logic (e.g., claim to lender address, deposit to external vault) upon repayment. The hook must return
 * the keccak256 hash of "PWNLenderRepaymentHook.onLoanRepaid" to confirm successful execution.
 */
interface IPWNLenderRepaymentHook {
    /**
     * @notice Called by PWNLoan when a lender receives a repayment to execute lender-side custom logic.
     * @param lender The address of the lender.
     * @param creditAddress The address of the credit token used for the loan.
     * @param repayment The amount repaid to the lender.
     * @param lenderData Additional data provided by the lender for custom logic.
     * @return A keccak256 hash of "PWNLenderRepaymentHook.onLoanRepaid".
     */
    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32);
}



// ============================================================
// FILE: src/core/loan/LOANStatus.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

library LOANStatus {
    uint8 constant DEAD = 0;
    uint8 constant RUNNING = 2;
    uint8 constant REPAID = 3;
    uint8 constant DEFAULTED = 4;
}



// ============================================================
// FILE: src/core/loan/PWNProposalManager.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MerkleProof } from "openzeppelin/utils/cryptography/MerkleProof.sol";

import { IPWNProposalModule } from "pwn/core/loan/module/IPWNProposalModule.sol";
import { PWNSignatureChecker } from "pwn/core/lib/PWNSignatureChecker.sol";


/**
 * @title PWNProposalManager
 * @notice Manages proposal and multiproposal verification for PWN protocol.
 */
contract PWNProposalManager {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes32 public constant MULTIPROPOSAL_DOMAIN_SEPARATOR = keccak256(abi.encode(keccak256("EIP712Domain(string name)"), keccak256("PWNMultiproposal")));
    bytes32 public constant MULTIPROPOSAL_TYPEHASH = keccak256("Multiproposal(bytes32 multiproposalMerkleRoot)");
    bytes32 public constant EIP712DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");

    /**
     * @notice Struct representing a multiproposal, identified by its Merkle root.
     * @param multiproposalMerkleRoot Merkle root of the multiproposal tree.
     */
    struct Multiproposal {
        bytes32 multiproposalMerkleRoot;
    }

    /** @notice Mapping to track if a proposal is acceptable for a given proposer.*/
    mapping (address => mapping (bytes32 => bool)) public isProposalAcceptable;
    /** @notice Mapping to track if a multiproposal is acceptable for a given proposer.*/
    mapping (address => mapping (bytes32 => bool)) public isMultiproposalAcceptable;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when a proposal is marked as acceptable.*/
    event ProposalAcceptable(bytes32 indexed proposalHash, address indexed proposer, address indexed proposalModule, bytes proposal);
    /** @notice Emitted when a proposal is marked as unacceptable.*/
    event ProposalUnacceptable(bytes32 indexed proposalHash);
    /** @notice Emitted when a multiproposal is marked as acceptable.*/
    event MultiproposalAcceptable(bytes32 indexed multiproposalHash, address indexed proposer, bytes32 multiproposalMerkleRoot);
    /** @notice Emitted when a multiproposal is marked as unacceptable.*/
    event MultiproposalUnacceptable(bytes32 indexed multiproposalHash);


    /*----------------------------------------------------------*|
    |*  # ON-CHAIN PROPOSAL                                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Mark a proposal as acceptable for the sender.
     * @param proposalModule The proposal module contract.
     * @param proposalData Raw proposal data.
     * @return proposalHash Hash of the proposal marked as acceptable.
     */
    function makeProposalAcceptable(
        IPWNProposalModule proposalModule,
        bytes calldata proposalData
    ) external returns (bytes32 proposalHash) {
        proposalHash = hashProposal(proposalModule, proposalData);
        isProposalAcceptable[msg.sender][proposalHash] = true;
        emit ProposalAcceptable(proposalHash, msg.sender, address(proposalModule), proposalData);
    }

    /**
     * @notice Mark a proposal as unacceptable for the sender.
     * @param proposalHash Hash of the proposal to mark as unacceptable.
     */
    function makeProposalUnacceptable(bytes32 proposalHash) external {
        isProposalAcceptable[msg.sender][proposalHash] = false;
        emit ProposalUnacceptable(proposalHash);
    }

    /**
     * @notice Mark a multiproposal as acceptable for the sender.
     * @param multiproposal The multiproposal struct to mark as acceptable.
     * @return multiproposalHash Hash of the multiproposal marked as acceptable.
     */
    function makeMultiproposalAcceptable(Multiproposal memory multiproposal) external returns (bytes32 multiproposalHash) {
        multiproposalHash = hashMultiproposal(multiproposal);
        isMultiproposalAcceptable[msg.sender][multiproposalHash] = true;
        emit MultiproposalAcceptable(multiproposalHash, msg.sender, multiproposal.multiproposalMerkleRoot);
    }

    /**
     * @notice Mark a multiproposal as unacceptable for the sender.
     * @param multiproposalHash Hash of the multiproposal to mark as unacceptable.
     */
    function makeMultiproposalUnacceptable(bytes32 multiproposalHash) external {
        isMultiproposalAcceptable[msg.sender][multiproposalHash] = false;
        emit MultiproposalUnacceptable(multiproposalHash);
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL HASHING                                      *|
    |*----------------------------------------------------------*/

    /**
     * @notice Compute the EIP-712 hash for a proposal using its module and data.
     * @param proposalModule The proposal module contract.
     * @param proposalData Raw proposal data.
     * @return proposalHash Hash of the proposal.
     */
    function hashProposal(
        IPWNProposalModule proposalModule,
        bytes calldata proposalData
    ) public view returns (bytes32 proposalHash) {
        (string memory name, string memory version) = proposalModule.nameAndVersion();
        proposalHash = keccak256(abi.encodePacked(
            hex"1901",
            keccak256(abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256(abi.encodePacked(name)),
                keccak256(abi.encodePacked(version)),
                block.chainid,
                address(proposalModule)
            )),
            proposalModule.hashProposalTypedData(proposalData)
        ));
    }

    /**
     * @notice Compute the EIP-712 hash for a multiproposal struct.
     * @param multiproposal The multiproposal struct to hash.
     * @return Hash of the multiproposal.
     */
    function hashMultiproposal(Multiproposal memory multiproposal) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901", MULTIPROPOSAL_DOMAIN_SEPARATOR, keccak256(abi.encodePacked(
                MULTIPROPOSAL_TYPEHASH, abi.encode(multiproposal)
            ))
        ));
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL SIGNATURE CHECKING                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Internal function to check the validity of a proposal or multiproposal signature.
     * @dev Reverts if the signature is invalid or the proposal/multiproposal is not marked as acceptable.
     * @param proposer Address of the proposer.
     * @param proposalHash Hash of the proposal.
     * @param proposalInclusionProof Merkle proof for multiproposal inclusion (empty for single proposal).
     * @param signature Signature to verify.
     */
    function _checkProposalSignature(
        address proposer,
        bytes32 proposalHash,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) internal view {
        // Check proposal signature or that it was made on-chain
        if (proposalInclusionProof.length == 0) {
            // Single proposal signature
            if (!isProposalAcceptable[proposer][proposalHash]) {
                if (!PWNSignatureChecker.isValidSignatureNow(proposer, proposalHash, signature)) {
                    revert PWNSignatureChecker.InvalidSignature({ signer: proposer, digest: proposalHash });
                }
            }
        } else {
            // Multiproposal signature
            bytes32 multiproposalHash = hashMultiproposal(
                Multiproposal({
                    multiproposalMerkleRoot: MerkleProof.processProofCalldata({
                        proof: proposalInclusionProof,
                        leaf: proposalHash
                    })
                })
            );
            if (!isMultiproposalAcceptable[proposer][multiproposalHash]) {
                if (!PWNSignatureChecker.isValidSignatureNow(proposer, multiproposalHash, signature)) {
                    revert PWNSignatureChecker.InvalidSignature({ signer: proposer, digest: multiproposalHash });
                }
            }
        }
    }

}



// ============================================================
// FILE: src/core/loan/PWNVault.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IERC721Receiver } from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import { IERC1155Receiver, IERC165 } from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";


/**
 * @title PWN Vault
 * @notice Base contract for transferring and managing collateral and loan assets in PWN protocol.
 * @dev Loan contracts inherits PWN Vault to act as a Vault for its loan type.
 */
abstract contract PWNVault is IERC721Receiver, IERC1155Receiver {
    using MultiToken for MultiToken.Asset;

    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when asset transfer happens from an `origin` address to a vault.*/
    event VaultPull(MultiToken.Asset asset, address indexed origin);
    /** @notice Emitted when asset transfer happens from a vault to a `beneficiary` address.*/
    event VaultPush(MultiToken.Asset asset, address indexed beneficiary);
    /** @notice Emitted when asset transfer happens from an `origin` address to a `beneficiary` address.*/
    event VaultPushFrom(MultiToken.Asset asset, address indexed origin, address indexed beneficiary);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when the Vault receives an asset that is not transferred by the Vault itself.*/
    error UnsupportedTransferFunction();
    /** @notice Thrown when an asset transfer is incomplete.*/
    error IncompleteTransfer();
    /** @notice Thrown when an asset transfer source and destination address are the same.*/
    error VaultTransferSameSourceAndDestination(address addr);


    /*----------------------------------------------------------*|
    |*  # TRANSFER FUNCTIONS                                    *|
    |*----------------------------------------------------------*/

    /**
     * @notice Function pulling an asset into a vault.
     * @dev The function assumes a prior token approval to a vault address.
     * @param asset An asset construct - for a definition see { MultiToken dependency lib }.
     * @param origin Borrower address that is transferring collateral to Vault or repaying a loan.
     */
    function _pull(MultiToken.Asset memory asset, address origin) internal {
        uint256 originalBalance = asset.balanceOf(address(this));

        asset.transferAssetFrom(origin, address(this));
        _checkTransfer({
            asset: asset,
            originalBalance: originalBalance,
            checkedAddress: address(this),
            counterPartyAddress: origin
        });

        emit VaultPull(asset, origin);
    }

    /**
     * @notice Function pushing an asset from a vault to a recipient.
     * @dev This is used for claiming a paid back loan or a defaulted collateral, or returning collateral to a borrower.
     * @param asset An asset construct - for a definition see { MultiToken dependency lib }.
     * @param beneficiary An address of a recipient of an asset.
     */
    function _push(MultiToken.Asset memory asset, address beneficiary) internal {
        uint256 originalBalance = asset.balanceOf(beneficiary);

        asset.safeTransferAssetFrom(address(this), beneficiary);
        _checkTransfer({
            asset: asset,
            originalBalance: originalBalance,
            checkedAddress: beneficiary,
            counterPartyAddress: address(this)
        });

        emit VaultPush(asset, beneficiary);
    }

    /**
     * @notice Function pushing an asset from an origin address to a beneficiary address.
     * @dev The function assumes a prior token approval to a vault address.
     * @param asset An asset construct - for a definition see { MultiToken dependency lib }.
     * @param origin An address of a lender who is providing a loan asset.
     * @param beneficiary An address of the recipient of an asset.
     */
    function _pushFrom(MultiToken.Asset memory asset, address origin, address beneficiary) internal {
        uint256 originalBalance = asset.balanceOf(beneficiary);

        asset.safeTransferAssetFrom(origin, beneficiary);
        _checkTransfer({
            asset: asset,
            originalBalance: originalBalance,
            checkedAddress: beneficiary,
            counterPartyAddress: origin
        });

        emit VaultPushFrom(asset, origin, beneficiary);
    }

    function _checkTransfer(
        MultiToken.Asset memory asset,
        uint256 originalBalance,
        address checkedAddress,
        address counterPartyAddress
    ) private view {
        if (checkedAddress == counterPartyAddress) {
            revert VaultTransferSameSourceAndDestination({ addr: checkedAddress });
        }

        uint256 expectedBalance = originalBalance + asset.getTransferAmount();
        if (expectedBalance != asset.balanceOf(checkedAddress)) {
            revert IncompleteTransfer();
        }
    }


    /*----------------------------------------------------------*|
    |*  # ERC721/1155 RECEIVED HOOKS                            *|
    |*----------------------------------------------------------*/

    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * @return `IERC721Receiver.onERC721Received.selector` if transfer is allowed
     */
    function onERC721Received(
        address operator,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) override external view returns (bytes4) {
        if (operator != address(this))
            revert UnsupportedTransferFunction();

        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     * To accept the transfer, this must return
     * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     * (i.e. 0xf23a6e61, or its own function selector).
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(
        address operator,
        address /*from*/,
        uint256 /*id*/,
        uint256 /*value*/,
        bytes calldata /*data*/
    ) override external view returns (bytes4) {
        if (operator != address(this))
            revert UnsupportedTransferFunction();

        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @dev Handles the receipt of a multiple ERC1155 token types. This function
     * is called at the end of a `safeBatchTransferFrom` after the balances have
     * been updated. To accept the transfer(s), this must return
     * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     * (i.e. 0xbc197c81, or its own function selector).
     * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] calldata /*ids*/,
        uint256[] calldata /*values*/,
        bytes calldata /*data*/
    ) override external pure returns (bytes4) {
        revert UnsupportedTransferFunction();
    }


    /*----------------------------------------------------------*|
    |*  # SUPPORTED INTERFACES                                  *|
    |*----------------------------------------------------------*/

    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external pure virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId;
    }

}



// ============================================================
// FILE: src/core/token/IERC5646.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IERC5646
 * @notice Interface of the ERC5646 standard, as defined in the https://eips.ethereum.org/EIPS/eip-5646.
 */
interface IERC5646 {

    /**
     * @notice Function to return current token state fingerprint.
     * @param tokenId Id of a token state in question.
     * @return Current token state fingerprint.
     */
    function getStateFingerprint(uint256 tokenId) external view returns (bytes32);

}



// ============================================================
// FILE: src/core/token/IPWNLoanMetadataProvider.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IPWNLoanMetadataProvider
 * @notice Interface for a provider of a LOAN token metadata.
 * @dev Loan contracts should implement this interface.
 */
interface IPWNLoanMetadataProvider {

    /**
     * @notice Get a loan metadata uri for a LOAN token minted by this contract.
     * @return LOAN token metadata uri.
     */
    function loanMetadataUri() external view returns (string memory);

}



// ============================================================
// FILE: src/core/token/PWNLOAN.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { ERC721 } from "openzeppelin/token/ERC721/ERC721.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IERC5646 } from "pwn/core/token/IERC5646.sol";
import { IPWNLoanMetadataProvider } from "pwn/core/token/IPWNLoanMetadataProvider.sol";


/**
 * @title PWN LOAN token
 * @notice A LOAN token representing a loan in PWN protocol.
 * @dev Token doesn't hold any loan logic, just an address of a loan contract that minted the LOAN token.
 *      PWN LOAN token is shared between all loan contracts.
 */
contract PWNLOAN is ERC721, IERC5646 {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    PWNHub public immutable hub;

    /** @dev Last used LOAN id. First LOAN id is 1. This value is incremental.*/
    uint256 public lastLoanId;

    /** @dev Mapping of a LOAN id to a loan contract that minted the LOAN token.*/
    mapping (uint256 => address) public loanContract;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when a new LOAN token is minted.*/
    event LOANMinted(uint256 indexed loanId, address indexed loanContract, address indexed owner);
    /** @notice Emitted when a LOAN token is burned.*/
    event LOANBurned(uint256 indexed loanId);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when `PWNLOAN.burn` caller is not a loan contract that minted the LOAN token.*/
    error InvalidLoanContractCaller();
    /** @notice Thrown when caller is missing a PWN Hub tag.*/
    error CallerMissingHubTag(bytes32 tag);


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyActiveLoan() {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN))
            revert CallerMissingHubTag({ tag: PWNHubTags.ACTIVE_LOAN });
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _hub) ERC721("PWN LOAN", "LOAN") {
        hub = PWNHub(_hub);
    }


    /*----------------------------------------------------------*|
    |*  # TOKEN LIFECYCLE                                       *|
    |*----------------------------------------------------------*/

    /**
     * @notice Mint a new LOAN token.
     * @dev Only an address with associated `ACTIVE_LOAN` tag in PWN Hub can call this function.
     * @param owner Address of a LOAN token receiver.
     * @return loanId Id of a newly minted LOAN token.
     */
    function mint(address owner) external onlyActiveLoan returns (uint256 loanId) {
        loanId = ++lastLoanId;
        loanContract[loanId] = msg.sender;
        _mint(owner, loanId);
        emit LOANMinted(loanId, msg.sender, owner);
    }

    /**
     * @notice Burn a LOAN token.
     * @dev Any address that is associated with given loan id can call this function.
     * It is enabled to let deprecated loan contracts repay and claim existing loans.
     * @param loanId Id of a LOAN token to be burned.
     */
    function burn(uint256 loanId) external {
        if (loanContract[loanId] != msg.sender)
            revert InvalidLoanContractCaller();

        delete loanContract[loanId];
        _burn(loanId);
        emit LOANBurned(loanId);
    }


    /*----------------------------------------------------------*|
    |*  # METADATA                                              *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return a LOAN token metadata uri base on a loan contract that minted the token.
     * @param tokenId Id of a LOAN token.
     * @return Metadata uri for given token id (loan id).
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        return IPWNLoanMetadataProvider(loanContract[tokenId]).loanMetadataUri();
    }


    /*----------------------------------------------------------*|
    |*  # ERC5646                                               *|
    |*----------------------------------------------------------*/

    /** @dev See {IERC5646-getStateFingerprint}.*/
    function getStateFingerprint(uint256 tokenId) external view virtual override returns (bytes32) {
        address _loanContract = loanContract[tokenId];

        if (_loanContract == address(0))
            return bytes32(0);

        return IERC5646(_loanContract).getStateFingerprint(tokenId);
    }


    /*----------------------------------------------------------*|
    |*  # ERC165                                                *|
    |*----------------------------------------------------------*/

    /** @dev See {IERC165-supportsInterface}.*/
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC5646).interfaceId;
    }

}



// ============================================================
// FILE: src/core/loan/module/IPWNProposalModule.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { LoanTerms } from "pwn/core/loan/LoanTerms.sol";

/**
 * @title IPWNProposalModule
 * @dev Interface for the Proposal Module within the PWN Protocol's loan core system.
 * This module is responsible for handling proposals related to loan agreements,
 * such as creating, managing, and validating loan proposals between parties.
 * It defines the essential functions that must be implemented to facilitate
 * secure and flexible negotiation of loan terms, ensuring that proposals
 * adhere to protocol standards and can be integrated with other modules.
 * The Proposal Module serves as a key component in the workflow of decentralized
 * lending, enabling users to interact with loan offers and requests in a trustless manner.
 */
interface IPWNProposalModule {

    /**
     * @notice Returns the name and version of the proposal module.
     * @dev This function provides metadata about the module for identification and compatibility purposes.
     * @return name The name of the proposal module.
     * @return version The version of the proposal module.
     */
    function nameAndVersion() external view returns (string memory name, string memory version);

    /**
     * @notice Hashes typed proposal data.
     * @param proposalData Encoded proposal data.
     * @return The hash of the proposal data.
     */
    function hashProposalTypedData(bytes calldata proposalData) external view returns (bytes32);

    /**
     * @notice Accept a loan proposal and return the agreed loan terms.
     * @param loanId Unique identifier for the loan created from the proposal.
     * @param acceptor Address accepting the proposal.
     * @param proposer Address of the proposer who created the proposal.
     * @param proposalData Encoded proposal data.
     * @return loanTerms LoanTerms struct containing the agreed loan parameters.
     */
    function acceptProposal(
        uint256 loanId,
        address acceptor,
        address proposer,
        bytes calldata proposalData
    ) external returns (LoanTerms memory loanTerms);

}



// ============================================================
// FILE: src/core/loan/module/IPWNInterestModule.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IPWNInterestModule
 * @notice Interface for PWN interest modules used by the PWNLoan contract.
 *
 * @dev This module is set per-loan at origination and is immutable for the loan's lifetime.
 * The PWNLoan contract calls the `interest` function to calculate the interest accrued since the last update.
 * The module must use the `lastUpdateTimestamp` (fetched from the loan contract at the provided address)
 * to ensure only interest accrued since the last update is returned.
 *
 * Implementations do not have to account for unpaid accrued interest before the last update, as it is added to the total debt
 * by the loan contract. If the implementation computes interest only from the principal amount, it can safely ignore previously accrued interest.
 * Only if the module's logic requires it for its own computation should it consider previously accrued interest.
 *
 * The `interest` function MUST NOT revert. If the call to this function reverts, it will be interpreted
 * by the loan contract as returning zero interest accrued. Always return a value.
 */
interface IPWNInterestModule {
    /**
     * @notice Returns the interest accrued for a loan since its last update.
     * @dev The implementation must fetch the `lastUpdateTimestamp` from the loan contract
     * and calculate interest only for the period after this timestamp.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return The amount of interest accrued since the last update timestamp.
     */
    function interest(address loanContract, uint256 loanId) external view returns (uint256);
}



// ============================================================
// FILE: src/core/loan/module/IPWNDefaultModule.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IPWNDefaultModule
 * @notice Interface for PWN default modules used by the PWNLoan contract.
 *
 * @dev This module is set per-loan at origination and is immutable for the loan's lifetime.
 * The PWNLoan contract calls the `isDefaulted` function to determine if a loan is in default.
 * The module must use the loan's state (fetched from the loan contract at the provided address)
 * to evaluate whether default conditions are met (e.g., time-based, debt limit, or other criteria).
 *
 * The `isDefaulted` function MUST NOT revert. If the call to this function reverts, it will be interpreted
 * by the loan contract as returning false (i.e., the loan is not in default). Always return a boolean value.
 */
interface IPWNDefaultModule {
    /**
     * @notice Returns whether the loan is currently in default.
     * @dev The implementation must fetch relevant loan state from the loan contract
     * and evaluate default conditions according to the module's logic.
     * @param loanContract The address of the PWNLoan contract managing the loan.
     * @param loanId The unique identifier of the loan.
     * @return True if the loan is in default, false otherwise.
     */
    function isDefaulted(address loanContract, uint256 loanId) external view returns (bool);
}



// ============================================================
// FILE: src/core/loan/module/IPWNLiquidationModule.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

/**
 * @title IPWNLiquidationModule
 * @notice Interface for PWN liquidation modules used by the PWNLoan contract.
 *
 * @dev This module is set per-loan at origination and is immutable for the loan's lifetime.
 * When a loan is in default, as determined by the default module, the Loan contract calls the liquidation module
 * to execute the liquidation process. The collateral is transferred to the liquidation module, which is then responsible
 * for handling the liquidation (e.g., auction, direct sale, or other custom logic).
 *
 * The liquidation module can return any amount as the liquidation amount, including values less than or greater than the total debt.
 * This means liquidations can result in a loss or extra profit for lenders, making this module a critical part of the protocol's security.
 * Careful review and testing of custom liquidation modules is strongly recommended.
 *
 * The `debt` argument passed to the `liquidate` function should be used as the outstanding loan debt.
 * Do not fetch the debt from the loan contract, as the debt is removed from the loan contract state
 * prior to calling the liquidation module. Always rely on the provided argument for the correct value.
 *
 * The caller of the `liquidate` function is always expected to be the Loan contract. However, modules should implement
 * additional access control checks to ensure that only the authorized Loan contract can call this function and prevent
 * unauthorized access or misuse.
 */
interface IPWNLiquidationModule {
    /**
     * @notice Executes the liquidation process for a loan.
     * @dev This function is called by PWNLoan to perform the liquidation process.
     * Collateral is transferred to the liquidation module before this function is called.
     * Liquidation amount is transferred by the PWNLoan contract at the end of the liquidation process.
     * @param loanId The unique identifier of the loan.
     * @param liquidator The address of the entity initiating the liquidation.
     * @param borrower The address of the borrower whose loan is being liquidated.
     * @param debt The total outstanding debt of the loan at the time of liquidation.
     * @param creditAddress The address of the credit token used for the loan.
     * @param collateral The collateral asset being liquidated, represented as a MultiToken.Asset struct.
     * @param liquidationData Additional data that may be required for custom liquidation logic.
     * @return liquidationAmount The amount of collateral liquidated, which can be less than, greater than, or equal to the debt.
     */
    function liquidate(
        uint256 loanId,
        address liquidator,
        address borrower,
        uint256 debt,
        address creditAddress,
        MultiToken.Asset calldata collateral,
        bytes calldata liquidationData
    ) external returns (uint256 liquidationAmount);
}



// ============================================================
// FILE: src/periphery/interfaces/IChainlinkAggregatorLike.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


/**
 * @title IChainlinkAggregatorLike
 * @notice Chainlink Aggregator Interface.
 */
interface IChainlinkAggregatorLike {

    /**
     * @notice Get the number of decimals for the aggregator answers.
     * @return Number of decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Get the description of the aggregator.
     * @return Description of the aggregator.
     */
    function description() external view returns (string memory);

    /**
     * @notice Get the latest round data for the aggregator.
     * @return roundId The round ID from the aggregator for which the data was retrieved combined with a phase to ensure that round IDs get larger as time moves forward.
     * @return answer The answer for the latest round.
     * @return startedAt The timestamp when the round was started. (Only some AggregatorV3Interface implementations return meaningful values).
     * @return updatedAt The timestamp when the round last was updated (i.e. answer was last computed).
     * @return answeredInRound The round ID of the round in which the answer was computed. (Only some AggregatorV3Interface implementations return meaningful values).
     */
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

}



// ============================================================
// FILE: src/periphery/interfaces/IChainlinkFeedRegistryLike.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IChainlinkAggregatorLike } from "pwn/periphery/interfaces/IChainlinkAggregatorLike.sol";


/**
 * @title IChainlinkFeedRegistryLike
 * @notice Chainlink Feed Registry Interface.
 */
interface IChainlinkFeedRegistryLike {

    /**
     * @notice Get the Chainlink aggregator for a given base and quote asset.
     * @param base Base asset address.
     * @param quote Quote asset address.
     * @return aggregator Chainlink aggregator for the given base and quote asset.
     */
    function getFeed(address base, address quote) external view returns (IChainlinkAggregatorLike aggregator);

    /**
     * @notice Allows an owner to begin transferring ownership to a new address,
     * pending.
     */
    function transferOwnership(address to) external;

    /**
     * @notice Allows an ownership transfer to be completed by the recipient.
     */
    function acceptOwnership() external;

    /**
     * @notice Propose a new Chainlink aggregator for a given base and quote asset.
     * @param base Base asset address.
     * @param quote Quote asset address.
     * @param aggregator Chainlink aggregator address.
     */
    function proposeFeed(address base, address quote, address aggregator) external;

    /**
     * @notice Confirm a new Chainlink aggregator for a given base and quote asset.
     * @param base Base asset address.
     * @param quote Quote asset address.
     * @param aggregator Chainlink aggregator address.
     */
    function confirmFeed(address base, address quote, address aggregator) external;

}



// ============================================================
// FILE: src/periphery/utils/safeFetchDecimals.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


function safeFetchDecimals(address asset) view returns (uint256) {
    (bool success, bytes memory returndata) = asset.staticcall(abi.encodeWithSignature("decimals()"));
    if (!success || returndata.length == 0) {
        return 0;
    }
    return abi.decode(returndata, (uint256));
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

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
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
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
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC721/IERC721.sol)

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC1155/IERC1155.sol)

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC1155 compliant contract, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1155[EIP].
 *
 * _Available since v3.1._
 */
interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` tokens of token type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the amount of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(
        address[] calldata accounts,
        uint256[] calldata ids
    ) external view returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/Address.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/Address.sol)

pragma solidity ^0.8.1;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     *
     * Furthermore, `isContract` will also return true if the target contract within
     * the same transaction is already scheduled for destruction by `SELFDESTRUCT`,
     * which only has an effect at the end of a transaction.
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.0/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
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



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/access/Ownable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (access/Ownable.sol)

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (access/Ownable2Step.sol)

pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import {Initializable} from "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Ownable).
 */
abstract contract Ownable2StepUpgradeable is Initializable, OwnableUpgradeable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function __Ownable2Step_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable2Step_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public virtual {
        address sender = _msgSender();
        require(pendingOwner() == sender, "Ownable2Step: caller is not the new owner");
        _transferOwnership(sender);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}



// ============================================================
// FILE: src/core/config/IStateFingerpringComputer.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IStateFingerpringComputer
 * @notice State Fingerprint Computer Interface.
 * @dev Contract can compute state fingerprint of several tokens as long as they share the same state structure.
 */
interface IStateFingerpringComputer {

    /**
     * @notice Compute current token state fingerprint for a given token.
     * @param token Address of a token contract.
     * @param tokenId Token id to compute state fingerprint for.
     * @return Current token state fingerprint.
     */
    function computeStateFingerprint(address token, uint256 tokenId) external view returns (bytes32);

    /**
     * @notice Check if the computer supports a given token address.
     * @param token Address of a token contract.
     * @return True if the computer supports the token address, false otherwise.
     */
    function supportsToken(address token) external view returns (bool);

}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.2) (utils/cryptography/MerkleProof.sol)

pragma solidity ^0.8.0;

/**
 * @dev These functions deal with verification of Merkle Tree proofs.
 *
 * The tree and the proofs can be generated using our
 * https://github.com/OpenZeppelin/merkle-tree[JavaScript library].
 * You will find a quickstart guide in the readme.
 *
 * WARNING: You should avoid using leaf values that are 64 bytes long prior to
 * hashing, or use a hash function other than keccak256 for hashing leaves.
 * This is because the concatenation of a sorted pair of internal nodes in
 * the merkle tree could be reinterpreted as a leaf value.
 * OpenZeppelin's JavaScript library generates merkle trees that are safe
 * against this attack out of the box.
 */
library MerkleProof {
    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        return processProof(proof, leaf) == root;
    }

    /**
     * @dev Calldata version of {verify}
     *
     * _Available since v4.7._
     */
    function verifyCalldata(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        return processProofCalldata(proof, leaf) == root;
    }

    /**
     * @dev Returns the rebuilt hash obtained by traversing a Merkle tree up
     * from `leaf` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the root of the tree. When processing the proof, the pairs
     * of leafs & pre-images are assumed to be sorted.
     *
     * _Available since v4.4._
     */
    function processProof(bytes32[] memory proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = _hashPair(computedHash, proof[i]);
        }
        return computedHash;
    }

    /**
     * @dev Calldata version of {processProof}
     *
     * _Available since v4.7._
     */
    function processProofCalldata(bytes32[] calldata proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = _hashPair(computedHash, proof[i]);
        }
        return computedHash;
    }

    /**
     * @dev Returns true if the `leaves` can be simultaneously proven to be a part of a merkle tree defined by
     * `root`, according to `proof` and `proofFlags` as described in {processMultiProof}.
     *
     * CAUTION: Not all merkle trees admit multiproofs. See {processMultiProof} for details.
     *
     * _Available since v4.7._
     */
    function multiProofVerify(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return processMultiProof(proof, proofFlags, leaves) == root;
    }

    /**
     * @dev Calldata version of {multiProofVerify}
     *
     * CAUTION: Not all merkle trees admit multiproofs. See {processMultiProof} for details.
     *
     * _Available since v4.7._
     */
    function multiProofVerifyCalldata(
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return processMultiProofCalldata(proof, proofFlags, leaves) == root;
    }

    /**
     * @dev Returns the root of a tree reconstructed from `leaves` and sibling nodes in `proof`. The reconstruction
     * proceeds by incrementally reconstructing all inner nodes by combining a leaf/inner node with either another
     * leaf/inner node or a proof sibling node, depending on whether each `proofFlags` item is true or false
     * respectively.
     *
     * CAUTION: Not all merkle trees admit multiproofs. To use multiproofs, it is sufficient to ensure that: 1) the tree
     * is complete (but not necessarily perfect), 2) the leaves to be proven are in the opposite order they are in the
     * tree (i.e., as seen from right to left starting at the deepest layer and continuing at the next layer).
     *
     * _Available since v4.7._
     */
    function processMultiProof(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32 merkleRoot) {
        // This function rebuilds the root hash by traversing the tree up from the leaves. The root is rebuilt by
        // consuming and producing values on a queue. The queue starts with the `leaves` array, then goes onto the
        // `hashes` array. At the end of the process, the last hash in the `hashes` array should contain the root of
        // the merkle tree.
        uint256 leavesLen = leaves.length;
        uint256 proofLen = proof.length;
        uint256 totalHashes = proofFlags.length;

        // Check proof validity.
        require(leavesLen + proofLen - 1 == totalHashes, "MerkleProof: invalid multiproof");

        // The xxxPos values are "pointers" to the next value to consume in each array. All accesses are done using
        // `xxx[xxxPos++]`, which return the current value and increment the pointer, thus mimicking a queue's "pop".
        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        uint256 proofPos = 0;
        // At each step, we compute the next hash using two values:
        // - a value from the "main queue". If not all leaves have been consumed, we get the next leaf, otherwise we
        //   get the next hash.
        // - depending on the flag, either another value from the "main queue" (merging branches) or an element from the
        //   `proof` array.
        for (uint256 i = 0; i < totalHashes; i++) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = proofFlags[i]
                ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                : proof[proofPos++];
            hashes[i] = _hashPair(a, b);
        }

        if (totalHashes > 0) {
            require(proofPos == proofLen, "MerkleProof: invalid multiproof");
            unchecked {
                return hashes[totalHashes - 1];
            }
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }

    /**
     * @dev Calldata version of {processMultiProof}.
     *
     * CAUTION: Not all merkle trees admit multiproofs. See {processMultiProof} for details.
     *
     * _Available since v4.7._
     */
    function processMultiProofCalldata(
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32 merkleRoot) {
        // This function rebuilds the root hash by traversing the tree up from the leaves. The root is rebuilt by
        // consuming and producing values on a queue. The queue starts with the `leaves` array, then goes onto the
        // `hashes` array. At the end of the process, the last hash in the `hashes` array should contain the root of
        // the merkle tree.
        uint256 leavesLen = leaves.length;
        uint256 proofLen = proof.length;
        uint256 totalHashes = proofFlags.length;

        // Check proof validity.
        require(leavesLen + proofLen - 1 == totalHashes, "MerkleProof: invalid multiproof");

        // The xxxPos values are "pointers" to the next value to consume in each array. All accesses are done using
        // `xxx[xxxPos++]`, which return the current value and increment the pointer, thus mimicking a queue's "pop".
        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        uint256 proofPos = 0;
        // At each step, we compute the next hash using two values:
        // - a value from the "main queue". If not all leaves have been consumed, we get the next leaf, otherwise we
        //   get the next hash.
        // - depending on the flag, either another value from the "main queue" (merging branches) or an element from the
        //   `proof` array.
        for (uint256 i = 0; i < totalHashes; i++) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = proofFlags[i]
                ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                : proof[proofPos++];
            hashes[i] = _hashPair(a, b);
        }

        if (totalHashes > 0) {
            require(proofPos == proofLen, "MerkleProof: invalid multiproof");
            unchecked {
                return hashes[totalHashes - 1];
            }
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}



// ============================================================
// FILE: src/core/lib/PWNSignatureChecker.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { ECDSA } from "openzeppelin/utils/cryptography/ECDSA.sol";
import { IERC1271 } from "openzeppelin/interfaces/IERC1271.sol";


/**
 * @title PWN Signature Checker
 * @notice Library to check if a given signature is valid for EOAs or contract accounts.
 * @dev This library is a modification of an Open-Zeppelin `SignatureChecker` library extended by a support for EIP-2098 compact signatures.
 */
library PWNSignatureChecker {

    string internal constant VERSION = "1.0";

    /** @dev Thrown when signature length is not 64 nor 65 bytes.*/
    error InvalidSignatureLength(uint256 length);
    /** @dev Thrown when signature is invalid.*/
    error InvalidSignature(address signer, bytes32 digest);

    /**
     * @dev Function will try to recover a signer of a given signature and check if is the same as given signer address.
     * For a contract account signer address, function will check signature validity by calling `isValidSignature` function defined by EIP-1271.
     * @param signer Address that should be a `hash` signer or a signature validator, in case of a contract account.
     * @param hash Hash of a signed message that should validated.
     * @param signature Signature of a signed `hash`. Could be empty for a contract account signature validation. Signature can be standard (65 bytes) or compact (64 bytes) defined by EIP-2098.
     * @return True if a signature is valid.
     */
    function isValidSignatureNow(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        // Check that signature is valid for contract account
        if (signer.code.length > 0) {
            (bool success, bytes memory result) = signer.staticcall(
                abi.encodeWithSelector(IERC1271.isValidSignature.selector, hash, signature)
            );
            return
                success &&
                result.length == 32 &&
                abi.decode(result, (bytes32)) == bytes32(IERC1271.isValidSignature.selector);
        }
        // Check that signature is valid for EOA
        else {
            bytes32 r;
            bytes32 s;
            uint8 v;

            // Standard signature data (65 bytes)
            if (signature.length == 65) {
                assembly ("memory-safe") {
                    r := mload(add(signature, 0x20))
                    s := mload(add(signature, 0x40))
                    v := byte(0, mload(add(signature, 0x60)))
                }
            }
            // Compact signature data (64 bytes) - see EIP-2098
            else if (signature.length == 64) {
                bytes32 vs;

                assembly ("memory-safe") {
                    r := mload(add(signature, 0x20))
                    vs := mload(add(signature, 0x40))
                }

                s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
                v = uint8((uint256(vs) >> 255) + 27);
            } else {
                revert InvalidSignatureLength({ length: signature.length });
            }

            return signer == ECDSA.recover(hash, v, r, s);
        }
    }

}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC721/IERC721Receiver.sol)

pragma solidity ^0.8.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC1155/IERC1155Receiver.sol)

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev _Available since v3.1._
 */
interface IERC1155Receiver is IERC165 {
    /**
     * @dev Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     *
     * NOTE: To accept the transfer, this must return
     * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     * (i.e. 0xf23a6e61, or its own function selector).
     *
     * @param operator The address which initiated the transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param id The ID of the token being transferred
     * @param value The amount of tokens being transferred
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    /**
     * @dev Handles the receipt of a multiple ERC1155 token types. This function
     * is called at the end of a `safeBatchTransferFrom` after the balances have
     * been updated.
     *
     * NOTE: To accept the transfer(s), this must return
     * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     * (i.e. 0xbc197c81, or its own function selector).
     *
     * @param operator The address which initiated the batch transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param ids An array containing ids of each token being transferred (order and length must match values array)
     * @param values An array containing amounts of each token being transferred (order and length must match ids array)
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./extensions/IERC721Metadata.sol";
import "../../utils/Address.sol";
import "../../utils/Context.sol";
import "../../utils/Strings.sol";
import "../../utils/introspection/ERC165.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: address zero is not a valid owner");
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _ownerOf(tokenId);
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not token owner or approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        _requireMinted(tokenId);

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist
     */
    function _ownerOf(uint256 tokenId) internal view virtual returns (address) {
        return _owners[tokenId];
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId, 1);

        // Check that tokenId was not minted by `_beforeTokenTransfer` hook
        require(!_exists(tokenId), "ERC721: token already minted");

        unchecked {
            // Will not overflow unless all 2**256 token ids are minted to the same owner.
            // Given that tokens are minted one by one, it is impossible in practice that
            // this ever happens. Might change if we allow batch minting.
            // The ERC fails to describe this case.
            _balances[to] += 1;
        }

        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);

        _afterTokenTransfer(address(0), to, tokenId, 1);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     * This is an internal function that does not check if the sender is authorized to operate on the token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ERC721.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId, 1);

        // Update ownership in case tokenId was transferred by `_beforeTokenTransfer` hook
        owner = ERC721.ownerOf(tokenId);

        // Clear approvals
        delete _tokenApprovals[tokenId];

        unchecked {
            // Cannot overflow, as that would require more tokens to be burned/transferred
            // out than the owner initially received through minting and transferring in.
            _balances[owner] -= 1;
        }
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);

        _afterTokenTransfer(owner, address(0), tokenId, 1);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId, 1);

        // Check that tokenId was not transferred by `_beforeTokenTransfer` hook
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");

        // Clear approvals from the previous owner
        delete _tokenApprovals[tokenId];

        unchecked {
            // `_balances[from]` cannot overflow for the same reason as described in `_burn`:
            // `from`'s balance is the number of token held, which is at least one before the current
            // transfer.
            // `_balances[to]` could overflow in the conditions described in `_mint`. That would require
            // all 2**256 token ids to be minted, which in practice is impossible.
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId, 1);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual {
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev Reverts if the `tokenId` has not been minted yet.
     */
    function _requireMinted(uint256 tokenId) internal view virtual {
        require(_exists(tokenId), "ERC721: invalid token ID");
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting and burning. If {ERC721Consecutive} is
     * used, the hook may be called as part of a consecutive (batch) mint, as indicated by `batchSize` greater than 1.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s tokens will be transferred to `to`.
     * - When `from` is zero, the tokens will be minted for `to`.
     * - When `to` is zero, ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     * - `batchSize` is non-zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize) internal virtual {}

    /**
     * @dev Hook that is called after any token transfer. This includes minting and burning. If {ERC721Consecutive} is
     * used, the hook may be called as part of a consecutive (batch) mint, as indicated by `batchSize` greater than 1.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s tokens were transferred to `to`.
     * - When `from` is zero, the tokens were minted for `to`.
     * - When `to` is zero, ``from``'s tokens were burned.
     * - `from` and `to` are never both zero.
     * - `batchSize` is non-zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize) internal virtual {}

    /**
     * @dev Unsafe write access to the balances, used by extensions that "mint" tokens using an {ownerOf} override.
     *
     * WARNING: Anyone calling this MUST ensure that the balances remain consistent with the ownership. The invariant
     * being that for any address `a` the value returned by `balanceOf(a)` must be equal to the number of tokens such
     * that `ownerOf(tokenId)` is `a`.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __unsafe_increaseBalance(address account, uint256 amount) internal {
        _balances[account] += amount;
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/Context.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.4) (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (access/Ownable.sol)

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import {Initializable} from "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}



// ============================================================
// FILE: lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.2;

import "../../utils/AddressUpgradeable.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that functions marked with `initializer` can be nested in the context of a
     * constructor.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: setting the version to 255 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized != type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/cryptography/ECDSA.sol)

pragma solidity ^0.8.0;

import "../Strings.sol";

/**
 * @dev Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
 *
 * These functions can be used to verify that a message was signed by the holder
 * of the private keys of a given address.
 */
library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS,
        InvalidSignatureV // Deprecated in v4.8
    }

    function _throwError(RecoverError error) private pure {
        if (error == RecoverError.NoError) {
            return; // no error: do nothing
        } else if (error == RecoverError.InvalidSignature) {
            revert("ECDSA: invalid signature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSA: invalid signature length");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSA: invalid signature 's' value");
        }
    }

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature` or error string. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     *
     * Documentation for signature generation:
     * - with https://web3js.readthedocs.io/en/v1.3.4/web3-eth-accounts.html#sign[Web3.js]
     * - with https://docs.ethers.io/v5/api/signer/#Signer-signMessage[ethers]
     *
     * _Available since v4.3._
     */
    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address, RecoverError) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            /// @solidity memory-safe-assembly
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength);
        }
    }

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature`. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, signature);
        _throwError(error);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `r` and `vs` short-signature fields separately.
     *
     * See https://eips.ethereum.org/EIPS/eip-2098[EIP-2098 short signatures]
     *
     * _Available since v4.3._
     */
    function tryRecover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address, RecoverError) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `r and `vs` short-signature fields separately.
     *
     * _Available since v4.2._
     */
    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, r, vs);
        _throwError(error);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `v`,
     * `r` and `s` signature fields separately.
     *
     * _Available since v4.3._
     */
    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address, RecoverError) {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS);
        }

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature);
        }

        return (signer, RecoverError.NoError);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `v`,
     * `r` and `s` signature fields separately.
     */
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, v, r, s);
        _throwError(error);
        return recovered;
    }

    /**
     * @dev Returns an Ethereum Signed Message, created from a `hash`. This
     * produces hash corresponding to the one signed with the
     * https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`]
     * JSON-RPC method as part of EIP-191.
     *
     * See {recover}.
     */
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 message) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, "\x19Ethereum Signed Message:\n32")
            mstore(0x1c, hash)
            message := keccak256(0x00, 0x3c)
        }
    }

    /**
     * @dev Returns an Ethereum Signed Message, created from `s`. This
     * produces hash corresponding to the one signed with the
     * https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`]
     * JSON-RPC method as part of EIP-191.
     *
     * See {recover}.
     */
    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(s.length), s));
    }

    /**
     * @dev Returns an Ethereum Signed Typed Data, created from a
     * `domainSeparator` and a `structHash`. This produces hash corresponding
     * to the one signed with the
     * https://eips.ethereum.org/EIPS/eip-712[`eth_signTypedData`]
     * JSON-RPC method as part of EIP-712.
     *
     * See {recover}.
     */
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 data) {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "\x19\x01")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            data := keccak256(ptr, 0x42)
        }
    }

    /**
     * @dev Returns an Ethereum Signed Data with intended validator, created from a
     * `validator` and `data` according to the version 0 of EIP-191.
     *
     * See {recover}.
     */
    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x00", validator, data));
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/interfaces/IERC1271.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (interfaces/IERC1271.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC1271 standard signature validation method for
 * contracts as defined in https://eips.ethereum.org/EIPS/eip-1271[ERC-1271].
 *
 * _Available since v4.1._
 */
interface IERC1271 {
    /**
     * @dev Should return whether the signature provided is valid for the provided data
     * @param hash      Hash of the data to be signed
     * @param signature Signature byte array associated with _data
     */
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC721/extensions/IERC721Metadata.sol)

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/Strings.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/Strings.sol)

pragma solidity ^0.8.0;

import "./math/Math.sol";
import "./math/SignedMath.sol";

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), _SYMBOLS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    /**
     * @dev Converts a `int256` to its ASCII `string` decimal representation.
     */
    function toString(int256 value) internal pure returns (string memory) {
        return string(abi.encodePacked(value < 0 ? "-" : "", toString(SignedMath.abs(value))));
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }

    /**
     * @dev Returns true if the two strings are equal.
     */
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/ERC165.sol)

pragma solidity ^0.8.0;

import "./IERC165.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.4) (utils/Context.sol)

pragma solidity ^0.8.0;
import {Initializable} from "../proxy/utils/Initializable.sol";

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}



// ============================================================
// FILE: lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/Address.sol)

pragma solidity ^0.8.1;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     *
     * Furthermore, `isContract` will also return true if the target contract within
     * the same transaction is already scheduled for destruction by `SELFDESTRUCT`,
     * which only has an effect at the end of a transaction.
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.0/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/SignedMath.sol)

pragma solidity ^0.8.0;

/**
 * @dev Standard signed math utilities missing in the Solidity language.
 */
library SignedMath {
    /**
     * @dev Returns the largest of two signed numbers.
     */
    function max(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two signed numbers.
     */
    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two signed numbers without overflow.
     * The result is rounded towards zero.
     */
    function average(int256 a, int256 b) internal pure returns (int256) {
        // Formula from the book "Hacker's Delight"
        int256 x = (a & b) + ((a ^ b) >> 1);
        return x + (int256(uint256(x) >> 255) & (a ^ b));
    }

    /**
     * @dev Returns the absolute unsigned value of a signed value.
     */
    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }
}
