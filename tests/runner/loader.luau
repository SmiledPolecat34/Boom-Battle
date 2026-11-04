--!nocheck
-- Chargeur : reproduit hors Studio l'arbre d'instances décrit par default.project.json (Rojo) et le `require` Roblox
-- (require(instance)), pour exécuter les modules de src/ SANS les modifier.
--
-- Services simulés : ReplicatedStorage, ServerScriptService, StarterPlayer, Players, RunService, DataStoreService,
-- et quelques autres inoffensifs. Tout service ou classe non simulé LÈVE une erreur explicite (jamais de faux succès) :
-- un module qui en dépend appartient aux tests Studio (tests/Phase*Tests.luau), pas aux tests Lune.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Instances = require("./instances")

local Loader = {}

-- Signal / BindableEvent -------------------------------------------------------------------------------------------
local function newSignal()
	local handlers: { [number]: (...any) -> () } = {}
	local nextId = 0
	local signal = {}

	function signal:Connect(handler)
		nextId += 1
		local id = nextId
		handlers[id] = handler
		return {
			Connected = true,
			Disconnect = function(self)
				self.Connected = false
				handlers[id] = nil
			end,
		}
	end

	function signal:Once(handler)
		local connection
		connection = signal:Connect(function(...)
			connection:Disconnect()
			handler(...)
		end)
		return connection
	end

	local function fire(...)
		-- copie des gestionnaires : un gestionnaire peut se déconnecter pendant l'appel.
		local snapshot = {}
		for id, handler in handlers do
			snapshot[id] = handler
		end
		local args = table.pack(...)
		for _, handler in snapshot do
			handler(table.unpack(args, 1, args.n))
		end
	end

	function signal:_count()
		local n = 0
		for _ in handlers do
			n += 1
		end
		return n
	end

	return signal, fire
end

-- Nœuds d'instance ------------------------------------------------------------------------------------------------
local Node = {}
Node.__index = function(self, key)
	local children = rawget(self, "_children")
	if children[key] then
		return children[key]
	end
	local method = Node[key]
	if method ~= nil then
		return method
	end
	error(("'%s' n'existe pas sous '%s' (arbre Rojo simulé)"):format(tostring(key), rawget(self, "Name")), 2)
end

local function newNode(name: string, className: string, parent: any?)
	local node = setmetatable({ Name = name, ClassName = className, Parent = parent, _children = {}, _attributes = {} }, Node)
	if parent then
		rawget(parent, "_children")[name] = node
	end
	return node
end

function Node:FindFirstChild(name: string)
	return rawget(self, "_children")[name]
end

function Node:WaitForChild(name: string, timeout: number?)
	local child = rawget(self, "_children")[name]
	if child == nil and timeout ~= nil then
		return nil -- comme Roblox : expiration du délai => nil
	end
	return child or error(("WaitForChild('%s') : absent sous '%s' (arbre Rojo simulé)"):format(name, rawget(self, "Name")), 2)
end

function Node:GetChildren()
	local list = {}
	for _, child in rawget(self, "_children") do
		table.insert(list, child)
	end
	return list
end

function Node:SetAttribute(name: string, value: any)
	rawget(self, "_attributes")[name] = value
end

function Node:GetAttribute(name: string)
	return rawget(self, "_attributes")[name]
end

function Node:IsA(className: string)
	return rawget(self, "ClassName") == className
end

