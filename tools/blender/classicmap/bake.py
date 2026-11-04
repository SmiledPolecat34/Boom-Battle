# Cuisson des albedo : depliage UV + bake DIFFUSE(COLOR) depuis les materiaux procéduraux, puis remplacement par 1 materiau/image par modele
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_materials.py").read())
import os, time
TEX_ROOT = r"C:\Users\steve\Boom-Battle\assets\Textures\ClassicMap"
SIZES = {  # (PC, mobile)
 "Towers":(1024,512),"Trees":(512,256),"Rocks":(256,128),"Fences":(256,128),"Vegetation":(256,128),"Paths":(512,256),"Decorations":(256,128)}
def setup_cycles():
    sc = bpy.context.scene; st = (sc.render.engine,)
    sc.render.engine = 'CYCLES'; sc.cycles.samples = 1; sc.cycles.device = 'CPU'; sc.cycles.use_denoising = False
    return st
def bake_one(ob, size, out_path):
    me = ob.data; slots = [m.name for m in me.materials]            # noms PROV_EXT_xxx
    keys = [n.replace("PROV_EXT_", "") for n in slots]
    for i, k in enumerate(keys): me.materials[i] = tex_mat(k)      # remplacement en place (garde material_index)
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003); bpy.ops.object.mode_set(mode='OBJECT')
    img = bpy.data.images.new("bake_tmp", size, size, alpha=False); img.colorspace_settings.name = 'sRGB'
    img.generated_color = (0.5, 0.5, 0.5, 1)
    nodes = []
    for m in me.materials:
        n = m.node_tree.nodes.new("ShaderNodeTexImage"); n.image = img; m.node_tree.nodes.active = n; n.select = True; nodes.append((m, n))
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=6, use_clear=True)
    for m, n in nodes: m.node_tree.nodes.remove(n)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    img.filepath_raw = out_path; img.file_format = 'PNG'; img.save()
    final = bpy.data.materials.get("MAT_EXT_" + ob.name.replace("BB_EXT_", "")) or bpy.data.materials.new("MAT_EXT_" + ob.name.replace("BB_EXT_", ""))
    final.use_nodes = True; nt = final.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); bs = nt.nodes.new("ShaderNodeBsdfPrincipled"); bs.inputs["Roughness"].default_value = 0.9
    tx = nt.nodes.new("ShaderNodeTexImage"); fimg = bpy.data.images.load(out_path, check_existing=False); fimg.name = os.path.basename(out_path); tx.image = fimg
    nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"]); nt.links.new(bs.outputs[0], out.inputs[0])
    me.materials.clear(); me.materials.append(final)
    for p in me.polygons: p.material_index = 0
    bpy.data.images.remove(img)
def bake_group(g, mobile=False, only=None):
    t0 = time.time(); eng = bpy.context.scene.render.engine; setup_cycles()
    cname = g + ("_Mobile" if mobile else ""); size = SIZES[g][1 if mobile else 0]
    for ob in sorted(bpy.data.collections[cname].objects, key=lambda o: o.name):
        if only and not any(s in ob.name for s in only): continue
        nm = ob.name.replace("BB_EXT_MOB_", "").replace("BB_EXT_", "")
        path = os.path.join(TEX_ROOT, "MOBILE" if mobile else "PC", g, nm + ("_albedo_%d.png" % size if mobile else "_albedo.png"))
        bake_one(ob, size, path)
    bpy.context.scene.render.engine = eng
    print(cname, "ok", round(time.time()-t0,1), "s")
