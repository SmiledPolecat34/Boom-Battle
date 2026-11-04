--!nocheck
-- Point d'entrée des tests automatisés (Lune).
--
--   lune run tests/run                       toutes les suites
--   lune run tests/run -- GridService        seulement les fichiers dont le chemin contient « GridService »
--   lune run tests/run -- --filter "pilier"  seulement les tests dont le nom contient « pilier »
--   lune run tests/run -- --verbose          liste chaque test
--   lune run tests/run -- --json out.json    écrit un rapport JSON
--
-- Code de sortie : 0 = tout passe, 1 = au moins un échec, 2 = erreur d'utilisation / suite illisible.
-- Sous GitHub Actions, un résumé Markdown est ajouté à $GITHUB_STEP_SUMMARY.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Framework = require("./runner/framework")
local Loader = require("./runner/loader")
local Fixtures = require("./runner/fixtures")

local ROOT = "."
local SPEC_DIR = "tests/unit"

-- Arguments ----------------------------------------------------------------------------------------------------
local pathFilter: string? = nil
local nameFilter: string? = nil
local verbose = false
local jsonPath: string? = nil
do
	local args = process.args
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--" then
			-- séparateur ignoré
		elseif a == "--verbose" or a == "-v" then
			verbose = true
		elseif a == "--filter" then
			i += 1
			nameFilter = args[i]
		elseif a == "--json" then
			i += 1
			jsonPath = args[i]
		elseif string.sub(a, 1, 2) == "--" then
			print("Option inconnue : " .. a)
			process.exit(2)
		else
			pathFilter = a
		end
		i += 1
	end
end

-- Découverte des suites ----------------------------------------------------------------------------------------
local function findSpecs(directory: string, out: { string })
	local entries = fs.readDir(directory)
	table.sort(entries)
	for _, entry in entries do
		local full = directory .. "/" .. entry
		if fs.isDir(full) then
			findSpecs(full, out)
		elseif string.sub(entry, -#".spec.luau") == ".spec.luau" then
			table.insert(out, full)
		end
	end
end

local specs: { string } = {}
findSpecs(SPEC_DIR, specs)
if pathFilter then
	local filtered = {}
	for _, spec in specs do
		if string.find(string.lower(spec), string.lower(pathFilter), 1, true) then
			table.insert(filtered, spec)
		end
	end
	specs = filtered
end
if #specs == 0 then
	print("Aucune suite trouvée.")
	process.exit(2)
end

-- Exécution -----------------------------------------------------------------------------------------------------
local allResults: { Framework.Result } = {}
local brokenSuites: { string } = {}

for _, specPath in specs do
	local suiteName = string.gsub(string.sub(specPath, #SPEC_DIR + 2), "%.spec%.luau$", "")
	local world = Loader.new(ROOT)
	local api, runSuite = Framework.newSuite(suiteName)

	-- Lune copie les paires de `environment` (métatables ignorées) : on aplatit les couches.
	local env = table.clone(world.env)
	for k, v in api do
		env[k] = v
	end
	env.world = world
	env.game = world.game
	env.require = world.require
	env.Fixtures = Fixtures(world)
	-- Bibliothèques Lune pour les suites « méta » (analyse des fichiers du dépôt).
	env.Lune = { fs = fs, luau = luau, serde = serde, process = process }

	local ok, err = pcall(function()
		-- Le script d'une suite est lui-même chargé via luau.load pour avoir les globales de test.
		local chunk = luau.load(fs.readFile(specPath), { debugName = specPath, environment = env })
		chunk()
	end)
	if not ok then
		print(("✗ %s  (suite illisible)\n    %s"):format(suiteName, tostring(err)))
		table.insert(brokenSuites, ("%s : %s"):format(specPath, tostring(err)))
		table.insert(allResults, { suite = suiteName, name = "(chargement de la suite)", ok = false, message = tostring(err), seconds = 0 })
		continue
	end

	local results = runSuite(nameFilter)
	local failures = 0
	for _, r in results do
		table.insert(allResults, r)
		if not r.ok then
			failures += 1
		end
	end
	if #results > 0 then
		print(("%s %s  (%d tests)"):format(if failures == 0 then "✓" else "✗", suiteName, #results))
		for _, r in results do
			if not r.ok then
				print(("    ✗ %s\n        %s"):format(r.name, r.message or ""))
			elseif verbose then
				print(("    ✓ %s"):format(r.name))
			end
		end
	end
end

-- Bilan ---------------------------------------------------------------------------------------------------------
local passed, failed = 0, 0
for _, r in allResults do
	if r.ok then
		passed += 1
	else
		failed += 1
	end
end

print(("\nBilan : %d réussis, %d échecs, %d suites"):format(passed, failed, #specs))

if jsonPath then
	fs.writeFile(jsonPath, serde.encode("json", { passed = passed, failed = failed, suites = #specs, results = allResults }, true))
end

local summaryPath = process.env.GITHUB_STEP_SUMMARY
if summaryPath and summaryPath ~= "" then
	local lines = { "## Tests Luau (Lune)", "", ("**%d réussis, %d échecs, %d suites**"):format(passed, failed, #specs), "" }
	for _, r in allResults do
		if not r.ok then
			table.insert(lines, ("- ❌ `%s` › %s — %s"):format(r.suite, r.name, (string.gsub(r.message or "", "\n", " "))))
		end
	end
	local existing = if fs.isFile(summaryPath) then fs.readFile(summaryPath) else ""
	fs.writeFile(summaryPath, existing .. table.concat(lines, "\n") .. "\n")
end

process.exit(if failed == 0 and #brokenSuites == 0 then 0 else 1)
