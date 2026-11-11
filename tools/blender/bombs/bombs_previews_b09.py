"""Boom Battle - vues de B09 Cosmique (bombe SEULE) : face, profil, dessus, perspective, gros plan, camera du jeu.
Reutilise le rig d'apercu de bombs_previews_batch8.py (lumieres, monde, fonctions shot / shot_game). Fichiers : 06_PREVIEWS/*/Batch08_Elements_B09_*.png"""
import bpy, math
_P = r"C:\Users\steve\Boom-Battle\tools\blender\bombs\bombs_previews_batch8.py"
_src = open(_P, encoding="utf-8").read()
exec(compile(_src.split("set_hidden(True)")[0], "previews_head", "exec"))

# bombe seule : tout le reste est masque au rendu (sauf grille / camera / lumieres)
hidden_prev = []
for o in bpy.data.objects:
    if o.type in {'MESH', 'EMPTY'} and not o.name.startswith("DIAG_") and (not o.name.startswith("B09_") or o.name.endswith("_Mobile") or "_Mobile" in (o.parent.name if o.parent else "")):
        if not o.hide_render:
            o.hide_render = True; hidden_prev.append(o.name)
for o in bpy.data.objects:
    if o.name.startswith("B09_") and o.parent and o.parent.name.endswith("_Mobile"):
        o.hide_render = True
for o in bpy.data.objects:                                   # les enfants de la racine mobile
    if o.name.startswith("B09_") and o.name.endswith("_Mobile"):
        o.hide_render = True
        if o.name not in hidden_prev:
            hidden_prev.append(o.name)

C = (12, 0, 1.9)
shot("FRONT", "B09_face", (12, 11, 2.0), C, 50, (900, 900))
shot("FRONT", "B09_profil", (1, 0, 2.0), C, 50, (900, 900))
shot("TOP", "B09_dessus", (12, 0, 14), (12, 0, 1.5), 50, (900, 900))
shot("THREE_QUARTER", "B09_persp", (6.0, 8.5, 6.0), C, 50, (900, 900))
shot("FRONT", "B09_gros_plan", (12, 7.5, 3.8), (12, 0, 1.8), 50, (900, 900))
shot_game("ingame_B09_yaw0", 0, (12, 0, 1.8), 7.0, (900, 900))
shot_game("ingame_B09_yaw90", 90, (12, 0, 1.8), 7.0, (900, 900))
for n in hidden_prev:
    o = bpy.data.objects.get(n)
    if o:
        o.hide_render = False
# la variante mobile reste masquee au rendu comme dans les autres scripts d'apercu
bpy.ops.wm.save_mainfile()
