// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x5026d8b7d0d39221965473857d69b190bc3a3703
// Contract Name: WalletContract



// ============================================================
// FILE: contracts/WalletContract.sol
// ============================================================
// SPDX-License-Identifier: UNLICENSED

/*
Copyright © 2025 PickYesNo.com. All Rights Reserved.
This source code is provided for viewing purposes only. No copying, distribution, modification, or commercial use is permitted without explicit written permission from the copyright holder.
Contact PickYesNo.com for licensing inquiries.
*/

pragma solidity 0.8.28;

import "./BaseUsdcContract.sol";

// Wallet Contract
contract WalletContract is BaseUsdcContract, IWallet {
    uint256 public nonce;                    // Signature nonce for replay protection
    address public boundWallet;              // Bound wallet, default 0 indicates not bound
    uint64 public preSignAmount;             // Pre-signed amount
    uint64 public bonus;                     // Bonus given by platform marketing, etc., can be used for trading, but direct redemption is restricted by marketing rules
    uint64 public lastTime;                  // Last transaction time
    address[] public predictionFactories;    // Built-in prediction factory contracts
    mapping(address => bool) public oracles; // Built-in oracle contracts

    bytes32 private immutable DOMAIN_SEPARATOR;
    bytes32 private constant TYPEHASH_BIND_WALLET = keccak256("BindWallet(address wallet,uint256 nonce,uint256 chainId,address walletContract)");
    bytes32 private constant TYPEHASH_REDEEM = keccak256("Redeem(address wallet,uint256 amount,uint256 nonce,uint256 chainId,address walletContract)");
    bytes32 private constant TYPEHASH_PRESIGN = keccak256("PreSign(uint64 amount,uint256 nonce,uint256 chainId,address walletContract)");
    bytes32 private constant TYPEHASH_UPGRADE_WALLET = keccak256("UpgradeWallet(address implementation,address predictionFactory,address oracle,uint256 nonce,uint256 chainId,address walletContract)");

    // Uses ERC-1967 storage slot address, based on a "hybrid mode" upgrade approach. Important points:
    // 1. The new logic must inherit BaseUsdcContract, which inherits from BaseContract. This means variables in all base classes within the inheritance chain cannot be added, removed, or changed in order.
    // 2. The new logic must copy all variables from the old logic and cannot change the order of any old logic variables.
    // 3. The new logic must not modify the values of any old logic variables but can read them.
    // 4. New logic variables must be appended at the end.
    // 5. Retrieval logic: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event WalletBound(uint256 requestId, address wallet, bool byUser);                // Wallet bound event
    event Entrusted(uint256 requestId, address wallet, uint256 amount, bool byUser);  // Entrust event
    event Redeemed(uint256 requestId, address wallet, uint256 amount, bool byUser);   // Reddeem event
    event PreSigned(uint256 requestId, uint64 amount, bool byUser);                   // Pre-sign event
    event Presented(uint256 requestId);                                               // Bonus presentation event
    event TokenRescued(uint256 requestId, address from, address to, uint256 balance); // Token rescue event
    event WalletRecycled(uint256 requestId, uint256 balance, bool success);           // Wallet recycled event
    event Upgraded(address indexed implementation);                                   // Contract upgraded event
    event WalletUpgraded(uint256 requestId);                                          // Wallet contract upgraded event

    // Only the bound wallet or an executor EOA can call
    modifier onlyBoundWalletOrExecutorEOA() {
        require(msg.sender == boundWallet || IPERMISSION.checkAddress(msg.sender, AddressTypeLib.EXECUTOR_EOA), "unauthorized");
        _;
    }

    // Only prediction contracts can call
    modifier onlyPrediction() {
        require(_checkPrediction(msg.sender), "unauthorized");
        _;
    }

    // Only oracle contracts can call
    modifier onlyOracle() {
        require(oracles[msg.sender], "unauthorized");
        _;
    }

    // Initialization
    constructor() {
        predictionFactories.push(0x1CB187729ea2395f6a7e717D2c7026C9B9345950); // Built-in prediction factory contract
        oracles[0xF8a69A4478e870f0fB6b34482E0Dc96AEa43F676] = true;           // Built-in oracle contract
        oracles[0xfeE6959a685749E55c75650D10edaF7E336672Ef] = true;           // Built-in chainlink oracle contract

        // EIP712 Domain Separator
        DOMAIN_SEPARATOR = keccak256(abi.encode(EIP712Lib.EIP712_DOMAIN, keccak256(bytes("Wallet Contract")), keccak256(bytes("1")), block.chainid, address(this)));
    }

    // Non-payable fallback function, key protection
    fallback() external payable {
        require(msg.value == 0, "fallback err");
        assembly {
            let impl := sload(IMPLEMENTATION_SLOT)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    // Non-payable receive function, another layer of protection
    receive() external payable {
        revert("receive err");
    }

    // Bind a wallet, used for withdrawals and signing
    function bindWallet(uint256 requestId, address wallet, bytes calldata signature) external onlyBoundWalletOrExecutorEOA {
        // Whether called by the user
        bool byUser = msg.sender == boundWallet;

        // If wallet is bound, and the caller is not the bound wallet, signature is required
        if (boundWallet != address(0) && !byUser) {
            require(boundWallet == EIP712Lib.recoverEIP712(DOMAIN_SEPARATOR, abi.encode(TYPEHASH_BIND_WALLET, wallet, nonce++, block.chainid, address(this)), signature), "signature err");
        }

        // Bind the wallet
        boundWallet = wallet;

        // Log success event
        emit WalletBound(requestId, wallet, byUser);
    }

    // Entrust USDC to contract. Besides platform calls, the bound wallet can also call to redeem by itself.
    function entrust(uint256 requestId, address from, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyBoundWalletOrExecutorEOA {
        // Permit
        try IUSDC.permit(from, address(this), amount, deadline, v, r, s) {
            // permit succeeded
        } catch {
            // ignore and continue
        }

        // Transfer to Wallet Contract
        require(IUSDC.transferFrom(from, address(this), amount), "entrust failed"); 

        // Whether called by the user
        bool byUser = msg.sender == boundWallet;

        // Log success event
        emit Entrusted(requestId, from, amount, byUser);
    }

    // Redeem USDC to a specified address. Besides platform calls, the bound wallet can also call to redeem by itself.
    function redeem(uint256 requestId, address wallet, uint256 amount, bytes calldata signature) external onlyBoundWalletOrExecutorEOA {
        // Redemption amount does not include the bonus
        require(wallet != address(0) && IUSDC.balanceOf(address(this)) >= (amount + bonus), "param err");

        // Whether called by the user
        bool byUser = msg.sender == boundWallet;

        // If wallet is bound, and the caller is not the bound wallet, and the redemption address is not the bound wallet, signature is required
        if (boundWallet != address(0) && boundWallet != wallet && !byUser) {
            require(boundWallet == EIP712Lib.recoverEIP712(DOMAIN_SEPARATOR, abi.encode(TYPEHASH_REDEEM, wallet, amount, nonce++, block.chainid, address(this)), signature), "signature err");
        }

        // Redeem to the user-specified wallet
        transferUsdc(wallet, amount);

        // Log success event
        emit Redeemed(requestId, wallet, amount, byUser);
    }

    // Pre-sign
    function preSign(uint256 requestId, uint64 amount, bytes calldata signature) external onlyBoundWalletOrExecutorEOA {
        // Only bound wallets need pre-signing
        require(boundWallet != address(0), "unbound wallet");

        // Whether called by the user
        bool byUser = msg.sender == boundWallet;

        // If wallet is bound, and the caller is not the bound wallet, signature is required
        if (!byUser) {
            require(boundWallet == EIP712Lib.recoverEIP712(DOMAIN_SEPARATOR, abi.encode(TYPEHASH_PRESIGN, amount, nonce++, block.chainid, address(this)), signature), "signature err");
        }

        // Set the pre-signed amount
        preSignAmount = amount;

        // Log success event
        emit PreSigned(requestId, amount, byUser);
    }

    // Award bonus / Unlock bonus / Reclaim bonus
    function present(uint256 requestId, uint64 amount, address from, bytes32 code, bytes calldata signature, uint64 unlocked, uint64 reclaimed) external onlyExecutorEOA {
        // Award bonus
        if (amount != 0) {
            uint256 balanceBefore = IUSDC.balanceOf(address(this));
            IMarketing(from).transferFrom(amount, address(this), code, signature);
            uint256 balanceAfter = IUSDC.balanceOf(address(this));
            require((balanceAfter - balanceBefore) == amount, "from err");
            bonus += amount;
        }

        // Unlock bonus
        if (unlocked != 0) {
            require(bonus >= unlocked, "unlocked err");
            bonus -= unlocked;
        }

        // Reclaim bonus
        if (reclaimed != 0) {
            require(bonus >= reclaimed, "reclaimed err");
            bonus -= reclaimed;
            transferUsdc(IPERMISSION.feeEOA(), reclaimed);
        }

        // Log success event
        emit Presented(requestId);
    }

    // Rescue ERC-20 tokens
    function rescueToken(uint256 requestId, address from, address to) external onlyExecutorEOA {
        // Ensure safety via whitelist, and USDC is not supported for rescue because USDC must be redeemed via redeem
        require(from != USDC && to != address(0) && IPERMISSION.checkAddress(from, AddressTypeLib.ERC20), "param err");

        // Rescue transfer
        IERC20 token = IERC20(from);
        uint256 balance = token.balanceOf(address(this));
        token.transfer(to, balance); // No need to worry about whether the transfer was successful

        // Log success event
        emit TokenRescued(requestId, from, to, balance);
    }

    // Recycle wallet
    function recycleWallet(uint256 requestId) external onlyExecutorEOA {
        // Balance
        uint256 balance = IUSDC.balanceOf(address(this));

        // Record whether recycling was successful, for off-chain judgment
        bool success;

        if (balance != 0) {
            // Wallet balance greater than 0, but must have no transaction record for at least 1 year to be recycled, and balance transferred to: fee EOA
            if (lastTime != 0) {
                if (block.timestamp > (lastTime + 365 days)) {
                    transferUsdc(IPERMISSION.feeEOA(), balance);
                    success = true;
                }
            } else {
                lastTime = uint64(block.timestamp);
            }
        } else {
            // Wallet balance equals 0, but no transaction record for over half a year, can be recycled. Otherwise, recycling will be permitted after 3 days
            if (lastTime != 0) {
                if (block.timestamp > (lastTime + 180 days)) {
                    success = true;
                }
            } else {
                lastTime = uint64(block.timestamp - 177 days);
            }
        }

        // Successfully recycled, remove binding
        if (success) {
            boundWallet = address(0);
            preSignAmount = 0;
            bonus = 0;
            lastTime = 0;
        }

        // Log success event
        emit WalletRecycled(requestId, balance, success);
    }

    // Upgrade contract
    function upgradeWallet(uint256 requestId, address newImplementation, address newPredictionFactory, address newOracle, bytes calldata signature) external onlyExecutorEOA {
        // Only bound wallets need signature verification
        if (boundWallet != address(0)) {
            require(boundWallet == EIP712Lib.recoverEIP712(DOMAIN_SEPARATOR, abi.encode(TYPEHASH_UPGRADE_WALLET, newImplementation, newPredictionFactory, newOracle, nonce++, block.chainid, address(this)), signature), "signature err");
        }

        // Update implementation address
        if (newImplementation != address(0)) {
            require(IPERMISSION.checkAddress(newImplementation, AddressTypeLib.IMPLEMENTATION), "impl err");
            assembly {
                sstore(IMPLEMENTATION_SLOT, newImplementation)
            }
            emit Upgraded(newImplementation);
        }

        // Update contracts, while preserving contract history so that old predictions/oracles can continue to be used
        if (newPredictionFactory != address(0)) {            
            require(IPERMISSION.checkAddress(newPredictionFactory, AddressTypeLib.PREDICTION_FACTORY), "factory err");
            predictionFactories.push(newPredictionFactory);
        }
        if (newOracle != address(0)) {
            require(IPERMISSION.checkAddress(newOracle, AddressTypeLib.ORACLE), "oracle err");
            oracles[newOracle] = true;
        }

        // Log success event
        emit WalletUpgraded(requestId);
    }

    // Verify buy signature and transfer USDC to prediction contract
    function transferToBuyPrediction(address oracle, uint256 amount, bytes calldata encodedData, bytes calldata signature) external onlyPrediction {
        require(oracles[oracle], "oracle err");
        _checkSign(amount, encodedData, signature);
        transferUsdc(msg.sender, amount);
    }

    // Verify sell signature
    function transferToSellPrediction(uint256 amount, bytes calldata encodedData, bytes calldata signature) external onlyPrediction {
        _checkSign(amount, encodedData, signature);
    }

    // Verify signature and transfer USDC to oracle contract
    function transferToOracle(uint256 amount, bytes calldata encodedData, bytes calldata signature) external onlyOracle {
        _checkSign(amount, encodedData, signature);
        transferUsdc(msg.sender, amount);
    }

    // Check if the prediction is correct
    function _checkPrediction(address prediction) private view returns (bool) {
        uint256 len = predictionFactories.length;
        while (len != 0) {
            unchecked { --len; }
            if (IFactory(predictionFactories[len]).check(prediction)) {
                return true;
            }
        }
        return false;
    }

    // Check signature and update pre-signed amount
    function _checkSign(uint256 amount, bytes memory encodedData, bytes memory signature) private {
        if (boundWallet != address(0)) {
            if (signature.length != 0 || preSignAmount < amount) {
                require(boundWallet == EIP712Lib.recoverEIP712(DOMAIN_SEPARATOR, encodedData, signature), "signature err"); // If a signature is passed in or the operation amount exceeds the pre-signed amount, signature validity must be checked.
            } else {
                preSignAmount -= uint64(amount); // Deduct pre-signed amount (overflow considered)
            }
        }

        // Record last used time
        lastTime = uint64(block.timestamp);
    }
}


// ============================================================
// FILE: contracts/BaseUsdcContract.sol
// ============================================================
// SPDX-License-Identifier: UNLICENSED

/*
Copyright © 2025 PickYesNo.com. All Rights Reserved.
This source code is provided for viewing purposes only. No copying, distribution, modification, or commercial use is permitted without explicit written permission from the copyright holder.
Contact PickYesNo.com for licensing inquiries.
*/

pragma solidity 0.8.28;

import "./BaseContract.sol";

// USDC Base Contract
abstract contract BaseUsdcContract is BaseContract {
    address public constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359; // Built-in official USDC contract address

    IERC20 internal constant IUSDC = IERC20(USDC); // Official USDC contract interface

    event UsdcTransferredError(string reason);             // Event emitted when an error occurs while attempting to transfer USDC
    event UsdcTransferredLowLevelData(bytes lowLevelData); // Event emitted when an error occurs while attempting to transfer USDC

    // Transfer
    function transferUsdc(address to, uint256 amount) internal {
        try IUSDC.transfer(to, amount) returns (bool success) {
            require(success, "usdc err");
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("usdc err 1,", reason)));
        } catch (bytes memory lowLevelData) {
            revert(string(abi.encodePacked("usdc err 2,", lowLevelData)));
        }
    }

    // Attempt Transfer
    function tryTransferUsdc(address to, uint256 amount) internal returns (bool) {
        try IUSDC.transfer(to, amount) returns (bool success) {
            return success;
        } catch Error(string memory reason) {
            emit UsdcTransferredError(reason);
        } catch (bytes memory lowLevelData) {
            emit UsdcTransferredLowLevelData(lowLevelData);
        }
        return false;
    }
}


// ============================================================
// FILE: contracts/BaseContract.sol
// ============================================================
// SPDX-License-Identifier: UNLICENSED

/*
Copyright © 2025 PickYesNo.com. All Rights Reserved.
This source code is provided for viewing purposes only. No copying, distribution, modification, or commercial use is permitted without explicit written permission from the copyright holder.
Contact PickYesNo.com for licensing inquiries.
*/

pragma solidity 0.8.28;

import "./Common.sol";

// Base contract
abstract contract BaseContract {
    address public constant PERMISSION = 0xb98Fa2A38d147a5D3278c336191ADc719f7A8cef; // Built-in permission contract address

    IPermission internal constant IPERMISSION = IPermission(PERMISSION);  // Permission contract interface

    // Only the Executor EOA can call
    modifier onlyExecutorEOA() {
        require(IPERMISSION.checkAddress(msg.sender, AddressTypeLib.EXECUTOR_EOA), "unauthorized");
        _;
    }
}


// ============================================================
// FILE: contracts/Common.sol
// ============================================================
// SPDX-License-Identifier: UNLICENSED

/*
Copyright © 2025 PickYesNo.com. All Rights Reserved.
This source code is provided for viewing purposes only. No copying, distribution, modification, or commercial use is permitted without explicit written permission from the copyright holder.
Contact PickYesNo.com for licensing inquiries.
*/

pragma solidity 0.8.28;

struct PredictionSetting {
    // slot 0
    uint64 optionId;          // Option id
    uint64 roundNo;           // Round number
    uint32 startTime;         // Start time
    uint32 endTime;           // End time
    uint32 interval;          // Interval of each round
    uint16 aggregator;        // Aggregator for chainlink using  
    uint16 maxVotes;          // Maximum number of votes for single outcome

    // slot 1
    uint64 stakingAmount;     // Voting stake amount, unit: 1 USDC, i.e., 10**6
    uint64 challengeStaking;  // Challenge stake amount, unit: 1 USDC, i.e., 10**6
    uint32 votingDuration;    // Voting duration (in seconds)
    uint32 challengeDuration; // Challenge duration (in seconds)
    uint32 totalRewards;      // Total reward amount, unit: 1 USDC, i.e., 10**6
    uint8 rewardRanking;      // Ranking required to receive rewards
    uint8 challengePercent;   // Percentage of reward taken by challengers: 0~100%
    bool independent;         // Whether results are independent, false = single result, true = independent result
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;    
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface AggregatorV3Interface {
    function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface IPermission {
    function feeEOA() external view returns (address);
    function managerEOA() external view returns (address);
    function operationEOA() external view returns (address);
    function setAddress(uint256 requestId, address newAddress, uint256 addrType, bool value) external;
    function setAddresses(uint256 requestId, address[] calldata newAddresses, uint256 addrType, bool value) external;
    function checkAddress(address addr, uint256 addrType) external view returns (bool);
    function checkAddress2(address addr1, uint256 addrType1, address addr2, uint256 addrType2) external view returns (bool);
    function checkAddress3(address addr1, uint256 addrType1, address addr2, uint256 addrType2, address addr3, uint256 addrType3) external view returns (bool);
}

interface IFactory {  
    function check(address addr) external view returns (bool);
}

interface IPrediction {
    function getSetting(uint256 optionId) external view returns (PredictionSetting memory);
}

interface IOracle {
    function getOutcome(address prediction, uint256 optionId) external view returns (uint256);
}

interface IWallet {
    function transferToBuyPrediction(address oracle, uint256 amount, bytes calldata encodedData, bytes calldata signature) external;
    function transferToSellPrediction(uint256 amount, bytes calldata encodedData, bytes calldata signature) external;
    function transferToOracle(uint256 amount, bytes calldata encodedData, bytes calldata signature) external;
}

interface IMarketing {
    function transferFrom(uint256 amount, address wallet, bytes32 code, bytes calldata signature) external;
}

library AddressTypeLib {
    uint256 public constant EXECUTOR_EOA = 1000;
    uint256 public constant ARBITRATOR_EOA = 2000;
    uint256 public constant MARKETING = 3000;
    uint256 public constant ERC20 = 4000;
    uint256 public constant IMPLEMENTATION = 5000;
    uint256 public constant WALLET_FACTORY = 6000;
    uint256 public constant WALLET = 7000;
    uint256 public constant PREDICTION_FACTORY = 8000;
    uint256 public constant PREDICTION = 9000;
    uint256 public constant ORACLE = 10000;
}

library OutcomeTypeLib {
    uint256 public constant ZERO = 0;
    uint256 public constant YES = 1;
    uint256 public constant NO = 2;
    uint256 public constant UNCLEAR = 3;
    uint256 public constant PENDING = 4;
    uint256 public constant CANCELLED = 5; 
}

library EIP712Lib {
    bytes32 public constant EIP712_DOMAIN = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    function recoverEIP712(bytes32 domainSeparator, bytes memory encodedData, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) {
            return address(0);
        }
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))          
        }
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }
        bytes32 structHash = keccak256(encodedData);
        bytes32 digest;
        assembly ("memory-safe") { 
            let ptr := mload(0x40)
            mstore(ptr, hex"19_01")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            digest := keccak256(ptr, 0x42)            
        }
        return ecrecover(digest, v, r, s);
    }
}