"""
Boom Battle - B09 Cosmique : d'apres le SCHEMA de modelisation du proprietaire ("Bombe Cosmique").
Schema : sphere violet fonce brillante (verre sombre) ; VORTEX DE GALAXIE en spirale rose-magenta emissive au centre-avant ; nebuleuses, eclats ;
col violet ; meche en corde ; etincelle cosmique rose-blanc. (Etoiles scintillantes flottantes, auras : hors case.)
Meme exigence que B08 v3/v4 ("pas de simple dessin") : tout est CREUSE dans le volume, par DIFFERENCE BOOLEENNE EXACTE avec des solides :
  - NEBULEUSE : bassin peu profond a fond COURBE (calotte spherique, 0,17 d'epaisseur de coupe) sous le vortex = lueur violette qui remplit la zone ;
  - 3 BRAS SPIRALES (spirale logarithmique autour d'un centre, ~0,9 tour, largeur et profondeur decroissantes vers l'exterieur) en V : parois MAGENTA ;
  - CRATERE CENTRAL conique (coeur du vortex) : parois magenta, fond ROSE-BLANC ;
  - fond des bras plus etroit et plus profond = ROSE-BLANC (meme logique a deux niveaux que B08) ;
  - petit VORTEX au dos (meme construction, 65 %) pour la lisibilite sous les 4 lacets de la camera ;
  - ETOILES en creux (petites pointes blanches) semees sur la sphere (PC).
  Les materiaux des cutters sont transferes aux parois creusees : la lumiere est AU FOND des creux.
Pieces exportees : BombBody_Base en 3 pieces (Shell / SpiralGlow Neon magenta / SpiralCore Neon rose-blanc) ; BombCollar_Base (Metal violet, maillage de B01) ; meche ; bout.
Avant (grand vortex) = +Y Blender (+Z Roblox). Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B09_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_ROB = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b21_robot_v3_schema.py"
exec(compile(open(_ROB, encoding="utf-8").read().split("def shell_mesh(")[0], "robot_helpers", "exec"))

N09 = {
    "PC":     dict(seg=32, rings=16, arm_n=11, arms=3, basin=(26, 3), stars=8, collar_seg=20, fuse=(8, 22)),
    "MOBILE": dict(seg=24, rings=12, arm_n=7,  arms=2, basin=(14, 2), stars=0, collar_seg=12, fuse=(8, 14)),
}
TOP_ABOVE = 0.12
INNER_W, INNER_EXTRA = 0.42, 0.08
FRONT = (80.0, 2.0)                  # (azimut, elevation) du centre du grand vortex
BACK = (262.0, -12.0)                # petit vortex du dos

def solid_v(bm, pts, wfun, dfun):
    """Solide ferme en V le long du chemin ; wfun(u), dfun(u) = demi-largeur au-dessus de la surface et profondeur (u de 0 a 1)."""
    n = len(pts)
    Ls, Rs, Bs = [], [], []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        t = (b - a)
        t = (t - p * t.dot(p)).normalized()
        l = p.cross(t).normalized()
        u = i / (n - 1)
        wt, dep = wfun(u), dfun(u)
        Ls.append(bm.verts.new((p * RS + l * wt).normalized() * (RS + TOP_ABOVE)))
        Rs.append(bm.verts.new((p * RS - l * wt).normalized() * (RS + TOP_ABOVE)))
        Bs.append(bm.verts.new(p * (RS - dep)))
    fs = []
    for i in range(n - 1):
        fs.append(bm.faces.new((Ls[i], Ls[i + 1], Bs[i + 1], Bs[i])))
        fs.append(bm.faces.new((Rs[i], Bs[i], Bs[i + 1], Rs[i + 1])))
        fs.append(bm.faces.new((Ls[i], Rs[i], Rs[i + 1], Ls[i + 1])))
    fs.append(bm.faces.new((Ls[0], Bs[0], Rs[0])))
    fs.append(bm.faces.new((Ls[-1], Rs[-1], Bs[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    vol = 0.0
    for f in fs:
        vs = [v.co for v in f.verts]
        for j in range(1, len(vs) - 1):
            vol += vs[0].dot(vs[j].cross(vs[j + 1])) / 6.0
    if vol < 0:
        bmesh.ops.reverse_faces(bm, faces=fs)

def cone_pit(bm, c, r_top, r_bot, depth, segs):
    """Cone creuse oriente selon c : sommet (large) au-dessus de la surface, fond (etroit) a 'depth' sous la surface."""
    top_z, bot_z = TOP_ABOVE * 0.5, -depth
    height = top_z - bot_z
    mid = (RS + (top_z + bot_z) / 2.0)
    rot = Vector((0, 0, 1)).rotation_difference(c).to_matrix().to_4x4()
    mtx = Matrix.Translation(c * mid) @ rot
    r_top_eff = r_top * (height / (-bot_z + 1e-6)) if False else r_top
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_bot, radius2=r_top_eff, depth=height, matrix=mtx)

def cap_solid(bm, c, rho_deg, r_top, r_bot, segs=26, rings=3):
    """Calotte spherique fermee (centre c, rayon angulaire rho) entre les rayons r_bot et r_top : cutter de bassin a fond COURBE."""
    c = c.normalized()
    u = Vector((0, 0, 1)).cross(c)
    if u.length < 1e-4:
        u = Vector((1, 0, 0)).cross(c)
    u.normalize(); w = c.cross(u)
    def ring_dirs(k):
        rho = math.radians(rho_deg * k / rings)
        return [(c * math.cos(rho) + (u * math.cos(math.tau * j / segs) + w * math.sin(math.tau * j / segs)) * math.sin(rho)).normalized() for j in range(segs)]
    top = [[bm.verts.new(c * r_top)]] + [[bm.verts.new(d * r_top) for d in ring_dirs(k)] for k in range(1, rings + 1)]
    bot = [[bm.verts.new(c * r_bot)]] + [[bm.verts.new(d * r_bot) for d in ring_dirs(k)] for k in range(1, rings + 1)]
    fs = []
    for j in range(segs):
        j2 = (j + 1) % segs
        fs.append(bm.faces.new((top[0][0], top[1][j], top[1][j2])))
        fs.append(bm.faces.new((bot[0][0], bot[1][j2], bot[1][j])))
    for k in range(1, rings):
        for j in range(segs):
            j2 = (j + 1) % segs
            fs.append(bm.faces.new((top[k][j], top[k + 1][j], top[k + 1][j2], top[k][j2])))
            fs.append(bm.faces.new((bot[k][j], bot[k][j2], bot[k + 1][j2], bot[k + 1][j])))
    for j in range(segs):
        j2 = (j + 1) % segs
        fs.append(bm.faces.new((top[rings][j], top[rings][j2], bot[rings][j2], bot[rings][j])))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    vol = 0.0
    for f in fs:
        vs = [v.co for v in f.verts]
        for j in range(1, len(vs) - 1):
            vol += vs[0].dot(vs[j].cross(vs[j + 1])) / 6.0
    if vol < 0:
        bmesh.ops.reverse_faces(bm, faces=fs)

def spiral_pts(c, rho0, rho1, th0, turns, n):
    c = c.normalized()
    u = Vector((0, 0, 1)).cross(c)
    if u.length < 1e-4:
        u = Vector((1, 0, 0)).cross(c)
    u.normalize(); w = c.cross(u)
    pts = []
    for i in range(n):
        t = i / (n - 1)
        th = th0 + t * turns * math.tau
        rho = math.radians(rho0 * (rho1 / rho0) ** t)
        pts.append((c * math.cos(rho) + (u * math.cos(th) + w * math.sin(th)) * math.sin(rho)).normalized())
    return pts

def vortex(outer, inner, neb, az, el, scale, cfg, arms, basin):
    c = direction(az, el)
    for k in range(arms):
        pts = spiral_pts(c, 16.0 * scale, 60.0 * scale, k * math.tau / arms + 0.4, 0.9, cfg["arm_n"])
        wf = lambda u, s=scale: (0.035 + 0.14 * (1 - 0.65 * u)) * (0.6 + 0.4 * s)
        df = lambda u: 0.08 + 0.17 * (1 - 0.55 * u)
        solid_v(outer, pts, wf, df)
        wi = lambda u, s=scale: (0.014 + 0.14 * (1 - 0.65 * u) * INNER_W) * (0.6 + 0.4 * s)
        di = lambda u: 0.08 + 0.17 * (1 - 0.55 * u) + INNER_EXTRA
        solid_v(inner, pts, wi, di)
    cone_pit(outer, c, 0.36 * scale + 0.04, 0.14 * scale, 0.27, 14)          # cratere : parois magenta
    cone_pit(inner, c, 0.18 * scale + 0.02, 0.04 * scale, 0.35, 12)          # fond du cratere : rose-blanc
    if basin:
        cap_solid(neb, c, 38.0 * scale, RS + TOP_ABOVE, RS - 0.07, segs=cfg["basin"][0], rings=cfg["basin"][1])   # nebuleuse : bassin peu profond a fond courbe

def carved_body(v, m_body, m_glow, m_core, m_neb):
    cfg = N09[v]
    for o in [o for o in bpy.data.objects if o.name.startswith("tmp_")]:
        bpy.data.objects.remove(o, do_unlink=True)
    for c_ in [c_ for c_ in bpy.data.collections if c_.name.startswith("TMP_")]:
        bpy.data.collections.remove(c_)
    rng = random.Random(9)
    outer, inner, neb = bmesh.new(), bmesh.new(), bmesh.new()
    vortex(outer, inner, neb, FRONT[0], FRONT[1], 1.0, cfg, cfg["arms"], True)
    vortex(outer, inner, neb, BACK[0], BACK[1], 0.65, cfg, 2 if cfg["arms"] > 2 else 1, False)
    vortex_dirs = [direction(*FRONT), direction(*BACK)]
    placed = 0
    tries = 0
    while placed < cfg["stars"] and tries < 200:                  # etoiles en creux, loin des vortex
        tries += 1
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.8, 0.8))).normalized()
        if any(d.dot(vd) > math.cos(math.radians(62)) for vd in vortex_dirs):
            continue
        cone_pit(inner, d, 0.075, 0.0, 0.10, 5)
        placed += 1
    for b_ in (outer, inner, neb):
        bmesh.ops.scale(b_, vec=(1, 1, ZSQ), verts=b_.verts)
    sph = bmesh.new()
    bmesh.ops.create_uvsphere(sph, u_segments=cfg["seg"], v_segments=cfg["rings"], radius=RS)
    bmesh.ops.scale(sph, vec=(1, 1, ZSQ), verts=sph.verts)
    for f in sph.faces:
        f.smooth = True
    me_t = bpy.data.meshes.new("tmp_body"); sph.to_mesh(me_t); sph.free(); me_t.materials.append(m_body)
    me_o = bpy.data.meshes.new("tmp_outer"); outer.to_mesh(me_o); outer.free(); me_o.materials.append(m_glow)
    me_i = bpy.data.meshes.new("tmp_inner"); inner.to_mesh(me_i); inner.free(); me_i.materials.append(m_core)
    me_n = bpy.data.meshes.new("tmp_neb"); neb.to_mesh(me_n); neb.free(); me_n.materials.append(m_neb)
    sc = bpy.context.scene
    base_c, cd = bpy.data.collections.new("TMP_BASE"), bpy.data.collections.new("TMP_D")
    for c_ in (base_c, cd):
        sc.collection.children.link(c_)
    target = bpy.data.objects.new("tmp_body", me_t); base_c.objects.link(target); target.hide_render = True
    for nm, me_c in (("tmp_outer", me_o), ("tmp_inner", me_i), ("tmp_neb", me_n)):
        o = bpy.data.objects.new(nm, me_c); cd.objects.link(o); o.hide_render = True
    md = target.modifiers.new("D", 'BOOLEAN')
    md.operation, md.operand_type, md.collection, md.solver = 'DIFFERENCE', 'COLLECTION', cd, 'EXACT'
    try:
        md.use_self = True
    except Exception as e:
        print("use_self indisponible :", e)
    try:
        md.material_mode = 'TRANSFER'
    except Exception as e:
        print("material_mode indisponible :", e)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    me.name = f"B09_Carved_{v}"
    for c_ in (base_c, cd):
        for o in list(c_.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c_)
    for t_ in [t_ for t_ in bpy.data.meshes if t_.name.startswith("tmp_") and t_.users == 0]:
        bpy.data.meshes.remove(t_)
    canon = [m_body.name, m_glow.name, m_core.name, m_neb.name]
    names = [m.name for m in me.materials]
    idx = [canon.index(names[p.material_index]) if p.material_index < len(names) and names[p.material_index] in canon else 0 for p in me.polygons]
    bm2 = bmesh.new(); bm2.from_mesh(me)
    for e in bm2.edges:
        try:
            if e.is_manifold and e.calc_face_angle() > math.radians(35):
                e.smooth = False
        except Exception:
            pass
    out = bpy.data.meshes.new(me.name + "_final")
    bm2.to_mesh(out); bm2.free()
    for m_ in (m_body, m_glow, m_core, m_neb):
        out.materials.append(m_)
    for p, i in zip(out.polygons, idx):
        p.material_index = i
        p.use_smooth = (i == 0)
    bpy.data.meshes.remove(me)
    out.name = f"B09_Carved_{v}"
    return out, placed

# ---------------------------------------------------------------- nettoyage (uniquement B09_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B09_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B09_"):
        bpy.data.collections.remove(c)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

diag = bpy.data.collections["BOMB_BASE_DIAG"]
base_root, mob_root = bpy.data.objects["BombVisualRoot"], bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)
spark_src = bpy.data.objects["DIAG_SparkPreview"]
spark_loc = spark_src.location.copy()
m_rope, m_tip = mat("DIAG_B09_Rope", "#C79A5A", 0.7), mat("DIAG_FuseTip", "#2A1C12", 0.8)
m_body = mat("DIAG_B09_Shell", "#2B1466", 0.15)
m_glow = mat("DIAG_B09_SpiralGlow_Neon", "#E52FD1", 0.3, emit=4.0)
m_core = mat("DIAG_B09_SpiralCore_Neon", "#FFC2F7", 0.3, emit=5.0)
m_neb = mat("DIAG_B09_Nebula_Neon", "#6A2BD6", 0.3, emit=2.5)
m_collar = mat("DIAG_B09_Collar_Metal", "#6E44C0", 0.35, metal=0.5)

report = []
for v, src_root, off in (("PC", base_root, Vector((12, 0, 0))), ("MOBILE", mob_root, Vector((12, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B09_Cosmique_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B09_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B09", "Cosmique", v
    root["default_explosion"], root["spark_color"] = "E09", "#FF7AF0"
    root["orientation"] = "grand vortex = +Z Roblox ; petit vortex au dos ; pivoter en Y pour faire face a la camera"
    body, collar, fuse = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"))
    me_body, n_stars = carved_body(v, m_body, m_glow, m_core, m_neb)
    body.data = me_body
    set_obj_materials(collar, [m_collar])                      # col = BombCollar_Base de B01, violet
    fme = ninja_fuse_mesh(f"B09_Fuse_{v}", *N09[v]["fuse"]); fme.materials.append(m_rope); fme.materials.append(m_tip); fuse.data = fme
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B09_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off
        set_obj_materials(sp, [mat("DIAG_B09_Spark", "#FF7AF0", 0.3, 3.0)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH'), tris(me_body), n_stars))

bpy.context.view_layer.update()
import collections
for v, n_t, n_b, ns in report:
    print(f"B09 {v:7s} total {n_t:5d} tris | corps creuse {n_b:5d} | etoiles {ns}")
for v, nm in (("PC", "B09_BombBody_Base"), ("MOBILE", "B09_BombBody_Base_Mobile")):
    me = bpy.data.objects[nm].data
    bm = bmesh.new(); bm.from_mesh(me)
    print(f"  {v}: materiaux {[m.name for m in me.materials]} | repartition {dict(sorted(collections.Counter(q.material_index for q in me.polygons).items()))} | bords ouverts {sum(1 for e in bm.edges if len(e.link_faces)==1)} | aretes>2 faces {sum(1 for e in bm.edges if len(e.link_faces)>2)}")
    bm.free()
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B09_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w_ = o.matrix_world @ vv.co
                xs.append(w_.x); ys.append(w_.y); zs.append(w_.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
