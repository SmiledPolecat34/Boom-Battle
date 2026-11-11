"""
Genere src/shared/BombSkinConfig.luau a partir des manifestes d'export des 24 bombes
(assets/3D/BOOM_BATTLE_ART/05_EXPORTS_ROBLOX/BOMBES/Bnn_*_Manifest.json, variante PC).

Pourquoi : les FBX ne portent NI couleur, NI materiau, NI transparence (tout arrive en Plastic gris). Ce style est donc
applique au moment de l'affichage (BombVisuals), d'apres cette config : il ne depend plus de l'etat du lieu Studio et
s'applique aussi aux futurs modeles MOBILE.

Usage : python tools/blender/bombs/gen_bomb_skin_config.py     (depuis la racine du depot)
"""
import glob, json, os, re

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MANIFESTS = os.path.join(ROOT, "assets", "3D", "BOOM_BATTLE_ART", "05_EXPORTS_ROBLOX", "BOMBES")
OUT = os.path.join(ROOT, "src", "shared", "BombSkinConfig.luau")

# B01 : manifeste historique (Phase 3) sans couleurs ; valeurs de b01_classique.py
B01_COLORS = {"BombBody_Base": "23262E", "BombCollar_Base": "5B6373", "BombFuse_Curved": "C8742E", "BombFuse_Tip": "2A1C12"}
# Bombes dont le dessin a un AVANT (+Z Roblox) : le client les tourne vers la camera.
FACES_CAMERA = {"B09_Cosmique", "B11_Crane", "B12_Citrouille", "B16_Ninja", "B17_Coeur", "B18_Etoiles", "B21_Robot", "B24_Cristal"}
# Effets Roblox animes par script (client).
FX = {"B09_Cosmique": "cosmic"}

rows, total = [], 0
for path in sorted(glob.glob(os.path.join(MANIFESTS, "B*_Manifest.json"))):
    base = os.path.basename(path).replace("_Manifest.json", "")
    if not re.match(r"B\d\d_", base):
        continue
    parts = json.load(open(path, encoding="utf-8"))["PC"]["parts"]
    pieces = []
    for p in parts:
        hexcol = (p["diag_color"].lstrip("#") if "diag_color" in p else B01_COLORS[p["name"]]).upper()
        r, g, b = int(hexcol[0:2], 16), int(hexcol[2:4], 16), int(hexcol[4:6], 16)
        mat = p.get("roblox_material", "SmoothPlastic")
        tr = p.get("transparency", 0.0)
        tail = ', %g' % tr if tr else ''
        pieces.append('\t\t\t%s = { %d, %d, %d, "%s"%s },' % (p["name"], r, g, b, mat, tail))
    total += len(pieces)
    extra = ""
    if base in FX:
        extra = '\n\t\tfx = "%s",' % FX[base]
    rows.append('\t%s = {\n\t\tfacesCamera = %s,%s\n\t\tpieces = {\n%s\n\t\t},\n\t},' % (base, "true" if base in FACES_CAMERA else "false", extra, "\n".join(pieces)))

src = '''--!strict
-- GÉNÉRÉ par tools/blender/bombs/gen_bomb_skin_config.py à partir des manifestes d'export : NE PAS ÉDITER À LA MAIN
-- (relancer le générateur après toute modification d'un modèle de bombe).
--
-- Les FBX des bombes ne portent ni couleur, ni matériau, ni transparence : ce style est appliqué à l'affichage par
-- BombVisuals (client). Pièce : { rouge, vert, bleu, "Matériau Roblox" (texte, résolu côté client), transparence? }.
-- facesCamera : le dessin a un AVANT (+Z) que le client tourne vers la caméra. fx : effet animé par script (client).

export type Piece = { any }
export type Skin = { facesCamera: boolean, fx: string?, pieces: { [string]: Piece } }

local BombSkinConfig = {}

-- Matériaux Roblox utilisés par les modèles (garde-fou de validation).
BombSkinConfig.Materials = table.freeze({
	"SmoothPlastic", "Metal", "Neon", "Ice", "Glass", "Wood", "Rock", "Basalt", "Slate", "Grass", "Sand", "Mud",
})

local models: { [string]: Skin } = {
%s
}

function BombSkinConfig.get(modelName: any): Skin?
	if typeof(modelName) ~= "string" then
		return nil
	end
	return models[modelName]
end

-- Noms des modèles décrits (ordre alphabétique : B01..B24).
function BombSkinConfig.modelNames(): { string }
	local names: { string } = {}
	for name in models do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return table.freeze(BombSkinConfig)
''' % "\n".join(rows)
open(OUT, "w", encoding="utf-8", newline="\n").write(src)
print("BombSkinConfig.luau : %d modeles, %d pieces, %d octets -> %s" % (len(rows), total, len(src.encode()), os.path.relpath(OUT, ROOT)))
