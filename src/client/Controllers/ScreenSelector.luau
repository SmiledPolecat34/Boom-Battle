--!strict
-- Choix PUR de l'écran principal d'après l'état annoncé par le serveur (même entrée, même sortie, aucune interface).
-- Extrait de UIController pour pouvoir être testé hors Studio (tests/unit/client/ScreenSelector.spec.luau).

local ScreenSelector = {}

export type PlayerSnapshot = {
	queued: boolean?,
	participant: boolean?,
	[string]: any,
}

-- snapshot : état serveur ({ state = "WAITING" | ... }) ; me : entrée du joueur local dans le snapshot, ou nil.
-- Retourne toujours un nom d'écran valide (jamais nil) : "MainMenu", "Lobby", "GameHUD" ou "Results".
function ScreenSelector.select(snapshot: any, me: PlayerSnapshot?): string
	local state: string = snapshot.state
	local queued = me ~= nil and me.queued == true

	-- Un participant qui a quitté la file (QUITTER dans le menu de pause) retourne au menu, pas aux résultats.
	if state == "FINISHED" and queued then
		return "Results"
	end
	if state == "COUNTDOWN" or state == "PLAYING" then
		if queued then
			return "GameHUD" -- participant, ou spectateur déjà inscrit
		end
		return "MainMenu"
	end
	if queued then
		return "Lobby"
	end
	return "MainMenu"
end

return ScreenSelector
