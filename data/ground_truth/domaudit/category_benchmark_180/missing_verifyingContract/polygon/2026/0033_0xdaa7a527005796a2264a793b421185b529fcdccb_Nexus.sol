// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xdaa7a527005796a2264a793b421185b529fcdccb
// Contract Name: Nexus



// ============================================================
// FILE: contracts/nexus/Nexus.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { BaseAccount } from "./base/BaseAccount.sol";
import { ModuleManager } from "./base/ModuleManager.sol";
import { ExecutionHelper } from "./base/ExecutionHelper.sol";
import { ComposableExecutionBase, ComposableExecution } from "../composability/ComposableExecutionBase.sol";
import { Initializable } from "../lib/nexus/Initializable.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";
import { INexus } from "../interfaces/nexus/INexus.sol";
import { ExecLib } from "../lib/erc-7579/ExecLib.sol";
import { NonceLib } from "../lib/nexus/NonceLib.sol";
import { SentinelListLib, SENTINEL, ZERO_ADDRESS } from "sentinellist/SentinelList.sol";
import { EmergencyUninstall } from "../types/DataTypes.sol";
import { LibPREP } from "../lib/nexus/local/LibPREP.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { IValidator } from "erc7579/interfaces/IERC7579Module.sol";
import {
    MODULE_TYPE_VALIDATOR,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK,
    MODULE_TYPE_HOOK,
    SUPPORTS_ERC7739
} from "../types/Constants.sol";
import {
    ModeLib,
    ExecutionMode,
    ExecType,
    CallType,
    CALLTYPE_BATCH,
    CALLTYPE_SINGLE,
    CALLTYPE_DELEGATECALL,
    EXECTYPE_DEFAULT,
    EXECTYPE_TRY
} from "../lib/erc-7579/ModeLib.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";

/// @title Nexus - Smart Account
/// @notice This contract integrates various functionalities to handle modular smart accounts compliant with ERC-7579
/// and
/// ERC-4337 standards.
/// @dev Comprehensive suite of methods for managing smart accounts, integrating module management, execution
/// management,
/// and upgradability via UUPS.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract Nexus is INexus, BaseAccount, ExecutionHelper, ModuleManager, UUPSUpgradeable, ComposableExecutionBase {
    using ModeLib for ExecutionMode;
    using ExecLib for bytes;
    using NonceLib for uint256;
    using SentinelListLib for SentinelListLib.SentinelList;

    /// @dev The timelock period for emergency hook uninstallation.
    uint256 internal constant _EMERGENCY_TIMELOCK = 1 days;

    /// @dev The event emitted when an emergency hook uninstallation is initiated.
    event EmergencyHookUninstallRequest(address hook, uint256 timestamp);

    /// @dev The event emitted when an emergency hook uninstallation request is reset.
    event EmergencyHookUninstallRequestReset(address hook, uint256 timestamp);

    /// @notice Initializes the smart account with the specified entry point.
    constructor(
        address anEntryPoint,
        address defaultValidator,
        bytes memory initData
    )
        ModuleManager(defaultValidator, initData)
    {
        require(address(anEntryPoint) != address(0), EntryPointCanNotBeZero());
        _ENTRYPOINT = anEntryPoint;
    }

    /// @notice Validates a user operation against a specified validator, extracted from the operation's nonce.
    /// @param op The user operation to validate, encapsulating all transaction details.
    /// @param userOpHash Hash of the user operation data, used for signature validation.
    /// @param missingAccountFunds Funds missing from the account's deposit necessary for transaction execution.
    /// This can be zero if covered by a paymaster or if sufficient deposit exists.
    /// @return validationData Encoded validation result or failure, propagated from the validator module.
    /// - Encoded format in validationData:
    ///     - First 20 bytes: Address of the Validator module, to which the validation task is forwarded.
    ///       The validator module returns:
    ///         - `SIG_VALIDATION_SUCCESS` (0) indicates successful validation.
    ///         - `SIG_VALIDATION_FAILED` (1) indicates signature validation failure.
    /// @dev Expects the validator's address to be encoded in the upper 96 bits of the user operation's nonce.
    /// This method forwards the validation task to the extracted validator module address.
    /// @dev The entryPoint calls this function. If validation fails, it returns `VALIDATION_FAILED` (1) otherwise `0`.
    /// @dev Features Module Enable Mode.
    /// This Module Enable Mode flow is intended for the module acting as the validator
    /// for the user operation that triggers the Module Enable Flow. Otherwise, a call to
    /// `Nexus.installModule` should be included in `userOp.callData`.
    function validateUserOp(
        PackedUserOperation calldata op,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    )
        external
        virtual
        payPrefund(missingAccountFunds)
        onlyEntryPoint
        returns (uint256 validationData)
    {
        address validator;
        PackedUserOperation memory userOp = op;

        if (op.nonce.isValidateMode()) {
            // do nothing special. This is introduced
            // to quickly identify the most commonly used
            // mode which is validate mode
            // and avoid checking two above conditions
        } else if (op.nonce.isModuleEnableMode()) {
            // if it is module enable mode, we need to enable the module first
            // and get the cleaned signature
            userOp.signature = _enableMode(userOpHash, op.signature);
        } else if (op.nonce.isPrepMode()) {
            // PREP Mode. Authorize prep signature
            // and initialize the account
            // PREP mode is only used for the uninited PREPs
            require(!isInitialized(), AccountAlreadyInitialized());
            bytes calldata initData;
            (userOp.signature, initData) = _handlePREP(op.signature);
            _initializeAccount(initData);
        }
        validator = _handleValidator(op.nonce.getValidator());
        (userOpHash, userOp.signature) = _withPreValidationHook(userOpHash, userOp, missingAccountFunds);
        validationData = IValidator(validator).validateUserOp(userOp, userOpHash);
    }

    /// @notice Executes transactions in single or batch modes as specified by the execution mode.
    /// @param mode The execution mode detailing how transactions should be handled (single, batch, default, try/catch).
    /// @param executionCalldata The encoded transaction data to execute.
    /// @dev This function handles transaction execution flexibility and is protected by the `onlyEntryPoint` modifier.
    /// @dev This function also goes through hook checks via withHook modifier.
    function execute(ExecutionMode mode, bytes calldata executionCalldata) external payable onlyEntryPoint withHook {
        (CallType callType, ExecType execType) = mode.decodeBasic();
        if (callType == CALLTYPE_SINGLE) {
            _handleSingleExecution(executionCalldata, execType);
        } else if (callType == CALLTYPE_BATCH) {
            _handleBatchExecution(executionCalldata, execType);
        } else if (callType == CALLTYPE_DELEGATECALL) {
            _handleDelegateCallExecution(executionCalldata, execType);
        } else {
            revert UnsupportedCallType(callType);
        }
    }

    /// @notice Executes transactions from an executor module, supporting both single and batch transactions.
    /// @param mode The execution mode (single or batch, default or try).
    /// @param executionCalldata The transaction data to execute.
    /// @return returnData The results of the transaction executions, which may include errors in try mode.
    /// @dev This function is callable only by an executor module and goes through hook checks.
    function executeFromExecutor(
        ExecutionMode mode,
        bytes calldata executionCalldata
    )
        external
        payable
        onlyExecutorModule
        withHook
        returns (bytes[] memory returnData)
    {
        (CallType callType, ExecType execType) = mode.decodeBasic();
        // check if calltype is batch or single or delegate call
        if (callType == CALLTYPE_SINGLE) {
            returnData = _handleSingleExecutionAndReturnData(executionCalldata, execType);
        } else if (callType == CALLTYPE_BATCH) {
            returnData = _handleBatchExecutionAndReturnData(executionCalldata, execType);
        } else if (callType == CALLTYPE_DELEGATECALL) {
            returnData = _handleDelegateCallExecutionAndReturnData(executionCalldata, execType);
        } else {
            revert UnsupportedCallType(callType);
        }
    }

    /// @notice Executes a user operation via a call using the contract's context.
    /// @param userOp The user operation to execute, containing transaction details.
    /// @param - Hash of the user operation.
    /// @dev Only callable by the EntryPoint. Decodes the user operation calldata, skipping the first four bytes, and
    /// executes the inner call.
    function executeUserOp(
        PackedUserOperation calldata userOp,
        bytes32
    )
        external
        payable
        virtual
        onlyEntryPoint
        withHook
    {
        bytes calldata callData = userOp.callData[4:];
        (bool success,) = address(this).delegatecall(callData);
        assembly {
            if iszero(success) {
                // revert ExecutionFailed()
                mstore(0x00, 0xacfdb444)
                revert(0x1c, 0x04)
            }
        }
    }

    /// @notice Executes a composable execution
    /// See more about composability here: https://docs.biconomy.io/composability
    /// @param executions The composable executions to execute
    function executeComposable(ComposableExecution[] calldata executions)
        external
        payable
        override
        onlyEntryPoint
        withHook
    {
        _executeComposable(executions);
    }

    /// @notice Executes a call to a target address with specified value and data.
    /// @param to The address to execute the action on
    /// @param value The value to send with the action
    /// @param data The data to send with the action
    /// @return result The result of the execution
    function _executeAction(address to, uint256 value, bytes memory data) internal override returns (bytes memory) {
        return _executeMemory(to, value, data);
    }

    /// @notice Installs a new module to the smart account.
    /// @param moduleTypeId The type identifier of the module being installed, which determines its role:
    /// - 1 for Validator
    /// - 2 for Executor
    /// - 3 for Fallback
    /// - 4 for Hook
    /// - 8 for 1271 Prevalidation Hook
    /// - 9 for 4337 Prevalidation Hook
    /// @param module The address of the module to install.
    /// @param initData Initialization data for the module.
    /// @dev This function can only be called by the EntryPoint or the account itself for security reasons.
    /// @dev This function goes through hook checks via withHook modifier through internal function _installModule.
    function installModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata initData
    )
        external
        payable
        virtual
        override
        onlyEntryPointOrSelf
    {
        _installModule(moduleTypeId, module, initData);
        assembly {
            // emit ModuleInstalled(moduleTypeId, module)
            mstore(0x00, moduleTypeId)
            mstore(0x20, module)
            log1(0x00, 0x40, 0xd21d0b289f126c4b473ea641963e766833c2f13866e4ff480abd787c100ef123)
        }
    }

    /// @notice Uninstalls a module from the smart account.
    /// @param moduleTypeId The type ID of the module to be uninstalled, matching the installation type:
    /// - 1 for Validator
    /// - 2 for Executor
    /// - 3 for Fallback
    /// - 4 for Hook
    /// - 8 for 1271 Prevalidation Hook
    /// - 9 for 4337 Prevalidation Hook
    /// @dev Attention: All the underlying functions _uninstall[ModuleType] are calling module.onInstall() method.
    /// If the module is malicious (which is not likely because such a module won't be attested), it can prevent
    /// itself from being uninstalled by spending all gas in the onUninstall() method. Then 1/64 gas left can
    /// be not enough to finish the uninstallation, assuming there may be hook postCheck() call.
    /// In this highly unlikely scenario, user will have to uninstall the hook, then uninstall the malicious
    /// module => in this case 1/64 gas left should be enough to finish the uninstallation.
    /// @param module The address of the module to uninstall.
    /// @param deInitData De-initialization data for the module.
    /// @dev Ensures that the operation is authorized and valid before proceeding with the uninstallation.
    function uninstallModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata deInitData
    )
        external
        payable
        onlyEntryPointOrSelf
        withHook
    {
        require(_isModuleInstalled(moduleTypeId, module, deInitData), ModuleNotInstalled(moduleTypeId, module));

        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            _uninstallValidator(module, deInitData);
            _checkInitializedValidators();
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            _uninstallExecutor(module, deInitData);
        } else if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            _uninstallFallbackHandler(module, deInitData);
        } else if (moduleTypeId == MODULE_TYPE_HOOK || _isPrevalidationHookType(moduleTypeId)) {
            _uninstallHook(module, moduleTypeId, deInitData);
        }
        emit ModuleUninstalled(moduleTypeId, module);
    }

    function emergencyUninstallHook(EmergencyUninstall calldata data, bytes calldata signature) external payable {
        // Validate the signature
        _checkEmergencyUninstallSignature(data, signature);
        // Parse uninstall data
        (uint256 hookType, address hook, bytes calldata deInitData) = (data.hookType, data.hook, data.deInitData);

        // Validate the hook is of a supported type and is installed
        require(hookType == MODULE_TYPE_HOOK || _isPrevalidationHookType(hookType), UnsupportedModuleType(hookType));
        require(_isModuleInstalled(hookType, hook, deInitData), ModuleNotInstalled(hookType, hook));

        // Get the account storage
        AccountStorage storage accountStorage = _getAccountStorage();
        uint256 hookTimelock = accountStorage.emergencyUninstallTimelock[hook];

        if (hookTimelock == 0) {
            // if the timelock hasnt been initiated, initiate it
            accountStorage.emergencyUninstallTimelock[hook] = block.timestamp;
            emit EmergencyHookUninstallRequest(hook, block.timestamp);
        } else if (block.timestamp >= hookTimelock + 3 * _EMERGENCY_TIMELOCK) {
            // if the timelock has been left for too long, reset it
            accountStorage.emergencyUninstallTimelock[hook] = block.timestamp;
            emit EmergencyHookUninstallRequestReset(hook, block.timestamp);
        } else if (block.timestamp >= hookTimelock + _EMERGENCY_TIMELOCK) {
            // if the timelock expired, clear it and uninstall the hook
            accountStorage.emergencyUninstallTimelock[hook] = 0;
            _uninstallHook(hook, hookType, deInitData);
            emit ModuleUninstalled(hookType, hook);
        } else {
            // if the timelock is initiated but not expired, revert
            revert EmergencyTimeLockNotExpired();
        }
    }

    /// @notice Initializes the smart account with the specified initialization data.
    /// @param initData The initialization data for the smart account.
    /// @dev This function can only be called by the account itself or the proxy factory.
    /// When a 7702 account is created, the first userOp should contain self-call to initialize the account.
    function initializeAccount(bytes calldata initData) external payable virtual {
        // Protect this function to only be callable when used with the proxy factory or when
        // account calls itself
        if (msg.sender != address(this)) {
            if (_amIERC7702()) {
                // If this is a 7702 account, we allow passing a user signature with the initData
                // to initialize the account. This allows 7702 accounts to be initialized
                // by a relayer.
                bytes calldata signature = initData[0:65];
                AccountStorage storage $accountStorage = _getAccountStorage();
                // Remove the signature  from the initData
                initData = initData[65:];
                // Calculate the hash of the initData
                bytes32 initDataHash;
                assembly {
                    let ptr := mload(0x40)
                    calldatacopy(ptr, initData.offset, initData.length)
                    initDataHash := keccak256(ptr, initData.length)
                }
                // Make sure the account has not been already initialized
                // Means relay can not re-initialize the account
                require(!isInitialized(), AccountAlreadyInitialized());
                // Make sure the initHash is not already used
                require(!$accountStorage.erc7702InitHashes[initDataHash], AccountAlreadyInitialized());
                // Check if the signature is valid
                require(ECDSA.recover(initDataHash, signature) == address(this), InvalidSignature());
                // Mark the initDataHash as used
                $accountStorage.erc7702InitHashes[initDataHash] = true;
            } else {
                Initializable.requireInitializable();
            }
        }
        _initializeAccount(initData);
    }

    function _initializeAccount(bytes calldata initData) internal {
        require(initData.length >= 24, InvalidInitData());

        address bootstrap;
        bytes calldata bootstrapCall;

        assembly {
            bootstrap := calldataload(initData.offset)
            let s := calldataload(add(initData.offset, 0x20))
            let u := add(initData.offset, s)
            bootstrapCall.offset := add(u, 0x20)
            bootstrapCall.length := calldataload(u)
        }

        (bool success,) = bootstrap.delegatecall(bootstrapCall);

        assembly {
            if iszero(success) {
                mstore(0x00, 0x315927c5) // NexusInitializationFailed()
                revert(0x1c, 0x04)
            }
        }
        if (!_amIERC7702()) {
            require(isInitialized(), AccountNotInitialized());
        }
    }

    /// @notice Validates a signature according to ERC-1271 standards.
    /// @param hash The hash of the data being validated.
    /// @param signature Signature data that needs to be validated.
    /// @return The status code of the signature validation (`0x1626ba7e` if valid).
    /// bytes4(keccak256("isValidSignature(bytes32,bytes)") = 0x1626ba7e
    /// @dev Delegates the validation to a validator module specified within the signature data.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view virtual override returns (bytes4) {
        // Handle potential ERC7739 support detection request
        if (signature.length == 0) {
            // Forces the compiler to optimize for smaller bytecode size.
            /// forge-lint:disable-next-line(divide-before-multiply)
            if (uint256(hash) == (~signature.length / 0xffff) * 0x7739) {
                return _checkERC7739Support(hash, signature);
            }
        }
        // else proceed with normal signature verification
        // First 20 bytes of data will be validator address and rest of the bytes is complete signature.
        address validator = _handleValidator(address(bytes20(signature[0:20])));
        bytes memory signature_;
        (hash, signature_) = _withPreValidationHook(hash, signature[20:]);
        try IValidator(validator).isValidSignatureWithSender(msg.sender, hash, signature_) returns (bytes4 res) {
            return res;
        } catch {
            return bytes4(0xffffffff);
        }
    }

    /// @notice Retrieves the address of the current implementation from the EIP-1967 slot.
    /// @notice Checks the 1967 implementation slot, if not found then checks the slot defined by address (Biconomy V2
    /// smart account)
    /// @return implementation The address of the current contract implementation.
    function getImplementation() external view returns (address implementation) {
        assembly {
            implementation := sload(_ERC1967_IMPLEMENTATION_SLOT)
        }
        if (implementation == address(0)) {
            assembly {
                implementation := sload(address())
            }
        }
    }

    /// @notice Checks if a specific module type is supported by this smart account.
    /// @param moduleTypeId The identifier of the module type to check.
    /// @return True if the module type is supported, false otherwise.
    function supportsModule(uint256 moduleTypeId) external view virtual returns (bool) {
        /* MODULE_TYPE_VALIDATOR || MODULE_TYPE_EXECUTOR
        || MODULE_TYPE_FALLBACK || MODULE_TYPE_HOOK
        || MODULE_TYPE_PREVALIDATION_HOOK_ERC1271
        || MODULE_TYPE_PREVALIDATION_HOOK_ERC4337 || MODULE_TYPE_MULTI */
        // Bitmap: 0x31F represents supported module types: 0,1,2,3,4,8,9
        // 0x31F = 0b1100011111 = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<8)|(1<<9)
        /// forge-lint:disable-next-line(incorrect-shift)
        return ((1 << moduleTypeId) & 0x31F) != 0;
    }

    /// @notice Determines if a specific execution mode is supported.
    /// @param mode The execution mode to evaluate.
    /// @return isSupported True if the execution mode is supported, false otherwise.
    function supportsExecutionMode(ExecutionMode mode) external view virtual returns (bool isSupported) {
        (CallType callType, ExecType execType) = mode.decodeBasic();

        // Return true if both the call type and execution type are supported.
        return (callType == CALLTYPE_SINGLE || callType == CALLTYPE_BATCH || callType == CALLTYPE_DELEGATECALL)
            && (execType == EXECTYPE_DEFAULT || execType == EXECTYPE_TRY);
    }

    /// @notice Determines whether a module is installed on the smart account.
    /// @param moduleTypeId The ID corresponding to the type of module (Validator, Executor, Fallback, Hook).
    /// @param module The address of the module to check.
    /// @param additionalContext Optional context that may be needed for certain checks.
    /// @return True if the module is installed, false otherwise.
    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata additionalContext
    )
        external
        view
        returns (bool)
    {
        return _isModuleInstalled(moduleTypeId, module, additionalContext);
    }

    /// @notice Checks if the smart account is initialized.
    /// @return True if the smart account is initialized, false otherwise.
    /// @dev In case default validator is initialized, two other SLOADS from _areSentinelListsInitialized() are not
    /// checked,
    /// this method should not introduce huge gas overhead.
    function isInitialized() public view returns (bool) {
        return (IValidator(_DEFAULT_VALIDATOR).isInitialized(address(this)) || _areSentinelListsInitialized());
    }

    /// Returns the account's implementation ID.
    /// @return The unique identifier for this account implementation.
    function accountId() external pure virtual returns (string memory) {
        return "biconomy.nexus.1.3.1";
    }

    /// Upgrades the contract to a new implementation and calls a function on the new contract.
    /// @notice Updates two slots 1. ERC1967 slot and
    /// 2. address() slot in case if it's potentially upgraded earlier from Biconomy V2 account,
    /// as Biconomy v2 Account (proxy) reads implementation from the slot that is defined by its address
    /// @param newImplementation The address of the new contract implementation.
    /// @param data The calldata to be sent to the new implementation.
    function upgradeToAndCall(address newImplementation, bytes calldata data) public payable virtual override withHook {
        require(newImplementation != address(0), InvalidImplementationAddress());
        bool res;
        assembly {
            res := gt(extcodesize(newImplementation), 0)
        }
        require(res, InvalidImplementationAddress());
        // update the address() storage slot as well
        // This is needed in case the og proxy is Nexus v2 proxy which
        // reads the implementation from the slot defined by its address
        assembly {
            sstore(address(), newImplementation)
        }
        UUPSUpgradeable.upgradeToAndCall(newImplementation, data);
    }

    /// @dev For automatic detection that the smart account supports the ERC7739 workflow
    /// Iterates over all the validators but only if this is a detection request
    /// ERC-7739 spec assumes that if the account doesn't support ERC-7739
    /// it will try to handle the detection request as it was normal sig verification
    /// request and will return 0xffffffff since it won't be able to verify the 0x signature
    /// against 0x7739...7739 hash.
    /// So this approach is consistent with the ERC-7739 spec.
    /// If no validator supports ERC-7739, this function returns false
    /// thus the account will proceed with normal signature verification
    /// and return 0xffffffff as a result.
    function _checkERC7739Support(bytes32 hash, bytes calldata signature) internal view virtual returns (bytes4) {
        bytes4 result;
        unchecked {
            SentinelListLib.SentinelList storage validators = _getAccountStorage().validators;
            address next = validators.entries[SENTINEL];
            while (next != ZERO_ADDRESS && next != SENTINEL) {
                result = _get7739Version(next, result, hash, signature);
                next = validators.getNext(next);
            }
        }
        result = _get7739Version(_DEFAULT_VALIDATOR, result, hash, signature); // check default validator
        return result == bytes4(0) ? bytes4(0xffffffff) : result;
    }

    function _get7739Version(
        address validator,
        bytes4 prevResult,
        bytes32 hash,
        bytes calldata signature
    )
        internal
        view
        returns (bytes4)
    {
        bytes4 support = IValidator(validator).isValidSignatureWithSender(msg.sender, hash, signature);
        /// forge-lint:disable-next-line(unsafe-typecast)
        if (bytes2(support) == bytes2(SUPPORTS_ERC7739) && support > prevResult) {
            return support;
        }
        return prevResult;
    }

    /// @dev Ensures that only authorized callers can upgrade the smart contract implementation.
    /// This is part of the UUPS (Universal Upgradeable Proxy Standard) pattern.
    /// param newImplementation The address of the new implementation to upgrade to.
    function _authorizeUpgrade(
        address /* newImplementation */
    )
        internal
        virtual
        override(UUPSUpgradeable)
        onlyEntryPointOrSelf
    {
        if (_amIERC7702()) {
            revert ERC7702AccountCannotBeUpgradedThisWay();
        }
    }

    /// @dev Handles the PREP initialization.
    /// @param data The packed data to be handled.
    /// @return cleanedSignature The cleaned signature for Nexus 4337 (validateUserOp) flow.
    /// @return initData The data to initialize the account with.
    function _handlePREP(bytes calldata data)
        internal
        returns (bytes calldata cleanedSignature, bytes calldata initData)
    {
        bytes32 saltAndDelegation;
        // unpack the data
        assembly {
            if lt(data.length, 0xf9) {
                mstore(0x0, 0xaed59595) // NotInitializable()
                revert(0x1c, 0x04)
            }

            saltAndDelegation := calldataload(data.offset)

            // initData
            let p := calldataload(add(data.offset, 0x20))
            let u := add(data.offset, p)
            initData.offset := add(u, 0x20)
            initData.length := calldataload(u)

            // cleanedSignature
            p := calldataload(add(data.offset, 0x40))
            u := add(data.offset, p)
            cleanedSignature.offset := add(u, 0x20)
            cleanedSignature.length := calldataload(u)
        }

        // check r is valid
        bytes32 r = LibPREP.rPREP(address(this), keccak256(initData), saltAndDelegation);
        assembly {
            if iszero(r) {
                mstore(0x00, 0xe483bbcb) // revert InvalidPREP()
                revert(0x1c, 0x04)
            }
            // emit PREPInitialized(r)
            mstore(0x00, r)
            log1(0x00, 0x20, 0x4f058962bce244bca6c9be42f256083afc66f1f63a1f9a04e31a3042311af38d)
        }
    }

    // checks if there's at least one validator initialized
    function _checkInitializedValidators() internal view {
        if (!_amIERC7702() && !IValidator(_DEFAULT_VALIDATOR).isInitialized(address(this))) {
            unchecked {
                SentinelListLib.SentinelList storage validators = _getAccountStorage().validators;
                address next = validators.entries[SENTINEL];
                while (next != ZERO_ADDRESS && next != SENTINEL) {
                    if (IValidator(next).isInitialized(address(this))) {
                        break;
                    }
                    next = validators.getNext(next);
                }
                if (next == SENTINEL) {
                    //went through all validators and none was initialized
                    assembly {
                        // revert CanNotRemoveLastValidator()
                        mstore(0x00, 0xcc319d84)
                        revert(0x1c, 0x04)
                    }
                }
            }
        }
    }

    /// @dev EIP712 domain name and version.
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "Nexus";
        version = "1.3.1";
    }
}



// ============================================================
// FILE: contracts/nexus/base/BaseAccount.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { IBaseAccount } from "../../interfaces/nexus/base/IBaseAccount.sol";

