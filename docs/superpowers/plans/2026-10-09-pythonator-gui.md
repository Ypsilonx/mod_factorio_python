# Pythonator – plán 3: knihovna kombinátorů a GUI editor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Cíl:** Hráč napíše, spustí a ladí program přímo ve hře. Má k tomu vlastní okno s editorem, stavem, vstupy,
výstupy, chybou a logem, tlačítka ▶ ⏸ ⟳ ⏭ a nápovědu. Jazyk dostane knihovnu kombinátorů: vektorové
operace nad signály a stavové prvky pod jménem.

**Architektura:** Knihovna je čistá Lua v `scripts/lang/` (runtime, checker, harness CPythonu) a nesahá na herní API.
GUI je v `scripts/gui/`, rozdělené na stavbu okna, obsluhu událostí, obnovu panelů a nápovědu. Logika okna
(co zobrazit, jaké akce povolit) se dá oddělit od `LuaGuiElement`, takže jde testovat unit testem s napodobeninou GUI.
Akce Play, Pauza, Reset a Krok se přesunou z `remote.lua` do společného `scripts/actions.lua`, aby je GUI i remote
volaly stejně.

**Spec:** `docs/superpowers/specs/2026-10-09-pythonator-design.md` (sekce GUI, Knihovna kombinátorů, Životní cyklus,
Rizika). Výsledky spiku pro editor jsou v `docs/development.md` → „Ověřená rizika“.

**Mimo tento plán:** publikace na portál (plán 4), zvýraznění syntaxe, auto-odsazení, undo s kódem.

## Rozhodnutí k potvrzení (navrhuji, schvaluješ s plánem)

| # | Otázka | Návrh | Trade-off |
|---|---|---|---|
| 1 | Výsledek `inp.each/where` | obyčejný `dict` klíč → číslo. Vektorové metody má i `dict` (řetězení `inp.where(">", 0).each("*", 2)`) | v CPythonu `dict` tyto metody nemá, harness vrací podtřídu `Signals`. Odchylka se zapíše |
| 2 | Aritmetika v `each` | sémantika **kombinátoru**, ne Pythonu: celočíselně, `/` k nule, dělení nulou = 0, int32 přetečení | stejná čísla jako vanilla kombinátor. Liší se od `//` v Pythonu, v nápovědě bude tabulka |
| 3 | `out.set(d)` vs. `out.add(d)` | `set` nahradí všechny výstupy daného objektu, `add` přičte | dvě metody místo jedné, ale bez `add` by se skládání výsledků psalo smyčkou |
| 4 | Stav prvků | v globálu `"#lib"` (neplatné jméno, uživatel ho nepřepíše): `{[jméno] = {kind, …}}`. Reset ho smaže s globály, paměť ho počítá, panel globálů ho skryje | jméno prvku musí být unikátní, jiný druh pod stejným jménem = chyba běhu |
| 5 | `delay`, `timer`, `pid` a čas | `timer` a `pid` počítají s `dt` (po výpadku proudu dožene). `delay(n)` počítá volání `loop()`, ne ticky | intuitivní při `interval=1`, při jiném intervalu to nápověda vysvětlí |
| 6 | Rozepsaný kód (draft) | `ctl.draft` ve `storage` se ukládá při psaní. Zavření okna ho neztratí. Blueprint ani copy-paste ho nepřenáší | více hráčů na stejné budově: vyhrává poslední zápis, okno ostatních se obnoví |
| 7 | Jeden hráč, jedno okno | otevřít jinou budovu = přepnout okno na ni | jednodušší stav: `storage.gui[player_index] = {unit, …}` |

## Global Constraints

- Factorio 2.0.77 stable, hra na Lua 5.2. Prefix `pyntr` / `pyntr-` / `pyntr_` (jména GUI prvků a stylů).
- Jména GUI prvků nesmí kolidovat s vlastnostmi `LuaGuiElement` (hlídá `test_gui_names.lua` proti `runtime-api.json`).
- Texty jen v locale `en` i `cs` se stejnou sadou klíčů (`test_locale.lua`). Komentáře a docstringy česky.
- UPS: obnova GUI jen přes `on_nth_tick(GUI_REFRESH_TICKS)` a hned končí, když nikdo nemá okno otevřené.
  Knihovna účtuje watchdogu počet zpracovaných signálů (`R.charge(n)`).
