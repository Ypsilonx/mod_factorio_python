--- Ikony výstupních signálů nad budovou v ALT režimu (jako ikony nastavení u vanilla kombinátorů): které signály
--- budova právě posílá na dráty, bez hodnot. Překresluje se jen při změně sady signálů na drátech
--- (io.flush hlásí přidaný / odebraný klíč), nejvýš jednou za MIN_TICKS – program, který mění sadu každý
--- tick, by jinak každý tick mazal a kreslil objekty. Objekty jsou v ctl.alt, dirty změna v ctl.alt_dirty.
local R = require("scripts.lang.builtins")
local signals = require("scripts.lang.signals")
local resolver = require("scripts.resolver")

local M = {}

-- Laditelné hodnoty.
--- Nejvíc ikon nad budovou; při víc signálech MAX_ICONS - 1 ikon a „+N“.
M.MAX_ICONS = 4
--- Zvětšení ikony signálu.
M.ICON_SCALE = 0.6
--- Zvětšení tmavého podkladu pod ikonou.
M.BACKGROUND_SCALE = 0.55
--- Zvětšení odznaku kvality (vlevo dole na ikoně).
M.QUALITY_SCALE = 0.3
--- Rozestup ikon od středu budovy (dlaždice).
M.SPACING = 0.45
--- Velikost textu „+N“.
M.TEXT_SCALE = 1.2
--- Nejkratší doba mezi dvěma překresleními jedné budovy (ticky).
M.MIN_TICKS = 30

--- Klíče signálů na výstupních drátech (sjednocení červeného a zeleného), seřazené po bajtech.
--- @param ctl table kontrolér s ctl.wires = { red = {sent}, green = {sent} }
--- @return string[]
function M.keys(ctl)
  local seen, keys = {}, {}
  for _, state in pairs(ctl.wires or {}) do
    for key in pairs(state.sent) do
      if not seen[key] then
        seen[key] = true
        keys[#keys + 1] = key
      end
    end
  end
  table.sort(keys, function(a, b) return R.strcmp(a, b) < 0 end)
  return keys
end

--- Polohy ikon podle jejich počtu: 1 uprostřed, 2 vedle sebe, 3–4 v mřížce 2×2.
local POSITIONS = {
  { { 0, 0 } },
  { { -1, 0 }, { 1, 0 } },
  { { -1, -1 }, { 1, -1 }, { -1, 1 } },
  { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } },
}

--- Rozvržení ikon: které klíče se ukážou, kde, a kolik se nevešlo.
--- @param keys string[] seřazené klíče
--- @return table[] { {key, offset = {x, y}}… }
--- @return integer rest počet nezobrazených signálů (> 0 = na poslední pozici „+rest“)
--- @return table|nil rest_offset poloha textu „+rest“
function M.layout(keys)
  local n, shown, rest = #keys, #keys, 0
  if n > M.MAX_ICONS then shown, rest = M.MAX_ICONS - 1, n - (M.MAX_ICONS - 1) end
  local slots = POSITIONS[math.min(n, M.MAX_ICONS)] or {}
  local icons = {}
  for i = 1, shown do
    icons[i] = { key = keys[i], offset = { slots[i][1] * M.SPACING, slots[i][2] * M.SPACING } }
  end
  local rest_offset = rest > 0 and { slots[M.MAX_ICONS][1] * M.SPACING, slots[M.MAX_ICONS][2] * M.SPACING } or nil
  return icons, rest, rest_offset
end

--- Smaže nakreslené ikony kontroléru.
--- @param ctl table
function M.destroy(ctl)
  for _, obj in ipairs(ctl.alt or {}) do
    if obj.valid then obj.destroy() end
  end
  ctl.alt = nil
end

--- Společné parametry kreslení: jen v ALT, přichycené k budově s posunem.
local function base(entity, offset, layer)
  return { target = { entity = entity, offset = offset }, surface = entity.surface, only_in_alt_mode = true,
           render_layer = layer }
end

--- Nakreslí ikony podle aktuální sady výstupů (staré smaže).
--- @param ctl table
function M.draw(ctl)
  M.destroy(ctl)
  ctl.alt_dirty = nil
  local entity = ctl.entity
  if not entity.valid then return end
  local icons, rest, rest_offset = M.layout(M.keys(ctl))
  if #icons == 0 then return end
  local res, objects = resolver.get(), {}
  for _, icon in ipairs(icons) do
    local sid = res:resolve(icon.key)
    local sprite = signals.sprite(sid)
    if sprite then
      local bg = base(entity, icon.offset, "entity-info-icon")
      bg.sprite, bg.x_scale, bg.y_scale = "utility/entity_info_dark_background", M.BACKGROUND_SCALE, M.BACKGROUND_SCALE
      objects[#objects + 1] = rendering.draw_sprite(bg)
      local p = base(entity, icon.offset, "entity-info-icon-above")
      p.sprite, p.x_scale, p.y_scale = sprite, M.ICON_SCALE, M.ICON_SCALE
      objects[#objects + 1] = rendering.draw_sprite(p)
      if sid.quality and sid.quality ~= "normal" then
        local q = base(entity, { icon.offset[1] - M.SPACING / 2, icon.offset[2] + M.SPACING / 2 },
                       "entity-info-icon-above")
        q.sprite, q.x_scale, q.y_scale = "quality/" .. sid.quality, M.QUALITY_SCALE, M.QUALITY_SCALE
        objects[#objects + 1] = rendering.draw_sprite(q)
      end
    end
  end
  if rest > 0 then
    local t = base(entity, rest_offset, "entity-info-icon-above")
    t.text, t.scale, t.color = "+" .. rest, M.TEXT_SCALE, { 1, 1, 1 }
    t.alignment, t.vertical_alignment = "center", "middle"
    objects[#objects + 1] = rendering.draw_text(t)
  end
  ctl.alt = objects
end

--- Po zápisu výstupů: při změně sady signálů (`changed`) nebo dřív odložené změně překreslí, pokud od
--- posledního kreslení uplynulo MIN_TICKS; jinak změnu odloží (dokreslí ji některý další běh loop()).
--- @param ctl table
--- @param changed boolean
function M.on_flushed(ctl, changed)
  if changed then ctl.alt_dirty = true end
  if not ctl.alt_dirty then return end
  local tick = game.tick
  if ctl.alt_tick and tick - ctl.alt_tick < M.MIN_TICKS then return end
  ctl.alt_tick = tick
  M.draw(ctl)
end

return M
