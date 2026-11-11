"""E09 Arc-en-ciel (référence : Explosions_32.png, rangée 2, 1re carte) : gerbe de lames aux 7 couleurs de l'arc-en-ciel autour d'un cœur blanc, flash bref,
confettis colorés projetés, petits nuages violets / roses / bleus au pied. Lecture en croix conservée (lames dans le sens des bras).
Briques composables (CENTER, SEGMENT, END ; 4 directions). Pilotage (Blender, E01_Classique_v2.blend ouvert) :
    E09_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Écrit E09_ArcEnCiel_v2.blend à côté ; E01_Classique_v2.blend n'est jamais écrasé.
"""
import bpy, math, os, random

RAINBOW = ["#FF3B3B", "#FF9A1F", "#FFE53B", "#3DDC5B", "#2FC8FF", "#3D6BFF", "#A64DFF"]
PUFF = ["#8E5BFF", "#FF6FD8", "#5CC8FF"]
RING_A, RING_B = "#FF6FD8", "#5CC8FF"
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

def mk(name, v, f):
    import bmesh
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return me

def blade_mesh(name="E09_Blade"):
    # lame effilée et COURBE (virgule) : moins rigide, donne un effet de tourbillon quand elles sont toutes orientées pareil
    secs = [(0.30, 0.17, 0.06), (0.62, 0.11, 0.045), (0.88, 0.05, 0.025)]
    bend = 0.22
    v = [(0, 0, 0)]
    for x, w, h in secs:
        yb = bend * x * x
        v += [(x, yb - w, 0), (x, yb, h), (x, yb + w, 0), (x, yb, -h)]
    v.append((1.0, bend, 0))
    f = []
    for k in range(4):
        f.append((0, 1 + (k + 1) % 4, 1 + k))
    for s_ in range(len(secs) - 1):
        a, b = 1 + 4 * s_, 1 + 4 * (s_ + 1)
        for k in range(4):
            k2 = (k + 1) % 4
            f.append((a + k, a + k2, b + k2, b + k))
    last = 1 + 4 * (len(secs) - 1)
    tip = len(v) - 1
    for k in range(4):
        f.append((last + k, last + (k + 1) % 4, tip))
    return mk(name, v, f)

def confetti_mesh(name="E09_Confetti"):
    v = [(-0.09, -0.06, 0), (0.09, -0.06, 0), (0.09, 0.06, 0), (-0.09, 0.06, 0)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], [(0, 1, 2, 3), (3, 2, 1, 0)])
    me.update()
    return me

def star_mesh(name="E09_Star"):
    # étoile à 4 branches, légèrement épaisse (bipyramide)
    v = [(0, 0, 0.05), (0, 0, -0.05)]
    for k in range(8):
        a = math.pi * k / 4
        r = 0.26 if k % 2 == 0 else 0.08
        v.append((r * math.cos(a), r * math.sin(a), 0))
    f = []
    for k in range(8):
        n = (k + 1) % 8
        f.append((0, 2 + k, 2 + n))
        f.append((1, 2 + n, 2 + k))
    return mk(name, v, f)

def spark_mesh(name="E09_Spark"):
    # petit éclat losange, pointe vers +X
    v = [(0.5, 0, 0), (-0.1, 0, 0), (0.1, 0.07, 0), (0.1, -0.07, 0), (0.1, 0, 0.07), (0.1, 0, -0.07)]
    f = [(0, 2, 4), (0, 4, 3), (0, 3, 5), (0, 5, 2), (1, 4, 2), (1, 3, 4), (1, 5, 3), (1, 2, 5)]
    return mk(name, v, f)

def strip_mesh(name="E09_Strip", length=4.0, w=0.16, h=0.07):
    # ruban plat le long de +X, origine à son début (grandit vers l'avant = onde)
    v = [(0, -w, -h), (length, -w, -h), (length, w, -h), (0, w, -h), (0, -w, h), (length, -w, h), (length, w, h), (0, w, h)]
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return mk(name, v, f)

