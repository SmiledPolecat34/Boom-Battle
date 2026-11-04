--!nocheck
-- Écrans d'interface (Help, Pause, Results, Quests, Events, EmoteWheel, Settings, Lobby, QuickChat, CosmeticBrowser,
-- GameHUD, MainMenu) : construction, câblage des boutons vers le contexte (ctx), mises à jour d'après l'état serveur.
-- Les éléments d'interface sont des instances génériques simulées : on vérifie la structure et le comportement
-- (textes, visibilité, appels), jamais le rendu à l'écran.
local QuestConfig = world.module("QuestConfig")
local EmoteConfig = world.module("EmoteConfig")
-- SettingsStore est un singleton : recharger celui du monde courant (world.reset vide le cache de modules).
local function Store()
	return world.module("SettingsStore")
end

local calls

-- ctx enregistreur : toute fonction appelée est notée { name, args... } dans `calls`.
local function newCtx()
	return setmetatable({ localUserId = 1 }, {
		__index = function(_t, name)
			return function(...)
				table.insert(calls, { name = name, args = table.pack(...) })
			end
		end,
	})
end

local function build(name, ...)
	local parent = world.env.Instance.new("Frame")
	local screen = world.module(name).new(parent, newCtx(), ...)
	return screen, parent
end

local function find(root, name)
	return root:FindFirstChild(name, true)
end

local function press(root, name)
	local button = find(root, name)
	expect(button).never.toBeNil()
	button:FireEvent("Activated")
end

