--!strict
-- HUD de manche : chronomètre, survivants, statistiques, bouton bombe, compte à rebours, mode spectateur.
-- Il reste en périphérie : rien ne couvre le centre de l'arène (cases de départ, trajectoires d'explosion).

local Components = require(script.Parent.Parent.Components)
local InputController = require(script.Parent.Parent.Parent.Controllers.InputController)
local SettingsStore = require(script.Parent.Parent.Parent.Controllers.SettingsStore)
local Theme = require(script.Parent.Parent.Theme)

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

	local canBomb = false
	local function placeBomb()
		if canBomb then
			ctx.placeBomb()
		end
	end
	bomb.Activated:Connect(placeBomb)
	InputController.onBombKey(placeBomb) -- Espace : raccourci facultatif

	local function applyBombSize()
		local px = SettingsStore.bombButtonPixels()
		bomb.Size = UDim2.fromOffset(px, px)
	end
	applyBombSize()
	SettingsStore.Changed:Connect(function(key: string)
		if key == "bombButtonSize" then
			applyBombSize()
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
