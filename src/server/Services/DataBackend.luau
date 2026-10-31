--!strict
-- Stockage des profils derrière une interface minimale, pour pouvoir tester la persistance sans DataStore.
--   load(key) -> (ok, data)   ok = false : échec (réseau, quota, accès API désactivé) ; data est alors le message
--   save(key, data) -> (ok, errorMessage)
-- Un chargement réussi sans donnée retourne (true, nil) : joueur neuf.

local DataStoreService = game:GetService("DataStoreService")

export type Backend = {
	name: string,
	load: (key: string) -> (boolean, any),
	save: (key: string, data: any) -> (boolean, string?),
}

local DataBackend = {}

function DataBackend.datastore(storeName: string): Backend
	local store: DataStore? = nil
	local function getStore(): DataStore
		if not store then
			store = DataStoreService:GetDataStore(storeName)
		end
		return store :: DataStore
	end
	return {
		name = "DataStore",
		load = function(key: string): (boolean, any)
			local ok, result = pcall(function()
				return getStore():GetAsync(key)
			end)
			return ok, result
		end,
		save = function(key: string, data: any): (boolean, string?)
			local ok, err = pcall(function()
				getStore():UpdateAsync(key, function(_old: any)
					return data
				end)
			end)
			return ok, if ok then nil else tostring(err)
		end,
	}
end

-- Mémoire du serveur : survit à un départ / retour du joueur dans la même session, jamais à l'arrêt du serveur.
-- Réservé aux tests et au repli en Studio. Les données sont copiées pour ne partager aucune référence.
local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

function DataBackend.memory(): Backend
	local data: { [string]: any } = {}
	return {
		name = "Memory",
		load = function(key: string): (boolean, any)
			return true, deepCopy(data[key])
		end,
		save = function(key: string, value: any): (boolean, string?)
			data[key] = deepCopy(value)
			return true, nil
		end,
	}
end

return DataBackend
