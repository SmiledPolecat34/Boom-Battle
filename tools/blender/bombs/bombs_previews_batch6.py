"""Boom Battle - rendus de validation du lot 6 (B01 reference, B06 Glacee, B21 Robot, B24 Cristal)."""
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

MOBILE_ROOTS = ("BombVisualRoot_Mobile",) + tuple(f"B{i:02d}_BombVisualRoot_Mobile" for i in (6, 21, 24))
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
    sc.render.filepath = f"{BASE}\\{folder}\\Batch06_Cristaux_{name}.png"
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
    sc.render.filepath = f"{BASE}\\GAMEPLAY\\Batch06_Cristaux_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("rendu :", sc.render.filepath)

set_hidden(True)
shot("FRONT", "front", (6, 30, 3.0), (6, 0, 2.0), 35)
shot("TOP", "top", (6, 0, 28), (6, 0, 0), 35)
shot("THREE_QUARTER", "3q", (22, -16, 11), (6, 0, 2.0), 35)
shot_game("ingame_yaw0", 0, (6, 0, 1.6), 15)
shot_game("ingame_yaw90", 90, (6, 0, 1.6), 15)
for i, bid in enumerate((6, 21, 24), start=1):
    shot_game(f"ingame_B{bid:02d}_yaw0", 0, (4 * i, 0, 1.8), 7.0, (900, 900))
    shot("FRONT", f"B{bid:02d}_face", (4 * i, 12, 2.2), (4 * i, 0, 1.9), 50, (900, 900))
set_hidden(False)
shot("THREE_QUARTER", "PC_vs_mobile", (24, -8, 14), (6, 4, 2.0), 35)
bpy.ops.wm.save_mainfile()
