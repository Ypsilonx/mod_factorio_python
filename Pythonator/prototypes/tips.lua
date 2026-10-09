--- Tipy a triky: kategorie Pythonator dostupná od začátku hry (bez budovy), aby šla reference číst kdykoli.
--- Texty jsou stejné klíče locale jako nápověda v okně budovy (scripts/gui/help.lua) – jeden zdroj, dvě místa.
--- Kód příkladů se přebírá z help.EXAMPLES (soubor bez herního API, jde načíst i v data stage).
local help = require("scripts.gui.help")

local TAG = "[entity=pyntr-pythonator]"

--- Záznam tipu pod titulkem Pythonatoru.
local function item(name, order, title, description)
  return {
    type = "tips-and-tricks-item",
    name = name,
    category = "pyntr",
    order = order,
    indent = 1,
    starting_status = "unlocked",
    localised_name = title,
    localised_description = description,
  }
end

--- Popis tipu Příklady: úvod a pro každý příklad nadpis, popis a kód (každý příklad jako vnořený řetězec –
--- hra dovoluje nejvýš 20 parametrů na úroveň).
local function examples_description()
  local desc = { "", { "pyntr-gui.tips-examples-text" } }
  for _, ex in ipairs(help.EXAMPLES) do
    desc[#desc + 1] = { "", "\n\n[font=default-bold]", { "pyntr-gui.help-example-" .. ex.id .. "-title" }, "[/font]\n",
      { "pyntr-gui.help-example-" .. ex.id .. "-desc" }, "\n[font=pyntr-mono]", ex.code, "[/font]" }
  end
  return desc
end

local prototypes = {
  { type = "tips-and-tricks-item-category", name = "pyntr", order = "z-[pythonator]" },
  {
    type = "tips-and-tricks-item",
    name = "pyntr-pythonator",
    category = "pyntr",
    order = "a",
    is_title = true,
    tag = TAG,
    starting_status = "unlocked",
    localised_name = { "pyntr-gui.tips-title" },
    localised_description = { "pyntr-gui.help-basics-text" },
  },
}
for i, id in ipairs(help.SECTIONS) do
  if id ~= "basics" then
    prototypes[#prototypes + 1] = item("pyntr-" .. id, "b" .. i, { "pyntr-gui.help-" .. id .. "-title" },
      { "pyntr-gui.help-" .. id .. "-text" })
  end
end
prototypes[#prototypes + 1] = item("pyntr-examples", "c", { "pyntr-gui.help-examples-title" }, examples_description())

data:extend(prototypes)
