"""
Boom Battle - Phase 4, lot 5 : B11 Crane, B12 Citrouille (formes 3D propres, en volume).
Prerequis : bomb_base.py execute dans CE fichier. Definitions communes (mat, clone_tree, virole fine, meche lisse) reprises du script B16.
Camera du jeu : tangage 55 deg, cote +Z Roblox (= +Y Blender), lacet par pas de 90 deg. Ces deux bombes ont un AVANT (+Y Blender) :
a l'integration, les faire pivoter en Y vers la camera (rotation cosmetique, sans effet gameplay).
- B11 : crane = cranium (ellipsoide) + machoire (ellipsoide, pied plat) fusionnes ; orbites, nez, dents = motifs sombres PROJETES sur la
        surface (projection le long de Y). Pieces : BombBody_Base (os), BombSkin_Features (sombre).
- B12 : citrouille = sphere a 10 cotes + fossette haute ; visage taille (yeux, nez, bouche) en pieces jaunes lumineuses (Neon) conformes a
        la surface. Pieces : BombBody_Base (orange), BombSkin_Face (Neon). La tige est la virole fine brune.
Idempotent (ne touche qu'aux objets B11_*, B12_*).
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

_B16 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b16_shuriken_debout.py"
exec(compile(open(_B16, encoding="utf-8").read().split("# ---------------------------------------------------------------- nettoyage (uniquement B16_*)")[0], "b16_defs", "exec"))

VAR5 = {
    "PC":     dict(cr=(24, 14), jaw=(20, 10), pump=(32, 16), eye_cuts=1, face_cuts=2, ring_pts=16),
    "MOBILE": dict(cr=(16, 9),  jaw=(14, 7),  pump=(20, 10), eye_cuts=0, face_cuts=1, ring_pts=10),
}

# ---------------------------------------------------------------- outils : motifs 2D triangules puis projetes
def tri_sub(poly, cuts):
    """Polygone 2D (liste de (x, y), peut etre concave) -> triangulation (+ subdivision) : (sommets 2D, faces d'indices)."""
    t = bmesh.new()
    vs = [t.verts.new((p[0], p[1], 0.0)) for p in poly]
    f = t.faces.new(vs)
    bmesh.ops.triangulate(t, faces=[f])
    if cuts > 0:
        bmesh.ops.subdivide_edges(t, edges=list(t.edges), cuts=cuts, use_grid_fill=True)
    t.verts.index_update()
    V = [(v.co.x, v.co.y) for v in t.verts]
    Fs = [[v.index for v in f.verts] for f in t.faces]
    t.free()
    return V, Fs

def add_projected(bm, poly, cuts, to3d):
    V, Fs = tri_sub(poly, cuts)
    vv = [bm.verts.new(to3d(x, y)) for x, y in V]
    for idx in Fs:
        try:
            bm.faces.new([vv[i] for i in idx])
        except ValueError:
            pass

def ellipse(cx, cz, rx, rz, n, tilt_deg=0.0):
    t0 = math.radians(tilt_deg)
    pts = []
    for k in range(n):
        a = math.tau * k / n
        x, y = rx * math.cos(a), rz * math.sin(a)
        pts.append((cx + x * math.cos(t0) - y * math.sin(t0), cz + x * math.sin(t0) + y * math.cos(t0)))
    return pts

def rect(cx, cz, w, h):
    return [(cx - w / 2, cz - h / 2), (cx + w / 2, cz - h / 2), (cx + w / 2, cz + h / 2), (cx - w / 2, cz + h / 2)]

def orient_from(bm, origin):
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median() - origin) < 0:
            f.normal_flip()

# ---------------------------------------------------------------- B11 : crane
CR_C, CR_R = Vector((0.0, 0.0, 1.75)), (1.30, 1.22, 1.05)      # cranium : centre, rayons (x, y, z)
JW_C, JW_R = Vector((0.0, 0.38, 0.56)), (0.98, 0.85, 0.62)     # machoire (plus large et plus haute : se raccorde au cranium)
Z_FLOOR = 0.0

