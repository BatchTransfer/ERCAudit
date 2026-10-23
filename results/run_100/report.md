# ERCAudit combined run (sample 100)

100 ERC-1155 sources, 100 permit sources, 100 transactions.

## Batch transfers (ERC-1155 `safeBatchTransferFrom`)

88/100 analysable, 36 contracts violate at least one of the eight constraints.

| Risk class | Severity | Contracts |
|---|---|---:|
| Missing Access Control | Critical | 4 |
| Missing Address Validation | High | 6 |
| Missing Array Length Check | High | 9 |
| Event Emit Inconsistencies | Medium | 4 |
| Missing Interface Check | High | 28 |

Against the 93 manually labelled contracts of the sample: TP 25, FP 4, FN 7, TN 57 (precision 0.862, recall 0.781).

## On-chain transactions (calldata of the batch transfers)

100 `safeBatchTransferFrom` and 0 `setApprovalForAll` transactions of 10 contracts: 2 unauthorised, 0 zero-address, 0 length-mismatch (the shipped transactions contain no `setApprovalForAll`, so approval chains are not exercised here). Derived columns identical to the stored analysis: True.

## Signing domains (rules R1-R9)

89/100 contracts violate at least one rule.

| Rule | Violation | Obs. | On-chain confirmed | refuted | unresolved | not probed |
|---|---|---:|---:|---:|---:|---:|
| R1 | missing domain separator or EIP-191 framing | 12 | 9 | 3 | 0 | 0 |
| R2 | missing chainId in the domain | 20 | 14 | 0 | 6 | 0 |
| R3 | hardcoded chainId | 17 | 4 | 0 | 13 | 0 |
| R4 | deployment-supplied chainId (conditional) | 6 | 0 | 0 | 0 | 6 |
| R5 | missing verifyingContract in the domain | 24 | 7 | 0 | 17 | 0 |
| R6 | hardcoded verifier | 3 | 0 | 3 | 0 | 0 |
| R7 | externally supplied verifier (conditional) | 5 | 0 | 0 | 5 | 0 |
| R8 | stored domain separator without refresh | 45 | 9 | 0 | 36 | 0 |
| R9 | hardcoded or zero salt | 0 | 0 | 0 | 0 | 0 |

Manual precision (class level, labelled contracts that are still flagged): 63/72 = 0.875. On-chain columns are the stored verdicts joined to this run's findings ('not probed': no record in the artifact, e.g. R4).
