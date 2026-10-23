#!/usr/bin/env python3
"""On-chain impact analysis for DomAudit-flagged contracts (R1-R8 / C1-C5), using Allium.

For every unique flagged contract (chain, address) it records
  * balances: latest fungible-token balances (Allium /wallet/balances, 100 addresses per call),
              with USD value where Allium returns a price;
  * activity: number of transactions seen, first/last timestamp and the token amounts moved
              (Allium /wallet/transactions, newest `--max-tx-pages` pages of 1000 per contract).
              Allium returns no USD there, so amounts are valued afterwards at CURRENT prices from
              /prices (native coins via their wrapped token). Tokens with < --min-liquidity USD of
              liquidity (default 10,000) are ignored to keep scam tokens out of the totals.
              Counts/volumes are LOWER BOUNDS for very busy contracts (`tx_truncated`).
No bulk transaction download is needed. Stdlib only; ALLIUM_API_KEY comes from .env and is never printed.

Run `--probe` FIRST on the server: it prints the field names Allium actually returns for one known
address, so you can confirm the USD fields before the full run (the parser tries several names).

Usage:
    python3 onchain_impact.py --probe
    python3 onchain_impact.py --results <dir with out_*.json> --out impact.jsonl [--limit N] [--stage balances|txs|both]
    python3 onchain_impact.py --summarize --results <dir> --out impact.jsonl
Resumable: addresses already present for a stage in --out are skipped.
"""
import argparse
import glob
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BASE = "https://api.allium.so/api/v1/developer"
CHAIN_SLUG = {"ethereum": "ethereum", "binance": "bsc", "polygon": "polygon", "avalanche": "avalanche"}
ADDR_RE = re.compile(r"0x[0-9a-fA-F]{40}")
CLASS_OF = {"R1": "C1", "R2": "C2", "R3": "C2", "R4": "C2", "R5": "C3", "R6": "C3", "R7": "C3", "R8": "C4", "R9": "C5"}
USD_KEYS = ("usd_amount", "amount_usd", "usd_value", "value_usd", "usd")


def load_env():
    for p in (Path(__file__).resolve().parent / ".env", Path.cwd() / ".env", Path.home() / ".env",
              Path.home() / "domaudit_run" / ".env"):
        if p.is_file():
            for line in p.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def post(path, body, params=None):
    key = os.environ.get("ALLIUM_API_KEY") or os.environ.get("ALLIUM_KEY") \
        or sys.exit("ALLIUM_API_KEY (or ALLIUM_KEY) missing from .env / environment.")
    url = BASE + path + (("?" + urllib.parse.urlencode(params)) if params else "")
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"X-API-KEY": key, "Content-Type": "application/json"})
    last = None
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}"
            if e.code in (429, 500, 502, 503, 504):
                time.sleep(2 ** attempt)
                continue
            return {"_error": f"HTTP {e.code}: {e.read()[:200].decode(errors='replace')}"}
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last = repr(e)
            time.sleep(2 ** attempt)
    return {"_error": last}


def collect_targets(results_dir):
    t = {}
    for p in sorted(glob.glob(os.path.join(results_dir, "out_20*_*.json"))):
        year, chain = re.search(r"out_(\d+)_(\w+)\.json", p).groups()
        for r in json.load(open(p))["results"]:
            if r.get("rules"):
                m = ADDR_RE.search(os.path.basename(r["file"]))
                if m:
                    e = t.setdefault((chain, m.group(0).lower()), {"rules": set(), "year": year})
                    e["rules"].update(r["rules"])
    return t


# ------------------------------------------------------------------ parsing helpers
HIGH_LIQ = 1e18  # Allium reports "LIQUIDITY_TOO_HIGH" for very liquid tokens (WBNB, USDT, ...)
MAX_LIQ = 5e9    # numeric liquidity above this is a fake/spoofed pool, not a real market


