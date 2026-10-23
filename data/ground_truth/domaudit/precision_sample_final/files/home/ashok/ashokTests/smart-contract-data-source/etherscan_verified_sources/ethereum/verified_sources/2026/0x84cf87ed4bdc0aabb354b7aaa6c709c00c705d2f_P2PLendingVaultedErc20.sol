// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x84cf87ed4bdc0aabb354b7aaa6c709c00c705d2f
// Contract Name: P2PLendingVaultedErc20



// ============================================================
// FILE: contracts/v1/P2PLendingVault.vy
// ============================================================
# @version 0.4.3

"""
@title P2PLendingVault
@author [Zharta](https://zharta.io/)
@notice This contract implements a vault to hold collateral for peer-to-peer loans
@dev Actual vaults are minimal proxy contracts to this, deployed via CREATE2 by the lending contract

"""

# Interfaces

from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed

interface Vault:
    def initialise(_owner: address, _token: address): nonpayable
    def deposit(amount: uint256, wallet: address): nonpayable
    def withdraw(amount: uint256, wallet: address): nonpayable


implements: Vault


VERSION: public(constant(String[30])) = "P2PLendingVault.20260310"

# Structs

event Deposit:
    wallet: address
    amount: uint256

event Withdraw:
    wallet: address
    amount: uint256

event TransferFailed:
    wallet: address
    amount: uint256

event WithdrawPending:
    wallet: address
    amount: uint256

# Global variables


owner: public(address)
caller: public(address)
token: public(address)
pending_transfers: public(HashMap[address, uint256])
pending_transfers_total: public(uint256)


@deploy
def __init__():
    pass


@external
def initialise(_owner: address, _token: address):

    """
    @notice Initialize a vault with the given owner, enabling it to receive specific tokens.
    @dev Ensures that the vault is not already initialized before setting the owner and caller.
    @param _owner The address of the vault's owner.
    @param _token The address of the ERC20 token that the vault will hold.
    """

    assert self.caller == empty(address), "already initialised"

    self.caller = msg.sender
    self.owner = _owner
    self.token = _token


@external
def deposit(amount: uint256, wallet: address):
    """
    @notice Deposit tokens into the vault on behalf of a specified wallet.
    @dev Transfers tokens from the wallet to the vault and emits a Deposit event.
    @param amount The amount of tokens to deposit.
    @param wallet The address of the wallet from which tokens will be transferred.
    """

    assert msg.sender == self.caller, "unauthorized"

    pending: uint256 = self.pending_transfers[wallet]
    if pending >= amount:
        self.pending_transfers[wallet] = pending - amount
        self.pending_transfers_total -= amount
        log WithdrawPending(wallet=wallet, amount=amount)
    elif pending > 0:
        self.pending_transfers_total -= pending
        self.pending_transfers[wallet] = 0
        log WithdrawPending(wallet=wallet, amount=pending)
        assert extcall IERC20(self.token).transferFrom(wallet, self, amount - pending), "transferFrom failed"
    else:
        assert extcall IERC20(self.token).transferFrom(wallet, self, amount), "transferFrom failed"
    log Deposit(wallet=wallet, amount=amount)


@external
def withdraw(amount: uint256, wallet: address):
    """
    @notice Withdraw tokens from the vault to a specified wallet.
    @dev Transfers tokens from the vault to the wallet and emits a Withdraw event.
    @param amount The amount of tokens to withdraw.
    @param wallet The address of the wallet to which tokens will be transferred.
    """
    assert msg.sender == self.caller, "unauthorized"
    assert amount + self.pending_transfers_total <= staticcall IERC20(self.token).balanceOf(self), "insufficient balance"

    success: bool = False
    response: Bytes[32] = b""

    success, response = raw_call(
        self.token,
        abi_encode(wallet, amount, method_id=method_id("transfer(address,uint256)")),
        max_outsize=32,
        revert_on_failure=False
    )

    if not success or not convert(response, bool):
        log TransferFailed(wallet=wallet, amount=amount)
        self.pending_transfers[wallet] += amount
        self.pending_transfers_total += amount
    else:
        log Withdraw(wallet=wallet, amount=amount)


@external
def withdraw_pending(amount: uint256):
    """
    @notice Withdraw tokens from the vault that are pending transfer to the sender.
    @dev Transfers tokens from the vault to the sender and emits a WithdrawPending event.
    @param amount The amount of tokens to withdraw.
    """
    assert self.pending_transfers[msg.sender] >= amount, "insufficient pending collateral"
    self.pending_transfers[msg.sender] -= amount
    self.pending_transfers_total -= amount
    assert extcall IERC20(self.token).transfer(msg.sender, amount), "transfer failed"
    log WithdrawPending(wallet=msg.sender, amount=amount)



// ============================================================
// FILE: contracts/v1/P2PLendingVaultedBase.vy
// ============================================================
# @version 0.4.3

"""
@title P2PLendingVaultedBase
@author [Zharta](https://zharta.io/)
@notice This contract facilitates peer-to-peer lending using ERC20s as collateral.
@dev Keep all state here so that the storage layout is consistent across contracts

"""

# Interfaces

from ethereum.ercs import IERC721
from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed
from contracts.v1 import P2PLendingVault as vault

struct AggregatorV3LatestRoundData:
    roundId: uint80
    answer: int256
    startedAt: uint256
    updatedAt: uint256
    answeredInRound: uint80

interface AggregatorV3Interface:
    def decimals() -> uint8: view
    def latestRoundData() -> AggregatorV3LatestRoundData: view

interface KYCValidator:
    def check_validation(validation: SignedWalletValidation) -> bool: view
    def check_validations_pair(validation1: SignedWalletValidation, validation2: SignedWalletValidation) -> bool: view

interface EIP1271Signer:
    def is_valid_signature(hash: bytes32, signature: Bytes[65]) -> bytes4: view

interface VaultRegistrar:
    def register_vault(vault: address, investor_wallet: address): nonpayable


# Structs

BPS: constant(uint256) = 10000
YEAR_TO_SECONDS: constant(uint256) = 365 * 24 * 60 * 60

MALLEABILITY_THRESHOLD: constant(uint256) = 57896044618658097711785492504343953926418782139537452191302581570759080747168
EIP1271_MAGIC_VALUE: constant(bytes4) = 0x1626ba7e


_COLLISION_OFFSET: constant(bytes1) = 0xFF
_DEPLOYMENT_CODE: constant(bytes9) = 0x602D3D8160093D39F3
_PRE: constant(bytes10) = 0x363d3d373d3d3d363d73
_POST: constant(bytes15) = 0x5af43d82803e903d91602b57fd5bf3

struct WalletValidation:
    wallet: address
    expiration_time: uint256

struct SignedWalletValidation:
    validation: WalletValidation
    signature: Signature

struct Offer:
    principal: uint256 # optional
    apr: uint256
    payment_token: address
    collateral_token: address
    duration: uint256
    origination_fee_bps: uint256

    min_collateral_amount: uint256 # optional
    max_iltv: uint256 # max initial LTV, optional and needs to be set if min_collateral_amount isn't specified
    available_liquidity: uint256 # amount of the principal token allocated to the offer
    call_eligibility: uint256 # when the loan starts to be callable, 0 if not callable
    call_window: uint256 # time after the loan is called where the borrower can repay the loan or the loan defaults entirely
    liquidation_ltv: uint256 # optional, used if > 0
    oracle_addr: address # optional, must match the oracle used for collateral valuation if defined

    expiration: uint256
    lender: address
    borrower: address
    tracing_id: bytes32


struct Signature:
    v: uint256
    r: uint256
    s: uint256

struct SignedOffer:
    offer: Offer
    signature: Signature

