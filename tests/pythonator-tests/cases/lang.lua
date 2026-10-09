--- Jazyk ve skutečné hře (Lua 5.2 hry místo 5.3 z unit testů): konformní programy z tests/conformance
--- (data generuje tools/run-tests.sh) a pojistky watchdog a paměť s výchozím nastavením mapy.
local H = require("helpers")
local ok_data, conformance = pcall(require, "conformance_data")

local cases = {}

if ok_data then
  for i, case in ipairs(conformance) do
    cases[#cases + 1] = {
      name = "konformita ve hře: " .. case.name,
      setup = function(ctx)
        -- Kód nahrát, hned pauza a ticks× krok: deterministické tick/dt jako v unit testech.
        ctx.p = H.pythonator(ctx, 1 + (i - 1) * 3, 1, case.source)
        remote.call("pyntr", "stop", ctx.p.unit_number)
        for _ = 1, case.ticks do remote.call("pyntr", "step", ctx.p.unit_number) end
      end,
      steps = { { ticks = 1, run = function(ctx)
        local s = H.state(ctx.p)
        if s.error then error("chyba programu: " .. serpent.line(s.error)) end
        H.eq(table.concat(s.prints, "\n"), case.expected, "výstup print()")
      end } },
    }
  end
end

cases[#cases + 1] = {
  name = "watchdog zastaví nekonečný cyklus s chybou a řádkem",
  setup = function(ctx)
    H.power(ctx)
    ctx.p = H.pythonator(ctx, 1, 1, "def loop():\n  while True:\n    pass")
  end,
  steps = { { ticks = 5, run = function(ctx)
    local s = H.state(ctx.p)
    H.eq(s.error and s.error.key, "pyntr-err.watchdog", "chyba")
    H.eq(s.error.line, 2, "řádek cyklu")
  end } },
}

cases[#cases + 1] = {
  name = "pojistka paměti zastaví rostoucí globál",
  setup = function(ctx)
    H.power(ctx)
    ctx.p = H.pythonator(ctx, 1, 1, "a = []\ndef loop():\n  for i in range(2000):\n    a.append(i)")
  end,
  steps = { { ticks = 150, run = function(ctx)
    local s = H.state(ctx.p)
    H.eq(s.error and s.error.key, "pyntr-err.memory", "chyba")
  end } },
}

return cases
