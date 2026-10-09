-- Napojení událostí hry na moduly ve scripts/ (logika je v modulech, ne zde).

-- Metatabulky hodnot jazyka pro uložení hry – musí se registrovat při načtení souboru.
require("scripts.metatables")
local lifecycle = require("scripts.lifecycle")
local scheduler = require("scripts.scheduler")
local blueprint = require("scripts.blueprint")
require("scripts.remote")

local FILTERS = { { filter = "name", name = lifecycle.DATA.entity } }

script.on_init(function()
  storage.controllers = {}
  storage.schedule = {}
end)

script.on_configuration_changed(lifecycle.on_configuration_changed)

script.on_event(defines.events.on_tick, function(event) scheduler.on_tick(event.tick) end)

for _, id in ipairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}) do
  script.on_event(id, function(event) lifecycle.on_built(event.entity, event.tags) end, FILTERS)
end

for _, id in ipairs({
  defines.events.on_player_mined_entity,
  defines.events.on_robot_mined_entity,
  defines.events.on_space_platform_mined_entity,
  defines.events.script_raised_destroy,
}) do
  script.on_event(id, function(event) lifecycle.remove(event.entity.unit_number) end, FILTERS)
end

-- Smrt: až po vzniku ducha, aby do něj šel zapsat kód.
script.on_event(defines.events.on_post_entity_died, lifecycle.on_post_died,
  { { filter = "type", type = "arithmetic-combinator" } })

-- Pojistka pro zánik bez události (destroy() bez raise_destroy, jiné mody).
script.on_event(defines.events.on_object_destroyed, function(event)
  if event.type == defines.target_type.entity and event.useful_id then lifecycle.remove(event.useful_id) end
end)

script.on_event(defines.events.on_player_setup_blueprint, blueprint.on_setup)
script.on_event(defines.events.on_entity_settings_pasted, blueprint.on_pasted)

-- Vanilla okno kombinátoru by hráči dovolilo nastavit operaci a posílat vlastní výstup – do GUI z plánu 3
-- se neotevírá (kód se zatím nahrává přes remote interface "pyntr").
script.on_event(defines.events.on_gui_opened, function(event)
  if lifecycle.is_ours(event.entity) then game.get_player(event.player_index).opened = nil end
end)
