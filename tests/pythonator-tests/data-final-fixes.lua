-- Regrese: recept Pythonatoru vytvořený v našem data-final-fixes musí převzít metatabulku ostatních receptů
-- (Pyanodon 3.1 na něj volá `recipe:has_category` a bez ní hra při načítání spadne). S Pyanodonem mají recepty
-- metatabulky dvě (napodobenina z data.lua a Py), proto se kontroluje jen, že nějakou má.
for name, recipe in pairs(data.raw["recipe"]) do
  if name:find("^pyntr%-") and not getmetatable(recipe) then
    error("PYNTR-TEST: recept " .. name .. " nemá metatabulku ostatních receptů")
  end
end
