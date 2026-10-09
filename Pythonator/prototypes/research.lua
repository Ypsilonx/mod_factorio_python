--- Čistá logika výzkumu Pythonatoru: prerekvizity dopočtené z toho, co recept potřebuje, takže výzkum sedí
--- i na stromy přeskládané overhaul mody. Testy v tests/unit/.
local tech_tree = require("prototypes.tech_tree")

local M = {}

--- Výzkumy, které jsou prerekvizitou vždy (pokud existují). Laditelné hodnoty.
M.EXTRA_TECHS = { "circuit-network" }
--- Balíčky vědy navíc: výzkum, který balíček odemyká, je prerekvizitou a balíček se přidá do ceny.
--- Úroveň „za kombinátory“ (spec: červená + zelená + modrá). Laditelné hodnoty.
M.EXTRA_PACKS = { "chemical-science-pack" }
--- Násobič počtu jednotek proti nejdražší přímé prerekvizitě. Laditelná hodnota.
M.COUNT_MULTIPLIER = 1.5

--- Hloubková kopie tabulky (data stage má table.deepcopy, unit testy ne).
local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for key, value in pairs(t) do out[key] = copy(value) end
  return out
end

--- Jednotka výzkumu s nejvíc druhy vědy (při shodě vyšší počet) – druhy vědy z jednoho existujícího výzkumu
--- zaručí, že je laboratoř umí zpracovat i v modech s více laboratořemi.
local function template_unit(raw, techs)
  local best
  for _, name in ipairs(techs) do
    local unit = raw.technology[name].unit
    if unit and unit.count then
      if not best or #unit.ingredients > #best.ingredients
        or (#unit.ingredients == #best.ingredients and unit.count > best.count) then
        best = unit
      end
    end
  end
  return best
end

--- Obsahuje seznam surovin výzkumu daný balíček? (formát { "jméno", n } i { name = …, amount = … })
local function has_pack(ingredients, pack)
  for _, ing in ipairs(ingredients) do
    if (ing[1] or ing.name) == pack then return true end
  end
  return false
end

--- Spočítá výzkum Pythonatoru.
--- @param raw table data.raw
--- @param ingredients table[] suroviny receptu
--- @return table|nil { prerequisites, unit | research_trigger }; nil = recept je dostupný od začátku
function M.build(raw, ingredients)
  local direct, packs = {}, {}
  for _, name in ipairs(M.EXTRA_TECHS) do
    if raw.technology[name] then direct[name] = true end
  end
  for _, ingredient in ipairs(ingredients) do
    local _, tech = tech_tree.item_source(raw, ingredient.name)
    if tech then direct[tech] = true end
  end
  for _, pack in ipairs(M.EXTRA_PACKS) do
    local _, tech = tech_tree.item_source(raw, pack)
    if tech then
      direct[tech] = true
      packs[#packs + 1] = pack
    end
  end
  local names = tech_tree.sorted_keys(direct)
  if #names == 0 then return nil end

  local implied = {}
  for _, name in ipairs(names) do
    for prerequisite in pairs(tech_tree.tech_closure(raw, name)) do implied[prerequisite] = true end
  end
  local result = { prerequisites = {} }
  for _, name in ipairs(names) do
    if not implied[name] then result.prerequisites[#result.prerequisites + 1] = name end
  end

  local base = template_unit(raw, names)
  if not base then
    -- Prerekvizity bez vědy (spouštěcí výzkumy Space Age, mody): odemkne se vyrobením první suroviny.
    result.research_trigger = { type = "craft-item", item = ingredients[1].name }
    return result
  end
  result.unit = copy(base)
  local max_count = 0
  for _, name in ipairs(names) do
    local unit = raw.technology[name].unit
    if unit and unit.count and unit.count > max_count then max_count = unit.count end
  end
  result.unit.count = math.ceil(max_count * M.COUNT_MULTIPLIER)
  for _, pack in ipairs(packs) do
    if not has_pack(result.unit.ingredients, pack) then
      result.unit.ingredients[#result.unit.ingredients + 1] = { pack, 1 }
    end
  end
  return result
end

return M
