"""E08 Feu (référence : Explosions_32.png, rangée 1, 8e carte) : un BRASIER — hautes langues de feu ondulantes (rouge-orange / orange / jaune, cœur clair) qui jaillissent,
vacillent et retombent, braises qui montent, petits rochers sombres au pied (centre seulement). Pas de gerbe de lames (E01), pas de fumée.
Chaque langue = 3 couches imbriquées (extérieur rouge-orange, milieu orange, cœur jaune). Les langues changent de hauteur et d'inclinaison à chaque image (vacillement).
Briques composables (CENTER, SEGMENT, END ; 4 directions). Pilotage (Blender, E01_Classique_v2.blend ouvert) :
    E08_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Écrit E08_Feu_v1.blend à côté ; E01_Classique_v2.blend n'est jamais écrasé.
"""
import bpy, math, os, random

COL = {"R": "#FF4A0A", "O": "#FF8A1E", "Y": "#FFD43A", "W": "#FFF3C0", "EMBER": "#FFC040"}
ROCK = "#3A2C26"
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

def make_mat(key, hx):
    m = bpy.data.materials["E01_WhiteHot"].copy()  # émissif opaque
    m.name = "E08_" + key
    set_color(m, hx)
    return m

def make_rock_mat():
    m = bpy.data.materials.new("E08_ROCK")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(ROCK)
    b.inputs["Roughness"].default_value = 0.9
    return m

def flame_mesh(name, seed, sides=6, rings=6, bend=0.25, wave=0.30):
    # langue de feu : base z=0, hauteur 1, pointe recourbée, flancs ondulés (low-poly facetté)
    r = random.Random(seed)
    ph = r.uniform(0, 6.28)
    bd = bend * r.choice([-1, 1])
    v, f = [], []
    ring_idx = []
    for k in range(rings):
        t = k / rings
        rad = 0.34 * (1 - t) ** 0.72 * (1 + wave * math.sin(5.2 * t + ph)) * (1.0 + 0.0 * k)
        cx, cy = bd * t * t, 0.18 * bd * t * t
        idx = []
        for s in range(sides):
            a = 2 * math.pi * s / sides + 0.35 * t
            rr = rad * (1 + r.uniform(-0.12, 0.12))
            v.append((cx + rr * math.cos(a), cy + rr * math.sin(a), t))
            idx.append(len(v) - 1)
        ring_idx.append(idx)
    v.append((bd * 1.0, 0.18 * bd, 1.0))
    tip = len(v) - 1
    f.append(tuple(reversed(ring_idx[0])))
    for k in range(rings - 1):
        for s in range(sides):
            a, b = ring_idx[k][s], ring_idx[k][(s + 1) % sides]
            c, d = ring_idx[k + 1][(s + 1) % sides], ring_idx[k + 1][s]
            f.append((a, b, c, d))
    for s in range(sides):
        f.append((ring_idx[-1][s], ring_idx[-1][(s + 1) % sides], tip))
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
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

def add_obj(ctx, name, mesh, mat, loc, keys, tilt=None, yaw=0.0, loc_keys=None):
    # keys = [(image, échelle)] ; tilt = (amplitude°) d'inclinaison aléatoire PAR IMAGE (vacillement) ; loc_keys = [(image,(x,y,z))]
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
        ta = jr.uniform(-tilt, tilt) if tilt and s > 0.01 else 0.0
        tb = jr.uniform(-tilt, tilt) if tilt and s > 0.01 else 0.0
        ob.rotation_euler = (math.radians(ta), math.radians(tb), math.radians(yaw + ctx.arm) + jr.uniform(-0.15, 0.15) * (1 if tilt else 0))
        ob.keyframe_insert("rotation_euler", frame=ctx.t0 + fr)
    if loc_keys:
        for fr, (x, y, z) in loc_keys:
            wx, wy = ctx.world(x, y)
            ob.location = (wx, wy, z)
            ob.keyframe_insert("location", frame=ctx.t0 + fr)
    COUNTS[ctx.coll.name] = COUNTS.get(ctx.coll.name, 0) + 1
    return ob

