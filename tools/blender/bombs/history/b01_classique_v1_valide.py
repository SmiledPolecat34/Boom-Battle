"""
Boom Battle - Phase 1 : bombe B01 Classique (reproductible, idempotent).

Convention : 1 unite Blender = 1 stud Roblox ; une case de grille = 4 studs ; sol a Z = 0.
Ne touche qu'aux collections B01_Classique et B01_DIAG. Materiaux = DIAGNOSTIC uniquement.

Hierarchie exportable (collection B01_Classique) :
  BombVisualRoot            origine au centre du sol (pivot de pose / squash)
  |- BombBody_Base          origine au centre de la sphere
  |- BombSkin_Details       vide, reserve aux accessoires specifiques d'un skin
  `- BombNeck               pivot a la base de la collerette (legerement incline)
     |- BombCollar_Base     collerette (revolution)
     `- BombFuse_Curved     meche (tube sur courbe de Bezier), origine = entree dans la collerette
        `- FuseTip_Attachment   point d'attache de la future etincelle (axe Z = tangente de la meche)
Collection B01_DIAG (a ne PAS exporter) : grille 3x3 de cases, etoile d'etincelle de previsualisation.
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

# ------------------------------------------------------------------ parametres
D = 3.0                       # diametre du corps (studs) : ~75 % d'une case de 4
R = D * 0.5
Z_SQUASH = 0.97               # leger tassement = impression de poids
BODY_SEG, BODY_RINGS = 32, 16
COLLAR_SEG = 24
TILT = math.radians(10.0)     # inclinaison de la collerette vers +X (comme l'illustration)
FUSE_R = 0.21
FUSE_SIDES = 8
FUSE_SAMPLES = 18
CELL = 4.0
SHARP_ANGLE = math.radians(60.0)
TIP_WORLD = Vector((1.35, 0.55, 4.30))      # bout de la meche (repere racine)
OUT_BLEND = r"C:\Users\steve\Boom-Battle\assets\3D\BOOM_BATTLE_ART\02_BLENDER\BASE\B01_Classique.blend"
SAVE = True

# ------------------------------------------------------------------ utilitaires
def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def mat(name, hexcol, rough=0.4, emit=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        if not m.node_tree:
            m.use_nodes = True
    except Exception:
        pass
    rgb = srgb(hexcol)
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*rgb, 1)
    return m

def clear_collections():
    for name in ("B01_Classique", "B01_DIAG"):
        col = bpy.data.collections.get(name)
        if col:
            for o in list(col.all_objects):
                bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.collections.remove(col)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)

def new_col(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c

def empty(name, col, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), kind='PLAIN_AXES', size=0.3):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type, e.empty_display_size = kind, size
    e.location, e.rotation_euler = loc, rot
    col.objects.link(e)
    e.parent = parent
    return e

def finish_bm(bm, smooth=True, sharp_angle=SHARP_ANGLE):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for e in bm.edges:
        try:
            if e.is_manifold and e.calc_face_angle() > sharp_angle:
                e.smooth = False
        except Exception:
            pass
    for f in bm.faces:
        f.smooth = smooth

def mesh_obj(name, bm, col, parent, loc, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    me.update()
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    ob.parent = parent
    ob.location = loc
    return ob

def flip_if_inward(bm, faces_radial):
    """faces_radial : liste de (face, vecteur radial attendu vers l'exterieur)."""
    f, rad = max(faces_radial, key=lambda t: t[1].length)
    if f.normal.dot(rad) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)