struct Loan:
    id: bytes32
    offer_id: bytes32
    offer_tracing_id: bytes32
    initial_amount: uint256
    amount: uint256
    apr: uint256
    payment_token: address
    maturity: uint256
    start_time: uint256
    accrual_start_time: uint256 # either start_time or last soft liquidation time
    borrower: address
    lender: address
    collateral_token: address
    collateral_amount: uint256
    min_collateral_amount: uint256
    origination_fee_amount: uint256
    protocol_upfront_fee_amount: uint256
    protocol_settlement_fee: uint256
    partial_liquidation_fee: uint256
    full_liquidation_fee: uint256
    call_eligibility: uint256 # amount of seconds after the start of the loan when the loan starts to be callable, 0 if not callable
    call_window: uint256 # amount of seconds after the loan is called where the borrower can repay the loan or the loan defaults entirely, optional and needs to be set if loan is callable
    liquidation_ltv: uint256 # needs to be higher than the initial ltv, optional and used if > 0
    oracle_addr: address # optional, needs to be set if soft_liquidaiton is defined
    initial_ltv: uint256 # initial ltv, needs to be set if soft_liquidation is defined
    call_time: uint256 # the time when the loan was called, 0 if not called

struct UInt256Rational:
    numerator: uint256
    denominator: uint256


struct PartialLiquidationResult:
    collateral_claimed: uint256
    liquidation_fee: uint256
    debt_written_off: uint256
    updated_ltv: uint256


event OfferRevoked:
    offer_id: bytes32
    lender: address

event TransferFailed:
    _to: address
    amount: uint256

# Global variables


owner: public(address)
proposed_owner: public(address)
transfer_agent: public(address)

loans: public(HashMap[bytes32, bytes32])

protocol_wallet: public(address)
protocol_upfront_fee: public(uint256)
partial_liquidation_fee: public(uint256)
full_liquidation_fee: public(uint256)
protocol_settlement_fee: public(uint256)

commited_liquidity: public(HashMap[bytes32, uint256])
revoked_offers: public(HashMap[bytes32, bool])

authorized_proxies: public(HashMap[address, bool])
pending_transfers: public(HashMap[address, uint256])

vault_registrar: public(address)
refinance_addr: public(address)
liquidation_addr: public(address)

ZHARTA_DOMAIN_NAME: constant(String[6]) = "Zharta"
ZHARTA_DOMAIN_VERSION: constant(String[1]) = "1"

DOMAIN_TYPE_HASH: constant(bytes32) = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
OFFER_TYPE_DEF: constant(String[370]) = "Offer(uint256 principal,uint256 apr,address payment_token,address collateral_token,uint256 duration," \
                                        "uint256 origination_fee_bps,uint256 min_collateral_amount,uint256 max_iltv,uint256 available_liquidity," \
                                        "uint256 call_eligibility,uint256 call_window,uint256 liquidation_ltv,address oracle_addr," \
                                        "uint256 expiration,address lender,address borrower,bytes32 tracing_id)"
OFFER_TYPE_HASH: constant(bytes32) = keccak256(OFFER_TYPE_DEF)


@deploy
def __init__():
    self.owner = msg.sender


# Internal functions

@pure
@internal
def _compute_loan_id(loan: Loan) -> bytes32:
    return keccak256(concat(
        convert(loan.borrower, bytes32),
        convert(loan.lender, bytes32),
        convert(loan.start_time, bytes32),
        loan.offer_id,
    ))

@pure
@internal
def _compute_signed_offer_id(offer: SignedOffer) -> bytes32:
    return keccak256(concat(
        convert(offer.signature.v, bytes32),
        convert(offer.signature.r, bytes32),
        convert(offer.signature.s, bytes32),
    ))

@internal
def _check_and_update_offer_state(offer: SignedOffer, amount: uint256):
    offer_id: bytes32 = self._compute_signed_offer_id(offer)
    assert not self.revoked_offers[offer_id], "offer revoked"

    liquidity_key: bytes32 = self._commited_liquidity_key(offer.offer.lender, offer.offer.tracing_id)
    commited_liquidity: uint256 = self.commited_liquidity[liquidity_key]
    assert commited_liquidity + amount <= offer.offer.available_liquidity, "offer fully utilized"
    self.commited_liquidity[liquidity_key] = commited_liquidity + amount

    if offer.offer.borrower != empty(address):
        # offer has borrower => normal offer
        self._revoke_offer(offer_id, offer)


@internal
def _revoke_offer(offer_id: bytes32, offer: SignedOffer):

    self.revoked_offers[offer_id] = True

    log OfferRevoked(offer_id=offer_id, lender=offer.offer.lender)


@internal
def _reduce_commited_liquidity(lender: address, tracing_id: bytes32, amount: uint256):
    liquidity_key: bytes32 = self._commited_liquidity_key(lender, tracing_id)
    commited_liquidity: uint256 = self.commited_liquidity[liquidity_key]
    self.commited_liquidity[liquidity_key] = 0 if amount > commited_liquidity else commited_liquidity - amount

@pure
@internal
def _commited_liquidity_key(lender: address, tracing_id: bytes32) -> bytes32:
    return keccak256(concat(convert(lender, bytes32), tracing_id))

@view
@internal
def _is_loan_valid(loan: Loan) -> bool:
    return self.loans[loan.id] == self._loan_state_hash(loan)

@pure
@internal
def _loan_state_hash(loan: Loan) -> bytes32:
    return keccak256(abi_encode(loan))


@internal
def _is_offer_signed_by_lender(signed_offer: SignedOffer, offer_sig_domain_separator: bytes32) -> bool:
    assert signed_offer.signature.s <= MALLEABILITY_THRESHOLD, "invalid signature"

    message_hash: bytes32 = keccak256(
            concat(
                convert("\x19\x01", Bytes[2]),
                abi_encode(
                    offer_sig_domain_separator,
                    keccak256(abi_encode(OFFER_TYPE_HASH, signed_offer.offer))
                )
            )
        )

    signer: address = ecrecover(
        message_hash,
        signed_offer.signature.v,
        signed_offer.signature.r,
        signed_offer.signature.s
    )

    if signed_offer.offer.lender.is_contract:
        return staticcall EIP1271Signer(signed_offer.offer.lender).is_valid_signature(
            message_hash,
            concat(
                convert(signed_offer.signature.r, bytes32),
                convert(signed_offer.signature.s, bytes32),
                convert(convert(signed_offer.signature.v, uint8), bytes1)
            )
        ) == EIP1271_MAGIC_VALUE
    else:
        return signer == signed_offer.offer.lender



@view
@internal
def _compute_settlement_interest(loan: Loan) -> uint256:
    return loan.amount * loan.apr * (block.timestamp - loan.accrual_start_time) // (BPS * YEAR_TO_SECONDS)


@internal
def _send_funds(_to: address, _amount: uint256, payment_token: address):
    success: bool = False
    response: Bytes[32] = b""

    success, response = raw_call(
        payment_token,
        abi_encode(_to, _amount, method_id=method_id("transfer(address,uint256)")),
        max_outsize=32,
        revert_on_failure=False
    )

    if not success or not convert(response, bool):
        log TransferFailed(_to=_to, amount=_amount)
        self.pending_transfers[_to] += _amount


@internal
def _receive_funds(_from: address, _amount: uint256, payment_token: address):
    assert extcall IERC20(payment_token).transferFrom(_from, self, _amount), "transferFrom failed"


@internal
def _transfer_funds(_from: address, _to: address, _amount: uint256, payment_token: address):
    assert extcall IERC20(payment_token).transferFrom(_from, _to, _amount), "transferFrom failed"


@internal
def _send_collateral(wallet: address, _amount: uint256, _vault: vault.Vault):
    extcall _vault.withdraw(_amount, wallet)


@internal
def _receive_collateral(_from: address, _amount: uint256, _vault: vault.Vault):
    extcall _vault.deposit(_amount, _from)


@internal
def _check_user(user: address) -> bool:
    return msg.sender == user or (self.authorized_proxies[msg.sender] and user == tx.origin)

