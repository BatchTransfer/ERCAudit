# Running the ERCAudit web service

A small web page and API: paste or upload a Solidity file and get the findings of every applicable rule set (ERC-1155 batch
transfers and EIP-712 / ERC-2612 signing domains). The service keeps no state and stores nothing.

## What it does
- `GET /` the page; `POST /api/audit` with `{"source": "<solidity>"}` returns `{findings, exit_status, applicable, elapsed_ms}`;
  `GET /healthz` health check.
- Safety limits: 300 KB per file, 25 s per audit in a separate process, 20 requests per minute per client address, the source is
  written to a private temporary directory and deleted straight away, the container is read-only, non-root, 1 GB memory.

## Deploy on a Linux server (Docker, about 5 minutes)
Requirements: Docker Engine with the compose plugin, ports 80 and 443 open, and a DNS A record pointing a host name at the server.

```bash
git clone https://github.com/BatchTransfer/ERCAudit.git && cd ERCAudit
cp .env.example .env          # set DOMAIN=your.host.name (Caddy then gets a free HTTPS certificate)
docker compose up -d --build
curl https://your.host.name/healthz        # {"status":"ok"}
```

Without a host name, set `DOMAIN=http://SERVER_IP` in `.env` to serve plain HTTP, or skip Caddy and start only the app:
`docker compose up -d --build web` with `WEB_BIND=0.0.0.0` (the app listens on port 8000).

## Keep it online
- `restart: unless-stopped` restarts the containers after a crash or reboot; run `sudo systemctl enable docker` once.
- Watchdog (cron, every 5 minutes): `*/5 * * * * curl -fsS https://your.host.name/healthz >/dev/null || docker compose -f /path/ERCAudit/docker-compose.yml restart`
- Update: `git pull && docker compose up -d --build`. Logs: `docker compose logs -f web` (they contain the request line and status,
  never the submitted source).

## Run without Docker
```bash
python3 -m venv .venv && . .venv/bin/activate
pip install . -r requirements.txt -r web/requirements.txt
gunicorn -w 1 --threads 6 -b 127.0.0.1:8000 --timeout 40 web.app:app
```

## Scope
The web service runs the static rule sets only. The on-chain verification of the paper needs RPC and Etherscan access and is
reproduced from the stored verdicts with `make onchain-table` (see the README).
