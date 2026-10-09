--- Stavba a zánik budovy všemi cestami, přenos kódu přes ducha (blueprint, smrt), remote interface.
-- luacheck: ignore 122
local H = require("helpers")

return {
  {
    name = "stavba vytvoří 2 skryté výstupy, zbourání s událostí je uklidí",
    setup = function(ctx) ctx.p = H.pythonator(ctx) end,
    steps = {
      { ticks = 1, run = function(ctx)
        H.eq(H.hidden_count(ctx), 2, "skryté výstupy po stavbě")
        ctx.p.destroy({ raise_destroy = true })
      end },
      { ticks = 2, run = function(ctx) H.eq(H.hidden_count(ctx), 0, "skryté výstupy po zbourání") end },
    },
  },
  {
    name = "zánik bez události (destroy) uklidí přes on_object_destroyed",
    setup = function(ctx) ctx.p = H.pythonator(ctx) end,
    steps = {
      { ticks = 1, run = function(ctx) ctx.p.destroy() end },
      { ticks = 3, run = function(ctx) H.eq(H.hidden_count(ctx), 0, "skryté výstupy") end },
    },
  },
  {
    name = "duch s tagy postaví budovu i s kódem (blueprint / roboti)",
    setup = function(ctx)
      local ghost = ctx.surface.create_entity({ name = "entity-ghost", inner_name = H.DATA.entity, force = "player",
        position = { ctx.origin.x + 1, ctx.origin.y + 1 },
        tags = { pyntr_code = "x = 7\ndef loop(): pass", pyntr_running = false } })
      local _, entity = ghost.revive({ raise_revive = true })
      ctx.p = entity
    end,
    steps = { { ticks = 1, run = function(ctx)
      local s = H.state(ctx.p)
      H.eq(s.globals.x, "7", "kód z tagů proběhl")
      H.eq(s.running, false, "pauza z tagů")
    end } },
  },
  {
    name = "smrt: duch dostane kód, skryté výstupy zmizí",
    setup = function(ctx)
      game.forces.player.create_ghost_on_entity_death = true
      ctx.p = H.pythonator(ctx, 1, 1, "def loop(): pass")
    end,
    steps = {
      { ticks = 1, run = function(ctx) ctx.p.die() end },
      { ticks = 2, run = function(ctx)
        H.eq(H.hidden_count(ctx), 0, "skryté výstupy")
        local ghosts = ctx.surface.find_entities_filtered({ name = "entity-ghost", position = { ctx.origin.x + 1, ctx.origin.y + 1 } })
        H.eq(#ghosts, 1, "duch")
        H.eq((ghosts[1].tags or {}).pyntr_code, "def loop(): pass", "kód v duchovi")
      end },
    },
  },
  {
    name = "remote: chyba překladu, pauza, krok, reset, play",
    setup = function(ctx)
      H.power(ctx)
      ctx.p = H.pythonator(ctx, 1, 1, "n = 0\ndef loop():\n  global n\n  n += 1")
    end,
    steps = {
      { ticks = 10, run = function(ctx)
        local ok, err = remote.call("pyntr", "set_code", ctx.p.unit_number, "def loop(:")
        H.eq(ok, false, "chybný kód")
        H.eq(type(err.line), "number", "řádek chyby")
        remote.call("pyntr", "stop", ctx.p.unit_number)
        ctx.n = tonumber(H.state(ctx.p).globals.n)
        if ctx.n < 5 then error("program neběžel: n = " .. ctx.n) end
      end },
      { ticks = 10, run = function(ctx)
        H.eq(tonumber(H.state(ctx.p).globals.n), ctx.n, "pauza")
        H.eq(remote.call("pyntr", "step", ctx.p.unit_number), true, "krok")
        H.eq(tonumber(H.state(ctx.p).globals.n), ctx.n + 1, "po kroku")
        H.eq(remote.call("pyntr", "reset", ctx.p.unit_number), true, "reset")
        H.eq(H.state(ctx.p).globals.n, "0", "po resetu")
        H.eq(remote.call("pyntr", "start", ctx.p.unit_number), true, "play")
      end },
      { ticks = 10, run = function(ctx)
        if tonumber(H.state(ctx.p).globals.n) < 5 then error("po play neběží") end
      end },
    },
  },
  {
    name = "klonování: klon má vlastní skryté výstupy a kód, po zbourání nic nezůstane",
    setup = function(ctx)
      ctx.p = H.pythonator(ctx, 1, 1, "x = 5\ndef loop(): pass")
    end,
    steps = {
      { ticks = 2, run = function(ctx)
        local o = ctx.origin
        ctx.surface.clone_area({ source_area = { { o.x - 0.5, o.y - 0.5 }, { o.x + 2.5, o.y + 2.5 } },
                                 destination_area = { { o.x + 7.5, o.y - 0.5 }, { o.x + 10.5, o.y + 2.5 } },
                                 clone_entities = true, clone_tiles = false })
        local clones = ctx.surface.find_entities_filtered({ name = H.DATA.entity, position = { o.x + 9, o.y + 1 }, radius = 1 })
        H.eq(#clones, 1, "klon budovy")
        ctx.clone = clones[1]
        H.eq(H.hidden_count(ctx), 4, "2 + 2 skryté výstupy (klony zdroje zničeny, klon má nové)")
        H.eq(H.state(ctx.clone).globals.x, "5", "kód klonu proběhl")
      end },
      { ticks = 2, run = function(ctx)
        ctx.clone.destroy({ raise_destroy = true })
        ctx.p.destroy({ raise_destroy = true })
      end },
      { ticks = 3, run = function(ctx) H.eq(H.hidden_count(ctx), 0, "nic nezůstalo") end },
    },
  },
  {
    name = "dvojí script_raised_built nezdvojí skryté výstupy, parametry kombinátoru se vynulují",
    setup = function(ctx)
      ctx.p = ctx.surface.create_entity({ name = H.DATA.entity, position = { ctx.origin.x + 1, ctx.origin.y + 1 },
                                          force = "player" })
      ctx.p.get_or_create_control_behavior().parameters = { first_signal = H.virtual("signal-each"),
        second_constant = 1, operation = "*", output_signal = H.virtual("signal-each") }
      script.raise_script_built({ entity = ctx.p })
      script.raise_script_built({ entity = ctx.p })
    end,
    steps = { { ticks = 1, run = function(ctx)
      H.eq(H.hidden_count(ctx), 2, "jen 2 skryté výstupy")
      H.eq(ctx.p.get_or_create_control_behavior().parameters.first_signal, nil, "parametry vynulované")
    end } },
  },
  {
    name = "stavová LED: běh bliká, pauza a chyba svítí, objekt LED existuje",
    setup = function(ctx)
      H.power(ctx)
      ctx.p = H.pythonator(ctx, 1, 1, "n = 0\ndef loop():\n  global n\n  n += 1\n  if n == 30:\n    x = 1 / 0")
    end,
    steps = {
      { ticks = 5, run = function(ctx)
        H.eq(H.state(ctx.p).led, "run", "běží")
        H.eq(#rendering.get_all_objects("Pythonator") > 0, true, "LED nakreslená")
      end },
      { ticks = 40, run = function(ctx)
        H.eq(H.state(ctx.p).led, "error", "chyba")
        remote.call("pyntr", "reset", ctx.p.unit_number)
        remote.call("pyntr", "stop", ctx.p.unit_number)
        H.eq(H.state(ctx.p).led, "pause", "pauza")
      end },
    },
  },
}
