--- Obsluha událostí GUI: otevření budovy, zavření okna, kliknutí a psaní v editoru. Prvky se rozlišují
--- podle tagu `pyntr_action` (události GUI dostávají všechny mody, tag mají jen naše prvky).
local controller = require("scripts.controller")
local lifecycle = require("scripts.lifecycle")
local actions = require("scripts.actions")
local window = require("scripts.gui.window")
local editor = require("scripts.gui.editor")
local help = require("scripts.gui.help")

local M = {}

--- Obsluha kliknutí podle tagu: function(player, st, ctl, element).
local CLICK = {
  close = function(player) window.close(player) end,
  play = function(_, st, ctl) actions.play(ctl, st.refs.code.text) end,
  pause = function(_, _, ctl) actions.pause(ctl) end,
  reset = function(_, _, ctl) actions.reset(ctl) end,
  step = function(_, _, ctl) actions.step(ctl, game.tick) end,
  toggle_log = function(player, st)
    st.refs.log_pane.visible = not st.refs.log_pane.visible
    window.refresh_live(player)
  end,
  goto_error = function(_, st)
    if st.error_line then editor.scroll_to(st.refs, st.error_line) end
  end,
}

--- Vložení příkladu z nápovědy do editoru (nahradí text; jen když jde psát).
function CLICK.insert_example(_, st, ctl, element)
  local ex = help.EXAMPLES[element.tags.example]
  if not (ctl and ex and actions.view(ctl).can.edit) then return end
  editor.set_text(st.refs, ex.code)
  st.text = ex.code
  actions.set_draft(ctl, ex.code)
  window.refresh_unit(ctl.unit)
end

--- Kliknutí, která nepotřebují hlavní okno (nápověda): function(player).
local PLAYER_CLICK = {
  help = function(player) help.open(player) end,
  help_close = function(player) help.close(player) end,
}

--- Akce, po kterých se obnoví všechna okna nad budovou (změnily stav kontroléru).
local CHANGES_STATE = { play = true, pause = true, reset = true, step = true }
M.CLICK = CLICK

--- Stav okna hráče z události a jeho kontrolér; nil, pokud událost nepatří našemu oknu.
local function context(event)
  local element = event.element
  if not (element and element.valid and element.tags and element.tags.pyntr_action) then return end
  local player = game.get_player(event.player_index)
  local st = player and window.state(player)
  if not st then return end
  return player, st, controller.get(st.unit), element
end

--- Otevření entity: místo vanilla okna kombinátoru naše okno.
function M.on_gui_opened(event)
  if not lifecycle.is_ours(event.entity) then return end
  local ctl = controller.get(event.entity.unit_number)
  local player = game.get_player(event.player_index)
  if not player then return end
  if not ctl then
    -- budova bez stavu (nemělo by nastat): aspoň nenechat otevřené vanilla okno kombinátoru
    player.opened = nil
    return
  end
  window.open(player, ctl)
end

--- Zavření okna (E, Esc): jen naše okno.
function M.on_gui_closed(event)
  local player = game.get_player(event.player_index)
  local refs = player and window.get(player)
  if refs and event.element == refs.frame then window.close(player) end
end

--- Kliknutí na prvek s tagem pyntr_action.
function M.on_gui_click(event)
  local el = event.element
  local simple = el and el.valid and el.tags and PLAYER_CLICK[el.tags.pyntr_action]
  if simple then
    local p = game.get_player(event.player_index)
    if p then simple(p) end
    return
  end
  local player, st, ctl, element = context(event)
  if not player then return end
  local action = element.tags.pyntr_action
  local handler = CLICK[action]
  if not handler or (CHANGES_STATE[action] and not ctl) then return end
  handler(player, st, ctl, element)
  if CHANGES_STATE[action] then window.refresh_unit(ctl.unit) end
end

--- Psaní v editoru: uloží draft, upraví čísla řádků a posune pohled; ostatním oknům nad budovou obnoví text.
function M.on_gui_text_changed(event)
  local player, st, ctl, element = context(event)
  if not (player and ctl) or element.tags.pyntr_action ~= "code" then return end
  local new = element.text
  editor.follow(st.refs, st.text or "", new)
  st.text = new
  actions.set_draft(ctl, new)
  -- vlastní okno: jen tlačítka a stav (Play se změněným textem), text boxu nepřepisovat
  window.refresh_status(player)
  for _, other in ipairs(window.viewers(ctl.unit)) do
    if other.index ~= player.index then window.refresh(other) end
  end
end

--- Jak často se otevřená okna obnovují (ticky). Laditelné.
M.REFRESH_TICKS = 10

--- Periodická obnova otevřených oken (on_nth_tick). Bez otevřených oken hned skončí.
function M.on_refresh()
  local open = storage.gui
  if not (open and next(open)) then return end
  -- kopie seznamu: obnova může okno zavřít (zaniklá budova) a měnit tabulku během průchodu
  local indices = {}
  for index in pairs(open) do indices[#indices + 1] = index end
  for _, index in ipairs(indices) do
    local player = game.get_player(index)
    if player then
      window.refresh_live(player)
    else
      open[index] = nil
    end
  end
end

--- Odchod hráče ze hry: okno i nápověda se zavřou (po návratu je otevře znovu).
function M.on_player_left_game(event)
  local player = game.get_player(event.player_index)
  if player then
    window.close(player)
    help.close(player)
  end
end

--- Odebrání hráče: jeho prvky zanikly s ním, uklidí se jen stav.
function M.on_player_removed(event)
  window.all()[event.player_index] = nil
end

--- Změna modů nebo verze: prvky oken nemusí odpovídat nové verzi – zavřít všechna okna, i zbytky
--- s prefixem bez záznamu ve storage, a stav oken vynulovat.
function M.on_configuration_changed()
  for _, player in pairs(game.players) do
    local ours = {}
    for _, child in ipairs(player.gui.screen.children) do
      if child.valid and child.name and child.name:find("^pyntr_") then ours[#ours + 1] = child end
    end
    for _, child in ipairs(ours) do child.destroy() end
  end
  storage.gui = {}
end

--- Zbourání budovy: okna nad ní se zavřou.
lifecycle.on_removed[#lifecycle.on_removed + 1] = function(unit)
  for _, player in ipairs(window.viewers(unit)) do window.close(player) end
end

return M
