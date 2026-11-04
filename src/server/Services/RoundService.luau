--!strict
-- Machine d'états de la manche : SEUL propriétaire des transitions, des participants, des spawns et du résultat.
--
-- WAITING -> READY -> COUNTDOWN -> PLAYING -> FINISHED -> RESETTING -> WAITING
--
-- Avant la première manche et entre les manches, une arène « lobby » est affichée : les joueurs s'y déplacent
-- librement mais ne peuvent pas poser de bombe. Les joueurs qui arrivent pendant une manche n'y participent pas
-- et la regardent depuis la caméra fixe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local ActorRegistry = require(script.Parent.ActorRegistry)
local BombService = require(script.Parent.BombService)
local BotService = require(script.Parent.BotService)
local DamageService = require(script.Parent.DamageService)
local MapService = require(script.Parent.MapService)
local MovementService = require(script.Parent.MovementService)
local PlayState = require(script.Parent.PlayState)
local PowerupService = require(script.Parent.PowerupService)
local RewardService = require(script.Parent.RewardService)
local RoundResolver = require(script.Parent.RoundResolver)

local ROUND = GameConfig.Round
local TICK_INTERVAL = 0.2
local SPAWN_HEIGHT = 3
-- Un joueur éliminé dans la même explosion (ou juste après) compte pour une égalité : voir RoundResolver.
local SIMULTANEOUS_WINDOW = GameConfig.Bomb.ExplosionDuration
-- Délai laissé après la dernière élimination avant de clore la manche, pour que les autres coups d'une même
-- explosion soient comptés.
local SETTLE_DELAY = GameConfig.Bomb.ExplosionDuration + 0.1

local RoundService = {}

local state: Types.GameState = "WAITING"
local stateEnteredAt = os.clock()
local endsAt: number? = nil -- heure serveur (workspace:GetServerTimeNow())

local ready: { [Player]: boolean } = {}
-- Joueurs ayant cliqué PLAY : seuls eux comptent pour démarrer une manche (les autres sont au menu).
local queued: { [Player]: boolean } = {}
-- « Rejouer » demandé pendant l'écran de résultats : devient « prêt » au retour au lobby.
local rematch: { [Player]: boolean } = {}
local participants: { [Player]: boolean } = {}
local participantOrder: { Player } = {}
local alive: { [Player]: boolean } = {}
local eliminations: { RoundResolver.Elimination } = {}
local spawnIndex: { [Player]: number } = {}
local roundStartedAt = 0
local roundId = 0 -- identifiant de la manche en cours : garantit une seule récompense par joueur et par manche
local lastEliminationAt = 0
local lastReadyRequest: { [Player]: number } = {}

-- Mode solo : manche d'entraînement contre des bots. Aucune récompense ni statistique (pas d'exploitation possible).
local soloRound = false
local fastStart = false -- vrai après une revanche unanime : compte à rebours court
local countdownSeconds = ROUND.QuickCountdown

