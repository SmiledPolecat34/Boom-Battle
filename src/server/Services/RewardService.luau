--!strict
-- Récompenses de fin de manche : calculées et attribuées UNIQUEMENT par le serveur, une seule fois par joueur et
-- par manche (le client n'a aucune remote pour demander des pièces).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerDataService = require(script.Parent.PlayerDataService)
local QuestService = require(script.Parent.QuestService)

local RewardService = {}

-- Clés faibles : l'entrée d'un joueur parti est libérée avec son instance (pas de fuite mémoire).
local lastAwardedRound: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Pièces gagnées pour un résultat : participation, plus bonus de victoire ou d'égalité.
-- (Une victoire remplace le bonus d'égalité ; un éliminé non gagnant n'a que la participation.)
function RewardService.coinsFor(userId: number, result: Types.RoundResult): number
	local coins = GameConfig.Rewards.ParticipationCoins
	if result.outcome == "WIN" and result.winnerUserId == userId then
		coins += GameConfig.Rewards.WinCoins
	elseif result.outcome == "DRAW" and table.find(result.tiedUserIds, userId) then
		coins += GameConfig.Rewards.DrawCoins
	end
	return coins
end

-- participants : joueurs encore présents à la fin de la manche. Retourne { [userId en texte] = pièces gagnées }.
function RewardService.awardRound(roundId: number, participants: { Player }, result: Types.RoundResult): { [string]: number }
	local rewards: { [string]: number } = {}
	for _, player in participants do
		if lastAwardedRound[player] ~= roundId then
			lastAwardedRound[player] = roundId
			local coins = RewardService.coinsFor(player.UserId, result)
			local won = result.outcome == "WIN" and result.winnerUserId == player.UserId
			local applied = PlayerDataService.mutate(player, function(profile)
				profile.Coins = math.min(GameConfig.Data.MaxCoins, profile.Coins + coins)
				profile.MatchesPlayed = math.min(GameConfig.Data.MaxCoins, profile.MatchesPlayed + 1)
				if won then
					profile.Wins = math.min(GameConfig.Data.MaxCoins, profile.Wins + 1)
				end
			end)
			if applied then
				rewards[tostring(player.UserId)] = coins
				QuestService.progress(player, "round_played", 1)
				if won then
					QuestService.progress(player, "round_won", 1)
				end
			end
		end
	end
	return rewards
end

return RewardService
