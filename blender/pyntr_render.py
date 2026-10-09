"""Render spritů pro Factorio: vrstvy (budova / stín), převzorkování, skládání a projekce bodů do souřadnic hry.

Převzato ze Storage Optimizeru (so_render.py) a doplněno o promítání bodů (dráty, LED) kamerou hry.
"""

import math

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

SAMPLES = 96
SUPERSAMPLE = 2                  # render ve 2× rozlišení a zmenšení → ostřejší detaily na 64 px/dlaždici


def setup_render(scene, px):
    """Cycles, průhledné pozadí, standardní převod barev; render v px × SUPERSAMPLE."""
    scene.render.engine = "CYCLES"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = px * SUPERSAMPLE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.get("PYNTR_RenderWorld") or bpy.data.worlds.new("PYNTR_RenderWorld")
    world.use_nodes = True
    nodes = world.node_tree.nodes
    background = next((n for n in nodes if n.type == "BACKGROUND"), None) or nodes.new("ShaderNodeBackground")
    output = next((n for n in nodes if n.type == "OUTPUT_WORLD"), None) or nodes.new("ShaderNodeOutputWorld")
    if not output.inputs["Surface"].is_linked:
        world.node_tree.links.new(background.outputs["Background"], output.inputs["Surface"])
    background.inputs["Color"].default_value = (0.42, 0.42, 0.45, 1.0)
    background.inputs["Strength"].default_value = 0.4
    scene.world = world


def add_shadow_catcher(collection):
    """Podložka zachytávající stín."""
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "PYNTR_shadow_catcher"
    ground.is_shadow_catcher = True
    for c in list(ground.users_collection):
        c.objects.unlink(ground)
    collection.objects.link(ground)
    return ground


def render_pass(scene, path, mode, parts, ground):
    """Vyrenderuje vrstvu: 'base' (budova), 'shadow' (jen stín na zemi)."""
    for obj in parts:
        obj.hide_render = False
        obj.visible_camera = mode != "shadow"
    ground.hide_render = mode != "shadow"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=scene.name)


def load_pixels(path):
    """Načte PNG jako numpy pole (výška, šířka, 4) s řádky shora dolů (hodnoty sRGB)."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    pixels = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]
    bpy.data.images.remove(img)
    return pixels


def save_pixels(pixels, path):
    """Uloží numpy pole (výška, šířka, 4; řádky shora dolů; sRGB) jako PNG."""
    h, w = pixels.shape[:2]
    img = bpy.data.images.new("PYNTR_tmp", width=w, height=h, alpha=True)
    img.pixels[:] = np.clip(pixels, 0.0, 1.0)[::-1].reshape(-1)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def srgb_to_linear(c):
    """Převod sRGB (0–1) na lineární hodnoty."""
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    """Převod lineárních hodnot zpět na sRGB (0–1)."""
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def downsample(pixels, factor=SUPERSAMPLE):
    """Zmenší obraz průměrem bloků factor×factor v lineárním prostoru s premultiplikovanou alfou."""
    if factor == 1:
        return pixels
    h, w = pixels.shape[:2]
    alpha = pixels[..., 3:4]
    pre = np.concatenate([srgb_to_linear(pixels[..., :3]) * alpha, alpha], axis=-1)
    pre = pre.reshape(h // factor, factor, w // factor, factor, 4).mean(axis=(1, 3))
    a = pre[..., 3:4]
    rgb = np.where(a > 1e-6, pre[..., :3] / np.maximum(a, 1e-6), 0.0)
    return np.concatenate([linear_to_srgb(rgb), a], axis=-1)


def shadow_only(pixels):
    """Ze stínového renderu ponechá jen alfu (černý stín, jak ho Factorio kreslí přes draw_as_shadow)."""
    out = np.zeros_like(pixels)
    out[..., 3] = pixels[..., 3]
    return out


def over(dst, src):
    """Složí vrstvu src přes dst (sRGB, nepremultiplikovaná alfa)."""
    a = src[..., 3:4]
    out = dst.copy()
    out[..., :3] = src[..., :3] * a + dst[..., :3] * (1.0 - a)
    out[..., 3:4] = a + dst[..., 3:4] * (1.0 - a)
    return out


def tint(layer, color):
    """Obarví vrstvu násobením barvou (jako tint ve Factoriu)."""
    out = layer.copy()
    out[..., :3] = linear_to_srgb(srgb_to_linear(layer[..., :3]) * srgb_to_linear(np.array(color)))
    return out


def to_game(scene, camera, frame_tiles, point):
    """Bod scény (xyz ve světě) → posun ve hře v dlaždicích od středu entity (x doprava, y dolů)."""
    co = world_to_camera_view(scene, camera, Vector(point))
    return ((co.x - 0.5) * frame_tiles, (0.5 - co.y) * frame_tiles)


def shadow_point(point, sun):
    """Průsečík paprsku slunce bodem `point` se zemí (z = 0) – kam dopadne stín bodu."""
    direction = sun.matrix_world.to_3x3() @ Vector((0, 0, -1))
    p = Vector(point)
    return p + direction * (p.z / -direction.z)


def led_glow(px=32):
    """Sprite záře LED: bílé jádro s měkkým halem (barví ho hra tintem), RGBA."""
    c = (np.arange(px) + 0.5) - px / 2
    gx, gy = np.meshgrid(c, c)
    r = np.hypot(gx, gy) / (px / 2)
    core = np.clip((0.22 - r) / 0.06, 0, 1)
    halo = np.exp(-(r / 0.45) ** 2) * 0.75
    a = np.clip(np.maximum(core, halo), 0, 1)
    rgb = np.ones((px, px, 3)) * (0.75 + 0.25 * core[..., None])
    return np.concatenate([rgb, a[..., None]], axis=-1).astype(np.float32)

