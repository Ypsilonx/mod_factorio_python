"""Rozložení desky Pythonatoru (čistá data bez bpy): rozměry, polohy součástek a body, kam vedou drátky.

Používá ho model (pyntr_model) i generovaná textura plošného spoje (pyntr_pcb) – plošky a potisk tak vždy
sedí pod součástkami. +Y = sever (zadní strana, výstup), kamera hry se dívá od jihu. 1 dlaždice = 1 m.
Všechny hodnoty jsou laditelné.
"""

import math

# --- Skříňka a deska ---
PLINTH = (1.86, 1.86, 0.06)      # sokl přes celou plochu 2×2
HOUSING = (1.74, 1.70, 0.22)     # skříňka pod deskou (šířka × hloubka × výška nad soklem)
STANDOFF_XY = 0.74               # distanční sloupky v rozích desky (= montážní otvory desky)
PCB_TOP = 0.42                   # horní plocha desky nad zemí
PCB_SIZE = (1.66, 1.62)
PCB_THICK = 0.03

# --- Součástky ---
CPU_POS = (0.05, 0.08)
CPU_SIZE = (0.44, 0.44, 0.05)
CPU_PINS = 9                     # vývodů na stranu
FINS = 7                         # žeber chladiče

TERMINAL_BLOCK = (0.28, 0.15, 0.10)
TERMINALS_IN = (-0.64, 0.42)     # vstup: y, vzdálenost od osy (červená vlevo, zelená vpravo)
TERMINALS_OUT = (0.64, 0.60)     # výstup: y, vzdálenost od osy (v zadních rozích, vedle LCD)
TERMINAL_HOLE_Z = 0.045          # výška otvoru pro drát nad deskou

LCD_POS = (0.0, 0.70)
LCD_SIZE = (0.72, 0.36)
LCD_TILT = 25.0                  # náklon dozadu (°) – obrazovka natočená ke kameře hry
# „Program“ na displeji: (odsazení, délka) řádků. Displej ukazuje LCD_VISIBLE řádků; běžící program je posouvá
# o řádek na snímek animace (snímků = počet řádků, pak se smyčka opakuje).
LCD_CODE = [(0, 0.55), (1, 0.70), (2, 0.45), (2, 0.62), (1, 0.38), (0, 0.50),
            (1, 0.60), (2, 0.30), (3, 0.52), (2, 0.66), (1, 0.42), (0, 0.24)]
LCD_VISIBLE = 6

LED_POS = (0.66, -0.60)
LED_R = 0.04

# Čipy DIP: (x, y, natočení °, délka)
DIPS = [(-0.47, 0.40, 0, 0.26), (-0.47, 0.13, 0, 0.26), (0.58, -0.12, 90, 0.30), (0.50, 0.40, 0, 0.22)]
# Kondenzátory: (x, y, poloměr, výška)
CAPS = [(-0.22, -0.30, 0.045, 0.11), (-0.10, -0.32, 0.035, 0.08), (0.36, -0.36, 0.05, 0.12),
        (0.68, 0.15, 0.035, 0.08), (-0.66, -0.18, 0.04, 0.10), (0.30, 0.44, 0.03, 0.07), (-0.66, 0.58, 0.05, 0.13)]
# Rezistory: (x, y, natočení °)
RESISTORS = [(-0.30, 0.56, 0), (-0.14, 0.56, 0), (0.68, 0.30, 90), (0.68, -0.40, 90), (-0.66, 0.02, 90)]
CRYSTAL = (-0.24, 0.30)
COIL = (0.22, -0.54)
FUSE = (-0.58, -0.42)

# Hřebínky pinů pro drátky: jméno → (střed x, y, počet sloupců, počet řad, natočení °)
PIN_PITCH = 0.042
HEADERS = {
    "main": (-0.10, -0.50, 8, 2, 0),     # hlavní hřebínek vpředu
    "cpu_s": (0.05, -0.24, 5, 1, 0),     # vstupy procesoru (jih)
    "cpu_n": (0.05, 0.39, 5, 1, 0),      # výstupy procesoru (sever)
    "dips": (-0.47, 0.265, 4, 1, 0),     # mezi levými čipy
    "right": (0.40, -0.12, 4, 1, 90),    # vedle pravého čipu
    "left": (-0.70, -0.30, 3, 1, 90),    # u pojistky
}

