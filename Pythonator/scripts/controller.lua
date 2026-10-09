--- Kontrolér Pythonatoru: stav ve storage, nahrání kódu, spuštění loop() s časem, výstupy a pojistkami.
--- Přeložené instance programů jsou v cache mimo storage (funkce nejdou uložit); staví se líně při prvním
--- použití, takže po načtení hry nebo připojení hráče vznikne na každém klientovi stejná instance bez initu.
local compiler = require("scripts.lang.compiler")
local signal_io = require("scripts.lang.signal_io")
local vm = require("scripts.lang.vm")
local resolver = require("scripts.resolver")
local io = require("scripts.io")

local M = {}

--- Kolik řádků print() si kontrolér pamatuje.
M.PRINT_LINES = 50
--- Jak často (v tickách programu) se po loop() kontroluje paměť.
M.MEMORY_CHECK_TICKS = 60

--- Cache instancí: unit_number → { inst, IO, sources }. Odvozená ze storage, neukládá se.
local instances = {}

--- Tabulka všech kontrolérů ve storage.
local function all()
  storage.controllers = storage.controllers or {}
  return storage.controllers
end

--- Limity z nastavení mapy v paměti (jméno → hodnota).
local limits = {}

--- Hodnota map setting.
local function setting(name)
  -- Čtení settings.global je volání API – drží se v paměti a obnoví po změně (refresh_settings).
  -- Nastavení mapy jsou na všech klientech stejná, cache je deterministická.
  local value = limits[name]
  if not value then
    value = settings.global[name].value
    limits[name] = value
  end
  return value
end

--- Zapomene uložené limity z nastavení mapy (on_runtime_mod_setting_changed).
function M.refresh_settings()
  limits = {}
end

--- Spotřeba budovy za tick (J) – pod ní v zásobníku budova nepracuje. Počítá se při stavbě a po změně
--- modů, ne každý tick (čtyři volání API).
--- @param entity LuaEntity
--- @return number
function M.energy_usage(entity)
  return entity.prototype.get_max_energy_usage(entity.quality)
end

--- Vytvoří stav kontroléru pro novou budovu (bez kódu, zastavený).
--- @param entity LuaEntity
--- @return table ctl
function M.create(entity)
  local ctl = {
    entity = entity,
    unit = entity.unit_number,
    code = "",
    running = false,
    error = nil,          -- chyba běhu (stav CHYBA)
    compile_error = nil,  -- poslední neúspěšný překlad (starý program běží dál)
    globals = {},
    out = { both = {}, red = {}, green = {} },
    tick = 0,
    last_run = nil,
    memory_checked = 0,
    interval = 1,
    outputs_mode = "hold",
    prints = {},
    used = 0,
    energy_usage = M.energy_usage(entity),
  }
  all()[ctl.unit] = ctl
  return ctl
end

--- Stav kontroléru podle unit_number.
--- @return table|nil
function M.get(unit)
  return all()[unit]
end

--- Odstraní stav kontroléru (zbourání).
function M.destroy(unit)
  all()[unit] = nil
  instances[unit] = nil
end

