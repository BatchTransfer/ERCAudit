#!/usr/bin/env python3
"""On-chain verification of DomAudit rules by recomputing the contract's EIP-712 domain separator.

Idea: a contract's DOMAIN_SEPARATOR() is keccak256(abi.encode(typehash, ...fields)). We rebuild it from the
contract's own name()/version()/address (public RPC, no keys) under candidate field layouts and see which one
reproduces the on-chain value. Which layout matches tells us which fields the domain really binds.

Rules implemented
  R2  (domain omits chainId):  confirmed if a layout WITHOUT chainId reproduces the separator;
                               refuted if a layout WITH chainId (or chainId carried in salt) reproduces it.
                               For confirmed contracts we also look for a cross-chain collision: the same address on
                               another chain returning the identical DOMAIN_SEPARATOR (a direct replay precondition).

  R3  (hardcoded chain id):    find the fixed chain id in the source (and, where the separator is readable, in the on-chain
                               separator) and compare it with the chain the contract lives on.
                               R3_differs_from_chain = the fixed id is not the deployed chain's id (the domain is bound to
                               another network; can be deliberate, e.g. a multichain wallet's own default chain id);
                               R3_matches_chain = fixed id equals the deployed chain (fork/replay risk only);
                               R3_refuted_dynamic = the source expression follows block.chainid.

  R4  (domain omits verifyingContract): confirmed if a layout WITHOUT verifyingContract reproduces the separator; refuted if one
                               WITH address(this) does. Confirmed contracts sharing an identical separator with another contract
                               on the same chain are reported (a direct cross-contract replay precondition).
  R5  (wrong verifier bound):  confirmed if the separator reproduces only with a verifier other than the contract itself
                               (hardcoded literal, stored/immutable address, ...); refuted if it binds address(this).

  R8  (hardcoded / zero salt): rebuild the separator with a salt field. R8_confirmed_zero / R8_confirmed_constant = the salt is
                               0x0 or a constant taken from the source (cannot tell logical domains apart); R8_refuted_dynamic =
                               the salt follows the chain id or the contract address. Contracts sharing one constant salt are
                               reported.

Usage:
    python3 onchain_domain_verify.py --rule R2|R3|R5|R6|R7|R9 --results <dir with out_*.json> --out r2_verify.jsonl [--limit N]
    python3 onchain_domain_verify.py --rule R2 --summarize --out r2_verify.jsonl
Resumable. Stdlib only (re-uses onchain_r31_verify.py for keccak/RPC helpers; keep both files together).
"""
import argparse
import json
import os
import sys
import threading
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import re  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import onchain_r31_verify as base  # noqa: E402
try:
    from ercaudit.domaudit.analyzer import extract_domain_construction_contexts, strip_comments  # noqa: E402
except ImportError:  # analyzer not available: fall back to whole-file literals
    extract_domain_construction_contexts = strip_comments = None

keccak256, decode_string = base.keccak256, base.decode_string
_TL = threading.local()


class DeadlineExceeded(Exception):
    pass


def set_deadline(seconds):
    _TL.end = time.monotonic() + seconds


def check_deadline():
    end = getattr(_TL, "end", None)
    if end is not None and time.monotonic() > end:
        raise DeadlineExceeded()


def _post_rpc(chain, payload):
    """POST a JSON-RPC payload (single or batch) to the first public RPC that answers; None if all fail."""
    body = json.dumps(payload).encode()
    for url in RPCS[chain][:4]:
        check_deadline()
        try:
            req = base.urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "User-Agent": "domaudit/1.0"})
            with base.urllib.request.urlopen(req, timeout=10) as r:
                return json.load(r)
        except base.urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(1.0)                       # rate limited: back off, then try the next node
        except Exception:
            pass
    return None


def eth_call(chain, to, data):
    out = _post_rpc(chain, {"jsonrpc": "2.0", "id": 1, "method": "eth_call", "params": [{"to": to, "data": data}, "latest"]})
    if out is None:
        return "RPC_FAIL"
    return out.get("result")
EXPECTED, KNOWN_IDS, RPCS = base.EXPECTED_CHAIN_ID, base.KNOWN_CHAIN_IDS, base.RPCS

NO_CHAINID_LAYOUTS = {
    "name,version,verifyingContract": ("EIP712Domain(string name,string version,address verifyingContract)", ("n", "v", "a")),
    "name,verifyingContract": ("EIP712Domain(string name,address verifyingContract)", ("n", "a")),
    "verifyingContract": ("EIP712Domain(address verifyingContract)", ("a",)),
    "name,version": ("EIP712Domain(string name,string version)", ("n", "v")),
    "name,version,verifyingContract,salt=0": ("EIP712Domain(string name,string version,address verifyingContract,bytes32 salt)", ("n", "v", "a", "z")),
}


def domain_inputs(chain, addr):
    """Read the on-chain separator plus the name/version candidates. Returns (error_verdict or None, data)."""
    ds_raw = eth_call(chain, addr, "0x3644e515")
    if ds_raw == "RPC_FAIL":
        return "rpc_fail", None
    if not ds_raw or len(ds_raw) != 66:
        return "ds_unavailable", None
    name_raw, ver_raw = eth_call(chain, addr, "0x06fdde03"), eth_call(chain, addr, "0x54fd4d50")
    names = [decode_string(name_raw)] if name_raw and name_raw != "RPC_FAIL" else []
    names = [n for n in names if n is not None] or [""]
    versions = ([decode_string(ver_raw)] if ver_raw and ver_raw != "RPC_FAIL" else [])
    versions = [v for v in versions if v is not None] + ["1", "2", "1.0", "v1"]
    return None, {"onchain": bytes.fromhex(ds_raw[2:]), "names": names, "versions": versions}


