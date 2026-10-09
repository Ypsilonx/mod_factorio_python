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
| `vector.lua` | knihovna kombinátorů: vektorové operace (`each`, `where`, `count`, `sum`, `max_key`, `min_key`) nad pohledem `(keys, vals)` |
| `elements.lua` | knihovna kombinátorů: stavové prvky pod jménem (`latch`, `timer`, `edge`, `counter`, `delay`, `pid`), stav v globálu `"#lib"` |

## GUI (`Pythonator/scripts/gui/`)
| Modul | Úloha |
|---|---|
| `window.lua` | okno hráče: stavba, `refresh` (text editoru + stav + panely), `refresh_live` (periodicky bez přepisu textu), stav `storage.gui[player_index] = {unit, refs, text, edit, error_line}` |
| `editor.lua` | text-box s čísly řádků, výška podle řádků, posun na změněný řádek |
| `status.lua` | lišta tlačítek, panel stavu (stav, tick, cena), pruh chyby |
| `panels.lua` | vstupy R/G, výstupy (stav drátu), globály, prvky knihovny, log |
| `help.lua` | okno nápovědy a příklady; seznam karet a kód příkladů sdílí s Tipy a triky (`prototypes/tips.lua`) |
| `events.lua` | obsluha událostí GUI podle tagu `pyntr_action`, obnova `on_nth_tick`, úklid po odchodu hráče a změně modů |

Akce Play/Pauza/Reset/Krok a pohled na stav (`actions.view` → co zobrazit a povolit) jsou v `scripts/actions.lua`, sdílené s remote interface. GUI se testuje unit testy s napodobeninou `LuaGuiElement` (`tests/unit/fake_gui.lua`); `test_gui_names.lua` hlídá jména prvků proti `runtime-api.json` a existenci stylů, integrační `cases/gui.lua` font a styly ve hře.

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
| Největší zpoždění `delay()` (velikost bufferu) | `DELAY_MAX` v `Pythonator/scripts/lang/elements.lua` | 1000 volání |
| Rozměry editoru: šířka textu, viditelná výška, výška řádku, min. počet řádků (box vyšší než pohled schová výběr ikon), rezerva, šířka čísel řádků, místo pro posuvník | `WIDTH`, `VIEW_HEIGHT`, `LINE_HEIGHT`, `MIN_LINES`, `HEIGHT_RESERVE`, `GUTTER_WIDTH`, `SCROLLBAR_WIDTH` v `Pythonator/scripts/gui/editor.lua` (styly v `prototypes/gui.lua` je přebírají) | 640 / 520 / 20 / 10 / 12 / 36 / 24 px |
| Mezera mezi editorem a pravými panely | `PANEL_GAP` v `Pythonator/scripts/gui/window.lua` | 12 px |
| Výška logu print() | `height` ve stylu `pyntr_log_scroll` v `Pythonator/prototypes/gui.lua` | 160 px |
| Barvy čísel řádků (běžné / chyba) | `COLOR_LINE`, `COLOR_ERROR` v `Pythonator/scripts/gui/editor.lua` | šedá / červená |
| Font editoru | `pyntr-mono` v `Pythonator/prototypes/gui.lua` (`from = "default-mono"`, velikost) | 14 |
| Barva pruhu ceny (podíl limitu watchdogu: žlutá / červená) | `COST_WARN`, `COST_HIGH` v `Pythonator/scripts/gui/status.lua` | 0,5 / 0,9 |
| Obnova otevřeného okna (ticky) | `REFRESH_TICKS` v `Pythonator/scripts/gui/events.lua` | 10 |
| Limity panelů: ikon signálů, délka repr, počet globálů, sloupce mřížky | `PANEL_MAX_ROWS`, `REPR_MAX`, `GLOBALS_MAX`, `SIGNAL_COLUMNS` v `Pythonator/scripts/gui/panels.lua` | 60 / 60 / 40 / 6 |
| Rozměry okna nápovědy (šířka textu, výška karet) | `TEXT_WIDTH`, `HEIGHT` v `Pythonator/scripts/gui/help.lua` | 620 / 560 px |

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
- [ ] Postavit Pythonator ručně – klik na budovu otevře okno Pythonatoru (ne vanilla okno kombinátoru).
- [ ] Nahrát kód z konzole: `/c remote.call("pyntr", "set_code", game.player.selected.unit_number, "def loop():\n  out['signal-A'] = 1")` (s budovou pod kurzorem) a ověřit signál na výstupu.
- [ ] Blueprint budovy s kódem → postavit z něj → kód jede (okno ukáže BĚŽÍ a stejný kód).