- Determinismus: GUI stav jen ve `storage.gui`, `on_load` nic nemění, žádný stav v upvalues.
- Před „hotovo“: `run-unit.sh` + `run-tests.sh vanilla` + `space-age` zelené. Vzhled a ovládání ověřuješ ty
  podle checklistu v `docs/development.md`.
- Commit po tasku jen po tvém souhlasu při spuštění plánu. Práce na větvi `feature/gui`.

## Review Focus

1. Budova zmizí, zatímco je okno otevřené (zbourání, smrt, výměna modu): okno se zavře bez chyby.
2. Dva hráči ve stejné budově: Play jednoho obnoví okno druhého a draft se nerozejde s textem v boxu.
3. Uložení a načtení s otevřeným oknem nebo aktualizace modu: `on_configuration_changed` okna zavře, žádná
   chyba „invalid element“.
4. Velké vstupy (stovky signálů) a velké globály v panelech: zobrazení se ořízne (`PANEL_MAX_ROWS`) a obnova nezabije UPS.
5. Knihovna nad prázdným vstupem, nad stejnými hodnotami (`max_key` při shodě) a s neplatným `op`:
   deterministický výsledek, nebo chyba s řádkem.

---

### Task 1: Vektorové operace nad signály

**Soubory:** `Pythonator/scripts/lang/{signal_io.lua,builtins.lua,checker.lua}`, nový `scripts/lang/vector.lua`,
locale (chyby), `tests/unit/test_vector.lua`, `tests/conformance/harness.py`, `tests/unit/prog_runner.lua`,
nový případ `tests/conformance/cases/vector.py`.

**Rozhraní** (metody objektů `inp/red/green/out*` a `dict`):
- `x.each(op, v) → dict`: `op` ∈ `+ - * / % ** << >> & | ^`, pro každý nenulový signál `hodnota op v`, výsledek 0 se vypustí.
- `x.where(op, v) → dict`: `op` ∈ `< <= > >= == !=`, nechá signály, které podmínku splní, s původní hodnotou.
- `x.count() → int`, `x.count(op, v) → int`, `x.sum() → int`, `x.max_key() / x.min_key() → str | None`.
  Při shodě vyhrává menší klíč podle bajtů (`R.strcmp`).
- `out.set(d)`, `out.add(d)` (jen zapisovací objekty). `d` je dict nebo objekt signálů. Zápis jde přes stávající
  `__setitem`, takže platí ořez, int32 i příznak `changed`.
- `vector.lua`: `M.arith(op, a, b) → int` a `M.compare(op, a, b) → bool` (sémantika kombinátoru), `M.apply(pairs, op, v) → dict`.

**Co:** jedno volání projde pole `pairs_of`, nepoužívá interpretovanou smyčku. Neplatný `op` je chyba běhu
s řádkem (`pyntr-err.bad-op`). Konstantní `op` ověří už checker. Harness: `Signals` dostane stejné metody,
hlavička `# inp: {...}` naplní vstupy (stejně se chová `prog_runner.lua`).

**Ověření:** unit testy hraničních případů (dělení nulou, int32, prázdný vstup, shoda u `max_key`), konformní
případ `vector.py` dá v CPythonu i v Lua stejný výstup a `bench-lang.lua` dostane program `each` pro porovnání
s ruční smyčkou.

### Task 2: Stavové prvky

**Soubory:** nový `Pythonator/scripts/lang/elements.lua`, `builtins.lua`, `checker.lua` (vyhrazená jména),
`vm.lua` (paměť počítá i `"#lib"`), locale, `tests/unit/test_elements.lua`, `harness.py`, případ `cases/elements.py`.

