--!strict
-- Schéma versionné du profil joueur et validation de TOUTE donnée lue (DataStore ou autre) : une donnée
-- corrompue ou falsifiée est ramenée à une valeur valide, jamais acceptée telle quelle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)

export type QuestState = { progress: number, done: boolean }

export type Profile = {
	DataVersion: number,
	Coins: number,
	Wins: number,
	MatchesPlayed: number,
	OwnedCosmetics: { [string]: boolean },
	EquippedCosmetics: { bomb: string, effect: string },
	QuestProgress: { [string]: QuestState },
}

local ProfileSchema = {}

local MAX = GameConfig.Data.MaxCoins

-- Entier positif ou nul borné ; tout le reste (NaN, négatif, texte, infini) devient 0.
local function toCount(value: any, max: number): number
	if typeof(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	if value >= max then
		return max
	end
	return math.floor(value)
end
ProfileSchema.toCount = toCount

function ProfileSchema.default(): Profile
	local owned: { [string]: boolean } = {}
	owned[CosmeticConfig.Defaults.bomb] = true
	owned[CosmeticConfig.Defaults.effect] = true
	local quests: { [string]: QuestState } = {}
	for _, quest in QuestConfig.Quests do
		quests[quest.id] = { progress = 0, done = false }
	end
	return {
		DataVersion = GameConfig.Data.DataVersion,
		Coins = 0,
		Wins = 0,
		MatchesPlayed = 0,
		OwnedCosmetics = owned,
		EquippedCosmetics = { bomb = CosmeticConfig.Defaults.bomb, effect = CosmeticConfig.Defaults.effect },
		QuestProgress = quests,
	}
end

-- Retourne (profil valide, nil), ou (nil, raison) si la donnée vient d'une version FUTURE : on ne la réécrit pas
-- (elle perdrait des champs) ; l'appelant doit traiter cela comme un échec de chargement.
function ProfileSchema.sanitize(raw: any): (Profile?, string?)
	local profile = ProfileSchema.default()
	if raw == nil then
		return profile, nil
	end
	if typeof(raw) ~= "table" then
		return profile, nil -- donnée inutilisable : profil neuf (le propriétaire a été journalisé par l'appelant)
	end

	local version = raw.DataVersion
	if typeof(version) == "number" and version > GameConfig.Data.DataVersion then
		return nil, "version future"
	end
	-- Migrations : à ajouter ici (if version < 2 then ... end) quand le schéma évoluera.

	profile.Coins = toCount(raw.Coins, MAX)
	profile.Wins = toCount(raw.Wins, MAX)
	profile.MatchesPlayed = toCount(raw.MatchesPlayed, MAX)

	if typeof(raw.OwnedCosmetics) == "table" then
		for id, owned in raw.OwnedCosmetics do
			if owned == true and CosmeticConfig.get(id) ~= nil then
				profile.OwnedCosmetics[id] = true
			end
		end
	end

	local equipped = raw.EquippedCosmetics
	if typeof(equipped) == "table" then
		for _, kind in { "bomb", "effect" } do
			local cosmetic = CosmeticConfig.get(equipped[kind])
			if cosmetic and cosmetic.kind == kind and profile.OwnedCosmetics[cosmetic.id] then
				profile.EquippedCosmetics[kind] = cosmetic.id
			end
		end
	end

	local savedQuests = raw.QuestProgress
	if typeof(savedQuests) == "table" then
		for _, quest in QuestConfig.Quests do
			local saved = savedQuests[quest.id]
			if typeof(saved) == "table" then
				local progress = toCount(saved.progress, quest.goal)
				profile.QuestProgress[quest.id] = {
					progress = progress,
					done = saved.done == true or progress >= quest.goal,
				}
			end
		end
	end
	return profile, nil
end

-- Copie sans référence partagée, prête à être sauvegardée.
function ProfileSchema.serialize(profile: Profile): { [string]: any }
	local owned: { [string]: boolean } = {}
	for id, value in profile.OwnedCosmetics do
		if value then
			owned[id] = true
		end
	end
	local quests: { [string]: any } = {}
	for id, state in profile.QuestProgress do
		quests[id] = { progress = state.progress, done = state.done }
	end
	return {
		DataVersion = GameConfig.Data.DataVersion,
		Coins = profile.Coins,
		Wins = profile.Wins,
		MatchesPlayed = profile.MatchesPlayed,
		OwnedCosmetics = owned,
		EquippedCosmetics = { bomb = profile.EquippedCosmetics.bomb, effect = profile.EquippedCosmetics.effect },
		QuestProgress = quests,
	}
end

return ProfileSchema
