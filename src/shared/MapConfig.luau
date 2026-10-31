--!strict
-- Paramètres des arènes. Voir docs/ARCHITECTURE.md §3 (H1, H2, H6) et §6.

local Types = require(script.Parent.Types)

export type SizeDefinition = {
	id: string,
	size: number,
	enabled: boolean,
	-- Axe de piliers symétrique (x -> size + 1 - x). Un pilier existe en (x, y) si x ET y sont dans l'axe.
	pillarAxis: { number },
	-- Nombre de joueurs pour lequel cette taille est choisie : minPlayers <= n <= maxPlayers.
	minPlayers: number,
	maxPlayers: number,
}

export type ThemeDefinition = {
	enabled: boolean,
	displayName: string,
	-- Sol : damier A/B, avec des cases « accent » (taches) discrètes ; jamais de couleur de danger.
	floorColorA: Color3,
	floorColorB: Color3,
	floorAccentColor: Color3,
	floorMaterial: Enum.Material,
	-- Murs fixes : bloc + chapeau plus clair.
	pillarColor: Color3,
	pillarCapColor: Color3,
	pillarMaterial: Enum.Material,
	-- Caisses destructibles : bloc + couvercle. Doivent contraster avec les murs ET avec le sol.
	crateColor: Color3,
	crateLidColor: Color3,
	crateMaterial: Enum.Material,
	borderColor: Color3,
	borderMaterial: Enum.Material,
	-- Sol hors de l'arène et décors (sans collision, hors de la zone de jeu).
	groundColor: Color3,
	groundMaterial: Enum.Material,
	decorKinds: { string }, -- "Tree" | "Rock" | "Cactus" | "Spike"
	decorPrimary: Color3, -- feuillage, cactus
	decorSecondary: Color3, -- roches, pointes
	lighting: { clockTime: number, ambient: Color3, outdoorAmbient: Color3, brightness: number },
}

local MapConfig = {}

-- H1 : la taille désigne les cases JOUABLES ; un anneau de murs indestructibles les entoure
-- (10 -> 12 x 12, 16 -> 18 x 18, 24 -> 26 x 26 au total).
-- H6 : trois tailles ; la sélection par nombre de joueurs est une PROPOSITION à valider.
-- H2 : sur une taille paire, le motif classique « une case sur deux » ne peut pas être symétrique,
-- d'où des axes explicites, à valider visuellement en Phase 1.
MapConfig.Sizes = table.freeze({
	Small = table.freeze({
		id = "Small",
		size = 10,
		enabled = true,
		pillarAxis = table.freeze({ 3, 5, 6, 8 }),
		minPlayers = 2,
		maxPlayers = 3,
	}),
	Medium = table.freeze({
		id = "Medium",
		size = 16,
		enabled = true,
		pillarAxis = table.freeze({ 3, 5, 7, 10, 12, 14 }),
		minPlayers = 4,
		maxPlayers = 6,
	}),
	Large = table.freeze({
		id = "Large",
		size = 24,
		enabled = true,
		pillarAxis = table.freeze({ 3, 5, 7, 9, 11, 14, 16, 18, 20, 22 }),
		minPlayers = 7,
		maxPlayers = 8,
	}),
}) :: { [string]: SizeDefinition }

-- Taille utilisée hors sélection automatique (tests, solo Studio).
MapConfig.DefaultSize = "Medium"

MapConfig.CellSize = 4 -- studs

-- Densité des caisses parmi les cases libres hors zones de spawn. PROPOSITION : à équilibrer.
MapConfig.CrateDensity = 0.55

-- Cases libres exigées autour de chaque spawn (distance de Manhattan <= SpawnSafeDistance).
MapConfig.SpawnSafeDistance = 2

-- Sorties accessibles minimales exigées autour de chaque spawn avant validation de la map.
MapConfig.MinSpawnExits = 2

-- Nombre maximal de régénérations avant d'utiliser la map de secours (sans caisse aléatoire).
MapConfig.MaxGenerationAttempts = 20

