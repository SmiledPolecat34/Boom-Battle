"""Boom Battle - rendus de validation du lot 1 (rangee B01..B10, une bombe par case de 4 studs). Rig dans BOMB_BASE_DIAG (non exporte)."""
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
sc.render.resolution_x, sc.render.resolution_y = 1600, 700
sc.render.image_settings.file_format = 'PNG'

# gabarits mobile caches pendant les rendus de la rangee PC
hidden = []
for n in ("BombVisualRoot_Mobile", "B10_BombVisualRoot_Mobile"):
    r = bpy.data.objects[n]
    for o in [r] + list(r.children_recursive):
        hidden.append((o, o.hide_render)); o.hide_render = True

def shot(folder, name, loc, target, lens):
    cam_d.lens = lens
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f"{BASE}\\{folder}\\Batch01_Couleurs_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("rendu :", sc.render.filepath)

shot("FRONT", "front", (12, -34, 3.0), (12, 0, 2.2), 35)
shot("TOP", "top", (12, 0, 31), (12, 0, 0), 35)
shot("THREE_QUARTER", "3q", (30, -26, 15), (12, 0, 2.0), 35)
shot("GAMEPLAY", "gameplay", (12, -7, 30), (12, 0, 0), 40)
for o, h in hidden:
    o.hide_render = h
bpy.ops.wm.save_mainfile()
