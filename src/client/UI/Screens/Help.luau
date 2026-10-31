--!strict
-- Aide : règles et commandes TELLES QU'IMPLÉMENTÉES. À mettre à jour quand le gameplay change.

local Components = require(script.Parent.Parent.Components)
local Theme = require(script.Parent.Parent.Theme)

local Help = {}

local TEXT = table.concat({
	"OBJECTIF",
	"Sois le dernier survivant de l'arène.",
	"",
	"COMMANDES",
	"• Se déplacer : clique ou touche une case de l'arène.",
	"• Poser une bombe : bouton BOMBE à l'écran (ou barre d'espace sur PC).",
	"",
	"BOMBES",
	"• Elles explosent après 2 secondes, en croix.",
	"• Les murs gris arrêtent l'explosion ; les caisses sont détruites.",
	"• Une bombe touchée explose aussitôt : réaction en chaîne.",
	"• Toucher une explosion t'élimine, sauf si tu as un bouclier.",
	"",
	"BONUS (laissés par certaines caisses)",
	"• B+ : une bombe de plus à la fois.",
	"• F+ : explosion plus longue d'une case.",
	"• S+ : tu te déplaces plus vite.",
	"• SH : un bouclier qui absorbe une explosion.",
	"",
	"MANCHE",
	"• Clique PLAY, puis PRÊT. La manche démarre quand tous sont prêts.",
	"• Elle dure 2 min 30. À la fin du temps, les survivants sont à égalité.",
	"• Éliminé, tu regardes la fin de la manche.",
}, "\n")

function Help.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "Help", true)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.45

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(620, 500))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.label(panel, "Title", "AIDE", 36, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 48)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(20, 70)
	scroll.Size = UDim2.new(1, -40, 1, -150)
	scroll.ScrollBarThickness = 8
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local body = Components.label(scroll, "Body", TEXT, 19, Theme.white, Theme.fontBody)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Size = UDim2.new(1, -12, 0, 0)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top

	local close = Components.button(panel, "CloseButton", "RETOUR", Theme.orange, UDim2.fromOffset(180, 52))
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -14)
	close.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	return { frame = frame, update = function(_s: any, _m: any) end, tick = function(_r: number?) end }
end

return Help
