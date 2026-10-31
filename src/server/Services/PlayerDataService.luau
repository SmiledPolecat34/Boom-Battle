--!strict
-- Profils des joueurs : chargement, validation, modification contrôlée, sauvegarde.
--
-- Règles de sécurité :
--  * le client ne modifie jamais un profil : seuls les services serveur appellent mutate() ;
--  * un profil dont le CHARGEMENT a échoué n'est jamais sauvegardé (il écraserait les vraies données) ;
--  * une sauvegarde qui échoue est signalée et réessayée, jamais déclarée réussie ;
--  * aucune panne de DataStore ne fait planter le serveur (tout est sous pcall).
--
-- Limite connue : pas de verrou de session entre serveurs (un joueur connecté deux fois pourrait écraser ses données).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local DataBackend = require(script.Parent.DataBackend)
local ProfileSchema = require(script.Parent.ProfileSchema)

type Entry = {
	profile: ProfileSchema.Profile,
	persisted: boolean, -- false : profil temporaire (chargement impossible) ; jamais sauvegardé
	dirty: boolean,
	saving: boolean,
	version: number, -- incrémenté à chaque modification
}

local PlayerDataService = {}

local entries: { [Player]: Entry } = {}
local backend: DataBackend.Backend = DataBackend.datastore(GameConfig.Data.DataStoreName)
local profileUpdated: RemoteEvent? = nil
local changedEvent = Instance.new("BindableEvent")
-- Déclenché après chaque chargement ou modification : (Player). Utilisé pour informer le client.
PlayerDataService.Changed = changedEvent.Event

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

-- Contenu envoyé au client (lecture seule côté client).
local function publicProfile(entry: Entry)
	local profile = entry.profile
	local owned: { [string]: boolean } = {}
	for id in profile.OwnedCosmetics do
		owned[id] = true
	end
	local quests: { [string]: any } = {}
	for id, state in profile.QuestProgress do
		quests[id] = { progress = state.progress, done = state.done }
	end
	return {
		coins = profile.Coins,
		wins = profile.Wins,
		matches = profile.MatchesPlayed,
		owned = owned,
		equipped = { bomb = profile.EquippedCosmetics.bomb, effect = profile.EquippedCosmetics.effect },
		quests = quests,
		persisted = entry.persisted,
	}
end

local function publish(player: Player)
	local entry = entries[player]
	if entry and profileUpdated then
		profileUpdated:FireClient(player, publicProfile(entry))
	end
	changedEvent:Fire(player)
end

-- Remplace le stockage (tests, ou repli mémoire en Studio).
function PlayerDataService.setBackend(newBackend: DataBackend.Backend)
	backend = newBackend
end

function PlayerDataService.getBackendName(): string
	return backend.name
end

function PlayerDataService.get(player: Player): ProfileSchema.Profile?
	local entry = entries[player]
	return if entry then entry.profile else nil
end

function PlayerDataService.isPersisted(player: Player): boolean
	local entry = entries[player]
	return entry ~= nil and entry.persisted
end

-- Modifie le profil SI il est chargé. fn reçoit le profil et le modifie en place. Retourne true si appliqué.
function PlayerDataService.mutate(player: Player, fn: (profile: ProfileSchema.Profile) -> ()): boolean
	local entry = entries[player]
	if not entry then
		return false
	end
	fn(entry.profile)
	entry.dirty = true
	entry.version += 1
	publish(player)
	return true
end

-- Charge le profil d'un joueur. Bloquant (réseau) : à appeler depuis un thread dédié.
function PlayerDataService.load(player: Player)
	if entries[player] then
		return
	end
	local key = keyFor(player)
	local profile: ProfileSchema.Profile? = nil
	local lastError = ""

	for attempt = 1, GameConfig.Data.MaxLoadRetries do
		local ok, result = backend.load(key)
		if ok then
			local sanitized, reason = ProfileSchema.sanitize(result)
			if sanitized then
				profile = sanitized
			else
				lastError = reason or "profil invalide"
			end
			break
		end
		lastError = tostring(result)
		if attempt < GameConfig.Data.MaxLoadRetries then
			task.wait(attempt) -- 1 s, 2 s
		end
	end

	if player.Parent ~= Players then
		return -- le joueur est parti pendant le chargement
	end

	if profile then
		entries[player] = { profile = profile, persisted = true, dirty = false, saving = false, version = 0 }
	else
		warn(("[PlayerDataService] Chargement impossible pour %s (%s) : profil temporaire, rien ne sera sauvegardé."):format(player.Name, lastError))
		local temporary = ProfileSchema.default()
		-- Aide de test, UNIQUEMENT dans Roblox Studio : solde de départ sur un profil temporaire.
		local devCoins = workspace:GetAttribute("DevStartCoins")
		if RunService:IsStudio() and typeof(devCoins) == "number" then
			temporary.Coins = ProfileSchema.toCount(devCoins, GameConfig.Data.MaxCoins)
		end
		entries[player] = { profile = temporary, persisted = false, dirty = false, saving = false, version = 0 }
	end
	publish(player)
end

-- Sauvegarde un joueur. Retourne true seulement si le stockage a confirmé l'écriture.
function PlayerDataService.save(player: Player): boolean
	local entry = entries[player]
	if not entry or not entry.persisted then
		return false -- profil temporaire : on n'écrase jamais de vraies données
	end
	if not entry.dirty then
		return true
	end
	if entry.saving then
		return false
	end
	entry.saving = true
	local savedVersion = entry.version
	local data = ProfileSchema.serialize(entry.profile)
	local saved = false
	for attempt = 1, GameConfig.Data.MaxSaveRetries do
		local ok, err = backend.save(keyFor(player), data)
		if ok then
			saved = true
			break
		end
		warn(("[PlayerDataService] Échec de sauvegarde pour %s (essai %d/%d) : %s"):format(player.Name, attempt, GameConfig.Data.MaxSaveRetries, tostring(err)))
		if attempt < GameConfig.Data.MaxSaveRetries then
			task.wait(attempt)
		end
	end
	entry.saving = false
	if saved then
		-- Une modification arrivée pendant la sauvegarde reste « sale » : elle sera sauvegardée au prochain passage.
		if entry.version == savedVersion then
			entry.dirty = false
		end
	else
		warn(("[PlayerDataService] Données de %s NON sauvegardées."):format(player.Name))
	end
	return saved
end

function PlayerDataService.start(remotes: Folder)
	profileUpdated = remotes:WaitForChild("ProfileUpdated") :: RemoteEvent

	local function onPlayerAdded(player: Player)
		task.spawn(PlayerDataService.load, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		PlayerDataService.save(player)
		entries[player] = nil
	end)

	-- Sauvegarde périodique des profils modifiés.
	task.spawn(function()
		while true do
			task.wait(GameConfig.Data.AutosaveInterval)
			for player, entry in entries do
				if entry.dirty and entry.persisted then
					task.spawn(PlayerDataService.save, player)
				end
			end
		end
	end)

	-- Arrêt du serveur : dernière sauvegarde de tous les joueurs, en parallèle.
	game:BindToClose(function()
		local pending = 0
		for player, entry in entries do
			if entry.dirty and entry.persisted then
				pending += 1
				task.spawn(function()
					PlayerDataService.save(player)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- Renvoie le profil courant à un client (ex. après ClientReady).
function PlayerDataService.sendProfile(player: Player)
	publish(player)
end

return PlayerDataService
