#!/usr/bin/env bash
# Spustí integrační testy v headless Factoriu: vytvoří mapu s modem a testovacím modem,
# odsimuluje ticky a vyhodnotí řádky PYNTR-TEST z logu.
# Použití: tools/run-tests.sh [vanilla|space-age]   (cestu k Factoriu lze změnit proměnnou FACTORIO_EXE)
#          tools/run-tests.sh mods <mod> [<mod>…]   kompatibilita s jinými mody (např. pymodpack, boblogistics):
#            mody i jejich povinné závislosti se vezmou v nejvyšší verzi ze složky MODS_SOURCE
#            (výchozí %APPDATA%/Factorio/mods) a spustí se jen obecné kontroly z cases/compat.lua.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO_EXE:-C:/STEAM/steamapps/common/Factorio/bin/x64/factorio.exe}"
VARIANT="${1:-vanilla}"
shift || true
RUN="$ROOT/.test-run/$VARIANT"
RUN_W="$(cygpath -m "$RUN")"
MODS_SOURCE="${MODS_SOURCE:-$APPDATA/Factorio/mods}"

rm -rf "$RUN"
mkdir -p "$RUN/mods" "$RUN/write-data"
cp -r "$ROOT/Pythonator" "$RUN/mods/Pythonator"
cp -r "$ROOT/tests/pythonator-tests" "$RUN/mods/pythonator-tests"

declare -A BUILTIN=([base]=true [elevated-rails]=false [quality]=false [space-age]=false)
EXTRA=()
[ "$VARIANT" = "space-age" ] && BUILTIN=([base]=true [elevated-rails]=true [quality]=true [space-age]=true)

# Zkopíruje nejvyšší verzi modu ze složky MODS_SOURCE a rekurzivně jeho povinné závislosti.
declare -A SEEN=()
add_mod() {
  local name="$1"
  [ -n "${SEEN[$name]:-}" ] && return 0
  SEEN[$name]=1
  if [ -n "${BUILTIN[$name]:-}" ]; then
    BUILTIN[$name]=true
    [ "$name" = "space-age" ] && BUILTIN[quality]=true && BUILTIN[elevated-rails]=true
    return 0
  fi
  [ "$name" = "core" ] && return 0
  local zip
  zip="$(ls "$MODS_SOURCE"/"${name}"_*.zip 2>/dev/null | grep -E "/${name}_[0-9.]+\.zip$" | sort -V | tail -1 || true)"
  if [ -z "$zip" ]; then echo "Mod $name není v $MODS_SOURCE"; exit 1; fi
  cp "$zip" "$RUN/mods/"
  EXTRA+=("$name")
  # Povinné závislosti: bez prefixu ?, (?), ! a ~ (ten je povinný, jen nemění pořadí načítání).
  local dep
  # info.json může být i na jednom řádku – proto spojit řádky a vzít jen obsah pole "dependencies".
  for dep in $(unzip -p "$zip" '*/info.json' | tr -d '\r\n' | grep -o '"dependencies"[^]]*' \
      | grep -o '"[^"]*"' | tr -d '"' | grep -v '^dependencies$' \
      | grep -vE '^(\?|\(\?\)|!)' | sed -E 's/^~ ?//; s/^ *//; s/[ <>=].*$//'); do
    add_mod "$dep"
  done
}

if [ "$VARIANT" = "mods" ]; then
  [ $# -eq 0 ] && { echo "Zadej aspoň jeden mod: tools/run-tests.sh mods <mod>…"; exit 1; }
  for mod in "$@"; do add_mod "$mod"; done
  echo "Mody: ${EXTRA[*]:-} | vestavěné: $(for k in "${!BUILTIN[@]}"; do [ "${BUILTIN[$k]}" = true ] && printf '%s ' "$k"; done)"
  # Herní testy počítají s vanilla prototypy (bedny, rozvodny), overhaul mody je mění – jen obecné kontroly.
  sed -i '/runner.register/{/cases.compat/!d}' "$RUN/mods/pythonator-tests/control.lua"
fi

{
  echo '{"mods":['
  for name in base elevated-rails quality space-age; do echo "  {\"name\":\"$name\",\"enabled\":${BUILTIN[$name]}},"; done
  for name in "${EXTRA[@]}"; do echo "  {\"name\":\"$name\",\"enabled\":true},"; done
  echo '  {"name":"Pythonator","enabled":true},'
  echo '  {"name":"pythonator-tests","enabled":true}'
  echo ']}'
} > "$RUN/mods/mod-list.json"
# Oddělená write-data složka, aby testy nepřepisovaly log a konfiguraci hráče.
cat > "$RUN/config.ini" <<INI
[path]
read-data=__PATH__executable__/../../data
write-data=$RUN_W/write-data
INI

ARGS=(--config "$RUN_W/config.ini" --mod-directory "$RUN_W/mods")
"$FACTORIO" "${ARGS[@]}" --create "$RUN_W/test.zip" > "$RUN/create.log" 2>&1 || true
if [ ! -f "$RUN/test.zip" ]; then
  echo "Vytvoření mapy selhalo:"
  grep -A12 -E "Error|error" "$RUN/create.log" | head -40
  exit 1
fi
"$FACTORIO" "${ARGS[@]}" --benchmark "$RUN_W/test.zip" --benchmark-ticks 1500 --disable-audio > "$RUN/bench.log" 2>&1 || true
grep -E "PYNTR-TEST|Error" "$RUN/bench.log" | sed 's/.*PYNTR-TEST/PYNTR-TEST/'
grep -q "PYNTR-TEST DONE pass=[0-9]* fail=0 " "$RUN/bench.log"
