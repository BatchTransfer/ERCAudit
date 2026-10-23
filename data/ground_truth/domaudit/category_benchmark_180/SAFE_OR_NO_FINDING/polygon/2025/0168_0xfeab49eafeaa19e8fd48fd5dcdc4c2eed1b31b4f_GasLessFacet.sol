// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xfeab49eafeaa19e8fd48fd5dcdc4c2eed1b31b4f
// Contract Name: GasLessFacet



// ============================================================
// FILE: @openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol
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
// FILE: @openzeppelin/contracts/token/ERC20/IERC20.sol
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
// FILE: @openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol
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
// FILE: @openzeppelin/contracts/utils/Address.sol
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
// FILE: @openzeppelin/contracts/utils/cryptography/ECDSA.sol
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
// FILE: @openzeppelin/contracts/utils/math/Math.sol
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
// FILE: @openzeppelin/contracts/utils/math/SignedMath.sol
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



// ============================================================
// FILE: @openzeppelin/contracts/utils/Strings.sol
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
// FILE: contracts/Shared/Errors.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// DZap Common Errors

error OnlyContractOwner();
error UnauthorizedCaller();
error UnAuthorized();
error CannotAuthorizeSelf();

error AlreadyInitialized();

error InsufficientBalance(uint256 amount, uint256 contractBalance);
error SlippageTooHigh(uint256 minAmount, uint256 returnAmount);
error AmountExceedsMaximum();

error TransferAmountMismatch();
error NoBridgeFromZeroAmount();
error NoSwapFromZeroAmount();

error ZeroAddress();
error NoTransferToNullAddress();
error NullAddrIsNotAValidSpender();
error NullAddrIsNotAValidRecipient();
error NativeTokenNotSupported();
error InvalidEncodedAddress();

error NotAContract();
error BridgeNotWhitelisted(address bridge);
error AdapterNotWhitelisted(address adapter);
error DexNotWhitelisted(address dex);

error InvalidPermitType();
error CannotBridgeToSameNetwork();

error SwapCallFailed(address target, bytes4 funSig, bytes reason);
error BridgeCallFailed(address target, bytes4 funSig, bytes reason);
error AdapterCallFailed(address adapter, bytes res);
error NativeCallFailed(bytes reason);
error Erc20CallFailed(bytes reason);
error NativeTransferFailed();



// ============================================================
// FILE: contracts/Shared/Facets/GasLessFacet.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LibAsset } from "../Libraries/LibAsset.sol";
import { LibPermit } from "../Libraries/LibPermit.sol";
import { LibValidator } from "../Libraries/LibValidator.sol";
import { LibBridge } from "../Libraries/LibBridge.sol";

import { PermitBatchTransferFrom } from "../Interfaces/IPermit2.sol";
import { IBridge } from "../Interfaces/IBridge.sol";
import { IGasLessFacet } from "../Interfaces/IGasLessFacet.sol";

import { Swapper } from "../Helpers/Swapper.sol";
import { RefundNative } from "../Helpers/RefundNative.sol";
import { Pausable } from "../Helpers/Pausable.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";

import { SwapData, BridgeSwapData, SwapExecutionData, TokenInfo, InputToken, AdapterInfo } from "../Types.sol";

/**
 * @title GasLessFacet
 * @author DZap
 * @dev This contract enables meta-transactions for swaps and bridges, allowing users to interact with DeFi
 *      protocols without holding native tokens for gas fees. Executors are compensated through fees.
 *
 *      Key Features:
 *      - Gasless swaps (single and multi-token)
 *      - Gasless bridges (single and multi-token)
 *      - Support for Permit2 batch transfers
 *      - Intent-based execution with signature verification
 *      - Executor fee compensation mechanism
 */
