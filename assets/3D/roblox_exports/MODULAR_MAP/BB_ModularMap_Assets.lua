-- BB_ModularMap_Assets : description des modèles modulaires de Boom Battle (ModuleScript)
-- NON TESTÉ dans Roblox Studio. Généré depuis Blender (BOOM_BATTLE_Environment.blend).
local M = {}

M.CELL_STUDS = 4
M.PLAY_SURFACE_Y = 0   -- face haute du sol ; les obstacles et décors y sont posés
M.CHECKER = { "BB_FLOOR_01_Grass", "BB_FLOOR_08_GrassDark" }  -- alternance en damier

M.Assets = {
	["BB_FLOOR_01_Grass"] = {
		category = "floor", weight = 6,
		size = Vector3.new(4, 0.954, 4), pivotOffset = Vector3.new(0, 0.023, -0),
		sizeMobile = Vector3.new(4, 0.954, 4), pivotOffsetMobile = Vector3.new(0, 0.023, -0),
		tris = { pc = 172, mobile = 140 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_FLOOR_02_GrassFlowers"] = {
		category = "floor", weight = 2,
		size = Vector3.new(4, 0.963, 4), pivotOffset = Vector3.new(0, 0.018, -0),
		sizeMobile = Vector3.new(3.935, 0.963, 3.935), pivotOffsetMobile = Vector3.new(0, 0.018, -0),
		tris = { pc = 592, mobile = 140 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_FLOOR_03_Sand"] = {
		category = "floor", weight = 2,
		size = Vector3.new(4, 0.632, 4), pivotOffset = Vector3.new(0, 0.184, -0),
		sizeMobile = Vector3.new(3.953, 0.632, 3.953), pivotOffsetMobile = Vector3.new(0, 0.184, -0),
		tris = { pc = 236, mobile = 140 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_FLOOR_04_DirtCracked"] = {
		category = "floor", weight = 1,
		size = Vector3.new(4, 0.627, 4), pivotOffset = Vector3.new(0, 0.187, -0),
		sizeMobile = Vector3.new(3.953, 0.627, 3.953), pivotOffsetMobile = Vector3.new(0, 0.187, -0),
		tris = { pc = 240, mobile = 140 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_FLOOR_05_SandRocks"] = {
		category = "floor", weight = 1,
		size = Vector3.new(4, 1.319, 4), pivotOffset = Vector3.new(0, -0.16, -0),
		sizeMobile = Vector3.new(3.953, 1.319, 3.953), pivotOffsetMobile = Vector3.new(0, -0.16, -0),
		tris = { pc = 216, mobile = 140 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_FLOOR_06_Cobble"] = {
		category = "floor", weight = 1,
		size = Vector3.new(4, 0.64, 4), pivotOffset = Vector3.new(0, 0.18, -0),
		sizeMobile = Vector3.new(3.953, 0.64, 3.953), pivotOffsetMobile = Vector3.new(0, 0.18, -0),
		tris = { pc = 400, mobile = 140 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_FLOOR_07_GrassDirtMix"] = {
		category = "floor", weight = 2,
		size = Vector3.new(4, 0.952, 4), pivotOffset = Vector3.new(0, 0.024, -0),
		sizeMobile = Vector3.new(3.953, 0.952, 4), pivotOffsetMobile = Vector3.new(0, 0.024, -0),
		tris = { pc = 208, mobile = 140 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_FLOOR_08_GrassDark"] = {
		category = "floor", weight = 6,
		size = Vector3.new(4, 0.949, 4), pivotOffset = Vector3.new(0, 0.026, -0),
		sizeMobile = Vector3.new(3.953, 0.949, 3.953), pivotOffsetMobile = Vector3.new(0, 0.026, -0),
		tris = { pc = 188, mobile = 140 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_WALL_01_StoneLight"] = {
		category = "wall_indestructible", weight = 5,
		size = Vector3.new(3.84, 4, 3.84), pivotOffset = Vector3.new(0, -2, -0),
		sizeMobile = Vector3.new(3.84, 4, 3.84), pivotOffsetMobile = Vector3.new(0, -2, -0),
		tris = { pc = 484, mobile = 300 },
		destructible = false, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_WALL_02_StoneDark"] = {
		category = "wall_indestructible", weight = 3,
		size = Vector3.new(3.84, 4, 3.84), pivotOffset = Vector3.new(0, -2, -0),
		sizeMobile = Vector3.new(3.84, 4, 3.84), pivotOffsetMobile = Vector3.new(0, -2, -0),
		tris = { pc = 484, mobile = 300 },
		destructible = false, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_WALL_03_StoneCracked"] = {
		category = "wall_indestructible", weight = 2,
		size = Vector3.new(3.91, 4, 3.98), pivotOffset = Vector3.new(-0.035, -2, -0),
		sizeMobile = Vector3.new(3.915, 4.018, 4.004), pivotOffsetMobile = Vector3.new(-0.036, -1.994, -0.012),
		tris = { pc = 3628, mobile = 900 },
		destructible = false, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_WALL_04_StoneMossy"] = {
		category = "wall_indestructible", weight = 2,
		size = Vector3.new(3.98, 4.738, 3.98), pivotOffset = Vector3.new(0, -2.369, -0),
		sizeMobile = Vector3.new(4.039, 4.795, 4.024), pivotOffsetMobile = Vector3.new(-0.022, -2.34, -0.022),
		tris = { pc = 4528, mobile = 900 },
		destructible = false, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DESTR_01_CrateWood"] = {
		category = "obstacle_destructible", weight = 4,
		size = Vector3.new(3.6, 3.6, 3.6), pivotOffset = Vector3.new(0, -1.8, -0),
		sizeMobile = Vector3.new(3.6, 3.6, 3.6), pivotOffsetMobile = Vector3.new(0, -1.8, -0),
		tris = { pc = 836, mobile = 450 },
		destructible = true, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DESTR_02_CrateDark"] = {
		category = "obstacle_destructible", weight = 3,
		size = Vector3.new(3.6, 3.6, 3.6), pivotOffset = Vector3.new(0, -1.8, -0),
		sizeMobile = Vector3.new(3.6, 3.6, 3.6), pivotOffsetMobile = Vector3.new(0, -1.8, -0),
		tris = { pc = 836, mobile = 450 },
		destructible = true, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DESTR_03_BushFlowers"] = {
		category = "obstacle_destructible", weight = 3,
		size = Vector3.new(3.72, 3.67, 3.72), pivotOffset = Vector3.new(0, -1.835, -0),
		sizeMobile = Vector3.new(3.713, 3.551, 3.753), pivotOffsetMobile = Vector3.new(0.01, -1.81, 0.03),
		tris = { pc = 944, mobile = 450 },
		destructible = true, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DESTR_04_HayBale"] = {
		category = "obstacle_destructible", weight = 2,
		size = Vector3.new(3.72, 4.445, 3.72), pivotOffset = Vector3.new(0, -2.223, -0),
		sizeMobile = Vector3.new(3.69, 4.445, 3.72), pivotOffsetMobile = Vector3.new(-0.015, -2.223, -0),
		tris = { pc = 1405, mobile = 600 },
		destructible = true, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DESTR_05_RockBrown"] = {
		category = "obstacle_destructible", weight = 2,
		size = Vector3.new(3.72, 3.55, 3.72), pivotOffset = Vector3.new(0, -1.775, -0),
		sizeMobile = Vector3.new(3.723, 3.551, 3.72), pivotOffsetMobile = Vector3.new(0.002, -1.774, -0),
		tris = { pc = 1072, mobile = 550 },
		destructible = true, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DESTR_06_RockGrey"] = {
		category = "obstacle_destructible", weight = 2,
		size = Vector3.new(3.72, 3.79, 3.72), pivotOffset = Vector3.new(0, -1.895, -0),
		sizeMobile = Vector3.new(3.723, 3.758, 3.719), pivotOffsetMobile = Vector3.new(0.001, -1.866, 0.004),
		tris = { pc = 1447, mobile = 549 },
		destructible = true, blocksExplosion = true, blocksMovement = true,
		collision = { CanCollide = true, CanQuery = true, CanTouch = true, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DECOR_01_GrassBush"] = {
		category = "decor_ground", weight = 6,
		size = Vector3.new(1.189, 0.716, 1.026), pivotOffset = Vector3.new(0.01, -0.358, 0.074),
		sizeMobile = Vector3.new(1.189, 0.716, 1.026), pivotOffsetMobile = Vector3.new(0.01, -0.358, 0.074),
		tris = { pc = 80, mobile = 80 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = false, CanQuery = false, CanTouch = false, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DECOR_02_GrassBladesA"] = {
		category = "decor_ground", weight = 4,
		size = Vector3.new(0.397, 0.982, 0.428), pivotOffset = Vector3.new(-0.05, -0.491, 0.045),
		sizeMobile = Vector3.new(0.397, 0.982, 0.428), pivotOffsetMobile = Vector3.new(-0.05, -0.491, 0.045),
		tris = { pc = 24, mobile = 24 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = false, CanQuery = false, CanTouch = false, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DECOR_03_GrassBladesB"] = {
		category = "decor_ground", weight = 3,
		size = Vector3.new(0.584, 1.239, 0.691), pivotOffset = Vector3.new(-0.005, -0.619, -0.013),
		sizeMobile = Vector3.new(0.584, 1.239, 0.691), pivotOffsetMobile = Vector3.new(-0.005, -0.619, -0.013),
		tris = { pc = 32, mobile = 32 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = false, CanQuery = false, CanTouch = false, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DECOR_04_FlowerWhite"] = {
		category = "decor_ground", weight = 2,
		size = Vector3.new(0.954, 0.909, 0.834), pivotOffset = Vector3.new(0.003, -0.455, 0),
		sizeMobile = Vector3.new(0.936, 0.909, 0.86), pivotOffsetMobile = Vector3.new(0, -0.455, 0),
		tris = { pc = 212, mobile = 118 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = false, CanQuery = false, CanTouch = false, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DECOR_05_FlowerCluster"] = {
		category = "decor_ground", weight = 2,
		size = Vector3.new(1.133, 0.693, 1.094), pivotOffset = Vector3.new(-0.004, -0.346, 0.091),
		sizeMobile = Vector3.new(1.123, 0.679, 1.101), pivotOffsetMobile = Vector3.new(0.001, -0.34, 0.094),
		tris = { pc = 412, mobile = 120 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = false, CanQuery = false, CanTouch = false, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DECOR_06_Pebble"] = {
		category = "decor_ground", weight = 3,
		size = Vector3.new(1.067, 0.537, 0.889), pivotOffset = Vector3.new(0.119, -0.268, -0.021),
		sizeMobile = Vector3.new(1.067, 0.537, 0.889), pivotOffsetMobile = Vector3.new(0.119, -0.268, -0.021),
		tris = { pc = 40, mobile = 40 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = false, CanQuery = false, CanTouch = false, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DECOR_07_PebbleGroup"] = {
		category = "decor_ground", weight = 2,
		size = Vector3.new(1.344, 0.46, 0.971), pivotOffset = Vector3.new(0.033, -0.23, 0.066),
		sizeMobile = Vector3.new(1.344, 0.46, 0.971), pivotOffsetMobile = Vector3.new(0.033, -0.23, 0.066),
		tris = { pc = 80, mobile = 80 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = false, CanQuery = false, CanTouch = false, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
	["BB_DECOR_08_LeafPlant"] = {
		category = "decor_ground", weight = 2,
		size = Vector3.new(1.324, 0.555, 1.243), pivotOffset = Vector3.new(0.008, -0.278, -0.014),
		sizeMobile = Vector3.new(1.292, 0.578, 1.243), pivotOffsetMobile = Vector3.new(0.023, -0.286, -0.014),
		tris = { pc = 216, mobile = 120 },
		destructible = false, blocksExplosion = false, blocksMovement = false,
		collision = { CanCollide = false, CanQuery = false, CanTouch = false, CollisionFidelity = Enum.CollisionFidelity.Box },
	},
}

function M.byCategory(category)
	local list = {}
	for name, a in pairs(M.Assets) do
		if a.category == category then table.insert(list, name) end
	end
	table.sort(list)
	return list
end

-- tirage pondéré dans une catégorie (rng = Random.new(seed))
function M.pick(category, rng)
	local names, total = M.byCategory(category), 0
	for _, n in ipairs(names) do total += M.Assets[n].weight end
	local r = rng:NextNumber() * total
	for _, n in ipairs(names) do
		r -= M.Assets[n].weight
		if r <= 0 then return n end
	end
	return names[#names]
end

-- centre de la case (gx, gz) à partir de l'origine de la grille
function M.cellCenter(origin, gx, gz)
	return origin + Vector3.new(gx * M.CELL_STUDS, 0, gz * M.CELL_STUDS)
end

-- place un MeshPart importé : son pivot (origine Blender) est amené sur worldPos
function M.place(meshPart, worldPos, useMobile)
	local a = M.Assets[meshPart.Name]
	meshPart.PivotOffset = CFrame.new(useMobile and a.pivotOffsetMobile or a.pivotOffset)
	meshPart:PivotTo(CFrame.new(worldPos))
	meshPart.Anchored = true
	meshPart.CanCollide, meshPart.CanQuery, meshPart.CanTouch = a.collision.CanCollide, a.collision.CanQuery, a.collision.CanTouch
	meshPart.CollisionFidelity = a.collision.CollisionFidelity
end

return M
