def loop():
    a = [3, 1, 2]
    a.append(5)
    a.insert(0, 9)
    print(a, a.pop(), a.pop(0), a, a.index(2), len(a))
    a.remove(1)
    print(a, a[-1], a[1:], a[:-1], a * 2, a + [7])
    t = (1, 2)
    x, y = t
    print(t, (1,), (), x + y, t == (1, 2), [1, 2] == [1, 2], [1] == (1,))
    d = {"a": 1, "b": 2, "c": 3}
    d.pop("b")
    d["b"] = 4
    d["a"] = 10
    print(d, sorted(d.values()), d.get("z"), d.get("z", 0))
    for k, v in d.items():
        print(k, v)
    print(sorted(d.keys()), "a" in d, 10 in d, len(d))
    n = [[1, 2], [3]]
    n[0].append(9)
    print(n, n[0][2], [[0] * 2] * 2)
