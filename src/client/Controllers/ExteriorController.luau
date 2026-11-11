--!strict
-- Décor extérieur de la map Classique (tours, clôtures, chemin, forêt, rochers, végétation, décorations).
-- 100 % CLIENT et purement visuel : rien n'est répliqué, aucune collision, le serveur et la logique de jeu (grille, bombes,
-- déplacements) ne sont pas touchés. La disposition (ExteriorLayouts) est fixe par taille d'arène ; les modèles viennent de
-- ReplicatedStorage.ExteriorAssets (PC) ou ExteriorAssetsMobile (appareil tactile, modèles allégés).
-- Si les modèles sont absents, le contrôleur ne fait rien (un seul avertissement).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local ExteriorLayouts = require(ReplicatedStorage.Shared.ExteriorLayouts)
local MobileAssets = require(script.Parent.MobileAssets)

local FOLDER_PC = "ExteriorAssets"
local FOLDER_MOBILE = "ExteriorAssetsMobile"
local EXTERIOR_NAME = "ClassicExterior"
local MODEL_PREFIX = "BB_EXT_"
local BATCH = 40 -- placements par image pour éviter les à-coups
local GROUND_TOP = -0.15 -- légèrement sous le sol jouable (Y = 0) : pas de scintillement

local ExteriorController = {}

local started = false
local current: Folder? = nil
local currentSize: string? = nil
local currentTheme: string? = nil
local generation = 0
local warned = false
local templates: { [string]: MeshPart } = {}

local function asMeshPart(instance: Instance): MeshPart?
	if instance:IsA("MeshPart") then
		return instance
	end
	if instance:IsA("Model") then
		local found: MeshPart? = nil
		for _, d in instance:GetDescendants() do
			if d:IsA("MeshPart") then
				if found then
					return nil -- modèle multi-pièces non géré : un modèle = un MeshPart
				end
				found = d
			end
		end
		return found
	end
	return nil
end

local function loadTemplates(): boolean
	table.clear(templates)
	local rootName = if MobileAssets.isLite() then FOLDER_MOBILE else FOLDER_PC
	local root = ReplicatedStorage:FindFirstChild(rootName)
	if not root then
		return false
	end
	for _, d in root:GetDescendants() do
		if d.Name:sub(1, #MODEL_PREFIX) == MODEL_PREFIX then
			local mesh = asMeshPart(d)
			if mesh then
				templates[d.Name:sub(#MODEL_PREFIX + 1)] = mesh
			end
		end
	end
	return next(templates) ~= nil
end

local function sizeIdFor(arena: Instance): string?
	local size = arena:GetAttribute("Size")
	if typeof(size) ~= "number" then
		return nil
	end
	for id, def in MapConfig.Sizes do
		if def.size == size then
			return id
		end
	end
	return nil
end

local function makeGround(parent: Instance, themeId: string)
	local theme = (MapConfig.Themes :: any)[themeId] or (MapConfig.Themes :: any)[MapConfig.DefaultTheme]
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.CanCollide = false
	ground.CanQuery = false
	ground.CanTouch = false
	ground.CastShadow = false
	ground.Material = theme.groundMaterial -- sol du thème de la map (herbe, sable, neige, lave, jungle)
	ground.Color = theme.groundColor
	ground.Size = Vector3.new(700, 1, 700)
	ground.Position = Vector3.new(0, GROUND_TOP - 0.5, 0)
	ground.Parent = parent
end

local function place(folder: Folder, entry: { string | number }, index: number, lite: boolean)
	local model = entry[1] :: string
	if lite and model:sub(1, 4) == "VEG_" and index % 2 == 0 then
		return -- appareil tactile : une plante sur deux
	end
	local template = templates[model]
	if not template then
		return
	end
	local part = template:Clone()
	part.Name = model
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = not (model:sub(1, 4) == "VEG_" or model:sub(1, 5) == "PATH_")
	local scale = entry[5] :: number
	local scaleX = entry[6] :: number
	part.Size = template.Size * Vector3.new(scale * scaleX, scale, scale)
	-- seule la translation du pivot compte (même convention que ModularAssets) ; le modèle est posé au sol (Y = 0)
	part.PivotOffset = CFrame.new(template.PivotOffset.Position)
	part:PivotTo(CFrame.new(entry[2] :: number, 0, entry[3] :: number) * CFrame.Angles(0, entry[4] :: number, 0))
	part.Parent = folder
end

-- La Baseplate grise de l'éditeur (dessus à Y = 0) recouvrirait le sol vert : on la masque côté client seulement.
local baseplateOriginal: number? = nil
local baseplateWanted = false
local function applyBaseplate(bp: Instance)
	if not bp:IsA("BasePart") then
		return
	end
	if baseplateWanted then
		if baseplateOriginal == nil then
			baseplateOriginal = bp.Transparency
		end
		bp.Transparency = 1
	elseif baseplateOriginal ~= nil then
		bp.Transparency = baseplateOriginal
		baseplateOriginal = nil
	end
end

local function setBaseplateHidden(hidden: boolean)
	baseplateWanted = hidden
	local bp = workspace:FindFirstChild("Baseplate")
	if bp then
		applyBaseplate(bp)
	elseif hidden then
		-- la Baseplate peut arriver après le décor (réplication) : on l'attend un peu
		task.spawn(function()
			local late = workspace:WaitForChild("Baseplate", 15)
			if late then
				applyBaseplate(late)
			end
		end)
	end
end

local function build(sizeId: string, themeId: string)
	generation += 1
	local myGeneration = generation
	if current then
		current:Destroy()
		current = nil
	end
	currentSize = sizeId
	currentTheme = themeId
	-- Décor de la map Classique uniquement : les autres thèmes gardent leur propre décor.
	if themeId ~= MapConfig.DefaultTheme then
		setBaseplateHidden(false)
		return
	end
	local layout = (ExteriorLayouts :: any)[sizeId]
	if not layout then
		return
	end
	setBaseplateHidden(true)
	local folder = Instance.new("Folder")
	folder.Name = EXTERIOR_NAME
	makeGround(folder, themeId)
	folder.Parent = workspace
	current = folder
	currentSize = sizeId
	currentTheme = themeId
	local lite = MobileAssets.isLite()
	for i, entry in layout do
		if myGeneration ~= generation then
			return -- une autre taille a été demandée entre-temps
		end
		place(folder, entry, i, lite)
		if i % BATCH == 0 then
			task.wait()
		end
	end
end

local function themeOf(arena: Instance): string
	local t = arena:GetAttribute("Theme")
	return if typeof(t) == "string" then t else MapConfig.DefaultTheme
end

local function onArena(arena: Instance)
	local id = sizeIdFor(arena)
	if not id then
		-- l'attribut Size peut arriver juste après l'instance
		arena:GetAttributeChangedSignal("Size"):Once(function()
			local late = sizeIdFor(arena)
			if late and (late ~= currentSize or themeOf(arena) ~= currentTheme) then
				task.spawn(build, late, themeOf(arena))
			end
		end)
		return
	end
	if id ~= currentSize or themeOf(arena) ~= currentTheme or current == nil or current.Parent == nil then
		task.spawn(build, id, themeOf(arena))
	end
end

function ExteriorController.start()
	if started then
		return
	end
	started = true
	if not loadTemplates() then
		if not warned then
			warned = true
			warn("[ExteriorController] modèles du décor extérieur absents (ReplicatedStorage.ExteriorAssets) : aucun décor.")
		end
		return
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Arena" then
			onArena(child)
		end
	end)
	local existing = workspace:FindFirstChild("Arena")
	if existing then
		onArena(existing)
	end
end

return ExteriorController
