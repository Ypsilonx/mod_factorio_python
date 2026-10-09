--- Runtime Pythonatoru: hodnoty a operace s Python sémantikou pro vygenerovaný kód.
--- int/float = Lua number, bool = Lua boolean, str = Lua string, None/list/tuple/dict = tabulky s metatabulkou.
--- Typ se rozpoznává vždy přes getmetatable – po načtení savu jsou to nové tabulky (identita se ztrácí).
local errors = require("scripts.lang.errors")

local R = {}

local NoneMT = { __pyntr = "None" }
local ListMT = { __pyntr = "list" }
local TupleMT = { __pyntr = "tuple" }
local DictMT = { __pyntr = "dict" }
R.NoneMT, R.ListMT, R.TupleMT, R.DictMT = NoneMT, ListMT, TupleMT, DictMT

R.None = setmetatable({}, NoneMT)

--- Lua `type` pro vygenerovaný kód (běží v prázdném prostředí bez globálů).
R.lua_type = type

--- Vyhodí chybu jazyka bez pozice (řádek doplní VM).
local function raise(key, ...) errors.raise(nil, nil, key, ...) end
R.raise = raise

--- Instance programu, která právě běží (nastavuje VM jen po dobu init/loop); platí za práci vestavěných funkcí.
R.active = nil

--- Započte n jednotek práce do rozpočtu watchdogu běžící instance (volat PŘED alokací výsledku).
--- @param n number
function R.charge(n)
  local inst = R.active
  if inst and n > 0 then inst.charge(n) end
end
local charge = R.charge

