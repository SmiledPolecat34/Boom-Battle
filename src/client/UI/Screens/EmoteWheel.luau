--!strict
-- Roue d'émotes Roblox + phrases rapides du chat. Le client n'envoie qu'un identifiant d'émote (le serveur valide) ;
-- les phrases passent par le vrai chat Roblox (filtré). Se ferme après un choix.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Parent.Components)
local EmoteConfig = require(ReplicatedStorage.Shared.EmoteConfig)
local Theme = require(script.Parent.Parent.Theme)

local EmoteWheel = {}

local WHEEL_SIZE = 380
local WHEEL_RADIUS = 134
local BUTTON_SIZE = Vector2.new(112, 62)

function EmoteWheel.new(parent: Instance, ctx: any)
	-- Fond transparent qui absorbe les clics : un clic en dehors de la roue la ferme.
	local frame = Components.screen(parent, "Emotes", true)
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.6
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = frame
	backdrop.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(WHEEL_SIZE + 40, 470))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.label(panel, "Title", "ÉMOTES", 32, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(0, 10)
	title.Size = UDim2.new(1, 0, 0, 42)

	-- Roue : les émotes en cercle autour d'un disque central.
	local wheel = Instance.new("Frame")
	wheel.Name = "Wheel"
	wheel.BackgroundTransparency = 1
	wheel.Position = UDim2.fromOffset(20, 64)
	wheel.Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE)
	wheel.Parent = panel
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(WHEEL_RADIUS * 2 - 20, WHEEL_RADIUS * 2 - 20)
	disc.BackgroundColor3 = Theme.navy
	disc.BackgroundTransparency = 0.3
	disc.Parent = wheel
	Components.corner(disc, WHEEL_RADIUS)
	local hint = Components.label(disc, "Hint", "Bouger\narrête l'émote", 18, Theme.muted, Theme.fontBold)
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.fromScale(0.5, 0.5)
	hint.Size = UDim2.new(1, -40, 0, 60)

	local count = #EmoteConfig.Emotes
	for index, emote in EmoteConfig.Emotes do
		local angle = math.rad(-90 + (index - 1) * (360 / count))
		local button = Components.button(wheel, "Emote_" .. emote.id, emote.name, Theme.violet, UDim2.fromOffset(BUTTON_SIZE.X, BUTTON_SIZE.Y))
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.new(0.5, math.cos(angle) * WHEEL_RADIUS, 0.5, math.sin(angle) * WHEEL_RADIUS)
		button.TextSize = 20
		button.Activated:Connect(function()
			ctx.playEmote(emote.id)
			ctx.closeOverlay()
		end)
	end

	local close = Components.button(panel, "CloseButton", "RETOUR", Theme.orange, UDim2.fromOffset(180, 50))
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -20, 1, -14)
	close.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	return { frame = frame, update = function(_s: any, _m: any) end, tick = function(_r: number?) end }
end

return EmoteWheel
