--!strict
-- Paramètres de l'arène. Voir docs/ARCHITECTURE.md §6 pour les hypothèses H1 et H2 en attente de validation.

local Types = require(script.Parent.Types)

local MapConfig = {}

-- H1 : 16 x 16 correspond à la zone JOUABLE ; un anneau de murs indestructibles l'entoure (18 x 18 au total).
MapConfig.GridSize = 16
MapConfig.CellSize = 4 -- studs

-- H2 : sur une grille paire, le motif classique « une colonne sur deux » ne peut pas être symétrique.
-- Axe de piliers symétrique proposé (x -> 17 - x) : {3, 5, 7, 10, 12, 14}. Un pilier existe en (x, y)
-- lorsque x ET y appartiennent à cet axe. Les lignes/colonnes 1-2 et 15-16 restent libres.
MapConfig.PillarAxis = table.freeze({ 3, 5, 7, 10, 12, 14 })

-- Densité des caisses parmi les cases libres hors zones de spawn. PROPOSITION : à équilibrer.
MapConfig.CrateDensity = 0.55

-- Nombre de cases libres exigées autour de chaque spawn (distance de Manhattan <= SpawnSafeDistance).
MapConfig.SpawnSafeDistance = 2

-- Sorties accessibles minimales exigées autour de chaque spawn avant validation de la map.
MapConfig.MinSpawnExits = 2

-- Nombre maximal de régénérations avant d'utiliser la map de secours (sans caisse aléatoire).
MapConfig.MaxGenerationAttempts = 20

-- 8 spawns symétriques par rotation de 90° : 4 coins puis 4 milieux de côté.
MapConfig.Spawns = table.freeze({
	table.freeze({ x = 1, y = 1 }),
	table.freeze({ x = 16, y = 16 }),
	table.freeze({ x = 16, y = 1 }),
	table.freeze({ x = 1, y = 16 }),
	table.freeze({ x = 8, y = 1 }),
	table.freeze({ x = 9, y = 16 }),
	table.freeze({ x = 16, y = 8 }),
	table.freeze({ x = 1, y = 9 }),
}) :: { Types.Cell }

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