-- Partie privée : un groupe par serveur, créé par un hôte, rejoint depuis le menu (ou via une invitation Roblox qui
-- amène l'ami sur ce serveur). Seul l'hôte lance la manche, à partir de PrivateMinPlayers. Les membres sont aussi
-- « queued » (écran Lobby) mais ne passent jamais par le lancement automatique de la partie rapide.
local party: { host: Player, members: { Player }, bots: { number } }? = nil -- bots : niveau (1-10) de chaque bot du groupe
local pendingParty = false
local lastPartyRequest: { [Player]: number } = {}

local roundStateRemote: RemoteEvent
local roundEndedRemote: RemoteEvent
local mapReadyRemote: RemoteEvent
local noticeRemote: RemoteEvent

local function minPlayers(): number
	if RunService:IsStudio() and ROUND.AllowSoloInStudio then
		return 1
	end
	return ROUND.MinimumPlayers
end

local function isPartyMember(player: Player): boolean
	return party ~= nil and table.find(party.members, player) ~= nil
end

-- Retire un joueur du groupe privé ; l'hôte part => le plus ancien membre le remplace ; groupe vide => dissous.
local function leaveParty(player: Player)
	local current = party
	if not current then
		return
	end
	local index = table.find(current.members, player)
	if not index then
		return
	end
	table.remove(current.members, index)
	if #current.members == 0 then
		party = nil
		pendingParty = false
	elseif current.host == player then
		current.host = current.members[1]
	end
end

local function countAlive(): number
	local n = 0
	for _ in alive do
		n += 1
	end
	return n
end

-- Diffusion ------------------------------------------------------------------------------------------------

local function buildSnapshot()
	local list = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, {
			userId = player.UserId,
			name = player.DisplayName,
			queued = queued[player] == true,
			inParty = isPartyMember(player),
			-- Écran de résultats : « prêt » = a cliqué REJOUER (le prêt de la manche terminée ne compte plus).
			ready = if state == "FINISHED" then rematch[player] == true else (ready[player] == true or rematch[player] == true),
			participant = participants[player] == true,
			alive = alive[player] == true,
		})
	end
	-- Les bots de la manche apparaissent comme participants (survivants comptés, noms dans les résultats).
	for _, actor in participantOrder do
		if ActorRegistry.isBot(actor) then
			table.insert(list, {
				userId = actor.UserId,
				name = actor.DisplayName,
				queued = true,
				ready = true,
				participant = true,
				alive = alive[actor] == true,
			})
		end
	end
	return {
		state = state,
		endsAt = endsAt,
		minPlayers = minPlayers(),
		players = list,
		survivors = countAlive(),
		participantCount = #participantOrder,
		party = if party
			then {
				hostUserId = party.host.UserId,
				count = #party.members + #party.bots,
				bots = table.clone(party.bots),
				max = ROUND.MaximumPlayers,
				minToStart = ROUND.PrivateMinPlayers,
			}
			else nil,
	}
end

local function broadcast()
	roundStateRemote:FireAllClients(buildSnapshot())
end

local function announceMap(target: Player?)
	local info = MapService.getCurrent()
	if not info then
		return
	end
	local payload = {
		sizeId = info.layout.sizeId,
		size = info.layout.size,
		cellSize = info.grid.cellSize,
		origin = info.grid.origin,
		seed = info.layout.seed,
		theme = info.layout.theme,
	}
	if target then
		mapReadyRemote:FireClient(target, payload)
	else
		mapReadyRemote:FireAllClients(payload)
	end
end

local function setState(newState: Types.GameState, durationSeconds: number?)
	print(("[RoundService] %s -> %s"):format(state, newState))
	state = newState
	stateEnteredAt = os.clock()
	endsAt = if durationSeconds then workspace:GetServerTimeNow() + durationSeconds else nil
	PlayState.setState(newState)
	broadcast()
end

-- Personnages et spawns -------------------------------------------------------------------------------------

local function placeCharacter(player: Player, character: Model)
	local info = MapService.getCurrent()
	local index = spawnIndex[player]
	if not info or not index then
		return
	end
	local cell = info.layout.spawns[index] or info.layout.spawns[1]
	character:PivotTo(CFrame.new(info.grid:cellToWorld(cell, SPAWN_HEIGHT)))
	MovementService.setupCharacter(player, character)
	DamageService.setAlive(player, true)
	PowerupService.reset(player)
end

local function claimLobbySpawn(player: Player)
	local used: { [number]: boolean } = {}
	for other, index in spawnIndex do
		if other ~= player then
			used[index] = true
		end
	end
	local total = #MapConfig.getSpawns(MapConfig.Sizes[MapConfig.DefaultSize].size)
	for index = 1, total do
		if not used[index] then
			spawnIndex[player] = index
			return
		end
	end
	spawnIndex[player] = ((player.UserId % total) + 1)
end

local function loadCharacter(player: Player)
	if player.Parent ~= Players then
		return
	end
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn(("[RoundService] LoadCharacter a échoué pour %s : %s"):format(player.Name, tostring(err)))
	end
end

local function removeCharacter(player: Player)
	MovementService.cancel(player)
	local character = player.Character
	if character then
		character:Destroy()
	end
end

-- Arène lobby : même générateur, taille par défaut, sans lien avec la manche à venir.
local function buildLobby()
	BombService.clear()
	MapService.generateAndBuild(MapConfig.Sizes[MapConfig.DefaultSize], os.time(), 8)
	announceMap(nil)
end

