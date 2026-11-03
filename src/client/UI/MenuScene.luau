--!strict
-- Décor 3D du menu principal : la cour d'entraînement (murs de briques, plateforme, 3 pads, caisses, bombes, arbres)
-- et les personnages Roblox des joueurs sur les pads (le joueur local au centre, les autres joueurs inscrits sur les
-- côtés).
--
-- Le décor est le modèle `ReplicatedStorage.MenuDecor` (exporté de Blender : 12 modèles, 319 MeshParts, textures et
-- matériaux déjà appliqués). Il est CLONÉ côté client et posé loin au-dessus de l'arène (ORIGIN), qui n'en est donc
-- jamais gênée ; rien n'est répliqué depuis le client. Si `MenuDecor` est absent, l'ancien décor en primitives
-- Roblox (_buildFallbackDecor) prend le relais avec un avertissement. Les personnages sont créés à partir des
-- identifiants Roblox des joueurs. Les animations de repos et de salut sont celles du script Animate par défaut.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Components = require(script.Parent.Components)

local MenuScene = {}
MenuScene.__index = MenuScene

local ORIGIN = Vector3.new(0, 600, 0)
local DECOR_TEMPLATE = "MenuDecor" -- dossier de ReplicatedStorage : décor importé (12 modèles ancrés)
local DECOR_TEMPLATE_LITE = "MenuDecorMobile" -- même décor allégé (≈ 58 % des triangles) pour téléphones et tablettes
local DECOR_ANCHOR = Vector3.new(0, 0, 25.6) -- point du modèle (centre du pad central, au sol) posé sur ORIGIN
local SLOT_X = { 0, -12, 12 } -- 1 : centre (joueur local) ; 2 : gauche ; 3 : droite (pads du modèle, espacés de 12)
local PODIUM_TOP = 1.7 -- hauteur du dessus des pads au-dessus du sol du décor
local SLOT_X_FALLBACK = { 0, -9, 9 } -- décor de secours (primitives)
local PODIUM_TOP_FALLBACK = 1.4
local RING_BRIGHT = Color3.fromRGB(255, 215, 80)
local RING_DIM = Color3.fromRGB(230, 160, 40)

local LightingAny = Lighting :: any -- accès par nom de propriété (MENU_LIGHTING)

-- Éclairage du menu, réglé en LOCAL (client) tant que le menu est affiché puis rétabli : le serveur (MapService) applique
-- l'éclairage de la carte à toute la partie, le menu a le sien. Calé sur la scène Blender d'origine : soleil chaud à 55°
-- venant de l'avant-gauche (ClockTime 10,39 et latitude -2,75 donnent cette direction), ambiance neutre, brume légère.
local MENU_LIGHTING: { [string]: any } = {
	ClockTime = 10.39,
	GeographicLatitude = -2.75,
	Brightness = 1.6,
	Ambient = Color3.fromRGB(112, 114, 124),
	OutdoorAmbient = Color3.fromRGB(128, 130, 142),
	ColorShift_Top = Color3.fromRGB(255, 240, 210),
	ExposureCompensation = -0.2,
	EnvironmentDiffuseScale = 0.6,
	EnvironmentSpecularScale = 0.5,
	ShadowSoftness = 0.3,
}
local MENU_ATMOSPHERE_DENSITY = 0.1
local MENU_BLOOM_INTENSITY = 0.35
local MENU_BLOOM_THRESHOLD = 0.95
local MENU_SATURATION = 0.12
local MENU_CONTRAST = 0.06
local PAD_LIGHT_BASE = 0.25 -- luminosité des lumières de pad : base + pulsation
local PAD_LIGHT_PULSE = 0.4

-- Animations du décor : amplitudes, durées et déphasages repris de la boucle de référence de Blender (30 images/s).
local FPS = 30
local PAD_CYCLE = 80 / FPS -- anneaux, lumières et ondes des pads : 80 images
local PAD_PHASE = { 0 / FPS, 27 / FPS, 53 / FPS } -- déphasage de chaque pad, en secondes
local PAD_WAVE_GROWTH = 0.5 -- les ondes passent de l'échelle 1,0 à 1,5
local PAD_WAVE_FROM = 0.35 -- leur transparence passe de 0,35 à 1
local DUST_SIZE = Vector3.new(70, 26, 110)
local DUST_CENTER = Vector3.new(0, 13, 20) -- par rapport à ORIGIN (le pad central est en z = 0) ; couvre la cour vue par la caméra
local ROOT_HEIGHT = 3 -- hauteur de HumanoidRootPart au-dessus de ses pieds (R15, taille 1)
local ACTOR_SCALE = 2.2 -- personnages agrandis : avec le plan d'ensemble, un personnage normal ne ferait que 12 % de la hauteur
local HEAD_ABOVE_ROOT = 2 -- sommet de la tête au-dessus du centre du corps (R15, taille 1)
local NAME_OFFSET = HEAD_ABOVE_ROOT * ACTOR_SCALE + 1.9 -- pseudo : 1,9 stud au-dessus de la tête
-- Bulle de chat : à DROITE de la tête, pas au-dessus du pseudo (elle recouvrirait le bas du logo, dessiné par-dessus). Le
-- décalage latéral est en fraction de la largeur de la bulle (ExtentsOffset) : il reste valable quelle que soit la taille d'écran.
local BUBBLE_HEIGHT = HEAD_ABOVE_ROOT * ACTOR_SCALE * 0.35 -- à hauteur de poitrine : sous le pseudo, qui est au-dessus de la tête
local BUBBLE_SIDE = 1.1 -- bord gauche de la bulle (250 px) à 150 px du centre : hors du pseudo (260 px, demi-largeur 130)
local BURST_RANDOM = Random.new(7)
local IDLE_ANIMATION = "rbxassetid://17172918855"
local WAVE_ANIMATION = "rbxassetid://507770239"
local WAVE_INTERVAL = 6
local SWAY_DEGREES = 9
local SWAY_SPEED = 0.9

