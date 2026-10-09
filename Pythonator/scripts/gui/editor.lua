--- Editor kódu v okně: text-box bez vlastního posuvníku ve vnějším scroll-pane a vedle něj sloupec čísel
--- řádků. Box roste s textem (výška = řádky × LINE_HEIGHT + rezerva), takže vnější scroll-pane posouvá
--- text i čísla řádků současně (ověřeno spikem, docs/development.md → Ověřená rizika).
--- API nezná pozici kurzoru: pohled se při psaní posune na řádek, kde se text změnil.
local M = {}

-- Laditelné rozměry editoru (px). Řádek musí odpovídat fontu pyntr-mono (prototypes/gui.lua).
--- Šířka textového pole.
M.WIDTH = 640
--- Viditelná výška editoru (scroll-pane).
M.VIEW_HEIGHT = 520
--- Výška jednoho řádku textu.
M.LINE_HEIGHT = 20
--- Nejmenší počet řádků boxu. Výběr ikon kreslí hra do pravého dolního rohu boxu – box vyšší než pohled
--- (VIEW_HEIGHT) by ho schoval pod spodní okraj, proto je výchozí box malý a roste až s textem.
M.MIN_LINES = 10
--- Rezerva výšky boxu pod posledním řádkem (vnitřní okraje text-boxu).
M.HEIGHT_RESERVE = 12
--- Šířka sloupce čísel řádků.
M.GUTTER_WIDTH = 36
--- Místo pro svislý posuvník a vnitřní okraje scroll-pane (hra je do šířky obsahu nepočítá).
M.SCROLLBAR_WIDTH = 24

--- Celková šířka editoru (scroll-pane): čísla řádků + text + posuvník s okraji.
--- @return integer
function M.outer_width()
  return M.GUTTER_WIDTH + M.WIDTH + M.SCROLLBAR_WIDTH
end

--- Barvy čísel řádků: běžné a řádek s chybou.
M.COLOR_LINE = { 0.55, 0.55, 0.55 }
M.COLOR_ERROR = { 1, 0.3, 0.25 }

--- Počet řádků textu.
--- @param text string
--- @return integer
function M.count_lines(text)
  local n = 1
  for _ in text:gmatch("\n") do n = n + 1 end
  return n
end

--- Číslo řádku (od 1), na kterém se texty poprvé liší; nil, pokud jsou stejné.
--- @param old string
--- @param new string
--- @return integer|nil
function M.changed_line(old, new)
  if old == new then return nil end
  local i, n = 1, math.min(#old, #new)
  while i <= n and old:byte(i) == new:byte(i) do i = i + 1 end
  return M.count_lines(new:sub(1, i - 1))
end

--- Postaví editor do `parent`.
--- @param parent LuaGuiElement
--- @return table refs { scroll, gutter, code }
function M.build(parent)
  local scroll = parent.add({ type = "scroll-pane", name = "pyntr_editor_scroll", style = "pyntr_editor_scroll",
                              horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" })
  scroll.style.height = M.VIEW_HEIGHT
  scroll.style.width = M.outer_width()
  local row = scroll.add({ type = "flow", name = "pyntr_editor_row", direction = "horizontal" })
  row.style.horizontal_spacing = 0
  local gutter = row.add({ type = "flow", name = "pyntr_gutter", direction = "vertical" })
  gutter.style.vertical_spacing = 0
  gutter.style.width = M.GUTTER_WIDTH
  gutter.style.top_padding = 4
  local code = row.add({ type = "text-box", name = "pyntr_code", style = "pyntr_code_textbox", icon_selector = true,
                         tags = { pyntr_action = "code" } })
  code.style.width = M.WIDTH
  code.word_wrap = false
  return { scroll = scroll, gutter = gutter, code = code }
end

--- Nastaví počet čísel řádků a výšku boxu podle počtu řádků textu.
--- @param refs table z build
--- @param lines integer
function M.resize(refs, lines)
  local shown = math.max(lines, M.MIN_LINES)
  local gutter = refs.gutter
  local have = #gutter.children
  for i = have + 1, shown do
    local label = gutter.add({ type = "label", caption = tostring(i), style = "pyntr_line_number" })
    label.style.font_color = M.COLOR_LINE
  end
  for i = have, shown + 1, -1 do gutter.children[i].destroy() end
  refs.code.style.height = shown * M.LINE_HEIGHT + M.HEIGHT_RESERVE
  refs.lines = shown
end

--- Zvýrazní číslo řádku s chybou (nil = žádný); předchozí zvýraznění zruší.
--- @param refs table z build
--- @param line integer|nil
--- @param previous integer|nil dříve zvýrazněný řádek
function M.mark_error(refs, line, previous)
  local labels = refs.gutter.children
  if previous and labels[previous] then labels[previous].style.font_color = M.COLOR_LINE end
  if line and labels[line] then labels[line].style.font_color = M.COLOR_ERROR end
end

--- Posune pohled na číslo řádku `line`.
function M.scroll_to(refs, line)
  local label = refs.gutter.children[line]
  if label then refs.scroll.scroll_to_element(label) end
end

--- Nastaví text editoru (a velikost), bez posunu pohledu.
--- @param refs table z build
--- @param text string
function M.set_text(refs, text)
  if refs.code.text ~= text then refs.code.text = text end
  M.resize(refs, M.count_lines(text))
end

--- Po psaní hráče: přizpůsobí velikost a posune pohled na změněný řádek.
--- @param refs table z build
--- @param old string text před změnou
--- @param new string text po změně
function M.follow(refs, old, new)
  M.resize(refs, M.count_lines(new))
  local line = M.changed_line(old, new)
  if line then M.scroll_to(refs, line) end
end

return M
