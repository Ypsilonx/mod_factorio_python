--- Šablony kódu pod editorem: vložení na místo posledního psaní a označení zástupného slova.
--- API text-boxu kurzor nezná (jen zápis select), proto se „kurzor“ odvozuje z rozdílu textů při psaní.
--- Pozice jsou v bajtech (počet bajtů před místem); pro select se převádějí na znaky.
local M = {}

--- Odsazení vnořeného bloku (mezery).
M.INDENT = "    "

--- Šířka popisku řádku lišty (px). Laditelné.
M.LABEL_WIDTH = 70

--- Řádky lišty: id řádku (popisek v locale [pyntr-gui] snippets-<id>) → id šablon v pořadí tlačítek.
M.ROWS = {
  { id = "code", snippets = { "loop", "if", "ifelse", "inp", "out", "print" } },
  { id = "lib", snippets = { "latch", "timer", "edge", "counter", "delay", "pid", "where", "each" } },
}

--- Šablony: id → kind, caption (popisek tlačítka – kód, nepřekládá se), code, select (zástupné slovo
--- k označení, první výskyt). kind "expr" = vloží se přímo na místo psaní, "stmt" = jako řádek(y) pod
--- aktuální řádek, s jeho odsazením. Zástupná slova velkými písmeny: nenahrazené ohlásí překladač.
--- Popis je v locale [pyntr-gui] snippet-<id>.
M.SNIPPETS = {
  { id = "loop", kind = "stmt", caption = "def loop", select = "pass",
    code = "def loop():\n    pass" },
  { id = "if", kind = "stmt", caption = "if", select = "SIGNAL",
    code = "if inp[\"SIGNAL\"] > NUMBER:\n    pass" },
  { id = "ifelse", kind = "stmt", caption = "if/else", select = "CONDITION",
    code = "if CONDITION:\n    pass\nelse:\n    pass" },
  { id = "inp", kind = "expr", caption = "inp[ ]", select = "SIGNAL",
    code = "inp[\"SIGNAL\"]" },
  { id = "out", kind = "stmt", caption = "out[ ] =", select = "SIGNAL",
    code = "out[\"SIGNAL\"] = VALUE" },
  { id = "print", kind = "stmt", caption = "print", select = "VALUE",
    code = "print(VALUE)" },
  { id = "latch", kind = "stmt", caption = "latch", select = "NAME",
    code = "on = latch(\"NAME\", SET_CONDITION, RESET_CONDITION)" },
  { id = "timer", kind = "stmt", caption = "timer", select = "NAME",
    code = "if timer(\"NAME\", TICKS):\n    pass" },
  { id = "edge", kind = "stmt", caption = "edge", select = "NAME",
    code = "change = edge(\"NAME\", CONDITION)" },
  { id = "counter", kind = "stmt", caption = "counter", select = "NAME",
    code = "n = counter(\"NAME\")" },
  { id = "delay", kind = "stmt", caption = "delay", select = "NAME",
    code = "old = delay(\"NAME\", VALUE, TICKS)" },
  { id = "pid", kind = "stmt", caption = "pid", select = "NAME",
    code = "u = pid(\"NAME\", SETPOINT, inp[\"SIGNAL\"], 0.02, 0.001, 0, 0, 100)" },
  { id = "where", kind = "expr", caption = ".where", select = "NUMBER",
    code = "inp.where(\">\", NUMBER)" },
  { id = "each", kind = "expr", caption = ".each", select = "NUMBER",
    code = "inp.each(\"*\", NUMBER)" },
}

local BY_ID = {}
for _, s in ipairs(M.SNIPPETS) do BY_ID[s.id] = s end

--- Šablona podle id, nebo nil.
--- @param id string
--- @return table|nil
function M.get(id)
  return BY_ID[id]
end

--- Je bajt pokračovacím bajtem UTF-8 (10xxxxxx)?
local function continuation(b)
  return b and b >= 0x80 and b < 0xC0
end

