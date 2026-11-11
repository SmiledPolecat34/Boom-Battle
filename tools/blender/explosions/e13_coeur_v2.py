"""E13 Coeur (base e09..e12) (référence : Explosions_32.png, rangée 2, 1re carte) : gerbe de lames aux 7 couleurs de l'arc-en-ciel autour d'un cœur blanc, flash bref,
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

HEART = "#FF6FBC"
SHEET = ["#FF6FBC", "#FFA3D6", "#FF4FA8"]  # grand coeur, petits coeurs clairs, petits coeurs vifs

def make_gem(key, hx, emi=0.7):
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.3
    b.inputs["Emission Color"].default_value = hex_lin(hx)
    b.inputs["Emission Strength"].default_value = emi
    return m

def make_glow(key, hx, alpha=0.35):
    m = bpy.data.materials["E01_Smoke"].copy()
    m.name = "E09_" + key
    set_color(m, hx)
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Alpha"].default_value = alpha
    return m

def make_rock(key, hx):
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.8
    b.inputs["Emission Color"].default_value = hex_lin("#FF4FA8")
    b.inputs["Emission Strength"].default_value = 0.15
    return m

def heart_mesh(name, thick=0.4, n=28):
    # coeur bombé, debout : normale le long de +X, haut = +Z, pointe en bas posée sur l'origine (hauteur 2, largeur ~2)
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 16.0 * 1.0, (y + 17.0) / 29.0 * 2.0))
    cu, cv = 0.0, 0.95
    prof = [(0.55, -0.85), (0.92, -0.45), (1.0, 0.0), (0.92, 0.45), (0.55, 0.85)]
    v, f = [], []
    for sc, z in prof:
        for (u, w) in pts:
            v.append((z * thick, cu + (u - cu) * sc, cv + (w - cv) * sc))
    nb = len(prof)
    for a in range(nb - 1):
        for k in range(n):
            k2 = (k + 1) % n
            f.append((a * n + k, a * n + k2, (a + 1) * n + k2, (a + 1) * n + k))
    v.append((-thick * 1.05, cu, cv))
    v.append((thick * 1.05, cu, cv))
    cb, ct = len(v) - 2, len(v) - 1
    for k in range(n):
        k2 = (k + 1) % n
        f.append((cb, k2, k))
        f.append((ct, (nb - 1) * n + k, (nb - 1) * n + k2))
    return mk(name, v, f)

def shine_mesh(name):
    # reflet brillant (ellipse inclinée) posé sur le coeur
    v, f = [], []
    n = 10
    for k in range(n):
        a = 2 * math.pi * k / n
        u, w = 0.30 * math.cos(a), 0.11 * math.sin(a)
        ca, sa = math.cos(0.7), math.sin(0.7)
        v.append((0.0, u * ca - w * sa, u * sa + w * ca))
    v.append((0.0, 0.0, 0.0))
    for k in range(n):
        f.append((n, k, (k + 1) % n))
        f.append((n, (k + 1) % n, k))
    return mk(name, v, f)

def pyramid(name, r=0.3, ln=1.0):
    v = [(0, -r, -r), (0, r, -r), (0, r, r), (0, -r, r), (ln, 0, 0)]
    f = [(0, 1, 2, 3), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
    return mk(name, v, f)

def rotv(vec, az, el):
    x, y, z = vec
    th = -math.radians(el)
    x2, z2 = x * math.cos(th) + z * math.sin(th), -x * math.sin(th) + z * math.cos(th)
    a = math.radians(az)
    return (x2 * math.cos(a) - y * math.sin(a), x2 * math.sin(a) + y * math.cos(a), z2)

def beat(S, start, burst):
    # le coeur surgit, bat deux fois, puis éclate
    k = [(1, 0.001), (start, 0.5 * S), (start + 1, 1.25 * S), (start + 2, S)]
    for i, f in enumerate(range(start + 3, burst)):
        k.append((f, S * (1.12 if i % 2 == 0 else 1.0)))
    k += [(burst, 1.3 * S), (burst + 1, 0.55 * S), (burst + 2, 0.001)]
    return k

def pop_fade(S, start, end):
    return [(1, 0.001), (start, 0.4 * S), (start + 1, 1.15 * S), (start + 2, S), (end - 2, 0.9 * S), (end - 1, 0.45 * S), (end, 0.001)]

def arc_path(x, y, z0, t, n, vx, vy, rise, fall):
    # trajectoire en arc (monte puis retombe doucement) qui avance dans la direction de la branche
    return [(t + i, (x + vx * i, y + vy * i, z0 + rise * i - fall * i * i)) for i in range(n)]

def soft_pulse(name, ctx, M, loc, start, rmax, az):
    # impulsion douce : un coeur plat translucide qui s'élargit et s'efface (onde "affective" organique, sans anneau).
    # Le coeur plat part de sa pointe : on recentre sa position à chaque image pour qu'il reste centré sur l'explosion.
    sc = [(start, 0.35 * rmax), (start + 1, 0.8 * rmax), (start + 3, rmax)]
    k = [(1, (0.001, 0.001, 0.001))] + [(f, (x, x, x)) for f, x in sc] + [(start + 4, (0.001, 0.001, 0.001))]
    ca, sa = math.cos(math.radians(az)), math.sin(math.radians(az))
    lk = [(f, (loc[0] + ca * x, loc[1] + sa * x, loc[2])) for f, x in sc]
    add_obj(ctx, name, M["heartF"], M["PULSE"], (loc[0] + ca * 0.35 * rmax, loc[1] + sa * 0.35 * rmax, loc[2]), k, az=az, el=90, loc_keys=lk)

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    face = 90 - ctx.arm  # les coeurs regardent toujours la caméra, quel que soit le bras
    if kind == "center":
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.9), [(1, 0.001), (2, 1.8), (3, 1.2), (4, 0.6), (5, 0.001)], az=20)
        add_obj(ctx, f"{tag}_Flash2", M["flash"], M["FLASH"], (0, 0, 1.6), [(1, 0.001), (8, 0.001), (9, 1.1), (10, 0.5), (11, 0.001)], az=70)  # éclat de l'éclatement du coeur
        add_obj(ctx, f"{tag}_Halo", M["halo"], M["GLOW"], (0, 0, 0.2), [(1, 0.001), (2, 0.8), (3, 1.8), (6, 2.0), (9, 1.7), (11, 0.001)])
        soft_pulse(f"{tag}_Pulse0", ctx, M, (0, 0, 0.1), 2, 2.2, 20)
        soft_pulse(f"{tag}_Pulse1", ctx, M, (0, 0, 0.12), 9, 2.6, -35)
        for i in range(3):  # pointes roses derrière le coeur
            az = 90 + (i - 1) * 55
            add_obj(ctx, f"{tag}_Spike{i}", M["spike"], M["SPIKE"], (0.0, 0.5, 0.0),
                    [(1, 0.001), (2, 0.9), (3, 2.0), (5, 1.9), (7, 1.0), (8, 0.001)], az=az, el=58)
        S = 1.9
        add_obj(ctx, f"{tag}_Heart", M["heartL"], M["HEART0"], (0, 0.0, 0.0), beat(S, 2, 9), az=face, el=24)
        sh = []
        for fr, sc in [(2, 0.5 * S), (3, 1.25 * S), (4, S)] + [(f, S * (1.12 if (f - 5) % 2 == 0 else 1.0)) for f in range(5, 9)] + [(9, 1.3 * S), (10, 0.55 * S)]:
            sh.append((fr, rotv((0.36 * sc, -0.45 * sc, 1.35 * sc), face, 24)))
        add_obj(ctx, f"{tag}_Shine", M["shine"], M["SHINE"], sh[0][1], [(1, 0.001), (2, 0.5 * S), (3, 1.2 * S), (4, S), (8, S), (9, 1.2 * S), (10, 0.001)], az=face, el=24, loc_keys=sh)
        for i in range(3):  # petits coeurs flottants (sur les côtés et derrière)
            ang = math.radians([15, 165, 270][i])
            x0, y0 = 1.8 * math.cos(ang), 1.8 * math.sin(ang)
            t = 3 + i
            add_obj(ctx, f"{tag}_Mini{i}", M["heartS"][i % 2], M["HEART%d" % (1 + i % 2)], (x0, y0, 0.8),
                    pop_fade(0.55 + 0.1 * i, t, 12), az=face + r.uniform(-20, 20), el=r.uniform(15, 35),
                    loc_keys=arc_path(x0, y0, 0.8, t, 9, 0.1 * math.cos(ang), 0.1 * math.sin(ang), 0.32, 0.0))
        for i, d in enumerate([0, 90, 180, 270]):  # l'éclatement du coeur projette 4 petits coeurs le long de la croix
            a = math.radians(d)
            ks = [(1, 0.001), (8, 0.001), (9, 0.7), (10, 0.9), (13, 0.7), (14, 0.001)]
            lk = [(fr, (math.cos(a) * dd, math.sin(a) * dd, 1.5 + 0.9 * math.sin((fr - 8) * 0.5) - 0.12 * (fr - 8))) for fr, dd in zip(range(8, 15), [0.3, 1.2, 2.5, 3.8, 5.0, 6.0, 6.8])]
            add_obj(ctx, f"{tag}_Burst{i}", M["heartS"][(i + 1) % 2], M["HEART%d" % (1 + (i + 1) % 2)], (0, 0, 1.5), ks, az=face + (30 if i % 2 else -30), el=30, loc_keys=lk)
        for i in range(3):  # nuages roses au pied (sur les côtés et derrière)
            a = math.radians([200, 270, 340][i])
            sz = 0.85 + 0.15 * i
            add_obj(ctx, f"{tag}_Puff{i}", M["puff"][i], M["PUFFL" if i == 1 else "PUFF"], (1.8 * math.cos(a), 1.8 * math.sin(a), 0.5),
                    [(1, 0.001), (2, 0.4 * sz), (4, sz), (8, sz), (10, 0.6 * sz), (12, 0.001)],
                    loc_keys=[(2, (1.5 * math.cos(a), 1.5 * math.sin(a), 0.4)), (6, (2.0 * math.cos(a), 2.0 * math.sin(a), 0.6)), (11, (2.3 * math.cos(a), 2.3 * math.sin(a), 0.9))])
        for i in range(2):
            a = math.radians(40 + 140 * i)
            add_obj(ctx, f"{tag}_Rubble{i}", M["rubble"], M["ROCKD"], (1.2 * math.cos(a), 1.2 * math.sin(a), 0.2), [(1, 0.001), (3, 0.5), (8, 0.5), (10, 0.001)])
        for g in range(4):
            a = math.radians(45 + 90 * g)
            add_obj(ctx, f"{tag}_Glint{g}", M["star"], M["SPARK"], (1.3 * math.cos(a), 1.3 * math.sin(a), 1.6), [(1, 0.001), (3, 0.001), (4, 1.1), (5, 0.4), (6, 1.0), (9, 0.001)],
                    loc_keys=[(fr, (1.3 * math.cos(a) * (1 + 0.1 * (fr - 3)), 1.3 * math.sin(a) * (1 + 0.1 * (fr - 3)), 1.6 + 0.2 * (fr - 3))) for fr in range(3, 10)], tumble=True)
        for i in range(6):  # paillettes projetées
            ang = r.uniform(0, 6.28)
            sp, vz = r.uniform(3.0, 6.0), r.uniform(6.0, 10.0)
            add_obj(ctx, f"{tag}_Glitter{i}", M["glit"][i % 2], M["SPARK"], (0, 0, 0.8), fade(0.9, 3 + i % 3, 9 + i % 3),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.8, g=20.0), az=math.degrees(ang), el=50)
    else:
        t = 2 if kind == "segment" else 3
        # propagation : les coeurs avancent le long de la branche (en arc), les traces au sol glissent vers l'extrémité
        if kind == "segment":
            spec = [(-1.4, 0.4, 0), (-0.2, -0.4, 1)]
        else:
            spec = [(-0.8, 0.45, 0), (0.0, -0.4, 1)]
        for i, (x, y, ci) in enumerate(spec):
            ti = t + i
            add_obj(ctx, f"{tag}_Trace{i}", M["heartF"], M["FLATM"], (x, 0.0, 0.06), [(1, 0.001), (ti, 0.5), (ti + 1, 1.0), (ti + 4, 0.9), (ti + 6, 0.001)], az=90 + 20 * i, el=90,
                    loc_keys=[(ti, (x, 0.0, 0.06)), (ti + 6, (x + 1.5, 0.0, 0.06))])
            add_obj(ctx, f"{tag}_Heart{i}", M["heartS"][ci], M["HEART%d" % (1 + ci)], (x, y, 0.0), pop_fade(0.85 if kind == "segment" else 1.0, ti, ti + 7),
                    az=face + (12 if i else -12), el=24 + 4 * i, loc_keys=arc_path(x, y, 0.0, ti, 7, 0.42, 0.0, 0.55, 0.06))
        add_obj(ctx, f"{tag}_Puff0", M["puff"][0], M["PUFF"], (0.0, 0.0, 0.45), [(1, 0.001), (t, 0.5), (t + 2, 0.85), (t + 5, 0.85), (t + 7, 0.001)],
                loc_keys=[(t, (-0.5, 0.0, 0.3)), (t + 6, (0.9, 0.0, 0.8))])
        if kind == "end":
            soft_pulse(f"{tag}_Pulse0", ctx, M, (0.3, 0, 0.1), 3, 1.1, 30)
        for g in range(2):
            add_obj(ctx, f"{tag}_Glint{g}", M["star"], M["SPARK"], (-0.8 + 1.6 * g, 0.0, 1.4), [(1, 0.001), (t + 2 + g, 0.001), (t + 3 + g, 0.9), (t + 4 + g, 0.35), (t + 5 + g, 0.8), (t + 7, 0.001)], tumble=True,
                    loc_keys=[(t + 2 + g, (-0.8 + 1.6 * g, 0.0, 1.2)), (t + 7, (-0.2 + 1.6 * g, 0.0, 2.2))])

def build():
    M = {"HEART%d" % i: make_gem("HEART%d" % i, hx, 0.7) for i, hx in enumerate(SHEET)}
    M["SPIKE"] = make_gem("SPIKE", "#FF5CB8", 0.9)
    M["FLASH"] = make_neon("FLASH", "#FFE6F3")
    M["SHINE"] = make_neon("SHINE", "#FFFFFF")
    M["SPARK"] = make_neon("SPARK", "#FFD6EC")
    M["FLATM"] = make_glow("FLATM", "#FF7CC4", 0.5)
    M["PULSE"] = make_glow("PULSE", "#FF8CCB", 0.4)
    M["GLOW"] = make_glow("GLOW", "#FF5CB8", 0.3)
    M["PUFF"] = make_puff("PUFF", "#FF6FB5")
    M["PUFFL"] = make_puff("PUFFL", "#FF9CCB")
    M["ROCKD"] = make_rock("ROCKD", "#5A0F3E")
    M["heartL"] = heart_mesh("E13_HeartL", 0.4)
    M["heartS"] = [heart_mesh("E13_HeartS0", 0.4), heart_mesh("E13_HeartS1", 0.4)]
    M["heartF"] = heart_mesh("E13_HeartF", 0.03)
    M["shine"] = shine_mesh("E13_Shine")
    M["spike"] = pyramid("E13_Spike", 0.22, 1.0)
    M["star"] = star_mesh("E13_Star")
    M["glit"] = [spark_mesh("E13_Glitter%d" % i) for i in range(2)]
    M["halo"] = blob_mesh("E13_Halo", 1.0, 0.12, 0.08, 14, 1)
    M["flash"] = blob_mesh("E13_Flash", 0.7, 0.85, 0.5, 33, 2)
    M["puff"] = [blob_mesh("E13_Puff%d" % i, 0.6, 0.7, 0.14, 40 + i, 2) for i in range(3)]
    M["rubble"] = blob_mesh("E13_Rubble", 0.5, 0.65, 0.3, 21, 1)
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
    print("OBJETS par brique :", tri)
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E13_Coeur")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E13_Coeur_v2.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E13")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11)), ("CAM_Game", (5, 9))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v2_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E13_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
