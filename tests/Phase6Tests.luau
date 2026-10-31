--!nocheck
-- Tests de la Phase 6 : schéma de données, boutique, récompenses, quêtes, stockage.
-- À EXÉCUTER DANS ROBLOX STUDIO côté serveur d'une session Play (en mode Edit, `require` peut garder d'anciens
-- modules en cache). Logique pure : aucun DataStore, aucun joueur réel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ProfileSchema = require(Services.ProfileSchema)
local ShopLogic = require(Services.ShopLogic)
local QuestService = require(Services.QuestService)
local RewardService = require(Services.RewardService)
local DataBackend = require(Services.DataBackend)

local passed, failed = 0, 0
local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		warn(("ÉCHEC : %s %s"):format(name, detail or ""))
	end
end

-- Catalogue ---------------------------------------------------------------------------------------------------
for _, kind in { "bomb", "effect" } do
	local ids = CosmeticConfig.idsOfKind(kind)
	check(kind .. " : au moins 2 objets", #ids >= 2)
	local seen = {}
	for _, id in ids do
		local item = CosmeticConfig.get(id)
		check(id .. " : prix entier >= 0", item.price == math.floor(item.price) and item.price >= 0)
		check(id .. " : type cohérent", item.kind == kind)
		check(id .. " : unique", not seen[id])
		seen[id] = true
	end
	check(kind .. " : défaut gratuit", CosmeticConfig.get(CosmeticConfig.Defaults[kind]).price == 0)
end
check("get : id inconnu => nil", CosmeticConfig.get("nope") == nil and CosmeticConfig.get(42) == nil and CosmeticConfig.get(nil) == nil)

-- Profil par défaut et validation -------------------------------------------------------------------------------
local d = ProfileSchema.default()
check("défaut : 0 pièce", d.Coins == 0 and d.Wins == 0 and d.MatchesPlayed == 0)
check("défaut : cosmétiques par défaut possédés et équipés", d.OwnedCosmetics.bomb_classic and d.EquippedCosmetics.bomb == "bomb_classic" and d.EquippedCosmetics.effect == "effect_classic")
check("défaut : toutes les quêtes présentes", (function() for _, q in QuestConfig.Quests do if not d.QuestProgress[q.id] then return false end end return true end)())

check("sanitize nil => profil neuf", select(1, ProfileSchema.sanitize(nil)).Coins == 0)
check("sanitize texte => profil neuf", select(1, ProfileSchema.sanitize("hack")).Coins == 0)
local forged = ProfileSchema.sanitize({
	DataVersion = 1,
	Coins = 0 / 0,
	Wins = -5,
	MatchesPlayed = "beaucoup",
	OwnedCosmetics = { bomb_ice = true, fake_item = true, effect_fire = "oui", [5] = true },
	EquippedCosmetics = { bomb = "bomb_red", effect = "bomb_ice" },
	QuestProgress = { play3 = { progress = 999, done = false }, win1 = "x" },
})
check("sanitize : NaN => 0", forged.Coins == 0)
check("sanitize : négatif => 0", forged.Wins == 0)
check("sanitize : texte => 0", forged.MatchesPlayed == 0)
check("sanitize : objet inventé ignoré", forged.OwnedCosmetics.fake_item == nil)
check("sanitize : objet valide conservé", forged.OwnedCosmetics.bomb_ice == true)
check("sanitize : valeur non booléenne ignorée", forged.OwnedCosmetics.effect_fire == nil)
check("sanitize : équipement non possédé refusé", forged.EquippedCosmetics.bomb == "bomb_classic")
check("sanitize : mauvais type d'équipement refusé", forged.EquippedCosmetics.effect == "effect_classic")
check("sanitize : progression bornée à l'objectif", forged.QuestProgress.play3.progress == 3 and forged.QuestProgress.play3.done == true)
check("sanitize : quête invalide remise à zéro", forged.QuestProgress.win1.progress == 0 and forged.QuestProgress.win1.done == false)
check("sanitize : pièces plafonnées", ProfileSchema.sanitize({ Coins = math.huge }).Coins == GameConfig.Data.MaxCoins)
check("sanitize : décimaux arrondis vers le bas", ProfileSchema.sanitize({ Coins = 99.9 }).Coins == 99)
local future, reason = ProfileSchema.sanitize({ DataVersion = GameConfig.Data.DataVersion + 1, Coins = 5 })
check("sanitize : version future refusée (jamais réécrite)", future == nil and reason ~= nil)

-- Boutique -------------------------------------------------------------------------------------------------------
do
	local p = ProfileSchema.default()
	p.Coins = 300
	local ok, err = ShopLogic.purchase(p, "bomb_red")
	check("T14 achat : réussi", ok and err == nil)
	check("T14 achat : solde débité", p.Coins == 50)
	check("T14 achat : objet possédé", p.OwnedCosmetics.bomb_red == true)
	local ok2, err2 = ShopLogic.purchase(p, "bomb_red")
	check("achat : doublon refusé", not ok2 and err2 == "owned" and p.Coins == 50)
	local ok3, err3 = ShopLogic.purchase(p, "bomb_ice")
	check("achat : solde insuffisant refusé", not ok3 and err3 == "funds" and p.Coins == 50 and not p.OwnedCosmetics.bomb_ice)
	for _, bad in { "inconnu", 12, true, {}, "" } do
		local okb = ShopLogic.purchase(p, bad)
		check("achat : id invalide refusé (" .. tostring(bad) .. ")", not okb and p.Coins == 50)
	end
	local ok4 = ShopLogic.equip(p, "bomb_red")
	check("équiper : objet possédé", ok4 and p.EquippedCosmetics.bomb == "bomb_red")
	local ok5, err5 = ShopLogic.equip(p, "bomb_ice")
	check("équiper : objet non possédé refusé", not ok5 and err5 == "not_owned" and p.EquippedCosmetics.bomb == "bomb_red")
	ShopLogic.purchase(p, "effect_red") -- 250 > 50 : refusé
	check("équiper : un objet d'un autre type ne remplace pas le bon emplacement", ShopLogic.equip(p, "effect_classic") and p.EquippedCosmetics.bomb == "bomb_red" and p.EquippedCosmetics.effect == "effect_classic")
	-- Solde exact.
	local q = ProfileSchema.default()
	q.Coins = 250
	check("achat : solde exact accepté", ShopLogic.purchase(q, "effect_yellow") and q.Coins == 0)
end

-- Récompenses ----------------------------------------------------------------------------------------------------
do
	local win = { outcome = "WIN", winnerUserId = 1, tiedUserIds = {}, ranking = { 1, 2 }, durationSeconds = 30 }
	check("récompense : vainqueur", RewardService.coinsFor(1, win) == GameConfig.Rewards.ParticipationCoins + GameConfig.Rewards.WinCoins)
	check("récompense : perdant", RewardService.coinsFor(2, win) == GameConfig.Rewards.ParticipationCoins)
	local draw = { outcome = "DRAW", tiedUserIds = { 3, 4 }, ranking = { 3, 4, 5 }, durationSeconds = 30 }
	check("récompense : égalité", RewardService.coinsFor(3, draw) == GameConfig.Rewards.ParticipationCoins + GameConfig.Rewards.DrawCoins)
	check("récompense : éliminé avant l'égalité", RewardService.coinsFor(5, draw) == GameConfig.Rewards.ParticipationCoins)
	check("récompense : jamais négative", RewardService.coinsFor(999, win) >= 0)
end

-- Quêtes -----------------------------------------------------------------------------------------------------------
do
	local p = ProfileSchema.default()
	check("quête : progression partielle sans récompense", #QuestService.apply(p, "round_played", 2) == 0 and p.Coins == 0 and p.QuestProgress.play3.progress == 2)
	local done = QuestService.apply(p, "round_played", 1)
	check("quête : terminée et récompensée une fois", done[1] == "play3" and p.Coins == QuestConfig.get("play3").reward and p.QuestProgress.play3.done)
	local before = p.Coins
	check("quête : pas de seconde récompense", #QuestService.apply(p, "round_played", 5) == 0 and p.Coins == before)
	check("quête : événement inconnu ignoré", #QuestService.apply(p, "n_importe_quoi", 5) == 0)
	check("quête : quantité négative ignorée", #QuestService.apply(p, "crates_destroyed", -5) == 0 and p.QuestProgress.crates20.progress == 0)
	check("quête : NaN ignoré", #QuestService.apply(p, "crates_destroyed", 0 / 0) == 0 and p.QuestProgress.crates20.progress == 0)
	QuestService.apply(p, "crates_destroyed", 15)
	local finished = QuestService.apply(p, "crates_destroyed", 15)
	check("quête : progression plafonnée à l'objectif", finished[1] == "crates20" and p.QuestProgress.crates20.progress == 20)
end

-- Stockage / rechargement (T15, logique) -----------------------------------------------------------------------------
do
	local backend = DataBackend.memory()
	local p = ProfileSchema.default()
	p.Coins = 123
	p.Wins = 2
	p.MatchesPlayed = 7
	ShopLogic.purchase({ Coins = 0, OwnedCosmetics = {}, EquippedCosmetics = {} }, "bomb_red") -- profil bidon : ne doit pas planter
	p.OwnedCosmetics.bomb_blue = true
	p.EquippedCosmetics.bomb = "bomb_blue"
	p.QuestProgress.play3 = { progress = 2, done = false }
	local saved = backend.save("Player_1", ProfileSchema.serialize(p))
	check("stockage : sauvegarde confirmée", saved)
	local ok, raw = backend.load("Player_1")
	local reloaded = ProfileSchema.sanitize(raw)
	check("T15 rechargement : pièces", ok and reloaded.Coins == 123 and reloaded.Wins == 2 and reloaded.MatchesPlayed == 7)
	check("T15 rechargement : cosmétiques et équipement", reloaded.OwnedCosmetics.bomb_blue and reloaded.EquippedCosmetics.bomb == "bomb_blue")
	check("T15 rechargement : quêtes", reloaded.QuestProgress.play3.progress == 2)
	-- Pas de référence partagée entre le profil et le stockage.
	p.Coins = 999
	local _, raw2 = backend.load("Player_1")
	check("stockage : aucune référence partagée", raw2.Coins == 123)
	local okNew, rawNew = backend.load("Player_inconnu")
	check("stockage : joueur neuf => (true, nil)", okNew and rawNew == nil)
end

print(("[Phase6Tests] %d réussis, %d échecs"):format(passed, failed))
