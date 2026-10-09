def loop():
    print(7 // 2, -7 // 2, 7 % 3, -7 % 3, 7 % -3)
    print(2 ** 10, 10 / 4, 1 / 3, 0.1 + 0.2)
    print(5 & 3, 5 | 3, 5 ^ 3, ~5, 1 << 4, -16 >> 2)
    print(0 < 5 < 10, 1 < 0 < 2, 3 == 3.0, True + 1)
    print(round(2.5), round(3.5), round(-2.5), round(1.234, 2))
    print(abs(-4), min(3, 1, 2), max([4, 9, 2]), int(-3.7), int("12"), float("2.5"))
    print(sum([1, 2, 3]), sum(range(5), 10), sorted([3, 1, 2]))
    print(1e20, 1.5e-7, 123456.789, -0.5)