-- Cadrage de la maquette : le personnage occupe environ 30 % de la hauteur (pieds vers 70 %, tête vers 42 %).
-- Cadrage : le plan d'ensemble de la caméra principale de Blender (toute la cour vue depuis l'entrée). Blender : caméra en
-- (0, -19, 12.5) visant (0, 60, 10), objectif 20 mm = 53,7° de champ vertical. Ici le décor est décalé de -25,6 en
-- profondeur (DECOR_ANCHOR) : la caméra est donc en z = -19 - 25,6 et vise z = 60 - 25,6. CameraController adapte le champ
-- de vision pour que le cadre 16:9 de l'interface reste visible sur tout écran.
MenuScene.CameraCFrame = CFrame.lookAt(ORIGIN + Vector3.new(0, 12.5, -19 - DECOR_ANCHOR.Z), ORIGIN + Vector3.new(0, 10, 60 - DECOR_ANCHOR.Z))
MenuScene.FieldOfView = 53.7
MenuScene.forceLite = false -- réservé aux tests : force le décor allégé même sur un ordinateur

type Actor = {
	userId: number,
	slot: number,
	isLocal: boolean,
	phase: number,
	destroyed: boolean,
	model: Model?,
	root: BasePart?,
	bomb: BasePart?,
	idle: AnimationTrack?,
	wave: AnimationTrack?,
	gui: BillboardGui?,
	status: TextLabel?,
	lastWave: number,
	animator: Animator?,
	emoteTracks: { [string]: AnimationTrack },
	emote: AnimationTrack?,
	emoteToken: number,
}

