"""Procedurální model Pythonatoru: „bastlený“ řídicí počítač – na soklu natřená skříňka s větráním, nad ní na
distančních sloupcích deska plošných spojů (generovaná textura, pyntr_pcb) s procesorem a chladičem, čipy,
kondenzátory, rezistory, krystalem, cívkou, pojistkou, hřebínky pinů a propojovacími drátky s konektory Dupont. Vpředu vstupní svorkovnice, v zadních rozích výstupní, vzadu nakloněný LCD s „řádky kódu“
a malým logem Pythonu v rohu a vpravo vpředu stavová LED (blikátko, renderuje se zvlášť).

Rozměry a polohy jsou v pyntr_layout (sdílí je s texturou desky). +Y = sever, kamera hry se dívá od jihu.
"""

import math

import bpy
from mathutils import Vector

import pyntr_layout as L
import pyntr_logo
import pyntr_materials as M

DUPONT = (0.026, 0.026, 0.06)    # konektor Dupont nasazený na pin (š × h × v)
FERRULE_LEN = 0.035              # kovová dutinka drátu u svorkovnice
JUMPER_R = 0.011                 # poloměr propojovacího drátku
WIRE_R = 0.014                   # poloměr drátů ke svorkovnicím


# --- Pomocné funkce geometrie ---

def move_to(obj, collection):
    """Přesune objekt jen do dané kolekce (operátory ho zakládají do aktivní kolekce)."""
    if collection is None:
        return
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)


def box(name, size, location, material, bevel=0.0, collection=None, rot_z=0.0):
    """Kvádr daných rozměrů; `location` = střed podstavy (z = spodní hrana); volitelné zaoblení a natočení."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(location[0], location[1], location[2] + size[2] / 2))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    obj.rotation_euler[2] = math.radians(rot_z)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
    obj.data.materials.append(material)
    move_to(obj, collection)
    return obj


def cylinder(name, radius, depth, location, material, collection=None, vertices=20, rot=(0.0, 0.0, 0.0)):
    """Válec stojící na `location` (z = spodní hrana), případně natočený (rot ve stupních, kolem středu)."""
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=vertices,
                                        location=(location[0], location[1], location[2] + depth / 2),
                                        rotation=tuple(math.radians(a) for a in rot))
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(material)
    move_to(obj, collection)
    return obj


def curve_wire(name, start, start_dir, end, end_dir, reach, swing, radius, material, collection):
    """Drát ze `start` do `end` (xyz) jako Bézierova křivka: z obou konců vychází ve směru *_dir
    (u konektoru nahoru, u svorkovnice vodorovně) a `reach` určuje, jak daleko než se ohne; `swing` vybočí
    oblouk do strany (neuklizené bastlení)."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    curve.resolution_u = 20
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(1)
    a, b = Vector(start), Vector(end)
    d = b - a
    side = Vector((-d.y, d.x, 0.0)).normalized() * swing
    p0, p1 = spline.bezier_points
    p0.co, p1.co = a, b
    p0.handle_right = a + Vector(start_dir) * reach + side
    p0.handle_left = a - Vector(start_dir) * 0.01
    p1.handle_left = b + Vector(end_dir) * reach + side
    p1.handle_right = b - Vector(end_dir) * 0.01
    obj = bpy.data.objects.new(name, curve)
    obj.data.materials.append(material)
    collection.objects.link(obj)
    return obj


# --- Části modelu ---

def base(collection, mats):
    """Sokl, natřená skříňka s větráním a výstražnými pruhy, distanční sloupky a deska."""
    parts = [box("PYNTR_plinth", L.PLINTH, (0, 0, 0), mats["plinth"], bevel=0.015, collection=collection)]
    hw, hd, hh = L.HOUSING
    z0 = L.PLINTH[2]
    parts.append(box("PYNTR_housing", L.HOUSING, (0, 0, z0), mats["housing"], bevel=0.035, collection=collection))
    for i in range(5):
        parts.append(box(f"PYNTR_vent_s{i}", (0.07, 0.02, 0.11), (-0.45 + i * 0.12, -hd / 2 - 0.004, z0 + 0.05),
                         mats["vent"], collection=collection))
    for side in (-1, 1):
        for i in range(4):
            parts.append(box(f"PYNTR_vent_{side}{i}", (0.02, 0.16, 0.08), (side * (hw / 2 + 0.004), -0.45 + i * 0.3, z0 + 0.07),
                             mats["vent"], collection=collection))
        for k in range(3):
            parts.append(box(f"PYNTR_stripe_{side}{k}", (0.05, 0.012, 0.16),
                             (side * (0.62 + k * 0.08), -hd / 2 - 0.006, z0 + 0.03), mats["stripe"], collection=collection))
    top = z0 + hh
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * L.STANDOFF_XY, sy * L.STANDOFF_XY
            parts.append(cylinder(f"PYNTR_standoff_{sx}{sy}", 0.03, L.PCB_TOP - L.PCB_THICK - top, (x, y, top),
                                  mats["standoff"], collection, vertices=6))
            parts.append(cylinder(f"PYNTR_screw_{sx}{sy}", 0.028, 0.014, (x, y, L.PCB_TOP), mats["screw"], collection,
                                  vertices=12))
    parts.append(box("PYNTR_pcb", (*L.PCB_SIZE, L.PCB_THICK), (0, 0, L.PCB_TOP - L.PCB_THICK), mats["pcb"],
                     bevel=0.006, collection=collection))
    return parts


