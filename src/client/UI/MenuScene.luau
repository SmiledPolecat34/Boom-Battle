--!strict
-- Décor 3D du menu principal : mur de briques, plateforme, podiums, caisses, bombes, et les personnages Roblox des
-- joueurs sur les podiums (le joueur local au centre, les autres joueurs inscrits sur les côtés).
--
-- Tout est LOCAL au client (Parts créées par le client, jamais répliquées) et placé loin au-dessus de l'arène, qui
-- n'en est donc jamais gênée. Rien n'est importé : décor en primitives Roblox, personnages créés à partir des
-- identifiants Roblox des joueurs. Les animations de repos et de salut sont celles du script Animate par défaut.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Components = require(script.Parent.Components)

local MenuScene = {}
MenuScene.__index = MenuScene

local ORIGIN = Vector3.new(0, 600, 0)
local SLOT_X = { 0, -9, 9 } -- 1 : centre (joueur local) ; 2 : gauche ; 3 : droite
local PODIUM_TOP = 1.4
local ROOT_HEIGHT = 3 -- hauteur de HumanoidRootPart au-dessus de ses pieds (R15)
local IDLE_ANIMATION = "rbxassetid://17172918855"
local WAVE_ANIMATION = "rbxassetid://507770239"
local WAVE_INTERVAL = 6
local SWAY_DEGREES = 9
local SWAY_SPEED = 0.9

-- Cadrage de la maquette : le personnage occupe environ 30 % de la hauteur (pieds vers 70 %, tête vers 42 %).
MenuScene.CameraCFrame = CFrame.lookAt(ORIGIN + Vector3.new(0, 8.2, -21), ORIGIN + Vector3.new(0, 5.4, 0))
MenuScene.FieldOfView = 50

type Actor = {
	userId: number,
	slot: number,
	isLocal: boolean,
	phase: number,
	destroyed: boolean,
	model: Model?,
	root: BasePart?,
	bomb: BasePart?,
	idle: AnimationTrack?,
	wave: AnimationTrack?,
	gui: BillboardGui?,
	status: TextLabel?,
	lastWave: number,
	animator: Animator?,
	emoteTracks: { [string]: AnimationTrack },
	emote: AnimationTrack?,
	emoteToken: number,
}

