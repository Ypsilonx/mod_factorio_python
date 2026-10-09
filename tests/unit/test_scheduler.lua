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
    entity.status = defines.entity_status.no_power
    ticks(scheduler, 3, 100)
    entity.status = defines.entity_status.working
    ticks(scheduler, 101, 200)
    -- běh v 1 a 2; v ticku 3 bez proudu → další pokus 63 (bez proudu) → 123 s proudem
    A.truthy(log_of(ctl):find("[(0, 1, 1), (1, 2, 1), (2, 123, 121), ", 1, true), "po obnově: tick +1, dt = celá pauza")
    A.truthy(log_of(ctl):find("(3, 124, 1)", 1, true), "pak zase po ticku")
  end },
  { "výpadek proudu, pauza, play: starý výpadek se nezapočte", function()
    local scheduler, ctl, entity = setup()
    local controller = require("scripts.controller")
    scheduler.add(ctl.unit, 1)
    ticks(scheduler, 1, 2)
    entity.status = defines.entity_status.no_power
    ticks(scheduler, 3, 10)
    controller.stop(ctl)
    entity.status = defines.entity_status.working
    controller.start(ctl)
    scheduler.add(ctl.unit, 300)
    ticks(scheduler, 300, 300)
    A.eq(log_of(ctl), "[(0, 1, 1), (1, 2, 1), (1, 300, 1)]", "po play tick stojí, dt = interval")
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
