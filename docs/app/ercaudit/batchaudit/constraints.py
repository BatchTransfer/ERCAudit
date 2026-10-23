"""Constraint verification for ERC-1155 ``safeBatchTransferFrom`` (Algorithm 2).

Eight boolean requirements are derived from the ERC-1155 specification
(paper Table I). ``True`` means the implementation *satisfies* the requirement;
a contract is flagged when a requirement that its violation class depends on is
``False`` (see :mod:`ercaudit.batchaudit.taxonomy`).

Provenance: the checks are the original research code
(``verify_erc1155_requirements`` and ``check_on_received_implementation`` in
``erc1155_safeBatchTransferFrom.py``), restructured into one function per
constraint. Regular expressions, their order and the resulting flag updates are
unchanged. ``tests/test_regression_against_original.py`` enforces this.
"""
from __future__ import annotations

import re
from typing import Dict, List, Optional, Tuple

from ..solidity import (
    CodeBlock,
    Function,
    collect_conditions,
    extract_batch_parameters,
    find_length_assignments,
    strip_comments,
)

#: Requirement flags in the order used throughout the paper and the result files.
REQUIREMENTS: Tuple[str, ...] = (
    "sender_check",
    "approval_check",
    "zero_address_check",
    "length_matching_check",
    "event_emission_order",
    "transfer_batch_event_found",
    "to_isContract_check",
    "on_received_check",
)

#: Ways a contract can refer to the caller inside a predicate.
SENDER_REPRS = ("msg.sender", "_msgSender()", "sender")

Condition = Tuple[str, str, str]  # (predicate text, source label, "require" | "if-revert")


# --------------------------------------------------------------------------
# Access control:  sender_check / approval_check
# --------------------------------------------------------------------------

def _check_sender(conditions: List[Condition], from_param: str) -> bool:
    """``msg.sender == from`` (or its negation guarding a revert)."""
    for cond, _src, kind in conditions:
        for sender in SENDER_REPRS:
            s = re.escape(sender)
            if kind == "if-revert":
                patterns = [
                    rf"{s}\s*!=\s*{from_param}",
                    rf"{from_param}\s*!=\s*{s}",
                    rf"if\s*\(\s*{s}\s*!=\s*{from_param}\s*&&\s*!isApprovedForAll\(\s*{from_param}\s*,\s*{s}\s*\)\s*\)",
                    rf"if\s*\(\s*{from_param}\s*!=\s*{s}",
                    rf"if\s*\(\s*{s}\s*!=\s*{from_param}",
                ]
            else:  # require
                patterns = [rf"{s}\s*==\s*{from_param}", rf"{from_param}\s*==\s*{s}"]
            if any(re.search(p, cond) for p in patterns):
                return True
    return False


def _check_approval(conditions: List[Condition], from_param: str) -> bool:
    """``isApprovedForAll(from, msg.sender)`` or an equivalent operator map lookup."""
    for cond, _src, kind in conditions:
        for sender in SENDER_REPRS:
            s = re.escape(sender)
            if kind == "if-revert":
                patterns = [
                    (rf"!isApprovedForAll\(\s*{from_param}\s*,\s*{s}\s*\)", 0),
                    (rf"operatorApproval\[{from_param}\]\[{s}\]\s*==\s*false", re.IGNORECASE),
                    (rf"!isApprovedForAll\[{from_param}\]\[{s}\]", 0),
                    (rf"if\s*\(\s*{s}\s*!=\s*{from_param}\s*&&\s*!isApprovedForAll\(\s*{from_param}\s*,\s*{s}\s*\)\s*\)"
                     rf"\s*{{\s*revert\s*ERC1155MissingApprovalForAll\(\s*{s}\s*,\s*{from_param}\s*\)", 0),
                ]
                polarity = "false"
            else:  # require
                patterns = [
                    (rf"isApprovedForAll\(\s*{from_param}\s*,\s*{s}\s*\)", 0),
                    (rf"operatorApproval\[{from_param}\]\[{s}\]\s*==\s*true", re.IGNORECASE),
                    (rf"isApprovedForAll\[{from_param}\]\[{s}\]", 0),
                    (rf"require\(\s*isApprovedForAll\[{from_param}\]\[{s}\]\s*,\s*['\"]NOT_AUTHORIZED['\"]\s*\)", 0),
                ]
                polarity = "true"

            if any(re.search(p, cond, flags) for p, flags in patterns):
                return True
            # heuristic fallback: an "...Approval..." predicate mentioning both parties
            if (re.search(r"Approval", cond, re.IGNORECASE)
                    and re.search(rf"{from_param}", cond)
                    and re.search(rf"{s}", cond)
                    and re.search(polarity, cond, re.IGNORECASE)):
                return True
    return False


