--!strict
-- Interface PROVISOIRE de manche (Phase 3) : statut, minuteur, bouton PRÊT, bandeau spectateur, résultats.
-- Les vrais écrans (MainMenu, Lobby, GameHUD, Results) seront construits en Phase 4.
-- Ce contrôleur n'affiche que ce que le serveur annonce ; il ne décide de rien.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SpectatorController = require(script.Parent.SpectatorController)
local UIController = require(script.Parent.UIController)

local RoundController = {}

local localPlayer = Players.LocalPlayer
local connections: { RBXScriptConnection } = {}
local gui: ScreenGui? = nil
local statusLabel: TextLabel
local timerLabel: TextLabel
local readyButton: TextButton
local resultFrame: Frame
local resultTitle: TextLabel
local resultBody: TextLabel

local currentSnapshot: any = nil
local iAmReady = false

local function makeLabel(name: string, parent: Instance, position: UDim2, size: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = position
	label.Size = size
	label.BackgroundColor3 = Color3.fromRGB(21, 27, 49)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextWrapped = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	label.Parent = parent
	return label
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function findMe(snapshot: any): any
	for _, entry in snapshot.players do
		if entry.userId == localPlayer.UserId then
			return entry
		end
	end
	return nil
end

local function render()
	local snapshot = currentSnapshot
	if not snapshot then
		return
	end
	local me = findMe(snapshot)
	local state: string = snapshot.state
	local total = #snapshot.players
	local readyCount = 0
	for _, entry in snapshot.players do
		if entry.ready then
			readyCount += 1
		end
	end
	iAmReady = me ~= nil and me.ready

	if state == "WAITING" then
		statusLabel.Text = ("En attente de joueurs (%d/%d)"):format(total, snapshot.minPlayers)
	elseif state == "READY" then
		statusLabel.Text = ("Prêts : %d/%d — appuie sur PRÊT"):format(readyCount, total)
	elseif state == "COUNTDOWN" then
		statusLabel.Text = "La manche commence !"
	elseif state == "PLAYING" then
		statusLabel.Text = ("Survivants : %d"):format(snapshot.survivors)
	elseif state == "FINISHED" then
		statusLabel.Text = "Manche terminée"
	else
		statusLabel.Text = "Nouvelle arène..."
	end

	-- Bouton PRÊT : lobby, ou annulation pendant le compte à rebours si on participe.
	local canToggleReady = state == "WAITING" or state == "READY" or (state == "COUNTDOWN" and me ~= nil and me.participant)
	readyButton.Visible = canToggleReady
	readyButton.Text = if iAmReady then "ANNULER" else "PRÊT"
	readyButton.BackgroundColor3 = if iAmReady then Color3.fromRGB(200, 70, 60) else Color3.fromRGB(60, 190, 80)

	resultFrame.Visible = state == "FINISHED"

	local inPlay = state == "PLAYING" and me ~= nil and me.participant and me.alive
	UIController.setBombVisible(inPlay)

	if state == "PLAYING" and not inPlay then
		SpectatorController.setText(("SPECTATEUR — %d survivant(s)"):format(snapshot.survivors))
	elseif state == "COUNTDOWN" and not (me ~= nil and me.participant) then
		SpectatorController.setText("Manche en préparation — tu rejoindras la suivante")
	else
		SpectatorController.setText(nil)
	end
end

local function showResult(payload: any)
	local result = payload.result
	local names: { [string]: string } = payload.names
	local function nameOf(userId: number): string
		return names[tostring(userId)] or ("Joueur " .. userId)
	end

	if result.outcome == "WIN" then
		local mine = result.winnerUserId == localPlayer.UserId
		resultTitle.Text = if mine then "VICTOIRE !" else ("Victoire de %s"):format(nameOf(result.winnerUserId))
	else
		local list = {}
		for _, userId in result.tiedUserIds do
			table.insert(list, nameOf(userId))
		end
		resultTitle.Text = if #list > 0 then ("ÉGALITÉ : %s"):format(table.concat(list, ", ")) else "ÉGALITÉ"
	end

	local lines = { ("Durée : %s"):format(formatTime(result.durationSeconds)), "Classement :" }
	for rank, userId in result.ranking do
		table.insert(lines, ("%d. %s"):format(rank, nameOf(userId)))
	end
	resultBody.Text = table.concat(lines, "\n")
end

function RoundController.start(remotes: Folder)
	RoundController.stop()

	local roundState = remotes:WaitForChild("RoundState") :: RemoteEvent
	local roundEnded = remotes:WaitForChild("RoundEnded") :: RemoteEvent
	local setReady = remotes:WaitForChild("SetReady") :: RemoteEvent

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RoundUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	statusLabel = makeLabel("Status", screenGui, UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(420, 38), 20)
	timerLabel = makeLabel("Timer", screenGui, UDim2.new(0.5, 0, 0, 54), UDim2.fromOffset(140, 34), 22)
	timerLabel.Text = ""

	readyButton = Instance.new("TextButton")
	readyButton.Name = "ReadyButton"
	readyButton.AnchorPoint = Vector2.new(0.5, 1)
	readyButton.Position = UDim2.new(0.5, 0, 1, -28)
	readyButton.Size = UDim2.fromOffset(240, 72)
	readyButton.Font = Enum.Font.GothamBlack
	readyButton.TextScaled = true
	readyButton.TextColor3 = Color3.new(1, 1, 1)
	readyButton.Text = "PRÊT"
	readyButton.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = readyButton
	readyButton.Parent = screenGui

	resultFrame = Instance.new("Frame")
	resultFrame.Name = "Results"
	resultFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	resultFrame.Position = UDim2.fromScale(0.5, 0.5)
	resultFrame.Size = UDim2.fromOffset(380, 300)
	resultFrame.BackgroundColor3 = Color3.fromRGB(21, 27, 49)
	resultFrame.BackgroundTransparency = 0.1
	resultFrame.Visible = false
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 14)
	frameCorner.Parent = resultFrame
	resultTitle = Instance.new("TextLabel")
	resultTitle.BackgroundTransparency = 1
	resultTitle.Size = UDim2.new(1, -20, 0, 60)
	resultTitle.Position = UDim2.fromOffset(10, 10)
	resultTitle.Font = Enum.Font.GothamBlack
	resultTitle.TextScaled = true
	resultTitle.TextColor3 = Color3.fromRGB(255, 201, 75)
	resultTitle.Parent = resultFrame
	resultBody = Instance.new("TextLabel")
	resultBody.BackgroundTransparency = 1
	resultBody.Size = UDim2.new(1, -20, 1, -90)
	resultBody.Position = UDim2.fromOffset(10, 80)
	resultBody.Font = Enum.Font.GothamMedium
	resultBody.TextSize = 20
	resultBody.TextColor3 = Color3.new(1, 1, 1)
	resultBody.TextXAlignment = Enum.TextXAlignment.Left
	resultBody.TextYAlignment = Enum.TextYAlignment.Top
	resultBody.Parent = resultFrame
	resultFrame.Parent = screenGui

	SpectatorController.attach(screenGui)
	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	table.insert(
		connections,
		readyButton.Activated:Connect(function()
			setReady:FireServer(not iAmReady)
		end)
	)
	table.insert(
		connections,
		roundState.OnClientEvent:Connect(function(snapshot: any)
			if typeof(snapshot) == "table" and typeof(snapshot.state) == "string" and typeof(snapshot.players) == "table" then
				currentSnapshot = snapshot
				render()
			end
		end)
	)
	table.insert(
		connections,
		roundEnded.OnClientEvent:Connect(function(payload: any)
			if typeof(payload) == "table" and typeof(payload.result) == "table" and typeof(payload.names) == "table" then
				showResult(payload)
			end
		end)
	)
	-- Minuteur : calculé localement à partir de l'heure serveur annoncée (aucun trafic réseau par seconde).
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			local snapshot = currentSnapshot
			if snapshot and typeof(snapshot.endsAt) == "number" then
				timerLabel.Text = formatTime(snapshot.endsAt - workspace:GetServerTimeNow())
			else
				timerLabel.Text = ""
			end
		end)
	)
end

function RoundController.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
		gui = nil
	end
	currentSnapshot = nil
end

return RoundController