contract GasLessFacet is IBridge, IGasLessFacet, Swapper, RefundNative, Pausable, ReentrancyGuard {
    /* ========= STORAGE ========= */

    string internal constant _SWAP_WITNESS_TYPE_STRING =
        "DZapSwapWitness witness)DZapSwapWitness(bytes32 txId,address user,bytes32 executorFeesHash,bytes32 swapDataHash)TokenPermissions(address token,uint256 amount)";
    string internal constant _BRIDGE_WITNESS_TYPE_STRING =
        "DZapBridgeWitness witness)DZapBridgeWitness(bytes32 txId,address user,bytes32 executorFeesHash,bytes32 swapDataHash,bytes32 adapterDataHash)TokenPermissions(address token,uint256 amount)";

    bytes32 internal constant _SWAP_WITNESS_TYPEHASH =
        keccak256("DZapSwapWitness(bytes32 txId,address user,bytes32 executorFeesHash,bytes32 swapDataHash)");
    bytes32 internal constant _BRIDGE_WITNESS_TYPEHASH =
        keccak256("DZapBridgeWitness(bytes32 txId,address user,bytes32 executorFeesHash,bytes32 swapDataHash,bytes32 adapterDataHash)");

    /* ========= EXTERNAL ========= */

    /// @inheritdoc IGasLessFacet
    function executeSwap(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        uint256 _userIntentDeadline,
        bytes calldata _userIntentSignature,
        bytes calldata _tokenApprovalData,
        TokenInfo calldata _executorFeeInfo,
        SwapData calldata _swapData,
        SwapExecutionData calldata _swapExecutionData
    ) external whenNotPaused nonReentrant {
        LibValidator.handleGasLessSwapVerification(
            _user,
            _userIntentDeadline,
            _transactionId,
            keccak256(abi.encode(_executorFeeInfo)),
            keccak256(abi.encode(_swapData)),
            _userIntentSignature
        );

        LibAsset.deposit(_user, _swapData.from, _swapData.fromAmount + _executorFeeInfo.amount, _tokenApprovalData);

        if (_executorFeeInfo.token != address(0)) LibAsset.transferERC20WithoutChecks(_executorFeeInfo.token, msg.sender, _executorFeeInfo.amount);

        _executeSwap(_transactionId, _user, _integrator, _swapData, _swapExecutionData, false);

        emit DZapGasLessStarted(_transactionId, msg.sender, _user);
    }

    /// @inheritdoc IGasLessFacet
    function executeMultiSwap(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        uint256 _userIntentDeadline,
        bytes calldata _userIntentSignature,
        InputToken[] calldata _inputTokens,
        TokenInfo[] calldata _executorFeeInfo,
        SwapData[] calldata _swapData,
        SwapExecutionData[] calldata _swapExecutionData
    ) external whenNotPaused nonReentrant {
        LibValidator.handleGasLessSwapVerification(
            _user,
            _userIntentDeadline,
            _transactionId,
            keccak256(abi.encode(_executorFeeInfo)),
            keccak256(abi.encode(_swapData)),
            _userIntentSignature
        );

        LibAsset.depositBatch(_user, _inputTokens);

        _transferExecutorFees(_executorFeeInfo);

        _executeSwaps(_transactionId, _user, _integrator, _swapData, _swapExecutionData, false);

        emit DZapGasLessStarted(_transactionId, msg.sender, _user);
    }

    /// @inheritdoc IGasLessFacet
    function executeMultiSwapWithWitness(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        bytes calldata _userIntentSignature,
        PermitBatchTransferFrom calldata _tokenDepositDetails,
        TokenInfo[] calldata _executorFeeInfo,
        SwapData[] calldata _swapData,
        SwapExecutionData[] calldata _swapExecutionData
    ) external whenNotPaused nonReentrant {
        bytes32 witness = _createSwapWitnessHash(_transactionId, _user, _executorFeeInfo, _swapData);

        LibPermit.permit2BatchWitnessTransferFrom(
            _user,
            address(this),
            witness,
            _tokenDepositDetails,
            _userIntentSignature,
            _SWAP_WITNESS_TYPE_STRING
        );

        _transferExecutorFees(_executorFeeInfo);

        _executeSwaps(_transactionId, _user, _integrator, _swapData, _swapExecutionData, false);

        emit DZapGasLessStarted(_transactionId, msg.sender, _user);
    }

    /// @inheritdoc IGasLessFacet
    function executeBridge(
        bytes32 _transactionId,
        bytes calldata _bridgeFeeData,
        bytes calldata _userIntentSignature,
        bytes calldata _feeVerificationSignature,
        uint256 _userIntentDeadline,
        uint256 _bridgeFeeDeadline,
        address _user,
        InputToken calldata _inputToken,
        TokenInfo calldata _executorFeeInfo,
        AdapterInfo calldata _adapterInfo
    ) external payable refundExcessNative(msg.sender) whenNotPaused nonReentrant {
        bytes32 adapterInfoHash = keccak256(abi.encode(_adapterInfo));

        LibValidator.handleGasLessBridgeVerification(
            _user,
            _userIntentDeadline,
            _transactionId,
            keccak256(abi.encode(_executorFeeInfo)),
            adapterInfoHash,
            _userIntentSignature
        );

        LibValidator.handleFeeVerification(
            _user,
            _bridgeFeeDeadline,
            _transactionId,
            keccak256(_bridgeFeeData),
            adapterInfoHash,
            _feeVerificationSignature
        );

        LibAsset.deposit(_user, _inputToken.token, _inputToken.amount, _inputToken.permit);

        if (_executorFeeInfo.token != address(0)) LibAsset.transferERC20WithoutChecks(_executorFeeInfo.token, msg.sender, _executorFeeInfo.amount);

        address integrator = LibBridge.takeFee(_bridgeFeeData);

        LibBridge.bridge(_adapterInfo);

        emit DZapBridgeStarted(_transactionId, _user, integrator);
        emit DZapGasLessStarted(_transactionId, msg.sender, _user);
    }

    /// @inheritdoc IGasLessFacet
    function executeMultiBridge(
        bytes32 _transactionId,
        bytes calldata _bridgeFeeData,
        bytes calldata _userIntentSignature,
        bytes calldata _feeVerificationSignature,
        uint256 _userIntentDeadline,
        uint256 _bridgeFeeDeadline,
        address _user,
        InputToken[] calldata _inputTokens,
        TokenInfo[] calldata _executorFeeInfo,
        BridgeSwapData[] calldata _swapData,
        SwapExecutionData[] calldata _swapExecutionData,
        AdapterInfo[] calldata _adapterInfo
    ) external payable refundExcessNative(msg.sender) whenNotPaused nonReentrant {
        bytes32 adapterInfoHash = keccak256(abi.encode(_adapterInfo));

        LibValidator.handleGasLessSwapBridgeVerification(
            _user,
            _userIntentDeadline,
            _transactionId,
            keccak256(abi.encode(_executorFeeInfo)),
            keccak256(abi.encode(_swapData)),
            adapterInfoHash,
            _userIntentSignature
        );

        LibValidator.handleFeeVerification(
            _user,
            _bridgeFeeDeadline,
            _transactionId,
            keccak256(_bridgeFeeData),
            adapterInfoHash,
            _feeVerificationSignature
        );

        LibAsset.depositBatch(_user, _inputTokens);

        _transferExecutorFees(_executorFeeInfo);

        address integrator = LibBridge.takeFee(_bridgeFeeData);

        _executeBridgeSwaps(_transactionId, _user, integrator, _swapData, _swapExecutionData, false);

        LibBridge.bridge(_adapterInfo);

        emit DZapBridgeStarted(_transactionId, _user, integrator);
        emit DZapGasLessStarted(_transactionId, msg.sender, _user);
    }

    /// @inheritdoc IGasLessFacet
    function executeMultiBridgeWithWitness(
        bytes32 _transactionId,
        bytes calldata _bridgeFeeData,
        bytes calldata _userIntentSignature,
        bytes calldata _feeVerificationSignature,
        uint256 _bridgeFeeDeadline,
        address _user,
        PermitBatchTransferFrom calldata _tokenDepositDetails,
        TokenInfo[] calldata _executorFeeInfo,
        BridgeSwapData[] calldata _swapData,
        SwapExecutionData[] calldata _swapExecutionData,
        AdapterInfo[] calldata _adapterInfo
    ) external payable refundExcessNative(msg.sender) whenNotPaused nonReentrant {
        bytes32 adapterInfoHash = keccak256(abi.encode(_adapterInfo));
        bytes32 witness = _createBridgeWitnessHash(_user, _transactionId, _executorFeeInfo, _swapData, adapterInfoHash);

        LibPermit.permit2BatchWitnessTransferFrom(
            _user,
            address(this),
            witness,
            _tokenDepositDetails,
            _userIntentSignature,
            _BRIDGE_WITNESS_TYPE_STRING
        );

        address integrator = LibBridge.verifyAndTakeFee(
            _user,
            _bridgeFeeDeadline,
            _transactionId,
            adapterInfoHash,
            _bridgeFeeData,
            _feeVerificationSignature
        );

        _transferExecutorFees(_executorFeeInfo);

        _executeBridgeSwaps(_transactionId, _user, integrator, _swapData, _swapExecutionData, false);

        LibBridge.bridge(_adapterInfo);

        emit DZapBridgeStarted(_transactionId, _user, integrator);
        emit DZapGasLessStarted(_transactionId, msg.sender, _user);
    }

    /* ========= INTERNAL ========= */

    function _transferExecutorFees(TokenInfo[] calldata _executorFeeInfo) internal {
        for (uint256 i = 0; i < _executorFeeInfo.length; ) {
            LibAsset.transferERC20WithoutChecks(_executorFeeInfo[i].token, msg.sender, _executorFeeInfo[i].amount);
            unchecked {
                ++i;
            }
        }
    }

    function _createSwapWitnessHash(
        bytes32 _transactionId,
        address _user,
        TokenInfo[] calldata _executorFeeInfo,
        SwapData[] calldata _swapData
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(_SWAP_WITNESS_TYPEHASH, _transactionId, _user, keccak256(abi.encode(_executorFeeInfo)), keccak256(abi.encode(_swapData)))
            );
    }

    function _createBridgeWitnessHash(
        address _user,
        bytes32 _transactionIdHash,
        TokenInfo[] calldata _executorFeeInfo,
        BridgeSwapData[] calldata _swapData,
        bytes32 _adapterInfoHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _BRIDGE_WITNESS_TYPEHASH,
                    _transactionIdHash,
                    _user,
                    keccak256(abi.encode(_executorFeeInfo)),
                    keccak256(abi.encode(_swapData)),
                    _adapterInfoHash
                )
            );
    }
}



// ============================================================
// FILE: contracts/Shared/Helpers/Pausable.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LibGlobalStorage } from "../Libraries/LibGlobalStorage.sol";

/**
 * @title Pausable
 * @author DZap
 * @notice Abstract contract that restricts function execution based on a global pause state.
 * @dev Intended for use with a global storage library (LibGlobalStorage) that manages the pause flag.
 */
abstract contract Pausable {
    /* ========= Errors ========= */

    error ContractIsPaused();
    error ContractIsNotPaused();

    /* ========= Modifiers ========= */

    modifier whenNotPaused() {
        if (LibGlobalStorage.getPaused()) revert ContractIsPaused();
        _;
    }

    modifier whenPaused() {
        if (!LibGlobalStorage.getPaused()) revert ContractIsNotPaused();
        _;
    }
}



// ============================================================
// FILE: contracts/Shared/Helpers/ReentrancyGuard.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title ReentrancyGuard
 * @author DZap
 * @notice Abstract contract to provide protection against reentrancy
 */
