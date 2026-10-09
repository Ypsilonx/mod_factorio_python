--- Testy prototypů Tipů a triků: kategorie Pythonator, záznamy odemčené od začátku, texty sdílené s nápovědou
--- budovy (stejné klíče locale), příklady s kódem a limity lokalizovaných řetězců hry.
local A = require("assert")

--- Načte prototypes/tips.lua s falešným `data` a vrátí přidané prototypy podle jména.
local function load()
  local saved = _G.data
  local added = {}
  _G.data = { extend = function(_, list) for _, p in ipairs(list) do added[p.name] = p end end }
  package.loaded["prototypes.tips"] = nil
  require("prototypes.tips")
  _G.data = saved
  package.loaded["prototypes.tips"] = nil
  return added
end

--- Klíče sekce [pyntr-gui] v locale souboru.
local function locale_keys(path)
  local set, section = {}, ""
  for line in io.lines(path) do
    local header = line:match("^%[(.+)%]$")
    if header then section = header
    elseif section == "pyntr-gui" then
      local key = line:match("^([%w%-_]+)=")
      if key then set["pyntr-gui." .. key] = true end
    end
  end
  return set
end

--- Projde lokalizovaný řetězec: zkontroluje limit parametrů (20) a vrátí použité klíče a texty.
local function walk(ls, keys, texts, depth)
  depth = depth or 1
  A.truthy(depth <= 20, "hloubka vnoření lokalizovaného řetězce")
  if type(ls) == "string" then
    texts[#texts + 1] = ls
    return
  end
  A.truthy(#ls - 1 <= 20, "nejvýš 20 parametrů (" .. tostring(ls[1]) .. ")")
  if ls[1] ~= "" then keys[ls[1]] = true end
  for i = 2, #ls do walk(ls[i], keys, texts, depth + 1) end
end

return {
  { "kategorie Pythonator: titulek a podřízené záznamy, všechny odemčené od začátku", function()
    local p = load()
    A.eq(p["pyntr"] and p["pyntr"].type, "tips-and-tricks-item-category", "kategorie")
    local title = p["pyntr-pythonator"]
    A.truthy(title and title.is_title, "titulní záznam")
    local n = 0
    for name, proto in pairs(p) do
      if proto.type == "tips-and-tricks-item" then
        n = n + 1
        A.eq(proto.category, "pyntr", name .. ": kategorie")
        A.eq(proto.starting_status, "unlocked", name .. ": dostupné bez budovy")
        if name ~= "pyntr-pythonator" then A.eq(proto.indent, 1, name .. ": odsazení pod titulkem") end
      end
    end
    A.eq(n, 6, "titulek (jak začít) + signály, jazyk, knihovna, výkon, příklady")
  end },
  { "texty tipů jsou klíče nápovědy budovy (en i cs) a vejdou se do limitů", function()
    local p = load()
    local en = locale_keys("Pythonator/locale/en/locale.cfg")
    local cs = locale_keys("Pythonator/locale/cs/locale.cfg")
    for name, proto in pairs(p) do
      if proto.type == "tips-and-tricks-item" then
        local keys, texts = {}, {}
        walk(proto.localised_name, keys, texts)
        walk(proto.localised_description, keys, texts)
        for key in pairs(keys) do
          A.truthy(en[key], name .. ": chybí v en " .. key)
          A.truthy(cs[key], name .. ": chybí v cs " .. key)
        end
      end
    end
  end },
  { "tip Příklady obsahuje kód všech příkladů z nápovědy", function()
    local p = load()
    local keys, texts = {}, {}
    walk(p["pyntr-examples"].localised_description, keys, texts)
    local all = table.concat(texts, "\n")
    for _, ex in ipairs(require("scripts.gui.help").EXAMPLES) do
      A.truthy(all:find(ex.code, 1, true), "kód příkladu " .. ex.id)
      A.truthy(keys["pyntr-gui.help-example-" .. ex.id .. "-desc"], "popis příkladu " .. ex.id)
    end
  end },
}
