"""
Boom Battle - Phase 5 : explosion E01 "Classique", v2 (conception Blender d'abord).

Reference : assets/3D/BOOM_BATTLE_ART/00_REFERENCES/Explosions_32.png (carte E01) :
  etoile de lames pointues superposees (coeur blanc -> jaune -> orange -> rouge aux pointes), eclats fins en losange,
  fumee beige bouffante a liseré orange au pied, cailloux, braises.

Convention du projet : 1 unite Blender = 1 stud ; case = 4 studs ; sol a Z = 0 ; Blender (X,Y,Z) -> Roblox (-X, Z, Y).
Camera de jeu (CameraController.luau) : tangage 55 deg au-dessus de l'horizon, FOV vertical 50 deg, cote +Z Roblox (= +Y Blender).

Briques composables (une collection par instance dans E01_EXPORT) :
  CENTER   case de la bombe          : coeur, 4 couches de lames (R/O/Y/W), halo au sol, 3 fumees, 10 eclats, 6 cailloux
  SEGMENT  case de bras (axe +X local): 3 couches de lames, halo, 2 fumees, 4 braises
  END      bout de bras               : lame avant longue, 3 couches, halo, 1 fumee, 5 eclats
Dissipation = fin de l'animation (les lames se rétractent, la fumee s'eleve puis disparait). 24 images/s, 12 images = 0,5 s.
Decalage de propagation : 1 image (~42 ms) par case (le client Roblox utilise 35 ms).

Usage dans Blender :
  E01_ACTION = "build";  exec(compile(open(chemin, encoding="utf-8").read(), chemin, "exec"))
  E01_ACTION = "render"; exec(...)   # rendus de validation dans 06_PREVIEWS/EXPLOSIONS/E01
"""
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix

ROOT = r"C:\Users\steve\Boom-Battle"
ART = os.path.join(ROOT, "assets", "3D", "BOOM_BATTLE_ART")
BLEND_OUT = os.path.join(ART, "03_VFX", "EXPLOSIONS", "E01_Classique", "E01_Classique_v2.blend")
PREVIEW_DIR = os.path.join(ART, "06_PREVIEWS", "EXPLOSIONS", "E01")
CELL = 4.0
FPS = 24
LIFE = 12          # images de vie d'une brique (0,5 s)
RANGE = 2          # portee de la croix de previsualisation


# ----------------------------------------------------------------------------------------------------------------- materiaux
def lin(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1.0)