@internal
def _check_offer_validity(offer: SignedOffer, payment_token: address, collateral_token: address, oracle_addr: address):
    assert offer.offer.expiration > block.timestamp, "offer expired"
    assert offer.offer.duration > 0, "duration is 0"
    assert offer.offer.payment_token == payment_token, "invalid payment token"
    assert offer.offer.collateral_token == collateral_token, "invalid collateral token"
    assert offer.offer.oracle_addr == empty(address) or offer.offer.oracle_addr == oracle_addr, "invalid oracle address"
    assert offer.offer.call_window != 0 or offer.offer.call_eligibility == 0, "call window is 0"
    assert offer.offer.min_collateral_amount > 0 or offer.offer.max_iltv > 0, "no min collateral nor max iltv"


@view
@internal
def _get_oracle_rate(oracle_addr: address, oracle_reverse: bool) -> UInt256Rational:
    answer: int256 = (staticcall AggregatorV3Interface(oracle_addr).latestRoundData()).answer
    assert answer > 0, "invalid oracle rate"
    if oracle_reverse:
        return UInt256Rational(
            numerator=10 ** convert(staticcall AggregatorV3Interface(oracle_addr).decimals(), uint256),
            denominator=convert(answer, uint256)
        )
    else:
        return UInt256Rational(
            numerator=convert(answer, uint256),
            denominator=10 ** convert(staticcall AggregatorV3Interface(oracle_addr).decimals(), uint256)
        )


@view
@internal
def _compute_ltv(collateral_amount: uint256, amount: uint256, convertion_rate: UInt256Rational, payment_token_decimals: uint256, collateral_token_decimals: uint256) -> uint256:
    return amount * BPS * convertion_rate.denominator * collateral_token_decimals // (collateral_amount * convertion_rate.numerator * payment_token_decimals)


@view
@internal
def _compute_partial_liquidation(
    collateral_amount: uint256,
    outstanding_debt: uint256,
    initial_ltv: uint256,
    partial_liquidation_fee: uint256,
    convertion_rate: UInt256Rational,
    payment_token_decimals: uint256,
    collateral_token_decimals: uint256
) -> (uint256, uint256, uint256):
    """
    returns:
        principal_written_off: uint256 - the amount of principal written off
        collateral_claimed: uint256 - the amount of collateral claimed
        liquidation_fee: uint256 - the liquidation fee
    """

    if (BPS + partial_liquidation_fee) * initial_ltv >= BPS * BPS:
        return max_value(uint256), max_value(uint256), max_value(uint256)
    collateral_value: uint256 = collateral_amount * convertion_rate.numerator * payment_token_decimals // (convertion_rate.denominator * collateral_token_decimals)
    principal_written_off: uint256 = (outstanding_debt * BPS - collateral_value * initial_ltv)  * BPS // (BPS * BPS - (BPS + partial_liquidation_fee) * initial_ltv)
    collateral_claimed: uint256 = principal_written_off * convertion_rate.denominator * collateral_token_decimals // (convertion_rate.numerator * payment_token_decimals)
    liquidation_fee: uint256 = collateral_claimed * partial_liquidation_fee // BPS

    return principal_written_off, collateral_claimed, liquidation_fee


@view
@internal
def _is_loan_defaulted(loan: Loan) -> bool:
    if block.timestamp > loan.maturity:
        return True
    if loan.call_time > 0:
        return block.timestamp > loan.call_time + loan.call_window
    return False


@internal
def _get_vault(wallet: address, vault_impl_addr: address) -> vault.Vault:
    _vault: address = self._wallet_to_vault(wallet, vault_impl_addr)
    assert _vault.is_contract, "no vault exists for wallet"
    return vault.Vault(_vault)

@internal
def _create_vault_if_needed(wallet: address, vault_impl_addr: address, payment_token: address, vault_registrar: address) -> vault.Vault:
    _vault: address = self._wallet_to_vault(wallet, vault_impl_addr)
    if not _vault.is_contract:
        _vault = create_minimal_proxy_to(vault_impl_addr, salt=convert(wallet, bytes32))
        extcall vault.Vault(_vault).initialise(wallet, payment_token)

        if vault_registrar != empty(address):
            extcall VaultRegistrar(vault_registrar).register_vault(_vault, wallet)

    return vault.Vault(_vault)


@view
@internal
def _wallet_to_vault(wallet: address, vault_impl_addr: address) -> address:
    return self._compute_address(
        convert(wallet, bytes32),
        keccak256(concat(
            _DEPLOYMENT_CODE,
            _PRE,
            convert(vault_impl_addr, bytes20),
            _POST
        )),
        self
    )

@pure
@internal
def _compute_address(salt: bytes32, bytecode_hash: bytes32, deployer: address) -> address:
    data: bytes32 = keccak256(concat(_COLLISION_OFFSET, convert(deployer, bytes20), salt, bytecode_hash))
    return self._convert_keccak256_2_address(data)


@pure
@internal
def _convert_keccak256_2_address(digest: bytes32) -> address:
    return convert(convert(digest, uint256) & convert(max_value(uint160), uint256), address)



// ============================================================
// FILE: contracts/v1/P2PLendingVaultedErc20.vy
// ============================================================
# @version 0.4.3

"""
@title P2PLendingVaultedErc20
@author [Zharta](https://zharta.io/)
@notice This contract facilitates peer-to-peer lending using ERC20s as collateral.

"""

from contracts.v1 import P2PLendingVaultedBase as base

initializes: base
exports: base.__interface__

# Interfaces

from ethereum.ercs import IERC721
from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed

from contracts.v1 import P2PLendingVault as vault

event LoanCreated:
    id: bytes32
    amount: uint256
    apr: uint256
    payment_token: address
    maturity: uint256
    start_time: uint256
    borrower: address
    lender: address
    collateral_token: address
    collateral_amount: uint256
    min_collateral_amount: uint256
    call_eligibility: uint256
    call_window: uint256
    liquidation_ltv: uint256
    oracle_addr: address
    initial_ltv: uint256
    origination_fee_amount: uint256
    protocol_upfront_fee_amount: uint256
    protocol_settlement_fee: uint256
    partial_liquidation_fee: uint256
    full_liquidation_fee: uint256
    offer_id: bytes32
    offer_tracing_id: bytes32
    oracle_rate_num: uint256
    oracle_rate_den: uint256


event LoanPaid:
    id: bytes32
    borrower: address
    lender: address
    payment_token: address
    paid_principal: uint256
    paid_interest: uint256
    origination_fee_amount: uint256
    protocol_upfront_fee_amount: uint256
    protocol_settlement_fee_amount: uint256


event LoanCollateralClaimed:
    id: bytes32
    borrower: address
    lender: address
    collateral_token: address
    collateral_amount: uint256


event LoanReplaced:
    id: bytes32
    amount: uint256
    apr: uint256
    maturity: uint256
    start_time: uint256
    borrower: address
    lender: address
    collateral_amount: uint256
    min_collateral_amount: uint256
    call_eligibility: uint256
    call_window: uint256
    liquidation_ltv: uint256
    initial_ltv: uint256
    origination_fee_amount: uint256
    protocol_upfront_fee_amount: uint256
    protocol_settlement_fee: uint256
    partial_liquidation_fee: uint256
    full_liquidation_fee: uint256
    offer_id: bytes32
    offer_tracing_id: bytes32
    original_loan_id: bytes32
    paid_principal: uint256
    paid_interest: uint256
    paid_protocol_settlement_fee_amount: uint256

event LoanReplacedByLender:
    id: bytes32
    amount: uint256
    apr: uint256
    maturity: uint256
    start_time: uint256
    borrower: address
    lender: address
    collateral_amount: uint256
    min_collateral_amount: uint256
    call_eligibility: uint256
    call_window: uint256
    liquidation_ltv: uint256
    initial_ltv: uint256
    origination_fee_amount: uint256
    protocol_upfront_fee_amount: uint256
    protocol_settlement_fee: uint256
    partial_liquidation_fee: uint256
    full_liquidation_fee: uint256
    offer_id: bytes32
    offer_tracing_id: bytes32
    original_loan_id: bytes32
    paid_principal: uint256
    paid_interest: uint256
    paid_protocol_settlement_fee_amount: uint256


