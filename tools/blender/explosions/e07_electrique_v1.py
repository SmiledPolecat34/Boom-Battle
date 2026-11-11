"""E07 Électrique (référence : Explosions_32.png, rangée 1, 7e carte) : gerbe bleu électrique à cœur blanc-bleuté, ÉCLAIRS fins et déchiquetés qui jaillissent
et crépitent (clignotement), arcs électriques au ras du sol, pas de rochers, pas de fumée. Palette : bleu électrique de l'image de référence de la bombe électrique.
Base : les briques d'E01 (lames, cœur, lueur, étincelles, cailloux) RECOLORÉES en violet + éclairs nouveaux (maillages zigzag) ajoutés dans chaque brique.
Pilotage (Blender, E01_Classique_v2.blend ouvert) :
    E07_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Écrit E07_Electrique_v1.blend à côté ; E01_Classique_v2.blend n'est jamais écrasé.
"""
import bpy, math, os, random

ROCK_SCALE = 2.0
PALETTE = {  # bleu électrique de l'image de référence (bombe électrique : éclairs bleu vif / cyan, cœur blanc-bleuté)
    "E01_Red": "#1E64FF", "E01_Orange": "#2D9BFF", "E01_Yellow": "#5CC8FF", "E01_WhiteHot": "#D2F2FF",
    "E01_Core": "#FFFFFF", "E01_Glow": "#3AA0FF", "E01_Spark": "#A5E6FF", "E01_DangerTile": "#2D7FE0",
    "E01_RockDark": "#1E64FF", "E01_RockLight": "#5CC8FF",
}
CELL = 4.0
ARMS = {"E": 0.0, "N": 90.0, "S": -90.0, "W": 180.0}
RNG = random.Random(707)
COUNTS = {}

def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def hex_lin(h):
    h = h.lstrip("#")
    return tuple(lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)

def set_color(mat, hx):
    for n in mat.node_tree.nodes:
        for i in n.inputs:
            if i.name in ("Color", "Base Color", "Emission Color") and hasattr(i, "default_value") and len(i.default_value) == 4:
                i.default_value = hex_lin(hx)

def recolor():
    for name, hx in PALETTE.items():
        m = bpy.data.materials.get(name)
        if m:
            set_color(m, hx)
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            continue
        if "Debris" in o.name or "Blades" in o.name:  # ni rochers ni gerbe de lames : électricité seulement (E03 Bleue garde la gerbe)
            bpy.data.objects.remove(o)
        elif "Smoke" in o.name:
            o.hide_render = True
            o.hide_viewport = True

def bolt_mesh(name, seed, n=8, amp=0.14, w=0.07):
    # éclair : ligne brisée de longueur 1 le long de +X, ruban en croix (visible de tous côtés)
    r = random.Random(seed)
    pts = []
    for i in range(n + 1):
        t = i / n
        a = 0.0 if i in (0, n) else amp * r.uniform(0.5, 1.0) * (1 if i % 2 else -1) * (1.0 - 0.4 * t)
        b = 0.0 if i in (0, n) else amp * r.uniform(-0.6, 0.6)
        pts.append((t, a, b))
    v, f = [], []
    for i, (x, y, z) in enumerate(pts):
        ww = w * (1.0 - 0.55 * i / n)
        v += [(x, y - ww, z), (x, y + ww, z), (x, y, z - ww), (x, y, z + ww)]
    for i in range(n):
        a, b = 4 * i, 4 * (i + 1)
        f += [(a, a + 1, b + 1, b), (a + 2, a + 3, b + 3, b + 2)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def rot(x, y, deg):
    a = math.radians(deg)
    return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)

def add_bolt(coll, arm, ox, t0, name, mesh, mat, loc, az, el, ln, keys):
    arm_deg = ARMS[arm]
    ob = bpy.data.objects.new(name, mesh)
    ob.data.materials.append(mat)
    coll.objects.link(ob)
    ob.visible_shadow = False
    wx, wy = rot(ox + loc[0], loc[1], arm_deg)
    ob.location = (wx, wy, loc[2])
    ob.rotation_euler = (0, -math.radians(el), math.radians(az) + math.radians(arm_deg))
    for f, k in keys:
        s = max(0.001, ln * k)
        ob.scale = (s, s, s)
        ob.keyframe_insert("scale", frame=t0 + f)
    COUNTS[coll.name] = COUNTS.get(coll.name, 0) + 1