abstract contract ReentrancyGuard {
    /* ========= Storage ========= */

    bytes32 private constant NAMESPACE = keccak256("dzap.reentrancyguard");

    /* ========= Types ========= */

    struct ReentrancyStorage {
        uint256 status;
    }

    /* ========= Errors ========= */

    error ReentrancyError();

    /* ========= Constants ========= */

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    /* ========= Modifiers ========= */

    modifier nonReentrant() {
        ReentrancyStorage storage s = reentrancyStorage();
        if (s.status == _ENTERED) revert ReentrancyError();
        s.status = _ENTERED;
        _;
        s.status = _NOT_ENTERED;
    }

    /* ========= Private Methods ========= */

    /// @dev fetch local storage
    function reentrancyStorage() private pure returns (ReentrancyStorage storage data) {
        bytes32 position = NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            data.slot := position
        }
    }
}



// ============================================================
// FILE: contracts/Shared/Helpers/RefundNative.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LibAsset } from "../Libraries/LibAsset.sol";

/**
 * @title RefundNative
 * @author DZap
 * @notice Abstract contract to provide functionality to refund native tokens
 */
abstract contract RefundNative {
    /// @dev Refunds any excess native asset sent to the contract after the main function
    /// @notice Refunds any excess native asset sent to the contract after the main function
    /// @param _refundee Address to send refunds to
    modifier refundExcessNative(address _refundee) {
        uint256 initialBalance = address(this).balance - msg.value;
        _;
        uint256 finalBalance = address(this).balance;

        if (finalBalance > initialBalance) LibAsset.transferNativeToken(_refundee, finalBalance - initialBalance);
    }
}



// ============================================================
// FILE: contracts/Shared/Helpers/Swapper.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LibAllowList } from "../Libraries/LibAllowList.sol";
import { LibAsset } from "../Libraries/LibAsset.sol";
import { LibSwap } from "../Libraries/LibSwap.sol";

import { SwapData, SwapExecutionData, SwapInfo, BridgeSwapData } from "../Types.sol";
import { DexNotWhitelisted, NullAddrIsNotAValidRecipient, NoSwapFromZeroAmount } from "../Errors.sol";

/**
 * @title Swapper
 * @author DZap
 * @notice Abstract contract to provide swap functionality
 */
abstract contract Swapper {
    /* ========= EVENTS ========= */

    event DZapTokenSwapped(bytes32 indexed transactionId, address indexed sender, address indexed integrator, SwapInfo swapInfo);
    event DZapBatchTokenSwapped(bytes32 indexed transactionId, address indexed sender, address indexed integrator, SwapInfo[] swapInfo);

    /* ========= INTERNAL ========= */

    /// @notice Validates the swap data
    function _validateSwapData(address _recipient, uint256 _fromAmount, SwapExecutionData memory _swapExecutionData) internal view {
        if (!LibAllowList.isDexWhitelisted(_swapExecutionData.callTo)) revert DexNotWhitelisted(_swapExecutionData.callTo);
        if (_recipient == address(0)) revert NullAddrIsNotAValidRecipient();
        if (_fromAmount == 0) revert NoSwapFromZeroAmount();
    }

    /// @notice Executes a swap
    function _executeSwap(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        SwapData memory _swapData,
        SwapExecutionData memory _swapExecutionData,
        bool _withoutRevert
    ) internal {
        _validateSwapData(_swapData.recipient, _swapData.fromAmount, _swapExecutionData);
        uint256 returnToAmount = LibSwap.swap(
            _user,
            _swapData.recipient,
            _swapData.from,
            _swapData.to,
            _swapData.fromAmount,
            _swapData.minToAmount,
            _swapExecutionData,
            _withoutRevert
        );

        emit DZapTokenSwapped(
            _transactionId,
            _user,
            _integrator,
            SwapInfo(
                _swapExecutionData.dex,
                _swapExecutionData.callTo,
                _swapData.recipient,
                _swapData.from,
                _swapData.to,
                _swapData.fromAmount,
                returnToAmount
            )
        );
    }

    /// @notice Executes multiple swaps
    function _executeSwaps(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        SwapData[] memory _swapData,
        SwapExecutionData[] memory _swapExecutionData,
        bool _withoutRevert
    ) internal {
        uint256 length = _swapData.length;
        uint256 i;
        SwapInfo[] memory swapInfo = new SwapInfo[](length);
        uint256 returnToAmount;

        for (i; i < length; ) {
            SwapData memory swapData = _swapData[i];
            SwapExecutionData memory swapExecutionData = _swapExecutionData[i];

            _validateSwapData(swapData.recipient, swapData.fromAmount, swapExecutionData);
            returnToAmount = LibSwap.swap(
                _user,
                swapData.recipient,
                swapData.from,
                swapData.to,
                swapData.fromAmount,
                swapData.minToAmount,
                swapExecutionData,
                _withoutRevert
            );

            swapInfo[i] = SwapInfo(
                swapExecutionData.dex,
                swapExecutionData.callTo,
                swapData.recipient,
                swapData.from,
                swapData.to,
                swapData.fromAmount,
                returnToAmount
            );
            unchecked {
                ++i;
            }
        }

        if (length > 0) emit DZapBatchTokenSwapped(_transactionId, _user, _integrator, swapInfo);
    }

    /// @notice Executes a bridge swap
    /// @dev Sweep dust if full return amount is not going to be used in bridge
    function _executeBridgeSwap(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        BridgeSwapData memory _swapData,
        SwapExecutionData memory _swapExecutionData,
        bool _withoutRevert
    ) internal {
        _validateSwapData(_swapData.recipient, _swapData.fromAmount, _swapExecutionData);
        uint256 returnToAmount = LibSwap.swap(
            _user,
            _swapData.recipient,
            _swapData.from,
            _swapData.to,
            _swapData.fromAmount,
            _swapData.minToAmount,
            _swapExecutionData,
            _withoutRevert
        );

        // sweep dust
        if (_swapData.recipient == address(this) && !_swapData.updateBridgeInAmount) {
            LibAsset.transferToken(_swapData.to, _user, returnToAmount - _swapData.minToAmount);
        }

        emit DZapTokenSwapped(
            _transactionId,
            _user,
            _integrator,
            SwapInfo(
                _swapExecutionData.dex,
                _swapExecutionData.callTo,
                _swapData.recipient,
                _swapData.from,
                _swapData.to,
                _swapData.fromAmount,
                returnToAmount
            )
        );
    }

    /// @notice Executes multiple bridge swaps
    /// @dev Sweep dust if full return amount is not going to be used in bridge
    function _executeBridgeSwaps(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        BridgeSwapData[] memory _swapData,
        SwapExecutionData[] memory _swapExecutionData,
        bool _withoutRevert
    ) internal {
        uint256 length = _swapData.length;
        uint256 i;
        SwapInfo[] memory swapInfo = new SwapInfo[](length);
        uint256 returnToAmount;

        for (i; i < length; ) {
            BridgeSwapData memory swapData = _swapData[i];
            SwapExecutionData memory swapExecutionData = _swapExecutionData[i];

            _validateSwapData(swapData.recipient, swapData.fromAmount, swapExecutionData);
            returnToAmount = LibSwap.swap(
                _user,
                swapData.recipient,
                swapData.from,
                swapData.to,
                swapData.fromAmount,
                swapData.minToAmount,
                swapExecutionData,
                _withoutRevert
            );

            if (swapData.recipient == address(this) && !swapData.updateBridgeInAmount) {
                LibAsset.transferToken(swapData.to, _user, returnToAmount - swapData.minToAmount);
            }

            swapInfo[i] = SwapInfo(
                swapExecutionData.dex,
                swapExecutionData.callTo,
                swapData.recipient,
                swapData.from,
                swapData.to,
                swapData.fromAmount,
                returnToAmount
            );
            unchecked {
                ++i;
            }
        }

        if (length > 0) emit DZapBatchTokenSwapped(_transactionId, _user, _integrator, swapInfo);
    }
}



// ============================================================
// FILE: contracts/Shared/Interfaces/IBridge.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/**
 * @title IBridge
 * @author DZap
 */
