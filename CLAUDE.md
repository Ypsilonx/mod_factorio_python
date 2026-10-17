# Pythonator

Mod do Factoria 2.0: programovatelný obvodový kontrolér, který se programuje v podmnožině Pythonu
(překlad do Lua, superloop `loop()` každý tick). Vydáno na mods.factorio.com. Velikost: L.

Doména: factorio-mod (+ blender-workflow pro grafiku) – obecná pravidla domény jsou ve skillu, tady se neopakují.

## Spuštění a ověření

- Ověřit (rychle, ~1 s): `bash tools/run-unit.sh` → `UNIT pass=… fail=0` (unit + konformní testy jazyka)
- Integrační: `bash tools/run-tests.sh vanilla|space-age` → `PYNTR-TEST DONE pass=… fail=0` (~minuty, dvoufázově přes uložení a načtení)
- Kompatibilita: `bash tools/run-tests.sh mods <mod>…`; výkon: `bash tools/run-perf.sh`; jazyk bez hry: `lua tools/bench-lang.lua`
- Přegenerovat očekávané výstupy v CPythonu (jen při změně případů): `bash tools/gen-conformance.sh`
- Ruční zkoušení ve hře: `bash tools/link-mod.sh`, pak checklist v `docs/development.md`
- Vydání: `docs/development.md` → Publikace (`tools/publish.sh`)

## Mapa projektu

- `Pythonator/scripts/lang/` – jazyk: lexer → parser → checker → codegen, runtime, VM s watchdogem, knihovna kombinátorů
- `Pythonator/scripts/` – budova: kontrolér, plánovač, I/O na drátech, životní cyklus, blueprinty, remote `pyntr`
- `Pythonator/scripts/gui/` – okno s editorem, panely, nápověda
- `tests/unit/`, `tests/conformance/` (programy `.py` + očekávané `.out`), `tests/pythonator-tests/` (integrační), `tests/perf/`
- `blender/` – model a sprity (skripty jsou zdroj pravdy, výstupy se ručně neupravují)
- Podrobné tabulky modulů, laditelných hodnot a měření: `docs/development.md`; návrh: `docs/specs/`

## Rozhodnutí a pravidla tohoto projektu

- Prefix `pyntr` / `pyntr-`, log tag testů `PYNTR`. Interní jméno `Pythonator` je po publikaci neměnné.
- Programy musí jít spustit i v CPythonu (konformní testy) – odchylky od Pythonu jen vědomě a zapsané
  v `docs/development.md` → „Známé odchylky od Pythonu“.
- Kód jazyka nesmí záviset na locale (porovnání po bajtech, jen ASCII třídy znaků) – hlídá `test_hardening.lua`.
- Na budově ani v grafice žádné logo Pythonu (ochranná známka PSF); popis na portálu má prohlášení o nezávislosti.
- Generovaný kód cílí na Lua 5.2 (hra), testy běží i ve hře přes vygenerovaná konformní data.

Stav práce: viz `STATUS.md`, milníky `ROADMAP.md`.