event LoanCollateralAdded:
    id: bytes32
    borrower: address
    lender: address
    collateral_token: address
    old_collateral_amount: uint256
    new_collateral_amount: uint256
    old_ltv: uint256
    new_ltv: uint256


event LoanCollateralRemoved:
    id: bytes32
    borrower: address
    lender: address
    collateral_token: address
    old_collateral_amount: uint256
    new_collateral_amount: uint256
    old_ltv: uint256
    new_ltv: uint256


event LoanPartiallyLiquidated:
    id: bytes32
    borrower: address
    lender: address
    written_off: uint256
    collateral_claimed: uint256
    liquidation_fee: uint256
    updated_amount: uint256
    updated_collateral_amount: uint256
    updated_accrual_start_time: uint256
    liquidator: address
    old_ltv: uint256
    new_ltv: uint256

event LoanLiquidated:
    id: bytes32
    borrower: address
    lender: address
    liquidator: address
    outstanding_debt: uint256
    collateral_for_debt: uint256
    remaining_collateral: uint256
    remaining_collateral_value: uint256
    shortfall: uint256
    liquidation_fee: uint256
    protocol_settlement_fee_amount: uint256

event LoanCalled:
    id: bytes32
    borrower: address
    lender: address
    call_time: uint256

event OwnerProposed:
    owner: address
    proposed_owner: address

event OwnershipTransferred:
    old_owner: address
    new_owner: address

event TransferAgentChanged:
    old_agent: address
    new_agent: address
    by: address

event ProtocolFeeSet:
    old_upfront_fee: uint256
    old_settlement_fee: uint256
    new_upfront_fee: uint256
    new_settlement_fee: uint256

event PartialLiquidationFeeSet:
    old_fee: uint256
    new_fee: uint256

event FullLiquidationFeeSet:
    old_fee: uint256
    new_fee: uint256

event ProtocolWalletChanged:
    old_wallet: address
    new_wallet: address

event ProxyAuthorizationChanged:
    proxy: address
    value: bool

event VaultRegistrarChanged:
    old_registrar: address
    new_registrar: address

event RefinanceAddrChanged:
    old_addr: address
    new_addr: address

event LiquidationAddrChanged:
    old_addr: address
    new_addr: address

event PendingTransfersClaimed:
    _to: address
    amount: uint256


event LoanBorrowerTransferred:
    loan_id: bytes32
    new_loan_id: bytes32
    old_borrower: address
    new_borrower: address
    lender: address


BPS: constant(uint256) = 10000
YEAR_TO_SECONDS: constant(uint256) = 365 * 24 * 60 * 60

VERSION: public(constant(String[30])) = "P2PLendingErc20.20260512"

payment_token: public(immutable(address))
collateral_token: public(immutable(address))
oracle_addr: public(immutable(address))
oracle_reverse: public(immutable(bool))
kyc_validator_addr: public(immutable(address))

max_protocol_upfront_fee: public(immutable(uint256))
max_protocol_settlement_fee: public(immutable(uint256))

payment_token_decimals: public(immutable(uint256))
collateral_token_decimals: public(immutable(uint256))

offer_sig_domain_separator: immutable(bytes32)

vault_impl_addr: public(immutable(address))

@deploy
def __init__(
    _payment_token: address,
    _collateral_token: address,
    _oracle_addr: address,
    _oracle_reverse: bool,
    _kyc_validator_addr: address,
    _protocol_upfront_fee: uint256,
    _protocol_settlement_fee: uint256,
    _protocol_wallet: address,
    _max_protocol_upfront_fee: uint256,
    _max_protocol_settlement_fee: uint256,
    _partial_liquidation_fee: uint256,
    _full_liquidation_fee: uint256,
    _refinance_addr: address,
    _liquidation_addr: address,
    _vault_impl_addr: address,
    _transfer_agent: address,
    _vault_registrar_addr: address
):

    """
    @notice Initialize the contract with the given parameters.
    @param _payment_token The address of the payment token.
    @param _collateral_token The address of the collateral token.
    @param _oracle_addr The address of the oracle contract for collateral valuation.
    @param _oracle_reverse Whether the oracle returns the collateral price in reverse (i.e., 1 / price).
    @param _protocol_upfront_fee The percentage (bps) of the principal paid to the protocol at origination.
    @param _protocol_settlement_fee The percentage (bps) of the interest paid to the protocol at settlement.
    @param _protocol_wallet The address where the protocol fees are accrued.
    @param _max_protocol_upfront_fee The maximum percentage (bps) of the principal that can be charged as protocol upfront fee.
    @param _max_protocol_settlement_fee The maximum percentage (bps) of the interest that can be charged as protocol settlement fee.
    @param _partial_liquidation_fee The percentage (bps) of the principal that is charged as a liquidation fee when a loan is partially liquidated.
    @param _full_liquidation_fee The percentage (bps) of the principal that is charged as a liquidation fee when a loan is fully liquidated.
    @param _refinance_addr The address of the facet contract implementing the refinance functionality.
    @param _liquidation_addr The address of the facet contract implementing the liquidation functionality.
    @param _vault_impl_addr The address of the vault implementation contract.
    @param _transfer_agent The wallet address for the transfer agent role.
    @param _vault_registrar_addr The address of the vault registrar connector contract.
    """

    base.__init__()

    payment_token = _payment_token
    collateral_token = _collateral_token
    oracle_addr = _oracle_addr
    oracle_reverse = _oracle_reverse
    kyc_validator_addr = _kyc_validator_addr
    max_protocol_upfront_fee = _max_protocol_upfront_fee
    max_protocol_settlement_fee = _max_protocol_settlement_fee
    base.refinance_addr = _refinance_addr
    base.liquidation_addr = _liquidation_addr
    vault_impl_addr = _vault_impl_addr
    collateral_token_decimals = 10 ** convert(staticcall IERC20Detailed(_collateral_token).decimals(), uint256)
    payment_token_decimals = 10 ** convert(staticcall IERC20Detailed(_payment_token).decimals(), uint256)
    base.protocol_upfront_fee = _protocol_upfront_fee
    base.protocol_settlement_fee = _protocol_settlement_fee
    base.protocol_wallet = _protocol_wallet
    base.transfer_agent = _transfer_agent
    base.partial_liquidation_fee = _partial_liquidation_fee
    base.full_liquidation_fee = _full_liquidation_fee
    base.vault_registrar = _vault_registrar_addr

    offer_sig_domain_separator = keccak256(
        abi_encode(
            base.DOMAIN_TYPE_HASH,
            keccak256(base.ZHARTA_DOMAIN_NAME),
            keccak256(base.ZHARTA_DOMAIN_VERSION),
            chain.id,
            self
        )
    )


# Config functions


@external
def set_partial_liquidation_fee(new_partial_liquidation_fee: uint256):

    """
    @notice Set the partial liquidation fee
    @dev Sets the partial liquidation fee to the given value and logs the event. Admin function.
    @param new_partial_liquidation_fee The new partial liquidation fee.
    """

    assert msg.sender == base.owner
    assert new_partial_liquidation_fee <= BPS, "fee exceeds BPS"

    log PartialLiquidationFeeSet(old_fee=base.partial_liquidation_fee, new_fee=new_partial_liquidation_fee)
    base.partial_liquidation_fee = new_partial_liquidation_fee


@external
def set_full_liquidation_fee(new_full_liquidation_fee: uint256):

    """
    @notice Set the full liquidation fee
    @dev Sets the full liquidation fee to the given value and logs the event. Admin function.
    @param new_full_liquidation_fee The new full liquidation fee.
    """

    assert msg.sender == base.owner
    assert new_full_liquidation_fee <= BPS, "fee exceeds BPS"

    log FullLiquidationFeeSet(old_fee=base.full_liquidation_fee, new_fee=new_full_liquidation_fee)
    base.full_liquidation_fee = new_full_liquidation_fee


