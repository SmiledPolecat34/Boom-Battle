--!nocheck
-- ExplosionResolver : explosion en croix, obstacles, chaînes (calcul pur sur un instantané).
local ExplosionResolver = world.module("ExplosionResolver")

local function addBomb(grid, bombs, x, y, range)
	local bomb = { cell = { x = x, y = y }, range = range, exploded = false }
	bombs[grid:key(x, y)] = bomb
	grid:setBomb(x, y, true)
	return bomb
end

local function hasCell(result, x, y): boolean
	for _, c in result.cells do
		if c.x == x and c.y == y then
			return true
		end
	end
	return false
end

describe("obstacles", function()
	it("T06 un pilier arrête la propagation sans être touché", function()
		local grid, cells = Fixtures.emptyGrid(9)
		cells[5][7] = "PILLAR"
		local bombs = {}
		local r = ExplosionResolver.resolve(grid, bombs, addBomb(grid, bombs, 5, 5, 4))
		expect(hasCell(r, 6, 5)).toBe(true)
		expect(hasCell(r, 7, 5)).toBe(false)
		expect(hasCell(r, 8, 5)).toBe(false)
		expect(hasCell(r, 1, 5)).toBe(true)
	end)

	it("T07 une caisse est touchée, listée, détruite puis bloque", function()
		local grid, cells = Fixtures.emptyGrid(9)
		cells[5][7] = "CRATE"
		local bombs = {}
		local r = ExplosionResolver.resolve(grid, bombs, addBomb(grid, bombs, 5, 5, 4))
		expect(hasCell(r, 7, 5)).toBe(true)
		expect(#r.crates).toBe(1)
		expect(r.crates[1].x).toBe(7)
		expect(r.crates[1].y).toBe(5)
		expect(hasCell(r, 8, 5)).toBe(false)
	end)

end)

describe("forme de l'explosion", function()
	it("portée 2 : croix de 9 cases, ni diagonale ni case à 3", function()
		local grid = Fixtures.emptyGrid(9)
		local bombs = {}
		local r = ExplosionResolver.resolve(grid, bombs, addBomb(grid, bombs, 5, 5, 2))
		expect(hasCell(r, 7, 5)).toBe(true)
		expect(hasCell(r, 5, 3)).toBe(true)
		expect(hasCell(r, 8, 5)).toBe(false)
		expect(hasCell(r, 6, 6)).toBe(false)
		expect(#r.cells).toBe(9)
	end)

	it("dans un coin, l'explosion ne sort pas de la grille", function()
		local grid = Fixtures.emptyGrid(9)
		local bombs = {}
		local r = ExplosionResolver.resolve(grid, bombs, addBomb(grid, bombs, 1, 1, 6))
		expect(#r.cells).toBe(13)
		for _, c in r.cells do
			expect(grid:inBounds(c.x, c.y)).toBe(true)
		end
	end)

	it("portée 1 : seulement les 4 voisines et le centre", function()
		local grid = Fixtures.emptyGrid(9)
		local bombs = {}
		local r = ExplosionResolver.resolve(grid, bombs, addBomb(grid, bombs, 5, 5, 1))
		expect(#r.cells).toBe(5)
	end)

	it("aucune case en double", function()
		local grid = Fixtures.emptyGrid(9)
		local bombs = {}
		local a = addBomb(grid, bombs, 5, 5, 3)
		addBomb(grid, bombs, 5, 7, 3)
		local r = ExplosionResolver.resolve(grid, bombs, a)
		local seen = {}
		for _, c in r.cells do
			local k = c.x .. "," .. c.y
			expect(seen[k]).toBeNil()
			seen[k] = true
		end
	end)
end)

describe("chaînes", function()
	it("T08 chaque bombe de la chaîne explose une seule fois", function()
		local grid = Fixtures.emptyGrid(9)
		local bombs = {}
		local a = addBomb(grid, bombs, 2, 5, 2)
		local b = addBomb(grid, bombs, 4, 5, 2)
		local c = addBomb(grid, bombs, 4, 8, 1)
		local d = addBomb(grid, bombs, 4, 7, 1)
		local r = ExplosionResolver.resolve(grid, bombs, a)
		local counts = {}
		for _, bomb in r.bombs do
			counts[bomb] = (counts[bomb] or 0) + 1
		end
		expect(counts[a]).toBe(1)
		expect(counts[b]).toBe(1)
		expect(counts[c]).toBe(1)
		expect(counts[d]).toBe(1)
		expect(#r.bombs).toBe(4)
	end)

	it("une bombe hors portée ne rejoint pas la chaîne", function()
		local grid = Fixtures.emptyGrid(9)
		local bombs = {}
		local a = addBomb(grid, bombs, 2, 5, 2)
		local far = addBomb(grid, bombs, 8, 5, 2)
		local r = ExplosionResolver.resolve(grid, bombs, a)
		expect(#r.bombs).toBe(1)
		expect(table.find(r.bombs, far)).toBeNil()
	end)

	it("une bombe derrière un pilier est protégée", function()
		local grid, cells = Fixtures.emptyGrid(9)
		cells[5][3] = "PILLAR"
		local bombs = {}
		local a = addBomb(grid, bombs, 2, 5, 3)
		local hidden = addBomb(grid, bombs, 4, 5, 1)
		expect(table.find(ExplosionResolver.resolve(grid, bombs, a).bombs, hidden)).toBeNil()
	end)

	it("une bombe touchée ne bloque pas la propagation", function()
		local grid = Fixtures.emptyGrid(9)
		local bombs = {}
		local a = addBomb(grid, bombs, 2, 5, 5)
		addBomb(grid, bombs, 4, 5, 1)
		local r = ExplosionResolver.resolve(grid, bombs, a)
		expect(hasCell(r, 7, 5)).toBe(true)
	end)

	it("ne modifie ni la grille ni les bombes (calcul pur)", function()
		local grid, cells = Fixtures.emptyGrid(9)
		cells[5][7] = "CRATE"
		local bombs = {}
		local a = addBomb(grid, bombs, 5, 5, 4)
		ExplosionResolver.resolve(grid, bombs, a)
		expect(cells[5][7]).toBe("CRATE")
		expect(a.exploded).toBe(false)
		expect(grid:hasBomb(5, 5)).toBe(true)
	end)
end)
