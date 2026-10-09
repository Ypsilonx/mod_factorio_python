--- Malá sada jmen prototypů pro testy (místo prototypes.* ve hře). "water" je schválně item i fluid.
return function()
  return {
    item = { ["iron-plate"] = true, ["copper-plate"] = true, ["iron-gear-wheel"] = true,
             ["assembling-machine-1"] = true, water = true, coal = true, ["iron-ore"] = true },
    fluid = { water = true, ["crude-oil"] = true, ["petroleum-gas"] = true },
    virtual = { ["signal-A"] = true, ["signal-B"] = true, ["signal-I"] = true, ["signal-P"] = true,
                ["signal-S"] = true, ["signal-U"] = true },
    recipe = { ["iron-plate"] = true, ["iron-gear-wheel"] = true },
    entity = { ["assembling-machine-1"] = true },
    ["space-location"] = { nauvis = true },
    ["asteroid-chunk"] = {},
    quality = { normal = true, uncommon = true, rare = true, epic = true, legendary = true },
  }
end
