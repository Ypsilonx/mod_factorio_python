-- Recept a výzkum až ve final-fixes: suroviny a prerekvizity se odvozují z obsahu hry včetně cizích modů.
local recipe = require("prototypes.recipe")
local research = require("prototypes.research")

local NAME = "pyntr-pythonator"

local ingredients = recipe.ingredients(data.raw)
local tech = research.build(data.raw, ingredients)

data:extend({
  {
    type = "recipe",
    name = NAME,
    enabled = tech == nil,
    energy_required = 5,
    ingredients = ingredients,
    results = { { type = "item", name = NAME, amount = 1 } },
  },
})

if tech then
  data:extend({
    {
      type = "technology",
      name = NAME,
      icon = "__Pythonator__/graphics/technology/pythonator.png",
      icon_size = 256,
      effects = { { type = "unlock-recipe", recipe = NAME } },
      prerequisites = tech.prerequisites,
      unit = tech.unit,
      research_trigger = tech.research_trigger,
    },
  })
end

--- Přidělí našemu prototypu metatabulku, kterou mají ostatní prototypy stejného typu.
--- Pyanodon 3.1 dává všem receptům metody (`recipe:has_category`) přes metatabulku jen při svém načtení a ve
--- svém data-final-fixes je volá i na recepty vytvořené po něm – bez metatabulky hra při načítání spadne.
--- @param prototype table náš prototyp v data.raw
local function inherit_metatable(prototype)
  if getmetatable(prototype) then return end
  for _, other in pairs(data.raw[prototype.type]) do
    local meta = getmetatable(other)
    if meta then
      setmetatable(prototype, meta)
      return
    end
  end
end

for _, prototypes in pairs(data.raw) do
  for name, prototype in pairs(prototypes) do
    if name:find("^pyntr%-") then inherit_metatable(prototype) end
  end
end

-- Kontrola při testech s cizími mody: co z receptu a výzkumu vzniklo.
local names = {}
for _, ing in ipairs(ingredients) do names[#names + 1] = ing.amount .. "× " .. ing.name end
log("Pythonator: suroviny = " .. table.concat(names, ", ")
  .. "; prerekvizity = " .. (tech and table.concat(tech.prerequisites, ", ") or "žádné (recept od začátku)"))
