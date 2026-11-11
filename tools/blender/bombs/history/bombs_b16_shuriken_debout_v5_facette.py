"""
Boom Battle - B16 Ninja v4 : la BOMBE EST UN SHURIKEN 2.5D, DEBOUT.
(remplace les versions : v1/v2 = sphere + bandeau, v3_flat = etoile a plat ; elles restent dans history/)

Forme : etoile a 4 pointes sur les diagonales (X), bords concaves, plan VERTICAL, face vers +Y Blender (= +Z Roblox, cote camera par defaut).
Elle tient debout sur deux pieds plats (pointes basses coupees a l'horizontale).
Relief 2.5D en gradins (de l'exterieur vers le centre) :
  paroi + biseau + bouton central -> argent (metal) : arete lumineuse
  pente                           -> acier sombre   : face
  plateau (etoile interieure)     -> rouge          : accent ninja, met le relief en valeur
Trou central TRAVERSANT (v5) : anneau rouge, biseau et paroi argent ; plus de bouton central.
Collerette = virole FINE propre au Ninja (v5, rouge sombre) dans le creux du haut ; meche = piece de B01 (BombNeck deplace).
Pieces exportees : BombBody_Black, BombBody_Edge, BombBody_Plateau (3 materiaux d'un meme objet BombBody_Base), collerette, meche, bout.
Prerequis : bomb_base.py execute dans CE fichier. Idempotent (ne touche qu'aux objets B16_*).
"""
import bpy, bmesh, math
from mathutils import Vector

CELL = 4.0
VARS = {"PC": dict(curve=3, hole_seg=20, collar_seg=16), "MOBILE": dict(curve=2, hole_seg=12, collar_seg=12)}
T, N, TIPW, CONC = 2.30, 0.78, 0.15, 0.20        # rayon des pointes, des creux, largeur du bout de pointe, concavite
FOOT = 0.16                                      # coupe horizontale au-dessus du point le plus bas : pieds plats
Y_WALL, Y_BEV, Y_TOP = 0.17, 0.32, 0.50          # demi-epaisseurs : paroi, biseau, plateau
S_BEV, S_TOP = 0.94, 0.70                        # echelles du contour pour le biseau et le plateau
HOLE_R, HOLE_RIM, HOLE_DROP = 0.32, 0.06, 0.08   # trou central TRAVERSANT : rayon, largeur du biseau du bord, retrait du biseau
NECK_ABOVE_CENTER = N - 0.05                     # la fine virole sort du creux du haut de l'etoile (enfoncee de 0,05)
BASE_NECK_Z = 2.71                               # BombNeck de la base (sphere)

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

# ---------------------------------------------------------------- contour de l'etoile (plan x,z local)
def star_outline(ns):
    P = lambda r, deg: Vector((r * math.cos(math.radians(deg)), r * math.sin(math.radians(deg))))
    pts = []
    for k in range(4):
        phi = 45 + 90 * k
        n0, n1 = P(N, phi - 45), P(N, phi + 45)
        tip = P(T, phi)
        axis = tip.normalized(); perp = Vector((-axis.y, axis.x))
        cw, ccw = tip - perp * TIPW / 2, tip + perp * TIPW / 2
        def curve(A, B):
            mid = (A + B) / 2
            shift = axis * mid.dot(axis) - mid                  # vers l'axe de la lame -> bord concave
            C = mid + (shift.normalized() * CONC if shift.length > 1e-6 else Vector((0, 0)))
            return [(1 - t) ** 2 * A + 2 * (1 - t) * t * C + t * t * B for t in ((i + 1) / (ns + 1) for i in range(ns))]
        pts.append(n0); pts += curve(n0, cw); pts += [cw, ccw]; pts += curve(ccw, n1)
    return pts

def clip_below(poly, zmin):
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        ain, bin_ = a.y >= zmin, b.y >= zmin
        if ain:
            out.append(a)
        if ain != bin_:
            out.append(a.lerp(b, (zmin - a.y) / (b.y - a.y)))
    return out

def inside(poly, p):
    c, n = False, len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
            c = not c
    return c

