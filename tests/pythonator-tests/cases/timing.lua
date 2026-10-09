--- Časování a výstupy ve skutečné hře: zpoždění jako vanilla kombinátor, out_red/out_green, hold/clear,
--- výpadek proudu, kvalita v klíči.
local H = require("helpers")

local A = H.virtual("signal-A")
local SAMPLES = 6

--- Kroky, které po změně zdroje sbírají výstup Pythonatoru a vanilla kombinátoru tick po ticku.
local function sampling_steps()
  local steps = { { ticks = 20, run = function(ctx) H.set_source(ctx.source, A, 5) end } }
  for _ = 1, SAMPLES do
    steps[#steps + 1] = { ticks = 1, run = function(ctx)
      ctx.ours[#ctx.ours + 1] = H.output(ctx.p, A)
      ctx.vanilla[#ctx.vanilla + 1] = H.output(ctx.v, A)
    end }
  end
  steps[#steps + 1] = { ticks = 1, run = function(ctx)
    local a, b = table.concat(ctx.ours, ","), table.concat(ctx.vanilla, ",")
    H.eq(a, b, "průběh výstupu (Pythonator vs. aritmetický kombinátor; vanilla stav " .. ctx.v.status
      .. ", vstup " .. ctx.v.get_signal(A, defines.wire_connector_id.combinator_input_red) .. ")")
    if not a:find("5") then error("výstup se nezměnil: " .. a) end
  end }
  return steps
end

return {
  {
    name = "zpoždění vstup → výstup je stejné jako u vanilla kombinátoru (1 tick)",
    setup = function(ctx)
      H.power(ctx)
      ctx.p = H.pythonator(ctx, 1, 1, "def loop():\n  out['signal-A'] = inp['signal-A']")
      ctx.v = ctx.surface.create_entity({ name = "arithmetic-combinator", force = "player",
                                          position = { ctx.origin.x + 4.5, ctx.origin.y + 1 } })
      ctx.v.get_or_create_control_behavior().parameters = { first_signal = H.virtual("signal-each"), second_constant = 0,
                                                             operation = "+", output_signal = H.virtual("signal-each") }
      ctx.source = H.source(ctx, 7.5, 1.5)
      H.wire_input(ctx.source, ctx.p)
      H.wire_input(ctx.source, ctx.v)
      -- Výstupní konektor bez drátu nemá síť (get_signal by vracel 0) – připojit ke sloupu.
      local pole = ctx.surface.create_entity({ name = "medium-electric-pole", force = "player",
                                               position = { ctx.origin.x + 4.5, ctx.origin.y - 1.5 } })
      ctx.v.get_wire_connector(defines.wire_connector_id.combinator_output_red, true)
        .connect_to(pole.get_wire_connector(defines.wire_connector_id.circuit_red, true), false)
      ctx.ours, ctx.vanilla = {}, {}
    end,
    steps = sampling_steps(),
  },
  {
    name = "out_red / out_green / out jdou na správné dráty",
    setup = function(ctx)
      H.power(ctx)
      ctx.p = H.pythonator(ctx, 1, 1,
        "def loop():\n  out_red['signal-A'] = 1\n  out_green['signal-B'] = 2\n  out['signal-C'] = 3")
    end,
    steps = { { ticks = 5, run = function(ctx)
      H.eq(H.output(ctx.p, A, "red"), 1, "A na červeném")
      H.eq(H.output(ctx.p, A, "green"), 0, "A na zeleném")
      H.eq(H.output(ctx.p, H.virtual("signal-B"), "green"), 2, "B na zeleném")
      H.eq(H.output(ctx.p, H.virtual("signal-B"), "red"), 0, "B na červeném")
      H.eq(H.output(ctx.p, H.virtual("signal-C"), "red"), 3, "C na červeném")
      H.eq(H.output(ctx.p, H.virtual("signal-C"), "green"), 3, "C na zeleném")
    end } },
  },
  {
    name = "hold drží výstup, clear ho po dalším loop() smaže",
    setup = function(ctx)
      H.power(ctx)
      local code = "n = 0\ndef loop():\n  global n\n  n += 1\n  if n == 1:\n    out['signal-A'] = 9"
      ctx.hold = H.pythonator(ctx, 1, 1, code)
      ctx.clear = H.pythonator(ctx, 4, 1, "config(outputs='clear')\n" .. code)
    end,
    steps = { { ticks = 10, run = function(ctx)
      H.eq(H.output(ctx.hold, A), 9, "hold")
      H.eq(H.output(ctx.clear, A), 0, "clear")
    end } },
  },
  {
    name = "výpadek proudu: tick stojí, výstupy zůstanou, po obnově dt zahrne pauzu",
    setup = function(ctx)
      ctx.pole = H.power(ctx)
      ctx.p = H.pythonator(ctx, 1, 1, "last = 0\ndef loop():\n  global last\n  last = dt\n  out['signal-A'] = tick + 1")
    end,
    steps = {
      { ticks = 30, run = function(ctx) ctx.pole.destroy() end },
      { ticks = 200, run = function(ctx)
        ctx.tick = H.state(ctx.p).tick
      end },
      { ticks = 120, run = function(ctx)
        H.eq(H.state(ctx.p).tick, ctx.tick, "tick stojí")
        if H.output(ctx.p, A) == 0 then error("výstup zmizel") end
        H.power(ctx)
      end },
      { ticks = 150, run = function(ctx)
        local s = H.state(ctx.p)
        if s.tick <= ctx.tick then error("po obnově proudu neběží") end
        if s.tick > ctx.tick + 150 then error("tick započítal výpadek: " .. s.tick .. " vs " .. ctx.tick) end
      end },
    },
  },
  {
    name = "kvalita v klíči výstupu",
    requires = "quality",
    setup = function(ctx)
      H.power(ctx)
      ctx.p = H.pythonator(ctx, 1, 1, "def loop():\n  out['iron-plate@rare'] = 3")
    end,
    steps = { { ticks = 5, run = function(ctx)
      H.eq(H.output(ctx.p, { type = "item", name = "iron-plate", quality = "rare" }), 3, "rare")
      H.eq(H.output(ctx.p, { type = "item", name = "iron-plate", quality = "normal" }), 0, "normal")
    end } },
  },
}
