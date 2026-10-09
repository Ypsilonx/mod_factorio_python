--- Základní kontrola: mod se načte a nastavení mapy mají výchozí hodnoty.
return {
  {
    name = "nastavení mapy existují s výchozími hodnotami",
    steps = { { ticks = 1, run = function()
      for _, name in ipairs({ "pyntr-watchdog-limit", "pyntr-memory-limit" }) do
        local value = settings.global[name].value
        if value ~= 10000 then error(name .. " = " .. tostring(value)) end
      end
    end } },
  },
}
