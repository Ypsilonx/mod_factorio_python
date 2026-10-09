--- Uložení a načtení hry uprostřed běhu (runner ukládá v SAVE_TICK, tools/run-tests.sh pak načte uloženou
--- pozici): globály s list/dict/None/tuple a sdílenou referencí pokračují bez inicializace, výstupy drží.
local H = require("helpers")
local runner = require("runner")

local CODE = table.concat({
  "a = [1, None, (2, 'x')]",
  "b = a",
  "d = {'z': 1, 'a': 2}",
  "d['m'] = 3",
  "n = 0",
  "def loop():",
  "    global n",
  "    n += 1",
  "    out['signal-A'] = n",
  "    print(n, a is b, d.keys(), a[1] is None, a[2])",
}, "\n")

return {
  {
    name = "uložení a načtení: stav pokračuje bez initu, pořadí dict, None, sdílená reference",
    setup = function(ctx)
      H.power(ctx)
      ctx.p = H.pythonator(ctx, 1, 1, CODE)
    end,
    steps = {
      { ticks = runner.SAVE_TICK - 10, run = function(ctx)
        ctx.before = tonumber(H.state(ctx.p).globals.n)
        if ctx.before < 10 then error("program neběžel") end
      end },
      { ticks = 60, run = function(ctx)
        if not runner.was_loaded() then error("hra se nenačetla z uložené pozice (běží run-tests.sh dvoufázově?)") end
        local s = H.state(ctx.p)
        if s.error then error("chyba po načtení: " .. serpent.line(s.error)) end
        local n = tonumber(s.globals.n)
        if n <= ctx.before + 30 then error("po načtení neběží nebo proběhl init: n = " .. n .. ", před " .. ctx.before) end
        H.eq(s.prints[#s.prints], n .. " True ['z', 'a', 'm'] True (2, 'x')", "poslední print")
        local out = H.output(ctx.p, H.virtual("signal-A"))
        if math.abs(out - n) > 1 then error("výstup na drátě " .. out .. " vs n " .. n) end
      end },
    },
  },
}
