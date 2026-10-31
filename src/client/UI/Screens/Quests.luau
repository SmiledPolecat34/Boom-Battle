--!strict
-- Quêtes : progression et récompenses (créditées automatiquement par le serveur à l'objectif atteint).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Parent.Components)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local Theme = require(script.Parent.Parent.Theme)

local Quests = {}

function Quests.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "Quests", true)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.45

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(620, 460))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.label(panel, "Title", "QUÊTES", 36, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 48)

	local rows: { [string]: { fill: Frame, count: TextLabel, tag: TextLabel } } = {}
	for index, quest in QuestConfig.Quests do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. quest.id
		row.Position = UDim2.fromOffset(24, 76 + (index - 1) * 96)
		row.Size = UDim2.new(1, -48, 0, 84)
		row.BackgroundColor3 = Theme.navy
		row.BackgroundTransparency = 0.2
		row.Parent = panel
		Components.corner(row, 10)

		local name = Components.label(row, "Name", quest.name, 22, Theme.white, Theme.fontBold)
		name.Position = UDim2.fromOffset(14, 6)
		name.Size = UDim2.new(0.6, 0, 0, 28)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local desc = Components.label(row, "Description", quest.description, 16, Theme.muted, Theme.fontBody)
		desc.Position = UDim2.fromOffset(14, 34)
		desc.Size = UDim2.new(0.6, 0, 0, 22)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		local reward = Components.label(row, "Reward", ("+%d pièces"):format(quest.reward), 18, Theme.yellow, Theme.fontBold)
		reward.AnchorPoint = Vector2.new(1, 0)
		reward.Position = UDim2.new(1, -14, 0, 8)
		reward.Size = UDim2.fromOffset(160, 24)
		reward.TextXAlignment = Enum.TextXAlignment.Right
		local tag = Components.label(row, "Tag", "", 16, Theme.green, Theme.fontBold)
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -14, 0, 34)
		tag.Size = UDim2.fromOffset(160, 22)
		tag.TextXAlignment = Enum.TextXAlignment.Right

		local bar = Instance.new("Frame")
		bar.Position = UDim2.new(0, 14, 1, -22)
		bar.Size = UDim2.new(1, -120, 0, 12)
		bar.BackgroundColor3 = Theme.disabled
		bar.Parent = row
		Components.corner(bar, 6)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = Theme.turquoise
		fill.Parent = bar
		Components.corner(fill, 6)
		local count = Components.label(row, "Count", "", 16, Theme.white, Theme.fontBold)
		count.AnchorPoint = Vector2.new(1, 1)
		count.Position = UDim2.new(1, -14, 1, -14)
		count.Size = UDim2.fromOffset(90, 20)
		count.TextXAlignment = Enum.TextXAlignment.Right
		rows[quest.id] = { fill = fill, count = count, tag = tag }
	end

	local close = Components.button(panel, "CloseButton", "RETOUR", Theme.orange, UDim2.fromOffset(180, 52))
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -14)
	close.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	return {
		frame = frame,
		setProfile = function(profile: any)
			for _, quest in QuestConfig.Quests do
				local row = rows[quest.id]
				local saved = profile.quests[quest.id]
				local progress = if saved then saved.progress else 0
				local done = saved ~= nil and saved.done == true
				row.fill.Size = UDim2.fromScale(math.clamp(progress / quest.goal, 0, 1), 1)
				row.count.Text = ("%d / %d"):format(progress, quest.goal)
				row.tag.Text = if done then "✓ Terminée" else ""
			end
		end,
		update = function(_snapshot: any, _me: any) end,
		tick = function(_remaining: number?) end,
	}
end

return Quests
