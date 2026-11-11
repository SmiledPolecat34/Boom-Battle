"""E02 Rouge : variante d'E01 (même gerbe de lames) : palette rouge sang, cœur jaune-orangé, PAS de fumée, gros rochers sombres au pied.
Pilotage (dans Blender, avec E01_Classique_v2.blend ouvert) :
    E02_ACTION = "build" | "render"; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
Les maillages de lames/étincelles sont ceux d'E01 (aucun nouvel import dans Roblox) ; seuls la palette, les rochers agrandis (x ROCK_SCALE)
et la fumée masquée changent. Le script écrit E02_Rouge_v1.blend à côté (E01_Classique_v2.blend n'est jamais écrasé).
"""
import bpy, os

ROCK_SCALE = 2.4
PALETTE = {  # nom de matériau Blender -> couleur sRGB hex
    "E01_Red": "#B0101C", "E01_Orange": "#F01E10", "E01_Yellow": "#FF7A16", "E01_WhiteHot": "#FFD9A0",
    "E01_Core": "#FFF1D0", "E01_Glow": "#E0200E", "E01_Spark": "#FF5A28", "E01_DangerTile": "#D01010",
    "E01_RockDark": "#2A1A20", "E01_RockLight": "#5A3036",
}

def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def hex_lin(h):
    h = h.lstrip("#")
    return tuple(lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)

def recolor():
    for name, hx in PALETTE.items():
        m = bpy.data.materials.get(name)
        if not m:
            continue
        for n in m.node_tree.nodes:
            for i in n.inputs:
                if i.name in ("Color", "Base Color", "Emission Color") and hasattr(i, "default_value") and len(i.default_value) == 4:
                    i.default_value = hex_lin(hx)

def rocks_and_smoke():
    done = set()
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        if "Smoke" in o.name:
            o.hide_render = True
            o.hide_viewport = True
        if "Debris" in o.name and o.data.name not in done:
            done.add(o.data.name)
            for v in o.data.vertices:
                v.co *= ROCK_SCALE

def build():
    recolor()
    rocks_and_smoke()
    base = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "E02_Rouge")
    os.makedirs(base, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base, "E02_Rouge_v1.blend"))

def render():
    root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))  # .../03_VFX/EXPLOSIONS/<E>/ -> BOOM_BATTLE_ART
    out = os.path.join(root, "06_PREVIEWS", "EXPLOSIONS", "E02")
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for cam in ("CAM_Game", "CAM_Close"):
        sc.camera = bpy.data.objects[cam]
        for f in (3, 5, 8, 11):
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out, "v1_%s_f%02d.png" % ("game" if cam == "CAM_Game" else "close", f))
            bpy.ops.render.render(write_still=True)
    return out

action = globals().get("E02_ACTION", "build")
if action == "build":
    build()
elif action == "render":
    print(render())
