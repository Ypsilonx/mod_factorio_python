--- Testy stavové LED (blikátka): stav kontroléru → animace/barva, překreslení jen při změně, poloha podle směru.
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
    A.eq(#log.created, 1, "jednou")
    A.eq(log.created[1].kind, "animation", "běh = animace blikání")
    ctl.running = false
    indicator.update(ctl)
    A.eq(#log.created, 2, "změna")
    A.eq(log.created[1].valid, false, "starý zrušen")
    A.eq(log.created[2].kind, "sprite", "pauza = trvalé světlo")
    ctl.code = ""
    indicator.update(ctl)
    A.eq(log.created[2].valid, false, "bez kódu zhasne")
    A.eq(#log.created, 2, "nic nového")
  end },
  { "poloha LED podle směru entity, při otočení se překreslí", function()
    local indicator, ctl, log = setup()
    local data = require("prototypes.graphics_data")
    ctl.code, ctl.running = "x", true
    indicator.update(ctl)
    A.eq(log.created[1].params.target.offset[1], data.led[1][1], "sever x")
    ctl.entity.direction = 4
    indicator.update(ctl, true)
    A.eq(log.created[2].params.target.offset[2], data.led[2][2], "východ y")
  end },
}
