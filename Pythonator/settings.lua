--- Nastavení mapy: limity pojistek jazyka (čte se za běhu ze settings.global, změna platí hned).

--- Horní mez obou limitů – vyšší hodnota by jednomu programu dovolila zabrat celý tick (UPS).
local LIMIT_MAX = 200000

data:extend({
  {
    type = "int-setting",
    name = "pyntr-watchdog-limit",
    setting_type = "runtime-global",
    default_value = 10000,
    minimum_value = 100,
    maximum_value = LIMIT_MAX,
    order = "a",
  },
  {
    type = "int-setting",
    name = "pyntr-memory-limit",
    setting_type = "runtime-global",
    default_value = 10000,
    minimum_value = 100,
    maximum_value = LIMIT_MAX,
    order = "b",
  },
})
