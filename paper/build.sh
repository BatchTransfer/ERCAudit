#!/bin/sh
# Compile with Tectonic (or replace by: pdflatex main.tex twice). Usage: ./build.sh [outdir]
OUT=${1:-.}
tectonic -X compile main.tex --outdir "$OUT"
