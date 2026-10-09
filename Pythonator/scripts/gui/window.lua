--- Okno Pythonatoru (player.gui.screen): titulek, editor kódu a panely stavu. Jedno okno na hráče;
--- otevření jiné budovy okno přestaví pro ni. Stav okna je ve storage.gui[player_index] = {unit, refs, text},
--- kde refs jsou odkazy na prvky (LuaGuiElement jde uložit do storage, před použitím se kontroluje valid).
local controller = require("scripts.controller")
local actions = require("scripts.actions")
local editor = require("scripts.gui.editor")
local status = require("scripts.gui.status")
local panels = require("scripts.gui.panels")

local M = {}

local WINDOW = "pyntr_window"

--- Tabulka otevřených oken ve storage (založí se líně – ne v on_load).
local function all()
  storage.gui = storage.gui or {}
  return storage.gui
end
M.all = all

--- Odkazy na prvky otevřeného okna hráče, nebo nil.
--- @param player LuaPlayer
--- @return table|nil refs
function M.get(player)
  local st = all()[player.index]
  if st and st.refs.frame.valid then return st.refs end
end

--- Stav okna hráče (unit, refs, text), nebo nil.
function M.state(player)
  return all()[player.index]
end

--- Titulek: jméno budovy, plocha pro přetažení okna a křížek.
local function add_titlebar(frame, refs)
  local bar = frame.add({ type = "flow", name = "pyntr_titlebar", direction = "horizontal" })
  bar.drag_target = frame
  bar.style.horizontal_spacing = 8
  bar.add({ type = "label", caption = { "entity-name.pyntr-pythonator" }, style = "frame_title",
            ignored_by_interaction = true })
  local drag = bar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  drag.style.height = 24
  drag.style.horizontally_stretchable = true
  refs.close = bar.add({ type = "sprite-button", name = "pyntr_close", sprite = "utility/close",
                         style = "frame_action_button", tags = { pyntr_action = "close" } })
end

--- Zavře okno hráče (pokud je otevřené).
--- @param player LuaPlayer
function M.close(player)
  local st = all()[player.index]
  all()[player.index] = nil
  if st and st.refs.frame.valid then st.refs.frame.destroy() end
end

--- Otevře okno nad kontrolérem (jiné okno hráče se zavře).
--- @param player LuaPlayer
--- @param ctl table kontrolér
function M.open(player, ctl)
  M.close(player)
  local frame = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical" })
  local refs = { frame = frame }
  add_titlebar(frame, refs)
  local body = frame.add({ type = "flow", name = "pyntr_body", direction = "horizontal" })
  refs.body = body
  local left = body.add({ type = "flow", name = "pyntr_left", direction = "vertical" })
  local ed = editor.build(left)
  refs.scroll, refs.gutter, refs.code = ed.scroll, ed.gutter, ed.code
  refs.left = left
  refs.side = body.add({ type = "flow", name = "pyntr_side", direction = "vertical" })
  status.build(left, refs.side, refs)
  panels.build(left, refs.side, refs)
  all()[player.index] = { unit = ctl.unit, refs = refs, text = nil }
  frame.force_auto_center()
  M.refresh(player)
  player.opened = frame
end

--- Obnoví okno podle stavu kontroléru: text editoru (za běhu nahraný kód, při pauze draft) a jen pro čtení.
--- @param player LuaPlayer
function M.refresh(player)
  local st = all()[player.index]
  if not st then return end
  local ctl = controller.get(st.unit)
  if not ctl or not st.refs.frame.valid then
    M.close(player)
    return
  end
  local view = actions.view(ctl)
  local text = view.can.edit and actions.text(ctl) or ctl.code
  st.refs.code.read_only = not view.can.edit
  editor.set_text(st.refs, text)
  st.text, st.edit, st.code = text, view.can.edit, ctl.code
  status.update(st.refs, view, st)
  panels.refresh(st.refs, ctl)
end

--- Periodická obnova otevřeného okna: stav a panely; text editoru jen když se změnilo, jestli jde psát
--- (chyba nebo výpadek změní stav bez akce hráče).
--- @param player LuaPlayer
function M.refresh_live(player)
  local st = all()[player.index]
  local ctl = st and controller.get(st.unit)
  if not (ctl and st.refs.frame.valid) then
    M.close(player)
    return
  end
  local view = actions.view(ctl)
  -- plná obnova i po novém kódu bez akce v okně (vložení nastavení, remote set_code), jinak by
  -- editor ukazoval starý text a Play by nový kód přepsal
  if view.can.edit ~= st.edit or ctl.code ~= st.code then return M.refresh(player) end
  status.update(st.refs, view, st)
  panels.refresh(st.refs, ctl)
end

--- Obnoví jen tlačítka a stav (ne text editoru – hráč právě píše).
--- @param player LuaPlayer
function M.refresh_status(player)
  local st = all()[player.index]
  local ctl = st and controller.get(st.unit)
  if ctl and st.refs.frame.valid then status.update(st.refs, actions.view(ctl), st) end
end

--- Hráči, kteří mají otevřené okno budovy `unit`.
--- @param unit integer
--- @return LuaPlayer[]
function M.viewers(unit)
  local out = {}
  for index, st in pairs(all()) do
    if st.unit == unit then
      local player = game.get_player(index)
      if player then out[#out + 1] = player end
    end
  end
  return out
end

--- Obnoví všechna okna nad budovou (po akci jednoho hráče uvidí změnu i ostatní).
function M.refresh_unit(unit)
  for _, player in ipairs(M.viewers(unit)) do M.refresh(player) end
end

return M
