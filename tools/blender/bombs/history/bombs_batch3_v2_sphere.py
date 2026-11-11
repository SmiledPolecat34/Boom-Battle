"""
Boom Battle - Phase 4, lot 3 : B15 Epineuse, B16 Ninja (Famille B : accessoires sous BombSkin_Details).
Prerequis : bomb_base.py execute dans CE fichier. Corps, collerette, meche = maillages de B01 (partages).
- B15 : BombSkin_Spikes = 10 pointes (icosaedre sans les 2 poles : pas de pointe sous la collerette ni vers le sol).
        Portee horizontale limitee (< 3,6 studs) pour rester dans la case de 4.
- B16 (v2) : BombSkin_Band = bandeau rouge LARGE (1,0 stud) en relief sur un grand cercle incline de 35 degres (reste lisible de dessus),
        BombSkin_Shuriken = grand shuriken a 4 pointes (X), lames en relief et trou central, epousant la sphere,
        pose au centre du bandeau (cote +Y Blender = +Z Roblox = camera par defaut du jeu : CameraController, tangage 55 degres). Etincelle rouge (spark_color du manifeste).
Pose : 1 case de 4 studs par bombe (B01 de reference a x=0, B15 a x=4, B16 a x=8) ; variantes mobile a y=+8. Idempotent.
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

CELL = 4.0
R = 1.5
Z_SQUASH = 0.97
VAR = {"PC": dict(spike_sides=10, band_segs=48), "MOBILE": dict(spike_sides=6, band_segs=32)}
SPIKE_L, SPIKE_RB, SPIKE_SINK, SPIKE_AZ = 0.55, 0.30, 0.12, math.radians(18)
BAND_TILT, BAND_W = math.radians(35), 1.00

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

# ---------------------------------------------------------------- B16 : bandeau + shuriken
def band_axes():
    a = Vector((0, -math.sin(BAND_TILT), math.cos(BAND_TILT)))     # le point haut du bandeau regarde +Y Blender = +Z Roblox (camera par defaut)
    u = Vector((1, 0, 0))
    return a, u, a.cross(u)

def band_mesh(name, v):
    segs = VAR[v]["band_segs"]
    a, u, w = band_axes()
    prof = [(-BAND_W / 2, -0.01), (-BAND_W / 2 + 0.10, 0.075), (BAND_W / 2 - 0.10, 0.075), (BAND_W / 2, -0.01)]
    bm = bmesh.new()
    rows = []
    for i in range(segs):
        th = math.tau * i / segs
        q = u * math.cos(th) + w * math.sin(th)
        rows.append([bm.verts.new((q * R + a * off).normalized() * (R + h)) for off, h in prof])
    for i in range(segs):
        j = (i + 1) % segs
        for k in range(3):
            bm.faces.new((rows[i][k], rows[i][k + 1], rows[j][k + 1], rows[j][k]))
    return finish(bm, name)

def shuriken_mesh(name):
    """Etoile a 4 pointes en X : pointes fines, lames en relief (le relief monte vers le centre), trou central.
    Sommets epousant la sphere ; enroulement controle (pas d'orient_outward : les parois du trou regardent vers l'axe)."""
    a, u, w = band_axes()
    n = w                                            # point du grand cercle le plus haut, cote +Y (= +Z Roblox)
    rot = n.to_track_quat('Z', 'Y').to_matrix() @ Matrix.Rotation(math.radians(45), 3, 'Z')
    TIP, NOTCH, HOLE = 0.74, 0.27, 0.14
    base = 0.07                                      # pose sur le dessus du bandeau (0,075)
    h_tip, h_notch, h_hole = 0.05, 0.08, 0.13
    def pt(r, i, h):
        ang = i * math.pi / 4
        d = (n * R + rot @ Vector((r * math.cos(ang), r * math.sin(ang), 0))).normalized()
        return d * (R + base + h)
    bm = bmesh.new()
    Pt, Pb, Ht, Hb = [], [], [], []
    for i in range(8):
        r, h = (TIP, h_tip) if i % 2 == 0 else (NOTCH, h_notch)
        Pt.append(bm.verts.new(pt(r, i, h)))
        Pb.append(bm.verts.new(pt(r, i, 0.0)))
        Ht.append(bm.verts.new(pt(HOLE, i, h_hole)))
        Hb.append(bm.verts.new(pt(HOLE, i, 0.0)))
    for i in range(8):
        j = (i + 1) % 8
        bm.faces.new((Pt[i], Pt[j], Ht[j], Ht[i]))      # dessus (anneau autour du trou), normale vers l'exterieur
        bm.faces.new((Pb[i], Pb[j], Pt[j], Pt[i]))      # paroi exterieure
        bm.faces.new((Hb[j], Hb[i], Ht[i], Ht[j]))      # paroi du trou (normale vers l'axe)
    return finish(bm, name, smooth=False, orient=False)

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
            me = band_mesh(f"B16_Band_{v}", v)
            me.materials.append(mat("DIAG_B16_Band", "#D8262A", 0.4))
            extras.append(("BombSkin_Band", me))
            me2 = shuriken_mesh(f"B16_Shuriken_{v}")
            me2.materials.append(mat("DIAG_B16_Shuriken_Metal", "#D4D9E3", 0.3, metal=0.45))
            extras.append(("BombSkin_Shuriken", me2))
        for nm, mesh in extras:
            ob = bpy.data.objects.new(pfx + nm + sfx, mesh)
            col.objects.link(ob)
            ob.parent = details
            ob.location = body.location            # geometrie construite autour du centre de la sphere
        if v == "PC":
            sp = spark_src.copy()
            sp.name = pfx + "DIAG_SparkPreview"
            diag.objects.link(sp)
            sp.location = spark_loc + off
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
