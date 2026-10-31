--!strict
-- Effets visuels : flammes d'explosion, une Part par case touchée, uniquement locales.
-- Le serveur décide des cases ; ce contrôleur n'a aucune influence sur le gameplay.

local Debris = game:GetService("Debris")

local CameraController = require(script.Parent.CameraController)

local EffectsController = {}

local connection: RBXScriptConnection? = nil

function EffectsController.start(info: CameraController.MapInfo, remotes: Folder)
	EffectsController.stop()
	local explosion = remotes:WaitForChild("Explosion") :: RemoteEvent
	connection = explosion.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.cells) ~= "table" then
			return
		end
		local duration = if typeof(payload.duration) == "number" then math.clamp(payload.duration, 0.1, 2) else 0.5
		for _, cell in payload.cells do
			if typeof(cell) == "table" and typeof(cell.x) == "number" and typeof(cell.y) == "number" then
				local flame = Instance.new("Part")
				flame.Name = "Flame"
				flame.Anchored = true
				flame.CanCollide = false
				flame.CanQuery = false
				flame.CanTouch = false
				flame.CastShadow = false
				flame.Material = Enum.Material.Neon
				flame.Color = Color3.fromRGB(255, 150, 30)
				flame.Transparency = 0.15
				flame.Size = Vector3.new(info.cellSize * 0.95, 0.5, info.cellSize * 0.95)
				flame.Position = info.origin
					+ Vector3.new((cell.x - 0.5) * info.cellSize, 0.25, (cell.y - 0.5) * info.cellSize)
				flame.Parent = workspace
				Debris:AddItem(flame, duration)
			end
		end
	end)
end

function EffectsController.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return EffectsController
