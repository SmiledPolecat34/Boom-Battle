"""
Boom Battle - Phase 4, lot 3 : B15 Epineuse, B16 Ninja (Famille B : accessoires sous BombSkin_Details).
Prerequis : bomb_base.py execute dans CE fichier. Corps, collerette, meche = maillages de B01 (partages).
- B15 : BombSkin_Spikes = 10 pointes (icosaedre sans les 2 poles : pas de pointe sous la collerette ni vers le sol).
        Portee horizontale limitee (< 3,6 studs) pour rester dans la case de 4.
- B16 (v3) : la BOMBE ENTIERE a la forme d'un shuriken : corps = etoile a 4 branches posee a plat (pointes sur les diagonales,
        bords concaves, relief bombe), moyeu rond sous la collerette, BombSkin_Band = anneau rouge autour du moyeu.
        4 branches = identique sous les 4 lacets de la camera du jeu (tangage 55 deg, pas de 90 deg). Etincelle rouge.
        Collerette et meche = pieces de B01, descendues sur le moyeu (neck_z modifie).
Pose : 1 case de 4 studs par bombe (B01 de reference a x=0, B15 a x=4, B16 a x=8) ; variantes mobile a y=+8. Idempotent.
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

CELL = 4.0
R = 1.5
Z_SQUASH = 0.97
VAR = {"PC": dict(spike_sides=10, band_segs=48), "MOBILE": dict(spike_sides=6, band_segs=32)}
SPIKE_L, SPIKE_RB, SPIKE_SINK, SPIKE_AZ = 0.55, 0.30, 0.12, math.radians(18)
NINJA_VAR = {"PC": dict(n=6, rings=(1.0, 0.78, 0.56, 0.34), seg=24),
             "MOBILE": dict(n=3, rings=(1.0, 0.66, 0.34), seg=16)}
STAR_TIP, STAR_NOTCH, STAR_CTRL = 2.3, 0.95, 0.5       # rayon des pointes (diagonales), des creux, courbure des bords
RIM_H, CTR_H, DOME_P = 0.16, 0.62, 1.5                 # epaisseur au bord, au centre, profil bombe
HUB_TOP = 0.96
NINJA_NECK_Z = HUB_TOP - 0.20                          # la collerette s'enfonce de 0,20 dans le moyeu (comme sur la sphere)
HUB_PROFILE = [(0.97, 0.0), (0.97, 0.50), (0.90, 0.76), (0.72, 0.91), (0.55, 0.96), (0.45, 0.96)]
RING_PROFILE = [(0.995, 0.44), (0.995, 0.52), (0.93, 0.78), (0.75, 0.955), (0.62, 1.0)]

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

def orient_outward(bm):
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median()) < 0:
            f.normal_flip()

def finish(bm, name, smooth=True, orient=True):
    bm.normal_update()
    if orient:
        orient_outward(bm)
    bmesh.ops.scale(bm, vec=(1, 1, Z_SQUASH), verts=bm.verts)
    for f in bm.faces:
        f.smooth = smooth
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me

# ---------------------------------------------------------------- B15 : pointes
def spikes_mesh(name, v):
    sides = VAR[v]["spike_sides"]
    z, rr = 1 / math.sqrt(5), 2 / math.sqrt(5)
    dirs = []
    for k in range(5):
        a = math.tau * k / 5 + SPIKE_AZ
        dirs.append(Vector((rr * math.cos(a), rr * math.sin(a), z)))
        dirs.append(Vector((rr * math.cos(a + math.pi / 5), rr * math.sin(a + math.pi / 5), -z)))
    bm = bmesh.new()
    for d in dirs:
        ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(ref).normalized(); w = d.cross(u)
        bc = d * (R - SPIKE_SINK)
        ring = [bm.verts.new(bc + (u * math.cos(t) + w * math.sin(t)) * SPIKE_RB)
                for t in (math.tau * i / sides for i in range(sides))]
        tip = bm.verts.new(d * (R + SPIKE_L))
        for i in range(sides):
            bm.faces.new((ring[i], ring[(i + 1) % sides], tip))
    return finish(bm, name)

# ---------------------------------------------------------------- B16 (v3) : corps en forme de shuriken
def star_outline(n):
    """Contour de l'etoile (sens trigo) : pointes a 45/135/225/315 deg, creux a 0/90/180/270 deg, bords concaves (Bezier)."""
    pts = []
    for k in range(4):
        d = lambda deg, r: Vector((math.cos(math.radians(deg)), math.sin(math.radians(deg)), 0)) * r
        tip, notch, nxt = d(45 + 90 * k, STAR_TIP), d(90 + 90 * k, STAR_NOTCH), d(135 + 90 * k, STAR_TIP)
        for A, B in ((tip, notch), (notch, nxt)):
            C = (A + B) * 0.5 * STAR_CTRL
            for i in range(n):
                t = i / n
                pts.append((1 - t) ** 2 * A + 2 * (1 - t) * t * C + t * t * B)
    return pts

def spin_profile(bm, prof, seg):
    vs = [bm.verts.new((r, 0, z)) for r, z in prof]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), dvec=(0, 0, 0),
                   angle=math.tau, steps=seg, use_merge=True, use_duplicate=False)

