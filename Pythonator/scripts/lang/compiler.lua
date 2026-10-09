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
    error(res, 0)
  end
  local chunk, lerr = load(res.lua, "=pythonator", "t", {})
  if not chunk then error("Pythonator: vygenerovaný kód nejde načíst: " .. tostring(lerr) .. "\n" .. res.lua, 0) end
  return { factory = chunk(), config = res.config, lua = res.lua }
end

return M
