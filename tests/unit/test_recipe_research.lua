--- Jednotkové testy receptu a výzkumu Pythonatoru nad falešným data.raw (vanilla, chybějící předměty, overhaul).
local A = require("assert")
local recipe = require("prototypes.recipe")
local research = require("prototypes.research")
local tech_tree = require("prototypes.tech_tree")

--- Testovací data.raw ve tvaru vanilla 2.0 (zkrácený strom výzkumů).
--- @param drop table|nil množina předmětů, které „mod odstranil“
local function vanilla(drop)
  drop = drop or {}
  local raw = { item = {}, tool = {}, recipe = {}, technology = {} }
  --- Přidá výzkum.
  local function tech(name, prerequisites, packs, count)
    local ingredients = {}
    for i = 1, packs do ingredients[i] = { "pack-" .. i, 1 } end
    raw.technology[name] = { name = name, prerequisites = prerequisites, effects = {},
                             unit = { count = count, time = 30, ingredients = ingredients } }
  end
  --- Přidá předmět s receptem; tech = výzkum, který recept odemyká (nil = od začátku).
  local function item(name, tech_name, kind)
    if drop[name] then return end
    raw[kind or "item"][name] = { name = name }
    raw.recipe[name] = { name = name, enabled = tech_name == nil, results = { { type = "item", name = name, amount = 1 } } }
    if tech_name then
      local effects = raw.technology[tech_name].effects
      effects[#effects + 1] = { type = "unlock-recipe", recipe = name }
    end
  end
  tech("steel-processing", {}, 1, 50)
  tech("circuit-network", {}, 2, 100)
  tech("advanced-circuit", {}, 2, 200)
  tech("chemical-science-pack", { "advanced-circuit" }, 2, 75)
  item("iron-plate")
  item("electronic-circuit")
  item("steel-plate", "steel-processing")
  item("advanced-circuit", "advanced-circuit")
  item("arithmetic-combinator", "circuit-network")
  item("decider-combinator", "circuit-network")
  item("chemical-science-pack", "chemical-science-pack", "tool")
  return raw
end

--- Množství suroviny podle jména (nil = chybí).
local function amount(ingredients, name)
  for _, ingredient in ipairs(ingredients) do
    if ingredient.name == name then return ingredient.amount end
  end
end

return {
  { "recept: vanilla suroviny", function()
    local ing = recipe.ingredients(vanilla())
    A.eq(#ing, 4, "počet surovin")
    A.eq(amount(ing, "advanced-circuit"), 5, "advanced-circuit")
    A.eq(amount(ing, "decider-combinator"), 2, "decider")
    A.eq(amount(ing, "arithmetic-combinator"), 2, "arithmetic")
    A.eq(amount(ing, "steel-plate"), 5, "steel")
  end },
  { "recept: náhrada odstraněných předmětů", function()
    local ing = recipe.ingredients(vanilla({ ["advanced-circuit"] = true, ["steel-plate"] = true }))
    A.eq(amount(ing, "electronic-circuit"), 5, "náhrada obvodu")
    A.eq(amount(ing, "iron-plate"), 5, "náhrada oceli")
    A.eq(amount(ing, "advanced-circuit"), nil, "odstraněný předmět")
  end },
  { "recept: stejné předměty se sloučí, chybějící surovina se vynechá", function()
    local spec = { { { "iron-plate" }, 2 }, { { "steel-plate", "iron-plate" }, 3 }, { { "unobtainium" }, 1 } }
    local ing = recipe.ingredients(vanilla({ ["steel-plate"] = true }), spec)
    A.eq(#ing, 1, "jedna surovina")
    A.eq(amount(ing, "iron-plate"), 5, "sloučené množství")
  end },
  { "výzkum: prerekvizity bez tranzitivně zbytečných, modrá věda navíc", function()
    local raw = vanilla()
    local tech = research.build(raw, recipe.ingredients(raw))
    A.eq(table.concat(tech.prerequisites, ","), "chemical-science-pack,circuit-network,steel-processing", "prerekvizity")
    local packs = {}
    for _, ing in ipairs(tech.unit.ingredients) do packs[#packs + 1] = ing[1] end
    A.eq(table.concat(packs, ","), "pack-1,pack-2,chemical-science-pack", "druhy vědy")
    A.eq(tech.unit.count, 300, "1,5 × nejdražší prerekvizita")
  end },
  { "výzkum: bez modré vědy (mod ji odstranil) se obejde", function()
    local raw = vanilla({ ["chemical-science-pack"] = true })
    local tech = research.build(raw, recipe.ingredients(raw))
    A.eq(table.concat(tech.prerequisites, ","), "advanced-circuit,circuit-network,steel-processing", "prerekvizity")
    A.eq(#tech.unit.ingredients, 2, "jen věda z prerekvizit")
  end },
  { "výzkum: vše dostupné od začátku → žádný výzkum", function()
    local raw = { item = { a = {} }, tool = {}, recipe = { a = { enabled = true, results = { { name = "a" } } } }, technology = {} }
    A.eq(research.build(raw, { { type = "item", name = "a", amount = 1 } }), nil, "recept od začátku")
  end },
  { "výzkum: prerekvizity bez vědy (spouštěcí výzkumy) → odemčení vyrobením suroviny", function()
    local raw = vanilla({ ["chemical-science-pack"] = true })
    for _, t in pairs(raw.technology) do t.unit = nil; t.research_trigger = { type = "mine-entity", entity = "x" } end
    local tech = research.build(raw, recipe.ingredients(raw))
    A.eq(tech.unit, nil, "bez jednotky")
    A.eq(tech.research_trigger.type, "craft-item", "spouštěč")
    A.eq(tech.research_trigger.item, "advanced-circuit", "první surovina")
  end },
  { "zdroj předmětu: alternativní recept s menším stromem, skryté recepty se nepočítají", function()
    local raw = vanilla()
    raw.technology["late"] = { name = "late", prerequisites = { "advanced-circuit", "circuit-network" }, effects = {} }
    raw.recipe["steel-alt"] = { name = "steel-alt", enabled = false, results = { { name = "steel-plate" } } }
    table.insert(raw.technology["late"].effects, { type = "unlock-recipe", recipe = "steel-alt" })
    raw.recipe["steel-recycling"] = { name = "steel-recycling", hidden = true, enabled = true, results = { { name = "advanced-circuit" } } }
    local _, tech = tech_tree.item_source(raw, "steel-plate")
    A.eq(tech, "steel-processing", "menší uzávěr vyhrává")
    local _, tech2 = tech_tree.item_source(raw, "advanced-circuit")
    A.eq(tech2, "advanced-circuit", "skrytá recyklace se ignoruje")
  end },
}
