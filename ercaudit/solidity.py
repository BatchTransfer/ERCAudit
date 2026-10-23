"""Lightweight Solidity front-end shared by all ERCAudit analyzers.

This module contains the source-level program-representation layer that the
BatchAudit study used (paper Sec. IV, Phase 2 and Algorithm 1). It is
deliberately *not* a full Solidity parser: it recovers function declarations,
bounded call-graph edges and security-relevant predicates with regular
expressions and brace matching, which is what makes the analysis scale to
millions of contracts.

The functions below are the original research code
(``erc1155_safeBatchTransferFrom.py``) cleaned for readability. Their logic --
including a few deliberate quirks that the published numbers depend on -- is
unchanged; every quirk is documented where it occurs.
"""
from __future__ import annotations

import re
from typing import Dict, List, Optional, Set, Tuple

Function = Dict[str, object]
CodeBlock = Tuple[str, str]  # (source text, provenance label)

# --------------------------------------------------------------------------
# Signature handling
# --------------------------------------------------------------------------

#: Canonical signature of the analysed ERC-1155 batch-transfer entry point.
SAFE_BATCH_TRANSFER_SIG = (
    "safeBatchTransferFrom(address from, address to, uint256[] memory ids, "
    "uint256[] memory amounts, bytes memory data)"
)
#: ``bytes4(keccak256("safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)"))``
SAFE_BATCH_TRANSFER_SELECTOR = "2eb2c2d6"


def normalize_signature(signature: str) -> str:
    """Reduce a Solidity function signature to its canonical ABI form.

    Parameter names and storage locations are dropped and a bare ``uint`` is
    widened to ``uint256`` (matching Etherscan's behaviour), while explicit
    widths such as ``uint8`` are kept.
    """
    if "(" not in signature:
        return signature

    func_name = signature.split("(")[0].strip()
    params = signature[len(func_name):].strip("()").split(",")

    param_types = []
    for param in params:
        param = param.strip()
        if " " in param:  # drop the parameter name (text after the last space)
            param = param.rsplit(" ", 1)[0].strip()
        param = re.sub(r"\s+(memory|calldata|storage)\b", "", param)
        if param == "uint" or re.match(r"uint(?!\d)", param):
            param = "uint256"
        param_types.append(param)

    return f"{func_name}({','.join(param_types)})"


def get_parameter_dict(params_str: str) -> Dict[str, str]:
    """Map ``"address from, uint256[] memory ids"`` to ``{name: type}``."""
    params: Dict[str, str] = {}
    for param in params_str.split(","):
        parts = param.strip().split()
        if len(parts) >= 2:
            params[parts[-1]] = " ".join(parts[:-1])
    return params


# --------------------------------------------------------------------------
# Function discovery
# --------------------------------------------------------------------------

_FUNC_PATTERN = re.compile(
    r"function\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(([^)]*)\)"  # name and parameters
    r"([^{;]*)"                                            # modifiers / returns
    r"(?:\{)",                                             # body start
    re.DOTALL,
)


def find_all_functions(solidity_code: str) -> List[Function]:
    """Return every function *with a body* declared in ``solidity_code``.

    Interface declarations (terminated by ``;``) are not matched by the
    pattern; the original implementation had a dead branch for them which has
    been removed.
    """
    functions: List[Function] = []
    for match in _FUNC_PATTERN.finditer(solidity_code):
        open_brace = match.end() - 1
        depth, close = 1, open_brace + 1
        while depth > 0 and close < len(solidity_code):
            char = solidity_code[close]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
            close += 1

        if depth == 0:
            functions.append({
                "name": match.group(1),
                "params": match.group(2).strip(),
                "modifiers": match.group(3).strip(),
                "start": match.start(),
                "end": close,
                "body": solidity_code[match.start():close].strip(),
                "is_implementation": True,
            })
    return functions


def find_functions_by_signature(functions: List[Function], target_signature: str) -> List[Function]:
    """Select functions whose normalised signature equals ``target_signature``.

    Matching selected functions are annotated in place with a ``parameters``
    dictionary (``{name: type}``).
    """
    target = normalize_signature(target_signature)
    matches = []
    for func in functions:
        if normalize_signature(f"{func['name']}({func['params']})") == target:
            func["parameters"] = get_parameter_dict(func["params"])
            matches.append(func)
    return matches


# --------------------------------------------------------------------------
# Interprocedural call collection (ICFG approximation)
# --------------------------------------------------------------------------

_NON_CALL_KEYWORDS = {
    "require", "assert", "revert", "emit", "new", "return", "returns", "if",
    "try", "iscontract", "continue", "break", "for", "while", "do", "else",
    "catch", "delete", "length",
}
_NON_CALL_BUILTINS = {
    "gasleft", "msg", "block", "tx", "abi", "type", "this", "selfdestruct",
    "sha3", "keccak256", "ripemd160", "ecrecover", "addmod", "mulmod",
    "balance", "sub", "add",
}


