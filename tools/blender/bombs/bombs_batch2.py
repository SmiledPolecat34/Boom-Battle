"""
Boom Battle - Phase 4, lot 2 : B13 Football, B14 Basketball (Famille B : geometrie specifique).
Prerequis : bomb_base.py execute dans CE fichier. Collerette, meche et bout de meche = maillages de B01 (partages).
- B13 : corps = icosaedre tronque (12 pentagones noirs + 20 hexagones blancs), chaque panneau bombe, rainure entre panneaux.
        2 materiaux -> 2 pieces a l'export (BombBody_White / BombBody_Black).
- B14 : corps = sphere de B01 (maillage partage) en orange + pieces de coutures noires en relief (BombBody_Seams).
Pose : 1 case de 4 studs par bombe (B01 de reference a x=0, B13 a x=4, B14 a x=8) ; variantes mobile a y=+8. Idempotent.
"""
import bpy, bmesh, math
from mathutils import Vector

CELL = 4.0
R = 1.5
Z_SQUASH = 0.97
GROOVE = 0.07            # profondeur de la rainure entre panneaux (studs)

# variante : (decoupe d'arete du panneau, anneaux), segments des coutures
VAR = {"PC":     dict(edge_div=2, rings=(1.0, 0.82), seam_segs=48, seam_w=0.13),
       "MOBILE": dict(edge_div=1, rings=(1.0, 0.80), seam_segs=32, seam_w=0.15)}
SEAM_H = 0.03

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

def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)

def orient_outward(bm):
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median()) < 0:
            f.normal_flip()

# ---------------------------------------------------------------- B13 : corps de football
def football_mesh(name, v):
    cfg = VAR[v]
    ico = bmesh.new()
    bmesh.ops.create_icosphere(ico, subdivisions=1, radius=1.0)
    bmesh.ops.bevel(ico, geom=list(ico.verts), offset=33.3333, offset_type='PERCENT', segments=1, affect='VERTICES')
    ico.faces.ensure_lookup_table()
    top = max(ico.faces, key=lambda f: f.calc_center_median().z)
    assert len(top.verts) == 5, "un pentagone doit etre au sommet (sous la collerette)"
    bm = bmesh.new()
    for f in ico.faces:
        pts = [vv.co.copy() * R for vv in f.verts]
        n = len(pts)
        c = sum(pts, Vector()) / n
        black = (n == 5)
        loop = []
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            for k in range(cfg["edge_div"]):
                loop.append(a.lerp(b, k / cfg["edge_div"]))
        rings = []
        for j, s in enumerate(cfg["rings"]):
            rad = R - GROOVE if j == 0 else R
            rings.append([bm.verts.new((c + (p - c) * s).normalized() * rad) for p in loop])
        apex = bm.verts.new(c.normalized() * R)
        m = len(loop)
        for j in range(len(rings) - 1):
            for i in range(m):
                bm.faces.new((rings[j][i], rings[j][(i + 1) % m], rings[j + 1][(i + 1) % m], rings[j + 1][i]))
        for i in range(m):
            bm.faces.new((rings[-1][i], rings[-1][(i + 1) % m], apex))
        # materiau des faces de ce panneau : 0 = blanc, 1 = noir
        for face in bm.faces:
            pass
        mi = 1 if black else 0
        for face in bm.faces[-(m * (len(rings) - 1) + m):]:
            face.material_index = mi
    ico.free()
    bm.normal_update()
    orient_outward(bm)
    bmesh.ops.scale(bm, vec=(1, 1, Z_SQUASH), verts=bm.verts)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me

# ---------------------------------------------------------------- B14 : coutures
def seam_curve(bm, n, d, segs, width):
    """Bande fine sur la sphere : cercle du plan de normale n (unitaire), decale de d (en rayons)."""
    n = Vector(n).normalized()
    ref = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
    u = n.cross(ref).normalized(); w = n.cross(u)
    rr = math.sqrt(max(0.0, 1 - d * d))
    top, bot = [], []
    for i in range(segs):
        th = math.tau * i / segs
        p = (n * d + (u * math.cos(th) + w * math.sin(th)) * rr).normalized()
        t = (-u * math.sin(th) + w * math.cos(th))
        s = p.cross(t).normalized()
        top.append(bm.verts.new(((p * R) + s * width / 2).normalized() * (R + SEAM_H)))
        bot.append(bm.verts.new(((p * R) - s * width / 2).normalized() * (R + SEAM_H)))
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((top[i], bot[i], bot[j], top[j]))