### GUI (okno, editor, nápověda)
- [ ] Okno: titulek jde táhnout, ✕, E i Esc ho zavřou; otevření jiné budovy okno přepne.
- [ ] Editor: psaní, výběr, Ctrl+C/V/A; čísla řádků sedí na řádky textu i u dlouhého kódu (100+ řádků); při psaní na konci dlouhého kódu se pohled posouvá za psaním.
- [ ] Výběr ikony v rohu editoru vloží rich text signálu na kurzor; program s ikonou se přeloží.
- [ ] Za běhu je editor jen pro čtení; ⏸ ho odemkne; rozepsaný kód přežije zavření okna i uložení hry.
- [ ] ▶ se změněným kódem s chybou: červený pruh „Řádek N: …“, červené číslo řádku, klik na pruh posune editor na řádek; program zůstane pozastavený.
- [ ] Chyba běhu (např. `1 // 0`): stav CHYBA, ▶ nejde, ⟳ Reset jde; po opravě kódu ▶ spustí nový kód.
- [ ] ⏭ při pauze: tick a globály se posunou o jeden loop().
- [ ] Panely: vstupy R/G ukazují signály z drátů, výstupy stav drátu, globály a prvky knihovny se mění za běhu; tlačítko Log rozbalí výpis print().
- [ ] Cena a pruh ceny se mění podle programu (smyčka s mnoha průchody → žlutá/červená).
- [ ] Nápověda (?): karty Základy, Signály, Jazyk, Knihovna, Příklady jsou čitelné v cs i en; „Vložit do editoru“ při pauze nahradí text příkladem a ▶ ho spustí.
- [ ] Zbourání budovy s otevřeným oknem okno zavře bez chyby; totéž po aktualizaci modu (okna se zavřou).
- [ ] Okno nad budovou se 100 signály na vstupu: UPS v F4/debug se viditelně nezmění.
- [ ] Multiplayer (pokud jde vyzkoušet): Play jednoho hráče obnoví okno druhého.
- [ ] Víceřádková chyba (dlouhá hláška): červený pruh se roztáhne a nezakryje lištu tlačítek pod sebou.
- [ ] Shift+klik vložení nastavení do pozastavené budovy s otevřeným oknem: editor ukáže vložený kód a ▶ spustí právě ten.
- [ ] Glyfy ▶ ⏸ ⟳ ⏭ ● v textech stavu, tooltipech a nápovědě se vykreslí (ne čtverečky).
- [ ] Po uložení a načtení s otevřeným oknem zavřou okno E i Esc (ne jen ✕).
- [ ] Příklad „Sekvence“ v nápovědě: `"ABSU"[step]` se zobrazí doslova (hranaté závorky nevezme jako rich text).
- [ ] Nápověda → karta Výkon je čitelná (odrážky •, čísla); 150 budov s příkladem „Sekvence“ zapnutých najednou: v F4 → show-time-usage u mod-Pythonator nejsou špičky jednou za 60 ticků (max blízko průměru).
- [ ] Tipy a triky (F1 / menu): kategorie Pythonator je dostupná hned v nové hře (bez výzkumu a budovy), záznamy Jak začít, Signály, Jazyk, Knihovna, Výkon, Příklady; odrážky a tučné názvy funkcí se vykreslí, kód příkladů neproporcionálním písmem.
- [ ] Okno nad budovou se 300 signály na vstupu a velkým listem v globálu: UPS se viditelně nezmění.
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

### Sekvence bez čtení vstupů (`PERF_N=150 PERF_MODES="idle seq-tick seq-change seq-60" bash tools/run-perf.sh`)
| Režim (150 budov, příklad „Sekvence“) | ms/tick | Pythonator (bez idle 0,14) | µs na budovu |
|---|---|---|---|
| seq-tick – `out.clear()` + zápis každý tick | 0,98 (před zrychlením zápisu 1,07) | 0,84 | 5,6 |
| seq-change – zápis jen při změně (timer) | 0,55 | 0,41 | 2,7 |
| seq-60 – `config(interval=60)` | 0,19 | 0,05 | 0,4 |

Ve hře s F4 → show-time-usage hráč naměřil u seq-tick (před zrychlením zápisu) 2,36 ms, seq-change 1,22 ms a
seq-60 0,17 ms. Živá hra s profilerem je zhruba 2× dražší než `--benchmark`, poměry sedí. Pevná režie jednoho
spuštění `loop()` (plánovač, kontrola energie, watchdog) je ~3 µs ve hře.

Budovy s intervalem > 1 běží ve fázi `unit_number % interval` (`scheduler.first_tick`): zapnuté najednou se
rozloží do různých ticků místo jedné špičky za interval. Fáze se drží i po načtení hry a změně modů.

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
- Chyba uprostřed `loop()`: výstupy zapsané před chybou zůstanou v `ctl.out`, ale na drát se nepošlou – drát drží stav z posledního úspěšného běhu; panel Výstupy v okně ukazuje právě stav drátu (`ctl.wires`).
- Undo zbourání (Ctrl+Z) vrátí budovu bez kódu – duch z undo nenese tagy (řešitelné přes undo-redo API 2.0).
- Po načtení hry se každý program překládá zvlášť a všechny v prvním ticku (při stovkách budov krátké zaškobrtnutí).
- `set_slot` skrytého výstupu vyvolá `on_entity_logistic_slot_changed` – mody, které ji poslouchají, platí za každou změnu výstupu.
- Varianta testů `mods …` je jednofázová (bez uložení a načtení).

## Známá omezení GUI a knihovny (plán 3)
- Tab v editoru nefunguje a API nezná pozici kurzoru: pohled se posouvá jen při psaní (na první změněný řádek), šipky a myš posun nevyvolají.
- Rozepsaný kód (`ctl.draft`) je sdílený pro budovu: když píšou dva hráči současně, poslední zápis přepíše text druhému.
- Vektorové operace jsou zhruba stejně drahé jako ruční smyčka (`lua tools/bench-lang.lua`: `each2x` vs `loop2x`); řetězení `where(...).each(...)` = víc průchodů. Výhodou je hlavně kratší zápis.
- `timer` po výpadku proudu (`dt` přes několik period) vystřelí jen jednou; `pid` s mezemi při saturaci nepřičítá integrál (podmíněná integrace), výstup po odchodu ze saturace skočí.
- Panel signálů ukazuje kvalitu jen v tooltipu (ikona `sprite-button` kvalitu nevykreslí).
