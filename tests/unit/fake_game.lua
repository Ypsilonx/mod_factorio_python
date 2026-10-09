--- Napodobenina herního prostředí pro testy hostitele (storage, settings, prototypes, defines, entita).
---@diagnostic disable: inject-field, missing-fields
local fake_protos = require("fake_protos")

local M = {}

--- Mapování typu SignalID → jméno slovníku v `prototypes`.
local PROTO_TABLES = { item = "item", fluid = "fluid", virtual = "virtual_signal", recipe = "recipe",
                       entity = "entity", ["space-location"] = "space_location",
                       ["asteroid-chunk"] = "asteroid_chunk", quality = "quality" }

--- Nastaví globály storage/settings/prototypes/defines na čerstvé hodnoty a znovu načte moduly hostitele
--- (zahození cache instancí = simulace načtení hry, pokud `keep_storage`).
--- @param keep_storage boolean|nil ponechat storage (simulace uložení a načtení)
function M.reset(keep_storage)
  if not keep_storage then _G.storage = {} end
  _G.settings = { global = { ["pyntr-watchdog-limit"] = { value = 10000 }, ["pyntr-memory-limit"] = { value = 10000 } } }
  local protos = {}
  for stype, set in pairs(fake_protos()) do protos[PROTO_TABLES[stype]] = set end
  _G.prototypes = protos
  _G.defines = { wire_connector_id = { combinator_input_red = 1, combinator_input_green = 2,
                                       combinator_output_red = 3, combinator_output_green = 4 } }
  for _, name in ipairs({ "scripts.resolver", "scripts.io", "scripts.controller" }) do package.loaded[name] = nil end
end

--- Falešná entita Pythonatoru se signály na vstupních drátech.
--- @param unit integer unit_number
--- @return table entita; `red`/`green` = { "jméno" = hodnota } (jen item/virtual s kvalitou normal)
function M.entity(unit)
  local e = { unit_number = unit, valid = true, red = {}, green = {} }
  --- Signály drátu podle id konektoru.
  local function wire(id) return id == 1 and e.red or id == 2 and e.green or {} end
  function e.get_signal(sid, a, b)
    return (wire(a)[sid.name] or 0) + (b and wire(b)[sid.name] or 0)
  end
  function e.get_signals(a, b)
    local sum = {}
    for _, id in ipairs({ a, b }) do
      for name, v in pairs(wire(id)) do sum[name] = (sum[name] or 0) + v end
    end
    local list = {}
    for name, v in pairs(sum) do
      list[#list + 1] = { signal = { type = name:find("^signal%-") and "virtual" or nil, name = name }, count = v }
    end
    if #list == 0 then return nil end
    return list
  end
  return e
end

return M
