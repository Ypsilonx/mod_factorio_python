# Pythonator – plán 2: budova ve hře

**Cíl:** Z hotového jádra jazyka udělat hratelnou budovu: prototyp, recept a výzkum kompatibilní s overhaul mody,
běh programů plánovačem s časovou garancí T → T+1, persistence, blueprinty, integrační a výkonové testy a vlastní
model z Blenderu s logem Pythonu.

**Architektura:** `control.lua` jen napojuje události na moduly v `Pythonator/scripts/` (controller, io, scheduler,
lifecycle, blueprint, remote). Jazyk (`scripts/lang/`) se nemění, jen se volá přes `compiler.compile`,
`vm.instantiate`, `vm.run` a `vm.check_memory`. Stav je jen ve `storage`. Přeložené instance leží v cache mimo
`storage` a staví se líně.

**Spec:** `docs/superpowers/specs/2026-10-09-pythonator-design.md` (sekce Budova, Životní cyklus, Plánování,
Vstupy a výstupy, Testy, Rizika).

**Mimo tento plán:** GUI editor (plán 3). Kód se zatím nahrává přes remote interface a konzoli, vanilla okno
kombinátoru se neotevře.

## Global Constraints

- Factorio 2.0.77 stable, hra běží na Lua 5.2. Prefix `pyntr` / `pyntr-` u všeho globálního (prototypy,
  nastavení, GUI, tagy, remote, log tagy testů `PYNTR-TEST`).
- Determinismus: žádný měnitelný stav v upvalues kromě cache instancí odvozené ze `storage`. `on_load` nemění `storage`.
- UPS: nikdy neprocházet všechny kontroléry každý tick. Spouští je jen plánovač.
- Texty pro hráče jen přes locale `en` i `cs`. Komentáře a docstringy česky.
- Před ohlášením hotovo: `run-unit.sh` + `run-tests.sh vanilla` + `run-tests.sh space-age` zelené.

## Review Focus

1. Uložení a načtení hry uprostřed běhu: globály, výstupy, `None`, pořadí dict a plán musí pokračovat beze změny.
2. Zbourání nebo smrt budovy kteroukoli cestou: skryté kombinátory nesmí zůstat ve světě.
3. Cizí mod přidá recept nebo signál se jménem `pyntr-…`: hledat podle `mod-data` a `storage`, ne podle prefixu.
4. Tisíce výstupních signálů: limit slotů v sekci konstantního kombinátoru.
5. Výpadek proudu a jeho obnovení: `tick` stojí, `dt` naroste, výstupy zůstanou.

---

### Task 1: Ověřovací prototyp rizik (spike, kód se zahodí)

**Soubory:** dočasně v `Pythonator/` na pracovní větvi. Výsledek se zapíše do `docs/development.md` (sekce
„Ověřená rizika“), kód se nezachová.

**Co:** minimální entita 2×2 odvozená z `arithmetic-combinator` a testovací okno s `text-box`. Ověří se:
(1) `text-box` s rich textem a `icon_selector`, (2) Tab v `text-box`, (3) čísla řádků vedle `text-box`
(podívat se do `fcpu` v `%APPDATA%/Factorio/mods`), (4) 2×2 kombinátor: dráty, vstupní a výstupní strana,
rotace, (5) montovna „Set recipe“ a signál typu `recipe` proti `item`.

**Ověření:** ty projdeš body 1–5 ve hře podle krátkého checklistu. Když něco nefunguje (hlavně 2×2), zastavíme
se a rozhodneme fallback spolu, dřív než na tom postavíme další tasky.

### Task 2: Kostra modu, nástroje, nastavení

**Soubory:** `Pythonator/{settings.lua,data.lua,control.lua,changelog.txt}`, `tools/{run-tests.sh,link-mod.sh,package.sh}`,
`tests/pythonator-tests/{info.json,control.lua,runner.lua,cases/smoke.lua}`, `.vscode/tasks.json`,
`tests/unit/test_locale.lua`. Šablony vezmu ze skillu `factorio-mod`.

**Co:** map settings `pyntr-watchdog-limit` (výchozí 10 000, strop 200 000) a `pyntr-memory-limit`
(10 000, strop 200 000). Testovací mod s runnerem a smoke testem. `info.json` dostane `quality` jako volitelnou
závislost pro Space Age variantu.

**Ověření:** `run-tests.sh vanilla` a `space-age` vypíšou `PYNTR-TEST DONE pass=1 fail=0`.

### Task 3: Prototypy – entita, skryté výstupy, předmět, recept, výzkum