# --------------------------------------------------------------------------
# Input validation:  zero_address_check / length_matching_check
# --------------------------------------------------------------------------

def _check_zero_address(conditions: List[Condition], to_param: str) -> bool:
    """Recipient must be non-zero (``to != address(0)`` or ``to == address(0) -> revert``)."""
    for cond, _src, kind in conditions:
        if kind == "if-revert":
            patterns = [
                rf"{to_param}\s*==\s*address\(0\)",
                rf"address\(0\)\s*==\s*{to_param}",
                rf"{to_param}\s*==\s*address\(0x0\)",
                rf"address\(0x0\)\s*==\s*{to_param}",
                r"recipient\s*==\s*address\(0\)",
                r"recipient\s*==\s*address\(0x0\)",
            ]
        else:  # require
            patterns = [
                rf"{to_param}\s*!=\s*address\(0\)",
                rf"address\(0\)\s*!=\s*{to_param}",
                rf"{to_param}\s*!=\s*address\(0x0\)",
                rf"address\(0x0\)\s*!=\s*{to_param}",
                r"recipient\s*!=\s*address\(0\)",
                r"recipient\s*!=\s*address\(0x0\)",
                r"require\s*\(\s*recipient\s*!=\s*address\(0\)\s*,\s*['\"]ERC1155:\s*transfer\s*to\s*the\s*zero\s*address['\"]\s*\)",
            ]
        if any(re.search(p, cond) for p in patterns):
            return True
    return False


def _check_length_matching(
    conditions: List[Condition], ids_param: str, amounts_param: str, length_aliases: Dict[str, dict]
) -> bool:
    """``ids.length == amounts.length`` (directly, or through an alias variable)."""
    direct = [
        rf"{ids_param}\.length\s*[!=]=\s*{amounts_param}\.length",
        rf"{amounts_param}\.length\s*[!=]=\s*{ids_param}\.length",
        rf"{ids_param}\.length\s*[==]=\s*{amounts_param}\.length",
        rf"{amounts_param}\.length\s*[==]=\s*{ids_param}\.length",
    ]
    anonymous = [r"\.length\s*!=\s*\.length", r"\.length\s*==\s*\.length"]
    aliased: List[str] = []
    for var_name in length_aliases:
        aliased.extend([
            rf"{var_name}\s*[!=]=\s*{amounts_param}\.length",
            rf"{amounts_param}\.length\s*[!=]=\s*{var_name}",
        ])
    patterns = direct + aliased + anonymous
    return any(re.search(p, cond) for cond, _s, _k in conditions for p in patterns)


# --------------------------------------------------------------------------
# Receiver acceptance:  onERC1155BatchReceived
# --------------------------------------------------------------------------

_RETURN_GUARD = re.compile(
    r"""
    (?:require|if)\s*\(                          # start with require or if
    [^)]*?                                       # any characters (non-greedy)
    (?:[a-zA-Z_][\w.]*\s*\(\s*[^)]*\s*\)\s*\.)?  # optional contract prefix with params
    onERC1155BatchReceived\s*\(                  # the target function
    [^)]*                                        # parameters
    \s*\)                                        # closing paren of the call
    [^)]*                                        # any remaining condition
    \)                                           # closing paren of require/if
    """,
    re.VERBOSE | re.DOTALL,
)


