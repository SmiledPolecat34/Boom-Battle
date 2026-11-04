--!strict
-- Point d'entrée serveur : crée les remotes, démarre les services et laisse RoundService piloter la partie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent.Services
local BombService = require(Services.BombService)
local DamageService = require(Services.DamageService)
local EmoteService = require(Services.EmoteService)
local MapService = require(Services.MapService)
local MovementService = require(Services.MovementService)
local PlayerDataService = require(Services.PlayerDataService)
local PowerupService = require(Services.PowerupService)
local QuickChatService = require(Services.QuickChatService)
local QuestService = require(Services.QuestService)
local RoundService = require(Services.RoundService)
local ShopService = require(Services.ShopService)

-- Les personnages sont chargés explicitement par RoundService (lobby, début de manche) ; un joueur éliminé ne
-- réapparaît pas tout seul.
Players.CharacterAutoLoads = false

-- Remotes -------------------------------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in {
	"ClientReady",
	"MapReady",
	"RequestMove",
	"MoveRejected",
	"RequestPlaceBomb",
	"Explosion",
	"StatsChanged",
	"PlayerEliminated",
	"SetReady",
	"SetQueued",
	"ProfileUpdated",
	"RequestPurchase",
	"RequestEquip",
	"ShopResult",
	"RequestEmote",
	"RequestQuickChat",
	"PartyAction",
	"Notice",
	"RoundState",
	"RoundEnded",
} do
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
end
remotes.Parent = ReplicatedStorage

-- Services ------------------------------------------------------------------------------------------------

MovementService.start(remotes, function()
	local info = MapService.getCurrent()
	return if info then info.grid else nil
end)
PowerupService.start(remotes)
DamageService.start(remotes)
BombService.start(remotes)
PlayerDataService.start(remotes)
QuestService.start()
ShopService.start(remotes)
EmoteService.start(remotes)
QuickChatService.start(remotes)
RoundService.start(remotes)

-- Le client signale qu'il est prêt à recevoir l'arène et l'état de la manche.
local clientReadyAt: { [Player]: number } = {}
local clientReadyEvent = remotes:FindFirstChild("ClientReady") :: RemoteEvent
clientReadyEvent.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if now - (clientReadyAt[player] or 0) < 1 then
		return
	end
	clientReadyAt[player] = now
	RoundService.sendFullState(player)
	PlayerDataService.sendProfile(player) -- sans effet tant que le profil n'est pas chargé : il est alors envoyé au chargement
end)
Players.PlayerRemoving:Connect(function(player)
	clientReadyAt[player] = nil
end)
