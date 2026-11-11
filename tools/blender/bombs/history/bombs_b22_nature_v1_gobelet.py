"""
Boom Battle - B22 Nature : d'apres le SCHEMA de modelisation du proprietaire ("Bombe Nature").
Schema : corps en BOIS (noix de coco / ecorce) brun avec rainures et reliefs de bois horizontaux ; col en BOIS CLAIR (gobelet large) ;
FEUILLES vertes stylisees (grappes autour de fleurs) ; FLEURS blanches a 5 PETALES et coeur orange ; meche en corde ; etincelle jaune-orange.
Construction :
  - CORPS : sphere (Wood) dont l'ECORCE est creusee de 4 RAINURES horizontales legerement inclinees (DIFFERENCE BOOLEENNE avec 4 tores fins,
    interieur sombre) = lignes de veines/ecorce qui se lisent de tous les cotes.
  - COL : gobelet en bois clair (revolution), trou sombre pour la meche.
  - 14 FEUILLES lanceolees (coque fermee mince, nervure legerement surelevee, pointe relevee) posees le long de la sphere, en 2 tons de vert.
  - 3 FLEURS (devant-gauche, devant-bas, dos) : 5 petales blancs en coupe + coeur orange.
Pieces exportees : BombBody_Wood (Wood), BombBody_Groove ; BombSkin_LeafA/LeafB ; BombSkin_Petals ; BombSkin_Core ; BombCollar_Base (Wood clair) ; meche ; bout.
Le devant (feuilles/fleur en bas) = +Y Blender (+Z Roblox) mais le decor est reparti sur 360 deg (dos fleuri aussi).
Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B22_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

# helpers (frame, direction, surface, mesh_from, disc, torus_mesh...) repris du script du Robot v3 + definitions communes (mat, clone_tree, ...)
_ROB = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b21_robot_v3_schema.py"
exec(compile(open(_ROB, encoding="utf-8").read().split("def shell_mesh(")[0], "robot_helpers", "exec"))

N22 = {
    "PC":     dict(seg=24, rings=12, tor=(32, 4), leaf_nt=5, leaf_solid=False, petal_n=8, core_n=10, collar_seg=20, fuse=(8, 22)),
    "MOBILE": dict(seg=16, rings=9,  tor=(24, 4), leaf_nt=3, leaf_solid=False, petal_n=6, core_n=6,  collar_seg=12, fuse=(8, 14)),
}
GROOVES = [(-0.95, 7, 40), (-0.42, 9, 200), (0.12, 8, 100), (0.66, 7, 300)]      # (hauteur rel. centre, inclinaison deg, azimut d'inclinaison)
FLOWERS = [(30, 6, 12), (100, -36, 30), (262, 12, 0)]                              # (az, el, rotation)
LEAVES = [(62, 52, 165, 1.15, 0.54), (44, 38, 118, 1.00, 0.50), (32, 28, 95, 0.85, 0.44), (18, -14, 215, 0.80, 0.42),
          (76, -42, 190, 0.95, 0.47), (126, -34, 8, 0.95, 0.47), (100, -14, 92, 0.85, 0.44),
          (150, 32, 28, 1.05, 0.50), (160, 6, 352, 1.00, 0.50), (146, -42, 330, 0.60, 0.32),
          (240, 38, 125, 0.95, 0.47), (288, -14, 335, 0.90, 0.45), (254, -38, 205, 0.80, 0.40), (205, 20, 160, 0.90, 0.44),
          (12, 4, 250, 0.85, 0.42), (44, -6, 15, 0.80, 0.40), (276, 28, 55, 0.85, 0.42)]   # (az, el, psi, longueur, largeur)

def leaf(bm, az, el, psi, L, W, nt, solid, lift=0.10, thick=0.03):
    d, u, w = frame(direction(az, el))
    t0 = (u * math.cos(math.radians(psi)) + w * math.sin(math.radians(psi))).normalized()
    top, bot = [], []
    for i in range(nt + 1):
        t = i / nt
        ang = t * L / RS
        pd = (d * math.cos(ang) + t0 * math.sin(ang)).normalized()
        tg = (-d * math.sin(ang) + t0 * math.cos(ang))
        lat = pd.cross(tg).normalized()
        wd = 0.5 * W * (math.sin(math.pi * (t ** 0.85)) ** 0.75) if 0 < t < 1 else 0.0
        h = 0.04 + lift * t * t
        rt, rb = [], []
        for s_ in (-1, 0, 1):
            hh = h + (0.06 * (wd / (0.5 * W)) if s_ == 0 and wd > 0 else 0.0)
            rt.append(bm.verts.new(pd * (RS + hh) + lat * (s_ * wd)))
            if solid:
                rb.append(bm.verts.new(pd * (RS + hh - thick) + lat * (s_ * wd)))
        top.append(rt); bot.append(rb)
    new = []
    for i in range(nt):
        for j in range(2):
            f = bm.faces.new((top[i][j], top[i][j + 1], top[i + 1][j + 1], top[i + 1][j]))
            f.material_index = j                       # 0 = LeafA (cote gauche), 1 = LeafB (cote droit)
            new.append(f)
            if solid:
                fb = bm.faces.new((bot[i][j + 1], bot[i][j], bot[i + 1][j], bot[i + 1][j + 1]))
                fb.material_index = j
                new.append(fb)
        if solid:
            for s_ in (0, 2):
                fs = bm.faces.new((top[i][s_], top[i + 1][s_], bot[i + 1][s_], bot[i][s_]) if s_ == 0 else (top[i + 1][s_], top[i][s_], bot[i][s_], bot[i + 1][s_]))
                fs.material_index = 0 if s_ == 0 else 1
                new.append(fs)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    new = [f for f in new if f.is_valid]
    bm.normal_update()
    if solid:
        bmesh.ops.recalc_face_normals(bm, faces=new)
    for f in new:
        if f.normal.dot(f.calc_center_median()) < 0 and not solid:
            f.normal_flip()
    return new

def petal(bm, d, u, w, ang, size, n, solid):
    cx, cy = 0.55 * size, 0.0
    ex, ey = 0.55 * size, 0.40 * size
    ca, sa = math.cos(ang), math.sin(ang)
    def P(px, py, h):
        x, y = px * ca - py * sa, px * sa + py * ca
        return bm.verts.new(surface(d, u, w, x, y, h))
    ring_t = [P(cx + ex * math.cos(t), cy + ey * math.sin(t), 0.035 + 0.05 * (0.5 + 0.5 * math.cos(t))) for t in (math.tau * k / n for k in range(n))]
    apex_t = P(cx, cy, 0.075)
    new = []
    for k in range(n):
        new.append(bm.faces.new((ring_t[k], ring_t[(k + 1) % n], apex_t)))
    if solid:
        ring_b = [P(cx + ex * math.cos(t), cy + ey * math.sin(t), 0.005) for t in (math.tau * k / n for k in range(n))]
        apex_b = P(cx, cy, 0.0)
        for k in range(n):
            new.append(bm.faces.new((ring_b[(k + 1) % n], ring_b[k], apex_b)))
            new.append(bm.faces.new((ring_t[k], ring_b[k], ring_b[(k + 1) % n], ring_t[(k + 1) % n])))
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=new)
    for f in new:
        if f.normal.dot(f.calc_center_median()) < 0 and not solid:
            f.normal_flip()

def flowers_meshes(v):
    cfg = N22[v]
    pet, core = bmesh.new(), bmesh.new()
    for az, el, rot in FLOWERS:
        d, u, w = frame(direction(az, el))
        for k in range(5):
            petal(pet, d, u, w, math.radians(rot) + math.tau * k / 5, 0.44, cfg["petal_n"], cfg["leaf_solid"])
        disc(core, direction(az, el), 0.10, 0.11, cfg["core_n"])
    return mesh_from(pet, f"B22_Petals_{v}", True), mesh_from(core, f"B22_Core_{v}", True)

def leaves_mesh(v):
    cfg = N22[v]
    bm = bmesh.new()
    for az, el, psi, L, W in LEAVES:
        leaf(bm, az, el, psi, L * 1.20, W * 1.60, cfg["leaf_nt"], cfg["leaf_solid"])
    for f in bm.faces:
        f.smooth = False
    return mesh_from(bm, f"B22_Leaves_{v}", False)

def wood_shell(v, m_wood, m_groove, m_wood2):
    cfg = N22[v]
    for o in [o for o in bpy.data.objects if o.name.startswith("tmp_")]:
        bpy.data.objects.remove(o, do_unlink=True)
    for c_ in [c_ for c_ in bpy.data.collections if c_.name.startswith("TMP_")]:
        bpy.data.collections.remove(c_)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=cfg["seg"], v_segments=cfg["rings"], radius=RS)
    bmesh.ops.scale(bm, vec=(1, 1, ZSQ), verts=bm.verts)
    for f in bm.faces:
        f.smooth = True
    tme = bpy.data.meshes.new("tmp_shell"); bm.to_mesh(tme); bm.free(); tme.materials.append(m_wood)
    sc = bpy.context.scene
    base_c, cd = bpy.data.collections.new("TMP_BASE"), bpy.data.collections.new("TMP_D")
    for c_ in (base_c, cd):
        sc.collection.children.link(c_)
    target = bpy.data.objects.new("tmp_shell", tme); base_c.objects.link(target); target.hide_render = True
    M, mm = cfg["tor"]
    for k, (h, tilt, taz) in enumerate(GROOVES):
        a_, t_ = math.radians(taz), math.radians(tilt)
        normal = Vector((math.sin(t_) * math.cos(a_), math.sin(t_) * math.sin(a_), math.cos(t_)))
        dd = h * math.cos(t_)                                           # plan n.p = dd : le cercle est EXACTEMENT sur la sphere
        me_c = torus_mesh(f"tmp_g{k}", math.sqrt(RS * RS - dd * dd), 0.065, M, mm, tuple(normal), tuple(normal * dd), m_groove)
        o = bpy.data.objects.new(f"tmp_g{k}", me_c); cd.objects.link(o); o.hide_render = True
    md = target.modifiers.new("D", 'BOOLEAN')
    md.operation, md.operand_type, md.collection, md.solver = 'DIFFERENCE', 'COLLECTION', cd, 'EXACT'
    try:
        md.material_mode = 'TRANSFER'
    except Exception as e:
        print("material_mode indisponible :", e)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    me.name = f"B22_Shell_{v}"
    for c_ in (base_c, cd):
        for o in list(c_.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c_)
    for t_ in [t_ for t_ in bpy.data.meshes if t_.name.startswith("tmp_") and t_.users == 0]:
        bpy.data.meshes.remove(t_)
    names = [m.name for m in me.materials]
    idx = [1 if (p.material_index < len(names) and names[p.material_index] == m_groove.name) else 0 for p in me.polygons]
    out = bpy.data.meshes.new(me.name + "_final")
    bm2 = bmesh.new(); bm2.from_mesh(me)
    for i_, f_ in enumerate(bm2.faces):                # bandes de bois alternees entre les rainures
        if idx[i_] == 0:
            c_ = f_.calc_center_median()
            c_ = Vector((c_.x, c_.y, c_.z / ZSQ))
            k_ = 0
            for h_, tl_, ta_ in GROOVES:
                n_ = Vector((math.sin(math.radians(tl_)) * math.cos(math.radians(ta_)), math.sin(math.radians(tl_)) * math.sin(math.radians(ta_)), math.cos(math.radians(tl_))))
                if c_.dot(n_) - h_ * math.cos(math.radians(tl_)) > 0:
                    k_ += 1
            if k_ % 2 == 1:
                idx[i_] = 2
    for e in bm2.edges:
        try:
            if e.is_manifold and e.calc_face_angle() > math.radians(50):
                e.smooth = False
        except Exception:
            pass
    bm2.to_mesh(out); bm2.free()
    out.materials.append(m_wood); out.materials.append(m_groove); out.materials.append(m_wood2)
    for p, i in zip(out.polygons, idx):
        p.material_index = i
        p.use_smooth = True
    bpy.data.meshes.remove(me)
    out.name = f"B22_Shell_{v}"
    return out

def wood_collar(v, m):
    """Gobelet en bois clair (revolution) : bride, corps, levre epaisse, trou."""
    prof = [(0.72, -0.20), (0.72, 0.10), (0.65, 0.16), (0.62, 0.50), (0.69, 0.55), (0.69, 0.66), (0.40, 0.66), (0.40, 0.30), (0.22, 0.22)]
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in prof]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), dvec=(0, 0, 0), angle=math.tau, steps=N22[v]["collar_seg"], use_merge=True, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    f0 = max(bm.faces, key=lambda f: Vector((f.calc_center_median().x, f.calc_center_median().y, 0)).length)
    if f0.normal.dot(Vector((f0.calc_center_median().x, f0.calc_center_median().y, 0))) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    for e in bm.edges:
        try:
            if e.is_manifold and e.calc_face_angle() > math.radians(50):
                e.smooth = False
        except Exception:
            pass
    me = bpy.data.meshes.new(f"B22_Collar_{v}")
    bm.to_mesh(me); bm.free(); me.materials.append(m)
    return me

# ---------------------------------------------------------------- nettoyage (uniquement B22_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B22_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B22_"):
        bpy.data.collections.remove(c)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

diag = bpy.data.collections["BOMB_BASE_DIAG"]
base_root, mob_root = bpy.data.objects["BombVisualRoot"], bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)
spark_src = bpy.data.objects["DIAG_SparkPreview"]
spark_loc = spark_src.location.copy()
m_rope, m_tip = mat("DIAG_B22_Rope", "#B98A4C", 0.7), mat("DIAG_FuseTip", "#2A1C12", 0.8)
m_wood = mat("DIAG_B22_Wood", "#8A5530", 0.8)
m_wood2 = mat("DIAG_B22_Wood2", "#74462A", 0.8)
m_groove = mat("DIAG_B22_Groove", "#47281A", 0.9)
m_collar = mat("DIAG_B22_Collar_Wood", "#DDAB5E", 0.65)
m_leafA = mat("DIAG_B22_LeafA", "#58C24D", 0.55)
m_leafB = mat("DIAG_B22_LeafB", "#2FA043", 0.55)
m_petal = mat("DIAG_B22_Petals", "#FBF8EE", 0.5)
m_core = mat("DIAG_B22_Core", "#F59A1B", 0.5)

report = []
for v, src_root, off in (("PC", base_root, Vector((4, 0, 0))), ("MOBILE", mob_root, Vector((4, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B22_Nature_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B22_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B22", "Nature", v
    root["default_explosion"], root["spark_color"] = "E22", "#FFC63A"
    body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
    sh = wood_shell(v, m_wood, m_groove, m_wood2)
    body.data = sh
    body.location = (0, 0, 1.455)
    collar.data = wood_collar(v, m_collar)
    fme = ninja_fuse_mesh(f"B22_Fuse_{v}", *N22[v]["fuse"]); fme.materials.append(m_rope); fme.materials.append(m_tip); fuse.data = fme
    lv = leaves_mesh(v); lv.materials.append(m_leafA); lv.materials.append(m_leafB)
    pet, core = flowers_meshes(v); pet.materials.append(m_petal); core.materials.append(m_core)
    extras = [("BombSkin_Leaves", lv), ("BombSkin_Petals", pet), ("BombSkin_Core", core)]
    for nm, mesh in extras:
        ob = bpy.data.objects.new("B22_" + nm + ("_Mobile" if v == "MOBILE" else ""), mesh)
        col.objects.link(ob)
        ob.parent = details
        ob.location = body.location
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B22_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off
        set_obj_materials(sp, [mat("DIAG_B22_Spark", "#FFC63A", 0.3, 1.5)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH') + sum(tris(m) for _, m in extras), tris(sh), tris(lv), tris(pet) + tris(core)))

bpy.context.view_layer.update()
import collections
for v, n_t, n_b, n_l, n_f in report:
    print(f"B22 {v:7s} total {n_t:5d} tris | coque {n_b:5d} | feuilles {n_l:4d} | fleurs {n_f:4d}")
for v, nm in (("PC", "B22_BombBody_Base"), ("MOBILE", "B22_BombBody_Base_Mobile")):
    me = bpy.data.objects[nm].data
    bm = bmesh.new(); bm.from_mesh(me)
    print(f"  {v}: coque repartition {dict(sorted(collections.Counter(q.material_index for q in me.polygons).items()))} | bords ouverts {sum(1 for e in bm.edges if len(e.link_faces)==1)} | aretes>2 faces {sum(1 for e in bm.edges if len(e.link_faces)>2)}")
    bm.free()
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B22_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w_ = o.matrix_world @ vv.co
                xs.append(w_.x); ys.append(w_.y); zs.append(w_.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
