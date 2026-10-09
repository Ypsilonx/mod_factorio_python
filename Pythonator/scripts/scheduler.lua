--- Plánovač běhů: storage.schedule[tick] = { unit_number… }. V každém ticku se zpracují jen kontroléry
--- naplánované na tento tick (UPS – nikdy se neprochází všechny). Zastavené a chybové se nezařazují.
local controller = require("scripts.controller")

local M = {}

--- Za kolik ticků se znovu zkusí kontrolér bez proudu. Laditelná hodnota.
M.POWER_RETRY_TICKS = 60

--- Háček při změně stavu kontroléru (chyba, výpadek a obnova proudu) – control.lua sem dá překreslení LED.
M.on_state_change = function(_) end

--- Plán ve storage.
local function schedule()
  storage.schedule = storage.schedule or {}
  return storage.schedule
end

--- Naplánuje kontrolér na tick. Platí jen poslední plán (ctl.scheduled_tick); starší záznamy se při
--- zpracování přeskočí, takže dvojí zařazení nic nestojí ani nespustí loop() dvakrát.
--- @param unit integer unit_number
--- @param tick integer herní tick (> aktuální)
function M.add(unit, tick)
  local ctl = controller.get(unit)
  if not ctl or ctl.scheduled_tick == tick then return end
  ctl.scheduled_tick = tick
  local plan = schedule()
  local list = plan[tick]
  if not list then
    list = {}
    plan[tick] = list
  end
  list[#list + 1] = unit
end

--- Má budova proud? Energie v zásobníku aspoň na jeden tick, nebo se od minulé kontroly změnila.
--- Sonda (2.0.77): při podpětí se zásobník na celý tick nedoplní, ale energie tick od ticku kolísá a vanilla
--- kombinátor běží; bez zdroje i bez sloupu stojí energie na zbytku (stav je v obou případech low_power).
--- Skok energie při výpadku tak pustí ještě jeden běh – odpovídá dobíhání zásobníku.
--- @return boolean
local function powered(ctl)
  local energy = ctl.entity.energy
  local last = ctl.last_energy
  ctl.last_energy = energy
  if energy >= ctl.energy_usage then return true end
  return last ~= nil and energy ~= last
end

--- Zpracuje jeden kontrolér v jeho ticku: spustí loop() nebo počká na proud; při úspěchu přeplánuje.
local function process(ctl, tick)
  if not ctl.running or ctl.error or not ctl.entity.valid then return end
  if not powered(ctl) then
    if not ctl.outage_since then
      ctl.outage_since = tick
      M.on_state_change(ctl)
    end
    M.add(ctl.unit, tick + M.POWER_RETRY_TICKS)
    return
  end
  local lost = 0
  if ctl.outage_since then
    lost = tick - ctl.outage_since
    ctl.outage_since = nil
    M.on_state_change(ctl)
  end
  if controller.run_loop(ctl, tick, lost) then
    M.add(ctl.unit, tick + ctl.interval)
  else
    M.on_state_change(ctl)
  end
end

--- Zpracuje kontroléry naplánované na tento tick (on_tick).
--- @param tick integer
function M.on_tick(tick)
  local plan = schedule()
  local list = plan[tick]
  if not list then return end
  plan[tick] = nil
  for _, unit in ipairs(list) do
    local ctl = controller.get(unit)
    if ctl and ctl.scheduled_tick == tick then
      ctl.scheduled_tick = nil
      process(ctl, tick)
    end
  end
end

--- Přestaví plán: všechny běžící kontroléry na příští tick (on_configuration_changed, start, reset).
--- @param tick integer aktuální tick
function M.rebuild(tick)
  storage.schedule = {}
  for unit, ctl in pairs(storage.controllers or {}) do
    ctl.scheduled_tick = nil
    if ctl.running and not ctl.error then M.add(unit, tick + 1) end
  end
end

return M
