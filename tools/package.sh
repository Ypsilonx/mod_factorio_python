#!/usr/bin/env bash
# Sestaví zip modu pro mod portál: dist/Pythonator_<verze>.zip s kořenovou složkou Pythonator_<verze>/.
# Používá PowerShell 7 (Compress-Archive v pwsh zapisuje cesty s lomítky, jak Factorio vyžaduje).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(grep -oE '"version"[^"]*"[^"]+"' "$ROOT/Pythonator/info.json" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
NAME="Pythonator_$VERSION"
STAGE="$ROOT/dist/stage"
rm -rf "$STAGE" "$ROOT/dist/$NAME.zip"
mkdir -p "$STAGE"
cp -r "$ROOT/Pythonator" "$STAGE/$NAME"
pwsh -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$STAGE/$NAME")' -DestinationPath '$(cygpath -w "$ROOT/dist/$NAME.zip")'"
rm -rf "$STAGE"
echo "$ROOT/dist/$NAME.zip"
