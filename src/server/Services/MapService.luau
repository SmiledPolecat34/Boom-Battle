--!strict
-- Construction et destruction des Parts de l'arène à partir d'un MapLayout.
-- Le sol de la zone jouable a sa face supérieure à Y = 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local GridService = require(script.Parent.GridService)
local MapGenerator = require(script.Parent.MapGenerator)

local ARENA_NAME = "Arena"
local WALL_HEIGHT_RATIO = 1 -- hauteur des piliers / murs = 1 case

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
function MapService.generateAndBuild(sizeDef: MapConfig.SizeDefinition, seed: number, spawnCount: number): MapInfo
	MapService.destroy()

	local layout = MapGenerator.generate(sizeDef, seed, spawnCount)
	local cellSize = MapConfig.CellSize
	local size = layout.size
	local theme = MapConfig.Themes[layout.theme]
	local origin = Vector3.new(-size * cellSize / 2, 0, -size * cellSize / 2)
	local grid = GridService.new(layout, cellSize, origin)

	local folder = Instance.new("Folder")
	folder.Name = ARENA_NAME
	folder:SetAttribute("Seed", layout.seed)
	folder:SetAttribute("Size", size)

	local wallHeight = cellSize * WALL_HEIGHT_RATIO
	local crates: { [number]: BasePart } = {}

	for y = 1, size do
		for x = 1, size do
			local cell = { x = x, y = y }
			local floorColor = if (x + y) % 2 == 0 then theme.FloorColorA else theme.FloorColorB
			local floorCenter = grid:cellToWorld(cell, -0.5)
			local floor = makePart(
				("Floor_%d_%d"):format(x, y),
				Vector3.new(cellSize, 1, cellSize),
				floorCenter,
				floorColor,
				theme.Material,
				folder
			)
			floor:SetAttribute("CellX", x)
			floor:SetAttribute("CellY", y)

			local kind = layout.cells[y][x]
			if kind == "PILLAR" or kind == "CRATE" then
				local isCrate = kind == "CRATE"
				local blockSize = if isCrate then cellSize * 0.9 else cellSize
				local part = makePart(
					(if isCrate then "Crate_%d_%d" else "Pillar_%d_%d"):format(x, y),
					Vector3.new(blockSize, wallHeight, blockSize),
					grid:cellToWorld(cell, wallHeight / 2),
					if isCrate then theme.CrateColor else theme.PillarColor,
					theme.Material,
					folder
				)
				part:SetAttribute("CellX", x)
				part:SetAttribute("CellY", y)
				if isCrate then
					crates[(y - 1) * size + x] = part
				end
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
					theme.BorderColor,
					theme.Material,
					folder
				)
			end
		end
	end

	folder.Parent = workspace

	local info: MapInfo = { layout = layout, grid = grid, folder = folder, crates = crates }
	current = info
	return info
end

return MapService