**Rozhraní** (vestavěné funkce, `name` je `str`):
- `latch(name, set, reset) → bool`: SR klopný obvod, přednost má reset.
- `timer(name, period) → bool`: `True` jednou za `period` ticků. Sčítá `dt` a přebytek si nechá.
- `edge(name, value) → int`: `1` náběžná, `-1` sestupná, `0` žádná (podle pravdivosti `value`).
- `counter(name, step=1, reset=False) → int`
- `delay(name, value, n) → any`: hodnota z doby před `n` voláními, do naplnění `0`. `n ≤ 1000`, změna `n` buffer vymaže.
- `pid(name, setpoint, measured, kp, ki, kd, lo=None, hi=None) → float`: integrál a derivace s `dt`.
  S `lo/hi` ořez výstupu a anti-windup (integrál se při saturaci nezvětšuje).
- `elements.state(G, name, kind) → table`: založí nebo vrátí stav. Jiný `kind` pod stejným jménem vyvolá
  `pyntr-err.element-kind`.

**Co:** stav je obyčejná Lua tabulka v `G["#lib"]` (uloží se se savem, nepotřebuje metatabulku). Harness
napodobí všech šest funkcí a `dt`. Jména funkcí patří mezi vyhrazená jako vestavěné.

**Ověření:** unit testy pro každý prvek (hrana při změně True/False, timer při `dt > period`, pid s ořezem,
delay se změnou `n`, kolize druhu). Konformní `elements.py` přes 20 ticků. Integrační test v `persistence.lua`:
timer a delay pokračují po uložení a načtení.

### Task 3: Společné akce a stav pro GUI

**Soubory:** nový `Pythonator/scripts/actions.lua`, `scripts/remote.lua` (bude ho volat), `scripts/controller.lua`
(`draft`), `scripts/lifecycle.lua` (hook `on_removed` pro GUI), `tests/unit/test_actions.lua`.

**Rozhraní:**
- `actions.play(ctl, text) → ok, err`: když se `text` liší od `ctl.code`, zavolá `load_code` (chyba překladu =
  pauza a `compile_error`), jinak `start`. Pak `wake`.
- `actions.pause(ctl)`, `actions.reset(ctl) → ok`, `actions.step(ctl, tick) → ok`
- `actions.view(ctl) → {state = "off"|"running"|"paused"|"error"|"no_power", tick, used, limit, error,
  compile_error, can = {play, pause, reset, step, edit}}`. Je to čistá funkce, kterou GUI jen vykreslí.
- `ctl.draft` (string | nil), `actions.set_draft(ctl, text)`. Po úspěšném Play se smaže.
- `lifecycle.on_removed` bude seznam posluchačů, zatím jen jeden: GUI zavře okna nad odstraněnou budovou.

**Ověření:** unit test tabulky `view` → `can` pro každý stav a test, že remote i GUI jdou přes `actions`.
Dosavadní integrační testy remote zůstanou zelené.

### Task 4: Okno – kostra, editor, otevírání a zavírání

**Soubory:** nový `Pythonator/scripts/gui/{window.lua,editor.lua,events.lua}`, `Pythonator/prototypes/gui.lua`
(font `pyntr-mono` a styly), `data.lua`, `control.lua`, locale, `tests/unit/fake_gui.lua`,
`tests/unit/test_gui_window.lua`, `tests/unit/test_gui_names.lua`.

**Rozhraní:**
- `window.open(player, ctl)`, `window.close(player)`, `window.get(player) → refs | nil`
- `storage.gui[player_index] = {unit, refs}`, kde `refs` jsou odkazy na prvky (LuaGuiElement se dá uložit do `storage`).
- `editor.build(parent) → {box, gutter, scroll}`, `editor.set_text(refs, text)`,
  `editor.line_numbers(refs, n_lines, error_line)`, `editor.follow(refs, old, new)` (posun za kurzorem podle spiku).

