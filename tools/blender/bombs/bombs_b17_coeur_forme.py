"""
Boom Battle - B17 Coeur v2 : la BOMBE EST UN COEUR 2.5D, DEBOUT, LISSE (meme approche que le Ninja v6).
(remplace la v1 = sphere + 4 coeurs en relief, conservee dans history/)

Forme : coeur (courbe parametrique classique) de 3,0 studs de large, plan VERTICAL face a +Y Blender (= +Z Roblox),
pointe du bas coupee a l'horizontale : le coeur tient debout sur un pied plat.
Relief 2.5D "gonfle" : paroi arrondie, dome peu gonfle (demi-epaisseur 0,24 -> 0,62) en 7 anneaux (PC) ; un COEUR INTERIEUR clair (bord net) sur le dome.
Collerette fine + meche lisse = celles du Ninja (definitions reprises du script B16), recolorees ; elles sortent du creux du haut.
Pieces exportees : BombBody_Heart (rose-rouge), BombBody_Inner (rose clair), collerette, meche, bout.
Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B17_*).
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

# definitions partagees (mat, clone_tree, clip_below, inside, ninja_collar_mesh, ninja_fuse_mesh, ...) reprises du script B16
_B16 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b16_shuriken_debout.py"
exec(compile(open(_B16, encoding="utf-8").read().split("# ---------------------------------------------------------------- nettoyage (uniquement B16_*)")[0], "b16_defs", "exec"))

HW, FOOT_H, ORIGIN_FRAC = 3.0, 0.30, 0.38          # largeur du coeur, hauteur du pied plat, hauteur de l'origine (part de la hauteur)
NECK_OFFSET = 0.18                                 # collerette posee au fond du creux (ajustable)
HVARS = {
    "PC": dict(n=40, rings=[(1.0, 0.24), (0.985, 0.34), (0.955, 0.42), (0.905, 0.49), (0.83, 0.54), (0.73, 0.58), (0.62, 0.60)],
               inner_ring=5, apex=0.62, collar_seg=20, fuse=(10, 26)),
    "MOBILE": dict(n=24, rings=[(1.0, 0.24), (0.95, 0.40), (0.83, 0.53), (0.62, 0.60)],
                   inner_ring=2, apex=0.62, collar_seg=12, fuse=(8, 14)),
}

def heart_outline(n):
    """Contour du coeur (courbe classique), largeur HW, origine a ORIGIN_FRAC de la hauteur ; sommet 0 = creux du haut."""
    raw = []
    for k in range(n):
        t = math.tau * k / n
        raw.append((16 * math.sin(t) ** 3, 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)))
    sc = HW / 32.0
    ymin, ymax = -17.0, max(p[1] for p in raw)
    oy = ymin + ORIGIN_FRAC * (ymax - ymin)
    pts = [Vector((x * sc, (y - oy) * sc)) for x, y in raw]
    return pts, (5.0 - oy) * sc                      # (contour, hauteur locale du creux)

def heart_geometry(name, v):
    cfg = HVARS[v]
    poly, cleft_y = heart_outline(cfg["n"])
    ang = [math.atan2(p.y, p.x) for p in poly]
    dd = [((ang[(i + 1) % len(ang)] - ang[i] + math.pi) % math.tau) - math.pi for i in range(len(ang))]
    mono = all(x > -1e-9 for x in dd) or all(x < 1e-9 for x in dd)       # contour etoile : l'angle tourne toujours dans le meme sens
    zcut = min(p.y for p in poly) + FOOT_H
    poly = clip_below(poly, zcut)
    zc = -zcut                                         # hauteur du centre : pied plat a z = 0
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
            mi = 0 if g < cfg["inner_ring"] else 1       # au-dela de l'anneau "inner_ring" : coeur interieur clair
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
    for e in bm.edges:                                     # arete franche : angles vifs (pied, creux) et bord du coeur interieur
        try:
            if e.is_manifold and e.calc_face_angle() > math.radians(50):
                e.smooth = False
            elif len(e.link_faces) == 2 and e.link_faces[0].material_index != e.link_faces[1].material_index:
                e.smooth = False
        except Exception:
            pass
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me, zc, cleft_y, mono

# ---------------------------------------------------------------- nettoyage (uniquement B17_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B17_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B17_"):
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
m_heart = mat("DIAG_B17_Heart", "#E0245E", 0.3)
m_inner = mat("DIAG_B17_Inner", "#FF8FB1", 0.35)
m_collar = mat("DIAG_B17_Collar", "#A81645", 0.4)

report = []
for v, src_root, off in (("PC", base_root, Vector((4 * 1, 0, 0))), ("MOBILE", mob_root, Vector((4 * 1, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B17_Coeur_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B17_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B17", "Coeur", v
    root["default_explosion"], root["spark_color"] = "E13", "#FF7FB0"
    root["orientation"] = "plan du coeur vertical, face vers +Z Roblox ; pivoter en Y pour faire face a la camera"
    body, collar, fuse = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"))
    neck = find_part(made, "BombNeck")
    me, zc, cleft_y, mono = heart_geometry(f"B17_Heart_{v}", v)
    if not mono:
        print("ATTENTION : le contour n'est pas etoile par rapport a l'origine")
    me.materials.append(m_heart); me.materials.append(m_inner)
    body.data = me
    body.location = (0, 0, zc)
    neck_z = zc + cleft_y + NECK_OFFSET
    neck.location.z = neck_z
    cme = ninja_collar_mesh(f"B17_Collar_{v}", HVARS[v]["collar_seg"])
    cme.materials.append(m_collar)
    collar.data = cme
    fme = ninja_fuse_mesh(f"B17_Fuse_{v}", *HVARS[v]["fuse"])
    fme.materials.append(m_fuse); fme.materials.append(m_tip)
    fuse.data = fme
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B17_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off + Vector((0, 0, neck_z - BASE_NECK_Z))
        set_obj_materials(sp, [mat("DIAG_B17_Spark", "#FF7FB0", 0.3, 1.2)])
    n_t = sum(tris(o.data) for o in made.values() if o.type == 'MESH')
    report.append((v, n_t, zc, neck_z, cleft_y))

bpy.context.view_layer.update()
for v, n_t, zc, nz, cy in report:
    print(f"B17 {v:7s} {n_t:5d} tris | centre z={zc:.3f} | creux local y={cy:.3f} | cou z={nz:.3f}")
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B17_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | epaisseur Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
