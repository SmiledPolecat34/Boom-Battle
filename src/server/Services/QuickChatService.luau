--!strict
-- Chat rapide : affiche une phrase PRÉFAITE du catalogue en bulle au-dessus de la tête du joueur. La bulle est créée
-- par le serveur (donc répliquée à tous). Le client n'envoie qu'un identifiant ; rien d'autre n'est jamais affiché.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local QuickChatConfig = require(ReplicatedStorage.Shared.QuickChatConfig)
local PlayState = require(script.Parent.PlayState)

local BUBBLE_NAME = "QuickChatBubble"

local QuickChatService = {}

local lastRequest: { [Player]: number } = {}

local function buildBubble(text: string): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = BUBBLE_NAME
	gui.AlwaysOnTop = true -- lisible depuis la caméra de dessus
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(250, 78)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 400

	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.Size = UDim2.new(1, 0, 0, 62)
	bubble.BackgroundColor3 = Color3.new(1, 1, 1)
	bubble.BorderSizePixel = 0
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(10, 10, 10)
	stroke.Thickness = 4
	stroke.Parent = bubble

	-- Pointe de la bulle, vers le personnage.
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, -2)
	tail.Size = UDim2.fromOffset(20, 20)
	tail.Rotation = 45
	tail.BackgroundColor3 = Color3.new(1, 1, 1)
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = bubble
	local tailStroke = Instance.new("UIStroke")
	tailStroke.Color = Color3.fromRGB(10, 10, 10)
	tailStroke.Thickness = 4
	tailStroke.Parent = tail

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -20, 1, -10)
	label.Position = UDim2.fromOffset(10, 5)
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = Color3.fromRGB(10, 10, 10)
	label.TextScaled = true
	label.ZIndex = 2
	label.Parent = bubble
	-- Garde la bulle lisible sans jamais dépasser sa taille.
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 34
	limit.MinTextSize = 12
	limit.Parent = label
	return gui
end

local function handle(player: Player, id: any)
	-- Identifiant connu du catalogue : le seul contenu qui peut être affiché.
	local phrase = QuickChatConfig.get(id)
	if not phrase then
		return
	end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < GameConfig.RemoteLimits.QuickChatMinInterval then
		return
	end
	lastRequest[player] = now
	if not PlayState.canEmote(player) then
		return
	end

	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not head or not head:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Une seule bulle par joueur : la nouvelle remplace l'ancienne.
	local previous = head:FindFirstChild(BUBBLE_NAME)
	if previous then
		previous:Destroy()
	end
	local gui = buildBubble(phrase.text)
	gui.Adornee = head
	gui.Parent = head
	Debris:AddItem(gui, QuickChatConfig.BubbleSeconds)
end

function QuickChatService.start(remotes: Folder)
	local request = remotes:WaitForChild("RequestQuickChat") :: RemoteEvent
	request.OnServerEvent:Connect(handle)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequest[player] = nil
	end)
end

return QuickChatService
