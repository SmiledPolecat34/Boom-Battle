--!strict
-- Modèles 3D des bombes, côté CLIENT : retrouve le modèle d'un cosmétique (ReplicatedStorage.BombModels, ou
-- BombModelsMobile sur appareil tactile quand il existe), lui applique son style (BombSkinConfig : les FBX ne portent ni
-- couleur, ni matériau, ni transparence), le place au sol et l'oriente. Utilisé par le jeu (BombSkinController), la boutique,
-- l'inventaire, le HUD et le menu. Tout se REPLIE proprement : modèle absent => nil, l'appelant garde la sphère de repli.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BombAura = require(script.Parent.BombAura)
local BombFlame = require(script.Parent.BombFlame)
local BombSkinConfig = require(ReplicatedStorage.Shared.BombSkinConfig)
local MobileAssets = require(script.Parent.MobileAssets)

local STORE = "BombModels"
local STORE_LITE = "BombModelsMobile"
local ANCHOR_PIECE = "BombCollar_Base" -- présent dans les 24 modèles, posé sur l'axe de la bombe
local PREVIEW_FLAME_SCALE = 1.2 -- flamme de mèche dans l'aperçu détaillé
local PREVIEW_FLAME_SCALE_MINI = 1.5 -- flamme de mèche dans les miniatures (petits cadres : il faut qu'elle se lise)
local FLAME_HEADROOM = 1.05 -- hauteur de flamme au-dessus du bout de la mèche, pour une flamme d'échelle 1

export type Built = {
	model: Model,
	skin: BombSkinConfig.Skin,
	modelName: string,
	rel: CFrame, -- pivot du modèle relatif au point « sol sous le col » (identité d'orientation)
	height: number,
}

local BombVisuals = {}

local function templateIn(folderName: string, modelName: string): Model?
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	local model = if folder then folder:FindFirstChild(modelName) else nil
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- Version allégée sur appareil tactile (si elle existe), sinon version PC.
local function findTemplate(modelName: string): Model?
	if MobileAssets.isLite() then
		local lite = templateIn(STORE_LITE, modelName)
		if lite then
			return lite
		end
	end
	return templateIn(STORE, modelName)
end

local function materialOf(name: any): Enum.Material
	if typeof(name) == "string" then
		local ok, value = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and typeof(value) == "EnumItem" then
			return value :: any
		end
	end
	return Enum.Material.SmoothPlastic
end

-- Style des pièces + mode « purement visuel » (aucune collision, requête ni contact).
local function styleModel(model: Model, skin: BombSkinConfig.Skin)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local piece = skin.pieces[descendant.Name]
			local transparency = 0
			local material = Enum.Material.SmoothPlastic
			if piece then
				descendant.Color = Color3.fromRGB(piece[1], piece[2], piece[3])
				material = materialOf(piece[4])
				descendant.Material = material
				transparency = if typeof(piece[5]) == "number" then piece[5] else 0
				descendant.Transparency = transparency
			end
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = transparency == 0 and material ~= Enum.Material.Neon
		end
	end
end

-- Pivot relatif au point « sol sous le col » + hauteur totale ; (nil, 0) si la pièce d'ancrage est absente.
local function measure(model: Model): (CFrame?, number)
	local anchor = model:FindFirstChild(ANCHOR_PIECE)
	if not anchor or not anchor:IsA("BasePart") then
		return nil, 0
	end
	local boxCFrame, boxSize = model:GetBoundingBox()
	local base = CFrame.new(anchor.Position.X, boxCFrame.Position.Y - boxSize.Y / 2, anchor.Position.Z)
	return base:ToObjectSpace(model:GetPivot()), boxSize.Y
end

-- Un modèle (et son style) existe-t-il pour ce cosmétique ?
function BombVisuals.hasModel(cosmetic: any): boolean
	if typeof(cosmetic) ~= "table" or typeof(cosmetic.model) ~= "string" then
		return false
	end
	return BombSkinConfig.get(cosmetic.model) ~= nil and findTemplate(cosmetic.model) ~= nil
end

-- Copie stylée du modèle, ou nil (modèle / style introuvable, pièce d'ancrage absente). Le modèle n'est PAS encore parenté.
function BombVisuals.build(cosmetic: any): Built?
	if typeof(cosmetic) ~= "table" or typeof(cosmetic.model) ~= "string" then
		return nil
	end
	local skin = BombSkinConfig.get(cosmetic.model)
	local template = findTemplate(cosmetic.model)
	if not skin or not template then
		return nil
	end
	local clone = template:Clone()
	styleModel(clone, skin)
	local rel, height = measure(clone)
	if not rel then
		clone:Destroy()
		return nil
	end
	return { model = clone, skin = skin, modelName = cosmetic.model, rel = rel, height = height }
end

-- Les meshes du modèle se sont-ils chargés ? (YIELD : à appeler dans un thread dédié.) false si un mesh a échoué : un asset
-- envoyé par un compte qui n'est pas le propriétaire de l'expérience peut ne pas se charger chez les autres joueurs (voir
-- TODO.md §1). L'appelant garde alors son repli (sphère colorée / pastille) : une bombe n'est jamais invisible.
function BombVisuals.waitLoaded(model: Instance): boolean
	local failed = false
	local ok = pcall(function()
		ContentProvider:PreloadAsync({ model }, function(_contentId: string, status: Enum.AssetFetchStatus)
			if status ~= Enum.AssetFetchStatus.Success then
				failed = true
			end
		end)
	end)
	return ok and not failed
end

-- Pose le modèle : le sol sous le col en `ground`, tourné de `yaw` radians autour de Y. `offset` : décalage d'animation
-- appliqué autour du point de sol (rebond, balancement : voir BombFx.poseOffset), sans effet sur le lacet.
function BombVisuals.place(built: Built, ground: Vector3, yaw: number, offset: CFrame?)
	built.model:PivotTo(CFrame.new(ground) * (offset or CFrame.identity) * CFrame.Angles(0, yaw, 0) * built.rel)
end

-- Lacet qui tourne l'AVANT (+Z) du modèle vers la caméra, identique pour toutes les bombes (direction de la caméra,
-- pas sa position : le cadrage de l'arène est fixe). 0 si la caméra regarde à la verticale.
function BombVisuals.yawTowardCamera(camera: Camera?): number
	if not camera then
		return 0
	end
	local look = camera.CFrame.LookVector
	local x, z = -look.X, -look.Z
	if x * x + z * z < 1e-6 then
		return 0
	end
	return math.atan2(x, z)
end

-- Aperçu 3D dans un cadre d'interface (boutique, inventaire, HUD). Retourne une fonction de nettoyage, ou nil si le modèle
-- est introuvable (l'appelant garde alors sa pastille / son icône de repli). spin : rotation lente continue.
-- onFailed : appelée plus tard si les meshes ne se chargent pas (l'aperçu reste vide : l'appelant remet son repli).
-- flame : qualité de la flamme de mèche (BombFlame : "full" aperçu détaillé, "mini" cartes et HUD) ; nil = pas de flamme.
-- Les particules ne s'affichent pas dans un ViewportFrame : la flamme est faite de pièces néon animées.
function BombVisuals.mountPreview(
	parent: GuiObject,
	cosmetic: any,
	spin: boolean,
	zIndex: number?,
	onFailed: (() -> ())?,
	flame: BombFlame.Quality?
): (() -> ())?
	local ok, built = pcall(BombVisuals.build, cosmetic)
	if not ok or not built then
		return nil
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview3D"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Active = false
	viewport.Ambient = Color3.fromRGB(150, 150, 165)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1.2, -0.8)
	viewport.ZIndex = zIndex or 3
	viewport.Parent = parent
	BombVisuals.place(built, Vector3.zero, 0)
	built.model.Parent = viewport
	-- La flamme dépasse le haut du modèle : on l'agrandit dans les petits cadres (lisibilité) et on réserve sa hauteur au cadrage.
	local flameScale = if flame == "mini" or flame == "static" then PREVIEW_FLAME_SCALE_MINI else PREVIEW_FLAME_SCALE
	local totalHeight = built.height
	local stopAura: (() -> ())? = nil
	local stopFlame: (() -> ())? = nil
	if flame == "full" then
		-- Aperçu détaillé (bombe SÉLECTIONNÉE) : effet d'ambiance autour de la bombe. Posé AVANT la flamme (mesure le corps).
		stopAura = BombAura.attach(built.model, built.modelName, { quality = "full", gate = parent })
	end
	if flame then
		-- "static" (miniatures de la grille, HUD) : flamme allumée mais FIGÉE, aucune animation. Les autres qualités s'animent
		-- seulement tant que le cadre est affiché (gate).
		stopFlame = BombFlame.attach(built.model, built.modelName, { quality = flame, scale = flameScale, gate = parent }) -- la mèche s'allume à l'affichage
		totalHeight += FLAME_HEADROOM * flameScale
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local center = Vector3.new(0, totalHeight * 0.5, 0)
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, totalHeight * 0.1, totalHeight * 2.25), center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	if onFailed then
		task.spawn(function()
			if not BombVisuals.waitLoaded(built.model) and viewport.Parent ~= nil then
				onFailed()
			end
		end)
	end

	local connection: RBXScriptConnection? = nil
	if spin then
		local yaw = 0
		connection = RunService.RenderStepped:Connect(function(dt: number)
			-- Écran détruit : l'aperçu s'arrête tout seul (aucune connexion orpheline).
			if viewport.Parent == nil then
				if connection then
					connection:Disconnect()
				end
				return
			end
			if not BombFlame.isShown(parent) then
				return -- écran fermé : l'aperçu ne tourne pas
			end
			yaw += dt * 0.9
			BombVisuals.place(built, Vector3.zero, yaw)
		end)
	end
	return function()
		-- Arrêt IMMÉDIAT de tout ce qui animait cet aperçu (flamme, effets, rotation) avant de détruire le cadre.
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if stopAura then
			stopAura()
		end
		if stopFlame then
			stopFlame()
		end
		viewport:Destroy()
	end
end

-- Remesure après une mise à l'échelle (Model:ScaleTo) : le pivot relatif et la hauteur changent.
function BombVisuals.remeasure(built: Built)
	local rel, height = measure(built.model)
	if rel then
		built.rel, built.height = rel, height
	end
end

return BombVisuals
