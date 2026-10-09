"""Generovaná textura plošného spoje: nepájivá maska, cesty pod maskou s ohyby 45°, cínové plošky pod
součástkami, prokovy, montážní otvory a bílý potisk (obrysy součástek, značky, název desky).

Kreslí se v numpy podle pyntr_layout, takže plošky a potisk sedí pod součástkami modelu. Výsledek je obrázek
(RGB = barva v sRGB, A = maska kovu pro metallic) v blender/renders/pcb.png – je odvozený, necommituje se.
Náhodné cesty jsou deterministické (pevné semínko SEED).
"""

import math
import random
from pathlib import Path

import bpy
import numpy as np

import pyntr_layout as L

RESOLUTION = 1536                # px na šířku desky (~925 px/m)
SEED = 7                         # semínko náhodných cest – jiné číslo = jiný „návrh“ desky

# Barvy (sRGB 0–1) – laditelné.
MASK = (0.04, 0.22, 0.09)        # nepájivá maska
MASK_TRACE = (0.07, 0.33, 0.13)  # cesta pod maskou (světlejší, vystouplá)
TIN = (0.72, 0.72, 0.68)         # cínované plošky a prokovy
COPPER = (0.72, 0.42, 0.18)      # holá měď (montážní kroužky)
HOLE = (0.03, 0.03, 0.03)        # otvor
SILK = (0.9, 0.9, 0.85)          # potisk

TRACE_W = 0.011                  # šířka cesty (m)
SILK_W = 0.007                   # šířka čáry potisku (m)


class Canvas:
    """Kreslicí plocha v metrech (střed desky = 0, 0; +Y = sever = horní řádek obrázku)."""

    def __init__(self):
        self.w_m, self.h_m = L.PCB_SIZE
        self.px = RESOLUTION / self.w_m
        self.nx, self.ny = RESOLUTION, int(round(self.h_m * self.px))
        self.rgb = np.empty((self.ny, self.nx, 3), dtype=np.float32)
        self.rgb[:] = MASK
        self.metal = np.zeros((self.ny, self.nx), dtype=np.float32)

    def _region(self, x0, y0, x1, y1):
        """Výřez obrázku (řádky, sloupce) a souřadnice jeho pixelů v metrech pro obdélník v metrech."""
        c0 = max(0, int((min(x0, x1) + self.w_m / 2) * self.px) - 2)
        c1 = min(self.nx, int((max(x0, x1) + self.w_m / 2) * self.px) + 3)
        r0 = max(0, int((self.h_m / 2 - max(y0, y1)) * self.px) - 2)
        r1 = min(self.ny, int((self.h_m / 2 - min(y0, y1)) * self.px) + 3)
        if c0 >= c1 or r0 >= r1:
            return None
        xs = (np.arange(c0, c1) + 0.5) / self.px - self.w_m / 2
        ys = self.h_m / 2 - (np.arange(r0, r1) + 0.5) / self.px
        gx, gy = np.meshgrid(xs, ys)
        return (slice(r0, r1), slice(c0, c1)), gx, gy

    def _paint(self, region, coverage, color, metal):
        """Smíchá barvu (a kov) do výřezu podle pokrytí 0–1 (vyhlazené hrany)."""
        sl, _, _ = region
        a = np.clip(coverage, 0.0, 1.0)[..., None]
        self.rgb[sl] = self.rgb[sl] * (1 - a) + np.array(color, dtype=np.float32) * a
        if metal is not None:
            self.metal[sl] = self.metal[sl] * (1 - a[..., 0]) + metal * a[..., 0]

    def segment(self, a, b, width, color, metal=None):
        """Úsečka s kulatými konci."""
        r = width / 2
        region = self._region(min(a[0], b[0]) - r, min(a[1], b[1]) - r, max(a[0], b[0]) + r, max(a[1], b[1]) + r)
        if not region:
            return
        _, gx, gy = region
        dx, dy = b[0] - a[0], b[1] - a[1]
        length2 = dx * dx + dy * dy or 1e-12
        t = np.clip(((gx - a[0]) * dx + (gy - a[1]) * dy) / length2, 0, 1)
        d = np.hypot(gx - (a[0] + t * dx), gy - (a[1] + t * dy))
        self._paint(region, (r - d) * self.px + 0.5, color, metal)

    def polyline(self, points, width, color, metal=None):
        """Lomená čára."""
        for a, b in zip(points, points[1:]):
            self.segment(a, b, width, color, metal)

    def rect(self, cx, cy, w, h, color, metal=None, rot=0.0):
        """Vyplněný obdélník se středem cx, cy (natočení ve stupních)."""
        ext = math.hypot(w, h) / 2
        region = self._region(cx - ext, cy - ext, cx + ext, cy + ext)
        if not region:
            return
        _, gx, gy = region
        c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        lx = (gx - cx) * c + (gy - cy) * s
        ly = -(gx - cx) * s + (gy - cy) * c
        cov = np.minimum((w / 2 - np.abs(lx)) * self.px + 0.5, (h / 2 - np.abs(ly)) * self.px + 0.5)
        self._paint(region, cov, color, metal)

    def outline(self, cx, cy, w, h, width, color, rot=0.0):
        """Obrys obdélníku (potisk)."""
        c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        corners = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2), (-w / 2, -h / 2)]
        pts = [(cx + x * c - y * s, cy + x * s + y * c) for x, y in corners]
        self.polyline(pts, width, color)

    def disc(self, cx, cy, r, color, metal=None):
        """Vyplněný kruh."""
        region = self._region(cx - r, cy - r, cx + r, cy + r)
        if not region:
            return
        _, gx, gy = region
        self._paint(region, (r - np.hypot(gx - cx, gy - cy)) * self.px + 0.5, color, metal)

    def ring(self, cx, cy, r, width, color):
        """Kružnice (potisk)."""
        region = self._region(cx - r - width, cy - r - width, cx + r + width, cy + r + width)
        if not region:
            return
        _, gx, gy = region
        d = np.abs(np.hypot(gx - cx, gy - cy) - r)
        self._paint(region, (width / 2 - d) * self.px + 0.5, color, None)

    def label(self, x, y, chars, size=0.022):
        """Náznak textu potisku: krátké svislé a vodorovné čárky (při 64 px/dlaždici se text stejně nepřečte)."""
        # Semínko z polohy (hash() řetězců je v Pythonu náhodný pro každý proces – potisk by se měnil).
        rng = random.Random(int(round(x * 1000)) * 7919 + int(round(y * 1000)) * 104729 + chars)
        for i in range(chars):
            cx = x + i * size * 0.8
            for _ in range(2):
                if rng.random() < 0.5:
                    self.segment((cx, y - size / 2), (cx, y + size / 2), SILK_W * 0.8, SILK)
                else:
                    yy = y + rng.choice((-1, 0, 1)) * size / 2
                    self.segment((cx - size / 4, yy), (cx + size / 4, yy), SILK_W * 0.8, SILK)


