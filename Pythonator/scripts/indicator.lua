--- Stavová LED (blikátko) na budově: zelená bliká = běží, žlutá svítí = pauza, červená svítí = chyba,
--- zhasnuto = bez kódu nebo bez proudu. Kreslí se přes rendering (objekt se uloží do stavu kontroléru) a mění
--- se jen při změně stavu – blikání přehrává engine sám (prototypes/led.lua), takže to nestojí výkon.
local graphics = require("prototypes.graphics_data")

local M = {}

--- Barvy stavů (tint bílé záře) – laditelné.
M.COLORS = {
  run = { r = 0.25, g = 1.0, b = 0.3 },
  pause = { r = 1.0, g = 0.8, b = 0.1 },
  error = { r = 1.0, g = 0.12, b = 0.08 },
}

--- Stav LED podle kontroléru.
--- @return string "off" | "run" | "pause" | "error"
function M.state(ctl)
  if ctl.error then return "error" end
  if ctl.code == "" then return "off" end
  if ctl.running then return ctl.outage_since and "off" or "run" end
  return "pause"
end

--- Posun LED od středu entity pro její směr (defines.direction: sever 0, východ 4, jih 8, západ 12).
local function offset(entity)
  return graphics.led[math.floor(entity.direction / 4) % 4 + 1]
end

--- Překreslí LED, pokud se změnil stav (nebo `force` – např. po otočení budovy).
--- @param ctl table kontrolér
--- @param force boolean|nil
function M.update(ctl, force)
  local state = M.state(ctl)
  if state == ctl.led_state and not force and (state == "off" or (ctl.led and ctl.led.valid)) then return end
  if ctl.led and ctl.led.valid then ctl.led.destroy() end
  ctl.led, ctl.led_state = nil, state
  if state == "off" or not ctl.entity.valid then return end
  local params = {
    target = { entity = ctl.entity, offset = offset(ctl.entity) },
    surface = ctl.entity.surface,
    tint = M.COLORS[state],
    render_layer = "higher-object-under",
  }
  if state == "run" then
    params.animation = "pyntr-led-blink"
    ctl.led = rendering.draw_animation(params)
  else
    params.sprite = "pyntr-led-steady"
    ctl.led = rendering.draw_sprite(params)
  end
end

return M
