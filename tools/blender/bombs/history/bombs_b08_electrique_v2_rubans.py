"""
Boom Battle - B08 Electrique : d'apres le SCHEMA de modelisation du proprietaire ("Bombe Electrique").
Schema : sphere violet-noir tres brillante ; FISSURES d'energie bleu vif en ECLAIRS (zigzags ramifies, emissifs), surtout a l'avant ;
col METALLIQUE gris ; meche en corde ; etincelle de decharge bleu-blanc. (Aura violette, decharges et eclairs autour : hors case, non modelises.)
Construction (v2 : reseau d'eclairs RAMIFIE genere de facon procedurale ; v1 = 13 zigzags traces a la main, voir history/) :
  - CORPS : sphere de la base (maillage partage avec B01), teinte violet-noir.
  - 12 FISSURES = rubans en zigzag poses sur la sphere (chemins en azimut/elevation, interpoles sur grand cercle), largeur variable (pointes fines),
    en 2 couches : HALO bleu electrique (Neon) + COEUR blanc-cyan (Neon), plus etroit et plus haut. Branches comprises ; fissures aussi au dos.
  - COL = BombCollar_Base de B01 (maillage partage), gris metal.
Pieces exportees : BombBody_Base (violet-noir) ; BombSkin_CrackGlow (Neon bleu) ; BombSkin_CrackCore (Neon blanc-cyan) ; BombCollar_Base (Metal) ; meche ; bout.
Les fissures sont reparties a 360 deg (plus denses a l'avant = +Y). Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B08_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_ROB = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b21_robot_v3_schema.py"
exec(compile(open(_ROB, encoding="utf-8").read().split("def shell_mesh(")[0], "robot_helpers", "exec"))

N08 = {
    "PC":     dict(trunks=10, branches=True,  aura=True,  subdiv=1, collar_seg=20, fuse=(8, 22)),
    "MOBILE": dict(trunks=7,  branches=False, aura=True,  subdiv=1, collar_seg=12, fuse=(8, 14)),
}
# TRONCS : (azimut de depart, elevation de depart, cap en degres [0 = vers +azimut, 90 = vers le haut], nb de pas, pas en degres, largeur max)
# avant = azimut 90 ; vu de face, la gauche = azimut < 90
TRUNKS = [
    (26, -42, 6, 10, 14.5, 0.15),      # eclair principal : bas du devant, de gauche a droite
    (76, -34, 88, 7, 12.0, 0.13),     # tronc vertical qui monte depuis l'eclair principal
    (138, -16, 78, 6, 12.5, 0.14),    # amas de droite
    (52, 36, -68, 4, 11.5, 0.11),     # haut gauche, descend
    (198, -30, 42, 6, 13.0, 0.13),    # dos
    (252, -40, 80, 5, 13.0, 0.13),
    (292, 24, -62, 5, 12.0, 0.12),
    (322, -34, 70, 5, 12.0, 0.12),
    (10, -14, 80, 4, 12.0, 0.11),
    (178, 32, -80, 4, 11.0, 0.10),
]

def jag_path(az, el, heading, steps, step, rng):
    """Zigzag : le cap alterne de part et d'autre du cap de base (aspect eclair)."""
    pts = []
    sign = 1.0
    for i in range(steps + 1):
        pts.append((az, el))
        h = math.radians(heading + sign * rng.uniform(16, 32))
        sign = -sign
        d_el = step * math.sin(h)
        d_az = step * math.cos(h) / max(math.cos(math.radians(el)), 0.35)
        az += d_az
        el = max(-78.0, min(78.0, el + d_el))
    return pts

def build_paths(cfg, rng):
    out = []
    for az, el, hd, st, sp, w in TRUNKS[: cfg["trunks"]]:
        trunk = jag_path(az, el, hd, st, sp, rng)
        out.append((trunk, w))
        if cfg["branches"]:
            for _ in range(1):                         # 1 branche par tronc, partant d'un sommet interieur
                k = rng.randint(2, max(2, len(trunk) - 3))
                ba, be = trunk[k]
                bh = hd + rng.choice((-1, 1)) * rng.uniform(42, 72)
                out.append((jag_path(ba, be, bh, 4, sp * 0.8, rng), w * 0.6))
    return out

