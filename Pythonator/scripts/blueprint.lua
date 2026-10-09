--- Přenos kódu: blueprint (tagy) a copy-paste nastavení mezi budovami (Shift+klik). Přenáší se kód
--- a jestli program běžel, ne stav – nová budova začne inicializací.
local controller = require("scripts.controller")
local lifecycle = require("scripts.lifecycle")

local M = {}

--- Při vytvoření blueprintu zapíše kód každé budovy do tagů.
--- @param event EventData.on_player_setup_blueprint
function M.on_setup(event)
  local bp = event.record or event.stack
  if not bp then return end
  if bp.object_name == "LuaItemStack" and not bp.valid_for_read then return end
  for index, entity in pairs(event.mapping.get()) do
    if lifecycle.is_ours(entity) then
      local ctl = controller.get(entity.unit_number)
      if ctl and ctl.code ~= "" then
        bp.set_blueprint_entity_tag(index, lifecycle.TAG_CODE, ctl.code)
        bp.set_blueprint_entity_tag(index, lifecycle.TAG_RUNNING, ctl.running)
      end
    end
  end
end

--- Shift+pravý/levý klik: zkopíruje kód (a běh/pauzu) z jedné budovy do druhé.
--- @param event EventData.on_entity_settings_pasted
function M.on_pasted(event)
  if not (lifecycle.is_ours(event.source) and lifecycle.is_ours(event.destination)) then return end
  local src = controller.get(event.source.unit_number)
  local dst = controller.get(event.destination.unit_number)
  if src and dst and src.code ~= "" then lifecycle.load_code(dst, src.code, src.running) end
end

return M
