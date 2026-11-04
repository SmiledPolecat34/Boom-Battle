# Export FBX individuels ClassicMap (PC + mobile) : 1 modele = 1 FBX, centre a l'origine, 1 unite = 1 stud (global_scale 0.01 comme la bibliotheque modulaire)
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
import os, json
OUT = r"C:\Users\steve\Boom-Battle\assets\3D\fbx\ClassicMap"
GROUPS = ("Towers","Trees","Rocks","Fences","Vegetation","Paths","Decorations")
def export_group(g, mobile):
    cname = g + ("_Mobile" if mobile else ""); d = os.path.join(OUT, "MOBILE" if mobile else "PC", g); os.makedirs(d, exist_ok=True)
    rows = []
    for ob in sorted(bpy.data.collections[cname].objects, key=lambda o: o.name):
        name = ob.name.replace("BB_EXT_MOB_", "BB_EXT_"); path = os.path.join(d, name + ".fbx")
        loc = ob.location.copy(); ob.location = (0, 0, 0)
        bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active = ob
        bpy.ops.export_scene.fbx(filepath=path, use_selection=True, global_scale=0.01, apply_unit_scale=True, apply_scale_options='FBX_SCALE_ALL',
            axis_forward='-Z', axis_up='Y', object_types={'MESH'}, use_mesh_modifiers=True, mesh_smooth_type='FACE', path_mode='RELATIVE', embed_textures=False, bake_anim=False, add_leaf_bones=False)
        ob.location = loc
        img = [n.image.filepath for m in ob.data.materials for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]
        rows.append({"name": name, "group": g, "variant": "mobile" if mobile else "pc", "fbx": os.path.relpath(path, r"C:\Users\steve\Boom-Battle").replace("\\", "/"),
                     "triangles": tris(ob), "size_studs": [round(x, 2) for x in ob.dimensions], "albedo": [os.path.basename(i) for i in img]})
    return rows
