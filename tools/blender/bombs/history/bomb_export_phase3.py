"""
Boom Battle - export FBX d'une bombe (convention du projet : 1 unite = 1 stud, global_scale 0.01, axes -Z/Y).
Une piece FBX = un materiau (la meche est decoupee a l'export en BombFuse_Curved + BombFuse_Tip).
Les pieces sont a leur place finale, racine a l'origine (pose de repos). Mapping Blender->Roblox : (X,Y,Z) = (-bx, bz, by).
Ecrit : 05_EXPORTS_ROBLOX/BOMBES/{PC,MOBILE}/<ID>_<Nom>.fbx et <ID>_<Nom>_Manifest.json.
"""
import bpy, bmesh, json, os
from mathutils import Matrix, Vector

REPO = r"C:\Users\steve\Boom-Battle"
OUT = REPO + r"\assets\3D\BOOM_BATTLE_ART\05_EXPORTS_ROBLOX\BOMBES"
PARTS = ("BombBody_Base", "BombCollar_Base", "BombFuse_Curved")
EXTRA = {"BombFuse_Curved": "BombFuse_Tip"}          # nom de la 2e piece (slot 1)

def rbx(v):
    return [round(-v.x, 4), round(v.z, 4), round(v.y, 4)]

def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)

def export_bomb(bomb_id, bomb_name, variant):
    sfx = "_Mobile" if variant == "MOBILE" else ""
    sc = bpy.context.scene
    root = bpy.data.objects["BombVisualRoot" + sfx]
    off = root.matrix_world.translation.copy()
    base = f"{bomb_id}_{bomb_name}"
    d = os.path.join(OUT, variant)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, base + ".fbx")

    # les sources sont renommees le temps de l'export : les pieces du FBX gardent ainsi des noms propres (sans ".001")
    srcmap = {part: bpy.data.objects[part + sfx] for part in PARTS}
    saved = [(o, o.name) for o in bpy.data.objects if o.name.replace("_Mobile", "") in PARTS]
    for o, n in saved:
        o.name = n + "__SRC"
    tcol = bpy.data.collections.new("TMP_EXPORT")
    sc.collection.children.link(tcol)
    temps, rows = [], []
    for part in PARTS:
        src = srcmap[part]
        for idx, slot in enumerate(src.data.materials):
            bm = bmesh.new()
            bm.from_mesh(src.data)
            bad = [f for f in bm.faces if f.material_index != idx]
            if bad:
                bmesh.ops.delete(bm, geom=bad, context='FACES')
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
            for f in bm.faces:
                f.material_index = 0
            nm = part if idx == 0 else EXTRA[part]
            me = bpy.data.meshes.new("TMP_" + nm)
            bm.to_mesh(me); bm.free()
            me.materials.append(slot)
            ob = bpy.data.objects.new(nm, me)
            tcol.objects.link(ob)
            ob.matrix_world = Matrix.Translation(-off) @ src.matrix_world
            temps.append(ob)
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action='DESELECT')
    for ob in temps:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = temps[0]
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, global_scale=0.01, apply_unit_scale=True,
        apply_scale_options='FBX_SCALE_ALL', axis_forward='-Z', axis_up='Y', object_types={'MESH'},
        use_mesh_modifiers=True, mesh_smooth_type='EDGE', path_mode='RELATIVE', embed_textures=False,
        bake_anim=False, add_leaf_bones=False)

    allmin, allmax = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for ob in temps:
        bb = [ob.matrix_world @ v.co for v in ob.data.vertices]   # sommets reels (bound_box surestime)
        mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        allmin = Vector((min(allmin[i], mn[i]) for i in range(3))); allmax = Vector((max(allmax[i], mx[i]) for i in range(3)))
        rows.append({"name": ob.name, "material": ob.data.materials[0].name, "triangles": tris(ob.data),
                     "size_studs_roblox": [round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)],
                     "origin_roblox_studs": rbx(ob.matrix_world.translation),
                     "bbox_center_roblox_studs": rbx((mn + mx) / 2)})
    att = bpy.data.objects["FuseTip_Attachment" + sfx]
    tip = att.matrix_world.translation - off
    tdir = att.matrix_world.to_3x3() @ Vector((0, 0, 1))
    man = {"id": bomb_id, "name": bomb_name, "variant": variant, "fbx": os.path.relpath(path, REPO).replace("\\", "/"),
           "units": "1 stud = 1 Blender unit ; FBX ecrit a l'echelle 0.01 comme le decor ClassicMap",
           "axes": "Roblox (X,Y,Z) = (-bx, bz, by)",
           "triangles_total": sum(r["triangles"] for r in rows),
           "size_studs_roblox": [round(allmax.x - allmin.x, 3), round(allmax.z - allmin.z, 3), round(allmax.y - allmin.y, 3)],
           "grid_cell_studs": 4, "pivot": "sol, centre de la case (0,0,0)",
           "parts": rows,
           "fuse_tip_attachment": {"position_roblox_studs": rbx(tip), "direction_roblox": [round(x, 4) for x in rbx(tdir)]},
           "material_slots": {"BombBody_Base": "Body", "BombCollar_Base": "Collar", "BombFuse_Curved": "Fuse", "BombFuse_Tip": "FuseTip"},
           "materials_status": "diagnostic (pas de textures definitives)"}

    for ob in temps:
        me = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.meshes.remove(me)
    bpy.data.collections.remove(tcol)
    report = verify_reimport(path)          # sources encore renommees : les noms reimportes sont ceux du FBX
    for o, n in saved:
        o.name = n
    return man, path, report

def verify_reimport(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    out = []
    for o in new:
        if o.type == 'MESH':
            out.append((o.name, tuple(round(x, 4) for x in o.dimensions), tuple(round(x, 4) for x in o.scale), tris(o.data), len(o.data.polygons)))
    for o in new:
        me = o.data if o.type == 'MESH' else None
        bpy.data.objects.remove(o, do_unlink=True)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)
    for m in list(bpy.data.materials):
        if m.users == 0 and m.name[-4:-3] == ".":
            bpy.data.materials.remove(m)
    return out

def run(bomb_id="B01", bomb_name="Classique"):
    result = {}
    for v in ("PC", "MOBILE"):
        man, path, report = export_bomb(bomb_id, bomb_name, v)
        result[v] = man
        print(v, "->", path, os.path.getsize(path), "octets |", man["triangles_total"], "tris |", man["size_studs_roblox"])
        for row in report:
            print("   reimport:", row)
    mp = os.path.join(OUT, f"{bomb_id}_{bomb_name}_Manifest.json")
    with open(mp, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2, ensure_ascii=False)
    print("manifeste :", mp)

run()
