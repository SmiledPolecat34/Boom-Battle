"""
Boom Battle - B21 Robot v2 : d'apres la photo de reference du proprietaire.
(remplace la v1 = sphere blanche + 8 petits panneaux bleus + 1 oeil central, conservee dans history/)

Photo : sphere blanche a lignes de panneaux, DEUX YEUX (un grand a gauche : lunette sombre / anneau cyan / verre sombre avec reflet ;
un plus petit a droite : boitier sombre + gros disque cyan), bande cyan lumineuse en haut pres de la collerette, grand panneau
sombre en bas, grande collerette bleu nuit, etincelle orange.
Construction :
  - COQUE : sphere (3 tons : Shell blanc, Shell2 gris clair en ceinture, Dark en bas) dont les LIGNES DE PANNEAUX sont de vraies RAINURES
    creusees par DIFFERENCE BOOLEENNE avec 3 tores fins (couture centrale, ceinture basse, couture diagonale) ; l'interieur des rainures est sombre.
  - OEIL GAUCHE (grand) : boitier sombre / anneau cyan Neon / verre sombre / reflet ; OEIL DROIT : boitier sombre / disque cyan Neon / reflet.
  - BANDE CYAN en arc au sommet, devant. Collerette = celle de la base (grande), bleu nuit. Meche lisse.
Pieces exportees : BombBody_Shell, BombBody_Shell2, BombBody_Dark (3 materiaux de BombBody_Base) ; BombSkin_Dark (boitiers, verres),
BombSkin_Glow (Neon cyan), BombSkin_Shine (Neon reflets) ; collerette, meche, bout.
Avant (les deux yeux) = +Y Blender (+Z Roblox) : pivoter en Y vers la camera. Prerequis : bomb_base.py execute dans CE fichier.
Idempotent (ne touche qu'aux objets B21_*).
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

_B16 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b16_shuriken_debout.py"
exec(compile(open(_B16, encoding="utf-8").read().split("# ---------------------------------------------------------------- nettoyage (uniquement B16_*)")[0], "b16_defs", "exec"))

RS, ZSQ = 1.5, 0.97
R21 = {
    "PC":     dict(seg=22, rings=12, tor=(36, 4), eye_n=18, glass_n=18, fuse=(8, 22), shell_cuts=True),
    "MOBILE": dict(seg=16, rings=9,  tor=(24, 4), eye_n=12, glass_n=12, fuse=(8, 14),  shell_cuts=True),
}
BELT_Z = -0.70                                   # hauteur (rel. au centre) de la ceinture ; au-dessous : panneau sombre
GROOVE_R = 0.05                                  # rayon mineur des tores = profondeur / demi-largeur des rainures

def frame(d):
    d = d.normalized()
    u = Vector((0, 0, 1)).cross(d)
    if u.length < 1e-4:
        u = Vector((1, 0, 0)).cross(d)
    u.normalize()
    return d, u, d.cross(u)

def direction(az_deg, el_deg):
    a, e = math.radians(az_deg), math.radians(el_deg)
    return Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))

def surface(d, u, w, x, y, h):
    return (d * RS + u * x + w * y).normalized() * (RS + h)

def mesh_from(bm, name, smooth, squash=True):
    if squash:
        bmesh.ops.scale(bm, vec=(1, 1, ZSQ), verts=bm.verts)
    for f in bm.faces:
        f.smooth = smooth
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me

def disc(bm, d, r, h, n, r_in=None, sink=-0.03, offset=(0.0, 0.0)):
    """Disque (ou anneau si r_in) en relief sur la sphere, centre sur la direction d (decale de 'offset' dans le plan tangent)."""
    d, u, w = frame(d)
    ox, oy = offset
    ring = lambda rr, hh: [bm.verts.new(surface(d, u, w, ox + rr * math.cos(t), oy + rr * math.sin(t), hh)) for t in (math.tau * k / n for k in range(n))]
    bo, to = ring(r, sink), ring(r, h)
    outer, cap, inner = [], [], []
    for k in range(n):
        k2 = (k + 1) % n
        outer.append(bm.faces.new((bo[k], bo[k2], to[k2], to[k])))
    if r_in:
        ti, bi = ring(r_in, h), ring(r_in, sink)
        for k in range(n):
            k2 = (k + 1) % n
            cap.append(bm.faces.new((to[k], to[k2], ti[k2], ti[k])))
            inner.append(bm.faces.new((bi[k], bi[k2], ti[k2], ti[k])))
    else:
        apex = bm.verts.new(surface(d, u, w, ox, oy, h))
        for k in range(n):
            cap.append(bm.faces.new((to[k], to[(k + 1) % n], apex)))
    bm.normal_update()
    for f in cap:
        if f.normal.dot(d) < 0:
            f.normal_flip()
    for f in outer:
        c = f.calc_center_median()
        if f.normal.dot(c - d * c.dot(d)) < 0:
            f.normal_flip()
    for f in inner:
        c = f.calc_center_median()
        if f.normal.dot(c - d * c.dot(d)) > 0:
            f.normal_flip()

def arc_strip(bm, az0, az1, el, width, h, n):
    """Bande lumineuse en arc (petit cercle d'elevation el) entre les azimuts az0 et az1."""
    rows = []
    for k in range(n + 1):
        a = az0 + (az1 - az0) * k / n
        d = direction(a, el)
        up = (direction(a, el + 2.0) - d).normalized()
        rows.append([bm.verts.new((d * RS + up * s_ * width / 2).normalized() * (RS + hh)) for s_, hh in ((-1, 0.0), (-1, h), (1, h), (1, 0.0))])
    for k in range(n):
        for j in range(3):
            bm.faces.new((rows[k][j], rows[k + 1][j], rows[k + 1][j + 1], rows[k][j + 1]))
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median()) < 0:
            f.normal_flip()

