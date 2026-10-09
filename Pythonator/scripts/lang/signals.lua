--- Klíče signálů: textový zápis ↔ SignalID {type, name, quality}, ověření proti prototypům.
local errors = require("scripts.lang.errors")

local M = {}

--- Typy hledané podle jména bez prefixu (v tomto pořadí).
M.PLAIN_TYPES = { "item", "fluid", "virtual" }

--- Všechny typy SignalID ve Factoriu 2.0.
M.ALL_TYPES = { "item", "fluid", "virtual", "recipe", "entity", "space-location", "asteroid-chunk", "quality" }

--- Typ v rich text tagu → typ SignalID.
M.TAG_TYPES = {
  item = "item", fluid = "fluid", ["virtual-signal"] = "virtual", recipe = "recipe", entity = "entity",
  ["space-location"] = "space-location", ["asteroid-chunk"] = "asteroid-chunk", quality = "quality",
}

local IS_TYPE, IS_PLAIN = {}, {}
for _, t in ipairs(M.ALL_TYPES) do IS_TYPE[t] = true end
for _, t in ipairs(M.PLAIN_TYPES) do IS_PLAIN[t] = true end

--- Rozloží textový klíč na části (bez ověření existence).
--- @param key string např. "recipe:iron-plate@rare"
--- @return string|nil stype explicitní typ, nebo nil
--- @return string name
--- @return string quality ("normal", pokud chybí)
function M.split(key)
  local stype, rest = key:match("^([A-Za-z0-9%-]+):(.+)$")
  if not (stype and IS_TYPE[stype]) then stype, rest = nil, key end
  local name, quality = rest:match("^(.+)@([A-Za-z0-9%-_]+)$")
  if not name then name, quality = rest, "normal" end
  return stype, name, quality
end

--- Textový klíč z rich text tagu ([item=x,quality=q]); typ je vždy explicitní.
--- @param tag_type string typ v tagu, např. "virtual-signal"
--- @param name string
--- @param quality string
--- @return string
function M.from_tag(tag_type, name, quality)
  local key = M.TAG_TYPES[tag_type] .. ":" .. name
  if quality ~= "normal" then key = key .. "@" .. quality end
  return key
end

--- Levenshteinova vzdálenost dvou řetězců.
local function distance(a, b)
  local prev = {}
  for j = 0, #b do prev[j] = j end
  for i = 1, #a do
    local cur, ca = { [0] = i }, a:byte(i)
    for j = 1, #b do
      local cost = (ca == b:byte(j)) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[#b]
end

--- Je a před b po bajtech? (Lua `<` na řetězcích používá strcoll, který závisí na locale.)
local function byte_less(a, b)
  for i = 1, math.min(#a, #b) do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then return x < y end
  end
  return #a < #b
end

--- Nejbližší jméno z množin kandidátů, pokud je dost blízko (deterministicky při shodě).
--- @return string|nil
local function suggest(name, sets)
  local best, bestd
  for _, set in ipairs(sets) do
    for cand in pairs(set) do
      local d = distance(name, cand)
      if not bestd or d < bestd or (d == bestd and byte_less(cand, best)) then best, bestd = cand, d end
    end
  end
  if best and bestd <= math.max(2, math.floor(#name / 3)) then return best end
end

local Resolver = {}
Resolver.__index = Resolver

--- Vytvoří resolver nad množinami jmen prototypů.
--- @param protos table typ SignalID → množina jmen (chybějící typy = prázdné)
--- @return table
function M.new_resolver(protos)
  local p = {}
  for _, t in ipairs(M.ALL_TYPES) do p[t] = protos[t] or {} end
  return setmetatable({ protos = p, cache = {}, canon = {} }, Resolver)
end

--- Typy bez prefixu, ve kterých jméno existuje.
--- @return string[]
function Resolver:plain_types(name)
  local found = {}
  for _, t in ipairs(M.PLAIN_TYPES) do
    if self.protos[t][name] then found[#found + 1] = t end
  end
  return found
end

--- Kanonický textový klíč: prefix jen u typů mimo item/fluid/virtual nebo při nejednoznačnosti.
--- @param sid table {type, name, quality} – chybějící typ = item, chybějící kvalita = normal (jako SignalID hry)
--- @return string
function Resolver:canonical(sid)
  local stype, name, quality = sid.type or "item", sid.name, sid.quality or "normal"
  -- Cache typ → kvalita → jméno: čtení vstupů převádí každý signál každý tick, prototypy se nemění.
  local by_quality = self.canon[stype]
  if not by_quality then
    by_quality = {}
    self.canon[stype] = by_quality
  end
  local by_name = by_quality[quality]
  if not by_name then
    by_name = {}
    by_quality[quality] = by_name
  end
  local key = by_name[name]
  if key then return key end
  key = name
  if not IS_PLAIN[stype] or #self:plain_types(name) > 1 then key = stype .. ":" .. key end
  if quality ~= "normal" then key = key .. "@" .. quality end
  by_name[name] = key
  return key
end

--- Chyba neznámého signálu (s návrhem, je-li nějaký blízký).
local function unknown(key, prefix, name, sets)
  local s = suggest(name, sets)
  if s then return errors.make(nil, nil, "unknown-signal", key, prefix .. s) end
  return errors.make(nil, nil, "unknown-signal-nosuggest", key)
end

--- Ověří textový klíč a vrátí SignalID a kanonický tvar. Výsledek se cachuje (tabulku sid neměnit).
--- @param key string
--- @return table|nil sid
--- @return string|nil canonical
--- @return table|nil err
function Resolver:resolve(key)
  local hit = self.cache[key]
  if hit then return hit.sid, hit.canonical end
  local stype, name, quality = M.split(key)
  if not self.protos.quality[quality] then
    return nil, nil, errors.make(nil, nil, "unknown-quality", quality)
  end
  if stype then
    if not self.protos[stype][name] then
      return nil, nil, unknown(key, stype .. ":", name, { self.protos[stype] })
    end
  else
    local found = self:plain_types(name)
    if #found > 1 then
      return nil, nil, errors.make(nil, nil, "ambiguous-signal", name, table.concat(found, ", "))
    end
    if #found == 0 then
      return nil, nil, unknown(key, "", name, { self.protos.item, self.protos.fluid, self.protos.virtual })
    end
    stype = found[1]
  end
  local sid = { type = stype, name = name, quality = quality }
  local canonical = self:canonical(sid)
  self.cache[key] = { sid = sid, canonical = canonical }
  return sid, canonical
end

return M
