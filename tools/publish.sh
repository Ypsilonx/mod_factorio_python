#!/usr/bin/env bash
# Nahraje mod na mods.factorio.com přes API portálu (zip sestaví tools/package.sh).
# Použití: tools/publish.sh [--new | --details] [--dry-run]
#   (bez přepínače)  nová verze existujícího modu (Mod upload API, oprávnění „ModPortal: Upload Mods“)
#   --details        navíc aktualizuje údaje na portálu (titul, shrnutí z info.json, popis z docs/mod-portal.md,
#                    kategorie, tagy, licence; oprávnění „ModPortal: Edit Mods“)
#   --new            první vydání – mod na portálu ještě není (Mod publish API, „ModPortal: Publish Mods“),
#                    pak nastaví údaje jako --details
#   --dry-run        jen kontroly a sestavení zipu, na portál nic neodešle
# API klíč (https://factorio.com/profile → API keys): proměnná FACTORIO_API_KEY, nebo soubor s klíčem
# v FACTORIO_API_KEY_FILE (výchozí ~/.factorio-api-key/all_api_key.txt – klíče leží ve složce). Nikdy ne do repozitáře.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="https://mods.factorio.com/api"
MOD="Pythonator"
#: Údaje na portálu (hodnoty podle Mod details API).
CATEGORY="content"
LICENSE="default_mit"
TAGS=(circuit-network)
#: Odkaz na zdrojový kód (GitHub); prázdný = na portál se nepošle.
SOURCE_URL="${PYNTR_SOURCE_URL:-https://github.com/Ypsilonx/mod_factorio_python}"

MODE="version"
DRY=0
for arg in "$@"; do
  case "$arg" in
    --new) MODE="new" ;;
    --details) MODE="details" ;;
    --dry-run) DRY=1 ;;
    *) echo "Neznámý přepínač: $arg"; exit 1 ;;
  esac
done

KEY_FILE="${FACTORIO_API_KEY_FILE:-$HOME/.factorio-api-key/all_api_key.txt}"
if [ -z "${FACTORIO_API_KEY:-}" ] && [ -d "$KEY_FILE" ]; then
  echo "$KEY_FILE je složka, ne soubor s klíčem. Soubory v ní:"
  ls -1 "$KEY_FILE"
  echo "Zadej konkrétní soubor: FACTORIO_API_KEY_FILE=\"$KEY_FILE/<soubor>\" bash tools/publish.sh …"
  exit 1
fi
KEY="${FACTORIO_API_KEY:-$(cat "$KEY_FILE" 2>/dev/null || true)}"
KEY="$(printf '%s' "$KEY" | tr -d '\r\n ')"
[ -z "$KEY" ] && { echo "Chybí API klíč: FACTORIO_API_KEY, FACTORIO_API_KEY_FILE nebo ~/.factorio-api-key"; exit 1; }

