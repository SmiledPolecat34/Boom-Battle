--!strict
-- Navigateur de cosmétiques, utilisé pour la BOUTIQUE (tout le catalogue, achat) et l'INVENTAIRE (objets possédés,
-- équipement). Le client n'envoie qu'un identifiant : prix, possession et solde sont revérifiés par le serveur.
-- Les bombes s'affichent en 3D (vrai modèle : aperçu rotatif dans le détail, miniature dans la grille, créée seulement pour les
-- cartes visibles) ; une pastille colorée sert de repli si le modèle est introuvable (et pour les effets : les images de la
-- maquette ne sont pas utilisables, texte et prix incrustés). Acheter une bombe l'équipe automatiquement (règle serveur).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombVisuals = require(script.Parent.Parent.Parent.Controllers.BombVisuals)
local Components = require(script.Parent.Parent.Components)
local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local Theme = require(script.Parent.Parent.Theme)

local CosmeticBrowser = {}

local ERROR_TEXT = {
	funds = "Solde insuffisant.",
	owned = "Tu possèdes déjà cet objet.",
	not_owned = "Tu ne possèdes pas cet objet.",
	unknown = "Objet inconnu.",
	invalid_price = "Prix invalide.",
	no_profile = "Profil non chargé, réessaie dans un instant.",
}

