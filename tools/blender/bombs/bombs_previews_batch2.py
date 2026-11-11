"""Boom Battle - rendus de validation du lot 2 (B01 reference, B13 Football, B14 Basketball)."""
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

MOBILE_ROOTS = ("BombVisualRoot_Mobile", "B13_BombVisualRoot_Mobile", "B14_BombVisualRoot_Mobile")
def tree(n):
    r = bpy.data.objects[n]
    return [r] + list(r.children_recursive)
def set_hidden(names, flag):
    for n in names:
        for o in tree(n):
            o.hide_render = flag

def shot(folder, name, loc, target, lens, res=(1600, 700)):
    sc.render.resolution_x, sc.render.resolution_y = res
    cam_d.lens = lens
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f"{BASE}\\{folder}\\Batch02_Sports_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("rendu :", sc.render.filepath)

set_hidden(MOBILE_ROOTS, True)
shot("FRONT", "front", (4, -26, 3.0), (4, 0, 2.2), 35)
shot("TOP", "top", (4, 0, 24), (4, 0, 0), 35)
shot("THREE_QUARTER", "3q", (20, -18, 11), (4, 0, 2.0), 35)
shot("GAMEPLAY", "gameplay", (4, -5, 24), (4, 0, 0), 40)
shot("THREE_QUARTER", "B13_detail", (10, -9, 6), (4, 0, 2.3), 50, (900, 900))
shot("THREE_QUARTER", "B14_detail", (14, -9, 6), (8, 0, 2.3), 50, (900, 900))
set_hidden(MOBILE_ROOTS, False)
shot("THREE_QUARTER", "PC_vs_mobile", (22, -6, 13), (4, 4, 2.0), 40)
bpy.ops.wm.save_mainfile()
