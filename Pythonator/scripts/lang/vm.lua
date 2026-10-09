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
  local prev = R.active
  R.active = inst
  local ok, e = pcall(inst[what])
  R.active = prev
  local used = limit - inst.budget()
  if ok then return true, nil, used end
  if errors.is(e) then
    e.line = e.line or inst.line()
    if e.key == "pyntr-err.watchdog" then e.args = { tostring(limit) } end
    return false, e, used
  end
  return false, errors.make(inst.line(), nil, "internal", tostring(e)), used
end

--- Velikost hodnoty pro pojistku paměti: prvky kontejnerů a řetězce podle délky (1 + délka // 100).
--- Prochází iterativně (hluboké vnoření nepřeteče zásobník); tabulky v seen se nepočítají znovu.
--- @param root any
--- @param seen table již započtené tabulky (sdílené přes všechny globály)
--- @param budget integer kolik ještě zbývá do limitu – nad ním se končí
--- @return integer
local function size_of(root, seen, budget)
  local n, stack = 0, { root }
  while #stack > 0 do
    local v = stack[#stack]
    stack[#stack] = nil
    local t = type(v)
    if t == "string" then
      n = n + 1 + math.floor(#v / 100)
    elseif t == "table" and not seen[v] then
      seen[v] = true
      local mt = getmetatable(v)
      if mt == R.ListMT or mt == R.TupleMT then
        n = n + v.n
        for i = 1, v.n do stack[#stack + 1] = v[i] end
      elseif mt == R.DictMT then
        n = n + #v.keys
        for _, k in ipairs(v.keys) do
          stack[#stack + 1] = k
          stack[#stack + 1] = R.dict_get(v, k)
        end
      end
    end
    if n > budget then return n end
  end
  return n
end

--- Spočítá velikost globálů; cykly a sdílené reference jednou.
--- @param G table
--- @param limit integer
--- @return integer total
--- @return string|nil biggest jméno největšího globálu, pokud total > limit
function M.memory(G, limit)
  local seen, total = {}, 0
  local names = {}
  for name in pairs(G) do names[#names + 1] = name end
  table.sort(names, function(a, b) return R.strcmp(a, b) < 0 end)
  local biggest, bsize = nil, -1
  for _, name in ipairs(names) do
    local n = size_of(G[name], seen, limit - total)
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
