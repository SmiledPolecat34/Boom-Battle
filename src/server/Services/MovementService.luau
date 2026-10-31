--!strict
-- Déplacements : le client demande une case, le serveur valide, calcule le chemin et pilote le personnage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local GridService = require(script.Parent.GridService)
local PlayState = require(script.Parent.PlayState)

local WAYPOINT_REACHED_DISTANCE = 1.5 -- studs : on enchaîne la case suivante avant de s'arrêter
local FINAL_REACHED_DISTANCE = 0.8
local LEG_TIMEOUT = 3 -- secondes avant d'abandonner un trajet bloqué

type PlayerState = {
	lastRequest: number,
	token: number, -- incrémenté à chaque nouveau trajet : annule le précédent
}

local MovementService = {}

local states: { [Player]: PlayerState } = {}
local getGrid: (() -> GridService.GridService?)? = nil
local connections: { RBXScriptConnection } = {}

local function getState(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = { lastRequest = 0, token = 0 }
		states[player] = state
	end
	return state
end

local function getLiveCharacter(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

local function flatDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function walkPath(player: Player, grid: GridService.GridService, path: { Types.Cell }, token: number)
	local state = getState(player)
	for index, cell in path do
		local humanoid, root = getLiveCharacter(player)
		if not humanoid or not root or state.token ~= token then
			return
		end
		-- Une bombe a pu être posée sur le trajet depuis le calcul du chemin : on s'arrête devant.
		if not grid:isWalkable(cell.x, cell.y) then
			return
		end
		local isLast = index == #path
		local target = grid:cellToWorld(cell, root.Position.Y)
		humanoid:MoveTo(target)

		local startedAt = os.clock()
		local threshold = if isLast then FINAL_REACHED_DISTANCE else WAYPOINT_REACHED_DISTANCE
		while flatDistance(root.Position, target) > threshold do
			if state.token ~= token or humanoid.Health <= 0 or os.clock() - startedAt > LEG_TIMEOUT then
				return
			end
			task.wait()
		end
	end
end

local function reject(player: Player, remotes: Folder, target: any)
	local event = remotes:FindFirstChild("MoveRejected")
	if event and event:IsA("RemoteEvent") then
		event:FireClient(player, target)
	end
end

local function handleMoveRequest(player: Player, remotes: Folder, payload: any)
	-- 1. Forme de la charge utile : jamais de confiance dans le client.
	if typeof(payload) ~= "table" then
		return
	end
	local x, y = payload.x, payload.y
	if typeof(x) ~= "number" or typeof(y) ~= "number" then
		return
	end
	if x ~= math.floor(x) or y ~= math.floor(y) then -- rejette aussi NaN et fractions
		return
	end

	-- 2. Cadence.
	local state = getState(player)
	local now = os.clock()
	if now - state.lastRequest < GameConfig.RemoteLimits.MoveRequestMinInterval then
		return
	end
	state.lastRequest = now

	-- 3. Contexte de jeu.
	local grid = if getGrid then getGrid() else nil
	local humanoid, root = getLiveCharacter(player)
	if not grid or not humanoid or not root then
		return
	end
	-- Hors lobby, seuls les joueurs encore en vie d'une manche en cours peuvent bouger.
	if not PlayState.canMove(player) then
		return
	end

	-- 4. Position de départ : celle du serveur, jamais celle annoncée par le client.
	local from = grid:worldToCell(root.Position)
	if not from then
		reject(player, remotes, payload)
		return
	end

	local path = grid:findPath(from, { x = x, y = y })
	if not path then
		reject(player, remotes, { x = x, y = y })
		return
	end

	state.token += 1
	local token = state.token
	task.spawn(walkPath, player, grid, path, token)
end

-- Prépare un personnage fraîchement apparu : vitesse, pas de saut, serveur propriétaire du réseau.
function MovementService.setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") then
		return
	end
	humanoid.WalkSpeed = GameConfig.Movement.BaseWalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.AutoRotate = true

	-- Le propriétaire réseau ne peut être changé qu'une fois la Part dans le Workspace.
	local ok, err = pcall(function()
		root:SetNetworkOwner(nil)
	end)
	if not ok then
		warn(("[MovementService] SetNetworkOwner a échoué pour %s : %s"):format(player.Name, tostring(err)))
	end
	getState(player).token += 1 -- annule un éventuel trajet de la vie précédente
end

function MovementService.cancel(player: Player)
	getState(player).token += 1
end

function MovementService.start(remotes: Folder, gridProvider: () -> GridService.GridService?)
	getGrid = gridProvider
	local requestMove = remotes:WaitForChild("RequestMove") :: RemoteEvent
	table.insert(
		connections,
		requestMove.OnServerEvent:Connect(function(player: Player, payload: any)
			handleMoveRequest(player, remotes, payload)
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			states[player] = nil
		end)
	)
end

function MovementService.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(states)
	getGrid = nil
end

return MovementService
