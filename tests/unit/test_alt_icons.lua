--- Testy ikon v ALT režimu: čtené vstupy z překladače, config(label, icon), výstupy po drátech, rozložení řad
--- otočené s budovou, kreslení a omezení četnosti překreslení.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")
local P = require("prog_runner")

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

--- Čtené vstupy programu jako "drát:klíč" spojené čárkou.
local function inputs_of(src)
  local parts = {}
  for _, i in ipairs(P.program(src).inputs) do parts[#parts + 1] = i.wire .. ":" .. i.key end
  return table.concat(parts, ",")
end

return {
  { "překladač: čtené vstupy podle drátu, bez opakování, Each za čtení celé sady", function()
    A.eq(inputs_of("def loop():\n  x = inp['iron-plate'] + red['signal-A'] + inp['iron-plate']"),
         "both:iron-plate,red:signal-A", "konstantní klíče")
    A.eq(inputs_of("def loop():\n  x = green.get('signal-B')\n  y = 'signal-A' in red"),
         "green:signal-B,red:signal-A", "get a in")
    A.eq(inputs_of("def loop():\n  k = 'iron-plate'\n  x = inp[k]"), "both:signal-each", "dynamický klíč")
    A.eq(inputs_of("def loop():\n  out.set(green.where('>', 0))\n  n = len(red)"),
         "green:signal-each,red:signal-each", "vektorové metody a len")
    A.eq(inputs_of("def loop():\n  out['signal-A'] = 1"), "", "výstupy nejsou vstupy")
  end },
  { "překladač: config(label, icon) – icon ověřená a kanonická, špatný typ = chyba", function()
    local cfg = P.program("config(label='Hlídání plynu', icon='petroleum-gas')\ndef loop(): pass").config
    A.eq(cfg.label, "Hlídání plynu", "label")
    A.eq(cfg.icon, "petroleum-gas", "icon")
    A.eq(P.program("config(icon=[item=iron-plate])\ndef loop(): pass").config.icon, "iron-plate", "ikona z výběru")
    -- "water" je item i fluid – ikona z výběru nese typ, takže je jednoznačná
    A.eq(P.program("config(icon='[fluid=water]')\ndef loop(): pass").config.icon, "fluid:water", "ikona v uvozovkách")
    A.eq(inputs_of("def loop():\n  x = inp['[item=iron-plate,quality=rare]']"), "both:iron-plate@rare",
         "ikona z výběru v uvozovkách jako klíč (regrese: hlásilo neznámý signál)")
    local _, err = pcall(P.program, "config(icon='iron-plat')\ndef loop(): pass")
    A.truthy(err and err.key and err.key:find("unknown%-signal"), "překlep v ikoně")
    _, err = pcall(P.program, "config(label=5)\ndef loop(): pass")
    A.eq(err and err.key, "pyntr-err.bad-config", "label musí být řetězec")
  end },
  { "šipky na hraně budovy, po toku signálu, otočené s budovou", function()
    local I = setup()
    local d = I.ARROW_DISTANCE
    local north = I.arrows(0)
    A.eq(north[1].offset[2], d, "sever: vstup dole")
    A.eq(north[2].offset[2], -d, "sever: výstup nahoře")
    A.eq(north[1].orientation, 0, "míří na sever")
    local east = I.arrows(4)
    A.eq(east[2].offset[1], d, "východ: výstup vpravo")
    A.eq(east[2].orientation, 0.25, "míří na východ")
  end },
  { "výstupy po drátech: oba, jen červený, jen zelený; seřazené", function()
    local I, io, ctl = setup()
    ctl.out.both["signal-B"] = 1
    ctl.out.red["signal-A"] = 1
    ctl.out.green["iron-plate"] = 1
    io.flush(ctl)
    local parts = {}
    for _, o in ipairs(I.outputs(ctl)) do parts[#parts + 1] = o.wire .. ":" .. o.key end
    A.eq(table.concat(parts, ","), "green:iron-plate,red:signal-A,both:signal-B", "dráty")
  end },
  { "io.flush hlásí změnu sady signálů, ne změnu hodnoty", function()
    local _, io, ctl = setup()
    ctl.out.both["signal-A"] = 1
    A.eq(select(2, io.flush(ctl)), true, "nový signál")
    ctl.out.both["signal-A"] = 5
    A.eq(select(2, io.flush(ctl)), false, "jen jiná hodnota")
    ctl.out.both["signal-A"] = nil
    A.eq(select(2, io.flush(ctl)), true, "odebraný signál")
  end },
  { "rozložení: výstupy na straně výstupu, vstupy na straně vstupu, ikona uprostřed, +N, otočení", function()
    local I = setup()
    local function items(n)
      local t = {}
      for i = 1, n do t[i] = { key = "k" .. i, wire = "both" } end
      return t
    end
    local l = I.layout(items(1), items(5), "x", 0)
    -- výstupy: 2 ikony + „+3“ nahoře; vstup: 1 dole; ikona programu uprostřed
    A.eq(#l, 5, "počet prvků")
    A.eq(l[1].offset[1], I.ROW_SLOTS[1], "první výstup na první poloze")
    A.eq(l[1].offset[2], -I.ROW_OFFSET, "výstupy nahoře")
    A.eq(l[3].text, "+3", "+N za nevešlé")
    A.eq(l[4].offset[2], I.ROW_OFFSET, "vstupy dole")
    A.eq(l[5].main, true, "ikona programu")
    A.eq(l[5].offset[1], 0, "uprostřed")
    local east = I.layout({}, items(1), nil, 4)
    A.eq(east[1].offset[1], I.ROW_OFFSET, "otočeno na východ: výstupy vpravo")
    A.eq(#I.layout({}, {}, nil, 0), 0, "nic")
  end },
  { "kreslení: podklad podle drátu, kvalita, jen v ALT; překreslení smaže staré", function()
    local I, io, ctl, drawn = setup()
    ctl.out.both["iron-plate@rare"] = 1
    ctl.out.red["signal-A"] = 1
    ctl.inputs = { { key = "signal-each", wire = "green" } }
    ctl.icon = "petroleum-gas"
    io.flush(ctl)
    I.draw(ctl)
    local objs = alive(drawn)
    -- výstupy: rare (podklad+ikona+kvalita) a signal-A (kruh+ikona); vstup (kruh+ikona); ikona programu (stín + ikona); 2 šipky
    A.eq(#objs, 11, "počet objektů")
    local circles, sprites, always = 0, {}, 0
    for _, o in ipairs(objs) do
      if not o.spec.only_in_alt_mode then always = always + 1 end
      if o.spec.sprite == "utility/white_square" then circles = circles + 1 end
      if o.spec.sprite then sprites[o.spec.sprite] = true end
    end
    A.eq(circles, 2, "barevné podklady jen u jednoho drátu")
    A.eq(always, 2, "trvale vidět jen ikona programu se stínem")
    A.truthy(sprites["quality/rare"] and sprites["fluid/petroleum-gas"] and sprites["virtual-signal/signal-each"], "sprity")
    ctl.out.both, ctl.out.red, ctl.inputs, ctl.icon = {}, {}, nil, nil
    io.flush(ctl)
    I.draw(ctl)
    A.eq(#alive(drawn), 2, "zůstanou jen šipky")
  end },
  { "překreslení výstupů nejvýš jednou za MIN_TICKS, odložená změna se dokreslí později", function()
    local I, io, ctl, drawn = setup()
    game.tick = 100
    ctl.out.both["signal-A"] = 1
    I.on_flushed(ctl, select(2, io.flush(ctl)))
    A.eq(#alive(drawn), 4, "první změna hned (2 šipky + podklad + ikona)")
    game.tick = 101
    ctl.out.both["signal-B"] = 1
    I.on_flushed(ctl, select(2, io.flush(ctl)))
    A.eq(#alive(drawn), 4, "druhá změna odložená")
    game.tick = 100 + I.MIN_TICKS
    I.on_flushed(ctl, false)
    A.eq(#alive(drawn), 6, "dokreslená bez další změny")
    A.eq(ctl.alt_dirty, nil, "nic nečeká")
  end },
}
