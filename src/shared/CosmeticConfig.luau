--!strict
-- Catalogue des cosmétiques (Bomb Coins uniquement, aucun Robux). Un cosmétique ne change QUE l'apparence :
-- ni zone, ni délai, ni vitesse, ni hitbox. Prix de départ tirés des maquettes de boutique, à équilibrer
-- avec GameConfig.Rewards. Les deux cosmétiques « classique » sont offerts et équipés par défaut.
--
-- Les 24 bombes ont chacune un modèle 3D (champ `model` = nom du modèle dans ReplicatedStorage.BombModels, style dans
-- BombSkinConfig). `color` / `material` ne servent plus que de REPLI (bombe ronde unie si le modèle est introuvable)
-- et de pastille dans les listes. Les identifiants existants (bomb_classic, bomb_red, bomb_blue, bomb_green,
-- bomb_yellow, bomb_ice) et leurs prix sont inchangés : les sauvegardes des joueurs restent valides.
-- PRIX = PROPOSITION (paliers 250 / 400-500 / 600-900 / 1 200-1 500 / 2 000-3 000), à valider par le propriétaire.

export type Kind = "bomb" | "effect"

export type Cosmetic = {
	id: string,
	kind: Kind,
	name: string,
	description: string,
	price: number,
	color: Color3,
	material: Enum.Material?,
	model: string?, -- bombes : nom du modèle 3D (ReplicatedStorage.BombModels)
}

local CosmeticConfig = {}

local function bomb(
	id: string,
	name: string,
	price: number,
	color: Color3,
	material: Enum.Material?,
	description: string,
	model: string
): Cosmetic
	return table.freeze({
		id = id,
		kind = "bomb" :: Kind,
		name = name,
		description = description,
		price = price,
		color = color,
		material = material,
		model = model,
	})
end

local function effect(id: string, name: string, price: number, color: Color3, description: string): Cosmetic
	return table.freeze({ id = id, kind = "effect" :: Kind, name = name, description = description, price = price, color = color, material = nil, model = nil })
end

