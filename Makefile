PY ?= python3

.PHONY: install test demo demo-200 smoke onchain-table reproduce-tx all

install:          ## editable install + test dependencies
	$(PY) -m pip install -e . -r requirements.txt

test:             ## 28 unit / end-to-end tests (~10 s)
	$(PY) -m pytest -q

demo:             ## unified run on the 100-file sample (~4 s): results/run_100/
	$(PY) combine_run.py --size 100

demo-200:         ## unified run on the 200-file sample (~6 s): results/run_200/
	$(PY) combine_run.py --size 200

smoke:            ## audit the synthetic examples: 1 compliant + 5 one-defect ERC-1155 contracts, 2 permit verifiers
	$(PY) -m ercaudit audit examples || true

onchain-table:    ## rules R1-R9 on-chain verification table for the whole corpus, from the stored verdicts
	$(PY) scripts/summarize_onchain.py

reproduce-tx:     ## transaction validator vs the stored analysis of all 1,094 transactions
	$(PY) scripts/reproduce_txaudit.py

all: install test demo demo-200 onchain-table reproduce-tx
