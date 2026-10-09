--- Životní cyklus budovy: stavba (vznik stavu a skrytých výstupů, kód z tagů), odstranění (úklid),
--- smrt (kód do ducha), údržba po změně modů a probuzení do plánovače.
local controller = require("scripts.controller")
local indicator = require("scripts.indicator")
local io = require("scripts.io")
local scheduler = require("scripts.scheduler")

local M = {}

--- Jména prototypů z data stage (mod-data) – hledat podle nich, ne podle prefixu.
M.DATA = prototypes.mod_data["pyntr-data"].data

--- Tagy blueprintu a ducha: kód a jestli program běžel (stav se nepřenáší, nová budova začne initem).
M.TAG_CODE = "pyntr_code"
M.TAG_RUNNING = "pyntr_running"

--- Je entita Pythonator?
function M.is_ours(entity)
  return entity and entity.valid and entity.name == M.DATA.entity
end

--- Po změně stavu (nahrání kódu, Play, Pauza, Reset, Krok): naplánuje běžící kontrolér na příští tick
--- a překreslí stavovou LED.
function M.wake(ctl)
  if ctl.running and not ctl.error then scheduler.add(ctl.unit, scheduler.first_tick(ctl.unit, ctl.interval, game.tick)) end
  indicator.update(ctl)
end

--- Nahraje kód do kontroléru; `running == false` ho po inicializaci nechá pozastavený.
--- @return boolean ok, table|nil err
function M.load_code(ctl, code, running)
  local ok, err = controller.set_code(ctl, code)
  if ok and running == false then controller.stop(ctl) end
  M.wake(ctl)
  return ok, err
end

--- Postavení budovy: stav, skryté výstupy, sledování zániku a kód z tagů (blueprint, duch po smrti).
--- @param entity LuaEntity
--- @param tags table|nil
function M.on_built(entity, tags)
  -- Jiný mod může vyvolat script_raised_built pro už evidovanou budovu – druhé skryté výstupy by zůstaly viset.
  if not M.is_ours(entity) or controller.get(entity.unit_number) then return end
  M.clear_parameters(entity)
  local ctl = controller.create(entity)
  ctl.outputs = io.attach_outputs(entity, M.DATA.output)
  script.register_on_object_destroyed(entity)
  if tags and tags[M.TAG_CODE] then M.load_code(ctl, tags[M.TAG_CODE], tags[M.TAG_RUNNING] ~= false) end
end

--- Vynuluje parametry aritmetického kombinátoru (blueprint z importu nebo vložení z vanilla kombinátoru by
--- jinak budově vrátil vlastní výpočet na výstup).
function M.clear_parameters(entity)
  entity.get_or_create_control_behavior().parameters = {}
end

--- Klonování (editor, mody přesouvající stavby): klon skrytého výstupu se zničí, klon budovy dostane vlastní
--- skryté výstupy a kód zdroje (jako z blueprintu – stav se nepřenáší).
--- @param event EventData.on_entity_cloned
function M.on_cloned(event)
  local dst, src = event.destination, event.source
  if not dst.valid then return end
  if dst.name == M.DATA.output then
    dst.destroy()
    return
  end
  local ctl = src.valid and controller.get(src.unit_number)
  local tags = ctl and ctl.code ~= "" and { [M.TAG_CODE] = ctl.code, [M.TAG_RUNNING] = ctl.running } or nil
  M.on_built(dst, tags)
end

--- Posluchači odstranění budovy: function(unit_number) (GUI zavře okna nad zaniklou budovou).
--- Registrují se při načtení modulů, ne za běhu – seznam není stav hry.
M.on_removed = {}

--- Odstraní stav a skryté výstupy kontroléru (jakákoli cesta zániku budovy).
function M.remove(unit)
  local ctl = controller.get(unit)
  if not ctl then return end
  if ctl.led and ctl.led.valid then ctl.led.destroy() end
  io.detach_outputs(ctl.outputs)
  controller.destroy(unit)
  for _, f in ipairs(M.on_removed) do f(unit) end
end

--- Otočení nebo převrácení budovy: LED se přesune na nové místo.
function M.on_rotated(entity)
  local ctl = M.is_ours(entity) and controller.get(entity.unit_number)
  if ctl then indicator.update(ctl, true) end
end

--- Smrt budovy: duch dostane kód do tagů, aby ho roboti postavili i s programem.
--- @param event EventData.on_post_entity_died
function M.on_post_died(event)
  local ctl = event.unit_number and controller.get(event.unit_number)
  if ctl and event.ghost and event.ghost.valid and ctl.code ~= "" then
    local tags = event.ghost.tags or {}
    tags[M.TAG_CODE], tags[M.TAG_RUNNING] = ctl.code, ctl.running
    event.ghost.tags = tags
  end
  if event.unit_number then M.remove(event.unit_number) end
end

--- Údržba po změně modů nebo verze: založit tabulky, uklidit zaniklé budovy, obnovit chybějící skryté
--- výstupy (stav jejich drátu se pošle celý znovu) a přestavět plán.
function M.on_configuration_changed()
  storage.controllers = storage.controllers or {}
  for unit, ctl in pairs(storage.controllers) do
    if not ctl.entity.valid then
      M.remove(unit)
    else
      ctl.energy_usage = controller.energy_usage(ctl.entity)
      local missing = false
      for _, out in pairs(ctl.outputs or {}) do
        if not out.valid then missing = true end
      end
      if missing or not ctl.outputs then
        io.detach_outputs(ctl.outputs)
        ctl.outputs, ctl.wires = io.attach_outputs(ctl.entity, M.DATA.output), nil
        io.flush(ctl)
      end
      indicator.update(ctl, true)
    end
  end
  scheduler.rebuild(game.tick)
end

return M
