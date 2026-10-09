--- Napodobenina LuaGuiElement a hráče pro testy GUI bez hry (headless Factorio nemá hráče).
---@diagnostic disable: inject-field, missing-fields
local M = {}

--- Nový prvek podle specifikace `add{…}`: děti podle jména i v pořadí, add/destroy/clear, tags, style.
--- @param spec table
--- @param parent table|nil
function M.element(spec, parent)
  local e = {}
  for key, value in pairs(spec) do e[key] = value end
  e.parent, e.valid = parent, true
  if e.enabled == nil then e.enabled = true end
  if e.visible == nil then e.visible = true end
  e.text = spec.text or ""
  e.style = type(spec.style) == "table" and spec.style or { name = spec.style }
  e.children, e.tags = {}, spec.tags or {}
  function e.add(child_spec)
    assert(e.valid, "add do zničeného prvku")
    local child = M.element(child_spec, e)
    e.children[#e.children + 1] = child
    if child_spec.name then
      assert(not e[child_spec.name], "duplicitní jméno prvku " .. child_spec.name)
      e[child_spec.name] = child
    end
    return child
  end
  function e.destroy()
    e.valid = false
    for _, c in ipairs(e.children) do c.destroy() end
    if parent then
      if e.name then parent[e.name] = nil end
      for i, c in ipairs(parent.children) do
        if c == e then table.remove(parent.children, i); break end
      end
    end
  end
  function e.clear()
    while #e.children > 0 do e.children[1].destroy() end
  end
  function e.scroll_to_element(target) e.scrolled_to = target end
  function e.force_auto_center() e.centered = true end
  function e.focus() e.focused = true end
  function e.get_mod() return "Pythonator" end
  return e
end

--- Falešný hráč s kořeny GUI; `opened` se při zničení prvku vynuluje jako ve hře.
--- @param index integer
function M.player(index)
  local p = { index = index, valid = true, connected = true }
  p.gui = { screen = M.element({ type = "root" }) }
  return p
end

--- Nastaví globální `game` s hráči (doplní existující falešné `game` z fake_game).
--- @param players table[]
function M.install(players)
  _G.game = _G.game or { tick = 0 }
  game.players = {}
  for _, p in ipairs(players) do game.players[p.index] = p end
  game.get_player = function(i) return game.players[i] end
end

return M
