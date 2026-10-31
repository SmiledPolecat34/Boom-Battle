--!nocheck
-- Tests des émotes, du chat rapide et des emplacements d'invitation (logique pure).
-- À EXÉCUTER DANS ROBLOX STUDIO côté CLIENT d'une session Play (modules client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client

local EmoteConfig = require(ReplicatedStorage.Shared.EmoteConfig)
local QuickChatConfig = require(ReplicatedStorage.Shared.QuickChatConfig)
local PartySlots = require(Client.UI.PartySlots)
local QuickChatStore = require(Client.Controllers.QuickChatStore)

local passed, failed = 0, 0
local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		warn(("ÉCHEC : %s %s"):format(name, detail or ""))
	end
end

-- Émotes -----------------------------------------------------------------------------------------------------
check("émotes : au moins 7", #EmoteConfig.Emotes >= 7)
local seen = {}
for _, emote in EmoteConfig.Emotes do
	check(emote.id .. " : identifiant d'animation rbxassetid", emote.animationId:match("^rbxassetid://%d+$") ~= nil)
	check(emote.id .. " : unique", not seen[emote.id])
	seen[emote.id] = true
end
check("émotes : id inconnu refusé", EmoteConfig.get("hack") == nil and EmoteConfig.get(42) == nil and EmoteConfig.get(nil) == nil)
check("émotes : les danses tournent, pas les gestes", EmoteConfig.get("dance").looped and not EmoteConfig.get("wave").looped)

-- Chat rapide --------------------------------------------------------------------------------------------------
local ids = {}
for _, phrase in QuickChatConfig.Phrases do
	check(phrase.id .. " : texte court", #phrase.text > 0 and #phrase.text <= 30)
	check(phrase.id .. " : unique", not ids[phrase.id])
	ids[phrase.id] = true
end
check("chat : id inconnu refusé", QuickChatConfig.get("<script>") == nil and QuickChatConfig.get({}) == nil)
for _, id in QuickChatConfig.DefaultFavorites do
	check("favori par défaut valide : " .. id, QuickChatConfig.get(id) ~= nil)
end

-- Récents et favoris
for _, id in { "gg", "nice", "rematch", "bye", "hello", "please", "ohno" } do
	QuickChatStore.addRecent(id)
end
local recents = QuickChatStore.getRecents()
check("récents : limités à " .. QuickChatConfig.MaxRecents, #recents == QuickChatConfig.MaxRecents)
check("récents : le plus récent en tête", recents[1] == "ohno")
QuickChatStore.addRecent("hello")
check("récents : pas de doublon, remonte en tête", QuickChatStore.getRecents()[1] == "hello" and #QuickChatStore.getRecents() == QuickChatConfig.MaxRecents)
QuickChatStore.addRecent("n_importe_quoi")
check("récents : id inconnu ignoré", QuickChatStore.getRecents()[1] == "hello")
local before = #QuickChatStore.getFavorites()
check("favoris : ajout", QuickChatStore.toggleFavorite("haha") and #QuickChatStore.getFavorites() == before + 1)
check("favoris : retrait", QuickChatStore.toggleFavorite("haha") and #QuickChatStore.getFavorites() == before)
check("favoris : id inconnu refusé", not QuickChatStore.toggleFavorite("zzz"))
-- liste pleine : l'ajout est refusé
for _, phrase in QuickChatConfig.Phrases do
	if #QuickChatStore.getFavorites() < QuickChatConfig.MaxFavorites and not QuickChatStore.isFavorite(phrase.id) then
		QuickChatStore.toggleFavorite(phrase.id)
	end
end
local full = #QuickChatStore.getFavorites()
local refused
for _, phrase in QuickChatConfig.Phrases do
	if not QuickChatStore.isFavorite(phrase.id) then
		refused = phrase.id
		break
	end
end
check("favoris : limités à " .. QuickChatConfig.MaxFavorites, full == QuickChatConfig.MaxFavorites)
check("favoris : ajout refusé quand la liste est pleine", refused ~= nil and not QuickChatStore.toggleFavorite(refused))

-- Emplacements d'invitation -----------------------------------------------------------------------------------
local function entry(id, name, queued, ready, friend) return { userId = id, name = name, queued = queued, ready = ready, isFriend = friend } end
local s0 = PartySlots.compute({}, 2)
check("groupe : personne d'autre => 2 emplacements « + »", #s0 == 2 and s0[1].kind == "invite" and s0[2].kind == "invite" and PartySlots.openInvites(s0) == 2)
local s1 = PartySlots.compute({ entry(5, "Ami", true, true, true) }, 2)
check("groupe : 1 joueur => 1 joueur + 1 « + »", s1[1].kind == "player" and s1[1].userId == 5 and s1[2].kind == "invite" and PartySlots.openInvites(s1) == 1)
check("groupe : statut Prêt", s1[1].status == "Prêt !" and s1[1].ready == true)
local s2 = PartySlots.compute({ entry(5, "A", false, false, false), entry(6, "B", true, false, false) }, 2)
check("groupe : 2 joueurs => plus aucun « + » (blocage à 2)", PartySlots.openInvites(s2) == 0)
check("groupe : statuts Au menu / En attente", (s2[1].status == "En attente" and s2[2].status == "Au menu"), tostring(s2[1].status) .. "/" .. tostring(s2[2].status))
local s3 = PartySlots.compute({ entry(1, "Zoe", true, true, false), entry(2, "Bob", false, false, true), entry(3, "Ann", true, false, true), entry(4, "Max", true, true, false) }, 2)
check("groupe : jamais plus de 2 emplacements même avec 4 joueurs", #s3 == 2 and PartySlots.openInvites(s3) == 0)
check("groupe : amis d'abord (Ann prête-inscrite avant Bob au menu)", s3[1].userId == 3 and s3[2].userId == 2, tostring(s3[1].userId) .. "," .. tostring(s3[2].userId))
local sorted1 = PartySlots.compute({ entry(9, "B", true, true, false), entry(8, "A", true, true, false) }, 2)
check("groupe : ordre stable à égalité (nom)", sorted1[1].name == "A")

-- Limite d'ouvertures de la fenêtre d'invitation (2 par minute)
local limiter = PartySlots.newLimiter(2, 60)
check("invitation 1 acceptée", select(1, PartySlots.tryAcquire(limiter, 0)))
check("invitation 2 acceptée", select(1, PartySlots.tryAcquire(limiter, 10)))
local ok3, wait3 = PartySlots.tryAcquire(limiter, 20)
check("invitation 3 BLOQUÉE (limite de 2)", not ok3 and math.abs(wait3 - 40) < 1e-6, tostring(wait3))
check("invitation à 61 s : la plus ancienne (t = 0) est sortie de la fenêtre", select(1, PartySlots.tryAcquire(limiter, 61)))
check("fenêtre glissante : t = 10 et t = 61 comptent encore => bloqué à 62 s", not select(1, PartySlots.tryAcquire(limiter, 62)))
check("fenêtre glissante : t = 10 est sorti à 71 s => possible", select(1, PartySlots.tryAcquire(limiter, 71)))

print(("[Phase8Tests] %d réussis, %d échecs"):format(passed, failed))
