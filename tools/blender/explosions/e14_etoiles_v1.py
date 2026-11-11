"""E14 Etoiles (base e09..e13) (référence : Explosions_32.png, rangée 2, 1re carte) : gerbe de lames aux 7 couleurs de l'arc-en-ciel autour d'un cœur blanc, flash bref,
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

GOLD, ORANGE, YEL = "#FFC21A", "#FF9A1A", "#FFE45C"

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
    b.inputs["Roughness"].default_value = 0.85
    b.inputs["Emission Color"].default_value = hex_lin("#FF9A1A")
    b.inputs["Emission Strength"].default_value = 0.1
    return m

def star5_mesh(name, thick=0.35, R=1.0, r=0.46):
    # étoile à 5 branches bombée, debout : normale le long de +X, une pointe vers le haut (+Z), centrée sur l'origine
    pts = []
    for k in range(10):
        a = math.pi / 2 + k * math.pi / 5
        rr = R if k % 2 == 0 else r
        pts.append((rr * math.cos(a), rr * math.sin(a)))
    prof = [(0.5, -1.0), (1.0, -0.55), (1.0, 0.55), (0.5, 1.0)]
    v, f = [], []
    for sc, z in prof:
        for (u, w) in pts:
            v.append((z * thick, u * sc, w * sc))
    n = len(pts)
    for a in range(len(prof) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            f.append((a * n + k, a * n + k2, (a + 1) * n + k2, (a + 1) * n + k))
    v.append((-thick * 1.05, 0, 0))
    v.append((thick * 1.05, 0, 0))
    cb, ct = len(v) - 2, len(v) - 1
    for k in range(n):
        k2 = (k + 1) % n
        f.append((cb, k2, k))
        f.append((ct, (len(prof) - 1) * n + k, (len(prof) - 1) * n + k2))
    return mk(name, v, f)

def trail_mesh(name, w=0.17):
    # traînée effilée le long de +X : pointe à l'arrière (x=0), large près de l'étoile (x=1)
    v = [(0, 0, -0.01), (1, -w, -0.01), (1, w, -0.01), (0, 0, 0.01), (1, -w, 0.01), (1, w, 0.01)]
    f = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    return mk(name, v, f)

def pyramid(name, r=0.3, ln=1.0):
    v = [(0, -r, -r), (0, r, -r), (0, r, r), (0, -r, r), (ln, 0, 0)]
    f = [(0, 1, 2, 3), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
    return mk(name, v, f)

def star_pulse(name, ctx, M, loc, start, rmax, az):
    # onde de choc : étoile plate translucide qui s'élargit et s'efface (remplace l'anneau)
    k = [(1, (0.001, 0.001, 0.001)), (start, (0.4 * rmax,) * 3), (start + 1, (0.85 * rmax,) * 3), (start + 2, (rmax,) * 3), (start + 3, (0.001, 0.001, 0.001))]
    add_obj(ctx, name, M["starF"], M["PULSE"], loc, k, az=az, el=90)

SPEED = [0.0, 1.4, 2.8, 4.0, 5.0, 5.8, 6.4, 6.8, 7.0]

def flight(ctx, tag, name, M, mesh, mat, S, start, origin, daz, el, dist, face, rng, trail=True, life=8):
    # une étoile jaillit en ligne droite (direction daz/el), grossit, puis rétrécit en montant ; sa traînée la suit
    d = (math.cos(math.radians(el)) * math.cos(math.radians(daz)), math.cos(math.radians(el)) * math.sin(math.radians(daz)), math.sin(math.radians(el)))
    n = min(life, len(SPEED))
    pts = [(start + i, tuple(origin[j] + d[j] * SPEED[i] * dist / 7.0 for j in range(3))) for i in range(n)]
    pts = [(f, (p[0], p[1], p[2] + (0.05 * i if i > 4 else 0))) for i, (f, p) in enumerate(pts)]
    kk = [(1, 0.001), (start, 0.5 * S), (start + 1, 1.2 * S), (start + 2, S), (start + n - 3, 0.9 * S), (start + n - 2, 0.5 * S), (start + n - 1, 0.001)]
    add_obj(ctx, f"{tag}_{name}", mesh, mat, pts[0][1], kk, az=face + rng.uniform(-8, 8), el=24, loc_keys=pts)
    if trail:
        Lt = 2.2 * S
        tk = [(1, 0.001), (start + 1, 0.5 * Lt), (start + 2, Lt), (start + n - 4, 0.9 * Lt), (start + n - 2, 0.001)]
        tl = [(f, (p[0] - d[0] * Lt * 0.9, p[1] - d[1] * Lt * 0.9, p[2] - d[2] * Lt * 0.9)) for f, p in pts]
        add_obj(ctx, f"{tag}_{name}Trail", M["trail"], M["TRAIL"], tl[0][1], tk, az=daz, el=el, loc_keys=tl)

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    face = 90 - ctx.arm
    if kind == "center":
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.9), [(1, 0.001), (2, 2.2), (3, 1.4), (4, 0.6), (5, 0.001)], az=20)
        add_obj(ctx, f"{tag}_Halo", M["halo"], M["GLOW"], (0, 0, 0.2), [(1, 0.001), (2, 0.8), (3, 1.8), (6, 1.8), (9, 1.4), (11, 0.001)])
        star_pulse(f"{tag}_Pulse0", ctx, M, (0, 0, 0.1), 2, 2.4, 18)
        star_pulse(f"{tag}_Pulse1", ctx, M, (0, 0, 0.12), 4, 3.0, 54)
        for i in range(6):  # gerbe d'étincelles dorées en pointes (éclatement)
            az = 60 * i + 15
            sz = 1.5 + 0.4 * (i % 2)
            add_obj(ctx, f"{tag}_Spike{i}", M["spike"], M["SPIKE"], (0, 0, 0.0), [(1, 0.001), (2, 0.6 * sz), (3, sz), (4, sz), (6, 0.5 * sz), (7, 0.001)], az=az, el=48 + 14 * (i % 2))
        for i, d in enumerate([0, 90, 180, 270]):  # grandes étoiles lancées le long de la croix
            flight(ctx, tag, f"Star{i}", M, M["starL"][i % 2], M["STAR%d" % (i % 2)], 0.85, 2, (0, 0, 0.9), d, 32, 6.0, face, r)
        for i in range(4):  # petites étoiles projetées
            ang = r.uniform(0, 6.28)
            sp, vz = r.uniform(4.0, 7.0), r.uniform(5.0, 9.0)
            add_obj(ctx, f"{tag}_Mini{i}", M["starS"], M["STAR2"], (0, 0, 0.8), fade(0.45, 3, 10 + i % 3),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.8, g=18.0), az=face + r.uniform(-15, 15), el=24)
        for g in range(4):
            a = math.radians(45 + 90 * g)
            add_obj(ctx, f"{tag}_Glint{g}", M["diamond"], M["SPARKW"], (1.3 * math.cos(a), 1.3 * math.sin(a), 1.4), [(1, 0.001), (3, 0.001), (4, 1.1), (5, 0.4), (6, 1.0), (9, 0.001)],
                    loc_keys=[(fr, (1.3 * math.cos(a) * (1 + 0.1 * (fr - 3)), 1.3 * math.sin(a) * (1 + 0.1 * (fr - 3)), 1.4 + 0.2 * (fr - 3))) for fr in range(3, 10)], tumble=True)
        for i in range(4):  # paillettes
            ang = r.uniform(0, 6.28)
            sp, vz = r.uniform(3.0, 6.0), r.uniform(6.0, 10.0)
            add_obj(ctx, f"{tag}_Glitter{i}", M["glit"][i % 2], M["SPARKW"], (0, 0, 0.8), fade(0.9, 4 + i % 3, 10 + i % 3),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.8, g=20.0), az=math.degrees(ang), el=50)
        for i in range(3):  # roches sombres au pied
            a = math.radians(30 + 120 * i)
            add_obj(ctx, f"{tag}_Rubble{i}", M["rubble"][i % 2], M["ROCKD"], (1.4 * math.cos(a), 1.4 * math.sin(a), 0.25), [(1, 0.001), (2, 0.6), (3, 0.9), (8, 0.9), (10, 0.001)],
                    loc_keys=[(2, (0.6 * math.cos(a), 0.6 * math.sin(a), 0.5)), (4, (1.4 * math.cos(a), 1.4 * math.sin(a), 0.25))])
        for i in range(3):  # poussière brune
            a = math.radians([200, 270, 340][i])
            sz = 0.85 + 0.15 * i
            add_obj(ctx, f"{tag}_Dust{i}", M["puff"][i], M["DUST"], (1.7 * math.cos(a), 1.7 * math.sin(a), 0.5), [(1, 0.001), (2, 0.4 * sz), (4, sz), (7, sz), (9, 0.6 * sz), (11, 0.001)],
                    loc_keys=[(2, (1.4 * math.cos(a), 1.4 * math.sin(a), 0.4)), (9, (2.2 * math.cos(a), 2.2 * math.sin(a), 0.8))])
    else:
        t = 2 if kind == "segment" else 3
        base = 0.7 if kind == "segment" else 0.9
        for i, (y, sz, col) in enumerate([(0.6, 0.8 * base, 0), (-0.5, 1.0 * base, 1), (0.05, 0.6 * base, 2)]):
            ti = t + (1 if i == 2 else 0)
            mesh = M["starL"][col] if col < 2 else M["starS"]
            flight(ctx, tag, f"Star{i}", M, mesh, M["STAR%d" % col], sz, ti, (-2.0, y, 0.2), 0, 28 + 4 * i, 3.6, face, r, trail=(i < 2), life=8)
        for i, x in enumerate([-1.0, 0.8][:1 if kind == "segment" else 2]):
            ti = t + i
            add_obj(ctx, f"{tag}_Trace{i}", M["starF"], M["FLATM"], (x, 0.0, 0.06), [(1, 0.001), (ti, 0.5), (ti + 1, 1.0), (ti + 4, 0.8), (ti + 6, 0.001)], az=20 * i, el=90,
                    loc_keys=[(ti, (x, 0.0, 0.06)), (ti + 6, (x + 1.4, 0.0, 0.06))])
        add_obj(ctx, f"{tag}_Dust0", M["puff"][0], M["DUST"], (0.0, 0.0, 0.4), [(1, 0.001), (t, 0.45), (t + 2, 0.75), (t + 5, 0.7), (t + 7, 0.001)],
                loc_keys=[(t, (-0.8, 0.0, 0.3)), (t + 6, (1.0, 0.0, 0.9))])
        add_obj(ctx, f"{tag}_Rubble0", M["rubble"][0], M["ROCKD"], (0.5, 0.3, 0.25), [(1, 0.001), (t + 1, 0.8), (t + 5, 0.8), (t + 7, 0.001)])
        if kind == "end":
            star_pulse(f"{tag}_Pulse0", ctx, M, (0.3, 0, 0.1), 3, 1.3, 30)
            for i in range(3):
                add_obj(ctx, f"{tag}_Spike{i}", M["spike"], M["SPIKE"], (0.3, 0, 0.0), [(1, 0.001), (3, 0.5), (4, 1.2), (6, 0.8), (7, 0.001)], az=-60 + 60 * i, el=55)
        for g in range(2):
            add_obj(ctx, f"{tag}_Glint{g}", M["diamond"], M["SPARKW"], (-0.8 + 1.6 * g, 0.0, 1.4), [(1, 0.001), (t + 3 + g, 0.001), (t + 4 + g, 0.9), (t + 5 + g, 0.35), (t + 6 + g, 0.8), (t + 8, 0.001)], tumble=True,
                    loc_keys=[(t + 3 + g, (-0.8 + 1.6 * g, 0.0, 1.2)), (t + 8, (-0.2 + 1.6 * g, 0.0, 2.3))])

def build():
    M = {"STAR0": make_gem("STAR0", GOLD, 0.8), "STAR1": make_gem("STAR1", ORANGE, 0.8), "STAR2": make_gem("STAR2", YEL, 0.8)}
    M["SPIKE"] = make_neon("SPIKE", "#FFC21A")
    M["FLASH"] = make_neon("FLASH", "#FFF3A0")
    M["TRAIL"] = make_neon("TRAIL", "#FFB020")
    M["SPARKW"] = make_neon("SPARKW", "#FFFBE0")
    M["PULSE"] = make_glow("PULSE", "#FFD24A", 0.25)
    M["FLATM"] = make_glow("FLATM", "#FFC83A", 0.25)
    M["GLOW"] = make_glow("GLOW", "#FFB62E", 0.3)
    M["DUST"] = make_puff("DUST", "#B8935F")
    M["ROCKD"] = make_rock("ROCKD", "#4A3626")
    M["starL"] = [star5_mesh("E14_StarG"), star5_mesh("E14_StarO")]
    M["starS"] = star5_mesh("E14_StarY")
    M["starF"] = star5_mesh("E14_StarF", thick=0.03)
    M["trail"] = trail_mesh("E14_Trail")
    M["spike"] = pyramid("E14_Spike", 0.2, 1.0)
    M["diamond"] = star_mesh("E14_Diamond")
    M["glit"] = [spark_mesh("E14_Glitter%d" % i) for i in range(2)]
    M["halo"] = blob_mesh("E14_Halo", 1.0, 0.12, 0.08, 14, 1)
    M["flash"] = blob_mesh("E14_Flash", 0.7, 0.85, 0.5, 33, 2)
    M["puff"] = [blob_mesh("E14_Dust%d" % i, 0.6, 0.7, 0.14, 40 + i, 2) for i in range(3)]
    M["rubble"] = [blob_mesh("E14_Rubble%d" % i, 0.5, 0.65, 0.3, 21 + i, 1) for i in range(2)]
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
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E14_Etoiles")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E14_Etoiles_v1.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E14")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11)), ("CAM_Game", (5, 9))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v1_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E14_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
