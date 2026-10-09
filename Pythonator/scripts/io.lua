--- Vstupy a výstupy kontroléru na drátech: zdroje signálů pro inp/red/green nad konektory entity.
local R = require("scripts.lang.builtins")

local M = {}

--- Konektory vstupních zdrojů programu.
--- @return table jméno objektu → { id konektoru, id druhého konektoru | nil }
function M.input_wires()
  local W = defines.wire_connector_id
  return {
    inp = { W.combinator_input_red, W.combinator_input_green },
    red = { W.combinator_input_red },
    green = { W.combinator_input_green },
  }
end

--- Zdroj signálů pro signal_io.reader nad konektory entity. Celý seznam (`all`) se načte nejvýš jednou
--- za běh loop(); `reset()` volá kontrolér před každým během.
--- @param entity LuaEntity
--- @param wires table { id, id2 | nil }
--- @param resolver table resolver signálů
--- @return table { get(canonical) → int, all() → { {klíč, hodnota}… }, reset() }
function M.reader_source(entity, wires, resolver)
  local cached
  local source = {}

  function source.get(canonical)
    local sid = resolver:resolve(canonical)
    return entity.get_signal(sid, wires[1], wires[2])
  end

  function source.all()
    if cached then return cached end
    cached = {}
    for _, s in ipairs(entity.get_signals(wires[1], wires[2]) or {}) do
      local sig = s.signal
      local key = resolver:canonical({ type = sig.type or "item", name = sig.name, quality = sig.quality or "normal" })
      cached[#cached + 1] = { key, s.count }
    end
    table.sort(cached, function(a, b) return R.strcmp(a[1], b[1]) < 0 end)
    return cached
  end

  function source.reset() cached = nil end

  return source
end

return M
