--- Testy oprav ze závěrečné kontroly: obejití watchdogu, řádky chyb, robustní překlad, NaN, paměť, unbound, locale.
local A = require("assert")
local P = require("prog_runner")
local R = require("scripts.lang.builtins")
local compiler = require("scripts.lang.compiler")
local lexer = require("scripts.lang.lexer")
local signal_io = require("scripts.lang.signal_io")
local signals = require("scripts.lang.signals")
local vm = require("scripts.lang.vm")
local fake = require("fake_protos")

--- Spustí program a ověří chybu běhu; vrátí ji.
local function fails(src, key, ticks)
  local res, err = P.run(src, ticks)
  A.eq(res, nil, "čekána chyba " .. key)
  A.eq(err.key, "pyntr-err." .. key, "klíč chyby")
  return err
end

--- Přeloží zdroj a ověří chybu překladu (vrácenou, ne vyhozenou).
local function compile_fails(src, key)
  local ok, prog, err = pcall(compiler.compile, src, signals.new_resolver(fake()))
  A.eq(ok, true, "compile nesmí vyhodit chybu Lua: " .. tostring(prog))
  A.eq(prog, nil, "program")
  A.eq(err.key, "pyntr-err." .. key, "klíč chyby")
  return err
end

--- Spustí fn s českým locale (strcoll/isalpha se liší od "C") a locale vždy vrátí.
local function with_czech_locale(fn)
  local old = os.setlocale(nil, "all")
  A.truthy(os.setlocale("Czech", "all"), "české locale není k dispozici")
  local ok, err = pcall(fn)
  os.setlocale(old, "all")
  if not ok then error(err, 0) end
end

return {
  { "watchdog: vestavěné funkce platí za každý prvek", function()
    fails("def loop():\n  x = len(range(10000000))", "watchdog")
    fails("def loop():\n  x = 'x' * 100000000", "watchdog")
    fails("def loop():\n  x = [0] * 10000000", "watchdog")
    fails("def loop():\n  s = 'ab'\n  for i in range(27):\n    s = s + s", "watchdog")
    fails("def loop():\n  big = [0] * 9000\n  x = sorted(big)", "watchdog")
  end },
  { "watchdog: běžná práce pod limitem projde", function()
    local res = P.run("def loop():\n  print(sum(range(2000)), len('x' * 3000))")
    A.eq(res.lines, "1999000 3000", "výstup")
  end },
  { "paměť: řetězce se počítají podle délky", function()
    A.eq(vm.memory({ a = string.rep("x", 1000) }, 100), 11, "1 + 1000 // 100")
  end },
  { "řádek chyby po návratu z funkce", function()
    A.eq(fails("def f():\n  return 0\ndef loop():\n  x = f() + 1 / 0", "zero-division").line, 4, "po return")
    A.eq(fails("def g():\n  pass\ndef loop():\n  g()\n  y = [1][5]", "index-error").line, 5, "po implicitním return")
  end },
  { "překlad příliš složitého kódu vrátí chybu jazyka", function()
    compile_fails("x = " .. string.rep("1 + ", 300) .. "1\ndef loop(): pass", "too-complex")
    compile_fails("def loop():\n  print(" .. string.rep("1, ", 300) .. "1)", "too-complex")
    compile_fails(string.rep("(", 200000), "too-complex")
    local defs = {}
    for i = 1, 170 do defs[i] = "def f" .. i .. "(): pass" end
    compile_fails(table.concat(defs, "\n") .. "\ndef loop(): pass", "too-complex")
  end },
  { "NaN a nekonečno nesmí na výstup", function()
    fails("def loop():\n  out['signal-A'] = 1e300 * 1e300", "overflow")
    fails("def loop():\n  x = 1e300 * 1e300\n  out['signal-A'] = x - x", "overflow")
  end },
  { "kontrola paměti zvládne hluboké vnoření", function()
    local a = R.list({}, 0)
    for _ = 1, 200000 do a = R.list({ a }, 1) end
    local ok, err = pcall(vm.check_memory, { a = a }, 10000)
    A.eq(ok, true, "bez přetečení zásobníku: " .. tostring(err))
    A.eq(err.key, "pyntr-err.memory", "chyba paměti")
  end },
  { "nepřiřazená proměnná se nepropaguje dál", function()
    A.eq(fails("def loop():\n  if False:\n    r = 1\n  q = r\n  print('x')", "unbound").line, 4, "lokální")
    A.eq(fails("def loop():\n  global g\n  if False:\n    g = 1\n  q = g", "unbound").line, 5, "globální")
    A.eq(fails("def f():\n  if False:\n    r = 1\n  return r\ndef loop():\n  f()", "unbound").line, 4, "return")
    A.eq(fails("def loop():\n  if False:\n    r = 1\n  a = [r]", "unbound").line, 4, "literál")
  end },
  { "lexer nezávisí na locale (é není písmeno)", function()
    with_czech_locale(function()
      A.raises(function() lexer.tokenize("\233 = 1") end, "bad-char")
    end)
  end },
  { "desetinná čísla nezávisí na locale (tečka, ne čárka)", function()
    with_czech_locale(function()
      local res, err = P.run("def loop():\n  x = 2.5\n  print(x, 1 / 4, 1e-7)")
      if not res then error(err, 0) end
      A.eq(res.lines, "2.5 0.25 1e-07", "výstup")
    end)
  end },
  { "upper/lower nemění bajty mimo ASCII podle locale", function()
    with_czech_locale(function()
      A.eq(R.method("a\233", "upper"), "A\233", "upper")
    end)
  end },
  { "řazení klíčů výstupu nezávisí na locale", function()
    with_czech_locale(function()
      local out = signal_io.writer({ ["signal-B"] = 1, ["signal-a"] = 2 }, signals.new_resolver(fake()))
      A.eq(R.repr(R.method(out, "keys")), "['signal-B', 'signal-a']", "pořadí po bajtech")
    end)
  end },
}
