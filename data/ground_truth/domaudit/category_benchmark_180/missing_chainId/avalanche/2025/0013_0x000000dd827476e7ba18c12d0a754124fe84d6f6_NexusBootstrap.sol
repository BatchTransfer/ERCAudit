// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x000000dd827476e7ba18c12d0a754124fe84d6f6
// Contract Name: NexusBootstrap



// ============================================================
// FILE: contracts/utils/NexusBootstrap.sol
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
// Learn more at https://biconomy.io. For security issues, contact: security@biconomy.io

import { ModuleManager } from "../base/ModuleManager.sol";
import { IModule } from "../interfaces/modules/IModule.sol";
import {
    MODULE_TYPE_VALIDATOR,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK,
    MODULE_TYPE_HOOK
} from "../types/Constants.sol";

/// @title NexusBootstrap Configuration for Nexus
/// @notice Provides configuration and initialization for Nexus smart accounts.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
struct BootstrapConfig {
    address module;
    bytes data;
}

struct BootstrapPreValidationHookConfig {
    uint256 hookType;
    address module;
    bytes data;
}

/// @title NexusBootstrap
/// @notice Manages the installation of modules into Nexus smart accounts using delegatecalls.
contract NexusBootstrap is ModuleManager {

    constructor(address defaultValidator, bytes memory initData) ModuleManager(defaultValidator, initData) {}

    modifier _withInitSentinelLists() {
        _initSentinelLists();
        _;
    }

    /// @notice Initializes the Nexus account with the default validator.
    /// @dev Intended to be called by the Nexus with a delegatecall.
    /// @param data The initialization data for the default validator module.
    function initNexusWithDefaultValidator(
        bytes calldata data
    )
        external
        payable
    {
        IModule(_DEFAULT_VALIDATOR).onInstall(data);
    }

    // ================================================
    // ===== DEFAULT VALIDATOR + OTHER MODULES =====
    // ================================================

    /// @notice Initializes the Nexus account with the default validator and other modules.
    /// @dev Intended to be called by the Nexus with a delegatecall.
    /// @param defaultValidatorInitData The initialization data for the default validator module.
    /// @param validators The configuration array for validator modules. Should not contain the default validator.
    /// @param executors The configuration array for executor modules.
    /// @param hook The configuration for the hook module.
    /// @param fallbacks The configuration array for fallback handler modules.
    /// @param preValidationHooks The configuration array for pre-validation hooks.
    function initNexusWithDefaultValidatorAndOtherModules(
        bytes calldata defaultValidatorInitData,
        BootstrapConfig[] calldata validators,
        BootstrapConfig[] calldata executors,
        BootstrapConfig calldata hook,
        BootstrapConfig[] calldata fallbacks,
        BootstrapPreValidationHookConfig[] calldata preValidationHooks
    )
        public
        payable
        _withInitSentinelLists
    {
        IModule(_DEFAULT_VALIDATOR).onInstall(defaultValidatorInitData);

        for (uint256 i; i < validators.length; i++) {
            if (validators[i].module == address(0)) continue;
            _installValidator(validators[i].module, validators[i].data);
            emit ModuleInstalled(MODULE_TYPE_VALIDATOR, validators[i].module);
        }

        for (uint256 i; i < executors.length; i++) {
            if (executors[i].module == address(0)) continue;
            _installExecutor(executors[i].module, executors[i].data);
            emit ModuleInstalled(MODULE_TYPE_EXECUTOR, executors[i].module);
        }

        // Initialize hook
        if (hook.module != address(0)) {
            _installHook(hook.module, hook.data);
            emit ModuleInstalled(MODULE_TYPE_HOOK, hook.module);
        }

        // Initialize fallback handlers
        for (uint256 i; i < fallbacks.length; i++) {
            if (fallbacks[i].module == address(0)) continue;
            _installFallbackHandler(fallbacks[i].module, fallbacks[i].data);
            emit ModuleInstalled(MODULE_TYPE_FALLBACK, fallbacks[i].module);
        } 

        // Initialize pre-validation hooks
        for (uint256 i; i < preValidationHooks.length; i++) {
            if (preValidationHooks[i].module == address(0)) continue;
            _installPreValidationHook(
                preValidationHooks[i].hookType,
                preValidationHooks[i].module,
                preValidationHooks[i].data
            );
            emit ModuleInstalled(preValidationHooks[i].hookType, preValidationHooks[i].module);
        }
    }

    /// @notice expose this function for backwards compatibility
    function initNexusWithDefaultValidatorAndOtherModulesNoRegistry(
        bytes calldata defaultValidatorInitData,
        BootstrapConfig[] calldata validators,
        BootstrapConfig[] calldata executors,
        BootstrapConfig calldata hook,
        BootstrapConfig[] calldata fallbacks,
        BootstrapPreValidationHookConfig[] calldata preValidationHooks
    )
        external
        payable
    {
        initNexusWithDefaultValidatorAndOtherModules(
            defaultValidatorInitData, 
            validators,
            executors, 
            hook, 
            fallbacks, 
            preValidationHooks
        );
    }

    // ================================================
    // ===== SINGLE VALIDATOR =====
    // ================================================

    /// @notice Initializes the Nexus account with a single validator.
    /// @dev Intended to be called by the Nexus with a delegatecall.
    /// @param validator The address of the validator module. Should not be the default validator.
    /// @param data The initialization data for the validator module.
    function initNexusWithSingleValidator(
        address validator,
        bytes calldata data
    )
        public
        payable
        _withInitSentinelLists
    {
        _installValidator(validator, data);
        emit ModuleInstalled(MODULE_TYPE_VALIDATOR, validator);
    }

    /// @notice expose this function for backwards compatibility
    function initNexusWithSingleValidatorNoRegistry(
        address validator,
        bytes calldata data
    )
        external
        payable
    {   
        initNexusWithSingleValidator(validator, data);
    }


    // ================================================
    // ===== GENERALIZED FLOW =====
    // ================================================

    /// @notice Initializes the Nexus account with multiple modules.
    /// @dev Intended to be called by the Nexus with a delegatecall.
    /// @param validators The configuration array for validator modules. Should not contain the default validator.
    /// @param executors The configuration array for executor modules.
    /// @param hook The configuration for the hook module.
    /// @param fallbacks The configuration array for fallback handler modules.
    /// @param preValidationHooks The configuration array for pre-validation hooks.
    function initNexus(
        BootstrapConfig[] calldata validators,
        BootstrapConfig[] calldata executors,
        BootstrapConfig calldata hook,
        BootstrapConfig[] calldata fallbacks,
        BootstrapPreValidationHookConfig[] calldata preValidationHooks
    )
        public
        _withInitSentinelLists
    {
        // Initialize validators
        for (uint256 i = 0; i < validators.length; i++) {
            _installValidator(validators[i].module, validators[i].data);
            emit ModuleInstalled(MODULE_TYPE_VALIDATOR, validators[i].module);
        }

        // Initialize executors
        for (uint256 i = 0; i < executors.length; i++) {
            if (executors[i].module == address(0)) continue;
            _installExecutor(executors[i].module, executors[i].data);
            emit ModuleInstalled(MODULE_TYPE_EXECUTOR, executors[i].module);
        }

        // Initialize fallback handlers
        for (uint256 i = 0; i < fallbacks.length; i++) {
            if (fallbacks[i].module == address(0)) continue;
            _installFallbackHandler(fallbacks[i].module, fallbacks[i].data);
            emit ModuleInstalled(MODULE_TYPE_FALLBACK, fallbacks[i].module);
        }

        // Initialize hook
        if (hook.module != address(0)) {
            _installHook(hook.module, hook.data);
            emit ModuleInstalled(MODULE_TYPE_HOOK, hook.module);
        }

        // Initialize pre-validation hooks
        for (uint256 i = 0; i < preValidationHooks.length; i++) {
            if (preValidationHooks[i].module == address(0)) continue;
            _installPreValidationHook(
                preValidationHooks[i].hookType,
                preValidationHooks[i].module,
                preValidationHooks[i].data
            );
            emit ModuleInstalled(preValidationHooks[i].hookType, preValidationHooks[i].module);
        }
    }

    /// @notice expose this function for backwards compatibility
    function initNexusNoRegistry(
        BootstrapConfig[] calldata validators,
        BootstrapConfig[] calldata executors,
        BootstrapConfig calldata hook,
        BootstrapConfig[] calldata fallbacks,
        BootstrapPreValidationHookConfig[] calldata preValidationHooks
    )
        external
        payable
    {
        initNexus(validators, executors, hook, fallbacks, preValidationHooks);
    }

    // ================================================
    // ===== SCOPED FLOW =====
    // ================================================

    /// @notice Initializes the Nexus account with a scoped set of modules.
    /// @dev Intended to be called by the Nexus with a delegatecall.
    /// @param validators The configuration array for validator modules. Should not contain the default validator.
    /// @param hook The configuration for the hook module.
    function initNexusScoped(
        BootstrapConfig[] calldata validators,
        BootstrapConfig calldata hook
    )
        public
        _withInitSentinelLists
    {
        // Initialize validators
        for (uint256 i = 0; i < validators.length; i++) {
            _installValidator(validators[i].module, validators[i].data);
            emit ModuleInstalled(MODULE_TYPE_VALIDATOR, validators[i].module);
        }

        // Initialize hook
        if (hook.module != address(0)) {
            _installHook(hook.module, hook.data);
            emit ModuleInstalled(MODULE_TYPE_HOOK, hook.module);
        }
    }

    /// @notice expose this function for backwards compatibility
    function initNexusScopedNoRegistry(
        BootstrapConfig[] calldata validators,
        BootstrapConfig calldata hook
    )
        external
        payable
    {
        initNexusScoped(validators, hook);
    }

    /// @dev EIP712 domain name and version.
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "NexusBootstrap";
        version = "1.3.0";
    }

    
    // required implementations. Are not used.
    function installModule(uint256 moduleTypeId, address module, bytes calldata initData) external payable override {
        // do nothing
    }

    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData) external payable override {
        // do nothing
    }

    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext) external view override returns (bool installed) {
        return false;
    }
}



