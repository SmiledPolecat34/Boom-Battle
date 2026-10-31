--!strict
-- Trois quêtes simples et permanentes (non répétables en v0.2). La récompense est créditée par le serveur,
-- une seule fois, au moment où l'objectif est atteint.

export type Quest = {
	id: string,
	name: string,
	description: string,
	event: string, -- événement serveur qui fait progresser la quête
	goal: number,
	reward: number, -- Bomb Coins
}

local QuestConfig = {}

QuestConfig.Quests = table.freeze({
	table.freeze({ id = "play3", name = "Premiers pas", description = "Jouer 3 manches", event = "round_played", goal = 3, reward = 30 }),
	table.freeze({ id = "win1", name = "Dernier survivant", description = "Gagner une manche", event = "round_won", goal = 1, reward = 60 }),
	table.freeze({ id = "crates20", name = "Démolisseur", description = "Détruire 20 caisses", event = "crates_destroyed", goal = 20, reward = 40 }),
}) :: { Quest }

function QuestConfig.get(id: string): Quest?
	for _, quest in QuestConfig.Quests do
		if quest.id == id then
			return quest
		end
	end
	return nil
end

return table.freeze(QuestConfig)
