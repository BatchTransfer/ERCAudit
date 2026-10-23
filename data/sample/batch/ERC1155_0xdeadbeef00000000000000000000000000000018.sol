// File: contracts/ArexaPlatform/ArexaPfmTokenFacet.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 AREXA
 */
pragma solidity ^0.8.9;

import { IERC1155 } from "../base/ERC1155/IERC1155.sol";

import { LibERC1155 } from "../base/ERC1155/base/LibERC1155.sol";

import { CallProtection } from "../base/Shared/ProtectedCall.sol";
import { ModifierPausable } from "../base/TargetedPausable/ModifierPausable.sol";
import { LibArexaConst } from "./LibArexaConst.sol";

contract ArexaPfmTokenFacet is IERC1155, CallProtection, ModifierPausable {
	constructor() {}

	function safeTransferFrom(
		address _from,
		address _to,
		uint256 _id,
		uint256 _value,
		bytes calldata _data
	) external override protectedCall whenNotPaused(LibArexaConst.FULL) {
		LibERC1155.safeTransfer(msg.sender, _from, _to, _id, _value, _data);
	}

	function safeBatchTransferFrom(
		address _from,
		address _to,
		uint256[] calldata _ids,
		uint256[] calldata _values,
		bytes calldata _data
	) external override protectedCall whenNotPaused(LibArexaConst.FULL) {
		LibERC1155.safeTransferBatch(msg.sender, _from, _to, _ids, _values, _data);
	}

	function balanceOf(address _owner, uint256 _id) external view override returns (uint256) {
		return LibERC1155.balanceOf(_owner, _id);
	}

	function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids) external view override returns (uint256[] memory) {
		return LibERC1155.balanceOfBatch(_owners, _ids);
	}

	function setApprovalForAll(address _operator, bool _approved) external override protectedCall whenNotPaused(LibArexaConst.FULL) {
		LibERC1155.setApprovalForAll(msg.sender, _operator, _approved);
	}

	function isApprovedForAll(address _owner, address _operator) external view override returns (bool) {
		return LibERC1155.isApprovedForAll(_owner, _operator);
	}
}


// File: contracts/ArexaPlatform/LibArexaConst.sol
// SPDX-License-Identifier: UNLICENCED
/**
 * Copyright (C) 2023 AREXA
 */
pragma solidity ^0.8.9;

library LibArexaConst {
	//
	//Pausable
	bytes32 public constant FULL = 0x00;
	bytes32 public constant SUBSCR1_TOKEN = keccak256(abi.encode("TOKEN", LibArexaConst.SUBSCR1_TOKEN_TYPE));
	bytes32 public constant SUBSCR2_TOKEN = keccak256(abi.encode("TOKEN", LibArexaConst.SUBSCR2_TOKEN_TYPE));
	bytes32 public constant TRADER_TOKEN = keccak256(abi.encode("TOKEN", LibArexaConst.TRADER_TOKEN_ID));
	bytes32 public constant AREXA_TOKEN = keccak256(abi.encode("TOKEN", LibArexaConst.AREXA_TOKEN_ID));
	bytes32 public constant MAGIC_TOKEN = keccak256(abi.encode("TOKEN", LibArexaConst.MAGIC_TOKEN_ID));

	//Roles
	bytes32 public constant AREXA_ADMIN_ROLE = keccak256("AREXA_ADMIN_ROLE");
	//bytes32 public constant TOKEN_ADMIN_ROLE = keccak256("AREXA_TOKEN_ADMIN_ROLE");
	//bytes32 public constant TREASURY_ROLE = keccak256("AREXA_TREASURY_ROLE");

	//BlackWhite lists
	bytes32 public constant MAGIC100_FIRST_BUYER = keccak256("MAGIC100_FIRST_BUYER"); //WhiteList

	//TokenIDs:
	uint256 public constant SUBSCR1_TOKEN_TYPE = 100000000; //Tier 1, every month
	uint256 public constant SUBSCR2_TOKEN_TYPE = 200000000; //Tier 2, every month
	uint256 public constant TRADER_TOKEN_ID = 300000000; //Tier 3, unlimited, always mint
	uint256 public constant AREXA_TOKEN_ID = 400000000; //Tier 4, 100000000 piece
	uint256 public constant MAGIC_TOKEN_ID = 500000000; //Tier 5, 100 piece

	//AREXA TOKEN POOL TYPES:
	uint8 public constant AREXA_TOKEN_POOL_INVESTOR = 1; //35M
	uint8 public constant AREXA_TOKEN_POOL_AREXAINC = 2; //5M
	uint8 public constant AREXA_TOKEN_POOL_MARKETING = 3; //5M
	uint8 public constant AREXA_TOKEN_POOL_DEVELOPMENT = 4; //5M
	uint8 public constant AREXA_TOKEN_POOL_RESERVED = 5; //50M
}


// File: contracts/ArexaPlatform/Platform/LibArexaPlatform.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 AREXA
 */
pragma solidity ^0.8.9;

import "hardhat/console.sol";

import "./LibArexaPlatformStorage.sol";
import "../../utils/Math.sol";

import "../../base/Diamond/LibDiamond.sol";
import "../../base/ERC1155/base/LibERC1155.sol";
import "../../base/TokenRestriction/LibTokenRestriction.sol";
import "../../base/TokenPNL/LibTokenPNL.sol";
import "../../base/TokenDynamicPricing/LibTokenDynamicPricing.sol";

import "../LibArexaConst.sol";

import { IERC20 } from "../../base/ERC20/IERC20.sol";
import { IERC20Metadata } from "../../base/ERC20/metadata/IERC20Metadata.sol";
import "../../base/BridgeCentralized/IBridgeableToken.sol";

library LibArexaPlatform {
	uint8 public constant AMOUNT_VALUE_TYPE = 0;
	uint8 public constant QUANTITY_VALUE_TYPE = 1;

	function _initArexaTokenPool(uint8 _tokenType, address _operator, address _tokenOwner, uint256 _amount) internal {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		require(arexa.arexaTokenPool[_tokenType].total == 0, "Arexa token pool is already initialized with the give type!");
		arexa.arexaTokenPool[_tokenType].total = _amount;
		LibERC1155.mint(_operator, _tokenOwner, LibArexaConst.AREXA_TOKEN_ID, _amount, "");
	}

	function initialize(address _operator, IERC20 payingToken, IERC20 arexaERC20Token, uint64 restrictionTimeDelta) internal {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		address contractAddress = LibDiamond.getDiamondAddress();

		arexa.payingERC20Token = payingToken;
		arexa.arexaERC20Token = arexaERC20Token;

		/*
		 * Tier I: LibArexaConst.SUBSCR_TOKEN_TYPE_1
		 */
		setArexaIncomeParameter(LibArexaConst.SUBSCR1_TOKEN_TYPE, 90, 10);

		/*
		 * Tier II: LibArexaConst.SUBSCR_TOKEN_TYPE_2
		 */
		setArexaIncomeParameter(LibArexaConst.SUBSCR2_TOKEN_TYPE, 95, 5);

		/*
		 * Tier III: LibArexaConst.TRADER_TOKEN_ID
		 */
		setArexaIncomeParameter(LibArexaConst.TRADER_TOKEN_ID, 995, 5);

		/*
		 * Tier IV: LibArexaConst.AREXA_TOKEN_ID
		 */
		setArexaIncomeParameter(LibArexaConst.AREXA_TOKEN_ID, 90, 10);

		//Engedélyezzük a tokenre a PNL számolást, így inicializálódik teljes darabszám is a PNLnél.
		LibTokenPNL.initTokenPNL(address(payingToken), LibArexaConst.AREXA_TOKEN_ID);

		//Ez által olyan mintha már nem kéne restriction-t kezelni, és a teljes összeg megy a kifizethetőbe
		LibTokenRestriction.initTokenRestriction(LibArexaConst.AREXA_TOKEN_ID, block.number, block.number + 1, restrictionTimeDelta);

		//kibocsájtjuk a poolba a tokeneket, de azonnal eladhatóak lesznek, a reserved tokeneket csak restriction élesítés után
		_initArexaTokenPool(LibArexaConst.AREXA_TOKEN_POOL_INVESTOR, _operator, contractAddress, 35000000);
		_initArexaTokenPool(LibArexaConst.AREXA_TOKEN_POOL_AREXAINC, _operator, contractAddress, 5000000);
		_initArexaTokenPool(LibArexaConst.AREXA_TOKEN_POOL_MARKETING, _operator, contractAddress, 5000000);
		_initArexaTokenPool(LibArexaConst.AREXA_TOKEN_POOL_DEVELOPMENT, _operator, contractAddress, 5000000);

		//Véglegesítjük a restriction paramétereket
		LibTokenRestriction.initTokenRestriction(
			LibArexaConst.AREXA_TOKEN_ID,
			block.number + 12 * restrictionTimeDelta + 1,
			block.number + 12 * restrictionTimeDelta + 1 + 12 * restrictionTimeDelta + 1,
			restrictionTimeDelta
		);

		//A reserved poolba most hozzuk létre, így a restriction érvényes lesz rá
		_initArexaTokenPool(LibArexaConst.AREXA_TOKEN_POOL_RESERVED, _operator, contractAddress, 50000000);

		/*
		 * Tier V: LibArexaConst.MAGIC_TOKEN_ID
		 */
		setArexaIncomeParameter(LibArexaConst.MAGIC_TOKEN_ID, 0, 100);
		LibERC1155.mint(_operator, contractAddress, LibArexaConst.MAGIC_TOKEN_ID, 100, "");
	}

	//TODO do the other functions...
	function getArexaTokenPool(uint8 _tokenType) internal view returns (ArexaTokenPool memory) {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		return arexa.arexaTokenPool[_tokenType];
	}

	function setArexaIncomeParameter(uint256 _tokenId, uint32 _pool, uint32 _arexa) internal {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		arexa.arexaIncomeParameter[_tokenId].pool = _pool;
		arexa.arexaIncomeParameter[_tokenId].arexa = _arexa;
	}

	function getArexaIncomeParameter(uint256 _tokenId) internal view returns (uint32 pool_, uint32 arexa_) {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		pool_ = arexa.arexaIncomeParameter[_tokenId].pool;
		arexa_ = arexa.arexaIncomeParameter[_tokenId].arexa;
	}

	function getPayingToken() internal view returns (IERC20) {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		return arexa.payingERC20Token;
	}

	function setPayingToken(IERC20 _token) internal {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		arexa.payingERC20Token = _token;
	}

	function getArexaERC20Token() internal view returns (IERC20) {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		return arexa.arexaERC20Token;
	}

	function _divideAmountPoolAndArexa(uint256 _tokenId, uint256 _value) internal {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();

		uint256 poolAmount = (_value * arexa.arexaIncomeParameter[_tokenId].pool) /
			(arexa.arexaIncomeParameter[_tokenId].pool + arexa.arexaIncomeParameter[_tokenId].arexa);
		uint256 arexaAmount = _value - poolAmount;

		LibTokenPNL.changeTotalValue(address(arexa.payingERC20Token), LibArexaConst.AREXA_TOKEN_ID, int256(poolAmount));
		arexa.poolBalance += poolAmount;
		arexa.arexaBalance += arexaAmount;
	}

	function createSubscriptions(
		address _operator,
		uint256 _tokenType,
		uint16 _year,
		uint8 _month,
		uint256 _quantity,
		uint256 _min,
		uint256 _max
	) internal returns (uint256 tokenId) {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		//100 000 000 10**8
		// 20 240 000
		uint256 monthlyTokenType = _tokenType + uint256(_year) * 10 ** 4 + uint256(_month) * 10 ** 2;

		require(int256(arexa.lastSubscriptionTokenIds[_tokenType]) - int256(monthlyTokenType) < 99, "Can't create for old months");

		if (arexa.lastSubscriptionTokenIds[_tokenType] < monthlyTokenType) {
			arexa.lastSubscriptionTokenIds[_tokenType] = monthlyTokenType;
		}
		arexa.lastSubscriptionTokenIds[_tokenType]++;
		tokenId = arexa.lastSubscriptionTokenIds[_tokenType];
		LibTokenDynamicPricing.initialize(tokenId, _quantity, _min, _max);
		LibERC1155.mint(_operator, LibDiamond.getDiamondAddress(), tokenId, _quantity, "");
	}

	function getCurrentSubscriptionTokenId(uint256 _tokenType) internal view returns (uint256) {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		return arexa.lastSubscriptionTokenIds[_tokenType];
	}

	function calcSubscriptionPrice(uint256 _tokenId, uint32 _quantity) internal view returns (uint256) {
		return LibTokenDynamicPricing.calcTotalValue(_tokenId, _quantity);
	}

	function buySubscription(uint256 _tokenId, address _account, uint32 _quantity) internal {
		//Tier3
		//AREXA_TOKEN
		//Price: d USDT/piece
		//Quantity: No limit to buy
		//_valueType: 0 is amount, 1 is quantity
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();

		uint256 amount = LibTokenDynamicPricing.buyQuantity(_tokenId, _quantity);

		address contractAddress = LibDiamond.getDiamondAddress();

		bool result = arexa.payingERC20Token.transferFrom(_account, contractAddress, amount);
		require(result, "Something wrong with the payment!");

		//divide the amount to pool and arexa
		//SUBSCR1_TOKEN_TYPE OR SUBSCR2_TOKEN_TYPE lesz a vége
		uint256 tokenType = (_tokenId / 100000000) * 100000000;
		_divideAmountPoolAndArexa(tokenType, amount);

		LibERC1155.safeTransfer(contractAddress, contractAddress, _account, _tokenId, _quantity, "");
	}

	function buyTraderToken(address _operator, address _account, uint128 _value, uint8 _valueType) internal {
		//Tier3
		//AREXA_TOKEN
		//Price: 1.0 USDT/piece
		//Quantity: No limit to buy
		//_valueType: 0 is amount, 1 is quantity
		require(_valueType == 0 || _valueType == 1, "valueType can be 0 or 1 only!");

		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();

		uint256 decimal = 10 ** IERC20Metadata(address(arexa.payingERC20Token)).decimals();
		uint256 priceFactor = 10;
		uint256 price = decimal * priceFactor * 1;

		uint256 amount = 0;
		uint256 quantity = 0;
		if (_valueType == 1) {
			amount = ((_value * 10 * price) / priceFactor + 5) / 10; //add 5 and div 10: rounding to the nearest
			quantity = (amount * priceFactor) / price;
			require(amount > 0 && quantity > 0, "The input quantity is too small for paying token!");
		} else {
			quantity = (_value * priceFactor) / price;
			amount = (quantity * price) / priceFactor;
			require(amount > 0 && quantity > 0, "The input amount is too small for buying a token!");
		}

		address contractAddress = LibDiamond.getDiamondAddress();

		bool result = arexa.payingERC20Token.transferFrom(_account, contractAddress, amount);
		require(result, "Something wrong with the payment!");

		//divide the amount to pool and arexa, fontos a sorrend, mielőtt megkapta a tokent és adminisztráltuk a PNL változást, előtte növeljük a pool értéket
		//azért mert így a deltaPNLben nem napja meg maga után járó részt.
		_divideAmountPoolAndArexa(LibArexaConst.TRADER_TOKEN_ID, amount);

		LibERC1155.mint(_operator, _account, LibArexaConst.TRADER_TOKEN_ID, quantity, "");
	}

	function buyArexaToken(address _account, uint128 _value, uint8 _valueType) internal {
		//Tier4
		//AREXA_TOKEN
		//Price: 0.1 USDT/piece
		//Quantity: No limit to buy
		//_valueType: 0 is amount, 1 is quantity

		require(_valueType == 0 || _valueType == 1, "valueType can be 0 or 1 only!");

		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();

		uint256 decimal = 10 ** IERC20Metadata(address(arexa.payingERC20Token)).decimals();
		uint256 priceFactor = 10;
		uint256 price = ((decimal * priceFactor) * 1) / 10;

		uint256 amount = 0;
		uint256 quantity = 0;
		if (_valueType == 1) {
			amount = ((_value * 10 * price) / priceFactor + 5) / 10; //add 5 and div 10: rounding to the nearest
			quantity = (amount * priceFactor) / price;
			require(amount > 0 && quantity > 0, "The input quantity is too small for paying token");
		} else {
			quantity = (_value * priceFactor) / price;
			amount = (quantity * price) / priceFactor;
			require(amount > 0 && quantity > 0, "The input amount is too small for buying a token");
		}

		ArexaTokenPool storage tokenPool = arexa.arexaTokenPool[LibArexaConst.AREXA_TOKEN_POOL_INVESTOR];
		require(tokenPool.sold + quantity <= tokenPool.total, "Not enough token to sell");
		tokenPool.sold = tokenPool.sold + quantity;

		address contractAddress = LibDiamond.getDiamondAddress();

		bool result = arexa.payingERC20Token.transferFrom(_account, contractAddress, amount);
		require(result, "Something wrong with the payment!");

		//divide the amount to pool and arexa, fontos a sorrend, mielőtt megkapta a tokent és adminisztráltuk a PNL változást, előtte növeljük a pool értéket
		//azért mert így a deltaPNLben nem napja meg maga után járó részt.
		_divideAmountPoolAndArexa(LibArexaConst.AREXA_TOKEN_ID, amount);

		LibERC1155.safeTransfer(contractAddress, contractAddress, _account, LibArexaConst.AREXA_TOKEN_ID, quantity, "");
		arexa.stakedArexaERC20TokenQuantity = arexa.stakedArexaERC20TokenQuantity + quantity;
	}

	function payByArexaToken(uint8 _poolType, address _account, uint32 _quantity) internal {
		//Tier4
		//AREXA_TOKEN GIFT
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();

		ArexaTokenPool storage tokenPool = arexa.arexaTokenPool[_poolType];
		require(tokenPool.sold + _quantity <= tokenPool.total, "Not enoguh token to gift");
		tokenPool.sold = tokenPool.sold + _quantity;

		address contractAddress = LibDiamond.getDiamondAddress();

		LibERC1155.safeTransfer(contractAddress, contractAddress, _account, LibArexaConst.AREXA_TOKEN_ID, _quantity, "");
		arexa.stakedArexaERC20TokenQuantity = arexa.stakedArexaERC20TokenQuantity + _quantity;
	}

	function buyMagic100Token(address _account) internal {
		//Tier5
		//MAGIC_TOKEN_ID
		//Price: 100.0 USDT/piece
		//Quantity: 1

		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();

		uint256 decimal = 10 ** IERC20Metadata(address(arexa.payingERC20Token)).decimals();
		uint256 amount = 100 * decimal;

		address contractAddress = LibDiamond.getDiamondAddress();

		bool result = arexa.payingERC20Token.transferFrom(_account, contractAddress, amount);
		require(result, "Something wrong with the payment!");

		LibERC1155.safeTransfer(contractAddress, contractAddress, _account, LibArexaConst.MAGIC_TOKEN_ID, 1, "");

		//divide the amount to pool and arexa, fontos a sorrend, miután megkapta a tokent és adminisztráltuk a PNL változást, utána növeljük a pool értéket csak!
		_divideAmountPoolAndArexa(LibArexaConst.MAGIC_TOKEN_ID, amount);
	}

	function payoutArexaIncome(address _account, uint256 _value) internal {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();
		require(_value <= arexa.arexaBalance, "Not enough amount to pay out!");

		bool result = arexa.payingERC20Token.transferFrom(LibDiamond.getDiamondAddress(), _account, _value);
		require(result, "Something wrong with the payment!");
	}

	function payoutPoolDivident(address _collectingAccount, address _toAccount, uint256 _amount) internal {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();

		LibTokenPNL.refreshPayoutDivident(
			address(LibArexaPlatform.getPayingToken()),
			LibArexaConst.AREXA_TOKEN_ID,
			_collectingAccount,
			int256(_amount)
		);
		bool result = arexa.payingERC20Token.transferFrom(LibDiamond.getDiamondAddress(), _toAccount, _amount);
		require(result, "Something wrong with the payment!");
	}

	function stakeArexaToken(address _fromAccount, address _toAccount, uint256 _quantity) internal {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();

		//Caclulate each token quantity from input. Input is an arexa20Quantity, but can have decimals fractions, so have to "round floor"
		//arexa11555Quantity have only whole number
		uint256 decimal = 10 ** IERC20Metadata(address(arexa.arexaERC20Token)).decimals();
		uint256 arexa11555Quantity = _quantity / decimal;
		uint256 arexa20Quantity = arexa11555Quantity * decimal;

		require(arexa11555Quantity > 0 && arexa20Quantity > 0, "The input amount is too small for staking (AREXA AI token)");

		//Burn the Arexa AI ERC20 from user
		IBridgeableToken(address(arexa.arexaERC20Token)).burnFrom(_fromAccount, arexa20Quantity);

		address contractAddress = LibDiamond.getDiamondAddress();

		//Transfer Arexa AI Token from contract to user
		LibERC1155.safeTransfer(contractAddress, contractAddress, _toAccount, LibArexaConst.AREXA_TOKEN_ID, arexa11555Quantity, "");
		arexa.stakedArexaERC20TokenQuantity = arexa.stakedArexaERC20TokenQuantity + arexa11555Quantity;
	}

	function withdrawArexaToken(address _operator, address _fromAccount, address _toAccount, uint256 _quantity) internal {
		ArexaPlatformStorage storage arexa = LibArexaPlatformStorage.layout();

		//Caclulate each token quantity from input. Input is an arexa11555Quantity
		//arexa11555Quantity have only whole number
		uint256 decimal = 10 ** IERC20Metadata(address(arexa.arexaERC20Token)).decimals();
		uint256 arexa20Quantity = _quantity * decimal;

		//Transfer Arexa AI Token from user to contract
		LibERC1155.safeTransfer(_operator, _fromAccount, LibDiamond.getDiamondAddress(), LibArexaConst.AREXA_TOKEN_ID, _quantity, "");

		//Mint the Arexa AI ERC20 to user
		IBridgeableToken(address(arexa.arexaERC20Token)).mint(_toAccount, arexa20Quantity);

		arexa.stakedArexaERC20TokenQuantity = arexa.stakedArexaERC20TokenQuantity - _quantity;
	}
}


