local A = require("assert")
local errors = require("scripts.lang.errors")

return {
  { "make sestaví chybu s prefixem klíče", function()
    local e = errors.make(3, 7, "bad-indent", "x")
    A.same(e, { pyntr_error = true, line = 3, col = 7, key = "pyntr-err.bad-indent", args = { "x" } }, "chyba")
  end },
  { "raise vyhodí tabulku", function()
    local e = A.raises(function() errors.raise(1, 2, "bad-char", "$") end, "bad-char")
    A.eq(e.args[1], "$", "argument")
  end },
  { "is rozliší chybu jazyka", function()
    A.eq(errors.is(errors.make(1, 1, "x")), true, "chyba")
    A.eq(errors.is("text"), false, "řetězec")
    A.eq(errors.is({}), false, "tabulka")
  end },
  { "argumenty se převedou na text", function()
    A.eq(errors.make(nil, nil, "x", 5).args[1], "5", "číslo")
  end },
}