def try_layouts(addr, data, layouts, chain_ids):
    """First layout/chain-id combination that reproduces the on-chain separator, else None."""
    a32 = bytes(12) + bytes.fromhex(addr[2:])
    hn = {n: keccak256(n.encode()) for n in data["names"]}
    hv = {v: keccak256(v.encode()) for v in data["versions"]}
    cb = {c: c.to_bytes(32, "big") for c in chain_ids}
    for layout, (typestr, order) in layouts.items():
        th = keccak256(typestr.encode())
        uses_v, uses_c = "v" in order, "c" in order
        for name in (data["names"] if "n" in order else [None]):
            for ver in (data["versions"] if uses_v else [None]):
                for cid in (chain_ids if uses_c else [None]):
                    parts = {"n": hn.get(name), "v": hv.get(ver), "c": cb.get(cid), "a": a32, "z": bytes(32)}
                    if keccak256(th + b"".join(parts[k] for k in order)) == data["onchain"]:
                        return {"layout": layout, "chain_id": cid, "name": name, "version": ver}
    return None


def cross_chain_collision(chain, addr, onchain_hex):
    """Other chains where the same address returns the identical DOMAIN_SEPARATOR()."""
    hits = []
    for other in RPCS:
        if other == chain:
            continue
        r = eth_call(other, addr, "0x3644e515")
        if r and r != "RPC_FAIL" and r.lower() == onchain_hex.lower():
            hits.append(other)
    return hits


FIELD_KEY = {"name": "n", "version": "v", "chainid": "c", "verifyingcontract": "a", "salt": "z"}


def fetch_source(chain, addr):
    """All source text of a verified contract (handles Etherscan's single-file and JSON multi-file formats)."""
    if base.POOL is None:
        return None, None, None
    res = base.etherscan(EXPECTED[chain], module="contract", action="getsourcecode", address=addr).get("result")
    if not isinstance(res, list) or not res:
        return None, None, None
    raw, cname, abi_text = res[0].get("SourceCode", ""), res[0].get("ContractName"), res[0].get("ABI", "")
    if raw.startswith("{{"):
        raw = raw[1:-1]
    if raw.startswith("{"):
        try:
            j = json.loads(raw)
            files = j.get("sources", j)
            raw = "\n".join(v.get("content", "") for v in files.values() if isinstance(v, dict))
        except json.JSONDecodeError:
            pass
    return raw, cname, abi_text


def source_layouts(code):
    """Layouts built from the EIP712Domain(...) strings that appear in the source itself."""
    out = {}
    for body in set(re.findall(r"EIP712Domain\s*\(([^)]*)\)", code)):
        fields = [f.strip().split() for f in body.split(",") if f.strip()]
        keys = [FIELD_KEY.get(f[-1].lower()) if len(f) >= 2 else None for f in fields]
        if keys and all(keys):
            typestr = "EIP712Domain(" + ",".join(" ".join(f) for f in fields) + ")"
            out[typestr] = (typestr, tuple(keys))
    return out


def source_string_candidates(code, cname):
    text = strip_comments(code) if strip_comments else code
    ctx = extract_domain_construction_contexts(text) if extract_domain_construction_contexts else ""
    lits = re.findall(r'"([^"\n]{0,40})"', ctx) or re.findall(r'"([^"\n]{1,32})"', text)
    names = list(dict.fromkeys(([cname] if cname else []) + lits))[:150]
    versions = list(dict.fromkeys([l for l in lits if len(l) <= 10] + ["1", "2", "1.0", "v1"]))[:30]
    return names, versions



# ------------------------------------------------------------------ exact-encoding evaluator
import itertools  # noqa: E402

TOKEN_RE = re.compile(r"""\s*(?:(?P<str>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?P<num>0x[0-9a-fA-F]+|\d[\d_]*)|(?P<id>[A-Za-z_$][\w$.]*)|(?P<sym>[(),])|(?P<op>\S))""")


class Unsupported(Exception):
    pass


def parse_expr(text):
    toks = [(m.lastgroup, m.group(m.lastgroup)) for m in TOKEN_RE.finditer(text)]
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else (None, None)

    def take():
        pos[0] += 1
        return toks[pos[0] - 1]

    def expr():
        k, v = take()
        if k == "str":
            return ("str", bytes(v[1:-1], "utf-8").decode("unicode_escape").encode("latin-1", "replace"))
        if k == "num":
            return ("num", int(v.replace("_", ""), 0))
        if k == "id":
            if peek() == ("sym", "("):
                take(); args = []
                while peek() != ("sym", ")"):
                    args.append(expr())
                    if peek() == ("sym", ","):
                        take()
                    elif peek() != ("sym", ")"):
                        raise Unsupported("operator in arguments")
                take()
                return ("call", v, args)
            return ("id", v)
        raise Unsupported(f"token {k} {v}")

    node = expr()
    if pos[0] != len(toks):
        raise Unsupported("trailing tokens")
    return node


def balanced_call(text, start):
    """text[start:] begins at 'name(' ; return the full 'name(...)' substring."""
    i = text.index("(", start); depth = 0
    for j in range(i, len(text)):
        if text[j] == "(":
            depth += 1
        elif text[j] == ")":
            depth -= 1
            if depth == 0:
                return text[start:j + 1]
    return None


def runtime_pools(chain, addr):
    """Candidate words/addresses/ints embedded in runtime code (immutables) and the first storage slots (one batched RPC)."""
    batch = [{"jsonrpc": "2.0", "id": 0, "method": "eth_getCode", "params": [addr, "latest"]}] + \
            [{"jsonrpc": "2.0", "id": 1 + i, "method": "eth_getStorageAt", "params": [addr, hex(i), "latest"]} for i in range(20)]
    out = _post_rpc(chain, batch)
    res = {x.get("id"): x.get("result") for x in out} if isinstance(out, list) else {}
    words, addrs, ints = set(), set(), set()
    code = res.get(0)
    if code and len(code) > 2:
        b = bytes.fromhex(code[2:]); i = 0
        while i < len(b):
            op = b[i]
            if 0x60 <= op <= 0x7f:
                n = op - 0x5f; data = b[i + 1:i + 1 + n]
                if n == 32: words.add(data)
                elif n == 20: addrs.add(data)
                elif 1 <= n <= 8: ints.add(int.from_bytes(data, "big"))
                i += 1 + n
            else:
                i += 1
    for slot in range(20):
        v = res.get(1 + slot)
        if v and int(v, 16):
            w = bytes.fromhex(v[2:].rjust(64, "0")); words.add(w)
            if w[:12] == bytes(12): addrs.add(w[12:])
    return {"words": list(words)[:300], "addrs": list(addrs)[:100], "ints": sorted(ints)[:150]}


