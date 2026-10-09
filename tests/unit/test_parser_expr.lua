local A = require("assert")
local parser = require("scripts.lang.parser")
local D = require("ast_dump")

--- Ověří výpis rozparsovaného výrazu.
local function px(src, expected)
  A.eq(D.expr(parser.parse_expression(src)), expected, src)
end

return {
  { "priorita + a *", function() px("1 + 2 * 3", "(+ 1 (* 2 3))") end },
  { "levá asociativita", function() px("a - b - c", "(- (- a b) c)") end },
  { "mocnina a unární minus", function()
    px("-2 ** 2", "(- (** 2 2))")
    px("2 ** -1", "(** 2 (- 1))")
    px("a ** b ** c", "(** a (** b c))")
  end },
  { "bitové operátory", function() px("a | b ^ c & d << 1", "(| a (^ b (& c (<< d 1))))") end },
  { "řetězené porovnání", function() px("0 < x <= 10", "(cmp 0 < x <= 10)") end },
  { "in, not in, is not", function()
    px("a not in b", "(cmp a not in b)")
    px("a in b", "(cmp a in b)")
    px("a is not None", "(cmp a is not None)")
    px("a is None", "(cmp a is None)")
  end },
  { "logické operátory", function() px("not a and b or c", "(or (and (not a) b) c)") end },
  { "podmíněný výraz", function() px("x if c else y", "(if c x y)") end },
  { "volání a pojmenované argumenty", function()
    px("config(interval=10)", "(call config interval=10)")
    px("max(a, b,)", "(call max a b)")
    px("f()", "(call f)")
  end },
  { "metody i řetězené", function()
    px("x.append(1)", "(.append x 1)")
    px("s.upper().lower()", "(.lower (.upper s))")
  end },
  { "index a řez", function()
    px("a[1]", "(idx a 1)")
    px("a[1:]", "(slice a 1 _)")
    px("a[:-1]", "(slice a _ (- 1))")
    px("a[:]", "(slice a _ _)")
  end },
  { "literály kolekcí", function()
    px("[1, 2,]", "[1 2]")
    px("[]", "[]")
    px("(1,)", "(tuple 1)")
    px("()", "(tuple)")
    px("(1)", "1")
    px("{'a': 1, 'b': 2}", '{"a":1 "b":2}')
    px("{}", "{}")
  end },
  { "n-tice bez závorek", function() px("a, b", "(tuple a b)") end },
  { "spojení sousedních řetězců", function() px("'a' 'b'", '"ab"') end },
  { "konstanty", function() px("[True, False, None]", "[True False None]") end },
  { "signál v indexu", function()
    px("inp[[item=iron-plate,quality=rare]]", "(idx inp <item:iron-plate@rare>)")
  end },
  { "chyby", function()
    A.raises(function() parser.parse_expression("f(x)(y)") end, "not-callable")
    A.raises(function() parser.parse_expression("a.b") end, "attribute-unsupported")
    A.raises(function() parser.parse_expression("[x for x in y]") end, "unsupported")
    A.raises(function() parser.parse_expression("a[1:2:3]") end, "unsupported")
    A.raises(function() parser.parse_expression("1 +") end, "unexpected-newline")
    A.raises(function() parser.parse_expression("x.f(a=1)") end, "kwargs-unsupported")
    A.raises(function() parser.parse_expression("f(a=1, 2)") end, "unexpected-token")
    A.raises(function() parser.parse_expression("(1, 2") end, "unexpected-newline")
    A.raises(function() parser.parse_expression("f(*a)") end, "unsupported")
  end },
  { "pozice uzlu", function()
    local e = parser.parse_expression("a +\\\n b")
    A.eq(e.right.line, 2, "řádek pravého operandu")
  end },
}