/// @title Nexus - BaseAccount
/// @notice Implements ERC-4337 and ERC-7579 standards for account management and access control within the Nexus suite.
/// @dev Manages entry points and configurations as specified in the ERC-4337 and ERC-7579 documentation.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract BaseAccount is IBaseAccount {
    /// @notice The canonical address for the ERC4337 EntryPoint contract, version 0.7.
    /// This address is consistent across all supported networks.
    address internal immutable _ENTRYPOINT;

    /// @dev Ensures the caller is either the EntryPoint or this account itself.
    /// Reverts with AccountAccessUnauthorized if the check fails.
    modifier onlyEntryPointOrSelf() {
        require(msg.sender == _ENTRYPOINT || msg.sender == address(this), AccountAccessUnauthorized());
        _;
    }

    /// @dev Ensures the caller is the EntryPoint.
    /// Reverts with AccountAccessUnauthorized if the check fails.
    modifier onlyEntryPoint() {
        require(msg.sender == _ENTRYPOINT, AccountAccessUnauthorized());
        _;
    }

    /// @dev Sends to the EntryPoint (i.e. `msg.sender`) the missing funds for this transaction.
    /// Subclass MAY override this modifier for better funds management.
    /// (e.g. send to the EntryPoint more than the minimum required, so that in future transactions
    /// it will not be required to send again)
    ///
    /// `missingAccountFunds` is the minimum value this modifier should send the EntryPoint,
    /// which MAY be zero, in case there is enough deposit, or the userOp has a paymaster.
    modifier payPrefund(uint256 missingAccountFunds) virtual {
        _;
        /// @solidity memory-safe-assembly
        assembly {
            if missingAccountFunds {
                // Ignore failure (it's EntryPoint's job to verify, not the account's).
                pop(call(gas(), caller(), missingAccountFunds, codesize(), 0x00, codesize(), 0x00))
            }
        }
    }

    /// @notice Adds deposit to the EntryPoint to fund transactions.
    function addDeposit() external payable virtual {
        address entryPointAddress = _ENTRYPOINT;
        /// @solidity memory-safe-assembly
        assembly {
            // The EntryPoint has balance accounting logic in the `receive()` function.
            if iszero(call(gas(), entryPointAddress, callvalue(), codesize(), 0x00, codesize(), 0x00)) {
                revert(codesize(), 0x00)
            } // For gas estimation.
        }
    }

    /// @notice Withdraws ETH from the EntryPoint to a specified address.
    /// @param to The address to receive the withdrawn funds.
    /// @param amount The amount to withdraw.
    function withdrawDepositTo(address to, uint256 amount) external payable virtual onlyEntryPointOrSelf {
        address entryPointAddress = _ENTRYPOINT;
        assembly {
            let freeMemPtr := mload(0x40) // Store the free memory pointer.
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            mstore(0x00, 0x205c2878000000000000000000000000) // `withdrawTo(address,uint256)`.
            if iszero(call(gas(), entryPointAddress, 0, 0x10, 0x44, codesize(), 0x00)) {
                returndatacopy(freeMemPtr, 0x00, returndatasize())
                revert(freeMemPtr, returndatasize())
            }
            mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    /// @notice Returns the current deposit balance of this account on the EntryPoint.
    /// @return result The current balance held at the EntryPoint.
    function getDeposit() external view virtual returns (uint256 result) {
        address entryPointAddress = _ENTRYPOINT;
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, address()) // Store the `account` argument.
            mstore(0x00, 0x70a08231) // `balanceOf(address)`.
            result := mul(
                // Returns 0 if the EntryPoint does not exist.
                mload(0x20),
                and(
                    // The arguments of `and` are evaluated from right to left.
                    gt(returndatasize(), 0x1f), // At least 32 bytes returned.
                    staticcall(gas(), entryPointAddress, 0x1c, 0x24, 0x20, 0x20)
                )
            )
        }
    }

    /// @notice Retrieves the address of the EntryPoint contract, currently using version 0.7.
    /// @dev This function returns the address of the canonical ERC4337 EntryPoint contract.
    /// It can be overridden to return a different EntryPoint address if needed.
    /// @return The address of the EntryPoint contract.
    function entryPoint() external view returns (address) {
        return _ENTRYPOINT;
    }
}



// ============================================================
// FILE: contracts/nexus/base/ModuleManager.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { SentinelListLib } from "sentinellist/SentinelList.sol";
import { Storage } from "./Storage.sol";
import {
    IModule,
    IValidator,
    IExecutor,
    IHook,
    IPreValidationHookERC1271,
    IPreValidationHookERC4337,
    IFallback
} from "erc7579/interfaces/IERC7579Module.sol";
import { CallType, CALLTYPE_SINGLE, CALLTYPE_STATIC } from "../../lib/erc-7579/ModeLib.sol";
import { ExecLib } from "../../lib/erc-7579/ExecLib.sol";
import { LocalCallDataParserLib } from "../../lib/nexus/local/LocalCallDataParserLib.sol";
import { IModuleManager } from "../../interfaces/nexus/base/IModuleManager.sol";
// solhint-disable no-unused-import
import {
    MODULE_TYPE_VALIDATOR,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_PREVALIDATION_HOOK_ERC1271,
    MODULE_TYPE_PREVALIDATION_HOOK_ERC4337,
    MODULE_TYPE_MULTI,
    MODULE_ENABLE_MODE_TYPE_HASH,
    EMERGENCY_UNINSTALL_TYPE_HASH,
    ERC1271_SUCCESS
} from "../../types/Constants.sol";
// solhint-enable no-unused-import
import { EIP712 } from "solady/utils/EIP712.sol";
import { ExcessivelySafeCall } from "excessively-safe-call/ExcessivelySafeCall.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { EmergencyUninstall } from "../../types/DataTypes.sol";

/// @title Nexus - ModuleManager
/// @notice Manages Validator, Executor, Hook, and Fallback modules within the Nexus suite, supporting
/// @dev Implements SentinelList for managing modules via a linked list structure, adhering to ERC-7579.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
abstract contract ModuleManager is Storage, EIP712, IModuleManager {
    using SentinelListLib for SentinelListLib.SentinelList;
    using LocalCallDataParserLib for bytes;
    using ExecLib for address;
    using ExcessivelySafeCall for address;

    /// @dev The default validator address.
    /// @notice To explicitly initialize the default validator, Nexus.execute(_DEFAULT_VALIDATOR.onInstall(...)) should
    /// be
    /// called.
    address internal immutable _DEFAULT_VALIDATOR;

    /// @notice Ensures the message sender is a registered executor module.
    modifier onlyExecutorModule() virtual {
        require(_getAccountStorage().executors.contains(msg.sender), InvalidModule(msg.sender));
        _;
    }

    /// @notice Does pre-checks and post-checks using an installed hook on the account.
    /// @dev sender, msg.data and msg.value is passed to the hook to implement custom flows.
    modifier withHook() {
        address hook = _getHook();
        if (hook == address(0)) {
            _;
        } else {
            bytes memory hookData = IHook(hook).preCheck(msg.sender, msg.value, msg.data);
            _;
            IHook(hook).postCheck(hookData);
        }
    }

    /// @dev initData should block the implementation from being used as a Smart Account
    constructor(address defaultValidator_, bytes memory initData_) {
        if (!IValidator(defaultValidator_).isModuleType(MODULE_TYPE_VALIDATOR)) {
            revert MismatchModuleTypeId();
        }
        IValidator(defaultValidator_).onInstall(initData_);
        _DEFAULT_VALIDATOR = defaultValidator_;
    }

    // receive function
    receive() external payable { }

    /// @dev Fallback function to manage incoming calls using designated handlers based on the call type.
    /// Hooked manually in the _fallback function
    fallback() external payable {
        _fallback(msg.data);
    }

    /// @dev Retrieves the default validator address.
    /// @return The address of the default validator.
    function getDefaultValidator() external view returns (address) {
        return _DEFAULT_VALIDATOR;
    }

    /// @dev Retrieves a paginated list of validator addresses from the linked list.
    /// This utility function is not defined by the ERC-7579 standard and is implemented to facilitate
    /// easier management and retrieval of large sets of validator modules.
    /// @param cursor The address to start pagination from, or zero to start from the first entry.
    /// @param size The number of validator addresses to return.
    /// @return array An array of validator addresses.
    /// @return next The address to use as a cursor for the next page of results.
    function getValidatorsPaginated(
        address cursor,
        uint256 size
    )
        external
        view
        returns (address[] memory array, address next)
    {
        (array, next) = _paginate(_getAccountStorage().validators, cursor, size);
    }

    /// @dev Retrieves a paginated list of executor addresses from the linked list.
    /// This utility function is not defined by the ERC-7579 standard and is implemented to facilitate
    /// easier management and retrieval of large sets of executor modules.
    /// @param cursor The address to start pagination from, or zero to start from the first entry.
    /// @param size The number of executor addresses to return.
    /// @return array An array of executor addresses.
    /// @return next The address to use as a cursor for the next page of results.
    function getExecutorsPaginated(
        address cursor,
        uint256 size
    )
        external
        view
        returns (address[] memory array, address next)
    {
        (array, next) = _paginate(_getAccountStorage().executors, cursor, size);
    }

    /// @notice Retrieves the currently active hook address.
    /// @return hook The address of the active hook module.
    function getActiveHook() external view returns (address hook) {
        return _getHook();
    }

    /// @notice Fetches the fallback handler for a specific selector.
    /// @param selector The function selector to query.
    /// @return calltype The type of call that the handler manages.
    /// @return handler The address of the fallback handler.
    function getFallbackHandlerBySelector(bytes4 selector) external view returns (CallType, address) {
        FallbackHandler memory handler = _getAccountStorage().fallbacks[selector];
        return (handler.calltype, handler.handler);
    }

    /// @dev Initializes the module manager by setting up default states for validators and executors.
    function _initSentinelLists() internal virtual {
        // account module storage
        AccountStorage storage ams = _getAccountStorage();
        ams.executors.init();
        ams.validators.init();
    }

    /// @dev Implements Module Enable Mode flow.
    /// @param packedData Data source to parse data required to perform Module Enable mode from.
    /// @return userOpSignature the clean signature which can be further used for userOp validation
    function _enableMode(
        bytes32 userOpHash,
        bytes calldata packedData
    )
        internal
        returns (bytes calldata userOpSignature)
    {
        address module;
        uint256 moduleType;
        bytes calldata moduleInitData;
        bytes calldata enableModeSignature;

        (module, moduleType, moduleInitData, enableModeSignature, userOpSignature) = packedData.parseEnableModeData();

        address enableModeSigValidator = _handleValidator(address(bytes20(enableModeSignature[0:20])));

        enableModeSignature = enableModeSignature[20:];

        bytes32 structHash = _getEnableModeDataHash(module, moduleType, userOpHash, moduleInitData);
        bool isValid = _checkEnableModeSignature(structHash, enableModeSignature, enableModeSigValidator);

        assembly {
            if iszero(isValid) {
                // revert EnableModeSigError()
                mstore(0x00, 0x46fdc333)
                revert(0x1c, 0x04)
            }
        }

        this.installModule(moduleType, module, moduleInitData);
    }

    /// @notice Installs a new module to the smart account.
    /// @param moduleTypeId The type identifier of the module being installed, which determines its role:
    /// - 0 for MultiType
    /// - 1 for Validator
    /// - 2 for Executor
    /// - 3 for Fallback
    /// - 4 for Hook
    /// - 8 for PreValidationHookERC1271
    /// - 9 for PreValidationHookERC4337
    /// @param module The address of the module to install.
    /// @param initData Initialization data for the module.
    /// @dev This function goes through hook checks via withHook modifier.
    /// @dev No need to check that the module is already installed, as this check is done
    /// when trying to sstore the module in an appropriate SentinelList
    function _installModule(uint256 moduleTypeId, address module, bytes calldata initData) internal {
        if (!_areSentinelListsInitialized()) {
            _initSentinelLists();
        }
        if (module == address(0)) revert ModuleAddressCanNotBeZero();
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            _installValidator(module, initData);
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            _installExecutor(module, initData);
        } else if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            _installFallbackHandler(module, initData);
        } else if (moduleTypeId == MODULE_TYPE_HOOK) {
            _installHook(module, initData);
        } else if (_isPrevalidationHookType(moduleTypeId)) {
            _installPreValidationHook(moduleTypeId, module, initData);
        } else if (moduleTypeId == MODULE_TYPE_MULTI) {
            _multiTypeInstall(module, initData);
        } else {
            revert InvalidModuleTypeId(moduleTypeId);
        }
    }

    /// @dev Installs a new validator module after checking if it matches the required module type.
    /// @param validator The address of the validator module to be installed.
    /// @param data Initialization data to configure the validator upon installation.
    function _installValidator(address validator, bytes calldata data) internal virtual withHook {
        if (!IValidator(validator).isModuleType(MODULE_TYPE_VALIDATOR)) revert MismatchModuleTypeId();
        if (validator == _DEFAULT_VALIDATOR) {
            revert DefaultValidatorAlreadyInstalled();
        }
        _getAccountStorage().validators.push(validator);
        IValidator(validator).onInstall(data);
    }

    /// @dev Uninstalls a validator module.
    /// @param validator The address of the validator to be uninstalled.
    /// @param data De-initialization data to configure the validator upon uninstallation.
    function _uninstallValidator(address validator, bytes calldata data) internal virtual {
        SentinelListLib.SentinelList storage validators = _getAccountStorage().validators;

        (address prev, bytes memory disableModuleData) = abi.decode(data, (address, bytes));

        // Perform the removal first
        validators.pop(prev, validator);

        validator.excessivelySafeCall(
            gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, disableModuleData)
        );
    }

    /// @dev Installs a new executor module after checking if it matches the required module type.
    /// @param executor The address of the executor module to be installed.
    /// @param data Initialization data to configure the executor upon installation.
    function _installExecutor(address executor, bytes calldata data) internal virtual withHook {
        if (!IExecutor(executor).isModuleType(MODULE_TYPE_EXECUTOR)) revert MismatchModuleTypeId();
        _getAccountStorage().executors.push(executor);
        IExecutor(executor).onInstall(data);
    }

    /// @dev Uninstalls an executor module by removing it from the executors list.
    /// @param executor The address of the executor to be uninstalled.
    /// @param data De-initialization data to configure the executor upon uninstallation.
    function _uninstallExecutor(address executor, bytes calldata data) internal virtual {
        (address prev, bytes memory disableModuleData) = abi.decode(data, (address, bytes));
        _getAccountStorage().executors.pop(prev, executor);
        executor.excessivelySafeCall(
            gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, disableModuleData)
        );
    }

    /// @dev Installs a hook module, ensuring no other hooks are installed before proceeding.
    /// @param hook The address of the hook to be installed.
    /// @param data Initialization data to configure the hook upon installation.
    function _installHook(address hook, bytes calldata data) internal virtual withHook {
        if (!IHook(hook).isModuleType(MODULE_TYPE_HOOK)) revert MismatchModuleTypeId();
        address currentHook = _getHook();
        require(currentHook == address(0), HookAlreadyInstalled(currentHook));
        _setHook(hook);
        IHook(hook).onInstall(data);
    }

    /// @dev Uninstalls a hook module, ensuring the current hook matches the one intended for uninstallation.
    /// @param hook The address of the hook to be uninstalled.
    /// @param hookType The type of the hook to be uninstalled.
    /// @param data De-initialization data to configure the hook upon uninstallation.
    function _uninstallHook(address hook, uint256 hookType, bytes calldata data) internal virtual {
        if (hookType == MODULE_TYPE_HOOK) {
            _setHook(address(0));
        } else if (_isPrevalidationHookType(hookType)) {
            _uninstallPreValidationHook(hookType);
        }
        hook.excessivelySafeCall(gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, data));
    }

    /// @dev Sets the current hook in the storage to the specified address.
    /// @param hook The new hook address.
    function _setHook(address hook) internal virtual {
        _getAccountStorage().hook = IHook(hook);
    }

    /// @dev Installs a fallback handler for a given selector with initialization data.
    /// @param handler The address of the fallback handler to install.
    /// @param params The initialization parameters including the selector and call type.
    function _installFallbackHandler(address handler, bytes calldata params) internal virtual withHook {
        if (!IFallback(handler).isModuleType(MODULE_TYPE_FALLBACK)) revert MismatchModuleTypeId();
        // Extract the function selector from the provided parameters.
        bytes4 selector = bytes4(params[0:4]);

        // Extract the call type from the provided parameters.
        CallType calltype = CallType.wrap(bytes1(params[4]));

        require(calltype == CALLTYPE_SINGLE || calltype == CALLTYPE_STATIC, FallbackCallTypeInvalid());

        // Extract the initialization data from the provided parameters.
        bytes memory initData = params[5:];

        // Revert if the selector is either `onInstall(bytes)` (0x6d61fe70) or `onUninstall(bytes)` (0x8a91b0e3) or
        // explicit bytes(0).
        // These selectors are explicitly forbidden to prevent security vulnerabilities.
        // Allowing these selectors would enable unauthorized users to uninstall and reinstall critical modules.
        // If a validator module is uninstalled and reinstalled without proper authorization, it can compromise
        // the account's security and integrity. By restricting these selectors, we ensure that the fallback handler
        // cannot be manipulated to disrupt the expected behavior and security of the account.
        require(
            !(selector == bytes4(0x6d61fe70) || selector == bytes4(0x8a91b0e3) || selector == bytes4(0)),
            FallbackSelectorForbidden()
        );

        // Revert if a fallback handler is already installed for the given selector.
        // This check ensures that we do not overwrite an existing fallback handler, which could lead to unexpected
        // behavior.
        require(!_isFallbackHandlerInstalled(selector), FallbackAlreadyInstalledForSelector(selector));

        // Store the fallback handler and its call type in the account storage.
        // This maps the function selector to the specified fallback handler and call type.
        _getAccountStorage().fallbacks[selector] = FallbackHandler(handler, calltype);

        // Invoke the `onInstall` function of the fallback handler with the provided initialization data.
        // This step allows the fallback handler to perform any necessary setup or initialization.
        IFallback(handler).onInstall(initData);
    }

    /// @dev Uninstalls a fallback handler for a given selector.
    /// @param fallbackHandler The address of the fallback handler to uninstall.
    /// @param data The de-initialization data containing the selector.
    function _uninstallFallbackHandler(address fallbackHandler, bytes calldata data) internal virtual {
        _getAccountStorage().fallbacks[bytes4(data[0:4])] = FallbackHandler(address(0), CallType.wrap(0x00));
        fallbackHandler.excessivelySafeCall(
            gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, data[4:])
        );
    }

    /// @dev Installs a pre-validation hook module, ensuring no other pre-validation hooks are installed before
    /// proceeding.
    /// @param preValidationHookType The type of the pre-validation hook.
    /// @param preValidationHook The address of the pre-validation hook to be installed.
    /// @param data Initialization data to configure the hook upon installation.
    function _installPreValidationHook(
        uint256 preValidationHookType,
        address preValidationHook,
        bytes calldata data
    )
        internal
        virtual
        withHook
    {
        if (!IModule(preValidationHook).isModuleType(preValidationHookType)) revert MismatchModuleTypeId();
        address currentPreValidationHook = _getPreValidationHook(preValidationHookType);
        require(currentPreValidationHook == address(0), PrevalidationHookAlreadyInstalled(currentPreValidationHook));
        _setPreValidationHook(preValidationHookType, preValidationHook);
        IModule(preValidationHook).onInstall(data);
    }

    /// @dev Uninstalls a pre-validation hook module
    /// @param hookType The type of the pre-validation hook.
    function _uninstallPreValidationHook(uint256 hookType) internal virtual {
        _setPreValidationHook(hookType, address(0));
    }

    /// @dev Sets the current pre-validation hook in the storage to the specified address, based on the hook type.
    /// @param hookType The type of the pre-validation hook.
    /// @param hook The new hook address.
    function _setPreValidationHook(uint256 hookType, address hook) internal virtual {
        if (hookType == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271) {
            _getAccountStorage().preValidationHookERC1271 = IPreValidationHookERC1271(hook);
        } else if (hookType == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337) {
            _getAccountStorage().preValidationHookERC4337 = IPreValidationHookERC4337(hook);
        }
    }

    /// @notice Installs a module with multiple types in a single operation.
    /// @dev This function handles installing a multi-type module by iterating through each type and initializing it.
    /// The initData should include an ABI-encoded tuple of (uint[] types, bytes[] initDatas).
    /// @param module The address of the multi-type module.
    /// @param initData Initialization data for each type within the module.
    function _multiTypeInstall(address module, bytes calldata initData) internal virtual {
        (uint256[] calldata types, bytes[] calldata initDatas) = initData.parseMultiTypeInitData();

        uint256 length = types.length;
        if (initDatas.length != length) revert InvalidInput();

        // iterate over all module types and install the module as a type accordingly
        for (uint256 i; i < length; i++) {
            uint256 theType = types[i];

            /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
            /*                      INSTALL VALIDATORS                    */
            /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
            if (theType == MODULE_TYPE_VALIDATOR) {
                _installValidator(module, initDatas[i]);
            }
            /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
            /*                       INSTALL EXECUTORS                    */
            /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
            else if (theType == MODULE_TYPE_EXECUTOR) {
                _installExecutor(module, initDatas[i]);
            }
            /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
            /*                       INSTALL FALLBACK                     */
            /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
            else if (theType == MODULE_TYPE_FALLBACK) {
                _installFallbackHandler(module, initDatas[i]);
            }
            /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
            /*          INSTALL HOOK (global only, not sig-specific)      */
            /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
            else if (theType == MODULE_TYPE_HOOK) {
                _installHook(module, initDatas[i]);
            }
            /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
            /*          INSTALL PRE-VALIDATION HOOK                       */
            /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
            else if (_isPrevalidationHookType(theType)) {
                _installPreValidationHook(theType, module, initDatas[i]);
            }
        }
    }

    /// @notice Checks if an emergency uninstall signature is valid.
    /// @param data The emergency uninstall data.
    /// @param signature The signature to validate.
    function _checkEmergencyUninstallSignature(EmergencyUninstall calldata data, bytes calldata signature) internal {
        address validator = _handleValidator(address(bytes20(signature[0:20])));
        // Hash the data
        bytes32 hash = _hashTypedData(
            keccak256(
                abi.encode(
                    EMERGENCY_UNINSTALL_TYPE_HASH, data.hook, data.hookType, keccak256(data.deInitData), data.nonce
                )
            )
        );
        // Check if nonce is valid
        require(!_getAccountStorage().nonces[data.nonce], InvalidNonce());
        // Mark nonce as used
        _getAccountStorage().nonces[data.nonce] = true;
        // Check if the signature is valid
        require(
            (IValidator(validator).isValidSignatureWithSender(address(this), hash, signature[20:]) == ERC1271_SUCCESS),
            EmergencyUninstallSigError()
        );
    }

    /// @dev Calls the pre-validation hook for ERC-4337.
    /// @param hash The hash of the user operation.
    /// @param userOp The user operation data.
    /// @param missingAccountFunds The amount of missing account funds.
    /// @return postHash The updated hash after the pre-validation hook.
    /// @return postSig The updated signature after the pre-validation hook.
    function _withPreValidationHook(
        bytes32 hash,
        PackedUserOperation memory userOp,
        uint256 missingAccountFunds
    )
        internal
        virtual
        returns (bytes32 postHash, bytes memory postSig)
    {
        // Get the pre-validation hook for ERC-4337
        address preValidationHook = _getPreValidationHook(MODULE_TYPE_PREVALIDATION_HOOK_ERC4337);
        // If no pre-validation hook is installed, return the original hash and signature
        if (preValidationHook == address(0)) {
            return (hash, userOp.signature);
        }
        // Otherwise, call the pre-validation hook and return the updated hash and signature
        else {
            return
                IPreValidationHookERC4337(preValidationHook).preValidationHookERC4337(userOp, missingAccountFunds, hash);
        }
    }

    /// @dev Retrieves the pre-validation hook from the storage based on the hook type.
    /// @param preValidationHookType The type of the pre-validation hook.
    /// @return preValidationHook The address of the pre-validation hook.
    function _getPreValidationHook(uint256 preValidationHookType) internal view returns (address preValidationHook) {
        preValidationHook = preValidationHookType == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271
            ? address(_getAccountStorage().preValidationHookERC1271)
            : address(_getAccountStorage().preValidationHookERC4337);
    }

    /// @dev Calls the pre-validation hook for ERC-1271.
    /// @param hash The hash of the user operation.
    /// @param signature The signature to validate.
    /// @return postHash The updated hash after the pre-validation hook.
    /// @return postSig The updated signature after the pre-validation hook.
    function _withPreValidationHook(
        bytes32 hash,
        bytes calldata signature
    )
        internal
        view
        virtual
        returns (bytes32 postHash, bytes memory postSig)
    {
        // Get the pre-validation hook for ERC-1271
        address preValidationHook = _getPreValidationHook(MODULE_TYPE_PREVALIDATION_HOOK_ERC1271);
        // If no pre-validation hook is installed, return the original hash and signature
        if (preValidationHook == address(0)) {
            return (hash, signature);
        }
        // Otherwise, call the pre-validation hook and return the updated hash and signature
        else {
            return IPreValidationHookERC1271(preValidationHook).preValidationHookERC1271(msg.sender, hash, signature);
        }
    }

    /// @notice Checks if an enable mode signature is valid.
    /// @param structHash data hash.
    /// @param sig Signature.
    /// @param validator Validator address.
    function _checkEnableModeSignature(
        bytes32 structHash,
        bytes calldata sig,
        address validator
    )
        internal
        view
        returns (bool)
    {
        bytes32 eip712Digest = _hashTypedData(structHash);
        // Use standard IERC-1271/ERC-7739 interface.
        // Even if the validator doesn't support 7739 under the hood, it is still secure,
        // as eip712digest is already built based on 712Domain of this Smart Account
        // This interface should always be exposed by validators as per ERC-7579
        try IValidator(validator).isValidSignatureWithSender(address(this), eip712Digest, sig) returns (bytes4 res) {
            return res == ERC1271_SUCCESS;
        } catch {
            return false;
        }
    }

    /// @notice Checks if a module is installed on the smart account.
    /// @param moduleTypeId The module type ID.
    /// @param module The module address.
    /// @param additionalContext Additional context for checking installation.
    /// @return True if the module is installed, false otherwise.
    function _isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata additionalContext
    )
        internal
        view
        returns (bool)
    {
        additionalContext;
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            return _isValidatorInstalled(module);
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            return _isExecutorInstalled(module);
        } else if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            bytes4 selector;
            if (additionalContext.length >= 4) {
                selector = bytes4(additionalContext[0:4]);
            } else {
                selector = bytes4(0x00000000);
            }
            return _isFallbackHandlerInstalled(selector, module);
        } else if (moduleTypeId == MODULE_TYPE_HOOK) {
            return _isHookInstalled(module);
        } else if (_isPrevalidationHookType(moduleTypeId)) {
            return _getPreValidationHook(moduleTypeId) == module;
        } else {
            return false;
        }
    }

    /// @dev Does bytecode optimized check of the module type id being a pre-validation hook type.
    /// @param moduleTypeId The module type id to check.
    /// return True if the module type id is a pre-validation hook type, otherwise false.
    /// If theType == 8: 8 - 8 = 0, and 0 < 2 ✓
    /// If theType == 9: 9 - 8 = 1, and 1 < 2 ✓
    /// If theType < 8 (e.g., 7): 7 - 8 = type(uint256).max (wraps), and type(uint256).max < 2 is false ✓
    /// If theType >= 10: result is >= 2, and fails the check ✓
    function _isPrevalidationHookType(uint256 moduleTypeId) internal pure returns (bool res) {
        assembly {
            res := lt(sub(moduleTypeId, 8), 2)
        }
    }

    /// @dev Checks if the validator list is already initialized.
    ///      In theory it doesn't 100% mean there is a validator or executor installed.
    ///      Use below functions to check for validators and executors.
    function _areSentinelListsInitialized() internal view virtual returns (bool) {
        // account module storage
        AccountStorage storage ams = _getAccountStorage();
        return ams.validators.alreadyInitialized() && ams.executors.alreadyInitialized();
    }

    /// @dev Checks if a fallback handler is set for a given selector.
    /// @param selector The function selector to check.
    /// @return True if a fallback handler is set, otherwise false.
    function _isFallbackHandlerInstalled(bytes4 selector) internal view virtual returns (bool) {
        FallbackHandler storage handler = _getAccountStorage().fallbacks[selector];
        return handler.handler != address(0);
    }

    /// @dev Checks if the expected fallback handler is installed for a given selector.
    /// @param selector The function selector to check.
    /// @param expectedHandler The address of the handler expected to be installed.
    /// @return True if the installed handler matches the expected handler, otherwise false.
    function _isFallbackHandlerInstalled(bytes4 selector, address expectedHandler) internal view returns (bool) {
        FallbackHandler storage handler = _getAccountStorage().fallbacks[selector];
        return handler.handler == expectedHandler;
    }

    /// @dev Checks if a validator is currently installed.
    /// @param validator The address of the validator to check.
    /// @return True if the validator is installed, otherwise false.
    function _isValidatorInstalled(address validator) internal view virtual returns (bool) {
        return _getAccountStorage().validators.contains(validator);
    }

    /// @dev Checks if an executor is currently installed.
    /// @param executor The address of the executor to check.
    /// @return True if the executor is installed, otherwise false.
    function _isExecutorInstalled(address executor) internal view virtual returns (bool) {
        return _getAccountStorage().executors.contains(executor);
    }

    /// @dev Checks if a hook is currently installed.
    /// @param hook The address of the hook to check.
    /// @return True if the hook is installed, otherwise false.
    function _isHookInstalled(address hook) internal view returns (bool) {
        return _getHook() == hook;
    }

    /// @dev Retrieves the current hook from the storage.
    /// @return hook The address of the current hook.
    function _getHook() internal view returns (address hook) {
        hook = address(_getAccountStorage().hook);
    }

    /// @dev Checks if the account is an ERC7702 account
    function _amIERC7702() internal view returns (bool res) {
        assembly {
            // use extcodesize as the first cheapest check
            if eq(extcodesize(address()), 23) {
                // use extcodecopy to copy first 3 bytes of this contract and compare with 0xef0100
                extcodecopy(address(), 0, 0, 3)
                res := eq(0xef0100, shr(232, mload(0x00)))
            }
            // if it is not 23, we do not even check the first 3 bytes
        }
    }

    /// @dev Returns the validator address to use
    function _handleValidator(address _validator) internal view returns (address validator) {
        if (_validator == address(0)) {
            validator = _DEFAULT_VALIDATOR;
        } else {
            if (!_isValidatorInstalled(_validator)) {
                assembly {
                    // revert ValidatorNotInstalled(address)
                    mstore(0x00, 0x6859e01e)
                    mstore(0x20, _validator)
                    revert(0x1c, 0x24)
                }
            }
            validator = _validator;
        }
    }

    /// @notice Builds the enable mode data hash as per eip712
    /// @param module Module being enabled
    /// @param moduleType Type of the module as per EIP-7579
    /// @param userOpHash Hash of the User Operation
    /// @param initData Module init data.
    /// @return structHash data hash
    function _getEnableModeDataHash(
        address module,
        uint256 moduleType,
        bytes32 userOpHash,
        bytes calldata initData
    )
        internal
        pure
        returns (bytes32)
    {
        bytes32 structHash;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, MODULE_ENABLE_MODE_TYPE_HASH)
            mstore(add(ptr, 0x20), module)
            mstore(add(ptr, 0x40), moduleType)
            mstore(add(ptr, 0x60), userOpHash)

            // Hash initData and store at ptr + 0x80
            // calldatacopy to copy initData to memory, then hash it
            let initDataPtr := add(ptr, 0xa0)
            calldatacopy(initDataPtr, initData.offset, initData.length)
            let initDataHash := keccak256(initDataPtr, initData.length)
            mstore(add(ptr, 0x80), initDataHash)

            // Hash the entire struct
            structHash := keccak256(ptr, 0xa0)
        }
        return structHash;
    }

    function _fallback(bytes calldata callData) private {
        bool success;
        bytes memory result;
        FallbackHandler storage $fallbackHandler = _getAccountStorage().fallbacks[msg.sig];
        address handler = $fallbackHandler.handler;
        CallType calltype = $fallbackHandler.calltype;

        if (handler != address(0)) {
            // hook manually
            address hook = _getHook();
            bytes memory hookData;
            if (hook != address(0)) {
                hookData = IHook(hook).preCheck(msg.sender, msg.value, msg.data);
            }
            //if there's a fallback handler, call it
            if (calltype == CALLTYPE_STATIC) {
                (success, result) = handler.staticcall(ExecLib.get2771CallData(callData));
            } else if (calltype == CALLTYPE_SINGLE) {
                (success, result) = handler.call{ value: msg.value }(ExecLib.get2771CallData(callData));
            } else {
                revert UnsupportedCallType(calltype);
            }

            // Use revert message from fallback handler if the call was not successful
            assembly {
                if iszero(success) { revert(add(result, 0x20), mload(result)) }
            }

            // hook post check
            if (hook != address(0)) {
                IHook(hook).postCheck(hookData);
            }

            // return the result
            assembly {
                return(add(result, 0x20), mload(result))
            }
        }

        // If there's no handler, the call can be one of onERCXXXReceived()
        // No need to hook this as no execution is done here
        bytes32 s;
        /// @solidity memory-safe-assembly
        assembly {
            s := shr(224, calldataload(0))
            // 0x150b7a02: `onERC721Received(address,address,uint256,bytes)`.
            // 0xf23a6e61: `onERC1155Received(address,address,uint256,uint256,bytes)`.
            // 0xbc197c81: `onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)`.
            if or(eq(s, 0x150b7a02), or(eq(s, 0xf23a6e61), eq(s, 0xbc197c81))) {
                mstore(0x20, s) // Store `msg.sig`.
                return(0x3c, 0x20) // Return `msg.sig`.
            }
            mstore(0x00, 0x08c63e27)
            mstore(0x20, shl(224, s)) // Left-align bytes4 for ABI encoding
            revert(0x1c, 0x24) // revert MissingFallbackHandler(msg.sig)
        }
    }

    /// @dev Helper function to paginate entries in a SentinelList.
    /// @param list The SentinelList to paginate.
    /// @param cursor The cursor to start paginating from.
    /// @param size The number of entries to return.
    /// @return array The array of addresses in the list.
    /// @return nextCursor The cursor for the next page of entries.
    function _paginate(
        SentinelListLib.SentinelList storage list,
        address cursor,
        uint256 size
    )
        private
        view
        returns (address[] memory array, address nextCursor)
    {
        (array, nextCursor) = list.getEntriesPaginated(cursor, size);
    }
}



