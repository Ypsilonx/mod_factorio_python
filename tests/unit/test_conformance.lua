local A = require("assert")
local P = require("prog_runner")

--- Přečte soubor jako text (bez CR).
local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a"):gsub("\r", "")
  f:close()
  return s
end

local cases = {}
for _, name in ipairs(dofile("tests/conformance/cases.lua")) do
  cases[#cases + 1] = { "konformita " .. name, function()
    local src = read("tests/conformance/cases/" .. name .. ".py")
    local expected = read("tests/conformance/cases/" .. name .. ".out"):gsub("\n$", "")
    local ticks = tonumber(src:match("^# ticks: (%d+)")) or 1
    local res, err = P.run(src, ticks)
    if not res then error(err, 0) end
    local got = res.lines:gsub("|", "\n")
    if got ~= expected then
      -- první rozdílný řádek pro čitelnou hlášku
      local gl, el = {}, {}
      for l in (got .. "\n"):gmatch("(.-)\n") do gl[#gl + 1] = l end
      for l in (expected .. "\n"):gmatch("(.-)\n") do el[#el + 1] = l end
      for i = 1, math.max(#gl, #el) do
        A.eq(gl[i], el[i], name .. " řádek " .. i)
      end
    end
  end }
end
return cases
