# ERCAudit

**Specification-guided auditing of ERC implementations, from the standard's text to deployed contracts.**
ERCAudit turns the normative requirements of Ethereum standards into source-level checks, runs them at scale and
validates the findings on chain. One tool, one pipeline, one report, three analysis modules:

| Module | Standard | Question | Risks reported |
|---|---|---|---|
| **BatchAudit** | ERC-1155 `safeBatchTransferFrom` | Does a batch transfer authorise the caller, validate the recipient, match array lengths, emit events in order and confirm receiver acceptance? | 5 automated classes: missing access control (critical); missing address validation, array-length check, interface check (high); event inconsistency (medium) |
| **DomAudit** | EIP-712, ERC-2612, ERC-5267 | Does the verifier bind every signature to the chain, contract, freshness state and logical domain the signer intended? | **R1-R9** in five authority boundaries C1-C5 (table below) |
| **On-chain analysis** | both | Do flagged contracts misbehave in deployed state or in real transactions? | TxAudit: zero-address, length-mismatch, unauthorised calls, secondary-approval chains. DomAudit: `confirmed / refuted / unresolved` verdicts per rule (separator recomputation, chain-ID fork test, `permit` simulation) |

| Class | Rule | Violation |
|---|---|---|
| C1 Domain separation | R1 | no domain separator or EIP-191 framing |
| C2 Chain binding | R2 / R3 / R4 | `chainId` missing / hard-coded / supplied at deployment (conditional) |
| C3 Verifier binding | R5 / R6 / R7 | `verifyingContract` missing / hard-coded / supplied externally (conditional) |
| C4 Domain freshness | R8 | stored domain separator without refresh |
| C5 Logical domain | R9 | hard-coded or zero salt |

Findings are **constraint violations, not proven exploits.**

## Docker (no setup)

```bash
docker build -t ercaudit .
docker run --rm ercaudit                              # audits the bundled examples
docker run --rm ercaudit ercaudit run --size 100      # unified run on the bundled sample
docker run --rm ercaudit python -m pytest -q          # 28 tests
```

## Web service

A small web page and API (`web/`) audits a pasted Solidity file with every applicable rule set. Run it with
`docker compose up -d --build` and open the host you configured; see [`docs/WEBSITE.md`](docs/WEBSITE.md) for the deployment on a Linux server.

## Quick start (about 2 minutes, offline)

```bash
git clone <this repository> ERCAudit && cd ERCAudit
python3 -m venv .venv && source .venv/bin/activate
pip install -e . -r requirements.txt
make test                       # 28 tests
make demo                       # unified run on the 100-file sample  -> results/run_100/
make demo-200                   # unified run on the 200-file sample  -> results/run_200/
```

`make demo` is `python combine_run.py --size 100` and also `ercaudit run --size 100`. It analyses 100 ERC-1155 sources,
100 permit sources and 100 transactions in about 4 s and writes:

| File | Content |
|---|---|
| `results/run_N/report.md`, `report.json` | merged summary of the three modules (deterministic) |
| `results/run_N/findings.csv` | one row per finding, all modules: `module, subject, address, rule, class, severity, evidence, onchain, manual` |
| `results/run_N/batchaudit.json`, `domaudit.json`, `txaudit.csv` | full per-contract / per-transaction output (git-ignored) |

The committed `report.md` of both sizes is the expected output; reruns must reproduce it exactly.

Single-contract use:

```bash
ercaudit audit path/to/Token.sol          # every applicable module, rule ids + severity; exit status 1 if anything is found
ercaudit audit examples                   # the 8 synthetic contracts (make smoke)
ercaudit batch analyze path/to/sources --jobs 8 -o batch.json     # corpus mode, per module
ercaudit dom   analyze path/to/sources --output-json d.json --output-summary s.json
ercaudit tx    analyze data/sample/tx_sample.csv -o analysed.csv [--strict]
```

## The sample

`data/sample/` is a deterministic, stratified sample (`scripts/make_sample.py`, seed 2026); the 100-file sample is a
prefix of the 200-file sample (`rank` column of the manifests). "Size N" means N files **per analyser**.

| Part | Size 100 | Size 200 | Source and labels |
|---|---:|---:|---|
| `batch/` ERC-1155 sources | 100 | 200 | BatchAudit labelled set; includes the 10 contracts whose transactions are shipped. Manual verdict: 32 / 41 non-compliant, 61 / 152 compliant, 7 unlabelled |
| `dom/` permit sources | 100 | 200 | DomAudit final precision sample: flagged contracts, 20 / 40 per class C1-C5; 180 carry a manual TP/FP label (145 TP, 35 FP) |
| `tx_sample.csv` | 100 | 200 | `safeBatchTransferFrom` transactions of 10 Ethereum contracts (the 2 unauthorised ones first); stored analysis for comparison |
| `onchain_dom_sample.jsonl` | | 276 records | stored on-chain verdicts of the sampled DomAudit contracts |

