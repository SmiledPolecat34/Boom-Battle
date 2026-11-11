"""E17 Eau V4 (reference : Explosions_32.png, rangee 3, carte Eau) : gouttes d'eau GEANTES qui tombent du ciel sur chaque case de la croix et eclatent.
Chute tres rapide (images 1 a 3) avec etirement, impact image 4 (aplatissement puis eclatement), couronne d'eclaboussures blanche/cyan, gouttelettes projetees,
petite onde liquide, ecume, traces d'eau temporaires. Centre : goutte plus grosse, grande couronne double, gerbe verticale, flash.
Briques CENTER / SEGMENT / END (4 directions). Aucune forme ne depasse la case (cases dangereuses uniquement).
Pilotage (Blender, E01_Classique_v2.blend ouvert) : E17_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Ecrit E17_Eau_v4.blend a cote ; E01_Classique_v2.blend n'est jamais ecrase.
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

def make_smoke(key, hx, alpha, emi=0.15):
    # translucide sombre (copie de E01_Smoke) : Transparency Roblox = 1 - alpha
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

def make_glow(key, hx, alpha, strength=1.4):
    # énergie lumineuse translucide : noeud Emission (=> Neon Roblox) + Principled (Alpha => Transparency) ; aperçu Blender = mélange Emission/Transparent
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = hex_lin(hx)
    em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = alpha
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    pb = nt.nodes.new("ShaderNodeBsdfPrincipled")
    pb.inputs["Base Color"].default_value = hex_lin(hx)
    pb.inputs["Alpha"].default_value = alpha
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    return m

def smooth(me):
    for p in me.polygons:
        p.use_smooth = True
    return me

def orb_mesh(name, seed, r=1.0, sub=3, noise=0.14, flat=1.0):
    # orbe d'énergie irrégulier, ombrage lisse (aucune arête dure)
    import bmesh
    from mathutils import Vector
    rr = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    ph = [rr.uniform(0, 6.28) for _ in range(3)]
    for v in bm.verts:
        x, y, z = v.co
        f = 1 + noise * math.sin(2.6 * x + ph[0] + 1.7 * y) * math.cos(2.2 * z + ph[1] + 1.3 * x) + 0.5 * noise * math.sin(4.1 * (y + z) + ph[2])
        v.co = Vector((x * f, y * f, z * f * flat))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return smooth(me)

def cross_mesh(name, K=5, N=48, h=0.35):
    # dôme d'énergie à 4 lobes dans l'axe des bras (+ : jamais de lobe sur les diagonales), bords ondulés, fermé
    v = [(0.0, 0.0, h)]
    f = []
    for k in range(1, K + 1):
        for i in range(N):
            th = 2 * math.pi * i / N
            c = abs(math.cos(2 * th))
            rr = (0.30 + 0.70 * c ** 1.2) * (1 + 0.05 * math.sin(7 * th + k)) * k / K
            z = h * (1 - (k / K) ** 2.2) * (0.6 + 0.4 * c) if k < K else 0.0
            v.append((rr * math.cos(th), rr * math.sin(th), z))
    for i in range(N):
        f.append((0, 1 + i, 1 + (i + 1) % N))
    for k in range(1, K):
        a, b = 1 + (k - 1) * N, 1 + k * N
        for i in range(N):
            j = (i + 1) % N
            f.append((a + i, b + i, b + j, a + j))
    cb = len(v)
    v.append((0.0, 0.0, 0.0))
    last = 1 + (K - 1) * N
    for i in range(N):
        f.append((cb, last + (i + 1) % N, last + i))
    return smooth(mk(name, v, f))

def tube_mesh(name, pts, ws, hs, flat=False):
    # ruban volumique (section en losange) le long d'une ligne médiane : sert aux vagues, volutes et éclairs
    n = len(pts)
    v, f = [], []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        L = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / L, tx / L
        w, h = ws[i], hs[i]
        v += [(p[0] + nx * w, p[1] + ny * w, p[2]), (p[0], p[1], p[2] + h), (p[0] - nx * w, p[1] - ny * w, p[2]), (p[0], p[1], p[2] - h)]
    for i in range(n - 1):
        for k in range(4):
            k2 = (k + 1) % 4
            f.append((4 * i + k, 4 * i + k2, 4 * (i + 1) + k2, 4 * (i + 1) + k))
    f.append((0, 3, 2, 1))
    e = 4 * (n - 1)
    f.append((e, e + 1, e + 2, e + 3))
    me = mk(name, v, f)
    return me if flat else smooth(me)

def wave_mesh(name, phase, width, amp, height, length=4.0, n=22, freq=1.35):
    # vague d'énergie : long ruban ondulant dans l'axe du bras, effilé aux deux bouts (se raccorde avec les briques voisines)
    pts, ws, hs = [], [], []
    for i in range(n + 1):
        t = i / n
        env = max(math.sin(math.pi * t) ** 0.7, 0.16)
        w = width * env * (0.82 + 0.18 * math.sin(5.0 * t + phase * 2))
        h = height * env * (0.7 + 0.3 * math.cos(4.0 * t + phase))
        pts.append((length * (t - 0.5), amp * math.sin(2 * math.pi * freq * t + phase) * env ** 0.5, h))
        ws.append(w)
        hs.append(h)
    return tube_mesh(name, pts, ws, hs, flat=True)

def wisp_mesh(name, turns, R=1.0, rise=0.9, W=0.2, n=20):
    # volute : spirale effilée qui s'élargit en montant
    pts, ws, hs = [], [], []
    for i in range(n + 1):
        t = i / n
        a = 2 * math.pi * turns * t
        rr = R * (0.25 + 0.75 * t)
        pts.append((rr * math.cos(a), rr * math.sin(a), 0.1 + rise * t))
        w = max(W * math.sin(math.pi * t) ** 0.8, 0.01)
        ws.append(w)
        hs.append(w * 0.6)
    return tube_mesh(name, pts, ws, hs)

def bolt_mesh(name, seed, L=2.2, n=8):
    # éclair fin en zigzag (à plat, dans l'axe du bras)
    rr = random.Random(seed)
    pts, ws, hs = [], [], []
    for i in range(n + 1):
        t = i / n
        y = 0.0 if i in (0, n) else rr.uniform(-0.3, 0.3)
        pts.append((L * t, y, 0.05))
        ws.append(0.05 if 0 < i < n else 0.01)
        hs.append(0.04 if 0 < i < n else 0.01)
    return tube_mesh(name, pts, ws, hs)

def lerp_path(p0, p1, frames, ease=1.0):
    n = len(frames) - 1
    return [(fr, tuple(p0[j] + (p1[j] - p0[j]) * ((i / n) ** (1.0 / ease) if n else 1.0) for j in range(3))) for i, fr in enumerate(frames)]

def track(p0, p1, f0, f1, ease=1.5):
    return lerp_path(p0, p1, list(range(f0, f1 + 1)), ease)

def pulse(f, amp=0.12, w=2.6, ph=0.0):
    return 1 + amp * math.sin(f * w + ph)

def p3(s, f, amp, w, ph=0.0, flat=1.0):
    # échelle qui "respire" différemment sur chaque axe (déformation vivante)
    return (s * pulse(f, amp, w, ph), s * pulse(f, amp, w * 1.17, ph + 1.1), s * flat * pulse(f, amp, w * 0.93, ph + 2.3))

def seq_keys(base_peak, f_start, hold_f, end_f, amp, w, ph=0.0, flat=1.0, swell=1.35):
    # gonfle brutalement (dépassement), pulse rapidement, puis se contracte jusqu'à disparaître
    k = [(1, 0.001), (f_start, base_peak * 0.35), (f_start + 1, base_peak * swell), (f_start + 2, p3(base_peak * 1.1, f_start + 2, amp, w, ph, flat))]
    for f in range(f_start + 3, hold_f + 1):
        k.append((f, p3(base_peak, f, amp, w, ph, flat)))
    n = end_f - hold_f
    for i in range(1, n):
        u = i / n
        k.append((hold_f + i, p3(base_peak * (1 - u) ** 0.8, hold_f + i, amp * 0.6, w, ph, flat)))
    k.append((end_f, 0.001))
    return k

def wave_flip(t0, hold, out, base, ph=0.0):
    # clés par image de la vague, avec "flipbook" : 2 maillages de phases opposées affichés une image sur deux -> les contours bougent
    seq = {}
    seq[t0] = (0.45 * base[0], 0.5 * base[1], 0.4 * base[2])
    seq[t0 + 1] = (1.0 * base[0], 1.25 * base[1], 1.2 * base[2])
    for i in range(2, 2 + hold):
        f = t0 + i
        seq[f] = (base[0], base[1] * pulse(f, 0.28, 2.7, ph), base[2] * pulse(f, 0.34, 3.1, ph))
    f1 = t0 + 2 + hold
    for i in range(1, out):
        u = i / out
        seq[f1 + i - 1] = (base[0] * (1 + 0.12 * u), base[1] * (1 - 0.55 * u), base[2] * (1 - 0.8 * u))
    last = f1 + out
    res = []
    for v in (0, 1):
        k = [(1, 0.001)]
        if t0 - 1 > 1:
            k.append((t0 - 1, 0.001))
        for f in sorted(seq):
            k.append((f, seq[f] if f % 2 == v else 0.001))
        k.append((last, 0.001))
        res.append(k)
    return res, last

def wave_loc(t, last, ph):
    # la vague avance puis ondule de façon instable (léger balancement latéral différent à chaque image)
    k = []
    for f in range(t, last + 1):
        u = min((f - t) / 3.0, 1.0)
        k.append((f, (-1.4 * (1 - u ** (1 / 1.8)), 0.16 * math.sin(f * 2.1 + ph), 0.0)))
    return k

def lathe_mesh(name, stations, sides=10, flat=1.0, curve=0.0):
    v, f = [], []
    rings = []
    for z, r in stations:
        if r <= 1e-6:
            v.append((curve * z * z, 0.0, z))
            rings.append(("apex", len(v) - 1))
        else:
            base = len(v)
            for k in range(sides):
                a = 2 * math.pi * k / sides
                v.append((r * math.cos(a) + curve * z * z, r * flat * math.sin(a), z))
            rings.append(("ring", base))
    for i in range(len(rings) - 1):
        (ta, a), (tb, b) = rings[i], rings[i + 1]
        for k in range(sides):
            k2 = (k + 1) % sides
            if ta == "apex" and tb == "ring":
                f.append((a, b + k, b + k2))
            elif ta == "ring" and tb == "apex":
                f.append((a + k2, a + k, b))
            else:
                f.append((a + k, a + k2, b + k2, b + k))
    return smooth(mk(name, v, f))

def tongue_stations(n=10, R=0.5, seed=0.0, bulge=0.0):
    return [(i / n, R * math.sqrt(max(1 - (i / n) ** 2.2, 0.0)) * (1 - 0.5 * i / n) * (1 + bulge * math.sin(i * 1.9 + seed))) for i in range(n + 1)]

# vraie goutte : fond rond en bas (z=0), pointe fine vers le haut (z=1) ; echelle (S) = hauteur totale
DROP_ST = [(0.0, 0.0), (0.03, 0.22), (0.1, 0.38), (0.22, 0.5), (0.36, 0.52), (0.5, 0.46), (0.64, 0.34), (0.78, 0.2), (0.9, 0.09), (1.0, 0.0)]

def crown_mesh(name, N=9, r0=0.6, r1=1.5, hmax=1.4, w0=0.4, seed=1, sides=6):
    # couronne d'eclaboussure : N petales arrondis irreguliers (hauteurs/largeurs differentes) qui montent puis s'ecartent ; UN seul maillage
    rr = random.Random(seed)
    v, f = [], []
    us = [0.0, 0.4, 0.75, 1.0]
    ws = [1.0, 0.95, 0.8, 0.5]
    for i in range(N):
        th = 2 * math.pi * (i + rr.uniform(-0.25, 0.25)) / N
        h = hmax * rr.uniform(0.5, 1.0)
        rt = r1 * rr.uniform(0.85, 1.0)
        wk = w0 * rr.uniform(0.8, 1.2)
        B = (-math.sin(th), math.cos(th), 0.0)
        P = []
        for u in us:
            rad = r0 + (rt - r0) * u ** 1.3
            P.append((rad * math.cos(th), rad * math.sin(th), h * math.sin(u * math.pi * 0.5 * 0.95)))
        base_ids = []
        for k, (p, wf) in enumerate(zip(P, ws)):
            q = P[min(k + 1, len(P) - 1)]
            q0 = P[max(k - 1, 0)]
            T = [q[j] - q0[j] for j in range(3)]
            L = math.sqrt(sum(t * t for t in T)) or 1.0
            T = [t / L for t in T]
            Nn = (T[1] * B[2] - T[2] * B[1], T[2] * B[0] - T[0] * B[2], T[0] * B[1] - T[1] * B[0])
            base = len(v)
            base_ids.append(base)
            for s_ in range(sides):
                a = 2 * math.pi * s_ / sides
                w = wk * wf
                tk = 0.6 * w
                v.append(tuple(p[j] + w * math.cos(a) * B[j] + tk * math.sin(a) * Nn[j] for j in range(3)))
        for k in range(len(P) - 1):
            a, b = base_ids[k], base_ids[k + 1]
            for s_ in range(sides):
                s2 = (s_ + 1) % sides
                f.append((a + s_, a + s2, b + s2, b + s_))
        # pointe arrondie + fond
        tip = P[-1]
        T = [P[-1][j] - P[-2][j] for j in range(3)]
        L = math.sqrt(sum(t * t for t in T)) or 1.0
        v.append(tuple(tip[j] + 0.5 * wk * 0.5 * T[j] / L for j in range(3)))
        ti = len(v) - 1
        for s_ in range(sides):
            f.append((base_ids[-1] + s_, base_ids[-1] + (s_ + 1) % sides, ti))
        v.append(P[0])
        bi = len(v) - 1
        for s_ in range(sides):
            f.append((base_ids[0] + (s_ + 1) % sides, base_ids[0] + s_, bi))
    return smooth(mk(name, v, f))

def jet_keys(t0, w, h, hold, out, ph=0.0):
    k = [(1, 0.001)]
    if t0 - 1 > 1:
        k.append((t0 - 1, 0.001))
    k += [(t0, (0.4 * w, 0.4 * w, 0.3 * h)), (t0 + 1, (1.0 * w, 1.0 * w, 1.3 * h)), (t0 + 2, (w, w, h))]
    for i in range(1, hold + 1):
        fr = t0 + 2 + i
        k.append((fr, (w * (1 + 0.06 * math.sin(fr * 2 + ph)), w * (1 + 0.06 * math.sin(fr * 2.4 + ph)), h * (1 + 0.07 * math.sin(fr * 2.3 + ph)))))
    f1 = t0 + 2 + hold
    for i in range(1, out):
        u = i / out
        k.append((f1 + i, (w * (1 + 0.6 * u), w * (1 + 0.6 * u), h * (1 - u) ** 0.9)))
    k.append((f1 + out, 0.001))
    return k

def ball_at(f0, v0, h0, steps, g=14.0):
    return [(f0 + i, (v0[0] * i / 24.0, v0[1] * i / 24.0, max(0.1, h0 + v0[2] * i / 24.0 - 0.5 * g * (i / 24.0) ** 2))) for i in range(steps + 1)]

def film_keys(t, hold, out, sx, sy):
    k = [(1, 0.001), (t, (0.3 * sx, 0.3 * sy, 0.4)), (t + 1, (1.1 * sx, 1.1 * sy, 0.5)), (t + 2, (sx, sy, 0.5))]
    for f in range(t + 3, t + 2 + hold):
        k.append((f, (sx * pulse(f, 0.08, 2.1), sy * pulse(f, 0.1, 2.6, 1.0), 0.45)))
    for i in range(1, out):
        u = i / out
        k.append((t + 2 + hold + i - 1, (sx * (1 + 0.1 * u), sy * (1 - 0.5 * u), 0.5 * (1 - u))))
    k.append((t + 2 + hold + out, 0.001))
    return k

IMPACT = 4   # image d'impact (locale) : chute = images 1 a 3, impact 4

def falling_drop(ctx, tag, M, S, H):
    # grosse goutte : tombe tres vite en s'etirant (images 1-3), s'ecrase a l'impact (4), s'aplatit puis eclate (5) ; reflet blanc colle a la goutte
    fz = [H, H * 0.42, H * 0.08, 0.05, 0.05]
    sc = [(0.78, 0.78, 1.4), (0.72, 0.72, 1.52), (0.8, 0.8, 1.36), (1.5, 1.5, 0.42), (2.05, 2.05, 0.16)]
    keys = [(i + 1, (S * a, S * b, S * c)) for i, (a, b, c) in enumerate(sc)] + [(6, 0.001)]
    lk = [(i + 1, (0.0, 0.0, z)) for i, z in enumerate(fz)]
    add_obj(ctx, f"{tag}_Drop", M["dropm"], M["DROP"], (0, 0, H), keys, loc_keys=lk)
    hk = []
    hl = []
    for i, (a, b, c) in enumerate(sc[:4]):
        hk.append((i + 1, (S * a * 0.2, S * b * 0.12, S * c * 0.36)))
        hl.append((i + 1, (-0.14 * S * a, 0.4 * S * b, fz[i] + 0.4 * S * c)))
    hk.append((5, 0.001))
    add_obj(ctx, f"{tag}_Hi", M["hi"], M["HI"], (0, 0, H), hk, loc_keys=hl)

def splash(ctx, tag, M, center):
    r = random.Random(tag)
    I = IMPACT
    if center:
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 1.0), [(1, 0.001), (I, 0.5), (I + 1, 2.4), (I + 2, 0.7), (I + 3, 0.001)], az=20)
        crowns = [("Crown", M["crown_c"], M["CROWN"], [(1, 0.001), (I, (0.3, 0.3, 0.2)), (I + 1, (0.85, 0.85, 1.2)), (I + 2, (1.0, 1.0, 1.05)), (I + 3, (1.03, 1.03, 1.0)),
                   (I + 4, (1.06, 1.06, 0.88)), (I + 5, (1.09, 1.09, 0.7)), (I + 6, (1.12, 1.12, 0.48)), (I + 7, (1.14, 1.14, 0.25)), (I + 8, (1.15, 1.15, 0.1)), (I + 9, 0.001)]),
                  ("CrownW", M["crown_w"], M["WCROWN"], [(1, 0.001), (I + 1, (0.3, 0.3, 0.2)), (I + 2, (0.9, 0.9, 1.25)), (I + 3, (1.0, 1.0, 1.1)), (I + 4, (1.05, 1.05, 0.95)),
                   (I + 5, (1.1, 1.1, 0.7)), (I + 6, (1.14, 1.14, 0.45)), (I + 7, (1.16, 1.16, 0.2)), (I + 8, 0.001)])]
        for nm, me, ma, keys in crowns:
            add_obj(ctx, f"{tag}_{nm}", me, ma, (0, 0, 0.05), keys, drift=40)
        # gerbe verticale (jaillit apres l'impact) + coeur lumineux
        add_obj(ctx, f"{tag}_Jet0", M["tongueH"], M["TONGUE"], (0, 0, 0.0), jet_keys(I, 0.9, 3.8, 3, 4, ph=0.3))
        add_obj(ctx, f"{tag}_Jet1", M["tongueL"], M["TONGUE"], (0.35, -0.3, 0.0), jet_keys(I + 1, 0.7, 2.6, 2, 4, ph=1.7), az=140, el=8)
        add_obj(ctx, f"{tag}_Jet2", M["tongueR"], M["TONGUE"], (-0.3, 0.35, 0.0), jet_keys(I + 1, 0.65, 2.2, 2, 4, ph=2.9), az=-40, el=10)
        add_obj(ctx, f"{tag}_Core", M["tongueG"], M["TONGUEG"], (0.0, 0.0, 0.0), jet_keys(I + 1, 0.5, 3.0, 2, 4, ph=1.0))
        ring_R = 2.0
        sizes = [1.1, 0.85, 0.7, 0.55, 0.42, 0.32]
        n_foam = 2
    else:
        crowns_k = [(1, 0.001), (I, (0.3, 0.3, 0.2)), (I + 1, (0.85, 0.85, 1.2)), (I + 2, (1.0, 1.0, 1.05)), (I + 3, (1.03, 1.03, 0.95)),
                    (I + 4, (1.06, 1.06, 0.75)), (I + 5, (1.09, 1.09, 0.5)), (I + 6, (1.11, 1.11, 0.28)), (I + 7, (1.12, 1.12, 0.1)), (I + 8, 0.001)]
        add_obj(ctx, f"{tag}_Crown", M["crown_b"], M["CROWN"], (0, 0, 0.05), crowns_k, drift=40)
        ring_R = 1.6
        sizes = [0.6, 0.45, 0.35]
        n_foam = 1
    ring_k = [(1, 0.001), (I, (0.35 * ring_R, 0.35 * ring_R, 0.5)), (I + 1, (0.75 * ring_R, 0.75 * ring_R, 0.5)), (I + 2, (ring_R, ring_R, 0.45)), (I + 3, (1.05 * ring_R, 1.05 * ring_R, 0.35)), (I + 4, 0.001)]
    add_obj(ctx, f"{tag}_Ring", M["ring"], M["RING"], (0, 0, 0.06), ring_k)
    # gouttelettes projetees (le long des bras ; dispersion laterale faible : elles restent sur les cases dangereuses)
    for i, S in enumerate(sizes):
        if center:
            ang = math.radians(90 * (i % 4) + r.uniform(-8, 8))
            sp = r.uniform(3.0, 5.0)
            v0 = (sp * math.cos(ang), sp * math.sin(ang), r.uniform(5.5, 8.0))
        else:
            v0 = (r.choice((-2.2, 2.2, 3.2)) * r.uniform(0.8, 1.2), r.uniform(-0.5, 0.5), r.uniform(4.5, 6.5))
        add_obj(ctx, f"{tag}_Spl{i}", M["dropm"], M["DROP"], (0, 0, 0.4), fade(S, I, I + 8), az=i * 60, loc_keys=ball_at(I, v0, 0.4, 9, 16.0))
    for i in range(n_foam):
        a = math.radians(90 + 180 * i)
        add_obj(ctx, f"{tag}_Foam{i}", M["foam"], M["FOAM"], (0.9 * math.cos(a) if center else 0.0, 0.9 * math.sin(a) if center else 0.0, 0.3),
                seq_keys(0.75 if center else 0.55, I + 1, I + 4, I + 8, 0.12, 2.5, i, 0.5, 1.3), drift=60)
    fs = (3.2, 3.2) if center else (2.6, 2.0)
    add_obj(ctx, f"{tag}_Film", M["film"], M["FILM"], (0.0, 0.0, 0.08), film_keys(I, 5, 5, fs[0], fs[1]), az=8)

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    if kind == "center":
        falling_drop(ctx, tag, M, 3.4, 11.0)
        splash(ctx, tag, M, True)
    else:
        falling_drop(ctx, tag, M, 1.9, 8.0)
        splash(ctx, tag, M, False)

def build():
    M = {"FLASH": make_neon("FLASH", "#DFF6FF"),
         "DROP": make_smoke("DROP", "#1F86FF", 0.7, 0.7), "HI": make_glow("HI", "#FFFFFF", 0.8, 1.6),
         "TONGUE": make_smoke("TONGUE", "#2E8BFF", 0.7, 0.6), "TONGUEG": make_glow("TONGUEG", "#BFEFFF", 0.55, 1.6),
         "FOAM": make_smoke("FOAM", "#D8F2FF", 0.38, 0.5), "FILM": make_smoke("FILM", "#8ADBFF", 0.3, 0.45),
         "CROWN": make_glow("CROWN", "#7FE0FF", 0.6, 1.5), "WCROWN": make_glow("WCROWN", "#EAF9FF", 0.7, 1.7), "RING": make_glow("RING", "#CFF4FF", 0.5, 1.5)}
    M["dropm"] = lathe_mesh("E17_Drop", DROP_ST, 12, 1.0, 0.0)
    M["hi"] = orb_mesh("E17_Hi", 3, 0.5, 2, 0.05, 1.0)
    M["flash"] = blob_mesh("E17_Flash", 0.7, 0.85, 0.5, 33, 2)
    M["crown_c"] = crown_mesh("E17_CrownC", 10, 0.5, 1.45, 3.4, 0.36, 5, 6)
    M["crown_w"] = crown_mesh("E17_CrownW", 8, 0.3, 0.9, 2.4, 0.3, 9, 6)
    M["crown_b"] = crown_mesh("E17_CrownB", 8, 0.35, 1.05, 2.1, 0.26, 13, 5)
    M["ring"] = ring_mesh("E17_Ring", 0.82, 1.0, 0.06, 24)
    M["foam"] = orb_mesh("E17_Foam", 8, 0.6, 2, 0.22, 0.8)
    M["film"] = orb_mesh("E17_Film", 12, 0.6, 2, 0.3, 0.3)
    M["tongueH"] = lathe_mesh("E17_TongueH", tongue_stations(12, 0.34, 1.0, 0.16), 10, 0.8, 0.1)
    M["tongueL"] = lathe_mesh("E17_TongueL", tongue_stations(10, 0.46, 2.1, 0.2), 10, 0.7, -0.34)
    M["tongueR"] = lathe_mesh("E17_TongueR", tongue_stations(10, 0.52, 4.0, 0.18), 10, 0.8, 0.3)
    M["tongueG"] = lathe_mesh("E17_TongueG", tongue_stations(10, 0.5, 0.0, 0.1), 10, 0.75, 0.1)
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
    flat = {}
    for k, m in M.items():
        if hasattr(m, "polygons"):
            flat[m.name] = len(m.polygons)
    print("polygones :", flat)
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E17_Eau")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E17_Eau_v4.blend"))

def render():
    from mathutils import Vector
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E17")
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
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 6, 7, 9, 11, 13, 15)), ("CAM_Game", (3, 5, 7)), ("CAM_Far", (3, 5, 8))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v4_%s_f%02d.png" % ({"CAM_Game": "game", "CAM_Far": "far"}.get(cam, "close"), f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E17_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
