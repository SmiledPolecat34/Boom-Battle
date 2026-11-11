"""
Boom Battle - B08 Electrique v3 : FISSURES CREUSEES (vraie profondeur, plus de "dessin" pose en surface).
(v1 = 13 zigzags en rubans traces a la main ; v2 = reseau ramifie en rubans Neon poses sur la sphere ; conservees dans history/)

Schema du proprietaire ("Bombe Electrique") : sphere violet-noir tres brillante ; fissures d'energie bleu vif en eclairs ramifies ; col metallique gris ;
meche en corde ; etincelle de decharge bleu-blanc. (Aura, decharges detachees : hors case.)
Construction :
  - Les eclairs (troncs en zigzag + branches, generes de facon procedurale, repartis a 360 deg, plus denses a l'avant) sont CREUSES dans la sphere
    par DIFFERENCE BOOLEENNE EXACTE avec des solides en V (section triangulaire : larges en haut, pointus au fond ; largeur/profondeur variables,
    pointes fines aux extremites).
  - DEUX NIVEAUX : solide externe (large, peu profond) = parois BLEU electrique ; solide interne (etroit, plus profond) = FOND BLANC-CYAN.
    Les matériaux des cutters sont transferes aux parois creusees : l'energie brille au FOND de la fissure (parois obliques visibles de cote).
  - Aretes vives (angle > 35 deg) sur les bords des fissures ; reste de la sphere lisse (brillante).
  - COL = BombCollar_Base de B01 (maillage partage), gris acier.
Pieces exportees : BombBody_Base en 3 pieces (Shell violet-noir / CrackGlow Neon bleu / CrackCore Neon blanc-cyan) ; BombCollar_Base (Metal) ; meche ; bout.
Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B08_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_ROB = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b21_robot_v3_schema.py"
exec(compile(open(_ROB, encoding="utf-8").read().split("def shell_mesh(")[0], "robot_helpers", "exec"))

N08 = {
    "PC":     dict(extra=11, branches=4, seg=28, rings=14, collar_seg=20, fuse=(8, 22)),
    "MOBILE": dict(extra=6,  branches=0, seg=24, rings=12, collar_seg=12, fuse=(8, 14)),
}
DEPTH, TOP_ABOVE = 0.20, 0.12              # profondeur du V externe sous la surface ; hauteur du haut du cutter au-dessus
INNER_EXTRA, INNER_W = 0.10, 0.42          # le fond blanc descend plus bas (+0.10) et mesure 42 % de la largeur externe
# 2 ECLAIRS FIXES a l'avant (azimut de depart, elevation de depart, cap [0 = vers +azimut, 90 = vers le haut], nb de pas, pas en degres, demi-largeur max du haut du cutter)
# avant = azimut 90 ; vu de face, la gauche = azimut < 90
FIXED = [
    (26, -42, 6, 7, 20.0, 0.15),       # eclair principal : bas du devant, de gauche a droite
    (76, -34, 88, 5, 15.0, 0.14),      # tronc vertical qui monte depuis l'eclair principal
]
MIN_SEP = 34.0                         # separation angulaire mini (deg) entre les points de depart : repartition homogene

def angdist(a, b):
    return math.degrees(math.acos(max(-1.0, min(1.0, a.dot(b)))))

def make_trunks(n_extra, rng):
    """Troncs supplementaires repartis sur TOUTE la sphere : candidats en spirale de Fibonacci, filtres par distance mini."""
    golden = math.pi * (3 - math.sqrt(5))
    chosen = [direction(f[0], f[1]) for f in FIXED]
    out = []
    n_cand = 40
    for j in range(n_cand):
        i = (j * 17) % n_cand                              # ordre melange (17 premier avec 40) : couvre le haut ET le bas
        if len(out) >= n_extra:
            break
        z = 1 - 2 * (i + 0.5) / n_cand
        el = math.degrees(math.asin(z))
        if abs(el) > 64:                                   # pas sous le col ni sous la bombe
            continue
        az = math.degrees(i * golden) % 360.0
        d = direction(az, el)
        if any(angdist(d, c) < MIN_SEP for c in chosen):
            continue
        chosen.append(d)
        out.append((az, el, rng.uniform(-90, 90), rng.choice((3, 3, 4, 4)), rng.uniform(13.0, 16.0), rng.uniform(0.115, 0.145)))
    return out

def jag_path(az, el, heading, steps, step, rng):
    pts, sign = [], 1.0
    for i in range(steps + 1):
        pts.append((az, el))
        h = math.radians(heading + sign * rng.uniform(14, 28))
        sign = -sign
        az += step * math.cos(h) / max(math.cos(math.radians(el)), 0.35)
        el = max(-78.0, min(78.0, el + step * math.sin(h)))
    return pts

def build_paths(cfg, rng):
    out = []
    for az, el, hd, st, sp, w in FIXED + make_trunks(cfg["extra"], rng):
        trunk = jag_path(az, el, hd, st, sp, rng)
        out.append((trunk, w))
        if len(out) // 2 < cfg["branches"] and cfg["branches"]:
            k = rng.randint(2, max(2, len(trunk) - 3))
            ba, be = trunk[k]
            out.append((jag_path(ba, be, hd + rng.choice((-1, 1)) * rng.uniform(42, 70), 4, sp * 0.8, rng), w * 0.62))
    return out

def v_cutter(bm, pts, wt_max, depth, wt_min=0.035):
    """Solide ferme en V le long du chemin : haut (2 sommets au-dessus de la surface) + fond (1 sommet sous la surface)."""
    n = len(pts)
    Ls, Rs, Bs = [], [], []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        t = (b - a)
        t = (t - p * t.dot(p)).normalized()
        l = p.cross(t).normalized()
        k = math.sin(math.pi * i / (n - 1)) ** 0.5
        wt = wt_min + (wt_max - wt_min) * k
        dep = depth * (0.45 + 0.55 * k)
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
    # orientation globale : les normales doivent pointer hors du solide (volume signe positif)
    vol = 0.0
    for f in fs:
        vs = [v.co for v in f.verts]
        for j in range(1, len(vs) - 1):
            vol += vs[0].dot(vs[j].cross(vs[j + 1])) / 6.0
    if vol < 0:
        bmesh.ops.reverse_faces(bm, faces=fs)

def carved_body(v, m_body, m_glow, m_core):
    cfg = N08[v]
    for o in [o for o in bpy.data.objects if o.name.startswith("tmp_")]:
        bpy.data.objects.remove(o, do_unlink=True)
    for c_ in [c_ for c_ in bpy.data.collections if c_.name.startswith("TMP_")]:
        bpy.data.collections.remove(c_)
    rng = random.Random(81)
    paths = build_paths(cfg, rng)
    outer, inner = bmesh.new(), bmesh.new()
    for pts_deg, wt in paths:
        pts = [direction(az, el) for az, el in pts_deg]
        v_cutter(outer, pts, wt, DEPTH)
        v_cutter(inner, pts, wt * INNER_W, DEPTH + INNER_EXTRA, wt_min=0.012)
    for b_ in (outer, inner):
        bmesh.ops.scale(b_, vec=(1, 1, ZSQ), verts=b_.verts)
    sph = bmesh.new()
    bmesh.ops.create_uvsphere(sph, u_segments=cfg["seg"], v_segments=cfg["rings"], radius=RS)
    bmesh.ops.scale(sph, vec=(1, 1, ZSQ), verts=sph.verts)
    for f in sph.faces:
        f.smooth = True
    me_t = bpy.data.meshes.new("tmp_body"); sph.to_mesh(me_t); sph.free(); me_t.materials.append(m_body)
    me_o = bpy.data.meshes.new("tmp_outer"); outer.to_mesh(me_o); outer.free(); me_o.materials.append(m_glow)
    me_i = bpy.data.meshes.new("tmp_inner"); inner.to_mesh(me_i); inner.free(); me_i.materials.append(m_core)
    sc = bpy.context.scene
    base_c, cd = bpy.data.collections.new("TMP_BASE"), bpy.data.collections.new("TMP_D")
    for c_ in (base_c, cd):
        sc.collection.children.link(c_)
    target = bpy.data.objects.new("tmp_body", me_t); base_c.objects.link(target); target.hide_render = True
    for nm, me_c in (("tmp_outer", me_o), ("tmp_inner", me_i)):
        o = bpy.data.objects.new(nm, me_c); cd.objects.link(o); o.hide_render = True
    md = target.modifiers.new("D", 'BOOLEAN')
    md.operation, md.operand_type, md.collection, md.solver = 'DIFFERENCE', 'COLLECTION', cd, 'EXACT'
    try:
        md.use_self = True                          # les cutters se recouvrent aux jonctions
    except Exception as e:
        print("use_self indisponible :", e)
    try:
        md.material_mode = 'TRANSFER'
    except Exception as e:
        print("material_mode indisponible :", e)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    me.name = f"B08_Carved_{v}"
    for c_ in (base_c, cd):
        for o in list(c_.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c_)
    for t_ in [t_ for t_ in bpy.data.meshes if t_.name.startswith("tmp_") and t_.users == 0]:
        bpy.data.meshes.remove(t_)
    canon = [m_body.name, m_glow.name, m_core.name]
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
    for m_ in (m_body, m_glow, m_core):
        out.materials.append(m_)
    for p, i in zip(out.polygons, idx):
        p.material_index = i
        p.use_smooth = (i == 0)
    bpy.data.meshes.remove(me)
    out.name = f"B08_Carved_{v}"
    return out, len(paths)

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
m_body = mat("DIAG_B08_Shell", "#241A4D", 0.18)
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
    body, collar, fuse = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"))
    me_body, n_paths = carved_body(v, m_body, m_glow, m_core)
    body.data = me_body
    set_obj_materials(collar, [m_collar])                      # col = BombCollar_Base de B01, gris acier
    fme = ninja_fuse_mesh(f"B08_Fuse_{v}", *N08[v]["fuse"]); fme.materials.append(m_rope); fme.materials.append(m_tip); fuse.data = fme
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B08_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off
        set_obj_materials(sp, [mat("DIAG_B08_Spark", "#9FE8FF", 0.3, 3.0)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH'), tris(me_body), n_paths))

bpy.context.view_layer.update()
import collections
for v, n_t, n_b, n_p in report:
    print(f"B08 {v:7s} total {n_t:5d} tris | corps creuse {n_b:5d} | {n_p} fissures")
for v, nm in (("PC", "B08_BombBody_Base"), ("MOBILE", "B08_BombBody_Base_Mobile")):
    me = bpy.data.objects[nm].data
    bm = bmesh.new(); bm.from_mesh(me)
    print(f"  {v}: materiaux {[m.name for m in me.materials]} | repartition {dict(sorted(collections.Counter(q.material_index for q in me.polygons).items()))} | bords ouverts {sum(1 for e in bm.edges if len(e.link_faces)==1)} | aretes>2 faces {sum(1 for e in bm.edges if len(e.link_faces)>2)}")
    bm.free()
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
