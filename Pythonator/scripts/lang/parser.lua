--- Parser: tokeny → AST (rekurzivní sestup, priority operátorů jako v Pythonu).
local errors = require("scripts.lang.errors")
local lexer = require("scripts.lang.lexer")

local M = {}

local P = {}
P.__index = P

--- Vyhodí chybu „nečekaný token“ s textem odpovídajícím druhu tokenu.
local function fail_at(tk)
  if tk.t == "NEWLINE" then errors.raise(tk.line, tk.col, "unexpected-newline") end
  if tk.t == "INDENT" then errors.raise(tk.line, tk.col, "unexpected-indent") end
  if tk.t == "DEDENT" or tk.t == "EOF" then errors.raise(tk.line, tk.col, "unexpected-eof") end
  local text
  if tk.t == "STR" then text = '"' .. tk.v .. '"'
  elseif tk.t == "SIG" then text = "[" .. tk.v.tag .. "=" .. tk.v.name .. "]"
  else text = tostring(tk.v) end
  errors.raise(tk.line, tk.col, "unexpected-token", text)
end
M.fail_at = fail_at

--- Nový uzel AST s pozicí tokenu.
local function node(k, tk, fields)
  fields.k, fields.line, fields.col = k, tk.line, tk.col
  return fields
end
M.node = node

local EXPR_START_OP = { ["("] = true, ["["] = true, ["{"] = true, ["-"] = true, ["+"] = true, ["~"] = true }
local EXPR_START_KW = { True = true, False = true, None = true, ["not"] = true }

--- Může token začínat výraz?
local function starts_expr(tk)
  return tk.t == "NAME" or tk.t == "NUM" or tk.t == "STR" or tk.t == "SIG"
    or (tk.t == "OP" and EXPR_START_OP[tk.v] == true) or (tk.t == "KW" and EXPR_START_KW[tk.v] == true)
end
M.starts_expr = starts_expr

--- Vytvoří parser nad tokeny.
function M.new(toks) return setmetatable({ toks = toks, i = 1 }, P) end

function P:peek(k) return self.toks[self.i + (k or 0)] end
function P:next() local tk = self.toks[self.i]; self.i = self.i + 1; return tk end
function P:is(t, v) local tk = self.toks[self.i]; return tk.t == t and (v == nil or tk.v == v) end
function P:accept(t, v) if self:is(t, v) then return self:next() end end
function P:expect(t, v) if self:is(t, v) then return self:next() end; fail_at(self:peek()) end

--- Comprehension není podporovaná – srozumitelná chyba místo „nečekané for“.
function P:no_comprehension()
  local tk = self:peek()
  if tk.t == "KW" and tk.v == "for" then errors.raise(tk.line, tk.col, "unsupported", "comprehension") end
end

--- Výraz včetně podmíněného `a if c else b`.
function P:expr()
  local e = self:or_expr()
  local tk = self:accept("KW", "if")
  if tk then
    local test = self:or_expr()
    self:expect("KW", "else")
    return node("IfExp", tk, { test = test, body = e, orelse = self:expr() })
  end
  return e
end

