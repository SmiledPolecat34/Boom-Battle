# Materiaux procéduraux ClassicMap (couleur de base PROV_EXT_* x detail procedural) -> utilises pour cuire les albedo
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\bb_lib.py").read())
KIND = {"StoneLight":"stone","StoneMid":"stone","StoneDark":"stone","StoneMoss":"moss",
        "WoodLight":"wood","WoodMid":"wood","WoodDark":"wood","Metal":"metal","MetalLight":"metal",
        "RoofRed":"roof","RoofDark":"roof","Window":"flat","ClothRed":"cloth","ClothYellow":"cloth",
        "LeafMid":"leaf","LeafLight":"leaf","LeafDark":"leaf","LeafAutumn":"leaf","Bark":"bark","BarkLight":"bark",
        "BirchBark":"birch","BirchMark":"flat","Dirt":"dirt","DirtDark":"dirt","Straw":"straw","Flame":"flat",
        "FlowerRed":"petal","FlowerYellow":"petal","FlowerWhite":"petal","FlowerPurple":"petal","Grass":"leaf","ArenaFloor":"dirt"}
def _n(nt, t, **kw):
    n = nt.nodes.new(t)
    for k, v in kw.items(): setattr(n, k, v)
    return n
def tex_mat(key):
    name = "MATX_EXT_" + key
    if name in bpy.data.materials: return bpy.data.materials[name]
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    out = _n(nt, "ShaderNodeOutputMaterial"); bsdf = _n(nt, "ShaderNodeBsdfPrincipled"); nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Roughness"].default_value = 0.9
    tc = _n(nt, "ShaderNodeTexCoord"); kind = KIND[key]
    def mapping(sc):
        mp = _n(nt, "ShaderNodeMapping"); mp.inputs["Scale"].default_value = sc; nt.links.new(tc.outputs["Object"], mp.inputs["Vector"]); return mp
    def noise(sc, mp_scale, detail=6, rough=0.55):
        mp = mapping(mp_scale); nz = _n(nt, "ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = sc; nz.inputs["Detail"].default_value = detail; nz.inputs["Roughness"].default_value = rough
        nt.links.new(mp.outputs[0], nz.inputs["Vector"]); return nz.outputs["Fac"]
    def ramp(fac, lo, hi):
        r = _n(nt, "ShaderNodeValToRGB"); r.color_ramp.elements[0].color = (lo,lo,lo,1); r.color_ramp.elements[1].color = (hi,hi,hi,1)
        nt.links.new(fac, r.inputs["Fac"]); return r.outputs["Color"]
    def mul(a, b):
        mx = _n(nt, "ShaderNodeMix", data_type='RGBA', blend_type='MULTIPLY'); mx.inputs[0].default_value = 1.0
        nt.links.new(a, mx.inputs[6]) if not isinstance(a, tuple) else None
        nt.links.new(b, mx.inputs[7]); return mx.outputs[2]
    base = _n(nt, "ShaderNodeRGB"); base.outputs[0].default_value = PAL[key] + (1,)
    col = base.outputs[0]
    if kind in ("stone","moss"):
        mp = mapping((1,1,1)); vo = _n(nt, "ShaderNodeTexVoronoi", feature='DISTANCE_TO_EDGE'); vo.inputs["Scale"].default_value = 1.4
        nt.links.new(mp.outputs[0], vo.inputs["Vector"]); crack = ramp(vo.outputs["Distance"], 0.55, 1.0)
        # compresser les fissures vers le haut (seuil)
        col = mul(col, crack); col = mul(col, ramp(noise(3.5,(1,1,1),8,0.6), 0.78, 1.08)); col = mul(col, ramp(noise(28,(1,1,1),2,0.5), 0.92, 1.05))
        if kind == "moss": col = mul(col, ramp(noise(9,(1,1,1),6,0.6), 0.7, 1.2))
    elif kind == "wood":
        col = mul(col, ramp(noise(3,(1,1,9),6,0.6), 0.62, 1.1)); col = mul(col, ramp(noise(14,(9,1,1),3,0.5), 0.88, 1.04))
        col = mul(col, ramp(noise(2.0,(1,1,1),4,0.5), 0.9, 1.05))
    elif kind in ("bark","birch"):
        col = mul(col, ramp(noise(4,(1,1,0.45),8,0.65), 0.45 if kind=="bark" else 0.8, 1.15)); col = mul(col, ramp(noise(18,(1,1,0.3),3,0.5), 0.85, 1.05))
    elif kind == "leaf":
        col = mul(col, ramp(noise(2.0,(1,1,1),6,0.55), 0.72, 1.12)); col = mul(col, ramp(noise(14,(1,1,1),4,0.5), 0.9, 1.06))
    elif kind == "dirt":
        col = mul(col, ramp(noise(2.5,(1,1,1),8,0.6), 0.7, 1.12)); col = mul(col, ramp(noise(22,(1,1,1),4,0.5), 0.85, 1.07))
        mp = mapping((1,1,1)); vo = _n(nt, "ShaderNodeTexVoronoi", feature='DISTANCE_TO_EDGE'); vo.inputs["Scale"].default_value = 3.0
        nt.links.new(mp.outputs[0], vo.inputs["Vector"]); col = mul(col, ramp(vo.outputs["Distance"], 0.8, 1.02))
    elif kind == "straw":
        col = mul(col, ramp(noise(5,(1,1,22),6,0.6), 0.6, 1.15)); col = mul(col, ramp(noise(14,(14,1,1),3,0.5), 0.85, 1.05))
    elif kind == "metal":
        col = mul(col, ramp(noise(16,(1,1,1),8,0.6), 0.72, 1.1)); col = mul(col, ramp(noise(4,(30,1,1),3,0.5), 0.85, 1.05))
    elif kind == "roof":
        mp = mapping((1,1,1)); br = _n(nt, "ShaderNodeTexBrick"); br.inputs["Scale"].default_value = 0.9; br.inputs["Mortar Size"].default_value = 0.03
        br.inputs["Color1"].default_value = (1,1,1,1); br.inputs["Color2"].default_value = (0.82,0.82,0.82,1); br.inputs["Mortar"].default_value = (0.45,0.45,0.45,1)
        nt.links.new(mp.outputs[0], br.inputs["Vector"]); col = mul(col, br.outputs["Color"]); col = mul(col, ramp(noise(5,(1,1,1),6,0.6), 0.85, 1.08))
    elif kind == "cloth":
        wv = _n(nt, "ShaderNodeTexWave"); wv.inputs["Scale"].default_value = 12; wv.inputs["Distortion"].default_value = 1.5
        nt.links.new(mapping((1,1,1)).outputs[0], wv.inputs["Vector"]); col = mul(col, ramp(wv.outputs["Fac"], 0.82, 1.05)); col = mul(col, ramp(noise(8,(1,1,1),4,0.5), 0.88, 1.06))
    elif kind == "petal":
        col = mul(col, ramp(noise(8,(1,1,1),4,0.5), 0.85, 1.08))
    nt.links.new(col, bsdf.inputs["Base Color"])
    return m
