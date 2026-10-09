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
                                       combinator_output_red = 3, combinator_output_green = 4 },
                 entity_status = { working = 1, no_power = 2, low_power = 3, not_plugged_in_electric_network = 4 } }
  for _, name in ipairs({ "scripts.resolver", "scripts.io", "scripts.controller", "scripts.scheduler" }) do package.loaded[name] = nil end
end

--- Falešná entita Pythonatoru se signály na vstupních drátech.
--- @param unit integer unit_number
--- @return table entita; `red`/`green` = { "jméno" = hodnota } (jen item/virtual s kvalitou normal)
function M.entity(unit)
  local e = { unit_number = unit, valid = true, red = {}, green = {}, status = 1, energy = 1000,
              prototype = { get_max_energy_usage = function() return 833 end } }
  --- Signály drátu podle id konektoru.
  local function wire(id) return id == 1 and e.red or id == 2 and e.green or {} end
  function e.get_signal(sid, a, b)
    return (wire(a)[sid.name] or 0) + (b and wire(b)[sid.name] or 0)
  end
  --- Id sítí konektorů (výchozí: síť podle entity a drátu, jen když na drátu něco je).
  e.net_ids, e.reads = {}, 0
  function e.get_circuit_network(id)
    local nid = e.net_ids[id] or (next(wire(id)) and e.unit_number * 10 + id)
    return nid and { network_id = nid } or nil
  end
  function e.get_signals(a, b)
    e.reads = e.reads + 1
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

--- Falešný skrytý konstantní kombinátor, který počítá volání API.
function M.output()
  local o = { valid = true, calls = 0, sections = {} }
  local cb = { sections_count = 0 }
  function cb.add_section()
    cb.sections_count = cb.sections_count + 1
    local section = { slots = {} }
    function section.set_slot(i, filter) o.calls = o.calls + 1; section.slots[i] = filter end
    function section.clear_slot(i) o.calls = o.calls + 1; section.slots[i] = nil end
    o.sections[cb.sections_count] = section
    return section
  end
  function cb.get_section(i) return o.sections[i] end
  function o.get_or_create_control_behavior() return cb end
  --- Výstup jako mapa jméno → hodnota (přes všechny sekce).
  function o.signals()
    local out = {}
    for _, section in ipairs(o.sections) do
      for _, f in pairs(section.slots) do
        local key = f.value.name .. (f.value.quality ~= "normal" and ("@" .. f.value.quality) or "")
        out[key] = f.min
      end
    end
    return out
  end
  return o
end

return M
