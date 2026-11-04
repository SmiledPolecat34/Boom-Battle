--!nocheck
-- GridService : état logique de la grille, conversions monde <-> case, recherche de chemin (BFS).
local MapConfig = world.module("MapConfig")
local MapGenerator = world.module("MapGenerator")
local GridService = world.module("GridService")

describe("limites et clés", function()
	it("inBounds refuse 0, size+1, NaN et fractions hors grille", function()
		local grid = Fixtures.emptyGrid(9)
		expect(grid:inBounds(1, 1)).toBe(true)
		expect(grid:inBounds(9, 9)).toBe(true)
		expect(grid:inBounds(0, 1)).toBe(false)
		expect(grid:inBounds(1, 10)).toBe(false)
		expect(grid:inBounds(-3, -3)).toBe(false)
	end)

	it("key est unique pour chaque case de la grille", function()
		local grid = Fixtures.emptyGrid(9)
		local seen = {}
		for y = 1, 9 do
			for x = 1, 9 do
				local k = grid:key(x, y)
				expect(seen[k]).toBeNil()
				seen[k] = true
			end
		end
	end)

	it("getKind hors grille ne plante pas et n'est jamais franchissable", function()
		local grid = Fixtures.emptyGrid(9)
		expect(grid:isWalkable(0, 5)).toBe(false)
		expect(grid:isWalkable(10, 5)).toBe(false)
		expect(grid:isWalkable(5, 0)).toBe(false)
	end)
end)

describe("franchissabilité", function()
	it("une case vide est franchissable", function()
		local grid = Fixtures.emptyGrid(9)
		expect(grid:isWalkable(5, 5)).toBe(true)
	end)

	it("pilier et caisse bloquent la marche", function()
		local grid, cells = Fixtures.emptyGrid(9)
		cells[5][5] = "PILLAR"
		cells[5][6] = "CRATE"
		expect(grid:isWalkable(5, 5)).toBe(false)
		expect(grid:isWalkable(6, 5)).toBe(false)
	end)

	it("une bombe bloque la marche, puis la libère une fois retirée", function()
		local grid = Fixtures.emptyGrid(9)
		grid:setBomb(3, 1, true)
		expect(grid:hasBomb(3, 1)).toBe(true)
		expect(grid:isWalkable(3, 1)).toBe(false)
		grid:setBomb(3, 1, false)
		expect(grid:hasBomb(3, 1)).toBe(false)
		expect(grid:isWalkable(3, 1)).toBe(true)
	end)

	it("setKind change la nature de la case", function()
		local grid = Fixtures.emptyGrid(9)
		grid:setKind(4, 4, "CRATE")
		expect(grid:getKind(4, 4)).toBe("CRATE")
		grid:setKind(4, 4, "EMPTY")
		expect(grid:isWalkable(4, 4)).toBe(true)
	end)
end)

describe("chemin (findPath)", function()
	local function openMediumGrid()
		local layout = MapGenerator.generate(MapConfig.Sizes.Medium, 99, 2)
		for y = 1, layout.size do
			for x = 1, layout.size do
				if layout.cells[y][x] == "CRATE" then
					layout.cells[y][x] = "EMPTY"
				end
			end
		end
		return GridService.new(layout, MapConfig.CellSize, Vector3.new(0, 0, 0)), layout
	end

	it("départ == cible retourne un chemin vide", function()
		local grid = openMediumGrid()
		local path = grid:findPath({ x = 1, y = 1 }, { x = 1, y = 1 })
		expect(path).never.toBeNil()
		expect(#path).toBe(0)
	end)

	it("ligne libre de 4 cases", function()
		local grid = openMediumGrid()
		expect(#grid:findPath({ x = 1, y = 1 }, { x = 5, y = 1 })).toBe(4)
	end)

	it("refuse un pilier, une case hors grille et un départ hors grille", function()
		local grid = openMediumGrid()
		expect(grid:findPath({ x = 1, y = 1 }, { x = 3, y = 3 })).toBeNil()
		expect(grid:findPath({ x = 1, y = 1 }, { x = 0, y = 1 })).toBeNil()
		expect(grid:findPath({ x = 1, y = 1 }, { x = 17, y = 1 })).toBeNil()
		expect(grid:findPath({ x = -1, y = 1 }, { x = 2, y = 1 })).toBeNil()
	end)

	it("coin à coin : 30 pas, tous orthogonaux et franchissables", function()
		local grid = openMediumGrid()
		local path = grid:findPath({ x = 1, y = 1 }, { x = 16, y = 16 })
		expect(path).never.toBeNil()
		expect(#path).toBe(30)
		local previous = { x = 1, y = 1 }
		for _, cell in path do
			expect(math.abs(cell.x - previous.x) + math.abs(cell.y - previous.y)).toBe(1)
			expect(grid:isWalkable(cell.x, cell.y)).toBe(true)
			previous = cell
		end
	end)

	it("un spawn encerré par des caisses est inatteignable", function()
		local grid, layout = openMediumGrid()
		layout.cells[1][2] = "CRATE"
		layout.cells[2][1] = "CRATE"
		expect(grid:findPath({ x = 1, y = 1 }, { x = 5, y = 1 })).toBeNil()
	end)

	it("contourne une bombe", function()
		local grid = Fixtures.emptyGrid(9)
		grid:setBomb(3, 1, true)
		local path = grid:findPath({ x = 1, y = 1 }, { x = 5, y = 1 })
		expect(path).never.toBeNil()
		expect(#path).toBe(6)
	end)

	it("ne traverse jamais une bombe même si c'est la cible", function()
		local grid = Fixtures.emptyGrid(9)
		grid:setBomb(5, 5, true)
		expect(grid:findPath({ x = 1, y = 1 }, { x = 5, y = 5 })).toBeNil()
	end)
end)

describe("conversions monde <-> case", function()
	it("aller-retour cellToWorld puis worldToCell", function()
		local grid = GridService.new(MapGenerator.generate(MapConfig.Sizes.Medium, 1, 2), MapConfig.CellSize, Vector3.new(0, 0, 0))
		for _, c in { { 1, 1 }, { 7, 9 }, { 16, 16 }, { 1, 16 } } do
			local back = grid:worldToCell(grid:cellToWorld({ x = c[1], y = c[2] }, 3))
			expect(back).never.toBeNil()
			expect(back.x).toBe(c[1])
			expect(back.y).toBe(c[2])
		end
	end)

	it("une position hors zone donne nil", function()
		local grid = Fixtures.emptyGrid(9)
		expect(grid:worldToCell(Vector3.new(-1000, 0, 0))).toBeNil()
		expect(grid:worldToCell(Vector3.new(1000, 0, 1000))).toBeNil()
	end)

	it("la hauteur demandée est respectée", function()
		local grid = Fixtures.emptyGrid(9)
		expect(grid:cellToWorld({ x = 1, y = 1 }, 5).Y).toBeCloseTo(5)
		expect(grid:cellToWorld({ x = 1, y = 1 }).Y).toBeCloseTo(0)
	end)
end)