// File: contracts/ArexaPlatform/Platform/LibArexaPlatformStorage.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 AREXA
 */
pragma solidity ^0.8.9;

import { EnumerableSet } from "../../utils/EnumerableSet.sol";
import { IERC20 } from "../../base/ERC20/IERC20.sol";

struct ArexaTokenPool {
	uint256 total;
	uint256 sold;
}

struct ArexaIncomeParameter {
	uint32 pool;
	uint32 arexa;
}

struct ArexaPlatformStorage {
	mapping(uint8 => ArexaTokenPool) arexaTokenPool;
	mapping(uint256 => ArexaIncomeParameter) arexaIncomeParameter;
	IERC20 payingERC20Token; //USDT
	uint256 poolBalance; //The "pool" part of the sum income
	uint256 arexaBalance; //The "owner" part of the sum income
	//tokenType => lastSubscriptionTokenId
	mapping(uint256 => uint256) lastSubscriptionTokenIds;
	IERC20 arexaERC20Token; //AREXA
	uint256 stakedArexaERC20TokenQuantity;
}

library LibArexaPlatformStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("usmart.contracts.arexa-platform.storage.v1");

	function layout() internal pure returns (ArexaPlatformStorage storage layout_) {
		bytes32 position = STORAGE_SLOT;
		assembly {
			layout_.slot := position
		}
	}
}


// File: contracts/base/AccessControl/LibAccessControl.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import "./LibAccessControlStorage.sol";

import { IERC173 } from "../../interfaces/IERC173.sol";

import { EnumerableSet } from "../../utils/EnumerableSet.sol";
import { UintUtils } from "../../utils/UintUtils.sol";
import { AddressUtils } from "../../utils/AddressUtils.sol";

library LibAccessControl {
	using EnumerableSet for EnumerableSet.AddressSet;
	using UintUtils for uint256;
	using AddressUtils for address;

	error Ownable__NotOwner();
	error Ownable__NotTransitiveOwner();

	error AccessDenied(bytes32 role, address account);

	event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

	event RoleAdminChanged(address indexed owner, bytes32 role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
	event RoleGranted(address indexed owner, bytes32 role, address indexed account, address indexed sender);
	event RoleRevoked(address indexed owner, bytes32 role, address indexed account, address indexed sender);

	bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

	function _setOwner(address _newOwner) internal {
		AccessControllStorage storage acls = LibAccessControlStorage.layout();
		address previousOwner = acls.owner;
		acls.owner = _newOwner;

		//Init DEFAULT_ADMIN_ROLE to _newOwner
		LibAccessControl._grantRole(LibAccessControl.DEFAULT_ADMIN_ROLE, _newOwner);

		emit OwnershipTransferred(previousOwner, _newOwner);
	}

	function _owner() internal view returns (address owner_) {
		AccessControllStorage storage acls = LibAccessControlStorage.layout();
		owner_ = acls.owner;
	}

	function _transitiveOwner() internal view returns (address owner_) {
		owner_ = LibAccessControl._owner();

		while (owner_.isContract()) {
			try IERC173(owner_).owner() returns (address transitiveOwner) {
				owner_ = transitiveOwner;
			} catch {
				break;
			}
		}
	}

	function _enforceIsOwner() internal view {
		//require(msg.sender == _owner(), "Not owner!");
		if (msg.sender != _owner()) {
			revert Ownable__NotOwner();
		}
	}

	function _enforceIsTransitiveOwner() internal view {
		//require(msg.sender == _transitiveOwner(), "Not transitive owner!");
		if (msg.sender != _transitiveOwner()) {
			revert Ownable__NotTransitiveOwner();
		}
	}

	/**
	 * @notice assign role to given account
	 * @param _role role to assign
	 * @param _account recipient of role assignment
	 */
	function _grantRole(bytes32 _role, address _account) internal {
		AccessControllStorage storage acls = LibAccessControlStorage.layout();
		if (!_hasRole(_role, _account)) {
			acls.roles[acls.owner][_role].members.add(_account);
			emit RoleGranted(acls.owner, _role, _account, msg.sender);
		}
	}

	/**
	 * @notice unassign role from given account
	 * @param _role role to unassign
	 * @param _account account to revokeAccessControlStorage
	 */
	function _revokeRole(bytes32 _role, address _account) internal {
		AccessControllStorage storage acls = LibAccessControlStorage.layout();
		// require(_role != LibAccessControl.DEFAULT_ADMIN_ROLE && _account != acls.owner);
		acls.roles[acls.owner][_role].members.remove(_account);
		emit RoleRevoked(acls.owner, _role, _account, msg.sender);
	}

	/**
	 * @notice relinquish role
	 * @param _role role to relinquish
	 */
	function _renounceRole(bytes32 _role) internal {
		_revokeRole(_role, msg.sender);
	}

	/**
	 * @notice Query one of the accounts that have role of the project
	 * @dev WARNING: When using _getProjectRoleMember and _getProjectRoleMemberCount, make sure you perform all queries on the same block.
	 * @param _role role to query
	 * @param _index index of role member
	 */
	function _getRoleMember(bytes32 _role, uint256 _index) internal view returns (address) {
		AccessControllStorage storage acls = LibAccessControlStorage.layout();
		return acls.roles[acls.owner][_role].members.at(_index);
	}

	/**
	 * @notice Query the number of accounts that have role.
	 * @dev WARNING: When using _getRoleMember and _getRoleMemberCount, make sure you perform all queries on the same block.
	 * @param _role role to query
	 */
	function _getRoleMemberCount(address, bytes32 _role) internal view returns (uint256) {
		AccessControllStorage storage acls = LibAccessControlStorage.layout();
		return acls.roles[acls.owner][_role].members.length();
	}

	/**
	 * @notice query whether role is assigned to account
	 * @param _role role to query
	 * @param _account account to query
	 * @return bool whether role is assigned to account
	 */
	function _hasRole(bytes32 _role, address _account) internal view returns (bool) {
		AccessControllStorage storage acls = LibAccessControlStorage.layout();
		return acls.roles[acls.owner][_role].members.contains(_account);
	}

	/**
	 * @notice revert if sender does not have given role
	 * @param _role role to query
	 */
	function _checkRole(bytes32 _role) internal view {
		_checkRole(_role, msg.sender);
	}

	/**
	 * @notice revert if given account does not have given role
	 * @param _role role to query
	 * @param _account to query
	 */
	function _checkRole(bytes32 _role, address _account) internal view {
		if (!_hasRole(_role, _account)) {
			revert AccessDenied({ role: _role, account: _account });
		}
	}

	/**
	 * @notice query admin role for given role
	 * @param _role role to query
	 * @return admin role
	 */
	function _getRoleAdmin(bytes32 _role) internal view returns (bytes32) {
		AccessControllStorage storage acls = LibAccessControlStorage.layout();
		return acls.roles[acls.owner][_role].adminRole;
	}

	/**
	 * @notice set role as admin role
	 * @param _role role to set
	 * @param _adminRole admin role to set
	 */
	function _setRoleAdmin(bytes32 _role, bytes32 _adminRole) internal {
		AccessControllStorage storage acls = LibAccessControlStorage.layout();
		bytes32 previousAdminRole = _getRoleAdmin(_role);
		acls.roles[acls.owner][_role].adminRole = _adminRole;
		emit RoleAdminChanged(acls.owner, _role, previousAdminRole, _adminRole);
	}
}


// File: contracts/base/AccessControl/LibAccessControlStorage.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { EnumerableSet } from "../../utils/EnumerableSet.sol";
import "./RoleData.sol";

struct AccessControllStorage {
	//owner => role => adminRole, members mapping
	address owner;
	mapping(address => mapping(bytes32 => RoleData)) roles;
}

library LibAccessControlStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("usmart.common.access-control.storage.v1");

	function layout() internal pure returns (AccessControllStorage storage acls_) {
		bytes32 position = STORAGE_SLOT;
		assembly {
			acls_.slot := position
		}
	}
}


// File: contracts/base/AccessControl/RoleData.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { EnumerableSet } from "../../utils/EnumerableSet.sol";

struct RoleData {
	bytes32 adminRole;
	EnumerableSet.AddressSet members;
}


// File: contracts/base/BridgeCentralized/IBridgeableToken.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

interface IBridgeableToken {
	function mint(address to, uint256 amount) external;

	function burnFrom(address from, uint256 amount) external;
}


// File: contracts/base/Diamond/LibDiamond.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/
import "./LibDiamondStorage.sol";
import { IDiamondCut } from "../../interfaces/IDiamondCut.sol";

import { LibAccessControl } from "../AccessControl/LibAccessControl.sol";

// Remember to add the loupe functions from DiamondLoupeFacet to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

