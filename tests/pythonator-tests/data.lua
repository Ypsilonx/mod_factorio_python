-- Napodobí Pyanodon 3.1: metody na všech dosavadních receptech přes metatabulku (kontrola v data-final-fixes.lua).
local recipe_meta = { __index = { has_category = function() return false end } }
for _, recipe in pairs(data.raw["recipe"]) do setmetatable(recipe, recipe_meta) end
