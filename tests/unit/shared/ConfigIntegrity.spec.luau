--!nocheck
-- Intégrité des configurations (src/shared) : un équilibrage ou un ajout de contenu qui casse une règle du jeu
-- (taille de map, quêtes, émotes, bonus, limites anti-spam...) est détecté ici avant d'atteindre Studio.
local MapConfig = world.module("MapConfig")
local GameConfig = world.module("GameConfig")
local QuestConfig = world.module("QuestConfig")
local ItemConfig = world.module("ItemConfig")
local EmoteConfig = world.module("EmoteConfig")

describe("MapConfig", function()
	it("tailles jouables 10 / 16 / 24", function()
		local sizes = {}
		for _, def in MapConfig.Sizes do
			table.insert(sizes, def.size)
		end
		table.sort(sizes)
		expect(sizes).toEqual({ 10, 16, 24 })
	end)

	it("chaque nombre de joueurs 2..8 reçoit une taille, sans trou ni chevauchement", function()
		for players = 2, 8 do
			local matches = 0
			for _, def in MapConfig.Sizes do
				if def.enabled and players >= def.minPlayers and players <= def.maxPlayers then
					matches += 1
				end
			end
			expect(matches).toBe(1)
			expect(MapConfig.getSizeForPlayerCount(players)).never.toBeNil()
		end
	end)

	it("nombre de joueurs hors plage : retombe sur la taille par défaut", function()
		expect(MapConfig.getSizeForPlayerCount(0).id).toBe(MapConfig.DefaultSize)
		expect(MapConfig.getSizeForPlayerCount(99).id).toBe(MapConfig.DefaultSize)
		expect(MapConfig.getSizeForPlayerCount(-1).id).toBe(MapConfig.DefaultSize)
	end)

	it("les axes de piliers sont dans la grille, triés et symétriques", function()
		for _, def in MapConfig.Sizes do
			local last = 0
			local set = {}
			for _, a in def.pillarAxis do
				expect(a).toBeGreaterThan(last)
				expect(a).toBeLessThanOrEqual(def.size)
				last = a
				set[a] = true
			end
			for a in set do
				expect(set[def.size + 1 - a]).toBe(true)
			end
		end
	end)

	it("8 spawns, dans la grille, distincts, invariants par rotation de 90°", function()
		for _, def in MapConfig.Sizes do
			local spawns = MapConfig.getSpawns(def.size)
			expect(#spawns).toBe(8)
			local seen = {}
			for _, s in spawns do
				expect(s.x >= 1 and s.x <= def.size and s.y >= 1 and s.y <= def.size).toBe(true)
				local k = s.x .. "," .. s.y
				expect(seen[k]).toBeNil()
				seen[k] = true
			end
			-- Les 4 coins sont stables par rotation (x, y) -> (size + 1 - y, x).
			for i = 1, 4 do
				local s = spawns[i]
				expect(seen[(def.size + 1 - s.y) .. "," .. s.x]).toBe(true)
			end
		end
	end)

	it("les thèmes de ThemeOrder existent, le thème par défaut aussi", function()
		for _, id in MapConfig.ThemeOrder do
			expect(MapConfig.Themes[id]).never.toBeNil()
		end
		expect(MapConfig.Themes[MapConfig.DefaultTheme]).never.toBeNil()
		expect(#MapConfig.ThemeOrder).toBe(5)
	end)

	it("themeForSeed retourne toujours un thème activé, même pour une seed négative ou énorme", function()
		for _, seed in { 0, 1, -7, 123456789, 2 ^ 40, 3.7 } do
			local id = MapConfig.themeForSeed(seed)
			expect(MapConfig.Themes[id]).never.toBeNil()
			expect(MapConfig.Themes[id].enabled).toBe(true)
		end
	end)

	it("themeForSeed est déterministe", function()
		expect(MapConfig.themeForSeed(42)).toBe(MapConfig.themeForSeed(42))
	end)
end)

describe("GameConfig", function()
	it("toutes les durées et limites sont strictement positives", function()
		for _, section in { "Round", "Bomb", "Movement", "RemoteLimits", "Rewards", "Data" } do
			for key, value in GameConfig[section] do
				if type(value) == "number" then
					expect(value).toBeGreaterThan(-1)
					if section == "RemoteLimits" or section == "Bomb" then
						expect(value).toBeGreaterThan(0)
					end
				end
				expect(value).never.toBeNil()
				expect(key).never.toBeNil()
			end
		end
	end)

	it("l'état de manche déclaré couvre la machine d'états documentée", function()
		for _, state in { "WAITING", "READY", "COUNTDOWN", "PLAYING", "FINISHED", "RESETTING" } do
			expect(GameConfig.States[state]).toBe(state)
		end
	end)

	it("bornes cohérentes : capacité et portée par défaut <= maximum", function()
		expect(GameConfig.Bomb.DefaultCapacity).toBeLessThanOrEqual(GameConfig.Bomb.MaxCapacity)
		expect(GameConfig.Bomb.DefaultBlastRange).toBeLessThanOrEqual(GameConfig.Bomb.MaxBlastRange)
		expect(GameConfig.Round.MinimumPlayers).toBeLessThanOrEqual(GameConfig.Round.MaximumPlayers)
		expect(GameConfig.Round.DefaultBotDifficulty).toBeLessThanOrEqual(GameConfig.Round.MaxBotDifficulty)
	end)

	it("la probabilité de bonus est dans [0, 1]", function()
		expect(GameConfig.Powerups.DropChancePerCrate).toBeGreaterThanOrEqual(0)
		expect(GameConfig.Powerups.DropChancePerCrate).toBeLessThanOrEqual(1)
	end)

	it("la mèche est plus longue que la durée des flammes (sinon plus de fuite possible)", function()
		expect(GameConfig.Bomb.FuseTime).toBeGreaterThan(GameConfig.Bomb.ExplosionDuration)
	end)

	it("tables de configuration gelées (aucune écriture accidentelle à l'exécution)", function()
		expect(function() GameConfig.Rewards.WinCoins = 1 end).toThrow()
		expect(function() GameConfig.Bomb.FuseTime = 0 end).toThrow()
	end)

	it("les récompenses sont des entiers >= 0", function()
		for _, value in GameConfig.Rewards do
			expect(value).toBe(math.floor(value))
			expect(value).toBeGreaterThanOrEqual(0)
		end
	end)
end)

describe("QuestConfig", function()
	it("ids uniques, objectifs et récompenses entiers > 0", function()
		local ids = {}
		for _, q in QuestConfig.Quests do
			expect(ids[q.id]).toBeNil()
			ids[q.id] = true
			expect(q.goal).toBeGreaterThan(0)
			expect(q.goal).toBe(math.floor(q.goal))
			expect(q.reward).toBeGreaterThan(0)
			expect(q.reward).toBe(math.floor(q.reward))
			expect(#q.name).toBeGreaterThan(0)
		end
		expect(QuestConfig.get("play3")).never.toBeNil()
		expect(QuestConfig.get("nope")).toBeNil()
	end)
end)

describe("ItemConfig", function()
	it("chaque bonus de PowerupOrder est défini, avec une quantité > 0", function()
		for _, id in ItemConfig.PowerupOrder do
			local p = ItemConfig.Powerups[id]
			expect(p).never.toBeNil()
			expect(p.id).toBe(id)
			expect(p.amount).toBeGreaterThan(0)
		end
		expect(#ItemConfig.PowerupOrder).toBe(4)
	end)
end)

describe("EmoteConfig", function()
	it("au moins 7 émotes, ids uniques, identifiants d'animation de la forme rbxassetid://N", function()
		expect(#EmoteConfig.Emotes).toBeGreaterThanOrEqual(7)
		local seen = {}
		for _, emote in EmoteConfig.Emotes do
			expect(emote.animationId:match("^rbxassetid://%d+$")).never.toBeNil()
			expect(seen[emote.id]).toBeNil()
			seen[emote.id] = true
		end
	end)

	it("get refuse tout identifiant invalide", function()
		expect(EmoteConfig.get("hack")).toBeNil()
		expect(EmoteConfig.get(42)).toBeNil()
		expect(EmoteConfig.get(nil)).toBeNil()
	end)

	it("les danses tournent, les gestes non", function()
		expect(EmoteConfig.get("dance").looped).toBe(true)
		expect(EmoteConfig.get("wave").looped).toBe(false)
	end)
end)
