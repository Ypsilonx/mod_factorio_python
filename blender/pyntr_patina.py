"""Procedurální materiály s patinou (převzato ze Storage Optimizeru a doplněno o elektroniku): rez v koutech,
odřené hrany, škrábance, stékající šmouhy, špína u země, oprýskaná barva, zaprášený plast a připálená deska.

Všechny materiály jsou jen pro Cycles (uzly Ambient Occlusion a Bevel). Souřadnice textur jsou v prostoru
objektu, takže se textura otáčí spolu s modelem a všechny 4 směry vypadají konzistentně.
"""

import bpy

# Barvy patiny (lineární RGB) – laditelné hodnoty vzhledu.
RUST = (0.3, 0.085, 0.018)
RUST_DARK = (0.06, 0.022, 0.008)
BARE_METAL = (0.55, 0.52, 0.48)
GRIME = (0.018, 0.016, 0.013)


def _socket(node, name, kind):
    """Najde vstup uzlu podle jména a typu (ShaderNodeMix má víc vstupů stejného jména)."""
    return next(s for s in node.inputs if s.name == name and s.type == kind)


def _set(nt, socket, value):
    """Do vstupu zapojí výstup jiného uzlu, nebo nastaví konstantu."""
    if isinstance(value, bpy.types.NodeSocket):
        nt.links.new(value, socket)
    elif isinstance(value, (tuple, list)) and len(value) == 3:
        socket.default_value = (*value, 1.0)
    else:
        socket.default_value = value


def math(nt, op, a, b=0.0, clamp=False):
    """Uzel Math; vrátí jeho výstup."""
    node = nt.nodes.new("ShaderNodeMath")
    node.operation = op
    node.use_clamp = clamp
    _set(nt, node.inputs[0], a)
    _set(nt, node.inputs[1], b)
    return node.outputs[0]


def mix(nt, factor, a, b, blend="MIX"):
    """Uzel Mix pro barvy; vrátí výstupní barvu."""
    node = nt.nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    node.blend_type = blend
    node.clamp_factor = True
    _set(nt, _socket(node, "Factor", "VALUE"), factor)
    _set(nt, _socket(node, "A", "RGBA"), a)
    _set(nt, _socket(node, "B", "RGBA"), b)
    return next(s for s in node.outputs if s.type == "RGBA")


def ramp(nt, value, low, high):
    """Plynulé prahování hodnoty mezi low a high (0 → 1)."""
    node = nt.nodes.new("ShaderNodeMapRange")
    node.interpolation_type = "SMOOTHSTEP"
    _set(nt, node.inputs["Value"], value)
    node.inputs["From Min"].default_value = low
    node.inputs["From Max"].default_value = high
    return node.outputs["Result"]


def noise(nt, coords, scale, detail=8.0, roughness=0.6, stretch=None):
    """Šumová textura; stretch=(x, y, z) protáhne vzor (např. do škrábanců)."""
    if stretch:
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = stretch
        nt.links.new(coords, mapping.inputs["Vector"])
        coords = mapping.outputs["Vector"]
    node = nt.nodes.new("ShaderNodeTexNoise")
    node.inputs["Scale"].default_value = scale
    node.inputs["Detail"].default_value = detail
    node.inputs["Roughness"].default_value = roughness
    nt.links.new(coords, node.inputs["Vector"])
    return node.outputs["Fac"]


def _masks(nt):
    """Společné masky: souřadnice, kouty (AO), hrany (Bevel) a spodní část (špína od země)."""
    coords = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.07
    ao.samples = 16
    crevice = ramp(nt, math(nt, "SUBTRACT", 1.0, ao.outputs["AO"]), 0.05, 0.6)

    bevel = nt.nodes.new("ShaderNodeBevel")
    bevel.inputs["Radius"].default_value = 0.03
    geometry = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bevel.outputs["Normal"], dot.inputs[0])
    nt.links.new(geometry.outputs["Normal"], dot.inputs[1])
    edge = ramp(nt, math(nt, "SUBTRACT", 1.0, dot.outputs["Value"]), 0.01, 0.12)

    position = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geometry.outputs["Position"], position.inputs["Vector"])
    low = ramp(nt, position.outputs["Z"], 0.12, 0.0)
    return coords, crevice, edge, low


