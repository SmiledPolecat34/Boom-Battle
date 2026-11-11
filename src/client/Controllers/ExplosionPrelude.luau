--!strict
-- DESCENTE ANTICIPÉE des effets d'explosion qui en ont une (ex. « Météore »). Purement visuel : ne décide de rien et ne touche à aucune mécanique.
-- Le serveur marque chaque bombe de deux attributs : BBPlacedAt (heure serveur de pose) et BBEffect (effet équipé par le poseur). Le client en déduit
-- l'instant de l'explosion (pose + durée de mèche) et lance la chute `lead` images avant, de sorte que l'impact tombe à l'instant du déclenchement
-- serveur. Si l'explosion arrive plus tôt (réaction en chaîne) ou pour un autre style, ExplosionE01 saute l'animation à l'impact ou annule la chute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExplosionE01 = require(script.Parent.ExplosionE01)
local MobileAssets = require(script.Parent.MobileAssets)
local ExplosionStyles = require(ReplicatedStorage.Shared.ExplosionStyles)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ExplosionPrelude = {}

local ARENA_NAME = "Arena" -- identique à MapService
-- L'explosion serveur arrive en pratique ~0,05 s après pose + mèche (mesuré dans Studio) : on cale l'impact dessus.
local IMPACT_BIAS = 0.05
local GRACE = 0.2 -- secondes laissées à l'explosion serveur pour réclamer la descente après la disparition de la bombe

local currentInfo: any = nil
local connections: { RBXScriptConnection } = {}
local seen: { [Instance]: boolean } = {}
local token = 0

local function serverNow(): number
	local ok, now = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and typeof(now) == "number" then now else os.clock()
end

local function attach(part: Instance, myToken: number)
	if not part:IsA("BasePart") or part.Name ~= "Bomb" or seen[part] then
		return
	end
	seen[part] = true
	local effectId = part:GetAttribute("BBEffect")
	local style = if typeof(effectId) == "string" then ExplosionStyles.get(effectId, nil) else nil
	local variant = if style then style.e01 else nil
	if not variant or not variant.lead or not ExplosionE01.available(variant) or not currentInfo then
		return
	end
	local placedAt = part:GetAttribute("BBPlacedAt")
	if typeof(placedAt) ~= "number" then
		return
	end
	local secondsToImpact = placedAt + GameConfig.Bomb.FuseTime + IMPACT_BIAS - serverNow()
	if secondsToImpact < 0.05 then
		return -- trop tard pour une descente : l'explosion démarrera directement à l'impact
	end
	local groundY = part:GetAttribute("BBGroundY")
	local ground = Vector3.new(part.Position.X, (if typeof(groundY) == "number" then groundY else currentInfo.origin.Y) + 0.25, part.Position.Z)
	local ok, handle = pcall(ExplosionE01.prelude, currentInfo, ground, secondsToImpact, MobileAssets.isLite(), variant)
	if not ok or not handle then
		return
	end
	-- Bombe disparue : si son explosion n'a pas réclamé la descente dans la minute de grâce, on l'annule.
	part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			task.delay(GRACE, function()
				if token == myToken then
					ExplosionE01.cancelPrelude(handle)
				end
			end)
		end
	end)
end

local function watchArena(arena: Instance, myToken: number)
	for _, child in arena:GetChildren() do
		attach(child, myToken)
	end
	table.insert(connections, arena.ChildAdded:Connect(function(child)
		attach(child, myToken)
	end))
end

function ExplosionPrelude.start(info: any)
	ExplosionPrelude.stop()
	currentInfo = info
	token += 1
	local myToken = token
	local existing = workspace:FindFirstChild(ARENA_NAME)
	if existing then
		watchArena(existing, myToken)
	end
	table.insert(connections, workspace.ChildAdded:Connect(function(child)
		if child.Name == ARENA_NAME then
			watchArena(child, myToken)
		end
	end))
end

function ExplosionPrelude.stop()
	token += 1
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	table.clear(seen)
	currentInfo = nil
end

return ExplosionPrelude
