-- Vypíše konformní případy (tests/conformance) jako Lua modul pro testovací mod:
-- return { { name, source, expected, ticks }, … }. Spouští tools/run-tests.sh z kořene repozitáře.

--- Přečte soubor jako text (bez CR).
local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a"):gsub("\r", "")
  f:close()
  return s
end

local out = { "-- Generováno tools/conformance-data.lua – neupravovat.", "return {" }
for _, name in ipairs(dofile("tests/conformance/cases.lua")) do
  local src = read("tests/conformance/cases/" .. name .. ".py")
  local expected = read("tests/conformance/cases/" .. name .. ".out"):gsub("\n$", "")
  local ticks = tonumber(src:match("^# ticks: (%d+)")) or 1
  out[#out + 1] = string.format("  { name = %q, source = %q, expected = %q, ticks = %d },", name, src, expected, ticks)
end
out[#out + 1] = "}"
print(table.concat(out, "\n"))
