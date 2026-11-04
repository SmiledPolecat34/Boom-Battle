--!strict
-- Commandes tactiles (mobile et tablette) : joystick ou croix directionnelle.
-- Ne décide de rien : elles n'écrivent qu'une direction dans InputController (« direction virtuelle »).
-- MovementController la lit comme une touche tenue et demande la case voisine au serveur (validée côté serveur).
-- Réglages (SettingsStore) : controlMode (Joystick / Croix), joystickFollows (le joystick apparaît sous le doigt),
-- flipControls (commandes à droite, bouton BOMBE à gauche).

local UserInputService = game:GetService("UserInputService")

local Components = require(script.Parent.Components)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local SettingsStore = require(script.Parent.Parent.Controllers.SettingsStore)

local TouchControls = {}

local BASE_SIZE = 150 -- diamètre du fond du joystick (pixels de conception)
local KNOB_SIZE = 64
local DEAD_ZONE = 0.3 -- part du rayon sous laquelle rien ne bouge
local PAD_BUTTON = 64 -- côté d'un bouton de la croix
local PAD_GAP = 8

-- Pur : direction de grille (x droite, y bas) pour un décalage en pixels ; nil dans la zone morte.
function TouchControls.directionFromOffset(offset: Vector2, radius: number): Vector2?
	if offset.Magnitude < radius * DEAD_ZONE then
		return nil
	end
	if math.abs(offset.X) >= math.abs(offset.Y) then
		return Vector2.new(if offset.X > 0 then 1 else -1, 0)
	end
	return Vector2.new(0, if offset.Y > 0 then 1 else -1)
end

function TouchControls.isTouchDevice(): boolean
	return UserInputService.TouchEnabled
end

-- Appelle callback quand l'appareil change (émulateur de Studio, clavier branché sur tablette...).
function TouchControls.onDeviceChanged(callback: () -> ())
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(callback)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(callback)
end

