--!strict
-- Progression des quêtes. La récompense est créditée UNE seule fois, côté serveur, quand l'objectif est atteint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local GameEvents = require(script.Parent.GameEvents)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProfileSchema = require(script.Parent.ProfileSchema)

local QuestService = {}

-- Logique PURE : applique un événement au profil. Retourne la liste des quêtes terminées par cet appel.
function QuestService.apply(profile: ProfileSchema.Profile, event: string, amount: number): { string }
	local completed: { string } = {}
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return completed
	end
	for _, quest in QuestConfig.Quests do
		if quest.event == event then
			local state = profile.QuestProgress[quest.id]
			if state == nil then
				state = { progress = 0, done = false }
				profile.QuestProgress[quest.id] = state
			end
			if not state.done then
				state.progress = math.min(quest.goal, state.progress + math.floor(amount))
				if state.progress >= quest.goal then
					state.done = true
					profile.Coins = math.min(GameConfig.Data.MaxCoins, profile.Coins + quest.reward)
					table.insert(completed, quest.id)
				end
			end
		end
	end
	return completed
end

function QuestService.progress(player: Player, event: string, amount: number)
	PlayerDataService.mutate(player, function(profile)
		QuestService.apply(profile, event, amount)
	end)
end

function QuestService.start()
	GameEvents.CratesDestroyed:Connect(function(ownerUserId: number, count: number)
		local player = Players:GetPlayerByUserId(ownerUserId)
		if player then
			QuestService.progress(player, "crates_destroyed", count)
		end
	end)
end

return QuestService
