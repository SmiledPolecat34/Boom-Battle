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

	-- Joueur factice (n'importe quelle table sert de clé côté services).
	function Fixtures.fakePlayer(userId: number, name: string?)
		-- Parent = service Players : PlayerDataService.load vérifie que le joueur est toujours présent.
		return {
			UserId = userId,
			Name = name or ("Joueur" .. userId),
			Parent = world.game:GetService("Players"),
			_attributes = {},
			GetAttribute = function(self, k)
				return self._attributes[k]
			end,
			SetAttribute = function(self, k, v)
				self._attributes[k] = v
			end,
		}
	end

	-- Dossier de remotes factice : remotes.<Nom> est un RemoteEvent simulé.
	--   remote.OnServerEvent:Connect(function(player, ...) end)   (réception serveur)
	--   remote:fireServer(player, ...)                            (simule un envoi client)
	--   remote.sent                                               (liste des FireClient/FireAllClients : { player, args })
	function Fixtures.fakeRemotes(names: { string })
		local folder = { _remotes = {} }
		for _, name in names do
			local signal, fire = Loader.newSignal()
			local remote = { Name = name, OnServerEvent = signal, sent = {} }
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

	return Fixtures
end