def check_on_received_implementation(code: str, params: Dict[str, Optional[str]], is_contract: bool) -> bool:
    """Does ``code`` call ``onERC1155BatchReceived`` and validate its return value?

    Three increasingly permissive argument-matching attempts are made
    (exact names, types-in-context, argument count). The return value must then
    be validated in a ``require``/``if`` either inline, via a captured
    ``bytes4`` variable, or via a ``try ... returns (bytes4 x)`` clause.
    """
    from_param, ids_param = params["from_param"], params["ids_param"]
    amounts_param, data_param, to_param = params["amounts_param"], params["data_param"], params["to_param"]
    operator_param = "operator"

    operator_var = None
    operator_assignment = re.search(
        r"(address\s+(\w+)\s*=\s*(?:msg\.sender|_msgSender\(\))\s*;)", code)
    if operator_assignment:
        operator_var = operator_assignment.group(2)

    normalized = strip_comments(code)

    if not is_contract:
        # without a preceding guard elsewhere, require an in-function isContract() guard
        if not re.search(rf"if\s*\(\s*{to_param}\s*\.\s*isContract\s*\(\s*\)\s*\)", normalized):
            return False

    call_prefix = r"\.onERC1155BatchReceived(?:\s*\{[^}]*\})?\s*\(\s*"

    # Attempt 1: exact parameter names
    arg_patterns = [
        operator_var or operator_param or r"(msg\.sender|_msgSender\(\))",
        from_param or r"_\w+",
        ids_param or r"_\w+",
        amounts_param or r"_\w+",
        data_param or r"_\w+",
    ]
    param_matched = re.search(call_prefix + r"\s*,\s*".join(arg_patterns) + r"\s*\)", normalized) is not None

    # Attempt 2: any five arguments, with the expected types nearby.
    # NOTE (legacy quirk, kept so published results stay reproducible): in the
    # original code the adjacent string literals were concatenated *before* the
    # ``* 4``, so the whole call prefix is repeated four times and this attempt
    # effectively never matches. Attempt 3 below is the working fallback.
    if not param_matched:
        call_match = re.search((call_prefix + r"[^,)]+\s*,\s*") * 4 + r"[^)]+" + r"\s*\)", normalized)
        if call_match:
            context = normalized[max(0, call_match.start() - 100):call_match.end() + 100]
            param_matched = all(
                re.search(t, context) for t in (r"address", r"address", r"uint256\[\]", r"uint256\[\]", r"bytes")
            )

    # Attempt 3: exactly five arguments
    if not param_matched:
        param_matched = re.search(call_prefix + r"([^,)]+\s*,\s*){4}" + r"[^)]+" + r"\s*\)", normalized) is not None

    # Return-value validation --------------------------------------------------
    return_valid = bool(_RETURN_GUARD.search(normalized)) and param_matched

    if not return_valid:  # captured into a bytes4 variable, then compared
        captured = re.search(
            r"(bytes4\s+(\w+)\s*=\s*[^;]*?\.onERC1155BatchReceived(?:\s*\{[^}]*\})?\([^)]+\)\s*;)", normalized)
        if captured:
            name = captured.group(2)
            return_valid = re.search(
                r"(?:require|if)\s*\(\s*" + re.escape(name) + r"\s*(==|!=)\s*[^)]+\s*\)", normalized) is not None

    if not return_valid:  # try ... returns (bytes4 x)
        returns = re.search(
            r"try\s+[^.]*\.onERC1155BatchReceived(?:\s*\{[^}]*\})?\([^)]+\)\s+returns\s*\(\s*bytes4\s+(\w+)\s*\)",
            normalized)
        if returns:
            name = returns.group(1)
            return_valid = re.search(
                r"(?:require|if)\s*\(\s*[^)]*?" + re.escape(name) + r"[^)]*\)", normalized, re.DOTALL) is not None

    return return_valid


# --------------------------------------------------------------------------
# Orchestration
# --------------------------------------------------------------------------

