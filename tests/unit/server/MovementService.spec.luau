--!nocheck
-- MovementService : validation des demandes de déplacement (types, bornes, cadence, état de manche) et pilotage du
-- personnage case par case. Le personnage est un faux Humanoid qui avance à WalkSpeed (Fixtures.fakeCharacter) dans un
-- temps simulé (world.advance).
local GameConfig = world.module("GameConfig")

local MovementService, PlayState, grid, remotes, emoteStops

local function centerOf(x, y)
	return grid:cellToWorld({ x = x, y = y }, 3)
end

-- Joueur dont le personnage est posé au centre de la case (x, y).
local function playerAt(x, y, userId)
	local player = Fixtures.fakePlayer(userId or 1)
	player.Character = Fixtures.fakeCharacter(centerOf(x, y))
	return player
end

local function distanceTo(player, x, y)
	local target, position = centerOf(x, y), player.Character.root.Position
	return math.sqrt((target.X - position.X) ^ 2 + (target.Z - position.Z) ^ 2)
end

local function request(player, payload)
	remotes.RequestMove:fireServer(player, payload)
end

beforeEach(function()
	world.reset()
	emoteStops = {}
	world.mock("EmoteService", {
		stop = function(actor)
			table.insert(emoteStops, actor)
		end,
	})
	MovementService = world.module("MovementService")
	PlayState = world.module("PlayState")
	grid = Fixtures.emptyGrid(9)
	remotes = Fixtures.fakeRemotes({ "RequestMove", "MoveRejected" })
	MovementService.start(remotes, function()
		return grid
	end)
	PlayState.setState("WAITING") -- lobby : tout le monde peut se déplacer
end)

afterEach(function()
	MovementService.stop()
end)

