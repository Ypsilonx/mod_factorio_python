# Pythonator – plán 1: jádro jazyka (překladač + runtime)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Čistá Lua knihovna, která přeloží program v podmnožině Pythonu na Lua funkci a spustí ji s watchdogem, pojistkou paměti a Python sémantikou – bez závislosti na herním API.

**Architecture:** Pipeline `lexer → parser (AST) → checker → codegen (zdroj Lua 5.2) → load()`. Vygenerovaný chunk vrací *factory* `function(R, G, IO)`, která vytvoří instanci programu nad tabulkou globálů `G` (ta půjde do `storage`) a vstupy/výstupy `IO`. Runtime `R` implementuje typy (`list`, `tuple`, `dict`, `None`) a operace s Python sémantikou. `vm.lua` spouští `init`/`loop` s rozpočtem watchdogu a převádí chyby na `{line, key, args}` (klíč lokalizace).

**Tech Stack:** Lua 5.2 (hra) / Lua 5.3 (lokální testy), `bit32`, CPython 3.14 přes `uv` (jen generování očekávaných výstupů konformních testů).

**Spec:** `docs/superpowers/specs/2026-10-09-pythonator-design.md`

**Navazující plány (nejsou součástí tohoto):**
- Plán 2 – mod: ověřovací prototyp rizik (text-box, Tab, 2×2), budova, recept, výzkum, plánovač, I/O přes skryté konstantní kombinátory, persistence, blueprinty, integrační testy.
- Plán 3 – GUI editor, stav, krokování, nápověda.

## Global Constraints

- Interní jméno modu `Pythonator`, prefix `pyntr` / `pyntr-`; klíče chyb `pyntr-err.<klíč>`.
- Factorio 2.0, hra běží na Lua 5.2: vygenerovaný kód nesmí používat konstrukce Lua 5.3 (`//`, `&`, `|`, `~`, `<<`, `>>`, `math.type`, celočíselný podtyp). Bitové operace jen přes `bit32`.
- Testy nesmí záviset na `tostring` čísel (5.2 vs 5.3 se liší); čísla na text jen přes `R.str`.
- Žádný text pro hráče natvrdo – chyby jsou klíč + argumenty, texty v `Pythonator/locale/{en,cs}/locale.cfg` (stejná sada klíčů).
- Komentáře a docstringy česky (`---` + `@param`/`@return`).
- Watchdog výchozí 10 000 operací / tick, paměť 10 000 prvků (hodnoty předává hostitel, knihovna je jen používá).
- Signál na výstupu: ořez k nule na celé číslo, přetečení do int32.
- Klíče signálů: `"name"`, `"name@quality"`, `"type:name"`; bez prefixu jen item/fluid/virtual; rich text tag `[item=x]`, `[item=x,quality=q]`.
- `global` povinný pro přiřazení do globálu ve funkci; `def` jen na nejvyšší úrovni, hoistované; funkce nejsou hodnoty.
- Kroky „Commit“ provádět jen tehdy, když uživatel při spuštění plánu odsouhlasí commit po každé úloze; jinak změny nechat necommitnuté a na konci ohlásit, co je nachystané.

## Review Focus

1. **Uložení a obnova hodnot bez metatabulek identity** – `None` po načtení savu je jiná tabulka; vše musí rozpoznávat typ přes `getmetatable`, ne `== R.None`. Test v úloze 5 (`kopie None/list/dict bez identity`).
2. **Pořadí iterace `dict` po smazání a znovuvložení klíče** – musí odpovídat CPythonu. Test v úloze 5 + konformní případ `collections.py`.
3. **`continue` v cyklu s lokálními proměnnými / dočasnými hodnotami** – `goto` v Lua 5.2 nesmí skočit do rozsahu `local`. Test v úloze 8 (`continue po rozbalení n-tice`).
4. **Chyba za běhu hlásí řádek zdrojového Pythonu**, ne řádek vygenerované Lua, i uvnitř funkce volané z `loop()`. Test v úloze 8.
5. **Nekonečná rekurze** se zastaví watchdogem dřív než přetečení zásobníku Lua. Test v úloze 8.

## Struktura souborů

```
Pythonator/
  info.json
  locale/en/locale.cfg, locale/cs/locale.cfg     klíče chyb [pyntr-err]
  scripts/lang/
    errors.lua     tvorba a rozpoznání chyb jazyka {line, col, key, args}
    signals.lua    klíče signálů: rozklad, resolver nad prototypy, kanonický tvar, návrhy překlepů
    lexer.lua      text → tokeny (INDENT/DEDENT, rich text tagy)
    parser.lua     tokeny → AST
    checker.lua    rozsahy jmen, global/local, omezení jazyka, překlad klíčů signálů → kanonické řetězce
    runtime.lua    typy a operace s Python sémantikou, vestavěné funkce, metody, objekty signálů
    codegen.lua    AST → zdroj Lua 5.2 (watchdog, číslo řádku)
    compiler.lua   compile(source, resolver) → program | chyba
    vm.lua         instantiate / run (watchdog, převod chyb) / memory
tests/unit/        run.lua, assert.lua, fake_protos.lua, test_*.lua
tests/conformance/ harness.py, cases/*.py, cases/*.out
tools/             run-unit.sh, gen-conformance.sh
```

Moduly se načítají `require("scripts.lang.<x>")` (funguje ve hře i v testech přes `package.path`).

### Rozhraní AST (sdílené úlohami 3, 4, 7, 8)

Každý uzel má `k` (druh), `line`, `col`.

- Modul: `{k="Module", body={stmt…}}`
- Příkazy: `Assign{targets={expr…}, value}`, `AugAssign{target, op, value}` (`op` bez `=`, např. `"+"`), `Expr{value}`, `If{test, body, orelse}`, `While{test, body}`, `For{target, iter, body}`, `Def{name, params={jméno…}, body}`, `Return{value|nil}`, `Global{names}`, `Pass`, `Break`, `Continue`.
- Výrazy: `Name{id}`, `Num{v}`, `Str{v}`, `Bool{v}`, `None`, `Signal{stype, name, quality}` (stype = typ z tagu po mapování, např. `"virtual"`), `BinOp{op, left, right}`, `UnaryOp{op, operand}` (`"-" "+" "~" "not"`), `BoolOp{op="and"|"or", values}`, `Compare{left, ops, comparators}` (`"<" "<=" ">" ">=" "==" "!=" "in" "not in" "is" "is not"`), `IfExp{test, body, orelse}`, `Call{func=jméno, args, kwargs={{name, value}…}}`, `Method{obj, name, args}`, `Subscript{value, index}`, `Slice{value, lower|nil, upper|nil}`, `List{elts}`, `Tuple{elts}`, `Dict{keys, values}`.

### Rozhraní chyb

`{pyntr_error=true, line=int|nil, col=int|nil, key="pyntr-err.<klíč>", args={string…}}`

---

### Task 0: Kostra repozitáře, testovací runner, chyby, lokalizace

**Files:**
- Create: `.gitignore`, `.gitattributes`, `.luacheckrc`, `.vscode/tasks.json`, `.vscode/extensions.json` (ze šablon skillu `factorio-mod/templates`, krok 1)
- Create: `Pythonator/info.json`, `Pythonator/locale/en/locale.cfg`, `Pythonator/locale/cs/locale.cfg`
- Create: `Pythonator/scripts/lang/errors.lua`
- Create: `tools/run-unit.sh`, `tests/unit/run.lua`, `tests/unit/assert.lua`, `tests/unit/test_locale.lua`, `tests/unit/test_errors.lua`

**Interfaces:**
- Produces: `errors.make(line, col, key, ...) → table`, `errors.raise(line, col, key, ...)` (vyhodí), `errors.is(v) → boolean`; aserce `A.eq`, `A.truthy`, `A.same` (hluboké porovnání), `A.raises(fn, key) → err`, `A.show(v) → string`.

- [ ] **Step 1: Zkopírovat šablony**

```bash
T="C:/Users/cibul/.claude/skills/factorio-mod/templates"
cd D:/61_Programing/mod_factorio_python
cp "$T/.gitignore" "$T/.gitattributes" "$T/.luacheckrc" .
mkdir -p .vscode tools tests/unit
cp "$T/vscode/tasks.json" "$T/vscode/extensions.json" .vscode/
cp "$T/tools/run-unit.sh" tools/
cp "$T/tests/unit/test_locale.lua" tests/unit/
sed -i 's/__MOD_NAME__/Pythonator/g' tests/unit/test_locale.lua
printf '\n# Konformní výstupy generuje CPython na Windows (CRLF) – drž LF\n*.out text eol=lf\n*.py text eol=lf\n' >> .gitattributes
printf '\n# Lokální cesta FMTK\n.vscode/settings.json\n' >> .gitignore
```

- [ ] **Step 2: `Pythonator/info.json`**

```json
{
  "name": "Pythonator",
  "version": "0.1.0",
  "title": "Pythonator",
  "author": "Ypsilonx",
  "factorio_version": "2.0",
  "description": "Programmable circuit controller scripted in a Python subset. Deterministic timing: read inputs, run loop(), write outputs – every tick.",
  "dependencies": ["base >= 2.0.0"]
}
```

- [ ] **Step 3: Runner a aserce**

`tests/unit/run.lua`:
```lua
---@diagnostic disable: undefined-global
--- Runner jednotkových testů (spouští se z kořene repozitáře: lua tests/unit/run.lua).
package.path = "Pythonator/?.lua;tests/unit/?.lua;" .. package.path

--- Seznam testovacích sad; každá vrací pole { "název", funkce }.
local SUITES = { "test_locale", "test_errors" }

local pass, fail = 0, 0
for _, suite in ipairs(SUITES) do
  for _, case in ipairs(require(suite)) do
    local ok, err = pcall(case[2])
    if ok then
      pass = pass + 1
    else
      fail = fail + 1
      if type(err) == "table" then err = (err.key or "?") .. " " .. table.concat(err.args or {}, ", ") end
      print("FAIL " .. suite .. " :: " .. case[1] .. ": " .. tostring(err))
    end
  end
end
print(string.format("UNIT pass=%d fail=%d", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

`tests/unit/assert.lua`:
```lua
--- Pomocné aserce pro jednotkové testy mimo hru.
local A = {}

--- Převod hodnoty na text pro hlášku (tabulky rekurzivně, klíče seřazené).
local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(v[k]) end
  return "{" .. table.concat(parts, ", ") .. "}"
end
A.show = show

--- Selže, pokud se hodnoty nerovnají.
--- @param actual any
--- @param expected any
--- @param what string popis kontrolované hodnoty
function A.eq(actual, expected, what)
  if actual ~= expected then
    error(string.format("%s: čekáno %s, dostáno %s", what, show(expected), show(actual)), 2)
  end
end

--- Selže, pokud hodnota není pravdivá.
function A.truthy(value, what)
  if not value then error(what .. ": čekána pravdivá hodnota", 2) end
end

--- Hluboké porovnání tabulek (metatabulky se ignorují).
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

--- Selže, pokud se tabulky hluboce liší.
function A.same(actual, expected, what)
  if not same(actual, expected) then
    error(string.format("%s: čekáno %s, dostáno %s", what, show(expected), show(actual)), 2)
  end
end

--- Ověří, že fn vyhodí chybu jazyka s daným klíčem (bez prefixu), a vrátí ji.
--- @param fn function
--- @param key string např. "bad-indent"
--- @return table err
function A.raises(fn, key)
  local ok, err = pcall(fn)
  if ok then error("čekána chyba " .. key .. ", nic nevyhozeno", 2) end
  if type(err) ~= "table" or err.key ~= "pyntr-err." .. key then
    error("čekána chyba " .. key .. ", dostáno " .. show(err), 2)
  end
  return err
end

return A
```

- [ ] **Step 4: Napsat padající test chyb**

`tests/unit/test_errors.lua`:
```lua
local A = require("assert")
local errors = require("scripts.lang.errors")

return {
  { "make sestaví chybu s prefixem klíče", function()
    local e = errors.make(3, 7, "bad-indent", "x")
    A.same(e, { pyntr_error = true, line = 3, col = 7, key = "pyntr-err.bad-indent", args = { "x" } }, "chyba")
  end },
  { "raise vyhodí tabulku", function()
    local e = A.raises(function() errors.raise(1, 2, "bad-char", "$") end, "bad-char")
    A.eq(e.args[1], "$", "argument")
  end },
  { "is rozliší chybu jazyka", function()
    A.eq(errors.is(errors.make(1, 1, "x")), true, "chyba")
    A.eq(errors.is("text"), false, "řetězec")
    A.eq(errors.is({}), false, "tabulka")
  end },
  { "argumenty se převedou na text", function()
    A.eq(errors.make(nil, nil, "x", 5).args[1], "5", "číslo")
  end },
}
```

- [ ] **Step 5: Spustit – musí selhat**

Run: `bash tools/run-unit.sh`
Expected: FAIL (`module 'scripts.lang.errors' not found`; test_locale selže na chybějícím locale).

- [ ] **Step 6: Implementace `errors.lua`**

`Pythonator/scripts/lang/errors.lua`:
```lua
--- Chyby jazyka Pythonator: tabulka {line, col, key, args}, kterou hostitel zobrazí lokalizovaně.
local M = {}

--- Sestaví chybu jazyka.
--- @param line integer|nil řádek zdroje (nil = doplní VM)
--- @param col integer|nil sloupec zdroje
--- @param key string klíč bez prefixu, např. "bad-indent"
--- @param ... any argumenty hlášky (převedou se na text)
--- @return table
function M.make(line, col, key, ...)
  local args = { ... }
  for i = 1, select("#", ...) do args[i] = tostring(args[i]) end
  return { pyntr_error = true, line = line, col = col, key = "pyntr-err." .. key, args = args }
end

--- Vyhodí chybu jazyka (bez připojené pozice Lua).
function M.raise(line, col, key, ...)
  error(M.make(line, col, key, ...), 0)
end

--- Je hodnota chyba jazyka?
--- @param v any
--- @return boolean
function M.is(v)
  return type(v) == "table" and v.pyntr_error == true
end

return M
```

- [ ] **Step 7: Lokalizace – kompletní sada klíčů pro celý plán**

`Pythonator/locale/en/locale.cfg`:
```ini
[mod-name]
Pythonator=Pythonator

[mod-description]
Pythonator=Programmable circuit controller scripted in a Python subset.

[pyntr-err]
bad-char=Invalid character __1__.
bad-indent=Indentation does not match any enclosing block.
unterminated-string=Unterminated string.
bad-number=Invalid number __1__.
unsupported=__1__ is not supported.
unexpected-token=Unexpected __1__.
unexpected-newline=Unexpected end of line.
unexpected-indent=Unexpected indentation.
unexpected-eof=Unexpected end of program.
expected-indent=Expected an indented block.
not-callable=Only named functions can be called.
attribute-unsupported=Attributes are not supported, only method calls (x.method()).
kwargs-unsupported=Keyword arguments are only allowed in config().
defaults-unsupported=Default parameter values are not supported.
bad-target=Cannot assign to this expression.
missing-loop=The program must define a function loop().
loop-params=loop() must not take parameters.
nested-def=Functions can only be defined at the top level.
duplicate-def=Function __1__ is defined twice.
unknown-name=Unknown name __1__.
function-value=Function __1__ can only be called, not used as a value.
missing-global=__1__ is a global variable – add "global __1__" to the function.
reserved-name=__1__ is reserved and cannot be assigned.
bad-config=config() accepts only interval=<integer ≥ 1> and outputs="hold"|"clear", as a top-level statement.
outside-loop=__1__ outside a loop.
return-outside=return outside a function.
arg-count=__1__ expects __2__ argument(s), got __3__.
signal-value=__1__ can only be indexed, used with its methods, len() or "in".
readonly-signal=__1__ is an input and cannot be written.
unknown-signal=Unknown signal __1__ (did you mean __2__?).
unknown-signal-nosuggest=Unknown signal __1__.
ambiguous-signal=Signal __1__ is ambiguous (__2__) – use a prefix, e.g. item:__1__.
unknown-quality=Unknown quality __1__.
bad-signal-key=Signal key must be a string, got __1__.
type-error=Unsupported operand types for __1__: __2__ and __3__.
type-error-unary=Unsupported operand type for __1__: __2__.
zero-division=Division by zero.
index-error=Index out of range.
bad-index-type=Index must be an integer, got __1__.
key-error=Key not found: __1__.
bad-dict-key=Dictionary keys must be str, int, float or bool, got __1__.
immutable=__1__ cannot be modified.
not-iterable=__1__ is not iterable.
empty-sequence=__1__() of an empty sequence.
not-in-list=Value is not in the list.
bad-int=Cannot convert __1__ to int.
bad-float=Cannot convert __1__ to float.
unpack-count=Expected __1__ values to unpack, got __2__.
range-step-zero=range() step must not be zero.
pop-empty=pop from an empty __1__.
negative-shift=Negative shift count.
unbound=Variable used before assignment.
unknown-method=__2__ has no method __1__.
watchdog=Watchdog: more than __1__ operations in one tick (endless loop?).
memory=Memory limit: global variables hold more than __2__ elements (largest: __1__).
internal=Internal error: __1__
```

`Pythonator/locale/cs/locale.cfg`:
```ini
[mod-name]
Pythonator=Pythonator

[mod-description]
Pythonator=Programovatelný obvodový kontrolér skriptovaný v podmnožině Pythonu.

[pyntr-err]
bad-char=Neplatný znak __1__.
bad-indent=Odsazení neodpovídá žádnému nadřazenému bloku.
unterminated-string=Neukončený řetězec.
bad-number=Neplatné číslo __1__.
unsupported=__1__ není podporováno.
unexpected-token=Nečekané __1__.
unexpected-newline=Nečekaný konec řádku.
unexpected-indent=Nečekané odsazení.
unexpected-eof=Nečekaný konec programu.
expected-indent=Očekáván odsazený blok.
not-callable=Volat lze jen pojmenované funkce.
attribute-unsupported=Atributy nejsou podporované, jen volání metod (x.metoda()).
kwargs-unsupported=Pojmenované argumenty jsou povolené jen v config().
defaults-unsupported=Výchozí hodnoty parametrů nejsou podporované.
bad-target=Do tohoto výrazu nelze přiřadit.
missing-loop=Program musí definovat funkci loop().
loop-params=loop() nesmí mít parametry.
nested-def=Funkce lze definovat jen na nejvyšší úrovni.
duplicate-def=Funkce __1__ je definovaná dvakrát.
unknown-name=Neznámé jméno __1__.
function-value=Funkci __1__ lze jen volat, ne použít jako hodnotu.
missing-global=__1__ je globální proměnná – přidej do funkce „global __1__“.
reserved-name=__1__ je vyhrazené jméno a nelze do něj přiřadit.
bad-config=config() přijímá jen interval=<celé číslo ≥ 1> a outputs="hold"|"clear", jako příkaz na nejvyšší úrovni.
outside-loop=__1__ mimo cyklus.
return-outside=return mimo funkci.
arg-count=__1__ očekává __2__ argument(ů), dostala __3__.
signal-value=__1__ lze jen indexovat, volat jeho metody, len() nebo „in“.
readonly-signal=__1__ je vstup a nelze do něj zapisovat.
unknown-signal=Neznámý signál __1__ (myslel jsi __2__?).
unknown-signal-nosuggest=Neznámý signál __1__.
ambiguous-signal=Signál __1__ není jednoznačný (__2__) – použij prefix, např. item:__1__.
unknown-quality=Neznámá kvalita __1__.
bad-signal-key=Klíč signálu musí být řetězec, dostáno __1__.
type-error=Nepodporované typy pro __1__: __2__ a __3__.
type-error-unary=Nepodporovaný typ pro __1__: __2__.
zero-division=Dělení nulou.
index-error=Index mimo rozsah.
bad-index-type=Index musí být celé číslo, dostáno __1__.
key-error=Klíč nenalezen: __1__.
bad-dict-key=Klíčem slovníku může být str, int, float nebo bool, dostáno __1__.
immutable=__1__ nelze měnit.
not-iterable=__1__ nelze procházet.
empty-sequence=__1__() z prázdné posloupnosti.
not-in-list=Hodnota není v seznamu.
bad-int=Nelze převést __1__ na int.
bad-float=Nelze převést __1__ na float.
unpack-count=Čekáno __1__ hodnot k rozbalení, dostáno __2__.
range-step-zero=Krok range() nesmí být nula.
pop-empty=pop z prázdného __1__.
negative-shift=Záporný posun.
unbound=Proměnná použita před přiřazením.
unknown-method=__2__ nemá metodu __1__.
watchdog=Watchdog: víc než __1__ operací v jednom ticku (nekonečná smyčka?).
memory=Limit paměti: globální proměnné drží víc než __2__ prvků (největší: __1__).
internal=Vnitřní chyba: __1__
```

- [ ] **Step 8: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=5 fail=0`

- [ ] **Step 9: Commit**

```bash
git add .gitignore .gitattributes .luacheckrc .vscode/tasks.json .vscode/extensions.json Pythonator tools tests
git commit -m "Kostra modu Pythonator: runner testů, chyby jazyka, lokalizace"
```

---

### Task 1: Klíče signálů (`signals.lua`)

**Files:**
- Create: `Pythonator/scripts/lang/signals.lua`
- Create: `tests/unit/fake_protos.lua`, `tests/unit/test_signals.lua`
- Modify: `tests/unit/run.lua` (přidat `"test_signals"` do `SUITES`)

**Interfaces:**
- Consumes: `errors.make`
- Produces:
  - `signals.split(key) → stype|nil, name, quality`
  - `signals.from_tag(tag_type, name, quality) → string` (textový klíč z rich text tagu)
  - `signals.TAG_TYPES` (tabulka typ tagu → typ SignalID)
  - `signals.new_resolver(protos) → resolver`; `protos` = `{item={jméno=true}, fluid=…, virtual=…, recipe=…, entity=…, ["space-location"]=…, ["asteroid-chunk"]=…, quality=…}`
  - `resolver:resolve(key) → sid, canonical` nebo `nil, nil, err` (err z `errors.make` bez pozice)
  - `resolver:canonical(sid) → string`

- [ ] **Step 1: Falešné prototypy pro testy**

`tests/unit/fake_protos.lua`:
```lua
--- Malá sada jmen prototypů pro testy (místo prototypes.* ve hře). "water" je schválně item i fluid.
return function()
  return {
    item = { ["iron-plate"] = true, ["copper-plate"] = true, ["iron-gear-wheel"] = true,
             ["assembling-machine-1"] = true, water = true, coal = true, ["iron-ore"] = true },
    fluid = { water = true, ["crude-oil"] = true, ["petroleum-gas"] = true },
    virtual = { ["signal-A"] = true, ["signal-B"] = true, ["signal-I"] = true, ["signal-P"] = true,
                ["signal-S"] = true, ["signal-U"] = true },
    recipe = { ["iron-plate"] = true, ["iron-gear-wheel"] = true },
    entity = { ["assembling-machine-1"] = true },
    ["space-location"] = { nauvis = true },
    ["asteroid-chunk"] = {},
    quality = { normal = true, uncommon = true, rare = true, epic = true, legendary = true },
  }
end
```

- [ ] **Step 2: Padající testy**