// ============================================================
// FILE: contracts/nexus/base/ExecutionHelper.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { Execution } from "erc7579/interfaces/IERC7579Account.sol";
import { IExecutionHelperEventsAndErrors } from "../../interfaces/nexus/base/IExecutionHelper.sol";
import { ExecType, EXECTYPE_DEFAULT, EXECTYPE_TRY } from "../../lib/erc-7579/ModeLib.sol";
import { ExecLib } from "../../lib/erc-7579/ExecLib.sol";

/// @title Nexus - ExecutionHelper
/// @notice Implements execution management within the Nexus suite, facilitating transaction execution strategies and
/// error handling.
/// @dev Provides mechanisms for direct and batched transactions with both committed and tentative execution strategies
/// as per ERC-4337 and ERC-7579 standards.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract ExecutionHelper is IExecutionHelperEventsAndErrors {
    using ExecLib for bytes;

    /// @notice Executes a call to a target address with specified value and data.
    /// @notice calls to an EOA should be counted as successful.
    /// @param target The address to execute the call on.
    /// @param value The amount of wei to send with the call.
    /// @param callData The calldata to send.
    /// @return result The bytes returned from the execution, which contains the returned data from the target address.
    function _execute(
        address target,
        uint256 value,
        bytes calldata callData
    )
        internal
        virtual
        returns (bytes memory result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            calldatacopy(result, callData.offset, callData.length)
            if iszero(call(gas(), target, value, result, callData.length, codesize(), 0x00)) {
                // Bubble up the revert if the call reverts.
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            mstore(result, returndatasize()) // Store the length.
            let o := add(result, 0x20)
            returndatacopy(o, 0x00, returndatasize()) // Copy the returndata.
            mstore(0x40, add(o, returndatasize())) // Allocate the memory.
        }
    }

    /// @notice Executes a call to a target address with specified value and data.
    /// same as _execute, but callData can be in memory
    function _executeMemory(
        address target,
        uint256 value,
        bytes memory callData
    )
        internal
        virtual
        returns (bytes memory result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            if iszero(call(gas(), target, value, add(callData, 0x20), mload(callData), codesize(), 0x00)) {
                // Bubble up the revert if the call reverts.
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            mstore(result, returndatasize()) // Store the length.
            let o := add(result, 0x20)
            returndatacopy(o, 0x00, returndatasize()) // Copy the returndata.
            mstore(0x40, add(o, returndatasize())) // Allocate the memory.
        }
    }

    /// @notice Executes a call to a target address with specified value and data.
    /// Same as _execute but without return data for gas optimization.
    function _executeNoReturndata(address target, uint256 value, bytes calldata callData) internal virtual {
        /// @solidity memory-safe-assembly
        assembly {
            let result := mload(0x40)
            calldatacopy(result, callData.offset, callData.length)
            if iszero(call(gas(), target, value, result, callData.length, codesize(), 0x00)) {
                // Bubble up the revert if the call reverts.
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            mstore(0x40, add(result, callData.length)) //allocate memory
        }
    }

    /// @notice Tries to execute a call and captures if it was successful or not.
    /// @dev Similar to _execute but returns a success boolean and catches reverts instead of propagating them.
    /// @notice calls to an EOA should be counted as successful.
    /// @param target The address to execute the call on.
    /// @param value The amount of wei to send with the call.
    /// @param callData The calldata to send.
    /// @return success True if the execution was successful, false otherwise.
    /// @return result The bytes returned from the execution, which contains the returned data from the target address.
    function _tryExecute(
        address target,
        uint256 value,
        bytes calldata callData
    )
        internal
        virtual
        returns (bool success, bytes memory result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            calldatacopy(result, callData.offset, callData.length)
            success := call(gas(), target, value, result, callData.length, codesize(), 0x00)
            mstore(result, returndatasize()) // Store the length.
            let o := add(result, 0x20)
            returndatacopy(o, 0x00, returndatasize()) // Copy the returndata.
            mstore(0x40, add(o, returndatasize())) // Allocate the memory.
        }
    }

    /// @notice Executes a batch of calls.
    /// @param executions An array of Execution structs each containing target, value, and calldata.
    /// @return result An array of bytes returned from each executed call, corresponding to the returndata from each
    /// target
    /// address.
    function _executeBatch(Execution[] calldata executions) internal returns (bytes[] memory result) {
        result = new bytes[](executions.length);

        Execution calldata exec;
        for (uint256 i; i < executions.length; i++) {
            exec = executions[i];
            result[i] = _execute(exec.target, exec.value, exec.callData);
        }
    }

    /// @notice Executes a batch of calls without returning the result.
    /// @param executions An array of Execution structs each containing target, value, and calldata.
    function _executeBatchNoReturndata(Execution[] calldata executions) internal {
        Execution calldata exec;
        for (uint256 i; i < executions.length; i++) {
            exec = executions[i];
            _executeNoReturndata(exec.target, exec.value, exec.callData);
        }
    }

    /// @notice Tries to execute a batch of calls and emits an event for each unsuccessful call.
    /// @param executions An array of Execution structs.
    /// @return result An array of bytes returned from each executed call, with unsuccessful calls marked by events.
    function _tryExecuteBatch(Execution[] calldata executions) internal returns (bytes[] memory result) {
        result = new bytes[](executions.length);

        Execution calldata exec;
        for (uint256 i; i < executions.length; i++) {
            exec = executions[i];
            bool success;
            (success, result[i]) = _tryExecute(exec.target, exec.value, exec.callData);
            if (!success) emit TryExecuteUnsuccessful(exec.callData, result[i]);
        }
    }

    /// @dev Execute a delegatecall with `delegate` on this account.
    /// @return result The bytes returned from the delegatecall, which contains the returned data from the delegate
    /// contract.
    function _executeDelegatecall(address delegate, bytes calldata callData) internal returns (bytes memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            calldatacopy(result, callData.offset, callData.length)
            // Forwards the `data` to `delegate` via delegatecall.
            if iszero(delegatecall(gas(), delegate, result, callData.length, codesize(), 0x00)) {
                // Bubble up the revert if the call reverts.
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            mstore(result, returndatasize()) // Store the length.
            let o := add(result, 0x20)
            returndatacopy(o, 0x00, returndatasize()) // Copy the returndata.
            mstore(0x40, add(o, returndatasize())) // Allocate the memory.
        }
    }

    /// @dev Execute a delegatecall with `delegate` on this account.
    /// Same as _executeDelegatecall but without return data for gas optimization.
    function _executeDelegatecallNoReturndata(address delegate, bytes calldata callData) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let result := mload(0x40)
            calldatacopy(result, callData.offset, callData.length)
            if iszero(delegatecall(gas(), delegate, result, callData.length, codesize(), 0x00)) {
                // Bubble up the revert if the call reverts.
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            mstore(0x40, add(result, callData.length)) //allocate memory
        }
    }

    /// @dev Execute a delegatecall with `delegate` on this account and catch reverts.
    /// @return success True if the delegatecall was successful, false otherwise.
    /// @return result The bytes returned from the delegatecall, which contains the returned data from the delegate
    /// contract.
    function _tryExecuteDelegatecall(
        address delegate,
        bytes calldata callData
    )
        internal
        returns (bool success, bytes memory result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            calldatacopy(result, callData.offset, callData.length)
            // Forwards the `data` to `delegate` via delegatecall.
            success := delegatecall(gas(), delegate, result, callData.length, codesize(), 0x00)
            mstore(result, returndatasize()) // Store the length.
            let o := add(result, 0x20)
            returndatacopy(o, 0x00, returndatasize()) // Copy the returndata.
            mstore(0x40, add(o, returndatasize())) // Allocate the memory.
        }
    }

    /// @dev Executes a single transaction based on the specified execution type.
    /// @param executionCalldata The calldata containing the transaction details (target address, value, and data).
    /// @param execType The execution type, which can be DEFAULT (revert on failure) or TRY (return on failure).
    function _handleSingleExecution(bytes calldata executionCalldata, ExecType execType) internal {
        (address target, uint256 value, bytes calldata callData) = executionCalldata.decodeSingle();
        if (execType == EXECTYPE_DEFAULT) {
            _executeNoReturndata(target, value, callData);
        } else if (execType == EXECTYPE_TRY) {
            (bool success, bytes memory result) = _tryExecute(target, value, callData);
            if (!success) emit TryExecuteUnsuccessful(callData, result);
        } else {
            revert UnsupportedExecType(execType);
        }
    }

    /// @dev Executes a batch of transactions based on the specified execution type.
    /// @param executionCalldata The calldata for a batch of transactions.
    /// @param execType The execution type, which can be DEFAULT (revert on failure) or TRY (return on failure).
    function _handleBatchExecution(bytes calldata executionCalldata, ExecType execType) internal {
        Execution[] calldata executions = executionCalldata.decodeBatch();
        if (execType == EXECTYPE_DEFAULT) _executeBatchNoReturndata(executions);
        else if (execType == EXECTYPE_TRY) _tryExecuteBatch(executions);
        else revert UnsupportedExecType(execType);
    }

    /// @dev Executes a single transaction based on the specified execution type.
    /// @param executionCalldata The calldata containing the transaction details (target address, value, and data).
    /// @param execType The execution type, which can be DEFAULT (revert on failure) or TRY (return on failure).
    function _handleDelegateCallExecution(bytes calldata executionCalldata, ExecType execType) internal {
        (address delegate, bytes calldata callData) = executionCalldata.decodeDelegateCall();
        if (execType == EXECTYPE_DEFAULT) {
            _executeDelegatecallNoReturndata(delegate, callData);
        } else if (execType == EXECTYPE_TRY) {
            (bool success, bytes memory result) = _tryExecuteDelegatecall(delegate, callData);
            if (!success) emit TryDelegateCallUnsuccessful(callData, result);
        } else {
            revert UnsupportedExecType(execType);
        }
    }

    /// @dev Executes a single transaction based on the specified execution type.
    /// @param executionCalldata The calldata containing the transaction details (target address, value, and data).
    /// @param execType The execution type, which can be DEFAULT (revert on failure) or TRY (return on failure).
    /// @return returnData An array containing the execution result. In the case of a single transaction, the array
    /// contains one element.
    function _handleSingleExecutionAndReturnData(
        bytes calldata executionCalldata,
        ExecType execType
    )
        internal
        returns (bytes[] memory returnData)
    {
        (address target, uint256 value, bytes calldata callData) = executionCalldata.decodeSingle();
        returnData = new bytes[](1);
        bool success;
        // check if execType is revert(default) or try
        if (execType == EXECTYPE_DEFAULT) {
            returnData[0] = _execute(target, value, callData);
        } else if (execType == EXECTYPE_TRY) {
            (success, returnData[0]) = _tryExecute(target, value, callData);
            if (!success) emit TryExecuteUnsuccessful(callData, returnData[0]);
        } else {
            revert UnsupportedExecType(execType);
        }
    }

    /// @dev Executes a batch of transactions based on the specified execution type.
    /// @param executionCalldata The calldata for a batch of transactions.
    /// @param execType The execution type, which can be DEFAULT (revert on failure) or TRY (return on failure).
    /// @return returnData An array containing the execution results for each transaction in the batch.
    function _handleBatchExecutionAndReturnData(
        bytes calldata executionCalldata,
        ExecType execType
    )
        internal
        returns (bytes[] memory returnData)
    {
        Execution[] calldata executions = executionCalldata.decodeBatch();
        if (execType == EXECTYPE_DEFAULT) returnData = _executeBatch(executions);
        else if (execType == EXECTYPE_TRY) returnData = _tryExecuteBatch(executions);
        else revert UnsupportedExecType(execType);
    }

    /// @dev Executes a single transaction based on the specified execution type.
    /// @param executionCalldata The calldata containing the transaction details (target address, value, and data).
    /// @param execType The execution type, which can be DEFAULT (revert on failure) or TRY (return on failure).
    /// @return returnData An array containing the result of the delegatecall execution.
    function _handleDelegateCallExecutionAndReturnData(
        bytes calldata executionCalldata,
        ExecType execType
    )
        internal
        returns (bytes[] memory returnData)
    {
        (address delegate, bytes calldata callData) = executionCalldata.decodeDelegateCall();
        returnData = new bytes[](1);
        bool success;
        if (execType == EXECTYPE_DEFAULT) {
            returnData[0] = _executeDelegatecall(delegate, callData);
        } else if (execType == EXECTYPE_TRY) {
            (success, returnData[0]) = _tryExecuteDelegatecall(delegate, callData);
            if (!success) emit TryDelegateCallUnsuccessful(callData, returnData[0]);
        } else {
            revert UnsupportedExecType(execType);
        }
    }
}



// ============================================================
// FILE: contracts/composability/ComposableExecutionBase.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ComposableExecutionLib } from "./ComposableExecutionLib.sol";
import { InputParam, OutputParam, ComposableExecution } from "../types/ComposabilityDataTypes.sol";
import { IComposableExecution } from "../interfaces/IComposableExecution.sol";
import { Execution } from "erc7579/interfaces/IERC7579Account.sol";

abstract contract ComposableExecutionBase is IComposableExecution {
    using ComposableExecutionLib for InputParam[];
    using ComposableExecutionLib for OutputParam[];

    /// @dev Override it in the account and introduce additional access control or other checks
    function executeComposable(ComposableExecution[] calldata cExecutions) external payable virtual;

    /// @dev internal function to execute the composable execution flow
    /// First, processes the input parameters and returns the composed calldata
    /// Then, executes the action
    /// Then, processes the output parameters
    function _executeComposable(ComposableExecution[] calldata cExecutions) internal {
        uint256 length = cExecutions.length;
        for (uint256 i; i < length; i++) {
            ComposableExecution calldata cExecution = cExecutions[i];
            Execution memory execution = cExecution.inputParams.processInputs(cExecution.functionSig);
            bytes memory returnData;
            if (execution.target != address(0)) {
                returnData = _executeAction(execution.target, execution.value, execution.callData);
            } else {
                returnData = new bytes(0);
            }
            // TODO: add early sanity check that output params length is > 0
            // so if it is 0, we can not even call processOutputs
            cExecution.outputParams.processOutputs(returnData, address(this));
        }
    }

    /// @dev Override this in the account
    /// using account's native execution approach
    /// we do not use Execution struct as an argument to be as less opinionated as possible
    /// instead we just use standard types
    function _executeAction(
        address to,
        uint256 value,
        bytes memory data
    )
        internal
        virtual
        returns (bytes memory returnData);
}



// ============================================================
// FILE: contracts/lib/nexus/Initializable.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// keccak256(abi.encode(uint256(keccak256("initializable.transient.Nexus")) - 1)) & ~bytes32(uint256(0xff));
bytes32 constant INIT_SLOT = 0x90b772c2cb8a51aa7a8a65fc23543c6d022d5b3f8e2b92eed79fba7eef829300;

/// @title Initializable
/// @dev This library provides a way to set a transient flag on a contract to ensure that it is only initialized during
/// the
/// constructor execution. This is useful to prevent a contract from being initialized multiple times.
library Initializable {
    /// @dev Thrown when an attempt to initialize an already initialized contract is made
    error NotInitializable();

    /// @dev Sets the initializable flag in the transient storage slot to true
    function setInitializable() internal {
        bytes32 slot = INIT_SLOT;
        assembly {
            tstore(slot, 0x01)
        }
    }

    /// @dev Checks if the initializable flag is set in the transient storage slot, reverts with NotInitializable if not
    function requireInitializable() internal view {
        bytes32 slot = INIT_SLOT;
        // Load the current value from the slot, revert if 0
        assembly {
            let isInitializable := tload(slot)
            if iszero(isInitializable) {
                mstore(0x0, 0xaed59595) // NotInitializable()
                revert(0x1c, 0x04)
            }
        }
    }
}



// ============================================================
// FILE: node_modules/solady/src/utils/UUPSUpgradeable.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {CallContextChecker} from "./CallContextChecker.sol";

/// @notice UUPS proxy mixin.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/UUPSUpgradeable.sol)
/// @author Modified from OpenZeppelin
/// (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol)
///
/// @dev Note:
/// - This implementation is intended to be used with ERC1967 proxies.
/// See: `LibClone.deployERC1967` and related functions.
/// - This implementation is NOT compatible with legacy OpenZeppelin proxies
/// which do not store the implementation at `_ERC1967_IMPLEMENTATION_SLOT`.
abstract contract UUPSUpgradeable is CallContextChecker {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The upgrade failed.
    error UpgradeFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when the proxy's implementation is upgraded.
    event Upgraded(address indexed implementation);

    /// @dev `keccak256(bytes("Upgraded(address)"))`.
    uint256 private constant _UPGRADED_EVENT_SIGNATURE =
        0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ERC-1967 storage slot for the implementation in the proxy.
    /// `uint256(keccak256("eip1967.proxy.implementation")) - 1`.
    bytes32 internal constant _ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      UUPS OPERATIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Please override this function to check if `msg.sender` is authorized
    /// to upgrade the proxy to `newImplementation`, reverting if not.
    /// ```
    ///     function _authorizeUpgrade(address) internal override onlyOwner {}
    /// ```
    function _authorizeUpgrade(address newImplementation) internal virtual;

    /// @dev Returns the storage slot used by the implementation,
    /// as specified in [ERC1822](https://eips.ethereum.org/EIPS/eip-1822).
    ///
    /// Note: The `notDelegated` modifier prevents accidental upgrades to
    /// an implementation that is a proxy contract.
    function proxiableUUID() public view virtual notDelegated returns (bytes32) {
        // This function must always return `_ERC1967_IMPLEMENTATION_SLOT` to comply with ERC1967.
        return _ERC1967_IMPLEMENTATION_SLOT;
    }

    /// @dev Upgrades the proxy's implementation to `newImplementation`.
    /// Emits a {Upgraded} event.
    ///
    /// Note: Passing in empty `data` skips the delegatecall to `newImplementation`.
    function upgradeToAndCall(address newImplementation, bytes calldata data)
        public
        payable
        virtual
        onlyProxy
    {
        _authorizeUpgrade(newImplementation);
        /// @solidity memory-safe-assembly
        assembly {
            newImplementation := shr(96, shl(96, newImplementation)) // Clears upper 96 bits.
            mstore(0x00, returndatasize())
            mstore(0x01, 0x52d1902d) // `proxiableUUID()`.
            let s := _ERC1967_IMPLEMENTATION_SLOT
            // Check if `newImplementation` implements `proxiableUUID` correctly.
            if iszero(eq(mload(staticcall(gas(), newImplementation, 0x1d, 0x04, 0x01, 0x20)), s)) {
                mstore(0x01, 0x55299b49) // `UpgradeFailed()`.
                revert(0x1d, 0x04)
            }
            // Emit the {Upgraded} event.
            log2(codesize(), 0x00, _UPGRADED_EVENT_SIGNATURE, newImplementation)
            sstore(s, newImplementation) // Updates the implementation.

            // Perform a delegatecall to `newImplementation` if `data` is non-empty.
            if data.length {
                // Forwards the `data` to `newImplementation` via delegatecall.
                let m := mload(0x40)
                calldatacopy(m, data.offset, data.length)
                if iszero(
                    delegatecall(gas(), newImplementation, m, data.length, codesize(), 0x00)
                ) {
                    // Bubble up the revert if the call reverts.
                    returndatacopy(m, 0x00, returndatasize())
                    revert(m, returndatasize())
                }
            }
        }
    }
}



// ============================================================
// FILE: contracts/interfaces/nexus/INexus.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { IAccountConfig } from "./base/IAccountConfig.sol";
import { IExecutionHelper } from "./base/IExecutionHelper.sol";
import { INexusEventsAndErrors } from "./INexusEventsAndErrors.sol";
import { IERC1271 } from "../standard/IERC1271.sol";
import { IAccount } from "account-abstraction/interfaces/IAccount.sol";

/// @title Nexus - INexus Interface
/// @notice Integrates ERC-4337 and ERC-7579 standards to manage smart accounts within the Nexus suite.
/// @dev Consolidates ERC-4337 user operations and ERC-7579 configurations into a unified interface for smart account
/// management.
/// It extends both IERC4337Account and IERC7579Account, enhancing modular capabilities and supporting advanced contract
/// architectures.
/// Includes error definitions for robust handling of common issues such as unsupported module types and execution
/// failures.
/// The initialize function sets up the account with validators and configurations, ensuring readiness for use.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface INexus is IAccountConfig, IExecutionHelper, IERC1271, IAccount, INexusEventsAndErrors {
    /// @notice Initializes the smart account with a validator and custom data.
    /// @dev This method sets up the account for operation, linking it with a validator and initializing it with
    /// specific
    /// data.
    /// Can be called directly or via a factory.
    /// @param initData Encoded data used for the account's configuration during initialization.
    function initializeAccount(bytes calldata initData) external payable;
}



// ============================================================
// FILE: contracts/lib/erc-7579/ExecLib.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Execution } from "erc7579/interfaces/IERC7579Account.sol";

