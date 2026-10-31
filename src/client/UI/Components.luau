--!strict
-- Composants d'interface réutilisables. Toutes les dimensions sont en « pixels de conception » : le gestionnaire
-- d'écrans applique un UIScale selon la taille réelle de l'écran (PC, tablette, mobile).

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Components = {}

function Components.corner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

function Components.stroke(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

-- Écran plein cadre, masqué par défaut. sink = true : absorbe les clics (aucun déplacement derrière un menu).
function Components.screen(parent: Instance, name: string, sink: boolean): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = sink
	frame.Visible = false
	frame.Parent = parent
	return frame
end

function Components.panel(parent: Instance, name: string, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.BackgroundColor3 = Theme.panel
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Parent = parent
	Components.corner(frame, 14)
	Components.stroke(frame, Theme.violet, 2)
	return frame
end

function Components.label(
	parent: Instance,
	name: string,
	text: string,
	textSize: number,
	color: Color3?,
	font: Enum.Font?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, textSize + 8)
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = color or Theme.white
	label.Font = font or Theme.fontBody
	label.TextWrapped = true
	label.Parent = parent
	return label
end

-- États d'un bouton : survol (PC) = léger agrandissement + voile clair ; pression (PC et tactile) = léger rétrécissement.
-- Utilise un UIScale et un voile enfant : ne touche jamais BackgroundColor3 (que le code change selon l'état du jeu).
-- options.scale : échelle au survol (1,05 par défaut) ; options.glow = false : pas de voile (ex. icônes transparentes).
function Components.addHover(button: GuiButton, options: { scale: number?, glow: boolean? }?)
	local hoverScale = (options and options.scale) or 1.05
	local useGlow = not (options and options.glow == false)

	local scale = Instance.new("UIScale")
	scale.Name = "HoverScale"
	scale.Parent = button

	local glow: Frame? = nil
	if useGlow then
		local overlay = Instance.new("Frame")
		overlay.Name = "HoverGlow"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.new(1, 1, 1)
		overlay.BackgroundTransparency = 1
		overlay.BorderSizePixel = 0
		overlay.Active = false -- ne bloque jamais le clic du bouton
		overlay.ZIndex = button.ZIndex + 1
		local existing = button:FindFirstChildOfClass("UICorner")
		Components.corner(overlay, if existing then existing.CornerRadius.Offset else 12)
		overlay.Parent = button
		glow = overlay
	end

	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local hovered = false
	local function apply(targetScale: number, glowTransparency: number)
		TweenService:Create(scale, info, { Scale = targetScale }):Play()
		if glow then
			TweenService:Create(glow, info, { BackgroundTransparency = glowTransparency }):Play()
		end
	end

	button.MouseEnter:Connect(function()
		hovered = true
		apply(hoverScale, 0.82)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		apply(1, 1)
	end)
	button.MouseButton1Down:Connect(function()
		apply(0.95, 0.9)
	end)
	button.MouseButton1Up:Connect(function()
		if hovered then
			apply(hoverScale, 0.82)
		else
			apply(1, 1)
		end
	end)
end

-- Bouton avec retour visuel (survol PC, pression mobile). Retourne le bouton ; brancher .Activated.
function Components.button(parent: Instance, name: string, text: string, color: Color3, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = color
	button.AutoButtonColor = false -- remplacé par addHover (agrandissement + voile)
	button.Text = text
	button.TextColor3 = Theme.white
	button.Font = Theme.fontTitle
	button.TextSize = 24
	button.TextStrokeTransparency = 0.5
	button.Parent = parent
	Components.corner(button, 12)
	Components.stroke(button, Theme.navy, 2)
	Components.addHover(button)
	return button
end

return Components
