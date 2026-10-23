"""Etherscan V2 client used by the transaction validator (paper Fig. 5).

Two operations are needed:

1. *collect* -- page through ``txlist`` for a contract and keep calls whose
   ``methodId`` is one of the requested selectors (``fetch_transactions``);
2. *receiver check* -- decide whether a recipient is a contract and whether its
   ABI exposes ``onERC1155BatchReceived`` (``augment_with_receiver_checks``).

Both are derived from ``get_transactions_and_events`` / ``augment_with_contract_checks``
in ``erc1155_safeBatch_TXNanalysis.py``. Differences from the research script, all
documented in ``docs/AUDIT_REPORT.md``:

* the deprecated V1 endpoint (``/api``) is replaced by V2 (``/v2/api?chainid=``);
* the research script hard-coded ``start_block=19_000_000`` (Jan 2024) and the
  ``approve``/``transferFrom`` selectors for its ERC-20 experiments; both are now
  parameters (defaults: block 0, the two ERC-1155 selectors);
* ``to_address_zero`` was set on the *whole column* if any row hit the zero
  address; it is now set per row.

API keys are read from the environment / ``.env`` (``ETHERSCAN_API_KEY``) and are
never written to disk.
"""
from __future__ import annotations

import json
import os
import time
from typing import Dict, Iterable, List, Optional, Tuple

import pandas as pd
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from .decoding import SELECTORS

V2_URL = "https://api.etherscan.io/v2/api"
CHAIN_IDS = {"ethereum": 1, "bsc": 56, "binance": 56, "polygon": 137, "avalanche": 43114}


def load_api_key(env_var: str = "ETHERSCAN_API_KEY") -> str:
    """Read the API key from the environment (``.env`` is honoured if python-dotenv is installed)."""
    try:
        from dotenv import load_dotenv
        load_dotenv()
    except ImportError:  # optional dependency
        pass
    key = os.getenv(env_var)
    if not key:
        raise ValueError(f"{env_var} not set. Copy .env.example to .env and add your key.")
    return key


def _session() -> requests.Session:
    session = requests.Session()
    retries = Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504])
    session.mount("https://", HTTPAdapter(max_retries=retries))
    return session


def fetch_transactions(
    address: str,
    api_key: str,
    method_ids: Iterable[str] = (SELECTORS["safeBatchTransferFrom"], SELECTORS["setApprovalForAll"]),
    *,
    chain: str = "ethereum",
    start_block: int = 0,
    end_block: int = 99_999_999,
    page_size: int = 10_000,
    pause: float = 0.2,
) -> List[Dict]:
    """All transactions to ``address`` whose ``methodId`` is in ``method_ids``."""
    wanted = {m.lower() for m in method_ids}
    session = _session()
    out: List[Dict] = []
    page = 1
    while True:
        params = {
            "chainid": CHAIN_IDS[chain], "module": "account", "action": "txlist", "address": address,
            "startblock": start_block, "endblock": end_block, "page": page, "offset": page_size,
            "sort": "asc", "apikey": api_key,
        }
        try:
            data = session.get(V2_URL, params=params, timeout=30).json()
        except requests.exceptions.Timeout:
            time.sleep(2)
            continue
        result = data.get("result")
        if data.get("status") == "0" or not isinstance(result, list):
            break  # "No transactions found" or an API error
        out.extend(tx for tx in result if tx and (tx.get("methodId") or "").lower() in wanted)
        if len(result) < page_size:
            break
        page += 1
        time.sleep(pause)
    return out


def _get(session: requests.Session, params: Dict, api_key: str) -> Dict:
    try:
        return session.get(V2_URL, params={**params, "apikey": api_key}, timeout=10).json()
    except Exception:  # network error: treated as "unknown" by callers
        return {}


def augment_with_receiver_checks(df: pd.DataFrame, api_key: str, chain: str = "ethereum") -> pd.DataFrame:
    """Add ``to_is_contract``, ``on_batch_received_impl`` and ``to_address_zero``.

    ``on_batch_received_impl`` only records that the recipient's *verified ABI*
    declares ``onERC1155BatchReceived``. It does not prove correct behaviour
    (paper Sec. VI-A, "Interface Compliance Violations"): that requires source
    inspection of the recipient.
    """
    df = df.copy()
    df["to_is_contract"] = False
    df["on_batch_received_impl"] = False
    df["to_address_zero"] = False

    session = _session()
    cache: Dict[str, Tuple[bool, bool]] = {}
    base = {"chainid": CHAIN_IDS[chain]}

    for idx, row in df.iterrows():
        to_addr = row.get("decoded_to") or row.get("to")
        if not isinstance(to_addr, str) or not to_addr.startswith("0x"):
            continue
        to_addr = to_addr.lower()

        if to_addr == "0x" + "0" * 40:
            df.at[idx, "to_address_zero"] = True
            continue

        if to_addr not in cache:
            code = _get(session, {**base, "module": "proxy", "action": "eth_getCode", "address": to_addr}, api_key)
            is_contract = bool(code.get("result")) and code.get("result") != "0x"
            has_receiver = False
            if is_contract:
                abi = _get(session, {**base, "module": "contract", "action": "getabi", "address": to_addr}, api_key)
                if abi.get("status") == "1":
                    try:
                        has_receiver = any(
                            e.get("type") == "function" and e.get("name") == "onERC1155BatchReceived"
                            for e in json.loads(abi["result"]))
                    except (ValueError, TypeError):
                        has_receiver = False
            cache[to_addr] = (is_contract, has_receiver)

        df.at[idx, "to_is_contract"], df.at[idx, "on_batch_received_impl"] = cache[to_addr]
    return df


def addresses_from_batchaudit_json(path: str, limit: Optional[int] = None) -> List[str]:
    """Contract addresses whose BatchAudit result has an implementation with unmet requirements.

    (``extract_addresses_from_json`` in the research script.)
    """
    import re

    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    out: List[str] = []
    for item in data:
        impls = item.get("all_implementations", [])
        if not any(not i.get("all_requirements_met", True) for i in impls):
            continue
        m = re.search(r"(0x[a-fA-F0-9]{40})", item.get("file", ""))
        if m:
            out.append(m.group(1))
            if limit and len(out) >= limit:
                break
    return out
