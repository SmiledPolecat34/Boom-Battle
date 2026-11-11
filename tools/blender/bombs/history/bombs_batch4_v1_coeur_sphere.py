"""
Boom Battle - Phase 4, lot 4 : B17 Coeur, B18 Etoiles, B19 Militaire, B20 Tonneau.
Prerequis : bomb_base.py execute dans CE fichier. Collerette + meche = maillages de B01 (partages), recolores.
Camera du jeu = tangage 55 deg, cote +Z Roblox (+Y Blender), lacet par pas de 90 deg : les motifs sont repartis sur les
4 azimuts (symetrie 90 deg) pour rester lisibles quel que soit l'angle.
- B17 : 4 coeurs en relief (BombSkin_Hearts) a 28 deg d'elevation, aux azimuts 0/90/180/270.
- B18 : 8 etoiles en relief (BombSkin_Stars, metal dore), tailles et rotations variees.
- B19 : camouflage = taches organiques en relief sur 2 couches (BombSkin_CamoDark, BombSkin_CamoLight) ; pas de texture.
- B20 : NOUVELLE SILHOUETTE : tonneau a douves (16 douves, rainures), couvercle, cercles metalliques + rivets (BombSkin_Hoops).
Pose : 1 case de 4 studs par bombe (B01 de reference a x=0, B17..B20 a x=4..16) ; variantes mobile a y=+8. Idempotent.
"""
import bpy, bmesh, math, random
from mathutils import Vector

CELL, R, Z_SQUASH = 4.0, 1.5, 0.97
BODY_H = 2 * R * Z_SQUASH                       # 2,91 : hauteur du corps de la base
VAR = {
    "PC":     dict(heart_n=24, heart_rings=[(1.0, 0.02), (0.74, 0.07), (0.44, 0.11)], blob_n=12, staves=16, rivets=12, rivet_sides=5),
    "MOBILE": dict(heart_n=14, heart_rings=[(1.0, 0.02), (0.62, 0.11)], blob_n=8,  staves=12, rivets=8,  rivet_sides=4),
}

def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def mat(name, hexcol, rough=0.4, emit=0.0, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        if not m.node_tree:
            m.use_nodes = True
    except Exception:
        pass
    rgb = srgb(hexcol)
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*rgb, 1)
    return m

def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)

def orient_from_origin(bm):
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median()) < 0:
            f.normal_flip()

def to_mesh(bm, name, smooth=True, squash=False):
    if squash:
        bmesh.ops.scale(bm, vec=(1, 1, Z_SQUASH), verts=bm.verts)
    for f in bm.faces:
        f.smooth = smooth
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me

# ---------------------------------------------------------------- motifs poses sur la sphere
def emboss(bm, d, outline, size, rot, rings, center_h):
    """Motif en relief : contour (liste de Vector2 ~ rayon 1) projete sur la sphere autour de la direction d ;
    anneaux = (echelle, hauteur) du bord vers le centre ; sommet central a center_h."""
    d = d.normalized()
    u = Vector((0, 0, 1)).cross(d).normalized(); w = d.cross(u)
    c, s_ = math.cos(rot), math.sin(rot)
    def P(pt, sc, h):
        x, y = pt.x * sc * size, pt.y * sc * size
        x, y = x * c - y * s_, x * s_ + y * c
        return (d * R + u * x + w * y).normalized() * (R + h)
    rv = [[bm.verts.new(P(pt, sc, h)) for pt in outline] for sc, h in rings]
    apex = bm.verts.new(d * (R + center_h))
    n = len(outline)
    for g in range(len(rv) - 1):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((rv[g][i], rv[g][j], rv[g + 1][j], rv[g + 1][i]))
    for i in range(n):
        bm.faces.new((rv[-1][i], rv[-1][(i + 1) % n], apex))

def direction(az_deg, el_deg):
    a, e = math.radians(az_deg), math.radians(el_deg)
    return Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))

def heart_outline(n):
    pts = []
    for k in range(n):
        t = math.tau * k / n
        pts.append(Vector((16 * math.sin(t) ** 3,
                           13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))))
    xs, ys = [p.x for p in pts], [p.y for p in pts]
    sc = 1.0 / (max(xs) - min(xs)); cy = (max(ys) + min(ys)) / 2
    return [Vector((p.x * sc, (p.y - cy) * sc)) for p in pts]

