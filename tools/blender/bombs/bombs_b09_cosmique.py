"""
Boom Battle - B09 Cosmique v2 : COSMIC GLASS BOMB (cahier des charges du proprietaire).
(v1 = sphere violet foncee opaque a vortex creuse, conservee dans history/ ; ici : coque de VERRE TRANSPARENTE + GALAXIE 3D separee a l'interieur)

Pieces (toutes separees, prevues pour etre animees par script Roblox) :
  COQUE : BombShell_Glass (sphere parfaite R = 1,5 ; Roblox : Glass, Transparency 0,70) ; BombShell_Frame (2 anneaux violet fonce = contours, Metal).
  GALAXIE (inclinee de 32 deg vers la camera du jeu ; axe de rotation = normale du disque, voir manifeste "fx") :
     BombGalaxy_Core (noyau tres lumineux, Neon blanc-rose) ; BombGalaxy_Halo (halo magenta, Neon, Transparency 0,55) ;
     BombGalaxy_ArmsInner / ArmsMid / ArmsOuter (3 bras spiralaires EN VOLUME de section losange, epaisseur et hauteur variables ; rose-blanc -> magenta -> violet electrique, Neon) ;
     BombGalaxy_NebulaViolet / NebulaMagenta (nebuleuses : ellipsoides aplatis, Neon, Transparency 0,55) ; BombGalaxy_Stars (etoiles : petits diamants, Neon blanc).
     Toute la galaxie reste a moins de 1,30 du centre (la coque fait 1,5) : elle ne depasse jamais.
  COL : BombCollar_Base (maillage de B01, violet fonce, Metal) + BombCollar_Rim (2 anneaux brillants Neon rose sur les aretes).
  MECHE : BombFuse_Curved / BombFuse_Tip (courte, TORSADEE a 3 lobes, brun dore) ; BombSpark_Star (etincelle : etoile a 3 pointes, Neon rose-blanc).
Roblox : transparence, Neon, PointLight, ParticleEmitter et animations = script (voir 05_EXPORTS_ROBLOX/VFX/B09_CosmicFX.luau). Rien d'exotique dans le FBX.
Avant = +Y Blender (+Z Roblox) : la galaxie regarde l'avant ; pivoter la bombe en Y vers la camera. Prerequis : bomb_base.py execute dans CE fichier. Idempotent (objets B09_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_B16 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b16_shuriken_debout.py"
exec(compile(open(_B16, encoding="utf-8").read().split("# ---------------------------------------------------------------- nettoyage (uniquement B16_*)")[0], "b16_defs", "exec"))

N09 = {
    "PC":     dict(shell=(28, 14), ring=(24, 4), arm_seg=12, core_sub=2, halo_sub=2, blobs=6, blob_uv=(8, 5), stars=26, rim_seg=20, rope=(12, 3, 22)),
    "MOBILE": dict(shell=(20, 10), ring=(16, 4), arm_seg=8,  core_sub=1, halo_sub=1, blobs=3, blob_uv=None,   stars=10, rim_seg=12, rope=(6, 2, 10)),
}
R_SHELL = 1.5
BODY_C = 1.5                                           # centre de la sphere (pose au sol)
NECK_Z = BODY_C + R_SHELL - 0.20                       # col pose sur le haut de la sphere (comme B01 : 0,20 sous le sommet)
TIP_WORLD9 = Vector((0.95, 0.38, NECK_Z + 1.22))        # bout de la meche : COURTE (la base montait a 1,59)
TILT_GAL = math.radians(-32.0)                          # inclinaison de la galaxie vers la camera du jeu (pitch 55 : normale ~ vers le haut-devant)
GAL = Matrix.Rotation(TILT_GAL, 4, 'X')
GAL_MAX_R = 1.32
GAL_DROP = 0.10                                         # la galaxie est abaissee dans la coque : le col ne la masque plus
COL_SCALE = 0.82                                        # col + meche a l'echelle de la reference (B01 est plus large)

def mat_a(name, hexcol, alpha=1.0, rough=0.4, emit=0.0, metal=0.0):
    """Materiau d'apercu avec transparence (Blender : alpha ; Roblox : Transparency du jeton _Tnn du nom)."""
    m = mat(name, hexcol, rough, emit, metal)
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            try:
                m.blend_method = 'BLEND'
            except Exception:
                pass
    return m

def finish(bm, smooth):
    for f in bm.faces:
        f.smooth = smooth

