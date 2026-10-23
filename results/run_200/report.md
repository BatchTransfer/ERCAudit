# ERCAudit combined run (sample 200)

200 ERC-1155 sources, 200 permit sources, 200 transactions.

## Batch transfers (ERC-1155 `safeBatchTransferFrom`)

174/200 analysable, 48 contracts violate at least one of the eight constraints.

| Risk class | Severity | Contracts |
|---|---|---:|
| Missing Access Control | Critical | 6 |
| Missing Address Validation | High | 11 |
| Missing Array Length Check | High | 12 |
| Event Emit Inconsistencies | Medium | 7 |
| Missing Interface Check | High | 38 |

Against the 193 manually labelled contracts of the sample: TP 32, FP 9, FN 9, TN 143 (precision 0.780, recall 0.780).

## On-chain transactions (calldata of the batch transfers)

200 `safeBatchTransferFrom` and 0 `setApprovalForAll` transactions of 10 contracts: 2 unauthorised, 0 zero-address, 0 length-mismatch (the shipped transactions contain no `setApprovalForAll`, so approval chains are not exercised here). Derived columns identical to the stored analysis: True.

## Signing domains (rules R1-R9)

175/200 contracts violate at least one rule.

| Rule | Violation | Obs. | On-chain confirmed | refuted | unresolved | not probed |
|---|---|---:|---:|---:|---:|---:|
| R1 | missing domain separator or EIP-191 framing | 26 | 16 | 6 | 2 | 2 |
| R2 | missing chainId in the domain | 20 | 14 | 0 | 6 | 0 |
| R3 | hardcoded chainId | 29 | 10 | 0 | 19 | 0 |
| R4 | deployment-supplied chainId (conditional) | 28 | 0 | 0 | 0 | 28 |
| R5 | missing verifyingContract in the domain | 24 | 7 | 0 | 17 | 0 |
| R6 | hardcoded verifier | 8 | 1 | 6 | 1 | 0 |
| R7 | externally supplied verifier (conditional) | 15 | 3 | 1 | 11 | 0 |
| R8 | stored domain separator without refresh | 100 | 29 | 1 | 70 | 0 |
| R9 | hardcoded or zero salt | 20 | 1 | 0 | 19 | 0 |

Manual precision (class level, labelled contracts that are still flagged): 132/157 = 0.841. On-chain columns are the stored verdicts joined to this run's findings ('not probed': no record in the artifact, e.g. R4).
