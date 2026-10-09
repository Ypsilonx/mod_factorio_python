--- Testy stavové LED (blikátka) a displeje: stav kontroléru → animace/barva, překreslení jen při změně,
--- poloha podle směru, rolující text displeje za běhu, zastavený při pauze a červený při chybě.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")

--- Falešné rendering API: zaznamenává vytvořené objekty.
local function fake_rendering()
  local log = { created = {} }
  local function make(kind, params)
    local obj = { kind = kind, params = params, valid = true }
    function obj.destroy() obj.valid = false end
    log.created[#log.created + 1] = obj
    return obj
  end
  _G.rendering = {
    draw_animation = function(p) return make("animation", p) end,
    draw_sprite = function(p) return make("sprite", p) end,
  }
  return log
end

--- Objekty LED (bez displeje) v pořadí vytvoření.
local function leds(log)
  local out = {}
  for _, o in ipairs(log.created) do
    if not (o.params.animation or ""):find("^pyntr%-lcd") then out[#out + 1] = o end
  end
  return out
end

--- Objekty displeje v pořadí vytvoření.
local function lcds(log)
  local out = {}
  for _, o in ipairs(log.created) do
    if (o.params.animation or ""):find("^pyntr%-lcd") then out[#out + 1] = o end
  end
  return out
end

--- Prostředí s kontrolérem a falešným renderingem.
local function setup()
  G.reset()
  package.loaded["scripts.indicator"] = nil
  local log = fake_rendering()
  local entity = G.entity(5)
  entity.direction, entity.surface = 0, "nauvis"
  local ctl = { entity = entity, code = "", running = false }
  return require("scripts.indicator"), ctl, log
end

return {
  { "stav: bez kódu nic, běh bliká zeleně, pauza svítí žlutě, chyba červeně, bez proudu nic", function()
    local indicator, ctl = setup()
    A.eq(indicator.state(ctl), "off", "bez kódu")
    ctl.code, ctl.running = "x", true
    A.eq(indicator.state(ctl), "run", "běží")
    ctl.outage_since = 10
    A.eq(indicator.state(ctl), "off", "bez proudu")
    ctl.outage_since, ctl.running = nil, false
    A.eq(indicator.state(ctl), "pause", "pauza")
    ctl.error = { key = "x" }
    A.eq(indicator.state(ctl), "error", "chyba")
  end },
  { "překreslí jen při změně stavu, starý objekt zruší", function()
    local indicator, ctl, log = setup()
    ctl.code, ctl.running = "x", true
    indicator.update(ctl)
    indicator.update(ctl)
    local l = leds(log)
    A.eq(#l, 1, "jednou")
    A.eq(l[1].kind, "animation", "běh = animace blikání")
    ctl.running = false
    indicator.update(ctl)
    l = leds(log)
    A.eq(#l, 2, "změna")
    A.eq(l[1].valid, false, "starý zrušen")
    A.eq(l[2].kind, "sprite", "pauza = trvalé světlo")
    ctl.code = ""
    indicator.update(ctl)
    A.eq(leds(log)[2].valid, false, "bez kódu zhasne")
    A.eq(#leds(log), 2, "nic nového")
  end },
  { "poloha LED podle směru entity, při otočení se překreslí", function()
    local indicator, ctl, log = setup()
    local data = require("prototypes.graphics_data")
    ctl.code, ctl.running = "x", true
    indicator.update(ctl)
    A.eq(leds(log)[1].params.target.offset[1], data.led[1][1], "sever x")
    ctl.entity.direction = 4
    indicator.update(ctl, true)
    A.eq(leds(log)[2].params.target.offset[2], data.led[2][2], "východ y")
  end },
  { "displej: za běhu roluje, pauza zastaví, chyba zčervená, bez kódu a bez proudu zhasne", function()
    local indicator, ctl, log = setup()
    local data = require("prototypes.graphics_data")
    ctl.code, ctl.running = "x", true
    indicator.update(ctl)
    local d = lcds(log)
    A.eq(#d, 1, "displej nakreslen")
    A.eq(d[1].params.animation, "pyntr-lcd-1", "animace pro sever")
    A.eq(d[1].params.animation_speed, indicator.LCD_SPEED, "roluje")
    A.eq(d[1].params.target.offset, data.lcd[1].offset, "poloha výřezu displeje")
    A.eq(ctl.lcd, d[1], "objekt uložený v kontroléru")
    ctl.running = false
    indicator.update(ctl)
    d = lcds(log)
    A.eq(d[1].valid, false, "starý displej zrušen")
    A.eq(d[2].params.animation_speed, 0, "pauza = zastavený text")
    A.eq(d[2].params.tint, nil, "bez barvy")
    ctl.error = { key = "x" }
    indicator.update(ctl)
    A.eq(lcds(log)[3].params.tint, indicator.LCD_ERROR_TINT, "chyba = červený text")
    ctl.error, ctl.running, ctl.outage_since = nil, true, 5
    indicator.update(ctl)
    A.eq(#lcds(log), 3, "bez proudu nový displej nevznikne")
    A.eq(lcds(log)[3].valid, false, "a starý zhasne")
  end },
  { "displej po otočení budovy: animace a poloha nového směru", function()
    local indicator, ctl, log = setup()
    local data = require("prototypes.graphics_data")
    ctl.code, ctl.running = "x", true
    ctl.entity.direction = 4
    indicator.update(ctl, true)
    A.eq(lcds(log)[1].params.animation, "pyntr-lcd-2", "východ")
    A.eq(lcds(log)[1].params.target.offset, data.lcd[2].offset, "poloha východ")
    ctl.entity.direction = 8
    indicator.update(ctl, true)
    A.eq(data.lcd[3], false, "na jihu je displej otočený od kamery")
    A.eq(#lcds(log), 1, "na jihu se displej nekreslí")
    A.eq(lcds(log)[1].valid, false, "displej z předchozího směru zrušen")
    A.eq(ctl.lcd, nil, "bez objektu displeje")
  end },
}
