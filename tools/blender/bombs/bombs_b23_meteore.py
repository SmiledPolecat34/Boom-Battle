"""
Boom Battle - B23 Meteore : d'apres le SCHEMA de modelisation du proprietaire ("Bombe Terre & Roche").
Schema : sphere de TERRE beige-brun a reseau de FISSURES/CREVASSES (aspect pave) ; FRAGMENTS ROCHEUX brun fonce incrustes et en relief ;
col METALLIQUE gris ; meche en corde ; etincelle jaune-orange. (Cailloux et debris en levitation : hors case, non modelises.)
Construction :
  - PLAQUES = cellules de VORONOI sur la sphere (calculees via l'enveloppe convexe de points sur la sphere : les sommets de Voronoi sont les
    directions des normales des triangles de l'enveloppe) : chaque plaque = polygone reduit (la marge = la CREVASSE), bords en pente, dessus bombe.
  - COEUR sombre (sphere legerement plus petite) visible dans les crevasses.
  - 7 plaques sont des FRAGMENTS ROCHEUX : plus hauts (0,15), dessus facette en pic, brun fonce.
  - COL = BombCollar_Base de B01 (maillage partage), teinte gris-bleu metal.
Pieces exportees : BombBody_Core (Mud) ; BombSkin_PlateA/PlateB (Sand) ; BombSkin_Rocks (Rock) ; BombCollar_Base (Metal) ; meche ; bout.
Decor sur 360 deg (aucun avant). Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B23_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_ROB = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b21_robot_v3_schema.py"
exec(compile(open(_ROB, encoding="utf-8").read().split("def shell_mesh(")[0], "robot_helpers", "exec"))

N23 = {
    "PC":     dict(n_cells=31, core=(20, 11), fuse=(8, 22)),
    "MOBILE": dict(n_cells=22, core=(12, 7),  fuse=(8, 14)),
}
ROCK_TARGETS = [(35, 5), (60, 40), (145, -30), (135, 10), (210, 25), (270, -10), (320, -30)]     # (az, el) des fragments rocheux
CORE_R = 1.44
GAP = 0.93                     # reduction de la plaque dans l'espace des directions : plus petit = crevasse plus large

def voronoi_cells(n, seed=23):
    rng = random.Random(seed)
    golden = math.pi * (3 - math.sqrt(5))
    pts = []
    for i in range(n):
        z = 1 - 2 * (i + 0.5) / n
        r_ = math.sqrt(max(0.0, 1 - z * z))
        a_ = i * golden + rng.uniform(-0.30, 0.30)
        d_ = Vector((r_ * math.cos(a_), r_ * math.sin(a_), z + rng.uniform(-0.05, 0.05))).normalized()
        pts.append(d_)
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    bmesh.ops.convex_hull(bm, input=vs, use_existing_faces=False)
    bm.normal_update()
    cells = []
    for v in bm.verts:
        if not v.link_faces:
            continue
        c = v.co.normalized()
        e1 = c.cross(Vector((0, 0, 1)))
        if e1.length < 1e-4:
            e1 = c.cross(Vector((1, 0, 0)))
        e1.normalize(); e2 = c.cross(e1)
        verts = sorted((f.normal.normalized() for f in v.link_faces), key=lambda n_: math.atan2(n_.dot(e2), n_.dot(e1)))
        cells.append((c, verts))
    bm.free()
    return cells

def plate(bm, c, ring, rock, rng):
    s0, s1 = GAP, (0.72 if rock else 0.86)
    h = (0.12 if rock else rng.uniform(0.025, 0.06))
    peak = (0.06 if rock else 0.02)
    r0, r1 = RS - 0.02, RS + h
    ring0 = [bm.verts.new(((c + (v - c) * s0).normalized()) * r0) for v in ring]
    ring1 = [bm.verts.new(((c + (v - c) * s1).normalized() * (r1 + (rng.uniform(-0.03, 0.03) if rock else 0.0)))) for v in ring]
    apex = bm.verts.new(c * (r1 + peak))
    n = len(ring)
    new = []
    for k in range(n):
        k2 = (k + 1) % n
        new.append(bm.faces.new((ring0[k], ring0[k2], ring1[k2], ring1[k])))
        new.append(bm.faces.new((ring1[k], ring1[k2], apex)))
    bm.normal_update()
    for f in new:
        if f.normal.dot(f.calc_center_median()) < 0:
            f.normal_flip()
    return new

def earth_meshes(v):
    cfg = N23[v]
    rng = random.Random(7)
    cells = voronoi_cells(cfg["n_cells"])
    # fragments rocheux : la cellule la plus proche de chaque cible
    rock_ids = set()
    for az, el in ROCK_TARGETS[: (7 if v == "PC" else 5)]:
        t = direction(az, el)
        rock_ids.add(max(range(len(cells)), key=lambda i: cells[i][0].dot(t)))
    pa, pb, rk = bmesh.new(), bmesh.new(), bmesh.new()
    for i, (c, ring) in enumerate(cells):
        if i in rock_ids:
            plate(rk, c, ring, True, rng)
        else:
            plate(pa if rng.random() < 0.55 else pb, c, ring, False, rng)
    for b in (pa, pb):                                  # terre : plaques bombees (ombrage lisse, sommets non partages entre plaques)
        for f in b.faces:
            f.smooth = True
    for f in rk.faces:                                  # rochers : facettes
        f.smooth = False
    # coeur sombre
    core = bmesh.new()
    seg, rings = cfg["core"]
    bmesh.ops.create_uvsphere(core, u_segments=seg, v_segments=rings, radius=CORE_R)
    bmesh.ops.scale(core, vec=(1, 1, ZSQ), verts=core.verts)
    for f in core.faces:
        f.smooth = True
    me_core = bpy.data.meshes.new(f"B23_Core_{v}"); core.to_mesh(me_core); core.free()
    return me_core, mesh_from(pa, f"B23_PlateA_{v}", True), mesh_from(pb, f"B23_PlateB_{v}", True), mesh_from(rk, f"B23_Rocks_{v}", False), len(cells), len(rock_ids)

# ---------------------------------------------------------------- nettoyage (uniquement B23_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B23_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B23_"):
        bpy.data.collections.remove(c)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

diag = bpy.data.collections["BOMB_BASE_DIAG"]
base_root, mob_root = bpy.data.objects["BombVisualRoot"], bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)
spark_src = bpy.data.objects["DIAG_SparkPreview"]
spark_loc = spark_src.location.copy()
m_rope, m_tip = mat("DIAG_B23_Rope", "#B8884A", 0.7), mat("DIAG_FuseTip", "#2A1C12", 0.8)
m_core = mat("DIAG_B23_Core_Mud", "#6B4A2B", 0.9)
m_pa = mat("DIAG_B23_PlateA_Sand", "#D9AE70", 0.85)
m_pb = mat("DIAG_B23_PlateB_Sand", "#C3925A", 0.85)
m_rock = mat("DIAG_B23_Rocks_Rock", "#5E3A22", 0.8)
m_collar = mat("DIAG_B23_Collar_Metal", "#4C5570", 0.35, metal=0.5)

report = []
for v, src_root, off in (("PC", base_root, Vector((8, 0, 0))), ("MOBILE", mob_root, Vector((8, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B23_Meteore_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B23_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B23", "Meteore", v
    root["default_explosion"], root["spark_color"] = "E23", "#FFC63A"
    body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
    me_core, me_a, me_b, me_r, n_cells, n_rocks = earth_meshes(v)
    me_core.materials.append(m_core); me_a.materials.append(m_pa); me_b.materials.append(m_pb); me_r.materials.append(m_rock)
    body.data = me_core
    body.location = (0, 0, 1.485)                          # +0,03 : les plaques en relief touchent le sol sans le traverser
    set_obj_materials(collar, [m_collar])                      # col = BombCollar_Base de B01, gris metal
    fme = ninja_fuse_mesh(f"B23_Fuse_{v}", *N23[v]["fuse"]); fme.materials.append(m_rope); fme.materials.append(m_tip); fuse.data = fme
    extras = [("BombSkin_PlateA", me_a), ("BombSkin_PlateB", me_b), ("BombSkin_Rocks", me_r)]
    for nm, mesh in extras:
        ob = bpy.data.objects.new("B23_" + nm + ("_Mobile" if v == "MOBILE" else ""), mesh)
        col.objects.link(ob)
        ob.parent = details
        ob.location = body.location
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B23_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off
        set_obj_materials(sp, [mat("DIAG_B23_Spark", "#FFC63A", 0.3, 1.5)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH') + sum(tris(m) for _, m in extras), tris(me_core), tris(me_a) + tris(me_b), tris(me_r), n_cells, n_rocks))

bpy.context.view_layer.update()
for v, n_t, n_c, n_p, n_r, nc, nr in report:
    print(f"B23 {v:7s} total {n_t:5d} tris | coeur {n_c:4d} | plaques {n_p:4d} ({nc - nr}) | rochers {n_r:4d} ({nr})")
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B23_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w_ = o.matrix_world @ vv.co
                xs.append(w_.x); ys.append(w_.y); zs.append(w_.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
