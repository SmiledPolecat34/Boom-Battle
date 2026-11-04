--!strict
-- Menu principal, disposition de la maquette : logo en haut, solde + aide + réglages en haut à droite,
-- BOUTIQUE / INVENTAIRE à gauche, cartes ÉVÉNEMENTS / QUÊTES à droite, grand bouton PLAY en bas à droite.
-- Le fond est une scène 3D (MenuScene) avec le personnage Roblox du joueur au centre, sur son podium.
-- Rien n'est affiché qui n'existe pas : pas de bouton « + inviter », pas d'événement ou de saison inventés.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(script.Parent.Parent.AssetIds)
local CameraController = require(script.Parent.Parent.Parent.Controllers.CameraController)
local Components = require(script.Parent.Parent.Components)
local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local EventConfig = require(ReplicatedStorage.Shared.EventConfig)
local EmoteConfig = require(ReplicatedStorage.Shared.EmoteConfig)
local MenuScene = require(script.Parent.Parent.MenuScene)
local PartySlots = require(script.Parent.Parent.PartySlots)
local QuickChatConfig = require(ReplicatedStorage.Shared.QuickChatConfig)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local Theme = require(script.Parent.Parent.Theme)

local MainMenu = {}

local function formatNumber(n: number): string
	local text = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (text:gsub("^ ", ""))
end

local function logoLabel(parent: Instance, name: string, text: string, color: Color3, y: number, size: number): TextLabel
	local label = Components.label(parent, name, text, size, color, Theme.fontTitle)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, y)
	label.Size = UDim2.new(0.6, 0, 0, size + 8)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(88, 36, 10)
	return label
end

