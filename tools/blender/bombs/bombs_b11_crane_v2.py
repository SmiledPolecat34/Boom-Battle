"""
Boom Battle - B11 Crane v2 : crane SCULPTE en volume, creux reels, dents individuelles.
(remplace la v1 = 2 ellipsoides + motifs plaques, conservee dans history/)

Construction par operations booleennes exactes (Blender) :
  UNION       : cranium + maxillaire + machoire + 2 pommettes + 2 arcades sourcilieres  -> volume du crane avec ses plis
  DIFFERENCE  : 2 orbites + cavite nasale + fente de la bouche + plan du sol (pied plat) -> creux REELS, interieur sombre
  + dents     : 5 dents hautes et 5 dents basses (boites biseautees) dans la fente
Ombrage lisse avec aretes franches la ou le volume plie (angle > 40 deg).
Pieces exportees (2 materiaux d'un meme objet BombBody_Base) : BombBody_Bone (os + dents), BombBody_Cavity (interieur sombre) ;
+ virole fine sombre (Ninja) + meche lisse. Avant = +Y Blender (+Z Roblox) : pivoter en Y vers la camera a l'integration.
Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B11_*).
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

_B16 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b16_shuriken_debout.py"
exec(compile(open(_B16, encoding="utf-8").read().split("# ---------------------------------------------------------------- nettoyage (uniquement B16_*)")[0], "b16_defs", "exec"))

SKV = {
    "PC":     dict(cr=(26, 15), fa=(18, 11), jw=(18, 11), ch=(10, 6), br=(10, 6), eye=(14, 8), nose=(10, 6), mouth=(16, 8),
                   tooth_bevel=False, collar_seg=20, fuse=(10, 26)),
    "MOBILE": dict(cr=(18, 10), fa=(14, 8), jw=(14, 8), ch=(8, 5), br=(8, 5), eye=(10, 6), nose=(8, 5), mouth=(12, 6),
                   tooth_bevel=False, collar_seg=12, fuse=(8, 14)),
}
SHARP_DEG = 55                                       # n'arete franche que pour les vraies ruptures (rebords des creux, dessous des arcades)
SMOOTH_ITERS, SMOOTH_FACTOR = 2, 0.35                # lissage doux des plis d'union (hors rebords des creux et pied plat)

# volumes (centre, rayons) ; avant = +Y ; sol = z 0
CR_C, CR_R = Vector((0.0, -0.10, 1.82)), (1.38, 1.20, 1.00)        # cranium
FA_C, FA_R = Vector((0.0, 0.42, 1.20)), (1.10, 0.82, 0.55)         # maxillaire (face) : large, raccorde cranium et machoire
JW_C, JW_R = Vector((0.0, 0.48, 0.60)), (1.00, 0.74, 0.62)         # machoire
CH_C, CH_R = Vector((0.80, 0.66, 1.38)), (0.27, 0.30, 0.20)        # pommette (x > 0, miroir en x)
BR_C, BR_R = Vector((0.50, 0.88, 2.16)), (0.58, 0.23, 0.20)        # arcade sourciliere (x > 0) : moins saillante
# creux
EY_C, EY_R = Vector((0.50, 1.05, 1.80)), (0.45, 0.52, 0.40)        # orbite (x > 0), inclinee
NS_C, NS_R = Vector((0.0, 1.12, 1.36)), (0.15, 0.28, 0.27)         # cavite nasale
MO_C, MO_R = Vector((0.0, 1.05, 0.90)), (0.86, 0.50, 0.165)        # fente de la bouche
EYE_TILT = 12                                                      # deg : orbites inclinees vers le bas, vers l'exterieur

def ell_mesh(name, c, r, seg, rings, mat, tilt_deg=0.0):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    rot = Matrix.Rotation(math.radians(tilt_deg), 3, 'Y')
    for v in bm.verts:
        v.co = rot @ Vector((v.co.x * r[0], v.co.y * r[1], v.co.z * r[2])) + c
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    me.materials.append(mat)
    return me

def link_obj(me, coll, hide=True):
    ob = bpy.data.objects.new(me.name, me)
    coll.objects.link(ob)
    if hide:
        ob.hide_render = True
    return ob

def mirrored(c):
    return Vector((-c.x, c.y, c.z))

def skull_mesh(v, m_bone, m_dark):
    cfg = SKV[v]
    sc = bpy.context.scene
    for o in [o for o in bpy.data.objects if o.name.startswith("tmp_")]:          # restes d'un essai interrompu
        bpy.data.objects.remove(o, do_unlink=True)
    for c_ in [c_ for c_ in bpy.data.collections if c_.name.startswith("TMP_")]:
        bpy.data.collections.remove(c_)
    for t_ in [t_ for t_ in bpy.data.meshes if t_.name.startswith("tmp_") and t_.users == 0]:
        bpy.data.meshes.remove(t_)
    cu = bpy.data.collections.new("TMP_U"); cd = bpy.data.collections.new("TMP_D")
    base = bpy.data.collections.new("TMP_BASE")
    for c_ in (cu, cd, base):
        sc.collection.children.link(c_)
    tmp_meshes = []
    def part(name, c, r, sg, mat, coll, tilt=0.0):
        me = ell_mesh(name, c, r, sg[0], sg[1], mat, tilt)
        tmp_meshes.append(me)
        return link_obj(me, coll)
    target = part("tmp_cranium", CR_C, CR_R, cfg["cr"], m_bone, base)
    part("tmp_face", FA_C, FA_R, cfg["fa"], m_bone, cu)
    part("tmp_jaw", JW_C, JW_R, cfg["jw"], m_bone, cu)
    for sgn in (1, -1):
        part(f"tmp_cheek{sgn}", Vector((sgn * CH_C.x, CH_C.y, CH_C.z)), CH_R, cfg["ch"], m_bone, cu)
        part(f"tmp_brow{sgn}", Vector((sgn * BR_C.x, BR_C.y, BR_C.z)), BR_R, cfg["br"], m_bone, cu)
        part(f"tmp_eye{sgn}", Vector((sgn * EY_C.x, EY_C.y, EY_C.z)), EY_R, cfg["eye"], m_dark, cd, tilt=-sgn * EYE_TILT)
    part("tmp_nose", NS_C, NS_R, cfg["nose"], m_dark, cd)
    part("tmp_mouth", MO_C, MO_R, cfg["mouth"], m_dark, cd)
    # plan du sol : coupe a z = 0 (pied plat), face de coupe = os
    fb = bmesh.new()
    bmesh.ops.create_cube(fb, size=1.0)
    for vv in fb.verts:
        vv.co = Vector((vv.co.x * 8, vv.co.y * 8, vv.co.z * 2 - 1.0))
    fme = bpy.data.meshes.new("tmp_floor"); fb.to_mesh(fme); fb.free(); fme.materials.append(m_bone)
    tmp_meshes.append(fme); link_obj(fme, cd)

    m1 = target.modifiers.new("U", 'BOOLEAN')
    m1.operation, m1.operand_type, m1.collection, m1.solver = 'UNION', 'COLLECTION', cu, 'EXACT'
    m2 = target.modifiers.new("D", 'BOOLEAN')
    m2.operation, m2.operand_type, m2.collection, m2.solver = 'DIFFERENCE', 'COLLECTION', cd, 'EXACT'
    for m_ in (m1, m2):
        try:
            m_.material_mode = 'TRANSFER'
        except Exception as e:
            print("material_mode indisponible :", e)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    target_mesh = target.data
    # nettoyage temporaire
    for c_ in (cu, cd, base):
        for o in list(c_.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c_)
    for nm in {t.name for t in tmp_meshes} | {target_mesh.name}:                     # (le cranium figure deux fois : dedoublonner par nom)
        t = bpy.data.meshes.get(nm)
        if t is not None and t.users == 0:
            bpy.data.meshes.remove(t)
    return me

def tooth_geometry(bm, x, y_front, z0, z1, w, depth, bevel):
    n0 = len(bm.faces)
    ret = bmesh.ops.create_cube(bm, size=1.0)
    vs = ret["verts"]
    for vv in vs:
        vv.co = Vector((x + vv.co.x * w, y_front - depth / 2 + vv.co.y * depth, (z0 + z1) / 2 + vv.co.z * (z1 - z0)))
    if bevel:
        edges = list({e for vv in vs for e in vv.link_edges})
        bmesh.ops.bevel(bm, geom=edges, offset=0.022, segments=1, affect='EDGES')

def jaw_front_y(x, z):
    q = 1 - (x / JW_R[0]) ** 2 - ((z - JW_C.z) / JW_R[2]) ** 2
    yj = JW_C.y + JW_R[1] * math.sqrt(max(q, 0.0))
    q2 = 1 - (x / FA_R[0]) ** 2 - ((z - FA_C.z) / FA_R[2]) ** 2
    yf = FA_C.y + FA_R[1] * math.sqrt(max(q2, 0.0))
    return min(yj, yf)

def finish_skull(me, v):
    cfg = SKV[v]
    bm = bmesh.new(); bm.from_mesh(me)
    pinned = set()
    for e in bm.edges:                                            # rebords des creux (limite os / creux) : jamais deplaces
        if len(e.link_faces) == 2 and e.link_faces[0].material_index != e.link_faces[1].material_index:
            pinned.update(e.verts)
    pinned.update(vv for vv in bm.verts if abs(vv.co.z) < 1e-4)  # pied plat
    free = [vv for vv in bm.verts if vv not in pinned]
    for _ in range(SMOOTH_ITERS):
        bmesh.ops.smooth_vert(bm, verts=free, factor=SMOOTH_FACTOR, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    for k in range(5):                                            # 5 dents hautes + 5 dents basses
        x = (k - 2) * 0.185
        yf = jaw_front_y(x, 0.90) - 0.05
        tooth_geometry(bm, x, yf, 0.905, 1.045, 0.16, 0.22, cfg["tooth_bevel"])
        tooth_geometry(bm, x, yf, 0.755, 0.895, 0.16, 0.22, cfg["tooth_bevel"])
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        try:
            if e.is_manifold and e.calc_face_angle() > math.radians(SHARP_DEG):
                e.smooth = False
        except Exception:
            pass
    out = bpy.data.meshes.new(me.name + "_final")
    bm.to_mesh(out); bm.free()
    for m in me.materials:
        out.materials.append(m)
    # les dents (nouvelles faces) prennent l'index 0 = os
    return out

# ---------------------------------------------------------------- nettoyage (uniquement B11_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B11_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B11_"):
        bpy.data.collections.remove(c)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

diag = bpy.data.collections["BOMB_BASE_DIAG"]
base_root, mob_root = bpy.data.objects["BombVisualRoot"], bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)
spark_src = bpy.data.objects["DIAG_SparkPreview"]
spark_loc = spark_src.location.copy()
m_fuse, m_tip = mat("DIAG_Fuse", "#C8742E", 0.7), mat("DIAG_FuseTip", "#2A1C12", 0.8)
m_bone = mat("DIAG_B11_Bone", "#EDE6D3", 0.45)
m_dark = mat("DIAG_B11_Cavity", "#17141B", 0.7)
m_collar = mat("DIAG_B11_Collar", "#2A2A2E", 0.45)

report = []
for v, src_root, off in (("PC", base_root, Vector((4, 0, 0))), ("MOBILE", mob_root, Vector((4, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B11_Crane_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B11_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B11", "Crane", v
    root["default_explosion"], root["spark_color"] = "E24", "#C8F7FF"
    root["orientation"] = "avant = +Z Roblox ; pivoter en Y pour faire face a la camera"
    body, collar, fuse = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"))
    neck = find_part(made, "BombNeck")
    raw = skull_mesh(v, m_bone, m_dark)
    me = finish_skull(raw, v)
    if raw.users == 0:
        bpy.data.meshes.remove(raw)
    me.name = f"B11_Skull_{v}"
    body.data = me
    body.location = (0, 0, 0)
    neck_z = CR_C.z + CR_R[2] - 0.10
    neck.location.z = neck_z
    cme = ninja_collar_mesh(f"B11_Collar_{v}", SKV[v]["collar_seg"]); cme.materials.append(m_collar); collar.data = cme
    fme = ninja_fuse_mesh(f"B11_Fuse_{v}", *SKV[v]["fuse"]); fme.materials.append(m_fuse); fme.materials.append(m_tip); fuse.data = fme
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B11_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off + Vector((0, 0, neck_z - BASE_NECK_Z))
        set_obj_materials(sp, [mat("DIAG_B11_Spark", "#C8F7FF", 0.3, 1.2)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH'), tris(me), [m.name for m in me.materials]))

bpy.context.view_layer.update()
import collections
for v, n_t, n_b, mats in report:
    print(f"B11 {v:7s} total {n_t:5d} tris | corps {n_b:5d} | materiaux {mats}")
for v, nm in (("PC", "B11_BombBody_Base"), ("MOBILE", "B11_BombBody_Base_Mobile")):
    me = bpy.data.objects[nm].data
    bm = bmesh.new(); bm.from_mesh(me)
    print(f"  {v}: repartition materiaux {dict(collections.Counter(q.material_index for q in me.polygons))} | bords ouverts {sum(1 for e in bm.edges if len(e.link_faces)==1)} | aretes>2 faces {sum(1 for e in bm.edges if len(e.link_faces)>2)} | aretes franches {sum(1 for e in bm.edges if not e.smooth)}")
    bm.free()
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B11_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
