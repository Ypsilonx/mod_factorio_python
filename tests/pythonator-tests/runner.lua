--- Minimalistický runner integračních testů: testy běží paralelně, každý na vlastním výřezu povrchu.
--- Výsledky jdou do logu s prefixem PYNTR-TEST, souhrn řádkem „PYNTR-TEST DONE pass=… fail=… skip=…“.
local M = {}

--- V tomto ticku se hra uloží (tools/run-tests.sh pak server ukončí a testy doběhnou po načtení uložené
--- pozice – každý test, který běží déle, tak přejde přes skutečné uložení a načtení).
M.SAVE_TICK = 60
--- Jméno automatického uložení (soubor _autosave-<jméno>.zip ve write-data/saves).
M.SAVE_NAME = "pyntr-saved"

--- Byla hra v tomto běhu načtena z uložené pozice? (on_load; v upvalue, storage měnit nesmí.)
local loaded = false

--- Načtení z uložené pozice (script.on_load).
function M.on_load() loaded = true end

--- Proběhlo v tomto běhu načtení uložené hry?
function M.was_loaded() return loaded end

--- Registrované testy (definované v kódu, ve storage je jen jejich stav podle indexu).
local cases = {}

--- Přidá seznam testů.
function M.register(list)
  for _, case in ipairs(list) do cases[#cases + 1] = case end
end

--- Zaloguje výsledek a započítá ho do souhrnu.
local function finish(state, result, message)
  state.done = true
  storage.summary[result] = storage.summary[result] + 1
  log("PYNTR-TEST " .. string.upper(result) .. " " .. cases[state.index].name .. (message and (": " .. message) or ""))
end

--- Vytvoří povrch s laboratorními dlaždicemi a spustí setup všech testů.
function M.on_init()
  local surface = game.create_surface("pyntr-test")
  surface.generate_with_lab_tiles = true
  -- Výřezy testů (8 v řadě po 24 dlaždicích od −96) rostou s počtem testů dolů – poloměr podle poslední řady,
  -- jinak testy za okrajem vygenerované oblasti padají na nesmyslné chybě („nelze postavit“).
  local bottom = math.floor((#cases - 1) / 8) * 24 - 96 + 24
  surface.request_to_generate_chunks({ 0, 0 }, math.max(8, math.ceil(bottom / 32) + 1))
  surface.force_generate_chunk_requests()
  storage.summary = { pass = 0, fail = 0, skip = 0 }
  storage.tests = {}
  for index, case in ipairs(cases) do
    local origin = { x = ((index - 1) % 8) * 24 - 96, y = math.floor((index - 1) / 8) * 24 - 96 }
    local state = { index = index, step = 1, ctx = { surface = surface, origin = origin } }
    storage.tests[index] = state
    if case.requires and not script.active_mods[case.requires] then
      finish(state, "skip", "chybí mod " .. case.requires)
    else
      local ok, err = pcall(case.setup or function() end, state.ctx)
      if ok then
        state.due = game.tick + case.steps[1].ticks
      else
        finish(state, "fail", "setup: " .. tostring(err))
      end
    end
  end
end

--- Spustí kroky, které jsou v tomto ticku na řadě; po dokončení všech testů zaloguje souhrn.
function M.on_tick(event)
  if event.tick == M.SAVE_TICK then game.auto_save(M.SAVE_NAME) end
  if storage.finished then return end
  local all_done = true
  for _, state in ipairs(storage.tests) do
    if not state.done then
      all_done = false
      if state.due == event.tick then
        local case = cases[state.index]
        local ok, err = pcall(case.steps[state.step].run, state.ctx)
        if not ok then
          finish(state, "fail", tostring(err))
        elseif state.step == #case.steps then
          finish(state, "pass")
        else
          state.step = state.step + 1
          state.due = event.tick + case.steps[state.step].ticks
        end
      end
    end
  end
  if all_done then
    storage.finished = true
    local s = storage.summary
    log(string.format("PYNTR-TEST DONE pass=%d fail=%d skip=%d", s.pass, s.fail, s.skip))
  end
end

return M
