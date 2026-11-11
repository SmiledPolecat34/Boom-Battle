"""E08 Feu (référence : Explosions_32.png, rangée 1, 8e carte) : un BRASIER — hautes langues de feu ondulantes (rouge-orange / orange / jaune, cœur clair) qui jaillissent,
vacillent et retombent, braises qui montent, petits rochers sombres au pied (centre seulement). Pas de gerbe de lames (E01), pas de fumée.
Chaque langue = 3 couches imbriquées (extérieur rouge-orange, milieu orange, cœur jaune). Les langues changent de hauteur et d'inclinaison à chaque image (vacillement).
Briques composables (CENTER, SEGMENT, END ; 4 directions). Pilotage (Blender, E01_Classique_v2.blend ouvert) :
    E08_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Écrit E08_Feu_v2.blend à côté ; E01_Classique_v2.blend n'est jamais écrasé.
"""
import bpy, math, os, random

COL = {"R": "#FF3A08", "O": "#FF8A1E", "Y": "#FFD43A", "W": "#FFF6C8", "EMBER": "#FFC040", "FLASH": "#FFE98A"}
SMOKE = "#2E2724"
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

def make_smoke_mat():
    m = bpy.data.materials["E01_Smoke"].copy()
    m.name = "E08_SMOKE"
    for n in m.node_tree.nodes:
        for i in n.inputs:
            if i.name in ("Color", "Base Color", "Emission Color") and hasattr(i, "default_value") and len(i.default_value) == 4:
                i.default_value = hex_lin(SMOKE)
            if i.name == "Alpha":
                i.default_value = 0.42
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    return m

def make_rock_mat():
    m = bpy.data.materials.new("E08_ROCK")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(ROCK)
    b.inputs["Roughness"].default_value = 0.9
    return m

def _flame_geo(v, f, ox, seed, h=1.0, w=0.34, bend=0.3, rings=9, sides=8, flat=0.5):
    # lame de feu : colonne vertébrale en S (ondulation + courbure + pointe qui s'enroule), section ELLIPTIQUE aplatie, rayon qui gonfle puis s'effile
    r = random.Random(seed)
    ph, ph2 = r.uniform(0, 6.28), r.uniform(0, 6.28)
    bd = bend * r.choice([-1, 1])
    base = len(v)
    rows = []
    for k in range(rings):
        t = k / rings
        cx = ox + bd * t ** 1.7 * h + 0.16 * h * math.sin(4.6 * t + ph) * t
        cy = 0.16 * h * math.sin(3.1 * t + ph2) * t
        rad = w * (1 - t) ** 0.6 * (0.55 + 0.45 * math.sin(math.pi * min(1.0, 0.25 + 0.9 * t))) * (1 + 0.18 * math.sin(7 * t + ph))
        idx = []
        for sd in range(sides):
            a = 2 * math.pi * sd / sides + 0.25 * t
            rr = rad * (1 + r.uniform(-0.1, 0.1))
            v.append((cx + rr * math.cos(a), cy + rr * flat * math.sin(a), t * h))
            idx.append(len(v) - 1)
        rows.append(idx)
    v.append((ox + bd * h * 1.05 + 0.05 * h, 0.16 * h * math.sin(3.1 + ph2) + 0.03, h))
    tip = len(v) - 1
    f.append(tuple(reversed(rows[0])))
    for k in range(rings - 1):
        for sd in range(sides):
            a, b = rows[k][sd], rows[k][(sd + 1) % sides]
            c, d = rows[k + 1][(sd + 1) % sides], rows[k + 1][sd]
            f.append((a, b, c, d))
    for sd in range(sides):
        f.append((rows[-1][sd], rows[-1][(sd + 1) % sides], tip))

def flame_mesh(name, seed, bend=0.3):
    v, f = [], []
    _flame_geo(v, f, 0.0, seed, bend=bend)
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    for p in me.polygons:
        p.use_smooth = True
    return me