interface IBridge {
    /* ========= EVENTS ========= */
    event DZapBridgeStarted(bytes32 indexed transactionId, address indexed user, address indexed integrator);

    event BridgeStarted(
        bytes32 indexed transactionId,
        address indexed user,
        bytes receiver,
        string bridge,
        address bridgeAddress,
        address from,
        bytes to,
        uint256 amount,
        uint256 destinationChainId,
        bytes destinationCalldata
    );
}



// ============================================================
// FILE: contracts/Shared/Interfaces/IGasLessFacet.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { PermitBatchTransferFrom } from "./IPermit2.sol";
import { SwapData, BridgeSwapData, SwapExecutionData, TokenInfo, InputToken, AdapterInfo } from "../Types.sol";

/**
 * @title IGasLessFacet
 * @author DZap
 */
interface IGasLessFacet {
    /* ========= EVENTS ========= */

    event DZapGasLessStarted(bytes32 indexed _transactionId, address indexed executor, address indexed _user);

    /* ========= EXTERNAL ========= */

    /**
     * @notice Executes a gasless token swap on behalf of a user
     * @dev The executor pays gas fees and receives compensation through _executorFeeInfo.
     *      User must have signed an intent with the specified parameters and deadline.
     *
     * @param _transactionId Unique identifier to prevent replay attacks
     * @param _user Address of the user initiating the swap
     * @param _integrator Address of the integrator for fee sharing
     * @param _userIntentDeadline Timestamp after which the user's intent expires
     * @param _userIntentSignature User's signature authorizing the transaction
     * @param _tokenApprovalData Encoded approval data for token transfers (simple approval, eip2612 permit, permit2 transferFrom)
     * @param _executorFeeInfo Token and amount for executor compensation
     * @param _swapData Configuration for the token swap (recipient, tokens, amounts, slippage)
     * @param _swapExecutionData Low-level execution data (target contract, calldata)
     */
    function executeSwap(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        uint256 _userIntentDeadline,
        bytes calldata _userIntentSignature,
        bytes calldata _tokenApprovalData,
        TokenInfo calldata _executorFeeInfo,
        SwapData calldata _swapData,
        SwapExecutionData calldata _swapExecutionData
    ) external;

    /**
     * @notice Executes multiple gasless token swaps in a single transaction
     * @dev Enables complex multi-hop swaps or parallel swaps across different tokens.
     *      More gas-efficient than multiple single swaps and provides atomic execution.
     *
     * @param _transactionId Unique identifier to prevent replay attacks
     * @param _user Address of the user initiating the swaps
     * @param _integrator Address of the integrator for fee sharing
     * @param _userIntentDeadline Timestamp after which the user's intent expires
     * @param _userIntentSignature User's signature authorizing all swaps
     * @param _inputTokens Array of input tokens with amounts and permissions
     * @param _executorFeeInfo Array of executor fee tokens and amounts
     * @param _swapData Array of swap configurations for each token pair
     * @param _swapExecutionData Array of execution data for each swap
     */
    function executeMultiSwap(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        uint256 _userIntentDeadline,
        bytes calldata _userIntentSignature,
        InputToken[] calldata _inputTokens,
        TokenInfo[] calldata _executorFeeInfo,
        SwapData[] calldata _swapData,
        SwapExecutionData[] calldata _swapExecutionData
    ) external;

    /**
     * @notice Executes multiple gasless swaps using Permit2 batch witness transfers
     * @dev Uses Permit2 for gas-efficient batch token transfers with witness data.
     *      Eliminates need for separate token approvals by including signature-based permits.
     *
     * @param _transactionId Unique identifier to prevent replay attacks
     * @param _user Address of the user initiating the swaps
     * @param _integrator Address of the integrator for fee sharing
     * @param _userIntentSignature User's signature authorizing the operation
     * @param _tokenDepositDetails Permit2 batch transfer structure with witness
     * @param _executorFeeInfo Array of executor fee tokens and amounts
     * @param _swapData Array of swap configurations
     * @param _swapExecutionData Array of execution data for each swap
     */
    function executeMultiSwapWithWitness(
        bytes32 _transactionId,
        address _user,
        address _integrator,
        bytes calldata _userIntentSignature,
        PermitBatchTransferFrom calldata _tokenDepositDetails,
        TokenInfo[] calldata _executorFeeInfo,
        SwapData[] calldata _swapData,
        SwapExecutionData[] calldata _swapExecutionData
    ) external;

    /**
     * @notice Executes a gasless cross-chain bridge transaction
     * @dev Enables users to bridge tokens without holding native tokens for gas.
     *      Includes fee verification to ensure accurate bridge costs.
     *
     * @param _transactionId Unique identifier for the bridge operation
     * @param _bridgeFeeData Encoded FeeConfig containing integrator address and fees info.
     *                       Used for fee distribution between integrator and protocol
     * @param _userIntentSignature User's signature authorizing the bridge
     * @param _feeVerificationSignature Oracle signature verifying bridge fees
     * @param _userIntentDeadline Expiration time for user's intent
     * @param _bridgeFeeDeadline Expiration time for fee quote
     * @param _user Address of the user initiating the bridge
     * @param _inputToken Token to be bridged with amount and permissions
     * @param _executorFeeInfo Executor compensation details
     * @param _adapterInfo Bridge adapter configuration and parameters
     */
    function executeBridge(
        bytes32 _transactionId,
        bytes calldata _bridgeFeeData,
        bytes calldata _userIntentSignature,
        bytes calldata _feeVerificationSignature,
        uint256 _userIntentDeadline,
        uint256 _bridgeFeeDeadline,
        address _user,
        InputToken calldata _inputToken,
        TokenInfo calldata _executorFeeInfo,
        AdapterInfo calldata _adapterInfo
    ) external payable;

    /**
     * @notice Executes multiple gasless bridge transactions with optional pre-bridge swaps
     * @dev Combines swapping and bridging in atomic transactions. Useful for bridging
     *      tokens that aren't natively supported on destination chains.
     *
     * @param _transactionId Unique identifier for the multi-bridge operation
     * @param _bridgeFeeData Encoded FeeConfig containing integrator address and fees info.
     *                       Used for fee distribution between integrator and protocol
     * @param _userIntentSignature User's signature for the entire operation
     * @param _feeVerificationSignature Oracle verification of all bridge fees
     * @param _userIntentDeadline User intent expiration timestamp
     * @param _bridgeFeeDeadline Bridge fee quote expiration timestamp
     * @param _user Address of the user initiating the bridges
     * @param _inputTokens Array of input tokens for swaps and bridges
     * @param _executorFeeInfo Array of executor fees for each operation
     * @param _swapData Array of swap configurations (empty if no pre-bridge swaps)
     * @param _swapExecutionData Array of swap execution data
     * @param _adapterInfo Array of bridge adapter configurations
     */
    function executeMultiBridge(
        bytes32 _transactionId,
        bytes calldata _bridgeFeeData,
        bytes calldata _userIntentSignature,
        bytes calldata _feeVerificationSignature,
        uint256 _userIntentDeadline,
        uint256 _bridgeFeeDeadline,
        address _user,
        InputToken[] calldata _inputTokens,
        TokenInfo[] calldata _executorFeeInfo,
        BridgeSwapData[] calldata _swapData,
        SwapExecutionData[] calldata _swapExecutionData,
        AdapterInfo[] calldata _adapterInfo
    ) external payable;

