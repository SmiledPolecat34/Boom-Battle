--!strict
-- Événements RÉELLEMENT disponibles. Aucun événement n'existe dans le MVP : la liste est vide et le panneau
-- Événements l'indique honnêtement. Ajouter une entrée ici ne suffit pas : il faut aussi implémenter son effet.

export type GameEvent = {
	id: string,
	name: string,
	description: string,
	-- Heures serveur (os.time) de début et de fin ; nil = permanent.
	startsAt: number?,
	endsAt: number?,
}

local EventConfig = {}

EventConfig.Events = table.freeze({}) :: { GameEvent }

return table.freeze(EventConfig)
