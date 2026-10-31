--!strict
-- Pose des bombes, mèche, explosions (via ExplosionResolver), destruction des caisses et dégâts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local ActorRegistry = require(script.Parent.ActorRegistry)
local DamageService = require(script.Parent.DamageService)
local ExplosionResolver = require(script.Parent.ExplosionResolver)
local MapService = require(script.Parent.MapService)
local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local GameEvents = require(script.Parent.GameEvents)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayState = require(script.Parent.PlayState)
local PowerupService = require(script.Parent.PowerupService)

local DAMAGE_TICK = 0.05
local BOMB_HEIGHT = 1.6

local BombService = {}

local bombsByKey: { [number]: ExplosionResolver.BombRecord } = {}
local activeByOwner: { [number]: number } = {} -- userId -> bombes posées non explosées
local lastPlaceRequest: { [Player]: number } = {}
local flameUntil: { [number]: number } = {} -- clé de case -> heure de fin des flammes
local explosionRemote: RemoteEvent? = nil
local nextBombId = 0

-- Apparence équipée par un joueur (purement visuelle : taille, portée et délai ne changent jamais).
local function equippedCosmetic(userId: number, kind: CosmeticConfig.Kind): CosmeticConfig.Cosmetic
	local player = Players:GetPlayerByUserId(userId)
	local profile = if player then PlayerDataService.get(player) else nil
	local id = if profile then profile.EquippedCosmetics[kind] else CosmeticConfig.Defaults[kind]
	return CosmeticConfig.get(id) or (CosmeticConfig.get(CosmeticConfig.Defaults[kind]) :: CosmeticConfig.Cosmetic)
end

local function getLivePlayerCell(player: any, info: MapService.MapInfo): Types.Cell?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") or not DamageService.isAlive(player) then
		return nil
	end
	return info.grid:worldToCell(root.Position)
end