-- Ordre d'affichage dans la boutique.
local list: { Cosmetic } = {
	-- Bombes (24), du plus accessible au plus rare. Numéro entre crochets = numéro du catalogue 3D (Bnn).
	bomb("bomb_classic", "Classique", 0, Color3.fromRGB(35, 35, 45), Enum.Material.SmoothPlastic, "Une bombe standard, fiable et efficace.", "B01_Classique"), -- B01
	bomb("bomb_red", "Rouge", 250, Color3.fromRGB(200, 40, 40), Enum.Material.SmoothPlastic, "Impossible de la rater.", "B02_Rouge"), -- B02
	bomb("bomb_blue", "Bleue", 250, Color3.fromRGB(40, 110, 220), Enum.Material.SmoothPlastic, "Calme avant l'explosion.", "B03_Bleue"), -- B03
	bomb("bomb_green", "Verte", 250, Color3.fromRGB(50, 170, 70), Enum.Material.SmoothPlastic, "Fraîche et explosive.", "B04_Verte"), -- B04
	bomb("bomb_yellow", "Jaune", 250, Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic, "Brille dans l'arène.", "B05_Jaune"), -- B05
	bomb("bomb_pumpkin", "Citrouille", 400, Color3.fromRGB(240, 138, 28), Enum.Material.SmoothPlastic, "Une citrouille pas si inoffensive.", "B12_Citrouille"), -- B12
	bomb("bomb_football", "Football", 400, Color3.fromRGB(242, 242, 240), Enum.Material.SmoothPlastic, "Un coup de pied pour la victoire.", "B13_Football"), -- B13
	bomb("bomb_basketball", "Basket", 400, Color3.fromRGB(232, 118, 30), Enum.Material.SmoothPlastic, "Un tir à trois points... d'explosion.", "B14_Basketball"), -- B14
	bomb("bomb_military", "Militaire", 400, Color3.fromRGB(79, 122, 52), Enum.Material.SmoothPlastic, "Camouflée, mais pas discrète.", "B19_Militaire"), -- B19
	bomb("bomb_barrel", "Tonneau", 400, Color3.fromRGB(168, 105, 58), Enum.Material.Wood, "Un tonneau qui ne contient pas de rhum.", "B20_Tonneau"), -- B20
	bomb("bomb_ice", "Glacée", 500, Color3.fromRGB(150, 220, 250), Enum.Material.Ice, "Un cristal de glace prêt à éclater.", "B06_Glacee"), -- B06
	bomb("bomb_spiky", "Épineuse", 600, Color3.fromRGB(185, 191, 203), Enum.Material.Metal, "Attention aux piquants !", "B15_Epineuse"), -- B15
	bomb("bomb_heart", "Cœur", 600, Color3.fromRGB(224, 36, 94), Enum.Material.SmoothPlastic, "Une explosion d'amour.", "B17_Coeur"), -- B17
	bomb("bomb_skull", "Crâne", 700, Color3.fromRGB(237, 230, 211), Enum.Material.SmoothPlastic, "Un os à ronger avant qu'il n'explose.", "B11_Crane"), -- B11
	bomb("bomb_stars", "Étoiles", 700, Color3.fromRGB(42, 79, 196), Enum.Material.SmoothPlastic, "Une pluie d'étoiles filantes.", "B18_Etoiles"), -- B18
	bomb("bomb_ninja", "Ninja", 800, Color3.fromRGB(43, 47, 59), Enum.Material.Metal, "Silencieuse et mortelle.", "B16_Ninja"), -- B16
	bomb("bomb_rainbow", "Arc-en-ciel", 900, Color3.fromRGB(253, 216, 53), Enum.Material.SmoothPlastic, "Toutes les couleurs dans une seule bombe.", "B10_ArcEnCiel"), -- B10
	bomb("bomb_robot", "Robot", 1200, Color3.fromRGB(237, 242, 246), Enum.Material.SmoothPlastic, "Un petit robot... bien explosif.", "B21_Robot"), -- B21
	bomb("bomb_nature", "Nature", 1200, Color3.fromRGB(138, 85, 48), Enum.Material.Wood, "La nature reprend ses droits.", "B22_Nature"), -- B22
	bomb("bomb_meteor", "Météore", 1500, Color3.fromRGB(217, 174, 112), Enum.Material.Sand, "Tombée du ciel, ou presque.", "B23_Meteore"), -- B23
	bomb("bomb_crystal", "Cristal", 1500, Color3.fromRGB(147, 85, 240), Enum.Material.SmoothPlastic, "Une gemme à haut potentiel explosif.", "B24_Cristal"), -- B24
	bomb("bomb_lava", "Lave", 2000, Color3.fromRGB(255, 154, 31), Enum.Material.Neon, "Du magma en fusion.", "B07_Lave"), -- B07
	bomb("bomb_electric", "Électrique", 2000, Color3.fromRGB(42, 107, 255), Enum.Material.Neon, "Chargée à bloc !", "B08_Electrique"), -- B08
	bomb("bomb_cosmic", "Cosmique", 3000, Color3.fromRGB(138, 92, 224), Enum.Material.Glass, "Une galaxie prisonnière d'un globe de verre.", "B09_Cosmique"), -- B09

	effect("effect_classic", "Classique", 0, Color3.fromRGB(255, 150, 30), "Un effet d'explosion standard, propre et efficace."),
	effect("effect_red", "Rouge", 250, Color3.fromRGB(240, 50, 40), "Des flammes rouge sang."),
	effect("effect_blue", "Bleu", 250, Color3.fromRGB(60, 150, 255), "Une explosion bleu électrique."),
	effect("effect_green", "Verte", 250, Color3.fromRGB(80, 220, 80), "Une explosion toxique."),
	effect("effect_yellow", "Jaune", 250, Color3.fromRGB(255, 225, 60), "Éclatant comme le soleil."),
	effect("effect_ice", "Glacée", 450, Color3.fromRGB(150, 225, 255), "Des éclats de glace."),
	effect("effect_electric", "Électrique", 450, Color3.fromRGB(180, 100, 255), "Une décharge violette."),
	effect("effect_fire", "Feu", 450, Color3.fromRGB(255, 110, 20), "Un brasier orangé."),
	effect("effect_rainbow", "Arc-en-ciel", 700, Color3.fromRGB(255, 200, 60), "Toutes les couleurs en une explosion."),
	effect("effect_neon", "Néon", 700, Color3.fromRGB(255, 60, 200), "Un flash néon rose électrique (aperçu : effet pas encore réalisé)"),
	effect("effect_meteor", "Météore", 800, Color3.fromRGB(255, 130, 40), "Un impact de roche enflammée (aperçu : effet pas encore réalisé)"),
	effect("effect_crystal", "Cristal", 800, Color3.fromRGB(170, 90, 255), "Des éclats de cristal violet (aperçu : effet pas encore réalisé)"),
	effect("effect_heart", "Cœur", 800, Color3.fromRGB(255, 90, 150), "Une explosion d'amour (aperçu : effet pas encore réalisé)"),
	effect("effect_stars", "Étoiles", 800, Color3.fromRGB(255, 215, 60), "Une pluie d'étoiles (aperçu : effet pas encore réalisé)"),
	effect("effect_smoke", "Fumée", 700, Color3.fromRGB(170, 170, 175), "Un gros nuage de fumée grise (aperçu : effet pas encore réalisé)"),
	effect("effect_aura", "Aura", 900, Color3.fromRGB(150, 70, 230), "Une aura sombre et violette (aperçu : effet pas encore réalisé)"),
	effect("effect_water", "Eau", 600, Color3.fromRGB(70, 160, 255), "Des éclaboussures d'eau (aperçu : effet pas encore réalisé)"),
	effect("effect_nature", "Nature", 600, Color3.fromRGB(90, 200, 80), "Feuilles et végétation (aperçu : effet pas encore réalisé)"),
	effect("effect_sand", "Sable", 600, Color3.fromRGB(235, 195, 120), "Un nuage de sable (aperçu : effet pas encore réalisé)"),
	effect("effect_toxic", "Toxic", 700, Color3.fromRGB(120, 230, 40), "Un nuage toxique vert (aperçu : effet pas encore réalisé)"),
	effect("effect_cosmic", "Cosmique", 1200, Color3.fromRGB(130, 80, 230), "Un archipel de galaxies projeté en croix, qui se disperse en poussière d'étoiles"),
	effect("effect_lava", "Lave", 900, Color3.fromRGB(255, 100, 20), "Du magma en fusion (aperçu : effet pas encore réalisé)"),
	effect("effect_wind", "Vent", 700, Color3.fromRGB(160, 215, 255), "Une tornade de vent (aperçu : effet pas encore réalisé)"),
	effect("effect_spirit", "Esprit", 900, Color3.fromRGB(130, 200, 255), "Des fantômes bleutés (aperçu : effet pas encore réalisé)"),
	effect("effect_pixel", "Pixel", 700, Color3.fromRGB(255, 170, 30), "Une explosion en pixels (aperçu : effet pas encore réalisé)"),
	effect("effect_bubble", "Bulle", 600, Color3.fromRGB(110, 200, 255), "Des bulles qui éclatent (aperçu : effet pas encore réalisé)"),
	effect("effect_flower", "Fleur", 600, Color3.fromRGB(255, 130, 190), "Pétales et fleurs roses (aperçu : effet pas encore réalisé)"),
	effect("effect_snowball", "Balle de neige", 600, Color3.fromRGB(225, 240, 255), "Une boule de neige explosive (aperçu : effet pas encore réalisé)"),
	effect("effect_gift", "Cadeau", 800, Color3.fromRGB(230, 60, 60), "Des cadeaux qui explosent (aperçu : effet pas encore réalisé)"),
	effect("effect_candy", "Bonbon", 800, Color3.fromRGB(255, 110, 200), "Sucreries et confettis (aperçu : effet pas encore réalisé)"),
	effect("effect_cactus", "Cactus", 600, Color3.fromRGB(100, 190, 70), "Des cactus piquants (aperçu : effet pas encore réalisé)"),
	effect("effect_shadow", "Ombre", 900, Color3.fromRGB(110, 50, 190), "Des éclats d'ombre (aperçu : effet pas encore réalisé)"),
}

local byId: { [string]: Cosmetic } = {}
local idsByKind: { bomb: { string }, effect: { string } } = { bomb = {}, effect = {} }
for _, cosmetic in list do
	byId[cosmetic.id] = cosmetic
	table.insert(idsByKind[cosmetic.kind], cosmetic.id)
end

CosmeticConfig.Defaults = table.freeze({ bomb = "bomb_classic", effect = "effect_classic" })

function CosmeticConfig.get(id: any): Cosmetic?
	if typeof(id) ~= "string" then
		return nil
	end
	return byId[id]
end

-- Identifiants d'un type, dans l'ordre d'affichage.
function CosmeticConfig.idsOfKind(kind: Kind): { string }
	return idsByKind[kind]
end

return table.freeze(CosmeticConfig)