local function part(parent: Instance, name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Position = ORIGIN + offset
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function crate(parent: Instance, x: number, z: number, size: number)
	part(parent, "Crate", Vector3.new(size, size, size), Vector3.new(x, size / 2, z), Color3.fromRGB(205, 140, 62), Enum.Material.WoodPlanks)
	part(parent, "CrateLid", Vector3.new(size * 0.8, 0.3, size * 0.8), Vector3.new(x, size + 0.15, z), Color3.fromRGB(232, 170, 86), Enum.Material.WoodPlanks)
end

local function groundBomb(parent: Instance, x: number, z: number)
	part(parent, "Bomb", Vector3.new(2.2, 2.2, 2.2), Vector3.new(x, 1.1, z), Color3.fromRGB(35, 35, 45), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	part(parent, "Fuse", Vector3.new(0.4, 0.4, 0.4), Vector3.new(x, 2.5, z), Color3.fromRGB(255, 150, 30), Enum.Material.Neon, Enum.PartType.Ball)
end

function MenuScene.new()
	local self = setmetatable({}, MenuScene)
	self.actors = {} :: { [number]: Actor }
	self.visible = false
	self.connection = nil :: RBXScriptConnection?
	self.bombColor = Color3.fromRGB(35, 35, 45)

	local folder = Instance.new("Folder")
	folder.Name = "MenuScene"
	self.folder = folder

	self.slotX = SLOT_X
	self.podiumTop = PODIUM_TOP
	self.podiums = {} :: { [number]: BasePart }
	self.plusGuis = {} :: { [number]: BillboardGui }
	self.inviteOpen = {} :: { [number]: boolean }
	self.onInvite = nil :: (() -> ())?
	self.rings = {} :: { { part: BasePart, phase: number, light: PointLight? } }
	self.lightingSaved = nil :: { [string]: any }?
	self.lightingConnections = {} :: { RBXScriptConnection }
	self.menuColorCorrection = nil :: ColorCorrectionEffect?
	self.pulses = {} :: { { part: BasePart, baseSize: Vector3, phase: number } }
	self.swayers = {} :: { { part: BasePart, base: CFrame, ax: number, ay: number, az: number, omega: number, phase: number } }
	self.emitters = {} :: { ParticleEmitter }
	self.fuseLights = {} :: { { light: PointLight, phase: number } }
	self.sparkers = {} :: { { emitter: ParticleEmitter, nextBurst: number } }
	self.lowPower = false -- vrai avec le décor allégé : moins de particules

	if not self:_buildDecor(folder) then
		warn("[MenuScene] ReplicatedStorage." .. DECOR_TEMPLATE .. " introuvable ou incomplet : décor de secours (primitives)")
		self.slotX = SLOT_X_FALLBACK
		self.podiumTop = PODIUM_TOP_FALLBACK
		self.podiums = {}
		self:_buildFallbackDecor(folder)
	end

	folder.Parent = workspace
	return self
end

-- Décor importé : clone de ReplicatedStorage.MenuDecor, posé à ORIGIN, purement visuel (rien ne collisionne ni ne
-- répond aux requêtes). Les 3 pads servent de podiums ; leurs anneaux et ondes sont animés par _animateDecor.
function MenuScene._buildDecor(self, folder: Folder): boolean
	-- Téléphones et tablettes (écran tactile sans clavier) : décor allégé s'il existe, sinon le décor complet.
	local template: Instance? = nil
	if MenuScene.forceLite or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		template = ReplicatedStorage:FindFirstChild(DECOR_TEMPLATE_LITE)
		self.lowPower = template ~= nil
	end
	if not template then
		template = ReplicatedStorage:WaitForChild(DECOR_TEMPLATE, 10)
	end
	if not template then
		return false
	end
	local decor = template:Clone()
	decor.Name = "Decor"
	local shift = ORIGIN - DECOR_ANCHOR
	for _, descendant in decor:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame += shift
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	local tops: { BasePart } = {}
	for index = 1, 3 do
		local top = decor:FindFirstChild("PAD_" .. index .. "_Top", true)
		if top and top:IsA("BasePart") then
			table.insert(tops, top)
		end
		local ring = decor:FindFirstChild("PAD_" .. index .. "_Ring", true)
		if ring and ring:IsA("BasePart") then
			table.insert(self.rings, { part = ring, phase = PAD_PHASE[index], light = ring:FindFirstChildWhichIsA("PointLight", true) })
		end
		local pulse = decor:FindFirstChild("PAD_" .. index .. "_Pulse", true)
		if pulse and pulse:IsA("BasePart") then
			table.insert(self.pulses, { part = pulse, baseSize = pulse.Size, phase = PAD_PHASE[index] })
		end
	end
	if #tops < 3 then
		decor:Destroy()
		table.clear(self.rings)
		table.clear(self.pulses)
		table.clear(self.swayers)
		table.clear(self.emitters)
		table.clear(self.fuseLights)
		table.clear(self.sparkers)
		return false
	end

	-- Chaque emplacement prend le pad dont la position est la plus proche de SLOT_X.
	for slotIndex, x in SLOT_X do
		local best: BasePart = tops[1]
		local bestDistance = math.huge
		for _, top in tops do
			local distance = math.abs(top.Position.X - ORIGIN.X - x)
			if distance < bestDistance then
				best, bestDistance = top, distance
			end
		end
		self.podiums[slotIndex] = best
	end

	self:_buildMotion(decor)
	decor.Parent = folder
	return true
end

-- Balancements (mèches, feuillages, volants) et émetteurs (étincelles, fumée des mèches, vapeur des tuyaux, poussières).
function MenuScene._addSway(self, part: BasePart, axDegrees: number, ayDegrees: number, azDegrees: number, cycleFrames: number, phaseFrames: number)
	table.insert(self.swayers, {
		part = part,
		base = part:GetPivot(), -- les pivots du modèle sont ceux de Blender (mèche : fond du col ; feuillage : sommet du tronc)
		ax = math.rad(axDegrees),
		ay = math.rad(ayDegrees),
		az = math.rad(azDegrees),
		omega = 2 * math.pi / (cycleFrames / FPS),
		phase = phaseFrames / FPS,
	})
end

function MenuScene._buildMotion(self, decor: Instance)
	local fuseIndex = 0
	local treePhase: { [string]: number } = {}
	local treeCount = 0
	for _, descendant in decor:GetDescendants() do
		if descendant:IsA("MeshPart") then
			local name = descendant.Name
			if string.find(name, "^BOMB_Fuse_") then
				self:_addSway(descendant, 3, 0, 2.5, 60, fuseIndex * 7)
				fuseIndex += 1
			elseif string.find(name, "_Foliage") then
				-- Les 3 pièces d'un même arbre (une par matériau) partagent le pivot et la phase.
				local tree = string.gsub(name, "__.*$", "")
				if treePhase[tree] == nil then
					treePhase[tree] = treeCount * 17
					treeCount += 1
				end
				self:_addSway(descendant, 1.2, 1.8, 0.8, 120, treePhase[tree])
			elseif string.find(name, "^PIPE_Valve_Wheel") then
				self:_addSway(descendant, 0, 0, 10, 240, 0)
			end
		elseif descendant:IsA("Attachment") then
			if string.find(descendant.Name, "^BOMB_SparkAnchor_") then
				-- Mèche allumée : étincelles, flamme, et (décor complet) halo, fumée et lumière qui vacille.
				local sparks = MenuScene._sparkEmitter(descendant, self.lowPower)
				table.insert(self.emitters, sparks)
				table.insert(self.sparkers, { emitter = sparks, nextBurst = BURST_RANDOM:NextNumber() })
				table.insert(self.emitters, MenuScene._flameEmitter(descendant, self.lowPower))
				if not self.lowPower then
					table.insert(self.emitters, MenuScene._glowEmitter(descendant))
					table.insert(self.emitters, MenuScene._fuseSmokeEmitter(descendant))
					local light = Instance.new("PointLight")
					light.Name = "FuseLight"
					light.Color = Color3.fromRGB(255, 150, 50)
					light.Range = 8
					light.Brightness = 1.4
					light.Shadows = false
					light.Enabled = false
					light.Parent = descendant
					table.insert(self.fuseLights, { light = light, phase = #self.fuseLights * 1.7 })
				end
			elseif string.find(descendant.Name, "^PIPE_SmokeAnchor_") then
				table.insert(self.emitters, MenuScene._steamEmitter(descendant, string.find(descendant.Name, "_2$") ~= nil))
			end
		end
	end

	-- Poussières lumineuses : volume invisible au-dessus de la cour (omises avec le décor allégé).
	if self.lowPower then
		return
	end
	local dust = Instance.new("Part")
	dust.Name = "DustVolume"
	dust.Anchored = true
	dust.CanCollide = false
	dust.CanQuery = false
	dust.CanTouch = false
	dust.Transparency = 1
	dust.Size = DUST_SIZE
	dust.CFrame = CFrame.new(ORIGIN + DUST_CENTER)
	dust.Parent = decor
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Motes"
	motes.Enabled = false
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Rate = 6
	motes.Lifetime = NumberRange.new(6, 9)
	motes.Speed = NumberRange.new(0.2, 0.5)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Size = NumberSequence.new(0.12)
	motes.LightEmission = 1
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180))
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	motes.Parent = dust
	table.insert(self.emitters, motes)
end

-- Valeurs de la spécification Blender (étincelles : 6/s, taille 0,15) fortement agrandies : la caméra du menu est à 25-60
-- studs des bombes, des particules de 0,15 stud ne feraient que 2 à 4 pixels.
function MenuScene._sparkEmitter(parent: Attachment, lite: boolean): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparks"
	e.Enabled = false
	e.Rate = if lite then 14 else 26
	e.Lifetime = NumberRange.new(0.35, 0.9)
	e.Speed = NumberRange.new(4, 9)
	e.SpreadAngle = Vector2.new(75, 75)
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 190)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 196, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 20)),
	})
	e.LightEmission = 1
	e.Acceleration = Vector3.new(0, -14, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.4, 0.4), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
	return e
