--!strict
-- VRAIE MÈCHE ALLUMÉE, en géométrie néon (les particules ne s'affichent pas dans un ViewportFrame : boutique, inventaire, HUD).
-- Composition posée sur le bout de la mèche, du plus net au plus doux :
--   • une FLAMME en goutte (pile de sphères néon qui s'affinent vers le haut, 2 couches : enveloppe orange-rouge, cœur jaune
--     clair) : elle vacille, monte et se balance ;
--   • une ÉTOILE D'ÉTINCELLE (fuseaux néon fins croisés dans les trois axes + diagonales, comme l'étincelle des illustrations)
--     qui tourne lentement et scintille : lisible de loin et sous n'importe quel angle ;
--   • des ÉTINCELLES qui jaillissent, un léger voile de fumée et une lumière chaude (PointLight) dans le monde.
-- À l'affichage la mèche s'ALLUME : éclair d'étoile, flamme qui grandit. Purement visuel et local. UNE seule connexion anime
-- toutes les flammes ; les pièces vivent dans le modèle et disparaissent avec lui.
-- Qualités : full (aperçu détaillé, menu), mini (peu de pièces, 24 Hz), game (bombe posée : BombFx ajoute déjà étincelles et
-- fumée en particules), static (une image figée, aucune animation : miniatures de la boutique et HUD).
-- Le BOUT NOIR de la mèche est ce qui brûle : le pied de la flamme est DANS le bout (qu'il enveloppe), le bout rougeoie comme une
-- braise (néon, couleur qui pulse), et toute la flamme suit la position ET l'orientation de la pièce (la bombe qui se balance).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BombEffectsConfig = require(ReplicatedStorage.Shared.BombEffectsConfig)

local TAU = math.pi * 2
local IGNITE_TIME = 0.45 -- secondes : la flamme grandit
local FLASH_TIME = 0.4 -- secondes : éclair de l'étoile à l'allumage
local SURGE_PERIOD = 3.0 -- secondes entre deux poussées de flamme

export type Quality = "full" | "mini" | "game" | "static"
export type Options = { quality: Quality?, scale: number?, light: boolean?, gate: GuiObject? }

-- outer / inner : nombre de sphères de la goutte (enveloppe / cœur) ; spikes : fuseaux de l'étoile (3 = axes, 5 = + 2 diag., 7 = + 4)
local QUALITIES = {
	full = { outer = 8, inner = 3, spikes = 7, sparks = 6, smoke = 0, hz = 60 },
	mini = { outer = 5, inner = 2, spikes = 3, sparks = 2, smoke = 0, hz = 24 },
	game = { outer = 6, inner = 2, spikes = 5, sparks = 0, smoke = 0, hz = 30 },
	-- static : UNE image figée (flamme allumée, aucune animation, aucun coût par image) : miniatures de la boutique et icône du HUD
	static = { outer = 5, inner = 2, spikes = 3, sparks = 0, smoke = 0, hz = 1, still = true },
}
-- Goutte (studs, pour une bombe d'échelle 1 : corps de 3 studs) : k va de 0 (pied) à 1 (pointe) ; le diamètre s'affine, la
-- hauteur monte. Enveloppe : pied à 0,2, pointe à 0,88 ; cœur : plus petit, jusqu'à 0,45.
local OUTER_BASE_D, OUTER_TIP_D, OUTER_Y0, OUTER_Y1 = 0.54, 0.09, 0.2, 0.9
local INNER_BASE_D, INNER_TIP_D, INNER_Y0, INNER_Y1 = 0.3, 0.1, 0.15, 0.46
-- Étoile : longueur de chaque fuseau (axes Y, X, Z puis diagonales) et épaisseur
local SPIKE_LEN = { 1.2, 2.1, 2.1, 1.2, 1.2, 1.2, 1.2 }
local SPIKE_ROT = {
	CFrame.identity, -- Y (vertical)
	CFrame.Angles(0, 0, math.pi / 2), -- X
	CFrame.Angles(math.pi / 2, 0, 0), -- Z
	CFrame.Angles(0, 0, math.pi / 4),
	CFrame.Angles(0, 0, -math.pi / 4),
	CFrame.Angles(math.pi / 4, 0, 0),
	CFrame.Angles(-math.pi / 4, 0, 0),
}
local SPIKE_THICK = 0.13
local STAR_LIFT = 0.34 -- hauteur du centre de l'étoile au-dessus du bout de la mèche

type Flame = {
	model: Model,
	anchor: BasePart,
	scale: number,
	startedAt: number,
	interval: number,
	nextAt: number,
	all: { Instance },
	outer: { BasePart },
	outerColors: { Color3 },
	inner: { BasePart },
	spikes: { BasePart },
	spikeColor: Color3,
	redColor: Color3,
	light: PointLight?,
	ember: boolean, -- le bout de la mèche rougeoie (pièce BombFuse_Tip)
	gate: GuiObject?, -- cadre d'interface qui porte l'aperçu : animation suspendue tant qu'il n'est pas affiché
	sparks: { BasePart },
	sparkPhase: { number },
	sparkDir: { Vector3 },
	smoke: { BasePart },
	smokePhase: { number },
}

local BombFlame = {}

-- Le cadre et tous ses parents sont-ils affichés ? (économie : rien n'est animé dans un écran fermé)
function BombFlame.isShown(gui: GuiObject): boolean
	local node: Instance? = gui
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	if node and node:IsA("LayerCollector") then
		return (node :: any).Enabled ~= false
	end
	return node ~= nil
end

local active: { Flame } = {}
local connection: RBXScriptConnection? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function basePart(model: Model, name: string, color: Color3, material: Enum.Material, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = "BBFlame_" .. name
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	part.Transparency = transparency
	part.Parent = model
	return part
end

local function ball(model: Model, name: string, color: Color3, material: Enum.Material, transparency: number): Part
	local part = basePart(model, name, color, material, transparency)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Fuseau (ellipsoïde allongé) : un Part avec un SpecialMesh sphère mis à l'échelle de sa taille.
local function spindle(model: Model, name: string, color: Color3): Part
	local part = basePart(model, name, color, Enum.Material.Neon, 0)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function setBall(part: BasePart, size: number, position: Vector3)
	part.Size = Vector3.new(size, size, size)
	part.Position = position
end

local function destroyFlame(flame: Flame)
	for _, instance in flame.all do
		instance:Destroy()
	end
	table.clear(flame.all)
end

local function step(flame: Flame, now: number)
	local t = now - flame.startedAt
	local s = flame.scale
	-- Le pied de la flamme est DANS le bout noir ; tout est exprimé dans le repère de la pièce (suit son orientation).
	local rotation = flame.anchor.CFrame.Rotation
	local base = flame.anchor.CFrame:PointToWorldSpace(Vector3.new(0, flame.anchor.Size.Y * 0.12, 0))
	local function at(x: number, y: number, z: number): Vector3
		return base + rotation:VectorToWorldSpace(Vector3.new(x, y, z))
	end

	local u = math.clamp(t / IGNITE_TIME, 0, 1)
	local grow = 1 - (1 - u) * (1 - u) * (1 - u)
	local flash = math.max(0, 1 - t / FLASH_TIME)
	local surge = math.max(0, math.sin(TAU * t / SURGE_PERIOD)) ^ 6
	local sway = 0.05 * s * math.sin(t * 5.3)

	-- Le bout noir brûle : braise qui pulse du rouge sombre à l'orange vif (plus vive à l'allumage et à la poussée).
	if flame.ember then
		local pulse = 0.5 + 0.3 * math.sin(t * 9) + 0.25 * math.noise(t * 6, 3.1, 0) * 2
		local heat = math.clamp(0.25 + 0.55 * pulse + 0.4 * surge, 0, 1) * (0.4 + 0.6 * grow)
		flame.anchor.Color = Color3.fromRGB(95, 22, 8):Lerp(Color3.fromRGB(255, 125, 30), heat):Lerp(Color3.new(1, 1, 1), flash * 0.4)
	end

	-- Goutte : pile de sphères qui s'affinent vers le haut ; le haut se balance et vacille, poussée périodique.
	local function layer(parts: { BasePart }, d0: number, d1: number, y0: number, y1: number, seed: number, colors: { Color3 }?)
		local n = #parts
		for index, part in parts do
			local k = if n > 1 then (index - 1) / (n - 1) else 0
			local noise = math.noise(t * 8 + index * 2.3, seed, 0) * 2
			local diameter = (d0 + (d1 - d0) * k ^ 1.6) * s * grow * (1 + 0.1 * noise) * (1 + 0.15 * surge * (1 - k))
			local height = (y0 + (y1 - y0) * k) * s * grow * (1 + 0.28 * surge * k + 0.05 * noise)
			local lateral = (0.13 * s * math.sin(t * 5.3 + seed) + 0.04 * s * noise) * k * k
			setBall(part, math.max(diameter, 0.01), at(lateral, height, 0.03 * s * math.sin(t * 4.1 + seed) * k))
			if colors then
				part.Color = colors[index]:Lerp(Color3.new(1, 1, 1), flash * 0.35)
			end
		end
	end
	layer(flame.outer, OUTER_BASE_D, OUTER_TIP_D, OUTER_Y0, OUTER_Y1, 0.3, flame.outerColors)
	layer(flame.inner, INNER_BASE_D, INNER_TIP_D, INNER_Y0, INNER_Y1, 1.7, nil)

	-- Étoile d'étincelle : tourne et scintille ; éclair plus grand à l'allumage, poussée avec la flamme.
	local starCenter = at(0, STAR_LIFT * s * grow, 0)
	local frame = CFrame.new(starCenter) * rotation * CFrame.Angles(0.3 * math.sin(t * 0.9), t * 1.2, 0.22 * math.sin(t * 0.7))
	for index, part in flame.spikes do
		local twinkle = 0.82 + 0.18 * math.sin(t * 12 + index * 1.7)
		local length = SPIKE_LEN[index] * s * grow * twinkle * (1 + 1.1 * flash + 0.25 * surge)
		local thick = SPIKE_THICK * s * grow * (0.85 + 0.5 * flash)
		part.Size = Vector3.new(thick, math.max(length, 0.01), thick)
		part.CFrame = frame * SPIKE_ROT[index]
		part.Color = flame.spikeColor:Lerp(Color3.new(1, 1, 1), flash * 0.6)
	end
	if flame.light then
		flame.light.Brightness = (1.1 + 0.5 * math.noise(t * 8, 2.2, 0) * 2 + 1.2 * flash + 0.4 * surge) * grow
	end

	for index, spark in flame.sparks do
		local tau = (t * 1.5 + flame.sparkPhase[index]) % 1
		local dir = flame.sparkDir[index]
		local position = starCenter + dir * (1.3 * s * tau) + Vector3.new(0, -0.9 * s * tau * tau, 0)
		setBall(spark, math.max(0.1 * s * (1 - tau) * grow, 0.005), position)
		spark.Transparency = tau * tau
		spark.Color = flame.spikeColor:Lerp(flame.redColor, tau)
	end
	for index, smoke in flame.smoke do
		local tau = (t * 0.6 + flame.smokePhase[index]) % 1
		local drift = 0.3 * s * math.sin(flame.smokePhase[index] * TAU) * tau
		setBall(smoke, (0.1 + 0.26 * tau) * s * grow, at(drift, (1.1 + 0.9 * tau) * s, 0.1 * s * (flame.smokePhase[index] - 0.5)))
		smoke.Transparency = 0.55 + 0.45 * tau
	end
end

local function tick()
	local now = os.clock()
	local i = 1
	while i <= #active do
		local flame = active[i]
		if not flame.model.Parent or not flame.anchor.Parent then
			destroyFlame(flame) -- le modèle a disparu (écran fermé, bombe détruite) : on retire la flamme
			table.remove(active, i)
		else
			if now >= flame.nextAt then
				flame.nextAt = now + flame.interval
				-- Aperçu dans un écran caché (boutique fermée) : aucun calcul.
				if not flame.gate or BombFlame.isShown(flame.gate) then
					step(flame, now)
				end
			end
			i += 1
		end
	end
	if #active == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Pose la mèche allumée sur la pièce d'ancrage du modèle (bout de la mèche ; BombSpark_Star pour la Cosmique). Renvoie une
-- fonction qui l'enlève, ou nil si le modèle n'a pas la pièce (rien n'est créé). Appeler APRÈS tout soudage / teinte du modèle.
function BombFlame.attach(model: Model, modelName: string, options: Options?): (() -> ())?
	local cfg: BombEffectsConfig.ModelFx = BombEffectsConfig.get(modelName) or {}
	local pieceName = cfg.flamePiece or cfg.fusePiece or BombEffectsConfig.DefaultFusePiece
	local anchor = model:FindFirstChild(pieceName)
	if not anchor or not anchor:IsA("BasePart") then
		return nil
	end
	local quality: Quality = (options and options.quality) or "full"
	local q = QUALITIES[quality]
	local colors = cfg.flame or BombEffectsConfig.DefaultFlame
	local core, mid, tipColor = rgb(colors.core), rgb(colors.mid), rgb(colors.tip)
	local all: { Instance } = {}
	local function track<T>(instance: T & Instance): T
		table.insert(all, instance)
		return instance
	end

	local outer: { BasePart } = {}
	local outerColors: { Color3 } = {}
	for index = 1, q.outer do
		local k = if q.outer > 1 then (index - 1) / (q.outer - 1) else 0 -- 0 = pied (orange), 1 = pointe (rouge)
		local color = mid:Lerp(tipColor, k)
		table.insert(outerColors, color)
		table.insert(outer, track(ball(model, "Outer" .. index, color, Enum.Material.Neon, 0.05)))
	end
	local inner: { BasePart } = {}
	for index = 1, q.inner do
		local k = if q.inner > 1 then (index - 1) / (q.inner - 1) else 0
		table.insert(inner, track(ball(model, "Inner" .. index, core:Lerp(mid, 0.2 + 0.3 * k), Enum.Material.Neon, 0)))
	end
	local spikeColor = mid:Lerp(core, 0.3) -- doré : le néon blanchit déjà les couleurs claires
	local spikes: { BasePart } = {}
	if cfg.star ~= false then
		for index = 1, q.spikes do
			table.insert(spikes, track(spindle(model, "Spike" .. index, spikeColor)))
		end
	end
	local light: PointLight? = nil
	if quality ~= "mini" and not (options and options.light == false) then
		local pointLight = Instance.new("PointLight")
		pointLight.Name = "BBFlame_Light"
		pointLight.Color = mid
		pointLight.Range = 7 * ((options and options.scale) or 1)
		pointLight.Brightness = 0
		pointLight.Shadows = false
		pointLight.Parent = anchor
		light = track(pointLight)
	end
	local sparks: { BasePart } = {}
	local sparkPhase: { number } = {}
	local sparkDir: { Vector3 } = {}
	for index = 1, q.sparks do
		table.insert(sparks, track(ball(model, "Spark" .. index, core, Enum.Material.Neon, 1)))
		table.insert(sparkPhase, (index - 1) / q.sparks)
		local angle = (index * 2.399963) % TAU -- angle d'or : répartition régulière
		local elevation = 0.5 + 0.4 * ((index * 0.618) % 1)
		table.insert(sparkDir, Vector3.new(math.cos(angle) * (1 - elevation * 0.5), elevation, math.sin(angle) * (1 - elevation * 0.5)))
	end
	local smoke: { BasePart } = {}
	local smokePhase: { number } = {}
	for index = 1, q.smoke do
		table.insert(smoke, track(ball(model, "Smoke" .. index, Color3.fromRGB(90, 90, 100), Enum.Material.SmoothPlastic, 0.7)))
		table.insert(smokePhase, (index - 1) / q.smoke)
	end

	local ember = anchor.Name == "BombFuse_Tip"
	if ember then
		anchor.Material = Enum.Material.Neon -- le bout noir devient une braise
	end

	local flame: Flame = {
		model = model,
		anchor = anchor,
		scale = (options and options.scale) or 1,
		startedAt = os.clock(),
		interval = 1 / q.hz,
		nextAt = 0,
		all = all,
		outer = outer,
		outerColors = outerColors,
		inner = inner,
		spikes = spikes,
		spikeColor = spikeColor,
		redColor = tipColor,
		light = light,
		ember = ember,
		gate = options and options.gate,
		sparks = sparks,
		sparkPhase = sparkPhase,
		sparkDir = sparkDir,
		smoke = smoke,
		smokePhase = smokePhase,
	}
	if q.still then
		-- Image figée : flamme pleinement allumée, hors poussée (t choisi pour que sin(2π t / période) soit négatif), sans animation.
		step(flame, flame.startedAt + SURGE_PERIOD * 34 + 1.6)
		return function()
			destroyFlame(flame)
		end
	end
	step(flame, flame.startedAt) -- première image tout de suite (pas de pièces à l'origine)
	table.insert(active, flame)
	if not connection then
		connection = RunService.RenderStepped:Connect(tick)
	end
	return function()
		destroyFlame(flame)
		flame.model = Instance.new("Model") -- sans parent : le gestionnaire la retirera au prochain passage
	end
end

return BombFlame
