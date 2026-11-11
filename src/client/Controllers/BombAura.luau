--!strict
-- EFFETS D'AMBIANCE AUTOUR DES BOMBES, en géométrie néon animée (les particules ne s'affichent pas dans un ViewportFrame) :
-- éclairs bleus qui circulent autour de l'Électrique, flocons qui tombent autour de la Glacée, petites étoiles qui tournent autour
-- de la bombe Étoiles, billes arc-en-ciel, braises, feuilles, cœurs, volutes, scintillements... Les données (mode, forme, couleurs,
-- nombre) sont dans BombEffectsConfig (champ aura) ; ici, la mise en mouvement.
-- Purement visuel et local. UN seul gestionnaire (une connexion RenderStepped) anime toutes les auras ; les pièces vivent dans le
-- modèle et disparaissent avec lui. Sert pour : l'aperçu détaillé de la boutique / l'inventaire (bombe SÉLECTIONNÉE seulement),
-- le menu (bombe en main) et la bombe posée en partie. Les miniatures de la grille et le HUD n'en ont JAMAIS (ils sont figés).
-- `gate` : cadre d'interface qui porte l'aperçu ; tant qu'il (ou un de ses parents) n'est pas affiché, rien n'est calculé.
--
-- Qualités : full (aperçu, menu : toutes les pièces, 60 Hz), game (bombe posée : moitié des pièces, 30 Hz ; density réduit encore).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BombEffectsConfig = require(ReplicatedStorage.Shared.BombEffectsConfig)
local BombFlame = require(script.Parent.BombFlame)

local TAU = math.pi * 2
local BODY_RADIUS = 1.5 -- rayon du corps de chaque modèle (3 studs de diamètre)
local FADE_IN = 0.5 -- secondes : l'aura apparaît en douceur
local BOLT_SEGMENTS = 6

export type Quality = "full" | "game"
export type Options = { quality: Quality?, scale: number?, density: number?, gate: GuiObject? }

local HZ = { full = 60, game = 30 }

type Piece = {
	parts: { BasePart },
	phase: number, -- 0..1, décale les pièces entre elles
	a: number, -- 0..1 hasard fixe (rayon, inclinaison)
	b: number,
	color: Color3,
}

type Bolt = { parts: { BasePart }, index: number, nextRoll: number, visibleUntil: number }

type Aura = {
	model: Model,
	collar: BasePart,
	offset: Vector3, -- centre du corps dans le repère local du col
	scale: number,
	startedAt: number,
	interval: number,
	nextAt: number,
	cfg: BombEffectsConfig.Aura,
	boltColor: Color3,
	pieces: { Piece },
	bolts: { Bolt },
	random: Random,
	gate: GuiObject?,
	all: { Instance },
}

local BombAura = {}

