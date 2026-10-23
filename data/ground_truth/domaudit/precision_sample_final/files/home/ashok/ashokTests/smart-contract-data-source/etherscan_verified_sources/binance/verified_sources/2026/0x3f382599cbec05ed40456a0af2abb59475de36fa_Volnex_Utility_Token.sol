// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x3f382599cbec05ed40456a0af2abb59475de36fa
// Contract Name: Volnex_Utility_Token



// ============================================================
// FILE: v9_token.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
======================================================================
  ██╗   ██╗ ██████╗ ██╗     ███╗   ██╗███████╗██╗  ██╗      ██╗   ██╗ █████╗ 
  ██║   ██║██╔═══██╗██║     ████╗  ██║██╔════╝╚██╗██╔╝      ██║   ██║██╔══██╗
  ██║   ██║██║   ██║██║     ██╔██╗ ██║█████╗   ╚███╔╝ █████╗██║   ██║╚██████║
  ╚██╗ ██╔╝██║   ██║██║     ██║╚██╗██║██╔══╝   ██╔██╗ ╚════╝╚██╗ ██╔╝ ╚═══██║
   ╚████╔╝ ╚██████╔╝███████╗██║ ╚████║███████╗██╔╝ ██╗       ╚████╔╝  █████╔╝
    ╚═══╝   ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝        ╚═══╝   ╚════╝ 

  Volnex Index Bond (V9) — Backed by Volnex ETF
  Version: 3.6.0 | Decimals: 18 | Network: BSC (BEP20)
  ----------------------------------------------------------------------
  The V9 token is the core utility token of the Volnex Ecosystem.
  It is minted exclusively by contributing USDT (BEP20).

  Volnex CORE MECHANISMS:

  1. MINTING (USDT Contribution):
     - Input: USDT (BEP20)
     - Expense Tax: 9% of USDT goes to Expense Wallet. [Adjustable via Governance]
     - Treasury Allocation: 91% of USDT stays in Contract (Treasury). [Auto-Adjusted]
     - Token Distribution (Tiered Ratios [User : Reserve : Treasury]):
       - < 1,000 USDT:      1 : 3 : 6   (Default) [Multipliers Fixed in Code]
       - 1,000 - 1,999:     1 : 4 : 8
       - 2,000 - 4,999:     1 : 5 : 10
       - 5,000 - 9,999:     1 : 6 : 12
       - >= 10,000 USDT:    1 : 8 : 16
       * User Share is constant (~11.11 V9/USDT) [Adjustable via Governance]
       * Reserve/Treasury multipliers increase with volume.

  2. SELLING & TAXATION:
     - Sell Tax: 10% (Applied on DEX Sells)
       - Founders:  10% of Tax (1% Total)
       - Core Pool: 30% of Tax (3% Total)
       - Syndicate: 60% of Tax (6% Total)
     - Buy Tax: 0%
     - Burn Logic:
       - Direct Sell: User burns V9 -> Gets USDT (90% Value).
       - DEX Sell: Treasury burns equivalent V9 to offset inflation.

  3. TREASURY MANAGEMENT:
     - Reserve Assets: Stores 91% of Minted USDT in contract.
     - V9 Holdings: Accumulates Treasury Share (~66.66 V9/USDT).
     - Purpose: Backs V9 value and facilitates DEX sell burns.

  4. DAO GOVERNANCE:
     - Model: Decentralised voting (1 Token = 1 Vote).
     - Proposal Types: Funding, Membership, Governance, General.
     - Thresholds: Quorum (51%), Proposal Threshold (1%).

  5. MULTI-SIG & CUSTODY:
     - Custodians: Trusted signers required for critical changes.
     - Timelock: 24-hour mandatory delay on sensitive parameters.
     - Approvals: Multi-sig confirmation for large withdrawals/updates.

  6. SECURITY & EMERGENCY:
     - Circuit Breaker: Pause/Unpause functionality.
     - Withdrawal Limits: Max 30% per transaction, 7-day cooldown.
     - Safety: recoverToken() restricted (cannot drain Reserve/V9).
     - Protection: Blacklist for malicious actors.

  7. KEY WALLETS:
     - Reserve Wallet: Holds Reserve Share of V9.
     - Expense Wallet: Receives 9% Mint Tax (USDT).
     - Founders/Syndicate/Core: Receive portions of Sell Tax.

  8. TOKEN STANDARDS:
     - ERC-20: Fully compliant standard interface.
     - EIP-2612 Permit: Gas-less approvals via signatures.
     - 18 Decimals: Standard DeFi compatibility.

  9. MARKET CONTROL:
     - Emissions Toggle: Can enable/disable auto-minting on DEX buys.
     - Direct Access: Can open/close direct contract minting/burning.
     - Market Pair: Specific DEX pair identification for tax logic.
======================================================================
*/


