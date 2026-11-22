--- Šablony kódu pod editorem: vložení na místo posledního psaní a označení zástupného slova.
--- API text-boxu kurzor nezná (jen zápis select), proto se „kurzor“ odvozuje z rozdílu textů při psaní.
--- Pozice jsou v bajtech (počet bajtů před místem); pro select se převádějí na znaky.
local M = {}

--- Odsazení vnořeného bloku (mezery).
M.INDENT = "    "

--- Šířka popisku řádku lišty (px). Laditelné.
M.LABEL_WIDTH = 70
--- Velikost tlačítka výběru signálu (px). Laditelné.
M.PICK_SIZE = 28

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

--- Zástupné slovo šablony: identifikátor jen z velkých písmen a podtržítek, aspoň 2 znaky (SIGNAL, SET_CONDITION).
--- Explicitní ASCII třídy – %w závisí na locale.
local PLACEHOLDER = "%f[A-Za-z0-9_][A-Z][A-Z_]+%f[^A-Za-z0-9_]"
--- Zástupné slovo, které nahradí vybraný signál.
M.SIGNAL_PLACEHOLDER = "SIGNAL"

--- První zástupné slovo v úseku textu.
--- @param text string
--- @param from integer první bajt hledání
--- @param to integer poslední bajt, kde smí slovo končit
--- @return integer|nil first
--- @return integer|nil last
function M.next_placeholder(text, from, to)
  local first, last = text:find(PLACEHOLDER, from)
  if first and last <= to then return first, last end
end

--- Vloží vybraný signál. Je-li označené zástupné SIGNAL z poslední šablony (`sel`, text se od vložení
--- nezměnil), nahradí ho jménem signálu a vrátí další zástupné slovo šablony k označení; jinak vloží
--- "jméno" v uvozovkách na místo psaní.
--- @param text string
--- @param caret integer|nil místo psaní (bajty před ním)
--- @param sel table|nil { first, last, region_end, text } označení z poslední šablony
--- @param key string kanonický klíč signálu
--- @return string new_text
--- @return integer new_caret
--- @return table|nil new_sel označení dalšího zástupného slova (stejný tvar jako `sel`)
function M.insert_signal(text, caret, sel, key)
  if sel and sel.text == text and text:sub(sel.first, sel.last) == M.SIGNAL_PLACEHOLDER then
    local new = text:sub(1, sel.first - 1) .. key .. text:sub(sel.last + 1)
    local new_caret = sel.first - 1 + #key
    local region_end = sel.region_end + #key - (sel.last - sel.first + 1)
    local first, last = M.next_placeholder(new, new_caret + 1, region_end)
    local next_sel = first and { first = first, last = last, region_end = region_end, text = new } or nil
    return new, new_caret, next_sel
  end
  if not caret or caret > #text then caret = #text end
  local quoted = "\"" .. key .. "\""
  return text:sub(1, caret) .. quoted .. text:sub(caret + 1), caret + #quoted, nil
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
    if row_def.id == "code" then
      local pick = row.add({ type = "choose-elem-button", name = "pyntr_signal_pick", elem_type = "signal",
                             tooltip = { "pyntr-gui.snippet-signal" }, tags = { pyntr_action = "signal_pick" } })
      pick.style.size = M.PICK_SIZE
    end
  end
  return bar
end

return M
