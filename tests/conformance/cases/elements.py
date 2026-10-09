# ticks: 20
# Knihovna kombinátorů: stavové prvky (latch, timer, edge, counter, delay, pid).
level = 0
pulses = 0


def loop():
    global level, pulses
    level = level + 15 if tick < 10 else level - 12
    full = latch("full", level > 100, level < 40)
    if timer("t", 4):
        pulses += 1
    e = edge("full-edge", full)
    n = counter("ticks")
    k = counter("evens", 2, tick % 5 == 0)
    old = delay("level", level, 3)
    hist = delay("pair", [tick, level], 2)
    u = pid("ctl", 50, level, 0.5, 0.1, 0.25, -20, 20)
    print(tick, level, full, pulses, e, n, k, old, hist, round(u * 1000))  # celé číslo: Pythonator nerozlišuje 2 a 2.0
