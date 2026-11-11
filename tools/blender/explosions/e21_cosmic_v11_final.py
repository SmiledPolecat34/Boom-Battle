"""E21 Cosmique V4 (nouvelle direction) : UNE FAILLE SUR L'UNIVERS. Grande ouverture verticale au-dessus de la case centrale, bord dechire lumineux, tunnel sombre bleu nuit/violet, galaxie spirale rose et bleue en profondeur,
nebuleuses et etoiles sur plusieurs plans (parallaxe), asteroides a differentes profondeurs. Cette etape ne contient QUE l'univers (pas la propagation). Pilotage : E21_ACTION = "build" | "render".
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




def eo(u, p=2.2):
    return 1.0 - (1.0 - max(0.0, min(1.0, u))) ** p

def dense(pts):
    out = []
    for (f0, v0), (f1, v1) in zip(pts[:-1], pts[1:]):
        t0 = v0 if isinstance(v0, tuple) else (v0, v0, v0)
        t1 = v1 if isinstance(v1, tuple) else (v1, v1, v1)
        for f in range(f0, f1):
            u = (f - f0) / float(f1 - f0)
            out.append((f, tuple(t0[i] + (t1[i] - t0[i]) * u for i in range(3))))
    out.append(pts[-1])
    out[0] = (out[0][0], out[0][1])
    return out

def up(me):
    # oriente les faces vers l'exterieur/haut (evite l'effet "interieur visible")
    tot = sum(p.normal.z * p.area for p in me.polygons)
    if tot < 0:
        me.flip_normals()
        me.update()
    return me

def dune_mesh(name, seed, nx=16, ny=8, crest=0.4, wall=True):
    # vague/dune (longueur x in [-1,1], largeur y in [-1,1], hauteur ~1) : dos long et doux, front raide qui se courbe vers l'avant (levre en surplomb), crete irreguliere.
    # wall=True : mur de sable sur toute la largeur de la case (continuite d'une case a l'autre) ; wall=False : dune isolee a pente douce, sommet anguleux
    rr = random.Random(seed)
    v, f = [], []
    for j in range(ny + 1):
        y = -1.0 + 2.0 * j / ny
        for i in range(nx + 1):
            x = -1.0 + 2.0 * i / nx
            cx = max(-0.2, min(0.8, crest + 0.28 * math.sin(2.7 * y + seed) + 0.12 * math.sin(7.0 * y + 2 * seed)))
            if x < cx:
                p = ((x + 1.0) / (cx + 1.0)) ** (1.5 if wall else 1.0)
            else:
                p = max(0.0, 1.0 - (x - cx) / (1.0 - cx)) ** 1.05
            lat = max(0.0, 1.0 - abs(y) ** 5) ** 0.8 if wall else max(0.0, 1.0 - abs(y)) ** 0.9
            h = p * lat * (0.88 + 0.24 * rr.random()) if 0 < i < nx and 0 < j < ny else 0.0
            xs = x + (0.34 * h * h if x >= cx - 0.1 else 0.0)
            v.append((xs, y, h))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            f.append((a, a + 1, a + nx + 2, a + nx + 1))
    return smooth(up(mk(name, v, f)))

def mound_mesh(name, seed, rings=5, seg=14, peaks=3):
    # montagne de sable irreguliere (rayon 1, hauteur ~1) : plusieurs sommets, flancs inegaux
    rr = random.Random(seed)
    bumps = [(rr.uniform(-0.45, 0.45), rr.uniform(-0.45, 0.45), rr.uniform(0.18, 0.36)) for _ in range(peaks)]
    wob = [rr.uniform(0.8, 1.2) for _ in range(seg)]
    def hh(x, y, r):
        base = max(0.0, 1.0 - r * r) ** 0.45
        b = sum(a * math.exp(-((x - px) ** 2 + (y - py) ** 2) / 0.22) for px, py, a in bumps)
        return base * 0.7 + b * max(0.0, 1.0 - r) ** 0.6
    v = [(0.0, 0.0, hh(0.0, 0.0, 0.0))]
    for i in range(1, rings + 1):
        r = i / float(rings)
        for j in range(seg):
            a = 2 * math.pi * j / seg
            rad = r * wob[j] if i < rings else r * 0.98
            x, y = rad * math.cos(a), rad * math.sin(a)
            v.append((x, y, hh(x, y, min(1.0, rad)) if i < rings else 0.0))
    f = []
    for j in range(seg):
        f.append((0, 1 + (j + 1) % seg, 1 + j))
    for i in range(1, rings):
        for j in range(seg):
            a, b = 1 + (i - 1) * seg + j, 1 + (i - 1) * seg + (j + 1) % seg
            c, d = 1 + i * seg + (j + 1) % seg, 1 + i * seg + j
            f.append((a, b, c, d))
    return smooth(up(mk(name, v, f)))

def mound_anim(ctx, name, mesh, mat, rx, h, x, y, start, cs, end, az=0.0):
    # surgit brutalement (depassement), tient, puis les flancs s'effondrent (elargissement, affaissement) et le sable retourne dans le sol
    keys = dense([(1, 0.001), (start, (0.5 * rx, 0.5 * rx, 0.1 * h)), (start + 1, (rx, rx, 1.15 * h)), (start + 2, (1.03 * rx, 1.03 * rx, h)),
                  (cs, (1.05 * rx, 1.05 * rx, 0.95 * h)), (cs + 2, (1.25 * rx, 1.25 * rx, 0.5 * h)), (end - 1, (1.45 * rx, 1.45 * rx, 0.15 * h)), (end, 0.001)])
    keys[0] = (1, 0.001)
    lk = [(start, (x, y, -0.15)), (cs, (x, y, -0.15)), (end - 1, (x, y, -0.4)), (end, (x, y, -0.6))]
    return add_obj(ctx, name, mesh, mat, (x, y, -0.15), keys, az=az, loc_keys=lk)

def wave(ctx, name, mesh, mat, start, ang, x0, x1, L, W, H, y0=0.0, ox=0.0):
    # vague : se soulève, avance (sur 8 images), se courbe, s'effondre ; (ang) oriente la crete dans la direction de propagation (centre : 4 bras)
    a = math.radians(ang)
    H = H + 0.3
    keys = dense([(1, 0.001), (start, (0.6 * L, W, 0.3 * H)), (start + 1, (L, W, H)), (start + 4, (L, W, 0.95 * H)), (start + 6, (1.15 * L, W, 0.55 * H)), (start + 8, (1.3 * L, W, 0.2 * H)), (start + 9, 0.001)])
    keys[0] = (1, 0.001)
    lk = []
    for f in range(start, start + 10):
        x = x0 + (x1 - x0) * eo((f - start) / 8.0, 1.3)
        lk.append((f, (ox + x * math.cos(a) - y0 * math.sin(a), x * math.sin(a) + y0 * math.cos(a), -0.3)))
    return add_obj(ctx, name, mesh, mat, (0, 0, -0.3), keys, az=ang, loc_keys=lk)

def sgrain(ctx, name, mesh, mat, start, ang, sp, vz, S, dur, h0=0.4):
    a = math.radians(ang)
    keys = [(1, 0.001), (start, S), (start + dur - 1, S), (start + dur, 0.001)]
    return add_obj(ctx, name, mesh, mat, (0, 0, h0), keys, tumble=True, loc_keys=ball_at(start, (sp * math.cos(a), sp * math.sin(a), vz), h0, dur, 18.0))

def rock(ctx, name, mesh, mat, start, ang, sp, vz, S):
    a = math.radians(ang)
    keys = [(1, 0.001), (start, S), (11, S), (12, 0.5 * S), (13, 0.001)]
    return add_obj(ctx, name, mesh, mat, (0, 0, 0.4), keys, tumble=True, loc_keys=ball_at(start, (sp * math.cos(a), sp * math.sin(a), vz), 0.4, 10, 16.0))

def streak(ctx, name, mesh, mat, s0, x0, x1, off, wd, z, a_deg=0.0, rootx=0.0):
    a = math.radians(a_deg)
    lk = []
    for f in range(s0, s0 + 7):
        x = x0 + (x1 - x0) * eo((f - s0) / 6.0, 1.5)
        lk.append((f, (rootx + x * math.cos(a) - off * math.sin(a), x * math.sin(a) + off * math.cos(a), z)))
    keys = dense([(1, 0.001), (s0, (0.7, 0.3, 0.25)), (s0 + 1, (1.5, wd, 0.3)), (s0 + 3, (1.8, wd + 0.1, 0.32)), (s0 + 5, (1.4, wd, 0.25)), (s0 + 6, 0.001)])
    keys[0] = (1, 0.001)
    return add_obj(ctx, name, mesh, mat, (0, 0, z), keys, az=a_deg, loc_keys=lk)

def cloud(ctx, name, mesh, mat, x, y, z, R, start, hold, end, rise=0.5, ph=0.0, drift=(0.0, 0.0)):
    # nuage qui gonfle (depassement), bouillonne (pulsation) puis se contracte et se dissipe
    keys = [(1, 0.001), (start, 0.35 * R), (start + 1, 1.15 * R), (start + 2, R)]
    f = start + 3
    while f < hold:
        keys.append((f, R * (1.0 + 0.07 * math.sin(1.9 * f + ph))))
        f += 1
    keys += [(hold, R), (end - 1, 0.45 * R), (end, 0.001)]
    keys = dense(sorted(set((a, b) for a, b in keys), key=lambda t: t[0])) if False else keys
    lk = [(start, (x, y, z)), (end, (x + drift[0], y + drift[1], z + rise))]
    return add_obj(ctx, name, mesh, mat, (x, y, z), keys, az=ph * 20, loc_keys=lk)

def bubble(ctx, name, mesh, mat, x, y, start, rise, S, life=5):
    lk = [(start + n, (x + 0.08 * math.sin(n * 2.0 + x), y, 0.3 + rise * eo(n / float(life), 1.4))) for n in range(life + 1)]
    keys = [(1, 0.001), (start, 0.4 * S), (start + 1, S), (start + life - 1, S), (start + life, 1.5 * S), (start + life + 1, 0.001)]
    return add_obj(ctx, name, mesh, mat, (x, y, 0.3), keys, tumble=False, loc_keys=lk)

def shapes_mesh(name, specs, tilt=50.0, sub=3):
    # assemble plusieurs ellipsoides (cx,cy,cz,sx,sy,sz) en UN maillage lisse, puis incline l'ensemble (visage tourne vers la camera, vu de dessus)
    import bmesh
    from mathutils import Vector, Matrix
    bm = bmesh.new()
    for (cx, cy, cz, sx, sy, sz) in specs:
        res = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        for v in res["verts"]:
            v.co = Vector((v.co.x * sx + cx, v.co.y * sy + cy, v.co.z * sz + cz))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(180), 3, "Z"))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(tilt), 3, "X"))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return smooth(me)

def flow(ctx, name, mesh, mat, start, x0, x1, L, W, H, y=0.0, hold=7, end=12, z=0.0):
    # coulee toxique : s'allonge en avancant, ondule, puis se retracte vers le centre et s'affaisse (rien ne reste au sol)
    pts = [(1, 0.001), (start, (0.4 * L, 0.8 * W, 0.3 * H)), (start + 1, (L, W, 1.15 * H)), (start + 4, (1.05 * L, 1.05 * W, H))]
    for f in range(start + 5, hold):
        pts.append((f, (L * (1.0 + 0.05 * math.sin(2.1 * f)), W, H * (1.0 + 0.1 * math.sin(1.7 * f + 1)))))
    pts += [(hold, (L, W, H)), (end - 1, (0.55 * L, 0.7 * W, 0.25 * H)), (end, 0.001)]
    keys = dense(pts) if False else pts
    lk = []
    for f in range(start, end + 1):
        u = (f - start) / 5.0
        x = x0 + (x1 - x0) * eo(u, 1.6) if f <= hold else x1 + (x0 - x1) * 0.6 * (f - hold) / float(max(1, end - hold))
        lk.append((f, (x, y, z)))
    return add_obj(ctx, name, mesh, mat, (x0, y, z), keys, az=r_az(name), loc_keys=lk)

def r_az(name):
    return random.Random(name).uniform(-12, 12)

def spiral_mesh(name, phase, turns=1.25, R=1.9, W=0.55, seg=30, flat=0.06, arms=1):
    # bras de spirale plat (galaxie vue de dessus), effile aux deux bouts ; arms=2 => deux bras opposes dans un seul maillage
    v, f = [], []
    base = 0
    for ar in range(arms):
        ph = phase + ar * 2 * math.pi / arms
        for i in range(seg + 1):
            t = i / float(seg)
            th = ph + turns * 2 * math.pi * t
            rad = R * (0.08 + 0.92 * t ** 0.85)
            w = W * (math.sin(math.pi * min(1.0, t * 1.05)) ** 0.7) * (1.0 - 0.3 * t) + 0.02
            cx, cy = rad * math.cos(th), rad * math.sin(th)
            nx, ny = math.cos(th), math.sin(th)
            v += [(cx + nx * w, cy + ny * w, 0.0), (cx + nx * 0.5 * w, cy + ny * 0.5 * w, flat * w * 3), (cx - nx * 0.5 * w, cy - ny * 0.5 * w, flat * w * 3), (cx - nx * w, cy - ny * w, 0.0), (cx - nx * 0.5 * w, cy - ny * 0.5 * w, -flat * w * 3), (cx + nx * 0.5 * w, cy + ny * 0.5 * w, -flat * w * 3)]
        for i in range(seg):
            for a in range(6):
                b = (a + 1) % 6
                f.append((base + i * 6 + a, base + i * 6 + b, base + (i + 1) * 6 + b, base + (i + 1) * 6 + a))
        base += (seg + 1) * 6
    return smooth(mk(name, v, f))

def starfield_mesh(name, n, seed, mode="disc", R=1.9, smin=0.03, smax=0.085):
    # champ d'etoiles : n minuscules octaedres dans UN SEUL maillage (centaines d'etoiles pour un seul objet Roblox)
    rr = random.Random(seed)
    v, f = [], []
    for k in range(n):
        if mode == "disc":
            t = rr.random() ** 0.8
            ar = rr.randrange(2)
            th = ar * math.pi + 1.25 * 2 * math.pi * t + rr.gauss(0, 0.28)
            rad = R * (0.08 + 0.92 * t ** 0.85) + rr.gauss(0, 0.1)
            x, y, z = rad * math.cos(th), rad * math.sin(th), rr.gauss(0, 0.13) * (1.0 - 0.5 * t)
        elif mode == "halo":
            while True:
                x, y, z = rr.gauss(0, 0.8), rr.gauss(0, 0.8), rr.gauss(0, 0.5)
                if x * x + y * y + z * z < 2.8:
                    break
        else:   # bande (branches)
            x, y, z = rr.uniform(-1.9, 1.9), rr.gauss(0, 0.32), rr.uniform(0.0, 0.7)
        s_ = rr.uniform(smin, smax)
        b0 = len(v)
        v += [(x + s_, y, z), (x - s_, y, z), (x, y + s_, z), (x, y - s_, z), (x, y, z + s_), (x, y, z - s_)]
        f += [(b0, b0 + 2, b0 + 4), (b0 + 2, b0 + 1, b0 + 4), (b0 + 1, b0 + 3, b0 + 4), (b0 + 3, b0, b0 + 4), (b0 + 2, b0, b0 + 5), (b0 + 1, b0 + 2, b0 + 5), (b0 + 3, b0 + 1, b0 + 5), (b0, b0 + 3, b0 + 5)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

import bmesh
from mathutils import Matrix, Vector

A_, B_ = 5.7, 3.9        # demi-largeur / demi-hauteur de la faille (plus grande, plus couchee)
LEAN = -52.0             # inclinaison (degres) : la faille se penche vers la camera
Z0 = 2.5                 # centre de la faille au-dessus du sol

def rift_rim(name, a, b, N=110, seed=1.0):
    # bord dechire irregulier (epaisseur et rayon qui varient), tube a 4 faces dans le plan XY, z>0 = vers le spectateur
    v, f = [], []
    _jr = random.Random(5)
    for k in range(N):
        th = 2 * math.pi * k / N
        rs = 1.0 + 0.08 * math.sin(3 * th + seed) + 0.07 * math.sin(5 * th + 2 * seed) + 0.05 * math.sin(8 * th + 3 * seed) + 0.04 * math.sin(13 * th + seed) + 0.05 * (_jr.random() - 0.5)
        px, py = a * rs * math.cos(th), b * rs * math.sin(th)
        rl = math.hypot(px, py)
        w = 0.014 + 0.03 * (0.5 + 0.5 * math.sin(4 * th + seed)) ** 2 + 0.012 * _jr.random()
        ux, uy = px / rl, py / rl
        for (d, z) in ((-w, 0.14), (w, 0.14), (w, -0.14), (-w, -0.14)):
            v.append((px + ux * d, py + uy * d, z))
    for k in range(N):
        n = (k + 1) % N
        for e in range(4):
            e2 = (e + 1) % 4
            f.append((k * 4 + e, n * 4 + e, n * 4 + e2, k * 4 + e2))
    return smooth(mk(name, v, f))

def dust_mesh(name, n, seed, big=0.07, tiny=0.012, clumps=6):
    # vraie poussiere stellaire : grains tres fins (tetraedres), quelques etoiles plus grosses, amas organiques le long de la branche
    rr = random.Random(seed)
    cs = [(rr.uniform(-1.8, 1.8), rr.uniform(-0.35, 0.35), rr.uniform(0.15, 0.6)) for _ in range(clumps)]
    v, f = [], []
    for k in range(n):
        if rr.random() < 0.3:
            x, y, z = rr.uniform(-1.9, 1.9), rr.gauss(0, 0.4), rr.uniform(0.0, 0.8)
        else:
            c = rr.choice(cs)
            x, y, z = c[0] + rr.gauss(0, 0.4), c[1] + rr.gauss(0, 0.28), c[2] + rr.gauss(0, 0.15)
        s_ = tiny * (1 + 2.2 * rr.random() ** 2) if rr.random() < 0.93 else big * (0.6 + 0.6 * rr.random())
        b0 = len(v)
        v += [(x + s_, y, z - 0.6 * s_), (x - s_ * 0.5, y + 0.87 * s_, z - 0.6 * s_), (x - s_ * 0.5, y - 0.87 * s_, z - 0.6 * s_), (x, y, z + s_)]
        f += [(b0, b0 + 1, b0 + 3), (b0 + 1, b0 + 2, b0 + 3), (b0 + 2, b0, b0 + 3), (b0, b0 + 2, b0 + 1)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def crack_mesh(name, a, b, n=14, seed=4):
    # fissures de la realite : fines dechirures effilees qui partent du bord (dans le plan de la faille)
    rr = random.Random(seed)
    v, f = [], []
    for k in range(n):
        th = 2 * math.pi * (k + rr.uniform(-0.3, 0.3)) / n
        ln = rr.uniform(0.5, 1.5)
        x0, y0 = a * math.cos(th) * 0.98, b * math.sin(th) * 0.98
        d = math.atan2(y0 / b, x0 / a) + rr.uniform(-0.25, 0.25)
        dx, dy = math.cos(d), math.sin(d)
        mx, my = x0 + dx * ln * 0.5 + rr.uniform(-0.15, 0.15), y0 + dy * ln * 0.5 + rr.uniform(-0.15, 0.15)
        ex, ey = x0 + dx * ln, y0 + dy * ln
        w = rr.uniform(0.05, 0.09)
        b0 = len(v)
        v += [(x0 - dy * w, y0 + dx * w, 0), (x0 + dy * w, y0 - dx * w, 0), (mx - dy * w * 0.4, my + dx * w * 0.4, 0), (mx + dy * w * 0.4, my - dx * w * 0.4, 0), (ex, ey, 0)]
        f += [(b0, b0 + 1, b0 + 3), (b0, b0 + 3, b0 + 2), (b0 + 2, b0 + 3, b0 + 4), (b0, b0 + 3, b0 + 1), (b0, b0 + 2, b0 + 3), (b0 + 2, b0 + 4, b0 + 3)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def tunnel_mesh(name, a, b, depth, shrink=0.8, rings=9, N=44):
    # paroi interieure du tunnel (normales vers l'axe) + fond ferme ; z = 0 (bord) -> -depth
    v, f = [], []
    for i in range(rings + 1):
        t = i / float(rings)
        s_ = 1.0 - (1.0 - shrink) * t
        for k in range(N):
            th = 2 * math.pi * k / N
            v.append((a * s_ * math.cos(th), b * s_ * math.sin(th), -depth * t))
    for i in range(rings):
        for k in range(N):
            n = (k + 1) % N
            f.append((i * N + k, i * N + n, (i + 1) * N + n, (i + 1) * N + k))
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    # orienter chaque face vers l'axe central
    for p in me.polygons:
        c = p.center
        toward = Vector((-c.x, -c.y, 0.0))
        if p.normal.dot(toward) < 0:
            idx = list(p.vertices)
    bm = bmesh.new()
    bm.from_mesh(me)
    for fc in bm.faces:
        c = fc.calc_center_median()
        if fc.normal.dot(Vector((-c.x, -c.y, 0.0))) < 0:
            fc.normal_flip()
    bm.to_mesh(me)
    bm.free()
    return smooth(me)

def backdrop_mesh(name, a, b, z, N=44):
    v = [(0, 0, z)] + [(a * math.cos(2 * math.pi * k / N), b * math.sin(2 * math.pi * k / N), z) for k in range(N)]
    f = [(0, 1 + k, 1 + (k + 1) % N) for k in range(N)]
    return mk(name, v, f)

def ell(name, specs, dz=0.0, sub=3):
    me = shapes_mesh(name, specs, tilt=0.0, sub=sub)
    me.transform(Matrix.Translation((0, 0, dz)))
    return me

def starvol_mesh(name, n, seed, z0, z1, smin, smax, ea=2.0, eb=2.5):
    rr = random.Random(seed)
    v, f = [], []
    for k in range(n):
        rad = math.sqrt(rr.random())
        th = rr.uniform(0, 2 * math.pi)
        x, y, z = ea * rad * math.cos(th), eb * rad * math.sin(th), rr.uniform(z0, z1)
        s_ = rr.uniform(smin, smax)
        b0 = len(v)
        v += [(x + s_, y, z), (x - s_, y, z), (x, y + s_, z), (x, y - s_, z), (x, y, z + s_), (x, y, z - s_)]
        f += [(b0, b0 + 2, b0 + 4), (b0 + 2, b0 + 1, b0 + 4), (b0 + 1, b0 + 3, b0 + 4), (b0 + 3, b0, b0 + 4), (b0 + 2, b0, b0 + 5), (b0 + 1, b0 + 2, b0 + 5), (b0 + 3, b0 + 1, b0 + 5), (b0, b0 + 3, b0 + 5)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def baked(me, dz=0.0, dx=0.0, dy=0.0):
    me.transform(Matrix.Translation((dx, dy, dz)))
    return me

def layer(ctx, name, mesh, mat, st, spin=0.0, hold=9, S=1.0, pulse=0.0, loc=(0, 0, Z0), ph=0.0, bump=1.0, dip=0.0, pts_=None):
    # piece de la faille : s'ouvre (depassement), tient, puis se referme ; meme inclinaison pour tout ; rotation propre autour de la normale de la faille (spin deg/image)
    pts = [(1, 0.001), (st, 0.3 * S), (st + 1, 1.12 * S), (st + 2, S)]
    for f in range(st + 3, hold):
        bp = bump * (0.14 if f == 6 else (0.08 if f == 7 else 0.0)) - (dip if f == 5 else 0.0)
        pts.append((f, S * (1.0 + bp + pulse * math.sin(2.4 * f + ph))))
    pts += [(hold, S), (hold + 1, 0.85 * S), (hold + 2, 0.45 * S), (hold + 3, 0.12 * S), (hold + 4, 0.001)]
    if pts_ is not None:
        pts = pts_
    GKs = 1.0 if name.endswith(("_Rim", "_RimGlow", "_Crack", "_Tunnel", "_Void")) else (1.5 if any(t in name for t in ("GDisc", "GArm", "GStars", "GCore")) else 1.3)
    pts = [(fr_, (tuple(c * GKs for c in sv_) if isinstance(sv_, tuple) else sv_ * GKs)) for fr_, sv_ in pts]
    ob = add_obj(ctx, name, mesh, mat, loc, pts)
    ob.rotation_mode = "ZYX"
    for f in range(1, 17):
        ob.rotation_euler = (math.radians(LEAN), 0.0, math.radians(spin * (f - st)))
        ob.keyframe_insert("rotation_euler", frame=ctx.t0 + f)
    return ob

def glint_mesh(name, L=1.0, nlong=4):
    # eclat d'etoile a 4 branches longues + 4 courtes (a plat, double face)
    v, f = [(0, 0, 0)], []
    n = 16
    for k in range(n):
        a_ = 2 * math.pi * k / n
        r = L if k % 4 == 0 else (0.42 * L if k % 2 == 0 else 0.1 * L)
        v.append((r * math.cos(a_), r * math.sin(a_), 0))
    for k in range(n):
        f.append((0, 1 + k, 1 + (k + 1) % n))
        f.append((0, 1 + (k + 1) % n, 1 + k))
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def elong_mesh(name, L=1.8, W=0.22):
    v = [(L, 0, 0), (0, W, 0), (-L, 0, 0), (0, -W, 0)]
    f = [(0, 1, 2), (0, 2, 3), (0, 2, 1), (0, 3, 2)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def rays_mesh(name, n, seed, rmin=0.35, rlo=1.6, rhi=3.2):
    # rayons de lumiere qui partent du noyau (dans le plan de la faille)
    rr = random.Random(seed)
    v, f = [], []
    for k in range(n):
        a_ = 2 * math.pi * k / n + rr.uniform(-0.05, 0.05)
        r1 = rr.uniform(rlo, rhi)
        w = rr.uniform(0.05, 0.11)
        ca, sa = math.cos(a_), math.sin(a_)
        b0 = len(v)
        v += [(rmin * ca - w * sa, rmin * sa + w * ca, 0), (rmin * ca + w * sa, rmin * sa - w * ca, 0), (r1 * ca, r1 * sa, 0)]
        f += [(b0, b0 + 1, b0 + 2), (b0, b0 + 2, b0 + 1)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def streak_mesh(name, R, span, w, seg=8):
    # courte trainee stellaire courbe, effilee
    pts = [(R * math.sin(span * i / seg), R * (1 - math.cos(span * i / seg))) for i in range(seg + 1)]
    v, f = [], []
    for i, (x, y) in enumerate(pts):
        t = i / float(seg)
        ww = w * (1 - t) ** 0.7 + 0.005
        if i < seg:
            nx, ny = pts[i + 1][0] - x, pts[i + 1][1] - y
        else:
            nx, ny = x - pts[i - 1][0], y - pts[i - 1][1]
        ln = math.hypot(nx, ny)
        nx, ny = -ny / ln, nx / ln
        v += [(x + nx * ww, y + ny * ww, 0), (x - nx * ww, y - ny * ww, 0)]
    for i in range(seg):
        a0, a1, b0, b1 = 2 * i, 2 * i + 1, 2 * i + 2, 2 * i + 3
        f += [(a0, a1, b1), (a0, b1, b0), (a0, b1, a1), (a0, b0, b1)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def tw(ctx, name, mesh, mat, loc, st, end, S, ph=0.0, x1=None, rise=0.0, spin=0.0):
    # element scintillant (pousse, scintille, s'eteint) ; peut deriver le long de la branche
    pts = [(1, 0.001), (st, 0.3 * S), (st + 1, 1.15 * S)]
    for f in range(st + 2, end - 1):
        pts.append((f, S * (0.75 + 0.3 * math.sin(2.7 * f + ph))))
    pts += [(end - 1, 0.45 * S), (end, 0.001)]
    lk = None
    if x1 is not None or rise:
        xe = loc[0] if x1 is None else x1
        lk = [(f, (loc[0] + (xe - loc[0]) * eo((f - st) / 5.0, 1.5), loc[1], loc[2] + rise * (f - st) / float(max(1, end - st)))) for f in range(st, end + 1)]
    ob = add_obj(ctx, name, mesh, mat, loc, pts, loc_keys=lk, drift=spin)
    return ob

def gather(ctx, name, mesh, mat, a0, r0, st, end, S):
    # etincelle : particules qui convergent vers le centre
    lk = [(f, (r0 * (1 - (f - st) / float(end - st)) * math.cos(a0), r0 * (1 - (f - st) / float(end - st)) * math.sin(a0), 0.9)) for f in range(st, end + 1)]
    keys = [(1, 0.001), (st, S), (end - 1, 0.5 * S), (end, 0.001)]
    return add_obj(ctx, name, mesh, mat, lk[0][1], keys, tumble=True, loc_keys=lk)

def axis_rays_mesh(name, n, seed, rmin=0.6, rlo=2.5, rhi=7.0):
    # rayons stellaires a plat : surtout dans les 4 directions de la croix, quelques-uns plus courts entre
    rr = random.Random(seed)
    v, f = [], []
    for k in range(n):
        if rr.random() < 0.7:
            a_ = math.radians(90 * rr.randrange(4)) + rr.gauss(0, 0.22)
            r1 = rr.uniform(rlo, rhi)
        else:
            a_ = rr.uniform(0, 2 * math.pi)
            r1 = rr.uniform(rlo * 0.5, rlo * 1.1)
        w = rr.uniform(0.06, 0.14)
        ca, sa = math.cos(a_), math.sin(a_)
        b0 = len(v)
        v += [(rmin * ca - w * sa, rmin * sa + w * ca, 0), (rmin * ca + w * sa, rmin * sa - w * ca, 0), (r1 * ca, r1 * sa, 0)]
        f += [(b0, b0 + 1, b0 + 2), (b0, b0 + 2, b0 + 1)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def flayer(ctx, name, mesh, mat, st, spin=0.0, hold=9, S=1.0, pulse=0.0, ph=0.0, bump=1.0, dip=0.0, pts_=None, z=0.0, grow=0.0):
    # piece de la galaxie a plat : grandit vite depuis le noyau (grow>0 : demarre plus petit), tient, puis se retracte vers le noyau
    pts = [(1, 0.001), (st, 0.3 * S), (st + 1, 0.8 * S), (st + 2, 1.05 * S), (st + 3, 1.0 * S)]
    for f in range(st + 4, hold):
        bp = bump * (0.12 if f == 6 else (0.07 if f == 7 else 0.0)) - (dip if f == 5 else 0.0)
        pts.append((f, S * (1.0 + bp + pulse * math.sin(2.4 * f + ph))))
    pts += [(hold, S), (hold + 1, 0.8 * S), (hold + 2, 0.4 * S), (hold + 3, 0.1 * S), (hold + 4, 0.001)]
    if pts_ is not None:
        pts = pts_
    ob = add_obj(ctx, name, mesh, mat, (0, 0, z), pts)
    ob.rotation_mode = "XYZ"
    for f in range(1, 17):
        ob.rotation_euler = (0.0, 0.0, math.radians(spin * (f - st)))
        ob.keyframe_insert("rotation_euler", frame=ctx.t0 + f)
    return ob

def dust(ctx, name, mesh, mat, b0, e, sc, x0, x1, ph=0.0, wy=1.0, fq=2.9):
    # bande de poussiere d'etoiles : dense et etroite au depart, puis s'etale et scintille avant de s'eteindre
    pts = [(1, 0.001), (b0, (0.5 * sc, 0.3, 0.6)), (b0 + 1, (1.1 * sc, 0.5 * wy, 1.0)), (b0 + 3, (1.25 * sc, 0.85 * wy, 1.0))]
    for f in range(b0 + 4, e - 1):
        k = 0.9 + 0.22 * math.sin(fq * f + ph)
        dec = 1.0 - 0.6 * max(0, f - (b0 + 4)) / float(max(1, e - 2 - (b0 + 4)))
        pts.append((f, (1.2 * sc * k * dec, (0.9 + 0.1 * (f - b0)) * wy * (0.6 + 0.4 * dec), dec)))
    pts += [(e - 1, (0.35 * sc, 1.3 * wy, 0.35)), (e, 0.001)]
    lk = [(f, (x0 + (x1 - x0) * eo((f - b0) / 6.0, 1.6), 0, 0.1)) for f in range(b0, e + 1)]
    return add_obj(ctx, name, mesh, mat, (x0, 0, 0.1), pts, loc_keys=lk)

# ============================================================ V9 : ARCHIPEL STELLAIRE (galaxies projetees puis desintegrees)
import bmesh as _bm
from mathutils import Vector as _V

def ebl(name, specs, sub=3):
    bm = _bm.new()
    for (cx, cy, cz, sx, sy, sz) in specs:
        res = _bm.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        for v in res["verts"]:
            v.co = _V((v.co.x * sx + cx, v.co.y * sy + cy, v.co.z * sz + cz))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return smooth(me)

def stars_at(name, pts):
    v, f = [], []
    for (x, y, z, s_) in pts:
        b0 = len(v)
        v += [(x + s_, y, z), (x - s_, y, z), (x, y + s_, z), (x, y - s_, z), (x, y, z + s_), (x, y, z - s_)]
        f += [(b0, b0 + 2, b0 + 4), (b0 + 2, b0 + 1, b0 + 4), (b0 + 1, b0 + 3, b0 + 4), (b0 + 3, b0, b0 + 4), (b0 + 2, b0, b0 + 5), (b0 + 1, b0 + 2, b0 + 5), (b0 + 3, b0 + 1, b0 + 5), (b0, b0 + 3, b0 + 5)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def ribbons_mesh(name, items):
    v, f = [], []
    for (pts, ws, h, z) in items:
        base = len(v)
        n = len(pts)
        for i, (cx, cy) in enumerate(pts):
            if i < n - 1:
                dx, dy = pts[i + 1][0] - cx, pts[i + 1][1] - cy
            else:
                dx, dy = cx - pts[i - 1][0], cy - pts[i - 1][1]
            L = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / L, dx / L
            w = ws[i]
            t = h * min(1.0, w * 3)
            v += [(cx + nx * w, cy + ny * w, z), (cx + nx * 0.5 * w, cy + ny * 0.5 * w, z + t), (cx - nx * 0.5 * w, cy - ny * 0.5 * w, z + t), (cx - nx * w, cy - ny * w, z), (cx - nx * 0.5 * w, cy - ny * 0.5 * w, z - t), (cx + nx * 0.5 * w, cy + ny * 0.5 * w, z - t)]
        for i in range(n - 1):
            for a in range(6):
                b = (a + 1) % 6
                f.append((base + i * 6 + a, base + i * 6 + b, base + (i + 1) * 6 + b, base + (i + 1) * 6 + a))
    return smooth(mk(name, v, f))

def merge_meshes(name, mes):
    bm = _bm.new()
    for m in mes:
        bm.from_mesh(m)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me

def sp_pts(r0, r1, turns, ph, n=44, ex=0.85):
    out = []
    for i in range(n + 1):
        t = i / float(n)
        th = math.radians(ph) + turns * 2 * math.pi * t
        r = r0 + (r1 - r0) * t ** ex
        out.append((r * math.cos(th), r * math.sin(th)))
    return out

def taper(n, W, p=0.7, fall=0.3):
    return [W * (math.sin(math.pi * min(1.0, (i / float(n)) * 1.05)) ** p) * (1 - fall * i / float(n)) + 0.02 for i in range(n + 1)]

def path_stars(pts, ws, n, seed, spread=0.5, z0=0.4, smin=0.03, smax=0.08):
    rr = random.Random(seed)
    out = []
    m = len(pts) - 1
    for _ in range(n):
        t = rr.random() ** 0.9
        i = min(m - 1, int(t * m))
        x, y = pts[i]
        dx, dy = pts[i + 1][0] - x, pts[i + 1][1] - y
        L = math.hypot(dx, dy) or 1
        o = rr.gauss(0, spread * ws[i] + 0.05)
        out.append((x - dy / L * o, y + dx / L * o, z0 + abs(rr.gauss(0, 0.1)), rr.uniform(smin, smax)))
    return out

def scatter_stars(n, seed, R, z0=0.3, z1=0.6, smin=0.03, smax=0.07):
    rr = random.Random(seed)
    out = []
    for _ in range(n):
        rad = R * math.sqrt(rr.random())
        th = rr.uniform(0, 6.283)
        out.append((rad * math.cos(th), rad * 0.93 * math.sin(th), rr.uniform(z0, z1), rr.uniform(smin, smax)))
    return out

GAL = [dict(R=1.5, na=2, turns=0.9, W=0.55, ph=20, c1="#FF3FB0", c2="#FFB0E8", spin=42, rho=3.2, om=-13, seed=3),
       dict(R=1.2, na=3, turns=0.65, W=0.42, ph=80, c1="#35D8FF", c2="#C0F4FF", spin=-58, rho=3.7, om=10, seed=4),
       dict(R=1.7, na=2, turns=1.1, W=0.6, ph=200, c1="#FFB020", c2="#FFE6A0", spin=30, rho=3.0, om=-8, seed=5),
       dict(R=1.0, na=2, turns=0.75, W=0.4, ph=300, c1="#8C5CFF", c2="#D6C4FF", spin=-66, rho=3.4, om=15, seed=6),
       dict(R=0.65, na=2, turns=0.8, W=0.22, ph=40, c1="#30E890", c2="#C0FFE0", spin=90, rho=3.5, om=9, seed=8)]
for _g, _c3 in zip(GAL, ("#9B4DFF", "#2F6BFF", "#FF5A3C", "#4FA8FF", "#1FC8B0")):
    _g["c3"] = _c3
KDIR = {"E": 0, "N": 1, "W": 2, "S": 3}

def arm_pts(g, a, n=26, amp=0.1):
    rr = random.Random(g["seed"] * 10 + a)
    base = sp_pts(0.22 * g["R"], g["R"], g["turns"], g["ph"] + 360.0 / g["na"] * a, n)
    p1, p2 = rr.uniform(0, 6.28), rr.uniform(0, 6.28)
    out = []
    for i, (x, y) in enumerate(base):
        t = i / float(n)
        r_ = math.hypot(x, y) * (1 + amp * math.sin(5 * t + p1) + amp * 0.6 * math.sin(11 * t + p2))
        th = math.atan2(y, x) + amp * 1.5 * math.sin(4 * t + p2)
        out.append((r_ * math.cos(th), r_ * math.sin(th)))
    return out

def ws_irr(n, W, seed, p=0.7, fall=0.3):
    rr = random.Random(seed)
    ph = [rr.uniform(0, 6.28) for _ in range(3)]
    out = []
    for i, w in enumerate(taper(n, W, p, fall)):
        t = i / float(n)
        m = 0.65 + 0.45 * math.sin(7 * t + ph[0]) ** 2 + 0.2 * math.sin(13 * t + ph[1])
        pinch = 1.0 - 0.85 * math.exp(-((t - (0.25 + 0.4 * ph[2] / 6.28)) / 0.05) ** 2)
        out.append(max(0.02, w * m * pinch))
    return out

def build_gal(M, k):
    g = GAL[k]
    R = g["R"]
    n = 26
    arms = [arm_pts(g, a, n, 0.2) for a in range(g["na"])]
    wss = [ws_irr(n, g["W"], g["seed"] * 13 + a) for a in range(g["na"])]
    rr = random.Random(g["seed"] * 3)
    veil = ebl(f"E21_G{k}V", [(0, 0, 0, R * 1.15, R * 1.05, 0.05), (R * 0.3, -R * 0.2, 0, R * 0.9, R * 0.95, 0.05)], 2)
    items = [(p_, [w * 2.3 for w in w_], 0.1, 0.02) for p_, w_ in zip(arms, wss)]
    for a, p_ in enumerate(arms):
        for j in range(2):
            i0 = rr.randint(6, 18)
            x, y = p_[i0]
            dx, dy = p_[i0 + 1][0] - x, p_[i0 + 1][1] - y
            ang = math.atan2(dy, dx) + math.radians(rr.choice((-1, 1)) * rr.uniform(30, 55))
            L = R * rr.uniform(0.35, 0.6)
            sp = [(x + math.cos(ang + 0.5 * (q / 6.0)) * L * q / 6.0, y + math.sin(ang + 0.5 * (q / 6.0)) * L * q / 6.0) for q in range(7)]
            items.append((sp, [0.02 + 0.25 * g["W"] * math.sin(math.pi * q / 6.0) for q in range(7)], 0.1, 0.02))
    M[f"g{k}body"] = merge_meshes(f"E21_G{k}Body", [veil, ribbons_mesh(f"E21_G{k}W", items)])
    M[f"g{k}armsIn"] = ribbons_mesh(f"E21_G{k}ArmsI", [(p_[:15], [w * 0.62 for w in w_[:15]], 0.1, 0.08) for p_, w_ in zip(arms, wss)])
    M[f"g{k}armsOut"] = ribbons_mesh(f"E21_G{k}ArmsO", [(p_[13:], [w * 0.62 for w in w_[13:]], 0.1, 0.1) for p_, w_ in zip(arms, wss)])
    kn = []
    for a, p_ in enumerate(arms):
        for _ in range(5):
            i = rr.randint(4, 24)
            r_ = rr.uniform(0.03, 0.07) * R
            kn.append((p_[i][0] + rr.gauss(0, 0.04 * R), p_[i][1] + rr.gauss(0, 0.04 * R), 0.16, r_, r_, r_ * 0.6))
        ic = rr.randint(14, 22)
        for _ in range(3):
            kn.append((p_[ic][0] + rr.gauss(0, 0.09 * R), p_[ic][1] + rr.gauss(0, 0.09 * R), 0.16, 0.045 * R, 0.045 * R, 0.03 * R))
    M[f"g{k}knots"] = ebl(f"E21_G{k}Knots", kn, 1)
    M[f"g{k}core"] = ebl(f"E21_G{k}Core", [(0, 0, 0.12, R * 0.34, R * 0.34, R * 0.28)], 2)
    st = []
    for a, (p_, w_) in enumerate(zip(arms, wss)):
        st += path_stars(p_, w_, 26, g["seed"] * 7 + a, 0.8, 0.3, 0.03, 0.07)
        for c in range(3):
            ic = rr.randint(5, 22)
            for _ in range(13):
                st.append((p_[ic][0] + rr.gauss(0, 0.2 * R), p_[ic][1] + rr.gauss(0, 0.2 * R), 0.3 + abs(rr.gauss(0, 0.1)), rr.uniform(0.025, 0.06)))
    st += scatter_stars(60, g["seed"] * 5, R * 1.3, 0.25, 0.5, 0.025, 0.055)
    M[f"g{k}stars"] = stars_at(f"E21_G{k}Stars", st)
    esc = []
    for _ in range(70):
        a_ = rr.uniform(0, 6.283)
        r_ = R * rr.uniform(0.5, 1.4)
        esc.append((r_ * math.cos(a_), r_ * math.sin(a_), rr.uniform(0.25, 0.5), rr.uniform(0.025, 0.06)))
    M[f"g{k}esc"] = stars_at(f"E21_G{k}Esc", esc)
    for i, (ai_, a0_, a1_) in enumerate(((0, 0, 10), (0, 8, 18), (0, 16, 26), (1, 6, 16))):
        M[f"g{k}frag{i}"] = ribbons_mesh(f"E21_G{k}F{i}", [(arms[ai_][a0_:a1_ + 1], [x * 0.5 + 0.03 for x in wss[ai_][a0_:a1_ + 1]], 0.1, 0.08)])
    M[f"g{k}trail"] = dust_mesh(f"E21_G{k}Trail", 140, 130 + k, 0.06, 0.012, 4)
    M[f"g{k}band"] = dust_mesh(f"E21_G{k}Band", 200, 150 + k)

def cloud_mesh(name, seed, n, rmax, smin, smax, z, ey=0.9):
    rr = random.Random(seed)
    specs = []
    for _ in range(n):
        rad = rmax * math.sqrt(rr.random())
        th = rr.uniform(0, 6.283)
        sx = rr.uniform(smin, smax)
        specs.append((rad * math.cos(th), rad * ey * math.sin(th), z, sx, sx * rr.uniform(0.55, 1.0), 0.05))
    return ebl(name, specs, 2)

def build_meshes_v9(M):
    for k, g in enumerate(GAL):
        M[f"GB{k}"] = make_glow(f"GB{k}", g["c1"], 0.2, 1.2)
        M[f"GA{k}"] = make_glow(f"GA{k}", g["c1"], 0.9, 1.7)
        M[f"GC{k}"] = make_glow(f"GC{k}", g["c3"], 0.78, 1.6)
        M[f"GH{k}"] = make_neon(f"GH{k}", g["c2"])
        M[f"GS{k}"] = make_glow(f"GS{k}", g["c2"], 0.95, 1.3)
    M["SHOCKM"] = make_glow("SHOCKM", "#FFE8FF", 0.35, 1.3)
    M["SHOCKB"] = make_glow("SHOCKB", "#7FB0FF", 0.3, 1.3)
    M["CLA"] = make_glow("CLA", "#1A1A80", 0.3, 0.5)
    M["CLB"] = make_glow("CLB", "#4A1AA8", 0.26, 0.7)
    M["CLC"] = make_glow("CLC", "#1F4FD0", 0.2, 0.8)
    M["CLD"] = make_glow("CLD", "#14186E", 0.12, 0.5)
    M["STARG"] = make_glow("STARG", "#FFC850", 0.95, 1.1)
    M["MBP"] = make_glow("MBP", "#FF3FB0", 0.4, 1.2)
    M["MAP"] = make_glow("MAP", "#FF3FD0", 0.95, 1.7)
    M["MHP"] = make_neon("MHP", "#FFD6F2")
    M["MBB"] = make_glow("MBB", "#2F8CFF", 0.36, 1.2)
    M["MAB"] = make_glow("MAB", "#2F7CFF", 0.95, 1.7)
    M["MHB"] = make_neon("MHB", "#D6F4FF")
    M["MGLOW"] = make_glow("MGLOW", "#FFB26B", 0.2, 1.2)
    for k in range(4):
        build_gal(M, k)
    g = GAL[4]
    arms = [arm_pts(g, a, 20) for a in range(2)]
    ws = taper(20, g["W"])
    tiny = merge_meshes("E21_Tiny", [ribbons_mesh("E21_TinyA", [(p_, [w * 1.3 for w in ws], 0.1, 0.1) for p_ in arms]), ebl("E21_TinyC", [(0, 0, 0.12, 0.2, 0.2, 0.17)], 2)])
    for i in range(3):
        M[f"tiny{i}"] = tiny.copy()
    M["tail"] = streak_mesh("E21_Tail", 5.0, 0.5, 0.30)
    M["tailW"] = streak_mesh("E21_TailW", 5.0, 0.5, 0.09)
    M["bandG"] = dust_mesh("E21_BandG", 220, 108)
    # galaxie principale (grande, au centre)
    mg = dict(R=2.9, na=2, turns=1.0, W=0.8, ph=10, seed=21)
    mg2 = dict(R=2.7, na=2, turns=0.85, W=0.55, ph=100, seed=22)
    aP = [arm_pts(mg, a, 30) for a in range(2)]
    aB = [arm_pts(mg2, a, 30) for a in range(2)]
    wP, wB = taper(30, mg["W"]), taper(30, mg2["W"])
    veil = ebl("E21_MVeil", [(0, 0, 0, 3.3, 3.0, 0.06), (0.8, -0.5, 0, 2.7, 2.8, 0.06)], 3)
    M["mBodyP"] = merge_meshes("E21_MBodyP", [veil, ribbons_mesh("E21_MWP", [(p_, [w * 1.5 for w in wP], 0.1, 0.02) for p_ in aP])])
    M["mBodyB"] = ribbons_mesh("E21_MBodyB", [(p_, [w * 1.6 for w in wB], 0.1, 0.03) for p_ in aB])
    M["mArmP"] = ribbons_mesh("E21_MArmP", [(p_, [w * 0.42 for w in wP], 0.1, 0.1) for p_ in aP])
    M["mArmB"] = ribbons_mesh("E21_MArmB", [(p_, [w * 0.42 for w in wB], 0.1, 0.12) for p_ in aB])
    M["mHiP"] = ribbons_mesh("E21_MHiP", [(p_, [w * 0.13 for w in wP], 0.1, 0.16) for p_ in aP])
    M["mHiB"] = ribbons_mesh("E21_MHiB", [(p_, [w * 0.13 for w in wB], 0.1, 0.18) for p_ in aB])
    M["mCore"] = ebl("E21_MCore", [(0, 0, 0.3, 0.95, 0.95, 0.8)], 3)
    M["mGlow"] = ebl("E21_MGlow", [(0, 0, 0.25, 1.7, 1.7, 0.3)], 3)
    st = []
    for a, p_ in enumerate(aP):
        st += path_stars(p_, wP, 50, 300 + a, 0.7, 0.35, 0.04, 0.09)
    st += scatter_stars(70, 310, 3.6, 0.3, 0.6, 0.03, 0.08)
    M["mStarsW"] = stars_at("E21_MStarsW", st)
    st = []
    for a, p_ in enumerate(aB):
        st += path_stars(p_, wB, 50, 320 + a, 0.7, 0.35, 0.04, 0.09)
    st += scatter_stars(40, 330, 3.6, 0.3, 0.6, 0.03, 0.08)
    M["mStarsP"] = stars_at("E21_MStarsP", st)
    # fond cosmique et nebuleuses entre les galaxies
    M["cA"] = cloud_mesh("E21_CloudA", 41, 12, 4.8, 1.6, 3.0, 0.03)
    M["cB"] = cloud_mesh("E21_CloudB", 42, 9, 4.0, 1.2, 2.4, 0.05)
    M["cC"] = cloud_mesh("E21_CloudC", 43, 8, 4.4, 1.0, 2.0, 0.07)
    M["cD"] = cloud_mesh("E21_CloudD", 44, 6, 5.6, 2.2, 3.6, 0.02)
    M["cStW"] = stars_at("E21_CStW", scatter_stars(230, 45, 7.0, 0.25, 0.55, 0.025, 0.06))
    M["cStC"] = stars_at("E21_CStC", scatter_stars(100, 46, 7.0, 0.25, 0.55, 0.025, 0.06))
    M["nebFar"] = ebl("E21_NebFar", [(0.0, 0.3, 0.10, 5.8, 3.6, 0.12), (-3.0, -1.7, 0.10, 2.6, 1.7, 0.1)], 3)
    M["nebBlue"] = ebl("E21_NebBlue", [(3.1, -1.3, 0.12, 3.0, 1.8, 0.1), (-3.6, 1.6, 0.12, 2.1, 1.3, 0.1)], 3)
    M["nebPink"] = ebl("E21_NebPink", [(-2.7, 1.0, 0.14, 2.7, 1.5, 0.1), (3.0, 1.8, 0.14, 1.8, 1.2, 0.09)], 3)
    M["nebCyan"] = ebl("E21_NebCyan", [(-2.4, -1.8, 0.16, 3.1, 1.6, 0.1), (3.3, 1.5, 0.16, 2.5, 1.3, 0.09)], 3)
    M["nebMag"] = ebl("E21_NebMag", [(2.0, -2.1, 0.18, 2.8, 1.5, 0.1), (-3.7, 1.0, 0.18, 2.0, 1.3, 0.09)], 3)
    for i, (r_, sd) in enumerate(((0.38, 7), (0.32, 9), (0.42, 11), (0.3, 13), (0.36, 15))):
        M["rock%d" % (i + 1)] = rocks_mesh("E21_Rock%d" % (i + 1), [(0, 0, 0.0, r_)], False, sd)
    M["rockS"] = rocks_mesh("E21_RockS", [(0, 0, 0.0, 0.22)], False, 17)
    M["raysW"] = axis_rays_mesh("E21_RaysW", 34, 31, 0.6, 2.2, 5.6)
    M["raysB"] = axis_rays_mesh("E21_RaysB", 22, 32, 0.6, 1.8, 4.6)
    M["shock"] = ring_mesh("E21_Shock", 0.97, 1.0, 0.03, 56)

def sm(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)

TL = 6
def pos_c(T, k):
    g = GAL[k]
    a = math.radians(90 * k)
    if T >= TL:
        x = g["rho"] + (4.4 - g["rho"]) * eo((T - TL) / 1.3, 1.3)
        return (x * math.cos(a), x * math.sin(a))
    ang = a + math.radians(g["om"]) * (T - TL)
    r_ = g["rho"] * (0.35 + 0.65 * sm((T - 1.5) / 1.8))
    return (r_ * math.cos(ang), r_ * math.sin(ang))

def app_c(T, k):
    x = (T - (1.4 + 0.25 * k)) / 1.2
    return sm(x) * (1 + 0.12 * math.sin(math.pi * max(0.0, min(1.0, x))))

def gstate(kind, f, k):
    # etat de la galaxie k dans la brique : (x, y, u, T) ou None. u = avancement de la desintegration (0 entiere -> 1 poussiere)
    if kind == "center":
        if f < 1 or f > 7:
            return None
        x, y = pos_c(f, k)
        return (x, y, max(0.0, (f - TL) / 6.5), f)
    if kind == "segment":
        if f < 6 or f > 10:
            return None
        t = (f - 6) / 4.0
        return (0.4 + 2.4 * eo(t, (1.1, 1.35, 1.2, 1.5)[k]), 0.0, 0.2 + 0.42 * t, f + 1)
    if f < 6 or f > 12:
        return None
    t = (f - 6) / 6.0
    return (-0.8 + 2.2 * eo(t, (1.3, 1.1, 1.5, 1.25)[k]), 0.0, 0.55 + 0.45 * t, f + 2)

FR = {"center": (1, 7), "segment": (6, 10), "end": (6, 12)}

def kobj(ctx, name, mesh, mat, sfun, lfun, spin=0.0, az=0.0):
    keys, lk, mx = [], [], 0.0
    for f in range(1, 17):
        sv = sfun(f)
        sv = sv if isinstance(sv, tuple) else (sv, sv, sv)
        sv = tuple(max(0.001, c) for c in sv)
        mx = max(mx, max(sv))
        keys.append((f, sv))
        lk.append((f, lfun(f)))
    if mx < 0.02:
        return None
    return add_obj(ctx, name, mesh, mat, lk[0][1], keys, az=az, drift=spin * 12.0, loc_keys=lk)

def srole(role, u, T):
    def fall(a, b):
        return 1.0 if u <= a else max(0.0, 1.0 - ((u - a) / (b - a)) ** 1.2)
    g_ = min(1.0, u / 0.5)
    if role == "body":
        return fall(0.3, 0.76) * (1 + 0.15 * g_)
    if role == "armsIn":
        return fall(0.4, 0.9) * (1 + 0.15 * g_)
    if role == "armsOut":
        return fall(0.28, 0.8) * (1 + 0.25 * g_)
    if role == "knots":
        return fall(0.4, 0.92)
    if role == "core":
        return fall(0.62, 1.0) * (1 + 0.12 * math.sin(5 * T))
    if role == "esc":
        return sm((u - 0.02) / 0.15) * (1 - sm((u - 0.55) / 0.4)) * (0.8 + 2.2 * u)
    return fall(0.5, 0.97) * (1 + 0.5 * min(1.0, u / 0.6))

def galaxy_pieces(ctx, tag, kind, k, M):
    g = GAL[k]
    fmin, fmax = FR[kind]
    z0 = 0.4 + 0.05 * k
    def st(f):
        return gstate(kind, f, k)
    def lf(f, dx=0.0, dy=0.0, dz=0.0):
        s_ = st(min(max(f, fmin), fmax))
        return (s_[0] + dx, s_[1] + dy, z0 + dz)
    ax = math.radians(90 * k)
    sgn = 1.0 if g["spin"] > 0 else -1.0
    SZ = {"center": 1.0, "segment": 0.92, "end": 0.85}[kind]
    for role, mk_, mat_ in (("body", "body", "GB"), ("armsIn", "armsIn", "GA"), ("armsOut", "armsOut", "GC"), ("knots", "knots", "GS"), ("core", "core", None), ("stars", "stars", "GS"), ("esc", "esc", "GS")):
        def sf(f, role=role):
            s_ = st(f)
            if s_ is None:
                return 0.001
            v = srole(role, s_[2], s_[3])
            return v * SZ * (app_c(s_[3], k) if kind == "center" else 1.0)
        kobj(ctx, f"{tag}_G{k}{role}", M[f"g{k}{mk_}"], M["CORE"] if mat_ is None else M[f"{mat_}{k}"], sf, lf, spin=g["spin"])
    # traine : les bras s'etirent sous la vitesse
    def tail_s(f, wide):
        s_ = st(f)
        if s_ is None or (kind == "center" and s_[3] < TL):
            return 0.001
        a_ = st(min(max(f - 1, fmin), fmax))
        b_ = st(min(max(f + 1, fmin), fmax))
        spd = math.hypot(b_[0] - a_[0], b_[1] - a_[1]) / 2.0
        u = s_[2]
        fade = 1.0 if u < 0.6 else max(0.0, 1.0 - (u - 0.6) / 0.35)
        return (max(0.15, min(1.3, spd / 1.3)) * fade * (1.0 if wide else 1.15), (1.0 - 0.4 * u) * (1.0 if wide else 0.8), 1.0)
    az_t = (180.0 + 90 * k) if kind == "center" else 180.0
    kobj(ctx, f"{tag}_G{k}tail", M["tail"], M[f"GA{k}"], lambda f: tail_s(f, True), lf, az=az_t)
    kobj(ctx, f"{tag}_G{k}tailW", M["tailW"], M["STARW"], lambda f: tail_s(f, False), lambda f: lf(f, 0, 0, 0.12), az=az_t)
    # fragments de bras qui se detachent, puis traine de poussiere d'etoiles
    for i in range(4):
        u0 = 0.15 + 0.05 * i
        lat = (-1.0, 0.35, 1.0, -0.4)[i]
        def fs(f, i=i, u0=u0):
            s_ = st(f)
            if s_ is None or s_[2] < u0:
                return 0.001
            u = s_[2]
            return 0.95 * sm((u - u0) / 0.08) * (1.0 if u <= 0.5 else max(0.0, 1.0 - ((u - 0.5) / 0.5) ** 1.4))
        def fl(f, i=i, u0=u0, lat=lat):
            s_ = st(min(max(f, fmin), fmax))
            du = max(0.0, s_[2] - u0)
            return (s_[0] - (1.4 if i == 1 else 0.9) * du * 2.0, s_[1] + lat * du * 1.3, z0 + 0.7 * du)
        kobj(ctx, f"{tag}_G{k}frag{i}", M[f"g{k}frag{i}"], M[f"GA{k}"], fs, fl, spin=(90, -130, 170, 120)[i] * sgn)
    def trs(f):
        s_ = st(f)
        if s_ is None:
            return 0.001
        up = sm((s_[2] - 0.05) / 0.2) * (1 - sm((s_[2] - 0.85) / 0.15))
        return (0.9 * up, 0.8 * up, up)
    kobj(ctx, f"{tag}_G{k}trail", M[f"g{k}trail"], M[f"GS{k}"], trs, lambda f: lf(f, -0.9 * math.cos(ax) if kind == "center" else -0.9, -0.9 * math.sin(ax) if kind == "center" else 0.0, 0.0), az=(90 * k if kind == "center" else 0.0))

def build_brick(ctx, kind, M):
    tag = ctx.coll.name
    r = random.Random(tag)
    if kind == "center":
        st = 2
        H = 8
        for i in range(8):
            gather(ctx, f"{tag}_Gath{i}", M["star"], M["STARW"], 0.785 * i, 2.5, 1, 3, 0.8)
        tw(ctx, f"{tag}_Spark", M["glintL"], M["STARW"], (0, 0, 1.0), 1, 3, 1.0, spin=90)
        # espace cosmique miniature, nebuleuses et poussiere entre les galaxies
        for nm, mk_, mt, sp in (("CloudD", "cD", "CLD", -1), ("CloudA", "cA", "CLA", 2), ("CloudB", "cB", "CLB", -3), ("CloudC", "cC", "CLC", 4)):
            flayer(ctx, f"{tag}_{nm}", M[mk_], M[mt], st, sp, hold=H, pulse=0.02, bump=1.3, dip=0.04)
        flayer(ctx, f"{tag}_CStW", M["cStW"], M["STARW"], st + 1, 1.5, hold=H + 1, pulse=0.07, bump=1.2)
        flayer(ctx, f"{tag}_CStC", M["cStC"], M["STARC"], st + 1, -1.5, hold=H + 1, pulse=-0.07, bump=1.2)
        for nm, mk_, mt, sp, ph in (("NebFar", "nebFar", "NEBV", 3, 0.0), ("NebBlue", "nebBlue", "NEBB", -4, 1.0), ("NebPink", "nebPink", "NEBP", 5, 2.0), ("NebCyan", "nebCyan", "NEBC", -3, 3.0), ("NebMag", "nebMag", "NEBM", 4, 4.0)):
            flayer(ctx, f"{tag}_{nm}", M[mk_], M[mt], st + 1, sp, hold=H, pulse=0.03, ph=ph, bump=1.5, dip=0.05)
        # galaxie principale au coeur de l'archipel
        for nm, mk_, mt, sp in (("MBodyP", "mBodyP", "MBP", 7), ("MBodyB", "mBodyB", "MBB", -5), ("MArmP", "mArmP", "MAP", 10), ("MArmB", "mArmB", "MAB", -8), ("MHiP", "mHiP", "MHP", 10), ("MHiB", "mHiB", "MHB", -8)):
            flayer(ctx, f"{tag}_{nm}", M[mk_], M[mt], st, sp, hold=H - 1, bump=1.5, dip=0.06)
        flayer(ctx, f"{tag}_MStarsW", M["mStarsW"], M["STARW"], st + 1, 10, hold=H - 1, pulse=0.05, bump=1.5, dip=0.06)
        flayer(ctx, f"{tag}_MStarsP", M["mStarsP"], M["STARP"], st + 1, -8, hold=H - 1, pulse=-0.05, bump=1.5, dip=0.06)
        core = [(1, 0.001), (st, 0.3), (st + 1, 0.7), (st + 2, 1.0), (4, 1.2), (5, 0.35), (6, 1.25), (7, 0.95), (8, 0.75), (9, 0.55), (10, 0.35), (11, 0.2), (12, 0.12), (13, 0.001)]
        flayer(ctx, f"{tag}_MCore", M["mCore"], M["CORE"], st, 0, pts_=core)
        flayer(ctx, f"{tag}_MGlow", M["mGlow"], M["MGLOW"], st, 0, pts_=[(1, 0.001), (st, 0.3), (4, 1.2), (5, 0.5), (6, 1.5), (7, 1.0), (9, 0.75), (11, 0.4), (12, 0.001)])
        # galaxies satellites : orbites differentes, puis expulsion le long des 4 branches
        for k in range(4):
            galaxy_pieces(ctx, tag, "center", k, M)
        for k in range(4):
            tb = 1.4 + 0.25 * k + 0.6
            kobj(ctx, f"{tag}_Birth{k}", M["glintL"], (M["STARW"], M["STARC"], M["STARG"], M["STARP"])[k], lambda f, tb=tb: 1.5 * max(0.0, 1.0 - abs(f - tb) / 1.2), lambda f, k=k: pos_c(f, k) + (0.9,), spin=120)
        # petites galaxies aspirees par le noyau (contraction avant la detonation)
        for i, (a0, mt) in enumerate(((40, "GA4"), (150, "GA1"), (255, "GA0"))):
            def ts(f, i=i):
                if f < 2 or f > 6:
                    return 0.001
                return app_c(f, i) * (1.0 - sm((f - 4.3) / 1.4))
            def tl(f, a0=a0):
                ang = math.radians(a0 + 9 * (f - 5))
                r_ = 3.5 * (1.0 - sm((f - 4) / 1.6))
                return (r_ * math.cos(ang), r_ * math.sin(ang), 0.5)
            kobj(ctx, f"{tag}_Tiny{i}", M[f"tiny{i}"], M[mt], ts, tl, spin=90)
        # asteroides : en orbite, puis projetes avec les galaxies
        for i, (rho, om, zz, mt) in enumerate(((2.7, 11, 1.6, "ROCKA"), (3.3, -9, 2.1, "ROCKB"), (2.4, 13, 1.8, "ROCKA"), (3.6, -12, 2.3, "ROCKB"), (3.0, 7, 1.5, "ROCKA"))):
            a_ = math.radians(90 * i)
            def rs(f, i=i):
                if f < 2:
                    return 0.001
                if i == 4:
                    return 0.001 if f > 6 else (1.0 - sm((f - 4.4) / 1.4))
                return 1.0 if f <= 7 else max(0.0, 1.0 - (f - 7.0) / 1.0)
            def rl(f, i=i, a_=a_, rho=rho, om=om, zz=zz):
                if i == 4:
                    ang = a_ + math.radians(om * (f - 6))
                    r_ = rho * (1.0 - sm((f - 4) / 1.6))
                    return (r_ * math.cos(ang), r_ * math.sin(ang), zz)
                if f <= 6:
                    ang = a_ + math.radians(om * (f - 6))
                    return (rho * math.cos(ang), rho * math.sin(ang), zz)
                x = rho + (f - 6) * 2.4
                return (x * math.cos(a_), x * math.sin(a_), zz + 0.3 * (f - 6))
            kobj(ctx, f"{tag}_Rock{i}", M["rock%d" % (i + 1)], M[mt], rs, rl, spin=(120, -140, 160, -110, 90)[i])
        # contraction lumineuse du noyau (f4-5)
        for i in range(6):
            gather(ctx, f"{tag}_Imp{i}", M["star"], (M["STARW"], M["STARB"], M["STARC"])[i % 3], 1.05 * i + 0.3, 2.3, 4, 6, 0.9)
        # detonation : flash bref blanc-violet, impulsions lumineuses, rayons dans les 4 directions
        add_obj(ctx, f"{tag}_Flash", M["flash"], M["FLASH"], (0, 0, 1.0), [(1, 0.001), (4, 0.1), (5, 0.3), (6, 0.8), (7, 0.3), (8, 0.001)], az=20)
        add_obj(ctx, f"{tag}_FlashHalo", M["flash"], M["FLASHH"], (0, 0, 1.0), [(1, 0.001), (5, 0.001), (6, 1.2), (7, 0.5), (8, 0.001)], az=50)
        for nm, ma_, mxu, dl in (("ShockA", M["SHOCKM"], 0.4, 0), ("ShockB", M["SHOCKB"], 0.3, 1)):
            add_obj(ctx, f"{tag}_{nm}", M["shock"], ma_, (0, 0, 0.3), [(1, 0.001), (6 + dl, (0.4, 0.4, 1.0)), (7 + dl, (2.6 * mxu, 2.6 * mxu, 1.0)), (8 + dl, (4.6 * mxu, 4.6 * mxu, 1.0)), (9 + dl, (6.2 * mxu, 6.2 * mxu, 0.5)), (10 + dl, 0.001)])
        for nm, me_, ma_, sp in (("RaysW", M["raysW"], M["RAYW"], 7), ("RaysB", M["raysB"], M["RAYB"], -5)):
            flayer(ctx, f"{tag}_{nm}", me_, ma_, 5, sp, pts_=[(1, 0.001), (5, 0.3), (6, 1.4), (7, 1.1), (8, 0.6), (9, 0.001)], z=0.4)
        mats3 = (M["STARP"], M["STARB"], M["STARW"], M["STARC"])
        for i in range(8):
            ar = math.radians(90 * (i % 4) + r.uniform(-9, 9))
            sp_ = r.uniform(7.0, 11.0)
            S_ = r.uniform(0.6, 1.1)
            keys = [(1, 0.001), (6, 0.5 * S_), (7, 1.3 * S_), (9, 0.9 * S_), (11, 1.0 * S_), (12, 0.001)]
            lk = [(6 + n_, (sp_ * n_ / 24.0 * math.cos(ar), sp_ * n_ / 24.0 * math.sin(ar), 1.0 + 0.5 * n_ / 6.0)) for n_ in range(7)]
            add_obj(ctx, f"{tag}_Glint{i}", M["glintM"] if i % 2 else M["glintL"], mats3[i % 4], lk[0][1], keys, loc_keys=lk, drift=60)
        tw(ctx, f"{tag}_Last", M["glintL"], M["STARW"], (0, 0, 1.0), 11, 15, 0.8, spin=120)
    else:
        k = KDIR[tag.split("_")[-1]]
        galaxy_pieces(ctx, tag, kind, k, M)
        b0 = 5 if kind == "segment" else 6
        e = 16
        sc = 1.0 if kind == "segment" else 0.85
        tw(ctx, f"{tag}_Flare", M["flare"], M["STARW"], (0, 0, 0.35), b0, b0 + 4, sc * 1.1)
        # poussiere d'etoiles issue de la desintegration : traces blanches et aux couleurs de la galaxie
        dsets = (("bandW", "STARW"), ("band%d" % k, None), ("bandC", "STARC")) if kind == "segment" else (("bandW", "STARW"), ("band%d" % k, None), ("bandC", "STARC"), ("bandG", "STARG"), ("bandM", "STARM"), ("bandV", "STARV"))
        for i, (mk_, mat_) in enumerate(dsets):
            mesh_ = M["g%dband" % k] if mat_ is None else M[mk_]
            mt_ = M["GS%d" % k] if mat_ is None else M[mat_]
            dust(ctx, f"{tag}_Dust{i}", mesh_, mt_, (7 if kind == "segment" else 8) + (i % 2), e - (i % 3), sc, (-1.2 + 0.15 * i) * sc, (0.6 + 0.2 * i) * sc, ph=1.7 * i, wy=1.0 + 0.12 * (i % 3), fq=2.2 + 0.8 * i)
        for i in range(3):
            tw(ctx, f"{tag}_Glint{i}", M["glintM"] if i % 2 else M["glintL"], (M["STARC"], M["STARP"], M["STARG"])[i], (r.uniform(-1.0, 1.0) * sc, r.uniform(-0.45, 0.45), 0.6 + 0.12 * i), b0 + 1 + i, e - i, 0.5 * sc, ph=2.3 * i, spin=20)
        for i in range(1):
            tw(ctx, f"{tag}_Streak{i}", M["streak"], (M["TRAIL"], M["STARC"])[i], (-1.8 * sc, r.uniform(-0.55, 0.55), 0.5 + 0.1 * i), b0 + i + 1, b0 + i + 6, 1.0, x1=(1.2 + 0.3 * i) * sc)
        # fragment d'asteroide emporte avec la galaxie
        def rsf(f):
            s_ = gstate(kind, f, k)
            if s_ is None:
                return 0.001
            return 0.9 * (1.0 - sm((s_[2] - 0.3) / 0.5))
        def rlf(f):
            s_ = gstate(kind, min(max(f, FR[kind][0]), FR[kind][1]), k)
            return (s_[0] + 0.3, 0.7, 1.0 + 0.2 * s_[2])
        kobj(ctx, f"{tag}_RockS", M["rockS"], M["ROCKA"], rsf, rlf, spin=220)

def starburst(ctx, name, mesh, mat, start, ang, sp, vz, S, dur=6, h0=1.0):
    a = math.radians(ang)
    keys = [(1, 0.001), (start, S), (start + 1, 0.5 * S), (start + 2, S), (start + dur - 1, 0.6 * S), (start + dur, 0.001)]
    lk = [(start + n, (sp * n / 24.0 * math.cos(a), sp * n / 24.0 * math.sin(a), h0 + vz * n / 24.0)) for n in range(dur + 1)]
    return add_obj(ctx, name, mesh, mat, lk[0][1], keys, tumble=True, loc_keys=lk)

def build():
    M = {"RIM": make_glow("RIM", "#9C8CFF", 0.55, 0.8), "RIMOUT": make_glow("RIMOUT", "#5A4CE0", 0.12, 1.0), "CRACK": make_glow("CRACK", "#BFB0FF", 0.5, 0.9), "FLASHH": make_glow("FLASHH", "#9A6BFF", 0.28, 1.4), "SPACE": make_glow("SPACE", "#14186E", 0.74, 0.4), "SPACE2": make_glow("SPACE2", "#2A0E78", 0.5, 0.6), "SPACE3": make_glow("SPACE3", "#14186E", 0.22, 0.4), "STARM": make_glow("STARM", "#FF3CC8", 0.95, 1.1), "STARV": make_glow("STARV", "#9B6BFF", 0.95, 1.1), "NEBC": make_glow("NEBC", "#20D8FF", 0.24, 1.0), "NEBM": make_glow("NEBM", "#FF40C0", 0.24, 1.0), "STARC": make_glow("STARC", "#3FEFFF", 0.95, 1.1), "TUNNEL": make_leaf("TUNNEL", "#0B0838", 0.12), "VOID": make_leaf("VOID", "#04061C", 0.0),
         "NEBV": make_glow("NEBV", "#5A2DD0", 0.28, 1.0), "NEBB": make_glow("NEBB", "#2F6BFF", 0.3, 1.1), "NEBP": make_glow("NEBP", "#E040D8", 0.3, 1.1),
         "DISC": make_glow("DISC", "#3A1AA8", 0.8, 0.9), "SPA": make_glow("SPA", "#FF3FD0", 0.95, 1.7), "SPAS": make_glow("SPAS", "#FF6FE0", 0.14, 1.2),
         "SPB": make_glow("SPB", "#2F7CFF", 0.95, 1.7), "SPBS": make_glow("SPBS", "#4F9CFF", 0.14, 1.2), "CORE": make_neon("CORE", "#F6EEFF"),
         "STARW": make_neon("STARW", "#FFFFFF"), "STARP": make_glow("STARP", "#FF58E0", 0.95, 1.1), "STARB": make_glow("STARB", "#4F9BFF", 0.95, 1.1), "TRAIL": make_neon("TRAIL", "#C8D8FF"), "FLASH": make_neon("FLASH", "#FFF0FF"),
         "RAYW": make_glow("RAYW", "#FFE8FF", 0.5, 1.4), "RAYB": make_glow("RAYB", "#7FB0FF", 0.65, 1.5),
         "ROCKA": make_leaf("ROCKA", "#6B34B8", 0.5), "ROCKB": make_leaf("ROCKB", "#8A55DC", 0.55), "GROUND": make_glow("GROUND", "#B050FF", 0.2, 1.0)}
    a, b = A_, B_
    M["rim"] = rift_rim("E21_Rim", a, b)
    M["crack"] = crack_mesh("E21_Crack", a, b)
    M["shock"] = ring_mesh("E21_Shock", 0.97, 1.0, 0.03, 56)
    M["gstarsC"] = starvol_mesh("E21_GStarsC", 110, 99, -1.1, -0.75, 0.035, 0.08, 2.9, 2.2)
    M["bandC"] = dust_mesh("E21_BandC", 240, 104)
    M["tunnel"] = tunnel_mesh("E21_Tunnel", a * 0.97, b * 0.97, 5.0, 0.55, 12)
    M["void"] = backdrop_mesh("E21_Void", a * 0.97 * 0.55, b * 0.97 * 0.55, -5.0)
    M["nebFar"] = ell("E21_NebFar", [(0.0, 0.2, 0, 3.6, 2.2, 0.2), (-1.8, -1.0, 0.1, 1.6, 1.0, 0.18)], -1.5, 3)
    M["nebBlue"] = ell("E21_NebBlue", [(1.9, -0.8, 0, 1.8, 1.1, 0.16), (-2.2, 1.0, 0.1, 1.3, 0.8, 0.14)], -1.2, 3)
    M["nebPink"] = ell("E21_NebPink", [(-1.6, 0.6, 0, 1.6, 0.9, 0.16), (1.8, 1.1, 0.1, 1.1, 0.7, 0.12)], -0.8, 3)
    M["gdisc"] = ell("E21_GDisc", [(0, 0, 0, 3.0, 2.3, 0.09)], -1.0, 3)
    M["armP1"] = baked(spiral_mesh("E21_ArmP1", 0.3, 1.2, 2.9, 0.42, arms=2), -0.9)
    M["armP2"] = baked(spiral_mesh("E21_ArmP2", 0.3, 1.2, 2.9, 0.95, arms=2), -0.95)
    M["armB1"] = baked(spiral_mesh("E21_ArmB1", 1.9, 1.4, 3.1, 0.3, arms=2), -0.85)
    M["armB2"] = baked(spiral_mesh("E21_ArmB2", 1.9, 1.4, 3.1, 0.7, arms=2), -0.9)
    M["gstarsW"] = starvol_mesh("E21_GStarsW", 200, 91, -1.1, -0.75, 0.035, 0.08, 2.9, 2.2)
    M["gstarsP"] = starvol_mesh("E21_GStarsP", 140, 92, -1.1, -0.75, 0.035, 0.08, 2.9, 2.2)
    M["sDeepW"] = starvol_mesh("E21_SDeepW", 260, 111, -3.7, -2.6, 0.025, 0.05, 4.2, 2.9)
    M["sDeepB"] = starvol_mesh("E21_SDeepB", 160, 112, -3.4, -2.4, 0.025, 0.05, 4.2, 2.9)
    M["sDeepP"] = starvol_mesh("E21_SDeepP", 120, 113, -3.4, -2.4, 0.025, 0.05, 4.2, 2.9)
    M["nebCyan"] = ell("E21_NebCyan", [(-1.5, -1.1, 0, 1.9, 1.0, 0.16), (2.0, 0.9, 0.1, 1.5, 0.8, 0.14)], -2.6, 3)
    M["nebMag"] = ell("E21_NebMag", [(1.2, -1.3, 0, 1.7, 0.9, 0.15), (-2.3, 0.6, 0.1, 1.2, 0.8, 0.12)], -2.0, 3)
    M["gcore"] = ell("E21_GCore", [(0, 0, 0, 0.6, 0.6, 0.4)], -0.85, 2)
    M["sFarW"] = starvol_mesh("E21_SFarW", 220, 93, -1.7, -1.3, 0.025, 0.05, 4.0, 2.7)
    M["sFarP"] = starvol_mesh("E21_SFarP", 120, 94, -1.7, -1.3, 0.025, 0.05, 4.0, 2.7)
    M["sMidB"] = starvol_mesh("E21_SMidB", 90, 95, -1.4, -0.5, 0.04, 0.08, 4.0, 2.7)
    M["sMidW"] = starvol_mesh("E21_SMidW", 90, 96, -1.4, -0.5, 0.04, 0.08, 4.0, 2.7)
    M["sNearW"] = starvol_mesh("E21_SNearW", 40, 97, -0.4, 0.2, 0.04, 0.09, 4.0, 2.7)
    M["sNearP"] = starvol_mesh("E21_SNearP", 30, 98, -0.4, 0.2, 0.04, 0.09, 4.0, 2.7)
    for i, (x, y, z, r_, sd) in enumerate(((-3.9, -0.4, 0.55, 0.95, 7), (3.6, 1.2, 0.35, 0.7, 9), (2.0, -2.3, -0.6, 0.5, 11), (-2.2, 1.9, -1.2, 0.36, 13), (0.6, 2.6, 0.5, 0.45, 15), (-3.1, -1.7, -0.3, 0.4, 17), (3.4, -1.5, 0.9, 0.55, 19), (-1.0, -2.4, -1.8, 0.3, 21), (1.4, 2.2, -2.5, 0.4, 23), (-3.6, 1.0, -3.0, 0.5, 25))):
        M["rock%d" % (i + 1)] = baked(rocks_mesh("E21_Rock%d" % (i + 1), [(x, y, 0.0, r_)], False, sd), z)
    M["gnd"] = orb_mesh("E21_Ground", 99, 1.0, 3, 0.05, 0.1)
    M["flash"] = blob_mesh("E21_Flash", 0.7, 0.85, 0.5, 33, 2)
    M["star"] = blob_mesh("E21_Star", 0.1, 0.9, 0.3, 73, 1)
    M["raysW"] = rays_mesh("E21_RaysW", 40, 31, 0.5, 1.8, 4.8)
    M["raysB"] = rays_mesh("E21_RaysB", 28, 32, 0.5, 1.5, 3.8)
    M["glintL"] = glint_mesh("E21_GlintL", 0.9)
    M["glintM"] = glint_mesh("E21_GlintM", 0.6)
    M["flare"] = elong_mesh("E21_Flare", 1.9, 0.22)
    M["streak"] = streak_mesh("E21_Streak", 1.4, 0.8, 0.04)
    M["bandW"] = dust_mesh("E21_BandW", 260, 101)
    M["bandP"] = dust_mesh("E21_BandP", 220, 102)
    M["bandB"] = dust_mesh("E21_BandB", 240, 103)
    M["bandM"] = dust_mesh("E21_BandM", 200, 106)
    M["bandV"] = dust_mesh("E21_BandV", 200, 107)
    build_meshes_v9(M)
    for cn in ["E01_CENTER"] + ["E01_SEG1_" + d for d in ARMS] + ["E01_END_" + d for d in ARMS]:
        for o in list(bpy.data.collections[cn].objects):
            bpy.data.objects.remove(o)
    COUNTS.clear()
    build_brick(Ctx(bpy.data.collections["E01_CENTER"], "E", 0.0, 0), "center", M)
    for d in ARMS:
        build_brick(Ctx(bpy.data.collections["E01_SEG1_" + d], d, CELL, 1), "segment", M)
        build_brick(Ctx(bpy.data.collections["E01_END_" + d], d, 2 * CELL, 2), "end", M)
    bpy.context.scene.frame_end = 26
    for cn in ("E01_CENTER", "E01_SEG1_E", "E01_END_E"):
        print(cn, "objets", len([o for o in bpy.data.collections[cn].objects if o.type == "MESH"]))
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E21_Cosmic")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E21_Cosmic_v11.blend"))

def ensure_cams():
    sc = bpy.context.scene
    if "CAM_Top" not in bpy.data.objects:
        cd = bpy.data.cameras.new("CAM_Top")
        cd.lens = 28
        cam = bpy.data.objects.new("CAM_Top", cd)
        sc.collection.objects.link(cam)
        cam.location = (0, 0, 20)
        cam.rotation_euler = (0, 0, 0)

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E21")
    os.makedirs(out, exist_ok=True)
    ensure_cams()
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 15)),):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v11_close_f%02d.png" % f)
            bpy.ops.render.render(write_still=True)
    return out

def make_multi():
    if "MULTI_ON" in bpy.data.objects:
        return
    sc = bpy.context.scene
    names = ["E01_CENTER"] + ["E01_SEG1_" + d for d in ARMS] + ["E01_END_" + d for d in ARMS]
    for k, (dx, dy) in enumerate(((16, -8), (-12, 12), (4, 20))):
        for cn in names:
            em = bpy.data.objects.new(f"MULTI_{k}_{cn}", None)
            em.instance_type = "COLLECTION"
            em.instance_collection = bpy.data.collections[cn]
            em.location = (dx, dy, 0)
            sc.collection.objects.link(em)
    sc.collection.objects.link(bpy.data.objects.new("MULTI_ON", None))

def render_video(cam, tag, f0=1.0, f1=19.0, step=0.25):
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E21", "video_v11_" + tag)
    os.makedirs(out, exist_ok=True)
    ensure_cams()
    if tag == "multi":
        make_multi()
    sc = bpy.context.scene
    sc.camera = bpy.data.objects[cam]
    i0 = int(round((f0 - 1.0) / step))
    n = int(round((f1 - 1.0) / step)) + 1
    for i in range(i0, n):
        f = 1.0 + i * step
        sc.frame_set(int(f), subframe=f - int(f))
        sc.render.filepath = os.path.join(out, "f%03d.png" % i)
        bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E21_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
elif action == "video":
    print(render_video(globals()["E21_CAM"], globals()["E21_TAG"], globals().get("E21_F0", 1.0), globals().get("E21_F1", 19.0)))
