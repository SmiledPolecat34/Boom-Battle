"""
Boom Battle - B08 Electrique : d'apres le SCHEMA de modelisation du proprietaire ("Bombe Electrique").
Schema : sphere violet-noir tres brillante ; FISSURES d'energie bleu vif en ECLAIRS (zigzags ramifies, emissifs), surtout a l'avant ;
col METALLIQUE gris ; meche en corde ; etincelle de decharge bleu-blanc. (Aura violette, decharges et eclairs autour : hors case, non modelises.)
Construction :
  - CORPS : sphere de la base (maillage partage avec B01), teinte violet-noir.
  - 12 FISSURES = rubans en zigzag poses sur la sphere (chemins en azimut/elevation, interpoles sur grand cercle), largeur variable (pointes fines),
    en 2 couches : HALO bleu electrique (Neon) + COEUR blanc-cyan (Neon), plus etroit et plus haut. Branches comprises ; fissures aussi au dos.
  - COL = BombCollar_Base de B01 (maillage partage), gris metal.
Pieces exportees : BombBody_Base (violet-noir) ; BombSkin_CrackGlow (Neon bleu) ; BombSkin_CrackCore (Neon blanc-cyan) ; BombCollar_Base (Metal) ; meche ; bout.
Les fissures sont reparties a 360 deg (plus denses a l'avant = +Y). Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B08_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_ROB = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b21_robot_v3_schema.py"
exec(compile(open(_ROB, encoding="utf-8").read().split("def shell_mesh(")[0], "robot_helpers", "exec"))

N08 = {
    "PC":     dict(n_paths=13, subdiv=2, collar_seg=20, fuse=(8, 22)),
    "MOBILE": dict(n_paths=8,  subdiv=1, collar_seg=12, fuse=(8, 14)),
}
# (points (azimut, elevation) en degres, largeur max) ; avant = azimut 90 ; vu de face, la gauche = azimut < 90
CRACKS = [
    ([(38, -44), (50, -34), (58, -46), (74, -34), (86, -48), (102, -36), (114, -47), (130, -34), (140, -44)], 0.15),   # eclair principal, bas du devant
    ([(74, -34), (80, -20), (76, -8), (86, 2), (82, 14)], 0.11),                                                       # branche vers le haut
    ([(138, -12), (150, -2), (144, 10), (156, 22), (150, 34)], 0.13),                                                  # amas de droite
    ([(114, -47), (120, -58), (112, -68)], 0.09),                                                                      # branche vers le bas
    ([(54, 38), (64, 30), (58, 20), (68, 12)], 0.10),                                                                  # haut gauche
    ([(150, -2), (164, -8), (172, 2)], 0.09),
    ([(130, -34), (138, -24), (136, -14)], 0.10),                                                                      # relie l'eclair principal a l'amas de droite
    ([(196, -30), (208, -18), (204, -6), (218, 2)], 0.12),                                                             # dos
    ([(232, -38), (244, -26), (238, -14), (252, -4), (248, 8)], 0.13),
    ([(284, 20), (296, 10), (290, -2), (302, -12)], 0.12),
    ([(318, -30), (328, -18), (322, -6), (336, 6)], 0.12),
    ([(10, -14), (20, -4), (14, 8), (24, 18)], 0.10),
    ([(176, 30), (186, 20), (180, 10)], 0.09),
]

def densify(pts, k):
    out = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        for s in range(k):
            out.append((a + (b - a) * (s / k)).normalized())
    out.append(pts[-1])
    return out

def ribbon(bm, pts, wmax, h, wmin=0.03):
    n = len(pts)
    left, right = [], []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        t = (b - a)
        t = (t - p * t.dot(p)).normalized()
        l = p.cross(t).normalized()
        u = i / (n - 1)
        w = wmin + (wmax - wmin) * (math.sin(math.pi * u) ** 0.5)
        left.append(bm.verts.new((p * RS + l * (w / 2)).normalized() * (RS + h)))
        right.append(bm.verts.new((p * RS - l * (w / 2)).normalized() * (RS + h)))
    new = []
    for i in range(n - 1):
        try:
            new.append(bm.faces.new((left[i], left[i + 1], right[i + 1], right[i])))
        except ValueError:
            pass
    bm.normal_update()
    for f in new:
        if f.normal.dot(f.calc_center_median()) < 0:
            f.normal_flip()

def cracks_meshes(v):
    cfg = N08[v]
    rng = random.Random(8)
    glow, core = bmesh.new(), bmesh.new()
    for pts_deg, wmax in CRACKS[: cfg["n_paths"]]:
        pts = [direction(az + rng.uniform(-1.5, 1.5), el + rng.uniform(-1.5, 1.5)) for az, el in pts_deg]
        pts = densify(pts, cfg["subdiv"])
        ribbon(glow, pts, wmax * 2.5, 0.025, wmin=0.07)
        ribbon(core, pts, wmax * 2.5 * 0.28, 0.040, wmin=0.022)
    for b in (glow, core):
        for f in b.faces:
            f.smooth = True
    return mesh_from(glow, f"B08_Glow_{v}", True), mesh_from(core, f"B08_Core_{v}", True)

# ---------------------------------------------------------------- nettoyage (uniquement B08_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B08_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B08_"):
        bpy.data.collections.remove(c)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

diag = bpy.data.collections["BOMB_BASE_DIAG"]
base_root, mob_root = bpy.data.objects["BombVisualRoot"], bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)
spark_src = bpy.data.objects["DIAG_SparkPreview"]
spark_loc = spark_src.location.copy()
m_rope, m_tip = mat("DIAG_B08_Rope", "#C98F4A", 0.7), mat("DIAG_FuseTip", "#2A1C12", 0.8)
m_body = mat("DIAG_B08_Body", "#241A4D", 0.18)
m_glow = mat("DIAG_B08_CrackGlow_Neon", "#2A6BFF", 0.3, emit=4.0)
m_core = mat("DIAG_B08_CrackCore_Neon", "#BFEFFF", 0.3, emit=5.0)
m_collar = mat("DIAG_B08_Collar_Metal", "#7D8398", 0.35, metal=0.6)

report = []
for v, src_root, off in (("PC", base_root, Vector((8, 0, 0))), ("MOBILE", mob_root, Vector((8, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B08_Electrique_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B08_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B08", "Electrique", v
    root["default_explosion"], root["spark_color"] = "E08", "#9FE8FF"
    body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
    set_obj_materials(body, [m_body])                          # sphere de la base (maillage partage), violet-noir
    set_obj_materials(collar, [m_collar])                      # col = BombCollar_Base de B01, gris metal
    fme = ninja_fuse_mesh(f"B08_Fuse_{v}", *N08[v]["fuse"]); fme.materials.append(m_rope); fme.materials.append(m_tip); fuse.data = fme
    me_g, me_c = cracks_meshes(v)
    me_g.materials.append(m_glow); me_c.materials.append(m_core)
    extras = [("BombSkin_CrackGlow", me_g), ("BombSkin_CrackCore", me_c)]
    for nm, mesh in extras:
        ob = bpy.data.objects.new("B08_" + nm + ("_Mobile" if v == "MOBILE" else ""), mesh)
        col.objects.link(ob)
        ob.parent = details
        ob.location = body.location
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B08_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off
        set_obj_materials(sp, [mat("DIAG_B08_Spark", "#9FE8FF", 0.3, 3.0)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH') + sum(tris(m) for _, m in extras), tris(me_g), tris(me_c)))

bpy.context.view_layer.update()
for v, n_t, n_g, n_c in report:
    print(f"B08 {v:7s} total {n_t:5d} tris | halo {n_g:4d} | coeur {n_c:4d}")
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B08_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w_ = o.matrix_world @ vv.co
                xs.append(w_.x); ys.append(w_.y); zs.append(w_.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