local function returnToLobby(keepReady: boolean)
	BotService.clear() -- retire les bots (personnages, décisions, statistiques)
	soloRound = false
	local previousReady = ready
	ready = {}
	table.clear(participants)
	table.clear(participantOrder)
	table.clear(alive)
	table.clear(eliminations)
	table.clear(spawnIndex)
	PlayState.clearActive()

	buildLobby()
	for _, player in Players:GetPlayers() do
		if queued[player] and ((keepReady and previousReady[player]) or rematch[player]) then
			ready[player] = true
		end
		rematch[player] = nil
		claimLobbySpawn(player)
		loadCharacter(player)
	end
end

-- Transitions ------------------------------------------------------------------------------------------------

-- botCount : nombre de bots (mode solo) ; 0 pour une manche normale.
local function startCountdown(group: { Player }, botCount: number?, botDifficulties: { number }?)
	BotService.clear()
	countdownSeconds = if fastStart then ROUND.RematchCountdown else ROUND.QuickCountdown
	fastStart = false
	table.clear(participants)
	table.clear(participantOrder)
	table.clear(alive)
	table.clear(eliminations)
	table.clear(spawnIndex)
	PlayState.clearActive()

	roundId += 1
	for index, player in group do
		participants[player] = true
		participantOrder[index] = player
		spawnIndex[player] = index
	end

	-- Bots : participants à part entière (ils comptent dans la taille de l'arène et les spawns).
	local bots: { any } = if botCount and botCount > 0 then BotService.createBots(botCount, botDifficulties) else {}
	soloRound = #bots > 0
	for botIndex, bot in bots do
		local index = #group + botIndex
		participants[bot] = true
		participantOrder[index] = bot
		spawnIndex[bot] = index
		ready[bot] = true
	end
	local total = #group + #bots

	BombService.clear()
	local sizeDef = MapConfig.getSizeForPlayerCount(total)
	local seed = os.time()
	-- Thème d'après la seed ; l'Attribut de test `MapTheme` du Workspace le force (ex. « Volcano »).
	local forced = workspace:GetAttribute("MapTheme")
	local themeId = if typeof(forced) == "string" and MapConfig.Themes[forced] then forced else MapConfig.themeForSeed(seed)
	local info = MapService.generateAndBuild(sizeDef, seed, total, themeId)
	print(("[RoundService] Manche : %d joueur(s) + %d bot(s), arène %s (%d x %d), thème %s, seed %d"):format(
		#group,
		#bots,
		info.layout.sizeId,
		info.layout.size,
		info.layout.size,
		info.layout.theme,
		info.layout.seed
	))
	announceMap(nil)
	setState("COUNTDOWN", countdownSeconds)

	for _, player in Players:GetPlayers() do
		if participants[player] then
			loadCharacter(player)
		else
			removeCharacter(player) -- spectateur : pas de personnage dans l'arène
		end
	end

	-- Personnages des bots, posés sur leurs spawns comme ceux des joueurs.
	for botIndex, bot in bots do
		local model = BotService.buildCharacter(bot, botIndex)
		if model then
			placeCharacter(bot, model)
		end
	end
end

local function beginPlaying()
	for _, player in participantOrder do
		alive[player] = true
		PlayState.setActive(player, true)
	end
	roundStartedAt = os.clock()
	lastEliminationAt = 0
	setState("PLAYING", ROUND.RoundDuration)
	if soloRound then
		BotService.startAI(ActorRegistry.getBots())
	end
end

local function finishRound()
	local participantIds: { number } = {}
	local aliveIds: { [number]: boolean } = {}
	local names: { [string]: string } = {}
	for _, player in participantOrder do
		table.insert(participantIds, player.UserId)
		names[tostring(player.UserId)] = player.DisplayName
		if alive[player] then
			aliveIds[player.UserId] = true
		end
	end
	for _, elimination in eliminations do
		if names[tostring(elimination.userId)] == nil then
			names[tostring(elimination.userId)] = "Joueur " .. elimination.userId
		end
	end

	local duration = os.clock() - roundStartedAt
	local result = RoundResolver.compute(participantIds, aliveIds, eliminations, SIMULTANEOUS_WINDOW, duration)

	PlayState.clearActive()
	-- Récompenses : calculées ici, une fois par manche, avant d'annoncer les résultats.
	-- Manche solo contre des bots : aucune récompense ni statistique (sinon des bots sans risque feraient gagner des pièces).
	local rewards = if soloRound then {} else RewardService.awardRound(roundId, table.clone(participantOrder), result)
	setState("FINISHED", ROUND.ResultDuration)
	roundEndedRemote:FireAllClients({ result = result, names = names, rewards = rewards })
end

local function resetRound()
	setState("RESETTING")
	returnToLobby(false)
	setState("WAITING")
end

-- Joueurs dans la file (PLAY cliqué), dans l'ordre d'arrivée.
local function queuedPlayers(): { Player }
	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
		if queued[player] and not isPartyMember(player) then
			table.insert(list, player)
		end
	end
	return list
end

local function onEliminated(player: Player)
	if state ~= "PLAYING" or not alive[player] then
		return
	end
	alive[player] = nil
	PlayState.setActive(player, false)
	local now = os.clock()
	lastEliminationAt = now
	table.insert(eliminations, { userId = player.UserId, t = now })
	broadcast()
end

-- Joueurs (pas les bots) encore en vie / présents dans la manche : sert à clore une manche solo sans humain.
local function humansAlive(): number
	local n = 0
	for actor in alive do
		if not ActorRegistry.isBot(actor) then
			n += 1
		end
	end
	return n
end

local function humanParticipants(): number
	local n = 0
	for _, actor in participantOrder do
		if not ActorRegistry.isBot(actor) then
			n += 1
		end
	end
	return n
end

-- Écran de résultats : sans attendre la fin du délai, referme la manche dès que plus personne ne doit y rester.
-- - plus aucun humain dans la file (tous ont cliqué MENU ou sont partis) : retour immédiat au lobby ;
-- - tous les humains restants ont cliqué REJOUER : retour immédiat et nouvelle manche (même nombre de bots en solo).
local function checkRematch()
	if state ~= "FINISHED" then
		return
	end
	local humans: { Player } = {}
	for _, actor in participantOrder do
		if not ActorRegistry.isBot(actor) and (actor :: Player).Parent == Players and queued[actor :: Player] then
			table.insert(humans, actor :: Player)
		end
	end
	if #humans == 0 then
		resetRound()
		return
	end
	for _, player in humans do
		if not rematch[player] then
			return
		end
	end
	local wasParty = isPartyMember(humans[1])
	fastStart = true
	resetRound() -- rematch[player] => prêts dès le retour au lobby
	if wasParty then
		pendingParty = true -- revanche unanime d'une partie privée (bots compris) : relance directe
	end
end

local function tick()
	-- Lancement de la partie privée demandé par l'hôte (validé par la remote).
	if pendingParty and (state == "WAITING" or state == "READY") then
		pendingParty = false
		local group: { Player } = {}
		if party then
			for _, member in party.members do
				if member.Parent == Players and queued[member] then
					table.insert(group, member)
				end
			end
		end
		local botLevels: { number } = if party then table.clone(party.bots) else {}
		if #group >= 1 and #group + #botLevels >= ROUND.PrivateMinPlayers then
			for _, member in group do
				ready[member] = true
			end
			startCountdown(group, #botLevels, botLevels)
			return
		end
	end

	if state == "WAITING" then
		-- Partie rapide : pas de lobby ni de « prêt ». Dès qu'il y a assez de joueurs dans la file, le compte à rebours part.
		-- (L'état READY et l'écran Lobby restent en place pour les futurs serveurs privés.)
		local group = queuedPlayers()
		if #group >= minPlayers() then
			while #group > ROUND.MaximumPlayers do
				table.remove(group)
			end
			for _, player in group do
				ready[player] = true
			end
			startCountdown(group)
		end
	elseif state == "READY" then
		local all = queuedPlayers()
		if #all < minPlayers() then
			setState("WAITING")
			return
		end
		local readyList: { Player } = {}
		for _, player in all do
			if ready[player] then
				table.insert(readyList, player)
			end
		end
		local everyoneReady = #readyList == #all
		local timedOut = os.clock() - stateEnteredAt >= ROUND.ReadyTimeout
		if #readyList >= minPlayers() and (everyoneReady or timedOut) then
			startCountdown(readyList)
		end
	elseif state == "COUNTDOWN" then
		local stillReady = 0
		for _, player in participantOrder do
			if ready[player] then
				stillReady += 1
			end
		end
		-- Un participant qui annule ou quitte interrompt le compte à rebours (en solo : si l'humain part ou annule).
		local soloAbandoned = soloRound and humanParticipants() == 0
		if soloAbandoned or stillReady < #participantOrder or (not soloRound and #participantOrder < minPlayers()) then
			print("[RoundService] Compte à rebours interrompu")
			returnToLobby(true)
			setState("WAITING")
		elseif os.clock() - stateEnteredAt >= countdownSeconds then
			beginPlaying()
		end
	elseif state == "PLAYING" then
		local survivors = countAlive()
		local threshold = if #participantOrder <= 1 then 0 else 1 -- le solo Studio dure jusqu'à la mort ou la fin du temps
		local settled = os.clock() - lastEliminationAt >= SETTLE_DELAY
		if survivors <= threshold and settled then
			finishRound()
		elseif soloRound and humansAlive() == 0 and settled then
			finishRound() -- en solo, la manche s'arrête dès que l'humain est éliminé (inutile de regarder les bots)
		elseif os.clock() - roundStartedAt >= ROUND.RoundDuration then
			finishRound()
		end
	elseif state == "FINISHED" then
		if os.clock() - stateEnteredAt >= ROUND.ResultDuration then
			resetRound()
		end
	end
end

-- Joueurs ---------------------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(placeCharacter, player, character)
	end)
	if state == "WAITING" or state == "READY" then
		claimLobbySpawn(player)
		task.spawn(loadCharacter, player)
	end
	-- Pendant une manche : spectateur, sans personnage, jusqu'au retour au lobby.
	broadcast()
end

local function onPlayerRemoving(player: Player)
	ready[player] = nil
	queued[player] = nil
	rematch[player] = nil
	lastReadyRequest[player] = nil
	lastPartyRequest[player] = nil
	leaveParty(player)
	spawnIndex[player] = nil
	if participants[player] then
		participants[player] = nil
		local position = table.find(participantOrder, player)
		if position then
			table.remove(participantOrder, position)
		end
		if state == "PLAYING" and alive[player] then
			alive[player] = nil
			local now = os.clock()
			lastEliminationAt = now
			table.insert(eliminations, { userId = player.UserId, t = now })
		end
	end
	alive[player] = nil
	PlayState.setActive(player, false)
	broadcast()
end

function RoundService.getState(): Types.GameState
	return state
end

-- Envoie à un client qui vient de se connecter l'arène courante et l'état de la manche.
function RoundService.sendFullState(player: Player)
	announceMap(player)
	roundStateRemote:FireClient(player, buildSnapshot())
end

function RoundService.start(remotes: Folder)
	roundStateRemote = remotes:WaitForChild("RoundState") :: RemoteEvent
	roundEndedRemote = remotes:WaitForChild("RoundEnded") :: RemoteEvent
	mapReadyRemote = remotes:WaitForChild("MapReady") :: RemoteEvent
	local setReady = remotes:WaitForChild("SetReady") :: RemoteEvent
	noticeRemote = remotes:WaitForChild("Notice") :: RemoteEvent

	buildLobby()

	DamageService.onEliminated(onEliminated)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	setReady.OnServerEvent:Connect(function(player: Player, value: any)
		if typeof(value) ~= "boolean" then
			return
		end
		local now = os.clock()
		if now - (lastReadyRequest[player] or 0) < GameConfig.RemoteLimits.ReadyToggleMinInterval then
			return
		end
		lastReadyRequest[player] = now

		if not queued[player] then
			return -- il faut d'abord cliquer PLAY
		end
		if state == "WAITING" or state == "READY" or (state == "COUNTDOWN" and participants[player]) then
			ready[player] = if value then true else nil
			broadcast()
		elseif state == "FINISHED" then
			rematch[player] = if value then true else nil -- « Rejouer » : prêt dès le retour au lobby
			broadcast()
			checkRematch()
		end
	end)

	-- PLAY / retour au menu. Un participant encore en jeu ne peut quitter la file qu'en abandonnant explicitement
	-- (menu de pause, 2e argument `true`) : il est alors éliminé, puis retiré de la file.
	local setQueued = remotes:WaitForChild("SetQueued") :: RemoteEvent
	setQueued.OnServerEvent:Connect(function(player: Player, value: any, forfeit: any)
		if typeof(value) ~= "boolean" or (forfeit ~= nil and typeof(forfeit) ~= "boolean") then
			return
		end
		local now = os.clock()
		if now - (lastReadyRequest[player] or 0) < GameConfig.RemoteLimits.ReadyToggleMinInterval then
			return
		end
		lastReadyRequest[player] = now

		local lockedIn = participants[player]
			and (state == "COUNTDOWN" or (state == "PLAYING" and alive[player] == true))
		if not value and lockedIn then
			if forfeit ~= true then
				return
			end
			if state == "PLAYING" and alive[player] == true then
				DamageService.eliminate(player) -- déclenche onEliminated : mise à jour de la manche et diffusion
			end
			-- Pendant le compte à rebours : la file est quittée ci-dessous, ce qui interrompt le départ.
		end
		queued[player] = if value then true else nil
		if not value then
			ready[player] = nil
			rematch[player] = nil
			leaveParty(player)
		end
		broadcast()
		checkRematch()
	end)

	-- Partie privée : créer, rejoindre, lancer. Le client n'envoie qu'un mot ; tout est revalidé ici.
	local partyAction = remotes:WaitForChild("PartyAction") :: RemoteEvent
	partyAction.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
		if typeof(action) ~= "string" then
			return
		end
		local now = os.clock()
		if now - (lastPartyRequest[player] or 0) < GameConfig.RemoteLimits.ReadyToggleMinInterval then
			return
		end
		lastPartyRequest[player] = now

		local open = state == "WAITING" or state == "READY"
		if action == "create" then
			if queued[player] then
				return
			end
			if not open then
				noticeRemote:FireClient(player, "Une manche est en cours : attends la fin pour créer une partie privée.")
				return
			end
			if party then
				noticeRemote:FireClient(player, "Une partie privée existe déjà sur ce serveur : rejoins-la.")
				return
			end
			party = { host = player, members = { player }, bots = {} }
			queued[player] = true
			ready[player] = nil
			broadcast()
		elseif action == "join" then
			local current = party
			if queued[player] or not current then
				return
			end
			if not open then
				noticeRemote:FireClient(player, "Une manche est en cours : attends la fin pour rejoindre la partie.")
				return
			end
			if #current.members + #current.bots >= ROUND.MaximumPlayers then
				noticeRemote:FireClient(player, "La partie privée est complète.")
				return
			end
			table.insert(current.members, player)
			queued[player] = true
			ready[player] = nil
			broadcast()
		elseif action == "start" then
			local current = party
			if not current or current.host ~= player or not open then
				return
			end
			if #current.members + #current.bots < ROUND.PrivateMinPlayers then
				noticeRemote:FireClient(player, ("Il faut au moins %d joueurs pour lancer la partie."):format(ROUND.PrivateMinPlayers))
				return
			end
			pendingParty = true
		elseif action == "addBot" or action == "removeBot" or action == "botLevel" then
			-- Gestion des bots du groupe : hôte seulement, hors manche.
			local current = party
			if not current or current.host ~= player or not open then
				return
			end
			if action == "addBot" then
				if #current.members + #current.bots >= ROUND.MaximumPlayers then
					noticeRemote:FireClient(player, "La partie est complète.")
					return
				end
				local level = ROUND.DefaultBotDifficulty
				if typeof(arg) == "number" and arg == math.floor(arg) and arg >= 1 and arg <= ROUND.MaxBotDifficulty then
					level = arg
				end
				table.insert(current.bots, level)
			elseif action == "removeBot" then
				if typeof(arg) ~= "number" or arg ~= math.floor(arg) or arg < 1 or arg > #current.bots then
					return
				end
				table.remove(current.bots, arg)
			else
				if typeof(arg) ~= "table" then
					return
				end
				local index, level = arg.index, arg.level
				if
					typeof(index) ~= "number"
					or typeof(level) ~= "number"
					or index ~= math.floor(index)
					or level ~= math.floor(level)
					or index < 1
					or index > #current.bots
					or level < 1
					or level > ROUND.MaxBotDifficulty
				then
					return
				end
				current.bots[index] = level
			end
			broadcast()
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				warn("[RoundService] Erreur dans tick : " .. tostring(err))
			end
			task.wait(TICK_INTERVAL)
		end
	end)
end

return RoundService
