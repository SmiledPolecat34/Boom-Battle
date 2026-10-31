--!strict
-- Statistiques des joueurs, bonus au sol et ramassage. Le serveur est la seule source de vérité des statistiques.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local MapService = require(script.Parent.MapService)

local PICKUP_POLL_INTERVAL = 0.1
local PICKUP_HEIGHT = 1.6

-- Libellé court et couleur par bonus : la forme (Ball / Block / Cylinder / Wedge) + le texte, jamais la couleur seule.
local APPEARANCE = {
	BombPlus = { label = "B+", color = Color3.fromRGB(60, 60, 70), shape = Enum.PartType.Ball },
	FirePlus = { label = "F+", color = Color3.fromRGB(235, 90, 40), shape = Enum.PartType.Block },
	SpeedPlus = { label = "S+", color = Color3.fromRGB(60, 190, 235), shape = Enum.PartType.Cylinder },
	Shield = { label = "SH", color = Color3.fromRGB(110, 90, 235), shape = Enum.PartType.Ball },
}

type Pickup = { id: Types.PowerupId, part: Part, mapFolder: Folder }

local PowerupService = {}

local statsByPlayer: { [Player]: Types.PlayerStats } = {}
local pickups: { [number]: Pickup } = {} -- clé : grid:key(x, y)
local statsChanged: RemoteEvent? = nil
local dropRng: Random? = nil
local dropRngMap: MapService.MapInfo? = nil

local function defaultStats(): Types.PlayerStats
	return {
		bombCapacity = GameConfig.Bomb.DefaultCapacity,
		blastRange = GameConfig.Bomb.DefaultBlastRange,
		speedPickups = 0,
		hasShield = false,
	}
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return player:GetAttribute("Alive") == true and humanoid ~= nil and humanoid.Health > 0
end

local function publish(player: Player)
	local stats = statsByPlayer[player]
	if statsChanged and stats then
		statsChanged:FireClient(player, {
			bombCapacity = stats.bombCapacity,
			blastRange = stats.blastRange,
			speedPickups = stats.speedPickups,
			hasShield = stats.hasShield,
		})
	end
end

local function applySpeed(player: Player)
	local stats = statsByPlayer[player]
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if stats and humanoid then
		humanoid.WalkSpeed = GameConfig.Movement.BaseWalkSpeed
			+ stats.speedPickups * GameConfig.Movement.SpeedBonusPerPickup
	end
end

function PowerupService.getStats(player: Player): Types.PlayerStats
	local stats = statsByPlayer[player]
	if not stats then
		stats = defaultStats()
		statsByPlayer[player] = stats
	end
	return stats
end

-- À appeler à chaque apparition de personnage (et au début de chaque manche).
function PowerupService.reset(player: Player)
	statsByPlayer[player] = defaultStats()
	applySpeed(player)
	publish(player)
end

-- Consomme le bouclier s'il existe. Retourne true si une explosion a été absorbée.
function PowerupService.consumeShield(player: Player): boolean
	local stats = statsByPlayer[player]
	if stats and stats.hasShield then
		stats.hasShield = false
		publish(player)
		return true
	end
	return false
end

local function apply(player: Player, id: Types.PowerupId)
	local stats = PowerupService.getStats(player)
	local definition = ItemConfig.Powerups[id]
	if id == "BombPlus" then
		stats.bombCapacity = math.min(GameConfig.Bomb.MaxCapacity, stats.bombCapacity + definition.amount)
	elseif id == "FirePlus" then
		stats.blastRange = math.min(GameConfig.Bomb.MaxBlastRange, stats.blastRange + definition.amount)
	elseif id == "SpeedPlus" then
		stats.speedPickups = math.min(GameConfig.Movement.MaxSpeedPickups, stats.speedPickups + definition.amount)
		applySpeed(player)
	elseif id == "Shield" then
		stats.hasShield = true
	end
	publish(player)
end

local function spawnPickup(info: MapService.MapInfo, cell: Types.Cell, id: Types.PowerupId)
	local key = info.grid:key(cell.x, cell.y)
	if pickups[key] then
		return
	end
	local look = APPEARANCE[id]
	local part = Instance.new("Part")
	part.Name = "Powerup_" .. id
	part.Anchored = true
	part.CanCollide = false
	part.Shape = look.shape
	part.Size = Vector3.new(2, 2, 2)
	part.Color = look.color
	part.Material = Enum.Material.Neon
	part.CFrame = CFrame.new(info.grid:cellToWorld(cell, PICKUP_HEIGHT))
	part:SetAttribute("PowerupId", id)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(60, 30)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = look.label
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0
	text.Parent = gui
	gui.Parent = part

	part.Parent = info.folder
	pickups[key] = { id = id, part = part, mapFolder = info.folder }
end

-- Tire un éventuel bonus pour une caisse détruite. Le tirage dépend de la seed de la map (reproductible).
function PowerupService.maybeDrop(info: MapService.MapInfo, cell: Types.Cell)
	if dropRngMap ~= info or not dropRng then
		dropRng = Random.new(info.layout.seed + 7919)
		dropRngMap = info
	end
	local rng = dropRng :: Random
	if rng:NextNumber() >= GameConfig.Powerups.DropChancePerCrate then
		return
	end
	local order = ItemConfig.PowerupOrder
	spawnPickup(info, cell, order[rng:NextInteger(1, #order)] :: Types.PowerupId)
end

function PowerupService.destroyAt(info: MapService.MapInfo, cell: Types.Cell)
	local key = info.grid:key(cell.x, cell.y)
	local pickup = pickups[key]
	if pickup then
		pickup.part:Destroy()
		pickups[key] = nil
	end
end

function PowerupService.clear()
	for key, pickup in pickups do
		pickup.part:Destroy()
		pickups[key] = nil
	end
	dropRng, dropRngMap = nil, nil
end

function PowerupService.start(remotes: Folder)
	statsChanged = remotes:WaitForChild("StatsChanged") :: RemoteEvent

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < PICKUP_POLL_INTERVAL then
			return
		end
		elapsed = 0
		local info = MapService.getCurrent()
		if not info or next(pickups) == nil then
			return
		end
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") and isAlive(player) then
				local cell = info.grid:worldToCell(root.Position)
				if cell then
					local key = info.grid:key(cell.x, cell.y)
					local pickup = pickups[key]
					if pickup then
						pickups[key] = nil -- retiré avant d'appliquer : un seul joueur peut le ramasser
						pickup.part:Destroy()
						apply(player, pickup.id)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		statsByPlayer[player] = nil
	end)
end

return PowerupService
