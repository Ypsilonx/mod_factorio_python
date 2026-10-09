--- Čistá logika nad stromem výzkumů a recepty (převzato ze Storage Optimizeru): jak hráč k předmětu přijde
--- a jaké jsou (i nepřímé) prerekvizity výzkumu. Nepoužívá globály Factoria – testy v tests/unit/.
local M = {}

--- Klíče tabulky seřazené abecedně (deterministické pořadí i mimo Factorio).
--- @return string[]
function M.sorted_keys(t)
  local keys = {}
  for key in pairs(t or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

--- Neskryté recepty, jejichž výsledkem je daný předmět. Skryté recepty (recyklace Space Age „vyrábí“
--- suroviny a je enabled) hráč běžně nevyrábí, proto se nepočítají.
local function recipes_for(raw, item_name)
  local list = {}
  for _, name in ipairs(M.sorted_keys(raw.recipe)) do
    local recipe = raw.recipe[name]
    if not recipe.hidden then
      for _, result in ipairs(recipe.results or {}) do
        if result.name == item_name then
          list[#list + 1] = name
          break
        end
      end
    end
  end
  return list
end

--- Množina všech (i nepřímých) prerekvizit výzkumu.
--- @return table<string, true>
function M.tech_closure(raw, tech)
  local seen, stack = {}, { tech }
  while #stack > 0 do
    local proto = raw.technology[table.remove(stack)]
    for _, prerequisite in ipairs(proto and proto.prerequisites or {}) do
      if not seen[prerequisite] then
        seen[prerequisite] = true
        stack[#stack + 1] = prerequisite
      end
    end
  end
  return seen
end

--- Počet prvků množiny.
local function count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

--- Výzkum, který odemyká recept (skryté a vypnuté výzkumy hráč nevyzkoumá, nepočítají se).
--- @return string|nil
local function unlocking_tech(raw, recipe_name)
  for _, name in ipairs(M.sorted_keys(raw.technology)) do
    local tech = raw.technology[name]
    if not tech.hidden and tech.enabled ~= false then
      for _, effect in ipairs(tech.effects or {}) do
        if effect.type == "unlock-recipe" and effect.recipe == recipe_name then return name end
      end
    end
  end
end

--- Jak hráč k předmětu přijde: z více receptů (overhaul mody mají alternativní) ten dostupný nejdřív –
--- od začátku, jinak přes výzkum s nejmenším uzávěrem prerekvizit.
--- @return string|nil recipe nil = předmět nemá vyrobitelný recept (ruda, kapalina…)
--- @return string|nil tech nil = recept je dostupný od začátku
function M.item_source(raw, item_name)
  local best_recipe, best_tech, best_size
  for _, recipe in ipairs(recipes_for(raw, item_name)) do
    local tech = unlocking_tech(raw, recipe)
    if not tech and raw.recipe[recipe].enabled ~= false then return recipe, nil end
    if tech then
      local size = count(M.tech_closure(raw, tech))
      if not best_size or size < best_size then
        best_recipe, best_tech, best_size = recipe, tech, size
      end
    end
  end
  return best_recipe, best_tech
end

return M