library LibDiamond {
	event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

	function setDiamondAddress(address _diamondAddress) internal {
		DiamondStorage storage ds = LibDiamondStorage.layout();
		require(ds.diamondAddress == address(0), "Already initialized!");
		ds.diamondAddress = _diamondAddress;
	}

	function getDiamondAddress() internal view returns (address) {
		DiamondStorage storage ds = LibDiamondStorage.layout();
		return ds.diamondAddress;
	}

	function setContractOwner(address _newOwner) internal {
		LibAccessControl._setOwner(_newOwner);
	}

	function enforceIsContractOwner() internal view {
		LibAccessControl._enforceIsOwner();
	}

	// Internal function version of diamondCut
	function diamondCut(IDiamondCut.FacetCut[] memory _diamondCut, address _init, bytes memory _calldata) internal {
		for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
			IDiamondCut.FacetCutAction action = _diamondCut[facetIndex].action;
			if (action == IDiamondCut.FacetCutAction.Add) {
				addFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
			} else if (action == IDiamondCut.FacetCutAction.Replace) {
				replaceFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
			} else if (action == IDiamondCut.FacetCutAction.Remove) {
				removeFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
			} else {
				revert("LibDiamondCut: Incorrect FacetCutAction");
			}
		}
		emit DiamondCut(_diamondCut, _init, _calldata);
		initializeDiamondCut(_init, _calldata);
	}

	function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
		require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
		DiamondStorage storage ds = LibDiamondStorage.layout();
		require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");
		uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
		// add new facet address if it does not exist
		if (selectorPosition == 0) {
			addFacet(ds, _facetAddress);
		}
		for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
			bytes4 selector = _functionSelectors[selectorIndex];
			address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
			require(oldFacetAddress == address(0), "LibDiamondCut: Can't add function that already exists");
			addFunction(ds, selector, selectorPosition, _facetAddress);
			selectorPosition++;
		}
	}

	function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
		require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
		DiamondStorage storage ds = LibDiamondStorage.layout();
		require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");
		uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
		// add new facet address if it does not exist
		if (selectorPosition == 0) {
			addFacet(ds, _facetAddress);
		}
		for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
			bytes4 selector = _functionSelectors[selectorIndex];
			address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
			require(oldFacetAddress != _facetAddress, "LibDiamondCut: Can't replace function with same function");
			removeFunction(ds, oldFacetAddress, selector);
			addFunction(ds, selector, selectorPosition, _facetAddress);
			selectorPosition++;
		}
	}

	function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
		require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
		DiamondStorage storage ds = LibDiamondStorage.layout();
		// if function does not exist then do nothing and return
		require(_facetAddress == address(0), "LibDiamondCut: Remove facet address must be address(0)");
		for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
			bytes4 selector = _functionSelectors[selectorIndex];
			address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
			removeFunction(ds, oldFacetAddress, selector);
		}
	}

	function addFacet(DiamondStorage storage ds, address _facetAddress) internal {
		enforceHasContractCode(_facetAddress, "LibDiamondCut: New facet has no code");
		ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = ds.facetAddresses.length;
		ds.facetAddresses.push(_facetAddress);
	}

	function addFunction(DiamondStorage storage ds, bytes4 _selector, uint96 _selectorPosition, address _facetAddress) internal {
		ds.selectorToFacetAndPosition[_selector].functionSelectorPosition = _selectorPosition;
		ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(_selector);
		ds.selectorToFacetAndPosition[_selector].facetAddress = _facetAddress;
	}

	function removeFunction(DiamondStorage storage ds, address _facetAddress, bytes4 _selector) internal {
		require(_facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");
		// an immutable function is a function defined directly in a diamond
		require(_facetAddress != address(this), "LibDiamondCut: Can't remove immutable function");
		// replace selector with last selector, then delete last selector
		uint256 selectorPosition = ds.selectorToFacetAndPosition[_selector].functionSelectorPosition;
		uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;
		// if not the same then replace _selector with lastSelector
		if (selectorPosition != lastSelectorPosition) {
			bytes4 lastSelector = ds.facetFunctionSelectors[_facetAddress].functionSelectors[lastSelectorPosition];
			ds.facetFunctionSelectors[_facetAddress].functionSelectors[selectorPosition] = lastSelector;
			ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(selectorPosition);
		}
		// delete the last selector
		ds.facetFunctionSelectors[_facetAddress].functionSelectors.pop();
		delete ds.selectorToFacetAndPosition[_selector];

		// if no more selectors for facet address then delete the facet address
		if (lastSelectorPosition == 0) {
			// replace facet address with last facet address and delete last facet address
			uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;
			uint256 facetAddressPosition = ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
			if (facetAddressPosition != lastFacetAddressPosition) {
				address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
				ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
				ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;
			}
			ds.facetAddresses.pop();
			delete ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
		}
	}

	function initializeDiamondCut(address _init, bytes memory _calldata) internal {
		if (_init == address(0)) {
			return;
		}
		enforceHasContractCode(_init, "LibDiamondCut: _init address has no code");
		(bool success, bytes memory error) = _init.delegatecall(_calldata);
		if (!success) {
			if (error.length > 0) {
				// bubble up error
				/// @solidity memory-safe-assembly
				assembly {
					let returndata_size := mload(error)
					revert(add(32, error), returndata_size)
				}
			} else {
				revert InitializationFunctionReverted(_init, _calldata);
			}
		}
	}

	function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
		uint256 contractSize;
		assembly {
			contractSize := extcodesize(_contract)
		}
		require(contractSize > 0, _errorMessage);
	}
}


// File: contracts/base/Diamond/LibDiamondStorage.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { EnumerableSet } from "../../utils/EnumerableSet.sol";

struct FacetAddressAndPosition {
	address facetAddress;
	uint96 functionSelectorPosition; // position in facetFunctionSelectors.functionSelectors array
}

struct FacetFunctionSelectors {
	bytes4[] functionSelectors;
	uint256 facetAddressPosition; // position of facetAddress in facetAddresses array
}

struct DiamondStorage {
	address diamondAddress;
	// maps function selector to the facet address and
	// the position of the selector in the facetFunctionSelectors.selectors array
	mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
	// maps facet addresses to function selectors
	mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
	// facet addresses
	address[] facetAddresses;
	// Used to query if a contract implements an interface.
	// Used to implement ERC-165.
	mapping(bytes4 => bool) supportedInterfaces;
	//the whole diamond is paused or not
	bool paused;
}

library LibDiamondStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("usmart.contracts.diamond.storage.v1");

	function layout() internal pure returns (DiamondStorage storage layout_) {
		bytes32 position = STORAGE_SLOT;
		assembly {
			layout_.slot := position
		}
	}
}


// File: contracts/base/ERC1155/base/LibERC1155.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import "./LibERC1155Storage.sol";

import "../customization/LibERC1155Customization.sol";

import { AddressUtils } from "../../../utils/AddressUtils.sol";
import { EnumerableSet } from "../../../utils/EnumerableSet.sol";
import { IERC1155Receiver } from "../IERC1155Receiver.sol";

error LibERC1155__BalanceQueryZeroAddress(); //Ok
error LibERC1155__ArrayLengthMismatch(); //Ok
error LibERC1155__MintToZeroAddress(); //ok
error LibERC1155__BurnExceedsBalance(); ///Ok
error LibERC1155__BurnFromZeroAddress(); //Ok
error LibERC1155__ERC1155ReceiverRejected(); // OK
error LibERC1155__ERC1155ReceiverNotImplemented(); //ok
error LibERC1155__TransferExceedsBalance(); //Ok
error LibERC1155__TransferToZeroAddress(); //Ok
error LibERC1155__NotOwnerOrApproved(); //Ok
error LibERC1155__NotOwnerOrApprovedLimit(); //Ok
error LibERC1155__SelfApproval(); //OK

