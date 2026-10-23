// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xc477032db5ccbea767fa74ab76556ba15a06de5b
// Contract Name: PushSender



// ============================================================
// FILE: src/PushSender/PushSender.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./ValidationSender.sol";
import "./Messages.sol";
import "../libraries/UnsafeMath.sol";

contract PushSender is ValidationSender, Messages {
    using SafeERC20 for IERC20;
    using SafeTransferLib for IERC20;
    using Address for address payable;
    using Address for address;
    using UnsafeMath for uint256;

    address public constant ETH_ADDRESS = 0x000000000000000000000000000000000000bEEF;

    IPermit2 public permit2;

    event Multisent(uint256 total, IERC20 tokenAddress);
    event Permit2Set(address permit2);
    event ReferralModeUpdated(bool newMode);

    constructor(
        uint256 _fee,
        uint256 _referralFee,
        address payable _beneficiary20,
        address payable _beneficiary80,
        VipTier[] memory _tiers,
        address _permit2Addr
    ) {
        require(_fee >= _referralFee, "Referral fee can't be more than service fee");
        referralFee = _referralFee;
        fee = _fee;
        require(_beneficiary20 != address(0), "Beneficiary20 can't be zero address");
        beneficiary20 = _beneficiary20;
        require(_beneficiary80 != address(0), "Beneficiary80 can't be zero address");
        beneficiary80 = _beneficiary80;

        for (uint8 i = 0; i < _tiers.length; i++) {
            require(_tiers[i].price != 0, "Price can't be zero");
            require(_tiers[i].duration != 0, "Duration can't be zero");
            tiers.push(_tiers[i]);
        }

        if (_permit2Addr != address(0)) {
            permit2 = IPermit2(_permit2Addr);
        }
    }

    function multisendEther(Recipient[] calldata recipients) external payable returns (uint256 gasLeft) {
        return _multisendEther(recipients, payable(msg.sender), 0);
    }

    function multisendEtherWithSignature(Recipient[] calldata recipients, bytes calldata signature, uint256 deadline)
        external
        payable
        returns (uint256 gasLeft)
    {
        return _multisendEtherWithSignature(recipients, signature, deadline, false, 0);
    }

    function multisendEtherWithPersonalSignature(
        Recipient[] calldata recipients,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendEtherWithSignature(recipients, signature, deadline, true, 0);
    }

    function multisendEtherWithContractSignature(
        Recipient[] calldata recipients,
        address signer,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "The signature has expired");
        checkContractApprove(signer, msg.sender, deadline, signature);
        return _multisendEther(recipients, payable(signer), 0);
    }

    function multisendEthGasLimit(Recipient[] calldata recipients, uint256 etherTransferGasLimit)
        external
        payable
        returns (uint256 gasLeft)
    {
        return _multisendEther(recipients, payable(msg.sender), etherTransferGasLimit);
    }

    function multisendEthSignatureGasLimit(
        Recipient[] calldata recipients,
        uint256 etherTransferGasLimit,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendEtherWithSignature(recipients, signature, deadline, false, etherTransferGasLimit);
    }

    function multisendEthPersonalSignatureGasLimit(
        Recipient[] calldata recipients,
        uint256 etherTransferGasLimit,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendEtherWithSignature(recipients, signature, deadline, true, etherTransferGasLimit);
    }

    function multisendEthContractSignatureGasLimit(
        Recipient[] calldata recipients,
        uint256 etherTransferGasLimit,
        address signer,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "The signature has expired");
        checkContractApprove(signer, msg.sender, deadline, signature);
        return _multisendEther(recipients, payable(signer), etherTransferGasLimit);
    }

    function multisendToken(IERC20 token, Recipient[] calldata recipients, uint256 total, address payable referral)
        external
        payable
        returns (uint256 gasLeft)
    {
        _chargeFee(referral);
        token.safeTransferFrom(msg.sender, address(this), total);
        return _multisendToken(token, recipients, total, msg.sender);
    }

    function multisendTokenWithSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendTokenWithSignature(token, recipients, total, referral, signature, deadline, false);
    }

    function multisendTokenWithPersonalSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendTokenWithSignature(token, recipients, total, referral, signature, deadline, true);
    }

    function multisendTokenWithContractSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        address signer,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "The signature has expired");
        checkContractApprove(signer, msg.sender, deadline, signature);
        _chargeFee(referral);
        token.safeTransferFrom(signer, address(this), total);
        return _multisendToken(token, recipients, total, signer);
    }

    function multisendTokenPermit2(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        bytes calldata permitSig,
        IPermit2.PermitSingle calldata permitDetails
    ) external payable returns (uint256 gasLeft) {
        return _multisendTokenPermit2(token, recipients, total, referral, permitSig, msg.sender, permitDetails);
    }

    function multisendTokenPermit2WithSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        bytes calldata permitSig,
        IPermit2.PermitSingle calldata permitDetails,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendTokenPermit2WithSignature(
            token, recipients, total, referral, permitSig, permitDetails, signature, deadline, false
        );
    }

    function multisendTokenPermit2WithPersonalSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        bytes calldata permitSig,
        IPermit2.PermitSingle calldata permitDetails,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendTokenPermit2WithSignature(
            token, recipients, total, referral, permitSig, permitDetails, signature, deadline, true
        );
    }

    function multisendTokenPermit2WithContractSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        bytes calldata permitSig,
        IPermit2.PermitSingle calldata permitDetails,
        address signer,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "The signature has expired");
        checkContractApprove(signer, msg.sender, deadline, signature);
        return _multisendTokenPermit2(token, recipients, total, referral, permitSig, signer, permitDetails);
    }

    function multisendDeflationaryToken(IERC20 token, Recipient[] calldata recipients, address payable referral)
        external
        payable
        returns (uint256 gasLeft)
    {
        _chargeFee(referral);
        return _multisendDeflationaryToken(token, recipients, msg.sender);
    }

    function multisendDeflationaryTokenWithSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendDeflationaryTokenWithSignature(token, recipients, referral, signature, deadline, false);
    }

    function multisendDeflationaryTokenWithPersonalSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendDeflationaryTokenWithSignature(token, recipients, referral, signature, deadline, true);
    }

    function multisendDeflationaryTokenWithContractSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        address signer,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "the signature has expired");
        checkContractApprove(signer, msg.sender, deadline, signature);
        _chargeFee(referral);
        return _multisendDeflationaryToken(token, recipients, signer);
    }

    function multisendDeflationaryTokenPermit2(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        bytes calldata permitSig,
        IPermit2.PermitSingle calldata permitDetails
    ) external payable returns (uint256 gasLeft) {
        return _multisendDeflationaryTokenPermit2(token, recipients, referral, permitDetails, permitSig, msg.sender);
    }

    function multisendDeflationaryTokenPermit2WithSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        bytes calldata permitSig,
        IPermit2.PermitSingle calldata permitDetails,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendDeflationaryTokenPermit2WithSignature(
            token, recipients, referral, permitDetails, permitSig, signature, deadline, false
        );
    }

    function multisendDeflationaryTokenPermit2WithPersonalSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        bytes calldata permitSig,
        IPermit2.PermitSingle calldata permitDetails,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        return _multisendDeflationaryTokenPermit2WithSignature(
            token, recipients, referral, permitDetails, permitSig, signature, deadline, true
        );
    }

    function multisendDeflationaryTokenPermit2WithContractSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        bytes calldata permitSig,
        IPermit2.PermitSingle calldata permitDetails,
        address signer,
        bytes calldata signature,
        uint256 deadline
    ) external payable returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "The signature has expired");
        checkContractApprove(signer, msg.sender, deadline, signature);
        return _multisendDeflationaryTokenPermit2(token, recipients, referral, permitDetails, permitSig, signer);
    }

    // INTERNAL FUNCTIONS ---------------------------------------------
    // ----------------------------------------------------------------

    function _multisendEther(
        Recipient[] calldata recipients,
        address payable etherHolder,
        uint256 etherTransferGasLimit
    ) internal returns (uint256 gasLeft) {
        uint256 unspentEther = msg.value;
        uint256 requiredTotal;

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i = i.unsafeInc()) {
            uint256 amount = recipients[i].amount;
            require(unspentEther >= amount, "Incorrect recipients amounts: sum more than total");
            requiredTotal += amount;
            bool success;
            if (etherTransferGasLimit > 0) {
                (success,) = recipients[i].addr.call{value: amount, gas: etherTransferGasLimit}("");
            } else {
                success = recipients[i].addr.send(amount);
            }
            if (success) {
                unchecked {
                    unspentEther -= amount;
                }
            }
        }

        uint256 sentTotal = msg.value - unspentEther;
        uint256 change = requiredTotal - sentTotal;
        if (change > 0) {
            require(change <= unspentEther, "Low msg.value");
            unchecked {
                unspentEther -= change;
            }
            etherHolder.sendValue(change);
        }

        if (unspentEther > 0) {
            _sendBeneficiaryFee(unspentEther);
        }

        emit Multisent(sentTotal, IERC20(ETH_ADDRESS));

        return gasleft();
    }

    function _multisendEtherWithSignature(
        Recipient[] calldata recipients,
        bytes calldata signature,
        uint256 deadline,
        bool isPersonalSignature,
        uint256 etherTransferGasLimit
    ) internal returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "The signature has expired");
        address etherHolder = isPersonalSignature
            ? getPersonalApprover(msg.sender, deadline, signature)
            : getApprover(msg.sender, deadline, signature);

        return _multisendEther(recipients, payable(etherHolder), etherTransferGasLimit);
    }

    function _multisendToken(IERC20 token, Recipient[] calldata recipients, uint256 total, address tokenHolder)
        internal
        returns (uint256 gasLeft)
    {
        require(recipients.length > 0, "No recipients sent");

        uint256 unspentToken = total;
        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i = i.unsafeInc()) {
            uint256 amount = recipients[i].amount;
            require(unspentToken >= amount, "Incorrect recipients amounts: sum more than total");
            bool success = token.lowGasTransfer(recipients[i].addr, amount);
            if (success) {
                unchecked {
                    unspentToken -= amount;
                }
            }
        }
        if (unspentToken > 0) {
            token.safeTransfer(tokenHolder, unspentToken);
        }
        emit Multisent(total - unspentToken, token);

        return gasleft();
    }

    function _multisendTokenWithSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        bytes calldata signature,
        uint256 deadline,
        bool isPersonalSignature
    ) internal returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "The signature has expired");
        address tokenHolder = isPersonalSignature
            ? getPersonalApprover(msg.sender, deadline, signature)
            : getApprover(msg.sender, deadline, signature);

        _chargeFee(referral);
        token.safeTransferFrom(tokenHolder, address(this), total);
        return _multisendToken(token, recipients, total, tokenHolder);
    }

    function _multisendTokenPermit2(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        bytes calldata permitSig,
        address signer,
        IPermit2.PermitSingle memory permitDetails
    ) internal returns (uint256 gasLeft) {
        require(address(permit2) != address(0), "No permit2 in this chain");

        _chargeFee(referral);

        if (permitSig.length != 0) {
            permit2.permit(signer, permitDetails, permitSig);
        }
        permit2.transferFrom(signer, address(this), uint160(total), address(token));

        return _multisendToken(IERC20(token), recipients, total, signer);
    }

    function _multisendTokenPermit2WithSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        uint256 total,
        address payable referral,
        bytes calldata permitSig,
        IPermit2.PermitSingle memory permitDetails,
        bytes calldata signature,
        uint256 deadline,
        bool isPersonalSignature
    ) internal returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "The signature has expired");
        address tokenHolder = isPersonalSignature
            ? getPersonalApprover(msg.sender, deadline, signature)
            : getApprover(msg.sender, deadline, signature);
        return _multisendTokenPermit2(token, recipients, total, referral, permitSig, tokenHolder, permitDetails);
    }

    function _multisendDeflationaryToken(IERC20 token, Recipient[] calldata recipients, address tokenHolder)
        internal
        returns (uint256 gasLeft)
    {
        require(recipients.length > 0, "No recipients sent");
        require(address(token).isContract(), "Token address empty code");

        uint256 total;
        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i = i.unsafeInc()) {
            uint256 amount = recipients[i].amount;
            bool success = token.lowGasTransferFrom(tokenHolder, recipients[i].addr, amount);
            if (success) {
                unchecked {
                    total += amount;
                }
            }
        }
        emit Multisent(total, token);
        return gasleft();
    }

    function _multisendDeflationaryTokenWithSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        bytes calldata signature,
        uint256 deadline,
        bool isPersonalSignature
    ) internal returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "the signature has expired");
        address tokenHolder = isPersonalSignature
            ? getPersonalApprover(msg.sender, deadline, signature)
            : getApprover(msg.sender, deadline, signature);

        _chargeFee(referral);
        return _multisendDeflationaryToken(token, recipients, tokenHolder);
    }

    function _multisendDeflationaryTokenPermit2(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        IPermit2.PermitSingle calldata permitDetails,
        bytes calldata signature,
        address signer
    ) internal returns (uint256 gasLeft) {
        require(address(permit2) != address(0), "No permit2 in this chain");
        require(recipients.length > 0, "No recipients sent");
        require(address(token).isContract(), "Token address empty code");

        _chargeFee(referral);

        if (signature.length != 0) {
            permit2.permit(signer, permitDetails, signature);
        }

        uint256 total;
        for (uint256 i = 0; i < recipients.length; i = i.unsafeInc()) {
            try permit2.transferFrom(signer, recipients[i].addr, uint160(recipients[i].amount), address(token)) {
                unchecked {
                    total += recipients[i].amount;
                }
            } catch {}
        }
        emit Multisent(total, token);
        return gasleft();
    }

    function _multisendDeflationaryTokenPermit2WithSignature(
        IERC20 token,
        Recipient[] calldata recipients,
        address payable referral,
        IPermit2.PermitSingle calldata permitDetails,
        bytes calldata permitSig,
        bytes calldata signature,
        uint256 deadline,
        bool isPersonalSignature
    ) internal returns (uint256 gasLeft) {
        require(deadline >= block.timestamp, "The signature has expired");
        address tokenHolder = isPersonalSignature
            ? getPersonalApprover(msg.sender, deadline, signature)
            : getApprover(msg.sender, deadline, signature);
        return _multisendDeflationaryTokenPermit2(token, recipients, referral, permitDetails, permitSig, tokenHolder);
    }

    function _chargeFee(address payable referral) internal override {
        super._chargeFee(referral);
    }

    function _permit2() internal view virtual override returns (IPermit2) {
        return permit2;
    }

    function tokenFallback(address _from, uint256 _value, bytes memory _data) external {}

    fallback() external payable {
        if (msg.value > 0) {
            _sendBeneficiaryFee(msg.value);
        }
    }

    receive() external payable {
        if (msg.value > 0) {
            _sendBeneficiaryFee(msg.value);
        }
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol
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
// FILE: lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/utils/SafeERC20.sol)

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
     * non-reverting calls are assumed to be successful. Compatible with tokens that require the approval to be set to
     * 0 before setting it to a non-zero value.
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
// FILE: lib/openzeppelin-contracts/contracts/utils/Address.sol
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
// FILE: src/PushSender/ValidationSender.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../FeeChargeable.sol";

import "../interfaces/IPermit2.sol";
import "../libraries/SafeTransferLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract ValidationSender is FeeChargeable {
    using SafeERC20 for IERC20;
    using SafeTransferLib for IERC20;

    struct Recipient {
        address payable addr;
        uint256 amount;
    }

    function _permit2() internal view virtual returns (IPermit2);

    function validateEther(Recipient[] calldata recipients)
        external
        payable
        returns (uint256 gasLeft, Recipient[] memory badAddresses)
    {
        badAddresses = new Recipient[](recipients.length);
        uint256 total = msg.value;

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i++) {
            bool success = recipients[i].addr.send(recipients[i].amount);
            if (!success) {
                badAddresses[i] = recipients[i];
            } else {
                total -= recipients[i].amount;
            }
        }

        if (total > 0) {
            _sendBeneficiaryFee(total);
        }

        gasLeft = gasleft();
    }

    function validateEtherGasLimit(Recipient[] calldata recipients, uint256 etherTransferGasLimit)
        external
        payable
        returns (uint256 gasLeft, Recipient[] memory badAddresses)
    {
        badAddresses = new Recipient[](recipients.length);
        uint256 total = msg.value;

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i++) {
            (bool success,) = recipients[i].addr.call{value: recipients[i].amount, gas: etherTransferGasLimit}("");
            if (!success) {
                badAddresses[i] = recipients[i];
            } else {
                total -= recipients[i].amount;
            }
        }

        if (total > 0) {
            _sendBeneficiaryFee(total);
        }

        gasLeft = gasleft();
    }

    function validateToken(IERC20 token, uint256 total, Recipient[] calldata recipients)
        external
        payable
        returns (bool isDeflationary, uint256 gasLeft, Recipient[] memory badAddresses)
    {
        _chargeFee(payable(address(0)));
        badAddresses = new Recipient[](recipients.length);

        uint256 balanceDiff = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), total);
        balanceDiff = token.balanceOf(address(this)) - balanceDiff;
        if (balanceDiff != total) {
            // isDeflationary
            return (true, 0, badAddresses);
        }

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i++) {
            balanceDiff = token.balanceOf(recipients[i].addr);
            bool success = token.lowGasTransfer(recipients[i].addr, recipients[i].amount);
            balanceDiff = success ? token.balanceOf(recipients[i].addr) - balanceDiff : 0;

            if (success && balanceDiff != recipients[i].amount) {
                // isDeflationary
                return (true, 0, badAddresses);
            }

            if (!success) {
                badAddresses[i] = recipients[i];
            }
        }
        gasLeft = gasleft();
    }

    function validateDeflationaryToken(IERC20 token, Recipient[] calldata recipients)
        external
        payable
        returns (uint256 gasLeft, Recipient[] memory badAddresses)
    {
        _chargeFee(payable(address(0)));
        badAddresses = new Recipient[](recipients.length);

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i++) {
            bool success = token.lowGasTransferFrom(msg.sender, recipients[i].addr, recipients[i].amount);

            if (!success) {
                badAddresses[i] = recipients[i];
            }
        }
        gasLeft = gasleft();
    }

    function validateTokenPermit2(
        IERC20 token,
        uint160 total,
        Recipient[] calldata recipients,
        bytes calldata signature,
        IPermit2.PermitSingle calldata permitDetails
    ) external payable returns (bool isDeflationary, uint256 gasLeft, Recipient[] memory badAddresses) {
        _chargeFee(payable(address(0)));
        badAddresses = new Recipient[](recipients.length);

        uint256 balanceDiff = token.balanceOf(address(this));

        if (signature.length != 0) {
            _permit2().permit(msg.sender, permitDetails, signature);
        }
        _permit2().transferFrom(msg.sender, address(this), total, address(token));
        balanceDiff = token.balanceOf(address(this)) - balanceDiff;
        if (balanceDiff != total) {
            // isDeflationary
            return (true, 0, badAddresses);
        }

        for (uint256 i = 0; i < recipients.length; i++) {
            balanceDiff = token.balanceOf(recipients[i].addr);
            bool success = token.lowGasTransfer(recipients[i].addr, recipients[i].amount);
            balanceDiff = success ? token.balanceOf(recipients[i].addr) - balanceDiff : 0;

            if (success && balanceDiff != recipients[i].amount) {
                // isDeflationary
                return (true, 0, badAddresses);
            }

            if (!success) {
                badAddresses[i] = recipients[i];
            }
        }
        gasLeft = gasleft();
    }

    function validateDeflationaryTokenPermit2(
        IERC20 token,
        Recipient[] calldata recipients,
        bytes calldata signature,
        IPermit2.PermitSingle calldata permitDetails
    ) external payable returns (uint256 gasLeft, Recipient[] memory badAddresses) {
        _chargeFee(payable(address(0)));
        badAddresses = new Recipient[](recipients.length);

        if (signature.length != 0) {
            _permit2().permit(msg.sender, permitDetails, signature);
        }

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i++) {
            try _permit2().transferFrom(msg.sender, recipients[i].addr, uint160(recipients[i].amount), address(token)) {}
            catch {
                badAddresses[i] = recipients[i];
            }
        }
        gasLeft = gasleft();
    }
}



