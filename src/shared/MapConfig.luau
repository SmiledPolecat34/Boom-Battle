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

-- Un seul thème activé en v0.1. Les quatre autres arrivent en v0.2 (Phase 5) sur le même générateur.
MapConfig.Themes = table.freeze({
	Classic = table.freeze({
		Enabled = true,
		FloorColorA = Color3.fromRGB(122, 196, 70),
		FloorColorB = Color3.fromRGB(104, 178, 58),
		PillarColor = Color3.fromRGB(128, 134, 150),
		CrateColor = Color3.fromRGB(214, 138, 54),
		BorderColor = Color3.fromRGB(96, 102, 118),
		Material = Enum.Material.SmoothPlastic,
	}),
})

MapConfig.DefaultTheme = "Classic"

return table.freeze(MapConfig)
