// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x675b2d54df8045f2a296ea566b21a10c793836ef
// Contract Name: Lust
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/* =========================================================
 *  Lust - Decentralized (v1.0.17 Final Audit)
 *  Redes: BNB Chain, Polygon
 *  Deploy: Remix Compiler 0.8.30 + optimization enabled
 * ========================================================= */

// ========== INTERFACES ==========

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

// ===== Token LUST =====

contract Lust is IERC20, IMintable {
    string public name = "Lust";
    string public symbol = "LST";
    uint8 public decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    address public feeReceiver;
    address public feeDestination;
    address public immutable initialFeeReceiver;

    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public authorizedMinters;

    bytes32 public DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event ControlRenounced(address previousReceiver);

    constructor() {
        feeReceiver = msg.sender;
        feeDestination = msg.sender;
        initialFeeReceiver = msg.sender;

        // Whitelisted Exchanges (no fees)
    isWhitelisted[0x28C6c06298d514Db089934071355E5743bf21d60] = true; // Binance
    isWhitelisted[0x2c2F7E7C5604d162D2f346C470B299E2934EBc84] = true; // OKX
    isWhitelisted[0x503828976D22510aad0201ac7EC88293211D23Da] = true; // Coinbase
    isWhitelisted[0x1BFeEA39880225b260f2FaaE27fD7A6B1dd9f1Cd] = true; // Bybit
    isWhitelisted[0xFa4b761c8A6F45E7b6F648BdE8b2528F2C8c0Aa9] = true; // KuCoin
    isWhitelisted[0x8F22F2063d253846b53609231Ed80fa571Bc0C8c] = true; // Bitget
    isWhitelisted[0x5C985E89DDe482eFE97ea9f1950aD149Eb73829B] = true; // Huobi (HTX)
    isWhitelisted[0xEA3bCf0Ed8a2E3F5DC21CE09616C7F7E1427e2d7] = true; // Gate.io
    isWhitelisted[0xF7a0f23c2b69E28d6d3a5C5Bb12C6EFdD3C12187] = true; // MEXC
    isWhitelisted[0x46340b20830761efd32832A74d7169B29FEB9758] = true; // Crypto.com
    isWhitelisted[0x5E575279bf9f4acf0A130c186861454247394C06] = true; // Kraken
    isWhitelisted[0x876EabF441B2EE5B5b0554Fd502a8E0600950cFa] = true; // Bitfinex
    isWhitelisted[0x5AbFEc25f74Cd88437631a7731906932776356f9] = true; // LBank
    isWhitelisted[0xA7EFAe728D2936e78BDA97dc267687568dD593f3] = true; // BingX
    isWhitelisted[0x8c59cF41A05D2DD64f3d26D3a43E6e8a1919A27A] = true; // CoinEx


        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Not approved");
        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(amount > 0, "Zero amount");
        require(balanceOf[from] >= amount, "Insufficient balance");

        if (isWhitelisted[from] || isWhitelisted[to]) {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
            emit Transfer(from, to, amount);
            return true;
        }

        uint256 fee = (amount * 1) / 100;
        uint256 burnAmount = fee / 2;
        uint256 receiverAmount = fee - burnAmount;

        require(balanceOf[from] >= amount + fee, "Need amount + fee");

        balanceOf[from] -= amount + fee;
        balanceOf[to] += amount;
        balanceOf[feeDestination] += receiverAmount;
        totalSupply -= burnAmount;

        emit Transfer(from, to, amount);
        emit Transfer(from, feeDestination, receiverAmount);
        emit Transfer(from, address(0), burnAmount);
        emit Burn(from, burnAmount);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "Expired");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "176",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recovered = ecrecover(digest, v, r, s);
        require(recovered == owner && recovered != address(0), "Invalid sig");

        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function mint(address to, uint256 amount) external override {
        require(to != address(0), "Zero address");
        require(msg.sender == feeReceiver || authorizedMinters[msg.sender], "Not authorized");
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
    }

    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Not enough");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
        emit Burn(msg.sender, amount);
    }

    function updateFeeReceiver(address newReceiver) external {
        require(msg.sender == feeReceiver, "Only current");
        feeReceiver = newReceiver;
    }

    function updateFeeDestination(address newDest) external {
        require(msg.sender == feeDestination, "Only current");
        feeDestination = newDest;
    }

    function setWhitelist(address user, bool status) external {
        require(msg.sender == feeReceiver, "Only creator");
        isWhitelisted[user] = status;
    }

    function authorizeMinter(address minter, bool status) external {
        require(msg.sender == feeReceiver, "Only creator");
        authorizedMinters[minter] = status;
    }

    function renounceControl() external {
        require(msg.sender == feeReceiver, "Only owner");
        emit ControlRenounced(feeReceiver);
        feeReceiver = address(0);
    }

    function getWhitelisted(address user) external view returns (bool) {
        return isWhitelisted[user];
    }
}