def find_liq(item):
    """Liquidity (USD) of a balance item's token: number, HIGH_LIQ for the TOO_HIGH sentinel, or None if unknown."""
    t = (((item.get("token") or {}).get("attributes") or {}).get("total_liquidity_usd")) if isinstance(item, dict) else None
    if isinstance(t, (int, float)):
        return float(t)
    if isinstance(t, dict):
        if isinstance(t.get("amount"), (int, float)):
            return float(t["amount"])
        if t.get("details") == "LIQUIDITY_TOO_HIGH":
            return HIGH_LIQ
    return None


def counted_usd(usd, liq, min_liq):
    """USD value to trust for one token holding: needs real liquidity, and cannot exceed it."""
    if liq == HIGH_LIQ:
        return usd
    if liq is not None:
        return min(usd, liq) if min_liq <= liq <= MAX_LIQ else 0.0
    return usd if usd <= 10_000 else 0.0  # liquidity unknown: only tiny holdings are trusted


def token_usd(item):
    """(usd_value, priced?) for one balance item; tolerant to field naming."""
    tok = item.get("token") or {}
    info = tok.get("info") or {}
    dec = tok.get("decimals")
    raw = item.get("raw_balance_str") or item.get("raw_balance")
    price = next((x for x in (tok.get("price"), tok.get("usd_price"), info.get("price"), item.get("price"),
                              item.get("usd_price")) if isinstance(x, (int, float))), None)
    direct = next((item[k] for k in ("usd_value", "usd_amount", "value_usd") if isinstance(item.get(k), (int, float))), None)
    if direct is not None:
        return float(direct), True
    try:
        amount = int(raw) / (10 ** int(dec))
    except (TypeError, ValueError):
        return 0.0, False
    return (amount * price, True) if price is not None else (0.0, False)


WRAPPED_NATIVE = {  # used to price native coins (ETH/BNB/POL/AVAX) through Allium's /prices
    "ethereum": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
    "bsc": "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c",
    "polygon": "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270",
    "avalanche": "0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7",
}
NFT_TYPES = ("721", "1155", "nft")


def asset_key(chain, asset):
    """('chain|address') price key for a transfer asset, or None for NFTs / unknown assets."""
    typ = (asset.get("type") or "").lower()
    addr = (asset.get("address") or "").lower()
    if asset.get("token_id") is not None or any(t in typ for t in NFT_TYPES):
        return None
    if typ == "native" or addr in ("", "0x0000000000000000000000000000000000000000",
                                   "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"):
        return f"{CHAIN_SLUG[chain]}|{WRAPPED_NATIVE[CHAIN_SLUG[chain]]}"
    return f"{CHAIN_SLUG[chain]}|{addr}"


def price_table(path):
    return json.load(open(path)) if os.path.exists(path) else {}


STABLE_ADDRS = {
    "ethereum": ["0xdac17f958d2ee523a2206206994597c13d831ec7", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "0x6b175474e89094c44da98b954eedeac495271d0f"],
    "bsc": ["0x55d398326f99059ff775485246999027b3197955", "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d",
            "0xe9e7cea3dedca5984780bafc599bd69add087d56", "0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3"],
    "polygon": ["0x2791bca1f2de4661ed88a30c99a7a9449aa84174", "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359",
                "0xc2132d05d31c914a87c6611c10748aeb04b58e8f", "0x8f3cf7ad23cd3cadbd9735aff958023239c6a063"],
    "avalanche": ["0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e", "0x9702230a8ea53601f5cd2dc00fdbc13d4df4a8c7",
                  "0xc7198437980c041c805a1edcba50c1ce5db95118", "0xa7d7079b0fead91f3e65f86e8915cb59c1a4c664",
                  "0xd586e7f844cea2f87f50152665bcbc2c279d8d70"],
}
SAFE_KEYS = {f"{c}|{a}" for c, addrs in STABLE_ADDRS.items() for a in addrs} | {f"{c}|{a}" for c, a in WRAPPED_NATIVE.items()}