/**
 * @title Volnex_Utility_Token
 * @dev A Decentralised Autonomous Organisation (DAO) contract with ERC-20 token functionality
 * @author Volnex Team
 * @notice This contract implements a complete DAO with token, member management, voting, and fund management
 * @custom:security-contact Info@volnex.pro
 */

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Volnex_Utility_Token is IERC20 {
    
    // ============ ERC-20 STATE VARIABLES ============
    
    /// @notice The name of the token
    string public constant name = "Volnex Index";
    
    /// @notice The symbol of the token
    string public constant symbol = "V9";
    
    /// @notice The number of decimals the token uses
    uint8 public constant decimals = 18;
    
    /// @notice Mutable total supply
    uint256 private _totalSupply;
    
    /// @notice Mapping from account to token balance
    mapping(address => uint256) private _balances;
    
    /// @notice Mapping from account to spender to allowance amount
    mapping(address => mapping(address => uint256)) private _allowances;
    
    /**
     * @notice Get all governance parameters in one call
     */
    function getGovernanceParams() external view returns (
        uint256 _votingPeriod,
        uint256 _quorumPercentage,
        uint256 _proposalThresholdPercentage,
        uint256 _timelockDelay,
        uint256 _requiredConfirmations,
        uint256 _custodianCount
    ) {
        return (votingPeriod, quorumPercentage, proposalThresholdPercentage, timelockDelay, requiredConfirmations, custodianCount);
    }

    /**
     * @notice Get all token factor parameters in one call
     */
    function getFactorParams() external view returns (
        uint256 _uFactor,
        uint256 _oFactor,
        uint256 _tFactor,
        uint256 _sFactor,
        uint256 _sellTax,
        uint256 _mintExpenseTax,
        bool _emissionsEnabled,
        bool _directAccess
    ) {
        return (uFactor, oFactor, tFactor, sFactor, sellTax, mintExpenseTax, emissionsEnabled, directAccess);
    }
    
    /**
     * @notice Get withdrawal parameters
     */
    function getWithdrawalParams() external view returns (
        uint256 _limitPercent,
        uint256 _cooldown
    ) {
        return (reserveWithdrawalLimitPercent, reserveWithdrawalCooldown);
    }

    // ============ DAO STATE VARIABLES ============
    
    /// @notice The version of the contract
    string public constant version = "3.6.0";
    
    /// @notice The owner/admin of the DAO
    address public owner;
    
    /// @notice Total number of members in the DAO
    uint256 public totalMembers;
    
    /// @notice Total number of proposals created
    uint256 public totalProposals;
    
    /// @notice Minimum voting period in seconds (Default: 7 days)
    uint256 private votingPeriod = 7 days;
    
    /// @notice Minimum quorum percentage required for proposal execution (Default: 51%)
    uint256 private quorumPercentage = 51;

    /// @notice Minimum proposal threshold percentage (Default: 1%)
    uint256 private proposalThresholdPercentage = 1;
    
    /// @notice Treasury balance
    uint256 public treasuryBalance;

    IERC20 public reserveToken;
    address public market;
    bool private emissionsEnabled = true; // Controls DEX auto-minting
    bool private directAccess = true;     // Controls direct contribute() function
    uint256 private uFactor = 100;
    uint256 private oFactor = 300;
    uint256 private tFactor = 600;
    uint256 private sFactor = 0; // Syndicate Share
    uint256 private constant factorDenominator = 9;
    uint256 private sellTax = 10; // 10% Total Sell Tax
    // uint256 public sellTax = 0; // Removed unused variable
    // uint256 public corePoolTax = 10; // Renamed to sellTax
    address public syndicateWallet; // Separate Wallet for Syndicate
    address public corePoolWallet;  // Wallet for Core Pool Tax
    address public foundersWallet;  // Wallet for Founders Tax
    address public reserveWallet;   // Wallet for Reserve (formerly Owner Share)
    address public bondWallet;      // Wallet for Volnex Index Bond / ETF (USDT Withdrawals)
    address public expenseWallet;   // Wallet for Project Expenses (10% of Mint)
    uint256 private mintExpenseTax = 9; // 9% Tax on Mint (USDT)
    uint256 private buyTax = 0; // 0% Buy Tax
    bool public paused = false; // Emergency Pause Status
    
    // Withdrawal Limits for Owner
    uint256 public lastReserveWithdrawalTime;
    uint256 private reserveWithdrawalLimitPercent = 30;
    uint256 private reserveWithdrawalCooldown = 7 days;

    // EIP-2612 Permit
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    mapping(address => uint256) public nonces;
    bytes32 public DOMAIN_SEPARATOR;

    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        _checkPaused();
        _;
    }

    function _checkPaused() internal view {
        if (paused) revert ContractPaused();
    }

    enum ChangeType { SET_MARKET, SET_FACTORS, SET_SELL_TAX, SET_EMISSIONS, SET_DIRECT, WITHDRAW_RESERVE, SET_SYNDICATE, SET_FOUNDERS, SET_RESERVE, ADD_CUSTODIAN, REMOVE_CUSTODIAN, PAUSE_CONTRACT, UNPAUSE_CONTRACT, SET_WITHDRAWAL_PARAMS }
    struct Change { uint256 id; ChangeType changeType; uint256 scheduleTime; uint256 approvals; bool executed; address addr; uint256 v1; uint256 v2; uint256 v3; bool b; }
    mapping(uint256 => Change) private changes;
    mapping(uint256 => mapping(address => bool)) public changeApprovals;
    mapping(address => bool) public custodians;
    mapping(address => bool) public isBlacklisted;
    struct SpendingLimit { uint256 limit; uint256 spent; uint256 lastReset; }
    mapping(address => SpendingLimit) public spendingLimits;
    uint256 public custodianCount;
    uint256 public requiredConfirmations = 1;
    uint256 public timelockDelay = 1 days;
    uint256 public changeCount;
    
    // ============ STRUCTS ============
    
    /// @notice Structure to represent a DAO member
    struct Member {
        bool isActive;          // Whether the member is active
        uint256 joinedAt;       // Timestamp when member joined
        uint256 votingPower;    // Voting power of the member
        string name;            // Name of the member
    }
    
    /// @notice Structure to represent a proposal
    struct Proposal {
        uint256 id;                    // Unique proposal ID
        address proposer;              // Address of the proposer
        string title;                  // Title of the proposal
        string description;            // Description of the proposal
        uint256 amount;                // Amount requested (if funding proposal)
        address payable recipient;     // Recipient address (if funding proposal)
        uint256 votesFor;              // Number of votes in favor
        uint256 votesAgainst;          // Number of votes against
        uint256 createdAt;             // Creation timestamp
        uint256 deadline;              // Voting deadline
        bool executed;                 // Whether proposal has been executed
        bool cancelled;                // Whether proposal has been cancelled
        ProposalType proposalType;     // Type of proposal
    }
    
    /// @notice Enum for different types of proposals
    enum ProposalType {
        FUNDING,        // Request for funding (ETH/BNB)
        MEMBERSHIP,     // Add/remove member
        GOVERNANCE,     // Change governance parameters
        GENERAL,        // General proposal
        TOKEN_TRANSFER  // Request for V9 Token transfer from Treasury
    }
    
    /// @notice Structure to track votes
    struct Vote {
        bool hasVoted;      // Whether the member has voted
        bool support;       // True for yes, false for no
        uint256 votedAt;    // Timestamp of vote
    }
    
    // ============ MAPPINGS ============
    
    /// @notice Mapping from address to Member struct
    mapping(address => Member) public members;
    
    /// @notice Mapping from proposal ID to Proposal struct
    mapping(uint256 => Proposal) private proposals;
    
    /// @notice Mapping from proposal ID to member address to Vote struct
    mapping(uint256 => mapping(address => Vote)) public votes;
    
    /// @notice Array of all member addresses
    address[] public memberAddresses;
    
    // ============ EVENTS ============
    
    /// @notice Emitted when tokens are transferred (ERC-20 standard)
    // event Transfer(address indexed from, address indexed to, uint256 value); - Already defined in IERC20
    
    /// @notice Emitted when allowance is set (ERC-20 standard)
    // event Approval(address indexed owner, address indexed spender, uint256 value); - Already defined in IERC20
    
    /// @notice Emitted when a new member is added
    event MemberAdded(address indexed member, string name, uint256 votingPower);
    
    /// @notice Emitted when a member is removed
    event MemberRemoved(address indexed member);
    
    /// @notice Emitted when a new proposal is created
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        ProposalType proposalType
    );
    
    /// @notice Emitted when a vote is cast
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votingPower
    );
    
    /// @notice Emitted when a proposal is executed
    event ProposalExecuted(uint256 indexed proposalId, bool success);
    
    /// @notice Emitted when funds are deposited
    event FundsDeposited(address indexed depositor, uint256 amount);
    
    /// @notice Emitted when funds are withdrawn
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    
    /// @notice Emitted when ownership is transferred
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    /// @notice Emitted when tokens are distributed to members
    event TokensDistributed(address indexed recipient, uint256 amount);

    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
    event DailyLimitSet(address indexed account, uint256 limit);
    
    event Activity(address indexed actor, uint256 p0, uint256 p1, uint256 p2, uint256 p3);
    
    // ============ ERRORS ============
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientAllowance();
    error Unauthorised();
    error AddressBlacklisted();
    error LimitExceeded();
    error ProposalInactive();
    error AlreadyVoted();
    error ArrayMismatch();
    error TransferFailed();
    error TimelockActive();
    error AlreadyExecuted();
    error NotMember();
    error PermitExpired();
    error InvalidSignature();
    error ContractPaused();
    error WithdrawalCooldownActive();
    error WithdrawalLimitExceeded();
    error UseQueueFunction();
    error TooManyCustodians();

    // ============ MODIFIERS ============
    
    /// @notice Modifier to restrict access to members only
    modifier onlyMember() {
        if (!members[msg.sender].isActive) revert NotMember();
        _;
    }
    
    /// @notice Modifier to restrict access to owner only
    function _checkOwner() internal view {
        if (msg.sender != owner) revert Unauthorised();
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }
    
    /// @notice Modifier to check if proposal exists and is active
    modifier validProposal(uint256 _proposalId) {
        if (_proposalId >= totalProposals) revert ProposalInactive();
        if (proposals[_proposalId].executed) revert AlreadyExecuted();
        if (proposals[_proposalId].cancelled) revert ProposalInactive();
        if (block.timestamp > proposals[_proposalId].deadline) revert ProposalInactive();
        _;
    }
    
    // ============ CONSTRUCTOR ============
    
    /**
     * @notice Constructor to initialise the DAO
     * @param _initialMembers Array of initial member addresses
     * @param _memberNames Array of initial member names
     * @param _votingPowers Array of initial voting powers
     * @param _reserveTokenAddress Address of the reserve token
     * @param _syndicateWallet Address of the syndicate wallet
     * @param _corePoolWallet Address of the core pool wallet
     */
    constructor(
        address[] memory _initialMembers,
        string[] memory _memberNames,
        uint256[] memory _votingPowers,
        address _reserveTokenAddress,
        address _syndicateWallet,
        address _corePoolWallet,
        address _bondWallet
    ) {
        if (_initialMembers.length != _memberNames.length || _memberNames.length != _votingPowers.length) revert ArrayMismatch();
        if (_initialMembers.length == 0) revert InvalidAmount();
        if (_reserveTokenAddress == address(0)) revert InvalidAddress();
        // Removed non-zero checks for wallets to allow setting them later
        
        owner = msg.sender;
        reserveToken = IERC20(_reserveTokenAddress);
        syndicateWallet = _syndicateWallet;
        corePoolWallet = _corePoolWallet;
        bondWallet = _bondWallet;

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                address(this)
            )
        );
        
        // Initial supply: 0 V9 (Minted via Contribute only)
        // _mint(msg.sender, 9000 * 10**18); // Removed as per new requirement
        
        // Add initial members
        for (uint256 i = 0; i < _initialMembers.length; i++) {
            if (_initialMembers[i] == address(0)) revert InvalidAddress();
            if (_votingPowers[i] == 0) revert InvalidAmount();
            
            members[_initialMembers[i]] = Member({
                isActive: true,
                joinedAt: block.timestamp,
                votingPower: _votingPowers[i],
                name: _memberNames[i]
            });
            
            memberAddresses.push(_initialMembers[i]);
            totalMembers++;
            
            emit MemberAdded(_initialMembers[i], _memberNames[i], _votingPowers[i]);
        }
    }
    
    // ============ ERC-20 FUNCTIONS ============
    
    /**
     * @notice Returns the amount of tokens owned by account
     * @param account The address to query the balance of
     * @return The amount of tokens owned by the account
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    /**
     * @notice Moves amount tokens from the caller's account to to
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     * @return A boolean value indicating whether the operation succeeded
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        address sender = msg.sender;
        _transfer(sender, to, amount);
        return true;
    }

    /**
     * @notice Returns the total token supply
     * @return Current total supply
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    
    /**
     * @notice Returns the remaining number of tokens that spender will be allowed to spend on behalf of owner
     * @param tokenOwner The address which owns the tokens
     * @param spender The address which will spend the tokens
     * @return The remaining allowance
     */
    function allowance(address tokenOwner, address spender) public view override returns (uint256) {
        return _allowances[tokenOwner][spender];
    }
    
    /**
     * @notice Sets amount as the allowance of spender over the caller's tokens
     * @param spender The address which will spend the tokens
     * @param amount The amount of tokens to approve
     * @return A boolean value indicating whether the operation succeeded
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        address sender = msg.sender;
        _approve(sender, spender, amount);
        return true;
    }
    
    /**
     * @notice Moves amount tokens from from to to using the allowance mechanism
     * @param from The address to transfer tokens from
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     * @return A boolean value indicating whether the operation succeeded
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    /**
     * @notice Internal function to handle token transfers
     * @param from The address to transfer tokens from
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     */
    function _transfer(address from, address to, uint256 amount) internal whenNotPaused {
        if (from == address(0)) revert InvalidAddress();
        if (to == address(0)) revert InvalidAddress();
        if (isBlacklisted[from]) revert AddressBlacklisted();
        if (isBlacklisted[to]) revert AddressBlacklisted();
        
        // Check Spending Limit
        SpendingLimit storage limitInfo = spendingLimits[from];
        if (limitInfo.limit > 0) {
            // Reset if 24 hours passed
            if (block.timestamp >= limitInfo.lastReset + 1 days) {
                limitInfo.spent = 0;
                limitInfo.lastReset = block.timestamp;
            }
            if (limitInfo.spent + amount > limitInfo.limit) revert LimitExceeded();
            limitInfo.spent += amount;
        }

        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance();

        uint256 finalAmount = amount;
        uint256 burnAmount = 0;
        uint256 coreTaxAmount = 0;
        uint256 foundersTaxAmount = 0;
        uint256 syndicateTaxAmount = 0;

        // Apply Sell Tax (10%)
        // 10% -> Founders (1.0%)
        // 30% -> Core Pool (3.0%)
        // 60% -> Syndicate (6.0%)
        if (to == market && emissionsEnabled) {
            uint256 totalTaxAmount = (amount * sellTax) / 100;
            
            foundersTaxAmount = (totalTaxAmount * 10) / 100;
            coreTaxAmount = (totalTaxAmount * 30) / 100;
            syndicateTaxAmount = totalTaxAmount - foundersTaxAmount - coreTaxAmount;

            finalAmount = amount - totalTaxAmount;
            
            // Treasury Burn Logic: Burn equivalent amount from Treasury to offset sell pressure
            // We burn from address(this) which holds the Treasury funds
            uint256 treasuryBurnAmount = amount; 
            if (_balances[address(this)] >= treasuryBurnAmount) {
                _burn(address(this), treasuryBurnAmount);
            }
        }

        // Apply Buy Tax (1% -> Founders)
        if (from == market && emissionsEnabled) {
             uint256 bTax = (amount * buyTax) / 100;
             foundersTaxAmount += bTax;
             finalAmount = amount - bTax;
        }
        
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += finalAmount;
        }
        
        // Handle Burn
        if (burnAmount > 0) {
            _totalSupply -= burnAmount;
            emit Transfer(from, address(0), burnAmount);
        }

        // Handle Taxes
        if (coreTaxAmount > 0) {
            _balances[corePoolWallet] += coreTaxAmount;
            emit Transfer(from, corePoolWallet, coreTaxAmount);
        }
        if (foundersTaxAmount > 0) {
            _balances[foundersWallet] += foundersTaxAmount;
            emit Transfer(from, foundersWallet, foundersTaxAmount);
        }
        if (syndicateTaxAmount > 0) {
            _balances[syndicateWallet] += syndicateTaxAmount;
            emit Transfer(from, syndicateWallet, syndicateTaxAmount);
        }

        emit Transfer(from, to, finalAmount);

        // Buy Logic (Mint)
        if (from == market && emissionsEnabled) {
            // Mint Extra Tokens based on ratios
            // Ratios: User=1, Reserve=3, Treasury=6, Syndicate=0
            // Buy 1000 -> Mint 3000 (Reserve), 6000 (Treasury), 0 (Syndicate)
            uint256 ownerShare = (amount * oFactor) / uFactor;
            uint256 treasuryShare = (amount * tFactor) / uFactor;
            
            _mint(reserveWallet, ownerShare); // Reserve Share (formerly Owner Share)
            _mint(address(this), treasuryShare);

            if (sFactor > 0) {
                uint256 synShare = (amount * sFactor) / uFactor;
                _mint(syndicateWallet, synShare);
            }
            
            emit Activity(to, 0, amount, ownerShare, treasuryShare);
        }

        // Sell Logic (Treasury Burn) - Burns equivalent to what entered the market
        if (to == market && emissionsEnabled) {
            uint256 burnAmt = finalAmount;
            uint256 treasuryBal = _balances[address(this)];
            if (treasuryBal >= burnAmt) {
                _burn(address(this), burnAmt);
            } else if (treasuryBal > 0) {
                _burn(address(this), treasuryBal);
            }
            emit Activity(from, burnAmt, 0, 0, 0);
        }
    }

    /**
     * @notice Internal mint function
     * @param to Recipient of minted tokens
     * @param amount Amount to mint
     */
    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidAddress();
        unchecked {
            _totalSupply += amount;
            _balances[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Internal burn function
     * @param from Address to burn tokens from
     * @param amount Amount to burn
     */
    function _burn(address from, uint256 amount) internal {
        if (from == address(0)) revert InvalidAddress();
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance();
        unchecked {
            _balances[from] = fromBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
    
    /**
     * @notice Internal function to handle approvals
     * @param tokenOwner The address which owns the tokens
     * @param spender The address which will spend the tokens
     * @param amount The amount of tokens to approve
     */
    function _approve(address tokenOwner, address spender, uint256 amount) internal {
        if (tokenOwner == address(0)) revert InvalidAddress();
        if (spender == address(0)) revert InvalidAddress();
        
        _allowances[tokenOwner][spender] = amount;
        emit Approval(tokenOwner, spender, amount);
    }
    
    /**
     * @notice Internal function to handle allowance spending
     * @param tokenOwner The address which owns the tokens
     * @param spender The address which will spend the tokens
     * @param amount The amount of tokens to spend
     */
    function _spendAllowance(address tokenOwner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(tokenOwner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance();
            unchecked {
                _approve(tokenOwner, spender, currentAllowance - amount);
            }
        }
    }

    // ============ MINT/BURN FUNCTIONS ============
    
    // Manual mint and burn disabled


    // ============ TOKEN UTILITY FUNCTIONS ============
    
    function _getRatioMultipliers(uint256 amount) internal pure returns (uint256 rMult, uint256 tMult) {
        // Tiers based on USDT amount (18 decimals)
        // Returns (Reserve Multiplier, Treasury Multiplier) based on User Share
        if (amount >= 10000 * 1e18) return (8, 16); // 1:8:16
        if (amount >= 5000 * 1e18) return (6, 12);  // 1:6:12
        if (amount >= 2000 * 1e18) return (5, 10);  // 1:5:10
        if (amount >= 1000 * 1e18) return (4, 8);   // 1:4:8
        return (3, 6);                              // 1:3:6 (Default)
    }

    /**
     * @notice Buy tokens with USDT
     * @param amount Amount of USDT to spend (must be approved first)
     */
    function contribute(uint256 amount) external whenNotPaused {
        if (!directAccess) revert Unauthorised();
        if (amount == 0) revert InvalidAmount();
        if (reserveToken.allowance(msg.sender, address(this)) < amount) revert InsufficientAllowance();
        if (reserveToken.balanceOf(msg.sender) < amount) revert InsufficientBalance();
        
        // Split USDT (10% Expense, 90% Treasury)
        uint256 expense = (amount * mintExpenseTax) / 100;
        uint256 netTreasury = amount - expense;

        if (expense > 0 && expenseWallet != address(0)) {
            if (!_safeTransferFrom(reserveToken, msg.sender, expenseWallet, expense)) revert TransferFailed();
        } else {
            // If expense wallet not set, send all to treasury
            netTreasury = amount;
        }

        if (netTreasury > 0) {
            if (!_safeTransferFrom(reserveToken, msg.sender, address(this), netTreasury)) revert TransferFailed();
        }
        
        // Calculate shares
        // User gets standard rate based on uFactor
        uint256 userShare = (amount * uFactor) / factorDenominator;

        // Reserve & Treasury get multiples of User Share based on Amount Tier
        (uint256 rMult, uint256 tMult) = _getRatioMultipliers(amount);
        uint256 ownerShare = userShare * rMult;
        uint256 treasuryShare = userShare * tMult;
        
        // Apply Buy Tax (0% -> Founders)
        uint256 bTax = (userShare * buyTax) / 100;
        uint256 userFinal = userShare - bTax;

        // Mint tokens
        _mint(msg.sender, userFinal);
        if (bTax > 0) {
            _mint(foundersWallet, bTax);
        }
        _mint(reserveWallet, ownerShare); // Reserve Share
        _mint(address(this), treasuryShare);

        if (sFactor > 0) {
            uint256 synShare = (amount * sFactor) / factorDenominator;
            _mint(syndicateWallet, synShare);
        }
        
        emit Activity(msg.sender, amount, userShare, ownerShare, treasuryShare);
    }

    /**
     * @notice Sell tokens back to contract for USDT (Direct Sell)
     * @param tokenAmount Amount of V9 tokens to sell
     */
    function sellTokens(uint256 tokenAmount) external whenNotPaused {
        if (!directAccess) revert Unauthorised();
        if (tokenAmount == 0) revert InvalidAmount();
        if (_balances[msg.sender] < tokenAmount) revert InsufficientBalance();

        // Calculate Tax
        uint256 totalTaxAmount = (tokenAmount * sellTax) / 100;
        uint256 sellAmount = tokenAmount - totalTaxAmount;

        // Calculate USDT Value (Reverse of Mint)
        // sellAmount * 9 / 100 = USDT Value
        uint256 usdtAmount = (sellAmount * factorDenominator) / uFactor;

        if (usdtAmount == 0) revert InvalidAmount();
        if (reserveToken.balanceOf(address(this)) < usdtAmount) revert InsufficientBalance();

        // Process Tokens
        // 1. Tax Split
        // 10% -> Founders, 30% -> Core Pool, 60% -> Syndicate
        if (totalTaxAmount > 0) {
            uint256 fTax = (totalTaxAmount * 10) / 100;
            uint256 cTax = (totalTaxAmount * 30) / 100;
            uint256 sTax = totalTaxAmount - fTax - cTax;

            if (fTax > 0) _transfer(msg.sender, foundersWallet, fTax);
            if (cTax > 0) _transfer(msg.sender, corePoolWallet, cTax);
            if (sTax > 0) _transfer(msg.sender, syndicateWallet, sTax);
        }

        // 2. Burn Sold Tokens (Instant Burn)
        _burn(msg.sender, sellAmount);

        // 3. Send USDT to User
        if (!reserveToken.transfer(msg.sender, usdtAmount)) revert TransferFailed();

        emit Activity(msg.sender, usdtAmount, tokenAmount, 0, 0);
    }
 
    function _safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal returns (bool) {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
        if (!success) return false;
        if (data.length == 0) return true;
        return abi.decode(data, (bool));
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Recover any ERC20 token sent to contract by mistake (except ReserveToken and V9)
     * @param tokenAddress Address of the token to recover
     * @param tokenAmount Amount to recover
     */
    function recoverToken(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        if (tokenAddress == address(reserveToken)) revert Unauthorised(); // Cannot withdraw ReserveToken (USDT)
        if (tokenAddress == address(this)) revert Unauthorised(); // Cannot withdraw V9
        IERC20(tokenAddress).transfer(owner, tokenAmount);
    }

    /**
     * @notice EIP-2612 Permit function
     */
    function permit(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert PermitExpired();
        
        bytes32 structHash;
        unchecked {
            structHash = keccak256(
                abi.encode(PERMIT_TYPEHASH, owner_, spender, value, nonces[owner_]++, deadline)
            );
        }
        
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0) || signer != owner_) revert InvalidSignature();
        _approve(owner_, spender, value);
    }

    /**
     * @notice Distribute tokens to multiple addresses (only owner)
     * @param recipients Array of recipient addresses
     * @param amounts Array of token amounts to distribute
     */
    function distributeTokens(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        if (recipients.length != amounts.length) revert ArrayMismatch();
        if (recipients.length == 0) revert InvalidAmount();
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidAddress();
            if (amounts[i] == 0) revert InvalidAmount();
            
            _transfer(msg.sender, recipients[i], amounts[i]);
            emit TokensDistributed(recipients[i], amounts[i]);
        }
    }
    
    /**
     * @notice Distribute equal tokens to all active members (only owner)
     * @param amountPerMember Amount of tokens to give each member
     */
    function distributeToAllMembers(uint256 amountPerMember) external onlyOwner {
        if (amountPerMember == 0) revert InvalidAmount();
        if (totalMembers == 0) revert InvalidAmount();
        
        uint256 totalRequired = amountPerMember * totalMembers;
        if (_balances[msg.sender] < totalRequired) revert InsufficientBalance();
        
        for (uint256 i = 0; i < memberAddresses.length; i++) {
            if (members[memberAddresses[i]].isActive) {
                _transfer(msg.sender, memberAddresses[i], amountPerMember);
                emit TokensDistributed(memberAddresses[i], amountPerMember);
            }
        }
    }

    /**
     * @notice Change the Syndicate Wallet address (Governance or Owner)
     * @param _newWallet New address for Syndicate Funds
     */
    function setSyndicateWallet(address _newWallet) external onlyOwner {
        if (_newWallet == address(0)) revert InvalidAddress();
        syndicateWallet = _newWallet;
    }

    /**
     * @notice Change the Core Pool Wallet address (Governance or Owner)
     * @param _newWallet New address for Core Pool Funds
     */
    function setCorePoolWallet(address _newWallet) external onlyOwner {
        if (_newWallet == address(0)) revert InvalidAddress();
        corePoolWallet = _newWallet;
    }

    /**
     * @notice Change the Bond Wallet address (Governance or Owner)
     * @param _newWallet New address for Bond Funds
     */
    function setBondWallet(address _newWallet) external onlyOwner {
        if (_newWallet == address(0)) revert InvalidAddress();
        bondWallet = _newWallet;
    }

    /**
     * @notice Change the Founders Wallet address (Governance or Owner)
     * @param _newWallet New address for Founders Tax
     */
    function setFoundersWallet(address _newWallet) external onlyOwner {
        if (_newWallet == address(0)) revert InvalidAddress();
        foundersWallet = _newWallet;
    }

    /**
     * @notice Change the Reserve Wallet address (Governance or Owner)
     * @param _newWallet New address for Reserve Share
     */
    function setReserveWallet(address _newWallet) external onlyOwner {
        if (_newWallet == address(0)) revert InvalidAddress();
        reserveWallet = _newWallet;
    }

    /**
     * @notice Get token balance of a specific member
     * @param member Address of the member
     * @return Token balance of the member
     */
    function getMemberTokenBalance(address member) external view returns (uint256) {
        if (!members[member].isActive) revert NotMember();
        return _balances[member];
    }
    
    /**
     * @notice Get total tokens held by all DAO members
     * @return Total tokens held by members
     */
    function getTotalMemberTokens() external view returns (uint256) {
        uint256 totalMemberTokens = 0;
        for (uint256 i = 0; i < memberAddresses.length; i++) {
            if (members[memberAddresses[i]].isActive) {
                totalMemberTokens += _balances[memberAddresses[i]];
            }
        }
        return totalMemberTokens;
    }
    
    /**
     * @notice Check if an address has minimum tokens to participate in governance
     * @param account Address to check
     * @param minimumTokens Minimum token requirement
     * @return True if account has sufficient tokens
     */
    function hasMinimumTokens(address account, uint256 minimumTokens) external view returns (bool) {
        return _balances[account] >= minimumTokens;
    }
    
    /**
     * @notice Add a new member to the DAO
     * @param _member Address of the new member
     * @param _name Name of the new member
     * @param _votingPower Voting power to assign to the member
     */
    function addMember(
        address _member,
        string memory _name,
        uint256 _votingPower
    ) external onlyOwner {
        if (_member == address(0)) revert InvalidAddress();
        if (members[_member].isActive) revert InvalidAddress(); // Already member
        if (_votingPower == 0) revert InvalidAmount();
        if (bytes(_name).length == 0) revert InvalidAddress(); // Empty name
        
        members[_member] = Member({
            isActive: true,
            joinedAt: block.timestamp,
            votingPower: _votingPower,
            name: _name
        });
        
        memberAddresses.push(_member);
        totalMembers++;
        
        emit MemberAdded(_member, _name, _votingPower);
    }
    
    /**
     * @notice Remove a member from the DAO
     * @param _member Address of the member to remove
     */
    function removeMember(address _member) external onlyOwner {
        if (!members[_member].isActive) revert NotMember();
        if (totalMembers <= 1) revert InvalidAmount(); // Cannot remove last member
        
        members[_member].isActive = false;
        
        // Remove from memberAddresses array
        for (uint256 i = 0; i < memberAddresses.length; i++) {
            if (memberAddresses[i] == _member) {
                memberAddresses[i] = memberAddresses[memberAddresses.length - 1];
                memberAddresses.pop();
                break;
            }
        }
        
        totalMembers--;
        
        emit MemberRemoved(_member);
    }
    
    /**
     * @notice Get member information
     * @param _member Address of the member
     * @return Member struct information
     */
    function getMember(address _member) external view returns (Member memory) {
        return members[_member];
    }
    
    /**
     * @notice Get all member addresses
     * @return Array of member addresses
     */
    function getAllMembers() external view returns (address[] memory) {
        return memberAddresses;
    }
    
    // ============ PROPOSAL FUNCTIONS ============
    
    /**
     * @notice Create a new proposal
     * @param _title Title of the proposal
     * @param _description Description of the proposal
     * @param _amount Amount requested (for funding proposals)
     * @param _recipient Recipient address (for funding proposals)
     * @param _proposalType Type of the proposal
     */
    function createProposal(
        string memory _title,
        string memory _description,
        uint256 _amount,
        address payable _recipient,
        ProposalType _proposalType
    ) external returns (uint256) {
        if (_balances[msg.sender] == 0) revert Unauthorised(); // Must hold tokens to create proposal
        if (bytes(_title).length == 0) revert InvalidAddress(); // Empty title
        if (bytes(_description).length == 0) revert InvalidAddress(); // Empty desc
        
        if (_proposalType == ProposalType.FUNDING) {
            if (_amount == 0) revert InvalidAmount();
            if (_recipient == address(0)) revert InvalidAddress();
            if (_amount > treasuryBalance) revert InsufficientBalance();
        } else if (_proposalType == ProposalType.TOKEN_TRANSFER) {
            if (_amount == 0) revert InvalidAmount();
            if (_recipient == address(0)) revert InvalidAddress();
            if (_amount > _balances[address(this)]) revert InsufficientBalance();
        }
        
        uint256 proposalId = totalProposals;
        
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            title: _title,
            description: _description,
            amount: _amount,
            recipient: _recipient,
            votesFor: 0,
            votesAgainst: 0,
            createdAt: block.timestamp,
            deadline: block.timestamp + votingPeriod,
            executed: false,
            cancelled: false,
            proposalType: _proposalType
        });
        
        totalProposals++;
        
        emit ProposalCreated(proposalId, msg.sender, _title, _proposalType);
        
        return proposalId;
    }
    
    /**
     * @notice Vote on a proposal
     * @param _proposalId ID of the proposal
     * @param _support True for yes, false for no
     */
    function vote(uint256 _proposalId, bool _support) external validProposal(_proposalId) {
        if (votes[_proposalId][msg.sender].hasVoted) revert AlreadyVoted();
        
        uint256 votingPower = _balances[msg.sender];
        if (votingPower == 0) revert Unauthorised(); // Must hold V9 tokens to vote

        votes[_proposalId][msg.sender] = Vote({
            hasVoted: true,
            support: _support,
            votedAt: block.timestamp
        });
        
        if (_support) {
            proposals[_proposalId].votesFor += votingPower;
        } else {
            proposals[_proposalId].votesAgainst += votingPower;
        }
        
        emit VoteCast(_proposalId, msg.sender, _support, votingPower);
    }
    
    /**
     * @notice Execute a proposal if it has passed
     * @param _proposalId ID of the proposal to execute
     */
    function executeProposal(uint256 _proposalId) external {
        if (_proposalId >= totalProposals) revert ProposalInactive();
        if (proposals[_proposalId].executed) revert AlreadyExecuted();
        if (proposals[_proposalId].cancelled) revert ProposalInactive();
        if (block.timestamp <= proposals[_proposalId].deadline) revert ProposalInactive();
        
        Proposal storage proposal = proposals[_proposalId];
        
        // Check if proposal has passed
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        uint256 totalVotingPower = getTotalVotingPower();
        
        if (totalVotes < (totalVotingPower * quorumPercentage) / 100) revert ProposalInactive(); // Quorum not reached
        if (proposal.votesFor <= proposal.votesAgainst) revert ProposalInactive(); // Not passed
        
        proposal.executed = true;
        
        bool success = true;
        
        // Execute based on proposal type
        if (proposal.proposalType == ProposalType.FUNDING) {
            if (proposal.amount <= treasuryBalance) {
                treasuryBalance -= proposal.amount;
                (success, ) = proposal.recipient.call{value: proposal.amount}("");
                if (success) {
                    emit FundsWithdrawn(proposal.recipient, proposal.amount);
                }
            } else {
                success = false;
            }
        } else if (proposal.proposalType == ProposalType.TOKEN_TRANSFER) {
            // Ensure we don't spend Syndicate funds (Logic Removed: Syndicate Funds are External)
            if (proposal.amount <= _balances[address(this)]) {
                _transfer(address(this), proposal.recipient, proposal.amount);
                emit TokensDistributed(proposal.recipient, proposal.amount);
                success = true;
            } else {
                success = false;
            }
        }
        
        emit ProposalExecuted(_proposalId, success);
    }
    
    /**
     * @notice Get proposal information
     * @param _proposalId ID of the proposal
     * @return Proposal struct information
     */
    function getProposal(uint256 _proposalId) external view returns (Proposal memory) {
        if (_proposalId >= totalProposals) revert ProposalInactive();
        return proposals[_proposalId];
    }
    
    /**
     * @notice Check if a member has voted on a proposal
     * @param _proposalId ID of the proposal
     * @param _member Address of the member
     * @return Vote information
     */
    function getVote(uint256 _proposalId, address _member) external view returns (Vote memory) {
        return votes[_proposalId][_member];
    }
    
    // ============ FUND MANAGEMENT FUNCTIONS ============
    
    /**
     * @notice Deposit funds to the DAO treasury
     */
    function depositFunds() external payable {
        if (msg.value == 0) revert InvalidAmount();
        treasuryBalance += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }
    
    /**
     * @notice Emergency withdrawal function (only owner)
     * @param _amount Amount to withdraw
     */
    function emergencyWithdraw(uint256 _amount) external onlyOwner {
        if (_amount > treasuryBalance) revert InsufficientBalance();
        if (_amount > address(this).balance) revert InsufficientBalance();
        
        treasuryBalance -= _amount;
        (bool success, ) = payable(owner).call{value: _amount}("");
        if (!success) revert TransferFailed();
        
        emit FundsWithdrawn(owner, _amount);
    }
    
    function withdrawReserve(uint256 amount) external onlyOwner {
        if (bondWallet == address(0)) revert InvalidAddress();

        // Check cooldown (1 week)
        if (block.timestamp < lastReserveWithdrawalTime + reserveWithdrawalCooldown) {
            revert WithdrawalCooldownActive();
        }

        // Check 30% limit of CURRENT balance
        uint256 currentBalance = reserveToken.balanceOf(address(this));
        uint256 maxAmount = (currentBalance * reserveWithdrawalLimitPercent) / 100;
        
        if (amount > maxAmount) {
            revert WithdrawalLimitExceeded();
        }

        // Update timestamp
        lastReserveWithdrawalTime = block.timestamp;

        if (!reserveToken.transfer(bondWallet, amount)) revert TransferFailed();
    }


    /**
     * @notice Get the current treasury ETH/BNB balance
     * @return Current treasury ETH/BNB balance
     */
    function getTreasuryBalance() external view returns (uint256) {
        return treasuryBalance;
    }

    /**
     * @notice Get the current treasury V9 Token balance (Total Contract Balance - Syndicate Pool)
     * @return Current treasury V9 balance
     */
    function getTreasuryV9Balance() external view returns (uint256) {
        return _balances[address(this)];
    }
    
    /**
     * @notice Get the contract's ETH balance
     * @return Contract's ETH balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // ============ GOVERNANCE FUNCTIONS ============
    
    /**
     * @notice Transfer ownership of the DAO
     * @param _newOwner Address of the new owner
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert InvalidAddress();
        if (_newOwner == owner) revert InvalidAddress();
        
        address previousOwner = owner;
        owner = _newOwner;
        
        emit OwnershipTransferred(previousOwner, _newOwner);
    }
    
    function addCustodian(address a) external onlyOwner {
        if (custodianCount == 0) {
            _addCustodian(a);
        } else {
            revert("Use queueAddCustodian");
        }
    }

    function _addCustodian(address a) internal {
        if (a == address(0)) revert InvalidAddress();
        if (custodians[a]) revert InvalidAddress();
        custodians[a] = true;
        custodianCount += 1;
    }
    


    /**
     * @notice Emergency function to reset custodians if access is lost
     * @dev Can only be called if custodianCount drops to 0 or 1
     */
    function emergencyResetCustodians() external onlyOwner {
        if (custodianCount > 1) revert("Too many custodians active");
        requiredConfirmations = 1;
    }

    function _queueChange(ChangeType _type, address _addr, uint256 _v1, uint256 _v2, uint256 _v3, bool _b) internal returns (uint256) {
        unchecked {
            changeCount += 1;
        }
        changes[changeCount] = Change(changeCount, _type, block.timestamp + timelockDelay, 0, false, _addr, _v1, _v2, _v3, _b);
        return changeCount;
    }

    function queueAddCustodian(address a) external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.ADD_CUSTODIAN, a, 0, 0, 0, false);
    }

    function queueRemoveCustodian(address a) external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.REMOVE_CUSTODIAN, a, 0, 0, 0, false);
    }
    
    function queuePause() external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.PAUSE_CONTRACT, address(0), 0, 0, 0, false);
    }

    function queueUnpause() external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.UNPAUSE_CONTRACT, address(0), 0, 0, 0, false);
    }

    function queueSetWithdrawalParams(uint256 _limitPercent, uint256 _cooldown) external onlyOwner returns (uint256) {
        if (_limitPercent > 100) revert InvalidAmount();
        return _queueChange(ChangeType.SET_WITHDRAWAL_PARAMS, address(0), _limitPercent, _cooldown, 0, false);
    }

    function setRequiredConfirmations(uint256 r) external onlyOwner {
        if (r == 0) revert InvalidAmount();
        if (r > custodianCount) revert InvalidAmount(); // Cannot require more confirmations than custodians
        requiredConfirmations = r;
    }

    function setExpenseWallet(address _wallet) external onlyOwner {
        if (_wallet == address(0)) revert InvalidAddress();
        expenseWallet = _wallet;
    }

    function setMintExpenseTax(uint256 _tax) external onlyOwner {
        if (_tax > 20) revert InvalidAmount(); // Safety cap
        mintExpenseTax = _tax;
    }
    
    function setProposalThreshold(uint256 p) external onlyOwner {
        if (p == 0) revert InvalidAmount();
        if (p > 10) revert InvalidAmount(); // Max 10% to prevent locking out everyone
        proposalThresholdPercentage = p;
    }
    
    function setVotingPeriod(uint256 _seconds) external onlyOwner {
        if (_seconds < 1 days) revert InvalidAmount();
        votingPeriod = _seconds;
    }
    
    function setQuorumPercentage(uint256 _percentage) external onlyOwner {
        if (_percentage == 0 || _percentage > 100) revert InvalidAmount();
        quorumPercentage = _percentage;
    }

    function setTimelockDelay(uint256 d) external onlyOwner {
        if (d < 1 hours) revert InvalidAmount();
        timelockDelay = d;
    }
    
    function queueSetMarket(address _pair) external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.SET_MARKET, _pair, 0, 0, 0, false);
    }
    
    function queueSetFactors(uint256 _u, uint256 _o, uint256 _t) external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.SET_FACTORS, address(0), _u, _o, _t, false);
    }
    
    function queueSetSellTax(uint256 _tax) external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.SET_SELL_TAX, address(0), _tax, 0, 0, false);
    }

    function queueSetSyndicate(uint256 _tax, uint256 _share) external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.SET_SYNDICATE, address(0), _tax, _share, 0, false);
    }
    
    function queueSetEmissionsEnabled(bool enabled) external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.SET_EMISSIONS, address(0), 0, 0, 0, enabled);
    }
    
    function queueSetDirectAccess(bool enabled) external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.SET_DIRECT, address(0), 0, 0, 0, enabled);
    }
    
    function queueWithdrawReserve(uint256 amount) external onlyOwner returns (uint256) {
        return _queueChange(ChangeType.WITHDRAW_RESERVE, address(0), amount, 0, 0, false);
    }
    
    function approveChange(uint256 id) external {
        if (!custodians[msg.sender]) revert Unauthorised();
        Change storage c = changes[id];
        if (c.executed) revert AlreadyExecuted();
        if (changeApprovals[id][msg.sender]) revert AlreadyVoted();
        changeApprovals[id][msg.sender] = true;
        unchecked {
            c.approvals += 1;
        }
    }
    
    function executeChange(uint256 id) external {
        Change storage c = changes[id];
        if (c.executed) revert AlreadyExecuted();
        if (block.timestamp < c.scheduleTime) revert TimelockActive();
        if (c.approvals < requiredConfirmations) revert Unauthorised();
        
        if (c.changeType == ChangeType.SET_MARKET) {
            market = c.addr;
        } else if (c.changeType == ChangeType.SET_FACTORS) {
            if (c.v1 == 0) revert InvalidAmount();
            uFactor = c.v1;
            oFactor = c.v2;
            tFactor = c.v3;
        } else if (c.changeType == ChangeType.SET_SELL_TAX) {
            if (c.v1 > 20) revert InvalidAmount();
            sellTax = c.v1;
        } else if (c.changeType == ChangeType.SET_SYNDICATE) {
            if (c.v1 > 20) revert InvalidAmount();
            sellTax = c.v1;
            sFactor = c.v2;
        } else if (c.changeType == ChangeType.SET_EMISSIONS) {
            emissionsEnabled = c.b;
        } else if (c.changeType == ChangeType.SET_DIRECT) {
            directAccess = c.b;
        } else if (c.changeType == ChangeType.WITHDRAW_RESERVE) {
            if (bondWallet == address(0)) revert InvalidAddress();
            if (!reserveToken.transfer(bondWallet, c.v1)) revert TransferFailed();
        } else if (c.changeType == ChangeType.ADD_CUSTODIAN) {
            _addCustodian(c.addr);
        } else if (c.changeType == ChangeType.REMOVE_CUSTODIAN) {
            if (!custodians[c.addr]) revert InvalidAddress();
            custodians[c.addr] = false;
            custodianCount -= 1;
            if (custodianCount < requiredConfirmations) {
                requiredConfirmations = custodianCount;
            }
        } else if (c.changeType == ChangeType.PAUSE_CONTRACT) {
            paused = true;
            emit Paused(msg.sender);
        } else if (c.changeType == ChangeType.UNPAUSE_CONTRACT) {
            paused = false;
            emit Unpaused(msg.sender);
        } else if (c.changeType == ChangeType.SET_WITHDRAWAL_PARAMS) {
            if (c.v1 > 100) revert InvalidAmount();
            reserveWithdrawalLimitPercent = c.v1;
            reserveWithdrawalCooldown = c.v2;
        }
        c.executed = true;
    }
    
    /**
     * @notice Get total voting power of all active members
     * @return Total voting power
     */
    function getTotalVotingPower() public view returns (uint256) {
        return _totalSupply - _balances[address(this)];
    }
    
    /**
     * @notice Check if an address is an active member
     * @param _address Address to check
     * @return True if address is an active member
     */
    function isMember(address _address) external view returns (bool) {
        return members[_address].isActive;
    }
    
    // ============ BLACKLIST FUNCTIONS ============

    /**
     * @notice Blacklist an address to prevent transfers
     * @param _account Address to blacklist
     */
    function blacklistAddress(address _account) external onlyOwner {
        if (_account == address(0)) revert InvalidAddress();
        if (isBlacklisted[_account]) revert AddressBlacklisted();
        isBlacklisted[_account] = true;
        emit Blacklisted(_account);
    }

    /**
     * @notice Remove an address from blacklist
     * @param _account Address to unblacklist
     */
    function unBlacklistAddress(address _account) external onlyOwner {
        if (_account == address(0)) revert InvalidAddress();
        if (!isBlacklisted[_account]) revert InvalidAddress(); // Not blacklisted
        isBlacklisted[_account] = false;
        emit UnBlacklisted(_account);
    }

    // ============ SPENDING LIMIT FUNCTIONS ============

    /**
     * @notice Set daily spending limit for an address
     * @param _account Address to restrict
     * @param _limit Daily limit amount (0 to remove limit)
     */
    function setDailyLimit(address _account, uint256 _limit) external onlyOwner {
        if (_account == address(0)) revert InvalidAddress();
        spendingLimits[_account] = SpendingLimit({
            limit: _limit,
            spent: 0,
            lastReset: block.timestamp
        });
        emit DailyLimitSet(_account, _limit);
    }

    /**
     * @notice Transfer tokens and apply daily limit in one transaction
     * @param _to Recipient address
     * @param _amount Amount to transfer
     * @param _dailyLimit Daily limit to apply
     */
    function transferWithLimit(address _to, uint256 _amount, uint256 _dailyLimit) external onlyOwner {
        // 1. Set Limit First
        spendingLimits[_to] = SpendingLimit({
            limit: _dailyLimit,
            spent: 0,
            lastReset: block.timestamp
        });
        emit DailyLimitSet(_to, _dailyLimit);

        // 2. Transfer Tokens
        _transfer(msg.sender, _to, _amount);
    }

    // ============ UTILITY FUNCTIONS ============
    
    /**
     * @notice Receive function to accept ETH deposits
     */
    receive() external payable {
        treasuryBalance += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }
    
    /**
     * @notice Fallback function
     */
    fallback() external payable {
        treasuryBalance += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }
}