def ring_mesh(name="E09_Ring", r0=0.86, r1=1.0, h=0.06, seg=24):
    prof = [(r0, -h), (r1, -h), (r1, h), (r0, h)]
    v, f = [], []
    for s_ in range(seg):
        a = 2 * math.pi * s_ / seg
        for r, z in prof:
            v.append((r * math.cos(a), r * math.sin(a), z))
    for s_ in range(seg):
        n = (s_ + 1) % seg
        for k in range(4):
            k2 = (k + 1) % 4
            f.append((s_ * 4 + k, n * 4 + k, n * 4 + k2, s_ * 4 + k2))
    return mk(name, v, f)

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

def add_obj(ctx, name, mesh, mat, loc, keys, az=0.0, el=0.0, jit=0.0, loc_keys=None, tumble=False, drift=0.0, roll=0.0):
    # keys = [(image, échelle ou (sx,sy,sz))] ; az/el = direction ; jit = scintillement angulaire par image ;
    # drift = rotation lente de l'azimut sur la durée (les couleurs "tournent") ; roll = roulis autour de l'axe de la lame
    jr = random.Random(name)
    ob = bpy.data.objects.new(name, mesh)
    if not ob.data.materials:
        ob.data.materials.append(mat)
    ctx.coll.objects.link(ob)
    ob.visible_shadow = False
    wx, wy = ctx.world(loc[0], loc[1])
    ob.location = (wx, wy, loc[2])
    for fr, s in keys:
        sv = s if isinstance(s, tuple) else (s, s, s)
        ob.scale = sv
        ob.keyframe_insert("scale", frame=ctx.t0 + fr)
        if tumble:
            ob.rotation_euler = (jr.uniform(0, 6.28), jr.uniform(0, 6.28), jr.uniform(0, 6.28))
        else:
            vis = max(sv) > 0.01
            ja = jr.uniform(-jit, jit) if vis else 0.0
            je = jr.uniform(-jit * 0.6, jit * 0.6) if vis else 0.0
            jroll = jr.uniform(-jit, jit) if vis else 0.0
            ob.rotation_euler = (math.radians(roll + jroll), -math.radians(el + je), math.radians(az + drift * fr / 12.0 + ja + ctx.arm))
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

def pop(L, start=2, ph=0.0, end=12, wob=0.16):
    # apparition fulgurante avec dépassement, "respiration" par image (déphasée entre lames voisines => les couleurs ondulent),
    # puis extinction progressive (la fin varie d'une lame à l'autre)
    k = [(1, 0.001), (start, 0.6 * L), (start + 1, 1.2 * L), (start + 2, L)]
    for f in range(start + 3, end - 2):
        k.append((f, L * (1 - 0.05 * (f - start)) * (1 + wob * math.sin(f * 1.9 + ph))))
    k += [(end - 2, 0.6 * L), (end - 1, 0.28 * L), (end, 0.001)]
    return k

