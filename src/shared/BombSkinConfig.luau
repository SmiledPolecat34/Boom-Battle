--!strict
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
	B01_Classique = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 35, 38, 46, "SmoothPlastic" },
			BombCollar_Base = { 91, 99, 115, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B02_Rouge = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 200, 40, 40, "SmoothPlastic" },
			BombCollar_Base = { 150, 28, 28, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B03_Bleue = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 40, 110, 220, "SmoothPlastic" },
			BombCollar_Base = { 28, 80, 170, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B04_Verte = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 50, 170, 70, "SmoothPlastic" },
			BombCollar_Base = { 34, 125, 50, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B05_Jaune = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 240, 200, 40, "SmoothPlastic" },
			BombCollar_Base = { 190, 145, 20, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B06_Glacee = {
		facesCamera = false,
		pieces = {
			BombBody_Abyss = { 39, 163, 222, "Ice" },
			BombBody_Deep = { 56, 196, 238, "Ice" },
			BombBody_Mid = { 110, 224, 247, "Ice" },
			BombBody_Light = { 194, 246, 255, "Ice" },
			BombBody_Edge = { 232, 252, 255, "Ice" },
			BombCollar_Base = { 169, 228, 255, "Ice" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B07_Lave = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 255, 154, 31, "Neon" },
			BombSkin_Plates = { 42, 37, 35, "Basalt" },
			BombSkin_PlateEdge = { 255, 74, 18, "Neon" },
			BombCollar_Base = { 47, 47, 54, "Metal" },
			BombFuse_Curved = { 184, 136, 74, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B08_Electrique = {
		facesCamera = false,
		pieces = {
			BombBody_Shell = { 36, 26, 77, "SmoothPlastic" },
			BombBody_CrackGlow = { 42, 107, 255, "Neon" },
			BombBody_CrackCore = { 191, 239, 255, "Neon" },
			BombCollar_Base = { 125, 131, 152, "Metal" },
			BombFuse_Curved = { 201, 143, 74, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B09_Cosmique = {
		facesCamera = true,
		fx = "cosmic",
		pieces = {
			BombShell_Glass = { 138, 92, 224, "Glass", 0.7 },
			BombShell_Frame = { 42, 16, 96, "Metal" },
			BombGalaxy_Core = { 255, 240, 251, "Neon" },
			BombGalaxy_Halo = { 255, 79, 224, "Neon", 0.55 },
			BombGalaxy_ArmsInner = { 255, 91, 230, "Neon" },
			BombGalaxy_ArmsMid = { 214, 47, 209, "Neon" },
			BombGalaxy_ArmsOuter = { 143, 75, 255, "Neon" },
			BombGalaxy_NebulaViolet = { 106, 43, 214, "Neon", 0.55 },
			BombGalaxy_NebulaMagenta = { 195, 47, 214, "Neon", 0.55 },
			BombGalaxy_Stars = { 255, 255, 255, "Neon" },
			BombCollar_Base = { 58, 31, 122, "Metal" },
			BombCollar_Rim = { 255, 122, 240, "Neon" },
			BombFuse_Curved = { 184, 128, 60, "SmoothPlastic" },
			BombFuse_Tip = { 58, 36, 16, "SmoothPlastic" },
			BombSpark_Star = { 255, 214, 250, "Neon" },
		},
	},
	B10_ArcEnCiel = {
		facesCamera = false,
		pieces = {
			BombBody_Band1 = { 142, 36, 170, "SmoothPlastic" },
			BombBody_Band2 = { 30, 136, 229, "SmoothPlastic" },
			BombBody_Band3 = { 67, 160, 71, "SmoothPlastic" },
			BombBody_Band4 = { 253, 216, 53, "SmoothPlastic" },
			BombBody_Band5 = { 251, 140, 0, "SmoothPlastic" },
			BombBody_Band6 = { 229, 57, 53, "SmoothPlastic" },
			BombCollar_Base = { 216, 27, 138, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B11_Crane = {
		facesCamera = true,
		pieces = {
			BombBody_Bone = { 237, 230, 211, "SmoothPlastic" },
			BombBody_Cavity = { 23, 20, 27, "SmoothPlastic" },
			BombCollar_Base = { 42, 42, 46, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B12_Citrouille = {
		facesCamera = true,
		pieces = {
			BombBody_Base = { 240, 138, 28, "SmoothPlastic" },
			BombSkin_Face = { 255, 211, 74, "Neon" },
			BombCollar_Base = { 91, 58, 28, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B13_Football = {
		facesCamera = false,
		pieces = {
			BombBody_White = { 242, 242, 240, "SmoothPlastic" },
			BombBody_Black = { 22, 22, 27, "SmoothPlastic" },
			BombCollar_Base = { 58, 63, 74, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B14_Basketball = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 232, 118, 30, "SmoothPlastic" },
			BombBody_Seams = { 27, 22, 18, "SmoothPlastic" },
			BombCollar_Base = { 74, 58, 46, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B15_Epineuse = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 27, 34, 56, "SmoothPlastic" },
			BombSkin_Spikes = { 185, 191, 203, "Metal" },
			BombCollar_Base = { 75, 81, 96, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B16_Ninja = {
		facesCamera = true,
		pieces = {
			BombBody_Black = { 43, 47, 59, "SmoothPlastic" },
			BombBody_Edge = { 212, 217, 227, "Metal" },
			BombBody_Plateau = { 216, 38, 42, "SmoothPlastic" },
			BombCollar_Base = { 163, 29, 33, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B17_Coeur = {
		facesCamera = true,
		pieces = {
			BombBody_Heart = { 224, 36, 94, "SmoothPlastic" },
			BombBody_Inner = { 255, 143, 177, "SmoothPlastic" },
			BombCollar_Base = { 168, 22, 69, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B18_Etoiles = {
		facesCamera = true,
		pieces = {
			BombBody_Star = { 42, 79, 196, "SmoothPlastic" },
			BombBody_Inner = { 255, 197, 46, "Metal" },
			BombCollar_Base = { 30, 58, 148, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B19_Militaire = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 79, 122, 52, "SmoothPlastic" },
			BombSkin_CamoDark = { 47, 74, 34, "SmoothPlastic" },
			BombSkin_CamoLight = { 169, 181, 107, "SmoothPlastic" },
			BombCollar_Base = { 85, 103, 42, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B20_Tonneau = {
		facesCamera = false,
		pieces = {
			BombBody_Wood = { 168, 105, 58, "SmoothPlastic" },
			BombBody_Lid = { 196, 138, 82, "SmoothPlastic" },
			BombSkin_Hoops = { 154, 163, 178, "Metal" },
			BombCollar_Base = { 94, 58, 32, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B21_Robot = {
		facesCamera = true,
		pieces = {
			BombBody_Shell = { 237, 242, 246, "SmoothPlastic" },
			BombBody_Shell2 = { 212, 221, 231, "SmoothPlastic" },
			BombBody_Dark = { 22, 32, 58, "SmoothPlastic" },
			BombSkin_Dark = { 26, 39, 68, "SmoothPlastic" },
			BombSkin_Glow = { 47, 230, 255, "Neon" },
			BombSkin_Shine = { 168, 243, 255, "Neon" },
			BombCollar_Base = { 36, 48, 73, "Metal" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B22_Nature = {
		facesCamera = false,
		pieces = {
			BombBody_Wood = { 138, 85, 48, "Wood" },
			BombBody_Groove = { 71, 40, 26, "SmoothPlastic" },
			BombBody_Wood2 = { 116, 70, 42, "Wood" },
			BombSkin_LeafA = { 88, 194, 77, "SmoothPlastic" },
			BombSkin_LeafB = { 47, 160, 67, "SmoothPlastic" },
			BombSkin_Petals = { 251, 248, 238, "SmoothPlastic" },
			BombSkin_Core = { 245, 154, 27, "SmoothPlastic" },
			BombCollar_Base = { 221, 171, 94, "Wood" },
			BombFuse_Curved = { 185, 138, 76, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B23_Meteore = {
		facesCamera = false,
		pieces = {
			BombBody_Base = { 107, 74, 43, "Mud" },
			BombSkin_PlateA = { 217, 174, 112, "Sand" },
			BombSkin_PlateB = { 195, 146, 90, "Sand" },
			BombSkin_Rocks = { 94, 58, 34, "Rock" },
			BombCollar_Base = { 76, 85, 112, "Metal" },
			BombFuse_Curved = { 184, 136, 74, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
	B24_Cristal = {
		facesCamera = true,
		pieces = {
			BombBody_Abyss = { 58, 26, 146, "SmoothPlastic" },
			BombBody_Deep = { 106, 47, 224, "SmoothPlastic" },
			BombBody_Mid = { 164, 104, 255, "SmoothPlastic" },
			BombBody_Light = { 220, 194, 255, "SmoothPlastic" },
			BombBody_Edge = { 246, 238, 255, "Neon" },
			BombCollar_Base = { 58, 29, 124, "SmoothPlastic" },
			BombFuse_Curved = { 200, 116, 46, "SmoothPlastic" },
			BombFuse_Tip = { 42, 28, 18, "SmoothPlastic" },
		},
	},
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
