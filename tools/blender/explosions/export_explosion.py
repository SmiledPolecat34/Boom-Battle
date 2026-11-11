"""
Boom Battle - Export GÉNÉRIQUE d'une explosion modulaire (briques CENTER / SEGMENT / END) de Blender vers Roblox.
Produit :
  1. un module Luau de DONNÉES (src/shared/Explosions/<Nom>Data.luau) : pour chaque objet, son maillage (nom du maillage Blender), son matériau
     (clé) et l'animation ÉCHANTILLONNÉE image par image (px,py,pz, échelle uniforme, quaternion) relative à l'origine de la brique ;
     plus la table des matériaux (couleur sRGB, Material Roblox, transparence) lue dans Blender ;
  2. un FBX STATIQUE de tous les maillages uniques (<Nom>_Meshes.fbx), sans animation (Roblox n'importe pas les animations de maillage) :
     chaque maillage est un objet "M_<nom du maillage>", rangé en grille, à échelle 1 (Roblox l'importe à l'échelle x100 : le lecteur corrige).
Repère : Blender (X, Y, Z) -> Roblox (-X, Z, Y). Matrice propre (déterminant +1).
Usage (Blender, fichier de l'explosion ouvert) :
    EXPORT = {"name": "E06", "prefix": "E06_"}; exec(compile(open(PATH, encoding="utf-8").read(), PATH, "exec"))
"""
import bpy, math, os
from mathutils import Matrix, Vector

ROOT = r"C:\Users\steve\Boom-Battle"
FRAMES = int(globals().get("EXPORT", {}).get("frames", 13))
M4 = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
M3 = M4.to_3x3()
_T0 = globals().get("EXPORT", {}).get("t0", {})
PIECES = [("CENTER", "E01_CENTER", _T0.get("CENTER", 0), Vector((0, 0, 0))), ("SEGMENT", "E01_SEG1_E", _T0.get("SEGMENT", 1), Vector((4, 0, 0))), ("END", "E01_END_E", _T0.get("END", 2), Vector((8, 0, 0)))]


def r3(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def srgb(c):
    return round((c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055) * 255)


def mat_info(m, prefix):
    key = m.name[len(prefix):] if m.name.startswith(prefix) else m.name
    col, alpha, neon = (1, 1, 1), 1.0, False
    for n in m.node_tree.nodes:
        if n.type == "EMISSION":
            col, neon = tuple(n.inputs["Color"].default_value[:3]), True
        elif n.type == "BSDF_PRINCIPLED":
            col = tuple(n.inputs["Base Color"].default_value[:3])
            alpha = n.inputs["Alpha"].default_value
    return key, (srgb(col[0]), srgb(col[1]), srgb(col[2])), alpha, neon


def mesh_data(me):
    me.calc_loop_triangles()
    v = []
    for p in me.vertices:
        c = M3 @ p.co
        v += [r3(c.x), r3(c.y), r3(c.z)]
    t, smooth = [], False
    for lt in me.loop_triangles:
        t += [str(i + 1) for i in lt.vertices]
        smooth = smooth or me.polygons[lt.polygon_index].use_smooth
    return v, t, smooth


def export(name, prefix):
    scene = bpy.context.scene
    meshes, mats, pieces_out = {}, {}, []
    for pname, coll_name, t0, O in PIECES:
        objs_out = []
        for ob in [o for o in bpy.data.collections[coll_name].all_objects if o.type == "MESH"]:
            me = ob.data
            if me.name not in meshes:
                meshes[me.name] = mesh_data(me)
            key, rgb, alpha, neon = mat_info(me.materials[0], prefix)
            mats[key] = (rgb, alpha, neon)
            samples = []
            for lf in range(1, FRAMES + 1):
                scene.frame_set(lf + t0)
                loc = M3 @ (ob.location - O)
                q = (M3 @ ob.rotation_euler.to_matrix() @ M3.inverted()).to_quaternion()
                samples += [r3(loc.x), r3(loc.y), r3(loc.z), r3(ob.scale.x), r3(q.x), r3(q.y), r3(q.z), r3(q.w)]
            objs_out.append((ob.name, me.name, key, samples))
        pieces_out.append((pname, t0, objs_out))
    scene.frame_set(1)

    L = ["--!nocheck", f"-- GENERE par tools/blender/explosions/export_explosion.py ({name}). Ne pas editer a la main.",
         "-- Maillages en repere Roblox ; animation echantillonnee (13 images a 24 i/s) : 8 valeurs par image = px,py,pz,echelle,qx,qy,qz,qw.",
         "return {", "\tfps = 24,", f"\tframes = {FRAMES},", "\tmats = {"]
    for k, ((r, g, b), alpha, neon) in mats.items():
        L.append(f'\t\t{k} = {{ color = Color3.fromRGB({r}, {g}, {b}), neon = {"true" if neon else "false"}, transparency = {r3(1 - alpha)} }},')
    L.append("\t},")
    L.append("\tmeshes = {")
    for mname, (v, t, smooth) in ([] if SLIM else meshes.items()):  # SLIM : le moteur n'utilise que le FBX, pas les sommets
        L.append(f'\t\t["{mname}"] = {{ smooth = {"true" if smooth else "false"}, v = {{{",".join(v)}}}, t = {{{",".join(t)}}} }},')
    L.append("\t},")
    L.append("\tpieces = {")
    for pname, t0, objs_out in pieces_out:
        L.append(f"\t\t{pname} = {{ t0 = {t0}, objs = {{")
        for oname, mname, key, samples in objs_out:
            L.append(f'\t\t\t{{ name = "{oname}", mesh = "{mname}", mat = "{key}", f = {{{",".join(samples)}}} }},')
        L.append("\t\t} },")
    L.append("\t},")
    L.append("}")
    out_dir = os.path.join(ROOT, "src", "shared", "Explosions")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{name}Data.luau")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")

    # FBX statique : un objet par maillage unique, en grille (jamais d'animation)
    fbx_dir = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), name + "_FBX")
    fbx_dir = os.path.join(os.path.dirname(bpy.data.filepath), "FBX_export")
    os.makedirs(fbx_dir, exist_ok=True)
    tmp = bpy.data.collections.new("TMP_EXPORT_MESHES")
    bpy.context.scene.collection.children.link(tmp)
    news = []
    for i, mname in enumerate(sorted(meshes)):
        ob = bpy.data.objects.new("M_" + mname, bpy.data.meshes[mname])
        tmp.objects.link(ob)
        ob.location = ((i % 8) * 10.0, (i // 8) * 10.0, 0)
        news.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for o in news:
        o.select_set(True)
    bpy.context.view_layer.objects.active = news[0]
    fbx = os.path.join(fbx_dir, f"{name}_Meshes.fbx")
    bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, object_types={"MESH"}, apply_unit_scale=True, global_scale=1.0,
                             apply_scale_options="FBX_SCALE_NONE", bake_anim=False, add_leaf_bones=False, mesh_smooth_type="FACE", path_mode="COPY")
    for o in news:
        bpy.data.objects.remove(o)
    bpy.data.collections.remove(tmp)
    print(name, "| maillages uniques :", len(meshes), "| objets :", {p: len(o) for p, _, o in pieces_out}, "| data :", os.path.getsize(out), "o | fbx :", os.path.getsize(fbx), "o")
    return out, fbx


_cfg = globals().get("EXPORT", {"name": "E06", "prefix": "E06_"})
SLIM = bool(_cfg.get("slim", False))
export(_cfg["name"], _cfg["prefix"])
