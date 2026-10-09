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
      icons = data.raw.item[NAME].icons,
      effects = { { type = "unlock-recipe", recipe = NAME } },
      prerequisites = tech.prerequisites,
      unit = tech.unit,
      research_trigger = tech.research_trigger,
    },
  })
end

-- Kontrola při testech s cizími mody: co z receptu a výzkumu vzniklo.
local names = {}
for _, ing in ipairs(ingredients) do names[#names + 1] = ing.amount .. "× " .. ing.name end
log("Pythonator: suroviny = " .. table.concat(names, ", ")
  .. "; prerekvizity = " .. (tech and table.concat(tech.prerequisites, ", ") or "žádné (recept od začátku)"))
