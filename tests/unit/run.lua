---@diagnostic disable: undefined-global
--- Runner jednotkových testů (spouští se z kořene repozitáře: lua tests/unit/run.lua).
package.path = "Pythonator/?.lua;tests/unit/?.lua;" .. package.path

--- Seznam testovacích sad; každá vrací pole { "název", funkce }.
local SUITES = { "test_locale", "test_errors", "test_signals", "test_lexer", "test_parser_expr", "test_parser_stmt", "test_runtime_core", "test_builtins", "test_signal_io" }

local pass, fail = 0, 0
for _, suite in ipairs(SUITES) do
  for _, case in ipairs(require(suite)) do
    local ok, err = pcall(case[2])
    if ok then
      pass = pass + 1
    else
      fail = fail + 1
      if type(err) == "table" then err = (err.key or "?") .. " " .. table.concat(err.args or {}, ", ") end
      print("FAIL " .. suite .. " :: " .. case[1] .. ": " .. tostring(err))
    end
  end
end
print(string.format("UNIT pass=%d fail=%d", pass, fail))
os.exit(fail == 0 and 0 or 1)
