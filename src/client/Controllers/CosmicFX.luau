--!strict
--[[
	Effets de la bombe COSMIQUE (« Cosmic Glass Bomb »), côté CLIENT : rotation lente de la galaxie, pulsation du noyau,
	variation des bras, étoiles, lumières (PointLight) et particules (ParticleEmitter). Les FBX ne portent que la géométrie.
	Version intégrée au jeu de assets/3D/BOOM_BATTLE_ART/05_EXPORTS_ROBLOX/VFX/B09_CosmicFX.luau (testée dans Studio sur un modèle
	factice puis en Play sur le vrai modèle : voir le test de ce dossier). Différences avec la source : `addEffects` accepte
	`outline` (le contour Highlight est coupé pour les bombes en jeu : Roblox n'affiche qu'un nombre limité de contours à la fois).

	Utilisation : BombSkinController l'appelle pour chaque bombe Cosmique posée :
	    local state = CosmicFX.newState(model)           -- état de repos (relatif à BombShell_Glass)
	    CosmicFX.addEffects(model, quality, false)       -- lumières + particules (qualité "low" sur mobile)
	    CosmicFX.step(state, secondesDepuisLaPose)       -- à chaque frame
	La galaxie tourne autour de l'axe normal à son disque (incliné de 32° vers l'avant), dans le repère de BombShell_Glass.
]]

local RunService = game:GetService("RunService")

local CosmicFX = {}

-- name = { Material, Color (hex), Transparency }  (copie de la section "parts" du manifeste PC)
local STYLE = {
	BombShell_Glass = { Enum.Material.Glass, "#8A5CE0", 0.70 },
	BombShell_Frame = { Enum.Material.Metal, "#2A1060", 0 },
	BombGalaxy_Core = { Enum.Material.Neon, "#FFF0FB", 0 },
	BombGalaxy_Halo = { Enum.Material.Neon, "#FF4FE0", 0.55 },
	BombGalaxy_ArmsInner = { Enum.Material.Neon, "#FF5BE6", 0 },
	BombGalaxy_ArmsMid = { Enum.Material.Neon, "#D62FD1", 0 },
	BombGalaxy_ArmsOuter = { Enum.Material.Neon, "#8F4BFF", 0 },
	BombGalaxy_NebulaViolet = { Enum.Material.Neon, "#6A2BD6", 0.55 },
	BombGalaxy_NebulaMagenta = { Enum.Material.Neon, "#C32FD6", 0.55 },
	BombGalaxy_Stars = { Enum.Material.Neon, "#FFFFFF", 0 },
	BombCollar_Base = { Enum.Material.Metal, "#3A1F7A", 0 },
	BombCollar_Rim = { Enum.Material.Neon, "#FF7AF0", 0 },
	BombFuse_Curved = { Enum.Material.SmoothPlastic, "#B8803C", 0 },
	BombFuse_Tip = { Enum.Material.SmoothPlastic, "#3A2410", 0 },
	BombSpark_Star = { Enum.Material.Neon, "#FFD6FA", 0 },
}

local GALAXY_PARTS = {
	"BombGalaxy_Core", "BombGalaxy_Halo", "BombGalaxy_ArmsInner", "BombGalaxy_ArmsMid", "BombGalaxy_ArmsOuter",
	"BombGalaxy_NebulaViolet", "BombGalaxy_NebulaMagenta", "BombGalaxy_Stars",
}
local ARM_PARTS = { "BombGalaxy_ArmsInner", "BombGalaxy_ArmsMid", "BombGalaxy_ArmsOuter" }

local SPIN_AXIS = Vector3.new(0, 0.848, 0.530) -- normale du disque, repere de BombShell_Glass
local CENTER_OFFSET = Vector3.new(0, -0.10, 0) -- la galaxie est abaissee de 0.10 dans la coque
local SPIN_DEG_PER_S = 14
local STARS_COUNTER_SPIN_DEG_PER_S = -5

local function getPart(model: Instance, name: string): BasePart?
	local p = model:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- 1) materiaux, couleurs, transparences, pieces purement visuelles
function CosmicFX.prepare(model: Instance)
	for name, style in pairs(STYLE) do
		local p = getPart(model, name)
		if p then
			p.Material = style[1]
			p.Color = Color3.fromHex(style[2])
			p.Transparency = style[3]
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
		end
	end
	local glass = getPart(model, "BombShell_Glass")
	if glass then
		glass.Reflectance = 0.1
	end