def eth_rpc(chain, method, params):
    out = _post_rpc(chain, {"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    return "RPC_FAIL" if out is None else out.get("result")


class Evaluator:
    def __init__(self, code, chain, addr, cid, strings, pools):
        self.cid, self.a32 = cid, bytes(12) + bytes.fromhex(addr[2:])
        self.strings, self.pools = strings, pools
        self.consts = {}
        for m in re.finditer(r"\b(\w+)\s*=\s*([^;=][^;]*);", strip_comments(code) if strip_comments else code):
            self.consts.setdefault(m.group(1), m.group(2).strip())
        self.budget = 60000

    def _w(self, n):  # int -> word
        return n.to_bytes(32, "big")

    def word(self, node, depth=0):
        if depth > 8: raise Unsupported("depth")
        k = node[0]
        if k == "num": return [self._w(node[1])]
        if k == "id":
            nm = node[1]
            if nm.lower() in ("block.chainid", "chainid"): return [self._w(self.cid)]
            if nm in self.consts: return self.word(parse_expr(self.consts[nm]), depth + 1)
            hint = re.search(r"router|addr|verif|contract|owner|factory|bridge|target|impl|token|vault", nm, re.I)
            pool = [bytes(12) + a for a in self.pools["addrs"]] + [self.a32]
            if not hint:
                pool = pool + self.pools["words"] + [self._w(i) for i in self.pools["ints"]]
            return pool
        if k == "call":
            f, args = node[1].lower(), node[2]
            if f == "keccak256" and len(args) == 1:
                return [keccak256(b) for b in self.byts(args[0], depth + 1)]
            if f == "address" and args and args[0] == ("id", "this"): return [self.a32]
            if f == "address" and args and args[0] == ("num", 0): return [bytes(32)]
            if f in ("uint256", "uint", "uint160", "uint32", "uint64", "uint8", "bytes32", "address") and len(args) == 1:
                return self.word(args[0], depth + 1)
            if f.endswith("chainid") or f.endswith("getchainid") or f.endswith("getchainId".lower()): return [self._w(self.cid)]
        raise Unsupported(f"word {node[:2]}")

    def byts(self, node, depth=0):
        if depth > 8: raise Unsupported("depth")
        k = node[0]
        if k == "str": return [node[1]]
        if k == "id":
            nm = node[1]
            if nm in self.consts: return self.byts(parse_expr(self.consts[nm]), depth + 1)
            return [s.encode() for s in self.strings]
        if k == "call":
            f, args = node[1].lower(), node[2]
            if f in ("bytes", "string") and len(args) == 1: return self.byts(args[0], depth + 1)
            if f == "abi.encodepacked" and len(args) == 1: return self.byts(args[0], depth + 1)
            if f == "abi.encode": return self.encode(args, depth + 1)
        raise Unsupported(f"bytes {node[:2]}")

    def encode(self, args, depth):
        opts = []
        for a in args:
            if a[0] == "str": opts.append([("dyn", a[1])])
            else: opts.append([("st", w) for w in self.word(a, depth)])
        total = 1
        for o in opts: total *= max(len(o), 1)
        if total > self.budget: raise Unsupported("too many combinations")
        self.budget -= total
        out = []
        for combo in itertools.product(*opts):
            head, tail = b"", b""
            base_off = 32 * len(combo)
            for kind, v in combo:
                if kind == "st": head += v
                else:
                    head += self._w(base_off + len(tail))
                    tail += self._w(len(v)) + v + bytes(-len(v) % 32)
            out.append(head + tail)
        return out


def exact_from_source(chain, addr, code, cname, onchain, names_pool):
    """Evaluate the source's own keccak256(abi.encode(<typehash>, ...)) domain expression and compare."""
    text = strip_comments(code) if strip_comments else code
    ctx = extract_domain_construction_contexts(text) if extract_domain_construction_contexts else text
    exprs = []
    for m in re.finditer(r"keccak256\s*\(\s*abi\.encode\s*\(", ctx):
        full = balanced_call(ctx, m.start())
        if full and re.search(r"TYPEHASH|EIP712Domain|DOMAIN", full, re.I) and full not in exprs:
            exprs.append(full)
    if not exprs:
        return None
    pools = runtime_pools(chain, addr)
    ev = Evaluator(code, chain, addr, EXPECTED[chain], names_pool, pools)
    for full in exprs[:3]:
        try:
            node = parse_expr(full)
            args = node[2][0][2]  # keccak256( abi.encode( args ) )
            opts = [ev.word(a) for a in args]
        except Unsupported:
            continue
        total = 1
        for o in opts: total *= max(len(o), 1)
        if total > ev.budget:
            continue
        for combo in itertools.product(*opts):
            if keccak256(b"".join(combo)) == onchain:
                typestrs = re.findall(r"EIP712Domain\s*\(([^)]*)\)", code)
                word0 = combo[0]
                decided = None
                for ts in typestrs:
                    if keccak256(("EIP712Domain(" + re.sub(r"\s+", " ", ts).strip() + ")").encode()) == word0 or \
                       keccak256(("EIP712Domain(" + ts + ")").encode()) == word0:
                        decided = ("chainId" in ts.replace(" ", "").replace("uint256chainId", "chainId") or "chainid" in ts.lower())
                        break
                return {"layout": "source expression", "decided_chain_in_type": decided}
    return None


GETTER_RE = re.compile(r"separator|seperator|domain_?hash|^domain$|domain_?sep", re.I)


def alt_getters(abi_text):
    try:
        abi = json.loads(abi_text)
    except Exception:
        return []
    return [x["name"] for x in abi if x.get("type") == "function" and not x.get("inputs") and x.get("outputs")
            and x["outputs"][0]["type"] == "bytes32" and GETTER_RE.search(x["name"]) and not re.search("type", x["name"], re.I)]


def erc5267(chain, addr):
    r = eth_call(chain, addr, "0x84b0196e")
    if r and r != "RPC_FAIL" and len(r) >= 2 + 64 * 7:
        fields = int(r[2:4], 16)
        return bool(fields & 0x04)  # chainId bit
    return None


def verify_r2(chain, addr):
    rec = {"chain": chain, "address": addr, "expected": EXPECTED[chain]}
    err, data = domain_inputs(chain, addr)
    code = cname = abi_text = None
    if err == "ds_unavailable":
        has_chain = erc5267(chain, addr)                      # route 1: ERC-5267 eip712Domain()
        if has_chain is not None:
            rec.update(verdict="R2_refuted" if has_chain else "R2_confirmed", via="ERC-5267 eip712Domain()")
            if not has_chain:
                rec["collision_chains"] = []
            return rec
        code, cname, abi_text = fetch_source(chain, addr)       # route 2: differently named separator getter
        for g in alt_getters(abi_text or ""):
            sel = "0x" + base.selector(g + "()")
            r = eth_call(chain, addr, sel)
            if r and r != "RPC_FAIL" and len(r) == 66:
                nm = eth_call(chain, addr, "0x06fdde03"); vr = eth_call(chain, addr, "0x54fd4d50")
                names = [decode_string(nm)] if nm and nm != "RPC_FAIL" else []
                vers = ([decode_string(vr)] if vr and vr != "RPC_FAIL" else []) + ["1", "2", "1.0", "v1"]
                data = {"onchain": bytes.fromhex(r[2:]), "names": [n for n in names if n is not None] or [""], "versions": vers}
                err = None; rec["getter"] = g
                break
    if err:
        rec["verdict"] = err
        return rec
    ids = [EXPECTED[chain]] + [c for c in KNOWN_IDS if c != EXPECTED[chain]]

    def classify(m, how):
        rec.update(**m, via=how)
        chain_in = m.get("decided_chain_in_type")
        if chain_in is None:
            chain_in = "chainId" in m["layout"] or m["layout"].endswith("salt=chainId") or m.get("chain_id") is not None
        if chain_in and "salt=0" not in m["layout"]:
            rec["verdict"] = "R2_refuted"
        else:
            rec["verdict"] = "R2_confirmed"
            rec["collision_chains"] = cross_chain_collision(chain, addr, "0x" + data["onchain"].hex())
        return rec

    exp_only = [EXPECTED[chain]]
    m = try_layouts(addr, data, NO_CHAINID_LAYOUTS, ids) or try_layouts(addr, data, base.DOMAIN_LAYOUTS, ids)
    if m:
        return classify(m, "rpc name/version")
    if code is None:
        code, cname, abi_text = fetch_source(chain, addr)
    if code:
        names, versions = source_string_candidates(code, cname)
        data2 = {"onchain": data["onchain"], "names": names or [""], "versions": versions}
        sl = source_layouts(code)
        no_chain = {k: v for k, v in sl.items() if "c" not in v[1]}
        with_chain = {k: v for k, v in sl.items() if "c" in v[1]}
        for layouts in (NO_CHAINID_LAYOUTS, no_chain, base.DOMAIN_LAYOUTS, with_chain):
            m = try_layouts(addr, data2, layouts, exp_only)
            if m:
                return classify(m, "source literals")
        m = exact_from_source(chain, addr, code, cname, data["onchain"], list(dict.fromkeys(data2["names"] + data2["versions"])))
        if m:
            if m["decided_chain_in_type"] is None:
                rec.update(verdict="matched_unclassified", via="source expression")
                return rec
            return classify(m, "source expression")
    rec["verdict"] = "inconclusive"
    return rec



def exact_matches(chain, addr, code, onchain, names_pool, cid):
    """True if the source's own domain expression, evaluated with chain id `cid`, reproduces the on-chain separator."""
    text = strip_comments(code) if strip_comments else code
    ctx = extract_domain_construction_contexts(text) if extract_domain_construction_contexts else text
    exprs = []
    for m in re.finditer(r"keccak256\s*\(\s*abi\.encode\s*\(", ctx):
        full = balanced_call(ctx, m.start())
        if full and re.search(r"TYPEHASH|EIP712Domain|DOMAIN", full, re.I) and full not in exprs:
            exprs.append(full)
    if not exprs:
        return None
    ev = Evaluator(code, chain, addr, cid, names_pool, runtime_pools(chain, addr))
    for full in exprs[:3]:
        try:
            opts = [ev.word(a) for a in parse_expr(full)[2][0][2]]
        except Unsupported:
            continue
        total = 1
        for o in opts: total *= max(len(o), 1)
        if total > ev.budget:
            continue
        for combo in itertools.product(*opts):
            if keccak256(b"".join(combo)) == onchain:
                return True
    return False


def onchain_separator(chain, addr, rec):
    """(verdict_or_None, data, code, cname, baked_from_5267). Same routes as R2."""
    err, data = domain_inputs(chain, addr)
    code = cname = abi_text = None
    if err == "ds_unavailable":
        r = eth_call(chain, addr, "0x84b0196e")
        if r and r != "RPC_FAIL" and len(r) >= 2 + 64 * 7:
            return None, None, None, None, (int(r[2:4], 16) & 0x04, int(r[2 + 64 * 3:2 + 64 * 4], 16))
        code, cname, abi_text = fetch_source(chain, addr)
        for g in alt_getters(abi_text or ""):
            r = eth_call(chain, addr, "0x" + base.selector(g + "()"))
            if r and r != "RPC_FAIL" and len(r) == 66:
                nm = eth_call(chain, addr, "0x06fdde03"); vr = eth_call(chain, addr, "0x54fd4d50")
                names = [decode_string(nm)] if nm and nm != "RPC_FAIL" else []
                vers = ([decode_string(vr)] if vr and vr != "RPC_FAIL" else []) + ["1", "2", "1.0", "v1"]
                rec["getter"] = g
                return None, {"onchain": bytes.fromhex(r[2:]), "names": [n for n in names if n is not None] or [""], "versions": vers}, code, cname, None
    return err, data, code, cname, None


def domain_exprs(ctx):
    out = []
    for m in re.finditer(r"keccak256\s*\(\s*abi\.encode\s*\(", ctx):
        full = balanced_call(ctx, m.start())
        if full and re.search(r"TYPEHASH|EIP712Domain|DOMAIN", full, re.I) and full not in out:
            out.append(full)
    return out


def source_hardcoded_ids(code):
    """Chain ids written as literals/constants in the domain construction (numeric abi.encode args, constants, assembly)."""
    text = strip_comments(code) if strip_comments else code
    ctx = extract_domain_construction_contexts(text) if extract_domain_construction_contexts else text
    ev = Evaluator(code, "ethereum", "0x" + "00" * 20, 1, [], {"words": [], "addrs": [], "ints": []})
    vals = set()
    for full in domain_exprs(ctx):
        try:
            for arg in parse_expr(full)[2][0][2]:
                node = arg
                if node[0] == "id" and node[1] in ev.consts:
                    try:
                        node = parse_expr(ev.consts[node[1]])
                    except Unsupported:
                        continue
                if node[0] == "num":
                    vals.add(node[1])
        except Unsupported:
            continue
    for m in re.finditer(r"\b\w*chain_?id\w*\s*(?::=|=)\s*(0x[0-9a-fA-F]+|\d[\d_]*)\s*[;\n]", ctx, re.I):
        vals.add(int(m.group(1).replace("_", ""), 0))
    return sorted(v for v in vals if v < 2 ** 64)  # larger values are hash constants, not chain ids


def verify_r3(chain, addr):
    exp = EXPECTED[chain]
    rec = {"chain": chain, "address": addr, "expected": exp}
    code, cname, _ = fetch_source(chain, addr)
    src_ids = source_hardcoded_ids(code) if code else []
    rec["source_ids"] = src_ids
    err, data, code2, cname2, erc5267 = onchain_separator(chain, addr, rec)
    onchain_baked = None
    if erc5267 is not None and erc5267[0]:
        onchain_baked = erc5267[1]
    elif data and not err:                                   # try to reproduce the separator with the candidate ids only
        cand = list(dict.fromkeys(src_ids + [exp]))
        layouts = {k: v for k, v in base.DOMAIN_LAYOUTS.items() if "c" in v[1]}
        names, versions = source_string_candidates(code, cname) if code else ([""], ["1"])
        d = {"onchain": data["onchain"], "names": list(dict.fromkeys(data["names"] + names))[:40], "versions": list(dict.fromkeys(data["versions"] + versions))[:10]}
        m = try_layouts(addr, d, {**layouts, **{k: v for k, v in (source_layouts(code).items() if code else []) if "c" in v[1]}}, cand)
        if m:
            onchain_baked = m["chain_id"]
        if code and onchain_baked == exp and not src_ids:
            pool = list(dict.fromkeys(d["names"] + d["versions"]))
            if exact_matches(chain, addr, code, data["onchain"], pool, 987654321) is False and exact_matches(chain, addr, code, data["onchain"], pool, exp):
                rec.update(verdict="R3_refuted_dynamic", baked=exp, evidence="on-chain")
                return rec
    if onchain_baked is not None:
        rec.update(baked=onchain_baked, evidence="on-chain")
    elif len(src_ids) == 1:
        rec.update(baked=src_ids[0], evidence="source literal vs deployed chain")
    elif len(src_ids) > 1:
        rec.update(baked=None, evidence="ambiguous literals")
        rec["verdict"] = "ambiguous"
        return rec
    else:
        rec["verdict"] = "unresolved" if not err else err
        return rec
    rec["verdict"] = "R3_differs_from_chain" if rec["baked"] != exp else "R3_matches_chain"
    if data and not err:
        rec["collision_chains"] = cross_chain_collision(chain, addr, "0x" + data["onchain"].hex())
    return rec



# ------------------------------------------------------------------ R4 / R5 (verifier binding)
FIELD_SRC = {"n": "string name", "v": "string version", "c": "uint256 chainId", "a": "address verifyingContract", "z": "bytes32 salt"}


def subset_layouts(with_verifier):
    """Every ordered subset of the standard EIP-712 fields that does (or does not) include verifyingContract."""
    out = {}
    keys = "nvcaz"
    for mask in range(1, 32):
        order = tuple(k for i, k in enumerate(keys) if mask >> i & 1)
        if ("a" in order) != with_verifier:
            continue
        typestr = "EIP712Domain(" + ",".join(FIELD_SRC[k] for k in order) + ")"
        out[typestr] = (typestr, order)
    return out


def erc5267_fields(chain, addr):
    r = eth_call(chain, addr, "0x84b0196e")
    if r and r != "RPC_FAIL" and len(r) >= 2 + 64 * 7:
        return {"fields": int(r[2:4], 16), "verifier": "0x" + r[2 + 64 * 4 + 24:2 + 64 * 5]}
    return None


def get_separator(chain, addr, rec):
    """(verdict_or_None, data, code, cname) via DOMAIN_SEPARATOR() or a differently named getter."""
    err, data = domain_inputs(chain, addr)
    code = cname = None
    if err == "ds_unavailable":
        code, cname, abi_text = fetch_source(chain, addr)
        for g in alt_getters(abi_text or ""):
            r = eth_call(chain, addr, "0x" + base.selector(g + "()"))
            if r and r != "RPC_FAIL" and len(r) == 66:
                nm = eth_call(chain, addr, "0x06fdde03"); vr = eth_call(chain, addr, "0x54fd4d50")
                names = [decode_string(nm)] if nm and nm != "RPC_FAIL" else []
                vers = ([decode_string(vr)] if vr and vr != "RPC_FAIL" else []) + ["1", "2", "1.0", "v1"]
                rec["getter"] = g
                return None, {"onchain": bytes.fromhex(r[2:]), "names": [n for n in names if n is not None] or [""], "versions": vers}, code, cname
    return err, data, code, cname


def try_layouts_v(addr, data, layouts, chain_ids, verifiers):
    """try_layouts with a list of candidate verifier words (32 bytes) for the 'a' field."""
    hn = {n: keccak256(n.encode()) for n in data["names"]}
    hv = {v: keccak256(v.encode()) for v in data["versions"]}
    cb = {c: c.to_bytes(32, "big") for c in chain_ids}
    for layout, (typestr, order) in layouts.items():
        th = keccak256(typestr.encode())
        for name in (data["names"] if "n" in order else [None]):
            for ver in (data["versions"] if "v" in order else [None]):
                for cid in (chain_ids if "c" in order else [None]):
                    for va in (verifiers if "a" in order else [None]):
                        parts = {"n": hn.get(name), "v": hv.get(ver), "c": cb.get(cid), "a": va, "z": bytes(32)}
                        if keccak256(th + b"".join(parts[k] for k in order)) == data["onchain"]:
                            return {"layout": layout, "chain_id": cid, "name": name, "version": ver,
                                    "verifier": ("0x" + va[12:].hex()) if va else None}
    return None


def candidates(chain, addr, data, code, cname, src_ids):
    exp = EXPECTED[chain]
    cids = list(dict.fromkeys([exp] + list(src_ids) + [1, 56, 137, 43114, 0]))
    sources = [("rpc", data)]
    if code:
        names, versions = source_string_candidates(code, cname)
        sources.append(("source", {"onchain": data["onchain"], "names": list(dict.fromkeys(data["names"] + names))[:40],
                                   "versions": list(dict.fromkeys(data["versions"] + versions))[:10]}))
    return cids, sources


def verify_verifier_rule(chain, addr, rule, deployment=False):
    # rule is the historical internal name: "R4" = missing verifier (paper R5), "R5" = foreign verifier
    # (paper R6 hardcoded; paper R7 with deployment=True: the verifier is supplied at deployment)
    P = "R7" if deployment else ("R5" if rule == "R4" else "R6")
    rec = {"chain": chain, "address": addr, "expected": EXPECTED[chain]}
    self32 = bytes(12) + bytes.fromhex(addr[2:])
    e5267 = erc5267_fields(chain, addr)
    if e5267 is not None:                                              # ERC-5267 states the verifier directly
        has_v = bool(e5267["fields"] & 0x08)
        if rule == "R4":
            rec.update(verdict=f"{P}_refuted" if has_v else f"{P}_confirmed", via="ERC-5267")
        elif not has_v:
            rec.update(verdict=f"{P}_not_applicable", via="ERC-5267 (no verifier field)")
        else:
            same = e5267["verifier"].lower() == "0x" + addr[2:].lower()
            rec.update(verdict=f"{P}_refuted" if same else f"{P}_confirmed", verifier=e5267["verifier"], via="ERC-5267")
        return rec
    err, data, code, cname = get_separator(chain, addr, rec)
    if err:
        rec["verdict"] = err
        return rec
    if code is None:
        code, cname, _ = fetch_source(chain, addr)
    src_ids = source_hardcoded_ids(code) if code else []
    cids, sources = candidates(chain, addr, data, code, cname, src_ids)
    rec["separator"] = "0x" + data["onchain"].hex()
    with_v, without_v = subset_layouts(True), subset_layouts(False)
    for how, d in sources:
        if rule == "R4":
            m = try_layouts_v(addr, d, without_v, cids, [None])
            if m:
                rec.update(verdict=f"{P}_confirmed", via=how, layout=m["layout"]); return rec
            m = try_layouts_v(addr, d, with_v, cids, [self32])
            if m:
                rec.update(verdict=f"{P}_refuted", via=how, layout=m["layout"], verifier=m["verifier"]); return rec
        else:
            m = try_layouts_v(addr, d, with_v, cids, [self32])
            if m:
                rec.update(verdict=f"{P}_refuted", via=how, layout=m["layout"], verifier="self"); return rec
    dep = deployment_words(chain, addr) if deployment else []
    if rule == "R5" and (code or dep or deployment):                   # other verifier candidates: source literals, deployment arguments, stored/immutable addresses
        lits = []
        if code:
            text = strip_comments(code) if strip_comments else code
            ctx = extract_domain_construction_contexts(text) if extract_domain_construction_contexts else text
            lits = [bytes(12) + bytes.fromhex(a[2:]) for a in dict.fromkeys(re.findall(r"\b0x[0-9a-fA-F]{40}\b", ctx))]
        pools = runtime_pools(chain, addr)
        cands = list(dict.fromkeys(dep + lits + [bytes(12) + a for a in pools["addrs"]] + ([bytes(32)] if deployment else [])))
        cands = [c for c in cands if c != self32][:160]
        for how, d in sources:
            m = try_layouts_v(addr, d, with_v, cids, cands)
            if m:
                vb = bytes.fromhex(m["verifier"][2:]).rjust(32, b"\0")
                if vb == bytes(32):
                    kind = "zero address"
                elif vb in dep:
                    kind = "constructor or initializer argument"
                elif vb in lits:
                    kind = "hardcoded literal in source"
                else:
                    kind = "stored or immutable address"
                rec.update(verdict=f"{P}_confirmed", via=how, layout=m["layout"], verifier=m["verifier"], verifier_kind=kind)
                return rec
    rec["verdict"] = "inconclusive"
    return rec


def deployment_words(chain, addr):
    """Address-like 32-byte words passed at deployment: constructor arguments and initializer calldata (Etherscan V2)."""
    if base.POOL is None:
        return []
    words = []
    try:
        res = base.etherscan(EXPECTED[chain], module="contract", action="getsourcecode", address=addr).get("result")
        info = res[0] if isinstance(res, list) and res else {}
        args = (info.get("ConstructorArguments") or "").lower()
        words += [args[i:i + 64] for i in range(0, len(args) - 63, 64)]
        abi_text = info.get("ABI") or ""
        abi = json.loads(abi_text) if abi_text.startswith("[") else []
        inits = [x for x in abi if x.get("type") == "function" and re.fullmatch(r"(initialize\w*|init\w*|__\w*init\w*)", x["name"], re.I)]
        sels = {base.selector(f'{f["name"]}({",".join(i["type"] for i in f["inputs"])})') for f in inits}
        if sels:
            tx = base.etherscan(EXPECTED[chain], module="account", action="txlist", address=addr, startblock=0,
                                endblock=99999999, page=1, offset=50, sort="asc").get("result")
            for t_ in tx if isinstance(tx, list) else []:
                data = (t_.get("input") or "")[2:].lower()
                if t_.get("isError") == "0" and data[:8] in sels:
                    words += [data[8 + i:8 + i + 64] for i in range(0, len(data) - 8 - 63, 64)]
    except Exception:
        pass
    out = [bytes.fromhex(w) for w in words if len(w) == 64 and w[:24] == "0" * 24]
    return list(dict.fromkeys(out))


def verify_r4(chain, addr):
    return verify_verifier_rule(chain, addr, "R4")


def verify_r5(chain, addr):
    return verify_verifier_rule(chain, addr, "R5")


def verify_r7(chain, addr):
    """Paper R7: the verifier is supplied at deployment. Confirmed if a verifier other than the contract reproduces the
    live separator (zero address, constructor or initializer argument, literal, stored address); refuted if the contract
    itself does."""
    return verify_verifier_rule(chain, addr, "R5", deployment=True)



# ------------------------------------------------------------------ R8 (salt)
def subset_layouts_salt():
    out = {}
    for mask in range(1, 32):
        order = tuple(k for i, k in enumerate("nvcaz") if mask >> i & 1)
        if "z" in order:
            typestr = "EIP712Domain(" + ",".join(FIELD_SRC[k] for k in order) + ")"
            out[typestr] = (typestr, order)
    return out


def try_layouts_salt(addr, data, layouts, chain_ids, salts, budget=6000):
    """salts: list of (label, 32-byte word). Stops after `budget` hash evaluations (returns None)."""
    a32 = bytes(12) + bytes.fromhex(addr[2:])
    hn = {n: keccak256(n.encode()) for n in data["names"]}
    hv = {v: keccak256(v.encode()) for v in data["versions"]}
    cb = {c: c.to_bytes(32, "big") for c in chain_ids}
    prio = lambda kv: (0 if kv[1][1] in (("n", "v", "a", "z"), ("n", "v", "c", "a", "z")) else 1, len(kv[1][1]))
    left = [budget]
    for layout, (typestr, order) in sorted(layouts.items(), key=prio):
        th = keccak256(typestr.encode())
        for name in (data["names"] if "n" in order else [None]):
            for ver in (data["versions"] if "v" in order else [None]):
                for cid in (chain_ids if "c" in order else [None]):
                    for label, salt in salts:
                        left[0] -= 1
                        if left[0] < 0:
                            return None
                        if left[0] % 500 == 0:
                            check_deadline()
                        parts = {"n": hn.get(name), "v": hv.get(ver), "c": cb.get(cid), "a": a32, "z": salt}
                        if keccak256(th + b"".join(parts[k] for k in order)) == data["onchain"]:
                            return {"layout": layout, "salt_kind": label, "salt": "0x" + salt.hex(), "chain_id": cid}
    return None


def salt_candidates(chain, addr, code, cids):
    a32 = bytes(12) + bytes.fromhex(addr[2:])
    cands = [("zero", bytes(32))]
    ev = Evaluator(code or "", chain, addr, EXPECTED[chain], [], {"words": [], "addrs": [], "ints": []})
    seen = {bytes(32)}
    for name, expr in ev.consts.items():                       # constants named *salt* in the source
        if re.search("salt", name, re.I):
            try:
                for w in ev.word(parse_expr(expr)):
                    if w not in seen:
                        seen.add(w); cands.append(("constant:" + name, w))
            except Unsupported:
                continue
    for h in dict.fromkeys(re.findall(r"0x([0-9a-fA-F]{64})\b", code or "")):   # any 32-byte hex literal in the source
        w = bytes.fromhex(h)
        if w not in seen:
            seen.add(w); cands.append(("constant:hex literal", w))
    cands += [("dynamic:chainId", c.to_bytes(32, "big")) for c in cids] + [("dynamic:address", a32)]
    pools = runtime_pools(chain, addr)
    cands += [("stored value", w) for w in pools["words"] if w not in seen][:40]
    return cands


def verify_r8(chain, addr):
    rec = {"chain": chain, "address": addr, "expected": EXPECTED[chain]}
    e = base.eth_call(chain, addr, "0x84b0196e")
    if e and e != "RPC_FAIL" and len(e) >= 2 + 64 * 7:           # ERC-5267: salt is stated directly
        fields = int(e[2:4], 16)
        if not fields & 0x10:
            rec.update(verdict="R9_refuted_no_salt_field", via="ERC-5267")
            return rec
        salt = bytes.fromhex(e[2 + 64 * 5:2 + 64 * 6])
        code, cname, _ = fetch_source(chain, addr)
        lits = {bytes.fromhex(h) for h in re.findall(r"0x([0-9a-fA-F]{64})\b", code or "")}
        kind = ("zero" if not any(salt) else "dynamic:chainId" if salt == EXPECTED[chain].to_bytes(32, "big")
                else "dynamic:address" if salt[12:] == bytes.fromhex(addr[2:]) else "constant:hex literal" if salt in lits else "stored value")
        rec.update(salt="0x" + salt.hex(), salt_kind=kind, via="ERC-5267")
        rec["verdict"] = "R9_refuted_dynamic" if kind.startswith("dynamic") else ("R9_confirmed_zero" if kind == "zero" else
                                                                              "R9_confirmed_constant" if kind.startswith("constant") else "R9_nonzero_unclassified")
        return rec
    err, data, code, cname = get_separator(chain, addr, rec)
    if err:
        rec["verdict"] = err
        return rec
    if code is None:
        code, cname, _ = fetch_source(chain, addr)
    src_ids = source_hardcoded_ids(code) if code else []
    cids = list(dict.fromkeys([EXPECTED[chain]] + list(src_ids)[:2]))
    rec["separator"] = "0x" + data["onchain"].hex()
    layouts = subset_layouts_salt()
    salts = salt_candidates(chain, addr, code, cids)
    sources = [data]
    if code:
        names, versions = source_string_candidates(code, cname)
        sources.append({"onchain": data["onchain"], "names": list(dict.fromkeys(data["names"] + names))[:12],
                        "versions": list(dict.fromkeys(data["versions"] + versions))[:5]})
    for d in sources:
        m = try_layouts_salt(addr, d, layouts, cids, salts)
        if m:
            kind = m["salt_kind"]
            rec.update(salt=m["salt"], salt_kind=kind, layout=m["layout"], via="recompute")
            rec["verdict"] = ("R9_refuted_dynamic" if kind.startswith("dynamic") else "R9_confirmed_zero" if kind == "zero" else
                              "R9_confirmed_constant" if kind.startswith("constant") else "R9_nonzero_unclassified")
            return rec
    rec["verdict"] = "inconclusive"
    return rec


# public rule names follow the paper (R1..R9); verify_r4/verify_r5/verify_r8 keep their historical function names
RULES = {"R2": verify_r2, "R3": verify_r3, "R5": verify_r4, "R6": verify_r5, "R7": verify_r7, "R9": verify_r8}


def summarize(path):
    rows = [json.loads(l) for l in open(path)]
    by = defaultdict(Counter)
    for r in rows:
        by[r["chain"]][r["verdict"]] += 1
        by["ALL"][r["verdict"]] += 1
        if r.get("collision_chains"):
            by[r["chain"]]["cross-chain collision"] += 1
            by["ALL"]["cross-chain collision"] += 1
    cols = sorted({k for c in by.values() for k in c}, key=lambda k: (not k.startswith(("R2_confirmed", "R3_differs", "R5_confirmed", "R6_confirmed", "R7_confirmed", "R9_confirmed")), not k.startswith(("R2_refuted", "R3_matches", "R5_refuted", "R6_refuted", "R7_refuted", "R9_refuted")), k))
    print("| Chain | Contracts | " + " | ".join(cols) + " |")
    print("|---|---:|" + "---:|" * len(cols))
    for ch in ["ethereum", "binance", "polygon", "avalanche", "ALL"]:
        if ch in by:
            n = sum(1 for r in rows if ch == "ALL" or r["chain"] == ch)
            print(f"| {ch} | {n} | " + " | ".join(str(by[ch][c]) for c in cols) + " |")
    groups = defaultdict(list)
    for r in rows:
        if r.get("separator") and r["verdict"].endswith("confirmed"):
            groups[(r["chain"], r["separator"])].append(r["address"])
    shared = [(k, v) for k, v in groups.items() if len(v) > 1]
    if shared:
        print(f"\nSHARED SEPARATORS: {len(shared)} groups, {sum(len(v) for _, v in shared)} contracts reuse an identical separator on the same chain")
        for (chain, sep), addrs in sorted(shared, key=lambda kv: -len(kv[1]))[:8]:
            print(f"  {chain}: {len(addrs)} contracts share {sep[:14]}...  e.g. {addrs[0][:12]}, {addrs[1][:12]}")
    salts = defaultdict(list)
    for r in rows:
        if r.get("salt") and r["verdict"].startswith("R9_confirmed"):
            salts[r["salt"]].append(r["address"])
    shared_salts = [(k, v) for k, v in salts.items() if len(v) > 1 and any(k.strip("0x"))]
    if shared_salts:
        print(f"\nSHARED CONSTANT SALTS: {len(shared_salts)} non-zero salts reused by {sum(len(v) for _, v in shared_salts)} contracts")
    for r in rows:
        if r.get("collision_chains"):
            print(f"  COLLISION {r['chain']} {r['address']} same separator on {r['collision_chains']}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rule", default="R2", choices=sorted(RULES))
    ap.add_argument("--results", default="results")
    ap.add_argument("--out", default="rule_verify.jsonl")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--threads", type=int, default=6)
    ap.add_argument("--deadline", type=int, default=90, help="max seconds per contract")
    ap.add_argument("--summarize", action="store_true")
    a = ap.parse_args()
    if a.summarize:
        return summarize(a.out)
    base.load_env()
    try:
        base.POOL = base.KeyPool()
        print(f"Etherscan keys available: {len(base.POOL.keys)} (used only to fetch verified source)")
    except SystemExit:
        print("No Etherscan keys: source-literal fallback disabled")
    targets = base.collect_targets(a.results, a.rule)
    print(f"{a.rule}: {len(targets)} unique flagged contracts", dict(Counter(c for c, _ in targets)))
    done = set()
    if os.path.exists(a.out):
        done = {(json.loads(l)["chain"], json.loads(l)["address"]) for l in open(a.out)}
    todo = [k for k in sorted(targets) if k not in done][: a.limit]
    print(f"{len(done)} already done, {len(todo)} to process")
    lock, n, t0 = threading.Lock(), [0], time.time()

    def work(k):
        set_deadline(a.deadline)
        try:
            rec = RULES[a.rule](*k)
        except DeadlineExceeded:
            rec = {"chain": k[0], "address": k[1], "verdict": "timeout"}
        except Exception as e:
            rec = {"chain": k[0], "address": k[1], "verdict": "error", "note": repr(e)[:120]}
        rec.update(targets[k])
        with lock:
            with open(a.out, "a") as fh:
                fh.write(json.dumps(rec) + "\n")
            n[0] += 1
            if n[0] % 25 == 0 or n[0] == len(todo):
                print(f"  [{n[0]}/{len(todo)}] {time.time() - t0:.0f}s", flush=True)

    with ThreadPoolExecutor(a.threads) as ex:
        list(ex.map(work, todo))
    summarize(a.out)


if __name__ == "__main__":
    main()
