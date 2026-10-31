--!strict
-- Réglages d'affichage du joueur. Conservés pendant la session uniquement : la sauvegarde arrive en Phase 6
-- avec PlayerDataService. Aucun réglage audio tant qu'aucun son n'existe.

local SettingsStore = {}

export type Key = "bombButtonSize" | "uiScale" | "showMoveMarker" | "showTimer"

SettingsStore.BombButtonSizes = table.freeze({ Petit = 90, Moyen = 120, Grand = 150 })
SettingsStore.UiScales = table.freeze({ Petit = 0.85, Normal = 1, Grand = 1.15 })

local values: { [string]: any } = {
	bombButtonSize = "Moyen",
	uiScale = "Normal",
	showMoveMarker = true,
	showTimer = true,
}

local changedEvent = Instance.new("BindableEvent")
SettingsStore.Changed = changedEvent.Event

function SettingsStore.get(key: Key): any
	return values[key]
end

-- Retourne false si la valeur est refusée (clé inconnue ou valeur hors liste).
function SettingsStore.set(key: Key, value: any): boolean
	if key == "bombButtonSize" then
		if SettingsStore.BombButtonSizes[value] == nil then
			return false
		end
	elseif key == "uiScale" then
		if SettingsStore.UiScales[value] == nil then
			return false
		end
	elseif key == "showMoveMarker" or key == "showTimer" then
		if typeof(value) ~= "boolean" then
			return false
		end
	else
		return false
	end
	values[key] = value
	changedEvent:Fire(key)
	return true
end

function SettingsStore.bombButtonPixels(): number
	return SettingsStore.BombButtonSizes[values.bombButtonSize]
end

function SettingsStore.uiScaleMultiplier(): number
	return SettingsStore.UiScales[values.uiScale]
end

return SettingsStore
