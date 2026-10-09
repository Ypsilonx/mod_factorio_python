--- Budova Pythonator: odvozená z aritmetického kombinátoru (rotace, dráty, vstup/výstup, blueprint zdarma),
--- vlastní chování kombinátoru je vypnuté prázdnými parametry. Grafika z Blenderu (blender/build_sprites.py):
--- sprity 4 směrů, stín, ikony a body drátů v generovaném prototypes/graphics_data.lua.

local G = require("prototypes.graphics_data")

--- Jméno entity, předmětu a receptu.
local NAME = "pyntr-pythonator"
--- Spotřeba při běhu. Laditelná hodnota.
local ENERGY_USAGE = "50kW"
local GFX = "__Pythonator__/graphics/"

--- Prázdný sprite pro symboly operací a LED kombinátoru (Pythonator má vlastní stavovou LED – scripts/indicator).
local EMPTY = { filename = "__core__/graphics/empty.png", width = 1, height = 1 }
local EMPTY_4WAY = { north = EMPTY, east = EMPTY, south = EMPTY, west = EMPTY }

--- Sprite jednoho směru: budova + stín, snímek `index` (0 = sever) z listu 4 směrů vedle sebe.
local function direction_sprite(index)
  local x = index * G.frame_px
  return {
    layers = {
      { filename = GFX .. "entity/pythonator.png", width = G.frame_px, height = G.frame_px, x = x, scale = 0.5 },
      { filename = GFX .. "entity/pythonator-shadow.png", width = G.frame_px, height = G.frame_px, x = x, scale = 0.5,
        draw_as_shadow = true },
    },
  }
end

local entity = table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
entity.name = NAME
entity.icon = GFX .. "icons/pythonator.png"
entity.icon_size = 64
entity.icons = nil
entity.minable = { mining_time = 0.5, result = NAME }
entity.placeable_by = nil
entity.fast_replaceable_group = nil
entity.next_upgrade = nil
entity.additional_pastable_entities = nil
entity.max_health = 250
entity.collision_box = { { -0.65, -0.65 }, { 0.65, 0.65 } }
entity.selection_box = { { -1, -1 }, { 1, 1 } }
entity.input_connection_bounding_box = { { -1, 0 }, { 1, 1 } }
entity.output_connection_bounding_box = { { -1, -1 }, { 1, 0 } }
entity.active_energy_usage = ENERGY_USAGE
entity.sprites = { north = direction_sprite(0), east = direction_sprite(1), south = direction_sprite(2),
                   west = direction_sprite(3) }
entity.input_connection_points = G.input
entity.output_connection_points = G.output
entity.activity_led_sprites = EMPTY_4WAY
entity.activity_led_light = nil
entity.screen_light = nil
for _, key in ipairs({ "plus", "minus", "multiply", "divide", "modulo", "power", "left_shift", "right_shift",
                       "and", "or", "xor" }) do
  entity[key .. "_symbol_sprites"] = EMPTY_4WAY
end

local item = table.deepcopy(data.raw.item["arithmetic-combinator"])
item.name = NAME
item.icon = entity.icon
item.icon_size = 64
item.icons = nil
item.place_result = NAME
item.order = (item.order or "c") .. "-z[pythonator]"

data:extend({ entity, item })