def mesh_of(bm, name):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me

def signed_volume_fix(bm, faces):
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    vol = 0.0
    for f in faces:
        vs = [v.co for v in f.verts]
        for j in range(1, len(vs) - 1):
            vol += vs[0].dot(vs[j].cross(vs[j + 1])) / 6.0
    if vol < 0:
        bmesh.ops.reverse_faces(bm, faces=faces)

def torus_bm(bm, major, minor, M, m, zc=0.0):
    rows = []
    for i in range(M):
        a = math.tau * i / M
        row = []
        for j in range(m):
            b = math.tau * j / m
            rr = major + minor * math.cos(b)
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), zc + minor * math.sin(b))))
        rows.append(row)
    fs = []
    for i in range(M):
        i2 = (i + 1) % M
        for j in range(m):
            j2 = (j + 1) % m
            fs.append(bm.faces.new((rows[i][j], rows[i][j2], rows[i2][j2], rows[i2][j])))
    signed_volume_fix(bm, fs)

# ---------------------------------------------------------------- coque
def shell_mesh(v):
    cfg = N09[v]
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=cfg["shell"][0], v_segments=cfg["shell"][1], radius=R_SHELL)
    finish(bm, True)
    return mesh_of(bm, f"B09_Shell_{v}")

def frame_mesh(v):
    cfg = N09[v]
    bm = bmesh.new()
    for zc in (1.115, -1.115):                         # anneaux a +/-48 deg de latitude : centre du cercle EXACTEMENT sur la sphere
        torus_bm(bm, math.sqrt(R_SHELL ** 2 - zc ** 2), 0.034, cfg["ring"][0], cfg["ring"][1], zc)
    finish(bm, True)
    return mesh_of(bm, f"B09_Frame_{v}")

# ---------------------------------------------------------------- galaxie
def sphere_bm(sub, radius):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=radius)
    finish(bm, True)
    return bm

def arms_mesh(v):
    cfg = N09[v]
    nseg, n_arms = cfg["arm_seg"], 3
    bm = bmesh.new()
    for k in range(n_arms):
        th0 = k * math.tau / n_arms
        zoff = (-0.12, 0.0, 0.12)[k]                           # les 3 bras sont decales en hauteur : volume
        def P(t):
            t = max(0.0, min(1.0, t))
            r = 0.20 * (1.12 / 0.20) ** t                       # spirale logarithmique de 0,20 a 1,12
            th = th0 + t * math.tau * 1.25
            return Vector((r * math.cos(th), r * math.sin(th), zoff + 0.20 * math.sin(math.tau * 1.1 * t + k * 2.1) * (0.4 + 0.6 * t)))   # ondulation verticale : spirale 3D
        rings = []
        for i in range(nseg + 1):
            t = i / nseg
            p = P(t)
            tg = (P(t + 0.02) - P(t - 0.02)).normalized()
            lat = Vector((0, 0, 1)).cross(tg).normalized()
            up = tg.cross(lat).normalized()
            w = 0.19 * (1 - 0.60 * t) + 0.04                  # largeur : forte au centre, fine a l'exterieur
            h = 0.085 * (1 - 0.40 * t) + 0.03
            rings.append([bm.verts.new(p - lat * w), bm.verts.new(p + up * h), bm.verts.new(p + lat * w), bm.verts.new(p - up * h)])
        fs = []
        for i in range(nseg):
            band = 0 if i < nseg * 0.34 else (1 if i < nseg * 0.67 else 2)
            for a in range(4):
                a2 = (a + 1) % 4
                f = bm.faces.new((rings[i][a], rings[i][a2], rings[i + 1][a2], rings[i + 1][a]))
                f.material_index = band
                fs.append(f)
        c0 = bm.faces.new(rings[0]); c0.material_index = 0; fs.append(c0)
        c1 = bm.faces.new(rings[-1][::-1]); c1.material_index = 2; fs.append(c1)
        signed_volume_fix(bm, fs)
    finish(bm, False)
    bmesh.ops.transform(bm, matrix=GAL, verts=bm.verts)
    return mesh_of(bm, f"B09_Arms_{v}")