end

local function newEmitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- 2) lumieres, particules, contour
local EFFECT_NAMES = {
	CosmicCoreLight = true, CosmicSparkLight = true, CosmicFuseMagic = true, CosmicInnerStars = true, CosmicOutline = true,
}

function CosmicFX.addEffects(model: Instance, quality: string?, outline: boolean?)
	local low = (quality == "low")
	local created: { Instance } = {}
	-- idempotent : un second appel ne duplique pas les effets (supprime d'abord ceux d'un appel precedent)
	for _, inst in ipairs(model:GetDescendants()) do
		if EFFECT_NAMES[inst.Name] then
			inst:Destroy()
		end
	end

	local core = getPart(model, "BombGalaxy_Core")
	if core then
		local light = Instance.new("PointLight")
		light.Name = "CosmicCoreLight"
		light.Color = Color3.fromHex("#FF6AF0")
		light.Brightness = 2
		light.Range = 9
		light.Shadows = false
		light.Parent = core
		table.insert(created, light)
	end

	local spark = getPart(model, "BombSpark_Star")
	if spark then
		local light = Instance.new("PointLight")
		light.Name = "CosmicSparkLight"
		light.Color = Color3.fromHex("#FFD6FA")
		light.Brightness = 2
		light.Range = 6
		light.Shadows = false
		light.Parent = spark
		table.insert(created, light)

		-- particules magiques autour de la meche
		table.insert(created, newEmitter(spark, {
			Name = "CosmicFuseMagic",
			Rate = low and 8 or 18,
			Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(1.5, 3.0),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 2,
			Acceleration = Vector3.new(0, 1.5, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-90, 90),
			LightEmission = 1,
			LightInfluence = 0,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromHex("#FFFFFF"), Color3.fromHex("#FF5BE6")),
		}))
	end

	-- etoiles qui flottent a l'interieur de la coque (volume d'emission = la sphere de verre)
	local glass = getPart(model, "BombShell_Glass")
	if glass then
		local e = newEmitter(glass, {
			Name = "CosmicInnerStars",
			Rate = low and 4 or 10,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(0.05, 0.15),
			SpreadAngle = Vector2.new(180, 180),
			Rotation = NumberRange.new(0, 360),
			LightEmission = 1,
			LightInfluence = 0,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.14), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromHex("#FFFFFF"), Color3.fromHex("#C9A3FF")),
		})
		pcall(function()
			e.Shape = Enum.ParticleEmitterShape.Sphere
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		end)
		table.insert(created, e)
	end

	-- contour violet fonce de la coque (pas de geometrie : un Highlight)
	if not low and outline ~= false and model:IsA("Model") then
		local h = Instance.new("Highlight")
		h.Name = "CosmicOutline"
		h.FillTransparency = 1
		h.OutlineColor = Color3.fromHex("#2A1060")
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = model
		h.Parent = model
		table.insert(created, h)
	end
	return created
end

-- 3) animation. newState() memorise l'etat de repos ; step(state, t) pose la galaxie a l'instant t (secondes) : testable sans boucle ; animate() = newState + Heartbeat.
function CosmicFX.newState(model: Instance): any?
	local shell = getPart(model, "BombShell_Glass")
	if not shell then
		return nil
	end
	local state: any = { model = model, shell = shell, rest = {}, baseSize = {}, baseColor = {} }
	-- etat de repos de chaque piece de galaxie, relatif a la coque
	for _, name in ipairs(GALAXY_PARTS) do
		local p = getPart(model, name)
		if p then
			state.rest[name] = shell.CFrame:ToObjectSpace(p.CFrame)
			state.baseSize[name] = p.Size
			state.baseColor[name] = p.Color
		end
	end
	state.spark = getPart(model, "BombSpark_Star")
	state.sparkSize = state.spark and state.spark.Size
	local core = getPart(model, "BombGalaxy_Core")
	state.coreLight = core and core:FindFirstChild("CosmicCoreLight")
	state.sparkLight = state.spark and state.spark:FindFirstChild("CosmicSparkLight")
	return state
end

