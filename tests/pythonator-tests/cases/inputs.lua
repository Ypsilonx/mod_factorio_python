--- Čtení vstupů ve skutečné hře: inp / red / green × všechny cesty čtení (klíč, get, in, len, metody, iterace).
--- Regrese: red['x'] / green['x'] padaly na „'wire_connector_id': real number expected got nil“ – unit testy
--- to neodhalily, protože falešná entita výslovné nil přijala. Tady volá skutečné API enginu.
local H = require("helpers")

--- Program spočte pro každý vstup seznam výsledků všech cest čtení a uloží ho do globálu (repr čte test).
--- Objekt signálů nejde předat do funkce (checker: jen index, metody, len, in), proto výraz pro každý vstup zvlášť.
local CHECK = "[S['signal-A'], S.get('signal-B'), S.get('signal-B', -1), 'signal-B' in S, len(S), S.sum(), "
  .. "S.keys(), S.values(), len(S.items()), S.count('>', 0), S.max_key(), S.where('>', 4).sum()]"
local CODE = "r = 0\ng = 0\ni = 0\ndef loop():\n  global r, g, i\n"
  .. "  r = " .. CHECK:gsub("S", "red") .. "\n"
  .. "  g = " .. CHECK:gsub("S", "green") .. "\n"
  .. "  i = " .. CHECK:gsub("S", "inp") .. "\n"

return {
  {
    name = "vstupy inp / red / green: čtení po klíči, get, in, len, metody, iterace",
    setup = function(ctx)
      H.power(ctx)
      ctx.p = H.pythonator(ctx, 1, 1, CODE)
      local red = H.source(ctx, 5.5, 1.5)
      H.set_source(red, H.virtual("signal-A"), 5)
      H.wire_input(red, ctx.p, "red")
      local green = H.source(ctx, 5.5, 3.5)
      local cb = green.get_or_create_control_behavior()
      local section = cb.get_section(1) or cb.add_section()
      section.set_slot(1, { value = { type = "virtual", name = "signal-A", quality = "normal", comparator = "=" }, min = 7 })
      section.set_slot(2, { value = { type = "virtual", name = "signal-B", quality = "normal", comparator = "=" }, min = 3 })
      H.wire_input(green, ctx.p, "green")
    end,
    steps = { { ticks = 10, run = function(ctx)
      local s = H.state(ctx.p)
      if s.error then error("běh programu: " .. serpent.line(s.error)) end
      H.eq(s.globals.r, "[5, 0, -1, False, 1, 5, ['signal-A'], [5], 1, 1, 'signal-A', 5]", "red")
      H.eq(s.globals.g, "[7, 3, 3, True, 2, 10, ['signal-A', 'signal-B'], [7, 3], 2, 2, 'signal-A', 7]", "green")
      H.eq(s.globals.i, "[12, 3, 3, True, 2, 15, ['signal-A', 'signal-B'], [12, 3], 2, 2, 'signal-A', 12]", "inp")
    end } },
  },
}
