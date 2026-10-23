"""BatchAudit driver: per-contract analysis (Algorithm 1) and corpus scanning.

``analyze_source`` is the cleaned ``analyze_safeBatchTransfer_interprocedural_analysis``
from the original research script and ``analyze_directory`` its corpus driver.
The result schema is the one used in the published result files
(``results/paper/*.json``), extended with optional informational fields.
"""
from __future__ import annotations

import json
import os
import signal
try:
    from concurrent.futures import ProcessPoolExecutor
except ImportError:  # browsers (Pyodide) have no multiprocessing; only the corpus driver needs it
    ProcessPoolExecutor = None
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional

from ..solidity import (
    SAFE_BATCH_TRANSFER_SIG,
    contains_assembly,
    find_all_functions,
    find_functions_by_signature,
    get_all_internal_calls,
)
from .constraints import REQUIREMENTS, apply_helper_name_hints, verify_batch_requirements

#: Error string emitted by the published pipeline when the target function has
#: no in-contract callees (``for f in None`` raised ``TypeError``).
LEAF_FUNCTION_ERROR = "Error processing file: 'NoneType' object is not iterable"


def analyze_source(
    solidity_code: str,
    target_sig: str = SAFE_BATCH_TRANSFER_SIG,
    *,
    include_leaf_functions: bool = False,
    ternary_resets: bool = True,
) -> Dict:
    """Analyse one Solidity source for ERC-1155 batch-transfer compliance.

    Parameters
    ----------
    include_leaf_functions:
        Paper-compatible default (``False``): a ``safeBatchTransferFrom`` whose
        body calls no other in-contract function is reported as an error, exactly
        as in the published runs (0.5% of contracts). ``True`` analyses such
        functions on their own body instead.
    ternary_resets:
        See :func:`ercaudit.batchaudit.constraints.verify_batch_requirements`.

    Returns
    -------
    ``{"all_implementations": [...], "summary": {...}}`` on success, otherwise
    ``{"error": "..."}``.
    """
    all_functions = find_all_functions(solidity_code)
    target_funcs = find_functions_by_signature(all_functions, target_sig)
    if not target_funcs:
        return {"error": "safeBatchTransferFrom function not found"}

    results: List[Dict] = []
    for target_func in target_funcs:
        # Inline assembly in the entry point makes the regex analysis unsound:
        # skip the remaining implementations (the published "assembly_delete" runs).
        if contains_assembly(target_func["body"]):
            break

        internal_calls = get_all_internal_calls(target_func["body"], all_functions)
        if internal_calls is None:
            if not include_leaf_functions:
                return {"error": LEAF_FUNCTION_ERROR, "error_kind": "no_internal_calls"}
            internal_calls = []

        requirements = verify_batch_requirements(target_func, internal_calls, ternary_resets=ternary_resets)
        requirements = apply_helper_name_hints(internal_calls, requirements)

        all_met = all(requirements.get(r, False) for r in REQUIREMENTS)
        some_met = any(requirements.get(r, False) for r in REQUIREMENTS)

        results.append({
            "function": target_func["name"],
            # NOTE: the published field is labelled "Line" but holds *character offsets*;
            # kept for compatibility, true line numbers are added alongside.
            "implementation_location": f"Line {target_func['start']}-{target_func['end']}",
            "line_start": solidity_code.count("\n", 0, target_func["start"]) + 1,
            "line_end": solidity_code.count("\n", 0, target_func["end"]) + 1,
            "parameters": target_func.get("parameters", {}),
            "requirements": requirements,
            "internal_calls": [f["name"] for f in internal_calls],
            "on_received_check_found": requirements.get("on_received_check", False),
            "all_requirements_met": all_met,
            "some_requirements_met": some_met,
            # informational, not part of the eight requirements (paper Sec. III-D.6, "IET"):
            "gas_iet_safetransferfrom_in_batch": any(f["name"] == "safeTransferFrom" for f in internal_calls),
        })

    if results:
        return {
            "all_implementations": results,
            "summary": {
                "total_implementations": len(results),
                "fully_compliant": sum(1 for r in results if r["all_requirements_met"]),
                "partially_compliant": sum(1 for r in results if r["some_requirements_met"]),
            },
        }
    return {"error": "No valid implementations found (possibly due to recursive calls)"}


# --------------------------------------------------------------------------
# Corpus driver
# --------------------------------------------------------------------------

class _Timeout(Exception):
    pass


def _analyze_file(args) -> Dict:
    path, target_sig, include_leaf, timeout, *rest = args
    ternary_resets = rest[0] if rest else True
    use_alarm = bool(timeout) and hasattr(signal, "SIGALRM")
    if use_alarm:
        def _raise(_signum, _frame):
            raise _Timeout()
        signal.signal(signal.SIGALRM, _raise)
        signal.setitimer(signal.ITIMER_REAL, timeout)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            code = fh.read()
        result = analyze_source(code, target_sig, include_leaf_functions=include_leaf, ternary_resets=ternary_resets)
    except _Timeout:
        result = {"error": f"Timeout after {timeout}s", "error_kind": "timeout"}
    except Exception as exc:  # noqa: BLE001 - mirror the published pipeline: record and continue
        result = {"error": f"Error processing file: {exc}"}
    finally:
        if use_alarm:
            signal.setitimer(signal.ITIMER_REAL, 0)
    result["file"] = path
    return result


def iter_solidity_files(directory: str) -> Iterable[str]:
    """Deterministically enumerate ``*.sol`` files below ``directory``."""
    for root, dirs, files in os.walk(directory):
        dirs.sort()
        for name in sorted(files):
            if name.endswith(".sol"):
                yield os.path.join(root, name)


def analyze_directory(
    directory: str,
    output_file: Optional[str] = None,
    target_sig: str = SAFE_BATCH_TRANSFER_SIG,
    *,
    jobs: int = 1,
    timeout: Optional[float] = None,
    include_leaf_functions: bool = False,
    ternary_resets: bool = True,
    limit: Optional[int] = None,
    progress: Optional[Callable[[int, int], None]] = None,
    file_list: Optional[str] = None,
) -> List[Dict]:
    """Analyse every ``*.sol`` below ``directory`` (or the paths in ``file_list``, one per line)."""
    if file_list:
        with open(file_list, encoding="utf-8") as fh:
            files = [ln.strip() for ln in fh if ln.strip().endswith(".sol")]
    else:
        files = list(iter_solidity_files(directory))
    if limit:
        files = files[:limit]
    tasks = [(f, target_sig, include_leaf_functions, timeout, ternary_resets) for f in files]

    results: List[Dict] = []
    if jobs and jobs > 1:
        with ProcessPoolExecutor(max_workers=jobs) as pool:
            for i, res in enumerate(pool.map(_analyze_file, tasks, chunksize=8), 1):
                results.append(res)
                if progress:
                    progress(i, len(tasks))
    else:
        for i, task in enumerate(tasks, 1):
            results.append(_analyze_file(task))
            if progress:
                progress(i, len(tasks))

    if output_file:
        save_results(results, output_file)
    return results


def save_results(results: List[Dict], output_path: str) -> None:
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
