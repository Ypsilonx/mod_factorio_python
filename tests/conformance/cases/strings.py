def loop():
    s = "Hello"
    print(s + " " + "world", s * 2, len(s), s[1], s[-1], s[1:3], s[:2], s[3:])
    print(s.upper(), s.lower(), s.startswith("He"), s.endswith("lo"))
    print("a,b,,c".split(","), " x  y ".split(), "-".join(["a", "b", "c"]))
    print("a.b.c".replace(".", "/"), "ll" in s, "z" not in s)
    print(["it's", 'say "hi"'], ["a", 'b'], str(12) + "!")
    print("abc" < "abd", "B" < "a", str(None), str(True))
