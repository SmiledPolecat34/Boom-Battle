--!nocheck
-- ProfileSchema (validation de toute donnée lue) et ShopLogic (achat / équipement). Le serveur est autoritaire :
-- aucune donnée venue du stockage ou du client n'est crue sans passer par ces fonctions.
local CosmeticConfig = world.module("CosmeticConfig")
local QuestConfig = world.module("QuestConfig")
local GameConfig = world.module("GameConfig")
local ProfileSchema = world.module("ProfileSchema")
local ShopLogic = world.module("ShopLogic")

describe("catalogue cosmétique", function()
	for _, kind in { "bomb", "effect" } do
		it(kind .. " : au moins 2 objets, prix entiers >= 0, ids uniques, type cohérent", function()
			local ids = CosmeticConfig.idsOfKind(kind)
			expect(#ids).toBeGreaterThanOrEqual(2)
			local seen = {}
			for _, id in ids do
				local item = CosmeticConfig.get(id)
				expect(item.price).toBe(math.floor(item.price))
				expect(item.price).toBeGreaterThanOrEqual(0)
				expect(item.kind).toBe(kind)
				expect(seen[id]).toBeNil()
				seen[id] = true
			end
		end)

		it(kind .. " : l'objet par défaut est gratuit", function()
			expect(CosmeticConfig.get(CosmeticConfig.Defaults[kind]).price).toBe(0)
		end)
	end

	it("get refuse tout identifiant inconnu ou de mauvais type", function()
		expect(CosmeticConfig.get("nope")).toBeNil()
		expect(CosmeticConfig.get(42)).toBeNil()
		expect(CosmeticConfig.get(nil)).toBeNil()
		expect(CosmeticConfig.get({})).toBeNil()
		expect(CosmeticConfig.get(true)).toBeNil()
	end)
end)

describe("ProfileSchema.default", function()
	it("profil neuf : 0 pièce, cosmétiques par défaut possédés et équipés", function()
		local d = ProfileSchema.default()
		expect(d.Coins).toBe(0)
		expect(d.Wins).toBe(0)
		expect(d.MatchesPlayed).toBe(0)
		expect(d.OwnedCosmetics.bomb_classic).toBe(true)
		expect(d.EquippedCosmetics.bomb).toBe("bomb_classic")
		expect(d.EquippedCosmetics.effect).toBe("effect_classic")
		expect(d.DataVersion).toBe(GameConfig.Data.DataVersion)
	end)

	it("toutes les quêtes sont présentes, à zéro", function()
		local d = ProfileSchema.default()
		for _, q in QuestConfig.Quests do
			expect(d.QuestProgress[q.id].progress).toBe(0)
			expect(d.QuestProgress[q.id].done).toBe(false)
		end
	end)

	it("deux profils neufs ne partagent aucune table", function()
		local a, b = ProfileSchema.default(), ProfileSchema.default()
		a.OwnedCosmetics.bomb_red = true
		a.QuestProgress.play3.progress = 2
		expect(b.OwnedCosmetics.bomb_red).toBeNil()
		expect(b.QuestProgress.play3.progress).toBe(0)
	end)
end)

describe("ProfileSchema.sanitize", function()
	it("nil, texte, nombre, booléen => profil neuf (jamais d'erreur)", function()
		for _, raw in { "hack", 12, true, false } do
			expect(ProfileSchema.sanitize(raw).Coins).toBe(0)
		end
		expect(ProfileSchema.sanitize(nil).Coins).toBe(0)
	end)

	it("donnée forgée : tout est corrigé", function()
		local forged = ProfileSchema.sanitize({
			DataVersion = 1,
			Coins = 0 / 0,
			Wins = -5,
			MatchesPlayed = "beaucoup",
			OwnedCosmetics = { bomb_ice = true, fake_item = true, effect_fire = "oui", [5] = true },
			EquippedCosmetics = { bomb = "bomb_red", effect = "bomb_ice" },
			QuestProgress = { play3 = { progress = 999, done = false }, win1 = "x" },
		})
		expect(forged.Coins).toBe(0)
		expect(forged.Wins).toBe(0)
		expect(forged.MatchesPlayed).toBe(0)
		expect(forged.OwnedCosmetics.fake_item).toBeNil()
		expect(forged.OwnedCosmetics.bomb_ice).toBe(true)
		expect(forged.OwnedCosmetics.effect_fire).toBeNil()
		expect(forged.EquippedCosmetics.bomb).toBe("bomb_classic") -- bomb_red non possédé
		expect(forged.EquippedCosmetics.effect).toBe("effect_classic") -- mauvais type
		expect(forged.QuestProgress.play3.progress).toBe(3)
		expect(forged.QuestProgress.play3.done).toBe(true)
		expect(forged.QuestProgress.win1.progress).toBe(0)
		expect(forged.QuestProgress.win1.done).toBe(false)
	end)

	it("les pièces sont plafonnées, arrondies vers le bas, jamais infinies", function()
		expect(ProfileSchema.sanitize({ Coins = math.huge }).Coins).toBe(GameConfig.Data.MaxCoins)
		expect(ProfileSchema.sanitize({ Coins = 99.9 }).Coins).toBe(99)
		expect(ProfileSchema.sanitize({ Coins = -math.huge }).Coins).toBe(0)
		expect(ProfileSchema.sanitize({ Coins = GameConfig.Data.MaxCoins + 1 }).Coins).toBe(GameConfig.Data.MaxCoins)
	end)

	it("une version future est refusée (le profil ne sera jamais réécrit)", function()
		local profile, reason = ProfileSchema.sanitize({ DataVersion = GameConfig.Data.DataVersion + 1, Coins = 5 })
		expect(profile).toBeNil()
		expect(reason).never.toBeNil()
	end)

	it("un profil valide fait l'aller-retour serialize -> sanitize sans perte", function()
		local p = ProfileSchema.default()
		p.Coins, p.Wins, p.MatchesPlayed = 321, 4, 9
		p.OwnedCosmetics.bomb_blue = true
		p.EquippedCosmetics.bomb = "bomb_blue"
		p.QuestProgress.crates20 = { progress = 7, done = false }
		local back = ProfileSchema.sanitize(ProfileSchema.serialize(p))
		expect(back.Coins).toBe(321)
		expect(back.Wins).toBe(4)
		expect(back.MatchesPlayed).toBe(9)
		expect(back.OwnedCosmetics.bomb_blue).toBe(true)
		expect(back.EquippedCosmetics.bomb).toBe("bomb_blue")
		expect(back.QuestProgress.crates20.progress).toBe(7)
	end)

	it("serialize ne partage aucune référence avec le profil", function()
		local p = ProfileSchema.default()
		local s = ProfileSchema.serialize(p)
		p.OwnedCosmetics.bomb_red = true
		expect(s.OwnedCosmetics.bomb_red).toBeNil()
	end)
end)

describe("ShopLogic.purchase", function()
	local function richProfile(coins: number)
		local p = ProfileSchema.default()
		p.Coins = coins
		return p
	end

	it("T14 achat réussi : solde débité, objet possédé", function()
		local p = richProfile(300)
		local ok, err = ShopLogic.purchase(p, "bomb_red")
		expect(ok).toBe(true)
		expect(err).toBeNil()
		expect(p.Coins).toBe(50)
		expect(p.OwnedCosmetics.bomb_red).toBe(true)
	end)

	it("doublon refusé sans débit", function()
		local p = richProfile(300)
		ShopLogic.purchase(p, "bomb_red")
		local ok, err = ShopLogic.purchase(p, "bomb_red")
		expect(ok).toBe(false)
		expect(err).toBe("owned")
		expect(p.Coins).toBe(50)
	end)

	it("solde insuffisant refusé sans effet", function()
		local p = richProfile(50)
		local ok, err = ShopLogic.purchase(p, "bomb_ice")
		expect(ok).toBe(false)
		expect(err).toBe("funds")
		expect(p.Coins).toBe(50)
		expect(p.OwnedCosmetics.bomb_ice).toBeNil()
	end)

	it("solde exact accepté (tombe à 0, jamais négatif)", function()
		local p = richProfile(250)
		expect(ShopLogic.purchase(p, "effect_yellow")).toBe(true)
		expect(p.Coins).toBe(0)
	end)

	it("identifiants invalides refusés sans effet", function()
		local p = richProfile(1000)
		for _, bad in { "inconnu", 12, true, {}, "" } do
			expect(ShopLogic.purchase(p, bad)).toBe(false)
		end
		expect(ShopLogic.purchase(p, nil)).toBe(false)
		expect(p.Coins).toBe(1000)
	end)
end)

describe("ShopLogic.equip", function()
	it("équiper un objet possédé", function()
		local p = ProfileSchema.default()
		p.Coins = 300
		ShopLogic.purchase(p, "bomb_red")
		expect(ShopLogic.equip(p, "bomb_red")).toBe(true)
		expect(p.EquippedCosmetics.bomb).toBe("bomb_red")
	end)

	it("un objet non possédé est refusé et l'équipement reste inchangé", function()
		local p = ProfileSchema.default()
		local ok, err = ShopLogic.equip(p, "bomb_ice")
		expect(ok).toBe(false)
		expect(err).toBe("not_owned")
		expect(p.EquippedCosmetics.bomb).toBe("bomb_classic")
	end)

	it("un objet n'occupe que l'emplacement de son type", function()
		local p = ProfileSchema.default()
		p.Coins = 300
		ShopLogic.purchase(p, "bomb_red")
		ShopLogic.equip(p, "bomb_red")
		expect(ShopLogic.equip(p, "effect_classic")).toBe(true)
		expect(p.EquippedCosmetics.bomb).toBe("bomb_red")
		expect(p.EquippedCosmetics.effect).toBe("effect_classic")
	end)

	it("identifiants invalides refusés", function()
		local p = ProfileSchema.default()
		for _, bad in { "x", 5, true, {}, "" } do
			expect(ShopLogic.equip(p, bad)).toBe(false)
		end
	end)
end)