--- Místo psaní po změně textu: počet bajtů nového textu před koncem změněného úseku.
--- Společný začátek a konec obou textů se přeskočí; zbytek je to, co hráč napsal / smazal.
--- @param old string
--- @param new string
--- @return integer
function M.caret_after(old, new)
  local n = math.min(#old, #new)
  local p = 0
  while p < n and old:byte(p + 1) == new:byte(p + 1) do p = p + 1 end
  local s = 0
  while s < n - p and old:byte(#old - s) == new:byte(#new - s) do s = s + 1 end
  local caret = #new - s
  -- společný konec mohl začít uprostřed vícebajtového znaku: místo posunout za celý znak
  while continuation(new:byte(caret + 1)) do caret = caret + 1 end
  return caret
end

--- Odsazení řádku (úvodní mezery a tabulátory).
local function indent_of(line)
  return line:match("^[ \t]*")
end

--- Odsazení pro řádek pod `line`: stejné, o úroveň víc za řádkem končícím dvojtečkou.
local function indent_below(line)
  local base = indent_of(line)
  if line:match(":%s*$") then return base .. M.INDENT end
  return base
end

--- Poslední neprázdný řádek v textu, nebo "".
local function last_nonblank(text)
  local last = ""
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line:find("[^ \t]") then last = line end
  end
  return last
end

--- Umístění šablony příkazu: prázdný řádek s místem psaní se nahradí, jinak se vloží řádek pod něj.
--- @return integer from první bajt nahrazovaného úseku (od 1)
--- @return integer to poslední bajt nahrazovaného úseku (to < from = jen vložení)
--- @return string prefix text před blokem v nahrazovaném úseku ("\n" nebo "")
--- @return string indent odsazení bloku
local function place_statement(text, caret)
  local line_start = (text:sub(1, caret):match(".*()\n") or 0) + 1
  local nl = text:find("\n", caret + 1, true)
  local line_end = (nl or #text + 1) - 1
  local line = text:sub(line_start, line_end)
  if line:find("[^ \t]") then
    return line_end + 1, line_end, "\n", indent_below(line)
  end
  -- prázdný řádek: vlastní odsazení hráče má přednost, jinak podle předchozího neprázdného řádku
  local indent = line
  if indent == "" then indent = indent_below(last_nonblank(text:sub(1, line_start - 2))) end
  return line_start, line_end, "", indent
end

--- Vloží šablonu do textu na místo `caret`.
--- @param text string
--- @param caret integer|nil bajtů před místem (nil nebo mimo text = konec textu)
--- @param snippet table z SNIPPETS
--- @return string new_text
--- @return integer sel_start první bajt zástupného slova (od 1)
--- @return integer sel_end poslední bajt zástupného slova
--- @return integer new_caret místo za vloženým kódem
function M.insert(text, caret, snippet)
  if not caret or caret > #text then caret = #text end
  local from, to, block = caret + 1, caret, snippet.code
  if snippet.kind == "stmt" then
    local prefix, indent
    from, to, prefix, indent = place_statement(text, caret)
    block = prefix .. indent .. snippet.code:gsub("\n", "\n" .. indent)
  end
  local new = text:sub(1, from - 1) .. block .. text:sub(to + 1)
  local sel_start = from - 1 + block:find(snippet.select, 1, true)
  return new, sel_start, sel_start + #snippet.select - 1, from - 1 + #block
end

--- Počet znaků UTF-8 v prvních `bytes` bajtech textu.
--- @param text string
--- @param bytes integer
--- @return integer
function M.char_count(text, bytes)
  local n = 0
  for i = 1, bytes do
    if not continuation(text:byte(i)) then n = n + 1 end
  end
  return n
end

--- Postaví lištu šablon pod editor: řádky s popiskem a tlačítky (tooltip = popis + kód šablony).
--- @param parent LuaGuiElement
--- @return LuaGuiElement bar
function M.build_bar(parent)
  local bar = parent.add({ type = "flow", name = "pyntr_snippets", direction = "vertical" })
  bar.style.vertical_spacing = 2
  for _, row_def in ipairs(M.ROWS) do
    local row = bar.add({ type = "flow", name = "pyntr_snippets_" .. row_def.id, direction = "horizontal" })
    row.style.vertical_align = "center"
    row.style.horizontal_spacing = 4
    local label = row.add({ type = "label", caption = { "pyntr-gui.snippets-" .. row_def.id } })
    label.style.width = M.LABEL_WIDTH
    for _, id in ipairs(row_def.snippets) do
      local s = BY_ID[id]
      row.add({ type = "button", name = "pyntr_snippet_" .. id, caption = s.caption,
                style = "pyntr_snippet_button",
                tooltip = { "pyntr-gui.snippet-tooltip", { "pyntr-gui.snippet-" .. id }, s.code },
                tags = { pyntr_action = "snippet", snippet = id } })
    end
  end
  return bar
end

return M
