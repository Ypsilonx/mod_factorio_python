local A = require("assert")
local R = require("scripts.lang.builtins")
local B = R.builtins

local function L(...) local a = { ... }; return R.list(a, select("#", ...)) end

return {
  { "abs, min, max", function()
    A.eq(B.abs(-4), 4, "abs"); A.eq(B.min(3, 1, 2), 1, "min argumentů")
    A.eq(B.max(L(4, 9, 2)), 9, "max iterovatelného"); A.eq(B.max("a", "b"), "b", "max str")
    A.raises(function() B.min(L()) end, "empty-sequence")
    A.raises(function() B.abs() end, "arg-count")
  end },
  { "round – bankéřské zaokrouhlení", function()
    A.eq(B.round(2.5), 2, "2.5"); A.eq(B.round(3.5), 4, "3.5"); A.eq(B.round(-2.5), -2, "-2.5")
    A.eq(B.round(1.234, 2), 1.23, "na 2 místa")
    A.eq(B.round(7), 7, "celé")
  end },
  { "int, float, str, bool", function()
    A.eq(B.int(-3.7), -3, "ořez k nule"); A.eq(B.int(" 12 "), 12, "z textu"); A.eq(B.int(true), 1, "bool")
    A.raises(function() B.int("1.5") end, "bad-int")
    A.eq(B.float("2.5"), 2.5, "float z textu"); A.raises(function() B.float("x") end, "bad-float")
    A.eq(B.str(L(1)), "[1]", "str"); A.eq(B.bool(L()), false, "bool")
  end },
  { "len, range, sum, sorted", function()
    A.eq(B.len("abc"), 3, "str"); A.eq(B.len(L(1, 2)), 2, "list")
    A.eq(R.repr(B.range(3)), "[0, 1, 2]", "range(3)"); A.eq(R.repr(B.range(5, 1, -2)), "[5, 3]", "záporný krok")
    A.raises(function() B.range(1, 2, 0) end, "range-step-zero")
    A.eq(B.sum(L(1, 2, 3)), 6, "sum"); A.eq(B.sum(L(1), 10), 11, "sum se startem")
    A.eq(R.repr(B.sorted(L(3, 1, 2))), "[1, 2, 3]", "sorted")
    A.raises(function() B.len(5) end, "type-error-unary")
  end },
  { "range_bounds pro číselný for", function()
    A.same({ R.range_bounds(0, 3, 1) }, { 0, 2, 1 }, "0..2")
    A.same({ R.range_bounds(5, 1, -2) }, { 5, 2, -2 }, "sestupně")
    A.raises(function() R.range_bounds(0, 3, 0) end, "range-step-zero")
    A.raises(function() R.range_bounds(0, 2.5, 1) end, "bad-int")
  end },
  { "metody listu", function()
    local l = L(1, 2)
    R.method(l, "append", 3); A.eq(R.repr(l), "[1, 2, 3]", "append")
    A.eq(R.method(l, "pop"), 3, "pop"); A.eq(R.method(l, "pop", 0), 1, "pop(0)")
    R.method(l, "insert", 0, 9); A.eq(R.repr(l), "[9, 2]", "insert")
    R.method(l, "remove", 9); A.eq(R.method(l, "index", 2), 0, "index")
    R.method(l, "clear"); A.raises(function() R.method(l, "pop") end, "pop-empty")
    A.raises(function() R.method(l, "remove", 5) end, "not-in-list")
    A.raises(function() R.method(l, "nope") end, "unknown-method")
  end },
  { "metody dict", function()
    local d = R.dict({ "a", 1 }, 2)
    A.eq(R.method(d, "get", "a"), 1, "get"); A.eq(R.method(d, "get", "x", 5), 5, "get s výchozí")
    A.eq(R.is_(R.method(d, "get", "x"), R.None), true, "get bez výchozí = None")
    A.eq(R.repr(R.method(d, "items")), "[('a', 1)]", "items")
    A.eq(R.repr(R.method(d, "keys")), "['a']", "keys"); A.eq(R.repr(R.method(d, "values")), "[1]", "values")
    A.eq(R.method(d, "pop", "a"), 1, "pop"); A.raises(function() R.method(d, "pop", "a") end, "key-error")
    A.eq(R.method(d, "pop", "a", 0), 0, "pop s výchozí")
  end },
  { "metody str", function()
    A.eq(R.method("Ab", "upper"), "AB", "upper"); A.eq(R.method("Ab", "lower"), "ab", "lower")
    A.eq(R.method("abc", "startswith", "ab"), true, "startswith"); A.eq(R.method("abc", "endswith", "bc"), true, "endswith")
    A.eq(R.repr(R.method("a,b", "split", ",")), "['a', 'b']", "split oddělovač")
    A.eq(R.repr(R.method(" a  b ", "split")), "['a', 'b']", "split mezery")
    A.eq(R.method("-", "join", L("a", "b")), "a-b", "join")
    A.eq(R.method("a.b.c", "replace", ".", "-"), "a-b-c", "replace bez vzorů Lua")
  end },
  { "print_line a watchdog", function()
    A.eq(R.print_line(1, "a", R.None, L(2)), "1 a None [2]", "print")
    A.raises(function() R.watchdog() end, "watchdog")
  end },
}
