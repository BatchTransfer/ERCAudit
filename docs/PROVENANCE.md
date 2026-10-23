# Provenance of the shipped data

| Path | Origin (research tree `ERC-Analysis-master-ICSE-tool`) | Modification |
|---|---|---|
| `ercaudit/` | package of the same name | `domaudit/` is the 21 Oct 2026 revision that reports the nine final rules; optional LLM cross-check removed; `onchain.py`, `pipeline.py`, `RULE_TITLES` added |
| `data/sample/batch` | `data/ground_truth/batchaudit/sources` (+ `legacy/.../ERC1155-ethereum` for 7 transaction contracts) | selected by `scripts/make_sample.py` |
| `data/sample/dom` | `data/ground_truth/domaudit/precision_sample_final/files` | flattened |
| `data/sample/tx_sample*.csv` | `data/transactions/{raw,analysed_txs_1094_stored}.csv` | ranked subset |
| `data/sample/onchain_dom_sample.jsonl` | `results/onchain/r*_verify*.jsonl` | rows of the sampled files, `rule` added |
| `data/ground_truth/batchaudit/ground_truth.json` | same | none (labels of 1,032 contracts, 941 usable; sources not shipped) |
| `data/ground_truth/domaudit/precision_sample_final` | same | labels `manifest_labeled.csv` (final R1-R9); earlier label versions kept for audit |
| `results/onchain/*.jsonl` | `results/onchain` | final pass per rule only (R8: `r8_verify.jsonl`); superseded passes omitted |
| `results/onchain/r4_summary.json` | DomAudit study table | typed in from the study; raw records absent |
| `scripts/maintainer/` | `scripts/` | verbatim; need corpora, API keys, RPC and `anvil` |

## Known differences from published numbers

1. **DomAudit manual precision.** Re-running the shipped analyzer on the 180 labelled contracts flags 157 (as published)
   but yields 132 true positives (84.1 %), not 141 (89.8 %). The nine contracts concerned are labelled false positive
   for R6 ("verifier supplied at initialisation / delegated by design") and are reported by the final analyzer as R7, a
   conditional rule decided on chain. The labels were not updated for the final rule numbering.
2. **R1 on-chain verdicts.** 12 refuted / 13 unresolved versus 11 / 14 published (one contract).
3. **Rule numbering inside the analyzer.** `critical_issues` strings of `domaudit/analyzer.py` still use the historical
   numbering (R3 = missing chainId, R4 = hard-coded chainId, ...). The R1-R9 of the paper are produced only through
   `domaudit/rules.py`; use `paper_rules()` and `findings.csv`, not the raw strings.
4. **BatchAudit precision.** The study reports precision 0.804 (37/46) and recall 0.902 (37/41) on 941 labelled contracts. The labels
   shipped in `data/ground_truth/batchaudit/ground_truth.json` confirm 37 true positives and 4 false negatives, but 20 contracts that the
   stored (labelling-time) tool output flags are manually compliant (9 annotated as false positives, 11 not), and the research tree's
   fresh re-run of the current revision gives precision 0.44 and recall 0.78 (its `docs/AUDIT_REPORT.md`, F3). The 941 sources are not part
   of this artifact, so the figures cannot be recomputed here; the paper cites 0.804 as published and states the discrepancy.
5. **Sample rates.** The samples are built from flagged and labelled contracts and are enriched for defects.