// ============================================================
// FILE: contracts/base/ModuleManager.sol
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
import { IHook } from "../interfaces/modules/IHook.sol";
import { IModule } from "../interfaces/modules/IModule.sol";
import { IPreValidationHookERC1271, IPreValidationHookERC4337 } from "../interfaces/modules/IPreValidationHook.sol";
import { IExecutor } from "../interfaces/modules/IExecutor.sol";
import { IFallback } from "../interfaces/modules/IFallback.sol";
import { IValidator } from "../interfaces/modules/IValidator.sol";
import { CallType, CALLTYPE_SINGLE, CALLTYPE_STATIC } from "../lib/ModeLib.sol";
import { ExecLib } from "../lib/ExecLib.sol";
import { LocalCallDataParserLib } from "../lib/local/LocalCallDataParserLib.sol";
import { IModuleManager } from "../interfaces/base/IModuleManager.sol";
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
    ERC1271_MAGICVALUE
} from "../types/Constants.sol";
import { EIP712 } from "solady/utils/EIP712.sol";
import { ExcessivelySafeCall } from "excessively-safe-call/ExcessivelySafeCall.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { EmergencyUninstall } from "../types/DataTypes.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";

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
    using ECDSA for bytes32;

    /// @dev The default validator address.
    /// @notice To explicitly initialize the default validator, Nexus.execute(_DEFAULT_VALIDATOR.onInstall(...)) should be called.
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
        if (!IValidator(defaultValidator_).isModuleType(MODULE_TYPE_VALIDATOR)) 
            revert MismatchModuleTypeId(); 
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
    function getValidatorsPaginated(address cursor, uint256 size) external view returns (address[] memory array, address next) {
        (array, next) = _paginate(_getAccountStorage().validators, cursor, size);
    }

    /// @dev Retrieves a paginated list of executor addresses from the linked list.
    /// This utility function is not defined by the ERC-7579 standard and is implemented to facilitate
    /// easier management and retrieval of large sets of executor modules.
    /// @param cursor The address to start pagination from, or zero to start from the first entry.
    /// @param size The number of executor addresses to return.
    /// @return array An array of executor addresses.
    /// @return next The address to use as a cursor for the next page of results.
    function getExecutorsPaginated(address cursor, uint256 size) external view returns (address[] memory array, address next) {
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
    function _enableMode(bytes32 userOpHash, bytes calldata packedData) internal returns (bytes calldata userOpSignature) {
        address module;
        uint256 moduleType;
        bytes calldata moduleInitData;
        bytes calldata enableModeSignature;

        (module, moduleType, moduleInitData, enableModeSignature, userOpSignature) = packedData.parseEnableModeData();

        address enableModeSigValidator = _handleValidator(address(bytes20(enableModeSignature[0:20])));
        
        enableModeSignature = enableModeSignature[20:];
        
        if (!_checkEnableModeSignature({
            structHash: _getEnableModeDataHash(module, moduleType, userOpHash, moduleInitData), 
            sig: enableModeSignature,
            validator: enableModeSigValidator
        })) {
            revert EnableModeSigError();
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
        } else if (moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 || moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337) {
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
    function _installValidator(
        address validator,
        bytes calldata data
    )
        internal
        virtual
        withHook
    {
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

        validator.excessivelySafeCall(gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, disableModuleData));
    }

    /// @dev Installs a new executor module after checking if it matches the required module type.
    /// @param executor The address of the executor module to be installed.
    /// @param data Initialization data to configure the executor upon installation.
    function _installExecutor(
        address executor,
        bytes calldata data
    ) 
        internal
        virtual
        withHook
    {
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
        executor.excessivelySafeCall(gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, disableModuleData));
    }

    /// @dev Installs a hook module, ensuring no other hooks are installed before proceeding.
    /// @param hook The address of the hook to be installed.
    /// @param data Initialization data to configure the hook upon installation.
    function _installHook(
        address hook,
        bytes calldata data
    ) 
        internal
        virtual
        withHook
    {
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
        } else if (hookType == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 || hookType == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337) {
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
    function _installFallbackHandler(
        address handler, 
        bytes calldata params
    )
        internal 
        virtual
        withHook
    {
        if (!IFallback(handler).isModuleType(MODULE_TYPE_FALLBACK)) revert MismatchModuleTypeId();
        // Extract the function selector from the provided parameters.
        bytes4 selector = bytes4(params[0:4]);

        // Extract the call type from the provided parameters.
        CallType calltype = CallType.wrap(bytes1(params[4]));

        require(calltype == CALLTYPE_SINGLE || calltype == CALLTYPE_STATIC, FallbackCallTypeInvalid());

        // Extract the initialization data from the provided parameters.
        bytes memory initData = params[5:];

        // Revert if the selector is either `onInstall(bytes)` (0x6d61fe70) or `onUninstall(bytes)` (0x8a91b0e3) or explicit bytes(0).
        // These selectors are explicitly forbidden to prevent security vulnerabilities.
        // Allowing these selectors would enable unauthorized users to uninstall and reinstall critical modules.
        // If a validator module is uninstalled and reinstalled without proper authorization, it can compromise
        // the account's security and integrity. By restricting these selectors, we ensure that the fallback handler
        // cannot be manipulated to disrupt the expected behavior and security of the account.
        require(!(selector == bytes4(0x6d61fe70) || selector == bytes4(0x8a91b0e3) || selector == bytes4(0)), FallbackSelectorForbidden());

        // Revert if a fallback handler is already installed for the given selector.
        // This check ensures that we do not overwrite an existing fallback handler, which could lead to unexpected behavior.
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
        fallbackHandler.excessivelySafeCall(gasleft(), 0, 0, abi.encodeWithSelector(IModule.onUninstall.selector, data[4:]));
    }

    /// @dev Installs a pre-validation hook module, ensuring no other pre-validation hooks are installed before proceeding.
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
            else if (theType == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 || theType == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337) {
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
        bytes32 hash = _getEmergencyUninstallDataHash(data.hook, data.hookType, data.deInitData, data.nonce);
        // Check if nonce is valid
        require(!_getAccountStorage().nonces[data.nonce], InvalidNonce());
        // Mark nonce as used
        _getAccountStorage().nonces[data.nonce] = true;
        // Check if the signature is valid
        require((IValidator(validator).isValidSignatureWithSender(address(this), hash, signature[20:]) == ERC1271_MAGICVALUE), EmergencyUninstallSigError());
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
        if (preValidationHook == address(0)) return (hash, userOp.signature);
        // Otherwise, call the pre-validation hook and return the updated hash and signature
        else return IPreValidationHookERC4337(preValidationHook).preValidationHookERC4337(userOp, missingAccountFunds, hash);
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
    function _withPreValidationHook(bytes32 hash, bytes calldata signature) internal view virtual returns (bytes32 postHash, bytes memory postSig) {
        // Get the pre-validation hook for ERC-1271
        address preValidationHook = _getPreValidationHook(MODULE_TYPE_PREVALIDATION_HOOK_ERC1271);
        // If no pre-validation hook is installed, return the original hash and signature
        if (preValidationHook == address(0)) return (hash, signature);
        // Otherwise, call the pre-validation hook and return the updated hash and signature
        else return IPreValidationHookERC1271(preValidationHook).preValidationHookERC1271(msg.sender, hash, signature);
    }

    /// @notice Checks if an enable mode signature is valid.
    /// @param structHash data hash.
    /// @param sig Signature.
    /// @param validator Validator address.
    function _checkEnableModeSignature(
        bytes32 structHash,
        bytes calldata sig,
        address validator
    ) internal view returns (bool) {
        bytes32 eip712Digest = _hashTypedData(structHash);
        // Use standard IERC-1271/ERC-7739 interface.
        // Even if the validator doesn't support 7739 under the hood, it is still secure,
        // as eip712digest is already built based on 712Domain of this Smart Account
        // This interface should always be exposed by validators as per ERC-7579
        try IValidator(validator).isValidSignatureWithSender(address(this), eip712Digest, sig) returns (bytes4 res) {
                return res == ERC1271_MAGICVALUE;
        } catch {
            return false;
        }
    }

    /// @notice Builds the emergency uninstall data hash as per eip712
    /// @param hookType Type of the hook (4 for Hook, 8 for ERC-1271 Prevalidation Hook, 9 for ERC-4337 Prevalidation Hook)
    /// @param hook address of the hook being uninstalled
    /// @param data De-initialization data to configure the hook upon uninstallation.
    /// @param nonce Unique nonce for the operation
    /// @return structHash data hash
    function _getEmergencyUninstallDataHash(address hook, uint256 hookType, bytes calldata data, uint256 nonce) internal view returns (bytes32) {
        return _hashTypedData(keccak256(abi.encode(EMERGENCY_UNINSTALL_TYPE_HASH, hook, hookType, keccak256(data), nonce)));
    }

    /// @notice Checks if a module is installed on the smart account.
    /// @param moduleTypeId The module type ID.
    /// @param module The module address.
    /// @param additionalContext Additional context for checking installation.
    /// @return True if the module is installed, false otherwise.
    function _isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext) internal view returns (bool) {
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
        } else if (moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 || moduleTypeId == MODULE_TYPE_PREVALIDATION_HOOK_ERC4337) {
            return _getPreValidationHook(moduleTypeId) == module;
        } else {
            return false;
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
    function _handleValidator(address validator) internal view returns (address) {
        if (validator == address(0)) {
            return _DEFAULT_VALIDATOR;
        } else {
            require(_isValidatorInstalled(validator), ValidatorNotInstalled(validator));
            return validator;
        }
    }

    /// @notice Builds the enable mode data hash as per eip712
    /// @param module Module being enabled
    /// @param moduleType Type of the module as per EIP-7579
    /// @param userOpHash Hash of the User Operation
    /// @param initData Module init data.
    /// @return structHash data hash
    function _getEnableModeDataHash(address module, uint256 moduleType, bytes32 userOpHash, bytes calldata initData) internal pure returns (bytes32) {
        return keccak256(abi.encode(MODULE_ENABLE_MODE_TYPE_HASH, module, moduleType, userOpHash, keccak256(initData)));
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
                if iszero(success) {
                    revert(add(result, 0x20), mload(result))
                }
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
        }
        // if there was no handler and it is not the onERCXXXReceived call, revert
        revert MissingFallbackHandler(msg.sig);
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
// FILE: contracts/interfaces/modules/IModule.sol
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

/// @title Nexus - ERC-7579 Module Base Interface
/// @notice Interface for module management in smart accounts, complying with ERC-7579 specifications.
/// @dev Defines the lifecycle hooks and checks for modules within the smart account architecture.
/// This interface includes methods for installing, uninstalling, and verifying module types and initialization status.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IModule {
    /// @notice Installs the module with necessary initialization data.
    /// @dev Reverts if the module is already initialized.
    /// @param data Arbitrary data required for initializing the module during `onInstall`.
    function onInstall(bytes calldata data) external;

    /// @notice Uninstalls the module and allows for cleanup via arbitrary data.
    /// @dev Reverts if any issues occur that prevent clean uninstallation.
    /// @param data Arbitrary data required for deinitializing the module during `onUninstall`.
    function onUninstall(bytes calldata data) external;

    /// @notice Determines if the module matches a specific module type.
    /// @dev Should return true if the module corresponds to the type ID, false otherwise.
    /// @param moduleTypeId Numeric ID of the module type as per ERC-7579 specifications.
    /// @return True if the module is of the specified type, false otherwise.
    function isModuleType(uint256 moduleTypeId) external view returns (bool);

    /// @notice Checks if the module has been initialized for a specific smart account.
    /// @dev Returns true if initialized, false otherwise.
    /// @param smartAccount Address of the smart account to check for initialization status.
    /// @return True if the module is initialized for the given smart account, false otherwise.
    function isInitialized(address smartAccount) external view returns (bool);
}



// ============================================================
// FILE: contracts/types/Constants.sol
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

// Magic value for ERC-1271 valid signature
bytes4 constant ERC1271_MAGICVALUE = 0x1626ba7e;

// Value indicating an invalid ERC-1271 signature
bytes4 constant ERC1271_INVALID = 0xFFFFFFFF;

// Value indicating successful validation
uint256 constant VALIDATION_SUCCESS = 0;

// Value indicating failed validation
uint256 constant VALIDATION_FAILED = 1;

// Module type identifier for Multitype install
uint256 constant MODULE_TYPE_MULTI = 0;

// Module type identifier for validators
uint256 constant MODULE_TYPE_VALIDATOR = 1;

// Module type identifier for executors
uint256 constant MODULE_TYPE_EXECUTOR = 2;

// Module type identifier for fallback handlers
uint256 constant MODULE_TYPE_FALLBACK = 3;

// Module type identifier for hooks
uint256 constant MODULE_TYPE_HOOK = 4;

// Module type identifiers for pre-validation hooks
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 = 8;
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC4337 = 9;


// keccak256("ModuleEnableMode(address module,uint256 moduleType,bytes32 userOpHash,bytes initData)")
bytes32 constant MODULE_ENABLE_MODE_TYPE_HASH = 0xf6c866c1cd985ce61f030431e576c0e82887de0643dfa8a2e6efc3463e638ed0;

// keccak256("EmergencyUninstall(address hook,uint256 hookType,bytes deInitData,uint256 nonce)")
bytes32 constant EMERGENCY_UNINSTALL_TYPE_HASH = 0xd3ddfc12654178cc44d4a7b6b969cfdce7ffe6342326ba37825314cffa0fba9c;

// Validation modes
bytes1 constant MODE_VALIDATION = 0x00;
bytes1 constant MODE_MODULE_ENABLE = 0x01;
bytes1 constant MODE_PREP = 0x02;

bytes4 constant SUPPORTS_ERC7739 = 0x77390000;
bytes4 constant SUPPORTS_ERC7739_V1 = 0x77390001;



// ============================================================
// FILE: node_modules/sentinellist/src/SentinelList.sol
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
// FILE: contracts/base/Storage.sol
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

import { IStorage } from "../interfaces/base/IStorage.sol";

/// @title Nexus - Storage
/// @notice Manages isolated storage spaces for Modular Smart Account in compliance with ERC-7201 standard to ensure collision-resistant storage.
/// @dev Implements the ERC-7201 namespaced storage pattern to maintain secure and isolated storage sections for different states within Nexus suite.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract Storage is IStorage {
    /// @custom:storage-location erc7201:biconomy.storage.Nexus
    /// ERC-7201 namespaced via `keccak256(abi.encode(uint256(keccak256(bytes("biconomy.storage.Nexus"))) - 1)) & ~bytes32(uint256(0xff));`
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
// FILE: contracts/interfaces/modules/IHook.sol
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

import { IModule } from "./IModule.sol";

/// @title Hook Management Interface
/// @notice Provides methods for pre-checks and post-checks of transactions to ensure conditions and state consistency.
/// @dev Defines two critical lifecycle hooks in the transaction process: `preCheck` and `postCheck`.
/// These methods facilitate validating conditions prior to execution and verifying state changes afterwards, respectively.
interface IHook is IModule {
    /// @notice Performs checks before a transaction is executed, potentially modifying the transaction context.
    /// @dev This method is called before the execution of a transaction to validate and possibly adjust execution context.
    /// @param msgSender The original sender of the transaction.
    /// @param msgValue The amount of wei sent with the call.
    /// @param msgData The calldata of the transaction.
    /// @return hookData Data that may be used or modified throughout the transaction lifecycle, passed to `postCheck`.
    function preCheck(address msgSender, uint256 msgValue, bytes calldata msgData) external returns (bytes memory hookData);

    /// @notice Performs checks after a transaction is executed to ensure state consistency and log results.
    /// @dev This method is called after the execution of a transaction to verify and react to the execution outcome.
    /// @param hookData Data returned from `preCheck`, containing execution context or modifications.
    function postCheck(bytes calldata hookData) external;
}



// ============================================================
// FILE: contracts/interfaces/modules/IPreValidationHook.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { IModule } from "./IModule.sol";

/// @title Nexus - IPreValidationHookERC1271 Interface
/// @notice Defines the interface for ERC-1271 pre-validation hooks
interface IPreValidationHookERC1271 is IModule {
    /// @notice Performs pre-validation checks for isValidSignature
    /// @dev This method is called before the validation of a signature on a validator within isValidSignature
    /// @param sender The original sender of the request
    /// @param hash The hash of signed data
    /// @param data The signature data to validate
    /// @return hookHash The hash after applying the pre-validation hook
    /// @return hookSignature The signature after applying the pre-validation hook
    function preValidationHookERC1271(address sender, bytes32 hash, bytes calldata data) external view returns (bytes32 hookHash, bytes memory hookSignature);
}

/// @title Nexus - IPreValidationHookERC4337 Interface
/// @notice Defines the interface for ERC-4337 pre-validation hooks
interface IPreValidationHookERC4337 is IModule {
    /// @notice Performs pre-validation checks for user operations
    /// @dev This method is called before the validation of a user operation
    /// @param userOp The user operation to be validated
    /// @param missingAccountFunds The amount of funds missing in the account
    /// @param userOpHash The hash of the user operation data
    /// @return hookHash The hash after applying the pre-validation hook
    /// @return hookSignature The signature after applying the pre-validation hook
    function preValidationHookERC4337(
        PackedUserOperation calldata userOp,
        uint256 missingAccountFunds,
        bytes32 userOpHash
    )
        external
        returns (bytes32 hookHash, bytes memory hookSignature);
}



// ============================================================
// FILE: contracts/interfaces/modules/IExecutor.sol
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

import { IModule } from "./IModule.sol";

/// @title Nexus - IExecutor Interface
/// @notice Defines the interface for Executor modules within the Nexus Smart Account framework, compliant with the ERC-7579 standard.
/// @dev Extends IModule to include functionalities specific to execution modules.
/// This interface is future-proof, allowing for expansion and integration of advanced features in subsequent versions.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IExecutor is IModule {
    // Future methods for execution management will be defined here to accommodate evolving requirements.
}



// ============================================================
// FILE: contracts/interfaces/modules/IFallback.sol
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

import { IModule } from "./IModule.sol";

/// @title Nexus - IFallback Interface
/// @notice Defines the interface for Fallback modules within the Nexus Smart Account framework, compliant with the ERC-7579 standard.
/// @dev Extends IModule to include functionalities specific to fallback modules.
/// This interface is future-proof, allowing for expansion and integration of advanced features in subsequent versions.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IFallback is IModule {
    // Future methods for fallback management will be defined here to accommodate evolving blockchain technologies.
}



