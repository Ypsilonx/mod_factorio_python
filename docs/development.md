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

## Kde ladit hodnoty
| Hodnota | Kde | Výchozí |
|---|---|---|
| Limit watchdogu (průchod cyklem a volání funkce = 1; vestavěné funkce a operace s kontejnery/řetězci platí počtem prvků či bajtů výsledku, PŘED alokací) | předává hostitel do `vm.run(inst, what, limit)` (nastavení `pyntr-watchdog-limit`, plán 2) | 10 000 |
| Limit paměti (prvky list/tuple/dict v globálech; řetězec = 1 + délka // 100) | `vm.check_memory(G, limit)` (nastavení `pyntr-memory-limit`, plán 2) | 10 000 |

## Známé odchylky od Pythonu
- `int` a `float` se nerozlišují: `6 / 2` vypíše `3`, ne `3.0`; čísla nad 2^53 ztrácí přesnost.
- Bitové operace jsou 32bitové se znaménkem (jako obvodová síť).
- `dict.keys()/values()/items()` vrací list, ne pohled.
- Klíčem slovníku může být jen `str`, číslo nebo `bool`.
- `def` na nejvyšší úrovni jsou dostupné i před svou definicí (hoisting).
- Přiřazení do globálu ve funkci bez `global` je chyba překladu (Python by vytvořil lokální proměnnou).

## Determinismus (multiplayer)
- Kód jazyka nesmí záviset na locale: řetězce se porovnávají a řadí po bajtech (`R.strcmp`), lexer používá jen ASCII třídy znaků (`[A-Za-z0-9_]`, ne `%a/%w`), `upper/lower` mění jen ASCII a čísla se formátují s tečkou i při locale s desetinnou čárkou. Hlídají to testy v `tests/unit/test_hardening.lua` s českým locale.