# Propojovací drátky: (materiál, začátek, konec, výška oblouku, vybočení do strany).
# Konec = ("pin", hřebínek, sloupec, řada) – drátek s konektorem Dupont nasazeným na pin,
#         ("term", "in"|"out", "red"|"green", otvor 0|1) – drát vodorovně do otvoru svorkovnice.
JUMPERS = [
    ("wire_red", ("term", "in", "red", 1), ("pin", "cpu_s", 0, 0), 0.10, -0.04),
    ("wire_green", ("term", "in", "green", 0), ("pin", "cpu_s", 4, 0), 0.12, 0.05),
    ("wire_red", ("pin", "cpu_n", 0, 0), ("term", "out", "red", 1), 0.14, 0.05),
    ("wire_green", ("pin", "cpu_n", 4, 0), ("term", "out", "green", 0), 0.12, -0.05),
    ("jumper_yellow", ("pin", "main", 1, 1), ("pin", "dips", 1, 0), 0.16, 0.08),
    ("jumper_blue", ("pin", "main", 4, 1), ("pin", "right", 1, 0), 0.14, -0.10),
    ("jumper_white", ("pin", "main", 0, 0), ("pin", "left", 1, 0), 0.10, -0.05),
    ("jumper_orange", ("pin", "right", 3, 0), ("pin", "cpu_n", 2, 0), 0.20, 0.12),
    ("jumper_yellow", ("pin", "main", 6, 1), ("pin", "cpu_s", 2, 0), 0.11, 0.06),
    ("jumper_blue", ("pin", "dips", 3, 0), ("pin", "cpu_n", 1, 0), 0.12, -0.06),
]


def header_pin(name, col, row):
    """Poloha pinu (x, y) hřebínku `name`."""
    x, y, cols, rows, rot = HEADERS[name]
    lx = (col - (cols - 1) / 2) * PIN_PITCH
    ly = (row - (rows - 1) / 2) * PIN_PITCH
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    return x + lx * c - ly * s, y + lx * s + ly * c


def terminal_block_pos(side, color):
    """Střed svorkovnice (x, y) – side "in"/"out", color "red"/"green"."""
    y, x_off = TERMINALS_IN if side == "in" else TERMINALS_OUT
    return (-x_off if color == "red" else x_off), y


def terminal_hole(side, color, hole):
    """Otvor pro drát ve svorkovnici: poloha (x, y) na vnitřní stěně (k procesoru) a směr ven (dx, dy)."""
    x, y = terminal_block_pos(side, color)
    bw, bd, _ = TERMINAL_BLOCK
    inward = 1.0 if y < 0 else -1.0              # vnitřní stěna míří ke středu desky
    return (x + (hole - 0.5) * bw / 2, y + inward * bd / 2), (0.0, inward)


def dip_legs(x, y, rot, length):
    """Polohy vývodů čipu DIP: [(x, y)…]."""
    legs = max(3, int(length / 0.045))
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    out = []
    for k in range(legs):
        along = -length / 2 + (k + 0.5) * length / legs
        for side in (-1, 1):
            lx, ly = along, side * 0.065
            out.append((x + lx * c - ly * s, y + lx * s + ly * c))
    return out


def cpu_pins():
    """Polohy vývodů procesoru: [(x, y, strana)…], strana s/n/w/e."""
    x, y = CPU_POS
    w, d, _ = CPU_SIZE
    step = w / (CPU_PINS + 1)
    out = []
    for i in range(1, CPU_PINS + 1):
        o = -w / 2 + i * step
        out += [(x + o, y - d / 2 - 0.02, "s"), (x + o, y + d / 2 + 0.02, "n"),
                (x - w / 2 - 0.02, y + o, "w"), (x + w / 2 + 0.02, y + o, "e")]
    return out
