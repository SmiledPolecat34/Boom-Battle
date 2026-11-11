--!strict
-- MOTEUR VISUEL MODULAIRE DES EXPLOSIONS (client, purement cosmétique). À partir des cases touchées décidées par le serveur, pose sur
-- chaque case le module qui convient (ExplosionLayout : Centre, Jonction, Segment, Bout, Impact) :
--   • gerbes de flamme (fuseaux néon) qui jaillissent puis se rétractent,
--   • cœur lumineux et onde de choc au sol (centre),
--   • volutes de fumée / poussière basses qui se dissipent vite,
--   • éclats de roche ou de bois projetés (centre, impact),
--   • étincelles (ParticleEmitter, un seul tir par module).
-- Chaque style (ExplosionStyles) est une PALETTE + une RECETTE : le moteur est le même pour tous.
-- Règles de lisibilité : tout reste dans la case (gerbes < 1,2 case), rien ne masque durablement un joueur, la fumée est basse et
-- translucide, tout disparaît en 1,1 x la durée des flammes au plus. La dalle de danger (EffectsController) reste la référence.
-- Ressources : tout vient de POOLS plafonnés (aucune création / destruction par explosion) ; un seul gestionnaire d'animation,
-- actif uniquement pendant qu'une explosion joue ; qualité réduite sur appareil tactile (moitié des éléments).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ExplosionLayout = require(ReplicatedStorage.Shared.ExplosionLayout)
local ExplosionStyles = require(ReplicatedStorage.Shared.ExplosionStyles)
local MobileAssets = require(script.Parent.MobileAssets)
local ExplosionE01 = require(script.Parent.ExplosionE01)

local TAU = math.pi * 2
local GRAVITY = 32
local MAX_POOL = 220
local MAX_ACTIVE_ITEMS = 700 -- garde-fou : au-delà, les éléments décoratifs sont ignorés (les dalles de danger, elles, restent)
local FOLDER_NAME = "BBExplosionFx"
local SMOKE_LIFE_FACTOR = 1.1

export type Info = { origin: Vector3, cellSize: number }

type Item = {
	kind: string, -- tile (non utilisé ici), spike, core, ring, smoke, debris, sparks
	part: BasePart,
	pool: string,
	pos: Vector3, -- position de départ
	dir: Vector3, -- gerbe : direction ; fumée : dérive ; débris : vitesse
	spin: Vector3,
	a: number, -- taille / longueur
	b: number, -- épaisseur / taille finale
	color: Color3,
	delay: number,
	life: number,
	startedAt: number,
	count: number, -- étincelles
	ground: number,
	alpha: number, -- transparence de départ (halo translucide)
}

local ExplosionFx = {}

local pools: { [string]: { BasePart } } = { ball = {}, spindle = {}, block = {}, ring = {}, emitter = {} }
local items: { Item } = {}
local connection: RBXScriptConnection? = nil
local folder: Folder? = nil

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	folder = f
	return f
end

local function baseProps(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function create(pool: string): BasePart
	local part = Instance.new("Part")
	baseProps(part)
	if pool == "ball" then
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
	elseif pool == "spindle" then
		part.Material = Enum.Material.Neon
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	elseif pool == "block" then
		part.Material = Enum.Material.Slate
	elseif pool == "ring" then
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.Neon
	else -- emitter : support invisible d'un ParticleEmitter
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Spark"
		emitter.Enabled = false
		emitter.Lifetime = NumberRange.new(0.3, 0.55)
		emitter.Speed = NumberRange.new(14, 26)
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.Acceleration = Vector3.new(0, -38, 0)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Rate = 0
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.38), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		emitter.Parent = part
	end
	return part
end

local function acquire(pool: string): BasePart
	local part = table.remove(pools[pool])
	if not part then
		part = create(pool)
	end
	part.Transparency = if pool == "emitter" then 1 else 0
	part.Parent = getFolder()
	return part
end

local function release(pool: string, part: BasePart)
	part.Parent = nil
	local list = pools[pool]
	if #list < MAX_POOL then
		table.insert(list, part)
	else
		part:Destroy()
	end
end

local function easeOut(p: number): number
	return 1 - (1 - p) ^ 3
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Une pièce à partir de coordonnées de case.
local function spiral(index: number, count: number): number
	return (index - 1) * TAU / math.max(count, 1) + (index * 0.37)
end

local function orientAlong(position: Vector3, direction: Vector3): CFrame
	local up = if math.abs(direction.Y) > 0.97 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + direction, up) * CFrame.Angles(-math.pi / 2, 0, 0)
