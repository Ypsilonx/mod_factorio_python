# ticks: 6
count = 0
pump_on = False
history = []
LIMITS = {"iron": (2, 4)}
active = {}


def hyst(key, value, low, high):
    if value < low:
        active[key] = True
    elif value > high:
        active[key] = False
    return active.get(key, False)


def loop():
    global count, pump_on
    count += 1
    level = (count * 3) % 7
    if level < 2:
        pump_on = True
    elif level > 5:
        pump_on = False
    history.append(level)
    if len(history) > 3:
        history.pop(0)
    for key, (low, high) in LIMITS.items():
        print(tick, count, level, pump_on, history, hyst(key, level, low, high), sum(history) // len(history))
