-- Napojení událostí hry na moduly ve scripts/ (logika je v modulech, ne zde).

-- Metatabulky hodnot jazyka pro uložení hry – musí se registrovat při načtení souboru.
require("scripts.metatables")
local controller = require("scripts.controller")
local lifecycle = require("scripts.lifecycle")
local scheduler = require("scripts.scheduler")
local indicator = require("scripts.indicator")
local blueprint = require("scripts.blueprint")
local gui_events = require("scripts.gui.events")
require("scripts.remote")

local FILTERS = { { filter = "name", name = lifecycle.DATA.entity } }

-- Stavová LED se překresluje jen při změně stavu (chyba, výpadek a obnova proudu z plánovače).
scheduler.on_state_change = indicator.update

script.on_init(function()
  storage.controllers = {}
  storage.schedule = {}
end)

script.on_configuration_changed(function()
  lifecycle.on_configuration_changed()
  gui_events.on_configuration_changed()
end)

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

script.on_event(defines.events.on_entity_cloned, lifecycle.on_cloned,
  { { filter = "name", name = lifecycle.DATA.entity }, { filter = "name", name = lifecycle.DATA.output } })

-- Smrt: až po vzniku ducha, aby do něj šel zapsat kód.
script.on_event(defines.events.on_post_entity_died, lifecycle.on_post_died,
  { { filter = "type", type = "arithmetic-combinator" } })

-- Pojistka pro zánik bez události (destroy() bez raise_destroy, jiné mody).
script.on_event(defines.events.on_object_destroyed, function(event)
  if event.type == defines.target_type.entity and event.useful_id then lifecycle.remove(event.useful_id) end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, controller.refresh_settings)

for _, id in ipairs({ defines.events.on_player_rotated_entity, defines.events.on_player_flipped_entity }) do
  script.on_event(id, function(event) lifecycle.on_rotated(event.entity) end)
end

script.on_event(defines.events.on_player_setup_blueprint, blueprint.on_setup)
script.on_event(defines.events.on_entity_settings_pasted, blueprint.on_pasted)

-- Okno Pythonatoru místo vanilla okna kombinátoru (to by dovolilo nastavit operaci a vlastní výstup).
script.on_event(defines.events.on_gui_opened, gui_events.on_gui_opened)
script.on_event(defines.events.on_gui_closed, gui_events.on_gui_closed)
script.on_event(defines.events.on_gui_click, gui_events.on_gui_click)
script.on_event(defines.events.on_gui_text_changed, gui_events.on_gui_text_changed)
script.on_event(defines.events.on_player_left_game, gui_events.on_player_left_game)
script.on_event(defines.events.on_player_removed, gui_events.on_player_removed)
-- Obnova otevřených oken (bez otevřeného okna handler hned skončí).
script.on_nth_tick(gui_events.REFRESH_TICKS, gui_events.on_refresh)
