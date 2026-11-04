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
	local runService = {
		Name = "RunService",
		Heartbeat = heartbeat,
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
	local function instanceNew(className: string)
		if className == "BindableEvent" then
			local event, fire = newSignal()
			return { ClassName = className, Event = event, Fire = function(_self, ...) fire(...) end, Destroy = function() end }
		elseif className == "Folder" then
			return newNode("Folder", "Folder", nil)
		end
		error(("Instance.new('%s') non simulé : ce module relève des tests Studio"):format(className), 2)
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

	local taskLibrary = {
		spawn = function(fn, ...)
			local thread = coroutine.create(fn)
			coroutine.resume(thread, ...)
			return thread
		end,
		defer = function(fn, ...)
			local thread = coroutine.create(fn)
			coroutine.resume(thread, ...)
			return thread
		end,
		delay = function(_seconds, fn, ...)
			-- Pas d'horloge simulée : les délais ne s'exécutent pas (les modules testés ici n'en dépendent pas).
			return coroutine.create(fn)
		end,
		wait = function(seconds)
			return seconds or 0
		end,
		cancel = function() end,
	}

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

	local env = {
		Enum = Enum,
		game = gameNode,
		workspace = newNode("Workspace", "Workspace", nil),
		Instance = { new = instanceNew },
		Random = Random,
		task = taskLibrary,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		Color3 = roblox.Color3,
		CFrame = roblox.CFrame,
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