def cpu(collection, mats):
    """Procesor s vývody po obvodu a hliníkovým chladičem s žebry."""
    x, y = L.CPU_POS
    w, _, h = L.CPU_SIZE
    parts = [box("PYNTR_cpu", L.CPU_SIZE, (x, y, L.PCB_TOP), mats["chip"], bevel=0.006, collection=collection)]
    for i, (px, py, side) in enumerate(L.cpu_pins()):
        size = (0.012, 0.04, 0.006) if side in ("s", "n") else (0.04, 0.012, 0.006)
        parts.append(box(f"PYNTR_cpu_pin{i}", size, (px, py, L.PCB_TOP), mats["pin"], collection=collection))
    sink_w = w * 0.8
    base_z = L.PCB_TOP + h
    parts.append(box("PYNTR_heatsink_base", (sink_w, sink_w, 0.02), (x, y, base_z), mats["heatsink"], collection=collection))
    for i in range(L.FINS):
        fy = y - sink_w / 2 + (i + 0.5) * sink_w / L.FINS
        parts.append(box(f"PYNTR_fin{i}", (sink_w, 0.018, 0.09), (x, fy, base_z + 0.02), mats["heatsink"], bevel=0.004,
                         collection=collection))
    return parts


def dips(collection, mats):
    """Čipy v pouzdře DIP s vývody na delších stranách."""
    parts = []
    for i, (x, y, rot, length) in enumerate(L.DIPS):
        parts.append(box(f"PYNTR_dip{i}", (length, 0.11, 0.035), (x, y, L.PCB_TOP + 0.01), mats["chip"], bevel=0.004,
                         collection=collection, rot_z=rot))
        for k, (lx, ly) in enumerate(L.dip_legs(x, y, rot, length)):
            parts.append(box(f"PYNTR_dip{i}_leg{k}", (0.012, 0.025, 0.03), (lx, ly, L.PCB_TOP), mats["pin"],
                             collection=collection, rot_z=rot))
    return parts


def headers(collection, mats):
    """Hřebínky pinů (plastová lišta a zlacené piny)."""
    parts = []
    for name, (x, y, cols, rows, rot) in L.HEADERS.items():
        parts.append(box(f"PYNTR_header_{name}", (cols * L.PIN_PITCH, rows * L.PIN_PITCH, 0.03), (x, y, L.PCB_TOP),
                         mats["header"], collection=collection, rot_z=rot))
        for c in range(cols):
            for r in range(rows):
                px, py = L.header_pin(name, c, r)
                parts.append(box(f"PYNTR_hpin_{name}{c}{r}", (0.01, 0.01, 0.06), (px, py, L.PCB_TOP), mats["gold"],
                                 collection=collection))
    return parts


