--!strict
-- État logique de la grille et recherche de chemin. Aucune dépendance au Workspace : testable seul.
-- Coordonnées de cellule 1-indexées ; la cellule (x, y) est centrée en
-- origin + ((x - 0.5) * cellSize, 0, (y - 0.5) * cellSize).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local DIRECTIONS = {
	{ x = 1, y = 0 },
	{ x = -1, y = 0 },
	{ x = 0, y = 1 },
	{ x = 0, y = -1 },
}

local GridService = {}
GridService.__index = GridService

export type GridService = typeof(setmetatable(
	{} :: {
		layout: Types.MapLayout,
		size: number,
		cellSize: number,
		origin: Vector3, -- coin de la zone jouable (cellule 1,1)
		bombs: { [number]: boolean }, -- cases occupées par une bombe, clé : key(x, y)
	},
	GridService
))

function GridService.new(layout: Types.MapLayout, cellSize: number, origin: Vector3): GridService
	return setmetatable({
		layout = layout,
		size = layout.size,
		cellSize = cellSize,
		origin = origin,
		bombs = {},
	}, GridService)
end

function GridService.key(self: GridService, x: number, y: number): number
	return (y - 1) * self.size + x
end

function GridService.setBomb(self: GridService, x: number, y: number, present: boolean)
	self.bombs[self:key(x, y)] = if present then true else nil
end

function GridService.hasBomb(self: GridService, x: number, y: number): boolean
	return self.bombs[self:key(x, y)] == true
end

function GridService.inBounds(self: GridService, x: number, y: number): boolean
	return x >= 1 and x <= self.size and y >= 1 and y <= self.size
end

function GridService.getKind(self: GridService, x: number, y: number): Types.CellKind
	if not self:inBounds(x, y) then
		return "BORDER"
	end
	return self.layout.cells[y][x]
end

function GridService.setKind(self: GridService, x: number, y: number, kind: Types.CellKind)
	if self:inBounds(x, y) then
		self.layout.cells[y][x] = kind
	end
end

-- Franchissable à pied : case vide sans bombe.
function GridService.isWalkable(self: GridService, x: number, y: number): boolean
	return self:getKind(x, y) == "EMPTY" and not self:hasBomb(x, y)
end

function GridService.cellToWorld(self: GridService, cell: Types.Cell, height: number?): Vector3
	return self.origin
		+ Vector3.new((cell.x - 0.5) * self.cellSize, height or 0, (cell.y - 0.5) * self.cellSize)
end

-- Retourne nil si la position est en dehors de la zone jouable.
function GridService.worldToCell(self: GridService, position: Vector3): Types.Cell?
	local x = math.floor((position.X - self.origin.X) / self.cellSize) + 1
	local y = math.floor((position.Z - self.origin.Z) / self.cellSize) + 1
	if not self:inBounds(x, y) then
		return nil
	end
	return { x = x, y = y }
end

-- Plus court chemin (parcours en largeur, déplacements orthogonaux, coût uniforme).
-- Retourne les cellules à parcourir SANS la case de départ, AVEC la cible ; {} si départ == cible ;
-- nil si la cible n'est pas franchissable ou n'est pas atteignable.
function GridService.findPath(self: GridService, from: Types.Cell, to: Types.Cell): { Types.Cell }?
	if not self:isWalkable(to.x, to.y) then
		return nil
	end
	if from.x == to.x and from.y == to.y then
		return {}
	end

	-- Parcours en largeur sur des clés numériques : aucune table allouée par case visitée.
	local size = self.size
	local startKey = (from.y - 1) * size + from.x
	local targetKey = (to.y - 1) * size + to.x
	local parent: { [number]: number } = { [startKey] = -1 }
	local queue: { number } = { startKey }
	local head, tail = 1, 1

	while head <= tail do
		local currentKey = queue[head]
		head += 1
		local cx = (currentKey - 1) % size + 1
		local cy = (currentKey - 1) // size + 1
		for _, d in DIRECTIONS do
			local nx, ny = cx + d.x, cy + d.y
			if self:isWalkable(nx, ny) then
				local key = (ny - 1) * size + nx
				if parent[key] == nil then
					parent[key] = currentKey
					if key == targetKey then
						-- Reconstruction à rebours puis inversion (évite table.insert(path, 1, ...) en O(n²)).
						local reversed: { Types.Cell } = {}
						local walk = key
						while walk ~= startKey do
							table.insert(reversed, { x = (walk - 1) % size + 1, y = (walk - 1) // size + 1 })
							walk = parent[walk]
						end
						local path: { Types.Cell } = table.create(#reversed)
						for i = #reversed, 1, -1 do
							table.insert(path, reversed[i])
						end
						return path
					end
					tail += 1
					queue[tail] = key
				end
			end
		end
	end
	return nil
end

return GridService