def shuriken_geometry(name, v):
    cfg = VARS[v]
    poly = star_outline(cfg["curve"])
    zcut = min(p.y for p in poly) + FOOT
    poly = clip_below(poly, zcut)
    zc = -zcut                                    # hauteur du centre de l'etoile : pieds plats a z = 0
    n = len(poly)
    bm = bmesh.new()
    ring = lambda s, y: [bm.verts.new((p.x * s, y, p.y * s)) for p in poly]
    r0f, r0b = ring(1.0, Y_WALL), ring(1.0, -Y_WALL)
    r1f, r1b = ring(S_BEV, Y_BEV), ring(S_BEV, -Y_BEV)
    r2f, r2b = ring(S_TOP, Y_TOP), ring(S_TOP, -Y_TOP)
    wall, front, back, holewall = [], [], [], []
    def F(vs, mi, bucket):
        f = bm.faces.new(vs); f.material_index = mi; bucket.append(f)
    for i in range(n):
        j = (i + 1) % n
        F((r0b[i], r0b[j], r0f[j], r0f[i]), 1, wall)
        F((r0f[i], r0f[j], r1f[j], r1f[i]), 1, front)      # biseau (argent)
        F((r1f[i], r1f[j], r2f[j], r2f[i]), 0, front)      # pente (sombre)
        F((r0b[j], r0b[i], r1b[i], r1b[j]), 1, back)
        F((r1b[j], r1b[i], r2b[i], r2b[j]), 0, back)
    # ---- trou central traversant : anneau rouge (plateau) -> biseau argent -> paroi argent
    m = cfg["hole_seg"]
    circ = lambda r, y: [bm.verts.new((r * math.cos(math.tau * k / m), y, r * math.sin(math.tau * k / m))) for k in range(m)]
    hf1, hf2 = circ(HOLE_R + HOLE_RIM, Y_TOP), circ(HOLE_R, Y_TOP - HOLE_DROP)
    hb1, hb2 = circ(HOLE_R + HOLE_RIM, -Y_TOP), circ(HOLE_R, -(Y_TOP - HOLE_DROP))
    def lace(S, H, bucket):
        """Triangule l'anneau entre le contour de l'etoile S et le cercle H (meme sens trigo, premier sommet a l'angle 0),
        en avancant du cote dont le prochain sommet a le plus petit angle (aucun triangle ne traverse le trou)."""
        ang = []
        for v_ in S:
            a_ = math.atan2(v_.co.z, v_.co.x) % math.tau
            if ang and a_ < ang[-1]:
                a_ += math.tau
            ang.append(a_)
        ang.append(ang[0] + math.tau)
        i = k = 0
        while i < len(S) or k < len(H):
            nxt_s = ang[i + 1] if i < len(S) else 9e9
            nxt_h = math.tau * (k + 1) / len(H) if k < len(H) else 9e9
            if i < len(S) and nxt_s <= nxt_h:
                F((S[i], S[(i + 1) % len(S)], H[k % len(H)]), 2, bucket); i += 1
            else:
                F((S[i % len(S)], H[(k + 1) % len(H)], H[k]), 2, bucket); k += 1
    lace(r2f, hf1, front)
    lace(r2b, hb1, back)
    for i in range(m):
        j = (i + 1) % m
        F((hf1[i], hf1[j], hf2[j], hf2[i]), 1, front)           # biseau du trou (argent)
        F((hb1[j], hb1[i], hb2[i], hb2[j]), 1, back)
        F((hf2[i], hf2[j], hb2[j], hb2[i]), 1, holewall)        # paroi du trou (argent)
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
    for f in holewall:                                    # normale vers l'axe du trou
        c = f.calc_center_median()
        if f.normal.dot(Vector((c.x, 0, c.z))) > 0:
            f.normal_flip()
    for f in bm.faces:
        f.smooth = False                                  # etoile : facettes nettes (style cartoon)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me, zc

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
    for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombNeck", "BombSkin_Details"):
        if name.startswith(k):
            return k
    return None

def find_part(made, key):
    return next(n for k, n in made.items() if part_key(k) == key)

