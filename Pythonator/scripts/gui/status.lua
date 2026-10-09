--- Lišta tlačítek (▶ ⏸ ⟳ ⏭), panel stavu (stav, tick, cena posledního běhu) a pruh chyby s řádkem.
--- Co je povolené, rozhoduje actions.view – tady se to jen vykreslí.
local indicator = require("scripts.indicator")
local editor = require("scripts.gui.editor")

local M = {}

--- Barva štítku stavu (shodná se stavovou LED; bez kódu a bez proudu šedá).
local GREY = { 0.6, 0.6, 0.6 }
M.STATE_COLORS = {
  running = indicator.COLORS.run, paused = indicator.COLORS.pause, error = indicator.COLORS.error,
  off = GREY, no_power = GREY,
}

--- Zaplnění rozpočtu watchdogu, od kterého je pruh ceny žlutý / červený (podíl limitu). Laditelné.
M.COST_WARN, M.COST_HIGH = 0.5, 0.9

--- Tlačítka lišty: jméno v refs, sprite, tag akce.
local BUTTONS = {
  { "play", "utility/play" },
  { "pause", "utility/pause" },
  { "reset", "utility/reset" },
  { "step", "utility/tick_once" },
}

--- Postaví lištu tlačítek a pruh chyby pod editor (`left`) a panel stavu do bočního sloupce (`side`).
--- @param refs table odkazy okna (doplní se play, pause, reset, step, state, tick, cost, cost_bar, error_*)
function M.build(left, side, refs)
  local bar = left.add({ type = "frame", name = "pyntr_error_bar", style = "pyntr_error_bar",
                         direction = "horizontal" })
  bar.style.horizontally_stretchable = true
  refs.error_bar = bar
  refs.error_label = bar.add({ type = "label", name = "pyntr_error_label", tags = { pyntr_action = "goto_error" } })
  refs.error_label.style.single_line = false
  refs.error_label.style.maximal_width = editor.WIDTH + editor.GUTTER_WIDTH

  local toolbar = left.add({ type = "flow", name = "pyntr_toolbar", direction = "horizontal" })
  for _, b in ipairs(BUTTONS) do
    refs[b[1]] = toolbar.add({ type = "sprite-button", name = "pyntr_btn_" .. b[1], sprite = b[2],
                               style = "tool_button", tooltip = { "pyntr-gui.tooltip-" .. b[1] },
                               tags = { pyntr_action = b[1] } })
  end
  refs.help = toolbar.add({ type = "sprite-button", name = "pyntr_btn_help", sprite = "utility/questionmark",
                            style = "tool_button", tooltip = { "pyntr-gui.tooltip-help" }, tags = { pyntr_action = "help" } })
  refs.toolbar = toolbar

  local panel = side.add({ type = "frame", name = "pyntr_status", style = "inside_shallow_frame_with_padding",
                           direction = "vertical" })
  refs.state = panel.add({ type = "label", name = "pyntr_state", style = "heading_2_label" })
  refs.tick = panel.add({ type = "label", name = "pyntr_tick" })
  refs.cost = panel.add({ type = "label", name = "pyntr_cost", tooltip = { "pyntr-gui.tooltip-cost" } })
  refs.cost_bar = panel.add({ type = "progressbar", name = "pyntr_cost_bar", value = 0 })
  refs.cost_bar.style.horizontally_stretchable = true
end

--- Text chyby: „Řádek N: zpráva“ (zpráva je lokalizovaný klíč chyby jazyka s argumenty).
--- @param err table {line, key, args}
--- @param compile boolean chyba překladu nového kódu (starý program případně běží dál)
local function error_caption(err, compile)
  local msg = { err.key }
  for _, a in ipairs(err.args or {}) do msg[#msg + 1] = a end
  local where = err.line and { "pyntr-gui.error-line", err.line } or ""
  return { "", where, " ", msg, compile and { "", " ", { "pyntr-gui.compile-error-note" } } or "" }
end

--- Chyba k zobrazení: chyba překladu má přednost (týká se textu v editoru), jinak chyba běhu.
--- @return table|nil err, boolean compile
function M.shown_error(view)
  if view.compile_error then return view.compile_error, true end
  return view.error, false
end

--- Vykreslí stav podle pohledu z actions.view.
--- @param refs table odkazy okna
--- @param view table actions.view(ctl)
--- @param st table stav okna (pamatuje si zvýrazněný řádek v `error_line`)
function M.update(refs, view, st)
  for _, b in ipairs(BUTTONS) do refs[b[1]].enabled = view.can[b[1]] end
  refs.state.caption = { "pyntr-gui.state-" .. view.state }
  refs.state.style.font_color = M.STATE_COLORS[view.state]
  refs.tick.caption = { "pyntr-gui.tick", view.tick }
  refs.cost.caption = { "pyntr-gui.cost", view.used, view.limit }
  local fill = view.limit > 0 and math.min(view.used / view.limit, 1) or 0
  refs.cost_bar.value = fill
  refs.cost_bar.style.color = fill >= M.COST_HIGH and indicator.COLORS.error
    or fill >= M.COST_WARN and indicator.COLORS.pause or indicator.COLORS.run

  local err, compile = M.shown_error(view)
  refs.error_bar.visible = err ~= nil
  if err then refs.error_label.caption = error_caption(err, compile) end
  -- přebarvit jen při změně řádku chyby nebo počtu řádků (nová čísla řádků mají výchozí barvu)
  local line = err and err.line or nil
  if line ~= st.error_line or refs.lines ~= st.marked_lines then
    editor.mark_error(refs, line, st.error_line)
    st.error_line, st.marked_lines = line, refs.lines
  end
end

return M
