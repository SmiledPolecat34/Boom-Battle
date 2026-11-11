--!strict
-- Découpe MODULAIRE d'une explosion en croix (calcul PUR, partagé client / tests, aucune logique de jeu) : à partir des cases
-- touchées, des cases d'origine (bombes qui explosent) et des cases de caisses détruites, classe chaque case en :
--   center   : case d'une bombe qui explose (gerbe principale)
--   junction : case touchée par deux bras qui se croisent sans être une origine (réaction en chaîne) : traitée comme un petit centre
--   segment  : case au milieu d'un bras (voisins de part et d'autre)
--   end      : bout d'un bras (un seul voisin) ; `dir` = direction du bras, du centre vers le bout
--   impact   : case de caisse détruite (le bras s'arrête dessus) ; `dir` = direction du bras si connue
-- Le serveur reste SEUL juge des cases dangereuses : ce découpage ne sert qu'à choisir quel module visuel poser sur chaque case.
-- Les cases viennent du résolveur d'explosion ; rien n'est ajouté ni retiré ici (le nombre de cases en sortie = en entrée).

local Types = require(script.Parent.Types)

export type Kind = "center" | "junction" | "segment" | "end" | "impact"
export type Piece = {
	cell: Types.Cell,
	kind: Kind,
	dir: { x: number, y: number }, -- direction du bras (0, 0 pour un centre)
	axis: string, -- "x", "y" ou "none"
}

local ExplosionLayout = {}

local function key(x: number, y: number): string
	return x .. ":" .. y
end

local function isCell(value: any): boolean
	return typeof(value) == "table" and typeof(value.x) == "number" and typeof(value.y) == "number"
end

-- cells / origins / crates : listes de { x, y } (valeurs invalides ignorées). Retourne une pièce par case valide, sans doublon,
-- dans l'ordre d'entrée.
function ExplosionLayout.classify(cells: any, origins: any, crates: any): { Piece }
	local pieces: { Piece } = {}
	if typeof(cells) ~= "table" then
		return pieces
	end
	local inBlast: { [string]: boolean } = {}
	local ordered: { Types.Cell } = {}
	for _, cell in cells do
		if isCell(cell) and not inBlast[key(cell.x, cell.y)] then
			inBlast[key(cell.x, cell.y)] = true
			table.insert(ordered, { x = cell.x, y = cell.y })
		end
	end
	local isOrigin: { [string]: boolean } = {}
	if typeof(origins) == "table" then
		for _, cell in origins do
			if isCell(cell) then
				isOrigin[key(cell.x, cell.y)] = true
			end
		end
	end
	local isCrate: { [string]: boolean } = {}
	if typeof(crates) == "table" then
		for _, cell in crates do
			if isCell(cell) then
				isCrate[key(cell.x, cell.y)] = true
			end
		end
	end
	-- Sans origine connue (ancien serveur) : la case qui a le plus de voisins sert de centre.
	if next(isOrigin) == nil and #ordered > 0 then
		local best, bestCount = ordered[1], -1
		for _, cell in ordered do
			local n = 0
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				if inBlast[key(cell.x + d[1], cell.y + d[2])] then
					n += 1
				end
			end
			if n > bestCount then
				best, bestCount = cell, n
			end
		end
		isOrigin[key(best.x, best.y)] = true
	end

	for _, cell in ordered do
		local k = key(cell.x, cell.y)
		local east = inBlast[key(cell.x + 1, cell.y)] == true
		local west = inBlast[key(cell.x - 1, cell.y)] == true
		local north = inBlast[key(cell.x, cell.y + 1)] == true
		local south = inBlast[key(cell.x, cell.y - 1)] == true
		local horizontal = east and west
		local vertical = north and south
		local kind: Kind
		local dir = { x = 0, y = 0 }
		local axis = "none"
		if isOrigin[k] then
			kind = "center"
		elseif isCrate[k] then
			kind = "impact"
		elseif horizontal and vertical then
			kind = "junction"
		elseif horizontal then
			kind, axis = "segment", "x"
		elseif vertical then
			kind, axis = "segment", "y"
		else
			kind = "end"
		end
		-- Direction du bras pour un bout / un impact : opposée à l'unique voisin (du centre vers l'extérieur).
		if kind == "end" or kind == "impact" then
			if west and not east then
				dir, axis = { x = 1, y = 0 }, "x"
			elseif east and not west then
				dir, axis = { x = -1, y = 0 }, "x"
			elseif south and not north then
				dir, axis = { x = 0, y = 1 }, "y"
			elseif north and not south then
				dir, axis = { x = 0, y = -1 }, "y"
			end
		end
		table.insert(pieces, { cell = cell, kind = kind, dir = dir, axis = axis })
	end
	return pieces
end

return table.freeze(ExplosionLayout)
