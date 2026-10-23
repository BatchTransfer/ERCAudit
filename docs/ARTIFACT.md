# Artifact description

**Title.** ERCAudit: specification-guided auditing of ERC implementations (BatchAudit, DomAudit, on-chain analysis).
**Badges targeted.** Available (after licence and archive), Functional, Reusable.

**Requirements.** Python >= 3.9; about 100 MB disk; no GPU; no network for any command in the README quick start.
Tested on macOS 15, Intel i7-9750H, 32 GB, Python 3.9.19.

**Steps.** `pip install -e . -r requirements.txt`; `make test` (28 passed); `make demo` and `make demo-200` (compare
`results/run_N/report.md` with the committed copy); `make onchain-table`; `make reproduce-tx`.

**Extending.** A new standard is a rule set: (1) a function mapping extracted facts to named boolean constraints
(see `ercaudit/batchaudit/constraints.py`), (2) a constraint-to-class table (`taxonomy.py`), (3) a compliant / single-defect
example pair and a test. The front-end, driver, JSON schema and unified report are shared.

**Limits.** See `README.md` ("What this artifact does and does not reproduce") and `PROVENANCE.md`.
