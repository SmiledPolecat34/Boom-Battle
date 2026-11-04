--!strict
-- Modèles 3D de l'arène importés de Blender (ReplicatedStorage.MapAssets) : détection, tirage pondéré, pose.
-- Aucune règle de jeu ici : MapService décide quoi poser et où ; ce module sait seulement cloner et placer une pièce.
-- Origine de chaque modèle = centre de la case ; son PivotOffset (posé par l'import dans Studio) est conservé :
-- un simple PivotTo place la pièce.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local ModularAssets = {}

local templates: { [string]: MeshPart } = {}
local warnedMissing = false
local warnedOptional: { [string]: boolean } = {}

-- Relit le dossier d'assets (une trentaine de MeshParts : peu coûteux). Appelé avant chaque construction.
local function refresh()
	table.clear(templates)
	local root = ReplicatedStorage:FindFirstChild(MapConfig.Modular.assetsFolder)
	if not root then
		return
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("MeshPart") then
			templates[descendant.Name] = descendant
		end
	end
end

-- Noms exigés par le rendu modulaire (sol, murs, obstacles). Les décors sont facultatifs.
function ModularAssets.requiredNames(): { string }
	local config = MapConfig.Modular
	local names: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(name: string)
		if not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	for _, name in config.floorBase do
		add(name)
	end
	for _, entry in config.floorVariants do
		add(entry.name)
	end
	for _, entry in config.walls do
		add(entry.name)
	end
	for _, entry in config.obstacles do
		add(entry.name)
	end
	return names
end

-- true si le modèle existe dans le dernier dossier lu (voir isAvailable).
function ModularAssets.has(name: string): boolean
	return templates[name] ~= nil
end

-- Relit le dossier ; true si TOUS les modèles obligatoires sont présents. Sinon avertit une seule fois (liste des
-- manquants) et retourne false : MapService retombe alors sur l'ancien rendu en Parts colorées. Prévient aussi, une
-- fois chacun, des décors facultatifs absents (ils sont ignorés).
function ModularAssets.isAvailable(): boolean
	refresh()
	local missing: { string } = {}
	for _, name in ModularAssets.requiredNames() do
		if not templates[name] then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		if not warnedMissing then
			warnedMissing = true
			warn(("[ModularAssets] Modèles manquants dans ReplicatedStorage.%s : %s. Rendu en Parts colorées."):format(
				MapConfig.Modular.assetsFolder,
				table.concat(missing, ", ")
			))
		end
		return false
	end
	warnedMissing = false
	for _, entry in MapConfig.Modular.decor do
		if not templates[entry.name] and not warnedOptional[entry.name] then
			warnedOptional[entry.name] = true
			warn(("[ModularAssets] Décor facultatif absent (ignoré) : %s"):format(entry.name))
		end
	end
	return true
end

-- Tirage pondéré (pur : testable sans Studio). Ne retient que les entrées de poids > 0 et, si `isUsable` est fourni,
-- celles qu'il accepte. Retourne nil si aucune entrée n'est utilisable. Un seul tirage `rng:NextNumber()` par appel.
function ModularAssets.pickWeighted(
	entries: { MapConfig.WeightedAsset },
	rng: Random,
	isUsable: ((string) -> boolean)?
): string?
	local total = 0
	for _, entry in entries do
		if entry.weight > 0 and (isUsable == nil or isUsable(entry.name)) then
			total += entry.weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	local last: string? = nil
	for _, entry in entries do
		if entry.weight > 0 and (isUsable == nil or isUsable(entry.name)) then
			last = entry.name
			roll -= entry.weight
			if roll < 0 then
				return entry.name
			end
		end
	end
	return last
end

-- Clone le modèle, l'ancre et amène son pivot (l'origine Blender : centre de la case, sol à Y = 0) sur `cframe`.
function ModularAssets.place(name: string, cframe: CFrame, parent: Instance): MeshPart
	local template = templates[name]
	assert(template, ("[ModularAssets] modèle inconnu : %s"):format(name))
	local part = template:Clone()
	part.Anchored = true
	part:SetAttribute("BBAsset", name) -- le client mobile s'en sert pour afficher la version allégée
	-- Le PivotOffset importé porte une rotation (axes Blender, Z vers le haut) : on ne garde que sa translation, sinon
	-- la pièce serait couchée. L'orientation reste celle du modèle (debout), `cframe` donne position et lacet.
	part.PivotOffset = CFrame.new(template.PivotOffset.Position)
	part:PivotTo(cframe)
	part.Parent = parent
	return part
end

return ModularAssets
