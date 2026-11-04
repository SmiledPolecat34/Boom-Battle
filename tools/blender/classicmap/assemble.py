# ClassicMap/Assembly - assemblage final du decor exterieur autour de l'arene (instances liees des modeles de la bibliotheque)
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
CY = -400                      # centre de l'arene proxy (64 x 56)
ASM = coll("Assembly", coll("ClassicMap")); 
for c in list(ASM.children): 
    for o in list(c.objects): bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(c)
for o in list(ASM.objects): bpy.data.objects.remove(o, do_unlink=True)
SUB = {k: coll("ASM_"+k, ASM) for k in ("Ground","Towers","Fences","Paths","Trees","Rocks","Vegetation","Decorations")}
rng = random.Random(2026)
def src(n):
    for o in bpy.data.objects:
        if o.name.startswith("BB_EXT_"+n) and o.name.count("_") >= 3 and o.users_collection and o.users_collection[0].name in ("Towers","Trees","Rocks","Fences","Vegetation","Paths","Decorations"): return o
    raise KeyError(n)
placed = []   # (x,y,r) pour eviter les collisions
def inst(kind, n, x, y, rz=0.0, s=1.0, sx=None, reg=None):
    s0 = src(n); o = bpy.data.objects.new("BB_ASM_"+n.split("_",1)[1] if False else "BB_ASM_"+n, s0.data)
    o.location = (x, y, 0); o.rotation_euler = (0, 0, rz); o.scale = (s*(sx or 1), s, s)
    SUB[kind].objects.link(o)
    if reg: placed.append((x, y, reg*s))
    return o
def free(x, y, r): return all((x-px)**2 + (y-py)**2 >= (r+pr)**2 for px,py,pr in placed)
def in_arena(x, y, m=0): return abs(x) < 46+m and abs(y-CY) < 43+m
def on_path(x, y): return abs(x) < 10 and y < CY-30
# --- sol ---
me = bpy.data.meshes.new("BB_ASM_Ground"); me.from_pydata([(-170,CY-170,-0.05),(170,CY-170,-0.05),(170,CY+150,-0.05),(-170,CY+150,-0.05)],[],[(0,1,2,3)])
me.materials.append(mat("Grass")); g = bpy.data.objects.new("BB_ASM_Ground", me); SUB["Ground"].objects.link(g)
# --- tours aux 4 coins (porte vers l'exterieur) ---
TX, TY = 41, 37
for nm, sx, sy in (("TOWER_01_KeepPyramid",-1,-1),("TOWER_02_KeepBattlement",1,-1),("TOWER_03_RoundDrum",1,1),("TOWER_04_RuinedTower",-1,1)):
    dx, dy = sx, sy; th = math.atan2(-dx, dy)
    inst("Towers", nm, sx*TX, CY+sy*TY, th, 1.0, reg=12)
# --- cloture : 4 cotes, portail au sud ---
def fence_line(x0, y0, x1, y1, rz, skip=None):
    L = math.hypot(x1-x0, y1-y0); n = max(1, round(L/4)); sc = L/(n*4)
    for i in range(n):
        t = (i+0.5)/n; x = x0+(x1-x0)*t; y = y0+(y1-y0)*t
        if skip and skip(x, y): continue
        r = rng.random()
        kind = "FENCE_01_PicketStraight" if r < 0.55 else ("FENCE_02_PostRail" if r < 0.78 else ("FENCE_05_Broken" if r < 0.86 else "FENCE_06_StoneWall"))
        inst("Fences", kind, x, y, rz, 1.0, sx=sc)
for side in (-1, 1):
    seg = [(-34,-7),(7,34)] if side == -1 else [(-34,34)]
    for a, b_ in seg: fence_line(a, CY+side*TY, b_, CY+side*TY, math.pi if side == -1 else 0.0)
for side in (-1, 1): fence_line(side*TX, CY-30, side*TX, CY+30, math.pi/2*(1 if side==-1 else -1))
inst("Fences", "FENCE_03_Gate", 0, CY-TY, math.pi)
for sx in (-1, 1): inst("Fences", "FENCE_07_StonePillar", sx*7.6, CY-TY, 0.0, 0.8)
for sx in (-1, 1):  # muret de pierre en fond (nord) : 2 sections par cote pour l'ambiance
    pass
# --- chemin depuis le portail vers le sud ---
y0 = CY - TY - 3
inst("Paths", "PATH_05_Flagstones", 0, y0+5, math.pi)           # seuil dallage
y = y0 - 5
for i in range(3): inst("Paths", "PATH_01_DirtStraight", 0, y - i*10.5, math.pi)
yc = y - 3*10.5 - 5.5
inst("Paths", "PATH_03_DirtCross", 0, yc)
inst("Paths", "PATH_02_DirtCurve", 4.2+2, yc-6-0, math.pi)       # depart vers le sud-est
inst("Paths", "PATH_01_DirtStraight", -6, yc-2, math.pi/2)       # branche ouest
inst("Paths", "PATH_04_StepStones", 16, yc-6, math.pi/2)
inst("Paths", "PATH_07_PlankWalk", 0, yc-8, math.pi)
inst("Paths", "PATH_06_Cobblestone", -10.5, y0-2, 0.0)
# --- decorations (zones fixes) ---
for sx in (-1, 1):
    inst("Decorations", "DECOR_04_LampPost", sx*9.5, CY-TY-4, 0)
    inst("Decorations", "DECOR_10_Banner", sx*13.5, CY-TY-2, 0.0)
    inst("Decorations", "DECOR_04_LampPost", sx*7.5, y0-14, 0); inst("Decorations", "DECOR_04_LampPost", sx*7.5, y0-30, 0)
