# ClassicMap/Exterior/Paths + Decorations - v2
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
PG = group("Paths"); DG = group("Decorations"); clear(PG); clear(DG)
PM = ["Dirt","DirtDark","StoneLight","StoneMid","StoneDark","StoneMoss","WoodLight","WoodMid","WoodDark","LeafMid","LeafLight","Metal"]
DM = ["WoodLight","WoodMid","WoodDark","Metal","MetalLight","StoneLight","StoneMid","StoneDark","Straw","Flame","ClothRed","Window","StoneMoss","LeafMid","RoofRed"]

# ---------------- CHEMINS ----------------
def slab(b, c, s, k, rng, rz=0.0, j=0.07):
    box(b, c, s, k, rz=rz, taper=0.93, jit=j, rng=rng)
def dirt_path(b, rng, length, width, turn, edge=True):
    steps = 10; L = []; R = []; rad = length/turn if turn else None
    for i in range(steps+1):
        t = i/steps
        if turn: th = turn*t; cx = rad*(1-math.cos(th)); cy = rad*math.sin(th); nx, ny = math.cos(th), -math.sin(th)
        else: cx = 0; cy = t*length; nx, ny = 1, 0
        for side, arr in ((-1,L),(1,R)):
            w = width/2*(1+(rng.uniform(-.1,.1) if 0<i<steps else 0))
            arr.append(Vector((cx+nx*w*side, cy+ny*w*side, 0)))
    h = 0.25
    for i in range(steps):
        k = "Dirt" if i%3 else "DirtDark"
        a,bb,c,d = L[i],R[i],R[i+1],L[i+1]
        up = lambda p: Vector((p.x,p.y,h))
        for (p,q) in ((a,d),(c,bb)):
            b.bm.faces.new([b.bm.verts.new(p), b.bm.verts.new(q), b.bm.verts.new(up(q)), b.bm.verts.new(up(p))]).material_index = b.I["DirtDark"]
        b.bm.faces.new([b.bm.verts.new(up(a)),b.bm.verts.new(up(bb)),b.bm.verts.new(up(c)),b.bm.verts.new(up(d))]).material_index = b.I[k]
    bmesh.ops.remove_doubles(b.bm, verts=b.bm.verts, dist=0.001)
    if edge:
        for arr in (L,R):
            for i in range(0,steps+1):
                p = arr[i]; blob(b,(p.x,p.y,h*0.7),rng.uniform(0.28,0.5),rng.choice(("StoneMid","StoneLight","StoneDark")),rng,0.6,0.25,1)
def cross(b, rng):
    for c in [(0,0),(4,0),(-4,0),(0,4),(0,-4)]:
        box(b,(c[0],c[1],0.125),(4.0-0.05,4.0-0.05,0.25),"Dirt" if rng.random()>0.3 else "DirtDark",jit=0.04,rng=rng)
    for i in range(14):
        a=rng.uniform(0,6.28); r=rng.uniform(2.4,6.3); blob(b,(r*math.cos(a),r*math.sin(a),0.1),rng.uniform(0.25,0.45),"StoneMid",rng,0.6,0.25,1)
def stepstones(b, rng):
    for i in range(6):
        slab(b,(rng.uniform(-0.5,0.5),-5+i*2.0,0.18),(rng.uniform(1.5,2.0),rng.uniform(1.3,1.7),0.36),rng.choice(("StoneLight","StoneMid","StoneDark")),rng,rng.uniform(0,1.5))
        if rng.random()<.5: blob(b,(rng.uniform(-1.4,1.4),-5+i*2.0+rng.uniform(-.8,.8),0.05),0.3,"StoneMoss",rng,0.4,0.2,1)
def flagstones(b, rng):
    for i in range(3):
        for j in range(5):
            slab(b,(-2.0+i*2.0+rng.uniform(-.05,.05),-4+j*2.0+rng.uniform(-.05,.05),0.15),(1.82,1.82,0.3),rng.choice(("StoneLight","StoneMid","StoneLight","StoneDark")),rng,rng.uniform(-.04,.04),0.05)
    for i in range(10): box(b,(rng.uniform(-2.8,2.8),rng.uniform(-4.8,4.8),0.31),(rng.uniform(.3,.7),rng.uniform(.3,.7),0.03),"StoneMoss",rz=rng.uniform(0,3))
