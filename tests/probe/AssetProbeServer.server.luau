--!nocheck
-- SONDE ÉTAPE 1 : le serveur peut-il créer chaque MeshPart par identifiant dans une expérience publiée ?
-- À placer dans ServerScriptService d'un lieu de TEST publié, avec ProbeManifest (ModuleScript, même dossier).
-- Ne touche à rien du jeu : crée seulement des MeshParts temporaires, détruits aussitôt.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local manifest = require(script.Parent.ProbeManifest)

local report = Instance.new("RemoteEvent")
report.Name = "AssetProbeReport"
report.Parent = ReplicatedStorage

local function run(label: string)
	local ok, fail = 0, 0
	local failures = {}
	local worst = 0
	for _, e in manifest do
		local t0 = os.clock()
		local success, result = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. e.mesh))
		end)
		local dt = os.clock() - t0
		worst = math.max(worst, dt)
		if success then
			ok += 1
			result:Destroy()
		else
			fail += 1
			table.insert(failures, ("%s/%s mesh=%d : %s"):format(e.tier, e.name, e.mesh, tostring(result):sub(1, 140)))
		end
	end
	print(("[AssetProbe][SERVEUR %s] CreateMeshPartAsync : %d réussis, %d échecs (plus lent : %.2f s)"):format(label, ok, fail, worst))
	for _, line in failures do
		warn("[AssetProbe][SERVEUR] ÉCHEC " .. line)
	end
end

print(("[AssetProbe] PlaceId=%d CreatorType=%s CreatorId=%d PrivateServer=%s"):format(
	game.PlaceId, tostring(game.CreatorType), game.CreatorId, tostring(game.PrivateServerId ~= "")))
run("démarrage")

report.OnServerEvent:Connect(function(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	print(("[AssetProbe][CLIENT %s (%d)] plateforme=%s qualité=%s"):format(
		player.Name, player.UserId, tostring(payload.platform), tostring(payload.tier)))
	print(("[AssetProbe][CLIENT %s] CreateMeshPartAsync : %d réussis, %d échecs ; Preload : %d réussis, %d échecs ; plus lent %.2f s"):format(
		player.Name, payload.created or -1, payload.createFailed or -1, payload.preloadOk or -1, payload.preloadFailed or -1, payload.worst or -1))
	for _, line in (payload.failures or {}) do
		warn(("[AssetProbe][CLIENT %s] ÉCHEC %s"):format(player.Name, tostring(line)))
	end
end)

Players.PlayerAdded:Connect(function(player)
	print(("[AssetProbe] joueur %s (%d) rejoint ; il est %s propriétaire des assets de l'expérience"):format(
		player.Name, player.UserId, if player.UserId == game.CreatorId then "le" else "PAS le"))
end)