def small_parts(collection, mats):
    """Kondenzátory, rezistory, krystal, cívka a pojistka."""
    parts = []
    for i, (x, y, r, h) in enumerate(L.CAPS):
        parts.append(cylinder(f"PYNTR_cap{i}", r, h, (x, y, L.PCB_TOP), mats["cap_blue"], collection))
        parts.append(cylinder(f"PYNTR_cap{i}_top", r * 0.92, 0.006, (x, y, L.PCB_TOP + h), mats["cap_top"], collection))
    for i, (x, y, rot) in enumerate(L.RESISTORS):
        parts.append(box(f"PYNTR_res{i}", (0.09, 0.028, 0.028), (x, y, L.PCB_TOP + 0.004), mats["resistor"], bevel=0.01,
                         collection=collection, rot_z=rot))
    parts.append(box("PYNTR_crystal", (0.12, 0.05, 0.04), (*L.CRYSTAL, L.PCB_TOP), mats["crystal"], bevel=0.018,
                     collection=collection))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.05, minor_radius=0.022, location=(*L.COIL, L.PCB_TOP + 0.024),
                                     major_segments=24, minor_segments=8)
    coil = bpy.context.active_object
    coil.name = "PYNTR_coil"
    bpy.ops.object.shade_smooth()
    coil.data.materials.append(mats["copper_coil"])
    move_to(coil, collection)
    parts.append(coil)
    fx, fy = L.FUSE
    parts.append(cylinder("PYNTR_fuse", 0.018, 0.12, (fx, fy, L.PCB_TOP + 0.022 - 0.06), mats["fuse_glass"], collection,
                          rot=(0, 90, 0)))
    for k in (-1, 1):
        parts.append(box(f"PYNTR_fuse_clip{k}", (0.025, 0.05, 0.045), (fx + k * 0.065, fy, L.PCB_TOP), mats["pin"],
                         collection=collection))
    return parts


def terminals(collection, mats):
    """Svorkovnice pro červený (vlevo) a zelený (vpravo) drát: dva šroubky, otvory pro dráty a barevné značení."""
    parts = []
    bw, bd, bh = L.TERMINAL_BLOCK
    for side in ("in", "out"):
        for color in ("red", "green"):
            x, y = L.terminal_block_pos(side, color)
            prefix = f"PYNTR_{side}_{color}"
            parts.append(box(prefix + "_block", L.TERMINAL_BLOCK, (x, y, L.PCB_TOP), mats["terminal_block"], bevel=0.01,
                             collection=collection))
            for hole in (0, 1):
                (hx, hy), (_, dy) = L.terminal_hole(side, color, hole)
                parts.append(cylinder(f"{prefix}_screw{hole}", 0.032, 0.015, (hx, y, L.PCB_TOP + bh), mats["brass"],
                                      collection, vertices=12))
                parts.append(box(f"{prefix}_hole{hole}", (0.045, 0.012, 0.04), (hx, hy + dy * 0.003, L.PCB_TOP + 0.025),
                                 mats["vent"], collection=collection))
            # Barevné značení na vnější stěně (k okraji desky).
            outer = math.copysign(bd / 2, y)
            parts.append(box(prefix + "_mark", (bw * 0.9, 0.025, 0.012), (x, y + outer, L.PCB_TOP + bh - 0.03),
                             mats["wire_" + color], collection=collection))
    return parts


def anchor(end):
    """Konec drátku podle pyntr_layout: (bod xyz, směr, kterým drát z konce vychází)."""
    if end[0] == "pin":
        x, y = L.header_pin(end[1], end[2], end[3])
        return Vector((x, y, L.PCB_TOP + 0.005 + DUPONT[2])), Vector((0, 0, 1))
    (x, y), (dx, dy) = L.terminal_hole(end[1], end[2], end[3])
    tip = Vector((x + dx * FERRULE_LEN, y + dy * FERRULE_LEN, L.PCB_TOP + L.TERMINAL_HOLE_Z))
    return tip, Vector((dx, dy, 0))


def end_piece(name, end, collection, mats):
    """Zakončení drátku: konektor Dupont nasazený na pin, nebo kovová dutinka zasunutá do svorkovnice."""
    if end[0] == "pin":
        x, y = L.header_pin(end[1], end[2], end[3])
        return box(name, DUPONT, (x, y, L.PCB_TOP + 0.005), mats["dupont"], bevel=0.003, collection=collection)
    (x, y), (dx, dy) = L.terminal_hole(end[1], end[2], end[3])
    length = FERRULE_LEN + 0.01
    center = (x + dx * (FERRULE_LEN / 2 - 0.005), y + dy * (FERRULE_LEN / 2 - 0.005), L.PCB_TOP + L.TERMINAL_HOLE_Z - length / 2)
    return cylinder(name, WIRE_R * 0.85, length, center, mats["ferrule"], collection, vertices=10,
                    rot=(90, 0, 0) if dy else (0, 90, 0))


