# ERCAudit: everything needed to try the tool, no build steps for the reviewer.
#   docker build -t ercaudit .
#   docker run --rm ercaudit                                 # audits the bundled examples
#   docker run --rm ercaudit ercaudit run --size 100         # unified run on the bundled sample
FROM python:3.9-slim
WORKDIR /ercaudit
COPY requirements.txt pyproject.toml README.md ./
COPY ercaudit ./ercaudit
RUN pip install --no-cache-dir -e . -r requirements.txt
COPY examples ./examples
COPY data ./data
COPY results ./results
COPY scripts ./scripts
COPY tests ./tests
COPY combine_run.py Makefile ./
CMD ["ercaudit", "audit", "examples"]