inst("Decorations", "DECOR_03_SignPost", 8, yc+7, 0.6)
camp = (-28, CY-TY-30)
inst("Decorations", "DECOR_07_Campfire", camp[0], camp[1], 0, reg=4); inst("Decorations", "DECOR_06_Bench", camp[0]-5.5, camp[1], math.pi/2, reg=3); inst("Decorations", "DECOR_06_Bench", camp[0], camp[1]-5.5, 0, reg=3); inst("Decorations", "DECOR_01_Barrel", camp[0]+6, camp[1]+3, 0, reg=2.5)
cart = (27, CY-TY-27)
inst("Decorations", "DECOR_09_Cart", cart[0], cart[1], 0.5, reg=6); inst("Decorations", "DECOR_05_HayBale", cart[0]+8, cart[1]+1, 0.3, reg=3); inst("Decorations", "DECOR_05_HayBale", cart[0]+11, cart[1]-2, 1.0, reg=3); inst("Decorations", "DECOR_02_CrateStack", cart[0]-2, cart[1]-7, 0.4, reg=4)
inst("Decorations", "DECOR_08_Well", 56, CY+5, 0, reg=5)
inst("Decorations", "DECOR_01_Barrel", -TX-9, CY-TY+4, 0, reg=2.5); inst("Decorations", "DECOR_02_CrateStack", TX+9, CY+TY-3, 2.0, reg=4); inst("Decorations", "DECOR_01_Barrel", TX+8, CY-TY+3, 1.0, reg=2.5)
# --- foret ---
SP = [("TREE_01_Oak",7.5,3), ("TREE_02_Pine",5.5,4), ("TREE_03_Birch",4.5,3), ("TREE_04_AutumnMaple",6.5,2), ("TREE_06_BushTree",5.5,2), ("TREE_05_DeadTree",3.5,0.6)]
W = [w for _,_,w in SP]
count = 0
for _ in range(6000):
    if count >= 130: break
    x = rng.uniform(-125, 125); y = rng.uniform(CY-125, CY+115)
    if in_arena(x, y, 8) or on_path(x, y) or (abs(x) < 16 and y < CY-30 and y > yc-60): continue
    d = math.hypot(x, y-CY)
    n, r, _w = rng.choices(SP, weights=W)[0]
    if y > CY+TY+6 and n.startswith("TREE_04"): continue
    if d > 85 and rng.random() < 0.35: n, r = "TREE_02_Pine", 5.5      # fond : plus de pins
    s = rng.uniform(0.85, 1.3)
    if not free(x, y, r*s): continue
    inst("Trees", n, x, y, rng.uniform(0, 6.28), s, reg=r); count += 1
# --- rochers ---
RK = ["ROCK_01_Boulder","ROCK_03_RockPile","ROCK_05_RockCluster","ROCK_06_SmallRocks","ROCK_04_FlatSlab","ROCK_02_Menhir"]
c = 0
for _ in range(2000):
    if c >= 26: break
    x = rng.uniform(-110,110); y = rng.uniform(CY-100, CY+100)
    if in_arena(x, y, 4) or on_path(x, y): continue
    n = rng.choices(RK, weights=[3,3,3,5,2,1])[0]; s = rng.uniform(0.8,1.3)
    if not free(x, y, 4.5*s): continue
    inst("Rocks", n, x, y, rng.uniform(0,6.28), s, reg=4.5); c += 1
# --- vegetation : au pied des arbres, le long des clotures et du chemin ---
VG = [("VEG_01_Bush",3),("VEG_02_BerryBush",1),("VEG_03_TallGrass",4),("VEG_04_GrassTuft",5),("VEG_05_Fern",3),("VEG_08_Mushrooms",1)]
c = 0
for _ in range(4000):
    if c >= 150: break
    x = rng.uniform(-115,115); y = rng.uniform(CY-110, CY+105)
    if in_arena(x, y, 2) or abs(x) < 3.5 and y < CY-30: continue
    n = rng.choices([a for a,_ in VG], weights=[w for _,w in VG])[0]; s = rng.uniform(0.8,1.4)
    if not free(x, y, 1.6*s): continue
    inst("Vegetation", n, x, y, rng.uniform(0,6.28), s); c += 1
for i in range(30):   # fleurs le long du chemin
    x = rng.choice((-1,1))*rng.uniform(5.5,10); yy = rng.uniform(yc-45, y0)
    inst("Vegetation", rng.choice(("VEG_06_Daisies","VEG_07_Tulips")), x, yy, rng.uniform(0,6.28), rng.uniform(.9,1.3))
for i in range(28):   # lierre/buissons contre la cloture
    side = rng.choice((-1,1)); xx = rng.uniform(-33,33); 
    if abs(xx) < 8 and side == -1: continue
    inst("Vegetation", "VEG_01_Bush", xx, CY+side*(TY+2.6), rng.uniform(0,6.28), rng.uniform(.7,1.0))
tot = sum(len(c_.objects) for c_ in SUB.values()); print("instances:", tot, {k: len(v.objects) for k, v in SUB.items()})