end

-- Flamme au bout de la mèche : cœur blanc-jaune qui vire à l'orange puis au rouge en montant.
function MenuScene._flameEmitter(parent: Attachment, lite: boolean): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Flame"
	e.Enabled = false
	e.Rate = if lite then 10 else 20
	e.Lifetime = NumberRange.new(0.25, 0.45)
	e.Speed = NumberRange.new(0.8, 1.8)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 210)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 170, 45)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 60, 10)),
	})
	e.LightEmission = 1
	e.Acceleration = Vector3.new(0, 3, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(0.6, 0.65), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
	return e
end

-- Halo chaud autour de la flamme (lisible de loin).
function MenuScene._glowEmitter(parent: Attachment): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "FuseGlow"
	e.Enabled = false
	e.Rate = 5
	e.Lifetime = NumberRange.new(0.45, 0.6)
	e.Speed = NumberRange.new(0, 0)
	e.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60))
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.0), NumberSequenceKeypoint.new(1, 2.0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
	return e
end

function MenuScene._fuseSmokeEmitter(parent: Attachment): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "FuseSmoke"
	e.Enabled = false
	e.Rate = 3
	e.Lifetime = NumberRange.new(1.0, 1.6)
	e.Speed = NumberRange.new(0.6, 1.2)
	e.SpreadAngle = Vector2.new(20, 20)
	e.Color = ColorSequence.new(Color3.fromRGB(170, 170, 175))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.1) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
	return e
end

-- Vapeur des bouches de ventilation : la bouche « 1 » monte, la bouche « 2 » (colonne verticale) souffle vers la salle.
-- Vapeur des bouches : valeurs relevées dans la scène Blender (FX_Smoke_*), sans modification. Cycle de 80 images à 30 i/s, 5 bouffées
-- par bouche réparties régulièrement ; diamètre 0,3 → 0,9 → 1,8 → 2,5 studs ; opacité 0 → 0,42 → 0,26 → 0 ; couleur (0,92 ; 0,93 ; 0,96)
-- linéaire, émission 0,15. Trajet en studs (axes Roblox) : bouche « 1 » (-0,7 ; 4,6 ; 0,95), bouche « 2 » (1,5 ; 3,4 ; 0,82), soit vers le haut
-- et, pour la « 2 », un peu vers la salle (le mur à tuyaux est à x négatif : la salle est vers +X).
function MenuScene._steamEmitter(parent: Attachment, towardRoom: boolean): ParticleEmitter
	local travel = if towardRoom then Vector3.new(1.5, 3.4, 0.82) else Vector3.new(-0.7, 4.6, 0.95)
	local lifetime = 80 / FPS
	-- L'émetteur part dans la direction « haut » de son attachement : on l'oriente selon le trajet de Blender.
	local position = parent.WorldPosition
	parent.WorldCFrame = CFrame.lookAt(position, position + travel) * CFrame.Angles(-math.pi / 2, 0, 0)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Steam"
	e.Enabled = false
	e.Texture = "rbxasset://textures/particles/smoke_main.dds" -- sans texture, Roblox dessine une étoile scintillante, pas un nuage
	e.Rate = 5 / lifetime
	e.Lifetime = NumberRange.new(lifetime)
	e.Speed = NumberRange.new(travel.Magnitude / lifetime)
	e.SpreadAngle = Vector2.new(0, 0)
	e.Acceleration = Vector3.zero
	e.Rotation = NumberRange.new(0, 360)
	e.Color = ColorSequence.new(Color3.fromRGB(246, 247, 250))
	e.LightEmission = 0.1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.125, 0.9),
		NumberSequenceKeypoint.new(0.5625, 1.8),
		NumberSequenceKeypoint.new(1, 2.5),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.125, 0.58),
		NumberSequenceKeypoint.new(0.5625, 0.74),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = parent
	return e