    /**
     * @notice Executes multiple gasless bridges using Permit2 batch transfers
     * @dev Most gas-efficient method for complex multi-bridge operations.
     *      Combines Permit2 batch transfers with multi-bridge execution.
     *
     * @param _transactionId Unique identifier for the batch bridge operation
     * @param _bridgeFeeData Encoded FeeConfig containing integrator address and fees info.
     *                       Used for fee distribution between integrator and protocol
     * @param _userIntentSignature User's authorization signature
     * @param _feeVerificationSignature Oracle verification of bridge fees
     * @param _bridgeFeeDeadline Expiration time for fee quotes
     * @param _user Address of the user initiating the operations
     * @param _tokenDepositDetails Permit2 batch transfer with witness data
     * @param _executorFeeInfo Array of executor compensation details
     * @param _swapData Array of pre-bridge swap configurations
     * @param _swapExecutionData Array of swap execution parameters
     * @param _adapterInfo Array of bridge adapter configurations
     */
    function executeMultiBridgeWithWitness(
        bytes32 _transactionId,
        bytes calldata _bridgeFeeData,
        bytes calldata _userIntentSignature,
        bytes calldata _feeVerificationSignature,
        uint256 _bridgeFeeDeadline,
        address _user,
        PermitBatchTransferFrom calldata _tokenDepositDetails,
        TokenInfo[] calldata _executorFeeInfo,
        BridgeSwapData[] calldata _swapData,
        SwapExecutionData[] calldata _swapExecutionData,
        AdapterInfo[] calldata _adapterInfo
    ) external payable;
}



// ============================================================
// FILE: contracts/Shared/Interfaces/IPermit2.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

    function transferFrom(address from, address to, uint160 amount, address token) external;

    function allowance(address, address, address) external view returns (uint160, uint48, uint48);

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
// FILE: contracts/Shared/Libraries/LibAllowList.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LibAsset } from "../Libraries/LibAsset.sol";
import { BridgeNotWhitelisted, AdapterNotWhitelisted, DexNotWhitelisted, CannotAuthorizeSelf, NotAContract, ZeroAddress } from "../Errors.sol";

struct AllowListStorage {
    mapping(address => bool) dexAllowlist;
    mapping(address => bool) adaptersAllowlist;
    mapping(address => bool) bridgeAllowlist;
}

/**
 * @title LibAllowList
 * @author DZap
 * @notice Library for managing and accessing the conract address allow list
 */
library LibAllowList {
    bytes32 internal constant ALLOWLIST_NAMESPACE = keccak256("dzap.library.allow.whitelist");

    /// @dev Fetch local storage struct
    function allowListStorage() internal pure returns (AllowListStorage storage als) {
        bytes32 position = ALLOWLIST_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            als.slot := position
        }
    }

    /* ========= VIEWS ========= */

    function isDexWhitelisted(address _dex) internal view returns (bool) {
        return allowListStorage().dexAllowlist[_dex];
    }

    function isAdapterWhitelisted(address _adapter) internal view returns (bool) {
        return allowListStorage().adaptersAllowlist[_adapter];
    }

    function isBridgeWhitelisted(address _bridge) internal view returns (bool) {
        return allowListStorage().bridgeAllowlist[_bridge];
    }

    /* ========= MUTATIONS ========= */

    function addDex(address _dex) internal {
        if (_dex == address(0)) revert ZeroAddress();
        if (_dex == address(this)) revert CannotAuthorizeSelf();
        if (!LibAsset.isContract(_dex)) revert NotAContract();
        allowListStorage().dexAllowlist[_dex] = true;
    }

    function addDexes(address[] memory _dexes) internal {
        AllowListStorage storage als = allowListStorage();
        for (uint256 i; i < _dexes.length; ++i) {
            address dex = _dexes[i];
            if (dex == address(0)) revert ZeroAddress();
            if (dex == address(this)) revert CannotAuthorizeSelf();
            if (!LibAsset.isContract(dex)) revert NotAContract();
            als.dexAllowlist[dex] = true;
        }
    }

    function removeDex(address _dex) internal {
        AllowListStorage storage als = allowListStorage();
        if (!als.dexAllowlist[_dex]) {
            revert DexNotWhitelisted(_dex);
        }
        als.dexAllowlist[_dex] = false;
    }

    function removeDexes(address[] memory _dexes) internal {
        AllowListStorage storage als = allowListStorage();
        for (uint256 i; i < _dexes.length; ++i) {
            if (!als.dexAllowlist[_dexes[i]]) {
                revert DexNotWhitelisted(_dexes[i]);
            }
            als.dexAllowlist[_dexes[i]] = false;
        }
    }

    function addBridge(address _bridge) internal {
        if (_bridge == address(0)) revert ZeroAddress();
        if (_bridge == address(this)) revert CannotAuthorizeSelf();
        if (!LibAsset.isContract(_bridge)) revert NotAContract();
        allowListStorage().bridgeAllowlist[_bridge] = true;
    }

    function addBridges(address[] memory _bridges) internal {
        AllowListStorage storage als = allowListStorage();
        for (uint256 i; i < _bridges.length; ++i) {
            address bridge = _bridges[i];
            if (bridge == address(0)) revert ZeroAddress();
            if (bridge == address(this)) revert CannotAuthorizeSelf();
            if (!LibAsset.isContract(bridge)) revert NotAContract();
            als.bridgeAllowlist[bridge] = true;
        }
    }

    function removeBridge(address _bridge) internal {
        AllowListStorage storage als = allowListStorage();
        if (!als.bridgeAllowlist[_bridge]) {
            revert BridgeNotWhitelisted(_bridge);
        }
        als.bridgeAllowlist[_bridge] = false;
    }

    function removeBridges(address[] memory _bridges) internal {
        AllowListStorage storage als = allowListStorage();
        for (uint256 i; i < _bridges.length; ++i) {
            if (!als.bridgeAllowlist[_bridges[i]]) {
                revert BridgeNotWhitelisted(_bridges[i]);
            }
            als.bridgeAllowlist[_bridges[i]] = false;
        }
    }

    function addAdapter(address _adapter) internal {
        if (_adapter == address(0)) revert ZeroAddress();
        if (_adapter == address(this)) revert CannotAuthorizeSelf();
        if (!LibAsset.isContract(_adapter)) revert NotAContract();
        allowListStorage().adaptersAllowlist[_adapter] = true;
    }

    function addAdapters(address[] memory _adapters) internal {
        AllowListStorage storage als = allowListStorage();
        for (uint256 i; i < _adapters.length; ++i) {
            address adapter = _adapters[i];
            if (adapter == address(0)) revert ZeroAddress();
            if (adapter == address(this)) revert CannotAuthorizeSelf();
            if (!LibAsset.isContract(adapter)) revert NotAContract();
            als.adaptersAllowlist[adapter] = true;
        }
    }

    function removeAdapter(address _adapter) internal {
        AllowListStorage storage als = allowListStorage();
        if (!als.adaptersAllowlist[_adapter]) {
            revert AdapterNotWhitelisted(_adapter);
        }
        als.adaptersAllowlist[_adapter] = false;
    }

    function removeAdapters(address[] memory _adapters) internal {
        AllowListStorage storage als = allowListStorage();
        for (uint256 i; i < _adapters.length; ++i) {
            if (!als.adaptersAllowlist[_adapters[i]]) {
                revert AdapterNotWhitelisted(_adapters[i]);
            }
            als.adaptersAllowlist[_adapters[i]] = false;
        }
    }
}



// ============================================================
// FILE: contracts/Shared/Libraries/LibAsset.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { LibPermit } from "../Libraries/LibPermit.sol";
import { PermitType, InputToken } from "../Types.sol";
import { PermitBatchTransferFrom } from "../Interfaces/IPermit2.sol";
import { NoTransferToNullAddress, NativeTransferFailed, NullAddrIsNotAValidSpender, InvalidPermitType, TransferAmountMismatch } from "../Errors.sol";

/**
 * @title LibAsset
 * @author DZap
 * @notice This library contains helpers for dealing with onchain transfers
 *         of assets, including accounting for the native asset `assetId`
 *         conventions and any noncompliant ERC20 transfers
 */
