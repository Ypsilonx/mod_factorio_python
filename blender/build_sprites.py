"""Model Pythonatoru a render spritů pro Factorio – vstupní skript.

Spuštění přes Blender MCP (běžící Blender):
    g = {"__file__": r"<repo>/blender/build_sprites.py", "__name__": "__main__", "PYNTR_STAGE": "model"}
    exec(compile(open(g["__file__"], encoding="utf-8").read(), g["__file__"], "exec"), g)
nebo headless: blender -b --factory-startup --python blender/build_sprites.py

PYNTR_STAGE: "model" = jen postaví scénu a nastaví pohled kamery hry,
             "preview" = navíc náhledové rendery (Cycles, písek pod modelem) z kamery hry a ve 3D do
                         blender/renders/preview-{game,3d}.png – pro připomínky,
             "render" = navíc vyrenderuje sprity do modu (Pythonator/graphics, thumbnail.png) a zapíše
                        body drátů a polohy LED do Pythonator/prototypes/graphics_data.lua.

Projekce jako ve hře: ortografická kamera pod 45° a model natažený v ose Y o √2 (prázdný objekt PYNTR_stretch),
aby dlaždice na zemi vyšla čtvercová. Šikmý 3D náhled se renderuje bez natažení.
Scéna "Pythonator" a kolekce PYNTR / PYNTR_Ref patří skriptu – při spuštění se znovu vytvoří.
"""

import math
import sys
import tomllib
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).parent
# Blender drží importované moduly v paměti – vlastní moduly vyhodit, ať běží aktuální verze.
for _name in list(sys.modules):
    _file = getattr(sys.modules[_name], "__file__", None)
    if _file and Path(_file).parent == HERE:
        del sys.modules[_name]
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import numpy as np  # noqa: E402

import pyntr_layout as L  # noqa: E402
import pyntr_model  # noqa: E402
import pyntr_render as R  # noqa: E402

SCENE_NAME = "Pythonator"
RENDERS = HERE / "renders"
PREVIEW_PX = 576                 # rozlišení náhledů (3 dlaždice → 192 px na dlaždici)
PREVIEW_SAMPLES = 48             # vzorky Cycles pro náhledy (sprity mají víc)
PREVIEW_3D_CAMERA = (3.2, -3.6, 2.6)  # poloha šikmé kamery náhledu
CONFIG = tomllib.loads((HERE / "camera.toml").read_text(encoding="utf-8"))
MOD = HERE.parent / "Pythonator"
STRETCH = math.sqrt(2.0)         # natažení v ose Y – čtvercové dlaždice jako ve hře
# Natočení modelu pro směry entity (pořadí Factoria N, E, S, W): výstup (sever modelu) míří ve směru entity.
DIRECTIONS = [("north", 0.0), ("east", -90.0), ("south", 180.0), ("west", 90.0)]
ICON_PX, TECH_PX, THUMB_PX = 64, 256, 144
ICON_ORTHO = 2.5                 # záběr ikon v dlaždicích (celá budova včetně LCD)
ICON_SHIFT = 0.2                 # posun záběru ikon nahoru v dlaždicích (LCD převyšuje budovu)


def reset_scene():
    """Samostatná scéna Pythonator s prázdnými kolekcemi PYNTR (model) a PYNTR_Ref (reference, nerenderuje se)."""
    scene = bpy.data.scenes.get(SCENE_NAME) or bpy.data.scenes.new(SCENE_NAME)
    if not bpy.app.background:
        bpy.context.window.scene = scene
    for name in ("PYNTR", "PYNTR_Ref"):
        coll = bpy.data.collections.get(name)
        if coll:
            for obj in list(coll.objects):
                bpy.data.objects.remove(obj, do_unlink=True)
        else:
            coll = bpy.data.collections.new(name)
        if coll.name not in scene.collection.children:
            scene.collection.children.link(coll)
    for obj in list(scene.collection.objects):
        if obj.name.startswith("PYNTR_"):
            bpy.data.objects.remove(obj, do_unlink=True)
    ref = bpy.data.collections["PYNTR_Ref"]
    ref.hide_render = True
    return scene, bpy.data.collections["PYNTR"], ref