def cobble(b, rng):
    for i in range(7):
        for j in range(14):
            x = -3.0 + i*0.95 + (0.47 if j%2 else 0); y = -6.6 + j*0.95
            if x > 3.2: continue
            blob(b,(x+rng.uniform(-.06,.06),y,0.1),0.5,rng.choice(("StoneMid","StoneLight","StoneDark","StoneMid")),rng,0.35,0.12,1)
def planks(b, rng):
    for i in range(10):
        box(b,(0,-4.5+i*0.95,0.35),(4.0,0.85,0.18),rng.choice(("WoodLight","WoodMid")),jit=0.015,rng=rng,rz=rng.uniform(-.015,.015))
        for x in (-1.6,1.6): box(b,(x,-4.5+i*0.95,0.43),(0.12,0.12,0.04),"Metal")
    for x in (-1.7,1.7): box(b,(x,0,0.12),(0.3,9.8,0.25),"WoodDark")
def mkp(name, fn, x, seed):
    rng = random.Random(seed); b = B(PM); fn(b, rng); ob = finish(b, PG, "BB_EXT_PATH_"+name); ob.location = (x, -90, 0)
mkp("01_DirtStraight", lambda b,r: dirt_path(b,r,10,4.2,0), -36, 700)
mkp("02_DirtCurve", lambda b,r: dirt_path(b,r,9,4.2,math.radians(85)), -22, 701)
mkp("03_DirtCross", cross, -4, 702)
mkp("04_StepStones", stepstones, 10, 703)
mkp("05_Flagstones", flagstones, 22, 704)
mkp("06_Cobblestone", cobble, 34, 705)
mkp("07_PlankWalk", planks, 46, 706)

# ---------------- DECORATIONS ----------------
def barrel(b, rng):
    prof = [(1.25,0),(1.6,0.7),(1.85,1.6),(1.6,2.5),(1.25,3.2)]; seg = 14; rings = []
    for r,z in prof: rings.append([b.bm.verts.new((r*math.cos(2*math.pi*k/seg),r*math.sin(2*math.pi*k/seg),z)) for k in range(seg)])
    for i in range(len(prof)-1):
        for k in range(seg): b.bm.faces.new([rings[i][k],rings[i][(k+1)%seg],rings[i+1][(k+1)%seg],rings[i+1][k]]).material_index = b.I["WoodLight" if k%2 else "WoodMid"]
    b.bm.faces.new(rings[0][::-1]).material_index = b.I["WoodDark"]; b.bm.faces.new(rings[-1]).material_index = b.I["WoodMid"]
    for (r,z) in [(1.45,0.45),(1.85,1.15),(1.88,2.05),(1.45,2.75)]: prism(b,(0,0,z-0.12),r+0.1,r+0.1,0.28,14,"Metal")
    prism(b,(0,0,3.19),1.0,1.0,0.06,14,"WoodDark")
def crates(b, rng):
    def crate(c,s,rz):
        box(b,c,s,"WoodLight",rz=rz,taper=0.98)
        for dx in (-1,1):
            for dy in (-1,1): box(b,(c[0]+Rz(rz).to_3x3()@Vector((dx*(s[0]/2-0.15),dy*(s[1]/2-0.15),0))).x*1 if False else (c[0]+(Rz(rz)@Vector((dx*(s[0]/2-0.12),dy*(s[1]/2-0.12),0))).x, c[1]+(Rz(rz)@Vector((dx*(s[0]/2-0.12),dy*(s[1]/2-0.12),0))).y, c[2]),(0.3,0.3,s[2]+0.05),"WoodDark",rz=rz)
        box(b,(c[0],c[1],c[2]+s[2]/2+0.02),(s[0]*0.9,s[1]*0.9,0.08),"WoodMid",rz=rz)
    crate((0,0,1.4),(2.8,2.8,2.8),0.1); crate((3.2,0.6,1.1),(2.2,2.2,2.2),-0.2); crate((0.5,0.1,4.1),(2.2,2.2,2.2),0.5)