// ============================================================
// FILE: src/PushSender/Messages.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/ISignatureValidator.sol";

abstract contract Messages {
    struct Authorization {
        address authorizedSigner;
        uint256 expiration;
    }
    /**
     * Domain separator encoding per EIP 712.
     * keccak256(
     *     "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
     * )
     */

    bytes32 public constant EIP712_DOMAIN_TYPEHASH = 0xd87cd6ef79d4e2b95e15ce8abf732db51ec771f1ca2edccf22a46c729ac56472;

    /**
     * Validator struct type encoding per EIP 712
     * keccak256(
     *     "Authorization(address authorizedSigner,uint256 expiration)"
     * )
     */
    bytes32 private constant AUTHORIZATION_TYPEHASH = 0xe419504a688f0e6ea59c2708f49b2bbc10a2da71770bd6e1b324e39c73e7dc25;

    /**
     * Domain separator per EIP 712
     */
    // bytes32 public DOMAIN_SEPARATOR;
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        bytes32 salt = 0xf2d857f4a3edcb9b78b4d503bfe733db1e3f6cdc2b7971ee739626c97e86a558;
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, keccak256("Multisender"), keccak256("3.0"), block.chainid, address(this), salt
            )
        );
    }

    /**
     * @notice Calculates authorizationHash according to EIP 712.
     * @param _authorizedSigner address of trustee
     * @param _expiration expiration date
     * @return bytes32 EIP 712 hash of _authorization.
     */
    function hash(address _authorizedSigner, uint256 _expiration) public pure returns (bytes32) {
        return keccak256(abi.encode(AUTHORIZATION_TYPEHASH, _authorizedSigner, _expiration));
    }

    function getApprover(address spender, uint256 deadline, bytes memory signature) public view returns (address) {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hash(spender, deadline)));
        (address signer,) = ECDSA.tryRecover(digest, signature);
        require(signer != address(0), "the signature is invalid");
        return signer;
    }

    function getPersonalApprover(address spender, uint256 deadline, bytes memory signature)
        public
        view
        returns (address)
    {
        bytes32 digest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", "96", abi.encode(block.chainid, spender, deadline))
        );
        (address signer,) = ECDSA.tryRecover(digest, signature);
        require(signer != address(0), "the signature is invalid");
        return signer;
    }

    function checkContractApprove(address signer, address spender, uint256 deadline, bytes memory signature)
        public
        view
        returns (bool)
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hash(spender, deadline)));
        bytes4 value = ISignatureValidator(signer).isValidSignature(digest, signature);
        require(
            value == EIP1271_MAGIC_VALUE || value == EIP1271_MAGIC_VALUE_SAFE, "Invalid contract signature provided"
        );
        return true;
    }
}