def ellipsoid_into(bm, c, r, seg, rings, zmin=None):
    vb = set(bm.verts)
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    for v in bm.verts:
        if v in vb:
            continue
        v.co = Vector((c.x + v.co.x * r[0], c.y + v.co.y * r[1], c.z + v.co.z * r[2]))
        if zmin is not None and v.co.z < zmin:
            v.co.z = zmin                                  # pied plat de la machoire

def on_ellipsoid(c, r, off):
    """Projection le long de -Y d'un point (x, z) sur la face avant (+Y) d'un ellipsoide, decalee de 'off' selon la normale."""
    def f(x, z):
        q = 1 - ((x - c.x) / r[0]) ** 2 - ((z - c.z) / r[2]) ** 2
        y = c.y + r[1] * math.sqrt(max(q, 0.0))
        p = Vector((x, y, z))
        n = Vector(((x - c.x) / r[0] ** 2, (y - c.y) / r[1] ** 2, (z - c.z) / r[2] ** 2))
        return p + (n.normalized() * off if n.length > 1e-9 else Vector((0, 0, 0)))
    return f

def skull_meshes(v):
    cfg = VAR5[v]
    bone = bmesh.new()
    ellipsoid_into(bone, CR_C, CR_R, *cfg["cr"])
    ellipsoid_into(bone, JW_C, JW_R, *cfg["jaw"], zmin=Z_FLOOR)
    orient_from(bone, Vector((0, 0.2, 1.2)))
    for f in bone.faces:
        f.smooth = True
    bme = bpy.data.meshes.new(f"B11_Bone_{v}")
    bone.to_mesh(bme); bone.free()

    fb = bmesh.new()
    cr, jw = on_ellipsoid(CR_C, CR_R, 0.035), on_ellipsoid(JW_C, JW_R, 0.035)
    n = cfg["ring_pts"]
    add_projected(fb, ellipse(0.50, 1.80, 0.42, 0.38, n, 12), cfg["eye_cuts"], cr)      # orbites
    add_projected(fb, ellipse(-0.50, 1.80, 0.42, 0.38, n, -12), cfg["eye_cuts"], cr)
    add_projected(fb, [(-0.20, 1.18), (0.20, 1.18), (0.0, 1.55)], cfg["eye_cuts"], cr)   # nez
    add_projected(fb, rect(0.0, 1.00, 1.15, 0.06), 0, jw)                               # ligne des dents
    for ux in (-0.40, -0.20, 0.0, 0.20, 0.40):
        add_projected(fb, rect(ux, 0.78, 0.055, 0.40), 0, jw)                           # separations des dents
    orient_from(fb, Vector((0, 0.2, 1.2)))
    for f in fb.faces:
        f.smooth = True
    fme = bpy.data.meshes.new(f"B11_Features_{v}")
    fb.to_mesh(fme); fb.free()
    return bme, fme

# ---------------------------------------------------------------- B12 : citrouille
PUMP = dict(Rxy=1.50, Rz=1.25, ribs=10, rib_amp=0.075, dimple=0.30)

def pumpkin_point(az, colat, off=0.0):
    """Point de la surface (repere centre sur le corps) ; colat = 0 au pole haut. Cotes nulles aux poles, vallee a l'azimut 90 deg (face)."""
    s, c = math.sin(colat), math.cos(colat)
    rib = 1 + PUMP["rib_amp"] * math.cos(PUMP["ribs"] * az) * s ** 1.2
    z = PUMP["Rz"] * c - PUMP["dimple"] * math.exp(-(colat / 0.42) ** 2)
    p = Vector((PUMP["Rxy"] * rib * s * math.cos(az), PUMP["Rxy"] * rib * s * math.sin(az), z))
    return p + p.normalized() * off if off else p

