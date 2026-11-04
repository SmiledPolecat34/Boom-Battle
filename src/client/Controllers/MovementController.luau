--!strict
-- Convertit une position écran en case de la grille et envoie la demande au serveur.
-- Le client n'envoie QUE la case visée ; le serveur décide du chemin et du déplacement.
-- Le repère visuel est local : blanc = demande envoyée, rouge = refusée par le serveur.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)
local SettingsStore = require(script.Parent.SettingsStore)

local MovementController = {}

local MARKER_LIFETIME = 0.7
local KEY_REPEAT_INTERVAL = 0.12 -- > GameConfig.RemoteLimits.MoveRequestMinInterval (0,1 s)
local marker: Part? = nil
local connections: { RBXScriptConnection } = {}

local function showMarker(info: CameraController.MapInfo, x: number, y: number, color: Color3)
	if marker then
		marker:Destroy()
		marker = nil
	end
	if not SettingsStore.get("showMoveMarker") then
		return
	end
	local part = Instance.new("Part")
	part.Name = "MoveMarker"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.35
	part.Size = Vector3.new(info.cellSize * 0.9, 0.2, info.cellSize * 0.9)
	part.Position = info.origin + Vector3.new((x - 0.5) * info.cellSize, 0.1, (y - 0.5) * info.cellSize)
	part.Parent = workspace
	Debris:AddItem(part, MARKER_LIFETIME)
	marker = part
end

-- Intersection du rayon de la caméra avec le plan du sol (Y = 0) -> case de la grille, ou nil.
local function screenToCell(info: CameraController.MapInfo, screenPosition: Vector2): (number?, number?)
	local camera = CameraController.getCamera()
	if not camera then
		return nil, nil
	end
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil, nil
	end
	local t = -ray.Origin.Y / ray.Direction.Y
	if t <= 0 then
		return nil, nil
	end
	local hit = ray.Origin + ray.Direction * t
	local x = math.floor((hit.X - info.origin.X) / info.cellSize) + 1
	local y = math.floor((hit.Z - info.origin.Z) / info.cellSize) + 1
	if x < 1 or x > info.size or y < 1 or y > info.size then
		return nil, nil
	end
	return x, y
end

function MovementController.start(info: CameraController.MapInfo, remotes: Folder)
	MovementController.stop()

	local requestMove = remotes:WaitForChild("RequestMove") :: RemoteEvent
	local moveRejected = remotes:WaitForChild("MoveRejected") :: RemoteEvent

	InputController.onPrimaryAction(function(screenPosition: Vector2)
		-- Au menu principal la caméra montre le décor 3D : un clic n'a rien à déplacer.
		if CameraController.isOverridden() then
			return
		end
		local character = Players.LocalPlayer.Character
		if not character then
			return
		end
		local x, y = screenToCell(info, screenPosition)
		if not x or not y then
			return
		end
		showMarker(info, x, y, Color3.new(1, 1, 1))
		requestMove:FireServer({ x = x, y = y })
	end)

	-- Clavier (flèches ou WASD) : tant qu'une direction est tenue, on demande la case voisine dans cette direction.
	-- Le serveur valide et pilote le déplacement comme pour un clic ; la cadence reste sous la limite serveur.
	local lastKeyRequest = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			local direction = InputController.getHeldDirection()
			if not direction or CameraController.isOverridden() then
				return
			end
			local now = os.clock()
			if now - lastKeyRequest < KEY_REPEAT_INTERVAL then
				return
			end
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				return
			end
			local cx = math.floor((root.Position.X - info.origin.X) / info.cellSize) + 1
			local cy = math.floor((root.Position.Z - info.origin.Z) / info.cellSize) + 1
			local gridDirection = CameraController.screenToGrid(direction)
			local x, y = cx + gridDirection.X, cy + gridDirection.Y
			if x < 1 or x > info.size or y < 1 or y > info.size then
				return
			end
			lastKeyRequest = now
			showMarker(info, x, y, Color3.new(1, 1, 1))
			requestMove:FireServer({ x = x, y = y })
		end)
	)

	table.insert(
		connections,
		moveRejected.OnClientEvent:Connect(function(target: any)
			if typeof(target) == "table" and typeof(target.x) == "number" and typeof(target.y) == "number" then
				showMarker(info, target.x, target.y, Color3.fromRGB(235, 64, 52))
			end
		end)
	)
end

function MovementController.stop()
	InputController.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if marker then
		marker:Destroy()
		marker = nil
	end
end

return MovementController
