--!nocheck
-- BombEffectsConfig (effets et animations de couleur des 24 bombes) : cohérence des données avec BombSkinConfig (les pièces
-- citées existent), valeurs saines des préréglages de particules et budget par bombe. Le rendu réel est vérifié dans Studio
-- (tests/Phase11BombSkinsTests.luau).
local BombEffectsConfig = world.module("BombEffectsConfig")
local BombSkinConfig = world.module("BombSkinConfig")

local function eachModel(fn)
	for _, name in BombEffectsConfig.modelNames() do
		fn(name, BombEffectsConfig.get(name), BombSkinConfig.get(name))
	end
end

local function validRgb(color)
	for channel = 1, 3 do
		expect(color[channel]).toBe(math.floor(color[channel]))
		expect(color[channel]).toBeGreaterThanOrEqual(0)
		expect(color[channel]).toBeLessThanOrEqual(255)
	end
end

describe("BombEffectsConfig", function()
	it("une entrée par modèle du catalogue 3D (les mêmes 24 noms que BombSkinConfig)", function()
		expect(BombEffectsConfig.modelNames()).toEqual(BombSkinConfig.modelNames())
		expect(#BombEffectsConfig.modelNames()).toBe(24)
	end)

	it("préréglages de particules : valeurs saines (débit, durées, tailles, couleurs, transparence, dispersion)", function()
		local count = 0
		for _, preset in BombEffectsConfig.Presets do
			count += 1
			expect(preset.rate).toBeGreaterThan(0)
			expect(preset.rate).toBeLessThanOrEqual(40)
			expect(preset.lifetime[1]).toBeGreaterThan(0)
			expect(preset.lifetime[1]).toBeLessThanOrEqual(preset.lifetime[2])
			expect(preset.lifetime[2]).toBeLessThanOrEqual(3)
			expect(preset.speed[1]).toBeGreaterThanOrEqual(0)
			expect(preset.speed[1]).toBeLessThanOrEqual(preset.speed[2])
			expect(preset.size[1]).toBeGreaterThanOrEqual(0)
			expect(preset.size[2]).toBeGreaterThanOrEqual(0)
			expect(preset.transparency[1]).toBeGreaterThanOrEqual(0)
			expect(preset.transparency[2]).toBeLessThanOrEqual(1)
			validRgb(preset.color[1])
			validRgb(preset.color[2])
			expect(preset.spread).toBeGreaterThanOrEqual(0)
			expect(preset.spread).toBeLessThanOrEqual(180)
			expect(#preset.accel).toBe(3)
			expect(preset.light).toBeGreaterThanOrEqual(0)
			expect(preset.light).toBeLessThanOrEqual(1)
		end
		expect(count).toBeGreaterThanOrEqual(10)
		expect(BombEffectsConfig.Presets.fuse_spark).never.toBeNil()
		expect(BombEffectsConfig.Presets.fuse_smoke).never.toBeNil()
	end)

	it("chaque émetteur thématique : préréglage existant, pièce existante dans le modèle, 3 au maximum par bombe", function()
		eachModel(function(_name, fx, skin)
			local emitters = fx.emitters or {}
			expect(#emitters).toBeLessThanOrEqual(3)
			for _, entry in emitters do
				expect(BombEffectsConfig.Presets[entry.preset]).never.toBeNil()
				expect(skin.pieces[entry.piece]).never.toBeNil()
			end
		end)
	end)

	it("la pièce qui porte l'étincelle de mèche existe (sauf bombe qui a la sienne : fuse = false)", function()
		eachModel(function(_name, fx, skin)
			if fx.fuse ~= false then
				expect(skin.pieces[fx.fusePiece or BombEffectsConfig.DefaultFusePiece]).never.toBeNil()
			end
		end)
	end)

	it("pulsations (glow) : pièces existantes, couleurs valides, fréquence raisonnable", function()
		eachModel(function(_name, fx, skin)
			for _, glow in fx.glow or {} do
				expect(#glow.pieces).toBeGreaterThan(0)
				for _, pieceName in glow.pieces do
					expect(skin.pieces[pieceName]).never.toBeNil()
				end
				validRgb(glow.a)
				validRgb(glow.b)
				expect(glow.hz).toBeGreaterThanOrEqual(0.1)
				expect(glow.hz).toBeLessThanOrEqual(10)
			end
		end)
	end)

	it("cycle de couleurs (arc-en-ciel) : au moins 2 pièces existantes", function()
		local found = false
		eachModel(function(name, fx, skin)
			if fx.cycle then
				found = true
				expect(#fx.cycle.pieces).toBeGreaterThanOrEqual(2)
				for _, pieceName in fx.cycle.pieces do
					expect(skin.pieces[pieceName]).never.toBeNil()
				end
				expect(fx.cycle.hz).toBeGreaterThan(0)
			end
		end)
		expect(found).toBe(true)
	end)

	it("les bombes sans effet propre sont déclarées (pas d'oubli) ; la Cosmique n'a pas d'étincelle générique", function()
		for _, name in { "B01_Classique", "B02_Rouge", "B03_Bleue", "B04_Verte", "B05_Jaune", "B13_Football", "B14_Basketball", "B19_Militaire", "B20_Tonneau" } do
			local fx = BombEffectsConfig.get(name)
			expect(fx).never.toBeNil()
			expect(fx.emitters).toBeNil()
		end
		expect(BombEffectsConfig.get("B09_Cosmique").fuse).toBe(false)
	end)

	it("flamme de mèche : couleurs valides, pièce d'ancrage existante dans chaque modèle (BombFlame)", function()
		local function validFlame(flame)
			for _, key in { "core", "mid", "tip" } do
				validRgb(flame[key])
			end
		end
		validFlame(BombEffectsConfig.DefaultFlame)
		eachModel(function(_name, fx, skin)
			expect(skin.pieces[fx.flamePiece or fx.fusePiece or BombEffectsConfig.DefaultFusePiece]).never.toBeNil()
			if fx.flame then
				validFlame(fx.flame)
			end
		end)
		-- bombes à flamme particulière
		expect(BombEffectsConfig.get("B09_Cosmique").flamePiece).toBe("BombSpark_Star")
		expect(BombEffectsConfig.get("B08_Electrique").flame).never.toBeNil()
	end)

	it("effet d'ambiance (aura) : chaque bombe en a un, valeurs saines, formes et modes connus", function()
		local modes = { orbit = true, fall = true, rise = true, bolts = true, glint = true }
		local shapes = { sparkle = true, ball = true, heart = true, leaf = true, rock = true }
		eachModel(function(_name, fx)
			local aura = fx.aura
			expect(aura).never.toBeNil()
			expect(modes[aura.mode]).toBe(true)
			expect(shapes[aura.shape]).toBe(true)
			expect(aura.count).toBeGreaterThanOrEqual(2)
			expect(aura.count).toBeLessThanOrEqual(8)
			expect(#aura.colors).toBeGreaterThanOrEqual(1)
			for _, color in aura.colors do
				validRgb(color)
			end
			expect(aura.size).toBeGreaterThan(0.05)
			expect(aura.size).toBeLessThanOrEqual(0.8)
			expect(aura.speed).toBeGreaterThan(0)
			expect(aura.speed).toBeLessThanOrEqual(1)
			if aura.radius then
				expect(aura.radius).toBeGreaterThan(0.5)
				expect(aura.radius).toBeLessThanOrEqual(2)
			end
			if aura.alpha then
				expect(aura.alpha).toBeGreaterThanOrEqual(0)
				expect(aura.alpha).toBeLessThan(1)
			end
			if aura.mode == "fall" or aura.mode == "rise" then
				expect(aura.y0).never.toBeNil()
				expect(aura.y1).never.toBeNil()
			end
		end)
	end)

	it("auras attendues : éclairs (Électrique), flocons (Glacée), étoiles en orbite (Étoiles), cœurs (Cœur), feuilles (Nature), braises (Lave, Météore)", function()
		expect(BombEffectsConfig.get("B08_Electrique").aura.mode).toBe("bolts")
		expect(BombEffectsConfig.get("B06_Glacee").aura.mode).toBe("fall")
		expect(BombEffectsConfig.get("B18_Etoiles").aura.mode).toBe("orbit")
		expect(BombEffectsConfig.get("B18_Etoiles").aura.shape).toBe("sparkle")
		expect(BombEffectsConfig.get("B17_Coeur").aura.shape).toBe("heart")
		expect(BombEffectsConfig.get("B22_Nature").aura.shape).toBe("leaf")
		expect(BombEffectsConfig.get("B07_Lave").aura.mode).toBe("rise")
		expect(BombEffectsConfig.get("B23_Meteore").aura.mode).toBe("rise")
	end)

	it("get refuse tout ce qui n'est pas un nom de modèle connu", function()
		expect(BombEffectsConfig.get(nil)).toBeNil()
		expect(BombEffectsConfig.get(7)).toBeNil()
		expect(BombEffectsConfig.get("B99_Inconnue")).toBeNil()
	end)
end)