def row_mesh(name, seed, n=6, length=4.8):
    # RANGÉE de flammes basses et serrées qui court le long d'un bras (une seule maille) : relie visuellement les cases en une vague continue
    r = random.Random(seed)
    v, f = [], []
    for j in range(n):
        x = -length / 2 + length * (j + 0.5) / n
        _flame_geo(v, f, x, seed * 10 + j, h=r.uniform(0.55, 0.95), w=0.46, bend=r.uniform(0.15, 0.35), rings=5, sides=6, flat=0.8)
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    for p in me.polygons:
        p.use_smooth = True
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
        ob.rotation_euler = (math.radians(ta), math.radians(tb), math.radians(yaw + ctx.arm) + jr.uniform(-1.1, 1.1) * (1 if tilt else 0))
        ob.keyframe_insert("rotation_euler", frame=ctx.t0 + fr)
    if loc_keys:
        for fr, (x, y, z) in loc_keys:
            wx, wy = ctx.world(x, y)
            ob.location = (wx, wy, z)
            ob.keyframe_insert("location", frame=ctx.t0 + fr)
    COUNTS[ctx.coll.name] = COUNTS.get(ctx.coll.name, 0) + 1
    return ob

def life(L, seed, start=2, flick=0.16):
    # apparition en 1-2 images, dépassement (pic), vacillement irrégulier qui se calme, retombée douce
    r = random.Random(seed)
    out = [(1, 0.001), (start, 0.5 * L), (start + 1, 1.18 * L), (start + 2, 1.0 * L)]
    for fr in range(start + 3, 9):
        out.append((fr, L * (0.95 - 0.04 * (fr - start - 2)) * r.uniform(1 - flick, 1 + flick)))
    out += [(9, 0.62 * L), (10, 0.38 * L), (11, 0.16 * L), (12, 0.001)]
    return out

def tongue(ctx, tag, n, M, loc, L, delay=0, layers="ROY"):
    # couches imbriquées : rouge (extérieur) / orange / jaune (/ blanc-jaune au cœur du centre), chacune une variante de forme différente
    spec = {"R": ("R", 1.0, 0.0), "O": ("O", 0.78, 0.03), "Y": ("Y", 0.55, 0.06), "W": ("W", 0.34, 0.09)}
    for i, ch in enumerate(layers):
        mk, k, up = spec[ch]
        add_obj(ctx, f"{tag}_Flame{n}{ch}", M["flame"][(n + i) % 4], M[mk], (loc[0], loc[1], loc[2] + up),
                life(1.35 * L * k, 40 * n + i, 2 + delay), tilt=13 if i == 0 else 9)

