"""
Boom Battle - B24 Cristal v2 : grappe de cristaux SCULPTEE (meme exigence de finition que le Crane v2).
(remplace la v1 = prisme unique + 6 petits cristaux separes, conservee dans history/)

- 8 cristaux hexagonaux (1 grand, 7 secondaires de tailles/inclinaisons variees) : facettes PLANES par construction
  (les 6 sommets de chaque anneau partagent le meme facteur d'irregularite -> faces trapezoidales planes) ;
  terminaison pointue (le grand : sommet tronque pour la virole).
- Socle rocheux facette (prisme a 9 pans, pied plat) d'ou la grappe pousse.
- Aretes BISEAUTEES (cristaux de PC) : fines facettes claires le long de toutes les aretes = bords polis qui accrochent la lumiere.
- UNION BOOLEENNE EXACTE socle + cristaux -> une seule enveloppe propre (plus de coques qui s'interpenetrent).
- Tons de facettes par orientation (Light / Mid / Deep) + socle (Rock) ; ombrage PLAT (cristal).
Pieces exportees (4 materiaux d'un meme objet BombBody_Base) : BombBody_Rock, BombBody_Deep, BombBody_Mid, BombBody_Light (Neon) ;
+ virole fine violette sombre + meche lisse. Symetrie approx. 360 deg : lisible sous les 4 lacets de la camera du jeu.
Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B24_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_B16 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b16_shuriken_debout.py"
exec(compile(open(_B16, encoding="utf-8").read().split("# ---------------------------------------------------------------- nettoyage (uniquement B16_*)")[0], "b16_defs", "exec"))

K24 = {
    "PC":     dict(bevel=True,  n_small=7, collar_seg=20, fuse=(10, 26)),
    "MOBILE": dict(bevel=False, n_small=4, collar_seg=12, fuse=(8, 14)),
}
LIGHT = Vector((0.35, 0.45, 0.82)).normalized()
TONES = (0.62, 0.05)                     # seuils Light / Mid / Deep sur n . L : Light = facettes de terminaison tournees vers le haut
BEVEL_W = 0.032

# (nom, base, azimut d'inclinaison, inclinaison, longueur, rayon, rotation, rayon du sommet (0 = pointe))
CRYSTALS = [
    ("main", (0.00, 0.00, 0.30), 0, 0, 2.52, 0.95, 8, 0.42),
    ("s1", (0.80, 0.35, 0.35), 25, 22, 1.75, 0.40, 20, 0.0),
    ("s2", (-0.80, 0.45, 0.35), 150, 26, 1.50, 0.38, -10, 0.0),
    ("s3", (-0.55, -0.85, 0.35), 255, 28, 1.35, 0.36, 5, 0.0),
    ("s4", (0.65, -0.80, 0.35), 320, 24, 1.20, 0.33, 15, 0.0),
    ("s5", (-1.00, -0.10, 0.30), 190, 34, 0.95, 0.28, 0, 0.0),
    ("s6", (0.30, 0.95, 0.30), 80, 36, 0.80, 0.24, 30, 0.0),
    ("s7", (-0.30, 0.95, 0.30), 100, 34, 0.70, 0.22, -20, 0.0),
]

def crystal_bm(spec, bevel, rng):
    name, base, az, tilt, L, r, rot, top = spec
    base = Vector(base)
    a_, t_ = math.radians(az), math.radians(tilt)
    axis = Vector((math.cos(a_) * math.sin(t_), math.sin(a_) * math.sin(t_), math.cos(t_))).normalized()
    u = axis.cross(Vector((0, 0, 1)))
    if u.length < 1e-4:
        u = Vector((1, 0, 0))
    u.normalize(); w = axis.cross(u)
    f = [1.0 + 0.07 * (rng.random() * 2 - 1) for _ in range(6)]           # irregularite PAR SOMMET, commune a tous les anneaux
    rings = [(0.0, 0.90 * r, 0.9), (0.12, r, 1.0), (1.0 - 0.32 - (0.0 if top else 0.06), r, 1.0), (1.0, top, 1.0)]
    # anneaux : (t le long de l'axe, rayon, - ) ; le dernier = sommet (rayon 0 -> un seul sommet)
    bm = bmesh.new()
    rows = []
    for t, rad, _ in rings:
        row = []
        for k in range(6):
            th = math.tau * k / 6 + math.radians(rot)
            row.append((base + axis * (t * L) + (u * math.cos(th) + w * math.sin(th)) * rad * f[k]))
        rows.append(row)
    vr = [[bm.verts.new(p) for p in row] for row in rows[:-1]]
    if top > 0:
        vr.append([bm.verts.new(p) for p in rows[-1]])
        apex = None
    else:
        apex = bm.verts.new(base + axis * L)
    for i in range(len(vr) - 1):
        for k in range(6):
            k2 = (k + 1) % 6
            bm.faces.new((vr[i][k], vr[i][k2], vr[i + 1][k2], vr[i + 1][k]))
    if apex is not None:
        for k in range(6):
            bm.faces.new((vr[-1][k], vr[-1][(k + 1) % 6], apex))
    else:
        pass
    bm.faces.new(vr[0][::-1])                                             # base (enfouie dans le socle)
    if top > 0:
        bm.faces.new(vr[-1])                                              # table du sommet (pour la virole)
    center = base + axis * (0.5 * L)
    bm.normal_update()
    for fc in bm.faces:
        c = fc.calc_center_median()
        p = center + axis * ((c - center).dot(axis))
        if fc.normal.dot(c - p) < 0 and abs(fc.normal.dot(axis)) < 0.99:
            fc.normal_flip()
        elif abs(fc.normal.dot(axis)) >= 0.99:
            if fc.normal.dot(c - center) < 0:
                fc.normal_flip()
    bm.normal_update()
    tone_of = {}
    for fc in bm.faces:
        t = fc.normal.dot(LIGHT)
        tone_of[fc] = 2 if t > TONES[0] else (1 if t > TONES[1] else 0)      # 0 Deep, 1 Mid, 2 Light
    for fc in bm.faces:
        fc.material_index = tone_of[fc]
        fc.smooth = False
    if bevel:
        edges = list(bm.edges)
        res = bmesh.ops.bevel(bm, geom=edges, offset=BEVEL_W, offset_type='OFFSET', segments=1, affect='EDGES')
        for fc in res["faces"]:
            fc.material_index = 2                                            # bords polis = ton clair
            fc.smooth = False
    return bm

def rock_bm(rng):
    bm = bmesh.new()
    prof = [(1.25, 0.00), (1.52, 0.22), (1.18, 0.52)]
    n = 9
    rows = []
    for r, z in prof:
        rows.append([bm.verts.new(((r * (1 + 0.08 * (rng.random() * 2 - 1))) * math.cos(math.tau * k / n + 0.2 * z),
                                    (r * (1 + 0.08 * (rng.random() * 2 - 1))) * math.sin(math.tau * k / n + 0.2 * z), z)) for k in range(n)])
    for i in range(len(rows) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]))
    bm.faces.new(rows[0][::-1]); bm.faces.new(rows[-1])
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.normal_update()
    cen = Vector((0, 0, 0.25))
    for fc in bm.faces:
        if fc.normal.dot(fc.calc_center_median() - cen) < 0:
            fc.normal_flip()
        fc.material_index = 0
        fc.smooth = False
    return bm

def to_obj(bm, name, mats, coll):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.hide_render = True
    return ob

def cluster_mesh(v, m_rock, m_tones):
    cfg = K24[v]
    for o in [o for o in bpy.data.objects if o.name.startswith("tmp_")]:
        bpy.data.objects.remove(o, do_unlink=True)
    for c_ in [c_ for c_ in bpy.data.collections if c_.name.startswith("TMP_")]:
        bpy.data.collections.remove(c_)
    sc = bpy.context.scene
    base_c, cu = bpy.data.collections.new("TMP_BASE"), bpy.data.collections.new("TMP_U")
    for c_ in (base_c, cu):
        sc.collection.children.link(c_)
    rng = random.Random(24)
    target = to_obj(rock_bm(rng), "tmp_rock", [m_rock], base_c)
    for spec in CRYSTALS[: 1 + cfg["n_small"]]:
        to_obj(crystal_bm(spec, cfg["bevel"], rng), "tmp_" + spec[0], list(m_tones), cu)
    md = target.modifiers.new("U", 'BOOLEAN')
    md.operation, md.operand_type, md.collection, md.solver = 'UNION', 'COLLECTION', cu, 'EXACT'
    try:
        md.material_mode = 'TRANSFER'
    except Exception as e:
        print("material_mode indisponible :", e)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    me.name = f"B24_Cluster_{v}"                                  # (avant le nettoyage des tmp_*)
    for c_ in (base_c, cu):
        for o in list(c_.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c_)
    for t_ in [t_ for t_ in bpy.data.meshes if t_.name.startswith("tmp_") and t_.users == 0]:
        bpy.data.meshes.remove(t_)
    # ordre canonique des materiaux : Rock, Deep, Mid, Light
    canon = [m_rock.name] + [m.name for m in m_tones]
    idx = [canon.index(me.materials[p.material_index].name) if p.material_index < len(me.materials) else 0 for p in me.polygons]
    me.materials.clear()
    for nm in canon:
        me.materials.append(bpy.data.materials[nm])
    for p, i in zip(me.polygons, idx):
        p.material_index = i
        p.use_smooth = False
    me.name = f"B24_Cluster_{v}"
    return me

# ---------------------------------------------------------------- nettoyage (uniquement B24_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B24_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B24_"):
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
m_rock = mat("DIAG_B24_Rock", "#463070", 0.7)
m_deep = mat("DIAG_B24_Deep", "#5E34C8", 0.2)
m_mid = mat("DIAG_B24_Mid", "#A06CFF", 0.2)
m_light = mat("DIAG_B24_Light_Neon", "#CDB0FF", 0.15, emit=0.5)
m_collar = mat("DIAG_B24_Collar", "#2E1C5E", 0.4)

report = []
for v, src_root, off in (("PC", base_root, Vector((12, 0, 0))), ("MOBILE", mob_root, Vector((12, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B24_Cristal_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B24_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B24", "Cristal", v
    root["default_explosion"], root["spark_color"] = "E12", "#E0C8FF"
    body, collar, fuse = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"))
    neck = find_part(made, "BombNeck")
    me = cluster_mesh(v, m_rock, (m_deep, m_mid, m_light))
    body.data = me
    body.location = (0, 0, 0)
    neck_z = 0.30 + CRYSTALS[0][4] - 0.10
    neck.location.z = neck_z
    cme = ninja_collar_mesh(f"B24_Collar_{v}", K24[v]["collar_seg"]); cme.materials.append(m_collar); collar.data = cme
    fme = ninja_fuse_mesh(f"B24_Fuse_{v}", *K24[v]["fuse"]); fme.materials.append(m_fuse); fme.materials.append(m_tip); fuse.data = fme
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B24_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off + Vector((0, 0, neck_z - BASE_NECK_Z))
        set_obj_materials(sp, [mat("DIAG_B24_Spark", "#E0C8FF", 0.3, 1.2)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH'), tris(me)))

bpy.context.view_layer.update()
import collections
for v, n_t, n_b in report:
    print(f"B24 {v:7s} total {n_t:5d} tris | corps {n_b:5d}")
for v, nm in (("PC", "B24_BombBody_Base"), ("MOBILE", "B24_BombBody_Base_Mobile")):
    me = bpy.data.objects[nm].data
    bm = bmesh.new(); bm.from_mesh(me)
    print(f"  {v}: materiaux {[m.name for m in me.materials]} | repartition {dict(collections.Counter(q.material_index for q in me.polygons))} | bords ouverts {sum(1 for e in bm.edges if len(e.link_faces)==1)} | aretes>2 faces {sum(1 for e in bm.edges if len(e.link_faces)>2)}")
    bm.free()
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B24_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
