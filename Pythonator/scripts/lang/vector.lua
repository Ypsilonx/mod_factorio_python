--- Knihovna kombinátorů: vektorové operace nad sadou signálů (objekt signálů nebo dict) jedním voláním.
--- Aritmetika má sémantiku vanilla kombinátoru (celá čísla int32, dělení k nule, dělení nulou = 0).
local R = require("scripts.lang.builtins")

local M = {}

local TWO32 = 4294967296

--- Převod na int32 se znaménkem (zabalení modulo 2^32).
local function wrap(x)
  if x >= -2147483648 and x <= 2147483647 then return x end
  x = x % TWO32
  return x >= 2147483648 and x - TWO32 or x
end

--- Ořez čísla k nule (signál je celé číslo).
local function trunc(x)
  if x % 1 == 0 then return x end -- signály jsou celá čísla: rychlá cesta bez volání math
  return x >= 0 and math.floor(x) or math.ceil(x)
end

--- Násobení modulo 2^32 bez ztráty přesnosti double (rozklad na 16bitové poloviny).
local function mul32(a, b)
  local r = a * b
  -- součin int32 do 2^53 je v double přesný; pomalý rozklad jen pro velké hodnoty
  if r > -9007199254740992 and r < 9007199254740992 then return wrap(r) end
  local ua, ub = a % TWO32, b % TWO32
  local lo, hi = ua % 65536, math.floor(ua / 65536)
  return wrap((lo * ub + ((hi * ub) % 65536) * 65536) % TWO32)
end

--- Bez znaménka (0 … 2^32-1) pro bit32.
local function u(x) return x % TWO32 end

local ARITH = {
  ["+"] = function(a, b) return wrap(a + b) end,
  ["-"] = function(a, b) return wrap(a - b) end,
  ["*"] = mul32,
  ["/"] = function(a, b)
    if b == 0 then return 0 end
    return wrap(trunc(a / b))
  end,
  ["%"] = function(a, b)
    if b == 0 then return 0 end
    return wrap(a - b * trunc(a / b))
  end,
  ["**"] = function(a, b)
    if b < 0 then return 0 end
    local r = 1
    while b > 0 do
      if b % 2 == 1 then r = mul32(r, a) end
      a = mul32(a, a)
      b = math.floor(b / 2)
    end
    return r
  end,
  ["<<"] = function(a, b) return wrap(bit32.lshift(u(a), b % 32)) end,
  [">>"] = function(a, b) return wrap(bit32.arshift(u(a), b % 32)) end,
  ["&"] = function(a, b) return wrap(bit32.band(u(a), u(b))) end,
  ["|"] = function(a, b) return wrap(bit32.bor(u(a), u(b))) end,
  ["^"] = function(a, b) return wrap(bit32.bxor(u(a), u(b))) end,
}

local COMPARE = {
  ["<"] = function(a, b) return a < b end,
  ["<="] = function(a, b) return a <= b end,
  [">"] = function(a, b) return a > b end,
  [">="] = function(a, b) return a >= b end,
  ["=="] = function(a, b) return a == b end,
  ["!="] = function(a, b) return a ~= b end,
}
M.ARITH_OPS, M.COMPARE_OPS = ARITH, COMPARE

--- Číselná hodnota operandu, jinak TypeError.
local function number(op, v)
  if type(v) == "number" then return v end
  local x = R.numv(v)
  if not x then R.raise("type-error", op, "int", R.typename(v)) end
  return x
end

--- Funkce operátoru z tabulky ops, jinak chyba bad-op.
local function operator(ops, op, kind)
  local f = type(op) == "string" and ops[op]
  if not f then R.raise("bad-op", R.str(op), kind) end
  return f
end

--- a op b se sémantikou aritmetického kombinátoru.
--- @return integer
function M.arith(op, a, b)
  return operator(ARITH, op, "each")(trunc(a), trunc(b))
end

--- a op b jako podmínka rozhodovacího kombinátoru.
--- @return boolean
function M.compare(op, a, b)
  return operator(COMPARE, op, "where")(a, b)
end

-- Sada signálů se předává jako pohled (keys, vals): pole klíčů v pořadí a mapa klíč → hodnota.
-- Dict ho má nativně (d.keys, d.vals), objekty signálů ho staví bez tabulky pro každou dvojici.