def nebula_mesh(v):
    cfg = N09[v]
    rng = random.Random(9)
    bm = bmesh.new()
    spec = [(0.62, 20, 0), (0.80, 85, 1), (0.70, 150, 0), (0.82, 215, 1), (0.60, 280, 1), (0.78, 335, 0)][: cfg["blobs"]]
    for rr, ang, mi in spec:
        tmp = bmesh.new()
        if cfg["blob_uv"]:
            bmesh.ops.create_uvsphere(tmp, u_segments=cfg["blob_uv"][0], v_segments=cfg["blob_uv"][1], radius=1.0)
        else:
            bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=1.0)
        sx, sy, sz = rng.uniform(0.34, 0.40), rng.uniform(0.22, 0.27), rng.uniform(0.10, 0.13)
        a = math.radians(ang)
        pos = Vector((rr * math.cos(a), rr * math.sin(a), rng.uniform(-0.12, 0.12)))
        rot = Matrix.Rotation(a + rng.uniform(-0.6, 0.6), 3, 'Z')
        mp = {}
        for vv in tmp.verts:
            q = rot @ Vector((vv.co.x * sx, vv.co.y * sy, vv.co.z * sz)) + pos
            mp[vv] = bm.verts.new(q)
        for f in tmp.faces:
            nf = bm.faces.new([mp[x] for x in f.verts]); nf.material_index = mi; nf.smooth = True
        tmp.free()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=GAL, verts=bm.verts)
    return mesh_of(bm, f"B09_Nebula_{v}")

def diamond(bm, c, size, rot):
    """Petit diamant (bipyramide) : etoile scintillante."""
    top, bot = Vector((0, 0, 1.7 * size)), Vector((0, 0, -1.7 * size))
    eq = [Vector((size * math.cos(math.pi / 4 + k * math.pi / 2), size * math.sin(math.pi / 4 + k * math.pi / 2), 0)) for k in range(4)]
    pts = [rot @ q + c for q in [top, bot] + eq]
    vs = [bm.verts.new(p) for p in pts]
    fs = []
    for k in range(4):
        k2 = (k + 1) % 4
        fs.append(bm.faces.new((vs[0], vs[2 + k], vs[2 + k2])))
        fs.append(bm.faces.new((vs[1], vs[2 + k2], vs[2 + k])))
    bmesh.ops.recalc_face_normals(bm, faces=fs)

def stars_mesh(v):
    cfg = N09[v]
    rng = random.Random(99)
    bm = bmesh.new()
    placed = 0
    while placed < cfg["stars"]:
        c = Vector((rng.uniform(-1.15, 1.15), rng.uniform(-1.15, 1.15), rng.uniform(-1.0, 1.0)))
        if c.length > 1.12 or c.length < 0.34:
            continue
        rot = Matrix.Rotation(rng.uniform(0, math.tau), 3, 'Z') @ Matrix.Rotation(rng.uniform(0, math.pi), 3, 'X')
        diamond(bm, c, rng.uniform(0.034, 0.062), rot)
        placed += 1
    finish(bm, False)
    bmesh.ops.transform(bm, matrix=GAL, verts=bm.verts)
    return mesh_of(bm, f"B09_Stars_{v}")

# ---------------------------------------------------------------- col, meche, etincelle
def rim_mesh(v):
    cfg = N09[v]
    bm = bmesh.new()
    torus_bm(bm, 0.525, 0.024, cfg["rim_seg"], 4, 0.488)      # arete haute du col
    torus_bm(bm, 0.652, 0.020, cfg["rim_seg"], 4, 0.150)      # arete de la bride
    finish(bm, True)
    return mesh_of(bm, f"B09_Rim_{v}")

