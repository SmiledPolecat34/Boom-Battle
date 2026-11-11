"""E06 Glacée v5 « PICS DE GLACE » : le sol gèle sous un souffle glacial ET de vrais pics de glace translucides jaillissent du sol (grappes de pointes inégales),
entourés de tous les effets glacés (onde, nappe de gel, traînées de poudreuse, brume, éclats, neige). Variante proposée en plus de la V3 validée (V3 non modifiée).
Base v4 :
- Plus de gros volumes blancs opaques : nappe de gel et dalles de glace TRANSLUCIDES bleu glacier à arêtes irrégulières.
- Lames de glace bien visibles au centre et dans le sens de la propagation (secondaires, brèves).
- Nappes de poudreuse / brume qui RELIENT les cases (traînées basses le long des bras).
- Nuances cyan / bleu clair, jamais trop lumineux ; fragments projetés (sans ombres noires) ; neige légère (un émetteur complète en jeu).
- Budget d'objets réduit pour le mobile : voir PIECES_BUDGET affiché à la construction.
Briques composables (CENTER, SEGMENT, END ; 4 directions E/N/S/W). Pilotage (Blender, E01_Classique_v2.blend ouvert) :
    E06_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Écrit E06_Glacee_v5.blend à côté ; E01_Classique_v2.blend n'est jamais écrasé.
"""
import bpy, math, os, random

COL = {"WAVE": "#35AEFF", "WAVE_CORE": "#E4F6FF", "SHEET": "#CDEBFA", "SLAB": "#58B5EE", "MIST": "#BFE4FA",
       "SPIKE": "#8AD4FF", "SPIKE2": "#E2F6FF", "ICE": "#8FD2FA", "ICE2": "#C9ECFF"}
ALPHA = {"MIST": 0.34}
DANGER = "#4AA8E8"
CELL = 4.0
ARMS = {"E": 0.0, "N": 90.0, "S": -90.0, "W": 180.0}
FPS = 24.0
G = 32.0
RNG = random.Random(606)
COUNTS = {}

def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def hex_lin(h):
    h = h.lstrip("#")
    return tuple(lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)

def set_color(mat, hx, alpha=None):
    for n in mat.node_tree.nodes:
        for i in n.inputs:
            if i.name in ("Color", "Base Color", "Emission Color") and hasattr(i, "default_value") and len(i.default_value) == 4:
                i.default_value = hex_lin(hx)
            if alpha is not None and i.name == "Alpha":
                i.default_value = alpha

def make_solid(key, hx):
    # matériau OPAQUE éclairé (Principled) : la glace est solide et se lit par ses facettes, pas par une teinte plate translucide
    m = bpy.data.materials.new("E06_" + key)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_lin(hx)
    b.inputs["Roughness"].default_value = 0.25
    # léger auto-éclairage : la glace reste claire (les faces à l'ombre ne deviennent pas noires) mais garde ses facettes
    b.inputs["Emission Color"].default_value = hex_lin(hx)
    b.inputs["Emission Strength"].default_value = 0.85
    return m

def make_mat(key, hx):
    if key in ("SPIKE", "SPIKE2", "SHEET"):
        return make_solid(key, hx)
    a = ALPHA.get(key)
    m = bpy.data.materials["E01_Smoke" if a else "E01_WhiteHot"].copy()
    m.name = "E06_" + key
    set_color(m, hx, a)
    if a:
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    return m

