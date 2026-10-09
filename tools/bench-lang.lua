-- Lokální měření rychlosti jazyka a hostitele (Lua 5.3, napodobené herní API): µs na jeden loop()
-- pro sadu typických programů. Spouštět z kořene repozitáře: lua tools/bench-lang.lua [počet běhů]
-- Čísla jsou relativní (hra běží na Lua 5.2 a skutečné API je dražší) – slouží k porovnání změn.
package.path = "Pythonator/?.lua;tests/unit/?.lua;" .. package.path
local G = require("fake_game")

--- Počet vstupních signálů (jako ve výkonovém scénáři tests/perf).
local SIGNALS = 20

local PROGRAMS = {
  { "pass", "def loop():\n    pass" },
  { "items", "def loop():\n    for k, v in inp.items():\n        pass" },
  { "get20", (function()
    local lines = { "def loop():" }
    for i = 1, SIGNALS do lines[#lines + 1] = "    x" .. i .. " = inp['signal-" .. string.char(64 + i) .. "']" end
    return table.concat(lines, "\n")
  end)() },
  { "hyst", table.concat({
    "LOW = 30", "HIGH = 70", "on = {}",
    "def loop():",
    "    for k, v in inp.items():",
    "        if v < LOW:",
    "            on[k] = True",
    "        elif v > HIGH:",
    "            on[k] = False",
    "        out[k] = 1 if on.get(k, False) else 0",
  }, "\n") },
  { "arith", table.concat({
    "acc = 0",
    "def loop():",
    "    global acc",
    "    for i in range(50):",
    "        acc = (acc + i * 3) % 1000",
    "        if acc > 500 and i % 2 == 0:",
    "            acc -= 1",
  }, "\n") },
  { "list", table.concat({
    "hist = []",
    "def loop():",
    "    hist.append(tick)",
    "    if len(hist) > 30:",
    "        hist.pop(0)",
    "    s = 0",
    "    for x in hist:",
    "        s += x",
    "    out['signal-A'] = s // len(hist)",
  }, "\n") },
}

local runs = tonumber(arg[1]) or 20000
G.reset()
local controller = require("scripts.controller")
local e = G.entity(1)
for i = 1, SIGNALS do
  local name = "signal-" .. string.char(64 + i)
  e.red[name] = i * 5
  _G.prototypes.virtual_signal[name] = true
end
local ctl = controller.create(e)
ctl.outputs = { red = G.output(), green = G.output() }

for _, p in ipairs(PROGRAMS) do
  local ok, err = controller.set_code(ctl, p[2])
  if not ok then error(p[1] .. ": " .. tostring(err.key)) end
  local t = os.clock()
  for i = 1, runs do controller.run_loop(ctl, i) end
  local us = (os.clock() - t) / runs * 1e6
  print(string.format("%-8s %8.2f µs/loop%s", p[1], us, ctl.error and ("  CHYBA " .. ctl.error.key) or ""))
end
