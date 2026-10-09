--- Vestavěné funkce a metody jazyka; rozšiřuje runtime R a vrací ho.
local R = require("scripts.lang.runtime")

local raise = R.raise
local B = {}
R.builtins = B

--- Ověří počet argumentů (min..max).
local function argc(name, n, min, max)
  if n < min or n > (max or min) then
    raise("arg-count", name, min == (max or min) and tostring(min) or (min .. "–" .. max), n)
  end
end

--- Celé číslo z hodnoty, jinak bad-int.
local function int_of(v)
  local x = R.numv(v)
  if not x or x ~= math.floor(x) then raise("bad-int", R.repr(v)) end
  return x
end

--- Pole hodnot z iterovatelného objektu.
local function collect(v)
  local arr, n = {}, 0
  for x in R.iter(v) do
    n = n + 1
    arr[n] = x
    R.charge(1)
  end
  return arr, n
end

--- Bankéřské zaokrouhlení (polovina k sudému) jako round() v Pythonu.
local function round_even(x)
  local f = math.floor(x)
  local d = x - f
  if d > 0.5 then return f + 1 end
  if d < 0.5 then return f end
  return (f % 2 == 0) and f or f + 1
end

--- Společná logika min/max (sign = -1 pro min, 1 pro max).
local function extreme(name, sign, ...)
  local n = select("#", ...)
  if n == 0 then raise("arg-count", name, "1+", 0) end
  local arr, count
  if n == 1 then arr, count = collect((...)) else arr, count = { ... }, n end
  if count == 0 then raise("empty-sequence", name) end
  local best = arr[1]
  for i = 2, count do
    if R.cmp(arr[i], best, name) * sign > 0 then best = arr[i] end
  end
  return best
end

function B.abs(...)
  argc("abs", select("#", ...), 1)
  local x = R.numv((...))
  if not x then raise("type-error-unary", "abs", R.typename((...))) end
  return math.abs(x)
end

function B.min(...) return extreme("min", -1, ...) end
function B.max(...) return extreme("max", 1, ...) end

function B.round(...)
  local n = select("#", ...)
  argc("round", n, 1, 2)
  local x, digits = ...
  x = R.numv(x) or raise("type-error-unary", "round", R.typename(x))
  if n == 1 then return round_even(x) end
  local m = 10 ^ int_of(digits)
  return round_even(x * m) / m
end

function B.int(...)
  argc("int", select("#", ...), 1)
  local v = ...
  if type(v) == "string" then
    local s = v:match("^[ \t\n\r]*([%+%-]?[0-9]+)[ \t\n\r]*$")
    if not s then raise("bad-int", R.repr(v)) end
    return tonumber(s)
  end
  local x = R.numv(v)
  if not x then raise("bad-int", R.repr(v)) end
  return x >= 0 and math.floor(x) or math.ceil(x)
end

function B.float(...)
  argc("float", select("#", ...), 1)
  local v = ...
  if type(v) == "string" then
    local x = tonumber(v:match("^[ \t\n\r]*(.-)[ \t\n\r]*$"))
    if not x then raise("bad-float", R.repr(v)) end
    return x
  end
  return R.numv(v) or raise("bad-float", R.repr(v))
end

function B.str(...) argc("str", select("#", ...), 1); return R.str((...)) end
function B.bool(...) argc("bool", select("#", ...), 1); return R.truthy((...)) end

function B.len(...)
  argc("len", select("#", ...), 1)
  local v = ...
  if type(v) == "string" then return #v end
  local mt = getmetatable(v)
  if mt == R.ListMT or mt == R.TupleMT then return v.n end
  if mt == R.DictMT then return #v.keys end
  if mt and mt.__len_py then return mt.__len_py(v) end
  raise("type-error-unary", "len", R.typename(v))
end

--- Parametry range() → první, poslední (včetně) a krok pro číselný for Lua.
--- @return number first, number last, number step
function R.range_bounds(a, b, c)
  local start, stop, step
  if b == nil then start, stop, step = 0, int_of(a), 1
  else start, stop, step = int_of(a), int_of(b), (c == nil) and 1 or int_of(c) end
  if step == 0 then raise("range-step-zero") end
  if step > 0 then return start, stop - 1, step end
  return start, stop + 1, step
end

function B.range(...)
  argc("range", select("#", ...), 1, 3)
  local first, last, step = R.range_bounds(...)
  R.charge(math.floor((last - first) / step) + 1)
  local arr, n = {}, 0
  for i = first, last, step do n = n + 1; arr[n] = i end
  return R.list(arr, n)
end

function B.sum(...)
  local n = select("#", ...)
  argc("sum", n, 1, 2)
  local it, start = ...
  local total = (n == 2) and start or 0
  for x in R.iter(it) do
    R.charge(1)
    total = R.add(total, x)
  end
  return total
end

function B.sorted(...)
  argc("sorted", select("#", ...), 1)
  local arr, n = collect((...))
  R.charge(n)
  table.sort(arr, function(x, y) return R.cmp(x, y, "sorted") < 0 end)
  return R.list(arr, n)
end

