--!strict
-- Pose des bombes, mèche, explosions (via ExplosionResolver), destruction des caisses et dégâts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local DamageService = require(script.Parent.DamageService)
local ExplosionResolver = require(script.Parent.ExplosionResolver)
local MapService = require(script.Parent.MapService)
local PlayState = require(script.Parent.PlayState)
local PowerupService = require(script.Parent.PowerupService)

local DAMAGE_TICK = 0.05
local BOMB_HEIGHT = 1.6

local BombService = {}

local bombsByKey: { [number]: ExplosionResolver.BombRecord } = {}
local activeByOwner: { [number]: number } = {} -- userId -> bombes posées non explosées
local lastPlaceRequest: { [Player]: number } = {}
local explosionRemote: RemoteEvent? = nil
local nextBombId = 0

local function getLivePlayerCell(player: Player, info: MapService.MapInfo): Types.Cell?
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

	if explosionRemote then
		explosionRemote:FireAllClients({ cells = result.cells, duration = duration })
	end

	-- Dégâts pendant toute la durée des flammes ; un joueur n'est touché qu'une fois par explosion.
	local hit: { [Player]: boolean } = {}
	task.spawn(function()
		local startedAt = os.clock()
		repeat
			if MapService.getCurrent() ~= info then
				return
			end
			for _, player in Players:GetPlayers() do
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

local function makeBombPart(info: MapService.MapInfo, cell: Types.Cell): Part
	local part = Instance.new("Part")
	part.Name = "Bomb"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(3, 3, 3)
	part.Color = Color3.fromRGB(35, 35, 45)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false -- le blocage est logique (GridService) ; évite de coincer le poseur
	part.CFrame = CFrame.new(info.grid:cellToWorld(cell, BOMB_HEIGHT))
	part.Parent = info.folder
	return part
end

local function handlePlaceBomb(player: Player)
	local now = os.clock()
	if now - (lastPlaceRequest[player] or 0) < GameConfig.RemoteLimits.PlaceBombMinInterval then
		return
	end
	lastPlaceRequest[player] = now

	if not PlayState.canBomb(player) then
		return
	end
	local info = MapService.getCurrent()
	if not info then
		return
	end
	-- La case vient de la position SERVEUR du joueur : le client ne peut pas choisir où poser.
	local cell = getLivePlayerCell(player, info)
	if not cell then
		return
	end
	local stats = PowerupService.getStats(player)
	if (activeByOwner[player.UserId] or 0) >= stats.bombCapacity then
		return
	end
	if info.grid:getKind(cell.x, cell.y) ~= "EMPTY" or info.grid:hasBomb(cell.x, cell.y) then
		return
	end

	nextBombId += 1
	local bomb: ExplosionResolver.BombRecord = {
		cell = cell,
		range = stats.blastRange,
		id = nextBombId,
		ownerId = player.UserId,
		exploded = false,
		mapInfo = info,
		part = makeBombPart(info, cell),
	}
	bombsByKey[info.grid:key(cell.x, cell.y)] = bomb
	info.grid:setBomb(cell.x, cell.y, true)
	activeByOwner[player.UserId] = (activeByOwner[player.UserId] or 0) + 1

	task.delay(GameConfig.Bomb.FuseTime, function()
		explode(bomb)
	end)
end

-- À appeler quand l'arène est détruite ou régénérée.
function BombService.clear()
	table.clear(bombsByKey)
	table.clear(activeByOwner)
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