def torus_mesh(name, major, minor, M, m, normal, center, mat_):
    bm = bmesh.new()
    rows = []
    for i in range(M):
        a = math.tau * i / M
        row = []
        for j in range(m):
            b = math.tau * j / m
            rr = major + minor * math.cos(b)
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), minor * math.sin(b))))
        rows.append(row)
    for i in range(M):
        i2 = (i + 1) % M
        for j in range(m):
            j2 = (j + 1) % m
            bm.faces.new((rows[i][j], rows[i][j2], rows[i2][j2], rows[i2][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rot = Vector((0, 0, 1)).rotation_difference(Vector(normal).normalized()).to_matrix()
    for v in bm.verts:
        v.co = rot @ v.co + Vector(center)
        v.co.z *= ZSQ
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    me.materials.append(mat_)
    return me

def shell_mesh(v, m_shell, m_shell2, m_dark):
    cfg = R21[v]
    for o in [o for o in bpy.data.objects if o.name.startswith("tmp_")]:
        bpy.data.objects.remove(o, do_unlink=True)
    for c_ in [c_ for c_ in bpy.data.collections if c_.name.startswith("TMP_")]:
        bpy.data.collections.remove(c_)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=cfg["seg"], v_segments=cfg["rings"], radius=RS)
    bmesh.ops.scale(bm, vec=(1, 1, ZSQ), verts=bm.verts)
    for f in bm.faces:
        f.smooth = True
    tme = bpy.data.meshes.new("tmp_shell"); bm.to_mesh(tme); bm.free(); tme.materials.append(m_shell)
    sc = bpy.context.scene
    base_c, cd = bpy.data.collections.new("TMP_BASE"), bpy.data.collections.new("TMP_D")
    for c_ in (base_c, cd):
        sc.collection.children.link(c_)
    target = bpy.data.objects.new("tmp_shell", tme); base_c.objects.link(target); target.hide_render = True
    M, mm = cfg["tor"]
    cutters = [
        ("tmp_seam1", RS, (1.0, 0.12, 0.0), (0, 0, 0)),                                   # couture centrale (entre les deux yeux)
        ("tmp_belt", math.sqrt(RS * RS - (BELT_Z) ** 2), (0, 0, 1), (0, 0, BELT_Z)),       # ceinture basse
        ("tmp_seam2", RS, (0.55, -0.35, 0.76), (0, 0, 0)),                                # couture diagonale
    ]
    for nm, major, normal, center in cutters:
        me_c = torus_mesh(nm, major, GROOVE_R, M, mm, normal, center, m_dark)
        o = bpy.data.objects.new(nm, me_c); cd.objects.link(o); o.hide_render = True
    md = target.modifiers.new("D", 'BOOLEAN')
    md.operation, md.operand_type, md.collection, md.solver = 'DIFFERENCE', 'COLLECTION', cd, 'EXACT'
    try:
        md.material_mode = 'TRANSFER'
    except Exception as e:
        print("material_mode indisponible :", e)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    me.name = f"B21_Shell_{v}"
    for c_ in (base_c, cd):
        for o in list(c_.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c_)
    for t_ in [t_ for t_ in bpy.data.meshes if t_.name.startswith("tmp_") and t_.users == 0]:
        bpy.data.meshes.remove(t_)
    # tons : rainures (materiau Dark deja transfere), panneau du bas, ceinture
    canon = [m_shell.name, m_shell2.name, m_dark.name]
    names = [m.name for m in me.materials]
    bm2 = bmesh.new(); bm2.from_mesh(me)
    idx = []
    for f in bm2.faces:
        src = names[f.material_index] if f.material_index < len(names) else m_shell.name
        c = f.calc_center_median()
        if src == m_dark.name or c.z < (BELT_Z - 0.03) * ZSQ:
            idx.append(2)
        elif c.z < -0.28 * ZSQ:
            idx.append(1)
        else:
            idx.append(0)
    for f, i in zip(bm2.faces, idx):
        f.material_index = i
    bm2.normal_update()
    for e in bm2.edges:
        try:
            if e.is_manifold and e.calc_face_angle() > math.radians(50):
                e.smooth = False
        except Exception:
            pass
    out = bpy.data.meshes.new(me.name + "_final")
    bm2.to_mesh(out); bm2.free()
    for nm in canon:
        out.materials.append(bpy.data.materials[nm])
    for p, i in zip(out.polygons, idx):
        p.material_index = i
        p.use_smooth = True
    bpy.data.meshes.remove(me)
    out.name = f"B21_Shell_{v}"
    return out

def eyes_meshes(v):
    cfg = R21[v]
    dark, glow, shine = bmesh.new(), bmesh.new(), bmesh.new()
    nL, nG = cfg["eye_n"], cfg["glass_n"]
    # OEIL GAUCHE (grand, cote +X = gauche vu de face)
    L = direction(52, -8)
    disc(dark, L, 0.80, 0.16, nL, r_in=0.60)                    # boitier
    disc(glow, L, 0.60, 0.12, nL, r_in=0.44)                    # anneau cyan
    disc(dark, L, 0.44, 0.10, nG)                               # verre sombre
    disc(shine, L, 0.11, 0.125, 10, offset=(-0.14, 0.15))       # reflet
    # OEIL DROIT (plus petit, cote -X, un peu plus haut)
    Rr = direction(128, 2)
    disc(dark, Rr, 0.66, 0.14, nL, r_in=0.50)                   # boitier
    disc(glow, Rr, 0.50, 0.10, nG)                              # disque cyan
    disc(shine, Rr, 0.20, 0.115, 12, offset=(0.10, 0.12))       # reflet
    # BANDE CYAN en arc au sommet, devant
    arc_strip(glow, 62, 118, 60, 0.15, 0.055, 14 if v == "PC" else 8)
    return (mesh_from(dark, f"B21_Dark_{v}", True), mesh_from(glow, f"B21_Glow_{v}", True), mesh_from(shine, f"B21_Shine_{v}", True))

# ---------------------------------------------------------------- nettoyage (uniquement B21_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B21_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B21_"):
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
m_shell = mat("DIAG_B21_Shell", "#EDF2F6", 0.35)
m_shell2 = mat("DIAG_B21_Shell2", "#D4DDE7", 0.35)
m_dark = mat("DIAG_B21_Dark", "#16203A", 0.45)
m_house = mat("DIAG_B21_House", "#1A2744", 0.4)
m_glow = mat("DIAG_B21_Glow_Neon", "#2FE6FF", 0.2, emit=3.0)
m_shine = mat("DIAG_B21_Shine_Neon", "#E0FCFF", 0.2, emit=3.0)
m_collar = mat("DIAG_B21_Collar", "#1E2A4A", 0.35)

report = []
for v, src_root, off in (("PC", base_root, Vector((8, 0, 0))), ("MOBILE", mob_root, Vector((8, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B21_Robot_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B21_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B21", "Robot", v
    root["default_explosion"], root["spark_color"] = "E10", "#FF9A2E"
    root["orientation"] = "les deux yeux regardent +Z Roblox ; pivoter en Y pour faire face a la camera"
    body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
    sh = shell_mesh(v, m_shell, m_shell2, m_dark)
    body.data = sh
    body.location = (0, 0, 1.455)
    set_obj_materials(collar, [m_collar])                      # grande collerette de la base, bleu nuit
    fme = ninja_fuse_mesh(f"B21_Fuse_{v}", *R21[v]["fuse"]); fme.materials.append(m_fuse); fme.materials.append(m_tip); fuse.data = fme
    d_me, g_me, s_me = eyes_meshes(v)
    d_me.materials.append(m_house); g_me.materials.append(m_glow); s_me.materials.append(m_shine)
    extras = [("BombSkin_Dark", d_me), ("BombSkin_Glow", g_me), ("BombSkin_Shine", s_me)]
    for nm, mesh in extras:
        ob = bpy.data.objects.new("B21_" + nm + ("_Mobile" if v == "MOBILE" else ""), mesh)
        col.objects.link(ob)
        ob.parent = details
        ob.location = body.location
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B21_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off
        set_obj_materials(sp, [mat("DIAG_B21_Spark", "#FF9A2E", 0.3, 1.5)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH') + sum(tris(m) for _, m in extras), tris(sh)))

bpy.context.view_layer.update()
import collections
for v, n_t, n_b in report:
    print(f"B21 {v:7s} total {n_t:5d} tris | coque {n_b:5d}")
for v, nm in (("PC", "B21_BombBody_Base"), ("MOBILE", "B21_BombBody_Base_Mobile")):
    me = bpy.data.objects[nm].data
    bm = bmesh.new(); bm.from_mesh(me)
    print(f"  {v}: materiaux {[m.name for m in me.materials]} | repartition {dict(sorted(collections.Counter(q.material_index for q in me.polygons).items()))} | bords ouverts {sum(1 for e in bm.edges if len(e.link_faces)==1)} | aretes>2 faces {sum(1 for e in bm.edges if len(e.link_faces)>2)}")
    bm.free()
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B21_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
