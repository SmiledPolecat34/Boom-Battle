--!strict
-- Définition des bonus. Les cosmétiques et quêtes arrivent en Phase 6 : aucun contenu factice ici.

local Types = require(script.Parent.Types)

export type PowerupDefinition = {
	id: Types.PowerupId,
	displayName: string,
	description: string,
	-- Champ de PlayerStats modifié par le bonus.
	stat: string,
	amount: number,
}

local ItemConfig = {}

ItemConfig.Powerups = table.freeze({
	BombPlus = table.freeze({
		id = "BombPlus",
		displayName = "Bomb+",
		description = "Une bombe supplémentaire à poser en même temps.",
		stat = "bombCapacity",
		amount = 1,
	}),
	FirePlus = table.freeze({
		id = "FirePlus",
		displayName = "Fire+",
		description = "Explosions plus longues d'une case.",
		stat = "blastRange",
		amount = 1,
	}),
	SpeedPlus = table.freeze({
		id = "SpeedPlus",
		displayName = "Speed+",
		description = "Déplacements plus rapides.",
		stat = "speedPickups",
		amount = 1,
	}),
	Shield = table.freeze({
		id = "Shield",
		displayName = "Shield",
		description = "Absorbe une explosion.",
		stat = "hasShield",
		amount = 1,
	}),
}) :: { [string]: PowerupDefinition }

-- Ordre d'affichage dans le HUD.
ItemConfig.PowerupOrder = table.freeze({ "BombPlus", "FirePlus", "SpeedPlus", "Shield" })

return table.freeze(ItemConfig)