def make_mat(name, hexcol, kind="emit", strength=1.0, alpha=1.0, backface=False):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    col = lin(hexcol)
    if kind == "emit":
        sh = nt.nodes.new("ShaderNodeEmission")
        sh.inputs["Color"].default_value = col
        sh.inputs["Strength"].default_value = strength
    else:
        sh = nt.nodes.new("ShaderNodeBsdfPrincipled")
        sh.inputs["Base Color"].default_value = col
        sh.inputs["Roughness"].default_value = 1.0
        sh.inputs["Emission Color"].default_value = col
        sh.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.inputs[0].default_value = alpha
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(sh.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    else:
        nt.links.new(sh.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = backface
    m.diffuse_color = col
    return m


def materials():
    return {
        "R": make_mat("E01_Red", "#FF3B0A", "emit", 1.6),
        "O": make_mat("E01_Orange", "#FF8A00", "emit", 1.8),
        "Y": make_mat("E01_Yellow", "#FFD11A", "emit", 2.0),
        "W": make_mat("E01_WhiteHot", "#FFF3B8", "emit", 2.5),
        "CORE": make_mat("E01_Core", "#FFFFFF", "emit", 3.0),
        "GLOW": make_mat("E01_Glow", "#FFB020", "emit", 1.5, alpha=0.55),
        "SMOKE": make_mat("E01_Smoke", "#E4CFB0", "diffuse", 0.6),
        "SMOKE_EDGE": make_mat("E01_SmokeEdge", "#E2561B", "emit", 1.2, backface=True),
        "SPARK": make_mat("E01_Spark", "#FFC83A", "emit", 3.0),
        "ROCK_A": make_mat("E01_RockLight", "#CDBBA0", "diffuse", 0.25),
        "ROCK_B": make_mat("E01_RockDark", "#5B4637", "diffuse", 0.15),
        "FLOOR_A": make_mat("E01_FloorA", "#8C8F99", "diffuse", 0.0),
        "FLOOR_B": make_mat("E01_FloorB", "#7A7D88", "diffuse", 0.0),
        "DANGER": make_mat("E01_DangerTile", "#FF7A1A", "emit", 1.0, alpha=0.5),
    }


# ----------------------------------------------------------------------------------------------------------------- geometrie
class MeshBuilder:
    def __init__(self):
        self.bm = bmesh.new()

    def blade(self, o, d, L, w, t=None):
        """Lame pointue : base etroite, renflement a 26 %, pointe. Section en losange (plate)."""
        o, d = Vector(o), Vector(d).normalized()
        t = w * 0.28 if t is None else t
        s = d.cross(Vector((0, 0, 1)))
        if s.length < 1e-3:
            s = Vector((1, 0, 0))
        s.normalize()
        u = d.cross(s).normalized()
        bm = self.bm

        def ring(c, ws, ts):
            return [bm.verts.new(c + s * ws), bm.verts.new(c + u * ts), bm.verts.new(c - s * ws), bm.verts.new(c - u * ts)]

        r0 = ring(o, w * 0.55, t * 0.55)
        r1 = ring(o + d * L * 0.26, w, t)
        tip = bm.verts.new(o + d * L)
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
            bm.faces.new((r1[i], r1[j], tip))
        bm.faces.new(r0[::-1])

    def diamond(self, d, L, w):
        """Eclat fin en losange centre sur l'origine, oriente selon d."""
        d = Vector(d).normalized()
        s = d.cross(Vector((0, 0, 1)))
        if s.length < 1e-3:
            s = Vector((1, 0, 0))
        s.normalize()
        u = d.cross(s).normalized()
        bm = self.bm
        ring = [bm.verts.new(s * w), bm.verts.new(u * w * 0.35), bm.verts.new(-s * w), bm.verts.new(-u * w * 0.35)]
        t1, t0 = bm.verts.new(d * L * 0.7), bm.verts.new(-d * L * 0.3)
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((ring[i], ring[j], t1))
            bm.faces.new((ring[j], ring[i], t0))

    def sphere(self, pos, r, sub=1, squash=1.0):
        bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=r,
                                   matrix=Matrix.Translation(Vector(pos)) @ Matrix.Diagonal((1, 1, squash, 1)))

    def cube(self, size, rng):
        rot = Matrix.Rotation(rng.uniform(0, 6.28), 4, "X") @ Matrix.Rotation(rng.uniform(0, 6.28), 4, "Z")
        bmesh.ops.create_cube(self.bm, size=size, matrix=rot)

    def disc(self, r, z=0.04, seg=24):
        bmesh.ops.create_circle(self.bm, cap_ends=True, cap_tris=True, segments=seg, radius=r,
                                matrix=Matrix.Translation((0, 0, z)))

    def quad(self, c, ax, ay, w, h, z=0.04):
        """Rectangle horizontal centre c, de demi-largeur w le long de ax et demi-hauteur h le long de ay (normale +Z)."""
        c, ax, ay = Vector(c), Vector(ax), Vector(ay)
        pts = [c - ax * w - ay * h, c + ax * w - ay * h, c + ax * w + ay * h, c - ax * w + ay * h]
        self.bm.faces.new([self.bm.verts.new(Vector((p.x, p.y, z))) for p in pts])

    def finish(self, name, mat, loc, coll, smooth=False, flip=False, recalc=True):
        bm = self.bm
        if recalc:
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if flip:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        for f in bm.faces:
            f.smooth = smooth
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        ob.location = loc
        try:
            ob.visible_shadow = False
        except Exception:
            pass
        coll.objects.link(ob)
        return ob


# ----------------------------------------------------------------------------------------------------------------- animation
def pop(obs, keys, t0):
    for ob in obs:
        for f, k in keys:
            ob.scale = (k, k, k)
            ob.keyframe_insert("scale", frame=f + t0)


def ballistic(ob, start, vel, g, t0, scale_keys, spin=None):
    """Position balistique echantillonnee toutes les 2 images sur la vie de la brique."""
    for f in range(1, LIFE + 2, 2):
        tau = (f - 1) / FPS
        p = Vector(start) + Vector(vel) * tau - Vector((0, 0, 0.5 * g * tau * tau))
        ob.location = p
        ob.keyframe_insert("location", frame=f + t0)
        if spin:
            ob.rotation_euler = (spin[0] * tau, spin[1] * tau, spin[2] * tau)
            ob.keyframe_insert("rotation_euler", frame=f + t0)
    for f, k in scale_keys:
        ob.scale = (k, k, k)
        ob.keyframe_insert("scale", frame=f + t0)


LAYER_KEYS = {
    "R": [(1, 0), (3, 1.15), (5, 1.0), (8, 0.75), (11, 0)],
    "O": [(1, 0), (3, 1.1), (6, 1.0), (9, 0.7), (12, 0)],
    "Y": [(2, 0), (4, 1.1), (7, 0.95), (10, 0.55), (13, 0)],
    "W": [(2, 0), (4, 1.0), (7, 0.8), (10, 0.4), (13, 0)],
}
LAYERS = [("R", 1.00, 1.00, 0.55), ("O", 0.82, 0.80, 0.85), ("Y", 0.62, 0.62, 1.15), ("W", 0.42, 0.44, 1.50)]  # (id, echelle longueur, echelle largeur, facteur d epaisseur : plus epais vers l interieur pour percer la couche externe)


def _rot(v, a):
    return Matrix.Rotation(a, 3, "Z") @ Vector(v)


def _dir(az_deg, el_deg):
    az, el = math.radians(az_deg), math.radians(el_deg)
    return Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))


