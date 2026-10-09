--- Testy panelů okna: globály, vstupy a výstupy drátů, stav prvků knihovny, log print() a periodická obnova.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")
local F = require("fake_gui")

--- Čerstvé prostředí: hráč, budova se skrytými výstupy a programem, otevřené okno.
local function setup(code)
  G.reset()
  for _, name in ipairs({ "scripts.gui.window", "scripts.gui.editor", "scripts.gui.events", "scripts.gui.status",
                          "scripts.gui.panels" }) do
    package.loaded[name] = nil
  end
  local player = F.player(1)
  F.install({ player })
  local controller = require("scripts.controller")
  local e = G.entity(1)
  e.name = "pyntr-pythonator"
  local ctl = controller.create(e)
  ctl.outputs = { red = G.output(), green = G.output() }
  require("scripts.actions").play(ctl, code or "def loop():\n  pass")
  local t = { player = player, ctl = ctl, entity = e, controller = controller,
              panels = require("scripts.gui.panels"), events = require("scripts.gui.events"),
              window = require("scripts.gui.window") }
  t.events.on_gui_opened({ player_index = 1, entity = e })
  t.refs = t.window.get(player)
  return t
end

return {
  { "řádky globálů: řazené, zkrácený repr, bez #lib", function()
    local t = setup()
    local R = require("scripts.lang.builtins")
    local long = {}
    for i = 1, 100 do long[i] = i end
    local rows = t.panels.rows_globals({ b = 2, a = R.list(long, 100), ["#lib"] = {} })
    A.eq(#rows, 2, "dva globály")
    A.eq(rows[1][1], "a", "řazení"); A.eq(rows[2][1], "b", "řazení")
    A.eq(#rows[1][2], t.panels.REPR_MAX, "zkrácený repr")
    A.truthy(rows[1][2]:find("…$"), "zkrácení označené")
    A.eq(rows[2][2], "2", "repr čísla")
  end },
  { "řádky signálů: ikona podle typu, ořez na PANEL_MAX_ROWS a zbytek", function()
    local t = setup()
    local pairs_ = { { "iron-plate", 5 }, { "signal-A", -1 }, { "water", 3 }, { "recipe:iron-plate", 1 } }
    local rows, rest = t.panels.rows_signals(pairs_, 10)
    A.eq(rows[1].sprite, "item/iron-plate", "item")
    A.eq(rows[2].sprite, "virtual-signal/signal-A", "virtual")
    A.eq(rows[4].sprite, "recipe/iron-plate", "recipe")
    A.eq(rows[1].number, 5, "číslo"); A.eq(rest, 0, "nic navíc")
    local _, rest2 = t.panels.rows_signals(pairs_, 3)
    A.eq(rest2, 1, "zbytek nad limit")
  end },
  { "obnova: vstupy z drátů, výstupy podle skutečného stavu drátu, globály a log", function()
    local t = setup("n = 0\ndef loop():\n  global n\n  n += 1\n  out['signal-A'] = n\n  print('n', n)")
    t.entity.red["iron-plate"] = 7
    t.entity.green["signal-B"] = 2
    t.controller.run_loop(t.ctl, 1)
    t.events.on_gui_click({ player_index = 1, element = t.refs.log_toggle })
    t.events.on_refresh()
    local r = t.refs
    A.eq(#r.in_red.children, 1, "červený vstup"); A.eq(r.in_red.children[1].number, 7, "hodnota")
    A.eq(#r.in_green.children, 1, "zelený vstup")
    A.eq(r.out_red.children[1].number, 1, "výstup na červeném drátu")
    A.eq(r.globals.children[2].caption, "1", "globál n")
    A.eq(r.log.children[#r.log.children].caption, "n 1", "poslední řádek logu")
  end },
  { "výstupy po chybě ukazují stav drátu, ne rozepsané výstupy programu", function()
    local t = setup("n = 0\ndef loop():\n  global n\n  n += 1\n  out['signal-A'] = n\n  if n == 2:\n    x = 1 // 0")
    t.controller.run_loop(t.ctl, 1)
    t.controller.run_loop(t.ctl, 2)
    A.truthy(t.ctl.error, "chyba ve 2. běhu")
    t.events.on_refresh()
    A.eq(t.ctl.out.both["signal-A"], 2, "program zapsal 2")
    A.eq(t.refs.out_red.children[1].number, 1, "na drátu zůstala 1")
  end },
  { "výkon: z 300 vstupních signálů se převádí jen zobrazené (bez řazení celé sady)", function()
    local t = setup()
    for i = 1, 300 do t.entity.red["sig-" .. i] = i end
    local res = require("scripts.resolver").get()
    local orig, calls = res.canonical, 0
    res.canonical = function(...) calls = calls + 1; return orig(...) end
    t.events.on_refresh()
    res.canonical = nil
    A.eq(#t.refs.in_red.children, t.panels.PANEL_MAX_ROWS + 1, "zobrazeno PANEL_MAX_ROWS + „další“")
    A.eq(t.refs.in_red.children[t.panels.PANEL_MAX_ROWS + 1].number, 300 - t.panels.PANEL_MAX_ROWS, "počet dalších")
    A.truthy(calls <= t.panels.PANEL_MAX_ROWS, "převedeno jen zobrazené (" .. calls .. ")")
  end },
  { "výkon: repr velkého globálu se zastaví u REPR_MAX", function()
    local t = setup()
    local R = require("scripts.lang.builtins")
    local visits = 0
    local mt = { __pyntr = "obj", __repr_py = function() visits = visits + 1; return "o" end }
    local arr = {}
    for i = 1, 10000 do arr[i] = setmetatable({}, mt) end
    local rows = t.panels.rows_globals({ big = R.list(arr, 10000) })
    A.truthy(visits <= t.panels.REPR_MAX, "navštíveno jen na začátek (" .. visits .. ")")
    A.eq(rows[1][2]:sub(1, 7), "[o, o, ", "začátek repr")
    A.truthy(rows[1][2]:find("…$"), "zkrácení označené")
    A.eq(t.panels.rows_globals({ s = R.list({ 1, 2 }, 2) })[1][2], "[1, 2]", "krátký repr celý")
  end },
  { "výkon: obnova beze změny nepřepisuje ikony signálů", function()
    local t = setup()
    t.entity.red["iron-plate"] = 7
    t.events.on_refresh()
    local cell = t.refs.in_red.children[1]
    cell.number = "nezapsáno"
    t.events.on_refresh()
    A.eq(cell.number, "nezapsáno", "beze změny žádný zápis")
    t.entity.red["iron-plate"] = 8
    t.events.on_refresh()
    A.eq(cell.number, 8, "změna se zapíše")
  end },
  { "stav prvků knihovny", function()
    local t = setup("def loop():\n  latch('plné', 1, 0)\n  counter('kusy', 3)")
    t.controller.run_loop(t.ctl, 1)
    local rows = t.panels.rows_elements(t.ctl.globals["#lib"])
    A.eq(rows[1][1], "kusy", "řazení podle jména")
    A.same(rows[1][2], { "pyntr-gui.element-counter", "3" }, "counter")
    A.same(rows[2][2], { "pyntr-gui.element-latch", "True" }, "latch")
  end },
  { "obnova bez otevřených oken nic nedělá, zavřené okno se přeskočí", function()
    local t = setup()
    t.window.close(t.player)
    t.events.on_refresh()
    storage.gui = nil
    t.events.on_refresh()
  end },
  { "log se rozbalí a sbalí tlačítkem", function()
    local t = setup()
    A.eq(t.refs.log_pane.visible, false, "výchozí sbalený")
    t.events.on_gui_click({ player_index = 1, element = t.refs.log_toggle })
    A.eq(t.refs.log_pane.visible, true, "rozbalený")
  end },
}
