--!strict
-- Catalogue des cosmétiques (Bomb Coins uniquement, aucun Robux). Un cosmétique ne change QUE l'apparence :
-- ni zone, ni délai, ni vitesse, ni hitbox. Prix de départ tirés des maquettes de boutique, à équilibrer
-- avec GameConfig.Rewards. Les deux cosmétiques « classique » sont offerts et équipés par défaut.

export type Kind = "bomb" | "effect"

export type Cosmetic = {
	id: string,
	kind: Kind,
	name: string,
	description: string,
	price: number,
	color: Color3,
	material: Enum.Material?,
}

local CosmeticConfig = {}

local function bomb(id: string, name: string, price: number, color: Color3, material: Enum.Material?, description: string): Cosmetic
	return table.freeze({ id = id, kind = "bomb" :: Kind, name = name, description = description, price = price, color = color, material = material })
end

local function effect(id: string, name: string, price: number, color: Color3, description: string): Cosmetic
	return table.freeze({ id = id, kind = "effect" :: Kind, name = name, description = description, price = price, color = color, material = nil })
end

-- Ordre d'affichage dans la boutique.
local list: { Cosmetic } = {
	bomb("bomb_classic", "Classique", 0, Color3.fromRGB(35, 35, 45), Enum.Material.SmoothPlastic, "Une bombe standard, fiable et efficace."),
	bomb("bomb_red", "Rouge", 250, Color3.fromRGB(200, 40, 40), Enum.Material.SmoothPlastic, "Impossible de la rater."),
	bomb("bomb_blue", "Bleue", 250, Color3.fromRGB(40, 110, 220), Enum.Material.SmoothPlastic, "Calme avant l'explosion."),
	bomb("bomb_green", "Verte", 250, Color3.fromRGB(50, 170, 70), Enum.Material.SmoothPlastic, "Fraîche et explosive."),
	bomb("bomb_yellow", "Jaune", 250, Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic, "Brille dans l'arène."),
	bomb("bomb_ice", "Glacée", 500, Color3.fromRGB(150, 220, 250), Enum.Material.Ice, "Un cristal de glace prêt à éclater."),

	effect("effect_classic", "Classique", 0, Color3.fromRGB(255, 150, 30), "Un effet d'explosion standard, propre et efficace."),
	effect("effect_red", "Rouge", 250, Color3.fromRGB(240, 50, 40), "Des flammes rouge sang."),
	effect("effect_blue", "Bleu", 250, Color3.fromRGB(60, 150, 255), "Une explosion bleu électrique."),
	effect("effect_green", "Verte", 250, Color3.fromRGB(80, 220, 80), "Une explosion toxique."),
	effect("effect_yellow", "Jaune", 250, Color3.fromRGB(255, 225, 60), "Éclatant comme le soleil."),
	effect("effect_ice", "Glacée", 450, Color3.fromRGB(150, 225, 255), "Des éclats de glace."),
	effect("effect_electric", "Électrique", 450, Color3.fromRGB(180, 100, 255), "Une décharge violette."),
	effect("effect_fire", "Feu", 450, Color3.fromRGB(255, 110, 20), "Un brasier orangé."),
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
