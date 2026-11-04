# ClassicMap/Exterior/Fences - v2 : clotures bois + pierre (sections de 4 studs, pivot au centre)
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
G = group("Fences"); clear(G)
MATS = ["WoodLight","WoodMid","WoodDark","Metal","MetalLight","StoneLight","StoneMid","StoneDark","StoneMoss","LeafMid"]

def post(b, x, y, h=4.6, w=0.8, k="WoodDark", cap=True):
    box(b,(x,y,h/2),(w,w,h),k,taper=0.96)
    if cap: prism(b,(x,y,h),w*0.78,0.05,0.65,4,k,math.pi/4)
    box(b,(x,y,0.35),(w+0.25,w+0.25,0.7),"StoneMid",taper=0.88)   # sabot de pierre
def picket(b, x, y, h, w=0.55, k="WoodLight", rz=0.0):
    box(b,(x,y,h/2),(w,0.28,h),k,rz=rz)
    prism(b,(x,y,h),w*0.72,0.04,0.42,4,k,math.pi/4+rz)
def nail(b,x,y,z): box(b,(x,y,z),(0.14,0.1,0.14),"Metal")
def span(b, x0, x1, y=0, picket_h=3.4, style="picket", broken=False, rng=None):
    L = x1-x0; xm = (x0+x1)/2
    for z in (1.3, 2.9): box(b,(xm,y+0.32,z),(L,0.28,0.5),"WoodMid")
    n = 6
    for i in range(n):
        x = x0 + L*(i+0.5)/n; h = picket_h + (rng.uniform(-0.15,0.15) if rng else 0)
        if broken and i in (2,3):
            picket(b,x,y,h*0.55 if i==2 else 0.9,0.5,"WoodLight",rz=0.0); continue
        picket(b,x,y,h)
        nail(b,x,y+0.18,1.3); nail(b,x,y+0.18,2.9)
def mk(name, fn, x, seed):
    rng = random.Random(seed); b = B(MATS); fn(b, rng); ob = finish(b, G, "BB_EXT_FENCE_"+name); ob.location = (x, -210, 0)

def picket_straight(b, rng): post(b,-2,0); post(b,2,0); span(b,-1.6,1.6,0,rng=rng)
def post_rail(b, rng):
    post(b,-2,0,3.8,0.7); post(b,2,0,3.8,0.7)
    for z in (1.1,2.0,2.9): 
        tube(b,(-2,0.0,z),(2,0.0,z+(0.06 if z>2 else 0)),0.2,0.2,"WoodMid",6)
def gate(b, rng):
    post(b,-4,0,5.6,1.0); post(b,4,0,5.6,1.0)
    for s in (-1,1):
        cx = s*2.05
        for z in (0.9, 4.2): box(b,(cx,0,z),(3.5,0.3,0.42),"WoodMid")
        for i in range(5): box(b,(cx-1.5+i*0.75,0,2.55),(0.4,0.26,3.5 if i%2==0 else 3.4),"WoodLight")
        tube(b,(cx-s*1.7,0.22,1.0),(cx+s*1.7,0.22,4.2),0.17,0.17,"WoodDark",4)
        for z in (1.2,3.9): box(b,(s*3.4,0.28,z),(1.6,0.12,0.3),"Metal"); box(b,(s*3.9,0.28,z),(0.35,0.2,0.5),"MetalLight")
    box(b,(0,0.2,2.55),(0.6,0.2,0.7),"Metal"); box(b,(0,0.3,2.55),(0.3,0.15,0.3),"MetalLight")
    box(b,(0,0,6.1),(8.6,0.5,0.35),"WoodDark",taper=1.0)  # linteau
def corner(b, rng):
    post(b,0,0,5.0,1.0)
    for z in (1.3,2.9):
        box(b,(2.0,0.0,z),(3.6,0.28,0.5),"WoodMid"); box(b,(0.0,2.0,z),(0.28,3.6,0.5),"WoodMid")
    for i in range(3):
        picket(b,0.9+i*1.0,0,3.4); picket(b,0,0.9+i*1.0,3.4,rz=math.pi/2)
def broken(b, rng):
    post(b,-2,0); post(b,2,0,2.6,0.8,"WoodDark",False)
    for z in (1.3,): box(b,(0,0.32,z),(4,0.28,0.5),"WoodMid")
    box(b,(-0.9,0.35,2.9),(2.2,0.28,0.45),"WoodMid",rz=0.0)
    tube(b,(0.6,0.2,2.0),(2.2,0.2,0.2),0.18,0.16,"WoodMid",5)
    for i in range(6):
        x=-1.7+i*0.68
        if i in (3,4): picket(b,x,0,rng.uniform(0.5,1.4),0.5); continue
        picket(b,x,0,3.4 if i<3 else 2.2)
    picket(b,1.0,1.0,0.5,0.5,"WoodLight",rz=1.3)
def stonewall(b, rng):
    base_w = 1.7
    for row,z in enumerate((0.55,1.55,2.55)):
        x = -2.0; 
        while x < 1.95:
            w = min(rng.uniform(1.0,1.6), 2.0 - x)
            if 2.0-x-w < 0.55: w = 2.0 - x
            h = rng.uniform(0.85,1.0)
            k = rng.choice(("StoneLight","StoneMid","StoneMid","StoneDark"))
            box(b,(x+w/2,rng.uniform(-0.06,0.06),z),(w-0.07,base_w-0.2*row,h),k,rz=rng.uniform(-0.04,0.04),taper=0.96,jit=0.03,rng=rng); x += w
    for i in range(4): box(b,(-1.5+i*1.0,0,3.25),(0.96,1.3,0.45),rng.choice(("StoneLight","StoneMid")),taper=0.9,jit=0.03,rng=rng)
    for i in range(5): box(b,(rng.uniform(-1.8,1.8),0.0,3.5),(rng.uniform(.2,.5),.4,.2),"StoneMoss",rz=rng.uniform(0,3))
def pillar(b, rng):
    box(b,(0,0,0.5),(2.6,2.6,1.0),"StoneDark",taper=0.9)
    for i in range(5): box(b,(0,0,1.9+i*1.2),(2.0-0.06*i,2.0-0.06*i,1.15),rng.choice(("StoneLight","StoneMid")),rz=rng.uniform(-.05,.05),taper=0.97)
    box(b,(0,0,8.0),(2.8,2.8,0.6),"StoneLight",taper=0.85); prism(b,(0,0,8.4),0.9,0.0,0.7,12,"StoneMid")
    blob(b,(0,0,9.2),0.65,"StoneLight",rng,1.0,0.03,2)
    for i in range(3): box(b,(rng.uniform(-.8,.8),rng.uniform(-1.0,-0.9),1.2+i*0.8),(.5,.1,.35),"StoneMoss")
for i,(n,f) in enumerate([("01_PicketStraight",picket_straight),("02_PostRail",post_rail),("03_Gate",gate),("04_Corner",corner),("05_Broken",broken),("06_StoneWall",stonewall),("07_StonePillar",pillar)]):
    mk(n,f,-48+i*14,500+i)
report(G)