def smoke_puff(coll, M, name, loc, r, t0, rng, rise=0.3):
    """Nuage bouffant : 3 spheres fusionnees + coque inversee orange (liseré). Animation : grossit, monte, disparait."""
    mb = MeshBuilder()
    mb.sphere((0, 0, 0), r)
    mb.sphere((r * 0.85, rng.uniform(-0.3, 0.3), -r * 0.1), r * 0.78)
    mb.sphere((-r * 0.7, rng.uniform(-0.3, 0.3), -r * 0.05), r * 0.7)
    body = mb.finish(name, M["SMOKE"], loc, coll, smooth=True)
    mb2 = MeshBuilder()
    k = 1.14
    mb2.sphere((0, 0, 0), r * k)
    mb2.sphere((r * 0.85, 0, -r * 0.1), r * 0.78 * k)
    mb2.sphere((-r * 0.7, 0, -r * 0.05), r * 0.7 * k)
    shell = mb2.finish(name + "_Edge", M["SMOKE_EDGE"], loc, coll, smooth=True, flip=True)
    shell.location = loc
    keys = [(3, 0), (7, 0.85), (10, 1.0), (12, 0)]
    for ob in (body, shell):
        for f, k_ in keys:
            ob.scale = (k_, k_, k_)
            ob.location = Vector(loc) + Vector((0, 0, rise * max(0, f - 3) / 10))
            ob.keyframe_insert("scale", frame=f + t0)
            ob.keyframe_insert("location", frame=f + t0)
    return [body, shell]


def spark(coll, M, name, start, d, speed, t0, L, w, rng):
    mb = MeshBuilder()
    mb.diamond(d, L, w)
    ob = mb.finish(name, M["SPARK"], start, coll)
    ballistic(ob, start, Vector(d).normalized() * speed, 10.0, t0, [(1, 0), (2, 1), (9, 0.8), (12, 0)])
    return ob


# ----------------------------------------------------------------------------------------------------------------- briques
def blade_layers(coll, M, prefix, O, blades, t0, layers=LAYERS):
    """blades : liste de (origine locale, direction, longueur, demi-largeur). Un maillage fusionne par couche."""
    obs = []
    for lid, ls, ws, tf in layers:
        mb = MeshBuilder()
        for (o, d, L, w) in blades:
            mb.blade(o, d, L * ls, w * ws, t=min(w * 0.30 * tf, w * ws * 0.9))
        ob = mb.finish(f"{prefix}_Blades_{lid}", M[lid], O, coll)
        pop([ob], LAYER_KEYS[lid], t0)
        obs.append(ob)
    return obs