INFO="$ROOT/$MOD/info.json"
VERSION=$(grep -oE '"version"[^"]*"[^"]+"' "$INFO" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
TITLE=$(grep -oE '"title" *: *"[^"]*"' "$INFO" | sed -E 's/^"title" *: *"(.*)"$/\1/')
SUMMARY=$(grep -oE '"description" *: *"[^"]*"' "$INFO" | sed -E 's/^"description" *: *"(.*)"$/\1/')
grep -q "^Version: $VERSION$" "$ROOT/$MOD/changelog.txt" || { echo "changelog.txt nemá sekci $VERSION"; exit 1; }
[ "${#SUMMARY}" -le 500 ] || { echo "Shrnutí (description v info.json) má ${#SUMMARY} znaků, portál dovolí 500."; exit 1; }

STATUS=$(curl -sS -o /dev/null -w "%{http_code}" "$API/mods/$MOD")
if [ "$MODE" = "new" ]; then
  [ "$STATUS" = "404" ] || { echo "Mod $MOD už na portálu je (HTTP $STATUS) – použij nahrání nové verze."; exit 1; }
else
  [ "$STATUS" = "200" ] || { echo "Mod $MOD na portálu není (HTTP $STATUS) – první vydání: --new."; exit 1; }
  if curl -sS "$API/mods/$MOD" | grep -q "\"version\":\"$VERSION\""; then
    echo "Verze $VERSION už na portálu je – zvyš version v info.json."
    exit 1
  fi
fi
[ -n "$(git -C "$ROOT" status --porcelain -- "$MOD" docs/mod-portal.md)" ] \
  && echo "Pozor: $MOD nebo popis mají necommitnuté změny, nahrávají se tak, jak jsou."

ZIP="$(bash "$ROOT/tools/package.sh" | tail -1)"
echo "Mod $MOD $VERSION ($TITLE), zip $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "Shrnutí (${#SUMMARY} znaků): $SUMMARY"
echo "Kategorie $CATEGORY, licence $LICENSE, tagy ${TAGS[*]}, zdroj $SOURCE_URL, popis docs/mod-portal.md"
if [ "$DRY" = 1 ]; then
  echo "Zkouška nanečisto (--dry-run) – na portál se nic neodeslalo."
  exit 0
fi

#: Pole se zdrojem kódu jen tehdy, když je SOURCE_URL vyplněná.
SOURCE_ARGS=()
#: init_publish nezná pole homepage (portál vrátí „Unknown field“) – to nastaví až edit_details.
PUBLISH_SOURCE_ARGS=()
if [ -n "$SOURCE_URL" ]; then SOURCE_ARGS=(-F "source_url=$SOURCE_URL" -F "homepage=$SOURCE_URL"); fi
if [ -n "$SOURCE_URL" ]; then PUBLISH_SOURCE_ARGS=(-F "source_url=$SOURCE_URL"); fi

#: Hodnota pole „success“ v odpovědi portálu, jinak ukončí skript s chybou.
check() {
  printf '%s' "$2" | grep -q '"success" *: *true' || { echo "$1 selhalo: $2"; exit 1; }
}

#: Údaje modu na portálu (titul, shrnutí, popis, kategorie, tagy, licence).
edit_details() {
  # Shrnutí přes soubor: curl.exe dostane argumenty v kódové stránce Windows a ne-ASCII znaky (–) rozbije.
  local summary_file
  summary_file="$(mktemp)"
  printf "%s" "$SUMMARY" > "$summary_file"
  local args=(-F "mod=$MOD" -F "title=$TITLE" -F "summary=<$(cygpath -m "$summary_file")" -F "category=$CATEGORY" -F "license=$LICENSE"
    "${SOURCE_ARGS[@]}" -F "description=<$(cygpath -m "$ROOT/docs/mod-portal.md")")
  for tag in "${TAGS[@]}"; do args+=(-F "tags=$tag"); done
  check "Úprava údajů" "$(curl -sS -H "Authorization: Bearer $KEY" "${args[@]}" "$API/v2/mods/edit_details")"
  rm -f "$summary_file"
  echo "Údaje a popis na portálu nastaveny."
}

if [ "$MODE" = "new" ]; then
  INIT="$(curl -sS -H "Authorization: Bearer $KEY" -F "mod=$MOD" "$API/v2/mods/init_publish")"
else
  INIT="$(curl -sS -H "Authorization: Bearer $KEY" -F "mod=$MOD" "$API/v2/mods/releases/init_upload")"
fi
URL="$(printf '%s' "$INIT" | grep -oE '"upload_url" *: *"[^"]+"' | sed -E 's/.*"(https[^"]+)"/\1/')"
[ -z "$URL" ] && { echo "Založení nahrávání selhalo: $INIT"; exit 1; }
if [ "$MODE" = "new" ]; then
  check "Zveřejnění modu" "$(curl -sS -F "file=@$(cygpath -m "$ZIP")" -F "category=$CATEGORY" -F "license=$LICENSE" \
    "${PUBLISH_SOURCE_ARGS[@]}" -F "description=<$(cygpath -m "$ROOT/docs/mod-portal.md")" "$URL")"
  echo "Mod zveřejněn: https://mods.factorio.com/mod/$MOD"
else
  check "Nahrání verze" "$(curl -sS -F "file=@$(cygpath -m "$ZIP")" "$URL")"
  echo "Verze $VERSION nahrána: https://mods.factorio.com/mod/$MOD"
fi
[ "$MODE" != "version" ] && edit_details
exit 0