# ------------------------------------------------------------------ construction
def build():
    sc = bpy.context.scene
    sc.unit_settings.system, sc.unit_settings.scale_length = 'METRIC', 1.0
    clear_collections()
    col, dcol = new_col("B01_Classique"), new_col("B01_DIAG")

    m_body = mat("DIAG_B01_Body", "#23262e", 0.35)
    m_collar = mat("DIAG_B01_Collar", "#5b6373", 0.45)
    m_fuse = mat("DIAG_B01_Fuse", "#c8742e", 0.7)
    m_tip = mat("DIAG_B01_FuseTip", "#2a1c12", 0.8)

    root = empty("BombVisualRoot", col, size=0.8)
    root["bomb_id"], root["bomb_name"] = "B01", "Classique"
    root["units"], root["grid_cell_studs"] = "1 Blender unit = 1 stud", CELL

    # --- corps
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=BODY_SEG, v_segments=BODY_RINGS, radius=R)
    bmesh.ops.scale(bm, vec=(1, 1, Z_SQUASH), verts=bm.verts)
    finish_bm(bm)
    body_h = 2 * R * Z_SQUASH
    mesh_obj("BombBody_Base", bm, col, root, (0, 0, body_h / 2), [m_body])

    empty("BombSkin_Details", col, parent=root, size=0.4)

    # --- collerette
    neck_z = body_h - 0.20
    neck = empty("BombNeck", col, parent=root, loc=(0, 0, neck_z), rot=(0, TILT, 0), size=0.5)
    prof = [(0.66, -0.20), (0.66, 0.13), (0.645, 0.18), (0.61, 0.205), (0.57, 0.21),
            (0.57, 0.42), (0.55, 0.47), (0.50, 0.50), (0.34, 0.50), (0.30, 0.50),
            (0.30, 0.22), (0.12, 0.16)]
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in prof]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), dvec=(0, 0, 0),
                   angle=math.tau, steps=COLLAR_SEG, use_merge=True, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    flip_if_inward(bm, [(f, Vector((f.calc_center_median().x, f.calc_center_median().y, 0))) for f in bm.faces])
    finish_bm(bm)
    mesh_obj("BombCollar_Base", bm, col, neck, (0, 0, 0), [m_collar])

    # --- meche (repere local de la collerette)
    inv = (Matrix.Translation((0, 0, neck_z)) @ Matrix.Rotation(TILT, 4, 'Y')).inverted()
    p0 = Vector((0, 0, 0.25))
    p3 = inv @ TIP_WORLD
    p1 = Vector((0, 0, 1.05))
    p2 = p3 - inv.to_3x3() @ Vector((0.55, 0.30, 0.30))

    def bez(t):
        u = 1 - t
        return u**3 * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t**3 * p3

    def bez_d(t):
        u = 1 - t
        return (3 * u * u * (p1 - p0) + 6 * u * t * (p2 - p1) + 3 * t * t * (p3 - p2)).normalized()

    def smoothstep(a, b, x):
        x = max(0.0, min(1.0, (x - a) / (b - a)))
        return x * x * (3 - 2 * x)

    bm = bmesh.new()
    rings, tans, centers = [], [], []
    n_vec = None
    for i in range(FUSE_SAMPLES):
        t = i / (FUSE_SAMPLES - 1)
        c, tg = bez(t), bez_d(t)
        if n_vec is None:
            n_vec = tg.cross(Vector((0, 1, 0)))
            if n_vec.length < 1e-4:
                n_vec = tg.cross(Vector((1, 0, 0)))
        n_vec = (n_vec - tg * n_vec.dot(tg)).normalized()
        b_vec = tg.cross(n_vec)
        rad = FUSE_R * (1 + 0.18 * smoothstep(0.80, 0.92, t))
        ring = [bm.verts.new(c - p0 + (n_vec * math.cos(a) + b_vec * math.sin(a)) * rad)
                for a in (math.tau * k / FUSE_SIDES for k in range(FUSE_SIDES))]
        rings.append(ring); tans.append(tg); centers.append(c - p0)
    tip_idx = FUSE_SAMPLES - 3
    faces_info = []
    for i in range(FUSE_SAMPLES - 1):
        for k in range(FUSE_SIDES):
            k2 = (k + 1) % FUSE_SIDES
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            f.material_index = 1 if i >= tip_idx else 0
            faces_info.append((f, f.calc_center_median() - centers[i]))
    apex = bm.verts.new(centers[-1] + tans[-1] * FUSE_R * 0.7)
    for k in range(FUSE_SIDES):
        f = bm.faces.new((rings[-1][k], rings[-1][(k + 1) % FUSE_SIDES], apex))
        f.material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    flip_if_inward(bm, faces_info)
    finish_bm(bm)
    fuse = mesh_obj("BombFuse_Curved", bm, col, neck, p0, [m_fuse, m_tip])

    tip_local = (p3 - p0)
    rot = tans[-1].to_track_quat('Z', 'Y').to_euler()
    empty("FuseTip_Attachment", col, parent=fuse, loc=tip_local, rot=rot, kind='ARROWS', size=0.3)

    # --- diagnostic (hors export)
    bm = bmesh.new()
    for sz, ang, L in ((0, 0, 0.46), (1, math.radians(45), 0.30)):
        pts = [(L, 0, 0), (-L, 0, 0), (0, L, 0), (0, -L, 0), (0, 0, L), (0, 0, -L)]
        vv = [bm.verts.new(Matrix.Rotation(ang, 3, 'Z') @ Vector(p)) for p in pts]
        for sx in (0, 1):
            for sy in (2, 3):
                for sz_ in (4, 5):
                    bm.faces.new((vv[sx], vv[sy], vv[sz_]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = False
    spark = mesh_obj("DIAG_SparkPreview", bm, dcol, None, TIP_WORLD + tans[-1] * 0.0, [mat("DIAG_Spark", "#ffb02e", 0.3, 1.2)])
    # l'etoile est posee au bout reel de la meche
    bpy.context.view_layer.update()
    spark.location = bpy.data.objects["FuseTip_Attachment"].matrix_world.translation

    bm = bmesh.new()
    mats_grid = [mat("DIAG_Cell_A", "#8c939e", 0.9), mat("DIAG_Cell_B", "#7a818c", 0.9)]
    for gx in range(-1, 2):
        for gy in range(-1, 2):
            x0, y0 = gx * CELL - CELL / 2, gy * CELL - CELL / 2
            vv = [bm.verts.new((x0 + dx, y0 + dy, -0.002)) for dx, dy in ((0, 0), (CELL, 0), (CELL, CELL), (0, CELL))]
            f = bm.faces.new(vv)
            f.material_index = (gx + gy) % 2
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh_obj("DIAG_Grid3x3", bm, dcol, None, (0, 0, 0), mats_grid)
    bpy.context.view_layer.update()

def metrics():
    dg = bpy.context.evaluated_depsgraph_get()
    tot_t = tot_m = 0
    for o in bpy.data.collections["B01_Classique"].all_objects:
        if o.type != 'MESH':
            continue
        me = o.evaluated_get(dg).to_mesh()
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        print(f"{o.name:18s} tris={tris:4d} verts={len(me.vertices):4d} mats={len(o.data.materials)} "
              f"world_min={tuple(round(x, 2) for x in mn)} world_max={tuple(round(x, 2) for x in mx)}")
        tot_t += tris; tot_m += 1
        o.evaluated_get(dg).to_mesh_clear()
    print(f"TOTAL B01 : {tot_m} meshes, {tot_t} triangles")

build()
metrics()
if SAVE:
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath or OUT_BLEND)
    print("Sauvegarde :", bpy.data.filepath)
