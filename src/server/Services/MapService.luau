--!strict
-- Construction et destruction des Parts de l'arène à partir d'un MapLayout et d'un thème.
-- Le sol de la zone jouable a sa face supérieure à Y = 0. Le thème ne change que l'aspect : aucune règle de jeu.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local GridService = require(script.Parent.GridService)
local MapGenerator = require(script.Parent.MapGenerator)

local ARENA_NAME = "Arena"
local WALL_HEIGHT_RATIO = 1 -- hauteur des piliers / murs = 1 case
local FLOOR_ACCENT_RATIO = 0.12 -- part des cases de sol qui reçoivent la couleur d'accent
local DECOR_MARGIN_CELLS = 4 -- les décors vivent dans cette bande, autour de l'anneau de murs

export type MapInfo = {
	layout: Types.MapLayout,
	grid: GridService.GridService,
	folder: Folder,
	crates: { [number]: BasePart }, -- clé : (y - 1) * size + x
}

local MapService = {}

local current: MapInfo? = nil

local function makePart(
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Pièce décorative : aucune collision, aucune requête de rayon, jamais dans la zone de jeu.
local function makeDecorPart(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildDecor(
	kind: string,
	index: number,
	position: Vector3,
	theme: MapConfig.ThemeDefinition,
	rng: Random,
	parent: Instance
)
	local scale = rng:NextNumber(0.8, 1.35)
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local name = ("Decor_%s_%d"):format(kind, index)
	if kind == "Tree" then
		local trunkHeight = 5 * scale
		makeDecorPart(name .. "_Trunk", Enum.PartType.Cylinder, Vector3.new(trunkHeight, 1.4, 1.4),
			CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(110, 76, 46), Enum.Material.Wood, parent)
		makeDecorPart(name .. "_Leaves", Enum.PartType.Ball, Vector3.new(6, 6, 6) * scale,
			CFrame.new(position + Vector3.new(0, trunkHeight + 2 * scale, 0)),
			theme.decorPrimary, Enum.Material.Grass, parent)
	elseif kind == "Cactus" then
		local height = 6 * scale
		makeDecorPart(name, Enum.PartType.Cylinder, Vector3.new(height, 1.8, 1.8),
			CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			theme.decorPrimary, Enum.Material.Grass, parent)
		makeDecorPart(name .. "_Arm", Enum.PartType.Cylinder, Vector3.new(2.6 * scale, 1.1, 1.1),
			CFrame.new(position + Vector3.new(1.6, height * 0.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			theme.decorPrimary, Enum.Material.Grass, parent)
	elseif kind == "Spike" then
		local height = 7 * scale
		makeDecorPart(name, Enum.PartType.Block, Vector3.new(2.2 * scale, height, 2.2 * scale),
			CFrame.new(position + Vector3.new(0, height / 2, 0)) * yaw * CFrame.Angles(0, 0, rng:NextNumber(-0.18, 0.18)),
			theme.decorSecondary, if theme.groundMaterial == Enum.Material.Neon then Enum.Material.Basalt else Enum.Material.Ice, parent)
	else -- "Rock"
		makeDecorPart(name, Enum.PartType.Ball, Vector3.new(4.5, 3, 4) * scale,
			CFrame.new(position + Vector3.new(0, 1 * scale, 0)) * yaw,
			theme.decorSecondary, Enum.Material.Slate, parent)
	end
end

local function applyLighting(theme: MapConfig.ThemeDefinition)
	local l = theme.lighting
	Lighting.ClockTime = l.clockTime
	Lighting.Ambient = l.ambient
	Lighting.OutdoorAmbient = l.outdoorAmbient
	Lighting.Brightness = l.brightness
end

function MapService.destroy()
	if current then
		current.folder:Destroy()
		current = nil
	end
	-- Supprime aussi une arène résiduelle (ex. rechargement de script en Studio).
	local leftover = workspace:FindFirstChild(ARENA_NAME)
	if leftover then
		leftover:Destroy()
	end
end

function MapService.getCurrent(): MapInfo?
	return current
end

-- Détruit l'ancienne arène, génère une nouvelle map et construit ses Parts.
-- themeId : thème visuel ; nil ou inconnu => thème par défaut.
function MapService.generateAndBuild(
	sizeDef: MapConfig.SizeDefinition,
	seed: number,
	spawnCount: number,
	themeId: string?
): MapInfo
	MapService.destroy()

	local layout = MapGenerator.generate(sizeDef, seed, spawnCount, themeId)
	local cellSize = MapConfig.CellSize
	local size = layout.size
	local theme = MapConfig.Themes[layout.theme]
	local origin = Vector3.new(-size * cellSize / 2, 0, -size * cellSize / 2)
	local grid = GridService.new(layout, cellSize, origin)
	-- Tout l'aspect (taches de sol, décors) dépend de la seed : une map reproduit exactement son rendu.
	local rng = Random.new(layout.seed + 104729)

	local folder = Instance.new("Folder")
	folder.Name = ARENA_NAME
	folder:SetAttribute("Seed", layout.seed)
	folder:SetAttribute("Size", size)
	folder:SetAttribute("Theme", layout.theme)

	local wallHeight = cellSize * WALL_HEIGHT_RATIO
	local crates: { [number]: BasePart } = {}

	applyLighting(theme)

	-- Sol extérieur : masque la baseplate de l'éditeur et donne l'ambiance (lave, neige, sable, ...).
	local groundSize = (size + 2 * DECOR_MARGIN_CELLS + 8) * cellSize
	makePart("Ground", Vector3.new(groundSize, 1, groundSize),
		Vector3.new(0, -1.6, 0), theme.groundColor, theme.groundMaterial, folder)

	for y = 1, size do
		for x = 1, size do
			local cell = { x = x, y = y }
			local floorColor = if (x + y) % 2 == 0 then theme.floorColorA else theme.floorColorB
			if rng:NextNumber() < FLOOR_ACCENT_RATIO then
				floorColor = theme.floorAccentColor
			end
			local floor = makePart(
				("Floor_%d_%d"):format(x, y),
				Vector3.new(cellSize, 1, cellSize),
				grid:cellToWorld(cell, -0.5),
				floorColor,
				theme.floorMaterial,
				folder
			)
			floor:SetAttribute("CellX", x)
			floor:SetAttribute("CellY", y)

			local kind = layout.cells[y][x]
			if kind == "PILLAR" then
				local pillar = makePart(
					("Pillar_%d_%d"):format(x, y),
					Vector3.new(cellSize, wallHeight, cellSize),
					grid:cellToWorld(cell, wallHeight / 2),
					theme.pillarColor,
					theme.pillarMaterial,
					folder
				)
				pillar:SetAttribute("CellX", x)
				pillar:SetAttribute("CellY", y)
				-- Chapeau plus clair : lisible depuis la caméra de dessus. Enfant du pilier : détruit avec lui.
				local cap = makePart("Cap", Vector3.new(cellSize * 0.8, 0.3, cellSize * 0.8),
					grid:cellToWorld(cell, wallHeight + 0.15), theme.pillarCapColor, theme.pillarMaterial, pillar)
				cap.CanCollide = false
				cap.CanQuery = false
			elseif kind == "CRATE" then
				local body = cellSize * 0.9
				local crate = makePart(
					("Crate_%d_%d"):format(x, y),
					Vector3.new(body, wallHeight, body),
					grid:cellToWorld(cell, wallHeight / 2),
					theme.crateColor,
					theme.crateMaterial,
					folder
				)
				crate:SetAttribute("CellX", x)
				crate:SetAttribute("CellY", y)
				-- Couvercle : même principe ; détruit avec la caisse quand elle explose.
				local lid = makePart("Lid", Vector3.new(body * 0.78, 0.3, body * 0.78),
					grid:cellToWorld(cell, wallHeight + 0.15), theme.crateLidColor, theme.crateMaterial, crate)
				lid.CanCollide = false
				lid.CanQuery = false
				crates[(y - 1) * size + x] = crate
			end
		end
	end

	-- Anneau de murs extérieurs : cellules 0 et size + 1 sur chaque axe.
	for y = 0, size + 1 do
		for x = 0, size + 1 do
			if x == 0 or y == 0 or x == size + 1 or y == size + 1 then
				makePart(
					("Border_%d_%d"):format(x, y),
					Vector3.new(cellSize, wallHeight, cellSize),
					grid:cellToWorld({ x = x, y = y }, wallHeight / 2),
					theme.borderColor,
					theme.borderMaterial,
					folder
				)
			end
		end
	end

	-- Décors : uniquement dans la bande extérieure à l'anneau de murs (jamais sur la zone de jeu).
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = folder
	local decorCount = math.clamp(size * 3, 30, 72)
	local placed = 0
	local attempts = 0
	while placed < decorCount and attempts < decorCount * 10 do
		attempts += 1
		local cx = rng:NextInteger(-DECOR_MARGIN_CELLS, size + 1 + DECOR_MARGIN_CELLS)
		local cy = rng:NextInteger(-DECOR_MARGIN_CELLS, size + 1 + DECOR_MARGIN_CELLS)
		-- L'anneau occupe les cellules 0..size+1 : on reste strictement dehors, avec une case de dégagement.
		if cx < -1 or cx > size + 2 or cy < -1 or cy > size + 2 then
			placed += 1
			local position = grid:cellToWorld({ x = cx, y = cy }, 0)
				+ Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2))
			local kind = theme.decorKinds[rng:NextInteger(1, #theme.decorKinds)]
			buildDecor(kind, placed, position, theme, rng, decorFolder)
		end
	end

	folder.Parent = workspace

	local info: MapInfo = { layout = layout, grid = grid, folder = folder, crates = crates }
	current = info
	return info
end

return MapService
