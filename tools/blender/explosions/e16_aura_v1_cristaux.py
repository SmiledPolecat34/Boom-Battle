"""E16 Aura (reference : Explosions_32.png, rangee 2, carte Aura) : couronne de lames sombres indigo qui jaillit d'un coeur violet lumineux, anneaux d'aura
neon magenta/violet en tirets autour de la base, debris sombres flottants, etincelles violettes. Briques CENTER / SEGMENT / END (4 directions).
Pilotage (Blender, E01_Classique_v2.blend ouvert) : E16_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Ecrit E16_Aura_v1.blend a cote ; E01_Classique_v2.blend n'est jamais ecrase.
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

def arc_mesh(name="E09_Arc", half=16.0, r0=0.95, r1=1.0, h=0.06, seg=6):
    # arc plat et fin (onde de choc) : n'existe QUE dans l'axe d'un bras (+-16 deg), jamais sur les diagonales
    prof = [(r0, -h), (r1, -h), (r1, h), (r0, h)]
    v, f = [], []
    for s_ in range(seg + 1):
        a = math.radians(-half + 2 * half * s_ / seg)
        for r, z in prof:
            v.append((r * math.cos(a), r * math.sin(a), z))
    for s_ in range(seg):
        for k in range(4):
            k2 = (k + 1) % 4
            f.append((s_ * 4 + k, (s_ + 1) * 4 + k, (s_ + 1) * 4 + k2, s_ * 4 + k2))
    f.append((0, 3, 2, 1))
    f.append((seg * 4, seg * 4 + 1, seg * 4 + 2, seg * 4 + 3))
    return mk(name, v, f)

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

DARK, DEEP, VIOLET, MAGENTA = "#2E1458", "#3A1670", "#8E3CFF", "#FF4DE6"

def make_cloud(key, hx, emi=0.14, alpha=1.0):
    # alpha < 1 : matériau translucide (copie de E01_Smoke) -> Transparency Roblox = 1 - alpha
    if alpha >= 0.999:
        m = bpy.data.materials.new("E09_" + key)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = hex_lin(hx)
        b.inputs["Roughness"].default_value = 0.9
        b.inputs["Emission Color"].default_value = hex_lin(hx)
        b.inputs["Emission Strength"].default_value = emi
        return m
    m = bpy.data.materials["E01_Smoke"].copy()
    m.name = "E09_" + key
    set_color(m, hx)
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Alpha"].default_value = alpha
            n.inputs["Roughness"].default_value = 0.9
            if "Emission Strength" in n.inputs:
                n.inputs["Emission Strength"].default_value = emi
    return m

def spike_mesh(name):
    # lame de flamme sombre (cristal effilé, légèrement décalée vers +X comme une flamme) : base au sol z=0, pointe z=1
    lv = [(0.0, 0.40, 0.12), (0.5, 0.32, 0.09), (0.8, 0.17, 0.045)]
    off = [0.0, 0.05, 0.10]
    v, f = [], []
    for (z, w, d), o in zip(lv, off):
        v += [(-w + o, -d, z), (w + o, -d, z), (w + o, d, z), (-w + o, d, z)]
    v.append((0.12, 0.0, 1.0))
    for lvl in range(2):
        a, b = 4 * lvl, 4 * (lvl + 1)
        for k in range(4):
            k2 = (k + 1) % 4
            f.append((a + k, a + k2, b + k2, b + k))
    t = 8
    tip = 12
    for k in range(4):
        f.append((t + k, t + (k + 1) % 4, tip))
    f.append((0, 3, 2, 1))
    return mk(name, v, f)

def dash_ring_mesh(name, n=6, r0=0.88, r1=1.0, h=0.05, fill=0.62, seg=3):
    # anneau d'aura en tirets (n arcs séparés par des vides) : la rotation se voit en vue de dessus
    prof = [(r0, -h), (r1, -h), (r1, h), (r0, h)]
    v, f = [], []
    for d in range(n):
        a0 = 2 * math.pi * d / n
        span = 2 * math.pi / n * fill
        base = len(v)
        for s_ in range(seg + 1):
            a = a0 + span * s_ / seg
            for r, z in prof:
                v.append((r * math.cos(a), r * math.sin(a), z))
        for s_ in range(seg):
            for k in range(4):
                k2 = (k + 1) % 4
                f.append((base + s_ * 4 + k, base + (s_ + 1) * 4 + k, base + (s_ + 1) * 4 + k2, base + s_ * 4 + k2))
        f.append((base, base + 3, base + 2, base + 1))
        e = base + seg * 4
        f.append((e, e + 1, e + 2, e + 3))
    return mk(name, v, f)

def disc_mesh(name, seg=12, h=0.04):
    v, f = [], []
    for s_ in range(seg):
        a = 2 * math.pi * s_ / seg
        v.append((math.cos(a), math.sin(a), h))
    v.append((0, 0, h))
    for s_ in range(seg):
        f.append((seg, s_, (s_ + 1) % seg))
    return mk(name, v, f)

def lerp_path(p0, p1, frames, ease=1.0):
    n = len(frames) - 1
    return [(fr, tuple(p0[j] + (p1[j] - p0[j]) * ((i / n) ** (1.0 / ease) if n else 1.0) for j in range(3))) for i, fr in enumerate(frames)]

def track(p0, p1, f0, f1, ease=1.5):
    return lerp_path(p0, p1, list(range(f0, f1 + 1)), ease)

def spike_keys(t0, w, h, hold, out, ph=0.0):
    # lame qui jaillit (dépassement), tient en vacillant légèrement, puis rétrécit vite jusqu'à disparaître
    k = [(1, 0.001)]
    if t0 - 1 > 1:
        k.append((t0 - 1, 0.001))
    k += [(t0, (0.35 * w, 0.35 * w, 0.2 * h)), (t0 + 1, (1.1 * w, 1.1 * w, 1.25 * h)), (t0 + 2, (w, w, h))]
    for i in range(1, hold + 1):
        fr = t0 + 2 + i
        k.append((fr, (w * (1 + 0.05 * math.sin(fr * 2 + ph)), w, h * (1 + 0.05 * math.sin(fr * 2.3 + ph)))))
    f1 = t0 + 2 + hold
    for i in range(1, out):
        u = i / out
        k.append((f1 + i, (w * (1 - 0.5 * u), w * (1 - 0.5 * u), h * (1 - u) ** 0.9)))
    k.append((f1 + out, 0.001))
    return k

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 1.8), (3, 0.5), (4, 0.001)], az=20)
        # disque d'aura translucide, contenu dans la case centrale (rayon <= 2)
        add_obj(ctx, f"{tag}_Disc", M["disc"], M["DISC"], (0, 0, 0.1),
                [(1, 0.001), (2, (1.0, 1.0, 1)), (3, (1.9, 1.9, 1)), (7, (2.0, 2.0, 1)), (10, (1.9, 1.9, 1)), (12, 0.001)])
        # coeur néon magenta au pied de la couronne
        add_obj(ctx, f"{tag}_Core", M["core"], M["CORE"], (0, 0, 0.2), [(1, 0.001), (2, (0.8, 0.8, 1)), (3, (1.3, 1.3, 1)), (8, (1.2, 1.2, 1)), (10, 0.001)])
        # couronne de lames sombres : une grande lame centrale + 6 lames inclinées vers l'extérieur
        add_obj(ctx, f"{tag}_Spike0", M["spike"], M["SPIKED"], (0, 0, 0.0), spike_keys(2, 0.95, 3.0, 4, 4), az=0, el=0)
        for i in range(6):
            phi = 60 * i + 30
            h = (2.0, 2.4, 1.8, 2.2, 1.7, 2.1)[i]
            add_obj(ctx, f"{tag}_Spike{i + 1}", M["spike"], M["SPIKED"], (0.35 * math.cos(math.radians(phi)), 0.35 * math.sin(math.radians(phi)), 0.0),
                    spike_keys(2 + i % 2, 0.7 + 0.08 * (i % 3), h, 3, 4, ph=i), az=phi - 180, el=24 + 4 * (i % 2))
        # coeur lumineux violet dans la couronne
        for i in range(3):
            phi = 120 * i + 60
            add_obj(ctx, f"{tag}_Glow{i}", M["spikeG"], M["GLOW"], (0.15 * math.cos(math.radians(phi)), 0.15 * math.sin(math.radians(phi)), 0.0),
                    spike_keys(3, 0.5, (1.8, 1.5, 1.4)[i], 2, 4, ph=i), az=phi - 180, el=12)
        # anneaux d'aura néon en tirets, contenus dans la case centrale, qui tournent en sens inverse
        add_obj(ctx, f"{tag}_RingA", M["ringA"], M["RINGA"], (0, 0, 0.3),
                [(1, 0.001), (2, (0.7, 0.7, 1)), (3, (1.4, 1.4, 1)), (4, (1.8, 1.8, 1)), (7, (1.9, 1.9, 1)), (9, (2.0, 2.0, 0.5)), (10, 0.001)], drift=220)
        add_obj(ctx, f"{tag}_RingB", M["ringB"], M["RINGB"], (0, 0, 0.45),
                [(1, 0.001), (2, 0.001), (3, (0.8, 0.8, 1)), (4, (1.4, 1.4, 1)), (5, (1.6, 1.6, 1)), (8, (1.7, 1.7, 1)), (10, (1.8, 1.8, 0.5)), (11, 0.001)], drift=-200)
        # débris sombres violets qui flottent (le long des axes des bras), étincelles violettes et particules lumineuses
        for i in range(4):
            ang = math.radians(90 * i + r.uniform(-18, 18))
            sp, vz = r.uniform(2.5, 4.5), r.uniform(3.0, 5.0)
            add_obj(ctx, f"{tag}_Rock{i}", M["rock"], M["ROCK"], (0, 0, 0.8), fade(1.1, 3, 12 + i % 2),
                    loc_keys=ballistic((sp * math.cos(ang), sp * math.sin(ang), vz), 0.8, steps=14, g=7.0), az=math.degrees(ang), el=30, tumble=True)
        for i, d in enumerate([0, 90, 180, 270, 45, 225]):
            a = math.radians(d if i < 4 else 0)
            up = i >= 4
            p1 = (0.0, 0.0, 4.0) if up else (6.0 * math.cos(a), 6.0 * math.sin(a), 1.2)
            add_obj(ctx, f"{tag}_Spark{i}", M["spark"], M["SPARK"], (0.4 * math.cos(a), 0.4 * math.sin(a), 0.6), fade(1.4, 3, 10),
                    loc_keys=track((0.4 * math.cos(a), 0.4 * math.sin(a), 0.6), p1, 3, 10, 1.6), az=(0 if up else d), el=(80 if up else 8))
        for i in range(4):
            a = math.radians(45 + 90 * i)
            add_obj(ctx, f"{tag}_Mote{i}", M["mote"], M["MOTE"], (0.6 * math.cos(a), 0.6 * math.sin(a), 0.5), fade(0.9, 3 + i % 2, 13),
                    loc_keys=track((0.6 * math.cos(a), 0.6 * math.sin(a), 0.5), (1.3 * math.cos(a), 1.3 * math.sin(a), 3.2), 3, 13, 1.2))
    else:
        t = 2 if kind == "segment" else 3
        big = 1.0 if kind == "segment" else 1.25
        add_obj(ctx, f"{tag}_Disc", M["disc"], M["DISC"], (0, 0, 0.1),
                [(1, 0.001), (t, (0.8, 0.8, 1)), (t + 1, (1.3, 1.3, 1)), (t + 4, (1.3, 1.3, 1)), (t + 6, 0.001)])
        # lames qui jaillissent l'une après l'autre dans le sens de la propagation, droites, face large tournée à 45° pour rester lisibles sur les 4 bras
        n_bl = 3 if kind == "segment" else 4
        for i in range(n_bl):
            x = -1.2 + 1.2 * i if kind == "segment" else -1.4 + 0.95 * i
            h = (1.4, 1.7, 1.4)[i] if kind == "segment" else (1.2, 1.5, 1.7, 2.2)[i]
            add_obj(ctx, f"{tag}_Blade{i}", M["spike"], M["SPIKED"], (x, (0.3, -0.4, 0.2, 0.0)[i], 0.0), spike_keys(t + i, 0.65 * big, h, 2, 3, ph=i), az=45, el=0)
        # front d'énergie : arc néon fin qui avance sur la case (dans l'axe du bras)
        add_obj(ctx, f"{tag}_Front", M["front"], M["FRONT"], (-3.6, 0, 0.3), [(1, 0.001), (t, (2.4, 2.4, 0.6)), (t + 3, (2.4, 2.4, 0.6)), (t + 5, 0.001)],
                loc_keys=track((-3.6, 0, 0.3), (-0.4, 0, 0.3), t, t + 5, 1.3))
        add_obj(ctx, f"{tag}_Spark0", M["spark"], M["SPARK"], (-1.5, 0.3, 0.6), fade(1.4, t, t + 7),
                loc_keys=track((-1.5, 0.3, 0.6), (3.0, 0.3, 1.0), t, t + 7, 1.5), az=0, el=6)
        add_obj(ctx, f"{tag}_Mote0", M["mote"], M["MOTE"], (0.0, 0.4, 0.5), fade(0.9, t + 1, t + 9),
                loc_keys=track((0.0, 0.4, 0.5), (0.6, 0.4, 2.8), t + 1, t + 9, 1.2))
        if kind == "end":
            ang = math.radians(r.uniform(-15, 15))
            add_obj(ctx, f"{tag}_Rock0", M["rock"], M["ROCK"], (0.5, 0.0, 0.6), fade(1.0, t + 1, t + 9),
                    loc_keys=ballistic((3.0 * math.cos(ang), 3.0 * math.sin(ang), 4.0), 0.6, steps=12, g=7.0), tumble=True)

def build():
    M = {"SPIKED": make_cloud("SPIKED", DARK, 0.28), "ROCK": make_cloud("ROCK", "#2B1B4A", 0.2), "DISC": make_cloud("DISC", "#5B2BD6", 0.7, 0.30)}
    M["FLASH"] = make_neon("FLASH", "#F2C8FF")
    M["CORE"] = make_neon("CORE", "#E040FF")
    M["GLOW"] = make_neon("GLOW", "#B04BFF")
    M["RINGA"] = make_neon("RINGA", MAGENTA)
    M["RINGB"] = make_neon("RINGB", "#8A5CFF")
    M["FRONT"] = make_neon("FRONT", "#C65CFF")
    M["SPARK"] = make_neon("SPARK", "#FF8CFF")
    M["MOTE"] = make_neon("MOTE", "#FFB0FF")
    M["spike"] = spike_mesh("E16_Spike")
    M["spikeG"] = spike_mesh("E16_SpikeG")
    M["ringA"] = dash_ring_mesh("E16_RingA", 6)
    M["ringB"] = dash_ring_mesh("E16_RingB", 8)
    M["front"] = arc_mesh("E16_Front", 16.0, 0.95, 1.0, 0.06, 6)
    M["disc"] = disc_mesh("E16_Disc")
    M["core"] = disc_mesh("E16_Core")
    M["rock"] = blob_mesh("E16_Rock", 0.35, 0.8, 0.35, 41, 1)
    M["spark"] = spark_mesh("E16_Spark")
    M["mote"] = blob_mesh("E16_Mote", 0.12, 0.9, 0.15, 51, 1)
    M["flash"] = blob_mesh("E16_Flash", 0.7, 0.85, 0.5, 33, 2)
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
    tot = 0
    for cn in ("E01_CENTER", "E01_SEG1_E", "E01_END_E"):
        ms = [o for o in bpy.data.collections[cn].objects if o.type == "MESH"]
        print(cn, "objets", len(ms), "translucides", len([o for o in ms if alpha_of(o) < 0.99]))
    print("triangles :", {k: len(m.polygons) for k, m in M.items() if hasattr(m, "polygons")})
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E16_Aura")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E16_Aura_v1.blend"))

def render():
    from mathutils import Vector
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E16")
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
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11)), ("CAM_Game", (5, 9)), ("CAM_Far", (4, 7, 10))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v1_%s_f%02d.png" % ({"CAM_Game": "game", "CAM_Far": "far"}.get(cam, "close"), f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E16_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
