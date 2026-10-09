"""Stylizované logo Pythonu pro roh LCD: dva propletení „hadi“ (modrý nahoře vlevo, žlutý dole vpravo,
otočený o 180°) s očky. Vlastní zjednodušená kresba v barvách Pythonu, ne kopie oficiálního loga
(ochranná známka PSF – před publikací ověřit pravidla užití).

Kreslí se v numpy do obrázku RGBA (průhledné pozadí) a na LCD svítí jako součást displeje.
"""

import bpy
import numpy as np

RESOLUTION = 256
BLUE = (0.216, 0.463, 0.671)     # #3776AB
YELLOW = (1.0, 0.831, 0.231)     # #FFD43B
EYE = (0.95, 0.95, 0.95)
GLOW = 2.5                       # síla svitu na displeji

# Tvar jednoho hada v souřadnicích −1…1 (y nahoru): zaoblené obdélníky (x0, y0, x1, y1, poloměr)
# – hlava s horním pásem a levý sloupec, ze kterého vede ocas. Druhý had je otočený o 180°.
SNAKE = [(-0.78, 0.22, 0.18, 0.86, 0.2), (-0.78, -0.42, -0.22, 0.86, 0.2), (-0.78, -0.42, 0.06, 0.06, 0.16)]
EYE_POS = (-0.48, 0.58, 0.085)   # oko modrého hada (x, y, poloměr)


def _rounded_rect(gx, gy, x0, y0, x1, y1, r):
    """Pokrytí 0–1 zaobleného obdélníku (vyhlazené hrany)."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = np.abs(gx - cx) - hx, np.abs(gy - cy) - hy
    d = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
    return np.clip(0.5 - d * RESOLUTION / 2, 0, 1)


def _snake(gx, gy):
    """Pokrytí jednoho hada (sjednocení obdélníků)."""
    cov = np.zeros_like(gx)
    for rect in SNAKE:
        cov = np.maximum(cov, _rounded_rect(gx, gy, *rect))
    return cov


def make_image():
    """Vykreslí logo do obrázku Blenderu PYNTR_logo (RGBA, průhledné pozadí)."""
    coords = (np.arange(RESOLUTION) + 0.5) / RESOLUTION * 2 - 1
    gx, gy = np.meshgrid(coords, coords[::-1])
    rgba = np.zeros((RESOLUTION, RESOLUTION, 4), dtype=np.float32)
    for color, sign in ((BLUE, 1), (YELLOW, -1)):
        cov = _snake(gx * sign, gy * sign)
        ex, ey, er = EYE_POS
        eye = np.clip(0.5 - (np.hypot(gx * sign - ex, gy * sign - ey) - er) * RESOLUTION / 2, 0, 1) * cov
        col = np.array(color) * (1 - eye[..., None]) + np.array(EYE) * eye[..., None]
        rgba[..., :3] = rgba[..., :3] * (1 - cov[..., None]) + col * cov[..., None]
        rgba[..., 3] = np.maximum(rgba[..., 3], cov)
    name = "PYNTR_logo"
    img = bpy.data.images.get(name) or bpy.data.images.new(name, width=RESOLUTION, height=RESOLUTION, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).reshape(-1))
    img.pack()
    return img


def material():
    """Svítící materiál loga s průhledným pozadím (Cycles)."""
    mat = bpy.data.materials.get("PYNTR_logo") or bpy.data.materials.new("PYNTR_logo")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = make_image()
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Emission Strength"].default_value = GLOW
    bsdf.inputs["Roughness"].default_value = 0.2
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat
