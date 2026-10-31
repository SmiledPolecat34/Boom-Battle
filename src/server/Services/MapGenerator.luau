--!strict
-- Génération procédurale pure (aucune Part) : produit un MapLayout reproductible à partir d'une seed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local Types = require(ReplicatedStorage.Shared.Types)

local MapGenerator = {}

local DIRECTIONS = {
	{ x = 1, y = 0 },
	{ x = -1, y = 0 },
	{ x = 0, y = 1 },
	{ x = 0, y = -1 },
}

local function newCells(size: number): { { Types.CellKind } }
	local cells = {}
	for y = 1, size do
		local row: { Types.CellKind } = {}
		for x = 1, size do
			row[x] = "EMPTY"
		end
		cells[y] = row
	end
	return cells
end

local function placePillars(cells: { { Types.CellKind } }, axis: { number })
	for _, py in axis do
		for _, px in axis do
			cells[py][px] = "PILLAR"
		end
	end
end

local function isInSafeZone(x: number, y: number, spawns: { Types.Cell }): boolean
	for _, spawn in spawns do
		if math.abs(spawn.x - x) + math.abs(spawn.y - y) <= MapConfig.SpawnSafeDistance then
			return true
		end
	end
	return false
end

local function placeCrates(cells: { { Types.CellKind } }, size: number, spawns: { Types.Cell }, rng: Random)
	for y = 1, size do
		for x = 1, size do
			if cells[y][x] == "EMPTY" and not isInSafeZone(x, y, spawns) then
				if rng:NextNumber() < MapConfig.CrateDensity then
					cells[y][x] = "CRATE"
				end
			end
		end
	end
end

-- Une map est valide si : chaque spawn a au moins MinSpawnExits cases vides voisines, et toutes les
-- cases non-pilier sont reliées entre elles (les caisses comptent comme franchissables : elles sont destructibles).
function MapGenerator.validate(cells: { { Types.CellKind } }, size: number, spawns: { Types.Cell }): boolean
	for _, spawn in spawns do
		if cells[spawn.y][spawn.x] ~= "EMPTY" then
			return false
		end
		local exits = 0
		for _, d in DIRECTIONS do
			local nx, ny = spawn.x + d.x, spawn.y + d.y
			if nx >= 1 and nx <= size and ny >= 1 and ny <= size and cells[ny][nx] == "EMPTY" then
				exits += 1
			end
		end
		if exits < MapConfig.MinSpawnExits then
			return false
		end
	end

	local total = 0
	for y = 1, size do
		for x = 1, size do
			if cells[y][x] ~= "PILLAR" then
				total += 1
			end
		end
	end

	local start = spawns[1]
	local visited: { [number]: boolean } = { [(start.y - 1) * size + start.x] = true }
	local queue: { Types.Cell } = { start }
	local head, reached = 1, 1
	while head <= #queue do
		local current = queue[head]
		head += 1
		for _, d in DIRECTIONS do
			local nx, ny = current.x + d.x, current.y + d.y
			if nx >= 1 and nx <= size and ny >= 1 and ny <= size and cells[ny][nx] ~= "PILLAR" then
				local key = (ny - 1) * size + nx
				if not visited[key] then
					visited[key] = true
					reached += 1
					table.insert(queue, { x = nx, y = ny })
				end
			end
		end
	end
	return reached == total
end

-- seed : graine demandée. layout.seed contient la graine EFFECTIVEMENT utilisée (seed + tentatives échouées),
-- qui reproduit exactement la même map si on la repasse à generate().
function MapGenerator.generate(sizeDef: MapConfig.SizeDefinition, seed: number, spawnCount: number): Types.MapLayout
	local size = sizeDef.size
	local count = math.clamp(math.floor(spawnCount), 1, 8)
	local allSpawns = MapConfig.getSpawns(size)
	local spawns: { Types.Cell } = table.move(allSpawns, 1, count, 1, {})

	for attempt = 0, MapConfig.MaxGenerationAttempts - 1 do
		local usedSeed = seed + attempt
		local cells = newCells(size)
		placePillars(cells, sizeDef.pillarAxis)
		placeCrates(cells, size, spawns, Random.new(usedSeed))
		if MapGenerator.validate(cells, size, spawns) then
			return {
				seed = usedSeed,
				sizeId = sizeDef.id,
				size = size,
				theme = MapConfig.DefaultTheme,
				cells = cells,
				spawns = spawns,
			}
		end
	end

	warn(("[MapGenerator] Aucune map valide après %d essais (seed %d) : map de secours sans caisse."):format(
		MapConfig.MaxGenerationAttempts,
		seed
	))
	local cells = newCells(size)
	placePillars(cells, sizeDef.pillarAxis)
	return {
		seed = seed,
		sizeId = sizeDef.id,
		size = size,
		theme = MapConfig.DefaultTheme,
		cells = cells,
		spawns = spawns,
	}
end

return MapGenerator