**Soubory:** `Pythonator/prototypes/{entity.lua,hidden.lua,item.lua,recipe.lua,research.lua,mod_data.lua}`,
`Pythonator/data-final-fixes.lua`, `tests/unit/test_recipe.lua`, `tests/unit/test_research.lua`.

**Rozhraní:**
- `recipe.ingredients(raw) → {{type, name, amount}…}`: kandidáti na každou surovinu, první existující
  v `raw.item` vyhrává, duplicity se sloučí. Výchozí: advanced-circuit ×5, decider-combinator ×2,
  arithmetic-combinator ×2, steel-plate ×5.
- `research.build(raw, ingredients) → tech | nil`: prerekvizity dopočtené z výzkumů, které odemykají suroviny,
  plus `circuit-network`. Tranzitivně zbytečné se vyřadí. Jednotka vědy se převezme z prerekvizity s nejvíc
  druhy vědy. Vzor: `Storage_optimizer/prototypes/research.lua`.
- `mod-data` `pyntr-data`: jméno entity, jména skrytých kombinátorů a energie.

**Co:** entita `pyntr-pythonator` (`deepcopy` z `arithmetic-combinator`). Má 2×2 collision a selection box,
50 kW (konstanta nahoře v `entity.lua`) a dočasnou grafiku, tedy zvětšený vanilla sprite s tintem.
Skrytý `constant-combinator` `pyntr-output` slouží jako výstup. Recept a výzkum vznikají v
`data-final-fixes.lua`, aby viděly cizí mody, a do logu se vypíšou suroviny a prerekvizity.

**Ověření:** unit testy s falešným `data.raw` (vanilla, chybějící surovina, Py styl s alternativními recepty)
a v integraci smoke „entita, recept i výzkum existují a výzkum je dosažitelný“.

### Task 4: Kontrolér – stav, cache instancí, životní cyklus kódu

**Soubory:** `Pythonator/scripts/{controller.lua,resolver.lua,metatables.lua}`, `tests/unit/test_controller.lua`.

**Rozhraní:**
- `storage.controllers[unit_number] = {entity, outputs = {red, green}, code, running, error, globals, out_store
  = {both, red, green}, tick, last_run, interval, outputs_mode, prints, used}`
- `controller.create(entity) → ctl`, `controller.destroy(unit_number)`
- `controller.set_code(ctl, source) → ok, err`: při chybě překladu běží dál starý program. Při úspěchu
  proběhne reset globálů, init a vymazání výstupů.
- `controller.instance(ctl) → inst`: líně z cache `instances[unit_number]` mimo `storage`.
- `controller.run_loop(ctl, game_tick)`, `controller.start(ctl)`, `controller.stop(ctl)`
- `resolver.get() → resolver` nad `prototypes.{item,fluid,virtual_signal,recipe,entity,space_location,asteroid_chunk,quality}`,
  postavený jednou v rámci modulu

**Co:** napojení VM na stav, `print` do kruhového logu (50 řádků) a pojistka paměti každých 60 ticků.
Čtení i zápis signálů zatím přes falešné IO (Task 5).

**Ověření:** unit test s napodobeninou entity: nový kód resetuje globály, chybný kód nechá běžet starý,
po zahození cache (simulace načtení) se instance postaví znovu bez initu a stav pokračuje.

### Task 5: Vstupy a výstupy na drátech

**Soubory:** `Pythonator/scripts/io.lua`, `tests/unit/test_io.lua`.

**Rozhraní:**
- `io.reader_source(entity, connector_ids) → {get(canonical) → int, all() → {{klíč, hodnota}…}}`: `all()`
  se načte nejvýš jednou za tick.
- `io.flush(ctl)`: rozdíl `out_store` proti minulému ticku zapíše do sekce skrytých kombinátorů.
  `slot_of[klíč]` se drží ve `storage`, volné sloty se recyklují.

**Ověření:** unit test diffu (nezměněný výstup = žádné volání API) a integrační test „vstup v T → výstup v T+1“
vedle vanilla aritmetického kombinátoru se stejným zpožděním. Integrace dál ověří hold/clear, `out_red`,
`out_green` a kvalitu v klíči (space-age).

### Task 6: Plánovač a napájení

**Soubory:** `Pythonator/scripts/scheduler.lua`, `tests/unit/test_scheduler.lua`.

**Rozhraní:** `scheduler.add(unit_number, tick)`, `scheduler.on_tick(game_tick)`: spustí jen kontroléry
naplánované na tento tick a přeplánuje je o `interval`. Pojistka proti dvojímu zařazení je `scheduled_tick`.

**Co:** zastavené a chybové kontroléry se nezařazují. Bez proudu se kontrolér přeplánuje o 60 ticků, `tick` stojí
a po obnově proudu `dt` zahrne celou pauzu.