--- Text řádku print(): argumenty přes str() oddělené mezerou.
function R.print_line(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = R.str((select(i, ...))) end
  return table.concat(parts, " ")
end

--- Zásah watchdogu (limit do hlášky doplní VM).
function R.watchdog() raise("watchdog") end

-- Metody podle typu: METHODS[jméno typu][jméno metody] = function(self, n, ...)
local METHODS = { list = {}, dict = {}, str = {} }
R.METHODS = METHODS

local LM, DM, SM = METHODS.list, METHODS.dict, METHODS.str

function LM.append(l, n, x) argc("append", n, 1); l.n = l.n + 1; l[l.n] = x; return R.None end

function LM.pop(l, n, i)
  argc("pop", n, 0, 1)
  if l.n == 0 then raise("pop-empty", "list") end
  local idx = (n == 0) and l.n or nil
  if not idx then
    idx = int_of(i)
    if idx < 0 then idx = idx + l.n end
    if idx < 0 or idx >= l.n then raise("index-error") end
    idx = idx + 1
  end
  R.charge(l.n - idx + 1)
  local v = table.remove(l, idx)
  l.n = l.n - 1
  return v
end

function LM.insert(l, n, i, x)
  argc("insert", n, 2)
  local idx = int_of(i)
  if idx < 0 then idx = math.max(0, idx + l.n) end
  idx = math.min(idx, l.n)
  R.charge(l.n - idx + 1)
  table.insert(l, idx + 1, x)
  l.n = l.n + 1
  return R.None
end

function LM.index(l, n, x)
  argc("index", n, 1)
  R.charge(l.n)
  for i = 1, l.n do if R.eq(l[i], x) then return i - 1 end end
  raise("not-in-list")
end

function LM.remove(l, n, x)
  argc("remove", n, 1)
  local i = LM.index(l, 1, x)
  table.remove(l, i + 1)
  l.n = l.n - 1
  return R.None
end

function LM.clear(l, n)
  argc("clear", n, 0)
  for i = l.n, 1, -1 do l[i] = nil end
  l.n = 0
  return R.None
end

function DM.get(d, n, k, default)
  argc("get", n, 1, 2)
  local v = R.dict_get(d, k)
  if v ~= nil then return v end
  if n == 2 then return default end
  return R.None
end

--- Seznam z klíčů dict převedených funkcí f(klíč).
local function dict_list(d, f)
  R.charge(#d.keys)
  local arr = {}
  for i, k in ipairs(d.keys) do arr[i] = f(k) end
  return R.list(arr, #d.keys)
end

function DM.items(d, n)
  argc("items", n, 0)
  return dict_list(d, function(k) return R.tuple({ k, R.dict_get(d, k) }, 2) end)
end
function DM.keys(d, n) argc("keys", n, 0); return dict_list(d, function(k) return k end) end
function DM.values(d, n) argc("values", n, 0); return dict_list(d, function(k) return R.dict_get(d, k) end) end

function DM.pop(d, n, k, default)
  argc("pop", n, 1, 2)
  local v = R.dict_del(d, k)
  if v ~= nil then return v end
  if n == 2 then return default end
  raise("key-error", R.repr(k))
end

function DM.clear(d, n)
  argc("clear", n, 0)
  d.keys, d.vals = {}, {}
  return R.None
end

--- Ověří, že argument je řetězec.
local function strarg(name, v)
  if type(v) ~= "string" then raise("type-error", name, "str", R.typename(v)) end
  return v
end

--- Jen ASCII písmena: toupper/tolower z C závisí na locale (cs mění i bajty nad 127).
function SM.upper(s, n)
  argc("upper", n, 0)
  R.charge(#s)
  return (s:gsub("[a-z]", string.upper))
end
function SM.lower(s, n)
  argc("lower", n, 0)
  R.charge(#s)
  return (s:gsub("[A-Z]", string.lower))
end

function SM.startswith(s, n, p)
  argc("startswith", n, 1)
  p = strarg("startswith", p)
  return s:sub(1, #p) == p
end

function SM.endswith(s, n, p)
  argc("endswith", n, 1)
  p = strarg("endswith", p)
  return p == "" or s:sub(-#p) == p
end

function SM.split(s, n, sep)
  argc("split", n, 0, 1)
  local arr = {}
  if n == 0 or getmetatable(sep) == R.NoneMT then
    R.charge(#s)
    for w in s:gmatch("[^ \t\n\r\f\v]+") do arr[#arr + 1] = w end
  else
    sep = strarg("split", sep)
    R.charge(#s)
    if sep == "" then raise("empty-sequence", "split") end
    local start = 1
    while true do
      local i, j = s:find(sep, start, true)
      if not i then arr[#arr + 1] = s:sub(start); break end
      arr[#arr + 1] = s:sub(start, i - 1)
      start = j + 1
    end
  end
  return R.list(arr, #arr)
end

function SM.join(s, n, it)
  argc("join", n, 1)
  local parts = {}
  local total = 0
  for x in R.iter(it) do
    parts[#parts + 1] = strarg("join", x)
    total = total + #x + #s
  end
  R.charge(total)
  return table.concat(parts, s)
end

function SM.replace(s, n, old, new)
  argc("replace", n, 2)
  old, new = strarg("replace", old), strarg("replace", new)
  if old == "" then return s end
  R.charge(#s)
  local out, start = {}, 1
  while true do
    local i, j = s:find(old, start, true)
    if not i then out[#out + 1] = s:sub(start); break end
    out[#out + 1] = s:sub(start, i - 1)
    out[#out + 1] = new
    start = j + 1
  end
  return table.concat(out)
end

--- Volání metody obj.name(...) s kontrolou existence.
function R.method(obj, name, ...)
  local tn = R.typename(obj)
  local mt = getmetatable(obj)
  local m = (METHODS[tn] and METHODS[tn][name]) or (mt and mt.__methods and mt.__methods[name])
  if not m then raise("unknown-method", name, tn) end
  return m(obj, select("#", ...), ...)
end

return R