describe("déplacement valide", function()
	it("le personnage rejoint le centre de la case demandée", function()
		local player = playerAt(1, 1)
		request(player, { x = 5, y = 1 })
		world.advance(3)
		expect(distanceTo(player, 5, 1)).toBeLessThan(0.9)
	end)

	it("le chemin contourne un pilier et arrive quand même", function()
		local _, cells = grid, nil
		grid:setKind(3, 1, "PILLAR")
		local player = playerAt(1, 1)
		request(player, { x = 5, y = 1 })
		world.advance(5)
		expect(distanceTo(player, 5, 1)).toBeLessThan(0.9)
	end)

	it("une nouvelle demande annule la précédente", function()
		local player = playerAt(1, 1)
		request(player, { x = 9, y = 1 })
		world.advance(0.5)
		world.advance(0.2) -- dépasse la cadence minimale
		request(player, { x = 1, y = 9 })
		world.advance(6)
		expect(distanceTo(player, 1, 9)).toBeLessThan(0.9)
	end)

	it("se déplacer interrompt l'émote ; ne pas bouger (même case) ne l'interrompt pas", function()
		local player = playerAt(1, 1)
		request(player, { x = 1, y = 1 })
		expect(#emoteStops).toBe(0)
		world.advance(0.2)
		request(player, { x = 3, y = 1 })
		expect(emoteStops[1]).toBe(player)
	end)

	it("une bombe posée sur le trajet arrête le personnage devant elle", function()
		local player = playerAt(1, 1)
		request(player, { x = 6, y = 1 })
		world.advance(0.1)
		grid:setBomb(4, 1, true)
		world.advance(5)
		expect(distanceTo(player, 6, 1)).toBeGreaterThan(2)
		expect(distanceTo(player, 3, 1)).toBeLessThan(5)
	end)

	it("cancel stoppe le trajet en cours", function()
		local player = playerAt(1, 1)
		request(player, { x = 9, y = 1 })
		world.advance(0.3)
		MovementService.cancel(player)
		local stoppedAt = player.Character.root.Position.X
		world.advance(3)
		expect(math.abs(player.Character.root.Position.X - stoppedAt)).toBeLessThan(5) -- au plus la case en cours
		expect(distanceTo(player, 9, 1)).toBeGreaterThan(4)
	end)
end)

describe("charges utiles hostiles", function()
	local bad = {
		"x", 5, true, {}, { x = "3", y = 1 }, { x = 1 }, { y = 1 }, { x = 0 / 0, y = 1 }, { x = 1.5, y = 1 },
		{ x = 1, y = 2.5 },
	}

	it("types invalides, NaN, fractions et infinis : ignorés sans réponse ni déplacement", function()
		for _, payload in bad do
			local player = playerAt(1, 1)
			world.advance(0.2)
			request(player, payload)
			world.advance(1)
			expect(distanceTo(player, 1, 1)).toBeLessThan(0.1)
		end
		request(playerAt(1, 1, 7), nil)
		expect(#remotes.MoveRejected.sent).toBe(0)
	end)

	it("case hors grille ou piliers : refus renvoyé au joueur", function()
		grid:setKind(3, 3, "PILLAR")
		local player = playerAt(1, 1)
		-- (l'infini passe le contrôle de type mais est refusé comme case hors grille)
		for _, target in { { x = 0, y = 1 }, { x = 99, y = 99 }, { x = -4, y = 2 }, { x = 3, y = 3 }, { x = math.huge, y = 1 }, { x = 1, y = -math.huge } } do
			world.advance(0.2)
			request(player, target)
		end
		expect(#remotes.MoveRejected.sent).toBe(6)
		expect(remotes.MoveRejected.sent[1].player).toBe(player)
		expect(remotes.MoveRejected.sent[4].args[1]).toEqual({ x = 3, y = 3 })
		expect(distanceTo(player, 1, 1)).toBeLessThan(0.1)
	end)

	it("case inaccessible (encerclée) : refus", function()
		grid:setKind(8, 9, "PILLAR")
		grid:setKind(9, 8, "PILLAR")
		local player = playerAt(1, 1)
		request(player, { x = 9, y = 9 })
		expect(#remotes.MoveRejected.sent).toBe(1)
	end)

	it("personnage hors de la zone jouable : refus, aucun plantage", function()
		local player = Fixtures.fakePlayer(1)
		player.Character = Fixtures.fakeCharacter(Vector3.new(-500, 3, -500))
		request(player, { x = 2, y = 2 })
		expect(#remotes.MoveRejected.sent).toBe(1)
	end)
end)

describe("cadence", function()
	it("la 2e demande dans MoveRequestMinInterval est ignorée, puis acceptée plus tard", function()
		local player = playerAt(1, 1)
		request(player, { x = 3, y = 1 })
		request(player, { x = 1, y = 9 }) -- immédiate : ignorée
		world.advance(2)
		expect(distanceTo(player, 3, 1)).toBeLessThan(0.9)
		world.advance(GameConfig.RemoteLimits.MoveRequestMinInterval + 0.05)
		request(player, { x = 1, y = 5 })
		world.advance(3)
		expect(distanceTo(player, 1, 5)).toBeLessThan(0.9)
	end)

	it("la cadence est par joueur", function()
		local a, b = playerAt(1, 1, 1), playerAt(1, 2, 2)
		request(a, { x = 4, y = 1 })
		request(b, { x = 4, y = 2 })
		world.advance(3)
		expect(distanceTo(a, 4, 1)).toBeLessThan(0.9)
		expect(distanceTo(b, 4, 2)).toBeLessThan(0.9)
	end)
end)

describe("porte d'actions (état de manche)", function()
	it("compte à rebours : le joueur est gelé", function()
		local player = playerAt(1, 1)
		PlayState.setState("COUNTDOWN")
		PlayState.setActive(player, true)
		request(player, { x = 5, y = 1 })
		world.advance(2)
		expect(distanceTo(player, 1, 1)).toBeLessThan(0.1)
	end)

	it("en manche : un éliminé ou un spectateur ne bouge pas, un vivant oui", function()
		local alive, dead = playerAt(1, 1, 1), playerAt(1, 2, 2)
		PlayState.setState("PLAYING")
		PlayState.setActive(alive, true)
		request(alive, { x = 4, y = 1 })
		request(dead, { x = 4, y = 2 })
		world.advance(3)
		expect(distanceTo(alive, 4, 1)).toBeLessThan(0.9)
		expect(distanceTo(dead, 1, 2)).toBeLessThan(0.1)
	end)

	it("sans personnage ou Humanoid mort : refus silencieux", function()
		local noBody = Fixtures.fakePlayer(1)
		request(noBody, { x = 2, y = 2 })
		local corpse = playerAt(1, 1, 2)
		corpse.Character.humanoid.Health = 0
		request(corpse, { x = 2, y = 1 })
		world.advance(1)
		expect(distanceTo(corpse, 1, 1)).toBeLessThan(0.1)
		expect(#remotes.MoveRejected.sent).toBe(0)
	end)
end)

describe("acteurs non joueurs (bots)", function()
	it("requestMove déplace un bot sans jamais envoyer de refus", function()
		local bot = { UserId = -1000001, IsBot = true, Character = Fixtures.fakeCharacter(centerOf(1, 1)) }
		expect(MovementService.requestMove(bot, 4, 1, remotes)).toBe(true)
		world.advance(3)
		local pos = bot.Character.root.Position
		expect(math.abs(pos.X - centerOf(4, 1).X)).toBeLessThan(0.9)
		expect(MovementService.requestMove(bot, 99, 99, remotes)).toBe(false)
		expect(#remotes.MoveRejected.sent).toBe(0)
	end)

	it("forget annule le trajet d'un bot retiré", function()
		local bot = { UserId = -1000001, IsBot = true, Character = Fixtures.fakeCharacter(centerOf(1, 1)) }
		MovementService.requestMove(bot, 9, 1)
		world.advance(0.2)
		MovementService.forget(bot)
		local x = bot.Character.root.Position.X
		world.advance(3)
		expect(bot.Character.root.Position.X - x).toBeLessThan(5)
	end)
end)

describe("setupCharacter", function()
	it("vitesse de base, pas de saut, rotation automatique", function()
		local player = Fixtures.fakePlayer(1)
		local character = Fixtures.fakeCharacter(centerOf(1, 1))
		MovementService.setupCharacter(player, character)
		expect(character.humanoid.WalkSpeed).toBe(GameConfig.Movement.BaseWalkSpeed)
		expect(character.humanoid.JumpPower).toBe(0)
		expect(character.humanoid.AutoRotate).toBe(true)
	end)

	it("un personnage incomplet ne plante pas", function()
		local player = Fixtures.fakePlayer(1)
		local broken = { WaitForChild = function() return nil end }
		MovementService.setupCharacter(player, broken)
	end)

	it("réapparition : un trajet de la vie précédente est annulé", function()
		local player = playerAt(1, 1)
		request(player, { x = 9, y = 1 })
		world.advance(0.2)
		MovementService.setupCharacter(player, player.Character)
		local x = player.Character.root.Position.X
		world.advance(3)
		expect(player.Character.root.Position.X - x).toBeLessThan(5)
	end)
end)

describe("cycle de vie", function()
	it("le départ d'un joueur libère son état de cadence", function()
		local player = playerAt(1, 1)
		request(player, { x = 3, y = 1 })
		world.removePlayer(player)
		request(player, { x = 1, y = 3 }) -- aurait été bloqué par la cadence
		world.advance(2)
		expect(distanceTo(player, 1, 3)).toBeLessThan(0.9)
	end)

	it("stop déconnecte les remotes", function()
		MovementService.stop()
		local player = playerAt(1, 1)
		request(player, { x = 5, y = 1 })
		world.advance(2)
		expect(distanceTo(player, 1, 1)).toBeLessThan(0.1)
	end)

	it("sans fournisseur de grille actif : refus sans erreur", function()
		MovementService.stop()
		expect(MovementService.requestMove(playerAt(1, 1), 2, 1)).toBe(false)
	end)
end)