library LibAsset {
    // ============= CONSTANTS =============

    address internal constant _NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // ============= BALANCE QUERY FUNCTIONS =============

    /// @notice Gets the balance of the inheriting contract for the given asset
    function getOwnBalance(address _token) internal view returns (uint256) {
        return _token == _NATIVE_TOKEN ? address(this).balance : IERC20(_token).balanceOf(address(this));
    }

    /// @notice Gets the balance of the given asset for the given recipient
    function getBalance(address _token, address _recipient) internal view returns (uint256) {
        return _token == _NATIVE_TOKEN ? _recipient.balance : IERC20(_token).balanceOf(_recipient);
    }

    /// @notice Gets the balance of the given erc20 token for the given recipient
    function getErc20Balance(address _token, address _recipient) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_recipient);
    }

    // ============= APPROVAL FUNCTIONS =============

    /// @notice If the current allowance is insufficient, then MAX_UINT allowance for a given spender
    function maxApproveERC20(address _token, address _spender, uint256 _amount) internal {
        if (_spender == address(0)) revert NullAddrIsNotAValidSpender();
        uint256 allowance = IERC20(_token).allowance(address(this), _spender);
        if (allowance < _amount) {
            SafeERC20.forceApprove(IERC20(_token), _spender, type(uint256).max);
        }
    }

    // ============= TRANSFER FUNCTIONS =============

    /// @notice Transfers ether from the inheriting contract to a given recipient
    function transferNativeToken(address _recipient, uint256 _amount) internal {
        if (_recipient == address(0)) revert NoTransferToNullAddress();
        (bool success, ) = _recipient.call{ value: _amount }("");
        if (!success) revert NativeTransferFailed();
    }

    /// @notice Transfers tokens from the inheriting contract to a given recipient
    function transferERC20(address _token, address _recipient, uint256 _amount) internal {
        if (_recipient == address(0)) revert NoTransferToNullAddress();
        SafeERC20.safeTransfer(IERC20(_token), _recipient, _amount);
    }

    /// @notice Transfers tokens from the inheriting contract to a given recipient without checks
    function transferERC20WithoutChecks(address _token, address _recipient, uint256 _amount) internal {
        SafeERC20.safeTransfer(IERC20(_token), _recipient, _amount);
    }

    /// @notice Transfers tokens from a sender to a given recipient without checking the final balance
    /// @dev need to handle deflationary, rebasing or share based tokens
    function transferFromERC20WithoutChecks(address _token, address _from, address _to, uint256 _amount) internal {
        SafeERC20.safeTransferFrom(IERC20(_token), _from, _to, _amount);
    }

    /// @notice Transfers tokens from the inheriting contract to a given recipient with balance check
    function transferERC20WithBalanceCheck(address _token, address _recipient, uint256 _amount) internal {
        if (_recipient == address(0)) revert NoTransferToNullAddress();

        IERC20 token = IERC20(_token);
        uint256 prevBalance = token.balanceOf(_recipient);
        SafeERC20.safeTransfer(token, _recipient, _amount);
        uint256 curr = token.balanceOf(_recipient);
        if (curr < prevBalance || curr - prevBalance != _amount) {
            revert TransferAmountMismatch();
        }
    }

    /// @notice Transfers tokens from a sender to a given recipient with balance check
    function transferFromERC20WithBalanceCheck(address _token, address _sender, address _recipient, uint256 _amount) internal {
        if (_recipient == address(0)) revert NoTransferToNullAddress();

        IERC20 token = IERC20(_token);
        uint256 prevBalance = token.balanceOf(_recipient);
        SafeERC20.safeTransferFrom(token, _sender, _recipient, _amount);
        uint256 curr = token.balanceOf(_recipient);
        if (curr < prevBalance || curr - prevBalance != _amount) {
            revert TransferAmountMismatch();
        }
    }

    /// @notice Wrapper function to transfer a given asset (native or erc20) to
    ///         some recipient. Should handle all non-compliant return value
    ///         tokens as well by using the SafeERC20 contract by open zeppelin.
    function transferToken(address _token, address _recipient, uint256 _amount) internal {
        if (_amount != 0) {
            if (_token == _NATIVE_TOKEN) transferNativeToken(_recipient, _amount);
            else transferERC20(_token, _recipient, _amount);
        }
    }

    // ============= DEPOSIT FUNCTIONS =============

    /// @notice Deposits tokens from a sender to the inheriting contract
    /// @dev only handles erc20 token
    function deposit(address _from, address _token, uint256 _amount, bytes calldata _permit) internal {
        (PermitType permitType, bytes memory data) = abi.decode(_permit, (PermitType, bytes));

        if (permitType == PermitType.PERMIT2_WITNESS_TRANSFER) {
            LibPermit.permit2WitnessTransferFrom(_from, address(this), _token, _amount, data);
        } else if (permitType == PermitType.PERMIT) {
            if (data.length != 0) LibPermit.eip2612Permit(_from, address(this), _token, _amount, data);
            transferFromERC20WithoutChecks(_token, _from, address(this), _amount);
        } else if (permitType == PermitType.PERMIT2_APPROVE) {
            LibPermit.permit2ApproveAndTransfer(_from, address(this), _token, uint160(_amount), data);
        } else {
            revert InvalidPermitType();
        }
    }

    /// @notice Deposits tokens from a sender to the inheriting contract
    function depositBatch(address _from, InputToken[] calldata erc20Tokens) internal {
        uint256 i;
        uint256 length = erc20Tokens.length;
        for (i; i < length; ) {
            deposit(_from, erc20Tokens[i].token, erc20Tokens[i].amount, erc20Tokens[i].permit);
            unchecked {
                ++i;
            }
        }
    }

    function depositBatch(address _from, PermitBatchTransferFrom calldata permit, bytes calldata permitSignature) internal {
        LibPermit.permit2BatchWitnessTransferFrom(_from, address(this), permit, permitSignature);
    }

    // ============= UTILITY FUNCTIONS =============

    /// @notice Determines whether the given token is the native token
    function isNativeToken(address _token) internal pure returns (bool) {
        return _token == _NATIVE_TOKEN;
    }

    /// @dev Checks whether the given address is a contract and contains code
    function isContract(address _contractAddr) internal view returns (bool) {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(_contractAddr)
        }
        return size != 0;
    }
}



// ============================================================
// FILE: contracts/Shared/Libraries/LibBridge.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LibAllowList } from "../../Shared/Libraries/LibAllowList.sol";
import { LibGlobalStorage } from "../../Shared/Libraries/LibGlobalStorage.sol";
import { LibValidator } from "../../Shared/Libraries/LibValidator.sol";
import { LibAsset } from "../../Shared/Libraries/LibAsset.sol";

import { AdapterInfo } from "../Types.sol";
import { FeeConfig } from "../../Shared/Types.sol";
import { AdapterNotWhitelisted, AdapterCallFailed } from "../../Shared/Errors.sol";

/**
 * @title LibBridge
 * @author DZap
 * @notice This library contains helpers for bridging tokens
 */
