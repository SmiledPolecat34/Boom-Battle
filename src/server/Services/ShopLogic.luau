--!strict
-- Règles PURES d'achat et d'équipement : aucune dépendance au réseau, entièrement testables.
-- Toute la confiance est côté serveur : le client n'envoie qu'un identifiant de cosmétique.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local ProfileSchema = require(script.Parent.ProfileSchema)

local ShopLogic = {}

export type Error = "unknown" | "owned" | "funds" | "invalid_price" | "not_owned"

-- Achète un cosmétique : vérifie l'existence, la non-possession et le solde, puis débite ET donne l'objet en un
-- seul bloc (pas d'état intermédiaire). Aucun achat négatif, aucune duplication possible.
-- Une BOMBE achetée est ÉQUIPÉE automatiquement (le joueur l'utilise tout de suite, sans repasser par l'inventaire) ;
-- les effets restent à équiper à la main. Le joueur peut rééquiper une autre bombe possédée à tout moment (inventaire).
function ShopLogic.purchase(profile: ProfileSchema.Profile, id: any): (boolean, Error?)
	local item = CosmeticConfig.get(id)
	if not item then
		return false, "unknown"
	end
	if profile.OwnedCosmetics[item.id] then
		return false, "owned"
	end
	-- Garde-fou de configuration : un prix négatif ou fractionnaire créditerait / fausserait le solde.
	if item.price ~= math.floor(item.price) or item.price < 0 then
		return false, "invalid_price"
	end
	if profile.Coins < item.price then
		return false, "funds"
	end
	profile.Coins -= item.price
	profile.OwnedCosmetics[item.id] = true
	if item.kind == "bomb" then
		profile.EquippedCosmetics.bomb = item.id
	end
	return true, nil
end

-- Équipe un cosmétique possédé (un par type). Un objet non possédé ne peut jamais être équipé.
function ShopLogic.equip(profile: ProfileSchema.Profile, id: any): (boolean, Error?)
	local item = CosmeticConfig.get(id)
	if not item then
		return false, "unknown"
	end
	if not profile.OwnedCosmetics[item.id] then
		return false, "not_owned"
	end
	profile.EquippedCosmetics[item.kind] = item.id
	return true, nil
end

return ShopLogic
