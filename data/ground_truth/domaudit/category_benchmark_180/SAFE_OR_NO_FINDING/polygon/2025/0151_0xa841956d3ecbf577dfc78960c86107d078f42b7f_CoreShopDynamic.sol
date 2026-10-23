// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xa841956d3ecbf577dfc78960c86107d078f42b7f
// Contract Name: CoreShopDynamic



// ============================================================
// FILE: CoreShopDynamic.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

interface INovaToken is IERC20Upgradeable {
    function burn(uint256 amount) external;
}

// ✅ EIP-2612 Permit 인터페이스
interface IPermitToken is IERC20Upgradeable {
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

interface INovaEvolutionNFT {
    function mintWithNOVAPermit(
        address user,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        string memory currency,
        uint256 price
    ) external;
    
    // ✅ [신규] 상점 전용 민팅 함수
    function mintFromShop(address user, string memory currency, uint256 price) external;
}

interface IDailyRewards {
    function addUserPoints(address user, uint256 points) external;
    function getUserInfo(address user) external view returns (uint256, uint256, uint64, bool);
    function coreShopAddress() external view returns (address);
    function setTrustedForwarder(address forwarder) external;
    function setUserPass(address user, uint256 dailyRewardAmount, bool hasPass, uint8 passType) external;  // ✅ passType 추가
}

// ✅ 스테이킹 컨트랙트 인터페이스 추가
interface IStakingV2 {
    function refreshMyAPY(uint256 poolId) external;
}

interface IAchievementSystem {
    function createRecord(
        address user,
        uint8 recordType,
        uint256 amount,
        string memory metadata
    ) external returns (uint256);
}

/**
 * @title CoreShop Dynamic with CoinGecko API
 * @notice USDT 기준 동적 가격 시스템 (CoinGecko API 연동)
 * 
 * ✅ Polygon Mainnet에 배포됨
 * 🔄 가격은 앱에서 CoinGecko API로 조회 후 관리자가 수동 업데이트
 * 
 * 📝 가격 설정 (테스트용):
 * - PointCore: 100 USDT = 100 NOVA (1:1 비율)
 * - BoostCore: 100 USDT
 * - NFTCore: 500 USDT
 * - 향후 변경: setPointCoreUsdtPrice(newPrice) 함수로 수정 가능
 */
contract CoreShopDynamic is 
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ============ 상수 ============
    uint256 public constant POINTS_PER_BUNDLE = 100;
    uint256 public constant MAX_BOOST_CORES = 30;
    uint256 public constant BOOST_APY_INCREASE = 50;
    uint256 public constant USDT_UNIT = 1e6;

    // ============ 상태 변수 ============
    IERC20Upgradeable public polToken;
    INovaToken public novaToken;
    IDailyRewards public dailyRewards;
    IStakingV2 public stakingContract;
    
    address public projectWallet;
    address public novaProjectWallet;

    IAchievementSystem public achievementSystem;
    
    bool public isNovaPoolActive;
    
    // 사용자 소유 현황
    mapping(address => uint256) public boostCoreCount;
    mapping(address => uint256) public nftCoreCount;
    mapping(address => uint256) public pointCoreBundleCount;
    
    // ✅ [신규] NovaEvolutionNFT 연동 (맨 뒤에 추가)
    INovaEvolutionNFT public novaEvolutionNFT;
    address public novaEvolutionNFTAddress;

    // ✅ [신규] 추천인 분배 (기존 레이아웃 맨 끝에 추가)
    uint16 public referralBP; // in basis points (e.g., 500 = 5%)
    uint240 private __reservedReferral; // padding for future extension

    function setAchievementSystem(address _achievement) external onlyOwner {
        require(_achievement != address(0), "invalid address");
        achievementSystem = IAchievementSystem(_achievement);
    }
    
    // ============ 이벤트 ============
    event BoostCorePurchased(address indexed user, uint256 quantity, string currency);
    event NFTCorePurchased(address indexed user, uint256 quantity, string currency);
    event PointCorePurchased(address indexed user, uint256 quantity, string currency);
    event PriceUpdated(string coreType, uint256 usdtPrice);
    event ExchangeRateUpdated(uint256 polPerUsdt, uint256 novaPerUsdt, uint256 timestamp);
    event NovaPoolActivated(uint256 novaPerUsdt);
    event ReferralPaid(address indexed user, address indexed referrer, uint256 rewardAmount, string currency, string itemType, uint256 totalPrice);
    event ReferralSplitPaid(address indexed user, address indexed primaryReferrer, address indexed secondaryWallet, uint256 primaryAmount, uint256 secondaryAmount, string currency, uint256 totalPrice);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 계약 초기화
     */
    function initialize(
        address _polToken,
        address _novaToken,
        address _dailyRewards,
        address _projectWallet,
        address _novaProjectWallet,
        address _stakingContract  // ✅ 새로 추가
    ) public initializer {
        require(_polToken != address(0), "invalid POL");
        require(_novaToken != address(0), "invalid NOVA");
        require(_dailyRewards != address(0), "invalid DailyRewards");
        require(_projectWallet != address(0), "invalid project wallet");
        require(_novaProjectWallet != address(0), "invalid nova project wallet");
        require(_stakingContract != address(0), "invalid staking contract");  // ✅ 검증 추가

        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        polToken = IERC20Upgradeable(_polToken);
        novaToken = INovaToken(_novaToken);
        dailyRewards = IDailyRewards(_dailyRewards);
        stakingContract = IStakingV2(_stakingContract);
        projectWallet = _projectWallet;
        novaProjectWallet = _novaProjectWallet;
        referralBP = 500; // default 5%

        // ✅ NOVA 풀 활성화
        // 모든 가격은 앱에서 API로 조회하여 직접 전달하므로 컨트랙트에서 관리 불필요
        isNovaPoolActive = true;
        emit NovaPoolActivated(0);
    }

    // ============ NOVA 풀 활성화 ============
    
    /**
     * @notice NOVA 풀 활성화 (앱에서 API 가격만 사용)
     * @dev 가격은 모두 앱에서 관리
     */
    function activateNovaPool() external onlyOwner {
        require(!isNovaPoolActive, "NOVA pool already active");
        isNovaPoolActive = true;
        emit NovaPoolActivated(0);  // 가격 정보 제거
    }

    // ============ 기타 관리자 함수 ============
    
    function setDailyRewards(address _dailyRewards) external onlyOwner {
        require(_dailyRewards != address(0), "invalid address");
        dailyRewards = IDailyRewards(_dailyRewards);
    }