**Ověření:** unit test plánu a integrace výpadku proudu (`tick` a `dt` podle specu, výstupy zůstanou).

### Task 7: Stavba, bourání, blueprinty, copy-paste, remote

**Soubory:** `Pythonator/scripts/{lifecycle.lua,blueprint.lua,remote.lua}`, `Pythonator/control.lua`.

**Rozhraní (remote `pyntr`):** `set_code(unit, src) → ok, err`, `get_state(unit) → {running, error, tick,
globals (repr), outputs, prints, used}`, `start(unit)`, `stop(unit)`, `step(unit)`.

**Co:** stavba a odstranění všemi cestami. Vytvoří se dva skryté výstupy připojené drátem s
`wire_origin.script` a při zbourání se uklidí. Blueprint tag `pyntr_code` a `pyntr_running` přenáší kód, ne
stav. Copy-paste mezi budovami. Vanilla okno kombinátoru se zavře (do plánu 3). Při `on_configuration_changed`
se doplní tabulky, uklidí neplatné záznamy a přestaví plán.

**Ověření:** integrační testy pro stavbu a zbourání robotem i skriptem (nezůstanou skryté entity), blueprint
s kódem, copy-paste a remote.

### Task 8: Integrace jazyka ve hře (Lua 5.2) a uložení/načtení

**Soubory:** `tests/pythonator-tests/cases/{lang.lua,persistence.lua}`. `tools/run-tests.sh` při běhu zkopíruje
`tests/conformance/*.py|.out` do testovacího modu (generovaný soubor jen v `.test-run/`).

**Co:** konformní programy poběží ve skutečné budově na Lua 5.2 hry a porovná se `print` log. Pojistky
watchdog i paměť se ověří s map settings. Persistence: nejdřív ověřím, jestli headless běh zvládne
„uložit → načíst“ (dvě fáze `--benchmark`). Když ne, test zahodí cache a zavolá cestu `on_load` a skutečné
načtení přidám do checklistu ruční kontroly.

**Ověření:** `run-tests.sh vanilla` i `space-age` zelené, včetně konformních programů.

### Task 9: Kompatibilita a výkon

**Soubory:** `tests/pythonator-tests/cases/compat.lua`, `tests/perf/pyntr-perf/`, `tools/run-perf.sh`,
`docs/development.md`.

**Co:** `run-tests.sh mods pymodpack`, `mods bobrevamp` a `mods aai-industry`. Kontroluje se, že entita vznikla,
recept má výzkum a každá surovina je nejpozději s ním vyrobitelná. Výkon: N budov s typickým programem
(hystereze nad 20 signály) proti prázdné mapě, výsledek v ms/tick do `docs/development.md`.

**Ověření:** všechny tři mody projdou a výkonové číslo je zapsané (verze hry, počty).

### Task 10: Model v Blenderu – logo Pythonu

> **Poznámka:** na budově bude **logo Pythonu** (dva propletení hadi, modrá `#3776AB` a žlutá `#FFD43B`).
> Je to hlavní vizuální prvek a má to vypadat. Modeluju živě v tvém Blenderu přes MCP, ty se díváš
> a připomínkuješ, další krok dělám až po tvém OK.

**Soubory:** `blender/build_sprites.py` + `blender/pyntr_{model,materials,render}.py`, `Pythonator/graphics/entity|icons/`,
`Pythonator/prototypes/wires.lua`, `tests/unit/test_sprites.lua`. Vzor je pipeline ve
`factorio_loader-unloader/blender/`, postup podle skillu `blender-workflow`.

**Co:** postup po krocích, každý ukážu screenshotem. (1) Tvar skříně 2×2 a měřítko proti vanilla kombinátoru.
(2) Logo a materiály. (3) Detaily vstupu a výstupu, aby byla čitelná orientace. (4) Render 4 směrů, stínu,
ikony 64 px, ikony výzkumu 256 px a thumbnailu 144 px. Body drátů se spočítají ze stejné projekce
(`wires.lua`) a nahradí dočasnou grafiku z Tasku 3.

**Na co pozor:** logo má zůstat čitelné při 64 px na dlaždici. Při rotaci se otáčí vstup a výstup, logo může
zůstat vzpřímené, to rozhodneš v kroku 3. Licence: PSF Trademark Policy, před publikací ověřit. Bezpečnější
je vlastní stylizace dvou hadů než přesná kopie loga.

**Ověření:** test rozměrů PNG a tvoje kontrola ve hře (vzhled, dráty sedí na konektory ve všech 4 směrech).

---

## Body napojení na Factorio API

