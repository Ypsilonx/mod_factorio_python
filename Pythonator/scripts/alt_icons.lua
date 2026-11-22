--- Šipky vstupu a výstupu a ikony nad budovou v ALT režimu (jako ikony nastavení u vanilla kombinátorů): na straně vstupu řada signálů,
--- které program čte v kódu (Each = čte celou sadu), na straně výstupu řada signálů, které budova právě
--- posílá na dráty; ikony stojí vedle šipek hry. Uprostřed ikona z config(icon=…) – ta je vidět trvale, i bez ALT.
--- Barva podkladu značí drát: tmavá oba, červená, zelená. Řady se otáčejí s budovou.
--- Výstupy se překreslují jen při změně sady signálů na drátech (io.flush hlásí přidaný / odebraný klíč), nejvýš
--- jednou za MIN_TICKS – program, který mění sadu každý tick, by jinak každý tick mazal a kreslil objekty. Objekty jsou v ctl.alt, odložená změna v ctl.alt_dirty.
local R = require("scripts.lang.builtins")
local signals = require("scripts.lang.signals")
local resolver = require("scripts.resolver")

local M = {}

-- Laditelné hodnoty.
--- Vzdálenost řady vstupů / výstupů od středu budovy (dlaždice); šipky stojí na hraně (ARROW_DISTANCE),
--- řady jsou uvnitř.
M.ROW_OFFSET = 0.55
--- Polohy ikon v řadě napříč budovou (dlaždice).
--- Počet poloh = nejvíc ikon v řadě; při víc signálech se na poslední poloze ukáže „+N“.
M.ROW_SLOTS = { -0.6, 0, 0.6 }
--- Zvětšení ikony signálu v řadě.
M.ICON_SCALE = 0.5
--- Zvětšení tmavého podkladu (signál na obou drátech).
M.BACKGROUND_SCALE = 0.45
--- Velikost barevného podkladu signálu na jednom drátu (strana čtverce v dlaždicích).
M.WIRE_SIZE = 0.48
--- Barvy podkladu podle drátu – poloprůhledné; složky jsou přednásobené alfou (tint sprite ve Factoriu).
M.WIRE_COLORS = { red = { r = 0.3, g = 0.04, b = 0.04, a = 0.5 }, green = { r = 0.04, g = 0.25, b = 0.06, a = 0.5 } }
--- Sprite podkladu drátu (bílý čtverec 10 px, obarví se tintem) a jeho velikost v dlaždicích při zvětšení 1.
local WIRE_SPRITE, WIRE_SPRITE_TILES = "utility/white_square", 10 / 32
--- Zvětšení ikony z config(icon=…) uprostřed budovy (vidět trvale, ne jen v ALT).
M.MAIN_SCALE = 0.6
--- Stín ikony programu: posun (dlaždice) a barva (průhledná černá).
M.SHADOW_SHIFT = 0.05
M.SHADOW_COLOR = { r = 0, g = 0, b = 0, a = 0.6 }
--- Zvětšení odznaku kvality (vlevo dole na ikoně).
M.QUALITY_SCALE = 0.25
--- Velikost textu „+N“.
M.TEXT_SCALE = 1
--- Šipky vstupu a výstupu (šipky enginu jsou vypnuté příznakem hide-alt-info v prototypes/entity.lua):
--- vzdálenost středu šipky od středu budovy (dlaždice; 1 = na hraně), zvětšení a sprite (míří na sever).
M.ARROW_DISTANCE = 1.05
M.ARROW_SCALE = 0.6
M.ARROW_SPRITE = "utility/indication_arrow"
--- Nejkratší doba mezi dvěma překresleními jedné budovy kvůli změně výstupů (ticky).
M.MIN_TICKS = 30

