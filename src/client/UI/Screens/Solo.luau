--!strict
-- Mode solo : choix du nombre de bots (1 à 3). Manche d'entraînement : aucune pièce ni statistique n'est gagnée.
-- Le client n'envoie que le nombre ; le serveur valide (bornes, état de la partie, joueurs en attente).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Parent.Components)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Theme = require(script.Parent.Parent.Theme)

local Solo = {}

function Solo.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "Solo", true)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.45

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(560, 400))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.label(panel, "Title", "MODE SOLO", 38, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 50)

	local body = Components.label(panel, "Body", "Entraîne-toi contre des bots.\nChoisis combien d'adversaires :", 20, Theme.white, Theme.fontBold)
	body.Position = UDim2.fromOffset(24, 76)
	body.Size = UDim2.new(1, -48, 0, 60)

	local maxBots = GameConfig.Round.MaxSoloBots
	local width = 150
	local gap = 20
	local totalWidth = maxBots * width + (maxBots - 1) * gap
	for count = 1, maxBots do
		local label = if count == 1 then "1 BOT" else ("%d BOTS"):format(count)
		local button = Components.button(panel, "Bots" .. count, label, if count == 3 then Theme.red else Theme.green, UDim2.fromOffset(width, 90))
		button.AnchorPoint = Vector2.new(0.5, 0)
		button.Position = UDim2.new(0.5, -totalWidth / 2 + width / 2 + (count - 1) * (width + gap), 0, 160)
		button.TextSize = 28
		button.Activated:Connect(function()
			ctx.startSolo(count)
			ctx.closeOverlay()
		end)
	end

	local note = Components.label(panel, "Note", "Entraînement : aucune pièce gagnée, aucune statistique.", 16, Theme.muted, Theme.fontBody)
	note.Position = UDim2.fromOffset(0, 270)
	note.Size = UDim2.new(1, 0, 0, 24)

	local close = Components.button(panel, "CloseButton", "RETOUR", Theme.orange, UDim2.fromOffset(180, 52))
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -16)
	close.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	return { frame = frame, update = function(_s: any, _m: any) end, tick = function(_r: number?) end }
end

return Solo