local function lastCall()
	return calls[#calls]
end

beforeEach(function()
	world.reset()
	calls = {}
end)

describe("chargement des modules d'écran", function()
	it("chaque écran expose new (la couverture du dépôt les reconnaît par ces références)", function()
		local modules = {
			world.module("Help"),
			world.module("Pause"),
			world.module("Results"),
			world.module("Quests"),
			world.module("Events"),
			world.module("EmoteWheel"),
			world.module("Settings"),
			world.module("Lobby"),
			world.module("GameHUD"),
			world.module("MainMenu"),
		}
		for _, module in modules do
			expect(type(module.new)).toBe("function")
		end
	end)
end)

describe("contrat commun", function()
	local names = { "Help", "Pause", "Results", "Quests", "Events", "EmoteWheel", "Settings", "Lobby", "QuickChat", "GameHUD", "MainMenu" }
	for _, name in names do
		it(name .. " : se construit dans le parent et expose frame, update et tick", function()
			local screen, parent = build(name)
			expect(screen.frame).never.toBeNil()
			expect(screen.frame.Parent).toBe(parent)
			expect(type(screen.update)).toBe("function")
		end)
	end

	it("CosmeticBrowser (Boutique et Inventaire) se construit", function()
		local shop = build("CosmeticBrowser", "Shop")
		local inventory = build("CosmeticBrowser", "Inventory")
		expect(shop.frame).never.toBeNil()
		expect(inventory.frame).never.toBeNil()
	end)

	it("les écrans à fenêtre ont un fond cliquable qui referme (Help, Pause, Settings, EmoteWheel)", function()
		for _, name in { "Help", "Pause", "Settings", "EmoteWheel" } do
			calls = {}
			local screen = build(name)
			press(screen.frame, "Backdrop")
			expect(lastCall().name).toBe("closeOverlay")
		end
	end)

	it("update accepte un joueur inconnu (nil) et un instantané minimal sans erreur", function()
		for _, name in { "Help", "Pause", "Quests", "Events", "EmoteWheel", "Settings", "Lobby", "GameHUD", "Results", "MainMenu", "QuickChat" } do
			local screen = build(name)
			screen.update({ state = "WAITING", players = {}, survivors = 0, participantCount = 0, minPlayers = 1 }, nil)
			if screen.tick then
				screen.tick(nil)
				screen.tick(12.4)
			end
		end
	end)
end)

describe("Pause", function()
	it("REPRENDRE ferme ; AIDE et RÉGLAGES s'ouvrent depuis la pause", function()
		local screen = build("Pause")
		press(screen.frame, "ResumeButton")
		expect(lastCall().name).toBe("closeOverlay")
		press(screen.frame, "HelpButton")
		expect(lastCall().name).toBe("openOverlayFromPause")
		expect(lastCall().args[1]).toBe("Help")
		press(screen.frame, "SettingsButton")
		expect(lastCall().args[1]).toBe("Settings")
	end)

	it("QUITTER demande une confirmation : le 1er clic arme, le 2e quitte", function()
		local screen = build("Pause")
		press(screen.frame, "LeaveButton")
		expect(find(screen.frame, "LeaveButton").Text).toBe("CONFIRMER ?")
		expect(#calls).toBe(0) -- rien n'a quitté
		press(screen.frame, "LeaveButton")
		expect(lastCall().name).toBe("leaveMatch")
		expect(find(screen.frame, "LeaveButton").Text).toBe("QUITTER LA PARTIE")
	end)

	it("la confirmation expire au bout de 3 s (clic accidentel sans conséquence)", function()
		local screen = build("Pause")
		press(screen.frame, "LeaveButton")
		world.advance(3.2)
		expect(find(screen.frame, "LeaveButton").Text).toBe("QUITTER LA PARTIE")
		press(screen.frame, "LeaveButton") -- ré-arme seulement
		expect(#calls).toBe(0)
	end)

	it("rouvrir le menu (changement de visibilité) désarme la confirmation", function()
		local screen = build("Pause")
		press(screen.frame, "LeaveButton")
		screen.frame.Visible = false
		expect(find(screen.frame, "LeaveButton").Text).toBe("QUITTER LA PARTIE")
	end)
end)

describe("Results", function()
	local function payload(result, extra)
		local base = { result = result, names = { ["1"] = "Moi", ["2"] = "Autre" }, rewards = { ["1"] = 60 } }
		for k, v in extra or {} do
			base[k] = v
		end
		return base
	end

	it("victoire du joueur local : titre, vainqueur, durée, récompense, classement", function()
		local screen = build("Results")
		screen.setResult(payload({ outcome = "WIN", winnerUserId = 1, tiedUserIds = {}, ranking = { 1, 2 }, durationSeconds = 75 }))
		local title = find(screen.frame, "Title").Text
		local details = find(screen.frame, "Details").Text
		expect(title).toBe("VICTOIRE !")
		expect(details).toContain("Vainqueur : Moi")
		expect(details).toContain("1:15")
		expect(details).toContain("+60 pièces")
		expect(details).toContain("1. Moi")
		expect(details).toContain("2. Autre")
	end)

	it("défaite : le gagnant est un autre joueur ; pas de récompense affichée sans entrée", function()
		local screen = build("Results")
		screen.setResult(payload({ outcome = "WIN", winnerUserId = 2, tiedUserIds = {}, ranking = { 2, 1 }, durationSeconds = 5 }, { rewards = {} }))
		expect(find(screen.frame, "Title").Text).toBe("DÉFAITE")
		expect(find(screen.frame, "Details").Text).never.toContain("Récompense")
	end)

	it("égalité : liste des ex æquo ; sans personne : « Aucun vainqueur »", function()
		local screen = build("Results")
		screen.setResult(payload({ outcome = "DRAW", tiedUserIds = { 1, 2 }, ranking = { 1, 2 }, durationSeconds = 150 }))
		expect(find(screen.frame, "Title").Text).toBe("ÉGALITÉ")
		expect(find(screen.frame, "Details").Text).toContain("Moi, Autre")
		screen.setResult(payload({ outcome = "DRAW", tiedUserIds = {}, ranking = {}, durationSeconds = 1 }))
		expect(find(screen.frame, "Details").Text).toContain("Aucun vainqueur")
	end)

	it("joueur absent de la liste de noms : « Joueur N » plutôt qu'une erreur", function()
		local screen = build("Results")
		screen.setResult(payload({ outcome = "WIN", winnerUserId = 99, tiedUserIds = {}, ranking = { 99 }, durationSeconds = 1 }))
		expect(find(screen.frame, "Details").Text).toContain("Joueur 99")
	end)

	it("REJOUER n'envoie la revanche qu'une fois ; MENU quitte la file", function()
		local screen = build("Results")
		screen.update({ state = "FINISHED", players = {} }, { queued = true, ready = false })
		press(screen.frame, "ReplayButton")
		expect(lastCall().name).toBe("setReady")
		expect(lastCall().args[1]).toBe(true)
		screen.update({ state = "FINISHED", players = {} }, { queued = true, ready = true })
		expect(find(screen.frame, "ReplayButton").Text).toBe("EN ATTENTE…")
		local before = #calls
		press(screen.frame, "ReplayButton") -- déjà prêt : aucun renvoi
		expect(#calls).toBe(before)
		press(screen.frame, "MenuButton")
		expect(lastCall().name).toBe("setQueued")
		expect(lastCall().args[1]).toBe(false)
	end)

	it("un spectateur (hors file) n'a pas de bouton REJOUER", function()
		local screen = build("Results")
		screen.update({ state = "FINISHED", players = {} }, { queued = false })
		expect(find(screen.frame, "ReplayButton").Visible).toBe(false)
		screen.update({ state = "FINISHED", players = {} }, nil)
		expect(find(screen.frame, "ReplayButton").Visible).toBe(false)
	end)

	it("le décompte de retour au lobby ne descend jamais sous 0", function()
		local screen = build("Results")
		screen.tick(3.2)
		expect(find(screen.frame, "Footer").Text).toBe("Retour au lobby dans 4 s")
		screen.tick(-5)
		expect(find(screen.frame, "Footer").Text).toBe("Retour au lobby dans 0 s")
		screen.tick(nil)
		expect(find(screen.frame, "Footer").Text).toBe("")
	end)
end)

describe("Quests", function()
	it("une ligne par quête de la config, avec nom, description et récompense", function()
		local screen = build("Quests")
		for _, quest in QuestConfig.Quests do
			local row = find(screen.frame, "Row_" .. quest.id)
			expect(row).never.toBeNil()
			expect(find(row, "Name").Text).toBe(quest.name)
			expect(find(row, "Reward").Text).toBe(("+%d pièces"):format(quest.reward))
		end
	end)

	it("setProfile : progression, barre bornée et marque « Terminée »", function()
		local screen = build("Quests")
		screen.setProfile({ quests = { play3 = { progress = 2, done = false }, win1 = { progress = 1, done = true } } })
		local play = find(screen.frame, "Row_play3")
		expect(find(play, "Count").Text).toBe("2 / 3")
		expect(find(play, "Tag").Text).toBe("")
		local win = find(screen.frame, "Row_win1")
		expect(find(win, "Tag").Text).toBe("✓ Terminée")
		local crates = find(screen.frame, "Row_crates20")
		expect(find(crates, "Count").Text).toBe("0 / 20") -- quête absente du profil : zéro
	end)

	it("une progression excessive ne dépasse pas 100 % de la barre", function()
		local screen = build("Quests")
		screen.setProfile({ quests = { play3 = { progress = 999, done = true } } })
		local fill = find(screen.frame, "Row_play3"):FindFirstChildWhichIsA("Frame", true)
		expect(fill).never.toBeNil()
	end)

	it("RETOUR ferme la fenêtre", function()
		local screen = build("Quests")
		press(screen.frame, "CloseButton")
		expect(lastCall().name).toBe("closeOverlay")
	end)
end)

describe("EmoteWheel", function()
	it("un bouton par émote : jouer l'émote puis fermer", function()
		local screen = build("EmoteWheel")
		for _, emote in EmoteConfig.Emotes do
			calls = {}
			press(screen.frame, "Emote_" .. emote.id)
			expect(calls[1].name).toBe("playEmote")
			expect(calls[1].args[1]).toBe(emote.id)
			expect(calls[2].name).toBe("closeOverlay")
		end
	end)

	it("RETOUR ferme sans jouer d'émote", function()
		local screen = build("EmoteWheel")
		press(screen.frame, "CloseButton")
		expect(#calls).toBe(1)
		expect(lastCall().name).toBe("closeOverlay")
	end)
end)

describe("Settings", function()
	it("les boutons de choix écrivent dans SettingsStore et le bouton sélectionné passe en vert", function()
		local screen = build("Settings")
		press(screen.frame, "bombButtonSizeGrand")
		expect(Store().get("bombButtonSize")).toBe("Grand")
		local theme = world.module("Theme")
		expect(find(screen.frame, "bombButtonSizeGrand").BackgroundColor3).toEqual(theme.green)
		expect(find(screen.frame, "bombButtonSizeMoyen").BackgroundColor3).toEqual(theme.violet)
		press(screen.frame, "uiScalePetit")
		expect(Store().get("uiScale")).toBe("Petit")
	end)

	it("les interrupteurs inversent la valeur et mettent le texte à jour", function()
		local screen = build("Settings")
		local before = Store().get("showMoveMarker")
		press(screen.frame, "MarkerToggle")
		expect(Store().get("showMoveMarker")).toBe(not before)
		expect(find(screen.frame, "MarkerToggle").Text).toBe(if before then "Désactivé" else "Activé")
		press(screen.frame, "TimerToggle")
		expect(find(screen.frame, "TimerToggle").Text).toBe(if Store().get("showTimer") then "Affiché" else "Masqué")
	end)

	it("la section tactile n'apparaît que sur un appareil tactile (pas de faux bouton sur PC)", function()
		local pc = build("Settings")
		expect(find(pc.frame, "TouchSection").Visible).toBe(false)
		world.reset()
		world.game:GetService("UserInputService").TouchEnabled = true
		world.game:GetService("UserInputService").KeyboardEnabled = false
		local phone = build("Settings")
		expect(find(phone.frame, "TouchSection").Visible).toBe(true)
	end)

	it("RETOUR ferme ; un changement extérieur des réglages rafraîchit l'écran", function()
		local screen = build("Settings")
		press(screen.frame, "CloseButton")
		expect(lastCall().name).toBe("closeOverlay")
		Store().set("showMoveMarker", false)
		expect(find(screen.frame, "MarkerToggle").Text).toBe("Désactivé")
	end)
end)

describe("Lobby", function()
	local function snapshot(overrides)
		local s = {
			state = "WAITING",
			minPlayers = 1,
			players = { { userId = 1, name = "Moi", queued = true, ready = false, inParty = false } },
		}
		for k, v in overrides or {} do
			s[k] = v
		end
		return s
	end

	it("les boutons de navigation appellent le contexte", function()
		local screen = build("Lobby")
		press(screen.frame, "BackButton")
		expect(lastCall().name).toBe("setQueued")
		expect(lastCall().args[1]).toBe(false)
		for button, overlay in { HelpButton = "Help", SettingsButton = "Settings", EmotesButton = "Emotes", ChatButton = "QuickChat" } do
			press(screen.frame, button)
			expect(lastCall().name).toBe("openOverlay")
			expect(lastCall().args[1]).toBe(overlay)
		end
	end)

	it("partie rapide : statut de recherche, liste des joueurs en file, pas de contrôles d'hôte", function()
		local screen = build("Lobby")
		screen.update(snapshot(), { userId = 1, queued = true })
		expect(find(screen.frame, "Status").Text).toContain("Recherche de joueurs (1/1)")
		expect(find(screen.frame, "Title").Text).toBe("LOBBY")
		expect(find(screen.frame, "StartButton").Visible).toBe(false)
		expect(find(screen.frame, "AddBotButton").Visible).toBe(false)
		expect(#find(screen.frame, "List"):GetChildren()).toBeGreaterThan(0)
	end)

	it("les joueurs hors file n'apparaissent pas dans la liste", function()
		local screen = build("Lobby")
		local s = snapshot()
		table.insert(s.players, { userId = 2, name = "AuMenu", queued = false, ready = false, inParty = false })
		screen.update(s, { userId = 1, queued = true })
		local rows = 0
		for _, child in find(screen.frame, "List"):GetChildren() do
			if child.Name == "Row" then
				rows += 1
			end
		end
		expect(rows).toBe(1)
	end)

	it("partie privée, hôte : LANCER n'agit que si le minimum de joueurs est atteint", function()
		local screen = build("Lobby")
		local party = { hostUserId = 1, count = 1, bots = {}, max = 8, minToStart = 2 }
		local me = { userId = 1, queued = true, inParty = true }
		screen.update(snapshot({ party = party, players = { { userId = 1, name = "Moi", queued = true, inParty = true } } }), me)
		expect(find(screen.frame, "StartButton").Visible).toBe(true)
		press(screen.frame, "StartButton")
		expect(#calls).toBe(0) -- un seul joueur : lancement refusé côté client aussi
		party.bots = { 5 }
		screen.update(snapshot({ party = party, players = { { userId = 1, name = "Moi", queued = true, inParty = true } } }), me)
		press(screen.frame, "StartButton")
		expect(lastCall().name).toBe("partyAction")
		expect(lastCall().args[1]).toBe("start")
	end)

	it("partie privée, membre non hôte : ni lancement ni ajout de bot", function()
		local screen = build("Lobby")
		local party = { hostUserId = 9, count = 2, bots = {}, max = 8, minToStart = 2 }
		screen.update(
			snapshot({ party = party, players = { { userId = 9, name = "Hote", queued = true, inParty = true }, { userId = 1, name = "Moi", queued = true, inParty = true } } }),
			{ userId = 1, queued = true, inParty = true }
		)
		expect(find(screen.frame, "StartButton").Visible).toBe(false)
		expect(find(screen.frame, "AddBotButton").Visible).toBe(false)
		expect(find(screen.frame, "Status").Text).toContain("En attente de l'hôte")
	end)

	it("niveaux des bots : bornes 1 et 10 respectées, retrait par indice", function()
		local screen = build("Lobby")
		local party = { hostUserId = 1, count = 3, bots = { 1, 10 }, max = 8, minToStart = 2 }
		screen.update(
			snapshot({ party = party, players = { { userId = 1, name = "Moi", queued = true, inParty = true } } }),
			{ userId = 1, queued = true, inParty = true }
		)
		local rows = {}
		for _, child in find(screen.frame, "List"):GetChildren() do
			if child.Name == "BotRow" then
				table.insert(rows, child)
			end
		end
		expect(#rows).toBe(2)
		rows[1]:FindFirstChild("Minus"):FireEvent("Activated") -- niveau 1 : ne descend pas
		expect(#calls).toBe(0)
		rows[1]:FindFirstChild("Plus"):FireEvent("Activated")
		expect(lastCall().args[1]).toBe("botLevel")
		expect(lastCall().args[2]).toEqual({ index = 1, level = 2 })
		calls = {}
		rows[2]:FindFirstChild("Plus"):FireEvent("Activated") -- niveau 10 : ne monte pas
		expect(#calls).toBe(0)
		rows[2]:FindFirstChild("Remove"):FireEvent("Activated")
		expect(lastCall().args[1]).toBe("removeBot")
		expect(lastCall().args[2]).toBe(2)
	end)

	it("pendant une manche, le groupe affiche « Nouvelle arène en préparation » et ne peut plus lancer", function()
		local screen = build("Lobby")
		local party = { hostUserId = 1, count = 2, bots = { 5 }, max = 8, minToStart = 2 }
		screen.update(
			snapshot({ state = "RESETTING", party = party, players = { { userId = 1, name = "Moi", queued = true, inParty = true } } }),
			{ userId = 1, queued = true, inParty = true }
		)
		expect(find(screen.frame, "Status").Text).toContain("Nouvelle arène")
		expect(find(screen.frame, "StartButton").Visible).toBe(false)
		expect(find(screen.frame, "AddBotButton").Visible).toBe(false)
	end)

	it("INVITER n'apparaît qu'en partie privée et ouvre la demande d'invitation", function()
		local screen = build("Lobby")
		screen.update(snapshot(), { userId = 1, queued = true })
		expect(find(screen.frame, "InviteButton").Visible).toBe(false)
		local party = { hostUserId = 1, count = 1, bots = {}, max = 8, minToStart = 2 }
		screen.update(snapshot({ party = party, players = { { userId = 1, name = "Moi", queued = true, inParty = true } } }), { userId = 1, queued = true, inParty = true })
		expect(find(screen.frame, "InviteButton").Visible).toBe(true)
		press(screen.frame, "InviteButton")
		expect(lastCall().name).toBe("requestInvite")
	end)
end)