def pumpkin_body(v):
    seg, rings = VAR5[v]["pump"]
    bm = bmesh.new()
    top = bm.verts.new(pumpkin_point(0.0, 0.0))
    bot = bm.verts.new(pumpkin_point(0.0, math.pi))
    rv = []
    for i in range(1, rings):
        colat = math.pi * i / rings
        rv.append([bm.verts.new(pumpkin_point(math.tau * k / seg, colat)) for k in range(seg)])
    for k in range(seg):
        k2 = (k + 1) % seg
        bm.faces.new((top, rv[0][k2], rv[0][k]))
        bm.faces.new((bot, rv[-1][k], rv[-1][k2]))
        for i in range(len(rv) - 1):
            bm.faces.new((rv[i][k], rv[i][k2], rv[i + 1][k2], rv[i + 1][k]))
    orient_from(bm, Vector((0, 0, 0)))
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(f"B12_Pumpkin_{v}")
    bm.to_mesh(me); bm.free()
    return me

def pumpkin_face(v):
    cfg = VAR5[v]
    fb = bmesh.new()
    zf = 0.38                                                  # hauteur du centre du visage (plus haut : mieux vu depuis la camera a 55 deg)
    def to3d(u, w):                                            # (u, w) en studs : u vers la DROITE vue de face (= -X), w vers le haut
        z = zf + w
        colat = math.acos(max(-0.999, min(0.999, z / PUMP["Rz"])))
        return pumpkin_point(math.pi / 2 + u / PUMP["Rxy"], colat, 0.05)
    c = cfg["face_cuts"]
    add_projected(fb, [(-0.80, 0.20), (-0.30, 0.20), (-0.55, 0.68)], c, to3d)            # oeil gauche (triangle)
    add_projected(fb, [(0.30, 0.20), (0.80, 0.20), (0.55, 0.68)], c, to3d)               # oeil droit
    add_projected(fb, [(-0.14, -0.10), (0.14, -0.10), (0.0, 0.14)], c, to3d)             # nez
    add_projected(fb, [(-0.95, -0.15), (-0.62, -0.30), (-0.46, -0.15), (-0.22, -0.35), (0.0, -0.20), (0.22, -0.35), (0.46, -0.15),
                       (0.62, -0.30), (0.95, -0.15), (0.74, -0.52), (0.34, -0.68), (-0.34, -0.68), (-0.74, -0.52)], c, to3d)        # bouche dentee
    orient_from(fb, Vector((0, 0, 0)))
    for f in fb.faces:
        f.smooth = True
    me = bpy.data.meshes.new(f"B12_Face_{v}")
    fb.to_mesh(me); fb.free()
    return me

# ---------------------------------------------------------------- nettoyage du lot
for o in list(bpy.data.objects):
    if o.name.startswith(("B11_", "B12_")):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith(("B11_", "B12_")):
        bpy.data.collections.remove(c)
for n in ("DIAG_GridRow", "DIAG_Grid3x3"):
    o = bpy.data.objects.get(n)
    if o:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me.users == 0:
            bpy.data.meshes.remove(me)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

diag = bpy.data.collections["BOMB_BASE_DIAG"]
base_root, mob_root = bpy.data.objects["BombVisualRoot"], bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)
spark_src = bpy.data.objects["DIAG_SparkPreview"]
spark_loc = spark_src.location.copy()
m_fuse, m_tip = mat("DIAG_Fuse", "#C8742E", 0.7), mat("DIAG_FuseTip", "#2A1C12", 0.8)

BOMBS5 = [dict(id="B11", name="Crane", folder="B11_Crane", x=1, spark="#C8F7FF", expl="E24"),
          dict(id="B12", name="Citrouille", folder="B12_Citrouille", x=2, spark="#FF9A2E", expl="E01")]
