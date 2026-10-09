--- Testy společných akcí GUI a remote (Play, Pauza, Reset, Krok, draft) a pohledu `view` pro GUI.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")

local OK = "n = 0\ndef loop():\n  global n\n  n += 1"

--- Čerstvé prostředí, moduly a kontrolér s falešnou entitou.
local function setup()
  G.reset()
  local actions = require("scripts.actions")
  local controller = require("scripts.controller")
  return actions, controller, controller.create(G.entity(3))
end

return {
  { "view bez kódu: jen úpravy a Play nového textu", function()
    local actions, _, ctl = setup()
    local v = actions.view(ctl)
    A.eq(v.state, "off", "stav")
    A.same(v.can, { play = false, pause = false, reset = false, step = false, edit = true }, "akce")
    actions.set_draft(ctl, OK)
    A.eq(actions.view(ctl).can.play, true, "s rozepsaným kódem jde Play")
  end },
  { "Play s novým textem nahraje kód, smaže draft a běží", function()
    local actions, _, ctl = setup()
    actions.set_draft(ctl, OK)
    A.eq(actions.play(ctl, OK), true, "ok")
    A.eq(ctl.code, OK, "kód"); A.eq(ctl.draft, nil, "draft smazán")
    local v = actions.view(ctl)
    A.eq(v.state, "running", "stav")
    A.same(v.can, { play = false, pause = true, reset = true, step = false, edit = false }, "za běhu")
    A.eq(storage.schedule[game.tick + 1] ~= nil, true, "probuzení do plánovače")
  end },
  { "Pauza, Krok, Play se stejným textem pokračuje", function()
    local actions, _, ctl = setup()
    actions.play(ctl, OK)
    actions.pause(ctl)
    local v = actions.view(ctl)
    A.eq(v.state, "paused", "pauza")
    A.same(v.can, { play = true, pause = false, reset = true, step = true, edit = true }, "při pauze")
    A.eq(actions.step(ctl, 10), true, "krok")
    A.eq(ctl.globals.n, 1, "krok provedl loop()")
    A.eq(actions.play(ctl, OK), true, "pokračování")
    A.eq(ctl.globals.n, 1, "stejný text nespustí init")
    A.eq(ctl.running, true, "běží")
  end },
  { "Play s chybou překladu: pauza, chyba, draft zůstane", function()
    local actions, _, ctl = setup()
    actions.play(ctl, OK)
    actions.pause(ctl)
    actions.set_draft(ctl, "def loop(:")
    local ok, err = actions.play(ctl, "def loop(:")
    A.eq(ok, false, "neprošlo"); A.truthy(err, "chyba")
    A.eq(ctl.code, OK, "starý kód zůstal")
    A.eq(ctl.draft, "def loop(:", "draft zůstal")
    local v = actions.view(ctl)
    A.eq(v.state, "paused", "stav"); A.truthy(v.compile_error, "chyba překladu v pohledu")
  end },
  { "chyba běhu: jen Reset, nebo Play nového textu", function()
    local actions, controller, ctl = setup()
    actions.play(ctl, "def loop():\n  x = 1 // 0")
    controller.run_loop(ctl, 1)
    local v = actions.view(ctl)
    A.eq(v.state, "error", "stav"); A.eq(v.error.line, 2, "řádek chyby")
    A.same(v.can, { play = false, pause = false, reset = true, step = false, edit = true }, "po chybě")
    actions.set_draft(ctl, OK)
    A.eq(actions.view(ctl).can.play, true, "nový text jde spustit")
    A.eq(actions.play(ctl, OK), true, "spuštění nového kódu")
    A.eq(actions.view(ctl).state, "running", "běží")
  end },
  { "Reset při pauze nechá pauzu a vynuluje globály", function()
    local actions, _, ctl = setup()
    actions.play(ctl, OK)
    actions.pause(ctl)
    actions.step(ctl, 5)
    A.eq(actions.reset(ctl), true, "reset")
    A.eq(ctl.globals.n, 0, "globály od nuly"); A.eq(ctl.running, false, "pauza zůstala")
  end },
  { "draft stejný jako kód se neukládá; bez proudu", function()
    local actions, _, ctl = setup()
    actions.play(ctl, OK)
    actions.set_draft(ctl, OK)
    A.eq(ctl.draft, nil, "nezměněný text")
    ctl.outage_since = 1
    A.eq(actions.view(ctl).state, "no_power", "bez proudu")
  end },
  { "odstranění budovy zavolá posluchače (GUI zavře okna)", function()
    local _, _, ctl = setup()
    local lifecycle = require("scripts.lifecycle")
    local got
    lifecycle.on_removed[#lifecycle.on_removed + 1] = function(unit) got = unit end
    lifecycle.remove(ctl.unit)
    A.eq(got, 3, "unit odstraněné budovy")
    A.eq(require("scripts.controller").get(3), nil, "stav smazán")
  end },
  { "view: cena a limit watchdogu", function()
    local actions, controller, ctl = setup()
    actions.play(ctl, OK)
    controller.run_loop(ctl, 1)
    local v = actions.view(ctl)
    A.eq(v.limit, 10000, "limit z nastavení mapy"); A.truthy(v.used > 0, "cena posledního běhu")
    A.eq(v.tick, ctl.tick, "tick")
  end },
}
