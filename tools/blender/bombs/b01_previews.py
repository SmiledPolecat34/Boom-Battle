"""Boom Battle - rendus de validation de B01 (rig de previsualisation dans la collection B01_DIAG, non exportee)."""
import bpy, math
from mathutils import Vector

BASE = r"C:\Users\steve\Boom-Battle\assets\3D\BOOM_BATTLE_ART\06_PREVIEWS"
sc = bpy.context.scene
dcol = bpy.data.collections["B01_DIAG"]

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
bg.inputs[0].default_value = (0.008, 0.011, 0.03, 1)
bg.inputs[1].default_value = 1.0
sc.world = w

sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = sc.render.resolution_y = 800
sc.render.image_settings.file_format = 'PNG'

def shot(folder, name, loc, target, lens=50):
    cam_d.lens = lens
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f"{BASE}\\{folder}\\B01_Classique_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("rendu :", sc.render.filepath)

shot("FRONT", "front", (0, -17, 2.6), (0.25, 0, 2.3), 50)
shot("TOP", "top", (0, 0, 22), (0, 0, 0), 50)
shot("THREE_QUARTER", "3q", (10, -12, 9), (0.25, 0, 2.2), 50)
shot("GAMEPLAY", "gameplay", (0, -6, 30), (0, 0, 0), 50)
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
