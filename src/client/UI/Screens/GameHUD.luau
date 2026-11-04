--!strict
-- HUD de manche : chronomètre, survivants, statistiques, bouton bombe, compte à rebours, mode spectateur.
-- Il reste en périphérie : rien ne couvre le centre de l'arène (cases de départ, trajectoires d'explosion).

local UserInputService = game:GetService("UserInputService")

local Components = require(script.Parent.Parent.Components)
local InputController = require(script.Parent.Parent.Parent.Controllers.InputController)
local SettingsStore = require(script.Parent.Parent.Parent.Controllers.SettingsStore)
local Theme = require(script.Parent.Parent.Theme)
local TouchControls = require(script.Parent.Parent.TouchControls)
local CosmeticConfig = require(game:GetService("ReplicatedStorage").Shared.CosmeticConfig)

local GameHUD = {}

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

function GameHUD.new(parent: Instance, ctx: any)
	local frame = Components.screen(parent, "GameHUD", false)

	-- Haut : chronomètre et survivants.
	local timer = Components.label(frame, "Timer", "", 44, Theme.white, Theme.fontTitle)
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = UDim2.new(0.5, 0, 0, 10)
	timer.Size = UDim2.fromOffset(220, 52)
	timer.TextStrokeTransparency = 0.3
	local survivors = Components.label(frame, "Survivors", "", 22, Theme.yellow, Theme.fontBold)
	survivors.AnchorPoint = Vector2.new(0.5, 0)
	survivors.Position = UDim2.new(0.5, 0, 0, 62)
	survivors.Size = UDim2.fromOffset(320, 30)
	survivors.TextStrokeTransparency = 0.3

	-- Bas gauche : statistiques et bonus actifs.
	local stats = Components.panel(frame, "Stats", UDim2.fromOffset(210, 124))
	stats.AnchorPoint = Vector2.new(0, 1)
	stats.Position = UDim2.new(0, 16, 1, -16)
	stats.BackgroundTransparency = 0.25
	local statLabels: { [string]: TextLabel } = {}
	for index, key in { "bombs", "range", "speed", "shield" } do
		local label = Components.label(stats, key, "", 20, Theme.white, Theme.fontBold)
		label.Position = UDim2.fromOffset(14, 8 + (index - 1) * 28)
		label.Size = UDim2.new(1, -20, 0, 26)
		label.TextXAlignment = Enum.TextXAlignment.Left
		statLabels[key] = label
	end

	-- Bas droite : bouton bombe (grande zone tactile, taille réglable).
	local bomb = Components.button(frame, "BombButton", "BOMBE", Theme.orange, UDim2.fromOffset(120, 120))
	bomb.AnchorPoint = Vector2.new(1, 1)
	bomb.Position = UDim2.new(1, -24, 1, -24)
	bomb.TextSize = 24
	local bombCorner = bomb:FindFirstChildOfClass("UICorner")
	if bombCorner then
		bombCorner.CornerRadius = UDim.new(1, 0)
	end

	-- Le bouton montre la bombe équipée (même couleur et matière que la vraie bombe), pas un simple texte.
	bomb.Text = ""
	bomb.BackgroundColor3 = Theme.navy
	Components.stroke(bomb, Theme.orange, 4)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "BombIcon"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(0.86, 0.86)
	viewport.BackgroundTransparency = 1
	viewport.Active = false
	viewport.Ambient = Color3.fromRGB(150, 150, 165)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1.2, -0.8)
	viewport.ZIndex = 2
	viewport.Parent = bomb
	local iconCamera = Instance.new("Camera")
	iconCamera.FieldOfView = 35
	iconCamera.CFrame = CFrame.lookAt(Vector3.new(0, 2.2, 9), Vector3.new(0, 0.6, 0))
	iconCamera.Parent = viewport
	viewport.CurrentCamera = iconCamera
	local function iconPart(shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Shape = shape
		part.Size = size
		part.CFrame = cframe
		part.Color = color
		part.Material = material
		part.Parent = viewport
		return part
	end
	local body = iconPart(Enum.PartType.Ball, Vector3.new(3, 3, 3), CFrame.new(0, 0, 0), Color3.fromRGB(35, 35, 45), Enum.Material.SmoothPlastic)
	iconPart(Enum.PartType.Cylinder, Vector3.new(0.7, 0.5, 0.5), CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 70, 80), Enum.Material.Metal)
	iconPart(Enum.PartType.Ball, Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 2.25, 0), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)

	local function setBombSkin(profile: any)
		local equipped = if typeof(profile) == "table" and typeof(profile.equipped) == "table" then profile.equipped.bomb else nil
		local skin = CosmeticConfig.get(equipped) or CosmeticConfig.get(CosmeticConfig.Defaults.bomb)
		if skin then
			body.Color = skin.color
			body.Material = skin.material or Enum.Material.SmoothPlastic
		end
	end
	setBombSkin(nil)

	-- Haut droite : menu de pause (quitter, aide, réglages). Toujours disponible, y compris pour un spectateur.
	local menu = Components.button(frame, "MenuButton", "MENU", Theme.navy, UDim2.fromOffset(120, 44))
	menu.AnchorPoint = Vector2.new(1, 0)
	menu.Position = UDim2.new(1, -24, 0, 20)
	menu.TextSize = 18
	menu.Activated:Connect(function()
		ctx.openOverlay("Pause")
	end)

	-- Haut droite : émotes et chat rapide (joueurs de la manche seulement). Les petits boutons restent en périphérie.
	local emotes = Components.button(frame, "EmotesButton", "ÉMOTES", Theme.violet, UDim2.fromOffset(120, 44))
	emotes.AnchorPoint = Vector2.new(1, 0)
	emotes.Position = UDim2.new(1, -24, 0, 76)
	emotes.TextSize = 18
	emotes.Activated:Connect(function()
		ctx.openOverlay("Emotes")
	end)
	local chat = Components.bubbleButton(frame, "ChatButton", "CHAT", UDim2.fromOffset(120, 44))
	chat.AnchorPoint = Vector2.new(1, 0)
	chat.Position = UDim2.new(1, -24, 0, 128)
	chat.Activated:Connect(function()
		ctx.openOverlay("QuickChat")
	end)

	-- Centre : compte à rebours de début de manche.
	local countdown = Components.label(frame, "Countdown", "", 120, Theme.yellow, Theme.fontTitle)
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.Position = UDim2.fromScale(0.5, 0.4)
	countdown.Size = UDim2.fromOffset(300, 140)
	countdown.TextStrokeTransparency = 0

	-- Spectateur : bandeau et sortie vers le menu.
	local banner = Components.label(frame, "SpectatorBanner", "", 20, Theme.white, Theme.fontBold)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 100)
	banner.Size = UDim2.fromOffset(520, 34)
	banner.BackgroundTransparency = 0.15
	banner.BackgroundColor3 = Theme.violet
	Components.corner(banner, 8)
	local leave = Components.button(frame, "LeaveButton", "QUITTER", Theme.violet, UDim2.fromOffset(180, 56))
	leave.AnchorPoint = Vector2.new(0.5, 1)
	leave.Position = UDim2.new(0.5, 0, 1, -24)
	leave.Activated:Connect(function()
		ctx.setQueued(false)
	end)

	-- Raccourcis clavier (PC) : M = menu, E = émotes, C = chat rapide. Ignorés pendant une saisie de texte,
	-- hors du HUD, ou quand le bouton correspondant n'est pas affiché (ex. émotes pour un spectateur sans personnage).
	local SHORTCUTS: { [Enum.KeyCode]: { overlay: string, button: GuiButton } } = {
		[Enum.KeyCode.M] = { overlay = "Pause", button = menu },
		[Enum.KeyCode.E] = { overlay = "Emotes", button = emotes },
		[Enum.KeyCode.C] = { overlay = "QuickChat", button = chat },
	}
	UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		local shortcut = SHORTCUTS[input.KeyCode]
		if not shortcut or UserInputService:GetFocusedTextBox() then
			return
		end
		if frame.Visible and shortcut.button.Visible then
			ctx.toggleOverlay(shortcut.overlay)
		end
	end)

	local canBomb = false
	local function placeBomb()
		if canBomb then
			ctx.placeBomb()
		end
	end
	bomb.Activated:Connect(placeBomb)
	InputController.onBombKey(placeBomb) -- Espace : raccourci facultatif

	-- Commandes tactiles (mobile / tablette) : joystick ou croix. Sur appareil tactile, les statistiques passent en haut
	-- à gauche pour laisser le coin bas aux commandes ; « inverser » met les commandes à droite et BOMBE à gauche.
	local touchControls = TouchControls.new(frame)
	local function applyStatsSide()
		if TouchControls.isTouchDevice() then
			stats.AnchorPoint = Vector2.new(0, 0)
			-- Sous la barre Roblox (logo, menu, chat, micro) qui occupe le coin haut gauche sur mobile.
			stats.Position = UDim2.fromOffset(16, 120)
		else
			stats.AnchorPoint = Vector2.new(0, 1)
			stats.Position = UDim2.new(0, 16, 1, -16)
		end
	end
	applyStatsSide()

	local function applyBombSize()
		local px = SettingsStore.bombButtonPixels()
		bomb.Size = UDim2.fromOffset(px, px)
	end
	local function applyBombSide()
		local flipped = TouchControls.isTouchDevice() and SettingsStore.get("flipControls") == true
		bomb.AnchorPoint = Vector2.new(if flipped then 0 else 1, 1)
		bomb.Position = UDim2.new(if flipped then 0 else 1, if flipped then 24 else -24, 1, -24)
	end
	applyBombSize()
	applyBombSide()
	TouchControls.onDeviceChanged(function()
		applyStatsSide()
		applyBombSide()
		touchControls.setActive(canBomb)
	end)
	SettingsStore.Changed:Connect(function(key: string)
		if key == "bombButtonSize" then
			applyBombSize()
		elseif key == "flipControls" then
			applyBombSide()
		end
	end)

	local lastSnapshot: any = nil
	local function renderTime(remaining: number?)
		local snapshot = lastSnapshot
		if not snapshot or remaining == nil then
			timer.Text = ""
			countdown.Text = ""
			return
		end
		if snapshot.state == "COUNTDOWN" then
			timer.Text = ""
			countdown.Text = tostring(math.max(0, math.ceil(remaining)))
		else
			-- Le minuteur peut être masqué par le joueur (Réglages) ; le compte à rebours de départ, jamais.
			timer.Text = if SettingsStore.get("showTimer") then formatTime(remaining) else ""
			countdown.Text = ""
		end
	end

	return {
		frame = frame,
		setProfile = setBombSkin,
		setStats = function(value: any)
			if typeof(value) ~= "table" then
				return
			end
			statLabels.bombs.Text = ("Bombes : %d"):format(value.bombCapacity)
			statLabels.range.Text = ("Portée : %d"):format(value.blastRange)
			statLabels.speed.Text = ("Vitesse : +%d"):format(value.speedPickups)
			statLabels.shield.Text = ("Bouclier : %s"):format(if value.hasShield then "oui" else "non")
		end,
		update = function(snapshot: any, me: any)
			lastSnapshot = snapshot
			local state: string = snapshot.state
			local participant = me ~= nil and me.participant == true
			local alive = me ~= nil and me.alive == true
			local playing = state == "PLAYING" and participant and alive
			canBomb = playing

			bomb.Visible = playing
			touchControls.setActive(playing)
			-- Émotes et chat : tant qu'on a un personnage dans la manche (pas pour un spectateur sans personnage).
			local hasCharacter = participant and (state == "COUNTDOWN" or alive)
			emotes.Visible = hasCharacter
			chat.Visible = hasCharacter
			stats.Visible = participant and (state == "PLAYING" or state == "COUNTDOWN")
			survivors.Text = if state == "PLAYING" then ("Survivants : %d"):format(snapshot.survivors) else ""

			-- Pendant le compte à rebours, les participants ne sont pas encore « en vie » côté serveur : pas spectateurs.
			local spectating = not participant or (state == "PLAYING" and not alive)
			banner.Visible = spectating
			leave.Visible = spectating
			if spectating then
				banner.Text = if participant
					then ("Éliminé — spectateur (%d survivant(s))"):format(snapshot.survivors)
					else "Manche en cours — tu rejoindras la suivante"
			end
		end,
		tick = renderTime,
	}
end

return GameHUD