def orient_dome(faces, center):
    for f in faces:
        if f.normal.dot(f.calc_center_median() - center) < 0:
            f.normal_flip()

def finish_shaded(bm, name, sharp=math.radians(50)):
    for e in bm.edges:
        try:
            if e.is_manifold and e.calc_face_angle() > sharp:
                e.smooth = False
        except Exception:
            pass
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return me

def ninja_star_mesh(name, v):
    cfg = NINJA_VAR[v]
    pts = star_outline(cfg["n"]); m = len(pts)
    bm = bmesh.new()
    rings = []
    for sc_ in cfg["rings"]:
        z = RIM_H + (CTR_H - RIM_H) * (1 - sc_ ** DOME_P)
        rings.append([bm.verts.new((p.x * sc_, p.y * sc_, z)) for p in pts])
    for j in range(len(rings) - 1):
        for i in range(m):
            bm.faces.new((rings[j][i], rings[j][(i + 1) % m], rings[j + 1][(i + 1) % m], rings[j + 1][i]))
    ctr = bm.verts.new((0, 0, CTR_H))
    for i in range(m):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % m], ctr))
    bot = [bm.verts.new((p.x, p.y, 0)) for p in pts]
    for i in range(m):
        j = (i + 1) % m
        bm.faces.new((bot[i], bot[j], rings[0][j], rings[0][i]))      # flanc exterieur
    bm.normal_update()
    star = set(bm.faces)
    if next(iter(bm.faces)).normal.z < 0:
        for f in star:
            f.normal_flip()
    spin_profile(bm, HUB_PROFILE, cfg["seg"])                          # moyeu rond
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.normal_update()
    orient_dome([f for f in bm.faces if f not in star], Vector((0, 0, 0.45)))
    return finish_shaded(bm, name)

def ring_mesh(name, v):
    bm = bmesh.new()
    spin_profile(bm, RING_PROFILE, NINJA_VAR[v]["seg"])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.normal_update()
    orient_dome(list(bm.faces), Vector((0, 0, 0.45)))
    return finish_shaded(bm, name)

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
PFX = ("B15_", "B16_")
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
    dict(id="B15", name="Epineuse", folder="B15_Epineuse", x=1, body="#1B2238", collar="#4B5160", expl="E01", spark="#FFB02E"),
    dict(id="B16", name="Ninja", folder="B16_Ninja", x=2, body="#15161C", collar="#3A3F4A", expl="E01", spark="#FF3B3B"),
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
        root["default_explosion"] = bb["expl"]
        root["spark_color"] = bb["spark"]
        body, collar, fuse, details = (find_part(made, k) for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved", "BombSkin_Details"))
        set_obj_materials(body, [mat(f"DIAG_{bb['id']}_Body", bb["body"], 0.3)])
        set_obj_materials(collar, [mat(f"DIAG_{bb['id']}_Collar", bb["collar"], 0.45)])
        set_obj_materials(fuse, [m_fuse, m_tip])
        sfx = "_Mobile" if v == "MOBILE" else ""
        extras = []
        if bb["id"] == "B15":
            me = spikes_mesh(f"B15_Spikes_{v}", v)
            me.materials.append(mat("DIAG_B15_Spikes_Metal", "#B9BFCB", 0.3, metal=0.45))
            extras.append(("BombSkin_Spikes", me))
        else:
            star = ninja_star_mesh(f"B16_Star_{v}", v)
            star.materials.append(mat("DIAG_B16_Body", bb["body"], 0.35))
            body.data = star
            body.material_slots[0].link = 'DATA'
            body.location = (0, 0, 0)                          # maillage construit dans le repere de la racine (sol Z = 0)
            made["BombNeck" + sfx].location.z = NINJA_NECK_Z   # collerette + meche descendues sur le moyeu
            me = ring_mesh(f"B16_Ring_{v}", v)
            me.materials.append(mat("DIAG_B16_Band", "#D8262A", 0.4))
            extras.append(("BombSkin_Band", me))
        for nm, mesh in extras:
            ob = bpy.data.objects.new(pfx + nm + sfx, mesh)
            col.objects.link(ob)
            ob.parent = details
            ob.location = body.location            # B15 : autour du centre de la sphere ; B16 : repere de la racine
        if v == "PC":
            sp = spark_src.copy()
            sp.name = pfx + "DIAG_SparkPreview"
            diag.objects.link(sp)
            bpy.context.view_layer.update()
            sp.location = made["FuseTip_Attachment"].matrix_world.translation.copy()
            set_obj_materials(sp, [mat(f"DIAG_{bb['id']}_Spark", bb["spark"], 0.3, 1.2)])
        n = sum(tris(o.data) for o in made.values() if o.type == 'MESH') + sum(tris(m) for _, m in extras)
        report.append((bb["id"], v, n, len(extras)))

# grille diagnostic 3 x 3 cases
bm = bmesh.new()
ma, mb = mat("DIAG_Cell_A", "#8c939e", 0.9), mat("DIAG_Cell_B", "#7a818c", 0.9)
for gx in range(0, 3):
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
    print("%-4s %-7s %5d tris (+%d accessoire(s))" % r)
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