**Co:** `player.gui.screen` frame s titulkem (tažení, ✕), `player.opened = frame`, takže okno zavře E i Esc.
Editor je `text-box` bez vlastního posuvníku ve vnějším `scroll-pane`. Vedle něj je sloupec čísel řádků
(20 px na řádek, font `pyntr-mono`) a pod ním nativní `icon_selector`. Za běhu je editor `read_only`
a zobrazuje `ctl.code`. Při pauze zobrazuje `draft or code`. Konstanty `EDITOR_WIDTH`, `EDITOR_MIN_LINES` a `LINE_HEIGHT`
budou nahoře v `editor.lua` a zapíšou se do „Kde ladit hodnoty“.

**Ověření:** unit test s `fake_gui`: open, přepnutí na jinou budovu, close a znovuotevření s draftem. Test jmen
prvků proti `runtime-api.json`. Ruční kontrola: okno, čísla řádků a posun při psaní dlouhého kódu.

### Task 5: Tlačítka, stav a chyba

**Soubory:** `scripts/gui/{window.lua,events.lua}`, nový `scripts/gui/status.lua`, locale, `tests/unit/test_gui_status.lua`.

**Co:** lišta ▶ ⏸ ⟳ ⏭ ? (`sprite-button` s tooltipem), aktivní podle `actions.view().can`. Panel stavu ukazuje
barevný štítek stavu shodný s LED (`indicator.COLORS`), `tick` a cenu `used / limit` s barvou podle zaplnění.
Pruh chyby ukazuje řádek a lokalizovanou zprávu (`errors` → `{key, args}`), chybový řádek je v gutteru červený.
Chyba překladu nového kódu se zobrazí, i když starý program běží dál. Kliknutím na chybu se editor posune na řádek.
Jiné okno nad stejnou budovou se po akci obnoví.

**Ověření:** unit test: akce → volání `actions` → nové `view` → stav tlačítek a text chyby. Ruční kontrola: Play
s chybou překladu, chyba běhu, Krok při pauze.

### Task 6: Panely globálů, vstupů, výstupů a log

**Soubory:** nový `scripts/gui/panels.lua`, `scripts/gui/events.lua` (`on_nth_tick`), `control.lua`,
`tests/unit/test_gui_panels.lua`.

**Rozhraní:**
- `panels.rows_globals(G) → {{name, repr}}`: bez `"#lib"`, řazené, `repr` zkrácený na `REPR_MAX` znaků.
- `panels.rows_signals(pairs) → {{sprite, number, tooltip}}`, nejvýš `PANEL_MAX_ROWS`, zbytek jako „+N dalších“.
- `panels.refresh(refs, ctl)`: aktualizuje existující prvky na místě, nestaví je znovu.
- `events.on_refresh()` přes `on_nth_tick(GUI_REFRESH_TICKS = 10)`. Když je `storage.gui` prázdné, hned skončí.

**Co:** vstupy R a G zvlášť jako mřížka ikon s čísly, čtou se jen při otevřeném okně (`get_signals` na konektorech).
Výstupy ukazují **skutečný stav drátu** (`ctl.wires`, poslední úspěšný flush), ne `ctl.out`. Tím se uzavírá
známé omezení z plánu 2. Pod nimi je rozbalovací log `print()` (posledních 50 řádků) a stav prvků knihovny (`"#lib"`).

**Ověření:** unit test řádků (ořez, „+N“, skrytí `#lib`, výstupy po chybě = stav drátu). Ruční kontrola: hodnoty
se mění za běhu a s otevřeným oknem nad budovou se 100 signály na vstupu UPS nespadne.

### Task 7: Nápověda

**Soubory:** nový `scripts/gui/help.lua`, locale (sekce nápovědy en a cs), `tests/unit/test_gui_help.lua`.

**Co:** samostatné okno (tlačítko ?) s kartami: Základy (superloop a časování T → T+1), Signály (klíče,
`inp/red/green/out*`, hold/clear), Jazyk (co umí a co ne, odchylky od Pythonu), Knihovna (každá funkce
s jedním příkladem, tabulka sémantiky `each`), Příklady (hystereze, sekvence, recept do montovny přes signál
předmětu, PID). Tlačítko „Vložit příklad“ vloží příklad do draftu (jen při pauze). Odsazování mezerami, Tab nejde
(z výsledků spiku).