/// @title ExecutionLib
/// @author zeroknots.eth | rhinestone.wtf
/// Helper Library for decoding Execution calldata
/// malloc for memory allocation is bad for gas. use this assembly instead
library ExecLib {
    function get2771CallData(bytes calldata cd) internal view returns (bytes memory callData) {
        /// @solidity memory-safe-assembly
        (cd);
        assembly {
            // as per solidity docs
            function allocate(length) -> pos {
                pos := mload(0x40)
                mstore(0x40, add(pos, length))
            }

            callData := allocate(add(calldatasize(), 0x20)) //allocate extra 0x20 to store length
            mstore(callData, add(calldatasize(), 0x14)) //store length, extra 0x14 is for msg.sender address
            calldatacopy(add(callData, 0x20), 0, calldatasize())

            // The msg.sender address is shifted to the left by 12 bytes to remove the padding
            // Then the address without padding is stored right after the calldata
            let senderPtr := allocate(0x14)
            mstore(senderPtr, shl(96, caller()))
        }
    }

    /**
     * @notice Decode a batch of `Execution` executionBatch from a `bytes` calldata.
     * @dev code is copied from solady's LibERC7579.sol
     * https://github.com/Vectorized/solady/blob/740812cedc9a1fc11e17cb3d4569744367dedf19/src/accounts/LibERC7579.sol#L146
     *      Credits to Vectorized and the Solady Team
     */
    function decodeBatch(bytes calldata executionCalldata) internal pure returns (Execution[] calldata executionBatch) {
        /// @solidity memory-safe-assembly
        assembly {
            let u := calldataload(executionCalldata.offset)
            let s := add(executionCalldata.offset, u)
            let e := sub(add(executionCalldata.offset, executionCalldata.length), 0x20)
            executionBatch.offset := add(s, 0x20)
            executionBatch.length := calldataload(s)
            if or(shr(64, u), gt(add(s, shl(5, executionBatch.length)), e)) {
                mstore(0x00, 0xba597e7e) // `DecodingError()`.
                revert(0x1c, 0x04)
            }
            if executionBatch.length {
                // Perform bounds checks on the decoded `executionBatch`.
                // Loop runs out-of-gas if `executionBatch.length` is big enough to cause overflows.
                for { let i := executionBatch.length } 1 { } {
                    i := sub(i, 1)
                    let p := calldataload(add(executionBatch.offset, shl(5, i)))
                    let c := add(executionBatch.offset, p)
                    let q := calldataload(add(c, 0x40))
                    let o := add(c, q)
                    // forgefmt: disable-next-item
                    if or(shr(64, or(calldataload(o), or(p, q))),
                        or(gt(add(c, 0x40), e), gt(add(o, calldataload(o)), e))) {
                        mstore(0x00, 0xba597e7e) // `DecodingError()`.
                        revert(0x1c, 0x04)
                    }
                    if iszero(i) { break }
                }
            }
        }
    }

    function encodeBatch(Execution[] memory executions) internal pure returns (bytes memory callData) {
        callData = abi.encode(executions);
    }

    function decodeSingle(bytes calldata executionCalldata)
        internal
        pure
        returns (address target, uint256 value, bytes calldata callData)
    {
        target = address(bytes20(executionCalldata[0:20]));
        value = uint256(bytes32(executionCalldata[20:52]));
        callData = executionCalldata[52:];
    }

    function decodeDelegateCall(bytes calldata executionCalldata)
        internal
        pure
        returns (address delegate, bytes calldata callData)
    {
        // destructure executionCallData according to single exec
        delegate = address(uint160(bytes20(executionCalldata[0:20])));
        callData = executionCalldata[20:];
    }

    function encodeSingle(
        address target,
        uint256 value,
        bytes memory callData
    )
        internal
        pure
        returns (bytes memory userOpCalldata)
    {
        userOpCalldata = abi.encodePacked(target, value, callData);
    }
}



// ============================================================
// FILE: contracts/lib/nexus/NonceLib.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// solhint-disable-next-line no-unused-import
import { MODE_MODULE_ENABLE, MODE_PREP, MODE_VALIDATION } from "../../types/Constants.sol";

/**
 * Nonce structure
 *     [3 bytes empty][1 bytes validation mode][20 bytes validator][8 bytes nonce]
 */
library NonceLib {
    /// @dev Parses validator address out of nonce
    /// @param nonce The nonce
    /// @return validator
    function getValidator(uint256 nonce) internal pure returns (address validator) {
        assembly {
            validator := shr(96, shl(32, nonce))
        }
    }

    /// @dev Detects if Validation Mode is Module Enable Mode
    /// @param nonce The nonce
    /// @return res boolean result, true if it is the Module Enable Mode
    function isModuleEnableMode(uint256 nonce) internal pure returns (bool res) {
        assembly {
            let vmode := byte(3, nonce)
            res := eq(shl(248, vmode), MODE_MODULE_ENABLE)
        }
    }

    /// @dev Detects if the validator provided in the nonce is address(0)
    /// which means the default validator is used
    /// @param nonce The nonce
    /// @return res boolean result, true if it is the Default Validator Mode
    function isDefaultValidatorMode(uint256 nonce) internal pure returns (bool res) {
        assembly {
            res := iszero(shr(96, shl(32, nonce)))
        }
    }

    /// @dev Detects if Validation Mode is Prep Mode
    /// @param nonce The nonce
    /// @return res boolean result, true if it is the Prep Mode
    function isPrepMode(uint256 nonce) internal pure returns (bool res) {
        assembly {
            let vmode := byte(3, nonce)
            res := eq(shl(248, vmode), MODE_PREP)
        }
    }

    /// @dev Detects if Validation Mode is Validate Mode
    /// @param nonce The nonce
    /// @return res boolean result, true if it is the Validation Mode
    function isValidateMode(uint256 nonce) internal pure returns (bool res) {
        assembly {
            let vmode := byte(3, nonce)
            res := eq(shl(248, vmode), MODE_VALIDATION)
        }
    }
}



// ============================================================
// FILE: node_modules/@rhinestone/sentinellist/src/SentinelList.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Sentinel address
address constant SENTINEL = address(0x1);
// Zero address
address constant ZERO_ADDRESS = address(0x0);

/**
 * @title SentinelListLib
 * @dev Library for managing a linked list of addresses
 * @author Rhinestone
 */
library SentinelListLib {
    // Struct to hold the linked list
    struct SentinelList {
        mapping(address => address) entries;
    }

    error LinkedList_AlreadyInitialized();
    error LinkedList_InvalidPage();
    error LinkedList_InvalidEntry(address entry);
    error LinkedList_EntryAlreadyInList(address entry);

    /**
     * Initialize the linked list
     *
     * @param self The linked list
     */
    function init(SentinelList storage self) internal {
        if (alreadyInitialized(self)) revert LinkedList_AlreadyInitialized();
        self.entries[SENTINEL] = SENTINEL;
    }

    /**
     * Check if the linked list is already initialized
     *
     * @param self The linked list
     *
     * @return bool True if the linked list is already initialized
     */
    function alreadyInitialized(SentinelList storage self) internal view returns (bool) {
        return self.entries[SENTINEL] != ZERO_ADDRESS;
    }

    /**
     * Get the next entry in the linked list
     *
     * @param self The linked list
     * @param entry The current entry
     *
     * @return address The next entry
     */
    function getNext(SentinelList storage self, address entry) internal view returns (address) {
        if (entry == ZERO_ADDRESS) {
            revert LinkedList_InvalidEntry(entry);
        }
        return self.entries[entry];
    }

    /**
     * Push a new entry to the linked list
     *
     * @param self The linked list
     * @param newEntry The new entry
     */
    function push(SentinelList storage self, address newEntry) internal {
        if (newEntry == ZERO_ADDRESS || newEntry == SENTINEL) {
            revert LinkedList_InvalidEntry(newEntry);
        }
        if (self.entries[newEntry] != ZERO_ADDRESS) revert LinkedList_EntryAlreadyInList(newEntry);
        self.entries[newEntry] = self.entries[SENTINEL];
        self.entries[SENTINEL] = newEntry;
    }

    /**
     * Safe push a new entry to the linked list
     * @dev This ensures that the linked list is initialized and initializes it if it is not
     *
     * @param self The linked list
     * @param newEntry The new entry
     */
    function safePush(SentinelList storage self, address newEntry) internal {
        if (!alreadyInitialized({ self: self })) {
            init({ self: self });
        }
        push({ self: self, newEntry: newEntry });
    }

    /**
     * Pop an entry from the linked list
     *
     * @param self The linked list
     * @param prevEntry The entry before the entry to pop
     * @param popEntry The entry to pop
     */
    function pop(SentinelList storage self, address prevEntry, address popEntry) internal {
        if (popEntry == ZERO_ADDRESS || popEntry == SENTINEL) {
            revert LinkedList_InvalidEntry(prevEntry);
        }
        if (self.entries[prevEntry] != popEntry) revert LinkedList_InvalidEntry(popEntry);
        self.entries[prevEntry] = self.entries[popEntry];
        self.entries[popEntry] = ZERO_ADDRESS;
    }

    /**
     * Pop all entries from the linked list
     *
     * @param self The linked list
     */
    function popAll(SentinelList storage self) internal {
        address next = self.entries[SENTINEL];
        while (next != ZERO_ADDRESS) {
            address current = next;
            next = self.entries[next];
            self.entries[current] = ZERO_ADDRESS;
        }
        self.entries[SENTINEL] = SENTINEL;
    }

    /**
     * Check if the linked list contains an entry
     *
     * @param self The linked list
     * @param entry The entry to check
     *
     * @return bool True if the linked list contains the entry
     */
    function contains(SentinelList storage self, address entry) internal view returns (bool) {
        return SENTINEL != entry && self.entries[entry] != ZERO_ADDRESS;
    }

    /**
     * Get all entries in the linked list
     *
     * @param self The linked list
     * @param start The start entry
     * @param pageSize The page size
     *
     * @return array All entries in the linked list
     * @return next The next entry
     */
    function getEntriesPaginated(
        SentinelList storage self,
        address start,
        uint256 pageSize
    )
        internal
        view
        returns (address[] memory array, address next)
    {
        if (start != SENTINEL && !contains(self, start)) revert LinkedList_InvalidEntry(start);
        if (pageSize == 0) revert LinkedList_InvalidPage();
        // Init array with max page size
        array = new address[](pageSize);

        // Populate return array
        uint256 entryCount = 0;
        next = self.entries[start];
        while (next != ZERO_ADDRESS && next != SENTINEL && entryCount < pageSize) {
            array[entryCount] = next;
            next = self.entries[next];
            entryCount++;
        }

        /**
         * Because of the argument validation, we can assume that the loop will always iterate over
         * the valid entry list values
         *       and the `next` variable will either be an enabled entry or a sentinel address
         * (signalling the end).
         *
         *       If we haven't reached the end inside the loop, we need to set the next pointer to
         * the last element of the entry array
         *       because the `next` variable (which is a entry by itself) acting as a pointer to the
         * start of the next page is neither
         *       incSENTINELrent page, nor will it be included in the next one if you pass it as a
         * start.
         */
        if (next != SENTINEL && entryCount > 0) {
            next = array[entryCount - 1];
        }
        // Set correct size of returned array
        // solhint-disable-next-line no-inline-assembly
        /// @solidity memory-safe-assembly
        assembly {
            mstore(array, entryCount)
        }
    }
}



// ============================================================
// FILE: contracts/types/DataTypes.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

/// @title Emergency Uninstall
/// @notice Struct to encapsulate emergency uninstall data for a hook
struct EmergencyUninstall {
    /// @notice The address of the hook to be uninstalled
    address hook;
    /// @notice The hook type identifier
    uint256 hookType;
    /// @notice Data used to uninstall the hook
    bytes deInitData;
    /// @notice Nonce used to prevent replay attacks
    uint256 nonce;
}



// ============================================================
// FILE: contracts/lib/nexus/local/LibPREP.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { LibBit } from "solady/utils/LibBit.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { LibEIP7702 } from "solady/accounts/LibEIP7702.sol";

/// @title LibPREP
/// @notice A library to encapsulate the PREP (Provably Rootless EIP-7702 Proxy) workflow.
/// See: https://blog.biconomy.io/prep-deep-dive/
library LibPREP {
    /// @dev Validates if `digest` and `saltAndDelegation` results in `target`.
    /// `saltAndDelegation` is `bytes32((uint256(salt) << 160) | uint160(delegation))`.
    /// Returns a non-zero `r` for the PREP signature, if valid.
    /// Otherwise returns 0.
    /// `r` will be less than `2**160`, allowing for optional storage packing.
    function rPREP(address target, bytes32 digest, bytes32 saltAndDelegation) internal view returns (bytes32 r) {
        r = (EfficientHashLib.hash(digest, saltAndDelegation >> 160) << 96) >> 96;
        if (!isValid(target, r, address(uint160(uint256(saltAndDelegation))))) r = 0;
    }

    /// @dev Returns if `r` and `delegation` results in `target`.
    function isValid(address target, bytes32 r, address delegation) internal view returns (bool) {
        bytes32 s = EfficientHashLib.hash(r);
        bytes32 h; // `keccak256(abi.encodePacked(hex"05", LibRLP.p(0).p(delegation).p(0).encode()))`.
        assembly ("memory-safe") {
            mstore(0x20, 0x80)
            mstore(0x1f, delegation)
            mstore(0x0b, 0x05d78094)
            h := keccak256(0x27, 0x19)
        }
        return LibBit.and(target != address(0), ECDSA.tryRecover(h, 27, r, s) == target);
    }

    /// @dev Returns if `target` is a PREP.
    function isPREP(address target, bytes32 r) internal view returns (bool) {
        address delegation = LibEIP7702.delegationOf(target);
        return !LibBit.or(delegation == address(0), r == 0) && isValid(target, r, delegation);
    }
}



// ============================================================
// FILE: node_modules/solady/src/utils/ECDSA.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Gas optimized ECDSA wrapper.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/ECDSA.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/ECDSA.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol)
///
/// @dev Note:
/// - The recovery functions use the ecrecover precompile (0x1).
/// - As of Solady version 0.0.68, the `recover` variants will revert upon recovery failure.
///   This is for more safety by default.
///   Use the `tryRecover` variants if you need to get the zero address back
///   upon recovery failure instead.
/// - As of Solady version 0.0.134, all `bytes signature` variants accept both
///   regular 65-byte `(r, s, v)` and EIP-2098 `(r, vs)` short form signatures.
///   See: https://eips.ethereum.org/EIPS/eip-2098
///   This is for calldata efficiency on smart accounts prevalent on L2s.
///
/// WARNING! Do NOT directly use signatures as unique identifiers:
/// - The recovery operations do NOT check if a signature is non-malleable.
/// - Use a nonce in the digest to prevent replay attacks on the same contract.
/// - Use EIP-712 for the digest to prevent replay attacks across different chains and contracts.
///   EIP-712 also enables readable signing of typed data for better user safety.
/// - If you need a unique hash from a signature, please use the `canonicalHash` functions.
library ECDSA {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The order of the secp256k1 elliptic curve.
    uint256 internal constant N =
        0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;

    /// @dev `N/2 + 1`. Used for checking the malleability of the signature.
    uint256 private constant _HALF_N_PLUS_1 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CUSTOM ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The signature is invalid.
    error InvalidSignature();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    RECOVERY OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Recovers the signer's address from a message digest `hash`, and the `signature`.
    function recover(bytes32 hash, bytes memory signature) internal view returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            for { let m := mload(0x40) } 1 {
                mstore(0x00, 0x8baa579f) // `InvalidSignature()`.
                revert(0x1c, 0x04)
            } {
                switch mload(signature)
                case 64 {
                    let vs := mload(add(signature, 0x40))
                    mstore(0x20, add(shr(255, vs), 27)) // `v`.
                    mstore(0x60, shr(1, shl(1, vs))) // `s`.
                }
                case 65 {
                    mstore(0x20, byte(0, mload(add(signature, 0x60)))) // `v`.
                    mstore(0x60, mload(add(signature, 0x40))) // `s`.
                }
                default { continue }
                mstore(0x00, hash)
                mstore(0x40, mload(add(signature, 0x20))) // `r`.
                result := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                mstore(0x60, 0) // Restore the zero slot.
                mstore(0x40, m) // Restore the free memory pointer.
                // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
                if returndatasize() { break }
            }
        }
    }

    /// @dev Recovers the signer's address from a message digest `hash`, and the `signature`.
    function recoverCalldata(bytes32 hash, bytes calldata signature)
        internal
        view
        returns (address result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            for { let m := mload(0x40) } 1 {
                mstore(0x00, 0x8baa579f) // `InvalidSignature()`.
                revert(0x1c, 0x04)
            } {
                switch signature.length
                case 64 {
                    let vs := calldataload(add(signature.offset, 0x20))
                    mstore(0x20, add(shr(255, vs), 27)) // `v`.
                    mstore(0x40, calldataload(signature.offset)) // `r`.
                    mstore(0x60, shr(1, shl(1, vs))) // `s`.
                }
                case 65 {
                    mstore(0x20, byte(0, calldataload(add(signature.offset, 0x40)))) // `v`.
                    calldatacopy(0x40, signature.offset, 0x40) // Copy `r` and `s`.
                }
                default { continue }
                mstore(0x00, hash)
                result := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                mstore(0x60, 0) // Restore the zero slot.
                mstore(0x40, m) // Restore the free memory pointer.
                // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
                if returndatasize() { break }
            }
        }
    }

    /// @dev Recovers the signer's address from a message digest `hash`,
    /// and the EIP-2098 short form signature defined by `r` and `vs`.
    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal view returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x00, hash)
            mstore(0x20, add(shr(255, vs), 27)) // `v`.
            mstore(0x40, r)
            mstore(0x60, shr(1, shl(1, vs))) // `s`.
            result := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
            // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
            if iszero(returndatasize()) {
                mstore(0x00, 0x8baa579f) // `InvalidSignature()`.
                revert(0x1c, 0x04)
            }
            mstore(0x60, 0) // Restore the zero slot.
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    /// @dev Recovers the signer's address from a message digest `hash`,
    /// and the signature defined by `v`, `r`, `s`.
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (address result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x00, hash)
            mstore(0x20, and(v, 0xff))
            mstore(0x40, r)
            mstore(0x60, s)
            result := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
            // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
            if iszero(returndatasize()) {
                mstore(0x00, 0x8baa579f) // `InvalidSignature()`.
                revert(0x1c, 0x04)
            }
            mstore(0x60, 0) // Restore the zero slot.
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   TRY-RECOVER OPERATIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // WARNING!
    // These functions will NOT revert upon recovery failure.
    // Instead, they will return the zero address upon recovery failure.
    // It is critical that the returned address is NEVER compared against
    // a zero address (e.g. an uninitialized address variable).

    /// @dev Recovers the signer's address from a message digest `hash`, and the `signature`.
    function tryRecover(bytes32 hash, bytes memory signature)
        internal
        view
        returns (address result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            for { let m := mload(0x40) } 1 {} {
                switch mload(signature)
                case 64 {
                    let vs := mload(add(signature, 0x40))
                    mstore(0x20, add(shr(255, vs), 27)) // `v`.
                    mstore(0x60, shr(1, shl(1, vs))) // `s`.
                }
                case 65 {
                    mstore(0x20, byte(0, mload(add(signature, 0x60)))) // `v`.
                    mstore(0x60, mload(add(signature, 0x40))) // `s`.
                }
                default { break }
                mstore(0x00, hash)
                mstore(0x40, mload(add(signature, 0x20))) // `r`.
                pop(staticcall(gas(), 1, 0x00, 0x80, 0x40, 0x20))
                mstore(0x60, 0) // Restore the zero slot.
                // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
                result := mload(xor(0x60, returndatasize()))
                mstore(0x40, m) // Restore the free memory pointer.
                break
            }
        }
    }

    /// @dev Recovers the signer's address from a message digest `hash`, and the `signature`.
    function tryRecoverCalldata(bytes32 hash, bytes calldata signature)
        internal
        view
        returns (address result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            for { let m := mload(0x40) } 1 {} {
                switch signature.length
                case 64 {
                    let vs := calldataload(add(signature.offset, 0x20))
                    mstore(0x20, add(shr(255, vs), 27)) // `v`.
                    mstore(0x40, calldataload(signature.offset)) // `r`.
                    mstore(0x60, shr(1, shl(1, vs))) // `s`.
                }
                case 65 {
                    mstore(0x20, byte(0, calldataload(add(signature.offset, 0x40)))) // `v`.
                    calldatacopy(0x40, signature.offset, 0x40) // Copy `r` and `s`.
                }
                default { break }
                mstore(0x00, hash)
                pop(staticcall(gas(), 1, 0x00, 0x80, 0x40, 0x20))
                mstore(0x60, 0) // Restore the zero slot.
                // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
                result := mload(xor(0x60, returndatasize()))
                mstore(0x40, m) // Restore the free memory pointer.
                break
            }
        }
    }

    /// @dev Recovers the signer's address from a message digest `hash`,
    /// and the EIP-2098 short form signature defined by `r` and `vs`.
    function tryRecover(bytes32 hash, bytes32 r, bytes32 vs)
        internal
        view
        returns (address result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x00, hash)
            mstore(0x20, add(shr(255, vs), 27)) // `v`.
            mstore(0x40, r)
            mstore(0x60, shr(1, shl(1, vs))) // `s`.
            pop(staticcall(gas(), 1, 0x00, 0x80, 0x40, 0x20))
            mstore(0x60, 0) // Restore the zero slot.
            // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
            result := mload(xor(0x60, returndatasize()))
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    /// @dev Recovers the signer's address from a message digest `hash`,
    /// and the signature defined by `v`, `r`, `s`.
    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (address result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x00, hash)
            mstore(0x20, and(v, 0xff))
            mstore(0x40, r)
            mstore(0x60, s)
            pop(staticcall(gas(), 1, 0x00, 0x80, 0x40, 0x20))
            mstore(0x60, 0) // Restore the zero slot.
            // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
            result := mload(xor(0x60, returndatasize()))
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     HASHING OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns an Ethereum Signed Message, created from a `hash`.
    /// This produces a hash corresponding to the one signed with the
    /// [`eth_sign`](https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_sign)
    /// JSON-RPC method as part of EIP-191.
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, hash) // Store into scratch space for keccak256.
            mstore(0x00, "\x00\x00\x00\x00\x19Ethereum Signed Message:\n32") // 28 bytes.
            result := keccak256(0x04, 0x3c) // `32 * 2 - (32 - 28) = 60 = 0x3c`.
        }
    }

    /// @dev Returns an Ethereum Signed Message, created from `s`.
    /// This produces a hash corresponding to the one signed with the
    /// [`eth_sign`](https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_sign)
    /// JSON-RPC method as part of EIP-191.
    /// Note: Supports lengths of `s` up to 999999 bytes.
    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let sLength := mload(s)
            let o := 0x20
            mstore(o, "\x19Ethereum Signed Message:\n") // 26 bytes, zero-right-padded.
            mstore(0x00, 0x00)
            // Convert the `s.length` to ASCII decimal representation: `base10(s.length)`.
            for { let temp := sLength } 1 {} {
                o := sub(o, 1)
                mstore8(o, add(48, mod(temp, 10)))
                temp := div(temp, 10)
                if iszero(temp) { break }
            }
            let n := sub(0x3a, o) // Header length: `26 + 32 - o`.
            // Throw an out-of-offset error (consumes all gas) if the header exceeds 32 bytes.
            returndatacopy(returndatasize(), returndatasize(), gt(n, 0x20))
            mstore(s, or(mload(0x00), mload(n))) // Temporarily store the header.
            result := keccak256(add(s, sub(0x20, n)), add(n, sLength))
            mstore(s, sLength) // Restore the length.
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CANONICAL HASH FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // The following functions return the hash of the signature in its canonicalized format,
    // which is the 65-byte `abi.encodePacked(r, s, uint8(v))`, where `v` is either 27 or 28.
    // If `s` is greater than `N / 2` then it will be converted to `N - s`
    // and the `v` value will be flipped.
    // If the signature has an invalid length, or if `v` is invalid,
    // a uniquely corrupt hash will be returned.
    // These functions are useful for "poor-mans-VRF".

    /// @dev Returns the canonical hash of `signature`.
    function canonicalHash(bytes memory signature) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let l := mload(signature)
            for {} 1 {} {
                mstore(0x00, mload(add(signature, 0x20))) // `r`.
                let s := mload(add(signature, 0x40))
                let v := mload(add(signature, 0x41))
                if eq(l, 64) {
                    v := add(shr(255, s), 27)
                    s := shr(1, shl(1, s))
                }
                if iszero(lt(s, _HALF_N_PLUS_1)) {
                    v := xor(v, 7)
                    s := sub(N, s)
                }
                mstore(0x21, v)
                mstore(0x20, s)
                result := keccak256(0x00, 0x41)
                mstore(0x21, 0) // Restore the overwritten part of the free memory pointer.
                break
            }

            // If the length is neither 64 nor 65, return a uniquely corrupted hash.
            if iszero(lt(sub(l, 64), 2)) {
                // `bytes4(keccak256("InvalidSignatureLength"))`.
                result := xor(keccak256(add(signature, 0x20), l), 0xd62f1ab2)
            }
        }
    }

    /// @dev Returns the canonical hash of `signature`.
    function canonicalHashCalldata(bytes calldata signature)
        internal
        pure
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            for {} 1 {} {
                mstore(0x00, calldataload(signature.offset)) // `r`.
                let s := calldataload(add(signature.offset, 0x20))
                let v := calldataload(add(signature.offset, 0x21))
                if eq(signature.length, 64) {
                    v := add(shr(255, s), 27)
                    s := shr(1, shl(1, s))
                }
                if iszero(lt(s, _HALF_N_PLUS_1)) {
                    v := xor(v, 7)
                    s := sub(N, s)
                }
                mstore(0x21, v)
                mstore(0x20, s)
                result := keccak256(0x00, 0x41)
                mstore(0x21, 0) // Restore the overwritten part of the free memory pointer.
                break
            }
            // If the length is neither 64 nor 65, return a uniquely corrupted hash.
            if iszero(lt(sub(signature.length, 64), 2)) {
                calldatacopy(mload(0x40), signature.offset, signature.length)
                // `bytes4(keccak256("InvalidSignatureLength"))`.
                result := xor(keccak256(mload(0x40), signature.length), 0xd62f1ab2)
            }
        }
    }

    /// @dev Returns the canonical hash of `signature`.
    function canonicalHash(bytes32 r, bytes32 vs) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, r) // `r`.
            let v := add(shr(255, vs), 27)
            let s := shr(1, shl(1, vs))
            mstore(0x21, v)
            mstore(0x20, s)
            result := keccak256(0x00, 0x41)
            mstore(0x21, 0) // Restore the overwritten part of the free memory pointer.
        }
    }

    /// @dev Returns the canonical hash of `signature`.
    function canonicalHash(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, r) // `r`.
            if iszero(lt(s, _HALF_N_PLUS_1)) {
                v := xor(v, 7)
                s := sub(N, s)
            }
            mstore(0x21, v)
            mstore(0x20, s)
            result := keccak256(0x00, 0x41)
            mstore(0x21, 0) // Restore the overwritten part of the free memory pointer.
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   EMPTY CALLDATA HELPERS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns an empty calldata bytes.
    function emptySignature() internal pure returns (bytes calldata signature) {
        /// @solidity memory-safe-assembly
        assembly {
            signature.length := 0
        }
    }
}



