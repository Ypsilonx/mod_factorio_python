--- Testy kontroléru: nahrání kódu, běh loop(), čas, výstupy, chyby a obnova po načtení hry.
-- luacheck: ignore 122
---@diagnostic disable: inject-field, missing-fields
local A = require("assert")
local G = require("fake_game")

--- Čerstvé prostředí a kontrolér s falešnou entitou.
local function setup()
  G.reset()
  local controller = require("scripts.controller")
  local entity = G.entity(7)
  return controller, controller.create(entity), entity
end

--- Nahraje kód, který musí projít.
local function load(controller, ctl, src)
  local ok, err = controller.set_code(ctl, src)
  if not ok then error(err, 0) end
end

return {
  { "nahrání kódu spustí inicializaci a zapne běh", function()
    local controller, ctl = setup()
    load(controller, ctl, "x = 41 + 1\ndef loop(): pass")
    A.eq(ctl.globals.x, 42, "globál po initu")
    A.eq(ctl.running, true, "běží")
    A.eq(ctl.error, nil, "bez chyby")
  end },
  { "nový kód resetuje globály a výstupy", function()
    local controller, ctl = setup()
    load(controller, ctl, "x = 1\ny = 2\ndef loop():\n  out['signal-A'] = 5")
    controller.run_loop(ctl, 100)
    A.eq(ctl.out.both["signal-A"], 5, "výstup")
    load(controller, ctl, "x = 3\ndef loop(): pass")
    A.eq(ctl.globals.y, nil, "starý globál zmizel")
    A.eq(ctl.globals.x, 3, "nový globál")
    A.eq(next(ctl.out.both), nil, "výstupy vymazány")
  end },
  { "chyba překladu nechá běžet starý program", function()
    local controller, ctl = setup()
    load(controller, ctl, "x = 1\ndef loop():\n  global x\n  x += 1")
    local ok, err = controller.set_code(ctl, "def loop(:")
    A.eq(ok, false, "překlad selhal")
    A.truthy(err and err.key, "chyba")
    A.eq(ctl.compile_error.key, err.key, "uložená chyba překladu")
    controller.run_loop(ctl, 100)
    A.eq(ctl.globals.x, 2, "starý program běží")
  end },
  { "tick, game_tick a dt", function()
    local controller, ctl = setup()
    load(controller, ctl, "config(interval=5)\nlog = []\ndef loop():\n  log.append((tick, game_tick, dt))")
    controller.run_loop(ctl, 100)
    controller.run_loop(ctl, 105)
    controller.run_loop(ctl, 112)
    local R = require("scripts.lang.builtins")
    A.eq(R.repr(ctl.globals.log), "[(0, 100, 5), (5, 105, 5), (12, 112, 7)]", "log")
    A.eq(ctl.interval, 5, "interval z config()")
  end },
  { "stop: tick stojí, po startu dt = interval", function()
    local controller, ctl = setup()
    load(controller, ctl, "log = []\ndef loop():\n  log.append((tick, dt))")
    controller.run_loop(ctl, 10)
    controller.run_loop(ctl, 11)
    controller.stop(ctl)
    A.eq(controller.run_loop(ctl, 12), false, "zastavený neběží")
    controller.start(ctl)
    controller.run_loop(ctl, 50)
    local R = require("scripts.lang.builtins")
    A.eq(R.repr(ctl.globals.log), "[(0, 1), (1, 1), (1, 1)]", "log")
  end },
  { "vstupy z drátů: inp = červený + zelený, red/green zvlášť", function()
    local controller, ctl, entity = setup()
    entity.red["signal-A"], entity.green["signal-A"], entity.green["iron-plate"] = 3, 4, 9
    load(controller, ctl, "def loop():\n  print(inp['signal-A'], red['signal-A'], green['signal-A'], inp.keys())")
    controller.run_loop(ctl, 1)
    A.eq(ctl.prints[1], "7 3 4 ['iron-plate', 'signal-A']", "print")
  end },
  { "výstupy: hold drží, clear maže před loop()", function()
    local controller, ctl = setup()
    load(controller, ctl, "n = 0\ndef loop():\n  global n\n  n += 1\n  if n == 1:\n    out['signal-A'] = 1")
    controller.run_loop(ctl, 1)
    controller.run_loop(ctl, 2)
    A.eq(ctl.out.both["signal-A"], 1, "hold")
    load(controller, ctl, "config(outputs='clear')\nn = 0\ndef loop():\n  global n\n  n += 1\n  if n == 1:\n    out_red['signal-A'] = 1")
    controller.run_loop(ctl, 3)
    A.eq(ctl.out.red["signal-A"], 1, "první tick")
    controller.run_loop(ctl, 4)
    A.eq(ctl.out.red["signal-A"], nil, "clear")
  end },
  { "chyba běhu: stav CHYBA, loop() se dál nevolá, výstupy zůstanou", function()
    local controller, ctl = setup()
    load(controller, ctl, "n = 0\ndef loop():\n  global n\n  n += 1\n  out['signal-A'] = n\n  if n == 2:\n    x = 1 / 0")
    controller.run_loop(ctl, 1)
    A.eq(controller.run_loop(ctl, 2), false, "chyba")
    A.eq(ctl.error.key, "pyntr-err.zero-division", "klíč")
    A.eq(ctl.error.line, 7, "řádek")
    A.eq(controller.run_loop(ctl, 3), false, "už neběží")
    A.eq(ctl.globals.n, 2, "loop se nevolal")
    A.eq(ctl.out.both["signal-A"], 2, "výstup zůstal")
    A.eq(controller.start(ctl), false, "start po chybě nejde – nutné nahrát kód")
  end },
  { "chyba v inicializaci = stav CHYBA", function()
    local controller, ctl = setup()
    local ok = controller.set_code(ctl, "x = [1][3]\ndef loop(): pass")
    A.eq(ok, true, "překlad prošel")
    A.eq(ctl.error.key, "pyntr-err.index-error", "chyba initu")
  end },
  { "print drží posledních 50 řádků", function()
    local controller, ctl = setup()
    load(controller, ctl, "def loop():\n  for i in range(60):\n    print(i)")
    controller.run_loop(ctl, 1)
    A.eq(#ctl.prints, 50, "počet")
    A.eq(ctl.prints[1], "10", "nejstarší")
    A.eq(ctl.prints[50], "59", "nejnovější")
  end },
  { "pojistka paměti a limit watchdogu z nastavení", function()
    local controller, ctl = setup()
    settings.global["pyntr-memory-limit"].value = 100
    load(controller, ctl, "a = []\ndef loop():\n  for i in range(60):\n    a.append(i)")
    controller.run_loop(ctl, 60)
    A.eq(controller.run_loop(ctl, 120), false, "nad limitem")
    A.eq(ctl.error.key, "pyntr-err.memory", "paměť")
    local controller2, ctl2 = setup()
    settings.global["pyntr-watchdog-limit"].value = 100
    load(controller2, ctl2, "def loop():\n  for i in range(200):\n    pass")
    A.eq(controller2.run_loop(ctl2, 1), false, "watchdog")
    A.eq(ctl2.error.key, "pyntr-err.watchdog", "klíč")
  end },
  { "po načtení hry (prázdná cache) pokračuje stav bez inicializace", function()
    local controller, ctl = setup()
    load(controller, ctl, "n = 100\nd = {'b': 1, 'a': 2}\nz = None\ndef loop():\n  global n\n  n += 1\n  print(n, d.keys(), z)")
    controller.run_loop(ctl, 1)
    G.reset(true)
    local reloaded = require("scripts.controller")
    local again = reloaded.get(7)
    A.truthy(again == ctl, "stejný stav ze storage")
    reloaded.run_loop(again, 2)
    A.eq(again.prints[2], "102 ['b', 'a'] None", "pokračuje bez initu, pořadí dict drží")
  end },
  { "po načtení hry neprojde překlad (odebraný mod) → stav CHYBA", function()
    local controller, ctl = setup()
    load(controller, ctl, "def loop():\n  out['signal-A'] = 1")
    G.reset(true)
    prototypes.virtual_signal["signal-A"] = nil
    local reloaded = require("scripts.controller")
    A.eq(reloaded.run_loop(ctl, 5), false, "neběží")
    A.eq(ctl.error and ctl.error.key, "pyntr-err.unknown-signal", "chyba s důvodem")
  end },
  { "reset: vynuluje stav a znovu spustí init uloženého kódu, zachová běh či pauzu", function()
    local controller, ctl = setup()
    load(controller, ctl,
      "n = 0\ndef loop():\n  global n\n  n += 1\n  out['signal-A'] = n\n  print(n)\n  if n == 3:\n    x = 1 / 0")
    controller.run_loop(ctl, 1)
    controller.run_loop(ctl, 2)
    A.eq(controller.reset(ctl), true, "reset za běhu")
    A.eq(ctl.globals.n, 0, "globály od nuly")
    A.eq(ctl.tick, 0, "tick od nuly")
    A.eq(next(ctl.out.both), nil, "výstupy vymazány")
    A.eq(#ctl.prints, 0, "log vymazán")
    A.eq(ctl.running, true, "běží dál")
    for t = 3, 5 do controller.run_loop(ctl, t) end
    A.truthy(ctl.error, "chyba ve 3. loopu")
    controller.reset(ctl)
    A.eq(ctl.error, nil, "chyba smazána")
    A.eq(ctl.running, false, "po chybě zůstane pozastavený")
    A.eq(controller.start(ctl), true, "play")
  end },
  { "reset bez kódu nic nedělá", function()
    local controller, ctl = setup()
    A.eq(controller.reset(ctl), false, "není co resetovat")
  end },
  { "zbourání smaže stav", function()
    local controller, ctl = setup()
    load(controller, ctl, "def loop(): pass")
    controller.destroy(7)
    A.eq(controller.get(7), nil, "stav zmizel")
  end },
}
