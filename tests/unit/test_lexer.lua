local A = require("assert")
local lexer = require("scripts.lang.lexer")

--- Kompaktní zápis tokenů "TYP:hodnota" (hodnoty SIG/STR/NUM se kontrolují zvlášť).
local function dump(src)
  local out = {}
  for _, t in ipairs(lexer.tokenize(src)) do
    if t.t == "NAME" or t.t == "KW" or t.t == "OP" then out[#out + 1] = t.t .. ":" .. t.v
    else out[#out + 1] = t.t end
  end
  return table.concat(out, " ")
end

--- Vrátí tokeny daného typu.
local function only(src, kind)
  local out = {}
  for _, t in ipairs(lexer.tokenize(src)) do if t.t == kind then out[#out + 1] = t end end
  return out
end

return {
  { "přiřazení", function()
    A.eq(dump("x = 1\n"), "NAME:x OP:= NUM NEWLINE EOF", "tokeny")
  end },
  { "bez koncového konce řádku", function()
    A.eq(dump("x = 1"), "NAME:x OP:= NUM NEWLINE EOF", "tokeny")
  end },
  { "odsazení a návrat", function()
    A.eq(dump("if a:\n    b\nc\n"),
      "KW:if NAME:a OP:: NEWLINE INDENT NAME:b NEWLINE DEDENT NAME:c NEWLINE EOF", "tokeny")
  end },
  { "prázdné řádky a komentáře se ignorují", function()
    A.eq(dump("a\n\n   # k\n# z\nb  # c\n"), "NAME:a NEWLINE NAME:b NEWLINE EOF", "tokeny")
  end },
  { "DEDENT na konci souboru", function()
    A.eq(dump("def f():\n  x\n"), "KW:def NAME:f OP:( OP:) OP:: NEWLINE INDENT NAME:x NEWLINE DEDENT EOF", "tokeny")
  end },
  { "vícenásobný návrat", function()
    A.eq(dump("if a:\n if b:\n  c\nd"),
      "KW:if NAME:a OP:: NEWLINE INDENT KW:if NAME:b OP:: NEWLINE INDENT NAME:c NEWLINE DEDENT DEDENT NAME:d NEWLINE EOF",
      "tokeny")
  end },
  { "návrat mimo úroveň = bad-indent", function()
    local e = A.raises(function() lexer.tokenize("if a:\n    b\n  c\n") end, "bad-indent")
    A.eq(e.line, 3, "řádek")
  end },
  { "míchání tabulátoru a mezer = bad-indent", function()
    A.raises(function() lexer.tokenize("if a:\n\tb\n    c\n") end, "bad-indent")
  end },
  { "tabulátor jako odsazení", function()
    A.eq(dump("if a:\n\tb\n"), "KW:if NAME:a OP:: NEWLINE INDENT NAME:b NEWLINE DEDENT EOF", "tokeny")
  end },
  { "závorky spojují řádky", function()
    A.eq(dump("x = [1,\n   2]\n"), "NAME:x OP:= OP:[ NUM OP:, NUM OP:] NEWLINE EOF", "tokeny")
  end },
  { "zpětné lomítko spojuje řádky", function()
    A.eq(dump("x = 1 + \\\n 2"), "NAME:x OP:= NUM OP:+ NUM NEWLINE EOF", "tokeny")
  end },
  { "nejdelší operátor", function()
    A.eq(dump("a **= b // c != d"), "NAME:a OP:**= NAME:b OP:// NAME:c OP:!= NAME:d NEWLINE EOF", "tokeny")
  end },
  { "řetězce a escape", function()
    local s = only([[s = "a\tb" + 'c\'d']], "STR")
    A.eq(s[1].v, "a\tb", "první")
    A.eq(s[2].v, "c'd", "druhý")
  end },
  { "trojité uvozovky přes řádky", function()
    local toks = lexer.tokenize('x = """a\nb"""\ny')
    A.eq(toks[3].v, "a\nb", "obsah")
    A.eq(toks[5].v, "y", "další jméno")
    A.eq(toks[5].line, 3, "řádek dalšího jména")
  end },
  { "neukončený řetězec", function()
    local e = A.raises(function() lexer.tokenize('x = "abc\n') end, "unterminated-string")
    A.eq(e.line, 1, "řádek")
    A.eq(e.col, 5, "sloupec")
  end },
  { "čísla", function()
    local n = only("0x1F 1_000 2.5 1e3 .5", "NUM")
    A.eq(n[1].v, 31, "hex")
    A.eq(n[2].v, 1000, "podtržítka")
    A.eq(n[3].v, 2.5, "desetinné")
    A.eq(n[4].v, 1000, "exponent")
    A.eq(n[5].v, 0.5, "začíná tečkou")
  end },
  { "špatné číslo", function()
    A.raises(function() lexer.tokenize("12abc") end, "bad-number")
  end },
  { "klíčová slova a jména", function()
    A.eq(dump("if iffy not"), "KW:if NAME:iffy KW:not NEWLINE EOF", "tokeny")
  end },
  { "nepodporované klíčové slovo", function()
    local e = A.raises(function() lexer.tokenize("import os") end, "unsupported")
    A.eq(e.args[1], "import", "slovo")
  end },
  { "f-string nepodporovaný", function()
    A.raises(function() lexer.tokenize('x = f"a{b}"') end, "unsupported")
  end },
  { "středník nepodporovaný", function()
    A.raises(function() lexer.tokenize("a = 1; b = 2") end, "unsupported")
  end },
  { "rich text tag uvnitř indexu", function()
    A.eq(dump("inp[[item=iron-plate]]"), "NAME:inp OP:[ SIG OP:] NEWLINE EOF", "tokeny")
    A.same(only("inp[[item=iron-plate]]", "SIG")[1].v,
      { stype = "item", tag = "item", name = "iron-plate", quality = "normal" }, "hodnota")
  end },
  { "tag virtuálního signálu a kvalita", function()
    local s = only("[virtual-signal=signal-A] [item=iron-plate,quality=rare]", "SIG")
    A.same(s[1].v, { stype = "virtual", tag = "virtual-signal", name = "signal-A", quality = "normal" }, "virtual")
    A.same(s[2].v, { stype = "item", tag = "item", name = "iron-plate", quality = "rare" }, "kvalita")
  end },
  { "seznam s porovnáním není tag", function()
    A.eq(dump("[a==b]"), "OP:[ NAME:a OP:== NAME:b OP:] NEWLINE EOF", "tokeny")
  end },
  { "pozice tokenů", function()
    local toks = lexer.tokenize("x = 1\n  # c\ny = 2")
    A.eq(toks[3].col, 5, "sloupec čísla")
    A.eq(toks[5].v, "y", "jméno y")
    A.eq(toks[5].line, 3, "řádek y")
    A.eq(toks[5].col, 1, "sloupec y")
  end },
  { "neplatný znak", function()
    local e = A.raises(function() lexer.tokenize("x = $") end, "bad-char")
    A.eq(e.args[1], "$", "znak")
    A.eq(e.col, 5, "sloupec")
  end },
  { "CRLF konce řádků", function()
    A.eq(dump("a\r\nb\r\n"), "NAME:a NEWLINE NAME:b NEWLINE EOF", "tokeny")
  end },
}
