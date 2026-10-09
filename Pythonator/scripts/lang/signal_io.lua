--- Objekty signálů pro program: čtení vstupů (inp/red/green) a zápis výstupů (out/out_red/out_green).
local R = require("scripts.lang.builtins")

local M = {}

local ReaderMT = { __pyntr = "signals" }
local WriterMT = { __pyntr = "signals" }
M.ReaderMT, M.WriterMT = ReaderMT, WriterMT

--- Kanonický klíč z hodnoty klíče, jinak chyba resolveru.
local function canon(obj, key)
  -- Klíče se v programu opakují každý tick: převedený tvar si objekt pamatuje (jen řetězce).
  local c = obj.ccache[key]
  if c then return c end
  if type(key) ~= "string" then R.raise("bad-signal-key", R.typename(key)) end
  local _, canonical, err = obj.resolver:resolve(key)
  if not canonical then error(err, 0) end
  obj.ccache[key] = canonical
  return canonical
end

--- Vytvoří čtecí objekt.
--- @param source table {get = function(canonical) → number, all = function() → { {klíč, hodnota}… }}
--- @param resolver table z signals.new_resolver
function M.reader(source, resolver)
  return setmetatable({ source = source, resolver = resolver, ccache = {} }, ReaderMT)
end

--- Vytvoří zapisovací objekt nad úložištěm kanonický klíč → int32.
--- @param store table úložiště (tatáž tabulka zůstává, clear ji jen vyprázdní)
--- @param resolver table z signals.new_resolver
function M.writer(store, resolver)
  return setmetatable({ store = store, resolver = resolver, ccache = {} }, WriterMT)
end

--- Dvojice (klíč, hodnota) všech nenulových signálů objektu.
local function pairs_of(obj)
  if getmetatable(obj) == ReaderMT then return obj.source.all() end
  local keys = {}
  for k in pairs(obj.store) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return R.strcmp(a, b) < 0 end)
  local out = {}
  for i, k in ipairs(keys) do out[i] = { k, obj.store[k] } end
  return out
end

--- Hodnota signálu (0, pokud chybí).
local function get(obj, key)
  local c = canon(obj, key)
  if getmetatable(obj) == ReaderMT then return obj.source.get(c) end
  return obj.store[c] or 0
end

--- Seznam z dvojic převedených funkcí f.
local function list_of(obj, f)
  local arr = {}
  for i, p in ipairs(pairs_of(obj)) do arr[i] = f(p) end
  return R.list(arr, #arr)
end

local common = {
  get = function(obj, n, key, default)
    if n < 1 or n > 2 then R.raise("arg-count", "get", "1–2", n) end
    local v = get(obj, key)
    if v == 0 and n == 2 then return default end
    return v
  end,
  items = function(obj) return list_of(obj, function(p) return R.tuple({ p[1], p[2] }, 2) end) end,
  keys = function(obj) return list_of(obj, function(p) return p[1] end) end,
  values = function(obj) return list_of(obj, function(p) return p[2] end) end,
}

local writer_methods = {
  get = common.get, items = common.items, keys = common.keys, values = common.values,
  clear = function(obj)
    if next(obj.store) then obj.changed = true end
    for k in pairs(obj.store) do obj.store[k] = nil end
    return R.None
  end,
}

for _, mt in ipairs({ ReaderMT, WriterMT }) do
  mt.__getitem = get
  mt.__contains = function(obj, key) return get(obj, key) ~= 0 end
  mt.__len_py = function(obj) return #pairs_of(obj) end
  mt.__repr_py = function(obj) return R.repr(common.items(obj)) end
  mt.__iter = function(obj)
    local ps, i = pairs_of(obj), 0
    return function() i = i + 1; return ps[i] and ps[i][1] end
  end
end
ReaderMT.__methods = common
-- Rychlý průchod `for k, v in inp.items()` (R.items_array) bez stavby seznamu n-tic.
ReaderMT.__pairs_py = pairs_of
WriterMT.__pairs_py = pairs_of
WriterMT.__methods = writer_methods

ReaderMT.__setitem = function() R.raise("readonly-signal", "inp") end

WriterMT.__setitem = function(obj, key, value)
  local c = canon(obj, key)
  local x = R.numv(value)
  if not x then R.raise("type-error", "=", "signal", R.typename(value)) end
  -- NaN a nekonečno nemají celočíselnou hodnotu (Python: OverflowError), na drát nesmí
  if x ~= x or x == math.huge or x == -math.huge then R.raise("overflow", R.str(x)) end
  x = x >= 0 and math.floor(x) or math.ceil(x)
  if x > 2147483647 or x < -2147483648 then x = R.wrap32(x) end
  if x == 0 then x = nil end
  -- `changed` čte hostitel: výstupy zapisuje na drát jen po skutečné změně (program často každý tick
  -- zapíše tytéž hodnoty).
  if obj.store[c] ~= x then
    obj.store[c] = x
    obj.changed = true
  end
end

return M
