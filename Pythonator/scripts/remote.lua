--- Remote interface "pyntr": ovládání budovy podle unit_number pro integrační testy, konzoli a jiné mody.
--- Akce jdou přes scripts/actions.lua stejně jako z GUI. Vrací jen data (žádné funkce ani objekty jazyka).
local controller = require("scripts.controller")
local lifecycle = require("scripts.lifecycle")
local actions = require("scripts.actions")
local R = require("scripts.lang.builtins")
local elements = require("scripts.lang.elements")

--- Kontrolér podle unit_number, jinak chyba volání.
local function get(unit)
  local ctl = controller.get(unit)
  if not ctl then error("Pythonator " .. tostring(unit) .. " neexistuje") end
  return ctl
end

--- Kopie mapy klíč → číslo.
local function copy(map)
  local out = {}
  for k, v in pairs(map) do out[k] = v end
  return out
end

remote.add_interface("pyntr", {
  --- Nahraje kód a spustí ho od nuly; při chybě překladu běží dál starý program.
  --- @return boolean ok, table|nil chyba překladu
  set_code = function(unit, source)
    if type(source) ~= "string" then error("set_code: kód musí být řetězec") end
    return lifecycle.load_code(get(unit), source)
  end,

  --- Stav pro ladění a testy: běh, chyby, čas, globály (repr), výstupy, log print().
  get_state = function(unit)
    local ctl = get(unit)
    local globals = {}
    -- stav prvků knihovny ("#lib") není proměnná programu
    for name, value in pairs(ctl.globals) do
      if name ~= elements.STATE then globals[name] = R.repr(value) end
    end
    return {
      code = ctl.code, draft = ctl.draft, running = ctl.running, error = ctl.error,
      compile_error = ctl.compile_error, tick = ctl.tick, interval = ctl.interval, used = ctl.used,
      globals = globals, led = ctl.led_state,
      outputs = { both = copy(ctl.out.both), red = copy(ctl.out.red), green = copy(ctl.out.green) },
      prints = copy(ctl.prints),
    }
  end,

  --- ▶ Play nahraného kódu (pokračování). @return boolean
  start = function(unit) return (actions.play(get(unit))) end,

  --- ⏸ Pauza.
  stop = function(unit) actions.pause(get(unit)) end,

  --- ⟳ Reset. @return boolean
  reset = function(unit) return actions.reset(get(unit)) end,

  --- ⏭ Krok (jen při pauze). @return boolean
  step = function(unit) return actions.step(get(unit), game.tick) end,
})