def mesh_from(name, verts, faces, smooth=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    for p in me.polygons:
        p.use_smooth = smooth
    return me

def ring_mesh():
    segs, ro, ri, h = 24, 1.0, 0.97, 0.03
    v, f = [], []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        c, s = math.cos(a), math.sin(a)
        v += [(ro * c, ro * s, 0), (ro * c, ro * s, h), (ri * c, ri * s, 0), (ri * c, ri * s, h)]
    for k in range(segs):
        a, b = 4 * k, 4 * ((k + 1) % segs)
        f += [(a + 1, b + 1, b + 3, a + 3), (a, a + 2, b + 2, b), (a, b, b + 1, a + 1), (a + 2, a + 3, b + 3, b + 2)]
    return mesh_from("E06_Ring", v, f)

def sheet_mesh():
    # nappe de gel : bord très irrégulier (dentelé), plate
    n = 20
    r = random.Random(7)
    v = [(0, 0, 0.04)]
    for k in range(n):
        a = 2 * math.pi * k / n
        rad = 1.0 * (0.62 + 0.38 * (1.0 if k % 2 else 0.35 + 0.4 * r.random()))
        v.append((rad * math.cos(a), rad * math.sin(a), 0.02))
    return mesh_from("E06_Sheet", v, [(0, 1 + k, 1 + (k + 1) % n) for k in range(n)])

def slab_mesh(name, seed):
    # dalle de glace irrégulière : polygone à 7 côtés extrudé fin, dessus légèrement incliné
    r = random.Random(seed)
    n = 7
    v, top, bot = [], [], []
    for k in range(n):
        a = 2 * math.pi * k / n + r.uniform(-0.2, 0.2)
        rad = r.uniform(0.55, 1.0)
        v.append((rad * math.cos(a), rad * math.sin(a), 0.0))
    for k in range(n):
        x, y, _ = v[k]
        v.append((x * 0.8, y * 0.8, r.uniform(0.18, 0.36)))
    f = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    for k in range(n):
        f.append((k, (k + 1) % n, n + (k + 1) % n, n + k))
    return mesh_from(name, v, f)

def blade_mesh():
    L, w = 1.0, 0.12
    v = [(0, -w, -w), (0, w, -w), (0, w, w), (0, -w, w), (L, 0, 0)]
    return mesh_from("E06_Blade", v, [(0, 1, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)])

def spike_mesh(name, seed):
    # pic de glace : prisme à 5 côtés qui s'effile en pointe irrégulière (base z=0, hauteur 1)
    r = random.Random(seed)
    n = 5
    v, f = [], []
    for k in range(n):
        a = 2 * math.pi * k / n + r.uniform(-0.25, 0.25)
        rad = 0.42 * r.uniform(0.8, 1.2)
        v.append((rad * math.cos(a), rad * math.sin(a), 0.0))
    for k in range(n):
        a = 2 * math.pi * k / n + r.uniform(-0.3, 0.3)
        rad = 0.22 * r.uniform(0.8, 1.2)
        v.append((rad * math.cos(a), rad * math.sin(a), 0.55 + r.uniform(-0.05, 0.05)))
    v.append((r.uniform(-0.02, 0.02), r.uniform(-0.02, 0.02), 1.0))
    top = 2 * n
    f.append(tuple(reversed(range(n))))
    for k in range(n):
        k2 = (k + 1) % n
        f.append((k, k2, n + k2, n + k))
        f.append((n + k, n + k2, top))
    return mesh_from(name, v, f)

def stream_mesh():
    # traînée basse en forme de lentille, longue de 5,2 : relie visuellement les cases le long d'un bras
    n = 14
    v = [(0, 0, 0.3)]
    for k in range(n):
        a = 2 * math.pi * k / n
        v.append((2.6 * math.cos(a), 0.8 * math.sin(a), 0.1))
    return mesh_from("E06_Stream", v, [(0, 1 + k, 1 + (k + 1) % n) for k in range(n)])

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
    for p in me.polygons:
        p.use_smooth = False
    return me

def rot(x, y, deg):
    a = math.radians(deg)
    return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)

class Ctx:
    def __init__(self, coll, arm, ox, t0):
        self.coll, self.arm_deg, self.ox, self.t0 = coll, ARMS[arm], ox, t0
    def world(self, x, y):
        return rot(self.ox + x, y, self.arm_deg)

def add_obj(ctx, name, mesh, mat, loc, scale_keys, loc_keys=None, spin=None, euler=None):
    ob = bpy.data.objects.new(name, mesh)
    if not ob.data.materials:
        ob.data.materials.append(mat)
    ctx.coll.objects.link(ob)
    ob.visible_shadow = False  # pas d'ombres noires portées par les éléments d'effet
    wx, wy = ctx.world(loc[0], loc[1])
    ob.location = (wx, wy, loc[2])
    if euler:
        ob.rotation_euler = euler
    for f, s in scale_keys:
        ob.scale = (s, s, s)
        ob.keyframe_insert("scale", frame=ctx.t0 + f)
    if loc_keys:
        for f, (x, y, z) in loc_keys:
            wx, wy = ctx.world(x, y)
            ob.location = (wx, wy, z)
            ob.keyframe_insert("location", frame=ctx.t0 + f)
    if spin:
        ob.rotation_euler = (0, 0, 0)
        ob.keyframe_insert("rotation_euler", frame=ctx.t0 + 1)
        ob.rotation_euler = spin
        ob.keyframe_insert("rotation_euler", frame=ctx.t0 + 13)
    COUNTS[ctx.coll.name] = COUNTS.get(ctx.coll.name, 0) + 1
    return ob

