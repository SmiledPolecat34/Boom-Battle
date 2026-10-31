--!strict
-- Menu principal : logo, avatar du joueur, PLAY, Aide, Réglages.
-- Boutique, inventaire, quêtes, événements et solde de pièces sont absents : ils n'existent pas encore (Phase 6).

local Players = game:GetService("Players")

local Components = require(script.Parent.Parent.Components)
local Theme = require(script.Parent.Parent.Theme)

local MainMenu = {}

function MainMenu.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "MainMenu", true)
	frame.BackgroundColor3 = Theme.navy
	frame.BackgroundTransparency = 0.3

	local logo = Components.label(frame, "Logo", "BOM BATTLE", 96, Theme.yellow, Theme.fontTitle)
	logo.AnchorPoint = Vector2.new(0.5, 0)
	logo.Position = UDim2.new(0.5, 0, 0.04, 0)
	logo.Size = UDim2.new(0.9, 0, 0, 110)
	logo.TextStrokeTransparency = 0
	logo.TextStrokeColor3 = Color3.fromRGB(140, 60, 20)

	local tagline = Components.label(frame, "Tagline", "Place ta bombe. Fuis l'explosion. Reste le dernier.", 22, Theme.white)
	tagline.AnchorPoint = Vector2.new(0.5, 0)
	tagline.Position = UDim2.new(0.5, 0, 0.04, 118)
	tagline.Size = UDim2.new(0.9, 0, 0, 30)

	-- Avatar du joueur local.
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.Position = UDim2.new(0.5, 0, 0.55, 0)
	avatar.Size = UDim2.fromOffset(240, 240)
	avatar.BackgroundColor3 = Theme.panel
	avatar.BackgroundTransparency = 0.2
	avatar.Parent = frame
	Components.corner(avatar, 120)
	Components.stroke(avatar, Theme.yellow, 3)

	local nameLabel = Components.label(frame, "PlayerName", Players.LocalPlayer.DisplayName, 28, Theme.white, Theme.fontBold)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.new(0.5, 0, 0.55, 132)
	nameLabel.Size = UDim2.fromOffset(360, 36)

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				Players.LocalPlayer.UserId,
				Enum.ThumbnailType.AvatarBust,
				Enum.ThumbnailSize.Size420x420
			)
		end)
		if ok and typeof(content) == "string" then
			avatar.Image = content
		end
	end)

	local play = Components.button(frame, "PlayButton", "PLAY", Theme.green, UDim2.fromOffset(260, 96))
	play.AnchorPoint = Vector2.new(1, 1)
	play.Position = UDim2.new(1, -40, 1, -40)
	play.TextSize = 48
	play.Activated:Connect(function()
		ctx.setQueued(true)
	end)

	local help = Components.button(frame, "HelpButton", "AIDE", Theme.violet, UDim2.fromOffset(130, 52))
	help.AnchorPoint = Vector2.new(1, 0)
	help.Position = UDim2.new(1, -24, 0, 24)
	help.Activated:Connect(function()
		ctx.openOverlay("Help")
	end)

	local settings = Components.button(frame, "SettingsButton", "RÉGLAGES", Theme.violet, UDim2.fromOffset(170, 52))
	settings.AnchorPoint = Vector2.new(1, 0)
	settings.Position = UDim2.new(1, -164, 0, 24)
	settings.Activated:Connect(function()
		ctx.openOverlay("Settings")
	end)

	return {
		frame = frame,
		update = function(_snapshot: any, _me: any) end,
		tick = function(_remaining: number?) end,
	}
end

return MainMenu
