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
- `bash tools/run-tests.sh vanilla|space-age` – integrační testy v headless Factoriu (testovací mod `tests/pythonator-tests/`, běh v `.test-run/`). Běží dvoufázově: headless server (jen 127.0.0.1:34297) dojede do uložení hry v ticku `SAVE_TICK` (`tests/pythonator-tests/runner.lua`), pak se uložená pozice načte v `--benchmark` – všechny delší testy tak přejdou přes skutečné uložení a načtení. Konformní programy jazyka se do testovacího modu generují (`tools/conformance-data.lua`) a běží ve hře na Lua 5.2.
- `bash tools/run-tests.sh mods <mod>…` – kompatibilita s cizími mody ze `%APPDATA%/Factorio/mods`.
- `bash tools/link-mod.sh` – propojí `Pythonator/` do složky modů hry (junction) pro ruční zkoušení.

## Kde ladit hodnoty
| Hodnota | Kde | Výchozí |
|---|---|---|
| Limit watchdogu (průchod cyklem a volání funkce = 1; vestavěné funkce a operace s kontejnery/řetězci platí počtem prvků či bajtů výsledku, PŘED alokací) | předává hostitel do `vm.run(inst, what, limit)` – map setting `pyntr-watchdog-limit` (`Pythonator/settings.lua`, 100–200 000, strop `LIMIT_MAX`) | 10 000 |
| Limit paměti (prvky list/tuple/dict v globálech; řetězec = 1 + délka // 100) | `vm.check_memory(G, limit)` – map setting `pyntr-memory-limit` (`Pythonator/settings.lua`, 100–200 000) | 10 000 |
| Spotřeba budovy | `ENERGY_USAGE` v `Pythonator/prototypes/entity.lua` | 50 kW |
| Tint dočasné grafiky a ikony | `TINT` v `Pythonator/prototypes/entity.lua` | modrá |
| Suroviny receptu (kandidáti s náhradami) | `INGREDIENTS` v `Pythonator/prototypes/recipe.lua` | 5× advanced-circuit, 2× decider, 2× arithmetic, 5× steel-plate |
| Výzkum: povinné prerekvizity, věda navíc, cena | `EXTRA_TECHS`, `EXTRA_PACKS`, `COUNT_MULTIPLIER` v `Pythonator/prototypes/research.lua` | circuit-network; modrá věda; 1,5× nejdražší prerekvizita |
| Opakování pokusu bez proudu | `POWER_RETRY_TICKS` v `Pythonator/scripts/scheduler.lua` | 60 ticků |
| Délka logu print() / interval kontroly paměti | `PRINT_LINES`, `MEMORY_CHECK_TICKS` v `Pythonator/scripts/controller.lua` | 50 řádků / 60 ticků |

## Známé odchylky od Pythonu
- `int` a `float` se nerozlišují: `6 / 2` vypíše `3`, ne `3.0`; čísla nad 2^53 ztrácí přesnost.
- Bitové operace jsou 32bitové se znaménkem (jako obvodová síť).
- `dict.keys()/values()/items()` vrací list, ne pohled.
- Klíčem slovníku může být jen `str`, číslo nebo `bool`.
- `def` na nejvyšší úrovni jsou dostupné i před svou definicí (hoisting).
- Přiřazení do globálu ve funkci bez `global` je chyba překladu (Python by vytvořil lokální proměnnou).
- Knihovna kombinátorů (`each`, `where`, `count`, `sum`, `max_key`, `min_key`, `set`, `add`) nemá v CPythonu obdobu; konformní harness ji napodobuje třídou `Signals`. Vektorové metody má v Pythonatoru i obyčejný `dict` (kvůli řetězení), v CPythonu jen výsledky knihovny. Aritmetika `each` je jako u kombinátoru: `/` a `%` k nule, dělení nulou = 0, int32.

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

## Checklist ruční kontroly (headless test nemá hráče)
- [ ] Postavit Pythonator ručně – klik na budovu neotevře vanilla okno kombinátoru.
- [ ] Nahrát kód z konzole: `/c remote.call("pyntr", "set_code", game.player.selected.unit_number, "def loop():\n  out['signal-A'] = 1")` (s budovou pod kurzorem) a ověřit signál na výstupu.
- [ ] Blueprint budovy s kódem → postavit z něj → kód jede (`remote.call("pyntr", "get_state", …)`).
- [ ] Shift+pravý / levý klik mezi dvěma budovami přenese kód.
- [ ] Ctrl+C / Ctrl+V budovy přenese kód.
- [ ] Vytěžit budovu → nezůstanou žádné skryté entity (Alt-mód, F4 → show-entity-info).

## Napájení
Pythonator běží, když má v zásobníku energii aspoň na jeden tick (`entity.energy >= get_max_energy_usage`), **nebo** když se energie od minulé kontroly změnila (`ctl.last_energy`, `scripts/scheduler.lua` `powered()`). Sonda (Factorio 2.0.77):

| Situace | `energy` | `status` | Pythonator |
|---|---|---|---|
| dostatek proudu | ≥ spotřeba ticku | `working` | běží |
| podpětí (zdroj dá ~polovinu) | kolísá pod spotřebou (820, 1240 …) | `low_power` | běží (119/120 ticků, jako vanilla kombinátor) |
| zdroj zmizel, síť zůstala | stojí na zbytku (222) | `low_power` | stojí |
| zbouraný sloup | stojí na zbytku (222) | `low_power` | stojí |

Stav entity rozhodovat nemůže (`low_power` ve všech třech případech). Skok energie při výpadku pustí ještě jeden běh (dobíhá zásobník); první kontrola po postavení v podpětí nemá s čím srovnat, takže Pythonator začne až po 60 ticích.

## Kompatibilita (ověřeno 2026-10-09, Factorio 2.0.77)
`bash tools/run-tests.sh mods …` – obecné kontroly z `cases/compat.lua` (entita, recept, výzkum, dostupnost surovin):
| Mody | Výsledek | Suroviny / prerekvizity |
|---|---|---|
| Pyanodon (`pymodpack` + závislosti) | ✓ | vanilla suroviny; prerekvizity basic-electronics, chemical-science-pack, circuit-network, steel-mk02; naše final-fixes běží před `pypostprocessing`, který vědu přepočítá |
| Bob's (`bobrevamp` + 16 modů) | ✓ | vanilla suroviny; chemical-science-pack, circuit-network |
| AAI Industry | ✓ | vanilla suroviny; chemical-science-pack, circuit-network |

## Výkon (`bash tools/run-perf.sh`, 500 budov, zdroj 20 signálů, 3600 ticků, Factorio 2.0.77)
| Režim | ms/tick | µs na budovu |
|---|---|---|
| idle (jen zdroj a proud) | 0,14 | – |
| decider (vanilla rozhodovací kombinátor) | 0,14 | ~0 |
| pass (prázdný `loop()`) | 1,65 | 3,3 |
| items (průchod `inp.items()`, 20 signálů, sdílená síť) | 3,66 | 7 |
| get20 (20× `inp['signal-X']`) | 12,2 | 24 |
| hyst (hystereze nad 20 signály, sdílená síť) | 14,8 | 30 |
| hyst-own (hystereze, každá budova vlastní síť) | 29,7 | 59 |

Hlavní cena je čtení signálů z enginu (`get_signals` s 20 signály ~25 µs, `get_signal` ~1,2 µs za signál).
Budovy na téže síti čtou v jednom ticku jen jednou (sdílená cache podle `network_id` v `scripts/io.lua`).
Vývoj: první měření hyst 108 ms → 50,5 (řazení klíčů jen při změně, zápis výstupů jen po změně, cache
nastavení a energie) → 31,2 (rychlé cesty překladače: `for … in x.items()/keys()/values()` bez seznamu,
`a if c else b` s literálem bez closure, `d.get`/`l.append` bez dispatch, číselné operace bez převodů)
→ 14,8 / 29,7 (sdílené čtení sítě).

Lokální rychlé měření jazyka bez hry: `lua tools/bench-lang.lua` (µs na loop() pro sadu programů,
napodobené API – čísla jen pro porovnání změn).

## Grafika (Blender 5.2, `blender/`)
Skripty jsou zdroj pravdy, výstupy (PNG, `prototypes/graphics_data.lua`) se ručně neupravují.
- Spuštění v běžícím Blenderu přes MCP: `exec` souboru `blender/build_sprites.py` s `PYNTR_STAGE` = `model` (jen scéna), `preview` (náhledy do `blender/renders/`, gitignored) nebo `render` (sprity do modu, ~2 min).
- Headless: `blender -b --factory-startup --python blender/build_sprites.py` (výchozí fáze `render`).
- Výstupy: `graphics/entity/pythonator.png` + `-shadow.png` (4 směry N, E, S, W vedle sebe, 224 px = 3,5 dlaždice, `scale = 0.5`), `pythonator-led.png` (záře LED, 2 snímky), `graphics/icons/pythonator.png` (64), `graphics/technology/pythonator.png` (256), `thumbnail.png` (144), `prototypes/graphics_data.lua` (body drátů a poloha LED promítnuté stejnou kamerou).
- Projekce: ortografická kamera pod 45°, model natažený v ose Y o √2 (čtvercová dlaždice jako ve hře).

| Co ladit | Kde |
|---|---|
| Kamera, světla, šířka snímku | `blender/camera.toml` |
| Rozměry a polohy součástek, drátky, LCD, logo | `blender/pyntr_layout.py` (sdílí model i textura desky) |
| Materiály a míra prachu | `blender/pyntr_materials.py` (parametr `dust`), patina `blender/pyntr_patina.py` |
| Textura plošného spoje (barvy, šířky, semínko cest) | `blender/pyntr_pcb.py` (`MASK`, `TRACE_W`, `SEED` …) |
| Logo Pythonu (tvar, barvy, svit) | `blender/pyntr_logo.py` (`SNAKE`, `EYE_POS`, `GLOW`) – vlastní stylizace, ochrannou známku PSF ověřit před publikací |
| Záběr ikon | `ICON_ORTHO`, `ICON_SHIFT` v `blender/build_sprites.py` |
| Barvy stavové LED | `COLORS` v `Pythonator/scripts/indicator.lua` |
| Rytmus blikání | `BLINK`, `ANIMATION_SPEED` v `Pythonator/prototypes/led.lua` |

### Ruční kontrola grafiky ve hře
- [ ] Budova ve všech 4 směrech (R): sedí na mřížce 2×2, stín doprava dolů, LCD vzadu.
- [ ] Dráty: červený/zelený se připojí na šroubky vstupní (u výstupu kombinátoru vstup = strana „vstupu“ při najetí myší) a výstupní svorkovnice ve všech směrech; stín drátu sedí.
- [ ] Stavová LED: bez kódu zhasnutá, po nahrání kódu bliká zeleně, `stop` = žlutá, chyba = červená; po otočení budovy LED „sedí“ na objímce.
- [ ] Ikona v inventáři, ve stromu výzkumu a thumbnail v seznamu modů.

## Známá omezení a odložené drobnosti (review plánu 2)
- Chyba uprostřed `loop()`: výstupy zapsané před chybou zůstanou v `ctl.out`, ale na drát se nepošlou – drát drží stav z posledního úspěšného běhu (GUI v plánu 3 má ukazovat stav drátu).
- Undo zbourání (Ctrl+Z) vrátí budovu bez kódu – duch z undo nenese tagy (řešitelné přes undo-redo API 2.0).
- Po načtení hry se každý program překládá zvlášť a všechny v prvním ticku (při stovkách budov krátké zaškobrtnutí).
- `set_slot` skrytého výstupu vyvolá `on_entity_logistic_slot_changed` – mody, které ji poslouchají, platí za každou změnu výstupu.
- Varianta testů `mods …` je jednofázová (bez uložení a načtení).