The sample is **enriched for defects** (it is built from flagged and labelled contracts); its rates are not prevalence.

## Whole-corpus on-chain table (R1-R9)

```bash
make onchain-table          # results/tables/onchain_verification.md
```

rebuilds the on-chain verification table of the DomAudit study from `results/onchain/*.jsonl` (17,005 contract
records) and prints the published values beside it. Eight of nine rules reproduce exactly; R1 differs by one contract
(12 refuted / 13 unresolved here, 11 / 14 published). R4 is taken from the published summary
(`results/onchain/r4_summary.json`) because its per-contract records are not part of this artifact.

## Layout

```
ercaudit/            package + CLI (ercaudit batch|tx|dom|run|select)
  solidity.py        shared Solidity front-end: functions, call graph, require/revert predicates
  batchaudit/        constraints, analyzer, taxonomy (risk classes), evaluation
  domaudit/          analyzer (facts -> rules), rules.py (internal categories -> R1-R9, C1-C5)
  txaudit/           calldata decoding, transaction patterns, Etherscan V2 client
  onchain.py         reading and aggregating on-chain verdicts
  pipeline.py        the unified run behind combine_run.py
combine_run.py       one-command driver
data/sample/         the 100/200-file sample (above)
data/transactions/   all 1,094 stored transactions + stored analysis
data/ground_truth/   BatchAudit labels (941 contracts, no sources); DomAudit labelled sample, 180-file category benchmark
data/specifications/ ERC specification JSON the constraints were derived from
results/onchain/     stored verdicts of the on-chain verifiers (R1-R3, R5-R9), recall check, R4 summary
results/run_100|200/ expected output of the unified run
scripts/             make_sample.py, summarize_onchain.py, reproduce_txaudit.py; maintainer/ = corpus-scale scripts
examples/            synthetic contracts: 1 compliant + 5 single-defect ERC-1155 mutants; 2 permit verifiers
tests/               28 tests (front-end, constraints, rules, tx patterns, on-chain reader, unified run)
paper/               ICSE tool-paper source (IEEEtran, 4 pages)
```

## What this artifact does and does not reproduce

| Item | Status |
|---|---|
| Unified run, both sizes | deterministic, committed expected output |
| TxAudit on all 1,094 stored transactions | every derived column identical to the stored analysis (`make reproduce-tx`) |
| On-chain table R1-R9 | 8/9 rules identical; R1 off by one (see above) |
| DomAudit manual precision, 180 labels | **84.1 % (132/157)** here vs 89.8 % (141/157) published: the 157 flagged contracts agree, the difference is 9 class-C3 contracts whose label targets the old R6 and which the final analyzer reports as R7 |
| BatchAudit precision / recall | only on the sample (see `report.md`); the 941-file figures need the full labelled sources (research tree) |
| Corpus-level counts (148,517 permit files, 19,298 observations; 9,275 ERC-1155 sources) | **not regenerable**: corpora are not shipped; the paper states them as published numbers |
| R4 per-contract records, secondary-approval chains (no `setApprovalForAll` in the shipped transactions), testnet exploits | not shipped |

Corpus-scale scripts (`scripts/maintainer/`) need the corpora, an Etherscan V2 key in `.env` (git-ignored), RPC access
and, for R8, Foundry's `anvil`; they are provided for provenance only.

## Limitations

Verified Solidity only; the front-end is regular-expression and brace-matching based (no compiler), so inheritance,
inline assembly and custom encodings can cause misses and false positives. Rules R4 and R7 are conditional and need chain
state; R6 depends on intent (16 % confirmed on decidable contracts) and is a review aid.

## Responsible use

Everything here is public code and public chain data. In this release, the addresses of the 49 contracts with confirmed, possibly unpatched
defects (26 tokens whose `permit` verifies no signature, and 23 ERC-1155 contracts without a caller check) are replaced by pseudonymous
identifiers of the form `0xdeadbeef...NNNN`, and the verdict records carry `REDACTED` in place of their names. All counts, tables and
expected outputs are unchanged. Please do not try to re-identify these contracts. Report findings to the contract owners.

## Licence and citation

No licence is chosen yet; add one before archiving (Zenodo DOI for the *Available* badge). Cite the BatchAudit and
DomAudit studies and the ERCAudit tool paper (`paper/main.tex`).

## Demo video

`video/ercaudit_demo.mp4` is the demo video of the tool.
