--- Animace displeje (rolující řádky kódu) kreslená skriptem přes rendering (scripts/indicator.lua): jeden list
--- snímků na směr budovy (N, E, S, W), výřez s polohou z graphics_data.lua (generuje blender/build_sprites.py).
--- Rychlost určuje skript při kreslení (běh = rolování, pauza a chyba = zastavený text).
local graphics = require("prototypes.graphics_data")

local DIRECTIONS = { "north", "east", "south", "west" }

local list = {}
for i, name in ipairs(DIRECTIONS) do
  local lcd = graphics.lcd[i]
  -- false = v tomto směru je displej otočený od kamery a text není vidět
  if lcd then
    list[#list + 1] = {
      type = "animation",
      name = "pyntr-lcd-" .. i,
      filename = "__Pythonator__/graphics/entity/pythonator-lcd-" .. name .. ".png",
      width = lcd.width,
      height = lcd.height,
      frame_count = graphics.lcd_frames,
      line_length = graphics.lcd_frames,
      animation_speed = 1,
      scale = 0.5,
    }
  end
end
data:extend(list)
