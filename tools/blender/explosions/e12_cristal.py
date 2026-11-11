"""E12 Cristal (base e09/e10/e11) (référence : Explosions_32.png, rangée 2, 1re carte) : gerbe de lames aux 7 couleurs de l'arc-en-ciel autour d'un cœur blanc, flash bref,
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

CRY = ["#8B3DFF", "#D346FF", "#5B45FF"]   # violet, magenta, bleu-violet (cristaux)
GLOWC = "#B15CFF"

def make_rock(key, hx):
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.8
    b.inputs["Emission Color"].default_value = hex_lin("#7A3DFF")
    b.inputs["Emission Strength"].default_value = 0.2
    return m

def make_gem(key, hx):
    # cristal opaque, très lumineux : couleur franche + forte émission (rendu « gemme » sans transparence, bon marché sur mobile)
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.25
    b.inputs["Emission Color"].default_value = hex_lin(hx)
    b.inputs["Emission Strength"].default_value = 0.8
    return m

def make_glow(key, hx, alpha=0.35):
    m = bpy.data.materials["E01_Smoke"].copy()
    m.name = "E09_" + key
    set_color(m, hx)
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Alpha"].default_value = alpha
    return m

def glow_mesh(name, length=4.0, w=0.5, h=0.02):
    v = [(0, -w, -h), (length, -w, -h), (length, w, -h), (0, w, -h), (0, -w, h), (length, -w, h), (length, w, h), (0, w, h)]
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return mk(name, v, f)

def crystal_prism(name, r=0.3, shoulder=0.62, tip=0.38, taper=0.8, twist=0.0):
    # cristal hexagonal le long de +X (longueur 1) : base légèrement plus étroite, fût, puis pointe pyramidale à 6 faces
    v, f = [], []
    rings = [(0.0, r * taper), (shoulder, r)]
    for x, rr in rings:
        for k in range(6):
            a = math.pi / 3 * k + (twist if x > 0 else 0)
            v.append((x, rr * math.cos(a), rr * math.sin(a)))
    v.append((1.0, 0, 0))
    for k in range(6):
        k2 = (k + 1) % 6
        f.append((k, k2, 6 + k2, 6 + k))          # fût
        f.append((6 + k, 6 + k2, 12))             # pointe
    f.append((5, 4, 3, 2))
    f.append((0, 5, 2, 1))
    return mk(name, v, f)

def pulse_ring(name, ctx, M, mat, loc, start, rmax, key="ring"):
    # onde de choc cristalline brève et fine (3 images)
    k = [(1, (0.001, 0.001, 0.001)), (start, (rmax * 0.35, rmax * 0.35, 1.0)), (start + 1, (rmax * 0.85, rmax * 0.85, 0.8)), (start + 2, (rmax, rmax, 0.4)), (start + 3, (0.001, 0.001, 0.001))]
    add_obj(ctx, name, M[key], mat, loc, k, az=random.Random(name).uniform(0, 60))

def strip_into(v, f, pts, ws, h=0.02):
    base = len(v)
    for (x, y), w in zip(pts, ws):
        v += [(x, y - w, -h), (x, y + w, -h), (x, y + w, h), (x, y - w, h)]
    for i in range(len(pts) - 1):
        a = base + 4 * i
        b = a + 4
        for k in range(4):
            k2 = (k + 1) % 4
            f.append((a + k, a + k2, b + k2, b + k))
    f.append((base, base + 3, base + 2, base + 1))
    e = base + 4 * (len(pts) - 1)
    f.append((e, e + 1, e + 2, e + 3))

def crack_mesh(name, seed, length=4.0, w=0.2, h=0.02):
    # fissure cristalline irrégulière : ligne brisée principale effilée + 2-3 ramifications, posée au sol le long de +X
    r = random.Random(seed)
    n = 8
    xs = [length * (k / n) for k in range(n + 1)]
    ys = [0.0]
    for k in range(1, n + 1):
        ys.append(max(-0.8, min(0.8, ys[-1] + r.uniform(-0.38, 0.38))))
    ws = [w * (1.0 - 0.55 * k / n) * r.uniform(0.8, 1.2) for k in range(n + 1)]
    v, f = [], []
    strip_into(v, f, list(zip(xs, ys)), ws, h)
    for bi in r.sample(range(2, n - 1), 3):
        sgn = r.choice([-1, 1])
        ln = r.uniform(0.45, 0.8)
        d = (r.uniform(0.35, 0.7), sgn * r.uniform(0.6, 1.0))
        nm = math.hypot(*d)
        pts = [(xs[bi] + d[0] / nm * ln * t / 3.0, ys[bi] + d[1] / nm * ln * t / 3.0) for t in range(4)]
        strip_into(v, f, pts, [w * 0.9, w * 0.75, w * 0.55, w * 0.3], h)
    return mk(name, v, f)

def facet_mesh(name, r=0.30, shoulder=0.62, taper=0.8):
    # liseré brillant le long d'une arête du cristal (reflet stylisé), posé légèrement au-dessus de la face
    p = [(0.10, r * taper * 1.08), (shoulder, r * 1.08), (0.97, 0.03)]
    ws = [0.045, 0.05, 0.012]
    v, f = [], []
    for (x, y), w in zip(p, ws):
        v += [(x, y, -w), (x, y, w)]
    for i in range(2):
        a = 2 * i
        f.append((a, a + 2, a + 3, a + 1))
        f.append((a, a + 1, a + 3, a + 2))
    return mk(name, v, f)

def grow(L, start, shatter, wid=1.0):
    # un cristal jaillit du sol (échelle le long de son axe), dépasse, se stabilise, puis éclate (rétrécit vite) à `shatter`
    return [(1, (0.001, 0.001, 0.001)), (start, (0.45 * L, wid, wid)), (start + 1, (1.25 * L, wid, wid)), (start + 2, (1.05 * L, wid, wid)), (start + 3, (L, wid, wid)),
            (shatter, (L, wid, wid)), (shatter + 1, (0.55 * L, 0.8 * wid, 0.8 * wid)), (shatter + 2, (0.001, 0.001, 0.001))]

def gem(ctx, tag, i, M, ci, loc, L, start, shatter, az, el, wid=1.0, facet=False, trans=False):
    r = random.Random(tag + str(i))
    L2 = L * r.uniform(0.85, 1.2)
    st = start + (1 if r.random() < 0.3 else 0)
    az2 = az + r.uniform(-14, 14)
    el2 = el + r.uniform(-8, 8)
    lz = r.uniform(-0.05, 0.12)
    kk = grow(L2, st, shatter + (1 if r.random() < 0.5 else 0), wid)
    lc = (loc[0], loc[1], loc[2] + lz)
    if trans:
        add_obj(ctx, f"{tag}_GemT{i}", M["prism"][3], M["CRYT"], lc, kk, az=az2, el=el2, jit=0)
    else:
        add_obj(ctx, f"{tag}_Gem{i}", M["prism"][ci], M["CRY%d" % ci], lc, kk, az=az2, el=el2, jit=0)
    if facet:
        add_obj(ctx, f"{tag}_Facet{i}", M["facet"][ci % 3], M["FACET"], lc, kk, az=az2, el=el2, jit=0)

def crack_pair(ctx, tag, M, loc, az, t, length, idx, fade_at):
    S = length / 4.0
    # fissure sombre (bordure) + coeur lumineux, qui se propage vite puis se refroidit et disparaît
    gk = [(1, (0.001, S, S)), (t, (0.45 * S, S, S)), (t + 1, (S, S, S)), (fade_at, (S, S, S)), (fade_at + 1, (S, 0.5 * S, 0.5 * S)), (fade_at + 2, 0.001)]
    add_obj(ctx, f"{tag}_CrackD{idx}", M["crackD"][idx], M["ROCKD"], (loc[0], loc[1], 0.04), gk, az=az)
    add_obj(ctx, f"{tag}_Crack{idx}", M["crack"][idx], M["CRACKC"], (loc[0], loc[1], 0.07), gk, az=az)

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 2.0), (3, 1.2), (4, 0.4), (5, 0.001)], az=20)
        add_obj(ctx, f"{tag}_Halo", M["halo"], M["GLOW"], (0, 0, 0.2), [(1, 0.001), (2, 0.8), (3, 1.7), (5, 2.0), (8, 1.6), (10, 0.001)])
        pulse_ring(f"{tag}_Ring0", ctx, M, M["RINGA"], (0, 0, 0.1), 2, 2.8, "hex")
        for q in range(4):  # fissures irrégulières qui rayonnent du centre
            crack_pair(ctx, tag, M, (0, 0), 90 * q + 45, 2, 2.2, q % 2, 8)
        gem(ctx, tag, 0, M, 0, (0, 0, 0.0), 3.6, 2, 9, 0, 90, facet=True)
        for i in range(4):
            az = 45 + 90 * i
            gem(ctx, tag, i + 1, M, 1 + i % 2, (0.35 * math.cos(math.radians(az)), 0.35 * math.sin(math.radians(az)), 0.0),
                2.4 + 0.3 * (i % 2), 3 + (i % 2), 9 + (i % 2), az, 62, facet=(i % 2 == 0), trans=(i == 3))
        for i in range(8):  # éclats de gemme projetés
            ang = r.uniform(0, 6.28)
            sp, vz = r.uniform(5.0, 9.0), r.uniform(4.0, 8.0)
            add_obj(ctx, f"{tag}_Shard{i}", M["spark"][i % 3], M["CRY%d" % (i % 3)], (0, 0, 0.9), fade(1.2, 3, 9 + i % 4),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.9, g=18.0), az=math.degrees(ang), el=40)
        for i in range(5):  # petits éclats brillants projetés pendant l'apparition
            ang = r.uniform(0, 6.28)
            sp, vz = r.uniform(3.0, 6.0), r.uniform(7.0, 11.0)
            add_obj(ctx, f"{tag}_Spark{i}", M["spk"][i % 2], M["SPK%d" % (i % 2)], (0, 0, 0.5), fade(0.9, 2, 6 + i % 3),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.5, g=20.0), az=math.degrees(ang), el=60)
        for i in range(4):  # éclatement du cristal central
            ang = math.radians(90 * i + 20)
            ks = [(1, 0.001), (8, 0.001), (9, 1.4), (11, 0.9), (13, 0.001)]
            lk = [(fr, (math.cos(ang) * d, math.sin(ang) * d, 1.8 - 0.1 * d)) for fr, d in zip(range(8, 14), [0.2, 0.8, 2.0, 3.2, 4.0, 4.4])]
            add_obj(ctx, f"{tag}_Burst{i}", M["spark"][(i + 1) % 3], M["CRY%d" % ((i + 1) % 3)], (0, 0, 1.8), ks, az=math.degrees(ang), el=20, loc_keys=lk)
        for i in range(5):
            a = math.radians(20 + 72 * i)
            add_obj(ctx, f"{tag}_Rubble{i}", M["rubble"][i % 2], M["ROCKD" if i % 2 == 0 else "ROCKL"], (1.5 * math.cos(a), 1.5 * math.sin(a), 0.25), [(1, 0.001), (3, 0.9 + 0.2 * (i % 3)), (8, 0.9 + 0.2 * (i % 3)), (10, 0.001)])
        for g in range(3):
            a = math.radians(60 + 120 * g)
            add_obj(ctx, f"{tag}_Glint{g}", M["star"], M["CRY%d" % (g % 3)], (1.2 * math.cos(a), 1.2 * math.sin(a), 1.2), [(1, 0.001), (7, 0.001), (8, 1.0), (9, 0.4), (10, 0.9), (11, 0.001)],
                    loc_keys=[(fr, (1.2 * math.cos(a) * (1 + 0.08 * (fr - 7)), 1.2 * math.sin(a) * (1 + 0.08 * (fr - 7)), 1.2 + 0.2 * (fr - 7))) for fr in range(7, 12)], tumble=True)
    else:
        t = 2 if kind == "segment" else 3
        crack_pair(ctx, tag, M, (-2.0, 0.0), 0, t, 4.0, 0 if kind == "segment" else 1, t + 6)
        if kind == "segment":
            spec = [(-1.2, 0.35, 90, 1.3, 0), (0.0, -0.4, -90, 1.8, 1), (1.2, 0.3, 90, 1.5, 2)]
        else:
            spec = [(-0.6, 0.4, 90, 1.6, 0), (0.0, -0.4, -90, 2.1, 1), (0.8, 0.0, 0, 2.5, 2)]
        for i, (x, y, az, ln, ci) in enumerate(spec):
            gem(ctx, tag, i, M, ci, (x, y, 0.0), ln, t + i, t + 7 + i, az, 66 if i < 2 or kind == "segment" else 82, facet=(i == 1), trans=(kind == "segment" and i == 2))
        if kind == "end":
            pulse_ring(f"{tag}_Ring0", ctx, M, M["RINGA"], (0.3, 0, 0.1), 3, 1.3, "hex")
        add_obj(ctx, f"{tag}_Rubble0", M["rubble"][0], M["ROCKD"], (0.4, 0.2, 0.25), [(1, 0.001), (t + 1, 0.9), (t + 6, 0.9), (t + 8, 0.001)])
        for n in range(2):
            ang = r.uniform(-0.5, 0.5)
            sp, vz = r.uniform(5.0, 8.0), r.uniform(3.0, 6.0)
            add_obj(ctx, f"{tag}_Shard{n}", M["spark"][n % 3], M["CRY%d" % (n % 3)], (0, 0, 0.7), fade(1.0, 2, 8 + n),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.7, g=18.0), az=math.degrees(ang), el=40)
        sa = r.uniform(-0.4, 0.4)
        add_obj(ctx, f"{tag}_Spark0", M["spk"][0], M["SPK0"], (0, 0, 0.5), fade(0.8, t, t + 4),
                loc_keys=ballistic((5.0 * math.cos(sa), 5.0 * math.sin(sa), 8.0), 0.5, g=20.0), az=math.degrees(sa), el=60)

def build():
    M = {"CRY%d" % i: make_gem("CRY%d" % i, hx) for i, hx in enumerate(CRY)}
    # facettes plus lumineuses : émission renforcée sur les gemmes
    for i in range(3):
        b = M["CRY%d" % i].node_tree.nodes.get("Principled BSDF")
        b.inputs["Emission Strength"].default_value = 1.1
    M["CRYT"] = make_glow("CRYT", "#E060FF", 0.8)
    M["FACET"] = make_neon("FACET", "#F6E8FF")
    M["SPK0"] = make_neon("SPK0", "#FFF4FF")
    M["SPK1"] = make_neon("SPK1", "#FF9CF0")
    M["FLASH"] = make_neon("FLASH", "#F2E2FF")
    M["RINGA"] = make_neon("RINGA", "#C98CFF")
    M["CRACKC"] = make_neon("CRACKC", "#E65CFF")
    M["GLOW"] = make_glow("GLOW", GLOWC, 0.3)
    M["ROCKD"] = make_rock("ROCKD", "#2A1850")
    M["ROCKL"] = make_rock("ROCKL", "#A982F0")
    M["prism"] = [crystal_prism("E12_Gem%d" % i, r=0.30 + 0.02 * i, twist=0.2 * i) for i in range(3)] + [crystal_prism("E12_GemT", r=0.32, twist=0.1)]
    M["facet"] = [facet_mesh("E12_Facet%d" % i, r=0.30 + 0.02 * i) for i in range(3)]
    M["spark"] = [spark_mesh("E12_Shard%d" % i) for i in range(3)]
    M["spk"] = [spark_mesh("E12_Spark%d" % i) for i in range(2)]
    M["star"] = star_mesh("E12_Star")
    M["hex"] = ring_mesh("E12_Hex", r0=0.95, r1=1.0, h=0.04, seg=12)
    M["crack"] = [crack_mesh("E12_Crack%d" % i, 11 + i, 4.0, 0.12) for i in range(2)]
    M["crackD"] = [crack_mesh("E12_CrackD%d" % i, 11 + i, 4.0, 0.2) for i in range(2)]
    M["halo"] = blob_mesh("E12_Halo", 1.0, 0.12, 0.08, 14, 1)
    M["flash"] = blob_mesh("E12_Flash", 0.7, 0.85, 0.5, 33, 2)
    M["rubble"] = [blob_mesh("E12_Rubble%d" % i, 0.5, 0.65, 0.3, 21 + i, 1) for i in range(2)]
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
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E12_Cristal")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E12_Cristal_v2.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E12")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11)), ("CAM_Game", (5, 9))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v2_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E12_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
