--- Testy výstupů na drátech: připojení skrytých kombinátorů a zápis rozdílu do jejich sekcí.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")

--- Kontrolér se dvěma falešnými výstupy.
local function setup()
  G.reset()
  local io = require("scripts.io")
  local ctl = { out = { both = {}, red = {}, green = {} }, outputs = { red = G.output(), green = G.output() } }
  return io, ctl
end

--- Zdroj vstupu inp (oba dráty) nad falešnou entitou.
local function inp_source(io, entity)
  local wires = io.input_wires().inp
  return io.reader_source(entity, wires, require("scripts.resolver").get())
end

return {
  { "budovy na stejné síti čtou v jednom ticku z enginu jen jednou", function()
    local io = setup()
    local a, b = G.entity(1), G.entity(2)
    a.red["signal-A"], b.red["signal-A"] = 5, 5
    a.net_ids[1], b.net_ids[1] = 77, 77
    local sa, sb = inp_source(io, a), inp_source(io, b)
    sa.reset(10); sb.reset(10)
    A.eq(sa.all()[1][2], 5, "první budova")
    A.eq(sb.all()[1][2], 5, "druhá budova")
    A.eq(a.reads + b.reads, 1, "jedno čtení za tick")
    sa.reset(11); sb.reset(11)
    b.red["signal-A"], a.red["signal-A"] = 6, 6
    A.eq(sb.all()[1][2], 6, "nový tick = nové čtení")
    A.eq(a.reads + b.reads, 2, "druhý tick")
  end },
  { "různé sítě se čtou zvlášť, budova bez sítě nečte nic", function()
    local io = setup()
    local a, b, c = G.entity(1), G.entity(2), G.entity(3)
    a.red["signal-A"], b.red["signal-A"] = 1, 2
    local sa, sb, sc = inp_source(io, a), inp_source(io, b), inp_source(io, c)
    sa.reset(5); sb.reset(5); sc.reset(5)
    A.eq(sa.all()[1][2], 1, "a")
    A.eq(sb.all()[1][2], 2, "b")
    A.eq(#sc.all(), 0, "bez sítě prázdné")
    A.eq(c.reads, 0, "bez sítě se engine nevolá")
  end },
  { "výstup = out + out_red / out_green, s přetečením int32", function()
    local io, ctl = setup()
    ctl.out.both["signal-A"], ctl.out.red["signal-A"], ctl.out.green["iron-plate@rare"] = 2, 3, 4
    ctl.out.both["signal-B"], ctl.out.red["signal-B"] = 2147483647, 1
    io.flush(ctl)
    local red, green = ctl.outputs.red.signals(), ctl.outputs.green.signals()
    A.eq(red["signal-A"], 5, "červený A")
    A.eq(green["signal-A"], 2, "zelený A")
    A.eq(green["iron-plate@rare"], 4, "kvalita")
    A.eq(red["signal-B"], -2147483648, "přetečení")
  end },
  { "nezměněné výstupy nevolají API, zmizelé uvolní slot", function()
    local io, ctl = setup()
    ctl.out.both["signal-A"], ctl.out.both["signal-B"] = 1, 2
    io.flush(ctl)
    local before = ctl.outputs.red.calls
    io.flush(ctl)
    A.eq(ctl.outputs.red.calls, before, "žádné volání")
    ctl.out.both["signal-A"] = nil
    ctl.out.both["iron-plate"] = 7
    io.flush(ctl)
    A.eq(ctl.outputs.red.calls, before + 2, "jedno smazání a jedno nastavení")
    local red = ctl.outputs.red.signals()
    A.eq(red["signal-A"], nil, "smazáno")
    A.eq(red["iron-plate"], 7, "nový signál")
    local max_slot = 0
    for i in pairs(ctl.outputs.red.sections[1].slots) do max_slot = math.max(max_slot, i) end
    A.eq(max_slot, 2, "slot se recykloval")
  end },
  { "přes 1000 signálů se použije další sekce", function()
    local io, ctl = setup()
    _G.prototypes.item = {}
    for i = 1, 1500 do _G.prototypes.item["x" .. i] = true end
    for i = 1, 1500 do ctl.out.both["x" .. i] = i end
    io.flush(ctl)
    A.eq(#ctl.outputs.red.sections, 2, "dvě sekce")
    local red = ctl.outputs.red.signals()
    A.eq(red["x1500"], 1500, "poslední signál")
  end },
  { "neplatný výstup (zničený jiným modem) se přeskočí", function()
    local io, ctl = setup()
    ctl.outputs.red.valid = false
    ctl.out.both["signal-A"] = 1
    io.flush(ctl)
    A.eq(ctl.outputs.red.calls, 0, "nic")
    A.eq(ctl.outputs.green.signals()["signal-A"], 1, "druhý drát funguje")
  end },
}
