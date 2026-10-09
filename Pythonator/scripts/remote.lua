--- Remote interface "pyntr": ovládání budovy podle unit_number pro integrační testy, konzoli a jiné mody.
--- Do GUI z plánu 3 jediný způsob, jak nahrát kód. Vrací jen data (žádné funkce ani objekty jazyka).
local controller = require("scripts.controller")
local lifecycle = require("scripts.lifecycle")
local R = require("scripts.lang.builtins")

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
  --- Nahraje kód a spustí ho od nuly. @return boolean ok, table|nil chyba překladu
  set_code = function(unit, source)
    return lifecycle.load_code(get(unit), source)
  end,

  --- Stav pro ladění a testy: běh, chyby, čas, globály (repr), výstupy, log print().
  get_state = function(unit)
    local ctl = get(unit)
    local globals = {}
    for name, value in pairs(ctl.globals) do globals[name] = R.repr(value) end
    return {
      code = ctl.code, running = ctl.running, error = ctl.error, compile_error = ctl.compile_error,
      tick = ctl.tick, interval = ctl.interval, used = ctl.used, globals = globals, led = ctl.led_state,
      outputs = { both = copy(ctl.out.both), red = copy(ctl.out.red), green = copy(ctl.out.green) },
      prints = copy(ctl.prints),
    }
  end,

  --- ▶ Play. @return boolean
  start = function(unit)
    local ctl = get(unit)
    local ok = controller.start(ctl)
    lifecycle.wake(ctl)
    return ok
  end,

  --- ⏸ Pauza.
  stop = function(unit)
    local ctl = get(unit)
    controller.stop(ctl)
    lifecycle.wake(ctl)
  end,

  --- ⟳ Reset. @return boolean
  reset = function(unit)
    local ctl = get(unit)
    local ok = controller.reset(ctl)
    lifecycle.wake(ctl)
    return ok
  end,

  --- ⏭ Krok (jen při pauze). @return boolean
  step = function(unit)
    local ctl = get(unit)
    local ok = controller.step(ctl, game.tick)
    lifecycle.wake(ctl)
    return ok
  end,
})