def build_center(coll, M, O, t0=0):
    rng = random.Random(101)
    j = lambda v, a: v + rng.uniform(-a, a)
    spec = [(0, 90, 5.8, 0.95), (40, 72, 4.7, 0.9), (220, 72, 4.4, 0.9), (130, 65, 4.0, 0.85), (310, 66, 4.2, 0.85),
            (90, 45, 3.4, 0.8), (270, 45, 3.3, 0.8), (0, 40, 3.2, 0.8), (180, 42, 3.1, 0.8),
            (0, 12, 2.4, 0.75), (90, 12, 2.4, 0.75), (180, 12, 2.4, 0.75), (270, 12, 2.4, 0.75),
            (45, 28, 2.6, 0.7), (135, 30, 2.5, 0.7), (225, 28, 2.6, 0.7), (315, 30, 2.5, 0.7)]
    blades = []
    for az, el, L, w in spec:
        flat = el >= 89
        blades.append(((0, 0, 0.4), _dir(j(az, 0 if flat else 6), el if flat else j(el, 4)), L * rng.uniform(0.93, 1.07), w))
    obs = blade_layers(coll, M, "E01_CENTER", O, blades, t0)
    mb = MeshBuilder()
    mb.sphere((0, 0, 0.8), 1.3, sub=2, squash=0.78)
    core = mb.finish("E01_CENTER_Core", M["CORE"], O, coll, smooth=True)
    pop([core], [(1, 0), (3, 1.35), (6, 1.0), (10, 0.45), (13, 0)], t0)
    mb = MeshBuilder()
    mb.disc(2.1)
    glow = mb.finish("E01_CENTER_Glow", M["GLOW"], O, coll, recalc=False)
    pop([glow], [(1, 0), (3, 1.0), (8, 0.8), (13, 0)], t0)
    obs += [core, glow]
    for i, az in enumerate((30, 150, 270)):
        loc = Vector(O) + Vector((2.1 * math.cos(math.radians(az)), 2.1 * math.sin(math.radians(az)), 0.45))
        obs += smoke_puff(coll, M, f"E01_CENTER_Smoke{i}", loc, 0.85 - 0.07 * i, t0, rng)
    for i in range(10):
        d = _dir(rng.uniform(0, 360), rng.uniform(25, 75))
        obs.append(spark(coll, M, f"E01_CENTER_Spark{i}", Vector(O) + Vector((0, 0, 0.9)), d, rng.uniform(12, 18), t0, 1.5, 0.12, rng))
    for i in range(6):
        mb = MeshBuilder()
        mb.cube(rng.uniform(0.2, 0.32), rng)
        ob = mb.finish(f"E01_CENTER_Debris{i}", M["ROCK_A" if i % 2 == 0 else "ROCK_B"], Vector(O) + Vector((0, 0, 0.5)), coll)
        d = _dir(rng.uniform(0, 360), rng.uniform(40, 70))
        ballistic(ob, Vector(O) + Vector((0, 0, 0.5)), d * rng.uniform(9, 13), 40.0, t0, [(1, 0), (2, 1), (10, 1), (12, 0)],
                  spin=(rng.uniform(-9, 9), rng.uniform(-9, 9), rng.uniform(-9, 9)))
        obs.append(ob)
    return obs


def _arm_common(coll, M, name, O, a, t0, blades_local, glow_len, smokes, rng, layers=LAYERS[:3], smoke_r=0.65):
    blades = [(_rot(o, a), _rot(d, a), L, w) for (o, d, L, w) in blades_local]
    obs = blade_layers(coll, M, name, O, blades, t0, layers=layers)
    ax, ay = _rot((1, 0, 0), a), _rot((0, 1, 0), a)
    mb = MeshBuilder()
    mb.quad((0, 0, 0), ax, ay, glow_len / 2, 0.75)
    glow = mb.finish(name + "_Glow", M["GLOW"], O, coll, recalc=False)
    pop([glow], [(1, 0), (3, 1.0), (8, 0.8), (13, 0)], t0)
    obs.append(glow)
    for i, loc in enumerate(smokes):
        obs += smoke_puff(coll, M, f"{name}_Smoke{i}", Vector(O) + _rot(loc, a), smoke_r, t0, rng)
    return obs


