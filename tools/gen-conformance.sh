#!/usr/bin/env bash
# Přegeneruje očekávané výstupy konformních testů v CPythonu (spouštět jen při změně případů).
set -euo pipefail
cd "$(dirname "$0")/.."
for f in tests/conformance/cases/*.py; do
  uv run --no-project python -I tests/conformance/harness.py "$f" > "${f%.py}.out"
done
echo "OK: $(ls tests/conformance/cases/*.out | wc -l) výstupů"
