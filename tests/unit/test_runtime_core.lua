local A = require("assert")
local R = require("scripts.lang.runtime")

local function L(...) local a = { ... }; return R.list(a, select("#", ...)) end
local function T(...) local a = { ... }; return R.tuple(a, select("#", ...)) end
local function Dct(...) local a = { ... }; return R.dict(a, select("#", ...)) end

--- Kopie hodnoty jako po uložení a načtení hry: nové tabulky, stejné metatabulky (register_metatable).
local function savecopy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[savecopy(k)] = savecopy(x) end
  return setmetatable(c, getmetatable(v))
end

return {
  { "pravdivost", function()
    A.eq(R.truthy(0), false, "0"); A.eq(R.truthy(2), true, "2")
    A.eq(R.truthy(""), false, "prázdný str"); A.eq(R.truthy("a"), true, "str")
    A.eq(R.truthy(R.None), false, "None"); A.eq(R.truthy(L()), false, "prázdný list")
    A.eq(R.truthy(L(0)), true, "list"); A.eq(R.truthy(Dct()), false, "prázdný dict")
    A.raises(function() R.truthy(nil) end, "unbound")
  end },
  { "sčítání", function()
    A.eq(R.add(1, 2), 3, "čísla"); A.eq(R.add("a", "b"), "ab", "str")
    A.eq(R.add(true, 1), 2, "bool"); A.eq(R.repr(R.add(L(1), L(2))), "[1, 2]", "list")
    A.raises(function() R.add("a", 1) end, "type-error")
    A.raises(function() R.add(nil, 1) end, "unbound")
  end },
  { "dělení a zbytek po Pythonu", function()
    A.eq(R.floordiv(7, 2), 3, "7//2"); A.eq(R.floordiv(-7, 2), -4, "-7//2")
    A.eq(R.mod(-7, 3), 2, "-7%3"); A.eq(R.mod(7, -3), -2, "7%-3")
    A.eq(R.truediv(10, 4), 2.5, "10/4"); A.eq(R.pow(2, 10), 1024, "2**10")
    A.raises(function() R.truediv(1, 0) end, "zero-division")
    A.raises(function() R.floordiv(1, 0) end, "zero-division")
    A.raises(function() R.mod(1, 0) end, "zero-division")
  end },
  { "násobení sekvencí", function()
    A.eq(R.mul("ab", 3), "ababab", "str*int"); A.eq(R.mul(2, "x"), "xx", "int*str")
    A.eq(R.repr(R.mul(L(1), 2)), "[1, 1]", "list*int")
    A.raises(function() R.mul("a", "b") end, "type-error")
  end },
  { "bitové operace int32", function()
    A.eq(R.band(5, 3), 1, "&"); A.eq(R.bor(5, 3), 7, "|"); A.eq(R.bxor(5, 3), 6, "^")
    A.eq(R.invert(5), -6, "~"); A.eq(R.lshift(1, 4), 16, "<<"); A.eq(R.rshift(-16, 2), -4, ">>")
    A.eq(R.lshift(1, 31), -2147483648, "přetečení do znaménka")
    A.raises(function() R.band(1.5, 1) end, "type-error")
    A.raises(function() R.lshift(1, -1) end, "negative-shift")
  end },
  { "wrap32", function()
    A.eq(R.wrap32(2147483648), -2147483648, "2^31"); A.eq(R.wrap32(-1), -1, "-1")
    A.eq(R.wrap32(4294967297), 1, "2^32+1")
  end },
  { "rovnost", function()
    A.eq(R.eq(1, true), true, "1 == True"); A.eq(R.eq(L(1, 2), L(1, 2)), true, "list")
    A.eq(R.eq(Dct("a", 1, "b", 2), Dct("b", 2, "a", 1)), true, "dict bez ohledu na pořadí")
    A.eq(R.eq(R.None, R.None), true, "None"); A.eq(R.eq("a", 1), false, "str vs int")
    A.eq(R.eq(L(1), T(1)), false, "list vs tuple"); A.eq(R.ne(1, 2), true, "!=")
  end },
  { "uspořádání", function()
    A.eq(R.lt(1, 2), true, "čísla"); A.eq(R.lt("B", "a"), true, "str po bajtech")
    A.eq(R.lt(L(1, 2), L(1, 3)), true, "list lexikograficky"); A.eq(R.le(L(1), L(1)), true, "<=")
    A.eq(R.gt(3, 2), true, ">"); A.eq(R.ge(2, 2), true, ">=")
    A.raises(function() R.lt("a", 1) end, "type-error")
  end },
  { "in a is", function()
    A.eq(R.contains("abc", "b"), true, "podřetězec"); A.eq(R.contains(L(1, 2), 2), true, "list")
    A.eq(R.contains(Dct("k", 1), "k"), true, "klíč dict"); A.eq(R.contains(Dct("k", 1), 1), false, "hodnota není klíč")
    A.eq(R.is_(R.None, R.None), true, "None is None"); A.eq(R.is_(0, R.None), false, "0 is None")
  end },
  { "str a repr", function()
    A.eq(R.str(3), "3", "int"); A.eq(R.str(2.5), "2.5", "float"); A.eq(R.str(0.1), "0.1", "0.1")
    A.eq(R.str(1 / 3), "0.3333333333333333", "1/3"); A.eq(R.str(1e20), "1e+20", "velké")
    A.eq(R.str(-7), "-7", "záporné"); A.eq(R.str(true), "True", "bool"); A.eq(R.str("x"), "x", "str")
    A.eq(R.repr("it's"), "\"it's\"", "apostrof"); A.eq(R.repr("a\nb"), "'a\\nb'", "escape")
    A.eq(R.repr(L(1, "a", R.None, true)), "[1, 'a', None, True]", "list")
    A.eq(R.repr(T(1)), "(1,)", "jednoprvková n-tice"); A.eq(R.repr(T()), "()", "prázdná n-tice")
    A.eq(R.repr(Dct("a", 1)), "{'a': 1}", "dict")
  end },
  { "indexování", function()
    A.eq(R.getitem(L(1, 2, 3), -1), 3, "záporný index"); A.eq(R.getitem("abc", 1), "b", "str")
    A.raises(function() R.getitem(L(1), 1) end, "index-error")
    A.raises(function() R.getitem(L(1), "a") end, "bad-index-type")
    A.eq(A.raises(function() R.getitem(Dct(), "x") end, "key-error").args[1], "'x'", "repr klíče")
    A.raises(function() R.setitem(T(1), 0, 2) end, "immutable")
    local l = L(1, 2); R.setitem(l, -1, 5); A.eq(R.repr(l), "[1, 5]", "setitem list")
  end },
  { "řezy", function()
    A.eq(R.repr(R.slice(L(1, 2, 3), 1, nil)), "[2, 3]", "[1:]")
    A.eq(R.repr(R.slice(L(1, 2, 3), nil, -1)), "[1, 2]", "[:-1]")
    A.eq(R.repr(R.slice(L(1, 2, 3), 5, 10)), "[]", "mimo rozsah")
    A.eq(R.slice("hello", 1, 3), "el", "str")
    A.eq(R.repr(R.slice(T(1, 2), nil, nil)), "(1, 2)", "tuple")
  end },
  { "pořadí dict po smazání a znovuvložení", function()
    local d = Dct("a", 1, "b", 2, "c", 3)
    A.eq(R.dict_del(d, "b"), 2, "smazaná hodnota")
    R.dict_set(d, "b", 4)
    local keys = {}
    for k in R.iter(d) do keys[#keys + 1] = k end
    A.eq(table.concat(keys, ","), "a,c,b", "pořadí klíčů")
  end },
  { "iterace", function()
    local s = {}
    for x in R.iter(L(1, 2)) do s[#s + 1] = R.str(x) end
    for x in R.iter("ab") do s[#s + 1] = x end
    A.eq(table.concat(s, ","), "1,2,a,b", "list a str")
    A.raises(function() R.iter(5) end, "not-iterable")
  end },
  { "rozbalení", function()
    local a, b = R.unpack(T(1, 2), 2)
    A.eq(a + b, 3, "hodnoty")
    A.raises(function() R.unpack(T(1, 2, 3), 2) end, "unpack-count")
  end },
  { "kopie None/list/dict bez identity (uložení hry)", function()
    local none, list, dict = savecopy(R.None), savecopy(L(1, R.None)), savecopy(Dct("k", L(2)))
    A.eq(R.truthy(none), false, "None nepravdivé")
    A.eq(R.is_(none, R.None), true, "None is None")
    A.eq(R.eq(none, R.None), true, "None == None")
    A.eq(R.repr(list), "[1, None]", "list")
    A.eq(R.repr(R.getitem(dict, "k")), "[2]", "dict")
  end },
  { "and/or v hodnotovém kontextu", function()
    A.eq(R.or_(0, function() return 5 end), 5, "0 or 5")
    A.eq(R.and_("", function() error("nevyhodnocovat") end), "", "'' and …")
    A.eq(R.and_(1, function() return 7 end), 7, "1 and 7")
  end },
}
