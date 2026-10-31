--!strict
-- Récents et favoris du chat rapide (logique PURE de listes, testable). Conservés pendant la session ; la sauvegarde
-- dans le profil du joueur pourra venir avec PlayerDataService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuickChatConfig = require(ReplicatedStorage.Shared.QuickChatConfig)

local QuickChatStore = {}

local recents: { string } = {}
local favorites: { string } = table.clone(QuickChatConfig.DefaultFavorites)

local changedEvent = Instance.new("BindableEvent")
QuickChatStore.Changed = changedEvent.Event

function QuickChatStore.getRecents(): { string }
	return table.clone(recents)
end

function QuickChatStore.getFavorites(): { string }
	return table.clone(favorites)
end

function QuickChatStore.isFavorite(id: string): boolean
	return table.find(favorites, id) ~= nil
end

-- Phrase envoyée : passe en tête des récents (sans doublon, limitée à MaxRecents).
function QuickChatStore.addRecent(id: string)
	if QuickChatConfig.get(id) == nil then
		return
	end
	local existing = table.find(recents, id)
	if existing then
		table.remove(recents, existing)
	end
	table.insert(recents, 1, id)
	while #recents > QuickChatConfig.MaxRecents do
		table.remove(recents)
	end
	changedEvent:Fire()
end

-- Ajoute ou retire un favori. Retourne false si refusé (inconnu, ou liste pleine à l'ajout).
function QuickChatStore.toggleFavorite(id: string): boolean
	if QuickChatConfig.get(id) == nil then
		return false
	end
	local index = table.find(favorites, id)
	if index then
		table.remove(favorites, index)
	else
		if #favorites >= QuickChatConfig.MaxFavorites then
			return false
		end
		table.insert(favorites, id)
	end
	changedEvent:Fire()
	return true
end

return QuickChatStore