def ninja_collar_mesh(name, seg):
    """Virole fine (rayon 0,40 contre 0,66 pour B01 ; hauteur 0,52 contre 0,70) : socle evase, gorge, levre arrondie."""
    prof = [(0.40, -0.20), (0.40, 0.05), (0.385, 0.09), (0.35, 0.10), (0.32, 0.10), (0.32, 0.24),
            (0.335, 0.29), (0.31, 0.32), (0.27, 0.32), (0.25, 0.30), (0.25, 0.12), (0.12, 0.08)]
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in prof]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), dvec=(0, 0, 0),
                   angle=math.tau, steps=seg, use_merge=True, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    f0 = max(bm.faces, key=lambda f: Vector((f.calc_center_median().x, f.calc_center_median().y, 0)).length)
    c0 = f0.calc_center_median()
    if f0.normal.dot(Vector((c0.x, c0.y, 0))) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    for e in bm.edges:
        try:
            if e.is_manifold and e.calc_face_angle() > math.radians(60):
                e.smooth = False
        except Exception:
            pass
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me

def set_obj_materials(ob, mats):
    for s, m in zip(ob.material_slots, mats):
        s.link = 'OBJECT'
        s.material = m

# ---------------------------------------------------------------- nettoyage (uniquement B16_*)
for o in list(bpy.data.objects):
    if o.name.startswith("B16_"):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith("B16_"):
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
m_steel = mat("DIAG_B16_Steel", "#2B2F3B", 0.5)
m_edge = mat("DIAG_B16_Edge_Metal", "#D4D9E3", 0.28, metal=0.45)
m_plateau = mat("DIAG_B16_Plateau", "#D8262A", 0.4)
m_collar = mat("DIAG_B16_Collar", "#A31D21", 0.4)

report = []
for v, src_root, off in (("PC", base_root, Vector((2 * CELL, 0, 0))), ("MOBILE", mob_root, Vector((2 * CELL, 2 * CELL, 0)))):
    col = bpy.data.collections.new(f"B16_Ninja_{v}")
    bpy.context.scene.collection.children.link(col)
    made = clone_tree(src_root, "B16_", off, col)
    root = made[src_root.name]
    root["bomb_id"], root["bomb_name"], root["variant"] = "B16", "Ninja", v
    root["default_explosion"], root["spark_color"] = "E01", "#FF3B3B"
    root["orientation"] = "plan de l'etoile vertical, face vers +Z Roblox ; pivoter en Y pour faire face a la camera"
    body, collar, fuse = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"))
    neck = find_part(made, "BombNeck")
    me, zc = shuriken_geometry(f"B16_Shuriken_{v}", v)
    for m in (m_steel, m_edge, m_plateau):
        me.materials.append(m)
    body.data = me
    body.location = (0, 0, zc)
    neck_z = zc + NECK_ABOVE_CENTER
    neck.location.z = neck_z
    cme = ninja_collar_mesh(f"B16_Collar_{v}", VARS[v]["collar_seg"])
    cme.materials.append(m_collar)
    collar.data = cme
    set_obj_materials(fuse, [m_fuse, m_tip])
    if v == "PC":
        sp = spark_src.copy()
        sp.name = "B16_DIAG_SparkPreview"
        diag.objects.link(sp)
        sp.location = spark_loc + off + Vector((0, 0, neck_z - BASE_NECK_Z))
        set_obj_materials(sp, [mat("DIAG_B16_Spark", "#FF3B3B", 0.3, 1.2)])
    n = sum(tris(o.data) for k, o in made.items() if o.type == 'MESH')
    report.append((v, n, zc, neck_z))

bpy.context.view_layer.update()
for v, n, zc, nz in report:
    print(f"B16 {v:7s} {n:5d} tris | centre de l'etoile z={zc:.3f} | cou z={nz:.3f}")
for v, suffix in (("PC", ""), ("MOBILE", "_Mobile")):
    xs, ys, zs = [], [], []
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith("B16_") and o.name.endswith(suffix) and "DIAG" not in o.name and (suffix or not o.name.endswith("_Mobile")):
            for vv in o.data.vertices:
                w = o.matrix_world @ vv.co
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  {v}: largeur X {max(xs)-min(xs):.3f} | epaisseur Y {max(ys)-min(ys):.3f} | hauteur {max(zs)-min(zs):.3f} | z min {min(zs):.3f}")
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
