--!strict
-- Couleurs et polices de l'interface (palette du cahier des charges graphique, à valider au prototype visuel).

local Theme = {
	navy = Color3.fromRGB(21, 27, 49),
	panel = Color3.fromRGB(30, 38, 68),
	violet = Color3.fromRGB(107, 66, 237),
	yellow = Color3.fromRGB(255, 201, 75),
	turquoise = Color3.fromRGB(46, 220, 202),
	green = Color3.fromRGB(60, 190, 80),
	red = Color3.fromRGB(200, 70, 60),
	orange = Color3.fromRGB(255, 160, 40),
	white = Color3.new(1, 1, 1),
	muted = Color3.fromRGB(170, 178, 205),
	disabled = Color3.fromRGB(90, 96, 120),

	fontTitle = Enum.Font.GothamBlack,
	fontBold = Enum.Font.GothamBold,
	fontBody = Enum.Font.GothamMedium,
}

return Theme