def via(cv, x, y):
    """Prokov: cínový kroužek s otvorem."""
    cv.disc(x, y, 0.011, TIN, 1.0)
    cv.disc(x, y, 0.0045, HOLE, 0.0)


def fanout(cv, rng, x, y, dx, dy, max_len):
    """Cesta z plošky ven: rovně, ohyb 45° a dál rovně, na konci prokov."""
    l1 = rng.uniform(0.03, 0.09)
    turn = rng.choice((-1, 1))
    p1 = (x + dx * l1, y + dy * l1)
    l2 = rng.uniform(0.02, 0.07)
    diag = ((dx - turn * dy) / math.sqrt(2), (dy + turn * dx) / math.sqrt(2))
    p2 = (p1[0] + diag[0] * l2, p1[1] + diag[1] * l2)
    l3 = rng.uniform(0.04, max_len)
    p3 = (p2[0] + dx * l3, p2[1] + dy * l3)
    lim_x, lim_y = L.PCB_SIZE[0] / 2 - 0.04, L.PCB_SIZE[1] / 2 - 0.04
    p3 = (max(-lim_x, min(lim_x, p3[0])), max(-lim_y, min(lim_y, p3[1])))
    cv.polyline([(x, y), p1, p2, p3], TRACE_W, MASK_TRACE)
    via(cv, *p3)


