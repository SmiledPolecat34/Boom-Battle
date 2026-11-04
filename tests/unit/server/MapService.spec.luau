--!nocheck
-- MapService (construction de l'arène) et ModularAssets (modèles 3D modulaires). Les Parts sont des instances génériques
-- simulées : on vérifie ce qui est construit (noms, nombre, positions, attributs, rendu modulaire ou de secours),
-- jamais le rendu à l'écran (couvert en Studio par Phase5Tests).
local MapConfig = world.module("MapConfig")

local MapService, ModularAssets

-- Thème modulaire (le seul à `modular = true`) et un thème Parts classique.
local function themeIds()
	local modular, plain
	for _, id in MapConfig.ThemeOrder do
		if MapConfig.Themes[id].modular then
			modular = modular or id
		else
			plain = plain or id
		end
	end
	return modular, plain
end

-- Dossier ReplicatedStorage.MapAssets avec `names` (MeshParts), ou avec tous les modèles obligatoires si names = nil.
local function attachAssets(names)
	local Instance = world.env.Instance
	local root = Instance.new("Folder")
	root.Name = MapConfig.Modular.assetsFolder
	local sub = Instance.new("Folder", root)
	sub.Name = "Floors"
	for _, name in names or ModularAssets.requiredNames() do
		local mesh = Instance.new("MeshPart", sub)
		mesh.Name = name
	end
	world.attach("ReplicatedStorage", root)
	return root
end

local function childrenNamed(folder, pattern)
	local list = {}
	for _, child in folder:GetChildren() do
		if child.Name:match(pattern) then
			table.insert(list, child)
		end
	end
	return list
end

local function count(layout, kind)
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

beforeEach(function()
	world.reset()
	MapService = world.module("MapService")
	ModularAssets = world.module("ModularAssets")
end)

describe("construction en Parts", function()
	for sizeId, sizeDef in MapConfig.Sizes do
		it(("taille %s : une Part par pilier et par caisse, plaque de sol, 4 murs d'enceinte"):format(sizeId), function()
			local _, plain = themeIds()
			local info = MapService.generateAndBuild(sizeDef, 42, 4, plain)
			local folder = info.folder
			expect(#childrenNamed(folder, "^Pillar_")).toBe(count(info.layout, "PILLAR"))
			expect(#childrenNamed(folder, "^Crate_")).toBe(count(info.layout, "CRATE"))
			local crateCount = 0
			for _ in info.crates do
				crateCount += 1
			end
			expect(crateCount).toBe(count(info.layout, "CRATE"))
			expect(folder:FindFirstChild("Floor")).never.toBeNil()
			expect(folder:FindFirstChild("Ground")).never.toBeNil()
			for _, side in { "North", "South", "West", "East" } do
				expect(folder:FindFirstChild("Border_" .. side)).never.toBeNil()
			end
		end)
	end

	it("le dossier Arena est dans le Workspace avec seed, taille et thème en attributs", function()
		local _, plain = themeIds()
		local info = MapService.generateAndBuild(MapConfig.Sizes.Small, 5, 2, plain)
		expect(info.folder.Parent).toBe(world.env.workspace)
		expect(info.folder.Name).toBe("Arena")
		expect(info.folder:GetAttribute("Seed")).toBe(info.layout.seed)
		expect(info.folder:GetAttribute("Size")).toBe(info.layout.size)
		expect(info.folder:GetAttribute("Theme")).toBe(info.layout.theme)
		expect(info.folder:GetAttribute("Modular")).toBeNil()
		expect(MapService.getCurrent()).toBe(info)
	end)

	it("chaque pilier et caisse porte sa case en attributs et se trouve au centre de cette case", function()
		local _, plain = themeIds()
		local info = MapService.generateAndBuild(MapConfig.Sizes.Small, 5, 2, plain)
		for _, part in childrenNamed(info.folder, "^Crate_") do
			local cell = { x = part:GetAttribute("CellX"), y = part:GetAttribute("CellY") }
			expect(info.layout.cells[cell.y][cell.x]).toBe("CRATE")
			expect(info.grid:worldToCell(part.Position)).toEqual(cell)
		end
		for _, part in childrenNamed(info.folder, "^Pillar_") do
			local x, y = part:GetAttribute("CellX"), part:GetAttribute("CellY")
			expect(info.layout.cells[y][x]).toBe("PILLAR")
		end
	end)

	it("les cases de spawn sont libres de toute Part (aucune caisse ni pilier)", function()
		local _, plain = themeIds()
		local info = MapService.generateAndBuild(MapConfig.Sizes.Medium, 9, 8, plain)
		for _, spawn in info.layout.spawns do
			expect(info.folder:FindFirstChild(("Crate_%d_%d"):format(spawn.x, spawn.y))).toBeNil()
			expect(info.folder:FindFirstChild(("Pillar_%d_%d"):format(spawn.x, spawn.y))).toBeNil()
		end
	end)

	it("les décors restent hors de la zone jouable", function()
		local _, plain = themeIds()
		local info = MapService.generateAndBuild(MapConfig.Sizes.Medium, 9, 4, plain)
		local decor = info.folder:FindFirstChild("Decor")
		expect(#decor:GetChildren()).toBeGreaterThan(0)
		local half = info.layout.size * MapConfig.CellSize / 2
		for _, part in decor:GetChildren() do
			local p = part.Position
			expect(math.abs(p.X) > half or math.abs(p.Z) > half).toBe(true)
			expect(part.CanCollide).toBe(false)
		end
	end)

	it("même seed et même thème : arène identique (mêmes noms de Parts, mêmes positions)", function()
		local _, plain = themeIds()
		local function signature()
			local info = MapService.generateAndBuild(MapConfig.Sizes.Small, 77, 3, plain)
			local lines = {}
			for _, part in info.folder:GetDescendants() do
				table.insert(lines, part.Name .. "@" .. tostring(part.Position))
			end
			table.sort(lines)
			return table.concat(lines, "|")
		end
		expect(signature()).toBe(signature())
	end)

	it("chaque thème construit une arène valide et applique son éclairage", function()
		local Lighting = world.game:GetService("Lighting")
		for _, id in MapConfig.ThemeOrder do
			local info = MapService.generateAndBuild(MapConfig.Sizes.Small, 3, 2, id)
			expect(info.layout.theme).toBe(id)
			expect(Lighting.ClockTime).toBe(MapConfig.Themes[id].lighting.clockTime)
			expect(Lighting.Brightness).toBe(MapConfig.Themes[id].lighting.brightness)
		end
	end)
end)

describe("cycle de vie", function()
	it("générer à nouveau détruit l'ancienne arène : une seule Arena dans le Workspace", function()
		local _, plain = themeIds()
		local first = MapService.generateAndBuild(MapConfig.Sizes.Small, 1, 2, plain)
		local second = MapService.generateAndBuild(MapConfig.Sizes.Small, 2, 2, plain)
		expect(first.folder.destroyed).toBe(true)
		local arenas = 0
		for _, child in world.env.workspace:GetChildren() do
			if child.Name == "Arena" then
				arenas += 1
			end
		end
		expect(arenas).toBe(1)
		expect(MapService.getCurrent()).toBe(second)
	end)

	it("destroy supprime l'arène courante et une arène résiduelle inconnue", function()
		local _, plain = themeIds()
		local info = MapService.generateAndBuild(MapConfig.Sizes.Small, 1, 2, plain)
		local stray = world.env.Instance.new("Folder", world.env.workspace)
		stray.Name = "Arena"
		MapService.destroy()
		expect(info.folder.destroyed).toBe(true)
		expect(stray.destroyed).toBe(true)
		expect(MapService.getCurrent()).toBeNil()
		MapService.destroy() -- idempotent
	end)

	it("sans aucune arène : getCurrent vaut nil", function()
		expect(MapService.getCurrent()).toBeNil()
	end)
end)

describe("rendu modulaire (modèles 3D)", function()
	it("avec tous les modèles obligatoires : rendu modulaire, pièces étiquetées BBAsset", function()
		local modular = themeIds()
		attachAssets()
		local info = MapService.generateAndBuild(MapConfig.Sizes.Small, 11, 2, modular)
		expect(info.folder:GetAttribute("Modular")).toBe(true)
		expect(info.folder:FindFirstChild("BorderStones")).never.toBeNil()
		local tile = info.folder:FindFirstChild("Tile_1_1")
		expect(tile).never.toBeNil()
		expect(type(tile:GetAttribute("BBAsset"))).toBe("string")
		for _, part in childrenNamed(info.folder, "^Crate_") do
			expect(type(part:GetAttribute("BBAsset"))).toBe("string")
			expect(part:GetAttribute("CellX")).never.toBeNil()
		end
		expect(#childrenNamed(info.folder, "^Pillar_")).toBe(count(info.layout, "PILLAR"))
	end)

	it("un modèle obligatoire manquant : retombe sur les Parts colorées, avec un avertissement", function()
		local modular = themeIds()
		local names = ModularAssets.requiredNames()
		table.remove(names)
		attachAssets(names)
		local info = MapService.generateAndBuild(MapConfig.Sizes.Small, 11, 2, modular)
		expect(info.folder:GetAttribute("Modular")).toBeNil()
		expect(info.folder:FindFirstChild("BorderStones")).toBeNil()
		local warned = false
		for _, line in world.warnings do
			if line:find("Modèles manquants", 1, true) then
				warned = true
			end
		end
		expect(warned).toBe(true)
	end)

	it("dossier d'assets absent : rendu en Parts", function()
		local modular = themeIds()
		local info = MapService.generateAndBuild(MapConfig.Sizes.Small, 11, 2, modular)
		expect(info.folder:GetAttribute("Modular")).toBeNil()
	end)

	it("un thème non modulaire ignore les modèles même s'ils sont présents", function()
		local _, plain = themeIds()
		attachAssets()
		local info = MapService.generateAndBuild(MapConfig.Sizes.Small, 11, 2, plain)
		expect(info.folder:GetAttribute("Modular")).toBeNil()
	end)

	it("la grille logique est identique en rendu modulaire et en Parts (même seed)", function()
		local modular = themeIds()
		local plainInfo = MapService.generateAndBuild(MapConfig.Sizes.Small, 31, 2, modular)
		local plainCells = {}
		for y = 1, plainInfo.layout.size do
			plainCells[y] = table.clone(plainInfo.layout.cells[y])
		end
		attachAssets()
		local modularInfo = MapService.generateAndBuild(MapConfig.Sizes.Small, 31, 2, modular)
		expect(modularInfo.layout.cells).toEqual(plainCells)
	end)
end)

describe("ModularAssets", function()
	it("requiredNames : sans doublon, sol, murs et obstacles seulement", function()
		local names = ModularAssets.requiredNames()
		local seen = {}
		for _, name in names do
			expect(seen[name]).toBeNil()
			seen[name] = true
		end
		for _, name in MapConfig.Modular.floorBase do
			expect(seen[name]).toBe(true)
		end
		for _, entry in MapConfig.Modular.decor do
			expect(seen[entry.name]).toBeNil() -- les décors sont facultatifs
		end
	end)

	it("isAvailable : faux sans dossier, faux s'il manque un modèle, vrai si tout est là", function()
		expect(ModularAssets.isAvailable()).toBe(false)
		attachAssets({ "BB_FLOOR_01_Grass" })
		expect(ModularAssets.isAvailable()).toBe(false)
		world.reset()
		ModularAssets = world.module("ModularAssets")
		attachAssets()
		expect(ModularAssets.isAvailable()).toBe(true)
		expect(ModularAssets.has("BB_FLOOR_01_Grass")).toBe(true)
		expect(ModularAssets.has("inconnu")).toBe(false)
	end)

	it("pickWeighted : poids nul ignoré, filtre appliqué, nil si rien d'utilisable", function()
		local rng = Random.new(1)
		local entries = { { name = "a", weight = 0 }, { name = "b", weight = 1 }, { name = "c", weight = 1 } }
		for _ = 1, 50 do
			expect(ModularAssets.pickWeighted(entries, rng)).never.toBe("a")
		end
		for _ = 1, 20 do
			expect(ModularAssets.pickWeighted(entries, rng, function(name)
				return name == "c"
			end)).toBe("c")
		end
		expect(ModularAssets.pickWeighted({}, rng)).toBeNil()
		expect(ModularAssets.pickWeighted({ { name = "x", weight = 0 } }, rng)).toBeNil()
		expect(ModularAssets.pickWeighted(entries, rng, function()
			return false
		end)).toBeNil()
	end)

	it("pickWeighted : les fréquences suivent les poids (tolérance large)", function()
		local rng = Random.new(7)
		local entries = { { name = "rare", weight = 1 }, { name = "common", weight = 9 } }
		local common = 0
		for _ = 1, 1000 do
			if ModularAssets.pickWeighted(entries, rng) == "common" then
				common += 1
			end
		end
		expect(common).toBeGreaterThan(800)
		expect(common).toBeLessThan(970)
	end)

	it("pickWeighted consomme exactement un tirage par appel (garde les tirages alignés)", function()
		local draws = 0
		local rng = { NextNumber = function() draws += 1 return 0.5 end }
		ModularAssets.pickWeighted({ { name = "a", weight = 1 }, { name = "b", weight = 1 } }, rng)
		expect(draws).toBe(1)
	end)

	it("place : clone ancré, étiqueté, positionné (translation du pivot seulement) ; modèle inconnu = erreur", function()
		attachAssets()
		expect(ModularAssets.isAvailable()).toBe(true)
		local parent = world.env.Instance.new("Folder")
		local name = ModularAssets.requiredNames()[1]
		local part = ModularAssets.place(name, CFrame.new(10, 0, 20), parent)
		expect(part.Parent).toBe(parent)
		expect(part.Anchored).toBe(true)
		expect(part:GetAttribute("BBAsset")).toBe(name)
		expect(part:GetPivot().Position).toEqual(Vector3.new(10, 0, 20))
		expect(function()
			ModularAssets.place("BB_N_EXISTE_PAS", CFrame.new(0, 0, 0), parent)
		end).toThrow("modèle inconnu")
	end)
end)
