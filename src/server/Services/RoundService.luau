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
local BombService = require(script.Parent.BombService)
local DamageService = require(script.Parent.DamageService)
local MapService = require(script.Parent.MapService)
local MovementService = require(script.Parent.MovementService)
local PlayState = require(script.Parent.PlayState)
local PowerupService = require(script.Parent.PowerupService)
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
local lastEliminationAt = 0
local lastReadyRequest: { [Player]: number } = {}

local roundStateRemote: RemoteEvent
local roundEndedRemote: RemoteEvent
local mapReadyRemote: RemoteEvent

local function minPlayers(): number
	if RunService:IsStudio() and ROUND.AllowSoloInStudio then
		return 1
	end
	return ROUND.MinimumPlayers
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
			ready = ready[player] == true or rematch[player] == true,
			participant = participants[player] == true,
			alive = alive[player] == true,
		})
	end
	return {
		state = state,
		endsAt = endsAt,
		minPlayers = minPlayers(),
		players = list,
		survivors = countAlive(),
		participantCount = #participantOrder,
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

local function startCountdown(group: { Player })
	table.clear(participants)
	table.clear(participantOrder)
	table.clear(alive)
	table.clear(eliminations)
	table.clear(spawnIndex)
	PlayState.clearActive()

	for index, player in group do
		participants[player] = true
		participantOrder[index] = player
		spawnIndex[player] = index
	end

	BombService.clear()
	local sizeDef = MapConfig.getSizeForPlayerCount(#group)
	local info = MapService.generateAndBuild(sizeDef, os.time(), #group)
	print(("[RoundService] Manche : %d joueur(s), arène %s (%d x %d), seed %d"):format(
		#group,
		info.layout.sizeId,
		info.layout.size,
		info.layout.size,
		info.layout.seed
	))
	announceMap(nil)
	setState("COUNTDOWN", ROUND.ReadyCountdown)

	for _, player in Players:GetPlayers() do
		if participants[player] then
			loadCharacter(player)
		else
			removeCharacter(player) -- spectateur : pas de personnage dans l'arène
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
	setState("FINISHED", ROUND.ResultDuration)
	roundEndedRemote:FireAllClients({ result = result, names = names })
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
		if queued[player] then
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

local function tick()
	if state == "WAITING" then
		if #queuedPlayers() >= minPlayers() then
			setState("READY")
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
		-- Un participant qui annule ou quitte interrompt le compte à rebours.
		if stillReady < #participantOrder or #participantOrder < minPlayers() then
			print("[RoundService] Compte à rebours interrompu")
			returnToLobby(true)
			setState("READY")
		elseif os.clock() - stateEnteredAt >= ROUND.ReadyCountdown then
			beginPlaying()
		end
	elseif state == "PLAYING" then
		local survivors = countAlive()
		local threshold = if #participantOrder <= 1 then 0 else 1 -- le solo Studio dure jusqu'à la mort ou la fin du temps
		if survivors <= threshold and os.clock() - lastEliminationAt >= SETTLE_DELAY then
			finishRound()
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

	buildLobby()

	DamageService.Eliminated:Connect(onEliminated)
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
		end
	end)

	-- PLAY / retour au menu. Un participant encore en jeu ne peut pas quitter la file.
	local setQueued = remotes:WaitForChild("SetQueued") :: RemoteEvent
	setQueued.OnServerEvent:Connect(function(player: Player, value: any)
		if typeof(value) ~= "boolean" then
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
			return
		end
		queued[player] = if value then true else nil
		if not value then
			ready[player] = nil
			rematch[player] = nil
		end
		broadcast()
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