local function part(parent: Instance, name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Position = ORIGIN + offset
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function crate(parent: Instance, x: number, z: number, size: number)
	part(parent, "Crate", Vector3.new(size, size, size), Vector3.new(x, size / 2, z), Color3.fromRGB(205, 140, 62), Enum.Material.WoodPlanks)
	part(parent, "CrateLid", Vector3.new(size * 0.8, 0.3, size * 0.8), Vector3.new(x, size + 0.15, z), Color3.fromRGB(232, 170, 86), Enum.Material.WoodPlanks)
end

local function groundBomb(parent: Instance, x: number, z: number)
	part(parent, "Bomb", Vector3.new(2.2, 2.2, 2.2), Vector3.new(x, 1.1, z), Color3.fromRGB(35, 35, 45), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	part(parent, "Fuse", Vector3.new(0.4, 0.4, 0.4), Vector3.new(x, 2.5, z), Color3.fromRGB(255, 150, 30), Enum.Material.Neon, Enum.PartType.Ball)
end

function MenuScene.new()
	local self = setmetatable({}, MenuScene)
	self.actors = {} :: { [number]: Actor }
	self.visible = false
	self.connection = nil :: RBXScriptConnection?
	self.bombColor = Color3.fromRGB(35, 35, 45)

	local folder = Instance.new("Folder")
	folder.Name = "MenuScene"
	self.folder = folder

	-- Sol et plateforme.
	part(folder, "Floor", Vector3.new(140, 1, 90), Vector3.new(0, -0.5, 6), Color3.fromRGB(124, 128, 138), Enum.Material.Concrete)
	part(folder, "Platform", Vector3.new(40, 0.6, 16), Vector3.new(0, 0.3, 0), Color3.fromRGB(78, 82, 94), Enum.Material.DiamondPlate)
	for i = 0, 19 do
		local color = if i % 2 == 0 then Color3.fromRGB(240, 200, 40) else Color3.fromRGB(34, 34, 40)
		part(folder, "Hazard", Vector3.new(2, 0.7, 1), Vector3.new(-19 + i * 2, 0.35, -8.3), color, Enum.Material.SmoothPlastic)
		part(folder, "Hazard", Vector3.new(2, 0.7, 1), Vector3.new(-19 + i * 2, 0.35, 8.3), color, Enum.Material.SmoothPlastic)
	end

	-- Podiums (cylindres verticaux) avec leur anneau doré. Les podiums sont mémorisés : les marqueurs « + »
	-- d'invitation s'y accrochent.
	self.podiums = {} :: { [number]: BasePart }
	self.plusGuis = {} :: { [number]: BillboardGui }
	self.inviteOpen = {} :: { [number]: boolean }
	self.onInvite = nil :: (() -> ())?
	for slotIndex, x in SLOT_X do
		local podium = part(folder, "Podium", Vector3.new(0.8, 7, 7), Vector3.new(x, 1, 0), Color3.fromRGB(112, 116, 128), Enum.Material.Metal, Enum.PartType.Cylinder)
		podium.CFrame = CFrame.new(ORIGIN + Vector3.new(x, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		self.podiums[slotIndex] = podium
		local ring = part(folder, "PodiumRing", Vector3.new(0.1, 7.7, 7.7), Vector3.new(x, 0.95, 0), Color3.fromRGB(255, 200, 60), Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.CFrame = CFrame.new(ORIGIN + Vector3.new(x, 0.95, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	end

	-- Mur de briques et couronnement de pierre.
	part(folder, "WallBack", Vector3.new(140, 26, 2), Vector3.new(0, 13, 16), Color3.fromRGB(178, 94, 62), Enum.Material.Brick)
	part(folder, "WallCap", Vector3.new(140, 1.6, 4), Vector3.new(0, 26.8, 16), Color3.fromRGB(128, 132, 142), Enum.Material.Concrete)
	part(folder, "Pillar", Vector3.new(4, 26, 4), Vector3.new(-18, 13, 15), Color3.fromRGB(128, 132, 142), Enum.Material.Concrete)

	-- Arbres derrière le mur.
	for _, x in { -30, -8, 26 } do
		part(folder, "TreeTrunk", Vector3.new(2.4, 14, 2.4), Vector3.new(x, 20, 24), Color3.fromRGB(110, 76, 46), Enum.Material.Wood)
		part(folder, "TreeLeaves", Vector3.new(15, 15, 15), Vector3.new(x, 31, 24), Color3.fromRGB(72, 150, 60), Enum.Material.Grass, Enum.PartType.Ball)
	end

	-- Caisses, conteneur, tonneau et bombes posées.
	crate(folder, -14, -3, 4)
	crate(folder, -16.5, -6.5, 3)
	crate(folder, 15, -2, 5)
	crate(folder, 12.5, -6.5, 3.4)
	crate(folder, 22, 4, 6)
	part(folder, "Container", Vector3.new(14, 6, 9), Vector3.new(-26, 3, 6), Color3.fromRGB(70, 150, 70), Enum.Material.Metal)
	local barrel = part(folder, "Barrel", Vector3.new(4, 3, 3), Vector3.new(19, 2, -5), Color3.fromRGB(150, 98, 50), Enum.Material.Wood, Enum.PartType.Cylinder)
	barrel.CFrame = CFrame.new(ORIGIN + Vector3.new(19, 2, -5)) * CFrame.Angles(0, 0, math.pi / 2)
	groundBomb(folder, -12, -9)
	groundBomb(folder, -10, -10.5)
	groundBomb(folder, 11, -10)

	folder.Parent = workspace
	return self
end

-- Acteurs ---------------------------------------------------------------------------------------------------

local function loadTrack(animator: Animator, id: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = looped
		track.Priority = priority
		return track
	end
	return nil
end

function MenuScene._buildActor(self, actor: Actor, name: string)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(actor.userId)
	end)
	if actor.destroyed then
		if ok and typeof(model) == "Instance" then
			model:Destroy()
		end
		return
	end
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return -- pas de personnage (identifiant invalide) : le podium reste vide, sans erreur visible
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	root.Anchored = true
	model.Name = "Actor_" .. actor.userId
	local home = ORIGIN + Vector3.new(SLOT_X[actor.slot], PODIUM_TOP + ROOT_HEIGHT, 0)
	root.CFrame = CFrame.new(home)
	model.Parent = self.folder
	actor.model, actor.root = model, root

	-- Bombe tenue en main : main gauche pour le joueur local (la droite fait le salut), droite pour les autres.
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		local hand = model:FindFirstChild(if actor.isLocal then "LeftHand" else "RightHand")
		if hand and hand:IsA("BasePart") then
			local bomb = Instance.new("Part")
			bomb.Name = "HeldBomb"
			bomb.Shape = Enum.PartType.Ball
			bomb.Size = Vector3.new(1.7, 1.7, 1.7)
			bomb.Color = if actor.isLocal then self.bombColor else Color3.fromRGB(35, 35, 45)
			bomb.Material = Enum.Material.SmoothPlastic
			bomb.CanCollide = false
			bomb.CanQuery = false
			bomb.CanTouch = false
			bomb.Massless = true
			bomb.CFrame = hand.CFrame * CFrame.new(0, -0.9, -0.2)
			bomb.Parent = model
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = bomb
			weld.Parent = bomb
			actor.bomb = bomb
		end

		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		actor.animator = animator
		actor.idle = loadTrack(animator, IDLE_ANIMATION, true, Enum.AnimationPriority.Idle)
		if actor.isLocal then
			actor.wave = loadTrack(animator, WAVE_ANIMATION, false, Enum.AnimationPriority.Action)
		end
		if actor.idle then
			actor.idle:Play()
			if not self.visible then
				actor.idle:AdjustSpeed(0)
			end
		end
	end

	-- Pseudonyme et statut au-dessus de la tête.
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Adornee = root
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(260, 64)
	gui.StudsOffset = Vector3.new(0, 3.9, 0)
	gui.Enabled = self.visible
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 36)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 30
	nameLabel.Text = name
	nameLabel.TextColor3 = if actor.isLocal then Color3.fromRGB(90, 200, 255) else Color3.fromRGB(255, 120, 100)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.Parent = gui
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(0, 34)
	status.Size = UDim2.new(1, 0, 0, 24)
	status.Font = Enum.Font.GothamBold
	status.TextSize = 20
	status.Text = ""
	status.TextColor3 = Color3.fromRGB(110, 230, 110)
	status.TextStrokeTransparency = 0
	status.Parent = gui
	gui.Parent = root
	actor.gui, actor.status = gui, status
end

function MenuScene._removeActor(self, userId: number)
	local actor = self.actors[userId]
	if actor then
		actor.destroyed = true
		if actor.model then
			actor.model:Destroy()
		end
		self.actors[userId] = nil
	end
end

function MenuScene._ensureActor(self, userId: number, name: string, slot: number, isLocal: boolean): Actor
	local existing = self.actors[userId]
	if existing and existing.slot == slot then
		return existing
	end
	if existing then
		self:_removeActor(userId)
	end
	local actor: Actor = {
		userId = userId, slot = slot, isLocal = isLocal, phase = slot * 1.7, destroyed = false,
		model = nil, root = nil, bomb = nil, idle = nil, wave = nil, gui = nil, status = nil, lastWave = os.clock(),
		animator = nil, emoteTracks = {}, emote = nil, emoteToken = 0,
	}
	self.actors[userId] = actor
	task.spawn(function()
		self:_buildActor(actor, name)
	end)
	return actor
end

-- Le joueur local occupe toujours le podium central.
function MenuScene.setLocalPlayer(self, userId: number, name: string)
	self:_ensureActor(userId, name, 1, true)
end

-- Marqueur « + » d'invitation sur un podium : cercle blanc translucide cliquable, posé au-dessus du podium vide.
-- C'est un BillboardGui dans PlayerGui adossé au podium : seul moyen qu'une interface 2D suive un objet 3D et reçoive
-- les clics.
function MenuScene._plusGui(self, slot: number): BillboardGui
	local existing = self.plusGuis[slot]
	if existing then
		return existing
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "InviteSlot" .. slot
	gui.Adornee = self.podiums[slot]
	gui.AlwaysOnTop = true
	gui.Active = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(120, 120)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0)
	gui.Enabled = false

	local button = Instance.new("TextButton")
	button.Name = "Plus"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromOffset(96, 96)
	button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	button.BackgroundTransparency = 0.82
	button.AutoButtonColor = false
	button.Text = "+"
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 72
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0.4
	button.Parent = gui
	Components.corner(button, 48)
	Components.stroke(button, Color3.new(1, 1, 1), 4)
	Components.addHover(button, { scale = 1.1 })
	button.Activated:Connect(function()
		if self.onInvite then
			self.onInvite()
		end
	end)

	local player = Players.LocalPlayer
	gui.Parent = player:WaitForChild("PlayerGui")
	self.plusGuis[slot] = gui
	return gui
end

-- slots : deux emplacements (voir PartySlots.compute), dans l'ordre des podiums latéraux (gauche puis droite).
-- Un emplacement « player » affiche le personnage et son statut ; un emplacement « invite » affiche le « + ».
function MenuScene.setParty(self, slots: { any }, onInvite: (() -> ())?)
	self.onInvite = onInvite
	local keep: { [number]: boolean } = {}
	for _, actor in self.actors do
		if actor.isLocal then
			keep[actor.userId] = true
		end
	end

	for index = 1, 2 do
		local slot = slots[index]
		local podiumSlot = index + 1
		local isInvite = slot == nil or slot.kind == "invite"
		self.inviteOpen[podiumSlot] = isInvite
		if isInvite then
			local gui = self:_plusGui(podiumSlot)
			gui.Enabled = self.visible
		else
			local gui = self.plusGuis[podiumSlot]
			if gui then
				gui.Enabled = false
			end
			local actor = self:_ensureActor(slot.userId, slot.name, podiumSlot, false)
			keep[slot.userId] = true
			if actor.status then
				actor.status.Text = slot.status or ""
				actor.status.TextColor3 = if slot.ready then Color3.fromRGB(110, 230, 110) else Color3.fromRGB(200, 205, 225)
			end
		end
	end

	for userId in table.clone(self.actors) do
		if not keep[userId] then
			self:_removeActor(userId)
		end
	end
end

-- Bulle de chat rapide au-dessus du personnage LOCAL du menu (aperçu : visible seulement par ce client ; en jeu
-- c'est le serveur qui affiche la bulle à tout le monde).
function MenuScene.showBubble(self, text: string, seconds: number)
	for _, actor in self.actors do
		if actor.isLocal and actor.root then
			local previous = actor.root:FindFirstChild("QuickChatBubble")
			if previous then
				previous:Destroy()
			end
			local gui = Instance.new("BillboardGui")
			gui.Name = "QuickChatBubble"
			gui.Adornee = actor.root
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			gui.Size = UDim2.fromOffset(250, 78)
			gui.StudsOffset = Vector3.new(0, 5.6, 0)
			local bubble = Instance.new("Frame")
			bubble.Size = UDim2.new(1, 0, 0, 62)
			bubble.BackgroundColor3 = Color3.new(1, 1, 1)
			bubble.BorderSizePixel = 0
			bubble.Parent = gui
			Components.corner(bubble, 16)
			Components.stroke(bubble, Color3.fromRGB(10, 10, 10), 4)
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, -20, 1, -10)
			label.Position = UDim2.fromOffset(10, 5)
			label.Font = Enum.Font.GothamBlack
			label.Text = text
			label.TextColor3 = Color3.fromRGB(10, 10, 10)
			label.TextScaled = true
			label.Parent = bubble
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 34
			limit.MinTextSize = 12
			limit.Parent = label
			gui.Enabled = self.visible
			gui.Parent = actor.root
			task.delay(seconds, function()
				if gui.Parent then
					gui:Destroy()
				end
			end)
		end
	end
end

-- Joue une émote sur le personnage LOCAL du menu (aperçu : ne concerne que ce client). emote : EmoteConfig.Emote.
function MenuScene.playEmote(self, emote: { id: string, animationId: string, looped: boolean }, maxLoopSeconds: number)
	for _, actor in self.actors do
		if actor.isLocal and actor.animator then
			if actor.emote then
				actor.emote:Stop(0.15)
				actor.emote = nil
			end
			local track = actor.emoteTracks[emote.id]
			if not track then
				local animation = Instance.new("Animation")
				animation.AnimationId = emote.animationId
				local ok, loaded = pcall(function()
					return (actor.animator :: Animator):LoadAnimation(animation)
				end)
				if not ok or not loaded then
					return
				end
				loaded.Priority = Enum.AnimationPriority.Action
				loaded.Looped = emote.looped
				actor.emoteTracks[emote.id] = loaded
				track = loaded
			end
			actor.emoteToken += 1
			local token = actor.emoteToken
			actor.emote = track
			actor.lastWave = os.clock() -- pas de salut automatique juste après
			track:Play(0.2)
			if emote.looped then
				task.delay(maxLoopSeconds, function()
					if actor.emoteToken == token and actor.emote == track then
						track:Stop(0.3)
						actor.emote = nil
					end
				end)
			end
		end
	end
end

-- Couleur de la bombe équipée par le joueur local (cosmétique : purement visuel).
function MenuScene.setLocalBombColor(self, color: Color3)
	self.bombColor = color
	for _, actor in self.actors do
		if actor.isLocal and actor.bomb then
			actor.bomb.Color = color
		end
	end
end

-- Affichage ---------------------------------------------------------------------------------------------------

function MenuScene._step(self)
	local now = os.clock()
	for _, actor in self.actors do
		local root = actor.root
		if root then
			local home = ORIGIN + Vector3.new(SLOT_X[actor.slot], PODIUM_TOP + ROOT_HEIGHT, 0)
			root.CFrame = CFrame.new(home) * CFrame.Angles(0, math.rad(math.sin(now * SWAY_SPEED + actor.phase) * SWAY_DEGREES), 0)
			local emoting = actor.emote ~= nil and actor.emote.IsPlaying
			if actor.wave and not emoting and now - actor.lastWave >= WAVE_INTERVAL then
				actor.lastWave = now
				actor.wave:Play(0.2)
			end
		end
	end
end

function MenuScene.setVisible(self, visible: boolean)
	if visible == self.visible then
		return
	end
	self.visible = visible
	for _, actor in self.actors do
		if actor.idle then
			actor.idle:AdjustSpeed(if visible then 1 else 0)
		end
		if actor.gui then
			actor.gui.Enabled = visible
		end
	end
	for slot, gui in self.plusGuis do
		gui.Enabled = visible and self.inviteOpen[slot] == true
	end
	if visible and not self.connection then
		self.connection = RunService.RenderStepped:Connect(function()
			self:_step()
		end)
	elseif not visible and self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

function MenuScene.destroy(self)
	self:setVisible(false)
	for userId in table.clone(self.actors) do
		self:_removeActor(userId)
	end
	for _, gui in self.plusGuis do
		gui:Destroy()
	end
	table.clear(self.plusGuis)
	self.folder:Destroy()
end

return MenuScene
