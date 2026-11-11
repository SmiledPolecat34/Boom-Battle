"""
Boom Battle - Phase 5 : export de E01 (briques CENTER / SEGMENT / END) de Blender vers un module Luau de TEST.

Pour chaque objet de chaque brique : maillage (sommets + triangles, repere Roblox) et animation ECHANTILLONNEE image par image
(position, echelle uniforme, quaternion) relative a l'origine de la brique. Le lecteur Luau (src/client/Pilot/E01Pilot.luau) rejoue ces
valeurs : on conserve donc l'animation de Blender sans passer par un FBX anime (Roblox n'importe pas les animations de maillage).

Repere : Blender (X, Y, Z) -> Roblox (-X, Z, Y). Matrice propre (determinant +1) : le sens des triangles est conserve.
Usage dans Blender (scene E01 ouverte) :  exec(compile(open(chemin, encoding="utf-8").read(), chemin, "exec"))
"""
import bpy, math, os
from mathutils import Matrix, Vector

ROOT = r"C:\Users\steve\Boom-Battle"
OUT = os.path.join(ROOT, "src", "shared", "Pilot", "E01PilotData.luau")
FRAMES = 13  # images locales 1..13 (0,5 s a 24 images/s)
M4 = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
M3 = M4.to_3x3()
PIECES = [("CENTER", "E01_CENTER", 0, Vector((0, 0, 0))),
          ("SEGMENT", "E01_SEG1_E", 1, Vector((4, 0, 0))),
          ("END", "E01_END_E", 2, Vector((8, 0, 0)))]
MATS = {"E01_Red": "R", "E01_Orange": "O", "E01_Yellow": "Y", "E01_WhiteHot": "W", "E01_Core": "CORE", "E01_Glow": "GLOW",
        "E01_Smoke": "SMOKE", "E01_SmokeEdge": "SMOKE_EDGE", "E01_Spark": "SPARK", "E01_RockLight": "ROCK_A", "E01_RockDark": "ROCK_B"}


def r3(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def mesh_data(ob):
    me = ob.data
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


def build():
    scene = bpy.context.scene
    meshes, mesh_keys, pieces_out = {}, {}, []
    for pname, coll_name, t0, O in PIECES:
        coll = bpy.data.collections[coll_name]
        objs = [o for o in coll.all_objects if o.type == "MESH"]
        objs_out = []
        for ob in objs:
            v, t, smooth = mesh_data(ob)
            key = (tuple(v), tuple(t), smooth)
            if key not in mesh_keys:
                mname = f"{pname}_{ob.name.split('_', 2)[-1]}"
                mesh_keys[key] = mname
                meshes[mname] = (v, t, smooth)
            mname = mesh_keys[key]
            samples = []
            for lf in range(1, FRAMES + 1):
                scene.frame_set(lf + t0)
                loc = M3 @ (ob.location - O)
                q = (M3 @ ob.rotation_euler.to_matrix() @ M3.inverted()).to_quaternion()
                s = ob.scale.x
                samples += [r3(loc.x), r3(loc.y), r3(loc.z), r3(s), r3(q.x), r3(q.y), r3(q.z), r3(q.w)]
            mat = MATS[ob.data.materials[0].name]
            objs_out.append((ob.name, mname, mat, samples))
        pieces_out.append((pname, t0, objs_out))
    scene.frame_set(1)

    L = ["--!nocheck", "-- GENERE par tools/blender/explosions/e01_export_luau.py (E01 v2, pilote). Ne pas editer a la main.",
         "-- Maillages en repere Roblox ; animation echantillonnee (13 images a 24 i/s) : 8 valeurs par image = px,py,pz,echelle,qx,qy,qz,qw.",
         "return {", "\tfps = 24,", f"\tframes = {FRAMES},", "\tmeshes = {"]
    for name, (v, t, smooth) in meshes.items():
        L.append(f'\t\t["{name}"] = {{ smooth = {"true" if smooth else "false"}, v = {{{",".join(v)}}}, t = {{{",".join(t)}}} }},')
    L.append("\t},")
    L.append("\tpieces = {")
    for pname, t0, objs_out in pieces_out:
        L.append(f"\t\t{pname} = {{ t0 = {t0}, objs = {{")
        for name, mname, mat, samples in objs_out:
            L.append(f'\t\t\t{{ name = "{name}", mesh = "{mname}", mat = "{mat}", f = {{{",".join(samples)}}} }},')
        L.append("\t\t} },")
    L.append("\t},")
    L.append("}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")
    print("meshes uniques :", len(meshes), "| objets :", sum(len(o) for _, _, o in pieces_out), "| taille :", os.path.getsize(OUT), "octets")
    for pname, t0, objs_out in pieces_out:
        print(pname, "objets:", len(objs_out))


build()
