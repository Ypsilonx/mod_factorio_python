---@diagnostic disable: undefined-global
--- Jména GUI prvků nesmí kolidovat s vlastnostmi a metodami LuaGuiElement (např. "state"), jinak hra
--- spadne při stavbě okna. Headless testy GUI netvoří (nejsou hráči), proto kontrola staticky proti API
--- dokumentaci hry. Bez dokumentace (jiná instalace) se test přeskočí.
local A = require("assert")

--- Cesta k API dokumentaci; jiná instalace hry → proměnná prostředí FACTORIO_API_JSON.
local API_JSON = os.getenv("FACTORIO_API_JSON") or "C:/STEAM/steamapps/common/Factorio/doc-html/runtime-api.json"

--- Soubory, které stavějí GUI prvky.
local GUI_FILES = {
  "Pythonator/scripts/gui/window.lua",
  "Pythonator/scripts/gui/editor.lua",
}

--- Celý soubor jako text (nebo nil).
local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end

--- Množina jmen z definice třídy LuaGuiElement (vlastnosti, metody, parametry).
local function reserved_names(api)
  local start = api:find('{"name":"LuaGuiElement","order"', 1, true)
  local first = api:find('"abstract":', start, true)
  local next_class = api:find('"abstract":', first + 1, true)
  local set = {}
  for name in api:sub(start, next_class):gmatch('"name":"([%w_]+)"') do set[name] = true end
  return set
end

return {
  { "jména prvků okna nekolidují s LuaGuiElement a mají prefix", function()
    local api = read(API_JSON)
    if not api then
      print("SKIP test_gui_names: chybí " .. API_JSON)
      return
    end
    local reserved = reserved_names(api)
    A.truthy(reserved["state"] and reserved["caption"], "seznam vlastností LuaGuiElement načten")
    for _, file in ipairs(GUI_FILES) do
      local source = read(file)
      A.truthy(source, "soubor " .. file)
      for name in source:gmatch('name%s*=%s*"([^"]+)"') do
        A.eq(reserved[name], nil, file .. ": jméno prvku '" .. name .. "' koliduje s LuaGuiElement")
        A.truthy(name:find("^pyntr_"), file .. ": jméno prvku '" .. name .. "' bez prefixu pyntr_")
      end
    end
  end },
}