@external
def set_protocol_fee(protocol_upfront_fee: uint256, protocol_settlement_fee: uint256):

    """
    @notice Set the protocol fee
    @dev Sets the protocol fee to the given value and logs the event. Admin function.
    @param protocol_upfront_fee The new protocol upfront fee.
    @param protocol_settlement_fee The new protocol settlement fee.
    """

    assert msg.sender == base.owner
    assert protocol_upfront_fee <= max_protocol_upfront_fee, "upfront fee exceeds max"
    assert protocol_settlement_fee <= max_protocol_settlement_fee, "settlement fee exceeds max"

    log ProtocolFeeSet(
        old_upfront_fee=base.protocol_upfront_fee,
        old_settlement_fee=base.protocol_settlement_fee,
        new_upfront_fee=protocol_upfront_fee,
        new_settlement_fee=protocol_settlement_fee
    )
    base.protocol_upfront_fee = protocol_upfront_fee
    base.protocol_settlement_fee = protocol_settlement_fee


@external
def change_protocol_wallet(new_protocol_wallet: address):

    """
    @notice Change the protocol wallet
    @dev Changes the protocol wallet to the given address and logs the event. Admin function.
    @param new_protocol_wallet The new protocol wallet.
    """

    assert msg.sender == base.owner
    assert new_protocol_wallet != empty(address)

    log ProtocolWalletChanged(old_wallet=base.protocol_wallet, new_wallet=new_protocol_wallet)
    base.protocol_wallet = new_protocol_wallet


@external
def change_vault_registrar(new_vault_registrar: address):

    """
    @notice Change the vault registrar
    @dev Changes the vault registrar to the given address and logs the event. Admin function.
    @param new_vault_registrar The new vault registrar.
    """

    assert msg.sender == base.owner
    log VaultRegistrarChanged(old_registrar=base.vault_registrar, new_registrar=new_vault_registrar)
    base.vault_registrar = new_vault_registrar


@external
def set_refinance_addr(_address: address):

    """
    @notice Set the refinance facet address
    @dev Changes the refinance facet contract address. Admin function.
    @param _address The address of the new refinance facet contract.
    """

    assert msg.sender == base.owner
    assert _address != empty(address)
    log RefinanceAddrChanged(old_addr=base.refinance_addr, new_addr=_address)
    base.refinance_addr = _address


@external
def set_liquidation_addr(_address: address):

    """
    @notice Set the liquidation facet address
    @dev Changes the liquidation facet contract address. Admin function.
    @param _address The address of the new liquidation facet contract.
    """

    assert msg.sender == base.owner
    assert _address != empty(address)
    log LiquidationAddrChanged(old_addr=base.liquidation_addr, new_addr=_address)
    base.liquidation_addr = _address


@external
def set_proxy_authorization(_proxy: address, _value: bool):

    """
    @notice Set authorization
    @dev Sets the authorization for the given proxy and logs the event. Admin function.
    @param _proxy The address of the proxy.
    @param _value The value of the authorization.
    """

    assert msg.sender == base.owner

    base.authorized_proxies[_proxy] = _value

    log ProxyAuthorizationChanged(proxy=_proxy, value=_value)


@external
def propose_owner(_address: address):

    """
    @notice Propose a new owner
    @dev Proposes a new owner and logs the event. Admin function.
    @param _address The address of the proposed owner.
    """

    assert msg.sender == base.owner
    assert _address != empty(address)

    log OwnerProposed(owner=base.owner, proposed_owner=_address)
    base.proposed_owner = _address


@external
def claim_ownership():

    """
    @notice Claim the ownership of the contract
    @dev Claims the ownership of the contract and logs the event. Requires the caller to be the proposed owner.
    """

    assert msg.sender == base.proposed_owner

    log OwnershipTransferred(old_owner=base.owner, new_owner=base.proposed_owner)
    base.owner = msg.sender
    base.proposed_owner = empty(address)


@external
def set_transfer_agent(_address: address):

    """
    @notice Set transfer agent
    @dev Sets the transfer agent to the given address. Admin function.
    @param _address The address of the new transfer agent.
    """

    assert msg.sender == base.owner or msg.sender == base.transfer_agent
    log TransferAgentChanged(old_agent=base.transfer_agent, new_agent=_address, by=msg.sender)
    base.transfer_agent = _address



# Core functions

@external
def create_loan(
    offer: base.SignedOffer,
    principal: uint256,
    collateral_amount: uint256,
    borrower_kyc: base.SignedWalletValidation,
    lender_kyc: base.SignedWalletValidation
) -> bytes32:

    """
    @notice Create a loan.
    @param offer The signed offer.
    @param principal The principal amount of the loan.
    @param collateral_amount The amount of collateral tokens to be used for the loan.
    @param borrower_kyc The signed KYC validation for the borrower.
    @param lender_kyc The signed KYC validation for the lender.
    @return The ID of the created loan.
    """


    assert base._is_offer_signed_by_lender(offer, offer_sig_domain_separator), "offer not signed by lender"
    self._check_offer_validity(offer)

    borrower: address = msg.sender if not base.authorized_proxies[msg.sender] else tx.origin

    assert staticcall base.KYCValidator(kyc_validator_addr).check_validations_pair(borrower_kyc, lender_kyc), "KYC validation fail"
    assert lender_kyc.validation.wallet == offer.offer.lender, "KYC validation fail"
    assert borrower_kyc.validation.wallet == borrower, "KYC validation fail"
    assert offer.offer.borrower == empty(address) or offer.offer.borrower == borrower, "borrower not allowed"
    assert offer.offer.principal == 0 or offer.offer.principal == principal, "offer principal mismatch"
    assert offer.offer.min_collateral_amount <= collateral_amount, "low collateral amount"
    assert offer.offer.origination_fee_bps <= BPS, "origination fee gt principal"

    convertion_rate: base.UInt256Rational = self._get_oracle_rate()

    max_initial_ltv: uint256 = offer.offer.max_iltv
    if offer.offer.max_iltv == 0:
        max_initial_ltv = self._compute_ltv(offer.offer.min_collateral_amount, principal, convertion_rate)

    initial_ltv: uint256 = self._compute_ltv(collateral_amount, principal, convertion_rate)
    assert initial_ltv <= max_initial_ltv, "initial ltv gt max iltv"

    if offer.offer.liquidation_ltv > 0:
        assert offer.offer.liquidation_ltv > max_initial_ltv, "liquidation ltv le initial ltv"

    offer_id: bytes32 = base._compute_signed_offer_id(offer)
    loan: base.Loan = base.Loan(
        id=empty(bytes32),
        offer_id=offer_id,
        offer_tracing_id=offer.offer.tracing_id,
        initial_amount=principal,
        amount=principal,
        apr=offer.offer.apr,
        payment_token=offer.offer.payment_token,
        maturity=block.timestamp + offer.offer.duration,
        start_time=block.timestamp,
        accrual_start_time=block.timestamp,
        borrower=borrower,
        lender=offer.offer.lender,
        collateral_token=collateral_token,
        collateral_amount=collateral_amount,
        min_collateral_amount=offer.offer.min_collateral_amount,
        origination_fee_amount=offer.offer.origination_fee_bps * principal // BPS,
        protocol_upfront_fee_amount=base.protocol_upfront_fee * principal // BPS,
        protocol_settlement_fee=base.protocol_settlement_fee,
        partial_liquidation_fee=base.partial_liquidation_fee,
        full_liquidation_fee=base.full_liquidation_fee,
        call_eligibility=offer.offer.call_eligibility,
        call_window=offer.offer.call_window,
        liquidation_ltv=offer.offer.liquidation_ltv,
        oracle_addr=oracle_addr,
        initial_ltv=max_initial_ltv,
        call_time=0,
    )
    loan.id = base._compute_loan_id(loan)

    assert base.loans[loan.id] == empty(bytes32), "loan already exists"
    base._check_and_update_offer_state(offer, principal)
    base.loans[loan.id] = base._loan_state_hash(loan)

    _vault: vault.Vault = base._create_vault_if_needed(loan.borrower, vault_impl_addr, collateral_token, base.vault_registrar)
    base._receive_collateral(loan.borrower, loan.collateral_amount, _vault)
    self._transfer_funds(loan.lender, loan.borrower, loan.amount - loan.origination_fee_amount)

    if loan.protocol_upfront_fee_amount > 0:
        self._transfer_funds(loan.lender, base.protocol_wallet, loan.protocol_upfront_fee_amount)

    log LoanCreated(
        id=loan.id,
        amount=loan.initial_amount,
        apr=loan.apr,
        payment_token=loan.payment_token,
        maturity=loan.maturity,
        start_time=loan.start_time,
        borrower=loan.borrower,
        lender=loan.lender,
        collateral_token=loan.collateral_token,
        collateral_amount=loan.collateral_amount,
        min_collateral_amount=loan.min_collateral_amount,
        call_eligibility=loan.call_eligibility,
        call_window=loan.call_window,
        liquidation_ltv=loan.liquidation_ltv,
        oracle_addr=loan.oracle_addr,
        initial_ltv=loan.initial_ltv,
        origination_fee_amount=loan.origination_fee_amount,
        protocol_upfront_fee_amount=loan.protocol_upfront_fee_amount,
        protocol_settlement_fee=loan.protocol_settlement_fee,
        partial_liquidation_fee=loan.partial_liquidation_fee,
        full_liquidation_fee=loan.full_liquidation_fee,
        offer_id=offer_id,
        offer_tracing_id=offer.offer.tracing_id,
        oracle_rate_num=convertion_rate.numerator,
        oracle_rate_den=convertion_rate.denominator,
    )
    return loan.id


