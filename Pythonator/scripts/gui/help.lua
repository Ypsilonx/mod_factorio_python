--- Okno nápovědy (tlačítko ? v liště): karty Základy, Signály, Jazyk, Knihovna a Příklady. Texty jsou
--- v locale ([pyntr-gui] help-*), kód příkladů je tady (není překládaný; test ověří, že se každý přeloží).
--- Okno se neotevírá jako player.opened, aby hlavní okno zůstalo otevřené vedle něj.
local M = {}

local WINDOW = "pyntr_help"
--- Šířka textu nápovědy (px). Laditelné.
M.TEXT_WIDTH = 620
--- Výška obsahu karet (px). Laditelné.
M.HEIGHT = 560

--- Textové karty: id → klíče locale help-<id>-title a help-<id>-text.
M.SECTIONS = { "basics", "signals", "language", "library" }

--- Příklady: id → klíče help-example-<id>-title a -desc; kód se vkládá do editoru.
M.EXAMPLES = {
  {
    id = "hysteresis",
    code = table.concat({
      "def loop():",
      "    gas = inp[\"petroleum-gas\"]",
      "    on = latch(\"pump\", gas < 1000, gas > 20000)",
      "    out[\"signal-S\"] = 1 if on else 0",
    }, "\n"),
  },
  {
    id = "sequence",
    code = table.concat({
      "step = 0",
      "",
      "def loop():",
      "    global step",
      "    if timer(\"step\", 60):",
      "        step = (step + 1) % 4",
      "    out.clear()",
      "    out[\"signal-\" + \"ABSU\"[step]] = 1",
    }, "\n"),
  },
  {
    id = "recipe",
    code = table.concat({
      "def loop():",
      "    out.clear()",
      "    if inp[\"iron-gear-wheel\"] < 200:",
      "        out[\"iron-gear-wheel\"] = 1",
    }, "\n"),
  },
  {
    id = "each",
    code = table.concat({
      "config(outputs=\"clear\")",
      "",
      "def loop():",
      "    out.set(inp.where(\">\", 1000).each(\"-\", 1000))",
      "    out[\"signal-A\"] = inp.where(\">\", 1000).count()",
    }, "\n"),
  },
  {
    id = "pid",
    code = table.concat({
      "def loop():",
      "    u = pid(\"level\", 5000, inp[\"petroleum-gas\"], 0.02, 0.001, 0, 0, 100)",
      "    out[\"signal-P\"] = u",
    }, "\n"),
  },
}

--- Otevřené okno nápovědy hráče, nebo nil.
local function frame_of(player)
  local f = player.gui.screen[WINDOW]
  if f and f.valid then return f end
end

--- Víceřádkový popisek s pevnou šířkou.
local function text(parent, caption, style)
  local label = parent.add({ type = "label", caption = caption, style = style })
  label.style.single_line = false
  label.style.maximal_width = M.TEXT_WIDTH
  return label
end

--- Obsah karty: posuvník s vlastním obsahem.
local function tab_content(tabs, caption)
  local tab = tabs.add({ type = "tab", caption = caption })
  local pane = tabs.add({ type = "scroll-pane", horizontal_scroll_policy = "never" })
  pane.style.height = M.HEIGHT
  pane.style.padding = 8
  tabs.add_tab(tab, pane)
  return pane
end

--- Otevře nápovědu (je-li otevřená, jen ji přenese dopředu).
--- @param player LuaPlayer
function M.open(player)
  local existing = frame_of(player)
  if existing then
    existing.bring_to_front()
    return
  end
  local frame = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical" })
  local bar = frame.add({ type = "flow", name = "pyntr_help_titlebar", direction = "horizontal" })
  bar.drag_target = frame
  bar.style.horizontal_spacing = 8
  bar.add({ type = "label", caption = { "pyntr-gui.help-title" }, style = "frame_title", ignored_by_interaction = true })
  local drag = bar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  drag.style.height = 24
  drag.style.horizontally_stretchable = true
  bar.add({ type = "sprite-button", name = "pyntr_help_close", sprite = "utility/close", style = "frame_action_button",
            tags = { pyntr_action = "help_close" } })

  local tabs = frame.add({ type = "tabbed-pane", name = "pyntr_help_tabs" })
  for _, id in ipairs(M.SECTIONS) do
    local pane = tab_content(tabs, { "pyntr-gui.help-" .. id .. "-title" })
    text(pane, { "pyntr-gui.help-" .. id .. "-text" })
  end
  local pane = tab_content(tabs, { "pyntr-gui.help-examples-title" })
  text(pane, { "pyntr-gui.help-examples-text" })
  for i, ex in ipairs(M.EXAMPLES) do
    pane.add({ type = "line" })
    text(pane, { "pyntr-gui.help-example-" .. ex.id .. "-title" }, "caption_label")
    text(pane, { "pyntr-gui.help-example-" .. ex.id .. "-desc" })
    local code = pane.add({ type = "frame", style = "inside_deep_frame", direction = "vertical" })
    code.style.padding = 6
    text(code, ex.code, "pyntr_log_line")
    pane.add({ type = "button", caption = { "pyntr-gui.help-insert" }, tooltip = { "pyntr-gui.tooltip-help-insert" },
               tags = { pyntr_action = "insert_example", example = i } })
  end
  frame.force_auto_center()
end

--- Zavře nápovědu hráče.
function M.close(player)
  local f = frame_of(player)
  if f then f.destroy() end
end

--- Tlačítka „Vložit do editoru“ v pořadí příkladů (prázdné, není-li nápověda otevřená).
--- @return LuaGuiElement[]
function M.example_buttons(player)
  local out = {}
  local function walk(e)
    if e.tags and e.tags.pyntr_action == "insert_example" then out[#out + 1] = e end
    for _, c in ipairs(e.children) do walk(c) end
  end
  local f = frame_of(player)
  if f then walk(f) end
  return out
end

return M
