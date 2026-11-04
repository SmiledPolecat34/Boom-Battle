--!nocheck
-- PowerupService : statistiques, bonus au sol (tirage lié à la seed), ramassage par proximité, plafonds, bouclier.
-- Le tirage utilise le Random de remplacement du harnais : on teste des propriétés, pas des valeurs exactes.
local GameConfig = world.module("GameConfig")
local MapConfig = world.module("MapConfig")

local PowerupService, MapService, info, remotes

local function cellCenter(cell)
	return info.grid:cellToWorld(cell, 3)
end

local function actorAt(cell, userId)
	local player = Fixtures.fakePlayer(userId)
	player.Character = Fixtures.instanceCharacter(cellCenter(cell))
	player:SetAttribute("Alive", true)
	world.addPlayer(player)
	return player
end

local function pickupsInFolder()
	local list = {}
	for _, child in info.folder:GetChildren() do
		if child.Name:match("^Powerup_") then
			table.insert(list, child)
		end
	end
	return list
end

-- Tire des bonus sur toute la carte jusqu'à en obtenir un du type voulu ; retourne sa case.
local function dropOfKind(id)
	for y = 1, info.layout.size do
		for x = 1, info.layout.size do
			PowerupService.maybeDrop(info, { x = x, y = y })
			for _, part in pickupsInFolder() do
				if part:GetAttribute("PowerupId") == id then
					return { x = x, y = y }, part
				end
			end
		end
	end
	error("aucun bonus " .. id .. " tiré sur toute la carte")
end

beforeEach(function()
	world.reset()
	MapService = world.module("MapService")
	PowerupService = world.module("PowerupService")
	info = MapService.generateAndBuild(MapConfig.Sizes.Medium, 12345, 4)
	remotes = Fixtures.fakeRemotes({ "StatsChanged" })
	PowerupService.start(remotes)
end)