--- Zapíše řádek print() do kruhového logu.
local function add_print(ctl, line)
  local prints = ctl.prints
  prints[#prints + 1] = line
  if #prints > M.PRINT_LINES then table.remove(prints, 1) end
end

--- Přeloží kód kontroléru (bez spuštění).
local function compile(code)
  return compiler.compile(code, resolver.get())
end

--- Postaví instanci programu nad stavem kontroléru.
--- @return table|nil cache záznam { inst, IO, sources }
local function build(ctl, program)
  local res = resolver.get()
  local sources, IO = {}, {
    out = signal_io.writer(ctl.out.both, res),
    out_red = signal_io.writer(ctl.out.red, res),
    out_green = signal_io.writer(ctl.out.green, res),
    print = function(line) add_print(ctl, line) end,
    tick = 0, game_tick = 0, dt = 0,
  }
  for name, wires in pairs(io.input_wires()) do
    sources[name] = io.reader_source(ctl.entity, wires, res)
    IO[name] = signal_io.reader(sources[name], res)
  end
  local entry = { inst = vm.instantiate(program, ctl.globals, IO), IO = IO, sources = sources }
  instances[ctl.unit] = entry
  return entry
end

--- Instance programu z cache, případně znovu přeložená z kódu ve storage (po načtení hry).
--- @return table|nil
local function instance(ctl)
  local entry = instances[ctl.unit]
  if entry then return entry end
  local program, err = compile(ctl.code)
  if not program then
    -- Kód prošel při nahrání, teď ne: po načtení chybí prototyp (odebraný mod) → stav CHYBA s důvodem.
    ctl.error = err
    return nil
  end
  return build(ctl, program)
end

--- Spustí část programu s watchdogem; při chybě přepne do stavu CHYBA.
--- @return boolean ok
local function run(ctl, entry, what)
  local ok, err, used = vm.run(entry.inst, what, setting("pyntr-watchdog-limit"))
  ctl.used = used
  if not ok then
    ctl.error = err
    return false
  end
  return true
end

--- Zkontroluje paměť globálů; při překročení přepne do stavu CHYBA.
--- @return boolean ok
local function check_memory(ctl)
  ctl.memory_checked = ctl.tick
  local err = vm.check_memory(ctl.globals, setting("pyntr-memory-limit"))
  if err then
    ctl.error = err
    return false
  end
  return true
end

--- Zapíše výstupy na dráty, pokud se změnily (zapisovací objekty hlásí `changed`) nebo `force`.
--- Kontrolér bez skrytých výstupů (jednotkové testy) nic nezapisuje.
local function flush(ctl, entry, force)
  local IO = entry.IO
  if ctl.outputs and (force or IO.out.changed or IO.out_red.changed or IO.out_green.changed) then io.flush(ctl) end
  IO.out.changed, IO.out_red.changed, IO.out_green.changed = nil, nil, nil
end

--- Vyprázdní tabulky výstupů (tabulky zůstávají – drží je zapisovací objekty instance).
--- @return boolean něco bylo nastavené
local function clear_outputs(ctl)
  local any = false
  for _, store in pairs(ctl.out) do
    for k in pairs(store) do
      store[k] = nil
      any = true
    end
  end
  return any
end

--- Nahraje nový kód. Při chybě překladu běží dál starý program a chyba se uloží do compile_error.
--- Při úspěchu: reset globálů, výstupů a času, inicializace a zapnutí běhu (chyba initu = stav CHYBA).
--- @param ctl table
--- @param source string
--- @return boolean ok překlad prošel
--- @return table|nil err chyba překladu
function M.set_code(ctl, source)
  local program, err = compile(source)
  if not program then
    ctl.compile_error = err
    return false, err
  end
  ctl.code = source
  ctl.compile_error, ctl.error = nil, nil
  for k in pairs(ctl.globals) do ctl.globals[k] = nil end
  clear_outputs(ctl)
  ctl.prints = {}
  ctl.tick, ctl.last_run, ctl.memory_checked = 0, nil, 0
  ctl.interval = program.config.interval
  ctl.outputs_mode = program.config.outputs
  ctl.running = true
  local entry = build(ctl, program)
  -- Vymazané výstupy jdou na drát hned; co nastaví init, také (init může výstupy zapsat)
  if run(ctl, entry, "init") then check_memory(ctl) end
  flush(ctl, entry, true)
  return true
end

--- Spustí jeden loop() v herním ticku `game_tick` (volá plánovač nebo krok z GUI).
--- @param ctl table
--- @param game_tick integer
--- @param lost integer|nil ticků bez proudu od posledního běhu – do `tick` se nepočítají (do `dt` ano)
--- @return boolean ok loop proběhl bez chyby
function M.run_loop(ctl, game_tick, lost)
  if not ctl.running or ctl.error then return false end
  local entry = instance(ctl)
  if not entry then return false end
  local dt = ctl.interval
  if ctl.last_run then
    dt = game_tick - ctl.last_run
    ctl.tick = ctl.tick + dt - (lost or 0)
  end
  ctl.last_run = game_tick
  local IO = entry.IO
  IO.tick, IO.game_tick, IO.dt = ctl.tick, game_tick, dt
  for _, source in pairs(entry.sources) do source.reset() end
  local cleared = ctl.outputs_mode == "clear" and clear_outputs(ctl)
  if not run(ctl, entry, "loop") then return false end
  flush(ctl, entry, cleared)
  if ctl.tick - ctl.memory_checked >= M.MEMORY_CHECK_TICKS then return check_memory(ctl) end
  return true
end

--- Reset: vynuluje globály, čas, výstupy, log i chybu a znovu spustí inicializaci uloženého kódu (ne textu
--- v editoru). Běžící program běží dál od nuly; pozastavený nebo po chybě zůstane pozastavený.
--- @return boolean false = není nahraný žádný kód
function M.reset(ctl)
  if ctl.code == "" then return false end
  local keep_running = ctl.running and not ctl.error
  M.set_code(ctl, ctl.code)
  ctl.running = keep_running and not ctl.error
  return true
end

--- Krok: při pauze provede jeden loop(), jako by od minulého uběhl právě jeden interval.
--- @return boolean false = program běží, je v chybě nebo nemá kód; jinak výsledek loop()
function M.step(ctl, game_tick)
  if ctl.running or ctl.error or ctl.code == "" then return false end
  if ctl.last_run then ctl.last_run = game_tick - ctl.interval end
  ctl.running = true
  local ok = M.run_loop(ctl, game_tick)
  ctl.running = false
  return ok
end

--- Zastaví běh (stav zůstává, tick stojí).
function M.stop(ctl)
  ctl.running = false
end

--- Spustí zastavený program. Po chybě nejde – stav může být napůl provedený, je nutné nahrát kód znovu.
--- @return boolean
function M.start(ctl)
  if ctl.error or ctl.code == "" then return false end
  ctl.running = true
  ctl.last_run = nil
  return true
end

return M
