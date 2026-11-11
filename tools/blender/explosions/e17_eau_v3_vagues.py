"""E17 Eau (reference : Explosions_32.png, rangee 3, carte Eau) : jaillissement d'eau (langues d'eau arrondies bleues et coeur cyan lumineux), gouttes en forme de larme
projetees en arcs, ecume blanche, vagues d'eau qui se propagent en croix (rubans ondulants alternes), petit jaillissement a chaque extremite avant la dissipation.
Aucun rocher ni solide : eau translucide. Briques CENTER / SEGMENT / END (4 directions).
Pilotage (Blender, E01_Classique_v2.blend ouvert) : E17_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Ecrit E17_Eau_v3.blend a cote ; E01_Classique_v2.blend n'est jamais ecrase.
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

def lathe_mesh(name, stations, sides=10, flat=0.75, curve=0.0):
    # solide de révolution lisse (langue d'eau, goutte) : stations = [(z, rayon)] ; rayon 0 = pointe arrondie ; ferme par une pointe ou un fond
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
            elif ta == "ring" and tb == "ring":
                f.append((a + k, a + k2, b + k2, b + k))
    if rings[0][0] == "ring":
        c = len(v)
        v.append((0.0, 0.0, stations[0][0]))
        for k in range(sides):
            f.append((c, rings[0][1] + (k + 1) % sides, rings[0][1] + k))
    if rings[-1][0] == "ring":
        c = len(v)
        v.append((curve * stations[-1][0] ** 2, 0.0, stations[-1][0]))
        for k in range(sides):
            f.append((c, rings[-1][1] + k, rings[-1][1] + (k + 1) % sides))
    return smooth(mk(name, v, f))

DROP_ST = [(0.0, 0.0), (0.12, 0.05), (0.3, 0.1), (0.45, 0.22), (0.6, 0.38), (0.75, 0.48), (0.88, 0.42), (0.97, 0.22), (1.0, 0.0)]

def jet_keys(t0, w, h, hold, out, ph=0.0):
    # jet d'eau : jaillit (dépassement), tient en ondulant, puis retombe : la hauteur s'effondre pendant que la base s'étale
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

def tongue_stations(n=10, R=0.5, seed=0.0, bulge=0.0):
    # langue d'eau : base large, sommet arrondi, renflements irréguliers (liquide, pas de forme parfaite)
    return [(i / n, R * math.sqrt(max(1 - (i / n) ** 2.2, 0.0)) * (1 - 0.5 * i / n) * (1 + bulge * math.sin(i * 1.9 + seed))) for i in range(n + 1)]

def ball_at(f0, v0, h0, steps, g=14.0):
    return [(f0 + i, (v0[0] * i / 24.0, v0[1] * i / 24.0, max(0.1, h0 + v0[2] * i / 24.0 - 0.5 * g * (i / 24.0) ** 2))) for i in range(steps + 1)]

def drop_obj(ctx, tag, n, M, S, f0, v0, h0, steps, g, loc0):
    add_obj(ctx, f"{tag}_Drop{n}", M["drop"], M["DROP"], loc0, fade(S, f0, f0 + steps - 1), el=180, az=n * 70,
            loc_keys=ball_at(f0, v0, h0, steps, g))

def film_keys(t, hold, out, sx, sy):
    k = [(1, 0.001), (t, (0.3 * sx, 0.3 * sy, 0.4)), (t + 1, (1.1 * sx, 1.1 * sy, 0.5)), (t + 2, (sx, sy, 0.5))]
    for f in range(t + 3, t + 2 + hold):
        k.append((f, (sx * pulse(f, 0.08, 2.1), sy * pulse(f, 0.1, 2.6, 1.0), 0.45)))
    for i in range(1, out):
        u = i / out
        k.append((t + 2 + hold + i - 1, (sx * (1 + 0.15 * u), sy * (1 - 0.5 * u), 0.5 * (1 - u))))
    k.append((t + 2 + hold + out, 0.001))
    return k

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (2, 1.9), (3, 0.5), (4, 0.001)], az=20)
        # nappe d'eau basse (plus de dôme "bouclier") : onde de pression plate dans l'axe des bras
        add_obj(ctx, f"{tag}_Cross", M["cross"], M["CROSS"], (0, 0, 0.1),
                [(1, 0.001), (2, (1.2, 1.2, 0.5)), (3, (3.4, 3.4, 0.7)), (4, (4.8, 4.8, 0.5)), (5, (5.4, 5.4, 0.3)), (6, (5.6, 5.6, 0.12)), (7, 0.001)])
        # gerbe centrale haute : 1 jet principal fin et haut + 2 jets compagnons décalés (irréguliers)
        add_obj(ctx, f"{tag}_Jet0", M["tongueH"], M["TONGUE"], (0, 0, 0.0), jet_keys(2, 0.85, 4.2, 4, 5, ph=0.3), az=0, el=0)
        add_obj(ctx, f"{tag}_Jet1", M["tongueL"], M["TONGUE"], (0.25, -0.2, 0.0), jet_keys(3, 0.7, 3.0, 3, 4, ph=1.7), az=140, el=10)
        add_obj(ctx, f"{tag}_Jet2", M["tongueR"], M["TONGUE"], (-0.2, 0.25, 0.0), jet_keys(3, 0.65, 2.5, 3, 4, ph=2.9), az=-40, el=14)
        # couronne d'éclaboussures irrégulière (angles, tailles et formes différents)
        angs = [8, 58, 112, 171, 221, 262, 318]
        hs = [1.5, 2.1, 1.3, 1.9, 1.2, 1.7, 1.4]
        for i, phi in enumerate(angs):
            m = (M["tongue"], M["tongueL"], M["tongueR"])[i % 3]
            add_obj(ctx, f"{tag}_Crown{i}", m, M["TONGUE"], (0.35 * math.cos(math.radians(phi)), 0.35 * math.sin(math.radians(phi)), 0.0),
                    jet_keys(2 + i % 2, 0.6 + 0.07 * (i % 4), hs[i], 2 + i % 3, 4, ph=i), az=phi - 180, el=32 + 5 * (i % 3))
        # cœur clair lumineux dans la gerbe
        for i in range(2):
            add_obj(ctx, f"{tag}_Core{i}", M["tongueG"], M["TONGUEG"], (0.08 * (1 - 2 * i), 0.0, 0.0), jet_keys(3, 0.5, (3.0, 2.0)[i], 2, 4, ph=i), az=90 * i, el=6)
        for i in range(3):
            a = math.radians(30 + 120 * i)
            add_obj(ctx, f"{tag}_Foam{i}", M["foam"], M["FOAM"], (1.1 * math.cos(a), 1.1 * math.sin(a), 0.3),
                    seq_keys(0.7, 3, 8, 11, 0.12, 2.5, i, 0.5, 1.3), drift=60)
        # gouttes de tailles variées projetées le long des bras (cases dangereuses uniquement)
        sizes = [1.6, 1.1, 0.8, 0.6, 0.45, 0.35]
        for i, S in enumerate(sizes):
            ang = math.radians(90 * (i % 4) + r.uniform(-9, 9))
            sp, vz = r.uniform(4.0, 7.5), r.uniform(5.5, 8.5)
            drop_obj(ctx, tag, i, M, S, 2 + i % 2, (sp * math.cos(ang), sp * math.sin(ang), vz), 1.2, 12, 14.0, (0, 0, 1.2))
        # retombée : gouttes qui s'écrasent dans la case centrale pendant l'effondrement de la gerbe
        for i in range(2):
            drop_obj(ctx, tag, 6 + i, M, (0.7, 0.5)[i], 7 + i, ((0.9, -0.9)[i], 0.0, 0.5), 3.0, 8, 40.0, (0, 0, 3.0))
    else:
        t = 2 if kind == "segment" else 3
        # vagues continues : 2 variantes de forme par couche (flipbook) => les contours se déforment ; le front est plus haut
        layers = [("B", M["waveB"], (M["WAVEB"], M["WAVEB2"]), (1.0, 1.1, 1.35), 4, 6, 0.0), ("L", M["waveL"], (M["WAVEL"], M["WAVEL2"]), (1.0, 1.0, 1.25), 4, 4, 0.7)]
        if kind == "segment":
            layers.append(("F", M["waveF"], (M["WAVEF"], M["WAVEF2"]), (1.0, 1.0, 1.0), 3, 3, 1.4))
        for name, meshes, mat, base, hold, out, ph in layers:
            keysets, last = wave_flip(t, hold, out, base, ph)
            for v in (0, 1):
                add_obj(ctx, f"{tag}_Wave{name}{v}", meshes[v], mat[v], (-1.4, 0, 0.0), keysets[v], jit=5.0, loc_keys=wave_loc(t, last, ph + v))
        # déferlante : langue d'eau penchée dans le sens de la propagation (la vague "déferle" sur la case)
        add_obj(ctx, f"{tag}_Crest0", M["tongueR"], M["TONGUE"], (-1.0, -0.55, 0.0), jet_keys(t, 0.85, 1.7, 2, 4, ph=0.5), az=180 - 6, el=52)
        add_obj(ctx, f"{tag}_Crest1", M["tongueL"], M["TONGUE"], (-0.4, 0.6, 0.0), jet_keys(t + 1, 0.7, 1.4, 2, 4, ph=2.0), az=180 + 8, el=58)
        # petite gerbe verticale sur la branche
        add_obj(ctx, f"{tag}_Spray0", M["tongue"], M["TONGUE"], (0.7, 0.1, 0.0), jet_keys(t + 2 + (2 if kind == "end" else 0), 0.6, 1.2 if kind == "segment" else 2.0, 1, 3, ph=1.1), az=0, el=0)
        drop_obj(ctx, tag, 0, M, 0.8, t + 1, (r.uniform(3.0, 4.5), r.uniform(-1.0, 1.0), r.uniform(5.0, 6.5)), 0.6, 10, 14.0, (-1.0, 0.0, 0.6))
        drop_obj(ctx, tag, 1, M, 0.5, t + 2, (r.uniform(1.5, 3.0), r.uniform(-1.4, 1.4), r.uniform(4.0, 5.5)), 0.5, 9, 14.0, (-0.5, 0.0, 0.5))
        add_obj(ctx, f"{tag}_Foam0", M["foam"], M["FOAM"], (0.0, -0.3, 0.25), seq_keys(0.6, t + 1, t + 5, t + 8, 0.14, 2.7, 0.5, 0.5, 1.3), drift=60)
        # traces d'eau temporaires au sol (filets) qui s'étalent puis se résorbent
        add_obj(ctx, f"{tag}_Film0", M["film"], M["FILM"], (0.0, 0.0, 0.08), film_keys(t + 2, 4, 5, 2.6, 1.0), az=8)

def build():
    M = {"FLASH": make_neon("FLASH", "#DFF6FF"), "FILM": make_smoke("FILM", "#8ADBFF", 0.3, 0.45),
         "TONGUE": make_smoke("TONGUE", "#2E8BFF", 0.7, 0.6), "TONGUEG": make_glow("TONGUEG", "#BFEFFF", 0.55, 1.6),
         "FOAM": make_smoke("FOAM", "#D8F2FF", 0.38, 0.5), "DROP": make_smoke("DROP", "#4FB0FF", 0.75, 0.7),
         "CROSS": make_glow("CROSS", "#5CC8FF", 0.32, 1.3),
         "WAVEB": make_smoke("WAVEB", "#1456D8", 0.55, 0.5), "WAVEB2": make_smoke("WAVEB2", "#1E6BE8", 0.4, 0.6),
         "WAVEL": make_glow("WAVEL", "#7FD8FF", 0.55, 1.4), "WAVEL2": make_glow("WAVEL2", "#A8E8FF", 0.4, 1.6),
         "WAVEF": make_glow("WAVEF", "#EAF8FF", 0.8, 1.8), "WAVEF2": make_glow("WAVEF2", "#CFF1FF", 0.55, 2.0)}
    M["tongue"] = lathe_mesh("E17_Tongue", tongue_stations(10, 0.5, 0.0, 0.14), 10, 0.75, 0.18)
    M["tongueL"] = lathe_mesh("E17_TongueL", tongue_stations(10, 0.46, 2.1, 0.2), 10, 0.7, -0.34)
    M["tongueR"] = lathe_mesh("E17_TongueR", tongue_stations(10, 0.52, 4.0, 0.18), 10, 0.8, 0.3)
    M["tongueH"] = lathe_mesh("E17_TongueH", tongue_stations(12, 0.34, 1.0, 0.16), 10, 0.8, 0.1)
    M["tongueG"] = lathe_mesh("E17_TongueG", tongue_stations(10, 0.5), 10, 0.75, 0.1)
    M["drop"] = lathe_mesh("E17_Drop", DROP_ST, 10, 1.0, 0.0)
    M["foam"] = orb_mesh("E17_Foam", 8, 0.6, 2, 0.22, 0.8)
    M["cross"] = cross_mesh("E17_Cross")
    M["film"] = orb_mesh("E17_Film", 12, 0.6, 2, 0.3, 0.3)
    M["flash"] = blob_mesh("E17_Flash", 0.7, 0.85, 0.5, 33, 2)
    M["waveB"] = [wave_mesh("E17_WaveB%d" % v, v * math.pi, 1.5, 0.35, 0.35) for v in (0, 1)]
    M["waveL"] = [wave_mesh("E17_WaveL%d" % v, v * math.pi + 0.7, 1.0, 0.3, 0.26) for v in (0, 1)]
    M["waveF"] = [wave_mesh("E17_WaveF%d" % v, v * math.pi + 1.4, 0.5, 0.2, 0.18) for v in (0, 1)]
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
        for mm in (m if isinstance(m, list) else [m]):
            if hasattr(mm, "polygons"):
                flat[mm.name] = len(mm.polygons)
    print("polygones :", flat)
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E17_Eau")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E17_Eau_v3.blend"))

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
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11, 13)), ("CAM_Game", (5, 9)), ("CAM_Far", (4, 7, 10))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v3_%s_f%02d.png" % ({"CAM_Game": "game", "CAM_Far": "far"}.get(cam, "close"), f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E17_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
