--- Obecné kontroly prototypů platné s jakýmikoli mody (běží i ve variantě `run-tests.sh mods …`):
--- entita a skrytý výstup existují, recept má výzkum (nebo je od začátku) a každá surovina jde vyrobit
--- nejpozději s tímto výzkumem.
local DATA = prototypes.mod_data["pyntr-data"].data

--- Množina výzkumu a všech jeho (i nepřímých) prerekvizit.
local function closure(tech)
  local seen, stack = { [tech.name] = true }, { tech }
  while #stack > 0 do
    for name, pre in pairs(table.remove(stack).prerequisites) do
      if not seen[name] then
        seen[name] = true
        stack[#stack + 1] = pre
      end
    end
  end
  return seen
end

--- Výzkum, který odemyká recept (nil = žádný).
local function unlocking(recipe_name)
  for name, tech in pairs(prototypes.technology) do
    if not tech.hidden and tech.enabled then
      for _, effect in ipairs(tech.effects) do
        if effect.type == "unlock-recipe" and effect.recipe == recipe_name then return name end
      end
    end
  end
end

--- Jde předmět vyrobit od začátku nebo s některým výzkumem z množiny `allowed`?
local function obtainable(item, allowed)
  for name, recipe in pairs(prototypes.recipe) do
    if not recipe.hidden then
      for _, product in ipairs(recipe.products) do
        if product.name == item then
          local tech = unlocking(name)
          if (tech == nil and recipe.enabled) or (tech and allowed[tech]) then return true end
        end
      end
    end
  end
  return false
end

return {
  {
    name = "compat: prototypy, recept a výzkum jsou dosažitelné",
    steps = { { ticks = 1, run = function()
      if not prototypes.entity[DATA.entity] then error("chybí entita " .. DATA.entity) end
      if not prototypes.entity[DATA.output] then error("chybí skrytý výstup " .. DATA.output) end
      local recipe = prototypes.recipe[DATA.entity]
      if not recipe then error("chybí recept") end
      local tech_name = unlocking(DATA.entity)
      if not tech_name and not recipe.enabled then error("recept nemá výzkum a není od začátku") end
      local allowed = tech_name and closure(prototypes.technology[tech_name]) or {}
      if tech_name then allowed[tech_name] = nil end
      for _, ing in ipairs(recipe.ingredients) do
        if not obtainable(ing.name, allowed) then error("surovina není dostupná včas: " .. ing.name) end
      end
    end } },
  },
}
