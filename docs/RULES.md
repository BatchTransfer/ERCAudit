# ERCAudit rules: basis, preconditions, false positives and on-chain decidability

ERCAudit has **17 rules in ten risk classes**: eight rules for ERC-1155 batch transfers (five of them checked statically, classes B1 to B5)
and nine rules for EIP-712 / ERC-2612 signing domains (classes C1 to C5). This file explains each rule beyond the short tables of the paper.
It answers four questions for every rule: *where does it come from* (normative or recommended), *what must hold for it to matter*,
*when does it raise a false alarm*, and *can the on-chain probe decide it*.

Terms: a **rule** is a checkable requirement taken from a standard. A **class** groups rules by the boundary they protect.
A **finding** is a violated rule with its source lines. It is a constraint violation, not a proven exploit.

**Basis levels.** *Normative* = the standard says MUST / MUST NOT. *Recommended* = SHOULD, MAY or a stated common choice.
*Practice* = the standard does not require it, but its security considerations, public audit findings or incident reports do.
Wording below is paraphrased from [EIP-1155](https://eips.ethereum.org/EIPS/eip-1155), [EIP-712](https://eips.ethereum.org/EIPS/eip-712)
and [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612).

## 1. Batch-transfer rules (ERC-1155 `safeBatchTransferFrom`)

Precondition for all of them: the contract implements `safeBatchTransferFrom`, its source is available, and the entry point has no inline assembly
(such contracts are skipped, never guessed). The batch rules need **no adversary model**: they follow directly from the standard's text.
Code: [`ercaudit/batchaudit/constraints.py`](../ercaudit/batchaudit/constraints.py), classes and severities in [`taxonomy.py`](../ercaudit/batchaudit/taxonomy.py).

| # | Rule (class, severity) | Basis in EIP-1155 | What ERCAudit checks | Expected false alarms | On-chain probe |
|---|---|---|---|---|---|
| 1 | **Authorization** (B1 access control, Critical) | **Normative.** The caller MUST be approved to manage the tokens leaving `_from`. | A `require` or `if ... revert` in the entry point or its in-contract callees that compares `msg.sender` (or `_msgSender()`) with `from` (`sender_check`). An `isApprovedForAll(from, sender)` lookup is recorded (`approval_check`) but does not create a class on its own. | Authorization done in a modifier, library or inherited function that the lexical front-end does not resolve; operator maps with unusual names. | **Partly.** Transaction replay flags callers that are not `from` and have no recorded approval (`unauthorized`). This shows use of the gap, not the missing check. |
| 2 | **Recipient validity** (B2 address validation, High) | **Normative.** MUST revert if `_to` is the zero address. | A predicate that rejects `to == address(0)` in the entry point or its callees (`zero_address_check`). | Check hidden in a helper with an unusual name; custom mint/burn variants that allow the zero address on purpose. | **Yes.** A successful transfer whose decoded `to` is `0x0` confirms that the contract accepted a burn to the zero address. |
| 3 | **Balance sufficiency** (no class) | **Normative.** MUST revert if a balance is below the amount sent. | **Not checked.** It is a state and arithmetic property (checked arithmetic, `SafeMath`), not a syntactic one. | n/a | Not probed. |
| 4 | **Array integrity** (B3 array-length check, High) | **Normative.** MUST revert if `_ids` and `_values` differ in length. (The standard does not require non-empty arrays, and ERCAudit checks equality only.) | A predicate equating the lengths, directly or through an alias such as `n = ids.length` (`length_matching_check`). | Equality enforced only implicitly (for example an out-of-bounds read in a loop), which the standard accepts but the pattern check does not see. | **Yes.** A successful transaction with `len(ids) != len(values)` confirms the gap (`length_mismatch`). The study observed none. |
| 5 | **Atomicity** (no class) | **Normative.** MUST revert on any other error. | **Not checked.** It is a whole-execution property. | n/a | Not probed. |
| 6 | **Event emission** (B4 event inconsistency, Medium) | **Normative** that a `TransferBatch` or `TransferSingle` event reflects every balance change, with updates and events **before** any receiver call. `TransferBatch` is a SHOULD for multiple tokens. | `emit TransferBatch(` is present (`transfer_batch_event_found`) and appears before the receiver-hook call (`event_emission_order`). | A loop of `TransferSingle` events is allowed by the standard but is reported; events emitted in a helper with an unusual name. | **No.** Logs are not inspected. |
| 7 | **Interface compliance** (B5 interface check, High) | **Normative.** For a contract recipient the transfer MUST call `onERC1155BatchReceived` (or the single hook), MUST accept only the magic value `0xbc197c81`, and MUST revert otherwise. | A code-size test of `to` (`extcodesize`, `isContract`, `.code.length`; `to_isContract_check`) and a hook call whose return value is compared with the selector (`on_received_check`). | Hook call wrapped in a library or inherited helper (partly handled by name hints); unusual wrappers. | **Partly.** A receiver check reads the recipient's code and verified ABI for the hook. It shows the hook is declared, not that it behaves. |
| 8 | **Gas efficiency** (no class) | **Practice.** The standard only says batching reduces gas. It sets no limit. | **Not one of the ten classes and not checked.** The study triaged 84 gas findings manually. | n/a | Not probed. |

## 2. Signing-domain rules (EIP-712, ERC-2612, ERC-5267, ERC-1271)

Preconditions for all of them: the contract verifies EIP-712 typed-data signatures (for example `permit`), and the adversary model of the paper holds.
The attacker obtains a valid signature `sigma` and its message `m` (public calldata, relay), can deploy contracts and send transactions, and cannot forge signatures,
steal keys, change deployed code or skip the target's own checks (signer recovery, nonce, deadline). A violation is a **replay condition**: it becomes an exploit only if
a state-changing target accepts the replayed authorization. Code: [`ercaudit/domaudit/analyzer.py`](../ercaudit/domaudit/analyzer.py), mapping to R1 to R9 in [`rules.py`](../ercaudit/domaudit/rules.py).

EIP-712 makes every domain field optional ("only the fields that make sense for the signing domain"), so **R2 to R9 are security practice, not MUST requirements**.
The one normative anchor is the digest encoding of R1. Counts below come from the whole-corpus on-chain verification (Table III of the paper).
*Decided* = the probe returned confirmed or refuted; the rest are unresolved (no readable separator, custom layout).

| Rule (class, severity) | Requirement | Basis | What ERCAudit checks | Expected false alarms | On-chain probe, decided share, result |
|---|---|---|---|---|---|
| **R1** Missing separator or framing (C1, High) | The signed digest binds a domain separator and the `0x1901` prefix. | **Normative** for EIP-712: the digest is `keccak256("\x19\x01" ‖ domainSeparator ‖ hashStruct(message))`. ERC-2612 requires `DOMAIN_SEPARATOR()` as defined by EIP-712. | A permit or typed-data digest without a separator reference or without the prefix. | Delegator or proxy stubs whose separator is defined in the implementation; declarations without a body. | Simulate `permit` through `eth_call` with an invalid signature: if it does not revert, no signature is verified. Decided 38 of 51 (75%): **26 confirmed** (permit verifies no signature), 12 refuted. |
| **R2** Missing `chainId` (C2, High) | The domain includes the chain ID. | **Recommended.** EIP-712: clients should refuse to sign if `chainId` differs from the active chain. ERC-2612: common choice. Rationale as in EIP-155. | The `EIP712Domain` type or construction has no `chainId`, and no salt bound to the chain. | Chain bound elsewhere (in each message, a salt, or a library argument). | Recompute the separator with and without `chainId`; same separator at the same address on other chains. Decided 76 of 116 (66%): **76 confirmed**, 0 refuted. |
| **R3** Hard-coded `chainId` (C2, High) | The chain ID is not a fixed constant. | **Practice.** ERC-2612 security considerations warn about chain splits; audit finding [Swivel #98](https://github.com/code-423n4/2021-09-swivel-findings/issues/98). | The chain value is a literal or constant (named constants resolved), not `block.chainid` or `chainid()`. | Deliberate single-chain deployments; constants that equal the deployed chain today (194 of the 292 decided cases: a fork-and-copy risk, not a wrong value). | Source value versus chain, then recompute. Decided 292 of 522 (56%): **284 confirmed**, 8 refuted. |
| **R4** Deployment-supplied `chainId` (C2, conditional) | The ID passed at deployment equals the deployed chain. | **Practice.** | The chain ID comes from a constructor or initializer parameter. | Correct value passed (979 of 1,008 decided). | Decode constructor arguments or `initialize` calldata and compare. Decided 1,008 of 1,151 (88%): **29 wrong chain ID**, 979 correct. |
| **R5** Missing verifier (C3, High) | The domain includes the verifying contract address. | **Recommended.** EIP-712: `verifyingContract` may be used for phishing prevention. ERC-2612: common choice. | The type or construction has no `verifyingContract`. | Verifier hashed into another field or omitted by design. | Recompute with and without the verifier. Decided 15 of 58 (26%): **15 confirmed**. |
| **R6** Hard-coded verifier (C3, High) | The verifier is `address(this)`, not a literal address. | **Practice.** | `verifyingContract` is a literal address. | Deliberate delegation to a target contract (order book, wallet module). **This rule depends on intent**: it is a review aid. | Candidate verifiers from literals, immutables and storage. Decided 38 of 170 (22%): 6 confirmed, **32 refuted**. |
| **R7** Externally supplied verifier (C3, conditional) | A verifier passed at deployment is the contract itself. | **Practice.** | The verifier comes from a constructor or initializer parameter, or an argument of the domain function. | Parameter equals the contract (proxy patterns). | Candidate verifiers and deployment arguments. Decided 85 of 262 (32%): **72 bind a foreign verifier**, 13 bind the contract. |
| **R8** Stored separator without refresh (C4, High) | A stored separator is recomputed when the chain or verifier changes. | **Practice.** ERC-2612 security considerations warn that a separator fixed at deployment enables cross-chain replay after a chain split; audit finding [VVV #161](https://github.com/sherlock-audit/2024-11-vvv-exchange-update-judging/issues/161). The standard states no rule. | The separator is assigned in a constructor or initializer (or proxy-stale) and used in `permit` without recomputation or a chain-ID check. | Refresh patterns the lexical analysis does not recognize. | Fork the chain twice at the same block with different chain IDs (`anvil`) and read the separator getter. Decided 7,651 of 16,881 (45%): **7,438 unchanged (97%)**, 213 refreshed. |
| **R9** Hard-coded salt (C5, High) | The salt is not zero and not shared by all deployments. | **Practice.** EIP-712 calls the salt a "domain separator of last resort" and gives it no keyword. | A salt that is zero or a constant. | A salt that is unique per deployment. | Candidate salts. Decided 3 of 75 (4%): **3 confirmed**. |

## 3. How the ten classes are counted

Five batch-transfer classes: **B1** access control, **B2** address validation, **B3** array-length check, **B4** event inconsistency, **B5** interface check.
Five signing-domain classes: **C1** domain separation (R1), **C2** chain binding (R2, R3, R4), **C3** verifier binding (R5, R6, R7), **C4** domain freshness (R8), **C5** logical domain (R9).
Gas (rule 8 above) is triaged manually and is not counted.

## 4. Where to look in the code

| Topic | File |
|---|---|
| Batch-transfer checks and flags | `ercaudit/batchaudit/constraints.py` |
| Classes, severities | `ercaudit/batchaudit/taxonomy.py` |
| Signing-domain facts and checks | `ercaudit/domaudit/analyzer.py` |
| Mapping to R1 to R9 and C1 to C5 | `ercaudit/domaudit/rules.py` |
| On-chain verdicts and the table above | `results/onchain/`, `scripts/summarize_onchain.py` |
