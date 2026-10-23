# ERCAudit web service. Build from the repository root:  docker build -f web/Dockerfile -t ercaudit-web .
FROM python:3.9-slim
RUN useradd --create-home --uid 10001 app
WORKDIR /ercaudit
COPY requirements.txt pyproject.toml README.md ./
COPY web/requirements.txt ./web/requirements.txt
COPY ercaudit ./ercaudit
RUN pip install --no-cache-dir . -r requirements.txt -r web/requirements.txt
COPY web ./web
COPY examples ./examples
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/healthz', timeout=3)"
CMD ["gunicorn", "-w", "1", "--threads", "6", "-b", "0.0.0.0:8000", "--timeout", "40", "--access-logfile", "-", "--access-logformat", "%(h)s %(r)s %(s)s %(L)ss", "web.app:app"]
