--!strict
-- Affiche, sur CHAQUE client, le modèle 3D de la bombe posée à la place de la sphère de repli du serveur, et lui donne vie.
-- Le serveur ne fabrique qu'une sphère portant des attributs (BBBombSkin = id du cosmétique, BBGroundY = hauteur du sol,
-- BBPlacedAt = instant de pose, heure serveur) ; ici on y accroche une copie locale du modèle (version allégée sur mobile
-- s'il existe), on masque la sphère EN LOCAL (même méthode que MobileAssets), on tourne vers la caméra les dessins qui ont un
-- avant et on anime : rebond à la pose, balancement, mèche qui crépite, effet du thème, clignotement avant l'explosion
-- (BombFx, CosmicFX). Rien ne change côté serveur, qui garde seul l'autorité. Si quoi que ce soit échoue, la sphère de repli
-- reste visible : jamais de bombe invisible.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BombAura = require(script.Parent.BombAura)
local BombFlame = require(script.Parent.BombFlame)
local BombFx = require(script.Parent.BombFx)
local BombVisuals = require(script.Parent.BombVisuals)
local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local CosmicFX = require(script.Parent.CosmicFX)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MobileAssets = require(script.Parent.MobileAssets)

local ARENA_NAME = "Arena" -- identique à MapService (dossier de l'arène dans Workspace)

type Entry = {
	part: BasePart,
	built: BombVisuals.Built,
	fx: BombFx.Runtime,
	placedAt: number, -- heure serveur de la pose
	fxState: any?, -- état de CosmicFX (bombe Cosmique)
	fxStart: number,
	skip: boolean, -- appareil tactile : une image sur deux
}

local BombSkinController = {}

local entries: { [BasePart]: Entry } = {}
local failedModels: { [string]: boolean } = {} -- modèles dont les meshes n'ont pas pu se charger (réessayé à chaque manche)
local started = false

local function serverNow(): number
	local ok, now = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and typeof(now) == "number" then now else os.clock()
end

local function attach(instance: Instance)
	if not instance:IsA("BasePart") or instance.Name ~= "Bomb" or entries[instance] then
		return
	end
	local part = instance
	local skinId = part:GetAttribute("BBBombSkin")
	local groundY = part:GetAttribute("BBGroundY")
	if typeof(skinId) ~= "string" or typeof(groundY) ~= "number" then
		return
	end
	local cosmetic = CosmeticConfig.get(skinId)
	if not cosmetic or cosmetic.kind ~= "bomb" or failedModels[cosmetic.model] or not BombVisuals.hasModel(cosmetic) then
		return -- pas de modèle (ou meshes non chargés) : la sphère de repli reste affichée
	end
	local ok, built = pcall(BombVisuals.build, cosmetic)
	if not ok or not built then
		warn("[BOOM BATTLE] Modèle de bombe indisponible (" .. skinId .. ") : sphère de repli conservée.")
		return
	end

	local lite = MobileAssets.isLite()
	local placedAtAttribute = part:GetAttribute("BBPlacedAt")
	local placedAt = if typeof(placedAtAttribute) == "number" then placedAtAttribute else serverNow()
	local now = serverNow()
	local elapsed = math.max(0, now - placedAt)
	local fraction = math.clamp(elapsed / GameConfig.Bomb.FuseTime, 0, 1)
	local yaw = if built.skin.facesCamera then BombVisuals.yawTowardCamera(workspace.CurrentCamera) else 0
	BombVisuals.place(built, Vector3.new(part.Position.X, groundY, part.Position.Z), yaw, BombFx.poseOffset(elapsed, fraction))
	built.model.Parent = part.Parent

	local fx: BombFx.Runtime = BombFx.attach(built.model, cosmetic.model :: string, lite)
	-- Flamme de mèche (posée APRÈS BombFx : ses pièces ne sont pas teintées au clignotement) ; BombFx fournit déjà les
	-- étincelles et la fumée en particules, la flamme néon n'ajoute que le feu lui-même.
	BombAura.attach(built.model, cosmetic.model :: string, { quality = "game", density = if lite then 0.6 else 1 }) -- ambiance (avant la flamme)
	BombFlame.attach(built.model, cosmetic.model :: string, { quality = "game" })
	local entry: Entry = { part = part, built = built, fx = fx, placedAt = placedAt, fxState = nil, fxStart = os.clock(), skip = false }
	if built.skin.fx == "cosmic" then
		CosmicFX.addEffects(built.model, if lite then "low" else "high", false)
		entry.fxState = CosmicFX.newState(built.model)
	end
	entries[part] = entry

	-- La sphère de repli reste en place (cycle de vie géré par le serveur) et reste VISIBLE tant que les meshes ne sont pas
	-- confirmés chargés ; elle n'est masquée (en local) qu'ensuite. Échec de chargement : modèle retiré, sphère conservée.
	task.spawn(function()
		local loaded = BombVisuals.waitLoaded(built.model)
		if entries[part] ~= entry then
			return -- bombe déjà détruite
		end
		if loaded then
			part.LocalTransparencyModifier = 1
			part.CastShadow = false
		else
			warn("[BOOM BATTLE] Meshes de la bombe " .. skinId .. " non chargés : sphère de repli conservée.")
			failedModels[cosmetic.model :: string] = true
			entries[part] = nil
			built.model:Destroy()
		end
	end)

	part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			entries[part] = nil
			built.model:Destroy()
		end
	end)
end

local function update()
	if next(entries) == nil then
		return
	end
	local camera = workspace.CurrentCamera
	local cameraYaw = BombVisuals.yawTowardCamera(camera)
	local now = serverNow()
	local clock = os.clock()
	local fuseTime = GameConfig.Bomb.FuseTime
	for part, entry in entries do
		-- Appareil tactile : l'animation de pose et les couleurs sont recalculées une image sur deux.
		local lite = MobileAssets.isLite()
		entry.skip = lite and not entry.skip
		if lite and entry.skip then
			continue
		end
		local elapsed = math.max(0, now - entry.placedAt)
		local fraction = math.clamp(elapsed / fuseTime, 0, 1)
		local groundY = part:GetAttribute("BBGroundY")
		local ground = Vector3.new(part.Position.X, if typeof(groundY) == "number" then groundY else 0, part.Position.Z)
		BombVisuals.place(entry.built, ground, if entry.built.skin.facesCamera then cameraYaw else 0, BombFx.poseOffset(elapsed, fraction))
		entry.fx.update(elapsed, fraction, clock)
		if entry.fxState then
			CosmicFX.step(entry.fxState, clock - entry.fxStart)
		end
	end
end

local function watchArena(folder: Instance)
	table.clear(failedModels) -- nouvelle arène : on réessaie les modèles qui avaient échoué
	for _, child in folder:GetChildren() do
		attach(child)
	end
	folder.ChildAdded:Connect(attach)
end

function BombSkinController.start()
	if started then
		return
	end
	started = true
	local existing = workspace:FindFirstChild(ARENA_NAME)
	if existing then
		watchArena(existing)
	end
	-- L'arène est détruite et recréée à chaque manche : on se rebranche sur la nouvelle.
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == ARENA_NAME then
			watchArena(child)
		end
	end)
	RunService.Heartbeat:Connect(update)
end

-- Test uniquement : nombre de bombes habillées.
function BombSkinController.count(): number
	local n = 0
	for _ in entries do
		n += 1
	end
	return n
end

return BombSkinController
