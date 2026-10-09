--- Překladač Pythonatoru: zdroj → program (factory instance + config).
local errors = require("scripts.lang.errors")
local parser = require("scripts.lang.parser")
local checker = require("scripts.lang.checker")
local codegen = require("scripts.lang.codegen")

local M = {}

--- Přeloží zdroj programu.
--- @param source string
--- @param resolver table z signals.new_resolver
--- @return table|nil program {factory = function(R, G, IO), config, lua}
--- @return table|nil err chyba jazyka {line, col, key, args}
function M.compile(source, resolver)
  local ok, res = pcall(function()
    local ast = parser.parse(source)
    local info = checker.check(ast, resolver)
    return { lua = codegen.generate(ast, info), config = info.config }
  end)
  if not ok then
    if errors.is(res) then return nil, res end
    return nil, M.lua_failure(res)
  end
  local chunk, lerr = load(res.lua, "=pythonator", "t", {})
  if not chunk then return nil, M.lua_failure(lerr) end
  return { factory = chunk(), config = res.config, lua = res.lua }
end

--- Chyba jazyka z chyby Lua při překladu: limity Lua (hloubka, počet lokálních proměnných, registrů)
--- jsou „příliš složitý program“, cokoli jiného je vnitřní chyba. Nikdy se nevyhazuje – hostitel by spadl.
--- @param msg any chybová zpráva Lua
--- @return table
function M.lua_failure(msg)
  msg = tostring(msg)
  for _, pattern in ipairs({ "stack overflow", "C levels", "too many", "overflow" }) do
    if msg:find(pattern, 1, true) then return errors.make(1, 1, "too-complex") end
  end
  return errors.make(1, 1, "internal", msg)
end

return M
