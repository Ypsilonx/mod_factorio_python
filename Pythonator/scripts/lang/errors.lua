--- Chyby jazyka Pythonator: tabulka {line, col, key, args}, kterou hostitel zobrazí lokalizovaně.
local M = {}

--- Sestaví chybu jazyka.
--- @param line integer|nil řádek zdroje (nil = doplní VM)
--- @param col integer|nil sloupec zdroje
--- @param key string klíč bez prefixu, např. "bad-indent"
--- @param ... any argumenty hlášky (převedou se na text)
--- @return table
function M.make(line, col, key, ...)
  local args = { ... }
  for i = 1, select("#", ...) do args[i] = tostring(args[i]) end
  return { pyntr_error = true, line = line, col = col, key = "pyntr-err." .. key, args = args }
end

--- Vyhodí chybu jazyka (bez připojené pozice Lua).
function M.raise(line, col, key, ...)
  error(M.make(line, col, key, ...), 0)
end

--- Je hodnota chyba jazyka?
--- @param v any
--- @return boolean
function M.is(v)
  return type(v) == "table" and v.pyntr_error == true
end

return M