SEAM_TILT = math.radians(35)
SEAMS = [((1, 0, 0), 0.0),                                           # meridien central (vertical de face)
         ((0, 0, 1), 0.0),                                           # equateur
         ((math.cos(SEAM_TILT), math.sin(SEAM_TILT), 0), 0.0),       # meridiens tournes : arcs lateraux "( )" de face
         ((math.cos(SEAM_TILT), -math.sin(SEAM_TILT), 0), 0.0)]

def seams_mesh(name, v):
    cfg = VAR[v]
    bm = bmesh.new()
    for n, d in SEAMS:
        seam_curve(bm, n, d, cfg["seam_segs"], cfg["seam_w"])
    bm.normal_update()
    orient_outward(bm)
    bmesh.ops.scale(bm, vec=(1, 1, Z_SQUASH), verts=bm.verts)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me

# ---------------------------------------------------------------- clonage
def clone_tree(src_root, pfx, offset, col):
    made = {}
    def rec(o, parent):
        n = o.copy()
        n.name = pfx + o.name
        col.objects.link(n)
        n.parent = parent
        made[o.name] = n
        for c in o.children:
            rec(c, n)
    rec(src_root, None)
    made[src_root.name].location = offset
    return made

def part_key(name):
    for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"):
        if name.startswith(k):
            return k
    return None

def find_part(made, key):
    return next(n for k, n in made.items() if part_key(k) == key)

def set_obj_materials(ob, mats):
    for s, m in zip(ob.material_slots, mats):
        s.link = 'OBJECT'
        s.material = m

# ---------------------------------------------------------------- nettoyage du lot
PFX = ("B13_", "B14_")
for o in list(bpy.data.objects):
    if o.name.startswith(PFX):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith(PFX):
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

BOMBS = [
    dict(id="B13", name="Football", folder="B13_Football", x=1, collar="#3A3F4A", spark="#FFB02E", expl="E01"),
    dict(id="B14", name="Basketball", folder="B14_Basketball", x=2, collar="#4A3A2E", spark="#FFB02E", expl="E01"),
]
report = []
for bb in BOMBS:
    pfx = bb["id"] + "_"
    for v, src_root, off in (("PC", base_root, Vector((bb["x"] * CELL, 0, 0))),
                             ("MOBILE", mob_root, Vector((bb["x"] * CELL, 2 * CELL, 0)))):
        col = bpy.data.collections.new(f"{bb['folder']}_{v}")
        bpy.context.scene.collection.children.link(col)
        made = clone_tree(src_root, pfx, off, col)
        root = made[src_root.name]
        root["bomb_id"], root["bomb_name"], root["variant"] = bb["id"], bb["name"], v
        root["default_explosion"] = bb["expl"]
        body, collar, fuse = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"))
        set_obj_materials(collar, [mat(f"DIAG_{bb['id']}_Collar", bb["collar"], 0.45)])
        set_obj_materials(fuse, [m_fuse, m_tip])
        sfx = "_Mobile" if v == "MOBILE" else ""
        if bb["id"] == "B13":
            me = football_mesh(f"B13_Body_{v}", v)
            me.materials.append(mat("DIAG_B13_White", "#F2F2F0", 0.35))
            me.materials.append(mat("DIAG_B13_Black", "#16161B", 0.35))
            body.data = me
        else:
            set_obj_materials(body, [mat("DIAG_B14_Orange", "#E8761E", 0.45)])
            me = seams_mesh(f"B14_Seams_{v}", v)
            me.materials.append(mat("DIAG_B14_Seams", "#1B1612", 0.5))
            sm = bpy.data.objects.new(pfx + "BombBody_Seams" + sfx, me)
            col.objects.link(sm)
            sm.parent = root
            sm.location = body.location
        if v == "PC":
            sp = spark_src.copy()
            sp.name = pfx + "DIAG_SparkPreview"
            diag.objects.link(sp)
            sp.location = spark_loc + off
            set_obj_materials(sp, [mat(f"DIAG_{bb['id']}_Spark", bb["spark"], 0.3, 1.2)])
        meshes = {o.data.name: tris(o.data) for o in made.values() if o.type == 'MESH'}
        extra = [o for o in col.objects if o.type == 'MESH' and o.name.endswith("BombBody_Seams" + sfx)]
        for o in extra:
            meshes[o.data.name] = tris(o.data)
        report.append((bb["id"], v, sum(meshes.values()), len(meshes)))

# grille diagnostic 3 cases x 3
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
    print("%-4s %-7s %5d tris (%d maillages)" % r)
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
