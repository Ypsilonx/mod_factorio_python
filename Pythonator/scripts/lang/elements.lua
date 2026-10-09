--- Knihovna kombinátorů: stavové prvky pod jménem (latch, timer, edge, counter, delay, pid).
--- Stav leží v globálu "#lib" běžící instance (neplatné jméno – program ho nepřepíše) jako obyčejné Lua
--- tabulky: uloží se se savem bez metatabulek, Reset ho smaže s globály a počítá ho pojistka paměti.
local R = require("scripts.lang.builtins")

local M = {}

--- Jméno globálu se stavem prvků.
M.STATE = "#lib"
--- Největší zpoždění delay() (velikost bufferu).
M.DELAY_MAX = 1000

local B = R.builtins

--- Ověří počet argumentů (min..max).
local function argc(name, n, min, max)
  if n < min or n > max then
    R.raise("arg-count", name, min == max and tostring(min) or (min .. "–" .. max), n)
  end
end

--- Chyba neplatného argumentu.
local function bad(fn, arg, v) R.raise("bad-arg", fn, arg, R.repr(v)) end

--- Číslo z argumentu, jinak bad-arg.
local function num(fn, arg, v)
  local x = R.numv(v)
  if not x then bad(fn, arg, v) end
  return x
end

--- Stav prvku `name` druhu `kind` v globálech G; při prvním použití ho založí.
--- @param G table globály instance
--- @return table stav (pole kind + data prvku)
function M.state(G, fn, name, kind)
  if type(name) ~= "string" then bad(fn, "name", name) end
  local all = G[M.STATE]
  if not all then
    all = {}
    G[M.STATE] = all
  end
  local s = all[name]
  if not s then
    s = { kind = kind }
    all[name] = s
  elseif s.kind ~= kind then
    R.raise("element-kind", name, s.kind, kind)
  end
  return s
end

--- Globály a dt běžící instance (prvky se volají jen z běžícího programu).
local function active()
  local inst = R.active
  return inst.globals, inst.io.dt
end

--- latch(name, set, reset) → bool: SR klopný obvod, přednost má reset.
function B.latch(...)
  local n, name, set, reset = select("#", ...), ...
  argc("latch", n, 3, 3)
  local s = M.state(active(), "latch", name, "latch")
  if R.truthy(reset) then
    s.q = false
  elseif R.truthy(set) then
    s.q = true
  end
  return s.q == true
end

--- timer(name, period) → bool: True jednou za period ticků (sčítá dt, zbytek po periodě si nechá).
function B.timer(...)
  local n, name, period = select("#", ...), ...
  argc("timer", n, 2, 2)
  local G, dt = active()
  local s = M.state(G, "timer", name, "timer")
  local p = num("timer", "period", period)
  if p <= 0 then bad("timer", "period", period) end
  s.acc = (s.acc or 0) + dt
  if s.acc >= p then
    -- po výpadku proudu (dt přes několik period) vystřelí jen jednou
    s.acc = s.acc % p
    return true
  end
  return false
end

--- edge(name, value) → 1 náběžná, -1 sestupná, 0 žádná hrana (podle pravdivosti value).
function B.edge(...)
  local n, name, value = select("#", ...), ...
  argc("edge", n, 2, 2)
  local s = M.state(active(), "edge", name, "edge")
  local now, prev = R.truthy(value), s.prev == true
  s.prev = now
  if now and not prev then return 1 end
  if prev and not now then return -1 end
  return 0
end

--- counter(name, step=1, reset=False) → int: přičte step, reset vynuluje.
function B.counter(...)
  local n, name, step, reset = select("#", ...), ...
  argc("counter", n, 1, 3)
  local s = M.state(active(), "counter", name, "counter")
  if n >= 3 and R.truthy(reset) then
    s.value = 0
  else
    s.value = (s.value or 0) + (n >= 2 and num("counter", "step", step) or 1)
  end
  return s.value
end

--- delay(name, value, n) → hodnota z doby před n voláními (do naplnění 0); změna n buffer vymaže.
function B.delay(...)
  local argn, name, value, n = select("#", ...), ...
  argc("delay", argn, 3, 3)
  local s = M.state(active(), "delay", name, "delay")
  local size = num("delay", "n", n)
  if size < 1 or size > M.DELAY_MAX or size ~= math.floor(size) then bad("delay", "n", n) end
  if s.n ~= size then
    s.n, s.buf, s.pos = size, {}, 1
  end
  local old = s.buf[s.pos]
  s.buf[s.pos] = value
  s.pos = s.pos % size + 1
  if old == nil then return 0 end
  return old
end

--- pid(name, setpoint, measured, kp, ki, kd, lo=None, hi=None) → float.
--- Integrál a derivace podle dt; s lo/hi ořez výstupu a anti-windup (při saturaci směrem
--- od rozsahu se integrál nezvětší).
function B.pid(...)
  local n, name, sp, pv, kp, ki, kd, lo, hi = select("#", ...), ...
  argc("pid", n, 6, 8)
  local G, dt = active()
  local s = M.state(G, "pid", name, "pid")
  local e = num("pid", "setpoint", sp) - num("pid", "measured", pv)
  kp, ki, kd = num("pid", "kp", kp), num("pid", "ki", ki), num("pid", "kd", kd)
  local low = (lo ~= nil and lo ~= R.None) and num("pid", "lo", lo) or nil
  local high = (hi ~= nil and hi ~= R.None) and num("pid", "hi", hi) or nil
  local integral = (s.integral or 0) + e * dt
  local deriv = (s.prev_e and dt > 0) and (e - s.prev_e) / dt or 0
  local out = kp * e + ki * integral + kd * deriv
  if high and out > high then
    out = high
    if e > 0 then integral = s.integral or 0 end
  elseif low and out < low then
    out = low
    if e < 0 then integral = s.integral or 0 end
  end
  s.integral, s.prev_e = integral, e
  return out
end

return M