--- Pohled na dict.
--- @return table keys, table vals
function M.dict_view(d) return d.keys, d.vals end

--- Nový dict naplněný přímo přes keys/vals (klíče pocházejí ze sady, jsou platné a unikátní).
--- @return table dict, table keys, table vals
local function new_dict()
  local d = R.dict({}, 0)
  return d, d.keys, d.vals
end

--- Každý signál op v (jako Each v aritmetickém kombinátoru); nulové výsledky se vypustí.
--- @return table dict
function M.each(keys, vals, op, v)
  local f = operator(ARITH, op, "each")
  local b = trunc(number(op, v))
  R.charge(#keys)
  local d, ok, ov = new_dict()
  local n = 0
  for i = 1, #keys do
    local k = keys[i]
    local r = f(trunc(number(op, vals[k])), b)
    if r ~= 0 then
      n = n + 1
      ok[n], ov[k] = k, r
    end
  end
  return d
end

--- Signály splňující hodnota op v (filtr jako Each v rozhodovacím kombinátoru), s původní hodnotou.
--- @return table dict
function M.where(keys, vals, op, v)
  local f = operator(COMPARE, op, "where")
  local b = number(op, v)
  R.charge(#keys)
  local d, ok, ov = new_dict()
  local n = 0
  for i = 1, #keys do
    local k = keys[i]
    local x = vals[k]
    if f(number(op, x), b) then
      n = n + 1
      ok[n], ov[k] = k, x
    end
  end
  return d
end

--- Počet signálů; s op a v jen těch, které podmínku splní.
function M.count(keys, vals, n, op, v)
  if n ~= 0 and n ~= 2 then R.raise("arg-count", "count", "0/2", n) end
  if n == 0 then return #keys end
  local f = operator(COMPARE, op, "count")
  local b = number(op, v)
  R.charge(#keys)
  local c = 0
  for i = 1, #keys do
    if f(number(op, vals[keys[i]]), b) then c = c + 1 end
  end
  return c
end

--- Součet hodnot (přesně, bez přetečení int32).
function M.sum(keys, vals)
  R.charge(#keys)
  local s = 0
  for i = 1, #keys do s = s + number("sum", vals[keys[i]]) end
  return s
end

--- Klíč s největší (sign = 1) nebo nejmenší (sign = -1) hodnotou; při shodě menší klíč po bajtech.
--- @return any klíč, nebo None pro prázdnou sadu
function M.extreme_key(keys, vals, sign)
  R.charge(#keys)
  local best, bv
  for i = 1, #keys do
    local k = keys[i]
    local x = number("max_key", vals[k]) * sign
    if best == nil or x > bv or (x == bv and R.strcmp(R.str(k), R.str(best)) < 0) then
      best, bv = k, x
    end
  end
  if best == nil then return R.None end
  return best
end

--- Metody sady signálů nad funkcí view(obj) → keys, vals. Signatura metody (obj, n, ...) jako R.METHODS.
--- @param view function
--- @return table jméno → metoda
function M.methods(view)
  local function argc(name, n, k)
    if n ~= k then R.raise("arg-count", name, k, n) end
  end
  return {
    each = function(obj, n, op, v)
      argc("each", n, 2)
      local keys, vals = view(obj)
      return M.each(keys, vals, op, v)
    end,
    where = function(obj, n, op, v)
      argc("where", n, 2)
      local keys, vals = view(obj)
      return M.where(keys, vals, op, v)
    end,
    count = function(obj, n, op, v)
      local keys, vals = view(obj)
      return M.count(keys, vals, n, op, v)
    end,
    sum = function(obj, n)
      argc("sum", n, 0)
      return M.sum(view(obj))
    end,
    max_key = function(obj, n)
      argc("max_key", n, 0)
      local keys, vals = view(obj)
      return M.extreme_key(keys, vals, 1)
    end,
    min_key = function(obj, n)
      argc("min_key", n, 0)
      local keys, vals = view(obj)
      return M.extreme_key(keys, vals, -1)
    end,
  }
end

-- Metody i pro dict, aby šly operace řetězit (`inp.where(">", 0).each("*", 2)`).
for name, f in pairs(M.methods(M.dict_view)) do R.METHODS.dict[name] = f end

return M
