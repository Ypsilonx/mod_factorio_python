--- Spouštění programů Pythonatoru v testech: překlad, init a n× loop s falešnými vstupy/výstupy.
local compiler = require("scripts.lang.compiler")
local vm = require("scripts.lang.vm")
local signals = require("scripts.lang.signals")
local signal_io = require("scripts.lang.signal_io")
local fake = require("fake_protos")

local P = {}

--- Přeloží zdroj; při chybě ji vyhodí (pro testy úspěšných programů).
function P.program(src)
  local prog, err = compiler.compile(src, signals.new_resolver(fake()))
  if not prog then error(err, 0) end
  return prog
end

--- Spustí init a `ticks`× loop.
--- @param src string
--- @param ticks integer|nil počet ticků (výchozí 1)
--- @param values table|nil vstupní signály kanonický klíč → hodnota (inp i red)
--- @return table|nil result {lines (spojené "|"), G, out, prog}
--- @return table|nil err
function P.run(src, ticks, values)
  local prog = P.program(src)
  local resolver = signals.new_resolver(fake())
  local lines, store = {}, {}
  values = values or {}
  local source = {
    get = function(k) return values[k] or 0 end,
    all = function()
      local keys = {}
      for k in pairs(values) do keys[#keys + 1] = k end
      table.sort(keys)
      local out = {}
      for i, k in ipairs(keys) do out[i] = { k, values[k] } end
      return out
    end,
  }
  local empty = { get = function() return 0 end, all = function() return {} end }
  local IO = {
    inp = signal_io.reader(source, resolver), red = signal_io.reader(source, resolver),
    green = signal_io.reader(empty, resolver),
    out = signal_io.writer(store, resolver), out_red = signal_io.writer({}, resolver),
    out_green = signal_io.writer({}, resolver),
    print = function(s) lines[#lines + 1] = s end,
    tick = 0, game_tick = 0, dt = 1,
  }
  local G = {}
  local inst = vm.instantiate(prog, G, IO)
  local ok, err = vm.run(inst, "init", 10000)
  if not ok then return nil, err end
  for t = 0, (ticks or 1) - 1 do
    IO.tick, IO.game_tick = t, t
    ok, err = vm.run(inst, "loop", 10000)
    if not ok then return nil, err end
  end
  return { lines = table.concat(lines, "|"), G = G, out = store, prog = prog }
end

return P
