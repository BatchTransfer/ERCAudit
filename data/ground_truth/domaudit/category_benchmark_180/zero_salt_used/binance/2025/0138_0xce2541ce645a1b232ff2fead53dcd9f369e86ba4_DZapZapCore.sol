// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xce2541ce645a1b232ff2fead53dcd9f369e86ba4
// Contract Name: DZapZapCore



// ============================================================
// FILE: @openzeppelin/contracts/access/Ownable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;

import {Context} from "../utils/Context.sol";

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
abstract contract Ownable is Context {
    address private _owner;

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
    constructor(address initialOwner) {
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
        return _owner;
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
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}



// ============================================================
// FILE: @openzeppelin/contracts/interfaces/IERC1363.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (interfaces/IERC1363.sol)

pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {IERC165} from "./IERC165.sol";

/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * Defines an extension interface for ERC-20 tokens that supports executing code on a recipient contract
 * after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 is IERC20, IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0xb0202a11.
     * 0xb0202a11 ===
     *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
     *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
     */

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}



// ============================================================
// FILE: @openzeppelin/contracts/interfaces/IERC165.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC165.sol)

pragma solidity ^0.8.20;

import {IERC165} from "../utils/introspection/IERC165.sol";



// ============================================================
// FILE: @openzeppelin/contracts/interfaces/IERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC20.sol)

pragma solidity ^0.8.20;

import {IERC20} from "../token/ERC20/IERC20.sol";



// ============================================================
// FILE: @openzeppelin/contracts/token/ERC1155/IERC1155.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC1155/IERC1155.sol)

pragma solidity ^0.8.20;

import {IERC165} from "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC-1155 compliant contract, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1155[ERC].
 */
interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` amount of tokens of type `id` are transferred from `from` to `to` by `operator`.
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
     * @dev Returns the value of tokens of token type `id` owned by `account`.
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
     * - `operator` cannot be the zero address.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers a `value` amount of tokens of type `id` from `from` to `to`.
     *
     * WARNING: This function can potentially allow a reentrancy attack when transferring tokens
     * to an untrusted contract, when invoking {onERC1155Received} on the receiver.
     * Ensure to follow the checks-effects-interactions pattern and consider employing
     * reentrancy guards when interacting with untrusted contracts.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `value` amount.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * WARNING: This function can potentially allow a reentrancy attack when transferring tokens
     * to an untrusted contract, when invoking {onERC1155BatchReceived} on the receiver.
     * Ensure to follow the checks-effects-interactions pattern and consider employing
     * reentrancy guards when interacting with untrusted contracts.
     *
     * Emits either a {TransferSingle} or a {TransferBatch} event, depending on the length of the array arguments.
     *
     * Requirements:
     *
     * - `ids` and `values` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external;
}



// ============================================================
// FILE: @openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC1155/IERC1155Receiver.sol)

pragma solidity ^0.8.20;

import {IERC165} from "../../utils/introspection/IERC165.sol";

/**
 * @dev Interface that must be implemented by smart contracts in order to receive
 * ERC-1155 token transfers.
 */
interface IERC1155Receiver is IERC165 {
    /**
     * @dev Handles the receipt of a single ERC-1155 token type. This function is
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
     * @dev Handles the receipt of a multiple ERC-1155 token types. This function
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
// FILE: @openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC1155/utils/ERC1155Holder.sol)

pragma solidity ^0.8.20;

import {IERC165, ERC165} from "../../../utils/introspection/ERC165.sol";
import {IERC1155Receiver} from "../IERC1155Receiver.sol";

/**
 * @dev Simple implementation of `IERC1155Receiver` that will allow a contract to hold ERC-1155 tokens.
 *
 * IMPORTANT: When inheriting this contract, you must include a way to use the received tokens, otherwise they will be
 * stuck.
 */
abstract contract ERC1155Holder is ERC165, IERC1155Receiver {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}



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
// FILE: @openzeppelin/contracts/token/ERC20/IERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
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



// ============================================================
// FILE: @openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";
import {IERC1363} from "../../../interfaces/IERC1363.sol";
import {Address} from "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     *
     * NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
     * only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
     * set here.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Performs an {ERC1363} transferAndCall, with a fallback to the simple {ERC20} transfer if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferFromAndCall, with a fallback to the simple {ERC20} transferFrom if the target
     * has no code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} approveAndCall, with a fallback to the simple {ERC20} approve if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * NOTE: When the recipient address (`to`) has no code (i.e. is an EOA), this function behaves as {forceApprove}.
     * Opposedly, when the recipient address (`to`) has code, this function only attempts to call {ERC1363-approveAndCall}
     * once without retrying, and relies on the returned value to be true.
     *
     * Reverts if the returned value is other than `true`.
     */
    function approveAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturnBool} that reverts if call fails to meet the requirements.
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize == 0 ? address(token).code.length == 0 : returnValue != 1) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silently catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? address(token).code.length > 0 : returnValue == 1);
    }
}



// ============================================================
// FILE: @openzeppelin/contracts/token/ERC721/IERC721.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC721/IERC721.sol)

pragma solidity ^0.8.20;

import {IERC165} from "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC-721 compliant contract.
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
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC-721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or
     *   {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC-721
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
     * - The `operator` cannot be the address zero.
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
// FILE: @openzeppelin/contracts/token/ERC721/IERC721Receiver.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC721/IERC721Receiver.sol)

pragma solidity ^0.8.20;

/**
 * @title ERC-721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC-721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be
     * reverted.
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
// FILE: @openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC721/utils/ERC721Holder.sol)

pragma solidity ^0.8.20;

import {IERC721Receiver} from "../IERC721Receiver.sol";

/**
 * @dev Implementation of the {IERC721Receiver} interface.
 *
 * Accepts all token transfers.
 * Make sure the contract is able to use its token with {IERC721-safeTransferFrom}, {IERC721-approve} or
 * {IERC721-setApprovalForAll}.
 */
abstract contract ERC721Holder is IERC721Receiver {
    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}



// ============================================================
// FILE: @openzeppelin/contracts/utils/Address.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/Address.sol)

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

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert Errors.FailedCall();
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
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert Errors.FailedCall();
        }
    }
}



// ============================================================
// FILE: @openzeppelin/contracts/utils/Context.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

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
// FILE: @openzeppelin/contracts/utils/cryptography/ECDSA.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/cryptography/ECDSA.sol)

pragma solidity ^0.8.20;

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
        InvalidSignatureS
    }

    /**
     * @dev The signature derives the `address(0)`.
     */
    error ECDSAInvalidSignature();

    /**
     * @dev The signature has an invalid length.
     */
    error ECDSAInvalidSignatureLength(uint256 length);

    /**
     * @dev The signature has an S value that is in the upper half order.
     */
    error ECDSAInvalidSignatureS(bytes32 s);

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with `signature` or an error. This will not
     * return address(0) without also returning an error description. Errors are documented using an enum (error type)
     * and a bytes32 providing additional information about the error.
     *
     * If no error is returned, then the address can be used for verification purposes.
     *
     * The `ecrecover` EVM precompile allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {MessageHashUtils-toEthSignedMessageHash} on it.
     *
     * Documentation for signature generation:
     * - with https://web3js.readthedocs.io/en/v1.3.4/web3-eth-accounts.html#sign[Web3.js]
     * - with https://docs.ethers.io/v5/api/signer/#Signer-signMessage[ethers]
     */
    function tryRecover(
        bytes32 hash,
        bytes memory signature
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            assembly ("memory-safe") {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(signature.length));
        }
    }

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature`. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM precompile allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {MessageHashUtils-toEthSignedMessageHash} on it.
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, signature);
        _throwError(error, errorArg);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `r` and `vs` short-signature fields separately.
     *
     * See https://eips.ethereum.org/EIPS/eip-2098[ERC-2098 short signatures]
     */
    function tryRecover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
        unchecked {
            bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            // We do not check for an overflow here since the shift operation results in 0 or 1.
            uint8 v = uint8((uint256(vs) >> 255) + 27);
            return tryRecover(hash, v, r, s);
        }
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `r and `vs` short-signature fields separately.
     */
    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, r, vs);
        _throwError(error, errorArg);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `v`,
     * `r` and `s` signature fields separately.
     */
    function tryRecover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
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
            return (address(0), RecoverError.InvalidSignatureS, s);
        }

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature, bytes32(0));
        }

        return (signer, RecoverError.NoError, bytes32(0));
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `v`,
     * `r` and `s` signature fields separately.
     */
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, v, r, s);
        _throwError(error, errorArg);
        return recovered;
    }

    /**
     * @dev Optionally reverts with the corresponding custom error according to the `error` argument provided.
     */
    function _throwError(RecoverError error, bytes32 errorArg) private pure {
        if (error == RecoverError.NoError) {
            return; // no error: do nothing
        } else if (error == RecoverError.InvalidSignature) {
            revert ECDSAInvalidSignature();
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert ECDSAInvalidSignatureLength(uint256(errorArg));
        } else if (error == RecoverError.InvalidSignatureS) {
            revert ECDSAInvalidSignatureS(errorArg);
        }
    }
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



// ============================================================
// FILE: @openzeppelin/contracts/utils/introspection/ERC165.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/introspection/ERC165.sol)

pragma solidity ^0.8.20;

import {IERC165} from "./IERC165.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC-165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}



// ============================================================
// FILE: @openzeppelin/contracts/utils/introspection/IERC165.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/introspection/IERC165.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
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
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}



// ============================================================
// FILE: @openzeppelin/contracts/utils/Pausable.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/Pausable.sol)

pragma solidity ^0.8.20;

import {Context} from "../utils/Context.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}



// ============================================================
// FILE: @openzeppelin/contracts/utils/ReentrancyGuard.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.20;

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
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
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
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
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
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}



// ============================================================
// FILE: contracts/interfaces/IDZapZapCore.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { InputErc20Tokens, FeeConfig, ZapData, TokenInfo } from "../zap/Types.sol";
import { PermitBatchTransferFrom } from "../interfaces/IPermit2.sol";

interface IDZapZapCore {
    // ============= EXTERNAL FUNCTIONS =============

    /// @notice Executes a zap with individual token permits
    /// @param _transactionId Unique transaction identifier
    /// @param _crosschainData Additional crosschain data
    /// @param _zapVerificationSignature Verifier signature for zap authorization
    /// @param _deadline Signature expiration timestamp
    /// @param _dustReceiver Address to receive leftover tokens
    /// @param _inputTokens Input tokens with permit data
    /// @param _feeConfig Fee distribution configuration
    /// @param _zapData Array of zap execution data
    /// @param _sweepDust Token addresses to sweep as dust
    function zap(
        bytes32 _transactionId,
        bytes calldata _crosschainData,
        bytes calldata _zapVerificationSignature,
        uint256 _deadline,
        address _dustReceiver,
        InputErc20Tokens[] calldata _inputTokens,
        FeeConfig calldata _feeConfig,
        ZapData[] calldata _zapData,
        address[] calldata _sweepDust
    ) external payable;

    /// @notice Executes a zap with batch permit2 transfer
    /// @param _transactionId Unique transaction identifier
    /// @param _crosschainData Additional crosschain data
    /// @param _zapVerificationSignature Verifier signature for zap authorization
    /// @param _batchDepositSignature User signature for batch transfer
    /// @param _deadline Signature expiration timestamp
    /// @param _dustReceiver Address to receive leftover tokens
    /// @param _tokenDepositDetails Batch transfer permit details
    /// @param _feeConfig Fee distribution configuration
    /// @param _zapData Array of zap execution data
    /// @param _sweepDust Token addresses to sweep as dust
    function zapWithBatchDeposit(
        bytes32 _transactionId,
        bytes calldata _crosschainData,
        bytes calldata _zapVerificationSignature,
        bytes calldata _batchDepositSignature,
        uint256 _deadline,
        address _dustReceiver,
        PermitBatchTransferFrom calldata _tokenDepositDetails,
        FeeConfig calldata _feeConfig,
        ZapData[] calldata _zapData,
        address[] calldata _sweepDust
    ) external payable;

    /// @notice Executes a zap with individual token permits
    /// @param _transactionId Unique transaction identifier
    /// @param _crosschainData Additional crosschain data
    /// @param _zapVerificationSignature Verifier signature for zap authorization
    /// @param _userIntentSignature User's intent signature
    /// @param _zapDeadline Zap deadline
    /// @param _userIntentDeadline User intent deadline
    /// @param _user User address
    /// @param _dustReceiver Address to receive leftover tokens
    /// @param _inputTokens Input tokens with permit data
    /// @param _feeConfig Fee distribution configuration
    /// @param _executorFeeInfo Executor fee information
    /// @param _zapData Array of zap execution data
    /// @param _sweepDust Token addresses to sweep as dust
    function executeZap(
        bytes32 _transactionId,
        bytes calldata _crosschainData,
        bytes calldata _zapVerificationSignature,
        bytes calldata _userIntentSignature,
        uint256 _zapDeadline,
        uint256 _userIntentDeadline,
        address _user,
        address _dustReceiver,
        InputErc20Tokens[] calldata _inputTokens,
        FeeConfig calldata _feeConfig,
        TokenInfo[] calldata _executorFeeInfo,
        ZapData[] calldata _zapData,
        address[] calldata _sweepDust
    ) external payable;

    /// @notice Executes a gasless zap on behalf of a user (with batch permit2)
    /// @param _transactionId Unique transaction identifier
    /// @param _crosschainData Additional crosschain data
    /// @param _zapVerificationSignature Verifier signature for zap authorization
    /// @param _userIntentSignature User's signature for gasless execution
    /// @param _zapDeadline Zap verification signature deadline
    /// @param _user User address on whose behalf the zap is executed
    /// @param _dustReceiver Address to receive leftover tokens
    /// @param _tokenDepositDetails Batch transfer permit details
    /// @param _feeConfig Fee distribution configuration
    /// @param _executorFeeInfo Executor fee information
    /// @param _zapData Array of zap execution data
    /// @param _sweepDust Token addresses to sweep as dust
    function executeZapWithWitness(
        bytes32 _transactionId,
        bytes calldata _crosschainData,
        bytes calldata _zapVerificationSignature,
        bytes calldata _userIntentSignature,
        uint256 _zapDeadline,
        address _user,
        address _dustReceiver,
        PermitBatchTransferFrom calldata _tokenDepositDetails,
        FeeConfig calldata _feeConfig,
        TokenInfo[] calldata _executorFeeInfo,
        ZapData[] calldata _zapData,
        address[] calldata _sweepDust
    ) external payable;
}



// ============================================================
// FILE: contracts/interfaces/IPermit2.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

struct PermitDetails {
    address token;
    uint160 amount;
    uint48 expiration;
    uint48 nonce;
}

struct PermitSingle {
    PermitDetails details;
    address spender;
    uint256 sigDeadline;
}

struct TokenPermissions {
    address token;
    uint256 amount;
}

struct PermitTransferFrom {
    TokenPermissions permitted;
    uint256 nonce;
    uint256 deadline;
}

struct SignatureTransferDetails {
    address to;
    uint256 requestedAmount;
}

struct PermitBatchTransferFrom {
    // the tokens and corresponding amounts permitted for a transfer
    TokenPermissions[] permitted;
    // a unique value for every token owner's signature to prevent signature replays
    uint256 nonce;
    // deadline on the permit signature
    uint256 deadline;
}

interface IPermit2 {
    function permit(address owner, PermitSingle memory permitSingle, bytes calldata signature) external;

    function approve(address token, address spender, uint160 amount, uint48 deadline) external;

    function transferFrom(address from, address to, uint160 amount, address token) external;

    function allowance(address owner, address token, address spender) external view returns (uint160, uint48, uint48);

    function permitWitnessTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;

    function permitWitnessTransferFrom(
        PermitBatchTransferFrom memory permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;
}



// ============================================================
// FILE: contracts/shared/libraries/LibAsset.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IPermit2, PermitBatchTransferFrom } from "../../interfaces/IPermit2.sol";
import { InputErc20Tokens, PermitType } from "../../zap/Types.sol";
import { LibPermit } from "./LibPermit.sol";

/**
 * @title LibAsset
 * @author DZap
 * @notice This library contains helpers for dealing with onchain transfers
 *         of assets, including accounting for the native asset `assetId`
 *         conventions and any noncompliant ERC20 transfers
 */
library LibAsset {
    using SafeERC20 for IERC20;

    // ============= ERRORS =============

    error NativeTransferFailed();
    error NoTransferToNullAddress();
    error NullAddrIsNotAValidSpender();
    error InvalidAmount();
    error InvalidPermitType();

    // ============= CONSTANTS =============

    address internal constant _NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // ============= BALANCE QUERY FUNCTIONS =============

    function selfNativeBalance() internal view returns (uint256 contractBalance) {
        assembly {
            contractBalance := selfbalance()
        }
    }

    function getErc20Balance(address _token, address _account) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_account);
    }

    function getBalance(address _token, address _account) internal view returns (uint256) {
        return _token == _NATIVE_TOKEN ? _account.balance : IERC20(_token).balanceOf(_account);
    }

    function getNativeBalance(address _account) internal view returns (uint256) {
        return _account.balance;
    }

    function getOwnerOfERC721(address _token, uint256 _id) internal view returns (address) {
        return IERC721(_token).ownerOf(_id);
    }
    function getBalanceOfERC1155(address _token, address _account, uint256 _id) internal view returns (uint256) {
        return IERC1155(_token).balanceOf(_account, _id);
    }

    // ============= TRANSFER FUNCTIONS =============

    function transferToken(address _token, address _to, uint256 _amount) internal {
        if (_token == _NATIVE_TOKEN) transferNativeToken(_to, _amount);
        else transferERC20(_token, _to, _amount);
    }

    function transferNativeToken(address _to, uint256 _amount) internal {
        if (_amount == 0) return;
        require(_to != address(0), NoTransferToNullAddress());

        (bool success, ) = _to.call{ value: _amount }("");
        require(success, NativeTransferFailed());
    }

    function transferERC20(address _token, address _to, uint256 _amount) internal {
        if (_amount == 0) return;
        require(_to != address(0), NoTransferToNullAddress());

        IERC20(_token).safeTransfer(_to, _amount);
    }

    function transferERC20WithoutChecks(address _token, address _to, uint256 _amount) internal {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function transferFromERC20(address _token, address _from, address _to, uint256 _amount) internal {
        IERC20(_token).safeTransferFrom(_from, _to, _amount);
    }

    function transferERC721(address _token, address _to, uint256 _id) internal {
        IERC721(_token).safeTransferFrom(address(this), _to, _id);
    }

    function transferERC721(address _token, address _from, address _to, uint256 _id) internal {
        IERC721(_token).safeTransferFrom(_from, _to, _id);
    }

    function transferBatchERC1155(address _token, address _to, uint256[] memory _ids, uint256[] memory _amounts) internal {
        IERC1155(_token).safeBatchTransferFrom(address(this), _to, _ids, _amounts, "");
    }

    function transferERC1155(address _token, address _from, address _to, uint256 _id, uint256 _amount) internal {
        IERC1155(_token).safeTransferFrom(_from, _to, _id, _amount, "");
    }

    // ============= APPROVAL FUNCTIONS =============

    /// @notice If the current allowance is insufficient, then MAX_UINT allowance for a given spender
    function maxApproveERC20(address _token, address _spender, uint256 _amount) internal {
        require(_spender != address(this), NullAddrIsNotAValidSpender());

        uint256 allowance = IERC20(_token).allowance(address(this), _spender);
        if (allowance < _amount) {
            SafeERC20.forceApprove(IERC20(_token), _spender, type(uint256).max);
        }
    }

    function maxPermit2Approve(address _permit2, address _token, address _spender, uint256 _amount) internal {
        require(_spender != address(0), NullAddrIsNotAValidSpender());

        (uint160 allowance, uint48 expiration, ) = IPermit2(_permit2).allowance(address(this), _token, _spender);
        if (allowance < _amount || block.timestamp > expiration) {
            IPermit2(_permit2).approve(_token, _spender, type(uint160).max, type(uint48).max);
        }

        maxApproveERC20(_token, _permit2, _amount);
    }

    function approveERC721(address _token, address _to, uint256 _tokenId) internal {
        require(_to != address(0), NullAddrIsNotAValidSpender());
        IERC721(_token).approve(_to, _tokenId);
    }

    function approveERC1155(address _token, address _spender) internal {
        IERC1155(_token).setApprovalForAll(_spender, true);
    }

    function isErc1155ApprovedForAll(address _token, address _operator, address _spender) internal view returns (bool) {
        return IERC1155(_token).isApprovedForAll(_operator, _spender);
    }

    function revokeERC1155(address _token, address _spender) internal {
        IERC1155(_token).setApprovalForAll(_spender, false);
    }

    // ============= DEPOSIT FUNCTIONS =============

    /// @notice Deposits tokens from a sender to the inheriting contract
    /// @dev only handles erc20 token
    function depositErc20(address _permit2, address _user, address _token, uint256 _amount, bytes calldata _permit) internal {
        (PermitType permitType, bytes memory data) = abi.decode(_permit, (PermitType, bytes));

        if (permitType == PermitType.PERMIT2_WITNESS_TRANSFER) {
            LibPermit.permit2WitnessTransferFrom(_permit2, _user, address(this), _token, _amount, data);
        } else if (permitType == PermitType.PERMIT) {
            if (data.length != 0) LibPermit.eip2612Permit(_user, address(this), _token, _amount, data);
            transferFromERC20(_token, _user, address(this), _amount);
        } else if (permitType == PermitType.PERMIT2_APPROVE) {
            LibPermit.permit2ApproveAndTransfer(_permit2, _user, address(this), _token, uint160(_amount), data);
        } else {
            revert InvalidPermitType();
        }
    }

    function depositBatch(address _permit2, address _user, InputErc20Tokens[] calldata erc20Tokens) internal {
        uint256 length = erc20Tokens.length;
        for (uint256 i; i < length; ++i) {
            depositErc20(_permit2, _user, erc20Tokens[i].token, erc20Tokens[i].amount, erc20Tokens[i].permit);
        }
    }

    function depositBatch(address _permit2, address _user, PermitBatchTransferFrom calldata permit, bytes calldata permitSignature) internal {
        LibPermit.permit2BatchWitnessTransferFrom(_permit2, _user, address(this), permit, permitSignature);
    }

    // ============= UTILITY FUNCTIONS =============

    /// @notice Determines whether the given token is the native token
    function isNativeToken(address _token) internal pure returns (bool) {
        return _token == _NATIVE_TOKEN;
    }
}



// ============================================================
// FILE: contracts/shared/libraries/LibPermit.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { PermitTransferFrom, PermitBatchTransferFrom, SignatureTransferDetails, PermitSingle, PermitDetails, TokenPermissions, IPermit2 } from "../../interfaces/IPermit2.sol";

/**
 * @title LibPermit
 * @author DZap
 * @notice This library contains helpers for using permit and permit2
 */
library LibPermit {
    // ============= ERRORS =============

    error InvalidPermit(string reason);

    // ============= CONSTANTS =============

    string internal constant _DZAP_TRANSFER_WITNESS_TYPE_STRING =
        "DZapTransferWitness witness)DZapTransferWitness(address owner,address recipient)TokenPermissions(address token,uint256 amount)";
    bytes32 internal constant _DZAP_TRANSFER_WITNESS_TYPEHASH = keccak256("DZapTransferWitness(address owner,address recipient)");

    // ============= EIP-2612 PERMIT FUNCTIONS =============

    /// @notice Handles eip2612 permit
    function eip2612Permit(address _owner, address _spender, address _token, uint256 _amount, bytes memory _data) internal {
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(_data, (uint256, uint8, bytes32, bytes32));
        IERC20Permit(_token).permit(_owner, _spender, _amount, deadline, v, r, s);
    }

    // ============= PERMIT2 FUNCTIONS =============

    /// @notice Handles permit2 approve and transfer
    function permit2ApproveAndTransfer(address _permit2, address _from, address _to, address _token, uint160 _amount, bytes memory data) internal {
        permit2Approve(_permit2, _from, _to, _token, _amount, data);
        IPermit2(_permit2).transferFrom(_from, _to, uint160(_amount), _token);
    }

    /// @notice Handles permit2 approve
    function permit2Approve(address _permit2, address _owner, address _spender, address _token, uint160 _amount, bytes memory _data) internal {
        if (_data.length == 0) return;
        IPermit2 permit2Contract = IPermit2(_permit2);
        (uint48 nonce, uint48 expiration, uint256 sigDeadline, bytes memory signature) = abi.decode(_data, (uint48, uint48, uint256, bytes));

        try
            permit2Contract.permit(_owner, PermitSingle(PermitDetails(_token, _amount, expiration, nonce), _spender, sigDeadline), signature)
        {} catch Error(string memory reason) {
            (uint256 currentAllowance, uint256 allowanceExpiration, ) = permit2Contract.allowance(_owner, _token, _spender);
            require(currentAllowance >= _amount && allowanceExpiration >= block.timestamp, InvalidPermit(reason));
        }
    }

    /// @notice Handles permit2 witness transfer from
    function permit2WitnessTransferFrom(
        address _permit2,
        address _owner,
        address _recipient,
        address _token,
        uint256 _amount,
        bytes memory _data
    ) internal {
        (uint256 nonce, uint256 deadline, bytes memory _signature) = abi.decode(_data, (uint256, uint256, bytes));

        IPermit2(_permit2).permitWitnessTransferFrom(
            PermitTransferFrom(TokenPermissions(_token, _amount), nonce, deadline),
            SignatureTransferDetails(_recipient, _amount),
            _owner,
            _createWitnessTransferFromHash(_owner, _recipient),
            _DZAP_TRANSFER_WITNESS_TYPE_STRING,
            _signature
        );
    }

    /// @notice Handles permit2 batch witness transfer from
    function permit2BatchWitnessTransferFrom(
        address _permit2,
        address _owner,
        address _recipient,
        PermitBatchTransferFrom calldata permit,
        bytes calldata _signature
    ) internal {
        uint256 length = permit.permitted.length;
        SignatureTransferDetails[] memory details = new SignatureTransferDetails[](length);

        for (uint256 i; i < length; ++i) {
            details[i] = SignatureTransferDetails(_recipient, permit.permitted[i].amount);
        }

        IPermit2(_permit2).permitWitnessTransferFrom(
            permit,
            details,
            _owner,
            _createWitnessTransferFromHash(_owner, _recipient),
            _DZAP_TRANSFER_WITNESS_TYPE_STRING,
            _signature
        );
    }

    /// @notice Handles permit2 batch witness transfer from
    function permit2BatchWitnessTransferFrom(
        address _permit2,
        address _owner,
        address _recipient,
        bytes32 _witness,
        PermitBatchTransferFrom calldata permit,
        bytes calldata _signature,
        string memory _witnessTypeString
    ) internal {
        uint256 length = permit.permitted.length;
        SignatureTransferDetails[] memory details = new SignatureTransferDetails[](length);

        for (uint256 i; i < length; ++i) {
            details[i] = SignatureTransferDetails(_recipient, permit.permitted[i].amount);
        }

        IPermit2(_permit2).permitWitnessTransferFrom(permit, details, _owner, _witness, _witnessTypeString, _signature);
    }

    /* ========= PRIVATE ========= */

    function _createWitnessTransferFromHash(address _owner, address _recipient) private pure returns (bytes32) {
        return keccak256(abi.encode(_DZAP_TRANSFER_WITNESS_TYPEHASH, _owner, _recipient));
    }
}



// ============================================================
// FILE: contracts/zap/DZapAdmin.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { LibAsset } from "../shared/libraries/LibAsset.sol";
import { DZapCoreBase } from "./DZapCoreBase.sol";
import { InvalidProtocolFeeVault, ZeroAddress, NoTransferToNullAddress, UniswapPermit2AlreadySet, UniswapPermit2ByteCodeMismatch, ProtectedSelector } from "./Errors.sol";

/// @title DZapAdmin
/// @author DZap
/// @notice Abstract contract containing all administrative functions
/// @dev Provides gas-optimized admin operations for contract management
abstract contract DZapAdmin is DZapCoreBase, Pausable {
    // ============= PROTOCOL CONFIGURATION =============

    /// @notice Updates protocol fee vault address
    /// @param _protocolFeeVault New protocol fee vault address
    function setProtocolFeeVault(address _protocolFeeVault) external onlyOwner {
        require(_protocolFeeVault != address(0) && _protocolFeeVault != address(this), InvalidProtocolFeeVault());
        protocolFeeVault = _protocolFeeVault;
        emit ProtocolFeeVaultSet(_protocolFeeVault);
    }

    /// @notice Updates zap verifier address
    /// @param _verifier New verifier address
    function setVerifier(address _verifier) external onlyOwner {
        require(_verifier != address(0), ZeroAddress());
        zapVerifier = _verifier;
        emit ZapVerifierSet(_verifier);
    }

    /// @notice Updates to Uniswap Permit2 if bytecode matches expected hash
    function updateToUniswapPermit2() external onlyOwnerOrAdmin {
        require(permit2 != UNISWAP_PERMIT2, UniswapPermit2AlreadySet());
        require(keccak256(UNISWAP_PERMIT2.code) == EXPECTED_PERMIT2_RUNTIME_HASH, UniswapPermit2ByteCodeMismatch());
        permit2 = UNISWAP_PERMIT2;
        emit Permit2Updated();
    }

    // ============= ADMIN MANAGEMENT =============

    /// @notice Adds an address as an admin
    /// @param _account Address to add as admin
    function addAdmin(address _account) external onlyOwner {
        admins[_account] = true;
        emit AdminAdded(_account);
    }

    /// @notice Removes an address from admin role
    /// @param _account Address to remove from admin
    function removeAdmin(address _account) external onlyOwner {
        admins[_account] = false;
        emit AdminRemoved(_account);
    }

    // ============= WHITELIST MANAGEMENT =============

    /// @notice Updates adapter whitelist status for multiple addresses
    /// @param _adapters Array of adapter addresses to update
    /// @param _whitelisted Whether adapters should be whitelisted
    function whitelistAdapters(address[] calldata _adapters, bool _whitelisted) external onlyOwner {
        uint256 length = _adapters.length;

        for (uint256 i; i < length; ++i) {
            address adapter = _adapters[i];
            require(adapter != address(0), ZeroAddress());
            _adaptersAllowlist[adapter] = _whitelisted;
        }

        emit AdaptersWhitelistingUpdated(_adapters, _whitelisted);
    }

    /// @notice Updates ERC1155 spender whitelist status for multiple addresses
    /// @param _spenders Array of spender addresses to update
    /// @param _whitelisted Whether spenders should be whitelisted
    function whitelistErc1155Spender(address[] calldata _spenders, bool _whitelisted) external onlyOwner {
        uint256 length = _spenders.length;

        for (uint256 i; i < length; ++i) {
            address spender = _spenders[i];
            require(spender != address(0), ZeroAddress());
            _allowedErc1155Spender[spender] = _whitelisted;
        }

        emit Erc1155SpenderWhitelistingUpdated(_spenders, _whitelisted);
    }

    /// @notice Blocks multiple selectors
    /// @param _selectors Array of selectors to block
    function blockSelectors(bytes4[] calldata _selectors) external onlyOwner {
        uint256 length = _selectors.length;

        for (uint256 i; i < length; ++i) {
            bytes4 selector = _selectors[i];
            blockedSelectors[selector] = true;
        }

        emit SelectorsBlacklistingUpdated(_selectors, true);
    }

    /// @notice Unblocks multiple selectors
    /// @param _selectors Array of selectors to unblock
    function unblockSelectors(bytes4[] calldata _selectors) external onlyOwner {
        uint256 length = _selectors.length;

        for (uint256 i; i < length; ++i) {
            bytes4 selector = _selectors[i];
            require(!_isProtectedSelector(selector), ProtectedSelector(selector));
            blockedSelectors[selector] = false;
        }

        emit SelectorsBlacklistingUpdated(_selectors, false);
    }

    // ============= EMERGENCY RECOVERY =============

    /// @notice Recovers stuck ERC20/native tokens from the contract
    /// @param _token Token address (use LibAsset._NATIVE_TOKEN for native)
    /// @param _recipient Recovery recipient address
    /// @param _amount Amount to recover
    function recoverToken(address _token, address _recipient, uint256 _amount) external onlyOwner {
        require(_recipient != address(0), NoTransferToNullAddress());
        LibAsset.transferToken(_token, _recipient, _amount);
        emit TokenRecovered(_token, _recipient, _amount);
    }

    /// @notice Recovers stuck ERC721 tokens from the contract
    /// @param _token ERC721 contract address
    /// @param _recipient Recovery recipient address
    /// @param _id Token ID to recover
    function recoverERC721(address _token, address _recipient, uint256 _id) external onlyOwner {
        require(_recipient != address(0), NoTransferToNullAddress());
        LibAsset.transferERC721(_token, _recipient, _id);
        emit ERC721Recovered(_token, _recipient, _id);
    }

    /// @notice Recovers stuck ERC1155 tokens from the contract
    /// @param _token ERC1155 contract address
    /// @param _recipient Recovery recipient address
    /// @param _ids Array of token IDs to recover
    /// @param _amounts Array of amounts to recover for each ID
    function recoverERC1155(address _token, address _recipient, uint256[] calldata _ids, uint256[] calldata _amounts) external onlyOwner {
        require(_recipient != address(0), NoTransferToNullAddress());
        LibAsset.transferBatchERC1155(_token, _recipient, _ids, _amounts);
        emit ERC1155Recovered(_token, _recipient, _ids, _amounts);
    }

    // ============= PAUSE FUNCTIONALITY =============

    /// @notice Pauses contract operations
    function pause() external onlyOwnerOrAdmin whenNotPaused {
        _pause();
    }

    /// @notice Unpauses contract operations
    function unpause() external onlyOwnerOrAdmin whenPaused {
        _unpause();
    }

    // solhint-disable-next-line code-complexity
    function _isProtectedSelector(bytes4 selector) private pure returns (bool) {
        if (selector == bytes4(0)) return true;

        // ERC20 functions
        if (selector == IERC20.approve.selector) return true;
        if (selector == IERC20.transfer.selector) return true;
        if (selector == IERC20.transferFrom.selector) return true;

        // ERC721 functions
        if (selector == IERC721.approve.selector) return true;
        if (selector == IERC721.transferFrom.selector) return true;
        if (selector == IERC721.setApprovalForAll.selector) return true;
        if (selector == bytes4(keccak256("safeTransferFrom(address,address,uint256)"))) return true;
        if (selector == bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"))) return true;

        // ERC1155 functions
        if (selector == IERC1155.safeTransferFrom.selector) return true;
        if (selector == IERC1155.safeBatchTransferFrom.selector) return true;
        if (selector == IERC1155.setApprovalForAll.selector) return true;

        return false;
    }
}



// ============================================================
// FILE: contracts/zap/DZapCoreBase.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { LibAsset } from "../shared/libraries/LibAsset.sol";

import { InvalidProtocolFeeVault, ZeroAddress, NoTransferToNullAddress, CallerIsNotOwnerOrAdmin } from "./Errors.sol";

/// @title DZapCoreBase
/// @author DZap
/// @notice Base contract containing core state variables, modifiers, and constructor
/// @dev This contract establishes the foundation for the modular DZap architecture
abstract contract DZapCoreBase is Ownable, ERC721Holder, ERC1155Holder, ReentrancyGuard {
    // ============= PUBLIC STORAGE =============
    address public protocolFeeVault;
    address public zapVerifier;
    address public permit2;

    // ============= MAPPINGS =============
    mapping(address user => uint256 nonce) public nonce;
    mapping(address admin => bool isAdmin) public admins;
    mapping(bytes4 selector => bool isBlocked) public blockedSelectors;
    mapping(address adapter => bool isWhitelisted) internal _adaptersAllowlist;
    mapping(address spender => bool isWhitelisted) internal _allowedErc1155Spender;

    // ============= IMMUTABLE VARIABLES =============
    address public immutable UNISWAP_PERMIT2;
    bytes32 public immutable EXPECTED_PERMIT2_RUNTIME_HASH;
    bytes32 internal immutable _DOMAIN_SEPARATOR;

    // ============= CONSTANTS =============
    string internal constant _DOMAIN_NAME = "DZapVerifier";
    string internal constant _ZAP_VERSION = "1";

    bytes32 internal constant _GASLESS_WITNESS_TYPEHASH =
        keccak256(
            "DZapGaslessZapWitness(bytes32 txId,address user,address dustReceiver,bytes32 zapDataHash,bytes32 feeDataHash,bytes32 executorFeeDataHash,bytes32 crosschainDataHash,bytes32 sweepDataHash)"
        );

    bytes32 internal constant _SIGNED_GASLESS_DATA_TYPEHASH =
        keccak256(
            "DZapGaslessZapData(bytes32 txId,address user,address dustReceiver,uint256 nonce,uint256 deadline,bytes32 zapDataHash,bytes32 feeDataHash,bytes32 executorFeeDataHash,bytes32 crosschainDataHash,bytes32 sweepDataHash)"
        );

    bytes32 internal constant _SIGNED_ZAP_DATA_TYPEHASH =
        keccak256("DZapSignedZapData(bytes32 txId,address user,uint256 nonce,uint256 deadline,bytes32 zapDataHash,bytes32 feeDataHash)");

    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");

    string internal constant _GASLESS_WITNESS_TYPE_STRING =
        "DZapGaslessZapWitness witness)DZapGaslessZapWitness(bytes32 txId,address user,address dustReceiver,bytes32 zapDataHash,bytes32 feeDataHash,bytes32 executorFeeDataHash,bytes32 crosschainDataHash,bytes32 sweepDataHash)TokenPermissions(address token,uint256 amount)";

    // ============= EVENTS =============

    event ProtocolFeeVaultSet(address indexed newVault);
    event ZapVerifierSet(address indexed newVerifier);
    event Permit2Updated();
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event SelectorsBlacklistingUpdated(bytes4[] selectors, bool whitelisted);
    event AdaptersWhitelistingUpdated(address[] adapters, bool whitelisted);
    event Erc1155SpenderWhitelistingUpdated(address[] spenders, bool whitelisted);
    event TokenRecovered(address indexed token, address indexed recipient, uint256 amount);
    event ERC721Recovered(address indexed token, address indexed recipient, uint256 indexed tokenId);
    event ERC1155Recovered(address indexed token, address indexed recipient, uint256[] tokenIds, uint256[] amounts);
    event Zapped(bytes32 indexed transactionId, address indexed user, address indexed integrator, bytes crosschainData);
    event GaslessZapped(bytes32 indexed transactionId, address executor, address indexed user, address indexed integrator, bytes crosschainData);

    // ============= MODIFIERS =============

    /// @notice Restricts access to owner or admin
    modifier onlyOwnerOrAdmin() {
        require(msg.sender == owner() || admins[msg.sender], CallerIsNotOwnerOrAdmin());
        _;
    }

    /// @notice Validates dust receiver address
    modifier validDustReceiver(address _dustReceiver) {
        require(_dustReceiver != address(0), NoTransferToNullAddress());
        _;
    }

    modifier refundExcessNative(address _refundee) {
        uint256 initialBalance = LibAsset.selfNativeBalance() - msg.value;
        _;
        uint256 finalBalance = LibAsset.selfNativeBalance();
        if (finalBalance > initialBalance) LibAsset.transferNativeToken(_refundee, finalBalance - initialBalance);
    }

    // ============= VIEWS =============

    function isAdapterWhitelisted(address adapter) public view returns (bool isWhitelisted) {
        return _adaptersAllowlist[adapter];
    }

    function isErc1155SpenderWhitelisted(address spender) public view returns (bool isWhitelisted) {
        return _allowedErc1155Spender[spender];
    }

    // ============= CONSTRUCTOR =============

    /// @notice Initializes the DZap core base contract
    /// @param _owner Contract owner address
    /// @param _protocolFeeVault Protocol fee recipient address
    /// @param _zapVerifier Address authorized to sign zap verifications
    /// @param _permit2 Permit2 contract address
    /// @param _uniswapPermit2 Uniswap Permit2 contract address
    /// @param _uniswapPermit2BytecodeHash Expected bytecode hash for Uniswap Permit2
    /// @param _salt Domain separator salt
    constructor(
        address _owner,
        address _protocolFeeVault,
        address _zapVerifier,
        address _permit2,
        address _uniswapPermit2,
        bytes32 _uniswapPermit2BytecodeHash,
        bytes32 _salt
    ) Ownable(_owner) {
        require(_zapVerifier != address(0) && _permit2 != address(0), ZeroAddress());
        require(_protocolFeeVault != address(0) && _protocolFeeVault != address(this), InvalidProtocolFeeVault());

        protocolFeeVault = _protocolFeeVault;
        zapVerifier = _zapVerifier;
        permit2 = _permit2;
        UNISWAP_PERMIT2 = _uniswapPermit2;
        EXPECTED_PERMIT2_RUNTIME_HASH = _uniswapPermit2BytecodeHash;

        _DOMAIN_SEPARATOR = keccak256(
            abi.encode(_DOMAIN_TYPEHASH, keccak256(bytes(_DOMAIN_NAME)), keccak256(bytes(_ZAP_VERSION)), block.chainid, address(this), _salt)
        );

        blockedSelectors[IERC20.approve.selector] = true;
        blockedSelectors[IERC20.transfer.selector] = true;
        blockedSelectors[IERC20.transferFrom.selector] = true;

        blockedSelectors[IERC721.approve.selector] = true;
        blockedSelectors[IERC721.transferFrom.selector] = true;
        blockedSelectors[IERC721.setApprovalForAll.selector] = true;
        blockedSelectors[bytes4(keccak256("safeTransferFrom(address,address,uint256)"))] = true;
        blockedSelectors[bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"))] = true;

        blockedSelectors[IERC1155.safeTransferFrom.selector] = true;
        blockedSelectors[IERC1155.safeBatchTransferFrom.selector] = true;
        blockedSelectors[IERC1155.setApprovalForAll.selector] = true;
    }

    // ============= RECEIVE NATIVE TOKENS =============

    /// @notice Allows contract to receive native tokens
    receive() external payable {}
}



// ============================================================
// FILE: contracts/zap/DZapExecution.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { DZapTokenHandler } from "./DZapTokenHandler.sol";
import { ZapData } from "./Types.sol";
import { UnauthorizedCall, ZapExecutionFailed, SelectorNotAllowed } from "./Errors.sol";

/// @title DZapExecution
/// @author DZap
/// @notice Abstract contract for handling zap execution logic
/// @dev Provides gas-optimized execution of external calls and zap operations
abstract contract DZapExecution is DZapTokenHandler {
    // ============= CORE EXECUTION FUNCTIONS =============

    /// @notice Executes a single external call (regular call or delegatecall)
    /// @param _zapData Zap execution data containing call information
    function _execute(ZapData memory _zapData) internal {
        if (_zapData.callData.length == 0) return;

        bool success;
        bytes memory result;

        if (_zapData.isDelegateCall) {
            require(_zapData.callTo != address(this), UnauthorizedCall(_zapData.callTo));

            // solhint-disable-next-line
            (success, result) = _zapData.callTo.delegatecall(_zapData.callData);
        } else {
            bytes4 selector = bytes4(_zapData.callData);
            require(!blockedSelectors[selector], SelectorNotAllowed(_zapData.callTo, selector));

            (success, result) = _zapData.callTo.call{ value: _zapData.nativeValue }(_zapData.callData);
        }

        require(success, ZapExecutionFailed(_zapData.callTo, bytes4(_zapData.callData), result));
    }

    /// @notice Executes a complete zap operation with multiple steps
    /// @param _zapData Array of zap execution steps
    function _handleZap(ZapData[] calldata _zapData, address _user) internal {
        uint256 length = _zapData.length;

        for (uint256 i; i < length; ++i) {
            bool hasErc1155AsInput = _processInputTokens(_zapData[i].inputTokens, _user, _zapData[i].approveTo);

            uint256[] memory initialOutputBalances = _getOutputTokensInitialBalances(_zapData[i].outputTokens, _zapData[i].nativeValue);

            _execute(_zapData[i]);

            _processOutputTokens(_zapData[i].outputTokens, initialOutputBalances);

            if (hasErc1155AsInput) {
                _revokeErc1155Approvals(_zapData[i].inputTokens, _zapData[i].approveTo);
            }
        }
    }
}



// ============================================================
// FILE: contracts/zap/DZapTokenHandler.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { LibAsset } from "../shared/libraries/LibAsset.sol";
import { DZapVerification } from "./DZapVerification.sol";
import { InputToken, OutputToken, TokenType, InputTransferType, OutputTransferType, TokenInfo, FeeConfig } from "./Types.sol";
import { InvalidTokenOwner, InvalidReturnAmount, InvalidRecipient, FeeExceedsReturnAmount, Erc1155SpenderNotWhitelisted } from "./Errors.sol";

/// @title DZapTokenHandler
/// @author DZap
/// @notice Abstract contract for handling token input and output operations
/// @dev Provides gas-optimized functions for processing various token standards
abstract contract DZapTokenHandler is DZapVerification {
    // ============= INPUT TOKEN PROCESSING =============

    /// @notice Processes all input tokens for a zap operation
    /// @param _inputTokens Array of input token specifications
    /// @param _spender Address to approve/transfer tokens to
    /// @return hasErc1155AsInput Whether any ERC1155 tokens are being used as input
    function _processInputTokens(InputToken[] calldata _inputTokens, address _user, address _spender) internal returns (bool hasErc1155AsInput) {
        uint256 length = _inputTokens.length;

        for (uint256 i; i < length; ++i) {
            InputToken calldata inputToken = _inputTokens[i];

            if (inputToken.tokenType == TokenType.NATIVE) {
                _handleNativeInput(inputToken, _spender);
            } else if (inputToken.tokenType == TokenType.ERC20) {
                _handleErc20Input(inputToken, _spender);
            } else if (inputToken.tokenType == TokenType.ERC721) {
                _handleErc721Input(inputToken, _user, _spender);
            } else if (inputToken.tokenType == TokenType.ERC1155) {
                hasErc1155AsInput = true;
                _handleErc1155Input(inputToken, _user, _spender);
            }
        }
    }

    /// @notice Handles native token input operations
    /// @param _inputToken Input token specification
    /// @param _spender Address to transfer to
    function _handleNativeInput(InputToken calldata _inputToken, address _spender) private {
        if (_inputToken.transferType == InputTransferType.TransferToSpender) {
            LibAsset.transferNativeToken(_spender, _inputToken.amount);
        }
    }

    /// @notice Handles ERC20 token input operations
    /// @param _inputToken Input token specification
    /// @param _spender Address to approve/transfer to
    function _handleErc20Input(InputToken calldata _inputToken, address _spender) private {
        if (_inputToken.transferType == InputTransferType.ApproveForSpender) {
            LibAsset.maxApproveERC20(_inputToken.tokenAddress, _spender, _inputToken.amount);
        } else if (_inputToken.transferType == InputTransferType.TransferToSpender) {
            LibAsset.transferERC20(_inputToken.tokenAddress, _spender, _inputToken.amount);
        } else if (_inputToken.transferType == InputTransferType.ApproveForSpenderViaPermit2) {
            LibAsset.maxPermit2Approve(permit2, _inputToken.tokenAddress, _spender, _inputToken.amount);
        }
    }

    /// @notice Handles ERC721 token input operations
    /// @param _inputToken Input token specification
    /// @param _spender Address to approve/transfer to
    function _handleErc721Input(InputToken calldata _inputToken, address _user, address _spender) private {
        if (_inputToken.transferType == InputTransferType.ApproveForSpender) {
            address currentOwner = LibAsset.getOwnerOfERC721(_inputToken.tokenAddress, _inputToken.tokenId);
            if (currentOwner != address(this)) {
                LibAsset.transferERC721(_inputToken.tokenAddress, _user, address(this), _inputToken.tokenId);
            }
            LibAsset.approveERC721(_inputToken.tokenAddress, _spender, _inputToken.tokenId);
        } else if (_inputToken.transferType == InputTransferType.TransferToSpender) {
            LibAsset.transferERC721(_inputToken.tokenAddress, _spender, _inputToken.tokenId);
        } else if (_inputToken.transferType == InputTransferType.DirectTransferToSpender) {
            LibAsset.transferERC721(_inputToken.tokenAddress, _user, _spender, _inputToken.tokenId);
        }
    }

    /// @notice Handles ERC1155 token input operations
    /// @param _inputToken Input token specification
    /// @param _spender Address to approve/transfer to
    function _handleErc1155Input(InputToken calldata _inputToken, address _user, address _spender) private {
        require(_allowedErc1155Spender[_spender], Erc1155SpenderNotWhitelisted(_spender));

        if (_inputToken.transferType == InputTransferType.DirectTransferToSpender) {
            LibAsset.transferERC1155(_inputToken.tokenAddress, _user, _spender, _inputToken.tokenId, _inputToken.amount);
            return;
        }

        uint256 currentBalance = LibAsset.getBalanceOfERC1155(_inputToken.tokenAddress, address(this), _inputToken.tokenId);

        if (currentBalance < _inputToken.amount) {
            uint256 needed = _inputToken.amount - currentBalance;
            LibAsset.transferERC1155(_inputToken.tokenAddress, _user, address(this), _inputToken.tokenId, needed);
        }

        if (_inputToken.transferType == InputTransferType.ApproveForSpender) {
            if (!LibAsset.isErc1155ApprovedForAll(_inputToken.tokenAddress, address(this), _spender)) {
                LibAsset.approveERC1155(_inputToken.tokenAddress, _spender);
            }
        } else if (_inputToken.transferType == InputTransferType.TransferToSpender) {
            LibAsset.transferERC1155(_inputToken.tokenAddress, address(this), _spender, _inputToken.tokenId, _inputToken.amount);
        }
    }

    /// @notice Revokes ERC1155 approvals after zap execution
    /// @param _inputTokens Array of input tokens
    /// @param _spender Address to revoke approvals from
    function _revokeErc1155Approvals(InputToken[] calldata _inputTokens, address _spender) internal {
        uint256 length = _inputTokens.length;
        for (uint256 i; i < length; ++i) {
            InputToken calldata inputToken = _inputTokens[i];
            if (inputToken.tokenType == TokenType.ERC1155) {
                if (LibAsset.isErc1155ApprovedForAll(inputToken.tokenAddress, address(this), _spender)) {
                    LibAsset.revokeERC1155(inputToken.tokenAddress, _spender);
                }
            }
        }
    }

    // ============= OUTPUT TOKEN PROCESSING =============

    /// @notice Gets initial balances for output tokens before zap execution
    /// @param _outputTokens Array of output token specifications
    /// @param _nativeValueUsed Native value being used in the execution
    /// @return initialBalances Array of initial balances
    function _getOutputTokensInitialBalances(
        OutputToken[] calldata _outputTokens,
        uint256 _nativeValueUsed
    ) internal view returns (uint256[] memory initialBalances) {
        uint256 length = _outputTokens.length;
        initialBalances = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            OutputToken calldata outputToken = _outputTokens[i];

            if (outputToken.transferType == OutputTransferType.ReceiveInContract) {
                require(outputToken.recipient == address(this), InvalidRecipient());
            }

            address recipient = _getRecipient(outputToken);

            if (outputToken.tokenType == TokenType.ERC20) {
                initialBalances[i] = LibAsset.getErc20Balance(outputToken.tokenAddress, recipient);
            } else if (outputToken.tokenType == TokenType.NATIVE) {
                uint256 balance = recipient == address(this) ? LibAsset.selfNativeBalance() - _nativeValueUsed : LibAsset.getNativeBalance(recipient);
                initialBalances[i] = balance;
            } else if (outputToken.tokenType == TokenType.ERC1155) {
                initialBalances[i] = LibAsset.getBalanceOfERC1155(outputToken.tokenAddress, recipient, outputToken.tokenId);
            }
        }
    }

    /// @notice Processes all output tokens after zap execution
    /// @param _outputTokens Array of output token specifications
    /// @param _initialBalances Array of initial balances before execution
    function _processOutputTokens(OutputToken[] calldata _outputTokens, uint256[] memory _initialBalances) internal {
        uint256 length = _outputTokens.length;

        for (uint256 i; i < length; ++i) {
            TokenType tokenType = _outputTokens[i].tokenType;

            if (tokenType == TokenType.ERC20) {
                _handleERC20Output(_outputTokens[i], _initialBalances[i]);
            } else if (tokenType == TokenType.NATIVE) {
                _handleNativeOutput(_outputTokens[i], _initialBalances[i]);
            } else if (tokenType == TokenType.ERC721) {
                _handleERC721Output(_outputTokens[i]);
            } else if (tokenType == TokenType.ERC1155) {
                _handleERC1155Output(_outputTokens[i], _initialBalances[i]);
            }
        }
    }

    /// @notice Handles ERC20 output token validation and transfer
    /// @param _outputToken Output token specification
    /// @param _initialBalance Initial balance before execution
    function _handleERC20Output(OutputToken calldata _outputToken, uint256 _initialBalance) private {
        address recipient = _getRecipient(_outputToken);
        uint256 currentBalance = LibAsset.getBalance(_outputToken.tokenAddress, recipient);
        uint256 returnAmount = currentBalance - _initialBalance;

        require(returnAmount >= _outputToken.minReturn, InvalidReturnAmount(returnAmount, _outputToken.minReturn));

        if (_outputToken.transferType == OutputTransferType.ReceiveAndTransfer) {
            require(_outputToken.feeAmount <= returnAmount, FeeExceedsReturnAmount(returnAmount, _outputToken.feeAmount));
            uint256 transferAmount = returnAmount - _outputToken.feeAmount;
            LibAsset.transferERC20(_outputToken.tokenAddress, _outputToken.recipient, transferAmount);
        }
    }

    /// @notice Handles native token output validation and transfer
    /// @param _outputToken Output token specification
    /// @param _initialBalance Initial balance before execution
    function _handleNativeOutput(OutputToken calldata _outputToken, uint256 _initialBalance) private {
        address recipient = _getRecipient(_outputToken);
        uint256 currentBalance = LibAsset.getBalance(_outputToken.tokenAddress, recipient);
        uint256 returnAmount = currentBalance - _initialBalance;

        require(returnAmount >= _outputToken.minReturn, InvalidReturnAmount(returnAmount, _outputToken.minReturn));

        if (_outputToken.transferType == OutputTransferType.ReceiveAndTransfer) {
            uint256 transferAmount = returnAmount - _outputToken.feeAmount;
            LibAsset.transferNativeToken(_outputToken.recipient, transferAmount);
        }
    }

    /// @notice Handles ERC721 output validation and transfer
    /// @param _outputToken Output token specification
    function _handleERC721Output(OutputToken calldata _outputToken) private {
        address recipient = _getRecipient(_outputToken);
        address tokenOwner = LibAsset.getOwnerOfERC721(_outputToken.tokenAddress, _outputToken.tokenId);

        require(recipient == tokenOwner, InvalidTokenOwner(_outputToken.tokenId));

        if (_outputToken.transferType == OutputTransferType.ReceiveAndTransfer) {
            LibAsset.transferERC721(_outputToken.tokenAddress, _outputToken.recipient, _outputToken.tokenId);
        }
    }

    /// @notice Handles ERC1155 output validation and transfer
    /// @param _outputToken Output token specification
    /// @param _initialBalance Initial balance before execution
    function _handleERC1155Output(OutputToken calldata _outputToken, uint256 _initialBalance) private {
        address recipient = _getRecipient(_outputToken);
        uint256 currentBalance = LibAsset.getBalanceOfERC1155(_outputToken.tokenAddress, recipient, _outputToken.tokenId);
        uint256 returnAmount = currentBalance - _initialBalance;

        require(returnAmount >= _outputToken.minReturn, InvalidReturnAmount(returnAmount, _outputToken.minReturn));

        if (_outputToken.transferType == OutputTransferType.ReceiveAndTransfer) {
            LibAsset.transferERC1155(_outputToken.tokenAddress, address(this), _outputToken.recipient, _outputToken.tokenId, returnAmount);
        }
    }

    /// @notice Determines the actual recipient address for output tokens
    /// @param _outputToken Output token specification
    /// @return recipient The actual recipient address
    function _getRecipient(OutputToken calldata _outputToken) private view returns (address recipient) {
        recipient = _outputToken.transferType == OutputTransferType.ReceiveAndTransfer ? address(this) : _outputToken.recipient;
    }

    // ============= FEE AND SWEEP FUNCTIONS =============

    /// @notice Processes fee payments to integrator and protocol
    /// @param _feeConfig Fee configuration
    function _processFee(FeeConfig calldata _feeConfig) internal {
        uint256 length = _feeConfig.fees.length;

        for (uint256 i; i < length; ++i) {
            LibAsset.transferToken(_feeConfig.fees[i].token, _feeConfig.integrator, _feeConfig.fees[i].integratorFeeAmount);
            LibAsset.transferToken(_feeConfig.fees[i].token, protocolFeeVault, _feeConfig.fees[i].protocolFeeAmount);
        }
    }

    /// @notice Transfers executor fees to the transaction executor
    /// @param _executorFeeInfo Array of executor fee specifications
    function _transferExecutorFees(TokenInfo[] calldata _executorFeeInfo) internal {
        uint256 length = _executorFeeInfo.length;

        for (uint256 i; i < length; ++i) {
            LibAsset.transferERC20WithoutChecks(_executorFeeInfo[i].token, msg.sender, _executorFeeInfo[i].amount);
        }
    }

    /// @notice Sweeps remaining tokens to dust receiver
    /// @param _sweepTokens Array of token addresses to sweep
    /// @param _dustReceiver Address to receive swept tokens
    function _handleSweepTokens(address[] calldata _sweepTokens, address _dustReceiver) internal {
        uint256 length = _sweepTokens.length;

        for (uint256 i; i < length; ++i) {
            uint256 balance = LibAsset.getBalance(_sweepTokens[i], address(this));

            if (balance > 0) {
                LibAsset.transferERC20WithoutChecks(_sweepTokens[i], _dustReceiver, balance);
            }
        }
    }
}



// ============================================================
// FILE: contracts/zap/DZapVerification.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { DZapAdmin } from "./DZapAdmin.sol";
import { UnauthorizedSigner, SigDeadlineExpired } from "./Errors.sol";

/// @title DZapVerification
/// @author DZap
/// @notice Abstract contract handling all signature verification logic
/// @dev Implements EIP-712 signature verification for zap operations
abstract contract DZapVerification is DZapAdmin {
    // ============= INTERNAL VERIFICATION FUNCTIONS =============

    /// @notice Verifies EIP-712 signature against expected signer
    /// @param _verifier Expected signer address
    /// @param _msgHash Message hash to verify
    /// @param _signature Signature to verify
    function _verifySignature(address _verifier, bytes32 _msgHash, bytes calldata _signature) internal view {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _DOMAIN_SEPARATOR, _msgHash));
        require(ECDSA.recover(digest, _signature) == _verifier, UnauthorizedSigner());
    }

    /// @notice Handles zap verification with signature validation
    /// @param _transactionId Unique transaction identifier
    /// @param _zapDataHash Hash of zap execution data
    /// @param _feeDataHash Hash of fee configuration
    /// @param _user User address for nonce tracking
    /// @param _deadline Signature expiration timestamp
    /// @param _signature Verifier signature
    function _handleZapVerification(
        bytes32 _transactionId,
        bytes32 _zapDataHash,
        bytes32 _feeDataHash,
        address _user,
        uint256 _deadline,
        bytes calldata _signature
    ) internal {
        require(_deadline >= block.timestamp, SigDeadlineExpired());

        bytes32 msgHash = keccak256(
            abi.encode(_SIGNED_ZAP_DATA_TYPEHASH, _transactionId, _user, nonce[_user], _deadline, _zapDataHash, _feeDataHash)
        );

        _verifySignature(zapVerifier, msgHash, _signature);

        unchecked {
            ++nonce[_user];
        }
    }

    /// @notice Handles gasless verification with user intent signature
    /// @param _transactionId Unique transaction identifier
    /// @param _zapDataHash Hash of zap execution data
    /// @param _feeDataHash Hash of fee configuration
    /// @param _executorFeeDataHash Hash of executor fee data
    /// @param _crosschainDataHash Hash of crosschain data
    /// @param _sweepDustHash Hash of sweep dust data
    /// @param _user User address for nonce tracking
    /// @param _dustReceiver Address to receive leftover tokens
    /// @param _deadline Signature expiration timestamp
    /// @param _userIntentSignature User's intent signature
    function _handleGaslessVerification(
        bytes32 _transactionId,
        bytes32 _zapDataHash,
        bytes32 _feeDataHash,
        bytes32 _executorFeeDataHash,
        bytes32 _crosschainDataHash,
        bytes32 _sweepDustHash,
        address _user,
        address _dustReceiver,
        uint256 _deadline,
        bytes calldata _userIntentSignature
    ) internal {
        require(_deadline >= block.timestamp, SigDeadlineExpired());

        bytes32 msgHash = keccak256(
            abi.encode(
                _SIGNED_GASLESS_DATA_TYPEHASH,
                _transactionId,
                _user,
                _dustReceiver,
                nonce[_user],
                _deadline,
                _zapDataHash,
                _feeDataHash,
                _executorFeeDataHash,
                _crosschainDataHash,
                _sweepDustHash
            )
        );

        _verifySignature(_user, msgHash, _userIntentSignature);

        unchecked {
            ++nonce[_user];
        }
    }

    /// @notice Creates witness hash for gasless batch permit2 operations
    /// @param _transactionId Unique transaction identifier
    /// @param _user User address
    /// @param _dustReceiver Address to receive leftover tokens
    /// @param _userNonce Current user nonce
    /// @param _deadline Signature expiration timestamp
    /// @param _zapDataHash Hash of zap execution data
    /// @param _feeDataHash Hash of fee configuration
    /// @param _executorFeeDataHash Hash of executor fee data
    /// @param _crosschainDataHash Hash of crosschain data
    /// @param _sweepDustHash Hash of sweep dust data
    /// @return witness Computed witness hash for permit2
    function _createGaslessWitness(
        bytes32 _transactionId,
        address _user,
        address _dustReceiver,
        uint256 _userNonce,
        uint256 _deadline,
        bytes32 _zapDataHash,
        bytes32 _feeDataHash,
        bytes32 _executorFeeDataHash,
        bytes32 _crosschainDataHash,
        bytes32 _sweepDustHash
    ) internal pure returns (bytes32 witness) {
        witness = keccak256(
            abi.encode(
                _GASLESS_WITNESS_TYPEHASH,
                _transactionId,
                _user,
                _dustReceiver,
                _userNonce,
                _deadline,
                _zapDataHash,
                _feeDataHash,
                _executorFeeDataHash,
                _crosschainDataHash,
                _sweepDustHash
            )
        );
    }
}



// ============================================================
// FILE: contracts/zap/DZapZapCore.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { LibAsset } from "../shared/libraries/LibAsset.sol";
import { LibPermit } from "../shared/libraries/LibPermit.sol";

import { IDZapZapCore } from "../interfaces/IDZapZapCore.sol";
import { PermitBatchTransferFrom } from "../interfaces/IPermit2.sol";

import { DZapCoreBase } from "./DZapCoreBase.sol";
import { DZapExecution } from "./DZapExecution.sol";

import { FeeConfig, ZapData, InputErc20Tokens, TokenInfo } from "./Types.sol";
import { DustReceiverIsZeroAddress, IntegratorIsZeroAddress } from "./Errors.sol";

/*  
---------------------------------------------------------
---------------------------------------------------------

 /$$$$$$$  /$$$$$$$$  /$$$$$$  /$$$$$$$ 
| $$__  $$|_____ $$  /$$__  $$| $$__  $$
| $$  \ $$     /$$/ | $$  \ $$| $$  \ $$
| $$  | $$    /$$/  | $$$$$$$$| $$$$$$$/
| $$  | $$   /$$/   | $$__  $$| $$____/ 
| $$  | $$  /$$/    | $$  | $$| $$      
| $$$$$$$/ /$$$$$$$$| $$  | $$| $$      
|_______/ |________/|__/  |__/|__/       


Author: DZap <https://dzap.io> (https://x.com/dzap_io)

---------------------------------------------------------
---------------------------------------------------------
*/

/// @title DZapZapCore
/// @notice Main contract for executing zap transactions across protocols
/// @dev Inherits from modular abstract contracts for clean separation of concerns
contract DZapZapCore is ReentrancyGuard, DZapExecution, IDZapZapCore {
    // ============= CONSTRUCTOR =============

    /// @param _owner Owner of the contract
    /// @param _protocolFeeVault Address where protocol fees are sent
    /// @param _zapVerifier Address of the zap verifier
    /// @param _permit2 Address of the permit2 contract
    /// @param _uniswapPermit2 Address of the uniswap permit2 contract
    /// @param _uniswapPermit2BytecodeHash Hash of the uniswap permit2 bytecode
    /// @param _salt Random salt for contract creation
    constructor(
        address _owner,
        address _protocolFeeVault,
        address _zapVerifier,
        address _permit2,
        address _uniswapPermit2,
        bytes32 _uniswapPermit2BytecodeHash,
        bytes32 _salt
    ) DZapCoreBase(_owner, _protocolFeeVault, _zapVerifier, _permit2, _uniswapPermit2, _uniswapPermit2BytecodeHash, _salt) {}

    // ============= EXTERNAL FUNCTIONS =============

    /// @inheritdoc IDZapZapCore
    function zap(
        bytes32 _transactionId,
        bytes calldata _crosschainData,
        bytes calldata _zapVerificationSignature,
        uint256 _deadline,
        address _dustReceiver,
        InputErc20Tokens[] calldata _inputTokens,
        FeeConfig calldata _feeConfig,
        ZapData[] calldata _zapData,
        address[] calldata _sweepDust
    ) external payable nonReentrant whenNotPaused refundExcessNative(_dustReceiver) {
        require(_dustReceiver != address(0), DustReceiverIsZeroAddress());
        require(_feeConfig.integrator != address(0), IntegratorIsZeroAddress());

        bytes32 zapDataHash = keccak256(abi.encode(_zapData));
        bytes32 feeDataHash = keccak256(abi.encode(_feeConfig));

        _handleZapVerification(_transactionId, zapDataHash, feeDataHash, msg.sender, _deadline, _zapVerificationSignature);

        LibAsset.depositBatch(permit2, msg.sender, _inputTokens);

        _handleZap(_zapData, msg.sender);

        _processFee(_feeConfig);

        _handleSweepTokens(_sweepDust, _dustReceiver);

        emit Zapped(_transactionId, msg.sender, _feeConfig.integrator, _crosschainData);
    }

    /// @inheritdoc IDZapZapCore
    function zapWithBatchDeposit(
        bytes32 _transactionId,
        bytes calldata _crosschainData,
        bytes calldata _zapVerificationSignature,
        bytes calldata _batchDepositSignature,
        uint256 _deadline,
        address _dustReceiver,
        PermitBatchTransferFrom calldata _tokenDepositDetails,
        FeeConfig calldata _feeConfig,
        ZapData[] calldata _zapData,
        address[] calldata _sweepDust
    ) external payable nonReentrant whenNotPaused refundExcessNative(_dustReceiver) {
        require(_dustReceiver != address(0), DustReceiverIsZeroAddress());
        require(_feeConfig.integrator != address(0), IntegratorIsZeroAddress());

        bytes32 zapDataHash = keccak256(abi.encode(_zapData));
        bytes32 feeDataHash = keccak256(abi.encode(_feeConfig));

        _handleZapVerification(_transactionId, zapDataHash, feeDataHash, msg.sender, _deadline, _zapVerificationSignature);

        LibAsset.depositBatch(permit2, msg.sender, _tokenDepositDetails, _batchDepositSignature);

        _handleZap(_zapData, msg.sender);

        _processFee(_feeConfig);

        _handleSweepTokens(_sweepDust, _dustReceiver);

        emit Zapped(_transactionId, msg.sender, _feeConfig.integrator, _crosschainData);
    }

    /// @inheritdoc IDZapZapCore
    function executeZap(
        bytes32 _transactionId,
        bytes calldata _crosschainData,
        bytes calldata _zapVerificationSignature,
        bytes calldata _userIntentSignature,
        uint256 _zapDeadline,
        uint256 _userIntentDeadline,
        address _user,
        address _dustReceiver,
        InputErc20Tokens[] calldata _inputTokens,
        FeeConfig calldata _feeConfig,
        TokenInfo[] calldata _executorFeeInfo,
        ZapData[] calldata _zapData,
        address[] calldata _sweepDust
    ) external payable nonReentrant whenNotPaused refundExcessNative(_dustReceiver) {
        require(_dustReceiver != address(0), DustReceiverIsZeroAddress());
        require(_feeConfig.integrator != address(0), IntegratorIsZeroAddress());

        bytes32 zapDataHash = keccak256(abi.encode(_zapData));
        bytes32 feeDataHash = keccak256(abi.encode(_feeConfig));

        _handleZapVerification(_transactionId, zapDataHash, feeDataHash, _user, _zapDeadline, _zapVerificationSignature);

        _handleGaslessVerification(
            _transactionId,
            zapDataHash,
            feeDataHash,
            keccak256(abi.encode(_executorFeeInfo)),
            keccak256(_crosschainData),
            keccak256(abi.encode(_sweepDust)),
            _user,
            _dustReceiver,
            _userIntentDeadline,
            _userIntentSignature
        );

        LibAsset.depositBatch(permit2, _user, _inputTokens);

        _handleZap(_zapData, _user);

        _processFee(_feeConfig);

        _transferExecutorFees(_executorFeeInfo);

        _handleSweepTokens(_sweepDust, _dustReceiver);

        emit GaslessZapped(_transactionId, msg.sender, _user, _feeConfig.integrator, _crosschainData);
    }

    /// @inheritdoc IDZapZapCore
    function executeZapWithWitness(
        bytes32 _transactionId,
        bytes calldata _crosschainData,
        bytes calldata _zapVerificationSignature,
        bytes calldata _userIntentSignature,
        uint256 _zapDeadline,
        address _user,
        address _dustReceiver,
        PermitBatchTransferFrom calldata _tokenDepositDetails,
        FeeConfig calldata _feeConfig,
        TokenInfo[] calldata _executorFeeInfo,
        ZapData[] calldata _zapData,
        address[] calldata _sweepDust
    ) external payable nonReentrant whenNotPaused refundExcessNative(_dustReceiver) {
        require(_dustReceiver != address(0), DustReceiverIsZeroAddress());
        require(_feeConfig.integrator != address(0), IntegratorIsZeroAddress());

        bytes32 zapDataHash = keccak256(abi.encode(_zapData));
        bytes32 feeDataHash = keccak256(abi.encode(_feeConfig));

        _handleZapVerification(_transactionId, zapDataHash, feeDataHash, _user, _zapDeadline, _zapVerificationSignature);

        bytes32 witness = keccak256(
            abi.encode(
                _GASLESS_WITNESS_TYPEHASH,
                _transactionId,
                _user,
                _dustReceiver,
                zapDataHash,
                feeDataHash,
                keccak256(abi.encode(_executorFeeInfo)),
                keccak256(_crosschainData),
                keccak256(abi.encode(_sweepDust))
            )
        );

        LibPermit.permit2BatchWitnessTransferFrom(
            permit2,
            _user,
            address(this),
            witness,
            _tokenDepositDetails,
            _userIntentSignature,
            _GASLESS_WITNESS_TYPE_STRING
        );

        _handleZap(_zapData, _user);

        _processFee(_feeConfig);

        _transferExecutorFees(_executorFeeInfo);

        _handleSweepTokens(_sweepDust, _dustReceiver);

        emit GaslessZapped(_transactionId, msg.sender, _user, _feeConfig.integrator, _crosschainData);
    }
}



// ============================================================
// FILE: contracts/zap/Errors.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ============= ZAP ERRORS =============

error CallerIsNotOwnerOrAdmin();

error ZeroAddress();
error NoTransferToNullAddress();
error DustReceiverIsZeroAddress();
error IntegratorIsZeroAddress();

error UnauthorizedSigner();
error SigDeadlineExpired();

error InvalidRecipient();
error InvalidTokenOwner(uint256);
error InvalidReturnAmount(uint256 returnAmount, uint256 minReturn);
error FeeExceedsReturnAmount(uint256 returnAmount, uint256 feeAmount);

error InvalidProtocolFeeVault();

error UniswapPermit2AlreadySet();
error UniswapPermit2ByteCodeMismatch();

error UnauthorizedCall(address callTo);
error ZapExecutionFailed(address target, bytes4 funSig, bytes reason);
error SelectorNotAllowed(address target, bytes4 selector);
error Erc1155SpenderNotWhitelisted(address spender);
error ProtectedSelector(bytes4 selector);



// ============================================================
// FILE: contracts/zap/Types.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Types
/// @notice Contains type definitions

enum PermitType {
    PERMIT, // EIP2612
    PERMIT2_APPROVE,
    PERMIT2_WITNESS_TRANSFER,
    BATCH_PERMIT2_WITNESS_TRANSFER
}

enum TokenType {
    UNDEFINED,
    NATIVE,
    ERC20,
    ERC721,
    ERC1155
}

enum InputTransferType {
    None,
    ApproveForSpender,
    TransferToSpender,
    DirectTransferToSpender,
    ApproveForSpenderViaPermit2
}

enum OutputTransferType {
    ReceiveInContract,
    ReceiveAndTransfer,
    DirectTransferToRecipient
}

struct InputToken {
    TokenType tokenType;
    InputTransferType transferType;
    address tokenAddress;
    uint256 amount;
    uint256 tokenId;
}

struct OutputToken {
    TokenType tokenType;
    OutputTransferType transferType;
    address tokenAddress;
    address recipient;
    uint96 feeAmount;
    uint256 minReturn;
    uint256 tokenId;
}

/// @dev Core zap execution data structure
struct ZapData {
    address callTo; // Address to call for zap execution
    address approveTo; // Address to approve tokens to
    bytes callData; // Encoded function call data
    bool isDelegateCall; // Whether to use delegatecall
    uint256 nativeValue; // Native token value to send
    InputToken[] inputTokens; // Input token specifications
    OutputToken[] outputTokens; // Output token specifications
}

/// @dev ERC20 token input with permit data
struct InputErc20Tokens {
    address token; // Token contract address
    uint256 amount; // Amount to transfer
    bytes permit; // Permit signature data
}

/// @dev Simple token amount pair
struct TokenInfo {
    address token; // Token contract address
    uint256 amount; // Token amount
}

/// @dev Fee distribution data
struct Fees {
    address token; // Fee token address
    uint256 integratorFeeAmount; // Fee amount for integrator
    uint256 protocolFeeAmount; // Fee amount for protocol
}

/// @dev Fee configuration for a transaction
struct FeeConfig {
    address integrator; // Integrator address to receive fees
    Fees[] fees; // Array of fee distributions
}
