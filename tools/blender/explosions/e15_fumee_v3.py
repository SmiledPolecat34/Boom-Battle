"""E15 Fumee V3 (reference : Explosions_32.png, rangee 2, carte Fumee) : detonation seche (flash + onde de pression) puis gros nuage de fumee organique.
Centre dense et sombre (opaque), branches translucides, suie/poussiere plutot que rochers. Briques CENTER / SEGMENT / END (4 directions).
Pilotage (Blender, E01_Classique_v2.blend ouvert) : E15_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Ecrit E15_Fumee_v3.blend a cote ; E01_Classique_v2.blend n'est jamais ecrase.
"""
import bpy, math, os, random

FLAME = ["#FF7A18", "#FFD23B", "#FF4A12"]  # lave orange, jaune, rouge-orangé
ROCK = ["#3B2B26", "#5A4034", "#2A1E1A"]  # roche sombre, roche claire, très sombre
RAINBOW = FLAME
PUFF = ROCK
RING_A, RING_B = "#FFC53D", "#FF7A18"
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

def strip_mesh(name="E09_Strip", length=4.0, phase=0.0, n=9, amp=0.22):
    # ruban plat ONDULANT (sinusoïde en Y), largeur et épaisseur qui varient le long du ruban ; origine à son début (grandit vers l'avant)
    v, f = [], []
    for i in range(n + 1):
        t = i / n
        x = length * t
        y = amp * math.sin(t * 7.0 + phase)
        w = 0.10 + 0.10 * (0.5 + 0.5 * math.sin(t * 9.0 + phase * 1.7)) * (1.0 - 0.4 * t)
        h = 0.045 + 0.035 * (0.5 + 0.5 * math.sin(t * 9.0 + phase * 1.7))
        v += [(x, y - w, -h), (x, y + w, -h), (x, y + w, h), (x, y - w, h)]
    for i in range(n):
        a_, b_ = 4 * i, 4 * (i + 1)
        for k in range(4):
            k2 = (k + 1) % 4
            f.append((a_ + k, b_ + k, b_ + k2, a_ + k2))
    f.append((0, 3, 2, 1))
    f.append((4 * n, 4 * n + 1, 4 * n + 2, 4 * n + 3))
    return mk(name, v, f)

def ring_mesh(name="E09_Ring", r0=0.95, r1=1.0, h=0.04, seg=20):
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

WHITE, LGREY, MGREY, DGREY = "#F4F5FB", "#D3D6E3", "#9AA1BA", "#555B75"

def make_cloud(key, hx, emi=0.14, alpha=1.0):
    # alpha < 1 : matériau translucide (copie de E01_Smoke) ; l'exporteur lit Alpha du Principled -> Transparency Roblox = 1 - alpha
    if alpha >= 0.999:
        m = bpy.data.materials.new("E09_" + key)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = hex_lin(hx)
        b.inputs["Roughness"].default_value = 0.95
        b.inputs["Emission Color"].default_value = hex_lin(hx)
        b.inputs["Emission Strength"].default_value = emi
        return m
    m = bpy.data.materials["E01_Smoke"].copy()
    m.name = "E09_" + key
    set_color(m, hx)
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Alpha"].default_value = alpha
            n.inputs["Roughness"].default_value = 0.95
            if "Emission Strength" in n.inputs:
                n.inputs["Emission Strength"].default_value = emi
    return m

def make_rock(key, hx):
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.85
    return m