// ============================================================
// FILE: src/libraries/UnsafeMath.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library UnsafeMath {
    function unsafeInc(uint256 x) internal pure returns (uint256) {
        unchecked {
            return x + 1;
        }
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/extensions/IERC20Permit.sol)

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
// FILE: src/FeeChargeable.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract FeeChargeable {
    using Address for address payable;

    struct VipTier {
        uint256 duration;
        uint256 price;
    }

    uint256 public fee;
    uint256 public referralFee;
    address payable public beneficiary20;
    address payable public beneficiary80;
    VipTier[] public tiers;
    mapping(address => uint256) public hasVipUntil;

    event PurchaseVIP(address customer, uint256 tier);

    // USERS METHODS --------------------------------------------------
    // ----------------------------------------------------------------
    function buyVip(uint256 tier) external payable {
        require(msg.value >= tiers[tier].price, "Not enough ETH value for VIP status purchase");
        _sendBeneficiaryFee(msg.value);

        uint256 start = Math.max(hasVipUntil[msg.sender], block.timestamp);
        hasVipUntil[msg.sender] = start + tiers[tier].duration;

        emit PurchaseVIP(msg.sender, tier);
    }

    function currentFee(address customer) public view returns (uint256) {
        if (hasVipUntil[customer] >= block.timestamp) {
            return 0;
        }
        return fee;
    }

    function getAllVipTiers() external view returns (VipTier[] memory) {
        return tiers;
    }

    function _sendBeneficiaryFee(uint256 _fee) internal {
        uint256 fee20 = (_fee * 20) / 100;
        // no ReentrancyGuard because trusted recipients
        beneficiary20.sendValue(fee20);
        beneficiary80.sendValue(_fee - fee20);
    }

    function _chargeFee(address payable referral) internal virtual {
        uint256 value = msg.value;
        if (value > 0) {
            uint256 refFee;
            if (referral != address(0)) {
                refFee = Math.min(referralFee, value);
                // no check of success by design
                bool success = referral.send(refFee);
                if (!success) {
                    refFee = 0;
                }
            }
            if (value > refFee) {
                _sendBeneficiaryFee(value - refFee);
            }
        }
    }
}



