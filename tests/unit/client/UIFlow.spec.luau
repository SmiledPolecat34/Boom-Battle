--!nocheck
-- Interface complète : CosmeticBrowser (boutique / inventaire), QuickChat, puis UIController qui assemble tous les
-- écrans (routage d'après l'état serveur, fenêtres, actions envoyées au serveur, toasts, échelle, minuteur) avec MainMenu
-- et GameHUD réels. Les éléments sont des instances génériques simulées ; on déclenche les boutons par leurs événements.
local CosmeticConfig = world.module("CosmeticConfig")
local QuickChatConfig = world.module("QuickChatConfig")

local calls

local function newCtx()
	return setmetatable({ localUserId = 1 }, {
		__index = function(_t, name)
			return function(...)
				table.insert(calls, { name = name, args = table.pack(...) })
			end
		end,
	})
end

local function find(root, name)
	return root:FindFirstChild(name, true)
end

local function press(root, name)
	local target = find(root, name)
	expect(target).never.toBeNil()
	target:FireEvent("Activated")
end

local function lastCall()
	return calls[#calls]
end

local function profile(overrides)
	local p = {
		coins = 300,
		wins = 0,
		matches = 0,
		owned = { bomb_classic = true, effect_classic = true },
		equipped = { bomb = "bomb_classic", effect = "effect_classic" },
		quests = {},
		persisted = true,
	}
	for k, v in overrides or {} do
		p[k] = v
	end
	return p
end

beforeEach(function()
	world.reset()
	calls = {}
end)

describe("CosmeticBrowser — boutique", function()
	local function shop()
		local parent = world.env.Instance.new("Frame")
		local screen = world.module("CosmeticBrowser").new(parent, newCtx(), "shop")
		return screen
	end

	it("sans profil : aucune action possible ; le solde apparaît dès réception du profil", function()
		local screen = shop()
		press(screen.frame, "Action")
		expect(#calls).toBe(0)
		expect(find(screen.frame, "Coins").Text).toBe("")
		screen.setProfile(profile({ coins = 10 }))
		expect(find(screen.frame, "Coins").Text).toBe("Pièces : 10")
	end)

	it("affiche toute l'offre avec prix ou état (équipé / possédé)", function()
		local screen = shop()
		screen.setProfile(profile())
		local ids = CosmeticConfig.idsOfKind("bomb")
		for _, id in ids do
			expect(find(screen.frame, "Card_" .. id)).never.toBeNil()
		end
		expect(find(find(screen.frame, "Card_bomb_classic"), "Status").Text).toBe("ÉQUIPÉ")
		expect(find(find(screen.frame, "Card_bomb_red"), "Status").Text).toBe(("%d pièces"):format(CosmeticConfig.get("bomb_red").price))
		expect(find(screen.frame, "Coins").Text).toBe("Pièces : 300")
	end)

	it("le catalogue de 24 bombes est entièrement dans la boutique (cartes + prix), l'inventaire n'affiche que les possédées", function()
		local screen = shop()
		screen.setProfile(profile())
		local cards = 0
		for _, id in CosmeticConfig.idsOfKind("bomb") do
			expect(find(screen.frame, "Card_" .. id)).never.toBeNil()
			cards += 1
		end
		expect(cards).toBe(24)
		expect(find(find(screen.frame, "Card_bomb_cosmic"), "Status").Text).toBe(("%d pièces"):format(CosmeticConfig.get("bomb_cosmic").price))
	end)

	it("le solde est formaté par milliers", function()
		local screen = shop()
		screen.setProfile(profile({ coins = 1234567 }))
		expect(find(screen.frame, "Coins").Text).toBe("Pièces : 1 234 567")
	end)

	it("acheter : le client demande l'identifiant ; le serveur revérifie (bouton grisé = simple aide)", function()
		local screen = shop()
		screen.setProfile(profile({ coins = 5 })) -- trop pauvre : le bouton est grisé mais la demande part quand même
		press(screen.frame, "Card_bomb_red")
		expect(find(screen.frame, "Action").Text).toContain("ACHETER")
		press(screen.frame, "Action")
		expect(lastCall().name).toBe("purchase")
		expect(lastCall().args[1]).toBe("bomb_red")
	end)

	it("objet possédé : ÉQUIPER envoie equip ; déjà équipé : aucune demande", function()
		local screen = shop()
		screen.setProfile(profile({ owned = { bomb_classic = true, bomb_red = true, effect_classic = true } }))
		press(screen.frame, "Card_bomb_red")
		expect(find(screen.frame, "Action").Text).toBe("ÉQUIPER")
		press(screen.frame, "Action")
		expect(lastCall().name).toBe("equip")
		expect(lastCall().args[1]).toBe("bomb_red")
		calls = {}
		press(screen.frame, "Card_bomb_classic")
		expect(find(screen.frame, "Action").Text).toBe("ÉQUIPÉ")
		press(screen.frame, "Action")
		expect(#calls).toBe(0)
	end)

	it("onglet EFFETS : liste les effets ; retour aux bombes", function()
		local screen = shop()
		screen.setProfile(profile())
		press(screen.frame, "Tab_effect")
		for _, id in CosmeticConfig.idsOfKind("effect") do
			expect(find(screen.frame, "Card_" .. id)).never.toBeNil()
		end
		expect(find(screen.frame, "Card_bomb_red")).toBeNil()
		press(screen.frame, "Tab_bomb")
		expect(find(screen.frame, "Card_bomb_red")).never.toBeNil()
	end)

	it("résultat du serveur : message de succès ou raison lisible ; charges invalides ignorées", function()
		local screen = shop()
		screen.onShopResult({ ok = true, action = "purchase" })
		expect(find(screen.frame, "Feedback").Text).toBe("Achat réussi !")
		screen.onShopResult({ ok = true, action = "equip" })
		expect(find(screen.frame, "Feedback").Text).toBe("Objet équipé.")
		-- achat d'une bombe : le serveur indique qu'elle est équipée automatiquement
		screen.onShopResult({ ok = true, action = "purchase", equipped = true })
		expect(find(screen.frame, "Feedback").Text).toBe("Achat réussi ! Objet équipé.")
		screen.onShopResult({ ok = true, action = "purchase", equipped = false })
		expect(find(screen.frame, "Feedback").Text).toBe("Achat réussi !")
		screen.onShopResult({ ok = false, error = "funds" })
		expect(#find(screen.frame, "Feedback").Text).toBeGreaterThan(0)
		screen.onShopResult({ ok = false, error = "inconnu" })
		expect(find(screen.frame, "Feedback").Text).toBe("Action impossible.")
		screen.onShopResult("x")
		screen.onShopResult(nil)
		expect(find(screen.frame, "Feedback").Text).toBe("Action impossible.")
	end)

	it("RETOUR ferme la fenêtre", function()
		local screen = shop()
		press(screen.frame, "CloseButton")
		expect(lastCall().name).toBe("closeOverlay")
	end)
end)

describe("CosmeticBrowser — inventaire", function()
	local function inventory()
		return world.module("CosmeticBrowser").new(world.env.Instance.new("Frame"), newCtx(), "inventory")
	end

	it("n'affiche que les objets possédés, jamais d'achat", function()
		local screen = inventory()
		screen.setProfile(profile({ owned = { bomb_classic = true, bomb_blue = true, effect_classic = true } }))
		expect(find(screen.frame, "Card_bomb_classic")).never.toBeNil()
		expect(find(screen.frame, "Card_bomb_blue")).never.toBeNil()
		expect(find(screen.frame, "Card_bomb_red")).toBeNil()
		press(screen.frame, "Action")
		expect(lastCall()).toBeNil() -- bomb_classic déjà équipé
	end)

	it("catégorie vide : message explicite", function()
		local screen = inventory()
		screen.setProfile(profile({ owned = {} }))
		expect(find(screen.frame, "Feedback").Text).toBe("Aucun objet dans cette catégorie.")
	end)
end)

describe("QuickChat", function()
	local function chat()
		return world.module("QuickChat").new(world.env.Instance.new("Frame"), newCtx())
	end

	it("favoris par défaut dans la colonne de droite, récents vides avec message d'aide", function()
		local screen = chat()
		expect(find(screen.frame, "Empty")).never.toBeNil()
		for _, id in QuickChatConfig.DefaultFavorites do
			expect(find(screen.frame, "Phrase_" .. id)).never.toBeNil()
		end
	end)

	it("une phrase : envoie l'IDENTIFIANT (jamais le texte) puis ferme", function()
		local screen = chat()
		local id = QuickChatConfig.DefaultFavorites[1]
		press(screen.frame, "Phrase_" .. id)
		expect(calls[1].name).toBe("sendQuickChat")
		expect(calls[1].args[1]).toBe(id)
		expect(calls[2].name).toBe("closeOverlay")
	end)

	it("les récents se mettent à jour quand le magasin change", function()
		local screen = chat()
		world.module("QuickChatStore").addRecent("gg")
		expect(find(screen.frame, "Empty")).toBeNil()
		local recents = find(screen.frame, "Recents")
		expect(find(recents, "Phrase_gg")).never.toBeNil()
	end)

	it("« + » ouvre le catalogue complet avec étoiles ; basculer un favori met à jour la liste", function()
		local screen = chat()
		press(screen.frame, "PlusButton")
		expect(find(screen.frame, "RightTitle").Text).toBe("Toutes")
		for _, phrase in QuickChatConfig.Phrases do
			expect(find(screen.frame, "Row_" .. phrase.id)).never.toBeNil()
		end
		local store = world.module("QuickChatStore")
		local candidate
		for _, phrase in QuickChatConfig.Phrases do
			if not store.isFavorite(phrase.id) then
				candidate = phrase.id
				break
			end
		end
		press(screen.frame, "Fav_" .. candidate)
		expect(store.isFavorite(candidate)).toBe(true)
		press(screen.frame, "PlusButton")
		expect(find(screen.frame, "RightTitle").Text).toBe("Favoris")
		expect(find(screen.frame, "Phrase_" .. candidate)).never.toBeNil()
	end)

	it("RETOUR et fond ferment", function()
		local screen = chat()
		press(screen.frame, "CloseButton")
		press(screen.frame, "Backdrop")
		expect(calls[1].name).toBe("closeOverlay")
		expect(calls[2].name).toBe("closeOverlay")
	end)
end)

describe("UIController (assemblage)", function()
	local remotes, UI, gui, screens

	local function start()
		remotes = Fixtures.fakeRemotes({
			"SetQueued", "SetReady", "RequestPlaceBomb", "RequestPurchase", "RequestEquip", "RequestEmote", "RequestQuickChat", "PartyAction",
		})
		UI = world.module("UIController")
		UI.start(remotes)
		gui = world.game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild("BombBattleUI")
		screens = gui:FindFirstChild("Root")
	end

	local function snapshot(state, me, extra)
		local s = { state = state, players = {}, survivors = 0, participantCount = 0, minPlayers = 1 }
		if me then
			me.userId = 1
			me.name = "Moi"
			table.insert(s.players, me)
		end
		for k, v in extra or {} do
			s[k] = v
		end
		return s
	end

	local function visibleMain()
		local list = {}
		for _, name in { "MainMenu", "Lobby", "GameHUD", "Results" } do
			if find(screens, name).Visible then
				table.insert(list, name)
			end
		end
		return list
	end

	local function overlayVisible(name)
		return find(screens, name).Visible
	end

	local MENU = { queued = false, participant = false, alive = false, ready = false }
	local PLAYING = { queued = true, participant = true, alive = true, ready = true }

	beforeEach(function()
		start()
	end)

	it("construit l'interface une seule fois dans PlayerGui, même si start est rappelé", function()
		UI.start(remotes)
		local count = 0
		for _, child in world.game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui"):GetChildren() do
			if child.Name == "BombBattleUI" then
				count += 1
			end
		end
		expect(count).toBe(1)
		expect(gui.ResetOnSpawn).toBe(false)
	end)

	it("routage : un seul écran principal visible à la fois, selon l'état serveur", function()
		UI.onSnapshot(snapshot("WAITING", table.clone(MENU)))
		expect(visibleMain()).toEqual({ "MainMenu" })
		UI.onSnapshot(snapshot("READY", { queued = true }))
		expect(visibleMain()).toEqual({ "Lobby" })
		UI.onSnapshot(snapshot("COUNTDOWN", table.clone(PLAYING)))
		expect(visibleMain()).toEqual({ "GameHUD" })
		UI.onSnapshot(snapshot("FINISHED", table.clone(PLAYING)))
		expect(visibleMain()).toEqual({ "Results" })
		expect(UI.getCurrentScreen()).toBe("Results")
	end)

	it("avant le premier message du serveur : le menu principal (jamais un écran vide)", function()
		expect(UI.getCurrentScreen()).toBe("MainMenu")
		expect(visibleMain()).toEqual({ "MainMenu" })
	end)

	it("joueur absent de l'instantané => menu principal", function()
		UI.onSnapshot(snapshot("PLAYING", nil))
		expect(UI.getCurrentScreen()).toBe("MainMenu")
	end)

	it("stop détruit l'interface et remet l'état à zéro ; on peut redémarrer", function()
		UI.onSnapshot(snapshot("PLAYING", table.clone(PLAYING)))
		UI.stop()
		expect(gui.destroyed).toBe(true)
		expect(UI.getCurrentScreen()).toBeNil()
		UI.start(remotes)
		local again = world.game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild("BombBattleUI")
		expect(again).never.toBeNil()
		expect(again).never.toBe(gui)
	end)

	it("PLAY envoie SetQueued(true) ; QUITTER du HUD envoie SetQueued(false)", function()
		UI.onSnapshot(snapshot("WAITING", table.clone(MENU)))
		press(screens, "PlayButton")
		expect(remotes.SetQueued.sentToServer[1][1]).toBe(true)
		UI.onSnapshot(snapshot("PLAYING", table.clone(PLAYING)))
	end)

	it("partie privée : crée un groupe, ou le rejoint quand il existe", function()
		UI.onSnapshot(snapshot("WAITING", table.clone(MENU)))
		press(screens, "PrivateButton")
		expect(remotes.PartyAction.sentToServer[1][1]).toBe("create")
		UI.onSnapshot(snapshot("WAITING", table.clone(MENU), { party = { hostUserId = 9, count = 1, bots = {}, max = 8, minToStart = 2 } }))
		expect(find(screens, "PrivateButton").Text).toContain("REJOINDRE (1/8)")
		press(screens, "PrivateButton")
		expect(remotes.PartyAction.sentToServer[2][1]).toBe("join")
	end)

	it("fenêtres : une seule ouverte à la fois, RETOUR la ferme", function()
		UI.onSnapshot(snapshot("WAITING", table.clone(MENU)))
		press(screens, "HelpButton")
		expect(overlayVisible("Help")).toBe(true)
		press(screens, "SettingsButton")
		expect(overlayVisible("Settings")).toBe(true)
		expect(overlayVisible("Help")).toBe(false)
		press(find(screens, "Settings"), "CloseButton")
		expect(overlayVisible("Settings")).toBe(false)
	end)

	it("en manche : Aide / Réglages sont refermés, Émotes / Chat / Pause restent autorisés", function()
		UI.onSnapshot(snapshot("READY", { queued = true }))
		press(screens, "HelpButton")
		expect(overlayVisible("Help")).toBe(true)
		UI.onSnapshot(snapshot("COUNTDOWN", table.clone(PLAYING)))
		expect(overlayVisible("Help")).toBe(false)
		press(find(screens, "GameHUD"), "EmotesButton")
		expect(overlayVisible("Emotes")).toBe(true)
		UI.onSnapshot(snapshot("PLAYING", table.clone(PLAYING)))
		expect(overlayVisible("Emotes")).toBe(true)
	end)

	it("menu pause : Aide s'ouvre depuis la pause et revient à la pause à la fermeture", function()
		UI.onSnapshot(snapshot("PLAYING", table.clone(PLAYING)))
		press(find(screens, "GameHUD"), "MenuButton")
		expect(overlayVisible("Pause")).toBe(true)
		press(find(screens, "Pause"), "HelpButton")
		expect(overlayVisible("Help")).toBe(true)
		expect(overlayVisible("Pause")).toBe(false)
		press(find(screens, "Help"), "Backdrop")
		expect(overlayVisible("Help")).toBe(false)
		expect(overlayVisible("Pause")).toBe(true)
	end)

	it("quitter la partie (2 clics) : demande SetQueued(false, true) et referme la pause", function()
		UI.onSnapshot(snapshot("PLAYING", table.clone(PLAYING)))
		press(find(screens, "GameHUD"), "MenuButton")
		press(find(screens, "Pause"), "LeaveButton")
		expect(#remotes.SetQueued.sentToServer).toBe(0)
		press(find(screens, "Pause"), "LeaveButton")
		expect(remotes.SetQueued.sentToServer[1][1]).toBe(false)
		expect(remotes.SetQueued.sentToServer[1][2]).toBe(true)
		expect(overlayVisible("Pause")).toBe(false)
	end)

	it("bombe : le bouton envoie la demande seulement quand le joueur peut poser", function()
		UI.onSnapshot(snapshot("COUNTDOWN", table.clone(PLAYING)))
		press(find(screens, "GameHUD"), "BombButton")
		expect(#remotes.RequestPlaceBomb.sentToServer).toBe(0)
		UI.onSnapshot(snapshot("PLAYING", table.clone(PLAYING)))
		press(find(screens, "GameHUD"), "BombButton")
		expect(#remotes.RequestPlaceBomb.sentToServer).toBe(1)
		UI.onSnapshot(snapshot("PLAYING", { queued = true, participant = true, alive = false }))
		press(find(screens, "GameHUD"), "BombButton")
		expect(#remotes.RequestPlaceBomb.sentToServer).toBe(1) -- éliminé : plus de demande
	end)

	it("raccourcis PC : Espace pose, M ouvre / ferme la pause, ignorés pendant une saisie de texte", function()
		UI.onSnapshot(snapshot("PLAYING", table.clone(PLAYING)))
		local uis = world.game:GetService("UserInputService")
		uis._fireInputBegan({ KeyCode = Enum.KeyCode.Space, UserInputType = Enum.UserInputType.Keyboard }, false)
		expect(#remotes.RequestPlaceBomb.sentToServer).toBe(1)
		uis._fireInputBegan({ KeyCode = Enum.KeyCode.M, UserInputType = Enum.UserInputType.Keyboard }, false)
		expect(overlayVisible("Pause")).toBe(true)
		uis._fireInputBegan({ KeyCode = Enum.KeyCode.M, UserInputType = Enum.UserInputType.Keyboard }, false)
		expect(overlayVisible("Pause")).toBe(false)
		uis.focusedTextBox = {}
		uis._fireInputBegan({ KeyCode = Enum.KeyCode.M, UserInputType = Enum.UserInputType.Keyboard }, false)
		expect(overlayVisible("Pause")).toBe(false)
	end)

	it("émotes : au menu, simple aperçu local ; en manche, demande au serveur ; identifiant inconnu impossible", function()
		UI.onSnapshot(snapshot("WAITING", table.clone(MENU)))
		press(screens, "EmotesButton")
		press(find(screens, "Emotes"), "Emote_wave")
		expect(#remotes.RequestEmote.sentToServer).toBe(0)
		UI.onSnapshot(snapshot("PLAYING", table.clone(PLAYING)))
		press(find(screens, "GameHUD"), "EmotesButton")
		press(find(screens, "Emotes"), "Emote_wave")
		expect(remotes.RequestEmote.sentToServer[1][1]).toBe("wave")
	end)

	it("chat rapide : au menu aperçu local, en manche l'identifiant part au serveur, les récents sont mémorisés", function()
		local id = QuickChatConfig.DefaultFavorites[1]
		UI.onSnapshot(snapshot("WAITING", table.clone(MENU)))
		press(screens, "ChatButton")
		press(find(screens, "QuickChat"), "Phrase_" .. id)
		expect(#remotes.RequestQuickChat.sentToServer).toBe(0)
		UI.onSnapshot(snapshot("PLAYING", table.clone(PLAYING)))
		press(find(screens, "GameHUD"), "ChatButton")
		press(find(screens, "QuickChat"), "Phrase_" .. id)
		expect(remotes.RequestQuickChat.sentToServer[1][1]).toBe(id)
		expect(world.module("QuickChatStore").getRecents()[1]).toBe(id)
	end)

	it("boutique : achat et équipement passent par les remotes avec le seul identifiant", function()
		UI.onSnapshot(snapshot("WAITING", table.clone(MENU)))
		UI.onProfile(profile({ owned = { bomb_classic = true, bomb_red = true, effect_classic = true } }))
		press(screens, "ShopButton")
		press(find(screens, "Shop"), "Card_bomb_red")
		press(find(screens, "Shop"), "Action")
		expect(remotes.RequestEquip.sentToServer[1][1]).toBe("bomb_red")
		press(find(screens, "Shop"), "Card_bomb_blue")
		press(find(screens, "Shop"), "Action")
		expect(remotes.RequestPurchase.sentToServer[1][1]).toBe("bomb_blue")
	end)

	it("profil reçu AVANT la création de l'interface : appliqué dès le démarrage", function()
		world.reset()
		local early = world.module("UIController")
		early.onProfile(profile({ coins = 4242 }))
		early.start(Fixtures.fakeRemotes({
			"SetQueued", "SetReady", "RequestPlaceBomb", "RequestPurchase", "RequestEquip", "RequestEmote", "RequestQuickChat", "PartyAction",
		}))
		local root = world.game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild("BombBattleUI"):FindFirstChild("Root")
		expect(find(find(root, "Shop"), "Coins").Text).toBe("Pièces : 4 242")
	end)

	it("résultats et statistiques : relayés aux écrans ; avant le démarrage, sans erreur", function()
		UI.onRoundEnded({
			result = { outcome = "WIN", winnerUserId = 1, tiedUserIds = {}, ranking = { 1 }, durationSeconds = 10 },
			names = { ["1"] = "Moi" },
			rewards = { ["1"] = 60 },
		})
		expect(find(find(screens, "Results"), "Title").Text).toBe("VICTOIRE !")
		UI.onStats({ bombCapacity = 2, blastRange = 3, speedPickups = 1, hasShield = true })
		world.reset()
		local fresh = world.module("UIController")
		fresh.onStats({})
		fresh.onRoundEnded({})
		fresh.onShopResult({})
		fresh.showToast("x")
	end)

	it("toast : affiché, remplacé par le suivant, masqué après 3,5 s depuis le DERNIER message", function()
		local toast = find(screens, "Toast")
		UI.showToast("Premier")
		expect(toast.Visible).toBe(true)
		expect(toast.Text).toBe("Premier")
		world.advance(2)
		UI.showToast("Second")
		world.advance(2) -- 4 s depuis le premier, 2 s depuis le second
		expect(toast.Visible).toBe(true)
		expect(toast.Text).toBe("Second")
		world.advance(2)
		expect(toast.Visible).toBe(false)
	end)

	it("échelle d'interface : suit l'écran et le réglage, bornée entre 0,55 et 1,4", function()
		local root = find(gui, "Root")
		local scale = root:FindFirstChildOfClass("UIScale")
		local camera = world.env.workspace.CurrentCamera
		expect(scale.Scale).toBeCloseTo(1)
		camera.ViewportSize = Vector2.new(390, 844)
		expect(scale.Scale).toBeCloseTo(0.55)
		camera.ViewportSize = Vector2.new(5120, 2880)
		expect(scale.Scale).toBeCloseTo(1.4)
		camera.ViewportSize = Vector2.new(1280, 720)
		world.module("SettingsStore").set("uiScale", "Petit")
		expect(scale.Scale).toBeCloseTo(0.85)
	end)

	it("minuteur : le compte à rebours des résultats suit l'horloge serveur, une mise à jour par seconde", function()
		UI.onSnapshot(snapshot("FINISHED", table.clone(PLAYING), { endsAt = world.clock.now + 5 }))
		world.fireRenderStepped(0.016)
		expect(find(find(screens, "Results"), "Footer").Text).toBe("Retour au lobby dans 5 s")
		world.advance(2.1)
		world.fireRenderStepped(0.016)
		expect(find(find(screens, "Results"), "Footer").Text).toBe("Retour au lobby dans 3 s")
	end)

	it("sélection d'écran exposée et identique à ScreenSelector", function()
		local selector = world.module("ScreenSelector")
		expect(UI.selectScreen).toBe(selector.select)
	end)
end)
