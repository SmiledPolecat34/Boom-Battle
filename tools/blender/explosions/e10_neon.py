"""E10 Néon (base e09) (référence : Explosions_32.png, rangée 2, 1re carte) : gerbe de lames aux 7 couleurs de l'arc-en-ciel autour d'un cœur blanc, flash bref,
confettis colorés projetés, petits nuages violets / roses / bleus au pied. Lecture en croix conservée (lames dans le sens des bras).
Briques composables (CENTER, SEGMENT, END ; 4 directions). Pilotage (Blender, E01_Classique_v2.blend ouvert) :
    E09_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Écrit E09_ArcEnCiel_v3.blend à côté ; E01_Classique_v2.blend n'est jamais écrasé.
"""
import bpy, math, os, random

NEON = ["#FF2BD6", "#FF4FE8", "#B03BFF", "#E83DFF"]  # magenta, rose vif, violet, rose-violet (plus de blanc délavé)
RAINBOW = NEON
PUFF = ["#7A1F8F", "#A02BB0", "#5E1A78"]  # gravats sombres
RING_A, RING_B = "#FF3DE0", "#C94BFF"
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

def crystal_mesh(name):
    # éclat cristallin facetté à tête de flèche (4 faces), pointe vers +X
    secs = [(0.12, 0.12, 0.12), (0.5, 0.2, 0.2), (0.78, 0.09, 0.09)]
    v = [(0, 0, 0)]
    for x, w, h in secs:
        v += [(x, -w, 0), (x, 0, h), (x, w, 0), (x, 0, -h)]
    v.append((1.0, 0, 0))
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

def blink(keys, off_frames):
    # clignotement néon : coupe l'objet sur certaines images
    out = []
    for fr, s in keys:
        out.append((fr, 0.001 if fr in off_frames else s))
    return out

def make_glow(key, hx, alpha=0.32):
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

