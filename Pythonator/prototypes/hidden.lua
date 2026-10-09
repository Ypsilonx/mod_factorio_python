--- Skrytý konstantní kombinátor pro výstupy: skript ho postaví pod Pythonator a propojí drátem
--- (wire_origin.script) s jeho výstupním konektorem. Hráč ho nevidí, nevybere, nevytěží ani nedá do blueprintu.

local output = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
output.name = "pyntr-output"
output.icon = nil
output.icons = data.raw["constant-combinator"]["constant-combinator"].icons
  or { { icon = data.raw["constant-combinator"]["constant-combinator"].icon } }
output.flags = { "not-on-map", "not-blueprintable", "not-deconstructable", "not-upgradable", "placeable-off-grid",
                 "hide-alt-info", "no-copy-paste", "not-in-kill-statistics", "not-repairable", "not-flammable" }
output.hidden = true
output.hidden_in_factoriopedia = true
output.selectable_in_game = false
output.minable = nil
output.fast_replaceable_group = nil
output.next_upgrade = nil
output.corpse = nil
output.dying_explosion = nil
output.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
output.selection_box = nil
output.collision_mask = { layers = {} }
output.sprites = nil
output.activity_led_sprites = nil
output.activity_led_light = nil
output.draw_circuit_wires = false
output.circuit_wire_max_distance = 3

data:extend({ output })
