--!nocheck
-- Fabriques de données de test partagées par les suites (exposées aux specs sous le nom global `Fixtures`).

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Loader = require("./loader")

return function(world)
	local Fixtures = {}

	-- Grille vide size x size (toutes les cases EMPTY). Retourne (grille, cases) : modifier `cases[y][x]` change la grille.
	function Fixtures.emptyGrid(size: number?, cellSize: number?)
		local GridService = world.module("GridService")
		local n = size or 9
		local cells = {}
		for y = 1, n do
			cells[y] = {}
			for x = 1, n do
				cells[y][x] = "EMPTY"
			end
		end
		local layout = { seed = 1, sizeId = "T", size = n, theme = "Classic", cells = cells, spawns = {} }
		return GridService.new(layout, cellSize or 4, Vector3.zero), cells
	end

	-- Faux personnage : Humanoid + HumanoidRootPart. Il avance vers la cible de MoveTo à WalkSpeed studs/s, à chaque pas
	-- de simulation (world.advance). `character.destroyed` passe à true après Destroy().
	function Fixtures.fakeCharacter(position)
		local root = {
			Position = position or Vector3.zero,
			IsA = function(_self, className)
				return className == "BasePart"
			end,
			SetNetworkOwner = function() end,
		}
		local humanoid = {
			Health = 100,
			WalkSpeed = 16,
			target = nil,
			IsA = function(_self, className)
				return className == "Humanoid"
			end,
		}
		function humanoid:MoveTo(target)
			self.target = target
		end
		local character = { Name = "Character", destroyed = false, root = root, humanoid = humanoid }
		function character:PivotTo(cframe)
			root.Position = cframe.Position
		end
		function character:FindFirstChildOfClass(className)
			return if className == "Humanoid" then humanoid else nil
		end
		function character:FindFirstChild(name)
			return if name == "HumanoidRootPart" then root elseif name == "Humanoid" then humanoid else nil
		end
		function character:WaitForChild(name)
			return character:FindFirstChild(name)
		end
		function character:Destroy()
			self.destroyed = true
		end
		world.onStep(function(dt)
			local target = humanoid.target
			if not target or character.destroyed or humanoid.Health <= 0 then
				return
			end
			local dx, dz = target.X - root.Position.X, target.Z - root.Position.Z
			local distance = math.sqrt(dx * dx + dz * dz)
			local step = humanoid.WalkSpeed * dt
			if distance <= step then
				root.Position = Vector3.new(target.X, root.Position.Y, target.Z)
				humanoid.target = nil
			else
				root.Position = Vector3.new(
					root.Position.X + dx / distance * step,
					root.Position.Y,
					root.Position.Z + dz / distance * step
				)
			end
		end)
		return character
	end

	-- Personnage fait d'instances génériques : Model > Humanoid, HumanoidRootPart, Head (voir instances.luau).
	-- Contrairement à fakeCharacter, il ne bouge pas tout seul : on pose sa position avec character.HumanoidRootPart.Position.
	function Fixtures.instanceCharacter(position)
		local Instance = world.env.Instance
		local model = Instance.new("Model")
		model.Name = "Character"
		Instance.new("Humanoid", model)
		local root = Instance.new("Part", model)
		root.Name = "HumanoidRootPart"
		root.Position = position or Vector3.zero
		local head = Instance.new("Part", model)
		head.Name = "Head"
		head.Position = (position or Vector3.zero) + Vector3.new(0, 2, 0)
		return model
	end

	-- Joueur factice. Parent = service Players (PlayerDataService.load vérifie que le joueur est toujours présent).
	-- LoadCharacter crée un faux personnage et déclenche CharacterAdded, comme Roblox ; `loadCount` les compte.
	function Fixtures.fakePlayer(userId: number, name: string?)
		local characterAdded, fireCharacterAdded = Loader.newSignal()
		local player = {
			_isInstance = true,
			UserId = userId,
			Name = name or ("Joueur" .. userId),
			DisplayName = name or ("Joueur" .. userId),
			Parent = world.game:GetService("Players"),
			Character = nil,
			CharacterAdded = characterAdded,
			loadCount = 0,
			_attributes = {},
		}
		function player:GetAttribute(k)
			return self._attributes[k]
		end
		function player:SetAttribute(k, v)
			self._attributes[k] = v
		end
		function player:LoadCharacter()
			self.loadCount += 1
			self.Character = Fixtures.fakeCharacter(Vector3.zero)
			fireCharacterAdded(self.Character)
		end
		return player
	end

	-- Dossier de remotes factice : remotes.<Nom> est un RemoteEvent simulé.
	--   remote.OnServerEvent:Connect(function(player, ...) end)   (réception serveur)
	--   remote:fireServer(player, ...)                            (simule un envoi client)
	--   remote.sent                                               (liste des FireClient/FireAllClients : { player, args })
	function Fixtures.fakeRemotes(names: { string })
		local folder = { _remotes = {} }
		for _, name in names do
			local signal, fire = Loader.newSignal()
			local clientSignal, fireClientEvent = Loader.newSignal()
			local remote = {
				Name = name,
				OnServerEvent = signal,
				OnClientEvent = clientSignal,
				sent = {},
				sentToServer = {}, -- appels FireServer (côté client)
				IsA = function(_self, className)
					return className == "RemoteEvent"
				end,
			}
			function remote:FireServer(...)
				table.insert(self.sentToServer, table.pack(...))
			end
			-- Simule un message du serveur reçu par le client.
			function remote:fireClient(...)
				fireClientEvent(...)
			end
			function remote:fireServer(player, ...)
				fire(player, ...)
			end
			function remote:FireClient(player, ...)
				table.insert(self.sent, { player = player, args = table.pack(...) })
			end
			function remote:FireAllClients(...)
				table.insert(self.sent, { player = "all", args = table.pack(...) })
			end
			folder[name] = remote
			folder._remotes[name] = remote
		end
		function folder:WaitForChild(name)
			return folder._remotes[name] or error("remote inconnu : " .. tostring(name), 2)
		end
		function folder:FindFirstChild(name)
			return folder._remotes[name]
		end
		return folder
	end

	-- MapService de test : génération et grille RÉELLES (MapGenerator, GridService), sans aucune Part.
	function Fixtures.mockMapService(calls)
		local MapGenerator = world.module("MapGenerator")
		local GridService = world.module("GridService")
		local MapConfig = world.module("MapConfig")
		local current = nil
		return world.mock("MapService", {
			generateAndBuild = function(sizeDef, seed, total, themeId)
				local layout = MapGenerator.generate(sizeDef, seed, total, themeId)
				current = { layout = layout, grid = GridService.new(layout, MapConfig.CellSize, Vector3.zero) }
				if calls then
					table.insert(calls.map, { sizeId = sizeDef.id, seed = seed, total = total, theme = themeId })
				end
				return current
			end,
			getCurrent = function()
				return current
			end,
			destroy = function()
				current = nil
			end,
		})
	end

	-- Harnais complet de RoundService : remplace les services dépendant du moteur par des doubles (la génération de
	-- carte, la grille, les récompenses et les profils restent RÉELS), charge RoundService et le démarre.
	-- Les clients simulés envoient avec harness.remotes.SetQueued:fireServer(player, true) ; le temps s'écoule avec
	-- world.advance(secondes).
	function Fixtures.roundHarness()
		local BotActor = world.module("BotActor")
		local calls = { map = {}, botsCreated = 0, botsCleared = 0, bombsCleared = 0, aiStarted = 0 }

		Fixtures.mockMapService(calls)
		world.mock("BombService", {
			clear = function()
				calls.bombsCleared += 1
			end,
		})

		local eliminatedCallback = nil
		local damage = { alive = {} }
		function damage.onEliminated(callback)
			eliminatedCallback = callback
		end
		function damage.setAlive(player, value)
			damage.alive[player] = value
		end
		function damage.isAlive(player)
			return damage.alive[player] == true
		end
		-- Comme le vrai DamageService : élimine un acteur et prévient RoundService.
		function damage.eliminate(player)
			if eliminatedCallback then
				eliminatedCallback(player)
			end
			return true
		end
		world.mock("DamageService", damage)

		local movement = { setup = {}, cancelled = {}, forgotten = {} }
		function movement.setupCharacter(player)
			table.insert(movement.setup, player)
		end
		function movement.cancel(player)
			table.insert(movement.cancelled, player)
		end
		function movement.forget(actor)
			table.insert(movement.forgotten, actor)
		end
		world.mock("MovementService", movement)

		world.mock("PowerupService", { reset = function() end, forget = function() end })

		local ActorRegistry = world.module("ActorRegistry")
		local bots = {}
		world.mock("BotService", {
			clear = function()
				calls.botsCleared += 1
				table.clear(bots)
				ActorRegistry.clearBots()
			end,
			createBots = function(count, difficulties)
				for index = 1, count do
					local bot = BotActor.new(index, difficulties and difficulties[index] or nil)
					table.insert(bots, bot)
					ActorRegistry.addBot(bot)
				end
				calls.botsCreated += count
				return table.clone(bots)
			end,
			buildCharacter = function()
				return nil
			end,
			startAI = function()
				calls.aiStarted += 1
			end,
		})

		local DataBackend = world.module("DataBackend")
		local PlayerDataService = world.module("PlayerDataService")
		PlayerDataService.setBackend(DataBackend.memory())

		local remotes = Fixtures.fakeRemotes({ "RoundState", "RoundEnded", "MapReady", "SetReady", "SetQueued", "PartyAction", "Notice" })
		local RoundService = world.module("RoundService")
		RoundService.start(remotes)

		local harness = { RoundService = RoundService, remotes = remotes, damage = damage, movement = movement, calls = calls, bots = bots }

		-- Ajoute un joueur connecté, profil chargé. queue = true : clique PLAY.
		function harness.join(userId: number, queue: boolean?)
			local player = Fixtures.fakePlayer(userId)
			PlayerDataService.load(player)
			world.addPlayer(player)
			if queue then
				remotes.SetQueued:fireServer(player, true)
			end
			return player
		end

		-- Dernier instantané diffusé à tous les clients.
		function harness.lastSnapshot()
			for index = #remotes.RoundState.sent, 1, -1 do
				local sent = remotes.RoundState.sent[index]
				if sent.player == "all" then
					return sent.args[1]
				end
			end
			return nil
		end

		-- Dernier message de la remote Notice envoyé à `player`.
		function harness.lastNotice(player)
			for index = #remotes.Notice.sent, 1, -1 do
				if remotes.Notice.sent[index].player == player then
					return remotes.Notice.sent[index].args[1]
				end
			end
			return nil
		end

		-- Avance jusqu'à l'état voulu (au plus `limit` secondes simulées) ; retourne true si atteint.
		function harness.advanceUntil(stateName: string, limit: number?)
			local waited = 0
			while RoundService.getState() ~= stateName and waited < (limit or 60) do
				world.advance(0.2)
				waited += 0.2
			end
			return RoundService.getState() == stateName
		end

		return harness
	end

	return Fixtures
end
