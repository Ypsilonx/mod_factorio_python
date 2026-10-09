#!/usr/bin/env bash
# Spustí integrační testy v headless Factoriu: vytvoří mapu s modem a testovacím modem,
# odsimuluje ticky a vyhodnotí řádky PYNTR-TEST z logu.
# Použití: tools/run-tests.sh [vanilla|space-age]   (cestu k Factoriu lze změnit proměnnou FACTORIO_EXE)
#          tools/run-tests.sh mods <mod> [<mod>…]   kompatibilita s jinými mody (např. pymodpack, boblogistics):
#            mody i jejich povinné závislosti se vezmou v nejvyšší verzi ze složky MODS_SOURCE
#            (výchozí %APPDATA%/Factorio/mods) a spustí se jen obecné kontroly z cases/compat.lua.
# Varianty vanilla/space-age běží dvoufázově: 1) headless server (jen 127.0.0.1) do uložení hry v ticku
# runner.SAVE_TICK, 2) --benchmark uložené pozice – testy tak přejdou přes skutečné uložení a načtení.
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
# Konformní programy jazyka jako data pro test ve hře (generovaný soubor jen v běhu, ne v repozitáři).
(cd "$ROOT" && lua tools/conformance-data.lua) > "$RUN/mods/pythonator-tests/conformance_data.lua"

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
BENCH_SAVE="$RUN_W/test.zip"
: > "$RUN/server.log"
if [ "$VARIANT" != "mods" ]; then
  # Fáze 1: server bez hráčů (auto_pause vypnuté) dojede do uložení, pak se ukončí.
  sed -e 's/"auto_pause": true/"auto_pause": false/' -e 's/"public": true/"public": false/' \
      -e 's/"lan": true/"lan": false/' -e 's/"require_user_verification": true/"require_user_verification": false/' \
      -e 's/"autosave_interval": [0-9]*/"autosave_interval": 0/' \
      "$(dirname "$FACTORIO")/../../data/server-settings.example.json" > "$RUN/server-settings.json"
  "$FACTORIO" "${ARGS[@]}" --start-server "$RUN_W/test.zip" --server-settings "$RUN_W/server-settings.json" \
    --bind 127.0.0.1:34297 > "$RUN/server.log" 2>&1 &
  SERVER=$!
  for _ in $(seq 1 240); do
    grep -q "Saving finished" "$RUN/server.log" && break
    kill -0 "$SERVER" 2>/dev/null || break
    sleep 0.5
  done
  kill "$SERVER" 2>/dev/null || true
  wait "$SERVER" 2>/dev/null || true
  if ! grep -q "Saving finished" "$RUN/server.log"; then
    echo "Fáze 1 (server) hru neuložila:"
    grep -E "PYNTR-TEST|Error" "$RUN/server.log" | head -20
    exit 1
  fi
  BENCH_SAVE="$RUN_W/write-data/saves/_autosave-pyntr-saved.zip"
fi
"$FACTORIO" "${ARGS[@]}" --benchmark "$BENCH_SAVE" --benchmark-ticks 1500 --disable-audio > "$RUN/bench.log" 2>&1 || true
cat "$RUN/server.log" "$RUN/bench.log" | grep -E "PYNTR-TEST|Error" | sed 's/.*PYNTR-TEST/PYNTR-TEST/'
grep -q "PYNTR-TEST DONE pass=[0-9]* fail=0 " "$RUN/bench.log"