def ballistic(v0, h0):
    out = []
    for f in range(1, 14):
        t = (f - 1) / FPS
        out.append((f, (v0[0] * t, v0[1] * t, max(0.08, h0 + v0[2] * t - 0.5 * G * t * t))))
    return out

def blade(ctx, tag, n, M, az, el, ln, t_in=2):
    d = math.radians(az)
    start = (0.2 * math.cos(d), 0.2 * math.sin(d), 0.25)
    reach = (0.9 * math.cos(d), 0.9 * math.sin(d), 0.25 + 0.5 * math.sin(math.radians(el)))
    ob = add_obj(ctx, f"{tag}_Blade{n}", M["blade"], M["SPIKE"], start,
                 [(1, 0.001), (t_in, 0.9 * ln), (t_in + 1, 1.15 * ln), (6, 1.0 * ln), (9, 0.001)],
                 [(1, start), (t_in + 1, reach), (9, (reach[0] * 1.15, reach[1] * 1.15, reach[2] + 0.1))])
    ob.rotation_euler = (0, -math.radians(el), math.radians(az) + math.radians(ctx.arm_deg))

def build_brick(ctx, kind, M):
    c = kind == "center"
    big = 1.0 if c else 0.85
    tag = ctx.coll.name
    if c:  # impact : flash bleuté très bref
        add_obj(ctx, tag + "_Flash", M["flash"], M["WAVE_CORE"], (0, 0, 0.9), [(1, 0.4), (2, 1.8), (3, 1.2), (4, 0.001)])
    add_obj(ctx, tag + "_Wave", M["ring"], M["WAVE"], (0, 0, 0.1), [(1, 0.4), (3, 1.5 * big), (4, 1.8 * big), (5, 0.001)])
    # le sol gèle : nappe translucide bleu glacier à bord dentelé, reste jusqu'à la fin
    add_obj(ctx, tag + "_Sheet", M["sheet"], M["SHEET"], (0, 0, 0.0), [(1, 0.001), (2, 1.5 * big), (4, 2.0 * big), (10, 2.0 * big), (13, 1.5 * big)])
    # traînées de poudreuse / brume qui relient les cases le long des bras
    for n in range(0):
        ob = add_obj(ctx, f"{tag}_Stream{n}", M["stream"], M["MIST"], (0, 0, 0.3), [(1, 0.2), (3, 0.9 * big), (7, 1.0 * big), (12, 0.001)])
        ob.rotation_euler = (0, 0, math.radians(ctx.arm_deg + 90 * n))
    for n in range(1 if c else 0):  # brume haute au centre
        a = 2 * math.pi * n / 3
        add_obj(ctx, f"{tag}_Mist{n}", M["puff"], M["MIST"], (0.5 * math.cos(a), 0.5 * math.sin(a), 0.5),
                [(1, 0.15), (3, 0.9), (6, 1.0), (10, 0.7), (13, 0.001)],
                [(1, (0.3 * math.cos(a), 0.3 * math.sin(a), 0.5)), (6, (0.9 * math.cos(a), 0.9 * math.sin(a), 0.9)), (13, (1.4 * math.cos(a), 1.4 * math.sin(a), 1.4))]) if c else None
    # PICS DE GLACE : grappes de pointes translucides qui jaillissent du sol, inégales, un pic dominant ; secondaires en nombre mais bien visibles
    if c:
        spec = [(0.0, 0.0, 3.4, 0, 0), (1.1, 0.0, 2.4, 12, 0), (-0.6, 1.0, 2.7, 14, 120), (-0.6, -1.0, 2.3, 12, 240), (0.9, 1.5, 1.8, 18, 45), (0.9, -1.5, 1.7, 18, 315),
                (1.5, 1.2, 1.4, 22, 60), (-1.4, 0.0, 1.5, 22, 180), (1.5, -1.2, 1.3, 22, 300)]
    elif kind == "segment":
        spec = [(0.0, 0.0, 2.2, 8, 0), (0.8, 1.0, 1.6, 16, 70), (-0.8, -0.9, 1.7, 16, 250), (-0.9, 0.9, 1.3, 20, 140)]
    else:
        spec = [(0.0, 0.0, 3.0, 6, 0), (0.8, 0.9, 2.0, 16, 60), (0.6, -1.0, 1.9, 16, 300), (-0.8, 0.2, 1.5, 22, 170)]
    for n, (px, py, ln, tilt, az) in enumerate(spec):
        t_in = 2 + (n % 3 if c else n % 2)
        ob = add_obj(ctx, f"{tag}_Spike{n}", M["spike"][n % 3], M["SPIKE"] if n % 2 == 0 else M["SPIKE2"], (px, py, 0.0),
                     [(1, 0.001), (t_in, 1.1 * ln), (t_in + 1, ln), (10, ln), (13, 0.001)])
        ob.rotation_euler = (0, math.radians(tilt), math.radians(az) + math.radians(ctx.arm_deg))
    # fragments projetés
    nfr = 6 if c else (2 if kind == "segment" else 3)
    for n in range(nfr):
        a = 2 * math.pi * (n + RNG.random() * 0.4) / nfr
        sp, vz = RNG.uniform(5, 11), RNG.uniform(6, 13)
        s = RNG.uniform(0.8, 1.3)
        add_obj(ctx, f"{tag}_Frag{n}", M["frag"][n % 3], M["ICE"] if n % 2 == 0 else M["ICE2"], (0, 0, 0.5),
                [(1, 0.001), (2, s), (9, s), (12, 0.001)], ballistic((sp * math.cos(a), sp * math.sin(a), vz), 0.5),
                spin=(RNG.uniform(-6, 6), RNG.uniform(-6, 6), RNG.uniform(-6, 6)))
    # grains de neige (aperçu ; en jeu un ParticleEmitter fait l'essentiel)
    for n in range(6 if c else (3 if kind == "segment" else 3)):
        a = RNG.uniform(0, 2 * math.pi)
        sp, vz = RNG.uniform(1.5, 5.0), RNG.uniform(1.5, 5)
        add_obj(ctx, f"{tag}_Snow{n}", M["snow"], M["ICE2"], (0, 0, 0.4),
                [(1, 0.001), (2, RNG.uniform(0.9, 1.6)), (11, 1.0), (13, 0.001)],
                [(f, (x * 0.6, y * 0.6, z + 0.6 + 0.1 * f)) for f, (x, y, z) in ballistic((sp * math.cos(a), sp * math.sin(a), vz), 0.4)])

