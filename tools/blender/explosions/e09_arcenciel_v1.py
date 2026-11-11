"""E09 Arc-en-ciel (référence : Explosions_32.png, rangée 2, 1re carte) : gerbe de lames aux 7 couleurs de l'arc-en-ciel autour d'un cœur blanc, flash bref,
confettis colorés projetés, petits nuages violets / roses / bleus au pied. Lecture en croix conservée (lames dans le sens des bras).
Briques composables (CENTER, SEGMENT, END ; 4 directions). Pilotage (Blender, E01_Classique_v2.blend ouvert) :
    E09_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Écrit E09_ArcEnCiel_v1.blend à côté ; E01_Classique_v2.blend n'est jamais écrasé.
"""
import bpy, math, os, random

RAINBOW = ["#FF3B3B", "#FF9A1F", "#FFE53B", "#3DDC5B", "#2FC8FF", "#3D6BFF", "#A64DFF"]
PUFF = ["#8E5BFF", "#FF6FD8", "#5CC8FF"]
CELL = 4.0
ARMS = {"E": 0.0, "N": 90.0, "S": -90.0, "W": 180.0}
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

def make_neon(key, hx):
    m = bpy.data.materials["E01_WhiteHot"].copy()
    m.name = "E09_" + key
    set_color(m, hx)
    return m

def make_puff(key, hx):
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.6
    b.inputs["Emission Color"].default_value = hex_lin(hx)
    b.inputs["Emission Strength"].default_value = 0.55
    return m

def blade_mesh(name="E09_Blade"):
    v = [(0, 0, 0), (0.3, -0.17, 0), (0.3, 0.17, 0), (1, 0, 0), (0.3, 0, 0.06), (0.3, 0, -0.06)]
    b, l, r, tip, t, u = range(6)
    f = [(b, l, t), (b, t, r), (b, r, u), (b, u, l), (l, tip, t), (t, tip, r), (r, tip, u), (u, tip, l)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def confetti_mesh(name="E09_Confetti"):
    v = [(-0.09, -0.06, 0), (0.09, -0.06, 0), (0.09, 0.06, 0), (-0.09, 0.06, 0)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], [(0, 1, 2, 3), (3, 2, 1, 0)])
    me.update()
    return me

def blob_mesh(name, radius, squash, jitter, seed, detail=1):
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=radius)
    r = random.Random(seed)
    for vert in bm.verts:
        vert.co *= 1.0 - jitter + 2 * jitter * r.random()
        vert.co.z *= squash
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me

def rot(x, y, deg):
    a = math.radians(deg)
    return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)

class Ctx:
    def __init__(self, coll, arm, ox, t0):
        self.coll, self.arm, self.ox, self.t0 = coll, ARMS[arm], ox, t0
    def world(self, x, y):
        return rot(self.ox + x, y, self.arm)

def add_obj(ctx, name, mesh, mat, loc, keys, az=0.0, el=0.0, jit=0.0, loc_keys=None, tumble=False):
    # keys = [(image, échelle)] ; az/el = direction (degrés, repère de la brique) ; jit = scintillement angulaire par image ; tumble = confetti qui tourne
    jr = random.Random(name)
    ob = bpy.data.objects.new(name, mesh)
    if not ob.data.materials:
        ob.data.materials.append(mat)
    ctx.coll.objects.link(ob)
    ob.visible_shadow = False
    wx, wy = ctx.world(loc[0], loc[1])
    ob.location = (wx, wy, loc[2])
    for fr, s in keys:
        ob.scale = (s, s, s)
        ob.keyframe_insert("scale", frame=ctx.t0 + fr)
        if tumble:
            ob.rotation_euler = (jr.uniform(0, 6.28), jr.uniform(0, 6.28), jr.uniform(0, 6.28))
        else:
            ja = jr.uniform(-jit, jit) if s > 0.01 else 0.0
            je = jr.uniform(-jit * 0.5, jit * 0.5) if s > 0.01 else 0.0
            ob.rotation_euler = (0, -math.radians(el + je), math.radians(az + ja + ctx.arm))
        ob.keyframe_insert("rotation_euler", frame=ctx.t0 + fr)
    if loc_keys:
        for fr, (x, y, z) in loc_keys:
            wx, wy = ctx.world(x, y)
            ob.location = (wx, wy, z)
            ob.keyframe_insert("location", frame=ctx.t0 + fr)
    COUNTS[ctx.coll.name] = COUNTS.get(ctx.coll.name, 0) + 1
    return ob

def ballistic(v0, h0, steps=12, g=16.0):
    return [(fr, (v0[0] * (fr - 1) / 24.0, v0[1] * (fr - 1) / 24.0, max(0.1, h0 + v0[2] * (fr - 1) / 24.0 - 0.5 * g * ((fr - 1) / 24.0) ** 2))) for fr in range(1, steps + 1)]

