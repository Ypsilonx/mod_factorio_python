---@diagnostic disable: undefined-global
--- Kontrola, že angličtina a čeština mají přesně stejnou sadu klíčů.
local A = require("assert")

--- Načte locale.cfg a vrátí množinu klíčů „sekce.klíč“.
local function keys(path)
  local set, section = {}, ""
  for line in io.lines(path) do
    local header = line:match("^%[(.+)%]$")
    if header then
      section = header
    else
      local key = line:match("^([^#;=][^=]*)=")
      if key then set[section .. "." .. key] = true end
    end
  end
  return set
end

return {
  { "en a cs mají stejné klíče", function()
    local en = keys("Pythonator/locale/en/locale.cfg")
    local cs = keys("Pythonator/locale/cs/locale.cfg")
    for key in pairs(en) do A.truthy(cs[key], "chybí v cs: " .. key) end
    for key in pairs(cs) do A.truthy(en[key], "chybí v en: " .. key) end
  end },
}