library LibERC1155 {
	/************************************************************************************************************
	 *
	 * EVENTS from IERC1155
	 *
	 ************************************************************************************************************/
	event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

	event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);

	event ApprovalForAll(address indexed account, address indexed operator, bool approved);

	event URI(string value, uint256 indexed tokenId);

	/************************************************************************************************************
	 *
	 * EVENTS from IERC1155Allowance
	 *
	 ************************************************************************************************************/
	event Approval(address indexed owner, address indexed operator, uint256 indexed id, uint256 currenctValue, uint256 newValue);

	/************************************************************************************************************
	 *
	 * EVENTS from IERC1155Paused
	 *
	 ************************************************************************************************************/
	event AllTokenPaused(address indexed account);

	event AllTokenUnpaused(address indexed account);

	event TokenPaused(address indexed account, uint256 indexed tokenId);

	event TokenUnpaused(address indexed account, uint256 indexed tokenId);

	/************************************************************************************************************
	 *
	 * Usings
	 *
	 ************************************************************************************************************/
	using AddressUtils for address;
	using EnumerableSet for EnumerableSet.AddressSet;
	using EnumerableSet for EnumerableSet.UintSet;

	/************************************************************************************************************
	 *
	 * IERC1155
	 *
	 ************************************************************************************************************/

	/**
	 * @notice query the balance of given token held by given address
	 * @param _account address to query
	 * @param _tokenId token to query
	 * @return token balance
	 */
	function balanceOf(address _account, uint256 _tokenId) internal view returns (uint256) {
		if (_account == address(0)) revert LibERC1155__BalanceQueryZeroAddress();
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		return e1155s.balances[_tokenId][_account];
	}

	/**
	 * @notice query the balance of given token held by the given addresses
	 * @param _accounts addresses to query
	 * @param _tokenIds list of token IDs to query
	 * @return tokens' balance
	 */
	function balanceOfBatch(address[] memory _accounts, uint256[] memory _tokenIds) internal view returns (uint256[] memory) {
		require(_accounts.length == _tokenIds.length, "ERC1155: accounts and ids length mismatch");
		if (_tokenIds.length != _accounts.length) revert LibERC1155__ArrayLengthMismatch();

		uint256[] memory batchBalances = new uint256[](_accounts.length);

		for (uint256 i = 0; i < _accounts.length; ++i) {
			batchBalances[i] = balanceOf(_accounts[i], _tokenIds[i]);
		}

		return batchBalances;
	}

	/**
	 * @notice mint given quantity of tokens for given address
	 * @param _operator caller, msg.sender or msgSender()
	 * @param _toAccount beneficiary of minting
	 * @param _tokenId token ID
	 * @param _amount quantity of tokens to mint
	 * @param _data data payload
	 */
	function mint(address _operator, address _toAccount, uint256 _tokenId, uint256 _amount, bytes memory _data) internal {
		if (_toAccount == address(0)) revert LibERC1155__MintToZeroAddress();

		uint256[] memory tokenIds = _asSingletonArray(_tokenId);
		uint256[] memory amounts = _asSingletonArray(_amount);

		_beforeTokenTransfer(_operator, address(0), _toAccount, tokenIds, amounts, _data);

		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		_whenTokenNotPaused(e1155s, _tokenId);

		e1155s.balances[_tokenId][_toAccount] += _amount;
		emit TransferSingle(_operator, address(0), _toAccount, _tokenId, _amount);

		_afterTokenTransfer(_operator, address(0), _toAccount, tokenIds, amounts, _data);

		_doSafeTransferAcceptanceCheck(_operator, address(0), _toAccount, _tokenId, _amount, _data);
	}

	/**
	 * @notice mint batch of tokens for given address
	 * @param _operator caller, msg.sender or msgSender()
	 * @param _toAccount beneficiary of minting
	 * @param _tokenIds list of token IDs
	 * @param _amounts list of quantities of tokens to mint
	 * @param _data data payload
	 */
	function mintBatch(
		address _operator,
		address _toAccount,
		uint256[] memory _tokenIds,
		uint256[] memory _amounts,
		bytes memory _data
	) internal {
		if (_toAccount == address(0)) revert LibERC1155__MintToZeroAddress();
		if (_tokenIds.length != _amounts.length) revert LibERC1155__ArrayLengthMismatch();

		_beforeTokenTransfer(_operator, address(0), _toAccount, _tokenIds, _amounts, _data);

		ERC1155Storage storage e1155s = LibERC1155Storage.layout();

		for (uint256 i = 0; i < _tokenIds.length; ) {
			uint256 tokenId = _tokenIds[i];
			_whenTokenNotPaused(e1155s, tokenId);
			e1155s.balances[tokenId][_toAccount] += _amounts[i];
			unchecked {
				i++;
			}
		}

		emit TransferBatch(_operator, address(0), _toAccount, _tokenIds, _amounts);

		_afterTokenTransfer(_operator, address(0), _toAccount, _tokenIds, _amounts, _data);

		_doSafeBatchTransferAcceptanceCheck(_operator, address(0), _toAccount, _tokenIds, _amounts, _data);
	}

	/**
	 * @notice burn given quantity of tokens held by given address
	 * @param _operator caller, msg.sender or msgSender()
	 * @param _fromAccount holder of tokens to burn
	 * @param _tokenId token ID
	 * @param _amount quantity of tokens to burn
	 */
	function burn(address _operator, address _fromAccount, uint256 _tokenId, uint256 _amount) internal {
		if (_fromAccount == address(0)) revert LibERC1155__BurnFromZeroAddress();

		_beforeTokenTransfer(_operator, _fromAccount, address(0), _asSingletonArray(_tokenId), _asSingletonArray(_amount), "");

		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		_whenTokenNotPaused(e1155s, _tokenId);

		if (_amount > e1155s.balances[_tokenId][_fromAccount]) revert LibERC1155__BurnExceedsBalance();

		unchecked {
			e1155s.balances[_tokenId][_fromAccount] -= _amount;
		}

		emit TransferSingle(_operator, _fromAccount, address(0), _tokenId, _amount);
	}

	/**
	 * @notice burn given batch of tokens held by given address
	 * @param _operator caller, msg.sender or msgSender()
	 * @param _fromAccount holder of tokens to burn
	 * @param _tokenIds token IDs
	 * @param _amounts quantities of tokens to burn
	 */
	function burnBatch(address _operator, address _fromAccount, uint256[] memory _tokenIds, uint256[] memory _amounts) internal {
		if (_fromAccount == address(0)) revert LibERC1155__BurnFromZeroAddress();
		if (_tokenIds.length != _amounts.length) revert LibERC1155__ArrayLengthMismatch();

		_beforeTokenTransfer(_operator, _fromAccount, address(0), _tokenIds, _amounts, "");

		ERC1155Storage storage e1155s = LibERC1155Storage.layout();

		unchecked {
			for (uint256 i; i < _tokenIds.length; i++) {
				uint256 tokenId = _tokenIds[i];
				_whenTokenNotPaused(e1155s, tokenId);
				if (_amounts[i] > e1155s.balances[tokenId][_fromAccount]) revert LibERC1155__BurnExceedsBalance();
				e1155s.balances[tokenId][_fromAccount] -= _amounts[i];
			}
		}

		emit TransferBatch(_operator, _fromAccount, address(0), _tokenIds, _amounts);
	}

	/**
	 * @notice transfer tokens between given addresses
	 * @param _operator executor of transfer
	 * @param _fromAccount sender of tokens
	 * @param _toAccount receiver of tokens
	 * @param _tokenId token ID
	 * @param _amount quantity of tokens to transfer
	 * @param _data data payload
	 */
	function safeTransfer(
		address _operator,
		address _fromAccount,
		address _toAccount,
		uint256 _tokenId,
		uint256 _amount,
		bytes memory _data
	) internal {
		if (_toAccount == address(0)) revert LibERC1155__TransferToZeroAddress();

		uint256[] memory tokenIds = _asSingletonArray(_tokenId);
		uint256[] memory amounts = _asSingletonArray(_amount);

		_beforeTokenTransfer(_operator, _fromAccount, _toAccount, tokenIds, amounts, _data);

		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		_whenTokenNotPaused(e1155s, _tokenId);

		uint256 senderBalance = e1155s.balances[_tokenId][_fromAccount];

		if (_amount > senderBalance) revert LibERC1155__TransferExceedsBalance();
		checkAllowance(_operator, _fromAccount, _tokenId, _amount);

		unchecked {
			e1155s.balances[_tokenId][_fromAccount] = senderBalance - _amount;
			if (_operator != _fromAccount) {
				if (e1155s.operatorSpendingLimitEnabled[_tokenId]) {
					e1155s.allowances[_fromAccount][_operator][_tokenId] = e1155s.allowances[_fromAccount][_operator][_tokenId] - _amount;
				}
			}
		}

		e1155s.balances[_tokenId][_toAccount] += _amount;

		emit TransferSingle(_operator, _fromAccount, _toAccount, _tokenId, _amount);

		_afterTokenTransfer(_operator, _fromAccount, _toAccount, tokenIds, amounts, _data);

		_doSafeTransferAcceptanceCheck(_operator, _fromAccount, _toAccount, _tokenId, _amount, _data);
	}

	/**
	 * @notice transfer batch of tokens between given addresses
	 * @param _operator executor of transfer
	 * @param _fromAccount sender of tokens
	 * @param _toAccount receiver of tokens
	 * @param _tokenIds token IDs
	 * @param _amounts quantities of tokens to transfer
	 * @param _data data payload
	 */
	function safeTransferBatch(
		address _operator,
		address _fromAccount,
		address _toAccount,
		uint256[] memory _tokenIds,
		uint256[] memory _amounts,
		bytes memory _data
	) internal {
		if (_toAccount == address(0)) revert LibERC1155__TransferToZeroAddress();
		if (_tokenIds.length != _amounts.length) revert LibERC1155__ArrayLengthMismatch();

		_beforeTokenTransfer(_operator, _fromAccount, _toAccount, _tokenIds, _amounts, _data);

		ERC1155Storage storage e1155s = LibERC1155Storage.layout();

		checkAllowanceBach(_operator, _fromAccount, _tokenIds, _amounts);

		for (uint256 i; i < _tokenIds.length; ) {
			uint256 tokenId = _tokenIds[i];
			uint256 amount = _amounts[i];

			unchecked {
				_whenTokenNotPaused(e1155s, tokenId);

				uint256 senderBalance = e1155s.balances[tokenId][_fromAccount];

				if (amount > senderBalance) revert LibERC1155__TransferExceedsBalance();

				e1155s.balances[tokenId][_fromAccount] = senderBalance - amount;

				if (_operator != _fromAccount) {
					if (e1155s.operatorSpendingLimitEnabled[tokenId]) {
						e1155s.allowances[_fromAccount][_operator][tokenId] = e1155s.allowances[_fromAccount][_operator][tokenId] - amount;
					}
				}

				i++;
			}

			// balance increase cannot be unchecked because ERC1155Base neither tracks nor validates a totalSupply
			e1155s.balances[tokenId][_toAccount] += amount;
		}

		emit TransferBatch(_operator, _fromAccount, _toAccount, _tokenIds, _amounts);

		_afterTokenTransfer(_operator, _fromAccount, _toAccount, _tokenIds, _amounts, _data);

		_doSafeBatchTransferAcceptanceCheck(_operator, _fromAccount, _toAccount, _tokenIds, _amounts, _data);
	}

	/**
	 * @notice Enable or disable approval for a third party ("operator") to manage all of the caller's tokens.
	 * @dev MUST emit the ApprovalForAll event on success.
	 * @param _account The owner of the tokens
	 * @param _operator Address to add to the set of authorized operators
	 * @param _approved True if the operator is approved, false to revoke approval
	 */
	function setApprovalForAll(address _account, address _operator, bool _approved) internal {
		if (_account == _operator) revert LibERC1155__SelfApproval();
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		e1155s.operatorApprovals[_account][_operator] = _approved;
		emit ApprovalForAll(_account, _operator, _approved);
	}

	/**
	 * @notice Queries the approval status of an operator for a given owner.
	 * @param _account The owner of the tokens
	 * @param _operator Address of authorized operator
	 * @return True if the operator is approved, false if not
	 */
	function isApprovedForAll(address _account, address _operator) internal view returns (bool) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		return e1155s.operatorApprovals[_account][_operator];
	}

	/************************************************************************************************************
	 *
	 * IERC1155Receiver
	 *
	 ************************************************************************************************************/
	bytes4 internal constant ERC1155_ACCEPTED = 0xf23a6e61; // bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
	bytes4 internal constant ERC1155_BATCH_ACCEPTED = 0xbc197c81; // bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))

	function onERC1155Received(
		address _operator,
		address _from,
		uint256 _id,
		uint256 _value,
		bytes calldata _data
	) internal returns (bytes4) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		ERC1155ReceiverStorage storage receivedData = e1155s.receivedTokens[e1155s.receivedTokensLength];
		receivedData.operator = _operator;
		receivedData.from = _from;
		receivedData.ids = _asSingletonArray(_id);
		receivedData.values = _asSingletonArray(_value);
		receivedData.data = _data;
		e1155s.receivedTokensLength++;

		// if (shouldReject == true) {
		// 	revert("onERC1155Received: transfer not accepted");
		// } else {
		// 	return ERC1155_ACCEPTED;
		// }
		return ERC1155_ACCEPTED;
	}

	function onERC1155BatchReceived(
		address _operator,
		address _from,
		uint256[] calldata _ids,
		uint256[] calldata _values,
		bytes calldata _data
	) internal returns (bytes4) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		ERC1155ReceiverStorage storage receivedData = e1155s.receivedTokens[e1155s.receivedTokensLength];
		receivedData.operator = _operator;
		receivedData.from = _from;
		receivedData.ids = _ids;
		receivedData.values = _values;
		receivedData.data = _data;
		e1155s.receivedTokensLength++;
		return ERC1155_BATCH_ACCEPTED;
	}

	/************************************************************************************************************
	 *
	 * IERC1155Allowance
	 *
	 ************************************************************************************************************/

	function isOperatorSpendingLimitEnabled(uint256 _tokenId) internal view returns (bool) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		return e1155s.operatorSpendingLimitEnabled[_tokenId];
	}

	function setOperatorSpendingLimitEnabled(uint256 _tokenId, bool _enabled) internal {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		e1155s.operatorSpendingLimitEnabled[_tokenId] = _enabled;
	}

	/**
	 * @notice Allow other accounts/contracts to spend tokens on behalf of msg.sender
	 * @dev MUST emit Approval event on success.
	 * To minimize the risk of the approve/transferFrom attack vector (see https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/), this function will throw if the current approved allowance does not equal the expected _currentValue, unless _value is 0.
	 * @param _owner Address of token owner
	 * @param _operator Address to approve, _operator will ba able to send token
	 * @param _tokenId ID of the Token
	 * @param _currentValue Expected current value of approved allowance.
	 * @param _newValue Allowance amount
	 */
	function approve(address _owner, address _operator, uint256 _tokenId, uint256 _currentValue, uint256 _newValue) internal {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		require(e1155s.allowances[_owner][_operator][_tokenId] == _currentValue, "Current value mismatch");
		e1155s.allowances[_owner][_operator][_tokenId] = _newValue;

		emit Approval(_owner, _operator, _tokenId, _currentValue, _newValue);
	}

	/**
	 * @notice Queries the spending limit approved for an account
	 * @param _owner The owner allowing the spending
	 * @param _operator The address allowed to spend.
	 * @param _tokenId ID of the Token
	 * @return The _operator's allowed spending balance of the Token requested
	 */
	function allowance(address _owner, address _operator, uint256 _tokenId) internal view returns (uint256) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		return e1155s.allowances[_owner][_operator][_tokenId];
	}

	function checkAllowance(address _operator, address _fromAccount, uint256 _tokenId, uint256 _value) internal view {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		if (_fromAccount != _operator) {
			if (!e1155s.operatorApprovals[_fromAccount][_operator]) {
				revert LibERC1155__NotOwnerOrApproved();
			}
			if (e1155s.operatorSpendingLimitEnabled[_tokenId] && e1155s.allowances[_fromAccount][_operator][_tokenId] < _value) {
				revert LibERC1155__NotOwnerOrApprovedLimit();
			}
		}
	}

	function checkAllowanceBach(
		address _operator,
		address _fromAccount,
		uint256[] memory _tokenIds,
		uint256[] memory _amounts
	) internal view {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		if (_fromAccount != _operator) {
			if (!e1155s.operatorApprovals[_fromAccount][_operator]) {
				revert LibERC1155__NotOwnerOrApproved();
			}

			if (_tokenIds.length != _amounts.length) revert LibERC1155__ArrayLengthMismatch();

			for (uint256 i; i < _tokenIds.length; ) {
				unchecked {
					uint256 tokenId = _tokenIds[i];
					uint256 amount = _amounts[i];
					if (e1155s.operatorSpendingLimitEnabled[tokenId] && e1155s.allowances[_fromAccount][_operator][tokenId] < amount) {
						revert LibERC1155__NotOwnerOrApprovedLimit();
					}
					i++;
				}
			}
		}
	}

	/************************************************************************************************************
	 *
	 * IERC1155Metadata
	 *
	 ************************************************************************************************************/

	/**
	 * @notice Query global metadata URI, can contain {id}, client will replace with a valid token id
	 */
	function getUri() internal view returns (string memory) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		return e1155s.uri;
	}

	/**
	 * @notice set global metadata URI, can contain {id}, client will
	 * @param _URI global URI
	 */
	function setURI(string memory _URI) internal {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		e1155s.uri = _URI;
	}

	function getTokenBaseUri() internal view returns (string memory) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		return e1155s.baseURI;
	}

	/**
	 * @notice set base metadata URI
	 * @dev base URI is a non-standard feature adapted from the ERC721 specification
	 * @param _baseURI base URI
	 */
	function setTokenBaseURI(string memory _baseURI) internal {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		e1155s.baseURI = _baseURI;
	}

	function getTokenUri(uint256 _tokenId) internal view returns (string memory) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		return e1155s.tokenURIs[_tokenId];
	}

	/**
	 * @notice set pre-token metadata URI
	 * @param _tokenId token whose metadata URI to set
	 * @param _tokenURI per-token URI
	 */
	function setTokenURI(uint256 _tokenId, string memory _tokenURI) internal {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		e1155s.tokenURIs[_tokenId] = _tokenURI;
		emit URI(_tokenURI, _tokenId);
	}

	/**
	 * This implementation returns the concatenation of the `_baseURI`
	 * and the token-specific uri if the latter is set
	 *
	 * This enables the following behaviors:
	 *
	 * - if `_tokenURIs[tokenId]` is set, then the result is the concatenation
	 *   of `_baseURI` and `_tokenURIs[tokenId]`
	 *
	 * - if `_tokenURIs[tokenId]` is NOT set then we fallback to the defaut URI
	 *   which contains `ERC1155.uri`;
	 */
	function getUri(uint256 tokenId) internal view returns (string memory) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		string memory tokenURI = e1155s.tokenURIs[tokenId];

		// If token URI is set, concatenate base URI and tokenURI (via abi.encodePacked).
		return bytes(tokenURI).length > 0 ? string(abi.encodePacked(e1155s.baseURI, tokenURI)) : e1155s.uri;
	}

	/************************************************************************************************************
	 *
	 * IERC1155Enumerable
	 *
	 ************************************************************************************************************/

	/**
	 * @notice query total minted supply of given token
	 * @param _tokenId token id to query
	 * @return token supply
	 */
	function totalSupply(uint256 _tokenId) internal view returns (uint256) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		return e1155s.totalSupply[_tokenId];
	}

	/**
	 * @notice query total number of holders for given token
	 * @param id token id to query
	 * @return quantity of holders
	 */
	function totalHolders(uint256 id) internal view returns (uint256) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		return e1155s.accountsByToken[id].length();
	}

	/**
	 * @notice query holders of given token
	 * @param _tokenId token id to query
	 * @return list of holder addresses
	 */
	function accountsByToken(uint256 _tokenId) internal view returns (address[] memory) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		EnumerableSet.AddressSet storage accounts = e1155s.accountsByToken[_tokenId];

		address[] memory addresses = new address[](accounts.length());

		unchecked {
			for (uint256 i; i < accounts.length(); i++) {
				addresses[i] = accounts.at(i);
			}
		}

		return addresses;
	}

	/**
	 * @notice query tokens held by given address
	 * @param _account address to query
	 * @return list of token ids
	 */
	function tokensByAccount(address _account) internal view returns (uint256[] memory) {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		EnumerableSet.UintSet storage tokens = e1155s.tokensByAccount[_account];

		uint256[] memory ids = new uint256[](tokens.length());

		unchecked {
			for (uint256 i; i < tokens.length(); i++) {
				ids[i] = tokens.at(i);
			}
		}

		return ids;
	}

	/************************************************************************************************************
	 *
	 * IERC1155Pausable
	 *
	 ************************************************************************************************************/
	function _whenNotPaused(ERC1155Storage storage e1155s) internal view {
		require(!e1155s.paused, "All token is paused!");
	}

	function _whenTokenNotPaused(ERC1155Storage storage e1155s, uint256 _tokenId) internal view {
		_whenNotPaused(e1155s);
		require(!e1155s.pausedToken[_tokenId], "Token is paused!");
	}

	function whenNotPaused() internal view {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		_whenNotPaused(e1155s);
	}

	function whenTokenNotPaused(uint256 _tokenId) internal view {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		_whenTokenNotPaused(e1155s, _tokenId);
	}

	function pauseAllToken(address _operator) internal {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		require(!e1155s.paused, "All tokens are already paused");
		e1155s.paused = true;
		emit AllTokenPaused(_operator);
	}

	function unpauseAllToken(address _operator) internal {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		require(e1155s.paused, "All tokens are not paused yet");
		e1155s.paused = false;
		emit AllTokenUnpaused(_operator);
	}

	function pauseToken(address _operator, uint256 _tokenId) internal {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		require(!e1155s.pausedToken[_tokenId], "Token is already paused");
		e1155s.pausedToken[_tokenId] = true;
		emit TokenPaused(_operator, _tokenId);
	}

	function unpauseToken(address _operator, uint256 _tokenId) internal {
		ERC1155Storage storage e1155s = LibERC1155Storage.layout();
		require(e1155s.pausedToken[_tokenId], "Token is not paused yet");
		e1155s.pausedToken[_tokenId] = false;
		emit TokenUnpaused(_operator, _tokenId);
	}

	/************************************************************************************************************
	 *
	 * Library internal helper functions
	 *
	 ************************************************************************************************************/

	/**
	 * @notice revert if applicable transfer recipient is not valid ERC1155Receiver
	 * @param _operator executor of transfer
	 * @param _fromAccount sender of tokens
	 * @param _toAccount receiver of tokens
	 * @param _tokenId token ID
	 * @param _amount quantity of tokens to transfer
	 * @param _data data payload
	 */
	function _doSafeTransferAcceptanceCheck(
		address _operator,
		address _fromAccount,
		address _toAccount,
		uint256 _tokenId,
		uint256 _amount,
		bytes memory _data
	) internal {
		if (_toAccount.isContract()) {
			try IERC1155Receiver(_toAccount).onERC1155Received(_operator, _fromAccount, _tokenId, _amount, _data) returns (
				bytes4 response
			) {
				if (response != IERC1155Receiver.onERC1155Received.selector) revert LibERC1155__ERC1155ReceiverRejected();
			} catch Error(string memory reason) {
				revert(reason);
			} catch {
				revert LibERC1155__ERC1155ReceiverNotImplemented();
			}
		}
	}

	/**
	 * @notice revert if applicable transfer recipient is not valid ERC1155Receiver
	 * @param _operator executor of transfer
	 * @param _fromAccount sender of tokens
	 * @param _toAccount receiver of tokens
	 * @param _tokenIds token IDs
	 * @param _amounts quantities of tokens to transfer
	 * @param _data data payload
	 */
	function _doSafeBatchTransferAcceptanceCheck(
		address _operator,
		address _fromAccount,
		address _toAccount,
		uint256[] memory _tokenIds,
		uint256[] memory _amounts,
		bytes memory _data
	) private {
		if (_toAccount.isContract()) {
			try IERC1155Receiver(_toAccount).onERC1155BatchReceived(_operator, _fromAccount, _tokenIds, _amounts, _data) returns (
				bytes4 response
			) {
				if (response != IERC1155Receiver.onERC1155BatchReceived.selector) revert LibERC1155__ERC1155ReceiverRejected();
			} catch Error(string memory reason) {
				revert(reason);
			} catch {
				revert LibERC1155__ERC1155ReceiverNotImplemented();
			}
		}
	}

	function _asSingletonArray(uint256 element) internal pure returns (uint256[] memory) {
		uint256[] memory array = new uint256[](1);
		array[0] = element;
		return array;
	}

	/**
	 * @notice ERC1155 hook, called before all transfers including mint and burn
	 * The same hook is called on both single and batched variants. For single
	 * transfers, the length of the `ids` and `amounts` arrays will be 1.
	 * Calling conditions (for each `id` and `amount` pair):
	 * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens of token type `id` will be  transferred to `to`.
	 * - When `from` is zero, `amount` tokens of token type `id` will be minted for `to`.
	 * - when `to` is zero, `amount` of ``from``'s tokens of token type `id` will be burned.
	 * - `from` and `to` are never both zero.
	 * - `ids` and `amounts` have the same, non-zero length.
	 * @param _operator executor of transfer
	 * @param _fromAccount sender of tokens
	 * @param _toAccount receiver of tokens
	 * @param _tokenIds token IDs
	 * @param _amounts quantities of tokens to transfer
	 * @param _data data payload
	 */
	function _beforeTokenTransfer(
		address _operator,
		address _fromAccount,
		address _toAccount,
		uint256[] memory _tokenIds,
		uint256[] memory _amounts,
		bytes memory _data
	) internal {
		if (_fromAccount != _toAccount) {
			ERC1155Storage storage e1155s = LibERC1155Storage.layout();

			mapping(uint256 => EnumerableSet.AddressSet) storage tokenAccounts = e1155s.accountsByToken;

			EnumerableSet.UintSet storage fromAccountTokens = e1155s.tokensByAccount[_fromAccount];
			EnumerableSet.UintSet storage toAccountTokens = e1155s.tokensByAccount[_toAccount];

			for (uint256 i; i < _tokenIds.length; ) {
				uint256 amount = _amounts[i];

				if (amount > 0) {
					uint256 id = _tokenIds[i];

					if (_fromAccount == address(0)) {
						e1155s.totalSupply[id] += amount;
					} else if (balanceOf(_fromAccount, id) == amount) {
						tokenAccounts[id].remove(_fromAccount);
						fromAccountTokens.remove(id);
					}

					if (_toAccount == address(0)) {
						e1155s.totalSupply[id] -= amount;
					} else if (balanceOf(_toAccount, id) == 0) {
						tokenAccounts[id].add(_toAccount);
						toAccountTokens.add(id);
					}
				}

				unchecked {
					i++;
				}
			}
		}
		LibERC1155Customization._beforeTokenTransfer(_operator, _fromAccount, _toAccount, _tokenIds, _amounts, _data);
	}

	/**
	 * @notice ERC1155 hook, called after all transfers including mint and burn
	 * The same hook is called on both single and batched variants. For single
	 * transfers, the length of the `id` and `amount` arrays will be 1.
	 * Calling conditions (for each `id` and `amount` pair):
	 * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens of token type `id` will be  transferred to `to`.
	 * - When `from` is zero, `amount` tokens of token type `id` will be minted for `to`.
	 * - when `to` is zero, `amount` of ``from``'s tokens of token type `id` will be burned.
	 * - `from` and `to` are never both zero.
	 * - `ids` and `amounts` have the same, non-zero length.
	 * @param _operator executor of transfer
	 * @param _fromAccount sender of tokens
	 * @param _toAccount receiver of tokens
	 * @param _tokenIds token IDs
	 * @param _amounts quantities of tokens to transfer
	 * @param _data data payload
	 */
	function _afterTokenTransfer(
		address _operator,
		address _fromAccount,
		address _toAccount,
		uint256[] memory _tokenIds,
		uint256[] memory _amounts,
		bytes memory _data
	) internal {
		LibERC1155Customization._afterTokenTransfer(_operator, _fromAccount, _toAccount, _tokenIds, _amounts, _data);
	}
}


