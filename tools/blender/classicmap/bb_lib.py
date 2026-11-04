# Boom Battle - ClassicMap exterior : bibliotheque de generation Blender (1 unite = 1 stud)
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

PAL = {
 "StoneLight":(0.66,0.63,0.57),"StoneMid":(0.52,0.50,0.46),"StoneDark":(0.36,0.35,0.34),"StoneMoss":(0.34,0.46,0.26),
 "WoodLight":(0.62,0.44,0.26),"WoodMid":(0.46,0.31,0.18),"WoodDark":(0.30,0.20,0.12),
 "Metal":(0.22,0.23,0.26),"MetalLight":(0.46,0.47,0.52),
 "RoofRed":(0.58,0.22,0.14),"RoofDark":(0.38,0.14,0.10),"Window":(0.04,0.04,0.05),
 "ClothRed":(0.72,0.14,0.14),"ClothYellow":(0.90,0.72,0.20),
 "LeafMid":(0.22,0.50,0.18),"LeafLight":(0.42,0.68,0.24),"LeafDark":(0.12,0.36,0.16),"LeafAutumn":(0.80,0.46,0.14),
 "Bark":(0.32,0.21,0.12),"BarkLight":(0.50,0.36,0.22),"BirchBark":(0.86,0.84,0.78),"BirchMark":(0.12,0.12,0.12),
 "Dirt":(0.48,0.36,0.22),"DirtDark":(0.36,0.26,0.16),"Straw":(0.85,0.72,0.30),"Flame":(1.0,0.55,0.10),
 "FlowerRed":(0.80,0.15,0.15),"FlowerYellow":(0.95,0.80,0.15),"FlowerWhite":(0.95,0.95,0.90),"FlowerPurple":(0.55,0.25,0.70),
 "Grass":(0.25,0.45,0.20),
}
def mat(key):
    n = "PROV_EXT_" + key
    m = bpy.data.materials.get(n) or bpy.data.materials.new(n)
    m.use_nodes = True
    c = PAL[key] + (1.0,)
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = c; b.inputs["Roughness"].default_value = 0.9
    m.diffuse_color = c
    return m

def coll(name, parent=None):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    par = parent or bpy.context.scene.collection
    if c.name not in par.children: par.children.link(c)
    return c
def group(name, root="Exterior"):
    cm = coll("ClassicMap"); ex = coll(root, cm); return coll(name + ("_Mobile" if root == "ExteriorMobile" else ""), ex)
def clear(c):
    for o in list(c.objects):
        me = o.data; bpy.data.objects.remove(o, do_unlink=True)
        if me and me.users == 0: bpy.data.meshes.remove(me)

class B:
    """Constructeur de maillage: liste de materiaux + bmesh."""
    def __init__(self, mats):
        self.bm = bmesh.new(); self.mats = mats; self.I = {k:i for i,k in enumerate(mats)}
    def mi(self, k): return self.I[k]
    def sub(self, M, fn):
        t = B.__new__(B); t.bm = bmesh.new(); t.mats = self.mats; t.I = self.I
        fn(t); t.bm.transform(M)
        me = bpy.data.meshes.new("t"); t.bm.to_mesh(me); t.bm.free(); self.bm.from_mesh(me); bpy.data.meshes.remove(me)

def Rz(a): return Matrix.Rotation(a, 4, 'Z')
def T(v): return Matrix.Translation(Vector(v))

def box(b, c, s, k, rz=0.0, taper=1.0, jit=0.0, rng=None, bev=0.0):
    r = bmesh.ops.create_cube(b.bm, size=1.0); vs = r["verts"]
    R = Rz(rz).to_3x3()
    for v in vs:
        x, y, z = v.co.x, v.co.y, v.co.z
        if z > 0: x *= taper; y *= taper
        p = Vector((x*s[0], y*s[1], z*s[2]))
        if jit and rng: p += Vector((rng.uniform(-jit,jit), rng.uniform(-jit,jit), rng.uniform(-jit,jit)))
        v.co = R @ p + Vector(c)
    for f in {f for v in vs for f in v.link_faces}: f.material_index = b.I[k]
    if bev > 0:
        bmesh.ops.bevel(b.bm, geom=list({e for v in vs for e in v.link_edges}), offset=bev, segments=1, affect='EDGES')
    return vs

def prism(b, c, R0, R1, h, n, k, phase=0.0, cap_bottom=True, cap_top=True):
    """tronc de pyramide/cone a n cotes, base au centre c (z = bas)."""
    x, y, z = c
    def ring(R, zz): return [b.bm.verts.new((x+R*math.cos(phase+2*math.pi*i/n), y+R*math.sin(phase+2*math.pi*i/n), zz)) for i in range(n)]
    r0 = ring(R0, z); mi = b.I[k]
    tip = R1 < 0.05
    r1 = None if tip else ring(R1, z+h)
    tv = b.bm.verts.new((x, y, z+h)) if tip else None
    for i in range(n):
        j = (i+1) % n
        f = b.bm.faces.new([r0[i], r0[j], tv] if tip else [r0[i], r0[j], r1[j], r1[i]]); f.material_index = mi
    if cap_bottom: b.bm.faces.new(r0[::-1]).material_index = mi
    if cap_top and not tip: b.bm.faces.new(r1).material_index = mi

