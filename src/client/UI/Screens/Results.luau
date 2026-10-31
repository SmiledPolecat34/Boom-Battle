--!strict
-- Résultats de manche : victoire / égalité, classement, REJOUER, MENU. Retour automatique au lobby.

local Components = require(script.Parent.Parent.Components)
local Theme = require(script.Parent.Parent.Theme)

local Results = {}

function Results.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "Results", true)
	frame.BackgroundColor3 = Theme.navy
	frame.BackgroundTransparency = 0.45

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(460, 440))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.label(panel, "Title", "", 40, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 56)
	local details = Components.label(panel, "Details", "", 20, Theme.white, Theme.fontBody)
	details.Position = UDim2.fromOffset(16, 82)
	details.Size = UDim2.new(1, -32, 0, 200)
	details.TextXAlignment = Enum.TextXAlignment.Left
	details.TextYAlignment = Enum.TextYAlignment.Top

	local footer = Components.label(panel, "Footer", "", 16, Theme.muted, Theme.fontBody)
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -84)
	footer.Size = UDim2.new(1, -32, 0, 24)

	local replay = Components.button(panel, "ReplayButton", "REJOUER", Theme.green, UDim2.fromOffset(190, 60))
	replay.AnchorPoint = Vector2.new(0, 1)
	replay.Position = UDim2.new(0, 24, 1, -16)
	local menu = Components.button(panel, "MenuButton", "MENU", Theme.violet, UDim2.fromOffset(190, 60))
	menu.AnchorPoint = Vector2.new(1, 1)
	menu.Position = UDim2.new(1, -24, 1, -16)

	local iAmReady = false
	replay.Activated:Connect(function()
		ctx.setReady(not iAmReady)
	end)
	menu.Activated:Connect(function()
		ctx.setQueued(false)
	end)

	local function formatDuration(seconds: number): string
		seconds = math.floor(seconds)
		return ("%d:%02d"):format(seconds // 60, seconds % 60)
	end

	return {
		frame = frame,
		-- payload : { result = RoundResult, names = { [userId] = nom } } annoncé par le serveur.
		setResult = function(payload: any)
			local result = payload.result
			local names: { [string]: string } = payload.names
			local function nameOf(userId: number): string
				return names[tostring(userId)] or ("Joueur " .. userId)
			end
			if result.outcome == "WIN" then
				local mine = result.winnerUserId == ctx.localUserId
				title.Text = if mine then "VICTOIRE !" else "DÉFAITE"
				details.Text = ("Vainqueur : %s\n"):format(nameOf(result.winnerUserId))
			else
				local list = {}
				for _, userId in result.tiedUserIds do
					table.insert(list, nameOf(userId))
				end
				title.Text = "ÉGALITÉ"
				details.Text = if #list > 0 then ("À égalité : %s\n"):format(table.concat(list, ", ")) else "Aucun vainqueur\n"
			end
			local earned = if typeof(payload.rewards) == "table" then payload.rewards[tostring(ctx.localUserId)] else nil
			local lines = { details.Text, ("Durée : %s"):format(formatDuration(result.durationSeconds)) }
			if typeof(earned) == "number" then
				table.insert(lines, ("Récompense : +%d pièces"):format(earned))
			end
			table.insert(lines, "")
			table.insert(lines, "Classement :")
			for rank, userId in result.ranking do
				table.insert(lines, ("%d. %s"):format(rank, nameOf(userId)))
			end
			details.Text = table.concat(lines, "\n")
		end,
		update = function(_snapshot: any, me: any)
			iAmReady = me ~= nil and me.ready == true
			replay.Text = if iAmReady then "ANNULER" else "REJOUER"
			replay.BackgroundColor3 = if iAmReady then Theme.red else Theme.green
			-- Un joueur non inscrit dans la file (spectateur) n'a pas de revanche.
			replay.Visible = me ~= nil and me.queued == true
		end,
		tick = function(remaining: number?)
			footer.Text = if remaining then ("Retour au lobby dans %d s"):format(math.max(0, math.ceil(remaining))) else ""
		end,
	}
end

return Results
