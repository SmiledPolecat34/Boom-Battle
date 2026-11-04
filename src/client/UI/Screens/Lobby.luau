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
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Partie privée : inviter des amis (fenêtre d'invitation Roblox) et lancer la manche (hôte, dès 2 joueurs).
	local invite = Components.button(frame, "InviteButton", "INVITER", Theme.green, UDim2.fromOffset(150, 52))
	invite.Position = UDim2.fromOffset(24, 404)
	invite.Visible = false
	invite.Activated:Connect(function()
		ctx.requestInvite()
	end)
	local addBot = Components.button(frame, "AddBotButton", "+ BOT", Theme.orange, UDim2.fromOffset(150, 52))
	addBot.Position = UDim2.fromOffset(24, 468)
	addBot.Visible = false
	addBot.Activated:Connect(function()
		ctx.partyAction("addBot")
	end)
	local start = Components.button(frame, "StartButton", "LANCER LA PARTIE", Theme.green, UDim2.fromOffset(420, 84))
	start.AnchorPoint = Vector2.new(0.5, 1)
	start.Position = UDim2.new(0.5, 0, 1, -32)
	start.TextSize = 34
	start.Visible = false
	local canStart = false
	start.Activated:Connect(function()
		if canStart then
			ctx.partyAction("start")
		end
	end)

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

			-- Dans une partie privée, la liste ne montre que le groupe ; sinon seulement la file de la partie rapide.
			local inParty = me ~= nil and me.inParty == true and snapshot.party ~= nil
			local function shown(entry: any): boolean
				return entry.queued and (entry.inParty == true) == inParty
			end

			local queuedCount, readyCount = 0, 0
			for _, entry in snapshot.players do
				if shown(entry) then
					queuedCount += 1
					if entry.ready then
						readyCount += 1
					end
				end
			end

			local isHost = inParty and snapshot.party.hostUserId == (me and me.userId)
			local minToStart = if inParty then snapshot.party.minToStart else 0
			title.Text = if inParty then "PARTIE PRIVÉE" else "LOBBY"
			invite.Visible = inParty
			local bots: { number } = if inParty then snapshot.party.bots or {} else {}
			local total = queuedCount + #bots -- joueurs + bots du groupe
			local open = state == "WAITING" or state == "READY"
			addBot.Visible = isHost and open and total < snapshot.party.max
			canStart = isHost and open and total >= minToStart
			start.Visible = isHost and open
			start.BackgroundColor3 = if canStart then Theme.green else Theme.muted
			start.Text = if canStart then "LANCER LA PARTIE" else ("%d JOUEUR(S) MINIMUM"):format(minToStart)

			if inParty then
				if not open then
					status.Text = "Nouvelle arène en préparation..."
				elseif isHost then
					status.Text = if canStart
						then ("%d joueurs dans le groupe\nLance quand tout le monde est là"):format(total)
						else ("Invite des amis ou ajoute un bot (%d/%d)\nIl faut au moins %d joueurs"):format(total, snapshot.party.max, minToStart)
				else
					status.Text = ("%d joueurs dans le groupe\nEn attente de l'hôte..."):format(total)
				end
			elseif state == "WAITING" then
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
				if shown(entry) then
					order += 1
					local row = Instance.new("Frame")
					row.Name = "Row"
					row.LayoutOrder = order
					row.Size = UDim2.new(1, 0, 0, 30)
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
						if inParty and snapshot.party.hostUserId == entry.userId
							then "HÔTE"
							elseif entry.ready then "PRÊT"
							else "En attente",
						16,
						if inParty and snapshot.party.hostUserId == entry.userId
							then Theme.yellow
							elseif entry.ready then Theme.green
							else Theme.muted,
						Theme.fontBold
					)
					tag.Size = UDim2.new(0.4, -10, 1, 0)
					tag.Position = UDim2.new(0.6, 0, 0, 0)
					tag.TextXAlignment = Enum.TextXAlignment.Right
				end
			end

			-- Bots du groupe : l'hôte règle le niveau (1 à 10) de chacun et peut le retirer ; les autres le voient seulement.
			for index, level in bots do
				local row = Instance.new("Frame")
				row.Name = "BotRow"
				row.LayoutOrder = 100 + index
				row.Size = UDim2.new(1, 0, 0, 30)
				row.BackgroundColor3 = Theme.navy
				row.BackgroundTransparency = 0.3
				row.Parent = list
				Components.corner(row, 8)
				local name = Components.label(row, "Name", "Bot " .. index, 16, Theme.white, Theme.fontBold)
				name.Size = UDim2.fromOffset(70, 30)
				name.Position = UDim2.fromOffset(8, 0)
				name.TextXAlignment = Enum.TextXAlignment.Left
				local value = Components.label(row, "Level", "Niv. " .. level, 16, Theme.yellow, Theme.fontBold)
				value.Size = UDim2.fromOffset(62, 30)
				value.Position = UDim2.fromOffset(if isHost then 108 else 80, 0)
				if isHost then
					local minus = Components.button(row, "Minus", "-", Theme.violet, UDim2.fromOffset(26, 24))
					minus.Position = UDim2.fromOffset(78, 3)
					minus.TextSize = 18
					minus.Activated:Connect(function()
						if level > 1 then
							ctx.partyAction("botLevel", { index = index, level = level - 1 })
						end
					end)
					local plus = Components.button(row, "Plus", "+", Theme.violet, UDim2.fromOffset(26, 24))
					plus.Position = UDim2.fromOffset(172, 3)
					plus.TextSize = 18
					plus.Activated:Connect(function()
						if level < 10 then
							ctx.partyAction("botLevel", { index = index, level = level + 1 })
						end
					end)
					local remove = Components.button(row, "Remove", "X", Theme.red, UDim2.fromOffset(26, 24))
					remove.AnchorPoint = Vector2.new(1, 0)
					remove.Position = UDim2.new(1, -6, 0, 3)
					remove.TextSize = 16
					remove.Activated:Connect(function()
						ctx.partyAction("removeBot", index)
					end)
				end
			end
		end,
		tick = function(_remaining: number?) end,
	}
end

return Lobby
