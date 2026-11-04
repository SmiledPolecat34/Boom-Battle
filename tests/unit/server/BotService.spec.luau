--!nocheck
-- BotService : création des bots, personnage, boucle de décision (BotBrain réel), animations, nettoyage. Les actions
-- passent par MovementService / BombService : ici ces deux services sont des doubles qui enregistrent les appels,
-- pour vérifier qu'un bot agit par les MÊMES portes qu'un joueur (aucun raccourci).
local MapConfig = world.module("MapConfig")

local BotService, ActorRegistry, DamageService, PlayState, info
local moves, bombs, forgotten, brokenMove

local function center(cell)
	return info.grid:cellToWorld(cell, 3)
end

-- Bot vivant et actif, personnage posé sur `cell`.
local function activeBot(index, cell)
	local bot = BotService.createBots(1)[1]
	local model = BotService.buildCharacter(bot, index)
	model.HumanoidRootPart.Position = center(cell)
	DamageService.setAlive(bot, true)
	PlayState.setActive(bot, true)
	return bot, model
end

beforeEach(function()
	world.reset()
	moves, bombs, forgotten, brokenMove = {}, {}, {}, false
	world.mock("MovementService", {
		requestMove = function(actor, x, y)
			if brokenMove then
				error("panne simulée")
			end
			table.insert(moves, { actor = actor, x = x, y = y })
			return true
		end,
		forget = function(actor)
			table.insert(forgotten, actor)
		end,
		cancel = function() end,
	})
	world.mock("BombService", {
		placeBomb = function(actor)
			table.insert(bombs, actor)
			return true
		end,
		canPlaceBomb = function()
			return true
		end,
		getDangerKeys = function()
			return {}
		end,
	})
	BotService = world.module("BotService")
	ActorRegistry = world.module("ActorRegistry")
	DamageService = world.module("DamageService")
	PlayState = world.module("PlayState")
	info = world.module("MapService").generateAndBuild(MapConfig.Sizes.Medium, 555, 4)
	PlayState.setState("PLAYING")
end)

afterEach(function()
	BotService.clear()
	PlayState.clearActive()
	PlayState.setState("WAITING")
end)