def blob(b, c, r, k, rng, squash=0.85, noise=0.18, sub=2, stretch=(1,1)):
    g = bmesh.ops.create_icosphere(b.bm, subdivisions=sub, radius=1.0); vs = g["verts"]
    for v in vs:
        q = 1 + rng.uniform(-noise, noise)
        v.co = Vector((v.co.x*r*stretch[0]*q, v.co.y*r*stretch[1]*q, v.co.z*r*squash*q)) + Vector(c)
    for f in {f for v in vs for f in v.link_faces}: f.material_index = b.I[k]
    return vs

def tube(b, p0, p1, r0, r1, k, seg=6):
    p0 = Vector(p0); p1 = Vector(p1); d = p1 - p0; L = d.length
    if L < 1e-5: return
    M = T(p0) @ d.normalized().to_track_quat('Z','Y').to_matrix().to_4x4()
    def f(t): prism(t, (0,0,0), r0, r1, L, seg, k)
    b.sub(M, f)

def quad(b, pts, k, double=True):
    for back in ((False, True) if double else (False,)):
        vs = [b.bm.verts.new(p) for p in pts]
        if back: vs = vs[::-1]
        b.bm.faces.new(vs).material_index = b.I[k]

def finish(b, coll_, name, loc=(0,0,0), smooth=False, ground=True):
    b.bm.normal_update(); bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    me = bpy.data.meshes.new(name); b.bm.to_mesh(me); b.bm.free()
    for k in b.mats: me.materials.append(mat(k))
    for p in me.polygons: p.use_smooth = smooth
    if ground:
        zmin = min(v.co.z for v in me.vertices)
        for v in me.vertices: v.co.z -= zmin
    ob = bpy.data.objects.new(name, me); coll_.objects.link(ob); ob.location = loc
    return ob

def report(c):
    print(c.name, [(o.name.split("BB_EXT_")[-1], len(o.data.polygons), tuple(round(x,1) for x in o.dimensions)) for o in c.objects])

def preview(show_prefixes, path, target, dist, az, el, ground_center=None, ground_rgb=(0.45,0.55,0.38), lens=35, ground_size=(260,200)):
    sc = bpy.context.scene; lcs = bpy.context.view_layer.layer_collection
    orig = {c.name: c.exclude for c in lcs.children}
    for c in lcs.children: c.exclude = c.name != "ClassicMap"
    vis = {o.name: o.hide_render for o in bpy.data.objects}
    for o in bpy.data.objects:
        if o.name.startswith(("BB_EXT_","BB_ASM","BB_PREVIEW_Arena")): o.hide_render = not o.name.startswith(tuple(show_prefixes))
    g = bpy.data.objects.get("BB_PREVIEW_Ground")
    if not g:
        me = bpy.data.meshes.new("BB_PREVIEW_Ground"); me.from_pydata([(-.5,-.5,0),(.5,-.5,0),(.5,.5,0),(-.5,.5,0)], [], [(0,1,2,3)])
        g = bpy.data.objects.new("BB_PREVIEW_Ground", me); coll("Preview", coll("ClassicMap")).objects.link(g)
    gm = bpy.data.materials.get("PREVIEW_GroundTmp") or bpy.data.materials.new("PREVIEW_GroundTmp")
    gm.use_nodes = True; gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = ground_rgb + (1,)
    g.data.materials.clear(); g.data.materials.append(gm)
    t = Vector(target); g.location = (t.x, t.y, -0.02); g.scale = (ground_size[0], ground_size[1], 1); g.hide_render = False
    cam = bpy.data.objects.get("BB_PREVIEW_Cam")
    if not cam:
        cam = bpy.data.objects.new("BB_PREVIEW_Cam", bpy.data.cameras.new("BB_PREVIEW_Cam")); coll("Preview", coll("ClassicMap")).objects.link(cam)
    sc.camera = cam; cam.data.lens = lens; cam.data.clip_end = 2000
    a = math.radians(az); e = math.radians(el)
    cam.location = t + Vector((dist*math.cos(e)*math.sin(a), -dist*math.cos(e)*math.cos(a), dist*math.sin(e)))
    cam.rotation_euler = (t - cam.location).to_track_quat('-Z','Y').to_euler()
    sc.render.resolution_x = 1100; sc.render.resolution_y = 800; sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in bpy.data.objects:
        if o.name in vis: o.hide_render = vis[o.name]
    g.hide_render = True
    for c in lcs.children: c.exclude = orig[c.name]

def tris(o): return sum(len(p.vertices)-2 for p in o.data.polygons)
