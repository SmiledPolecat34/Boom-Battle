--!nocheck
-- ExplosionLayout : découpe modulaire d'une explosion en croix (centre, segment, bout, impact, jonction). Pur : le nombre de cases en
-- sortie est EXACTEMENT celui d'entrée (le visuel ne change jamais les cases dangereuses).
local ExplosionLayout = world.module("ExplosionLayout")

local function cross(cx, cy, range)
	local cells = { { x = cx, y = cy } }
	for step = 1, range do
		table.insert(cells, { x = cx + step, y = cy })
		table.insert(cells, { x = cx - step, y = cy })
		table.insert(cells, { x = cx, y = cy + step })
		table.insert(cells, { x = cx, y = cy - step })
	end
	return cells
end

local function byKey(pieces)
	local map = {}
	for _, piece in pieces do
		map[piece.cell.x .. ":" .. piece.cell.y] = piece
	end
	return map
end

describe("ExplosionLayout.classify", function()
	it("croix de portée 2 : 1 centre, 4 segments, 4 bouts, directions vers l'extérieur", function()
		local cells = cross(5, 5, 2)
		local pieces = ExplosionLayout.classify(cells, { { x = 5, y = 5 } }, {})
		expect(#pieces).toBe(#cells)
		local map = byKey(pieces)
		expect(map["5:5"].kind).toBe("center")
		for _, k in { "6:5", "4:5", "5:6", "5:4" } do
			expect(map[k].kind).toBe("segment")
		end
		for _, k in { "7:5", "3:5", "5:7", "5:3" } do
			expect(map[k].kind).toBe("end")
		end
		expect(map["7:5"].dir).toEqual({ x = 1, y = 0 })
		expect(map["3:5"].dir).toEqual({ x = -1, y = 0 })
		expect(map["5:7"].dir).toEqual({ x = 0, y = 1 })
		expect(map["5:3"].dir).toEqual({ x = 0, y = -1 })
		expect(map["6:5"].axis).toBe("x")
		expect(map["5:6"].axis).toBe("y")
	end)

	it("portée 1 : le bout touche directement le centre", function()
		local pieces = ExplosionLayout.classify(cross(2, 2, 1), { { x = 2, y = 2 } }, {})
		local map = byKey(pieces)
		expect(map["2:2"].kind).toBe("center")
		for _, k in { "3:2", "1:2", "2:3", "2:1" } do
			expect(map[k].kind).toBe("end")
		end
	end)

	it("une caisse détruite au bout d'un bras devient un impact orienté vers l'extérieur", function()
		local cells = { { x = 5, y = 5 }, { x = 6, y = 5 }, { x = 7, y = 5 } }
		local pieces = ExplosionLayout.classify(cells, { { x = 5, y = 5 } }, { { x = 7, y = 5 } })
		local map = byKey(pieces)
		expect(map["7:5"].kind).toBe("impact")
		expect(map["7:5"].dir).toEqual({ x = 1, y = 0 })
		expect(map["6:5"].kind).toBe("segment")
	end)

	it("réaction en chaîne : deux centres, bras qui se croisent = jonction ; le nombre de cases est conservé", function()
		local cells = {}
		local seen = {}
		for _, c in cross(5, 5, 2) do
			seen[c.x .. ":" .. c.y] = true
			table.insert(cells, c)
		end
		for _, c in cross(7, 7, 2) do
			if not seen[c.x .. ":" .. c.y] then
				table.insert(cells, c)
			end
		end
		local pieces = ExplosionLayout.classify(cells, { { x = 5, y = 5 }, { x = 7, y = 7 } }, {})
		expect(#pieces).toBe(#cells)
		local map = byKey(pieces)
		expect(map["5:5"].kind).toBe("center")
		expect(map["7:7"].kind).toBe("center")
		expect(map["7:5"].kind).toBe("junction") -- le bras de (5,5) et celui de (7,7) se croisent en (7,5)
	end)

	it("sans origine fournie (ancien serveur) : la case la plus connectée sert de centre", function()
		local pieces = ExplosionLayout.classify(cross(3, 3, 2), nil, nil)
		expect(byKey(pieces)["3:3"].kind).toBe("center")
	end)

	it("entrées invalides ignorées, doublons retirés, aucune erreur", function()
		expect(ExplosionLayout.classify(nil, nil, nil)).toEqual({})
		expect(ExplosionLayout.classify(7, {}, {})).toEqual({})
		local pieces = ExplosionLayout.classify({ { x = 1, y = 1 }, { x = 1, y = 1 }, { x = "a", y = 2 }, "x", { x = 2, y = 1 } }, { { x = 1, y = 1 } }, {})
		expect(#pieces).toBe(2)
	end)

	it("une seule case : centre", function()
		local pieces = ExplosionLayout.classify({ { x = 4, y = 4 } }, { { x = 4, y = 4 } }, {})
		expect(#pieces).toBe(1)
		expect(pieces[1].kind).toBe("center")
	end)
end)