// File: contracts/base/ERC1155/base/LibERC1155Storage.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { EnumerableSet } from "../../../utils/EnumerableSet.sol";

struct ERC1155ReceiverStorage {
	bytes data;
	address operator;
	address from;
	uint256[] ids;
	uint256[] values;
}

struct ERC1155Storage {
	mapping(uint256 => mapping(address => uint256)) balances; // Mapping from token ID to account balances
	mapping(address => mapping(address => bool)) operatorApprovals; // Mapping from account to operator approvals
	mapping(uint256 => bool) operatorSpendingLimitEnabled;
	mapping(address => mapping(address => mapping(uint256 => uint256))) allowances;
	mapping(uint256 => uint256) totalSupply;
	mapping(uint256 => EnumerableSet.AddressSet) accountsByToken;
	mapping(address => EnumerableSet.UintSet) tokensByAccount;
	string uri; // Used as the URI for all token types by relying on ID substitution, e.g. https://token-cdn-domain/{id}.json
	string baseURI; // Optional base URI, e.g. ipfs://53453534
	mapping(uint256 => string) tokenURIs; // Optional mapping for token URIs, e.g. 4236464216781, so tokenURI will be: ipfs://53453534/4236464216781
	bool paused;
	mapping(uint256 => bool) pausedToken;
	uint256 receivedTokensLength;
	mapping(uint256 => ERC1155ReceiverStorage) receivedTokens;
}

library LibERC1155Storage {
	bytes32 internal constant ERC1155_STORAGE_SLOT = keccak256("usmart.contracts.erc1155-base.storage.v1");

	function layout() internal pure returns (ERC1155Storage storage e1155s_) {
		bytes32 position = ERC1155_STORAGE_SLOT;
		assembly {
			e1155s_.slot := position
		}
	}
}


// File: contracts/base/ERC1155/customization/LibERC1155Customization.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import "../../TokenRestriction/LibTokenRestriction.sol";
import "../../TokenPNL/LibTokenPNL.sol";

import "../../../ArexaPlatform/Platform/LibArexaPlatform.sol";

library LibERC1155Customization {
	/**
	 * @notice ERC1155 hook, called before all transfers including mint and burn
	 * The same hook is called on both single and batched variants. For single
	 * transfers, the length of the `ids` and `amounts` arrays will be 1.
	 * Calling conditions (for each `id` and `amount` pair):
	 * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens of token type `id` will be  transferred to `to`.
	 * - When `from` is zero, `amount` tokens of token type `id` will be minted for `to`.
	 * - when `to` is zero, `amount` of ``from``'s tokens of token type `id` will be burned.
	 * - `from` and `to` are never both zero.
	 * - `ids` and `amounts` have the same, non-zero length.
	 *  param_operator executor of transfer
	 * @param _fromAccount sender of tokens
	 *  param_toAccount receiver of tokens
	 * @param _tokenIds token IDs
	 * @param _amounts quantities of tokens to transfer
	 *  param _data data payload
	 */
	function _beforeTokenTransfer(
		address, //_operator,
		address _fromAccount,
		address, //_toAccount,
		uint256[] memory _tokenIds,
		uint256[] memory _amounts,
		bytes memory //_data
	) internal view {
		if (_fromAccount != address(0)) {
			LibTokenRestriction.checkRestrictions(_fromAccount, _tokenIds, _amounts);
		}
	}

	/**
	 * @notice ERC1155 hook, called after all transfers including mint and burn
	 * The same hook is called on both single and batched variants. For single
	 * transfers, the length of the `id` and `amount` arrays will be 1.
	 * Calling conditions (for each `id` and `amount` pair):
	 * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens of token type `id` will be  transferred to `to`.
	 * - When `from` is zero, `amount` tokens of token type `id` will be minted for `to`.
	 * - when `to` is zero, `amount` of ``from``'s tokens of token type `id` will be burned.
	 * - `from` and `to` are never both zero.
	 * - `ids` and `amounts` have the same, non-zero length.
	 * _operator executor of transfer
	 * @param _fromAccount sender of tokens
	 * @param _toAccount receiver of tokens
	 * @param _tokenIds token IDs
	 * @param _amounts quantities of tokens to transfer
	 * _data data payload
	 */
	function _afterTokenTransfer(
		address, //_operator
		address _fromAccount,
		address _toAccount,
		uint256[] memory _tokenIds,
		uint256[] memory _amounts,
		bytes memory //_data
	) internal {
		if (_fromAccount != address(0)) {
			LibTokenRestriction.recalcRestrictions(_fromAccount, _tokenIds, _amounts, 0);
		}

		if (_toAccount != address(0)) {
			LibTokenRestriction.recalcRestrictions(_toAccount, _tokenIds, _amounts, 1);
		}

		for (uint256 i; i < _tokenIds.length; ) {
			LibTokenPNL.refreshDivident(address(LibArexaPlatform.getPayingToken()), _tokenIds[i], _fromAccount, _toAccount, _amounts[i]);

			unchecked {
				i++;
			}
		}
	}
}


// File: contracts/base/ERC1155/IERC1155.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

/**
 * @dev Required interface of an ERC1155 compliant contract, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1155.
 */
interface IERC1155 {
	/**
	 * @dev Either `TransferSingle` or `TransferBatch` MUST emit when tokens are transferred, including zero value transfers as well as minting or burning (see "Safe Transfer Rules" section of the standard).
	 * The `_operator` argument MUST be the address of an account/contract that is approved to make the transfer (SHOULD be msg.sender).
	 * The `_from` argument MUST be the address of the holder whose balance is decreased.
	 * The `_to` argument MUST be the address of the recipient whose balance is increased.
	 * The `_id` argument MUST be the token type being transferred.
	 * The `_value` argument MUST be the number of tokens the holder balance is decreased by and match what the recipient balance is increased by.
	 * When minting/creating tokens, the `_from` argument MUST be set to `0x0` (i.e. zero address).
	 * When burning/destroying tokens, the `_to` argument MUST be set to `0x0` (i.e. zero address).
	 */
	event TransferSingle(address indexed _operator, address indexed _from, address indexed _to, uint256 _id, uint256 _value);

	/**
	 * @dev Either `TransferSingle` or `TransferBatch` MUST emit when tokens are transferred, including zero value transfers as well as minting or burning (see "Safe Transfer Rules" section of the standard).
	 * The `_operator` argument MUST be the address of an account/contract that is approved to make the transfer (SHOULD be msg.sender).
	 * The `_from` argument MUST be the address of the holder whose balance is decreased.
	 * The `_to` argument MUST be the address of the recipient whose balance is increased.
	 * The `_ids` argument MUST be the list of tokens being transferred.
	 * The `_values` argument MUST be the list of number of tokens (matching the list and order of tokens specified in _ids) the holder balance is decreased by and match what the recipient balance is increased by.
	 * When minting/creating tokens, the `_from` argument MUST be set to `0x0` (i.e. zero address).
	 * When burning/destroying tokens, the `_to` argument MUST be set to `0x0` (i.e. zero address).
	 */
	event TransferBatch(address indexed _operator, address indexed _from, address indexed _to, uint256[] _ids, uint256[] _values);

	/**
	 * @dev MUST emit when approval for a second party/operator address to manage all tokens for an owner address is enabled or disabled (absence of an event assumes disabled).
	 */
	event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);

	/**
	 * @dev MUST emit when the URI is updated for a token ID.
	 * URIs are defined in RFC 3986.
	 * The URI MUST point to a JSON file that conforms to the "ERC-1155 Metadata URI JSON Schema".
	 */
	event URI(string _value, uint256 indexed _id);

	/**
	 * @notice Transfers `_value` amount of an `_id` from the `_from` address to the `_to` address specified (with safety call).
	 * @dev Caller must be approved to manage the tokens being transferred out of the `_from` account (see "Approval" section of the standard).
	 * MUST revert if `_to` is the zero address.
	 * MUST revert if balance of holder for token `_id` is lower than the `_value` sent.
	 * MUST revert on any other error.
	 * MUST emit the `TransferSingle` event to reflect the balance change (see "Safe Transfer Rules" section of the standard).
	 * After the above conditions are met, this function MUST check if `_to` is a smart contract (e.g. code size > 0). If so, it MUST call `onERC1155Received` on `_to` and act appropriately (see "Safe Transfer Rules" section of the standard).
	 * @param _from Source address
	 * @param _to Target address
	 * @param _id ID of the token type
	 * @param _value Transfer amount
	 * @param _data Additional data with no specified format, MUST be sent unaltered in call to `onERC1155Received` on `_to`
	 */
	function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data) external;

	/**
	 * @notice Transfers `_values` amount(s) of `_ids` from the `_from` address to the `_to` address specified (with safety call).
	 * @dev Caller must be approved to manage the tokens being transferred out of the `_from` account (see "Approval" section of the standard).
	 * MUST revert if `_to` is the zero address.
	 * MUST revert if length of `_ids` is not the same as length of `_values`.
	 * MUST revert if any of the balance(s) of the holder(s) for token(s) in `_ids` is lower than the respective amount(s) in `_values` sent to the recipient.
	 * MUST revert on any other error.
	 * MUST emit `TransferSingle` or `TransferBatch` event(s) such that all the balance changes are reflected (see "Safe Transfer Rules" section of the standard).
	 * Balance changes and events MUST follow the ordering of the arrays (_ids[0]/_values[0] before _ids[1]/_values[1], etc).
	 * After the above conditions for the transfer(s) in the batch are met, this function MUST check if `_to` is a smart contract (e.g. code size > 0). If so, it MUST call the relevant `ERC1155TokenReceiver` hook(s) on `_to` and act appropriately (see "Safe Transfer Rules" section of the standard).
	 * @param _from Source address
	 * @param _to Target address
	 * @param _ids IDs of each token type (order and length must match _values array)
	 * @param _values Transfer amounts per token type (order and length must match _ids array)
	 * @param _data Additional data with no specified format, MUST be sent unaltered in call to the `ERC1155TokenReceiver` hook(s) on `_to`
	 */
	function safeBatchTransferFrom(
		address _from,
		address _to,
		uint256[] calldata _ids,
		uint256[] calldata _values,
		bytes calldata _data
	) external;

	/**
	 * @notice Get the balance of an account's tokens.
	 * @param _owner The address of the token holder
	 * @param _id ID of the token
	 * @return The _owner's balance of the token type requested
	 */
	function balanceOf(address _owner, uint256 _id) external view returns (uint256);

	/**
	 * @notice Get the balance of multiple account/token pairs
	 * @param _owners The addresses of the token holders
	 * @param _ids ID of the tokens
	 * @return The _owner's balance of the token types requested (i.e. balance for each (owner, id) pair)
	 */
	function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids) external view returns (uint256[] memory);

	/**
	 * @notice Enable or disable approval for a third party ("operator") to manage all of the caller's tokens.
	 * @dev MUST emit the ApprovalForAll event on success.
	 * @param _operator Address to add to the set of authorized operators
	 * @param _approved True if the operator is approved, false to revoke approval
	 */
	function setApprovalForAll(address _operator, bool _approved) external;

	/**
	 * @notice Queries the approval status of an operator for a given owner.
	 * @param _owner The owner of the tokens
	 * @param _operator Address of authorized operator
	 * @return True if the operator is approved, false if not
	 */
	function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}


// File: contracts/base/ERC1155/IERC1155Receiver.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

/**
 * https://eips.ethereum.org/EIPS/eip-1155.
 */
interface IERC1155Receiver {
	/**
	 * @notice Handle the receipt of a single ERC1155 token type.
	 * @dev An ERC1155-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeTransferFrom` after the balance has been updated.
	 * This function MUST return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` (i.e. 0xf23a6e61) if it accepts the transfer.
	 * This function MUST revert if it rejects the transfer.
	 * Return of any other value than the prescribed keccak256 generated value MUST result in the transaction being reverted by the caller.
	 * @param _operator The address which initiated the transfer (i.e. msg.sender)
	 * @param _from The address which previously owned the token
	 * @param _id The ID of the token being transferred
	 * @param _value The amount of tokens being transferred
	 * @param _data Additional data with no specified format
	 * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
	 */
	function onERC1155Received(
		address _operator,
		address _from,
		uint256 _id,
		uint256 _value,
		bytes calldata _data
	) external returns (bytes4);

	/**
	 * @notice Handle the receipt of multiple ERC1155 token types.
	 * @dev An ERC1155-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeBatchTransferFrom` after the balances have been updated.
	 * This function MUST return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` (i.e. 0xbc197c81) if it accepts the transfer(s).
	 * This function MUST revert if it rejects the transfer(s).
	 * Return of any other value than the prescribed keccak256 generated value MUST result in the transaction being reverted by the caller.
	 * @param _operator The address which initiated the batch transfer (i.e. msg.sender)
	 * @param _from The address which previously owned the token
	 * @param _ids An array containing ids of each token being transferred (order and length must match _values array)
	 * @param _values An array containing amounts of each token being transferred (order and length must match _ids array)
	 * @param _data Additional data with no specified format
	 * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
	 */
	function onERC1155BatchReceived(
		address _operator,
		address _from,
		uint256[] calldata _ids,
		uint256[] calldata _values,
		bytes calldata _data
	) external returns (bytes4);
}


// File: contracts/base/ERC20/IERC20.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