// ===== PresaleBonusController =====

contract PresaleBonusController {
    IERC20 public usdt;
    IWETH public wrappedNative;
    AggregatorV3Interface public priceFeed;
    INonfungiblePositionManager public positionManager;

    IERC20 public token;
    IMintable public minter;

    address public creator;
    bool public presaleStarted;
    bool public liquidityCreated;
    bool public refundsAllowed;

    uint256 public presaleEndTime;
    uint256 public totalTokensForPresale = 20_000_000 * 1e18;
    uint256 public tokensSold;

    uint256 public stage1Tokens = 10_000_000 * 1e18;
    uint256 public stage2Tokens = 6_000_000 * 1e18;
    uint256 public stage3Tokens = 4_000_000 * 1e18;

    uint256 public stage1Bonus = 12;
    uint256 public stage2Bonus = 5;
    uint256 public stage3Bonus = 3;

    mapping(address => uint256) public contributionsUSDT;
    mapping(address => uint256) public bonusesLST;
    mapping(address => uint8) public claimedStages;

    event PresaleStarted(uint256 endTime);
    event Purchased(address indexed buyer, uint256 usdtAmount6, uint256 lstAmount18, uint256 bonusPercent);
    event BonusClaimed(address indexed user, uint256 amount18, uint8 stage);
    event LiquidityCreated(uint256 usdtAdded6, uint256 lstMinted18);
    event RefundEnabled();
    event RefundIssued(address indexed user, uint256 amount6);
    event ControlRenounced(address previousCreator);

    modifier onlyCreator() {
        require(msg.sender == creator, "Only creator");
        _;
    }

    constructor(address _minter) {
        creator = msg.sender;
        minter = IMintable(_minter);
        token = IERC20(_minter);

        // BNB Chain
        usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
        wrappedNative = IWETH(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
        priceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);
        positionManager = INonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
    }

    function startPresale(uint256 durationSeconds) external onlyCreator {
        require(!presaleStarted, "Presale already started");
        presaleStarted = true;
        presaleEndTime = block.timestamp + durationSeconds;
        emit PresaleStarted(presaleEndTime);
    }

    function buyWithNative() external payable {
        require(presaleStarted && block.timestamp < presaleEndTime, "Presale not active");
        require(msg.value > 0, "No native sent");
        uint256 usdtAmount6 = _nativeToUSDT6(msg.value);
        require(usdtAmount6 >= 1e6, "Minimum 1 USDT");
        _processPurchase(msg.sender, usdtAmount6);
    }

    function buyWithUSDT(uint256 usdtAmount6) external {
        require(presaleStarted && block.timestamp < presaleEndTime, "Presale not active");
        require(usdtAmount6 >= 1e6, "Minimum 1 USDT");
        require(usdt.transferFrom(msg.sender, address(this), usdtAmount6), "USDT transfer failed");
        _processPurchase(msg.sender, usdtAmount6);
    }

    function _processPurchase(address buyer, uint256 valueInUSDT6) internal {
        uint256 toMint18 = valueInUSDT6 * 1e12;
        uint256 bonusPercent;
        if (tokensSold < stage1Tokens) bonusPercent = stage1Bonus;
        else if (tokensSold < stage1Tokens + stage2Tokens) bonusPercent = stage2Bonus;
        else if (tokensSold < totalTokensForPresale) bonusPercent = stage3Bonus;
        else revert("Presale sold out");

        require(tokensSold + toMint18 <= totalTokensForPresale, "Exceeds cap");

        tokensSold += toMint18;
        minter.mint(buyer, toMint18);

        uint256 bonus18 = (toMint18 * bonusPercent) / 100;
        bonusesLST[buyer] += bonus18;
        contributionsUSDT[buyer] += valueInUSDT6;

        emit Purchased(buyer, valueInUSDT6, toMint18, bonusPercent);
    }

    function claimBonus() external {
        uint8 stage = claimedStages[msg.sender];
        require(stage < 3, "All claimed");
        require(block.timestamp >= presaleEndTime + (stage + 1) * 20 days, "Locked");

        uint256 totalBonus = bonusesLST[msg.sender];
        require(totalBonus > 0, "No bonus");

        uint256 amount = totalBonus / 3;
        claimedStages[msg.sender] = stage + 1;
        minter.mint(msg.sender, amount);

        emit BonusClaimed(msg.sender, amount, stage + 1);
    }

    function finalizePresaleAndCreateLiquidity() external onlyCreator {
        require(presaleStarted, "Not started");
        require(!liquidityCreated, "Already finalized");
        require(block.timestamp >= presaleEndTime || tokensSold >= totalTokensForPresale, "Not finished");

        uint256 totalUSDT = usdt.balanceOf(address(this));
        require(totalUSDT > 0, "No funds");

        uint256 liquidityUSDT = (totalUSDT * 90) / 100;
        uint256 creatorUSDT = totalUSDT - liquidityUSDT;

        uint256 unsold = totalTokensForPresale - tokensSold;
        if (unsold > 0) minter.mint(address(0), unsold);

        uint256 liquidityLST = liquidityUSDT * 1e12;
        minter.mint(address(this), liquidityLST);

        usdt.approve(address(positionManager), liquidityUSDT);
        token.approve(address(positionManager), liquidityLST);

        (address token0, address token1) = address(token) < address(usdt)
            ? (address(token), address(usdt))
            : (address(usdt), address(token));

        uint256 amt0 = token0 == address(token) ? liquidityLST : liquidityUSDT;
        uint256 amt1 = token0 == address(token) ? liquidityUSDT : liquidityLST;

        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: amt0,
                amount1Desired: amt1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: creator,
                deadline: block.timestamp
            })
        );

        usdt.transfer(creator, creatorUSDT);
        liquidityCreated = true;
        refundsAllowed = false;
        emit LiquidityCreated(liquidityUSDT, liquidityLST);
    }

    function enableRefunds() external onlyCreator {
        require(!liquidityCreated, "Already finalized");
        refundsAllowed = true;
        emit RefundEnabled();
    }

    function claimRefund() external {
        require(refundsAllowed, "Not enabled");
        uint256 amount = contributionsUSDT[msg.sender];
        require(amount > 0, "Nothing to refund");
        contributionsUSDT[msg.sender] = 0;
        usdt.transfer(msg.sender, amount);
        emit RefundIssued(msg.sender, amount);
    }

    function renounceCreator() external onlyCreator {
        emit ControlRenounced(creator);
        creator = address(0);
    }

    function getCurrentStage() external view returns (uint8) {
        if (tokensSold < stage1Tokens) return 1;
        else if (tokensSold < stage1Tokens + stage2Tokens) return 2;
        else if (tokensSold < totalTokensForPresale) return 3;
        else return 0;
    }

    function _nativeToUSDT6(uint256 nativeWei) internal view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return (nativeWei * uint256(price)) / 1e20;
    }

    receive() external payable {}

}

