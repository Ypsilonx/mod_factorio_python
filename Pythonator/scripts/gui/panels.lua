--- Panely okna: vstupy R | G, výstupy (skutečný stav drátu), globální proměnné, stav prvků knihovny
--- a log print(). Obnovují se jen při otevřeném okně (events.on_refresh) a prvky se mění na místě.
local R = require("scripts.lang.builtins")
local elements = require("scripts.lang.elements")
local io = require("scripts.io")
local resolver = require("scripts.resolver")

local M = {}

-- Laditelné limity zobrazení.
--- Nejvíc ikon signálů v jedné mřížce (zbytek jako „+N“).
M.PANEL_MAX_ROWS = 60
--- Nejdelší zobrazený repr globální proměnné (znaky).
M.REPR_MAX = 60
--- Nejvíc zobrazených globálů.
M.GLOBALS_MAX = 40
--- Sloupců v mřížce signálů.
M.SIGNAL_COLUMNS = 6

--- Typ SignalID → předpona sprite cesty.
local SPRITE_TYPE = { item = "item", fluid = "fluid", virtual = "virtual-signal", recipe = "recipe", entity = "entity",
  ["space-location"] = "space-location", ["asteroid-chunk"] = "asteroid-chunk", quality = "quality" }

--- Řádky globálů {jméno, repr} seřazené podle jména, bez stavu prvků knihovny.
--- @param G table globály programu
--- @return table[]
function M.rows_globals(G)
  local names = {}
  for name in pairs(G) do
    if name ~= elements.STATE then names[#names + 1] = name end
  end
  table.sort(names, function(a, b) return R.strcmp(a, b) < 0 end)
  local rows = {}
  for i = 1, math.min(#names, M.GLOBALS_MAX) do
    local ok, text = pcall(R.repr, G[names[i]])
    if not ok then text = "?" end
    if #text > M.REPR_MAX then text = text:sub(1, M.REPR_MAX - 3) .. "…" end
    rows[i] = { names[i], text }
  end
  return rows
end

--- Řádky mřížky signálů z dvojic {klíč, hodnota}.
--- @param ps table[] dvojice v pořadí zobrazení
--- @param max integer|nil nejvíc řádků (výchozí PANEL_MAX_ROWS)
--- @return table[] rows {sprite, number, tooltip}
--- @return integer rest kolik se nevešlo
function M.rows_signals(ps, max)
  max = max or M.PANEL_MAX_ROWS
  local res = resolver.get()
  local rows = {}
  for i = 1, math.min(#ps, max) do
    local key, value = ps[i][1], ps[i][2]
    local sid = res:resolve(key)
    local sprite = sid and SPRITE_TYPE[sid.type] and (SPRITE_TYPE[sid.type] .. "/" .. sid.name) or "utility/questionmark"
    rows[i] = { sprite = sprite, number = value, tooltip = key .. " = " .. tostring(value) }
  end
  return rows, math.max(#ps - max, 0)
end

--- Krátký popis stavu prvku knihovny pro panel.
local SUMMARY = {
  latch = function(s) return R.repr(s.q == true) end,
  timer = function(s) return R.str(s.acc or 0) end,
  edge = function(s) return R.repr(s.prev == true) end,
  counter = function(s) return R.str(s.value or 0) end,
  delay = function(s) return R.str(s.n or 0) end,
  pid = function(s) return R.str(math.floor((s.integral or 0) * 1000 + 0.5) / 1000) end,
}

--- Řádky prvků knihovny {jméno, lokalizovaný popis} seřazené podle jména.
--- @param lib table|nil G["#lib"]
function M.rows_elements(lib)
  local names = {}
  for name in pairs(lib or {}) do names[#names + 1] = name end
  table.sort(names, function(a, b) return R.strcmp(a, b) < 0 end)
  local rows = {}
  for i = 1, math.min(#names, M.GLOBALS_MAX) do
    local s = lib[names[i]]
    rows[i] = { names[i], { "pyntr-gui.element-" .. s.kind, SUMMARY[s.kind](s) } }
  end
  return rows
end

--- Nadpis sekce panelu.
local function heading(parent, caption)
  parent.add({ type = "label", caption = caption, style = "caption_label" })
end

--- Mřížka signálů s popiskem drátu.
local function signal_grid(parent, name, caption)
  local flow = parent.add({ type = "flow", direction = "horizontal" })
  flow.add({ type = "label", caption = caption })
  return parent.add({ type = "table", name = name, column_count = M.SIGNAL_COLUMNS, style = "filter_slot_table" })
end

--- Postaví panely do bočního sloupce (`side`) a log pod editor (`left`).
--- @param refs table odkazy okna (doplní in_red, in_green, out_red, out_green, globals, lib, log, log_pane, log_toggle)
function M.build(left, side, refs)
  local pane = side.add({ type = "scroll-pane", name = "pyntr_panels", style = "pyntr_panels_scroll",
                          horizontal_scroll_policy = "never" })
  local inputs = pane.add({ type = "frame", name = "pyntr_inputs", style = "inside_shallow_frame_with_padding",
                            direction = "vertical" })
  heading(inputs, { "pyntr-gui.inputs" })
  refs.in_red = signal_grid(inputs, "pyntr_in_red", { "pyntr-gui.wire-red" })
  refs.in_green = signal_grid(inputs, "pyntr_in_green", { "pyntr-gui.wire-green" })
  local outputs = pane.add({ type = "frame", name = "pyntr_outputs", style = "inside_shallow_frame_with_padding",
                             direction = "vertical" })
  heading(outputs, { "pyntr-gui.outputs" })
  refs.out_red = signal_grid(outputs, "pyntr_out_red", { "pyntr-gui.wire-red" })
  refs.out_green = signal_grid(outputs, "pyntr_out_green", { "pyntr-gui.wire-green" })
  local vars = pane.add({ type = "frame", name = "pyntr_vars", style = "inside_shallow_frame_with_padding",
                          direction = "vertical" })
  heading(vars, { "pyntr-gui.globals" })
  refs.globals = vars.add({ type = "table", name = "pyntr_globals", column_count = 2 })
  heading(vars, { "pyntr-gui.elements" })
  refs.lib = vars.add({ type = "table", name = "pyntr_lib", column_count = 2 })

  refs.log_toggle = refs.toolbar.add({ type = "button", name = "pyntr_log_toggle", caption = { "pyntr-gui.log" },
                                       tooltip = { "pyntr-gui.tooltip-log" }, tags = { pyntr_action = "toggle_log" } })
  refs.log_pane = left.add({ type = "scroll-pane", name = "pyntr_log_pane", style = "pyntr_log_scroll" })
  refs.log_pane.visible = false
  refs.log = refs.log_pane.add({ type = "flow", name = "pyntr_log", direction = "vertical" })
  refs.log.style.vertical_spacing = 0
end

--- Přizpůsobí počet dětí `parent` na n: chybějící přidá funkcí add(parent), přebytečné zničí.
local function fit(parent, n, add)
  local children = parent.children
  for _ = #children + 1, n do add(parent) end
  children = parent.children
  for i = #children, n + 1, -1 do children[i].destroy() end
  return parent.children
end

--- Naplní mřížku signálů (na místě).
local function fill_signals(grid, ps)
  local rows, rest = M.rows_signals(ps)
  local n = #rows + (rest > 0 and 1 or 0)
  local cells = fit(grid, n, function(p) p.add({ type = "sprite-button", style = "slot_button" }) end)
  for i, row in ipairs(rows) do
    local c = cells[i]
    c.sprite, c.number, c.tooltip = row.sprite, row.number, row.tooltip
  end
  if rest > 0 then
    local c = cells[n]
    c.sprite, c.number, c.tooltip = "utility/questionmark", rest, { "pyntr-gui.more-signals", rest }
  end
end

--- Naplní dvousloupcovou tabulku řádků {levý, pravý} (na místě).
local function fill_table(tbl, rows)
  local cells = fit(tbl, #rows * 2, function(p) p.add({ type = "label" }) end)
  for i, row in ipairs(rows) do
    cells[2 * i - 1].caption = row[1]
    cells[2 * i].caption = row[2]
  end
end

--- Dvojice {klíč, hodnota} mapy seřazené podle klíče.
local function sorted_pairs(map)
  local ps = {}
  for k, v in pairs(map or {}) do ps[#ps + 1] = { k, v } end
  table.sort(ps, function(a, b) return R.strcmp(a[1], b[1]) < 0 end)
  return ps
end

--- Signály na vstupním drátu entity (čtení jen pro otevřené okno, bez sdílení s programem).
local function input_pairs(entity, wire)
  if not entity.valid then return {} end
  local source = io.reader_source(entity, { wire }, resolver.get())
  source.reset(nil)
  return source.all()
end

--- Obnoví obsah panelů podle kontroléru.
--- @param refs table odkazy okna
--- @param ctl table kontrolér
function M.refresh(refs, ctl)
  local W = defines.wire_connector_id
  fill_signals(refs.in_red, input_pairs(ctl.entity, W.combinator_input_red))
  fill_signals(refs.in_green, input_pairs(ctl.entity, W.combinator_input_green))
  -- skutečně odeslaný stav drátu (po chybě uprostřed loop() se liší od ctl.out)
  local wires = ctl.wires or {}
  fill_signals(refs.out_red, sorted_pairs(wires.red and wires.red.sent))
  fill_signals(refs.out_green, sorted_pairs(wires.green and wires.green.sent))
  fill_table(refs.globals, M.rows_globals(ctl.globals))
  fill_table(refs.lib, M.rows_elements(ctl.globals[elements.STATE]))
  if refs.log_pane.visible then
    local lines = fit(refs.log, #ctl.prints, function(p) p.add({ type = "label", style = "pyntr_log_line" }) end)
    for i, line in ipairs(ctl.prints) do lines[i].caption = line end
  end
end

return M
