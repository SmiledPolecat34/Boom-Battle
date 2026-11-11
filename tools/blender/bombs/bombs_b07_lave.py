"""
Boom Battle - B07 Lave : d'apres le SCHEMA de modelisation du proprietaire ("Bombe de Lave & Feu").
Schema : sphere de ROCHE VOLCANIQUE noire en PLAQUES bombees (motif de ballon) separees par des FISSURES de LAVE incandescente orange-jaune
(emissives) ; col en METAL NOIRCI ; meche en corde ; etincelle de magma/feu. (Flammeches, aura de chaleur, braises : hors case, non modelises.)
Construction (meme pavage de Voronoi que B23) :
  - ~26 PLAQUES en basalte noir, bombees, relief irregulier ; marge entre plaques = la fissure.
  - COEUR Neon jaune-orange (lave) visible dans les fissures.
  - Pentes des plaques (bords) en Neon orange-rouge = bord chauffe : degrade jaune (centre de la fissure) -> orange -> roche noire.
  - COL = BombCollar_Base de B01 (maillage partage), noirci.
Pieces exportees : BombBody_Base (coeur lave, Neon) ; BombSkin_Plates (Basalt) ; BombSkin_PlateEdge (Neon) ; BombCollar_Base (Metal) ; meche ; bout.
Decor sur 360 deg (aucun avant). Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B07_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_B23 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b23_meteore.py"
exec(compile(open(_B23, encoding="utf-8").read().split("def plate(")[0], "b23_helpers", "exec"))     # helpers du Robot + voronoi_cells

N07 = {
    "PC":     dict(n_cells=26, core=(20, 11), fuse=(8, 22)),
    "MOBILE": dict(n_cells=18, core=(12, 7),  fuse=(8, 14)),
}
GAP7 = 0.89                    # largeur des fissures de lave (plus petit = plus large)
LAVA_CORE_R = 1.43
BODY_Z = 1.475

def plate7(bm, c, ring, rng):
    r0, r1 = RS - 0.03, RS + rng.uniform(0.04, 0.07)
    ring0 = [bm.verts.new(((c + (v - c) * GAP7).normalized()) * r0) for v in ring]
    ring1 = [bm.verts.new(((c + (v - c) * 0.84).normalized()) * (r1 + rng.uniform(-0.015, 0.015))) for v in ring]
    apex = bm.verts.new(c * (r1 + 0.02 + rng.uniform(0.0, 0.015)))
    n = len(ring)
    sides, tops = [], []
    for k in range(n):
        k2 = (k + 1) % n
        sides.append(bm.faces.new((ring0[k], ring0[k2], ring1[k2], ring1[k])))
        tops.append(bm.faces.new((ring1[k], ring1[k2], apex)))
    bm.normal_update()
    for f in sides + tops:
        if f.normal.dot(f.calc_center_median()) < 0:
            f.normal_flip()
    for f in tops:
        f.material_index = 0                       # roche
    for f in sides:
        f.material_index = 1                       # bord chauffe

def lava_meshes(v):
    cfg = N07[v]
    rng = random.Random(77)
    cells = voronoi_cells(cfg["n_cells"], seed=7)
    pl = bmesh.new()
    for c, ring in cells:
        plate7(pl, c, ring, rng)
    for f in pl.faces:
        f.smooth = True
    core = bmesh.new()
    seg, rings = cfg["core"]
    bmesh.ops.create_uvsphere(core, u_segments=seg, v_segments=rings, radius=LAVA_CORE_R)
    bmesh.ops.scale(core, vec=(1, 1, ZSQ), verts=core.verts)
    for f in core.faces:
        f.smooth = True
    me_core = bpy.data.meshes.new(f"B07_Core_{v}"); core.to_mesh(me_core); core.free()
    return me_core, mesh_from(pl, f"B07_Plates_{v}", True), len(cells)

# ---------------------------------------------------------------- nettoyage (uniquement B07_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B07_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B07_"):
        bpy.data.collections.remove(c)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

diag = bpy.data.collections["BOMB_BASE_DIAG"]
base_root, mob_root = bpy.data.objects["BombVisualRoot"], bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)
spark_src = bpy.data.objects["DIAG_SparkPreview"]
spark_loc = spark_src.location.copy()
m_rope, m_tip = mat("DIAG_B07_Rope", "#B8884A", 0.7), mat("DIAG_FuseTip", "#2A1C12", 0.8)
m_core = mat("DIAG_B07_Core_Neon", "#FF9A1F", 0.3, emit=4.0)
m_rock = mat("DIAG_B07_Plates_Basalt", "#2A2523", 0.75)
m_edge = mat("DIAG_B07_PlateEdge_Neon", "#FF4A12", 0.3, emit=3.5)
m_collar = mat("DIAG_B07_Collar_Metal", "#2F2F36", 0.4, metal=0.5)

report = []
for v, src_root, off in (("PC", base_root, Vector((4, 0, 0))), ("MOBILE", mob_root, Vector((4, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B07_Lave_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B07_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B07", "Lave", v
    root["default_explosion"], root["spark_color"] = "E07", "#FF8A1A"
    body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
    me_core, me_pl, n_cells = lava_meshes(v)
    me_core.materials.append(m_core)
    me_pl.materials.append(m_rock); me_pl.materials.append(m_edge)
    body.data = me_core
    body.location = (0, 0, BODY_Z)
    set_obj_materials(collar, [m_collar])                      # col = BombCollar_Base de B01, noirci
    fme = ninja_fuse_mesh(f"B07_Fuse_{v}", *N07[v]["fuse"]); fme.materials.append(m_rope); fme.materials.append(m_tip); fuse.data = fme
    ob = bpy.data.objects.new("B07_BombSkin_Plates" + ("_Mobile" if v == "MOBILE" else ""), me_pl)
    col.objects.link(ob)
    ob.parent = details
    ob.location = body.location
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B07_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off
        set_obj_materials(sp, [mat("DIAG_B07_Spark", "#FF8A1A", 0.3, 2.5)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH') + tris(me_pl), tris(me_core), tris(me_pl), n_cells))

bpy.context.view_layer.update()
for v, n_t, n_c, n_p, nc in report:
    print(f"B07 {v:7s} total {n_t:5d} tris | coeur {n_c:4d} | plaques {n_p:4d} ({nc} plaques)")
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B07_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w_ = o.matrix_world @ vv.co
                xs.append(w_.x); ys.append(w_.y); zs.append(w_.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
