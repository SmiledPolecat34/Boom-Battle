# E21 Cosmique - 3 directions artistiques de galaxie a plat (rendus fixes de la galaxie formee, avant explosion)
import math, random, bpy, bmesh, os
from mathutils import Vector
E21_ACTION = "lib"
_P = r"C:\Users\steve\Boom-Battle\tools\blender\explosions\e21_cosmic.py"
exec(compile(open(_P, encoding="utf-8").read(), _P, "exec"))

def G(key, hx, a, s=1.4):
    return make_glow("D_" + key, hx, a, s)

def N(key, hx):
    return make_neon("D_" + key, hx)

def ebl(name, specs, sub=3):
    bm = bmesh.new()
    for (cx, cy, cz, sx, sy, sz) in specs:
        res = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        for v in res["verts"]:
            v.co = Vector((v.co.x * sx + cx, v.co.y * sy + cy, v.co.z * sz + cz))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return smooth(me)

def stars_at(name, pts):
    v, f = [], []
    for (x, y, z, s_) in pts:
        b0 = len(v)
        v += [(x + s_, y, z), (x - s_, y, z), (x, y + s_, z), (x, y - s_, z), (x, y, z + s_), (x, y, z - s_)]
        f += [(b0, b0 + 2, b0 + 4), (b0 + 2, b0 + 1, b0 + 4), (b0 + 1, b0 + 3, b0 + 4), (b0 + 3, b0, b0 + 4), (b0 + 2, b0, b0 + 5), (b0 + 1, b0 + 2, b0 + 5), (b0 + 3, b0 + 1, b0 + 5), (b0, b0 + 3, b0 + 5)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    return me

def ribbon_mesh(name, pts, ws, h=0.08, zs=None):
    v, f = [], []
    n = len(pts)
    for i, (cx, cy) in enumerate(pts):
        if i < n - 1:
            dx, dy = pts[i + 1][0] - cx, pts[i + 1][1] - cy
        else:
            dx, dy = cx - pts[i - 1][0], cy - pts[i - 1][1]
        L = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / L, dx / L
        w = ws[i]
        z = zs[i] if zs else 0.0
        t = h * min(1.0, w * 3)
        v += [(cx + nx * w, cy + ny * w, z), (cx + nx * 0.5 * w, cy + ny * 0.5 * w, z + t), (cx - nx * 0.5 * w, cy - ny * 0.5 * w, z + t), (cx - nx * w, cy - ny * w, z), (cx - nx * 0.5 * w, cy - ny * 0.5 * w, z - t), (cx + nx * 0.5 * w, cy + ny * 0.5 * w, z - t)]
    for i in range(n - 1):
        for a in range(6):
            b = (a + 1) % 6
            f.append((i * 6 + a, i * 6 + b, (i + 1) * 6 + b, (i + 1) * 6 + a))
    return smooth(mk(name, v, f))

def sp_pts(r0, r1, turns, ph, n=44, ox=0.0, oy=0.0, ex=0.85):
    out = []
    for i in range(n + 1):
        t = i / float(n)
        th = math.radians(ph) + turns * 2 * math.pi * t
        r = r0 + (r1 - r0) * t ** ex
        out.append((ox + r * math.cos(th), oy + r * math.sin(th)))
    return out

def taper(n, W, p=0.7, fall=0.3):
    return [W * (math.sin(math.pi * min(1.0, (i / float(n)) * 1.05)) ** p) * (1 - fall * i / float(n)) + 0.02 for i in range(n + 1)]

def circ_pts(R, a0, a1, n=60, wob=0.0, seed=1):
    rr = random.Random(seed)
    ph = [rr.uniform(0, 6.28) for _ in range(3)]
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / float(n))
        rw = R * (1 + wob * (0.6 * math.sin(3 * a + ph[0]) + 0.4 * math.sin(5 * a + ph[1])))
        out.append((rw * math.cos(a), rw * math.sin(a)))
    return out

