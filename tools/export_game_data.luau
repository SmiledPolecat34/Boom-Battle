--!nocheck
-- Exporte en JSON les données de jeu définies dans src/shared (cosmétiques, quêtes, cartes, thèmes, bonus, émotes,
-- phrases rapides, réglages), pour les afficher dans un outil externe (tableau de bord, documentation...).
--
--   lune run tools/export_game_data -- chemin/vers/game-data.json
--
-- Lecture seule : le script charge les configurations telles quelles (aucune modification de src/). Les couleurs
-- deviennent des chaînes « #rrggbb », les valeurs Enum leur nom court (« SmoothPlastic »), les vecteurs { x, y, z }.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("../tests/runner/loader")

local outputPath = process.args[#process.args]
if outputPath == nil or string.sub(outputPath, -5) ~= ".json" then
	print("Usage : lune run tools/export_game_data -- chemin/vers/game-data.json")
	process.exit(2)
end

local world = Loader.new(".")

local function hex(color)
	local function channel(value)
		return math.floor(value * 255 + 0.5)
	end
	return string.format("#%02x%02x%02x", channel(color.R), channel(color.G), channel(color.B))
end

-- Convertit récursivement une valeur de configuration en valeur sérialisable en JSON.
local function plain(value)
	local kind = type(value)
	if kind == "string" then
		return string.match(value, "^Enum%.%w+%.(%w+)$") or value
	elseif kind == "number" or kind == "boolean" then
		return value
	elseif kind == "table" then
		local count, isArray = 0, true
		for key in value do
			count += 1
			if type(key) ~= "number" then
				isArray = false
			end
		end
		if isArray and count == #value then
			local list = {}
			for index, item in value do
				list[index] = plain(item)
			end
			return list
		end
		local keys = {}
		for key in value do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		local object = {}
		for _, key in keys do
			local original = value[key]
			if original == nil then
				original = value[tonumber(key)]
			end
			if type(original) ~= "function" then
				object[key] = plain(original)
			end
		end
		return object
	elseif kind == "userdata" then
		if value.R ~= nil and value.G ~= nil and value.B ~= nil then
			return hex(value)
		elseif value.X ~= nil and value.Y ~= nil and value.Z ~= nil then
			return { x = value.X, y = value.Y, z = value.Z }
		end
	end
	return nil
end

local CosmeticConfig = world.module("CosmeticConfig")
local cosmetics = {}
for _, kind in { "bomb", "effect" } do
	cosmetics[kind] = {}
	for _, id in CosmeticConfig.idsOfKind(kind) do
		table.insert(cosmetics[kind], plain(CosmeticConfig.get(id)))
	end
end

local MapConfig = world.module("MapConfig")
local sizes = {}
for _, id in { "Small", "Medium", "Large" } do
	local definition = MapConfig.Sizes[id]
	local entry = plain(definition)
	entry.spawns = plain(MapConfig.getSpawns(definition.size))
	sizes[#sizes + 1] = entry
end
local themes = {}
for _, id in MapConfig.ThemeOrder do
	local entry = plain(MapConfig.Themes[id])
	entry.id = id
	themes[#themes + 1] = entry
end

local GameConfig = world.module("GameConfig")
local ItemConfig = world.module("ItemConfig")
local powerups = {}
for _, id in ItemConfig.PowerupOrder do
	powerups[#powerups + 1] = plain(ItemConfig.Powerups[id])
end

local data = {
	_commentaire = "Généré par tools/export_game_data.luau à partir de src/shared. Ne pas éditer à la main.",
	version = GameConfig.Version,
	cosmetics = cosmetics,
	cosmeticDefaults = plain(CosmeticConfig.Defaults),
	quests = plain(world.module("QuestConfig").Quests),
	map = {
		cellSize = MapConfig.CellSize,
		defaultSize = MapConfig.DefaultSize,
		defaultTheme = MapConfig.DefaultTheme,
		crateDensity = MapConfig.CrateDensity,
		spawnSafeDistance = MapConfig.SpawnSafeDistance,
		sizes = sizes,
		themes = themes,
	},
	powerups = powerups,
	emotes = {
		maxLoopSeconds = world.module("EmoteConfig").MaxLoopSeconds,
		list = plain(world.module("EmoteConfig").Emotes),
	},
	quickChat = {
		bubbleSeconds = world.module("QuickChatConfig").BubbleSeconds,
		maxRecents = world.module("QuickChatConfig").MaxRecents,
		maxFavorites = world.module("QuickChatConfig").MaxFavorites,
		defaultFavorites = plain(world.module("QuickChatConfig").DefaultFavorites),
		phrases = plain(world.module("QuickChatConfig").Phrases),
	},
	settings = {
		round = plain(GameConfig.Round),
		bomb = plain(GameConfig.Bomb),
		movement = plain(GameConfig.Movement),
		powerupDrops = plain(GameConfig.Powerups),
		remoteLimits = plain(GameConfig.RemoteLimits),
		rewards = plain(GameConfig.Rewards),
		data = plain(GameConfig.Data),
	},
}

fs.writeFile(outputPath, serde.encode("json", data, true))
print(("Données exportées vers %s"):format(outputPath))