def trusted_liquidity(rec):
    """chain|token -> best liquidity seen, harvested from every contract's balance records."""
    trusted = {}
    for r in rec.values():
        for t in (r.get("balances") or {}).get("top", []):
            if t.get("addr") and t.get("liq") is not None and (t["liq"] == HIGH_LIQ or t["liq"] <= MAX_LIQ):
                k = f"{t['chain']}|{t['addr']}"
                trusted[k] = max(trusted.get(k, 0), t["liq"])
    return trusted


def usd_volume(assets, prices, trusted, min_liq=1_000_000, max_ratio=5):
    """Volume in USD, lower bound. Counted in full for whitelisted stablecoins / wrapped-native coins and for tokens
    Allium marks LIQUIDITY_TOO_HIGH. Any other token counts only if its liquidity is >= min_liq AND the value moved
    is <= max_ratio x that liquidity; larger ratios indicate a spoofed price or pool and are ignored."""
    total, counted, skipped = 0.0, 0, 0
    for key, a in assets.items():
        price = (prices.get(key) or {}).get("price")
        if price is None:
            skipped += 1; continue
        value = a["amount"] * price
        liq = trusted.get(key, 0)
        if key in SAFE_KEYS or liq == HIGH_LIQ or (liq >= min_liq and value <= max_ratio * liq):
            total += value; counted += 1
        else:
            skipped += 1
    return total, counted, skipped


# ------------------------------------------------------------------ stages
def balances_stage(keys, out_fh, lock):
    by_chain = defaultdict(list)
    for chain, addr in keys:
        by_chain[chain].append(addr)
    for chain, addrs in by_chain.items():
        for i in range(0, len(addrs), 100):
            batch = addrs[i:i + 100]
            body = [{"chain": CHAIN_SLUG[chain], "address": a} for a in batch]
            agg = {a: {"usd": 0.0, "tokens": 0, "unpriced": 0} for a in batch}
            cursor, pages, err = None, 0, None
            while pages < 30:
                resp = post("/wallet/balances", body, {"with_liquidity_info": "true", **({"cursor": cursor} if cursor else {})})
                if "_error" in resp:
                    err = resp["_error"]; break
                for it in resp.get("items", []):
                    a = (it.get("address") or "").lower()
                    if a in agg:
                        usd, priced = token_usd(it)
                        agg[a]["usd"] += usd; agg[a]["tokens"] += 1; agg[a]["unpriced"] += (0 if priced else 1)
                        if usd > 0:
                            agg[a].setdefault("top", []).append({"sym": ((it.get("token") or {}).get("info") or {}).get("symbol"),
                                                                 "addr": ((it.get("token") or {}).get("address") or "").lower(), "chain": CHAIN_SLUG[chain],
                                                                 "usd": usd, "liq": find_liq(it)})
                cursor = resp.get("cursor"); pages += 1
                if not cursor:
                    break
            with lock:
                for a in batch:
                    agg[a]["top"] = sorted(agg[a].get("top", []), key=lambda t: -t["usd"])[:25]
                    out_fh.write(json.dumps({"stage": "balances", "chain": chain, "address": a, **agg[a],
                                             **({"error": err} if err else {})}) + "\n")
                out_fh.flush()
            print(f"  balances {chain} {min(i + 100, len(addrs))}/{len(addrs)}", flush=True)