def cloud_mesh(name, seed, lobes=4, spread=0.5, body=(1.1, 0.95, 0.8)):
    # nuage ORGANIQUE : un corps (icosphère 3 : 320 tri) irrégulier + quelques lobes (80 tri) fusionnés en UN maillage, ombrage lisse,
    # déformé par un bruit basse fréquence (plus de sphères reconnaissables). Base posée sur z=0.
    import bmesh
    from mathutils import Matrix, Vector
    r = random.Random(seed)
    bm = bmesh.new()
    for i in range(lobes):
        if i == 0:
            rad, sub, pos, sc = 0.62, 3, (0.0, 0.0, 0.0), body
        else:
            ang = 2 * math.pi * (i - 1) / (lobes - 1) + r.uniform(-0.5, 0.5)
            d = spread * r.uniform(0.55, 1.0)
            rad, sub = r.uniform(0.3, 0.46), 2
            pos = (d * math.cos(ang), d * math.sin(ang) * 0.9, r.uniform(0.0, 0.35))
            sc = (r.uniform(0.9, 1.3), r.uniform(0.8, 1.15), r.uniform(0.7, 1.0))
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=rad, matrix=Matrix.Translation(pos) @ Matrix.Diagonal(Vector((sc[0], sc[1], sc[2], 1.0))))
    ph = [r.uniform(0, 6.28) for _ in range(3)]
    for v in bm.verts:
        x, y, z = v.co
        f = 1 + 0.14 * math.sin(3.1 * x + ph[0] + 2.0 * y) * math.cos(2.7 * z + ph[1] + 1.5 * y) + 0.07 * math.sin(5.3 * (x + z) + ph[2])
        v.co = Vector((x * f, y * f, z * f))
    zmin = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= zmin
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return me

def sc3(v):
    return v if isinstance(v, tuple) else (v, v, v)

def cloud(ctx, name, mesh, mat, keys, locks, az=None, drift=12.0):
    a = random.Random(name).uniform(0, 360) if az is None else az
    return add_obj(ctx, name, mesh, mat, locks[0][1], [(f, sc3(v)) for f, v in keys], az=a, drift=drift, loc_keys=locks)

def lerp_path(p0, p1, frames, ease=1.0):
    n = len(frames) - 1
    return [(f, tuple(p0[j] + (p1[j] - p0[j]) * ((i / n) ** (1.0 / ease) if n else 1.0) for j in range(3))) for i, f in enumerate(frames)]

def track(p0, p1, f0, f1, ease=1.5):
    return lerp_path(p0, p1, list(range(f0, f1 + 1)), ease)

def life(t0, S, hold, out, ax=(1.0, 1.0, 1.0), ph=0.0, peak=1.2, wob=0.1, end=(1.35, 0.85, 0.45)):
    # vie d'un nuage, UNE clé par image : gonfle d'un coup (petit/écrasé -> dépassement -> stabilisation), "respire" (déformation par axe),
    # puis se dissipe : s'étire (end = proportions finales selon l'axe du bras, aplatit), rétrécit progressivement jusqu'à disparaître.
    def sv(k, f, e=(1, 1, 1)):
        return tuple(S * ax[j] * k * e[j] * (1 + wob * math.sin(f * (1.7, 2.1, 1.9)[j] + ph + j * 1.3)) for j in range(3))
    keys = [(1, 0.001)]
    if t0 - 1 > 1:
        keys.append((t0 - 1, 0.001))
    keys += [(t0, sv(0.4, t0, (1, 1, 0.6))), (t0 + 1, sv(peak, t0 + 1)), (t0 + 2, sv(1.0, t0 + 2))]
    for i in range(1, hold + 1):
        keys.append((t0 + 2 + i, sv(1.0 + 0.04 * i, t0 + 2 + i)))
    f1 = t0 + 2 + hold
    for i in range(1, out):
        u = i / out
        e = tuple(1 + (end[j] - 1) * u for j in range(3))
        keys.append((f1 + i, sv((1 + 0.04 * hold) * (1 - u) ** 0.8, f1 + i, e)))
    keys.append((f1 + out, 0.001))
    return keys

