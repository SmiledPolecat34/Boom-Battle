--!nocheck
-- BombService : pose (règles et capacité), mèche, explosion, chaînes, caisses, dégâts, bouclier, zones de danger,
-- cadence réseau, nettoyage. Intégration réelle de MapService, ExplosionResolver, DamageService, PowerupService et
-- PlayerDataService dans un temps simulé (world.advance) ; seules les Parts sont des instances génériques simulées.
local GameConfig = world.module("GameConfig")
local MapConfig = world.module("MapConfig")

local BombService, MapService, DamageService, PowerupService, PlayState, GameEvents, PlayerDataService
local info, remotes

local FUSE = GameConfig.Bomb.FuseTime
local FLAMES = GameConfig.Bomb.ExplosionDuration

local function center(cell)
	return info.grid:cellToWorld(cell, 3)
end

-- Joueur vivant, actif en manche, debout sur la case `cell`.
local function player(userId, cell)
	local p = Fixtures.fakePlayer(userId)
	p.Character = Fixtures.instanceCharacter(center(cell))
	world.addPlayer(p)
	DamageService.setAlive(p, true)
	PlayState.setActive(p, true)
	return p
end

local function moveTo(p, cell)
	p.Character.HumanoidRootPart.Position = center(cell)
end

local function bombParts()
	local list = {}
	for _, child in info.folder:GetChildren() do
		if child.Name == "Bomb" then
			table.insert(list, child)
		end
	end
	return list
end

local spawn1, spawn2

beforeEach(function()
	world.reset()
	MapService = world.module("MapService")
	DamageService = world.module("DamageService")
	PowerupService = world.module("PowerupService")
	PlayState = world.module("PlayState")
	GameEvents = world.module("GameEvents")
	PlayerDataService = world.module("PlayerDataService")
	PlayerDataService.setBackend(world.module("DataBackend").memory())
	BombService = world.module("BombService")

	info = MapService.generateAndBuild(MapConfig.Sizes.Medium, 777, 4)
	spawn1, spawn2 = info.layout.spawns[1], info.layout.spawns[2]
	remotes = Fixtures.fakeRemotes({ "Explosion", "RequestPlaceBomb", "PlayerEliminated", "StatsChanged" })
	DamageService.start(remotes)
	PowerupService.start(remotes)
	BombService.start(remotes)
	PlayState.setState("PLAYING")
end)

afterEach(function()
	PlayState.clearActive()
	PlayState.setState("WAITING")
end)

