--!nocheck
-- Tests de la Phase 1 (logique pure : génération de map et recherche de chemin).
-- À EXÉCUTER DANS ROBLOX STUDIO : après synchronisation Rojo, coller ce fichier dans la barre de commande
-- (mode Edit) et lire Output. Aucune Part n'est créée.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local MapGenerator = require(ServerScriptService.Server.Services.MapGenerator)
local GridService = require(ServerScriptService.Server.Services.GridService)

local passed, failed = 0, 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		warn(("ÉCHEC : %s %s"):format(name, detail or ""))
	end
end

local function layoutsEqual(a, b): boolean
	for y = 1, a.size do
		for x = 1, a.size do
			if a.cells[y][x] ~= b.cells[y][x] then
				return false
			end
		end
	end
	return true
end

-- Génération ------------------------------------------------------------------------------------------------
for sizeId, sizeDef in MapConfig.Sizes do
	local invalid = 0
	for seed = 1, 50 do
		local layout = MapGenerator.generate(sizeDef, seed, 8)
		if not MapGenerator.validate(layout.cells, layout.size, layout.spawns) then
			invalid += 1
		end
	end
	check(("%s : 50 maps valides"):format(sizeId), invalid == 0, ("(%d invalides)"):format(invalid))

	local a = MapGenerator.generate(sizeDef, 1234, 8)
	local b = MapGenerator.generate(sizeDef, 1234, 8)
	check(("%s : même seed => même map"):format(sizeId), layoutsEqual(a, b))
	-- La seed effective permet de rejouer exactement la map.
	local c = MapGenerator.generate(sizeDef, a.seed, 8)
	check(("%s : seed effective reproductible"):format(sizeId), layoutsEqual(a, c))

	local pillars, crates = 0, 0
	for y = 1, a.size do
		for x = 1, a.size do
			if a.cells[y][x] == "PILLAR" then
				pillars += 1
			elseif a.cells[y][x] == "CRATE" then
				crates += 1
			end
		end
	end
	check(("%s : nombre de piliers attendu"):format(sizeId), pillars == #sizeDef.pillarAxis ^ 2)
	check(("%s : des caisses sont générées"):format(sizeId), crates > 0)

	-- Aucune caisse dans les zones de spawn.
	local crateInSafeZone = false
	for _, spawn in a.spawns do
		for y = 1, a.size do
			for x = 1, a.size do
				local d = math.abs(spawn.x - x) + math.abs(spawn.y - y)
				if d <= MapConfig.SpawnSafeDistance and a.cells[y][x] == "CRATE" then
					crateInSafeZone = true
				end
			end
		end
	end
	check(("%s : zones de spawn sans caisse"):format(sizeId), not crateInSafeZone)

	-- Symétrie des piliers : (x, y) <=> (size + 1 - x, y).
	local symmetric = true
	for y = 1, a.size do
		for x = 1, a.size do
			if (a.cells[y][x] == "PILLAR") ~= (a.cells[y][a.size + 1 - x] == "PILLAR") then
				symmetric = false
			end
		end
	end
	check(("%s : piliers symétriques"):format(sizeId), symmetric)
end

-- Chemin ----------------------------------------------------------------------------------------------------
local medium = MapConfig.Sizes.Medium
local layout = MapGenerator.generate(medium, 99, 2)
local grid = GridService.new(layout, MapConfig.CellSize, Vector3.new(0, 0, 0))

-- On vide la map pour les tests de chemin (seuls les piliers restent).
for y = 1, layout.size do
	for x = 1, layout.size do
		if layout.cells[y][x] == "CRATE" then
			layout.cells[y][x] = "EMPTY"
		end
	end
end

local path = grid:findPath({ x = 1, y = 1 }, { x = 1, y = 1 })
check("chemin : départ == cible => {}", path ~= nil and #path == 0)

path = grid:findPath({ x = 1, y = 1 }, { x = 5, y = 1 })
check("chemin : ligne libre de 4 cases", path ~= nil and #path == 4)

path = grid:findPath({ x = 1, y = 1 }, { x = 3, y = 3 }) -- (3, 3) est un pilier
check("chemin : cible = pilier => refus", path == nil)

path = grid:findPath({ x = 1, y = 1 }, { x = 0, y = 1 })
check("chemin : cible hors grille => refus", path == nil)

path = grid:findPath({ x = 1, y = 1 }, { x = 16, y = 16 })
check("chemin : coin à coin atteignable", path ~= nil and #path == 30, path and tostring(#path) or "nil")

local noStep = true
if path then
	local previous = { x = 1, y = 1 }
	for _, cell in path do
		if math.abs(cell.x - previous.x) + math.abs(cell.y - previous.y) ~= 1 or not grid:isWalkable(cell.x, cell.y) then
			noStep = false
		end
		previous = cell
	end
end
check("chemin : pas orthogonaux et uniquement sur cases franchissables", noStep)

-- Une caisse bloque le passage (elle n'est pas franchissable à pied).
layout.cells[1][2] = "CRATE"
layout.cells[2][1] = "CRATE"
check("chemin : spawn encerré par des caisses => inatteignable", grid:findPath({ x = 1, y = 1 }, { x = 5, y = 1 }) == nil)

-- Conversions monde <-> case.
local cell = grid:worldToCell(grid:cellToWorld({ x = 7, y = 9 }, 3))
check("conversion : cellToWorld puis worldToCell", cell ~= nil and cell.x == 7 and cell.y == 9)
check("conversion : hors zone => nil", grid:worldToCell(Vector3.new(-1000, 0, 0)) == nil)

print(("[Phase1Tests] %d réussis, %d échecs"):format(passed, failed))
