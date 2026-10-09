-- Výkonový scénář: N budov napojených na společný zdroj 20 signálů. Režimy (mode.lua, count.lua generuje
-- tools/run-perf.sh): idle = jen zdroj a proud, pass = Pythonator s prázdným loop(), hyst = Pythonator
-- s hysterezí nad 20 signály, items = jen průchod inp.items(), get20 = 20× čtení signálu po jednom,
-- decider = vanilla rozhodovací kombinátor nad stejnými signály.
local MODE = require("mode")
local N = require("count")

--- Počet signálů zdroje.
local SIGNALS = 20

--- Typický program: hystereze každého příchozího signálu (zapnout pod LOW, vypnout nad HIGH).
local HYST = table.concat({
  "LOW = 30",
  "HIGH = 70",
  "on = {}",
  "def loop():",
  "    for k, v in inp.items():",
  "        if v < LOW:",
  "            on[k] = True",
  "        elif v > HIGH:",
  "            on[k] = False",
  "        out[k] = 1 if on.get(k, False) else 0",
}, "\n")

--- Programy podle režimu (items/get20 rozlišují cenu čtení všech signálů a čtení po jednom).
local GET20 = { "def loop():" }
for i = 1, SIGNALS do GET20[#GET20 + 1] = "    x" .. i .. " = inp['signal-" .. string.char(64 + i) .. "']" end
local PROGRAMS = {
  pass = "def loop():\n    pass",
  hyst = HYST,
  items = "def loop():\n    for k, v in inp.items():\n        pass",
  get20 = table.concat(GET20, "\n"),
}

local W = defines.wire_connector_id

--- Postaví entitu (s raise_built, aby ji Pythonator zaevidoval).
local function place(surface, spec)
  spec.force = "player"
  spec.raise_built = true
  local entity = surface.create_entity(spec)
  assert(entity, "nelze postavit " .. spec.name)
  return entity
end

script.on_init(function()
  local surface = game.create_surface("pyntr-perf")
  surface.generate_with_lab_tiles = true
  surface.request_to_generate_chunks({ 0, 0 }, 10)
  surface.force_generate_chunk_requests()
  local source = place(surface, { name = "constant-combinator", position = { -80.5, -70.5 } })
  local section = source.get_or_create_control_behavior().add_section()
  for i = 1, SIGNALS do
    section.set_slot(i, { value = { type = "virtual", name = "signal-" .. string.char(64 + i), quality = "normal",
                                    comparator = "=" }, min = i * 5 })
  end
  local power = place(surface, { name = "electric-energy-interface", position = { -78, -70 } })
  power.power_production = 1e9
  power.electric_buffer_size = 1e10
  storage.units = {}
  local previous = source
  local previous_id = W.circuit_red
  for i = 0, N - 1 do
    local column, row = i % 50, math.floor(i / 50)
    local x, y = column * 3 - 75, row * 4 - 60
    if column % 6 == 0 and row % 4 == 0 then place(surface, { name = "substation", position = { x - 1, y - 1 } }) end
    local e
    if PROGRAMS[MODE] then
      e = place(surface, { name = "pyntr-pythonator", position = { x + 1, y + 1 } })
      remote.call("pyntr", "set_code", e.unit_number, PROGRAMS[MODE])
      storage.units[#storage.units + 1] = e.unit_number
    elseif MODE == "decider" then
      e = place(surface, { name = "decider-combinator", position = { x + 0.5, y + 1 } })
      e.get_or_create_control_behavior().parameters = {
        conditions = { { first_signal = { type = "virtual", name = "signal-each" }, comparator = "<", constant = 50 } },
        outputs = { { signal = { type = "virtual", name = "signal-each" }, copy_count_from_input = false } },
      }
    end
    if e then
      -- Vstupy v řetězu: všechny budovy vidí stejnou síť se zdrojem.
      previous.get_wire_connector(previous_id, true).connect_to(e.get_wire_connector(W.combinator_input_red, true), false)
      previous, previous_id = e, W.combinator_input_red
    end
  end
end)

-- Kontrola, že scénář opravdu běží (jinak by měření nic neříkalo).
script.on_nth_tick(3000, function()
  if PROGRAMS[MODE] then
    local errors, running = 0, 0
    for _, unit in ipairs(storage.units) do
      local state = remote.call("pyntr", "get_state", unit)
      if state.error then errors = errors + 1 elseif state.running then running = running + 1 end
    end
    log("PYNTR-PERF running=" .. running .. " errors=" .. errors)
  end
end)
