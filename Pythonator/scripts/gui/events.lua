--- Obsluha událostí GUI: otevření budovy, zavření okna, kliknutí a psaní v editoru. Prvky se rozlišují
--- podle tagu `pyntr_action` (události GUI dostávají všechny mody, tag mají jen naše prvky).
local controller = require("scripts.controller")
local lifecycle = require("scripts.lifecycle")
local actions = require("scripts.actions")
local window = require("scripts.gui.window")
local editor = require("scripts.gui.editor")

local M = {}

--- Obsluha kliknutí podle tagu: function(player, st, ctl, element).
local CLICK = {
  close = function(player) window.close(player) end,
  play = function(_, st, ctl) actions.play(ctl, st.refs.code.text) end,
  pause = function(_, _, ctl) actions.pause(ctl) end,
  reset = function(_, _, ctl) actions.reset(ctl) end,
  step = function(_, _, ctl) actions.step(ctl, game.tick) end,
  goto_error = function(_, st)
    if st.error_line then editor.scroll_to(st.refs, st.error_line) end
  end,
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

--- Zbourání budovy: okna nad ní se zavřou.
lifecycle.on_removed[#lifecycle.on_removed + 1] = function(unit)
  for _, player in ipairs(window.viewers(unit)) do window.close(player) end
end

return M
