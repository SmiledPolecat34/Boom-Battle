--!strict
-- Calcul PUR d'une explosion en croix, réactions en chaîne comprises. Ne modifie ni la grille ni les bombes :
-- le résultat est calculé sur un « instantané » pour que toutes les bombes d'une même chaîne explosent ensemble.
--
-- Règles : un pilier ou un mur bloque la propagation (sans être touché) ; une caisse est touchée, détruite puis
-- bloque la propagation ; une bombe touchée rejoint la chaîne mais ne bloque pas la propagation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GridService = require(script.Parent.GridService)

export type BombRecord = {
	cell: Types.Cell,
	range: number,
	[string]: any, -- champs propres à BombService (propriétaire, Part, ...)
}

export type Result = {
	cells: { Types.Cell }, -- toutes les cases touchées (sans doublon), origines incluses
	crates: { Types.Cell }, -- caisses à détruire
	bombs: { BombRecord }, -- bombes qui explosent dans la chaîne, dans l'ordre de détonation
}

local DIRECTIONS = {
	{ x = 1, y = 0 },
	{ x = -1, y = 0 },
	{ x = 0, y = 1 },
	{ x = 0, y = -1 },
}

local ExplosionResolver = {}

-- bombsByKey : bombes vivantes, indexées par grid:key(x, y). first : bombe qui déclenche la chaîne.
function ExplosionResolver.resolve(
	grid: GridService.GridService,
	bombsByKey: { [number]: BombRecord },
	first: BombRecord
): Result
	local cells: { Types.Cell } = {}
	local seenCells: { [number]: boolean } = {}
	local crates: { Types.Cell } = {}
	local seenCrates: { [number]: boolean } = {}
	local detonated: { BombRecord } = {}
	local queued: { [BombRecord]: boolean } = { [first] = true }
	local queue: { BombRecord } = { first }
	local head = 1

	local function addCell(x: number, y: number)
		local key = grid:key(x, y)
		if not seenCells[key] then
			seenCells[key] = true
			table.insert(cells, { x = x, y = y })
		end
	end

	while head <= #queue do
		local bomb = queue[head]
		head += 1
		table.insert(detonated, bomb)
		addCell(bomb.cell.x, bomb.cell.y)

		for _, d in DIRECTIONS do
			for step = 1, bomb.range do
				local x, y = bomb.cell.x + d.x * step, bomb.cell.y + d.y * step
				local kind = grid:getKind(x, y)
				if kind == "PILLAR" or kind == "BORDER" then
					break
				end
				addCell(x, y)

				local key = grid:key(x, y)
				local other = bombsByKey[key]
				if other and not queued[other] then
					queued[other] = true
					table.insert(queue, other)
				end

				if kind == "CRATE" then
					if not seenCrates[key] then
						seenCrates[key] = true
						table.insert(crates, { x = x, y = y })
					end
					break
				end
			end
		end
	end

	return { cells = cells, crates = crates, bombs = detonated }
end

return ExplosionResolver