-- 8 spawns symétriques par rotation de 90° ((x, y) -> (size + 1 - y, x)) : 4 coins puis 4 milieux de côté.
-- Les deux premiers sont des coins opposés, ce qui équilibre les parties à 2 joueurs.
function MapConfig.getSpawns(size: number): { Types.Cell }
	local half = size // 2
	return table.freeze({
		table.freeze({ x = 1, y = 1 }),
		table.freeze({ x = size, y = size }),
		table.freeze({ x = size, y = 1 }),
		table.freeze({ x = 1, y = size }),
		table.freeze({ x = half, y = 1 }),
		table.freeze({ x = size + 1 - half, y = size }),
		table.freeze({ x = size, y = half }),
		table.freeze({ x = 1, y = half + 1 }),
	})
end

-- Retourne la définition de taille adaptée au nombre de joueurs, ou la taille par défaut.
function MapConfig.getSizeForPlayerCount(playerCount: number): SizeDefinition
	for _, definition in MapConfig.Sizes do
		if definition.enabled and playerCount >= definition.minPlayers and playerCount <= definition.maxPlayers then
			return definition
		end
	end
	return MapConfig.Sizes[MapConfig.DefaultSize]
end

-- Cinq thèmes sur le MÊME générateur : seuls les couleurs, matériaux, décors et l'éclairage changent. Les règles de
-- grille, de collision et de jouabilité sont identiques (H8 : les accents de sol restent sobres pour ne jamais
-- ressembler à une zone dangereuse).
local function lighting(clockTime: number, ambient: Color3, outdoor: Color3, brightness: number)
	return table.freeze({ clockTime = clockTime, ambient = ambient, outdoorAmbient = outdoor, brightness = brightness })
end

