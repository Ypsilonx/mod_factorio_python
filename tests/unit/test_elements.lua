local A = require("assert")
local P = require("prog_runner")
local R = require("scripts.lang.builtins")
local vm = require("scripts.lang.vm")

--- Spustí program na `ticks` ticků a vrátí řádky print() spojené "|".
local function lines(src, ticks)
  local res, err = P.run(src, ticks)
  if not res then error(err, 0) end
  return res.lines
end

--- Klíč chyby programu.
local function fails(src, ticks)
  local res, err = P.run(src, ticks)
  A.eq(res, nil, "program měl skončit chybou")
  return err.key
end

return {
  { "latch: set, reset, přednost resetu", function()
    A.eq(lines("S = [1, 0, 0, 1, 1, 0]\nR_ = [0, 0, 1, 0, 1, 0]\ndef loop():\n"
      .. "  print(latch('a', S[tick], R_[tick]))", 6),
      "True|True|False|True|False|False", "latch")
  end },
  { "edge: náběžná a sestupná hrana", function()
    A.eq(lines("V = [0, 1, 1, 0, 5, 0]\ndef loop():\n  print(edge('e', V[tick]))", 6),
      "0|1|0|-1|1|-1", "edge")
  end },
  { "counter: krok, reset", function()
    A.eq(lines("def loop():\n  print(counter('c'), counter('d', 5, tick == 2))", 4),
      "1 5|2 10|3 0|4 5", "counter")
  end },
  { "timer: perioda a dt", function()
    A.eq(lines("def loop():\n  print(timer('t', 3))", 7), "False|False|True|False|False|True|False", "timer")
    -- výpadek proudu: dt přes několik period vystřelí jednou a zbytek si nechá
    local res = P.run("def loop():\n  print(timer('t', 4))", 1, nil, { dt = 9 })
    A.eq(res.lines, "True", "dt > perioda")
    A.eq(res.G["#lib"].t.acc, 1, "zbytek po dělení periodou")
  end },
  { "delay: zpoždění o n volání, změna n vymaže", function()
    A.eq(lines("def loop():\n  print(delay('d', tick * 10, 2))", 5), "0|0|0|10|20", "delay 2")
    A.eq(lines("def loop():\n  print(delay('d', tick, 1 if tick < 3 else 2))", 6), "0|0|1|0|0|3", "změna n")
  end },
  { "pid: P, I, D, ořez s anti-windup", function()
    A.eq(lines("def loop():\n  print(pid('p', 10, tick, 1, 0, 0))", 3), "10|9|8", "P")
    A.eq(lines("def loop():\n  print(pid('p', 10, 0, 0, 0.5, 0))", 3), "5|10|15", "I")
    A.eq(lines("def loop():\n  print(pid('p', 0, tick * tick, 0, 0, 1))", 3), "0|-1|-3", "D")
    A.eq(lines("def loop():\n  print(pid('p', 10 if tick < 4 else -10, 0, 0, 1, 0, -15, 15))", 6),
      "10|15|15|15|0|-10", "integrál se při saturaci nezvětšuje")
  end },
  { "chyby argumentů a kolize druhu", function()
    A.eq(fails("def loop():\n  latch('x', 1, 0)\n  edge('x', 1)"), "pyntr-err.element-kind", "kolize")
    A.eq(fails("def loop():\n  timer('t', 0)"), "pyntr-err.bad-arg", "perioda 0")
    A.eq(fails("def loop():\n  delay('d', 1, 1001)"), "pyntr-err.bad-arg", "n nad limit")
    A.eq(fails("def loop():\n  latch(5, 1, 0)"), "pyntr-err.bad-arg", "jméno není str")
    A.eq(fails("def loop():\n  latch('a', 1)"), "pyntr-err.arg-count", "počet argumentů")
  end },
  { "pid s None z globálu po načtení hry (None = nová tabulka s NoneMT)", function()
    local res = P.run("LO = None\ndef loop():\n  print(pid('p', 10, 0, 1, 0, 0, LO, 5))", 1)
    local copy = setmetatable({}, R.NoneMT)
    res.G.LO = copy
    local inst = require("scripts.lang.vm").instantiate(res.prog, res.G, {
      print = function() end, tick = 0, game_tick = 0, dt = 1 })
    local ok, err = vm.run(inst, "loop", 10000)
    A.eq(ok, true, "pid s kopií None: " .. tostring(err and err.key))
  end },
  { "jména prvků jsou vyhrazená", function()
    A.raises(function() P.program("timer = 1\ndef loop():\n  pass") end, "reserved-name")
  end },
  { "stav prvků počítá pojistka paměti", function()
    local res = P.run("def loop():\n  for i in range(50):\n    delay(str(i), i, 100)", 100)
    A.truthy(vm.memory(res.G, 1000000) >= 5000, "buffery delay se počítají")
    A.truthy(vm.check_memory(res.G, 1000) ~= nil, "nad limitem chyba paměti")
  end },
  { "stav prvků je uložitelný (bez metatabulek a funkcí)", function()
    local res = P.run("def loop():\n  latch('a', 1, 0)\n  delay('d', [1, 2], 2)\n  pid('p', 1, 0, 1, 1, 1)", 2)
    local function plain(t, path)
      for k, v in pairs(t) do
        A.truthy(type(v) ~= "function", path .. "." .. tostring(k) .. " není funkce")
        if type(v) == "table" and getmetatable(v) == nil then plain(v, path .. "." .. tostring(k)) end
      end
    end
    plain(res.G["#lib"], "#lib")
    A.eq(R.repr(res.G["#lib"].d.buf[1]), "[1, 2]", "hodnota v bufferu")
  end },
}
