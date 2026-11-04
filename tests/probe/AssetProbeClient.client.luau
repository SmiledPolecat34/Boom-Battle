--!nocheck
-- SONDE ÉTAPE 1 (client) : crée chaque modèle PC et mobile par identifiant sur ce client, mesure le préchargement
-- (ContentProvider) et affiche une rangée de modèles + un texte de résultat pour la vérification VISUELLE.
-- À placer dans StarterPlayerScripts du lieu de test publié.

local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local manifest = require(ReplicatedStorage:WaitForChild("ProbeManifest"))
local report = ReplicatedStorage:WaitForChild("AssetProbeReport")

local platform = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "tactile" else "bureau"
local created, createFailed, worst = 0, 0, 0
local failures = {}
local templates = {} -- [tier][name] = MeshPart

for _, e in manifest do
	templates[e.tier] = templates[e.tier] or {}
	local t0 = os.clock()
	local ok, mesh = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. e.mesh))
	end)
	worst = math.max(worst, os.clock() - t0)
	if ok then
		created += 1
		mesh.TextureID = "rbxassetid://" .. e.tex
		mesh.Anchored = true
		mesh.Name = e.name
		templates[e.tier][e.name] = mesh
	else
		createFailed += 1
		table.insert(failures, ("%s/%s mesh=%d : %s"):format(e.tier, e.name, e.mesh, tostring(mesh):sub(1, 140)))
	end
end

-- Préchargement : chaque MeshPart (mesh + texture) doit finir en « Success ».
local toPreload = {}
for _, byName in templates do
	for _, mesh in byName do
		mesh.Parent = workspace
		table.insert(toPreload, mesh)
	end
end
local preloadOk, preloadFailed = 0, 0
ContentProvider:PreloadAsync(toPreload, function(contentId, status)
	if status == Enum.AssetFetchStatus.Success then
		preloadOk += 1
	else
		preloadFailed += 1
		table.insert(failures, ("Preload %s : %s"):format(tostring(contentId), tostring(status)))
	end
end)

-- Vérification visuelle : rangées de modèles devant la caméra (PC en haut, mobile en bas).
local origin = Vector3.new(0, 20, 0)
local names = { "BB_WALL_04_StoneMossy", "BB_WALL_01_StoneLight", "BB_DESTR_01_CrateWood", "BB_DESTR_03_BushFlowers", "BB_FLOOR_01_Grass", "BB_DECOR_05_FlowerCluster" }
for rowIndex, tier in { "pc", "mobile" } do
	for i, name in names do
		local mesh = templates[tier] and templates[tier][name]
		if mesh then
			mesh.Position = origin + Vector3.new((i - 3.5) * 6, (rowIndex == 1 and 4 or -4), 0)
			mesh.Parent = workspace
		end
	end
end
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = CFrame.lookAt(origin + Vector3.new(0, 0, 26), origin)

local gui = Instance.new("ScreenGui")
gui.Name = "AssetProbeGui"
gui.ResetOnSpawn = false
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 0, 120)
label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
label.BackgroundTransparency = 0.2
label.TextColor3 = Color3.new(1, 1, 1)
label.TextScaled = true
label.Font = Enum.Font.Code
label.Text = ("%s | création : %d OK / %d échec | préchargement : %d OK / %d échec | plus lent %.2f s\nHaut = PC, bas = mobile"):format(
	platform, created, createFailed, preloadOk, preloadFailed, worst)
label.Parent = gui
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

report:FireServer({
	platform = platform, tier = platform == "tactile" and "mobile" or "pc",
	created = created, createFailed = createFailed, preloadOk = preloadOk, preloadFailed = preloadFailed,
	worst = worst, failures = failures,
})
print("[AssetProbe] terminé :", label.Text)
