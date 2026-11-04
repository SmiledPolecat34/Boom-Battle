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

-- Piliers ALÉATOIRES mais équitables : on part de la grille classique et chaque pilier d'un quart de map est déplacé
-- d'au plus MAX_SHIFT cases, puis recopié par symétrie miroir sur les deux axes (même nombre, même équité pour tous).
-- Contraintes : jamais en bordure, jamais dans la zone de sécurité d'un spawn, jamais au contact (côté) d'un autre pilier,
-- sauf la paire miroir qui se touche au centre comme dans la grille classique. La connexité est vérifiée par validate().
-- Retourne false si aucun tirage ne passe : l'appelant retombe sur la grille classique.
local PILLAR_MAX_SHIFT = 2

local function placeRandomPillars(
	cells: { { Types.CellKind } },
	size: number,
	sizeDef: MapConfig.SizeDefinition,
	rng: Random
): boolean
	local half = size // 2
	local allSpawns = MapConfig.getSpawns(size)
	local origins: { Types.Cell } = {}
	for _, py in sizeDef.pillarAxis do
		for _, px in sizeDef.pillarAxis do
			if px <= half and py <= half and size + 1 - px ~= px and size + 1 - py ~= py then
				table.insert(origins, { x = px, y = py })
			end
		end
	end
	local expected = (#sizeDef.pillarAxis) ^ 2
	if #origins * 4 ~= expected then
		return false -- axe non symétrique : on garde la grille classique
	end
	for _ = 1, 20 do
		for i = #origins, 2, -1 do
			local j = rng:NextInteger(1, i)
			origins[i], origins[j] = origins[j], origins[i]
		end
		local taken: { [number]: boolean } = {}
		local placed: { Types.Cell } = {}
		local complete = true
		for _, origin in origins do
			local options: { Types.Cell } = {}
			for y = math.max(2, origin.y - PILLAR_MAX_SHIFT), math.min(half, origin.y + PILLAR_MAX_SHIFT) do
				for x = math.max(2, origin.x - PILLAR_MAX_SHIFT), math.min(half, origin.x + PILLAR_MAX_SHIFT) do
					local xs = { x, size + 1 - x }
					local ys = { y, size + 1 - y }
					local ok = true
					for _, ox in xs do
						for _, oy in ys do
							if isInSafeZone(ox, oy, allSpawns) or taken[(oy - 1) * size + ox] then
								ok = false
							end
							for _, d in DIRECTIONS do
								local nx, ny = ox + d.x, oy + d.y
								if nx >= 1 and nx <= size and ny >= 1 and ny <= size and taken[(ny - 1) * size + nx] then
									ok = false
								end
							end
						end
					end
					if ok then
						table.insert(options, { x = x, y = y })
					end
				end
			end
			if #options == 0 then
				complete = false
				break
			end
			local pick = options[rng:NextInteger(1, #options)]
			for _, ox in { pick.x, size + 1 - pick.x } do
				for _, oy in { pick.y, size + 1 - pick.y } do
					taken[(oy - 1) * size + ox] = true
					table.insert(placed, { x = ox, y = oy })
				end
			end
		end
		if complete then
			for _, pc in placed do
				cells[pc.y][pc.x] = "PILLAR"
			end
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
-- themeId : thème visuel (ne change PAS la grille) ; inconnu ou nil => thème par défaut.
function MapGenerator.generate(
	sizeDef: MapConfig.SizeDefinition,
	seed: number,
	spawnCount: number,
	themeId: string?
): Types.MapLayout
	local theme = if themeId and MapConfig.Themes[themeId] then themeId else MapConfig.DefaultTheme
	local size = sizeDef.size
	local count = math.clamp(math.floor(spawnCount), 1, 8)
	local allSpawns = MapConfig.getSpawns(size)
	local spawns: { Types.Cell } = table.move(allSpawns, 1, count, 1, {})

	for attempt = 0, MapConfig.MaxGenerationAttempts - 1 do
		local usedSeed = seed + attempt
		local cells = newCells(size)
		-- Rng dédié aux piliers (seed + sel) : ne décale pas le tirage des caisses. Repli : grille classique.
		if not placeRandomPillars(cells, size, sizeDef, Random.new(usedSeed + 31337)) then
			placePillars(cells, sizeDef.pillarAxis)
		end
		placeCrates(cells, size, spawns, Random.new(usedSeed))
		if MapGenerator.validate(cells, size, spawns) then
			return {
				seed = usedSeed,
				sizeId = sizeDef.id,
				size = size,
				theme = theme,
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
	if not placeRandomPillars(cells, size, sizeDef, Random.new(seed + 31337)) then
		placePillars(cells, sizeDef.pillarAxis)
	end
	return {
		seed = seed,
		sizeId = sizeDef.id,
		size = size,
		theme = theme,
		cells = cells,
		spawns = spawns,
	}
end

return MapGenerator
