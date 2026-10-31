--!strict
-- Applique les dégâts d'explosion : le bouclier absorbe une explosion, sinon le joueur est éliminé.
-- L'état « vivant » est l'Attribut `Alive` du Player (true / false), posé uniquement par ce service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementService = require(script.Parent.MovementService)
local PowerupService = require(script.Parent.PowerupService)

local DamageService = {}

local eliminatedEvent = Instance.new("BindableEvent")
-- Signal pour le futur RoundService : se déclenche une seule fois par élimination, avec le Player concerné.
DamageService.Eliminated = eliminatedEvent.Event

-- Rappels directs : un BindableEvent COPIE les tables qu'on lui passe (un bot perdrait son identité). Les rappels
-- reçoivent l'acteur lui-même, joueur ou bot.
local listeners: { (actor: any) -> () } = {}
function DamageService.onEliminated(callback: (actor: any) -> ())
	table.insert(listeners, callback)
end

local playerEliminatedRemote: RemoteEvent? = nil

function DamageService.start(remotes: Folder)
	playerEliminatedRemote = remotes:WaitForChild("PlayerEliminated") :: RemoteEvent
end

function DamageService.setAlive(player: Player, alive: boolean)
	player:SetAttribute("Alive", alive)
end

function DamageService.isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return player:GetAttribute("Alive") == true and humanoid ~= nil and humanoid.Health > 0
end

-- Retourne true si le joueur est éliminé par ce coup, false s'il est protégé ou déjà éliminé.
function DamageService.hit(player: Player): boolean
	if not DamageService.isAlive(player) then
		return false
	end
	if PowerupService.consumeShield(player) then
		return false
	end

	DamageService.setAlive(player, false)
	MovementService.cancel(player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.Health = 0
	end
	if playerEliminatedRemote then
		playerEliminatedRemote:FireAllClients(player.UserId)
	end
	if typeof(player) == "Instance" then
		eliminatedEvent:Fire(player)
	end
	for _, callback in listeners do
		callback(player)
	end
	return true
end

return DamageService
