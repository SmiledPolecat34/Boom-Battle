--!nocheck
-- BombSkinConfig (style des 24 modèles 3D de bombes, généré depuis les manifestes d'export) : cohérence des données et lien
-- avec le catalogue cosmétique. Les FBX ne portent ni couleur, ni matériau, ni transparence : tout vient de cette config.
local BombSkinConfig = world.module("BombSkinConfig")
local CosmeticConfig = world.module("CosmeticConfig")

local function allowedMaterials()
	local set = {}
	for _, name in BombSkinConfig.Materials do
		set[name] = true
	end
	return set
end

describe("BombSkinConfig", function()
	it("décrit exactement les 24 modèles du catalogue 3D (B01 à B24, un numéro une seule fois)", function()
		local names = BombSkinConfig.modelNames()
		expect(#names).toBe(24)
		local numbers = {}
		for _, name in names do
			local number = tonumber(name:match("^B(%d%d)_"))
			expect(number).never.toBeNil()
			expect(numbers[number]).toBeNil()
			numbers[number] = true
		end
		for number = 1, 24 do
			expect(numbers[number]).toBe(true)
		end
	end)

	it("chaque bombe du catalogue cosmétique pointe vers un modèle décrit, et chaque modèle sert à une seule bombe", function()
		local used = {}
		for _, id in CosmeticConfig.idsOfKind("bomb") do
			local model = CosmeticConfig.get(id).model
			expect(BombSkinConfig.get(model)).never.toBeNil()
			expect(used[model]).toBeNil()
			used[model] = id
		end
		for _, name in BombSkinConfig.modelNames() do
			expect(used[name]).never.toBeNil()
		end
	end)

	it("chaque modèle a la pièce d'ancrage BombCollar_Base et au moins 3 pièces", function()
		for _, name in BombSkinConfig.modelNames() do
			local skin = BombSkinConfig.get(name)
			expect(skin.pieces.BombCollar_Base).never.toBeNil()
			local count = 0
			for _ in skin.pieces do
				count += 1
			end
			expect(count).toBeGreaterThanOrEqual(3)
		end
	end)

	it("chaque pièce : couleur entière 0 à 255, matériau autorisé, transparence entre 0 et 1", function()
		local materials = allowedMaterials()
		for _, name in BombSkinConfig.modelNames() do
			for pieceName, piece in BombSkinConfig.get(name).pieces do
				expect(pieceName:find("^Bomb")).never.toBeNil()
				for channel = 1, 3 do
					expect(piece[channel]).toBe(math.floor(piece[channel]))
					expect(piece[channel]).toBeGreaterThanOrEqual(0)
					expect(piece[channel]).toBeLessThanOrEqual(255)
				end
				expect(materials[piece[4]]).toBe(true)
				if piece[5] ~= nil then
					expect(piece[5]).toBeGreaterThan(0)
					expect(piece[5]).toBeLessThan(1)
				end
			end
		end
	end)

	it("seule la bombe Cosmique a un effet animé (fx = cosmic) et des pièces transparentes", function()
		for _, name in BombSkinConfig.modelNames() do
			local skin = BombSkinConfig.get(name)
			local transparent = 0
			for _, piece in skin.pieces do
				if piece[5] ~= nil then
					transparent += 1
				end
			end
			if name == "B09_Cosmique" then
				expect(skin.fx).toBe("cosmic")
				expect(transparent).toBeGreaterThan(0)
			else
				expect(skin.fx).toBeNil()
				expect(transparent).toBe(0)
			end
			expect(type(skin.facesCamera)).toBe("boolean")
		end
	end)

	it("get refuse tout ce qui n'est pas un nom de modèle connu", function()
		expect(BombSkinConfig.get(nil)).toBeNil()
		expect(BombSkinConfig.get(42)).toBeNil()
		expect(BombSkinConfig.get({})).toBeNil()
		expect(BombSkinConfig.get("B99_Inconnue")).toBeNil()
	end)
end)
