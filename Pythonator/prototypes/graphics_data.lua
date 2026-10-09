-- Generováno blender/build_sprites.py (fáze render) – neupravovat ručně.
-- Body drátů a poloha stavové LED pro směry N, E, S, W v dlaždicích od středu entity.
return {
  frame_px = 224,
  frame_tiles = 3.5,
  input = {
    { wire = { red = { -0.4200, 0.6400 }, green = { 0.4200, 0.6400 } }, shadow = { red = { -0.4200, 0.6400 }, green = { 0.4200, 0.6400 } } },
    { wire = { red = { -0.4200, 0.6400 }, green = { 0.4200, 0.6400 } }, shadow = { red = { -0.4200, 0.6400 }, green = { 0.4200, 0.6400 } } },
    { wire = { red = { -0.4200, 0.6400 }, green = { 0.4200, 0.6400 } }, shadow = { red = { -0.4200, 0.6400 }, green = { 0.4200, 0.6400 } } },
    { wire = { red = { -0.4200, 0.6400 }, green = { 0.4200, 0.6400 } }, shadow = { red = { -0.4200, 0.6400 }, green = { 0.4200, 0.6400 } } },
  },
  output = {
    { wire = { red = { -0.6000, -0.6400 }, green = { 0.6000, -0.6400 } }, shadow = { red = { -0.6000, -0.6400 }, green = { 0.6000, -0.6400 } } },
    { wire = { red = { -0.6000, -0.6400 }, green = { 0.6000, -0.6400 } }, shadow = { red = { -0.6000, -0.6400 }, green = { 0.6000, -0.6400 } } },
    { wire = { red = { -0.6000, -0.6400 }, green = { 0.6000, -0.6400 } }, shadow = { red = { -0.6000, -0.6400 }, green = { 0.6000, -0.6400 } } },
    { wire = { red = { -0.6000, -0.6400 }, green = { 0.6000, -0.6400 } }, shadow = { red = { -0.6000, -0.6400 }, green = { 0.6000, -0.6400 } } },
  },
  led = {
    { 0.6600, 0.6000 },
    { 0.6600, 0.6000 },
    { 0.6600, 0.6000 },
    { 0.6600, 0.6000 },
  },
  lcd_frames = 12,
  lcd = {
    { offset = { -0.0547, -1.1875 }, width = 35, height = 22 },
    { offset = { 0.7344, -0.4922 }, width = 12, height = 45 },
    false,
    { offset = { -0.7344, -0.3828 }, width = 12, height = 45 },
  },
}