def star_outline():
    pts = []
    for k in range(10):
        r = 1.0 if k % 2 == 0 else 0.46
        a = math.pi / 2 + k * math.pi / 5
        pts.append(Vector((r * math.cos(a), r * math.sin(a))))
    return pts

def blob_outline(n, rng):
    ph = [rng.random() * math.tau for _ in range(3)]
    return [Vector((math.cos(t), math.sin(t))) * (1 + 0.30 * math.sin(2 * t + ph[0]) + 0.20 * math.sin(3 * t + ph[1]) + 0.12 * math.sin(5 * t + ph[2]))
            for t in (math.tau * k / n for k in range(n))]

def hearts_mesh(name, v):
    bm = bmesh.new()
    out = heart_outline(VAR[v]["heart_n"])
    for az in (0, 90, 180, 270):
        emboss(bm, direction(az, 28), out, 1.05, 0.0, VAR[v]["heart_rings"], 0.135)
    orient_from_origin(bm)
    return to_mesh(bm, name, smooth=True, squash=True)

STARS = [(90, 30, 0.95, 8), (20, 45, 0.70, -10), (160, 45, 0.72, 15), (225, 25, 0.90, 0),
         (310, 35, 0.80, -20), (350, 5, 0.85, 12), (125, 0, 0.78, 22), (255, -12, 0.70, -5)]   # (azimut, elevation, diametre, rotation)

def stars_mesh(name, v):
    bm = bmesh.new()
    out = star_outline()
    for az, el, dia, rot in STARS:
        emboss(bm, direction(az, el), out, dia / 2, math.radians(rot), [(1.0, 0.02), (0.50, 0.10)], 0.12)
    orient_from_origin(bm)
    return to_mesh(bm, name, smooth=False, squash=True)

def camo_meshes(v):
    rng = random.Random(19)
    dark, light = bmesh.new(), bmesh.new()
    N, golden = 36, math.pi * (3 - math.sqrt(5))
    n = VAR[v]["blob_n"]
    for i in range(N):
        z = 1 - 2 * (i + 0.5) / N
        if not (-0.30 <= z <= 0.80):                    # ni sous la collerette ni sous la bombe
            continue
        rr = math.sqrt(1 - z * z)
        d = Vector((rr * math.cos(i * golden), rr * math.sin(i * golden), z))
        out = blob_outline(n, rng)
        if i % 3 != 0:
            emboss(dark, d, out, 0.36 + 0.10 * rng.random(), rng.random() * math.tau, [(1.0, 0.012)], 0.020)
        else:
            emboss(light, d, out, 0.32 + 0.08 * rng.random(), rng.random() * math.tau, [(1.0, 0.028)], 0.034)
    for bm in (dark, light):
        orient_from_origin(bm)
    return to_mesh(dark, f"B19_CamoDark_{v}", smooth=False, squash=True), to_mesh(light, f"B19_CamoLight_{v}", smooth=False, squash=True)

