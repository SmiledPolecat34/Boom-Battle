"""
Boom Battle - B06 Glacee v2 : BOULE DE GLACE facettee, d'apres le SCHEMA de modelisation du proprietaire.
(remplace la v1 = icosphere jitteree + 8 eclats pointus ; conservee dans history/)

Schema : grosse boule a GRANDES FACETTES (low-poly, tres ronde, SANS pointes), pale turquoise avec degrades vers un cyan plus profond en bas,
ARETES plus claires ; col court glace/metal bleu clair avec trou sombre ; meche en corde ; etincelle orange. (Flocons et eclats flottants : hors case.)
Construction : meme technique que la gemme B06 v3 : sphere decoupee par ~29 PLANS (pans reellement plans) dont 2 un peu plus grands, table de dessus
pour le col, pied plat ; aretes biseautees claires (PC) ; 4 tons de pans selon la lumiere haut-avant + piece d'aretes ; materiau Roblox Ice.
Pieces exportees (5 materiaux de BombBody_Base) : BombBody_Abyss/Deep/Mid/Light/Edge (Ice) ; BombCollar_Base (Ice, col de la base recolore) ; meche ; bout.
Symetrie ~360 deg (aucun avant) : lisible sous les 4 lacets de la camera. Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B06_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_B16 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b16_shuriken_debout.py"
exec(compile(open(_B16, encoding="utf-8").read().split("# ---------------------------------------------------------------- nettoyage (uniquement B16_*)")[0], "b16_defs", "exec"))

G24 = {
    "PC":     dict(sub=4, bevel=True,  n_rand=29, n_chip=7, fuse=(10, 26)),
    "MOBILE": dict(sub=3, bevel=False, n_rand=21, n_chip=0, fuse=(8, 14)),
}
LIGHT = Vector((0.25, 0.60, 0.55)).normalized()
T_LIGHT, T_MID, T_DEEP = 0.55, 0.05, -0.40
CENTER_Z = 1.45
D_BASE = 1.38
BEVEL_W = 0.020

def direction(az_deg, el_deg):
    a, e = math.radians(az_deg), math.radians(el_deg)
    return Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))

def make_planes(v):
    """Pans irreguliers (tailles tres variees) : 1 table + 1 pied plat + 3 grands pans + pans aleatoires + quelques eclats."""
    cfg = G24[v]
    rng = random.Random(24)
    P = [(Vector((0, 0, 1)), 1.40),            # table du haut : porte la collerette
         (Vector((0, 0, -1)), 1.45)]           # pied plat (sol a z = 0)
    big = [(direction(75, 22), 1.30),           # 2 pans un peu plus grands (le schema montre quelques grandes facettes)
           (direction(200, 30), 1.33)]
    P += big
    golden = math.pi * (3 - math.sqrt(5))
    n = cfg["n_rand"]
    for i in range(n):
        z = 1 - 2 * (i + 0.5) / n
        if abs(z) > 0.93:
            continue
        r_ = math.sqrt(1 - z * z)
        a_ = i * golden + rng.uniform(-0.40, 0.40)
        d_ = Vector((r_ * math.cos(a_), r_ * math.sin(a_), z)).normalized()
        if any(d_.dot(b_[0]) > math.cos(math.radians(26)) for b_ in big):
            continue
        P.append((d_, rng.uniform(1.33, 1.48)))
    for _ in range(cfg["n_chip"]):                                        # petits eclats : coupent un coin
        d_ = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 0.8))).normalized()
        P.append((d_, rng.uniform(1.52, 1.58)))
    return P

def gem_mesh(v):
    cfg = G24[v]
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=cfg["sub"], radius=2.6)
    for n, d in make_planes(v):
        n = n.normalized()
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=n * d, plane_no=n, clear_outer=True, clear_inner=False)
        bnd = [e for e in bm.edges if e.is_boundary]
        if bnd:
            bmesh.ops.holes_fill(bm, edges=bnd, sides=len(bnd))
    bm.normal_update()
    rmax = max(vv.co.length for vv in bm.verts)
    for f in bm.faces:
        t = f.normal.dot(LIGHT)
        f.material_index = 3 if t > T_LIGHT else (2 if t > T_MID else (1 if t > T_DEEP else 0))   # 3 Light, 2 Mid, 1 Deep, 0 Abyss
        f.smooth = False
    nfac = len(bm.faces)
    if cfg["bevel"]:
        res = bmesh.ops.bevel(bm, geom=list(bm.edges), offset=BEVEL_W, offset_type='OFFSET', segments=1, affect='EDGES')
        for f in res["faces"]:
            f.material_index = 4              # arete polie claire
            f.smooth = False
    me = bpy.data.meshes.new(f"B06_Gem_{v}")
    bm.to_mesh(me); bm.free()
    return me, rmax, nfac

# ---------------------------------------------------------------- nettoyage (uniquement B06_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B06_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B06_"):
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
m_abyss = mat("DIAG_B06_Abyss_Ice", "#27A3DE", 0.4)
m_deep = mat("DIAG_B06_Deep_Ice", "#38C4EE", 0.4)
m_mid = mat("DIAG_B06_Mid_Ice", "#6EE0F7", 0.4)
m_light = mat("DIAG_B06_Light_Ice", "#C2F6FF", 0.4)
m_edge = mat("DIAG_B06_Edge_Ice", "#E8FCFF", 0.35)
m_collar = mat("DIAG_B06_Collar_Ice", "#A9E4FF", 0.3)

report = []
for v, src_root, off in (("PC", base_root, Vector((4, 0, 0))), ("MOBILE", mob_root, Vector((4, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B06_Glacee_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B06_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B06", "Glacee", v
    root["default_explosion"], root["spark_color"] = "E06", "#FFB020"
    body, collar, fuse = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"))
    me, rmax, nfac = gem_mesh(v)
    for m_ in (m_abyss, m_deep, m_mid, m_light, m_edge):
        me.materials.append(m_)
    body.data = me
    body.location = (0, 0, CENTER_Z)
    set_obj_materials(collar, [m_collar])                      # collerette de la base (grande), recoloree
    fme = ninja_fuse_mesh(f"B06_Fuse_{v}", *G24[v]["fuse"]); fme.materials.append(m_fuse); fme.materials.append(m_tip); fuse.data = fme
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B06_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off
        set_obj_materials(sp, [mat("DIAG_B06_Spark", "#FFB020", 0.3, 1.5)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH'), tris(me), rmax, nfac))

bpy.context.view_layer.update()
import collections
for v, n_t, n_b, rmax, nfac in report:
    print(f"B06 {v:7s} total {n_t:5d} tris | corps {n_b:5d} | pans {nfac} | rayon max {rmax:.2f} (sphere de depart 2.6 : doit etre < 2.6)")
for v, nm in (("PC", "B06_BombBody_Base"), ("MOBILE", "B06_BombBody_Base_Mobile")):
    me = bpy.data.objects[nm].data
    bm = bmesh.new(); bm.from_mesh(me)
    print(f"  {v}: repartition {dict(sorted(collections.Counter(q.material_index for q in me.polygons).items()))} | bords ouverts {sum(1 for e in bm.edges if len(e.link_faces)==1)} | aretes>2 faces {sum(1 for e in bm.edges if len(e.link_faces)>2)}")
    bm.free()
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B06_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
