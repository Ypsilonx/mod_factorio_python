local A = require("assert")
local R = require("scripts.lang.builtins")
local signal_io = require("scripts.lang.signal_io")
local signals = require("scripts.lang.signals")
local vector = require("scripts.lang.vector")
local fake = require("fake_protos")
local P = require("prog_runner")

--- Čtecí objekt nad pevnou tabulkou kanonický klíč → hodnota (pořadí podle order).
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

local function writer(store) return signal_io.writer(store or {}, signals.new_resolver(fake())) end

local function m(obj, name, ...) return R.method(obj, name, ...) end

return {
  { "aritmetika kombinátoru", function()
    A.eq(vector.arith("+", 2147483647, 1), -2147483648, "přetečení +")
    A.eq(vector.arith("*", 65536, 65536), 0, "přetečení *")
    A.eq(vector.arith("*", -3, 7), -21, "záporné *")
    A.eq(vector.arith("/", -7, 2), -3, "/ k nule")
    A.eq(vector.arith("/", 7, 0), 0, "/ nulou = 0")
    A.eq(vector.arith("%", -7, 2), -1, "% se znaménkem dělence")
    A.eq(vector.arith("%", 7, 0), 0, "% nulou = 0")
    A.eq(vector.arith("**", 3, 4), 81, "mocnina")
    A.eq(vector.arith("**", 2, 31), -2147483648, "mocnina přeteče")
    A.eq(vector.arith("**", 2, -1), 0, "záporný exponent")
    A.eq(vector.arith("<<", 1, 33), 2, "posun mod 32")
    A.eq(vector.arith(">>", -8, 1), -4, "aritmetický posun")
    A.eq(vector.arith("&", 6, 3), 2, "and"); A.eq(vector.arith("|", 6, 3), 7, "or")
    A.eq(vector.arith("^", 6, 3), 5, "xor")
    A.eq(vector.arith("+", 2.9, -0.5), 2, "desetinná čísla se ořežou k nule")
  end },
  { "each a where nad vstupem", function()
    local inp = reader({ ["iron-plate"] = 5, ["signal-A"] = -2, ["copper-plate"] = 1 },
      { "copper-plate", "iron-plate", "signal-A" })
    A.eq(R.repr(m(inp, "each", "*", 2)), "{'copper-plate': 2, 'iron-plate': 10, 'signal-A': -4}", "each *")
    A.eq(R.repr(m(inp, "each", "-", 1)), "{'iron-plate': 4, 'signal-A': -3}", "nula se vypustí")
    A.eq(R.repr(m(inp, "where", ">", 0)), "{'copper-plate': 1, 'iron-plate': 5}", "where >")
    A.eq(R.repr(m(m(inp, "where", ">", 1), "each", "+", 1)), "{'iron-plate': 6}", "řetězení přes dict")
  end },
  { "agregace", function()
    local inp = reader({ ["iron-plate"] = 5, ["signal-A"] = 5, ["copper-plate"] = 1 },
      { "signal-A", "iron-plate", "copper-plate" })
    A.eq(m(inp, "count"), 3, "count"); A.eq(m(inp, "count", ">=", 5), 2, "count s podmínkou")
    A.eq(m(inp, "sum"), 11, "sum")
    A.eq(m(inp, "max_key"), "iron-plate", "max_key při shodě = menší klíč")
    A.eq(m(inp, "min_key"), "copper-plate", "min_key")
    local empty = reader({}, {})
    A.eq(m(empty, "max_key"), R.None, "prázdný max_key"); A.eq(m(empty, "sum"), 0, "prázdný sum")
    A.eq(m(empty, "count"), 0, "prázdný count")
  end },
  { "set a add na výstupu", function()
    local store = {}
    local out = writer(store)
    R.setitem(out, "signal-B", 9)
    m(out, "set", m(reader({ ["iron-plate"] = 3 }, { "iron-plate" }), "each", "*", 2))
    A.same(store, { ["iron-plate"] = 6 }, "set nahradí")
    m(out, "add", R.dict({ "iron-plate", 1, "signal-A", 2 }, 4))
    A.same(store, { ["iron-plate"] = 7, ["signal-A"] = 2 }, "add přičte")
    m(out, "add", R.dict({ "signal-A", -2 }, 2))
    A.same(store, { ["iron-plate"] = 7 }, "součet 0 signál smaže")
    m(out, "set", reader({ ["copper-plate"] = 4 }, { "copper-plate" }))
    A.same(store, { ["copper-plate"] = 4 }, "set z objektu signálů")
  end },
  { "chyby", function()
    local inp = reader({ ["iron-plate"] = 5 }, { "iron-plate" })
    A.raises(function() m(inp, "each", "<", 1) end, "bad-op")
    A.raises(function() m(inp, "where", "+", 1) end, "bad-op")
    A.raises(function() m(inp, "each", "*", "x") end, "type-error")
    A.raises(function() m(inp, "set", R.dict({}, 0)) end, "unknown-method")
    A.raises(function() m(writer(), "set", 5) end, "type-error")
    A.raises(function() m(R.dict({ "a", "x" }, 2), "each", "+", 1) end, "type-error")
  end },
  { "neplatný konstantní op ohlásí překladač", function()
    A.raises(function() P.program("def loop():\n  out.set(inp.each('<', 1))") end, "bad-op")
  end },
  { "watchdog platí za signály", function()
    local values, order = {}, {}
    for i = 1, 26 do
      local k = "signal-" .. string.char(64 + i)
      values[k] = i; order[#order + 1] = k
    end
    local inp, total = reader(values, order), 0
    local prev = R.active
    R.active = { charge = function(n) total = total + n end }
    m(inp, "each", "+", 1); m(inp, "sum")
    R.active = prev
    A.truthy(total >= 52, "každá operace platí počtem signálů (" .. total .. ")")
  end },
}
