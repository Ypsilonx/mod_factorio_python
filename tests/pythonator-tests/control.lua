-- Headless integrační testy modu Pythonator (spouští tools/run-tests.sh).
local runner = require("runner")

runner.register(require("cases.smoke"))
runner.register(require("cases.prototypes"))
runner.register(require("cases.compat"))
runner.register(require("cases.building"))
runner.register(require("cases.timing"))

script.on_init(runner.on_init)
script.on_event(defines.events.on_tick, runner.on_tick)