end

-- Ancien décor en primitives Roblox : utilisé seulement si le modèle importé est absent.
function MenuScene._buildFallbackDecor(self, folder: Folder)
	-- Sol et plateforme.
	part(folder, "Floor", Vector3.new(140, 1, 90), Vector3.new(0, -0.5, 6), Color3.fromRGB(124, 128, 138), Enum.Material.Concrete)
	part(folder, "Platform", Vector3.new(40, 0.6, 16), Vector3.new(0, 0.3, 0), Color3.fromRGB(78, 82, 94), Enum.Material.DiamondPlate)
	for i = 0, 19 do
		local color = if i % 2 == 0 then Color3.fromRGB(240, 200, 40) else Color3.fromRGB(34, 34, 40)
		part(folder, "Hazard", Vector3.new(2, 0.7, 1), Vector3.new(-19 + i * 2, 0.35, -8.3), color, Enum.Material.SmoothPlastic)
		part(folder, "Hazard", Vector3.new(2, 0.7, 1), Vector3.new(-19 + i * 2, 0.35, 8.3), color, Enum.Material.SmoothPlastic)
	end

	-- Podiums (cylindres verticaux) avec leur anneau doré. Les podiums sont mémorisés : les marqueurs « + »
	-- d'invitation s'y accrochent.
	for slotIndex, x in SLOT_X_FALLBACK do
		local podium = part(folder, "Podium", Vector3.new(0.8, 7, 7), Vector3.new(x, 1, 0), Color3.fromRGB(112, 116, 128), Enum.Material.Metal, Enum.PartType.Cylinder)
		podium.CFrame = CFrame.new(ORIGIN + Vector3.new(x, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		self.podiums[slotIndex] = podium
		local ring = part(folder, "PodiumRing", Vector3.new(0.1, 7.7, 7.7), Vector3.new(x, 0.95, 0), Color3.fromRGB(255, 200, 60), Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.CFrame = CFrame.new(ORIGIN + Vector3.new(x, 0.95, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	end

	-- Mur de briques et couronnement de pierre.
	part(folder, "WallBack", Vector3.new(140, 26, 2), Vector3.new(0, 13, 16), Color3.fromRGB(178, 94, 62), Enum.Material.Brick)
	part(folder, "WallCap", Vector3.new(140, 1.6, 4), Vector3.new(0, 26.8, 16), Color3.fromRGB(128, 132, 142), Enum.Material.Concrete)
	part(folder, "Pillar", Vector3.new(4, 26, 4), Vector3.new(-18, 13, 15), Color3.fromRGB(128, 132, 142), Enum.Material.Concrete)

	-- Arbres derrière le mur.
	for _, x in { -30, -8, 26 } do
		part(folder, "TreeTrunk", Vector3.new(2.4, 14, 2.4), Vector3.new(x, 20, 24), Color3.fromRGB(110, 76, 46), Enum.Material.Wood)
		part(folder, "TreeLeaves", Vector3.new(15, 15, 15), Vector3.new(x, 31, 24), Color3.fromRGB(72, 150, 60), Enum.Material.Grass, Enum.PartType.Ball)
	end

	-- Caisses, conteneur, tonneau et bombes posées.
	crate(folder, -14, -3, 4)
	crate(folder, -16.5, -6.5, 3)
	crate(folder, 15, -2, 5)
	crate(folder, 12.5, -6.5, 3.4)
	crate(folder, 22, 4, 6)
	part(folder, "Container", Vector3.new(14, 6, 9), Vector3.new(-26, 3, 6), Color3.fromRGB(70, 150, 70), Enum.Material.Metal)
	local barrel = part(folder, "Barrel", Vector3.new(4, 3, 3), Vector3.new(19, 2, -5), Color3.fromRGB(150, 98, 50), Enum.Material.Wood, Enum.PartType.Cylinder)
	barrel.CFrame = CFrame.new(ORIGIN + Vector3.new(19, 2, -5)) * CFrame.Angles(0, 0, math.pi / 2)
	groundBomb(folder, -12, -9)
	groundBomb(folder, -10, -10.5)
	groundBomb(folder, 11, -10)
end

-- Anneaux dorés qui respirent et ondes qui s'élargissent en s'effaçant, sur chaque pad.
function MenuScene._animateDecor(self, now: number)
	for _, ring in self.rings do
		local glow = 0.5 + 0.5 * math.sin(2 * math.pi * (now + ring.phase) / PAD_CYCLE)
		ring.part.Color = RING_DIM:Lerp(RING_BRIGHT, glow)
		if ring.light then
			ring.light.Brightness = PAD_LIGHT_BASE + PAD_LIGHT_PULSE * glow
		end
	end
	for _, pulse in self.pulses do
		local t = ((now + pulse.phase) / PAD_CYCLE) % 1
		pulse.part.Size = pulse.baseSize * (1 + PAD_WAVE_GROWTH * t)
		pulse.part.Transparency = PAD_WAVE_FROM + (1 - PAD_WAVE_FROM) * t
	end
	for _, fuse in self.fuseLights do
		-- Vacillement irrégulier de la lumière de chaque mèche.
		fuse.light.Brightness = 1.0 + 1.1 * (0.5 + 0.5 * math.noise(now * 8, fuse.phase, 0.37))
	end
	for _, sparker in self.sparkers do
		-- Gerbes d'étincelles irrégulières, en plus du flux continu.
		if now >= sparker.nextBurst then
			sparker.emitter:Emit(14)
			sparker.nextBurst = now + 0.35 + BURST_RANDOM:NextNumber() * 0.9
		end
	end
	for _, sway in self.swayers do
		local a = math.sin(sway.omega * (now - sway.phase))
		-- L'axe vertical de Blender (Z) est l'axe Y de Roblox : les angles sont appliqués dans l'ordre (X, Z, Y).
		sway.part:PivotTo(sway.base * CFrame.Angles(sway.ax * a, sway.az * a, sway.ay * a))
	end
end

-- Acteurs ---------------------------------------------------------------------------------------------------

local function loadTrack(animator: Animator, id: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = looped
		track.Priority = priority
		return track
	end
	return nil
end

function MenuScene._buildActor(self, actor: Actor, name: string)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(actor.userId)
	end)
	if actor.destroyed then
		if ok and typeof(model) == "Instance" then
			model:Destroy()
		end
		return
	end
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return -- pas de personnage (identifiant invalide) : le podium reste vide, sans erreur visible
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model:ScaleTo(ACTOR_SCALE)
	root.Anchored = true
	model.Name = "Actor_" .. actor.userId
	local home = ORIGIN + Vector3.new(self.slotX[actor.slot], self.podiumTop + ROOT_HEIGHT * ACTOR_SCALE, 0)
	root.CFrame = CFrame.new(home)
	model.Parent = self.folder
	actor.model, actor.root = model, root

	-- Bombe tenue en main : main gauche pour le joueur local (la droite fait le salut), droite pour les autres.
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		local hand = model:FindFirstChild(if actor.isLocal then "LeftHand" else "RightHand")
		if hand and hand:IsA("BasePart") then
			local bomb = Instance.new("Part")
			bomb.Name = "HeldBomb"
			bomb.Shape = Enum.PartType.Ball
			bomb.Size = Vector3.new(1.7, 1.7, 1.7) * ACTOR_SCALE
			bomb.Color = if actor.isLocal then self.bombColor else Color3.fromRGB(35, 35, 45)
			bomb.Material = Enum.Material.SmoothPlastic
			bomb.CanCollide = false
			bomb.CanQuery = false
			bomb.CanTouch = false
			bomb.Massless = true
			bomb.CFrame = hand.CFrame * CFrame.new(0, -0.9 * ACTOR_SCALE, -0.2 * ACTOR_SCALE)
			bomb.Parent = model
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = bomb
			weld.Parent = bomb
			actor.bomb = bomb
		end

		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		actor.animator = animator
		actor.idle = loadTrack(animator, IDLE_ANIMATION, true, Enum.AnimationPriority.Idle)
		if actor.isLocal then
			actor.wave = loadTrack(animator, WAVE_ANIMATION, false, Enum.AnimationPriority.Action)
		end
		if actor.idle then
			actor.idle:Play()
			if not self.visible then
				actor.idle:AdjustSpeed(0)
			end
		end
	end

	-- Pseudonyme et statut au-dessus de la tête.
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Adornee = root
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(260, 64)
	gui.StudsOffset = Vector3.new(0, NAME_OFFSET, 0)
	gui.Enabled = self.visible
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 36)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 30
	nameLabel.Text = name
	nameLabel.TextColor3 = if actor.isLocal then Color3.fromRGB(90, 200, 255) else Color3.fromRGB(255, 120, 100)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.Parent = gui
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(0, 34)
	status.Size = UDim2.new(1, 0, 0, 24)
	status.Font = Enum.Font.GothamBold
	status.TextSize = 20
	status.Text = ""
	status.TextColor3 = Color3.fromRGB(110, 230, 110)
	status.TextStrokeTransparency = 0
	status.Parent = gui
	gui.Parent = root
	actor.gui, actor.status = gui, status
end

function MenuScene._removeActor(self, userId: number)
	local actor = self.actors[userId]
	if actor then
		actor.destroyed = true
		if actor.model then
			actor.model:Destroy()
		end
		self.actors[userId] = nil
	end
end

function MenuScene._ensureActor(self, userId: number, name: string, slot: number, isLocal: boolean): Actor
	local existing = self.actors[userId]
	if existing and existing.slot == slot then
		return existing
	end
	if existing then
		self:_removeActor(userId)
	end
	local actor: Actor = {
		userId = userId, slot = slot, isLocal = isLocal, phase = slot * 1.7, destroyed = false,
		model = nil, root = nil, bomb = nil, idle = nil, wave = nil, gui = nil, status = nil, lastWave = os.clock(),
		animator = nil, emoteTracks = {}, emote = nil, emoteToken = 0,
	}
	self.actors[userId] = actor
	task.spawn(function()
		self:_buildActor(actor, name)
	end)
	return actor
end

-- Le joueur local occupe toujours le podium central.
function MenuScene.setLocalPlayer(self, userId: number, name: string)
	self:_ensureActor(userId, name, 1, true)
end

-- Marqueur « + » d'invitation sur un podium : cercle blanc translucide cliquable, posé au-dessus du podium vide.
-- C'est un BillboardGui dans PlayerGui adossé au podium : seul moyen qu'une interface 2D suive un objet 3D et reçoive
-- les clics.
function MenuScene._plusGui(self, slot: number): BillboardGui
	local existing = self.plusGuis[slot]
	if existing then
		return existing
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "InviteSlot" .. slot
	gui.Adornee = self.podiums[slot]
	gui.AlwaysOnTop = true
	gui.Active = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(78, 78)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5 * ACTOR_SCALE, 0) -- à hauteur de poitrine d'un personnage
	gui.Enabled = false

	local button = Instance.new("TextButton")
	button.Name = "Plus"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromOffset(62, 62)
	button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	button.BackgroundTransparency = 0.82
	button.AutoButtonColor = false
	button.Text = "+"
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 46
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0.4
	button.Parent = gui
	Components.corner(button, 31)
	Components.stroke(button, Color3.new(1, 1, 1), 3)
	Components.addHover(button, { scale = 1.1 })
	button.Activated:Connect(function()
		if self.onInvite then
			self.onInvite()
		end
	end)

	local player = Players.LocalPlayer
	gui.Parent = player:WaitForChild("PlayerGui")
	self.plusGuis[slot] = gui
	return gui
end

-- slots : deux emplacements (voir PartySlots.compute), dans l'ordre des podiums latéraux (gauche puis droite).
-- Un emplacement « player » affiche le personnage et son statut ; un emplacement « invite » affiche le « + ».
function MenuScene.setParty(self, slots: { any }, onInvite: (() -> ())?)
	self.onInvite = onInvite
	local keep: { [number]: boolean } = {}
	for _, actor in self.actors do
		if actor.isLocal then
			keep[actor.userId] = true
		end
	end

	for index = 1, 2 do
		local slot = slots[index]
		local podiumSlot = index + 1
		local isInvite = slot == nil or slot.kind == "invite"
		self.inviteOpen[podiumSlot] = isInvite
		if isInvite then
			local gui = self:_plusGui(podiumSlot)
			gui.Enabled = self.visible
		else
			local gui = self.plusGuis[podiumSlot]
			if gui then
				gui.Enabled = false
			end
			local actor = self:_ensureActor(slot.userId, slot.name, podiumSlot, false)
			keep[slot.userId] = true
			if actor.status then
				actor.status.Text = slot.status or ""
				actor.status.TextColor3 = if slot.ready then Color3.fromRGB(110, 230, 110) else Color3.fromRGB(200, 205, 225)
			end
		end
	end

	for userId in table.clone(self.actors) do
		if not keep[userId] then
			self:_removeActor(userId)
		end
	end
end

-- Bulle de chat rapide au-dessus du personnage LOCAL du menu (aperçu : visible seulement par ce client ; en jeu
-- c'est le serveur qui affiche la bulle à tout le monde).
function MenuScene.showBubble(self, text: string, seconds: number)
	for _, actor in self.actors do
		if actor.isLocal and actor.root then
			local previous = actor.root:FindFirstChild("QuickChatBubble")
			if previous then
				previous:Destroy()
			end
			local gui = Instance.new("BillboardGui")
			gui.Name = "QuickChatBubble"
			gui.Adornee = actor.root
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			gui.Size = UDim2.fromOffset(250, 78)
			gui.StudsOffset = Vector3.new(0, BUBBLE_HEIGHT, 0)
			gui.ExtentsOffset = Vector3.new(BUBBLE_SIDE, 0, 0)
			local bubble = Instance.new("Frame")
			bubble.Size = UDim2.new(1, 0, 0, 62)
			bubble.BackgroundColor3 = Color3.new(1, 1, 1)
			bubble.BorderSizePixel = 0
			bubble.Parent = gui
			Components.corner(bubble, 16)
			Components.stroke(bubble, Color3.fromRGB(10, 10, 10), 4)
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, -20, 1, -10)
			label.Position = UDim2.fromOffset(10, 5)
			label.Font = Enum.Font.GothamBlack
			label.Text = text
			label.TextColor3 = Color3.fromRGB(10, 10, 10)
			label.TextScaled = true
			label.Parent = bubble
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 34
			limit.MinTextSize = 12
			limit.Parent = label
			gui.Enabled = self.visible
			gui.Parent = actor.root
			task.delay(seconds, function()
				if gui.Parent then
					gui:Destroy()
				end
			end)
		end
	end
end

-- Joue une émote sur le personnage LOCAL du menu (aperçu : ne concerne que ce client). emote : EmoteConfig.Emote.
function MenuScene.playEmote(self, emote: { id: string, animationId: string, looped: boolean }, maxLoopSeconds: number)
	for _, actor in self.actors do
		if actor.isLocal and actor.animator then
			if actor.emote then
				actor.emote:Stop(0.15)
				actor.emote = nil
			end
			local track = actor.emoteTracks[emote.id]
			if not track then
				local animation = Instance.new("Animation")
				animation.AnimationId = emote.animationId
				local ok, loaded = pcall(function()
					return (actor.animator :: Animator):LoadAnimation(animation)
				end)
				if not ok or not loaded then
					return
				end
				loaded.Priority = Enum.AnimationPriority.Action
				loaded.Looped = emote.looped
				actor.emoteTracks[emote.id] = loaded
				track = loaded
			end
			actor.emoteToken += 1
			local token = actor.emoteToken
			actor.emote = track
			actor.lastWave = os.clock() -- pas de salut automatique juste après
			track:Play(0.2)
			if emote.looped then
				task.delay(maxLoopSeconds, function()
					if actor.emoteToken == token and actor.emote == track then
						track:Stop(0.3)
						actor.emote = nil
					end
				end)
			end
		end
	end
end

-- Couleur de la bombe équipée par le joueur local (cosmétique : purement visuel).
function MenuScene.setLocalBombColor(self, color: Color3)
	self.bombColor = color
	for _, actor in self.actors do
		if actor.isLocal and actor.bomb then
			actor.bomb.Color = color
		end
	end
end

-- Éclairage du menu (local) ------------------------------------------------------------------------------------

local function sameValue(a: any, b: any): boolean
	if typeof(a) == "number" and typeof(b) == "number" then
		return math.abs(a - b) < 1e-4
	end
	return a == b
end

function MenuScene._applyMenuLighting(self)
	if self.lightingSaved then
		return
	end
	local saved: { [string]: any } = {}
	self.lightingSaved = saved
	for property, value in MENU_LIGHTING do
		saved[property] = LightingAny[property]
		LightingAny[property] = value
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		saved.atmosphereDensity = atmosphere.Density
		atmosphere.Density = MENU_ATMOSPHERE_DENSITY
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		saved.bloomIntensity = bloom.Intensity
		saved.bloomThreshold = bloom.Threshold
		bloom.Intensity = MENU_BLOOM_INTENSITY
		bloom.Threshold = MENU_BLOOM_THRESHOLD
	end
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "MenuColorCorrection"
	correction.Saturation = MENU_SATURATION
	correction.Contrast = MENU_CONTRAST
	correction.Parent = Lighting
	self.menuColorCorrection = correction

	-- Si le serveur change l'éclairage pendant que le menu est affiché (nouvelle carte), sa valeur devient la valeur à
	-- rétablir et le menu garde la sienne. Les changements égaux à la valeur du menu (les nôtres) sont ignorés.
	local connections = {}
	for property in MENU_LIGHTING do
		table.insert(
			connections,
			Lighting:GetPropertyChangedSignal(property):Connect(function()
				local current = LightingAny[property]
				if sameValue(current, MENU_LIGHTING[property]) then
					return
				end
				saved[property] = current
				LightingAny[property] = MENU_LIGHTING[property]
			end)
		)
	end
	self.lightingConnections = connections
end

function MenuScene._restoreMenuLighting(self)
	local saved = self.lightingSaved
	if not saved then
		return
	end
	self.lightingSaved = nil
	for _, connection in self.lightingConnections do
		connection:Disconnect()
	end
	self.lightingConnections = {}
	for property in MENU_LIGHTING do
		LightingAny[property] = saved[property]
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and saved.atmosphereDensity ~= nil then
		atmosphere.Density = saved.atmosphereDensity
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom and saved.bloomIntensity ~= nil then
		bloom.Intensity = saved.bloomIntensity
		bloom.Threshold = saved.bloomThreshold
	end
	if self.menuColorCorrection then
		self.menuColorCorrection:Destroy()
		self.menuColorCorrection = nil
	end
end

-- Affichage ---------------------------------------------------------------------------------------------------

function MenuScene._step(self)
	local now = os.clock()
	self:_animateDecor(now)
	for _, actor in self.actors do
		local root = actor.root
		if root then
			local home = ORIGIN + Vector3.new(self.slotX[actor.slot], self.podiumTop + ROOT_HEIGHT * ACTOR_SCALE, 0)
			root.CFrame = CFrame.new(home) * CFrame.Angles(0, math.rad(math.sin(now * SWAY_SPEED + actor.phase) * SWAY_DEGREES), 0)
			local emoting = actor.emote ~= nil and actor.emote.IsPlaying
			if actor.wave and not emoting and now - actor.lastWave >= WAVE_INTERVAL then
				actor.lastWave = now
				actor.wave:Play(0.2)
			end
		end
	end
end

function MenuScene.setVisible(self, visible: boolean)
	if visible == self.visible then
		return
	end
	self.visible = visible
	for _, emitter in self.emitters do
		emitter.Enabled = visible
	end
	for _, fuse in self.fuseLights do
		fuse.light.Enabled = visible
	end
	if visible then
		self:_applyMenuLighting()
	else
		self:_restoreMenuLighting()
	end
	for _, actor in self.actors do
		if actor.idle then
			actor.idle:AdjustSpeed(if visible then 1 else 0)
		end
		if actor.gui then
			actor.gui.Enabled = visible
		end
	end
	for slot, gui in self.plusGuis do
		gui.Enabled = visible and self.inviteOpen[slot] == true
	end
	if visible and not self.connection then
		self.connection = RunService.RenderStepped:Connect(function()
			self:_step()
		end)
	elseif not visible and self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

function MenuScene.destroy(self)
	self:setVisible(false)
	for userId in table.clone(self.actors) do
		self:_removeActor(userId)
	end
	for _, gui in self.plusGuis do
		gui:Destroy()
	end
	table.clear(self.plusGuis)
	self.folder:Destroy()
end

return MenuScene
