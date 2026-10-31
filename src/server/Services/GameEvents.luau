--!strict
-- Signaux internes du serveur entre services qui ne doivent pas se connaître (évite les dépendances circulaires).

local GameEvents = {}

local cratesDestroyed = Instance.new("BindableEvent")
-- (userId du poseur de la bombe qui a déclenché l'explosion, nombre de caisses détruites)
GameEvents.CratesDestroyed = cratesDestroyed.Event
function GameEvents.fireCratesDestroyed(ownerUserId: number, count: number)
	cratesDestroyed:Fire(ownerUserId, count)
end

return GameEvents
