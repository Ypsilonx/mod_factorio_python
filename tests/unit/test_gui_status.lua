--- Testy lišty tlačítek, panelu stavu a pruhu chyby v okně (bez hry, napodobenina GUI).
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")
local F = require("fake_gui")

local CODE = "n = 0\ndef loop():\n  global n\n  n += 1"

--- Čerstvé prostředí: dva hráči, budova s nahraným kódem, okno hráče 1 otevřené.
local function setup()
  G.reset()
  for _, name in ipairs({ "scripts.gui.window", "scripts.gui.editor", "scripts.gui.events", "scripts.gui.status" }) do
    package.loaded[name] = nil
  end
  local players = { F.player(1), F.player(2) }
  F.install(players)
  local controller = require("scripts.controller")
  local actions = require("scripts.actions")
  local e = G.entity(1)
  e.name = "pyntr-pythonator"
  local ctl = controller.create(e)
  actions.play(ctl, CODE)
  local t = {
    players = players, ctl = ctl, controller = controller, actions = actions,
    window = require("scripts.gui.window"), events = require("scripts.gui.events"),
  }
  t.events.on_gui_opened({ player_index = 1, entity = e })
  t.refs = t.window.get(players[1])
  return t
end

--- Klikne na tlačítko hráče `pi` (výchozí 1).
local function click(t, element, pi)
  t.events.on_gui_click({ player_index = pi or 1, element = element })
end

--- Napíše text do editoru hráče 1.
local function type_text(t, text)
  t.refs.code.text = text
  t.events.on_gui_text_changed({ player_index = 1, element = t.refs.code })
end

return {
  { "za běhu: povolená pauza a reset, stav BĚŽÍ", function()
    local t = setup()
    local r = t.refs
    A.eq(r.play.enabled, false, "play"); A.eq(r.pause.enabled, true, "pause")
    A.eq(r.reset.enabled, true, "reset"); A.eq(r.step.enabled, false, "step")
    A.same(r.state.caption, { "pyntr-gui.state-running" }, "stav")
  end },
  { "pauza, krok a pokračování tlačítky", function()
    local t = setup()
    local r = t.refs
    click(t, r.pause)
    A.eq(t.ctl.running, false, "pozastaveno")
    A.same(r.state.caption, { "pyntr-gui.state-paused" }, "stav po pauze")
    A.eq(r.step.enabled, true, "krok povolen"); A.eq(r.code.read_only, false, "editor odemčen")
    click(t, r.step)
    A.eq(t.ctl.globals.n, 1, "krok provedl loop()")
    A.same(r.tick.caption, { "pyntr-gui.tick", t.ctl.tick }, "tick po kroku")
    click(t, r.play)
    A.eq(t.ctl.running, true, "běží")
    A.eq(r.code.read_only, true, "za běhu jen pro čtení")
  end },
  { "Play s chybou překladu: pruh chyby s řádkem, červené číslo řádku, kód neběží", function()
    local t = setup()
    local r = t.refs
    click(t, r.pause)
    type_text(t, "n = 0\ndef loop():\n  n +=\n")
    click(t, r.play)
    A.eq(t.ctl.running, false, "zůstala pauza")
    A.eq(r.error_bar.visible, true, "pruh chyby")
    A.eq(r.error_label.caption[2][2], 3, "řádek chyby v textu")
    A.eq(r.gutter.children[3].style.font_color, require("scripts.gui.editor").COLOR_ERROR, "červený řádek")
    A.eq(r.code.text, "n = 0\ndef loop():\n  n +=\n", "draft zůstal v editoru")
    click(t, r.error_label)
    A.eq(r.scroll.scrolled_to, r.gutter.children[3], "klik na chybu posune na řádek")
  end },
  { "chyba běhu: jen reset, pruh chyby; oprava kódu a Play chybu smaže", function()
    local t = setup()
    local r = t.refs
    click(t, r.pause)
    type_text(t, "def loop():\n  x = 1 // 0")
    click(t, r.play)
    t.controller.run_loop(t.ctl, 5)
    t.window.refresh(t.players[1])
    A.same(r.state.caption, { "pyntr-gui.state-error" }, "stav CHYBA")
    A.eq(r.play.enabled, false, "play bez změny textu nejde")
    A.eq(r.reset.enabled, true, "reset jde")
    A.eq(r.error_bar.visible, true, "pruh chyby")
    type_text(t, CODE)
    A.eq(r.play.enabled, true, "nový text jde spustit")
    click(t, r.play)
    A.eq(r.error_bar.visible, false, "chyba zmizela")
    A.eq(r.gutter.children[2].style.font_color, require("scripts.gui.editor").COLOR_LINE, "řádek bez zvýraznění")
  end },
  { "výkon: zvýraznění řádku chyby se při obnově beze změny nepřepisuje", function()
    local t = setup()
    local editor = require("scripts.gui.editor")
    t.controller.run_loop(t.ctl, 1)
    t.events.on_refresh()
    local orig, calls = editor.mark_error, 0
    editor.mark_error = function(...) calls = calls + 1; return orig(...) end
    t.events.on_refresh()
    t.events.on_refresh()
    editor.mark_error = orig
    A.eq(calls, 0, "beze změny chyby ani počtu řádků žádné přebarvení")
  end },
  { "cena posledního běhu proti limitu", function()
    local t = setup()
    t.controller.run_loop(t.ctl, 1)
    t.window.refresh(t.players[1])
    A.same(t.refs.cost.caption, { "pyntr-gui.cost", t.ctl.used, 10000 }, "text ceny")
    A.eq(t.refs.cost_bar.value, t.ctl.used / 10000, "pruh ceny")
  end },
  { "akce jednoho hráče obnoví okno druhého", function()
    local t = setup()
    t.events.on_gui_opened({ player_index = 2, entity = t.ctl.entity })
    local other = t.window.get(t.players[2])
    click(t, t.refs.pause)
    A.same(other.state.caption, { "pyntr-gui.state-paused" }, "okno hráče 2 vidí pauzu")
    A.eq(other.step.enabled, true, "a povolený krok")
  end },
}
