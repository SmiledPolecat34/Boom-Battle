--!strict
-- Bots du mode solo : création des acteurs et de leurs personnages, boucle de décision (BotBrain), animations.
-- Un bot agit par les MÊMES services qu'un joueur (MovementService.requestMove, BombService.placeBomb) : il subit les
-- mêmes règles (cases franchissables, capacité de bombes, dégâts, bonus). Aucun avantage, aucune triche.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActorRegistry = require(script.Parent.ActorRegistry)
local BombService = require(script.Parent.BombService)
local BotActor = require(script.Parent.BotActor)
local BotBrain = require(script.Parent.BotBrain)
local DamageService = require(script.Parent.DamageService)
local MapService = require(script.Parent.MapService)
local MovementService = require(script.Parent.MovementService)
local PlayState = require(script.Parent.PlayState)
local PowerupService = require(script.Parent.PowerupService)

local DECISION_INTERVAL = 0.3 -- secondes entre deux décisions d'un bot
local REISSUE_INTERVAL = 1.2 -- on ne relance un déplacement vers la même cible qu'après ce délai
local BOT_FOLDER_NAME = "Bots"
-- Animations par défaut de Roblox (script Animate des personnages R15), lues dans ce jeu : repos et marche.
local IDLE_ANIMATION = "rbxassetid://17172918855"
local WALK_ANIMATION = "rbxassetid://913402848"

-- Couleurs de peau des bots (distinctes pour les reconnaître d'un coup d'œil).
local BOT_COLORS = {
	Color3.fromRGB(231, 76, 60),
	Color3.fromRGB(46, 204, 113),
	Color3.fromRGB(241, 196, 15),
	Color3.fromRGB(155, 89, 182),
}

local BotService = {}

local generation = 0 -- invalide les boucles d'une manche précédente

local function botFolder(): Folder
	local folder = workspace:FindFirstChild(BOT_FOLDER_NAME)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = BOT_FOLDER_NAME
		created.Parent = workspace
		folder = created
	end
	return folder :: Folder
end

-- Crée `count` bots (acteurs, sans personnage). Ils sont enregistrés pour les dégâts et les bonus.
function BotService.createBots(count: number, difficulties: { number }?): { any }
	local created: { any } = {}
	for index = 1, count do
		local bot = BotActor.new(index, if difficulties then difficulties[index] else nil)
		ActorRegistry.addBot(bot)
		table.insert(created, bot)
	end
	return created
end

-- Construit le personnage d'un bot (modèle R15 coloré) dans Workspace.Bots. Bloquant (création du modèle).
function BotService.buildCharacter(bot: any, colorIndex: number): Model?
	local description = Instance.new("HumanoidDescription")
	local color = BOT_COLORS[(colorIndex - 1) % #BOT_COLORS + 1]
	description.HeadColor = color
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = color
	description.RightLegColor = color
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		warn("[BotService] Création du personnage du bot impossible : " .. tostring(model))
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = bot.DisplayName
	end
	model.Name = bot.DisplayName
	model.Parent = botFolder()
	bot.Character = model
	return model
end

-- Animations : marche pendant les déplacements, repos sinon. Un échec de chargement n'a aucune autre conséquence.
local function attachAnimations(bot: any, token: number)
	local model = bot.Character :: Model?
	local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local function load(id: string): AnimationTrack?
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		return if ok then track else nil
	end
	local idle = load(IDLE_ANIMATION)
	local walk = load(WALK_ANIMATION)
	if idle then
		idle.Looped = true
		idle:Play()
	end
	if walk then
		walk.Looped = true
		humanoid.Running:Connect(function(speed: number)
			if generation ~= token then
				return
			end
			if speed > 0.5 then
				if not walk.IsPlaying then
					walk:Play(0.15)
				end
			elseif walk.IsPlaying then
				walk:Stop(0.15)
			end
		end)
	end
end

local function enemiesOf(bot: any, info: MapService.MapInfo): { any }
	local cells = {}
	for _, actor in ActorRegistry.all() do
		if actor ~= bot and DamageService.isAlive(actor) then
			local character = actor.Character :: Model?
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				local cell = info.grid:worldToCell(root.Position)
				if cell then
					table.insert(cells, cell)
				end
			end
		end
	end
	return cells
end

local function think(bot: any, rng: Random, memory: { target: string?, issuedAt: number })
	if not PlayState.canMove(bot) or not DamageService.isAlive(bot) then
		return
	end
	local info = MapService.getCurrent()
	local character = bot.Character :: Model?
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not info or not root or not root:IsA("BasePart") then
		return
	end
	local cell = info.grid:worldToCell(root.Position)
	if not cell then
		return
	end

	local stats = PowerupService.getStats(bot)
	local action = BotBrain.decide(info.grid, {
		cell = cell,
		range = stats.blastRange,
		canPlaceBomb = BombService.canPlaceBomb(bot),
		danger = BombService.getDangerKeys(info),
		enemies = enemiesOf(bot, info),
		rng = rng,
		difficulty = bot.difficulty,
	})

	if action.kind == "bomb" then
		BombService.placeBomb(bot)
	elseif action.kind == "move" and action.cell then
		local targetKey = ("%d,%d"):format(action.cell.x, action.cell.y)
		local now = os.clock()
		if memory.target ~= targetKey or now - memory.issuedAt >= REISSUE_INTERVAL then
			if MovementService.requestMove(bot, action.cell.x, action.cell.y, nil) then
				memory.target = targetKey
				memory.issuedAt = now
			end
		end
	end
end

-- Démarre la boucle de décision de chaque bot (à appeler au début de la manche).
function BotService.startAI(bots: { any })
	generation += 1
	local token = generation
	for index, bot in bots do
		attachAnimations(bot, token)
		local rng = Random.new(os.clock() * 1000 + index * 7919)
		local memory = { target = nil :: string?, issuedAt = 0 }
		task.spawn(function()
			-- Décalage initial : les bots ne décident pas tous au même instant.
			task.wait(0.2 + index * 0.1)
			while generation == token do
				local ok, err = pcall(think, bot, rng, memory)
				if not ok then
					warn("[BotService] Erreur de décision : " .. tostring(err))
				end
				task.wait(BotBrain.profile(bot.difficulty or 5).interval)
			end
		end)
	end
end

-- Arrête les bots, détruit leurs personnages et les retire du registre (fin de manche, retour au lobby).
function BotService.clear()
	generation += 1 -- stoppe toutes les boucles
	for _, bot in ActorRegistry.getBots() do
		MovementService.forget(bot)
		PowerupService.forget(bot)
		local character = bot.Character :: Model?
		if character then
			character:Destroy()
		end
		bot.Character = nil
	end
	ActorRegistry.clearBots()
	local folder = workspace:FindFirstChild(BOT_FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

return BotService