def life(L, seed, start=2):
    # croissance fulgurante, vacillement irrégulier, retombée
    r = random.Random(seed)
    out = [(1, 0.001), (start, 0.55 * L), (start + 1, 1.12 * L)]
    for fr in range(start + 2, 9):
        out.append((fr, L * r.uniform(0.78, 1.08)))
    out += [(9, 0.72 * L), (10, 0.45 * L), (11, 0.18 * L), (12, 0.001)]
    return out

def tongue(ctx, tag, n, M, loc, L, delay=0):
    # 3 couches : rouge-orange (extérieur), orange (milieu), jaune (cœur), chacune un peu plus petite / décalée
    for i, (mk, k, up) in enumerate((("R", 1.0, 0.0), ("O", 0.78, 0.04), ("Y", 0.52, 0.08))):
        add_obj(ctx, f"{tag}_Flame{n}{'ROY'[i]}", M["flame"][(n + i) % 3], M[mk], (loc[0], loc[1], loc[2] + up),
                life(1.35 * L * k, 40 * n + i, 2 + delay), tilt=11 if i == 0 else 8)

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    if kind == "center":
        tongue(ctx, tag, 0, M, (0, 0, 0.0), 3.1)
        for n, a in enumerate((45, 135, 225, 315)):
            x, y = 0.95 * math.cos(math.radians(a)), 0.95 * math.sin(math.radians(a))
            tongue(ctx, tag, n + 1, M, (x, y, 0.0), 2.1 - 0.15 * (n % 2), delay=n % 2)
        for n in range(4):  # petits rochers sombres au pied (comme la référence)
            a = math.radians(20 + 90 * n)
            add_obj(ctx, f"{tag}_Rock{n}", M["rock"][n % 2], M["ROCK"], (1.5 * math.cos(a), 1.5 * math.sin(a), 0.0),
                    [(1, 0.001), (2, 1.0), (11, 1.0), (12, 0.001)], yaw=n * 70)
        nem = 6
    elif kind == "segment":
        tongue(ctx, tag, 0, M, (0, 0, 0.0), 1.9)
        tongue(ctx, tag, 1, M, (0.2, 0.95, 0.0), 1.3, delay=1)
        tongue(ctx, tag, 2, M, (-0.2, -0.95, 0.0), 1.3, delay=1)
        nem = 3
    else:
        tongue(ctx, tag, 0, M, (0, 0, 0.0), 2.4, delay=1)
        tongue(ctx, tag, 1, M, (-0.1, 0.95, 0.0), 1.5, delay=2)
        tongue(ctx, tag, 2, M, (-0.1, -0.95, 0.0), 1.5, delay=2)
        nem = 3
    r = random.Random(tag)
    for n in range(nem):  # braises qui montent
        x0, y0 = r.uniform(-0.8, 0.8), r.uniform(-0.8, 0.8)
        drift = (r.uniform(-0.6, 0.6), r.uniform(-0.6, 0.6))
        add_obj(ctx, f"{tag}_Ember{n}", M["ember"], M["EMBER"], (x0, y0, 0.5),
                [(1, 0.001), (3, 1.0), (9, 0.9), (12, 0.001)],
                loc_keys=[(f, (x0 + drift[0] * f * 0.2, y0 + drift[1] * f * 0.2, 0.5 + 0.55 * f)) for f in range(1, 13)])

def build():
    M = {k: make_mat(k, hx) for k, hx in COL.items()}
    M["ROCK"] = make_rock_mat()
    M["flame"] = [flame_mesh("E08_Flame%d" % i, 10 + i, bend=0.22 + 0.06 * i) for i in range(3)]
    M["rock"] = [blob_mesh("E08_Rock%d" % i, 0.42, 0.65, 0.3, 60 + i, 1) for i in range(2)]
    M["ember"] = blob_mesh("E08_Ember", 0.10, 1.0, 0.1, 5, 0)
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
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E08_Feu")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E08_Feu_v1.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E08")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 4, 6, 8, 10)), ("CAM_Game", (4, 7))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v1_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E08_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
