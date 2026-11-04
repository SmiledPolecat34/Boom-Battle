# ClassicMap/Exterior/Towers - 4 tours de pierre differentes (v2 detaillee)
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
LOD = globals().get("LOD", 0)
G = group("Towers", "ExteriorMobile" if LOD else "Exterior"); clear(G)
MATS = ["StoneLight","StoneMid","StoneDark","StoneMoss","WoodMid","WoodDark","Metal","RoofRed","RoofDark","Window","ClothRed","ClothYellow","WoodLight"]

def tower(name, n, a0, a1, H, roof, seed, flag="ClothRed", ruin=False, door=True):
    rng = random.Random(seed); b = B(MATS); I = b.I
    phase = math.pi/2 - math.pi/n
    Rr = lambda a: a / math.cos(math.pi/n)
    z0 = 2.8
    ap = lambda z: a0 + (a1-a0)*max(0.0, min(1.0, (z-z0)/(H-z0)))
    # soubassement 2 gradins
    prism(b,(0,0,0),Rr(a0+1.9),Rr(a0+1.7),1.5,n,"StoneDark",phase)
    prism(b,(0,0,1.5),Rr(a0+1.2),Rr(a0+1.05),z0-1.5,n,"StoneMid",phase)
    # noyau du fut
    prism(b,(0,0,z0),Rr(a0),Rr(a1),H-z0,n,"StoneMid",phase)
    # appareil de pierres
    ch = 3.2 if LOD else 1.6; courses = int((H - z0 - 0.4)/ch)
    win_c = ({2, 5, 7} if H > 26 else {2, 4}) if LOD else ({4, 8, 12} if H > 26 else {3, 6})
    for c in range(courses):
        zc = z0 + 0.2 + ch*(c+0.5); a = ap(zc)
        for f in range(n):
            th = 2*math.pi*f/n                      # f=0 : face +Y
            fw = 2*a*math.tan(math.pi/n) - 0.35
            k = max(1, round(fw/(3.8 if LOD else 2.3))); bw = fw/k
            e = [-fw/2 + i*bw for i in range(k+1)]
            if c % 2: e = [-fw/2] + [-fw/2 + bw/2 + i*bw for i in range(k)] + [fw/2]
            for i in range(len(e)-1):
                w = e[i+1]-e[i]
                if w < 0.5: continue
                p = rng.uniform(0.10,0.26)
                if f == 0 and door and zc < z0+7.8 and abs((e[i]+e[i+1])/2) < 2.9: continue
                if f != 0 and c in win_c and abs((e[i]+e[i+1])/2) < 1.1 and n == 4: continue
                r = rng.random(); low = 1.0 - min(1.0,(zc-z0)/14)
                key = "StoneMoss" if r < 0.05+0.14*low*(2 if ruin else 1) else ("StoneLight" if r < 0.40 else ("StoneMid" if r < 0.78 else "StoneDark"))
                loc = Rz(th) @ Vector(((e[i]+e[i+1])/2, a + p/2 - 0.03, zc))
                box(b, loc, (w-0.08, p, ch-0.09), key, rz=th, taper=0.94, bev=0.0)
    # fenetres en arc (sur les faces carrees ou 4 faces cardinales du fut rond)
    def window(t, a, zc):
        box(t,(0,a+0.28,zc),(2.5,0.6,4.0),"StoneLight",taper=0.96)
        box(t,(0,a+0.60,zc-0.2),(1.0,0.2,2.8),"Window")
        prism(t,(0,0,0),0.55,0.55,0.2,8,"Window")  # placeholder remplace ci-dessous
    for f in range(n):
        if n != 4 and f % 3: continue
        th = 2*math.pi*f/n
        for c in win_c:
            if f == 0 and door and c < 4: continue
            zc = z0 + 0.2 + ch*(c+0.5); a = ap(zc)
            def build(t, a=a, zc=zc):
                box(t,(0,a+0.30,zc),(2.6,0.62,4.2),"StoneLight",bev=0.0)
                box(t,(0,a+0.62,zc-0.35),(1.1,0.22,2.7),"Window")
                M = T((0,a+0.62,zc+1.0)) @ Matrix.Rotation(math.pi/2,4,'X')
                t.sub(M, lambda u: prism(u,(0,0,0),0.55,0.55,0.22,10,"Window"))
                M2 = T((0,a+0.30,zc+2.1)) @ Matrix.Rotation(math.pi/2,4,'X')
                t.sub(M2, lambda u: prism(u,(0,0,0),1.3,1.3,0.62,10,"StoneLight"))
            b.sub(Rz(th), build)
    # porte + perron (face 0)
    if door:
        def porch(t):
            a = a0
            box(t,(0,a+1.9,1.4),(5.2,3.4,2.8),"StoneMid",bev=0.0)       # palier
            box(t,(0,a+4.1,0.55),(5.2,1.2,1.1),"StoneMid"); 
            box(t,(0,a+3.4,1.65),(5.0,1.2,0.3),"StoneLight")
            zb = 2.8
            box(t,(0,a+0.4,zb+2.9),(4.4,0.7,5.8),"StoneLight")           # encadrement
            box(t,(0,a+0.74,zb+2.5),(3.0,0.2,5.0),"WoodDark")            # vantail
            t.sub(T((0,a+0.74,zb+5.0)) @ Matrix.Rotation(math.pi/2,4,'X'), lambda u: prism(u,(0,0,0),1.5,1.5,0.2,12,"WoodDark"))
            t.sub(T((0,a+0.40,zb+5.8)) @ Matrix.Rotation(math.pi/2,4,'X'), lambda u: prism(u,(0,0,0),2.3,2.3,0.7,12,"StoneLight"))
            for zz in (zb+1.3, zb+3.6):  # ferrures
                box(t,(0,a+0.88,zz),(3.0,0.1,0.3),"Metal")
            for x in (-1.0,1.0): box(t,(x,a+0.88,zb+2.5),(0.25,0.1,5.0),"WoodMid")
        b.sub(Matrix.Identity(4), porch)
    # bandeau + machicoulis + parapet
    aH = ap(H)
    prism(b,(0,0,H-1.1),Rr(aH+0.55),Rr(aH+0.55),0.7,n,"StoneDark",phase)
    for f in range(n):
        th = 2*math.pi*f/n; fw = 2*(aH+1.5)*math.tan(math.pi/n)
        kc = max(2, round(fw/(3.2 if LOD else 1.9)))
        for i in range(kc):
            x = -fw/2 + fw*(i+0.5)/kc
            loc = Rz(th) @ Vector((x, aH+0.55, H-0.35))
            box(b, loc, (0.95, 0.9, 1.9), "StoneDark", rz=th, taper=1.55)
    ao = aH + 1.5
    prism(b,(0,0,H+0.55),Rr(ao),Rr(ao),0.7,n,"StoneMid",phase)
    prism(b,(0,0,H+0.5),Rr(ao-0.1),Rr(ao-0.1),0.3,n,"StoneDark",phase)
    mer_gap = set()
    if ruin:
        mer_gap = {(f,i) for f in range(n) for i in range(8) if rng.random() < 0.45}
    for f in range(n):
        th = 2*math.pi*f/n; fw = 2*ao*math.tan(math.pi/n)
        km = max(2, round(fw/3.0))
        loc = Rz(th) @ Vector((0, ao-0.45, H+1.75))
        if not ruin or rng.random() < 0.6:
            box(b, loc, (fw-0.05, 0.9, 1.0), "StoneMid", rz=th, bev=0.0)
        for i in range(km):
            if (f,i) in mer_gap: continue
            x = -fw/2 + fw*(i+0.5)/km
            hh = 2.0 if not ruin else rng.uniform(0.8,2.2)
            loc = Rz(th) @ Vector((x, ao-0.45, H+2.2+hh/2-0.5))
            box(b, loc, (fw/km*0.52, 1.0, hh), "StoneLight", rz=th, taper=0.92)
    # sommets
    if roof == "pyramid":
        h0 = H + 1.1
        prism(b,(0,0,h0),Rr(aH-1.2),Rr(aH-1.4),3.0,n,"StoneMid",phase)
        for i in range(n):  # petites ouvertures de tourelle
            th = 2*math.pi*i/n + 0
        rz0 = h0 + 3.0; Rb = Rr(aH+0.1); steps = 6
        for s in range(steps):
            r_a = Rb*(1 - s/steps) + 0.3; r_b = Rb*(1-(s+1)/steps) + 0.15*(s<steps-1)
            prism(b,(0,0,rz0+ s*1.1),r_a,max(r_b,0.0 if s==steps-1 else r_b),1.15,n,"RoofDark" if s%3==2 else "RoofRed",phase)
        zt = rz0 + steps*1.1
        tube(b,(0,0,zt),(0,0,zt+4.2),0.13,0.1,"WoodDark")
        quad(b,[(0.1,0,zt+4.1),(2.9,0.4,zt+3.6),(2.9,0.4,zt+2.2),(0.1,0,zt+2.4)],flag)
    elif roof == "cone":
        h0 = H + 1.1
        prism(b,(0,0,h0),Rr(aH-1.0),Rr(aH-1.2),3.4,n,"StoneMid",phase)
        rz0 = h0 + 3.4; Rb = Rr(aH+0.5); steps = 7
        for s in range(steps):
            r_a = Rb*(1 - s/steps) + 0.3; r_b = Rb*(1-(s+1)/steps)
            prism(b,(0,0,rz0+s*1.05),r_a,r_b,1.1,n,"RoofDark" if s%3==2 else "RoofRed",phase)
        zt = rz0 + steps*1.05
        tube(b,(0,0,zt),(0,0,zt+4.5),0.13,0.1,"WoodDark")
        quad(b,[(0.1,0,zt+4.4),(3.0,0.3,zt+3.9),(3.0,0.3,zt+2.5),(0.1,0,zt+2.7)],flag)
    elif roof == "flat":
        # cage d'escalier + brasero
        def turret(t):
            box(t,(ao-2.6,ao-2.6,H+1.1),(4.2,4.2,5.0),"StoneMid",bev=0.0)
            for i in range(4): box(t,(ao-2.6+ (1.9 if i%2 else -1.9)*(1 if i<2 else 0), ao-2.6+(1.9 if i%2 else -1.9)*(0 if i<2 else 1), H+3.9),(1.0,1.0,0.9),"StoneLight")
            prism(t,(ao-2.6,ao-2.6,H+3.6),3.5,0.0,3.0,4,"RoofRed",math.pi/4)
            box(t,(ao-2.6,ao-0.4,H+2.0),(1.3,0.4,2.2),"WoodDark")
        b.sub(Matrix.Identity(4), turret)
        prism(b,(-1.8,-1.8,H+1.2),0.9,1.15,0.9,8,"Metal")
        for i in range(3): box(b,(-1.8+0.25*(i-1),-1.8,H+2.3+0.1*i),(0.5,0.5,0.8-0.1*i),"ClothYellow",rz=i)
        tube(b,(-ao+1.2,-ao+1.2,H+1.2),(-ao+1.2,-ao+1.2,H+7.0),0.14,0.1,"WoodDark")
        quad(b,[(-ao+1.2,-ao+1.2,H+6.9),(-ao+4.1,-ao+1.5,H+6.4),(-ao+4.1,-ao+1.5,H+4.9),(-ao+1.2,-ao+1.2,H+5.1)],flag)
    elif roof == "ruin":
        for i in range(10):
            a_ = rng.uniform(0,6.28); r_ = rng.uniform(0,ao*0.6)
            blob(b,(r_*math.cos(a_),r_*math.sin(a_),H+1.2),rng.uniform(0.7,1.4),rng.choice(("StoneMid","StoneDark","StoneMoss")),rng,0.7,0.25,1)
    if ruin or roof == "ruin":
        for i in range(22):   # eboulis au pied
            a_ = rng.uniform(0,6.28); r_ = Rr(a0)+rng.uniform(1.8,5.2)
            sz = rng.uniform(0.5,1.7)
            blob(b,(r_*math.cos(a_),r_*math.sin(a_),sz*0.25),sz,rng.choice(("StoneMid","StoneDark","StoneLight","StoneMoss")),rng,0.6,0.28,1)
    return finish(b, G, name)

specs = [("01_KeepPyramid",4,6.2,5.2,30,"pyramid",11,"ClothRed",False),
         ("02_KeepBattlement",4,6.2,5.3,28,"flat",12,"ClothYellow",False),
         ("03_RoundDrum",12,5.9,5.0,30,"cone",13,"ClothYellow",False),
         ("04_RuinedTower",4,6.2,5.4,24,"ruin",14,"ClothRed",True)]
for i,(nm,n,a0,a1,H,roof,seed,flag,ruin) in enumerate(specs):
    if LOD and n == 12: n = 8
    ob = tower(("BB_EXT_MOB_TOWER_" if LOD else "BB_EXT_TOWER_")+nm, n, a0, a1, H, roof, seed, flag, ruin)
    ob.location = (-60 + i*30, -459 if LOD else -434, 0)
report(G)
