--- Testy okna Pythonatoru bez hry: otevření a zavření, editor s čísly řádků, rozepsaný kód, přepnutí budovy.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")
local F = require("fake_gui")

local CODE = "n = 0\ndef loop():\n  global n\n  n += 1"

--- Čerstvé prostředí: hráč, dvě budovy s nahraným kódem, moduly GUI.
local function setup()
  G.reset()
  for _, name in ipairs({ "scripts.gui.window", "scripts.gui.editor", "scripts.gui.events" }) do
    package.loaded[name] = nil
  end
  local player = F.player(1)
  F.install({ player })
  local controller = require("scripts.controller")
  local actions = require("scripts.actions")
  local ctls = {}
  for unit = 1, 2 do
    local e = G.entity(unit)
    e.name = "pyntr-pythonator"
    ctls[unit] = controller.create(e)
    actions.play(ctls[unit], CODE)
  end
  return {
    player = player, ctls = ctls, actions = actions,
    window = require("scripts.gui.window"), editor = require("scripts.gui.editor"),
    events = require("scripts.gui.events"),
  }
end

--- Otevře okno budovy událostí on_gui_opened.
local function open(t, unit)
  t.events.on_gui_opened({ player_index = 1, entity = t.ctls[unit].entity })
  return t.window.get(t.player)
end

--- Napíše text do editoru (jako hráč) a vyvolá on_gui_text_changed.
local function type_text(refs, text)
  refs.code.text = text
  require("scripts.gui.events").on_gui_text_changed({ player_index = 1, element = refs.code })
end

