--- Pomocné funkce integračních testů: proud, stavba Pythonatoru, dráty, signály.
local M = {}

M.DATA = prototypes.mod_data["pyntr-data"].data
local W = defines.wire_connector_id

--- SignalID virtuálního signálu.
function M.virtual(name) return { type = "virtual", name = name, quality = "normal" } end

--- Postaví zdroj energie a rozvodnu, která pokryje výřez testu.
--- @return LuaEntity rozvodna (zbouráním se vypne proud)
function M.power(ctx)
  local o = ctx.origin
  local eei = ctx.surface.create_entity({ name = "electric-energy-interface", position = { o.x + 10, o.y + 10 }, force = "player" })
  eei.power_production = 1e9
  eei.electric_buffer_size = 1e10
  return ctx.surface.create_entity({ name = "substation", position = { o.x + 6, o.y + 6 }, force = "player" })
end

--- Postaví Pythonator (s raise_built – jako by ho postavil hráč) a případně nahraje kód.
--- @return LuaEntity
function M.pythonator(ctx, dx, dy, code)
  local e = ctx.surface.create_entity({ name = M.DATA.entity, position = { ctx.origin.x + (dx or 1), ctx.origin.y + (dy or 1) },
                                        force = "player", raise_built = true })
  if code then
    local ok, err = remote.call("pyntr", "set_code", e.unit_number, code)
    if not ok then error("překlad: " .. serpent.line(err)) end
  end
  return e
end

--- Konstantní kombinátor jako zdroj signálů.
function M.source(ctx, dx, dy)
  return ctx.surface.create_entity({ name = "constant-combinator", position = { ctx.origin.x + dx, ctx.origin.y + dy },
                                     force = "player" })
end

--- Nastaví signál zdroje (slot 1 první sekce).
function M.set_source(source, sid, value)
  local cb = source.get_or_create_control_behavior()
  local section = cb.get_section(1) or cb.add_section()
  section.set_slot(1, { value = { type = sid.type, name = sid.name, quality = sid.quality, comparator = "=" }, min = value })
end

--- Propojí červeným drátem výstup zdroje se vstupem kombinátoru.
function M.wire_input(source, target)
  source.get_wire_connector(W.circuit_red, true).connect_to(target.get_wire_connector(W.combinator_input_red, true), false)
end

--- Hodnota signálu na výstupní síti kombinátoru (drát "red" nebo "green").
function M.output(entity, sid, wire)
  return entity.get_signal(sid, wire == "green" and W.combinator_output_green or W.combinator_output_red)
end

--- Počet skrytých výstupů v okolí pozice.
function M.hidden_count(ctx)
  return ctx.surface.count_entities_filtered({ name = M.DATA.output, area = { { ctx.origin.x - 2, ctx.origin.y - 2 },
                                                                           { ctx.origin.x + 20, ctx.origin.y + 20 } } })
end

--- Stav kontroléru přes remote.
function M.state(entity) return remote.call("pyntr", "get_state", entity.unit_number) end

--- Vyhodí chybu, pokud a ~= b.
function M.eq(a, b, what)
  if a ~= b then error(what .. ": čekáno " .. tostring(b) .. ", dostáno " .. tostring(a), 2) end
end

return M
