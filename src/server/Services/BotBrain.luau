--!strict
-- Cerveau des bots : fonction PURE (aucune Part, aucun Roblox) qui, d'après la grille et la situation, choisit une
-- action : fuir, poser une bombe, aller vers une cible ou attendre. Testable seule.
--
-- Priorités : 1) sortir d'une zone dangereuse ; 2) poser une bombe si elle sert (caisse ou ennemi dans la ligne de tir)
-- ET qu'une issue sûre existe après la pose ; 3) aller vers la case la plus proche d'où poser une bombe ; 4) rejoindre
-- un ennemi ; 5) attendre. Un bot ne se pose jamais de bombe sans issue : il ne se suicide pas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GridService = require(script.Parent.GridService)

export type Context = {
	cell: Types.Cell,
	range: number,
	canPlaceBomb: boolean,
	danger: { [number]: boolean }, -- cases menacées (clé grid:key)
	enemies: { Types.Cell },
	rng: Random?, -- facultatif : hésitation occasionnelle pour paraître moins mécanique
}

export type Action = {
	kind: "move" | "bomb" | "wait",
	cell: Types.Cell?,
}

local BotBrain = {}

local DIRECTIONS = {
	{ x = 1, y = 0 },
	{ x = -1, y = 0 },
	{ x = 0, y = 1 },
	{ x = 0, y = -1 },
}

local ESCAPE_DEPTH = 6 -- cases max pour s'éloigner d'une bombe qu'on vient de poser (la mèche dure 2 s)
local FLEE_DEPTH = 12
local SEEK_DEPTH = 26
local HESITATION_CHANCE = 0.06

-- Cases touchées par une bombe posée en `cell` (croix, arrêtée par piliers, murs et caisses).
function BotBrain.blastKeys(grid: GridService.GridService, cell: Types.Cell, range: number): { [number]: boolean }
	local keys: { [number]: boolean } = { [grid:key(cell.x, cell.y)] = true }
	for _, d in DIRECTIONS do
		for step = 1, range do
			local x, y = cell.x + d.x * step, cell.y + d.y * step
			local kind = grid:getKind(x, y)
			if kind == "PILLAR" or kind == "BORDER" then
				break
			end
			keys[grid:key(x, y)] = true
			if kind == "CRATE" then
				break
			end
		end
	end
	return keys
end

-- Une bombe posée ici toucherait-elle une caisse ou un ennemi ?
function BotBrain.isWorthBombing(
	grid: GridService.GridService,
	cell: Types.Cell,
	range: number,
	enemyKeys: { [number]: boolean }
): boolean
	for _, d in DIRECTIONS do
		for step = 1, range do
			local x, y = cell.x + d.x * step, cell.y + d.y * step
			local kind = grid:getKind(x, y)
			if kind == "PILLAR" or kind == "BORDER" then
				break
			end
			if kind == "CRATE" or enemyKeys[grid:key(x, y)] then
				return true
			end
		end
	end
	return false
end

-- Parcours en largeur depuis `from` (exclu). Retourne la première case vérifiant `goal`, et sa distance, ou nil.
local function search(
	grid: GridService.GridService,
	from: Types.Cell,
	maxDepth: number,
	passable: (x: number, y: number) -> boolean,
	goal: (x: number, y: number) -> boolean
): (Types.Cell?, number)
	local size = grid.size
	local startKey = (from.y - 1) * size + from.x
	local depthOf: { [number]: number } = { [startKey] = 0 }
	local queue: { number } = { startKey }
	local head, tail = 1, 1
	while head <= tail do
		local currentKey = queue[head]
		head += 1
		local depth = depthOf[currentKey]
		if depth < maxDepth then
			local cx = (currentKey - 1) % size + 1
			local cy = (currentKey - 1) // size + 1
			for _, d in DIRECTIONS do
				local nx, ny = cx + d.x, cy + d.y
				if passable(nx, ny) then
					local key = (ny - 1) * size + nx
					if depthOf[key] == nil then
						depthOf[key] = depth + 1
						if goal(nx, ny) then
							return { x = nx, y = ny }, depth + 1
						end
						tail += 1
						queue[tail] = key
					end
				end
			end
		end
	end
	return nil, 0
end

-- Existe-t-il, après la pose d'une bombe ici, une case sûre atteignable en peu de pas ?
function BotBrain.hasEscape(
	grid: GridService.GridService,
	cell: Types.Cell,
	range: number,
	danger: { [number]: boolean }
): boolean
	local blast = BotBrain.blastKeys(grid, cell, range)
	local function walkable(x: number, y: number): boolean
		return grid:isWalkable(x, y)
	end
	local function safe(x: number, y: number): boolean
		local key = grid:key(x, y)
		return not blast[key] and not danger[key]
	end
	local found = search(grid, cell, ESCAPE_DEPTH, walkable, safe)
	return found ~= nil
end

function BotBrain.decide(grid: GridService.GridService, context: Context): Action
	local cell = context.cell
	local selfKey = grid:key(cell.x, cell.y)

	local function walkable(x: number, y: number): boolean
		return grid:isWalkable(x, y)
	end
	local function safeCell(x: number, y: number): boolean
		return not context.danger[grid:key(x, y)]
	end

	-- 1. Fuir : on peut traverser des cases dangereuses pour sortir, mais le but est une case sûre.
	if context.danger[selfKey] then
		local target = search(grid, cell, FLEE_DEPTH, walkable, safeCell)
		if target then
			return { kind = "move", cell = target }
		end
		return { kind = "wait" }
	end

	if context.rng and context.rng:NextNumber() < HESITATION_CHANCE then
		return { kind = "wait" }
	end

	local enemyKeys: { [number]: boolean } = {}
	for _, enemy in context.enemies do
		enemyKeys[grid:key(enemy.x, enemy.y)] = true
	end

	-- 2. Poser une bombe ici ?
	if context.canPlaceBomb and BotBrain.isWorthBombing(grid, cell, context.range, enemyKeys) then
		if BotBrain.hasEscape(grid, cell, context.range, context.danger) then
			return { kind = "bomb" }
		end
	end

	-- 3. Aller vers la plus proche case sûre d'où une bombe serait utile ET sans danger pour soi.
	local function safeWalkable(x: number, y: number): boolean
		return grid:isWalkable(x, y) and not context.danger[grid:key(x, y)]
	end
	if context.canPlaceBomb then
		local spot = search(grid, cell, SEEK_DEPTH, safeWalkable, function(x: number, y: number): boolean
			local candidate = { x = x, y = y }
			return BotBrain.isWorthBombing(grid, candidate, context.range, enemyKeys)
				and BotBrain.hasEscape(grid, candidate, context.range, context.danger)
		end)
		if spot then
			return { kind = "move", cell = spot }
		end
	end

	-- 4. Rejoindre un ennemi : case libre voisine de l'un d'eux.
	if #context.enemies > 0 then
		local approach = search(grid, cell, SEEK_DEPTH, safeWalkable, function(x: number, y: number): boolean
			for _, d in DIRECTIONS do
				local nx, ny = x + d.x, y + d.y
				-- Hors grille, la clé numérique pourrait désigner une autre case : on vérifie d'abord les bornes.
				if grid:inBounds(nx, ny) and enemyKeys[grid:key(nx, ny)] then
					return true
				end
			end
			return false
		end)
		if approach then
			return { kind = "move", cell = approach }
		end
	end

	return { kind = "wait" }
end

return BotBrain