@external
def settle_loan(loan: base.Loan):

    """
    @notice Settle a loan.
    @param loan The loan to be settled.
    """

    assert base._is_loan_valid(loan), "invalid loan"
    assert not base._is_loan_defaulted(loan), "loan defaulted"
    assert base._check_user(loan.borrower), "not borrower"

    interest: uint256 = base._compute_settlement_interest(loan)
    protocol_settlement_fee: uint256 = loan.protocol_settlement_fee * interest // BPS

    base.loans[loan.id] = empty(bytes32)
    base._reduce_commited_liquidity(loan.lender, loan.offer_tracing_id, loan.amount)

    self._receive_funds(loan.borrower, loan.amount + interest)

    self._send_funds(loan.lender, loan.amount + interest - protocol_settlement_fee)
    if protocol_settlement_fee > 0:
        self._send_funds(base.protocol_wallet, protocol_settlement_fee)

    _vault: vault.Vault = base._get_vault(loan.borrower, vault_impl_addr)
    base._send_collateral(loan.borrower, loan.collateral_amount, _vault)

    log LoanPaid(
        id=loan.id,
        borrower=loan.borrower,
        lender=loan.lender,
        payment_token=loan.payment_token,
        paid_principal=loan.amount,
        paid_interest=interest,
        origination_fee_amount=loan.origination_fee_amount,
        protocol_upfront_fee_amount=loan.protocol_upfront_fee_amount,
        protocol_settlement_fee_amount=protocol_settlement_fee
    )


@external
def partially_liquidate_loan(loan: base.Loan):

    """
    @notice Partialy liquidates a loan if the LTV exceeds the liquidation_ltv, resulting in a write-off of part of the debt and transfer of part of the collateral to the lender. The loan remains active. Can be called by anyone.
    @param loan The loan to be soft liquidated.
    """
    raw_call(
        base.liquidation_addr,
        abi_encode(
            loan,
            payment_token,
            collateral_token,
            oracle_addr,
            oracle_reverse,
            kyc_validator_addr,
            collateral_token_decimals,
            payment_token_decimals,
            offer_sig_domain_separator,
            vault_impl_addr,
            method_id=method_id("partially_liquidate_loan((bytes32,bytes32,bytes32,uint256,uint256,uint256,address,uint256,uint256,uint256,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,uint256),address,address,address,bool,address,uint256,uint256,bytes32,address)"),
        ),
        is_delegate_call=True
    )



@external
def liquidate_loan(loan: base.Loan):

    """
    @notice Fully liquidates a defaulted loan. Can be called by anyone.
    @param loan The loan to be soft liquidated.
    """

    raw_call(
        base.liquidation_addr,
        abi_encode(
            loan,
            payment_token,
            collateral_token,
            oracle_addr,
            oracle_reverse,
            kyc_validator_addr,
            collateral_token_decimals,
            payment_token_decimals,
            offer_sig_domain_separator,
            vault_impl_addr,
            method_id=method_id("liquidate_loan((bytes32,bytes32,bytes32,uint256,uint256,uint256,address,uint256,uint256,uint256,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,uint256),address,address,address,bool,address,uint256,uint256,bytes32,address)"),
        ),
        is_delegate_call=True
    )

@external
def call_loan(loan: base.Loan):

    """
    @notice Call a loan.
    @param loan The loan to be called.
    """

    assert base._is_loan_valid(loan), "invalid loan"
    assert base._check_user(loan.lender), "not lender"

    assert loan.call_eligibility > 0, "loan not callable"
    assert loan.call_time == 0, "loan already called"
    assert block.timestamp >= loan.start_time + loan.call_eligibility, "call eligibility not reached"
    assert not base._is_loan_defaulted(loan), "loan defaulted"

    updated_loan: base.Loan = base.Loan(
        id=loan.id,
        offer_id=loan.offer_id,
        offer_tracing_id=loan.offer_tracing_id,
        initial_amount=loan.initial_amount,
        amount=loan.amount,
        apr=loan.apr,
        payment_token=loan.payment_token,
        maturity=loan.maturity,
        start_time=loan.start_time,
        accrual_start_time=loan.accrual_start_time,
        borrower=loan.borrower,
        lender=loan.lender,
        collateral_token=loan.collateral_token,
        collateral_amount=loan.collateral_amount,
        min_collateral_amount=loan.min_collateral_amount,
        origination_fee_amount=loan.origination_fee_amount,
        protocol_upfront_fee_amount=loan.protocol_upfront_fee_amount,
        protocol_settlement_fee=loan.protocol_settlement_fee,
        partial_liquidation_fee=loan.partial_liquidation_fee,
        full_liquidation_fee=loan.full_liquidation_fee,
        call_eligibility=loan.call_eligibility,
        call_window=loan.call_window,
        liquidation_ltv= loan.liquidation_ltv,
        oracle_addr=loan.oracle_addr,
        initial_ltv= loan.initial_ltv,
        call_time=block.timestamp,
    )
    base.loans[loan.id] = base._loan_state_hash(updated_loan)
    log LoanCalled(
        id=loan.id,
        borrower=loan.borrower,
        lender=loan.lender,
        call_time=updated_loan.call_time,
    )


