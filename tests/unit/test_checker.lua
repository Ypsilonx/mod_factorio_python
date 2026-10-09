local A = require("assert")
local parser = require("scripts.lang.parser")
local checker = require("scripts.lang.checker")
local signals = require("scripts.lang.signals")
local fake = require("fake_protos")

--- Rozparsuje a zkontroluje zdroj; vrátí info a AST.
local function check(src)
  local ast = parser.parse(src)
  return checker.check(ast, signals.new_resolver(fake())), ast
end

--- Ověří chybu kontroly a vrátí ji.
local function bad(src, key) return A.raises(function() check(src) end, key) end

return {
  { "minimální program", function()
    local info = check("def loop():\n  pass")
    A.same(info.config, { interval = 1, outputs = "hold" }, "výchozí config")
  end },
  { "chybí loop / loop s parametry", function()
    bad("x = 1", "missing-loop")
    bad("def loop(a):\n  pass", "loop-params")
  end },
  { "globální a lokální jména", function()
    local info = check("count = 0\ndef loop():\n  global count\n  x = 1\n  count += x")
    A.eq(info.globals.count, true, "count je globál")
    A.eq(info.functions.loop.locals.x, true, "x je lokální")
    A.eq(info.functions.loop.locals.count, nil, "count není lokální")
  end },
  { "chybějící global", function()
    local e = bad("count = 0\ndef loop():\n  count += 1", "missing-global")
    A.eq(e.line, 3, "řádek"); A.eq(e.args[1], "count", "jméno")
  end },
  { "mutace globálu bez global je OK", function()
    check("d = {}\ndef loop():\n  d['a'] = 1\n  d.clear()")
  end },
  { "neznámé jméno", function()
    A.eq(bad("def loop():\n  x = y", "unknown-name").args[1], "y", "jméno")
  end },
  { "funkce není hodnota", function()
    bad("def f():\n  pass\ndef loop():\n  x = f", "function-value")
    bad("def loop():\n  x = len", "function-value")
  end },
  { "vyhrazená jména", function()
    bad("def loop():\n  tick = 1", "reserved-name")
    bad("inp = 1\ndef loop(): pass", "reserved-name")
    bad("def len(x): pass\ndef loop(): pass", "reserved-name")
    bad("def f(): pass\nf = 1\ndef loop(): pass", "reserved-name")
  end },
  { "vnořená a podmíněná definice", function()
    bad("def loop():\n  def g():\n    pass", "nested-def")
    bad("if True:\n  def f():\n    pass\ndef loop(): pass", "nested-def")
  end },
  { "dvojí definice", function() bad("def loop(): pass\ndef loop(): pass", "duplicate-def") end },
  { "počet argumentů", function()
    A.same(bad("def f(a):\n  return a\ndef loop():\n  f(1, 2)", "arg-count").args, { "f", "1", "2" }, "argumenty")
  end },
  { "break / return mimo kontext", function()
    A.eq(bad("def loop():\n  break", "outside-loop").args[1], "break", "break")
    check("def loop():\n  for i in range(3):\n    if i: continue\n    break")
    bad("return 1\ndef loop(): pass", "return-outside")
  end },
  { "config", function()
    local info = check("config(interval=10, outputs='clear')\ndef loop(): pass")
    A.same(info.config, { interval = 10, outputs = "clear" }, "hodnoty")
    bad("config(interval=0)\ndef loop(): pass", "bad-config")
    bad("config(5)\ndef loop(): pass", "bad-config")
    bad("def loop():\n  config(interval=2)", "bad-config")
    bad("x = config(interval=2)\ndef loop(): pass", "bad-config")
  end },
  { "klíče signálů se přepíšou na kanonické", function()
    local _, ast = check("def loop():\n  out['signal-A'] = inp[[item=iron-plate]]\n  y = inp['item:iron-plate']")
    local body = ast.body[1].body
    A.same({ body[1].targets[1].index.k, body[1].targets[1].index.v }, { "Str", "signal-A" }, "cíl")
    A.same({ body[1].value.index.k, body[1].value.index.v }, { "Str", "iron-plate" }, "tag")
    A.eq(body[2].value.index.v, "iron-plate", "zbytečný prefix")
  end },
  { "neznámý klíč signálu s pozicí", function()
    local e = bad("def loop():\n  x = inp['iron-plates']", "unknown-signal")
    A.eq(e.line, 2, "řádek"); A.eq(e.col, 11, "sloupec")
  end },
  { "vstup nelze zapisovat", function()
    A.eq(bad("def loop():\n  inp['signal-A'] = 1", "readonly-signal").args[1], "inp", "jméno")
  end },
  { "objekt signálů jen v povolených místech", function()
    bad("def loop():\n  x = inp", "signal-value")
    local _, ast = check(table.concat({
      "def loop():",
      "  n = len(inp)",
      "  b = 'signal-A' in inp",
      "  v = red.get([virtual-signal=signal-B], 0)",
      "  for k, v in green.items():",
      "    pass",
    }, "\n"))
    local body = ast.body[1].body
    A.eq(body[2].value.left.v, "signal-A", "klíč u in")
    A.eq(body[3].value.args[1].v, "signal-B", "klíč u get")
  end },
  { "signál jako hodnota mimo index", function()
    local _, ast = check("K = [virtual-signal=signal-A]\ndef loop(): pass")
    A.same({ ast.body[1].value.k, ast.body[1].value.v }, { "Str", "signal-A" }, "konstanta")
  end },
  { "dynamický klíč se neověřuje", function()
    check("def loop():\n  k = 'xyz'\n  y = inp[k]")
  end },
  { "nevolatelné a pojmenované argumenty", function()
    bad("x = 1\ndef loop():\n  x()", "not-callable")
    bad("def f(a):\n  return a\ndef loop():\n  f(a=1)", "kwargs-unsupported")
  end },
  { "parametr smí zastínit globál", function()
    check("a = 1\ndef f(a):\n  return a\ndef loop():\n  f(2)")
  end },
}
