--- Testy ikon výstupů v ALT režimu: změna sady signálů z io.flush, výběr a rozložení ikon, kreslení a omezení
--- četnosti překreslení.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")

--- Čerstvé prostředí: kontrolér se dvěma falešnými výstupy a záznam kreslení.
local function setup()
  G.reset()
  package.loaded["scripts.alt_icons"] = nil
  local drawn = {}
  local function record(spec)
    local obj = { valid = true, spec = spec }
    function obj.destroy() obj.valid = false end
    drawn[#drawn + 1] = obj
    return obj
  end
  rendering.draw_sprite, rendering.draw_text = record, record
  local e = G.entity(1)
  e.surface = {}
  local ctl = { entity = e, out = { both = {}, red = {}, green = {} }, outputs = { red = G.output(), green = G.output() } }
  return require("scripts.alt_icons"), require("scripts.io"), ctl, drawn
end

--- Platné objekty kreslení.
local function alive(drawn)
  local out = {}
  for _, o in ipairs(drawn) do if o.valid then out[#out + 1] = o end end
  return out
end

return {
  { "io.flush hlásí změnu sady signálů, ne změnu hodnoty", function()
    local _, io, ctl = setup()
    ctl.out.both["signal-A"] = 1
    A.eq(select(2, io.flush(ctl)), true, "nový signál")
    ctl.out.both["signal-A"] = 5
    A.eq(select(2, io.flush(ctl)), false, "jen jiná hodnota")
    ctl.out.red["signal-B"] = 2
    A.eq(select(2, io.flush(ctl)), true, "signál na jednom drátu")
    ctl.out.both["signal-A"], ctl.out.red["signal-B"] = nil, nil
    A.eq(select(2, io.flush(ctl)), true, "odebrané signály")
  end },
  { "klíče z obou drátů bez opakování, seřazené po bajtech", function()
    local I, io, ctl = setup()
    ctl.out.both["signal-B"] = 1
    ctl.out.green["signal-A"] = 1
    ctl.out.red["signal-B"] = 3
    io.flush(ctl)
    local keys = I.keys(ctl)
    A.eq(table.concat(keys, ","), "signal-A,signal-B", "jednou a seřazené")
  end },
  { "rozložení: 1 uprostřed, 4 v mřížce, víc než 4 → 3 ikony a +N", function()
    local I = setup()
    local one = I.layout({ "a" })
    A.eq(one[1].offset[1], 0, "1: uprostřed")
    local four, rest = I.layout({ "a", "b", "c", "d" })
    A.eq(#four, 4, "4 ikony")
    A.eq(rest, 0, "nic navíc")
    local six, rest6, at = I.layout({ "a", "b", "c", "d", "e", "f" })
    A.eq(#six, 3, "3 ikony")
    A.eq(rest6, 3, "+3")
    A.eq(at[1], I.SPACING, "+N vpravo dole")
    A.eq(#I.layout({}), 0, "bez signálů nic")
  end },
  { "kreslení: podklad a ikona jen v ALT, odznak kvality, překreslení smaže staré", function()
    local I, io, ctl, drawn = setup()
    ctl.out.both["signal-A"] = 1
    ctl.out.both["iron-plate@rare"] = 1
    io.flush(ctl)
    I.draw(ctl)
    local objs = alive(drawn)
    A.eq(#objs, 5, "2× podklad + 2× ikona + kvalita")
    for _, o in ipairs(objs) do A.eq(o.spec.only_in_alt_mode, true, "jen v ALT") end
    local sprites = {}
    for _, o in ipairs(objs) do sprites[o.spec.sprite] = true end
    A.truthy(sprites["item/iron-plate"] and sprites["virtual-signal/signal-A"] and sprites["quality/rare"], "sprity")
    ctl.out.both = {}
    io.flush(ctl)
    I.draw(ctl)
    A.eq(#alive(drawn), 0, "bez výstupů nic")
    A.eq(ctl.alt, nil, "stav uklizený")
  end },
  { "překreslení nejvýš jednou za MIN_TICKS, odložená změna se dokreslí později", function()
    local I, io, ctl, drawn = setup()
    game.tick = 100
    ctl.out.both["signal-A"] = 1
    I.on_flushed(ctl, select(2, io.flush(ctl)))
    A.eq(#alive(drawn), 2, "první změna hned")
    game.tick = 101
    ctl.out.both["signal-B"] = 1
    I.on_flushed(ctl, select(2, io.flush(ctl)))
    A.eq(#alive(drawn), 2, "druhá změna odložená")
    A.eq(ctl.alt_dirty, true, "čeká")
    game.tick = 100 + I.MIN_TICKS
    I.on_flushed(ctl, false)
    A.eq(#alive(drawn), 4, "dokreslená bez další změny")
    A.eq(ctl.alt_dirty, nil, "nic nečeká")
  end },
}
