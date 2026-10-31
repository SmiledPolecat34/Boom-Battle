--!strict
-- Détermination PURE du résultat d'une manche (aucune dépendance au Workspace : testable seul).
--
-- Règles (H3, documentées dans docs/ARCHITECTURE.md) :
--  * un seul survivant            -> VICTOIRE de ce joueur ;
--  * plusieurs survivants (temps) -> ÉGALITÉ entre tous les survivants ;
--  * aucun survivant              -> ÉGALITÉ entre les derniers joueurs éliminés dans la même fenêtre de temps
--                                    (une victoire n'est jamais attribuée à un joueur éliminé).
-- Classement : survivants d'abord, puis éliminés du plus tardif au plus précoce.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

export type Elimination = { userId: number, t: number }

local RoundResolver = {}

-- participantIds : tous les joueurs de la manche. aliveIds : ensemble des survivants.
-- eliminations : ordre chronologique (t croissant). window : tolérance « même explosion », en secondes.
function RoundResolver.compute(
	participantIds: { number },
	aliveIds: { [number]: boolean },
	eliminations: { Elimination },
	window: number,
	durationSeconds: number
): Types.RoundResult
	local survivors: { number } = {}
	for _, id in participantIds do
		if aliveIds[id] then
			table.insert(survivors, id)
		end
	end

	local ranking: { number } = {}
	for _, id in survivors do
		table.insert(ranking, id)
	end
	for i = #eliminations, 1, -1 do
		table.insert(ranking, eliminations[i].userId)
	end

	if #survivors == 1 then
		return {
			outcome = "WIN",
			winnerUserId = survivors[1],
			tiedUserIds = {},
			ranking = ranking,
			durationSeconds = durationSeconds,
		}
	end

	local tied: { number } = {}
	if #survivors >= 2 then
		tied = table.clone(survivors)
	elseif #eliminations > 0 then
		local lastTime = eliminations[#eliminations].t
		for _, elimination in eliminations do
			if elimination.t >= lastTime - window then
				table.insert(tied, elimination.userId)
			end
		end
	end

	return {
		outcome = "DRAW",
		winnerUserId = nil,
		tiedUserIds = tied,
		ranking = ranking,
		durationSeconds = durationSeconds,
	}
end

return RoundResolver
