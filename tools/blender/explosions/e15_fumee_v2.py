"""E15 Fumee (base e09..e14) (référence : Explosions_32.png, rangée 2, 1re carte) : gerbe de lames aux 7 couleurs de l'arc-en-ciel autour d'un cœur blanc, flash bref,
confettis colorés projetés, petits nuages violets / roses / bleus au pied. Lecture en croix conservée (lames dans le sens des bras).
Briques composables (CENTER, SEGMENT, END ; 4 directions). Pilotage (Blender, E01_Classique_v2.blend ouvert) :
    E09_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Écrit E09_ArcEnCiel_v3.blend à côté ; E01_Classique_v2.blend n'est jamais écrasé.
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

def make_cloud(key, hx, emi=0.14):
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.95
    b.inputs["Emission Color"].default_value = hex_lin(hx)
    b.inputs["Emission Strength"].default_value = emi
    return m

def make_rock(key, hx):
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.85
    return m

def cloud_mesh(name, seed, n=6, spread=0.55):
    # nuage « chou-fleur » cartoon : plusieurs sphères basse définition fusionnées en UN seul maillage, posé sur le sol (z=0 en bas), rayon ~1
    import bmesh
    from mathutils import Matrix
    r = random.Random(seed)
    bm = bmesh.new()
    for i in range(n):
        ang = 2 * math.pi * i / n + r.uniform(-0.4, 0.4)
        d = spread * r.uniform(0.5, 1.0) if i else 0.0
        rad = r.uniform(0.42, 0.6) if i else 0.62
        z = rad * 0.7 + (0.0 if i == 0 else r.uniform(0.0, 0.45))
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=rad, matrix=Matrix.Translation((d * math.cos(ang), d * math.sin(ang), z)))
    zmin = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z = max(v.co.z - zmin, 0.0)
        v.co.x += r.uniform(-0.03, 0.03)
        v.co.y += r.uniform(-0.03, 0.03)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    return me

def sc3(v):
    return v if isinstance(v, tuple) else (v, v, v)

def cloud(ctx, name, mesh, mat, keys, locks, drift=25.0):
    # nuage à échelle NON uniforme (gonfle, s'étire, s'aplatit) : keys = [(image, échelle ou (sx,sy,sz))], locks = [(image, (x,y,z))]
    return add_obj(ctx, name, mesh, mat, locks[0][1], [(f, sc3(v)) for f, v in keys], az=random.Random(name).uniform(0, 360), drift=drift, loc_keys=locks)

def lerp_path(p0, p1, frames, ease=1.0):
    # positions de p0 à p1 sur `frames` (liste d'images) avec ralentissement (ease>1 : démarre vite, ralentit)
    n = len(frames) - 1
    out = []
    for i, f in enumerate(frames):
        u = (i / n) ** (1.0 / ease) if n else 1.0
        out.append((f, tuple(p0[j] + (p1[j] - p0[j]) * u for j in range(3))))
    return out

def dissolve(S, f0, f1, flat=0.55, stretch=1.25):
    # dissipation : le nuage se déforme (s'étale et s'aplatit), rétrécit, puis disparaît (tous les axes)
    return [(f0, (S, S, S)), ((f0 + f1) // 2, (S * stretch, S * 0.85, S * flat)), (f1 - 1, (S * 0.55, S * 0.45, S * 0.2)), (f1, 0.001)]

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 1.7), (3, 0.5), (4, 0.001)], az=20)
        # 1) le coeur sombre de la fumée gonfle brutalement : écrasé puis étiré vers le haut, dépasse, se stabilise puis s'étale en se dissipant
        S = 1.65
        cloud(ctx, f"{tag}_CloudCore", M["cloud"][4], M["CLOUDD"],
              [(1, 0.001), (2, (0.55 * S, 0.55 * S, 0.3 * S)), (3, (1.3 * S, 1.3 * S, 0.95 * S)), (4, (1.1 * S, 1.1 * S, 1.3 * S)), (6, (1.18 * S, 1.18 * S, 1.1 * S)), (8, (1.1 * S, 1.1 * S, 0.95 * S))] + dissolve(1.05 * S, 9, 14)[1:],
              [(2, (0, 0, 0.0)), (4, (0, 0, 0.3)), (14, (0, 0, 0.9))])
        # 2) nuages moyens/clairs expulsés du centre vers l'extérieur (expansion rapide puis ralentissement)
        for i, (ang, mi, mat, S2) in enumerate([(25, 3, "CLOUDM", 1.15), (150, 3, "CLOUDM", 1.0), (265, 2, "CLOUDG", 1.05), (335, 2, "CLOUDG", 0.9)]):
            a = math.radians(ang)
            p1 = (1.9 * math.cos(a), 1.9 * math.sin(a), 0.1)
            cloud(ctx, f"{tag}_CloudOut{i}", M["cloud"][mi], M[mat],
                  [(1, 0.001), (2, 0.35 * S2), (3, 1.15 * S2), (5, S2), (8, 1.05 * S2)] + dissolve(1.05 * S2, 9, 13)[1:],
                  lerp_path((0.1 * math.cos(a), 0.1 * math.sin(a), 0.0), p1, [2, 3, 4, 5, 6], ease=2.2) + [(13, (p1[0] * 1.15, p1[1] * 1.15, 0.8))])
        # 3) colonne claire qui monte et gonfle au-dessus du coeur
        for i, (z0, z1, S3, mi, mat, t) in enumerate([(1.0, 2.0, 1.3, 0, "CLOUDW", 3), (1.9, 3.1, 0.95, 1, "CLOUDW", 4)]):
            cloud(ctx, f"{tag}_CloudTop{i}", M["cloud"][mi], M[mat],
                  [(1, 0.001), (t, 0.35 * S3), (t + 1, 1.15 * S3), (t + 3, S3), (9, 1.08 * S3)] + dissolve(1.08 * S3, 10, 14)[1:],
                  [(t, (0, 0, z0)), (14, (0, 0, z1 + 0.8))])
        # 4) onde de poussière au ras du sol le long de la croix
        for i, d in enumerate([0, 90, 180, 270]):
            a = math.radians(d)
            p1 = (2.8 * math.cos(a), 2.8 * math.sin(a), 0.0)
            cloud(ctx, f"{tag}_Roll{i}", M["cloud"][2], M["CLOUDG"],
                  [(1, 0.001), (2, (0.4, 0.4, 0.25)), (3, (1.0, 0.7, 0.45)), (6, (0.9, 0.7, 0.4)), (9, 0.001)],
                  lerp_path((0.6 * math.cos(a), 0.6 * math.sin(a), 0.0), p1, [2, 3, 4, 5, 6, 7, 8, 9], ease=1.8))
        # 5) moins de gros rochers : 2 débris sombres + 3 petits éclats gris, suie, poussière
        for i in range(2):
            ang = r.uniform(0, 6.28)
            sp, vz = r.uniform(4.0, 7.0), r.uniform(5.0, 8.0)
            add_obj(ctx, f"{tag}_Rubble{i}", M["rubD"][i], M["RUBD"], (0, 0, 0.8), fade(0.8, 3, 11 + i),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.8, steps=14, g=18.0), az=math.degrees(ang), el=30, tumble=True)
        for i in range(3):
            ang = r.uniform(0, 6.28)
            sp, vz = r.uniform(3.0, 6.0), r.uniform(4.0, 7.0)
            add_obj(ctx, f"{tag}_Chip{i}", M["chip"], M["CHIP"], (0, 0, 0.8), fade(0.8, 3, 10 + i),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.8, steps=14, g=16.0), az=math.degrees(ang), el=30, tumble=True)
        for i in range(5):
            ang = r.uniform(0, 6.28)
            sp, vz = r.uniform(2.0, 5.0), r.uniform(3.0, 7.0)
            add_obj(ctx, f"{tag}_Soot{i}", M["soot"], M["SOOT"], (0, 0, 0.9), fade(0.8, 3 + i % 2, 12 + i % 3),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.9, steps=14, g=9.0))
        for i in range(4):
            a = math.radians(30 + 90 * i)
            add_obj(ctx, f"{tag}_Dust{i}", M["dust"], M["DUSTM"], (0.8 * math.cos(a), 0.8 * math.sin(a), 0.6), [(1, 0.001), (3, 0.001), (4, 0.8), (9, 0.7), (13, 0.001)],
                    loc_keys=[(3, (0.8 * math.cos(a), 0.8 * math.sin(a), 0.6)), (13, (2.6 * math.cos(a), 2.6 * math.sin(a), 2.0))])
    else:
        t = 2 if kind == "segment" else 3
        big = 1.0 if kind == "segment" else 1.2
        # onde de fumée qui se propage sur la case : un nuage bas et allongé glisse vers l'extrémité en se gonflant, des nuages plus hauts le suivent
        cloud(ctx, f"{tag}_Wave", M["cloud"][2], M["CLOUDG"],
              [(1, 0.001), (t, (0.5 * big, 0.35 * big, 0.25 * big)), (t + 1, (1.5 * big, 0.9 * big, 0.5 * big)), (t + 4, (1.3 * big, 1.0 * big, 0.6 * big)), (t + 6, (0.9 * big, 0.7 * big, 0.35 * big)), (t + 7, 0.001)],
              lerp_path((-2.0, 0.0, 0.0), (1.4, 0.0, 0.0), [t, t + 1, t + 2, t + 3, t + 4, t + 5, t + 6, t + 7], ease=1.6))
        for i, (y, mi, mat, S4, dt) in enumerate([(0.55, 3, "CLOUDM", 0.85, 1), (-0.5, 0, "CLOUDW", 0.75, 2), (0.0, 2, "CLOUDG", 0.65, 3)]):
            t1 = t + dt
            p0, p1 = (-1.8, y, 0.0), (1.2, y, 0.9)
            cloud(ctx, f"{tag}_Cloud{i}", M["cloud"][mi], M[mat],
                  [(1, 0.001), (t1, (0.5 * S4 * big, 0.3 * S4 * big, 0.25 * S4 * big)), (t1 + 1, (1.25 * S4 * big, 0.9 * S4 * big, 0.9 * S4 * big)), (t1 + 3, S4 * big)] + dissolve(S4 * big, t1 + 4, t1 + 8)[1:],
                  lerp_path(p0, p1, [t1, t1 + 1, t1 + 2, t1 + 3, t1 + 4, t1 + 5, t1 + 6, t1 + 7, t1 + 8], ease=1.4))
        for i in range(2):
            add_obj(ctx, f"{tag}_Soot{i}", M["soot"], M["SOOT"], (0, 0, 0.5), fade(0.7, t, t + 8 + i),
                    loc_keys=ballistic((r.uniform(2.5, 4.5), r.uniform(-1.5, 1.5), r.uniform(3.0, 5.0)), 0.5, steps=12, g=9.0))
        if kind == "end":
            cloud(ctx, f"{tag}_CloudEnd", M["cloud"][1], M["CLOUDW"],
                  [(1, 0.001), (t + 1, (0.5, 0.4, 0.3)), (t + 2, (1.3, 1.1, 1.0)), (t + 4, 1.1)] + dissolve(1.1, t + 5, t + 10)[1:],
                  [(t + 1, (0.4, 0.0, 0.0)), (t + 10, (0.9, 0.0, 1.1))])
            add_obj(ctx, f"{tag}_Chip0", M["chip"], M["CHIP"], (0.5, 0.3, 0.2), [(1, 0.001), (t + 1, 0.8), (t + 6, 0.8), (t + 8, 0.001)])
        add_obj(ctx, f"{tag}_Dust0", M["dust"], M["DUSTM"], (0, 0, 0.8), [(1, 0.001), (t + 2, 0.001), (t + 3, 0.7), (t + 7, 0.6), (t + 9, 0.001)],
                loc_keys=[(t + 2, (-0.5, 0.0, 0.8)), (t + 9, (0.8, 0.0, 2.0))])

def build():
    M = {"CLOUDW": make_cloud("CLOUDW", WHITE), "CLOUDG": make_cloud("CLOUDG", LGREY), "CLOUDM": make_cloud("CLOUDM", MGREY, 0.12), "CLOUDD": make_cloud("CLOUDD", DGREY, 0.1)}
    M["FLASH"] = make_neon("FLASH", "#F4F6FF")
    M["RUBD"] = make_rock("RUBD", "#2A2D3A")
    M["CHIP"] = make_rock("CHIP", "#8A90A8")
    M["SOOT"] = make_rock("SOOT", "#30344A")
    M["DUSTM"] = make_cloud("DUSTM", "#E8EAF4", 0.25)
    M["cloud"] = [cloud_mesh("E15_CloudW0", 1), cloud_mesh("E15_CloudW1", 2), cloud_mesh("E15_CloudG0", 4, 5, 0.5), cloud_mesh("E15_CloudM0", 3), cloud_mesh("E15_CloudD0", 5, 7, 0.6)]
    M["rubD"] = [blob_mesh("E15_RubD%d" % i, 0.45, 0.7, 0.35, 61 + i, 1) for i in range(2)]
    M["chip"] = blob_mesh("E15_Chip", 0.28, 0.7, 0.3, 71, 1)
    M["soot"] = blob_mesh("E15_Soot", 0.16, 0.8, 0.2, 81, 1)
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
    tri = {cn: len([o for o in bpy.data.collections[cn].objects if o.type == "MESH"]) for cn in ("E01_CENTER", "E01_SEG1_E", "E01_END_E")}
    print("OBJETS par brique :", tri, "triangles/nuage :", [len(m.polygons) for m in M["cloud"]])
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E15_Fumee")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E15_Fumee_v2.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E15")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11)), ("CAM_Game", (5, 9))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v2_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E15_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