**Ověření:** test, že každý příklad nápovědy se přeloží (`compiler.compile` s falešným resolverem) a klíče
nápovědy jsou v obou locale. Ruční kontrola čitelnosti.

### Task 8: Odolnost, multiplayer a dokumentace

**Soubory:** `scripts/gui/events.lua`, `scripts/lifecycle.lua` (`on_configuration_changed`), `control.lua`,
`tests/pythonator-tests/cases/gui.lua`, `docs/development.md`, nový `docs/user-guide.md`, `changelog.txt`.

**Co:** zavření okna při odstranění budovy (Task 3 hook), `on_player_removed` a `on_player_left_game` uklidí
`storage.gui`. `on_configuration_changed` zavře všechna okna (prvky po aktualizaci nemusí sedět). Neplatný
`refs` nebo budova zavře okno. `on_gui_opened` u Pythonatoru otevře naše okno místo `player.opened = nil`.
Dokumentace bude obsahovat tabulku „Kde ladit hodnoty“ (GUI konstanty), checklist ruční kontroly GUI,
uživatelskou příručku (CZ) a changelog.

**Ověření:** integrační test bez hráče (`gui.lua`): zbourání budovy a `on_configuration_changed` s naplněným
`storage.gui` (falešný záznam s neplatnými prvky) nespadne a `storage.gui` se uklidí. Plné `run-unit.sh`,
`run-tests.sh vanilla` a `space-age`, potom tvoje ruční kontrola podle checklistu.

---

## Body napojení na Factorio API

| Vstupní bod | Parametry → výsledek | Na co pozor |
|---|---|---|
| data: `type = "font"` | `{name = "pyntr-mono", from = "default-mono", size = 14}` | ověřeno spikem, řádek 20 px |
| data: `data.raw["gui-style"].default.pyntr_*` | styly text-boxu, gutteru a štítků | jméno stylu s prefixem; `parent` je vanilla styl |
| `on_gui_opened` | `entity`, `gui_type` | nahradit stávající `opened = nil`. Nejdřív `player.opened = nil` (zavře vanilla), pak naše okno a `player.opened = frame` |
| `on_gui_closed` | `element`, `gui_type = custom` | E/Esc. Zavírat jen naše okno (porovnat s `refs.frame`) |
| `on_gui_click` / `on_gui_text_changed` | `element`, `player_index` | dispatch podle `element.tags.pyntr_action`, ne podle jména. `text_changed` přijde při každém znaku → jen draft, gutter a posun |
| `LuaGuiElement` text-box | `read_only`, `icon_selector = true`, `text`, `scroll_to_element` | Tab nefunguje. Bez vlastního posuvníku roste s textem (spike). Kurzor API nezná |
| `player.gui.screen` | `frame.auto_center = true`, `drag_target` | pozici okna si hra nepamatuje mezi otevřeními – nevadí |
| `script.on_nth_tick(n, f)` | – | registrovat vždy (i v `on_load` platí stejná registrace). Při prázdném `storage.gui` vrátit hned |
| `LuaEntity.get_signals(connector)` | `combinator_input_red/green` | jen pro otevřená okna. Nil = prázdný drát |
| `on_player_removed`, `on_player_left_game` | `player_index` | uklidit `storage.gui` |
| `on_configuration_changed` | – | zavřít okna, `storage.gui = {}`. Starý save bez `storage.gui` musí projít |
| `storage` | `storage.gui`, `ctl.draft` | `LuaGuiElement` jde uložit, před použitím `valid`. Draft nepatří do blueprint tagů |
| headless testy | bez hráče | GUI se testuje přes `fake_gui.lua` v unit testech, do integrace jde jen úklid stavu |
| knihovna: `R.charge(n)` | počet signálů | vektorové operace platí watchdogu podle velikosti vstupu, stejně jako vestavěné funkce |