local function spinAbout(deg: number): CFrame
	local axis = SPIN_AXIS.Unit
	return CFrame.new(CENTER_OFFSET) * CFrame.fromAxisAngle(axis, math.rad(deg)) * CFrame.new(-CENTER_OFFSET)
end

function CosmicFX.step(state: any, t: number)
	local model, shell = state.model, state.shell
	if not shell.Parent then
		return
	end
	local frame = shell.CFrame
	local spin = spinAbout(SPIN_DEG_PER_S * t)
	local starsSpin = spinAbout((SPIN_DEG_PER_S + STARS_COUNTER_SPIN_DEG_PER_S) * t)
	local jitter = Vector3.new(math.noise(t * 0.7, 1, 0), math.noise(t * 0.6, 2, 0), math.noise(t * 0.5, 3, 0)) * 0.03

	for name, r in pairs(state.rest) do
		local p = getPart(model, name)
		if p then
			if name == "BombGalaxy_Stars" then
				p.CFrame = frame * CFrame.new(jitter) * starsSpin * r
			else
				p.CFrame = frame * spin * r
			end
		end
	end

	-- pulsation du noyau (taille + lumiere) et du halo
	local pulse = 0.5 + 0.5 * math.sin(2 * math.pi * 0.9 * t)
	local core = getPart(model, "BombGalaxy_Core")
	if core and state.baseSize.BombGalaxy_Core then
		core.Size = state.baseSize.BombGalaxy_Core * (1 + 0.12 * (pulse - 0.5) * 2)
	end
	local halo = getPart(model, "BombGalaxy_Halo")
	if halo and state.baseSize.BombGalaxy_Halo then
		local hp = 0.5 + 0.5 * math.sin(2 * math.pi * 0.9 * t + 0.6)
		halo.Size = state.baseSize.BombGalaxy_Halo * (1 + 0.08 * (hp - 0.5) * 2)
	end
	if state.coreLight and state.coreLight:IsA("PointLight") then
		state.coreLight.Brightness = 1.6 + 1.0 * pulse
	end

	-- legere variation d'intensite des bras (vers le blanc)
	for i, name in ipairs(ARM_PARTS) do
		local p = getPart(model, name)
		if p and state.baseColor[name] then
			local k = 0.10 * (0.5 + 0.5 * math.sin(2 * math.pi * 0.35 * t + i * 1.3))
			p.Color = state.baseColor[name]:Lerp(Color3.new(1, 1, 1), k)
		end
	end

	-- scintillement de l'etincelle
	if state.spark and state.sparkSize then
		local f = 0.5 + 0.5 * math.sin(2 * math.pi * 6 * t) * math.sin(2 * math.pi * 2.3 * t)
		state.spark.Size = state.sparkSize * (0.85 + 0.3 * f)
		if state.sparkLight and state.sparkLight:IsA("PointLight") then
			state.sparkLight.Brightness = 1.5 + f
		end
	end
end

-- remet la galaxie a son etat de repos (position relative a la coque, tailles, couleurs) : evite toute derive si le skin est reapplique
function CosmicFX.restore(state: any)
	local shell = state.shell
	if not shell.Parent then
		return
	end
	for name, r in pairs(state.rest) do
		local p = getPart(state.model, name)
		if p then
			p.CFrame = shell.CFrame * r
			p.Size = state.baseSize[name]
			p.Color = state.baseColor[name]
		end
	end
	if state.spark and state.sparkSize then
		state.spark.Size = state.sparkSize
	end
end

-- renvoie la fonction qui arrete la boucle ET restaure l'etat de repos
function CosmicFX.animate(model: Instance): () -> ()
	local state = CosmicFX.newState(model)
	if not state then
		return function() end
	end
	local t0 = os.clock()
	local conn = RunService.Heartbeat:Connect(function()
		CosmicFX.step(state, os.clock() - t0)
	end)
	return function()
		conn:Disconnect()
		CosmicFX.restore(state)
	end
end

-- tout en un
function CosmicFX.apply(model: Instance, options: { quality: string?, outline: boolean? }?): () -> ()
	local quality = options and options.quality or "high"
	CosmicFX.prepare(model)
	local created = CosmicFX.addEffects(model, quality, options == nil or options.outline ~= false)
	local stop = CosmicFX.animate(model)
	return function()
		stop()
		for _, inst in ipairs(created) do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end
end

return CosmicFX
