--!strict
-- BOOM BATTLE - animations du décor (script de DÉPART, NON TESTÉ dans Studio)
-- À placer dans StarterPlayerScripts (LocalScript) ou ServerScriptService selon l'usage.
-- Les noms d'objets viennent du fichier Blender ; adapter ENV_NAME au modèle importé.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ENV_NAME = "BOOM_BATTLE_ENVIRONMENT"
local env = Workspace:WaitForChild(ENV_NAME)
local function find(name: string): Instance?
	return env:FindFirstChild(name, true)
end

local FPS = 30 -- les durées de la boucle Blender sont en images à 30 i/s

-- 1. Socles : anneaux, lumières et ondes (cycle de 80 images, déphasage par socle)
local PAD_CYCLE = 80 / FPS
local PAD_PHASE = { 0 / FPS, 27 / FPS, 53 / FPS }
for i = 1, 3 do
	local ring = find("PAD_" .. i .. "_Ring")
	if ring and ring:IsA("BasePart") then
		ring.Material = Enum.Material.Neon
		local info = TweenInfo.new(PAD_CYCLE / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, PAD_PHASE[i])
		TweenService:Create(ring, info, { Color = Color3.fromRGB(255, 200, 70) }):Play()
	end
	local light = find("PAD_" .. i .. "_Light")
	if light and light:IsA("PointLight") then
		local info = TweenInfo.new(PAD_CYCLE / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, PAD_PHASE[i])
		TweenService:Create(light, info, { Brightness = 4.5 }):Play()
	end
	local pulse = find("PAD_" .. i .. "_Pulse")
	if pulse and pulse:IsA("BasePart") then
		local size0 = pulse.Size
		pulse.Transparency = 0.35
		local info = TweenInfo.new(PAD_CYCLE * 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, false, PAD_PHASE[i])
		TweenService:Create(pulse, info, { Size = Vector3.new(size0.X * 1.5, size0.Y, size0.Z * 1.5), Transparency = 1 }):Play()
	end
end

-- 2. Balancements (mèches, feuillages, volants) : rotation autour du pivot de la pièce
local swayers = {}
local function addSway(part: BasePart, ampX: number, ampY: number, ampZ: number, cycleFrames: number, phaseFrames: number)
	table.insert(swayers, { part = part, base = part.CFrame, ax = math.rad(ampX), ay = math.rad(ampY), az = math.rad(ampZ),
		w = 2 * math.pi / (cycleFrames / FPS), ph = phaseFrames / FPS })
end
local idx = 0
for _, d in ipairs(env:GetDescendants()) do
	if d:IsA("BasePart") then
		if string.find(d.Name, "^BOMB_Fuse_") then
			addSway(d, 3, 0, 2.5, 60, idx * 7); idx += 1
		elseif string.find(d.Name, "_Foliage") then
			addSway(d, 1.2, 1.8, 0.8, 120, idx * 17); idx += 1
		elseif string.find(d.Name, "^PIPE_Valve_Wheel") then
			addSway(d, 0, 0, 10, 240, 0)
		end
	end
end
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, s in ipairs(swayers) do
		local a = math.sin(s.w * (t - s.ph))
		-- Attention : l'axe vertical Blender (Z) devient l'axe Y de Roblox ; adapter l'ordre des angles si besoin.
		s.part.CFrame = s.base * CFrame.Angles(s.ax * a, s.az * a, s.ay * a)
	end
end)
-- Les pièces balancées doivent être Anchored = true (ou soudées à un parent animé).

-- 3. Étincelles et fumée : une Attachment par bombe au bout de la mèche (voir Animations_README.md)
local function makeEmitter(parent: Instance, spark: boolean)
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = spark and 1 or 0
	if spark then
		e.Rate = 6; e.Lifetime = NumberRange.new(0.4, 0.8); e.Speed = NumberRange.new(2, 4); e.SpreadAngle = Vector2.new(40, 40)
		e.Color = ColorSequence.new(Color3.fromRGB(255, 190, 60)); e.Acceleration = Vector3.new(0, -6, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) })
	else
		e.Rate = 3; e.Lifetime = NumberRange.new(1.0, 1.6); e.Speed = NumberRange.new(0.6, 1.2); e.SpreadAngle = Vector2.new(20, 20)
		e.Color = ColorSequence.new(Color3.fromRGB(170, 170, 175))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.1) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	end
	e.Parent = parent
end
for _, d in ipairs(env:GetDescendants()) do
	if d:IsA("Attachment") and string.find(d.Name, "^BOMB_SparkAnchor_") then
		makeEmitter(d, true)
		makeEmitter(d, false)
	end
end

-- 4. Fumée des tuyaux : un émetteur de vapeur par Attachment PIPE_SmokeAnchor_* (à créer à la position indiquée dans le README)
local function makeSteam(parent: Instance)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 5
	e.Lifetime = NumberRange.new(1.6, 2.4)
	e.Speed = NumberRange.new(1.5, 2.5)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Color = ColorSequence.new(Color3.fromRGB(230, 232, 238))
	e.LightEmission = 0.1
	e.Acceleration = Vector3.new(0, 1, 0)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.8) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
end
for _, d in ipairs(env:GetDescendants()) do
	if d:IsA("Attachment") and string.find(d.Name, "^PIPE_SmokeAnchor_") then
		makeSteam(d)
	end
end