def verify_batch_requirements(
    target_func: Function,
    internal_functions: List[Function],
    *,
    ternary_resets: bool = True,
) -> Dict[str, bool]:
    """Verify the eight ERC-1155 batch-transfer requirements.

    ``ternary_resets`` controls one block of the research code that is the *only*
    difference between the logic behind the stored Ethereum result file and the
    logic behind the stored BNB/Polygon/Avalanche files (see
    ``docs/AUDIT_REPORT.md``, finding F3). When a ``require(to.code.length == 0 ?
    to != address(0) : ...)`` guard is found, the current code sets
    ``to_isContract_check`` and ``on_received_check`` and *clears*
    ``zero_address_check`` and ``event_emission_order``. ``True`` (default) keeps
    that behaviour (reproduces BNB/Polygon/Avalanche results exactly);
    ``False`` skips the two clearing assignments (reproduces the Ethereum file
    to within 14 of 5,608 contracts).

    ``target_func`` is the ``safeBatchTransferFrom`` implementation and
    ``internal_functions`` its transitive callees; the requirement predicates are
    searched in the union of their bodies (interprocedural analysis).
    """
    requirements = dict.fromkeys(REQUIREMENTS, False)

    params = extract_batch_parameters(target_func)
    from_param, to_param = params["from_param"], params["to_param"]
    ids_param, amounts_param = params["ids_param"], params["amounts_param"]

    all_code: List[CodeBlock] = [(target_func["body"], "main function")]
    all_code += [(f["body"], f"internal function {f['name']}") for f in internal_functions]

    length_aliases = find_length_assignments(all_code, ids_param) if ids_param else {}
    conditions = collect_conditions(all_code)

    # -- forward pass over control-flow predicates ----------------------------
    if from_param:
        requirements["sender_check"] = _check_sender(conditions, from_param)
        requirements["approval_check"] = _check_approval(conditions, from_param)
    if to_param:
        requirements["zero_address_check"] = _check_zero_address(conditions, to_param)
    if ids_param and amounts_param:
        requirements["length_matching_check"] = _check_length_matching(
            conditions, ids_param, amounts_param, length_aliases)

    # -- pass over code blocks: events and receiver hook ----------------------
    event_pos: Optional[Tuple[str, int]] = None
    for code, source in all_code:
        if "emit TransferBatch(" in code and not requirements["transfer_batch_event_found"]:
            requirements["transfer_batch_event_found"] = True
            event_pos = (source, code.find("emit TransferBatch("))

        # the event must not precede the state-changing transfers
        if requirements["transfer_batch_event_found"] and source == event_pos[0]:
            post_event = code[event_pos[1]:]
            requirements["event_emission_order"] = not (
                "safeTransferFrom(" in post_event or "safeBatchTransferFrom(" in post_event)

        normalized = strip_comments(code)

        guards_if = [rf"if\s*\(\s*{to_param}\s*\.\s*isContract\s*\(\s*\)\s*\)"]
        guards_len = [
            rf"if\s*\(\s*{to_param}\s*\.\s*code\s*\.\s*length\s*[!=]=\s*0\s*\)",
            rf"if\s*\(\s*{to_param}\s*\.\s*code\s*\.\s*length\s*>\s*0\s*\)",
        ]
        guards_ternary = [
            rf"require\s*\(\s*{to_param}\s*\.\s*code\s*\.\s*length\s*==\s*0\s*\?\s*{to_param}\s*!=\s*address\s*\(\s*0\s*\)",
            rf"require\s*\(\s*{to_param}\s*\.\s*code\s*\.\s*length\s*==\s*0\s*\?\s*{to_param}\s*!=\s*0x0\b",
            rf"require\s*\(\s*{to_param}\s*\.\s*code\s*\.\s*length\s*==\s*0\s*\?\s*{to_param}\s*!=\s*address\s*\(\s*0\s*\)\s*:",
        ]

        if any(re.search(p, normalized) for p in guards_len):
            requirements["to_isContract_check"] = True
        if any(re.search(p, normalized) for p in guards_ternary):
            # ERC-1155 reference style ``code.length == 0 ? to != 0 : hook`` fuses the
            # recipient check and the hook; the individual flags are set explicitly.
            if ternary_resets:
                requirements["zero_address_check"] = False
                requirements["event_emission_order"] = False
            requirements["to_isContract_check"] = True
            requirements["on_received_check"] = True
        if any(re.search(p, normalized) for p in guards_if):
            requirements["to_isContract_check"] = True

        # the receiver hook is expected in a function reached after the event
        if event_pos and source != event_pos[0]:
            if check_on_received_implementation(code, params, requirements["to_isContract_check"]):
                requirements["on_received_check"] = True

    return requirements


#: Name-based shortcuts: an internal helper with one of these names is taken to
#: implement the corresponding requirement (e.g. OpenZeppelin's ``_doSafeBatchTransferAcceptanceCheck``).
_HELPER_NAME_HINTS = (
    ("onERC1155BatchReceived", ("on_received_check",)),
    ("isContract", ("to_isContract_check",)),
    ("isApprovedForAll", ("approval_check",)),
    ("msgSender", ("sender_check",)),
    ("isOperatable", ("sender_check", "approval_check")),
    ("isApprovedOrOwner", ("sender_check", "approval_check")),
    ("isSameLength", ("length_matching_check",)),
)


def apply_helper_name_hints(internal_calls: List[Function], requirements: Dict[str, bool]) -> Dict[str, bool]:
    """Credit requirements implied by well-known helper names (``furtherERC1155Checks``)."""
    for func in internal_calls:
        name = func.get("name", "")
        for hint, flags in _HELPER_NAME_HINTS:
            if hint in name:
                for flag in flags:
                    requirements[flag] = True
    return requirements
