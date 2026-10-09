--- Generátor: AST (po checkeru) → zdroj Lua 5.2 s watchdogem a sledováním řádku zdroje.
local checker = require("scripts.lang.checker")

local M = {}

--- Pomocné funkce runtime dostupné jako lokální proměnné vygenerovaného kódu.
local HELPERS = { "add", "sub", "mul", "truediv", "floordiv", "mod", "pow", "neg", "pos", "invert", "not_",
  "band", "bor", "bxor", "lshift", "rshift", "eq", "ne", "lt", "le", "gt", "ge", "contains", "is_",
  "truthy", "getitem", "setitem", "slice", "iter", "unpack", "method", "list", "tuple", "dict",
  "and_", "or_", "print_line", "range_bounds", "items_array", "mget", "mappend" }

local BINOP = { ["+"] = "add", ["-"] = "sub", ["*"] = "mul", ["/"] = "truediv", ["//"] = "floordiv",
  ["%"] = "mod", ["**"] = "pow", ["&"] = "band", ["|"] = "bor", ["^"] = "bxor", ["<<"] = "lshift", [">>"] = "rshift" }
local UNOP = { ["-"] = "neg", ["+"] = "pos", ["~"] = "invert", ["not"] = "not_" }
local CMPOP = { ["<"] = "lt", ["<="] = "le", [">"] = "gt", [">="] = "ge", ["=="] = "eq", ["!="] = "ne" }
local SIMPLE = { Name = true, Num = true, Str = true, Bool = true, None = true }
local WD = "_b = _b - 1 if _b < 0 then wd() end"

--- Operátory, které jdou pro dvě čísla zapsat přímo v Lua (výsledek je číslo = v Lua vždy pravdivé).
local INLINE_ARITH = { ["+"] = true, ["-"] = true, ["*"] = true }

--- Jednoduchý operand: lze ho vyhodnotit víckrát bez vedlejších účinků a levně (jméno, číslo).
local function simple_operand(e)
  return e.k == "Num" or e.k == "Name"
end

--- Je výraz literál, jehož hodnota v Lua není false ani nil (číslo, řetězec, None, True)?
--- Takový výraz jde bezpečně dát do `c and A or B` – Lua `and/or` pak odpovídá Python `A if c else B`.
local function truthy_literal(e)
  return e.k == "Num" or e.k == "Str" or e.k == "None" or (e.k == "Bool" and e.v)
end

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
  -- locale s desetinnou čárkou (cs) by printf psal "2,5" = dvě hodnoty v Lua
  return (string.format("%.17g", v):gsub(",", "."))
end

--- Výraz Lua pro čtení/zápis jména.
function Gen:name(id)
  if self.fn and self.fn.locals[id] then return "l_" .. id end
  if checker.READONLY[id] or checker.SIGNAL_OBJS[id] then return "IO." .. id end
  return string.format("G[%q]", id)
end

