-- Prototypy nezávislé na jiných modech (recept a výzkum vznikají v data-final-fixes.lua).
require("prototypes.entity")
require("prototypes.hidden")
require("prototypes.led")
require("prototypes.gui")
require("prototypes.tips")

--- Jména prototypů pro runtime (hledat podle nich, ne podle prefixu – overhaul mody přidávají „pyntr-…-pyvoid“).
data:extend({
  {
    type = "mod-data",
    name = "pyntr-data",
    data = { entity = "pyntr-pythonator", output = "pyntr-output" },
  },
})
