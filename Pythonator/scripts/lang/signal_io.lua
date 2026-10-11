--- Objekty signálů pro program: čtení vstupů (inp/red/green) a zápis výstupů (out/out_red/out_green).
local R = require("scripts.lang.builtins")
local vector = require("scripts.lang.vector")

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
--- @param zeros table|nil klíče, kterým program výslovně zapsal 0 (klíč → true): na drát nejdou (síť nulu
--- nenese), jen do panelu výstupů. Tatáž tabulka zůstává jako u `store`.
function M.writer(store, resolver, zeros)
  return setmetatable({ store = store, resolver = resolver, ccache = {}, zeros = zeros or {} }, WriterMT)
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

--- Pohled (keys, vals) na sadu signálů pro knihovnu kombinátorů (viz scripts/lang/vector.lua).
--- Vstup: převod dvojic z `all()` se drží, dokud zdroj vrací tutéž tabulku (v hostiteli celý tick).
--- @return table keys, table vals
local function view(obj)
  if getmetatable(obj) == ReaderMT then
    local ps = obj.source.all()
    if obj.view_of ~= ps then
      local keys, vals = {}, {}
      for i = 1, #ps do
        local p = ps[i]
        keys[i], vals[p[1]] = p[1], p[2]
      end
      obj.view_of, obj.view_keys, obj.view_vals = ps, keys, vals
    end
    return obj.view_keys, obj.view_vals
  end
  local keys = {}
  for k in pairs(obj.store) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return R.strcmp(a, b) < 0 end)
  return keys, obj.store
end

for name, f in pairs(vector.methods(view)) do common[name] = f end

--- Pohled na sadu pro out.set/add: dict nebo objekt signálů, jinak TypeError.
local function source_view(name, d)
  local mt = getmetatable(d)
  if mt == R.DictMT then return vector.dict_view(d) end
  if mt == ReaderMT or mt == WriterMT then return view(d) end
  R.raise("type-error", name, "dict", R.typename(d))
end

--- Hodnota pro drát: ořez k nule, přetečení do int32; 0 → nil (signál se nevysílá).
local function signal_value(value)
  local x = R.numv(value)
  if not x then R.raise("type-error", "=", "signal", R.typename(value)) end
  -- NaN a nekonečno nemají celočíselnou hodnotu (Python: OverflowError), na drát nesmí
  if x ~= x or x == math.huge or x == -math.huge then R.raise("overflow", R.str(x)) end
  x = x >= 0 and math.floor(x) or math.ceil(x)
  if x > 2147483647 or x < -2147483648 then x = R.wrap32(x) end
  if x == 0 then return nil end
  return x
end

--- Zapíše kanonický klíč; `changed` čte hostitel: výstupy jdou na drát jen po skutečné změně
--- (program často každý tick zapíše tytéž hodnoty). Zápis nuly (x = nil) si klíč poznamená v `zeros`.
local function store_set(obj, c, x)
  if obj.store[c] ~= x then
    obj.store[c] = x
    obj.changed = true
  end
  local zero = x == nil or nil
  if obj.zeros[c] ~= zero then
    obj.zeros[c] = zero
    obj.changed = true
  end
end

local writer_methods = {
  clear = function(obj)
    if next(obj.store) or next(obj.zeros) then obj.changed = true end
    for k in pairs(obj.store) do obj.store[k] = nil end
    for k in pairs(obj.zeros) do obj.zeros[k] = nil end
    return R.None
  end,
  --- out.set(d): výstupy nahradí sadou d. Nová sada se sestaví celá předem (d může být out sám) a do
  --- úložiště jde jen rozdíl – stejné hodnoty každý tick neoznačí výstup jako změněný.
  set = function(obj, n, d)
    if n ~= 1 then R.raise("arg-count", "set", 1, n) end
    local keys, vals = source_view("set", d)
    R.charge(#keys)
    local want, want_zero = {}, {}
    for i = 1, #keys do
      local k = keys[i]
      local c, x = canon(obj, k), signal_value(vals[k])
      want[c] = x
      if x == nil then want_zero[c] = true end
    end
    local store, zeros = obj.store, obj.zeros
    for c in pairs(store) do
      if want[c] == nil then store[c] = nil; obj.changed = true end
    end
    for c in pairs(zeros) do
      if not want_zero[c] then zeros[c] = nil; obj.changed = true end
    end
    for c, x in pairs(want) do store_set(obj, c, x) end
    for c in pairs(want_zero) do store_set(obj, c, nil) end
    return R.None
  end,
  --- out.add(d): k výstupům přičte sadu d.
  add = function(obj, n, d)
    if n ~= 1 then R.raise("arg-count", "add", 1, n) end
    local keys, vals = source_view("add", d)
    R.charge(#keys)
    for i = 1, #keys do
      local k = keys[i]
      local x = R.numv(vals[k])
      if not x then R.raise("type-error", "add", "int", R.typename(vals[k])) end
      local c = canon(obj, k)
      store_set(obj, c, signal_value((obj.store[c] or 0) + x))
    end
    return R.None
  end,
}
for name, f in pairs(common) do writer_methods[name] = writer_methods[name] or f end

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
  store_set(obj, canon(obj, key), signal_value(value))
end

return M