def build_segment(coll, M, O, a, t0, name):
    rng = random.Random(202)
    bl = [((-1.3, 0, 0.3), (0.3, 0, 1), 3.4, 0.7), ((0.0, 0, 0.3), (0.35, 0, 1), 2.8, 0.65), ((1.3, 0, 0.3), (0.4, 0, 1), 2.2, 0.6),
          ((-0.6, 0, 0.3), (0.5, 0.8, 0.6), 1.8, 0.5), ((-0.6, 0, 0.3), (0.5, -0.8, 0.6), 1.8, 0.5),
          ((0.8, 0, 0.3), (0.5, 0.8, 0.6), 1.5, 0.45), ((0.8, 0, 0.3), (0.5, -0.8, 0.6), 1.5, 0.45),
          ((-1.8, 0, 0.3), (1, 0, 0.18), 3.4, 0.55)]
    obs = _arm_common(coll, M, name, O, a, t0, bl, 3.6, [(-0.4, 1.9, 0.45), (0.4, -1.9, 0.45)], rng)
    for i in range(4):
        sgn = 1 if i % 2 == 0 else -1
        d = _rot((0.6, 0.4 * sgn, 1.0), a)
        obs.append(spark(coll, M, f"{name}_Ember{i}", Vector(O) + Vector((0, 0, 0.6)), d, rng.uniform(9, 13), t0, 1.1, 0.10, rng))
    return obs


def build_end(coll, M, O, a, t0, name):
    rng = random.Random(303)
    bl = [((-1.2, 0, 0.3), (1, 0, 0.2), 4.0, 0.75), ((-0.8, 0, 0.3), (0.3, 0, 1), 2.4, 0.6), ((0.6, 0, 0.3), (0.5, 0, 1), 1.8, 0.5),
          ((-0.4, 0, 0.3), (0.8, 0.7, 0.5), 1.6, 0.45), ((-0.4, 0, 0.3), (0.8, -0.7, 0.5), 1.6, 0.45)]
    obs = _arm_common(coll, M, name, O, a, t0, bl, 3.0, [(-0.2, 1.9, 0.45)], rng, smoke_r=0.6)
    for i in range(5):
        d = _rot((1.0, rng.uniform(-0.35, 0.35), rng.uniform(0.3, 0.7)), a)
        obs.append(spark(coll, M, f"{name}_Spark{i}", Vector(O) + Vector((0, 0, 0.6)), d, rng.uniform(12, 17), t0, 1.3, 0.11, rng))
    return obs


# ----------------------------------------------------------------------------------------------------------------- scene
def new_collection(parent, name):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


