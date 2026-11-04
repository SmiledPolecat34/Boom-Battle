--!nocheck
-- RewardService (récompenses de manche), QuestService (quêtes), PlayerDataService + DataBackend (persistance,
-- pannes, profil temporaire jamais sauvegardé). Tout se fait avec un stockage mémoire / un DataStore simulé.
local GameConfig = world.module("GameConfig")
local QuestConfig = world.module("QuestConfig")
local ProfileSchema = world.module("ProfileSchema")
local RewardService = world.module("RewardService")
local QuestService = world.module("QuestService")
local PlayerDataService = world.module("PlayerDataService")
local DataBackend = world.module("DataBackend")
local GameEvents = world.module("GameEvents")

describe("RewardService.coinsFor", function()
	local win = { outcome = "WIN", winnerUserId = 1, tiedUserIds = {}, ranking = { 1, 2 }, durationSeconds = 30 }
	local draw = { outcome = "DRAW", tiedUserIds = { 3, 4 }, ranking = { 3, 4, 5 }, durationSeconds = 30 }

	it("vainqueur = participation + victoire ; perdant = participation", function()
		expect(RewardService.coinsFor(1, win)).toBe(GameConfig.Rewards.ParticipationCoins + GameConfig.Rewards.WinCoins)
		expect(RewardService.coinsFor(2, win)).toBe(GameConfig.Rewards.ParticipationCoins)
	end)

	it("égalité : bonus pour les ex æquo seulement", function()
		expect(RewardService.coinsFor(3, draw)).toBe(GameConfig.Rewards.ParticipationCoins + GameConfig.Rewards.DrawCoins)
		expect(RewardService.coinsFor(5, draw)).toBe(GameConfig.Rewards.ParticipationCoins)
	end)

	it("jamais négative, même pour un inconnu", function()
		expect(RewardService.coinsFor(999, win)).toBeGreaterThanOrEqual(0)
	end)
end)

