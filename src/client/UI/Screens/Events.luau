--!strict
-- Événements : affiche uniquement ce qui existe réellement (EventConfig.Events). Aujourd'hui : aucun, et le dit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Parent.Components)
local EventConfig = require(ReplicatedStorage.Shared.EventConfig)
local Theme = require(script.Parent.Parent.Theme)

local Events = {}

function Events.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "Events", true)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.45

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(560, 380))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.label(panel, "Title", "ÉVÉNEMENTS", 36, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 48)

	local body = Components.label(panel, "Body", "", 20, Theme.white, Theme.fontBody)
	body.Position = UDim2.fromOffset(24, 80)
	body.Size = UDim2.new(1, -48, 0, 220)
	body.TextYAlignment = Enum.TextYAlignment.Top

	local lines: { string } = {}
	local now = os.time()
	for _, event in EventConfig.Events do
		local active = (event.startsAt == nil or now >= event.startsAt) and (event.endsAt == nil or now <= event.endsAt)
		if active then
			table.insert(lines, ("• %s\n   %s"):format(event.name, event.description))
		end
	end
	body.Text = if #lines > 0 then table.concat(lines, "\n\n") else "Aucun événement en cours.\nReviens bientôt !"
	body.TextXAlignment = if #lines > 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center

	local close = Components.button(panel, "CloseButton", "RETOUR", Theme.orange, UDim2.fromOffset(180, 52))
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -14)
	close.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	return { frame = frame, update = function(_s: any, _m: any) end, tick = function(_r: number?) end }
end

return Events
