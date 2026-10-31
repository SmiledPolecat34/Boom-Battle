--!strict
-- Chat rapide : panneau « Récents | Favoris » de bulles préfaites. Un clic sur une bulle l'envoie (l'identifiant seul
-- part au serveur). Le « + » vert bascule la colonne de droite entre les favoris et le catalogue complet, où l'on
-- ajoute ou retire des favoris.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Parent.Components)
local QuickChatConfig = require(ReplicatedStorage.Shared.QuickChatConfig)
local QuickChatStore = require(script.Parent.Parent.Parent.Controllers.QuickChatStore)
local Theme = require(script.Parent.Parent.Theme)

local QuickChat = {}

local PANEL_WIDTH, PANEL_HEIGHT = 600, 470

local function column(panel: Instance, name: string, x: number): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(x, 70)
	scroll.Size = UDim2.fromOffset((PANEL_WIDTH - 60) / 2, PANEL_HEIGHT - 150)
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = scroll
	return scroll
end

function QuickChat.new(parent: Instance, ctx: any)
	-- Fond transparent qui absorbe les clics : un clic en dehors du panneau le ferme.
	local frame = Components.screen(parent, "QuickChat", true)
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

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local half = (PANEL_WIDTH - 60) / 2
	local recentsTitle = Components.label(panel, "RecentsTitle", "Récents", 28, Theme.white, Theme.fontTitle)
	recentsTitle.Position = UDim2.fromOffset(20, 16)
	recentsTitle.Size = UDim2.fromOffset(half, 40)
	recentsTitle.TextStrokeTransparency = 0
	local rightTitle = Components.label(panel, "RightTitle", "Favoris", 28, Theme.white, Theme.fontTitle)
	rightTitle.Position = UDim2.fromOffset(40 + half, 16)
	rightTitle.Size = UDim2.fromOffset(half, 40)
	rightTitle.TextStrokeTransparency = 0

	local divider = Instance.new("Frame")
	divider.Position = UDim2.fromOffset(PANEL_WIDTH / 2 - 1, 64)
	divider.Size = UDim2.fromOffset(3, PANEL_HEIGHT - 150)
	divider.BackgroundColor3 = Theme.violet
	divider.BorderSizePixel = 0
	divider.Parent = panel

	local recentsColumn = column(panel, "Recents", 20)
	local rightColumn = column(panel, "Right", 40 + half)

	local catalogMode = false

	local function clear(scroll: ScrollingFrame)
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	local function sendBubble(parentFrame: Instance, id: string, text: string, order: number, width: number): TextButton
		local bubble = Components.bubbleButton(parentFrame, "Phrase_" .. id, text, UDim2.fromOffset(width, 52))
		bubble.LayoutOrder = order
		bubble.Activated:Connect(function()
			ctx.sendQuickChat(id)
			ctx.closeOverlay()
		end)
		return bubble
	end

	local function render()
		clear(recentsColumn)
		clear(rightColumn)

		local recents = QuickChatStore.getRecents()
		if #recents == 0 then
			local empty = Components.label(recentsColumn, "Empty", "Les phrases que tu\nutilises apparaissent ici.", 16, Theme.muted, Theme.fontBody)
			empty.Size = UDim2.new(1, -8, 0, 60)
			empty.TextYAlignment = Enum.TextYAlignment.Top
		end
		for order, id in recents do
			local phrase = QuickChatConfig.get(id)
			if phrase then
				sendBubble(recentsColumn, id, phrase.text, order, half - 16)
			end
		end

		rightTitle.Text = if catalogMode then "Toutes" else "Favoris"
		if catalogMode then
			for order, phrase in QuickChatConfig.Phrases do
				local row = Instance.new("Frame")
				row.Name = "Row_" .. phrase.id
				row.LayoutOrder = order
				row.BackgroundTransparency = 1
				row.Size = UDim2.new(1, -8, 0, 52)
				row.Parent = rightColumn
				sendBubble(row, phrase.id, phrase.text, 1, half - 70)
				local starred = QuickChatStore.isFavorite(phrase.id)
				local toggle = Components.button(row, "Fav_" .. phrase.id, if starred then "×" else "+", if starred then Theme.red else Theme.green, UDim2.fromOffset(46, 46))
				toggle.AnchorPoint = Vector2.new(1, 0.5)
				toggle.Position = UDim2.new(1, -2, 0.5, 0)
				toggle.TextSize = 30
				toggle.Activated:Connect(function()
					QuickChatStore.toggleFavorite(phrase.id)
				end)
			end
		else
			for order, id in QuickChatStore.getFavorites() do
				local phrase = QuickChatConfig.get(id)
				if phrase then
					sendBubble(rightColumn, id, phrase.text, order, half - 16)
				end
			end
		end
	end
	QuickChatStore.Changed:Connect(render)

	-- Le « + » vert : bascule entre les favoris et le catalogue complet.
	local plus = Components.button(panel, "PlusButton", "+", Theme.green, UDim2.fromOffset(64, 64))
	plus.AnchorPoint = Vector2.new(0, 1)
	plus.Position = UDim2.new(0, 20, 1, -14)
	plus.TextSize = 48
	plus.Activated:Connect(function()
		catalogMode = not catalogMode
		plus.Text = if catalogMode then "←" else "+"
		render()
	end)

	local close = Components.button(panel, "CloseButton", "RETOUR", Theme.orange, UDim2.fromOffset(170, 50))
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -20, 1, -14)
	close.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	render()
	return { frame = frame, update = function(_s: any, _m: any) end, tick = function(_r: number?) end }
end

return QuickChat
