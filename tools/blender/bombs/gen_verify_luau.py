"""Genere verify_import_<ID>.luau (verification Studio d'un import FBX) depuis le manifeste exporte (variante PC).
Usage : python gen_verify_luau.py <ID> <Nom> <piece distinctive> <gx> <gz> [piece de centrage]   (case de pose = decalage en cases par rapport a B01_Classique)"""
import json, sys, re, os
bid, name, distinct, gx, gz = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
center = sys.argv[6] if len(sys.argv) > 6 else distinct   # piece qui sert a centrer la bombe sur la case
root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
man = json.load(open(os.path.join(root, "assets/3D/BOOM_BATTLE_ART/05_EXPORTS_ROBLOX/BOMBES", f"{bid}_{name}_Manifest.json"), encoding="utf-8"))["PC"]
parts = {p["name"]: p for p in man["parts"]}
anc = parts["BombCollar_Base"]["bbox_center_roblox_studs"]
rows = []
for n, p in parts.items():
    s, c = p["size_studs_roblox"], p["bbox_center_roblox_studs"]
    rel = [round(c[i] - anc[i], 3) for i in range(3)]
    tr = p.get("transparency", 0.0)
    rows.append("\t%s = { size = Vector3.new(%s, %s, %s), rel = Vector3.new(%s, %s, %s), color = \"%s\", mat = \"%s\"%s }," % (n, *s, *rel, p["diag_color"], p.get("roblox_material", "SmoothPlastic"), (", transp = %s" % tr) if tr else ""))
t = open(os.path.join(os.path.dirname(__file__), "verify_template.luau"), encoding="utf-8").read()
a, b = t.index("local expected = {"), t.index("local lines, allOk")
t = t[:a] + "local expected = {\n" + "\n".join(rows) + "\n}\n\n" + t[b:]
t = t.replace("__ID___NAME_", f"{bid}_{name}").replace("__ID__", bid).replace("__NAME__", name)
t = t.replace("__CENTER__", center).replace("__DISTINCT__", distinct).replace("__GX__", str(gx)).replace("__GZ__", str(gz))
t = re.sub(r"Taille totale = .*?attendu ~ [^)]*\)", "Taille totale = (%.3f, %.3f, %.3f) (attendu ~ " + " , ".join(f"{x:.3f}" for x in man["size_studs_roblox"]) + ")", t)
open(os.path.join(os.path.dirname(__file__), f"verify_import_{bid}.luau"), "w", encoding="utf-8").write(t)
print(f"verify_import_{bid}.luau :", len(rows), "pieces")
