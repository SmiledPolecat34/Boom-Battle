--!strict
-- Version allégée des modèles de l'arène pour les appareils tactiles.
-- Le serveur construit l'arène avec les modèles PC (ReplicatedStorage.MapAssets) et étiquette chaque pièce (attribut BBAsset).
-- Sur un appareil tactile sans clavier, ce module affiche à la place le modèle du même nom de ReplicatedStorage.MapAssetsMobile
-- (beaucoup moins de triangles) et masque la pièce d'origine EN LOCAL uniquement : rien ne change côté serveur, qui garde seul
-- l'autorité (positions, destruction des obstacles). Quand le serveur détruit la pièce, sa version allégée disparaît aussi.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ASSET_FOLDER = "MapAssetsMobile"

local MobileAssets = {}

-- Test uniquement : force le rendu allégé sur un poste de bureau.
MobileAssets.forceLite = false

local templates: { [string]: MeshPart } = {}
local started = false

local function isLite(): boolean
	return MobileAssets.forceLite or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

local function loadTemplates(): boolean
	table.clear(templates)
	local root = ReplicatedStorage:FindFirstChild(ASSET_FOLDER)
	if not root then
		return false
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("MeshPart") then
			templates[descendant.Name] = descendant
		end
	end
	return next(templates) ~= nil
end

-- Remplace l'affichage d'une pièce du serveur par sa version allégée. Retourne la copie ou nil (aucun modèle correspondant).
function MobileAssets.swap(part: MeshPart): MeshPart?
	local name = part:GetAttribute("BBAsset")
	if typeof(name) ~= "string" or part:GetAttribute("BBLite") == true then
		return nil
	end
	local template = templates[name]
	if not template then
		return nil
	end
	local lite = template:Clone()
	lite.Name = part.Name .. "_Lite"
	lite.Anchored = true
	lite.CanCollide = part.CanCollide
	lite.CanQuery = part.CanQuery
	lite.CanTouch = part.CanTouch
	lite.CastShadow = part.CastShadow
	lite:SetAttribute("BBLite", true)
	-- Même convention que le serveur : seule la translation du pivot compte ; la pièce d'origine donne position et lacet.
	lite.PivotOffset = CFrame.new(template.PivotOffset.Position)
	lite:PivotTo(part:GetPivot())
	lite.Parent = part.Parent

	-- L'original reste en place (cycle de vie géré par le serveur) mais n'est plus ni visible ni solide sur ce client.
	part.LocalTransparencyModifier = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part:SetAttribute("BBLite", true)

	part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			lite:Destroy()
		end
	end)
	return lite
end

local function scan(arena: Instance)
	for _, descendant in arena:GetDescendants() do
		if descendant:IsA("MeshPart") and descendant:GetAttribute("BBAsset") ~= nil then
			MobileAssets.swap(descendant)
		end
	end
end

function MobileAssets.start()
	if started then
		return
	end
	started = true
	if not isLite() then
		return
	end
	if not loadTemplates() then
		warn("[MobileAssets] ReplicatedStorage." .. ASSET_FOLDER .. " absent : modèles PC conservés.")
		return
	end
	local function watch(arena: Instance)
		scan(arena)
		arena.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("MeshPart") then
				-- l'attribut est posé avant le parentage côté serveur ; on laisse tout de même la pièce finir de se répliquer
				task.defer(function()
					if descendant.Parent and descendant:GetAttribute("BBAsset") ~= nil then
						MobileAssets.swap(descendant)
					end
				end)
			end
		end)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Arena" then
			watch(child)
		end
	end)
	local existing = workspace:FindFirstChild("Arena")
	if existing then
		watch(existing)
	end
end

-- Pour les tests : démarre le remplacement quelle que soit la plateforme.
function MobileAssets.startForced()
	MobileAssets.forceLite = true
	started = false
	MobileAssets.start()
end

return MobileAssets
