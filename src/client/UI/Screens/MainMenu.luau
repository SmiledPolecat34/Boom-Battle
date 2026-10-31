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

	-- Boutique et inventaire à gauche, quêtes et événements à droite (disposition de la maquette).
	local function sideButton(name: string, text: string, color: Color3, overlay: string, position: UDim2, anchor: Vector2)
		local button = Components.button(frame, name, text, color, UDim2.fromOffset(210, 60))
		button.AnchorPoint = anchor
		button.Position = position
		button.TextSize = 22
		button.Activated:Connect(function()
			ctx.openOverlay(overlay)
		end)
	end
	sideButton("ShopButton", "BOUTIQUE", Theme.orange, "Shop", UDim2.new(0, 28, 0.42, 0), Vector2.new(0, 0.5))
	sideButton("InventoryButton", "INVENTAIRE", Color3.fromRGB(150, 100, 60), "Inventory", UDim2.new(0, 28, 0.42, 76), Vector2.new(0, 0.5))
	sideButton("QuestsButton", "QUÊTES", Theme.violet, "Quests", UDim2.new(1, -28, 0.42, 0), Vector2.new(1, 0.5))
	sideButton("EventsButton", "ÉVÉNEMENTS", Theme.turquoise, "Events", UDim2.new(1, -28, 0.42, 76), Vector2.new(1, 0.5))

	-- Solde de Bomb Coins (valeur du serveur) et avertissement si la progression n'est pas enregistrée.
	local coins = Components.label(frame, "Coins", "Pièces : ...", 26, Theme.yellow, Theme.fontBold)
	coins.AnchorPoint = Vector2.new(0, 0)
	coins.Position = UDim2.fromOffset(24, 24)
	coins.Size = UDim2.fromOffset(260, 36)
	coins.TextXAlignment = Enum.TextXAlignment.Left
	local saveNotice = Components.label(frame, "SaveNotice", "", 16, Theme.red, Theme.fontBold)
	saveNotice.Position = UDim2.fromOffset(24, 62)
	saveNotice.Size = UDim2.fromOffset(420, 24)
	saveNotice.TextXAlignment = Enum.TextXAlignment.Left

	return {
		frame = frame,
		setProfile = function(profile: any)
			local text = tostring(math.floor(profile.coins)):reverse():gsub("(%d%d%d)", "%1 "):reverse()
			coins.Text = ("Pièces : %s"):format((text:gsub("^ ", "")))
			saveNotice.Text = if profile.persisted then "" else "Sauvegarde indisponible : progression non enregistrée"
		end,
		update = function(_snapshot: any, _me: any) end,
		tick = function(_remaining: number?) end,
	}
end

return MainMenu