| Vstupní bod | Parametry → výsledek | Na co pozor |
|---|---|---|
| **data stage** `data.lua` / `data-final-fixes.lua` | `data.raw` → prototypy | Recept a výzkum až ve final-fixes. `pypostprocessing` přepočítá vědu, když běžíme dřív (pořadí ověřit v `create.log`). U `deepcopy` vynulovat `next_upgrade`, `fast_replaceable_group`, `minable.result` a správně nastavit `placeable_by`. |
| `CombinatorPrototype` (arithmetic) | `input_connection_points`, `output_connection_points` (4 směry), `active_energy_usage`, `energy_source` | 2×2 není ověřené (Task 1). Sprite se musí vejít do nové velikosti. |
| skrytý `constant-combinator` | flags `not-on-map`, `not-blueprintable`, `not-deconstructable`, `placeable-off-grid`, `hide-alt-info`, `no-copy-paste`; `hidden = true`, `selectable_in_game = false`, prázdná `collision_mask` | Nesmí se dát vybrat ani vytěžit a nesmí zůstat po zbourání. |
| `mod-data` | `prototypes.mod_data["pyntr-data"].data` | Načíst jednou na úrovni modulu. |
| **control** `script.register_metatable(name, mt)` | jméno → metatabulka | Jen na úrovni modulu (ne v událostech) pro `ListMT`, `TupleMT`, `DictMT` a `NoneMT`. `None` se porovnává podle metatabulky, ne identity (ověřeno v runtime). |
| `script.on_init` | – | Založit `storage.controllers`, `storage.schedule` a `storage.slots`. |
| `script.on_load` | – | Nesmí měnit `storage`. Cache instancí se jen nezakládá, staví se líně. |
| `script.on_configuration_changed` | `ConfigurationChangedData` | Doplnit tabulky, uklidit neplatné entity, přestavět plán. Starý save musí projít. |
| `prototypes.*` v control | slovníky prototypů | Resolver z nich postavit jednou při načtení modulu (deterministické, cizí mody v ceně). Ověřit, že `prototypes` je dostupný na úrovni modulu. |
| `on_tick` | `{tick}` | Volá jen `scheduler.on_tick`. Vstupy čtené v ticku T = co ostatní poslali v T−1. Zápis v T vidí ostatní v T+1 (ověřit integračním testem proti vanilla kombinátoru). |
| `LuaEntity.get_signal(signal, wire_connector_id, extra_wire_connector_id?)` | `SignalID` (vč. `quality`) → int32 | Konektory `combinator_input_red` a `combinator_input_green`. Pro `inp` předat oba najednou. |
| `LuaEntity.get_signals(wire_connector_id, extra?)` | → `Signal[]` nebo nil | nil = nic na drátě. |
| `LuaWireConnector.connect_to(target, reach_check, origin)` | → bool | `reach_check = false`, `origin = defines.wire_origin.script` (hráč drát nevidí ani neodstraní). Výstup: `combinator_output_red/green` ↔ `circuit_red/green` skrytého kombinátoru. |
| `LuaConstantCombinatorControlBehavior` → `LuaLogisticSection` `set_slot(i, filter)` / `clear_slot(i)` / `filters` | `LogisticFilter {value = {type, name, quality, comparator = "="}, min = hodnota}` | Jen manuální sekce. Limit slotů v sekci ověřit (Review Focus 4), při přetečení chyba programu, ne pád. |
| aritmetický kombinátor sám | `parameters` bez signálů → nevysílá nic | Hráč ho nesmí přenastavit: `on_gui_opened` → `player.opened = nil`. Blueprint uloží prázdné parametry. |
| stavba: `on_built_entity`, `on_robot_built_entity`, `on_space_platform_built_entity`, `script_raised_built`, `script_raised_revive` | `entity`, `tags` | Event filtry na jméno entity. Tagy z blueprintu nesou kód. |
| odstranění: `on_player_mined_entity`, `on_robot_mined_entity`, `on_space_platform_mined_entity`, `on_entity_died`, `script_raised_destroy` | `entity` | Uklidit skryté entity, `storage` a plán. Pojistka: `script.register_on_object_destroyed`. |
| `on_player_setup_blueprint` | `player_index`, `mapping` | `mapping.get()` dává mapování na zdrojové entity → `blueprint.set_blueprint_entity_tag`. |
| `on_entity_settings_pasted` | `source`, `destination` | Kód + running, stav ne. |
| `on_runtime_mod_setting_changed` | `setting` | Limity číst ze `settings.global` při běhu (ne cache v upvalue). |
| `remote.add_interface("pyntr", …)` | viz Task 7 | Jen data, žádné funkce v návratových hodnotách. |
| headless testy | `--create` + `--benchmark` v `.test-run/` | Bez hráče a bez GUI. Uložení a načtení viz Task 8. |