`tests/unit/test_signals.lua`:
```lua
local A = require("assert")
local signals = require("scripts.lang.signals")
local fake = require("fake_protos")

--- Ověří úspěšné rozlišení klíče.
local function ok(key, stype, name, quality, canonical)
  local r = signals.new_resolver(fake())
  local sid, c, err = r:resolve(key)
  A.eq(err, nil, key .. " chyba")
  A.same(sid, { type = stype, name = name, quality = quality }, key .. " sid")
  A.eq(c, canonical, key .. " kanonický")
end

--- Ověří chybu rozlišení klíče a vrátí ji.
local function bad(key, errkey)
  local _, _, err = signals.new_resolver(fake()):resolve(key)
  A.truthy(err, key .. " čekána chyba")
  A.eq(err.key, "pyntr-err." .. errkey, key .. " klíč chyby")
  return err
end

return {
  { "split rozloží typ, jméno, kvalitu", function()
    A.same({ signals.split("recipe:iron-plate@rare") }, { "recipe", "iron-plate", "rare" }, "plný")
    A.same({ signals.split("iron-plate") }, { nil, "iron-plate", "normal" }, "holý")
    A.same({ signals.split("foo:bar") }, { nil, "foo:bar", "normal" }, "neznámý prefix je součást jména")
  end },
  { "item bez prefixu", function() ok("iron-plate", "item", "iron-plate", "normal", "iron-plate") end },
  { "virtuální signál", function() ok("signal-A", "virtual", "signal-A", "normal", "signal-A") end },
  { "fluid", function() ok("crude-oil", "fluid", "crude-oil", "normal", "crude-oil") end },
  { "recept s prefixem", function() ok("recipe:iron-plate", "recipe", "iron-plate", "normal", "recipe:iron-plate") end },
  { "kvalita", function() ok("iron-plate@rare", "item", "iron-plate", "rare", "iron-plate@rare") end },
  { "normal se v kanonickém tvaru vynechá", function() ok("iron-plate@normal", "item", "iron-plate", "normal", "iron-plate") end },
  { "zbytečný prefix item se vynechá", function() ok("item:iron-plate", "item", "iron-plate", "normal", "iron-plate") end },
  { "nejednoznačné jméno s prefixem zůstane s prefixem", function()
    ok("item:water", "item", "water", "normal", "item:water")
    ok("fluid:water", "fluid", "water", "normal", "fluid:water")
  end },
  { "překlep nabídne návrh", function()
    A.same(bad("iron-plates", "unknown-signal").args, { "iron-plates", "iron-plate" }, "argumenty")
  end },
  { "překlep v receptu nabídne recept", function()
    A.same(bad("recipe:iron-plat", "unknown-signal").args, { "recipe:iron-plat", "recipe:iron-plate" }, "argumenty")
  end },
  { "nesmysl bez návrhu", function() bad("xyzzy-qwerty", "unknown-signal-nosuggest") end },
  { "nejednoznačné jméno", function()
    A.same(bad("water", "ambiguous-signal").args, { "water", "item, fluid" }, "argumenty")
  end },
  { "neznámá kvalita", function() bad("iron-plate@shiny", "unknown-quality") end },
  { "from_tag převede typ tagu", function()
    A.eq(signals.from_tag("virtual-signal", "signal-A", "normal"), "virtual:signal-A", "virtual")
    A.eq(signals.from_tag("item", "iron-plate", "rare"), "item:iron-plate@rare", "kvalita")
  end },
  { "cache vrací stejný výsledek", function()
    local r = signals.new_resolver(fake())
    local _, c1 = r:resolve("iron-plate")
    local _, c2 = r:resolve("iron-plate")
    A.eq(c1, c2, "kanonický")
  end },
}
```
Přidat `"test_signals"` do `SUITES` v `tests/unit/run.lua`.

- [ ] **Step 3: Spustit – musí selhat**

Run: `bash tools/run-unit.sh`
Expected: FAIL `module 'scripts.lang.signals' not found`

- [ ] **Step 4: Implementace**

`Pythonator/scripts/lang/signals.lua`:
```lua
--- Klíče signálů: textový zápis ↔ SignalID {type, name, quality}, ověření proti prototypům.
local errors = require("scripts.lang.errors")

local M = {}

--- Typy hledané podle jména bez prefixu (v tomto pořadí).
M.PLAIN_TYPES = { "item", "fluid", "virtual" }

--- Všechny typy SignalID ve Factoriu 2.0.
M.ALL_TYPES = { "item", "fluid", "virtual", "recipe", "entity", "space-location", "asteroid-chunk", "quality" }

--- Typ v rich text tagu → typ SignalID.
M.TAG_TYPES = {
  item = "item", fluid = "fluid", ["virtual-signal"] = "virtual", recipe = "recipe", entity = "entity",
  ["space-location"] = "space-location", ["asteroid-chunk"] = "asteroid-chunk", quality = "quality",
}

local IS_TYPE, IS_PLAIN = {}, {}
for _, t in ipairs(M.ALL_TYPES) do IS_TYPE[t] = true end
for _, t in ipairs(M.PLAIN_TYPES) do IS_PLAIN[t] = true end

--- Rozloží textový klíč na části (bez ověření existence).
--- @param key string např. "recipe:iron-plate@rare"
--- @return string|nil stype explicitní typ, nebo nil
--- @return string name
--- @return string quality ("normal", pokud chybí)
function M.split(key)
  local stype, rest = key:match("^([%w%-]+):(.+)$")
  if not (stype and IS_TYPE[stype]) then stype, rest = nil, key end
  local name, quality = rest:match("^(.+)@([%w%-_]+)$")
  if not name then name, quality = rest, "normal" end
  return stype, name, quality
end

--- Textový klíč z rich text tagu ([item=x,quality=q]); typ je vždy explicitní.
--- @param tag_type string typ v tagu, např. "virtual-signal"
--- @param name string
--- @param quality string
--- @return string
function M.from_tag(tag_type, name, quality)
  local key = M.TAG_TYPES[tag_type] .. ":" .. name
  if quality ~= "normal" then key = key .. "@" .. quality end
  return key
end

--- Levenshteinova vzdálenost dvou řetězců.
local function distance(a, b)
  local prev = {}
  for j = 0, #b do prev[j] = j end
  for i = 1, #a do
    local cur, ca = { [0] = i }, a:byte(i)
    for j = 1, #b do
      local cost = (ca == b:byte(j)) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[#b]
end

--- Nejbližší jméno z množin kandidátů, pokud je dost blízko (deterministicky při shodě).
--- @return string|nil
local function suggest(name, sets)
  local best, bestd
  for _, set in ipairs(sets) do
    for cand in pairs(set) do
      local d = distance(name, cand)
      if not bestd or d < bestd or (d == bestd and cand < best) then best, bestd = cand, d end
    end
  end
  if best and bestd <= math.max(2, math.floor(#name / 3)) then return best end
end

local Resolver = {}
Resolver.__index = Resolver

--- Vytvoří resolver nad množinami jmen prototypů.
--- @param protos table typ SignalID → množina jmen (chybějící typy = prázdné)
--- @return table
function M.new_resolver(protos)
  local p = {}
  for _, t in ipairs(M.ALL_TYPES) do p[t] = protos[t] or {} end
  return setmetatable({ protos = p, cache = {} }, Resolver)
end

--- Typy bez prefixu, ve kterých jméno existuje.
--- @return string[]
function Resolver:plain_types(name)
  local found = {}
  for _, t in ipairs(M.PLAIN_TYPES) do
    if self.protos[t][name] then found[#found + 1] = t end
  end
  return found
end

--- Kanonický textový klíč: prefix jen u typů mimo item/fluid/virtual nebo při nejednoznačnosti.
--- @param sid table {type, name, quality}
--- @return string
function Resolver:canonical(sid)
  local key = sid.name
  if not IS_PLAIN[sid.type] or #self:plain_types(sid.name) > 1 then key = sid.type .. ":" .. key end
  if sid.quality and sid.quality ~= "normal" then key = key .. "@" .. sid.quality end
  return key
end

--- Chyba neznámého signálu (s návrhem, je-li nějaký blízký).
local function unknown(key, prefix, name, sets)
  local s = suggest(name, sets)
  if s then return errors.make(nil, nil, "unknown-signal", key, prefix .. s) end
  return errors.make(nil, nil, "unknown-signal-nosuggest", key)
end

--- Ověří textový klíč a vrátí SignalID a kanonický tvar. Výsledek se cachuje (tabulku sid neměnit).
--- @param key string
--- @return table|nil sid
--- @return string|nil canonical
--- @return table|nil err
function Resolver:resolve(key)
  local hit = self.cache[key]
  if hit then return hit.sid, hit.canonical end
  local stype, name, quality = M.split(key)
  if not self.protos.quality[quality] then
    return nil, nil, errors.make(nil, nil, "unknown-quality", quality)
  end
  if stype then
    if not self.protos[stype][name] then
      return nil, nil, unknown(key, stype .. ":", name, { self.protos[stype] })
    end
  else
    local found = self:plain_types(name)
    if #found > 1 then
      return nil, nil, errors.make(nil, nil, "ambiguous-signal", name, table.concat(found, ", "))
    end
    if #found == 0 then
      return nil, nil, unknown(key, "", name, { self.protos.item, self.protos.fluid, self.protos.virtual })
    end
    stype = found[1]
  end
  local sid = { type = stype, name = name, quality = quality }
  local canonical = self:canonical(sid)
  self.cache[key] = { sid = sid, canonical = canonical }
  return sid, canonical
end

return M
```

