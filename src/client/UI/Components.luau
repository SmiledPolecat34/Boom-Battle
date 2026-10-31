--!strict
-- Composants d'interface réutilisables. Toutes les dimensions sont en « pixels de conception » : le gestionnaire
-- d'écrans applique un UIScale selon la taille réelle de l'écran (PC, tablette, mobile).

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

-- Bouton avec retour visuel (survol PC, pression mobile). Retourne le bouton ; brancher .Activated.
function Components.button(parent: Instance, name: string, text: string, color: Color3, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.Text = text
	button.TextColor3 = Theme.white
	button.Font = Theme.fontTitle
	button.TextSize = 24
	button.TextStrokeTransparency = 0.5
	button.Parent = parent
	Components.corner(button, 12)
	Components.stroke(button, Theme.navy, 2)
	return button
end

return Components