# ---------------------------------------------------------------- B20 : tonneau
def barrel_meshes(v):
    S = VAR[v]["staves"]; segs = 2 * S
    H, Rm, Re, GD = BODY_H, 1.50, 1.22, 0.055
    half = H / 2
    rad = lambda z: Re + (Rm - Re) * (1 - (2 * z / H - 1) ** 2)
    zs = [0.0, 0.10, 0.55, 1.0, 1.455, 1.91, 2.36, 2.81, H]
    bm = bmesh.new(); info = {}
    rings = []
    for i, z in enumerate(zs):
        r = rad(z) * (0.93 if i in (0, len(zs) - 1) else 1.0)
        ring = []
        for k in range(segs):
            th = math.tau * k / segs
            rr = r - (GD if k % 2 else 0.0)                 # douves : un sommet sur deux est en retrait = rainure
            vv = bm.verts.new((rr * math.cos(th), rr * math.sin(th), z - half))
            info[vv] = (i, k); ring.append(vv)
        rings.append(ring)
    for i in range(len(zs) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k])).material_index = 0
    lid_r = rad(H) * 0.93 * 0.86
    lid = []
    for k in range(segs):
        th = math.tau * k / segs
        vv = bm.verts.new((lid_r * math.cos(th), lid_r * math.sin(th), H - 0.055 - half)); info[vv] = (len(zs), k); lid.append(vv)
    ctr = bm.verts.new((0, 0, H - 0.065 - half))
    for k in range(segs):
        k2 = (k + 1) % segs
        bm.faces.new((rings[-1][k], rings[-1][k2], lid[k2], lid[k])).material_index = 1
        bm.faces.new((lid[k], lid[k2], ctr)).material_index = 1
    bm.normal_update()
    for f in bm.faces:
        c = f.calc_center_median()
        if f.material_index == 1:
            if f.normal.z < 0:
                f.normal_flip()
        elif f.normal.dot(Vector((c.x, c.y, 0))) < 0:
            f.normal_flip()
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:                                     # aretes verticales = limites de douves : franches
        a, b = info.get(e.verts[0]), info.get(e.verts[1])
        if a and b and a[1] == b[1] and a[0] != b[0]:
            e.smooth = False
    body = bpy.data.meshes.new(f"B20_Barrel_{v}")
    bm.to_mesh(body); bm.free()

    hb = bmesh.new()
    prof = lambda w: [(-w / 2, 0.0), (-w / 2 + 0.06, 0.07), (w / 2 - 0.06, 0.07), (w / 2, 0.0)]
    angles = [math.tau * k / segs for k in range(segs)]
    for zc, w in ((1.05, 0.66), (2.50, 0.24), (0.36, 0.24)):
        rows = []
        for off, h in prof(w):
            z = zc + off; r = rad(z) + h
            rows.append([hb.verts.new((r * math.cos(t), r * math.sin(t), z - half)) for t in angles])
        for g in range(3):
            for k in range(segs):
                k2 = (k + 1) % segs
                hb.faces.new((rows[g][k], rows[g][k2], rows[g + 1][k2], rows[g + 1][k]))
    zc = 1.05
    for q in range(VAR[v]["rivets"]):
        th = math.tau * (q + 0.5) / VAR[v]["rivets"]
        Rv = Vector((math.cos(th), math.sin(th), 0)); T = Vector((-math.sin(th), math.cos(th), 0))
        P = Rv * (rad(zc) + 0.07) + Vector((0, 0, zc - half))
        ns = VAR[v]["rivet_sides"]
        base = [hb.verts.new(P + (T * math.cos(a) + Vector((0, 0, 1)) * math.sin(a)) * 0.085) for a in (math.tau * i / ns for i in range(ns))]
        tip = hb.verts.new(P + Rv * 0.075)
        for i in range(ns):
            hb.faces.new((base[i], base[(i + 1) % ns], tip))
    hb.normal_update()
    for f in hb.faces:
        c = f.calc_center_median()
        if f.normal.dot(Vector((c.x, c.y, 0))) < 0:
            f.normal_flip()
    for f in hb.faces:
        f.smooth = True
    hoops = bpy.data.meshes.new(f"B20_Hoops_{v}")
    hb.to_mesh(hoops); hb.free()
    return body, hoops

# ---------------------------------------------------------------- clonage
def clone_tree(src_root, pfx, offset, col):
    made = {}
    def rec(o, parent):
        n = o.copy()
        n.name = pfx + o.name
        col.objects.link(n)
        n.parent = parent
        made[o.name] = n
        for c in o.children:
            rec(c, n)
    rec(src_root, None)
    made[src_root.name].location = offset
    return made

def part_key(name):
    for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"):
        if name.startswith(k):
            return k
    return None

def find_part(made, key):
    return next(n for k, n in made.items() if part_key(k) == key)

def set_obj_materials(ob, mats):
    for s, m in zip(ob.material_slots, mats):
        s.link = 'OBJECT'
        s.material = m

# ---------------------------------------------------------------- nettoyage du lot
PFX = ("B17_", "B18_", "B19_", "B20_")
for o in list(bpy.data.objects):
    if o.name.startswith(PFX):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith(PFX):
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

