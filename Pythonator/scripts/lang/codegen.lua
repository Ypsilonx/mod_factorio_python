--- Generátor: AST (po checkeru) → zdroj Lua 5.2 s watchdogem a sledováním řádku zdroje.
local checker = require("scripts.lang.checker")

local M = {}

--- Pomocné funkce runtime dostupné jako lokální proměnné vygenerovaného kódu.
local HELPERS = { "add", "sub", "mul", "truediv", "floordiv", "mod", "pow", "neg", "pos", "invert", "not_",
  "band", "bor", "bxor", "lshift", "rshift", "eq", "ne", "lt", "le", "gt", "ge", "contains", "is_",
  "truthy", "getitem", "setitem", "slice", "iter", "unpack", "method", "list", "tuple", "dict",
  "and_", "or_", "print_line", "range_bounds" }

local BINOP = { ["+"] = "add", ["-"] = "sub", ["*"] = "mul", ["/"] = "truediv", ["//"] = "floordiv",
  ["%"] = "mod", ["**"] = "pow", ["&"] = "band", ["|"] = "bor", ["^"] = "bxor", ["<<"] = "lshift", [">>"] = "rshift" }
local UNOP = { ["-"] = "neg", ["+"] = "pos", ["~"] = "invert", ["not"] = "not_" }
local CMPOP = { ["<"] = "lt", ["<="] = "le", [">"] = "gt", [">="] = "ge", ["=="] = "eq", ["!="] = "ne" }
local SIMPLE = { Name = true, Num = true, Str = true, Bool = true, None = true }
local WD = "_b = _b - 1 if _b < 0 then wd() end"

local Gen = {}
Gen.__index = Gen