--- Výstupní signály na drátech: { {key, wire}… } seřazené po bajtech; wire "both" = na obou drátech.
--- @param ctl table kontrolér s ctl.wires = { red = {sent}, green = {sent} }
--- @return table[]
function M.outputs(ctl)
  local wires = ctl.wires or {}
  local red = wires.red and wires.red.sent or {}
  local green = wires.green and wires.green.sent or {}
  local keys = {}
  for key in pairs(red) do keys[#keys + 1] = key end
  for key in pairs(green) do
    if red[key] == nil then keys[#keys + 1] = key end
  end
  table.sort(keys, function(a, b) return R.strcmp(a, b) < 0 end)
  local out = {}
  for i, key in ipairs(keys) do
    local wire = red[key] == nil and "green" or green[key] == nil and "red" or "both"
    out[i] = { key = key, wire = wire }
  end
  return out
end

--- Otočí posun (budova otočená výstupem na sever) podle směru budovy.
--- @param x number
--- @param y number
--- @param direction integer defines.direction (sever 0, východ 4, jih 8, západ 12)
--- @return table {x, y}
function M.rotate(x, y, direction)
  if direction == 4 then return { -y, x } end
  if direction == 8 then return { -x, -y } end
  if direction == 12 then return { y, -x } end
  return { x, y }
end

--- Rozvrhne jednu řadu do poloh ROW_SLOTS; při víc signálech než poloh poslední poloha ukáže „+N“.
local function row(items, y, direction, out)
  local n, max = #items, #M.ROW_SLOTS
  local shown = n > max and max - 1 or n
  for i = 1, math.min(n, max) do
    local offset = M.rotate(M.ROW_SLOTS[i], y, direction)
    if i <= shown then
      out[#out + 1] = { key = items[i].key, wire = items[i].wire, offset = offset }
    else
      out[#out + 1] = { text = "+" .. (n - shown), offset = offset }
    end
  end
end

--- Šipky vstupu a výstupu: polohy na hraně budovy a natočení po toku signálu (ze vstupu k výstupu).
--- @param direction integer
--- @return table[] { {offset = {x, y}, orientation}… } – vstupní a výstupní šipka
function M.arrows(direction)
  local orientation = direction / 16
  return {
    { offset = M.rotate(0, M.ARROW_DISTANCE, direction), orientation = orientation },
    { offset = M.rotate(0, -M.ARROW_DISTANCE, direction), orientation = orientation },
  }
end

--- Rozvržení všech ikon nad budovou.
--- @param inputs table[] čtené vstupy { {key, wire}… }
--- @param outputs table[] výstupy { {key, wire}… }
--- @param icon string|nil klíč ikony z config(icon=…)
--- @param direction integer
--- @return table[] { {key, wire, offset, main?} | {text, offset}… }
function M.layout(inputs, outputs, icon, direction)
  local out = {}
  row(outputs, -M.ROW_OFFSET, direction, out)
  row(inputs, M.ROW_OFFSET, direction, out)
  if icon then out[#out + 1] = { key = icon, wire = "both", offset = { 0, 0 }, main = true } end
  return out
end

--- Smaže nakreslené ikony kontroléru.
--- @param ctl table
function M.destroy(ctl)
  for _, obj in ipairs(ctl.alt or {}) do
    if obj.valid then obj.destroy() end
  end
  ctl.alt = nil
end

--- Společné parametry kreslení: přichycené k budově s posunem, jen v ALT (pokud `always` není true).
local function base(entity, offset, layer, always)
  return { target = { entity = entity, offset = offset }, surface = entity.surface, only_in_alt_mode = not always,
           render_layer = layer }
end

--- Nakreslí jednu ikonu (podklad podle drátu, sprite, odznak kvality) a přidá objekty do `objects`.
--- Ikona programu (item.main) je bez podkladu, se stínem a vidět trvale, jako nápis na budově.
local function draw_icon(entity, item, res, objects)
  local sid = res:resolve(item.key)
  local sprite = signals.sprite(sid)
  if not sprite then return end
  local main = item.main == true
  local scale = main and M.MAIN_SCALE or M.ICON_SCALE
  local color = M.WIRE_COLORS[item.wire]
  if color and not main then
    -- sprite, ne draw_circle: kruh nemá vrstvu a kreslí se přes ikonu
    local c = base(entity, item.offset, "entity-info-icon")
    local s = M.WIRE_SIZE / WIRE_SPRITE_TILES
    c.sprite, c.tint, c.x_scale, c.y_scale = WIRE_SPRITE, color, s, s
    objects[#objects + 1] = rendering.draw_sprite(c)
  elseif not main then
    local bg = base(entity, item.offset, "entity-info-icon")
    bg.sprite, bg.x_scale, bg.y_scale = "utility/entity_info_dark_background", M.BACKGROUND_SCALE, M.BACKGROUND_SCALE
    objects[#objects + 1] = rendering.draw_sprite(bg)
  end
  if main then
    local shifted = { item.offset[1] + M.SHADOW_SHIFT, item.offset[2] + M.SHADOW_SHIFT }
    local s = base(entity, shifted, "higher-object-under", true)
    s.sprite, s.x_scale, s.y_scale, s.tint = sprite, scale, scale, M.SHADOW_COLOR
    objects[#objects + 1] = rendering.draw_sprite(s)
  end
  -- stín ve vrstvě pod ikonou: ve stejné vrstvě hra pořadí objektů nezaručuje (stín byl nad ikonou)
  local p = base(entity, item.offset, main and "higher-object-above" or "entity-info-icon-above", main)
  p.sprite, p.x_scale, p.y_scale = sprite, scale, scale
  objects[#objects + 1] = rendering.draw_sprite(p)
  if sid.quality and sid.quality ~= "normal" then
    local d = scale * 0.4
    local q = base(entity, { item.offset[1] - d, item.offset[2] + d },
                   main and "higher-object-above" or "entity-info-icon-above", main)
    q.sprite, q.x_scale, q.y_scale = "quality/" .. sid.quality, M.QUALITY_SCALE, M.QUALITY_SCALE
    objects[#objects + 1] = rendering.draw_sprite(q)
  end
end

--- Nakreslí šipky a ikony podle aktuálních vstupů, výstupů a ikony programu (staré smaže).
--- Volá se i při stavbě a otočení budovy (šipky musí mít i budova bez kódu).
--- @param ctl table
function M.draw(ctl)
  M.destroy(ctl)
  ctl.alt_dirty = nil
  local entity = ctl.entity
  if not entity.valid then return end
  local items = M.layout(ctl.inputs or {}, M.outputs(ctl), ctl.icon, entity.direction)
  local res, objects = resolver.get(), {}
  for _, a in ipairs(M.arrows(entity.direction)) do
    local p = base(entity, a.offset, "entity-info-icon-above")
    p.sprite, p.orientation, p.x_scale, p.y_scale = M.ARROW_SPRITE, a.orientation, M.ARROW_SCALE, M.ARROW_SCALE
    objects[#objects + 1] = rendering.draw_sprite(p)
  end
  for _, item in ipairs(items) do
    if item.text then
      local t = base(entity, item.offset, "entity-info-icon-above")
      t.text, t.scale, t.color = item.text, M.TEXT_SCALE, { 1, 1, 1 }
      t.alignment, t.vertical_alignment = "center", "middle"
      objects[#objects + 1] = rendering.draw_text(t)
    else
      draw_icon(entity, item, res, objects)
    end
  end
  ctl.alt = objects
end

--- Po zápisu výstupů: při změně sady signálů (`changed`) nebo dřív odložené změně překreslí, pokud od
--- posledního kreslení uplynulo MIN_TICKS; jinak budovu zařadí do fronty storage.alt_pending, kterou dokreslí
--- on_pending – i když program mezitím stojí (pauza, chyba, bez proudu) nebo má dlouhý interval.
--- @param ctl table
--- @param changed boolean
function M.on_flushed(ctl, changed)
  if changed then ctl.alt_dirty = true end
  if not ctl.alt_dirty then return end
  local tick = game.tick
  if ctl.alt_tick and tick - ctl.alt_tick < M.MIN_TICKS then
    storage.alt_pending = storage.alt_pending or {}
    storage.alt_pending[ctl.unit] = true
    return
  end
  ctl.alt_tick = tick
  M.draw(ctl)
end

--- Dokreslí odložené změny (on_nth_tick(MIN_TICKS)). Bez čekajících budov hned skončí.
function M.on_pending()
  local pending = storage.alt_pending
  if not (pending and next(pending)) then return end
  storage.alt_pending = {}
  local tick = game.tick
  for unit in pairs(pending) do
    local ctl = storage.controllers[unit]
    if ctl and ctl.alt_dirty then
      ctl.alt_tick = tick
      M.draw(ctl)
    end
  end
end

return M
