# ClassicMap/Exterior/Vegetation - v2
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
G = group("Vegetation"); clear(G)
MATS = ["LeafDark","LeafMid","LeafLight","LeafAutumn","Bark","FlowerRed","FlowerYellow","FlowerWhite","FlowerPurple","StoneLight","StoneDark","ClothRed","WoodLight","Dirt","Straw"]

def blade(b, x, y, h, w, bend, ang, key, segs=3):
    ca, sa = math.cos(ang), math.sin(ang)
    def P(dx, t):  # t 0..1 ; courbure vers l'avant
        s = h*t; fwd = bend*t*t*h*0.55; ww = dx*(1-0.85*t)
        return (x + ww*(-sa) + fwd*ca, y + ww*ca + fwd*sa, s*(1-0.12*t*t))
    L = [P(-w/2, i/segs) for i in range(segs+1)]; R = [P(w/2, i/segs) for i in range(segs+1)]
    for back in (False, True):
        vl = [b.bm.verts.new(p) for p in L]; vr = [b.bm.verts.new(p) for p in R]
        for i in range(segs):
            q = [vl[i], vr[i], vr[i+1], vl[i+1]] if i < segs-1 else [vl[i], vr[i], vl[i+1]]
            if back: q = q[::-1]
            b.bm.faces.new(q).material_index = b.I[key]

def tuftgen(b, rng, n, hmin, hmax, wid, spread, keys=("LeafDark","LeafMid","LeafLight"), bend=(0.2,1.0)):
    for i in range(n):
        a = rng.uniform(0, 6.28); r = spread*math.sqrt(rng.random())
        blade(b, r*math.cos(a), r*math.sin(a), rng.uniform(hmin, hmax), wid*rng.uniform(.8,1.2), rng.uniform(*bend), a + rng.uniform(-.5,.5), rng.choice(keys))

def leafy(b, c, R, rng, n, keys=("LeafDark","LeafMid","LeafLight")):
    for i in range(n):
        a = rng.uniform(0,6.28); rr = R*math.sqrt(rng.random()); z = rng.uniform(-0.3,0.7)*R
        k = keys[2] if z > 0.35*R else (keys[1] if z > 0 else keys[0])
        blob(b, (c[0]+rr*math.cos(a), c[1]+rr*math.sin(a), c[2]+z), R*rng.uniform(0.3,0.5), k, rng, 0.8, 0.22, 1)

def flower(b, x, y, h, kind, k, rng):
    tube(b, (x,y,0), (x+rng.uniform(-.1,.1),y+rng.uniform(-.1,.1),h), 0.07, 0.05, "LeafDark", 4)
    for s in (-1,1): blade(b, x, y, h*0.45, 0.35, 0.8, rng.uniform(0,6.28), "LeafMid", 2)
    if kind == "daisy":
        for i in range(8):
            a = i*math.pi/4; box(b,(x+0.32*math.cos(a), y+0.32*math.sin(a), h),(0.4,0.14,0.05),"FlowerWhite",rz=a)
        blob(b,(x,y,h+0.03),0.2,"FlowerYellow",rng,0.8,0.0,1)
    elif kind == "tulip":
        prism(b,(x,y,h-0.55),0.12,0.42,0.9,6,k,0.0,True,False); prism(b,(x,y,h+0.3),0.42,0.0,0.4,6,k,0.0,False,False)
    else:
        blob(b,(x,y,h),0.38,k,rng,0.7,0.1,1)
        for i in range(5): a=i*1.256; blob(b,(x+0.38*math.cos(a),y+0.38*math.sin(a),h-0.05),0.2,k,rng,0.7,0.0,1)

def mk(name, fn, x, seed):
    rng = random.Random(seed); b = B(MATS); fn(b, rng); ob = finish(b, G, "BB_EXT_VEG_"+name); ob.location = (x, -150, 0)

def bush(b, rng):
    leafy(b,(0,0,1.6),2.9,rng,16); leafy(b,(2.0,0.8,1.2),1.7,rng,8); leafy(b,(-1.9,-0.7,1.1),1.6,rng,8)
def berry(b, rng):
    leafy(b,(0,0,1.6),2.6,rng,14,("LeafDark","LeafMid","LeafMid"))
    for i in range(22):
        a=rng.uniform(0,6.28); r=rng.uniform(0.8,2.5); blob(b,(r*math.cos(a),r*math.sin(a),rng.uniform(1.0,2.6)),0.2,"FlowerRed",rng,1.0,0.0,1)