// ============================================================
// FILE: contracts/interfaces/modules/IValidator.sol
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

import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";

import { IModule } from "./IModule.sol";

/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
interface IValidator is IModule {
    /// @notice Validates a user operation as per ERC-4337 standard requirements.
    /// @dev Should ensure that the signature and nonce are verified correctly before the transaction is allowed to proceed.
    /// The function returns a status code indicating validation success or failure.
    /// @param userOp The user operation containing transaction details to be validated.
    /// @param userOpHash The hash of the user operation data, used for verifying the signature.
    /// @return status The result of the validation process, typically indicating success or the type of failure.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) external returns (uint256);

    /// @notice Verifies a signature against a hash, using the sender's address as a contextual check.
    /// @dev Used to confirm the validity of a signature against the specific conditions set by the sender.
    /// @param sender The address from which the operation was initiated, adding an additional layer of validation against the signature.
    /// @param hash The hash of the data signed.
    /// @param data The signature data to validate.
    /// @return magicValue A bytes4 value that corresponds to the ERC-1271 standard, indicating the validity of the signature.
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata data) external view returns (bytes4);
}



// ============================================================
// FILE: contracts/lib/ModeLib.sol
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
    function decode(
        ExecutionMode mode
    ) internal pure returns (CallType _calltype, ExecType _execType, ModeSelector _modeSelector, ModePayload _modePayload) {
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

    function encode(CallType callType, ExecType execType, ModeSelector mode, ModePayload payload) internal pure returns (ExecutionMode) {
        return ExecutionMode.wrap(bytes32(abi.encodePacked(callType, execType, bytes4(0), ModeSelector.unwrap(mode), payload)));
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
// FILE: contracts/lib/ExecLib.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Execution } from "../types/DataTypes.sol";

/// @title ExecutionLib
/// @author zeroknots.eth | rhinestone.wtf
/// Helper Library for decoding Execution calldata
/// malloc for memory allocation is bad for gas. use this assembly instead
library ExecLib {
    error InvalidBatchCallData();

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

    function decodeSingle(bytes calldata executionCalldata) internal pure returns (address target, uint256 value, bytes calldata callData) {
        target = address(bytes20(executionCalldata[0:20]));
        value = uint256(bytes32(executionCalldata[20:52]));
        callData = executionCalldata[52:];
    }

    function decodeDelegateCall(bytes calldata executionCalldata) internal pure returns (address delegate, bytes calldata callData) {
        // destructure executionCallData according to single exec
        delegate = address(uint160(bytes20(executionCalldata[0:20])));
        callData = executionCalldata[20:];
    }

    function encodeSingle(address target, uint256 value, bytes memory callData) internal pure returns (bytes memory userOpCalldata) {
        userOpCalldata = abi.encodePacked(target, value, callData);
    }
}



// ============================================================
// FILE: contracts/lib/local/LocalCallDataParserLib.sol
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
    function parseEnableModeData(
        bytes calldata packedData
    )
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
    function parseMultiTypeInitData(bytes calldata initData) internal pure returns (uint256[] calldata types, bytes[] calldata initDatas) {
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
// FILE: contracts/interfaces/base/IModuleManager.sol
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
/// @notice Interface for managing modules within Smart Accounts, providing methods for installation and removal of modules.
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
    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext) external view returns (bool installed);
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
    /// We expect that most contracts will use `_hashTypedData` as the main hash,
    /// and `_hashTypedDataSansChainId` only occasionally for cross-chain workflows.
    /// Thus this is optimized for smaller bytecode size over runtime gas.
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

/// @title Execution
/// @notice Struct to encapsulate execution data for a transaction
struct Execution {
    /// @notice The target address for the transaction
    address target;
    /// @notice The value in wei to send with the transaction
    uint256 value;
    /// @notice The calldata for the transaction
    bytes callData;
}

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
    uint256 internal constant N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;

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

    // The following functions returns the hash of the signature in it's canonicalized format,
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
// FILE: contracts/interfaces/base/IStorage.sol
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
import { IPreValidationHookERC1271, IPreValidationHookERC4337 } from "../modules/IPreValidationHook.sol";
import { IHook } from "../modules/IHook.sol";
import { CallType } from "../../lib/ModeLib.sol";

/// @title Nexus - IStorage Interface
/// @notice Provides structured storage for Modular Smart Account under the Nexus suite, compliant with ERC-7579 and ERC-4337.
/// @dev Manages structured storage using SentinelListLib for validators and executors, and a mapping for fallback handlers.
/// This interface utilizes ERC-7201 storage location practices to ensure isolated and collision-resistant storage spaces within smart contracts.
/// It is designed to support dynamic execution and modular management strategies essential for advanced smart account architectures.
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
// FILE: contracts/interfaces/base/IModuleManagerEventsAndErrors.sol
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

import { CallType } from "../../lib/ModeLib.sol";

/// @title ERC-7579 Module Manager Events and Errors Interface
/// @notice Provides event and error definitions for actions related to module management in smart accounts.
/// @dev Used by IModuleManager to define the events and errors associated with the installation and management of modules.
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

    /// @notice Thrown when attempting to remove the last validator.
    error CanNotRemoveLastValidator();

    /// @dev Thrown when the specified module address is not recognized as valid.
    error ValidatorNotInstalled(address module);

    /// @dev Thrown when there is no installed validator detected.
    error NoValidatorInstalled();

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

    /// @dev Thrown when there is an attempt to uninstall a fallback handler for a selector that does not have one installed.
    error FallbackNotInstalledForSelector(bytes4 selector);

    /// @dev Thrown when a fallback handler fails to uninstall properly.
    error FallbackHandlerUninstallFailed();

    /// @dev Thrown when no fallback handler is available for a given selector.
    error MissingFallbackHandler(bytes4 selector);

    /// @dev Thrown when Invalid data is provided for MultiType install flow
    error InvalidInput();

    /// @dev Thrown when unable to validate Module Enable Mode signature
    error EnableModeSigError();

    /// @dev Thrown when unable to validate Emergency Uninstall signature
    error EmergencyUninstallSigError();

    /// @notice Error thrown when an invalid nonce is used
    error InvalidNonce();

    /// Error thrown when account installs/uninstalls module with mismatched moduleTypeId
    error MismatchModuleTypeId();

    /// @dev Thrown when there is an attempt to install a forbidden selector as a fallback handler.
    error FallbackSelectorForbidden();

    /// @dev Thrown when there is an attempt to install a fallback handler with an invalid calltype for a given selector.
    error FallbackCallTypeInvalid();

    /// @notice Error thrown when an execution with an unsupported CallType was made.
    /// @param callType The unsupported call type.
    error UnsupportedCallType(CallType callType);

    /// @notice Error thrown when the default validator is already installed.
    error DefaultValidatorAlreadyInstalled();
}
