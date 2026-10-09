# ticks: 2
# Konstrukce, které překladač zrychluje (rychlé cesty) – sémantika se nesmí změnit.
d = {"b": 2, "a": 1, "c": 0}
nested = {"x": (1, 2), "y": (3, 4)}
hist = []


def loop():
    # průchod .items() / .keys() / .values(), break a continue
    total = 0
    for k, v in d.items():
        if v == 0:
            continue
        total += v
    names = []
    for k in d.keys():
        names.append(k)
        if k == "a":
            break
    vals = []
    for v in d.values():
        vals.append(v * 10)
    pairs = []
    for key, (lo, hi) in nested.items():
        pairs.append(key + str(lo + hi))
    print(total, names, vals, pairs)

    # podmíněný výraz s „nepravdivými“ větvemi
    for x in [0, 1, 2]:
        a = 0 if x else 5
        b = "" if x == 1 else "s"
        c = None if x == 2 else x
        e = False if x else True
        f = (x * 2 if x > 0 else -1) if x != 2 else 99
        print(a, b, c, e, f)

    # aritmetika a porovnání s int, float, bool a zápornými čísly
    n = -7
    print(n % 3, n // 2, 7 % -3, -7 // -2, 2.5 * 3, 1.5 + 1, True + 2, 10 - True)
    print(n < 0, 3 <= 3, 2.5 > 2, True < 2, False >= 0, 0 < n < 10, "abc" < "abd", 1 == 1.0)
    acc = 0
    for i in range(10):
        acc = (acc + i * 3) % 7
        if acc > 3 and i % 2 == 0:
            acc -= 1
    print(acc)

    # dict.get a list.append
    cnt = {}
    for w in ["a", "b", "a", "c", "a"]:
        cnt[w] = cnt.get(w, 0) + 1
    hist.append(tick)
    print(cnt, cnt.get("z"), cnt.get("z", -1), hist)