def pulse_ring(name, ctx, M, mat, loc, start, rmax):
    # IMPULSION néon : anneau fin qui part vite du centre, grossit, s'amincit puis disparaît (aucune tenue statique)
    k = [(1, (0.001, 0.001, 0.001)), (start, (rmax * 0.15, rmax * 0.15, 1.0)), (start + 1, (rmax * 0.55, rmax * 0.55, 1.0)), (start + 2, (rmax * 0.85, rmax * 0.85, 0.7)),
         (start + 3, (rmax, rmax, 0.3)), (start + 4, (0.001, 0.001, 0.001))]
    add_obj(ctx, name, M["ring"], mat, loc, k)

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        # énergie : flash blanc très bref + noyau magenta qui pulse
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 1.8), (3, 1.0), (4, 0.3), (5, 0.001)], az=20)
        add_obj(ctx, f"{tag}_Core", M["core"], M["C0"], (0, 0, 0.6), [(1, 0.001), (2, 0.9), (3, 1.7), (4, 1.2), (5, 1.8), (6, 1.1), (7, 1.5), (8, 0.8), (9, 0.4), (10, 0.001)], az=0)
        # trois impulsions d'anneau successives
        for i, (st, rm) in enumerate(((2, 2.3), (3, 2.0), (4, 1.6))):
            pulse_ring(f"{tag}_Ring{i}", ctx, M, M["RINGA"] if i != 1 else M["RINGB"], (0, 0, 0.1 + 0.02 * i), st, rm)
        # rayons d'énergie au ras du sol (6) : lignes néon qui clignotent
        for i in range(6):
            az = 60.0 * i + 15
            ks = [(1, (0.001, 0.001, 0.001)), (2, (0.2, 0.6, 0.6)), (3, (0.55, 0.6, 0.6)), (4, (0.5, 0.6, 0.6)), (5, (0.001, 0.001, 0.001) if i % 2 else (0.5, 0.6, 0.6)),
                  (6, (0.5, 0.6, 0.6) if i % 2 else (0.001, 0.001, 0.001)), (7, (0.4, 0.5, 0.5)), (8, (0.3, 0.3, 0.3)), (9, (0.001, 0.001, 0.001))]
            add_obj(ctx, f"{tag}_Beam{i}", M["strip"][i % 4], M["C%d" % (i % 4)], (0.3 * math.cos(math.radians(az)), 0.3 * math.sin(math.radians(az)), 0.4), ks, az=az, el=10 + 6 * (i % 2))
        n = 6  # éclats cristallins : moins nombreux, plus courts
        for i in range(n):
            az = 360.0 * i / n + 25
            el = 40 + 14 * (i % 2)
            ln = 1.5 + 0.3 * (i % 2)
            add_obj(ctx, f"{tag}_Shard{i}", M["crystal"][i % 4], M["C%d" % (i % 4)], (0.5 * math.cos(math.radians(az)), 0.5 * math.sin(math.radians(az)), 0.3),
                    pop(ln, 3 + (i % 2), ph=i * 1.3, end=9 + (i % 3), wob=0.10), az=az, el=el, jit=6, drift=10, roll=(i * 70) % 360)
        for i in range(2):  # gravats sombres
            a = math.radians(60 + 180 * i)
            add_obj(ctx, f"{tag}_Rubble{i}", M["puffs"][i], M["PUFF%d" % i], (1.4 * math.cos(a), 1.4 * math.sin(a), 0.3), [(1, 0.001), (3, 0.8), (7, 0.8), (9, 0.001)])
        for g in range(2):  # étincelles néon en fin d'animation
            a = math.radians(100 + 160 * g)
            add_obj(ctx, f"{tag}_Glint{g}", M["spark"][(g * 2 + 1) % 4], M["C%d" % ((g * 2 + 1) % 4)], (1.1 * math.cos(a), 1.1 * math.sin(a), 0.9),
                    [(1, 0.001), (6, 0.001), (7, 1.0), (8, 0.4), (9, 0.9), (10, 0.3), (11, 0.001)], az=math.degrees(a), el=50,
                    loc_keys=[(fr, (1.1 * math.cos(a) * (1 + 0.07 * (fr - 6)), 1.1 * math.sin(a) * (1 + 0.07 * (fr - 6)), 0.9 + 0.2 * (fr - 6))) for fr in range(6, 12)])
        ndia = 4
    else:
        L = 1.0 if kind == "segment" else 0.75
        t = 2 if kind == "segment" else 3  # image d'arrivée de l'onde dans la brique
        for k, ci in enumerate((0, 1)):  # deux lignes néon droites qui clignotent
            yy = (-0.45, 0.45)[k]
            off = (t + 3,) if k == 0 else (t + 4,)
            base = [(1, (0.001, 1, 1)), (t, (0.4 * L, 1, 1)), (t + 1, (L, 1, 1)), (t + 2, (L, 1, 1)), (t + 3, (L, 1, 1)), (t + 4, (L, 1, 1)), (t + 5, (L, 0.6, 0.6)), (t + 6, (L, 0.3, 0.3)), (t + 7, (L, 0.001, 0.001))]
            ks = [(fr, (0.001, 0.001, 0.001) if fr in off else sv) for fr, sv in base]
            add_obj(ctx, f"{tag}_Line{k}", M["strip"][ci], M["C%d" % ci], (-2.0, yy, 0.1), ks)
        # rémanence : halo translucide large sous les lignes, qui persiste un peu plus longtemps
        gk = [(1, (0.001, 1, 1)), (t, (0.4 * L, 1, 1)), (t + 1, (L, 1, 1)), (t + 4, (L, 1, 1)), (t + 6, (L, 0.7, 1)), (t + 8, (L, 0.001, 1))]
        add_obj(ctx, f"{tag}_Trail", M["glow"], M["GLOW"], (-2.0, 0.0, 0.06), gk)
        if kind == "segment":
            for i, (az, el, ln) in enumerate([(-26, 46, 1.4), (26, 46, 1.4)]):
                add_obj(ctx, f"{tag}_Shard{i}", M["crystal"][(i + 2) % 4], M["C%d" % ((i + 2) % 4)], (0, 0, 0.3), pop(ln, 3, ph=i * 1.4, end=9 + (i % 3), wob=0.1), az=az, el=el, jit=6, roll=i * 80)
            ndia = 2
        else:
            pulse_ring(f"{tag}_Ring0", ctx, M, M["RINGA"], (0.3, 0, 0.1), 4, 1.3)
            for i, (az, el, ln) in enumerate([(-25, 44, 1.3), (25, 44, 1.3)]):
                add_obj(ctx, f"{tag}_Shard{i}", M["crystal"][(i + 2) % 4], M["C%d" % ((i + 2) % 4)], (0, 0, 0.3), pop(ln, 4, ph=i * 1.2, end=10 + (i % 3), wob=0.1), az=az, el=el, jit=6, roll=i * 80)
            ndia = 3
        add_obj(ctx, f"{tag}_Rubble0", M["puffs"][1], M["PUFF1"], (0.3, 0, 0.3), [(1, 0.001), (t + 1, 0.7), (t + 5, 0.7), (t + 8, 0.001)])
    for n in range(ndia):  # petits losanges de néon projetés
        ang = r.uniform(0, 6.28) if kind == "center" else r.uniform(-0.6, 0.6)
        sp, vz = r.uniform(4.0, 7.0), r.uniform(4.0, 8.0)
        add_obj(ctx, f"{tag}_Spark{n}", M["spark"][n % 4], M["C%d" % (n % 4)], (0, 0, 0.6), fade(1.0, 2, 8 + (n % 4)),
                loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.6), az=math.degrees(ang), el=30, tumble=False)

def build():
    M = {"C%d" % i: make_neon("C%d" % i, hx) for i, hx in enumerate(NEON)}
    M["FLASH"] = make_neon("FLASH", "#FFF0FF")
    M["RINGA"] = make_neon("RINGA", RING_A)
    M["RINGB"] = make_neon("RINGB", RING_B)
    M["GLOW"] = make_glow("GLOW", "#FF2BD6")
    M["glow"] = glow_mesh("E10_Glow")
    M["core"] = blob_mesh("E10_Core", 0.55, 0.8, 0.15, 55, 2)
    for i, hx in enumerate(PUFF):
        M["PUFF%d" % i] = make_puff("PUFF%d" % i, hx)
    M["crystal"] = [crystal_mesh("E10_Crystal%d" % i) for i in range(4)]
    M["spark"] = [spark_mesh("E10_Spark%d" % i) for i in range(4)]
    M["strip"] = [strip_mesh("E10_Line%d" % i, phase=0.0, n=2, amp=0.0) for i in range(4)]
    M["ring"] = ring_mesh("E10_Ring")
    M["puffs"] = [blob_mesh("E10_Rubble%d" % i, 0.55, 0.6, 0.25, 41 + i, 1) for i in range(3)]
    M["flash"] = blob_mesh("E10_Flash", 0.7, 0.85, 0.5, 33, 2)
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
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E10_Neon")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E10_Neon_v2.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E10")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11)), ("CAM_Game", (4, 8))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v2_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E10_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
