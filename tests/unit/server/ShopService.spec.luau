--!nocheck
-- ShopService : validation réseau des demandes d'achat / d'équipement (types, longueur, cadence, profil absent).
-- Le client ne peut envoyer qu'un identifiant ; toute autre forme de charge utile doit être ignorée sans effet.
local ShopService = world.module("ShopService")
local PlayerDataService = world.module("PlayerDataService")
local DataBackend = world.module("DataBackend")

local function setup()
	PlayerDataService.setBackend(DataBackend.memory())
	local remotes = Fixtures.fakeRemotes({ "RequestPurchase", "RequestEquip", "ShopResult" })
	ShopService.start(remotes)
	return remotes
end

local function richPlayer(userId: number, coins: number)
	local player = Fixtures.fakePlayer(userId)
	PlayerDataService.load(player)
	PlayerDataService.mutate(player, function(p)
		p.Coins = coins
	end)
	return player
end

describe("achat", function()
	it("un achat valide débite, informe le client et crédite l'objet", function()
		local remotes = setup()
		local player = richPlayer(1, 300)
		remotes.RequestPurchase:fireServer(player, "bomb_red")
		local profile = PlayerDataService.get(player)
		expect(profile.Coins).toBe(50)
		expect(profile.OwnedCosmetics.bomb_red).toBe(true)
		local sent = remotes.ShopResult.sent[1]
		expect(sent.player).toBe(player)
		expect(sent.args[1].ok).toBe(true)
		expect(sent.args[1].action).toBe("purchase")
	end)

	it("charges invalides ignorées sans réponse ni effet (nil, nombre, table, booléen, vide, trop long)", function()
		local remotes = setup()
		local player = richPlayer(2, 1000)
		for _, bad in { 12, true, {}, "", string.rep("a", 41), string.rep("a", 5000) } do
			remotes.RequestPurchase:fireServer(player, bad)
		end
		remotes.RequestPurchase:fireServer(player, nil)
		expect(PlayerDataService.get(player).Coins).toBe(1000)
		expect(#remotes.ShopResult.sent).toBe(0)
	end)

	it("limite de cadence : la 2e demande immédiate est ignorée", function()
		local remotes = setup()
		local player = richPlayer(3, 1000)
		remotes.RequestPurchase:fireServer(player, "bomb_red")
		remotes.RequestPurchase:fireServer(player, "bomb_blue")
		expect(#remotes.ShopResult.sent).toBe(1)
		expect(PlayerDataService.get(player).OwnedCosmetics.bomb_blue).toBeNil()
	end)

	it("la cadence est par joueur : un autre joueur n'est pas bloqué", function()
		local remotes = setup()
		local a, b = richPlayer(4, 1000), richPlayer(5, 1000)
		remotes.RequestPurchase:fireServer(a, "bomb_red")
		remotes.RequestPurchase:fireServer(b, "bomb_red")
		expect(#remotes.ShopResult.sent).toBe(2)
	end)

	it("achat refusé (solde insuffisant) : réponse ok=false avec la raison", function()
		local remotes = setup()
		local player = richPlayer(6, 10)
		remotes.RequestPurchase:fireServer(player, "bomb_ice")
		local sent = remotes.ShopResult.sent[1].args[1]
		expect(sent.ok).toBe(false)
		expect(sent.error).toBe("funds")
		expect(PlayerDataService.get(player).Coins).toBe(10)
	end)

	it("joueur sans profil chargé : réponse no_profile, aucun plantage", function()
		local remotes = setup()
		local player = Fixtures.fakePlayer(7)
		remotes.RequestPurchase:fireServer(player, "bomb_red")
		local sent = remotes.ShopResult.sent[1].args[1]
		expect(sent.ok).toBe(false)
		expect(sent.error).toBe("no_profile")
	end)

	it("le départ d'un joueur libère son compteur de cadence", function()
		local remotes = setup()
		local player = richPlayer(8, 1000)
		remotes.RequestPurchase:fireServer(player, "bomb_red")
		world.removePlayer(player)
		remotes.RequestPurchase:fireServer(player, "bomb_blue")
		expect(#remotes.ShopResult.sent).toBe(2)
	end)
end)

describe("équipement", function()
	it("équiper un objet possédé, refuser un objet non possédé", function()
		local remotes = setup()
		local player = richPlayer(9, 300)
		remotes.RequestPurchase:fireServer(player, "bomb_red")
		world.removePlayer(player) -- remet la cadence à zéro (comme une reconnexion)
		remotes.RequestEquip:fireServer(player, "bomb_red")
		expect(PlayerDataService.get(player).EquippedCosmetics.bomb).toBe("bomb_red")
		world.removePlayer(player)
		remotes.RequestEquip:fireServer(player, "bomb_ice")
		expect(PlayerDataService.get(player).EquippedCosmetics.bomb).toBe("bomb_red")
	end)
end)
