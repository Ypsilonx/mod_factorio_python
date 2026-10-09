--- Testy okna nápovědy: karty, příklady (každý se musí přeložit) a vložení příkladu do editoru.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")
local F = require("fake_gui")
local compiler = require("scripts.lang.compiler")
local signals = require("scripts.lang.signals")
local fake = require("fake_protos")

--- Čerstvé prostředí: hráč, budova s programem a otevřené hlavní okno.
local function setup()
  G.reset()
  for _, name in ipairs({ "scripts.gui.window", "scripts.gui.editor", "scripts.gui.events", "scripts.gui.status",
                          "scripts.gui.panels", "scripts.gui.help" }) do
    package.loaded[name] = nil
  end
  local player = F.player(1)
  F.install({ player })
  local e = G.entity(1)
  e.name = "pyntr-pythonator"
  local ctl = require("scripts.controller").create(e)
  require("scripts.actions").play(ctl, "def loop():\n  pass")
  local t = { player = player, ctl = ctl, help = require("scripts.gui.help"),
              events = require("scripts.gui.events"), window = require("scripts.gui.window") }
  t.events.on_gui_opened({ player_index = 1, entity = e })
  t.refs = t.window.get(player)
  return t
end

local function click(t, element) t.events.on_gui_click({ player_index = 1, element = element }) end

return {
  { "každý příklad nápovědy se přeloží", function()
    local help = require("scripts.gui.help")
    A.truthy(#help.EXAMPLES >= 5, "aspoň pět příkladů")
    for i, ex in ipairs(help.EXAMPLES) do
      local prog, err = compiler.compile(ex.code, signals.new_resolver(fake()))
      A.truthy(prog, "příklad " .. i .. " (" .. ex.id .. "): " .. tostring(err and err.key))
    end
  end },
  { "tlačítko ? otevře nápovědu s kartami, křížek ji zavře", function()
    local t = setup()
    click(t, t.refs.help)
    local frame = t.player.gui.screen.pyntr_help
    A.truthy(frame and frame.valid, "okno nápovědy")
    local tabs = frame.pyntr_help_tabs
    A.eq(#tabs.children, (#t.help.SECTIONS + 1) * 2, "karta + obsah pro každou sekci a příklady")
    A.truthy(t.window.get(t.player), "hlavní okno zůstalo otevřené")
    click(t, frame.pyntr_help_titlebar.pyntr_help_close)
    A.eq(frame.valid, false, "nápověda zavřená")
  end },
  { "vložení příkladu při pauze nahradí text editoru a uloží draft", function()
    local t = setup()
    click(t, t.refs.pause)
    click(t, t.refs.help)
    local button = t.help.example_buttons(t.player)[2]
    click(t, button)
    local code = t.help.EXAMPLES[2].code
    A.eq(t.refs.code.text, code, "text editoru")
    A.eq(t.ctl.draft, code, "draft")
  end },
  { "za běhu příklad nevloží", function()
    local t = setup()
    click(t, t.refs.help)
    click(t, t.help.example_buttons(t.player)[1])
    A.eq(t.ctl.draft, nil, "bez draftu")
    A.eq(t.refs.code.text, "def loop():\n  pass", "text beze změny")
  end },
  { "druhé otevření nápovědy nevytvoří druhé okno", function()
    local t = setup()
    click(t, t.refs.help)
    click(t, t.refs.help)
    local n = 0
    for _, c in ipairs(t.player.gui.screen.children) do if c.name == "pyntr_help" then n = n + 1 end end
    A.eq(n, 1, "jedno okno nápovědy")
  end },
}
