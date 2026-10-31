--!strict
-- Gestionnaire d'écrans : construit l'interface, choisit l'écran à afficher d'après l'état annoncé par le serveur,
-- gère les fenêtres Aide / Réglages et adapte l'échelle à la taille de l'écran (PC, tablette, mobile).
--
-- Écrans : MainMenu, Lobby, GameHUD (joueur et spectateur), Results ; fenêtres : Settings, Help.
-- Aucune décision de jeu ici : tout vient du serveur (RoundController relaie les messages).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SettingsStore = require(script.Parent.SettingsStore)
local GameHUD = require(script.Parent.Parent.UI.Screens.GameHUD)
local CosmeticBrowser = require(script.Parent.Parent.UI.Screens.CosmeticBrowser)
local Events = require(script.Parent.Parent.UI.Screens.Events)
local Help = require(script.Parent.Parent.UI.Screens.Help)
local Quests = require(script.Parent.Parent.UI.Screens.Quests)
local Lobby = require(script.Parent.Parent.UI.Screens.Lobby)
local MainMenu = require(script.Parent.Parent.UI.Screens.MainMenu)
local Results = require(script.Parent.Parent.UI.Screens.Results)
local Settings = require(script.Parent.Parent.UI.Screens.Settings)

local UIController = {}

local DESIGN_WIDTH, DESIGN_HEIGHT = 1280, 720
local MIN_SCALE, MAX_SCALE = 0.55, 1.4

local localPlayer = Players.LocalPlayer
local gui: ScreenGui? = nil
local root: Frame? = nil
local uiScale: UIScale? = nil
local screens: { [string]: any } = {}
local overlays: { [string]: any } = {}
local openOverlay: string? = nil
local currentSnapshot: any = nil
local currentScreen: string? = nil
local currentProfile: any = nil
local forceTick = false
local connections: { RBXScriptConnection } = {}

local function findMe(snapshot: any): any
	for _, entry in snapshot.players do
		if entry.userId == localPlayer.UserId then
			return entry
		end
	end
	return nil
end

-- Quel écran principal afficher ? (pur : même entrée, même sortie)
local function selectScreen(snapshot: any, me: any): string
	local state: string = snapshot.state
	local queued = me ~= nil and me.queued == true
	local participant = me ~= nil and me.participant == true

	if state == "FINISHED" and (queued or participant) then
		return "Results"
	end
	if state == "COUNTDOWN" or state == "PLAYING" then
		if participant or queued then
			return "GameHUD" -- participant, ou spectateur déjà inscrit
		end
		return "MainMenu"
	end
	if queued then
		return "Lobby"
	end
	return "MainMenu"
end
UIController.selectScreen = selectScreen

local function applyScale()
	local frame, scale = root, uiScale
	if not frame or not scale then
		return
	end
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(DESIGN_WIDTH, DESIGN_HEIGHT)
	local fit = math.min(viewport.X / DESIGN_WIDTH, viewport.Y / DESIGN_HEIGHT)
	local value = math.clamp(fit * SettingsStore.uiScaleMultiplier(), MIN_SCALE, MAX_SCALE)
	scale.Scale = value
	-- Le cadre racine est agrandi de 1/échelle pour continuer à remplir tout l'écran.
	frame.Size = UDim2.fromScale(1 / value, 1 / value)
end

local function remaining(): number?
	local snapshot = currentSnapshot
	if snapshot and typeof(snapshot.endsAt) == "number" then
		return snapshot.endsAt - workspace:GetServerTimeNow()
	end
	return nil
end

local function closeOverlay()
	if openOverlay then
		overlays[openOverlay].frame.Visible = false
		openOverlay = nil
	end
end

local function showOverlay(name: string)
	closeOverlay()
	if overlays[name] then
		overlays[name].frame.Visible = true
		openOverlay = name
	end
end

local function render()
	local snapshot = currentSnapshot
	if not snapshot then
		return
	end
	local me = findMe(snapshot)
	local target = selectScreen(snapshot, me)
	if target ~= currentScreen then
		currentScreen = target
		-- Les fenêtres Aide / Réglages ne sont accessibles que depuis le menu et le lobby.
		if target ~= "MainMenu" and target ~= "Lobby" then
			closeOverlay()
		end
	end
	for name, screen in screens do
		screen.frame.Visible = name == target
		if name == target then
			screen.update(snapshot, me)
		end
	end
end

-- Relais -----------------------------------------------------------------------------------------------------

function UIController.onSnapshot(snapshot: any)
	currentSnapshot = snapshot
	forceTick = true -- le prochain affichage des textes tient compte du nouvel état
	render()
end

function UIController.onRoundEnded(payload: any)
	if screens.Results then
		screens.Results.setResult(payload)
	end
