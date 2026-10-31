--!nocheck
-- Tests de la Phase 3 : résultat de manche (RoundResolver) et porte d'actions (PlayState).
-- À EXÉCUTER DANS ROBLOX STUDIO : coller dans la barre de commande (mode Edit) après synchronisation Rojo.

local ServerScriptService = game:GetService("ServerScriptService")
local RoundResolver = require(ServerScriptService.Server.Services.RoundResolver)
local PlayState = require(ServerScriptService.Server.Services.PlayState)

local passed, failed = 0, 0
local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		warn(("ÉCHEC : %s %s"):format(name, detail or ""))
	end
end

local WINDOW = 0.5

-- T11 : dernier survivant.
do
	local r = RoundResolver.compute({ 1, 2, 3 }, { [3] = true }, { { userId = 1, t = 10 }, { userId = 2, t = 20 } }, WINDOW, 30)
	check("T11 victoire du survivant", r.outcome == "WIN" and r.winnerUserId == 3)
	check("T11 pas d'égalité", #r.tiedUserIds == 0)
	check("T11 classement 3, 2, 1", r.ranking[1] == 3 and r.ranking[2] == 2 and r.ranking[3] == 1)
end

-- Temps écoulé avec plusieurs survivants : égalité entre eux.
do
	local r = RoundResolver.compute({ 1, 2, 3 }, { [2] = true, [3] = true }, { { userId = 1, t = 10 } }, WINDOW, 150)
	check("temps écoulé : égalité", r.outcome == "DRAW" and r.winnerUserId == nil)
	check("temps écoulé : survivants à égalité", #r.tiedUserIds == 2 and table.find(r.tiedUserIds, 2) ~= nil and table.find(r.tiedUserIds, 3) ~= nil)
	check("temps écoulé : le joueur éliminé n'est pas à égalité", table.find(r.tiedUserIds, 1) == nil)
end

-- Éliminations simultanées : égalité entre les derniers éliminés.
do
	local r = RoundResolver.compute({ 1, 2, 3 }, {}, { { userId = 1, t = 10 }, { userId = 2, t = 20.0 }, { userId = 3, t = 20.3 } }, WINDOW, 25)
	check("simultané : égalité", r.outcome == "DRAW")
	check("simultané : 2 et 3 à égalité, pas 1", #r.tiedUserIds == 2 and table.find(r.tiedUserIds, 1) == nil)
	check("simultané : pas de gagnant", r.winnerUserId == nil)
end

-- Aucun survivant, derniers éliminés espacés : jamais de victoire pour un joueur éliminé.
do
	local r = RoundResolver.compute({ 1, 2 }, {}, { { userId = 1, t = 10 }, { userId = 2, t = 12 } }, WINDOW, 12)
	check("aucun survivant : pas de victoire", r.outcome == "DRAW" and r.winnerUserId == nil)
	check("aucun survivant : le dernier éliminé seul à égalité", #r.tiedUserIds == 1 and r.tiedUserIds[1] == 2)
end

-- Solo (test Studio) : mort du seul joueur.
do
	local r = RoundResolver.compute({ 7 }, {}, { { userId = 7, t = 5 } }, WINDOW, 5)
	check("solo mort : égalité avec soi-même, pas de victoire", r.outcome == "DRAW" and r.winnerUserId == nil and r.tiedUserIds[1] == 7)
	local r2 = RoundResolver.compute({ 7 }, { [7] = true }, {}, WINDOW, 150)
	check("solo survivant au temps : victoire", r2.outcome == "WIN" and r2.winnerUserId == 7)
end

-- Départ en cours de manche compté comme élimination.
do
	local r = RoundResolver.compute({ 1, 2 }, { [2] = true }, { { userId = 1, t = 4 } }, WINDOW, 4)
	check("déconnexion : le restant gagne", r.outcome == "WIN" and r.winnerUserId == 2)
end

-- Porte d'actions.
do
	local fake = {} -- n'importe quelle table sert de clé de joueur
	PlayState.clearActive()
	for _, s in { "WAITING", "READY" } do
		PlayState.setState(s)
		check("porte : lobby autorise le déplacement (" .. s .. ")", PlayState.canMove(fake))
		check("porte : lobby interdit la bombe (" .. s .. ")", not PlayState.canBomb(fake))
	end
	PlayState.setState("COUNTDOWN")
	PlayState.setActive(fake, true)
	check("porte : compte à rebours gèle le joueur", not PlayState.canMove(fake) and not PlayState.canBomb(fake))
	PlayState.setState("PLAYING")
	check("porte : en manche, joueur actif peut bouger et poser", PlayState.canMove(fake) and PlayState.canBomb(fake))
	PlayState.setActive(fake, false)
	check("porte : joueur éliminé ne peut plus agir", not PlayState.canMove(fake) and not PlayState.canBomb(fake))
	PlayState.setState("FINISHED")
	PlayState.setActive(fake, true)
	check("porte : fin de manche bloque tout", not PlayState.canMove(fake) and not PlayState.canBomb(fake))
	PlayState.clearActive()
	PlayState.setState("WAITING")
end

print(("[Phase3Tests] %d réussis, %d échecs"):format(passed, failed))
