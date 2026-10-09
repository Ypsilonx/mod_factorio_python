--- Testy plánovače: spouštění podle intervalu, dvojí zařazení, zastavené a chybové kontroléry, výpadek proudu.
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")

--- Prostředí s kontrolérem, který si do globálu `log` zapisuje (tick, game_tick, dt).
local function setup(src)
  G.reset()
  local controller = require("scripts.controller")
  local scheduler = require("scripts.scheduler")
  local entity = G.entity(1)
  local ctl = controller.create(entity)
  local ok, err = controller.set_code(ctl, src or "log = []\ndef loop():\n  log.append((tick, game_tick, dt))")
  if not ok then error(err, 0) end
  return scheduler, ctl, entity
end

--- Odsimuluje ticky from..to.
local function ticks(scheduler, from, to)
  for t = from, to do scheduler.on_tick(t) end
end

--- Textová podoba logu programu.
local function log_of(ctl)
  return require("scripts.lang.builtins").repr(ctl.globals.log)
end

return {
  { "spouští jen naplánované ticky podle intervalu", function()
    local scheduler, ctl = setup("config(interval=3)\nlog = []\ndef loop():\n  log.append(game_tick)")
    scheduler.add(ctl.unit, 10)
    ticks(scheduler, 1, 17)
    A.eq(log_of(ctl), "[10, 13, 16]", "běhy")
  end },
  { "první běh s intervalem: fáze podle unit_number rozloží budovy do různých ticků", function()
    local scheduler = setup()
    A.eq(scheduler.first_tick(7, 1, 100), 101, "interval 1: hned příští tick")
    A.eq(scheduler.first_tick(7, 60, 100), 127, "fáze 7 z 60 (127 % 60 = 7)")
    A.eq(scheduler.first_tick(60, 60, 100), 120, "fáze 0")
    A.eq(scheduler.first_tick(41, 60, 100), 101, "fáze padne na příští tick")
    local seen = {}
    for unit = 1, 150 do seen[scheduler.first_tick(unit, 60, 100) % 60] = true end
    local phases = 0
    for _ in pairs(seen) do phases = phases + 1 end
    A.eq(phases, 60, "150 budov rozložených do všech 60 fází")
  end },
  { "rebuild (načtení, změna modů) zachová fázi budovy", function()
    local scheduler, ctl = setup("config(interval=10)\nlog = []\ndef loop():\n  log.append(game_tick)")
    ctl.unit = 3
    storage.controllers = { [3] = ctl }
    scheduler.rebuild(100)
    ticks(scheduler, 101, 125)
    A.eq(log_of(ctl), "[103, 113, 123]", "běhy ve fázi unit % interval")
  end },
  { "dvojí zařazení neběží dvakrát, platí poslední plán", function()
    local scheduler, ctl = setup("log = []\ndef loop():\n  log.append(game_tick)")
    scheduler.add(ctl.unit, 5)
    scheduler.add(ctl.unit, 5)
    scheduler.add(ctl.unit, 7)
    ticks(scheduler, 1, 8)
    A.eq(log_of(ctl), "[7, 8]", "běhy")
  end },
  { "zastavený a chybový kontrolér se dál neplánuje", function()
    local scheduler, ctl = setup("log = []\ndef loop():\n  log.append(game_tick)\n  if game_tick == 3:\n    x = 1 / 0")
    scheduler.add(ctl.unit, 1)
    ticks(scheduler, 1, 10)
    A.eq(log_of(ctl), "[1, 2, 3]", "do chyby")
    A.eq(next(storage.schedule), nil, "plán je prázdný")
    local scheduler2, ctl2 = setup()
    scheduler2.add(ctl2.unit, 1)
    ticks(scheduler2, 1, 2)
    require("scripts.controller").stop(ctl2)
    ticks(scheduler2, 3, 10)
    A.eq(ctl2.globals.log.n, 2, "po stop už neběží")
  end },
  { "výpadek proudu: tick stojí, dt zahrne pauzu, zkouší se po 60 ticích", function()
    local scheduler, ctl, entity = setup()
    scheduler.add(ctl.unit, 1)
    ticks(scheduler, 1, 2)
    entity.energy, entity.status = 0, defines.entity_status.no_power
    ticks(scheduler, 3, 100)
    entity.energy, entity.status = 1000, defines.entity_status.working
    ticks(scheduler, 101, 200)
    -- běh v 1, 2 a 3 (skok energie = dobíhá zásobník); v ticku 4 bez proudu → pokus 64 (bez proudu) → 124 s proudem
    A.truthy(log_of(ctl):find("[(0, 1, 1), (1, 2, 1), (2, 3, 1), (3, 124, 121), ", 1, true), "po obnově: tick +1, dt = celá pauza")
    A.truthy(log_of(ctl):find("(4, 125, 1)", 1, true), "pak zase po ticku")
  end },
  { "zbytek energie menší než spotřeba ticku = bez proudu (zbouraný sloup)", function()
    local scheduler, ctl, entity = setup()
    scheduler.add(ctl.unit, 1)
    ticks(scheduler, 1, 2)
    -- zbouraný sloup: zbytek v zásobníku menší než spotřeba ticku, stav low_power, žádná síť (ověřeno ve hře)
    entity.energy, entity.status, entity.electric_network_id = 222, defines.entity_status.low_power, nil
    ticks(scheduler, 3, 50)
    A.eq(log_of(ctl), "[(0, 1, 1), (1, 2, 1), (2, 3, 1)]", "po skoku energie už bez běhu")
  end },
  { "podpětí: zásobník pod spotřebou ticku, ale síť dodává → běží", function()
    local scheduler, ctl, entity = setup()
    scheduler.add(ctl.unit, 1)
    for t = 1, 70 do
      entity.energy, entity.status = 400 + (t * 7) % 300, defines.entity_status.low_power  -- kolísá jako ve hře
      scheduler.on_tick(t)
    end
    -- první kontrola nemá s čím srovnat → další pokus za 60 ticků, pak už běží každý tick
    A.eq(ctl.globals.log.n, 10, "běží od ticku 61")
  end },
  { "výpadek proudu, pauza, play: starý výpadek se nezapočte", function()
    local scheduler, ctl, entity = setup()
    local controller = require("scripts.controller")
    scheduler.add(ctl.unit, 1)
    ticks(scheduler, 1, 2)
    entity.energy, entity.status = 0, defines.entity_status.no_power
    ticks(scheduler, 3, 10)
    controller.stop(ctl)
    entity.energy, entity.status = 1000, defines.entity_status.working
    controller.start(ctl)
    scheduler.add(ctl.unit, 300)
    ticks(scheduler, 300, 300)
    A.eq(log_of(ctl), "[(0, 1, 1), (1, 2, 1), (2, 3, 1), (3, 300, 1)]", "po play tick pokračuje o interval, dt = interval")
  end },
  { "rebuild naplánuje všechny běžící kontroléry", function()
    local scheduler, ctl = setup()
    storage.schedule = {}
    ctl.scheduled_tick = nil
    scheduler.rebuild(50)
    ticks(scheduler, 50, 51)
    A.eq(log_of(ctl), "[(0, 51, 1)]", "běží od dalšího ticku")
  end },
}