    function setProjectWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "invalid address");
        projectWallet = _wallet;
    }

    function setNovaProjectWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "invalid address");
        novaProjectWallet = _wallet;
    }

    function setReferralBP(uint16 _bp) external onlyOwner {
        require(_bp <= 10_000, "bp too high");
        referralBP = _bp;
    }

    function setReferrerCustomBP(address referrer, uint16 customBP) external onlyOwner {
        require(referrer != address(0), "invalid referrer");
        require(customBP <= 10_000, "bp too high");
        referrerCustomBP[referrer] = customBP;
    }

    function setReferralSplit(
        address referrer,
        uint16 primaryBP,
        uint16 secondaryBP,
        address secondaryWallet
    ) external onlyOwner {
        require(referrer != address(0), "invalid referrer");
        require(secondaryWallet != address(0), "invalid secondary wallet");
        require(primaryBP + secondaryBP <= 10_000, "bp sum too high");
        
        referralSplits[referrer] = ReferralSplitConfig({
            primaryBP: primaryBP,
            secondaryBP: secondaryBP,
            secondaryWallet: secondaryWallet
        });
    }

    function clearReferralSplit(address referrer) external onlyOwner {
        require(referrer != address(0), "invalid referrer");
        delete referralSplits[referrer];
    }

    function setNovaEvolutionNFT(address _nftContract) external onlyOwner {
        require(_nftContract != address(0), "invalid address");
        novaEvolutionNFTAddress = _nftContract;
        novaEvolutionNFT = INovaEvolutionNFT(_nftContract);
    }

    // ============ 가격 계산 함수 제거됨 ============
    // 모든 가격은 앱에서 API로 조회 후 직접 전달하므로
    // 컨트랙트에서는 가격 계산 불필요

    // ============ 부스트 코어 구매 ============
    
    /**
     * @notice POL로 BoostCore 구매
     * @param quantity 구매 수량
     * @param totalPrice 앱에서 조회한 API 가격 (Wei)
     */
    function buyBoostCorePOL(uint256 quantity, uint256 totalPrice, address referrer) external payable nonReentrant {
        require(quantity > 0, "quantity=0");
        require(totalPrice > 0, "price=0");
        require(msg.value == totalPrice, "incorrect POL amount");
        require(boostCoreCount[msg.sender] + quantity <= MAX_BOOST_CORES, "exceed max boost cores");

        uint256 totalReferralAmount = 0;
        ReferralSplitConfig memory config = referralSplits[referrer];
        
        if (referrer != address(0) && referrer != msg.sender) {
            if (config.primaryBP > 0) {
                uint256 primaryAmount = (totalPrice * config.primaryBP) / 10_000;
                uint256 secondaryAmount = (totalPrice * config.secondaryBP) / 10_000;
                totalReferralAmount = primaryAmount + secondaryAmount;
                
                if (primaryAmount > 0) {
                    (bool ok1, ) = referrer.call{value: primaryAmount}("");
                    require(ok1, "referral primary POL transfer failed");
                }
                if (secondaryAmount > 0) {
                    (bool ok2, ) = config.secondaryWallet.call{value: secondaryAmount}("");
                    require(ok2, "referral secondary POL transfer failed");
                }
                emit ReferralSplitPaid(msg.sender, referrer, config.secondaryWallet, primaryAmount, secondaryAmount, "POL", totalPrice);
            } else {
                uint256 reward = _calcReferral(totalPrice, referrer);
                if (reward > 0) {
                    (bool rOk, ) = referrer.call{value: reward}("");
                    require(rOk, "referral POL transfer failed");
                    totalReferralAmount = reward;
                    emit ReferralPaid(msg.sender, referrer, reward, "POL", "BOOST", totalPrice);
                }
            }
        }

        uint256 rest = totalPrice - totalReferralAmount;
        (bool ok, ) = projectWallet.call{value: rest}("");
        require(ok, "POL transfer failed");

        boostCoreCount[msg.sender] += quantity;
        emit BoostCorePurchased(msg.sender, quantity, "POL");
        
        // ⚠️ [수정] 스테이킹 APY 갱신 제거
        // 이유: 스테이킹 컨트랙트에서 자체적으로 CoreShop 상태 변경 감지 후 자동 갱신
        // _refreshUserStakingAPY(msg.sender);
        
        // ✅ 업적 기록
        if (address(achievementSystem) != address(0)) {
            try achievementSystem.createRecord(
                msg.sender,
                5,  // 부스트 코어 구매
                quantity,
                ""
            ) {} catch {}
        }
    }

    /**
     * @notice Permit 기반 BoostCore 구매 (EIP-2612)
     * @dev 스테이킹과 동일한 Permit 방식 적용
     * @param price 실시간 API에서 조회한 NOVA Wei 단위 가격
     */
    function buyBoostCoreNOVAPermit(
        uint256 quantity,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 price,  // ← 반드시 앱에서 API 가격 전달
        address referrer
    ) external nonReentrant {
        require(quantity > 0, "E1: quantity=0");
        require(isNovaPoolActive, "E2: NOVA pool not active");
        require(boostCoreCount[msg.sender] + quantity <= MAX_BOOST_CORES, "E3: exceed max boost");
        require(price > 0, "E4: invalid price");
        
        // ✅ 앱에서 전달받은 API 가격만 사용
        uint256 totalPrice = price * quantity;
        require(totalPrice > 0, "E5: price calc failed");

        // ✅ EIP-2612 Permit으로 allowance 설정 (스테이킹과 동일)
        try IPermitToken(address(novaToken)).permit(
            msg.sender,
            address(this),
            totalPrice,
            deadline,
            v,
            r,
            s
        ) {} catch {}
        
        // ✅ Permit 이후 transferFrom (실패하면 E7 에러)
        uint256 totalReferralAmount = 0;
        ReferralSplitConfig memory config = referralSplits[referrer];
        
        if (referrer != address(0) && referrer != msg.sender) {
            if (config.primaryBP > 0) {
                uint256 primaryAmount = (totalPrice * config.primaryBP) / 10_000;
                uint256 secondaryAmount = (totalPrice * config.secondaryBP) / 10_000;
                totalReferralAmount = primaryAmount + secondaryAmount;
                
                if (primaryAmount > 0) {
                    bool ok1 = novaToken.transferFrom(msg.sender, referrer, primaryAmount);
                    require(ok1, "E7R1: referral primary transfer failed");
                }
                if (secondaryAmount > 0) {
                    bool ok2 = novaToken.transferFrom(msg.sender, config.secondaryWallet, secondaryAmount);
                    require(ok2, "E7R2: referral secondary transfer failed");
                }
                emit ReferralSplitPaid(msg.sender, referrer, config.secondaryWallet, primaryAmount, secondaryAmount, "NOVA", totalPrice);
            } else {
                uint256 reward = _calcReferral(totalPrice, referrer);
                if (reward > 0) {
                    bool okReward = novaToken.transferFrom(msg.sender, referrer, reward);
                    require(okReward, "E7R: referral transfer failed");
                    totalReferralAmount = reward;
                    emit ReferralPaid(msg.sender, referrer, reward, "NOVA", "BOOST", totalPrice);
                }
            }
        }
        
        uint256 rest = totalPrice - totalReferralAmount;
        bool ok = novaToken.transferFrom(msg.sender, novaProjectWallet, rest);
        require(ok, "E7: NOVA transfer failed");

        boostCoreCount[msg.sender] += quantity;
        emit BoostCorePurchased(msg.sender, quantity, "NOVA");
        
        // ⚠️ [수정] 스테이킹 APY 갱신 제거
        // 이유: 스테이킹 컨트랙트에서 자체적으로 CoreShop 상태 변경 감지 후 자동 갱신
        // _refreshUserStakingAPY(msg.sender);
    }

    // ============ NFT 코어 구매 ============
    
    /**
     * @notice POL로 NFTCore 구매
     * @param quantity 구매 수량
     * @param totalPrice 앱에서 조회한 API 가격 (Wei)
     */
    function buyNFTCorePOL(uint256 quantity, uint256 totalPrice, address referrer) external payable nonReentrant {
        require(quantity > 0, "quantity=0");
        require(totalPrice > 0, "price=0");
        require(msg.value == totalPrice, "incorrect POL amount");

        uint256 totalReferralAmount = 0;
        ReferralSplitConfig memory config = referralSplits[referrer];
        
        if (referrer != address(0) && referrer != msg.sender) {
            if (config.primaryBP > 0) {
                uint256 primaryAmount = (totalPrice * config.primaryBP) / 10_000;
                uint256 secondaryAmount = (totalPrice * config.secondaryBP) / 10_000;
                totalReferralAmount = primaryAmount + secondaryAmount;
                
                if (primaryAmount > 0) {
                    (bool ok1, ) = referrer.call{value: primaryAmount}("");
                    require(ok1, "referral primary POL transfer failed");
                }
                if (secondaryAmount > 0) {
                    (bool ok2, ) = config.secondaryWallet.call{value: secondaryAmount}("");
                    require(ok2, "referral secondary POL transfer failed");
                }
                emit ReferralSplitPaid(msg.sender, referrer, config.secondaryWallet, primaryAmount, secondaryAmount, "POL", totalPrice);
            } else {
                uint256 reward = _calcReferral(totalPrice, referrer);
                if (reward > 0) {
                    (bool rOk, ) = referrer.call{value: reward}("");
                    require(rOk, "referral POL transfer failed");
                    totalReferralAmount = reward;
                    emit ReferralPaid(msg.sender, referrer, reward, "POL", "NFT", totalPrice);
                }
            }
        }

        uint256 rest = totalPrice - totalReferralAmount;
        (bool ok, ) = projectWallet.call{value: rest}("");
        require(ok, "POL transfer failed");

        nftCoreCount[msg.sender] += quantity;
        emit NFTCorePurchased(msg.sender, quantity, "POL");
        
        // ✅ [신규] NovaEvolutionNFT 민팅 호출 (POL 구매 시에도 민팅)
        for (uint256 i = 0; i < quantity; i++) {
            try INovaEvolutionNFT(novaEvolutionNFTAddress).mintFromShop(
                msg.sender,
                "POL",
                totalPrice / quantity
            ) {} catch {}
        }
        
        // ⚠️ [수정] 스테이킹 APY 갱신 제거
        // 이유: 스테이킹 컨트랙트에서 자체적으로 CoreShop 상태 변경 감지 후 자동 갱신
        // _refreshUserStakingAPY(msg.sender);
        
        // ✅ 업적 기록
        if (address(achievementSystem) != address(0)) {
            try achievementSystem.createRecord(
                msg.sender,
                6,  // NFT 코어 구매
                quantity,
                ""
            ) {} catch {}
        }
    }

    /**
     * @notice Permit 기반 NFTCore 구매 (EIP-2612)
     * @dev Boost Core와 동일한 구조 적용
     * @param quantity 구매 수량
     * @param deadline permit 유효 기간
     * @param v 서명 v
     * @param r 서명 r
     * @param s 서명 s
     * @param price 실시간 API에서 조회한 NOVA Wei 단위 가격
     */
    function buyNFTCoreNOVAPermit(
        uint256 quantity,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 price,  // ← 반드시 앱에서 API 가격 전달
        address referrer
    ) external nonReentrant {
        require(quantity > 0, "E1: quantity=0");
        require(isNovaPoolActive, "E2: NOVA pool not active");
        require(price > 0, "E3: invalid price");
        
        // ✅ 앱에서 전달받은 API 가격만 사용
        uint256 totalPrice = price * quantity;
        require(totalPrice > 0, "E4: price calc failed");

        // ✅ EIP-2612 Permit (Boost Core와 동일)
        try IPermitToken(address(novaToken)).permit(
            msg.sender,
            address(this),
            totalPrice,
            deadline,
            v,
            r,
            s
        ) {} catch {}

        uint256 totalReferralAmount = 0;
        ReferralSplitConfig memory config = referralSplits[referrer];
        
        if (referrer != address(0) && referrer != msg.sender) {
            if (config.primaryBP > 0) {
                uint256 primaryAmount = (totalPrice * config.primaryBP) / 10_000;
                uint256 secondaryAmount = (totalPrice * config.secondaryBP) / 10_000;
                totalReferralAmount = primaryAmount + secondaryAmount;
                
                if (primaryAmount > 0) {
                    bool ok1 = novaToken.transferFrom(msg.sender, referrer, primaryAmount);
                    require(ok1, "E5R1: referral primary transfer failed");
                }
                if (secondaryAmount > 0) {
                    bool ok2 = novaToken.transferFrom(msg.sender, config.secondaryWallet, secondaryAmount);
                    require(ok2, "E5R2: referral secondary transfer failed");
                }
                emit ReferralSplitPaid(msg.sender, referrer, config.secondaryWallet, primaryAmount, secondaryAmount, "NOVA", totalPrice);
            } else {
                uint256 reward = _calcReferral(totalPrice, referrer);
                if (reward > 0) {
                    bool okReward = novaToken.transferFrom(msg.sender, referrer, reward);
                    require(okReward, "E5R: referral transfer failed");
                    totalReferralAmount = reward;
                    emit ReferralPaid(msg.sender, referrer, reward, "NOVA", "NFT", totalPrice);
                }
            }
        }
        
        uint256 rest = totalPrice - totalReferralAmount;
        bool ok = novaToken.transferFrom(msg.sender, novaProjectWallet, rest);
        require(ok, "E5: NOVA transfer failed");

        nftCoreCount[msg.sender] += quantity;
        emit NFTCorePurchased(msg.sender, quantity, "NOVA");
        
        // ✅ [신규] NovaEvolutionNFT 민팅 호출 (1개씩만 민팅)
        // ⚠️ [수정] 이제 mintFromShop을 호출 (서명 중복 문제 해결)
        for (uint256 i = 0; i < quantity; i++) {
            try INovaEvolutionNFT(novaEvolutionNFTAddress).mintFromShop(
                msg.sender,
                "NOVA",
                price
            ) {} catch {}
        }
        
        // ⚠️ [수정] 스테이킹 APY 갱신 제거
        // 이유: 스테이킹 컨트랙트에서 자체적으로 CoreShop 상태 변경 감지 후 자동 갱신
        // _refreshUserStakingAPY(msg.sender);
        
        // ✅ 업적 기록 (Boost Core와 동일)
        if (address(achievementSystem) != address(0)) {
            try achievementSystem.createRecord(
                msg.sender,
                6,  // NFT 코어 구매
                quantity,
                ""
            ) {} catch {}
        }
    }

    // ============ 포인트 코어 구매 ============
    
    /**
     * @notice POL로 PointCore 구매
     * @param bundles 구매 번들 수
     * @param totalPrice 앱에서 조회한 API 가격 (Wei)
     */
    function buyPointCorePOL(uint256 bundles, uint256 totalPrice, address referrer) external payable nonReentrant {
        require(bundles > 0, "bundles=0");
        require(totalPrice > 0, "price=0");
        require(msg.value == totalPrice, "incorrect POL amount");

        uint256 totalReferralAmount = 0;
        ReferralSplitConfig memory config = referralSplits[referrer];
        
        if (referrer != address(0) && referrer != msg.sender) {
            if (config.primaryBP > 0) {
                uint256 primaryAmount = (totalPrice * config.primaryBP) / 10_000;
                uint256 secondaryAmount = (totalPrice * config.secondaryBP) / 10_000;
                totalReferralAmount = primaryAmount + secondaryAmount;
                
                if (primaryAmount > 0) {
                    (bool ok1, ) = referrer.call{value: primaryAmount}("");
                    require(ok1, "referral primary POL transfer failed");
                }
                if (secondaryAmount > 0) {
                    (bool ok2, ) = config.secondaryWallet.call{value: secondaryAmount}("");
                    require(ok2, "referral secondary POL transfer failed");
                }
                emit ReferralSplitPaid(msg.sender, referrer, config.secondaryWallet, primaryAmount, secondaryAmount, "POL", totalPrice);
            } else {
                uint256 reward = _calcReferral(totalPrice, referrer);
                if (reward > 0) {
                    (bool rOk, ) = referrer.call{value: reward}("");
                    require(rOk, "referral POL transfer failed");
                    totalReferralAmount = reward;
                    emit ReferralPaid(msg.sender, referrer, reward, "POL", "POINT", totalPrice);
                }
            }
        }

        uint256 rest = totalPrice - totalReferralAmount;
        (bool ok, ) = projectWallet.call{value: rest}("");
        require(ok, "POL transfer failed");

        uint256 totalPoints = bundles * POINTS_PER_BUNDLE;
        dailyRewards.addUserPoints(msg.sender, totalPoints);

        pointCoreBundleCount[msg.sender] += bundles;
        emit PointCorePurchased(msg.sender, bundles, "POL");
        
        // ✅ 업적 기록
        if (address(achievementSystem) != address(0)) {
            try achievementSystem.createRecord(
                msg.sender,
                7,  // 포인트 코어 구매
                bundles,
                ""
            ) {} catch {}
        }
    }

    /**
     * @notice Permit 기반 포인트 코어 구매 (EIP-2612)
     * @dev 서명으로 approve 대체 - 한 번의 트랜잭션으로 완료
     * 
     * @param bundles 구매 번들 수
     * @param deadline permit 유효 기간
     * @param v 서명 v
     * @param r 서명 r
     * @param s 서명 s
     * @param price 실시간 API에서 조회한 NOVA Wei 단위 가격
     */
    function buyPointCoreWithNOVAPermit(
        uint256 bundles,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 price,  // ← 반드시 앱에서 API 가격 전달
        address referrer
    ) external nonReentrant {
        if (bundles == 0) revert("bundles=0");
        if (!isNovaPoolActive) revert NovaPoolInactive();
        if (price == 0) revert PriceZero();
        
        // ✅ 앱에서 전달받은 API 가격만 사용
        uint256 totalPrice = price * bundles;

        // ✅ EIP-2612 Permit으로 approve 및 transferFrom을 한 번에 처리
        // 서명이 유효하면 자동으로 allowance 설정
        try IPermitToken(address(novaToken)).permit(
            msg.sender,
            address(this),
            totalPrice,
            deadline,
            v,
            r,
            s
        ) {} catch {}

        uint256 totalReferralAmount = 0;
        ReferralSplitConfig memory config = referralSplits[referrer];
        
        if (referrer != address(0) && referrer != msg.sender) {
            if (config.primaryBP > 0) {
                uint256 primaryAmount = (totalPrice * config.primaryBP) / 10_000;
                uint256 secondaryAmount = (totalPrice * config.secondaryBP) / 10_000;
                totalReferralAmount = primaryAmount + secondaryAmount;
                
                if (primaryAmount > 0) {
                    bool ok1 = novaToken.transferFrom(msg.sender, referrer, primaryAmount);
                    require(ok1, "referral primary transfer failed");
                }
                if (secondaryAmount > 0) {
                    bool ok2 = novaToken.transferFrom(msg.sender, config.secondaryWallet, secondaryAmount);
                    require(ok2, "referral secondary transfer failed");
                }
                emit ReferralSplitPaid(msg.sender, referrer, config.secondaryWallet, primaryAmount, secondaryAmount, "NOVA", totalPrice);
            } else {
                uint256 reward = _calcReferral(totalPrice, referrer);
                if (reward > 0) {
                    bool okReward = novaToken.transferFrom(msg.sender, referrer, reward);
                    require(okReward, "referral transfer failed");
                    totalReferralAmount = reward;
                    emit ReferralPaid(msg.sender, referrer, reward, "NOVA", "POINT", totalPrice);
                }
            }
        }
        
        uint256 rest = totalPrice - totalReferralAmount;
        bool ok = novaToken.transferFrom(msg.sender, novaProjectWallet, rest);
        require(ok, "NOVA transfer failed");

        uint256 totalPoints = bundles * POINTS_PER_BUNDLE;

        // ✅ Proxy-safe external call
        (bool success, ) = address(dailyRewards).call(
            abi.encodeWithSignature("addUserPoints(address,uint256)", msg.sender, totalPoints)
        );
        require(success, "addUserPoints failed");

        pointCoreBundleCount[msg.sender] += bundles;
        emit PointCorePurchased(msg.sender, bundles, "NOVA");
    }

    // ============ 커스텀 에러 (현장 진단용) ============
    error NovaPoolInactive();
    error PriceZero();

    // ============ 헬퍼 함수 ============
    
    function _getReferralBP(address referrer) internal view returns (uint16) {
        if (referrer == address(0)) return 0;
        uint16 customBP = referrerCustomBP[referrer];
        return customBP > 0 ? customBP : referralBP;
    }

    function _calcReferral(uint256 amount, address referrer) internal view returns (uint256) {
        uint16 bp = _getReferralBP(referrer);
        if (bp == 0) return 0;
        return (amount * bp) / 10_000;
    }

    function _processReferralPayment(
        uint256 amount,
        address referrer,
        string memory currency,
        bool isPOL
    ) internal {
        if (referrer == address(0) || amount == 0) return;

        ReferralSplitConfig memory config = referralSplits[referrer];
        
        if (config.primaryBP > 0) {
            uint256 primaryAmount = (amount * config.primaryBP) / 10_000;
            uint256 secondaryAmount = (amount * config.secondaryBP) / 10_000;
            
            if (isPOL) {
                if (primaryAmount > 0) {
                    (bool ok1, ) = referrer.call{value: primaryAmount}("");
                    require(ok1, "referral primary POL transfer failed");
                }
                if (secondaryAmount > 0) {
                    (bool ok2, ) = config.secondaryWallet.call{value: secondaryAmount}("");
                    require(ok2, "referral secondary POL transfer failed");
                }
            } else {
                if (primaryAmount > 0) {
                    bool ok1 = novaToken.transferFrom(msg.sender, referrer, primaryAmount);
                    require(ok1, "referral primary NOVA transfer failed");
                }
                if (secondaryAmount > 0) {
                    bool ok2 = novaToken.transferFrom(msg.sender, config.secondaryWallet, secondaryAmount);
                    require(ok2, "referral secondary NOVA transfer failed");
                }
            }
            
            emit ReferralPaid(msg.sender, referrer, primaryAmount, currency, "SPLIT", amount);
        } else {
            uint256 reward = _calcReferral(amount, referrer);
            if (reward > 0) {
                if (isPOL) {
                    (bool ok, ) = referrer.call{value: reward}("");
                    require(ok, "referral POL transfer failed");
                } else {
                    bool ok = novaToken.transferFrom(msg.sender, referrer, reward);
                    require(ok, "referral NOVA transfer failed");
                }
                
                emit ReferralPaid(msg.sender, referrer, reward, currency, "SINGLE", amount);
            }
        }
    }
    
    /**
     * @notice [제거됨] 사용자의 모든 풀에서 APY 갱신
     * @dev 스테이킹 컨트랙트에서 자체적으로 CoreShop 이벤트 감지 후 APY 자동 갱신
     * @dev 더 이상 직접 호출하지 않음 (ReentrancyGuard 이슈, 불필요한 가스 소모)
     */
    // [제거됨] function _refreshUserStakingAPY(address user) internal 
    /*
    function _refreshUserStakingAPY(address user) internal {
        if (address(stakingContract) == address(0)) {
            return;
        }
        
        // ✅ 모든 풀(0~7)에서 사용자의 APY 갱신
        for (uint256 poolId = 0; poolId < 8; poolId++) {
            try stakingContract.refreshMyAPY(poolId) {
                // 성공
            } catch {
                // 실패해도 계속 진행 (스테이킹이 없을 수 있음)
            }
        }
    }
    */

    /**
     * @notice 스테이킹 컨트랙트 주소 설정/변경 (관리자)
     */
    function setStakingContract(address _stakingContract) external onlyOwner {
        require(_stakingContract != address(0), "invalid address");
        stakingContract = IStakingV2(_stakingContract);
    }
    
    /**
     * @notice 관리자가 사용자에게 부스트 코어 지급 (자동 APY 갱신 포함)
     * @dev 지급 후 자동으로 스테이킹 APY가 업데이트됨
     */
    function grantBoostCores(address user, uint256 amount) external onlyOwner {
        require(user != address(0), "invalid user");
        require(amount > 0, "amount must be > 0");
        require(boostCoreCount[user] + amount <= MAX_BOOST_CORES, "exceed max boost cores");
        
        boostCoreCount[user] += amount;
        
        // ⚠️ [수정] 스테이킹 APY 갱신 제거
        // 이유: 스테이킹 컨트랙트에서 자체적으로 CoreShop 상태 변경 감지 후 자동 갱신
        // _refreshUserStakingAPY(user);
        
        emit BoostCorePurchased(user, amount, "ADMIN_GRANT");
    }
    
    /**
     * @notice 관리자가 사용자의 부스트 코어 수량을 특정 값으로 설정 (감소)
     * @dev 예: 10개 보유 중 사용자가 5개 보유로 변경 가능
     * @param user 대상 사용자 주소
     * @param newAmount 변경할 새로운 부스트 코어 수량
     */
    function setBoostCoreCount(address user, uint256 newAmount) external onlyOwner {
        require(user != address(0), "invalid user");
        require(newAmount <= MAX_BOOST_CORES, "exceed max boost cores");
        
        uint256 previousAmount = boostCoreCount[user];
        boostCoreCount[user] = newAmount;
        
        // ⚠️ [수정] 스테이킹 APY 갱신 제거
        // 이유: 스테이킹 컨트랙트에서 자체적으로 CoreShop 상태 변경 감지 후 자동 갱신
        // _refreshUserStakingAPY(user);
        
        // ✅ 이벤트 발행 (감소 또는 증가 상황 기록)
        if (newAmount > previousAmount) {
            emit BoostCorePurchased(user, newAmount - previousAmount, "ADMIN_SET_INCREASE");
        } else if (newAmount < previousAmount) {
            emit BoostCorePurchased(user, previousAmount - newAmount, "ADMIN_SET_DECREASE");
        }
    }
    
    /**
     * @notice 관리자가 사용자에게 NFT 코어 지급 (자동 APY 갱신 포함)
     */
    function grantNFTCores(address user, uint256 amount) external onlyOwner {
        require(user != address(0), "invalid user");
        require(amount > 0, "amount must be > 0");
        
        nftCoreCount[user] += amount;
        
        // ⚠️ [수정] 스테이킹 APY 갱신 제거
        // 이유: 스테이킹 컨트랙트에서 자체적으로 CoreShop 상태 변경 감지 후 자동 갱신
        // _refreshUserStakingAPY(user);
        
        emit NFTCorePurchased(user, amount, "ADMIN_GRANT");
    }
    
    /**
     * @notice 관리자가 사용자에게 포인트 번들 지급
     */
    function grantPointBundles(address user, uint256 amount) external onlyOwner {
        require(user != address(0), "invalid user");
        require(amount > 0, "amount must be > 0");
        
        uint256 totalPoints = amount * POINTS_PER_BUNDLE;
        pointCoreBundleCount[user] += amount;
        
        // 포인트 지급
        (bool success, ) = address(dailyRewards).call(
            abi.encodeWithSignature("addUserPoints(address,uint256)", user, totalPoints)
        );
        require(success, "addUserPoints failed");
        
        emit PointCorePurchased(user, amount, "ADMIN_GRANT");
    }

    // ============ 조회 함수 ============
    
    function getUserCoreStatus(address user) external view returns (
        uint256 boostCores,
        uint256 nftCores,
        uint256 pointBundles,
        uint256 effectiveAPYIncrease
    ) {
        boostCores = boostCoreCount[user];
        nftCores = nftCoreCount[user];
        pointBundles = pointCoreBundleCount[user];
        effectiveAPYIncrease = boostCores * BOOST_APY_INCREASE;
    }
    
    // ✅ StakingV2와의 호환성을 위한 함수
    // StakingV2의 ICoreShop 인터페이스에서 호출
    function boostOwnedCount(address user) external view returns (uint256) {
        return boostCoreCount[user];
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    // ✅ [새로운 추천인 비율 분할 시스템] - Proxy 호환성을 위해 파일 맨 끝에 추가
    mapping(address => uint16) public referrerCustomBP;
    struct ReferralSplitConfig {
        uint16 primaryBP;
        uint16 secondaryBP;
        address secondaryWallet;
    }
    mapping(address => ReferralSplitConfig) public referralSplits;

    // ============================================
    // 🎁 프리세일 프로모션 번들 (부스트 코어 1개 + 200 N-Points)
    // ============================================
    
    // 프리세일 구매 여부 추적
    mapping(address => bool) public presalePurchased;
    
    // 프리세일 상수
    uint256 public constant PRESALE_BOOST_CORES = 1;
    uint256 public constant PRESALE_POINT_BUNDLES = 2;  // 200 포인트 (100 * 2)
    
    // 프리세일 이벤트
    event PresaleBundlePurchased(address indexed user, string currency, uint256 totalPrice);
    
    /**
     * @notice 프리세일 구매 여부 확인
     * @param user 확인할 사용자 주소
     * @return 구매 여부 (true = 이미 구매함)
     */
    function hasPresalePurchased(address user) external view returns (bool) {
        return presalePurchased[user];
    }
    
    /**
     * @notice POL로 프리세일 번들 구매 (부스트 코어 1개 + 200 N-Points)
     * @dev 1회 한정 구매 - 이미 구매한 사용자는 재구매 불가
     * @param totalPrice 앱에서 조회한 API 가격 (Wei) - 5달러 상당
     */
    function buyPresaleBundlePOL(uint256 totalPrice, address referrer) external payable nonReentrant {
        require(!presalePurchased[msg.sender], "already purchased presale");
        require(totalPrice > 0, "price=0");
        require(msg.value == totalPrice, "incorrect POL amount");
        require(boostCoreCount[msg.sender] + PRESALE_BOOST_CORES <= MAX_BOOST_CORES, "exceed max boost cores");
        
        // ✅ 추천인 수수료 처리 (buyBoostCorePOL과 동일)
        uint256 totalReferralAmount = 0;
        ReferralSplitConfig memory config = referralSplits[referrer];
        
        if (referrer != address(0) && referrer != msg.sender) {
            if (config.primaryBP > 0) {
                uint256 primaryAmount = (totalPrice * config.primaryBP) / 10_000;
                uint256 secondaryAmount = (totalPrice * config.secondaryBP) / 10_000;
                totalReferralAmount = primaryAmount + secondaryAmount;
                
                if (primaryAmount > 0) {
                    (bool ok1, ) = referrer.call{value: primaryAmount}("");
                    require(ok1, "referral primary POL transfer failed");
                }
                if (secondaryAmount > 0) {
                    (bool ok2, ) = config.secondaryWallet.call{value: secondaryAmount}("");
                    require(ok2, "referral secondary POL transfer failed");
                }
                emit ReferralSplitPaid(msg.sender, referrer, config.secondaryWallet, primaryAmount, secondaryAmount, "POL", totalPrice);
            } else {
                uint256 reward = _calcReferral(totalPrice, referrer);
                if (reward > 0) {
                    (bool rOk, ) = referrer.call{value: reward}("");
                    require(rOk, "referral POL transfer failed");
                    totalReferralAmount = reward;
                    emit ReferralPaid(msg.sender, referrer, reward, "POL", "PRESALE", totalPrice);
                }
            }
        }
        
        // ✅ 프로젝트 지갑으로 전송
        uint256 rest = totalPrice - totalReferralAmount;
        (bool ok, ) = projectWallet.call{value: rest}("");
        require(ok, "POL transfer failed");
        
        // ✅ 부스트 코어 1개 지급
        boostCoreCount[msg.sender] += PRESALE_BOOST_CORES;
        emit BoostCorePurchased(msg.sender, PRESALE_BOOST_CORES, "PRESALE_POL");
        
        // ✅ 200 N-Points 지급 (포인트 번들 2개)
        uint256 totalPoints = PRESALE_POINT_BUNDLES * POINTS_PER_BUNDLE;
        dailyRewards.addUserPoints(msg.sender, totalPoints);
        pointCoreBundleCount[msg.sender] += PRESALE_POINT_BUNDLES;
        emit PointCorePurchased(msg.sender, PRESALE_POINT_BUNDLES, "PRESALE_POL");
        
        // ✅ 프리세일 구매 완료 표시
        presalePurchased[msg.sender] = true;
        emit PresaleBundlePurchased(msg.sender, "POL", totalPrice);
        
        // ✅ 업적 기록
        if (address(achievementSystem) != address(0)) {
            try achievementSystem.createRecord(
                msg.sender,
                8,  // 프리세일 번들 구매
                1,
                "presale_bundle"
            ) {} catch {}
        }
    }
    
    /**
     * @notice Permit 기반 프리세일 번들 구매 (부스트 코어 1개 + 200 N-Points)
     * @dev 1회 한정 구매 - 이미 구매한 사용자는 재구매 불가
     * @param deadline permit 유효 기간
     * @param v 서명 v
     * @param r 서명 r
     * @param s 서명 s
     * @param price 실시간 API에서 조회한 NOVA Wei 단위 가격 - 5달러 상당
     */
    function buyPresaleBundleNOVAPermit(
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 price,
        address referrer
    ) external nonReentrant {
        require(!presalePurchased[msg.sender], "already purchased presale");
        require(isNovaPoolActive, "NOVA pool not active");
        require(price > 0, "price=0");
        require(boostCoreCount[msg.sender] + PRESALE_BOOST_CORES <= MAX_BOOST_CORES, "exceed max boost cores");
        
        uint256 totalPrice = price;  // 프리세일은 수량 1개 고정
        
        // ✅ EIP-2612 Permit (buyBoostCoreNOVAPermit과 동일)
        try IPermitToken(address(novaToken)).permit(
            msg.sender,
            address(this),
            totalPrice,
            deadline,
            v,
            r,
            s
        ) {} catch {}
        
        // ✅ 추천인 수수료 처리
        uint256 totalReferralAmount = 0;
        ReferralSplitConfig memory config = referralSplits[referrer];
        
        if (referrer != address(0) && referrer != msg.sender) {
            if (config.primaryBP > 0) {
                uint256 primaryAmount = (totalPrice * config.primaryBP) / 10_000;
                uint256 secondaryAmount = (totalPrice * config.secondaryBP) / 10_000;
                totalReferralAmount = primaryAmount + secondaryAmount;
                
                if (primaryAmount > 0) {
                    bool ok1 = novaToken.transferFrom(msg.sender, referrer, primaryAmount);
                    require(ok1, "referral primary transfer failed");
                }
                if (secondaryAmount > 0) {
                    bool ok2 = novaToken.transferFrom(msg.sender, config.secondaryWallet, secondaryAmount);
                    require(ok2, "referral secondary transfer failed");
                }
                emit ReferralSplitPaid(msg.sender, referrer, config.secondaryWallet, primaryAmount, secondaryAmount, "NOVA", totalPrice);
            } else {
                uint256 reward = _calcReferral(totalPrice, referrer);
                if (reward > 0) {
                    bool okReward = novaToken.transferFrom(msg.sender, referrer, reward);
                    require(okReward, "referral transfer failed");
                    totalReferralAmount = reward;
                    emit ReferralPaid(msg.sender, referrer, reward, "NOVA", "PRESALE", totalPrice);
                }
            }
        }
        
        // ✅ 프로젝트 지갑으로 전송
        uint256 rest = totalPrice - totalReferralAmount;
        bool ok = novaToken.transferFrom(msg.sender, novaProjectWallet, rest);
        require(ok, "NOVA transfer failed");
        
        // ✅ 부스트 코어 1개 지급
        boostCoreCount[msg.sender] += PRESALE_BOOST_CORES;
        emit BoostCorePurchased(msg.sender, PRESALE_BOOST_CORES, "PRESALE_NOVA");
        
        // ✅ 200 N-Points 지급 (포인트 번들 2개)
        uint256 totalPoints = PRESALE_POINT_BUNDLES * POINTS_PER_BUNDLE;
        (bool success, ) = address(dailyRewards).call(
            abi.encodeWithSignature("addUserPoints(address,uint256)", msg.sender, totalPoints)
        );
        require(success, "addUserPoints failed");
        pointCoreBundleCount[msg.sender] += PRESALE_POINT_BUNDLES;
        emit PointCorePurchased(msg.sender, PRESALE_POINT_BUNDLES, "PRESALE_NOVA");
        
        // ✅ 프리세일 구매 완료 표시
        presalePurchased[msg.sender] = true;
        emit PresaleBundlePurchased(msg.sender, "NOVA", totalPrice);
        
        // ✅ 업적 기록
        if (address(achievementSystem) != address(0)) {
            try achievementSystem.createRecord(
                msg.sender,
                8,  // 프리세일 번들 구매
                1,
                "presale_bundle"
            ) {} catch {}
        }
    }
    
    /**
     * @notice 관리자가 사용자의 프리세일 구매 상태를 리셋
     * @dev 테스트용 또는 특수 상황 대응용
     */
    function resetPresaleStatus(address user) external onlyOwner {
        require(user != address(0), "invalid user");
        presalePurchased[user] = false;
    }

    /**
     * @notice 관리자가 사용자에게 프리세일 번들을 직접 지급 (무료)
     * @dev 지급 시 구매한 것으로 처리되어(presalePurchased = true), 유저는 중복 구매 불가
     * @param user 지급 받을 사용자 주소
     */
    function grantPresaleBundle(address user) external onlyOwner {
        require(user != address(0), "invalid user");
        require(!presalePurchased[user], "already purchased/granted");

        // 최대 부스트 코어 개수 확인
        require(boostCoreCount[user] + PRESALE_BOOST_CORES <= MAX_BOOST_CORES, "exceed max boost cores");

        // 1. 부스트 코어 1개 지급
        boostCoreCount[user] += PRESALE_BOOST_CORES;
        emit BoostCorePurchased(user, PRESALE_BOOST_CORES, "ADMIN_GRANT_PRESALE");

        // 2. 200 N-Points 지급 (포인트 번들 2개)
        uint256 totalPoints = PRESALE_POINT_BUNDLES * POINTS_PER_BUNDLE;

        // DailyRewards 컨트랙트 호출
        dailyRewards.addUserPoints(user, totalPoints);

        pointCoreBundleCount[user] += PRESALE_POINT_BUNDLES;
        emit PointCorePurchased(user, PRESALE_POINT_BUNDLES, "ADMIN_GRANT_PRESALE");

        // 3. 프리세일 구매 완료 처리 (중복 구매/지급 방지)
        presalePurchased[user] = true;
        emit PresaleBundlePurchased(user, "ADMIN_GRANT", 0);

        // 4. 업적 기록 (구매와 동일한 타입 8번 사용)
        if (address(achievementSystem) != address(0)) {
            try achievementSystem.createRecord(
                user,
                8,  // 프리세일 번들 구매/획득
                1,
                "presale_grant"
            ) {} catch {}
        }
    }
}