// ============================================================
// FILE: node_modules/@erc7579/implementation/src/interfaces/IERC7579Module.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";

uint256 constant VALIDATION_SUCCESS = 0;
uint256 constant VALIDATION_FAILED = 1;

uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_FALLBACK = 3;
uint256 constant MODULE_TYPE_HOOK = 4;
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 = 8;
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC4337 = 9;

interface IModule {
    error AlreadyInitialized(address smartAccount);
    error NotInitialized(address smartAccount);

    /**
     * @dev This function is called by the smart account during installation of the module
     * @param data arbitrary data that may be required on the module during `onInstall`
     * initialization
     *
     * MUST revert on error (i.e. if module is already enabled)
     */
    function onInstall(bytes calldata data) external;

    /**
     * @dev This function is called by the smart account during uninstallation of the module
     * @param data arbitrary data that may be required on the module during `onUninstall`
     * de-initialization
     *
     * MUST revert on error
     */
    function onUninstall(bytes calldata data) external;

    /**
     * @dev Returns boolean value if module is a certain type
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     *
     * MUST return true if the module is of the given type and false otherwise
     */
    function isModuleType(uint256 moduleTypeId) external view returns (bool);

    /**
     * @dev Returns if the module was already initialized for a provided smartaccount
     */
    function isInitialized(address smartAccount) external view returns (bool);
}

interface IValidator is IModule {
    error InvalidTargetAddress(address target);

    /**
     * @dev Validates a transaction on behalf of the account.
     *         This function is intended to be called by the MSA during the ERC-4337 validaton phase
     *         Note: solely relying on bytes32 hash and signature is not suffcient for some
     * validation implementations (i.e. SessionKeys often need access to userOp.calldata)
     * @param userOp The user operation to be validated. The userOp MUST NOT contain any metadata.
     * The MSA MUST clean up the userOp before sending it to the validator.
     * @param userOpHash The hash of the user operation to be validated
     * @return return value according to ERC-4337
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        returns (uint256);

    /**
     * Validator can be used for ERC-1271 validation
     */
    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata data
    )
        external
        view
        returns (bytes4);
}

interface IExecutor is IModule { }

interface IHook is IModule {
    function preCheck(
        address msgSender,
        uint256 msgValue,
        bytes calldata msgData
    )
        external
        returns (bytes memory hookData);

    function postCheck(bytes calldata hookData) external;
}

interface IFallback is IModule { }

interface IPreValidationHookERC1271 is IModule {
    function preValidationHookERC1271(
        address sender,
        bytes32 hash,
        bytes calldata data
    )
        external
        view
        returns (bytes32 hookHash, bytes memory hookSignature);
}

interface IPreValidationHookERC4337 is IModule {
    function preValidationHookERC4337(
        PackedUserOperation calldata userOp,
        uint256 missingAccountFunds,
        bytes32 userOpHash
    )
        external
        returns (bytes32 hookHash, bytes memory hookSignature);
}



// ============================================================
// FILE: contracts/types/Constants.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// STX Sig types
bytes3 constant SIG_TYPE_MEE_FLOW = 0x177eee;

bytes4 constant SIG_TYPE_SIMPLE = 0x177eee00;
bytes4 constant SIG_TYPE_ON_CHAIN = 0x177eee01;
bytes4 constant SIG_TYPE_ERC20_PERMIT = 0x177eee02;
// bytes4 constant SIG_TYPE_MM_DELEGATION = 0x177eee03; // reserved for MM delegation support
bytes4 constant SIG_TYPE_SAFE_ACCOUNT = 0x177eee04;
bytes4 constant SIG_TYPE_NO_STX_VANILLA_1271_EOA = 0x177eee05;

// P256 sig types
bytes4 constant SIG_TYPE_SIMPLE_P256 = 0x177eee10;
bytes4 constant SIG_TYPE_NO_STX_VANILLA_1271_P256 = 0x177eee11;
bytes4 constant SIG_TYPE_NO_STX_P256 = 0x177eee12;

// Custom sig types
bytes4 constant SIG_TYPE_CUSTOM = 0x177eeeff;

// ...other sig types: ERC-7683, Permit2, etc

// EIP-1271 constants
bytes4 constant ERC1271_SUCCESS = 0x1626ba7e;
bytes4 constant ERC1271_FAILED = 0xffffffff;

// Node PM constants
bytes4 constant NODE_PM_MODE_USER = 0x170de000; // refund goes to the user
bytes4 constant NODE_PM_MODE_DAPP = 0x170de001; // refund goes to the dApp
bytes4 constant NODE_PM_MODE_KEEP = 0x170de002; // no refund as node sponsored

bytes4 constant NODE_PM_PREMIUM_PERCENT = 0x9ee4ce00; // premium percentage
bytes4 constant NODE_PM_PREMIUM_FIXED = 0x9ee4ce01;

// ERC-4337 validation constants
uint256 constant VALIDATION_SUCCESS = 0;
uint256 constant VALIDATION_FAILED = 1;

// Module type identifiers
uint256 constant MODULE_TYPE_MULTI = 0; // Module type identifier for Multitype install
uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_FALLBACK = 3;
uint256 constant MODULE_TYPE_HOOK = 4;
uint256 constant MODULE_TYPE_STATELESS_VALIDATOR = 7;
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 = 8;
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC4337 = 9;

// Nexus Validation modes
bytes1 constant MODE_VALIDATION = 0x00;
bytes1 constant MODE_MODULE_ENABLE = 0x01;
bytes1 constant MODE_PREP = 0x02;

// ERC-7739 support constants
bytes4 constant SUPPORTS_ERC7739 = 0x77390000;
bytes4 constant SUPPORTS_ERC7739_V1 = 0x77390001;

// Typehashes

// keccak256("ModuleEnableMode(address module,uint256 moduleType,bytes32 userOpHash,bytes initData)")
bytes32 constant MODULE_ENABLE_MODE_TYPE_HASH = 0xf6c866c1cd985ce61f030431e576c0e82887de0643dfa8a2e6efc3463e638ed0;

// keccak256("EmergencyUninstall(address hook,uint256 hookType,bytes deInitData,uint256 nonce)")
bytes32 constant EMERGENCY_UNINSTALL_TYPE_HASH = 0xd3ddfc12654178cc44d4a7b6b969cfdce7ffe6342326ba37825314cffa0fba9c;



// ============================================================
// FILE: contracts/lib/erc-7579/ModeLib.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title ModeLib
/// @author zeroknots.eth | rhinestone.wtf
/// To allow smart accounts to be very simple, but allow for more complex execution, A custom mode
/// encoding is used.
///    Function Signature of execute function:
///           function execute(ExecutionMode mode, bytes calldata executionCalldata) external payable;
/// This allows for a single bytes32 to be used to encode the execution mode, calltype, execType and
/// context.
/// NOTE: Simple Account implementations only have to scope for the most significant byte. Account  that
/// implement
/// more complex execution modes may use the entire bytes32.
///
/// |--------------------------------------------------------------------|
/// | CALLTYPE  | EXECTYPE  |   UNUSED   | ModeSelector  |  ModePayload  |
/// |--------------------------------------------------------------------|
/// | 1 byte    | 1 byte    |   4 bytes  | 4 bytes       |   22 bytes    |
/// |--------------------------------------------------------------------|
///
/// CALLTYPE: 1 byte
/// CallType is used to determine how the executeCalldata paramter of the execute function has to be
/// decoded.
/// It can be either single, batch or delegatecall. In the future different calls could be added.
/// CALLTYPE can be used by a validation module to determine how to decode <userOp.callData[36:]>.
///
/// EXECTYPE: 1 byte
/// ExecType is used to determine how the account should handle the execution.
/// It can indicate if the execution should revert on failure or continue execution.
/// In the future more execution modes may be added.
/// Default Behavior (EXECTYPE = 0x00) is to revert on a single failed execution. If one execution in
/// a batch fails, the entire batch is reverted
///
/// UNUSED: 4 bytes
/// Unused bytes are reserved for future use.
///
/// ModeSelector: bytes4
/// The "optional" mode selector can be used by account vendors, to implement custom behavior in
/// their accounts.
/// the way a ModeSelector is to be calculated is bytes4(keccak256("vendorname.featurename"))
/// this is to prevent collisions between different vendors, while allowing innovation and the
/// development of new features without coordination between ERC-7579 implementing accounts
///
/// ModePayload: 22 bytes
/// Mode payload is used to pass additional data to the smart account execution, this may be
/// interpreted depending on the ModeSelector
///
/// ExecutionCallData: n bytes
/// single, delegatecall or batch exec abi.encoded as bytes

// Custom type for improved developer experience
type ExecutionMode is bytes32;

type CallType is bytes1;

type ExecType is bytes1;

type ModeSelector is bytes4;

type ModePayload is bytes22;

// Default CallType
CallType constant CALLTYPE_SINGLE = CallType.wrap(0x00);
// Batched CallType
CallType constant CALLTYPE_BATCH = CallType.wrap(0x01);

CallType constant CALLTYPE_STATIC = CallType.wrap(0xFE);

// @dev Implementing delegatecall is OPTIONAL!
// implement delegatecall with extreme care.
CallType constant CALLTYPE_DELEGATECALL = CallType.wrap(0xFF);

// @dev default behavior is to revert on failure
// To allow very simple accounts to use mode encoding, the default behavior is to revert on failure
// Since this is value 0x00, no additional encoding is required for simple accounts
ExecType constant EXECTYPE_DEFAULT = ExecType.wrap(0x00);
// @dev account may elect to change execution behavior. For example "try exec" / "allow fail"
ExecType constant EXECTYPE_TRY = ExecType.wrap(0x01);

ModeSelector constant MODE_DEFAULT = ModeSelector.wrap(bytes4(0x00000000));
// Example declaration of a custom mode selector
ModeSelector constant MODE_OFFSET = ModeSelector.wrap(bytes4(keccak256("default.mode.offset")));

/// @dev ModeLib is a helper library to encode/decode ModeCodes
library ModeLib {
    function decode(ExecutionMode mode)
        internal
        pure
        returns (CallType _calltype, ExecType _execType, ModeSelector _modeSelector, ModePayload _modePayload)
    {
        assembly {
            _calltype := mode
            _execType := shl(8, mode)
            _modeSelector := shl(48, mode)
            _modePayload := shl(80, mode)
        }
    }

    function decodeBasic(ExecutionMode mode) internal pure returns (CallType _calltype, ExecType _execType) {
        assembly {
            _calltype := mode
            _execType := shl(8, mode)
        }
    }

    function encode(
        CallType callType,
        ExecType execType,
        ModeSelector mode,
        ModePayload payload
    )
        internal
        pure
        returns (ExecutionMode)
    {
        return ExecutionMode.wrap(
            bytes32(abi.encodePacked(callType, execType, bytes4(0), ModeSelector.unwrap(mode), payload))
        );
    }

    function encodeSimpleBatch() internal pure returns (ExecutionMode mode) {
        mode = encode(CALLTYPE_BATCH, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00));
    }

    function encodeSimpleSingle() internal pure returns (ExecutionMode mode) {
        mode = encode(CALLTYPE_SINGLE, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00));
    }

    function encodeTrySingle() internal pure returns (ExecutionMode mode) {
        mode = encode(CALLTYPE_SINGLE, EXECTYPE_TRY, MODE_DEFAULT, ModePayload.wrap(0x00));
    }

    function encodeTryBatch() internal pure returns (ExecutionMode mode) {
        mode = encode(CALLTYPE_BATCH, EXECTYPE_TRY, MODE_DEFAULT, ModePayload.wrap(0x00));
    }

    function encodeCustom(CallType callType, ExecType execType) internal pure returns (ExecutionMode mode) {
        mode = encode(callType, execType, MODE_DEFAULT, ModePayload.wrap(0x00));
    }

    function getCallType(ExecutionMode mode) internal pure returns (CallType calltype) {
        assembly {
            calltype := mode
        }
    }
}

using { _eqModeSelector as == } for ModeSelector global;
using { _eqCallType as == } for CallType global;
using { _uneqCallType as != } for CallType global;
using { _eqExecType as == } for ExecType global;

function _eqCallType(CallType a, CallType b) pure returns (bool) {
    return CallType.unwrap(a) == CallType.unwrap(b);
}

function _uneqCallType(CallType a, CallType b) pure returns (bool) {
    return CallType.unwrap(a) != CallType.unwrap(b);
}

function _eqExecType(ExecType a, ExecType b) pure returns (bool) {
    return ExecType.unwrap(a) == ExecType.unwrap(b);
}

//slither-disable-next-line dead-code
function _eqModeSelector(ModeSelector a, ModeSelector b) pure returns (bool) {
    return ModeSelector.unwrap(a) == ModeSelector.unwrap(b);
}



// ============================================================
// FILE: node_modules/account-abstraction/contracts/interfaces/PackedUserOperation.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.5;

/**
 * User Operation struct
 * @param sender                - The sender account of this request.
 * @param nonce                 - Unique value the sender uses to verify it is not a replay.
 * @param initCode              - If set, the account contract will be created by this constructor/
 * @param callData              - The method call to execute on this account.
 * @param accountGasLimits      - Packed gas limits for validateUserOp and gas limit passed to the callData method call.
 * @param preVerificationGas    - Gas not calculated by the handleOps method, but added to the gas paid.
 *                                Covers batch overhead.
 * @param gasFees               - packed gas fields maxPriorityFeePerGas and maxFeePerGas - Same as EIP-1559 gas parameters.
 * @param paymasterAndData      - If set, this field holds the paymaster address, verification gas limit, postOp gas limit and paymaster-specific extra data
 *                                The paymaster will pay for the transaction instead of the sender.
 * @param signature             - Sender-verified signature over the entire request, the EntryPoint address and the chain ID.
 */
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}



// ============================================================
// FILE: contracts/interfaces/nexus/base/IBaseAccount.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { IBaseAccountEventsAndErrors } from "./IBaseAccountEventsAndErrors.sol";

/// @title Nexus - IBaseAccount
/// @notice Interface for the BaseAccount functionalities compliant with ERC-7579 and ERC-4337.
/// @dev Interface for organizing the base functionalities using the Nexus suite.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IBaseAccount is IBaseAccountEventsAndErrors {
    /// @notice Adds deposit to the EntryPoint to fund transactions.
    function addDeposit() external payable;

    /// @notice Withdraws ETH from the EntryPoint to a specified address.
    /// @param to The address to receive the withdrawn funds.
    /// @param amount The amount to withdraw.
    function withdrawDepositTo(address to, uint256 amount) external payable;

    /// @notice Returns the current deposit balance of this account on the EntryPoint.
    /// @return The current balance held at the EntryPoint.
    function getDeposit() external view returns (uint256);

    /// @notice Retrieves the address of the EntryPoint contract, currently using version 0.7.
    /// @return The address of the EntryPoint contract.
    function entryPoint() external view returns (address);
}



// ============================================================
// FILE: contracts/nexus/base/Storage.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { IStorage } from "../../interfaces/nexus/base/IStorage.sol";

/// @title Nexus - Storage
/// @notice Manages isolated storage spaces for Modular Smart Account in compliance with ERC-7201 standard to ensure
/// collision-resistant storage.
/// @dev Implements the ERC-7201 namespaced storage pattern to maintain secure and isolated storage sections for
/// different
/// states within Nexus suite.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract Storage is IStorage {
    /// @custom:storage-location erc7201:biconomy.storage.Nexus
    /// ERC-7201 namespaced via `keccak256(abi.encode(uint256(keccak256(bytes("biconomy.storage.Nexus"))) - 1)) &
    /// ~bytes32(uint256(0xff));`
    bytes32 private constant _STORAGE_LOCATION = 0x0bb70095b32b9671358306b0339b4c06e7cbd8cb82505941fba30d1eb5b82f00;

    /// @dev Utilizes ERC-7201's namespaced storage pattern for isolated storage access. This method computes
    /// the storage slot based on a predetermined location, ensuring collision-resistant storage for contract states.
    /// @custom:storage-location ERC-7201 formula applied to "biconomy.storage.Nexus", facilitating unique
    /// namespace identification and storage segregation, as detailed in the specification.
    /// @return $ The proxy to the `AccountStorage` struct, providing a reference to the namespaced storage slot.
    function _getAccountStorage() internal pure returns (AccountStorage storage $) {
        assembly {
            $.slot := _STORAGE_LOCATION
        }
    }
}



// ============================================================
// FILE: contracts/lib/nexus/local/LocalCallDataParserLib.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library LocalCallDataParserLib {
    /// @dev Parses the `userOp.signature` to extract the module type, module initialization data,
    ///      enable mode signature, and user operation signature. The `userOp.signature` must be
    ///      encoded in a specific way to be parsed correctly.
    /// @param packedData The packed signature data, typically coming from `userOp.signature`.
    /// @return module The address of the module.
    /// @return moduleType The type of module as a `uint256`.
    /// @return moduleInitData Initialization data specific to the module.
    /// @return enableModeSignature Signature used to enable the module mode.
    /// @return userOpSignature The remaining user operation signature data.
    function parseEnableModeData(bytes calldata packedData)
        internal
        pure
        returns (
            address module,
            uint256 moduleType,
            bytes calldata moduleInitData,
            bytes calldata enableModeSignature,
            bytes calldata userOpSignature
        )
    {
        uint256 p;
        assembly ("memory-safe") {
            p := packedData.offset
            module := shr(96, calldataload(p))

            p := add(p, 0x14)
            moduleType := calldataload(p)

            moduleInitData.length := shr(224, calldataload(add(p, 0x20)))
            moduleInitData.offset := add(p, 0x24)
            p := add(moduleInitData.offset, moduleInitData.length)

            enableModeSignature.length := shr(224, calldataload(p))
            enableModeSignature.offset := add(p, 0x04)
            p := sub(add(enableModeSignature.offset, enableModeSignature.length), packedData.offset)
        }
        userOpSignature = packedData[p:];
    }

    /// @dev Parses the data to obtain types and initdata's for Multi Type module install mode
    /// @param initData Multi Type module init data, abi.encoded
    function parseMultiTypeInitData(bytes calldata initData)
        internal
        pure
        returns (uint256[] calldata types, bytes[] calldata initDatas)
    {
        // equivalent of:
        // (types, initDatas) = abi.decode(initData,(uint[],bytes[]))
        assembly ("memory-safe") {
            let offset := initData.offset
            let baseOffset := offset
            let dataPointer := add(baseOffset, calldataload(offset))

            types.offset := add(dataPointer, 32)
            types.length := calldataload(dataPointer)
            offset := add(offset, 32)

            dataPointer := add(baseOffset, calldataload(offset))
            initDatas.offset := add(dataPointer, 32)
            initDatas.length := calldataload(dataPointer)
        }
    }
}



// ============================================================
// FILE: contracts/interfaces/nexus/base/IModuleManager.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { IModuleManagerEventsAndErrors } from "./IModuleManagerEventsAndErrors.sol";

/// @title Nexus - IModuleManager
/// @notice Interface for managing modules within Smart Accounts, providing methods for installation and removal of
/// modules.
/// @dev Extends the IModuleManagerEventsAndErrors interface to include event and error definitions.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IModuleManager is IModuleManagerEventsAndErrors {
    /// @notice Installs a Module of a specific type onto the smart account.
    /// @param moduleTypeId The identifier for the module type.
    /// @param module The address of the module to be installed.
    /// @param initData Initialization data for configuring the module upon installation.
    function installModule(uint256 moduleTypeId, address module, bytes calldata initData) external payable;

    /// @notice Uninstalls a Module of a specific type from the smart account.
    /// @param moduleTypeId The identifier for the module type being uninstalled.
    /// @param module The address of the module to uninstall.
    /// @param deInitData De-initialization data for configuring the module upon uninstallation.
    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData) external payable;

    /// @notice Checks if a specific module is installed on the smart account.
    /// @param moduleTypeId The module type identifier to check.
    /// @param module The address of the module.
    /// @param additionalContext Additional information that may be required to verify the module's installation.
    /// @return installed True if the module is installed, false otherwise.
    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata additionalContext
    )
        external
        view
        returns (bool installed);
}



// ============================================================
// FILE: node_modules/solady/src/utils/EIP712.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Contract for EIP-712 typed structured data hashing and signing.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/EIP712.sol)
/// @author Modified from Solbase (https://github.com/Sol-DAO/solbase/blob/main/src/utils/EIP712.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/EIP712.sol)
///
/// @dev Note, this implementation:
/// - Uses `address(this)` for the `verifyingContract` field.
/// - Does NOT use the optional EIP-712 salt.
/// - Does NOT use any EIP-712 extensions.
/// This is for simplicity and to save gas.
/// If you need to customize, please fork / modify accordingly.
abstract contract EIP712 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`.
    bytes32 internal constant _DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    /// @dev `keccak256("EIP712Domain(string name,string version,address verifyingContract)")`.
    /// This is only used in `_hashTypedDataSansChainId`.
    bytes32 internal constant _DOMAIN_TYPEHASH_SANS_CHAIN_ID =
        0x91ab3d17e3a50a9d89e63fd30b92be7f5336b03b287bb946787a83a9d62a2766;

    /// @dev `keccak256("EIP712Domain(string name,string version)")`.
    /// This is only used in `_hashTypedDataSansChainIdAndVerifyingContract`.
    bytes32 internal constant _DOMAIN_TYPEHASH_SANS_CHAIN_ID_AND_VERIFYING_CONTRACT =
        0xb03948446334eb9b2196d5eb166f69b9d49403eb4a12f36de8d3f9f3cb8e15c3;

    /// @dev `keccak256("EIP712Domain(string name,string version,uint256 chainId)")`.
    /// This is only used in `_hashTypedDataSansVerifyingContract`.
    bytes32 internal constant _DOMAIN_TYPEHASH_SANS_VERIFYING_CONTRACT =
        0xc2f8787176b8ac6bf7215b4adcc1e069bf4ab82d9ab1df05a57a91d425935b6e;

    uint256 private immutable _cachedThis;
    uint256 private immutable _cachedChainId;
    bytes32 private immutable _cachedNameHash;
    bytes32 private immutable _cachedVersionHash;
    bytes32 private immutable _cachedDomainSeparator;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Cache the hashes for cheaper runtime gas costs.
    /// In the case of upgradeable contracts (i.e. proxies),
    /// or if the chain id changes due to a hard fork,
    /// the domain separator will be seamlessly calculated on-the-fly.
    constructor() {
        _cachedThis = uint256(uint160(address(this)));
        _cachedChainId = block.chainid;

        string memory name;
        string memory version;
        if (!_domainNameAndVersionMayChange()) (name, version) = _domainNameAndVersion();
        bytes32 nameHash = _domainNameAndVersionMayChange() ? bytes32(0) : keccak256(bytes(name));
        bytes32 versionHash =
            _domainNameAndVersionMayChange() ? bytes32(0) : keccak256(bytes(version));
        _cachedNameHash = nameHash;
        _cachedVersionHash = versionHash;

        bytes32 separator;
        if (!_domainNameAndVersionMayChange()) {
            /// @solidity memory-safe-assembly
            assembly {
                let m := mload(0x40) // Load the free memory pointer.
                mstore(m, _DOMAIN_TYPEHASH)
                mstore(add(m, 0x20), nameHash)
                mstore(add(m, 0x40), versionHash)
                mstore(add(m, 0x60), chainid())
                mstore(add(m, 0x80), address())
                separator := keccak256(m, 0xa0)
            }
        }
        _cachedDomainSeparator = separator;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   FUNCTIONS TO OVERRIDE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Please override this function to return the domain name and version.
    /// ```
    ///     function _domainNameAndVersion()
    ///         internal
    ///         pure
    ///         virtual
    ///         returns (string memory name, string memory version)
    ///     {
    ///         name = "Solady";
    ///         version = "1";
    ///     }
    /// ```
    ///
    /// Note: If the returned result may change after the contract has been deployed,
    /// you must override `_domainNameAndVersionMayChange()` to return true.
    function _domainNameAndVersion()
        internal
        view
        virtual
        returns (string memory name, string memory version);

    /// @dev Returns if `_domainNameAndVersion()` may change
    /// after the contract has been deployed (i.e. after the constructor).
    /// Default: false.
    function _domainNameAndVersionMayChange() internal pure virtual returns (bool result) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     HASHING OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the EIP-712 domain separator.
    function _domainSeparator() internal view virtual returns (bytes32 separator) {
        if (_domainNameAndVersionMayChange()) {
            separator = _buildDomainSeparator();
        } else {
            separator = _cachedDomainSeparator;
            if (_cachedDomainSeparatorInvalidated()) separator = _buildDomainSeparator();
        }
    }

    /// @dev Returns the hash of the fully encoded EIP-712 message for this domain,
    /// given `structHash`, as defined in
    /// https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct.
    ///
    /// The hash can be used together with {ECDSA-recover} to obtain the signer of a message:
    /// ```
    ///     bytes32 digest = _hashTypedData(keccak256(abi.encode(
    ///         keccak256("Mail(address to,string contents)"),
    ///         mailTo,
    ///         keccak256(bytes(mailContents))
    ///     )));
    ///     address signer = ECDSA.recover(digest, signature);
    /// ```
    function _hashTypedData(bytes32 structHash) internal view virtual returns (bytes32 digest) {
        // We will use `digest` to store the domain separator to save a bit of gas.
        if (_domainNameAndVersionMayChange()) {
            digest = _buildDomainSeparator();
        } else {
            digest = _cachedDomainSeparator;
            if (_cachedDomainSeparatorInvalidated()) digest = _buildDomainSeparator();
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the digest.
            mstore(0x00, 0x1901000000000000) // Store "\x19\x01".
            mstore(0x1a, digest) // Store the domain separator.
            mstore(0x3a, structHash) // Store the struct hash.
            digest := keccak256(0x18, 0x42)
            // Restore the part of the free memory slot that was overwritten.
            mstore(0x3a, 0)
        }
    }

    /// @dev Variant of `_hashTypedData` that excludes the chain ID.
    /// Included for the niche use case of cross-chain workflows.
    function _hashTypedDataSansChainId(bytes32 structHash)
        internal
        view
        virtual
        returns (bytes32 digest)
    {
        (string memory name, string memory version) = _domainNameAndVersion();
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Load the free memory pointer.
            mstore(0x00, _DOMAIN_TYPEHASH_SANS_CHAIN_ID)
            mstore(0x20, keccak256(add(name, 0x20), mload(name)))
            mstore(0x40, keccak256(add(version, 0x20), mload(version)))
            mstore(0x60, address())
            // Compute the digest.
            mstore(0x20, keccak256(0x00, 0x80)) // Store the domain separator.
            mstore(0x00, 0x1901) // Store "\x19\x01".
            mstore(0x40, structHash) // Store the struct hash.
            digest := keccak256(0x1e, 0x42)
            mstore(0x40, m) // Restore the free memory pointer.
            mstore(0x60, 0) // Restore the zero pointer.
        }
    }

    /// @dev Variant of `_hashTypedData` that excludes the chain ID and verifying contract.
    /// Included for the niche use case of cross-chain and multi-verifier workflows.
    function _hashTypedDataSansChainIdAndVerifyingContract(bytes32 structHash)
        internal
        view
        virtual
        returns (bytes32 digest)
    {
        (string memory name, string memory version) = _domainNameAndVersion();
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Load the free memory pointer.
            mstore(0x00, _DOMAIN_TYPEHASH_SANS_CHAIN_ID_AND_VERIFYING_CONTRACT)
            mstore(0x20, keccak256(add(name, 0x20), mload(name)))
            mstore(0x40, keccak256(add(version, 0x20), mload(version)))
            // Compute the digest.
            mstore(0x20, keccak256(0x00, 0x60)) // Store the domain separator.
            mstore(0x00, 0x1901) // Store "\x19\x01".
            mstore(0x40, structHash) // Store the struct hash.
            digest := keccak256(0x1e, 0x42)
            mstore(0x40, m) // Restore the free memory pointer.
            mstore(0x60, 0) // Restore the zero pointer.
        }
    }

    /// @dev Variant of `_hashTypedData` that excludes the chain ID and verifying contract.
    /// Included for the niche use case of multi-verifier workflows.
    function _hashTypedDataSansVerifyingContract(bytes32 structHash)
        internal
        view
        virtual
        returns (bytes32 digest)
    {
        (string memory name, string memory version) = _domainNameAndVersion();
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Load the free memory pointer.
            mstore(0x00, _DOMAIN_TYPEHASH_SANS_VERIFYING_CONTRACT)
            mstore(0x20, keccak256(add(name, 0x20), mload(name)))
            mstore(0x40, keccak256(add(version, 0x20), mload(version)))
            mstore(0x60, chainid())
            // Compute the digest.
            mstore(0x20, keccak256(0x00, 0x80)) // Store the domain separator.
            mstore(0x00, 0x1901) // Store "\x19\x01".
            mstore(0x40, structHash) // Store the struct hash.
            digest := keccak256(0x1e, 0x42)
            mstore(0x40, m) // Restore the free memory pointer.
            mstore(0x60, 0) // Restore the zero pointer.
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EIP-5267 OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev See: https://eips.ethereum.org/EIPS/eip-5267
    function eip712Domain()
        public
        view
        virtual
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        fields = hex"0f"; // `0b01111`.
        (name, version) = _domainNameAndVersion();
        chainId = block.chainid;
        verifyingContract = address(this);
        salt = salt; // `bytes32(0)`.
        extensions = extensions; // `new uint256[](0)`.
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the EIP-712 domain separator.
    function _buildDomainSeparator() private view returns (bytes32 separator) {
        // We will use `separator` to store the name hash to save a bit of gas.
        bytes32 versionHash;
        if (_domainNameAndVersionMayChange()) {
            (string memory name, string memory version) = _domainNameAndVersion();
            separator = keccak256(bytes(name));
            versionHash = keccak256(bytes(version));
        } else {
            separator = _cachedNameHash;
            versionHash = _cachedVersionHash;
        }
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Load the free memory pointer.
            mstore(m, _DOMAIN_TYPEHASH)
            mstore(add(m, 0x20), separator) // Name hash.
            mstore(add(m, 0x40), versionHash)
            mstore(add(m, 0x60), chainid())
            mstore(add(m, 0x80), address())
            separator := keccak256(m, 0xa0)
        }
    }

    /// @dev Returns if the cached domain separator has been invalidated.
    function _cachedDomainSeparatorInvalidated() private view returns (bool result) {
        uint256 cachedChainId = _cachedChainId;
        uint256 cachedThis = _cachedThis;
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(and(eq(chainid(), cachedChainId), eq(address(), cachedThis)))
        }
    }
}