def tallgrass(b, rng): tuftgen(b,rng,26,2.2,4.0,0.5,0.9,("LeafDark","LeafMid","LeafLight"),(0.3,1.2))
def tuft(b, rng): tuftgen(b,rng,18,0.9,1.7,0.5,0.5,("LeafMid","LeafLight"),(0.4,1.0))
def fern(b, rng):
    for i in range(7):
        a = i*6.283/7 + rng.uniform(-.2,.2); L = rng.uniform(2.6,3.4); ca,sa = math.cos(a),math.sin(a)
        prev = Vector((0,0,0.1))
        for s in range(1,6):
            t = s/5; p = Vector((ca*L*t*0.85, sa*L*t*0.85, 0.5 + L*0.55*math.sin(t*2.0) - 0.3*t*t*L))
            tube(b,prev,p,0.07*(1.2-t),0.06*(1.2-t),"LeafDark",4)
            for sd in (-1,1):
                w = 0.75*(1-0.7*t); d = Vector((-sa,ca,0))*sd*w
                quad(b,[tuple(prev),tuple(prev+d*0.9+Vector((0,0,-0.1))),tuple(p+d*0.8+Vector((0,0,-0.1))),tuple(p)],"LeafMid" if s%2 else "LeafLight")
            prev = p
def daisy(b, rng):
    for i in range(7): a=i*0.9; r=0.4+0.55*(i%3); flower(b,r*math.cos(a),r*math.sin(a),rng.uniform(1.1,1.7),"daisy","FlowerWhite",rng)
def tulip(b, rng):
    cols=("FlowerRed","FlowerYellow","FlowerPurple")
    for i in range(8): a=i*0.78; r=0.3+0.6*(i%3); flower(b,r*math.cos(a),r*math.sin(a),rng.uniform(1.2,1.9),"tulip",cols[i%3],rng)
def mushrooms(b, rng):
    for (x,y,s) in [(0,0,1.0),(1.2,0.6,0.7),(-0.9,0.9,0.55),(0.5,-1.1,0.75),(-1.3,-0.5,0.45)]:
        prism(b,(x,y,0),0.32*s,0.26*s,1.2*s,7,"Straw",0.0,True,True)
        blob(b,(x,y,1.2*s),0.95*s,"FlowerRed",rng,0.5,0.05,1)
        for i in range(4): a=rng.uniform(0,6.28); blob(b,(x+0.5*s*math.cos(a),y+0.5*s*math.sin(a),1.2*s+0.33*s),0.12*s,"FlowerWhite",rng,0.6,0.0,1)
def cattails(b, rng):
    for i in range(9):
        a=rng.uniform(0,6.28); r=rng.uniform(0.0,1.2); x,y=r*math.cos(a),r*math.sin(a); h=rng.uniform(4.2,6.2)
        tube(b,(x,y,0),(x+rng.uniform(-.4,.4),y+rng.uniform(-.4,.4),h),0.09,0.06,"LeafMid",4)
        top = (x,y,h); tube(b,(x,y,h-1.0),(x,y,h+0.6),0.2,0.2,"Bark",6)
    tuftgen(b,rng,14,2.2,4.0,0.35,1.2,("LeafMid","LeafLight"),(0.2,0.7))
def ivy(b, rng):   # panneau de lierre pour mur 4x4
    for i in range(9):
        x = rng.uniform(-1.6,1.6); tube(b,(x,0,0.1),(x+rng.uniform(-.6,.6),0.05,rng.uniform(2.5,3.8)),0.08,0.05,"Bark",4)
    for i in range(44):
        x=rng.uniform(-1.9,1.9); z=rng.uniform(0.3,3.8); a=rng.uniform(0,6.28); s=rng.uniform(0.35,0.65); k=rng.choice(("LeafDark","LeafMid","LeafLight"))
        c=(x,0.08+0.02*rng.random(),z); d=(math.cos(a)*s,0,math.sin(a)*s); e=(-math.sin(a)*s*0.6,0,math.cos(a)*s*0.6)
        quad(b,[(c[0],c[1],c[2]),(c[0]+d[0]+e[0],c[1],c[2]+d[2]+e[2]),(c[0]+2*d[0],c[1],c[2]+2*d[2]),(c[0]+d[0]-e[0],c[1],c[2]+d[2]-e[2])],k)
specs = [("01_Bush",bush),("02_BerryBush",berry),("03_TallGrass",tallgrass),("04_GrassTuft",tuft),("05_Fern",fern),("06_Daisies",daisy),("07_Tulips",tulip),("08_Mushrooms",mushrooms),("09_Cattails",cattails),("10_IvyPanel",ivy)]
for i,(n,f) in enumerate(specs): mk(n,f,-40+i*9,600+i)
report(G)
