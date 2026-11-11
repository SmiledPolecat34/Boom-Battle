--!nonstrict
-- EXPLOSION E01 « CLASSIQUE » (v2, conçue dans Blender) : rejoue l'animation Blender avec les VRAIS maillages importés (FBX).
-- Purement cosmétique : ne décide d'aucune case dangereuse (le serveur reste seul juge ; la dalle de danger est posée par EffectsController).
-- Briques composables, comme dans Blender :
--   CENTER  (28 objets) : case d'une bombe / jonction (jonction = même brique à 0,75 d'échelle),
--   SEGMENT (12 objets) : case au milieu d'un bras (le bras est le long de l'axe),
--   END     (11 objets) : bout d'un bras ou case de caisse détruite (orientée du centre vers l'extérieur).
-- Données : Shared.Pilot.E01PilotData (généré par tools/blender/explosions/e01_export_luau.py) ; maillages : ReplicatedStorage.E01Meshes
-- (51 MeshParts importés en centimètres, remis à l'échelle 0,01). Si les maillages sont absents, `available()` renvoie false et
-- ExplosionFx retombe sur l'ancien moteur : rien ne casse.
-- Ressources : pool de pièces réutilisées (aucune création après le premier usage), un seul Heartbeat actif pendant qu'une explosion joue,
-- éléments « décor » (étincelles, cailloux, halo) retirés sur appareil tactile, plafond global de pièces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ExplosionE01 = {}

local DESIGN_CELL = 4 -- taille de case (studs) pour laquelle E01 a été dessinée
local IMPORT_SCALE = 0.01 -- les FBX sont importés en centimètres
local MAX_ACTIVE_PARTS = 700
local AUTO_LITE_RESERVE = 300 -- pièces gardées en réserve (≈ 2 croix allégées) avant de basculer une explosion en version allégée
local MAX_POOL = 400
local FOLDER_NAME = "BBExplosionFx"
local JUNCTION_SCALE = 0.75
local EMPTY_VARIANT = { colors = {}, skip = {}, meshScale = {} }
local SKIPPED_WHEN_LITE = { SPARK = true, ROCK_A = true, ROCK_B = true, GLOW = true }

local function c3(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local MAT = {
	R = { c3(255, 59, 10), Enum.Material.Neon, 0 },
	O = { c3(255, 138, 0), Enum.Material.Neon, 0 },
	Y = { c3(255, 209, 26), Enum.Material.Neon, 0 },
	W = { c3(255, 243, 184), Enum.Material.Neon, 0 },
	CORE = { c3(255, 255, 255), Enum.Material.Neon, 0 },
	GLOW = { c3(255, 176, 32), Enum.Material.Neon, 0.45 },
	SMOKE = { c3(228, 207, 176), Enum.Material.SmoothPlastic, 0 },
	SMOKE_EDGE = { c3(226, 86, 27), Enum.Material.Neon, 0 },
	SPARK = { c3(255, 200, 58), Enum.Material.Neon, 0 },
	ROCK_A = { c3(205, 187, 160), Enum.Material.SmoothPlastic, 0 },
	ROCK_B = { c3(91, 70, 55), Enum.Material.SmoothPlastic, 0 },
}

-- Chaque explosion Blender a son module de DONNÉES et son dossier de MAILLAGES importés. E01 : données héritées (Shared.Pilot.E01PilotData,
-- dossier E01Meshes, matériaux ci-dessus). Les autres (E06...) : Shared.Explosions.<Nom>Data (matériaux inclus) et dossier <Nom>Meshes.
local LEGACY = { data = "E01PilotData", meshes = "E01Meshes", prefix = "M_E01_" }
local sources = {} -- clé "données|dossier" -> { data, mats, folder, templates }
local pools = {} -- nom de maillage (préfixé par la source) -> { MeshPart }
local active = {} -- explosions en cours : { elems, start, speed, maxDelay, data }
local preludes = {} -- descentes déjà lancées avant l'explosion (effets à `lead`, ex. Météore) : [fx] = true
local activeParts = 0
local connection = nil
local folder = nil

local function sourceOf(variant)
	local key = (variant and variant.data or LEGACY.data) .. "|" .. (variant and variant.meshes or LEGACY.meshes)
	local src = sources[key]
	if src == nil then
		src = false
		local dataName = variant and variant.data or LEGACY.data
		local ok, data = pcall(function()
			local shared = ReplicatedStorage.Shared
			local container = if variant and variant.data then shared.Explosions else shared.Pilot
			return require(container[dataName])
		end)
		local meshFolder = ReplicatedStorage:FindFirstChild(variant and variant.meshes or LEGACY.meshes)
		if ok and meshFolder then
			local mats = {}
			if data.mats then
				for k, m in data.mats do
					mats[k] = { m.color, if m.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic, m.transparency }
				end
			else
				mats = MAT
			end
			src = { key = key, data = data, mats = mats, folder = meshFolder, templates = {}, prefix = variant and variant.prefix or LEGACY.prefix }
			sources[key] = src
		end
	end
	return src
end

function ExplosionE01.available(variant): boolean
	return sourceOf(variant) ~= false
end

local function getFolder()
	if folder and folder.Parent then
		return folder
	end
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	folder = f
	return f
end

local function getTemplate(src, meshName)
	local t = src.templates[meshName]
	if t == nil then
		local key = if src.prefix == LEGACY.prefix then string.gsub(meshName, "^SEGMENT_E_", "SEG1_E_") else meshName
		local part = src.folder:FindFirstChild(src.prefix .. key)
		if part then
			t = { part = part, size = part.Size * IMPORT_SCALE, off = -part.PivotOffset.Position * IMPORT_SCALE }
		else
			t = false
		end
		src.templates[meshName] = t
	end
	return t
end

local function acquire(poolKey, tpl)
	local pool = pools[poolKey]
	local part = pool and table.remove(pool)
	if not part then
		part = tpl.part:Clone()
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
	return part
end

local function release(e)
	local part = e.part
	part.Parent = nil
	local pool = pools[e.poolKey]
	if not pool then
		pool = {}
		pools[e.poolKey] = pool
	end
	if #pool < MAX_POOL then
		table.insert(pool, part)
	else
		part:Destroy()
	end
	activeParts -= 1
end

local function sampleCF(f, i)
	local b = (i - 1) * 8
	return CFrame.new(f[b + 1], f[b + 2], f[b + 3], f[b + 5], f[b + 6], f[b + 7], f[b + 8]), f[b + 4]
end

local function setHidden(e, hide)
	if e.hidden ~= hide then
		e.hidden = hide
		e.part.Transparency = if hide then 1 else e.baseT
	end
end

local function apply(e, lf, n)
	if lf < 1 or lf > n then
		setHidden(e, true)
		return
	end
	local i0 = math.floor(lf)
	local a = lf - i0
	local i1 = math.min(i0 + 1, n)
	local cf0, s0 = sampleCF(e.f, i0)
	local cf1, s1 = sampleCF(e.f, i1)
	local s = s0 + (s1 - s0) * a
	if s < 0.02 then
		setHidden(e, true)
		return
	end
	local k = e.scale
	local lerped = cf0:Lerp(cf1, a)
	-- origine du maillage (repère de l'objet dans Blender) dans le monde ; le MeshPart se pose par le centre de sa boîte.
	local originCF = e.cf * CFrame.new(lerped.Position * k) * lerped.Rotation
	local part = e.part
	local ks = s * k * e.ms
	part.Size = (e.tpl.size * ks):Max(Vector3.new(0.002, 0.002, 0.002))
	part.CFrame = originCF * CFrame.new(e.tpl.off * ks)
	setHidden(e, false)
end

local function step()
	local now = os.clock()
	for i = #active, 1, -1 do
		local fx = active[i]
		local gf = (now - fx.start) * fx.fps * fx.speed + 1
		if gf > fx.frames + fx.maxDelay + 1 then
			for _, e in fx.elems do
				release(e)
			end
			preludes[fx] = nil
			table.remove(active, i)
		else
			for _, e in fx.elems do
				apply(e, gf - e.delay, fx.frames)
			end
		end
	end
	if #active == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Ajoute une brique ; retourne le nombre de pièces posées.
local function skippedWhenLite(variant, name)
	if variant.liteSkip then
		for _, token in variant.liteSkip do
			if string.find(name, token, 1, true) then
				return true
			end
		end
	end
	if variant.liteHalf then
		for _, token in variant.liteHalf do
			local index = string.match(name, token .. "(%d+)$")
			if index and tonumber(index) % 2 == 1 then
				return true
			end
		end
	end
	return false
end

local function addPiece(src, elems, pieceName, pieceCF, scale, delayFrames, lite, variant)
	local parent = getFolder()
	for _, o in src.data.pieces[pieceName].objs do
		local m = src.mats[o.mat]
		if
			m
			and not (lite and (SKIPPED_WHEN_LITE[o.mat] or skippedWhenLite(variant, o.name)))
			and not variant.skip[o.mat]
			and activeParts < MAX_ACTIVE_PARTS
		then
			local tpl = getTemplate(src, o.mesh)
			if tpl then
				local poolKey = src.key .. "|" .. o.mesh
				local part = acquire(poolKey, tpl)
				part.Color, part.Material = variant.colors[o.mat] or m[1], m[2]
				part.Transparency = 1
				part.Name = o.mesh
				part.Parent = parent
				activeParts += 1
				table.insert(elems, { part = part, poolKey = poolKey, tpl = tpl, f = o.f, cf = pieceCF, scale = scale, ms = variant.meshScale[o.mat] or 1, delay = delayFrames, baseT = m[3], hidden = true })
			end
		end
	end
end


-- Une descente (« prélude ») est lancée par ExplosionPrelude à partir de l'instant de pose de la bombe : le centre de l'effet joue ses images
-- de chute, puis l'impact tombe à l'heure prévue de l'explosion. Quand l'explosion serveur arrive, on la réclame ; si elle arrive plus tôt
-- que prévu (réaction en chaîne), l'animation saute directement à l'impact.
local function claimPrelude(variant, pos, cellSize, lead, fps): boolean
	for fx in preludes do
		local p = fx.prelude
		if not p.claimed and p.key == variant.data and (p.pos - pos).Magnitude < cellSize * 0.6 then
			p.claimed = true
			local now = os.clock()
			if now < fx.start + lead / fps - 0.04 then
				fx.start = now - lead / fps
			end
			return true
		end
	end
	return false
end

-- pieces : sortie de ExplosionLayout.classify ; delays[i] : retard de propagation (s) de la pièce i ; ground : hauteur du sol.
function ExplosionE01.play(info, pieces, delays, duration, lite, ground, variant)
	variant = variant or EMPTY_VARIANT
	local src = sourceOf(variant)
	if not src then
		return false
	end
	local data = src.data
	local gs = info.cellSize / DESIGN_CELL
	local elems = {}
	local maxDelay = 0
	-- Effet avec descente (variant.lead = images avant l'impact) : vitesse réelle, pour que la descente reste calée sur la mèche.
	local lead = variant.lead or 0
	local speed = if lead > 0 then 1 else math.clamp((data.frames / data.fps) / math.max(duration, 0.1), 0.8, 1.6)
	local nowClock = os.clock()
	-- Repli automatique en version allégée (purement visuel) quand le budget de pièces actives risque d'être dépassé : on garde une réserve
	-- pour deux explosions allégées supplémentaires, afin qu'aucune explosion simultanée ne soit tronquée.
	if not lite and variant.liteSkip then
		local heavy = 0
		for _, piece in pieces do
			local name = if piece.kind == "center" or piece.kind == "junction" then "CENTER" elseif piece.kind == "segment" then "SEGMENT" else "END"
			heavy += #data.pieces[name].objs
		end
		if activeParts + heavy + AUTO_LITE_RESERVE > MAX_ACTIVE_PARTS then
			lite = true
		end
	end
	for i, piece in pieces do
		local center = info.origin + Vector3.new((piece.cell.x - 0.5) * info.cellSize, 0, (piece.cell.y - 0.5) * info.cellSize)
		local pos = Vector3.new(center.X, ground, center.Z)
		local delayFrames = (delays[i] or 0) * data.fps
		maxDelay = math.max(maxDelay, delayFrames)
		local kind = piece.kind
		if kind == "center" then
			-- Descente déjà en cours pour cette bombe : on la « réclame » (l'impact se cale sur l'explosion serveur) au lieu de la rejouer.
			local claimed = lead > 0 and claimPrelude(variant, pos, info.cellSize, lead, data.fps)
			if not claimed then
				addPiece(src, elems, "CENTER", CFrame.new(pos), gs, delayFrames - lead, lite, variant) -- pas de descente : démarre à l'impact
			end
		elseif kind == "junction" then
			addPiece(src, elems, "CENTER", CFrame.new(pos), gs * JUNCTION_SCALE, delayFrames - lead, lite, variant)
		else
			local dir
			if piece.dir.x ~= 0 or piece.dir.y ~= 0 then
				dir = Vector3.new(piece.dir.x, 0, piece.dir.y)
			else
				dir = if piece.axis == "y" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
				if (piece.cell.x + piece.cell.y) % 2 == 0 then
					dir = -dir -- alterne le sens pour éviter l'effet « copié-collé » le long d'un bras
				end
			end
			local cf = CFrame.fromMatrix(pos, -dir, Vector3.yAxis)
			addPiece(src, elems, if kind == "segment" then "SEGMENT" else "END", cf, gs, delayFrames - (variant.pieceLead or 0), lite, variant)
		end
	end
	if #elems == 0 then
		return true
	end
	table.insert(active, { elems = elems, start = os.clock(), speed = speed, maxDelay = maxDelay, fps = data.fps, frames = data.frames })
	for _, e in elems do
		apply(e, 0, data.frames) -- cache tout avant la première image
	end
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
	return true
end


-- Lance la descente d'une bombe : worldPos = pied de la case ; secondsToImpact = temps restant avant l'explosion serveur prévue.
function ExplosionE01.prelude(info, worldPos: Vector3, secondsToImpact: number, lite: boolean, variant)
	local src = sourceOf(variant)
	local lead = variant and variant.lead
	if not src or not lead or lead <= 0 then
		return nil
	end
	local data = src.data
	local elems = {}
	addPiece(src, elems, "CENTER", CFrame.new(worldPos), info.cellSize / DESIGN_CELL, 0, lite, variant)
	if #elems == 0 then
		return nil
	end
	local fx = { elems = elems, start = os.clock() + secondsToImpact - lead / data.fps, speed = 1, maxDelay = 0, fps = data.fps, frames = data.frames,
		prelude = { pos = worldPos, key = variant.data, claimed = false } }
	table.insert(active, fx)
	preludes[fx] = true
	for _, e in elems do
		apply(e, 0, data.frames)
	end
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
	return fx
end

-- Annule une descente non réclamée (bombe disparue sans que son explosion ne soit arrivée pour ce style).
function ExplosionE01.cancelPrelude(fx)
	if fx and fx.prelude and not fx.prelude.claimed then
		local i = table.find(active, fx)
		if i then
			for _, e in fx.elems do
				release(e)
			end
			table.remove(active, i)
		end
		preludes[fx] = nil
	end
end

function ExplosionE01.stop()
	for _, fx in active do
		for _, e in fx.elems do
			release(e)
		end
	end
	table.clear(active)
	table.clear(preludes)
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

function ExplosionE01.activeCount(): number
	return activeParts
end

function ExplosionE01.poolSize(): number
	local n = 0
	for _, pool in pools do
		n += #pool
	end
	return n
end

return ExplosionE01
