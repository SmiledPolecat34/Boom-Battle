"""E18 Nature V3 (reference : Explosions_32.png, rangee 3, carte Nature) : des LIANES vivantes surgissent du sol, fouettent l'air, se recourbent pour "attraper", puis se
contractent brutalement vers le sol et disparaissent. Chaque liane = chaine de 4 segments de tube rigides (position/direction recalculees a chaque image => courbure,
ondulation, enroulement) ; feuilles volantes conservees (projetees + tourbillons). Eveil au centre : fissure + lueur verte + petites feuilles qui tourbillonnent
AVANT l'impact (descente `lead`). Briques CENTER / SEGMENT / END. Tout reste dans les cases de la croix.
Pilotage (Blender, E01_Classique_v2.blend ouvert) : E18_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Ecrit E18_Nature_v7.blend a cote ; E01_Classique_v2.blend n'est jamais ecrase.
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
    # evite que l'objet "pousse" lentement avant son apparition (interpolation entre l'image 1 invisible et la premiere vraie image) : maintien invisible
    keys = list(keys)
    if len(keys) > 1 and keys[0][0] == 1 and keys[1][0] > 2 and max(keys[0][1] if isinstance(keys[0][1], tuple) else (keys[0][1],)) < 0.01:
        keys.insert(1, (keys[1][0] - 1, 0.001))
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

def make_leaf(key, hx, emi=0.3):
    m = bpy.data.materials.new("E09_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.55
    b.inputs["Emission Color"].default_value = hex_lin(hx)
    b.inputs["Emission Strength"].default_value = emi
    return m

def rot_el_az(p, el, az):
    x, y, z = p
    c, s = math.cos(math.radians(el)), math.sin(math.radians(el))
    x, z = x * c - z * s, x * s + z * c
    c, s = math.cos(math.radians(az)), math.sin(math.radians(az))
    return (x * c - y * s, x * s + y * c, z)

def leaf_geom(L=1.0, W=0.45, fold=0.3, curl=0.18, thick=0.04, st=6):
    # feuille fine fermee : axe long = +X, nervure centrale pliee en V, bout recourbe
    v, top, bot = [], [], []
    for i in range(st + 1):
        u = i / st
        w = 0.0 if i in (0, st) else W * (math.sin(math.pi * u ** 0.8)) ** 0.75
        row_t, row_b = [], []
        if w == 0.0:
            z = curl * L * u * u
            v.append((u * L, 0.0, z)); row_t = [len(v) - 1] * 3
            v.append((u * L, 0.0, z - thick)); row_b = [len(v) - 1] * 3
        else:
            for j in (-1, 0, 1):
                z = curl * L * u * u + fold * w * abs(j)
                v.append((u * L, j * w, z)); row_t.append(len(v) - 1)
                v.append((u * L, j * w, z - thick)); row_b.append(len(v) - 1)
        top.append(row_t); bot.append(row_b)
    f = []
    for i in range(st):
        a, b = top[i], top[i + 1]
        c, d = bot[i], bot[i + 1]
        for k in (0, 1):
            for (p, q) in ((a, b), (d, c)):
                quad = [p[k], p[k + 1], q[k + 1], q[k]]
                u_ = []
                for idx in quad:
                    if idx not in u_:
                        u_.append(idx)
                if len(u_) >= 3:
                    f.append(tuple(u_))
        for k in (0, 2):
            quad = [a[k], b[k], d[k], c[k]]
            u_ = []
            for idx in quad:
                if idx not in u_:
                    u_.append(idx)
            if len(u_) >= 3:
                f.append(tuple(u_))
    return v, f

def leaf_mesh(name, L, W, fold, curl, seed=0):
    v, f = leaf_geom(L, W, fold, curl)
    return mk(name, v, f)

def cluster_mesh(name, n, L, W, el0, r0, seed, curl=0.2):
    rr = random.Random(seed)
    V, F = [], []
    for k in range(n):
        az = 360.0 * k / n + rr.uniform(-18, 18)
        el = el0 + rr.uniform(-12, 12)
        l = L * rr.uniform(0.8, 1.15)
        v, f = leaf_geom(l, W * rr.uniform(0.85, 1.15), 0.3, curl * rr.uniform(0.6, 1.3))
        off = len(V)
        for p in v:
            q = rot_el_az(p, el, az)
            V.append((q[0] + r0 * math.cos(math.radians(az)), q[1] + r0 * math.sin(math.radians(az)), q[2]))
        for fc in f:
            F.append(tuple(i + off for i in fc))
    return mk(name, V, F)

def blade_crown(name, N, r0, r1, hmax, w0, seed, sides=4):
    # couronne de lames d'herbe/feuilles pointues (plates, courbees vers l'exterieur, hauteurs et largeurs irregulieres) : UN seul maillage
    rr = random.Random(seed)
    v, f = [], []
    us = [0.0, 0.45, 0.8]
    ws = [1.0, 0.8, 0.4]
    for i in range(N):
        th = 2 * math.pi * (i + rr.uniform(-0.35, 0.35)) / N
        h = hmax * rr.uniform(0.45, 1.0)
        rt = r1 * rr.uniform(0.7, 1.1)
        wk = w0 * rr.uniform(0.75, 1.3)
        B = (-math.sin(th), math.cos(th), 0.0)
        P = []
        for u in us + [1.0]:
            rad = r0 + (rt - r0) * u ** 1.5
            P.append((rad * math.cos(th), rad * math.sin(th), h * math.sin(u * math.pi * 0.5 * 0.92)))
        ids = []
        for k in range(3):
            p, q0, q1 = P[k], P[max(k - 1, 0)], P[k + 1]
            T = [q1[j] - q0[j] for j in range(3)]
            L = math.sqrt(sum(t * t for t in T)) or 1.0
            T = [t / L for t in T]
            Nn = (T[1] * B[2] - T[2] * B[1], T[2] * B[0] - T[0] * B[2], T[0] * B[1] - T[1] * B[0])
            base = len(v)
            ids.append(base)
            for s_ in range(sides):
                a = 2 * math.pi * s_ / sides
                w = wk * ws[k]
                v.append(tuple(p[j] + w * math.cos(a) * B[j] + 0.3 * w * math.sin(a) * Nn[j] for j in range(3)))
        for k in range(2):
            a, b = ids[k], ids[k + 1]
            for s_ in range(sides):
                s2 = (s_ + 1) % sides
                f.append((a + s_, a + s2, b + s2, b + s_))
        v.append(P[3])
        ti = len(v) - 1
        for s_ in range(sides):
            f.append((ids[2] + s_, ids[2] + (s_ + 1) % sides, ti))
        v.append(P[0])
        bi = len(v) - 1
        for s_ in range(sides):
            f.append((ids[0] + (s_ + 1) % sides, ids[0] + s_, bi))
    return smooth(mk(name, v, f))

def rocks_mesh(name, specs, cap=False, seed=1):
    import bmesh
    from mathutils import Matrix, Vector
    rr = random.Random(seed)
    bm = bmesh.new()
    for (x, y, z, r) in specs:
        if cap:
            pos, rad, sq = Vector((x, y, z + 0.45 * r)), 0.72 * r, 0.5
        else:
            pos, rad, sq = Vector((x, y, z + 0.25 * r)), r, 0.72
        res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=rad)
        for vt in res["verts"]:
            c = vt.co
            vt.co = Vector((c.x * rr.uniform(0.85, 1.2), c.y * rr.uniform(0.85, 1.2), c.z * sq * rr.uniform(0.85, 1.15))) + pos
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me

def ball_at(f0, v0, h0, steps, g=14.0):
    return [(f0 + i, (v0[0] * i / 24.0, v0[1] * i / 24.0, max(0.1, h0 + v0[2] * i / 24.0 - 0.5 * g * (i / 24.0) ** 2))) for i in range(steps + 1)]

def grow_keys(t, hold, out, S=1.0, pk=1.25, ph=0.0, sway=0.05):
    # jaillit avec depassement, oscille legerement, puis se replie
    k = [(1, 0.001)]
    if t - 1 > 1:
        k.append((t - 1, 0.001))
    k += [(t, 0.35 * S), (t + 1, pk * S), (t + 2, S)]
    for i in range(1, hold + 1):
        fr = t + 2 + i
        k.append((fr, (S * (1 + sway * math.sin(fr * 2.1 + ph)), S * (1 + sway * math.sin(fr * 2.5 + ph)), S * (1 + 1.4 * sway * math.sin(fr * 2.3 + ph)))))
    f1 = t + 2 + hold
    for i in range(1, out):
        u = i / out
        k.append((f1 + i, S * (1 - u) ** 0.9))
    k.append((f1 + out, 0.001))
    return k

T0_SEG, T0_END = 4, 5   # lecture des branches par rapport au centre : moteur = retard de propagation (0,035 s/case, ~1 image/case) - pieceLead (1) ; centre : impact image 5

IMPACT_C = 5   # centre : eveil images 1-4 (lead = 4), surgissement des lianes image 5 = explosion serveur

def tube_mesh(name, sides=8, rb=0.78):
    # tube conique arrondi (dome au bout, aucune pointe) le long de +Z ; geometrie partagee par toutes les lianes
    v, f = [], []
    rings = ((0.0, 1.0), (1.0, rb), (1.18, rb * 0.78), (1.3, rb * 0.42))
    for z, r in rings:
        for k in range(sides):
            a = 2 * math.pi * k / sides
            v.append((r * math.cos(a), r * math.sin(a), z))
    v.append((0, 0, -0.05)); v.append((0, 0, 1.36))
    c0, c1 = len(rings) * sides, len(rings) * sides + 1
    for q in range(len(rings) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            f.append((q * sides + k, q * sides + k2, (q + 1) * sides + k2, (q + 1) * sides + k))
    for k in range(sides):
        k2 = (k + 1) % sides
        f.append((c0, k2, k))
        f.append((c1, (len(rings) - 1) * sides + k, (len(rings) - 1) * sides + k2))
    return smooth(mk(name, v, f))

def crack_mesh(name, n=7, rin=0.5, rout=1.6, seed=3):
    rr = random.Random(seed)
    v, f = [(0, 0, 0.03), (0, 0, -0.05)], []
    for i in range(2 * n):
        a = 2 * math.pi * i / (2 * n) + rr.uniform(-0.12, 0.12)
        r = (rout * rr.uniform(0.7, 1.0)) if i % 2 == 0 else (rin * rr.uniform(0.8, 1.2))
        v.append((r * math.cos(a), r * math.sin(a), 0.0))
    m = 2 * n
    for i in range(m):
        j = (i + 1) % m
        f.append((0, 2 + i, 2 + j))
        f.append((1, 2 + j, 2 + i))
    return mk(name, v, f)

def lerp_ang(a, b, w):
    d = (b - a + math.pi) % (2 * math.pi) - math.pi
    return a + d * w

def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))

def centerline(c, f):
    # ligne centrale de la liane a l'image f (ondulation en serpent, torsion, ouverture puis fermeture en spirale) : points (s, (x, y, z)) + direction au pied
    L = c["L"]
    ds = 0.1
    n = int(L * 1.15 / ds) + 1
    ph = c["ph"]
    tw = c["twist"] * clamp((f - c["ts"] - 0.5) / 2.0)
    o = clamp((f - c["to"]) / 2.0)
    cl = clamp((f - c["tc"]) / 1.2)
    Aw = c["wave"] * (1 - 0.8 * cl) * (1 + 0.6 * clamp(1 - (f - c["ts"]) / 3.0))
    az0, t0 = math.radians(c["az"]), math.radians(c["pitch"])
    x, y, z = c["root"]
    pts, T0 = [], None
    for i in range(n):
        s = i * ds
        u = s / L
        t = t0 + c["bend"] * u * 0.5 + 0.30 * math.sin(2.1 * s - 1.5 * f + ph * 1.3) * u + 0.45 * o * u
        w = clamp((s - 0.3 * L) / (0.5 * L))
        t = t * (1 - cl * w) + (1.15 + 0.95 * w) * cl * w
        t = clamp(t, 0.05, 2.9)
        a = az0 + Aw * (0.15 + 0.85 * u) * math.sin(2.6 * s - 1.6 * f + ph) + tw * s * (1 - cl * w) + cl * w * c["kappa"] * (s - 0.3 * L) * c["dir"]
        T = (math.sin(t) * math.cos(a), math.sin(t) * math.sin(a), math.cos(t))
        if T0 is None:
            T0 = T
        pts.append((s, (x, y, z)))
        x, y, z = x + T[0] * ds, y + T[1] * ds, z + T[2] * ds
    return pts, T0, c["root"]

def pos_at(pts, T0, root, s):
    if s <= 0:
        return (root[0] + T0[0] * s, root[1] + T0[1] * s, root[2] + T0[2] * s)
    ds = pts[1][0] - pts[0][0]
    i = min(int(s / ds), len(pts) - 2)
    w = clamp((s - pts[i][0]) / ds)
    p, q = pts[i][1], pts[i + 1][1]
    return tuple(p[k] + (q[k] - p[k]) * w for k in range(3))

def tip_pos(c, f):
    # position du bout (arc) : jaillit (2 images), reste, puis est AVALE dans le sol le long de sa propre trajectoire (accelere)
    L = c["L"]
    ts, tq = c["ts"], c["tq"]
    if f < ts:
        return -L
    if f == ts:
        return 0.5 * L
    if f == ts + 1:
        return 1.0 * L
    u = clamp((f - tq) / 2.4)
    if u <= 0:
        return L * (1.07 if f == tq - 1 else 1.0)
    return L * (1 - 2.2 * u ** 1.5)

def vine_frames(c):
    N, L = c["N"], c["L"]
    segs = [[] for _ in range(N)]
    leaves = [[] for _ in c.get("leaves", ())]
    lastd = [(0, 0, 1)] * N
    for f in range(1, 16):
        b = tip_pos(c, f)
        a = b - L
        pts, T0, root = centerline(c, f)
        ss = [a + L * i / N for i in range(N + 1)]
        P = [pos_at(pts, T0, root, s) for s in ss]
        for i in range(N):
            d = tuple(P[i + 1][k] - P[i][k] for k in range(3))
            ln = math.sqrt(sum(v * v for v in d))
            if ln > 0.03:
                lastd[i] = d
            if ln < 0.03 or max(P[i][2], P[i + 1][2]) < -0.3:
                segs[i].append((f, P[i], lastd[i], 0.001))
            else:
                ub = ((ss[i] + ss[i + 1]) / 2 - a) / L
                r = c["r0"] * (1 - 0.75 * ub ** 0.9) * (1 + 0.3 * clamp((f - c["tc"]) / 1.2) * (1 if f < c["tq"] + 1 else 0.8))
                segs[i].append((f, P[i], d, (r * (1.6 if i == N - 1 else 1.0), r * (1.6 if i == N - 1 else 1.0), ln * 1.0)))
        for li, (ub, S, side) in enumerate(c.get("leaves", ())):
            j = min(N - 1, int(ub * N))
            d = lastd[j]
            ln = math.sqrt(sum(v * v for v in d)) or 1.0
            cp = tuple(P[j][k] + 0.5 * (P[j + 1][k] - P[j][k]) for k in range(3))
            az = math.atan2(d[1], d[0]) + math.radians(75 * side)
            le = math.radians(35)
            ld = (math.cos(le) * math.cos(az), math.cos(le) * math.sin(az), math.sin(le))
            ok = cp[2] > 0.25 and f >= c["ts"]
            leaves[li].append((f, cp, ld, S if ok else 0.001))
    return segs, leaves

def add_seg(ctx, name, mesh, mat, frames, axis="z"):
    ob = bpy.data.objects.new(name, mesh)
    if not ob.data.materials:
        ob.data.materials.append(mat)
    ctx.coll.objects.link(ob)
    ob.visible_shadow = False
    prev = None
    for fr, p, d, s in frames:
        ob.scale = s if isinstance(s, tuple) else (s, s, s)
        wx, wy = ctx.world(p[0], p[1])
        ob.location = (wx, wy, p[2])
        L = math.sqrt(sum(x * x for x in d)) or 1.0
        dx, dy, dz = d[0] / L, d[1] / L, d[2] / L
        if axis == "z":
            el, az = math.acos(clamp(dz, -1, 1)), math.atan2(dy, dx) + math.pi
        else:
            el, az = math.asin(clamp(dz, -1, 1)), math.atan2(dy, dx)
        az += math.radians(ctx.arm)
        if prev is not None:
            while az - prev > math.pi:
                az -= 2 * math.pi
            while az - prev < -math.pi:
                az += 2 * math.pi
        prev = az
        ob.rotation_euler = (0, -el, az)
        for path in ("scale", "location", "rotation_euler"):
            ob.keyframe_insert(path, frame=ctx.t0 + fr)
    COUNTS[ctx.coll.name] = COUNTS.get(ctx.coll.name, 0) + 1
    return ob

def add_vine(ctx, tag, name, M, c, thick):
    segs, leaves = vine_frames(c)
    body = M["vineD"] if thick else M["vineL"]
    bmat = M["VINED"] if thick else M["VINEL"]
    N = c["N"]
    for k in range(N):
        tip = k == N - 1
        add_seg(ctx, f"{tag}_{name}_S{k}", M["vineT"] if tip else body, M["VINET"] if tip else bmat, segs[k])
    for li, fr in enumerate(leaves):
        add_seg(ctx, f"{tag}_{name}_VLeaf{li}", M["leafA"] if thick else M["leafB"], M["LEAFA"] if thick else M["LEAFB"], fr, axis="x")

def orbit_path(f0, steps, r, w, h0, h1, ph=0.0):
    out = []
    for i in range(steps + 1):
        u = i / steps
        hz = h0 + (h1 - h0) * math.sin(math.pi * u) ** 0.8
        out.append((f0 + i, (r * (1 - 0.25 * u) * math.cos(w * i + ph), r * (1 - 0.25 * u) * math.sin(w * i + ph), hz)))
    return out

def swirl_in(f0, steps, r0, w, h0, h1, ph=0.0):
    # tourbillon de feuilles pendant la contraction : le rayon diminue, la vitesse angulaire augmente, les feuilles descendent vers le sol
    out = []
    ang = ph
    for i in range(steps + 1):
        u = i / steps
        ang += w * (1 + 1.5 * u)
        r = r0 * (1 - 0.8 * u)
        out.append((f0 + i, (r * math.cos(ang), r * math.sin(ang), h0 + (h1 - h0) * u)))
    return out

def vcfg(**k):
    base = dict(ph=0.0, twist=0.5, wave=0.9, bend=0.3, kappa=2.0, dir=1.0, leaves=())
    base.update(k)
    return base

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        I = IMPACT_C
        add_obj(ctx, f"{tag}_Crack", M["crack"], M["CRACK"], (0, 0, 0.04), [(1, (0.5, 0.5, 1.0)), (2, (0.75, 0.75, 1.0)), (3, (0.9, 0.9, 1.0)), (4, (1.0, 1.0, 1.0)), (I, (1.1, 1.1, 1.0))]
                + [(f, (1.1, 1.1, 1.0)) for f in range(I + 1, 14)] + [(14, (0.7, 0.7, 1.0)), (15, 0.001)], az=10)
        add_obj(ctx, f"{tag}_Glow", M["glow"], M["GLOWD"], (0, 0, 0.08),
                [(1, (0.5, 0.5, 0.5)), (2, (0.8, 0.8, 0.6)), (3, (1.0, 1.0, 0.7)), (4, (1.2, 1.2, 0.8)), (I, (1.5, 1.5, 1.0)), (I + 1, (1.3, 1.3, 0.9)), (I + 3, (1.0, 1.0, 0.6)), (I + 6, (0.7, 0.7, 0.4)), (I + 8, 0.001)])
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 0.8), [(1, 0.001), (I, 0.4), (I + 1, 1.5), (I + 2, 0.4), (I + 3, 0.001)], az=20)
        for i in range(2):
            add_obj(ctx, f"{tag}_Orbit{i}", (M["leafA"], M["leafB"])[i], (M["LEAFA"], M["LEAFB"])[i], (0, 0, 0.5), fade(0.9, 1, I + 2),
                    az=i * 160, el=20, jit=25, drift=300, loc_keys=orbit_path(1, I + 1, 1.2, 0.6, 0.4, 2.8, i * 3.0))
        # 3 grandes lianes qui s'entrelacent (helices autour de l'axe central) + 2 lianes secondaires plus fines
        for i in range(3):
            ra = 20 + 120 * i
            c = vcfg(root=(0.45 * math.cos(math.radians(ra)), 0.45 * math.sin(math.radians(ra)), 0.0), az=ra + 25, pitch=11, L=5.0, N=11, r0=0.30, ts=I + (i % 2), to=I + 3, tc=I + 5, tq=I + 7,
                     twist=1.05, wave=0.85, bend=0.4, kappa=3.0, dir=1.0 if i % 2 == 0 else -1.0, ph=i * 2.1, leaves=((0.4, 0.95, 1), (0.72, 0.8, -1)))
            add_vine(ctx, tag, f"Thick{i}", M, c, True)
        for i in range(2):
            ra = 75 + 180 * i
            c = vcfg(root=(0.9 * math.cos(math.radians(ra)), 0.9 * math.sin(math.radians(ra)), 0.0), az=ra, pitch=30, L=3.8, N=9, r0=0.17, ts=I + 1, to=I + 3, tc=I + 5, tq=I + 7,
                     twist=-0.7, wave=1.0, bend=0.5, kappa=2.2, dir=-1.0 if i == 0 else 1.0, ph=4 + i * 1.7, leaves=((0.6, 0.7, 1),) if i == 0 else ())
            add_vine(ctx, tag, f"Thin{i}", M, c, False)
        # feuilles projetees violemment au surgissement (le long des bras) : conservees et renforcees
        for i in range(5):
            ang = math.radians(90 * (i % 4) + r.uniform(-20, 20))
            sp, vz = r.uniform(4.0, 6.5), r.uniform(8.0, 10.5)
            S = (2.5, 2.0, 1.7, 2.2, 1.4)[i]
            add_obj(ctx, f"{tag}_Fly{i}", (M["leafA"], M["leafB"])[i % 2], (M["LEAFA"], M["LEAFB"])[i % 2], (0, 0, 0.8), fade(S, I, 15),
                    az=r.uniform(0, 360), el=r.uniform(-40, 40), jit=30, drift=r.choice((-1, 1)) * 320, loc_keys=ball_at(I, (sp * math.cos(ang), sp * math.sin(ang), vz), 0.8, 10, 14.0))
        # tourbillon de feuilles pendant la contraction
        for i in range(5):
            add_obj(ctx, f"{tag}_Swirl{i}", (M["leafA"], M["leafB"])[i % 2], (M["LEAFA"], M["LEAFB"])[i % 2], (0, 0, 0.5), fade(1.0, I + 6, 16),
                    az=i * 72, el=15, jit=25, drift=500, loc_keys=swirl_in(I + 6, 10, 2.0, 0.72, 2.6, 0.15, i * 1.26))
        for i in range(2):
            a = math.radians(70 + 180 * i)
            add_obj(ctx, f"{tag}_Speck{i}", M["speck"], M["SPECK"], (0, 0, 0.5), fade(1.2, I, 13), loc_keys=ball_at(I, (2.4 * math.cos(a), 2.4 * math.sin(a), 6.5), 0.5, 8, 18.0))
        for i in range(3):
            a = math.radians(40 + 120 * i)
            add_obj(ctx, f"{tag}_Dirt{i}", M["dirt"], M["DIRTM"], (0, 0, 0.3), fade(1.1, I, 14), tumble=True, loc_keys=ball_at(I, (1.8 * math.cos(a + 0.6), 1.8 * math.sin(a + 0.6), 5.5), 0.3, 9, 18.0))
    else:
        ts = 2 if kind == "segment" else 3
        fwd = kind == "segment"
        add_obj(ctx, f"{tag}_Crack", M["crack"], M["CRACK"], (0, 0, 0.04), [(1, 0.001), (ts - 1 if ts > 2 else 1, 0.001), (ts, (0.5, 0.5, 1.0)), (ts + 1, (0.7, 0.7, 1.0))]
                + [(f, (0.7, 0.7, 1.0)) for f in range(ts + 2, ts + 6)] + [(ts + 6, (0.5, 0.5, 1.0)), (ts + 7, 0.001)], az=r.uniform(0, 90))
        c1 = vcfg(root=(-0.9, -0.3, 0.0) if fwd else (0.5, -0.3, 0.0), az=0 if fwd else 180, pitch=40 if fwd else 38, L=3.2, N=9, r0=0.26, ts=ts, to=ts + 2, tc=ts + 3, tq=ts + 5,
                  twist=0.5, wave=0.9, bend=0.4, kappa=2.2, dir=1.0, ph=r.uniform(0, 6), leaves=((0.5, 0.85, 1),))
        c2 = vcfg(root=(-0.5, 0.5, 0.0) if fwd else (0.2, 0.5, 0.0), az=-20 if fwd else 200, pitch=32, L=2.6, N=7, r0=0.15, ts=ts + 1, to=ts + 2, tc=ts + 3, tq=ts + 5,
                  twist=-0.6, wave=1.0, bend=0.5, kappa=2.4, dir=-1.0, ph=r.uniform(0, 6))
        add_vine(ctx, tag, "Thick0", M, c1, True)
        add_vine(ctx, tag, "Thin0", M, c2, False)
        for i in range(2 if kind == "segment" else 3):
            fv = r.uniform(2.0, 3.5) if i == 0 else r.uniform(-2.5, 2.0)
            if not fwd:
                fv = r.uniform(-2.5, 1.2)
            add_obj(ctx, f"{tag}_Fly{i}", (M["leafA"], M["leafB"])[i % 2], (M["LEAFA"], M["LEAFB"])[i % 2], (0, 0, 0.6), fade(1.2, ts, ts + 9),
                    az=r.uniform(0, 360), el=r.uniform(-40, 40), jit=30, drift=r.choice((-1, 1)) * 320, loc_keys=ball_at(ts, (fv, r.uniform(-0.5, 0.5), r.uniform(6.0, 8.0)), 0.6, 9, 14.0))
        add_obj(ctx, f"{tag}_Speck0", M["speck"], M["SPECK"], (0, 0, 0.5), fade(1.0, ts, ts + 8), loc_keys=ball_at(ts, (r.uniform(-1.5, 1.5), r.uniform(-0.6, 0.6), 6.0), 0.5, 8, 18.0))
        add_obj(ctx, f"{tag}_Dirt0", M["dirt"], M["DIRTM"], (0, 0, 0.3), fade(0.9, ts, ts + 8), tumble=True, loc_keys=ball_at(ts, (r.uniform(-1.5, 1.5), r.uniform(-0.8, 0.8), 4.5), 0.3, 8, 18.0))

def build():
    M = {"FLASH": make_neon("FLASH", "#F4FFB0"), "SPECK": make_neon("SPECK", "#D8FF5A"),
         "LEAFA": make_leaf("LEAFA", "#58C838", 0.3), "LEAFB": make_leaf("LEAFB", "#9BE44F", 0.3),
         "VINED": make_leaf("VINED", "#237A38", 0.3), "VINEL": make_leaf("VINEL", "#2FBF6A", 0.35), "VINET": make_leaf("VINET", "#B6F04A", 0.6),
         "CRACK": make_leaf("CRACK", "#3A2618", 0.05), "DIRTM": make_leaf("DIRTM", "#6B4A32", 0.15), "GLOWD": make_glow("GLOWD", "#B6FF3C", 0.6, 1.4)}
    M["flash"] = blob_mesh("E18_Flash", 0.7, 0.85, 0.5, 33, 2)
    M["speck"] = blob_mesh("E18_Speck", 0.12, 0.9, 0.2, 51, 1)
    M["leafA"] = leaf_mesh("E18_LeafA", 1.0, 0.42, 0.3, 0.2)
    M["leafB"] = leaf_mesh("E18_LeafB", 1.0, 0.36, 0.25, 0.28)
    M["vineD"] = tube_mesh("E18_VineD", 8, 0.92)
    M["vineL"] = tube_mesh("E18_VineL", 8, 0.92)
    M["vineT"] = tube_mesh("E18_VineT", 8, 0.9)
    M["crack"] = crack_mesh("E18_Crack", 8, 0.9, 1.35, 3)
    M["glow"] = orb_mesh("E18_Glow", 4, 1.0, 2, 0.05, 0.1)
    M["dirt"] = rocks_mesh("E18_Dirt", [(0.0, 0.0, 0.0, 0.22)], False, 6)
    for cn in ["E01_CENTER"] + ["E01_SEG1_" + d for d in ARMS] + ["E01_END_" + d for d in ARMS]:
        for o in list(bpy.data.collections[cn].objects):
            bpy.data.objects.remove(o)
    COUNTS.clear()
    build_brick(Ctx(bpy.data.collections["E01_CENTER"], "E", 0.0, 0), "center", M)
    for d in ARMS:
        build_brick(Ctx(bpy.data.collections["E01_SEG1_" + d], d, CELL, T0_SEG), "segment", M)
        build_brick(Ctx(bpy.data.collections["E01_END_" + d], d, 2 * CELL, T0_END), "end", M)
    bpy.context.scene.frame_end = 26
    def alpha_of(o):
        for n in o.data.materials[0].node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                return n.inputs["Alpha"].default_value
        return 1.0
    for cn in ("E01_CENTER", "E01_SEG1_E", "E01_END_E"):
        ms = [o for o in bpy.data.collections[cn].objects if o.type == "MESH"]
        print(cn, "objets", len(ms), "translucides", len([o for o in ms if alpha_of(o) < 0.99]))
    print("polygones :", {m.name: len(m.polygons) for m in M.values() if hasattr(m, "polygons")})
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E18_Nature")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E18_Nature_v7.blend"))

def render():
    from mathutils import Vector
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E18")
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
    for cam, frames in (("CAM_Close", (2, 4, 6, 7, 8, 10, 12, 14, 16, 19)), ("CAM_Game", (6, 9, 12)), ("CAM_Far", (6, 9, 12))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v7_%s_f%02d.png" % ({"CAM_Game": "game", "CAM_Far": "far"}.get(cam, "close"), f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E18_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