local active: { Aura } = {}
local connection: RBXScriptConnection? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function newPart(model: Model, name: string, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = "BBAura_" .. name
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	part.Transparency = 1
	if shape then
		part.Shape = shape
	end
	part.Parent = model
	return part
end

local function spindle(model: Model, name: string, color: Color3): Part
	local part = newPart(model, name, color, Enum.Material.Neon, nil)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Pièces d'une forme : sparkle = 3 fuseaux croisés (visible sous tous les angles), heart = carré posé sur la pointe + 2 boules,
-- leaf = ellipsoïde aplati, rock = bloc, ball = sphère.
local function buildShape(model: Model, shape: string, color: Color3, label: string): { BasePart }
	if shape == "sparkle" then
		return { spindle(model, label .. "A", color), spindle(model, label .. "B", color), spindle(model, label .. "C", color) }
	elseif shape == "heart" then
		return {
			newPart(model, label .. "Block", color, Enum.Material.Neon, nil),
			newPart(model, label .. "L", color, Enum.Material.Neon, Enum.PartType.Ball),
			newPart(model, label .. "R", color, Enum.Material.Neon, Enum.PartType.Ball),
		}
	elseif shape == "leaf" then
		return { spindle(model, label, color) }
	elseif shape == "rock" then
		return { newPart(model, label, color, Enum.Material.Slate, nil) }
	end
	return { newPart(model, label, color, Enum.Material.Neon, Enum.PartType.Ball) }
end

-- Pose une pièce (position, taille, rotation, transparence). size <= 0 : cachée.
local function placePiece(shape: string, piece: Piece, position: Vector3, size: number, rot: number, transparency: number)
	local parts = piece.parts
	if size <= 0.005 then
		for _, part in parts do
			part.Transparency = 1
		end
		return
	end
	if shape == "sparkle" then
		local base = CFrame.new(position) * CFrame.Angles(rot * 0.3, rot, rot * 0.5)
		local thick = size * 0.17
		parts[1].Size = Vector3.new(thick, size, thick)
		parts[1].CFrame = base
		parts[2].Size = Vector3.new(thick, size, thick)
		parts[2].CFrame = base * CFrame.Angles(0, 0, math.pi / 2)
		parts[3].Size = Vector3.new(thick, size * 0.6, thick)
		parts[3].CFrame = base * CFrame.Angles(math.pi / 2, 0, 0)
	elseif shape == "heart" then
		local d = size * 0.5
		local base = CFrame.new(position) * CFrame.Angles(0, rot * 0.4, 0)
		parts[1].Size = Vector3.new(d, d, d * 0.85)
		parts[1].CFrame = base * CFrame.Angles(0, 0, math.pi / 4)
		local offset = d * 0.3536
		parts[2].Size = Vector3.new(d, d, d)
		parts[2].CFrame = base * CFrame.new(-offset, offset, 0)
		parts[3].Size = Vector3.new(d, d, d)
		parts[3].CFrame = base * CFrame.new(offset, offset, 0)
	elseif shape == "leaf" then
		parts[1].Size = Vector3.new(size, size * 0.2, size * 0.55)
		parts[1].CFrame = CFrame.new(position) * CFrame.Angles(rot, rot * 0.7, rot * 1.3)
	elseif shape == "rock" then
		parts[1].Size = Vector3.new(size, size * 0.8, size * 0.9)
		parts[1].CFrame = CFrame.new(position) * CFrame.Angles(rot, rot * 0.6, rot * 0.3)
	else
		parts[1].Size = Vector3.new(size, size, size)
		parts[1].Position = position
	end
	for _, part in parts do
		part.Transparency = transparency
		part.Color = piece.color
	end
end

-- Éclair : suite de segments entre deux points du corps ; son point de départ CIRCULE autour de la bombe (azimut qui avance
-- avec le temps), le reste est tiré au hasard à chaque claquement.
local function rollBolt(aura: Aura, bolt: Bolt, center: Vector3, now: number)
	local s = aura.scale
	local random = aura.random
	local count = #aura.bolts
	local theta = (now - aura.startedAt) * 0.9 + (bolt.index - 1) * TAU / count + random:NextNumber(-0.35, 0.35)
	local height = random:NextNumber(-0.3, 0.85)
	local flat = math.sqrt(1 - height * height)
	local from = Vector3.new(math.cos(theta) * flat, height, math.sin(theta) * flat)
	local sweep = random:NextNumber(0.7, 1.3) * (if random:NextInteger(0, 1) == 0 then 1 else -1)
	local height2 = math.clamp(height + random:NextNumber(-0.5, 0.5), -0.5, 0.95)
	local flat2 = math.sqrt(1 - height2 * height2)
	local to = Vector3.new(math.cos(theta + sweep) * flat2, height2, math.sin(theta + sweep) * flat2)
	local radius = (aura.cfg.radius or 1.12) * BODY_RADIUS * s
	local points: { Vector3 } = {}
	for index = 0, BOLT_SEGMENTS do
		local k = index / BOLT_SEGMENTS
		local direction = from:Lerp(to, k)
		if direction.Magnitude < 0.05 then
			direction = from
		end
		-- l'arc se décolle du corps (bosse au milieu) et zigzague
		local bulge = 0.32 * s * math.sin(math.pi * k)
		local jitter = if index == 0 or index == BOLT_SEGMENTS then 0 else random:NextNumber(-0.16, 0.2) * s
		table.insert(points, center + direction.Unit * (radius + bulge + jitter))
	end
	local thickness = aura.cfg.size * s * random:NextNumber(0.7, 1.2)
	for index, part in bolt.parts do
		local a, b = points[index], points[index + 1]
		part.Size = Vector3.new(thickness, thickness, math.max((b - a).Magnitude, 0.02))
		part.CFrame = CFrame.lookAt((a + b) / 2, b)
		part.Color = aura.boltColor
	end
	bolt.visibleUntil = now + random:NextNumber(0.16, 0.36)
	bolt.nextRoll = bolt.visibleUntil + random:NextNumber(0.03, 0.22)
end

local function destroyAura(aura: Aura)
	for _, instance in aura.all do
		instance:Destroy()
	end
	table.clear(aura.all)
end

local function step(aura: Aura, now: number)
	local t = now - aura.startedAt
	local cfg = aura.cfg
	local s = aura.scale
	local center = aura.collar.CFrame:PointToWorldSpace(aura.offset)
	local fade = math.min(t / FADE_IN, 1)
	local mode = cfg.mode
	local alpha = cfg.alpha or 0
	local shape = cfg.shape

	if mode == "bolts" then
		for index, bolt in aura.bolts do
			if now >= bolt.nextRoll and now >= bolt.visibleUntil then
				rollBolt(aura, bolt, center, now)
			end
			local visible = now < bolt.visibleUntil and fade > 0.2
			local flicker = if visible then 0.05 + 0.45 * (math.sin(t * 90 + index * 5) * 0.5 + 0.5) else 1
			for _, part in bolt.parts do
				part.Transparency = flicker
			end
		end
		return
	end

	for index, piece in aura.pieces do
		local k = piece.phase
		if mode == "orbit" then
			local angle = (t * cfg.speed + k) * TAU
			local radius = (cfg.radius or 1.3) * BODY_RADIUS * s * (1 + 0.06 * math.sin(t * 2 + k * 7))
			local tilt = if index % 2 == 0 then 0.5 else -0.45
			local x, z = math.cos(angle) * radius, math.sin(angle) * radius
			local y = z * math.sin(tilt) + 0.22 * s * math.sin(t * 1.6 + k * TAU)
			local size = cfg.size * s * (0.75 + 0.3 * math.sin(t * 5 + k * 11)) * fade
			placePiece(shape, piece, center + Vector3.new(x, y, z * math.cos(tilt)), size, t * 1.4 + k * 6, alpha)
		elseif mode == "fall" or mode == "rise" then
			local tau = (t * cfg.speed + k) % 1
			local y0, y1 = cfg.y0 or 0, cfg.y1 or 2
			local y = (y0 + (y1 - y0) * tau) * s
			local radius = (cfg.radius or 1) * BODY_RADIUS * s * (0.62 + 0.5 * piece.a) * (if mode == "rise" then 0.6 + 0.6 * tau else 1)
			local angle = piece.b * TAU * 3 + math.sin(t * 1.3 + k * 5) * 0.7 + (if mode == "rise" then t * 0.7 else 0)
			local sway = 0.14 * s * math.sin(t * 2.1 + k * 9)
			local position = center + Vector3.new(math.cos(angle) * radius + sway, y, math.sin(angle) * radius)
			local life = math.max(math.min(tau / 0.14, (1 - tau) / 0.2, 1), 0)
			local size = cfg.size * s * (if mode == "rise" then 1 - 0.45 * tau else 1) * life * fade
			placePiece(shape, piece, position, size, t * 1.8 + k * 8, math.clamp(1 - life * (1 - alpha), alpha, 1))
		elseif mode == "glint" then
			local period = 2.4 + piece.a * 1.4
			local tau = ((t + k * period * 3) % period) / period
			local size = 0
			if tau < 0.16 then
				size = cfg.size * s * math.sin(math.pi * tau / 0.16)
			end
			local direction = if index % 2 == 1 then Vector3.new(-0.5, 0.55, 0.67) else Vector3.new(0.55, 0.3, 0.78)
			placePiece(shape, piece, center + direction.Unit * (BODY_RADIUS * s * 1.02), size * fade, t * 2.2 + k * 5, 0)
		end
	end
end

local function tick()
	local now = os.clock()
	local i = 1
	while i <= #active do
		local aura = active[i]
		if not aura.model.Parent or not aura.collar.Parent then
			destroyAura(aura)
			table.remove(active, i)
		else
			if now >= aura.nextAt then
				aura.nextAt = now + aura.interval
				if not aura.gate or BombFlame.isShown(aura.gate) then
					step(aura, now)
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

-- Centre du corps de la bombe (hors col, mèche et étincelle), dans le repère local du col. Appeler AVANT BombFlame.attach.
local function bodyOffset(model: Model, collar: BasePart, scale: number): Vector3
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and (child.Name:find("^BombBody") or child.Name:find("^BombSkin") or child.Name:find("^BombShell")) then
			local half = child.Size / 2
			low = Vector3.new(math.min(low.X, child.Position.X - half.X), math.min(low.Y, child.Position.Y - half.Y), math.min(low.Z, child.Position.Z - half.Z))
			high = Vector3.new(math.max(high.X, child.Position.X + half.X), math.max(high.Y, child.Position.Y + half.Y), math.max(high.Z, child.Position.Z + half.Z))
			found = true
		end
	end
	if not found then
		return Vector3.new(0, -1.389 * scale, 0)
	end
	return collar.CFrame:PointToObjectSpace((low + high) / 2)
end

-- Pose l'aura de la bombe sur le modèle. Renvoie une fonction qui l'enlève tout de suite, ou nil (modèle sans col ni aura décrite :
-- rien n'est créé). À appeler AVANT BombFlame.attach (le centre du corps est mesuré sur les pièces du modèle).
function BombAura.attach(model: Model, modelName: string, options: Options?): (() -> ())?
	local fx = BombEffectsConfig.get(modelName)
	local auraCfg = if fx then fx.aura else nil
	local collar = model:FindFirstChild("BombCollar_Base")
	if not auraCfg or not collar or not collar:IsA("BasePart") then
		return nil
	end
	local quality: Quality = (options and options.quality) or "full"
	local scale = (options and options.scale) or 1
	local density = (options and options.density) or 1
	local count = auraCfg.count
	if quality == "game" then
		count = math.ceil(count / 2)
	end
	count = math.max(1, math.floor(count * density + 0.5))

	local aura: Aura = {
		model = model,
		collar = collar,
		offset = bodyOffset(model, collar, scale),
		scale = scale,
		startedAt = os.clock(),
		interval = 1 / HZ[quality],
		nextAt = 0,
		cfg = auraCfg,
		boltColor = rgb(auraCfg.colors[1]),
		pieces = {},
		bolts = {},
		random = Random.new(),
		gate = options and options.gate,
		all = {},
	}
	local function track(part: BasePart): BasePart
		table.insert(aura.all, part)
		return part
	end

	if auraCfg.mode == "bolts" then
		for index = 1, math.min(count, auraCfg.count) do
			local parts: { BasePart } = {}
			for segment = 1, BOLT_SEGMENTS do
				table.insert(parts, track(newPart(model, "Bolt" .. index .. "_" .. segment, aura.boltColor, Enum.Material.Neon, nil)))
			end
			table.insert(aura.bolts, { parts = parts, index = index, nextRoll = os.clock() + (index - 1) * 0.12, visibleUntil = 0 })
		end
	else
		for index = 1, count do
			local color = rgb(auraCfg.colors[(index - 1) % #auraCfg.colors + 1])
			local parts = buildShape(model, auraCfg.shape, color, "P" .. index)
			for _, part in parts do
				track(part)
			end
			table.insert(aura.pieces, {
				parts = parts,
				phase = (index - 1) / count,
				a = (index * 0.6180339) % 1,
				b = (index * 0.7548777) % 1,
				color = color,
			})
		end
	end

	step(aura, aura.startedAt)
	table.insert(active, aura)
	if not connection then
		connection = RunService.RenderStepped:Connect(tick)
	end
	return function()
		destroyAura(aura)
		aura.model = Instance.new("Model") -- sans parent : le gestionnaire la retirera au prochain passage
	end
end

return BombAura