BOMBS = [
    dict(id="B17", name="Coeur", folder="B17_Coeur", x=1, body="#E0245E", collar="#A81645", spark="#FF7FB0", expl="E13"),
    dict(id="B18", name="Etoiles", folder="B18_Etoiles", x=2, body="#2A4FC4", collar="#1E3A94", spark="#FFD84A", expl="E14"),
    dict(id="B19", name="Militaire", folder="B19_Militaire", x=3, body="#4F7A34", collar="#55672A", spark="#FFB02E", expl="E01"),
    dict(id="B20", name="Tonneau", folder="B20_Tonneau", x=4, body=None, collar="#5E3A20", spark="#FFB02E", expl="E01"),
]
report = []
for bb in BOMBS:
    pfx = bb["id"] + "_"
    for v, src_root, off in (("PC", base_root, Vector((bb["x"] * CELL, 0, 0))),
                             ("MOBILE", mob_root, Vector((bb["x"] * CELL, 2 * CELL, 0)))):
        col = bpy.data.collections.new(f"{bb['folder']}_{v}")
        bpy.context.scene.collection.children.link(col)
        made = clone_tree(src_root, pfx, off, col)
        root = made[src_root.name]
        root["bomb_id"], root["bomb_name"], root["variant"] = bb["id"], bb["name"], v
        root["default_explosion"], root["spark_color"] = bb["expl"], bb["spark"]
        body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
        sfx = "_Mobile" if v == "MOBILE" else ""
        set_obj_materials(collar, [mat(f"DIAG_{bb['id']}_Collar", bb["collar"], 0.45)])
        set_obj_materials(fuse, [m_fuse, m_tip])
        extras = []
        if bb["id"] == "B17":
            set_obj_materials(body, [mat("DIAG_B17_Body", bb["body"], 0.3)])
            me = hearts_mesh(f"B17_Hearts_{v}", v); me.materials.append(mat("DIAG_B17_Hearts", "#FF9DBA", 0.35))
            extras.append(("BombSkin_Hearts", me))
        elif bb["id"] == "B18":
            set_obj_materials(body, [mat("DIAG_B18_Body", bb["body"], 0.3)])
            me = stars_mesh(f"B18_Stars_{v}", v); me.materials.append(mat("DIAG_B18_Stars_Metal", "#FFC52E", 0.3, metal=0.4))
            extras.append(("BombSkin_Stars", me))
        elif bb["id"] == "B19":
            set_obj_materials(body, [mat("DIAG_B19_Body", bb["body"], 0.5)])
            d_me, l_me = camo_meshes(v)
            d_me.materials.append(mat("DIAG_B19_CamoDark", "#2F4A22", 0.55)); l_me.materials.append(mat("DIAG_B19_CamoLight", "#A9B56B", 0.55))
            extras += [("BombSkin_CamoDark", d_me), ("BombSkin_CamoLight", l_me)]
        else:
            b_me, h_me = barrel_meshes(v)
            b_me.materials.append(mat("DIAG_B20_Wood", "#A8693A", 0.6)); b_me.materials.append(mat("DIAG_B20_Lid", "#C48A52", 0.6))
            body.data = b_me
            h_me.materials.append(mat("DIAG_B20_Hoops_Metal", "#9AA3B2", 0.35, metal=0.45))
            extras.append(("BombSkin_Hoops", h_me))
        for nm, mesh in extras:
            ob = bpy.data.objects.new(pfx + nm + sfx, mesh)
            col.objects.link(ob)
            ob.parent = details
            ob.location = body.location
        if v == "PC":
            sp = spark_src.copy()
            sp.name = pfx + "DIAG_SparkPreview"
            diag.objects.link(sp)
            sp.location = spark_loc + off
            set_obj_materials(sp, [mat(f"DIAG_{bb['id']}_Spark", bb["spark"], 0.3, 1.2)])
        n = sum(tris(o.data) for o in made.values() if o.type == 'MESH') + sum(tris(m) for _, m in extras)
        report.append((bb["id"], v, n))

# grille diagnostic : 5 cases de large
bm = bmesh.new()
ma, mb = mat("DIAG_Cell_A", "#8c939e", 0.9), mat("DIAG_Cell_B", "#7a818c", 0.9)
for gx in range(0, 5):
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
for bb in BOMBS:
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith(bb["id"] + "_") and not o.name.endswith("_Mobile") and "DIAG" not in o.name:
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {bb['id']} PC : largeur X {max(xs)-min(xs):.3f} | Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