def get_all_internal_calls(
    function_body: str,
    all_functions: List[Function],
    visited: Optional[Set[str]] = None,
) -> Optional[List[Function]]:
    """Collect, transitively, every in-contract function called from a body.

    Returns ``None`` (not ``[]``) when nothing is found. The published
    pipeline relied on that: callers iterate the result, so a target function
    without callees raises ``TypeError`` and the contract is recorded as an
    error. See :func:`ercaudit.batchaudit.analyzer.analyze_source` for how this
    is handled, and why it is preserved by default.

    Member calls such as ``lib.f(...)`` are tokenised as ``f`` followed by
    ``(`` and therefore resolve to any in-contract function named ``f``.
    """
    if visited is None:
        visited = set()

    internal_calls: List[Function] = []
    tokens = [t for t in re.split(r"(\W)", function_body) if t.strip()]

    i = 0
    while i < len(tokens):
        token = tokens[i]
        is_call = (
            token.isidentifier()
            and i + 1 < len(tokens)
            and tokens[i + 1] == "("
            and token not in visited
        )
        if not is_call:
            i += 1
            continue

        if token.lower() in _NON_CALL_KEYWORDS or token in _NON_CALL_BUILTINS:
            i += 1
            continue

        for func in all_functions:
            if func["name"] == token and func["body"] != function_body:
                visited.add(token)
                internal_calls.append(func)
                nested = get_all_internal_calls(func["body"], all_functions, visited)
                if nested:
                    internal_calls.extend(nested)

        # skip past the argument list of this call
        paren_count = 1
        i += 2
        while i < len(tokens) and paren_count > 0:
            if tokens[i] == "(":
                paren_count += 1
            elif tokens[i] == ")":
                paren_count -= 1
            i += 1

    return internal_calls if internal_calls else None


# --------------------------------------------------------------------------
# Predicate extraction (control-flow conditions)
# --------------------------------------------------------------------------

_REQUIRE_PATTERN = re.compile(
    r"require\s*\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)", re.DOTALL
)


def find_if_revert_control_flow(code: str) -> List[str]:
    """Return the conditions of ``if (...)`` statements whose block reverts."""
    conditions: List[str] = []
    pos, code_len = 0, len(code)

    while pos < code_len:
        if_pos = code.find("if", pos)
        if if_pos == -1:
            break

        # reject identifiers that merely contain "if"
        if if_pos > 0 and (code[if_pos - 1].isalnum() or code[if_pos - 1] == "_"):
            pos = if_pos + 2
            continue

        paren_pos = code.find("(", if_pos)
        if paren_pos == -1 or paren_pos > if_pos + 10:
            pos = if_pos + 2
            continue

        level, end_pos = 1, paren_pos + 1
        while end_pos < code_len and level > 0:
            if code[end_pos] == "(":
                level += 1
            elif code[end_pos] == ")":
                level -= 1
            end_pos += 1
        if level != 0:
            pos = if_pos + 2
            continue

        # the guarded block ends at the first '}' or, for a one-liner, at ';'
        block_start = end_pos
        block_end = code.find("}", block_start)
        semi_pos = code.find(";", block_start)
        if block_end == -1 or (semi_pos != -1 and semi_pos < block_end):
            block_end = semi_pos
        if block_end == -1:
            pos = if_pos + 2
            continue

        if code.find("revert", block_start, block_end) != -1:
            condition = code[paren_pos + 1:end_pos - 1].strip()
            conditions.append(re.sub(r"\s+", " ", condition))

        pos = end_pos

    return conditions


def collect_conditions(all_code: List[CodeBlock]) -> List[Tuple[str, str, str]]:
    """Gather ``(condition, source, kind)`` for every ``require`` / if-revert."""
    conditions: List[Tuple[str, str, str]] = []
    for code, source in all_code:
        for match in _REQUIRE_PATTERN.finditer(code):
            conditions.append((re.sub(r"\s+", " ", match.group(1).strip()), source, "require"))
        for cond in find_if_revert_control_flow(code):
            conditions.append((cond, source, "if-revert"))
    return conditions


# --------------------------------------------------------------------------
# Data-flow helpers and misc
# --------------------------------------------------------------------------

def extract_batch_parameters(target_func: Function) -> Dict[str, Optional[str]]:
    """Positional parameter names of a ``safeBatchTransferFrom`` declaration."""
    params = list(target_func.get("parameters", {}).items())

    def name(index: int) -> Optional[str]:
        return params[index][0] if len(params) > index else None

    return {
        "from_param": name(0),
        "to_param": name(1),
        "ids_param": name(2),
        "amounts_param": name(3),
        "data_param": name(4),
    }


def find_length_assignments(all_code: List[CodeBlock], ids_param: str) -> Dict[str, Dict[str, str]]:
    """Forward data-flow: aliases of ``ids.length`` (``uint256 n = ids.length;``)."""
    assignments: Dict[str, Dict[str, str]] = {}
    pattern = rf"uint256\s+(\w+)\s*=\s*{re.escape(ids_param)}\s*\.\s*length\s*;"
    for code, source in all_code:
        for match in re.finditer(pattern, code, re.DOTALL):
            assignments[match.group(1)] = {"source": source, "full_match": match.group(0)}
    return assignments


_ASSEMBLY_PATTERNS = [
    r"assembly\s*{",         # standard block
    r"assembly\s*\w*\s*{",   # with EVM dialect
    r"let\s+\w+\s*:=",       # assembly variable declaration
    r"mload\(|sload\(",      # common assembly ops
]


def contains_assembly(code) -> bool:
    """True if ``code`` (a string, or a dict of strings) contains inline assembly."""
    if isinstance(code, str):
        return any(re.search(p, code, re.IGNORECASE) for p in _ASSEMBLY_PATTERNS)
    if isinstance(code, dict):
        return any(contains_assembly(part) for part in code.values())
    return False


def strip_comments(code: str) -> str:
    """Remove ``//`` and ``/* */`` comments and collapse whitespace."""
    code = re.sub(r"//.*?\n|/\*.*?\*/", "", code, flags=re.DOTALL)
    return re.sub(r"\s+", " ", code)