/**
 * @title ERC20 interface
 * @dev see https://eips.ethereum.org/EIPS/eip-20
 */
interface IERC20 {
	event Transfer(address indexed from, address indexed to, uint256 value);

	event Approval(address indexed owner, address indexed spender, uint256 value);

	/**
	 * @notice query the total minted token supply
	 * @return token supply
	 */
	function totalSupply() external view returns (uint256);

	/**
	 * @notice query the token balance of given account
	 * @param account address to query
	 * @return token balance
	 */
	function balanceOf(address account) external view returns (uint256);

	/**
	 * @notice query the allowance granted from given holder to given spender
	 * @param holder approver of allowance
	 * @param spender recipient of allowance
	 * @return token allowance
	 */
	function allowance(address holder, address spender) external view returns (uint256);

	/**
	 * @notice grant approval to spender to spend tokens
	 * @dev prefer ERC20Extended functions to avoid transaction-ordering vulnerability (see https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729)
	 * @param spender recipient of allowance
	 * @param amount quantity of tokens approved for spending
	 * @return success status (always true; otherwise function should revert)
	 */
	function approve(address spender, uint256 amount) external returns (bool);

	/**
	 * @notice transfer tokens to given recipient
	 * @param recipient beneficiary of token transfer
	 * @param amount quantity of tokens to transfer
	 * @return success status (always true; otherwise function should revert)
	 */
	function transfer(address recipient, uint256 amount) external returns (bool);

	/**
	 * @notice transfer tokens to given recipient on behalf of given holder
	 * @param holder holder of tokens prior to transfer
	 * @param recipient beneficiary of token transfer
	 * @param amount quantity of tokens to transfer
	 * @return success status (always true; otherwise function should revert)
	 */
	function transferFrom(address holder, address recipient, uint256 amount) external returns (bool);
}


// File: contracts/base/ERC20/metadata/IERC20Metadata.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

/**
 * @title ERC20 metadata interface
 */
interface IERC20Metadata {
	/**
	 * @notice return token name
	 * @return token name
	 */
	function name() external view returns (string memory);

	/**
	 * @notice return token symbol
	 * @return token symbol
	 */
	function symbol() external view returns (string memory);

	/**
	 * @notice return token decimals, generally used only for display purposes
	 * @return token decimals
	 */
	function decimals() external view returns (uint8);
}


// File: contracts/base/Shared/ProtectedCall.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { LibDiamond } from "../Diamond/LibDiamond.sol";

contract CallProtection {
	modifier protectedCall() {
		require(address(this) == LibDiamond.getDiamondAddress(), "NOT_ALLOWED");
		_;
	}
}


// File: contracts/base/TargetedPausable/LibTargetedPausable.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import "./LibTargetedPausableStorage.sol";

library LibTargetedPausable {
	error TargetedPausable__TargetedPaused();
	error TargetedPausable__NotTargetedPaused();

	//target: what was paused
	//account: the operator who is paused the target
	event TargetedPaused(bytes32 indexed target, address indexed account);

	//target: what was unpaused
	//account: the operator who is unpaused the target
	event TargetedUnpaused(bytes32 target, address indexed account);

	function _whenNotPaused(bytes32 _target) internal view {
		if (LibTargetedPausable._paused(_target)) revert TargetedPausable__TargetedPaused();
	}

	function _whenPaused(bytes32 _target) internal view {
		if (!LibTargetedPausable._paused(_target)) revert TargetedPausable__NotTargetedPaused();
	}

	function _paused(bytes32 _target) internal view returns (bool paused_) {
		paused_ = LibTargetedPausableStorage.layout().paused[_target];
	}

	function _pause(bytes32 _target, address _operator) internal {
		TargetedPausableStorage storage ps = LibTargetedPausableStorage.layout();
		if (ps.paused[_target]) revert TargetedPausable__TargetedPaused();
		ps.paused[_target] = true;
		emit TargetedPaused(_target, _operator);
	}

	function _unpause(bytes32 _target, address _operator) internal {
		TargetedPausableStorage storage ps = LibTargetedPausableStorage.layout();
		if (!ps.paused[_target]) revert TargetedPausable__NotTargetedPaused();
		ps.paused[_target] = false;
		delete ps.paused[_target];
		emit TargetedUnpaused(_target, _operator);
	}
}


// File: contracts/base/TargetedPausable/LibTargetedPausableStorage.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { EnumerableSet } from "../../utils/EnumerableSet.sol";

struct TargetedPausableStorage {
	mapping(bytes32 => bool) paused;
}

library LibTargetedPausableStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("usmart.common.targeted-pausable.storage.v1");

	function layout() internal pure returns (TargetedPausableStorage storage layout_) {
		bytes32 position = STORAGE_SLOT;
		assembly {
			layout_.slot := position
		}
	}
}


// File: contracts/base/TargetedPausable/ModifierPausable.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { LibTargetedPausable } from "./LibTargetedPausable.sol";

abstract contract ModifierPausable {
	//
	modifier whenNotPaused(bytes32 target) {
		LibTargetedPausable._whenNotPaused(target);
		_;
	}

	modifier whenPaused(bytes32 target) {
		LibTargetedPausable._whenPaused(target);
		_;
	}
}


// File: contracts/base/TokenDynamicPricing/LibTokenDynamicPricing.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import "./LibTokenDynamicPricingStorage.sol";

import "../../utils/Math.sol";

library LibTokenDynamicPricing {
	function initialize(uint256 _tokenId, uint256 _initialQuantity, uint256 _min, uint256 _max) internal {
		TokenDynamicPricingStorage storage dynamicPricing = LibTokenDynamicPricingStorage.layout();
		DynamicPricing storage pricing = dynamicPricing.tokenDynamicPricing[_tokenId];

		pricing.isEnabled = true;
		pricing.quantity = _initialQuantity;
		pricing.k = (_min == 0) ? _initialQuantity * _initialQuantity : _initialQuantity * _initialQuantity * _min;
		pricing.min = _min; //must contain the decimals of the paying token!!!
		pricing.max = (_max == 0 || _max < _min) ? pricing.k : _max; //must contain the decimals of the paying token!!!
	}

	function _calcTotalValue(DynamicPricing storage pricing, uint256 _quantity) internal view returns (uint256) {
		require(pricing.isEnabled, "Calculation is not enabled for the token!");
		require(_quantity <= pricing.quantity, "Not enought quantity left!");
		uint256 totalValue = (((10 * _quantity * pricing.k) / (pricing.quantity * (pricing.quantity - _quantity + 1))) + 5) / 10;
		return Math.min(_quantity * pricing.max, Math.max(_quantity * pricing.min, totalValue));
	}

	function calcTotalValue(uint256 _tokenId, uint256 _quantity) internal view returns (uint256) {
		TokenDynamicPricingStorage storage dynamicPricing = LibTokenDynamicPricingStorage.layout();
		DynamicPricing storage pricing = dynamicPricing.tokenDynamicPricing[_tokenId];
		return _calcTotalValue(pricing, _quantity);
	}

	function buyQuantity(uint256 _tokenId, uint256 _quantity) internal returns (uint256) {
		TokenDynamicPricingStorage storage dynamicPricing = LibTokenDynamicPricingStorage.layout();
		DynamicPricing storage pricing = dynamicPricing.tokenDynamicPricing[_tokenId];
		uint256 totalValue = _calcTotalValue(pricing, _quantity);

		pricing.quantity = pricing.quantity - _quantity;
		pricing.totalValue = pricing.totalValue + totalValue;

		if (pricing.quantity == 0) {
			pricing.isEnabled = false;
		}

		return totalValue;
	}

	function getEnabled(uint256 _tokenId) internal view returns (bool) {
		//
		TokenDynamicPricingStorage storage dynamicPricing = LibTokenDynamicPricingStorage.layout();
		DynamicPricing storage pricing = dynamicPricing.tokenDynamicPricing[_tokenId];
		return pricing.isEnabled;
	}

	function setPricingEnabled(uint256 _tokenId, bool _enabledValue) internal {
		TokenDynamicPricingStorage storage dynamicPricing = LibTokenDynamicPricingStorage.layout();
		DynamicPricing storage pricing = dynamicPricing.tokenDynamicPricing[_tokenId];
		require(
			!_enabledValue || (_enabledValue && pricing.quantity > 0),
			"Reenable of token pricing is only availabe is there is som token left to sell!"
		);
		pricing.isEnabled = _enabledValue;
	}
}


// File: contracts/base/TokenDynamicPricing/LibTokenDynamicPricingStorage.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { EnumerableSet } from "../../utils/EnumerableSet.sol";

struct DynamicPricing {
	bool isEnabled;
	uint256 quantity;
	uint256 totalValue;
	uint256 k;
	uint256 min;
	uint256 max;
}

struct TokenDynamicPricingStorage {
	//tokenId => restriction, every token have
	mapping(uint256 => DynamicPricing) tokenDynamicPricing;
}

library LibTokenDynamicPricingStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("usmart.common.token-dynamic-pricing.storage.v1");

	function layout() internal pure returns (TokenDynamicPricingStorage storage layout_) {
		bytes32 position = STORAGE_SLOT;
		assembly {
			layout_.slot := position
		}
	}
}


// File: contracts/base/TokenPNL/LibTokenPNL.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

//import "hardhat/console.sol";

import "./LibTokenPNLStorage.sol";

library LibTokenPNL {
	function initTokenPNL(address _contract, uint256 _tokenId) internal {
		TokenPNLStorage storage tokenPNL = LibTokenPNLStorage.layout();
		Inventory storage inventory = tokenPNL.inventory[_contract][_tokenId];
		inventory.isEnabled = true;
		inventory.sumQuantity = 0;
		inventory.sumAmount = 0;
		inventory.sumPnl = 0;
	}

	function changeTotalValue(address _contract, uint256 _tokenId, int256 _amount) internal {
		TokenPNLStorage storage tokenPNL = LibTokenPNLStorage.layout();
		Inventory storage inventory = tokenPNL.inventory[_contract][_tokenId];
		if (!inventory.isEnabled) {
			return;
		}

		//because every transfer, mint and burn do like ralizing the pnl
		//and after this realizing the user can payout the collected a PNL
		//so decreasing the value can cause money loss in the contract!!!
		//if wanted full inventory feature in a distributed way: ask uSmart ;)
		require(_amount >= 0, "Pool can only increase!");

		inventory.sumAmount += _amount;
		inventory.sumPnl += _amount; //Here is the MAGIC!

		// console.log("ChangeTotalValue");
		// console.log("_tokenId", _tokenId);
		// if (inventory.sumAmount >= 0) {
		// 	console.log("inventory.sumAmount", uint256(inventory.sumAmount));
		// } else {
		// 	console.log("inventory.sumAmount -", uint256(-1 * inventory.sumAmount));
		// }

		// if (inventory.sumPnl >= 0) {
		// 	console.log("inventory.sumPnl", uint256(inventory.sumPnl));
		// } else {
		// 	console.log("inventory.sumPnl -", uint256(-1 * inventory.sumPnl));
		// }
	}

	function getInventory(
		address _contract,
		uint256 _tokenId
	) internal view returns (bool isEnabled, int256 sumQuantity, int256 sumAmount, int256 sumPnl) {
		//
		TokenPNLStorage storage tokenPNL = LibTokenPNLStorage.layout();
		Inventory storage inventory = tokenPNL.inventory[_contract][_tokenId];
		return (inventory.isEnabled, inventory.sumQuantity, inventory.sumAmount, inventory.sumPnl);
	}

	function getInventoryItem(
		address _contract,
		uint256 _tokenId,
		address _account
	) internal view returns (InventoryItem memory inventoryItem) {
		TokenPNLStorage storage tokenPNL = LibTokenPNLStorage.layout();
		Inventory storage inventory = tokenPNL.inventory[_contract][_tokenId];
		inventoryItem = inventory.divident[_account];
	}

	function _refreshDividentInternal(Inventory storage inventory, address _account, int256 _quantity) internal {
		InventoryItem storage inventoryItem = inventory.divident[_account];

		require(inventory.sumQuantity + _quantity >= 0, "Pool token quanity can't be less then zero!");
		require(inventoryItem.quantity + _quantity >= 0, "User token quanity can't be less then zero!");

		// console.log("_refreshDividentInternal");
		// console.log("account", _account);

		// if (inventory.sumQuantity >= 0) {
		// 	console.log("inventory.sumQuantity", uint256(inventory.sumQuantity));
		// } else {
		// 	console.log("inventory.sumQuantity -", uint256(-1 * inventory.sumQuantity));
		// }
		// if (inventory.sumPnl >= 0) {
		// 	console.log("inventory.sumPnl", uint256(inventory.sumPnl));
		// } else {
		// 	console.log("inventory.sumPnl -", uint256(-1 * inventory.sumPnl));
		// }

		int256 addressPnlDelta = 0;
		if (inventory.sumQuantity != 0) {
			addressPnlDelta = (inventory.sumPnl * _quantity) / inventory.sumQuantity;
		}
		// if (addressPnlDelta >= 0) {
		// 	console.log("addressPnlDelta", uint256(addressPnlDelta));
		// } else {
		// 	console.log("addressPnlDelta -", uint256(-1 * addressPnlDelta));
		// }

		inventory.sumQuantity = inventory.sumQuantity + _quantity;
		inventory.sumPnl = inventory.sumPnl + addressPnlDelta;
		inventoryItem.quantity = inventoryItem.quantity + _quantity;
		inventoryItem.deltaPnl = inventoryItem.deltaPnl - addressPnlDelta;

		// if (inventory.sumQuantity >= 0) {
		// 	console.log("NEW inventory.sumQuantity", uint256(inventory.sumQuantity));
		// } else {
		// 	console.log("NEW inventory.sumQuantity -", uint256(-1 * inventory.sumQuantity));
		// }
		// if (inventory.sumPnl >= 0) {
		// 	console.log("NEW inventory.sumPnl", uint256(inventory.sumPnl));
		// } else {
		// 	console.log("NEW inventory.sumPnl -", uint256(-1 * inventory.sumPnl));
		// }
		// if (inventoryItem.quantity >= 0) {
		// 	console.log("NEW inventoryItem.quantity", uint256(inventoryItem.quantity));
		// } else {
		// 	console.log("NEW inventoryItem.quantity -", uint256(-1 * inventoryItem.quantity));
		// }
		// if (inventoryItem.deltaPnl >= 0) {
		// 	console.log("NEW inventoryItem.deltaPnl", uint256(inventoryItem.deltaPnl));
		// } else {
		// 	console.log("NEW inventoryItem.deltaPnl -", uint256(-1 * inventoryItem.deltaPnl));
		// }
	}

	function refreshDivident(address _contract, uint256 _tokenId, address _fromAccount, address _toAccount, uint256 _quantity) internal {
		TokenPNLStorage storage tokenPNL = LibTokenPNLStorage.layout();
		Inventory storage inventory = tokenPNL.inventory[_contract][_tokenId];
		if (!inventory.isEnabled) {
			return;
		}

		if (_fromAccount != address(0)) {
			_refreshDividentInternal(inventory, _fromAccount, -1 * int256(_quantity));
		}

		if (_toAccount != address(0)) {
			_refreshDividentInternal(inventory, _toAccount, int256(_quantity));
		}
	}

	function calcDivident(address _contract, uint256 _tokenId, address _account) internal view returns (int256) {
		if (_account == address(0)) {
			return 0;
		}

		TokenPNLStorage storage tokenPNL = LibTokenPNLStorage.layout();
		Inventory storage inventory = tokenPNL.inventory[_contract][_tokenId];
		if (!inventory.isEnabled) {
			return 0;
		}

		InventoryItem storage inventoryItem = inventory.divident[_account];
		//calculate actual value of the token
		int256 actValue = 0;
		if (inventory.sumQuantity != 0) {
			actValue = (inventory.sumPnl * inventoryItem.quantity) / inventory.sumQuantity;
		}
		//the divident is equal with the actual value minus the summa pnlDelta
		//note: the pnlDelta already have the negative sign!!!
		int256 actDivident = actValue + inventoryItem.deltaPnl - inventoryItem.payedPnl;

		// console.log("calcDivident");
		// if (inventory.sumPnl >= 0) {
		// 	console.log("inventory.sumPnl", uint256(inventory.sumPnl));
		// } else {
		// 	console.log("inventory.sumPnl -", uint256(-1 * inventory.sumPnl));
		// }
		// if (inventoryItem.quantity >= 0) {
		// 	console.log("inventoryItem.quantity", uint256(inventoryItem.quantity));
		// } else {
		// 	console.log("inventoryItem.quantity -", uint256(-1 * inventoryItem.quantity));
		// }
		// if (inventory.sumQuantity >= 0) {
		// 	console.log("inventory.sumQuantity", uint256(inventory.sumQuantity));
		// } else {
		// 	console.log("inventory.sumQuantity -", uint256(-1 * inventory.sumQuantity));
		// }
		// if (inventoryItem.deltaPnl >= 0) {
		// 	console.log("inventoryItem.deltaPnl", uint256(inventoryItem.deltaPnl));
		// } else {
		// 	console.log("inventoryItem.deltaPnl -", uint256(-1 * inventoryItem.deltaPnl));
		// }
		// if (inventoryItem.payedPnl >= 0) {
		// 	console.log("inventoryItem.payedPnl", uint256(inventoryItem.payedPnl));
		// } else {
		// 	console.log("inventoryItem.payedPnl -", uint256(-1 * inventoryItem.payedPnl));
		// }
		// if (actDivident >= 0) {
		// 	console.log("actDivident", uint256(actDivident));
		// } else {
		// 	console.log("actDivident -", uint256(-1 * actDivident));
		// }

		return actDivident;
	}

	function refreshPayoutDivident(address _contract, uint256 _tokenId, address _account, int256 _amount) internal {
		TokenPNLStorage storage tokenPNL = LibTokenPNLStorage.layout();
		Inventory storage inventory = tokenPNL.inventory[_contract][_tokenId];
		if (!inventory.isEnabled) {
			return;
		}
		require(_amount >= 0, "Only positive amount can be payed out!");

		int256 payableDivident = calcDivident(_contract, _tokenId, _account);

		require(_amount <= payableDivident, "The amount is bigger then tha payable divident!");

		InventoryItem storage inventoryItem = inventory.divident[_account];
		inventoryItem.payedPnl = inventoryItem.payedPnl + _amount;
	}
}


