--!nocheck
-- BotBrain (cerveau pur des bots), BotActor, ActorRegistry. (Phase9Tests n'avait jamais été exécuté : ces tests le sont.)
local BotBrain = world.module("BotBrain")
local BotActor = world.module("BotActor")
local ActorRegistry = world.module("ActorRegistry")

local function ctx(cell, overrides)
	local c = { cell = cell, range = 2, canPlaceBomb = true, danger = {}, enemies = {}, rng = nil }
	for k, v in overrides or {} do
		c[k] = v
	end
	return c
end

describe("BotActor et ActorRegistry", function()
	it("identifiant négatif éloigné de ceux des joueurs, unique par bot", function()
		local bot = BotActor.new(1)
		expect(bot.UserId).toBeLessThan(-999999)
		expect(BotActor.new(1).UserId).never.toBe(BotActor.new(2).UserId)
	end)

	it("attributs lisibles/écrivables comme un joueur", function()
		local bot = BotActor.new(1)
		bot:SetAttribute("Alive", true)
		expect(bot:GetAttribute("Alive")).toBe(true)
		expect(bot:GetAttribute("Absent")).toBeNil()
	end)

	it("isBot ne reconnaît que les bots", function()
		expect(ActorRegistry.isBot(BotActor.new(1))).toBe(true)
		expect(ActorRegistry.isBot({})).toBe(false)
		expect(ActorRegistry.isBot(nil)).toBe(false)
		expect(ActorRegistry.isBot("bot")).toBe(false)
	end)

	it("all() = joueurs puis bots, dans une nouvelle table ; clearBots vide la liste", function()
		local player = Fixtures.fakePlayer(1)
		world.addPlayer(player)
		local bot = BotActor.new(1)
		ActorRegistry.addBot(bot)
		local list = ActorRegistry.all()
		expect(list[1]).toBe(player)
		expect(table.find(list, bot)).never.toBeNil()
		table.clear(list)
		expect(#ActorRegistry.all()).toBe(2)
		ActorRegistry.clearBots()
		expect(#ActorRegistry.getBots()).toBe(0)
		expect(#ActorRegistry.all()).toBe(1)
	end)
end)

describe("BotBrain.blastKeys", function()
	it("croix avec arrêt sur pilier, caisse touchée puis arrêt", function()
		local g, c = Fixtures.emptyGrid(9)
		c[5][7] = "PILLAR"
		c[3][5] = "CRATE"
		local keys = BotBrain.blastKeys(g, { x = 5, y = 5 }, 3)
		local function has(x, y)
			return keys[g:key(x, y)] == true
		end
		expect(has(5, 5) and has(6, 5) and has(4, 5) and has(5, 6)).toBe(true)
		expect(has(7, 5)).toBe(false)
		expect(has(8, 5)).toBe(false)
		expect(has(5, 3)).toBe(true)
		expect(has(5, 2)).toBe(false)
	end)
end)

describe("décisions", function()
	it("un bot menacé fuit vers une case hors de la zone, avant toute autre action", function()
		local g = Fixtures.emptyGrid(9)
		local danger = BotBrain.blastKeys(g, { x = 5, y = 5 }, 2)
		local action = BotBrain.decide(g, ctx({ x = 5, y = 4 }, { danger = danger }))
		expect(action.kind).toBe("move")
		expect(danger[g:key(action.cell.x, action.cell.y)]).toBeNil()
	end)

	it("pose une bombe à côté d'une caisse, jamais sans capacité", function()
		local g, c = Fixtures.emptyGrid(9)
		c[5][6] = "CRATE"
		expect(BotBrain.decide(g, ctx({ x = 5, y = 5 })).kind).toBe("bomb")
		expect(BotBrain.decide(g, ctx({ x = 5, y = 5 }, { canPlaceBomb = false })).kind).never.toBe("bomb")
	end)

	it("ne se suicide pas : aucune bombe dans un cul-de-sac sans issue", function()
		local g, c = Fixtures.emptyGrid(9)
		for x = 1, 9 do
			for y = 1, 9 do
				c[y][x] = "PILLAR"
			end
		end
		c[1][1], c[1][2], c[1][3] = "EMPTY", "EMPTY", "CRATE"
		expect(BotBrain.decide(g, ctx({ x = 1, y = 1 }, { range = 3 })).kind).never.toBe("bomb")
		expect(BotBrain.hasEscape(g, { x = 2, y = 1 }, 3, {})).toBe(false)
	end)

	it("hasEscape vrai en terrain ouvert", function()
		local g = Fixtures.emptyGrid(9)
		expect(BotBrain.hasEscape(g, { x = 5, y = 5 }, 2, {})).toBe(true)
	end)

	it("tire sur un ennemi aligné, s'approche d'un ennemi lointain, attend sans cible", function()
		local g = Fixtures.emptyGrid(9)
		expect(BotBrain.decide(g, ctx({ x = 5, y = 5 }, { enemies = { { x = 7, y = 5 } } })).kind).toBe("bomb")
		local far = BotBrain.decide(g, ctx({ x = 1, y = 1 }, { enemies = { { x = 9, y = 9 } } }))
		expect(far.kind).toBe("move")
		expect(far.cell).never.toBeNil()
		expect(BotBrain.decide(g, ctx({ x = 5, y = 5 })).kind).toBe("wait")
	end)

	it("ne marche jamais sur une case contenant une bombe", function()
		local g = Fixtures.emptyGrid(9)
		g:setBomb(5, 4, true)
		local danger = BotBrain.blastKeys(g, { x = 5, y = 4 }, 2)
		local action = BotBrain.decide(g, ctx({ x = 5, y = 5 }, { danger = danger }))
		if action.kind == "move" then
			expect(action.cell.x == 5 and action.cell.y == 4).toBe(false)
		end
	end)

	it("sans hasard : décision déterministe ; avec hasard : hésitation rare mais présente", function()
		local g, c = Fixtures.emptyGrid(9)
		c[5][6] = "CRATE"
		expect(BotBrain.decide(g, ctx({ x = 5, y = 5 })).kind).toBe(BotBrain.decide(g, ctx({ x = 5, y = 5 })).kind)
		local waits, total = 0, 400
		local rng = Random.new(1)
		for _ = 1, total do
			if BotBrain.decide(g, ctx({ x = 5, y = 5 }, { rng = rng })).kind == "wait" then
				waits += 1
			end
		end
		expect(waits).toBeGreaterThan(0)
		expect(waits).toBeLessThan(total * 0.15)
	end)

	it("profile(difficulty) renvoie un profil exploitable pour toute difficulté", function()
		for _, d in { 0, 1, 2, 3, 99, -1 } do
			expect(type(BotBrain.profile(d))).toBe("table")
		end
	end)
end)
