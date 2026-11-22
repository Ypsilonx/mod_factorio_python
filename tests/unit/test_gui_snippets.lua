--- Testy šablon editoru: místo psaní z rozdílu textů, vložení šablony, převod bajtů na znaky a klik v okně.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")
local F = require("fake_gui")
local S = require("scripts.gui.snippets")

local INP = S.get("inp")

return {
  { "místo psaní: připsání, vložení doprostřed, smazání", function()
    A.eq(S.caret_after("ab", "abc"), 3, "připsání na konec")
    A.eq(S.caret_after("ac", "abc"), 2, "vložení doprostřed")
    A.eq(S.caret_after("abc", "ac"), 1, "smazání")
    A.eq(S.caret_after("aaa", "aaaa"), 4, "opakované znaky: konec společného začátku")
    A.eq(S.caret_after("", "x = 1"), 5, "první psaní")
  end },
  { "místo psaní nepadne doprostřed znaku UTF-8", function()
    -- "á" = C3 A1, "é" = C3 A9: společný začátek končí uprostřed znaku
    A.eq(S.caret_after("# á!", "# é!"), 4, "za celým znakem é")
  end },
  { "vložení šablony a označení zástupného slova", function()
    local text, first, last, caret = S.insert("x = \n", 4, INP)
    A.eq(text, "x = inp[\"SIGNAL\"]\n", "text")
    A.eq(text:sub(first, last), "SIGNAL", "označený úsek")
    A.eq(caret, 4 + #INP.code, "místo za šablonou")
    A.eq((S.insert("ab", nil, INP)), "ab" .. INP.code, "bez místa psaní na konec")
    A.eq((S.insert("ab", 99, INP)), "ab" .. INP.code, "místo mimo text na konec")
  end },
  { "bajty na znaky pro select", function()
    A.eq(S.char_count("abc", 2), 2, "ASCII")
    A.eq(S.char_count("# čí x", 6), 4, "diakritika: 6 bajtů = 4 znaky")
  end },
  { "klik na šablonu v okně vloží kód na místo psaní a označí SIGNAL", function()
    G.reset()
    for _, name in ipairs({ "scripts.gui.window", "scripts.gui.editor", "scripts.gui.events" }) do
      package.loaded[name] = nil
    end
    local player = F.player(1)
    F.install({ player })
    local controller = require("scripts.controller")
    local e = G.entity(1)
    e.name = "pyntr-pythonator"
    local ctl = controller.create(e)
    local events = require("scripts.gui.events")
    events.on_gui_opened({ player_index = 1, entity = e })
    local refs = require("scripts.gui.window").get(player)
    refs.code.text = "# č\nx = "
    events.on_gui_text_changed({ player_index = 1, element = refs.code })
    events.on_gui_click({ player_index = 1, element = refs.snippets.pyntr_snippets_code.pyntr_snippet_inp })
    A.eq(refs.code.text, "# č\nx = inp[\"SIGNAL\"]", "text po vložení")
    A.eq(refs.code.focused, true, "editor zaměřený")
    -- "# č\nx = inp[\"" = 13 znaků → SIGNAL je 14.–19. znak
    A.eq(refs.code.selection[1], 14, "začátek označení ve znacích")
    A.eq(refs.code.selection[2], 19, "konec označení ve znacích")
    A.eq(require("scripts.actions").text(ctl), refs.code.text, "draft uložený")
  end },
  { "příkaz pod neprázdný řádek s jeho odsazením", function()
    local OUT = S.get("out")
    local text = "def loop():\n    x = 1\n    y = 2"
    local new, first, last = S.insert(text, #"def loop():\n    x = 1", OUT)
    A.eq(new, "def loop():\n    x = 1\n    out[\"SIGNAL\"] = VALUE\n    y = 2", "řádek pod x = 1")
    A.eq(new:sub(first, last), "SIGNAL", "označení")
    A.eq((S.insert("def loop():", 3, OUT)), "def loop():\n    out[\"SIGNAL\"] = VALUE", "za dvojtečkou o úroveň víc")
  end },
  { "příkaz na prázdný řádek ho nahradí, odsazení podle předchozího řádku", function()
    local IF = S.get("if")
    local text = "def loop():\n\nz = 0"
    local new, first, last, caret = S.insert(text, #"def loop():\n", IF)
    A.eq(new, "def loop():\n    if inp[\"SIGNAL\"] > NUMBER:\n        pass\nz = 0", "víceřádková šablona odsazená")
    A.eq(new:sub(first, last), "SIGNAL", "označení")
    A.eq(new:sub(caret, caret + 6), "s\nz = 0", "místo za blokem")
    A.eq((S.insert("if x:\n  ", 8, S.get("print"))), "if x:\n  print(VALUE)", "vlastní odsazení hráče má přednost")
    A.eq((S.insert("", nil, S.get("loop"))), "def loop():\n    pass", "prázdný editor")
  end },
  { "každá šablona má zástupné slovo, tlačítko v liště a popis v en i cs", function()
    local in_rows = {}
    for _, row in ipairs(S.ROWS) do
      for _, id in ipairs(row.snippets) do in_rows[id] = true end
    end
    for _, lang in ipairs({ "en", "cs" }) do
      local f = assert(io.open("Pythonator/locale/" .. lang .. "/locale.cfg", "rb"))
      local src = f:read("a")
      f:close()
      for _, s in ipairs(S.SNIPPETS) do
        A.truthy(src:find("\nsnippet%-" .. s.id .. "="), lang .. ": snippet-" .. s.id)
      end
      for _, row in ipairs(S.ROWS) do
        A.truthy(src:find("\nsnippets%-" .. row.id .. "="), lang .. ": snippets-" .. row.id)
      end
    end
    for _, s in ipairs(S.SNIPPETS) do
      A.truthy(s.code:find(s.select, 1, true), s.id .. ": zástupné slovo v kódu")
      A.truthy(in_rows[s.id], s.id .. ": v liště")
    end
  end },
  { "každá šablona po dosazení zástupných slov projde překladem i během", function()
    local P = require("prog_runner")
    local VALUES = { SIGNAL = "iron-plate", NUMBER = "5", VALUE = "1", CONDITION = "True", NAME = "x",
                     SET_CONDITION = "True", RESET_CONDITION = "False", TICKS = "10", SETPOINT = "100" }
    for _, s in ipairs(S.SNIPPETS) do
      local src
      if s.id == "loop" then
        src = (S.insert("", nil, s))
      elseif s.kind == "stmt" then
        src = (S.insert("def loop():", #"def loop():", s))
      else
        src = (S.insert("def loop():\n    x = ", nil, s))
      end
      src = src:gsub("[A-Z][A-Z_]+", VALUES)
      local res, err = P.run(src, 2)
      A.truthy(res, s.id .. ": " .. tostring(err and (err.key or err)) .. "\n" .. src)
    end
  end },
}