def txs_one(chain, addr, max_pages):
    n = 0
    assets, first, last, cursor, pages, err = {}, None, None, None, 0, None
    while pages < max_pages:
        params = {"limit": 1000, **({"cursor": cursor} if cursor else {})}
        resp = post("/wallet/transactions", [{"chain": CHAIN_SLUG[chain], "address": addr}], params)
        if "_error" in resp:
            err = resp["_error"]; break
        for tx in resp.get("items", []):
            n += 1
            ts = tx.get("block_timestamp")
            first = ts if first is None or (ts and ts < first) else first
            last = ts if last is None or (ts and ts > last) else last
            for tr in tx.get("asset_transfers") or []:
                key = asset_key(chain, tr.get("asset") or {})
                amt = (tr.get("amount") or {}).get("amount")
                if key and isinstance(amt, (int, float)):
                    a = assets.setdefault(key, {"amount": 0.0, "n": 0, "symbol": (tr.get("asset") or {}).get("symbol")})
                    a["amount"] += abs(float(amt)); a["n"] += 1
        cursor = resp.get("cursor"); pages += 1
        if not cursor:
            break
    top = dict(sorted(assets.items(), key=lambda kv: -kv[1]["n"])[:60])
    return {"stage": "txs", "chain": chain, "address": addr, "tx_count": n, "assets": top,
            "first_ts": first, "last_ts": last, "tx_truncated": bool(cursor),
            **({"error": err} if err else {})}


def prices_stage(out_path, prices_path):
    """Fetch current USD price (+liquidity) for every distinct asset seen in the txs stage."""
    need = set()
    for line in open(out_path):
        r = json.loads(line)
        if r["stage"] == "txs" and "error" not in r:
            need.update(r.get("assets", {}))
    prices = price_table(prices_path)
    todo = sorted(k for k in need if k not in prices)
    print(f"prices: {len(need)} distinct assets, {len(todo)} to fetch")
    for i in range(0, len(todo), 200):
        batch = todo[i:i + 200]
        body = [{"token_address": k.split("|")[1], "chain": k.split("|")[0]} for k in batch]
        resp = post("/prices", body, {"with_liquidity_info": "true"})
        got = {}
        for it in resp.get("items", []) if "_error" not in resp else []:
            got[f"{it.get('chain')}|{(it.get('address') or '').lower()}"] = {
                "price": it.get("price"), "liq": it.get("total_liquidity_usd")}
        for k in batch:
            prices[k] = got.get(k, {"price": None, "liq": None})
        json.dump(prices, open(prices_path, "w"))
        print(f"  prices {min(i + 200, len(todo))}/{len(todo)}", flush=True)


def probe():
    """Print the *shape* of Allium responses (keys only plus a few scalar samples), never the API key."""
    addr = "0xdac17f958d2ee523a2206206994597c13d831ec7"  # USDT contract on Ethereum
    for name, path, params in (("balances", "/wallet/balances", None), ("transactions", "/wallet/transactions", {"limit": 3})):
        resp = post(path, [{"chain": "ethereum", "address": addr}], params)
        print(f"== {name}: top-level keys:", sorted(resp.keys()))
        items = resp.get("items") or []
        print(f"   items: {len(items)}; first item keys:", sorted(items[0].keys()) if items else None)
        if items:
            print("   first item (truncated):", json.dumps(items[0])[:900])
    for slug in ("bsc", "polygon", "avalanche"):
        r = post("/wallet/balances", [{"chain": slug, "address": addr}])
        print(f"== chain slug '{slug}':", "ERROR " + r["_error"] if "_error" in r else f"ok ({len(r.get('items', []))} items)")


