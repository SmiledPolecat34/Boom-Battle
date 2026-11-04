--!strict
-- Lobby : liste des joueurs en file avec leur statut, bouton PRÊT, retour au menu.
-- L'arène du lobby reste visible et jouable (déplacement libre) derrière ce panneau latéral.

local Components = require(script.Parent.Parent.Components)
local Theme = require(script.Parent.Parent.Theme)

local Lobby = {}

function Lobby.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "Lobby", false)

	local back = Components.button(frame, "BackButton", "← MENU", Theme.violet, UDim2.fromOffset(150, 52))
	back.Position = UDim2.fromOffset(24, 84)
	back.Activated:Connect(function()
		ctx.setQueued(false)
	end)
	local help = Components.button(frame, "HelpButton", "AIDE", Theme.violet, UDim2.fromOffset(150, 52))
	help.Position = UDim2.fromOffset(24, 148)
	help.Activated:Connect(function()
		ctx.openOverlay("Help")
	end)
	local settings = Components.button(frame, "SettingsButton", "RÉGLAGES", Theme.violet, UDim2.fromOffset(150, 52))
	settings.Position = UDim2.fromOffset(24, 212)
	settings.Activated:Connect(function()
		ctx.openOverlay("Settings")
	end)

	local emotes = Components.button(frame, "EmotesButton", "ÉMOTES", Theme.violet, UDim2.fromOffset(150, 52))
	emotes.Position = UDim2.fromOffset(24, 276)
	emotes.Activated:Connect(function()
		ctx.openOverlay("Emotes")
	end)
	local chat = Components.bubbleButton(frame, "ChatButton", "CHAT", UDim2.fromOffset(150, 52))
	chat.Position = UDim2.fromOffset(24, 340)
	chat.Activated:Connect(function()
		ctx.openOverlay("QuickChat")
	end)

	local panel = Components.panel(frame, "PlayerPanel", UDim2.fromOffset(320, 400))
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -24, 0.5, 0)

	local title = Components.label(panel, "Title", "LOBBY", 30, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(0, 12)
	local status = Components.label(panel, "Status", "", 18, Theme.white, Theme.fontBold)
	status.Position = UDim2.fromOffset(0, 56)
	status.Size = UDim2.new(1, 0, 0, 50)

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(12, 112)
	list.Size = UDim2.new(1, -24, 1, -124)
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local ready = Components.button(frame, "ReadyButton", "PRÊT", Theme.green, UDim2.fromOffset(280, 84))
	ready.AnchorPoint = Vector2.new(0.5, 1)
	ready.Position = UDim2.new(0.5, 0, 1, -32)
	ready.TextSize = 40
	local iAmReady = false
	ready.Activated:Connect(function()
		ctx.setReady(not iAmReady)
	end)

	return {
		frame = frame,
		update = function(snapshot: any, me: any)
			iAmReady = me ~= nil and me.ready == true
			local state: string = snapshot.state

			local queuedCount, readyCount = 0, 0
			for _, entry in snapshot.players do
				if entry.queued then
					queuedCount += 1
					if entry.ready then
						readyCount += 1
					end
				end
			end

			if state == "WAITING" then
				status.Text = ("Recherche de joueurs (%d/%d)"):format(queuedCount, snapshot.minPlayers)
			elseif state == "READY" then
				status.Text = ("Prêts : %d/%d\nAppuie sur PRÊT quand tu es prêt"):format(readyCount, queuedCount)
			else
				status.Text = "Nouvelle arène en préparation..."
			end

			-- Partie rapide : plus de bouton PRÊT (le serveur lance la manche dès qu'il y a assez de joueurs).
			-- Le bouton reste construit pour les futurs serveurs privés.
			local canReady = false
			ready.Visible = canReady
			ready.Text = if iAmReady then "ANNULER" else "PRÊT"
			ready.BackgroundColor3 = if iAmReady then Theme.red else Theme.green

			for _, child in list:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			local order = 0
			for _, entry in snapshot.players do
				if entry.queued then
					order += 1
					local row = Instance.new("Frame")
					row.Name = "Row"
					row.LayoutOrder = order
					row.Size = UDim2.new(1, 0, 0, 36)
					row.BackgroundColor3 = if entry.userId == (me and me.userId) then Theme.violet else Theme.navy
					row.BackgroundTransparency = 0.3
					row.Parent = list
					Components.corner(row, 8)
					local name = Components.label(row, "Name", entry.name, 18, Theme.white, Theme.fontBold)
					name.Size = UDim2.new(0.6, 0, 1, 0)
					name.Position = UDim2.fromOffset(10, 0)
					name.TextXAlignment = Enum.TextXAlignment.Left
					local tag = Components.label(
						row,
						"Tag",
						if entry.ready then "PRÊT" else "En attente",
						16,
						if entry.ready then Theme.green else Theme.muted,
						Theme.fontBold
					)
					tag.Size = UDim2.new(0.4, -10, 1, 0)
					tag.Position = UDim2.new(0.6, 0, 0, 0)
					tag.TextXAlignment = Enum.TextXAlignment.Right
				end
			end
		end,
		tick = function(_remaining: number?) end,
	}
end

return Lobby