@external
def add_collateral_to_loan(loan: base.Loan, collateral_amount: uint256):

    """
    @notice Add collateral to a loan.
    @param loan The loan to which collateral is to be added.
    @param collateral_amount The amount of collateral tokens to be added.
    """

    assert base._is_loan_valid(loan), "invalid loan"
    assert base._check_user(loan.borrower), "not borrower"
    assert not base._is_loan_defaulted(loan), "loan defaulted"

    convertion_rate: base.UInt256Rational = self._get_oracle_rate()
    outstanding_debt: uint256 = loan.amount + base._compute_settlement_interest(loan)
    old_ltv: uint256 = self._compute_ltv(loan.collateral_amount, outstanding_debt, convertion_rate)
    new_ltv: uint256 = self._compute_ltv(loan.collateral_amount + collateral_amount, outstanding_debt, convertion_rate)

    _vault: vault.Vault = base._get_vault(loan.borrower, vault_impl_addr)
    base._receive_collateral(loan.borrower, collateral_amount, _vault)

    updated_loan: base.Loan = base.Loan(
        id=loan.id,
        offer_id=loan.offer_id,
        offer_tracing_id=loan.offer_tracing_id,
        initial_amount=loan.initial_amount,
        amount=loan.amount,
        apr=loan.apr,
        payment_token=loan.payment_token,
        maturity=loan.maturity,
        start_time=loan.start_time,
        accrual_start_time=loan.accrual_start_time,
        borrower=loan.borrower,
        lender=loan.lender,
        collateral_token=loan.collateral_token,
        collateral_amount=loan.collateral_amount + collateral_amount,
        min_collateral_amount=loan.min_collateral_amount,
        origination_fee_amount=loan.origination_fee_amount,
        protocol_upfront_fee_amount=loan.protocol_upfront_fee_amount,
        protocol_settlement_fee=loan.protocol_settlement_fee,
        partial_liquidation_fee=loan.partial_liquidation_fee,
        full_liquidation_fee=loan.full_liquidation_fee,
        call_eligibility=loan.call_eligibility,
        call_window=loan.call_window,
        liquidation_ltv= loan.liquidation_ltv,
        oracle_addr=loan.oracle_addr,
        initial_ltv= loan.initial_ltv,
        call_time=loan.call_time
    )
    base.loans[updated_loan.id] = base._loan_state_hash(updated_loan)

    log LoanCollateralAdded(
        id=loan.id,
        borrower=loan.borrower,
        lender=loan.lender,
        collateral_token=loan.collateral_token,
        old_collateral_amount=loan.collateral_amount,
        new_collateral_amount=updated_loan.collateral_amount,
        old_ltv=old_ltv,
        new_ltv=new_ltv
    )

@external
def remove_collateral_from_loan(loan: base.Loan, collateral_amount: uint256):

    """
    @notice Add collateral to a loan.
    @param loan The loan to which collateral is to be added.
    @param collateral_amount The amount of collateral tokens to be added.
    """

    assert base._is_loan_valid(loan), "invalid loan"
    assert base._check_user(loan.borrower), "not borrower"
    assert not base._is_loan_defaulted(loan), "loan defaulted"

    assert loan.min_collateral_amount + collateral_amount <= loan.collateral_amount, "collateral bellow min"

    convertion_rate: base.UInt256Rational = self._get_oracle_rate()
    outstanding_debt: uint256 = loan.amount + base._compute_settlement_interest(loan)
    old_ltv: uint256 = self._compute_ltv(loan.collateral_amount, outstanding_debt, convertion_rate)
    new_ltv: uint256 = self._compute_ltv(loan.collateral_amount - collateral_amount, outstanding_debt, convertion_rate)

    assert loan.initial_ltv >= new_ltv, "ltv gt initial ltv"

    updated_loan: base.Loan = base.Loan(
        id=loan.id,
        offer_id=loan.offer_id,
        offer_tracing_id=loan.offer_tracing_id,
        initial_amount=loan.initial_amount,
        amount=loan.amount,
        apr=loan.apr,
        payment_token=loan.payment_token,
        maturity=loan.maturity,
        start_time=loan.start_time,
        accrual_start_time=loan.accrual_start_time,
        borrower=loan.borrower,
        lender=loan.lender,
        collateral_token=loan.collateral_token,
        collateral_amount=loan.collateral_amount - collateral_amount,
        min_collateral_amount=loan.min_collateral_amount,
        origination_fee_amount=loan.origination_fee_amount,
        protocol_upfront_fee_amount=loan.protocol_upfront_fee_amount,
        protocol_settlement_fee=loan.protocol_settlement_fee,
        partial_liquidation_fee=loan.partial_liquidation_fee,
        full_liquidation_fee=loan.full_liquidation_fee,
        call_eligibility=loan.call_eligibility,
        call_window=loan.call_window,
        liquidation_ltv= loan.liquidation_ltv,
        oracle_addr=loan.oracle_addr,
        initial_ltv= loan.initial_ltv,
        call_time=loan.call_time
    )
    base.loans[updated_loan.id] = base._loan_state_hash(updated_loan)

    _vault: vault.Vault = base._get_vault(loan.borrower, vault_impl_addr)
    base._send_collateral(loan.borrower, collateral_amount, _vault)

    log LoanCollateralRemoved(
        id=loan.id,
        borrower=loan.borrower,
        lender=loan.lender,
        collateral_token=loan.collateral_token,
        old_collateral_amount=loan.collateral_amount,
        new_collateral_amount=updated_loan.collateral_amount,
        old_ltv=old_ltv,
        new_ltv=new_ltv
    )

@external
def revoke_offer(offer: base.SignedOffer):

    """
    @notice Revoke an offer.
    @param offer The signed offer to be revoked.
    """

    assert base._check_user(offer.offer.lender), "not lender"
    assert offer.offer.expiration > block.timestamp, "offer expired"
    assert base._is_offer_signed_by_lender(offer, offer_sig_domain_separator), "offer not signed by lender"

    offer_id: bytes32 = base._compute_signed_offer_id(offer)
    assert not base.revoked_offers[offer_id], "offer already revoked"

    base._revoke_offer(offer_id, offer)


@external
def claim_pending_transfers():
    assert base.pending_transfers[msg.sender] > 0, "no pending transfers"
    _amount: uint256 = base.pending_transfers[msg.sender]
    base.pending_transfers[msg.sender] = 0

    assert extcall IERC20(payment_token).transfer(msg.sender, _amount), "error sending funds"
    log PendingTransfersClaimed(_to=msg.sender, amount=_amount)



@view
@external
def current_ltv(loan: base.Loan) -> uint256:

    """
    @notice Get the current LTV of a loan.
    @param loan The loan to get the current LTV for.
    @return The current LTV of the loan.
    """

    assert base._is_loan_valid(loan), "invalid loan"

    convertion_rate: base.UInt256Rational = self._get_oracle_rate()
    return self._compute_ltv(loan.collateral_amount, loan.amount + base._compute_settlement_interest(loan), convertion_rate)


@view
@external
def is_loan_defaulted(loan: base.Loan) -> bool:

    """
    @notice Check if a loan is defaulted.
    @param loan The loan to check.
    @return True if the loan is defaulted, false otherwise.
    """

    return base._is_loan_defaulted(loan)


@view
@external
def simulate_partial_liquidation(loan: base.Loan) -> base.PartialLiquidationResult:

    assert base._is_loan_valid(loan), "invalid loan"
    assert not base._is_loan_defaulted(loan), "loan defaulted"

    current_interest: uint256 = base._compute_settlement_interest(loan)
    convertion_rate: base.UInt256Rational = self._get_oracle_rate()
    current_ltv: uint256 = self._compute_ltv(loan.collateral_amount, loan.amount + current_interest, convertion_rate)

    assert current_ltv >= loan.liquidation_ltv, "ltv lt liquidation ltv"

    debt_written_off: uint256 = 0
    collateral_claimed: uint256 = 0
    liquidation_fee: uint256 = 0
    debt_written_off, collateral_claimed, liquidation_fee = self._compute_partial_liquidation(
        loan.collateral_amount,
        loan.amount + current_interest,
        loan.initial_ltv,
        loan.partial_liquidation_fee,
        convertion_rate,
    )

    assert debt_written_off < loan.amount + current_interest, "written off ge debt"

    return base.PartialLiquidationResult(
        collateral_claimed=collateral_claimed,
        liquidation_fee=liquidation_fee,
        debt_written_off=debt_written_off,
        updated_ltv=self._compute_ltv(loan.collateral_amount - collateral_claimed - liquidation_fee, loan.amount + current_interest - debt_written_off, convertion_rate)
    )


