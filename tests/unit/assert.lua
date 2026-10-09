--- Pomocné aserce pro jednotkové testy mimo hru.
local A = {}

--- Převod hodnoty na text pro hlášku (tabulky rekurzivně, klíče seřazené).
local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(v[k]) end
  return "{" .. table.concat(parts, ", ") .. "}"
end
A.show = show

--- Selže, pokud se hodnoty nerovnají.
--- @param actual any
--- @param expected any
--- @param what string popis kontrolované hodnoty
function A.eq(actual, expected, what)
  if actual ~= expected then
    error(string.format("%s: čekáno %s, dostáno %s", what, show(expected), show(actual)), 2)
  end
end

--- Selže, pokud hodnota není pravdivá.
function A.truthy(value, what)
  if not value then error(what .. ": čekána pravdivá hodnota", 2) end
end

--- Hluboké porovnání tabulek (metatabulky se ignorují).
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

--- Selže, pokud se tabulky hluboce liší.
function A.same(actual, expected, what)
  if not same(actual, expected) then
    error(string.format("%s: čekáno %s, dostáno %s", what, show(expected), show(actual)), 2)
  end
end

--- Ověří, že fn vyhodí chybu jazyka s daným klíčem (bez prefixu), a vrátí ji.
--- @param fn function
--- @param key string např. "bad-indent"
--- @return table err
function A.raises(fn, key)
  local ok, err = pcall(fn)
  if ok then error("čekána chyba " .. key .. ", nic nevyhozeno", 2) end
  if type(err) ~= "table" or err.key ~= "pyntr-err." .. key then
    error("čekána chyba " .. key .. ", dostáno " .. show(err), 2)
  end
  return err
end

return A
