--- Panely okna: vstupy R | G, výstupy (skutečný stav drátu), globální proměnné, stav prvků knihovny
--- a log print(). Obnovují se jen při otevřeném okně (events.on_refresh) a prvky se mění na místě.
local R = require("scripts.lang.builtins")
local elements = require("scripts.lang.elements")
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
    local ok, text = pcall(M.short_repr, G[names[i]], M.REPR_MAX)
    rows[i] = { names[i], ok and text or "?" }
  end
  return rows
end

--- repr hodnoty zkrácený na `max` znaků („…“ na konci). Kontejnery se procházejí jen do vyčerpání délky –
--- velký globál (tisíce prvků) se při každé obnově okna nepřevádí celý.
--- @param v any hodnota jazyka
--- @param max integer
--- @return string
function M.short_repr(v, max)
  local parts, len = {}, 0
  local full = true

  --- Připojí text; vrátí false, jakmile je délka vyčerpaná.
  local function put(s)
    parts[#parts + 1] = s
    len = len + #s
    if len > max then full = false end
    return full
  end

  local walk
  --- Projde hodnotu; false = konec (délka vyčerpaná).
  walk = function(x)
    local mt = type(x) == "table" and getmetatable(x)
    if mt == R.ListMT or mt == R.TupleMT then
      if not put(mt == R.ListMT and "[" or "(") then return false end
      for i = 1, x.n do
        if i > 1 and not put(", ") then return false end
        if not walk(x[i]) then return false end
      end
      return put((mt == R.TupleMT and x.n == 1) and ",)" or (mt == R.ListMT and "]" or ")"))
    elseif mt == R.DictMT then
      if not put("{") then return false end
      for i, k in ipairs(x.keys) do
        if i > 1 and not put(", ") then return false end
        if not (walk(k) and put(": ") and walk(R.dict_get(x, k))) then return false end
      end
      return put("}")
    end
    return put(R.repr(x))
  end

  walk(v)
  local text = table.concat(parts)
  if full and #text <= max then return text end
  return text:sub(1, max - 3) .. "…"
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
    local tooltip = key .. " = " .. tostring(value)
    -- nula na síti neexistuje: v panelu je jen výslovně zapsaný výstup, který na drát nejde
    if value == 0 then tooltip = { "", tooltip, "\n", { "pyntr-gui.output-zero" } } end
    rows[i] = { sprite = sprite, number = value, tooltip = tooltip }
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

--- Naplní mřížku signálů (na místě). Do buňky se zapisuje jen při změně: `shown` (obyčejná tabulka ve
--- stavu okna) si pamatuje zobrazené ikony – zápis vlastnosti prvku je volání API.
--- @param grid LuaGuiElement
--- @param ps table[] dvojice {klíč, hodnota} (už oříznuté nebo celé)
--- @param total integer|nil celkový počet signálů (výchozí #ps)
--- @param shown table paměť zobrazených buněk
local function fill_signals(grid, ps, total, shown)
  local rows, rest = M.rows_signals(ps)
  rest = math.max((total or #ps) - #rows, rest)
  local n = #rows + (rest > 0 and 1 or 0)
  local before = #grid.children
  local cells = fit(grid, n, function(p) p.add({ type = "sprite-button", style = "slot_button" }) end)
  -- nové buňky nic nezobrazují, zrušené se zapomenou
  for i = before + 1, n do shown[i] = nil end
  for i = n + 1, #shown do shown[i] = nil end
  for i, row in ipairs(rows) do
    local id = row.sprite .. "=" .. tostring(row.number)
    if shown[i] ~= id then
      local c = cells[i]
      c.sprite, c.number, c.tooltip = row.sprite, row.number, row.tooltip
      shown[i] = id
    end
  end
  if rest > 0 and shown[n] ~= "+" .. rest then
    local c = cells[n]
    c.sprite, c.number, c.tooltip = "utility/questionmark", rest, { "pyntr-gui.more-signals", rest }
    shown[n] = "+" .. rest
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

--- Dvojice {klíč, hodnota} mapy seřazené podle klíče; klíče z `zero` (klíč → true) přibudou s hodnotou 0.
local function sorted_pairs(map, zero)
  local ps = {}
  for k, v in pairs(map or {}) do ps[#ps + 1] = { k, v } end
  for k in pairs(zero or {}) do ps[#ps + 1] = { k, 0 } end
  table.sort(ps, function(a, b) return R.strcmp(a[1], b[1]) < 0 end)
  return ps
end

--- Signály na vstupním drátu entity v pořadí hry (deterministické), jen prvních PANEL_MAX_ROWS převedených
--- na klíče – celá sada (stovky signálů) se kvůli zobrazení neřadí ani nepřevádí.
--- @return table[] dvojice {klíč, hodnota}
--- @return integer celkový počet signálů na drátu
local function input_pairs(entity, wire)
  if not entity.valid then return {}, 0 end
  local signals = entity.get_signals(wire)
  if not signals then return {}, 0 end
  local res = resolver.get()
  local ps = {}
  for i = 1, math.min(#signals, M.PANEL_MAX_ROWS) do
    ps[i] = { res:canonical(signals[i].signal), signals[i].count }
  end
  return ps, #signals
end

--- Paměť zobrazených buněk mřížky `name` ve stavu okna.
local function shown_of(refs, name)
  refs.shown = refs.shown or {}
  refs.shown[name] = refs.shown[name] or {}
  return refs.shown[name]
end

--- Obnoví obsah panelů podle kontroléru.
--- @param refs table odkazy okna
--- @param ctl table kontrolér
function M.refresh(refs, ctl)
  local W = defines.wire_connector_id
  local ps, total = input_pairs(ctl.entity, W.combinator_input_red)
  fill_signals(refs.in_red, ps, total, shown_of(refs, "in_red"))
  ps, total = input_pairs(ctl.entity, W.combinator_input_green)
  fill_signals(refs.in_green, ps, total, shown_of(refs, "in_green"))
  -- skutečně odeslaný stav drátu (po chybě uprostřed loop() se liší od ctl.out) a výslovně zapsané nuly
  local wires = ctl.wires or {}
  local red, green = wires.red or {}, wires.green or {}
  fill_signals(refs.out_red, sorted_pairs(red.sent, red.zero), nil, shown_of(refs, "out_red"))
  fill_signals(refs.out_green, sorted_pairs(green.sent, green.zero), nil, shown_of(refs, "out_green"))
  fill_table(refs.globals, M.rows_globals(ctl.globals))
  fill_table(refs.lib, M.rows_elements(ctl.globals[elements.STATE]))
  if refs.log_pane.visible then
    local n = #ctl.prints
    local lines = fit(refs.log, math.max(n, 1), function(p) p.add({ type = "label", style = "pyntr_log_line" }) end)
    if n == 0 then lines[1].caption = { "pyntr-gui.log-empty" } end
    for i, line in ipairs(ctl.prints) do lines[i].caption = line end
  end
end

return M
