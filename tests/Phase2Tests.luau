--!nocheck
-- Tests de la Phase 2 : calcul pur des explosions (ExplosionResolver) et règles de la grille.
-- À EXÉCUTER DANS ROBLOX STUDIO : coller dans la barre de commande (mode Edit) après synchronisation Rojo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GridService = require(ServerScriptService.Server.Services.GridService)
local ExplosionResolver = require(ServerScriptService.Server.Services.ExplosionResolver)

local passed, failed = 0, 0
local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		warn(("ÉCHEC : %s %s"):format(name, detail or ""))
	end
end

-- Grille 9x9 vide ; layout minimal.
local function makeGrid()
	local cells = {}
	for y = 1, 9 do
		cells[y] = {}
		for x = 1, 9 do
			cells[y][x] = "EMPTY"
		end
	end
	return GridService.new({ seed = 1, sizeId = "T", size = 9, theme = "Classic", cells = cells, spawns = {} }, 4, Vector3.zero),
		cells
end

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

-- T06 : un pilier arrête la propagation.
do
	local grid, cells = makeGrid()
	cells[5][7] = "PILLAR"
	local bombs = {}
	local bomb = addBomb(grid, bombs, 5, 5, 4)
	local r = ExplosionResolver.resolve(grid, bombs, bomb)
	check("T06 pilier : case avant touchée", hasCell(r, 6, 5))
	check("T06 pilier : pilier non touché", not hasCell(r, 7, 5))
	check("T06 pilier : derrière le pilier non touché", not hasCell(r, 8, 5))
	check("T06 pilier : autre direction non affectée", hasCell(r, 1, 5))
end

-- T07 : une caisse est détruite et arrête la propagation.
do
	local grid, cells = makeGrid()
	cells[5][7] = "CRATE"
	local bombs = {}
	local bomb = addBomb(grid, bombs, 5, 5, 4)
	local r = ExplosionResolver.resolve(grid, bombs, bomb)
	check("T07 caisse : touchée", hasCell(r, 7, 5))
	check("T07 caisse : listée à détruire", #r.crates == 1 and r.crates[1].x == 7 and r.crates[1].y == 5)
	check("T07 caisse : propagation arrêtée", not hasCell(r, 8, 5))
end

-- Portée et bord.
do
	local grid = makeGrid()
	local bombs = {}
	local bomb = addBomb(grid, bombs, 5, 5, 2)
	local r = ExplosionResolver.resolve(grid, bombs, bomb)
	check("portée 2 : atteint 2 cases", hasCell(r, 7, 5) and hasCell(r, 5, 3))
	check("portée 2 : pas 3 cases", not hasCell(r, 8, 5))
	check("portée 2 : forme en croix (pas de diagonale)", not hasCell(r, 6, 6))
	check("portée 2 : 9 cases au total", #r.cells == 9, tostring(#r.cells))

	local grid2 = makeGrid()
	local bombs2 = {}
	local corner = addBomb(grid2, bombs2, 1, 1, 6)
	local r2 = ExplosionResolver.resolve(grid2, bombs2, corner)
	check("bord : ne sort pas de la grille", #r2.cells == 13, tostring(#r2.cells)) -- 1 + 6 + 6
end

-- T08 : réaction en chaîne, chaque bombe explose une seule fois.
do
	local grid = makeGrid()
	local bombs = {}
	local a = addBomb(grid, bombs, 2, 5, 2)
	local b = addBomb(grid, bombs, 4, 5, 2) -- touchée par a
	local c = addBomb(grid, bombs, 4, 8, 1) -- touchée par b (portée verticale 2 -> case (4,7)? non : (4,8) à 3 cases)
	local d = addBomb(grid, bombs, 4, 7, 1) -- touchée par b
	local r = ExplosionResolver.resolve(grid, bombs, a)
	local count = {}
	for _, bomb in r.bombs do
		count[bomb] = (count[bomb] or 0) + 1
	end
	check("T08 chaîne : a et b explosent", count[a] == 1 and count[b] == 1)
	check("T08 chaîne : d (à 2 cases de b) explose", count[d] == 1)
	check("T08 chaîne : c (à 3 cases de b, portée 2) mais touchée par d", count[c] == 1)
	check("T08 chaîne : aucune bombe deux fois", #r.bombs == 4)
end

-- Bombe isolée hors portée : ne rejoint pas la chaîne.
do
	local grid = makeGrid()
	local bombs = {}
	local a = addBomb(grid, bombs, 2, 5, 2)
	local far = addBomb(grid, bombs, 8, 5, 2)
	local r = ExplosionResolver.resolve(grid, bombs, a)
	check("chaîne : bombe hors portée ignorée", #r.bombs == 1 and not table.find(r.bombs, far))
end

-- Bombe derrière un pilier : protégée.
do
	local grid, cells = makeGrid()
	cells[5][3] = "PILLAR"
	local bombs = {}
	local a = addBomb(grid, bombs, 2, 5, 3)
	local hidden = addBomb(grid, bombs, 4, 5, 1)
	local r = ExplosionResolver.resolve(grid, bombs, a)
	check("chaîne : bombe derrière un pilier non déclenchée", not table.find(r.bombs, hidden))
end

-- Grille : une bombe bloque la marche.
do
	local grid = makeGrid()
	grid:setBomb(3, 1, true)
	check("grille : case avec bombe non franchissable", not grid:isWalkable(3, 1))
	check("grille : chemin contourne la bombe", (function()
		local p = grid:findPath({ x = 1, y = 1 }, { x = 5, y = 1 })
		return p ~= nil and #p == 6
	end)())
	grid:setBomb(3, 1, false)
	check("grille : bombe retirée => franchissable", grid:isWalkable(3, 1))
end

print(("[Phase2Tests] %d réussis, %d échecs"):format(passed, failed))
