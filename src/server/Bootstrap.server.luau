--!strict
-- Point d'entrée serveur.
-- PHASE 1 (temporaire) : une arène est générée au démarrage et les joueurs apparaissent sur ses spawns.
-- La gestion des manches (RoundService) remplacera ce comportement en Phase 3.
--
-- Options de test, à définir comme Attributs du Workspace avant de lancer :
--   MapSize = "Small" | "Medium" | "Large"   (défaut : MapConfig.DefaultSize)
--   MapSeed = <nombre>                       (défaut : os.time())

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local Services = script.Parent.Services
local BombService = require(Services.BombService)
local DamageService = require(Services.DamageService)
local MapService = require(Services.MapService)
local MovementService = require(Services.MovementService)
local PowerupService = require(Services.PowerupService)

local SPAWN_HEIGHT = 3 -- studs au-dessus du sol

-- Remotes -------------------------------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in {
	"ClientReady",
	"MapReady",
	"RequestMove",
	"MoveRejected",
	"RequestPlaceBomb",
	"Explosion",
	"StatsChanged",
	"PlayerEliminated",
} do
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
end
remotes.Parent = ReplicatedStorage

-- Arène ---------------------------------------------------------------------------------------------------

local sizeName = workspace:GetAttribute("MapSize")
local sizeDef = if typeof(sizeName) == "string" and MapConfig.Sizes[sizeName]
	then MapConfig.Sizes[sizeName]
	else MapConfig.Sizes[MapConfig.DefaultSize]
local seedAttribute = workspace:GetAttribute("MapSeed")
local seed = if typeof(seedAttribute) == "number" then math.floor(seedAttribute) else os.time()

local mapInfo = MapService.generateAndBuild(sizeDef, seed, GameConfig.Round.MaximumPlayers)
print(("[BOM BATTLE] Arène %s (%d x %d), seed %d"):format(mapInfo.layout.sizeId, mapInfo.layout.size, mapInfo.layout.size, mapInfo.layout.seed))

MovementService.start(remotes, function()
	local info = MapService.getCurrent()
	return if info then info.grid else nil
end)
PowerupService.start(remotes)
DamageService.start(remotes)
BombService.start(remotes)

-- Spawns (temporaire) -------------------------------------------------------------------------------------

local spawnOwners: { [number]: Player } = {} -- index de spawn -> joueur
local spawnIndexByPlayer: { [Player]: number } = {}

local function claimSpawnIndexFor(player: Player): number
	local existing = spawnIndexByPlayer[player]
	if existing then
		return existing
	end
	for index = 1, #mapInfo.layout.spawns do
		if spawnOwners[index] == nil then
			spawnOwners[index] = player
			spawnIndexByPlayer[player] = index
			return index
		end
	end
	return 1 -- plus de spawn libre (ne devrait pas arriver avec MaximumPlayers) : on réutilise le premier
end

local function releaseSpawn(player: Player)
	local index = spawnIndexByPlayer[player]
	if index and spawnOwners[index] == player then
		spawnOwners[index] = nil
	end
	spawnIndexByPlayer[player] = nil
end

local function onCharacterAdded(player: Player, character: Model)
	local index = claimSpawnIndexFor(player)
	local cell = mapInfo.layout.spawns[index]
	character:PivotTo(CFrame.new(mapInfo.grid:cellToWorld(cell, SPAWN_HEIGHT)))
	MovementService.setupCharacter(player, character)
	-- PHASE 2 (temporaire) : chaque apparition remet les statistiques à zéro et rend le joueur vivant.
	-- En Phase 3, c'est le RoundService qui fera cela au début de chaque manche.
	DamageService.setAlive(player, true)
	PowerupService.reset(player)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	releaseSpawn(player)
end)

-- Le client signale qu'il est prêt à recevoir les informations d'arène.
local clientReadyAt: { [Player]: number } = {}
local clientReadyEvent = remotes:FindFirstChild("ClientReady") :: RemoteEvent
local mapReadyEvent = remotes:FindFirstChild("MapReady") :: RemoteEvent
clientReadyEvent.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if now - (clientReadyAt[player] or 0) < 1 then
		return
	end
	clientReadyAt[player] = now
	local info = MapService.getCurrent()
	if not info then
		return
	end
	mapReadyEvent:FireClient(player, {
		sizeId = info.layout.sizeId,
		size = info.layout.size,
		cellSize = info.grid.cellSize,
		origin = info.grid.origin,
		seed = info.layout.seed,
	})
end)
Players.PlayerRemoving:Connect(function(player)
	clientReadyAt[player] = nil
end)