function MainMenu.new(parent: Instance, ctx: any)
	-- Écran transparent : le décor 3D est le fond. Il n'absorbe PAS les clics : sinon il passerait au-dessus des « + »
	-- d'invitation du décor et les rendrait incliquables. Aucun déplacement n'est possible derrière le menu, car
	-- MovementController ignore les clics tant que la caméra du menu est active.
	local frame = Components.screen(parent, "MainMenu", false)
	frame.BackgroundTransparency = 1

	local scene = MenuScene.new()
	local localPlayer = Players.LocalPlayer
	scene:setLocalPlayer(localPlayer.UserId, localPlayer.DisplayName)

	-- Logo ------------------------------------------------------------------------------------------------------
	if AssetIds.Logo then
		local logo = Instance.new("ImageLabel")
		logo.Name = "Logo"
		logo.AnchorPoint = Vector2.new(0.5, 0)
		logo.Position = UDim2.new(0.5, 0, 0, 0)
		logo.Size = UDim2.fromOffset(460, math.floor(460 / AssetIds.LogoAspectRatio))
		logo.BackgroundTransparency = 1
		logo.Image = AssetIds.Logo
		logo.ScaleType = Enum.ScaleType.Fit
		logo.Parent = frame
	else
		-- Rendu de secours tant que l'image du logo n'est pas importée (assets/ui/LISEZMOI.md).
		logoLabel(frame, "LogoTop", "BOM", Color3.fromRGB(255, 142, 32), 6, 96)
		logoLabel(frame, "LogoBottom", "BATTLE", Color3.fromRGB(255, 214, 64), 92, 84)
	end

	-- Haut droite : solde, aide, réglages ----------------------------------------------------------------------
	local coinsPill = Instance.new("Frame")
	coinsPill.Name = "CoinsPill"
	coinsPill.AnchorPoint = Vector2.new(1, 0)
	coinsPill.Position = UDim2.new(1, if AssetIds.HelpIcon and AssetIds.SettingsIcon then -184 else -250, 0, 20)
	coinsPill.Size = UDim2.fromOffset(200, 50)
	coinsPill.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
	coinsPill.BackgroundTransparency = 0.1
	coinsPill.Parent = frame
	Components.corner(coinsPill, 25)
	Components.stroke(coinsPill, Theme.yellow, 2)
	local coinIcon = Instance.new("Frame")
	coinIcon.Position = UDim2.fromOffset(6, 5)
	coinIcon.Size = UDim2.fromOffset(40, 40)
	coinIcon.BackgroundColor3 = Theme.yellow
	coinIcon.Parent = coinsPill
	Components.corner(coinIcon, 20)
	Components.stroke(coinIcon, Color3.fromRGB(190, 130, 20), 3)
	local coinMark = Components.label(coinIcon, "Mark", "C", 24, Color3.fromRGB(150, 90, 10), Theme.fontTitle)
	coinMark.Size = UDim2.fromScale(1, 1)
	local coins = Components.label(coinsPill, "Coins", "...", 26, Theme.white, Theme.fontTitle)
	coins.Position = UDim2.fromOffset(52, 0)
	coins.Size = UDim2.new(1, -60, 1, 0)
	coins.TextXAlignment = Enum.TextXAlignment.Left

	-- Boutons d'aide et de réglages : image importée si disponible, sinon texte (rendu de secours).
	local help: GuiButton
	if AssetIds.HelpIcon then
		local image = Instance.new("ImageButton")
		image.Name = "HelpButton"
		image.Size = UDim2.fromOffset(68, 68)
		image.BackgroundTransparency = 1
		image.Image = AssetIds.HelpIcon
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = frame
		Components.addHover(image, { scale = 1.12, glow = false })
		help = image
	else
		local text = Components.button(frame, "HelpButton", "?", Color3.fromRGB(48, 120, 230), UDim2.fromOffset(56, 56))
		text.TextSize = 34
		help = text
	end
	help.AnchorPoint = Vector2.new(1, 0)
	help.Position = UDim2.new(1, if AssetIds.SettingsIcon then -100 else -182, 0, 12)
	help.Activated:Connect(function()
		ctx.openOverlay("Help")
	end)

	local settings: GuiButton
	if AssetIds.SettingsIcon then
		local image = Instance.new("ImageButton")
		image.Name = "SettingsButton"
		image.Size = UDim2.fromOffset(68, 68)
		image.BackgroundTransparency = 1
		image.Image = AssetIds.SettingsIcon
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = frame
		Components.addHover(image, { scale = 1.12, glow = false })
		settings = image
	else
		local text = Components.button(frame, "SettingsButton", "RÉGLAGES", Color3.fromRGB(64, 72, 98), UDim2.fromOffset(150, 56))
		text.TextSize = 20
		settings = text
	end
	settings.AnchorPoint = Vector2.new(1, 0)
	settings.Position = UDim2.new(1, -24, 0, if AssetIds.SettingsIcon then 12 else 17)
	settings.Activated:Connect(function()
		ctx.openOverlay("Settings")
	end)

	local saveNotice = Components.label(frame, "SaveNotice", "", 16, Theme.red, Theme.fontBold)
	saveNotice.AnchorPoint = Vector2.new(1, 0)
	saveNotice.Position = UDim2.new(1, -24, 0, 80)
	saveNotice.Size = UDim2.fromOffset(420, 22)
	saveNotice.TextXAlignment = Enum.TextXAlignment.Right
	saveNotice.TextStrokeTransparency = 0.4

	-- Gauche : boutique et inventaire ---------------------------------------------------------------------------
	local shop = Components.button(frame, "ShopButton", "BOUTIQUE", Color3.fromRGB(255, 150, 30), UDim2.fromOffset(310, 76))
	shop.AnchorPoint = Vector2.new(0, 0.5)
	shop.Position = UDim2.new(0, 24, 0.5, -6)
	shop.TextSize = 38
	shop.Activated:Connect(function()
		ctx.openOverlay("Shop")
	end)
	local inventory = Components.button(frame, "InventoryButton", "INVENTAIRE", Color3.fromRGB(140, 92, 58), UDim2.fromOffset(310, 66))
	inventory.AnchorPoint = Vector2.new(0, 0.5)
	inventory.Position = UDim2.new(0, 24, 0.5, 78)
	inventory.TextSize = 32
	inventory.Activated:Connect(function()
		ctx.openOverlay("Inventory")
	end)
	-- Émotes et chat rapide : deux boutons côte à côte sous l'inventaire.
	local emotes = Components.button(frame, "EmotesButton", "ÉMOTES", Theme.violet, UDim2.fromOffset(150, 58))
	emotes.AnchorPoint = Vector2.new(0, 0.5)
	emotes.Position = UDim2.new(0, 24, 0.5, 156)
	emotes.TextSize = 22
	emotes.Activated:Connect(function()
		ctx.openOverlay("Emotes")
	end)
	local chat = Components.bubbleButton(frame, "ChatButton", "CHAT", UDim2.fromOffset(150, 58))
	chat.AnchorPoint = Vector2.new(0, 0.5)
	chat.Position = UDim2.new(0, 184, 0.5, 156)
	chat.Activated:Connect(function()
		ctx.openOverlay("QuickChat")
	end)

	-- Droite : cartes événements et quêtes ----------------------------------------------------------------------
	local eventsCard = Instance.new("TextButton")
	eventsCard.Name = "EventsButton"
	eventsCard.AnchorPoint = Vector2.new(1, 0)
	eventsCard.Position = UDim2.new(1, -24, 0.5, -190)
	eventsCard.Size = UDim2.fromOffset(300, 150)
	eventsCard.BackgroundColor3 = Color3.fromRGB(122, 52, 30)
	eventsCard.AutoButtonColor = true
	eventsCard.Text = ""
	eventsCard.Parent = frame
	Components.corner(eventsCard, 14)
	Components.stroke(eventsCard, Color3.fromRGB(255, 160, 50), 3)
	eventsCard.AutoButtonColor = false
	Components.addHover(eventsCard, { scale = 1.04 })
	local eventsTitle = Components.label(eventsCard, "Title", "ÉVÉNEMENTS", 32, Theme.white, Theme.fontTitle)
	eventsTitle.Position = UDim2.fromOffset(0, 12)
	eventsTitle.TextStrokeTransparency = 0
	local activeEvents = 0
	local now = os.time()
	local firstName = ""
	for _, event in EventConfig.Events do
		if (event.startsAt == nil or now >= event.startsAt) and (event.endsAt == nil or now <= event.endsAt) then
			activeEvents += 1
			if firstName == "" then
				firstName = event.name
			end
		end
	end
	local eventsBody = Components.label(
		eventsCard,
		"Body",
		if activeEvents > 0 then firstName else "Aucun événement\nen cours",
		22,
		Color3.fromRGB(255, 226, 160),
		Theme.fontBold
	)
	eventsBody.Position = UDim2.fromOffset(0, 66)
	eventsBody.Size = UDim2.new(1, 0, 0, 64)
	eventsCard.Activated:Connect(function()
		ctx.openOverlay("Events")
	end)

	local questsCard = Instance.new("TextButton")
	questsCard.Name = "QuestsButton"
	questsCard.AnchorPoint = Vector2.new(1, 0)
	questsCard.Position = UDim2.new(1, -24, 0.5, -24)
	questsCard.Size = UDim2.fromOffset(300, 96)
	questsCard.BackgroundColor3 = Color3.fromRGB(58, 64, 94)
	questsCard.AutoButtonColor = true
	questsCard.Text = ""
	questsCard.Parent = frame
	Components.corner(questsCard, 14)
	Components.stroke(questsCard, Color3.fromRGB(150, 160, 205), 3)
	questsCard.AutoButtonColor = false
	Components.addHover(questsCard, { scale = 1.04 })
	-- Icône de quêtes à gauche (si importée) ; le titre et la barre se décalent pour lui laisser la place.
	local contentLeft = 18
	if AssetIds.QuestsIcon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "QuestsIcon"
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 10, 0.5, 0)
		icon.Size = UDim2.fromOffset(66, 70)
		icon.BackgroundTransparency = 1
		icon.Image = AssetIds.QuestsIcon
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = questsCard
		contentLeft = 86
	end
	local questsTitle = Components.label(questsCard, "Title", "QUÊTES", 30, Theme.white, Theme.fontTitle)
	questsTitle.Position = UDim2.fromOffset(contentLeft - 18, 8)
	questsTitle.Size = UDim2.new(1, -(contentLeft - 18), 0, 38)
	questsTitle.TextStrokeTransparency = 0
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.new(0, contentLeft, 1, -34)
	barBack.Size = UDim2.new(1, -(contentLeft + 72), 0, 16)
	barBack.BackgroundColor3 = Color3.fromRGB(30, 32, 48)
	barBack.Parent = questsCard
	Components.corner(barBack, 8)
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Theme.yellow
	barFill.Parent = barBack
	Components.corner(barFill, 8)
	local questsCount = Components.label(questsCard, "Count", ("0/%d"):format(#QuestConfig.Quests), 20, Theme.white, Theme.fontBold)
	questsCount.AnchorPoint = Vector2.new(1, 1)
	questsCount.Position = UDim2.new(1, -14, 1, -28)
	questsCount.Size = UDim2.fromOffset(64, 26)
	questsCount.TextXAlignment = Enum.TextXAlignment.Right
	questsCard.Activated:Connect(function()
		ctx.openOverlay("Quests")
	end)

	-- Bas droite : PLAY ------------------------------------------------------------------------------------------
	local play: GuiButton
	if AssetIds.PlayButton then
		-- Image du bouton (inchangée : couleurs, proportions et icônes d'origine) + texte « PLAY » stylé au centre.
		local width = 470
		local image = Instance.new("ImageButton")
		image.Name = "PlayButton"
		image.AnchorPoint = Vector2.new(1, 1)
		image.Position = UDim2.new(1, -24, 1, -20)
		image.Size = UDim2.fromOffset(width, width / AssetIds.PlayButtonAspectRatio) -- proportions exactes de l'image
		image.BackgroundTransparency = 1
		image.Image = AssetIds.PlayButton
		image.ScaleType = Enum.ScaleType.Fit
		image.AutoButtonColor = false
		image.Parent = frame
		Components.arcadeText(image, "PlayText", "PLAY", AssetIds.PlayTextArea)
		Components.addHover(image, { scale = 1.05, glow = false })
		play = image
	else
		-- Rendu de secours tant que l'image du bouton n'est pas importée.
		local text = Components.button(frame, "PlayButton", "PLAY", Color3.fromRGB(76, 200, 60), UDim2.fromOffset(440, 112))
		text.AnchorPoint = Vector2.new(1, 1)
		text.Position = UDim2.new(1, -28, 1, -28)
		text.TextSize = 72
		text.TextStrokeTransparency = 0
		text.TextStrokeColor3 = Color3.fromRGB(40, 110, 30)
		play = text
	end
	-- SOLO : entraînement contre des bots, juste au-dessus de PLAY.
	local solo = Components.button(frame, "SoloButton", "SOLO (BOTS)", Color3.fromRGB(48, 120, 230), UDim2.fromOffset(250, 58))
	solo.AnchorPoint = Vector2.new(1, 1)
	solo.Position = UDim2.new(1, -24, 1, -190)
	solo.TextSize = 24
	solo.Activated:Connect(function()
		ctx.openOverlay("Solo")
	end)

	-- PARTIE PRIVÉE : crée un groupe (on en devient l'hôte) ou rejoint celui qui existe déjà sur le serveur.
	local privateButton = Components.button(frame, "PrivateButton", "PARTIE PRIVÉE", Theme.violet, UDim2.fromOffset(250, 58))
	privateButton.AnchorPoint = Vector2.new(1, 1)
	privateButton.Position = UDim2.new(1, -24, 1, -256)
	privateButton.TextSize = 24
	local partyExists = false
	privateButton.Activated:Connect(function()
		ctx.partyAction(if partyExists then "join" else "create")
	end)

	play.Activated:Connect(function()
		ctx.setQueued(true)
	end)

	-- Groupe : deux emplacements à côté du joueur (joueur présent ou « + » d'invitation) ----------------------------
	local friendCache: { [number]: boolean } = {}
	local lastSnapshot: any = nil
	local lastMe: any = nil
	local function refreshParty()
		local entries: { PartySlots.Entry } = {}
		if lastSnapshot then
			for _, entry in lastSnapshot.players do
				if lastMe == nil or entry.userId ~= lastMe.userId then
					table.insert(entries, {
						userId = entry.userId,
						name = entry.name,
						queued = entry.queued == true,
						ready = entry.ready == true,
						isFriend = friendCache[entry.userId] == true,
					})
					if friendCache[entry.userId] == nil then
						friendCache[entry.userId] = false -- une seule demande par joueur
						task.spawn(function()
							local ok, isFriend = pcall(function()
								return localPlayer:IsFriendsWith(entry.userId)
							end)
							if ok and isFriend then
								friendCache[entry.userId] = true
								refreshParty()
							end
						end)
					end
				end
			end
		end
		scene:setParty(PartySlots.compute(entries, PartySlots.MaxSlots), function()
			ctx.requestInvite()
		end)
	end
	refreshParty() -- avant le premier message du serveur : deux emplacements « + »

	-- Décor 3D : visible seulement avec ce menu -------------------------------------------------------------------
	local function syncVisibility()
		if frame.Visible then
			scene:setVisible(true)
			CameraController.setOverride(MenuScene.CameraCFrame, MenuScene.FieldOfView)
		else
			scene:setVisible(false)
			CameraController.setOverride(nil)
		end
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(syncVisibility)

	return {
		frame = frame,
		setProfile = function(profile: any)
			coins.Text = formatNumber(profile.coins)
			saveNotice.Text = if profile.persisted then "" else "Sauvegarde indisponible : progression non enregistrée"

			local done = 0
			for _, quest in QuestConfig.Quests do
				local state = profile.quests[quest.id]
				if state and state.done then
					done += 1
				end
			end
			barFill.Size = UDim2.fromScale(done / math.max(#QuestConfig.Quests, 1), 1)
			questsCount.Text = ("%d/%d"):format(done, #QuestConfig.Quests)

			local equipped = CosmeticConfig.get(profile.equipped.bomb)
			if equipped then
				scene:setLocalBombColor(equipped.color)
			end
		end,
		-- Les autres joueurs du serveur occupent les deux podiums latéraux (amis d'abord) ; un emplacement libre
		-- affiche le « + » d'invitation.
		update = function(snapshot: any, me: any)
			lastSnapshot, lastMe = snapshot, me
			partyExists = snapshot.party ~= nil
			privateButton.Text = if snapshot.party
				then ("REJOINDRE (%d/%d)"):format(snapshot.party.count, snapshot.party.max)
				else "PARTIE PRIVÉE"
			refreshParty()
			syncVisibility()
		end,
		-- Aperçus locaux sur le personnage du menu (en jeu, c'est le serveur qui joue l'émote et affiche la bulle).
		previewEmote = function(emote: any)
			scene:playEmote(emote, EmoteConfig.MaxLoopSeconds)
		end,
		previewBubble = function(text: string)
			scene:showBubble(text, QuickChatConfig.BubbleSeconds)
		end,
		tick = function(_remaining: number?) end,
	}
end

return MainMenu