describe("création", function()
	it("createBots enregistre les bots (dégâts et bonus les voient) avec leur difficulté", function()
		local bots = BotService.createBots(3, { 1, 5, 10 })
		expect(#bots).toBe(3)
		expect(#ActorRegistry.getBots()).toBe(3)
		expect(bots[1].difficulty).toBe(1)
		expect(bots[3].difficulty).toBe(10)
		expect(bots[1].UserId).never.toBe(bots[2].UserId)
	end)

	it("difficulté par défaut quand aucune liste n'est fournie", function()
		expect(BotService.createBots(1)[1].difficulty).toBe(5)
	end)

	it("buildCharacter pose un modèle nommé dans Workspace.Bots et le rattache au bot", function()
		local bot = BotService.createBots(1)[1]
		local model = BotService.buildCharacter(bot, 1)
		expect(model).never.toBeNil()
		expect(model.Name).toBe(bot.DisplayName)
		expect(model.Parent.Name).toBe("Bots")
		expect(model.Parent.Parent).toBe(world.env.workspace)
		expect(bot.Character).toBe(model)
		expect(model:FindFirstChildOfClass("Humanoid").DisplayName).toBe(bot.DisplayName)
	end)

	it("l'indice de couleur boucle au-delà de la palette sans erreur", function()
		for index = 1, 9 do
			local bot = BotService.createBots(1)[1]
			expect(BotService.buildCharacter(bot, index)).never.toBeNil()
		end
	end)

	it("création du personnage impossible : nil et avertissement, aucune erreur", function()
		world.game:GetService("Players").CreateHumanoidModelFromDescription = function()
			error("service indisponible")
		end
		local bot = BotService.createBots(1)[1]
		expect(BotService.buildCharacter(bot, 1)).toBeNil()
		expect(#world.warnings).toBeGreaterThan(0)
	end)
end)

describe("boucle de décision", function()
	it("un bot actif agit (déplacement ou bombe) par les services du jeu, avec lui-même comme acteur", function()
		local bot = activeBot(1, info.layout.spawns[1])
		BotService.startAI({ bot })
		world.advance(4)
		expect(#moves + #bombs).toBeGreaterThan(0)
		for _, move in moves do
			expect(move.actor).toBe(bot)
			expect(info.grid:inBounds(move.x, move.y)).toBe(true)
		end
	end)

	it("un ennemi aligné à portée de bombe déclenche une pose", function()
		local spawn = info.layout.spawns[1]
		local bot = activeBot(1, spawn)
		local enemy = Fixtures.fakePlayer(1)
		enemy.Character = Fixtures.instanceCharacter(center({ x = spawn.x + 2, y = spawn.y }))
		DamageService.setAlive(enemy, true)
		world.addPlayer(enemy)
		BotService.startAI({ bot })
		world.advance(3)
		expect(#bombs).toBeGreaterThan(0)
		expect(bombs[1]).toBe(bot)
	end)

	it("aucune action hors manche (compte à rebours) ni pour un bot éliminé", function()
		local bot = activeBot(1, info.layout.spawns[1])
		PlayState.setState("COUNTDOWN")
		BotService.startAI({ bot })
		world.advance(3)
		expect(#moves + #bombs).toBe(0)
		PlayState.setState("PLAYING")
		DamageService.setAlive(bot, false)
		world.advance(3)
		expect(#moves + #bombs).toBe(0)
	end)

	it("une erreur de décision est capturée : avertissement, la boucle continue", function()
		local bot = activeBot(1, info.layout.spawns[1])
		brokenMove = true
		BotService.startAI({ bot })
		world.advance(3)
		expect(#world.warnings).toBeGreaterThan(0)
		brokenMove = false
		world.advance(3)
		expect(#moves + #bombs).toBeGreaterThan(0)
	end)

	it("plusieurs bots ne décident pas tous au même instant (décalage initial)", function()
		local bots = {}
		for i = 1, 3 do
			bots[i] = activeBot(i, info.layout.spawns[i])
		end
		BotService.startAI(bots)
		world.advance(0.25) -- avant le premier décalage du dernier bot
		local actors = {}
		for _, move in moves do
			actors[move.actor] = true
		end
		for _, bomb in bombs do
			actors[bomb] = true
		end
		local count = 0
		for _ in actors do
			count += 1
		end
		expect(count).toBeLessThan(3)
	end)
end)

describe("animations", function()
	it("repos en boucle dès le départ, marche selon la vitesse", function()
		local bot, model = activeBot(1, info.layout.spawns[1])
		BotService.startAI({ bot })
		local animator = model:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
		local idle, walk = animator.tracks[1], animator.tracks[2]
		expect(idle.Looped).toBe(true)
		expect(idle.IsPlaying).toBe(true)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		humanoid:FireEvent("Running", 8)
		expect(walk.IsPlaying).toBe(true)
		humanoid:FireEvent("Running", 0)
		expect(walk.IsPlaying).toBe(false)
	end)

	it("après clear, les anciens événements de marche sont ignorés", function()
		local bot, model = activeBot(1, info.layout.spawns[1])
		BotService.startAI({ bot })
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local walk = humanoid:FindFirstChildOfClass("Animator").tracks[2]
		BotService.clear()
		humanoid:FireEvent("Running", 10)
		expect(walk.IsPlaying).toBe(false)
	end)
end)

describe("nettoyage", function()
	it("clear arrête les décisions, détruit les personnages et vide le registre", function()
		local bot, model = activeBot(1, info.layout.spawns[1])
		BotService.startAI({ bot })
		world.advance(2)
		BotService.clear()
		local before = #moves + #bombs
		world.advance(5)
		expect(#moves + #bombs).toBe(before)
		expect(model.destroyed).toBe(true)
		expect(bot.Character).toBeNil()
		expect(#ActorRegistry.getBots()).toBe(0)
		expect(forgotten[1]).toBe(bot)
		expect(#world.env.workspace:FindFirstChild("Bots"):GetChildren()).toBe(0)
	end)

	it("clear sans aucun bot ni dossier : sans erreur", function()
		BotService.clear()
		BotService.clear()
	end)
end)