// ============================================================
// FILE: node_modules/excessively-safe-call/src/ExcessivelySafeCall.sol
// ============================================================
// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.7.6;

library ExcessivelySafeCall {
    uint256 constant LOW_28_MASK =
        0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// @notice Use when you _really_ really _really_ don't trust the called
    /// contract. This prevents the called contract from causing reversion of
    /// the caller in as many ways as we can.
    /// @dev The main difference between this and a solidity low-level call is
    /// that we limit the number of bytes that the callee can cause to be
    /// copied to caller memory. This prevents stupid things like malicious
    /// contracts returning 10,000,000 bytes causing a local OOG when copying
    /// to memory.
    /// @param _target The address to call
    /// @param _gas The amount of gas to forward to the remote contract
    /// @param _value The value in wei to send to the remote contract
    /// @param _maxCopy The maximum number of bytes of returndata to copy
    /// to memory.
    /// @param _calldata The data to send to the remote contract
    /// @return success and returndata, as `.call()`. Returndata is capped to
    /// `_maxCopy` bytes.
    function excessivelySafeCall(
        address _target,
        uint256 _gas,
        uint256 _value,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal returns (bool, bytes memory) {
        // set up for assembly call
        uint256 _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := call(
                _gas, // gas
                _target, // recipient
                _value, // ether value
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to 256 bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }

    /// @notice Use when you _really_ really _really_ don't trust the called
    /// contract. This prevents the called contract from causing reversion of
    /// the caller in as many ways as we can.
    /// @dev The main difference between this and a solidity low-level call is
    /// that we limit the number of bytes that the callee can cause to be
    /// copied to caller memory. This prevents stupid things like malicious
    /// contracts returning 10,000,000 bytes causing a local OOG when copying
    /// to memory.
    /// @param _target The address to call
    /// @param _gas The amount of gas to forward to the remote contract
    /// @param _maxCopy The maximum number of bytes of returndata to copy
    /// to memory.
    /// @param _calldata The data to send to the remote contract
    /// @return success and returndata, as `.call()`. Returndata is capped to
    /// `_maxCopy` bytes.
    function excessivelySafeStaticCall(
        address _target,
        uint256 _gas,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal view returns (bool, bytes memory) {
        // set up for assembly call
        uint256 _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := staticcall(
                _gas, // gas
                _target, // recipient
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to 256 bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }

    /**
     * @notice Swaps function selectors in encoded contract calls
     * @dev Allows reuse of encoded calldata for functions with identical
     * argument types but different names. It simply swaps out the first 4 bytes
     * for the new selector. This function modifies memory in place, and should
     * only be used with caution.
     * @param _newSelector The new 4-byte selector
     * @param _buf The encoded contract args
     */
    function swapSelector(bytes4 _newSelector, bytes memory _buf)
        internal
        pure
    {
        require(_buf.length >= 4);
        uint256 _mask = LOW_28_MASK;
        assembly {
            // load the first word of
            let _word := mload(add(_buf, 0x20))
            // mask out the top 4 bytes
            // /x
            _word := and(_word, _mask)
            _word := or(_newSelector, _word)
            mstore(add(_buf, 0x20), _word)
        }
    }
}



// ============================================================
// FILE: node_modules/@erc7579/implementation/src/interfaces/IERC7579Account.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { CallType, ExecType, ModeCode } from "../lib/ModeLib.sol";

struct Execution {
    address target;
    uint256 value;
    bytes callData;
}

interface IERC7579Account {
    event ModuleInstalled(uint256 moduleTypeId, address module);
    event ModuleUninstalled(uint256 moduleTypeId, address module);

    /**
     * @dev Executes a transaction on behalf of the account.
     *         This function is intended to be called by ERC-4337 EntryPoint.sol
     * @dev Ensure adequate authorization control: i.e. onlyEntryPointOrSelf
     *
     * @dev MSA MUST implement this function signature.
     * If a mode is requested that is not supported by the Account, it MUST revert
     * @param mode The encoded execution mode of the transaction. See ModeLib.sol for details
     * @param executionCalldata The encoded execution call data
     */
    function execute(ModeCode mode, bytes calldata executionCalldata) external payable;

    /**
     * @dev Executes a transaction on behalf of the account.
     *         This function is intended to be called by Executor Modules
     * @dev Ensure adequate authorization control: i.e. onlyExecutorModule
     *
     * @dev MSA MUST implement this function signature.
     * If a mode is requested that is not supported by the Account, it MUST revert
     * @param mode The encoded execution mode of the transaction. See ModeLib.sol for details
     * @param executionCalldata The encoded execution call data
     */
    function executeFromExecutor(
        ModeCode mode,
        bytes calldata executionCalldata
    )
        external
        payable
        returns (bytes[] memory returnData);

    /**
     * @dev ERC-1271 isValidSignature
     *         This function is intended to be used to validate a smart account signature
     * and may forward the call to a validator module
     *
     * @param hash The hash of the data that is signed
     * @param data The data that is signed
     */
    function isValidSignature(bytes32 hash, bytes calldata data) external view returns (bytes4);

    /**
     * @dev installs a Module of a certain type on the smart account
     * @dev Implement Authorization control of your chosing
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     * @param module the module address
     * @param initData arbitrary data that may be required on the module during `onInstall`
     * initialization.
     */
    function installModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata initData
    )
        external
        payable;

    /**
     * @dev uninstalls a Module of a certain type on the smart account
     * @dev Implement Authorization control of your chosing
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     * @param module the module address
     * @param deInitData arbitrary data that may be required on the module during `onUninstall`
     * de-initialization.
     */
    function uninstallModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata deInitData
    )
        external
        payable;

    /**
     * Function to check if the account supports a certain CallType or ExecType (see ModeLib.sol)
     * @param encodedMode the encoded mode
     */
    function supportsExecutionMode(ModeCode encodedMode) external view returns (bool);

    /**
     * Function to check if the account supports installation of a certain module type Id
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     */
    function supportsModule(uint256 moduleTypeId) external view returns (bool);

    /**
     * Function to check if the account has a certain module installed
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     *      Note: keep in mind that some contracts can be multiple module types at the same time. It
     *            thus may be necessary to query multiple module types
     * @param module the module address
     * @param additionalContext additional context data that the smart account may interpret to
     *                          identifiy conditions under which the module is installed.
     *                          usually this is not necessary, but for some special hooks that
     *                          are stored in mappings, this param might be needed
     */
    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata additionalContext
    )
        external
        view
        returns (bool);

    /**
     * @dev Returns the account id of the smart account
     * @return accountImplementationId the account id of the smart account
     * the accountId should be structured like so:
     *        "vendorname.accountname.semver"
     */
    function accountId() external view returns (string memory accountImplementationId);
}



// ============================================================
// FILE: contracts/interfaces/nexus/base/IExecutionHelper.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { ExecutionMode } from "../../../lib/erc-7579/ModeLib.sol";
import { IExecutionHelperEventsAndErrors } from "./IExecutionHelperEventsAndErrors.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";

/// @title Nexus - IExecutionHelper
/// @notice Interface for executing transactions on behalf of smart accounts within the Nexus system.
/// @dev Extends functionality for transaction execution with error handling as defined in
/// IExecutionHelperEventsAndErrors.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IExecutionHelper is IExecutionHelperEventsAndErrors {
    /// @notice Executes a transaction with specified execution mode and calldata.
    /// @param mode The execution mode, defining how the transaction is processed.
    /// @param executionCalldata The calldata to execute.
    /// @dev This function ensures that the execution complies with smart account execution policies and handles errors
    /// appropriately.
    function execute(ExecutionMode mode, bytes calldata executionCalldata) external payable;

    /// @notice Allows an executor module to perform transactions on behalf of the account.
    /// @param mode The execution mode that details how the transaction should be handled.
    /// @param executionCalldata The transaction data to be executed.
    /// @return returnData The result of the execution, allowing for error handling and results interpretation by the
    /// executor module.
    function executeFromExecutor(
        ExecutionMode mode,
        bytes calldata executionCalldata
    )
        external
        payable
        returns (bytes[] memory returnData);

    /**
     * Account may implement this execute method.
     * passing this methodSig at the beginning of callData will cause the entryPoint to pass the full UserOp (and hash)
     * to the account.
     * The account should skip the methodSig, and use the callData (and optionally, other UserOp fields)
     *
     * @param userOp              - The operation that was just validated.
     * @param userOpHash          - Hash of the user's request data.
     */
    function executeUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) external payable;
}



// ============================================================
// FILE: contracts/composability/ComposableExecutionLib.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ComposableStorage } from "./ComposableStorage.sol";
import {
    InputParam,
    OutputParam,
    Constraint,
    ConstraintType,
    InputParamType,
    InputParamFetcherType,
    OutputParamFetcherType
} from "../types/ComposabilityDataTypes.sol";
import { Execution } from "erc7579/interfaces/IERC7579Account.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Library for composable execution handling
library ComposableExecutionLib {
    error ConstraintNotMet(ConstraintType constraintType);
    error Output_StaticCallFailed();
    error InvalidParameterEncoding(string message);
    error InvalidOutputParamFetcherType();
    error InvalidConstraintType();
    error InvalidSetOfInputParams(string message);

    // Process the input parameters and return the composed calldata
    function processInputs(
        InputParam[] calldata inputParams,
        bytes4 functionSig
    )
        internal
        view
        returns (Execution memory)
    {
        address composedTarget;
        uint256 composedValue;
        bytes memory composedCalldata = abi.encodePacked(functionSig);
        uint256 length = inputParams.length;

        // Bit 0: TARGET param type set, Bit 1: VALUE param type set
        uint256 paramTypeFlags = 0;
        for (uint256 i; i < length; i++) {
            bytes memory processedInput = processInput(inputParams[i]);
            if (inputParams[i].paramType == InputParamType.TARGET) {
                if (inputParams[i].fetcherType == InputParamFetcherType.BALANCE) {
                    revert InvalidParameterEncoding("BALANCE fetcher type is not supported for TARGET param type");
                }
                // Check if TARGET has already been set (bit 0)
                if (paramTypeFlags & 1 != 0) {
                    revert InvalidSetOfInputParams("TARGET param type can only be set once");
                }
                paramTypeFlags |= 1; // Set bit 0
                composedTarget = abi.decode(processedInput, (address));
            } else if (inputParams[i].paramType == InputParamType.VALUE) {
                // Check if VALUE has already been set (bit 1)
                if (paramTypeFlags & 2 != 0) {
                    revert InvalidSetOfInputParams("VALUE param type can only be set once");
                }
                paramTypeFlags |= 2; // Set bit 1
                composedValue = abi.decode(processedInput, (uint256));
            } else if (inputParams[i].paramType == InputParamType.CALL_DATA) {
                composedCalldata = bytes.concat(composedCalldata, processedInput);
            } else {
                revert InvalidParameterEncoding("Invalid param type");
            }
        }
        // if a param with TARGET type was not provided, it will be address(0)
        // we don't restrict it since some calls may want to call address(0)
        // if a param with VALUE type was not provided, it will be 0
        // this is even more often case, as many calls happen with 0 value
        return Execution({ target: composedTarget, value: composedValue, callData: composedCalldata });
    }

    // Process a single input parameter and return the composed calldata
    function processInput(InputParam calldata param) internal view returns (bytes memory) {
        if (param.fetcherType == InputParamFetcherType.RAW_BYTES) {
            _validateConstraints(param.paramData, param.constraints);
            return param.paramData;
        } else if (param.fetcherType == InputParamFetcherType.STATIC_CALL) {
            address contractAddr;
            bytes calldata callData;
            bytes calldata paramData = param.paramData;
            // expect paramData to be abi.encode(address contractAddr, bytes callData)
            assembly {
                contractAddr := calldataload(paramData.offset)
                let s := calldataload(add(paramData.offset, 0x20))
                let u := add(paramData.offset, s)
                callData.offset := add(u, 0x20)
                callData.length := calldataload(u)
            }
            (bool success, bytes memory returnData) = contractAddr.staticcall(callData);
            assembly {
                if iszero(success) {
                    // revert ComposableExecutionFailed()
                    mstore(0x00, 0x6533cc8d)
                    revert(0x1c, 0x04)
                }
            }
            _validateConstraints(returnData, param.constraints);
            return returnData;
        } else if (param.fetcherType == InputParamFetcherType.BALANCE) {
            address tokenAddr;
            address account;
            bytes calldata paramData = param.paramData;

            // expect paramData to be abi.encodePacked(address token, address account)
            // Validate exact length requirement
            require(paramData.length == 40, InvalidParameterEncoding("Invalid paramData length"));
            assembly {
                tokenAddr := shr(96, calldataload(paramData.offset))
                account := shr(96, calldataload(add(paramData.offset, 0x14)))
            }

            uint256 balance;
            if (tokenAddr == address(0)) {
                balance = account.balance;
            } else {
                balance = IERC20(tokenAddr).balanceOf(account);
            }
            _validateConstraints(abi.encode(balance), param.constraints);
            return abi.encode(balance);
        } else {
            revert InvalidParameterEncoding("Invalid param fetcher type");
        }
    }

    // Process the output parameters
    function processOutputs(OutputParam[] calldata outputParams, bytes memory returnData, address account) internal {
        uint256 length = outputParams.length;
        for (uint256 i; i < length; i++) {
            processOutput(outputParams[i], returnData, account);
        }
    }

    // Process a single output parameter and write to storage
    function processOutput(OutputParam calldata param, bytes memory returnData, address account) internal {
        // only static types are supported for now as return values
        // can also process all the static return values which are before the first dynamic return value in the
        // returnData
        if (param.fetcherType == OutputParamFetcherType.EXEC_RESULT) {
            uint256 returnValues;
            address targetStorageContract;
            bytes32 targetStorageSlot;
            bytes calldata paramData = param.paramData;
            assembly {
                returnValues := calldataload(paramData.offset)
                targetStorageContract := calldataload(add(paramData.offset, 0x20))
                targetStorageSlot := calldataload(add(paramData.offset, 0x40))
            }
            _parseReturnDataAndWriteToStorage(
                returnValues, returnData, targetStorageContract, targetStorageSlot, account
            );
            // same for static calls
        } else if (param.fetcherType == OutputParamFetcherType.STATIC_CALL) {
            uint256 returnValues;
            address sourceContract;
            bytes calldata sourceCallData;
            address targetStorageContract;
            bytes32 targetStorageSlot;
            bytes calldata paramData = param.paramData;
            assembly {
                returnValues := calldataload(paramData.offset)
                sourceContract := calldataload(add(paramData.offset, 0x20))
                let s := calldataload(add(paramData.offset, 0x40))
                let u := add(paramData.offset, s)
                sourceCallData.offset := add(u, 0x20)
                sourceCallData.length := calldataload(u)
                targetStorageContract := calldataload(add(paramData.offset, 0x60))
                targetStorageSlot := calldataload(add(paramData.offset, 0x80))
            }
            (bool outputSuccess, bytes memory outputReturnData) = sourceContract.staticcall(sourceCallData);
            if (!outputSuccess) {
                revert Output_StaticCallFailed();
            }
            _parseReturnDataAndWriteToStorage(
                returnValues, outputReturnData, targetStorageContract, targetStorageSlot, account
            );
        } else {
            revert InvalidOutputParamFetcherType();
        }
    }

    /// @dev Validate the constraints => compare the value with the reference data
    function _validateConstraints(bytes memory rawValue, Constraint[] calldata constraints) private pure {
        if (constraints.length > 0) {
            for (uint256 i; i < constraints.length; i++) {
                Constraint memory constraint = constraints[i];
                bytes32 returnValue;
                assembly {
                    returnValue := mload(add(rawValue, add(0x20, mul(i, 0x20))))
                }
                if (constraint.constraintType == ConstraintType.EQ) {
                    require(returnValue == bytes32(constraint.referenceData), ConstraintNotMet(ConstraintType.EQ));
                } else if (constraint.constraintType == ConstraintType.GTE) {
                    require(returnValue >= bytes32(constraint.referenceData), ConstraintNotMet(ConstraintType.GTE));
                } else if (constraint.constraintType == ConstraintType.LTE) {
                    require(returnValue <= bytes32(constraint.referenceData), ConstraintNotMet(ConstraintType.LTE));
                } else if (constraint.constraintType == ConstraintType.IN) {
                    (bytes32 lowerBound, bytes32 upperBound) = abi.decode(constraint.referenceData, (bytes32, bytes32));
                    require(returnValue >= lowerBound && returnValue <= upperBound, ConstraintNotMet(ConstraintType.IN));
                } else {
                    revert InvalidConstraintType();
                }
            }
        }
    }

    /// @dev Parse the return data and write to the appropriate storage contract
    function _parseReturnDataAndWriteToStorage(
        uint256 returnValues,
        bytes memory returnData,
        address targetStorageContract,
        bytes32 targetStorageSlot,
        address account
    )
        internal
    {
        for (uint256 i; i < returnValues; i++) {
            bytes32 value;
            assembly {
                value := mload(add(returnData, add(0x20, mul(i, 0x20))))
            }
            ComposableStorage(targetStorageContract)
                .writeStorage({
                    slot: keccak256(abi.encodePacked(targetStorageSlot, i)), value: value, account: account
                });
        }
    }
}



// ============================================================
// FILE: contracts/types/ComposabilityDataTypes.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Type of the input parameter
enum InputParamType {
    TARGET, // The target address
    VALUE, // The value
    CALL_DATA // The call data
}

// Parameter type for composition
enum InputParamFetcherType {
    RAW_BYTES, // Already encoded bytes
    STATIC_CALL, // Perform a static call
    BALANCE // Get the balance of an address
}

enum OutputParamFetcherType {
    EXEC_RESULT, // The return of the execution call
    STATIC_CALL // Call to some other function
}

// Constraint type for parameter validation
enum ConstraintType {
    EQ, // Equal to
    GTE, // Greater than or equal to
    LTE, // Less than or equal to
    IN // In range
}

// Constraint for parameter validation
struct Constraint {
    ConstraintType constraintType;
    bytes referenceData;
}

// Structure to define parameter composition
struct InputParam {
    InputParamType paramType;
    InputParamFetcherType fetcherType; // How to fetch the parameter
    bytes paramData;
    Constraint[] constraints;
}

// Structure to define return value handling
struct OutputParam {
    OutputParamFetcherType fetcherType; // How to fetch the parameter
    bytes paramData;
}

// Structure to define a composable execution
struct ComposableExecution {
    bytes4 functionSig;
    InputParam[] inputParams;
    OutputParam[] outputParams;
}



// ============================================================
// FILE: contracts/interfaces/IComposableExecution.sol
// ============================================================
// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.23;

import { ComposableExecution } from "../types/ComposabilityDataTypes.sol";

interface IComposableExecution {
    function executeComposable(ComposableExecution[] calldata cExecutions) external payable;
}

interface IComposableExecutionModule is IComposableExecution {
    function executeComposableCall(ComposableExecution[] calldata cExecutions) external;
    function executeComposableDelegateCall(ComposableExecution[] calldata cExecutions) external;
}



// ============================================================
// FILE: node_modules/solady/src/utils/CallContextChecker.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Call context checker mixin.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/CallContextChecker.sol)
contract CallContextChecker {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The call is from an unauthorized call context.
    error UnauthorizedCallContext();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         IMMUTABLES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev For checking if the context is a delegate call.
    ///
    /// Note: To enable use cases with an immutable default implementation in the bytecode,
    /// (see: ERC6551Proxy), we don't require that the proxy address must match the
    /// value stored in the implementation slot, which may not be initialized.
    uint256 private immutable __self = uint256(uint160(address(this)));

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    CALL CONTEXT CHECKS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // A proxy call can be either via a `delegatecall` to an implementation,
    // or a 7702 call on an authority that points to a delegation.

    /// @dev Returns whether the current call context is on a EIP7702 authority
    /// (i.e. externally owned account).
    function _onEIP7702Authority() internal view virtual returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            extcodecopy(address(), 0x00, 0x00, 0x20)
            // Note: Checking that it starts with hex"ef01" is the most general and futureproof.
            // 7702 bytecode is `abi.encodePacked(hex"ef01", uint8(version), address(delegation))`.
            result := eq(0xef01, shr(240, mload(0x00)))
        }
    }

    /// @dev Returns the implementation of this contract.
    function _selfImplementation() internal view virtual returns (address) {
        return address(uint160(__self));
    }

    /// @dev Returns whether the current call context is on the implementation itself.
    function _onImplementation() internal view virtual returns (bool) {
        return __self == uint160(address(this));
    }

    /// @dev Requires that the current call context is performed via a EIP7702 authority.
    function _checkOnlyEIP7702Authority() internal view virtual {
        if (!_onEIP7702Authority()) _revertUnauthorizedCallContext();
    }

    /// @dev Requires that the current call context is performed via a proxy.
    function _checkOnlyProxy() internal view virtual {
        if (_onImplementation()) _revertUnauthorizedCallContext();
    }

    /// @dev Requires that the current call context is NOT performed via a proxy.
    /// This is the opposite of `checkOnlyProxy`.
    function _checkNotDelegated() internal view virtual {
        if (!_onImplementation()) _revertUnauthorizedCallContext();
    }

    /// @dev Requires that the current call context is performed via a EIP7702 authority.
    modifier onlyEIP7702Authority() virtual {
        _checkOnlyEIP7702Authority();
        _;
    }

    /// @dev Requires that the current call context is performed via a proxy.
    modifier onlyProxy() virtual {
        _checkOnlyProxy();
        _;
    }

    /// @dev Requires that the current call context is NOT performed via a proxy.
    /// This is the opposite of `onlyProxy`.
    modifier notDelegated() virtual {
        _checkNotDelegated();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _revertUnauthorizedCallContext() private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x9f03a026) // `UnauthorizedCallContext()`.
            revert(0x1c, 0x04)
        }
    }
}



// ============================================================
// FILE: contracts/interfaces/nexus/base/IAccountConfig.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { ExecutionMode } from "../../../lib/erc-7579/ModeLib.sol";

/// @title Nexus - ERC-7579 Account Configuration Interface
/// @notice Interface for querying and verifying configurations of Smart Accounts compliant with ERC-7579.
/// @dev Provides methods to check supported execution modes and module types for Smart Accounts, ensuring flexible and
/// extensible configuration.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IAccountConfig {
    /// @notice Returns the account ID in a structured format: "vendorname.accountname.semver"
    /// @return accountImplementationId The account ID of the smart account
    function accountId() external view returns (string memory accountImplementationId);

    /// @notice Checks if the account supports a certain execution mode.
    /// @param encodedMode The encoded mode to verify.
    /// @return supported True if the account supports the mode, false otherwise.
    function supportsExecutionMode(ExecutionMode encodedMode) external view returns (bool supported);

    /// @notice Checks if the account supports a specific module type.
    /// @param moduleTypeId The module type ID to verify.
    /// @return supported True if the account supports the module type, false otherwise.
    function supportsModule(uint256 moduleTypeId) external view returns (bool supported);
}



// ============================================================
// FILE: contracts/interfaces/nexus/INexusEventsAndErrors.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

/// @title Nexus - INexus Events and Errors
/// @notice Defines common errors for the Nexus smart account management interface.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface INexusEventsAndErrors {
    /// @notice Error thrown when an unsupported ModuleType is requested.
    /// @param moduleTypeId The ID of the unsupported module type.
    error UnsupportedModuleType(uint256 moduleTypeId);

    /// @notice Error thrown when a zero address is provided as the Entry Point address.
    error EntryPointCanNotBeZero();

    /// @notice Error thrown when the provided implementation address is invalid.
    error InvalidImplementationAddress();

    /// @notice Error thrown when attempted to emergency-uninstall a hook
    error EmergencyTimeLockNotExpired();

    /// @notice Error thrown when attempted to upgrade an ERC7702 account via UUPS proxy upgrade mechanism
    error ERC7702AccountCannotBeUpgradedThisWay();

    /// @notice Error thrown when the provided initData is invalid.
    error InvalidInitData();

    /// @notice Error thrown when the account is already initialized.
    error AccountAlreadyInitialized();

    /// @notice Error thrown when the account is not initialized but expected to be.
    error AccountNotInitialized();

    /// @notice Error thrown when the provided signature is invalid.
    error InvalidSignature();
}



