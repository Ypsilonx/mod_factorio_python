local A = require("assert")

local MODULES = { "errors", "signals", "lexer", "parser", "checker", "runtime", "builtins", "signal_io",
  "codegen", "compiler", "vm", "vector", "elements" }

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

--- Klíče sekce `section` v locale souboru.
local function section_keys(path, section)
  local set, current = {}, ""
  for line in io.lines(path) do
    local header = line:match("^%[(.+)%]$")
    if header then current = header
    elseif current == section then
      local key = line:match("^([%w%-_]+)=")
      if key then set[key] = true end
    end
  end
  return set
end

--- Soubory GUI a klíče skládané za běhu (stav a tooltipy tlačítek), které literál v kódu nenajde.
local GUI_FILES = { "window", "editor", "status", "events", "panels", "help" }
local GUI_DYNAMIC = { "state-off", "state-running", "state-paused", "state-error", "state-no_power",
  "tooltip-play", "tooltip-pause", "tooltip-reset", "tooltip-step" }

return {
  { "každý klíč [pyntr-gui] z kódu GUI má en i cs překlad", function()
    local en = section_keys("Pythonator/locale/en/locale.cfg", "pyntr-gui")
    local cs = section_keys("Pythonator/locale/cs/locale.cfg", "pyntr-gui")
    local used = {}
    for _, k in ipairs(GUI_DYNAMIC) do used[k] = true end
    for _, name in ipairs(GUI_FILES) do
      local f = io.open("Pythonator/scripts/gui/" .. name .. ".lua", "rb")
      if f then
        -- předpona skládaného klíče ("pyntr-gui.state-" .. x) pokrývá GUI_DYNAMIC
        for key in f:read("a"):gmatch('"pyntr%-gui%.([%w%-_]+)"') do
          if not key:find("%-$") then used[key] = true end
        end
        f:close()
      end
    end
    for key in pairs(used) do
      A.truthy(en[key], "chybí v en: pyntr-gui." .. key)
      A.truthy(cs[key], "chybí v cs: pyntr-gui." .. key)
    end
  end },
  { "každý klíč chyby z kódu má en i cs překlad", function()
    local en = locale_keys("Pythonator/locale/en/locale.cfg")
    local cs = locale_keys("Pythonator/locale/cs/locale.cfg")
    for key in pairs(used_keys()) do
      A.truthy(en[key], "chybí v en: " .. key)
      A.truthy(cs[key], "chybí v cs: " .. key)
    end
  end },
}