def signpost(b, rng):
    tube(b,(0,0,0),(0,0,6.4),0.28,0.24,"WoodDark",6); box(b,(0,0,0.25),(1.0,1.0,0.5),"StoneMid",taper=0.85)
    for z,rz,L,k in ((5.4,0.15,3.4,"WoodLight"),(4.2,-0.2,3.0,"WoodMid")):
        box(b,(0.9*(1 if rz<0 else -1)*-1,0.1,z),(L,0.25,0.95),k,rz=0.0)
        prism(b,(L/2*(1 if rz<0 else -1)*-1+(0.9*(1 if rz<0 else -1)*-1),0.1,z),0.01,0.01,0.01,3,k) if False else None
        box(b,(0.2,0.2,z),(0.2,0.1,0.2),"Metal")
    prism(b,(0,0,6.4),0.5,0.0,0.7,6,"WoodDark")
def lamppost(b, rng):
    prism(b,(0,0,0),1.1,0.8,0.9,8,"StoneDark"); prism(b,(0,0,0.9),0.6,0.5,0.5,8,"Metal"); tube(b,(0,0,1.4),(0,0,6.8),0.24,0.2,"Metal",8)
    prism(b,(0,0,2.0),0.38,0.38,0.35,8,"MetalLight"); 
    box(b,(0,0,7.0),(1.5,1.5,0.35),"Metal"); box(b,(0,0,8.1),(1.0,1.0,1.8),"Flame",taper=0.9)
    for sx,sy in ((1,1),(1,-1),(-1,1),(-1,-1)): tube(b,(sx*0.72,sy*0.72,7.1),(sx*0.62,sy*0.62,9.0),0.07,0.07,"Metal",4)
    prism(b,(0,0,9.0),1.15,0.0,1.1,4,"Metal",math.pi/4); blob(b,(0,0,10.3),0.2,"MetalLight",rng,1,0,1)
def haybale(b, rng):
    M = T((0,0,1.35)) @ Matrix.Rotation(math.pi/2,4,'X')
    b.sub(M, lambda t: prism(t,(0,0,-1.3),1.45,1.45,2.6,14,"Straw"))
    for y in (-0.6,0.6): b.sub(T((0,y,1.35)) @ Matrix.Rotation(math.pi/2,4,'X'), lambda t: prism(t,(0,0,-0.07),1.5,1.5,0.14,14,"WoodDark"))
    for i in range(20):
        a=rng.uniform(0,6.28); y=rng.uniform(-1.4,1.4); tube(b,(1.45*math.cos(a),y,1.35+1.45*math.sin(a)),(1.9*math.cos(a+0.3),y,1.35+1.9*math.sin(a+0.3)),0.04,0.02,"Straw",3)
def bench(b, rng):
    for z in (1.55,1.8): box(b,(0,0,z),(4.4,0.55,0.22),"WoodLight")
    box(b,(0,0.55,1.7),(4.4,0.55,0.22),"WoodLight")
    for z in (2.4,2.9): box(b,(0,0.78,z),(4.4,0.22,0.4),"WoodLight",rz=0.0)
    for x in (-1.8,1.8):
        box(b,(x,0,0.8),(0.3,1.2,1.6),"WoodDark"); box(b,(x,0.78,2.2),(0.3,0.3,2.4),"WoodDark"); box(b,(x,-0.1,1.9),(0.3,1.4,0.25),"WoodDark")
def campfire(b, rng):
    for i in range(9):
        a=i*math.pi*2/9; blob(b,(1.7*math.cos(a),1.7*math.sin(a),0.35),0.62,rng.choice(("StoneMid","StoneDark","StoneLight")),rng,0.75,0.2,1)
    for i in range(5):
        a=i*math.pi*2/5+0.4; tube(b,(1.3*math.cos(a),1.3*math.sin(a),0.35),(-0.1*math.cos(a),-0.1*math.sin(a),1.5),0.26,0.22,"WoodDark",6)
    prism(b,(0,0,0.25),0.9,0.7,0.4,8,"DirtDark") if False else None
    prism(b,(0,0,0.6),0.8,0.0,2.2,6,"Flame"); prism(b,(0.2,0.1,0.6),0.5,0.0,1.5,5,"StoneLight")  # flamme principale / coeur clair
    prism(b,(-0.4,-0.3,0.6),0.4,0.0,1.3,5,"Flame")