def fade(S, start, end):
    k = [(1, 0.001), (start, 1.3 * S)]
    n = max(1, end - start)
    for f in range(start + 1, end):
        k.append((f, S * (1 - 0.8 * (f - start) / n) * (1 + 0.18 * math.sin(f * 2.3))))
    k.append((end, 0.001))
    return k

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    C = M["cloud"]
    if kind == "center":
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 1.7), (3, 0.5), (4, 0.001)], az=20)
        # onde de pression : deux anneaux plats translucides très brefs qui s'élargissent à ras du sol
        add_obj(ctx, f"{tag}_Ring0", M["ring"], M["RINGM"], (0, 0, 0.25),
                [(1, 0.001), (2, (1.2, 1.2, 1.0)), (3, (3.0, 3.0, 1.0)), (4, (4.6, 4.6, 0.8)), (5, (5.6, 5.6, 0.5)), (6, (6.0, 6.0, 0.2)), (7, 0.001)])
        add_obj(ctx, f"{tag}_Ring1", M["ring"], M["RINGM"], (0, 0, 0.25),
                [(1, 0.001), (2, 0.001), (3, (1.0, 1.0, 1.0)), (4, (2.6, 2.6, 1.0)), (5, (3.8, 3.8, 0.7)), (6, (4.4, 4.4, 0.3)), (7, 0.001)])
        # coeur dense et sombre (opaque) : gonfle brutalement, deux lobes sombres déphasés pour casser la forme sphérique
        cloud(ctx, f"{tag}_CloudCore", C["D0"], M["CLOUDD"], life(2, 1.45, 4, 6, ax=(1, 1, 1.2), peak=1.35, wob=0.08, end=(1.3, 1.25, 0.6)),
              [(2, (0, 0, 0.0)), (5, (0, 0, 0.5)), (14, (0, 0, 1.0))], az=20)
        cloud(ctx, f"{tag}_CloudCore2", C["D1"], M["CLOUDD"], life(3, 0.9, 3, 5, ph=2.0, peak=1.3, end=(1.4, 1.2, 0.5)),
              [(3, (0.35, -0.25, 0.2)), (13, (0.5, -0.4, 1.0))], az=140)
        # nuages translucides expulsés (expansion rapide puis ralentissement), allongés dans le sens du souffle
        for i, (ang, mi, mat, S2) in enumerate([(25, "M0", "CLOUDM", 1.05), (150, "M0", "CLOUDM", 0.95), (265, "G0", "CLOUDG", 1.0), (335, "G0", "CLOUDG", 0.85)]):
            a = math.radians(ang)
            cloud(ctx, f"{tag}_CloudOut{i}", C[mi], M[mat], life(2, S2, 3, 5, ax=(1.15, 0.9, 0.85), ph=i * 1.1, end=(1.3, 0.85, 0.5)),
                  track((0.1 * math.cos(a), 0.1 * math.sin(a), 0.0), (2.0 * math.cos(a), 2.0 * math.sin(a), 0.5), 2, 12, 2.2), az=ang)
        # volutes claires qui montent au-dessus du coeur (plus basses qu'en V2)
        for i, (z0, z1, S3, mi, t) in enumerate([(0.9, 1.9, 1.05, "W0", 3), (1.6, 2.6, 0.8, "W1", 4)]):
            cloud(ctx, f"{tag}_CloudTop{i}", C[mi], M["CLOUDW"], life(t, S3, 3, 5, ph=i * 2.2, end=(1.3, 1.3, 0.5)),
                  track((0.05, 0.0, z0), (0.2, 0.0, z1), t, t + 10, 1.2))
        # poussière rasante le long de la croix
        for i, d in enumerate([0, 90, 180, 270]):
            a = math.radians(d)
            cloud(ctx, f"{tag}_Roll{i}", C["G1"], M["CLOUDG"], life(2, 0.8, 2, 4, ax=(1.25, 0.9, 0.55), ph=i * 1.5, peak=1.15, end=(1.3, 0.9, 0.35)),
                  track((0.6 * math.cos(a), 0.6 * math.sin(a), 0.0), (2.8 * math.cos(a), 2.8 * math.sin(a), 0.0), 2, 10, 1.8), az=d)
        # débris : 1 seul petit rocher sombre + 1 éclat gris ; le reste = suie et poussière
        ang = r.uniform(0, 6.28)
        add_obj(ctx, f"{tag}_Rubble0", M["rubD"], M["RUBD"], (0, 0, 0.8), fade(0.6, 3, 10),
                loc_keys=ballistic((5.0 * math.cos(ang), 5.0 * math.sin(ang), 6.0), 0.8, steps=14, g=18.0), az=math.degrees(ang), el=30, tumble=True)
        ang = r.uniform(0, 6.28)
        add_obj(ctx, f"{tag}_Chip0", M["chip"], M["CHIP"], (0, 0, 0.8), fade(0.7, 3, 10),
                loc_keys=ballistic((4.0 * math.cos(ang), 4.0 * math.sin(ang), 5.0), 0.8, steps=14, g=16.0), az=math.degrees(ang), el=30, tumble=True)
        for i in range(5):
            ang = r.uniform(0, 6.28)
            sp, vz = r.uniform(2.0, 5.0), r.uniform(3.0, 7.0)
            add_obj(ctx, f"{tag}_Soot{i}", M["soot"], M["SOOT"], (0, 0, 0.9), fade(1.0, 3 + i % 2, 12 + i % 3),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.9, steps=14, g=9.0))
        for i in range(4):
            a = math.radians(30 + 90 * i)
            add_obj(ctx, f"{tag}_Dust{i}", M["dust"], M["DUSTM"], (0.8 * math.cos(a), 0.8 * math.sin(a), 0.6), [(1, 0.001), (3, 0.001), (4, 0.8), (9, 0.7), (13, 0.001)],
                    loc_keys=[(3, (0.8 * math.cos(a), 0.8 * math.sin(a), 0.6)), (13, (2.6 * math.cos(a), 2.6 * math.sin(a), 2.0))])
    else:
        t = 2 if kind == "segment" else 3
        big = 1.0 if kind == "segment" else 1.2
        # onde de fumée : nuage bas et allongé qui glisse vers l'extrémité, suivi de 3 nuages décalés qui s'étirent dans le sens du bras
        cloud(ctx, f"{tag}_Wave", C["G1"], M["CLOUDG"], life(t, 0.9 * big, 2, 4, ax=(1.3, 0.95, 0.55), peak=1.15, end=(1.35, 0.9, 0.4)),
              track((-2.0, 0.0, 0.0), (1.4, 0.0, 0.1), t, t + 8, 1.6), az=0)
        for i, (y, mi, mat, S4, dt, az) in enumerate([(0.55, "M0", "CLOUDM", 0.85, 1, -20), (-0.5, "W0", "CLOUDW", 0.8, 2, 15), (0.0, "G0", "CLOUDG", 0.7, 3, 35)]):
            t1 = t + dt
            cloud(ctx, f"{tag}_Cloud{i}", C[mi], M[mat], life(t1, S4 * big, 2, 4, ax=(1.15, 0.95, 0.9), ph=i * 1.9, end=(1.25, 0.95, 0.6)),
                  track((-1.8, y, 0.0), (1.2, y, 0.9), t1, t1 + 8, 1.4), az=az)
        add_obj(ctx, f"{tag}_Soot0", M["soot"], M["SOOT"], (0, 0, 0.5), fade(0.9, t, t + 9),
                loc_keys=ballistic((r.uniform(2.5, 4.5), r.uniform(-1.5, 1.5), r.uniform(3.0, 5.0)), 0.5, steps=12, g=9.0))
        if kind == "end":
            cloud(ctx, f"{tag}_CloudEnd", C["W1"], M["CLOUDW"], life(t + 1, 1.1, 2, 5, ax=(1, 1, 1.1), ph=0.7, end=(1.3, 1.3, 0.55)),
                  [(t + 1, (0.4, 0.0, 0.0)), (t + 10, (0.9, 0.0, 1.1))], az=30)
        add_obj(ctx, f"{tag}_Dust0", M["dust"], M["DUSTM"], (0, 0, 0.8), [(1, 0.001), (t + 2, 0.001), (t + 3, 0.7), (t + 7, 0.6), (t + 9, 0.001)],
                loc_keys=[(t + 2, (-0.5, 0.0, 0.8)), (t + 9, (0.8, 0.0, 2.0))])

