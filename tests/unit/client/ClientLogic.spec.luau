--!nocheck
-- Logique pure du client : PartySlots (emplacements d'invitation, limiteur), QuickChatStore (récents / favoris),
-- SettingsStore (réglages validés).
local QuickChatConfig = world.module("QuickChatConfig")
local PartySlots = world.module("PartySlots")
local QuickChatStore = world.module("QuickChatStore")
local SettingsStore = world.module("SettingsStore")

local function entry(id, name, queued, ready, friend)
	return { userId = id, name = name, queued = queued, ready = ready, isFriend = friend }
end

describe("PartySlots.compute", function()
	it("personne d'autre : 2 emplacements « + »", function()
		local s = PartySlots.compute({}, 2)
		expect(#s).toBe(2)
		expect(s[1].kind).toBe("invite")
		expect(PartySlots.openInvites(s)).toBe(2)
	end)

	it("1 joueur : 1 joueur + 1 « + », statut Prêt", function()
		local s = PartySlots.compute({ entry(5, "Ami", true, true, true) }, 2)
		expect(s[1].kind).toBe("player")
		expect(s[1].userId).toBe(5)
		expect(s[1].status).toBe("Prêt !")
		expect(PartySlots.openInvites(s)).toBe(1)
	end)

	it("2 joueurs : blocage à 2 (plus aucun « + »), statuts En attente / Au menu", function()
		local s = PartySlots.compute({ entry(5, "A", false, false, false), entry(6, "B", true, false, false) }, 2)
		expect(PartySlots.openInvites(s)).toBe(0)
		expect(s[1].status).toBe("En attente")
		expect(s[2].status).toBe("Au menu")
	end)

	it("jamais plus de 2 emplacements, amis d'abord", function()
		local s = PartySlots.compute({ entry(1, "Zoe", true, true, false), entry(2, "Bob", false, false, true), entry(3, "Ann", true, false, true), entry(4, "Max", true, true, false) }, 2)
		expect(#s).toBe(2)
		expect(s[1].userId).toBe(3)
		expect(s[2].userId).toBe(2)
	end)

	it("ordre stable à égalité (par nom)", function()
		local s = PartySlots.compute({ entry(9, "B", true, true, false), entry(8, "A", true, true, false) }, 2)
		expect(s[1].name).toBe("A")
	end)
end)

describe("PartySlots limiteur d'ouvertures (fenêtre glissante)", function()
	it("2 ouvertures par minute, la 3e est bloquée avec le temps d'attente", function()
		local limiter = PartySlots.newLimiter(2, 60)
		expect(select(1, PartySlots.tryAcquire(limiter, 0))).toBe(true)
		expect(select(1, PartySlots.tryAcquire(limiter, 10))).toBe(true)
		local ok, wait = PartySlots.tryAcquire(limiter, 20)
		expect(ok).toBe(false)
		expect(wait).toBeCloseTo(40)
	end)

	it("la fenêtre glisse : la plus ancienne sort après 60 s", function()
		local limiter = PartySlots.newLimiter(2, 60)
		PartySlots.tryAcquire(limiter, 0)
		PartySlots.tryAcquire(limiter, 10)
		expect(select(1, PartySlots.tryAcquire(limiter, 61))).toBe(true)
		expect(select(1, PartySlots.tryAcquire(limiter, 62))).toBe(false)
		expect(select(1, PartySlots.tryAcquire(limiter, 71))).toBe(true)
	end)
end)

describe("QuickChatConfig", function()
	it("phrases courtes, ids uniques, favoris par défaut valides", function()
		local ids = {}
		for _, phrase in QuickChatConfig.Phrases do
			expect(#phrase.text).toBeGreaterThan(0)
			expect(#phrase.text).toBeLessThanOrEqual(30)
			expect(ids[phrase.id]).toBeNil()
			ids[phrase.id] = true
		end
		for _, id in QuickChatConfig.DefaultFavorites do
			expect(QuickChatConfig.get(id)).never.toBeNil()
		end
	end)

	it("get refuse les identifiants invalides (jamais de texte libre)", function()
		expect(QuickChatConfig.get("<script>")).toBeNil()
		expect(QuickChatConfig.get({})).toBeNil()
		expect(QuickChatConfig.get(nil)).toBeNil()
	end)
end)

describe("QuickChatStore", function()
	it("récents : limités, plus récent en tête, sans doublon, inconnus ignorés", function()
		for _, id in { "gg", "nice", "rematch", "bye", "hello", "please", "ohno" } do
			QuickChatStore.addRecent(id)
		end
		local recents = QuickChatStore.getRecents()
		expect(#recents).toBe(QuickChatConfig.MaxRecents)
		expect(recents[1]).toBe("ohno")
		QuickChatStore.addRecent("hello")
		expect(QuickChatStore.getRecents()[1]).toBe("hello")
		expect(#QuickChatStore.getRecents()).toBe(QuickChatConfig.MaxRecents)
		QuickChatStore.addRecent("n_importe_quoi")
		expect(QuickChatStore.getRecents()[1]).toBe("hello")
	end)

	it("getRecents renvoie une copie (modifier le résultat ne change pas le store)", function()
		QuickChatStore.addRecent("gg")
		local copy = QuickChatStore.getRecents()
		table.clear(copy)
		expect(#QuickChatStore.getRecents()).toBeGreaterThan(0)
	end)

	it("favoris : ajout, retrait, inconnu refusé", function()
		local before = #QuickChatStore.getFavorites()
		expect(QuickChatStore.toggleFavorite("haha")).toBe(true)
		expect(#QuickChatStore.getFavorites()).toBe(before + 1)
		expect(QuickChatStore.toggleFavorite("haha")).toBe(true)
		expect(#QuickChatStore.getFavorites()).toBe(before)
		expect(QuickChatStore.toggleFavorite("zzz")).toBe(false)
	end)

	it("favoris : liste pleine => ajout refusé, mais retrait toujours possible", function()
		for _, phrase in QuickChatConfig.Phrases do
			if #QuickChatStore.getFavorites() < QuickChatConfig.MaxFavorites and not QuickChatStore.isFavorite(phrase.id) then
				QuickChatStore.toggleFavorite(phrase.id)
			end
		end
		expect(#QuickChatStore.getFavorites()).toBe(QuickChatConfig.MaxFavorites)
		for _, phrase in QuickChatConfig.Phrases do
			if not QuickChatStore.isFavorite(phrase.id) then
				expect(QuickChatStore.toggleFavorite(phrase.id)).toBe(false)
				break
			end
		end
		local first = QuickChatStore.getFavorites()[1]
		expect(QuickChatStore.toggleFavorite(first)).toBe(true)
	end)

	it("l'événement Changed est déclenché", function()
		local fired = 0
		QuickChatStore.Changed:Connect(function() fired += 1 end)
		QuickChatStore.addRecent("gg")
		expect(fired).toBeGreaterThan(0)
	end)
end)

describe("SettingsStore", function()
	it("valeur par défaut, valeur valide acceptée, valeur inconnue refusée", function()
		expect(SettingsStore.get("bombButtonSize")).toBe("Moyen")
		expect(SettingsStore.set("bombButtonSize", "Grand")).toBe(true)
		expect(SettingsStore.bombButtonPixels()).toBe(150)
		expect(SettingsStore.set("bombButtonSize", "Gigantesque")).toBe(false)
		expect(SettingsStore.get("bombButtonSize")).toBe("Grand")
	end)

	it("clé inconnue et type invalide refusés", function()
		expect(SettingsStore.set("n_importe_quoi", "x")).toBe(false)
		expect(SettingsStore.set("showMoveMarker", "oui")).toBe(false)
		expect(SettingsStore.set("showTimer", 1)).toBe(false)
		expect(SettingsStore.set("controlMode", 42)).toBe(false)
		expect(SettingsStore.set("controlMode", "Telepathie")).toBe(false)
	end)

	it("échelle d'interface", function()
		expect(SettingsStore.set("uiScale", "Petit")).toBe(true)
		expect(SettingsStore.uiScaleMultiplier()).toBeCloseTo(0.85)
	end)

	it("les booléens et modes de contrôle valides sont acceptés", function()
		expect(SettingsStore.set("showMoveMarker", false)).toBe(true)
		expect(SettingsStore.get("showMoveMarker")).toBe(false)
		expect(SettingsStore.set("flipControls", true)).toBe(true)
		expect(SettingsStore.set("joystickFollows", false)).toBe(true)
		expect(SettingsStore.set("controlMode", "Joystick")).toBe(true)
	end)

	it("Changed est déclenché à la modification", function()
		local fired = 0
		SettingsStore.Changed:Connect(function() fired += 1 end)
		SettingsStore.set("showTimer", false)
		expect(fired).toBeGreaterThan(0)
	end)
end)
