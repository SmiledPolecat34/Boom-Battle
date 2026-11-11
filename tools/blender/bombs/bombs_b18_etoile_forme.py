"""
Boom Battle - B18 Etoiles v2 : la BOMBE EST UNE ETOILE 2.5D, DEBOUT, LISSEE (meme approche que le Coeur et le Ninja).
(remplace la v1 = sphere bleue + 8 etoiles dorees en relief, conservee dans history/)

Forme : etoile a 5 branches (pointe en haut), contour arrondi (coins adoucis, "chubby" cartoon), 3,1 studs de large,
plan VERTICAL face a +Y Blender (= +Z Roblox), debout sur DEUX PIEDS PLATS (les deux pointes du bas coupees a l'horizontale).
Relief 2.5D gonfle (dome en 7 anneaux) : bord et flancs BLEUS, ETOILE INTERIEURE DOREE (metal) a bord net.
Collerette fine + meche lisse = celles du Ninja/Coeur (definitions du script B16), posees sur la pointe du haut.
Pieces exportees : BombBody_Star (bleu), BombBody_Inner (or, Metal), collerette, meche, bout.
Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B18_*).
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

_B16 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b16_shuriken_debout.py"
exec(compile(open(_B16, encoding="utf-8").read().split("# ---------------------------------------------------------------- nettoyage (uniquement B16_*)")[0], "b16_defs", "exec"))

SW, FOOT_H, INNER_RATIO = 3.1, 0.30, 0.40          # largeur de l'etoile, hauteur des pieds plats, rayon creux / rayon pointe
NECK_SINK = 0.12                                   # la virole s'enfonce un peu dans la pointe du haut
COLLAR_SCALE = 0.70                                # virole reduite pour la pointe du haut
SVARS = {
    "PC": dict(smooth=2, round=0.10, rings=[(1.0, 0.15), (0.985, 0.25), (0.955, 0.34), (0.905, 0.42), (0.83, 0.49), (0.73, 0.55), (0.62, 0.59)],
               inner_ring=6, apex=0.62, collar_seg=20, fuse=(10, 26)),
    "MOBILE": dict(smooth=1, round=0.16, rings=[(1.0, 0.15), (0.95, 0.34), (0.83, 0.50), (0.62, 0.59)],
                   inner_ring=3, apex=0.62, collar_seg=12, fuse=(8, 14)),
}

def star5_outline(iters, a):
    """Etoile a 5 branches (pointe 0 en haut, sens trigo), coins adoucis PAR DECOUPE DE COINS FAIBLE (Chaikin, a = 10 %) puis remise a la largeur SW (un arrondi fort fait disparaitre les branches)."""
    pts = []
    for k in range(10):
        r = 1.0 if k % 2 == 0 else INNER_RATIO
        ang = math.pi / 2 + k * math.pi / 5                 # (ne pas reutiliser "a" : c'est le parametre d'arrondi)
        pts.append(Vector((r * math.cos(ang), r * math.sin(ang))))
    for _ in range(iters):
        new = []
        for i in range(len(pts)):
            p, q = pts[i], pts[(i + 1) % len(pts)]
            new.append(p * (1 - a) + q * a); new.append(p * a + q * (1 - a))
        pts = new
    xs = [p.x for p in pts]
    sc = SW / (max(xs) - min(xs))
    return [p * sc for p in pts]

def star_geometry(name, v):
    cfg = SVARS[v]
    poly = star5_outline(cfg["smooth"], cfg["round"])
    ymax = max(p.y for p in poly)
    zcut = min(p.y for p in poly) + FOOT_H
    poly = clip_below(poly, zcut)
    zc = -zcut                                         # hauteur du centre : pieds plats a z = 0
    n = len(poly)
    bm = bmesh.new()
    ring = lambda sc_, y: [bm.verts.new((p.x * sc_, y, p.y * sc_)) for p in poly]
    rf = [ring(s_, y) for s_, y in cfg["rings"]]
    rb = [ring(s_, -y) for s_, y in cfg["rings"]]
    af, ab = bm.verts.new((0, cfg["apex"], 0)), bm.verts.new((0, -cfg["apex"], 0))
    wall, front, back = [], [], []
    def F(vs, mi, bucket):
        f = bm.faces.new(vs); f.material_index = mi; bucket.append(f)
    for i in range(n):
        j = (i + 1) % n
        F((rb[0][i], rb[0][j], rf[0][j], rf[0][i]), 0, wall)
        for g in range(len(rf) - 1):
            mi = 0 if g < cfg["inner_ring"] else 1       # au-dela de l'anneau "inner_ring" : etoile interieure doree
            F((rf[g][i], rf[g][j], rf[g + 1][j], rf[g + 1][i]), mi, front)
            F((rb[g][j], rb[g][i], rb[g + 1][i], rb[g + 1][j]), mi, back)
        F((rf[-1][i], rf[-1][j], af), 1, front)
        F((rb[-1][j], rb[-1][i], ab), 1, back)
    bm.normal_update()
    for f in front:
        if f.normal.y < 0:
            f.normal_flip()
    for f in back:
        if f.normal.y > 0:
            f.normal_flip()
    for f in wall:
        c = f.calc_center_median()
        if inside(poly, Vector((c.x + f.normal.x * 0.03, c.z + f.normal.z * 0.03))):
            f.normal_flip()
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:                                     # arete franche : pieds (angles vifs) et bord de l'etoile interieure
        try:
            if e.is_manifold and e.calc_face_angle() > math.radians(50):
                e.smooth = False
            elif len(e.link_faces) == 2 and e.link_faces[0].material_index != e.link_faces[1].material_index:
                e.smooth = False
        except Exception:
            pass
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me, zc, ymax

# ---------------------------------------------------------------- nettoyage (uniquement B18_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B18_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B18_"):
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
m_star = mat("DIAG_B18_Star", "#2A4FC4", 0.3)
m_inner = mat("DIAG_B18_Inner_Metal", "#FFC52E", 0.3, metal=0.4)
m_collar = mat("DIAG_B18_Collar", "#1E3A94", 0.4)

report = []
for v, src_root, off in (("PC", base_root, Vector((4 * 2, 0, 0))), ("MOBILE", mob_root, Vector((4 * 2, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B18_Etoiles_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B18_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B18", "Etoiles", v
    root["default_explosion"], root["spark_color"] = "E14", "#FFD84A"
    root["orientation"] = "plan de l'etoile vertical, face vers +Z Roblox ; pivoter en Y pour faire face a la camera"
    body, collar, fuse = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"))
    neck = find_part(made, "BombNeck")
    me, zc, ymax = star_geometry(f"B18_Star_{v}", v)
    me.materials.append(m_star); me.materials.append(m_inner)
    body.data = me
    body.location = (0, 0, zc)
    neck_z = zc + ymax - NECK_SINK
    neck.location.z = neck_z
    cme = ninja_collar_mesh(f"B18_Collar_{v}", SVARS[v]["collar_seg"])
    cme.transform(Matrix.Scale(COLLAR_SCALE, 4))
    cme.materials.append(m_collar)
    collar.data = cme
    fme = ninja_fuse_mesh(f"B18_Fuse_{v}", *SVARS[v]["fuse"])
    fme.materials.append(m_fuse); fme.materials.append(m_tip)
    fuse.data = fme
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B18_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off + Vector((0, 0, neck_z - BASE_NECK_Z))
        set_obj_materials(sp, [mat("DIAG_B18_Spark", "#FFD84A", 0.3, 1.2)])
    n_t = sum(tris(o.data) for o in made.values() if o.type == 'MESH')
    report.append((v, n_t, zc, neck_z, ymax))

bpy.context.view_layer.update()
for v, n_t, zc, nz, ym in report:
    print(f"B18 {v:7s} {n_t:5d} tris | centre z={zc:.3f} | pointe haute local y={ym:.3f} | cou z={nz:.3f}")
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B18_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | epaisseur Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
