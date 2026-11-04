--!nocheck
-- Tests « méta » : qualité du dépôt lui-même.
--  1. Syntaxe : chaque fichier .luau (src/, tests/) doit se compiler (rojo build ne vérifie PAS la syntaxe).
--  2. Couverture : chaque module de src/ doit avoir une suite qui le charge, OU figurer dans tests/untested.json avec
--     une raison. Un nouveau module sans test fait donc échouer la CI : « une modif = un test ».
--  3. Cohérence Rojo : les dossiers référencés par default.project.json existent.
local fs = Lune.fs
local luau = Lune.luau
local serde = Lune.serde

local function walk(directory: string, out: { string }, suffix: string)
	for _, entry in fs.readDir(directory) do
		local full = directory .. "/" .. entry
		if fs.isDir(full) then
			walk(full, out, suffix)
		elseif string.sub(entry, -#suffix) == suffix then
			table.insert(out, full)
		end
	end
end

local function filesOf(directory: string): { string }
	local out = {}
	walk(directory, out, ".luau")
	table.sort(out)
	return out
end

describe("syntaxe Luau", function()
	for _, root in { "src", "tests" } do
		for _, path in filesOf(root) do
			it("compile : " .. path, function()
				local ok, err = pcall(luau.load, fs.readFile(path), { debugName = path })
				if not ok then
					error(tostring(err), 0)
				end
			end)
		end
	end
end)

describe("hygiène des fichiers source", function()
	it("aucun fichier de src/ ne contient de marque de conflit git", function()
		for _, path in filesOf("src") do
			local text = fs.readFile(path)
			expect(text:find("\n<<<<<<< ", 1, true)).toBeNil()
			expect(text:find("\n>>>>>>> ", 1, true)).toBeNil()
		end
	end)

	it("aucun secret apparent (clé d'API, cookie Roblox) dans src/ ou tests/", function()
		for _, root in { "src", "tests" } do
			for _, path in filesOf(root) do
				if path:find("/meta/", 1, true) then
					continue -- ce fichier contient les motifs recherchés
				end
				local text = fs.readFile(path)
				expect(text:find("_|WARNING:-DO-NOT-SHARE-THIS", 1, true)).toBeNil()
				expect(text:lower():find("x%-api%-key")).toBeNil()
			end
		end
	end)

	it("chaque module de src/ commence par --!strict (sauf exceptions listées)", function()
		local exceptions = {}
		local manifest = serde.decode("json", fs.readFile("tests/untested.json"))
		for _, name in manifest.nonStrictAllowed or {} do
			exceptions[name] = true
		end
		local missing = {}
		for _, path in filesOf("src") do
			local name = path:match("([^/]+)%.luau$")
			local firstLine = fs.readFile(path):match("^[^\n]*")
			if not firstLine:find("--!strict", 1, true) and not exceptions[name] then
				table.insert(missing, path)
			end
		end
		expect(missing).toEqual({})
	end)
end)

describe("couverture des tests", function()
	local manifest = serde.decode("json", fs.readFile("tests/untested.json"))
	local untested = manifest.untested or {}

	-- Nom de tous les modules de src/ (les Bootstrap sont des Scripts, pas des modules).
	local modules = {}
	for _, path in filesOf("src") do
		local fileName = path:match("([^/]+)%.luau$")
		if not fileName:find("%.server$") and not fileName:find("%.client$") then
			modules[fileName] = path
		end
	end

	-- Texte de toutes les suites (hors ce fichier méta).
	local specText = {}
	do
		local specs = {}
		walk("tests/unit", specs, ".spec.luau")
		for _, path in specs do
			if not path:find("/meta/", 1, true) then
				table.insert(specText, fs.readFile(path))
			end
		end
	end
	local function isCovered(name: string): boolean
		for _, text in specText do
			if text:find('module("' .. name .. '")', 1, true) or text:find("." .. name .. '"', 1, true) then
				return true
			end
		end
		return false
	end

	it("tous les modules de src/ sont testés ou explicitement exemptés (avec raison)", function()
		local offenders = {}
		for name, path in modules do
			if not isCovered(name) and not untested[name] then
				table.insert(offenders, name .. " (" .. path .. ")")
			end
		end
		table.sort(offenders)
		if #offenders > 0 then
			error(
				"Modules sans test : "
					.. table.concat(offenders, ", ")
					.. ". Crée tests/unit/<dossier>/<Module>.spec.luau (voir tests/README.md), ou ajoute le module à tests/untested.json avec une raison.",
				0
			)
		end
	end)

	it("chaque exemption a une raison non vide et vise un module existant", function()
		for name, reason in untested do
			expect(modules[name]).never.toBeNil()
			expect(type(reason) == "string" and #reason >= 10).toBe(true)
		end
	end)

	it("un module testé ne reste pas dans la liste d'exemptions (liste à nettoyer)", function()
		local stale = {}
		for name in untested do
			if isCovered(name) then
				table.insert(stale, name)
			end
		end
		table.sort(stale)
		expect(stale).toEqual({})
	end)
end)

describe("contrat réseau (remotes)", function()
	-- Un nom attendu par un service mais jamais créé par Bootstrap.server fait attendre le client indéfiniment
	-- (WaitForChild) : le jeu semblerait « figé » au démarrage. Ce test le détecte avant Studio.
	local function createdByServer()
		local text = fs.readFile("src/server/Bootstrap.server.luau")
		local block = text:match("for _, name in %{(.-)%} do")
		local names = {}
		for name in block:gmatch('"([%w_]+)"') do
			names[name] = true
		end
		return names
	end

	local function expectedBySources()
		local expected = {}
		for _, path in filesOf("src") do
			if not path:find("Bootstrap", 1, true) then
				local text = fs.readFile(path)
				for name in text:gmatch('remotes:WaitForChild%("([%w_]+)"%)') do
					expected[name] = path
				end
				for name in text:gmatch('remotes:FindFirstChild%("([%w_]+)"%)') do
					expected[name] = path
				end
			end
		end
		return expected
	end

	it("Bootstrap.server crée une remote pour chaque nom attendu par un service ou un contrôleur", function()
		local created = createdByServer()
		local missing = {}
		for name, path in expectedBySources() do
			if not created[name] then
				table.insert(missing, name .. " (" .. path .. ")")
			end
		end
		table.sort(missing)
		expect(missing).toEqual({})
	end)

	it("aucune remote créée sans être utilisée (code mort ou oubli)", function()
		local expected = expectedBySources()
		local unused = {}
		for name in createdByServer() do
			-- ClientReady et MapReady sont attendues par Bootstrap.client / RoundService (fichiers exclus ci-dessus)
			local used = expected[name] ~= nil
			if not used then
				for _, path in filesOf("src") do
					if fs.readFile(path):find('"' .. name .. '"', 1, true) and not path:find("Bootstrap.server", 1, true) then
						used = true
					end
				end
			end
			if not used then
				table.insert(unused, name)
			end
		end
		table.sort(unused)
		expect(unused).toEqual({})
	end)

	it("les noms de remotes sont uniques", function()
		local text = fs.readFile("src/server/Bootstrap.server.luau")
		local block = text:match("for _, name in %{(.-)%} do")
		local seen = {}
		for name in block:gmatch('"([%w_]+)"') do
			expect(seen[name]).toBeNil()
			seen[name] = true
		end
	end)
end)

describe("projet Rojo", function()
	it("chaque $path de default.project.json existe", function()
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local function check(node)
			for key, value in node do
				if key == "$path" then
					expect(fs.isDir(value) or fs.isFile(value)).toBe(true)
				elseif type(value) == "table" then
					check(value)
				end
			end
		end
		check(project.tree)
	end)
end)