def build():
    m = bpy.data.materials.get("E01_DangerTile")
    if m:
        set_color(m, DANGER)
    M = {k: make_mat(k, hx) for k, hx in COL.items()}
    M["ring"], M["sheet"], M["blade"], M["stream"] = ring_mesh(), sheet_mesh(), blade_mesh(), stream_mesh()
    M["spike"] = [spike_mesh("E06_Spike%d" % i, 90 + i) for i in range(3)]
    M["puff"] = blob_mesh("E06_Puff", 0.9, 0.5, 0.12, 11)
    M["frag"] = [blob_mesh("E06_Frag%d" % i, 0.16, 0.6, 0.3, 20 + i) for i in range(3)]
    M["snow"] = blob_mesh("E06_Snow", 0.07, 1.0, 0.15, 31, detail=0)
    M["flash"] = blob_mesh("E06_Flash", 0.8, 0.9, 0.05, 41, detail=2)
    for cn in ["E01_CENTER"] + ["E01_SEG1_" + d for d in ARMS] + ["E01_END_" + d for d in ARMS]:
        for o in list(bpy.data.collections[cn].objects):
            bpy.data.objects.remove(o)
    COUNTS.clear()
    build_brick(Ctx(bpy.data.collections["E01_CENTER"], "E", 0.0, 0), "center", M)
    for d in ARMS:
        build_brick(Ctx(bpy.data.collections["E01_SEG1_" + d], d, CELL, 1), "segment", M)
        build_brick(Ctx(bpy.data.collections["E01_END_" + d], d, 2 * CELL, 2), "end", M)
    tri = {}
    for cn in ("E01_CENTER", "E01_SEG1_E", "E01_END_E"):
        tri[cn] = sum(len(o.data.polygons) for o in bpy.data.collections[cn].objects if o.type == "MESH")
    print("PIECES_BUDGET objets (une direction) :", {k: v for k, v in COUNTS.items() if k in tri}, "| faces :", tri)
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E06_Glacee")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E06_Glacee_v5.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E06")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam, frames in (("CAM_Close", (2, 3, 4, 5, 7, 9, 11)), ("CAM_Game", (3, 5, 8))):
        sc.camera = bpy.data.objects[cam]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v5_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E06_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
