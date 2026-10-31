--!strict
-- Effets visuels : flammes d'explosion, une Part par case touchée, uniquement locales.
-- Le serveur décide des cases ; ce contrôleur n'a aucune influence sur le gameplay.
--
-- Optimisation : les Parts de flamme viennent d'un POOL réutilisé (aucune création / destruction à chaque explosion,
-- donc moins de ramasse-miettes et de travail du moteur pendant les grosses réactions en chaîne).

local CameraController = require(script.Parent.CameraController)

local EffectsController = {}

local MAX_POOL_SIZE = 160 -- plafond de Parts conservées ; au-delà, les Parts en trop sont détruites
local DEFAULT_COLOR = Color3.fromRGB(255, 150, 30)

local connection: RBXScriptConnection? = nil
local pool: { Part } = {}

local function acquire(): Part
	local flame = table.remove(pool)
	if flame then
		return flame
	end
	local created = Instance.new("Part")
	created.Name = "Flame"
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = false
	created.Material = Enum.Material.Neon
	created.Transparency = 0.15
	return created
end

local function release(flames: { Part })
	for _, flame in flames do
		flame.Parent = nil
		if #pool < MAX_POOL_SIZE then
			table.insert(pool, flame)
		else
			flame:Destroy()
		end
	end
end

function EffectsController.start(info: CameraController.MapInfo, remotes: Folder)
	EffectsController.stop()
	local explosion = remotes:WaitForChild("Explosion") :: RemoteEvent
	local flameSize = Vector3.new(info.cellSize * 0.95, 0.5, info.cellSize * 0.95)

	connection = explosion.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.cells) ~= "table" then
			return
		end
		local duration = if typeof(payload.duration) == "number" then math.clamp(payload.duration, 0.1, 2) else 0.5
		local color = if typeof(payload.color) == "Color3" then payload.color else DEFAULT_COLOR

		local used: { Part } = {}
		for _, cell in payload.cells do
			if typeof(cell) == "table" and typeof(cell.x) == "number" and typeof(cell.y) == "number" then
				local flame = acquire()
				flame.Size = flameSize
				flame.Color = color
				flame.Position = info.origin
					+ Vector3.new((cell.x - 0.5) * info.cellSize, 0.25, (cell.y - 0.5) * info.cellSize)
				flame.Parent = workspace
				table.insert(used, flame)
			end
		end
		-- Un seul minuteur par explosion (au lieu d'un par case).
		task.delay(duration, release, used)
	end)
end

function EffectsController.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return EffectsController
