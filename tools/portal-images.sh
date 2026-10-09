#!/usr/bin/env bash
# Nahraje obrázky z docs/screenshots/*.png na stránku modu na mods.factorio.com (Mod images API) a nastaví je
# v pořadí podle jména souboru (01-…, 02-…). Mod už na portálu musí být. Obrázky, které na stránce byly, nahradí.
# Použití: tools/portal-images.sh [--dry-run]
# API klíč s oprávněním „ModPortal: Edit Mods“: FACTORIO_API_KEY, jinak soubor FACTORIO_API_KEY_FILE (výchozí
# ~/.factorio-api-key/all_api_key.txt).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="https://mods.factorio.com/api"
MOD="Pythonator"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

KEY_FILE="${FACTORIO_API_KEY_FILE:-$HOME/.factorio-api-key/all_api_key.txt}"
[ -z "${FACTORIO_API_KEY:-}" ] && [ -d "$KEY_FILE" ] && {
  echo "$KEY_FILE je složka – zadej soubor: FACTORIO_API_KEY_FILE=\"$KEY_FILE/<soubor>\""; exit 1; }
KEY="${FACTORIO_API_KEY:-$(cat "$KEY_FILE" 2>/dev/null || true)}"
KEY="$(printf '%s' "$KEY" | tr -d '\r\n ')"
[ -z "$KEY" ] && { echo "Chybí API klíč"; exit 1; }

shopt -s nullglob
IMAGES=("$ROOT"/docs/screenshots/*.png)
[ "${#IMAGES[@]}" -gt 0 ] || { echo "Žádné obrázky v docs/screenshots/"; exit 1; }
for image in "${IMAGES[@]}"; do echo "Obrázek: $(basename "$image") ($(du -h "$image" | cut -f1))"; done
[ "$DRY" = 1 ] && { echo "Zkouška nanečisto – nic se neodeslalo."; exit 0; }

IDS=()
for image in "${IMAGES[@]}"; do
  INIT="$(curl -sS -H "Authorization: Bearer $KEY" -F "mod=$MOD" "$API/v2/mods/images/add")"
  URL="$(printf '%s' "$INIT" | grep -oE '"upload_url" *: *"[^"]+"' | sed -E 's/.*"(https[^"]+)"/\1/')"
  [ -z "$URL" ] && { echo "images/add selhalo: $INIT"; exit 1; }
  RESULT="$(curl -sS -F "image=@$(cygpath -m "$image")" "$URL")"
  ID="$(printf '%s' "$RESULT" | grep -oE '"id" *: *"[0-9a-f]+"' | sed -E 's/.*"([0-9a-f]+)"/\1/')"
  [ -z "$ID" ] && { echo "Nahrání $(basename "$image") selhalo: $RESULT"; exit 1; }
  echo "Nahráno $(basename "$image") → $ID"
  IDS+=("$ID")
done
LIST="$(IFS=,; echo "${IDS[*]}")"
RESULT="$(curl -sS -H "Authorization: Bearer $KEY" -F "mod=$MOD" -F "images=$LIST" "$API/v2/mods/images/edit")"
printf '%s' "$RESULT" | grep -q '"success" *: *true' || { echo "images/edit selhalo: $RESULT"; exit 1; }
echo "Obrázky na stránce modu nastaveny (${#IDS[@]}): https://mods.factorio.com/mod/$MOD"