def _new(name):
    """Vytvoří (nebo vyprázdní) materiál a vrátí (materiál, strom uzlů, Principled BSDF)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat, nt, bsdf


def _bump(nt, bsdf, height, strength):
    """Zapojí výškovou mapu jako bump do normály."""
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    bump.inputs["Distance"].default_value = 0.003
    nt.links.new(height, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def tread(nt, coords, scale=14.0):
    """Výšková mapa slzičkového plechu: drobné šikmé vyvýšeniny ve střídavém vzoru."""
    heights = []
    for angle in (45.0, -45.0):
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Rotation"].default_value = (0.0, 0.0, angle * 3.14159265 / 180.0)
        nt.links.new(coords, mapping.inputs["Vector"])
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.inputs["Scale"].default_value = scale
        nt.links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
        heights.append(ramp(nt, wave.outputs["Fac"], 0.75, 0.95))
    return math(nt, "MULTIPLY", heights[0], heights[1])


def weathered_metal(name, base, rust=0.5, wear=0.7, metallic=0.5, roughness=0.55, tread_plate=False):
    """Ocel s patinou: skvrny rzi, stékající rezavé šmouhy, odřené světlé hrany, škrábance, špína u země."""
    mat, nt, bsdf = _new(name)
    coords, crevice, edge, low = _masks(nt)

    blotch = noise(nt, coords, 7.0, detail=10.0)
    grain = noise(nt, coords, 90.0, detail=4.0)
    scratches = ramp(nt, noise(nt, coords, 25.0, detail=2.0, stretch=(1.0, 14.0, 1.0)), 0.62, 0.7)
    # Svislé šmouhy: šum stlačený v ose Z – rez stéká dolů po svislých plochách.
    streaks = ramp(nt, noise(nt, coords, 9.0, detail=6.0, stretch=(9.0, 9.0, 0.6)), 0.58, 0.72)
    rust_mask = math(nt, "MULTIPLY",
                     math(nt, "ADD", ramp(nt, blotch, 0.56, 0.62),
                          math(nt, "ADD", math(nt, "MULTIPLY", crevice, 1.2), math(nt, "MULTIPLY", streaks, 0.7)),
                          clamp=True),
                     rust, clamp=True)
    wear_mask = math(nt, "MULTIPLY", math(nt, "MULTIPLY", edge, ramp(nt, grain, 0.35, 0.55)), wear, clamp=True)

    color = mix(nt, math(nt, "MULTIPLY", grain, 0.35), base, tuple(c * 1.35 for c in base))
    color = mix(nt, rust_mask, color, mix(nt, blotch, RUST_DARK, RUST))
    color = mix(nt, math(nt, "ADD", wear_mask, math(nt, "MULTIPLY", scratches, 0.4 * wear), clamp=True),
                color, BARE_METAL)
    color = mix(nt, math(nt, "ADD", math(nt, "MULTIPLY", crevice, 0.55), math(nt, "MULTIPLY", low, 0.5),
                         clamp=True), color, GRIME)
    nt.links.new(color, bsdf.inputs["Base Color"])

    nt.links.new(math(nt, "ADD", math(nt, "MULTIPLY", rust_mask, -metallic), metallic, clamp=True),
                 bsdf.inputs["Metallic"])
    nt.links.new(math(nt, "ADD", math(nt, "MULTIPLY", rust_mask, 0.35),
                      math(nt, "ADD", roughness, math(nt, "MULTIPLY", wear_mask, -0.3)), clamp=True),
                 bsdf.inputs["Roughness"])
    height = math(nt, "ADD", math(nt, "MULTIPLY", grain, 0.3),
                  math(nt, "ADD", rust_mask, math(nt, "MULTIPLY", scratches, -0.5)))
    if tread_plate:
        height = math(nt, "ADD", height, math(nt, "MULTIPLY", tread(nt, coords), 2.5))
    _bump(nt, bsdf, height, 0.35)
    return mat


def chipped_paint(name, paint, under=(0.05, 0.048, 0.045), rusty=True, chipping=0.62):
    """Natřený kov s oprýskanou barvou: v odřených místech a na hranách prosvítá tmavý kov (a rez).

    rusty=False drží materiál ve stupních šedi – nutné pro vrstvu masky, kterou hra obarvuje tintem.
    Nižší chipping = víc oprýskaných míst.
    """
    mat, nt, bsdf = _new(name)
    coords, crevice, edge, low = _masks(nt)

    chips_noise = noise(nt, coords, 28.0, detail=12.0, roughness=0.7)
    chips = ramp(nt, math(nt, "ADD", chips_noise, math(nt, "MULTIPLY", edge, 0.35)), chipping, chipping + 0.04)
    fade = noise(nt, coords, 6.0, detail=6.0)

    paint_color = mix(nt, math(nt, "MULTIPLY", fade, 0.45), paint, tuple(c * 0.7 for c in paint))
    metal = mix(nt, ramp(nt, fade, 0.45, 0.65), under, RUST) if rusty else under
    color = mix(nt, chips, paint_color, metal)
    grime = GRIME if rusty else (0.017, 0.017, 0.017)
    color = mix(nt, math(nt, "ADD", math(nt, "MULTIPLY", crevice, 0.6), math(nt, "MULTIPLY", low, 0.4),
                         clamp=True), color, grime)
    nt.links.new(color, bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.15
    nt.links.new(math(nt, "ADD", 0.5, math(nt, "MULTIPLY", chips, 0.25)), bsdf.inputs["Roughness"])
    _bump(nt, bsdf, math(nt, "MULTIPLY", chips, -1.0), 0.35)
    return mat


def rubber(name):
    """Gumové pásky závěsu: matná tmavá guma se zaprášením."""
    mat, nt, bsdf = _new(name)
    coords, crevice, edge, low = _masks(nt)
    dust = noise(nt, coords, 40.0, detail=6.0)
    color = mix(nt, math(nt, "MULTIPLY", ramp(nt, dust, 0.45, 0.75), 0.6), (0.012, 0.012, 0.012), (0.06, 0.05, 0.04))
    nt.links.new(color, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def void(name):
    """Tmavý vnitřek otvoru (pohlcuje světlo)."""
    mat, nt, bsdf = _new(name)
    bsdf.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat


def grimy(name, base, metallic=0.0, roughness=0.5, dust=0.6, scorch=None, emission=None):
    """Zašlý povrch elektroniky: prach na plochách, mastnota v koutech a u země, jemná zrnitost.

    scorch=(x, y, poloměr) připálí povrch do hněda kolem bodu v souřadnicích objektu (deska kolem procesoru).
    emission=(barva, síla) – svítící povrch (displej), patina ho jen lehce zašpiní.
    """
    mat, nt, bsdf = _new(name)
    coords, crevice, edge, low = _masks(nt)
    dust_noise = noise(nt, coords, 18.0, detail=8.0)
    speck = ramp(nt, noise(nt, coords, 120.0, detail=3.0), 0.55, 0.7)
    dust_mask = math(nt, "MULTIPLY", math(nt, "ADD", ramp(nt, dust_noise, 0.45, 0.75),
                                          math(nt, "MULTIPLY", speck, 0.4), clamp=True), dust, clamp=True)
    color = mix(nt, math(nt, "MULTIPLY", noise(nt, coords, 40.0, detail=4.0), 0.3), base,
                tuple(c * 0.75 for c in base))
    if scorch:
        # Vzdálenost od bodu v rovině XY (souřadnice objektu): tmavé hnědé „připálení“ se šumem na okraji.
        center = nt.nodes.new("ShaderNodeVectorMath")
        center.operation = "DISTANCE"
        center.inputs[1].default_value = (scorch[0], scorch[1], 0.0)
        flat = nt.nodes.new("ShaderNodeVectorMath")
        flat.operation = "MULTIPLY"
        flat.inputs[1].default_value = (1.0, 1.0, 0.0)
        nt.links.new(coords, flat.inputs[0])
        nt.links.new(flat.outputs["Vector"], center.inputs[0])
        wobble = math(nt, "MULTIPLY", noise(nt, coords, 6.0, detail=6.0), scorch[2] * 0.6)
        burnt = ramp(nt, math(nt, "ADD", center.outputs["Value"], wobble), scorch[2] * 1.1, scorch[2] * 0.4)
        color = mix(nt, math(nt, "MULTIPLY", burnt, 0.85), color, (0.035, 0.02, 0.008))
    color = mix(nt, dust_mask, color, (0.16, 0.13, 0.09))
    color = mix(nt, math(nt, "ADD", math(nt, "MULTIPLY", crevice, 0.7), math(nt, "MULTIPLY", low, 0.5), clamp=True),
                color, GRIME)
    nt.links.new(color, bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = metallic
    nt.links.new(math(nt, "ADD", roughness, math(nt, "MULTIPLY", dust_mask, 0.35), clamp=True), bsdf.inputs["Roughness"])
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission[0], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission[1]
    _bump(nt, bsdf, math(nt, "ADD", dust_mask, math(nt, "MULTIPLY", speck, 0.3)), 0.2)
    return mat


def pcb(name, image, size, dust=0.25):
    """Deska plošných spojů z generované textury (RGB = barva, A = maska kovu): lesklá maska, cínové plošky
    kovové, lehký prach a mastnota v koutech. Textura se mapuje ze souřadnic objektu (střed desky = 0, 0)."""
    mat, nt, bsdf = _new(name)
    coords, crevice, edge, low = _masks(nt)
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0 / size[0], 1.0 / size[1], 1.0)
    mapping.inputs["Location"].default_value = (0.5, 0.5, 0.0)
    nt.links.new(coords, mapping.inputs["Vector"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.extension = "EXTEND"
    tex.interpolation = "Cubic"
    nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    dust_mask = math(nt, "MULTIPLY", ramp(nt, noise(nt, coords, 14.0, detail=8.0), 0.5, 0.8), dust, clamp=True)
    color = mix(nt, dust_mask, tex.outputs["Color"], (0.16, 0.13, 0.09))
    color = mix(nt, math(nt, "MULTIPLY", crevice, 0.6), color, GRIME)
    nt.links.new(color, bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Metallic"])
    nt.links.new(math(nt, "ADD", 0.38, math(nt, "MULTIPLY", tex.outputs["Alpha"], -0.12)), bsdf.inputs["Roughness"])
    return mat
