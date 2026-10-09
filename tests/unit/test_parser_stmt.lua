local A = require("assert")
local parser = require("scripts.lang.parser")
local D = require("ast_dump")

--- Ověří výpis rozparsovaného programu.
local function ps(src, expected)
  A.eq(D.stmts(parser.parse(src).body), expected, src)
end

return {
  { "přiřazení a rozšířené přiřazení", function() ps("x = 1\ny += 2\n", "(= x 1); (+= y 2)") end },
  { "řetězené přiřazení a n-tice", function()
    ps("a = b = 0", "(= a b 0)")
    ps("a, b = b, a", "(= (tuple a b) (tuple b a))")
    ps("[a, b] = t", "(= [a b] t)")
  end },
  { "přiřazení do indexu", function() ps("d['k'] = 1", '(= (idx d "k") 1)') end },
  { "neplatný cíl", function()
    A.raises(function() parser.parse("f() = 1") end, "bad-target")
    A.raises(function() parser.parse("a + 1 = 2") end, "bad-target")
    A.raises(function() parser.parse("a, b += 1") end, "bad-target")
    A.raises(function() parser.parse("x[1:2] = y") end, "bad-target")
  end },
  { "if / elif / else", function()
    ps("if a:\n  x = 1\nelif b:\n  x = 2\nelse:\n  x = 3\n",
      "(if a {(= x 1)} {(if b {(= x 2)} {(= x 3)})})")
  end },
  { "jednořádkový blok", function() ps("if a: b = 1\nc = 2", "(if a {(= b 1)} {}); (= c 2)") end },
  { "while, break, continue", function()
    ps("while x:\n  if y: break\n  continue\n", "(while x {(if y {break} {}); continue})")
  end },
  { "for s vnořenou n-ticí", function()
    ps("for k, (lo, hi) in L.items():\n  pass\n", "(for (tuple k (tuple lo hi)) (.items L) {pass})")
    ps("for i in range(3): pass", "(for i (call range 3) {pass})")
  end },
  { "def, global, return", function()
    ps("def f(a, b):\n  global g\n  return a, b\n", "(def f (a b) {(global g); (return (tuple a b))})")
    ps("def g():\n  return\n", "(def g () {(return)})")
  end },
  { "chybějící odsazení", function()
    local e = A.raises(function() parser.parse("if a:\nb") end, "expected-indent")
    A.eq(e.line, 2, "řádek")
  end },
  { "nečekané odsazení", function()
    A.raises(function() parser.parse("a\n  b\n") end, "unexpected-indent")
  end },
  { "výchozí parametry nepodporované", function()
    A.raises(function() parser.parse("def f(a=1): pass") end, "defaults-unsupported")
  end },
  { "while-else nepodporované", function()
    A.raises(function() parser.parse("while a:\n  pass\nelse:\n  pass") end, "unexpected-token")
  end },
  { "výrazový příkaz a docstring", function()
    ps('"""doc"""\nprint(1)', '"doc"; (call print 1)')
  end },
  { "čísla řádků příkazů", function()
    local m = parser.parse("a = 1\n\nif b:\n  c = 2")
    A.eq(m.body[2].line, 3, "if")
    A.eq(m.body[2].body[1].line, 4, "tělo if")
  end },
  { "ukázkový program s hysterezí", function()
    local src = table.concat({
      "LIMITS = {",
      "    'iron-plate': (1000, 5000),",
      "}",
      "active = {}",
      "",
      "def hyst(key, value, low, high):",
      "    if value < low:",
      "        active[key] = True",
      "    elif value > high:",
      "        active[key] = False",
      "    return active.get(key, False)",
      "",
      "def loop():",
      "    for key, (low, high) in LIMITS.items():",
      "        if hyst(key, inp[key], low, high):",
      "            out['recipe:' + key] = 1",
    }, "\n")
    local m = parser.parse(src)
    A.eq(#m.body, 4, "počet příkazů na nejvyšší úrovni")
    A.eq(m.body[3].k, "Def", "hyst")
    A.eq(m.body[4].name, "loop", "loop")
  end },
}