def fade(S, start, end):
    # extinction douce d'une particule : taille S puis rétrécit progressivement ; scintille légèrement
    k = [(1, 0.001), (start, 1.3 * S)]
    n = max(1, end - start)
    for f in range(start + 1, end):
        k.append((f, S * (1 - 0.8 * (f - start) / n) * (1 + 0.18 * math.sin(f * 2.3))))
    k.append((end, 0.001))
    return k

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        # 1) flash blanc intense, irrégulier, très bref
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 2.3), (3, 1.4), (4, 0.5), (5, 0.001)], az=20, jit=0, drift=0)
        # 2) éclatement de couleurs : éclats qui jaillissent du centre juste après le flash
        for i in range(7):
            az = 360.0 * i / 7 + 12
            ks = [(1, 0.001), (3, 0.001), (4, 1.5), (7, 1.1), (9, 0.5), (11, 0.001)]
            lk = [(fr, (math.cos(math.radians(az)) * d, math.sin(math.radians(az)) * d, 0.5 + 0.18 * (fr - 3))) for fr, d in zip(range(1, 12), [0.2, 0.3, 0.5, 1.4, 2.4, 3.2, 3.8, 4.2, 4.5, 4.7, 4.8])]
            add_obj(ctx, f"{tag}_Burst{i}", M["spark"][i % 7], M["C%d" % (i % 7)], (0, 0, 0.5), ks, az=az, el=18, loc_keys=lk)
        # 3) onde d'énergie circulaire multicolore (deux anneaux décalés) qui part du centre vers les 4 bras
        add_obj(ctx, f"{tag}_RingA", M["ring"], M["RINGA"], (0, 0, 0.12), [(1, 0.001), (2, 0.3), (3, 1.2), (4, 2.0), (5, 2.35), (6, 1.4), (7, 0.001)])
        add_obj(ctx, f"{tag}_RingB", M["ring"], M["RINGB"], (0, 0, 0.14), [(1, 0.001), (3, 0.3), (4, 1.0), (5, 1.8), (6, 2.2), (7, 1.2), (8, 0.001)])
        # 4) éventail de pics courbes : la rotation lente de l'azimut + respiration déphasée font onduler les couleurs
        n = 12
        for i in range(n):
            az = 360.0 * i / n
            el = 30 + 22 * (i % 3)
            ln = 2.5 + 0.55 * (i % 2)
            add_obj(ctx, f"{tag}_Blade{i}", M["blade"][i % 7], M["C%d" % (i % 7)], (0.15 * math.cos(math.radians(az)), 0.15 * math.sin(math.radians(az)), 0.3),
                    pop(ln, 3 + (i % 2), ph=i * 1.1, end=10 + (i % 3)), az=az, el=el, jit=10, drift=28, roll=(i * 55) % 360)
        for i in range(3):  # nuages colorés au pied
            a = math.radians(60 + 120 * i)
            add_obj(ctx, f"{tag}_Puff{i}", M["puffs"][i % 3], M["PUFF%d" % (i % 3)], (1.3 * math.cos(a), 1.3 * math.sin(a), 0.35),
                    [(1, 0.001), (3, 0.9), (8, 0.9), (10, 0.5), (12, 0.001)])
        nconf, nstar, nspark = 6, 6, 0
    elif kind == "segment":
        # onde multicolore : rubans qui courent le long du bras et relient les cases
        for k, ci in enumerate((1, 3, 5)):
            yy = (-0.55, 0.0, 0.55)[k]
            add_obj(ctx, f"{tag}_Wave{k}", M["strip"][ci], M["C%d" % ci], (-2.0, yy, 0.12),
                    [(1, (0.001, 1, 1)), (2 + k * 0, (0.35, 1, 1)), (3, (1.0, 1, 1)), (6, (1.0, 1, 1)), (8, (1.0, 0.5, 0.5)), (10, (1.0, 0.001, 0.001))])
        for i, (az, el, ln) in enumerate([(-40, 38, 1.9), (-18, 52, 2.2), (0, 62, 2.5), (18, 52, 2.2), (40, 38, 1.9)]):
            add_obj(ctx, f"{tag}_Blade{i}", M["blade"][(i + 1) % 7], M["C%d" % ((i + 1) % 7)], (0, 0, 0.3), pop(ln, 3, ph=i * 1.3, end=10 + (i % 3)), az=az, el=el, jit=10, drift=14 * (1 if i % 2 else -1), roll=i * 70)
        add_obj(ctx, f"{tag}_Puff0", M["puffs"][1], M["PUFF1"], (0, 0, 0.3), [(1, 0.001), (4, 0.9), (8, 0.9), (11, 0.001)])
        nconf, nstar, nspark = 2, 2, 2
    else:
        for k, ci in enumerate((0, 4, 6)):
            yy = (-0.55, 0.0, 0.55)[k]
            add_obj(ctx, f"{tag}_Wave{k}", M["strip"][ci], M["C%d" % ci], (-2.0, yy, 0.12),
                    [(1, (0.001, 1, 1)), (3, (0.3, 1, 1)), (4, (0.75, 1, 1)), (6, (0.75, 1, 1)), (8, (0.75, 0.5, 0.5)), (10, (0.75, 0.001, 0.001))])
        for i, (az, el, ln) in enumerate([(-35, 36, 1.7), (-12, 52, 2.1), (12, 52, 2.1), (35, 36, 1.7), (0, 70, 2.4)]):
            add_obj(ctx, f"{tag}_Blade{i}", M["blade"][(i + 3) % 7], M["C%d" % ((i + 3) % 7)], (0, 0, 0.3), pop(ln, 4, ph=i * 1.5, end=10 + (i % 3)), az=az, el=el, jit=10, drift=14 * (1 if i % 2 else -1), roll=i * 70)
        add_obj(ctx, f"{tag}_Puff0", M["puffs"][2], M["PUFF2"], (0, 0, 0.3), [(1, 0.001), (5, 0.9), (8, 0.9), (11, 0.001)])
        nconf, nstar, nspark = 3, 2, 3
    for n in range(nstar):  # étoiles qui retombent en scintillant, extinction étalée
        ang = r.uniform(0, 6.28) if kind == "center" else r.uniform(-0.7, 0.7)
        sp, vz = r.uniform(3.0, 6.0), r.uniform(5.0, 9.0)
        add_obj(ctx, f"{tag}_Star{n}", M["star"][(n * 2 + 1) % 7], M["C%d" % ((n * 2 + 1) % 7)], (0, 0, 0.7), fade(1.0 + 0.3 * (n % 2), 3, 9 + n % 4),
                loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.7), tumble=True)
    for n in range(nspark):  # étincelles : petits éclats rapides dans le sens du bras
        ang = r.uniform(-0.5, 0.5)
        sp, vz = r.uniform(5.0, 8.0), r.uniform(2.0, 5.0)
        add_obj(ctx, f"{tag}_Spark{n}", M["spark"][(n * 3 + 2) % 7], M["C%d" % ((n * 3 + 2) % 7)], (0, 0, 0.5), fade(0.9, 2, 7 + n),
                loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.5, g=20.0), az=math.degrees(ang), el=20)
    for n in range(nconf):  # confettis colorés projetés, qui tournent ; ils s'éteignent un à un
        ang = r.uniform(0, 6.28) if kind == "center" else r.uniform(-0.6, 0.6)
        sp, vz = r.uniform(4.0, 8.0), r.uniform(4.0, 8.0)
        add_obj(ctx, f"{tag}_Confetti{n}", M["confetti"][(n * 3) % 7], M["C%d" % ((n * 3) % 7)], (0, 0, 0.6), fade(1.0, 2, 9 + (n % 4)),
                loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.6), tumble=True)

