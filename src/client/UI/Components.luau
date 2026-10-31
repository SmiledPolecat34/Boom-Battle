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

-- Texte « arcade » façon bouton PLAY : police épaisse arrondie (FredokaOne), dégradé vertical jaune → orange → rouge
-- orangé, gros contour noir, ombre noire décalée vers le bas et reflet blanc sur le haut des lettres.
-- Quatre TextLabel transparents superposés dans une zone en FRACTIONS du parent (donc responsive : PC, tablette,
-- mobile) ; le texte est mis à l'échelle (TextScaled) dans cette zone. Retourne la zone.
export type TextArea = { x: number, y: number, width: number, height: number }

local TITLE_TOP = Color3.fromHex("#FFD52A")
local TITLE_MIDDLE = Color3.fromHex("#FF9800")
local TITLE_BOTTOM = Color3.fromHex("#F04400")
local TITLE_OUTLINE = Color3.fromHex("#080808")
local TITLE_STROKE_THICKNESS = 6 -- px de conception (mis à l'échelle avec l'interface)
local TITLE_SHADOW_OFFSET = 0.07 -- fraction de la hauteur de la zone, soit environ 5 px sur le bouton PLAY

function Components.arcadeText(parent: Instance, name: string, text: string, area: TextArea): Frame
	local zone = Instance.new("Frame")
	zone.Name = name
	zone.BackgroundTransparency = 1
	zone.BorderSizePixel = 0
	zone.Active = false -- ne bloque jamais le clic du bouton parent
	zone.Position = UDim2.fromScale(area.x, area.y)
	zone.Size = UDim2.fromScale(area.width, area.height)
	zone.ZIndex = if parent:IsA("GuiObject") then (parent :: GuiObject).ZIndex + 2 else 2
	zone.Parent = parent

	local function layer(layerName: string, offsetY: number, textColor: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = layerName
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Position = UDim2.fromScale(0, offsetY)
		label.Font = Enum.Font.FredokaOne
		label.Text = string.upper(text)
		label.TextColor3 = textColor
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Rotation = 0
		label.Active = false
		label.Parent = zone
		return label
	end

	-- 1. Ombre : noire, décalée vers le bas, avec son propre contour pour garder la silhouette épaisse.
	local shadow = layer("Shadow", TITLE_SHADOW_OFFSET, TITLE_OUTLINE)
	shadow.ZIndex = zone.ZIndex
	local shadowStroke = Instance.new("UIStroke")
	shadowStroke.Color = TITLE_OUTLINE
	shadowStroke.Thickness = TITLE_STROKE_THICKNESS
	shadowStroke.LineJoinMode = Enum.LineJoinMode.Round
	shadowStroke.Parent = shadow

	-- 2. Texte : dégradé vertical (le dégradé enfant du TextLabel colore le texte, pas le contour) + contour noir.
	local main = layer("Text", 0, Color3.new(1, 1, 1))
	main.ZIndex = zone.ZIndex + 1
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90 -- de haut en bas
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, TITLE_TOP),
		ColorSequenceKeypoint.new(0.5, TITLE_MIDDLE),
		ColorSequenceKeypoint.new(1, TITLE_BOTTOM),
	})
	gradient.Parent = main
	local stroke = Instance.new("UIStroke")
	stroke.Color = TITLE_OUTLINE
	stroke.Thickness = TITLE_STROKE_THICKNESS
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = main

	-- 3. Reflet : le même texte en blanc, visible seulement sur le haut des lettres (transparence en dégradé).
	local shine = layer("Shine", -0.015, Color3.new(1, 1, 1))
	shine.ZIndex = zone.ZIndex + 2
	local shineGradient = Instance.new("UIGradient")
	shineGradient.Rotation = 90
	shineGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.4, 0.8),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	shineGradient.Parent = shine

	return zone
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
