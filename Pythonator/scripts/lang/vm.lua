--- Běh programu: instance nad globály, spuštění s watchdogem, převod chyb, pojistka paměti.
local errors = require("scripts.lang.errors")
local R = require("scripts.lang.builtins")

local M = {}

--- Vytvoří instanci programu nad globály G a vstupy/výstupy IO.
--- @param program table z compiler.compile
--- @param G table globální proměnné (u hostitele ve storage)
--- @param IO table {inp, red, green, out, out_red, out_green, print, tick, game_tick, dt}
--- @return table instance
function M.instantiate(program, G, IO)
  return program.factory(R, G, IO)
end

--- Spustí init nebo loop s rozpočtem watchdogu.
--- @param inst table instance
--- @param what string "init" | "loop"
--- @param limit integer rozpočet operací
--- @return boolean ok
--- @return table|nil err chyba s řádkem zdroje
--- @return integer used spotřebované operace
function M.run(inst, what, limit)
  inst.set_budget(limit)
  local ok, e = pcall(inst[what])
  local used = limit - inst.budget()
  if ok then return true, nil, used end
  if errors.is(e) then
    e.line = e.line or inst.line()
    if e.key == "pyntr-err.watchdog" then e.args = { tostring(limit) } end
    return false, e, used
  end
  return false, errors.make(inst.line(), nil, "internal", tostring(e)), used
end

--- Spočítá prvky kontejnerů v globálech; cykly a sdílené reference jednou.
--- @param G table
--- @param limit integer
--- @return integer total
--- @return string|nil biggest jméno největšího globálu, pokud total > limit
function M.memory(G, limit)
  local seen, total = {}, 0
  local function count(v)
    if type(v) ~= "table" or seen[v] then return 0 end
    seen[v] = true
    local mt, n = getmetatable(v), 0
    if mt == R.ListMT or mt == R.TupleMT then
      n = v.n
      for i = 1, v.n do
        n = n + count(v[i])
        if total + n > limit then return n end
      end
    elseif mt == R.DictMT then
      n = #v.keys
      for _, k in ipairs(v.keys) do
        n = n + count(R.dict_get(v, k))
        if total + n > limit then return n end
      end
    end
    return n
  end
  local names = {}
  for name in pairs(G) do names[#names + 1] = name end
  table.sort(names)
  local biggest, bsize = nil, -1
  for _, name in ipairs(names) do
    local n = count(G[name])
    total = total + n
    if n > bsize then biggest, bsize = name, n end
    if total > limit then return total, biggest end
  end
  return total, nil
end

--- Chyba pojistky paměti, nebo nil, pokud je vše v limitu.
--- @return table|nil
function M.check_memory(G, limit)
  local total, biggest = M.memory(G, limit)
  if total > limit then return errors.make(nil, nil, "memory", biggest, limit) end
end

return M
