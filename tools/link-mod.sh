#!/usr/bin/env bash
# Vytvoří junction %APPDATA%/Factorio/mods/Pythonator → složka modu v repozitáři,
# aby hra načítala rozpracovanou verzi přímo z repozitáře (pro ruční hraní a FMTK debugger).
# Junction vytváří PowerShell – `cmd //c mklink /J` v Git Bash kazí přepínače převodem cest.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINK="$APPDATA/Factorio/mods/Pythonator"
if [ -e "$LINK" ]; then
  echo "Už existuje: $LINK"
  exit 0
fi
powershell.exe -NoProfile -Command \
  "New-Item -ItemType Junction -Path '$(cygpath -w "$LINK")' -Target '$(cygpath -w "$ROOT/Pythonator")' | Out-Null"
echo "Propojeno: $LINK → $ROOT/Pythonator"