local function explode(first: ExplosionResolver.BombRecord)
	local info = MapService.getCurrent()
	-- Bombe déjà explosée (chaîne) ou appartenant à une ancienne arène : ignorée. Garantit « une seule explosion ».
	if first.exploded or not info or first.mapInfo ~= info then
		return
	end

	local result = ExplosionResolver.resolve(info.grid, bombsByKey, first)

	for _, bomb in result.bombs do
		bomb.exploded = true
		local key = info.grid:key(bomb.cell.x, bomb.cell.y)
		bombsByKey[key] = nil
		info.grid:setBomb(bomb.cell.x, bomb.cell.y, false)
		local ownerId = bomb.ownerId :: number
		activeByOwner[ownerId] = math.max(0, (activeByOwner[ownerId] or 1) - 1)
		local part = bomb.part :: Part
		part:Destroy()
	end

	local blastKeys: { [number]: boolean } = {}
	for _, cell in result.cells do
		blastKeys[info.grid:key(cell.x, cell.y)] = true
		PowerupService.destroyAt(info, cell) -- les bonus déjà au sol sont détruits par les flammes
	end

	-- Caisses : la grille est mise à jour tout de suite ; un éventuel bonus n'apparaît qu'après les flammes.
	for _, cell in result.crates do
		local key = info.grid:key(cell.x, cell.y)
		info.grid:setKind(cell.x, cell.y, "EMPTY")
		local crate = info.crates[key]
		if crate then
			crate:Destroy()
			info.crates[key] = nil
		end
	end
	local duration = GameConfig.Bomb.ExplosionDuration
	task.delay(duration, function()
		if MapService.getCurrent() ~= info then
			return
		end
		for _, cell in result.crates do
			PowerupService.maybeDrop(info, cell)
		end
	end)

	if #result.crates > 0 then
		GameEvents.fireCratesDestroyed(first.ownerId :: number, #result.crates)
	end

	if explosionRemote then
		-- Couleur de l'effet choisi par le poseur de la bombe déclenchante : purement visuelle.
		local effect = equippedCosmetic(first.ownerId :: number, "effect")
		explosionRemote:FireAllClients({ cells = result.cells, duration = duration, color = effect.color })
	end

	-- Dégâts pendant toute la durée des flammes ; un joueur n'est touché qu'une fois par explosion.
	local hit: { [any]: boolean } = {}
	local flameEnd = os.clock() + duration
	for key in blastKeys do
		flameUntil[key] = flameEnd
	end
	task.spawn(function()
		local startedAt = os.clock()
		repeat
			if MapService.getCurrent() ~= info then
				return
			end
			for _, player in ActorRegistry.all() do
				if not hit[player] then
					local cell = getLivePlayerCell(player, info)
					if cell and blastKeys[info.grid:key(cell.x, cell.y)] then
						hit[player] = true
						DamageService.hit(player)
					end
				end
			end
			task.wait(DAMAGE_TICK)
		until os.clock() - startedAt >= duration
	end)
end

local function makeBombPart(info: MapService.MapInfo, cell: Types.Cell, ownerUserId: number): Part
	local skin = equippedCosmetic(ownerUserId, "bomb")
	local part = Instance.new("Part")
	part.Name = "Bomb"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(3, 3, 3) -- identique pour tous les skins
	part.Color = skin.color
	part.Material = skin.material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false -- le blocage est logique (GridService) ; évite de coincer le poseur
	part.CFrame = CFrame.new(info.grid:cellToWorld(cell, BOMB_HEIGHT))
	part.Parent = info.folder
	return part
end

-- Pose une bombe pour un acteur (joueur OU bot) à SA position serveur. Toutes les vérifications de jeu sont ici ;
-- la cadence des demandes d'un client est limitée à part (handlePlaceBomb). Retourne true si une bombe est posée.
function BombService.placeBomb(actor: any): boolean
	if not PlayState.canBomb(actor) then
		return false
	end
	local info = MapService.getCurrent()
	if not info then
		return false
	end
	-- La case vient de la position SERVEUR de l'acteur : jamais choisie par un client.
	local cell = getLivePlayerCell(actor, info)
	if not cell then
		return false
	end
	local stats = PowerupService.getStats(actor)
	if (activeByOwner[actor.UserId] or 0) >= stats.bombCapacity then
		return false
	end
	if info.grid:getKind(cell.x, cell.y) ~= "EMPTY" or info.grid:hasBomb(cell.x, cell.y) then
		return false
	end

	nextBombId += 1
	local bomb: ExplosionResolver.BombRecord = {
		cell = cell,
		range = stats.blastRange,
		id = nextBombId,
		ownerId = actor.UserId,
		exploded = false,
		mapInfo = info,
		part = makeBombPart(info, cell, actor.UserId),
	}
	bombsByKey[info.grid:key(cell.x, cell.y)] = bomb
	info.grid:setBomb(cell.x, cell.y, true)
	activeByOwner[actor.UserId] = (activeByOwner[actor.UserId] or 0) + 1

	task.delay(GameConfig.Bomb.FuseTime, function()
		explode(bomb)
	end)
	return true
end

-- L'acteur peut-il encore poser une bombe (capacité) ? Utilisé par les bots avant de décider.
function BombService.canPlaceBomb(actor: any): boolean
	local stats = PowerupService.getStats(actor)
	return (activeByOwner[actor.UserId] or 0) < stats.bombCapacity
end

-- Cases menacées : zone de toutes les bombes posées (chaînes comprises) et flammes encore actives.
-- Les bots s'en servent pour fuir ; clé = grid:key(x, y).
function BombService.getDangerKeys(info: MapService.MapInfo): { [number]: boolean }
	local danger: { [number]: boolean } = {}
	for _, bomb in bombsByKey do
		if bomb.mapInfo == info and not bomb.exploded then
			local result = ExplosionResolver.resolve(info.grid, bombsByKey, bomb)
			for _, cell in result.cells do
				danger[info.grid:key(cell.x, cell.y)] = true
			end
		end
	end
	local now = os.clock()
	for key, expiresAt in flameUntil do
		if expiresAt > now then
			danger[key] = true
		else
			flameUntil[key] = nil
		end
	end
	return danger
end

local function handlePlaceBomb(player: Player)
	local now = os.clock()
	if now - (lastPlaceRequest[player] or 0) < GameConfig.RemoteLimits.PlaceBombMinInterval then
		return
	end
	lastPlaceRequest[player] = now
	BombService.placeBomb(player)
end

-- À appeler quand l'arène est détruite ou régénérée.
function BombService.clear()
	table.clear(bombsByKey)
	table.clear(activeByOwner)
	table.clear(flameUntil)
	PowerupService.clear()
end

function BombService.start(remotes: Folder)
	explosionRemote = remotes:WaitForChild("Explosion") :: RemoteEvent
	local placeBomb = remotes:WaitForChild("RequestPlaceBomb") :: RemoteEvent
	placeBomb.OnServerEvent:Connect(handlePlaceBomb)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastPlaceRequest[player] = nil
	end)
end

return BombService