-- Grille : 4 colonnes de cartes 112 x 128 (pas 8) dans une fenêtre de 340 de haut : sert à ne créer les aperçus 3D que des
-- cartes visibles (calcul par la mise en page, pas par AbsolutePosition qui n'est pas à jour juste après la création).
local GRID_COLUMNS = 4
local ROW_HEIGHT = 136
local GRID_VIEW_HEIGHT = 340
local PREVIEW_MARGIN_ROWS = 1

local function formatNumber(n: number): string
	local text = tostring(math.floor(n))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- mode : "shop" ou "inventory".
function CosmeticBrowser.new(parent: Instance, ctx: any, mode: string)
	local isShop = mode == "shop"
	local frame = Components.screen(parent, if isShop then "Shop" else "Inventory", true)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.45

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(820, 540))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.label(panel, "Title", if isShop then "BOUTIQUE" else "INVENTAIRE", 36, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(20, 12)
	title.Size = UDim2.fromOffset(360, 48)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local coinsLabel = Components.label(panel, "Coins", "", 26, Theme.yellow, Theme.fontBold)
	coinsLabel.AnchorPoint = Vector2.new(1, 0)
	coinsLabel.Position = UDim2.new(1, -20, 0, 18)
	coinsLabel.Size = UDim2.fromOffset(300, 36)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Right

	local state = { tab = "bomb" :: string, selected = nil :: string?, profile = nil :: any }
	local detailCleanup: (() -> ())? = nil
	-- Cartes de la grille courante (aperçus 3D créés / détruits selon leur visibilité).
	local cardPreviews: { { order: number, cosmetic: any, dot: Frame, holder: Frame, cleanup: (() -> ())?, tried: boolean } } = {}

	local tabButtons: { [string]: TextButton } = {}
	for index, entry in { { "bomb", "BOMBES" }, { "effect", "EFFETS" } } do
		local button = Components.button(panel, "Tab_" .. entry[1], entry[2], Theme.violet, UDim2.fromOffset(150, 44))
		button.Position = UDim2.fromOffset(20 + (index - 1) * 160, 68)
		button.TextSize = 20
		tabButtons[entry[1]] = button
	end

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(20, 122)
	grid.Size = UDim2.fromOffset(500, 340)
	grid.ScrollBarThickness = 8
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(112, 128)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	-- Détail de l'objet sélectionné.
	local detail = Components.panel(panel, "Detail", UDim2.fromOffset(250, 340))
	detail.Position = UDim2.fromOffset(540, 122)
	local detailName = Components.label(detail, "Name", "", 26, Theme.white, Theme.fontTitle)
	detailName.Position = UDim2.fromOffset(0, 10)
	detailName.Size = UDim2.new(1, 0, 0, 34)
	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.AnchorPoint = Vector2.new(0.5, 0)
	preview.Position = UDim2.new(0.5, 0, 0, 48)
	preview.Size = UDim2.fromOffset(150, 150)
	preview.ClipsDescendants = true
	preview.Parent = detail
	Components.corner(preview, 24)
	Components.stroke(preview, Theme.white, 2)
	local detailText = Components.label(detail, "Description", "", 15, Theme.muted, Theme.fontBody)
	detailText.Position = UDim2.fromOffset(10, 204)
	detailText.Size = UDim2.new(1, -20, 0, 62)
	detailText.TextYAlignment = Enum.TextYAlignment.Top
	local action = Components.button(detail, "Action", "", Theme.green, UDim2.new(1, -20, 0, 52))
	action.Position = UDim2.new(0, 10, 1, -64)
	action.TextSize = 20

	local feedback = Components.label(panel, "Feedback", "", 18, Theme.white, Theme.fontBold)
	feedback.AnchorPoint = Vector2.new(0, 1)
	feedback.Position = UDim2.new(0, 20, 1, -22)
	feedback.Size = UDim2.fromOffset(520, 28)
	feedback.TextXAlignment = Enum.TextXAlignment.Left

	local close = Components.button(panel, "CloseButton", "RETOUR", Theme.orange, UDim2.fromOffset(170, 50))
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -20, 1, -14)
	close.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	local function visibleIds(): { string }
		local ids: { string } = {}
		for _, id in CosmeticConfig.idsOfKind(state.tab :: any) do
			local owned = state.profile ~= nil and state.profile.owned[id] == true
			if isShop or owned then
				table.insert(ids, id)
			end
		end
		return ids
	end

	local render: () -> ()

	-- Aperçus 3D des cartes visibles (+ une rangée de marge) ; ceux qui sortent de la fenêtre sont détruits.
	local function refreshCardPreviews()
		local top = grid.CanvasPosition.Y
		for _, info in cardPreviews do
			local row = math.floor((info.order - 1) / GRID_COLUMNS)
			local rowTop = row * ROW_HEIGHT
			local visible = rowTop + ROW_HEIGHT >= top - PREVIEW_MARGIN_ROWS * ROW_HEIGHT
				and rowTop <= top + GRID_VIEW_HEIGHT + PREVIEW_MARGIN_ROWS * ROW_HEIGHT
			if visible and not info.cleanup and not info.tried then
				info.tried = true
				info.cleanup = BombVisuals.mountPreview(info.holder, info.cosmetic, false, 2, function()
					info.dot.Visible = true -- meshes non chargés : la pastille colorée reprend la place
				end, "static") -- miniature FIGÉE : flamme allumée, AUCUNE animation (seule la bombe sélectionnée, à droite, s'anime)
				info.dot.Visible = info.cleanup == nil
			elseif not visible and info.cleanup then
				info.cleanup()
				info.cleanup = nil
				info.tried = false
				info.dot.Visible = true
			end
		end
	end
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshCardPreviews)

	local function select(id: string)
		state.selected = id
		render()
	end

	render = function()
		local profile = state.profile
		coinsLabel.Text = if profile then ("Pièces : %s"):format(formatNumber(profile.coins)) else "Chargement..."
		for kind, button in tabButtons do
			button.BackgroundColor3 = if kind == state.tab then Theme.green else Theme.violet
		end

		for _, child in grid:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		table.clear(cardPreviews)
		local ids = visibleIds()
		if state.selected == nil or table.find(ids, state.selected) == nil then
			state.selected = ids[1]
		end

		for order, id in ids do
			local cosmetic = CosmeticConfig.get(id) :: CosmeticConfig.Cosmetic
			local owned = profile ~= nil and profile.owned[id] == true
			local equipped = profile ~= nil and profile.equipped[cosmetic.kind] == id
			local card = Instance.new("TextButton")
			card.Name = "Card_" .. id
			card.LayoutOrder = order
			card.Text = ""
			card.AutoButtonColor = true
			card.BackgroundColor3 = if id == state.selected then Theme.violet else Theme.navy
			card.Parent = grid
			Components.corner(card, 10)
			card.AutoButtonColor = false
			Components.addHover(card, { scale = 1.05 })
			if id == state.selected then
				Components.stroke(card, Theme.yellow, 3)
			end
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0)
			dot.Position = UDim2.new(0.5, 0, 0, 14)
			dot.Size = UDim2.fromOffset(56, 56)
			dot.BackgroundColor3 = cosmetic.color
			dot.Parent = card
			Components.corner(dot, 28)
			if cosmetic.kind == "bomb" then
				local holder = Instance.new("Frame")
				holder.Name = "Preview3DHolder"
				holder.AnchorPoint = Vector2.new(0.5, 0)
				holder.Position = UDim2.new(0.5, 0, 0, 2)
				holder.Size = UDim2.fromOffset(100, 86)
				holder.BackgroundTransparency = 1
				holder.Active = false
				holder.Parent = card
				table.insert(cardPreviews, { order = order, cosmetic = cosmetic, dot = dot, holder = holder, cleanup = nil, tried = false })
			end
			local name = Components.label(card, "Name", cosmetic.name, 16, Theme.white, Theme.fontBold)
			name.Position = UDim2.fromOffset(0, 76)
			name.Size = UDim2.new(1, 0, 0, 22)
			local status = Components.label(
				card,
				"Status",
				if equipped then "ÉQUIPÉ" elseif owned then "POSSÉDÉ" else tostring(cosmetic.price) .. " pièces",
				14,
				if equipped then Theme.green elseif owned then Theme.turquoise else Theme.yellow,
				Theme.fontBold
			)
			status.Position = UDim2.fromOffset(0, 100)
			status.Size = UDim2.new(1, 0, 0, 20)
			card.Activated:Connect(function()
				select(id)
			end)
		end

		refreshCardPreviews()

		-- Détail et bouton d'action.
		if detailCleanup then
			detailCleanup()
			detailCleanup = nil
		end
		local selected = if state.selected then CosmeticConfig.get(state.selected) else nil
		detail.Visible = selected ~= nil
		if selected then
			local owned = profile ~= nil and profile.owned[selected.id] == true
			local equipped = profile ~= nil and profile.equipped[selected.kind] == selected.id
			detailName.Text = selected.name
			preview.BackgroundColor3 = selected.color
			preview.BackgroundTransparency = 0
			if selected.kind == "bomb" then
				detailCleanup = BombVisuals.mountPreview(preview, selected, true, 3, function()
					preview.BackgroundTransparency = 0 -- meshes non chargés : on retrouve la couleur pleine
				end, "full")
				if detailCleanup then
					preview.BackgroundTransparency = 0.55 -- le modèle 3D se détache sur une teinte de la bombe
				end
			end
			detailText.Text = selected.description
			if equipped then
				action.Text = "ÉQUIPÉ"
				action.BackgroundColor3 = Theme.disabled
			elseif owned then
				action.Text = "ÉQUIPER"
				action.BackgroundColor3 = Theme.turquoise
			else
				local affordable = profile ~= nil and profile.coins >= selected.price
				action.Text = ("ACHETER\n%d pièces"):format(selected.price)
				action.BackgroundColor3 = if affordable then Theme.green else Theme.disabled
			end
		end
		if not isShop and #ids == 0 then
			feedback.Text = "Aucun objet dans cette catégorie."
		end
	end

	for kind, button in tabButtons do
		button.Activated:Connect(function()
			state.tab = kind
			state.selected = nil
			feedback.Text = ""
			render()
		end)
	end

	action.Activated:Connect(function()
		local id = state.selected
		local profile = state.profile
		if not id or not profile then
			return
		end
		local cosmetic = CosmeticConfig.get(id)
		if not cosmetic then
			return
		end
		if profile.owned[id] then
			if profile.equipped[cosmetic.kind] ~= id then
				ctx.equip(id)
			end
		elseif isShop then
			ctx.purchase(id) -- le serveur revérifie le solde : un bouton grisé n'est qu'une aide visuelle
		end
	end)

	return {
		frame = frame,
		setProfile = function(profile: any)
			state.profile = profile
			render()
		end,
		select = function(id: string) -- sélection par code (tests) : mêmes effets qu'un clic sur la carte
			select(id)
		end,
		onShopResult = function(result: any)
			if typeof(result) ~= "table" then
				return
			end
			if result.ok then
				if result.action == "purchase" then
					-- Le serveur indique si l'objet acheté est maintenant équipé (bombe : oui, automatiquement).
					feedback.Text = if result.equipped == true then "Achat réussi ! Objet équipé." else "Achat réussi !"
				else
					feedback.Text = "Objet équipé."
				end
				feedback.TextColor3 = Theme.green
			else
				feedback.Text = ERROR_TEXT[result.error] or "Action impossible."
				feedback.TextColor3 = Theme.red
			end
		end,
		update = function(_snapshot: any, _me: any) end,
		tick = function(_remaining: number?) end,
	}
end

return CosmeticBrowser
