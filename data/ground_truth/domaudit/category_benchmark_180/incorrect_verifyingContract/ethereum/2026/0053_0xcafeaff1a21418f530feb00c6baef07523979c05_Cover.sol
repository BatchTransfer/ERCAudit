// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xcafeaff1a21418f530feb00c6baef07523979c05
// Contract Name: Cover



// ============================================================
// FILE: @openzeppelin/contracts-v4/token/ERC20/extensions/draft-IERC20Permit.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/draft-IERC20Permit.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
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
// FILE: @openzeppelin/contracts-v4/token/ERC20/IERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

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
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}



// ============================================================
// FILE: @openzeppelin/contracts-v4/token/ERC20/utils/SafeERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../extensions/draft-IERC20Permit.sol";
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

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

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
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}



// ============================================================
// FILE: @openzeppelin/contracts-v4/token/ERC721/IERC721.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC721/IERC721.sol)

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
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

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
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
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
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

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
    function setApprovalForAll(address operator, bool _approved) external;

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
// FILE: @openzeppelin/contracts-v4/utils/Address.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)

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
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
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
        return functionCall(target, data, "Address: low-level call failed");
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
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
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
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
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
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
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
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
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
}



// ============================================================
// FILE: @openzeppelin/contracts-v4/utils/cryptography/ECDSA.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.3) (utils/cryptography/ECDSA.sol)

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
        InvalidSignatureV
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
        } else if (error == RecoverError.InvalidSignatureV) {
            revert("ECDSA: invalid signature 'v' value");
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
    function tryRecover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address, RecoverError) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `r and `vs` short-signature fields separately.
     *
     * _Available since v4.2._
     */
    function recover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address) {
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
    function tryRecover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address, RecoverError) {
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
        if (v != 27 && v != 28) {
            return (address(0), RecoverError.InvalidSignatureV);
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
    function recover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
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
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
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
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}



// ============================================================
// FILE: @openzeppelin/contracts-v4/utils/introspection/IERC165.sol
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
// FILE: @openzeppelin/contracts-v4/utils/Strings.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Strings.sol)

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

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

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
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
}



// ============================================================
// FILE: contracts/abstract/EIP712.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-v4/utils/cryptography/ECDSA.sol";

abstract contract EIP712 {

  bytes32 public immutable DOMAIN_SEPARATOR;

  constructor(
    string memory name,
    string memory version,
    address verifyingContract
  ) {
    bytes32 hashedName = keccak256(bytes(name));
    bytes32 hashedVersion = keccak256(bytes(version));
    bytes32 typeHash = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    DOMAIN_SEPARATOR = keccak256(abi.encode(typeHash, hashedName, hashedVersion, block.chainid, verifyingContract));
  }

  function recoverSigner(
    bytes memory message,
    bytes memory signature
  ) internal view virtual returns (address signer) {
    bytes32 digest = ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, keccak256(message));
    return ECDSA.recover(digest, signature);
  }
}



// ============================================================
// FILE: contracts/abstract/Multicall.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.18;

abstract contract Multicall {

  error RevertedWithoutReason(uint index);

  // WARNING: Do not set this function as payable
  function multicall(bytes[] calldata data) external returns (bytes[] memory results) {

    uint callCount = data.length;
    results = new bytes[](callCount);

    for (uint i = 0; i < callCount; i++) {
      (bool ok, bytes memory result) = address(this).delegatecall(data[i]);

      if (!ok) {

        uint length = result.length;

        // 0 length returned from empty revert() / require(false)
        if (length == 0) {
          revert RevertedWithoutReason(i);
        }

        assembly {
          revert(add(result, 0x20), length)
        }
      }

      results[i] = result;
    }
  }
}



// ============================================================
// FILE: contracts/abstract/ReentrancyGuard.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.28;

abstract contract ReentrancyGuard {

  bool transient internal reentrancyLocked;

  error ReentrantCall();

  modifier nonReentrant() {
    require(!reentrancyLocked, ReentrantCall());
    reentrancyLocked = true;
    _;
    reentrancyLocked = false;
  }
}



// ============================================================
// FILE: contracts/abstract/RegistryAware.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.28;

import "../interfaces/IRegistry.sol";

// contract indexes
uint constant C_REGISTRY             = 1 << 0;   // 1
uint constant C_GOVERNOR             = 1 << 1;   // 2
uint constant C_TOKEN                = 1 << 2;   // 4
uint constant C_TOKEN_CONTROLLER     = 1 << 3;   // 8
uint constant C_POOL                 = 1 << 4;   // 16
uint constant C_COVER                = 1 << 5;   // 32
uint constant C_COVER_PRODUCTS       = 1 << 6;   // 64
uint constant C_STAKING_PRODUCTS     = 1 << 7;   // 128
uint constant C_RAMM                 = 1 << 8;   // 256
uint constant C_SAFE_TRACKER         = 1 << 9;   // 512
uint constant C_LIMIT_ORDERS         = 1 << 10;  // 1024
uint constant C_STAKING_NFT          = 1 << 11;  // 2048
uint constant C_COVER_NFT            = 1 << 12;  // 4096
uint constant C_SWAP_OPERATOR        = 1 << 13;  // 8192
uint constant C_ASSESSMENTS          = 1 << 14;  // 16384
uint constant C_CLAIMS               = 1 << 15;  // 32768
uint constant C_STAKING_POOL_FACTORY = 1 << 16;  // 65536

// pause types constants
uint constant PAUSE_GLOBAL        = 1 << 0;   // 1
uint constant PAUSE_RAMM          = 1 << 1;   // 2
uint constant PAUSE_SWAPS         = 1 << 2;   // 4
uint constant PAUSE_MEMBERSHIP    = 1 << 3;   // 8
uint constant PAUSE_ASSESSMENTS   = 1 << 4;   // 16
uint constant PAUSE_CLAIMS        = 1 << 5;   // 32
uint constant PAUSE_COVER         = 1 << 6;   // 64

contract RegistryAware {

  IRegistry public immutable registry;

  error Paused(uint currentState, uint checks);
  error Unauthorized(address caller, uint callerIndex, uint authorizedBitmap);
  error OnlyMember();
  error OnlyAdvisoryBoard();

  modifier whenNotPaused(uint mask) {
    uint config = registry.getPauseConfig();
    uint maskWithGlobal = mask | PAUSE_GLOBAL;
    require(config & maskWithGlobal == 0, Paused(config, mask));
    _;
  }

  modifier onlyContracts(uint authorizedBitmap) {
    uint callerIndex = msg.sender == address(registry)
      ? C_REGISTRY
      : registry.getContractIndexByAddress(msg.sender);
    bool isAuthorized = callerIndex & authorizedBitmap != 0;
    require(isAuthorized, Unauthorized(msg.sender, callerIndex, authorizedBitmap));
    _;
  }

  modifier onlyAdvisoryBoard() {
    require(registry.isAdvisoryBoardMember(msg.sender), OnlyAdvisoryBoard());
    _;
  }

  modifier onlyMember() {
    require(registry.isMember(msg.sender), OnlyMember());
    _;
  }

  function fetch(uint index) internal view returns (address) {
    return registry.getContractAddressByIndex(index);
  }

  constructor(address _registry) {
    registry = IRegistry(_registry);
  }

}



// ============================================================
// FILE: contracts/interfaces/ICover.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.5.0;

import "./ICoverNFT.sol";
import "./ICoverProducts.sol";
import "./IStakingNFT.sol";
import "./IStakingPoolBeacon.sol";

/* io structs */

struct BuyCoverParams {
  uint coverId;
  address owner;
  uint24 productId;
  uint8 coverAsset;
  uint96 amount;
  uint32 period;
  uint maxPremiumInAsset;
  uint8 paymentAsset;
  uint16 commissionRatio;
  address commissionDestination;
  string ipfsData;
}

struct PoolAllocationRequest {
  uint poolId;
  uint coverAmountInAsset;
}

/* storage structs */

struct PoolAllocation {
  uint40 poolId;
  uint96 coverAmountInNXM;
  uint96 premiumInNXM;
  uint24 allocationId;
}

struct CoverData {
  uint24 productId;
  uint8 coverAsset;
  uint96 amount;
  uint32 start;
  uint32 period;
  uint32 gracePeriod;
  uint16 rewardsRatio;
  uint16 capacityRatio;
}

struct CoverReference {
  uint32 originalCoverId; // set to 0 in the original cover
  uint32 latestCoverId; // used only in the original cover (set to 0 in original cover if never edited)
}

// reinsurance info
struct Ri {
  uint24 providerId;
  uint96 amount;
}

struct RiConfig {
  uint24 nextNonce;
  address premiumDestination;
}

struct RiRequest {
  uint providerId;
  uint amount;
  uint premium;
  bytes signature;
  bytes data;
  uint8 dataFormat;
  uint32 deadline;
}

interface ICover is IStakingPoolBeacon {

  /* ========== DATA STRUCTURES ========== */

  /* internal structs */

  struct RequestAllocationVariables {
    uint previousPoolAllocationsLength;
    uint previousPremiumInNXM;
    uint refund;
    uint coverAmountInNXM;
  }

  /* storage structs */

  struct ActiveCover {
    // Global active cover amount per asset.
    uint192 totalActiveCoverInAsset;
    // The last time activeCoverExpirationBuckets was updated
    uint64 lastBucketUpdateId;
  }

  /* ========== VIEWS ========== */

  function getCoverData(uint coverId) external view returns (CoverData memory);

  function getCoverRi(uint coverId) external view returns (Ri memory);

  function getCoverDataWithRi(uint coverId) external view returns (CoverData memory, Ri memory);

  function getCoverReference(uint coverId) external view returns(CoverReference memory);

  function getCoverDataWithReference(uint coverId) external view returns (CoverData memory, CoverReference memory);

  function getCoverMetadata(uint coverId) external view returns (string memory);

  function getCoverDataCount() external view returns (uint);

  function getPoolAllocations(uint coverId) external view returns (PoolAllocation[] memory);

  function getLatestEditCoverData(uint coverId) external view returns (CoverData memory);

  function getRiProviderConfig(uint providerId) external view returns (RiConfig memory);

  function recalculateActiveCoverInAsset(uint coverAsset) external;

  function totalActiveCoverInAsset(uint coverAsset) external view returns (uint);

  function getGlobalCapacityRatio() external view returns (uint);

  function getGlobalRewardsRatio() external view returns (uint);

  function getDefaultMinPriceRatio() external pure returns (uint);

  function getGlobalCapacityAndPriceRatios() external view returns (
    uint _globalCapacityRatio,
    uint _defaultMinPriceRatio
  );

  function DEFAULT_MIN_PRICE_RATIO() external view returns (uint);

  function coverNFT() external returns (ICoverNFT);

  function stakingNFT() external returns (IStakingNFT);

  function stakingPoolFactory() external returns (address);

  function coverProducts() external returns (ICoverProducts);

  /* === MUTATIVE FUNCTIONS ==== */

  function buyCover(
    BuyCoverParams calldata params,
    PoolAllocationRequest[] calldata coverChunkRequests
  ) external payable returns (uint coverId);

  function executeCoverBuy(
    BuyCoverParams calldata params,
    PoolAllocationRequest[] calldata coverChunkRequests,
    address buyer
  ) external payable returns (uint coverId);

  function buyCoverWithRi(
    BuyCoverParams calldata params,
    PoolAllocationRequest[] calldata coverChunkRequests,
    RiRequest calldata riRequest
  ) external payable returns (uint coverId);

  function burnStake(uint coverId, uint amount) external;

  /* ========== EVENTS ========== */

  event CoverBought(
    uint indexed coverId,
    uint indexed originalCoverId,
    uint indexed buyerMemberId,
    uint productId
  );
  event CoverRiAllocated(uint indexed coverId, uint premium, uint paymentAsset, bytes data, uint8 dataFormatVersion);

  // Auth
  error OnlyOwnerOrApproved();

  // Cover details
  error CoverPeriodTooShort();
  error CoverPeriodTooLong();
  error CoverAmountIsZero();
  error CoverAssetMismatch();

  // Products
  error ProductNotFound();
  error ProductDeprecated();

  // Cover and payment assets
  error CoverAssetNotSupported();
  error InvalidPaymentAsset();
  error UnexpectedEthSent();
  error EditNotSupported();
  error MustBeOriginalCoverId(uint originalCoverId);

  // Price & Commission
  error PriceExceedsMaxPremiumInAsset();
  error CommissionRateTooHigh();

  // ETH transfers
  error InsufficientEthSent();
  error ETHTransferFailed(address to, uint amount);

  // Misc
  error ExpiredCoversCannotBeEdited();
  error CoverNotYetExpired(uint coverId);
  error InsufficientCoverAmountAllocated();
  error AlreadyMigratedCoverData(uint coverId);

  // Ri
  error InvalidSignature();
  error SignatureExpired();
  error WrongCoverEditEntrypoint();
  error RiAmountIsZero();
  error InvalidRiConfig();
  error UnexpectedRiPremium();
}



// ============================================================
// FILE: contracts/interfaces/ICoverNFT.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.5.0;

import "@openzeppelin/contracts-v4/token/ERC721/IERC721.sol";

interface ICoverNFT is IERC721 {

  function isApprovedOrOwner(address spender, uint tokenId) external returns (bool);

  function mint(address to) external returns (uint tokenId);

  function changeOperator(address newOperator) external;

  function changeNFTDescriptor(address newNFTDescriptor) external;

  function totalSupply() external view returns (uint);

  function name() external view returns (string memory);

  error NotOperator();
  error NotMinted();
  error WrongFrom();
  error InvalidRecipient();
  error InvalidNewOperatorAddress();
  error InvalidNewNFTDescriptorAddress();
  error NotAuthorized();
  error UnsafeRecipient();
  error AlreadyMinted();

}



// ============================================================
// FILE: contracts/interfaces/ICoverProducts.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.5.0;

import "./ICover.sol";

/* enums */

enum ClaimMethod {
  IndividualClaims,
  DeprecatedYieldTokenIncidents
}

/* io structs */

struct ProductInitializationParams {
  uint productId;
  uint8 weight;
  uint96 initialPrice;
  uint96 targetPrice;
}

/* storage structs */

struct Product {
  uint16 productType;
  uint16 minPrice;
  // leftover memory gap from the previously used address field yieldTokenAddress
  uint144 __gap;
  // cover assets bitmap. each bit represents whether the asset with
  // the index of that bit is enabled as a cover asset for this product
  uint32 coverAssets;
  uint16 initialPriceRatio;
  uint16 capacityReductionRatio;
  bool isDeprecated;
  bool useFixedPrice;
}

struct ProductType {
  ClaimMethod claimMethod;
  uint32 gracePeriod;
  uint32 assessmentCooldownPeriod;
  uint32 payoutRedemptionPeriod;
}

interface ICoverProducts {

  /* storage structs */

  struct Metadata {
    string ipfsHash;
    uint timestamp;
  }

  /* io structs */

  struct ProductParam {
    string productName;
    uint productId;
    string ipfsMetadata;
    Product product;
    uint[] allowedPools;
  }

  struct ProductTypeParam {
    string productTypeName;
    uint productTypeId;
    string ipfsMetadata;
    ProductType productType;
  }

  /* ========== VIEWS ========== */

  function getProductType(uint productTypeId) external view returns (ProductType memory);

  function getProductTypeName(uint productTypeId) external view returns (string memory);

  function getProductTypeCount() external view returns (uint);

  function getProductTypes() external view returns (ProductType[] memory);

  function getProduct(uint productId) external view returns (Product memory);

  function getProductName(uint productTypeId) external view returns (string memory);

  function getProductCount() external view returns (uint);

  function getProducts() external view returns (Product[] memory);

  // add grace period function?
  function getProductWithType(uint productId) external view returns (Product memory, ProductType memory);

  function getProductTypeOf(uint productId) external view returns (ProductType memory);

  function getLatestProductMetadata(uint productId) external view returns (Metadata memory);

  function getLatestProductTypeMetadata(uint productTypeId) external view returns (Metadata memory);

  function getProductMetadata(uint productId) external view returns (Metadata[] memory);

  function getProductTypeMetadata(uint productTypeId) external view returns (Metadata[] memory);

  function getAllowedPools(uint productId) external view returns (uint[] memory _allowedPools);

  function getAllowedPoolsCount(uint productId) external view returns (uint);

  function isPoolAllowed(uint productId, uint poolId) external view returns (bool);

  function requirePoolIsAllowed(uint[] calldata productIds, uint poolId) external view;

  function getCapacityReductionRatios(uint[] calldata productIds) external view returns (uint[] memory);

  function getInitialPrices(uint[] calldata productIds) external view returns (uint[] memory);

  function getMinPrices(uint[] calldata productIds) external view returns (uint[] memory);

  function prepareStakingProductsParams(
    ProductInitializationParams[] calldata params
  ) external returns (
    ProductInitializationParams[] memory validatedParams
  );

  /* === MUTATIVE FUNCTIONS ==== */

  function setProductTypes(ProductTypeParam[] calldata productTypes) external;

  function setProducts(ProductParam[] calldata params) external;

  /* ========== EVENTS ========== */

  event ProductSet(uint id);
  event ProductTypeSet(uint id);

  // Products and product types
  error ProductNotFound();
  error ProductTypeNotFound();
  error ProductDeprecated();
  error PoolNotAllowedForThisProduct(uint productId);
  error StakingPoolDoesNotExist();
  error MismatchedArrayLengths();
  error MetadataRequired();
  error ClaimMethodMismatch();

  // Misc
  error UnsupportedCoverAssets();
  error InitialPriceRatioBelowMinPriceRatio();
  error InitialPriceRatioAbove100Percent();
  error CapacityReductionRatioAbove100Percent();

}



// ============================================================
// FILE: contracts/interfaces/INXMToken.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.5.0;

interface INXMToken {

  function burn(uint256 amount) external returns (bool);

  function burnFrom(address from, uint256 value) external returns (bool);

  function operatorTransfer(address from, uint256 value) external returns (bool);

  function mint(address account, uint256 amount) external;

  function isLockedForMV(address member) external view returns (uint);

  function whiteListed(address member) external view returns (bool);

  function addToWhiteList(address _member) external returns (bool);

  function removeFromWhiteList(address _member) external returns (bool);

  function changeOperator(address _newOperator) external returns (bool);

  function lockForMemberVote(address _of, uint _days) external;

  /**
 * @dev Returns the amount of tokens in existence.
 */
  function totalSupply() external view returns (uint256);

  /**
   * @dev Returns the amount of tokens owned by `account`.
   */
  function balanceOf(address account) external view returns (uint256);

  /**
   * @dev Moves `amount` tokens from the caller's account to `recipient`.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transfer(address recipient, uint256 amount) external returns (bool);

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
   * @dev Moves `amount` tokens from `sender` to `recipient` using the
   * allowance mechanism. `amount` is then deducted from the caller's
   * allowance.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

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
}



// ============================================================
// FILE: contracts/interfaces/IPool.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.5.0;

interface Aggregator {
  function decimals() external view returns (uint8);
  function latestAnswer() external view returns (int);
}

struct Asset {
  address assetAddress;
  bool isCoverAsset;
  bool isAbandoned;
  // 80 bits left
}

enum AggregatorType { ETH, USD }

struct Oracle {
  Aggregator aggregator;
  AggregatorType aggregatorType;
  uint8 assetDecimals;
  // 80 bits left
}

struct OrderIntent {
  uint8 sellAsset;
  uint8 buyAsset;
  uint96 sellAmount;
  uint96 buyAmount;
  uint16 slippage; // bps
  uint32 deadline;
}

struct AssetInSwapOperator {
  address assetAddress;
  uint96 amount;
}

struct MCR {
  uint80 stored;
  uint80 desired;
  uint32 updatedAt;
}

interface IPool {

  function getAsset(uint assetId) external view returns (Asset memory);

  function getAssets() external view returns (Asset[] memory);

  function addAsset(address assetAddress, bool isCoverAsset, Aggregator aggregator, AggregatorType aggregatorType) external;

  function setAssetDetails(uint assetId, bool isCoverAsset, bool isAbandoned) external;

  function sendPayout(uint assetIndex, address payable payoutAddress, uint amount, uint depositInETH) external;

  function sendEth(address payable payoutAddress, uint amount) external;

  function getPoolValueInEth() external view returns (uint);

  function getInternalTokenPriceInAsset(uint assetId) external view returns (uint tokenPrice);

  function getInternalTokenPriceInAssetAndUpdateTwap(uint assetId) external returns (uint tokenPrice);

  function getTokenPrice() external view returns (uint tokenPrice);

  function getMCRRatio() external view returns (uint);

  function getMCR() external view returns (uint);

  function transferAssetToSafe(address assetAddress, address safeAddress, uint amount) external;

  function transferAssetToSwapOperator(address assetAddress, uint amount) external;

  function clearSwapAssetAmount(address assetAddress) external;

  function getAssetForEth(address assetAddress, uint amount) external view returns (uint);

  function getEthForAsset(address assetAddress, uint amount) external view returns (uint);

  function updateMCR() external;

  function updateMCRInternal(bool forceUpdate) external;

  function migrate(address previousPool, address previousMCR) external;

  event MCRUpdated(
    uint mcr,
    uint desiredMCR,
    uint mcrFloor,
    uint mcrETHWithGear,
    uint totalSumAssured
  );

  event Payout(address indexed to, address indexed assetAddress, uint amount);
  event AssetsTransferredToSafe(address assetAddress, uint amount);
  event AssetsTransferredToSwapOperator(address assetAddress, uint amount);

  // migrations
  error AlreadyMigrated();

  // swaps
  error AssetNotFound();
  error InvalidAssetId();
  error OrderInProgress();
  error AssetMustNotBeZeroAddress();
  error AssetAlreadyExists();
  error NoSwapAssetAmountFound();

  // payout
  error EthTransferFailed(address to, uint amount);

  // price feed
  error AggregatorMustNotBeZeroAddress();
  error IncompatibleAggregatorDecimals(address aggregator, uint expectedDecimals, uint aggregatorDecimals);
  error InvalidEthAggregatorType(AggregatorType actual, AggregatorType expected);
  error NonPositiveRate(address aggregator, int rate);

}



// ============================================================
// FILE: contracts/interfaces/IRegistry.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.0;

interface IRegistry {

  struct Contract {
    address addr;
    bool isProxy;
  }

  struct SystemPause {
    uint48 config;
    uint48 proposedConfig;
    address proposer;
  }

  struct MembersMeta {
    uint48 memberCount;
    uint48 lastMemberId;
    address kycAuthAddress;
  }

  /* == EMERGENCY PAUSE == */
  function setEmergencyAdmin(address _emergencyAdmin, bool enabled) external;
  function proposePauseConfig(uint config) external;
  function confirmPauseConfig(uint config) external;
  function getSystemPause() external view returns (SystemPause memory);
  function getPauseConfig() external view returns (uint config);
  function isPaused(uint mask) external view returns (bool);
  function isEmergencyAdmin(address member) external view returns (bool);

  /* == MEMBERSHIP MANAGEMENT == */
  function isMember(address member) external view returns (bool);
  function getMemberId(address member) external view returns (uint);
  function getMemberAddress(uint memberId) external view returns (address);
  function getMemberCount() external view returns (uint);
  function getLastMemberId() external view returns (uint);
  function join(address member, bytes memory signature) external payable;
  function switchTo(address to) external;
  function switchFor(address from, address to) external;
  function leave() external;
  function setKycAuthAddress(address kycAuthAddress) external;
  function getKycAuthAddress() external view returns (address);

  /* == ADVISORY BOARD MANAGEMENT == */
  function isAdvisoryBoardMember(address member) external view returns (bool);
  function isAdvisoryBoardMemberById(uint memberId) external view returns (bool);
  function getAdvisoryBoardSeat(address member) external view returns (uint);
  function getMemberAddressBySeat(uint seat) external view returns (address);
  function swapAdvisoryBoardMember(uint from, uint to) external;

  /* == CONTRACT MANAGEMENT == */
  function isValidContractIndex(uint index) external pure returns (bool);
  function isProxyContract(uint index) external view returns (bool);
  function getContractAddressByIndex(uint index) external view returns (address payable);
  function getContractIndexByAddress(address contractAddress) external view returns (uint);
  function getContracts(uint[] memory indexes) external view returns (Contract[] memory);
  function deployContract(uint index, bytes32 salt, address implementation) external;
  function addContract(uint index, address contractAddress, bool isProxy) external;
  function upgradeContract(uint index, address implementation) external;
  function removeContract(uint index) external;

  /* == MIGRATIONS == */
  function migrateMembers(address[] calldata membersToMigrate) external;
  function migrateAdvisoryBoardMembers(address[] calldata abMembers) external;

  // joined: MembershipChanged(memberId, address(0), current)
  // swapped: MembershipChanged(memberId, previous, current)
  // left: MembershipChanged(memberId, current, address(0))
  event MembershipChanged(uint indexed memberId, address indexed previous, address indexed current);
  event AdvisoryBoardMemberSwapped(uint indexed seat, uint indexed from, uint indexed to);

  event ContractDeployed(uint indexed index, address indexed proxy, address implementation);
  event ContractUpgraded(uint indexed index, address indexed proxy, address implementation);
  event ContractAdded(uint indexed index, address indexed contractAddress, bool isProxy);
  event ContractRemoved(uint indexed index, address indexed contractAddress, bool isProxy);

  event EmergencyAdminSet(address indexed emergencyAdmin, bool enabled);
  event PauseConfigProposed(uint config, address indexed proposer);
  event PauseConfigConfirmed(uint config, address indexed confirmer);

  error ContractAlreadyExists();
  error InvalidContractIndex();
  error InvalidContractAddress();
  error ContractDoesNotExist();
  error ContractIsNotProxy();

  error OnlyEmergencyAdmin();
  error ProposerCannotConfirmPause();
  error PauseConfigMismatch();
  error NoConfigProposed();
  error Paused(uint currentState, uint checks);

  error NotMember();
  error AlreadyMember();
  error AddressAlreadyUsedForJoining();
  error InvalidJoinFee();
  error InvalidSignature();
  error FeeTransferFailed();

  error NotAdvisoryBoardMember();
  error AlreadyAdvisoryBoardMember();
  error AdvisoryBoardMemberCannotLeave();
  error InvalidSeat();

  error OnlyGovernor();
  error NotProxyOwner();
  error NotMemberRoles();

}



// ============================================================
// FILE: contracts/interfaces/IStakingNFT.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.5.0;

import "@openzeppelin/contracts-v4/token/ERC721/IERC721.sol";

interface IStakingNFT is IERC721 {

  function isApprovedOrOwner(address spender, uint tokenId) external returns (bool);

  function mint(uint poolId, address to) external returns (uint tokenId);

  function changeOperator(address newOperator) external;

  function changeNFTDescriptor(address newNFTDescriptor) external;

  function totalSupply() external returns (uint);

  function tokenInfo(uint tokenId) external view returns (uint poolId, address owner);

  function stakingPoolOf(uint tokenId) external view returns (uint poolId);

  function stakingPoolFactory() external view returns (address);

  function name() external view returns (string memory);

  error NotOperator();
  error NotMinted();
  error WrongFrom();
  error InvalidRecipient();
  error InvalidNewOperatorAddress();
  error InvalidNewNFTDescriptorAddress();
  error NotAuthorized();
  error UnsafeRecipient();
  error AlreadyMinted();
  error NotStakingPool();

}



// ============================================================
// FILE: contracts/interfaces/IStakingPool.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.5.0;

/* structs for io */

struct AllocationRequest {
  uint productId;
  uint coverId;
  uint period;
  uint gracePeriod;
  bool useFixedPrice;
  uint capacityRatio;
  uint capacityReductionRatio;
  uint rewardRatio;
  uint productMinPrice;
}

struct DeallocationRequest {
  uint allocationId;
  uint productId;
  uint premium;
  uint start;
  uint period;
  uint rewardsRatio;
}

struct BurnStakeParams {
  uint allocationId;
  uint productId;
  uint start;
  uint period;
  uint deallocationAmount;
}

interface IStakingPool {

  /* structs for storage */

  // stakers are grouped in tranches based on the timelock expiration
  // tranche index is calculated based on the expiration date
  // the initial proposal is to have 4 tranches per year (1 tranche per quarter)
  struct Tranche {
    uint128 stakeShares;
    uint128 rewardsShares;
  }

  struct ExpiredTranche {
    uint96 accNxmPerRewardShareAtExpiry;
    uint96 stakeAmountAtExpiry; // nxm total supply is 6.7e24 and uint96.max is 7.9e28
    uint128 stakeSharesSupplyAtExpiry;
  }

  struct Deposit {
    uint96 lastAccNxmPerRewardShare;
    uint96 pendingRewards;
    uint128 stakeShares;
    uint128 rewardsShares;
  }

  struct WithdrawTrancheContext {
    uint _firstActiveTrancheId;
    uint _accNxmPerRewardsShare;
    uint managerLockedInGovernanceUntil;
    bool withdrawStake;
    bool withdrawRewards;
    address destination;
}

  function initialize(
    bool isPrivatePool,
    uint initialPoolFee,
    uint maxPoolFee,
    uint _poolId
  ) external;

  function processExpirations(bool updateUntilCurrentTimestamp) external;

  function requestAllocation(
    uint amount,
    AllocationRequest calldata request
  ) external returns (uint premium, uint allocationId);

  function requestDeallocation(
    DeallocationRequest calldata request
  ) external;

  function burnStake(uint amount, BurnStakeParams calldata params) external;

  function depositTo(
    uint amount,
    uint trancheId,
    uint requestTokenId,
    address destination
  ) external returns (uint tokenId);

  function withdraw(
    uint tokenId,
    bool withdrawStake,
    bool withdrawRewards,
    uint[] memory trancheIds
  ) external returns (uint withdrawnStake, uint withdrawnRewards);

  function isPrivatePool() external view returns (bool);

  function isHalted() external view returns (bool);

  function manager() external view returns (address);

  function getPoolId() external view returns (uint);

  function getPoolFee() external view returns (uint);

  function getMaxPoolFee() external view returns (uint);

  function getActiveStake() external view returns (uint);

  function getStakeSharesSupply() external view returns (uint);

  function getRewardsSharesSupply() external view returns (uint);

  function getRewardPerSecond() external view returns (uint);

  function getAccNxmPerRewardsShare() external view returns (uint);

  function getLastAccNxmUpdate() external view returns (uint);

  function getFirstActiveTrancheId() external view returns (uint);

  function getFirstActiveBucketId() external view returns (uint);

  function getNextAllocationId() external view returns (uint);

  function getDeposit(uint tokenId, uint trancheId) external view returns (
    uint lastAccNxmPerRewardShare,
    uint pendingRewards,
    uint stakeShares,
    uint rewardsShares
  );

  function getTranche(uint trancheId) external view returns (
    uint stakeShares,
    uint rewardsShares
  );

  function getExpiredTranche(uint trancheId) external view returns (
    uint accNxmPerRewardShareAtExpiry,
    uint stakeAmountAtExpiry,
    uint stakeShareSupplyAtExpiry
  );

  function setPoolFee(uint newFee) external;

  function setPoolPrivacy(bool isPrivatePool) external;

  function getActiveAllocations(
    uint productId
  ) external view returns (uint[] memory trancheAllocations);

  function getTrancheCapacities(
    uint productId,
    uint firstTrancheId,
    uint trancheCount,
    uint capacityRatio,
    uint reductionRatio
  ) external view returns (uint[] memory trancheCapacities);

  /* ========== EVENTS ========== */

  event StakeDeposited(address indexed user, uint256 amount, uint256 trancheId, uint256 tokenId);

  event DepositExtended(address indexed user, uint256 tokenId, uint256 initialTrancheId, uint256 newTrancheId, uint256 topUpAmount);

  event PoolPrivacyChanged(address indexed manager, bool isPrivate);

  event PoolFeeChanged(address indexed manager, uint newFee);

  event Withdraw(address indexed user, uint indexed tokenId, uint tranche, uint amountStakeWithdrawn, uint amountRewardsWithdrawn);

  event StakeBurned(uint amount);

  event Deallocated(uint allocationId);

  event BucketExpired(uint bucketId);

  event TrancheExpired(uint trancheId);

  event ActiveStakeUpdated(uint activeStake, uint stakeSharesSupply);

  event TrancheUpdated(uint trancheId, uint stakeShares, uint stakeSharesSupply);

  event DepositUpdated(uint tokenId, uint trancheId, uint stakeShares, uint stakeSharesSupply);

  // Auth
  error OnlyCoverContract();
  error OnlyStakingProductsContract();
  error OnlyManager();
  error PrivatePool();
  error SystemPaused();
  error PoolHalted();

  // Fees
  error PoolFeeExceedsMax();
  error MaxPoolFeeAbove100();

  // Voting
  error NxmIsLockedForGovernanceVote();
  error ManagerNxmIsLockedForGovernanceVote();

  // Deposit
  error InsufficientDepositAmount();
  error RewardRatioTooHigh();

  // Staking NFTs
  error InvalidTokenId();
  error NotTokenOwnerOrApproved();
  error InvalidStakingPoolForToken();

  // Tranche & capacity
  error NewTrancheEndsBeforeInitialTranche();
  error RequestedTrancheIsNotYetActive();
  error RequestedTrancheIsExpired();
  error InsufficientCapacity();

  // Allocation
  error AlreadyDeallocated(uint allocationId);
  error InvalidAllocationId();
}



// ============================================================
// FILE: contracts/interfaces/IStakingPoolBeacon.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IStakingPoolBeacon {
  /**
   * @dev Must return an address that can be used as a delegate call target.
   *
   * {BeaconProxy} will check that this address is a contract.
   */
  function stakingPoolImplementation() external view returns (address);
}



// ============================================================
// FILE: contracts/interfaces/ITokenController.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.5.0;

import "./INXMToken.sol";

interface ITokenController {

  struct StakingPoolNXMBalances {
    uint128 rewards;
    uint128 deposits;
  }

  struct StakingPoolOwnershipOffer {
    address proposedManager;
    uint96 deadline;
  }

  struct WithdrawAssessment {
    bool stake;
    bool rewards;
  }

  /// @notice The stake deposit / rewards in a staking pool that will be withdrawn.
  /// @dev    Call StakingViewer.getToken to get tokenId / trancheId information
  /// @param tokenId The ID of the token stake deposit / rewards that will be withrawn.
  /// @param trancheIds An array of tranche IDs representing the tranches where the stake was deposited.
  struct StakingPoolDeposit {
    uint tokenId;
    uint[] trancheIds;
  }

  /// @notice Represents the rewards distributed to a staking pool manager.
  /// @dev    Call StakingViewer.getManagerTokenRewardsByAddr to get poolId / trancheId information
  /// @param poolId The ID of the pool managed by the manager.
  /// @param trancheIds An array of tranche IDs representing the tranches where the manager rewards were distributed.
  struct StakingPoolManagerReward {
    uint poolId;
    uint[] trancheIds;
  }

  /* ========== VIEWS ========== */

  function token() external view returns (INXMToken);

  function totalSupply() external view returns (uint);

  function totalBalanceOf(address _of) external view returns (uint amount);

  function totalBalanceOfWithoutDelegations(address _of) external view returns (uint amount);

  function getTokenPrice() external view returns (uint tokenPrice);

  function getStakingPoolManager(uint poolId) external view returns (address manager);

  function getManagerStakingPools(address manager) external view returns (uint[] memory poolIds);

  function isStakingPoolManager(address member) external view returns (bool);

  function getStakingPoolOwnershipOffer(uint poolId) external view returns (address proposedManager, uint deadline);

  function stakingPoolNXMBalances(uint poolId) external view returns (uint128 rewards, uint128 deposits);

  /* ========== MUTATIVE FUNCTIONS ========== */

  function changeOperator(address _newOperator) external;

  function operatorTransfer(address _from, address _to, uint _value) external returns (bool);

  function burnFrom(address _of, uint amount) external returns (bool);

  function addToWhitelist(address _member) external;

  function removeFromWhitelist(address _member) external;

  function switchMembership(address from, address to, bool includeNxmTokens) external;

  function mint(address _member, uint _amount) external;

  function lockForMemberVote(address _of, uint _days) external;

  function assignStakingPoolManager(uint poolId, address manager) external;

  function createStakingPoolOwnershipOffer(uint poolId, address proposedManager, uint deadline) external;

  function acceptStakingPoolOwnershipOffer(uint poolId) external;

  function cancelStakingPoolOwnershipOffer(uint poolId) external;

  function mintStakingPoolNXMRewards(uint amount, uint poolId) external;

  function burnStakingPoolNXMRewards(uint amount, uint poolId) external;

  function depositStakedNXM(address from, uint amount, uint poolId) external;

  function withdrawNXMStakeAndRewards(address to, uint stakeToWithdraw, uint rewardsToWithdraw, uint poolId) external;

  function burnStakedNXM(uint amount, uint poolId) external;
}



// ============================================================
// FILE: contracts/libraries/Math.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.18;

/**
 * @dev Simple library that defines min, max and babylonian sqrt functions
 */
library Math {

  function min(uint a, uint b) internal pure returns (uint) {
    return a < b ? a : b;
  }

  function max(uint a, uint b) internal pure returns (uint) {
    return a > b ? a : b;
  }

  function sum(uint[] memory items) internal pure returns (uint) {
    uint count = items.length;
    uint total;

    for (uint i = 0; i < count; i++) {
      total += items[i];
    }

    return total;
  }

  function divRound(uint a, uint b) internal pure returns (uint) {
    return (a + b / 2) / b;
  }

  function divCeil(uint a, uint b) internal pure returns (uint) {
    return (a + b - 1) / b;
  }

  function roundUp(uint a, uint b) internal pure returns (uint) {
    return divCeil(a, b) * b;
  }

  // babylonian method
  function sqrt(uint y) internal pure returns (uint) {

    if (y > 3) {
      uint z = y;
      uint x = y / 2 + 1;
      while (x < z) {
        z = x;
        x = (y / x + x) / 2;
      }
      return z;
    }

    if (y != 0) {
      return 1;
    }

    return 0;
  }

}



// ============================================================
// FILE: contracts/libraries/SafeUintCast.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @dev Wrappers over Solidity's uintXX casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeUintCast {
  /**
   * @dev Returns the downcasted uint248 from uint256, reverting on
   * overflow (when the input is greater than largest uint248).
   *
   * Counterpart to Solidity's `uint248` operator.
   *
   * Requirements:
   *
   * - input must fit into 248 bits
   */
  function toUint248(uint256 value) internal pure returns (uint248) {
    require(value < 2**248, "SafeCast: value doesn\'t fit in 248 bits");
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
   */
  function toUint240(uint256 value) internal pure returns (uint240) {
    require(value < 2**240, "SafeCast: value doesn\'t fit in 240 bits");
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
   */
  function toUint232(uint256 value) internal pure returns (uint232) {
    require(value < 2**232, "SafeCast: value doesn\'t fit in 232 bits");
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
   */
  function toUint224(uint256 value) internal pure returns (uint224) {
    require(value < 2**224, "SafeCast: value doesn\'t fit in 224 bits");
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
   */
  function toUint216(uint256 value) internal pure returns (uint216) {
    require(value < 2**216, "SafeCast: value doesn\'t fit in 216 bits");
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
   */
  function toUint208(uint256 value) internal pure returns (uint208) {
    require(value < 2**208, "SafeCast: value doesn\'t fit in 208 bits");
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
   */
  function toUint200(uint256 value) internal pure returns (uint200) {
    require(value < 2**200, "SafeCast: value doesn\'t fit in 200 bits");
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
   */
  function toUint192(uint256 value) internal pure returns (uint192) {
    require(value < 2**192, "SafeCast: value doesn\'t fit in 192 bits");
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
   */
  function toUint184(uint256 value) internal pure returns (uint184) {
    require(value < 2**184, "SafeCast: value doesn\'t fit in 184 bits");
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
   */
  function toUint176(uint256 value) internal pure returns (uint176) {
    require(value < 2**176, "SafeCast: value doesn\'t fit in 176 bits");
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
   */
  function toUint168(uint256 value) internal pure returns (uint168) {
    require(value < 2**168, "SafeCast: value doesn\'t fit in 168 bits");
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
   */
  function toUint160(uint256 value) internal pure returns (uint160) {
    require(value < 2**160, "SafeCast: value doesn\'t fit in 160 bits");
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
   */
  function toUint152(uint256 value) internal pure returns (uint152) {
    require(value < 2**152, "SafeCast: value doesn\'t fit in 152 bits");
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
   */
  function toUint144(uint256 value) internal pure returns (uint144) {
    require(value < 2**144, "SafeCast: value doesn\'t fit in 144 bits");
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
   */
  function toUint136(uint256 value) internal pure returns (uint136) {
    require(value < 2**136, "SafeCast: value doesn\'t fit in 136 bits");
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
   */
  function toUint128(uint256 value) internal pure returns (uint128) {
    require(value < 2**128, "SafeCast: value doesn\'t fit in 128 bits");
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
   */
  function toUint120(uint256 value) internal pure returns (uint120) {
    require(value < 2**120, "SafeCast: value doesn\'t fit in 120 bits");
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
   */
  function toUint112(uint256 value) internal pure returns (uint112) {
    require(value < 2**112, "SafeCast: value doesn\'t fit in 112 bits");
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
   */
  function toUint104(uint256 value) internal pure returns (uint104) {
    require(value < 2**104, "SafeCast: value doesn\'t fit in 104 bits");
    return uint104(value);
  }

  /**
   * @dev Returns the downcasted uint96 from uint256, reverting on
   * overflow (when the input is greater than largest uint96).
   *
   * Counterpart to Solidity's `uint104` operator.
   *
   * Requirements:
   *
   * - input must fit into 96 bits
   */
  function toUint96(uint256 value) internal pure returns (uint96) {
    require(value < 2**96, "SafeCast: value doesn\'t fit in 96 bits");
    return uint96(value);
  }

  /**
   * @dev Returns the downcasted uint88 from uint256, reverting on
   * overflow (when the input is greater than largest uint88).
   *
   * Counterpart to Solidity's `uint104` operator.
   *
   * Requirements:
   *
   * - input must fit into 88 bits
   */
  function toUint88(uint256 value) internal pure returns (uint88) {
    require(value < 2**88, "SafeCast: value doesn\'t fit in 88 bits");
    return uint88(value);
  }

  /**
   * @dev Returns the downcasted uint80 from uint256, reverting on
   * overflow (when the input is greater than largest uint80).
   *
   * Counterpart to Solidity's `uint104` operator.
   *
   * Requirements:
   *
   * - input must fit into 80 bits
   */
  function toUint80(uint256 value) internal pure returns (uint80) {
    require(value < 2**80, "SafeCast: value doesn\'t fit in 80 bits");
    return uint80(value);
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
   */
  function toUint64(uint256 value) internal pure returns (uint64) {
    require(value < 2**64, "SafeCast: value doesn\'t fit in 64 bits");
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
   */
  function toUint56(uint256 value) internal pure returns (uint56) {
    require(value < 2**56, "SafeCast: value doesn\'t fit in 56 bits");
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
   */
  function toUint48(uint256 value) internal pure returns (uint48) {
    require(value < 2**48, "SafeCast: value doesn\'t fit in 48 bits");
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
   */
  function toUint40(uint256 value) internal pure returns (uint40) {
    require(value < 2**40, "SafeCast: value doesn\'t fit in 40 bits");
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
   */
  function toUint32(uint256 value) internal pure returns (uint32) {
    require(value < 2**32, "SafeCast: value doesn\'t fit in 32 bits");
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
   */
  function toUint24(uint256 value) internal pure returns (uint24) {
    require(value < 2**24, "SafeCast: value doesn\'t fit in 24 bits");
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
   */
  function toUint16(uint256 value) internal pure returns (uint16) {
    require(value < 2**16, "SafeCast: value doesn\'t fit in 16 bits");
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
   * - input must fit into 8 bits.
   */
  function toUint8(uint256 value) internal pure returns (uint8) {
    require(value < 2**8, "SafeCast: value doesn\'t fit in 8 bits");
    return uint8(value);
  }
}



// ============================================================
// FILE: contracts/libraries/StakingPoolLibrary.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.18;

/**
 * @dev Simple library to derive the staking pool address from the pool id without external calls
 */
library StakingPoolLibrary {

  function getAddress(address factory, uint poolId) internal pure returns (address) {

    bytes32 hash = keccak256(
      abi.encodePacked(
        hex'ff',
        factory,
        poolId, // salt
        // init code hash of the MinimalBeaconProxy
        // updated using patch-staking-pool-library.js script
        hex'1eb804b66941a2e8465fa0951be9c8b855b7794ee05b0789ab22a02ee1298ebe' // init code hash
      )
    );

    // cast last 20 bytes of hash to address
    return address(uint160(uint(hash)));
  }

}



// ============================================================
// FILE: contracts/modules/cover/Cover.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.28;

import "@openzeppelin/contracts-v4/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-v4/token/ERC20/utils/SafeERC20.sol";

import "../../abstract/EIP712.sol";
import "../../abstract/Multicall.sol";
import "../../abstract/ReentrancyGuard.sol";
import "../../abstract/RegistryAware.sol";
import "../../interfaces/ICover.sol";
import "../../interfaces/ICoverNFT.sol";
import "../../interfaces/IPool.sol";
import "../../interfaces/IStakingNFT.sol";
import "../../interfaces/IStakingPool.sol";
import "../../interfaces/ITokenController.sol";
import "../../libraries/Math.sol";
import "../../libraries/SafeUintCast.sol";
import "../../libraries/StakingPoolLibrary.sol";

contract Cover is ICover, EIP712, RegistryAware, ReentrancyGuard, Multicall {
  using SafeERC20 for IERC20;
  using SafeUintCast for uint;

  /* ========== STATE VARIABLES ========== */

  uint[9] private __unused_0; // slots 0 - 8

  mapping(uint assetId => ActiveCover) public activeCover;
  mapping(uint assetId => mapping(uint bucketId => uint amount)) internal activeCoverExpirationBuckets;

  uint[2] private __unused_11; // slots 11 - 12

  mapping(uint coverId => CoverData) private _coverData;
  mapping(uint coverId => PoolAllocation[]) private _poolAllocations;
  mapping(uint coverId => CoverReference) private _coverReference;
  mapping(uint coverId => string ipfsMetadata) private _coverMetadata;

  mapping(uint coverId => Ri) private _coverRi;
  mapping(uint providerId => RiConfig) private _riProviderConfigs;
  address public riSigner;

  /* ========== CONSTANTS ========== */

  uint private constant GLOBAL_CAPACITY_RATIO = 20000; // 2
  uint private constant GLOBAL_REWARDS_RATIO = 5000; // 50%

  uint private constant COMMISSION_DENOMINATOR = 10000;
  uint private constant GLOBAL_CAPACITY_DENOMINATOR = 10_000;

  uint private constant MAX_COVER_PERIOD = 365 days;
  uint private constant MIN_COVER_PERIOD = 28 days;
  uint private constant BUCKET_SIZE = 7 days;

  uint public constant MAX_COMMISSION_RATIO = 3000; // 30%

  uint public constant DEFAULT_MIN_PRICE_RATIO = 100; // 1%

  uint private constant ONE_NXM = 1e18;

  uint private constant ETH_ASSET_ID = 0;
  uint private constant NXM_ASSET_ID = type(uint8).max;

  // internally we store capacity using 2 decimals
  // 1 nxm of capacity is stored as 100
  uint private constant ALLOCATION_UNITS_PER_NXM = 100;

  // given capacities have 2 decimals
  // smallest unit we can allocate is 1e18 / 100 = 1e16 = 0.01 NXM
  uint public constant NXM_PER_ALLOCATION_UNIT = ONE_NXM / ALLOCATION_UNITS_PER_NXM;

  bytes32 private constant BUY_COVER_WITH_RI_TYPEHASH = keccak256(
    abi.encodePacked(
      "RiQuote(",
      "uint256 coverId,",
      "uint24 productId,",
      "uint256 providerId,",
      "uint256 amount,",
      "uint256 premium,",
      "uint32 period,",
      "uint8 coverAsset,",
      "bytes data,",
      "uint8 dataFormat,",
      "uint32 deadline,",
      "uint256 nonce)"
    )
  );

  IPool public immutable pool;
  ITokenController public immutable tokenController;
  ICoverProducts public immutable coverProducts;
  ICoverNFT public immutable override coverNFT;
  IStakingNFT public immutable override stakingNFT;
  address public immutable override stakingPoolFactory;
  address public immutable override stakingPoolImplementation;
  address public immutable claims;

  /* ========== CONSTRUCTOR ========== */

  constructor(
    address _registry,
    address _stakingPoolImplementation,
    address _verifyingAddress
  ) RegistryAware(_registry) EIP712("NexusMutualCover", "1.0.0", _verifyingAddress) {

    // fetch deps
    coverNFT = ICoverNFT(fetch(C_COVER_NFT));
    coverProducts = ICoverProducts(fetch(C_COVER_PRODUCTS));
    pool = IPool(fetch(C_POOL));
    stakingNFT = IStakingNFT(fetch(C_STAKING_NFT));
    stakingPoolFactory = fetch(C_STAKING_POOL_FACTORY);
    tokenController = ITokenController(fetch(C_TOKEN_CONTROLLER));

    // store staking pool implementation
    stakingPoolImplementation = _stakingPoolImplementation;
  }

  /* === MUTATIVE FUNCTIONS ==== */

  /// @dev Entrypoint for users buying a cover by interacting with this contract directly
  function buyCover(
    BuyCoverParams memory params,
    PoolAllocationRequest[] memory poolAllocationRequests
  ) external payable onlyMember returns (uint coverId) {

    if (params.coverId != 0) {
      require(coverNFT.isApprovedOrOwner(msg.sender, params.coverId), OnlyOwnerOrApproved());
      require(_coverRi[params.coverId].amount == 0, WrongCoverEditEntrypoint());
    }

    coverId = _buyCover(
      params,
      poolAllocationRequests,
      0, // no riPremium
      address(0) // no riPremiumDestination
    );

    emit CoverBought(
      coverId,
      params.coverId != 0 ? params.coverId : coverId,
      registry.getMemberId(msg.sender),
      params.productId
    );

    return coverId;
  }

  /// @dev Entrypoint for LimitOrders contract
  function executeCoverBuy(
    BuyCoverParams memory params,
    PoolAllocationRequest[] memory poolAllocationRequests,
    address buyer
  ) external payable onlyContracts(C_LIMIT_ORDERS) returns (uint coverId) {

    if (params.coverId != 0) {
      require(coverNFT.isApprovedOrOwner(buyer, params.coverId), OnlyOwnerOrApproved());
      require(_coverRi[params.coverId].amount == 0, WrongCoverEditEntrypoint());
    }

    coverId = _buyCover(
      params,
      poolAllocationRequests,
      0, // no riPremium
      address(0) // no riPremiumDestination
    );

    emit CoverBought(
      coverId,
      params.coverId != 0 ? params.coverId : coverId,
      registry.getMemberId(buyer),
      params.productId
    );

    return coverId;
  }

  /// @dev Entrypoint for Users buying cover with ri
  function buyCoverWithRi(
    BuyCoverParams memory params,
    PoolAllocationRequest[] memory poolAllocationRequests,
    RiRequest memory riRequest
  ) external payable onlyMember returns (uint coverId) {

    require(riRequest.deadline > block.timestamp, SignatureExpired());

    if (params.coverId != 0) {
      require(coverNFT.isApprovedOrOwner(msg.sender, params.coverId), OnlyOwnerOrApproved());
    } else {
      // ri amount should be non-zero on first cover buy, but allowed to be zero on edits
      require(riRequest.amount > 0, RiAmountIsZero());
    }

    RiConfig storage riConfig = _riProviderConfigs[riRequest.providerId];
    address riPremiumDestination = riConfig.premiumDestination;
    uint nonce = riConfig.nextNonce++; // SLOAD + SSTORE

    require(riPremiumDestination != address(0), InvalidRiConfig());

    bytes memory message = abi.encode(
      BUY_COVER_WITH_RI_TYPEHASH,
      params.coverId,
      params.productId,
      riRequest.providerId,
      riRequest.amount,
      riRequest.premium,
      params.period,
      params.coverAsset,
      keccak256(riRequest.data),
      riRequest.dataFormat,
      riRequest.deadline,
      nonce
    );

    require(recoverSigner(message, riRequest.signature) == riSigner, InvalidSignature());
    require(params.paymentAsset == params.coverAsset, InvalidPaymentAsset());

    coverId = _buyCover(params, poolAllocationRequests, riRequest.premium, riPremiumDestination);

    _coverRi[coverId].providerId = riRequest.providerId.toUint24();
    _coverRi[coverId].amount = riRequest.amount.toUint96();

    emit CoverBought(
      coverId,
      params.coverId != 0 ? params.coverId : coverId,
      registry.getMemberId(msg.sender),
      params.productId
    );
    emit CoverRiAllocated(coverId, riRequest.premium, params.paymentAsset, riRequest.data, riRequest.dataFormat);

    return coverId;
  }

  function _buyCover(
    BuyCoverParams memory params,
    PoolAllocationRequest[] memory poolAllocationRequests,
    uint riPremiumInPaymentAsset,
    address riPremiumDestination
  ) internal nonReentrant whenNotPaused(PAUSE_COVER) returns (uint coverId) {

    require(params.period >= MIN_COVER_PERIOD, CoverPeriodTooShort());
    require(params.period <= MAX_COVER_PERIOD, CoverPeriodTooLong());
    require(params.commissionRatio <= MAX_COMMISSION_RATIO, CommissionRateTooHigh());

    // using riPremium as a proxy for the riAmount
    require(params.amount != 0 || riPremiumInPaymentAsset != 0, CoverAmountIsZero());

    // can pay with cover asset or nxm only
    require(params.paymentAsset == params.coverAsset || params.paymentAsset == NXM_ASSET_ID, InvalidPaymentAsset());

    // new cover
    coverId = coverNFT.mint(params.owner);
    _coverMetadata[coverId] = params.ipfsData;

    uint premiumInPaymentAsset;

    {
      uint nxmPriceInCoverAsset = pool.getInternalTokenPriceInAssetAndUpdateTwap(params.coverAsset);
      uint amountDueInNXM = _createCover(params, poolAllocationRequests, coverId, nxmPriceInCoverAsset);
      premiumInPaymentAsset = params.coverAsset == params.paymentAsset
        ? nxmPriceInCoverAsset * amountDueInNXM / ONE_NXM
        : amountDueInNXM;
    }

    _retrievePayment(
      params.paymentAsset,
      premiumInPaymentAsset,
      riPremiumInPaymentAsset,
      params.maxPremiumInAsset + riPremiumInPaymentAsset,
      riPremiumDestination,
      params.commissionRatio,
      params.commissionDestination
    );
  }

  function _createCover(
    BuyCoverParams memory params,
    PoolAllocationRequest[] memory poolAllocationRequests,
    uint coverId,
    uint nxmPriceInCoverAsset
  ) internal returns (uint amountDueInNXM) {

    uint previousCoverAmount;
    uint previousCoverExpiration;
    uint refundedPremium;

    if (params.coverId != 0) {

      CoverReference memory coverReference = getCoverReference(params.coverId);
      require(coverReference.originalCoverId == params.coverId, MustBeOriginalCoverId(coverReference.originalCoverId));

      CoverData memory cover = _coverData[coverReference.latestCoverId];
      previousCoverAmount = cover.amount;
      previousCoverExpiration = cover.start + cover.period;

      require(block.timestamp < previousCoverExpiration, ExpiredCoversCannotBeEdited());
      require(params.coverAsset == cover.coverAsset, CoverAssetMismatch());

      refundedPremium = _requestDeallocation(
        cover,
        coverReference.latestCoverId,
        previousCoverExpiration - block.timestamp // remaining period
      );

      // mark previous cover as ending now
      cover.period = (block.timestamp - cover.start).toUint32();
      _coverData[coverReference.latestCoverId] = cover;

      _coverReference[coverId].originalCoverId = params.coverId.toUint32();
      _coverReference[params.coverId].latestCoverId = coverId.toUint32();
    }

    AllocationRequest memory allocationRequest;

    {
      require(params.productId < coverProducts.getProductCount(), ProductNotFound());

      (
        Product memory product,
        ProductType memory productType
      ) = coverProducts.getProductWithType(params.productId);

      require(!product.isDeprecated, ProductDeprecated());
      require(_isCoverAssetSupported(params.coverAsset, product.coverAssets), CoverAssetNotSupported());

      allocationRequest = AllocationRequest(
        params.productId,
        coverId,
        params.period,
        productType.gracePeriod,
        product.useFixedPrice,
        GLOBAL_CAPACITY_RATIO,
        product.capacityReductionRatio,
        GLOBAL_REWARDS_RATIO,
        product.minPrice != 0 ? product.minPrice : DEFAULT_MIN_PRICE_RATIO
      );
    }

    (uint coverAmountInCoverAsset, uint totalPremiumInNxm) = _requestAllocation(
      allocationRequest,
      poolAllocationRequests,
      nxmPriceInCoverAsset
    );

    require(coverAmountInCoverAsset >= params.amount, InsufficientCoverAmountAllocated());

    _coverData[coverId] = CoverData(
      params.productId,
      params.coverAsset,
      coverAmountInCoverAsset.toUint96(),
      block.timestamp.toUint32(),
      params.period,
      allocationRequest.gracePeriod.toUint32(),
      GLOBAL_REWARDS_RATIO.toUint16(),
      GLOBAL_CAPACITY_RATIO.toUint16()
    );

    _updateTotalActiveCoverAmount(
      params.coverAsset,
      coverAmountInCoverAsset,
      block.timestamp + params.period,
      previousCoverAmount,
      previousCoverExpiration
    );

    // cap refund at new cover premium
    return totalPremiumInNxm > refundedPremium
      ? totalPremiumInNxm - refundedPremium
      : 0;
  }

  function expireCover(uint coverId) external {

    CoverData memory cover = _coverData[coverId];
    uint expiration = cover.start + cover.period;
    uint allocationsLength = _poolAllocations[coverId].length;

    require(block.timestamp >= expiration, CoverNotYetExpired(coverId));

    for (uint allocationIndex = 0; allocationIndex < allocationsLength; allocationIndex++) {
      // fetch allocation
      PoolAllocation memory allocation = _poolAllocations[coverId][allocationIndex];

      // construct deallocation request
      DeallocationRequest memory deallocationRequest = DeallocationRequest(
        allocation.allocationId,
        cover.productId,
        0, // premium
        cover.start,
        cover.period,
        cover.rewardsRatio
      );

      // request deallocation
      stakingPool(allocation.poolId).requestDeallocation(deallocationRequest);
    }

    _updateTotalActiveCoverAmount(
      cover.coverAsset,
      0, // new cover amount
      0, // new cover expiration
      cover.amount, // previous cover amount
      expiration // previous cover expiration
    );
  }

  function _requestAllocation(
    AllocationRequest memory allocationRequest,
    PoolAllocationRequest[] memory allocationRequests,
    uint nxmPriceInCoverAsset
  ) internal returns (
    uint totalCoverAmountInCoverAsset,
    uint totalPremiumInNXM
  ) {

    uint totalCoverAmountInNXM;

    for (uint i = 0; i < allocationRequests.length; i++) {

      // converting asset amount to nxm and rounding up to the nearest NXM_PER_ALLOCATION_UNIT
      uint coverAmountInNXM = Math.roundUp(
        Math.divCeil(allocationRequests[i].coverAmountInAsset * ONE_NXM, nxmPriceInCoverAsset),
        NXM_PER_ALLOCATION_UNIT
      );

      (uint premiumInNXM, uint allocationId) = stakingPool(allocationRequests[i].poolId).requestAllocation(
        coverAmountInNXM,
        allocationRequest
      );

      _poolAllocations[allocationRequest.coverId].push(
        PoolAllocation(
          allocationRequests[i].poolId.toUint40(),
          coverAmountInNXM.toUint96(),
          premiumInNXM.toUint96(),
          allocationId.toUint24()
        )
      );

      totalPremiumInNXM += premiumInNXM;
      totalCoverAmountInNXM += coverAmountInNXM;
    }

    totalCoverAmountInCoverAsset = totalCoverAmountInNXM * nxmPriceInCoverAsset / ONE_NXM;

    return (totalCoverAmountInCoverAsset, totalPremiumInNXM);
  }

  function _requestDeallocation(
    CoverData memory cover,
    uint coverId,
    uint remainingPeriod
  ) internal returns (uint refundedPremium) {

    uint allocationsLength = _poolAllocations[coverId].length;

    for (uint allocationIndex = 0; allocationIndex < allocationsLength; allocationIndex++) {
      // fetch allocation
      PoolAllocation memory allocation = _poolAllocations[coverId][allocationIndex];

      // refund = premium * remaining_period / cover_period
      refundedPremium += allocation.premiumInNXM * remainingPeriod / cover.period;

      // construct deallocation request
      DeallocationRequest memory deallocationRequest = DeallocationRequest(
        allocation.allocationId,
        cover.productId,
        allocation.premiumInNXM,
        cover.start,
        cover.period,
        cover.rewardsRatio
      );

      // request deallocation
      stakingPool(allocation.poolId).requestDeallocation(deallocationRequest);
    }

    return refundedPremium;
  }

  function _retrievePayment(
    uint paymentAsset,
    uint premium,
    uint riPremium,
    uint maxAmountInAsset,
    address riPremiumDestination,
    uint commissionRatio,
    address commissionDestination
  ) internal {

    uint totalPremium = premium + riPremium;
    uint totalPremiumWithCommission = totalPremium * COMMISSION_DENOMINATOR / (COMMISSION_DENOMINATOR - commissionRatio);
    uint commission = totalPremiumWithCommission - totalPremium;

    require(totalPremiumWithCommission <= maxAmountInAsset, PriceExceedsMaxPremiumInAsset());
    require(msg.value == 0 || paymentAsset == ETH_ASSET_ID, UnexpectedEthSent());

    // NXM payment
    if (paymentAsset == NXM_ASSET_ID) {

      // no ri premium when paying with nxm
      require(riPremium == 0, UnexpectedRiPremium());

      tokenController.burnFrom(msg.sender, premium);

      if (commission > 0) {
        // commission transfer reverts if the commissionDestination is not a member
        tokenController.operatorTransfer(msg.sender, commissionDestination, commission);
      }

      return;
    }

    // ETH payment
    if (paymentAsset == ETH_ASSET_ID) {

      require(msg.value >= totalPremiumWithCommission, InsufficientEthSent());

      uint remainder = msg.value - totalPremiumWithCommission;

      if (premium > 0) {
        // send premium in eth to the pool
        // solhint-disable-next-line avoid-low-level-calls
        (bool ok, /* data */) = address(pool).call{value: premium}("");
        require(ok, ETHTransferFailed(address(pool), premium));
      }

      if (riPremium > 0) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool ok, /* data */) = address(riPremiumDestination).call{value: riPremium}("");
        require(ok, ETHTransferFailed(riPremiumDestination, riPremium));
      }

      // send commission
      if (commission > 0) {
        (bool ok, /* data */) = address(commissionDestination).call{value: commission}("");
        require(ok, ETHTransferFailed(commissionDestination, commission));
      }

      if (remainder > 0) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool ok, /* data */) = address(msg.sender).call{value: remainder}("");
        require(ok, ETHTransferFailed(msg.sender, remainder));
      }

      return;
    }

    address coverAsset = pool.getAsset(paymentAsset).assetAddress;
    IERC20 token = IERC20(coverAsset);

    if (premium > 0) {
      token.safeTransferFrom(msg.sender, address(pool), premium);
    }

    if (riPremium > 0) {
      token.safeTransferFrom(msg.sender, riPremiumDestination, riPremium);
    }

    if (commission > 0) {
      token.safeTransferFrom(msg.sender, commissionDestination, commission);
    }
  }

  function updateTotalActiveCoverAmount(uint coverAsset) public {
    _updateTotalActiveCoverAmount(coverAsset, 0, 0, 0, 0);
  }

  function _updateTotalActiveCoverAmount(
    uint coverAsset,
    uint addedCoverAmount,
    uint addedCoverExpiration,
    uint removedCoverAmount,
    uint removedCoverExpiration
  ) internal {

    ActiveCover memory _activeCover = activeCover[coverAsset];
    uint totalActiveCover = _activeCover.totalActiveCoverInAsset;
    uint currentBucketId = block.timestamp / BUCKET_SIZE;

    // process expirations
    if (totalActiveCover != 0) {
      uint lastUpdateId = _activeCover.lastBucketUpdateId;
      while (lastUpdateId < currentBucketId) {
        ++lastUpdateId;
        totalActiveCover -= activeCoverExpirationBuckets[coverAsset][lastUpdateId];
      }
    }

    // add new cover amount
    if (addedCoverAmount != 0) {
      uint bucketID = Math.divCeil(addedCoverExpiration, BUCKET_SIZE);
      activeCoverExpirationBuckets[coverAsset][bucketID] += addedCoverAmount;
      totalActiveCover += addedCoverAmount;
    }

    // remove old cover amount
    uint previousExpirationBucketID = Math.divCeil(removedCoverExpiration, BUCKET_SIZE);

    if (removedCoverAmount != 0 && previousExpirationBucketID > currentBucketId) {
      totalActiveCover -= removedCoverAmount;
      activeCoverExpirationBuckets[coverAsset][previousExpirationBucketID] -= removedCoverAmount;
    }

    // update tracked active cover amount
    _activeCover.lastBucketUpdateId = currentBucketId.toUint64();
    _activeCover.totalActiveCoverInAsset = totalActiveCover.toUint192();

    // sstore
    activeCover[coverAsset] = _activeCover;
  }

  function burnStake(uint coverId, uint payoutAmountInAsset) external onlyContracts(C_CLAIMS) override {

    CoverData memory cover = _coverData[coverId];

    uint allocationsLength = _poolAllocations[coverId].length;

    for (uint i = 0; i < allocationsLength; i++) {
      PoolAllocation memory allocation = _poolAllocations[coverId][i];

      uint deallocationAmountInNXM = allocation.coverAmountInNXM * payoutAmountInAsset / cover.amount;
      uint burnAmountInNxm = deallocationAmountInNXM * GLOBAL_CAPACITY_DENOMINATOR / cover.capacityRatio;

      BurnStakeParams memory params = BurnStakeParams(
        allocation.allocationId,
        cover.productId,
        cover.start,
        cover.period,
        deallocationAmountInNXM
      );

      stakingPool(allocation.poolId).burnStake(burnAmountInNxm, params);

      allocation.coverAmountInNXM -= deallocationAmountInNXM.toUint96();
      allocation.premiumInNXM -= (allocation.premiumInNXM * payoutAmountInAsset / cover.amount).toUint96();

      // sstore
      _poolAllocations[coverId][i] = allocation;
    }

    _updateTotalActiveCoverAmount(
      cover.coverAsset,
      0, // new cover amount
      0, // new cover expiration
      payoutAmountInAsset, // previous cover amount
      cover.start + cover.period // previous cover expiration
    );

    // update && sstore
    cover.amount -= payoutAmountInAsset.toUint96();
    _coverData[coverId] = cover;
  }

  /* ========== VIEWS ========== */

  function getCoverData(uint coverId) external override view returns (CoverData memory) {
    return _coverData[coverId];
  }

  function getCoverRi(uint coverId) external override view returns (Ri memory) {
    return _coverRi[coverId];
  }

  function getCoverDataWithRi(uint coverId) external override view returns (CoverData memory, Ri memory) {
    return (_coverData[coverId], _coverRi[coverId]);
  }

  function getCoverReference(uint coverId) public override view returns(CoverReference memory coverReference) {
    coverReference = _coverReference[coverId];
    coverReference.originalCoverId = coverReference.originalCoverId != 0 ? coverReference.originalCoverId : coverId.toUint32();
    coverReference.latestCoverId = coverReference.latestCoverId != 0 ? coverReference.latestCoverId : coverId.toUint32();
  }

  function getCoverDataWithReference(uint coverId) external override view returns (CoverData memory, CoverReference memory) {
    return (_coverData[coverId], getCoverReference(coverId));
  }

  function getCoverMetadata(uint coverId) external override view returns (string memory) {
    return _coverMetadata[coverId];
  }

  function getPoolAllocations(uint coverId) external override view returns (PoolAllocation[] memory) {
    return _poolAllocations[coverId];
  }

  function getCoverDataCount() external override view returns (uint) {
    return coverNFT.totalSupply();
  }

  function getLatestEditCoverData(uint coverId) external override view returns (CoverData memory) {
    CoverReference memory coverReference = getCoverReference(coverId);
    return _coverData[coverReference.latestCoverId];
  }

  function getRiProviderConfig(uint providerId) external override view returns (RiConfig memory) {
    return _riProviderConfigs[providerId];
  }

  /* ========== COVER ASSETS HELPERS ========== */

  function recalculateActiveCoverInAsset(uint coverAsset) public {
    uint currentBucketId = block.timestamp / BUCKET_SIZE;
    uint totalActiveCover = 0;
    uint yearlyBucketsCount = Math.divCeil(MAX_COVER_PERIOD, BUCKET_SIZE);

    for (uint i = 1; i <= yearlyBucketsCount; i++) {
      uint bucketId = currentBucketId + i;
      totalActiveCover += activeCoverExpirationBuckets[coverAsset][bucketId];
    }

    activeCover[coverAsset] = ActiveCover(totalActiveCover.toUint192(), currentBucketId.toUint64());
  }

  function totalActiveCoverInAsset(uint assetId) public view returns (uint) {
    return uint(activeCover[assetId].totalActiveCoverInAsset);
  }

  function getGlobalCapacityRatio() external pure returns (uint) {
    return GLOBAL_CAPACITY_RATIO;
  }

  function getGlobalRewardsRatio() external pure returns (uint) {
    return GLOBAL_REWARDS_RATIO;
  }

  function getDefaultMinPriceRatio() external pure returns (uint) {
    return DEFAULT_MIN_PRICE_RATIO;
  }

  function getGlobalCapacityAndPriceRatios() external pure returns (
    uint _globalCapacityRatio,
    uint _defaultMinPriceRatio
  ) {
    _globalCapacityRatio = GLOBAL_CAPACITY_RATIO;
    _defaultMinPriceRatio = DEFAULT_MIN_PRICE_RATIO;
  }

  function _isCoverAssetSupported(uint assetId, uint productCoverAssetsBitmap) internal view returns (bool) {

    if (
      // product does not use default cover assets
      productCoverAssetsBitmap != 0 &&
      // asset id is not in the product's cover assets bitmap
      ((1 << assetId) & productCoverAssetsBitmap == 0)
    ) {
      return false;
    }

    Asset memory asset = pool.getAsset(assetId);

    return asset.isCoverAsset && !asset.isAbandoned;
  }

  function stakingPool(uint poolId) public view returns (IStakingPool) {
    return IStakingPool(
      StakingPoolLibrary.getAddress(address(stakingPoolFactory), poolId)
    );
  }

  function setRiSigner(address _riSigner) external onlyContracts(C_GOVERNOR) {
    riSigner = _riSigner;
  }

  function setRiConfig(uint providerId, address premiumDestination) external onlyContracts(C_GOVERNOR) {
    _riProviderConfigs[providerId].premiumDestination = premiumDestination;
  }

  function changeCoverNFTDescriptor(address _coverNFTDescriptor) external onlyContracts(C_GOVERNOR) {
    coverNFT.changeNFTDescriptor(_coverNFTDescriptor);
  }

  function changeStakingNFTDescriptor(address _stakingNFTDescriptor) external onlyContracts(C_GOVERNOR) {
    stakingNFT.changeNFTDescriptor(_stakingNFTDescriptor);
  }

  // one-time migration function

  error IpfsMetadataAlreadySet();

  function populateIpfsMetadata(
    uint[] memory coverIds,
    string[] memory ipfsMetadata
  ) external onlyAdvisoryBoard() {
    for (uint i = 0; i < coverIds.length; i++) {
      require(bytes(_coverMetadata[coverIds[i]]).length == 0, IpfsMetadataAlreadySet());
      _coverMetadata[coverIds[i]] = ipfsMetadata[i];
    }
  }

}
