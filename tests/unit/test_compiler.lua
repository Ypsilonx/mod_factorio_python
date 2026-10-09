local A = require("assert")
local P = require("prog_runner")
local compiler = require("scripts.lang.compiler")
local vm = require("scripts.lang.vm")
local signals = require("scripts.lang.signals")
local fake = require("fake_protos")

--- Spustí program a ověří výstup print (řádky spojené "|").
local function prints(src, expected, ticks)
  local res, err = P.run(src, ticks)
  if not res then error(err, 0) end
  A.eq(res.lines, expected, src)
  return res
end

--- Spustí program a ověří chybu běhu; vrátí ji.
local function fails(src, key, ticks)
  local res, err = P.run(src, ticks)
  A.eq(res, nil, "čekána chyba " .. key)
  A.eq(err.key, "pyntr-err." .. key, "klíč chyby")
  return err
end

return {
  { "print a aritmetika", function() prints("def loop():\n  print(1 + 2, 'a' * 2)", "3 aa") end },
  { "globály přežijí tick", function()
    local res = prints("count = 0\ndef loop():\n  global count\n  count += 1\n  print(count)", "1|2|3", 3)
    A.eq(res.G.count, 3, "G.count")
  end },
  { "hoisting funkcí a print v inicializaci", function()
    prints("print(f(2))\ndef f(x):\n  return x * 2\ndef loop(): pass", "4")
  end },
  { "rekurze", function()
    prints("def fib(n):\n  if n < 2:\n    return n\n  return fib(n - 1) + fib(n - 2)\ndef loop():\n  print(fib(10))", "55")
  end },
  { "while, break, continue", function()
    prints(table.concat({
      "def loop():",
      "  i = 0",
      "  s = 0",
      "  while True:",
      "    i += 1",
      "    if i > 9:",
      "      break",
      "    if i % 2 == 0:",
      "      continue",
      "    s += i",
      "  print(s)",
    }, "\n"), "25")
  end },
  { "for přes range ve všech tvarech", function()
    prints(table.concat({
      "def loop():",
      "  a = []",
      "  for i in range(3):",
      "    a.append(i)",
      "  for i in range(5, 0, -2):",
      "    a.append(i)",
      "  print(a, i)",
    }, "\n"), "[0, 1, 2, 5, 3, 1] 1")
  end },
  { "continue po rozbalení n-tice", function()
    prints(table.concat({
      "def loop():",
      "  d = {'a': 1, 'b': 2, 'c': 3}",
      "  s = 0",
      "  for k, v in d.items():",
      "    if k == 'b':",
      "      continue",
      "    s += v",
      "  print(s)",
    }, "\n"), "4")
  end },
  { "řetězené porovnání se zkratem", function()
    prints(table.concat({
      "def f(x):",
      "  print('f')",
      "  return x",
      "def loop():",
      "  print(0 < f(5) < 10)",
      "  print(5 < f(1) < f(9))",
    }, "\n"), "f|True|f|False")
  end },
  { "and/or vrací operand, podmíněný výraz", function()
    prints("def loop():\n  print(0 or 5, '' and 1, 1 and 2)\n  print('ano' if [] else 'ne')", "5  2|ne")
  end },
  { "rozbalení a řetězené přiřazení", function()
    prints("def loop():\n  a, b = 1, 2\n  a, b = b, a\n  x = y = []\n  x.append(1)\n  print(a, b, y)", "2 1 [1]")
  end },
  { "rozšířené přiřazení do indexu", function()
    prints("def loop():\n  d = {'k': 1}\n  d['k'] += 5\n  print(d)", "{'k': 6}")
  end },
  { "signály a config", function()
    local res = P.run(table.concat({
      "config(interval=5)",
      "def loop():",
      "  if inp['iron-plate'] > 100:",
      "    out['signal-A'] = 1",
      "  out[[recipe=iron-plate]] = 2",
      "  for k, v in inp.items():",
      "    print(k, v)",
    }, "\n"), 1, { ["iron-plate"] = 150 })
    A.same(res.out, { ["signal-A"] = 1, ["recipe:iron-plate"] = 2 }, "výstupy")
    A.eq(res.lines, "iron-plate 150", "items")
    A.eq(res.prog.config.interval, 5, "interval")
  end },
  { "chyba za běhu hlásí řádek Pythonu i ve funkci", function()
    local e = fails("def f(x):\n  return x // 0\ndef loop():\n  f(1)", "zero-division")
    A.eq(e.line, 2, "řádek")
  end },
  { "chyba v podmínce elif hlásí řádek elif", function()
    A.eq(fails("def loop():\n  x = 1\n  if x == 2:\n    pass\n  elif x // 0:\n    pass", "zero-division").line, 5, "řádek")
  end },
  { "chyba v inicializaci", function()
    A.eq(fails("x = 1 // 0\ndef loop(): pass", "zero-division").line, 1, "řádek")
  end },
  { "watchdog zastaví nekonečnou smyčku", function()
    local e = fails("def loop():\n  x = 0\n  while x < 10:\n    pass", "watchdog")
    A.eq(e.line, 3, "řádek"); A.eq(e.args[1], "10000", "limit")
  end },
  { "watchdog zastaví nekonečnou rekurzi", function()
    fails("def f():\n  return f() + 1\ndef loop():\n  f()", "watchdog")
  end },
  { "proměnná před přiřazením", function()
    A.eq(fails("def loop():\n  if False:\n    x = 1\n  print(x)", "unbound").line, 4, "řádek")
  end },
  { "watchdog a rozpočet: spotřeba", function()
    local prog = P.program("def loop():\n  for i in range(10):\n    pass")
    local inst = vm.instantiate(prog, {}, { print = print })
    local ok, _, used = vm.run(inst, "loop", 100)
    A.eq(ok, true, "běh"); A.eq(used, 11, "1 vstup do funkce + 10 průchodů")
  end },
  { "pojistka paměti", function()
    local res = P.run("log = []\ndef loop():\n  log.append(1)", 6)
    local total, biggest = vm.memory(res.G, 5)
    A.truthy(total > 5, "překročeno"); A.eq(biggest, "log", "největší")
    A.eq(vm.check_memory(res.G, 5).key, "pyntr-err.memory", "chyba")
    A.eq(vm.check_memory(res.G, 100), nil, "pod limitem")
  end },
  { "paměť s cyklem a sdílenou referencí", function()
    local res = P.run("a = []\na.append(a)\nb = a\ndef loop(): pass")
    local total = vm.memory(res.G, 100)
    A.eq(total, 1, "cyklus i sdílená reference se počítají jednou")
  end },
  { "chyba překladu se vrátí, nevyhodí", function()
    local prog, err = compiler.compile("def loop():\n  x = y", signals.new_resolver(fake()))
    A.eq(prog, nil, "program"); A.eq(err.key, "pyntr-err.unknown-name", "klíč"); A.eq(err.line, 2, "řádek")
  end },
  { "vygenerovaný kód nepoužívá operátory Lua 5.3", function()
    local lua = P.program("def loop():\n  x = 7 // 2 + (5 & 3) + (1 << 2) + (~1)\n  print(x)").lua
    for _, op in ipairs({ "//", " & ", " | ", "<<", ">>", " ~" }) do
      A.eq(lua:find(op, 1, true), nil, "operátor " .. op)
    end
  end },
}
