--!nocheck
-- ScreenSelector : quel écran principal afficher selon l'état serveur et le statut du joueur. Table exhaustive
-- (état × statut) : toute combinaison doit produire un écran valide, jamais un écran vide.
local ScreenSelector = world.module("ScreenSelector")

local STATES = { "WAITING", "READY", "COUNTDOWN", "PLAYING", "FINISHED", "RESETTING" }
local VALID = { MainMenu = true, Lobby = true, GameHUD = true, Results = true }

local menuPlayer = { queued = false, participant = false, alive = false, ready = false }
local queuedPlayer = { queued = true, participant = false, alive = false, ready = false }
local playing = { queued = true, participant = true, alive = true, ready = true }
local dead = { queued = true, participant = true, alive = false, ready = true }

local function pick(state, me)
	return ScreenSelector.select({ state = state, players = {} }, me)
end

describe("cas métier", function()
	it("au menu en attente => MainMenu", function()
		expect(pick("WAITING", menuPlayer)).toBe("MainMenu")
	end)
	it("PLAY cliqué (READY) => Lobby", function()
		expect(pick("READY", queuedPlayer)).toBe("Lobby")
	end)
	it("retour au lobby (RESETTING) => Lobby", function()
		expect(pick("RESETTING", queuedPlayer)).toBe("Lobby")
	end)
	it("compte à rebours et manche, participant => GameHUD", function()
		expect(pick("COUNTDOWN", playing)).toBe("GameHUD")
		expect(pick("PLAYING", playing)).toBe("GameHUD")
	end)
	it("éliminé ou spectateur inscrit => GameHUD (spectateur)", function()
		expect(pick("PLAYING", dead)).toBe("GameHUD")
		expect(pick("PLAYING", queuedPlayer)).toBe("GameHUD")
	end)
	it("au menu pendant une manche => MainMenu", function()
		expect(pick("PLAYING", menuPlayer)).toBe("MainMenu")
		expect(pick("COUNTDOWN", menuPlayer)).toBe("MainMenu")
	end)
	it("fin de manche : participant => Results, joueur au menu / ayant quitté => MainMenu", function()
		expect(pick("FINISHED", playing)).toBe("Results")
		expect(pick("FINISHED", menuPlayer)).toBe("MainMenu")
	end)
	it("joueur inconnu (nil) => MainMenu, jamais d'erreur", function()
		for _, state in STATES do
			expect(pick(state, nil)).toBe("MainMenu")
		end
	end)
end)

describe("exhaustivité", function()
	it("toute combinaison état × statut donne un écran valide", function()
		for _, state in STATES do
			for _, me in { menuPlayer, queuedPlayer, playing, dead, {}, false } do
				expect(VALID[pick(state, me or nil)]).toBe(true)
			end
		end
	end)

	it("un état inconnu retombe sur un écran valide", function()
		expect(VALID[pick("???", menuPlayer)]).toBe(true)
		expect(VALID[pick("???", queuedPlayer)]).toBe(true)
	end)

	it("déterministe : même entrée, même sortie", function()
		expect(pick("PLAYING", dead)).toBe(pick("PLAYING", dead))
	end)

	it("un champ queued non booléen n'est pas considéré inscrit", function()
		expect(pick("PLAYING", { queued = "true" })).toBe("MainMenu")
		expect(pick("PLAYING", { queued = 1 })).toBe("MainMenu")
	end)
end)
