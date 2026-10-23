#!/usr/bin/env python3
"""Build the static GitHub Pages site in docs/: the analyzer runs in the visitor's browser (Pyodide), nothing is uploaded.

Copies the pure-Python part of the package and the examples into docs/app/. Run it after changing the analyzers and commit the result.
"""
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "docs" / "app"
MODULES = ["ercaudit/__init__.py", "ercaudit/solidity.py", "ercaudit/webcore.py",
           "ercaudit/batchaudit/__init__.py", "ercaudit/batchaudit/analyzer.py", "ercaudit/batchaudit/constraints.py",
           "ercaudit/batchaudit/taxonomy.py", "ercaudit/batchaudit/evaluation.py",
           "ercaudit/domaudit/__init__.py", "ercaudit/domaudit/analyzer.py", "ercaudit/domaudit/rules.py"]
EXAMPLES = {"Batch transfer without address validation": "examples/batch/vuln_missing_address_validation.sol",
            "Batch transfer without array-length check": "examples/batch/vuln_missing_array_length_check.sol",
            "Batch transfer without caller check": "examples/batch/vuln_missing_access_control.sol",
            "Compliant batch transfer": "examples/batch/compliant.sol",
            "Replayable permit (R3, R6, R8)": "examples/domain/permit_replayable.sol",
            "Safe permit": "examples/domain/permit_safe.sol"}

if APP.exists():
    shutil.rmtree(APP)
(APP / "examples").mkdir(parents=True)
for m in MODULES:
    (APP / m).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(ROOT / m, APP / m)
index = {}
for title, rel in EXAMPLES.items():
    name = Path(rel).name
    shutil.copy(ROOT / rel, APP / "examples" / name)
    index[title] = f"examples/{name}"
(APP / "files.json").write_text(json.dumps(MODULES))
(APP / "examples.json").write_text(json.dumps(index, indent=1))
(ROOT / "docs" / ".nojekyll").write_text("")
print(f"site files written to {APP}")