describe("pose", function()
	it("pose une bombe sur la case SERVEUR du joueur : Part, grille bloquée, compteur", function()
		local p = player(1, spawn1)
		expect(BombService.placeBomb(p)).toBe(true)
		expect(#bombParts()).toBe(1)
		expect(info.grid:hasBomb(spawn1.x, spawn1.y)).toBe(true)
		expect(bombParts()[1].Position).toEqual(info.grid:cellToWorld(spawn1, 1.6))
	end)

	it("refuse hors manche (lobby, compte à rebours, fin) et pour un spectateur ou un éliminé", function()
		local p = player(1, spawn1)
		for _, state in { "WAITING", "READY", "COUNTDOWN", "FINISHED", "RESETTING" } do
			PlayState.setState(state)
			expect(BombService.placeBomb(p)).toBe(false)
		end
		PlayState.setState("PLAYING")
		PlayState.setActive(p, false)
		expect(BombService.placeBomb(p)).toBe(false)
		PlayState.setActive(p, true)
		DamageService.setAlive(p, false)
		expect(BombService.placeBomb(p)).toBe(false)
		expect(#bombParts()).toBe(0)
	end)

	it("refuse sans personnage ou hors de la zone jouable", function()
		local noBody = Fixtures.fakePlayer(2)
		PlayState.setActive(noBody, true)
		expect(BombService.placeBomb(noBody)).toBe(false)
		local lost = player(3, spawn1)
		lost.Character.HumanoidRootPart.Position = Vector3.new(-800, 3, -800)
		expect(BombService.placeBomb(lost)).toBe(false)
	end)

	it("une seule bombe par case ; la capacité (1 par défaut) limite les bombes actives", function()
		local p = player(1, spawn1)
		expect(BombService.canPlaceBomb(p)).toBe(true)
		expect(BombService.placeBomb(p)).toBe(true)
		expect(BombService.canPlaceBomb(p)).toBe(false)
		moveTo(p, { x = spawn1.x + 1, y = spawn1.y })
		expect(BombService.placeBomb(p)).toBe(false) -- capacité atteinte
		PowerupService.getStats(p).bombCapacity = 2
		expect(BombService.placeBomb(p)).toBe(true)
		moveTo(p, spawn1)
		PowerupService.getStats(p).bombCapacity = 5
		expect(BombService.placeBomb(p)).toBe(false) -- case déjà occupée par une bombe
		expect(#bombParts()).toBe(2)
	end)

	it("la capacité est rendue après l'explosion", function()
		local p = player(1, spawn1)
		BombService.placeBomb(p)
		moveTo(p, { x = spawn1.x + 3, y = spawn1.y + 3 })
		world.advance(FUSE + 0.1)
		expect(BombService.canPlaceBomb(p)).toBe(true)
	end)

	it("la couleur de la bombe suit le cosmétique équipé, la taille ne change jamais", function()
		local p = player(1, spawn1)
		PlayerDataService.load(p)
		PlayerDataService.mutate(p, function(profile)
			profile.OwnedCosmetics.bomb_red = true
			profile.EquippedCosmetics.bomb = "bomb_red"
		end)
		BombService.placeBomb(p)
		local part = bombParts()[1]
		expect(part.Color).toEqual(world.module("CosmeticConfig").get("bomb_red").color)
		expect(part.Size).toEqual(Vector3.new(3, 3, 3))
	end)

	it("la bombe porte l'identifiant de son apparence et la hauteur du sol (le client y accroche le modèle 3D)", function()
		local p = player(1, spawn1)
		PlayerDataService.load(p)
		PlayerDataService.mutate(p, function(profile)
			profile.OwnedCosmetics.bomb_cosmic = true
			profile.EquippedCosmetics.bomb = "bomb_cosmic"
		end)
		BombService.placeBomb(p)
		local part = bombParts()[1]
		expect(part:GetAttribute("BBBombSkin")).toBe("bomb_cosmic")
		local ground = part:GetAttribute("BBGroundY")
		expect(type(ground)).toBe("number")
		expect(math.abs(ground - (part.Position.Y - 1.6)) < 1e-6).toBe(true)
	end)

	it("sans profil chargé, la bombe porte l'apparence par défaut ; la sphère de repli et sa taille ne changent pas", function()
		local p = player(1, spawn1)
		BombService.placeBomb(p)
		local part = bombParts()[1]
		expect(part:GetAttribute("BBBombSkin")).toBe("bomb_classic")
		expect(part.Size).toEqual(Vector3.new(3, 3, 3))
		expect(part.CanCollide).toBe(false)
	end)

	it("la bombe porte l'instant de pose (BBPlacedAt) : les clients en tirent la progression de la mèche", function()
		local p = player(1, spawn1)
		BombService.placeBomb(p)
		expect(type(bombParts()[1]:GetAttribute("BBPlacedAt"))).toBe("number")
	end)
end)

describe("explosion", function()
	it("la bombe explose après la mèche : Part détruite, case libérée, remote avec cases et durée", function()
		local p = player(1, spawn1)
		BombService.placeBomb(p)
		moveTo(p, { x = spawn1.x + 4, y = spawn1.y + 4 })
		world.advance(FUSE - 0.2)
		expect(info.grid:hasBomb(spawn1.x, spawn1.y)).toBe(true)
		expect(#remotes.Explosion.sent).toBe(0)
		world.advance(0.4)
		expect(#bombParts()).toBe(0)
		expect(info.grid:hasBomb(spawn1.x, spawn1.y)).toBe(false)
		local payload = remotes.Explosion.sent[1].args[1]
		expect(#payload.cells).toBeGreaterThan(1)
		expect(payload.duration).toBe(FLAMES)
	end)

	it("le poseur resté dans la zone est éliminé ; celui qui s'est éloigné survit", function()
		local stays = player(1, spawn1)
		BombService.placeBomb(stays)
		local flees = player(2, { x = spawn1.x + 5, y = spawn1.y + 5 })
		world.advance(FUSE + FLAMES + 0.3)
		expect(DamageService.isAlive(stays)).toBe(false)
		expect(DamageService.isAlive(flees)).toBe(true)
		expect(remotes.PlayerEliminated.sent[1].args[1]).toBe(1)
	end)

	it("un joueur n'est touché qu'une fois par explosion (rappel d'élimination unique)", function()
		local eliminated = 0
		DamageService.onEliminated(function()
			eliminated += 1
		end)
		local p = player(1, spawn1)
		BombService.placeBomb(p)
		world.advance(FUSE + FLAMES + 0.3)
		expect(eliminated).toBe(1)
	end)

	it("le bouclier absorbe l'explosion : le joueur survit et le bouclier est consommé", function()
		local p = player(1, spawn1)
		PowerupService.getStats(p).hasShield = true
		BombService.placeBomb(p)
		world.advance(FUSE + FLAMES + 0.3)
		expect(DamageService.isAlive(p)).toBe(true)
		expect(PowerupService.getStats(p).hasShield).toBe(false)
	end)

	it("une caisse touchée est détruite (grille libérée), compte pour la quête, et arrête la propagation", function()
		local crateCell = { x = spawn1.x + 1, y = spawn1.y }
		info.grid:setKind(crateCell.x, crateCell.y, "CRATE")
		local destroyed = {}
		GameEvents.CratesDestroyed:Connect(function(owner, count)
			table.insert(destroyed, { owner = owner, count = count })
		end)
		local p = player(1, spawn1)
		BombService.placeBomb(p)
		moveTo(p, { x = spawn1.x, y = spawn1.y + 1 })
		world.advance(FUSE + 0.1)
		expect(info.grid:getKind(crateCell.x, crateCell.y)).toBe("EMPTY")
		expect(destroyed[1]).toEqual({ owner = 1, count = 1 })
		local cells = remotes.Explosion.sent[1].args[1].cells
		for _, c in cells do
			expect(c.x == crateCell.x + 1 and c.y == crateCell.y).toBe(false) -- derrière la caisse : protégé
		end
	end)

	it("réaction en chaîne : une bombe touchée explose avec la première, une seule fois", function()
		local a = player(1, spawn1)
		local neighbor = { x = spawn1.x + 1, y = spawn1.y }
		local b = player(2, neighbor)
		PowerupService.getStats(a).bombCapacity = 1
		BombService.placeBomb(a)
		BombService.placeBomb(b)
		moveTo(a, { x = spawn1.x + 6, y = spawn1.y + 6 })
		moveTo(b, { x = spawn1.x + 7, y = spawn1.y + 7 })
		world.advance(FUSE + 0.2)
		expect(#remotes.Explosion.sent).toBe(1) -- une explosion de chaîne, pas deux
		expect(#bombParts()).toBe(0)
		world.advance(FUSE + 1) -- la mèche de b ne déclenche rien de plus
		expect(#remotes.Explosion.sent).toBe(1)
	end)

	it("une bombe d'une ancienne arène n'explose plus après régénération de la carte", function()
		local p = player(1, spawn1)
		BombService.placeBomb(p)
		local newInfo = MapService.generateAndBuild(MapConfig.Sizes.Medium, 999, 4)
		world.advance(FUSE + 1)
		expect(#remotes.Explosion.sent).toBe(0)
		expect(newInfo ~= info).toBe(true)
	end)

	it("la couleur de l'explosion suit l'effet équipé, sans effet sur la portée", function()
		local p = player(1, spawn1)
		PlayerDataService.load(p)
		PlayerDataService.mutate(p, function(profile)
			profile.OwnedCosmetics.effect_red = true
			profile.EquippedCosmetics.effect = "effect_red"
		end)
		BombService.placeBomb(p)
		moveTo(p, { x = spawn1.x + 5, y = spawn1.y + 5 })
		world.advance(FUSE + 0.1)
		expect(remotes.Explosion.sent[1].args[1].color).toEqual(world.module("CosmeticConfig").get("effect_red").color)
	end)
end)

describe("zones de danger (pour les bots)", function()
	it("la zone d'une bombe armée est dangereuse, puis les flammes, puis plus rien", function()
		local p = player(1, spawn1)
		BombService.placeBomb(p)
		local key = info.grid:key(spawn1.x + 1, spawn1.y)
		expect(BombService.getDangerKeys(info)[key]).toBe(true)
		moveTo(p, { x = spawn1.x + 6, y = spawn1.y + 6 })
		world.advance(FUSE + 0.1)
		expect(BombService.getDangerKeys(info)[key]).toBe(true) -- flammes encore actives
		world.advance(FLAMES + 0.2)
		expect(next(BombService.getDangerKeys(info))).toBeNil()
	end)

	it("sans bombe : aucune case dangereuse", function()
		expect(next(BombService.getDangerKeys(info))).toBeNil()
	end)
end)

describe("réseau et nettoyage", function()
	it("RequestPlaceBomb pose une bombe à la position serveur du joueur", function()
		local p = player(1, spawn1)
		remotes.RequestPlaceBomb:fireServer(p)
		expect(#bombParts()).toBe(1)
	end)

	it("la cadence est limitée : la 2e demande immédiate est ignorée, puis acceptée plus tard", function()
		local p = player(1, spawn1)
		PowerupService.getStats(p).bombCapacity = 3
		remotes.RequestPlaceBomb:fireServer(p)
		moveTo(p, { x = spawn1.x + 1, y = spawn1.y })
		remotes.RequestPlaceBomb:fireServer(p)
		expect(#bombParts()).toBe(1)
		world.advance(GameConfig.RemoteLimits.PlaceBombMinInterval + 0.05)
		remotes.RequestPlaceBomb:fireServer(p)
		expect(#bombParts()).toBe(2)
	end)

	it("clear oublie les bombes et les bonus ; le départ d'un joueur libère sa cadence", function()
		local p = player(1, spawn1)
		BombService.placeBomb(p)
		BombService.clear()
		expect(next(BombService.getDangerKeys(info))).toBeNil()
		expect(BombService.canPlaceBomb(p)).toBe(true)
		world.removePlayer(p)
	end)

	it("un acteur non joueur (bot) pose comme un joueur", function()
		local bot = { UserId = -1000001, IsBot = true, Character = Fixtures.instanceCharacter(center(spawn2)), attributes = { Alive = true } }
		function bot:GetAttribute(k)
			return self.attributes[k]
		end
		function bot:SetAttribute(k, v)
			self.attributes[k] = v
		end
		PlayState.setActive(bot, true)
		expect(BombService.placeBomb(bot)).toBe(true)
	end)
end)
