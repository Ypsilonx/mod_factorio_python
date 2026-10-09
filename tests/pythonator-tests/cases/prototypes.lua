--- Prototypy ve vanilla hře: budova 2×2 jde postavit, skrytý výstup nejde vybrat, výzkum má modrou vědu.
local DATA = prototypes.mod_data["pyntr-data"].data

return {
  {
    name = "budova 2×2 jde postavit a má vstup i výstup",
    setup = function(ctx)
      ctx.entity = ctx.surface.create_entity({ name = DATA.entity, position = { ctx.origin.x + 1, ctx.origin.y + 1 },
                                               force = "player" })
    end,
    steps = { { ticks = 1, run = function(ctx)
      local e = ctx.entity
      if not (e and e.valid) then error("entita nevznikla") end
      local box = e.prototype.collision_box
      if box.right_bottom.x - box.left_top.x < 1.2 then error("není 2×2") end
      for _, id in ipairs({ "combinator_input_red", "combinator_input_green", "combinator_output_red", "combinator_output_green" }) do
        if not e.get_wire_connector(defines.wire_connector_id[id], true) then error("chybí konektor " .. id) end
      end
    end } },
  },
  {
    name = "skrytý výstup nejde vybrat ani dát do blueprintu",
    steps = { { ticks = 1, run = function()
      local p = prototypes.entity[DATA.output]
      if p.selectable_in_game then error("výstup jde vybrat") end
      if not p.has_flag("not-blueprintable") then error("výstup jde do blueprintu") end
    end } },
  },
  {
    name = "výzkum ve vanille: modrá věda a prerekvizita circuit-network",
    steps = { { ticks = 1, run = function()
      local tech = prototypes.technology[DATA.entity]
      if not tech then error("chybí výzkum") end
      local packs = {}
      for _, ing in ipairs(tech.research_unit_ingredients) do packs[ing.name] = true end
      if not packs["chemical-science-pack"] then error("chybí modrá věda") end
      local closure, stack = {}, { tech }
      while #stack > 0 do
        for name, pre in pairs(table.remove(stack).prerequisites) do
          if not closure[name] then closure[name] = true; stack[#stack + 1] = pre end
        end
      end
      if not closure["circuit-network"] then error("chybí circuit-network") end
    end } },
  },
}