def path_stars(pts, ws, n, seed, spread=0.5, z0=0.5, smin=0.04, smax=0.11):
    rr = random.Random(seed)
    out = []
    m = len(pts) - 1
    for _ in range(n):
        t = rr.random() ** 0.9
        i = min(m - 1, int(t * m))
        x, y = pts[i]
        dx, dy = pts[i + 1][0] - x, pts[i + 1][1] - y
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        o = rr.gauss(0, spread * ws[i] + 0.05)
        out.append((x + nx * o, y + ny * o, z0 + abs(rr.gauss(0, 0.12)), rr.uniform(smin, smax)))
    return out

def scatter_stars(n, seed, R, z0=0.3, z1=0.7, smin=0.03, smax=0.08, ey=0.93):
    rr = random.Random(seed)
    out = []
    for _ in range(n):
        rad = R * math.sqrt(rr.random())
        th = rr.uniform(0, 6.283)
        out.append((rad * math.cos(th), rad * ey * math.sin(th), rr.uniform(z0, z1), rr.uniform(smin, smax)))
    return out

def newcoll(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c

def put(coll, name, mesh, mat, z=0.0, rot=0.0, loc=(0.0, 0.0)):
    ob = bpy.data.objects.new(name, mesh)
    if not ob.data.materials:
        ob.data.materials.append(mat)
    coll.objects.link(ob)
    ob.location = (loc[0], loc[1], z)
    ob.rotation_euler = (0, 0, math.radians(rot))
    ob.visible_shadow = False
    return ob

def rock_at(coll, name, x, y, z, r, sd, mat):
    return put(coll, name, baked(rocks_mesh(name, [(x, y, 0.0, r)], False, sd), z), mat)

# ------------------------------------------------------------------ A : JOYAU STELLAIRE (spirale barree, noyau dore, bras magenta/bleu, voies de poussiere sombres)
def dirA():
    C = newcoll("DIR_A")
    rr = random.Random(11)
    put(C, "A_space", ebl("A_space", [(0, 0, 0, 7.4, 6.9, 0.04), (1.4, 1.1, 0, 6.7, 7.0, 0.04), (-1.5, -1.2, 0, 7.0, 6.4, 0.04)]), G("A_ind", "#150F6A", 0.9, 0.35), 0.03)
    put(C, "A_halo", ebl("A_halo", [(0, 0, 0, 8.8, 8.2, 0.04), (1.2, 1.0, 0, 8.2, 8.4, 0.04)]), G("A_halo", "#3A1AA8", 0.22, 0.6), 0.02)
    for i, (rx, hx, a, z) in enumerate(((5.4, "#4A2CD0", 0.35, 0.06), (4.0, "#B034D8", 0.4, 0.08), (2.8, "#FF6FB0", 0.45, 0.10), (1.8, "#FFB26B", 0.55, 0.12))):
        put(C, f"A_glow{i}", ebl(f"A_glow{i}", [(0, 0, 0, rx, rx * 0.93, 0.05)], 3), G(f"A_g{i}", hx, a, 1.3), z)
    put(C, "A_bar", ebl("A_bar", [(0, 0, 0, 3.4, 0.85, 0.3)]), G("A_bar", "#FFB86B", 0.62, 1.4), 0.2, rot=35)
    put(C, "A_bar2", ebl("A_bar2", [(0, 0, 0, 2.6, 0.45, 0.25)]), G("A_bar2", "#FFE6B0", 0.8, 1.6), 0.24, rot=35)
    # bras principaux magenta (depart aux extremites de la barre) + secondaires bleus
    n = 44
    for k, (ph, r0, r1, tn, col, W) in enumerate(((35, 2.3, 6.9, 0.95, "mag", 1.5), (215, 2.3, 6.9, 0.95, "mag", 1.5), (125, 2.6, 6.5, 0.85, "blu", 0.95), (305, 2.6, 6.5, 0.85, "blu", 0.95))):
        pts = sp_pts(r0, r1, tn, ph, n)
        ws = taper(n, W)
        hx = ("#FF3FA8", "#FF5FC0", "#FFD6F2") if col == "mag" else ("#2F8CFF", "#5FC8FF", "#D6F4FF")
        put(C, f"A_veil{k}", ribbon_mesh(f"A_veil{k}", pts, [w * 1.0 for w in ws], 0.1), G(f"A_veil{k}", hx[0], 0.33, 1.3), 0.18)
        put(C, f"A_arm{k}", ribbon_mesh(f"A_arm{k}", pts, [w * 0.38 for w in ws], 0.1), G(f"A_arm{k}", hx[1], 0.9, 1.7), 0.27)
        put(C, f"A_hi{k}", ribbon_mesh(f"A_hi{k}", pts, [w * 0.12 for w in ws], 0.1), N(f"A_hi{k}", hx[2]), 0.32)
        # voie de poussiere sombre le long du bord interieur
        dp = sp_pts(r0, r1, tn, ph - 9, n)
        put(C, f"A_dust{k}", ribbon_mesh(f"A_dust{k}", dp, [w * 0.30 for w in ws], 0.1), G(f"A_dk{k}", "#12073A", 0.82, 0.25), 0.40)
        st = path_stars(pts, ws, 70, 40 + k, 0.55)
        put(C, f"A_stars{k}", stars_at(f"A_stars{k}", st), G(f"A_st{k}", "#FFFFFF" if col == "mag" else "#BFE8FF", 0.95, 1.4), 0.0)
        kn = path_stars(pts, ws, 9, 60 + k, 0.25, 0.55, 0.12, 0.24)
        put(C, f"A_knot{k}", ebl(f"A_knot{k}", [(x, y, z, s_, s_, s_ * 0.6) for (x, y, z, s_) in kn], 1), G(f"A_kn{k}", "#FF9AE0" if col == "mag" else "#9AF0FF", 0.95, 1.8), 0.0)
    put(C, "A_scatter", stars_at("A_scatter", scatter_stars(260, 5, 7.2)), N("A_sc", "#FFFFFF"), 0.0)
    put(C, "A_scatterC", stars_at("A_scatterC", scatter_stars(120, 6, 7.2, smin=0.03, smax=0.07)), G("A_scc", "#7FD8FF", 0.95, 1.4), 0.0)
    put(C, "A_dome", ebl("A_dome", [(0, 0, 0, 1.25, 1.2, 0.95)], 3), N("A_dome", "#FFF1C8"), 0.18)
    put(C, "A_pt", ebl("A_pt", [(0, 0, 0, 0.55, 0.55, 0.45)], 2), N("A_pt", "#FFFFFF"), 0.9)
    for i, (x, y, z, r_) in enumerate(((3.6, 3.2, 2.1, 0.55), (-4.2, 2.4, 2.8, 0.4), (-3.0, -3.8, 1.9, 0.5), (4.4, -2.8, 2.5, 0.38))):
        rock_at(C, f"A_rock{i}", x, y, z, r_, 7 + i, make_leaf(f"A_rk{i}", "#8A55DC", 0.55))
    return C

# ------------------------------------------------------------------ B : OEIL AURORE (galaxie annulaire : anneaux turquoise/emeraude/violet, rideaux d'aurore, noyau a branches de diffraction)
def dirB():
    C = newcoll("DIR_B")
    put(C, "B_space", ebl("B_space", [(0, 0, 0, 7.5, 7.0, 0.04), (1.3, 1.0, 0, 6.8, 7.1, 0.04), (-1.4, -1.1, 0, 7.1, 6.5, 0.04)]), G("B_sp", "#0A1C58", 0.9, 0.4), 0.03)
    put(C, "B_halo", ebl("B_halo", [(0, 0, 0, 9.0, 8.4, 0.04)]), G("B_hl", "#2B0F7A", 0.25, 0.7), 0.02)
    put(C, "B_violetfog", ebl("B_vf", [(0, 0, 0, 6.0, 5.6, 0.05)]), G("B_vf", "#5A2DD0", 0.3, 0.9), 0.06)
    rings = ((2.1, 0.55, "#36F0D0", "#BFFFF0", 0, 360, 0.04), (3.7, 1.0, "#3AA0FF", "#9FE8FF", 0, 360, 0.06), (5.1, 1.1, "#2EE08A", "#C8FFD8", 20, 300, 0.07), (6.3, 0.6, "#B05CFF", "#E6C8FF", 100, 400, 0.08))
    for i, (R, W, c1, c2, a0, a1, wob) in enumerate(rings):
        pts = circ_pts(R, a0, a1, 70, wob, 3 + i)
        rr = random.Random(20 + i)
        ws = [W * (0.65 + 0.5 * rr.random()) * (0.4 + 0.6 * math.sin(math.pi * k / 70.0) ** 0.5 if (a1 - a0) < 360 else 1.0) for k in range(71)]
        put(C, f"B_ringV{i}", ribbon_mesh(f"B_ringV{i}", pts, ws, 0.1), G(f"B_rv{i}", c1, 0.3, 1.2), 0.14 + 0.01 * i)
        put(C, f"B_ringC{i}", ribbon_mesh(f"B_ringC{i}", pts, [w * 0.36 for w in ws], 0.1), G(f"B_rc{i}", c1, 0.92, 1.8), 0.22 + 0.01 * i)
        put(C, f"B_ringH{i}", ribbon_mesh(f"B_ringH{i}", pts, [w * 0.1 for w in ws], 0.1), N(f"B_rh{i}", c2), 0.28 + 0.01 * i)
        st = path_stars(pts, ws, 110, 70 + i, 0.5)
        put(C, f"B_rst{i}", stars_at(f"B_rst{i}", st), G(f"B_rs{i}", c2, 0.95, 1.5), 0.0)
        kn = path_stars(pts, ws, 7, 90 + i, 0.2, 0.5, 0.1, 0.2)
        put(C, f"B_rkn{i}", ebl(f"B_rkn{i}", [(x, y, z, s_, s_, s_ * 0.6) for (x, y, z, s_) in kn], 1), N(f"B_rk{i}", "#FFFFFF"), 0.0)
    # rideaux d'aurore : rubans ondulants qui flottent entre les anneaux, a plusieurs hauteurs
    for j in range(7):
        a0 = j * 51.0
        pts, zs, ws = [], [], []
        m = 36
        for i in range(m + 1):
            t = i / float(m)
            r = 1.8 + 4.6 * t
            th = math.radians(a0) + 0.8 * math.sin(2 * math.pi * 1.2 * t + j) + 0.5 * t
            pts.append((r * math.cos(th), r * math.sin(th)))
            zs.append(0.35 + (0.9 + 0.2 * (j % 3)) * math.sin(math.pi * t) ** 1.2)
            ws.append(0.5 * math.sin(math.pi * t) ** 0.8 + 0.04)
        hx = ("#3FFFB0", "#FF5FD0", "#8C7CFF")[j % 3]
        put(C, f"B_aurV{j}", ribbon_mesh(f"B_aurV{j}", pts, ws, 0.1, zs), G(f"B_av{j}", hx, 0.34, 1.4), 0.0)
        put(C, f"B_aurC{j}", ribbon_mesh(f"B_aurC{j}", pts, [w * 0.3 for w in ws], 0.1, zs), G(f"B_ac{j}", hx, 0.9, 1.8), 0.02)
    put(C, "B_scatter", stars_at("B_scatter", scatter_stars(240, 8, 7.2)), N("B_sc", "#FFFFFF"), 0.0)
    put(C, "B_scatterG", stars_at("B_scatterG", scatter_stars(110, 9, 7.2, smin=0.03, smax=0.07)), G("B_scg", "#FFD27F", 0.95, 1.4), 0.0)
    # noyau : petit, tres lumineux, avec branches de diffraction
    put(C, "B_coreHalo", ebl("B_ch", [(0, 0, 0, 1.7, 1.7, 0.2)], 3), G("B_chl", "#9FD8FF", 0.5, 1.5), 0.3)
    put(C, "B_core", ebl("B_core", [(0, 0, 0, 0.85, 0.85, 0.7)], 3), N("B_core", "#EAF6FF"), 0.3)
    put(C, "B_spikeA", glint_mesh("B_spikeA", 3.4), G("B_spA", "#FFFFFF", 0.9, 1.8), 0.7)
    put(C, "B_spikeB", glint_mesh("B_spikeB", 2.2), G("B_spB", "#FF8CE6", 0.85, 1.8), 0.72, rot=45)
    for i, (x, y, z, r_) in enumerate(((3.9, 3.0, 2.2, 0.5), (-4.4, 2.0, 2.9, 0.38), (-2.8, -4.0, 2.0, 0.48), (4.6, -2.6, 2.6, 0.34))):
        rock_at(C, f"B_rock{i}", x, y, z, r_, 17 + i, make_leaf(f"B_rk{i}", "#5A6BE0", 0.55))
    return C

# ------------------------------------------------------------------ C : ARCHIPEL STELLAIRE (soleil a petales dore + 5 mini-galaxies colorees reliees par des courants d'etoiles)
def dirC():
    C = newcoll("DIR_C")
    put(C, "C_space", ebl("C_space", [(0, 0, 0, 7.5, 7.0, 0.04), (1.3, 1.0, 0, 6.8, 7.1, 0.04), (-1.4, -1.1, 0, 7.1, 6.5, 0.04)]), G("C_sp", "#10135E", 0.9, 0.4), 0.03)
    put(C, "C_halo", ebl("C_halo", [(0, 0, 0, 9.0, 8.4, 0.04)]), G("C_hl", "#4A1AA0", 0.22, 0.7), 0.02)
    for i, (rx, hx, a, z) in enumerate(((4.2, "#7A2CC8", 0.3, 0.06), (3.0, "#FF5FA0", 0.38, 0.08), (1.9, "#FFB347", 0.5, 0.10))):
        put(C, f"C_glow{i}", ebl(f"C_glow{i}", [(0, 0, 0, rx, rx, 0.05)], 3), G(f"C_g{i}", hx, a, 1.3), z)
    # soleil a petales
    for k in range(12):
        a0 = k * 30.0
        big = (k % 2 == 0)
        pts, ws = [], []
        m = 22
        for i in range(m + 1):
            t = i / float(m)
            r = 0.7 + (3.6 if big else 2.6) * t
            th = math.radians(a0) + 0.75 * t ** 1.2
            pts.append((r * math.cos(th), r * math.sin(th)))
            ws.append((0.6 if big else 0.4) * math.sin(math.pi * t) ** 0.8 + 0.03)
        hx = ("#FFC050", "#FF4FB0")[k % 2]
        put(C, f"C_petV{k}", ribbon_mesh(f"C_petV{k}", pts, ws, 0.1), G(f"C_pv{k}", hx, 0.7, 1.6), 0.16 + 0.004 * k)
        put(C, f"C_petC{k}", ribbon_mesh(f"C_petC{k}", pts, [w * 0.3 for w in ws], 0.1), N(f"C_pc{k}", "#FFF4D0" if big else "#FFD0F0"), 0.22 + 0.004 * k)
    put(C, "C_dome", ebl("C_dome", [(0, 0, 0, 1.15, 1.15, 0.9)], 3), N("C_dome", "#FFF6D8"), 0.2)
    put(C, "C_pt", ebl("C_pt", [(0, 0, 0, 0.5, 0.5, 0.4)], 2), N("C_pt", "#FFFFFF"), 0.9)
    cols = (("#FF3FB0", "#FFB0E8"), ("#35D8FF", "#C0F4FF"), ("#FFB020", "#FFE6A0"), ("#8C5CFF", "#D6C4FF"), ("#30E890", "#C0FFE0"))
    for k, (c1, c2) in enumerate(cols):
        ang = math.radians(45 + 72 * k)
        cx, cy = 4.5 * math.cos(ang), 4.5 * math.sin(ang)
        put(C, f"C_isV{k}", ebl(f"C_isV{k}", [(cx, cy, 0, 1.9, 1.8, 0.05)], 3), G(f"C_iv{k}", c1, 0.32, 1.1), 0.12)
        for a in range(2):
            pts = sp_pts(0.25, 1.75, 0.8, 90 * k + 180 * a, 24, cx, cy)
            ws = taper(24, 0.55)
            put(C, f"C_isA{k}{a}", ribbon_mesh(f"C_isA{k}{a}", pts, ws, 0.1), G(f"C_ia{k}{a}", c1, 0.85, 1.6), 0.24)
            put(C, f"C_isH{k}{a}", ribbon_mesh(f"C_isH{k}{a}", pts, [w * 0.25 for w in ws], 0.1), N(f"C_ih{k}{a}", c2), 0.28)
        put(C, f"C_isK{k}", ebl(f"C_isK{k}", [(cx, cy, 0.3, 0.42, 0.42, 0.35)], 2), N(f"C_ik{k}", "#FFFFFF"), 0.0)
        st = [(cx + x, cy + y, z, s_) for (x, y, z, s_) in scatter_stars(26, 200 + k, 1.9, 0.3, 0.6, 0.03, 0.08)]
        put(C, f"C_isS{k}", stars_at(f"C_isS{k}", st), N(f"C_is{k}", "#FFFFFF"), 0.0)
        rock_at(C, f"C_rock{k}", cx * 1.12, cy * 1.12, 2.0 + 0.2 * k, 0.34, 30 + k, make_leaf(f"C_rk{k}", "#7B4FD0", 0.55))
        # courant d'etoiles entre le soleil et l'ile (S-courbe) + arc vers l'ile voisine
        pts, ws = [], []
        m = 30
        for i in range(m + 1):
            t = i / float(m)
            r = 1.6 + 1.9 * t
            th = ang - 0.55 * (1 - t) ** 1.5 + 0.12 * math.sin(6 * t)
            pts.append((r * math.cos(th), r * math.sin(th)))
            ws.append(0.28 * math.sin(math.pi * min(1, t * 1.1)) ** 0.7 + 0.03)
        put(C, f"C_strV{k}", ribbon_mesh(f"C_strV{k}", pts, ws, 0.1), G(f"C_sv{k}", c1, 0.45, 1.4), 0.17)
        put(C, f"C_strS{k}", stars_at(f"C_strS{k}", path_stars(pts, ws, 40, 300 + k, 0.7, 0.4, 0.03, 0.08)), N(f"C_ss{k}", "#FFFFFF"), 0.0)
        pts2, ws2 = [], []
        nxt = math.radians(45 + 72 * (k + 1))
        for i in range(m + 1):
            t = i / float(m)
            th = ang + (nxt - ang) * (0.18 + 0.64 * t)
            r = 5.3 + 0.6 * math.sin(math.pi * t)
            pts2.append((r * math.cos(th), r * math.sin(th)))
            ws2.append(0.2 * math.sin(math.pi * t) ** 0.8 + 0.02)
        put(C, f"C_arc{k}", ribbon_mesh(f"C_arc{k}", pts2, ws2, 0.1), G(f"C_ac{k}", c2, 0.55, 1.4), 0.2)
    put(C, "C_scatter", stars_at("C_scatter", scatter_stars(260, 12, 7.2)), N("C_sc", "#FFFFFF"), 0.0)
    put(C, "C_scatterP", stars_at("C_scatterP", scatter_stars(110, 13, 7.2, smin=0.03, smax=0.07)), G("C_scp", "#FF9AE8", 0.95, 1.4), 0.0)
    return C

def clear_base():
    for cn in ["E01_CENTER"] + ["E01_SEG1_" + d for d in ARMS] + ["E01_END_" + d for d in ARMS]:
        for o in list(bpy.data.collections[cn].objects):
            bpy.data.objects.remove(o)

def render_dirs(names):
    root = r"C:\Users\steve\Boom-Battle\assets\3D\BOOM_BATTLE_ART\06_PREVIEWS\EXPLOSIONS\E21\galaxy_dirs"
    os.makedirs(root, exist_ok=True)
    ensure_cams()
    sc = bpy.context.scene
    for nm in names:
        for c in bpy.context.scene.collection.children:
            if c.name.startswith("DIR_"):
                c.hide_render = (c.name != "DIR_" + nm)
                c.hide_viewport = (c.name != "DIR_" + nm)
        for cam, tag in (("CAM_Close", "close"), ("CAM_Game", "game"), ("CAM_Top", "top")):
            sc.camera = bpy.data.objects[cam]
            sc.render.filepath = os.path.join(root, "dir%s_%s.png" % (nm, tag))
            bpy.ops.render.render(write_still=True)
    return root

_act = globals().get("GAL_ACTION", "all")
if _act == "all":
    clear_base()
    dirA(); dirB(); dirC()
    print(render_dirs(["A", "B", "C"]))
