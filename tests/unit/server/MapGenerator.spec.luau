--!nocheck
-- MapGenerator : génération reproductible, validité, zones de spawn, symétrie des piliers.
-- NB : sous Lune, `Random` est un remplaçant déterministe (pas celui de Roblox) : on teste des PROPRIÉTÉS, jamais des
-- cases précises.
local MapConfig = world.module("MapConfig")
local MapGenerator = world.module("MapGenerator")

local function sameCells(a, b): boolean
	for y = 1, a.size do
		for x = 1, a.size do
			if a.cells[y][x] ~= b.cells[y][x] then
				return false
			end
		end
	end
	return true
end

local function count(layout, kind: string): number
	local n = 0
	for y = 1, layout.size do
		for x = 1, layout.size do
			if layout.cells[y][x] == kind then
				n += 1
			end
		end
	end
	return n
end

for sizeId, sizeDef in MapConfig.Sizes do
	describe("taille " .. sizeId, function()
		it("50 seeds donnent 50 maps valides (spawns reliés entre eux)", function()
			local invalid = 0
			for seed = 1, 50 do
				local layout = MapGenerator.generate(sizeDef, seed, 8)
				if not MapGenerator.validate(layout.cells, layout.size, layout.spawns) then
					invalid += 1
				end
			end
			expect(invalid).toBe(0)
		end)

		it("même seed => même map ; la seed effective rejoue exactement la map", function()
			local a = MapGenerator.generate(sizeDef, 1234, 8)
			expect(sameCells(a, MapGenerator.generate(sizeDef, 1234, 8))).toBe(true)
			expect(sameCells(a, MapGenerator.generate(sizeDef, a.seed, 8))).toBe(true)
		end)

		it("seeds différentes => maps différentes (au moins une paire)", function()
			local base = MapGenerator.generate(sizeDef, 1, 8)
			local different = false
			for seed = 2, 10 do
				if not sameCells(base, MapGenerator.generate(sizeDef, seed, 8)) then
					different = true
				end
			end
			expect(different).toBe(true)
		end)

		it("le nombre de piliers correspond à l'axe de la taille", function()
			expect(count(MapGenerator.generate(sizeDef, 7, 8), "PILLAR")).toBe((#sizeDef.pillarAxis) ^ 2)
		end)

		it("génère des caisses", function()
			expect(count(MapGenerator.generate(sizeDef, 7, 8), "CRATE")).toBeGreaterThan(0)
		end)

		it("aucune caisse dans les zones de spawn", function()
			local layout = MapGenerator.generate(sizeDef, 5, 8)
			for _, spawn in layout.spawns do
				for y = 1, layout.size do
					for x = 1, layout.size do
						local d = math.abs(spawn.x - x) + math.abs(spawn.y - y)
						if d <= MapConfig.SpawnSafeDistance then
							expect(layout.cells[y][x]).never.toBe("CRATE")
						end
					end
				end
			end
		end)

		it("piliers symétriques (gauche/droite)", function()
			local layout = MapGenerator.generate(sizeDef, 5, 8)
			for y = 1, layout.size do
				for x = 1, layout.size do
					expect(layout.cells[y][x] == "PILLAR").toBe(layout.cells[y][layout.size + 1 - x] == "PILLAR")
				end
			end
		end)

		it("les spawns sont sur des cases vides", function()
			local layout = MapGenerator.generate(sizeDef, 5, 8)
			for _, spawn in layout.spawns do
				expect(layout.cells[spawn.y][spawn.x]).toBe("EMPTY")
			end
		end)
	end)
end

describe("piliers aléatoires équitables", function()
	local function pillarsOf(layout)
		local list = {}
		for y = 1, layout.size do
			for x = 1, layout.size do
				if layout.cells[y][x] == "PILLAR" then
					table.insert(list, { x = x, y = y })
				end
			end
		end
		return list
	end

	for sizeId, sizeDef in MapConfig.Sizes do
		it(sizeId .. " : symétrie miroir sur les deux axes, jamais en bordure ni dans une zone de spawn", function()
			for seed = 1, 20 do
				local layout = MapGenerator.generate(sizeDef, seed, 8)
				for _, p in pillarsOf(layout) do
					expect(layout.cells[p.y][layout.size + 1 - p.x]).toBe("PILLAR")
					expect(layout.cells[layout.size + 1 - p.y][p.x]).toBe("PILLAR")
					expect(p.x >= 2 and p.x <= layout.size - 1 and p.y >= 2 and p.y <= layout.size - 1).toBe(true)
					for _, spawn in layout.spawns do
						expect(math.abs(spawn.x - p.x) + math.abs(spawn.y - p.y)).toBeGreaterThan(MapConfig.SpawnSafeDistance)
					end
				end
			end
		end)

		it(sizeId .. " : le nombre de piliers reste celui de la grille classique", function()
			for seed = 1, 20 do
				expect(#pillarsOf(MapGenerator.generate(sizeDef, seed, 8))).toBe((#sizeDef.pillarAxis) ^ 2)
			end
		end)

		it(sizeId .. " : les placements varient d'une seed à l'autre", function()
			local signatures = {}
			local distinct = 0
			for seed = 1, 12 do
				local parts = {}
				for _, p in pillarsOf(MapGenerator.generate(sizeDef, seed, 8)) do
					table.insert(parts, p.x .. "," .. p.y)
				end
				local signature = table.concat(parts, ";")
				if not signatures[signature] then
					signatures[signature] = true
					distinct += 1
				end
			end
			expect(distinct).toBeGreaterThan(1)
		end)
	end
end)

describe("paramètres limites", function()
	local medium = MapConfig.Sizes.Medium

	it("le nombre de spawns est borné entre 1 et 8", function()
		expect(#MapGenerator.generate(medium, 1, 0).spawns).toBe(1)
		expect(#MapGenerator.generate(medium, 1, -5).spawns).toBe(1)
		expect(#MapGenerator.generate(medium, 1, 99).spawns).toBe(8)
		expect(#MapGenerator.generate(medium, 1, 3).spawns).toBe(3)
	end)

	it("un thème inconnu retombe sur le thème par défaut", function()
		expect(MapGenerator.generate(medium, 1, 2, "NoSuchTheme").theme).toBe(MapConfig.DefaultTheme)
		expect(MapGenerator.generate(medium, 1, 2).theme).toBe(MapConfig.DefaultTheme)
	end)

	it("le thème ne change pas la grille (même seed)", function()
		local base = MapGenerator.generate(medium, 321, 4)
		for themeId in MapConfig.Themes do
			expect(sameCells(base, MapGenerator.generate(medium, 321, 4, themeId))).toBe(true)
		end
	end)

	it("validate refuse une map dont un spawn est encerré", function()
		local layout = MapGenerator.generate(medium, 1, 4)
		layout.cells[layout.spawns[1].y + 1] = layout.cells[layout.spawns[1].y + 1]
		-- on emmure le spawn 1 avec des piliers
		local s = layout.spawns[1]
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local x, y = s.x + d[1], s.y + d[2]
			if layout.cells[y] and layout.cells[y][x] then
				layout.cells[y][x] = "PILLAR"
			end
		end
		expect(MapGenerator.validate(layout.cells, layout.size, layout.spawns)).toBe(false)
	end)
end)
