# ClassicMap/Exterior/Trees - v2 detaillee
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
G = group("Trees"); clear(G)
MATS = ["Bark","BarkLight","BirchBark","BirchMark","LeafDark","LeafMid","LeafLight","LeafAutumn","StoneMoss"]

def trunk(b, prof, key, seg=8, lean=(0,0), twist=0.0, rng=None):
    """prof = [(z, r), ...]; lean = decalage (x,y) en haut; renvoie centres des anneaux"""
    top = prof[-1][0]; rings = []; centers = []
    for (z, r) in prof:
        t = (z/top)**1.6
        cx, cy = lean[0]*t, lean[1]*t
        centers.append(Vector((cx, cy, z)))
        rings.append([b.bm.verts.new((cx + r*(1+ (rng.uniform(-.08,.08) if rng else 0))*math.cos(2*math.pi*k/seg + twist*z),
                                       cy + r*(1+ (rng.uniform(-.08,.08) if rng else 0))*math.sin(2*math.pi*k/seg + twist*z), z)) for k in range(seg)])
    mi = b.I[key]
    for i in range(len(prof)-1):
        for k in range(seg):
            b.bm.faces.new([rings[i][k], rings[i][(k+1)%seg], rings[i+1][(k+1)%seg], rings[i+1][k]]).material_index = mi
    b.bm.faces.new(rings[0][::-1]).material_index = mi; b.bm.faces.new(rings[-1]).material_index = mi
    return centers

def roots(b, r, n, rng, key="Bark"):
    for i in range(n):
        a = i*2*math.pi/n + rng.uniform(-0.3,0.3); L = r*rng.uniform(2.0,2.8)
        tube(b, (r*0.5*math.cos(a), r*0.5*math.sin(a), 1.1), (L*math.cos(a), L*math.sin(a), -0.15), r*0.45, r*0.12, key, 5)

def clump(b, c, R, rng, n, keys=("LeafDark","LeafMid","LeafLight"), sq=0.8, hgt=None):
    for i in range(n):
        a = rng.uniform(0, 2*math.pi); rr = R*math.sqrt(rng.random()); zz = rng.uniform(-0.35, 0.65)*R*sq
        p = (c[0] + rr*math.cos(a), c[1] + rr*math.sin(a), c[2] + zz)
        h = (zz/(R*sq) + 0.35)            # haut = clair
        k = keys[2] if h > 0.7 else (keys[1] if h > 0.25 else keys[0])
        if rng.random() < 0.15: k = keys[1]
        blob(b, p, R*rng.uniform(0.38, 0.6), k, rng, sq, 0.22, 1)

def oak(rng):
    b = B(MATS)
    c = trunk(b, [(0,2.3),(1.2,1.7),(3.5,1.45),(7,1.3),(10,1.2)], "Bark", 9, (0.8,0.4), 0.05, rng)
    roots(b, 1.8, 5, rng)
    limbs = [(-4.2, 0.6, 14.0, 4.6), (4.6, -0.8, 13.6, 4.4), (0.4, 4.0, 15.0, 4.0), (0.2, -3.6, 14.4, 3.8), (0.8, 0.4, 17.2, 4.3)]
    for (x,y,z,R) in limbs:
        tube(b, (c[-1].x, c[-1].y, 8.6), (x*0.7, y*0.7, z-3), 0.85, 0.3, "Bark", 6)
        clump(b, (x,y,z), R, rng, 11)
    clump(b, (0.5,0.2,12.2), 5.6, rng, 14)
    return b

def pine(rng):
    b = B(MATS)
    trunk(b, [(0,1.5),(2,1.1),(10,0.7),(21,0.3)], "Bark", 8, (0,0), 0.0, rng)
    z = 3.2; seg = 12
    tiers = [(6.2,6.0),(5.4,5.6),(4.6,5.2),(3.8,4.8),(3.0,4.4),(2.2,4.0),(1.4,3.4)]
    for i,(r,h) in enumerate(tiers):
        k = "LeafDark" if i%2==0 else "LeafMid"
        ring = []
        for j in range(seg):
            a = 2*math.pi*j/seg + i*0.25; rr = r*(1.0 if j%2==0 else 0.72)
            ring.append(b.bm.verts.new((rr*math.cos(a), rr*math.sin(a), z - (0.5 if j%2==0 else -0.1))))
        tip = b.bm.verts.new((0,0,z+h))
        for j in range(seg): b.bm.faces.new([ring[j], ring[(j+1)%seg], tip]).material_index = b.I[k]
        b.bm.faces.new(ring[::-1]).material_index = b.I["LeafDark"]
        z += h*0.58
    return b