--- Porovnání řetězců po bajtech (-1/0/1), nezávislé na locale (Lua `<` používá strcoll).
local function strcmp(a, b)
  if a == b then return 0 end
  for i = 1, math.min(#a, #b) do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then return x < y and -1 or 1 end
  end
  return #a < #b and -1 or 1
end
R.strcmp = strcmp

--- Jméno typu v Python stylu (pro hlášky); nil = proměnná před přiřazením.
--- @return string
function R.typename(v)
  local t = type(v)
  if t == "number" then return v == math.floor(v) and "int" or "float" end
  if t == "string" then return "str" end
  if t == "boolean" then return "bool" end
  if t == "nil" then raise("unbound") end
  local mt = getmetatable(v)
  return mt and mt.__pyntr or "object"
end

--- Nový list z pole (pole se převezme).
function R.list(arr, n) arr.n = n; return setmetatable(arr, ListMT) end

--- Nová n-tice z pole (pole se převezme).
function R.tuple(arr, n) arr.n = n; return setmetatable(arr, TupleMT) end

--- Klíč Lua tabulky pro klíč slovníku (str/číslo/bool).
local function dkey(k)
  local t = type(k)
  if t == "string" or t == "boolean" then return k end
  if t == "number" and k == k then return k end
  raise("bad-dict-key", R.typename(k))
end

--- Hodnota pod klíčem, nebo nil, pokud klíč chybí.
function R.dict_get(d, k) return d.vals[dkey(k)] end

--- Nastaví klíč; nový klíč se přidá na konec pořadí.
function R.dict_set(d, k, v)
  local kk = dkey(k)
  if d.vals[kk] == nil then d.keys[#d.keys + 1] = k end
  d.vals[kk] = v
end

--- Smaže klíč a vrátí jeho hodnotu (nil, pokud chyběl).
function R.dict_del(d, k)
  local kk = dkey(k)
  local v = d.vals[kk]
  if v == nil then return nil end
  charge(#d.keys)
  d.vals[kk] = nil
  for i, key in ipairs(d.keys) do
    if dkey(key) == kk then table.remove(d.keys, i); break end
  end
  return v
end

--- Nový dict z prokládaného pole {k1, v1, k2, v2, …} o n prvcích.
function R.dict(kv, n)
  local d = setmetatable({ keys = {}, vals = {} }, DictMT)
  for i = 1, n, 2 do R.dict_set(d, kv[i], kv[i + 1]) end
  return d
end

--- Číselná hodnota (bool jako 0/1), nebo nil.
local function numv(v)
  local t = type(v)
  if t == "number" then return v end
  if t == "boolean" then return v and 1 or 0 end
end
R.numv = numv

local function type_error(op, a, b) raise("type-error", op, R.typename(a), R.typename(b)) end

--- Obě hodnoty jako čísla, jinak TypeError.
local function nums(op, a, b)
  local x, y = numv(a), numv(b)
  if not (x and y) then type_error(op, a, b) end
  return x, y
end

--- Pravdivost hodnoty podle Pythonu.
function R.truthy(v)
  if v == true then return true end
  if v == false then return false end
  local t = type(v)
  if t == "number" then return v ~= 0 end
  if t == "string" then return v ~= "" end
  if t == "nil" then raise("unbound") end
  local mt = getmetatable(v)
  if mt == NoneMT then return false end
  if mt == ListMT or mt == TupleMT then return v.n > 0 end
  if mt == DictMT then return #v.keys > 0 end
  if mt and mt.__len_py then return mt.__len_py(v) > 0 end
  return true
end

function R.not_(a) return not R.truthy(a) end

--- Nová sekvence z prvků a a b.
local function concat_seq(a, b, mt)
  charge(a.n + b.n)
  local r = { n = a.n + b.n }
  for i = 1, a.n do r[i] = a[i] end
  for i = 1, b.n do r[a.n + i] = b[i] end
  return setmetatable(r, mt)
end

--- Sekvence opakovaná n-krát.
local function repeat_seq(s, n, mt)
  charge(s.n * n)
  local r = { n = 0 }
  for _ = 1, n do
    for i = 1, s.n do r.n = r.n + 1; r[r.n] = s[i] end
  end
  return setmetatable(r, mt)
end

function R.add(a, b)
  local ta, tb = type(a), type(b)
  if ta == "number" and tb == "number" then return a + b end
  if ta == "string" and tb == "string" then
    charge(#a + #b)
    return a .. b
  end
  local x, y = numv(a), numv(b)
  if x and y then return x + y end
  local ma = getmetatable(a)
  if (ma == ListMT or ma == TupleMT) and ma == getmetatable(b) then return concat_seq(a, b, ma) end
  type_error("+", a, b)
end

function R.sub(a, b)
  if type(a) == "number" and type(b) == "number" then return a - b end
  local x, y = nums("-", a, b)
  return x - y
end

function R.mul(a, b)
  if type(a) == "number" and type(b) == "number" then return a * b end
  local x, y = numv(a), numv(b)
  if x and y then return x * y end
  local seq, count = a, y
  if x then seq, count = b, x end
  if count and count == math.floor(count) then
    count = math.max(0, count)
    if type(seq) == "string" then
      charge(#seq * count)
      return seq:rep(count)
    end
    local mt = getmetatable(seq)
    if mt == ListMT or mt == TupleMT then return repeat_seq(seq, count, mt) end
  end
  type_error("*", a, b)
end

function R.truediv(a, b)
  if type(a) == "number" and type(b) == "number" and b ~= 0 then return a / b end
  local x, y = nums("/", a, b)
  if y == 0 then raise("zero-division") end
  return x / y
end

function R.floordiv(a, b)
  if type(a) == "number" and type(b) == "number" and b ~= 0 then return math.floor(a / b) end
  local x, y = nums("//", a, b)
  if y == 0 then raise("zero-division") end
  return math.floor(x / y)
end

function R.mod(a, b)
  if type(a) == "number" and type(b) == "number" and b ~= 0 then return a - math.floor(a / b) * b end
  local x, y = nums("%", a, b)
  if y == 0 then raise("zero-division") end
  return x - math.floor(x / y) * y
end

function R.pow(a, b)
  local x, y = nums("**", a, b)
  if x == 0 and y < 0 then raise("zero-division") end
  return x ^ y
end

function R.neg(a)
  local x = numv(a)
  if not x then raise("type-error-unary", "-", R.typename(a)) end
  return -x
end

function R.pos(a)
  local x = numv(a)
  if not x then raise("type-error-unary", "+", R.typename(a)) end
  return x
end

--- Celé číslo pro bitovou operaci, jinak TypeError.
local function intv(op, v, other)
  local x = numv(v)
  if not x or x ~= math.floor(x) then type_error(op, v, other) end
  return x
end

--- Výsledek bit32 (0..2^32-1) → int32 se znaménkem.
local function signed(u)
  if u >= 2147483648 then return u - 4294967296 end
  return u
end

--- Přetečení do int32 jako v obvodové síti.
function R.wrap32(x) return signed(x % 4294967296) end

function R.invert(a)
  local x = numv(a)
  if not x or x ~= math.floor(x) then raise("type-error-unary", "~", R.typename(a)) end
  return -x - 1
end

function R.band(a, b) return signed(bit32.band(intv("&", a, b), intv("&", b, a))) end
function R.bor(a, b) return signed(bit32.bor(intv("|", a, b), intv("|", b, a))) end
function R.bxor(a, b) return signed(bit32.bxor(intv("^", a, b), intv("^", b, a))) end

function R.lshift(a, b)
  local x, s = intv("<<", a, b), intv("<<", b, a)
  if s < 0 then raise("negative-shift") end
  if s >= 32 then return 0 end
  return signed(bit32.lshift(x, s))
end

function R.rshift(a, b)
  local x, s = intv(">>", a, b), intv(">>", b, a)
  if s < 0 then raise("negative-shift") end
  if s >= 32 then return x < 0 and -1 or 0 end
  return signed(bit32.arshift(x, s))
end

--- Rovnost s Python sémantikou (Lua boolean).
function R.eq(a, b)
  if a == b then
    if a == nil then raise("unbound") end
    return true
  end
  if a == nil or b == nil then raise("unbound") end
  if type(a) == "number" and type(b) == "number" then return false end
  local x, y = numv(a), numv(b)
  if x and y then return x == y end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  local ma = getmetatable(a)
  if ma ~= getmetatable(b) then return false end
  if ma == NoneMT then return true end
  if ma == ListMT or ma == TupleMT then
    if a.n ~= b.n then return false end
    charge(a.n)
    for i = 1, a.n do if not R.eq(a[i], b[i]) then return false end end
    return true
  end
  if ma == DictMT then
    if #a.keys ~= #b.keys then return false end
    charge(#a.keys)
    for _, k in ipairs(a.keys) do
      local bv = R.dict_get(b, k)
      if bv == nil or not R.eq(R.dict_get(a, k), bv) then return false end
    end
    return true
  end
  return false
end

function R.ne(a, b) return not R.eq(a, b) end

--- Uspořádání -1/0/1 (čísla, str, list/tuple lexikograficky), jinak TypeError.
function R.cmp(a, b, op)
  local x, y = numv(a), numv(b)
  if x and y then return x < y and -1 or (x > y and 1 or 0) end
  if type(a) == "string" and type(b) == "string" then return strcmp(a, b) end
  local ma = getmetatable(a)
  if (ma == ListMT or ma == TupleMT) and ma == getmetatable(b) then
    charge(math.min(a.n, b.n))
    for i = 1, math.min(a.n, b.n) do
      local c = R.cmp(a[i], b[i], op)
      if c ~= 0 then return c end
    end
    return a.n < b.n and -1 or (a.n > b.n and 1 or 0)
  end
  type_error(op or "<", a, b)
end

function R.lt(a, b)
  if type(a) == "number" and type(b) == "number" then return a < b end
  return R.cmp(a, b, "<") < 0
end
function R.le(a, b)
  if type(a) == "number" and type(b) == "number" then return a <= b end
  return R.cmp(a, b, "<=") <= 0
end
function R.gt(a, b)
  if type(a) == "number" and type(b) == "number" then return a > b end
  return R.cmp(a, b, ">") > 0
end
function R.ge(a, b)
  if type(a) == "number" and type(b) == "number" then return a >= b end
  return R.cmp(a, b, ">=") >= 0
end

--- `item in container`.
function R.contains(container, item)
  if type(container) == "string" then
    if type(item) ~= "string" then type_error("in", item, container) end
    charge(#container)
    return container:find(item, 1, true) ~= nil
  end
  local mt = getmetatable(container)
  if mt == ListMT or mt == TupleMT then
    charge(container.n)
    for i = 1, container.n do if R.eq(container[i], item) then return true end end
    return false
  end
  if mt == DictMT then return R.dict_get(container, item) ~= nil end
  if mt and mt.__contains then return mt.__contains(container, item) end
  type_error("in", item, container)
end

--- `a is b` (None se pozná podle metatabulky).
function R.is_(a, b)
  local an, bn = getmetatable(a) == NoneMT, getmetatable(b) == NoneMT
  if an or bn then return an and bn end
  return rawequal(a, b)
end

--- Číslo jako text v Python stylu; celé hodnoty bez ".0" (int a float se nerozlišují).
local function fmt_num(x)
  if x ~= x then return "nan" end
  if x == math.huge then return "inf" end
  if x == -math.huge then return "-inf" end
  if x == math.floor(x) and math.abs(x) < 1e16 then return string.format("%d", x) end
  local s
  for p = 1, 17 do
    -- s locale s desetinnou čárkou (cs) by printf psal "2,5"
    s = string.format("%." .. p .. "g", x):gsub(",", ".")
    if tonumber(s) == x then break end
  end
  -- CRT na Windows píše exponent třemi číslicemi (1e+020); Python a ostatní platformy dvěma
  return (s:gsub("e([%+%-])0*(%d%d)", "e%1%2"))
end
R.fmt_num = fmt_num

--- Řetězec v uvozovkách jako repr() v Pythonu.
local function repr_str(s)
  local q = "'"
  if s:find("'", 1, true) and not s:find('"', 1, true) then q = '"' end
  local out = s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", "\\r")
  if q == "'" then out = out:gsub("'", "\\'") end
  return q .. out .. q
end

function R.repr(v)
  local t = type(v)
  if t == "string" then return repr_str(v) end
  if t == "number" then return fmt_num(v) end
  if t == "boolean" then return v and "True" or "False" end
  if t == "nil" then raise("unbound") end
  local mt = getmetatable(v)
  if mt == NoneMT then return "None" end
  if mt == ListMT or mt == TupleMT then
    local parts = {}
    charge(v.n)
    for i = 1, v.n do parts[i] = R.repr(v[i]) end
    if mt == ListMT then return "[" .. table.concat(parts, ", ") .. "]" end
    if v.n == 1 then return "(" .. parts[1] .. ",)" end
    return "(" .. table.concat(parts, ", ") .. ")"
  end
  if mt == DictMT then
    local parts = {}
    charge(#v.keys)
    for i, k in ipairs(v.keys) do parts[i] = R.repr(k) .. ": " .. R.repr(R.dict_get(v, k)) end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  if mt and mt.__repr_py then return mt.__repr_py(v) end
  return "<object>"
end

function R.str(v)
  if type(v) == "string" then return v end
  return R.repr(v)
end

--- Python index (záporný od konce) → Lua index 1..n, jinak IndexError.
local function seq_index(i, n)
  local x = numv(i)
  if not x or x ~= math.floor(x) then raise("bad-index-type", R.typename(i)) end
  if x < 0 then x = x + n end
  if x < 0 or x >= n then raise("index-error") end
  return x + 1
end

function R.getitem(o, k)
  local mt = getmetatable(o)
  if mt == ListMT or mt == TupleMT then return o[seq_index(k, o.n)] end
  if mt == DictMT then
    local v = R.dict_get(o, k)
    if v == nil then raise("key-error", R.repr(k)) end
    return v
  end
  if type(o) == "string" then
    local i = seq_index(k, #o)
    return o:sub(i, i)
  end
  if mt and mt.__getitem then return mt.__getitem(o, k) end
  type_error("[]", o, k)
end

function R.setitem(o, k, v)
  local mt = getmetatable(o)
  if mt == ListMT then o[seq_index(k, o.n)] = v; return end
  if mt == DictMT then R.dict_set(o, k, v); return end
  if mt and mt.__setitem then mt.__setitem(o, k, v); return end
  raise("immutable", R.typename(o))
end

--- Meze řezu (Python) → Lua rozsah from..to (včetně).
local function slice_bounds(lo, hi, n)
  local function norm(v, default)
    if v == nil or getmetatable(v) == NoneMT then return default end
    local x = numv(v)
    if not x or x ~= math.floor(x) then raise("bad-index-type", R.typename(v)) end
    if x < 0 then x = math.max(0, x + n) end
    return math.min(x, n)
  end
  return norm(lo, 0) + 1, norm(hi, n)
end

function R.slice(o, lo, hi)
  if type(o) == "string" then
    local a, b = slice_bounds(lo, hi, #o)
    charge(b - a + 1)
    return o:sub(a, b)
  end
  local mt = getmetatable(o)
  if mt == ListMT or mt == TupleMT then
    local a, b = slice_bounds(lo, hi, o.n)
    charge(b - a + 1)
    local r = { n = 0 }
    for i = a, b do r.n = r.n + 1; r[r.n] = o[i] end
    return setmetatable(r, mt)
  end
  raise("type-error", "[:]", R.typename(o), "slice")
end

--- Iterátor pro generický for vygenerovaného kódu (konec = nil).
function R.iter(v)
  local mt = getmetatable(v)
  if mt == ListMT or mt == TupleMT then
    local i = 0
    return function()
      i = i + 1
      if i <= v.n then return v[i] end
    end
  end
  if mt == DictMT then
    local ks, i = {}, 0
    charge(#v.keys)
    for j, k in ipairs(v.keys) do ks[j] = k end
    return function() i = i + 1; return ks[i] end
  end
  if type(v) == "string" then
    local i = 0
    return function()
      i = i + 1
      if i <= #v then return v:sub(i, i) end
    end
  end
  if mt and mt.__iter then return mt.__iter(v) end
  raise("not-iterable", R.typename(v))
end

--- Rychlá cesta `obj.get(k[, default])` (n = počet argumentů, zná ho překladač): slovník přímo,
--- ostatní (objekty signálů) obecně přes R.method.
function R.mget(o, n, k, default)
  if getmetatable(o) == DictMT then
    local v = o.vals[dkey(k)]
    if v ~= nil then return v end
    if n == 2 then return default end
    return R.None
  end
  if n == 1 then return R.method(o, "get", k) end
  return R.method(o, "get", k, default)
end

--- Rychlá cesta `obj.append(x)`: seznam přímo, ostatní obecně přes R.method (chyba metody).
function R.mappend(o, x)
  if getmetatable(o) == ListMT then
    o.n = o.n + 1
    o[o.n] = x
    return R.None
  end
  return R.method(o, "append", x)
end

--- Pole pro rychlý průchod `for … in obj.items()/keys()/values()` bez stavby seznamu a n-tic.
--- items → prvky {klíč, hodnota} (indexy 1 a 2 jako u n-tice), keys/values → přímo hodnoty.
--- Slovník: snímek v okamžiku začátku cyklu (jako R.iter); objekty signálů přes __pairs_py (pole se
--- nesmí měnit – u vstupů je to sdílená cache ticku); jiné objekty obecně přes metodu.
--- @return table pole, integer počet
function R.items_array(obj, kind)
  local mt = getmetatable(obj)
  if mt == DictMT then
    local keys, vals, n = obj.keys, obj.vals, #obj.keys
    charge(n)
    local arr = {}
    for i = 1, n do
      local k = keys[i]
      if kind == "keys" then arr[i] = k
      elseif kind == "values" then arr[i] = vals[dkey(k)]
      else arr[i] = { k, vals[dkey(k)] } end
    end
    return arr, n
  end
  if mt and mt.__pairs_py then
    local pairs_ = mt.__pairs_py(obj)
    local n = #pairs_
    if kind == "items" then return pairs_, n end
    local arr, idx = {}, kind == "keys" and 1 or 2
    for i = 1, n do arr[i] = pairs_[i][idx] end
    return arr, n
  end
  local l = R.method(obj, kind)
  return l, l.n
end

--- Rozbalí hodnotu na přesně n hodnot.
function R.unpack(v, n)
  local mt = getmetatable(v)
  local arr, len
  if mt == ListMT or mt == TupleMT then
    arr, len = v, v.n
  else
    arr, len = {}, 0
    for x in R.iter(v) do len = len + 1; arr[len] = x end
  end
  if len ~= n then raise("unpack-count", n, len) end
  return table.unpack(arr, 1, n)
end

--- `a and b` v hodnotovém kontextu (bf vyhodnotí b líně).
function R.and_(a, bf)
  if R.truthy(a) then return bf() end
  return a
end

--- `a or b` v hodnotovém kontextu (bf vyhodnotí b líně).
function R.or_(a, bf)
  if R.truthy(a) then return a end
  return bf()
end

return R
