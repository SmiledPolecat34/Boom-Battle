--!nocheck
-- EmoteService et QuickChatService : le client n'envoie qu'un identifiant ; tout est validé côté serveur (identifiant
-- connu, cadence, état de manche, joueur vivant). Instances génériques simulées (Animator, BillboardGui, Debris).
local GameConfig = world.module("GameConfig")
local EmoteConfig = world.module("EmoteConfig")
local QuickChatConfig = world.module("QuickChatConfig")

local EmoteService, QuickChatService, PlayState, remotes

local function lobbyPlayer(userId)
	local player = Fixtures.fakePlayer(userId)
	player.Character = Fixtures.instanceCharacter()
	return player
end

local function tracksOf(player)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid:FindFirstChildOfClass("Animator")
	return if animator then animator.tracks else {}
end

local function bubbleOf(player)
	return player.Character:FindFirstChild("Head"):FindFirstChild("QuickChatBubble")
end

beforeEach(function()
	world.reset()
	PlayState = world.module("PlayState")
	EmoteService = world.module("EmoteService")
	QuickChatService = world.module("QuickChatService")
	remotes = Fixtures.fakeRemotes({ "RequestEmote", "RequestQuickChat" })
	EmoteService.start(remotes)
	QuickChatService.start(remotes)
	PlayState.setState("WAITING")
end)

afterEach(function()
	PlayState.clearActive()
	PlayState.setState("WAITING")
end)