end

-- Profil public envoyé par le serveur (solde, possessions, équipement, quêtes). Lecture seule côté client.
function UIController.onProfile(profile: any)
	currentProfile = profile
	if screens.MainMenu then
		screens.MainMenu.setProfile(profile)
	end
	for _, overlay in overlays do
		if overlay.setProfile then
			overlay.setProfile(profile)
		end
	end
end

function UIController.onShopResult(result: any)
	for _, overlay in overlays do
		if overlay.onShopResult then
			overlay.onShopResult(result)
		end
	end
end

function UIController.onStats(stats: any)
	if screens.GameHUD then
		screens.GameHUD.setStats(stats)
	end
end

function UIController.getCurrentScreen(): string?
	return currentScreen
end

function UIController.start(remotes: Folder)
	if gui then
		return -- l'interface est créée une seule fois, même si l'arène est régénérée
	end

	local setQueued = remotes:WaitForChild("SetQueued") :: RemoteEvent
	local setReady = remotes:WaitForChild("SetReady") :: RemoteEvent
	local placeBomb = remotes:WaitForChild("RequestPlaceBomb") :: RemoteEvent
	local requestPurchase = remotes:WaitForChild("RequestPurchase") :: RemoteEvent
	local requestEquip = remotes:WaitForChild("RequestEquip") :: RemoteEvent

	local ctx = {
		purchase = function(id: string)
			requestPurchase:FireServer(id)
		end,
		equip = function(id: string)
			requestEquip:FireServer(id)
		end,
		localUserId = localPlayer.UserId,
		setQueued = function(value: boolean)
			setQueued:FireServer(value)
		end,
		setReady = function(value: boolean)
			setReady:FireServer(value)
		end,
		placeBomb = function()
			placeBomb:FireServer()
		end,
		openOverlay = showOverlay,
		closeOverlay = closeOverlay,
	}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BombBattleUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local rootFrame = Instance.new("Frame")
	rootFrame.Name = "Root"
	rootFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	rootFrame.Position = UDim2.fromScale(0.5, 0.5)
	rootFrame.BackgroundTransparency = 1
	rootFrame.BorderSizePixel = 0
	rootFrame.Parent = screenGui
	local scale = Instance.new("UIScale")
	scale.Parent = rootFrame
	root, uiScale = rootFrame, scale

	screens.MainMenu = MainMenu.new(rootFrame, ctx)
	screens.Lobby = Lobby.new(rootFrame, ctx)
	screens.GameHUD = GameHUD.new(rootFrame, ctx)
	screens.Results = Results.new(rootFrame, ctx)
	overlays.Settings = Settings.new(rootFrame, ctx)
	overlays.Help = Help.new(rootFrame, ctx)
	overlays.Shop = CosmeticBrowser.new(rootFrame, ctx, "shop")
	overlays.Inventory = CosmeticBrowser.new(rootFrame, ctx, "inventory")
	overlays.Quests = Quests.new(rootFrame, ctx)
	overlays.Events = Events.new(rootFrame, ctx)
	-- Les fenêtres passent au-dessus des écrans (frères sous Root, ZIndexBehavior = Sibling).
	for _, overlay in overlays do
		overlay.frame.ZIndex = 10
	end
	if currentProfile then
		UIController.onProfile(currentProfile) -- profil reçu avant la création de l'interface
	end

	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	applyScale()
	table.insert(connections, SettingsStore.Changed:Connect(applyScale))
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale))
	end

	-- Chronomètres : calculés localement à partir de l'heure serveur annoncée (aucun trafic réseau par seconde).
	-- Les textes ne changent qu'à la seconde : on ne les réécrit que lorsque la seconde affichée change (ou après un
	-- changement d'écran ou de réglage), au lieu de 60 fois par seconde.
	local lastSecond: number? = nil
	local lastTickedScreen: string? = nil
	table.insert(
		connections,
		SettingsStore.Changed:Connect(function()
			lastSecond = nil -- force un rafraîchissement (ex. minuteur masqué ou affiché)
		end)
	)
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			local screenName = currentScreen
			if not screenName or not screens[screenName] then
				return
			end
			local value = remaining()
			local second = if value then math.ceil(value) else -1
			if second ~= lastSecond or screenName ~= lastTickedScreen or forceTick then
				forceTick = false
				lastSecond, lastTickedScreen = second, screenName
				screens[screenName].tick(value)
			end
		end)
	)

	-- Avant le premier message du serveur : le menu principal (jamais un écran vide).
	currentScreen = "MainMenu"
	screens.MainMenu.frame.Visible = true
end

function UIController.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(screens)
	table.clear(overlays)
	openOverlay, currentScreen, currentSnapshot = nil, nil, nil
end

return UIController
