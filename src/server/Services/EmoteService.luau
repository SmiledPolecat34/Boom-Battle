--!strict
-- Émotes jouées PAR LE SERVEUR : l'animation est lancée sur l'Animator du personnage serveur, donc répliquée à tous
-- les joueurs (une animation lancée par le client ne serait pas vue des autres, le serveur étant propriétaire du
-- personnage). Le client ne demande qu'un identifiant ; tout est validé ici : identifiant connu, état de manche,
-- cadence, joueur vivant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EmoteConfig = require(ReplicatedStorage.Shared.EmoteConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlayState = require(script.Parent.PlayState)

type PlayerEmoteState = {
	character: Model?,
	tracks: { [string]: AnimationTrack }, -- pistes chargées, par id d'émote (rechargées si le personnage change)
	current: AnimationTrack?,
	token: number, -- invalide l'arrêt différé d'une danse précédente
	lastRequest: number,
}

local EmoteService = {}

local states: { [Player]: PlayerEmoteState } = {}

local function getState(player: Player): PlayerEmoteState
	local state = states[player]
	if not state then
		state = { character = nil, tracks = {}, current = nil, token = 0, lastRequest = 0 }
		states[player] = state
	end
	return state
end

-- Arrête l'émote en cours (appelé aussi quand le joueur se déplace).
function EmoteService.stop(player: Player)
	local state = states[player]
	if state and state.current then
		state.token += 1
		state.current:Stop(0.2)
		state.current = nil
	end
end

local function getAnimator(player: Player): Animator?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
end

local function handle(player: Player, id: any)
	-- 1. Forme et connaissance de l'émote : jamais de confiance dans le client.
	local emote = EmoteConfig.get(id)
	if not emote then
		return
	end
	-- 2. Cadence.
	local state = getState(player)
	local now = os.clock()
	if now - state.lastRequest < GameConfig.RemoteLimits.EmoteRequestMinInterval then
		return
	end
	state.lastRequest = now
	-- 3. Contexte de jeu et personnage vivant.
	if not PlayState.canEmote(player) then
		return
	end
	local animator = getAnimator(player)
	if not animator then
		return
	end

	-- Nouveau personnage : les anciennes pistes ne sont plus valides.
	if state.character ~= player.Character then
		state.character = player.Character
		table.clear(state.tracks)
		state.current = nil
	end

	local track = state.tracks[emote.id]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = emote.animationId
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok or not loaded then
			return
		end
		loaded.Priority = Enum.AnimationPriority.Action
		loaded.Looped = emote.looped
		state.tracks[emote.id] = loaded
		track = loaded
	end

	EmoteService.stop(player)
	state.current = track
	track:Play(0.2)

	if emote.looped then
		state.token += 1
		local token = state.token
		task.delay(EmoteConfig.MaxLoopSeconds, function()
			if state.token == token and state.current == track then
				track:Stop(0.3)
				state.current = nil
			end
		end)
	end
end

function EmoteService.start(remotes: Folder)
	local request = remotes:WaitForChild("RequestEmote") :: RemoteEvent
	request.OnServerEvent:Connect(handle)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
end

return EmoteService