return {
  { "otevření budovy postaví okno s kódem a otevře ho jako player.opened", function()
    local t = setup()
    local refs = open(t, 1)
    A.truthy(refs and refs.frame.valid, "okno existuje")
    A.eq(t.player.opened, refs.frame, "player.opened = naše okno")
    A.eq(storage.gui[1].unit, 1, "stav okna ve storage")
    A.eq(refs.code.text, CODE, "text editoru = kód")
    A.eq(refs.code.icon_selector, true, "výběr ikon signálů")
  end },
  { "čísla řádků a výška editoru podle počtu řádků", function()
    local t = setup()
    local refs = open(t, 1)
    local E = t.editor
    A.eq(#refs.gutter.children, math.max(4, E.MIN_LINES), "řádků v gutteru (min. MIN_LINES)")
    A.eq(refs.gutter.children[3].caption, "3", "číslo řádku")
    A.eq(refs.code.style.height, E.MIN_LINES * E.LINE_HEIGHT + E.HEIGHT_RESERVE, "výška pro krátký kód")
    local long = {}
    for i = 1, E.MIN_LINES + 10 do long[i] = "x" .. i .. " = 0" end
    t.actions.pause(t.ctls[1])
    t.window.refresh(t.player)
    type_text(refs, table.concat(long, "\n"))
    A.eq(#refs.gutter.children, E.MIN_LINES + 10, "gutter roste s textem")
    A.eq(refs.code.style.height, (E.MIN_LINES + 10) * E.LINE_HEIGHT + E.HEIGHT_RESERVE, "box roste s textem")
  end },
  { "psaní uloží draft a posune pohled na změněný řádek", function()
    local t = setup()
    t.actions.pause(t.ctls[1])
    local refs = open(t, 1)
    type_text(refs, (CODE:gsub("n %+= 1", "n += 2")))
    A.eq(t.ctls[1].draft, (CODE:gsub("n %+= 1", "n += 2")), "draft")
    A.eq(refs.scroll.scrolled_to, refs.gutter.children[4], "posun na řádek 4")
  end },
  { "zavření a znovuotevření ukáže rozepsaný kód", function()
    local t = setup()
    t.actions.pause(t.ctls[1])
    local refs = open(t, 1)
    type_text(refs, "def loop():\n  pass")
    t.events.on_gui_closed({ player_index = 1, element = refs.frame })
    A.eq(t.window.get(t.player), nil, "okno zavřené")
    A.eq(storage.gui[1], nil, "stav okna smazán")
    A.eq(open(t, 1).code.text, "def loop():\n  pass", "draft po znovuotevření")
  end },
  { "za běhu je editor jen pro čtení a ukazuje nahraný kód", function()
    local t = setup()
    t.ctls[1].draft = "rozepsáno"
    local refs = open(t, 1)
    A.eq(refs.code.read_only, true, "jen pro čtení")
    A.eq(refs.code.text, CODE, "běžící kód, ne draft")
    t.actions.pause(t.ctls[1])
    t.window.refresh(t.player)
    A.eq(refs.code.read_only, false, "při pauze lze psát")
    A.eq(refs.code.text, "rozepsáno", "při pauze draft")
  end },
  { "otevření jiné budovy přepne okno", function()
    local t = setup()
    local first = open(t, 1)
    local second = open(t, 2)
    A.eq(first.frame.valid, false, "staré okno zničené")
    A.eq(second.frame.valid, true, "nové okno")
    A.eq(storage.gui[1].unit, 2, "okno patří budově 2")
    A.eq(#t.player.gui.screen.children, 1, "jen jedno okno")
  end },
  { "zbourání budovy zavře okno", function()
    local t = setup()
    local refs = open(t, 1)
    require("scripts.lifecycle").remove(1)
    A.eq(refs.frame.valid, false, "okno zničené")
    A.eq(storage.gui[1], nil, "stav okna smazán")
  end },
  { "křížek v titulku zavře okno", function()
    local t = setup()
    local refs = open(t, 1)
    t.events.on_gui_click({ player_index = 1, element = refs.close })
    A.eq(refs.frame.valid, false, "okno zničené")
  end },
  { "cizí entita okno neotevře", function()
    local t = setup()
    t.events.on_gui_opened({ player_index = 1, entity = { valid = true, name = "arithmetic-combinator" } })
    A.eq(t.window.get(t.player), nil, "žádné okno")
  end },
  { "odchod hráče ze hry zavře okno, odebrání hráče uklidí stav", function()
    local t = setup()
    local refs = open(t, 1)
    t.events.on_player_left_game({ player_index = 1 })
    A.eq(refs.frame.valid, false, "okno zavřené při odchodu")
    open(t, 1)
    game.players[1] = nil
    t.events.on_player_removed({ player_index = 1 })
    A.eq(storage.gui[1], nil, "stav odebraného hráče smazán")
  end },
  { "změna konfigurace modů zavře okna i nápovědu a uklidí stav", function()
    local t = setup()
    local refs = open(t, 1)
    t.events.on_gui_click({ player_index = 1, element = refs.help })
    local help = t.player.gui.screen.pyntr_help
    -- zbytek okna ze staré verze bez záznamu ve storage
    local stale = t.player.gui.screen.add({ type = "frame", name = "pyntr_stale" })
    storage.gui[7] = { unit = 1, refs = { frame = { valid = false } } }
    t.events.on_configuration_changed()
    A.eq(refs.frame.valid, false, "hlavní okno zavřené")
    A.eq(help.valid, false, "nápověda zavřená")
    A.eq(stale.valid, false, "cizí zbytek okna s prefixem odstraněn")
    A.eq(next(storage.gui), nil, "storage.gui prázdné")
  end },
  { "neplatné prvky okna: obnova okno bez chyby zavře", function()
    local t = setup()
    local refs = open(t, 1)
    refs.frame.valid = false
    t.events.on_refresh()
    A.eq(storage.gui[1], nil, "stav smazán")
    storage.gui[1] = { unit = 99, refs = { frame = { valid = true, destroy = function() end } } }
    t.events.on_refresh()
    A.eq(storage.gui[1], nil, "okno nad neexistující budovou zavřené")
  end },
}
