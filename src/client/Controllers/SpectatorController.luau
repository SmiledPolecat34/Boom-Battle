--!strict
-- Bandeau « spectateur » (PROVISOIRE, Phase 3). La caméra fixe montre déjà toute l'arène : l'observation d'un joueur
-- précis (précédent / suivant) n'est pas implémentée et sera ajoutée avec le SpectatorHUD de la Phase 4.

local SpectatorController = {}

local label: TextLabel? = nil

function SpectatorController.attach(parent: Instance)
	if label then
		return
	end
	local banner = Instance.new("TextLabel")
	banner.Name = "SpectatorBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 96)
	banner.Size = UDim2.fromOffset(420, 34)
	banner.BackgroundColor3 = Color3.fromRGB(107, 66, 237)
	banner.BackgroundTransparency = 0.15
	banner.TextColor3 = Color3.new(1, 1, 1)
	banner.Font = Enum.Font.GothamBold
	banner.TextSize = 18
	banner.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = banner
	banner.Parent = parent
	label = banner
end

-- text == nil : masque le bandeau.
function SpectatorController.setText(text: string?)
	if not label then
		return
	end
	label.Visible = text ~= nil
	if text then
		label.Text = text
	end
end

return SpectatorController
