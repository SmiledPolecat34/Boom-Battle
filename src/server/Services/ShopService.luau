--!strict
-- Réseau de la boutique : valide les demandes d'achat / d'équipement et applique ShopLogic sur le profil serveur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ShopLogic = require(script.Parent.ShopLogic)

local MAX_ID_LENGTH = 40

local ShopService = {}

local lastRequest: { [Player]: number } = {}

local function handle(player: Player, id: any, action: "purchase" | "equip", resultRemote: RemoteEvent)
	if typeof(id) ~= "string" or #id == 0 or #id > MAX_ID_LENGTH then
		return
	end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < GameConfig.RemoteLimits.ShopRequestMinInterval then
		return
	end
	lastRequest[player] = now

	local ok, err = false, "no_profile" :: any
	local equipped = false
	PlayerDataService.mutate(player, function(profile)
		if action == "purchase" then
			ok, err = ShopLogic.purchase(profile, id)
		else
			ok, err = ShopLogic.equip(profile, id)
		end
		-- Après un achat réussi, l'objet est-il maintenant équipé ? (bombe : oui, automatiquement) : sert au message du client.
		local item = CosmeticConfig.get(id)
		equipped = ok and item ~= nil and profile.EquippedCosmetics[item.kind] == item.id
	end)
	resultRemote:FireClient(player, { action = action, id = id, ok = ok, equipped = equipped, error = if ok then nil else err })
end

function ShopService.start(remotes: Folder)
	local requestPurchase = remotes:WaitForChild("RequestPurchase") :: RemoteEvent
	local requestEquip = remotes:WaitForChild("RequestEquip") :: RemoteEvent
	local result = remotes:WaitForChild("ShopResult") :: RemoteEvent

	requestPurchase.OnServerEvent:Connect(function(player: Player, id: any)
		handle(player, id, "purchase", result)
	end)
	requestEquip.OnServerEvent:Connect(function(player: Player, id: any)
		handle(player, id, "equip", result)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequest[player] = nil
	end)
end

return ShopService
