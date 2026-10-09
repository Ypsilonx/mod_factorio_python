--- Stavová LED (blikátko) kreslená skriptem přes rendering (scripts/indicator.lua): bílá záře, barvu dává tint.
--- Blikání přehrává engine sám (animace se sekvencí snímků), skript jen mění stav – nestojí to výkon.

local FILE = "__Pythonator__/graphics/entity/pythonator-led.png"  -- 2 snímky 32×32: zhasnuto, svítí
--- Rytmus blikání: snímek 2 = svítí, 1 = zhasnuto; jeden krok sekvence trvá 1 / ANIMATION_SPEED ticků.
local BLINK = { 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1 }
local ANIMATION_SPEED = 0.2      -- 12 kroků × 5 ticků = 1 bliknutí za sekundu

data:extend({
  {
    type = "animation",
    name = "pyntr-led-blink",
    filename = FILE,
    width = 32,
    height = 32,
    frame_count = 2,
    line_length = 2,
    frame_sequence = BLINK,
    animation_speed = ANIMATION_SPEED,
    scale = 0.5,
    blend_mode = "additive",
  },
  {
    type = "sprite",
    name = "pyntr-led-steady",
    filename = FILE,
    width = 32,
    height = 32,
    x = 32,
    scale = 0.5,
    blend_mode = "additive",
  },
})