// ============================================================
// FILE: @openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;
import {Initializable} from "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}



// ============================================================
// FILE: @openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;

import {ContextUpgradeable} from "../utils/ContextUpgradeable.sol";
import {Initializable} from "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Ownable
    struct OwnableStorage {
        address _owner;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OwnableStorageLocation = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OwnableStorageLocation
        }
    }

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
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
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
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
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner;
        $._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}



// ============================================================
// FILE: @openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (proxy/utils/UUPSUpgradeable.sol)

pragma solidity ^0.8.22;

import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "./Initializable.sol";

/**
 * @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
 * {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
 *
 * A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
 * reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
 * `UUPSUpgradeable` with a custom implementation of upgrades.
 *
 * The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
 */
abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable __self = address(this);

    /**
     * @dev The version of the upgrade interface of the contract. If this getter is missing, both `upgradeTo(address)`
     * and `upgradeToAndCall(address,bytes)` are present, and `upgradeTo` must be used if no function should be called,
     * while `upgradeToAndCall` will invoke the `receive` function if the second argument is the empty byte string.
     * If the getter returns `"5.0.0"`, only `upgradeToAndCall(address,bytes)` is present, and the second argument must
     * be the empty byte string if no function should be called, making it impossible to invoke the `receive` function
     * during an upgrade.
     */
    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    /**
     * @dev The call is from an unauthorized context.
     */
    error UUPSUnauthorizedCallContext();

    /**
     * @dev The storage `slot` is unsupported as a UUID.
     */
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

    /**
     * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
     * a proxy contract with an implementation (as defined in ERC-1967) pointing to self. This should only be the case
     * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
     * function through ERC-1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
     * fail.
     */
    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    /**
     * @dev Check that the execution is not being performed through a delegate call. This allows a function to be
     * callable on the implementing contract but not through proxies.
     */
    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Implementation of the ERC-1822 {proxiableUUID} function. This returns the storage slot used by the
     * implementation. It is used to validate the implementation's compatibility when performing an upgrade.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier.
     */
    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call
     * encoded in `data`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     *
     * @custom:oz-upgrades-unsafe-allow-reachable delegatecall
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    /**
     * @dev Reverts if the execution is not performed via delegatecall or the execution
     * context is not of a proxy with an ERC-1967 compliant implementation pointing to self.
     */
    function _checkProxy() internal view virtual {
        if (
            address(this) == __self || // Must be called through delegatecall
            ERC1967Utils.getImplementation() != __self // Must be called through an active proxy
        ) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Reverts if the execution is performed via delegatecall.
     * See {notDelegated}.
     */
    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            // Must not be called through delegatecall
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeToAndCall}.
     *
     * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
     *
     * ```solidity
     * function _authorizeUpgrade(address) internal onlyOwner {}
     * ```
     */
    function _authorizeUpgrade(address newImplementation) internal virtual;

    /**
     * @dev Performs an implementation upgrade with a security check for UUPS proxies, and additional setup call.
     *
     * As a security check, {proxiableUUID} is invoked in the new implementation, and the return value
     * is expected to be the implementation slot in ERC-1967.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
                revert UUPSUnsupportedProxiableUUID(slot);
            }
            ERC1967Utils.upgradeToAndCall(newImplementation, data);
        } catch {
            // The implementation is not UUPS
            revert ERC1967Utils.ERC1967InvalidImplementation(newImplementation);
        }
    }
}



// ============================================================
// FILE: @openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.20;

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
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reinitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
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
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
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
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Pointer to storage slot. Allows integrators to override it with a custom storage location.
     *
     * NOTE: Consider following the ERC-7201 formula to derive storage locations.
     */
    function _initializableStorageSlot() internal pure virtual returns (bytes32) {
        return INITIALIZABLE_STORAGE;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        bytes32 slot = _initializableStorageSlot();
        assembly {
            $.slot := slot
        }
    }
}



