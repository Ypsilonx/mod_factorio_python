--- Akce nad kontrolérem společné pro GUI a remote interface (▶ Play, ⏸ Pauza, ⟳ Reset, ⏭ Krok),
--- rozepsaný kód (draft) a pohled na stav pro GUI (co zobrazit a které akce povolit).
local controller = require("scripts.controller")
local lifecycle = require("scripts.lifecycle")

local M = {}

--- Text v editoru: rozepsaný kód, jinak nahraný kód.
--- @return string
function M.text(ctl)
  return ctl.draft or ctl.code
end

--- Uloží rozepsaný kód; text shodný s nahraným kódem draft smaže.
--- @param ctl table
--- @param text string
function M.set_draft(ctl, text)
  if text == ctl.code then
    ctl.draft = nil
  else
    ctl.draft = text
  end
end

--- ▶ Play: změněný text přeloží a spustí od nuly, jinak pokračuje v běhu.
--- Chyba překladu nechá program pozastavený (a starý kód nahraný), draft zůstane k opravě.
--- @param ctl table
--- @param text string|nil text editoru (nil = nahraný kód)
--- @return boolean ok
--- @return table|nil err chyba překladu
function M.play(ctl, text)
  if text ~= nil and text ~= ctl.code then
    local ok, err = lifecycle.load_code(ctl, text)
    if not ok then return false, err end
    ctl.draft = nil
    return true
  end
  local ok = controller.start(ctl)
  lifecycle.wake(ctl)
  return ok
end

--- ⏸ Pauza.
function M.pause(ctl)
  controller.stop(ctl)
  lifecycle.wake(ctl)
end

--- ⟳ Reset uloženého kódu (text v editoru se nemění).
--- @return boolean false = žádný nahraný kód
function M.reset(ctl)
  local ok = controller.reset(ctl)
  lifecycle.wake(ctl)
  return ok
end

--- ⏭ Krok: jeden loop() při pauze.
--- @param game_tick integer
--- @return boolean
function M.step(ctl, game_tick)
  local ok = controller.step(ctl, game_tick)
  lifecycle.wake(ctl)
  return ok
end

--- Stav kontroléru pro zobrazení.
--- @return string "off" | "running" | "paused" | "error" | "no_power"
local function state(ctl)
  if ctl.error then return "error" end
  if ctl.code == "" then return "off" end
  if ctl.running then return ctl.outage_since and "no_power" or "running" end
  return "paused"
end

--- Pohled na kontrolér pro GUI: stav, čas, cena posledního běhu, chyby a povolené akce.
--- @return table {state, tick, used, limit, error, compile_error, can = {play, pause, reset, step, edit}}
function M.view(ctl)
  local st = state(ctl)
  local has_code = ctl.code ~= ""
  local running = ctl.running and not ctl.error
  local changed = ctl.draft ~= nil and ctl.draft ~= ""
  return {
    state = st,
    tick = ctl.tick,
    used = ctl.used,
    limit = controller.limit("pyntr-watchdog-limit"),
    error = ctl.error,
    compile_error = ctl.compile_error,
    can = {
      -- po chybě běhu jde spustit jen nový text (stav programu může být napůl provedený)
      play = not running and (changed or (has_code and not ctl.error)),
      pause = running,
      reset = has_code,
      step = has_code and not ctl.running and not ctl.error,
      edit = not running,
    },
  }
end

return M