-- Lecture de l'arbre Rojo -------------------------------------------------------------------------------------------
local function stripExtension(fileName: string): (string?, string?)
	for _, suffix in { ".server.luau", ".client.luau", ".luau" } do
		if string.sub(fileName, -#suffix) == suffix then
			local kind = if suffix == ".luau" then "ModuleScript" elseif suffix == ".server.luau" then "Script" else "LocalScript"
			return string.sub(fileName, 1, #fileName - #suffix), kind
		end
	end
	return nil, nil
end

local function mountDirectory(path: string, node: any, sources: { [any]: { path: string, kind: string } })
	for _, entry in fs.readDir(path) do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			mountDirectory(full, newNode(entry, "Folder", node), sources)
		else
			local name, kind = stripExtension(entry)
			if name then
				local child = newNode(name, kind, node)
				sources[child] = { path = full, kind = kind }
			end
		end
	end
end

local function mountTree(definition: any, node: any, root: string, sources: any)
	for key, value in definition do
		if string.sub(key, 1, 1) == "$" then
			if key == "$path" then
				mountDirectory(root .. "/" .. value, node, sources)
			end
		elseif type(value) == "table" then
			mountTree(value, newNode(key, value["$className"] or "Folder", node), root, sources)
		end
	end
end

-- Chargeur --------------------------------------------------------------------------------------------------------
--- Crée un « monde » isolé : arbre, cache de modules, services simulés.
--- `root` : racine du dépôt (contient default.project.json et src/).
function Loader.new(root: string)
	local project = serde.decode("json", fs.readFile(root .. "/default.project.json"))
	local gameNode = newNode("Game", "DataModel", nil)
	local sources = {}
	mountTree(project.tree, gameNode, root, sources)

	local world = { root = root, game = gameNode, sources = sources, cache = {}, loading = {} }

	-- Services simulés ----------------------------------------------------------------------------------------------
	local playerAdded, firePlayerAdded = newSignal()
	local playerRemoving, firePlayerRemoving = newSignal()
	local players = {}
	local playersService = {
		Name = "Players",
		PlayerAdded = playerAdded,
		PlayerRemoving = playerRemoving,
		GetPlayers = function()
			return table.clone(players)
		end,
		GetPlayerByUserId = function(_self, userId)
			for _, p in players do
				if p.UserId == userId then
					return p
				end
			end
			return nil
		end,
	}
	-- Accessible aux tests pour simuler une arrivée / un départ.
	function world.addPlayer(player: any)
		table.insert(players, player)
		firePlayerAdded(player)
	end
	function world.removePlayer(player: any)
		local index = table.find(players, player)
		if index then
			table.remove(players, index)
		end
		firePlayerRemoving(player)
	end

	local heartbeat, fireHeartbeat = newSignal()
	world.fireHeartbeat = fireHeartbeat
	local renderStepped, fireRenderStepped = newSignal()
	world.fireRenderStepped = fireRenderStepped
	local runService = {
		Name = "RunService",
		Heartbeat = heartbeat,
		RenderStepped = renderStepped,
		IsStudio = function()
			return false
		end,
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
	}

	-- Banque de données en mémoire : chaque test peut vérifier ce qui a été « sauvegardé ».
	local stores = {}
	world.dataStores = stores
	world.dataStoreFailure = nil -- chaîne : fait échouer tous les accès (simule une panne)
	local dataStoreService = {
		Name = "DataStoreService",
		GetDataStore = function(_self, name)
			stores[name] = stores[name] or {}
			local data = stores[name]
			return {
				GetAsync = function(_s, key)
					if world.dataStoreFailure then
						error(world.dataStoreFailure)
					end
					return data[key]
				end,
				UpdateAsync = function(_s, key, transform)
					if world.dataStoreFailure then
						error(world.dataStoreFailure)
					end
					data[key] = transform(data[key])
				end,
			}
		end,
	}

	local services = {
		Players = playersService,
		RunService = runService,
		DataStoreService = dataStoreService,
		ReplicatedStorage = gameNode:FindFirstChild("ReplicatedStorage"),
		ServerScriptService = gameNode:FindFirstChild("ServerScriptService"),
		StarterPlayer = gameNode:FindFirstChild("StarterPlayer"),
	}

	function gameNode:GetService(name: string)
		local service = services[name]
		if service == nil then
			error(("Service '%s' non simulé : ce module relève des tests Studio (tests/Phase*Tests.luau)"):format(name), 2)
		end
		return service
	end

	-- Environnement des modules ---------------------------------------------------------------------------------------
	local function instanceNew(className: string, parent: any?)
		if className == "BindableEvent" then
			local event, fire = newSignal()
			return { ClassName = className, Event = event, Fire = function(_self, ...) fire(...) end, Destroy = function() end }
		end
		-- Toute autre classe : instance générique simulée (voir instances.luau).
		return Instances.new(className, parent, { newSignal = newSignal })
	end

	-- Random déterministe de remplacement (le vrai Random de Roblox n'existe pas sous Lune).
	-- ATTENTION : la suite de nombres diffère de celle de Roblox ; les tests ne doivent pas dépendre de valeurs exactes.
	local Random = {}
	function Random.new(seed: number?)
		local state = (seed or 0) % 2147483647
		if state <= 0 then
			state += 2147483646
		end
		local rng = {}
		function rng:NextNumber(minimum: number?, maximum: number?)
			state = (state * 48271) % 2147483647
			local unit = state / 2147483647
			if minimum and maximum then
				return minimum + unit * (maximum - minimum)
			end
			return unit
		end
		function rng:NextInteger(minimum: number, maximum: number)
			return minimum + math.floor(rng:NextNumber() * (maximum - minimum + 1))
		end
		return rng
	end

	-- Horloge et ordonnanceur SIMULÉS. Le temps ne s'écoule que par world.advance(secondes) : les tests de machine
	-- d'états (manches, compte à rebours) sont donc instantanés et déterministes.
	-- task.wait n'est suspensif que dans un thread créé par task.spawn/delay/defer ; ailleurs (thread de test) il rend
	-- la main tout de suite, comme les attentes de réessai de PlayerDataService.
	local clock = { now = 1000 } -- > 0 : les limiteurs de cadence comparent à 0 au premier appel
	world.clock = clock
	local sleepers: { { wake: number, thread: thread, order: number } } = {}
	local mine: { [thread]: boolean } = {}
	local stepHooks: { (dt: number) -> () } = {}
	local order = 0
	local hookClock = { last = clock.now } -- dernier instant auquel les crochets de pas ont été appelés

	local function resume(thread: thread, ...)
		local ok, err = coroutine.resume(thread, ...)
		if not ok then
			table.insert(world.warnings, "erreur dans un thread simulé : " .. tostring(err))
		end
	end

	local function sleep(thread: thread, seconds: number)
		order += 1
		table.insert(sleepers, { wake = clock.now + math.max(seconds, 0), thread = thread, order = order })
	end

	local function start(fn: (...any) -> (), ...)
		local thread = coroutine.create(fn)
		mine[thread] = true
		resume(thread, ...)
		return thread
	end

	local taskLibrary = {
		spawn = start,
		defer = start,
		delay = function(seconds, fn, ...)
			local args = table.pack(...)
			local thread = coroutine.create(function()
				fn(table.unpack(args, 1, args.n))
			end)
			mine[thread] = true
			sleep(thread, seconds)
			return thread
		end,
		wait = function(seconds)
			local duration = seconds or 1 / 30
			local thread = coroutine.running()
			if mine[thread] then
				sleep(thread, duration)
				coroutine.yield()
			end
			return duration
		end,
		cancel = function(thread)
			for i = #sleepers, 1, -1 do
				if sleepers[i].thread == thread then
					table.remove(sleepers, i)
				end
			end
		end,
	}

	-- Fait avancer le temps simulé de `seconds`, par pas d'au plus 1/20 s, en réveillant les threads dans l'ordre.
	function world.advance(seconds: number)
		local target = clock.now + seconds
		while clock.now < target - 1e-9 do
			local nextStep = math.min(target, clock.now + 0.05)
			-- Réveille d'abord ce qui est dû avant la fin du pas, dans l'ordre chronologique.
			while true do
				local best = nil
				for index, sleeper in sleepers do
					if sleeper.wake <= nextStep + 1e-9 and (best == nil or sleeper.wake < sleepers[best].wake or (sleeper.wake == sleepers[best].wake and sleeper.order < sleepers[best].order)) then
						best = index
					end
				end
				if not best then
					break
				end
				local sleeper = table.remove(sleepers, best)
				clock.now = math.max(clock.now, sleeper.wake)
				resume(sleeper.thread)
			end
			clock.now = nextStep
			local dt = nextStep - hookClock.last
			hookClock.last = nextStep
			for _, hook in stepHooks do
				hook(math.max(dt, 0))
			end
		end
	end

	-- Fonction appelée à chaque pas de simulation (ex. déplacer un faux personnage vers sa cible).
	function world.onStep(hook: (dt: number) -> ())
		table.insert(stepHooks, hook)
	end

	local fakeOs = {
		clock = function()
			return clock.now
		end,
		time = function()
			return 1700000000 + math.floor(clock.now)
		end,
		date = os.date,
		difftime = os.difftime,
	}

	-- typeof : un faux Instance (marqué _isInstance) se comporte comme un Instance ; le reste suit le typeof de Luau.
	local luauTypeof = typeof
	local function typeofShim(value: any)
		if type(value) == "table" and rawget(value, "_isInstance") == true then
			return "Instance"
		end
		return luauTypeof(value)
	end

	-- Enum : toute valeur Enum.Type.Nom devient la chaîne "Enum.Type.Nom" (suffit pour des configs et des comparaisons).
	local Enum = setmetatable({}, {
		__index = function(_t, enumType)
			return setmetatable({}, {
				__index = function(_u, item)
					return "Enum." .. tostring(enumType) .. "." .. tostring(item)
				end,
			})
		end,
	})

	local workspaceNode = Instances.new("Workspace", nil, { newSignal = newSignal })
	rawset(workspaceNode, "GetServerTimeNow", function()
		return clock.now
	end)

	-- Services supplémentaires, simulés au minimum pour les services de jeu qui construisent des objets.
	services.Lighting = Instances.new("Lighting", nil, { newSignal = newSignal })
	-- Services client minimaux : suffisent aux écrans et contrôleurs pour se construire et réagir à des événements simulés.
	local function newUserInputService()
		local service = { Name = "UserInputService", TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false }
		for _, name in { "InputBegan", "InputEnded", "InputChanged", "LastInputTypeChanged", "TouchStarted", "TouchEnded" } do
			local signal, fire = newSignal()
			service[name] = signal
			service["_fire" .. name] = fire
		end
		local propertySignals = {}
		function service:GetPropertyChangedSignal(name)
			propertySignals[name] = propertySignals[name] or newSignal()
			return propertySignals[name]
		end
		-- Touches tenues et saisie de texte, pilotées par les tests : service.heldKeys[keyCode] = true / service.focusedTextBox.
		service.heldKeys = {}
		service.focusedTextBox = nil
		function service:IsKeyDown(keyCode)
			return self.heldKeys[keyCode] == true
		end
		function service:GetFocusedTextBox()
			return self.focusedTextBox
		end
		function service:GetMouseLocation()
			return roblox.Vector2.new(640, 360)
		end
		function service:GetLastInputType()
			return "Enum.UserInputType.Keyboard"
		end
		return service
	end
	services.UserInputService = newUserInputService()
	local function newTextChatService()
		local chat = Instances.new("TextChatService", nil, { newSignal = newSignal })
		for _, className in { "ChatWindowConfiguration", "ChatInputBarConfiguration", "BubbleChatConfiguration" } do
			Instances.new(className, chat, { newSignal = newSignal })
		end
		return chat
	end
	services.TextChatService = newTextChatService()
	services.TweenService = {
		Name = "TweenService",
		-- Un Tween simulé applique ses buts dès Play (assez pour vérifier l'état final d'une animation d'interface).
		Create = function(_self, instance, tweenInfo, goals)
			local tween = { PlaybackState = "Begin", instance = instance, goals = goals }
			local completed, fireCompleted = newSignal()
			tween.Completed = completed
			function tween:Play()
				for key, value in goals do
					instance[key] = value
				end
				self.PlaybackState = "Completed"
				fireCompleted("Completed")
			end
			function tween:Cancel()
				self.PlaybackState = "Cancelled"
			end
			function tween:Pause() end
			function tween:Destroy() end
			return tween
		end,
	}
	services.ContentProvider = {
		Name = "ContentProvider",
		PreloadAsync = function() end,
		GetAssetFetchStatus = function()
			return "Enum.AssetFetchStatus.Success"
		end,
	}
	local invitePrompts = 0
	world.invitePrompts = function()
		return invitePrompts
	end
	local function newSocialService()
		invitePrompts = 0
		return {
			Name = "SocialService",
			GameInvitePromptClosed = newSignal(),
			CanSendGameInviteAsync = function()
				return true
			end,
			PromptGameInvite = function()
				invitePrompts += 1
			end,
		}
	end
	services.SocialService = newSocialService()
	services.Debris = {
		Name = "Debris",
		AddItem = function(_self, item, seconds)
			taskLibrary.delay(seconds or 10, function()
				item:Destroy()
			end)
		end,
	}
	-- Personnage de remplacement créé « depuis une description » : Model + Humanoid + HumanoidRootPart.
	local function createHumanoidModel(_self, _description, _rigType)
		local model = Instances.new("Model", nil, { newSignal = newSignal })
		model.Name = "Model"
		Instances.new("Humanoid", model, { newSignal = newSignal })
		Instances.new("Part", model, { newSignal = newSignal }).Name = "HumanoidRootPart"
		return model
	end
	playersService.CreateHumanoidModelFromDescription = createHumanoidModel

	-- Joueur local (client) : Player simulé avec PlayerGui et PlayerScripts. Recréé à chaque world.reset().
	local function newLocalPlayer()
		local player = Instances.new("Player", nil, { newSignal = newSignal })
		player.Name = "LocalPlayer"
		player.DisplayName = "LocalPlayer"
		player.UserId = 1
		Instances.new("PlayerGui", player, { newSignal = newSignal })
		Instances.new("Folder", player, { newSignal = newSignal }).Name = "PlayerScripts"
		return player
	end
	playersService.LocalPlayer = newLocalPlayer()
	-- Caméra du Workspace.
	local function newCamera()
		local camera = Instances.new("Camera", nil, { newSignal = newSignal })
		workspaceNode.CurrentCamera = camera
		return camera
	end
	newCamera()

	local env = {
		Enum = Enum,
		game = gameNode,
		workspace = workspaceNode,
		Instance = { new = instanceNew },
		Random = Random,
		task = taskLibrary,
		os = fakeOs,
		typeof = typeofShim,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		Color3 = roblox.Color3,
		CFrame = roblox.CFrame,
		TweenInfo = { new = function(...) return { ... } end },
		-- Police simulée : Font.fromEnum / Font.new rendent une table décrivant la police demandée.
		Font = {
			fromEnum = function(item)
				return { Family = tostring(item), Weight = "Regular", Style = "Normal" }
			end,
			new = function(family, weight, style)
				return { Family = family, Weight = weight, Style = style }
			end,
		},
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Rect = roblox.Rect,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		BrickColor = roblox.BrickColor,
		Ray = roblox.Ray,
		-- print est capturé dans world.output (sinon la sortie des tests est noyée par les journaux des services).
		print = function(...)
			local parts = table.pack(...)
			for i = 1, parts.n do
				parts[i] = tostring(parts[i])
			end
			table.insert(world.output, table.concat(parts, " "))
		end,
		warn = function(...)
			-- Les avertissements des modules sont conservés pour que les tests les vérifient.
			local parts = table.pack(...)
			for i = 1, parts.n do
				parts[i] = tostring(parts[i])
			end
			table.insert(world.warnings, table.concat(parts, " "))
		end,
	}
	world.warnings = {}
	world.output = {}
	world.env = env

	local function makeRequire(): (any) -> any
		return function(target: any)
			local source = sources[target]
			if source == nil then
				error("require : module inconnu (" .. tostring(target) .. ")", 2)
			end
			if source.kind ~= "ModuleScript" then
				error(("require : '%s' est un %s, pas un ModuleScript"):format(target.Name, source.kind), 2)
			end
			if world.cache[target] ~= nil then
				return world.cache[target].value
			end
			if world.loading[target] then
				error("require : dépendance circulaire sur " .. target.Name, 2)
			end
			world.loading[target] = true

			-- Lune copie les paires de la table `environment` (les métatables sont ignorées) : on aplatit donc l'environnement.
			local moduleEnv = table.clone(env)
			moduleEnv.script = target
			moduleEnv.require = makeRequire()
			local chunk = luau.load(fs.readFile(source.path), { debugName = source.path, environment = moduleEnv })
			local value = chunk()
			world.loading[target] = nil
			world.cache[target] = { value = value }
			return value
		end
	end

	world.require = makeRequire()
	function world.moduleByPath(dotted: string)
		-- "ServerScriptService.Server.Services.GridService" -> nœud
		local node = gameNode
		for part in string.gmatch(dotted, "[^%.]+") do
			node = node:FindFirstChild(part)
			if node == nil then
				error("module introuvable : " .. dotted, 2)
			end
		end
		return node
	end
	function world.load(dotted: string)
		return world.require(world.moduleByPath(dotted))
	end

	-- Remet le monde à zéro : modules rechargés à la demande, joueurs et connexions oubliés, horloge à 1000, threads
	-- simulés supprimés. À appeler dans beforeEach pour les modules à état global (RoundService...) : les variables
	-- locales d'une suite qui contiennent d'anciens modules deviennent alors périmées (les recharger après reset).
	local attached: { { service: string, name: string } } = {}
	function world.reset()
		for _, entry in attached do
			rawget(gameNode:GetService(entry.service), "_children")[entry.name] = nil
		end
		table.clear(attached)
		playersService.CreateHumanoidModelFromDescription = createHumanoidModel -- un test a pu le remplacer
		playersService.LocalPlayer = newLocalPlayer()
		newCamera()
		services.UserInputService = newUserInputService()
		services.SocialService = newSocialService()
		services.TextChatService = newTextChatService()
		table.clear(world.cache)
		table.clear(world.loading)
		table.clear(players)
		playersService.PlayerAdded, firePlayerAdded = newSignal()
		playersService.PlayerRemoving, firePlayerRemoving = newSignal()
		table.clear(sleepers)
		table.clear(stepHooks)
		table.clear(mine)
		clock.now = 1000
		hookClock.last = 1000
		table.clear(world.warnings)
		table.clear(world.output)
		table.clear(stores)
		world.dataStoreFailure = nil
		workspaceNode:ClearAllChildren()
		for attribute in workspaceNode:GetAttributes() do
			workspaceNode:SetAttribute(attribute, nil)
		end
	end

	-- Ajoute une instance (ex. dossier d'assets) sous un service de l'arbre Rojo : world.attach("ReplicatedStorage", inst).
	function world.attach(serviceName: string, instance: any)
		rawget(gameNode:GetService(serviceName), "_children")[instance.Name] = instance
		table.insert(attached, { service = serviceName, name = instance.Name })
	end

	-- Remplace un module par un double de test AVANT qu'un autre module ne le charge (ex. services dépendant du moteur).
	function world.mock(name: string, replacement: any)
		for node, source in sources do
			if source.kind == "ModuleScript" and node.Name == name then
				world.cache[node] = { value = replacement }
				return replacement
			end
		end
		error("module introuvable : " .. name, 2)
	end

	-- Raccourci : world.module("GridService") retrouve le module par son nom (doit être unique dans l'arbre).
	function world.module(name: string)
		local found = nil
		for node, source in sources do
			if source.kind == "ModuleScript" and node.Name == name then
				if found then
					error("nom de module ambigu : " .. name, 2)
				end
				found = node
			end
		end
		if not found then
			error("module introuvable : " .. name, 2)
		end
		return world.require(found)
	end

	return world
end

Loader.newSignal = newSignal

return Loader