def birch(rng):
    b = B(MATS)
    c = trunk(b, [(0,1.0),(1.5,0.85),(5,0.75),(9,0.65),(12,0.55)], "BirchBark", 8, (-1.0,0.6), 0.02, rng)
    for i in range(12):   # marques sombres
        z = rng.uniform(0.8,11); a = rng.uniform(0,6.28); cc = min(range(len(c)), key=lambda j: abs(c[j].z - z))
        r = 0.85; p = Vector((c[cc].x + r*math.cos(a), c[cc].y + r*math.sin(a), z))
        box(b, p, (0.22, rng.uniform(0.5,1.1), 0.22), "BirchMark", rz=a)
    top = c[-1]
    for (dx,dy,dz,L) in [(-2.4,0.6,5.5,0.5),(2.4,-0.6,5.0,0.5),(0.4,-2.6,4.5,0.5)]:
        tube(b, (top.x,top.y,top.z-2.5), (top.x+dx, top.y+dy, top.z-2.5+dz), 0.35, 0.12, "BirchBark", 5)
    for (dx,dy,dz,R) in [(-0.5,0.2,15.2,3.2),(-2.6,0.8,12.6,2.6),(2.2,-0.6,12.4,2.8),(0.0,-2.7,11.2,2.4),(-1.2,2.0,12.0,2.4)]:
        clump(b, (top.x+dx, top.y+dy, dz), R, rng, 8, ("LeafMid","LeafLight","LeafLight"), 0.9)
    return b

def maple(rng):
    b = B(MATS)
    c = trunk(b, [(0,1.7),(1,1.3),(4,1.15),(6.5,1.0)], "Bark", 8, (0,0.3), 0.0, rng)
    roots(b, 1.3, 4, rng)
    for (x,y,z,R) in [(-2.8,0,9.6,3.6),(2.8,0.6,9.4,3.5),(0,-2.8,9.8,3.4),(0.2,2.8,10.0,3.2),(0,0,12.0,4.0)]:
        tube(b, (0,0.2,5.6), (x*0.6,y*0.6,z-2.2), 0.6, 0.25, "Bark", 6)
        clump(b, (x,y,z), R, rng, 9, ("LeafAutumn","LeafAutumn","LeafLight"), 0.85)
    return b

def dead(rng):
    b = B(MATS)
    c = trunk(b, [(0,1.8),(1.3,1.3),(4,1.0),(7,0.75),(9.5,0.4)], "Bark", 7, (1.0,-0.4), 0.12, rng)
    roots(b, 1.5, 4, rng)
    for (an, z, L, up) in [(0.3,4.2,4.2,0.8),(2.4,5.5,3.8,0.9),(4.4,6.4,3.2,1.1),(5.4,3.0,2.8,0.5),(1.4,7.6,2.4,1.2)]:
        p0 = Vector((c[min(len(c)-1, int(z/2.5))].x, c[min(len(c)-1, int(z/2.5))].y, z))
        p1 = p0 + Vector((math.cos(an)*L, math.sin(an)*L, up*L*0.7))
        tube(b, p0, p1, 0.42, 0.12, "Bark", 5)
        p2 = p1 + Vector((math.cos(an+0.7)*L*0.4, math.sin(an+0.7)*L*0.4, L*0.5)); tube(b, p1, p2, 0.12, 0.04, "BarkLight", 4)
        p3 = p1 + Vector((math.cos(an-0.8)*L*0.35, math.sin(an-0.8)*L*0.35, L*0.4)); tube(b, p1, p3, 0.1, 0.03, "BarkLight", 4)
    for i in range(3): blob(b, (rng.uniform(-1.6,1.6), rng.uniform(-1.6,1.6), 0.3), rng.uniform(0.35,0.7), "StoneMoss", rng, 0.6, 0.2, 1)
    return b

def bushtree(rng):   # petit arbre touffu/ornemental
    b = B(MATS)
    trunk(b, [(0,1.3),(1,0.95),(4,0.85)], "Bark", 7, (0,0), 0.0, rng)
    clump(b, (0,0,7.0), 4.2, rng, 14, ("LeafDark","LeafMid","LeafLight"), 0.95)
    clump(b, (0,0,4.8), 3.8, rng, 8, ("LeafDark","LeafDark","LeafMid"), 0.8)
    return b

specs = [("01_Oak",oak),("02_Pine",pine),("03_Birch",birch),("04_AutumnMaple",maple),("05_DeadTree",dead),("06_BushTree",bushtree)]
for i,(n,fn) in enumerate(specs):
    ob = finish(fn(random.Random(300+i)), G, "BB_EXT_TREE_"+n); ob.location = (-45 + i*18, -330, 0)
report(G)
