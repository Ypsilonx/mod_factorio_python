--- Prototypy GUI: neproporcionální font editoru a styly okna. Rozměry řádku sdílí s editorem
--- (scripts/gui/editor.lua – jen konstanty, bez herního API), aby čísla řádků seděla na text.
local editor = require("scripts.gui.editor")

data:extend({
  { type = "font", name = "pyntr-mono", from = "default-mono", size = 14 },
})

local styles = data.raw["gui-style"].default

--- Vnější posuvník editoru (posouvá text i čísla řádků najednou).
styles.pyntr_editor_scroll = {
  type = "scroll_pane_style",
  parent = "deep_scroll_pane",
  padding = 4,
}

--- Textové pole kódu: neproporcionální font, bez vlastního roztahování (výšku nastavuje editor podle řádků).
styles.pyntr_code_textbox = {
  type = "textbox_style",
  parent = "textbox",
  font = "pyntr-mono",
  vertically_stretchable = "off",
}

--- Číslo řádku v gutteru: stejný font a výška řádku jako text.
styles.pyntr_line_number = {
  type = "label_style",
  parent = "label",
  font = "pyntr-mono",
  horizontal_align = "right",
  width = editor.GUTTER_WIDTH,
  height = editor.LINE_HEIGHT,
  top_padding = 0,
  bottom_padding = 0,
  right_padding = 6,
}

--- Posuvník panelů v bočním sloupci (výška jako editor).
styles.pyntr_panels_scroll = {
  type = "scroll_pane_style",
  parent = "naked_scroll_pane",
  maximal_height = editor.VIEW_HEIGHT,
  minimal_width = 270,
}

--- Rozbalovací log print() pod editorem (šířka jako editor, výška laditelná zde).
styles.pyntr_log_scroll = {
  type = "scroll_pane_style",
  parent = "deep_scroll_pane",
  -- pevná výška: prázdný log by se jinak smrskl na čárku
  height = 160,
  width = editor.outer_width(),
  padding = 4,
}

--- Řádek logu: neproporcionální font jako editor.
styles.pyntr_log_line = {
  type = "label_style",
  parent = "label",
  font = "pyntr-mono",
}

--- Pruh chyby pod editorem. Vanilla rodič má bottom_margin = -36 (sahá do prvku pod sebou – překryl by
--- lištu tlačítek) a pevnou výšku 36 (víceřádková chyba by se ořízla).
styles.pyntr_error_bar = {
  type = "frame_style",
  parent = "negative_subheader_frame",
  bottom_margin = 0,
  minimal_height = 36,
  maximal_height = 160,
  vertically_stretchable = "on",
}
