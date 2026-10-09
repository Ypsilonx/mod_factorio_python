def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


def classify(x):
    if x < 0:
        return "neg"
    elif x == 0:
        return "zero"
    else:
        return "pos"


def loop():
    print(fib(15), classify(-3), classify(0), classify(8))
    s = 0
    i = 0
    while i < 20:
        i += 1
        if i % 3 == 0:
            continue
        if i > 14:
            break
        s += i
    print(s, i)
    out_list = []
    for a in range(3):
        for b in range(3):
            if a == b:
                continue
            out_list.append(a * 10 + b)
    print(out_list)
    print(0 or 5, "" and 1, 1 and 2, None or "x", "yes" if [] else "no")
    a, b = 1, 2
    a, b = b, a
    print(a, b)
