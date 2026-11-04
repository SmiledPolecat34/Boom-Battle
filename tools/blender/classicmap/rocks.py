# ClassicMap/Exterior/Rocks - v2 : rochers facettes (coupes planes), strates, mousse
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
G = group("Rocks"); clear(G)
MATS = ["StoneLight","StoneMid","StoneDark","StoneMoss","LeafMid","LeafLight","LeafDark"]

def rock(b, c, size, rng, cuts=6, sub=2, noise=0.14, flat=1.0, moss=0.55, rot=0.0, base=-0.35):
    g = bmesh.ops.create_icosphere(b.bm, subdivisions=sub, radius=1.0); vs = g["verts"]
    planes = []
    for i in range(cuts):
        n = Vector((rng.uniform(-1,1), rng.uniform(-1,1), rng.uniform(-0.3,1))).normalized(); planes.append((n, rng.uniform(0.62,0.85)))
    R = Rz(rot).to_3x3()
    for v in vs:
        p = v.co * (1 + rng.uniform(-noise, noise))
        for n, d in planes:
            dd = p.dot(n)
            if dd > d: p = p - (dd-d)*n
        p.z = max(p.z, base)
        v.co = R @ Vector((p.x*size[0], p.y*size[1], p.z*size[2]*flat)) + Vector(c)
    zs = [v.co.z for v in vs]; z0, z1 = min(zs), max(zs)
    for f in {f for v in vs for f in v.link_faces}:
        f.normal_update(); zc = sum(v.co.z for v in f.verts)/len(f.verts); t = (zc - z0)/max(0.01, z1-z0)
        if f.normal.z > 0.65: k = "StoneMoss" if rng.random() < moss else "StoneLight"
        else: k = "StoneDark" if t < 0.30 else ("StoneMid" if t < 0.65 else "StoneLight")
        if rng.random() < 0.08: k = "StoneDark" if k != "StoneDark" else "StoneMid"
        f.material_index = b.I[k]

def tuft(b, c, rng, n=6, h=1.2):
    for i in range(n):
        a = rng.uniform(0,6.28); r = rng.uniform(0,0.4)
        x, y = c[0] + r*math.cos(a), c[1] + r*math.sin(a); hh = rng.uniform(0.6,1.0)*h; k = rng.choice(("LeafMid","LeafLight","LeafDark"))
        for back in (False, True):
            pts = [(x-0.15*math.cos(a), y-0.15*math.sin(a), c[2]), (x+0.15*math.cos(a), y+0.15*math.sin(a), c[2]), (x+0.35*math.cos(a+1.5)+0.12, y+0.35*math.sin(a+1.5), c[2]+hh)]
            vv = [b.bm.verts.new(p) for p in pts]; vv = vv[::-1] if back else vv
            b.bm.faces.new(vv).material_index = b.I[k]

def mk(name, fn, x, seed):
    rng = random.Random(seed); b = B(MATS); fn(b, rng); ob = finish(b, G, "BB_EXT_ROCK_"+name); ob.location = (x, -270, 0)

def boulder(b, rng):
    rock(b,(0,0,0),(5.5,4.8,5.0),rng,7,2,0.12); rock(b,(4.6,1.6,-1.0),(2.6,2.3,2.2),rng,5,2,0.15); rock(b,(-3.8,-2.6,-1.4),(2.0,1.8,1.7),rng,5,1,0.15)
    tuft(b,(0.4,0.2,4.4),rng,6,1.3)
def menhir(b, rng):
    rock(b,(0,0,0),(2.6,2.1,7.0),rng,9,2,0.08,1.0,0.25,0.0,-0.5); rock(b,(1.9,0.9,0),(1.1,1.0,1.0),rng,4,1)
    for i in range(3): box(b,(0.0,-1.9,2.0+i*1.6),(0.9-0.15*i,0.12,0.22),"StoneDark",rz=0.0)
def pile(b, rng):
    rock(b,(0,0,0),(3.6,3.2,2.2),rng,6); rock(b,(-0.5,0.2,2.0),(2.7,2.4,1.8),rng,6); rock(b,(0.3,-0.2,3.7),(1.8,1.6,1.3),rng,5); rock(b,(3.4,0.8,-0.5),(1.4,1.3,1.1),rng,4,1)
def slab(b, rng):
    rock(b,(0,0,0),(5.4,3.8,1.5),rng,6,2,0.07,1.0,0.5); rock(b,(1.4,0.6,1.2),(3.2,2.4,0.8),rng,5,2,0.07,1.0,0.5,0.6)
def cluster(b, rng):
    for c,s in [((0,0,0),(2.9,2.6,2.3)),((3.3,1.2,-0.3),(1.9,1.7,1.5)),((-2.8,1.8,-0.5),(1.5,1.4,1.2)),((1.2,-3.0,-0.6),(1.7,1.4,1.3)),((-1.8,-2.4,-0.7),(1.0,1.0,0.9)),((4.6,-1.4,-0.8),(0.9,0.8,0.7))]:
        rock(b,c,s,rng,5,1,0.2)
def pebbles(b, rng):
    rock(b,(0,0,0),(1.5,1.3,1.0),rng,4,1,0.18)
    for i in range(6): a=i*1.05+rng.uniform(-.3,.3); rock(b,(2.0*math.cos(a)*rng.uniform(.8,1.4),2.0*math.sin(a)*rng.uniform(.8,1.4),-0.1),(0.45,0.4,0.3),rng,3,1,0.2,1.0,0.3)
for i,(n,f) in enumerate([("01_Boulder",boulder),("02_Menhir",menhir),("03_RockPile",pile),("04_FlatSlab",slab),("05_RockCluster",cluster),("06_SmallRocks",pebbles)]):
    mk(n,f,-45+i*18,400+i)
report(G)
