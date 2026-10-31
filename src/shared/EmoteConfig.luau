--!strict
-- Émotes Roblox par défaut (les phrases rapides sont dans QuickChatConfig).
--
-- Les identifiants d'animation ont été LUS dans le script Animate par défaut des personnages R15 de ce jeu
-- (dossiers wave, point, cheer, laugh, dance, dance2, dance3) le 31/10/2026. Ne jamais en inventer : si un jour
-- une animation ne se charge plus, relire le script Animate d'un personnage.

export type Emote = {
	id: string,
	name: string, -- nom affiché
	animationId: string,
	looped: boolean, -- les danses tournent (arrêtées après MaxLoopSeconds) ; les gestes se jouent une fois
}

local EmoteConfig = {}

EmoteConfig.MaxLoopSeconds = 8 -- durée maximale d'une danse
EmoteConfig.CancelOnMove = true -- bouger interrompt l'émote (côté serveur)

EmoteConfig.Emotes = table.freeze({
	table.freeze({ id = "wave", name = "Salut", animationId = "rbxassetid://507770239", looped = false }),
	table.freeze({ id = "point", name = "Pointer", animationId = "rbxassetid://507770453", looped = false }),
	table.freeze({ id = "cheer", name = "Acclamer", animationId = "rbxassetid://507770677", looped = false }),
	table.freeze({ id = "laugh", name = "Rire", animationId = "rbxassetid://507770818", looped = false }),
	table.freeze({ id = "dance", name = "Danse 1", animationId = "rbxassetid://507771019", looped = true }),
	table.freeze({ id = "dance2", name = "Danse 2", animationId = "rbxassetid://507776043", looped = true }),
	table.freeze({ id = "dance3", name = "Danse 3", animationId = "rbxassetid://507777268", looped = true }),
}) :: { Emote }

local byId: { [string]: Emote } = {}
for _, emote in EmoteConfig.Emotes do
	byId[emote.id] = emote
end

function EmoteConfig.get(id: any): Emote?
	if typeof(id) ~= "string" then
		return nil
	end
	return byId[id]
end

return table.freeze(EmoteConfig)
