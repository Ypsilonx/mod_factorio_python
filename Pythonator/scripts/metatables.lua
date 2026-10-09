--- Registrace metatabulek hodnot jazyka pro uložení hry: list, tuple, dict a None v globálech programu
--- (storage) si po načtení ponechají svou metatabulku. Musí proběhnout při načtení control.lua, ne v události.
--- Objekty signálů (inp/out…) do globálů uložit nejdou (checker: chyba signal-value), registrace nepotřebují.
local R = require("scripts.lang.builtins")

script.register_metatable("pyntr-list", R.ListMT)
script.register_metatable("pyntr-tuple", R.TupleMT)
script.register_metatable("pyntr-dict", R.DictMT)
script.register_metatable("pyntr-none", R.NoneMT)