--- Hodnota výrazu, která se ukládá nebo předává dál: holé jméno (kromě parametru a IO) se ověří,
--- že je přiřazené – jinak by nil tiše skončil v proměnné, seznamu nebo argumentu.
function Gen:val(e)
  if e.k == "Name" and not checker.READONLY[e.id] and not checker.SIGNAL_OBJS[e.id]
    and not (self.params and self.params[e.id]) then
    return "nn(" .. self:name(e.id) .. ")"
  end
  return self:ex(e)
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
  for i, a in ipairs(e.args) do args[i] = self:val(a) end
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
  if k == "BinOp" then
    local a, b = self:ex(e.left), self:ex(e.right)
    if INLINE_ARITH[e.op] and simple_operand(e.left) and simple_operand(e.right) then
      -- Rychlá cesta pro dvě čísla přímo v Lua, jinak obecná funkce (bool, řetězce, seznamy, chyby).
      local checks = {}
      if e.left.k ~= "Num" then checks[#checks + 1] = "type(" .. a .. ") == \"number\"" end
      if e.right.k ~= "Num" then checks[#checks + 1] = "type(" .. b .. ") == \"number\"" end
      if #checks > 0 then
        return "(" .. table.concat(checks, " and ") .. " and " .. a .. " " .. e.op .. " " .. b
          .. " or " .. BINOP[e.op] .. "(" .. a .. ", " .. b .. "))"
      end
    end
    return BINOP[e.op] .. "(" .. a .. ", " .. b .. ")"
  end
  if k == "UnaryOp" then return UNOP[e.op] .. "(" .. self:ex(e.operand) .. ")" end
  if k == "BoolOp" then
    local acc = self:val(e.values[#e.values])
    for i = #e.values - 1, 1, -1 do
      acc = (e.op == "and" and "and_" or "or_") .. "(" .. self:val(e.values[i]) .. ", function() return " .. acc .. " end)"
    end
    return acc
  end
  if k == "Compare" then return "(" .. self:compare(e) .. ")" end
  if k == "IfExp" then
    -- Rychlá cesta bez closure: s literálem v jedné větvi je Lua `and/or` přesné.
    if truthy_literal(e.body) then
      return "(" .. self:cond(e.test) .. " and " .. self:ex(e.body) .. " or " .. self:val(e.orelse) .. ")"
    end
    if truthy_literal(e.orelse) then
      return "(not " .. self:cond(e.test) .. " and " .. self:ex(e.orelse) .. " or " .. self:val(e.body) .. ")"
    end
    return "(function() if " .. self:cond(e.test) .. " then return " .. self:val(e.body)
      .. " end return " .. self:val(e.orelse) .. " end)()"
  end
  if k == "Call" then return self:call(e) end
  if k == "Method" then
    -- Rychlé cesty nejčastějších metod (o typu objektu rozhodne runtime, jinak obecná cesta).
    if e.name == "get" and (#e.args == 1 or #e.args == 2) then
      local a = { self:ex(e.obj), tostring(#e.args) }
      for _, arg in ipairs(e.args) do a[#a + 1] = self:val(arg) end
      return "mget(" .. table.concat(a, ", ") .. ")"
    end
    if e.name == "append" and #e.args == 1 then
      return "mappend(" .. self:ex(e.obj) .. ", " .. self:val(e.args[1]) .. ")"
    end
    local args = { self:ex(e.obj), string.format("%q", e.name) }
    for _, a in ipairs(e.args) do args[#args + 1] = self:val(a) end
    return "method(" .. table.concat(args, ", ") .. ")"
  end
  if k == "Subscript" then return "getitem(" .. self:ex(e.value) .. ", " .. self:ex(e.index) .. ")" end
  if k == "Slice" then
    return "slice(" .. self:ex(e.value) .. ", " .. (e.lower and self:ex(e.lower) or "nil") .. ", "
      .. (e.upper and self:ex(e.upper) or "nil") .. ")"
  end
  if k == "List" or k == "Tuple" then
    local parts = {}
    for i, v in ipairs(e.elts) do parts[i] = self:val(v) end
    return (k == "List" and "list" or "tuple") .. "({" .. table.concat(parts, ", ") .. "}, " .. #parts .. ")"
  end
  if k == "Dict" then
    local parts = {}
    for i, key in ipairs(e.keys) do
      parts[#parts + 1] = self:ex(key)
      parts[#parts + 1] = self:val(e.values[i])
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
      self:emit("do local _ = " .. self:val(v) .. " end")
    end
  elseif k == "Assign" then
    local t1 = s.targets[1]
    if #s.targets == 1 and t1.k ~= "Tuple" and t1.k ~= "List" then
      self:assign(t1, self:val(s.value))
    else
      local t = self:tmp()
      self:emit("do local " .. t .. " = " .. self:val(s.value))
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
    local t = s.target
    local pair_target = (t.k == "Tuple" or t.k == "List") and #t.elts == 2
    if it.k == "Method" and #it.args == 0 and (it.name == "keys" or it.name == "values"
        or (it.name == "items" and pair_target)) then
      -- Rychlá cesta: průchod polem bez seznamu a n-tic (R.items_array).
      local a, n, i = self:tmp(), self:tmp(), self:tmp()
      self:emit("do local " .. a .. ", " .. n .. " = items_array(" .. self:ex(it.obj) .. ", " .. string.format("%q", it.name) .. ")")
      self:emit("for " .. i .. " = 1, " .. n .. " do")
      self:emit(WD)
      self:emit("local " .. v .. " = " .. a .. "[" .. i .. "]")
      if it.name == "items" then
        self:assign(t.elts[1], v .. "[1]")
        self:assign(t.elts[2], v .. "[2]")
      else
        self:assign(t, v)
      end
      self:loop_body(s.body)
      self:emit("end end")
      return
    end
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
    -- _ln vrátit na řádek volajícího, jinak by chyba po návratu ukazovala do volané funkce
    self:emit("do local _r = " .. (s.value and self:val(s.value) or "None") .. "; _ln = _sl; return _r end")
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
  self.params = is_param
  self:emit("f_" .. fn.node.name .. " = function(" .. table.concat(params, ", ") .. ")")
  self:emit(WD)
  self:emit("local _sl = _ln")
  local locals = {}
  for name in pairs(fn.locals) do
    if not is_param[name] then locals[#locals + 1] = "l_" .. name end
  end
  table.sort(locals)
  if #locals > 0 then self:emit("local " .. table.concat(locals, ", ")) end
  self:stmts(fn.node.body)
  self:emit("_ln = _sl")
  self:emit("return None")
  self:emit("end")
  self.fn, self.params = nil, nil
end

--- Vygeneruje zdroj Lua: chunk vrací factory function(R, G, IO) → instance.
--- @param ast table Module (po checker.check)
--- @param info table výsledek checker.check
--- @return string
function M.generate(ast, info)
  local self = setmetatable({ out = {}, ntmp = 0, nlabel = 0, loops = {}, info = info }, Gen)
  self:emit("return function(R, G, IO)")
  self:emit("local None, B, type = R.None, R.builtins, R.lua_type")
  self:emit("local " .. table.concat(HELPERS, ", ") .. " = R." .. table.concat(HELPERS, ", R."))
  self:emit("local _b, _ln = 0, 0")
  self:emit("local function wd() R.watchdog() end")
  self:emit("local function print_(...) IO.print(print_line(...)) return None end")
  self:emit("local function nn(v) if v == nil then R.raise(\"unbound\") end return v end")
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
    .. " charge = function(n) _b = _b - n if _b < 0 then wd() end end,"
    .. " budget = function() return _b end, line = function() return _ln end }")
  self:emit("end")
  return table.concat(self.out, "\n")
end

return M
