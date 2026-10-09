--- Kompaktní textový výpis AST (S-výrazy) pro čitelné aserce v testech.
local D = {}

--- Spojí výpisy seznamu uzlů oddělovačem.
local function join(list, f, sep)
  local out = {}
  for i, v in ipairs(list) do out[i] = f(v) end
  return table.concat(out, sep or " ")
end

--- Číslo bez závislosti na tostring Lua 5.2/5.3.
local function num(v)
  if v == math.floor(v) then return string.format("%d", v) end
  return string.format("%.17g", v)
end

--- Výpis výrazu.
function D.expr(e)
  local k = e.k
  if k == "Name" then return e.id end
  if k == "Num" then return num(e.v) end
  if k == "Str" then return '"' .. e.v .. '"' end
  if k == "Bool" then return e.v and "True" or "False" end
  if k == "None" then return "None" end
  if k == "Signal" then return "<" .. e.stype .. ":" .. e.name .. "@" .. e.quality .. ">" end
  if k == "BinOp" then return "(" .. e.op .. " " .. D.expr(e.left) .. " " .. D.expr(e.right) .. ")" end
  if k == "UnaryOp" then return "(" .. e.op .. " " .. D.expr(e.operand) .. ")" end
  if k == "BoolOp" then return "(" .. e.op .. " " .. join(e.values, D.expr) .. ")" end
  if k == "Compare" then
    local s = "(cmp " .. D.expr(e.left)
    for i, op in ipairs(e.ops) do s = s .. " " .. op .. " " .. D.expr(e.comparators[i]) end
    return s .. ")"
  end
  if k == "IfExp" then return "(if " .. D.expr(e.test) .. " " .. D.expr(e.body) .. " " .. D.expr(e.orelse) .. ")" end
  if k == "Call" then
    local s = "(call " .. e.func
    for _, a in ipairs(e.args) do s = s .. " " .. D.expr(a) end
    for _, kw in ipairs(e.kwargs) do s = s .. " " .. kw.name .. "=" .. D.expr(kw.value) end
    return s .. ")"
  end
  if k == "Method" then
    local s = "(." .. e.name .. " " .. D.expr(e.obj)
    for _, a in ipairs(e.args) do s = s .. " " .. D.expr(a) end
    return s .. ")"
  end
  if k == "Subscript" then return "(idx " .. D.expr(e.value) .. " " .. D.expr(e.index) .. ")" end
  if k == "Slice" then
    return "(slice " .. D.expr(e.value) .. " " .. (e.lower and D.expr(e.lower) or "_") .. " "
      .. (e.upper and D.expr(e.upper) or "_") .. ")"
  end
  if k == "List" then return "[" .. join(e.elts, D.expr) .. "]" end
  if k == "Tuple" then return #e.elts == 0 and "(tuple)" or "(tuple " .. join(e.elts, D.expr) .. ")" end
  if k == "Dict" then
    local parts = {}
    for i, key in ipairs(e.keys) do parts[i] = D.expr(key) .. ":" .. D.expr(e.values[i]) end
    return "{" .. table.concat(parts, " ") .. "}"
  end
  error("neznámý uzel " .. tostring(k))
end

--- Výpis příkazu.
function D.stmt(s)
  local k = s.k
  if k == "Assign" then return "(= " .. join(s.targets, D.expr) .. " " .. D.expr(s.value) .. ")" end
  if k == "AugAssign" then return "(" .. s.op .. "= " .. D.expr(s.target) .. " " .. D.expr(s.value) .. ")" end
  if k == "Expr" then return D.expr(s.value) end
  if k == "If" then return "(if " .. D.expr(s.test) .. " {" .. D.stmts(s.body) .. "} {" .. D.stmts(s.orelse) .. "})" end
  if k == "While" then return "(while " .. D.expr(s.test) .. " {" .. D.stmts(s.body) .. "})" end
  if k == "For" then return "(for " .. D.expr(s.target) .. " " .. D.expr(s.iter) .. " {" .. D.stmts(s.body) .. "})" end
  if k == "Def" then return "(def " .. s.name .. " (" .. table.concat(s.params, " ") .. ") {" .. D.stmts(s.body) .. "})" end
  if k == "Return" then return s.value and "(return " .. D.expr(s.value) .. ")" or "(return)" end
  if k == "Global" then return "(global " .. table.concat(s.names, " ") .. ")" end
  if k == "Pass" then return "pass" end
  if k == "Break" then return "break" end
  if k == "Continue" then return "continue" end
  error("neznámý příkaz " .. tostring(k))
end

--- Výpis seznamu příkazů oddělený "; ".
function D.stmts(list) return join(list, D.stmt, "; ") end

return D
