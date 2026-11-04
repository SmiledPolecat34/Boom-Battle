--!strict
-- BOOM BATTLE : ancre les pièces importées et applique des collisions simplifiées.
-- À lancer UNE FOIS en mode édition (barre de commande de Studio) ou comme Script serveur.
-- ATTENTION : script généré depuis Blender, NON TESTÉ dans Roblox Studio.
local Workspace = game:GetService("Workspace")
local ROOT_NAME = "BOOM_BATTLE_ENVIRONMENT" -- dossier/modèle qui contient les FBX importés
local root: Instance = Workspace:FindFirstChild(ROOT_NAME) or Workspace

-- Première règle qui correspond au nom de la pièce. "None" = ni collision, ni toucher, ni requête (décor pur).
local RULES = {
	{ "^WALL_.*_Bricks", "None" },
	{ "^WALL_", "Box" },
	{ "^COPING_", "None" },
	{ "^FLOOR_Tiles", "None" },
	{ "^FLOOR_", "Box" },
	{ "^PLATFORM_Stripes", "None" },
	{ "^PLATFORM_DiamondPlate", "None" },
	{ "^PLATFORM_Brackets", "None" },
	{ "^PLATFORM_Seams", "None" },
	{ "^PLATFORM_", "Box" },
	{ "^PAD_%d_Ring", "None" },
	{ "^PAD_%d_Pulse", "None" },
	{ "^PAD_", "Hull" },
	{ "^CRATE_", "Box" },
	{ "^CONTAINER_", "Box" },
	{ "^BOMB_Fuse", "None" },
	{ "^BOMB_Neck", "None" },
	{ "^BOMB_", "Hull" },
	{ "^PIPE_", "None" },
	{ "^SCAFFOLD_.*Deck", "Box" },
	{ "^SCAFFOLD_", "Default" },
	{ "^DEBRIS_", "None" },
	{ "^PROP_", "Box" },
	{ "^TREE_", "None" },
	{ "^PILLAR_", "Box" },
	{ "^STONE_Rubble", "None" },
	{ "^STONE_", "Box" },
	{ "^STEPS_", "Box" },
	{ "^Alcove_Stone_.*Fixing", "None" },
	{ "^Alcove_Stone_", "Box" },
}

local function ruleFor(name: string): string
	for _, r in ipairs(RULES) do
		if string.find(name, r[1]) then return r[2] end
	end
	return "Box"
end

local counts: {[string]: number} = {}
for _, d in ipairs(root:GetDescendants()) do
	if d:IsA("MeshPart") then
		local rule = ruleFor(d.Name)
		d.Anchored = true -- décor statique : sans cela les pièces tombent
		if rule == "None" then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		else
			d.CanCollide = true
			d.CollisionFidelity = (Enum.CollisionFidelity :: any)[rule]
		end
		counts[rule] = (counts[rule] or 0) + 1
	end
end
print("[BoomBattle] collisions appliquées :", counts)