// ============================================================
// FILE: contracts/interfaces/standard/IERC1271.sol
// ============================================================
// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.27;

interface IERC1271 {
    /**
     * @dev Should return whether the signature provided is valid for the provided data
     * @param _dataHash Arbitrary length data signed on behalf of address(this)
     * @param _signature Signature byte array associated with _data
     *
     * MUST return the bytes4 magic value 0x1626ba7e when function passes.
     * MUST NOT modify state (using STATICCALL for solc < 0.5, view modifier for solc >
     * 0.5)
     * MUST allow external calls
     */
    function isValidSignature(bytes32 _dataHash, bytes calldata _signature) external view returns (bytes4);
}



// ============================================================
// FILE: node_modules/account-abstraction/contracts/interfaces/IAccount.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.5;

import "./PackedUserOperation.sol";

interface IAccount {
    /**
     * Validate user's signature and nonce
     * the entryPoint will make the call to the recipient only if this validation call returns successfully.
     * signature failure should be reported by returning SIG_VALIDATION_FAILED (1).
     * This allows making a "simulation call" without a valid signature
     * Other failures (e.g. nonce mismatch, or invalid signature format) should still revert to signal failure.
     *
     * @dev Must validate caller is the entryPoint.
     *      Must validate the signature and nonce
     * @param userOp              - The operation that is about to be executed.
     * @param userOpHash          - Hash of the user's request data. can be used as the basis for signature.
     * @param missingAccountFunds - Missing funds on the account's deposit in the entrypoint.
     *                              This is the minimum amount to transfer to the sender(entryPoint) to be
     *                              able to make the call. The excess is left as a deposit in the entrypoint
     *                              for future calls. Can be withdrawn anytime using "entryPoint.withdrawTo()".
     *                              In case there is a paymaster in the request (or the current deposit is high
     *                              enough), this value will be zero.
     * @return validationData       - Packaged ValidationData structure. use `_packValidationData` and
     *                              `_unpackValidationData` to encode and decode.
     *                              <20-byte> sigAuthorizer - 0 for valid signature, 1 to mark signature failure,
     *                                 otherwise, an address of an "authorizer" contract.
     *                              <6-byte> validUntil - Last timestamp this operation is valid. 0 for "indefinite"
     *                              <6-byte> validAfter - First timestamp this operation is valid
     *                                                    If an account doesn't use time-range, it is enough to
     *                                                    return SIG_VALIDATION_FAILED value (1) for signature failure.
     *                              Note that the validation code cannot use block.timestamp (or block.number) directly.
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);
}



// ============================================================
// FILE: node_modules/solady/src/utils/EfficientHashLib.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Library for efficiently performing keccak256 hashes.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/EfficientHashLib.sol)
/// @dev To avoid stack-too-deep, you can use:
/// ```
/// bytes32[] memory buffer = EfficientHashLib.malloc(10);
/// EfficientHashLib.set(buffer, 0, value0);
/// ..
/// EfficientHashLib.set(buffer, 9, value9);
/// bytes32 finalHash = EfficientHashLib.hash(buffer);
/// ```
library EfficientHashLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               MALLOC-LESS HASHING OPERATIONS               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns `keccak256(abi.encode(v0))`.
    function hash(bytes32 v0) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, v0)
            result := keccak256(0x00, 0x20)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0))`.
    function hash(uint256 v0) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, v0)
            result := keccak256(0x00, 0x20)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, v1))`.
    function hash(bytes32 v0, bytes32 v1) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, v0)
            mstore(0x20, v1)
            result := keccak256(0x00, 0x40)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, v1))`.
    function hash(uint256 v0, uint256 v1) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, v0)
            mstore(0x20, v1)
            result := keccak256(0x00, 0x40)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, v1, v2))`.
    function hash(bytes32 v0, bytes32 v1, bytes32 v2) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            result := keccak256(m, 0x60)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, v1, v2))`.
    function hash(uint256 v0, uint256 v1, uint256 v2) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            result := keccak256(m, 0x60)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, v1, v2, v3))`.
    function hash(bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3)
        internal
        pure
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            result := keccak256(m, 0x80)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, v1, v2, v3))`.
    function hash(uint256 v0, uint256 v1, uint256 v2, uint256 v3)
        internal
        pure
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            result := keccak256(m, 0x80)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v4))`.
    function hash(bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4)
        internal
        pure
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            result := keccak256(m, 0xa0)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v4))`.
    function hash(uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4)
        internal
        pure
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            result := keccak256(m, 0xa0)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v5))`.
    function hash(bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5)
        internal
        pure
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            result := keccak256(m, 0xc0)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v5))`.
    function hash(uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5)
        internal
        pure
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            result := keccak256(m, 0xc0)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v6))`.
    function hash(
        bytes32 v0,
        bytes32 v1,
        bytes32 v2,
        bytes32 v3,
        bytes32 v4,
        bytes32 v5,
        bytes32 v6
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            result := keccak256(m, 0xe0)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v6))`.
    function hash(
        uint256 v0,
        uint256 v1,
        uint256 v2,
        uint256 v3,
        uint256 v4,
        uint256 v5,
        uint256 v6
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            result := keccak256(m, 0xe0)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v7))`.
    function hash(
        bytes32 v0,
        bytes32 v1,
        bytes32 v2,
        bytes32 v3,
        bytes32 v4,
        bytes32 v5,
        bytes32 v6,
        bytes32 v7
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            result := keccak256(m, 0x100)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v7))`.
    function hash(
        uint256 v0,
        uint256 v1,
        uint256 v2,
        uint256 v3,
        uint256 v4,
        uint256 v5,
        uint256 v6,
        uint256 v7
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            result := keccak256(m, 0x100)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v8))`.
    function hash(
        bytes32 v0,
        bytes32 v1,
        bytes32 v2,
        bytes32 v3,
        bytes32 v4,
        bytes32 v5,
        bytes32 v6,
        bytes32 v7,
        bytes32 v8
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            result := keccak256(m, 0x120)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v8))`.
    function hash(
        uint256 v0,
        uint256 v1,
        uint256 v2,
        uint256 v3,
        uint256 v4,
        uint256 v5,
        uint256 v6,
        uint256 v7,
        uint256 v8
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            result := keccak256(m, 0x120)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v9))`.
    function hash(
        bytes32 v0,
        bytes32 v1,
        bytes32 v2,
        bytes32 v3,
        bytes32 v4,
        bytes32 v5,
        bytes32 v6,
        bytes32 v7,
        bytes32 v8,
        bytes32 v9
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            result := keccak256(m, 0x140)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v9))`.
    function hash(
        uint256 v0,
        uint256 v1,
        uint256 v2,
        uint256 v3,
        uint256 v4,
        uint256 v5,
        uint256 v6,
        uint256 v7,
        uint256 v8,
        uint256 v9
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            result := keccak256(m, 0x140)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v10))`.
    function hash(
        bytes32 v0,
        bytes32 v1,
        bytes32 v2,
        bytes32 v3,
        bytes32 v4,
        bytes32 v5,
        bytes32 v6,
        bytes32 v7,
        bytes32 v8,
        bytes32 v9,
        bytes32 v10
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            mstore(add(m, 0x140), v10)
            result := keccak256(m, 0x160)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v10))`.
    function hash(
        uint256 v0,
        uint256 v1,
        uint256 v2,
        uint256 v3,
        uint256 v4,
        uint256 v5,
        uint256 v6,
        uint256 v7,
        uint256 v8,
        uint256 v9,
        uint256 v10
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            mstore(add(m, 0x140), v10)
            result := keccak256(m, 0x160)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v11))`.
    function hash(
        bytes32 v0,
        bytes32 v1,
        bytes32 v2,
        bytes32 v3,
        bytes32 v4,
        bytes32 v5,
        bytes32 v6,
        bytes32 v7,
        bytes32 v8,
        bytes32 v9,
        bytes32 v10,
        bytes32 v11
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            mstore(add(m, 0x140), v10)
            mstore(add(m, 0x160), v11)
            result := keccak256(m, 0x180)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v11))`.
    function hash(
        uint256 v0,
        uint256 v1,
        uint256 v2,
        uint256 v3,
        uint256 v4,
        uint256 v5,
        uint256 v6,
        uint256 v7,
        uint256 v8,
        uint256 v9,
        uint256 v10,
        uint256 v11
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            mstore(add(m, 0x140), v10)
            mstore(add(m, 0x160), v11)
            result := keccak256(m, 0x180)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v12))`.
    function hash(
        bytes32 v0,
        bytes32 v1,
        bytes32 v2,
        bytes32 v3,
        bytes32 v4,
        bytes32 v5,
        bytes32 v6,
        bytes32 v7,
        bytes32 v8,
        bytes32 v9,
        bytes32 v10,
        bytes32 v11,
        bytes32 v12
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            mstore(add(m, 0x140), v10)
            mstore(add(m, 0x160), v11)
            mstore(add(m, 0x180), v12)
            result := keccak256(m, 0x1a0)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v12))`.
    function hash(
        uint256 v0,
        uint256 v1,
        uint256 v2,
        uint256 v3,
        uint256 v4,
        uint256 v5,
        uint256 v6,
        uint256 v7,
        uint256 v8,
        uint256 v9,
        uint256 v10,
        uint256 v11,
        uint256 v12
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            mstore(add(m, 0x140), v10)
            mstore(add(m, 0x160), v11)
            mstore(add(m, 0x180), v12)
            result := keccak256(m, 0x1a0)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v13))`.
    function hash(
        bytes32 v0,
        bytes32 v1,
        bytes32 v2,
        bytes32 v3,
        bytes32 v4,
        bytes32 v5,
        bytes32 v6,
        bytes32 v7,
        bytes32 v8,
        bytes32 v9,
        bytes32 v10,
        bytes32 v11,
        bytes32 v12,
        bytes32 v13
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            mstore(add(m, 0x140), v10)
            mstore(add(m, 0x160), v11)
            mstore(add(m, 0x180), v12)
            mstore(add(m, 0x1a0), v13)
            result := keccak256(m, 0x1c0)
        }
    }

    /// @dev Returns `keccak256(abi.encode(v0, .., v13))`.
    function hash(
        uint256 v0,
        uint256 v1,
        uint256 v2,
        uint256 v3,
        uint256 v4,
        uint256 v5,
        uint256 v6,
        uint256 v7,
        uint256 v8,
        uint256 v9,
        uint256 v10,
        uint256 v11,
        uint256 v12,
        uint256 v13
    ) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, v0)
            mstore(add(m, 0x20), v1)
            mstore(add(m, 0x40), v2)
            mstore(add(m, 0x60), v3)
            mstore(add(m, 0x80), v4)
            mstore(add(m, 0xa0), v5)
            mstore(add(m, 0xc0), v6)
            mstore(add(m, 0xe0), v7)
            mstore(add(m, 0x100), v8)
            mstore(add(m, 0x120), v9)
            mstore(add(m, 0x140), v10)
            mstore(add(m, 0x160), v11)
            mstore(add(m, 0x180), v12)
            mstore(add(m, 0x1a0), v13)
            result := keccak256(m, 0x1c0)
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*             BYTES32 BUFFER HASHING OPERATIONS              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns `keccak256(abi.encode(buffer[0], .., buffer[buffer.length - 1]))`.
    function hash(bytes32[] memory buffer) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := keccak256(add(buffer, 0x20), shl(5, mload(buffer)))
        }
    }

    /// @dev Sets `buffer[i]` to `value`, without a bounds check.
    /// Returns the `buffer` for function chaining.
    function set(bytes32[] memory buffer, uint256 i, bytes32 value)
        internal
        pure
        returns (bytes32[] memory)
    {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(add(buffer, shl(5, add(1, i))), value)
        }
        return buffer;
    }

    /// @dev Sets `buffer[i]` to `value`, without a bounds check.
    /// Returns the `buffer` for function chaining.
    function set(bytes32[] memory buffer, uint256 i, uint256 value)
        internal
        pure
        returns (bytes32[] memory)
    {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(add(buffer, shl(5, add(1, i))), value)
        }
        return buffer;
    }

    /// @dev Returns `new bytes32[](n)`, without zeroing out the memory.
    function malloc(uint256 n) internal pure returns (bytes32[] memory buffer) {
        /// @solidity memory-safe-assembly
        assembly {
            buffer := mload(0x40)
            mstore(buffer, n)
            mstore(0x40, add(shl(5, add(1, n)), buffer))
        }
    }

    /// @dev Frees memory that has been allocated for `buffer`.
    /// No-op if `buffer.length` is zero, or if new memory has been allocated after `buffer`.
    function free(bytes32[] memory buffer) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            let n := mload(buffer)
            mstore(shl(6, lt(iszero(n), eq(add(shl(5, add(1, n)), buffer), mload(0x40)))), buffer)
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EQUALITY CHECKS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns `a == abi.decode(b, (bytes32))`.
    function eq(bytes32 a, bytes memory b) internal pure returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := and(eq(0x20, mload(b)), eq(a, mload(add(b, 0x20))))
        }
    }

    /// @dev Returns `abi.decode(a, (bytes32)) == b`.
    function eq(bytes memory a, bytes32 b) internal pure returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := and(eq(0x20, mload(a)), eq(b, mload(add(a, 0x20))))
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               BYTE SLICE HASHING OPERATIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the keccak256 of the slice from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets.
    function hash(bytes memory b, uint256 start, uint256 end)
        internal
        pure
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let n := mload(b)
            end := xor(end, mul(xor(end, n), lt(n, end)))
            start := xor(start, mul(xor(start, n), lt(n, start)))
            result := keccak256(add(add(b, 0x20), start), mul(gt(end, start), sub(end, start)))
        }
    }

    /// @dev Returns the keccak256 of the slice from `start` to the end of the bytes.
    function hash(bytes memory b, uint256 start) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let n := mload(b)
            start := xor(start, mul(xor(start, n), lt(n, start)))
            result := keccak256(add(add(b, 0x20), start), mul(gt(n, start), sub(n, start)))
        }
    }

    /// @dev Returns the keccak256 of the bytes.
    function hash(bytes memory b) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := keccak256(add(b, 0x20), mload(b))
        }
    }

    /// @dev Returns the keccak256 of the slice from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets.
    function hashCalldata(bytes calldata b, uint256 start, uint256 end)
        internal
        pure
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            end := xor(end, mul(xor(end, b.length), lt(b.length, end)))
            start := xor(start, mul(xor(start, b.length), lt(b.length, start)))
            let n := mul(gt(end, start), sub(end, start))
            calldatacopy(mload(0x40), add(b.offset, start), n)
            result := keccak256(mload(0x40), n)
        }
    }

    /// @dev Returns the keccak256 of the slice from `start` to the end of the bytes.
    function hashCalldata(bytes calldata b, uint256 start) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            start := xor(start, mul(xor(start, b.length), lt(b.length, start)))
            let n := mul(gt(b.length, start), sub(b.length, start))
            calldatacopy(mload(0x40), add(b.offset, start), n)
            result := keccak256(mload(0x40), n)
        }
    }

    /// @dev Returns the keccak256 of the bytes.
    function hashCalldata(bytes calldata b) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            calldatacopy(mload(0x40), b.offset, b.length)
            result := keccak256(mload(0x40), b.length)
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      SHA2-256 HELPERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns `sha256(abi.encode(b))`. Yes, it's more efficient.
    function sha2(bytes32 b) internal view returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, b)
            result := mload(staticcall(gas(), 2, 0x00, 0x20, 0x01, 0x20))
            if iszero(returndatasize()) { invalid() }
        }
    }

    /// @dev Returns the sha256 of the slice from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets.
    function sha2(bytes memory b, uint256 start, uint256 end)
        internal
        view
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let n := mload(b)
            end := xor(end, mul(xor(end, n), lt(n, end)))
            start := xor(start, mul(xor(start, n), lt(n, start)))
            // forgefmt: disable-next-item
            result := mload(staticcall(gas(), 2, add(add(b, 0x20), start),
                mul(gt(end, start), sub(end, start)), 0x01, 0x20))
            if iszero(returndatasize()) { invalid() }
        }
    }

    /// @dev Returns the sha256 of the slice from `start` to the end of the bytes.
    function sha2(bytes memory b, uint256 start) internal view returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let n := mload(b)
            start := xor(start, mul(xor(start, n), lt(n, start)))
            // forgefmt: disable-next-item
            result := mload(staticcall(gas(), 2, add(add(b, 0x20), start),
                mul(gt(n, start), sub(n, start)), 0x01, 0x20))
            if iszero(returndatasize()) { invalid() }
        }
    }

    /// @dev Returns the sha256 of the bytes.
    function sha2(bytes memory b) internal view returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(staticcall(gas(), 2, add(b, 0x20), mload(b), 0x01, 0x20))
            if iszero(returndatasize()) { invalid() }
        }
    }

    /// @dev Returns the sha256 of the slice from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets.
    function sha2Calldata(bytes calldata b, uint256 start, uint256 end)
        internal
        view
        returns (bytes32 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            end := xor(end, mul(xor(end, b.length), lt(b.length, end)))
            start := xor(start, mul(xor(start, b.length), lt(b.length, start)))
            let n := mul(gt(end, start), sub(end, start))
            calldatacopy(mload(0x40), add(b.offset, start), n)
            result := mload(staticcall(gas(), 2, mload(0x40), n, 0x01, 0x20))
            if iszero(returndatasize()) { invalid() }
        }
    }

    /// @dev Returns the sha256 of the slice from `start` to the end of the bytes.
    function sha2Calldata(bytes calldata b, uint256 start) internal view returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            start := xor(start, mul(xor(start, b.length), lt(b.length, start)))
            let n := mul(gt(b.length, start), sub(b.length, start))
            calldatacopy(mload(0x40), add(b.offset, start), n)
            result := mload(staticcall(gas(), 2, mload(0x40), n, 0x01, 0x20))
            if iszero(returndatasize()) { invalid() }
        }
    }

    /// @dev Returns the sha256 of the bytes.
    function sha2Calldata(bytes calldata b) internal view returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            calldatacopy(mload(0x40), b.offset, b.length)
            result := mload(staticcall(gas(), 2, mload(0x40), b.length, 0x01, 0x20))
            if iszero(returndatasize()) { invalid() }
        }
    }
}



// ============================================================
// FILE: node_modules/solady/src/utils/LibBit.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Library for bit twiddling and boolean operations.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibBit.sol)
/// @author Inspired by (https://graphics.stanford.edu/~seander/bithacks.html)
library LibBit {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  BIT TWIDDLING OPERATIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Find last set.
    /// Returns the index of the most significant bit of `x`,
    /// counting from the least significant bit position.
    /// If `x` is zero, returns 256.
    function fls(uint256 x) internal pure returns (uint256 r) {
        /// @solidity memory-safe-assembly
        assembly {
            r := or(shl(8, iszero(x)), shl(7, lt(0xffffffffffffffffffffffffffffffff, x)))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            // forgefmt: disable-next-item
            r := or(r, byte(and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
                0x0706060506020504060203020504030106050205030304010505030400000000))
        }
    }

    /// @dev Count leading zeros.
    /// Returns the number of zeros preceding the most significant one bit.
    /// If `x` is zero, returns 256.
    function clz(uint256 x) internal pure returns (uint256 r) {
        /// @solidity memory-safe-assembly
        assembly {
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            // forgefmt: disable-next-item
            r := add(xor(r, byte(and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
                0xf8f9f9faf9fdfafbf9fdfcfdfafbfcfef9fafdfafcfcfbfefafafcfbffffffff)), iszero(x))
        }
    }

    /// @dev Find first set.
    /// Returns the index of the least significant bit of `x`,
    /// counting from the least significant bit position.
    /// If `x` is zero, returns 256.
    /// Equivalent to `ctz` (count trailing zeros), which gives
    /// the number of zeros following the least significant one bit.
    function ffs(uint256 x) internal pure returns (uint256 r) {
        /// @solidity memory-safe-assembly
        assembly {
            // Isolate the least significant bit.
            x := and(x, add(not(x), 1))
            // For the upper 3 bits of the result, use a De Bruijn-like lookup.
            // Credit to adhusson: https://blog.adhusson.com/cheap-find-first-set-evm/
            // forgefmt: disable-next-item
            r := shl(5, shr(252, shl(shl(2, shr(250, mul(x,
                0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))),
                0x8040405543005266443200005020610674053026020000107506200176117077)))
            // For the lower 5 bits of the result, use a De Bruijn lookup.
            // forgefmt: disable-next-item
            r := or(r, byte(and(div(0xd76453e0, shr(r, x)), 0x1f),
                0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
        }
    }

    /// @dev Returns the number of set bits in `x`.
    function popCount(uint256 x) internal pure returns (uint256 c) {
        /// @solidity memory-safe-assembly
        assembly {
            let max := not(0)
            let isMax := eq(x, max)
            x := sub(x, and(shr(1, x), div(max, 3)))
            x := add(and(x, div(max, 5)), and(shr(2, x), div(max, 5)))
            x := and(add(x, shr(4, x)), div(max, 17))
            c := or(shl(8, isMax), shr(248, mul(x, div(max, 255))))
        }
    }

    /// @dev Returns the number of zero bytes in `x`.
    /// To get the number of non-zero bytes, simply do `32 - countZeroBytes(x)`.
    function countZeroBytes(uint256 x) internal pure returns (uint256 c) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := 0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f
            c := byte(0, mul(shr(7, not(m)), shr(7, not(or(or(add(and(x, m), m), x), m)))))
        }
    }

    /// @dev Returns the number of zero bytes in `s`.
    /// To get the number of non-zero bytes, simply do `s.length - countZeroBytes(s)`.
    function countZeroBytes(bytes memory s) internal pure returns (uint256 c) {
        /// @solidity memory-safe-assembly
        assembly {
            function czb(x_) -> _c {
                let _m := 0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f
                _c := shr(7, not(or(or(add(and(x_, _m), _m), x_), _m)))
                _c := byte(0, mul(shr(7, not(_m)), _c))
            }
            let n := mload(s)
            let l := shl(5, shr(5, n))
            s := add(s, 0x20)
            for { let i } xor(i, l) { i := add(i, 0x20) } { c := add(czb(mload(add(s, i))), c) }
            if lt(l, n) {
                c := add(czb(or(shr(shl(3, sub(n, l)), not(0)), mload(add(s, l)))), c)
            }
        }
    }

    /// @dev Returns the number of zero bytes in `s`.
    /// To get the number of non-zero bytes, simply do `s.length - countZeroBytes(s)`.
    function countZeroBytesCalldata(bytes calldata s) internal pure returns (uint256 c) {
        /// @solidity memory-safe-assembly
        assembly {
            function czb(x_) -> _c {
                let _m := 0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f
                _c := shr(7, not(or(or(add(and(x_, _m), _m), x_), _m)))
                _c := byte(0, mul(shr(7, not(_m)), _c))
            }
            let l := shl(5, shr(5, s.length))
            for { let i } xor(i, l) { i := add(i, 0x20) } {
                c := add(czb(calldataload(add(s.offset, i))), c)
            }
            if lt(l, s.length) {
                let m := shr(shl(3, sub(s.length, l)), not(0))
                c := add(czb(or(m, calldataload(add(s.offset, l)))), c)
            }
        }
    }

    /// @dev Returns whether `x` is a power of 2.
    function isPo2(uint256 x) internal pure returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to `x && !(x & (x - 1))`.
            result := iszero(add(and(x, sub(x, 1)), iszero(x)))
        }
    }

    /// @dev Returns `x` reversed at the bit level.
    function reverseBits(uint256 x) internal pure returns (uint256 r) {
        uint256 m0 = 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
        uint256 m1 = m0 ^ (m0 << 2);
        uint256 m2 = m1 ^ (m1 << 1);
        r = reverseBytes(x);
        r = (m2 & (r >> 1)) | ((m2 & r) << 1);
        r = (m1 & (r >> 2)) | ((m1 & r) << 2);
        r = (m0 & (r >> 4)) | ((m0 & r) << 4);
    }

    /// @dev Returns `x` reversed at the byte level.
    function reverseBytes(uint256 x) internal pure returns (uint256 r) {
        unchecked {
            // Computing masks on-the-fly reduces bytecode size by about 200 bytes.
            uint256 m0 = 0x100000000000000000000000000000001 * (~toUint(x == uint256(0)) >> 192);
            uint256 m1 = m0 ^ (m0 << 32);
            uint256 m2 = m1 ^ (m1 << 16);
            uint256 m3 = m2 ^ (m2 << 8);
            r = (m3 & (x >> 8)) | ((m3 & x) << 8);
            r = (m2 & (r >> 16)) | ((m2 & r) << 16);
            r = (m1 & (r >> 32)) | ((m1 & r) << 32);
            r = (m0 & (r >> 64)) | ((m0 & r) << 64);
            r = (r >> 128) | (r << 128);
        }
    }

    /// @dev Returns the common prefix of `x` and `y` at the bit level.
    function commonBitPrefix(uint256 x, uint256 y) internal pure returns (uint256) {
        unchecked {
            uint256 s = 256 - clz(x ^ y);
            return (x >> s) << s;
        }
    }

    /// @dev Returns the common prefix of `x` and `y` at the nibble level.
    function commonNibblePrefix(uint256 x, uint256 y) internal pure returns (uint256) {
        unchecked {
            uint256 s = (64 - (clz(x ^ y) >> 2)) << 2;
            return (x >> s) << s;
        }
    }

    /// @dev Returns the common prefix of `x` and `y` at the byte level.
    function commonBytePrefix(uint256 x, uint256 y) internal pure returns (uint256) {
        unchecked {
            uint256 s = (32 - (clz(x ^ y) >> 3)) << 3;
            return (x >> s) << s;
        }
    }

    /// @dev hex"ABCD" -> hex"0A0B0C0D".
    function toNibbles(bytes memory s) internal pure returns (bytes memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let n := mload(s)
            mstore(result, add(n, n)) // Store the new length.
            s := add(s, 0x20)
            let o := add(result, 0x20)
            // forgefmt: disable-next-item
            for { let i := 0 } lt(i, n) { i := add(i, 0x10) } {
                let x := shr(128, mload(add(s, i)))
                x := and(0x0000000000000000ffffffffffffffff0000000000000000ffffffffffffffff, or(shl(64, x), x))
                x := and(0x00000000ffffffff00000000ffffffff00000000ffffffff00000000ffffffff, or(shl(32, x), x))
                x := and(0x0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff, or(shl(16, x), x))
                x := and(0x00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff, or(shl(8, x), x))
                mstore(add(o, add(i, i)),
                    and(0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f, or(shl(4, x), x)))
            }
            mstore(add(o, mload(result)), 0) // Zeroize slot after result.
            mstore(0x40, add(0x40, add(o, mload(result)))) // Allocate memory.
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     BOOLEAN OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // A Solidity bool on the stack or memory is represented as a 256-bit word.
    // Non-zero values are true, zero is false.
    // A clean bool is either 0 (false) or 1 (true) under the hood.
    // Usually, if not always, the bool result of a regular Solidity expression,
    // or the argument of a public/external function will be a clean bool.
    // You can usually use the raw variants for more performance.
    // If uncertain, test (best with exact compiler settings).
    // Or use the non-raw variants (compiler can sometimes optimize out the double `iszero`s).

    /// @dev Returns `x & y`. Inputs must be clean.
    function rawAnd(bool x, bool y) internal pure returns (bool z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := and(x, y)
        }
    }

    /// @dev Returns `x & y`.
    function and(bool x, bool y) internal pure returns (bool z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := and(iszero(iszero(x)), iszero(iszero(y)))
        }
    }

    /// @dev Returns `w & x & y`.
    function and(bool w, bool x, bool y) internal pure returns (bool z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := iszero(or(iszero(w), or(iszero(x), iszero(y))))
        }
    }

    /// @dev Returns `v & w & x & y`.
    function and(bool v, bool w, bool x, bool y) internal pure returns (bool z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := iszero(or(or(iszero(v), iszero(w)), or(iszero(x), iszero(y))))
        }
    }

    /// @dev Returns `x | y`. Inputs must be clean.
    function rawOr(bool x, bool y) internal pure returns (bool z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := or(x, y)
        }
    }

    /// @dev Returns `x | y`.
    function or(bool x, bool y) internal pure returns (bool z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := iszero(iszero(or(x, y)))
        }
    }

    /// @dev Returns `w | x | y`.
    function or(bool w, bool x, bool y) internal pure returns (bool z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := iszero(iszero(or(w, or(x, y))))
        }
    }

    /// @dev Returns `v | w | x | y`.
    function or(bool v, bool w, bool x, bool y) internal pure returns (bool z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := iszero(iszero(or(v, or(w, or(x, y)))))
        }
    }

    /// @dev Returns 1 if `b` is true, else 0. Input must be clean.
    function rawToUint(bool b) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := b
        }
    }

    /// @dev Returns 1 if `b` is true, else 0.
    function toUint(bool b) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := iszero(iszero(b))
        }
    }
}



// ============================================================
// FILE: node_modules/solady/src/accounts/LibEIP7702.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Library for EIP7702 operations.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/accounts/LibEIP7702.sol)
library LibEIP7702 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Failed to deploy the EIP7702Proxy.
    error DeploymentFailed();

    /// @dev The proxy query has failed.
    error ProxyQueryFailed();

    /// @dev Failed to change the proxy admin.
    error ChangeProxyAdminFailed();

    /// @dev Failed to upgrade the proxy.
    error UpgradeProxyFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ERC-1967 storage slot for the implementation in the proxy.
    /// `uint256(keccak256("eip1967.proxy.implementation")) - 1`.
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev The transient storage slot for requesting the proxy to initialize the implementation.
    /// `uint256(keccak256("eip7702.proxy.delegation.initialization.request")) - 1`.
    /// While we would love to use a smaller constant, this slot is used in both the proxy
    /// and the delegation, so we shall just use bytes32 in case we want to standardize this.
    bytes32 internal constant EIP7702_PROXY_DELEGATION_INITIALIZATION_REQUEST_SLOT =
        0x94e11c6e41e7fb92cb8bb65e13fdfbd4eba8b831292a1a220f7915c78c7c078f;

    /// @dev The creation code for the EIP7702Proxy.
    /// This is generated from `EIP7702Proxy.sol` with exact compilation settings.
    bytes internal constant EIP7702_PROXY_CREATION_CODE =
        hex"60c06040819052306080526102d63881900390819083398101604081905261002691610096565b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc8290557fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103819055811515110260a0526100c7565b80516001600160a01b0381168114610091575f5ffd5b919050565b5f5f604083850312156100a7575f5ffd5b6100b08361007b565b91506100be6020840161007b565b90509250929050565b60805160a0516101f06100e65f395f602701525f600601526101f05ff3fe60016040527f00000000000000000000000000000000000000000000000000000000000000007f00000000000000000000000000000000000000000000000000000000000000007f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc361960601c30841861010a576001361161008657815481165f5260205ff35b5f3560e01c80635c60da1b036100a157825482165f5260205ff35b7fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61038163f851a440036100d65780545f5260205ff35b80543303610106578382630900f01014028183638f2839701402178015610104576004358416815560206040f35b505b5f5ffd5b815481163660010361013b5780610133575082806101335760205f5f5f885afa15610106573d5ff35b805f5260205ff35b365f5f37806101a7575082806101a7576020365f5f885afa5f5f365f36515af416610168573d5f5f3e3d5ffd5b7f94e11c6e41e7fb92cb8bb65e13fdfbd4eba8b831292a1a220f7915c78c7c078f805c1561019e57365184548419161784555f815d5b503d5f5f3e3d5ff35b5f5f365f845af461019e573d5f5f3e3d5ffdfea2646970667358221220e8b1a2a38594baf32c154aa7dd7743c9cd741d4f386b5ab588a5dcd613c3a00e64736f6c634300081c0033";

    /// @dev The keccak256 of runtime code for `EIP7702Proxy.sol` with exact compilation settings,
    /// with immutables zeroized and without the CBOR metadata.
    bytes32 internal constant EIP7702_PROXY_MINIMAL_CODE_HASH =
        0xf8710866f390ac7c12640457f9cb9663657ac8168b7d4ce6418a982932b3043e;

    /// @dev The length of the runtime code for `EIP7702Proxy.sol` with exact compilation settings,
    /// with immutables zeroized and without the CBOR metadata.
    uint256 internal constant EIP7702_PROXY_MINIMAL_CODE_LENGTH = 0x1ba;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               AUTHORITY AND PROXY OPERATIONS               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the delegation of the account.
    /// If the account is not an EIP7702 authority, returns `address(0)`.
    function delegationOf(address account) internal view returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            extcodecopy(account, 0x00, 0x00, 0x20)
            // Note: Checking that it starts with hex"ef01" is the most general and futureproof.
            // 7702 bytecode is `abi.encodePacked(hex"ef01", uint8(version), address(delegation))`.
            result := mul(shr(96, mload(0x03)), eq(0xef01, shr(240, mload(0x00))))
        }
    }

    /// @dev Returns the delegation and the implementation of the account.
    /// If the account delegation is not a valid EIP7702Proxy, returns `address(0)`.
    function delegationAndImplementationOf(address account)
        internal
        view
        returns (address delegation, address implementation)
    {
        delegation = delegationOf(account);
        if (isEIP7702Proxy(delegation)) {
            /// @solidity memory-safe-assembly
            assembly {
                mstore(0x00, 0)
                if iszero(staticcall(gas(), account, 0x00, 0x01, 0x00, 0x20)) {
                    revert(0x00, 0x00)
                }
                implementation := mload(0x00)
            }
        }
    }

    /// @dev Returns the implementation of `target`.
    /// If `target` is neither an EIP7702Proxy nor an EOA delegated to an EIP7702Proxy, returns `address(0)`.
    function implementationOf(address target) internal view returns (address result) {
        if (!isEIP7702Proxy(target)) if (!isEIP7702Proxy(delegationOf(target))) return address(0);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0)
            if iszero(staticcall(gas(), target, 0x00, 0x01, 0x00, 0x20)) {
                revert(0x00, 0x00)
            }
            result := mload(0x00)
        }
    }

    /// @dev Returns if `target` is an valid EIP7702Proxy based on a bytecode hash check.
    function isEIP7702Proxy(address target) internal view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            // Copy the runtime bytecode without the CBOR metadata.
            extcodecopy(target, m, 0x00, EIP7702_PROXY_MINIMAL_CODE_LENGTH)
            // Zeroize the immutables.
            mstore(add(m, 0x06), 0) // The first `7f<immutable_word>`.
            mstore(add(m, 0x27), 0) // The second `7f<immutable_word>`.
            let h := keccak256(m, EIP7702_PROXY_MINIMAL_CODE_LENGTH)
            result := eq(EIP7702_PROXY_MINIMAL_CODE_HASH, h)
        }
    }

    /// @dev Returns the initialization code for the EIP7702Proxy.
    function proxyInitCode(address initialImplementation, address initialAdmin)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            EIP7702_PROXY_CREATION_CODE,
            uint256(uint160(initialImplementation)),
            uint256(uint160(initialAdmin))
        );
    }

    /// @dev Deploys an EIP7702Proxy.
    function deployProxy(address initialImplementation, address initialAdmin)
        internal
        returns (address instance)
    {
        bytes memory initCode = proxyInitCode(initialImplementation, initialAdmin);
        /// @solidity memory-safe-assembly
        assembly {
            instance := create(0, add(initCode, 0x20), mload(initCode))
            if iszero(instance) {
                mstore(0x00, 0x30116425) // `DeploymentFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Deploys an EIP7702Proxy to a deterministic address with `salt`.
    function deployProxyDeterministic(
        address initialImplementation,
        address initialAdmin,
        bytes32 salt
    ) internal returns (address instance) {
        bytes memory initCode = proxyInitCode(initialImplementation, initialAdmin);
        /// @solidity memory-safe-assembly
        assembly {
            instance := create2(0, add(initCode, 0x20), mload(initCode), salt)
            if iszero(instance) {
                mstore(0x00, 0x30116425) // `DeploymentFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Returns the admin of the proxy.
    /// Assumes that the proxy is a proper EIP7702Proxy, if it exists.
    function proxyAdmin(address proxy) internal view returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0xf851a440) // `admin()`.
            let t := staticcall(gas(), proxy, 0x1c, 0x04, 0x00, 0x20)
            if iszero(and(gt(returndatasize(), 0x1f), t)) {
                mstore(0x00, 0x26ec9b6a) // `ProxyQueryFailed()`.
                revert(0x1c, 0x04)
            }
            result := mload(0x00)
        }
    }

    /// @dev Changes the admin on the proxy. The caller must be the admin.
    /// Assumes that the proxy is a proper EIP7702Proxy, if it exists.
    function changeProxyAdmin(address proxy, address newAdmin) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x8f283970) // `changeAdmin(address)`.
            mstore(0x20, newAdmin) // The implementation will clean the upper 96 bits.
            if iszero(and(eq(mload(0x00), 1), call(gas(), proxy, 0, 0x1c, 0x24, 0x00, 0x20))) {
                mstore(0x00, 0xc502e37e) // `ChangeProxyAdminFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Changes the implementation on the proxy. The caller must be the admin.
    /// Assumes that the proxy is a proper EIP7702Proxy, if it exists.
    function upgradeProxy(address proxy, address newImplementation) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x0900f010) // `upgrade(address)`.
            mstore(0x20, newImplementation) // The implementation will clean the upper 96 bits.
            if iszero(and(eq(mload(0x00), 1), call(gas(), proxy, 0, 0x1c, 0x24, 0x00, 0x20))) {
                mstore(0x00, 0xc6edd882) // `UpgradeProxyFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      UUPS OPERATIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Upgrades the implementation.
    /// The new implementation will NOT be active until the next UserOp or transaction.
    /// To "auto-upgrade" to the latest implementation on the proxy, pass in `address(0)` to reset
    /// the implementation slot. This causes the proxy to use the latest default implementation,
    /// which may be optionally reinitialized via `requestProxyDelegationInitialization()`.
    /// This function is intended to be used on the authority of an EIP7702Proxy delegation.
    /// The most intended usage pattern is to wrap this in an access-gated admin function.
    function upgradeProxyDelegation(address newImplementation) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let s := ERC1967_IMPLEMENTATION_SLOT
            // Preserve the upper 96 bits when updating in case they are used for some stuff.
            mstore(0x00, sload(s))
            mstore(0x0c, shl(96, newImplementation))
            sstore(s, mload(0x00))
        }
    }

    /// @dev Requests the implementation to be initialized to the latest implementation on the proxy.
    /// This function is intended to be used on the authority of an EIP7702Proxy delegation.
    /// The most intended usage pattern is to place it at the end of an `execute` function.
    function requestProxyDelegationInitialization() internal {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(shl(96, sload(ERC1967_IMPLEMENTATION_SLOT))) {
                // Use a dedicated transient storage slot for better Swiss-cheese-model safety.
                tstore(EIP7702_PROXY_DELEGATION_INITIALIZATION_REQUEST_SLOT, address())
            }
        }
    }
}



// ============================================================
// FILE: contracts/interfaces/nexus/base/IBaseAccountEventsAndErrors.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

/// @title Execution Manager Events and Errors Interface
/// @notice Interface for defining events and errors related to transaction execution processes within smart accounts.
/// @dev This interface defines events and errors used by execution manager to handle and report the operational status
/// of
/// smart account transactions.
/// It is a part of the Nexus suite of contracts aimed at implementing flexible and secure smart account operations.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IBaseAccountEventsAndErrors {
    /// @dev Throws an error when a caller is not authorized to access an account.
    error AccountAccessUnauthorized();
}



// ============================================================
// FILE: contracts/interfaces/nexus/base/IStorage.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { SentinelListLib } from "sentinellist/SentinelList.sol";
import { IHook, IPreValidationHookERC1271, IPreValidationHookERC4337 } from "erc7579/interfaces/IERC7579Module.sol";
import { CallType } from "../../../lib/erc-7579/ModeLib.sol";

/// @title Nexus - IStorage Interface
/// @notice Provides structured storage for Modular Smart Account under the Nexus suite, compliant with ERC-7579 and
/// ERC-4337.
/// @dev Manages structured storage using SentinelListLib for validators and executors, and a mapping for fallback
/// handlers.
/// This interface utilizes ERC-7201 storage location practices to ensure isolated and collision-resistant storage
/// spaces
/// within smart contracts.
/// It is designed to support dynamic execution and modular management strategies essential for advanced smart account
/// architectures.
/// @custom:storage-location erc7201:biconomy.storage.Nexus
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IStorage {
    /// @notice Struct storing validators and executors using Sentinel lists, and fallback handlers via mapping.
    struct AccountStorage {
        ///< List of validators, initialized upon contract deployment.
        SentinelListLib.SentinelList validators;
        ///< List of executors, similarly initialized.
        SentinelListLib.SentinelList executors;
        ///< Mapping of selectors to their respective fallback handlers.
        mapping(bytes4 => FallbackHandler) fallbacks;
        ///< Current hook module associated with this account.
        IHook hook;
        ///< Mapping of hooks to requested timelocks.
        mapping(address hook => uint256) emergencyUninstallTimelock;
        ///< PreValidation hook for validateUserOp
        IPreValidationHookERC4337 preValidationHookERC4337;
        ///< PreValidation hook for isValidSignature
        IPreValidationHookERC1271 preValidationHookERC1271;
        ///< Mapping of used nonces for replay protection.
        mapping(uint256 => bool) nonces;
        ///< ERC-7484 registry
        address registry; // keeping this to avoid collisions b/w versions
        ///< Mapping of used 7702 init hashes for replay protection.
        mapping(bytes32 => bool) erc7702InitHashes;
    }

    /// @notice Defines a fallback handler with an associated handler address and a call type.
    struct FallbackHandler {
        ///< The address of the fallback function handler.
        address handler;
        ///< The type of call this handler supports (e.g., static or call).
        CallType calltype;
    }
}



// ============================================================
// FILE: contracts/interfaces/nexus/base/IModuleManagerEventsAndErrors.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { CallType } from "../../../lib/erc-7579/ModeLib.sol";

/// @title ERC-7579 Module Manager Events and Errors Interface
/// @notice Provides event and error definitions for actions related to module management in smart accounts.
/// @dev Used by IModuleManager to define the events and errors associated with the installation and management of
/// modules.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IModuleManagerEventsAndErrors {
    /// @notice Emitted when a module is installed onto a smart account.
    /// @param moduleTypeId The identifier for the type of module installed.
    /// @param module The address of the installed module.
    event ModuleInstalled(uint256 moduleTypeId, address module);

    /// @notice Emitted when a module is uninstalled from a smart account.
    /// @param moduleTypeId The identifier for the type of module uninstalled.
    /// @param module The address of the uninstalled module.
    event ModuleUninstalled(uint256 moduleTypeId, address module);

    /// @dev Thrown when the specified module address is not recognized as valid.
    error InvalidModule(address module);

    /// @dev Thrown when an invalid module type identifier is provided.
    error InvalidModuleTypeId(uint256 moduleTypeId);

    /// @dev Thrown when there is an attempt to install a module that is already installed.
    error ModuleAlreadyInstalled(uint256 moduleTypeId, address module);

    /// @dev Thrown when an operation is performed by an unauthorized operator.
    error UnauthorizedOperation(address operator);

    /// @dev Thrown when there is an attempt to uninstall a module that is not installed.
    error ModuleNotInstalled(uint256 moduleTypeId, address module);

    /// @dev Thrown when a module address is set to zero.
    error ModuleAddressCanNotBeZero();

    /// @dev Thrown when a post-check fails after hook execution.
    error HookPostCheckFailed();

    /// @dev Thrown when there is an attempt to install a hook while another is already installed.
    error HookAlreadyInstalled(address currentHook);

    /// @dev Thrown when there is an attempt to install a PreValidationHook while another is already installed.
    error PrevalidationHookAlreadyInstalled(address currentPreValidationHook);

    /// @dev Thrown when there is an attempt to install a fallback handler for a selector already having one.
    error FallbackAlreadyInstalledForSelector(bytes4 selector);

    /// @dev Thrown when there is an attempt to uninstall a fallback handler for a selector that does not have one
    /// installed.
    error FallbackNotInstalledForSelector(bytes4 selector);

    /// @dev Thrown when Invalid data is provided for MultiType install flow
    error InvalidInput();

    /// @dev Thrown when unable to validate Emergency Uninstall signature
    error EmergencyUninstallSigError();

    /// @notice Error thrown when an invalid nonce is used
    error InvalidNonce();

    /// Error thrown when account installs/uninstalls module with mismatched moduleTypeId
    error MismatchModuleTypeId();

    /// @dev Thrown when there is an attempt to install a forbidden selector as a fallback handler.
    error FallbackSelectorForbidden();

    /// @dev Thrown when there is an attempt to install a fallback handler with an invalid calltype for a given
    /// selector.
    error FallbackCallTypeInvalid();

    /// @notice Error thrown when an execution with an unsupported CallType was made.
    /// @param callType The unsupported call type.
    error UnsupportedCallType(CallType callType);

    /// @notice Error thrown when the default validator is already installed.
    error DefaultValidatorAlreadyInstalled();
}



// ============================================================
// FILE: node_modules/@erc7579/implementation/src/lib/ModeLib.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title ModeLib
 * To allow smart accounts to be very simple, but allow for more complex execution, A custom mode
 * encoding is used.
 *    Function Signature of execute function:
 *           function execute(ModeCode mode, bytes calldata executionCalldata) external payable;
 * This allows for a single bytes32 to be used to encode the execution mode, calltype, execType and
 * context.
 * NOTE: Simple Account implementations only have to scope for the most significant byte. Account  that
 * implement
 * more complex execution modes may use the entire bytes32.
 *
 * |--------------------------------------------------------------------|
 * | CALLTYPE  | EXECTYPE  |   UNUSED   | ModeSelector  |  ModePayload  |
 * |--------------------------------------------------------------------|
 * | 1 byte    | 1 byte    |   4 bytes  | 4 bytes       |   22 bytes    |
 * |--------------------------------------------------------------------|
 *
 * CALLTYPE: 1 byte
 * CallType is used to determine how the executeCalldata paramter of the execute function has to be
 * decoded.
 * It can be either single, batch or delegatecall. In the future different calls could be added.
 * CALLTYPE can be used by a validation module to determine how to decode <userOp.callData[36:]>.
 *
 * EXECTYPE: 1 byte
 * ExecType is used to determine how the account should handle the execution.
 * It can indicate if the execution should revert on failure or continue execution.
 * In the future more execution modes may be added.
 * Default Behavior (EXECTYPE = 0x00) is to revert on a single failed execution. If one execution in
 * a batch fails, the entire batch is reverted
 *
 * UNUSED: 4 bytes
 * Unused bytes are reserved for future use.
 *
 * ModeSelector: bytes4
 * The "optional" mode selector can be used by account vendors, to implement custom behavior in
 * their accounts.
 * the way a ModeSelector is to be calculated is bytes4(keccak256("vendorname.featurename"))
 * this is to prevent collisions between different vendors, while allowing innovation and the
 * development of new features without coordination between ERC-7579 implementing accounts
 *
 * ModePayload: 22 bytes
 * Mode payload is used to pass additional data to the smart account execution, this may be
 * interpreted depending on the ModeSelector
 *
 * ExecutionCallData: n bytes
 * single, delegatecall or batch exec abi.encoded as bytes
 */
import { Execution } from "../interfaces/IERC7579Account.sol";

// Custom type for improved developer experience
type ModeCode is bytes32;

type CallType is bytes1;

type ExecType is bytes1;

type ModeSelector is bytes4;

type ModePayload is bytes22;

// Default CallType
CallType constant CALLTYPE_SINGLE = CallType.wrap(0x00);
// Batched CallType
CallType constant CALLTYPE_BATCH = CallType.wrap(0x01);
// @dev Implementing delegatecall is OPTIONAL!
// implement delegatecall with extreme care.
CallType constant CALLTYPE_STATIC = CallType.wrap(0xFE);
CallType constant CALLTYPE_DELEGATECALL = CallType.wrap(0xFF);

// @dev default behavior is to revert on failure
// To allow very simple accounts to use mode encoding, the default behavior is to revert on failure
// Since this is value 0x00, no additional encoding is required for simple accounts
ExecType constant EXECTYPE_DEFAULT = ExecType.wrap(0x00);
// @dev account may elect to change execution behavior. For example "try exec" / "allow fail"
ExecType constant EXECTYPE_TRY = ExecType.wrap(0x01);

ModeSelector constant MODE_DEFAULT = ModeSelector.wrap(bytes4(0x00000000));
// Example declaration of a custom mode selector
ModeSelector constant MODE_OFFSET = ModeSelector.wrap(bytes4(keccak256("default.mode.offset")));

/**
 * @dev ModeLib is a helper library to encode/decode ModeCodes
 */
library ModeLib {
    function decode(ModeCode mode)
        internal
        pure
        returns (
            CallType _calltype,
            ExecType _execType,
            ModeSelector _modeSelector,
            ModePayload _modePayload
        )
    {
        assembly {
            _calltype := mode
            _execType := shl(8, mode)
            _modeSelector := shl(48, mode)
            _modePayload := shl(80, mode)
        }
    }

    function encode(
        CallType callType,
        ExecType execType,
        ModeSelector mode,
        ModePayload payload
    )
        internal
        pure
        returns (ModeCode)
    {
        return ModeCode.wrap(
            bytes32(
                abi.encodePacked(callType, execType, bytes4(0), ModeSelector.unwrap(mode), payload)
            )
        );
    }

    function encodeSimpleBatch() internal pure returns (ModeCode mode) {
        mode = encode(CALLTYPE_BATCH, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00));
    }