// ============================================================
// FILE: @openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
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
// FILE: @openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (proxy/ERC1967/ERC1967Utils.sol)

pragma solidity ^0.8.21;

import {IBeacon} from "../beacon/IBeacon.sol";
import {IERC1967} from "../../interfaces/IERC1967.sol";
import {Address} from "../../utils/Address.sol";
import {StorageSlot} from "../../utils/StorageSlot.sol";

/**
 * @dev This library provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[ERC-1967] slots.
 */
library ERC1967Utils {
    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev The `implementation` of the proxy is invalid.
     */
    error ERC1967InvalidImplementation(address implementation);

    /**
     * @dev The `admin` of the proxy is invalid.
     */
    error ERC1967InvalidAdmin(address admin);

    /**
     * @dev The `beacon` of the proxy is invalid.
     */
    error ERC1967InvalidBeacon(address beacon);

    /**
     * @dev An upgrade function sees `msg.value > 0` that may be lost.
     */
    error ERC1967NonPayable();

    /**
     * @dev Returns the current implementation address.
     */
    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the ERC-1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Performs implementation upgrade with additional setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit IERC1967.Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by ERC-1967) using
     * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the ERC-1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {IERC1967-AdminChanged} event.
     */
    function changeAdmin(address newAdmin) internal {
        emit IERC1967.AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the ERC-1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        if (newBeacon.code.length == 0) {
            revert ERC1967InvalidBeacon(newBeacon);
        }

        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
        if (beaconImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(beaconImplementation);
        }
    }

    /**
     * @dev Change the beacon and trigger a setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-BeaconUpgraded} event.
     *
     * CAUTION: Invoking this function has no effect on an instance of {BeaconProxy} since v5, since
     * it uses an immutable beacon without looking at the value of the ERC-1967 beacon slot for
     * efficiency.
     */
    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit IERC1967.BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Reverts if `msg.value` is not zero. It can be used to avoid `msg.value` stuck in the contract
     * if an upgrade doesn't perform an initialization call.
     */
    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert ERC1967NonPayable();
        }
    }
}



