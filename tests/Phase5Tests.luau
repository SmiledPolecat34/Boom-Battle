--!nocheck
-- Tests de la Phase 5 : cinq thèmes sur le même générateur, trois tailles.
-- À EXÉCUTER DANS ROBLOX STUDIO : coller dans la barre de commande (mode Edit) après synchronisation Rojo.
-- Le test de construction crée puis détruit l'arène (Workspace.Arena) ; il ne touche à rien d'autre.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Lighting = game:GetService("Lighting")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local MapGenerator = require(ServerScriptService.Server.Services.MapGenerator)
local MapService = require(ServerScriptService.Server.Services.MapService)

local passed, failed = 0, 0
local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		warn(("ÉCHEC : %s %s"):format(name, detail or ""))
	end
end

local FIELDS = {
	"displayName", "floorColorA", "floorColorB", "floorAccentColor", "floorMaterial", "pillarColor", "pillarCapColor",
	"pillarMaterial", "crateColor", "crateLidColor", "crateMaterial", "borderColor", "borderMaterial", "groundColor",
	"groundMaterial", "decorKinds", "decorPrimary", "decorSecondary", "lighting",
}

local function gridsEqual(a, b): boolean
	for y = 1, a.size do
		for x = 1, a.size do
			if a.cells[y][x] ~= b.cells[y][x] then
				return false
			end
		end
	end
	return true
end

-- Configuration ---------------------------------------------------------------------------------------------
check("5 thèmes ordonnés", #MapConfig.ThemeOrder == 5)
for _, id in MapConfig.ThemeOrder do
	local theme = MapConfig.Themes[id]
	check(id .. " : défini", theme ~= nil)
	if theme then
		local missing = {}
		for _, field in FIELDS do
			if theme[field] == nil then
				table.insert(missing, field)
			end
		end
		check(id .. " : tous les champs présents", #missing == 0, table.concat(missing, ","))
		check(id .. " : activé", theme.enabled)
		check(id .. " : décors valides", #theme.decorKinds > 0)
		-- Lisibilité : la caisse doit se distinguer du sol et des murs (écart de luminance minimal).
		local function lum(c: Color3) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end
		local dFloor = math.abs(lum(theme.crateColor) - lum(theme.floorColorA))
		local dWall = math.abs(lum(theme.crateColor) - lum(theme.pillarColor))
		local colorDist = (Vector3.new(theme.crateColor.R, theme.crateColor.G, theme.crateColor.B)
			- Vector3.new(theme.floorColorA.R, theme.floorColorA.G, theme.floorColorA.B)).Magnitude
		check(id .. " : caisse distincte du sol", dFloor > 0.08 or colorDist > 0.35, ("lum %.2f, dist %.2f"):format(dFloor, colorDist))
		check(id .. " : caisse distincte du mur", dWall > 0.04 or (Vector3.new(theme.crateColor.R, theme.crateColor.G, theme.crateColor.B) - Vector3.new(theme.pillarColor.R, theme.pillarColor.G, theme.pillarColor.B)).Magnitude > 0.3)
	end
end

local seen = {}
for seed = 1, 50 do
	seen[MapConfig.themeForSeed(seed)] = true
end
local distinct = 0
for _ in seen do distinct += 1 end
check("themeForSeed : les 5 thèmes sortent sur 50 seeds", distinct == 5, tostring(distinct))
check("themeForSeed : déterministe", MapConfig.themeForSeed(1234) == MapConfig.themeForSeed(1234))

-- Génération : 5 thèmes x 3 tailles x 20 seeds ------------------------------------------------------------
for _, themeId in MapConfig.ThemeOrder do
	for sizeId, sizeDef in MapConfig.Sizes do
		local invalid, wrongTheme = 0, 0
		for seed = 1, 20 do
			local layout = MapGenerator.generate(sizeDef, seed, 8, themeId)
			if not MapGenerator.validate(layout.cells, layout.size, layout.spawns) then
				invalid += 1
			end
			if layout.theme ~= themeId then
				wrongTheme += 1
			end
		end
		check(("%s/%s : 20 maps valides"):format(themeId, sizeId), invalid == 0, tostring(invalid))
		check(("%s/%s : thème enregistré"):format(themeId, sizeId), wrongTheme == 0)
	end
end

-- La grille ne dépend PAS du thème (même moteur) : mêmes cases pour une même seed.
for _, sizeDef in MapConfig.Sizes do
	local base = MapGenerator.generate(sizeDef, 777, 8, "Classic")
	for _, themeId in MapConfig.ThemeOrder do
		check(("grille identique : %s vs Classic (%s)"):format(themeId, sizeDef.id), gridsEqual(base, MapGenerator.generate(sizeDef, 777, 8, themeId)))
	end
end
check("thème inconnu => défaut", MapGenerator.generate(MapConfig.Sizes.Medium, 5, 8, "Atlantide").theme == MapConfig.DefaultTheme)

-- Construction : 5 thèmes x 3 tailles ----------------------------------------------------------------------
local saved = { Lighting.ClockTime, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness }
for _, themeId in MapConfig.ThemeOrder do
	for sizeId, sizeDef in MapConfig.Sizes do
		local ok, info = pcall(MapService.generateAndBuild, sizeDef, 31, 8, themeId)
		check(("construction %s/%s"):format(themeId, sizeId), ok, tostring(info))
		if ok then
			local folder = info.folder
			local size = info.layout.size
			local half = size * MapConfig.CellSize / 2 + MapConfig.CellSize -- demi-largeur de la zone + anneau
			local decorInside, decorCollide, floors, crates, parts = 0, 0, 0, 0, 0
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
			for _, child in folder:GetChildren() do
				if child.Name:match("^Floor_") then floors += 1 end
				if child.Name:match("^Crate_") then crates += 1 end
			end
			for _, d in folder.Decor:GetDescendants() do
				if d:IsA("BasePart") then
					if d.CanCollide or d.CanQuery then decorCollide += 1 end
					if math.abs(d.Position.X) < half and math.abs(d.Position.Z) < half then decorInside += 1 end
				end
			end
			check(("%s/%s : %d sols"):format(themeId, sizeId, size * size), floors == size * size, tostring(floors))
			check(("%s/%s : caisses = grille"):format(themeId, sizeId), crates == (function() local n = 0 for _ in info.crates do n += 1 end return n end)())
			check(("%s/%s : décors sans collision"):format(themeId, sizeId), decorCollide == 0, tostring(decorCollide))
			check(("%s/%s : aucun décor dans la zone de jeu"):format(themeId, sizeId), decorInside == 0, tostring(decorInside))
			check(("%s/%s : attribut Theme"):format(themeId, sizeId), folder:GetAttribute("Theme") == themeId)
			if sizeId == "Large" and themeId == "Classic" then
				print(("[Phase5Tests] Large/Classic : %d Parts"):format(parts))
			end
		end
	end
end
MapService.destroy()
Lighting.ClockTime, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness = table.unpack(saved)
check("arène détruite proprement", workspace:FindFirstChild("Arena") == nil)

print(("[Phase5Tests] %d réussis, %d échecs"):format(passed, failed))
