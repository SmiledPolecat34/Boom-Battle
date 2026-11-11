# Genere src/shared/ExteriorLayouts.luau (3 tailles) a partir de layout.py. Repere Roblox : (X,Y,Z) = (-bx, bz, by) ; yaw = rz.
exec(open(r"C:\Users\steve\Boom-Battle\tools\blender\classicmap\layout.py").read())
SIZES = {"Small": 24, "Medium": 36, "Large": 52}
lines = ["--!strict", "-- GENERE par tools/blender/classicmap/export_layouts.py : ne pas editer a la main.",
         "-- Disposition du decor exterieur ClassicMap par taille d'arene. Arene centree en (0,0,0), sol jouable a Y = 0, portail au sud (-Z).",
         "-- Chaque placement : { modele, x, z, yaw (rad), echelle, echelleX }. Les modeles sont les FBX BB_EXT_<modele>.", "", "export type Placement = { string | number }", "", "return table.freeze({"]
for name, h in SIZES.items():
    P = build_layout(h, h)
    lines.append("\t%s = {" % name)
    for p in P:
        lines.append('\t\t{ "%s", %.2f, %.2f, %.3f, %.2f, %.3f },' % (p["m"], -p["x"], p["y"], p["rz"], p["s"], p["sx"]))
    lines.append("\t},")
lines.append("})")
open(r"C:\Users\steve\Boom-Battle\src\shared\ExteriorLayouts.luau", "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
print({k: len(build_layout(h, h)) for k, h in SIZES.items()})
