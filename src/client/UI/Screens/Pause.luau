--!strict
-- Menu de pause en jeu : reprendre, aide, réglages, quitter la partie (retour au menu principal).
-- Le jeu continue en arrière-plan (jeu en ligne) : ce menu ne met rien en pause côté serveur.
-- Quitter en cours de manche = abandon : le serveur élimine le joueur (le client ne décide de rien).

local Components = require(script.Parent.Parent.Components)
local Theme = require(script.Parent.Parent.Theme)

local Pause = {}

function Pause.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "Pause", true)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.45

	-- Clic en dehors du panneau : referme le menu et reprend la partie normalement.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.ZIndex = 1
	backdrop.Parent = frame
	backdrop.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(440, 460))
	panel.ZIndex = 2 -- au-dessus du fond cliquable ; le panneau absorbe ses propres clics
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.label(panel, "Title", "MENU", 36, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 48)

	local note = Components.label(panel, "Note", "La manche continue pendant que ce menu est ouvert.", 16, Theme.muted, Theme.fontBody)
	note.Position = UDim2.fromOffset(20, 62)
	note.Size = UDim2.new(1, -40, 0, 22)

	local function addButton(index: number, name: string, text: string, color: Color3): TextButton
		local button = Components.button(panel, name, text, color, UDim2.fromOffset(320, 60))
		button.AnchorPoint = Vector2.new(0.5, 0)
		button.Position = UDim2.new(0.5, 0, 0, 96 + (index - 1) * 74)
		button.TextSize = 24
		return button
	end

	local resume = addButton(1, "ResumeButton", "REPRENDRE", Theme.green)
	resume.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	local help = addButton(2, "HelpButton", "AIDE", Theme.violet)
	help.Activated:Connect(function()
		ctx.openOverlayFromPause("Help")
	end)

	local settings = addButton(3, "SettingsButton", "RÉGLAGES", Theme.violet)
	settings.Activated:Connect(function()
		ctx.openOverlayFromPause("Settings")
	end)

	-- Quitter : deux clics (le second confirme), pour éviter d'abandonner une manche par erreur.
	local leave = addButton(4, "LeaveButton", "QUITTER LA PARTIE", Theme.red)
	local armedToken = 0
	local function disarm()
		armedToken += 1
		leave.Text = "QUITTER LA PARTIE"
	end
	leave.Activated:Connect(function()
		if leave.Text == "QUITTER LA PARTIE" then
			armedToken += 1
			local token = armedToken
			leave.Text = "CONFIRMER ?"
			task.delay(3, function()
				if armedToken == token then
					disarm()
				end
			end)
			return
		end
		disarm()
		ctx.leaveMatch()
	end)

	frame:GetPropertyChangedSignal("Visible"):Connect(disarm)

	return { frame = frame, update = function(_s: any, _m: any) end, tick = function(_r: number?) end }
end

return Pause
