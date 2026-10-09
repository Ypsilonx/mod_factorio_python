--- Lexer: zdrojový text → tokeny včetně INDENT/DEDENT a rich text tagů signálů.
local errors = require("scripts.lang.errors")
local signals = require("scripts.lang.signals")

local M = {}

--- Množina slov z řetězce odděleného mezerami.
local function set_of(words)
  local s = {}
  for w in words:gmatch("%S+") do s[w] = true end
  return s
end

local KEYWORDS = set_of("False None True and break continue def elif else for global if in is not or pass return while")
local UNSUPPORTED = set_of("class import from try except finally lambda with yield nonlocal del raise assert async await as")
local OPS3 = set_of("**= //= >>= <<=")
local OPS2 = set_of("** // == != <= >= << >> += -= *= /= %= &= |= ^=")
local OPS1 = {}
for c in ("+-*/%<>=()[]{},:.~&|^;"):gmatch(".") do OPS1[c] = true end
local OPEN = set_of("( [ {")
local CLOSE = set_of(") ] }")
local ESCAPES = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ["'"] = "'", ['"'] = '"', ["0"] = "\0" }

--- Rozdělí zdroj na tokeny {t, v, line, col}.
--- @param src string
--- @return table[]
function M.tokenize(src)
  src = src:gsub("\r\n", "\n"):gsub("\r", "\n")
  local toks, indents = {}, { "" }
  local pos, n, line, lstart, depth, bol = 1, #src, 1, 1, 0, true

  --- Přidá token (řádek implicitně aktuální).
  local function push(t, v, col, ln)
    toks[#toks + 1] = { t = t, v = v, line = ln or line, col = col }
  end

  --- Zpracuje odsazení na začátku logického řádku.
  local function indentation()
    local s, e = src:find("^[ \t]*", pos)
    local ind = src:sub(s, e)
    local c = src:sub(e + 1, e + 1)
    pos = e + 1
    if depth > 0 or c == "\n" or c == "#" or c == "" then return end
    local top = indents[#indents]
    if #ind > #top then
      if ind:sub(1, #top) ~= top then errors.raise(line, 1, "bad-indent") end
      indents[#indents + 1] = ind
      push("INDENT", nil, 1)
      return
    end
    while indents[#indents] ~= ind do
      if #indents == 1 or #indents[#indents] <= #ind then errors.raise(line, 1, "bad-indent") end
      indents[#indents] = nil
      push("DEDENT", nil, 1)
    end
  end

  --- Přečte řetězec v uvozovkách q (i trojitých) od pozice pos.
  local function string_literal(q, col)
    local startline = line
    local triple = src:sub(pos, pos + 2) == q:rep(3)
    local i = pos + (triple and 3 or 1)
    local buf = {}
    while true do
      local ch = src:sub(i, i)
      if ch == "" or (ch == "\n" and not triple) then errors.raise(startline, col, "unterminated-string") end
      if triple and src:sub(i, i + 2) == q:rep(3) then i = i + 3; break end
      if not triple and ch == q then i = i + 1; break end
      if ch == "\\" then
        local nx = src:sub(i + 1, i + 1)
        if nx == "\n" then
          line = line + 1; lstart = i + 2
        else
          buf[#buf + 1] = ESCAPES[nx] or ("\\" .. nx)
        end
        i = i + 2
      else
        if ch == "\n" then line = line + 1; lstart = i + 1 end
        buf[#buf + 1] = ch
        i = i + 1
      end
    end
    push("STR", table.concat(buf), col, startline)
    pos = i
  end

  --- Přečte číslo (desítkové, hex, exponent, podtržítka).
  local function number(col)
    local s = src:match("^0[xX][0-9A-Fa-f]+", pos)
    local v
    if s then
      v = tonumber(s:sub(3), 16)
    else
      s = src:match("^[0-9][0-9_]*%.?[0-9_]*", pos) or src:match("^%.[0-9][0-9_]*", pos)
      local ex = src:match("^[eE][%+%-]?[0-9]+", pos + #s)
      if ex then s = s .. ex end
      v = tonumber((s:gsub("_", "")))
    end
    local after = src:sub(pos + #s, pos + #s)
    if not v or after:match("[A-Za-z0-9_]") then errors.raise(line, col, "bad-number", s .. after) end
    push("NUM", v, col)
    pos = pos + #s
  end

  --- Přečte jméno nebo klíčové slovo.
  local function word(col)
    local w = src:match("^[A-Za-z_][A-Za-z0-9_]*", pos)
    local nxt = src:sub(pos + #w, pos + #w)
    if (nxt == '"' or nxt == "'") and #w <= 2 and w:match("^[fFrRbBuU]+$") then
      errors.raise(line, col, "unsupported", w .. nxt .. "…" .. nxt)
    end
    if UNSUPPORTED[w] then errors.raise(line, col, "unsupported", w) end
    push(KEYWORDS[w] and "KW" or "NAME", w, col)
    pos = pos + #w
  end

  --- Zkusí přečíst rich text tag signálu; vrátí true při úspěchu.
  local function tag(col)
    local tt, nm, q = src:match("^%[([A-Za-z0-9%-]+)=([A-Za-z0-9%-_]+),quality=([A-Za-z0-9%-_]+)%]", pos)
    local whole
    if tt then
      whole = "[" .. tt .. "=" .. nm .. ",quality=" .. q .. "]"
    else
      tt, nm = src:match("^%[([A-Za-z0-9%-]+)=([A-Za-z0-9%-_]+)%]", pos)
      q = "normal"
      if tt then whole = "[" .. tt .. "=" .. nm .. "]" end
    end
    if not (tt and signals.TAG_TYPES[tt]) then return false end
    push("SIG", { stype = signals.TAG_TYPES[tt], tag = tt, name = nm, quality = q }, col)
    pos = pos + #whole
    return true
  end

  --- Přečte operátor (nejdelší shoda).
  local function operator(c, col)
    local three, two = src:sub(pos, pos + 2), src:sub(pos, pos + 1)
    local op = (OPS3[three] and three) or (OPS2[two] and two) or (OPS1[c] and c)
    if not op then errors.raise(line, col, "bad-char", c) end
    if op == ";" then errors.raise(line, col, "unsupported", ";") end
    if OPEN[op] then depth = depth + 1 elseif CLOSE[op] and depth > 0 then depth = depth - 1 end
    push("OP", op, col)
    pos = pos + #op
  end

  while pos <= n do
    if bol then
      bol = false
      indentation()
    else
      local c = src:sub(pos, pos)
      local col = pos - lstart + 1
      if c == "\n" then
        if depth == 0 and #toks > 0 and toks[#toks].t ~= "NEWLINE" then push("NEWLINE", nil, col) end
        pos = pos + 1; line = line + 1; lstart = pos; bol = true
      elseif c == " " or c == "\t" then
        pos = pos + 1
      elseif c == "#" then
        pos = src:find("\n", pos, true) or n + 1
      elseif c == "\\" and src:sub(pos + 1, pos + 1) == "\n" then
        pos = pos + 2; line = line + 1; lstart = pos
      elseif c == '"' or c == "'" then
        string_literal(c, col)
      elseif c:match("[0-9]") or (c == "." and src:sub(pos + 1, pos + 1):match("[0-9]")) then
        number(col)
      elseif c:match("[A-Za-z_]") then
        word(col)
      elseif not (c == "[" and tag(col)) then
        operator(c, col)
      end
    end
  end
  if #toks > 0 and toks[#toks].t ~= "NEWLINE" then push("NEWLINE", nil, pos - lstart + 1) end
  for _ = 2, #indents do push("DEDENT", nil, 1) end
  push("EOF", nil, 1)
  return toks
end

return M