def add_references(ref):
    """Mřížka dlaždic 4×4 (obrys 2×2 budovy) a obrys vanilla aritmetického kombinátoru (1×2) vedle pro měřítko."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=4, y_subdivisions=4, size=4.0, location=(0, 0, 0.001))
    grid = bpy.context.active_object
    grid.name = "PYNTR_ref_tiles"
    grid.display_type = "WIRE"
    pyntr_model.move_to(grid, ref)
    # Aritmetický kombinátor: collision 0,7 × 1,3 m, tělo zhruba 0,7 × 1,1 × 0,45 m.
    combinator = pyntr_model.box("PYNTR_ref_arithmetic", (0.7, 1.1, 0.45), (1.75, 0, 0), bpy.data.materials.new("PYNTR_ref"),
                                 collection=ref)
    combinator.display_type = "WIRE"


def setup_camera_and_lights(scene):
    """Ortografická kamera pod 45° a světla podle camera.toml."""
    cam_cfg = CONFIG["camera"]
    cam_data = bpy.data.cameras.get("PYNTR_Camera") or bpy.data.cameras.new("PYNTR_Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = cam_cfg["frame_tiles"]
    camera = bpy.data.objects.new("PYNTR_Camera", cam_data)
    elev = math.radians(cam_cfg["elevation_deg"])
    camera.location = (0.0, -cam_cfg["distance"] * math.cos(elev), cam_cfg["distance"] * math.sin(elev))
    camera.rotation_euler = (math.pi / 2 - elev, 0.0, 0.0)
    scene.collection.objects.link(camera)
    scene.camera = camera
    for key in ("sun", "fill"):
        cfg = CONFIG[key]
        data = bpy.data.lights.get("PYNTR_" + key) or bpy.data.lights.new("PYNTR_" + key, "SUN")
        data.energy = cfg["energy"]
        data.color = cfg["color"]
        if key == "sun":
            data.angle = math.radians(cfg["angle_deg"])
        else:
            data.use_shadow = False
        light = bpy.data.objects.new("PYNTR_" + key, data)
        light.rotation_euler = [math.radians(a) for a in cfg["rotation_deg"]]
        scene.collection.objects.link(light)
    px = cam_cfg["frame_tiles"] * cam_cfg["px_per_tile"]
    scene.render.resolution_x = scene.render.resolution_y = int(px)
    return camera


def show_game_view():
    """Viewport: pohled kamery hry, náhled materiálů (pro screenshot k připomínkám)."""
    for area in bpy.context.window.screen.areas:
        if area.type == "VIEW_3D":
            space = area.spaces.active
            space.region_3d.view_perspective = "CAMERA"
            space.shading.type = "MATERIAL"
            space.overlay.show_overlays = True


def preview_world(scene):
    """Pozadí a písek pod modelem jen pro náhled (sprity se renderují s průhledným pozadím)."""
    world = bpy.data.worlds.get("PYNTR_World") or bpy.data.worlds.new("PYNTR_World")
    world.use_nodes = True
    nodes = world.node_tree.nodes
    bg = next((n for n in nodes if n.type == "BACKGROUND"), None) or nodes.new("ShaderNodeBackground")
    out = next((n for n in nodes if n.type == "OUTPUT_WORLD"), None) or nodes.new("ShaderNodeOutputWorld")
    if not out.inputs["Surface"].is_linked:
        world.node_tree.links.new(bg.outputs["Background"], out.inputs["Surface"])
    bg.inputs["Color"].default_value = (0.33, 0.27, 0.18, 1)
    bg.inputs["Strength"].default_value = 0.5
    scene.world = world
    scene.view_settings.view_transform = "Standard"
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "PYNTR_preview_ground"
    sand = bpy.data.materials.get("PYNTR_preview_sand") or bpy.data.materials.new("PYNTR_preview_sand")
    sand.use_nodes = True
    next(n for n in sand.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.11, 0.075, 0.04, 1)
    ground.data.materials.append(sand)
    return ground


def render_previews(scene, ref):
    """Náhledy pro připomínky: z kamery hry (s natažením) a ze šikmé 3D kamery (bez natažení)."""
    RENDERS.mkdir(exist_ok=True)
    ground = preview_world(scene)
    pyntr_model.move_to(ground, ref)
    ref.hide_render = False
    for obj in ref.objects:
        obj.hide_render = obj is not ground
    # Cycles: patina používá uzly AO a Bevel, které EEVEE neumí.
    scene.render.engine = "CYCLES"
    scene.cycles.samples = PREVIEW_SAMPLES
    scene.cycles.use_denoising = True
    scene.render.film_transparent = False
    scene.render.resolution_x = scene.render.resolution_y = PREVIEW_PX
    game_cam = scene.camera
    stretch = bpy.data.objects["PYNTR_stretch"]
    stretch.scale = (1.0, STRETCH, 1.0)
    scene.render.filepath = str(RENDERS / "preview-game.png")
    bpy.ops.render.render(write_still=True, scene=scene.name)
    stretch.scale = (1.0, 1.0, 1.0)
    cam = bpy.data.objects.new("PYNTR_preview_cam", bpy.data.cameras.new("PYNTR_preview_cam"))
    ref.objects.link(cam)
    cam.location = PREVIEW_3D_CAMERA
    target = -Vector(PREVIEW_3D_CAMERA) + Vector((0, 0, 0.3))
    cam.rotation_euler = target.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = str(RENDERS / "preview-3d.png")
    bpy.ops.render.render(write_still=True, scene=scene.name)
    scene.camera = game_cam


def layer(scene, name, mode, parts, ground):
    """Vyrenderuje vrstvu do pracovní složky a vrátí ji zmenšenou na cílové rozlišení."""
    path = str(RENDERS / (name + ".png"))
    R.render_pass(scene, path, mode, parts, ground)
    pixels = R.downsample(R.load_pixels(path))
    return R.shadow_only(pixels) if mode == "shadow" else pixels


def game_points(scene, camera, root, sun, frame_tiles):
    """Body drátů (vstup, výstup) a poloha LED pro aktuální natočení modelu v souřadnicích hry."""
    bpy.context.view_layer.update()
    m = root.matrix_world
    top = L.PCB_TOP + L.TERMINAL_BLOCK[2] + 0.015

    def wire_point(side):
        out = {"wire": {}, "shadow": {}}
        for color in ("red", "green"):
            x, y = L.terminal_block_pos(side, color)
            world = m @ Vector((x, y, top))
            out["wire"][color] = R.to_game(scene, camera, frame_tiles, world)
            out["shadow"][color] = R.to_game(scene, camera, frame_tiles, R.shadow_point(world, sun))
        return out

    led = m @ Vector((L.LED_POS[0], L.LED_POS[1], L.PCB_TOP + 0.03))
    return wire_point("in"), wire_point("out"), R.to_game(scene, camera, frame_tiles, led)


def lua_point(p):
    """Bod jako Lua tabulka {x, y} (4 desetinná místa)."""
    return "{ %.4f, %.4f }" % tuple(p)


def write_graphics_data(frame_px, frame_tiles, points):
    """Zapíše body drátů a LED pro všechny směry do Pythonator/prototypes/graphics_data.lua."""
    def conn(c):
        return ("{ wire = { red = %s, green = %s }, shadow = { red = %s, green = %s } }"
                % (lua_point(c["wire"]["red"]), lua_point(c["wire"]["green"]),
                   lua_point(c["shadow"]["red"]), lua_point(c["shadow"]["green"])))
    lines = ["-- Generováno blender/build_sprites.py (fáze render) – neupravovat ručně.",
             "-- Body drátů a poloha stavové LED pro směry N, E, S, W v dlaždicích od středu entity.",
             "return {",
             f"  frame_px = {frame_px},",
             f"  frame_tiles = {frame_tiles},",
             "  input = {"]
    lines += [f"    {conn(p[1])}," for p in points] + ["  },", "  output = {"]
    lines += [f"    {conn(p[2])}," for p in points] + ["  },", "  led = {"]
    lines += [f"    {lua_point(p[3])}," for p in points] + ["  },", "}", ""]
    (MOD / "prototypes" / "graphics_data.lua").write_text("\n".join(lines), encoding="utf-8")


def render_sprites(scene, root, parts, coll):
    """Sprity budovy (4 směry × budova + stín), LED, ikony, thumbnail a data bodů pro prototyp."""
    RENDERS.mkdir(exist_ok=True)
    cfg = CONFIG["camera"]
    frame_tiles, px_per_tile = cfg["frame_tiles"], cfg["px_per_tile"]
    frame_px = int(frame_tiles * px_per_tile)
    camera, sun = scene.camera, bpy.data.objects["PYNTR_sun"]
    ground = R.add_shadow_catcher(coll)
    stretch = bpy.data.objects["PYNTR_stretch"]
    stretch.scale = (1.0, STRETCH, 1.0)
    for obj in bpy.data.collections["PYNTR_Ref"].objects:
        obj.hide_render = True

    R.setup_render(scene, frame_px)
    camera.data.ortho_scale = frame_tiles
    sheets, points = {"base": [], "shadow": []}, []
    for direction, angle in DIRECTIONS:
        root.rotation_euler[2] = math.radians(angle)
        for mode in sheets:
            sheets[mode].append(layer(scene, f"entity-{direction}-{mode}", mode, parts, ground))
        points.append((direction, *game_points(scene, camera, root, sun, frame_tiles)))
    entity_dir = MOD / "graphics" / "entity"
    entity_dir.mkdir(parents=True, exist_ok=True)
    for mode, frames in sheets.items():
        name = "pythonator.png" if mode == "base" else "pythonator-shadow.png"
        R.save_pixels(np.concatenate(frames, axis=1), str(entity_dir / name))
    glow = R.led_glow()
    R.save_pixels(np.concatenate([np.zeros_like(glow), glow], axis=1), str(entity_dir / "pythonator-led.png"))
    write_graphics_data(frame_px, frame_tiles, points)

    # Kontrolní list jako ve hře: 4 směry na písku se stínem (jen náhled, do modu nejde).
    rows = []
    for base, shadow in zip(sheets["base"], sheets["shadow"]):
        sand = np.zeros_like(base)
        sand[..., :3] = (0.33, 0.27, 0.18)
        sand[..., 3] = 1.0
        shade = shadow.copy()
        shade[..., 3] *= 0.5
        rows.append(R.over(R.over(sand, shade), base))
    R.save_pixels(np.concatenate(rows, axis=1), str(RENDERS / "sheet.png"))

    # Ikony a thumbnail (směr sever, těsnější záběr).
    root.rotation_euler[2] = 0.0
    camera.data.ortho_scale = ICON_ORTHO
    camera.data.shift_y = ICON_SHIFT / ICON_ORTHO
    icons = MOD / "graphics" / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    for px, path in ((ICON_PX, icons / "pythonator.png"), (TECH_PX, MOD / "graphics" / "technology" / "pythonator.png")):
        path.parent.mkdir(parents=True, exist_ok=True)
        R.setup_render(scene, px)
        R.save_pixels(layer(scene, f"icon-{px}", "base", parts, ground), str(path))
    R.setup_render(scene, THUMB_PX)
    base = layer(scene, "thumb-base", "base", parts, ground)
    shadow = layer(scene, "thumb-shadow", "shadow", parts, ground)
    bg = np.zeros_like(base)
    bg[..., :3] = (0.11, 0.1, 0.09)
    bg[..., 3] = 1.0
    shadow[..., 3] *= 0.6
    R.save_pixels(R.over(R.over(bg, shadow), base), str(MOD / "thumbnail.png"))

    camera.data.ortho_scale = frame_tiles
    camera.data.shift_y = 0.0
    stretch.scale = (1.0, 1.0, 1.0)
    bpy.data.objects.remove(ground, do_unlink=True)
    return {"frame_px": frame_px, "led": [list(p[3]) for p in points]}


def main(stage):
    """Postaví scénu; ve stage "preview" udělá náhledy, ve "render" vyrenderuje sprity."""
    scene, coll, ref = reset_scene()
    root, parts, led = pyntr_model.build(coll, str(RENDERS))
    stretch = bpy.data.objects.new("PYNTR_stretch", None)
    coll.objects.link(stretch)
    root.parent = stretch
    add_references(ref)
    setup_camera_and_lights(scene)
    info = {}
    if stage == "preview":
        render_previews(scene, ref)
    if stage == "render":
        info = render_sprites(scene, root, parts + [led], coll)
    if not bpy.app.background:
        show_game_view()
    return {"parts": len(parts), "stage": stage, **info}


result = main(globals().get("PYNTR_STAGE", "render"))
