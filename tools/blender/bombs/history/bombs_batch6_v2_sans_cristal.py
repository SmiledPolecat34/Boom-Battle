"""
Boom Battle - Phase 4, lot 6 : B06 Glacee, B21 Robot, B24 Cristal.
Prerequis : bomb_base.py execute dans CE fichier. Definitions communes (mat, clone_tree, virole fine, meche lisse) reprises du script B16.
Camera du jeu : tangage 55 deg, cote +Z Roblox (= +Y Blender), lacet par pas de 90 deg. B21 a un AVANT (+Y) : a pivoter vers la camera.
- B06 : boule de glace FACETTEE (icosphere jitteree, ombrage plat, pied plat) en 3 tons selon l'orientation des facettes
        (BombBody_IceLight/Mid/Deep, materiau Roblox Ice) + 8 eclats de givre (BombSkin_Shards).
- B24 : cristal hexagonal violet (prisme a facettes irregulieres, sommet tronque pour la virole) en 3 tons (BombBody_Light/Mid/Deep)
        + grappe de 6 petits cristaux lumineux (BombSkin_Crystals, Neon).
- B21 : robot = sphere blanche + 8 panneaux bleus (BombSkin_Panels) + oeil a lunette (BombSkin_Dark / BombSkin_Glow Neon cyan) + 2 oreilles lumineuses.
Idempotent (ne touche qu'aux objets B06_*, B21_*, B24_*).
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

_B16 = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_b16_shuriken_debout.py"
exec(compile(open(_B16, encoding="utf-8").read().split("# ---------------------------------------------------------------- nettoyage (uniquement B16_*)")[0], "b16_defs", "exec"))

RS, ZSQ = 1.5, 0.97
V6 = {
    "PC":     dict(ice_sub=3, ice_sides=6, quartz_rings=6, eye_n=20, ear_n=14, panel_n=10, collar_seg=20, fuse=(10, 26)),
    "MOBILE": dict(ice_sub=2, ice_sides=4, quartz_rings=5, eye_n=14, ear_n=10, panel_n=8,  collar_seg=12, fuse=(8, 14)),
}
LIGHT = Vector((0.35, 0.45, 0.82)).normalized()

def mesh_from(bm, name, smooth, squash=False):
    if squash:
        bmesh.ops.scale(bm, vec=(1, 1, ZSQ), verts=bm.verts)
    for f in bm.faces:
        f.smooth = smooth
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me

def orient_from(bm, origin):
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median() - origin) < 0:
            f.normal_flip()

def tone(f, t_hi, t_mid):
    t = f.normal.dot(LIGHT)
    return 0 if t > t_hi else (1 if t > t_mid else 2)

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

# ---------------------------------------------------------------- B06 : glace
def ice_meshes(v):
    cfg = V6[v]
    rng = random.Random(6)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=cfg["ice_sub"], radius=RS)
    for vv in bm.verts:
        vv.co = vv.co * (1 + 0.07 * (rng.random() * 2 - 1))
        vv.co.z *= ZSQ
        if vv.co.z < -1.40:
            vv.co.z = -1.40                                      # pied plat
    bm.normal_update()
    for f in bm.faces:
        f.material_index = tone(f, 0.62, 0.12)
    top = max(vv.co.z for vv in bm.verts)
    body = mesh_from(bm, f"B06_Ice_{v}", smooth=False)
    sh = bmesh.new()
    sides = cfg["ice_sides"]
    for az, el, ln in ((10, 35, 0.50), (55, 48, 0.42), (100, 30, 0.55), (145, 42, 0.45), (190, 34, 0.52), (235, 50, 0.40), (280, 28, 0.46), (325, 44, 0.46)):
        d, u, w = frame(direction(az, el))
        base = d * (RS - 0.08)
        ring = [sh.verts.new(base + (u * math.cos(t) + w * math.sin(t)) * 0.26) for t in (math.tau * i / sides for i in range(sides))]
        tip = sh.verts.new(d * (RS + ln))
        for i in range(sides):
            sh.faces.new((ring[i], ring[(i + 1) % sides], tip))
    orient_from(sh, Vector((0, 0, 0)))
    shards = mesh_from(sh, f"B06_Shards_{v}", smooth=False, squash=True)
    return body, shards, top

# ---------------------------------------------------------------- B24 : cristal
def quartz_meshes(v):
    cfg = V6[v]
    rng = random.Random(24)
    zc = 1.40
    prof = ([(0.0, 0.95, 0), (0.20, 1.20, 0), (1.15, 1.23, 0), (1.95, 1.20, 0), (2.78, 0.42, 0)]       # prisme a parois droites + terminaison pyramidale
            if cfg["quartz_rings"] == 6 else [(0.0, 0.95, 0), (0.20, 1.20, 0), (1.95, 1.22, 0), (2.78, 0.42, 0)])
    sides = 6
    bm = bmesh.new()
    rows = []
    for z, r, tw in prof:
        row = []
        for k in range(sides):
            a = math.tau * k / sides + math.radians(tw)
            rr = r * (1 + 0.03 * (rng.random() * 2 - 1))
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z - zc)))
        rows.append(row)
    for i in range(len(rows) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]))
    bm.faces.new(rows[-1][::-1]); bm.faces.new(rows[0])
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    orient_from(bm, Vector((0, 0, 0)))
    for f in bm.faces:
        f.material_index = tone(f, 0.35, -0.15)
    body = mesh_from(bm, f"B24_Quartz_{v}", smooth=False)

    sh = bmesh.new()
    n_c = 6
    for k, (ln, rad, tilt) in enumerate(((1.15, 0.32, 30), (0.90, 0.28, 32), (1.20, 0.34, 28), (0.85, 0.26, 34), (1.05, 0.30, 30), (0.95, 0.27, 32))):
        az = math.radians(20 + k * 60)
        out = Vector((math.cos(az), math.sin(az), 0))
        base = out * 1.12 + Vector((0, 0, 0.25 - zc))
        axis = (out * math.sin(math.radians(tilt)) + Vector((0, 0, math.cos(math.radians(tilt))))).normalized()
        u = axis.cross(Vector((0, 0, 1))).normalized(); w = axis.cross(u)
        r0 = [sh.verts.new(base + (u * math.cos(t) + w * math.sin(t)) * rad) for t in (math.tau * i / sides for i in range(sides))]
        r1 = [sh.verts.new(base + axis * (0.6 * ln) + (u * math.cos(t) + w * math.sin(t)) * rad * 0.92) for t in (math.tau * i / sides for i in range(sides))]
        tip = sh.verts.new(base + axis * ln)
        new = []
        for i in range(sides):
            i2 = (i + 1) % sides
            new.append(sh.faces.new((r0[i], r0[i2], r1[i2], r1[i])))
            new.append(sh.faces.new((r1[i], r1[i2], tip)))
        sh.normal_update()
        for f in new:
            c = f.calc_center_median()
            p = base + axis * ((c - base).dot(axis))
            if f.normal.dot(c - p) < 0:
                f.normal_flip()
    crystals = mesh_from(sh, f"B24_Crystals_{v}", smooth=False)
    return body, crystals, zc

# ---------------------------------------------------------------- B21 : robot
def surface(d, u, w, x, y, h):
    return (d * RS + u * x + w * y).normalized() * (RS + h)

def disc(bm, d, r, h, n, r_in=None, sink=-0.03):
    """Disque (ou anneau si r_in) en relief sur la sphere, centre sur la direction d ; parois + dessus."""
    d, u, w = frame(d)
    ring = lambda rr, hh: [bm.verts.new(surface(d, u, w, rr * math.cos(t), rr * math.sin(t), hh)) for t in (math.tau * k / n for k in range(n))]
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
        apex = bm.verts.new(surface(d, u, w, 0, 0, h))
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

def panel(bm, d, size, n, rot_deg=0.0):
    d, u, w = frame(d)
    a = math.radians(rot_deg)
    def sq(t):
        c, s = math.cos(t), math.sin(t)
        return Vector((math.copysign(abs(c) ** 0.5, c), math.copysign(abs(s) ** 0.5, s)))      # carre aux coins arrondis (p = 4)
    pts = [sq(math.tau * k / n) for k in range(n)]
    rings = [(1.0, 0.02), (0.88, 0.07)]
    rv = []
    for sc_, hh in rings:
        row = []
        for p in pts:
            x, y = p.x * sc_ * size, p.y * sc_ * size
            x, y = x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
            row.append(bm.verts.new(surface(d, u, w, x, y, hh)))
        rv.append(row)
    apex = bm.verts.new(surface(d, u, w, 0, 0, 0.075))
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((rv[0][k], rv[0][k2], rv[1][k2], rv[1][k]))
        bm.faces.new((rv[1][k], rv[1][k2], apex))
    bm.normal_update()
    for f in list(bm.faces)[-2 * n:]:
        if f.normal.dot(d) < 0:
            f.normal_flip()

def robot_meshes(v):
    cfg = V6[v]
    pan, dark, glow = bmesh.new(), bmesh.new(), bmesh.new()
    for k in range(4):
        panel(pan, direction(45 + 90 * k, 40), 0.30, cfg["panel_n"], 0)
        panel(pan, direction(90 * k, -40), 0.30, cfg["panel_n"], 0)
    eye = direction(90, 8)
    disc(dark, eye, 0.70, 0.10, cfg["eye_n"], r_in=0.50)          # lunette
    disc(glow, eye, 0.50, 0.06, cfg["eye_n"], r_in=0.17)          # lentille cyan
    disc(dark, eye, 0.17, 0.10, cfg["eye_n"])                     # pupille
    for az in (0, 180):
        disc(dark, direction(az, 0), 0.38, 0.16, cfg["ear_n"])    # boitier d'oreille
        disc(glow, direction(az, 0), 0.22, 0.19, cfg["ear_n"])    # voyant
    return (mesh_from(pan, f"B21_Panels_{v}", True, True), mesh_from(dark, f"B21_Dark_{v}", True, True), mesh_from(glow, f"B21_Glow_{v}", True, True))

# ---------------------------------------------------------------- nettoyage du lot
PFX6 = ("B06_", "B21_")      # B24 Cristal : voir bombs_b24_cristal_v2.py (v1 dans history/)
for o in list(bpy.data.objects):
    if o.name.startswith(PFX6):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith(PFX6):
        bpy.data.collections.remove(c)
for n in ("DIAG_GridRow", "DIAG_Grid3x3"):
    o = bpy.data.objects.get(n)
    if o:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me.users == 0:
            bpy.data.meshes.remove(me)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

diag = bpy.data.collections["BOMB_BASE_DIAG"]
base_root, mob_root = bpy.data.objects["BombVisualRoot"], bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)
spark_src = bpy.data.objects["DIAG_SparkPreview"]
spark_loc = spark_src.location.copy()
m_fuse, m_tip = mat("DIAG_Fuse", "#C8742E", 0.7), mat("DIAG_FuseTip", "#2A1C12", 0.8)

BOMBS6 = [dict(id="B06", name="Glacee", folder="B06_Glacee", x=1, spark="#BFEFFF", expl="E06"),
          dict(id="B21", name="Robot", folder="B21_Robot", x=2, spark="#38E8FF", expl="E10")]  # B24 Cristal : voir bombs_b24_cristal_v2.py
report = []
for bb in BOMBS6:
    pfx = bb["id"] + "_"
    for v, src_root, off in (("PC", base_root, Vector((bb["x"] * CELL, 0, 0))), ("MOBILE", mob_root, Vector((bb["x"] * CELL, 2 * CELL, 0)))):
        col = bpy.data.collections.new(f"{bb['folder']}_{v}")
        bpy.context.scene.collection.children.link(col)
        made = clone_tree(src_root, pfx, off, col)
        root = made[src_root.name]
        root["bomb_id"], root["bomb_name"], root["variant"] = bb["id"], bb["name"], v
        root["default_explosion"], root["spark_color"] = bb["expl"], bb["spark"]
        body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
        neck = find_part(made, "BombNeck")
        sfx = "_Mobile" if v == "MOBILE" else ""
        fme = ninja_fuse_mesh(f"{pfx}Fuse_{v}", *V6[v]["fuse"]); fme.materials.append(m_fuse); fme.materials.append(m_tip); fuse.data = fme
        extras = []
        if bb["id"] == "B06":
            b_me, s_me, top = ice_meshes(v)
            for nm, hx in (("Light_Ice", "#CFF3FF"), ("Mid_Ice", "#6FCBFF"), ("Deep_Ice", "#2F8FE0")):
                b_me.materials.append(mat(f"DIAG_B06_{nm}", hx, 0.15))
            s_me.materials.append(mat("DIAG_B06_Shards_Ice", "#E4F9FF", 0.1))
            body.data = b_me; body.location = (0, 0, 1.40)
            extras = [("BombSkin_Shards", s_me, (0, 0, 1.40))]
            neck_z = 1.40 + top - 0.10
            cme = ninja_collar_mesh(f"{pfx}Collar_{v}", V6[v]["collar_seg"]); cme.materials.append(mat("DIAG_B06_Collar", "#6F8FA8", 0.4))
        elif bb["id"] == "B24":
            b_me, c_me, zc = quartz_meshes(v)
            for nm, hx in (("Light", "#D3B5FF"), ("Mid", "#9A5CF0"), ("Deep", "#6A33C4")):
                b_me.materials.append(mat(f"DIAG_B24_{nm}", hx, 0.2))
            c_me.materials.append(mat("DIAG_B24_Crystals_Neon", "#B58CFF", 0.2, emit=0.9))
            body.data = b_me; body.location = (0, 0, zc)
            extras = [("BombSkin_Crystals", c_me, (0, 0, zc))]
            neck_z = 2.78 - 0.10
            cme = ninja_collar_mesh(f"{pfx}Collar_{v}", V6[v]["collar_seg"]); cme.materials.append(mat("DIAG_B24_Collar", "#3B2470", 0.4))
        else:
            set_obj_materials(body, [mat("DIAG_B21_Body", "#E9EEF4", 0.3)])
            p_me, d_me, g_me = robot_meshes(v)
            p_me.materials.append(mat("DIAG_B21_Panels", "#2E7BE8", 0.3))
            d_me.materials.append(mat("DIAG_B21_Dark", "#2B313C", 0.4))
            g_me.materials.append(mat("DIAG_B21_Glow_Neon", "#38E8FF", 0.2, emit=3.0))
            extras = [("BombSkin_Panels", p_me, body.location), ("BombSkin_Dark", d_me, body.location), ("BombSkin_Glow", g_me, body.location)]
            neck_z = BASE_NECK_Z
            cme = ninja_collar_mesh(f"{pfx}Collar_{v}", V6[v]["collar_seg"]); cme.materials.append(mat("DIAG_B21_Collar", "#3A424F", 0.4))
        collar.data = cme
        neck.location.z = neck_z
        for nm, mesh, loc in extras:
            ob = bpy.data.objects.new(pfx + nm + sfx, mesh)
            col.objects.link(ob)
            ob.parent = details
            ob.location = loc
        if v == "PC":
            sp = spark_src.copy()
            sp.name = pfx + "DIAG_SparkPreview"
            diag.objects.link(sp)
            sp.location = spark_loc + off + Vector((0, 0, neck_z - BASE_NECK_Z))
            set_obj_materials(sp, [mat(f"DIAG_{bb['id']}_Spark", bb["spark"], 0.3, 1.2)])
        n_t = sum(tris(o.data) for o in made.values() if o.type == 'MESH') + sum(tris(m) for _, m, _ in extras)
        report.append((bb["id"], v, n_t))

bm = bmesh.new()
ma, mb = mat("DIAG_Cell_A", "#8c939e", 0.9), mat("DIAG_Cell_B", "#7a818c", 0.9)
for gx in range(0, 4):
    for gy in range(-1, 2):
        x0, y0 = gx * CELL - CELL / 2, gy * CELL - CELL / 2
        vv = [bm.verts.new((x0 + dx, y0 + dy, -0.002)) for dx, dy in ((0, 0), (CELL, 0), (CELL, CELL), (0, CELL))]
        bm.faces.new(vv).material_index = (gx + gy) % 2
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("DIAG_GridRow")
bm.to_mesh(me); bm.free()
me.materials.append(ma); me.materials.append(mb)
diag.objects.link(bpy.data.objects.new("DIAG_GridRow", me))

bpy.context.view_layer.update()
for r in report:
    print("%-4s %-7s %5d tris" % r)
for bb in BOMBS6:
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith(bb["id"] + "_") and not o.name.endswith("_Mobile") and "DIAG" not in o.name:
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {bb['id']} PC : largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