def pop(L, start=2):
    # apparition fulgurante avec dépassement, tenue, retombée
    return [(1, 0.001), (start, 0.6 * L), (start + 1, 1.15 * L), (start + 2, L), (9, 0.95 * L), (10, 0.6 * L), (11, 0.25 * L), (12, 0.001)]

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 1.5), (3, 0.8), (4, 0.001)], jit=0)
        n = 14
        for i in range(n):  # éventail de lames, une couleur par secteur (arc-en-ciel autour du centre)
            az = 360.0 * i / n
            el = 32 + 22 * (i % 3)
            ln = 2.6 + 0.5 * (i % 2)
            add_obj(ctx, f"{tag}_Blade{i}", M["blade"][i % 7], M["C%d" % (i % 7)], (0.15 * math.cos(math.radians(az)), 0.15 * math.sin(math.radians(az)), 0.3),
                    pop(ln, 2 + (i % 2)), az=az, el=el, jit=7)
        for i in range(4):  # nuages colorés au pied
            a = math.radians(45 + 90 * i)
            add_obj(ctx, f"{tag}_Puff{i}", M["puffs"][i % 3], M["PUFF%d" % (i % 3)], (1.3 * math.cos(a), 1.3 * math.sin(a), 0.35),
                    [(1, 0.001), (3, 1.0), (9, 1.0), (12, 0.001)])
        nconf, nb = 10, 0
    elif kind == "segment":
        for i, (az, el, ln) in enumerate([(-40, 38, 1.9), (-18, 52, 2.2), (0, 62, 2.5), (18, 52, 2.2), (40, 38, 1.9), (180, 40, 1.0)][:5]):
            add_obj(ctx, f"{tag}_Blade{i}", M["blade"][(i + 1) % 7], M["C%d" % ((i + 1) % 7)], (0, 0, 0.3), pop(ln, 3), az=az, el=el, jit=7)
        add_obj(ctx, f"{tag}_Puff0", M["puffs"][1], M["PUFF1"], (0, 0, 0.3), [(1, 0.001), (4, 0.9), (9, 0.9), (12, 0.001)])
        nconf, nb = 3, 0
    else:
        for i, (az, el, ln) in enumerate([(-35, 36, 1.7), (-12, 52, 2.1), (12, 52, 2.1), (35, 36, 1.7), (0, 70, 2.4)]):
            add_obj(ctx, f"{tag}_Blade{i}", M["blade"][(i + 3) % 7], M["C%d" % ((i + 3) % 7)], (0, 0, 0.3), pop(ln, 4), az=az, el=el, jit=7)
        add_obj(ctx, f"{tag}_Puff0", M["puffs"][2], M["PUFF2"], (0, 0, 0.3), [(1, 0.001), (5, 0.9), (9, 0.9), (12, 0.001)])
        nconf, nb = 4, 0
    for n in range(nconf):  # confettis colorés projetés, qui tournent
        ang = r.uniform(0, 6.28) if kind == "center" else r.uniform(-0.6, 0.6)
        sp, vz = r.uniform(4.0, 8.0), r.uniform(4.0, 8.0)
        add_obj(ctx, f"{tag}_Confetti{n}", M["confetti"][(n * 3) % 7], M["C%d" % ((n * 3) % 7)], (0, 0, 0.6), [(1, 0.001), (2, 1.3), (10, 1.0), (12, 0.001)],
                loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.6), tumble=True)

def build():
    M = {"C%d" % i: make_neon("C%d" % i, hx) for i, hx in enumerate(RAINBOW)}
    M["FLASH"] = make_neon("FLASH", "#FFFBE0")
    for i, hx in enumerate(PUFF):
        M["PUFF%d" % i] = make_puff("PUFF%d" % i, hx)
    M["blade"] = [blade_mesh("E09_Blade%d" % i) for i in range(7)]
    M["confetti"] = [confetti_mesh("E09_Confetti%d" % i) for i in range(7)]
    M["puffs"] = [blob_mesh("E09_Puff%d" % i, 0.75, 0.6, 0.18, 21 + i, 1) for i in range(3)]
    M["flash"] = blob_mesh("E09_Flash", 0.7, 0.85, 0.5, 33, 2)
    for cn in ["E01_CENTER"] + ["E01_SEG1_" + d for d in ARMS] + ["E01_END_" + d for d in ARMS]:
        for o in list(bpy.data.collections[cn].objects):
            bpy.data.objects.remove(o)
    COUNTS.clear()
    build_brick(Ctx(bpy.data.collections["E01_CENTER"], "E", 0.0, 0), "center", M)
    for d in ARMS:
        build_brick(Ctx(bpy.data.collections["E01_SEG1_" + d], d, CELL, 1), "segment", M)
        build_brick(Ctx(bpy.data.collections["E01_END_" + d], d, 2 * CELL, 2), "end", M)
    tri = {cn: len([o for o in bpy.data.collections[cn].objects if o.type == "MESH"]) for cn in ("E01_CENTER", "E01_SEG1_E", "E01_END_E")}
    print("OBJETS par brique :", tri)
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E09_ArcEnCiel")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E09_ArcEnCiel_v1.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E09")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 5, 7, 9, 11)), ("CAM_Game", (4, 8))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v1_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E09_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