function Gen:emit(line) self.out[#self.out + 1] = line end

--- Nové jméno dočasné proměnné.
function Gen:tmp()
  self.ntmp = self.ntmp + 1
  return "_t" .. self.ntmp
end

--- Číselný literál jako text Lua.
local function num(v)
  if v == math.huge then return "(1/0)" end
  if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
  return string.format("%.17g", v)
end

--- Výraz Lua pro čtení/zápis jména.
function Gen:name(id)
  if self.fn and self.fn.locals[id] then return "l_" .. id end
  if checker.READONLY[id] or checker.SIGNAL_OBJS[id] then return "IO." .. id end
  return string.format("G[%q]", id)
end

--- Jedno porovnání a op b jako Lua boolean.
local function cmp1(op, a, b)
  if op == "in" then return "contains(" .. b .. ", " .. a .. ")" end
  if op == "not in" then return "not contains(" .. b .. ", " .. a .. ")" end
  if op == "is" then return "is_(" .. a .. ", " .. b .. ")" end
  if op == "is not" then return "not is_(" .. a .. ", " .. b .. ")" end
  return CMPOP[op] .. "(" .. a .. ", " .. b .. ")"
end

--- Porovnání (i řetězené) jako Lua boolean výraz.
function Gen:compare(e)
  if #e.ops == 1 then return cmp1(e.ops[1], self:ex(e.left), self:ex(e.comparators[1])) end
  local simple = true
  for _, c in ipairs(e.comparators) do if not SIMPLE[c.k] then simple = false end end
  if simple then
    local operands, parts = { self:ex(e.left) }, {}
    for _, c in ipairs(e.comparators) do operands[#operands + 1] = self:ex(c) end
    for i, op in ipairs(e.ops) do parts[i] = cmp1(op, operands[i], operands[i + 1]) end
    return table.concat(parts, " and ")
  end
  local code = { "(function() local _a = " .. self:ex(e.left) }
  for i, op in ipairs(e.ops) do
    code[#code + 1] = "local _c = " .. self:ex(e.comparators[i])
    code[#code + 1] = "if not (" .. cmp1(op, "_a", "_c") .. ") then return false end"
    code[#code + 1] = "_a = _c"
  end
  code[#code + 1] = "return true end)()"
  return table.concat(code, " ")
end

--- Podmínka jako Lua boolean (bez obalování truthy, kde to jde).
function Gen:cond(e)
  local k = e.k
  if k == "Compare" then return "(" .. self:compare(e) .. ")" end
  if k == "Bool" then return e.v and "true" or "false" end
  if k == "UnaryOp" and e.op == "not" then return "not " .. self:cond(e.operand) end
  if k == "BoolOp" then
    local parts = {}
    for i, v in ipairs(e.values) do parts[i] = self:cond(v) end
    return "(" .. table.concat(parts, " " .. e.op .. " ") .. ")"
  end
  return "truthy(" .. self:ex(e) .. ")"
end

--- Volání funkce (uživatelské, print, vestavěné).
function Gen:call(e)
  local args = {}
  for i, a in ipairs(e.args) do args[i] = self:ex(a) end
  local list = table.concat(args, ", ")
  if self.info.functions[e.func] then return "f_" .. e.func .. "(" .. list .. ")" end
  if e.func == "print" then return "print_(" .. list .. ")" end
  return "B." .. e.func .. "(" .. list .. ")"
end

--- Výraz jako text Lua.
function Gen:ex(e)
  local k = e.k
  if k == "Num" then return num(e.v) end
  if k == "Str" then return string.format("%q", e.v) end
  if k == "Bool" then return e.v and "true" or "false" end
  if k == "None" then return "None" end
  if k == "Name" then return self:name(e.id) end
  if k == "BinOp" then return BINOP[e.op] .. "(" .. self:ex(e.left) .. ", " .. self:ex(e.right) .. ")" end
  if k == "UnaryOp" then return UNOP[e.op] .. "(" .. self:ex(e.operand) .. ")" end
  if k == "BoolOp" then
    local acc = self:ex(e.values[#e.values])
    for i = #e.values - 1, 1, -1 do
      acc = (e.op == "and" and "and_" or "or_") .. "(" .. self:ex(e.values[i]) .. ", function() return " .. acc .. " end)"
    end
    return acc
  end
  if k == "Compare" then return "(" .. self:compare(e) .. ")" end
  if k == "IfExp" then
    return "(function() if " .. self:cond(e.test) .. " then return " .. self:ex(e.body)
      .. " end return " .. self:ex(e.orelse) .. " end)()"
  end
  if k == "Call" then return self:call(e) end
  if k == "Method" then
    local args = { self:ex(e.obj), string.format("%q", e.name) }
    for _, a in ipairs(e.args) do args[#args + 1] = self:ex(a) end
    return "method(" .. table.concat(args, ", ") .. ")"
  end
  if k == "Subscript" then return "getitem(" .. self:ex(e.value) .. ", " .. self:ex(e.index) .. ")" end
  if k == "Slice" then
    return "slice(" .. self:ex(e.value) .. ", " .. (e.lower and self:ex(e.lower) or "nil") .. ", "
      .. (e.upper and self:ex(e.upper) or "nil") .. ")"
  end
  if k == "List" or k == "Tuple" then
    local parts = {}
    for i, v in ipairs(e.elts) do parts[i] = self:ex(v) end
    return (k == "List" and "list" or "tuple") .. "({" .. table.concat(parts, ", ") .. "}, " .. #parts .. ")"
  end
  if k == "Dict" then
    local parts = {}
    for i, key in ipairs(e.keys) do
      parts[#parts + 1] = self:ex(key)
      parts[#parts + 1] = self:ex(e.values[i])
    end
    return "dict({" .. table.concat(parts, ", ") .. "}, " .. #parts .. ")"
  end
  error("codegen: neznámý výraz " .. tostring(k))
end

--- Přiřazení hodnoty (text Lua, už vyhodnocený) do cíle.
function Gen:assign(target, value)
  local k = target.k
  if k == "Name" then
    self:emit(self:name(target.id) .. " = " .. value)
  elseif k == "Subscript" then
    self:emit("setitem(" .. self:ex(target.value) .. ", " .. self:ex(target.index) .. ", " .. value .. ")")
  else
    local names = {}
    for i = 1, #target.elts do names[i] = self:tmp() end
    self:emit("do local " .. table.concat(names, ", ") .. " = unpack(" .. value .. ", " .. #names .. ")")
    for i, el in ipairs(target.elts) do self:assign(el, names[i]) end
    self:emit("end")
  end
end

--- Tělo cyklu se štítkem pro continue na konci.
function Gen:loop_body(body)
  self.nlabel = self.nlabel + 1
  local label = "c" .. self.nlabel
  self.loops[#self.loops + 1] = label
  self:stmts(body)
  self.loops[#self.loops] = nil
  self:emit("::" .. label .. "::")
end

--- Příkaz jako řádky Lua.
function Gen:stmt(s)
  local k = s.k
  if k == "Def" or k == "Global" or k == "Pass" then return end
  self:emit("_ln = " .. s.line .. ";")
  if k == "Expr" then
    local v = s.value
    if v.k == "Call" and v.func == "config" then return end
    if v.k == "Call" or v.k == "Method" then
      self:emit(self:ex(v))
    else
      self:emit("do local _ = " .. self:ex(v) .. " end")
    end
  elseif k == "Assign" then
    local t1 = s.targets[1]
    if #s.targets == 1 and t1.k ~= "Tuple" and t1.k ~= "List" then
      self:assign(t1, self:ex(s.value))
    else
      local t = self:tmp()
      self:emit("do local " .. t .. " = " .. self:ex(s.value))
      for _, target in ipairs(s.targets) do self:assign(target, t) end
      self:emit("end")
    end
  elseif k == "AugAssign" then
    local f, t = BINOP[s.op], s.target
    if t.k == "Name" then
      local n = self:name(t.id)
      self:emit(n .. " = " .. f .. "(" .. n .. ", " .. self:ex(s.value) .. ")")
    else
      self:emit("do local _o, _k = " .. self:ex(t.value) .. ", " .. self:ex(t.index))
      self:emit("setitem(_o, _k, " .. f .. "(getitem(_o, _k), " .. self:ex(s.value) .. ")) end")
    end
  elseif k == "If" then
    self:emit("if " .. self:cond(s.test) .. " then")
    self:stmts(s.body)
    if #s.orelse > 0 then
      self:emit("else")
      self:stmts(s.orelse)
    end
    self:emit("end")
  elseif k == "While" then
    self:emit("while true do")
    self:emit("_ln = " .. s.line .. "; if not " .. self:cond(s.test) .. " then break end")
    self:emit(WD)
    self:loop_body(s.body)
    self:emit("end")
  elseif k == "For" then
    local it, v = s.iter, self:tmp()
    if it.k == "Call" and it.func == "range" and #it.args >= 1 and #it.args <= 3 then
      local args = {}
      for i, a in ipairs(it.args) do args[i] = self:ex(a) end
      local f, l, st = self:tmp(), self:tmp(), self:tmp()
      self:emit("do local " .. f .. ", " .. l .. ", " .. st .. " = range_bounds(" .. table.concat(args, ", ") .. ")")
      self:emit("for " .. v .. " = " .. f .. ", " .. l .. ", " .. st .. " do")
    else
      self:emit("do for " .. v .. " in iter(" .. self:ex(it) .. ") do")
    end
    self:emit(WD)
    self:assign(s.target, v)
    self:loop_body(s.body)
    self:emit("end end")
  elseif k == "Return" then
    self:emit("do return " .. (s.value and self:ex(s.value) or "None") .. " end")
  elseif k == "Break" then
    self:emit("do break end")
  elseif k == "Continue" then
    self:emit("goto " .. self.loops[#self.loops])
  else
    error("codegen: neznámý příkaz " .. tostring(k))
  end
end

function Gen:stmts(body)
  for _, s in ipairs(body) do self:stmt(s) end
end

--- Funkce uživatele (přiřazení do předem deklarované lokální f_<jméno>).
function Gen:func(fn)
  self.fn = fn
  local params, is_param = {}, {}
  for i, p in ipairs(fn.params) do params[i] = "l_" .. p; is_param[p] = true end
  self:emit("f_" .. fn.node.name .. " = function(" .. table.concat(params, ", ") .. ")")
  self:emit(WD)
  local locals = {}
  for name in pairs(fn.locals) do
    if not is_param[name] then locals[#locals + 1] = "l_" .. name end
  end
  table.sort(locals)
  if #locals > 0 then self:emit("local " .. table.concat(locals, ", ")) end
  self:stmts(fn.node.body)
  self:emit("return None")
  self:emit("end")
  self.fn = nil
end

--- Vygeneruje zdroj Lua: chunk vrací factory function(R, G, IO) → instance.
--- @param ast table Module (po checker.check)
--- @param info table výsledek checker.check
--- @return string
function M.generate(ast, info)
  local self = setmetatable({ out = {}, ntmp = 0, nlabel = 0, loops = {}, info = info }, Gen)
  self:emit("return function(R, G, IO)")
  self:emit("local None, B = R.None, R.builtins")
  self:emit("local " .. table.concat(HELPERS, ", ") .. " = R." .. table.concat(HELPERS, ", R."))
  self:emit("local _b, _ln = 0, 0")
  self:emit("local function wd() R.watchdog() end")
  self:emit("local function print_(...) IO.print(print_line(...)) return None end")
  local names = {}
  for _, s in ipairs(ast.body) do
    if s.k == "Def" then names[#names + 1] = "f_" .. s.name end
  end
  self:emit("local " .. table.concat(names, ", "))
  for _, s in ipairs(ast.body) do
    if s.k == "Def" then self:func(info.functions[s.name]) end
  end
  self:emit("local function init()")
  self:stmts(ast.body)
  self:emit("end")
  self:emit("return { init = init, loop = f_loop, set_budget = function(n) _b = n end,"
    .. " budget = function() return _b end, line = function() return _ln end }")
  self:emit("end")
  return table.concat(self.out, "\n")
end

return M
