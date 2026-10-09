#!/usr/bin/env bash
# Spustí jednotkové testy čisté logiky modu v lokální Lua.
set -euo pipefail
cd "$(dirname "$0")/.."
lua tests/unit/run.lua
