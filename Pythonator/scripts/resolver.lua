--- Resolver signálů nad prototypy hry (včetně cizích modů). Staví se jednou, líně: prototypy jsou po načtení
--- konstantní, takže je výsledek na všech klientech stejný (deterministické).
local signals = require("scripts.lang.signals")

local M = {}

--- Typ SignalID → jméno slovníku v `prototypes` (LuaCustomTable jde indexovat jménem i procházet pairs).
local PROTO_TABLES = { item = "item", fluid = "fluid", virtual = "virtual_signal", recipe = "recipe",
                       entity = "entity", ["space-location"] = "space_location",
                       ["asteroid-chunk"] = "asteroid_chunk", quality = "quality" }

local instance

--- Sdílený resolver signálů.
--- @return table
function M.get()
  if not instance then
    local protos = {}
    for stype, field in pairs(PROTO_TABLES) do protos[stype] = prototypes[field] end
    instance = signals.new_resolver(protos)
  end
  return instance
end

return M