def build_scene():
    # Nouvelle scene : l'ancienne (bombes) est retiree de la SESSION ; le fichier Batch01_Couleurs.blend sur disque n'est pas modifie
    # car on termine par un "Enregistrer sous" vers un nouveau fichier (la session ne pointe plus vers Batch01).
    new = bpy.data.scenes.new("E01_Classique")
    try:
        bpy.context.window.scene = new
    except Exception:
        bpy.context.window_manager.windows[0].scene = new
    for s in list(bpy.data.scenes):
        if s is not new:
            bpy.data.scenes.remove(s)
    bpy.data.orphans_purge(do_recursive=True)
    scene = new
    M = materials()
    root = scene.collection
    export = new_collection(root, "E01_EXPORT")
    ctx = new_collection(root, "E01_CONTEXT")

    # contexte : sol 9 x 9 cases, dalles de danger sous la croix (portee 2)
    for par, mat in ((0, "FLOOR_A"), (1, "FLOOR_B")):
        mb = MeshBuilder()
        for cx in range(-4, 5):
            for cy in range(-4, 5):
                if (cx + cy) % 2 == par:
                    mb.quad((cx * CELL, cy * CELL, 0), (1, 0, 0), (0, 1, 0), CELL / 2, CELL / 2, z=0.0)
        mb.finish(f"CTX_Floor{par}", M[mat], (0, 0, 0), ctx, recalc=False)
    mb = MeshBuilder()
    cross = [(0, 0)] + [(sx * k, sy * k) for k in range(1, RANGE + 1) for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
    for cx, cy in cross:
        mb.quad((cx * CELL, cy * CELL, 0), (1, 0, 0), (0, 1, 0), CELL / 2 - 0.1, CELL / 2 - 0.1, z=0.03)
    mb.finish("CTX_DangerTiles", M["DANGER"], (0, 0, 0), ctx, recalc=False)

    # briques d'explosion
    pieces = {}
    c = new_collection(export, "E01_CENTER")
    pieces["CENTER"] = build_center(c, M, Vector((0, 0, 0)), 0)
    for ang, tag in ((0, "E"), (90, "N"), (180, "W"), (270, "S")):
        a = math.radians(ang)
        dv = Vector((math.cos(a), math.sin(a), 0))
        for k in range(1, RANGE + 1):
            O = dv * CELL * k
            if k < RANGE:
                nm = f"E01_SEG{k}_{tag}"
                c = new_collection(export, nm)
                pieces[nm] = build_segment(c, M, O, a, k, nm)
            else:
                nm = f"E01_END_{tag}"
                c = new_collection(export, nm)
                pieces[nm] = build_end(c, M, O, a, k, nm)

    # camera de jeu + camera rapprochee, soleil, monde
    target = bpy.data.objects.new("CAM_Target", None)
    target.location = (0, 0, 0.8)
    ctx.objects.link(target)
    for nm, dist in (("CAM_Game", 30.0), ("CAM_Close", 13.0)):
        cd = bpy.data.cameras.new(nm)
        cd.sensor_fit = "VERTICAL"
        cd.lens_unit = "FOV"
        cd.angle = math.radians(50)
        cd.clip_end = 500
        co = bpy.data.objects.new(nm, cd)
        pitch = math.radians(55)
        co.location = Vector((0, math.cos(pitch), math.sin(pitch))) * dist + Vector((0, 0, 0.8))
        tc = co.constraints.new("TRACK_TO")
        tc.target = target
        tc.track_axis = "TRACK_NEGATIVE_Z"
        tc.up_axis = "UP_Y"
        ctx.objects.link(co)
    scene.camera = bpy.data.objects["CAM_Game"]
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 3.0
    so = bpy.data.objects.new("Sun", sd)
    so.rotation_euler = (math.radians(50), 0, math.radians(30))
    ctx.objects.link(so)
    w = bpy.data.worlds.new("E01_World")
    try:
        w.use_nodes = True
        bg = w.node_tree.nodes.get("Background")
        bg.inputs[0].default_value = (0.02, 0.03, 0.07, 1)
        bg.inputs[1].default_value = 1.0
    except Exception:
        pass
    scene.world = w
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, LIFE + RANGE + 1
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.render.engine = "BLENDER_EEVEE"
    try:
        scene.view_settings.view_transform = "Standard"
        scene.eevee.taa_render_samples = 32
    except Exception:
        pass

    # bilan (budget de triangles par brique : utile pour le transfert vers Roblox)
    lines = []
    total_objs = total_tris = 0
    for nm, obs in pieces.items():
        tris = 0
        for ob in obs:
            me = ob.data
            me.calc_loop_triangles()
            tris += len(me.loop_triangles)
        total_objs += len(obs)
        total_tris += tris
        lines.append(f"{nm}: {len(obs)} objets, {tris} triangles")
    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
    lines.append(f"TOTAL croix portee {RANGE}: {total_objs} objets, {total_tris} triangles")
    lines.append("enregistre : " + BLEND_OUT)
    print("\n".join(lines))


def render_previews(frames=(2, 3, 4, 5, 6, 8, 10, 12), cams=("CAM_Game", "CAM_Close")):
    scene = bpy.context.scene
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    out = []
    for cn in cams:
        scene.camera = bpy.data.objects[cn]
        for f in frames:
            scene.frame_set(f)
            scene.render.filepath = os.path.join(PREVIEW_DIR, f"v2_{cn[4:].lower()}_f{f:02d}.png")
            bpy.ops.render.render(write_still=True)
            out.append(scene.render.filepath)
    scene.camera = bpy.data.objects["CAM_Game"]
    scene.frame_set(1)
    print("\n".join(out))


_ACTION = globals().get("E01_ACTION", "build")
if _ACTION == "build":
    build_scene()
elif _ACTION == "render":
    render_previews()