MapConfig.Themes = table.freeze({
	Classic = table.freeze({
		enabled = true,
		displayName = "Classique",
		floorColorA = Color3.fromRGB(122, 196, 70),
		floorColorB = Color3.fromRGB(104, 178, 58),
		floorAccentColor = Color3.fromRGB(196, 150, 78),
		floorMaterial = Enum.Material.Grass,
		pillarColor = Color3.fromRGB(128, 134, 150),
		pillarCapColor = Color3.fromRGB(164, 170, 186),
		pillarMaterial = Enum.Material.Slate,
		crateColor = Color3.fromRGB(214, 138, 54),
		crateLidColor = Color3.fromRGB(236, 168, 84),
		crateMaterial = Enum.Material.WoodPlanks,
		borderColor = Color3.fromRGB(96, 102, 118),
		borderMaterial = Enum.Material.Cobblestone,
		groundColor = Color3.fromRGB(84, 140, 52),
		groundMaterial = Enum.Material.Grass,
		decorKinds = table.freeze({ "Tree", "Rock", "Tree" }),
		decorPrimary = Color3.fromRGB(58, 150, 58),
		decorSecondary = Color3.fromRGB(140, 146, 160),
		lighting = lighting(14, Color3.fromRGB(110, 118, 130), Color3.fromRGB(140, 150, 160), 2),
	}),
	Desert = table.freeze({
		enabled = true,
		displayName = "Désert",
		floorColorA = Color3.fromRGB(236, 204, 124),
		floorColorB = Color3.fromRGB(222, 188, 104),
		floorAccentColor = Color3.fromRGB(196, 156, 90),
		floorMaterial = Enum.Material.Sand,
		pillarColor = Color3.fromRGB(176, 140, 104),
		pillarCapColor = Color3.fromRGB(206, 172, 132),
		pillarMaterial = Enum.Material.Sandstone,
		crateColor = Color3.fromRGB(122, 84, 52),
		crateLidColor = Color3.fromRGB(150, 108, 68),
		crateMaterial = Enum.Material.WoodPlanks,
		borderColor = Color3.fromRGB(160, 122, 86),
		borderMaterial = Enum.Material.Sandstone,
		groundColor = Color3.fromRGB(226, 196, 120),
		groundMaterial = Enum.Material.Sand,
		decorKinds = table.freeze({ "Cactus", "Rock", "Cactus" }),
		decorPrimary = Color3.fromRGB(70, 140, 70),
		decorSecondary = Color3.fromRGB(170, 130, 96),
		lighting = lighting(13, Color3.fromRGB(150, 128, 98), Color3.fromRGB(190, 160, 120), 2.4),
	}),
	Ice = table.freeze({
		enabled = true,
		displayName = "Glace",
		floorColorA = Color3.fromRGB(204, 232, 250),
		floorColorB = Color3.fromRGB(184, 218, 242),
		floorAccentColor = Color3.fromRGB(238, 248, 255),
		floorMaterial = Enum.Material.Snow,
		pillarColor = Color3.fromRGB(96, 132, 188),
		pillarCapColor = Color3.fromRGB(150, 186, 226),
		pillarMaterial = Enum.Material.Ice,
		crateColor = Color3.fromRGB(70, 110, 150),
		crateLidColor = Color3.fromRGB(104, 150, 196),
		crateMaterial = Enum.Material.Glacier,
		borderColor = Color3.fromRGB(80, 112, 164),
		borderMaterial = Enum.Material.Ice,
		groundColor = Color3.fromRGB(232, 244, 252),
		groundMaterial = Enum.Material.Snow,
		decorKinds = table.freeze({ "Spike", "Tree", "Spike" }),
		decorPrimary = Color3.fromRGB(46, 110, 92),
		decorSecondary = Color3.fromRGB(170, 214, 240),
		lighting = lighting(11, Color3.fromRGB(120, 140, 170), Color3.fromRGB(160, 184, 210), 2.2),
	}),
	Volcano = table.freeze({
		enabled = true,
		displayName = "Volcan",
		floorColorA = Color3.fromRGB(78, 62, 66),
		floorColorB = Color3.fromRGB(66, 52, 56),
		floorAccentColor = Color3.fromRGB(104, 58, 52),
		floorMaterial = Enum.Material.Slate,
		pillarColor = Color3.fromRGB(36, 36, 44),
		pillarCapColor = Color3.fromRGB(70, 66, 78),
		pillarMaterial = Enum.Material.Basalt,
		crateColor = Color3.fromRGB(170, 96, 56),
		crateLidColor = Color3.fromRGB(204, 126, 74),
		crateMaterial = Enum.Material.WoodPlanks,
		borderColor = Color3.fromRGB(26, 24, 30),
		borderMaterial = Enum.Material.Basalt,
		groundColor = Color3.fromRGB(255, 96, 24), -- lave, hors de l'arène seulement
		groundMaterial = Enum.Material.Neon,
		decorKinds = table.freeze({ "Rock", "Spike", "Rock" }),
		decorPrimary = Color3.fromRGB(60, 60, 68),
		decorSecondary = Color3.fromRGB(46, 42, 52),
		lighting = lighting(18.5, Color3.fromRGB(120, 70, 60), Color3.fromRGB(170, 90, 60), 1.8),
	}),
	Jungle = table.freeze({
		enabled = true,
		displayName = "Jungle",
		floorColorA = Color3.fromRGB(78, 156, 84),
		floorColorB = Color3.fromRGB(64, 138, 72),
		floorAccentColor = Color3.fromRGB(120, 98, 58),
		floorMaterial = Enum.Material.Grass,
		pillarColor = Color3.fromRGB(104, 122, 100),
		pillarCapColor = Color3.fromRGB(86, 150, 98),
		pillarMaterial = Enum.Material.Slate,
		crateColor = Color3.fromRGB(150, 98, 46),
		crateLidColor = Color3.fromRGB(184, 128, 62),
		crateMaterial = Enum.Material.Wood,
		borderColor = Color3.fromRGB(64, 98, 66),
		borderMaterial = Enum.Material.Slate,
		groundColor = Color3.fromRGB(34, 94, 44),
		groundMaterial = Enum.Material.LeafyGrass,
		decorKinds = table.freeze({ "Tree", "Tree", "Rock" }),
		decorPrimary = Color3.fromRGB(34, 130, 56),
		decorSecondary = Color3.fromRGB(110, 124, 104),
		lighting = lighting(15, Color3.fromRGB(96, 130, 100), Color3.fromRGB(130, 170, 130), 2.1),
	}),
}) :: { [string]: ThemeDefinition }

-- Ordre stable : un même seed donne toujours le même thème.
MapConfig.ThemeOrder = table.freeze({ "Classic", "Desert", "Ice", "Volcano", "Jungle" })

MapConfig.DefaultTheme = "Classic"

-- Thème choisi pour une manche, d'après la seed ; ne retourne que des thèmes activés.
function MapConfig.themeForSeed(seed: number): string
	local enabled: { string } = {}
	for _, id in MapConfig.ThemeOrder do
		if MapConfig.Themes[id].enabled then
			table.insert(enabled, id)
		end
	end
	if #enabled == 0 then
		return MapConfig.DefaultTheme
	end
	return enabled[(math.floor(math.abs(seed)) % #enabled) + 1]
end

return table.freeze(MapConfig)