def well(b, rng):
    prism(b,(0,0,0),2.9,2.8,0.5,12,"StoneDark")
    for i in range(12):
        a=i*math.pi/6; box(b,(2.4*math.cos(a),2.4*math.sin(a),0.5+1.0),(1.15,1.0,1.9),rng.choice(("StoneLight","StoneMid")),rz=a+math.pi/2,taper=0.96)
    prism(b,(0,0,2.45),2.5,2.5,0.3,12,"StoneLight",0.0,True,True)
    for x in (-2.4,2.4): tube(b,(x,0,0.5),(x,0,7.0),0.28,0.26,"WoodDark",6)
    tube(b,(-2.4,0,4.3),(2.4,0,4.3),0.14,0.14,"Metal",8); prism(b,(0,0,4.3),0.01,0.01,0.01,3,"Metal") if False else None
    box(b,(0,0,3.7),(0.1,0.1,0.1),"Metal")
    prism(b,(0,0,6.9),3.9,0.0,2.6,4,"RoofRed",math.pi/4)
    tube(b,(0,0,4.3),(0,0,2.6),0.04,0.04,"Metal",4); prism(b,(0,0,2.1),0.5,0.4,0.55,8,"WoodMid")
def cart(b, rng):
    box(b,(0,0,2.0),(6.0,3.0,0.3),"WoodMid"); 
    for s in (-1,1): box(b,(0,s*1.4,2.9),(6.0,0.25,1.7),"WoodLight"); 
    box(b,(-2.85,0,2.9),(0.25,3.0,1.7),"WoodLight"); box(b,(2.85,0,2.9),(0.25,3.0,1.7),"WoodLight")
    for i in range(5): box(b,(-2.4+i*1.2,1.4,2.9),(0.14,0.3,1.8),"WoodDark"); box(b,(-2.4+i*1.2,-1.4,2.9),(0.14,0.3,1.8),"WoodDark")
    for s in (-1,1):
        M = T((0.2,s*1.85,1.5)) @ Matrix.Rotation(math.pi/2,4,'X')
        b.sub(M, lambda t: (prism(t,(0,0,-0.18),1.5,1.5,0.36,14,"WoodDark"), prism(t,(0,0,-0.24),0.35,0.35,0.48,8,"Metal"), prism(t,(0,0,-0.21),1.62,1.62,0.1,14,"Metal")))
        for i in range(4): 
            a=i*math.pi/4; b.sub(M@Rz(a), lambda t: box(t,(0,0,0),(2.9,0.18,0.3),"WoodMid"))
    tube(b,(-3.0,0,2.2),(-6.5,0,1.0),0.2,0.2,"WoodDark",6); tube(b,(-3.0,0.9,2.2),(-6.5,0.9,1.0),0.15,0.15,"WoodDark",5); tube(b,(-3.0,-0.9,2.2),(-6.5,-0.9,1.0),0.15,0.15,"WoodDark",5)
    for i in range(5): blob(b,(-1.5+rng.uniform(-1,1)*0.9,rng.uniform(-1,1)*0.8,2.4+rng.uniform(0,.5)),rng.uniform(0.5,0.8),"Straw",rng,0.7,0.2,1)
def banner(b, rng):
    tube(b,(0,0,0),(0,0,9.0),0.22,0.18,"WoodDark",6); box(b,(0,0,0.3),(1.1,1.1,0.6),"StoneMid",taper=0.85); tube(b,(-1.9,0,8.6),(1.9,0,8.6),0.12,0.12,"WoodDark",5)
    quad(b,[(-1.7,0.0,8.5),(1.7,0.0,8.5),(1.7,0.0,4.8),(0.0,0.0,4.0),(-1.7,0.0,4.8)][:4],"ClothRed")
    quad(b,[(-1.7,0.0,4.8),(0.0,0.0,4.0),(1.7,0.0,4.8)],"ClothRed")
    box(b,(0,0.04,6.8),(1.1,0.05,1.1),"Straw",rz=math.pi/4)
def mkd(name, fn, x, seed):
    rng = random.Random(seed); b = B(DM); fn(b, rng); ob = finish(b, DG, "BB_EXT_DECOR_"+name); ob.location = (x, -30, 0)
for i,(n,f) in enumerate([("01_Barrel",barrel),("02_CrateStack",crates),("03_SignPost",signpost),("04_LampPost",lamppost),("05_HayBale",haybale),("06_Bench",bench),("07_Campfire",campfire),("08_Well",well),("09_Cart",cart),("10_Banner",banner)]):
    mkd(n,f,-45+i*11,800+i)
report(PG); report(DG)
