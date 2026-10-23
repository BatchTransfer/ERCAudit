"""ERCAudit web service: paste or upload a Solidity file and get the findings of every applicable rule set.

The service never stores the submitted source. Each request writes the source to a private temporary file, runs
``ercaudit audit --json`` in a separate process with a hard timeout, deletes the file and returns the findings.
Limits: 300 KB per file, 25 s per audit, 20 requests per minute per client address.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from collections import defaultdict, deque
from pathlib import Path

from flask import Flask, jsonify, render_template, request

from ercaudit.webcore import CONSTRAINT_TEXT, RULE_REQ, applicability

ROOT = Path(__file__).resolve().parents[1]
MAX_BYTES = 300 * 1024
TIMEOUT_S = 25
RATE_PER_MIN = int(os.environ.get("ERCAUDIT_RATE_PER_MIN", "20"))

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_BYTES + 4096

EXAMPLES = {
    "Batch transfer without address validation": "examples/batch/vuln_missing_address_validation.sol",
    "Batch transfer without array-length check": "examples/batch/vuln_missing_array_length_check.sol",
    "Batch transfer without caller check": "examples/batch/vuln_missing_access_control.sol",
    "Compliant batch transfer": "examples/batch/compliant.sol",
    "Replayable permit (R3, R6, R8)": "examples/domain/permit_replayable.sol",
    "Safe permit": "examples/domain/permit_safe.sol",
}
_hits = defaultdict(deque)
_lock = threading.Lock()


def client_ip():
    fwd = request.headers.get("X-Forwarded-For", "")
    return (fwd.split(",")[0].strip() if fwd else request.remote_addr) or "?"


def rate_limited():
    now = time.time()
    with _lock:
        q = _hits[client_ip()]
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= RATE_PER_MIN:
            return True
        q.append(now)
    return False


def audit_source(code):
    t0 = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="ercaudit_") as td:
        path = Path(td) / "Submitted.sol"
        path.write_text(code, encoding="utf-8", errors="ignore")
        try:
            r = subprocess.run([sys.executable, "-m", "ercaudit", "audit", str(path), "--json"], cwd=ROOT,
                               capture_output=True, text=True, timeout=TIMEOUT_S)
        except subprocess.TimeoutExpired:
            return {"error": f"The analysis exceeded {TIMEOUT_S} s and was stopped. Try a smaller or flattened file."}, 504
    try:
        data = json.loads(r.stdout)
        findings = data[0]["findings"] if data else []
    except (ValueError, IndexError, KeyError):
        return {"error": "The file could not be analysed (invalid or unsupported Solidity)."}, 422
    for f in findings:
        if f["module"] == "batch":
            parts = [c for c in f["constraint"].split("+") if c]
            f["explanation"] = "; ".join(CONSTRAINT_TEXT.get(c, c) for c in parts)
        else:
            f["explanation"] = RULE_REQ.get(f.get("rule"), f["risk"])
    app_ = applicability(code)
    return {"findings": findings, "exit_status": 1 if findings else 0, "applicable": app_,
            "elapsed_ms": round((time.perf_counter() - t0) * 1000)}, 200


@app.after_request
def headers(resp):
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Referrer-Policy"] = "no-referrer"
    resp.headers["Content-Security-Policy"] = "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'"
    return resp


@app.get("/")
def index():
    return render_template("index.html", examples=list(EXAMPLES))


@app.get("/healthz")
def health():
    return jsonify(status="ok")


@app.get("/api/example")
def example():
    name = request.args.get("name", "")
    if name not in EXAMPLES:
        return jsonify(error="unknown example"), 404
    return jsonify(source=(ROOT / EXAMPLES[name]).read_text())


@app.post("/api/audit")
def audit():
    if rate_limited():
        return jsonify(error="Too many requests. Please wait a minute."), 429
    code = ""
    if request.files.get("file"):
        code = request.files["file"].read(MAX_BYTES + 1).decode("utf-8", errors="ignore")
    elif request.is_json:
        code = (request.get_json(silent=True) or {}).get("source", "")
    else:
        code = request.form.get("source", "")
    if not code.strip():
        return jsonify(error="No Solidity source received."), 400
    if len(code.encode("utf-8", errors="ignore")) > MAX_BYTES:
        return jsonify(error=f"The file is larger than {MAX_BYTES // 1024} KB."), 413
    body, status = audit_source(code)
    return jsonify(body), status


@app.errorhandler(413)
def too_large(_):
    return jsonify(error=f"The file is larger than {MAX_BYTES // 1024} KB."), 413


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8000)
