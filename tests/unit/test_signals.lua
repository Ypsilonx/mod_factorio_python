local A = require("assert")
local signals = require("scripts.lang.signals")
local fake = require("fake_protos")

--- Ověří úspěšné rozlišení klíče.
local function ok(key, stype, name, quality, canonical)
  local r = signals.new_resolver(fake())
  local sid, c, err = r:resolve(key)
  A.eq(err, nil, key .. " chyba")
  A.same(sid, { type = stype, name = name, quality = quality }, key .. " sid")
  A.eq(c, canonical, key .. " kanonický")
end

--- Ověří chybu rozlišení klíče a vrátí ji.
local function bad(key, errkey)
  local _, _, err = signals.new_resolver(fake()):resolve(key)
  A.truthy(err, key .. " čekána chyba")
  A.eq(err.key, "pyntr-err." .. errkey, key .. " klíč chyby")
  return err
end

return {
  { "split rozloží typ, jméno, kvalitu", function()
    A.same({ signals.split("recipe:iron-plate@rare") }, { "recipe", "iron-plate", "rare" }, "plný")
    A.same({ signals.split("iron-plate") }, { nil, "iron-plate", "normal" }, "holý")
    A.same({ signals.split("foo:bar") }, { nil, "foo:bar", "normal" }, "neznámý prefix je součást jména")
  end },
  { "item bez prefixu", function() ok("iron-plate", "item", "iron-plate", "normal", "iron-plate") end },
  { "virtuální signál", function() ok("signal-A", "virtual", "signal-A", "normal", "signal-A") end },
  { "fluid", function() ok("crude-oil", "fluid", "crude-oil", "normal", "crude-oil") end },
  { "recept s prefixem", function() ok("recipe:iron-plate", "recipe", "iron-plate", "normal", "recipe:iron-plate") end },
  { "kvalita", function() ok("iron-plate@rare", "item", "iron-plate", "rare", "iron-plate@rare") end },
  { "normal se v kanonickém tvaru vynechá", function() ok("iron-plate@normal", "item", "iron-plate", "normal", "iron-plate") end },
  { "zbytečný prefix item se vynechá", function() ok("item:iron-plate", "item", "iron-plate", "normal", "iron-plate") end },
  { "nejednoznačné jméno s prefixem zůstane s prefixem", function()
    ok("item:water", "item", "water", "normal", "item:water")
    ok("fluid:water", "fluid", "water", "normal", "fluid:water")
  end },
  { "překlep nabídne návrh", function()
    A.same(bad("iron-plates", "unknown-signal").args, { "iron-plates", "iron-plate" }, "argumenty")
  end },
  { "překlep v receptu nabídne recept", function()
    A.same(bad("recipe:iron-plat", "unknown-signal").args, { "recipe:iron-plat", "recipe:iron-plate" }, "argumenty")
  end },
  { "nesmysl bez návrhu", function() bad("xyzzy-qwerty", "unknown-signal-nosuggest") end },
  { "nejednoznačné jméno", function()
    A.same(bad("water", "ambiguous-signal").args, { "water", "item, fluid" }, "argumenty")
  end },
  { "neznámá kvalita", function() bad("iron-plate@shiny", "unknown-quality") end },
  { "from_tag převede typ tagu", function()
    A.eq(signals.from_tag("virtual-signal", "signal-A", "normal"), "virtual:signal-A", "virtual")
    A.eq(signals.from_tag("item", "iron-plate", "rare"), "item:iron-plate@rare", "kvalita")
  end },
  { "cache vrací stejný výsledek", function()
    local r = signals.new_resolver(fake())
    local _, c1 = r:resolve("iron-plate")
    local _, c2 = r:resolve("iron-plate")
    A.eq(c1, c2, "kanonický")
  end },
}