def ballistic(v0, h0, steps=12, g=14.0):
    out = []
    for fr in range(1, steps + 1):
        t = (fr - 1) / 24.0
        out.append((fr, (v0[0] * t, v0[1] * t, max(0.1, h0 + v0[2] * t - 0.5 * g * t * t))))
    return out

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        # flash jaune-blanc très bref + poussée de flammes plus haute
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 1.5), (3, 0.8), (4, 0.001)], tilt=1, yaw=0)
        tongue(ctx, tag, 0, M, (0, 0, 0.0), 3.6, layers="ROYW")
        for n, a in enumerate((45, 135, 225, 315)):
            x, y = 0.95 * math.cos(math.radians(a)), 0.95 * math.sin(math.radians(a))
            tongue(ctx, tag, n + 1, M, (x, y, 0.0), 2.3 - 0.2 * (n % 2), delay=n % 2, layers="ROY")
        for n in range(4):  # petits rochers sombres au pied
            a = math.radians(20 + 90 * n)
            add_obj(ctx, f"{tag}_Rock{n}", M["rock"][n % 2], M["ROCK"], (1.6 * math.cos(a), 1.6 * math.sin(a), 0.0),
                    [(1, 0.001), (2, 1.0), (11, 1.0), (12, 0.001)], yaw=n * 70)
        for n in range(4):  # langues de feu secondaires projetées vers l'extérieur
            a = math.radians(0 + 90 * n)
            add_obj(ctx, f"{tag}_Lick{n}", M["flame"][(n + 1) % 4], M["O"], (0.4 * math.cos(a), 0.4 * math.sin(a), 0.4),
                    [(1, 0.001), (2, 0.9), (6, 0.8), (9, 0.001)], tilt=40,
                    loc_keys=[(f, (0.4 * math.cos(a) + 0.5 * f * math.cos(a), 0.4 * math.sin(a) + 0.5 * f * math.sin(a), 0.4 + 0.9 * math.sin(min(f, 9) / 9 * math.pi))) for f in range(1, 10)])
        nem, smk = 8, 2
    elif kind == "segment":
        add_obj(ctx, f"{tag}_Row", M["row"], M["O"], (0, 0, 0.0), life(1.0, 7, 2, 0.12), tilt=6)
        tongue(ctx, tag, 0, M, (0, 0, 0.0), 2.0, layers="ROY")
        tongue(ctx, tag, 1, M, (0.3, 1.0, 0.0), 1.3, delay=1, layers="RO")
        tongue(ctx, tag, 2, M, (-0.3, -1.0, 0.0), 1.3, delay=1, layers="RO")
        nem, smk = 4, 1
    else:
        add_obj(ctx, f"{tag}_Row", M["row"], M["R"], (0, 0, 0.0), life(0.9, 9, 3, 0.12), tilt=6)
        tongue(ctx, tag, 0, M, (0, 0, 0.0), 2.3, delay=1, layers="ROY")
        tongue(ctx, tag, 1, M, (-0.1, 1.0, 0.0), 1.4, delay=2, layers="RO")
        tongue(ctx, tag, 2, M, (-0.1, -1.0, 0.0), 1.4, delay=2, layers="RO")
        add_obj(ctx, f"{tag}_Lick0", M["flame"][2], M["O"], (0.6, 0, 0.4), [(1, 0.001), (3, 0.9), (7, 0.7), (10, 0.001)], tilt=40,
                loc_keys=[(f, (0.6 + 0.5 * f, 0, 0.4 + 0.8 * math.sin(min(f, 10) / 10 * math.pi))) for f in range(1, 11)])
        nem, smk = 4, 1
    for n in range(nem):  # braises incandescentes projetées vers l'extérieur (le long du bras / du centre)
        ang = r.uniform(-0.5, 0.5) if kind != "center" else r.uniform(0, 6.28)
        sp, vz = r.uniform(4.5, 8.0), r.uniform(3.0, 7.0)
        add_obj(ctx, f"{tag}_Ember{n}", M["ember"], M["EMBER"], (0, 0, 0.5), [(1, 0.001), (2, 1.2), (9, 0.9), (12, 0.001)],
                loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.5))
    for n in range(smk):  # légère fumée sombre qui monte pendant la dissipation (petite, translucide)
        add_obj(ctx, f"{tag}_Smoke{n}", M["smoke"], M["SMOKE"], (0.3 * n, 0.2 * n, 1.2), [(1, 0.001), (6, 0.001), (8, 0.7), (11, 1.0), (13, 0.001)],
                loc_keys=[(f, (0.3 * n, 0.2 * n, 1.2 + 0.28 * f)) for f in range(1, 14)])

def build():
    M = {k: make_mat(k, hx) for k, hx in COL.items()}
    M["ROCK"] = make_rock_mat()
    M["SMOKE"] = make_smoke_mat()
    M["flame"] = [flame_mesh("E08_Flame%d" % i, 10 + i, bend=0.22 + 0.06 * i) for i in range(4)]
    M["row"] = row_mesh("E08_Row", 3)
    M["flash"] = blob_mesh("E08_Flash", 0.7, 0.85, 0.55, 77, 2)
    M["smoke"] = blob_mesh("E08_Smoke", 0.7, 0.6, 0.12, 88, 2)
    for pg in M["smoke"].polygons:
        pg.use_smooth = True
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
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E08_Feu_v2.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E08")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 5, 7, 9, 11)), ("CAM_Game", (4, 8))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v2_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E08_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