    function encodeSimpleSingle() internal pure returns (ModeCode mode) {
        mode = encode(CALLTYPE_SINGLE, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00));
    }

    function getCallType(ModeCode mode) internal pure returns (CallType calltype) {
        assembly {
            calltype := mode
        }
    }
}

using { eqModeSelector as == } for ModeSelector global;
using { eqCallType as == } for CallType global;
using { eqExecType as == } for ExecType global;

function eqCallType(CallType a, CallType b) pure returns (bool) {
    return CallType.unwrap(a) == CallType.unwrap(b);
}

function eqExecType(ExecType a, ExecType b) pure returns (bool) {
    return ExecType.unwrap(a) == ExecType.unwrap(b);
}

function eqModeSelector(ModeSelector a, ModeSelector b) pure returns (bool) {
    return ModeSelector.unwrap(a) == ModeSelector.unwrap(b);
}



// ============================================================
// FILE: contracts/interfaces/nexus/base/IExecutionHelperEventsAndErrors.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

/// @title Execution Manager Events and Errors Interface
/// @notice Interface for defining events and errors related to transaction execution processes within smart accounts.
/// @dev This interface defines events and errors used by execution manager to handle and report the operational status
/// of
/// smart account transactions.
/// It is a part of the Nexus suite of contracts aimed at implementing flexible and secure smart account operations.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady

import { ExecType } from "../../../lib/erc-7579/ModeLib.sol";

interface IExecutionHelperEventsAndErrors {
    /// @notice Event emitted when a transaction fails to execute successfully.
    event TryExecuteUnsuccessful(bytes callData, bytes result);

    /// @notice Event emitted when a transaction fails to execute successfully.
    event TryDelegateCallUnsuccessful(bytes callData, bytes result);

    /// @notice Error thrown when an execution with an unsupported ExecType was made.
    /// @param execType The unsupported execution type.
    error UnsupportedExecType(ExecType execType);
}



// ============================================================
// FILE: contracts/composability/ComposableStorage.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";

/**
 * @title ComposableStorage
 * @dev Contract to handle generic storage operations with cross-chain support
 */
contract ComposableStorage {
    using EfficientHashLib for *;

    error SlotNotInitialized();

    // Mapping to track initialized slots
    mapping(bytes32 => bool) private initializedSlots;

    // Mapping to track length of dynamic data
    mapping(bytes32 => uint256) private dynamicDataLength;

    /**
     * @dev Internal function to write a value to a specific storage slot
     */
    function _writeStorage(bytes32 slot, bytes32 value, bytes32 namespace) private {
        bytes32 namespacedSlot = getNamespacedSlot(namespace, slot);
        initializedSlots[namespacedSlot] = true;
        assembly {
            sstore(namespacedSlot, value)
        }
    }

    /**
     * @dev Write a value to a specific storage slot
     * @param slot The storage slot to write to
     * @param value The value to write
     */
    function writeStorage(bytes32 slot, bytes32 value, address account) external {
        bytes32 namespace = getNamespace(account, msg.sender);
        _writeStorage(slot, value, namespace);
    }

    /**
     * @dev Read a value from a specific namespace and slot
     * @param namespace The namespace (typically a contract address)
     * @param slot The storage slot to read from
     * @return The value stored at the specified namespaced slot
     */
    function readStorage(bytes32 namespace, bytes32 slot) external view returns (bytes32) {
        bytes32 namespacedSlot = getNamespacedSlot(namespace, slot);
        if (!initializedSlots[namespacedSlot]) {
            revert SlotNotInitialized();
        }
        bytes32 value;
        assembly {
            value := sload(namespacedSlot)
        }
        return value;
    }

    /**
     * @dev Generates a namespaced slot
     * @param namespace The namespace (typically a contract address)
     * @param slot The storage slot to read from
     * return The namespaced slot
     */
    function getNamespacedSlot(bytes32 namespace, bytes32 slot) public pure returns (bytes32 result) {
        assembly {
            mstore(0x00, namespace)
            mstore(0x20, slot)
            result := keccak256(0x00, 0x40)
        }
    }

    /**
     * @dev Generates a namespace for a given account and caller
     * @param account The account address
     * @param _caller The caller address
     * return The generated namespace
     */
    function getNamespace(address account, address _caller) public pure returns (bytes32 result) {
        assembly {
            mstore(0x00, account)
            mstore(0x14, _caller)
            result := keccak256(0x0c, 0x28)
        }
    }

    /**
     * @dev Check if a slot has been initialized
     */
    function isSlotInitialized(bytes32 namespace, bytes32 slot) external view returns (bool) {
        bytes32 namespacedSlot = getNamespacedSlot(namespace, slot);
        return initializedSlots[namespacedSlot];
    }
}



// ============================================================
// FILE: node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol
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
