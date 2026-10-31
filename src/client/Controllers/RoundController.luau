--!strict
-- Relais réseau de la manche : reçoit les messages du serveur et les transmet à UIController.
-- Ne contient aucune interface et ne décide de rien.

local RoundController = {}

local connections: { RBXScriptConnection } = {}

local UIController = require(script.Parent.UIController)

function RoundController.start(remotes: Folder)
	RoundController.stop()

	local roundState = remotes:WaitForChild("RoundState") :: RemoteEvent
	local roundEnded = remotes:WaitForChild("RoundEnded") :: RemoteEvent
	local statsChanged = remotes:WaitForChild("StatsChanged") :: RemoteEvent
	local profileUpdated = remotes:WaitForChild("ProfileUpdated") :: RemoteEvent
	local shopResult = remotes:WaitForChild("ShopResult") :: RemoteEvent
	local notice = remotes:WaitForChild("Notice") :: RemoteEvent

	-- Messages courts du serveur (ex. refus du mode solo) : affichés en bandeau.
	table.insert(
		connections,
		notice.OnClientEvent:Connect(function(text: any)
			if typeof(text) == "string" and #text > 0 and #text <= 120 then
				UIController.showToast(text)
			end
		end)
	)

	table.insert(
		connections,
		profileUpdated.OnClientEvent:Connect(function(profile: any)
			if typeof(profile) == "table" and typeof(profile.coins) == "number" and typeof(profile.owned) == "table" then
				UIController.onProfile(profile)
			end
		end)
	)
	table.insert(
		connections,
		shopResult.OnClientEvent:Connect(function(result: any)
			UIController.onShopResult(result)
		end)
	)

	table.insert(
		connections,
		roundState.OnClientEvent:Connect(function(snapshot: any)
			if typeof(snapshot) == "table" and typeof(snapshot.state) == "string" and typeof(snapshot.players) == "table" then
				UIController.onSnapshot(snapshot)
			end
		end)
	)
	table.insert(
		connections,
		roundEnded.OnClientEvent:Connect(function(payload: any)
			if typeof(payload) == "table" and typeof(payload.result) == "table" and typeof(payload.names) == "table" then
				UIController.onRoundEnded(payload)
			end
		end)
	)
	table.insert(
		connections,
		statsChanged.OnClientEvent:Connect(function(stats: any)
			if typeof(stats) == "table" then
				UIController.onStats(stats)
			end
		end)
	)
end

function RoundController.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return RoundController