// ============================================================
// FILE: src/interfaces/IPermit2.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Minimal Permit2 interface, derived from
// https://github.com/Uniswap/permit2/blob/main/src/interfaces/ISignatureTransfer.sol

interface IPermit2 {
    // The permit data for a token
    struct PermitDetails {
        // ERC20 token address
        address token;
        // the maximum amount allowed to spend
        uint160 amount;
        // timestamp at which a spender's token allowances become invalid
        uint48 expiration;
        // an incrementing value indexed per owner,token,and spender for each signature
        uint48 nonce;
    }

    // The permit message signed for a single token allowance
    struct PermitSingle {
        // the permit data for a single token alownce
        PermitDetails details;
        // address permissioned on the allowed tokens
        address spender;
        // deadline on the permit signature
        uint256 sigDeadline;
    }

    function permit(address owner, PermitSingle memory permitSingle, bytes calldata signature) external;

    function allowance(address owner, address token, address spender) external returns (uint160, uint48, uint48);

    function transferFrom(address from, address to, uint160 amount, address token) external;
}



// ============================================================
// FILE: src/libraries/SafeTransferLib.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Safe ETH and ERC20 transfer library that gracefully handles missing return values.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/SafeTransferLib.sol)
/// @dev Caution! This library won't check that a token has code, responsibility is delegated to the caller.
library SafeTransferLib {
    function lowGasTransferFrom(IERC20 token, address from, address to, uint256 amount)
        internal
        returns (bool success)
    {
        assembly {
            // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(4, from) // Append the "from" argument.
            mstore(36, to) // Append the "to" argument.
            mstore(68, amount) // Append the "amount" argument.

            success :=
                and(
                    // Set success to whether the call reverted, if not we check it either
                    // returned exactly 1 (can't just be non-zero data), or had no return data.
                    or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                    // We use 100 because that's the total length of our calldata (4 + 32 * 3)
                    // Counterintuitively, this call() must be positioned after the or() in the
                    // surrounding and() because and() evaluates its arguments from right to left.
                    call(gas(), token, 0, 0, 100, 0, 32)
                )

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, memPointer) // Restore the memPointer.
        }
    }

    function lowGasTransfer(IERC20 token, address to, uint256 amount) internal returns (bool success) {
        assembly {
            // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(4, to) // Append the "to" argument.
            mstore(36, amount) // Append the "amount" argument.

            success :=
                and(
                    // Set success to whether the call reverted, if not we check it either
                    // returned exactly 1 (can't just be non-zero data), or had no return data.
                    or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                    // We use 68 because that's the total length of our calldata (4 + 32 * 2)
                    // Counterintuitively, this call() must be positioned after the or() in the
                    // surrounding and() because and() evaluates its arguments from right to left.
                    call(gas(), token, 0, 0, 68, 0, 32)
                )

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, memPointer) // Restore the memPointer.
        }
    }
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol
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
// FILE: src/interfaces/ISignatureValidator.sol
// ============================================================
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// bytes4(keccak256("isValidSignature(bytes32,bytes)")
bytes4 constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
// bytes4(keccak256("isValidSignature(bytes,bytes)")
// https://github.com/safe-global/safe-core-sdk/blob/4b8db6d633cd208740592c59e0959c14d56e41e9/packages/protocol-kit/contracts/safe_V1_2_0/interfaces/ISignatureValidator.sol#L5
bytes4 constant EIP1271_MAGIC_VALUE_SAFE = 0x20c13b0b;

abstract contract ISignatureValidator {
    /**
     * @notice EIP1271 method to validate a signature.
     * @param _hash Hash of the data signed on the behalf of address(this).
     * @param _signature Signature byte array associated with _data.
     *
     * MUST return the bytes4 magic value 0x1626ba7e when function passes.
     * MUST NOT modify state (using STATICCALL for solc < 0.5, view modifier for solc > 0.5)
     * MUST allow external calls
     */
    function isValidSignature(bytes32 _hash, bytes memory _signature) external view virtual returns (bytes4);
}



// ============================================================
// FILE: lib/openzeppelin-contracts/contracts/utils/math/Math.sol
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
// FILE: lib/openzeppelin-contracts/contracts/utils/Strings.sol
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
// FILE: lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol
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
