--!nocheck
-- AssetIds / assets/manifest.json : règle « ne jamais inventer d'identifiant d'asset ». Chaque identifiant utilisé par
-- le code doit provenir d'un import enregistré dans le manifeste, et chaque fichier du manifeste doit exister avec
-- le sha256 annoncé (sinon l'image importée n'est plus celle du dépôt). Plus Theme et EventConfig.
local AssetIds = world.module("AssetIds")
local Theme = world.module("Theme")
local EventConfig = world.module("EventConfig")
local fs = Lune.fs
local serde = Lune.serde

local manifest = serde.decode("json", fs.readFile("assets/manifest.json"))

describe("manifeste d'assets", function()
	it("chaque entrée a un fichier existant dont le sha256 correspond", function()
		for _, asset in manifest.assets do
			expect(fs.isFile(asset.fichier)).toBe(true)
			expect(serde.hash("sha256", fs.readFile(asset.fichier))).toBe(asset.sha256)
		end
	end)

	it("sha256 et identifiants uniques (jamais deux imports du même fichier)", function()
		local shas, ids = {}, {}
		for _, asset in manifest.assets do
			expect(shas[asset.sha256]).toBeNil()
			expect(ids[asset.assetId]).toBeNil()
			shas[asset.sha256] = true
			ids[asset.assetId] = true
			expect(asset.assetId:match("^rbxassetid://%d+$")).never.toBeNil()
		end
	end)

	it("tout identifiant d'AssetIds provient du manifeste", function()
		local known = {}
		for _, asset in manifest.assets do
			known[asset.assetId] = true
		end
		for key, value in AssetIds do
			if type(value) == "string" then
				expect(value:match("^rbxassetid://%d+$")).never.toBeNil()
				if not known[value] then
					error(("AssetIds.%s = %s absent de assets/manifest.json (identifiant inventé ?)"):format(key, value), 0)
				end
			end
		end
	end)

	it("les rapports d'aspect sont positifs et la zone de texte PLAY reste dans l'image", function()
		expect(AssetIds.LogoAspectRatio).toBeGreaterThan(0)
		expect(AssetIds.PlayButtonAspectRatio).toBeGreaterThan(0)
		local a = AssetIds.PlayTextArea
		expect(a.x >= 0 and a.y >= 0 and a.x + a.width <= 1 and a.y + a.height <= 1).toBe(true)
	end)
end)

describe("Theme", function()
	it("toutes les couleurs de la palette sont définies", function()
		for _, name in { "navy", "panel", "violet", "yellow", "turquoise", "green", "red", "orange", "white", "muted", "disabled" } do
			expect(Theme[name]).never.toBeNil()
		end
	end)

	it("trois polices définies", function()
		expect(Theme.fontTitle).never.toBeNil()
		expect(Theme.fontBold).never.toBeNil()
		expect(Theme.fontBody).never.toBeNil()
	end)
end)

describe("EventConfig", function()
	it("aucun événement factice : la liste est vide tant que rien n'est implémenté", function()
		expect(#EventConfig.Events).toBe(0)
	end)
end)
