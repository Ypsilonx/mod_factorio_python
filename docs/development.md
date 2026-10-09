# Pythonator – vývoj

## Prostředí
- Factorio 2.0 (hra běží na Lua 5.2), lokální testy v Lua 5.3 (`lua` v PATH), CPython přes `uv` jen pro `tools/gen-conformance.sh`.
- Skripty `tools/*.sh` spouštět v Git Bash.
- Editor (sumneko): `.luarc.json` nastavuje runtime Lua 5.2 – jinak hlásí falešně `Undefined global bit32`.

## Struktura jazyka (`Pythonator/scripts/lang/`)
| Modul | Úloha |
|---|---|
| `errors.lua` | chyby jazyka `{line, col, key, args}` |
| `signals.lua` | klíče signálů, resolver nad prototypy |
| `lexer.lua` → `parser.lua` → `checker.lua` → `codegen.lua` | překlad zdroje na Lua |
| `compiler.lua` | `compile(source, resolver)` |
| `runtime.lua`, `builtins.lua`, `signal_io.lua` | Python sémantika za běhu |
| `vm.lua` | spuštění s watchdogem, pojistka paměti |

## Testy
- `bash tools/run-unit.sh` – jednotkové + konformní testy.
- `bash tools/gen-conformance.sh` – přegenerování `.out` v CPythonu (jen při změně případů).
- `bash tools/run-tests.sh vanilla|space-age` – integrační testy v headless Factoriu (testovací mod `tests/pythonator-tests/`, běh v `.test-run/`).
- `bash tools/run-tests.sh mods <mod>…` – kompatibilita s cizími mody ze `%APPDATA%/Factorio/mods`.
- `bash tools/link-mod.sh` – propojí `Pythonator/` do složky modů hry (junction) pro ruční zkoušení.

## Kde ladit hodnoty
| Hodnota | Kde | Výchozí |
|---|---|---|
| Limit watchdogu (průchod cyklem a volání funkce = 1; vestavěné funkce a operace s kontejnery/řetězci platí počtem prvků či bajtů výsledku, PŘED alokací) | předává hostitel do `vm.run(inst, what, limit)` – map setting `pyntr-watchdog-limit` (`Pythonator/settings.lua`, 100–200 000, strop `LIMIT_MAX`) | 10 000 |
| Limit paměti (prvky list/tuple/dict v globálech; řetězec = 1 + délka // 100) | `vm.check_memory(G, limit)` – map setting `pyntr-memory-limit` (`Pythonator/settings.lua`, 100–200 000) | 10 000 |

## Známé odchylky od Pythonu
- `int` a `float` se nerozlišují: `6 / 2` vypíše `3`, ne `3.0`; čísla nad 2^53 ztrácí přesnost.
- Bitové operace jsou 32bitové se znaménkem (jako obvodová síť).
- `dict.keys()/values()/items()` vrací list, ne pohled.
- Klíčem slovníku může být jen `str`, číslo nebo `bool`.
- `def` na nejvyšší úrovni jsou dostupné i před svou definicí (hoisting).
- Přiřazení do globálu ve funkci bez `global` je chyba překladu (Python by vytvořil lokální proměnnou).

## Determinismus (multiplayer)
- Kód jazyka nesmí záviset na locale: řetězce se porovnávají a řadí po bajtech (`R.strcmp`), lexer používá jen ASCII třídy znaků (`[A-Za-z0-9_]`, ne `%a/%w`), `upper/lower` mění jen ASCII a čísla se formátují s tečkou i při locale s desetinnou čárkou. Hlídají to testy v `tests/unit/test_hardening.lua` s českým locale.

## Ověřená rizika (spike, plán 2 / Task 1, Factorio 2.0.77)
| Riziko | Výsledek | Důsledek |
|---|---|---|
| Budova 2×2 z `arithmetic-combinator` | ✓ rotace, dráty, vstup/výstup fungují (stejně to dělá fCPU: collision ±0,65, selection ±1) | prototyp podle specu |
| Editor: `text-box` | ✓ psaní, výběr, Ctrl+C/V/A, Home/End, rich text ikony i jejich kopírování | |
| Tab v `text-box` | ✗ nedělá nic; skript ho nedoplní (API nezná pozici kurzoru) | odsazení mezerami, uvést v nápovědě; vložený text s tabulátory funguje |
| Čísla řádků | ✓ když `text-box` nemá vlastní posuvník: box roste s textem (výška = řádky × 20 px + rezerva), posouvá vnější `scroll-pane` i se sloupcem čísel | font `pyntr-mono` (`from = "default-mono"`, 14), řádek 20 px, horní odsazení čísel 4 px |
| Posun za kurzorem | ✓ při psaní: rozdíl starého a nového textu → řádek změny → `scroll_to_element` na jeho popisek; šipky a myš událost nevyvolají (známé omezení) | |
| Vkládání ikon | nativní `icon_selector` (vkládá na skutečný kurzor); poloha jen v pravém dolním rohu boxu, styl ji neumí změnit; vlastní výběr signálu nezná kurzor → zamítnuto | rozhodnutí uživatele: nechat nativní |
| Montovna „Nastavit recept“ | ✓ stačí signál **předmětu** (`out["iron-gear-wheel"] = 1`), prefix `recipe:` není potřeba | do příkladů v nápovědě |