describe("EmoteService", function()
	it("une émote connue est jouée par le serveur (Animator du personnage, animation de la config)", function()
		local p = lobbyPlayer(1)
		remotes.RequestEmote:fireServer(p, "wave")
		local tracks = tracksOf(p)
		expect(#tracks).toBe(1)
		expect(tracks[1].AnimationId).toBe(EmoteConfig.get("wave").animationId)
		expect(tracks[1].IsPlaying).toBe(true)
		expect(tracks[1].Looped).toBe(false)
	end)

	it("identifiants invalides ignorés : inconnu, nombre, table, booléen, nil, chaîne énorme", function()
		local p = lobbyPlayer(1)
		for _, bad in { "hack", 42, {}, true, string.rep("x", 10000), "" } do
			world.advance(GameConfig.RemoteLimits.EmoteRequestMinInterval + 0.1)
			remotes.RequestEmote:fireServer(p, bad)
		end
		remotes.RequestEmote:fireServer(p, nil)
		expect(#tracksOf(p)).toBe(0)
	end)

	it("cadence limitée : la 2e demande immédiate est ignorée, puis acceptée après l'intervalle", function()
		local p = lobbyPlayer(1)
		remotes.RequestEmote:fireServer(p, "wave")
		remotes.RequestEmote:fireServer(p, "cheer")
		expect(#tracksOf(p)).toBe(1)
		world.advance(GameConfig.RemoteLimits.EmoteRequestMinInterval + 0.1)
		remotes.RequestEmote:fireServer(p, "cheer")
		expect(#tracksOf(p)).toBe(2)
	end)

	it("une nouvelle émote arrête la précédente ; relancer la même réutilise la piste", function()
		local p = lobbyPlayer(1)
		remotes.RequestEmote:fireServer(p, "wave")
		world.advance(GameConfig.RemoteLimits.EmoteRequestMinInterval + 0.1)
		remotes.RequestEmote:fireServer(p, "cheer")
		local tracks = tracksOf(p)
		expect(tracks[1].IsPlaying).toBe(false)
		expect(tracks[2].IsPlaying).toBe(true)
		world.advance(GameConfig.RemoteLimits.EmoteRequestMinInterval + 0.1)
		remotes.RequestEmote:fireServer(p, "cheer")
		expect(#tracksOf(p)).toBe(2)
	end)

	it("une danse s'arrête toute seule après MaxLoopSeconds ; un geste n'est pas coupé", function()
		local p = lobbyPlayer(1)
		remotes.RequestEmote:fireServer(p, "dance")
		local dance = tracksOf(p)[1]
		expect(dance.Looped).toBe(true)
		world.advance(EmoteConfig.MaxLoopSeconds - 1)
		expect(dance.IsPlaying).toBe(true)
		world.advance(1.5)
		expect(dance.IsPlaying).toBe(false)
	end)

	it("une danse relancée n'est pas coupée par le minuteur de la précédente", function()
		local p = lobbyPlayer(1)
		remotes.RequestEmote:fireServer(p, "dance")
		world.advance(EmoteConfig.MaxLoopSeconds - 2)
		remotes.RequestEmote:fireServer(p, "dance2")
		local second = tracksOf(p)[2]
		world.advance(3) -- le minuteur de la 1re danse expire ici
		expect(second.IsPlaying).toBe(true)
	end)

	it("stop interrompt l'émote en cours (appelé quand le joueur se déplace) ; sans émote : sans erreur", function()
		local p = lobbyPlayer(1)
		EmoteService.stop(p)
		remotes.RequestEmote:fireServer(p, "dance")
		EmoteService.stop(p)
		expect(tracksOf(p)[1].IsPlaying).toBe(false)
	end)

	it("porte d'actions : interdit pendant le changement d'arène, et en manche pour un non-actif", function()
		local p = lobbyPlayer(1)
		PlayState.setState("RESETTING")
		remotes.RequestEmote:fireServer(p, "wave")
		expect(#tracksOf(p)).toBe(0)
		PlayState.setState("PLAYING")
		world.advance(2)
		remotes.RequestEmote:fireServer(p, "wave")
		expect(#tracksOf(p)).toBe(0)
		PlayState.setActive(p, true)
		world.advance(2)
		remotes.RequestEmote:fireServer(p, "wave")
		expect(#tracksOf(p)).toBe(1)
	end)

	it("personnage absent ou mort : ignoré", function()
		local noBody = Fixtures.fakePlayer(1)
		remotes.RequestEmote:fireServer(noBody, "wave")
		local dead = lobbyPlayer(2)
		dead.Character:FindFirstChildOfClass("Humanoid").Health = 0
		remotes.RequestEmote:fireServer(dead, "wave")
		expect(#tracksOf(dead)).toBe(0)
	end)

	it("un nouveau personnage recharge les pistes (les anciennes ne sont plus valides)", function()
		local p = lobbyPlayer(1)
		remotes.RequestEmote:fireServer(p, "wave")
		p.Character = Fixtures.instanceCharacter()
		world.advance(2)
		remotes.RequestEmote:fireServer(p, "wave")
		expect(#tracksOf(p)).toBe(1)
		expect(tracksOf(p)[1].plays).toBe(1)
	end)

	it("chargement d'animation en échec : ignoré sans erreur", function()
		local p = lobbyPlayer(1)
		local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
		local animator = world.env.Instance.new("Animator", humanoid)
		animator.LoadAnimation = function()
			error("animation introuvable")
		end
		remotes.RequestEmote:fireServer(p, "wave")
		expect(#animator.tracks).toBe(0)
	end)

	it("le départ du joueur libère son état", function()
		local p = lobbyPlayer(1)
		remotes.RequestEmote:fireServer(p, "wave")
		world.removePlayer(p)
		p.Character = Fixtures.instanceCharacter()
		remotes.RequestEmote:fireServer(p, "wave") -- aurait été limité par la cadence
		expect(#tracksOf(p)).toBe(1)
	end)
end)

describe("QuickChatService", function()
	local function say(player, id)
		remotes.RequestQuickChat:fireServer(player, id)
	end

	it("une phrase connue devient une bulle au-dessus de la tête avec le texte du catalogue", function()
		local p = lobbyPlayer(1)
		local phrase = QuickChatConfig.Phrases[1]
		say(p, phrase.id)
		local bubble = bubbleOf(p)
		expect(bubble).never.toBeNil()
		expect(bubble.Adornee).toBe(p.Character.Head)
		expect(bubble:FindFirstChild("Bubble"):FindFirstChild("Text").Text).toBe(phrase.text)
	end)

	it("seul le catalogue est affiché : texte libre, HTML, nombre, table, nil ignorés", function()
		local p = lobbyPlayer(1)
		for _, bad in { "<script>alert(1)</script>", "Bonjour tout le monde", 7, {}, true, "" } do
			world.advance(GameConfig.RemoteLimits.QuickChatMinInterval + 0.1)
			say(p, bad)
		end
		say(p, nil)
		expect(bubbleOf(p)).toBeNil()
	end)

	it("une seule bulle par joueur : la nouvelle remplace l'ancienne", function()
		local p = lobbyPlayer(1)
		say(p, QuickChatConfig.Phrases[1].id)
		local first = bubbleOf(p)
		world.advance(GameConfig.RemoteLimits.QuickChatMinInterval + 0.1)
		say(p, QuickChatConfig.Phrases[2].id)
		local second = bubbleOf(p)
		expect(first.destroyed).toBe(true)
		expect(second).never.toBe(first)
		local count = 0
		for _, child in p.Character.Head:GetChildren() do
			if child.Name == "QuickChatBubble" then
				count += 1
			end
		end
		expect(count).toBe(1)
	end)

	it("cadence limitée : une 2e phrase immédiate est ignorée", function()
		local p = lobbyPlayer(1)
		say(p, QuickChatConfig.Phrases[1].id)
		local first = bubbleOf(p)
		say(p, QuickChatConfig.Phrases[2].id)
		expect(bubbleOf(p)).toBe(first)
	end)

	it("la bulle disparaît après BubbleSeconds", function()
		local p = lobbyPlayer(1)
		say(p, QuickChatConfig.Phrases[1].id)
		local bubble = bubbleOf(p)
		world.advance(QuickChatConfig.BubbleSeconds - 0.5)
		expect(bubble.destroyed).toBe(false)
		world.advance(1)
		expect(bubble.destroyed).toBe(true)
	end)

	it("porte d'actions : rien pendant le changement d'arène ni en manche pour un non-actif", function()
		local p = lobbyPlayer(1)
		PlayState.setState("RESETTING")
		say(p, QuickChatConfig.Phrases[1].id)
		expect(bubbleOf(p)).toBeNil()
		PlayState.setState("PLAYING")
		world.advance(2)
		say(p, QuickChatConfig.Phrases[1].id)
		expect(bubbleOf(p)).toBeNil()
		PlayState.setActive(p, true)
		world.advance(2)
		say(p, QuickChatConfig.Phrases[1].id)
		expect(bubbleOf(p)).never.toBeNil()
	end)

	it("sans personnage, sans tête ou mort : ignoré", function()
		local noBody = Fixtures.fakePlayer(1)
		say(noBody, QuickChatConfig.Phrases[1].id)
		local dead = lobbyPlayer(2)
		dead.Character:FindFirstChildOfClass("Humanoid").Health = 0
		say(dead, QuickChatConfig.Phrases[1].id)
		expect(bubbleOf(dead)).toBeNil()
		local headless = lobbyPlayer(3)
		headless.Character.Head:Destroy()
		say(headless, QuickChatConfig.Phrases[1].id)
	end)

	it("le départ du joueur libère sa cadence", function()
		local p = lobbyPlayer(1)
		say(p, QuickChatConfig.Phrases[1].id)
		world.removePlayer(p)
		say(p, QuickChatConfig.Phrases[2].id)
		expect(bubbleOf(p):FindFirstChild("Bubble"):FindFirstChild("Text").Text).toBe(QuickChatConfig.Phrases[2].text)
	end)
end)
