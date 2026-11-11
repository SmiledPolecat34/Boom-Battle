"""
Boom Battle - Phase 4, lot 1 : B02 Rouge, B03 Bleue, B04 Verte, B05 Jaune, B10 Arc-en-ciel (Famille A).
Prerequis : bomb_base.py execute dans CE fichier (BombVisualRoot / BombVisualRoot_Mobile existent).
- B02-B05 : clones LIES du maillage B01 (aucune geometrie nouvelle), materiaux par objet (slots en lien OBJET).
- B10     : meme volume que B01, corps a 6 bandes (indices de materiau par face) - provisoire : sera remplace par une texture
            unique en Phase 7 (1 MeshPart au lieu de 6).
Pose en grille : 1 case de 4 studs par bombe (rangee PC a y=0 ; variantes mobile a y=+8). Idempotent.
"""
import bpy, json, math
from mathutils import Vector

REPO = r"C:\Users\steve\Boom-Battle"
DATA = json.load(open(REPO + r"\tools\blender\bombs\bomb_skins.json", encoding="utf-8"))
CELL = 4.0
R = 1.5

def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def mat(name, hexcol, rough=0.4, emit=0.0):
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
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*rgb, 1)
    return m

def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)

# ---------------------------------------------------------------- nettoyage (uniquement ce lot)
PREFIXES = tuple(s["id"] + "_" for s in DATA["skins"])
for o in list(bpy.data.objects):
    if o.name.startswith(PREFIXES):
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c.name.startswith(PREFIXES):
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
shared = DATA["shared"]
m_fuse = mat("DIAG_Fuse", shared["fuse"], 0.7)
m_tip = mat("DIAG_FuseTip", shared["fuse_tip"], 0.8)

# ---------------------------------------------------------------- clonage d'une hierarchie (maillages partages)
def clone_tree(src_root, pfx, offset, col):
    made = {}
    def rec(o, parent):
        n = o.copy()                     # copy() partage la donnee de maillage
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
    for k in ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved"):
        if name.startswith(k):
            return k
    return None

def find_part(made, key):
    return next(n for k, n in made.items() if part_key(k) == key)

def set_obj_materials(ob, mats):
    for s, m in zip(ob.material_slots, mats):
        s.link = 'OBJECT'
        s.material = m

def tilted_band_index(co, n_bands, tilt):
    s = co.z * math.cos(tilt) + co.x * math.sin(tilt)
    t = max(0.0, min(0.999, (s / R) * 0.5 + 0.5))
    return int(t * n_bands)

# ---------------------------------------------------------------- construction
base_root = bpy.data.objects["BombVisualRoot"]
mob_root = bpy.data.objects["BombVisualRoot_Mobile"]
mob_root.location = (0, 2 * CELL, 0)       # gabarit mobile range hors de la rangee PC
spark_src = bpy.data.objects["DIAG_SparkPreview"]
spark_src_loc = spark_src.location.copy()

report = []
for i, sk in enumerate(DATA["skins"], start=1):
    pfx = sk["id"] + "_"
    x = i * CELL
    variants = [("PC", base_root, Vector((x, 0, 0)))]
    if sk["id"] == "B10":
        variants.append(("MOBILE", mob_root, Vector((x, 2 * CELL, 0))))
    for variant, src_root, off in variants:
        col = bpy.data.collections.new(f"{sk['folder']}_{variant}")
        bpy.context.scene.collection.children.link(col)
        made = clone_tree(src_root, pfx, off, col)
        root = made[src_root.name]
        root["bomb_id"], root["bomb_name"], root["game_id"] = sk["id"], sk["name"], sk["game_id"] or ""
        root["variant"], root["default_explosion"] = variant, sk["default_explosion"]
        m_collar = mat(f"DIAG_{sk['id']}_Collar", sk["collar"], 0.45)
        if sk["id"] == "B10":
            bands = [mat(f"DIAG_B10_Band{k + 1}", h, 0.35) for k, h in enumerate(sk["bands_bottom_to_top"])]
            tilt = math.radians(sk["band_tilt_deg"])
            body_old = find_part(made, "BombBody_Base")
            me = body_old.data.copy()
            me.name = f"B10_BodyBands_{variant}"
            me.materials.clear()                      # AVANT d'assigner les indices (clear() les remet a zero)
            for m in bands:
                me.materials.append(m)
            for p in me.polygons:
                p.material_index = tilted_band_index(Vector(p.center), len(bands), tilt)
            body_old.data = me
        else:
            m_body = mat(f"DIAG_{sk['id']}_Body", sk["body"], 0.3)
            set_obj_materials(find_part(made, "BombBody_Base"), [m_body])
        set_obj_materials(find_part(made, "BombCollar_Base"), [m_collar])
        set_obj_materials(find_part(made, "BombFuse_Curved"), [m_fuse, m_tip])
        if variant == "PC":
            sp = spark_src.copy()
            sp.name = pfx + "DIAG_SparkPreview"
            diag.objects.link(sp)
            sp.location = spark_src_loc + off
            set_obj_materials(sp, [mat(f"DIAG_{sk['id']}_Spark", sk["spark"], 0.3, 1.2)])
        meshes = {o.data.name: tris(o.data) for o in made.values() if o.type == 'MESH'}
        report.append((sk["id"], variant, sum(meshes.values()), len(meshes)))

# ---------------------------------------------------------------- grille diagnostic (1 case = 4 studs) sous la rangee PC
import bmesh
bm = bmesh.new()
ma, mb = mat("DIAG_Cell_A", "#8c939e", 0.9), mat("DIAG_Cell_B", "#7a818c", 0.9)
for gx in range(0, 7):
    for gy in range(-1, 2):
        x0, y0 = gx * CELL - CELL / 2, gy * CELL - CELL / 2
        vv = [bm.verts.new((x0 + dx, y0 + dy, -0.002)) for dx, dy in ((0, 0), (CELL, 0), (CELL, CELL), (0, CELL))]
        f = bm.faces.new(vv)
        f.material_index = (gx + gy) % 2
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("DIAG_GridRow")
bm.to_mesh(me); bm.free()
me.materials.append(ma); me.materials.append(mb)
g = bpy.data.objects.new("DIAG_GridRow", me)
diag.objects.link(g)

bpy.context.view_layer.update()
for r in report:
    print("%-4s %-7s %5d tris (maillages distincts reellement utilises : %d)" % r)
bpy.ops.wm.save_mainfile()
print("Sauvegarde :", bpy.data.filepath)
