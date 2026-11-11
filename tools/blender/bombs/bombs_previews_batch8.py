"""Boom Battle - rendus de validation du lot 8 (B01 reference + B07 Lave, B08 Electrique, B09 Cosmique quand elles existent)."""
import bpy, math
from mathutils import Vector

BASE = r"C:\Users\steve\Boom-Battle\assets\3D\BOOM_BATTLE_ART\06_PREVIEWS"
sc = bpy.context.scene
dcol = bpy.data.collections["BOMB_BASE_DIAG"]
for n in ("DIAG_Cam", "DIAG_Sun", "DIAG_Fill"):
    o = bpy.data.objects.get(n)
    if o:
        bpy.data.objects.remove(o, do_unlink=True)
cam_d = bpy.data.cameras.new("DIAG_Cam"); cam = bpy.data.objects.new("DIAG_Cam", cam_d)
sun_d = bpy.data.lights.new("DIAG_Sun", 'SUN'); sun = bpy.data.objects.new("DIAG_Sun", sun_d)
fil_d = bpy.data.lights.new("DIAG_Fill", 'SUN'); fil = bpy.data.objects.new("DIAG_Fill", fil_d)
for o in (cam, sun, fil):
    dcol.objects.link(o)
sun_d.energy, fil_d.energy = 3.2, 1.0
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
fil.rotation_euler = (math.radians(60), 0, math.radians(-140))
sc.camera = cam
w = bpy.data.worlds.get("DIAG_World") or bpy.data.worlds.new("DIAG_World")
try:
    w.use_nodes = True
except Exception:
    pass
bg = w.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.008, 0.011, 0.03, 1); bg.inputs[1].default_value = 1.0
sc.world = w
sc.render.engine = 'BLENDER_EEVEE'
sc.render.image_settings.file_format = 'PNG'
try:
    sc.view_settings.view_transform = 'Standard'     # couleurs fideles (AgX delave les violets)
    sc.view_settings.exposure = 0.7                  # eclaircit les faces tournees vers la camera (lumiere d'apercu faible)
except Exception:
    pass

IDS = [i for i in (7, 8, 9) if f"B{i:02d}_BombVisualRoot" in bpy.data.objects]
CX = 2 * len(IDS)
# sol d'apercu etendu jusqu'aux cases de B22 / B23
import bmesh
for n_ in ("DIAG_GridRow",):
    o_ = bpy.data.objects.get(n_)
    if o_:
        bpy.data.objects.remove(o_, do_unlink=True)
_bm = bmesh.new()
_ma = bpy.data.materials.get("DIAG_Cell_A"); _mb = bpy.data.materials.get("DIAG_Cell_B")
for gx in range(0, 4):
    for gy in range(-1, 2):
        x0, y0 = gx * 4.0 - 2.0, gy * 4.0 - 2.0
        vv = [_bm.verts.new((x0 + dx, y0 + dy, -0.003)) for dx, dy in ((0, 0), (4, 0), (4, 4), (0, 4))]
        _bm.faces.new(vv).material_index = (gx + gy) % 2
bmesh.ops.recalc_face_normals(_bm, faces=_bm.faces)
_me = bpy.data.meshes.new("DIAG_GridRow"); _bm.to_mesh(_me); _bm.free()
if _ma and _mb:
    _me.materials.append(_ma); _me.materials.append(_mb)
dcol.objects.link(bpy.data.objects.new("DIAG_GridRow", _me))
MOBILE_ROOTS = ("BombVisualRoot_Mobile",) + tuple(f"B{i:02d}_BombVisualRoot_Mobile" for i in IDS)
def set_hidden(flag):
    for n in MOBILE_ROOTS:
        r = bpy.data.objects[n]
        for o in [r] + list(r.children_recursive):
            o.hide_render = flag

def shot(folder, name, loc, target, lens, res=(1600, 700)):
    sc.render.resolution_x, sc.render.resolution_y = res
    cam_d.sensor_fit = 'AUTO'; cam_d.sensor_height = 24.0
    cam_d.lens = lens
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f"{BASE}\\{folder}\\Batch08_Elements_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("rendu :", sc.render.filepath)

def shot_game(name, yaw_deg, target, dist, res=(1600, 900)):
    """Camera reelle du jeu : tangage 55, FOV vertical 50, cote +Z Roblox (= +Y Blender), lacet par pas de 90."""
    sc.render.resolution_x, sc.render.resolution_y = res
    cam_d.sensor_fit = 'VERTICAL'; cam_d.sensor_height = 24.0
    cam_d.lens = 12.0 / math.tan(math.radians(25))
    y, pch = math.radians(yaw_deg), math.radians(55)
    to_cam = Vector((-math.sin(y) * math.cos(pch), math.cos(y) * math.cos(pch), math.sin(pch)))
    loc = Vector(target) + to_cam * dist
    cam.location = loc
    cam.rotation_euler = (Vector(target) - loc).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f"{BASE}\\GAMEPLAY\\Batch08_Elements_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("rendu :", sc.render.filepath)

set_hidden(True)
shot("FRONT", "front", (CX, 30, 3.0), (CX, 0, 2.0), 35)
shot("TOP", "top", (CX, 0, 28), (CX, 0, 0), 35)
shot("THREE_QUARTER", "3q", (CX + 16, -16, 11), (CX, 0, 2.0), 35)
shot_game("ingame_yaw0", 0, (CX, 0, 1.6), 15)
shot_game("ingame_yaw90", 90, (CX, 0, 1.6), 15)
shot_game("ingame_yaw180", 180, (CX, 0, 1.6), 15)
for i, bid in enumerate(IDS, start=1):
    shot_game(f"ingame_B{bid:02d}_yaw0", 0, (4 * i, 0, 1.8), 7.0, (900, 900))
    shot("FRONT", f"B{bid:02d}_face", (4 * i, 12, 2.2), (4 * i, 0, 1.9), 50, (900, 900))
    shot("FRONT", f"B{bid:02d}_back", (4 * i, -12, 2.2), (4 * i, 0, 1.9), 50, (900, 900))
set_hidden(False)
shot("THREE_QUARTER", "PC_vs_mobile", (CX + 18, -8, 14), (CX, 4, 2.0), 35)
bpy.ops.wm.save_mainfile()
