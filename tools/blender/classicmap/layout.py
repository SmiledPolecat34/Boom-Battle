# Disposition du decor exterieur ClassicMap, parametree par la taille de l'arene (Python pur, sans bpy).
# HX, HY = demi-etendue EXTERIEURE de l'anneau de murs (Small 24, Medium 36, Large 52 ; proxy Blender 32 x 28).
# Retourne une liste de placements {m: modele, x, y, rz, s, sx} avec l'arene centree en (0,0), portail au sud (-Y), unites Blender.
import math, random
def build_layout(HX, HY, seed=2026):
    rng = random.Random(seed); P = []; placed = []
    def inst(m, x, y, rz=0.0, s=1.0, sx=1.0, reg=None):
        P.append({"m": m, "x": round(x,3), "y": round(y,3), "rz": round(rz,4), "s": round(s,3), "sx": round(sx,4)})
        if reg: placed.append((x, y, reg*s))
    def free(x, y, r): return all((x-px)**2 + (y-py)**2 >= (r+pr)**2 for px,py,pr in placed)
    TX, TY = HX + 9, HY + 9
    in_arena = lambda x, y, m=0: abs(x) < TX+5+m and abs(y) < TY+6+m
    # --- tours ---
    for nm, sx_, sy_ in (("TOWER_01_KeepPyramid",-1,-1),("TOWER_02_KeepBattlement",1,-1),("TOWER_03_RoundDrum",1,1),("TOWER_04_RuinedTower",-1,1)):
        inst(nm, sx_*TX, sy_*TY, math.atan2(-sx_, sy_), 1.0, reg=12)
    # --- clotures ---
    def fence_line(x0, y0, x1, y1, rz):
        L = math.hypot(x1-x0, y1-y0); n = max(1, round(L/4)); sc = L/(n*4)
        for i in range(n):
            t = (i+0.5)/n; x = x0+(x1-x0)*t; y = y0+(y1-y0)*t; r = rng.random()
            k = "FENCE_01_PicketStraight" if r < 0.55 else ("FENCE_02_PostRail" if r < 0.78 else ("FENCE_05_Broken" if r < 0.86 else "FENCE_06_StoneWall"))
            inst(k, x, y, rz, 1.0, sx=sc)
    fx, fy = TX-7, TY-7
    fence_line(-fx, -TY, -7, -TY, math.pi); fence_line(7, -TY, fx, -TY, math.pi); fence_line(-fx, TY, fx, TY, 0.0)
    for side in (-1, 1): fence_line(side*TX, -fy, side*TX, fy, math.pi/2*(1 if side == -1 else -1))
    inst("FENCE_03_Gate", 0, -TY, math.pi)
    for sx_ in (-1, 1): inst("FENCE_07_StonePillar", sx_*7.6, -TY, 0.0, 0.8)
    # --- chemin ---
    y0 = -TY - 3
    inst("PATH_05_Flagstones", 0, y0+5, math.pi); y = y0 - 5
    for i in range(3): inst("PATH_01_DirtStraight", 0, y - i*10.5, math.pi)
    yc = y - 3*10.5 - 5.5
    inst("PATH_03_DirtCross", 0, yc); inst("PATH_02_DirtCurve", 6.2, yc-6, math.pi); inst("PATH_01_DirtStraight", -6, yc-2, math.pi/2)
    inst("PATH_04_StepStones", 16, yc-6, math.pi/2); inst("PATH_07_PlankWalk", 0, yc-8, math.pi); inst("PATH_06_Cobblestone", -10.5, y0-2, 0.0)
    # --- decorations ---
    for sx_ in (-1, 1):
        inst("DECOR_04_LampPost", sx_*9.5, -TY-4); inst("DECOR_10_Banner", sx_*13.5, -TY-2)
        inst("DECOR_04_LampPost", sx_*7.5, y0-14); inst("DECOR_04_LampPost", sx_*7.5, y0-30)
    inst("DECOR_03_SignPost", 8, yc+7, 0.6)
    cx, cy = -28, -TY-30
    inst("DECOR_07_Campfire", cx, cy, 0, reg=4); inst("DECOR_06_Bench", cx-5.5, cy, math.pi/2, reg=3); inst("DECOR_06_Bench", cx, cy-5.5, 0, reg=3); inst("DECOR_01_Barrel", cx+6, cy+3, 0, reg=2.5)
    kx, ky = 27, -TY-27
    inst("DECOR_09_Cart", kx, ky, 0.5, reg=6); inst("DECOR_05_HayBale", kx+8, ky+1, 0.3, reg=3); inst("DECOR_05_HayBale", kx+11, ky-2, 1.0, reg=3); inst("DECOR_02_CrateStack", kx-2, ky-7, 0.4, reg=4)
    inst("DECOR_08_Well", TX+15, 5, 0, reg=5)
    inst("DECOR_01_Barrel", -TX-9, -TY+4, 0, reg=2.5); inst("DECOR_02_CrateStack", TX+9, TY-3, 2.0, reg=4); inst("DECOR_01_Barrel", TX+8, -TY+3, 1.0, reg=2.5)
    # --- foret / rochers / vegetation : densite constante, etendue = zone arene + marge ---
    ext_x, ext_y0, ext_y1 = TX+84, TY+88, TY+78
    area = (2*ext_x)*(ext_y0+ext_y1); k_area = area/(250*240)
    on_path = lambda x, y: abs(x) < 10 and y < -TY-3-5
    corridor = lambda x, y: abs(x) < 16 and y < -TY-3 and y > yc-60
    SP = [("TREE_01_Oak",7.5,3),("TREE_02_Pine",5.5,4),("TREE_03_Birch",4.5,3),("TREE_04_AutumnMaple",6.5,2),("TREE_06_BushTree",5.5,2),("TREE_05_DeadTree",3.5,0.6)]
    cnt = 0; target = int(130*k_area)
    for _ in range(int(6000*k_area)):
        if cnt >= target: break
        x = rng.uniform(-ext_x, ext_x); y = rng.uniform(-ext_y0, ext_y1)
        if in_arena(x, y, 8) or on_path(x, y) or corridor(x, y): continue
        d = math.hypot(x, y); n, r, _w = rng.choices(SP, weights=[w for _,_,w in SP])[0]
        if y > TY+6 and n.startswith("TREE_04"): continue
        if d > ext_x*0.7 and rng.random() < 0.35: n, r = "TREE_02_Pine", 5.5
        s = rng.uniform(0.85, 1.3)
        if not free(x, y, r*s): continue
        inst(n, x, y, rng.uniform(0, 6.28), s, reg=r); cnt += 1
    RK = ["ROCK_01_Boulder","ROCK_03_RockPile","ROCK_05_RockCluster","ROCK_06_SmallRocks","ROCK_04_FlatSlab","ROCK_02_Menhir"]; c = 0
    for _ in range(int(2000*k_area)):
        if c >= int(26*k_area): break
        x = rng.uniform(-ext_x, ext_x); y = rng.uniform(-ext_y0, ext_y1)
        if in_arena(x, y, 4) or on_path(x, y): continue
        n = rng.choices(RK, weights=[3,3,3,5,2,1])[0]; s = rng.uniform(0.8, 1.3)
        if not free(x, y, 4.5*s): continue
        inst(n, x, y, rng.uniform(0, 6.28), s, reg=4.5); c += 1
    VG = [("VEG_01_Bush",3),("VEG_02_BerryBush",1),("VEG_03_TallGrass",4),("VEG_04_GrassTuft",5),("VEG_05_Fern",3),("VEG_08_Mushrooms",1)]; c = 0
    for _ in range(int(4000*k_area)):
        if c >= int(150*k_area): break
        x = rng.uniform(-ext_x, ext_x); y = rng.uniform(-ext_y0, ext_y1)
        if in_arena(x, y, 2) or (abs(x) < 3.5 and y < -TY-3): continue
        n = rng.choices([a for a,_ in VG], weights=[w for _,w in VG])[0]; s = rng.uniform(0.8, 1.4)
        if not free(x, y, 1.6*s): continue
        inst(n, x, y, rng.uniform(0, 6.28), s); c += 1
    for i in range(30):
        x = rng.choice((-1,1))*rng.uniform(5.5, 10); yy = rng.uniform(yc-45, y0)
        inst(rng.choice(("VEG_06_Daisies","VEG_07_Tulips")), x, yy, rng.uniform(0, 6.28), rng.uniform(.9, 1.3))
    for i in range(int(28*(TX/41))):
        side = rng.choice((-1,1)); xx = rng.uniform(-(TX-8), TX-8)
        if abs(xx) < 8 and side == -1: continue
        inst("VEG_01_Bush", xx, side*(TY+2.6), rng.uniform(0, 6.28), rng.uniform(.7, 1.0))
    return P