def densify(pts, k):
    out = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        for s in range(k):
            out.append((a + (b - a) * (s / k)).normalized())
    out.append(pts[-1])
    return out

def ribbon(bm, pts, wmax, h, wmin=0.03):
    n = len(pts)
    left, right = [], []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        t = (b - a)
        t = (t - p * t.dot(p)).normalized()
        l = p.cross(t).normalized()
        u = i / (n - 1)
        w = wmin + (wmax - wmin) * (math.sin(math.pi * u) ** 0.5)
        left.append(bm.verts.new((p * RS + l * (w / 2)).normalized() * (RS + h)))
        right.append(bm.verts.new((p * RS - l * (w / 2)).normalized() * (RS + h)))
    new = []
    for i in range(n - 1):
        try:
            new.append(bm.faces.new((left[i], left[i + 1], right[i + 1], right[i])))
        except ValueError:
            pass
    bm.normal_update()
    for f in new:
        if f.normal.dot(f.calc_center_median()) < 0:
            f.normal_flip()

def cracks_meshes(v):
    cfg = N08[v]
    rng = random.Random(81)
    aura, glow, core = bmesh.new(), bmesh.new(), bmesh.new()
    for pts_deg, wmax in build_paths(cfg, rng):
        pts = densify([direction(az, el) for az, el in pts_deg], cfg["subdiv"])
        if cfg["aura"]:
            ribbon(aura, pts, wmax * 3.0, 0.012, wmin=0.10)
        ribbon(glow, pts, wmax * 2.0, 0.025, wmin=0.06)
        ribbon(core, pts, wmax * 2.0 * 0.28, 0.040, wmin=0.02)
    for b_ in (aura, glow, core):
        for f in b_.faces:
            f.smooth = True
    return (mesh_from(aura, f"B08_Aura_{v}", True) if cfg["aura"] else None), mesh_from(glow, f"B08_Glow_{v}", True), mesh_from(core, f"B08_Core_{v}", True)

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
m_body = mat("DIAG_B08_Body", "#241A4D", 0.18)
m_aura = mat("DIAG_B08_CrackAura_Neon", "#4A36C8", 0.3, emit=2.0)
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
    body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
    set_obj_materials(body, [m_body])                          # sphere de la base (maillage partage), violet-noir
    set_obj_materials(collar, [m_collar])                      # col = BombCollar_Base de B01, gris metal
    fme = ninja_fuse_mesh(f"B08_Fuse_{v}", *N08[v]["fuse"]); fme.materials.append(m_rope); fme.materials.append(m_tip); fuse.data = fme
    me_a, me_g, me_c = cracks_meshes(v)
    me_g.materials.append(m_glow); me_c.materials.append(m_core)
    extras = [("BombSkin_CrackGlow", me_g), ("BombSkin_CrackCore", me_c)]
    if me_a is not None:
        me_a.materials.append(m_aura)
        extras.insert(0, ("BombSkin_CrackAura", me_a))
    for nm, mesh in extras:
        ob = bpy.data.objects.new("B08_" + nm + ("_Mobile" if v == "MOBILE" else ""), mesh)
        col.objects.link(ob)
        ob.parent = details
        ob.location = body.location
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B08_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off
        set_obj_materials(sp, [mat("DIAG_B08_Spark", "#9FE8FF", 0.3, 3.0)])
    report.append((v, sum(tris(o.data) for o in made.values() if o.type == 'MESH') + sum(tris(m) for _, m in extras), tris(me_g), tris(me_c)))

bpy.context.view_layer.update()
for v, n_t, n_g, n_c in report:
    print(f"B08 {v:7s} total {n_t:5d} tris | halo {n_g:4d} | coeur {n_c:4d}")
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