describe("QuestService.apply", function()
	it("progression partielle sans récompense", function()
		local p = ProfileSchema.default()
		expect(#QuestService.apply(p, "round_played", 2)).toBe(0)
		expect(p.Coins).toBe(0)
		expect(p.QuestProgress.play3.progress).toBe(2)
	end)

	it("quête terminée : récompensée une seule fois", function()
		local p = ProfileSchema.default()
		QuestService.apply(p, "round_played", 2)
		local done = QuestService.apply(p, "round_played", 1)
		expect(done[1]).toBe("play3")
		expect(p.Coins).toBe(QuestConfig.get("play3").reward)
		local before = p.Coins
		expect(#QuestService.apply(p, "round_played", 5)).toBe(0)
		expect(p.Coins).toBe(before)
	end)

	it("événement inconnu, quantité négative, nulle, NaN ou non numérique : ignorés", function()
		local p = ProfileSchema.default()
		expect(#QuestService.apply(p, "n_importe_quoi", 5)).toBe(0)
		for _, bad in { -5, 0, 0 / 0, "5" } do
			expect(#QuestService.apply(p, "crates_destroyed", bad)).toBe(0)
		end
		expect(p.QuestProgress.crates20.progress).toBe(0)
	end)

	it("progression plafonnée à l'objectif", function()
		local p = ProfileSchema.default()
		QuestService.apply(p, "crates_destroyed", 15)
		local finished = QuestService.apply(p, "crates_destroyed", 15)
		expect(finished[1]).toBe("crates20")
		expect(p.QuestProgress.crates20.progress).toBe(20)
	end)

	it("une quête absente du profil est recréée", function()
		local p = ProfileSchema.default()
		p.QuestProgress.play3 = nil
		QuestService.apply(p, "round_played", 1)
		expect(p.QuestProgress.play3.progress).toBe(1)
	end)

	it("le solde ne dépasse jamais le plafond", function()
		local p = ProfileSchema.default()
		p.Coins = GameConfig.Data.MaxCoins
		QuestService.apply(p, "round_played", 3)
		expect(p.Coins).toBe(GameConfig.Data.MaxCoins)
	end)
end)

describe("DataBackend", function()
	it("mémoire : sauvegarde / chargement, joueur neuf => (true, nil)", function()
		local backend = DataBackend.memory()
		expect(backend.save("k", { a = 1 })).toBe(true)
		local ok, data = backend.load("k")
		expect(ok).toBe(true)
		expect(data.a).toBe(1)
		local okNew, none = backend.load("inconnu")
		expect(okNew).toBe(true)
		expect(none).toBeNil()
	end)

	it("mémoire : aucune référence partagée", function()
		local backend = DataBackend.memory()
		local source = { nested = { n = 1 } }
		backend.save("k", source)
		source.nested.n = 99
		local _, data = backend.load("k")
		expect(data.nested.n).toBe(1)
		data.nested.n = 50
		local _, again = backend.load("k")
		expect(again.nested.n).toBe(1)
	end)

	it("DataStore simulé : écriture puis lecture", function()
		local backend = DataBackend.datastore("TestStore")
		expect(backend.save("k", { v = 3 })).toBe(true)
		local ok, data = backend.load("k")
		expect(ok).toBe(true)
		expect(data.v).toBe(3)
	end)

	it("DataStore en panne : load et save renvoient false avec un message, sans lever d'erreur", function()
		local backend = DataBackend.datastore("TestStore")
		world.dataStoreFailure = "503 service indisponible"
		local ok, message = backend.load("k")
		expect(ok).toBe(false)
		expect(tostring(message)).toContain("503")
		local saved, err = backend.save("k", {})
		expect(saved).toBe(false)
		expect(err).toContain("503")
	end)
end)

describe("PlayerDataService", function()
	local backend
	beforeEach(function()
		backend = DataBackend.memory()
		PlayerDataService.setBackend(backend)
		world.dataStoreFailure = nil
		table.clear(world.warnings)
	end)

	it("joueur neuf : profil par défaut, persisté", function()
		local player = Fixtures.fakePlayer(1)
		PlayerDataService.load(player)
		expect(PlayerDataService.get(player).Coins).toBe(0)
		expect(PlayerDataService.isPersisted(player)).toBe(true)
	end)

	it("mutate sur un joueur non chargé retourne false", function()
		expect(PlayerDataService.mutate(Fixtures.fakePlayer(2), function() end)).toBe(false)
	end)

	it("T15 modification -> sauvegarde -> rechargement par un autre service", function()
		local player = Fixtures.fakePlayer(3)
		PlayerDataService.load(player)
		expect(PlayerDataService.mutate(player, function(p)
			p.Coins = 123
			p.Wins = 2
		end)).toBe(true)
		expect(PlayerDataService.save(player)).toBe(true)
		local _, raw = backend.load("Player_3")
		local reloaded = ProfileSchema.sanitize(raw)
		expect(reloaded.Coins).toBe(123)
		expect(reloaded.Wins).toBe(2)
	end)

	it("une sauvegarde sans modification est un succès immédiat sans écriture", function()
		local writes = 0
		local original = backend.save
		backend.save = function(k, d)
			writes += 1
			return original(k, d)
		end
		local player = Fixtures.fakePlayer(4)
		PlayerDataService.load(player)
		expect(PlayerDataService.save(player)).toBe(true)
		expect(writes).toBe(0)
	end)

	it("chargement en échec : profil TEMPORAIRE, jamais sauvegardé (ne peut pas écraser les vraies données)", function()
		backend.save("Player_5", ProfileSchema.serialize((function() local p = ProfileSchema.default() p.Coins = 777 return p end)()))
		local realLoad = backend.load
		backend.load = function() return false, "panne réseau" end
		local player = Fixtures.fakePlayer(5)
		PlayerDataService.load(player)
		expect(PlayerDataService.isPersisted(player)).toBe(false)
		PlayerDataService.mutate(player, function(p) p.Coins = 5 end)
		expect(PlayerDataService.save(player)).toBe(false)
		backend.load = realLoad
		local _, raw = backend.load("Player_5")
		expect(raw.Coins).toBe(777) -- les vraies données sont intactes
		expect(#world.warnings).toBeGreaterThan(0)
	end)

	it("données corrompues dans le stockage : profil neuf valide, pas d'erreur", function()
		backend.save("Player_6", { Coins = "beaucoup", OwnedCosmetics = "x" })
		local player = Fixtures.fakePlayer(6)
		PlayerDataService.load(player)
		expect(PlayerDataService.get(player).Coins).toBe(0)
	end)

	it("version de données future : profil temporaire (jamais réécrit)", function()
		backend.save("Player_7", { DataVersion = GameConfig.Data.DataVersion + 5, Coins = 40 })
		local player = Fixtures.fakePlayer(7)
		PlayerDataService.load(player)
		expect(PlayerDataService.isPersisted(player)).toBe(false)
	end)

	it("sauvegarde en échec : réessaie MaxSaveRetries fois, renvoie false, reste « sale » pour la suite", function()
		local attempts = 0
		backend.save = function() attempts += 1 return false, "quota" end
		local player = Fixtures.fakePlayer(8)
		PlayerDataService.load(player)
		PlayerDataService.mutate(player, function(p) p.Coins = 9 end)
		expect(PlayerDataService.save(player)).toBe(false)
		expect(attempts).toBe(GameConfig.Data.MaxSaveRetries)
		-- le service redevient disponible : la sauvegarde suivante réussit et écrit bien la valeur
		backend.save = DataBackend.memory().save
		local fresh = DataBackend.memory()
		PlayerDataService.setBackend(fresh)
		expect(PlayerDataService.save(player)).toBe(true)
		local _, raw = fresh.load("Player_8")
		expect(raw.Coins).toBe(9)
	end)

	it("un joueur parti pendant le chargement n'est pas enregistré", function()
		local player = Fixtures.fakePlayer(9)
		player.Parent = nil
		PlayerDataService.load(player)
		expect(PlayerDataService.get(player)).toBeNil()
	end)

	it("l'événement Changed est déclenché à chaque modification", function()
		local player = Fixtures.fakePlayer(10)
		PlayerDataService.load(player)
		local fired = 0
		PlayerDataService.Changed:Connect(function() fired += 1 end)
		PlayerDataService.mutate(player, function(p) p.Coins = 1 end)
		PlayerDataService.mutate(player, function(p) p.Coins = 2 end)
		expect(fired).toBe(2)
	end)

	it("QuestService.progress + RewardService.awardRound : récompense unique par manche et par joueur", function()
		local player = Fixtures.fakePlayer(11)
		PlayerDataService.load(player)
		local result = { outcome = "WIN", winnerUserId = 11, tiedUserIds = {}, ranking = { 11 }, durationSeconds = 10 }
		local first = RewardService.awardRound(1, { player }, result)
		local second = RewardService.awardRound(1, { player }, result) -- même manche : ignorée
		expect(first["11"]).toBe(GameConfig.Rewards.ParticipationCoins + GameConfig.Rewards.WinCoins)
		expect(second["11"]).toBeNil()
		local profile = PlayerDataService.get(player)
		expect(profile.MatchesPlayed).toBe(1)
		expect(profile.Wins).toBe(1)
		RewardService.awardRound(2, { player }, result)
		expect(PlayerDataService.get(player).MatchesPlayed).toBe(2)
	end)

	it("awardRound ignore un joueur dont le profil n'est pas chargé", function()
		local player = Fixtures.fakePlayer(12)
		local result = { outcome = "WIN", winnerUserId = 12, tiedUserIds = {}, ranking = { 12 }, durationSeconds = 10 }
		expect(RewardService.awardRound(1, { player }, result)["12"]).toBeNil()
	end)

	it("QuestService.start : les caisses détruites font progresser la quête du poseur", function()
		local player = Fixtures.fakePlayer(13)
		PlayerDataService.load(player)
		world.addPlayer(player)
		QuestService.start()
		GameEvents.fireCratesDestroyed(13, 4)
		expect(PlayerDataService.get(player).QuestProgress.crates20.progress).toBe(4)
		GameEvents.fireCratesDestroyed(9999, 4) -- poseur inconnu (ou bot) : ignoré sans erreur
	end)
end)