def build():
    M = {"C%d" % i: make_neon("C%d" % i, hx) for i, hx in enumerate(RAINBOW)}
    M["FLASH"] = make_neon("FLASH", "#FFFFFF")
    M["RINGA"] = make_neon("RINGA", RING_A)
    M["RINGB"] = make_neon("RINGB", RING_B)
    for i, hx in enumerate(PUFF):
        M["PUFF%d" % i] = make_puff("PUFF%d" % i, hx)
    M["blade"] = [blade_mesh("E09_Blade%d" % i) for i in range(7)]
    M["confetti"] = [confetti_mesh("E09_Confetti%d" % i) for i in range(7)]
    M["puffs"] = [blob_mesh("E09_Puff%d" % i, 0.75, 0.6, 0.18, 21 + i, 1) for i in range(3)]
    M["flash"] = blob_mesh("E09_Flash", 0.7, 0.85, 0.5, 33, 2)
    M["star"] = [star_mesh("E09_Star%d" % i) for i in range(7)]
    M["spark"] = [spark_mesh("E09_Spark%d" % i) for i in range(7)]
    M["strip"] = [strip_mesh("E09_Strip%d" % i) for i in range(7)]
    M["ring"] = ring_mesh("E09_Ring")
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
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E09_ArcEnCiel_v2.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E09")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11)), ("CAM_Game", (4, 8))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v2_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E09_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