function TouchControls.new(parent: Frame)
	local container = Instance.new("Frame")
	container.Name = "TouchControls"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = parent

	local active = false
	local trackedInput: InputObject? = nil
	local startPosition = Vector2.zero

	local function setDirection(direction: Vector2?)
		InputController.setVirtualDirection(direction)
	end

	local function uiScale(): number
		local scale = parent.Parent and parent.Parent:FindFirstChildOfClass("UIScale")
		return if scale then math.max(scale.Scale, 0.01) else 1
	end

	-- ===== Joystick =====
	local zone = Instance.new("Frame") -- zone tactile (transparente) qui capte le doigt
	zone.Name = "JoystickZone"
	zone.BackgroundTransparency = 1
	zone.Active = true
	zone.Parent = container

	local base = Instance.new("Frame")
	base.Name = "JoystickBase"
	base.AnchorPoint = Vector2.new(0.5, 0.5)
	base.Size = UDim2.fromOffset(BASE_SIZE, BASE_SIZE)
	base.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	base.BackgroundTransparency = 0.45
	base.Active = false
	base.Parent = zone
	Components.corner(base, BASE_SIZE // 2)
	Components.stroke(base, Color3.fromRGB(255, 255, 255), 3)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.BackgroundColor3 = Color3.fromRGB(240, 240, 250)
	knob.BackgroundTransparency = 0.1
	knob.Active = false
	knob.Parent = base
	Components.corner(knob, KNOB_SIZE // 2)

	-- ===== Croix =====
	local pad = Instance.new("Frame")
	pad.Name = "DPad"
	pad.AnchorPoint = Vector2.new(0.5, 1)
	pad.Size = UDim2.fromOffset(PAD_BUTTON * 3 + PAD_GAP * 2, PAD_BUTTON * 3 + PAD_GAP * 2)
	pad.BackgroundTransparency = 1
	pad.Parent = container

	local padButtons: { TextButton } = {}
	local function addPadButton(name: string, glyph: string, column: number, row: number, direction: Vector2)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Size = UDim2.fromOffset(PAD_BUTTON, PAD_BUTTON)
		button.Position = UDim2.fromOffset((column - 1) * (PAD_BUTTON + PAD_GAP), (row - 1) * (PAD_BUTTON + PAD_GAP))
		button.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
		button.BackgroundTransparency = 0.35
		button.AutoButtonColor = false
		button.Text = glyph
		button.TextSize = 32
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Font = Enum.Font.GothamBold
		button.Parent = pad
		Components.corner(button, 12)
		Components.stroke(button, Color3.new(1, 1, 1), 2)
		button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				setDirection(direction)
				button.BackgroundTransparency = 0.05
				local connection: RBXScriptConnection
				connection = input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						connection:Disconnect()
						button.BackgroundTransparency = 0.35
						setDirection(nil)
					end
				end)
			end
		end)
		table.insert(padButtons, button)
	end
	addPadButton("Up", "▲", 2, 1, Vector2.new(0, -1))
	addPadButton("Left", "◀", 1, 2, Vector2.new(-1, 0))
	addPadButton("Right", "▶", 3, 2, Vector2.new(1, 0))
	addPadButton("Down", "▼", 2, 3, Vector2.new(0, 1))

	-- ===== Mise en page selon les réglages =====
	local function layout()
		local joystick = SettingsStore.get("controlMode") == "Joystick"
		local follows = SettingsStore.get("joystickFollows") == true
		local flipped = SettingsStore.get("flipControls") == true
		local anchorX = if flipped then 1 else 0 -- côté des commandes (le bouton BOMBE prend l'autre côté)
		local marginX = if flipped then -(24 + 75) else (24 + 75)

		zone.Visible = joystick
		pad.Visible = not joystick
		setDirection(nil)
		trackedInput = nil
		knob.Position = UDim2.fromScale(0.5, 0.5)

		if joystick then
			-- Zone : moitié de l'écran du côté des commandes, sous la ligne du haut (garde les boutons MENU/ÉMOTES libres).
			zone.AnchorPoint = Vector2.new(anchorX, 1)
			zone.Position = UDim2.new(anchorX, 0, 1, 0)
			zone.Size = UDim2.new(0.5, 0, 0.62, 0)
			if follows then
				base.Visible = false
			else
				base.Visible = true
				base.Position = UDim2.new(anchorX, marginX, 1, -(24 + BASE_SIZE // 2 + 20))
			end
		else
			pad.Position = UDim2.new(anchorX, if flipped then -(24 + pad.Size.X.Offset / 2) else (24 + pad.Size.X.Offset / 2), 1, -24)
		end
	end

	zone.InputBegan:Connect(function(input: InputObject)
		-- Mode Croix : le joystick est totalement inactif.
		if SettingsStore.get("controlMode") ~= "Joystick" then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch or trackedInput then
			return
		end
		trackedInput = input
		startPosition = Vector2.new(input.Position.X, input.Position.Y)
		if SettingsStore.get("joystickFollows") == true then
			local origin = zone.AbsolutePosition
			base.Position = UDim2.fromOffset((startPosition.X - origin.X) / uiScale(), (startPosition.Y - origin.Y) / uiScale())
			base.Visible = true
		else
			local center = base.AbsolutePosition + base.AbsoluteSize / 2
			startPosition = center
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input ~= trackedInput or SettingsStore.get("controlMode") ~= "Joystick" then
			return
		end
		local offset = (Vector2.new(input.Position.X, input.Position.Y) - startPosition) / uiScale()
		local radius = BASE_SIZE / 2
		local clamped = if offset.Magnitude > radius then offset.Unit * radius else offset
		knob.Position = UDim2.new(0.5, clamped.X, 0.5, clamped.Y)
		setDirection(TouchControls.directionFromOffset(offset, radius))
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input ~= trackedInput then
			return
		end
		trackedInput = nil
		knob.Position = UDim2.fromScale(0.5, 0.5)
		setDirection(nil)
		if SettingsStore.get("joystickFollows") == true then
			base.Visible = false
		end
	end)

	SettingsStore.Changed:Connect(function(key: string)
		if key == "controlMode" or key == "joystickFollows" or key == "flipControls" then
			layout()
		end
	end)
	layout()

	return {
		-- Affiche les commandes seulement sur appareil tactile, pendant la manche, pour un joueur vivant.
		setActive = function(value: boolean)
			active = value and TouchControls.isTouchDevice()
			container.Visible = active
			if not active then
				trackedInput = nil
				setDirection(nil)
			end
		end,
		isActive = function(): boolean
			return active
		end,
	}
end

return TouchControls
