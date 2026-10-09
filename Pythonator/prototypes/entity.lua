--- Budova Pythonator: odvozená z aritmetického kombinátoru (rotace, dráty, vstup/výstup, blueprint zdarma),
--- vlastní chování kombinátoru je vypnuté prázdnými parametry. Dočasná grafika = vanilla sprite s tintem
--- (vlastní model z Blenderu přijde v Tasku 10).

--- Jméno entity, předmětu a receptu.
local NAME = "pyntr-pythonator"
--- Spotřeba při běhu. Laditelná hodnota.
local ENERGY_USAGE = "50kW"
--- Tint dočasné grafiky a ikony (modrá Pythonu). Laditelná hodnota.
local TINT = { r = 0.55, g = 0.75, b = 1.0, a = 1.0 }

--- Prázdný sprite pro symboly operací kombinátoru (Pythonator žádnou operaci neukazuje).
local EMPTY = { filename = "__core__/graphics/empty.png", width = 1, height = 1 }
local EMPTY_4WAY = { north = EMPTY, east = EMPTY, south = EMPTY, west = EMPTY }

--- Obarví vrstvy spritu kromě stínu.
local function tint_layers(sprite)
  for _, layer in ipairs(sprite.layers or { sprite }) do
    if not layer.draw_as_shadow then layer.tint = TINT end
  end
end

local entity = table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
entity.name = NAME
entity.icon = nil
entity.icons = { { icon = "__base__/graphics/icons/arithmetic-combinator.png", tint = TINT } }
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
for _, direction in ipairs({ "north", "east", "south", "west" }) do tint_layers(entity.sprites[direction]) end
for _, key in ipairs({ "plus", "minus", "multiply", "divide", "modulo", "power", "left_shift", "right_shift",
                       "and", "or", "xor" }) do
  entity[key .. "_symbol_sprites"] = EMPTY_4WAY
end

local item = table.deepcopy(data.raw.item["arithmetic-combinator"])
item.name = NAME
item.icon = nil
item.icons = entity.icons
item.place_result = NAME
item.order = (item.order or "c") .. "-z[pythonator]"

data:extend({ entity, item })