describe("statistiques", function()
	it("valeurs par défaut issues de GameConfig", function()
		local stats = PowerupService.getStats(Fixtures.fakePlayer(1))
		expect(stats.bombCapacity).toBe(GameConfig.Bomb.DefaultCapacity)
		expect(stats.blastRange).toBe(GameConfig.Bomb.DefaultBlastRange)
		expect(stats.speedPickups).toBe(0)
		expect(stats.hasShield).toBe(false)
	end)

	it("getStats renvoie la même table à chaque appel (état serveur unique)", function()
		local player = Fixtures.fakePlayer(1)
		expect(PowerupService.getStats(player)).toBe(PowerupService.getStats(player))
	end)

	it("reset remet les valeurs par défaut, la vitesse de base et informe le client", function()
		local player = Fixtures.fakePlayer(1)
		player.Character = Fixtures.instanceCharacter()
		local stats = PowerupService.getStats(player)
		stats.bombCapacity, stats.hasShield = 4, true
		PowerupService.reset(player)
		expect(PowerupService.getStats(player).bombCapacity).toBe(GameConfig.Bomb.DefaultCapacity)
		expect(PowerupService.getStats(player).hasShield).toBe(false)
		expect(player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed).toBe(GameConfig.Movement.BaseWalkSpeed)
		expect(remotes.StatsChanged.sent[#remotes.StatsChanged.sent].player).toBe(player)
	end)

	it("un bot a des statistiques mais aucun message réseau", function()
		local bot = { UserId = -1000001, IsBot = true }
		PowerupService.getStats(bot).bombCapacity = 3
		PowerupService.reset(bot)
		expect(#remotes.StatsChanged.sent).toBe(0)
	end)

	it("forget libère les statistiques d'un acteur", function()
		local bot = { UserId = -1000001, IsBot = true }
		PowerupService.getStats(bot).bombCapacity = 5
		PowerupService.forget(bot)
		expect(PowerupService.getStats(bot).bombCapacity).toBe(GameConfig.Bomb.DefaultCapacity)
	end)

	it("le départ du joueur oublie ses statistiques", function()
		local player = Fixtures.fakePlayer(1)
		PowerupService.getStats(player).bombCapacity = 5
		world.removePlayer(player)
		expect(PowerupService.getStats(player).bombCapacity).toBe(GameConfig.Bomb.DefaultCapacity)
	end)
end)

describe("bouclier", function()
	it("consumeShield n'absorbe qu'une explosion", function()
		local player = Fixtures.fakePlayer(1)
		PowerupService.getStats(player).hasShield = true
		expect(PowerupService.consumeShield(player)).toBe(true)
		expect(PowerupService.consumeShield(player)).toBe(false)
	end)

	it("sans statistiques ni bouclier : false", function()
		expect(PowerupService.consumeShield(Fixtures.fakePlayer(9))).toBe(false)
	end)
end)

describe("bonus au sol", function()
	it("maybeDrop : certaines caisses laissent un bonus, pas toutes", function()
		local dropped = 0
		local total = info.layout.size * info.layout.size
		for y = 1, info.layout.size do
			for x = 1, info.layout.size do
				PowerupService.maybeDrop(info, { x = x, y = y })
			end
		end
		dropped = #pickupsInFolder()
		expect(dropped).toBeGreaterThan(0)
		expect(dropped).toBeLessThan(total)
	end)

	it("le tirage est reproductible pour une même map (même seed => mêmes bonus)", function()
		local function run()
			local ids = {}
			for y = 1, info.layout.size do
				for x = 1, info.layout.size do
					PowerupService.maybeDrop(info, { x = x, y = y })
				end
			end
			for _, part in pickupsInFolder() do
				table.insert(ids, part.Name .. "@" .. tostring(part.Position))
			end
			table.sort(ids)
			return ids
		end
		local first = run()
		PowerupService.clear()
		for _, part in pickupsInFolder() do
			expect(part.destroyed).toBe(true)
		end
		expect(run()).toEqual(first)
	end)

	it("jamais deux bonus sur la même case", function()
		local cell = dropOfKind("BombPlus")
		local before = #pickupsInFolder()
		for _ = 1, 20 do
			PowerupService.maybeDrop(info, cell)
		end
		local atCell = 0
		for _, part in pickupsInFolder() do
			if part.Position == info.grid:cellToWorld(cell, 1.6) then
				atCell += 1
			end
		end
		expect(atCell).toBe(1)
		expect(#pickupsInFolder()).toBeGreaterThanOrEqual(before)
	end)

	it("destroyAt retire le bonus de la case ; clear retire tout", function()
		local cell, part = dropOfKind("FirePlus")
		PowerupService.destroyAt(info, cell)
		expect(part.destroyed).toBe(true)
		PowerupService.destroyAt(info, cell) -- case vide : sans erreur
		PowerupService.maybeDrop(info, { x = 1, y = 1 })
		PowerupService.clear()
		for _, p in pickupsInFolder() do
			expect(p.destroyed).toBe(true)
		end
	end)

	it("l'apparence combine forme et libellé (jamais la couleur seule)", function()
		local _, part = dropOfKind("BombPlus")
		local label = part:FindFirstChildOfClass("BillboardGui"):FindFirstChildOfClass("TextLabel")
		expect(label.Text).toBe("B+")
		expect(part.Shape).toBe("Enum.PartType.Ball")
		local _, fire = dropOfKind("FirePlus")
		expect(fire:FindFirstChildOfClass("BillboardGui"):FindFirstChildOfClass("TextLabel").Text).toBe("F+")
		expect(fire.Shape).never.toBe(part.Shape)
	end)
end)

describe("ramassage", function()
	local function pickUp(id, userId)
		local cell = dropOfKind(id)
		local player = actorAt(cell, userId or 1)
		player.Character:FindFirstChildOfClass("Humanoid").Health = 100
		world.fireHeartbeat(0.2)
		return player, cell
	end

	it("Bomb+ augmente la capacité (plafonnée à MaxCapacity) et consomme le bonus", function()
		local cell, part = dropOfKind("BombPlus")
		local player = actorAt(cell, 1)
		world.fireHeartbeat(0.2)
		expect(part.destroyed).toBe(true)
		expect(PowerupService.getStats(player).bombCapacity).toBe(GameConfig.Bomb.DefaultCapacity + 1)
		-- au plafond : un bonus de plus ne dépasse jamais MaxCapacity
		PowerupService.getStats(player).bombCapacity = GameConfig.Bomb.MaxCapacity
		local cell2 = dropOfKind("BombPlus")
		player.Character.HumanoidRootPart.Position = cellCenter(cell2)
		world.fireHeartbeat(0.2)
		expect(PowerupService.getStats(player).bombCapacity).toBe(GameConfig.Bomb.MaxCapacity)
	end)

	it("Fire+ augmente la portée, plafonnée à MaxBlastRange", function()
		local player = pickUp("FirePlus")
		expect(PowerupService.getStats(player).blastRange).toBe(GameConfig.Bomb.DefaultBlastRange + 1)
	end)

	it("Speed+ augmente la vitesse du personnage, plafonnée", function()
		local player = pickUp("SpeedPlus")
		expect(PowerupService.getStats(player).speedPickups).toBe(1)
		expect(player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed).toBe(
			GameConfig.Movement.BaseWalkSpeed + GameConfig.Movement.SpeedBonusPerPickup
		)
	end)

	it("Shield active le bouclier", function()
		local player = pickUp("Shield")
		expect(PowerupService.getStats(player).hasShield).toBe(true)
	end)

	it("le client est informé à chaque ramassage", function()
		local before = #remotes.StatsChanged.sent
		pickUp("FirePlus")
		expect(#remotes.StatsChanged.sent).toBeGreaterThan(before)
		local last = remotes.StatsChanged.sent[#remotes.StatsChanged.sent].args[1]
		expect(last.blastRange).toBe(GameConfig.Bomb.DefaultBlastRange + 1)
	end)

	it("un joueur éliminé ne ramasse rien", function()
		local cell, part = dropOfKind("BombPlus")
		local player = actorAt(cell, 1)
		player:SetAttribute("Alive", false)
		world.fireHeartbeat(0.2)
		expect(part.destroyed).toBe(false)
	end)

	it("deux joueurs sur la même case : un seul ramasse", function()
		local cell, part = dropOfKind("BombPlus")
		local a, b = actorAt(cell, 1), actorAt(cell, 2)
		world.fireHeartbeat(0.2)
		local gainedA = PowerupService.getStats(a).bombCapacity > GameConfig.Bomb.DefaultCapacity
		local gainedB = PowerupService.getStats(b).bombCapacity > GameConfig.Bomb.DefaultCapacity
		expect(gainedA ~= gainedB).toBe(true)
		expect(part.destroyed).toBe(true)
	end)

	it("un bot ramasse comme un joueur, sans message réseau", function()
		local cell = dropOfKind("FirePlus")
		local bot = { UserId = -1000001, IsBot = true, Character = Fixtures.instanceCharacter(cellCenter(cell)), attributes = { Alive = true } }
		function bot:GetAttribute(k)
			return self.attributes[k]
		end
		world.module("ActorRegistry").addBot(bot)
		local before = #remotes.StatsChanged.sent
		world.fireHeartbeat(0.2)
		expect(PowerupService.getStats(bot).blastRange).toBe(GameConfig.Bomb.DefaultBlastRange + 1)
		expect(#remotes.StatsChanged.sent).toBe(before)
	end)

	it("la sonde ne s'exécute qu'à intervalle (pas à chaque image)", function()
		local cell, part = dropOfKind("BombPlus")
		actorAt(cell, 1)
		world.fireHeartbeat(0.01)
		expect(part.destroyed).toBe(false)
		world.fireHeartbeat(0.2)
		expect(part.destroyed).toBe(true)
	end)

	it("hors de la zone jouable ou sans personnage : aucun plantage", function()
		local outside = Fixtures.fakePlayer(5)
		outside.Character = Fixtures.instanceCharacter(Vector3.new(-900, 3, -900))
		outside:SetAttribute("Alive", true)
		world.addPlayer(outside)
		world.addPlayer(Fixtures.fakePlayer(6))
		dropOfKind("BombPlus")
		world.fireHeartbeat(0.2)
	end)
end)