// ===== LustStakingTiers =====

contract LustStakingTiers {
    IERC20 public token;
    IMintable public minter;
    address public creator;
    bool public stakingStarted;

    enum Tier { Bronze, Silver, Gold, Diamond }

    struct Stake {
        uint256 amount;
        uint256 startTime;
        Tier tier;
        bool withdrawn;
    }

    mapping(address => Stake[]) public userStakes;

    uint256[4] public minLockPeriods = [
        30 days,
        60 days,
        90 days,
        180 days
    ];

    uint256[4] public rewardRates = [
        5,
        10,
        20,
        30
    ];

    uint256[4] public penaltyRates = [
        10,
        8,
        5,
        3
    ];

    mapping(address => uint256) public boosterMultiplier;

    event StakeCreated(address indexed user, uint256 amount, Tier tier);
    event Withdrawn(address indexed user, uint256 index, uint256 reward, uint256 penalty);
    event ControlRenounced(address previousCreator);
    event PenaltyBurned(address indexed user, uint256 amount);

    modifier onlyCreator() {
        require(msg.sender == creator, "Only creator");
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
        minter = IMintable(_token);
        creator = msg.sender;
    }

    function start() external onlyCreator {
        require(!stakingStarted, "Already started");
        stakingStarted = true;
    }

    function renounceCreator() external onlyCreator {
        emit ControlRenounced(creator);
        creator = address(0);
    }

    function stake(uint256 amount, Tier tier) external {
        require(stakingStarted, "Not started");
        require(amount > 0, "Amount > 0");
        require(uint8(tier) <= 3, "Invalid tier");

        token.transferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender].push(Stake(amount, block.timestamp, tier, false));

        emit StakeCreated(msg.sender, amount, tier);
    }

    function withdraw(uint256 index) external {
        require(stakingStarted, "Not started");
        require(index < userStakes[msg.sender].length, "Invalid index");

        Stake storage s = userStakes[msg.sender][index];
        require(!s.withdrawn, "Already withdrawn");

        uint8 t = uint8(s.tier);
        uint256 lockTime = minLockPeriods[t];
        uint256 reward = 0;
        uint256 amountToReturn = s.amount;

        if (block.timestamp >= s.startTime + lockTime) {
            uint256 baseReward = (s.amount * rewardRates[t]) / 100;
            uint256 multiplier = boosterMultiplier[msg.sender] > 0 ? boosterMultiplier[msg.sender] : 100;
            reward = (baseReward * multiplier) / 100;

            minter.mint(msg.sender, reward);
            token.transfer(msg.sender, amountToReturn);
        } else {
            uint256 penalty = (s.amount * penaltyRates[t]) / 100;
            amountToReturn -= penalty;
            token.transfer(msg.sender, amountToReturn);
            token.transfer(address(0), penalty);
            emit PenaltyBurned(msg.sender, penalty);
        }

        s.withdrawn = true;
        emit Withdrawn(msg.sender, index, reward, s.amount - amountToReturn);
    }

    function getPendingRewardsAll(address user) external view returns (uint256 total) {
        Stake[] memory stakes = userStakes[user];
        for (uint256 i = 0; i < stakes.length; i++) {
            Stake memory s = stakes[i];
            if (!s.withdrawn && block.timestamp >= s.startTime + minLockPeriods[uint8(s.tier)]) {
                uint256 base = (s.amount * rewardRates[uint8(s.tier)]) / 100;
                uint256 multiplier = boosterMultiplier[user] > 0 ? boosterMultiplier[user] : 100;
                total += (base * multiplier) / 100;
            }
        }
    }

    function getAllStakes(address user) external view returns (
        uint256[] memory amounts,
        uint256[] memory startTimes,
        uint8[] memory tiers,
        bool[] memory withdrawn,
        uint256[] memory unlockTimes
    ) {
        uint256 len = userStakes[user].length;
        amounts = new uint256[](len);
        startTimes = new uint256[](len);
        tiers = new uint8[](len);
        withdrawn = new bool[](len);
        unlockTimes = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            Stake memory s = userStakes[user][i];
            amounts[i] = s.amount;
            startTimes[i] = s.startTime;
            tiers[i] = uint8(s.tier);
            withdrawn[i] = s.withdrawn;
            unlockTimes[i] = s.startTime + minLockPeriods[uint8(s.tier)];
        }
    }

    function version() external pure returns (string memory) {
        return "Staking v1.0.17";
    }
}