--- GUI v headless hře (bez hráčů se okno postavit nedá – stavbu a obsluhu okna pokrývají unit testy s napodobeninou
--- GUI): font a styly okna existují ve hře se správným typem a obnova oken bez otevřeného okna nic nerozbije.
local H = require("helpers")

--- Styly, které okno používá (scripts/gui/*.lua), a jejich očekávaný typ.
local STYLES = {
  pyntr_code_textbox = "textbox_style", pyntr_editor_scroll = "scroll_pane_style",
  pyntr_line_number = "label_style", pyntr_log_line = "label_style", pyntr_log_scroll = "scroll_pane_style",
  pyntr_panels_scroll = "scroll_pane_style",
  caption_label = "label_style", draggable_space_header = "empty_widget_style", filter_slot_table = "table_style",
  frame_action_button = "button_style", frame_title = "label_style", heading_2_label = "label_style",
  inside_deep_frame = "frame_style", inside_shallow_frame_with_padding = "frame_style",
  negative_subheader_frame = "frame_style", slot_button = "button_style", tool_button = "button_style",
  pyntr_error_bar = "frame_style",
}

return {
  {
    name = "GUI: font pyntr-mono a styly okna existují se správným typem",
    setup = function() end,
    steps = { { ticks = 1, run = function()
      if not prototypes.font["pyntr-mono"] then error("chybí font pyntr-mono") end
      for name, stype in pairs(STYLES) do
        H.eq(prototypes.style[name], stype, "typ stylu " .. name)
      end
    end } },
  },
  {
    name = "GUI: obnova oken běží i bez otevřeného okna a s budovou v chodu",
    setup = function(ctx)
      H.power(ctx)
      ctx.p = H.pythonator(ctx, 1, 1, "n = 0\ndef loop():\n  global n\n  n += 1")
    end,
    steps = { { ticks = 35, run = function(ctx)
      local s = H.state(ctx.p)
      if s.error then error("chyba: " .. serpent.line(s.error)) end
      if tonumber(s.globals.n) < 30 then error("program neběžel") end
    end } },
  },
}