// File: contracts/base/TokenPNL/LibTokenPNLStorage.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { EnumerableSet } from "../../utils/EnumerableSet.sol";
import { IERC20 } from "../../base/ERC20/IERC20.sol";

struct InventoryItem {
	int256 quantity;
	int256 deltaPnl; //After calculating the act Pnl based on the quantity this is a Pnl modification factor!
	int256 payedPnl;
}

struct Inventory {
	bool isEnabled;
	int256 sumQuantity;
	int256 sumAmount;
	int256 sumPnl;
	//Account - pool divident calculation
	mapping(address => InventoryItem) divident;
}

struct TokenPNLStorage {
	//contract => tokenId => inventory map
	//Eg: IERC20 => 0 => inventory
	//Eg: IERC1155 => tokenId => Inventory
	mapping(address => mapping(uint256 => Inventory)) inventory;
}

library LibTokenPNLStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("usmart.common.token-pnl.storage.v1");

	function layout() internal pure returns (TokenPNLStorage storage layout_) {
		bytes32 position = STORAGE_SLOT;
		assembly {
			layout_.slot := position
		}
	}
}


// File: contracts/base/TokenRestriction/LibTokenRestriction.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

//import "hardhat/console.sol";

import "./LibTokenRestrictionStorage.sol";
import "../../base/ERC1155/base/LibERC1155.sol";
import "../../utils/Math.sol";

import { IERC20 } from "../../base/ERC20/IERC20.sol";

library LibTokenRestriction {
	function initTokenRestriction(uint256 _tokenId, uint256 _endOfRestriction, uint256 _endOfRestrictionCalc, uint256 _timeDelta) internal {
		// require(block.number + 12 * _timeDelta < _endOfRestriction);
		// require(_endOfRestriction + 12 * _timeDelta < _endOfRestrictionCalc);

		TokenRestrictionStorage storage arexa = LibTokenRestrictionStorage.layout();
		Restriction storage restriction = arexa.tokenRestriction[_tokenId];
		if ((restriction.endOfRestrictionCalc == 0) || (restriction.endOfRestriction + 1 == restriction.endOfRestrictionCalc)) {
			restriction.endOfRestriction = _endOfRestriction;
			restriction.endOfRestrictionCalc = _endOfRestrictionCalc;
			restriction.timeDelta = _timeDelta;
		}
	}

	function calcUnrestrictedAmount(address _account, uint256 _tokenId, uint256 _amount) internal view returns (uint256) {
		TokenRestrictionStorage storage arexa = LibTokenRestrictionStorage.layout();
		Restriction storage restriction = arexa.tokenRestriction[_tokenId];

		if (restriction.endOfRestrictionCalc < block.number) {
			return _amount;
		}

		// if (restriction.endOfRestriction < block.number) {
		// 	return _amount;
		// }

		RestrictionCalc storage accRestr = restriction.restriction[_account];

		//=FLOOR.MATH(FLOOR.MATH((K8-I8)/L8)*(E8-M8)/12)
		//=FLOOR.MATH(FLOOR.MATH((actTime-time)/timeDelta)*(bought-accumulated)/12)
		// console.log("calcUnrestrictedAmount");
		// console.log("account", _account);
		// console.log("blocknumber", block.number);
		// console.log("accRestr.time", accRestr.time);
		// console.log("restriction.timeDelta", restriction.timeDelta);
		// console.log("accRestr.bought", accRestr.bought);
		// console.log("accRestr.accumulated", accRestr.accumulated);
		uint256 helper = ((block.number - accRestr.time) / restriction.timeDelta) * ((accRestr.bought - accRestr.accumulated) / 12);
		// console.log("helper", helper);

		//=MIN(M10+Q10;E10)-G10
		//=MIN(accumulated+helper;bought)-sold
		uint256 canSell = Math.min(accRestr.accumulated + helper, accRestr.bought) - accRestr.sold;
		// console.log("canSell", canSell);

		return canSell;
	}

	function checkRestriction(address _account, uint256 _tokenId, uint256 _amount) internal view {
		TokenRestrictionStorage storage arexa = LibTokenRestrictionStorage.layout();
		Restriction storage restriction = arexa.tokenRestriction[_tokenId];

		if (restriction.endOfRestrictionCalc <= block.number) {
			return;
		}

		// if (restriction.endOfRestriction < block.number) {
		// 	return;
		// }

		RestrictionCalc storage accRestr = restriction.restriction[_account];

		//=FLOOR.MATH(FLOOR.MATH((K8-I8)/L8)*(E8-M8)/12)
		//=FLOOR.MATH(FLOOR.MATH((actTime-time)/timeDelta)*(bought-accumulated)/12)
		// console.log("CheckRestriction");
		// console.log("account", _account);
		// console.log("blocknumber", block.number);
		// console.log("accRestr.time", accRestr.time);
		// console.log("restriction.timeDelta", restriction.timeDelta);
		// console.log("accRestr.bought", accRestr.bought);
		// console.log("accRestr.accumulated", accRestr.accumulated);
		uint256 helper = ((block.number - accRestr.time) / restriction.timeDelta) * ((accRestr.bought - accRestr.accumulated) / 12);
		// console.log("helper", helper);

		//=MIN(M10+Q10;E10)-G10
		//=MIN(accumulated+helper;bought)-sold
		uint256 canSell = Math.min(accRestr.accumulated + helper, accRestr.bought) - accRestr.sold;
		// console.log("canSell", canSell);

		require(_amount <= canSell, "The amount is grater then the accumlated ('sellable') amount!");
	}

	function checkRestrictions(address _account, uint256[] memory _tokenIds, uint256[] memory _amounts) internal view {
		if (_tokenIds.length != _amounts.length) revert LibERC1155__ArrayLengthMismatch();

		for (uint256 i; i < _tokenIds.length; ) {
			checkRestriction(_account, _tokenIds[i], _amounts[i]);
			unchecked {
				i++;
			}
		}
	}

	function recalcRestriction(address _account, uint256 _tokenId, uint256 _amount, uint8 _direction) internal {
		//eladható mennyiség kalkulációhoz
		TokenRestrictionStorage storage arexa = LibTokenRestrictionStorage.layout();
		Restriction storage restriction = arexa.tokenRestriction[_tokenId];

		if (restriction.endOfRestrictionCalc <= block.number) {
			return;
		}

		RestrictionCalc storage accRestr = restriction.restriction[_account];

		if (restriction.endOfRestriction <= block.number) {
			//valami mást kell csinálni
			if (_direction == 1) {
				accRestr.bought += _amount;
				accRestr.accumulated += _amount;
			}
			return;
		}

		//frissíteni üzemszerűen.
		//=FLOOR.MATH(FLOOR.MATH((J12-I12)/L12)*(E12-M12)/12)
		//=FLOOR.MATH(FLOOR.MATH((actTime-time)/timeDelta)*(bought-accumlated)/12)
		// console.log("RecalcRestriction");
		// console.log("account", _account);
		// console.log("blocknumber", block.number);
		// console.log("accRestr.time", accRestr.time);
		// console.log("restriction.timeDelta", restriction.timeDelta);
		// console.log("accRestr.bought", accRestr.bought);
		// console.log("accRestr.accumulated", accRestr.accumulated);
		uint256 helper = ((block.number - accRestr.time) / restriction.timeDelta) * ((accRestr.bought - accRestr.accumulated) / 12);
		// console.log("helper", helper);

		//=MIN(M12+N12; E12)
		//=MIN(accumulated+helper; bought)
		accRestr.accumulated = Math.min(accRestr.accumulated + helper, accRestr.bought);
		// console.log("NEW accRestr.accumulated", accRestr.accumulated);

		//vesz, elad
		if (_direction == 1) {
			accRestr.bought += _amount;
		} else {
			accRestr.sold += _amount;
		}

		accRestr.time = block.number;

		// console.log("NEW accRestr.bought", accRestr.bought);
		// console.log("NEW accRestr.sold", accRestr.sold);
		// console.log("NEW accRestr.time", accRestr.time);
	}

	function recalcRestrictions(address _account, uint256[] memory _tokenIds, uint256[] memory _amounts, uint8 _direction) internal {
		if (_tokenIds.length != _amounts.length) revert LibERC1155__ArrayLengthMismatch();

		for (uint256 i; i < _tokenIds.length; ) {
			recalcRestriction(_account, _tokenIds[i], _amounts[i], _direction);
			unchecked {
				i++;
			}
		}
	}
}


// File: contracts/base/TokenRestriction/LibTokenRestrictionStorage.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { EnumerableSet } from "../../utils/EnumerableSet.sol";

struct RestrictionCalc {
	uint256 bought;
	uint256 sold;
	uint256 time; //blockheight * 1 000 000 000
	uint256 accumulated;
}

struct Restriction {
	uint256 endOfRestriction; //if act-time is lower then endOfRestriction then only calculating the a previous data, new tokens do not restircted
	uint256 endOfRestrictionCalc; //if act-time is lower then endOfRestrictionCalc then now calculation at all
	uint256 timeDelta; //if time is blockHeight based then delta should be calculated like that. If second based then...
	//Account - restriction calculation params
	mapping(address => RestrictionCalc) restriction;
}

struct TokenRestrictionStorage {
	//tokenId => restriction, every token have
	mapping(uint256 => Restriction) tokenRestriction;
}

library LibTokenRestrictionStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("usmart.common.token-restriction.storage.v1");

	function layout() internal pure returns (TokenRestrictionStorage storage layout_) {
		bytes32 position = STORAGE_SLOT;
		assembly {
			layout_.slot := position
		}
	}
}


// File: contracts/interfaces/IDiamondCut.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/

interface IDiamondCut {
	enum FacetCutAction {
		Add,
		Replace,
		Remove
	}
	// Add=0, Replace=1, Remove=2

	struct FacetCut {
		address facetAddress;
		FacetCutAction action;
		bytes4[] functionSelectors;
	}

	/// @notice Add/replace/remove any number of functions and optionally execute
	///         a function with delegatecall
	/// @param _diamondCut Contains the facet addresses and function selectors
	/// @param _init The address of the contract or facet to execute _calldata
	/// @param _calldata A function call, including function selector and arguments
	///                  _calldata is executed with delegatecall on _init
	function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;

	event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);
}


// File: contracts/interfaces/IERC173.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

/// @title ERC-173 Contract Ownership Standard
///  Note: the ERC-165 identifier for this interface is 0x7f5828d0
interface IERC173 {
	/// @dev This emits when ownership of a contract changes.
	event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

	/// @notice Get the address of the owner
	/// @return owner_ The address of the owner.
	function owner() external view returns (address owner_);

	/// @notice Set the address of the new owner of the contract
	/// @dev Set _newOwner to address(0) to renounce any ownership.
	/// @param _newOwner The address of the new owner of the contract
	function transferOwnership(address _newOwner) external;
}


// File: contracts/utils/AddressUtils.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

import { UintUtils } from "./UintUtils.sol";

library AddressUtils {
	using UintUtils for uint256;

	error AddressUtils__InsufficientBalance();
	error AddressUtils__NotContract();
	error AddressUtils__SendValueFailed();

	function toString(address account) internal pure returns (string memory) {
		return uint256(uint160(account)).toHexString(20);
	}

	function isContract(address account) internal view returns (bool) {
		uint256 size;
		assembly {
			size := extcodesize(account)
		}
		return size > 0;
	}

	function sendValue(address payable account, uint256 amount) internal {
		(bool success, ) = account.call{ value: amount }("");
		if (!success) revert AddressUtils__SendValueFailed();
	}

	function functionCall(address target, bytes memory data) internal returns (bytes memory) {
		return functionCall(target, data, "AddressUtils: failed low-level call");
	}

	function functionCall(address target, bytes memory data, string memory error) internal returns (bytes memory) {
		return _functionCallWithValue(target, data, 0, error);
	}

	function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
		return functionCallWithValue(target, data, value, "AddressUtils: failed low-level call with value");
	}

	function functionCallWithValue(address target, bytes memory data, uint256 value, string memory error) internal returns (bytes memory) {
		if (value > address(this).balance) revert AddressUtils__InsufficientBalance();
		return _functionCallWithValue(target, data, value, error);
	}

	/**
	 * @notice execute arbitrary external call with limited gas usage and amount of copied return data
	 * @dev derived from https://github.com/nomad-xyz/ExcessivelySafeCall (MIT License)
	 * @param target recipient of call
	 * @param gasAmount gas allowance for call
	 * @param value native token value to include in call
	 * @param maxCopy maximum number of bytes to copy from return data
	 * @param data encoded call data
	 * @return success whether call is successful
	 * @return returnData copied return data
	 */
	function excessivelySafeCall(
		address target,
		uint256 gasAmount,
		uint256 value,
		uint16 maxCopy,
		bytes memory data
	) internal returns (bool success, bytes memory returnData) {
		returnData = new bytes(maxCopy);

		assembly {
			// execute external call via assembly to avoid automatic copying of return data
			success := call(gasAmount, target, value, add(data, 0x20), mload(data), 0, 0)

			// determine whether to limit amount of data to copy
			let toCopy := returndatasize()

			if gt(toCopy, maxCopy) {
				toCopy := maxCopy
			}

			// store the length of the copied bytes
			mstore(returnData, toCopy)

			// copy the bytes from returndata[0:toCopy]
			returndatacopy(add(returnData, 0x20), 0, toCopy)
		}
	}

	function _functionCallWithValue(address target, bytes memory data, uint256 value, string memory error) private returns (bytes memory) {
		if (!isContract(target)) revert AddressUtils__NotContract();

		(bool success, bytes memory returnData) = target.call{ value: value }(data);

		if (success) {
			return returnData;
		} else if (returnData.length > 0) {
			assembly {
				let returnData_size := mload(returnData)
				revert(add(32, returnData), returnData_size)
			}
		} else {
			revert(error);
		}
	}
}