report = []
for bb in BOMBS5:
    pfx = bb["id"] + "_"
    for v, src_root, off in (("PC", base_root, Vector((bb["x"] * CELL, 0, 0))), ("MOBILE", mob_root, Vector((bb["x"] * CELL, 2 * CELL, 0)))):
        col = bpy.data.collections.new(f"{bb['folder']}_{v}")
        bpy.context.scene.collection.children.link(col)
        made = clone_tree(src_root, pfx, off, col)
        root = made[src_root.name]
        root["bomb_id"], root["bomb_name"], root["variant"] = bb["id"], bb["name"], v
        root["default_explosion"], root["spark_color"] = bb["expl"], bb["spark"]
        root["orientation"] = "avant = +Z Roblox ; pivoter en Y pour faire face a la camera"
        body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
        neck = find_part(made, "BombNeck")
        sfx = "_Mobile" if v == "MOBILE" else ""
        fme = ninja_fuse_mesh(f"{pfx}Fuse_{v}", *VARS[v]["fuse"])
        fme.materials.append(m_fuse); fme.materials.append(m_tip)
        fuse.data = fme
        if bb["id"] == "B11":
            bme, feat = skull_meshes(v)
            bme.materials.append(mat("DIAG_B11_Bone", "#EDE6D3", 0.45)); feat.materials.append(mat("DIAG_B11_Features", "#1E1B22", 0.6))
            body.data = bme; body.location = (0, 0, 0)
            extras = [("BombSkin_Features", feat, (0, 0, 0))]
            neck_z = CR_C.z + CR_R[2] - 0.10
            cme = ninja_collar_mesh(f"{pfx}Collar_{v}", VARS[v]["collar_seg"]); cme.materials.append(mat("DIAG_B11_Collar", "#2A2A2E", 0.45))
        else:
            bme = pumpkin_body(v); bme.materials.append(mat("DIAG_B12_Body", "#F08A1C", 0.45))
            face = pumpkin_face(v); face.materials.append(mat("DIAG_B12_Face_Neon", "#FFD34A", 0.3, emit=2.0))
            body.data = bme; body.location = (0, 0, PUMP["Rz"])
            extras = [("BombSkin_Face", face, (0, 0, PUMP["Rz"]))]
            neck_z = PUMP["Rz"] + pumpkin_point(0, 0).z - 0.05
            cme = ninja_collar_mesh(f"{pfx}Collar_{v}", VARS[v]["collar_seg"]); cme.transform(Matrix.Scale(1.15, 4)); cme.materials.append(mat("DIAG_B12_Collar", "#5B3A1C", 0.6))
        collar.data = cme
        neck.location.z = neck_z
        for nm, mesh, loc in extras:
            ob = bpy.data.objects.new(pfx + nm + sfx, mesh)
            col.objects.link(ob)
            ob.parent = details
            ob.location = loc
        if v == "PC":
            sp = spark_src.copy()
            sp.name = pfx + "DIAG_SparkPreview"
            diag.objects.link(sp)
            sp.location = spark_loc + off + Vector((0, 0, neck_z - BASE_NECK_Z))
            set_obj_materials(sp, [mat(f"DIAG_{bb['id']}_Spark", bb["spark"], 0.3, 1.2)])
        n_t = sum(tris(o.data) for o in made.values() if o.type == 'MESH') + sum(tris(m) for _, m, _ in extras)
        report.append((bb["id"], v, n_t))

bm = bmesh.new()
ma, mb = mat("DIAG_Cell_A", "#8c939e", 0.9), mat("DIAG_Cell_B", "#7a818c", 0.9)
for gx in range(0, 3):
    for gy in range(-1, 2):
        x0, y0 = gx * CELL - CELL / 2, gy * CELL - CELL / 2
        vv = [bm.verts.new((x0 + dx, y0 + dy, -0.002)) for dx, dy in ((0, 0), (CELL, 0), (CELL, CELL), (0, CELL))]
        bm.faces.new(vv).material_index = (gx + gy) % 2
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("DIAG_GridRow")
bm.to_mesh(me); bm.free()
me.materials.append(ma); me.materials.append(mb)
diag.objects.link(bpy.data.objects.new("DIAG_GridRow", me))

bpy.context.view_layer.update()
for r in report:
    print("%-4s %-7s %5d tris" % r)
for bb in BOMBS5:
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith(bb["id"] + "_") and not o.name.endswith("_Mobile") and "DIAG" not in o.name:
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {bb['id']} PC : largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