# ------------------------------------------------------------------ summary
def summarize(results_dir, path, min_liq=10000, vol_min_liq=1_000_000):
    targets = collect_targets(results_dir)
    prices = price_table(path + ".prices.json")
    rec = defaultdict(dict)
    for line in open(path):
        r = json.loads(line)
        rec[(r["chain"], r["address"])][r["stage"]] = r
    trusted = trusted_liquidity(rec)
    groups = defaultdict(list)
    for k, info in targets.items():
        for rule in info["rules"]:
            groups[rule].append(k)
            groups[CLASS_OF[rule] + " (class)"].append(k)
        groups["ANY RULE"].append(k)

    def row(label, keys):
        keys = list(dict.fromkeys(keys))
        bal = [rec[k]["balances"] for k in keys if "balances" in rec[k] and "error" not in rec[k]["balances"]]
        tx = [rec[k]["txs"] for k in keys if "txs" in rec[k] and "error" not in rec[k]["txs"]]
        held = [sum(counted_usd(t["usd"], t["liq"], min_liq) for t in b.get("top", [])) for b in bal]
        funded = sum(1 for h in held if h > 0)
        tvl = sum(held)
        active = sum(1 for t in tx if t["tx_count"] > 0)
        vol = sum(usd_volume(t.get("assets", {}), prices, trusted, vol_min_liq)[0] for t in tx)
        txs = sum(t["tx_count"] for t in tx)
        return (f"| {label} | {len(keys):,} | {len(bal):,} | {funded:,} | ${tvl:,.0f} | {active:,} | {txs:,} | ${vol:,.0f} |")

    print("| Group | Contracts | With balance data | Holding >$0 | Held (USD) | With txs | Tx count (>=) | Volume USD (>=) |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")
    order = ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9"]
    for g in order + [f"{c} (class)" for c in ("C1", "C2", "C3", "C4", "C5")] + ["ANY RULE"]:
        if g in groups:
            print(row(g, groups[g]))
    top = sorted(((sum(counted_usd(t["usd"], t["liq"], min_liq) for t in b["balances"].get("top", [])), k) for k, b in rec.items() if "balances" in b), reverse=True)[:15]
    print("\nTop 15 by USD held:")
    for usd, (chain, addr) in top:
        print(f"  ${usd:>16,.0f}  {chain:9s} {addr}  rules={sorted(targets.get((chain, addr), {}).get('rules', []))}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default="results")
    ap.add_argument("--out", default="impact.jsonl")
    ap.add_argument("--stage", choices=["balances", "txs", "prices", "both"], default="both")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--threads", type=int, default=12)
    ap.add_argument("--max-tx-pages", type=int, default=1)
    ap.add_argument("--min-liquidity", type=float, default=10000)
    ap.add_argument("--min-volume-liquidity", type=float, default=1_000_000)
    ap.add_argument("--chains", default="", help="comma list, e.g. ethereum,polygon (default: all)")
    ap.add_argument("--redo-balances", action="store_true")
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--summarize", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.summarize:
        return summarize(a.results, a.out, a.min_liquidity, a.min_volume_liquidity)
    targets = collect_targets(a.results)
    from collections import Counter
    print(f"{len(targets)} unique flagged contracts", dict(Counter(c for c, _ in targets)))
    if a.dry_run:
        return
    load_env()
    if a.probe:
        return probe()
    done = defaultdict(set)
    if os.path.exists(a.out):
        for line in open(a.out):
            r = json.loads(line)
            if "error" not in r:
                done[r["stage"]].add((r["chain"], r["address"]))
    wanted = {c for c in a.chains.split(",") if c}
    keys = [k for k in sorted(targets) if not wanted or k[0] in wanted][: a.limit]
    lock = threading.Lock()
    with open(a.out, "a") as fh:
        if a.stage in ("balances", "both"):
            todo = [k for k in keys if a.redo_balances or k not in done["balances"]]
            print(f"balances: {len(todo)} to fetch")
            balances_stage(todo, fh, lock)
        if a.stage in ("txs", "both"):
            todo = [k for k in keys if k not in done["txs"]]
            print(f"txs: {len(todo)} to fetch (max {a.max_tx_pages} pages each)")
            n, t0 = [0], time.time()

            def work(k):
                rec = txs_one(*k, a.max_tx_pages)
                with lock:
                    fh.write(json.dumps(rec) + "\n"); fh.flush()
                    n[0] += 1
                    if n[0] % 200 == 0 or n[0] == len(todo):
                        print(f"  txs [{n[0]}/{len(todo)}] {time.time() - t0:.0f}s", flush=True)

            with ThreadPoolExecutor(a.threads) as ex:
                list(ex.map(work, todo))
    if a.stage in ("txs", "prices", "both"):
        prices_stage(a.out, a.out + ".prices.json")
    summarize(a.results, a.out, a.min_liquidity, a.min_volume_liquidity)


if __name__ == "__main__":
    main()
