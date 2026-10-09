--- Stavová LED (blikátko) a displej na budově. LED: zelená bliká = běží, žlutá svítí = pauza, červená svítí =
--- chyba, zhasnuto = bez kódu nebo bez proudu. Displej: za běhu rolují řádky kódu, při pauze text stojí, při chybě
--- stojí červeně, bez kódu a bez proudu je zhasnutý. Kreslí se přes rendering (objekty se uloží do stavu
--- kontroléru) a mění se jen při změně stavu – animace přehrává engine sám (prototypes/led.lua, lcd.lua),
--- takže to nestojí výkon.
local graphics = require("prototypes.graphics_data")

local M = {}

--- Barvy stavů (tint bílé záře) – laditelné.
M.COLORS = {
  run = { r = 0.25, g = 1.0, b = 0.3 },
  pause = { r = 1.0, g = 0.8, b = 0.1 },
  error = { r = 1.0, g = 0.12, b = 0.08 },
}

--- Rychlost rolování textu na displeji (snímků = řádků za tick) – laditelné.
M.LCD_SPEED = 1 / 12
--- Barva textu displeje při chybě (násobí zelený text) – laditelné.
M.LCD_ERROR_TINT = { r = 1.0, g = 0.25, b = 0.2 }

--- Stav LED podle kontroléru.
--- @return string "off" | "run" | "pause" | "error"
function M.state(ctl)
  if ctl.error then return "error" end
  if ctl.code == "" then return "off" end
  if ctl.running then return ctl.outage_since and "off" or "run" end
  return "pause"
end

--- Index směru entity 1–4 (defines.direction: sever 0, východ 4, jih 8, západ 12).
local function direction(entity)
  return math.floor(entity.direction / 4) % 4 + 1
end

--- Nakreslí displej pro stav (starý objekt zruší); bez kódu, bez proudu a u neplatné entity zhasne.
local function draw_lcd(ctl, state)
  if ctl.lcd and ctl.lcd.valid then ctl.lcd.destroy() end
  ctl.lcd = nil
  if state == "off" or not ctl.entity.valid then return end
  local d = direction(ctl.entity)
  if not graphics.lcd[d] then return end  -- displej otočený od kamery
  ctl.lcd = rendering.draw_animation({
    animation = "pyntr-lcd-" .. d,
    target = { entity = ctl.entity, offset = graphics.lcd[d].offset },
    surface = ctl.entity.surface,
    render_layer = "higher-object-under",
    animation_speed = state == "run" and M.LCD_SPEED or 0,
    tint = state == "error" and M.LCD_ERROR_TINT or nil,
  })
end

--- Překreslí LED a displej, pokud se změnil stav (nebo `force` – např. po otočení budovy).
--- @param ctl table kontrolér
--- @param force boolean|nil
function M.update(ctl, force)
  local state = M.state(ctl)
  if state == ctl.led_state and not force and (state == "off" or (ctl.led and ctl.led.valid)) then return end
  if ctl.led and ctl.led.valid then ctl.led.destroy() end
  ctl.led, ctl.led_state = nil, state
  draw_lcd(ctl, state)
  if state == "off" or not ctl.entity.valid then return end
  local params = {
    target = { entity = ctl.entity, offset = graphics.led[direction(ctl.entity)] },
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