def jumpers(collection, mats):
    """Propojovací drátky s konektory a dráty do svorkovnic."""
    parts = []
    for i, (mat, a_end, b_end, height, swing) in enumerate(L.JUMPERS):
        a, a_dir = anchor(a_end)
        b, b_dir = anchor(b_end)
        radius = WIRE_R if mat.startswith("wire_") else JUMPER_R
        parts.append(curve_wire(f"PYNTR_jumper{i}", a, a_dir, b, b_dir, height, swing, radius, mats[mat], collection))
        parts.append(end_piece(f"PYNTR_jumper{i}_a", a_end, collection, mats))
        parts.append(end_piece(f"PYNTR_jumper{i}_b", b_end, collection, mats))
    return parts


def lcd(collection, mats):
    """Nakloněný LCD na nožkách vzadu: rámeček, obrazovka a svítící „řádky kódu“ s odsazením jako v Pythonu."""
    w, h = L.LCD_SIZE
    panel = bpy.data.objects.new("PYNTR_lcd", None)
    collection.objects.link(panel)
    panel.location = (L.LCD_POS[0], L.LCD_POS[1], L.PCB_TOP + 0.04)
    panel.rotation_euler = (-math.radians(L.LCD_TILT), 0, 0)  # záporný úhel = horní hrana dozadu (+Y)
    items = [box("PYNTR_lcd_bezel", (w, 0.05, h), (0, 0, 0), mats["lcd_bezel"], bevel=0.012, collection=collection),
             box("PYNTR_lcd_screen", (w - 0.08, 0.01, h - 0.08), (0, -0.027, 0.04), mats["lcd_screen"],
                 collection=collection)]
    line_h, gap = 0.026, 0.018
    left = -(w - 0.08) / 2 + 0.03
    for i, (indent, length) in enumerate(L.LCD_LINES):
        z = h - 0.07 - i * (line_h + gap) - line_h
        lw = (w - 0.16) * length
        items.append(box(f"PYNTR_lcd_line{i}", (lw, 0.006, line_h), (left + indent * 0.05 + lw / 2, -0.034, z),
                         mats["lcd_text"], collection=collection))
    items.append(logo(w, h, collection))
    for obj in items:
        obj.parent = panel
    legs = [box(f"PYNTR_lcd_leg{side}", (0.03, 0.03, 0.06), (L.LCD_POS[0] + side * (w / 2 - 0.08), L.LCD_POS[1], L.PCB_TOP),
                mats["frame"], collection=collection) for side in (-1, 1)]
    return panel, items + legs


def logo(w, h, collection):
    """Stylizované logo Pythonu v pravém horním rohu obrazovky LCD (souřadnice panelu)."""
    size = L.LOGO_SIZE
    x = (w - 0.08) / 2 - 0.015 - size / 2
    z = h - 0.055 - size / 2
    bpy.ops.mesh.primitive_plane_add(size=size, location=(x, -0.0335, z), rotation=(math.radians(90), 0, 0))
    obj = bpy.context.active_object
    obj.name = "PYNTR_lcd_logo"
    obj.data.materials.append(pyntr_logo.material())
    move_to(obj, collection)
    return obj


def led(collection, mats):
    """Stavová LED v objímce (blikátko). Vrací (díly objímky, kopule LED) – kopule se renderuje i zvlášť."""
    x, y = L.LED_POS
    holder = cylinder("PYNTR_led_holder", L.LED_R * 1.5, 0.025, (x, y, L.PCB_TOP), mats["chip"], collection)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=L.LED_R, segments=16, ring_count=8, location=(x, y, L.PCB_TOP + 0.025))
    dome = bpy.context.active_object
    dome.name = "PYNTR_led"
    bpy.ops.object.shade_smooth()
    dome.data.materials.append(mats["led_off"])
    move_to(dome, collection)
    return [holder], dome


def build(collection, work_dir):
    """Postaví model do kolekce; vrátí kořenový prázdný objekt (natáčení), seznam dílů a kopuli LED."""
    mats = M.build_all(work_dir)
    parts = base(collection, mats)
    parts += cpu(collection, mats)
    parts += dips(collection, mats)
    parts += headers(collection, mats)
    parts += small_parts(collection, mats)
    parts += terminals(collection, mats)
    parts += jumpers(collection, mats)
    panel, lcd_parts = lcd(collection, mats)
    holder, dome = led(collection, mats)
    parts += holder

    root = bpy.data.objects.new("PYNTR_root", None)
    collection.objects.link(root)
    for p in parts + lcd_parts + [dome, panel]:
        if p.parent is None:
            p.parent = root
    return root, parts + lcd_parts, dome