def rope_mesh(v):
    sides, lobes, samples = N09[v]["rope"]
    inv = (Matrix.Translation((0, 0, NECK_Z)) @ Matrix.Rotation(TILT, 4, 'Y')).inverted()
    p0 = Vector((0, 0, 0.25))
    p3 = inv @ TIP_WORLD9
    p1 = Vector((0, 0, 0.62))
    p2 = p3 - inv.to_3x3() @ Vector((0.22, 0.09, 0.30))
    bez = lambda t: (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3
    def bez_d(t):
        u = 1 - t
        return (3 * u * u * (p1 - p0) + 6 * u * t * (p2 - p1) + 3 * t * t * (p3 - p2)).normalized()
    sst = lambda a, b, x: (lambda q: q * q * (3 - 2 * q))(max(0.0, min(1.0, (x - a) / (b - a))))
    bm = bmesh.new()
    rings, cents, tans = [], [], []
    nv = None
    for i in range(samples):
        t = i / (samples - 1)
        c, tg = bez(t), bez_d(t)
        if nv is None:
            nv = tg.cross(Vector((0, 1, 0)))
            if nv.length < 1e-4:
                nv = tg.cross(Vector((1, 0, 0)))
        nv = (nv - tg * nv.dot(tg)).normalized()
        bv = tg.cross(nv)
        row = []
        for k in range(sides):
            th = math.tau * k / sides
            rad = 0.17 * (1 + 0.30 * math.cos(lobes * th + 3.0 * math.tau * t)) * (1 + 0.15 * sst(0.80, 0.92, t))   # CORDE : lobes torsades
            row.append(bm.verts.new(c - p0 + (nv * math.cos(th) + bv * math.sin(th)) * rad))
        rings.append(row); cents.append(c - p0); tans.append(tg)
    tip_i = samples - max(2, round(samples * 0.16))
    fs = []
    for i in range(samples - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            f.material_index = 1 if i >= tip_i else 0
            fs.append(f)
    apex = bm.verts.new(cents[-1] + tans[-1] * 0.12)
    for k in range(sides):
        f = bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], apex)); f.material_index = 1; fs.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    f0 = fs[len(fs) // 2]
    ci = len(fs) // 2 // sides
    if f0.normal.dot(f0.calc_center_median() - cents[min(ci, len(cents) - 1)]) < 0:
        bmesh.ops.reverse_faces(bm, faces=fs)
    finish(bm, True)
    return mesh_of(bm, f"B09_Rope_{v}"), p3 - p0, tans[-1]

def spark_mesh(v):
    bm = bmesh.new()
    for axis_rot in (Matrix.Identity(3), Matrix.Rotation(math.pi / 2, 3, 'X'), Matrix.Rotation(math.pi / 2, 3, 'Y')):
        diamond_bm = bmesh.new()
        diamond(diamond_bm, Vector((0, 0, 0)), 0.10, Matrix.Identity(3))
        mp = {}
        for vv in diamond_bm.verts:
            mp[vv] = bm.verts.new(axis_rot @ (vv.co * 1.0))
        for f in diamond_bm.faces:
            bm.faces.new([mp[x] for x in f.verts])
        diamond_bm.free()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    finish(bm, False)
    bmesh.ops.scale(bm, vec=(2.3, 2.3, 2.3), verts=bm.verts)
    return mesh_of(bm, f"B09_Spark_{v}")

# ---------------------------------------------------------------- nettoyage (uniquement B09_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B09_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B09_"):
        bpy.data.collections.remove(c)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

base_root, mob_root = bpy.data.objects["BombVisualRoot"], bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)
M = dict(
    shell=mat_a("DIAG_B09_Shell_Glass_T70", "#8A5CE0", 0.28, 0.06),
    frame=mat_a("DIAG_B09_Frame_Metal", "#2A1060", 1.0, 0.3, 0.0, 0.7),
    core=mat_a("DIAG_B09_Core_Neon", "#FFF0FB", 1.0, 0.3, 5.0),
    halo=mat_a("DIAG_B09_Halo_Neon_T55", "#FF4FE0", 0.5, 0.3, 1.6),
    a_in=mat_a("DIAG_B09_ArmsInner_Neon", "#FF5BE6", 1.0, 0.3, 1.8),
    a_mid=mat_a("DIAG_B09_ArmsMid_Neon", "#D62FD1", 1.0, 0.3, 1.6),
    a_out=mat_a("DIAG_B09_ArmsOuter_Neon", "#8F4BFF", 1.0, 0.3, 1.6),
    n_v=mat_a("DIAG_B09_NebulaViolet_Neon_T55", "#6A2BD6", 0.55, 0.3, 1.4),
    n_m=mat_a("DIAG_B09_NebulaMagenta_Neon_T55", "#C32FD6", 0.55, 0.3, 1.4),
    stars=mat_a("DIAG_B09_Stars_Neon", "#FFFFFF", 1.0, 0.3, 4.0),
    collar=mat_a("DIAG_B09_Collar_Metal", "#3A1F7A", 1.0, 0.3, 0.0, 0.6),
    rim=mat_a("DIAG_B09_Rim_Neon", "#FF7AF0", 1.0, 0.3, 2.5),
    rope=mat_a("DIAG_B09_Rope", "#B8803C", 1.0, 0.7),
    tip=mat_a("DIAG_B09_FuseTip", "#3A2410", 1.0, 0.8),
    spark=mat_a("DIAG_B09_Spark_Neon", "#FFD6FA", 1.0, 0.3, 4.0),
)

