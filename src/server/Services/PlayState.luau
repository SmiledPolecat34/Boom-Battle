--!strict
-- Porte d'actions : quels joueurs ont le droit de se déplacer ou de poser une bombe selon l'état de manche.
-- Module sans dépendance, écrit uniquement par RoundService, lu par MovementService et BombService.

local PlayState = {}

local state: string = "WAITING"
local active: { [Player]: boolean } = {} -- joueurs de la manche encore en jeu

function PlayState.setState(newState: string)
	state = newState
end

function PlayState.getState(): string
	return state
end

function PlayState.setActive(player: Player, isActive: boolean)
	active[player] = if isActive then true else nil
end

function PlayState.clearActive()
	table.clear(active)
end

-- Au lobby tout le monde peut se déplacer ; en manche, seuls les joueurs encore en vie.
function PlayState.canMove(player: Player): boolean
	return state == "WAITING" or state == "READY" or (state == "PLAYING" and active[player] == true)
end

-- Émotes : au lobby, pendant le compte à rebours et à la fin de manche (célébration) pour tous ; en manche
-- uniquement pour les joueurs encore en vie. Jamais pendant le changement d'arène.
function PlayState.canEmote(player: Player): boolean
	if state == "PLAYING" then
		return active[player] == true
	end
	return state ~= "RESETTING"
end

function PlayState.canBomb(player: Player): boolean
	return state == "PLAYING" and active[player] == true
end

return PlayState