- [ ] **Step 5: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=21 fail=0`

- [ ] **Step 6: Commit**

```bash
git add Pythonator/scripts/lang/signals.lua tests/unit
git commit -m "Klíče signálů: rozklad, resolver nad prototypy, návrhy překlepů"
```

---

### Task 2: Lexer (`lexer.lua`)

**Files:**
- Create: `Pythonator/scripts/lang/lexer.lua`
- Create: `tests/unit/test_lexer.lua`
- Modify: `tests/unit/run.lua` (přidat `"test_lexer"` do `SUITES`)

**Interfaces:**
- Consumes: `errors.raise`, `signals.TAG_TYPES`
- Produces: `lexer.tokenize(src) → token[]`, token = `{t, v, line, col}`; `t` ∈ `NAME KW NUM STR SIG OP NEWLINE INDENT DEDENT EOF`. `SIG.v = {stype, tag, name, quality}` (`stype` už namapovaný, např. `"virtual"`; `tag` původní typ v tagu, např. `"virtual-signal"`). Poslední tokeny jsou vždy `NEWLINE` (je-li nějaký obsah), `DEDENT…`, `EOF`.

Pravidla odsazení: nové odsazení musí začínat řetězcem nadřazeného (mezery/tabulátory se nemíchají), návrat musí přesně odpovídat některé úrovni na zásobníku, jinak `bad-indent`. Uvnitř závorek `([{` se konce řádků ignorují. Řádek zakončený `\` pokračuje. `;` je nepodporovaný.

- [ ] **Step 1: Padající testy**

`tests/unit/test_lexer.lua`:
```lua
local A = require("assert")
local lexer = require("scripts.lang.lexer")

--- Kompaktní zápis tokenů "TYP:hodnota" (hodnoty SIG/STR/NUM se kontrolují zvlášť).
local function dump(src)
  local out = {}
  for _, t in ipairs(lexer.tokenize(src)) do
    if t.t == "NAME" or t.t == "KW" or t.t == "OP" then out[#out + 1] = t.t .. ":" .. t.v
    else out[#out + 1] = t.t end
  end
  return table.concat(out, " ")
end

--- Vrátí tokeny daného typu.
local function only(src, kind)
  local out = {}
  for _, t in ipairs(lexer.tokenize(src)) do if t.t == kind then out[#out + 1] = t end end
  return out
end

return {
  { "přiřazení", function()
    A.eq(dump("x = 1\n"), "NAME:x OP:= NUM NEWLINE EOF", "tokeny")
  end },
  { "bez koncového konce řádku", function()
    A.eq(dump("x = 1"), "NAME:x OP:= NUM NEWLINE EOF", "tokeny")
  end },
  { "odsazení a návrat", function()
    A.eq(dump("if a:\n    b\nc\n"),
      "KW:if NAME:a OP:: NEWLINE INDENT NAME:b NEWLINE DEDENT NAME:c NEWLINE EOF", "tokeny")
  end },
  { "prázdné řádky a komentáře se ignorují", function()
    A.eq(dump("a\n\n   # k\n# z\nb  # c\n"), "NAME:a NEWLINE NAME:b NEWLINE EOF", "tokeny")
  end },
  { "DEDENT na konci souboru", function()
    A.eq(dump("def f():\n  x\n"), "KW:def NAME:f OP:( OP:) OP:: NEWLINE INDENT NAME:x NEWLINE DEDENT EOF", "tokeny")
  end },
  { "vícenásobný návrat", function()
    A.eq(dump("if a:\n if b:\n  c\nd"),
      "KW:if NAME:a OP:: NEWLINE INDENT KW:if NAME:b OP:: NEWLINE INDENT NAME:c NEWLINE DEDENT DEDENT NAME:d NEWLINE EOF",
      "tokeny")
  end },
  { "návrat mimo úroveň = bad-indent", function()
    local e = A.raises(function() lexer.tokenize("if a:\n    b\n  c\n") end, "bad-indent")
    A.eq(e.line, 3, "řádek")
  end },
  { "míchání tabulátoru a mezer = bad-indent", function()
    A.raises(function() lexer.tokenize("if a:\n\tb\n    c\n") end, "bad-indent")
  end },
  { "tabulátor jako odsazení", function()
    A.eq(dump("if a:\n\tb\n"), "KW:if NAME:a OP:: NEWLINE INDENT NAME:b NEWLINE DEDENT EOF", "tokeny")
  end },
  { "závorky spojují řádky", function()
    A.eq(dump("x = [1,\n   2]\n"), "NAME:x OP:= OP:[ NUM OP:, NUM OP:] NEWLINE EOF", "tokeny")
  end },
  { "zpětné lomítko spojuje řádky", function()
    A.eq(dump("x = 1 + \\\n 2"), "NAME:x OP:= NUM OP:+ NUM NEWLINE EOF", "tokeny")
  end },
  { "nejdelší operátor", function()
    A.eq(dump("a **= b // c != d"), "NAME:a OP:**= NAME:b OP:// NAME:c OP:!= NAME:d NEWLINE EOF", "tokeny")
  end },
  { "řetězce a escape", function()
    local s = only([[s = "a\tb" + 'c\'d']], "STR")
    A.eq(s[1].v, "a\tb", "první")
    A.eq(s[2].v, "c'd", "druhý")
  end },
  { "trojité uvozovky přes řádky", function()
    local toks = lexer.tokenize('x = """a\nb"""\ny')
    A.eq(toks[3].v, "a\nb", "obsah")
    A.eq(toks[5].v, "y", "další jméno")
    A.eq(toks[5].line, 3, "řádek dalšího jména")
  end },
  { "neukončený řetězec", function()
    local e = A.raises(function() lexer.tokenize('x = "abc\n') end, "unterminated-string")
    A.eq(e.line, 1, "řádek")
    A.eq(e.col, 5, "sloupec")
  end },
  { "čísla", function()
    local n = only("0x1F 1_000 2.5 1e3 .5", "NUM")
    A.eq(n[1].v, 31, "hex")
    A.eq(n[2].v, 1000, "podtržítka")
    A.eq(n[3].v, 2.5, "desetinné")
    A.eq(n[4].v, 1000, "exponent")
    A.eq(n[5].v, 0.5, "začíná tečkou")
  end },
  { "špatné číslo", function()
    A.raises(function() lexer.tokenize("12abc") end, "bad-number")
  end },
  { "klíčová slova a jména", function()
    A.eq(dump("if iffy not"), "KW:if NAME:iffy KW:not NEWLINE EOF", "tokeny")
  end },
  { "nepodporované klíčové slovo", function()
    local e = A.raises(function() lexer.tokenize("import os") end, "unsupported")
    A.eq(e.args[1], "import", "slovo")
  end },
  { "f-string nepodporovaný", function()
    A.raises(function() lexer.tokenize('x = f"a{b}"') end, "unsupported")
  end },
  { "středník nepodporovaný", function()
    A.raises(function() lexer.tokenize("a = 1; b = 2") end, "unsupported")
  end },
  { "rich text tag uvnitř indexu", function()
    A.eq(dump("inp[[item=iron-plate]]"), "NAME:inp OP:[ SIG OP:] NEWLINE EOF", "tokeny")
    A.same(only("inp[[item=iron-plate]]", "SIG")[1].v,
      { stype = "item", tag = "item", name = "iron-plate", quality = "normal" }, "hodnota")
  end },
  { "tag virtuálního signálu a kvalita", function()
    local s = only("[virtual-signal=signal-A] [item=iron-plate,quality=rare]", "SIG")
    A.same(s[1].v, { stype = "virtual", tag = "virtual-signal", name = "signal-A", quality = "normal" }, "virtual")
    A.same(s[2].v, { stype = "item", tag = "item", name = "iron-plate", quality = "rare" }, "kvalita")
  end },
  { "seznam s porovnáním není tag", function()
    A.eq(dump("[a==b]"), "OP:[ NAME:a OP:== NAME:b OP:] NEWLINE EOF", "tokeny")
  end },
  { "pozice tokenů", function()
    local toks = lexer.tokenize("x = 1\n  # c\ny = 2")
    A.eq(toks[3].col, 5, "sloupec čísla")
    A.eq(toks[5].v, "y", "jméno y")
    A.eq(toks[5].line, 3, "řádek y")
    A.eq(toks[5].col, 1, "sloupec y")
  end },
  { "neplatný znak", function()
    local e = A.raises(function() lexer.tokenize("x = $") end, "bad-char")
    A.eq(e.args[1], "$", "znak")
    A.eq(e.col, 5, "sloupec")
  end },
  { "CRLF konce řádků", function()
    A.eq(dump("a\r\nb\r\n"), "NAME:a NEWLINE NAME:b NEWLINE EOF", "tokeny")
  end },
}
```
Přidat `"test_lexer"` do `SUITES`.

- [ ] **Step 2: Spustit – musí selhat**

Run: `bash tools/run-unit.sh`
Expected: FAIL `module 'scripts.lang.lexer' not found`

- [ ] **Step 3: Implementace**

`Pythonator/scripts/lang/lexer.lua`:
```lua
--- Lexer: zdrojový text → tokeny včetně INDENT/DEDENT a rich text tagů signálů.
local errors = require("scripts.lang.errors")
local signals = require("scripts.lang.signals")

local M = {}

--- Množina slov z řetězce odděleného mezerami.
local function set_of(words)
  local s = {}
  for w in words:gmatch("%S+") do s[w] = true end
  return s
end

local KEYWORDS = set_of("False None True and break continue def elif else for global if in is not or pass return while")
local UNSUPPORTED = set_of("class import from try except finally lambda with yield nonlocal del raise assert async await as")
local OPS3 = set_of("**= //= >>= <<=")
local OPS2 = set_of("** // == != <= >= << >> += -= *= /= %= &= |= ^=")
local OPS1 = {}
for c in ("+-*/%<>=()[]{},:.~&|^;"):gmatch(".") do OPS1[c] = true end
local OPEN = set_of("( [ {")
local CLOSE = set_of(") ] }")
local ESCAPES = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ["'"] = "'", ['"'] = '"', ["0"] = "\0" }

--- Rozdělí zdroj na tokeny {t, v, line, col}.
--- @param src string
--- @return table[]
function M.tokenize(src)
  src = src:gsub("\r\n", "\n"):gsub("\r", "\n")
  local toks, indents = {}, { "" }
  local pos, n, line, lstart, depth, bol = 1, #src, 1, 1, 0, true

  --- Přidá token (řádek implicitně aktuální).
  local function push(t, v, col, ln)
    toks[#toks + 1] = { t = t, v = v, line = ln or line, col = col }
  end

  --- Zpracuje odsazení na začátku logického řádku.
  local function indentation()
    local s, e = src:find("^[ \t]*", pos)
    local ind = src:sub(s, e)
    local c = src:sub(e + 1, e + 1)
    pos = e + 1
    if depth > 0 or c == "\n" or c == "#" or c == "" then return end
    local top = indents[#indents]
    if #ind > #top then
      if ind:sub(1, #top) ~= top then errors.raise(line, 1, "bad-indent") end
      indents[#indents + 1] = ind
      push("INDENT", nil, 1)
      return
    end
    while indents[#indents] ~= ind do
      if #indents == 1 or #indents[#indents] <= #ind then errors.raise(line, 1, "bad-indent") end
      indents[#indents] = nil
      push("DEDENT", nil, 1)
    end
  end

  --- Přečte řetězec v uvozovkách q (i trojitých) od pozice pos.
  local function string_literal(q, col)
    local startline = line
    local triple = src:sub(pos, pos + 2) == q:rep(3)
    local i = pos + (triple and 3 or 1)
    local buf = {}
    while true do
      local ch = src:sub(i, i)
      if ch == "" or (ch == "\n" and not triple) then errors.raise(startline, col, "unterminated-string") end
      if triple and src:sub(i, i + 2) == q:rep(3) then i = i + 3; break end
      if not triple and ch == q then i = i + 1; break end
      if ch == "\\" then
        local nx = src:sub(i + 1, i + 1)
        if nx == "\n" then
          line = line + 1; lstart = i + 2
        else
          buf[#buf + 1] = ESCAPES[nx] or ("\\" .. nx)
        end
        i = i + 2
      else
        if ch == "\n" then line = line + 1; lstart = i + 1 end
        buf[#buf + 1] = ch
        i = i + 1
      end
    end
    push("STR", table.concat(buf), col, startline)
    pos = i
  end

  --- Přečte číslo (desítkové, hex, exponent, podtržítka).
  local function number(col)
    local s = src:match("^0[xX]%x+", pos)
    local v
    if s then
      v = tonumber(s:sub(3), 16)
    else
      s = src:match("^%d[%d_]*%.?[%d_]*", pos) or src:match("^%.%d[%d_]*", pos)
      local ex = src:match("^[eE][%+%-]?%d+", pos + #s)
      if ex then s = s .. ex end
      v = tonumber((s:gsub("_", "")))
    end
    local after = src:sub(pos + #s, pos + #s)
    if not v or after:match("[%w_]") then errors.raise(line, col, "bad-number", s .. after) end
    push("NUM", v, col)
    pos = pos + #s
  end

  --- Přečte jméno nebo klíčové slovo.
  local function word(col)
    local w = src:match("^[%a_][%w_]*", pos)
    local nxt = src:sub(pos + #w, pos + #w)
    if (nxt == '"' or nxt == "'") and #w <= 2 and w:match("^[fFrRbBuU]+$") then
      errors.raise(line, col, "unsupported", w .. nxt .. "…" .. nxt)
    end
    if UNSUPPORTED[w] then errors.raise(line, col, "unsupported", w) end
    push(KEYWORDS[w] and "KW" or "NAME", w, col)
    pos = pos + #w
  end

  --- Zkusí přečíst rich text tag signálu; vrátí true při úspěchu.
  local function tag(col)
    local tt, nm, q = src:match("^%[([%w%-]+)=([%w%-_]+),quality=([%w%-_]+)%]", pos)
    local whole
    if tt then
      whole = "[" .. tt .. "=" .. nm .. ",quality=" .. q .. "]"
    else
      tt, nm = src:match("^%[([%w%-]+)=([%w%-_]+)%]", pos)
      q = "normal"
      if tt then whole = "[" .. tt .. "=" .. nm .. "]" end
    end
    if not (tt and signals.TAG_TYPES[tt]) then return false end
    push("SIG", { stype = signals.TAG_TYPES[tt], tag = tt, name = nm, quality = q }, col)
    pos = pos + #whole
    return true
  end

  --- Přečte operátor (nejdelší shoda).
  local function operator(c, col)
    local three, two = src:sub(pos, pos + 2), src:sub(pos, pos + 1)
    local op = (OPS3[three] and three) or (OPS2[two] and two) or (OPS1[c] and c)
    if not op then errors.raise(line, col, "bad-char", c) end
    if op == ";" then errors.raise(line, col, "unsupported", ";") end
    if OPEN[op] then depth = depth + 1 elseif CLOSE[op] and depth > 0 then depth = depth - 1 end
    push("OP", op, col)
    pos = pos + #op
  end

  while pos <= n do
    if bol then
      bol = false
      indentation()
    else
      local c = src:sub(pos, pos)
      local col = pos - lstart + 1
      if c == "\n" then
        if depth == 0 and #toks > 0 and toks[#toks].t ~= "NEWLINE" then push("NEWLINE", nil, col) end
        pos = pos + 1; line = line + 1; lstart = pos; bol = true
      elseif c == " " or c == "\t" then
        pos = pos + 1
      elseif c == "#" then
        pos = src:find("\n", pos, true) or n + 1
      elseif c == "\\" and src:sub(pos + 1, pos + 1) == "\n" then
        pos = pos + 2; line = line + 1; lstart = pos
      elseif c == '"' or c == "'" then
        string_literal(c, col)
      elseif c:match("%d") or (c == "." and src:sub(pos + 1, pos + 1):match("%d")) then
        number(col)
      elseif c:match("[%a_]") then
        word(col)
      elseif not (c == "[" and tag(col)) then
        operator(c, col)
      end
    end
  end
  if #toks > 0 and toks[#toks].t ~= "NEWLINE" then push("NEWLINE", nil, pos - lstart + 1) end
  for _ = 2, #indents do push("DEDENT", nil, 1) end
  push("EOF", nil, 1)
  return toks
end

return M
```

- [ ] **Step 4: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=48 fail=0`

- [ ] **Step 5: Commit**

```bash
git add Pythonator/scripts/lang/lexer.lua tests/unit
git commit -m "Lexer: odsazení, řetězce, čísla, rich text tagy signálů"
```

---

### Task 3: Parser – výrazy

**Files:**
- Create: `Pythonator/scripts/lang/parser.lua` (výrazová část + `parse_expression`)
- Create: `tests/unit/ast_dump.lua` (textový výpis AST pro testy – výrazy i příkazy, příkazy využije úloha 4)
- Create: `tests/unit/test_parser_expr.lua`
- Modify: `tests/unit/run.lua` (přidat `"test_parser_expr"`)

**Interfaces:**
- Consumes: `lexer.tokenize`, `errors.raise`
- Produces: `parser.parse_expression(src) → expr` (jen pro testy); interní `P:expr()`, `P:expr_list()`, `P:atom()` pro úlohu 4; tvar uzlů dle „Rozhraní AST“ výše. `Signal` uzel nese navíc `tag` (původní typ v tagu). `ast_dump.expr(e) → string`, `ast_dump.stmts(list) → string`.

Priority (od nejnižší): `x if c else y` → `or` → `and` → `not` → porovnání (řetězí se) → `|` → `^` → `&` → `<< >>` → `+ -` → `* / // %` → unární `- + ~` → `**` (zprava, `-2**2 = -(2**2)`) → postfix (volání, index, řez, `.metoda()`) → atom.

- [ ] **Step 1: Výpis AST pro testy**

`tests/unit/ast_dump.lua`:
```lua
--- Kompaktní textový výpis AST (S-výrazy) pro čitelné aserce v testech.
local D = {}

--- Spojí výpisy seznamu uzlů oddělovačem.
local function join(list, f, sep)
  local out = {}
  for i, v in ipairs(list) do out[i] = f(v) end
  return table.concat(out, sep or " ")
end

--- Číslo bez závislosti na tostring Lua 5.2/5.3.
local function num(v)
  if v == math.floor(v) then return string.format("%d", v) end
  return string.format("%.17g", v)
end

--- Výpis výrazu.
function D.expr(e)
  local k = e.k
  if k == "Name" then return e.id end
  if k == "Num" then return num(e.v) end
  if k == "Str" then return '"' .. e.v .. '"' end
  if k == "Bool" then return e.v and "True" or "False" end
  if k == "None" then return "None" end
  if k == "Signal" then return "<" .. e.stype .. ":" .. e.name .. "@" .. e.quality .. ">" end
  if k == "BinOp" then return "(" .. e.op .. " " .. D.expr(e.left) .. " " .. D.expr(e.right) .. ")" end
  if k == "UnaryOp" then return "(" .. e.op .. " " .. D.expr(e.operand) .. ")" end
  if k == "BoolOp" then return "(" .. e.op .. " " .. join(e.values, D.expr) .. ")" end
  if k == "Compare" then
    local s = "(cmp " .. D.expr(e.left)
    for i, op in ipairs(e.ops) do s = s .. " " .. op .. " " .. D.expr(e.comparators[i]) end
    return s .. ")"
  end
  if k == "IfExp" then return "(if " .. D.expr(e.test) .. " " .. D.expr(e.body) .. " " .. D.expr(e.orelse) .. ")" end
  if k == "Call" then
    local s = "(call " .. e.func
    for _, a in ipairs(e.args) do s = s .. " " .. D.expr(a) end
    for _, kw in ipairs(e.kwargs) do s = s .. " " .. kw.name .. "=" .. D.expr(kw.value) end
    return s .. ")"
  end
  if k == "Method" then
    local s = "(." .. e.name .. " " .. D.expr(e.obj)
    for _, a in ipairs(e.args) do s = s .. " " .. D.expr(a) end
    return s .. ")"
  end
  if k == "Subscript" then return "(idx " .. D.expr(e.value) .. " " .. D.expr(e.index) .. ")" end
  if k == "Slice" then
    return "(slice " .. D.expr(e.value) .. " " .. (e.lower and D.expr(e.lower) or "_") .. " "
      .. (e.upper and D.expr(e.upper) or "_") .. ")"
  end
  if k == "List" then return "[" .. join(e.elts, D.expr) .. "]" end
  if k == "Tuple" then return #e.elts == 0 and "(tuple)" or "(tuple " .. join(e.elts, D.expr) .. ")" end
  if k == "Dict" then
    local parts = {}
    for i, key in ipairs(e.keys) do parts[i] = D.expr(key) .. ":" .. D.expr(e.values[i]) end
    return "{" .. table.concat(parts, " ") .. "}"
  end
  error("neznámý uzel " .. tostring(k))
end

--- Výpis příkazu.
function D.stmt(s)
  local k = s.k
  if k == "Assign" then return "(= " .. join(s.targets, D.expr) .. " " .. D.expr(s.value) .. ")" end
  if k == "AugAssign" then return "(" .. s.op .. "= " .. D.expr(s.target) .. " " .. D.expr(s.value) .. ")" end
  if k == "Expr" then return D.expr(s.value) end
  if k == "If" then return "(if " .. D.expr(s.test) .. " {" .. D.stmts(s.body) .. "} {" .. D.stmts(s.orelse) .. "})" end
  if k == "While" then return "(while " .. D.expr(s.test) .. " {" .. D.stmts(s.body) .. "})" end
  if k == "For" then return "(for " .. D.expr(s.target) .. " " .. D.expr(s.iter) .. " {" .. D.stmts(s.body) .. "})" end
  if k == "Def" then return "(def " .. s.name .. " (" .. table.concat(s.params, " ") .. ") {" .. D.stmts(s.body) .. "})" end
  if k == "Return" then return s.value and "(return " .. D.expr(s.value) .. ")" or "(return)" end
  if k == "Global" then return "(global " .. table.concat(s.names, " ") .. ")" end
  if k == "Pass" then return "pass" end
  if k == "Break" then return "break" end
  if k == "Continue" then return "continue" end
  error("neznámý příkaz " .. tostring(k))
end

--- Výpis seznamu příkazů oddělený "; ".
function D.stmts(list) return join(list, D.stmt, "; ") end

return D
```

- [ ] **Step 2: Padající testy**

`tests/unit/test_parser_expr.lua`:
```lua
local A = require("assert")
local parser = require("scripts.lang.parser")
local D = require("ast_dump")

--- Ověří výpis rozparsovaného výrazu.
local function px(src, expected)
  A.eq(D.expr(parser.parse_expression(src)), expected, src)
end

return {
  { "priorita + a *", function() px("1 + 2 * 3", "(+ 1 (* 2 3))") end },
  { "levá asociativita", function() px("a - b - c", "(- (- a b) c)") end },
  { "mocnina a unární minus", function()
    px("-2 ** 2", "(- (** 2 2))")
    px("2 ** -1", "(** 2 (- 1))")
    px("a ** b ** c", "(** a (** b c))")
  end },
  { "bitové operátory", function() px("a | b ^ c & d << 1", "(| a (^ b (& c (<< d 1))))") end },
  { "řetězené porovnání", function() px("0 < x <= 10", "(cmp 0 < x <= 10)") end },
  { "in, not in, is not", function()
    px("a not in b", "(cmp a not in b)")
    px("a in b", "(cmp a in b)")
    px("a is not None", "(cmp a is not None)")
    px("a is None", "(cmp a is None)")
  end },
  { "logické operátory", function() px("not a and b or c", "(or (and (not a) b) c)") end },
  { "podmíněný výraz", function() px("x if c else y", "(if c x y)") end },
  { "volání a pojmenované argumenty", function()
    px("config(interval=10)", "(call config interval=10)")
    px("max(a, b,)", "(call max a b)")
    px("f()", "(call f)")
  end },
  { "metody i řetězené", function()
    px("x.append(1)", "(.append x 1)")
    px("s.upper().lower()", "(.lower (.upper s))")
  end },
  { "index a řez", function()
    px("a[1]", "(idx a 1)")
    px("a[1:]", "(slice a 1 _)")
    px("a[:-1]", "(slice a _ (- 1))")
    px("a[:]", "(slice a _ _)")
  end },
  { "literály kolekcí", function()
    px("[1, 2,]", "[1 2]")
    px("[]", "[]")
    px("(1,)", "(tuple 1)")
    px("()", "(tuple)")
    px("(1)", "1")
    px("{'a': 1, 'b': 2}", '{"a":1 "b":2}')
    px("{}", "{}")
  end },
  { "n-tice bez závorek", function() px("a, b", "(tuple a b)") end },
  { "spojení sousedních řetězců", function() px("'a' 'b'", '"ab"') end },
  { "konstanty", function() px("[True, False, None]", "[True False None]") end },
  { "signál v indexu", function()
    px("inp[[item=iron-plate,quality=rare]]", "(idx inp <item:iron-plate@rare>)")
  end },
  { "chyby", function()
    A.raises(function() parser.parse_expression("f(x)(y)") end, "not-callable")
    A.raises(function() parser.parse_expression("a.b") end, "attribute-unsupported")
    A.raises(function() parser.parse_expression("[x for x in y]") end, "unsupported")
    A.raises(function() parser.parse_expression("a[1:2:3]") end, "unsupported")
    A.raises(function() parser.parse_expression("1 +") end, "unexpected-newline")
    A.raises(function() parser.parse_expression("x.f(a=1)") end, "kwargs-unsupported")
    A.raises(function() parser.parse_expression("f(a=1, 2)") end, "unexpected-token")
    A.raises(function() parser.parse_expression("(1, 2") end, "unexpected-newline")
    A.raises(function() parser.parse_expression("f(*a)") end, "unsupported")
  end },
  { "pozice uzlu", function()
    local e = parser.parse_expression("a +\\\n b")
    A.eq(e.right.line, 2, "řádek pravého operandu")
  end },
}
```
Přidat `"test_parser_expr"` do `SUITES`.

- [ ] **Step 3: Spustit – musí selhat**

Run: `bash tools/run-unit.sh`
Expected: FAIL `module 'scripts.lang.parser' not found`

- [ ] **Step 4: Implementace výrazové části**

`Pythonator/scripts/lang/parser.lua`:
```lua
--- Parser: tokeny → AST (rekurzivní sestup, priority operátorů jako v Pythonu).
local errors = require("scripts.lang.errors")
local lexer = require("scripts.lang.lexer")

local M = {}

local P = {}
P.__index = P

--- Vyhodí chybu „nečekaný token“ s textem odpovídajícím druhu tokenu.
local function fail_at(tk)
  if tk.t == "NEWLINE" then errors.raise(tk.line, tk.col, "unexpected-newline") end
  if tk.t == "INDENT" then errors.raise(tk.line, tk.col, "unexpected-indent") end
  if tk.t == "DEDENT" or tk.t == "EOF" then errors.raise(tk.line, tk.col, "unexpected-eof") end
  local text
  if tk.t == "STR" then text = '"' .. tk.v .. '"'
  elseif tk.t == "SIG" then text = "[" .. tk.v.tag .. "=" .. tk.v.name .. "]"
  else text = tostring(tk.v) end
  errors.raise(tk.line, tk.col, "unexpected-token", text)
end
M.fail_at = fail_at

--- Nový uzel AST s pozicí tokenu.
local function node(k, tk, fields)
  fields.k, fields.line, fields.col = k, tk.line, tk.col
  return fields
end
M.node = node

local EXPR_START_OP = { ["("] = true, ["["] = true, ["{"] = true, ["-"] = true, ["+"] = true, ["~"] = true }
local EXPR_START_KW = { True = true, False = true, None = true, ["not"] = true }

--- Může token začínat výraz?
local function starts_expr(tk)
  return tk.t == "NAME" or tk.t == "NUM" or tk.t == "STR" or tk.t == "SIG"
    or (tk.t == "OP" and EXPR_START_OP[tk.v] == true) or (tk.t == "KW" and EXPR_START_KW[tk.v] == true)
end
M.starts_expr = starts_expr

--- Vytvoří parser nad tokeny.
function M.new(toks) return setmetatable({ toks = toks, i = 1 }, P) end

function P:peek(k) return self.toks[self.i + (k or 0)] end
function P:next() local tk = self.toks[self.i]; self.i = self.i + 1; return tk end
function P:is(t, v) local tk = self.toks[self.i]; return tk.t == t and (v == nil or tk.v == v) end
function P:accept(t, v) if self:is(t, v) then return self:next() end end
function P:expect(t, v) if self:is(t, v) then return self:next() end; fail_at(self:peek()) end

--- Comprehension není podporovaná – srozumitelná chyba místo „nečekané for“.
function P:no_comprehension()
  local tk = self:peek()
  if tk.t == "KW" and tk.v == "for" then errors.raise(tk.line, tk.col, "unsupported", "comprehension") end
end

--- Výraz včetně podmíněného `a if c else b`.
function P:expr()
  local e = self:or_expr()
  local tk = self:accept("KW", "if")
  if tk then
    local test = self:or_expr()
    self:expect("KW", "else")
    return node("IfExp", tk, { test = test, body = e, orelse = self:expr() })
  end
  return e
end

--- Výraz nebo n-tice bez závorek (`a, b`).
function P:expr_list()
  local first = self:peek()
  local e = self:expr()
  if not self:is("OP", ",") then return e end
  local elts = { e }
  while self:accept("OP", ",") do
    if not starts_expr(self:peek()) then break end
    elts[#elts + 1] = self:expr()
  end
  return node("Tuple", first, { elts = elts })
end

--- Úroveň logického operátoru (`or` / `and`).
local function boollevel(op, next_name)
  return function(self)
    local e = self[next_name](self)
    if not self:is("KW", op) then return e end
    local values = { e }
    local first = self:peek()
    while self:accept("KW", op) do values[#values + 1] = self[next_name](self) end
    return node("BoolOp", first, { op = op, values = values })
  end
end
P.or_expr = boollevel("or", "and_expr")
P.and_expr = boollevel("and", "not_expr")

function P:not_expr()
  local tk = self:accept("KW", "not")
  if tk then return node("UnaryOp", tk, { op = "not", operand = self:not_expr() }) end
  return self:comparison()
end

local CMP = { ["<"] = true, [">"] = true, ["=="] = true, [">="] = true, ["<="] = true, ["!="] = true }

--- Přečte porovnávací operátor, nebo vrátí nil.
function P:cmp_op()
  local tk = self:peek()
  if tk.t == "OP" and CMP[tk.v] then self:next(); return tk.v end
  if tk.t == "KW" and tk.v == "in" then self:next(); return "in" end
  if tk.t == "KW" and tk.v == "not" then
    local nx = self:peek(1)
    if nx.t == "KW" and nx.v == "in" then self.i = self.i + 2; return "not in" end
  end
  if tk.t == "KW" and tk.v == "is" then
    self:next()
    if self:accept("KW", "not") then return "is not" end
    return "is"
  end
end

function P:comparison()
  local first = self:peek()
  local left = self:bitor()
  local ops, cmps = {}, {}
  while true do
    local op = self:cmp_op()
    if not op then break end
    ops[#ops + 1] = op
    cmps[#cmps + 1] = self:bitor()
  end
  if #ops == 0 then return left end
  return node("Compare", first, { left = left, ops = ops, comparators = cmps })
end

--- Úroveň binárních operátorů s levou asociativitou.
local function binlevel(next_name, ops)
  return function(self)
    local e = self[next_name](self)
    while true do
      local tk = self:peek()
      if not (tk.t == "OP" and ops[tk.v]) then return e end
      self:next()
      e = node("BinOp", tk, { op = tk.v, left = e, right = self[next_name](self) })
    end
  end
end
P.bitor = binlevel("bitxor", { ["|"] = true })
P.bitxor = binlevel("bitand", { ["^"] = true })
P.bitand = binlevel("shift", { ["&"] = true })
P.shift = binlevel("arith", { ["<<"] = true, [">>"] = true })
P.arith = binlevel("term", { ["+"] = true, ["-"] = true })
P.term = binlevel("factor", { ["*"] = true, ["/"] = true, ["//"] = true, ["%"] = true })

function P:factor()
  local tk = self:peek()
  if tk.t == "OP" and (tk.v == "-" or tk.v == "+" or tk.v == "~") then
    self:next()
    return node("UnaryOp", tk, { op = tk.v, operand = self:factor() })
  end
  return self:power()
end

function P:power()
  local base = self:postfix()
  local tk = self:accept("OP", "**")
  if tk then return node("BinOp", tk, { op = "**", left = base, right = self:factor() }) end
  return base
end

--- Argumenty volání po `(` až po `)`; vrátí poziční a pojmenované.
function P:call_args()
  local args, kwargs = {}, {}
  while not self:accept("OP", ")") do
    local tk, nx = self:peek(), self:peek(1)
    if tk.t == "NAME" and nx.t == "OP" and nx.v == "=" then
      self.i = self.i + 2
      kwargs[#kwargs + 1] = { name = tk.v, value = self:expr(), line = tk.line, col = tk.col }
    else
      if #kwargs > 0 then fail_at(tk) end
      if tk.t == "OP" and (tk.v == "*" or tk.v == "**") then errors.raise(tk.line, tk.col, "unsupported", tk.v .. "args") end
      args[#args + 1] = self:expr()
      self:no_comprehension()
    end
    if not self:accept("OP", ",") then self:expect("OP", ")"); break end
  end
  return args, kwargs
end

--- Index nebo řez po `[`.
function P:subscript(value, tk)
  local lower, upper
  if not self:is("OP", ":") then lower = self:expr() end
  if self:accept("OP", ":") then
    if not self:is("OP", "]") and not self:is("OP", ":") then upper = self:expr() end
    if self:is("OP", ":") then
      local t2 = self:peek()
      errors.raise(t2.line, t2.col, "unsupported", "[a:b:c]")
    end
    self:expect("OP", "]")
    return node("Slice", tk, { value = value, lower = lower, upper = upper })
  end
  self:expect("OP", "]")
  return node("Subscript", tk, { value = value, index = lower })
end

--- Atom s příponami: volání, index/řez, volání metody.
function P:postfix()
  local e = self:atom()
  while true do
    local tk = self:peek()
    if tk.t == "OP" and tk.v == "(" then
      if e.k ~= "Name" then errors.raise(tk.line, tk.col, "not-callable") end
      self:next()
      local args, kwargs = self:call_args()
      e = node("Call", e, { func = e.id, args = args, kwargs = kwargs })
    elseif tk.t == "OP" and tk.v == "[" then
      self:next()
      e = self:subscript(e, tk)
    elseif tk.t == "OP" and tk.v == "." then
      self:next()
      local name = self:expect("NAME")
      if not self:is("OP", "(") then errors.raise(name.line, name.col, "attribute-unsupported") end
      self:next()
      local args, kwargs = self:call_args()
      if #kwargs > 0 then errors.raise(kwargs[1].line, kwargs[1].col, "kwargs-unsupported") end
      e = node("Method", name, { obj = e, name = name.v, args = args })
    else
      return e
    end
  end
end

--- Prvky oddělené čárkou až po uzavírací závorku (koncová čárka povolená).
function P:sequence(close)
  local elts = {}
  while not self:accept("OP", close) do
    elts[#elts + 1] = self:expr()
    self:no_comprehension()
    if not self:accept("OP", ",") then self:expect("OP", close); break end
  end
  return elts
end

function P:atom()
  local tk = self:next()
  if tk.t == "NAME" then return node("Name", tk, { id = tk.v }) end
  if tk.t == "NUM" then return node("Num", tk, { v = tk.v }) end
  if tk.t == "STR" then
    local parts = { tk.v }
    while self:is("STR") do parts[#parts + 1] = self:next().v end
    return node("Str", tk, { v = table.concat(parts) })
  end
  if tk.t == "SIG" then
    return node("Signal", tk, { stype = tk.v.stype, tag = tk.v.tag, name = tk.v.name, quality = tk.v.quality })
  end
  if tk.t == "KW" then
    if tk.v == "True" then return node("Bool", tk, { v = true }) end
    if tk.v == "False" then return node("Bool", tk, { v = false }) end
    if tk.v == "None" then return node("None", tk, {}) end
  end
  if tk.t == "OP" and tk.v == "(" then
    if self:accept("OP", ")") then return node("Tuple", tk, { elts = {} }) end
    local e = self:expr()
    self:no_comprehension()
    if self:accept("OP", ")") then return e end
    local elts = { e }
    while self:accept("OP", ",") do
      if self:is("OP", ")") then break end
      elts[#elts + 1] = self:expr()
    end
    self:expect("OP", ")")
    return node("Tuple", tk, { elts = elts })
  end
  if tk.t == "OP" and tk.v == "[" then return node("List", tk, { elts = self:sequence("]") }) end
  if tk.t == "OP" and tk.v == "{" then
    local keys, values = {}, {}
    while not self:accept("OP", "}") do
      keys[#keys + 1] = self:expr()
      self:expect("OP", ":")
      values[#values + 1] = self:expr()
      if not self:accept("OP", ",") then self:expect("OP", "}"); break end
    end
    return node("Dict", tk, { keys = keys, values = values })
  end
  fail_at(tk)
end

--- Rozparsuje jediný výraz (pro testy).
--- @param src string
--- @return table expr
function M.parse_expression(src)
  local p = M.new(lexer.tokenize(src))
  local e = p:expr_list()
  p:expect("NEWLINE")
  p:expect("EOF")
  return e
end

M.Parser = P
return M
```

- [ ] **Step 5: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=66 fail=0`

- [ ] **Step 6: Commit**

```bash
git add Pythonator/scripts/lang/parser.lua tests/unit
git commit -m "Parser výrazů: priority jako v Pythonu, kolekce, volání, metody, řezy"
```

---

### Task 4: Parser – příkazy a celý program

**Files:**
- Modify: `Pythonator/scripts/lang/parser.lua` (přidat příkazy a `M.parse`, před řádek `M.Parser = P`)
- Create: `tests/unit/test_parser_stmt.lua`
- Modify: `tests/unit/run.lua` (přidat `"test_parser_stmt"`)

**Interfaces:**
- Consumes: z úlohy 3 `M.new`, `P:expr()`, `P:expr_list()`, `node`, `fail_at`, `starts_expr`
- Produces: `parser.parse(src) → {k="Module", body, line=1, col=1}`. `Assign.targets` je seznam (řetězené `a = b = 0`), cíle jsou `Name`, `Subscript` nebo `Tuple`/`List` z nich. `For.target` je `Name` nebo `Tuple` (vnořené). `Def.params` je seznam jmen.

- [ ] **Step 1: Padající testy**

`tests/unit/test_parser_stmt.lua`:
```lua
local A = require("assert")
local parser = require("scripts.lang.parser")
local D = require("ast_dump")

--- Ověří výpis rozparsovaného programu.
local function ps(src, expected)
  A.eq(D.stmts(parser.parse(src).body), expected, src)
end

return {
  { "přiřazení a rozšířené přiřazení", function() ps("x = 1\ny += 2\n", "(= x 1); (+= y 2)") end },
  { "řetězené přiřazení a n-tice", function()
    ps("a = b = 0", "(= a b 0)")
    ps("a, b = b, a", "(= (tuple a b) (tuple b a))")
    ps("[a, b] = t", "(= [a b] t)")
  end },
  { "přiřazení do indexu", function() ps("d['k'] = 1", '(= (idx d "k") 1)') end },
  { "neplatný cíl", function()
    A.raises(function() parser.parse("f() = 1") end, "bad-target")
    A.raises(function() parser.parse("a + 1 = 2") end, "bad-target")
    A.raises(function() parser.parse("a, b += 1") end, "bad-target")
    A.raises(function() parser.parse("x[1:2] = y") end, "bad-target")
  end },
  { "if / elif / else", function()
    ps("if a:\n  x = 1\nelif b:\n  x = 2\nelse:\n  x = 3\n",
      "(if a {(= x 1)} {(if b {(= x 2)} {(= x 3)})})")
  end },
  { "jednořádkový blok", function() ps("if a: b = 1\nc = 2", "(if a {(= b 1)} {}); (= c 2)") end },
  { "while, break, continue", function()
    ps("while x:\n  if y: break\n  continue\n", "(while x {(if y {break} {}); continue})")
  end },
  { "for s vnořenou n-ticí", function()
    ps("for k, (lo, hi) in L.items():\n  pass\n", "(for (tuple k (tuple lo hi)) (.items L) {pass})")
    ps("for i in range(3): pass", "(for i (call range 3) {pass})")
  end },
  { "def, global, return", function()
    ps("def f(a, b):\n  global g\n  return a, b\n", "(def f (a b) {(global g); (return (tuple a b))})")
    ps("def g():\n  return\n", "(def g () {(return)})")
  end },
  { "chybějící odsazení", function()
    local e = A.raises(function() parser.parse("if a:\nb") end, "expected-indent")
    A.eq(e.line, 2, "řádek")
  end },
  { "nečekané odsazení", function()
    A.raises(function() parser.parse("a\n  b\n") end, "unexpected-indent")
  end },
  { "výchozí parametry nepodporované", function()
    A.raises(function() parser.parse("def f(a=1): pass") end, "defaults-unsupported")
  end },
  { "while-else nepodporované", function()
    A.raises(function() parser.parse("while a:\n  pass\nelse:\n  pass") end, "unexpected-token")
  end },
  { "výrazový příkaz a docstring", function()
    ps('"""doc"""\nprint(1)', '"doc"; (call print 1)')
  end },
  { "čísla řádků příkazů", function()
    local m = parser.parse("a = 1\n\nif b:\n  c = 2")
    A.eq(m.body[2].line, 3, "if")
    A.eq(m.body[2].body[1].line, 4, "tělo if")
  end },
  { "ukázkový program s hysterezí", function()
    local src = table.concat({
      "LIMITS = {",
      "    'iron-plate': (1000, 5000),",
      "}",
      "active = {}",
      "",
      "def hyst(key, value, low, high):",
      "    if value < low:",
      "        active[key] = True",
      "    elif value > high:",
      "        active[key] = False",
      "    return active.get(key, False)",
      "",
      "def loop():",
      "    for key, (low, high) in LIMITS.items():",
      "        if hyst(key, inp[key], low, high):",
      "            out['recipe:' + key] = 1",
    }, "\n")
    local m = parser.parse(src)
    A.eq(#m.body, 4, "počet příkazů na nejvyšší úrovni")
    A.eq(m.body[3].k, "Def", "hyst")
    A.eq(m.body[4].name, "loop", "loop")
  end },
}
```
Přidat `"test_parser_stmt"` do `SUITES`.

- [ ] **Step 2: Spustit – musí selhat**

Run: `bash tools/run-unit.sh`
Expected: FAIL `attempt to call a nil value (field 'parse')`

- [ ] **Step 3: Implementace – vložit do `parser.lua` před `M.Parser = P`**

```lua
--- Konec jednoduchého příkazu: NEWLINE (nebo EOF).
function P:end_line()
  if self:accept("NEWLINE") or self:is("EOF") then return end
  fail_at(self:peek())
end

local AUG = {}
for _, op in ipairs({ "+=", "-=", "*=", "/=", "//=", "%=", "**=", "&=", "|=", "^=", "<<=", ">>=" }) do AUG[op] = true end

--- Ověří, že výraz je platný cíl přiřazení (rozšířené přiřazení nepovoluje n-tice).
local function check_target(e, aug)
  if e.k == "Name" or e.k == "Subscript" then return end
  if not aug and (e.k == "Tuple" or e.k == "List") then
    for _, el in ipairs(e.elts) do check_target(el, false) end
    return
  end
  errors.raise(e.line, e.col, "bad-target")
end

--- Jednoduchý příkaz (bez koncového NEWLINE).
function P:simple()
  local tk = self:peek()
  if tk.t == "KW" then
    if tk.v == "pass" then self:next(); return node("Pass", tk, {}) end
    if tk.v == "break" then self:next(); return node("Break", tk, {}) end
    if tk.v == "continue" then self:next(); return node("Continue", tk, {}) end
    if tk.v == "return" then
      self:next()
      local value
      if starts_expr(self:peek()) then value = self:expr_list() end
      return node("Return", tk, { value = value })
    end
    if tk.v == "global" then
      self:next()
      local names = { self:expect("NAME").v }
      while self:accept("OP", ",") do names[#names + 1] = self:expect("NAME").v end
      return node("Global", tk, { names = names })
    end
  end
  local first = self:expr_list()
  local op = self:peek()
  if op.t == "OP" and op.v == "=" then
    local items = { first }
    while self:accept("OP", "=") do items[#items + 1] = self:expr_list() end
    local value = table.remove(items)
    for _, t in ipairs(items) do check_target(t, false) end
    return node("Assign", tk, { targets = items, value = value })
  end
  if op.t == "OP" and AUG[op.v] then
    self:next()
    check_target(first, true)
    return node("AugAssign", tk, { target = first, op = op.v:sub(1, -2), value = self:expr_list() })
  end
  return node("Expr", tk, { value = first })
end

--- Blok po `:` – odsazený, nebo jednoduchý příkaz na stejném řádku.
function P:block()
  self:expect("OP", ":")
  local body = {}
  if self:accept("NEWLINE") then
    local tk = self:peek()
    if tk.t ~= "INDENT" then errors.raise(tk.line, tk.col, "expected-indent") end
    self:next()
    while not self:accept("DEDENT") do self:statement(body) end
  else
    body[1] = self:simple()
    self:end_line()
  end
  return body
end

--- if / elif (elif se vnoří do orelse).
function P:if_stmt()
  local tk = self:next()
  local test = self:expr()
  local n = node("If", tk, { test = test, body = self:block(), orelse = {} })
  if self:is("KW", "elif") then
    n.orelse = { self:if_stmt() }
  elseif self:accept("KW", "else") then
    n.orelse = self:block()
  end
  return n
end

--- Prvek cíle cyklu for: jméno nebo n-tice v závorkách.
function P:target_atom()
  local tk = self:next()
  if tk.t == "NAME" then return node("Name", tk, { id = tk.v }) end
  if tk.t == "OP" and tk.v == "(" then
    local t = self:target_list()
    self:expect("OP", ")")
    return t
  end
  fail_at(tk)
end

--- Cíl cyklu for: jeden prvek nebo n-tice oddělená čárkami.
function P:target_list()
  local first = self:peek()
  local t = self:target_atom()
  if not self:is("OP", ",") then return t end
  local elts = { t }
  while self:accept("OP", ",") do
    if not (self:is("NAME") or self:is("OP", "(")) then break end
    elts[#elts + 1] = self:target_atom()
  end
  return node("Tuple", first, { elts = elts })
end

function P:for_stmt()
  local tk = self:next()
  local target = self:target_list()
  self:expect("KW", "in")
  local iter = self:expr_list()
  return node("For", tk, { target = target, iter = iter, body = self:block() })
end

function P:def_stmt()
  local tk = self:next()
  local name = self:expect("NAME")
  self:expect("OP", "(")
  local params = {}
  while not self:accept("OP", ")") do
    local p = self:peek()
    if p.t == "OP" and (p.v == "*" or p.v == "**") then errors.raise(p.line, p.col, "unsupported", p.v .. "args") end
    params[#params + 1] = self:expect("NAME").v
    if self:is("OP", "=") then
      local d = self:peek()
      errors.raise(d.line, d.col, "defaults-unsupported")
    end
    if not self:accept("OP", ",") then self:expect("OP", ")"); break end
  end
  return node("Def", tk, { name = name.v, params = params, body = self:block() })
end

--- Jeden příkaz (složený nebo jednoduchý) připojený do seznamu out.
function P:statement(out)
  local tk = self:peek()
  if tk.t == "KW" then
    if tk.v == "if" then out[#out + 1] = self:if_stmt(); return end
    if tk.v == "while" then
      self:next()
      local test = self:expr()
      out[#out + 1] = node("While", tk, { test = test, body = self:block() })
      return
    end
    if tk.v == "for" then out[#out + 1] = self:for_stmt(); return end
    if tk.v == "def" then out[#out + 1] = self:def_stmt(); return end
  end
  if tk.t == "INDENT" then errors.raise(tk.line, tk.col, "unexpected-indent") end
  out[#out + 1] = self:simple()
  self:end_line()
end

--- Rozparsuje celý program.
--- @param src string
--- @return table Module
function M.parse(src)
  local p = M.new(lexer.tokenize(src))
  local body = {}
  while not p:is("EOF") do p:statement(body) end
  return { k = "Module", body = body, line = 1, col = 1 }
end
```

- [ ] **Step 4: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=82 fail=0`

- [ ] **Step 5: Commit**

```bash
git add Pythonator/scripts/lang/parser.lua tests/unit
git commit -m "Parser příkazů: bloky, if/while/for/def, přiřazení, celý program"
```

---

### Task 5: Runtime – hodnoty a operace

**Files:**
- Create: `Pythonator/scripts/lang/runtime.lua`
- Create: `tests/unit/test_runtime_core.lua`
- Modify: `tests/unit/run.lua` (přidat `"test_runtime_core"`)

**Interfaces:**
- Consumes: `errors.raise`
- Produces (vše na tabulce `R` vrácené modulem):
  - typy: `R.None`, `R.NoneMT`, `R.ListMT`, `R.TupleMT`, `R.DictMT`; `R.list(arr, n)`, `R.tuple(arr, n)`, `R.dict(kv, n)` (kv prokládané `{k1, v1, …}`, `n` = počet prvků pole kv); `R.dict_get(d, k) → v|nil`, `R.dict_set(d, k, v)`, `R.dict_del(d, k) → v|nil`
  - `R.typename(v)`, `R.truthy(v)`, `R.numv(v)`, `R.wrap32(x)`, `R.raise(key, ...)`
  - aritmetika: `add sub mul truediv floordiv mod pow neg pos invert not_`
  - bitové: `band bor bxor lshift rshift` (int32 se znaménkem)
  - porovnání: `eq ne lt le gt ge cmp contains is_`
  - text: `R.str(v)`, `R.repr(v)`
  - kontejnery: `getitem setitem slice iter unpack`
  - logika v hodnotovém kontextu: `R.and_(a, bf)`, `R.or_(a, bf)` (`bf` = funkce vracející pravý operand)
  - háčky metatabulek pro cizí objekty (úloha 6): `__getitem`, `__setitem`, `__contains`, `__iter`, `__len_py`, `__repr_py`; pole `__pyntr` = jméno typu.

Pravidla: typ hodnoty vždy přes `getmetatable` (identita `R.None` se po načtení savu ztrácí). `nil` jako operand = proměnná před přiřazením → chyba `unbound`. Řetězce se porovnávají po bajtech (ne `strcoll`, kvůli determinismu). `int` a `float` se nerozlišují: celé hodnoty se vypisují bez `.0` (odchylka od Pythonu, zapsat do nápovědy).

- [ ] **Step 1: Padající testy**

`tests/unit/test_runtime_core.lua`:
```lua
local A = require("assert")
local R = require("scripts.lang.runtime")

local function L(...) local a = { ... }; return R.list(a, select("#", ...)) end
local function T(...) local a = { ... }; return R.tuple(a, select("#", ...)) end
local function Dct(...) local a = { ... }; return R.dict(a, select("#", ...)) end

--- Kopie hodnoty jako po uložení a načtení hry: nové tabulky, stejné metatabulky (register_metatable).
local function savecopy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[savecopy(k)] = savecopy(x) end
  return setmetatable(c, getmetatable(v))
end

return {
  { "pravdivost", function()
    A.eq(R.truthy(0), false, "0"); A.eq(R.truthy(2), true, "2")
    A.eq(R.truthy(""), false, "prázdný str"); A.eq(R.truthy("a"), true, "str")
    A.eq(R.truthy(R.None), false, "None"); A.eq(R.truthy(L()), false, "prázdný list")
    A.eq(R.truthy(L(0)), true, "list"); A.eq(R.truthy(Dct()), false, "prázdný dict")
    A.raises(function() R.truthy(nil) end, "unbound")
  end },
  { "sčítání", function()
    A.eq(R.add(1, 2), 3, "čísla"); A.eq(R.add("a", "b"), "ab", "str")
    A.eq(R.add(true, 1), 2, "bool"); A.eq(R.repr(R.add(L(1), L(2))), "[1, 2]", "list")
    A.raises(function() R.add("a", 1) end, "type-error")
    A.raises(function() R.add(nil, 1) end, "unbound")
  end },
  { "dělení a zbytek po Pythonu", function()
    A.eq(R.floordiv(7, 2), 3, "7//2"); A.eq(R.floordiv(-7, 2), -4, "-7//2")
    A.eq(R.mod(-7, 3), 2, "-7%3"); A.eq(R.mod(7, -3), -2, "7%-3")
    A.eq(R.truediv(10, 4), 2.5, "10/4"); A.eq(R.pow(2, 10), 1024, "2**10")
    A.raises(function() R.truediv(1, 0) end, "zero-division")
    A.raises(function() R.floordiv(1, 0) end, "zero-division")
    A.raises(function() R.mod(1, 0) end, "zero-division")
  end },
  { "násobení sekvencí", function()
    A.eq(R.mul("ab", 3), "ababab", "str*int"); A.eq(R.mul(2, "x"), "xx", "int*str")
    A.eq(R.repr(R.mul(L(1), 2)), "[1, 1]", "list*int")
    A.raises(function() R.mul("a", "b") end, "type-error")
  end },
  { "bitové operace int32", function()
    A.eq(R.band(5, 3), 1, "&"); A.eq(R.bor(5, 3), 7, "|"); A.eq(R.bxor(5, 3), 6, "^")
    A.eq(R.invert(5), -6, "~"); A.eq(R.lshift(1, 4), 16, "<<"); A.eq(R.rshift(-16, 2), -4, ">>")
    A.eq(R.lshift(1, 31), -2147483648, "přetečení do znaménka")
    A.raises(function() R.band(1.5, 1) end, "type-error")
    A.raises(function() R.lshift(1, -1) end, "negative-shift")
  end },
  { "wrap32", function()
    A.eq(R.wrap32(2147483648), -2147483648, "2^31"); A.eq(R.wrap32(-1), -1, "-1")
    A.eq(R.wrap32(4294967297), 1, "2^32+1")
  end },
  { "rovnost", function()
    A.eq(R.eq(1, true), true, "1 == True"); A.eq(R.eq(L(1, 2), L(1, 2)), true, "list")
    A.eq(R.eq(Dct("a", 1, "b", 2), Dct("b", 2, "a", 1)), true, "dict bez ohledu na pořadí")
    A.eq(R.eq(R.None, R.None), true, "None"); A.eq(R.eq("a", 1), false, "str vs int")
    A.eq(R.eq(L(1), T(1)), false, "list vs tuple"); A.eq(R.ne(1, 2), true, "!=")
  end },
  { "uspořádání", function()
    A.eq(R.lt(1, 2), true, "čísla"); A.eq(R.lt("B", "a"), true, "str po bajtech")
    A.eq(R.lt(L(1, 2), L(1, 3)), true, "list lexikograficky"); A.eq(R.le(L(1), L(1)), true, "<=")
    A.eq(R.gt(3, 2), true, ">"); A.eq(R.ge(2, 2), true, ">=")
    A.raises(function() R.lt("a", 1) end, "type-error")
  end },
  { "in a is", function()
    A.eq(R.contains("abc", "b"), true, "podřetězec"); A.eq(R.contains(L(1, 2), 2), true, "list")
    A.eq(R.contains(Dct("k", 1), "k"), true, "klíč dict"); A.eq(R.contains(Dct("k", 1), 1), false, "hodnota není klíč")
    A.eq(R.is_(R.None, R.None), true, "None is None"); A.eq(R.is_(0, R.None), false, "0 is None")
  end },
  { "str a repr", function()
    A.eq(R.str(3), "3", "int"); A.eq(R.str(2.5), "2.5", "float"); A.eq(R.str(0.1), "0.1", "0.1")
    A.eq(R.str(1 / 3), "0.3333333333333333", "1/3"); A.eq(R.str(1e20), "1e+20", "velké")
    A.eq(R.str(-7), "-7", "záporné"); A.eq(R.str(true), "True", "bool"); A.eq(R.str("x"), "x", "str")
    A.eq(R.repr("it's"), "\"it's\"", "apostrof"); A.eq(R.repr("a\nb"), "'a\\nb'", "escape")
    A.eq(R.repr(L(1, "a", R.None, true)), "[1, 'a', None, True]", "list")
    A.eq(R.repr(T(1)), "(1,)", "jednoprvková n-tice"); A.eq(R.repr(T()), "()", "prázdná n-tice")
    A.eq(R.repr(Dct("a", 1)), "{'a': 1}", "dict")
  end },
  { "indexování", function()
    A.eq(R.getitem(L(1, 2, 3), -1), 3, "záporný index"); A.eq(R.getitem("abc", 1), "b", "str")
    A.raises(function() R.getitem(L(1), 1) end, "index-error")
    A.raises(function() R.getitem(L(1), "a") end, "bad-index-type")
    A.eq(A.raises(function() R.getitem(Dct(), "x") end, "key-error").args[1], "'x'", "repr klíče")
    A.raises(function() R.setitem(T(1), 0, 2) end, "immutable")
    local l = L(1, 2); R.setitem(l, -1, 5); A.eq(R.repr(l), "[1, 5]", "setitem list")
  end },
  { "řezy", function()
    A.eq(R.repr(R.slice(L(1, 2, 3), 1, nil)), "[2, 3]", "[1:]")
    A.eq(R.repr(R.slice(L(1, 2, 3), nil, -1)), "[1, 2]", "[:-1]")
    A.eq(R.repr(R.slice(L(1, 2, 3), 5, 10)), "[]", "mimo rozsah")
    A.eq(R.slice("hello", 1, 3), "el", "str")
    A.eq(R.repr(R.slice(T(1, 2), nil, nil)), "(1, 2)", "tuple")
  end },
  { "pořadí dict po smazání a znovuvložení", function()
    local d = Dct("a", 1, "b", 2, "c", 3)
    A.eq(R.dict_del(d, "b"), 2, "smazaná hodnota")
    R.dict_set(d, "b", 4)
    local keys = {}
    for k in R.iter(d) do keys[#keys + 1] = k end
    A.eq(table.concat(keys, ","), "a,c,b", "pořadí klíčů")
  end },
  { "iterace", function()
    local s = {}
    for x in R.iter(L(1, 2)) do s[#s + 1] = R.str(x) end
    for x in R.iter("ab") do s[#s + 1] = x end
    A.eq(table.concat(s, ","), "1,2,a,b", "list a str")
    A.raises(function() R.iter(5) end, "not-iterable")
  end },
  { "rozbalení", function()
    local a, b = R.unpack(T(1, 2), 2)
    A.eq(a + b, 3, "hodnoty")
    A.raises(function() R.unpack(T(1, 2, 3), 2) end, "unpack-count")
  end },
  { "kopie None/list/dict bez identity (uložení hry)", function()
    local none, list, dict = savecopy(R.None), savecopy(L(1, R.None)), savecopy(Dct("k", L(2)))
    A.eq(R.truthy(none), false, "None nepravdivé")
    A.eq(R.is_(none, R.None), true, "None is None")
    A.eq(R.eq(none, R.None), true, "None == None")
    A.eq(R.repr(list), "[1, None]", "list")
    A.eq(R.repr(R.getitem(dict, "k")), "[2]", "dict")
  end },
  { "and/or v hodnotovém kontextu", function()
    A.eq(R.or_(0, function() return 5 end), 5, "0 or 5")
    A.eq(R.and_("", function() error("nevyhodnocovat") end), "", "'' and …")
    A.eq(R.and_(1, function() return 7 end), 7, "1 and 7")
  end },
}
```
Přidat `"test_runtime_core"` do `SUITES`.

- [ ] **Step 2: Spustit – musí selhat**

Run: `bash tools/run-unit.sh`
Expected: FAIL `module 'scripts.lang.runtime' not found`

- [ ] **Step 3: Implementace**

`Pythonator/scripts/lang/runtime.lua`:
```lua
--- Runtime Pythonatoru: hodnoty a operace s Python sémantikou pro vygenerovaný kód.
--- int/float = Lua number, bool = Lua boolean, str = Lua string, None/list/tuple/dict = tabulky s metatabulkou.
--- Typ se rozpoznává vždy přes getmetatable – po načtení savu jsou to nové tabulky (identita se ztrácí).
local errors = require("scripts.lang.errors")

local R = {}

local NoneMT = { __pyntr = "None" }
local ListMT = { __pyntr = "list" }
local TupleMT = { __pyntr = "tuple" }
local DictMT = { __pyntr = "dict" }
R.NoneMT, R.ListMT, R.TupleMT, R.DictMT = NoneMT, ListMT, TupleMT, DictMT

R.None = setmetatable({}, NoneMT)

--- Vyhodí chybu jazyka bez pozice (řádek doplní VM).
local function raise(key, ...) errors.raise(nil, nil, key, ...) end
R.raise = raise

--- Jméno typu v Python stylu (pro hlášky); nil = proměnná před přiřazením.
--- @return string
function R.typename(v)
  local t = type(v)
  if t == "number" then return v == math.floor(v) and "int" or "float" end
  if t == "string" then return "str" end
  if t == "boolean" then return "bool" end
  if t == "nil" then raise("unbound") end
  local mt = getmetatable(v)
  return mt and mt.__pyntr or "object"
end

--- Nový list z pole (pole se převezme).
function R.list(arr, n) arr.n = n; return setmetatable(arr, ListMT) end

--- Nová n-tice z pole (pole se převezme).
function R.tuple(arr, n) arr.n = n; return setmetatable(arr, TupleMT) end

--- Klíč Lua tabulky pro klíč slovníku (str/číslo/bool).
local function dkey(k)
  local t = type(k)
  if t == "string" or t == "boolean" then return k end
  if t == "number" and k == k then return k end
  raise("bad-dict-key", R.typename(k))
end

--- Hodnota pod klíčem, nebo nil, pokud klíč chybí.
function R.dict_get(d, k) return d.vals[dkey(k)] end

--- Nastaví klíč; nový klíč se přidá na konec pořadí.
function R.dict_set(d, k, v)
  local kk = dkey(k)
  if d.vals[kk] == nil then d.keys[#d.keys + 1] = k end
  d.vals[kk] = v
end

--- Smaže klíč a vrátí jeho hodnotu (nil, pokud chyběl).
function R.dict_del(d, k)
  local kk = dkey(k)
  local v = d.vals[kk]
  if v == nil then return nil end
  d.vals[kk] = nil
  for i, key in ipairs(d.keys) do
    if dkey(key) == kk then table.remove(d.keys, i); break end
  end
  return v
end

--- Nový dict z prokládaného pole {k1, v1, k2, v2, …} o n prvcích.
function R.dict(kv, n)
  local d = setmetatable({ keys = {}, vals = {} }, DictMT)
  for i = 1, n, 2 do R.dict_set(d, kv[i], kv[i + 1]) end
  return d
end

--- Číselná hodnota (bool jako 0/1), nebo nil.
local function numv(v)
  local t = type(v)
  if t == "number" then return v end
  if t == "boolean" then return v and 1 or 0 end
end
R.numv = numv

local function type_error(op, a, b) raise("type-error", op, R.typename(a), R.typename(b)) end

--- Obě hodnoty jako čísla, jinak TypeError.
local function nums(op, a, b)
  local x, y = numv(a), numv(b)
  if not (x and y) then type_error(op, a, b) end
  return x, y
end

--- Pravdivost hodnoty podle Pythonu.
function R.truthy(v)
  if v == true then return true end
  if v == false then return false end
  local t = type(v)
  if t == "number" then return v ~= 0 end
  if t == "string" then return v ~= "" end
  if t == "nil" then raise("unbound") end
  local mt = getmetatable(v)
  if mt == NoneMT then return false end
  if mt == ListMT or mt == TupleMT then return v.n > 0 end
  if mt == DictMT then return #v.keys > 0 end
  if mt and mt.__len_py then return mt.__len_py(v) > 0 end
  return true
end

function R.not_(a) return not R.truthy(a) end

--- Nová sekvence z prvků a a b.
local function concat_seq(a, b, mt)
  local r = { n = a.n + b.n }
  for i = 1, a.n do r[i] = a[i] end
  for i = 1, b.n do r[a.n + i] = b[i] end
  return setmetatable(r, mt)
end

--- Sekvence opakovaná n-krát.
local function repeat_seq(s, n, mt)
  local r = { n = 0 }
  for _ = 1, n do
    for i = 1, s.n do r.n = r.n + 1; r[r.n] = s[i] end
  end
  return setmetatable(r, mt)
end

function R.add(a, b)
  local ta, tb = type(a), type(b)
  if ta == "number" and tb == "number" then return a + b end
  if ta == "string" and tb == "string" then return a .. b end
  local x, y = numv(a), numv(b)
  if x and y then return x + y end
  local ma = getmetatable(a)
  if (ma == ListMT or ma == TupleMT) and ma == getmetatable(b) then return concat_seq(a, b, ma) end
  type_error("+", a, b)
end

function R.sub(a, b)
  if type(a) == "number" and type(b) == "number" then return a - b end
  local x, y = nums("-", a, b)
  return x - y
end

function R.mul(a, b)
  local x, y = numv(a), numv(b)
  if x and y then return x * y end
  local seq, count = a, y
  if x then seq, count = b, x end
  if count and count == math.floor(count) then
    count = math.max(0, count)
    if type(seq) == "string" then return seq:rep(count) end
    local mt = getmetatable(seq)
    if mt == ListMT or mt == TupleMT then return repeat_seq(seq, count, mt) end
  end
  type_error("*", a, b)
end

function R.truediv(a, b)
  local x, y = nums("/", a, b)
  if y == 0 then raise("zero-division") end
  return x / y
end

function R.floordiv(a, b)
  local x, y = nums("//", a, b)
  if y == 0 then raise("zero-division") end
  return math.floor(x / y)
end

function R.mod(a, b)
  local x, y = nums("%", a, b)
  if y == 0 then raise("zero-division") end
  return x - math.floor(x / y) * y
end

function R.pow(a, b)
  local x, y = nums("**", a, b)
  if x == 0 and y < 0 then raise("zero-division") end
  return x ^ y
end

function R.neg(a)
  local x = numv(a)
  if not x then raise("type-error-unary", "-", R.typename(a)) end
  return -x
end

function R.pos(a)
  local x = numv(a)
  if not x then raise("type-error-unary", "+", R.typename(a)) end
  return x
end

--- Celé číslo pro bitovou operaci, jinak TypeError.
local function intv(op, v, other)
  local x = numv(v)
  if not x or x ~= math.floor(x) then type_error(op, v, other) end
  return x
end

--- Výsledek bit32 (0..2^32-1) → int32 se znaménkem.
local function signed(u)
  if u >= 2147483648 then return u - 4294967296 end
  return u
end

--- Přetečení do int32 jako v obvodové síti.
function R.wrap32(x) return signed(x % 4294967296) end

function R.invert(a)
  local x = numv(a)
  if not x or x ~= math.floor(x) then raise("type-error-unary", "~", R.typename(a)) end
  return -x - 1
end

function R.band(a, b) return signed(bit32.band(intv("&", a, b), intv("&", b, a))) end
function R.bor(a, b) return signed(bit32.bor(intv("|", a, b), intv("|", b, a))) end
function R.bxor(a, b) return signed(bit32.bxor(intv("^", a, b), intv("^", b, a))) end

function R.lshift(a, b)
  local x, s = intv("<<", a, b), intv("<<", b, a)
  if s < 0 then raise("negative-shift") end
  if s >= 32 then return 0 end
  return signed(bit32.lshift(x, s))
end

function R.rshift(a, b)
  local x, s = intv(">>", a, b), intv(">>", b, a)
  if s < 0 then raise("negative-shift") end
  if s >= 32 then return x < 0 and -1 or 0 end
  return signed(bit32.arshift(x, s))
end

--- Porovnání řetězců po bajtech (-1/0/1), nezávislé na locale.
local function strcmp(a, b)
  if a == b then return 0 end
  for i = 1, math.min(#a, #b) do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then return x < y and -1 or 1 end
  end
  return #a < #b and -1 or 1
end

--- Rovnost s Python sémantikou (Lua boolean).
function R.eq(a, b)
  if a == nil or b == nil then raise("unbound") end
  if a == b then return true end
  local x, y = numv(a), numv(b)
  if x and y then return x == y end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  local ma = getmetatable(a)
  if ma ~= getmetatable(b) then return false end
  if ma == NoneMT then return true end
  if ma == ListMT or ma == TupleMT then
    if a.n ~= b.n then return false end
    for i = 1, a.n do if not R.eq(a[i], b[i]) then return false end end
    return true
  end
  if ma == DictMT then
    if #a.keys ~= #b.keys then return false end
    for _, k in ipairs(a.keys) do
      local bv = R.dict_get(b, k)
      if bv == nil or not R.eq(R.dict_get(a, k), bv) then return false end
    end
    return true
  end
  return false
end

function R.ne(a, b) return not R.eq(a, b) end

--- Uspořádání -1/0/1 (čísla, str, list/tuple lexikograficky), jinak TypeError.
function R.cmp(a, b, op)
  local x, y = numv(a), numv(b)
  if x and y then return x < y and -1 or (x > y and 1 or 0) end
  if type(a) == "string" and type(b) == "string" then return strcmp(a, b) end
  local ma = getmetatable(a)
  if (ma == ListMT or ma == TupleMT) and ma == getmetatable(b) then
    for i = 1, math.min(a.n, b.n) do
      local c = R.cmp(a[i], b[i], op)
      if c ~= 0 then return c end
    end
    return a.n < b.n and -1 or (a.n > b.n and 1 or 0)
  end
  type_error(op or "<", a, b)
end

function R.lt(a, b)
  if type(a) == "number" and type(b) == "number" then return a < b end
  return R.cmp(a, b, "<") < 0
end
function R.le(a, b)
  if type(a) == "number" and type(b) == "number" then return a <= b end
  return R.cmp(a, b, "<=") <= 0
end
function R.gt(a, b)
  if type(a) == "number" and type(b) == "number" then return a > b end
  return R.cmp(a, b, ">") > 0
end
function R.ge(a, b)
  if type(a) == "number" and type(b) == "number" then return a >= b end
  return R.cmp(a, b, ">=") >= 0
end

--- `item in container`.
function R.contains(container, item)
  if type(container) == "string" then
    if type(item) ~= "string" then type_error("in", item, container) end
    return container:find(item, 1, true) ~= nil
  end
  local mt = getmetatable(container)
  if mt == ListMT or mt == TupleMT then
    for i = 1, container.n do if R.eq(container[i], item) then return true end end
    return false
  end
  if mt == DictMT then return R.dict_get(container, item) ~= nil end
  if mt and mt.__contains then return mt.__contains(container, item) end
  type_error("in", item, container)
end

--- `a is b` (None se pozná podle metatabulky).
function R.is_(a, b)
  local an, bn = getmetatable(a) == NoneMT, getmetatable(b) == NoneMT
  if an or bn then return an and bn end
  return rawequal(a, b)
end

--- Číslo jako text v Python stylu; celé hodnoty bez ".0" (int a float se nerozlišují).
local function fmt_num(x)
  if x ~= x then return "nan" end
  if x == math.huge then return "inf" end
  if x == -math.huge then return "-inf" end
  if x == math.floor(x) and math.abs(x) < 1e16 then return string.format("%d", x) end
  for p = 1, 17 do
    local s = string.format("%." .. p .. "g", x)
    if tonumber(s) == x then return s end
  end
  return string.format("%.17g", x)
end

--- Řetězec v uvozovkách jako repr() v Pythonu.
local function repr_str(s)
  local q = "'"
  if s:find("'", 1, true) and not s:find('"', 1, true) then q = '"' end
  local out = s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", "\\r")
  if q == "'" then out = out:gsub("'", "\\'") end
  return q .. out .. q
end

function R.repr(v)
  local t = type(v)
  if t == "string" then return repr_str(v) end
  if t == "number" then return fmt_num(v) end
  if t == "boolean" then return v and "True" or "False" end
  if t == "nil" then raise("unbound") end
  local mt = getmetatable(v)
  if mt == NoneMT then return "None" end
  if mt == ListMT or mt == TupleMT then
    local parts = {}
    for i = 1, v.n do parts[i] = R.repr(v[i]) end
    if mt == ListMT then return "[" .. table.concat(parts, ", ") .. "]" end
    if v.n == 1 then return "(" .. parts[1] .. ",)" end
    return "(" .. table.concat(parts, ", ") .. ")"
  end
  if mt == DictMT then
    local parts = {}
    for i, k in ipairs(v.keys) do parts[i] = R.repr(k) .. ": " .. R.repr(R.dict_get(v, k)) end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  if mt and mt.__repr_py then return mt.__repr_py(v) end
  return "<object>"
end

function R.str(v)
  if type(v) == "string" then return v end
  return R.repr(v)
end

--- Python index (záporný od konce) → Lua index 1..n, jinak IndexError.
local function seq_index(i, n)
  local x = numv(i)
  if not x or x ~= math.floor(x) then raise("bad-index-type", R.typename(i)) end
  if x < 0 then x = x + n end
  if x < 0 or x >= n then raise("index-error") end
  return x + 1
end

function R.getitem(o, k)
  local mt = getmetatable(o)
  if mt == ListMT or mt == TupleMT then return o[seq_index(k, o.n)] end
  if mt == DictMT then
    local v = R.dict_get(o, k)
    if v == nil then raise("key-error", R.repr(k)) end
    return v
  end
  if type(o) == "string" then
    local i = seq_index(k, #o)
    return o:sub(i, i)
  end
  if mt and mt.__getitem then return mt.__getitem(o, k) end
  type_error("[]", o, k)
end

function R.setitem(o, k, v)
  local mt = getmetatable(o)
  if mt == ListMT then o[seq_index(k, o.n)] = v; return end
  if mt == DictMT then R.dict_set(o, k, v); return end
  if mt and mt.__setitem then mt.__setitem(o, k, v); return end
  raise("immutable", R.typename(o))
end

--- Meze řezu (Python) → Lua rozsah from..to (včetně).
local function slice_bounds(lo, hi, n)
  local function norm(v, default)
    if v == nil or getmetatable(v) == NoneMT then return default end
    local x = numv(v)
    if not x or x ~= math.floor(x) then raise("bad-index-type", R.typename(v)) end
    if x < 0 then x = math.max(0, x + n) end
    return math.min(x, n)
  end
  return norm(lo, 0) + 1, norm(hi, n)
end

function R.slice(o, lo, hi)
  if type(o) == "string" then
    local a, b = slice_bounds(lo, hi, #o)
    return o:sub(a, b)
  end
  local mt = getmetatable(o)
  if mt == ListMT or mt == TupleMT then
    local a, b = slice_bounds(lo, hi, o.n)
    local r = { n = 0 }
    for i = a, b do r.n = r.n + 1; r[r.n] = o[i] end
    return setmetatable(r, mt)
  end
  raise("type-error", "[:]", R.typename(o), "slice")
end

--- Iterátor pro generický for vygenerovaného kódu (konec = nil).
function R.iter(v)
  local mt = getmetatable(v)
  if mt == ListMT or mt == TupleMT then
    local i = 0
    return function()
      i = i + 1
      if i <= v.n then return v[i] end
    end
  end
  if mt == DictMT then
    local ks, i = {}, 0
    for j, k in ipairs(v.keys) do ks[j] = k end
    return function() i = i + 1; return ks[i] end
  end
  if type(v) == "string" then
    local i = 0
    return function()
      i = i + 1
      if i <= #v then return v:sub(i, i) end
    end
  end
  if mt and mt.__iter then return mt.__iter(v) end
  raise("not-iterable", R.typename(v))
end

--- Rozbalí hodnotu na přesně n hodnot.
function R.unpack(v, n)
  local mt = getmetatable(v)
  local arr, len = v, nil
  if mt == ListMT or mt == TupleMT then
    len = v.n
  else
    arr, len = {}, 0
    for x in R.iter(v) do len = len + 1; arr[len] = x end
  end
  if len ~= n then raise("unpack-count", n, len) end
  return table.unpack(arr, 1, n)
end

--- `a and b` v hodnotovém kontextu (bf vyhodnotí b líně).
function R.and_(a, bf)
  if R.truthy(a) then return bf() end
  return a
end

--- `a or b` v hodnotovém kontextu (bf vyhodnotí b líně).
function R.or_(a, bf)
  if R.truthy(a) then return a end
  return bf()
end

return R
```

- [ ] **Step 4: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=99 fail=0`

- [ ] **Step 5: Commit**

```bash
git add Pythonator/scripts/lang/runtime.lua tests/unit
git commit -m "Runtime: hodnoty a operace s Python sémantikou"
```

---

### Task 6: Runtime – vestavěné funkce, metody, objekty signálů

**Files:**
- Create: `Pythonator/scripts/lang/builtins.lua` (vestavěné funkce a metody; rozšiřuje `R`)
- Create: `Pythonator/scripts/lang/signal_io.lua` (objekty `inp/red/green/out/out_red/out_green`)
- Create: `tests/unit/test_builtins.lua`, `tests/unit/test_signal_io.lua`
- Modify: `tests/unit/run.lua` (přidat obě sady)

**Interfaces:**
- Consumes: `R` z úlohy 5 (`R.list`, `R.tuple`, `R.dict_*`, `R.iter`, `R.cmp`, `R.eq`, `R.truthy`, `R.str`, `R.repr`, `R.numv`, `R.wrap32`, `R.raise`, `R.typename`)
- Produces:
  - `require("scripts.lang.builtins")` vrátí `R` doplněný o `R.builtins` (tabulka jméno → funkce: `abs min max round int float str bool len range sum sorted`), `R.method(obj, name, ...)`, `R.print_line(...) → string`, `R.range_bounds(a, b, c) → first, last, step` (pro číselný for v codegenu), `R.watchdog()` (vyhodí `watchdog`; limit doplní VM).
  - `signal_io.reader(source, resolver) → objekt` kde `source = {get = function(canonical) → number, all = function() → { {key, value}… } }`
  - `signal_io.writer(store, resolver) → objekt` nad tabulkou `store` (kanonický klíč → int32 ≠ 0)
  - `signal_io.ReaderMT`, `signal_io.WriterMT` (pro registraci metatabulek ve hře – úloha plánu 2)

Pravidla signálů: klíč musí být řetězec, ověří se resolverem (chyba = `unknown-signal…` z resolveru); čtení chybějícího signálu = 0; zápis: hodnota přes `numv`, ořez k nule, `wrap32`, nula klíč smaže. `items()` vrací list n-tic `(klíč, hodnota)` v pořadí od zdroje. Metody čtecího objektu: `get items keys values`; zapisovacího navíc `clear`. `len()` a pravdivost = počet nenulových signálů.

- [ ] **Step 1: Padající testy vestavěných funkcí a metod**

`tests/unit/test_builtins.lua`:
```lua
local A = require("assert")
local R = require("scripts.lang.builtins")
local B = R.builtins

local function L(...) local a = { ... }; return R.list(a, select("#", ...)) end

return {
  { "abs, min, max", function()
    A.eq(B.abs(-4), 4, "abs"); A.eq(B.min(3, 1, 2), 1, "min argumentů")
    A.eq(B.max(L(4, 9, 2)), 9, "max iterovatelného"); A.eq(B.max("a", "b"), "b", "max str")
    A.raises(function() B.min(L()) end, "empty-sequence")
    A.raises(function() B.abs() end, "arg-count")
  end },
  { "round – bankéřské zaokrouhlení", function()
    A.eq(B.round(2.5), 2, "2.5"); A.eq(B.round(3.5), 4, "3.5"); A.eq(B.round(-2.5), -2, "-2.5")
    A.eq(B.round(1.234, 2), 1.23, "na 2 místa")
    A.eq(B.round(7), 7, "celé")
  end },
  { "int, float, str, bool", function()
    A.eq(B.int(-3.7), -3, "ořez k nule"); A.eq(B.int(" 12 "), 12, "z textu"); A.eq(B.int(true), 1, "bool")
    A.raises(function() B.int("1.5") end, "bad-int")
    A.eq(B.float("2.5"), 2.5, "float z textu"); A.raises(function() B.float("x") end, "bad-float")
    A.eq(B.str(L(1)), "[1]", "str"); A.eq(B.bool(L()), false, "bool")
  end },
  { "len, range, sum, sorted", function()
    A.eq(B.len("abc"), 3, "str"); A.eq(B.len(L(1, 2)), 2, "list")
    A.eq(R.repr(B.range(3)), "[0, 1, 2]", "range(3)"); A.eq(R.repr(B.range(5, 1, -2)), "[5, 3]", "záporný krok")
    A.raises(function() B.range(1, 2, 0) end, "range-step-zero")
    A.eq(B.sum(L(1, 2, 3)), 6, "sum"); A.eq(B.sum(L(1), 10), 11, "sum se startem")
    A.eq(R.repr(B.sorted(L(3, 1, 2))), "[1, 2, 3]", "sorted")
    A.raises(function() B.len(5) end, "type-error-unary")
  end },
  { "range_bounds pro číselný for", function()
    A.same({ R.range_bounds(0, 3, 1) }, { 0, 2, 1 }, "0..2")
    A.same({ R.range_bounds(5, 1, -2) }, { 5, 2, -2 }, "sestupně")
    A.raises(function() R.range_bounds(0, 3, 0) end, "range-step-zero")
    A.raises(function() R.range_bounds(0, 2.5, 1) end, "bad-int")
  end },
  { "metody listu", function()
    local l = L(1, 2)
    R.method(l, "append", 3); A.eq(R.repr(l), "[1, 2, 3]", "append")
    A.eq(R.method(l, "pop"), 3, "pop"); A.eq(R.method(l, "pop", 0), 1, "pop(0)")
    R.method(l, "insert", 0, 9); A.eq(R.repr(l), "[9, 2]", "insert")
    R.method(l, "remove", 9); A.eq(R.method(l, "index", 2), 0, "index")
    R.method(l, "clear"); A.raises(function() R.method(l, "pop") end, "pop-empty")
    A.raises(function() R.method(l, "remove", 5) end, "not-in-list")
    A.raises(function() R.method(l, "nope") end, "unknown-method")
  end },
  { "metody dict", function()
    local d = R.dict({ "a", 1 }, 2)
    A.eq(R.method(d, "get", "a"), 1, "get"); A.eq(R.method(d, "get", "x", 5), 5, "get s výchozí")
    A.eq(R.is_(R.method(d, "get", "x"), R.None), true, "get bez výchozí = None")
    A.eq(R.repr(R.method(d, "items")), "[('a', 1)]", "items")
    A.eq(R.repr(R.method(d, "keys")), "['a']", "keys"); A.eq(R.repr(R.method(d, "values")), "[1]", "values")
    A.eq(R.method(d, "pop", "a"), 1, "pop"); A.raises(function() R.method(d, "pop", "a") end, "key-error")
    A.eq(R.method(d, "pop", "a", 0), 0, "pop s výchozí")
  end },
  { "metody str", function()
    A.eq(R.method("Ab", "upper"), "AB", "upper"); A.eq(R.method("Ab", "lower"), "ab", "lower")
    A.eq(R.method("abc", "startswith", "ab"), true, "startswith"); A.eq(R.method("abc", "endswith", "bc"), true, "endswith")
    A.eq(R.repr(R.method("a,b", "split", ",")), "['a', 'b']", "split oddělovač")
    A.eq(R.repr(R.method(" a  b ", "split")), "['a', 'b']", "split mezery")
    A.eq(R.method("-", "join", L("a", "b")), "a-b", "join")
    A.eq(R.method("a.b.c", "replace", ".", "-"), "a-b-c", "replace bez vzorů Lua")
  end },
  { "print_line a watchdog", function()
    A.eq(R.print_line(1, "a", R.None, L(2)), "1 a None [2]", "print")
    A.raises(function() R.watchdog() end, "watchdog")
  end },
}
```

`tests/unit/test_signal_io.lua`:
```lua
local A = require("assert")
local R = require("scripts.lang.builtins")
local signal_io = require("scripts.lang.signal_io")
local signals = require("scripts.lang.signals")
local fake = require("fake_protos")

--- Čtecí objekt nad pevnou tabulkou kanonický klíč → hodnota.
local function reader(values, order)
  local source = {
    get = function(k) return values[k] or 0 end,
    all = function()
      local out = {}
      for _, k in ipairs(order) do out[#out + 1] = { k, values[k] } end
      return out
    end,
  }
  return signal_io.reader(source, signals.new_resolver(fake()))
end

return {
  { "čtení, chybějící = 0", function()
    local inp = reader({ ["iron-plate"] = 5 }, { "iron-plate" })
    A.eq(R.getitem(inp, "iron-plate"), 5, "existující")
    A.eq(R.getitem(inp, "copper-plate"), 0, "chybějící")
    A.eq(R.getitem(inp, "item:iron-plate"), 5, "nekanonický zápis")
  end },
  { "neznámý signál a špatný typ klíče", function()
    local inp = reader({}, {})
    A.raises(function() R.getitem(inp, "iron-plates") end, "unknown-signal")
    A.raises(function() R.getitem(inp, 5) end, "bad-signal-key")
  end },
  { "vstup nelze zapisovat", function()
    A.raises(function() R.setitem(reader({}, {}), "iron-plate", 1) end, "readonly-signal")
  end },
  { "items, len, in, pravdivost", function()
    local inp = reader({ ["iron-plate"] = 5, ["signal-A"] = -1 }, { "iron-plate", "signal-A" })
    A.eq(R.repr(R.method(inp, "items")), "[('iron-plate', 5), ('signal-A', -1)]", "items")
    A.eq(R.builtins.len(inp), 2, "len")
    A.eq(R.contains(inp, "signal-A"), true, "in"); A.eq(R.contains(inp, "signal-B"), false, "not in")
    A.eq(R.truthy(reader({}, {})), false, "prázdný")
    local keys = {}
    for k in R.iter(inp) do keys[#keys + 1] = k end
    A.eq(table.concat(keys, ","), "iron-plate,signal-A", "iterace klíčů")
  end },
  { "zápis: ořez, přetečení, nula maže", function()
    local store = {}
    local out = signal_io.writer(store, signals.new_resolver(fake()))
    R.setitem(out, "signal-A", 3.7); A.eq(store["signal-A"], 3, "ořez k nule")
    R.setitem(out, "signal-B", -3.7); A.eq(store["signal-B"], -3, "ořez záporného")
    R.setitem(out, "signal-I", 2147483648); A.eq(store["signal-I"], -2147483648, "přetečení")
    R.setitem(out, "signal-P", true); A.eq(store["signal-P"], 1, "bool")
    R.setitem(out, "signal-A", 0); A.eq(store["signal-A"], nil, "nula maže")
    A.raises(function() R.setitem(out, "signal-A", "x") end, "type-error")
  end },
  { "zápis kanonickým klíčem a clear", function()
    local store = {}
    local out = signal_io.writer(store, signals.new_resolver(fake()))
    R.setitem(out, "recipe:iron-plate@rare", 1)
    A.eq(store["recipe:iron-plate@rare"], 1, "kanonický klíč")
    A.eq(R.getitem(out, "recipe:iron-plate@rare"), 1, "čtení výstupu")
    R.method(out, "clear")
    A.eq(next(store), nil, "clear vyprázdní úložiště (stejná tabulka)")
  end },
}
```

Přidat `"test_builtins", "test_signal_io"` do `SUITES`.

- [ ] **Step 2: Spustit – musí selhat**

Run: `bash tools/run-unit.sh`
Expected: FAIL `module 'scripts.lang.builtins' not found`

- [ ] **Step 3: Implementace `builtins.lua`**

`Pythonator/scripts/lang/builtins.lua`:
```lua
--- Vestavěné funkce a metody jazyka; rozšiřuje runtime R a vrací ho.
local R = require("scripts.lang.runtime")

local raise = R.raise
local B = {}
R.builtins = B

--- Ověří počet argumentů (min..max).
local function argc(name, n, min, max)
  if n < min or n > (max or min) then
    raise("arg-count", name, min == (max or min) and tostring(min) or (min .. "–" .. max), n)
  end
end

--- Celé číslo z hodnoty, jinak bad-int.
local function int_of(v)
  local x = R.numv(v)
  if not x or x ~= math.floor(x) then raise("bad-int", R.repr(v)) end
  return x
end

--- Pole hodnot z iterovatelného objektu.
local function collect(v)
  local arr, n = {}, 0
  for x in R.iter(v) do n = n + 1; arr[n] = x end
  return arr, n
end

--- Bankéřské zaokrouhlení (polovina k sudému) jako round() v Pythonu.
local function round_even(x)
  local f = math.floor(x)
  local d = x - f
  if d > 0.5 then return f + 1 end
  if d < 0.5 then return f end
  return (f % 2 == 0) and f or f + 1
end

--- Společná logika min/max (sign = -1 pro min, 1 pro max).
local function extreme(name, sign, ...)
  local n = select("#", ...)
  if n == 0 then raise("arg-count", name, "1+", 0) end
  local arr, count
  if n == 1 then arr, count = collect((...)) else arr, count = { ... }, n end
  if count == 0 then raise("empty-sequence", name) end
  local best = arr[1]
  for i = 2, count do
    if R.cmp(arr[i], best, name) * sign > 0 then best = arr[i] end
  end
  return best
end

function B.abs(...)
  argc("abs", select("#", ...), 1)
  local x = R.numv((...))
  if not x then raise("type-error-unary", "abs", R.typename((...))) end
  return math.abs(x)
end

function B.min(...) return extreme("min", -1, ...) end
function B.max(...) return extreme("max", 1, ...) end

function B.round(...)
  local n = select("#", ...)
  argc("round", n, 1, 2)
  local x, digits = ...
  x = R.numv(x) or raise("type-error-unary", "round", R.typename(x))
  if n == 1 then return round_even(x) end
  local m = 10 ^ int_of(digits)
  return round_even(x * m) / m
end

function B.int(...)
  argc("int", select("#", ...), 1)
  local v = ...
  if type(v) == "string" then
    local s = v:match("^%s*([%+%-]?%d+)%s*$")
    if not s then raise("bad-int", R.repr(v)) end
    return tonumber(s)
  end
  local x = R.numv(v)
  if not x then raise("bad-int", R.repr(v)) end
  return x >= 0 and math.floor(x) or math.ceil(x)
end

function B.float(...)
  argc("float", select("#", ...), 1)
  local v = ...
  if type(v) == "string" then
    local x = tonumber(v:match("^%s*(.-)%s*$"))
    if not x then raise("bad-float", R.repr(v)) end
    return x
  end
  return R.numv(v) or raise("bad-float", R.repr(v))
end

function B.str(...) argc("str", select("#", ...), 1); return R.str((...)) end
function B.bool(...) argc("bool", select("#", ...), 1); return R.truthy((...)) end

function B.len(...)
  argc("len", select("#", ...), 1)
  local v = ...
  if type(v) == "string" then return #v end
  local mt = getmetatable(v)
  if mt == R.ListMT or mt == R.TupleMT then return v.n end
  if mt == R.DictMT then return #v.keys end
  if mt and mt.__len_py then return mt.__len_py(v) end
  raise("type-error-unary", "len", R.typename(v))
end

--- Parametry range() → první, poslední (včetně) a krok pro číselný for Lua.
--- @return number first, number last, number step
function R.range_bounds(a, b, c)
  local start, stop, step
  if b == nil then start, stop, step = 0, int_of(a), 1
  else start, stop, step = int_of(a), int_of(b), (c == nil) and 1 or int_of(c) end
  if step == 0 then raise("range-step-zero") end
  if step > 0 then return start, stop - 1, step end
  return start, stop + 1, step
end

function B.range(...)
  argc("range", select("#", ...), 1, 3)
  local first, last, step = R.range_bounds(...)
  local arr, n = {}, 0
  for i = first, last, step do n = n + 1; arr[n] = i end
  return R.list(arr, n)
end

function B.sum(...)
  local n = select("#", ...)
  argc("sum", n, 1, 2)
  local it, start = ...
  local total = (n == 2) and start or 0
  for x in R.iter(it) do total = R.add(total, x) end
  return total
end

function B.sorted(...)
  argc("sorted", select("#", ...), 1)
  local arr, n = collect((...))
  table.sort(arr, function(x, y) return R.cmp(x, y, "sorted") < 0 end)
  return R.list(arr, n)
end

--- Text řádku print(): argumenty přes str() oddělené mezerou.
function R.print_line(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = R.str((select(i, ...))) end
  return table.concat(parts, " ")
end

--- Zásah watchdogu (limit do hlášky doplní VM).
function R.watchdog() raise("watchdog") end

-- Metody podle typu: METHODS[jméno typu][jméno metody] = function(self, n, ...)
local METHODS = { list = {}, dict = {}, str = {} }
R.METHODS = METHODS

local LM, DM, SM = METHODS.list, METHODS.dict, METHODS.str

function LM.append(l, n, x) argc("append", n, 1); l.n = l.n + 1; l[l.n] = x; return R.None end

function LM.pop(l, n, i)
  argc("pop", n, 0, 1)
  if l.n == 0 then raise("pop-empty", "list") end
  local idx = (n == 0) and l.n or nil
  if not idx then
    idx = int_of(i)
    if idx < 0 then idx = idx + l.n end
    if idx < 0 or idx >= l.n then raise("index-error") end
    idx = idx + 1
  end
  local v = table.remove(l, idx)
  l.n = l.n - 1
  return v
end

function LM.insert(l, n, i, x)
  argc("insert", n, 2)
  local idx = int_of(i)
  if idx < 0 then idx = math.max(0, idx + l.n) end
  idx = math.min(idx, l.n)
  table.insert(l, idx + 1, x)
  l.n = l.n + 1
  return R.None
end

function LM.index(l, n, x)
  argc("index", n, 1)
  for i = 1, l.n do if R.eq(l[i], x) then return i - 1 end end
  raise("not-in-list")
end

function LM.remove(l, n, x)
  argc("remove", n, 1)
  local i = LM.index(l, 1, x)
  table.remove(l, i + 1)
  l.n = l.n - 1
  return R.None
end

function LM.clear(l, n)
  argc("clear", n, 0)
  for i = l.n, 1, -1 do l[i] = nil end
  l.n = 0
  return R.None
end

function DM.get(d, n, k, default)
  argc("get", n, 1, 2)
  local v = R.dict_get(d, k)
  if v ~= nil then return v end
  if n == 2 then return default end
  return R.None
end

--- Seznam z klíčů dict převedených funkcí f(klíč).
local function dict_list(d, f)
  local arr = {}
  for i, k in ipairs(d.keys) do arr[i] = f(k) end
  return R.list(arr, #d.keys)
end

function DM.items(d, n)
  argc("items", n, 0)
  return dict_list(d, function(k) return R.tuple({ k, R.dict_get(d, k) }, 2) end)
end
function DM.keys(d, n) argc("keys", n, 0); return dict_list(d, function(k) return k end) end
function DM.values(d, n) argc("values", n, 0); return dict_list(d, function(k) return R.dict_get(d, k) end) end

function DM.pop(d, n, k, default)
  argc("pop", n, 1, 2)
  local v = R.dict_del(d, k)
  if v ~= nil then return v end
  if n == 2 then return default end
  raise("key-error", R.repr(k))
end

function DM.clear(d, n)
  argc("clear", n, 0)
  d.keys, d.vals = {}, {}
  return R.None
end

--- Ověří, že argument je řetězec.
local function strarg(name, v)
  if type(v) ~= "string" then raise("type-error", name, "str", R.typename(v)) end
  return v
end

function SM.upper(s, n) argc("upper", n, 0); return s:upper() end
function SM.lower(s, n) argc("lower", n, 0); return s:lower() end

function SM.startswith(s, n, p)
  argc("startswith", n, 1)
  p = strarg("startswith", p)
  return s:sub(1, #p) == p
end

function SM.endswith(s, n, p)
  argc("endswith", n, 1)
  p = strarg("endswith", p)
  return p == "" or s:sub(-#p) == p
end

function SM.split(s, n, sep)
  argc("split", n, 0, 1)
  local arr = {}
  if n == 0 or getmetatable(sep) == R.NoneMT then
    for w in s:gmatch("%S+") do arr[#arr + 1] = w end
  else
    sep = strarg("split", sep)
    if sep == "" then raise("empty-sequence", "split") end
    local start = 1
    while true do
      local i, j = s:find(sep, start, true)
      if not i then arr[#arr + 1] = s:sub(start); break end
      arr[#arr + 1] = s:sub(start, i - 1)
      start = j + 1
    end
  end
  return R.list(arr, #arr)
end

function SM.join(s, n, it)
  argc("join", n, 1)
  local parts = {}
  for x in R.iter(it) do parts[#parts + 1] = strarg("join", x) end
  return table.concat(parts, s)
end

function SM.replace(s, n, old, new)
  argc("replace", n, 2)
  old, new = strarg("replace", old), strarg("replace", new)
  if old == "" then return s end
  local out, start = {}, 1
  while true do
    local i, j = s:find(old, start, true)
    if not i then out[#out + 1] = s:sub(start); break end
    out[#out + 1] = s:sub(start, i - 1)
    out[#out + 1] = new
    start = j + 1
  end
  return table.concat(out)
end

--- Volání metody obj.name(...) s kontrolou existence.
function R.method(obj, name, ...)
  local tn = R.typename(obj)
  local mt = getmetatable(obj)
  local m = (METHODS[tn] and METHODS[tn][name]) or (mt and mt.__methods and mt.__methods[name])
  if not m then raise("unknown-method", name, tn) end
  return m(obj, select("#", ...), ...)
end

return R
```

- [ ] **Step 4: Implementace `signal_io.lua`**

`Pythonator/scripts/lang/signal_io.lua`:
```lua
--- Objekty signálů pro program: čtení vstupů (inp/red/green) a zápis výstupů (out/out_red/out_green).
local R = require("scripts.lang.builtins")

local M = {}

local ReaderMT = { __pyntr = "signals" }
local WriterMT = { __pyntr = "signals" }
M.ReaderMT, M.WriterMT = ReaderMT, WriterMT

--- Kanonický klíč z hodnoty klíče, jinak chyba resolveru.
local function canon(obj, key)
  if type(key) ~= "string" then R.raise("bad-signal-key", R.typename(key)) end
  local _, c, err = obj.resolver:resolve(key)
  if not c then error(err, 0) end
  return c
end

--- Vytvoří čtecí objekt.
--- @param source table {get = function(canonical) → number, all = function() → { {klíč, hodnota}… }}
--- @param resolver table z signals.new_resolver
function M.reader(source, resolver)
  return setmetatable({ source = source, resolver = resolver }, ReaderMT)
end

--- Vytvoří zapisovací objekt nad úložištěm kanonický klíč → int32.
--- @param store table úložiště (tatáž tabulka zůstává, clear ji jen vyprázdní)
--- @param resolver table z signals.new_resolver
function M.writer(store, resolver)
  return setmetatable({ store = store, resolver = resolver }, WriterMT)
end

--- Dvojice (klíč, hodnota) všech nenulových signálů objektu.
local function pairs_of(obj)
  if getmetatable(obj) == ReaderMT then return obj.source.all() end
  local keys = {}
  for k in pairs(obj.store) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for i, k in ipairs(keys) do out[i] = { k, obj.store[k] } end
  return out
end

--- Hodnota signálu (0, pokud chybí).
local function get(obj, key)
  local c = canon(obj, key)
  if getmetatable(obj) == ReaderMT then return obj.source.get(c) end
  return obj.store[c] or 0
end

--- Seznam z dvojic převedených funkcí f.
local function list_of(obj, f)
  local arr = {}
  for i, p in ipairs(pairs_of(obj)) do arr[i] = f(p) end
  return R.list(arr, #arr)
end

local common = {
  get = function(obj, n, key, default)
    if n < 1 or n > 2 then R.raise("arg-count", "get", "1–2", n) end
    local v = get(obj, key)
    if v == 0 and n == 2 then return default end
    return v
  end,
  items = function(obj) return list_of(obj, function(p) return R.tuple({ p[1], p[2] }, 2) end) end,
  keys = function(obj) return list_of(obj, function(p) return p[1] end) end,
  values = function(obj) return list_of(obj, function(p) return p[2] end) end,
}

local writer_methods = {
  get = common.get, items = common.items, keys = common.keys, values = common.values,
  clear = function(obj)
    for k in pairs(obj.store) do obj.store[k] = nil end
    return R.None
  end,
}

for _, mt in ipairs({ ReaderMT, WriterMT }) do
  mt.__getitem = get
  mt.__contains = function(obj, key) return get(obj, key) ~= 0 end
  mt.__len_py = function(obj) return #pairs_of(obj) end
  mt.__repr_py = function(obj) return R.repr(common.items(obj)) end
  mt.__iter = function(obj)
    local ps, i = pairs_of(obj), 0
    return function() i = i + 1; return ps[i] and ps[i][1] end
  end
end
ReaderMT.__methods = common
WriterMT.__methods = writer_methods

ReaderMT.__setitem = function() R.raise("readonly-signal", "inp") end

WriterMT.__setitem = function(obj, key, value)
  local c = canon(obj, key)
  local x = R.numv(value)
  if not x then R.raise("type-error", "=", "signal", R.typename(value)) end
  x = R.wrap32(x >= 0 and math.floor(x) or math.ceil(x))
  if x == 0 then obj.store[c] = nil else obj.store[c] = x end
end

return M
```

- [ ] **Step 5: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=114 fail=0`

- [ ] **Step 6: Commit**

```bash
git add Pythonator/scripts/lang/builtins.lua Pythonator/scripts/lang/signal_io.lua tests/unit
git commit -m "Runtime: vestavěné funkce, metody list/dict/str, objekty signálů"
```

---

### Task 7: Checker (`checker.lua`)

**Files:**
- Create: `Pythonator/scripts/lang/checker.lua`
- Create: `tests/unit/test_checker.lua`
- Modify: `tests/unit/run.lua` (přidat `"test_checker"`)

**Interfaces:**
- Consumes: `parser.parse` (AST), `signals.from_tag`, `resolver:resolve`, `errors.raise`
- Produces: `checker.check(ast, resolver) → info` a **mutuje AST**: každý konstantní klíč signálu (`Signal` uzel kdekoli, `Str` jako index/`in`/první argument `.get()` u objektu signálů) se přepíše na `{k="Str", v=<kanonický klíč>}`.
  - `info.globals` – množina jmen globálních proměnných
  - `info.functions[jméno] = {node, params, locals (množina), global_decl (množina)}`
  - `info.config = {interval = 1, outputs = "hold"}` (z `config()` na nejvyšší úrovni)
  - konstanty `checker.SIGNAL_OBJS` (`inp/red/green` = `"r"`, `out/out_red/out_green` = `"w"`), `checker.READONLY` (`tick game_tick dt`), `checker.BUILTINS`.

Pravidla: jméno přiřazené ve funkci je lokální, pokud není v `global`; je-li to zároveň globál → `missing-global`. Parametry smí zastínit globál. Funkce, vestavěné funkce, `config`, objekty signálů a `tick/game_tick/dt` nejsou přiřaditelné (`reserved-name`). Funkce a vestavěné funkce nejsou hodnoty (`function-value`). Objekt signálů smí stát jen jako indexovaný výraz, objekt metody, pravý operand `in`/`not in` a argument `len()`; jinde `signal-value`. Neznámé jméno je chyba už při překladu.

- [ ] **Step 1: Padající testy**

`tests/unit/test_checker.lua`:
```lua
local A = require("assert")
local parser = require("scripts.lang.parser")
local checker = require("scripts.lang.checker")
local signals = require("scripts.lang.signals")
local fake = require("fake_protos")

--- Rozparsuje a zkontroluje zdroj; vrátí info a AST.
local function check(src)
  local ast = parser.parse(src)
  return checker.check(ast, signals.new_resolver(fake())), ast
end

--- Ověří chybu kontroly a vrátí ji.
local function bad(src, key) return A.raises(function() check(src) end, key) end

return {
  { "minimální program", function()
    local info = check("def loop():\n  pass")
    A.same(info.config, { interval = 1, outputs = "hold" }, "výchozí config")
  end },
  { "chybí loop / loop s parametry", function()
    bad("x = 1", "missing-loop")
    bad("def loop(a):\n  pass", "loop-params")
  end },
  { "globální a lokální jména", function()
    local info = check("count = 0\ndef loop():\n  global count\n  x = 1\n  count += x")
    A.eq(info.globals.count, true, "count je globál")
    A.eq(info.functions.loop.locals.x, true, "x je lokální")
    A.eq(info.functions.loop.locals.count, nil, "count není lokální")
  end },
  { "chybějící global", function()
    local e = bad("count = 0\ndef loop():\n  count += 1", "missing-global")
    A.eq(e.line, 3, "řádek"); A.eq(e.args[1], "count", "jméno")
  end },
  { "mutace globálu bez global je OK", function()
    check("d = {}\ndef loop():\n  d['a'] = 1\n  d.clear()")
  end },
  { "neznámé jméno", function()
    A.eq(bad("def loop():\n  x = y", "unknown-name").args[1], "y", "jméno")
  end },
  { "funkce není hodnota", function()
    bad("def f():\n  pass\ndef loop():\n  x = f", "function-value")
    bad("def loop():\n  x = len", "function-value")
  end },
  { "vyhrazená jména", function()
    bad("def loop():\n  tick = 1", "reserved-name")
    bad("inp = 1\ndef loop(): pass", "reserved-name")
    bad("def len(x): pass\ndef loop(): pass", "reserved-name")
    bad("def f(): pass\nf = 1\ndef loop(): pass", "reserved-name")
  end },
  { "vnořená a podmíněná definice", function()
    bad("def loop():\n  def g():\n    pass", "nested-def")
    bad("if True:\n  def f():\n    pass\ndef loop(): pass", "nested-def")
  end },
  { "dvojí definice", function() bad("def loop(): pass\ndef loop(): pass", "duplicate-def") end },
  { "počet argumentů", function()
    A.same(bad("def f(a):\n  return a\ndef loop():\n  f(1, 2)", "arg-count").args, { "f", "1", "2" }, "argumenty")
  end },
  { "break / return mimo kontext", function()
    A.eq(bad("def loop():\n  break", "outside-loop").args[1], "break", "break")
    check("def loop():\n  for i in range(3):\n    if i: continue\n    break")
    bad("return 1\ndef loop(): pass", "return-outside")
  end },
  { "config", function()
    local info = check("config(interval=10, outputs='clear')\ndef loop(): pass")
    A.same(info.config, { interval = 10, outputs = "clear" }, "hodnoty")
    bad("config(interval=0)\ndef loop(): pass", "bad-config")
    bad("config(5)\ndef loop(): pass", "bad-config")
    bad("def loop():\n  config(interval=2)", "bad-config")
    bad("x = config(interval=2)\ndef loop(): pass", "bad-config")
  end },
  { "klíče signálů se přepíšou na kanonické", function()
    local _, ast = check("def loop():\n  out['signal-A'] = inp[[item=iron-plate]]\n  y = inp['item:iron-plate']")
    local body = ast.body[1].body
    A.same({ body[1].targets[1].index.k, body[1].targets[1].index.v }, { "Str", "signal-A" }, "cíl")
    A.same({ body[1].value.index.k, body[1].value.index.v }, { "Str", "iron-plate" }, "tag")
    A.eq(body[2].value.index.v, "iron-plate", "zbytečný prefix")
  end },
  { "neznámý klíč signálu s pozicí", function()
    local e = bad("def loop():\n  x = inp['iron-plates']", "unknown-signal")
    A.eq(e.line, 2, "řádek"); A.eq(e.col, 11, "sloupec")
  end },
  { "vstup nelze zapisovat", function()
    A.eq(bad("def loop():\n  inp['signal-A'] = 1", "readonly-signal").args[1], "inp", "jméno")
  end },
  { "objekt signálů jen v povolených místech", function()
    bad("def loop():\n  x = inp", "signal-value")
    local _, ast = check(table.concat({
      "def loop():",
      "  n = len(inp)",
      "  b = 'signal-A' in inp",
      "  v = red.get([virtual-signal=signal-B], 0)",
      "  for k, v in green.items():",
      "    pass",
    }, "\n"))
    local body = ast.body[1].body
    A.eq(body[2].value.left.v, "signal-A", "klíč u in")
    A.eq(body[3].value.args[1].v, "signal-B", "klíč u get")
  end },
  { "signál jako hodnota mimo index", function()
    local _, ast = check("K = [virtual-signal=signal-A]\ndef loop(): pass")
    A.same({ ast.body[1].value.k, ast.body[1].value.v }, { "Str", "signal-A" }, "konstanta")
  end },
  { "dynamický klíč se neověřuje", function()
    check("def loop():\n  k = 'xyz'\n  y = inp[k]")
  end },
  { "nevolatelné a pojmenované argumenty", function()
    bad("x = 1\ndef loop():\n  x()", "not-callable")
    bad("def f(a):\n  return a\ndef loop():\n  f(a=1)", "kwargs-unsupported")
  end },
  { "parametr smí zastínit globál", function()
    check("a = 1\ndef f(a):\n  return a\ndef loop():\n  f(2)")
  end },
}
```
Přidat `"test_checker"` do `SUITES`.

- [ ] **Step 2: Spustit – musí selhat**

Run: `bash tools/run-unit.sh`
Expected: FAIL `module 'scripts.lang.checker' not found`

- [ ] **Step 3: Implementace**

`Pythonator/scripts/lang/checker.lua`:
```lua
--- Kontrola programu: rozsahy jmen, global/local, omezení jazyka, klíče signálů → kanonické řetězce.
local errors = require("scripts.lang.errors")
local signals = require("scripts.lang.signals")

local M = {}

M.SIGNAL_OBJS = { inp = "r", red = "r", green = "r", out = "w", out_red = "w", out_green = "w" }
M.READONLY = { tick = true, game_tick = true, dt = true }
M.BUILTINS = {}
for w in ("abs min max round int float str bool len range sum sorted print"):gmatch("%S+") do M.BUILTINS[w] = true end

--- Je uzel holé jméno objektu signálů?
local function is_sigobj(e) return e.k == "Name" and M.SIGNAL_OBJS[e.id] ~= nil end

--- Jména přiřazovaná cílem (uzly Name; Subscript nic nepřiřazuje).
local function target_names(t, out)
  if t.k == "Name" then
    out[#out + 1] = t
  elseif t.k == "Tuple" or t.k == "List" then
    for _, e in ipairs(t.elts) do target_names(e, out) end
  end
end

--- Projde příkazy včetně vnořených bloků (bez vstupu do Def) a zavolá f(stmt).
local function walk_stmts(body, f)
  for _, s in ipairs(body) do
    f(s)
    if s.k == "If" then
      walk_stmts(s.body, f)
      walk_stmts(s.orelse, f)
    elseif s.k == "While" or s.k == "For" then
      walk_stmts(s.body, f)
    end
  end
end

--- Uzly Name přiřazené v těle (Assign, AugAssign, For).
local function assigned_in(body)
  local names = {}
  walk_stmts(body, function(s)
    if s.k == "Assign" then
      for _, t in ipairs(s.targets) do target_names(t, names) end
    elseif s.k == "AugAssign" or s.k == "For" then
      target_names(s.target, names)
    end
  end)
  return names
end

local C = {}
C.__index = C

--- Je jméno vyhrazené (nelze přiřadit)?
function C:reserved(name)
  return self.info.functions[name] ~= nil or M.BUILTINS[name] or M.READONLY[name]
    or M.SIGNAL_OBJS[name] ~= nil or name == "config"
end

--- Ověří, že do jména (uzel Name) lze přiřadit.
function C:assignable(n)
  if self:reserved(n.id) then errors.raise(n.line, n.col, "reserved-name", n.id) end
end

--- Přepíše konstantní klíč signálu (Signal nebo Str) na kanonický Str; jiné uzly nechá být.
function C:resolve_key(node)
  local key
  if node.k == "Signal" then
    key = signals.from_tag(node.tag, node.name, node.quality)
  elseif node.k == "Str" then
    key = node.v
  else
    return
  end
  local _, canonical, err = self.resolver:resolve(key)
  if not canonical then
    err.line, err.col = node.line, node.col
    error(err, 0)
  end
  node.k, node.v, node.stype, node.tag, node.name, node.quality = "Str", canonical, nil, nil, nil, nil
end

--- Kontrola čteného jména.
function C:load_name(e, ctx)
  local id = e.id
  if ctx.fn and ctx.fn.locals[id] then return end
  if self.info.globals[id] or M.READONLY[id] then return end
  if self.info.functions[id] or M.BUILTINS[id] or id == "config" then
    errors.raise(e.line, e.col, "function-value", id)
  end
  if M.SIGNAL_OBJS[id] then errors.raise(e.line, e.col, "signal-value", id) end
  errors.raise(e.line, e.col, "unknown-name", id)
end

--- Kontrola výrazu.
function C:expr(e, ctx)
  local k = e.k
  if k == "Name" then
    self:load_name(e, ctx)
  elseif k == "Signal" then
    self:resolve_key(e)
  elseif k == "BinOp" then
    self:expr(e.left, ctx); self:expr(e.right, ctx)
  elseif k == "UnaryOp" then
    self:expr(e.operand, ctx)
  elseif k == "BoolOp" then
    for _, v in ipairs(e.values) do self:expr(v, ctx) end
  elseif k == "IfExp" then
    self:expr(e.test, ctx); self:expr(e.body, ctx); self:expr(e.orelse, ctx)
  elseif k == "Compare" then
    local operands = { e.left }
    for _, c in ipairs(e.comparators) do operands[#operands + 1] = c end
    for j, o in ipairs(operands) do
      local op = e.ops[j - 1]
      if (op == "in" or op == "not in") and is_sigobj(o) then
        self:resolve_key(operands[j - 1])
      else
        self:expr(o, ctx)
      end
    end
  elseif k == "Call" then
    self:call(e, ctx)
  elseif k == "Method" then
    if is_sigobj(e.obj) then
      if e.name == "get" and e.args[1] then self:resolve_key(e.args[1]) end
    else
      self:expr(e.obj, ctx)
    end
    for _, a in ipairs(e.args) do self:expr(a, ctx) end
  elseif k == "Subscript" then
    if is_sigobj(e.value) then
      self:resolve_key(e.index)
    else
      self:expr(e.value, ctx)
    end
    self:expr(e.index, ctx)
  elseif k == "Slice" then
    self:expr(e.value, ctx)
    if e.lower then self:expr(e.lower, ctx) end
    if e.upper then self:expr(e.upper, ctx) end
  elseif k == "List" or k == "Tuple" then
    for _, v in ipairs(e.elts) do self:expr(v, ctx) end
  elseif k == "Dict" then
    for i, key in ipairs(e.keys) do self:expr(key, ctx); self:expr(e.values[i], ctx) end
  end
end

--- Kontrola volání funkce.
function C:call(e, ctx)
  local name = e.func
  if name == "config" then errors.raise(e.line, e.col, "bad-config") end
  if #e.kwargs > 0 then errors.raise(e.kwargs[1].line, e.kwargs[1].col, "kwargs-unsupported") end
  local fn = self.info.functions[name]
  if fn then
    if #e.args ~= #fn.params then errors.raise(e.line, e.col, "arg-count", name, #fn.params, #e.args) end
  elseif not M.BUILTINS[name] then
    if (ctx.fn and ctx.fn.locals[name]) or self.info.globals[name] or M.READONLY[name] or M.SIGNAL_OBJS[name] then
      errors.raise(e.line, e.col, "not-callable")
    end
    errors.raise(e.line, e.col, "unknown-name", name)
  end
  for _, a in ipairs(e.args) do
    if not (name == "len" and is_sigobj(a)) then self:expr(a, ctx) end
  end
end

--- Kontrola cíle přiřazení (čtení indexů, zápis do objektů signálů).
function C:target(t, ctx)
  if t.k == "Subscript" then
    if is_sigobj(t.value) then
      if M.SIGNAL_OBJS[t.value.id] == "r" then errors.raise(t.line, t.col, "readonly-signal", t.value.id) end
      self:resolve_key(t.index)
    else
      self:expr(t.value, ctx)
    end
    self:expr(t.index, ctx)
  elseif t.k == "Tuple" or t.k == "List" then
    for _, el in ipairs(t.elts) do self:target(el, ctx) end
  end
end

--- Zpracuje config() na nejvyšší úrovni.
function C:config(call, ctx)
  if ctx.fn or not ctx.top or #call.args > 0 then errors.raise(call.line, call.col, "bad-config") end
  for _, kw in ipairs(call.kwargs) do
    local v = kw.value
    if kw.name == "interval" and v.k == "Num" and v.v >= 1 and v.v == math.floor(v.v) then
      self.info.config.interval = v.v
    elseif kw.name == "outputs" and v.k == "Str" and (v.v == "hold" or v.v == "clear") then
      self.info.config.outputs = v.v
    else
      errors.raise(kw.line, kw.col, "bad-config")
    end
  end
end

--- Podkontext bloku (už ne přímo nejvyšší úroveň).
local function sub(ctx, loops) return { fn = ctx.fn, loops = loops or ctx.loops, top = false } end

--- Kontrola příkazu.
function C:stmt(s, ctx)
  local k = s.k
  if k == "Def" then
    if ctx.fn or not ctx.top then errors.raise(s.line, s.col, "nested-def") end
    self:stmts(s.body, { fn = self.info.functions[s.name], loops = 0, top = false })
  elseif k == "Assign" then
    self:expr(s.value, ctx)
    for _, t in ipairs(s.targets) do self:target(t, ctx) end
  elseif k == "AugAssign" then
    self:expr(s.target, ctx)
    self:target(s.target, ctx)
    self:expr(s.value, ctx)
  elseif k == "Expr" then
    if s.value.k == "Call" and s.value.func == "config" then
      self:config(s.value, ctx)
    else
      self:expr(s.value, ctx)
    end
  elseif k == "If" then
    self:expr(s.test, ctx)
    self:stmts(s.body, sub(ctx))
    self:stmts(s.orelse, sub(ctx))
  elseif k == "While" then
    self:expr(s.test, ctx)
    self:stmts(s.body, sub(ctx, ctx.loops + 1))
  elseif k == "For" then
    self:expr(s.iter, ctx)
    self:target(s.target, ctx)
    self:stmts(s.body, sub(ctx, ctx.loops + 1))
  elseif k == "Return" then
    if not ctx.fn then errors.raise(s.line, s.col, "return-outside") end
    if s.value then self:expr(s.value, ctx) end
  elseif k == "Break" or k == "Continue" then
    if ctx.loops == 0 then errors.raise(s.line, s.col, "outside-loop", k == "Break" and "break" or "continue") end
  end
end

function C:stmts(body, ctx)
  for _, s in ipairs(body) do self:stmt(s, ctx) end
end

--- Zkontroluje program a přepíše konstantní klíče signálů na kanonické.
--- @param ast table Module z parser.parse
--- @param resolver table z signals.new_resolver
--- @return table info {globals, functions, config}
function M.check(ast, resolver)
  local info = { globals = {}, functions = {}, config = { interval = 1, outputs = "hold" } }
  local self = setmetatable({ info = info, resolver = resolver }, C)
  local defs = {}
  for _, s in ipairs(ast.body) do
    if s.k == "Def" then
      if info.functions[s.name] then errors.raise(s.line, s.col, "duplicate-def", s.name) end
      if M.BUILTINS[s.name] or M.READONLY[s.name] or M.SIGNAL_OBJS[s.name] or s.name == "config" then
        errors.raise(s.line, s.col, "reserved-name", s.name)
      end
      info.functions[s.name] = { node = s, params = s.params, locals = {}, global_decl = {} }
      defs[#defs + 1] = info.functions[s.name]
    end
  end
  local loop = info.functions.loop
  if not loop then errors.raise(1, 1, "missing-loop") end
  if #loop.params > 0 then errors.raise(loop.node.line, loop.node.col, "loop-params") end

  for _, n in ipairs(assigned_in(ast.body)) do
    self:assignable(n)
    info.globals[n.id] = true
  end
  for _, fn in ipairs(defs) do
    walk_stmts(fn.node.body, function(s)
      if s.k == "Global" then
        for _, g in ipairs(s.names) do fn.global_decl[g] = true; info.globals[g] = true end
      end
    end)
  end
  for _, fn in ipairs(defs) do
    for _, p in ipairs(fn.params) do fn.locals[p] = true end
    for _, n in ipairs(assigned_in(fn.node.body)) do
      self:assignable(n)
      if not fn.global_decl[n.id] and not fn.locals[n.id] then
        if info.globals[n.id] then errors.raise(n.line, n.col, "missing-global", n.id) end
        fn.locals[n.id] = true
      end
    end
  end

  self:stmts(ast.body, { fn = nil, loops = 0, top = true })
  return info
end

return M
```

- [ ] **Step 4: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=135 fail=0`

- [ ] **Step 5: Commit**

```bash
git add Pythonator/scripts/lang/checker.lua tests/unit
git commit -m "Checker: rozsahy jmen, global, omezení jazyka, kanonické klíče signálů"
```

---

### Task 8: Generátor kódu, překladač, VM

**Files:**
- Create: `Pythonator/scripts/lang/codegen.lua`, `Pythonator/scripts/lang/compiler.lua`, `Pythonator/scripts/lang/vm.lua`
- Create: `tests/unit/prog_runner.lua` (spuštění programu v testech; použije i úloha 9), `tests/unit/test_compiler.lua`
- Modify: `tests/unit/run.lua` (přidat `"test_compiler"`)

**Interfaces:**
- Consumes: `parser.parse`, `checker.check` (+ `checker.READONLY`, `checker.SIGNAL_OBJS`), runtime `R` přes `require("scripts.lang.builtins")`, `signal_io` (jen v testech)
- Produces:
  - `codegen.generate(ast, info) → string` – chunk Lua 5.2 vracející `function(R, G, IO)`
  - `compiler.compile(source, resolver) → program` nebo `nil, err`; `program = {factory, config, lua}`
  - `vm.instantiate(program, G, IO) → inst` s `inst.init()`, `inst.loop()`, `inst.set_budget(n)`, `inst.budget()`, `inst.line()`
  - `vm.run(inst, "init"|"loop", limit) → ok, err|nil, used`
  - `vm.memory(G, limit) → total, biggest|nil`; `vm.check_memory(G, limit) → err|nil`
  - `IO` = `{inp, red, green, out, out_red, out_green, print = function(text), tick, game_tick, dt}` (hostitel aktualizuje `tick/game_tick/dt` před každým `loop`)

Mapování jmen ve vygenerovaném kódu: lokální `l_<jméno>`, globální `G["<jméno>"]`, funkce `f_<jméno>` (hoistované), `tick/game_tick/dt/inp/…` → `IO.<jméno>`, vestavěné `B.<jméno>`, `print` → `print_`. Každý příkaz začíná `_ln = <řádek>;`. Watchdog `_b = _b - 1 if _b < 0 then wd() end` na začátku každé funkce a každého průchodu cyklem. `continue` = `goto c<N>` na štítek na konci těla cyklu (tělo nemá lokální proměnné na úrovni bloku – dočasné hodnoty jsou v `do … end`). Řetězené porovnání s neprostými operandy a podmíněný výraz používají okamžitě volanou funkci (zachová zkrácené vyhodnocení).

- [ ] **Step 1: Pomocník pro spouštění programů v testech**

`tests/unit/prog_runner.lua`:
```lua
--- Spouštění programů Pythonatoru v testech: překlad, init a n× loop s falešnými vstupy/výstupy.
local compiler = require("scripts.lang.compiler")
local vm = require("scripts.lang.vm")
local signals = require("scripts.lang.signals")
local signal_io = require("scripts.lang.signal_io")
local fake = require("fake_protos")

local P = {}

--- Přeloží zdroj; při chybě ji vyhodí (pro testy úspěšných programů).
function P.program(src)
  local prog, err = compiler.compile(src, signals.new_resolver(fake()))
  if not prog then error(err, 0) end
  return prog
end

--- Spustí init a `ticks`× loop.
--- @param src string
--- @param ticks integer|nil počet ticků (výchozí 1)
--- @param values table|nil vstupní signály kanonický klíč → hodnota (inp i red)
--- @return table|nil result {lines (spojené "|"), G, out, prog}
--- @return table|nil err
function P.run(src, ticks, values)
  local prog = P.program(src)
  local resolver = signals.new_resolver(fake())
  local lines, store = {}, {}
  values = values or {}
  local source = {
    get = function(k) return values[k] or 0 end,
    all = function()
      local keys = {}
      for k in pairs(values) do keys[#keys + 1] = k end
      table.sort(keys)
      local out = {}
      for i, k in ipairs(keys) do out[i] = { k, values[k] } end
      return out
    end,
  }
  local empty = { get = function() return 0 end, all = function() return {} end }
  local IO = {
    inp = signal_io.reader(source, resolver), red = signal_io.reader(source, resolver),
    green = signal_io.reader(empty, resolver),
    out = signal_io.writer(store, resolver), out_red = signal_io.writer({}, resolver),
    out_green = signal_io.writer({}, resolver),
    print = function(s) lines[#lines + 1] = s end,
    tick = 0, game_tick = 0, dt = 1,
  }
  local G = {}
  local inst = vm.instantiate(prog, G, IO)
  local ok, err = vm.run(inst, "init", 10000)
  if not ok then return nil, err end
  for t = 0, (ticks or 1) - 1 do
    IO.tick, IO.game_tick = t, t
    ok, err = vm.run(inst, "loop", 10000)
    if not ok then return nil, err end
  end
  return { lines = table.concat(lines, "|"), G = G, out = store, prog = prog }
end

return P
```

- [ ] **Step 2: Padající testy**

`tests/unit/test_compiler.lua`:
```lua
local A = require("assert")
local P = require("prog_runner")
local compiler = require("scripts.lang.compiler")
local vm = require("scripts.lang.vm")
local signals = require("scripts.lang.signals")
local fake = require("fake_protos")

--- Spustí program a ověří výstup print (řádky spojené "|").
local function prints(src, expected, ticks)
  local res, err = P.run(src, ticks)
  if not res then error(err, 0) end
  A.eq(res.lines, expected, src)
  return res
end

--- Spustí program a ověří chybu běhu; vrátí ji.
local function fails(src, key, ticks)
  local res, err = P.run(src, ticks)
  A.eq(res, nil, "čekána chyba " .. key)
  A.eq(err.key, "pyntr-err." .. key, "klíč chyby")
  return err
end

return {
  { "print a aritmetika", function() prints("def loop():\n  print(1 + 2, 'a' * 2)", "3 aa") end },
  { "globály přežijí tick", function()
    local res = prints("count = 0\ndef loop():\n  global count\n  count += 1\n  print(count)", "1|2|3", 3)
    A.eq(res.G.count, 3, "G.count")
  end },
  { "hoisting funkcí a print v inicializaci", function()
    prints("print(f(2))\ndef f(x):\n  return x * 2\ndef loop(): pass", "4")
  end },
  { "rekurze", function()
    prints("def fib(n):\n  if n < 2:\n    return n\n  return fib(n - 1) + fib(n - 2)\ndef loop():\n  print(fib(10))", "55")
  end },
  { "while, break, continue", function()
    prints(table.concat({
      "def loop():",
      "  i = 0",
      "  s = 0",
      "  while True:",
      "    i += 1",
      "    if i > 9:",
      "      break",
      "    if i % 2 == 0:",
      "      continue",
      "    s += i",
      "  print(s)",
    }, "\n"), "25")
  end },
  { "for přes range ve všech tvarech", function()
    prints(table.concat({
      "def loop():",
      "  a = []",
      "  for i in range(3):",
      "    a.append(i)",
      "  for i in range(5, 0, -2):",
      "    a.append(i)",
      "  print(a, i)",
    }, "\n"), "[0, 1, 2, 5, 3, 1] 1")
  end },
  { "continue po rozbalení n-tice", function()
    prints(table.concat({
      "def loop():",
      "  d = {'a': 1, 'b': 2, 'c': 3}",
      "  s = 0",
      "  for k, v in d.items():",
      "    if k == 'b':",
      "      continue",
      "    s += v",
      "  print(s)",
    }, "\n"), "4")
  end },
  { "řetězené porovnání se zkratem", function()
    prints(table.concat({
      "def f(x):",
      "  print('f')",
      "  return x",
      "def loop():",
      "  print(0 < f(5) < 10)",
      "  print(5 < f(1) < f(9))",
    }, "\n"), "f|True|f|False")
  end },
  { "and/or vrací operand, podmíněný výraz", function()
    prints("def loop():\n  print(0 or 5, '' and 1, 1 and 2)\n  print('ano' if [] else 'ne')", "5  2|ne")
  end },
  { "rozbalení a řetězené přiřazení", function()
    prints("def loop():\n  a, b = 1, 2\n  a, b = b, a\n  x = y = []\n  x.append(1)\n  print(a, b, y)", "2 1 [1]")
  end },
  { "rozšířené přiřazení do indexu", function()
    prints("def loop():\n  d = {'k': 1}\n  d['k'] += 5\n  print(d)", "{'k': 6}")
  end },
  { "signály a config", function()
    local res = P.run(table.concat({
      "config(interval=5)",
      "def loop():",
      "  if inp['iron-plate'] > 100:",
      "    out['signal-A'] = 1",
      "  out[[recipe=iron-plate]] = 2",
      "  for k, v in inp.items():",
      "    print(k, v)",
    }, "\n"), 1, { ["iron-plate"] = 150 })
    A.same(res.out, { ["signal-A"] = 1, ["recipe:iron-plate"] = 2 }, "výstupy")
    A.eq(res.lines, "iron-plate 150", "items")
    A.eq(res.prog.config.interval, 5, "interval")
  end },
  { "chyba za běhu hlásí řádek Pythonu i ve funkci", function()
    local e = fails("def f(x):\n  return x // 0\ndef loop():\n  f(1)", "zero-division")
    A.eq(e.line, 2, "řádek")
  end },
  { "chyba v podmínce elif hlásí řádek elif", function()
    A.eq(fails("def loop():\n  x = 1\n  if x == 2:\n    pass\n  elif x // 0:\n    pass", "zero-division").line, 5, "řádek")
  end },
  { "chyba v inicializaci", function()
    A.eq(fails("x = 1 // 0\ndef loop(): pass", "zero-division").line, 1, "řádek")
  end },
  { "watchdog zastaví nekonečnou smyčku", function()
    local e = fails("def loop():\n  x = 0\n  while x < 10:\n    pass", "watchdog")
    A.eq(e.line, 3, "řádek"); A.eq(e.args[1], "10000", "limit")
  end },
  { "watchdog zastaví nekonečnou rekurzi", function()
    fails("def f():\n  return f() + 1\ndef loop():\n  f()", "watchdog")
  end },
  { "proměnná před přiřazením", function()
    A.eq(fails("def loop():\n  if False:\n    x = 1\n  print(x)", "unbound").line, 4, "řádek")
  end },
  { "watchdog a rozpočet: spotřeba", function()
    local prog = P.program("def loop():\n  for i in range(10):\n    pass")
    local inst = vm.instantiate(prog, {}, { print = print })
    local ok, _, used = vm.run(inst, "loop", 100)
    A.eq(ok, true, "běh"); A.eq(used, 11, "1 vstup do funkce + 10 průchodů")
  end },
  { "pojistka paměti", function()
    local res = P.run("log = []\ndef loop():\n  log.append(1)", 6)
    local total, biggest = vm.memory(res.G, 5)
    A.truthy(total > 5, "překročeno"); A.eq(biggest, "log", "největší")
    A.eq(vm.check_memory(res.G, 5).key, "pyntr-err.memory", "chyba")
    A.eq(vm.check_memory(res.G, 100), nil, "pod limitem")
  end },
  { "paměť s cyklem a sdílenou referencí", function()
    local res = P.run("a = []\na.append(a)\nb = a\ndef loop(): pass")
    local total = vm.memory(res.G, 100)
    A.eq(total, 1, "cyklus i sdílená reference se počítají jednou")
  end },
  { "chyba překladu se vrátí, nevyhodí", function()
    local prog, err = compiler.compile("def loop():\n  x = y", signals.new_resolver(fake()))
    A.eq(prog, nil, "program"); A.eq(err.key, "pyntr-err.unknown-name", "klíč"); A.eq(err.line, 2, "řádek")
  end },
  { "vygenerovaný kód nepoužívá operátory Lua 5.3", function()
    local lua = P.program("def loop():\n  x = 7 // 2 + (5 & 3) + (1 << 2) + (~1)\n  print(x)").lua
    for _, op in ipairs({ "//", " & ", " | ", "<<", ">>", " ~" }) do
      A.eq(lua:find(op, 1, true), nil, "operátor " .. op)
    end
  end },
}
```
Přidat `"test_compiler"` do `SUITES`.

- [ ] **Step 3: Spustit – musí selhat**

Run: `bash tools/run-unit.sh`
Expected: FAIL `module 'scripts.lang.compiler' not found`

- [ ] **Step 4: Implementace `codegen.lua`**

`Pythonator/scripts/lang/codegen.lua`:
```lua
--- Generátor: AST (po checkeru) → zdroj Lua 5.2 s watchdogem a sledováním řádku zdroje.
local checker = require("scripts.lang.checker")

local M = {}

--- Pomocné funkce runtime dostupné jako lokální proměnné vygenerovaného kódu.
local HELPERS = { "add", "sub", "mul", "truediv", "floordiv", "mod", "pow", "neg", "pos", "invert", "not_",
  "band", "bor", "bxor", "lshift", "rshift", "eq", "ne", "lt", "le", "gt", "ge", "contains", "is_",
  "truthy", "getitem", "setitem", "slice", "iter", "unpack", "method", "list", "tuple", "dict",
  "and_", "or_", "print_line", "range_bounds" }

local BINOP = { ["+"] = "add", ["-"] = "sub", ["*"] = "mul", ["/"] = "truediv", ["//"] = "floordiv",
  ["%"] = "mod", ["**"] = "pow", ["&"] = "band", ["|"] = "bor", ["^"] = "bxor", ["<<"] = "lshift", [">>"] = "rshift" }
local UNOP = { ["-"] = "neg", ["+"] = "pos", ["~"] = "invert", ["not"] = "not_" }
local CMPOP = { ["<"] = "lt", ["<="] = "le", [">"] = "gt", [">="] = "ge", ["=="] = "eq", ["!="] = "ne" }
local SIMPLE = { Name = true, Num = true, Str = true, Bool = true, None = true }
local WD = "_b = _b - 1 if _b < 0 then wd() end"

local Gen = {}
Gen.__index = Gen

function Gen:emit(line) self.out[#self.out + 1] = line end

--- Nové jméno dočasné proměnné.
function Gen:tmp()
  self.ntmp = self.ntmp + 1
  return "_t" .. self.ntmp
end

--- Číselný literál jako text Lua.
local function num(v)
  if v == math.huge then return "(1/0)" end
  if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
  return string.format("%.17g", v)
end

--- Výraz Lua pro čtení/zápis jména.
function Gen:name(id)
  if self.fn and self.fn.locals[id] then return "l_" .. id end
  if checker.READONLY[id] or checker.SIGNAL_OBJS[id] then return "IO." .. id end
  return string.format("G[%q]", id)
end

--- Jedno porovnání a op b jako Lua boolean.
local function cmp1(op, a, b)
  if op == "in" then return "contains(" .. b .. ", " .. a .. ")" end
  if op == "not in" then return "not contains(" .. b .. ", " .. a .. ")" end
  if op == "is" then return "is_(" .. a .. ", " .. b .. ")" end
  if op == "is not" then return "not is_(" .. a .. ", " .. b .. ")" end
  return CMPOP[op] .. "(" .. a .. ", " .. b .. ")"
end

--- Porovnání (i řetězené) jako Lua boolean výraz.
function Gen:compare(e)
  if #e.ops == 1 then return cmp1(e.ops[1], self:ex(e.left), self:ex(e.comparators[1])) end
  local simple = true
  for _, c in ipairs(e.comparators) do if not SIMPLE[c.k] then simple = false end end
  if simple then
    local operands, parts = { self:ex(e.left) }, {}
    for _, c in ipairs(e.comparators) do operands[#operands + 1] = self:ex(c) end
    for i, op in ipairs(e.ops) do parts[i] = cmp1(op, operands[i], operands[i + 1]) end
    return table.concat(parts, " and ")
  end
  local code = { "(function() local _a = " .. self:ex(e.left) }
  for i, op in ipairs(e.ops) do
    code[#code + 1] = "local _c = " .. self:ex(e.comparators[i])
    code[#code + 1] = "if not (" .. cmp1(op, "_a", "_c") .. ") then return false end"
    code[#code + 1] = "_a = _c"
  end
  code[#code + 1] = "return true end)()"
  return table.concat(code, " ")
end

--- Podmínka jako Lua boolean (bez obalování truthy, kde to jde).
function Gen:cond(e)
  local k = e.k
  if k == "Compare" then return "(" .. self:compare(e) .. ")" end
  if k == "Bool" then return e.v and "true" or "false" end
  if k == "UnaryOp" and e.op == "not" then return "not " .. self:cond(e.operand) end
  if k == "BoolOp" then
    local parts = {}
    for i, v in ipairs(e.values) do parts[i] = self:cond(v) end
    return "(" .. table.concat(parts, " " .. e.op .. " ") .. ")"
  end
  return "truthy(" .. self:ex(e) .. ")"
end

--- Volání funkce (uživatelské, print, vestavěné).
function Gen:call(e)
  local args = {}
  for i, a in ipairs(e.args) do args[i] = self:ex(a) end
  local list = table.concat(args, ", ")
  if self.info.functions[e.func] then return "f_" .. e.func .. "(" .. list .. ")" end
  if e.func == "print" then return "print_(" .. list .. ")" end
  return "B." .. e.func .. "(" .. list .. ")"
end

--- Výraz jako text Lua.
function Gen:ex(e)
  local k = e.k
  if k == "Num" then return num(e.v) end
  if k == "Str" then return string.format("%q", e.v) end
  if k == "Bool" then return e.v and "true" or "false" end
  if k == "None" then return "None" end
  if k == "Name" then return self:name(e.id) end
  if k == "BinOp" then return BINOP[e.op] .. "(" .. self:ex(e.left) .. ", " .. self:ex(e.right) .. ")" end
  if k == "UnaryOp" then return UNOP[e.op] .. "(" .. self:ex(e.operand) .. ")" end
  if k == "BoolOp" then
    local acc = self:ex(e.values[#e.values])
    for i = #e.values - 1, 1, -1 do
      acc = (e.op == "and" and "and_" or "or_") .. "(" .. self:ex(e.values[i]) .. ", function() return " .. acc .. " end)"
    end
    return acc
  end
  if k == "Compare" then return "(" .. self:compare(e) .. ")" end
  if k == "IfExp" then
    return "(function() if " .. self:cond(e.test) .. " then return " .. self:ex(e.body)
      .. " end return " .. self:ex(e.orelse) .. " end)()"
  end
  if k == "Call" then return self:call(e) end
  if k == "Method" then
    local args = { self:ex(e.obj), string.format("%q", e.name) }
    for _, a in ipairs(e.args) do args[#args + 1] = self:ex(a) end
    return "method(" .. table.concat(args, ", ") .. ")"
  end
  if k == "Subscript" then return "getitem(" .. self:ex(e.value) .. ", " .. self:ex(e.index) .. ")" end
  if k == "Slice" then
    return "slice(" .. self:ex(e.value) .. ", " .. (e.lower and self:ex(e.lower) or "nil") .. ", "
      .. (e.upper and self:ex(e.upper) or "nil") .. ")"
  end
  if k == "List" or k == "Tuple" then
    local parts = {}
    for i, v in ipairs(e.elts) do parts[i] = self:ex(v) end
    return (k == "List" and "list" or "tuple") .. "({" .. table.concat(parts, ", ") .. "}, " .. #parts .. ")"
  end
  if k == "Dict" then
    local parts = {}
    for i, key in ipairs(e.keys) do
      parts[#parts + 1] = self:ex(key)
      parts[#parts + 1] = self:ex(e.values[i])
    end
    return "dict({" .. table.concat(parts, ", ") .. "}, " .. #parts .. ")"
  end
  error("codegen: neznámý výraz " .. tostring(k))
end

--- Přiřazení hodnoty (text Lua, už vyhodnocený) do cíle.
function Gen:assign(target, value)
  local k = target.k
  if k == "Name" then
    self:emit(self:name(target.id) .. " = " .. value)
  elseif k == "Subscript" then
    self:emit("setitem(" .. self:ex(target.value) .. ", " .. self:ex(target.index) .. ", " .. value .. ")")
  else
    local names = {}
    for i = 1, #target.elts do names[i] = self:tmp() end
    self:emit("do local " .. table.concat(names, ", ") .. " = unpack(" .. value .. ", " .. #names .. ")")
    for i, el in ipairs(target.elts) do self:assign(el, names[i]) end
    self:emit("end")
  end
end

--- Tělo cyklu se štítkem pro continue na konci.
function Gen:loop_body(body)
  self.nlabel = self.nlabel + 1
  local label = "c" .. self.nlabel
  self.loops[#self.loops + 1] = label
  self:stmts(body)
  self.loops[#self.loops] = nil
  self:emit("::" .. label .. "::")
end

--- Příkaz jako řádky Lua.
function Gen:stmt(s)
  local k = s.k
  if k == "Def" or k == "Global" or k == "Pass" then return end
  self:emit("_ln = " .. s.line .. ";")
  if k == "Expr" then
    local v = s.value
    if v.k == "Call" and v.func == "config" then return end
    if v.k == "Call" or v.k == "Method" then
      self:emit(self:ex(v))
    else
      self:emit("do local _ = " .. self:ex(v) .. " end")
    end
  elseif k == "Assign" then
    local t1 = s.targets[1]
    if #s.targets == 1 and t1.k ~= "Tuple" and t1.k ~= "List" then
      self:assign(t1, self:ex(s.value))
    else
      local t = self:tmp()
      self:emit("do local " .. t .. " = " .. self:ex(s.value))
      for _, target in ipairs(s.targets) do self:assign(target, t) end
      self:emit("end")
    end
  elseif k == "AugAssign" then
    local f, t = BINOP[s.op], s.target
    if t.k == "Name" then
      local n = self:name(t.id)
      self:emit(n .. " = " .. f .. "(" .. n .. ", " .. self:ex(s.value) .. ")")
    else
      self:emit("do local _o, _k = " .. self:ex(t.value) .. ", " .. self:ex(t.index))
      self:emit("setitem(_o, _k, " .. f .. "(getitem(_o, _k), " .. self:ex(s.value) .. ")) end")
    end
  elseif k == "If" then
    self:emit("if " .. self:cond(s.test) .. " then")
    self:stmts(s.body)
    if #s.orelse > 0 then
      self:emit("else")
      self:stmts(s.orelse)
    end
    self:emit("end")
  elseif k == "While" then
    self:emit("while true do")
    self:emit("_ln = " .. s.line .. "; if not " .. self:cond(s.test) .. " then break end")
    self:emit(WD)
    self:loop_body(s.body)
    self:emit("end")
  elseif k == "For" then
    local it, v = s.iter, self:tmp()
    if it.k == "Call" and it.func == "range" and #it.args >= 1 and #it.args <= 3 then
      local args = {}
      for i, a in ipairs(it.args) do args[i] = self:ex(a) end
      local f, l, st = self:tmp(), self:tmp(), self:tmp()
      self:emit("do local " .. f .. ", " .. l .. ", " .. st .. " = range_bounds(" .. table.concat(args, ", ") .. ")")
      self:emit("for " .. v .. " = " .. f .. ", " .. l .. ", " .. st .. " do")
    else
      self:emit("do for " .. v .. " in iter(" .. self:ex(it) .. ") do")
    end
    self:emit(WD)
    self:assign(s.target, v)
    self:loop_body(s.body)
    self:emit("end end")
  elseif k == "Return" then
    self:emit("do return " .. (s.value and self:ex(s.value) or "None") .. " end")
  elseif k == "Break" then
    self:emit("do break end")
  elseif k == "Continue" then
    self:emit("goto " .. self.loops[#self.loops])
  else
    error("codegen: neznámý příkaz " .. tostring(k))
  end
end

function Gen:stmts(body)
  for _, s in ipairs(body) do self:stmt(s) end
end

--- Funkce uživatele (přiřazení do předem deklarované lokální f_<jméno>).
function Gen:func(fn)
  self.fn = fn
  local params, is_param = {}, {}
  for i, p in ipairs(fn.params) do params[i] = "l_" .. p; is_param[p] = true end
  self:emit("f_" .. fn.node.name .. " = function(" .. table.concat(params, ", ") .. ")")
  self:emit(WD)
  local locals = {}
  for name in pairs(fn.locals) do
    if not is_param[name] then locals[#locals + 1] = "l_" .. name end
  end
  table.sort(locals)
  if #locals > 0 then self:emit("local " .. table.concat(locals, ", ")) end
  self:stmts(fn.node.body)
  self:emit("return None")
  self:emit("end")
  self.fn = nil
end

--- Vygeneruje zdroj Lua: chunk vrací factory function(R, G, IO) → instance.
--- @param ast table Module (po checker.check)
--- @param info table výsledek checker.check
--- @return string
function M.generate(ast, info)
  local self = setmetatable({ out = {}, ntmp = 0, nlabel = 0, loops = {}, info = info }, Gen)
  self:emit("return function(R, G, IO)")
  self:emit("local None, B = R.None, R.builtins")
  self:emit("local " .. table.concat(HELPERS, ", ") .. " = R." .. table.concat(HELPERS, ", R."))
  self:emit("local _b, _ln = 0, 0")
  self:emit("local function wd() R.watchdog() end")
  self:emit("local function print_(...) IO.print(print_line(...)) return None end")
  local names = {}
  for _, s in ipairs(ast.body) do
    if s.k == "Def" then names[#names + 1] = "f_" .. s.name end
  end
  self:emit("local " .. table.concat(names, ", "))
  for _, s in ipairs(ast.body) do
    if s.k == "Def" then self:func(info.functions[s.name]) end
  end
  self:emit("local function init()")
  self:stmts(ast.body)
  self:emit("end")
  self:emit("return { init = init, loop = f_loop, set_budget = function(n) _b = n end,"
    .. " budget = function() return _b end, line = function() return _ln end }")
  self:emit("end")
  return table.concat(self.out, "\n")
end

return M
```

- [ ] **Step 5: Implementace `compiler.lua`**

`Pythonator/scripts/lang/compiler.lua`:
```lua
--- Překladač Pythonatoru: zdroj → program (factory instance + config).
local errors = require("scripts.lang.errors")
local parser = require("scripts.lang.parser")
local checker = require("scripts.lang.checker")
local codegen = require("scripts.lang.codegen")

local M = {}

--- Přeloží zdroj programu.
--- @param source string
--- @param resolver table z signals.new_resolver
--- @return table|nil program {factory = function(R, G, IO), config, lua}
--- @return table|nil err chyba jazyka {line, col, key, args}
function M.compile(source, resolver)
  local ok, res = pcall(function()
    local ast = parser.parse(source)
    local info = checker.check(ast, resolver)
    return { lua = codegen.generate(ast, info), config = info.config }
  end)
  if not ok then
    if errors.is(res) then return nil, res end
    error(res, 0)
  end
  local chunk, lerr = load(res.lua, "=pythonator", "t", {})
  if not chunk then error("Pythonator: vygenerovaný kód nejde načíst: " .. tostring(lerr) .. "\n" .. res.lua, 0) end
  return { factory = chunk(), config = res.config, lua = res.lua }
end

return M
```

- [ ] **Step 6: Implementace `vm.lua`**

`Pythonator/scripts/lang/vm.lua`:
```lua
--- Běh programu: instance nad globály, spuštění s watchdogem, převod chyb, pojistka paměti.
local errors = require("scripts.lang.errors")
local R = require("scripts.lang.builtins")

local M = {}

--- Vytvoří instanci programu nad globály G a vstupy/výstupy IO.
--- @param program table z compiler.compile
--- @param G table globální proměnné (u hostitele ve storage)
--- @param IO table {inp, red, green, out, out_red, out_green, print, tick, game_tick, dt}
--- @return table instance
function M.instantiate(program, G, IO)
  return program.factory(R, G, IO)
end

--- Spustí init nebo loop s rozpočtem watchdogu.
--- @param inst table instance
--- @param what string "init" | "loop"
--- @param limit integer rozpočet operací
--- @return boolean ok
--- @return table|nil err chyba s řádkem zdroje
--- @return integer used spotřebované operace
function M.run(inst, what, limit)
  inst.set_budget(limit)
  local ok, e = pcall(inst[what])
  local used = limit - inst.budget()
  if ok then return true, nil, used end
  if errors.is(e) then
    e.line = e.line or inst.line()
    if e.key == "pyntr-err.watchdog" then e.args = { tostring(limit) } end
    return false, e, used
  end
  return false, errors.make(inst.line(), nil, "internal", tostring(e)), used
end

--- Spočítá prvky kontejnerů v globálech; cykly a sdílené reference jednou.
--- @param G table
--- @param limit integer
--- @return integer total
--- @return string|nil biggest jméno největšího globálu, pokud total > limit
function M.memory(G, limit)
  local seen, total = {}, 0
  local function count(v)
    if type(v) ~= "table" or seen[v] then return 0 end
    seen[v] = true
    local mt, n = getmetatable(v), 0
    if mt == R.ListMT or mt == R.TupleMT then
      n = v.n
      for i = 1, v.n do
        n = n + count(v[i])
        if total + n > limit then return n end
      end
    elseif mt == R.DictMT then
      n = #v.keys
      for _, k in ipairs(v.keys) do
        n = n + count(R.dict_get(v, k))
        if total + n > limit then return n end
      end
    end
    return n
  end
  local names = {}
  for name in pairs(G) do names[#names + 1] = name end
  table.sort(names)
  local biggest, bsize = nil, -1
  for _, name in ipairs(names) do
    local n = count(G[name])
    total = total + n
    if n > bsize then biggest, bsize = name, n end
    if total > limit then return total, biggest end
  end
  return total, nil
end

--- Chyba pojistky paměti, nebo nil, pokud je vše v limitu.
--- @return table|nil
function M.check_memory(G, limit)
  local total, biggest = M.memory(G, limit)
  if total > limit then return errors.make(nil, nil, "memory", biggest, limit) end
end

return M
```

- [ ] **Step 7: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=158 fail=0`. Při selhání kvůli syntaxi vygenerovaného kódu se chyba vypíše i s celým zdrojem Lua (viz `compiler.lua`) – oprav generátor, ne test.

- [ ] **Step 8: Commit**

```bash
git add Pythonator/scripts/lang/codegen.lua Pythonator/scripts/lang/compiler.lua Pythonator/scripts/lang/vm.lua tests/unit
git commit -m "Generátor Lua, překladač a VM s watchdogem, řádky chyb a pojistkou paměti"
```

---

### Task 9: Konformní testy proti CPythonu

**Files:**
- Create: `tests/conformance/harness.py`, `tools/gen-conformance.sh`
- Create: `tests/conformance/cases/{arithmetic,strings,collections,control,state}.py` a vygenerované `*.out`
- Create: `tests/conformance/cases.lua` (seznam případů), `tests/unit/test_conformance.lua`
- Modify: `tests/unit/run.lua` (přidat `"test_conformance"`)

**Interfaces:**
- Consumes: `prog_runner.run(src, ticks)` z úlohy 8
- Produces: `bash tools/gen-conformance.sh` (přegeneruje `.out` v CPythonu). Hlavička případu `# ticks: N` (výchozí 1) určuje počet volání `loop()`.

Případy nesmí používat rich text tagy (nejsou platný Python) ani tisk desetinných čísel s celou hodnotou (`3.0` – naše známá odchylka), ani výstupy (`out`) – ty pokrývá úloha 8.

- [ ] **Step 1: Harness v Pythonu**

`tests/conformance/harness.py`:
```python
"""Spustí program Pythonatoru v CPythonu a vypíše řádky print() – referenční výstup pro Lua implementaci."""
import sys


class Signals(dict):
    """Náhrada objektů signálů: chybějící klíč čte 0."""

    def __missing__(self, key):
        return 0


def main(path: str) -> None:
    """Spustí inicializaci a `# ticks: N`× loop() programu ze souboru path."""
    with open(path, encoding="utf-8") as f:
        src = f.read()
    ticks = 1
    first = src.splitlines()[0] if src else ""
    if first.startswith("# ticks:"):
        ticks = int(first.split(":")[1])
    ns = {name: Signals() for name in ("inp", "red", "green", "out", "out_red", "out_green")}
    ns.update(tick=0, game_tick=0, dt=1, config=lambda **kw: None)
    exec(compile(src, path, "exec"), ns)
    for t in range(ticks):
        ns["tick"] = t
        ns["game_tick"] = t
        ns["loop"]()


if __name__ == "__main__":
    sys.stdout.reconfigure(newline="\n")
    main(sys.argv[1])
```

`tools/gen-conformance.sh`:
```bash
#!/usr/bin/env bash
# Přegeneruje očekávané výstupy konformních testů v CPythonu (spouštět jen při změně případů).
set -euo pipefail
cd "$(dirname "$0")/.."
for f in tests/conformance/cases/*.py; do
  uv run --no-project python -I tests/conformance/harness.py "$f" > "${f%.py}.out"
done
echo "OK: $(ls tests/conformance/cases/*.out | wc -l) výstupů"
```

- [ ] **Step 2: Případy**

`tests/conformance/cases/arithmetic.py`:
```python
def loop():
    print(7 // 2, -7 // 2, 7 % 3, -7 % 3, 7 % -3)
    print(2 ** 10, 10 / 4, 1 / 3, 0.1 + 0.2)
    print(5 & 3, 5 | 3, 5 ^ 3, ~5, 1 << 4, -16 >> 2)
    print(0 < 5 < 10, 1 < 0 < 2, 3 == 3.0, True + 1)
    print(round(2.5), round(3.5), round(-2.5), round(1.234, 2))
    print(abs(-4), min(3, 1, 2), max([4, 9, 2]), int(-3.7), int("12"), float("2.5"))
    print(sum([1, 2, 3]), sum(range(5), 10), sorted([3, 1, 2]))
    print(1e20, 1.5e-7, 123456.789, -0.5)
```

`tests/conformance/cases/strings.py`:
```python
def loop():
    s = "Hello"
    print(s + " " + "world", s * 2, len(s), s[1], s[-1], s[1:3], s[:2], s[3:])
    print(s.upper(), s.lower(), s.startswith("He"), s.endswith("lo"))
    print("a,b,,c".split(","), " x  y ".split(), "-".join(["a", "b", "c"]))
    print("a.b.c".replace(".", "/"), "ll" in s, "z" not in s)
    print(repr("it's"), repr('say "hi"'), ["a", 'b'], str(12) + "!")
    print("abc" < "abd", "B" < "a", str(None), str(True))
```

`tests/conformance/cases/collections.py`:
```python
def loop():
    a = [3, 1, 2]
    a.append(5)
    a.insert(0, 9)
    print(a, a.pop(), a.pop(0), a, a.index(2), len(a))
    a.remove(1)
    print(a, a[-1], a[1:], a[:-1], a * 2, a + [7])
    t = (1, 2)
    x, y = t
    print(t, (1,), (), x + y, t == (1, 2), [1, 2] == [1, 2], [1] == (1,))
    d = {"a": 1, "b": 2, "c": 3}
    d.pop("b")
    d["b"] = 4
    d["a"] = 10
    print(d, sorted(d.values()), d.get("z"), d.get("z", 0))
    for k, v in d.items():
        print(k, v)
    print(sorted(d.keys()), "a" in d, 10 in d, len(d))
    n = [[1, 2], [3]]
    n[0].append(9)
    print(n, n[0][2], [[0] * 2] * 2)
```

`tests/conformance/cases/control.py`:
```python
def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


def classify(x):
    if x < 0:
        return "neg"
    elif x == 0:
        return "zero"
    else:
        return "pos"


def loop():
    print(fib(15), classify(-3), classify(0), classify(8))
    s = 0
    i = 0
    while i < 20:
        i += 1
        if i % 3 == 0:
            continue
        if i > 14:
            break
        s += i
    print(s, i)
    out_list = []
    for a in range(3):
        for b in range(3):
            if a == b:
                continue
            out_list.append(a * 10 + b)
    print(out_list)
    print(0 or 5, "" and 1, 1 and 2, None or "x", "yes" if [] else "no")
    a, b = 1, 2
    a, b = b, a
    print(a, b)
```

`tests/conformance/cases/state.py`:
```python
# ticks: 6
count = 0
pump_on = False
history = []
LIMITS = {"iron": (2, 4)}
active = {}


def hyst(key, value, low, high):
    if value < low:
        active[key] = True
    elif value > high:
        active[key] = False
    return active.get(key, False)


def loop():
    global count, pump_on
    count += 1
    level = (count * 3) % 7
    if level < 2:
        pump_on = True
    elif level > 5:
        pump_on = False
    history.append(level)
    if len(history) > 3:
        history.pop(0)
    for key, (low, high) in LIMITS.items():
        print(tick, count, level, pump_on, history, hyst(key, level, low, high), sum(history) // len(history))
```

Seznam `tests/conformance/cases.lua`:
```lua
--- Konformní případy (jméno souboru bez přípony v tests/conformance/cases/).
return { "arithmetic", "strings", "collections", "control", "state" }
```

- [ ] **Step 3: Vygenerovat očekávané výstupy v CPythonu**

Run: `bash tools/gen-conformance.sh`
Expected: `OK: 5 výstupů`. Zkontroluj ručně `tests/conformance/cases/arithmetic.out` – první řádek `3 -4 1 2 -2`. Pokud kterýkoli `.out` obsahuje číslo ve tvaru `N.0` (celé desetinné), uprav případ tak, aby ho netiskl (známá odchylka), a vygeneruj znovu.

- [ ] **Step 4: Lua test konformity (padající, dokud něco nesedí)**

`tests/unit/test_conformance.lua`:
```lua
local A = require("assert")
local P = require("prog_runner")

--- Přečte soubor jako text (bez CR).
local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a"):gsub("\r", "")
  f:close()
  return s
end

local cases = {}
for _, name in ipairs(dofile("tests/conformance/cases.lua")) do
  cases[#cases + 1] = { "konformita " .. name, function()
    local src = read("tests/conformance/cases/" .. name .. ".py")
    local expected = read("tests/conformance/cases/" .. name .. ".out"):gsub("\n$", "")
    local ticks = tonumber(src:match("^# ticks: (%d+)")) or 1
    local res, err = P.run(src, ticks)
    if not res then error(err, 0) end
    local got = res.lines:gsub("|", "\n")
    if got ~= expected then
      -- první rozdílný řádek pro čitelnou hlášku
      local gl, el = {}, {}
      for l in (got .. "\n"):gmatch("(.-)\n") do gl[#gl + 1] = l end
      for l in (expected .. "\n"):gmatch("(.-)\n") do el[#el + 1] = l end
      for i = 1, math.max(#gl, #el) do
        A.eq(gl[i], el[i], name .. " řádek " .. i)
      end
    end
  end }
end
return cases
```
Pozn.: `prog_runner` spojuje řádky `|`; případy proto nesmí tisknout znak `|` (žádný ho netiskne).

Přidat `"test_conformance"` do `SUITES`.

Run: `bash tools/run-unit.sh`
Expected: buď `UNIT pass=163 fail=0`, nebo FAIL s konkrétním řádkem `… řádek N: čekáno X, dostáno Y`.

- [ ] **Step 5: Opravit rozdíly v runtime/codegenu (ne v `.out`)**

Každý rozdíl je chyba naší implementace, pokud nejde o zdokumentovanou odchylku (int/float, 32bitové bitové operace, `keys()` jako list). U zdokumentované odchylky uprav případ, ne implementaci. Po každé opravě znovu `bash tools/run-unit.sh`.

- [ ] **Step 6: Spustit – musí projít**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=163 fail=0`

- [ ] **Step 7: Commit**

```bash
git add tests/conformance tools/gen-conformance.sh tests/unit
git commit -m "Konformní testy: stejné programy v CPythonu a v Pythonatoru"
```

---

### Task 10: Úplnost lokalizace a vývojová dokumentace

**Files:**
- Create: `tests/unit/test_locale_keys.lua`
- Create: `docs/development.md`, `README.md`
- Modify: `tests/unit/run.lua` (přidat `"test_locale_keys"`)

**Interfaces:**
- Consumes: všechny moduly `Pythonator/scripts/lang/*.lua`, `Pythonator/locale/{en,cs}/locale.cfg`
- Produces: test, který selže, když kód použije klíč chyby bez překladu.

- [ ] **Step 1: Test úplnosti klíčů**

`tests/unit/test_locale_keys.lua`:
```lua
local A = require("assert")

local MODULES = { "errors", "signals", "lexer", "parser", "checker", "runtime", "builtins", "signal_io",
  "codegen", "compiler", "vm" }

--- Klíče sekce [pyntr-err] v locale souboru.
local function locale_keys(path)
  local set, section = {}, ""
  for line in io.lines(path) do
    local header = line:match("^%[(.+)%]$")
    if header then section = header
    elseif section == "pyntr-err" then
      local key = line:match("^([%w%-]+)=")
      if key then set[key] = true end
    end
  end
  return set
end

--- Klíče chyb použité v kódu: první řetězcový literál ve volání raise/make (i R.raise a raise).
local function used_keys()
  local set = {}
  for _, m in ipairs(MODULES) do
    local f = assert(io.open("Pythonator/scripts/lang/" .. m .. ".lua", "rb"))
    local src = f:read("a")
    f:close()
    for key in src:gmatch('raise%([^"\n]-"([%w%-]+)"') do set[key] = true end
    for key in src:gmatch('make%([^"\n]-"([%w%-]+)"') do set[key] = true end
  end
  set["unknown-signal-nosuggest"] = true
  return set
end

return {
  { "každý klíč chyby z kódu má en i cs překlad", function()
    local en = locale_keys("Pythonator/locale/en/locale.cfg")
    local cs = locale_keys("Pythonator/locale/cs/locale.cfg")
    for key in pairs(used_keys()) do
      A.truthy(en[key], "chybí v en: " .. key)
      A.truthy(cs[key], "chybí v cs: " .. key)
    end
  end },
}
```
Přidat `"test_locale_keys"` do `SUITES`.

- [ ] **Step 2: Spustit**

Run: `bash tools/run-unit.sh`
Expected: `UNIT pass=164 fail=0`. Pokud test hlásí chybějící klíč, doplň ho do obou locale (ne do testu).

- [ ] **Step 3: `docs/development.md`**

```markdown
# Pythonator – vývoj

## Prostředí
- Factorio 2.0 (hra běží na Lua 5.2), lokální testy v Lua 5.3 (`lua` v PATH), CPython přes `uv` jen pro `tools/gen-conformance.sh`.
- Skripty `tools/*.sh` spouštět v Git Bash.

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
| Limit watchdogu | předává hostitel do `vm.run(inst, what, limit)` (nastavení `pyntr-watchdog-limit`, plán 2) | 10 000 |
| Limit paměti | `vm.check_memory(G, limit)` (nastavení `pyntr-memory-limit`, plán 2) | 10 000 |

## Známé odchylky od Pythonu
- `int` a `float` se nerozlišují: `6 / 2` vypíše `3`, ne `3.0`; čísla nad 2^53 ztrácí přesnost.
- Bitové operace jsou 32bitové se znaménkem (jako obvodová síť).
- `dict.keys()/values()/items()` vrací list, ne pohled.
- Klíčem slovníku může být jen `str`, číslo nebo `bool`.
- `def` na nejvyšší úrovni jsou dostupné i před svou definicí (hoisting).
- Přiřazení do globálu ve funkci bez `global` je chyba překladu (Python by vytvořil lokální proměnnou).
```

`README.md`:
```markdown
# Pythonator

Mod do Factoria 2.0: programovatelný obvodový kontrolér, který se programuje v podmnožině Pythonu.
Každý tick: načíst vstupy → `loop()` → zapsat výstupy.

- Návrh: `docs/superpowers/specs/2026-10-09-pythonator-design.md`
- Vývoj a testy: `docs/development.md`

Rychlý start vývoje: `bash tools/run-unit.sh`
```

- [ ] **Step 4: Commit**

```bash
git add tests/unit Pythonator/locale docs/development.md README.md
git commit -m "Kontrola úplnosti lokalizace chyb, vývojová dokumentace"
```
