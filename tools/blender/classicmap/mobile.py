# ClassicMap/ExteriorMobile - variantes allegees (LOD mobile) de chaque modele de la bibliotheque
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
RATIO = {"Trees":0.45,"Rocks":0.6,"Fences":0.55,"Vegetation":0.7,"Paths":0.6,"Decorations":0.55}
report_rows = []
# tours : regeneration parametree
LOD = 1; exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\towers.py").read()); LOD = 0
for gname, ratio in RATIO.items():
    src_c = bpy.data.collections[gname]; dst = group(gname, "ExteriorMobile"); clear(dst)
    for o in sorted(src_c.objects, key=lambda x: x.name):
        me = o.data.copy(); me.name = o.name.replace("BB_EXT_","BB_EXT_MOB_")
        bm = bmesh.new(); bm.from_mesh(me)
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(4), verts=bm.verts, edges=bm.edges, use_dissolve_boundaries=False)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        n0 = tris(o)
        new = bpy.data.objects.new(me.name, me); dst.objects.link(new); new.location = (o.location.x, o.location.y-25, 0)
        if n0 > 120:
            md = new.modifiers.new("dec", 'DECIMATE'); md.decimate_type = 'COLLAPSE'; md.ratio = ratio if ratio*len(me.polygons) > 0 else 1.0
            dg = bpy.context.evaluated_depsgraph_get(); ev = new.evaluated_get(dg); m2 = bpy.data.meshes.new_from_object(ev)
            new.modifiers.remove(md); new.data = m2; bpy.data.meshes.remove(me); m2.name = o.name.replace("BB_EXT_","BB_EXT_MOB_")
        for p in new.data.polygons: p.use_smooth = False
# rapport
rows = []
for gname in ("Towers","Trees","Rocks","Fences","Vegetation","Paths","Decorations"):
    pc = {o.name.split("BB_EXT_")[1]: tris(o) for o in bpy.data.collections[gname].objects}
    mb = {o.name.split("BB_EXT_MOB_")[1]: tris(o) for o in bpy.data.collections[gname+"_Mobile"].objects}
    for k in pc: rows.append((k, pc[k], mb.get(k)))
    print(gname, sum(pc.values()), "->", sum(v for v in mb.values()))
for r in rows: print(r)