library LibBridge {
    /// @notice Returns true if the adapter is whitelisted
    function isAdapterWhitelisted(address _adapter) internal view returns (bool) {
        return LibAllowList.isAdapterWhitelisted(_adapter);
    }

    /// @notice Returns true if the bridge is whitelisted
    function isBridgeWhitelisted(address _bridge) internal view returns (bool) {
        return LibAllowList.isBridgeWhitelisted(_bridge);
    }

    /// @notice Verifies and takes fee
    function verifyAndTakeFee(
        address _user,
        uint256 _deadline,
        bytes32 _transactionIdHash,
        bytes32 _adapterInfoHash,
        bytes calldata _feeData,
        bytes calldata _signature
    ) internal returns (address integrator) {
        LibValidator.handleFeeVerification(_user, _deadline, _transactionIdHash, keccak256(_feeData), _adapterInfoHash, _signature);

        return takeFee(_feeData);
    }

    /// @notice Takes fee
    function takeFee(bytes calldata _feeData) internal returns (address integrator) {
        FeeConfig memory feeInfo = abi.decode(_feeData, (FeeConfig));
        address protocolFeeVault = LibGlobalStorage.getProtocolFeeVault();
        uint256 i;
        uint256 length = feeInfo.fees.length;

        for (i; i < length; ) {
            LibAsset.transferToken(feeInfo.fees[i].token, feeInfo.integrator, feeInfo.fees[i].integratorFeeAmount);
            LibAsset.transferToken(feeInfo.fees[i].token, protocolFeeVault, feeInfo.fees[i].protocolFeeAmount);
            unchecked {
                ++i;
            }
        }

        return feeInfo.integrator;
    }

    /// @notice Bridges tokens
    function bridge(AdapterInfo[] calldata _adapterInfo) internal {
        uint256 i;
        uint256 length = _adapterInfo.length;
        for (i; i < length; ) {
            bridge(_adapterInfo[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Bridges tokens
    function bridge(AdapterInfo calldata _adapterInfo) internal {
        address adapter = _adapterInfo.adapter;
        if (!isAdapterWhitelisted(adapter)) revert AdapterNotWhitelisted(adapter);

        (bool success, bytes memory res) = adapter.delegatecall(_adapterInfo.adapterData);
        if (!success) revert AdapterCallFailed(adapter, res);
    }
}



// ============================================================
// FILE: contracts/Shared/Libraries/LibGlobalStorage.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct GlobalStorage {
    bool initialized;
    address protocolFeeVault;
    address feeValidator;
    address permit2;
    address refundVault;
    bool paused;
}

/**
 * @title LibGlobalStorage
 * @author DZap
 * @notice This library provides functionality for managing global storage
 */
library LibGlobalStorage {
    bytes32 internal constant _GLOBAL_NAMESPACE = keccak256("dzap.storage.library.global");

    function globalStorage() internal pure returns (GlobalStorage storage ds) {
        bytes32 slot = _GLOBAL_NAMESPACE;
        assembly {
            ds.slot := slot
        }
    }

    function getRefundVault() internal view returns (address) {
        return globalStorage().refundVault;
    }

    function getProtocolFeeVault() internal view returns (address) {
        return globalStorage().protocolFeeVault;
    }

    function getFeeValidator() internal view returns (address) {
        return globalStorage().feeValidator;
    }

    function getPermit2() internal view returns (address) {
        return globalStorage().permit2;
    }

    function getPaused() internal view returns (bool) {
        return globalStorage().paused;
    }
}



// ============================================================
// FILE: contracts/Shared/Libraries/LibPermit.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { LibGlobalStorage } from "./LibGlobalStorage.sol";
import { PermitTransferFrom, PermitBatchTransferFrom, SignatureTransferDetails, PermitSingle, PermitDetails, TokenPermissions, IPermit2 } from "../Interfaces/IPermit2.sol";

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

    // ============= VIEW =============

    /// @notice Returns the permit2 address
    function permit2() private view returns (address) {
        return LibGlobalStorage.getPermit2();
    }

    // ============= EIP-2612 PERMIT FUNCTIONS =============

    /// @notice Handles eip2612 permit
    function eip2612Permit(address _owner, address _spender, address _token, uint256 _amount, bytes memory _data) internal {
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(_data, (uint256, uint8, bytes32, bytes32));
        try IERC20Permit(_token).permit(_owner, _spender, _amount, deadline, v, r, s) {} catch Error(string memory reason) {
            if (IERC20(_token).allowance(_owner, _spender) < _amount) {
                revert InvalidPermit(reason);
            }
        }
    }

    // ============= PERMIT2 FUNCTIONS =============

    /// @notice Handles permit2 approve and transfer
    function permit2ApproveAndTransfer(address _owner, address _spender, address _token, uint160 _amount, bytes memory data) internal {
        permit2Approve(_owner, _spender, _token, _amount, data);
        IPermit2(permit2()).transferFrom(_owner, _spender, uint160(_amount), _token);
    }

    /// @notice Handles permit2 approve
    function permit2Approve(address _owner, address _spender, address _token, uint160 _amount, bytes memory _data) internal {
        if (_data.length == 0) return;
        IPermit2 permit2Contract = IPermit2(permit2());
        (uint48 nonce, uint48 expiration, uint256 sigDeadline, bytes memory signature) = abi.decode(_data, (uint48, uint48, uint256, bytes));

        try
            permit2Contract.permit(_owner, PermitSingle(PermitDetails(_token, _amount, expiration, nonce), _spender, sigDeadline), signature)
        {} catch Error(string memory reason) {
            (uint256 currentAllowance, uint256 allowanceExpiration, ) = permit2Contract.allowance(_owner, _token, _spender);
            if (currentAllowance < _amount || allowanceExpiration < block.timestamp) revert InvalidPermit(reason);
        }
    }

    /// @notice Handles permit2 witness transfer from
    function permit2WitnessTransferFrom(address _owner, address _recipient, address _token, uint256 _amount, bytes memory _data) internal {
        (uint256 nonce, uint256 deadline, bytes memory _signature) = abi.decode(_data, (uint256, uint256, bytes));
        IPermit2(permit2()).permitWitnessTransferFrom(
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
        address _owner,
        address _recipient,
        PermitBatchTransferFrom calldata permit,
        bytes calldata _signature
    ) internal {
        uint256 length = permit.permitted.length;
        SignatureTransferDetails[] memory details = new SignatureTransferDetails[](length);

        for (uint256 i; i < length; ) {
            details[i] = SignatureTransferDetails(_recipient, permit.permitted[i].amount);
            unchecked {
                ++i;
            }
        }

        IPermit2(permit2()).permitWitnessTransferFrom(
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
        address _owner,
        address _recipient,
        bytes32 _witness,
        PermitBatchTransferFrom calldata permit,
        bytes calldata _signature,
        string memory _witnessTypeString
    ) internal {
        uint256 length = permit.permitted.length;
        SignatureTransferDetails[] memory details = new SignatureTransferDetails[](length);

        for (uint256 i; i < length; ) {
            details[i] = SignatureTransferDetails(_recipient, permit.permitted[i].amount);
            unchecked {
                ++i;
            }
        }

        IPermit2(permit2()).permitWitnessTransferFrom(permit, details, _owner, _witness, _witnessTypeString, _signature);
    }

    /* ========= PRIVATE ========= */

    function _createWitnessTransferFromHash(address _owner, address _recipient) private pure returns (bytes32) {
        return keccak256(abi.encode(_DZAP_TRANSFER_WITNESS_TYPEHASH, _owner, _recipient));
    }
}



// ============================================================
// FILE: contracts/Shared/Libraries/LibSwap.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LibAsset } from "../Libraries/LibAsset.sol";
import { SwapExecutionData } from "../Types.sol";
import { SwapCallFailed, SlippageTooHigh } from "../Errors.sol";

/**
 * @title LibSwap
 * @author DZap
 * @notice This library contains helpers for doing swap
 */
library LibSwap {
    function swap(
        address _user,
        address _recipient,
        address _from,
        address _to,
        uint256 _fromAmount,
        uint256 _minToAmount,
        SwapExecutionData memory _swapExecutionData,
        bool _withoutRevert
    ) internal returns (uint256 returnToAmount) {
        address recipient = _swapExecutionData.isDirectTransfer ? _recipient : address(this);
        uint256 initialToBalance = LibAsset.getBalance(_to, recipient);
        uint256 nativeValue;

        if (LibAsset.isNativeToken(_from)) {
            nativeValue = _fromAmount;
        } else {
            LibAsset.maxApproveERC20(_from, _swapExecutionData.approveTo, _fromAmount);
        }

        (bool success, bytes memory res) = _swapExecutionData.callTo.call{ value: nativeValue }(_swapExecutionData.swapCallData);

        if (!success) {
            if (_withoutRevert) {
                LibAsset.transferToken(_from, _user, _fromAmount);
                return (0);
            }
            revert SwapCallFailed(_swapExecutionData.callTo, bytes4(_swapExecutionData.swapCallData), res);
        }

        returnToAmount = LibAsset.getBalance(_to, recipient) - initialToBalance;
        if (returnToAmount < _minToAmount) revert SlippageTooHigh(_minToAmount, returnToAmount);
        if (!_swapExecutionData.isDirectTransfer && _recipient != address(this)) LibAsset.transferToken(_to, _recipient, returnToAmount);
    }
}



// ============================================================
// FILE: contracts/Shared/Libraries/LibValidator.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LibGlobalStorage } from "./LibGlobalStorage.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

struct ValidatorStorage {
    mapping(address => uint256) nonce;
}

/**
 * @title LibValidator
 * @author DZap
 * @notice This library contains helpers for validating signatures
 */
library LibValidator {
    error SigDeadlineExpired();
    error UnauthorizedSigner();

    bytes32 internal constant _VALIDATOR_NAMESPACE = keccak256("dzap.storage.library.validator");
    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");

    bytes32 private constant _SIGNED_GASLESS_DATA_TYPEHASH =
        keccak256("SignedGasLessSwapData(bytes32 txId,address user,uint256 nonce,uint256 deadline,bytes32 executorFeesHash,bytes32 swapDataHash)");

    bytes32 private constant _SIGNED_GASLESS_BRIDGE_DATA_TYPEHASH =
        keccak256(
            "SignedGasLessBridgeData(bytes32 txId,address user,uint256 nonce,uint256 deadline,bytes32 executorFeesHash,bytes32 adapterDataHash)"
        );

    bytes32 private constant _SIGNED_GASLESS_SWAP_BRIDGE_DATA_TYPEHASH =
        keccak256(
            "SignedGasLessSwapBridgeData(bytes32 txId,address user,uint256 nonce,uint256 deadline,bytes32 executorFeesHash,bytes32 swapDataHash,bytes32 adapterDataHash)"
        );
    bytes32 private constant _SIGNED_FEE_DATA_TYPEHASH =
        keccak256("SignedFeeData(bytes32 txId,address user,uint256 nonce,uint256 deadline,bytes32 feeDataHash,bytes32 adapterDataHash)");
    string private constant _DOMAIN_NAME = "DZapVerifier";
    string private constant _VERSION = "1";
    bytes32 private constant _SALT = keccak256("DZap-v0.1");

    function validatorStorage() internal pure returns (ValidatorStorage storage ds) {
        bytes32 slot = _VALIDATOR_NAMESPACE;
        assembly {
            ds.slot := slot
        }
    }

    /// @notice Returns the nonce for a given user
    function getNonce(address _user) internal view returns (uint256) {
        return validatorStorage().nonce[_user];
    }

    /// @notice Handles gasless swap verification
    function handleGasLessSwapVerification(
        address _user,
        uint256 _deadline,
        bytes32 _transactionId,
        bytes32 _executorFeesHash,
        bytes32 _swapDataHash,
        bytes calldata _signature
    ) internal {
        if (_deadline < block.timestamp) revert SigDeadlineExpired();
        uint256 nonce = getNonce(_user);
        bytes32 msgHash = keccak256(
            abi.encode(_SIGNED_GASLESS_DATA_TYPEHASH, _transactionId, _user, nonce, _deadline, _executorFeesHash, _swapDataHash)
        );
        _verifySignature(_user, msgHash, _signature);
        _incrementNonce(_user);
    }

    /// @notice Handles gasless bridge verification
    function handleGasLessBridgeVerification(
        address _user,
        uint256 _deadline,
        bytes32 _transactionId,
        bytes32 _executorFeesHash,
        bytes32 _adapterDataHash,
        bytes calldata _signature
    ) internal {
        if (_deadline < block.timestamp) revert SigDeadlineExpired();
        uint256 nonce = getNonce(_user);
        bytes32 msgHash = keccak256(
            abi.encode(_SIGNED_GASLESS_BRIDGE_DATA_TYPEHASH, _transactionId, _user, nonce, _deadline, _executorFeesHash, _adapterDataHash)
        );
        _verifySignature(_user, msgHash, _signature);
        _incrementNonce(_user);
    }

    /// @notice Handles gasless swap bridge verification
    function handleGasLessSwapBridgeVerification(
        address _user,
        uint256 _deadline,
        bytes32 _transactionId,
        bytes32 _executorFeesHash,
        bytes32 _swapDataHash,
        bytes32 _adapterDataHash,
        bytes calldata _signature
    ) internal {
        if (_deadline < block.timestamp) revert SigDeadlineExpired();
        uint256 nonce = getNonce(_user);
        bytes32 msgHash = keccak256(
            abi.encode(
                _SIGNED_GASLESS_SWAP_BRIDGE_DATA_TYPEHASH,
                _transactionId,
                _user,
                nonce,
                _deadline,
                _executorFeesHash,
                _swapDataHash,
                _adapterDataHash
            )
        );
        _verifySignature(_user, msgHash, _signature);
        _incrementNonce(_user);
    }

    /// @notice Handles fee verification
    function handleFeeVerification(
        address _user,
        uint256 _deadline,
        bytes32 _transactionId,
        bytes32 _feeDataHash,
        bytes32 _adapterDataHash,
        bytes calldata _signature
    ) internal {
        if (_deadline < block.timestamp) revert SigDeadlineExpired();
        address validator = LibGlobalStorage.getFeeValidator();
        uint256 nonce = getNonce(_user);
        bytes32 msgHash = keccak256(abi.encode(_SIGNED_FEE_DATA_TYPEHASH, _transactionId, _user, nonce, _deadline, _feeDataHash, _adapterDataHash));
        _verifySignature(validator, msgHash, _signature);
        _incrementNonce(_user);
    }

    /* ========= PRIVATE ========= */

    function _getDomainSeparator() private view returns (bytes32) {
        return
            keccak256(abi.encode(_DOMAIN_TYPEHASH, keccak256(bytes(_DOMAIN_NAME)), keccak256(bytes(_VERSION)), block.chainid, address(this), _SALT));
    }

    function _verifySignature(address _signer, bytes32 _msgHash, bytes calldata _signature) private view {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getDomainSeparator(), _msgHash));
        if (ECDSA.recover(digest, _signature) != _signer) revert UnauthorizedSigner();
    }

    function _incrementNonce(address _user) private {
        validatorStorage().nonce[_user]++;
    }
}



// ============================================================
// FILE: contracts/Shared/Types.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title DZap Types

enum PermitType {
    PERMIT, // EIP2612
    PERMIT2_APPROVE,
    PERMIT2_WITNESS_TRANSFER,
    BATCH_PERMIT2_WITNESS_TRANSFER
}

struct InputToken {
    address token;
    uint256 amount;
    bytes permit;
}

struct SwapInfo {
    string dex;
    address callTo;
    address recipient;
    address fromToken;
    address toToken;
    uint256 fromAmount;
    uint256 returnToAmount;
}

struct SwapData {
    address recipient;
    address from;
    address to;
    uint256 fromAmount;
    uint256 minToAmount;
}

struct BridgeSwapData {
    address recipient;
    address from;
    address to;
    uint256 fromAmount;
    uint256 minToAmount;
    bool updateBridgeInAmount;
}

struct SwapExecutionData {
    string dex;
    address callTo;
    address approveTo;
    bytes swapCallData;
    bool isDirectTransfer;
}

struct TokenInfo {
    address token;
    uint256 amount;
}

struct Fees {
    address token;
    uint256 integratorFeeAmount;
    uint256 protocolFeeAmount;
}

struct FeeConfig {
    address integrator;
    Fees[] fees;
}

struct AdapterInfo {
    address adapter;
    bytes adapterData;
}
