--- Rozměry PNG z Blenderu sedí s prototypy (headless hra sprity nenačítá, chybný rozměr by se ukázal až ve hře).
local A = require("assert")

--- Šířka a výška PNG ze záhlaví (IHDR).
local function png_size(path)
  local f = assert(io.open(path, "rb"))
  local head = f:read(24)
  f:close()
  local function u32(i)
    local a, b, c, d = head:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return u32(17), u32(21)
end

local G = dofile("Pythonator/prototypes/graphics_data.lua")

return {
  { "list budovy a stínu: 4 snímky vedle sebe po frame_px", function()
    for _, name in ipairs({ "pythonator", "pythonator-shadow" }) do
      local w, h = png_size("Pythonator/graphics/entity/" .. name .. ".png")
      A.eq(w, 4 * G.frame_px, name .. " šířka")
      A.eq(h, G.frame_px, name .. " výška")
    end
  end },
  { "LED, ikony a thumbnail", function()
    local cases = {
      { "Pythonator/graphics/entity/pythonator-led.png", 64, 32 },
      { "Pythonator/graphics/icons/pythonator.png", 64, 64 },
      { "Pythonator/graphics/technology/pythonator.png", 256, 256 },
      { "Pythonator/thumbnail.png", 144, 144 },
    }
    for _, c in ipairs(cases) do
      local w, h = png_size(c[1])
      A.eq(w, c[2], c[1] .. " šířka")
      A.eq(h, c[3], c[1] .. " výška")
    end
  end },
  { "animace displeje: list snímků na směr podle graphics_data (bez souboru, kde displej není vidět)", function()
    local names = { "north", "east", "south", "west" }
    A.eq(#G.lcd, 4, "4 směry")
    for i, name in ipairs(names) do
      local path = "Pythonator/graphics/entity/pythonator-lcd-" .. name .. ".png"
      local lcd = G.lcd[i]
      if lcd then
        local w, h = png_size(path)
        A.eq(w, lcd.width * G.lcd_frames, name .. " šířka")
        A.eq(h, lcd.height, name .. " výška")
      else
        A.eq(io.open(path, "rb"), nil, name .. ": bez displeje nemá zbýt starý soubor")
      end
    end
  end },
  { "body drátů a LED pro 4 směry", function()
    A.eq(#G.input, 4, "vstup")
    A.eq(#G.output, 4, "výstup")
    A.eq(#G.led, 4, "LED")
  end },
}