def route(cv, a, b, width=TRACE_W):
    """Cesta z bodu a do b: vodorovně/svisle a jeden úsek pod 45° (jako z návrhového programu)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    if abs(dx) >= abs(dy):
        mid = (b[0] - math.copysign(abs(dy), dx), a[1])
    else:
        mid = (a[0], b[1] - math.copysign(abs(dx), dy))
    cv.polyline([a, mid, b], width, MASK_TRACE)


def draw(cv):
    """Nakreslí celou desku do plátna."""
    rng = random.Random(SEED)
    w, h = L.PCB_SIZE
    # Okraj desky a montážní otvory v rozích (pod distančními sloupky).
    cv.outline(0, 0, w - 0.03, h - 0.03, SILK_W, SILK)
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * L.STANDOFF_XY, sy * L.STANDOFF_XY
            cv.disc(x, y, 0.05, COPPER, 1.0)
            cv.disc(x, y, 0.03, HOLE, 0.0)

    # Procesor: rozvod cest ven z vývodů, plošky a potisk.
    out_dir = {"s": (0, -1), "n": (0, 1), "w": (-1, 0), "e": (1, 0)}
    for px, py, side in L.cpu_pins():
        if rng.random() < 0.75:
            fanout(cv, rng, px, py, *out_dir[side], 0.22)
    for px, py, side in L.cpu_pins():
        vertical = side in ("s", "n")
        cv.rect(px, py, 0.016 if vertical else 0.05, 0.05 if vertical else 0.016, TIN, 1.0)
    cx, cy = L.CPU_POS
    cv.outline(cx, cy, L.CPU_SIZE[0] + 0.12, L.CPU_SIZE[1] + 0.12, SILK_W, SILK)
    cv.disc(cx - L.CPU_SIZE[0] / 2 - 0.035, cy + L.CPU_SIZE[1] / 2 + 0.035, 0.012, SILK)
    cv.label(cx - L.CPU_SIZE[0] / 2 - 0.02, cy - L.CPU_SIZE[1] / 2 - 0.09, 2)

    # Čipy DIP.
    for i, (x, y, rot, length) in enumerate(L.DIPS):
        legs = L.dip_legs(x, y, rot, length)
        for lx, ly in legs:
            if rng.random() < 0.5:
                d = (lx - x, ly - y)
                n = math.hypot(*d) or 1
                fanout(cv, rng, lx, ly, round(d[0] / n), round(d[1] / n), 0.10)
        for lx, ly in legs:
            cv.disc(lx, ly, 0.017, TIN, 1.0)
        cv.outline(x, y, length + 0.04, 0.16, SILK_W, SILK, rot)
        c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        cv.ring(x - (length / 2 + 0.02) * c, y - (length / 2 + 0.02) * s, 0.018, SILK_W, SILK)
        cv.label(x - length / 2, y + 0.11 if rot == 0 else y, 2)

    # Hřebínky pinů: čtvercové plošky a obrys.
    for name, (x, y, cols, rows, rot) in L.HEADERS.items():
        for c_ in range(cols):
            for r_ in range(rows):
                px, py = L.header_pin(name, c_, r_)
                cv.rect(px, py, 0.03, 0.03, TIN, 1.0, rot)
        cv.outline(x, y, cols * L.PIN_PITCH + 0.02, rows * L.PIN_PITCH + 0.02, SILK_W, SILK, rot)

    # Svorkovnice: plošky pod šrouby a cesty k hřebínkům procesoru.
    for side in ("in", "out"):
        for color in ("red", "green"):
            x, y = L.terminal_block_pos(side, color)
            bw, bd, _ = L.TERMINAL_BLOCK
            for k in (-1, 1):
                cv.disc(x + k * bw / 4, y, 0.03, TIN, 1.0)
            cv.outline(x, y, bw + 0.03, bd + 0.03, SILK_W, SILK)
            cv.label(x - bw / 2, y + (0.11 if y > 0 else -0.11), 3)
    for color, col in (("red", 0), ("green", 4)):
        route(cv, L.terminal_block_pos("in", color), L.header_pin("cpu_s", col, 0), TRACE_W * 1.6)
        route(cv, L.header_pin("cpu_n", col, 0), L.terminal_block_pos("out", color), TRACE_W * 1.6)

    # Kondenzátory, rezistory, krystal, pojistka, LED: plošky a potisk.
    for x, y, r, _ in L.CAPS:
        for k in (-1, 1):
            cv.disc(x + k * r * 0.6, y, 0.012, TIN, 1.0)
        cv.ring(x, y, r + 0.012, SILK_W, SILK)
        cv.segment((x - r - 0.03, y + r), (x - r - 0.01, y + r), SILK_W, SILK)
        cv.segment((x - r - 0.02, y + r - 0.01), (x - r - 0.02, y + r + 0.01), SILK_W, SILK)
    for x, y, rot in L.RESISTORS:
        c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        for k in (-1, 1):
            cv.disc(x + k * 0.06 * c, y + k * 0.06 * s, 0.014, TIN, 1.0)
        cv.outline(x, y, 0.15, 0.045, SILK_W, SILK, rot)
    cv.outline(*L.CRYSTAL, 0.16, 0.08, SILK_W, SILK)
    cv.ring(*L.COIL, 0.085, SILK_W, SILK)
    fx, fy = L.FUSE
    cv.rect(fx - 0.065, fy, 0.04, 0.06, TIN, 1.0)
    cv.rect(fx + 0.065, fy, 0.04, 0.06, TIN, 1.0)
    cv.outline(fx, fy, 0.2, 0.085, SILK_W, SILK)
    lx, ly = L.LED_POS
    cv.ring(lx, ly, L.LED_R * 1.8, SILK_W, SILK)
    cv.label(lx - 0.03, ly - 0.1, 3)

    # Název desky u přední hrany.
    cv.label(-0.30, -0.73, 8, size=0.03)


def make_image(out_dir):
    """Vygeneruje texturu desky a uloží ji jako PNG; vrátí obrázek Blenderu (RGB sRGB, A = maska kovu)."""
    cv = Canvas()
    draw(cv)
    rgba = np.concatenate([cv.rgb, cv.metal[..., None]], axis=-1)[::-1]  # Blender ukládá řádky odspodu
    name = "PYNTR_pcb_texture"
    img = bpy.data.images.get(name)
    if img and (img.size[0] != cv.nx or img.size[1] != cv.ny):
        bpy.data.images.remove(img)
        img = None
    img = img or bpy.data.images.new(name, width=cv.nx, height=cv.ny, alpha=True)
    img.alpha_mode = "CHANNEL_PACKED"
    img.pixels.foreach_set(np.ascontiguousarray(rgba, dtype=np.float32).reshape(-1))
    Path(out_dir).mkdir(exist_ok=True)
    img.filepath_raw = str(Path(out_dir) / "pcb.png")
    img.file_format = "PNG"
    img.save()
    return img