end

local function push(item: Item)
	if #items < MAX_ACTIVE_ITEMS then
		table.insert(items, item)
	else
		release(item.pool, item.part)
	end
end

local function update(now: number)
	local i = 1
	while i <= #items do
		local item = items[i]
		local elapsed = now - item.startedAt - item.delay
		local part = item.part
		if elapsed < 0 then
			part.Transparency = 1
			i += 1
		else
			local p = elapsed / item.life
			if p >= 1 then
				release(item.pool, part)
				items[i] = items[#items]
				items[#items] = nil
			else
				local kind = item.kind
				if kind == "spike" then
					local grow = if p < 0.22 then easeOut(p / 0.22) elseif p < 0.55 then 1 else 1 - ((p - 0.55) / 0.45) ^ 2
					local length = item.a * grow
					local thick = item.b * (0.5 + 0.5 * grow)
					part.Size = Vector3.new(thick, math.max(length, 0.02), thick)
					part.CFrame = orientAlong(item.pos + item.dir * (length / 2), item.dir)
					part.Color = item.color
					part.Transparency = math.max(0, (p - 0.7) / 0.3) * 0.9
				elseif kind == "core" then
					local scale = if p < 0.2 then easeOut(p / 0.2) else (1 - (p - 0.2) / 0.8) ^ 1.4
					local size = math.max(item.a * scale, 0.02)
					part.Size = Vector3.new(size, size, size)
					part.Position = item.pos
					part.Transparency = item.alpha + (1 - item.alpha) * p ^ 3 * 0.7
				elseif kind == "ring" then
					local d = item.a * easeOut(math.min(p * 1.6, 1))
					part.Size = Vector3.new(0.1, math.max(d, 0.02), math.max(d, 0.02))
					part.CFrame = CFrame.new(item.pos) * CFrame.Angles(0, 0, math.pi / 2)
					part.Transparency = 0.1 + 0.9 * p
				elseif kind == "smoke" then
					local e = easeOut(p)
					local size = lerp(item.a, item.b, e)
					part.Size = Vector3.new(size, size, size)
					part.Position = item.pos + item.dir * e
					part.Transparency = item.alpha + (1 - item.alpha) * (0.3 + 0.7 * p ^ 1.2)
				elseif kind == "debris" then
					local t = elapsed
					local position = item.pos + item.dir * t + Vector3.new(0, -0.5 * GRAVITY * t * t, 0)
					if position.Y < item.ground then
						position = Vector3.new(position.X, item.ground, position.Z)
					end
					part.CFrame = CFrame.new(position) * CFrame.Angles(item.spin.X * t, item.spin.Y * t, item.spin.Z * t)
					part.Transparency = math.max(0, (p - 0.65) / 0.35)
				elseif kind == "sparks" then
					if item.count > 0 then
						local emitter = part:FindFirstChild("Spark") :: ParticleEmitter?
						if emitter then
							emitter.Color = ColorSequence.new(item.color, item.color:Lerp(Color3.fromRGB(255, 80, 20), 0.6))
							emitter:Emit(item.count)
						end
						item.count = 0
					end
				end
				i += 1
			end
		end
	end
	if #items == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureRunning()
	if not connection then
		connection = RunService.Heartbeat:Connect(function()
			update(os.clock())
		end)
	end
end

local function add(
	kind: string,
	pool: string,
	startedAt: number,
	delay: number,
	life: number,
	position: Vector3,
	color: Color3,
	ground: number
): Item
	local part = acquire(pool)
	local item: Item = {
		kind = kind,
		part = part,
		pool = pool,
		pos = position,
		dir = Vector3.zero,
		spin = Vector3.zero,
		a = 1,
		b = 1,
		color = color,
		delay = delay,
		life = math.max(life, 0.05),
		startedAt = startedAt,
		count = 0,
		ground = ground,
		alpha = 0,
	}
	part.Color = color
	return item
end

-- Nombre d'éléments pour la qualité courante (moitié sur appareil tactile, au moins 1 s'il y en avait).
local function scaled(count: number, lite: boolean): number
	if count <= 0 then
		return 0
	end
	return if lite then math.max(1, math.floor(count / 2 + 0.5)) else count
end

-- Construit tous les éléments d'un module (une case).
local function buildModule(
	piece: ExplosionLayout.Piece,
	center: Vector3,
	cell: number,
	style: ExplosionStyles.Style,
	startedAt: number,
	delay: number,
	duration: number,
	lite: boolean,
	random: Random,
	ground: number
)
	local palette, recipe = style.palette, style.recipe
	local kind = piece.kind
	local life = duration * 0.95 - delay
	local base = Vector3.new(center.X, ground, center.Z)
	local function dirOf(azimuth: number, elevation: number): Vector3
		return Vector3.new(math.cos(azimuth) * math.cos(elevation), math.sin(elevation), math.sin(azimuth) * math.cos(elevation))
	end

	-- Cœur lumineux
	local coreSize = if kind == "center" then 0.7 elseif kind == "junction" then 0.46 elseif kind == "impact" then 0.42 elseif kind == "end" then 0.34 else 0.22
	local core = add("core", "ball", startedAt, delay, life, base + Vector3.new(0, cell * 0.18, 0), palette.core, ground)
	core.a = coreSize * cell
	push(core)
	-- Boule de feu translucide autour du cœur (centre, jonction, impact) : donne le volume de la gerbe.
	if kind == "center" or kind == "junction" or kind == "impact" then
		local halo = add("core", "ball", startedAt, delay, life, base + Vector3.new(0, cell * 0.2, 0), palette.mid, ground)
		halo.a = coreSize * cell * 1.75
		halo.alpha = 0.55
		push(halo)
	end

	-- Onde de choc au sol (centre)
	if kind == "center" and recipe.ring then
		local ring = add("ring", "ring", startedAt, delay, life, base + Vector3.new(0, 0.12, 0), palette.mid:Lerp(palette.core, 0.5), ground)
		ring.a = cell * 1.12
		push(ring)
	end

	-- Gerbes de flamme
	local spikes = scaled(recipe.spikes[kind] or 0, lite)
	for n = 1, spikes do
		local direction: Vector3
		local length: number
		if kind == "segment" then
			local sign = if n % 2 == 1 then 1 else -1
			local axisDir = if piece.axis == "y" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
			direction = (axisDir * sign * 0.55 + Vector3.yAxis * 0.85).Unit
			length = cell * random:NextNumber(0.46, 0.6)
		elseif kind == "end" or kind == "impact" then
			local forward = Vector3.new(piece.dir.x, 0, piece.dir.y)
			local spread = (n - (spikes + 1) / 2) * 0.55
			local side = Vector3.new(-forward.Z, 0, forward.X)
			direction = (forward * 0.7 + side * spread * 0.45 + Vector3.yAxis * 0.75).Unit
			length = cell * random:NextNumber(0.55, 0.78)
		else
			-- gerbes surtout dressées vers le haut (comme la référence), quelques-unes plus basses
			local elevation = (({ 1.38, 1.1, 0.8, 1.28, 0.62, 1.45, 0.95, 1.2, 0.72 })[(n - 1) % 9 + 1]) :: number
			direction = dirOf(spiral(n, spikes), elevation)
			length = cell * (if elevation > 1.05 then random:NextNumber(1.05, 1.4) else random:NextNumber(0.75, 0.95))
		end
		local color = if n % 3 == 0 then palette.core elseif n % 3 == 1 then palette.mid else palette.edge:Lerp(palette.mid, 0.4)
		local spike = add("spike", "spindle", startedAt, delay + random:NextNumber(0, 0.03), life, base + Vector3.new(0, 0.1, 0), color, ground)
		spike.dir = direction
		spike.a = length
		spike.b = cell * (if kind == "center" then 0.22 elseif kind == "junction" then 0.17 else 0.14)
		push(spike)
	end

	-- Fumée / poussière basse, très translucide
	local puffs = scaled(recipe.smoke[kind] or 0, lite)
	for n = 1, puffs do
		local angle = spiral(n, puffs)
		local radius = cell * (if kind == "center" then 0.22 else 0.14)
		local start = base + Vector3.new(math.cos(angle) * radius, 0.35, math.sin(angle) * radius)
		local puff = add("smoke", "ball", startedAt, delay + random:NextNumber(0, 0.04), life * SMOKE_LIFE_FACTOR, start, palette.smoke, ground)
		puff.part.Material = Enum.Material.SmoothPlastic
		puff.alpha = 0.15
		puff.dir = Vector3.new(math.cos(angle) * cell * 0.2, cell * 0.22, math.sin(angle) * cell * 0.2)
		puff.a = cell * 0.18
		puff.b = cell * (if kind == "center" then 0.46 else 0.34)
		push(puff)
	end

	-- Éclats projetés
	local chunks = scaled(recipe.debris[kind] or 0, lite)
	for n = 1, chunks do
		local angle = spiral(n, chunks) + random:NextNumber(-0.3, 0.3)
		local speed = random:NextNumber(3, 6.5)
		local size = cell * random:NextNumber(0.07, 0.12)
		local chunk = add("debris", "block", startedAt, delay, life, base + Vector3.new(0, cell * 0.2, 0), if kind == "impact" then Color3.fromRGB(150, 102, 58) else palette.debris, ground)
		chunk.part.Material = if kind == "impact" then Enum.Material.Wood else Enum.Material.Slate
		chunk.part.Size = Vector3.new(size, size * 0.8, size * 0.9)
		chunk.dir = Vector3.new(math.cos(angle) * speed, random:NextNumber(6.5, 10), math.sin(angle) * speed)
		chunk.spin = Vector3.new(random:NextNumber(-9, 9), random:NextNumber(-9, 9), random:NextNumber(-9, 9))
		chunk.ground = ground + size * 0.4
		push(chunk)
	end

	-- Étincelles (un tir)
	local sparkCount = scaled(recipe.sparks[kind] or 0, lite)
	if sparkCount > 0 then
		local sparks = add("sparks", "emitter", startedAt, delay, math.max(life, 0.7), base + Vector3.new(0, cell * 0.2, 0), palette.mid:Lerp(palette.core, 0.4), ground)
		sparks.part.Position = sparks.pos
		sparks.count = sparkCount
		push(sparks)
	end
end

-- Joue une explosion. info : origine de la grille et taille de case ; payload : cases décidées par le serveur (+ origines, caisses,
-- identifiant d'effet, couleur). Ne lève jamais d'erreur (tout est protégé) : au pire, seule la dalle de danger de
-- EffectsController reste affichée.
function ExplosionFx.play(info: Info, payload: any)
	if typeof(payload) ~= "table" or typeof(payload.cells) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		local duration = if typeof(payload.duration) == "number" then math.clamp(payload.duration, 0.1, 2) else 0.5
		local style = ExplosionStyles.get(payload.style, payload.color)
		local pieces = ExplosionLayout.classify(payload.cells, payload.origins, payload.crates)
		if #pieces == 0 then
			return
		end
		local lite = MobileAssets.isLite()
		local cell = info.cellSize
		local ground = info.origin.Y
		local startedAt = os.clock()
		local random = Random.new()
		-- Distance (en cases) de chaque module au centre le plus proche : l'onde se propage du centre vers les bouts.
		local centers: { { x: number, y: number } } = {}
		for _, piece in pieces do
			if piece.kind == "center" then
				table.insert(centers, piece.cell)
			end
		end
		local useE01 = style.e01 ~= nil and ExplosionE01.available(style.e01)
		local e01Delays: { number } = {}
		for index, piece in pieces do
			local distance = 0
			if #centers > 0 and piece.kind ~= "center" then
				distance = math.huge
				for _, c in centers do
					distance = math.min(distance, math.abs(piece.cell.x - c.x) + math.abs(piece.cell.y - c.y))
				end
			end
			local delay = math.min(distance * 0.035, duration * 0.3)
			local center = info.origin + Vector3.new((piece.cell.x - 0.5) * cell, 0, (piece.cell.y - 0.5) * cell)
			if useE01 then
				e01Delays[index] = delay
			else
				buildModule(piece, center, cell, style, startedAt, delay, duration, lite, random, ground + 0.25)
			end
		end
		if useE01 then
			-- E01 Classique v2 (Blender) : maillages importés animés ; remplace l'ancien décor (la dalle de danger reste posée par EffectsController).
			ExplosionE01.play(info, pieces, e01Delays, duration, lite, ground + 0.25, style.e01)
			return
		end
		ensureRunning()
	end)
	if not ok then
		warn("[BOOM BATTLE] Visuel d'explosion ignoré : " .. tostring(err))
	end
end

-- Arrête tout et rend les ressources (changement de manche, redémarrage).
function ExplosionFx.stop()
	ExplosionE01.stop()
	for _, item in items do
		release(item.pool, item.part)
	end
	table.clear(items)
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Test uniquement : éléments animés en cours et taille des pools.
function ExplosionFx.activeCount(): number
	return #items + ExplosionE01.activeCount()
end

function ExplosionFx.poolSizes(): { [string]: number }
	local sizes: { [string]: number } = {}
	for name, list in pools do
		sizes[name] = #list
	end
	sizes.e01 = ExplosionE01.poolSize()
	return sizes
end

return ExplosionFx