report = []
for v, src_root, off in (("PC", base_root, Vector((12, 0, 0))), ("MOBILE", mob_root, Vector((12, 2 * CELL, 0)))):
    sfx = "_Mobile" if v == "MOBILE" else ""
    col = bpy.data.collections.new(f"B09_Cosmique_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B09_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B09", "Cosmique", v
    root["default_explosion"], root["spark_color"] = "E09", "#FFD6FA"
    root["orientation"] = "la galaxie regarde +Z Roblox (avant) ; pivoter en Y pour faire face a la camera"
    body, collar, fuse, neck = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombNeck"))
    att = made["FuseTip_Attachment" + sfx]
    bpy.data.objects.remove(body, do_unlink=True)             # la sphere opaque de la base est remplacee par la coque de verre
    neck.location.z = NECK_Z
    neck.scale = (COL_SCALE, COL_SCALE, COL_SCALE)            # col, anneaux, meche, etincelle : a l'echelle de la reference
    set_obj_materials(collar, [M["collar"]])                  # col = BombCollar_Base de B01, violet fonce metal

    def add(name, mesh, mats, parent=root, loc=(0, 0, BODY_C - GAL_DROP)):
        for m_ in mats:
            mesh.materials.append(m_)
        ob = bpy.data.objects.new("B09_" + name + sfx, mesh)
        col.objects.link(ob)
        ob.parent = parent
        ob.location = loc
        return ob
    add("BombShell_Glass", shell_mesh(v), [M["shell"]], loc=(0, 0, BODY_C))
    add("BombShell_Frame", frame_mesh(v), [M["frame"]], loc=(0, 0, BODY_C))
    core = sphere_bm(N09[v]["core_sub"], 0.30); halo = sphere_bm(N09[v]["halo_sub"], 0.55)
    bmesh.ops.scale(halo, vec=(1, 1, 0.62), verts=halo.verts)                  # bulbe lenticulaire
    bmesh.ops.transform(halo, matrix=GAL, verts=halo.verts)
    add("BombGalaxy_Core", mesh_of(core, f"B09_Core_{v}"), [M["core"]])
    add("BombGalaxy_Halo", mesh_of(halo, f"B09_Halo_{v}"), [M["halo"]])
    arms = add("BombGalaxy_Arms", arms_mesh(v), [M["a_in"], M["a_mid"], M["a_out"]])
    neb = add("BombGalaxy_Nebula", nebula_mesh(v), [M["n_v"], M["n_m"]])
    stars = add("BombGalaxy_Stars", stars_mesh(v), [M["stars"]])
    add("BombCollar_Rim", rim_mesh(v), [M["rim"]], parent=neck, loc=(0, 0, 0))
    rope, tip_local, tip_tan = rope_mesh(v)
    for m_ in (M["rope"], M["tip"]):
        rope.materials.append(m_)
    fuse.data = rope
    att.location = tip_local
    att.rotation_euler = tip_tan.to_track_quat('Z', 'Y').to_euler()
    add("BombSpark_Star", spark_mesh(v), [M["spark"]], parent=att, loc=(0, 0, 0))
    gmax = 0.0
    for o_ in (bpy.data.objects["B09_BombGalaxy_Core" + sfx], bpy.data.objects["B09_BombGalaxy_Halo" + sfx], arms, neb, stars):
        gmax = max(gmax, max((vv.co + Vector((0, 0, -GAL_DROP))).length for vv in o_.data.vertices))
    n_t = sum(tris(o.data) for o in col.all_objects if o.type == 'MESH')
    report.append((v, n_t, gmax))

bpy.context.view_layer.update()
for v, n_t, gmax in report:
    print(f"B09 {v:7s} total {n_t:5d} tris | galaxie : distance max au centre {gmax:.3f} (coque {R_SHELL}) {'OK' if gmax <= GAL_MAX_R else 'DEPASSE'}")
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B09_") and o.name.endswith(suffix) and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w_ = o.matrix_world @ vv.co
                xs.append(w_.x); ys.append(w_.y); zs.append(w_.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
for o in sorted((o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith("B09_") and not o.name.endswith("_Mobile")), key=lambda o: o.name):
    bm = bmesh.new(); bm.from_mesh(o.data)
    ob_edges = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    print(f"    {o.name:28s} {tris(o.data):4d} tris | mats {len(o.data.materials)} | bords ouverts {ob_edges}")
    bm.free()
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
