--- Vstupy a výstupy kontroléru na drátech: zdroje signálů pro inp/red/green nad konektory entity
--- a zápis výstupů do dvou skrytých konstantních kombinátorů (jeden na červený, druhý na zelený drát).
local R = require("scripts.lang.builtins")
local resolver = require("scripts.resolver")

local M = {}

--- Počet slotů v jedné sekci konstantního kombinátoru (utility-constants max_logistic_filter_count).
M.SECTION_SLOTS = 1000

--- Postaví skryté výstupy pod budovou a připojí je skriptovým drátem k jejím výstupním konektorům.
--- @param entity LuaEntity Pythonator
--- @param output_name string jméno prototypu skrytého výstupu (mod-data)
--- @return table { red = LuaEntity, green = LuaEntity }
function M.attach_outputs(entity, output_name)
  local W = defines.wire_connector_id
  local outputs = {}
  for wire, ids in pairs({ red = { W.combinator_output_red, W.circuit_red },
                           green = { W.combinator_output_green, W.circuit_green } }) do
    local out = entity.surface.create_entity({ name = output_name, position = entity.position, force = entity.force,
                                               create_build_effect_smoke = false })
    out.destructible = false
    entity.get_wire_connector(ids[1], true).connect_to(out.get_wire_connector(ids[2], true), false,
                                                       defines.wire_origin.script)
    outputs[wire] = out
  end
  return outputs
end

--- Zničí skryté výstupy (zbourání budovy).
function M.detach_outputs(outputs)
  for _, out in pairs(outputs or {}) do
    if out.valid then out.destroy() end
  end
end

--- Požadovaný výstup drátu: out + out_red/out_green, součet přeteče do int32 jako v obvodové síti.
local function desired(both, single)
  local sum = {}
  for k, v in pairs(both) do sum[k] = v end
  for k, v in pairs(single) do sum[k] = R.wrap32((sum[k] or 0) + v) end
  for k, v in pairs(sum) do
    if v == 0 then sum[k] = nil end
  end
  return sum
end

--- Sekce a slot v ní pro globální index slotu (sekce se přidávají podle potřeby).
local function section_slot(cb, index)
  local s = math.floor((index - 1) / M.SECTION_SLOTS) + 1
  while cb.sections_count < s do cb.add_section() end
  return cb.get_section(s), (index - 1) % M.SECTION_SLOTS + 1
end

--- Zapíše do jednoho skrytého výstupu jen rozdíl proti minule odeslanému stavu.
--- @param out LuaEntity skrytý konstantní kombinátor
--- @param state table { sent = {klíč → hodnota}, slot = {klíč → index}, free = {index…}, top = max index }
--- @param want table klíč → hodnota
local function flush_wire(out, state, want)
  local cb
  for key in pairs(state.sent) do
    if want[key] == nil then
      cb = cb or out.get_or_create_control_behavior()
      local index = state.slot[key]
      local section, slot = section_slot(cb, index)
      section.clear_slot(slot)
      state.sent[key], state.slot[key] = nil, nil
      state.free[#state.free + 1] = index
    end
  end
  local res = resolver.get()
  for key, value in pairs(want) do
    if state.sent[key] ~= value then
      cb = cb or out.get_or_create_control_behavior()
      local index = state.slot[key]
      if not index then
        index = table.remove(state.free)
        if not index then
          state.top = state.top + 1
          index = state.top
        end
        state.slot[key] = index
      end
      local sid = res:resolve(key)
      local section, slot = section_slot(cb, index)
      section.set_slot(slot, { value = { type = sid.type, name = sid.name, quality = sid.quality, comparator = "=" },
                               min = value })
      state.sent[key] = value
    end
  end
end

--- Zapíše výstupy kontroléru na dráty (jen změny proti minulému zápisu). Neplatný výstup se přeskočí –
--- obnoví ho údržba budovy a stav jeho drátu se pak pošle celý znovu.
--- @param ctl table kontrolér s ctl.outputs = { red, green } a ctl.out = { both, red, green }
function M.flush(ctl)
  ctl.wires = ctl.wires or {}
  for wire, out in pairs(ctl.outputs) do
    local state = ctl.wires[wire]
    if not state then
      state = { sent = {}, slot = {}, free = {}, top = 0 }
      ctl.wires[wire] = state
    end
    if out.valid then flush_wire(out, state, desired(ctl.out.both, ctl.out[wire])) end
  end
end

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

--- Sdílené čtení sítí v rámci jednoho ticku: id červené sítě → id zelené → převedené pole signálů.
--- Hodnoty na síti se během ticku nemění (engine je přepočte až na jeho konci), takže budovy na téže síti
--- mohou výsledek sdílet – get_signals je nejdražší část čtení. Stav je odvozený a v každém ticku nový
--- (deterministické, do storage nepatří).
local shared_tick, shared = nil, {}

--- Zdroj signálů pro signal_io.reader nad konektory entity. Celý seznam (`all`) se načte nejvýš jednou
--- za běh loop() a budovy na téže síti ho v jednom ticku sdílí; `reset(tick)` volá kontrolér před každým během.
--- @param entity LuaEntity
--- @param wires table { id, id2 | nil }
--- @param res table resolver signálů
--- @return table { get(canonical) → int, all() → { {klíč, hodnota}… } (neměnit – sdílené), reset(tick) }
function M.reader_source(entity, wires, res)
  local cached, tick
  -- Klíče z minula v pořadí hry a jejich seřazené pořadí: hra vrací signály každý tick ve stejném
  -- pořadí, řadit (porovnání po bajtech v Lua je drahé) je potřeba jen při změně sady signálů.
  local last_keys, last_order
  local source = {}

  function source.get(canonical)
    local sid = res:resolve(canonical)
    return entity.get_signal(sid, wires[1], wires[2])
  end

  function source.all()
    if cached then return cached end
    local w1, w2 = wires[1], wires[2]
    local net1 = entity.get_circuit_network(w1)
    local net2 = w2 and entity.get_circuit_network(w2)
    local id1, id2 = net1 and net1.network_id or 0, net2 and net2.network_id or 0
    if id1 == 0 and id2 == 0 then
      cached = {}
      return cached
    end
    local slot
    if tick then
      if shared_tick ~= tick then shared_tick, shared = tick, {} end
      slot = shared[id1]
      if not slot then
        slot = {}
        shared[id1] = slot
      end
      if slot[id2] then
        cached = slot[id2]
        return cached
      end
    end
    local signals
    if id1 ~= 0 and id2 ~= 0 then signals = entity.get_signals(w1, w2)
    elseif id1 ~= 0 then signals = entity.get_signals(w1)
    else signals = entity.get_signals(w2) end
    signals = signals or {}
    local n = #signals
    local keys = {}
    local same = last_keys ~= nil and #last_keys == n
    for i = 1, n do
      local key = res:canonical(signals[i].signal)
      keys[i] = key
      if same and last_keys[i] ~= key then same = false end
    end
    if not same then
      local order = {}
      for i = 1, n do order[i] = i end
      table.sort(order, function(a, b) return R.strcmp(keys[a], keys[b]) < 0 end)
      last_keys, last_order = keys, order
    end
    cached = {}
    for j = 1, n do
      local i = last_order[j]
      cached[j] = { keys[i], signals[i].count }
    end
    if slot then slot[id2] = cached end
    return cached
  end

  --- Nový běh loop() v herním ticku `t` (nil = bez sdílení mezi budovami).
  function source.reset(t) cached, tick = nil, t end

  return source
end

return M
