--!strict
-- HUD PROVISOIRE de la Phase 2 : bouton de pose de bombe et affichage des statistiques.
-- Le vrai HUD (chronomètre, survivants, bonus actifs, états) arrive en Phase 4.

local Players = game:GetService("Players")

local InputController = require(script.Parent.InputController)

local UIController = {}

local gui: ScreenGui? = nil
local connections: { RBXScriptConnection } = {}

local function describe(stats: any): string
	return ("Bombes : %d   Portée : %d   Vitesse : +%d   Bouclier : %s"):format(
		stats.bombCapacity,
		stats.blastRange,
		stats.speedPickups,
		if stats.hasShield then "oui" else "non"
	)
end

function UIController.start(remotes: Folder)
	UIController.stop()

	local requestPlaceBomb = remotes:WaitForChild("RequestPlaceBomb") :: RemoteEvent
	local statsChanged = remotes:WaitForChild("StatsChanged") :: RemoteEvent

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local button = Instance.new("TextButton")
	button.Name = "BombButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -24, 1, -24)
	button.Size = UDim2.fromOffset(120, 120) -- grande zone tactile
	button.BackgroundColor3 = Color3.fromRGB(255, 160, 40)
	button.Text = "BOMBE"
	button.TextScaled = true
	button.Font = Enum.Font.GothamBlack
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0.3
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	button.Parent = screenGui

	local label = Instance.new("TextLabel")
	label.Name = "Stats"
	label.Position = UDim2.fromOffset(16, 12)
	label.Size = UDim2.fromOffset(460, 28)
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.fromRGB(21, 27, 49)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Text = "En attente des statistiques..."
	label.Parent = screenGui

	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	local function placeBomb()
		requestPlaceBomb:FireServer()
	end
	table.insert(connections, button.Activated:Connect(placeBomb))
	InputController.onBombKey(placeBomb)

	table.insert(
		connections,
		statsChanged.OnClientEvent:Connect(function(stats: any)
			if typeof(stats) == "table" then
				label.Text = describe(stats)
			end
		end)
	)
end

function UIController.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
		gui = nil
	end
end

return UIController
