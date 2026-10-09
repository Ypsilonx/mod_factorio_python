--- Kontrola programu: rozsahy jmen, global/local, omezení jazyka, klíče signálů → kanonické řetězce.
local errors = require("scripts.lang.errors")
local signals = require("scripts.lang.signals")

local M = {}

M.SIGNAL_OBJS = { inp = "r", red = "r", green = "r", out = "w", out_red = "w", out_green = "w" }
M.READONLY = { tick = true, game_tick = true, dt = true }
M.BUILTINS = {}
for w in ("abs min max round int float str bool len range sum sorted print"):gmatch("%S+") do M.BUILTINS[w] = true end

--- Je uzel holé jméno objektu signálů?
local function is_sigobj(e) return e.k == "Name" and M.SIGNAL_OBJS[e.id] ~= nil end

--- Jména přiřazovaná cílem (uzly Name; Subscript nic nepřiřazuje).
local function target_names(t, out)
  if t.k == "Name" then
    out[#out + 1] = t
  elseif t.k == "Tuple" or t.k == "List" then
    for _, e in ipairs(t.elts) do target_names(e, out) end
  end
end

--- Projde příkazy včetně vnořených bloků (bez vstupu do Def) a zavolá f(stmt).
local function walk_stmts(body, f)
  for _, s in ipairs(body) do
    f(s)
    if s.k == "If" then
      walk_stmts(s.body, f)
      walk_stmts(s.orelse, f)
    elseif s.k == "While" or s.k == "For" then
      walk_stmts(s.body, f)
    end
  end
end

--- Uzly Name přiřazené v těle (Assign, AugAssign, For).
local function assigned_in(body)
  local names = {}
  walk_stmts(body, function(s)
    if s.k == "Assign" then
      for _, t in ipairs(s.targets) do target_names(t, names) end
    elseif s.k == "AugAssign" or s.k == "For" then
      target_names(s.target, names)
    end
  end)
  return names
end

local C = {}
C.__index = C

--- Je jméno vyhrazené (nelze přiřadit)?
function C:reserved(name)
  return self.info.functions[name] ~= nil or M.BUILTINS[name] or M.READONLY[name]
    or M.SIGNAL_OBJS[name] ~= nil or name == "config"
end

--- Ověří, že do jména (uzel Name) lze přiřadit.
function C:assignable(n)
  if self:reserved(n.id) then errors.raise(n.line, n.col, "reserved-name", n.id) end
end

--- Přepíše konstantní klíč signálu (Signal nebo Str) na kanonický Str; jiné uzly nechá být.
function C:resolve_key(node)
  local key
  if node.k == "Signal" then
    key = signals.from_tag(node.tag, node.name, node.quality)
  elseif node.k == "Str" then
    key = node.v
  else
    return
  end
  local _, canonical, err = self.resolver:resolve(key)
  if not canonical then
    err.line, err.col = node.line, node.col
    error(err, 0)
  end
  node.k, node.v, node.stype, node.tag, node.name, node.quality = "Str", canonical, nil, nil, nil, nil
end

--- Kontrola čteného jména.
function C:load_name(e, ctx)
  local id = e.id
  if ctx.fn and ctx.fn.locals[id] then return end
  if self.info.globals[id] or M.READONLY[id] then return end
  if self.info.functions[id] or M.BUILTINS[id] or id == "config" then
    errors.raise(e.line, e.col, "function-value", id)
  end
  if M.SIGNAL_OBJS[id] then errors.raise(e.line, e.col, "signal-value", id) end
  errors.raise(e.line, e.col, "unknown-name", id)
end

--- Kontrola výrazu.
function C:expr(e, ctx)
  local k = e.k
  if k == "Name" then
    self:load_name(e, ctx)
  elseif k == "Signal" then
    self:resolve_key(e)
  elseif k == "BinOp" then
    self:expr(e.left, ctx); self:expr(e.right, ctx)
  elseif k == "UnaryOp" then
    self:expr(e.operand, ctx)
  elseif k == "BoolOp" then
    for _, v in ipairs(e.values) do self:expr(v, ctx) end
  elseif k == "IfExp" then
    self:expr(e.test, ctx); self:expr(e.body, ctx); self:expr(e.orelse, ctx)
  elseif k == "Compare" then
    local operands = { e.left }
    for _, c in ipairs(e.comparators) do operands[#operands + 1] = c end
    for j, o in ipairs(operands) do
      local op = e.ops[j - 1]
      if (op == "in" or op == "not in") and is_sigobj(o) then
        self:resolve_key(operands[j - 1])
      else
        self:expr(o, ctx)
      end
    end
  elseif k == "Call" then
    self:call(e, ctx)
  elseif k == "Method" then
    if is_sigobj(e.obj) then
      if e.name == "get" and e.args[1] then self:resolve_key(e.args[1]) end
    else
      self:expr(e.obj, ctx)
    end
    for _, a in ipairs(e.args) do self:expr(a, ctx) end
  elseif k == "Subscript" then
    if is_sigobj(e.value) then
      self:resolve_key(e.index)
    else
      self:expr(e.value, ctx)
    end
    self:expr(e.index, ctx)
  elseif k == "Slice" then
    self:expr(e.value, ctx)
    if e.lower then self:expr(e.lower, ctx) end
    if e.upper then self:expr(e.upper, ctx) end
  elseif k == "List" or k == "Tuple" then
    for _, v in ipairs(e.elts) do self:expr(v, ctx) end
  elseif k == "Dict" then
    for i, key in ipairs(e.keys) do self:expr(key, ctx); self:expr(e.values[i], ctx) end
  end
end

--- Kontrola volání funkce.
function C:call(e, ctx)
  local name = e.func
  if name == "config" then errors.raise(e.line, e.col, "bad-config") end
  if #e.kwargs > 0 then errors.raise(e.kwargs[1].line, e.kwargs[1].col, "kwargs-unsupported") end
  local fn = self.info.functions[name]
  if fn then
    if #e.args ~= #fn.params then errors.raise(e.line, e.col, "arg-count", name, #fn.params, #e.args) end
  elseif not M.BUILTINS[name] then
    if (ctx.fn and ctx.fn.locals[name]) or self.info.globals[name] or M.READONLY[name] or M.SIGNAL_OBJS[name] then
      errors.raise(e.line, e.col, "not-callable")
    end
    errors.raise(e.line, e.col, "unknown-name", name)
  end
  for _, a in ipairs(e.args) do
    if not (name == "len" and is_sigobj(a)) then self:expr(a, ctx) end
  end
end

--- Kontrola cíle přiřazení (čtení indexů, zápis do objektů signálů).
function C:target(t, ctx)
  if t.k == "Subscript" then
    if is_sigobj(t.value) then
      if M.SIGNAL_OBJS[t.value.id] == "r" then errors.raise(t.line, t.col, "readonly-signal", t.value.id) end
      self:resolve_key(t.index)
    else
      self:expr(t.value, ctx)
    end
    self:expr(t.index, ctx)
  elseif t.k == "Tuple" or t.k == "List" then
    for _, el in ipairs(t.elts) do self:target(el, ctx) end
  end
end

--- Zpracuje config() na nejvyšší úrovni.
function C:config(call, ctx)
  if ctx.fn or not ctx.top or #call.args > 0 then errors.raise(call.line, call.col, "bad-config") end
  for _, kw in ipairs(call.kwargs) do
    local v = kw.value
    if kw.name == "interval" and v.k == "Num" and v.v >= 1 and v.v == math.floor(v.v) then
      self.info.config.interval = v.v
    elseif kw.name == "outputs" and v.k == "Str" and (v.v == "hold" or v.v == "clear") then
      self.info.config.outputs = v.v
    else
      errors.raise(kw.line, kw.col, "bad-config")
    end
  end
end

--- Podkontext bloku (už ne přímo nejvyšší úroveň).
local function sub(ctx, loops) return { fn = ctx.fn, loops = loops or ctx.loops, top = false } end

--- Kontrola příkazu.
function C:stmt(s, ctx)
  local k = s.k
  if k == "Def" then
    if ctx.fn or not ctx.top then errors.raise(s.line, s.col, "nested-def") end
    self:stmts(s.body, { fn = self.info.functions[s.name], loops = 0, top = false })
  elseif k == "Assign" then
    self:expr(s.value, ctx)
    for _, t in ipairs(s.targets) do self:target(t, ctx) end
  elseif k == "AugAssign" then
    self:expr(s.target, ctx)
    self:target(s.target, ctx)
    self:expr(s.value, ctx)
  elseif k == "Expr" then
    if s.value.k == "Call" and s.value.func == "config" then
      self:config(s.value, ctx)
    else
      self:expr(s.value, ctx)
    end
  elseif k == "If" then
    self:expr(s.test, ctx)
    self:stmts(s.body, sub(ctx))
    self:stmts(s.orelse, sub(ctx))
  elseif k == "While" then
    self:expr(s.test, ctx)
    self:stmts(s.body, sub(ctx, ctx.loops + 1))
  elseif k == "For" then
    self:expr(s.iter, ctx)
    self:target(s.target, ctx)
    self:stmts(s.body, sub(ctx, ctx.loops + 1))
  elseif k == "Return" then
    if not ctx.fn then errors.raise(s.line, s.col, "return-outside") end
    if s.value then self:expr(s.value, ctx) end
  elseif k == "Break" or k == "Continue" then
    if ctx.loops == 0 then errors.raise(s.line, s.col, "outside-loop", k == "Break" and "break" or "continue") end
  end
end

function C:stmts(body, ctx)
  for _, s in ipairs(body) do self:stmt(s, ctx) end
end

--- Zkontroluje program a přepíše konstantní klíče signálů na kanonické.
--- @param ast table Module z parser.parse
--- @param resolver table z signals.new_resolver
--- @return table info {globals, functions, config}
function M.check(ast, resolver)
  local info = { globals = {}, functions = {}, config = { interval = 1, outputs = "hold" } }
  local self = setmetatable({ info = info, resolver = resolver }, C)
  local defs = {}
  for _, s in ipairs(ast.body) do
    if s.k == "Def" then
      if info.functions[s.name] then errors.raise(s.line, s.col, "duplicate-def", s.name) end
      if M.BUILTINS[s.name] or M.READONLY[s.name] or M.SIGNAL_OBJS[s.name] or s.name == "config" then
        errors.raise(s.line, s.col, "reserved-name", s.name)
      end
      info.functions[s.name] = { node = s, params = s.params, locals = {}, global_decl = {} }
      defs[#defs + 1] = info.functions[s.name]
    end
  end
  local loop = info.functions.loop
  if not loop then errors.raise(1, 1, "missing-loop") end
  if #loop.params > 0 then errors.raise(loop.node.line, loop.node.col, "loop-params") end

  for _, n in ipairs(assigned_in(ast.body)) do
    self:assignable(n)
    info.globals[n.id] = true
  end
  for _, fn in ipairs(defs) do
    walk_stmts(fn.node.body, function(s)
      if s.k == "Global" then
        for _, g in ipairs(s.names) do fn.global_decl[g] = true; info.globals[g] = true end
      end
    end)
  end
  for _, fn in ipairs(defs) do
    for _, p in ipairs(fn.params) do fn.locals[p] = true end
    for _, n in ipairs(assigned_in(fn.node.body)) do
      self:assignable(n)
      if not fn.global_decl[n.id] and not fn.locals[n.id] then
        if info.globals[n.id] then errors.raise(n.line, n.col, "missing-global", n.id) end
        fn.locals[n.id] = true
      end
    end
  end

  self:stmts(ast.body, { fn = nil, loops = 0, top = true })
  return info
end

return M
