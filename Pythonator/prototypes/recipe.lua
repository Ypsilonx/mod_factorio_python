--- Čistá logika receptu Pythonatoru: suroviny s náhradami pro mody, které předměty odstraní nebo přejmenují.
--- Meziprodukty (ne rudy a pláty) zajistí, že overhaul mod recept zdraží sám. Testy v tests/unit/.
local M = {}

--- Suroviny: { kandidáti, počet } – použije se první kandidát existující v data.raw.item. Laditelné hodnoty.
M.INGREDIENTS = {
  { { "advanced-circuit", "electronic-circuit" }, 5 },
  { { "decider-combinator" }, 2 },
  { { "arithmetic-combinator" }, 2 },
  { { "steel-plate", "iron-plate" }, 5 },
}

--- Sestaví suroviny receptu; stejné předměty sloučí (Factorio duplicitní suroviny odmítne).
--- @param raw table data.raw
--- @param spec table|nil seznam surovin (výchozí M.INGREDIENTS)
--- @return table[] suroviny ve formátu receptu Factoria
function M.ingredients(raw, spec)
  local list, index = {}, {}
  for _, entry in ipairs(spec or M.INGREDIENTS) do
    for _, candidate in ipairs(entry[1]) do
      if raw.item[candidate] then
        if index[candidate] then
          index[candidate].amount = index[candidate].amount + entry[2]
        else
          index[candidate] = { type = "item", name = candidate, amount = entry[2] }
          list[#list + 1] = index[candidate]
        end
        break
      end
    end
  end
  return list
end

return M
