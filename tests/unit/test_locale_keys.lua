local A = require("assert")

local MODULES = { "errors", "signals", "lexer", "parser", "checker", "runtime", "builtins", "signal_io",
  "codegen", "compiler", "vm" }

--- Klíče sekce [pyntr-err] v locale souboru.
local function locale_keys(path)
  local set, section = {}, ""
  for line in io.lines(path) do
    local header = line:match("^%[(.+)%]$")
    if header then section = header
    elseif section == "pyntr-err" then
      local key = line:match("^([%w%-]+)=")
      if key then set[key] = true end
    end
  end
  return set
end

--- Klíče chyb použité v kódu: první řetězcový literál ve volání raise/make (i R.raise a raise).
local function used_keys()
  local set = {}
  for _, m in ipairs(MODULES) do
    local f = assert(io.open("Pythonator/scripts/lang/" .. m .. ".lua", "rb"))
    local src = f:read("a")
    f:close()
    for key in src:gmatch('raise%([^"\n]-"([%w%-]+)"') do set[key] = true end
    for key in src:gmatch('make%([^"\n]-"([%w%-]+)"') do set[key] = true end
  end
  set["unknown-signal-nosuggest"] = true
  return set
end

return {
  { "každý klíč chyby z kódu má en i cs překlad", function()
    local en = locale_keys("Pythonator/locale/en/locale.cfg")
    local cs = locale_keys("Pythonator/locale/cs/locale.cfg")
    for key in pairs(used_keys()) do
      A.truthy(en[key], "chybí v en: " .. key)
      A.truthy(cs[key], "chybí v cs: " .. key)
    end
  end },
}
