local A = require("assert")
local R = require("scripts.lang.builtins")
local signal_io = require("scripts.lang.signal_io")
local signals = require("scripts.lang.signals")
local fake = require("fake_protos")

--- Čtecí objekt nad pevnou tabulkou kanonický klíč → hodnota.
local function reader(values, order)
  local source = {
    get = function(k) return values[k] or 0 end,
    all = function()
      local out = {}
      for _, k in ipairs(order) do out[#out + 1] = { k, values[k] } end
      return out
    end,
  }
  return signal_io.reader(source, signals.new_resolver(fake()))
end

return {
  { "čtení, chybějící = 0", function()
    local inp = reader({ ["iron-plate"] = 5 }, { "iron-plate" })
    A.eq(R.getitem(inp, "iron-plate"), 5, "existující")
    A.eq(R.getitem(inp, "copper-plate"), 0, "chybějící")
    A.eq(R.getitem(inp, "item:iron-plate"), 5, "nekanonický zápis")
  end },
  { "neznámý signál a špatný typ klíče", function()
    local inp = reader({}, {})
    A.raises(function() R.getitem(inp, "iron-plates") end, "unknown-signal")
    A.raises(function() R.getitem(inp, 5) end, "bad-signal-key")
  end },
  { "vstup nelze zapisovat", function()
    A.raises(function() R.setitem(reader({}, {}), "iron-plate", 1) end, "readonly-signal")
  end },
  { "items, len, in, pravdivost", function()
    local inp = reader({ ["iron-plate"] = 5, ["signal-A"] = -1 }, { "iron-plate", "signal-A" })
    A.eq(R.repr(R.method(inp, "items")), "[('iron-plate', 5), ('signal-A', -1)]", "items")
    A.eq(R.builtins.len(inp), 2, "len")
    A.eq(R.contains(inp, "signal-A"), true, "in"); A.eq(R.contains(inp, "signal-B"), false, "not in")
    A.eq(R.truthy(reader({}, {})), false, "prázdný")
    local keys = {}
    for k in R.iter(inp) do keys[#keys + 1] = k end
    A.eq(table.concat(keys, ","), "iron-plate,signal-A", "iterace klíčů")
  end },
  { "zápis: ořez, přetečení, nula maže", function()
    local store = {}
    local out = signal_io.writer(store, signals.new_resolver(fake()))
    R.setitem(out, "signal-A", 3.7); A.eq(store["signal-A"], 3, "ořez k nule")
    R.setitem(out, "signal-B", -3.7); A.eq(store["signal-B"], -3, "ořez záporného")
    R.setitem(out, "signal-I", 2147483648); A.eq(store["signal-I"], -2147483648, "přetečení")
    R.setitem(out, "signal-P", true); A.eq(store["signal-P"], 1, "bool")
    R.setitem(out, "signal-A", 0); A.eq(store["signal-A"], nil, "nula maže")
    A.raises(function() R.setitem(out, "signal-A", "x") end, "type-error")
  end },
  { "zápis kanonickým klíčem a clear", function()
    local store = {}
    local out = signal_io.writer(store, signals.new_resolver(fake()))
    R.setitem(out, "recipe:iron-plate@rare", 1)
    A.eq(store["recipe:iron-plate@rare"], 1, "kanonický klíč")
    A.eq(R.getitem(out, "recipe:iron-plate@rare"), 1, "čtení výstupu")
    R.method(out, "clear")
    A.eq(next(store), nil, "clear vyprázdní úložiště (stejná tabulka)")
  end },
}