// File: contracts/utils/EnumerableSet.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

/**
 * @title Set implementation with enumeration functions
 * @dev derived from https://github.com/OpenZeppelin/openzeppelin-contracts (MIT license)
 */
library EnumerableSet {
	error EnumerableSet__IndexOutOfBounds();

	struct Set {
		bytes32[] _values;
		// 1-indexed to allow 0 to signify nonexistence
		mapping(bytes32 => uint256) _indexes;
	}

	struct Bytes32Set {
		Set _inner;
	}

	struct AddressSet {
		Set _inner;
	}

	struct UintSet {
		Set _inner;
	}

	function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
		return _at(set._inner, index);
	}

	function at(AddressSet storage set, uint256 index) internal view returns (address) {
		return address(uint160(uint256(_at(set._inner, index))));
	}

	function at(UintSet storage set, uint256 index) internal view returns (uint256) {
		return uint256(_at(set._inner, index));
	}

	function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
		return _contains(set._inner, value);
	}

	function contains(AddressSet storage set, address value) internal view returns (bool) {
		return _contains(set._inner, bytes32(uint256(uint160(value))));
	}

	function contains(UintSet storage set, uint256 value) internal view returns (bool) {
		return _contains(set._inner, bytes32(value));
	}

	function indexOf(Bytes32Set storage set, bytes32 value) internal view returns (uint256) {
		return _indexOf(set._inner, value);
	}

	function indexOf(AddressSet storage set, address value) internal view returns (uint256) {
		return _indexOf(set._inner, bytes32(uint256(uint160(value))));
	}

	function indexOf(UintSet storage set, uint256 value) internal view returns (uint256) {
		return _indexOf(set._inner, bytes32(value));
	}

	function length(Bytes32Set storage set) internal view returns (uint256) {
		return _length(set._inner);
	}

	function length(AddressSet storage set) internal view returns (uint256) {
		return _length(set._inner);
	}

	function length(UintSet storage set) internal view returns (uint256) {
		return _length(set._inner);
	}

	function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
		return _add(set._inner, value);
	}

	function add(AddressSet storage set, address value) internal returns (bool) {
		return _add(set._inner, bytes32(uint256(uint160(value))));
	}

	function add(UintSet storage set, uint256 value) internal returns (bool) {
		return _add(set._inner, bytes32(value));
	}

	function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
		return _remove(set._inner, value);
	}

	function remove(AddressSet storage set, address value) internal returns (bool) {
		return _remove(set._inner, bytes32(uint256(uint160(value))));
	}

	function remove(UintSet storage set, uint256 value) internal returns (bool) {
		return _remove(set._inner, bytes32(value));
	}

	function toArray(Bytes32Set storage set) internal view returns (bytes32[] memory) {
		return set._inner._values;
	}

	function toArray(AddressSet storage set) internal view returns (address[] memory) {
		bytes32[] storage values = set._inner._values;
		address[] storage array;

		assembly {
			array.slot := values.slot
		}

		return array;
	}

	function toArray(UintSet storage set) internal view returns (uint256[] memory) {
		bytes32[] storage values = set._inner._values;
		uint256[] storage array;

		assembly {
			array.slot := values.slot
		}

		return array;
	}

	function _at(Set storage set, uint256 index) private view returns (bytes32) {
		if (index >= set._values.length) revert EnumerableSet__IndexOutOfBounds();
		return set._values[index];
	}

	function _contains(Set storage set, bytes32 value) private view returns (bool) {
		return set._indexes[value] != 0;
	}

	function _indexOf(Set storage set, bytes32 value) private view returns (uint256) {
		unchecked {
			return set._indexes[value] - 1;
		}
	}

	function _length(Set storage set) private view returns (uint256) {
		return set._values.length;
	}

	function _add(Set storage set, bytes32 value) private returns (bool status) {
		if (!_contains(set, value)) {
			set._values.push(value);
			set._indexes[value] = set._values.length;
			status = true;
		}
	}

	function _remove(Set storage set, bytes32 value) private returns (bool status) {
		uint256 valueIndex = set._indexes[value];

		if (valueIndex != 0) {
			unchecked {
				bytes32 last = set._values[set._values.length - 1];

				// move last value to now-vacant index

				set._values[valueIndex - 1] = last;
				set._indexes[last] = valueIndex;
			}
			// clear last index

			set._values.pop();
			delete set._indexes[value];

			status = true;
		}
	}
}


// File: contracts/utils/Math.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

library Math {
	/**
	 * @notice calculate the absolute value of a number
	 * @param a number whose absoluve value to calculate
	 * @return absolute value
	 */
	function abs(int256 a) internal pure returns (uint256) {
		return uint256(a < 0 ? -a : a);
	}

	/**
	 * @notice select the greater of two numbers
	 * @param a first number
	 * @param b second number
	 * @return greater number
	 */
	function max(uint256 a, uint256 b) internal pure returns (uint256) {
		return a > b ? a : b;
	}

	/**
	 * @notice select the lesser of two numbers
	 * @param a first number
	 * @param b second number
	 * @return lesser number
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a > b ? b : a;
	}

	/**
	 * @notice calculate the average of two numbers, rounded down
	 * @dev derived from https://github.com/OpenZeppelin/openzeppelin-contracts (MIT license)
	 * @param a first number
	 * @param b second number
	 * @return mean value
	 */
	function average(uint256 a, uint256 b) internal pure returns (uint256) {
		unchecked {
			return (a & b) + ((a ^ b) >> 1);
		}
	}

	/**
	 * @notice estimate square root of number
	 * @dev uses Babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
	 * @param x input number
	 * @return y square root
	 */
	function sqrt(uint256 x) internal pure returns (uint256 y) {
		uint256 z = (x + 1) >> 1;
		y = x;
		while (z < y) {
			y = z;
			z = (x / z + z) >> 1;
		}
	}
}


// File: contracts/utils/UintUtils.sol
// SPDX-License-Identifier: MIT
/**
 * Copyright (C) 2024 uSmart
 */
pragma solidity ^0.8.9;

/**
 * @title utility functions for uint256 operations
 * @dev derived from https://github.com/OpenZeppelin/openzeppelin-contracts/ (MIT license)
 */
library UintUtils {
	error UintUtils__InsufficientHexLength();

	bytes16 private constant HEX_SYMBOLS = "0123456789abcdef";

	function add(uint256 a, int256 b) internal pure returns (uint256) {
		return b < 0 ? sub(a, -b) : a + uint256(b);
	}

	function sub(uint256 a, int256 b) internal pure returns (uint256) {
		return b < 0 ? add(a, -b) : a - uint256(b);
	}

	function toString(uint256 value) internal pure returns (string memory) {
		if (value == 0) {
			return "0";
		}

		uint256 temp = value;
		uint256 digits;

		while (temp != 0) {
			digits++;
			temp /= 10;
		}

		bytes memory buffer = new bytes(digits);

		while (value != 0) {
			digits -= 1;
			buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
			value /= 10;
		}

		return string(buffer);
	}

	function toHexString(uint256 value) internal pure returns (string memory) {
		if (value == 0) {
			return "0x00";
		}

		uint256 length = 0;

		for (uint256 temp = value; temp != 0; temp >>= 8) {
			unchecked {
				length++;
			}
		}

		return toHexString(value, length);
	}

	function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
		bytes memory buffer = new bytes(2 * length + 2);
		buffer[0] = "0";
		buffer[1] = "x";

		unchecked {
			for (uint256 i = 2 * length + 1; i > 1; --i) {
				buffer[i] = HEX_SYMBOLS[value & 0xf];
				value >>= 4;
			}
		}

		if (value != 0) revert UintUtils__InsufficientHexLength();

		return string(buffer);
	}
}


// File: hardhat/console.sol
// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

library console {
    address constant CONSOLE_ADDRESS =
        0x000000000000000000636F6e736F6c652e6c6f67;

    function _sendLogPayloadImplementation(bytes memory payload) internal view {
        address consoleAddress = CONSOLE_ADDRESS;
        /// @solidity memory-safe-assembly
        assembly {
            pop(
                staticcall(
                    gas(),
                    consoleAddress,
                    add(payload, 32),
                    mload(payload),
                    0,
                    0
                )
            )
        }
    }

    function _castToPure(
      function(bytes memory) internal view fnIn
    ) internal pure returns (function(bytes memory) pure fnOut) {
        assembly {
            fnOut := fnIn
        }
    }

    function _sendLogPayload(bytes memory payload) internal pure {
        _castToPure(_sendLogPayloadImplementation)(payload);
    }

    function log() internal pure {
        _sendLogPayload(abi.encodeWithSignature("log()"));
    }
    function logInt(int256 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(int256)", p0));
    }

    function logUint(uint256 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256)", p0));
    }

    function logString(string memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", p0));
    }

    function logBool(bool p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
    }

    function logAddress(address p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address)", p0));
    }

    function logBytes(bytes memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes)", p0));
    }

    function logBytes1(bytes1 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes1)", p0));
    }

    function logBytes2(bytes2 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes2)", p0));
    }

    function logBytes3(bytes3 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes3)", p0));
    }

    function logBytes4(bytes4 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes4)", p0));
    }

    function logBytes5(bytes5 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes5)", p0));
    }

    function logBytes6(bytes6 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes6)", p0));
    }

    function logBytes7(bytes7 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes7)", p0));
    }

    function logBytes8(bytes8 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes8)", p0));
    }

    function logBytes9(bytes9 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes9)", p0));
    }

    function logBytes10(bytes10 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes10)", p0));
    }

    function logBytes11(bytes11 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes11)", p0));
    }

    function logBytes12(bytes12 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes12)", p0));
    }

    function logBytes13(bytes13 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes13)", p0));
    }

    function logBytes14(bytes14 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes14)", p0));
    }

    function logBytes15(bytes15 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes15)", p0));
    }

    function logBytes16(bytes16 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes16)", p0));
    }

    function logBytes17(bytes17 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes17)", p0));
    }

    function logBytes18(bytes18 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes18)", p0));
    }

    function logBytes19(bytes19 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes19)", p0));
    }

    function logBytes20(bytes20 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes20)", p0));
    }

    function logBytes21(bytes21 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes21)", p0));
    }

    function logBytes22(bytes22 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes22)", p0));
    }

    function logBytes23(bytes23 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes23)", p0));
    }

    function logBytes24(bytes24 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes24)", p0));
    }

    function logBytes25(bytes25 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes25)", p0));
    }

    function logBytes26(bytes26 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes26)", p0));
    }

    function logBytes27(bytes27 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes27)", p0));
    }

    function logBytes28(bytes28 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes28)", p0));
    }

    function logBytes29(bytes29 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes29)", p0));
    }

    function logBytes30(bytes30 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes30)", p0));
    }

    function logBytes31(bytes31 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes31)", p0));
    }

    function logBytes32(bytes32 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes32)", p0));
    }

    function log(uint256 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256)", p0));
    }

    function log(string memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", p0));
    }

    function log(bool p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
    }

    function log(address p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address)", p0));
    }

    function log(uint256 p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256)", p0, p1));
    }

    function log(uint256 p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string)", p0, p1));
    }

    function log(uint256 p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool)", p0, p1));
    }

    function log(uint256 p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address)", p0, p1));
    }

    function log(string memory p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256)", p0, p1));
    }

    function log(string memory p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string)", p0, p1));
    }

    function log(string memory p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool)", p0, p1));
    }

    function log(string memory p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address)", p0, p1));
    }

    function log(bool p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256)", p0, p1));
    }

    function log(bool p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string)", p0, p1));
    }

    function log(bool p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool)", p0, p1));
    }

    function log(bool p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address)", p0, p1));
    }

    function log(address p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256)", p0, p1));
    }

    function log(address p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string)", p0, p1));
    }

    function log(address p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool)", p0, p1));
    }

    function log(address p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address)", p0, p1));
    }

    function log(uint256 p0, uint256 p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256)", p0, p1, p2));
    }

    function log(uint256 p0, uint256 p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string)", p0, p1, p2));
    }

    function log(uint256 p0, uint256 p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool)", p0, p1, p2));
    }

    function log(uint256 p0, uint256 p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address)", p0, p1, p2));
    }

    function log(uint256 p0, string memory p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256)", p0, p1, p2));
    }

    function log(uint256 p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string)", p0, p1, p2));
    }

    function log(uint256 p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool)", p0, p1, p2));
    }

    function log(uint256 p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address)", p0, p1, p2));
    }

    function log(uint256 p0, bool p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256)", p0, p1, p2));
    }

    function log(uint256 p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string)", p0, p1, p2));
    }

    function log(uint256 p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool)", p0, p1, p2));
    }

    function log(uint256 p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address)", p0, p1, p2));
    }

    function log(uint256 p0, address p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256)", p0, p1, p2));
    }

    function log(uint256 p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string)", p0, p1, p2));
    }

    function log(uint256 p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool)", p0, p1, p2));
    }

    function log(uint256 p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address)", p0, p1, p2));
    }

    function log(string memory p0, uint256 p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256)", p0, p1, p2));
    }

    function log(string memory p0, uint256 p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string)", p0, p1, p2));
    }

    function log(string memory p0, uint256 p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool)", p0, p1, p2));
    }

    function log(string memory p0, uint256 p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address)", p0, p1, p2));
    }

    function log(string memory p0, address p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256)", p0, p1, p2));
    }

    function log(string memory p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string)", p0, p1, p2));
    }

    function log(string memory p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool)", p0, p1, p2));
    }

    function log(string memory p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address)", p0, p1, p2));
    }

    function log(bool p0, uint256 p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256)", p0, p1, p2));
    }

    function log(bool p0, uint256 p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string)", p0, p1, p2));
    }

    function log(bool p0, uint256 p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool)", p0, p1, p2));
    }

    function log(bool p0, uint256 p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address)", p0, p1, p2));
    }

    function log(bool p0, bool p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256)", p0, p1, p2));
    }

    function log(bool p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string)", p0, p1, p2));
    }

    function log(bool p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool)", p0, p1, p2));
    }

    function log(bool p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address)", p0, p1, p2));
    }

    function log(bool p0, address p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256)", p0, p1, p2));
    }

    function log(bool p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string)", p0, p1, p2));
    }

    function log(bool p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool)", p0, p1, p2));
    }

    function log(bool p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address)", p0, p1, p2));
    }

    function log(address p0, uint256 p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256)", p0, p1, p2));
    }

    function log(address p0, uint256 p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string)", p0, p1, p2));
    }

    function log(address p0, uint256 p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool)", p0, p1, p2));
    }

    function log(address p0, uint256 p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address)", p0, p1, p2));
    }

    function log(address p0, string memory p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256)", p0, p1, p2));
    }

    function log(address p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string)", p0, p1, p2));
    }

    function log(address p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool)", p0, p1, p2));
    }

    function log(address p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address)", p0, p1, p2));
    }

    function log(address p0, bool p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256)", p0, p1, p2));
    }

    function log(address p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string)", p0, p1, p2));
    }

    function log(address p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool)", p0, p1, p2));
    }

    function log(address p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address)", p0, p1, p2));
    }

    function log(address p0, address p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256)", p0, p1, p2));
    }

    function log(address p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string)", p0, p1, p2));
    }

    function log(address p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool)", p0, p1, p2));
    }

    function log(address p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address)", p0, p1, p2));
    }

    function log(uint256 p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,uint256,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,string,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,bool,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, uint256 p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,uint256,address,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,uint256,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,string,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,bool,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,string,address,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,uint256,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,string,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,bool,address,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,uint256,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,string,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,bool,address)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address,uint256)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address,string)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address,bool)", p0, p1, p2, p3));
    }

    function log(uint256 p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint256,address,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,uint256,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint256 p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint256,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint256,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint256,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,uint256)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,uint256,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint256 p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint256,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint256,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint256,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint256,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,uint256)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,uint256,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint256 p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint256,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint256,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint256,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint256 p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint256 p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint256 p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint256,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, uint256 p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,uint256)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,address)", p0, p1, p2, p3));
    }

}