def build():
    M = {"CLOUDW": make_cloud("CLOUDW", WHITE, 0.14, 0.62), "CLOUDG": make_cloud("CLOUDG", LGREY, 0.14, 0.60),
         "CLOUDM": make_cloud("CLOUDM", MGREY, 0.12, 0.66), "CLOUDD": make_cloud("CLOUDD", DGREY, 0.1)}
    M["RINGM"] = make_cloud("RINGM", "#F0F2FA", 0.6, 0.3)
    M["FLASH"] = make_neon("FLASH", "#F4F6FF")
    M["RUBD"] = make_rock("RUBD", "#2A2D3A")
    M["CHIP"] = make_rock("CHIP", "#8A90A8")
    M["SOOT"] = make_rock("SOOT", "#30344A")
    M["DUSTM"] = make_cloud("DUSTM", "#E8EAF4", 0.25)
    M["cloud"] = {"W0": cloud_mesh("E15_CloudW0", 1, 4), "W1": cloud_mesh("E15_CloudW1", 2, 3), "G0": cloud_mesh("E15_CloudG0", 4, 3, 0.45),
                  "G1": cloud_mesh("E15_CloudG1", 7, 3, 0.55, (1.25, 0.9, 0.7)), "M0": cloud_mesh("E15_CloudM0", 3, 4),
                  "D0": cloud_mesh("E15_CloudD0", 5, 4, 0.5), "D1": cloud_mesh("E15_CloudD1", 9, 3, 0.4)}
    M["ring"] = ring_mesh("E15_Ring", 0.93, 1.0, 0.08, 24)
    M["rubD"] = blob_mesh("E15_RubD", 0.45, 0.7, 0.35, 61, 1)
    M["chip"] = blob_mesh("E15_Chip", 0.28, 0.7, 0.3, 71, 1)
    M["soot"] = blob_mesh("E15_Soot", 0.22, 0.8, 0.25, 81, 1)
    M["dust"] = blob_mesh("E15_Dust", 0.22, 0.8, 0.2, 91, 1)
    M["flash"] = blob_mesh("E15_Flash", 0.7, 0.85, 0.5, 33, 2)
    for cn in ["E01_CENTER"] + ["E01_SEG1_" + d for d in ARMS] + ["E01_END_" + d for d in ARMS]:
        for o in list(bpy.data.collections[cn].objects):
            bpy.data.objects.remove(o)
    COUNTS.clear()
    build_brick(Ctx(bpy.data.collections["E01_CENTER"], "E", 0.0, 0), "center", M)
    for d in ARMS:
        build_brick(Ctx(bpy.data.collections["E01_SEG1_" + d], d, CELL, 1), "segment", M)
        build_brick(Ctx(bpy.data.collections["E01_END_" + d], d, 2 * CELL, 2), "end", M)
    bpy.context.scene.frame_end = 20
    def alpha_of(o):
        for n in o.data.materials[0].node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                return n.inputs["Alpha"].default_value
        return 1.0
    for cn in ("E01_CENTER", "E01_SEG1_E", "E01_END_E"):
        ms = [o for o in bpy.data.collections[cn].objects if o.type == "MESH"]
        print(cn, "objets", len(ms), "translucides", len([o for o in ms if alpha_of(o) < 0.99]))
    print("triangles/maillage :", {k: len(m.polygons) for k, m in M["cloud"].items()})
    for k in ("CLOUDW", "RINGM"):
        print(k, [n.type for n in M[k].node_tree.nodes])
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E15_Fumee")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E15_Fumee_v3.blend"))

def render():
    from mathutils import Vector
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E15")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    if "CAM_Far" not in bpy.data.objects:
        src = bpy.data.objects["CAM_Game"]
        cam = src.copy()
        cam.data = src.data.copy()
        cam.name = "CAM_Far"
        sc.collection.objects.link(cam)
        fwd = src.matrix_world.to_quaternion() @ Vector((0, 0, -1))
        cam.location = src.matrix_world.translation - fwd * 30
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11, 13)), ("CAM_Game", (5, 9)), ("CAM_Far", (4, 7, 10, 13))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v3_%s_f%02d.png" % ({"CAM_Game": "game", "CAM_Far": "far"}.get(cam, "close"), f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E15_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