@external
def replace_loan(
    loan: base.Loan,
    offer: base.SignedOffer,
    principal: uint256,
    collateral_amount: uint256,
    lender_kyc: base.SignedWalletValidation,
) -> bytes32:

    """
    @notice Replace an existing loan by accepting a new offer over the same collateral. The current loan is settled and the new loan is created. Must be called by the borrower.
    @dev The borrower must be the same as the borrower of the current loan.
    @param loan The loan to be replaced.
    @param offer The new signed offer.
    @param principal The principal amount of the new loan, 0 means the outstanding debt
    @param collateral_amount The amount of collateral tokens to be used for the new loan.
    @param lender_kyc The signed KYC validation for the lender.
    @return The ID of the new loan.
    """
    return convert(raw_call(
        base.refinance_addr,
        abi_encode(
            loan,
            offer,
            principal,
            collateral_amount,
            lender_kyc,
            payment_token,
            collateral_token,
            oracle_addr,
            oracle_reverse,
            kyc_validator_addr,
            collateral_token_decimals,
            payment_token_decimals,
            offer_sig_domain_separator,
            vault_impl_addr,
            method_id=method_id("replace_loan((bytes32,bytes32,bytes32,uint256,uint256,uint256,address,uint256,uint256,uint256,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,uint256),((uint256,uint256,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,bytes32),(uint256,uint256,uint256)),uint256,uint256,((address,uint256),(uint256,uint256,uint256)),address,address,address,bool,address,uint256,uint256,bytes32,address)"),
        ),
        max_outsize=32,
        is_delegate_call=True
    ), bytes32)


@external
def replace_loan_lender(
    loan: base.Loan,
    offer: base.SignedOffer,
    principal: uint256,
    lender_kyc: base.SignedWalletValidation,
) -> bytes32:

    """
    @notice Sell an existing loan by accepting a new offer over the same collateral. The current loan is settled and the new loan is created. Must be called by the lender.
    @dev No collateral transfer is required. The borrower must be the same as the borrower of the current loan.
    @param loan The loan to be replaced.
    @param offer The new signed offer.
    @param principal The principal amount of the new loan, 0 means the outstanding debt
    @param lender_kyc The signed KYC validation for the lender.
    @return The ID of the new loan.
    """

    return convert(raw_call(
        base.refinance_addr,
        abi_encode(
            loan,
            offer,
            principal,
            lender_kyc,
            payment_token,
            collateral_token,
            oracle_addr,
            oracle_reverse,
            kyc_validator_addr,
            collateral_token_decimals,
            payment_token_decimals,
            offer_sig_domain_separator,
            method_id=method_id("replace_loan_lender((bytes32,bytes32,bytes32,uint256,uint256,uint256,address,uint256,uint256,uint256,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,uint256),((uint256,uint256,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,bytes32),(uint256,uint256,uint256)),uint256,((address,uint256),(uint256,uint256,uint256)),address,address,address,bool,address,uint256,uint256,bytes32)"),
        ),
        max_outsize=32,
        is_delegate_call=True
    ), bytes32)


@view
@external
def wallet_to_vault(wallet: address) -> address:

    """
    @notice Get the vault address for a given wallet
    @param wallet The wallet address
    @return The vault address for the given wallet
    """

    return base._wallet_to_vault(wallet, vault_impl_addr)

@external
def create_vault_if_needed(wallet: address):

    """
    @notice Create a vault for a given wallet if it does not exist
    @param wallet The wallet address
    """

    base._create_vault_if_needed(wallet, vault_impl_addr, collateral_token, base.vault_registrar)


@external
def transfer_loan(loan: base.Loan, new_borrower: address, new_borrower_kyc: base.SignedWalletValidation):

    """
    @notice Transfer a loan to a new borrower.
    @dev Only allowed to be called by the transfer agent. Used for supporting cases of death, lost keys, or legal transfers
    @param loan The loan to be transferred.
    @param new_borrower The address of the new borrower.
    @param new_borrower_kyc The signed KYC validation for the new borrower.
    """

    assert base._is_loan_valid(loan), "invalid loan"
    assert base._check_user(base.transfer_agent), "not transfer agent"
    assert new_borrower != loan.borrower, "new borrower same as current"

    assert staticcall base.KYCValidator(kyc_validator_addr).check_validation(new_borrower_kyc), "KYC validation fail"
    assert new_borrower_kyc.validation.wallet == new_borrower, "KYC validation fail"

    updated_loan: base.Loan = base.Loan(
        id=empty(bytes32),
        offer_id=loan.offer_id,
        offer_tracing_id=loan.offer_tracing_id,
        initial_amount=loan.initial_amount,
        amount=loan.amount,
        apr=loan.apr,
        payment_token=loan.payment_token,
        maturity=loan.maturity,
        start_time=loan.start_time,
        accrual_start_time=loan.accrual_start_time,
        borrower=new_borrower,
        lender=loan.lender,
        collateral_token=loan.collateral_token,
        collateral_amount=loan.collateral_amount,
        min_collateral_amount=loan.min_collateral_amount,
        origination_fee_amount=loan.origination_fee_amount,
        protocol_upfront_fee_amount=loan.protocol_upfront_fee_amount,
        protocol_settlement_fee=loan.protocol_settlement_fee,
        partial_liquidation_fee=loan.partial_liquidation_fee,
        full_liquidation_fee=loan.full_liquidation_fee,
        call_eligibility=loan.call_eligibility,
        call_window=loan.call_window,
        liquidation_ltv= loan.liquidation_ltv,
        oracle_addr=loan.oracle_addr,
        initial_ltv= loan.initial_ltv,
        call_time=loan.call_time
    )
    updated_loan.id = base._compute_loan_id(updated_loan)
    base.loans[updated_loan.id] = base._loan_state_hash(updated_loan)
    base.loans[loan.id] = empty(bytes32)

    base._send_collateral(
        base._create_vault_if_needed(new_borrower, vault_impl_addr, collateral_token, base.vault_registrar).address,
        loan.collateral_amount,
        vault.Vault(base._wallet_to_vault(loan.borrower, vault_impl_addr))
    )

    log LoanBorrowerTransferred(
        loan_id=loan.id,
        new_loan_id=updated_loan.id,
        old_borrower=loan.borrower,
        new_borrower=new_borrower,
        lender=loan.lender
    )

# Internal functions

@internal
def _is_offer_signed_by_lender(signed_offer: base.SignedOffer) -> bool:
    return base._is_offer_signed_by_lender(signed_offer, offer_sig_domain_separator)


@internal
def _check_offer_validity(offer: base.SignedOffer):
    base._check_offer_validity(offer, payment_token, collateral_token, oracle_addr)

@view
@internal
def _get_oracle_rate() -> base.UInt256Rational:
    return base._get_oracle_rate(oracle_addr, oracle_reverse)


@view
@internal
def _compute_ltv(collateral_amount: uint256, amount: uint256, convertion_rate: base.UInt256Rational) -> uint256:
    return base._compute_ltv(collateral_amount, amount, convertion_rate, payment_token_decimals, collateral_token_decimals)


@internal
def _send_funds(_to: address, _amount: uint256):
    base._send_funds(_to, _amount, payment_token)


@internal
def _receive_funds(_from: address, _amount: uint256):
    base._receive_funds(_from, _amount, payment_token)


@internal
def _transfer_funds(_from: address, _to: address, _amount: uint256):
    base._transfer_funds(_from, _to, _amount, payment_token)


@view
@internal
def _compute_partial_liquidation(
    collateral_amount: uint256,
    outstanding_debt: uint256,
    initial_ltv: uint256,
    partial_liquidation_fee: uint256,
    convertion_rate: base.UInt256Rational,
) -> (uint256, uint256, uint256):
    return base._compute_partial_liquidation(
        collateral_amount,
        outstanding_debt,
        initial_ltv,
        partial_liquidation_fee,
        convertion_rate,
        payment_token_decimals,
        collateral_token_decimals
    )
