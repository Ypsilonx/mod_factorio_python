-- Generováno blender/build_sprites.py (fáze render) – neupravovat ručně.
-- Body drátů a poloha stavové LED pro směry N, E, S, W v dlaždicích od středu entity.
return {
  frame_px = 224,
  frame_tiles = 3.5,
  input = {
    { wire = { red = { -0.4200, 0.2617 }, green = { 0.4200, 0.2617 } }, shadow = { red = { 0.1742, 0.7602 }, green = { 1.0142, 0.7602 } } },
    { wire = { red = { -0.6400, -0.7983 }, green = { -0.6400, 0.0417 } }, shadow = { red = { -0.0458, -0.2998 }, green = { -0.0458, 0.5402 } } },
    { wire = { red = { 0.4200, -1.0183 }, green = { -0.4200, -1.0183 } }, shadow = { red = { 1.0142, -0.5198 }, green = { 0.1742, -0.5198 } } },
    { wire = { red = { 0.6400, 0.0417 }, green = { 0.6400, -0.7983 } }, shadow = { red = { 1.2342, 0.5402 }, green = { 1.2342, -0.2998 } } },
  },
  output = {
    { wire = { red = { -0.6000, -1.0183 }, green = { 0.6000, -1.0183 } }, shadow = { red = { -0.0058, -0.5198 }, green = { 1.1942, -0.5198 } } },
    { wire = { red = { 0.6400, -0.9783 }, green = { 0.6400, 0.2217 } }, shadow = { red = { 1.2342, -0.4798 }, green = { 1.2342, 0.7202 } } },
    { wire = { red = { 0.6000, 0.2617 }, green = { -0.6000, 0.2617 } }, shadow = { red = { 1.1942, 0.7602 }, green = { -0.0058, 0.7602 } } },
    { wire = { red = { -0.6400, 0.2217 }, green = { -0.6400, -0.9783 } }, shadow = { red = { -0.0458, 0.7202 }, green = { -0.0458, -0.4798 } } },
  },
  led = {
    { 0.6600, 0.2818 },
    { -0.6000, 0.3418 },
    { -0.6600, -0.9182 },
    { 0.6000, -0.9782 },
  },
  lcd_frames = 12,
  lcd = {
    { offset = { -0.0547, -1.1875 }, width = 35, height = 22 },
    { offset = { 0.7344, -0.4922 }, width = 12, height = 45 },
    false,
    { offset = { -0.7344, -0.3828 }, width = 12, height = 45 },
  },
}
