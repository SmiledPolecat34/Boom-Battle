"""E11 Météore (base e09/e10) (référence : Explosions_32.png, rangée 2, 1re carte) : gerbe de lames aux 7 couleurs de l'arc-en-ciel autour d'un cœur blanc, flash bref,
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

DESC = 6      # images de descente avant l'impact (le serveur déclenche à l'image DESC+1)
IMP = DESC - 1  # décalage de la chronologie "après impact" (image locale 2 = flash = image globale DESC+1)

def make_rock(key, hx):
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.85
    b.inputs["Emission Color"].default_value = hex_lin("#FF5A10")
    b.inputs["Emission Strength"].default_value = 0.22
    return m

def make_glow(key, hx, alpha=0.35):
    m = bpy.data.materials["E01_Smoke"].copy()
    m.name = "E09_" + key
    set_color(m, hx)
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Alpha"].default_value = alpha
    return m

def glow_mesh(name, length=4.0, w=0.55, h=0.02):
    v = [(0, -w, -h), (length, -w, -h), (length, w, -h), (0, w, -h), (0, -w, h), (length, -w, h), (length, w, h), (0, w, h)]
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return mk(name, v, f)

def crack_mesh(name, polylines, w=0.09, h=0.04):
    # fissures de lave : polylignes en zigzag, chaque segment est une petite barre plate posée au sol
    v, f = [], []
    for pl in polylines:
        for (ax, ay), (bx, by) in zip(pl[:-1], pl[1:]):
            dx, dy = bx - ax, by - ay
            ln = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / ln * w, dx / ln * w
            b0 = len(v)
            for (px, py) in ((ax, ay), (bx, by)):
                v += [(px - nx, py - ny, -h), (px + nx, py + ny, -h), (px + nx, py + ny, h), (px - nx, py - ny, h)]
            for k in range(4):
                k2 = (k + 1) % 4
                f.append((b0 + k, b0 + 4 + k, b0 + 4 + k2, b0 + k2))
            f.append((b0, b0 + 3, b0 + 2, b0 + 1))
            f.append((b0 + 4, b0 + 5, b0 + 6, b0 + 7))
    return mk(name, v, f)

def pulse_ring(name, ctx, M, mat, loc, start, rmax):
    k = [(1, (0.001, 0.001, 0.001)), (start, (rmax * 0.2, rmax * 0.2, 1.0)), (start + 1, (rmax * 0.6, rmax * 0.6, 1.0)), (start + 2, (rmax * 0.9, rmax * 0.9, 0.7)),
         (start + 3, (rmax, rmax, 0.3)), (start + 4, (0.001, 0.001, 0.001))]
    add_obj(ctx, name, M["ring"], mat, loc, k)

def path(f):
    # trajectoire du météore (images globales 1..DESC) : chute rapide en diagonale vers la case centrale
    zs = [24.0, 18.0, 12.0, 7.0, 3.2, 1.0]
    xs = [-6.0, -4.8, -3.4, -2.0, -0.8, 0.0]
    i = max(1, min(DESC, f)) - 1
    return (xs[i], 0.0, zs[i])

FRAG_DIRS = [0, 90, 180, 270, 45, 225]

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        D = Ctx(ctx.coll, "E", 0.0, 0)        # descente (images globales)
        C = Ctx(ctx.coll, "E", 0.0, IMP)      # après impact (image locale 2 = impact)
        # --- 1) descente : 6 blocs de roche sombre autour d'un coeur de lave visible dans les interstices
        offs = [(0.62, 0, 0), (-0.62, 0, 0), (0, 0.62, 0), (0, -0.62, 0), (0, 0, 0.62), (0, 0, -0.62)]
        for i, o in enumerate(offs):
            lk = []
            for fr in range(1, DESC + 1):
                px, py, pz = path(fr)
                lk.append((fr, (px + o[0] * 1.3, py + o[1] * 1.3, pz + o[2] * 1.3)))
            ang = math.radians(FRAG_DIRS[i])
            for fr in range(DESC + 1, 17):  # à l'impact le météore éclate : les blocs partent dans les directions de la croix
                t = (fr - DESC) / 24.0
                sp = 19.0 if i < 4 else 9.0
                vz = 6.5 if i < 4 else 9.0
                z = 0.9 + vz * t - 0.5 * 18.0 * t * t
                lk.append((fr, (sp * t * math.cos(ang), sp * t * math.sin(ang), max(0.45, z))))
            ks = [(1, 1.35), (DESC, 1.35), (DESC + 1, 1.15), (DESC + 4, 1.0), (13, 0.8), (14, 0.5), (15, 0.2), (16, 0.001)]
            add_obj(ctx, f"{tag}_Chunk{i}", M["chunks"][i % 2], M["ROCK%d" % (i % 2)], path(1), ks, loc_keys=lk, tumble=True)
        lk = [(fr, path(fr)) for fr in range(1, DESC + 1)] + [(DESC + 1, (0, 0, 1.0)), (DESC + 8, (0, 0, 0.9))]
        add_obj(ctx, f"{tag}_Core", M["core"], M["F0"], path(1), [(1, 1.5), (DESC, 1.5), (DESC + 1, 2.0), (DESC + 2, 1.4), (DESC + 4, 1.1), (DESC + 6, 0.6), (DESC + 8, 0.001)], loc_keys=lk)
        # --- 2) traînée : flammes (le long du chemin, derrière le météore), braises, fumée
        for k in range(4):
            lk = [(fr, tuple(a + b for a, b in zip(path(fr - 1 - (k % 2)), (0.0, 0.25 * (k - 1.5), 0.6 * k)))) for fr in range(2, DESC + 1)]
            add_obj(ctx, f"{tag}_Trail{k}", M["blade"][k % 3], M["F%d" % (k % 3)], lk[0][1], [(1, 0.001), (2, 2.6 - 0.3 * k), (DESC, 3.0 - 0.3 * k), (DESC + 1, 0.001)],
                    az=180, el=72, jit=4, loc_keys=lk)
        for k in range(3):
            px, py, pz = path(2 + k)
            add_obj(ctx, f"{tag}_Smoke{k}", M["puff"], M["SMOKE"], (px, py, pz), [(1, 0.001), (2 + k, 0.35), (DESC + 1, 0.8), (DESC + 3, 1.0), (DESC + 5, 0.001)])
        for k in range(3):
            lk = [(fr, (path(fr)[0] - 0.4 * k, 0.3 * (k - 1), path(fr)[2] + 0.8 + 0.5 * k - 0.15 * max(0, fr - 2) * k)) for fr in range(2, DESC + 1)]
            add_obj(ctx, f"{tag}_TEmber{k}", M["spark"][k % 2], M["F%d" % (k % 2)], lk[0][1], [(1, 0.001), (2, 1.0), (DESC, 1.0), (DESC + 1, 0.001)], az=180, el=60, loc_keys=lk)
        # --- 3) impact : flash jaune-orange, onde de choc, fissures de lave
        add_obj(C, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 2.8), (3, 1.7), (4, 0.7), (5, 0.001)], az=20)
        pulse_ring(f"{tag}_Ring0", ctx.__class__(ctx.coll, "E", 0.0, IMP), M, M["RINGA"], (0, 0, 0.1), 2, 2.6)
        pulse_ring(f"{tag}_Ring1", ctx.__class__(ctx.coll, "E", 0.0, IMP), M, M["RINGB"], (0, 0, 0.12), 3, 2.1)
        ck = [(1, 0.001), (2, 0.35), (3, 1.0), (4, 1.15), (7, 1.0), (10, 0.8), (12, 0.5), (14, 0.001)]
        add_obj(C, f"{tag}_Cracks", M["crack_star"], M["F0"], (0, 0, 0.07), ck, az=r.uniform(0, 60))
        # --- 4) éjectas : fragments de lave et braises dans les 4 directions de la croix
        for i in range(4):
            ang = math.radians(90 * i + r.uniform(-8, 8))
            sp, vz = r.uniform(7.0, 10.0), r.uniform(4.0, 7.0)
            add_obj(C, f"{tag}_Lava{i}", M["lavafrag"], M["F0"], (0, 0, 0.9), fade(1.0, 2, 10 + i % 3),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.9, g=18.0), tumble=True)
        nember = 6
    else:
        L = 1.0 if kind == "segment" else 0.75
        t = 2 if kind == "segment" else 3
        # fissures incandescentes temporaires sur la case + halo de chaleur translucide
        ck = [(1, (0.001, 0.001, 0.001)), (t, (0.3 * L, 1, 1)), (t + 1, (L, 1.5, 1)), (t + 2, (L, 1.0, 1)), (t + 6, (L, 0.9, 1)), (t + 9, (L, 0.5, 0.5)), (t + 11, (L, 0.001, 0.001))]
        add_obj(ctx, f"{tag}_Cracks", M["crack_seg" if kind == "segment" else "crack_end"], M["F0"], (-2.0, 0.0, 0.07), ck)
        gk = [(1, (0.001, 1, 1)), (t, (0.4 * L, 1, 1)), (t + 1, (L, 1, 1)), (t + 4, (L, 1, 1)), (t + 7, (L, 0.6, 1)), (t + 9, (L, 0.001, 1))]
        add_obj(ctx, f"{tag}_Trail", M["glow"], M["GLOW"], (-2.0, 0.0, 0.05), gk)
        if kind == "end":
            pulse_ring(f"{tag}_Ring0", ctx, M, M["RINGB"], (0.2, 0, 0.1), 3, 1.4)
        ang = r.uniform(-0.3, 0.3)
        sp, vz = r.uniform(6.0, 8.0), r.uniform(4.0, 6.0)
        add_obj(ctx, f"{tag}_Rock0", M["frag"][0], M["ROCK0"], (0, 0, 0.7), fade(1.0, 2, 9),
                loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.7, g=18.0), tumble=True)
        add_obj(ctx, f"{tag}_Lava0", M["lavafrag"], M["F0"], (0, 0, 0.7), fade(0.8, 2, 8),
                loc_keys=ballistic((sp * 0.8 * math.cos(-ang), sp * 0.8 * math.sin(-ang), vz * 1.2), 0.7, g=18.0), tumble=True)
        nember = 2
    for n in range(nember):  # braises
        ang = r.uniform(0, 6.28) if kind == "center" else r.uniform(-0.6, 0.6)
        sp, vz = r.uniform(4.0, 8.0), r.uniform(4.0, 8.0)
        c = ctx if kind != "center" else Ctx(ctx.coll, "E", 0.0, IMP)
        add_obj(c, f"{tag}_Ember{n}", M["spark"][n % 2], M["F%d" % (n % 2)], (0, 0, 0.6), fade(1.0, 2, 8 + (n % 4)),
                loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.6), az=math.degrees(ang), el=30)

def zig(a, b, n=5, amp=0.16):
    pts = [a]
    for i in range(1, n):
        t = i / n
        x = a[0] + (b[0] - a[0]) * t
        y = a[1] + (b[1] - a[1]) * t
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        o = amp * (1 if i % 2 else -1)
        pts.append((x - dy / ln * o, y + dx / ln * o))
    pts.append(b)
    return pts

def build():
    M = {"F%d" % i: make_neon("F%d" % i, hx) for i, hx in enumerate(FLAME)}
    M["FLASH"] = make_neon("FLASH", "#FFE27A")
    M["RINGA"] = make_neon("RINGA", RING_A)
    M["RINGB"] = make_neon("RINGB", RING_B)
    M["GLOW"] = make_glow("GLOW", "#FF8A1E", 0.30)
    M["SMOKE"] = make_glow("SMOKE", "#4A423D", 0.38)
    for i, hx in enumerate(ROCK):
        M["ROCK%d" % i] = make_rock("ROCK%d" % i, hx)
    M["blade"] = [blade_mesh("E11_Flame%d" % i) for i in range(3)]
    M["spark"] = [spark_mesh("E11_Ember%d" % i) for i in range(2)]
    M["ring"] = ring_mesh("E11_Ring")
    M["glow"] = glow_mesh("E11_Heat")
    M["core"] = blob_mesh("E11_LavaCore", 0.85, 0.95, 0.10, 61, 2)
    M["flash"] = blob_mesh("E11_Flash", 0.7, 0.85, 0.5, 33, 2)
    M["chunks"] = [blob_mesh("E11_Chunk%d" % i, 0.62, 0.85, 0.22, 71 + i, 1) for i in range(2)]
    M["frag"] = [blob_mesh("E11_Frag%d" % i, 0.34, 0.8, 0.28, 81 + i, 1) for i in range(2)]
    M["lavafrag"] = blob_mesh("E11_LavaFrag", 0.26, 0.85, 0.25, 85, 1)
    M["puff"] = blob_mesh("E11_Smoke", 0.9, 0.85, 0.2, 87, 1)
    M["crack_seg"] = crack_mesh("E11_CrackSeg", [zig((0, 0), (4, 0), 7), zig((1.4, -0.1), (1.9, -0.75), 3), zig((2.4, 0.1), (2.9, 0.7), 3), zig((3.1, -0.1), (3.6, -0.7), 3)])
    M["crack_end"] = crack_mesh("E11_CrackEnd", [zig((0, 0), (3.0, 0), 6), zig((1.2, 0.0), (1.7, 0.7), 3), zig((2.0, 0.0), (2.4, -0.65), 3)])
    rays = []
    for i in range(6):
        a = math.radians(60 * i)
        e = (2.0 * math.cos(a), 2.0 * math.sin(a))
        rays.append(zig((0, 0), e, 5))
        m = (1.0 * math.cos(a), 1.0 * math.sin(a))
        b = math.radians(60 * i + (28 if i % 2 else -28))
        rays.append(zig(m, (m[0] + 0.7 * math.cos(b), m[1] + 0.7 * math.sin(b)), 3))
    M["crack_star"] = crack_mesh("E11_CrackStar", rays)
    for cn in ["E01_CENTER"] + ["E01_SEG1_" + d for d in ARMS] + ["E01_END_" + d for d in ARMS]:
        for o in list(bpy.data.collections[cn].objects):
            bpy.data.objects.remove(o)
    COUNTS.clear()
    build_brick(Ctx(bpy.data.collections["E01_CENTER"], "E", 0.0, 0), "center", M)
    for d in ARMS:
        build_brick(Ctx(bpy.data.collections["E01_SEG1_" + d], d, CELL, IMP + 1), "segment", M)
        build_brick(Ctx(bpy.data.collections["E01_END_" + d], d, 2 * CELL, IMP + 2), "end", M)
    bpy.context.scene.frame_end = 24
    tri = {cn: len([o for o in bpy.data.collections[cn].objects if o.type == "MESH"]) for cn in ("E01_CENTER", "E01_SEG1_E", "E01_END_E")}
    print("OBJETS par brique :", tri)
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E11_Meteore")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E11_Meteore_v2.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E11")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Game", (2, 4, 6)), ("CAM_Close", (6, 7, 8, 9, 11, 14, 17)), ("CAM_Game", (9, 12))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v2_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E11_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