--- Výraz nebo n-tice bez závorek (`a, b`).
function P:expr_list()
  local first = self:peek()
  local e = self:expr()
  if not self:is("OP", ",") then return e end
  local elts = { e }
  while self:accept("OP", ",") do
    if not starts_expr(self:peek()) then break end
    elts[#elts + 1] = self:expr()
  end
  return node("Tuple", first, { elts = elts })
end

--- Úroveň logického operátoru (`or` / `and`).
local function boollevel(op, next_name)
  return function(self)
    local e = self[next_name](self)
    if not self:is("KW", op) then return e end
    local values = { e }
    local first = self:peek()
    while self:accept("KW", op) do values[#values + 1] = self[next_name](self) end
    return node("BoolOp", first, { op = op, values = values })
  end
end
P.or_expr = boollevel("or", "and_expr")
P.and_expr = boollevel("and", "not_expr")

function P:not_expr()
  local tk = self:accept("KW", "not")
  if tk then return node("UnaryOp", tk, { op = "not", operand = self:not_expr() }) end
  return self:comparison()
end

local CMP = { ["<"] = true, [">"] = true, ["=="] = true, [">="] = true, ["<="] = true, ["!="] = true }

--- Přečte porovnávací operátor, nebo vrátí nil.
function P:cmp_op()
  local tk = self:peek()
  if tk.t == "OP" and CMP[tk.v] then self:next(); return tk.v end
  if tk.t == "KW" and tk.v == "in" then self:next(); return "in" end
  if tk.t == "KW" and tk.v == "not" then
    local nx = self:peek(1)
    if nx.t == "KW" and nx.v == "in" then self.i = self.i + 2; return "not in" end
  end
  if tk.t == "KW" and tk.v == "is" then
    self:next()
    if self:accept("KW", "not") then return "is not" end
    return "is"
  end
end

function P:comparison()
  local first = self:peek()
  local left = self:bitor()
  local ops, cmps = {}, {}
  while true do
    local op = self:cmp_op()
    if not op then break end
    ops[#ops + 1] = op
    cmps[#cmps + 1] = self:bitor()
  end
  if #ops == 0 then return left end
  return node("Compare", first, { left = left, ops = ops, comparators = cmps })
end

--- Úroveň binárních operátorů s levou asociativitou.
local function binlevel(next_name, ops)
  return function(self)
    local e = self[next_name](self)
    while true do
      local tk = self:peek()
      if not (tk.t == "OP" and ops[tk.v]) then return e end
      self:next()
      e = node("BinOp", tk, { op = tk.v, left = e, right = self[next_name](self) })
    end
  end
end
P.bitor = binlevel("bitxor", { ["|"] = true })
P.bitxor = binlevel("bitand", { ["^"] = true })
P.bitand = binlevel("shift", { ["&"] = true })
P.shift = binlevel("arith", { ["<<"] = true, [">>"] = true })
P.arith = binlevel("term", { ["+"] = true, ["-"] = true })
P.term = binlevel("factor", { ["*"] = true, ["/"] = true, ["//"] = true, ["%"] = true })

function P:factor()
  local tk = self:peek()
  if tk.t == "OP" and (tk.v == "-" or tk.v == "+" or tk.v == "~") then
    self:next()
    return node("UnaryOp", tk, { op = tk.v, operand = self:factor() })
  end
  return self:power()
end

function P:power()
  local base = self:postfix()
  local tk = self:accept("OP", "**")
  if tk then return node("BinOp", tk, { op = "**", left = base, right = self:factor() }) end
  return base
end

--- Argumenty volání po `(` až po `)`; vrátí poziční a pojmenované.
function P:call_args()
  local args, kwargs = {}, {}
  while not self:accept("OP", ")") do
    local tk, nx = self:peek(), self:peek(1)
    if tk.t == "NAME" and nx.t == "OP" and nx.v == "=" then
      self.i = self.i + 2
      kwargs[#kwargs + 1] = { name = tk.v, value = self:expr(), line = tk.line, col = tk.col }
    else
      if #kwargs > 0 then fail_at(tk) end
      if tk.t == "OP" and (tk.v == "*" or tk.v == "**") then errors.raise(tk.line, tk.col, "unsupported", tk.v .. "args") end
      args[#args + 1] = self:expr()
      self:no_comprehension()
    end
    if not self:accept("OP", ",") then self:expect("OP", ")"); break end
  end
  return args, kwargs
end

--- Index nebo řez po `[`.
function P:subscript(value, tk)
  local lower, upper
  if not self:is("OP", ":") then lower = self:expr() end
  if self:accept("OP", ":") then
    if not self:is("OP", "]") and not self:is("OP", ":") then upper = self:expr() end
    if self:is("OP", ":") then
      local t2 = self:peek()
      errors.raise(t2.line, t2.col, "unsupported", "[a:b:c]")
    end
    self:expect("OP", "]")
    return node("Slice", tk, { value = value, lower = lower, upper = upper })
  end
  self:expect("OP", "]")
  return node("Subscript", tk, { value = value, index = lower })
end

--- Atom s příponami: volání, index/řez, volání metody.
function P:postfix()
  local e = self:atom()
  while true do
    local tk = self:peek()
    if tk.t == "OP" and tk.v == "(" then
      if e.k ~= "Name" then errors.raise(tk.line, tk.col, "not-callable") end
      self:next()
      local args, kwargs = self:call_args()
      e = node("Call", e, { func = e.id, args = args, kwargs = kwargs })
    elseif tk.t == "OP" and tk.v == "[" then
      self:next()
      e = self:subscript(e, tk)
    elseif tk.t == "OP" and tk.v == "." then
      self:next()
      local name = self:expect("NAME")
      if not self:is("OP", "(") then errors.raise(name.line, name.col, "attribute-unsupported") end
      self:next()
      local args, kwargs = self:call_args()
      if #kwargs > 0 then errors.raise(kwargs[1].line, kwargs[1].col, "kwargs-unsupported") end
      e = node("Method", name, { obj = e, name = name.v, args = args })
    else
      return e
    end
  end
end

--- Prvky oddělené čárkou až po uzavírací závorku (koncová čárka povolená).
function P:sequence(close)
  local elts = {}
  while not self:accept("OP", close) do
    elts[#elts + 1] = self:expr()
    self:no_comprehension()
    if not self:accept("OP", ",") then self:expect("OP", close); break end
  end
  return elts
end

function P:atom()
  local tk = self:next()
  if tk.t == "NAME" then return node("Name", tk, { id = tk.v }) end
  if tk.t == "NUM" then return node("Num", tk, { v = tk.v }) end
  if tk.t == "STR" then
    local parts = { tk.v }
    while self:is("STR") do parts[#parts + 1] = self:next().v end
    return node("Str", tk, { v = table.concat(parts) })
  end
  if tk.t == "SIG" then
    return node("Signal", tk, { stype = tk.v.stype, tag = tk.v.tag, name = tk.v.name, quality = tk.v.quality })
  end
  if tk.t == "KW" then
    if tk.v == "True" then return node("Bool", tk, { v = true }) end
    if tk.v == "False" then return node("Bool", tk, { v = false }) end
    if tk.v == "None" then return node("None", tk, {}) end
  end
  if tk.t == "OP" and tk.v == "(" then
    if self:accept("OP", ")") then return node("Tuple", tk, { elts = {} }) end
    local e = self:expr()
    self:no_comprehension()
    if self:accept("OP", ")") then return e end
    local elts = { e }
    while self:accept("OP", ",") do
      if self:is("OP", ")") then break end
      elts[#elts + 1] = self:expr()
    end
    self:expect("OP", ")")
    return node("Tuple", tk, { elts = elts })
  end
  if tk.t == "OP" and tk.v == "[" then return node("List", tk, { elts = self:sequence("]") }) end
  if tk.t == "OP" and tk.v == "{" then
    local keys, values = {}, {}
    while not self:accept("OP", "}") do
      keys[#keys + 1] = self:expr()
      self:expect("OP", ":")
      values[#values + 1] = self:expr()
      if not self:accept("OP", ",") then self:expect("OP", "}"); break end
    end
    return node("Dict", tk, { keys = keys, values = values })
  end
  fail_at(tk)
end

--- Rozparsuje jediný výraz (pro testy).
--- @param src string
--- @return table expr
function M.parse_expression(src)
  local p = M.new(lexer.tokenize(src))
  local e = p:expr_list()
  p:expect("NEWLINE")
  p:expect("EOF")
  return e
end


--- Konec jednoduchého příkazu: NEWLINE (nebo EOF).
function P:end_line()
  if self:accept("NEWLINE") or self:is("EOF") then return end
  fail_at(self:peek())
end

local AUG = {}
for _, op in ipairs({ "+=", "-=", "*=", "/=", "//=", "%=", "**=", "&=", "|=", "^=", "<<=", ">>=" }) do AUG[op] = true end

--- Ověří, že výraz je platný cíl přiřazení (rozšířené přiřazení nepovoluje n-tice).
local function check_target(e, aug)
  if e.k == "Name" or e.k == "Subscript" then return end
  if not aug and (e.k == "Tuple" or e.k == "List") then
    for _, el in ipairs(e.elts) do check_target(el, false) end
    return
  end
  errors.raise(e.line, e.col, "bad-target")
end

--- Jednoduchý příkaz (bez koncového NEWLINE).
function P:simple()
  local tk = self:peek()
  if tk.t == "KW" then
    if tk.v == "pass" then self:next(); return node("Pass", tk, {}) end
    if tk.v == "break" then self:next(); return node("Break", tk, {}) end
    if tk.v == "continue" then self:next(); return node("Continue", tk, {}) end
    if tk.v == "return" then
      self:next()
      local value
      if starts_expr(self:peek()) then value = self:expr_list() end
      return node("Return", tk, { value = value })
    end
    if tk.v == "global" then
      self:next()
      local names = { self:expect("NAME").v }
      while self:accept("OP", ",") do names[#names + 1] = self:expect("NAME").v end
      return node("Global", tk, { names = names })
    end
  end
  local first = self:expr_list()
  local op = self:peek()
  if op.t == "OP" and op.v == "=" then
    local items = { first }
    while self:accept("OP", "=") do items[#items + 1] = self:expr_list() end
    local value = table.remove(items)
    for _, t in ipairs(items) do check_target(t, false) end
    return node("Assign", tk, { targets = items, value = value })
  end
  if op.t == "OP" and AUG[op.v] then
    self:next()
    check_target(first, true)
    return node("AugAssign", tk, { target = first, op = op.v:sub(1, -2), value = self:expr_list() })
  end
  return node("Expr", tk, { value = first })
end

--- Blok po `:` – odsazený, nebo jednoduchý příkaz na stejném řádku.
function P:block()
  self:expect("OP", ":")
  local body = {}
  if self:accept("NEWLINE") then
    local tk = self:peek()
    if tk.t ~= "INDENT" then errors.raise(tk.line, tk.col, "expected-indent") end
    self:next()
    while not self:accept("DEDENT") do self:statement(body) end
  else
    body[1] = self:simple()
    self:end_line()
  end
  return body
end

--- if / elif (elif se vnoří do orelse).
function P:if_stmt()
  local tk = self:next()
  local test = self:expr()
  local n = node("If", tk, { test = test, body = self:block(), orelse = {} })
  if self:is("KW", "elif") then
    n.orelse = { self:if_stmt() }
  elseif self:accept("KW", "else") then
    n.orelse = self:block()
  end
  return n
end

--- Prvek cíle cyklu for: jméno nebo n-tice v závorkách.
function P:target_atom()
  local tk = self:next()
  if tk.t == "NAME" then return node("Name", tk, { id = tk.v }) end
  if tk.t == "OP" and tk.v == "(" then
    local t = self:target_list()
    self:expect("OP", ")")
    return t
  end
  fail_at(tk)
end

--- Cíl cyklu for: jeden prvek nebo n-tice oddělená čárkami.
function P:target_list()
  local first = self:peek()
  local t = self:target_atom()
  if not self:is("OP", ",") then return t end
  local elts = { t }
  while self:accept("OP", ",") do
    if not (self:is("NAME") or self:is("OP", "(")) then break end
    elts[#elts + 1] = self:target_atom()
  end
  return node("Tuple", first, { elts = elts })
end

function P:for_stmt()
  local tk = self:next()
  local target = self:target_list()
  self:expect("KW", "in")
  local iter = self:expr_list()
  return node("For", tk, { target = target, iter = iter, body = self:block() })
end

function P:def_stmt()
  local tk = self:next()
  local name = self:expect("NAME")
  self:expect("OP", "(")
  local params = {}
  while not self:accept("OP", ")") do
    local p = self:peek()
    if p.t == "OP" and (p.v == "*" or p.v == "**") then errors.raise(p.line, p.col, "unsupported", p.v .. "args") end
    params[#params + 1] = self:expect("NAME").v
    if self:is("OP", "=") then
      local d = self:peek()
      errors.raise(d.line, d.col, "defaults-unsupported")
    end
    if not self:accept("OP", ",") then self:expect("OP", ")"); break end
  end
  return node("Def", tk, { name = name.v, params = params, body = self:block() })
end

--- Jeden příkaz (složený nebo jednoduchý) připojený do seznamu out.
function P:statement(out)
  local tk = self:peek()
  if tk.t == "KW" then
    if tk.v == "if" then out[#out + 1] = self:if_stmt(); return end
    if tk.v == "while" then
      self:next()
      local test = self:expr()
      out[#out + 1] = node("While", tk, { test = test, body = self:block() })
      return
    end
    if tk.v == "for" then out[#out + 1] = self:for_stmt(); return end
    if tk.v == "def" then out[#out + 1] = self:def_stmt(); return end
  end
  if tk.t == "INDENT" then errors.raise(tk.line, tk.col, "unexpected-indent") end
  out[#out + 1] = self:simple()
  self:end_line()
end

--- Rozparsuje celý program.
--- @param src string
--- @return table Module
function M.parse(src)
  local p = M.new(lexer.tokenize(src))
  local body = {}
  while not p:is("EOF") do p:statement(body) end
  return { k = "Module", body = body, line = 1, col = 1 }
end

M.Parser = P
return M
