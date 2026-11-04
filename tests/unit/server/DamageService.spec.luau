--!nocheck
-- DamageService : élimination, bouclier, état « vivant », rappels (joueurs ET bots).
local DamageService, shieldCalls, cancelled, shield

local function alivePlayer(userId)
	local player = Fixtures.fakePlayer(userId)
	player.Character = Fixtures.instanceCharacter()
	DamageService.setAlive(player, true)
	return player
end

beforeEach(function()
	world.reset()
	shield = {}
	shieldCalls = 0
	cancelled = {}
	world.mock("MovementService", {
		cancel = function(player)
			table.insert(cancelled, player)
		end,
	})
	world.mock("PowerupService", {
		consumeShield = function(player)
			shieldCalls += 1
			return shield[player] == true
		end,
	})
	DamageService = world.module("DamageService")
end)

describe("état vivant", function()
	it("vivant = attribut Alive vrai ET Humanoid avec de la vie", function()
		local player = alivePlayer(1)
		expect(DamageService.isAlive(player)).toBe(true)
		player.Character:FindFirstChildOfClass("Humanoid").Health = 0
		expect(DamageService.isAlive(player)).toBe(false)
	end)

	it("sans personnage, sans Humanoid ou sans attribut : non vivant", function()
		local noBody = Fixtures.fakePlayer(1)
		DamageService.setAlive(noBody, true)
		expect(DamageService.isAlive(noBody)).toBe(false)
		local unflagged = Fixtures.fakePlayer(2)
		unflagged.Character = Fixtures.instanceCharacter()
		expect(DamageService.isAlive(unflagged)).toBe(false)
	end)
end)

describe("eliminate", function()
	it("élimine un vivant : attribut, vie à 0, déplacement annulé, remote, rappel", function()
		local remotes = Fixtures.fakeRemotes({ "PlayerEliminated" })
		DamageService.start(remotes)
		local eliminated = {}
		DamageService.onEliminated(function(actor)
			table.insert(eliminated, actor)
		end)
		local player = alivePlayer(7)
		expect(DamageService.eliminate(player)).toBe(true)
		expect(player:GetAttribute("Alive")).toBe(false)
		expect(player.Character:FindFirstChildOfClass("Humanoid").Health).toBe(0)
		expect(cancelled[1]).toBe(player)
		expect(remotes.PlayerEliminated.sent[1].args[1]).toBe(7)
		expect(eliminated).toEqual({ player })
	end)

	it("une seule élimination par joueur (la 2e retourne false, rappel non répété)", function()
		local calls = 0
		DamageService.onEliminated(function()
			calls += 1
		end)
		local player = alivePlayer(1)
		expect(DamageService.eliminate(player)).toBe(true)
		expect(DamageService.eliminate(player)).toBe(false)
		expect(calls).toBe(1)
	end)

	it("un joueur sans personnage ne peut pas être éliminé", function()
		local player = Fixtures.fakePlayer(1)
		DamageService.setAlive(player, true)
		expect(DamageService.eliminate(player)).toBe(false)
	end)

	it("tous les rappels enregistrés reçoivent l'acteur", function()
		local seenA, seenB
		DamageService.onEliminated(function(actor)
			seenA = actor
		end)
		DamageService.onEliminated(function(actor)
			seenB = actor
		end)
		local player = alivePlayer(1)
		DamageService.eliminate(player)
		expect(seenA).toBe(player)
		expect(seenB).toBe(player)
	end)

	it("un joueur déclenche l'événement Eliminated, un bot non (mais ses rappels oui)", function()
		local fired = {}
		DamageService.Eliminated:Connect(function(actor)
			table.insert(fired, actor)
		end)
		local callbacks = 0
		DamageService.onEliminated(function()
			callbacks += 1
		end)
		local player = alivePlayer(1)
		local bot = { UserId = -1000001, IsBot = true, Character = Fixtures.instanceCharacter(), attributes = {} }
		function bot:GetAttribute(k)
			return self.attributes[k]
		end
		function bot:SetAttribute(k, v)
			self.attributes[k] = v
		end
		DamageService.setAlive(bot, true)
		DamageService.eliminate(player)
		DamageService.eliminate(bot)
		expect(#fired).toBe(1)
		expect(fired[1]).toBe(player)
		expect(callbacks).toBe(2)
	end)

	it("fonctionne avant start (remote absente) sans erreur", function()
		local player = alivePlayer(1)
		expect(DamageService.eliminate(player)).toBe(true)
	end)
end)

describe("hit (dégâts d'explosion)", function()
	it("sans bouclier : éliminé", function()
		local player = alivePlayer(1)
		expect(DamageService.hit(player)).toBe(true)
		expect(DamageService.isAlive(player)).toBe(false)
	end)

	it("avec bouclier : l'explosion est absorbée, le joueur survit, puis le coup suivant tue", function()
		local player = alivePlayer(1)
		shield[player] = true
		expect(DamageService.hit(player)).toBe(false)
		expect(DamageService.isAlive(player)).toBe(true)
		shield[player] = false
		expect(DamageService.hit(player)).toBe(true)
	end)

	it("un joueur déjà éliminé ne consomme pas de bouclier et n'est pas re-touché", function()
		local player = alivePlayer(1)
		DamageService.eliminate(player)
		expect(DamageService.hit(player)).toBe(false)
		expect(shieldCalls).toBe(0)
	end)
end)