// ============================================================
// FILE: @openzeppelin/contracts/interfaces/draft-IERC1822.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/draft-IERC1822.sol)

pragma solidity >=0.4.16;

/**
 * @dev ERC-1822: Universal Upgradeable Proxy Standard (UUPS) documents a method for upgradeability through a simplified
 * proxy whose upgrades are fully controlled by the current implementation.
 */
interface IERC1822Proxiable {
    /**
     * @dev Returns the storage slot that the proxiable contract assumes is being used to store the implementation
     * address.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy.
     */
    function proxiableUUID() external view returns (bytes32);
}



// ============================================================
// FILE: @openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;
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
}



// ============================================================
// FILE: @openzeppelin/contracts/utils/StorageSlot.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

pragma solidity ^0.8.20;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC-1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Int256Slot` with member `value` located at `slot`.
     */
    function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns a `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }
}



// ============================================================
// FILE: @openzeppelin/contracts/utils/Address.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (utils/Address.sol)

pragma solidity ^0.8.20;

import {Errors} from "./Errors.sol";

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

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
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }

        (bool success, bytes memory returndata) = recipient.call{value: amount}("");
        if (!success) {
            _revert(returndata);
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {Errors.FailedCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {Errors.FailedCall}) in case
     * of an unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {Errors.FailedCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {Errors.FailedCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        } else {
            revert Errors.FailedCall();
        }
    }
}



// ============================================================
// FILE: @openzeppelin/contracts/interfaces/IERC1967.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1967.sol)

pragma solidity >=0.4.11;

/**
 * @dev ERC-1967: Proxy Storage Slots. This interface contains the events defined in the ERC.
 */
interface IERC1967 {
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);
}



// ============================================================
// FILE: @openzeppelin/contracts/proxy/beacon/IBeacon.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (proxy/beacon/IBeacon.sol)

pragma solidity >=0.4.16;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {UpgradeableBeacon} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}



// ============================================================
// FILE: @openzeppelin/contracts/utils/Errors.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

pragma solidity ^0.8.20;

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error InsufficientBalance(uint256 balance, uint256 needed);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedCall();

    /**
     * @dev The deployment failed.
     */
    error FailedDeployment();

    /**
     * @dev A necessary precompile is missing.
     */
    error MissingPrecompile(address);
}
