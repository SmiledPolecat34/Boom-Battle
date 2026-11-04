--!strict
-- Réglages d'affichage : taille du bouton bombe, taille de l'interface, repère de case.
-- Conservés pendant la session (sauvegarde en Phase 6). Aucun réglage audio tant qu'aucun son n'existe.

local Components = require(script.Parent.Parent.Components)
local SettingsStore = require(script.Parent.Parent.Parent.Controllers.SettingsStore)
local Theme = require(script.Parent.Parent.Theme)
local TouchControls = require(script.Parent.Parent.TouchControls)

local Settings = {}

function Settings.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "Settings", true)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.45

	-- Clic en dehors du panneau : referme et revient au jeu.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.ZIndex = 1
	backdrop.Parent = frame
	backdrop.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	local panel = Components.panel(frame, "Panel", UDim2.fromOffset(560, 440))
	panel.ZIndex = 2 -- au-dessus du fond cliquable
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.label(panel, "Title", "RÉGLAGES", 36, Theme.yellow, Theme.fontTitle)
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 48)

	local choiceButtons: { { button: TextButton, key: string, value: any } } = {}

	-- Section tactile : créée toujours, affichée selon l'appareil en direct (l'émulateur de Studio peut changer après le chargement).
	local touchSection = Instance.new("Frame")
	touchSection.Name = "TouchSection"
	touchSection.Size = UDim2.fromScale(1, 1)
	touchSection.BackgroundTransparency = 1
	touchSection.Parent = panel

	local function addChoiceRow(y: number, caption: string, key: string, options: { string }, host: Instance?)
		local panel = host or panel
		local label = Components.label(panel, key .. "Caption", caption, 20, Theme.white, Theme.fontBold)
		label.Position = UDim2.fromOffset(24, y)
		label.Size = UDim2.new(1, -48, 0, 26)
		label.TextXAlignment = Enum.TextXAlignment.Left
		for index, option in options do
			local button = Components.button(panel, key .. option, option, Theme.violet, UDim2.fromOffset(150, 46))
			button.Position = UDim2.fromOffset(24 + (index - 1) * 164, y + 32)
			button.TextSize = 20
			button.Activated:Connect(function()
				SettingsStore.set(key :: any, option)
			end)
			table.insert(choiceButtons, { button = button, key = key, value = option })
		end
	end

	addChoiceRow(78, "Taille du bouton BOMBE", "bombButtonSize", { "Petit", "Moyen", "Grand" })
	addChoiceRow(176, "Taille de l'interface", "uiScale", { "Petit", "Normal", "Grand" })

	local markerLabel = Components.label(panel, "MarkerCaption", "Repère de la case visée", 20, Theme.white, Theme.fontBold)
	markerLabel.Position = UDim2.fromOffset(24, 274)
	markerLabel.Size = UDim2.new(1, -48, 0, 26)
	markerLabel.TextXAlignment = Enum.TextXAlignment.Left
	local marker = Components.button(panel, "MarkerToggle", "", Theme.green, UDim2.fromOffset(150, 46))
	marker.Position = UDim2.fromOffset(24, 306)
	marker.TextSize = 20
	marker.Activated:Connect(function()
		SettingsStore.set("showMoveMarker", not SettingsStore.get("showMoveMarker"))
	end)

	local timerCaption = Components.label(panel, "TimerCaption", "Minuteur de manche", 20, Theme.white, Theme.fontBold)
	timerCaption.Position = UDim2.fromOffset(300, 274)
	timerCaption.Size = UDim2.new(1, -324, 0, 26)
	timerCaption.TextXAlignment = Enum.TextXAlignment.Left
	local timerToggle = Components.button(panel, "TimerToggle", "", Theme.green, UDim2.fromOffset(150, 46))
	timerToggle.Position = UDim2.fromOffset(300, 306)
	timerToggle.TextSize = 20
	timerToggle.Activated:Connect(function()
		SettingsStore.set("showTimer", not SettingsStore.get("showTimer"))
	end)

	-- Commandes tactiles : seulement sur mobile / tablette (pas de faux bouton sur PC).
	local touchToggles: { { button: TextButton, key: string, on: string, off: string } } = {}
	local followsLabel: TextLabel, followsToggle: TextButton, flipLabel: TextLabel, flipToggle: TextButton
	do
		addChoiceRow(352, "Commandes tactiles", "controlMode", { "Joystick", "Croix" }, touchSection)
		local function addToggleRow(y: number, caption: string, key: string, on: string, off: string): (TextLabel, TextButton)
			local label = Components.label(touchSection, key .. "Caption", caption, 20, Theme.white, Theme.fontBold)
			label.Position = UDim2.fromOffset(24, y)
			label.Size = UDim2.fromOffset(300, 46)
			label.TextXAlignment = Enum.TextXAlignment.Left
			local toggle = Components.button(touchSection, key .. "Toggle", "", Theme.green, UDim2.fromOffset(150, 46))
			toggle.Position = UDim2.fromOffset(340, y)
			toggle.TextSize = 20
			toggle.Activated:Connect(function()
				SettingsStore.set(key :: any, not SettingsStore.get(key :: any))
			end)
			table.insert(touchToggles, { button = toggle, key = key, on = on, off = off })
			return label, toggle
		end
		followsLabel, followsToggle = addToggleRow(440, "Joystick sous le doigt", "joystickFollows", "Activé", "Désactivé")
		flipLabel, flipToggle = addToggleRow(496, "Inverser les commandes", "flipControls", "Inversé", "Normal")
	end

	local note = Components.label(panel, "Note", "Réglages conservés pendant la session.", 14, Theme.muted, Theme.fontBody)
	note.Size = UDim2.new(1, 0, 0, 20)

	local close = Components.button(panel, "CloseButton", "RETOUR", Theme.orange, UDim2.fromOffset(180, 52))
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -14)
	close.Activated:Connect(function()
		ctx.closeOverlay()
	end)

	local function refresh()
		for _, entry in choiceButtons do
			local selected = SettingsStore.get(entry.key :: any) == entry.value
			entry.button.BackgroundColor3 = if selected then Theme.green else Theme.violet
		end
		local shown = SettingsStore.get("showMoveMarker")
		marker.Text = if shown then "Activé" else "Désactivé"
		marker.BackgroundColor3 = if shown then Theme.green else Theme.disabled
		local timerShown = SettingsStore.get("showTimer")
		timerToggle.Text = if timerShown then "Affiché" else "Masqué"
		timerToggle.BackgroundColor3 = if timerShown then Theme.green else Theme.disabled
		for _, entry in touchToggles do
			local value = SettingsStore.get(entry.key :: any) == true
			entry.button.Text = if value then entry.on else entry.off
			entry.button.BackgroundColor3 = if value then Theme.green else Theme.disabled
		end

		-- « Joystick sous le doigt » n'existe qu'avec le joystick ; avec la croix la ligne disparaît et l'autre remonte.
		local touch = TouchControls.isTouchDevice()
		local joystick = SettingsStore.get("controlMode") == "Joystick"
		followsLabel.Visible = joystick
		followsToggle.Visible = joystick
		local flipY = if joystick then 496 else 440
		flipLabel.Position = UDim2.fromOffset(24, flipY)
		flipToggle.Position = UDim2.fromOffset(340, flipY)
		touchSection.Visible = touch
		local height = if not touch then 440 elseif joystick then 640 else 584
		panel.Size = UDim2.fromOffset(560, height)
		note.Position = UDim2.fromOffset(0, height - 84)
	end
	SettingsStore.Changed:Connect(refresh)
	refresh()

	TouchControls.onDeviceChanged(refresh)

	return { frame = frame, update = function(_s: any, _m: any) end, tick = function(_r: number?) end }
end

return Settings