def flicker(phase):
    # clignotement : allumé / éteint, puis s'éteint ; décalé par éclair pour un crépitement irrégulier
    seq = [(1, 0.001), (2 + phase, 1.0), (3 + phase, 0.001), (4 + phase, 0.9), (5 + phase, 0.001), (6 + phase, 1.0), (8, 0.75), (10, 0.35), (11, 0.001)]
    out, last = [], 0
    for f, k in seq:
        if f > last:
            out.append((f, k))
            last = f
    return out

def build_brick(coll, arm, ox, t0, kind, M):
    tag = coll.name
    if kind == "center":
        spec = [(a, 28 if i % 2 else 12, 3.0 if i % 2 else 3.8) for i, a in enumerate(range(0, 360, 45))]  # 8 éclairs
        arcs = [(a, 0, 2.0) for a in (10, 70, 130, 190, 250, 310)]  # arcs au ras du sol
    elif kind == "segment":
        spec = [(-14, 30, 2.1), (16, 18, 2.4), (90, 36, 1.7)]
        arcs = [(-60, 0, 1.5), (70, 0, 1.5)]
    else:
        spec = [(-20, 26, 2.2), (0, 40, 2.8), (20, 26, 2.2)]
        arcs = [(-70, 0, 1.4), (70, 0, 1.4)]
    for n, (az, el, ln) in enumerate(spec):
        add_bolt(coll, arm, ox, t0, f"{tag}_Bolt{n}", M["bolt"][n % 3], M["BOLT"], (0.2 * math.cos(math.radians(az)), 0.2 * math.sin(math.radians(az)), 0.35),
                 az, el, ln, flicker(n % 3))
        add_bolt(coll, arm, ox, t0, f"{tag}_BoltCore{n}", M["core"][n % 3], M["CORE"], (0.2 * math.cos(math.radians(az)), 0.2 * math.sin(math.radians(az)), 0.37),
                 az, el, ln, flicker(n % 3))
    for n, (az, el, ln) in enumerate(arcs):
        add_bolt(coll, arm, ox, t0, f"{tag}_Arc{n}", M["bolt"][(n + 1) % 3], M["BOLT2"], (0.1, 0.1, 0.12), az, el, ln, flicker((n + 1) % 3))

def build():
    recolor()
    M = {}
    for key, hx in (("BOLT", "#35B4FF"), ("BOLT2", "#35B4FF"), ("CORE", "#FFFFFF")):
        m = bpy.data.materials["E01_WhiteHot"].copy()
        m.name = "E07_" + key
        set_color(m, hx)
        M[key] = m
    M["bolt"] = [bolt_mesh("E07_Bolt%d" % i, 500 + i, amp=0.15, w=0.10) for i in range(3)]
    M["core"] = [bolt_mesh("E07_Core%d" % i, 500 + i, amp=0.15, w=0.04) for i in range(3)]
    COUNTS.clear()
    build_brick(bpy.data.collections["E01_CENTER"], "E", 0.0, 0, "center", M)
    for d in ARMS:
        build_brick(bpy.data.collections["E01_SEG1_" + d], d, CELL, 1, "segment", M)
        build_brick(bpy.data.collections["E01_END_" + d], d, 2 * CELL, 2, "end", M)
    tri = {cn: len([o for o in bpy.data.collections[cn].objects if o.type == "MESH"]) for cn in ("E01_CENTER", "E01_SEG1_E", "E01_END_E")}
    print("OBJETS par brique (E01 recolorés + éclairs) :", tri)
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E07_Electrique")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E07_Electrique_v1.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E07")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (3, 4, 5, 6, 8, 11)), ("CAM_Game", (4, 6, 8))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v1_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E07_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
