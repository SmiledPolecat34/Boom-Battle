--!nocheck
-- RoundService : machine d'états de la manche, pilotée par une horloge SIMULÉE (world.advance). Les services dépendant
-- du moteur (Parts, Humanoid, bombes) sont remplacés par des doubles ; la génération de carte, la grille, les
-- récompenses et les profils restent réels. Voir Fixtures.roundHarness.
local GameConfig = world.module("GameConfig")
local PlayState, PlayerDataService, ActorRegistry -- rechargés à chaque test (voir beforeEach)

local ROUND = GameConfig.Round

local h
beforeEach(function()
	world.reset() -- RoundService est un singleton à état global : monde neuf pour chaque test
	h = Fixtures.roundHarness()
	PlayState = world.module("PlayState")
	PlayerDataService = world.module("PlayerDataService")
	ActorRegistry = world.module("ActorRegistry")
	expect(world.module("RoundService")).toBe(h.RoundService) -- le module testé est bien celui du harnais
end)

-- États successivement annoncés à tous les clients (sans doublons consécutifs).
local function statesSeen()
	local list = {}
	for _, sent in h.remotes.RoundState.sent do
		if sent.player == "all" then
			local state = sent.args[1].state
			if list[#list] ~= state then
				table.insert(list, state)
			end
		end
	end
	return list
end

local function indexOf(list, value, from)
	for i = from or 1, #list do
		if list[i] == value then
			return i
		end
	end
	return nil
end

-- Lance une manche à n joueurs et avance jusqu'à PLAYING.
local function playing(n)
	local players = {}
	for i = 1, n do
		table.insert(players, h.join(i, true))
	end
	expect(h.advanceUntil("COUNTDOWN")).toBe(true)
	expect(h.advanceUntil("PLAYING")).toBe(true)
	return players
end

describe("démarrage", function()
	it("commence en WAITING avec une arène lobby générée et annoncée", function()
		expect(h.RoundService.getState()).toBe("WAITING")
		expect(#h.calls.map).toBe(1)
		expect(h.lastSnapshot()).toBeNil() -- rien diffusé tant que personne ne joue
		expect(#h.remotes.MapReady.sent).toBe(1)
	end)

	it("un joueur qui arrive au lobby reçoit un personnage et un point d'apparition", function()
		local p = h.join(1)
		expect(p.loadCount).toBe(1)
		expect(h.movement.setup[1]).toBe(p)
	end)

	it("sendFullState envoie la carte et l'état à un client qui vient de se connecter", function()
		local p = h.join(1)
		h.RoundService.sendFullState(p)
		expect(#h.remotes.RoundState.sent).toBeGreaterThan(0)
		local last = h.remotes.RoundState.sent[#h.remotes.RoundState.sent]
		expect(last.player).toBe(p)
		expect(last.args[1].state).toBe("WAITING")
	end)
end)

describe("compte à rebours et manche", function()
	it("PLAY lance le compte à rebours, puis la manche après QuickCountdown", function()
		local p = h.join(1, true)
		expect(h.RoundService.getState()).toBe("WAITING")
		world.advance(0.3)
		expect(h.RoundService.getState()).toBe("COUNTDOWN")
		expect(PlayState.canMove(p)).toBe(false) -- gelé pendant le compte à rebours
		world.advance(ROUND.QuickCountdown - 1)
		expect(h.RoundService.getState()).toBe("COUNTDOWN")
		world.advance(1.5)
		expect(h.RoundService.getState()).toBe("PLAYING")
		expect(PlayState.canMove(p)).toBe(true)
		expect(PlayState.canBomb(p)).toBe(true)
	end)

	it("la taille d'arène suit le nombre de joueurs", function()
		playing(5)
		expect(h.calls.map[#h.calls.map].sizeId).toBe("Medium")
	end)

	it("l'instantané annonce participants, survivants et état", function()
		playing(3)
		local snap = h.lastSnapshot()
		expect(snap.state).toBe("PLAYING")
		expect(snap.survivors).toBe(3)
		expect(snap.participantCount).toBe(3)
		expect(#snap.players).toBe(3)
		for _, entry in snap.players do
			expect(entry.participant).toBe(true)
			expect(entry.alive).toBe(true)
		end
		expect(snap.endsAt).never.toBeNil()
	end)

	it("personne ne peut poser de bombe avant PLAYING", function()
		local p = h.join(1, true)
		world.advance(0.3)
		expect(PlayState.canBomb(p)).toBe(false)
	end)

	it("un joueur sans PLAY n'est pas participant, même connecté avant la manche", function()
		local menu = h.join(1)
		local queuedPlayer = h.join(2, true)
		h.advanceUntil("PLAYING")
		local snap = h.lastSnapshot()
		local byId = {}
		for _, entry in snap.players do
			byId[entry.userId] = entry
		end
		expect(byId[2].participant).toBe(true)
		expect(byId[1].participant).toBe(false)
		expect(PlayState.canMove(menu)).toBe(false)
		expect(queuedPlayer.loadCount).toBeGreaterThan(0)
	end)

	it("un joueur qui arrive pendant la manche est spectateur : aucun personnage chargé", function()
		playing(2)
		local late = h.join(99)
		expect(late.loadCount).toBe(0)
		expect(PlayState.canMove(late)).toBe(false)
		expect(PlayState.canBomb(late)).toBe(false)
	end)
end)

describe("fin de manche", function()
	it("dernier survivant : victoire, récompenses, résultats diffusés", function()
		local p = playing(2)
		h.damage.eliminate(p[1])
		world.advance(1)
		expect(h.RoundService.getState()).toBe("FINISHED")
		local ended = h.remotes.RoundEnded.sent[1].args[1]
		expect(ended.result.outcome).toBe("WIN")
		expect(ended.result.winnerUserId).toBe(2)
		expect(ended.rewards["2"]).toBe(GameConfig.Rewards.ParticipationCoins + GameConfig.Rewards.WinCoins)
		expect(ended.rewards["1"]).toBe(GameConfig.Rewards.ParticipationCoins)
		expect(PlayerDataService.get(p[2]).Wins).toBe(1)
		-- le gagnant touche aussi la quête « gagner une manche »
		expect(PlayerDataService.get(p[2]).Coins).toBe(ended.rewards["2"] + world.module("QuestConfig").get("win1").reward)
		expect(PlayState.canBomb(p[2])).toBe(false) -- plus aucune action après la fin
	end)

	it("une seule récompense par joueur et par manche", function()
		local p = playing(2)
		h.damage.eliminate(p[1])
		world.advance(1)
		local coins = PlayerDataService.get(p[2]).Coins
		world.advance(2) -- le temps passe, FINISHED ne recrédite rien
		expect(PlayerDataService.get(p[2]).Coins).toBe(coins)
		expect(PlayerDataService.get(p[2]).MatchesPlayed).toBe(1)
	end)

	it("élimination simultanée de tous : égalité, jamais de victoire à un éliminé", function()
		local p = playing(2)
		h.damage.eliminate(p[1])
		h.damage.eliminate(p[2])
		world.advance(1)
		local result = h.remotes.RoundEnded.sent[1].args[1].result
		expect(result.outcome).toBe("DRAW")
		expect(result.winnerUserId).toBeNil()
		expect(#result.tiedUserIds).toBe(2)
	end)

	it("une même explosion laisse le temps de compter les deux éliminés (délai d'attente)", function()
		local p = playing(3)
		h.damage.eliminate(p[1])
		world.advance(0.3) -- avant la fin du délai : la manche n'est pas encore close
		expect(h.RoundService.getState()).toBe("PLAYING")
		h.damage.eliminate(p[2])
		world.advance(1)
		expect(h.RoundService.getState()).toBe("FINISHED")
		expect(h.remotes.RoundEnded.sent[1].args[1].result.winnerUserId).toBe(3)
	end)

	it("temps écoulé avec plusieurs survivants : égalité entre eux", function()
		playing(2)
		world.advance(ROUND.RoundDuration + 1)
		expect(h.RoundService.getState()).toBe("FINISHED")
		local result = h.remotes.RoundEnded.sent[1].args[1].result
		expect(result.outcome).toBe("DRAW")
		expect(#result.tiedUserIds).toBe(2)
	end)

	it("solo (1 joueur) : la manche dure jusqu'à sa mort, pas de victoire automatique", function()
		local p = playing(1)
		world.advance(30)
		expect(h.RoundService.getState()).toBe("PLAYING")
		h.damage.eliminate(p[1])
		world.advance(1)
		expect(h.RoundService.getState()).toBe("FINISHED")
	end)

	it("retour automatique au lobby après ResultDuration, puis nouvelle manche pour les joueurs en file", function()
		local p = playing(2)
		h.damage.eliminate(p[1])
		world.advance(1)
		world.advance(ROUND.ResultDuration + 0.5)
		local seen = statesSeen()
		local resetting = indexOf(seen, "RESETTING", indexOf(seen, "FINISHED"))
		expect(resetting).never.toBeNil()
		expect(indexOf(seen, "WAITING", resetting)).never.toBeNil()
		-- toujours en file : une nouvelle manche repart toute seule
		expect(h.advanceUntil("COUNTDOWN")).toBe(true)
		expect(h.calls.bombsCleared).toBeGreaterThan(2)
	end)

	it("l'arène est reconstruite à chaque manche (nouvelle seed)", function()
		local p = playing(2)
		local before = #h.calls.map
		h.damage.eliminate(p[1])
		world.advance(1 + ROUND.ResultDuration + 0.5)
		expect(#h.calls.map).toBeGreaterThan(before)
	end)
end)

describe("départs et abandons", function()
	it("déconnexion en pleine manche : comptée comme élimination, le restant gagne", function()
		local p = playing(2)
		world.removePlayer(p[1])
		world.advance(1)
		local result = h.remotes.RoundEnded.sent[1].args[1].result
		expect(result.outcome).toBe("WIN")
		expect(result.winnerUserId).toBe(2)
	end)

	it("tous les participants partent : la manche se termine sans erreur", function()
		local p = playing(2)
		world.removePlayer(p[1])
		world.removePlayer(p[2])
		world.advance(2)
		expect(h.RoundService.getState()).toBe("FINISHED")
		expect(#world.warnings).toBe(0)
	end)

	it("abandon volontaire (forfeit) en manche : élimination puis sortie de la file", function()
		local p = playing(2)
		world.advance(1)
		h.remotes.SetQueued:fireServer(p[1], false, true)
		world.advance(1)
		expect(h.RoundService.getState()).toBe("FINISHED")
		expect(h.remotes.RoundEnded.sent[1].args[1].result.winnerUserId).toBe(2)
	end)

	it("quitter la file en manche SANS forfeit est refusé", function()
		local p = playing(2)
		world.advance(1)
		h.remotes.SetQueued:fireServer(p[1], false)
		world.advance(1)
		expect(h.RoundService.getState()).toBe("PLAYING")
		expect(PlayState.canBomb(p[1])).toBe(true)
	end)

	it("un participant qui abandonne pendant le compte à rebours l'interrompt", function()
		local p = {}
		for i = 1, 2 do
			table.insert(p, h.join(i, true))
		end
		h.advanceUntil("COUNTDOWN")
		world.advance(1)
		h.remotes.SetQueued:fireServer(p[2], false, true)
		world.advance(0.5)
		-- le compte à rebours est interrompu (retour WAITING) puis repart avec le seul joueur restant
		local seen = statesSeen()
		expect(indexOf(seen, "WAITING", indexOf(seen, "COUNTDOWN"))).never.toBeNil()
		h.advanceUntil("PLAYING")
		local snap = h.lastSnapshot()
		local participants = 0
		for _, entry in snap.players do
			if entry.participant then
				participants += 1
			end
		end
		expect(participants).toBe(1)
	end)
end)

describe("revanche (REJOUER)", function()
	it("tous les joueurs cliquent REJOUER : retour immédiat et compte à rebours court", function()
		local p = playing(2)
		h.damage.eliminate(p[1])
		world.advance(1)
		expect(h.RoundService.getState()).toBe("FINISHED")
		h.remotes.SetReady:fireServer(p[1], true)
		expect(h.RoundService.getState()).toBe("FINISHED") -- un seul sur deux
		h.remotes.SetReady:fireServer(p[2], true)
		expect(h.RoundService.getState()).toBe("WAITING") -- retour immédiat, sans attendre ResultDuration
		world.advance(0.3)
		expect(h.RoundService.getState()).toBe("COUNTDOWN")
		world.advance(ROUND.RematchCountdown + 0.5)
		expect(h.RoundService.getState()).toBe("PLAYING") -- 3 s au lieu de 6
	end)

	it("plus personne dans la file en fin de manche : retour immédiat au lobby", function()
		local p = playing(2)
		h.damage.eliminate(p[1])
		world.advance(1)
		h.remotes.SetQueued:fireServer(p[1], false)
		world.advance(1)
		h.remotes.SetQueued:fireServer(p[2], false)
		expect(h.RoundService.getState()).toBe("WAITING")
		world.advance(1)
		expect(h.RoundService.getState()).toBe("WAITING") -- personne en file : pas de nouvelle manche
	end)
end)

describe("remotes : charges utiles hostiles et cadence", function()
	it("SetReady : types invalides, joueur hors file et spam sont ignorés", function()
		local p = h.join(1)
		local before = #h.remotes.RoundState.sent
		for _, bad in { "true", 1, {}, nil } do
			h.remotes.SetReady:fireServer(p, bad)
		end
		h.remotes.SetReady:fireServer(p, true) -- pas encore dans la file
		expect(#h.remotes.RoundState.sent).toBe(before) -- rien n'a changé, rien n'a été diffusé
	end)

	it("SetQueued : types invalides ignorés", function()
		local p = h.join(1)
		for _, bad in { "true", 1, {}, nil } do
			h.remotes.SetQueued:fireServer(p, bad)
		end
		h.remotes.SetQueued:fireServer(p, true, "oui") -- forfeit non booléen
		world.advance(0.3)
		expect(h.RoundService.getState()).toBe("WAITING")
	end)

	it("SetQueued : la cadence est limitée (2e bascule immédiate ignorée)", function()
		local p = h.join(1, true) -- PLAY
		h.remotes.SetQueued:fireServer(p, false) -- trop tôt
		world.advance(0.3)
		expect(h.RoundService.getState()).toBe("COUNTDOWN") -- toujours en file
	end)

	it("PartyAction : action non textuelle ou inconnue ignorée", function()
		local p = h.join(1)
		local before = #h.remotes.RoundState.sent
		for _, bad in { 1, true, {}, "n_importe_quoi" } do
			h.remotes.PartyAction:fireServer(p, bad)
			world.advance(0.6)
		end
		expect(#h.remotes.RoundState.sent).toBe(before)
	end)

	it("le départ d'un joueur libère ses états (file, prêt, groupe)", function()
		local p = h.join(1, true)
		world.removePlayer(p)
		world.advance(1)
		expect(h.RoundService.getState()).toBe("WAITING")
	end)
end)

describe("partie privée", function()
	local function act(player, action, arg)
		h.remotes.PartyAction:fireServer(player, action, arg)
		world.advance(0.6) -- respecte la limite de cadence
	end

	it("create : l'hôte entre dans la file, le groupe apparaît dans l'instantané, sans lancement automatique", function()
		local host = h.join(1)
		act(host, "create")
		local snap = h.lastSnapshot()
		expect(snap.party.hostUserId).toBe(1)
		expect(snap.party.count).toBe(1)
		expect(h.RoundService.getState()).toBe("WAITING") -- un membre de groupe ne déclenche pas la partie rapide
	end)

	it("une seule partie par serveur ; un joueur déjà en file ne peut pas en créer", function()
		local a, b = h.join(1), h.join(2)
		act(a, "create")
		act(b, "create")
		expect(h.lastNotice(b)).toContain("existe déjà")
		act(a, "create") -- déjà en file : ignoré
		expect(h.lastSnapshot().party.hostUserId).toBe(1)
	end)

	it("join : un joueur rejoint, un joueur sans groupe existant est ignoré", function()
		local a, b = h.join(1), h.join(2)
		local before = #h.remotes.RoundState.sent
		act(b, "join") -- aucun groupe
		expect(#h.remotes.RoundState.sent).toBe(before)
		act(a, "create")
		act(b, "join")
		expect(h.lastSnapshot().party.count).toBe(2)
	end)

	it("start : seul l'hôte, et seulement avec assez de joueurs", function()
		local a, b = h.join(1), h.join(2)
		act(a, "create")
		act(a, "start")
		expect(h.lastNotice(a)).toContain("au moins")
		act(b, "join")
		act(b, "start") -- pas l'hôte
		world.advance(1)
		expect(h.RoundService.getState()).toBe("WAITING")
		act(a, "start")
		expect(h.advanceUntil("COUNTDOWN")).toBe(true)
		expect(h.advanceUntil("PLAYING")).toBe(true)
	end)

	it("bots : l'hôte ajoute / règle / retire ; charges hostiles ignorées ; non-hôte refusé", function()
		local a, b = h.join(1), h.join(2)
		act(a, "create")
		act(b, "join")
		act(b, "addBot") -- pas l'hôte
		expect(h.lastSnapshot().party.count).toBe(2)
		act(a, "addBot", 99) -- niveau invalide => niveau par défaut
		expect(h.lastSnapshot().party.bots[1]).toBe(ROUND.DefaultBotDifficulty)
		act(a, "addBot", 7)
		expect(h.lastSnapshot().party.bots[2]).toBe(7)
		act(a, "botLevel", { index = 1, level = 3 })
		expect(h.lastSnapshot().party.bots[1]).toBe(3)
		for _, bad in { { index = 9, level = 3 }, { index = 1, level = 99 }, { index = 1.5, level = 3 }, { index = 1 }, "x", 5 } do
			act(a, "botLevel", bad)
		end
		expect(h.lastSnapshot().party.bots).toEqual({ 3, 7 })
		for _, bad in { 0, 3, -1, 1.5, "1", {} } do
			act(a, "removeBot", bad)
		end
		expect(#h.lastSnapshot().party.bots).toBe(2)
		act(a, "removeBot", 1)
		expect(h.lastSnapshot().party.bots).toEqual({ 7 })
	end)

	it("groupe complet : plus de join ni d'addBot (MaximumPlayers)", function()
		local host = h.join(1)
		act(host, "create")
		for _ = 1, ROUND.MaximumPlayers - 1 do
			act(host, "addBot")
		end
		local late = h.join(50)
		act(late, "join")
		expect(h.lastNotice(late)).toContain("complète")
		act(host, "addBot")
		expect(h.lastNotice(host)).toContain("complète")
		expect(h.lastSnapshot().party.count).toBe(ROUND.MaximumPlayers)
	end)

	it("manche contre bots : bots créés, IA lancée, aucune récompense, bots retirés au retour au lobby", function()
		local host = h.join(1)
		act(host, "create")
		act(host, "addBot")
		act(host, "start")
		expect(h.advanceUntil("PLAYING")).toBe(true)
		expect(h.calls.botsCreated).toBe(1)
		expect(h.calls.aiStarted).toBe(1)
		local snap = h.lastSnapshot()
		expect(snap.participantCount).toBe(2)
		expect(#ActorRegistry.getBots()).toBe(1)
		-- la mort de l'humain clôt la manche (inutile de regarder les bots)
		h.damage.eliminate(host)
		world.advance(1)
		expect(h.RoundService.getState()).toBe("FINISHED")
		expect(next(h.remotes.RoundEnded.sent[1].args[1].rewards)).toBeNil()
		expect(PlayerDataService.get(host).Coins).toBe(0)
		world.advance(ROUND.ResultDuration + 0.5)
		expect(#ActorRegistry.getBots()).toBe(0)
	end)

	it("le départ de l'hôte transmet le groupe au plus ancien membre, groupe vide dissous", function()
		local a, b = h.join(1), h.join(2)
		act(a, "create")
		act(b, "join")
		world.removePlayer(a)
		expect(h.lastSnapshot().party.hostUserId).toBe(2)
		world.removePlayer(b)
		expect(h.lastSnapshot().party).toBeNil()
	end)

	it("pas de création de groupe pendant une manche", function()
		playing(2)
		local late = h.join(77)
		act(late, "create")
		expect(h.lastNotice(late)).toContain("manche est en cours")
	end)
end)
