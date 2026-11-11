--!nocheck
-- BombVisuals (modèles 3D des bombes, côté client) : REPLI. Dans cet environnement simulé aucun modèle n'existe dans
-- ReplicatedStorage.BombModels : tout doit se replier proprement (nil / false) pour que l'appelant garde sa sphère colorée.
-- Le rendu réel (style, pose au sol, orientation, aperçus 3D, contrôleur) est vérifié dans Studio : tests/Phase11BombSkinsTests.luau.
local CosmeticConfig = world.module("CosmeticConfig")
local BombVisuals = world.module("BombVisuals")

describe("BombVisuals — repli sans modèle", function()
	it("hasModel est faux sans modèle, pour un effet et pour une valeur invalide", function()
		expect(BombVisuals.hasModel(CosmeticConfig.get("bomb_cosmic"))).toBe(false)
		expect(BombVisuals.hasModel(CosmeticConfig.get("effect_red"))).toBe(false)
		expect(BombVisuals.hasModel(nil)).toBe(false)
		expect(BombVisuals.hasModel("bomb_red")).toBe(false)
	end)

	it("build renvoie nil sans modèle (la sphère de repli reste affichée)", function()
		expect(BombVisuals.build(CosmeticConfig.get("bomb_red"))).toBeNil()
		expect(BombVisuals.build(nil)).toBeNil()
		expect(BombVisuals.build({ model = 12 })).toBeNil()
	end)

	it("mountPreview renvoie nil sans modèle (la pastille colorée reste)", function()
		local parent = world.env.Instance.new("Frame")
		expect(BombVisuals.mountPreview(parent, CosmeticConfig.get("bomb_cosmic"), true)).toBeNil()
		expect(BombVisuals.mountPreview(parent, CosmeticConfig.get("effect_red"), false)).toBeNil()
	end)
end)

describe("BombVisuals.yawTowardCamera", function()
	it("0 sans caméra", function()
		expect(BombVisuals.yawTowardCamera(nil)).toBe(0)
	end)

	it("caméra côté +Z (regarde vers -Z) : l'avant du modèle (+Z) n'a pas à tourner", function()
		local camera = { CFrame = { LookVector = Vector3.new(0, -0.8, -0.6) } }
		expect(BombVisuals.yawTowardCamera(camera)).toBeCloseTo(0, 1e-6)
	end)

	it("caméra côté +X (regarde vers -X) : quart de tour", function()
		local camera = { CFrame = { LookVector = Vector3.new(-0.6, -0.8, 0) } }
		expect(BombVisuals.yawTowardCamera(camera)).toBeCloseTo(math.pi / 2, 1e-6)
	end)

	it("caméra à la verticale : 0 (aucune direction horizontale)", function()
		local camera = { CFrame = { LookVector = Vector3.new(0, -1, 0) } }
		expect(BombVisuals.yawTowardCamera(camera)).toBe(0)
	end)
end)
