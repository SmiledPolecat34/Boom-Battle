--!nocheck
-- Mini framework de tests (describe / it / expect), sans dépendance : tourne sous Lune.
-- Une suite = un fichier `tests/unit/**/*.spec.luau`. Chaque suite est exécutée avec une instance neuve du chargeur
-- (voir loader.luau), donc l'état des modules (singletons) n'est jamais partagé entre deux fichiers.

local Framework = {}

export type Result = {
	suite: string,
	name: string,
	ok: boolean,
	message: string?,
	seconds: number,
}

-- Comparaison profonde (tables, cycles gérés) -------------------------------------------------------------------
local function deepEqual(a: any, b: any, seen: any?): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		-- NaN == NaN doit être considéré égal dans un test.
		return a ~= a and b ~= b
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for k, v in a do
		if not deepEqual(v, b[k], seen) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) ~= "table" then
		return tostring(value)
	end
	local parts = {}
	local count = 0
	for k, v in value do
		count += 1
		if count > 8 then
			table.insert(parts, "…")
			break
		end
		table.insert(parts, tostring(k) .. "=" .. (type(v) == "table" and "{…}" or show(v)))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function where(): string
	-- niveau 1 : where, 2 : fail, 3 : matcher, 4 : le test.
	local source, line = debug.info(4, "sl")
	if source and line then
		return (" (%s:%d)"):format(source, line)
	end
	return ""
end

local function fail(message: string)
	error({ __expectFailure = true, message = message .. where() }, 0)
end

-- expect ----------------------------------------------------------------------------------------------------------
local Matchers = {}
Matchers.__index = Matchers

-- Les matchers s'appellent avec un point : expect(x).toBe(y). Les fermetures évitent le piège du `:`.
local function newExpectation(actual: any, negated: boolean)
	local state = setmetatable({ actual = actual, negated = negated }, Matchers)
	local public = {}
	for name, matcher in Matchers do
		if type(matcher) == "function" and string.sub(name, 1, 1) ~= "_" then
			public[name] = function(first: any, ...)
				-- tolère aussi expect(x):toBe(y) (le premier argument est alors la table publique)
				if first == public then
					return matcher(state, ...)
				end
				return matcher(state, first, ...)
			end
		end
	end
	return public
end

function Matchers:_assert(pass: boolean, positiveMessage: string, negativeMessage: string)
	if self.negated then
		if pass then
			fail(negativeMessage)
		end
	elseif not pass then
		fail(positiveMessage)
	end
end

function Matchers:toBe(expected: any)
	self:_assert(
		self.actual == expected or (self.actual ~= self.actual and expected ~= expected),
		("attendu %s, reçu %s"):format(show(expected), show(self.actual)),
		("attendu une valeur différente de %s"):format(show(expected))
	)
end

function Matchers:toEqual(expected: any)
	self:_assert(
		deepEqual(self.actual, expected),
		("attendu (égalité profonde) %s, reçu %s"):format(show(expected), show(self.actual)),
		("attendu une valeur profondément différente de %s"):format(show(expected))
	)
end

function Matchers:toBeTruthy()
	self:_assert(self.actual and true or false, ("attendu une valeur vraie, reçu %s"):format(show(self.actual)), "attendu une valeur fausse ou nil")
end

function Matchers:toBeFalsy()
	self:_assert(not self.actual, ("attendu une valeur fausse ou nil, reçu %s"):format(show(self.actual)), "attendu une valeur vraie")
end

function Matchers:toBeNil()
	self:_assert(self.actual == nil, ("attendu nil, reçu %s"):format(show(self.actual)), "attendu une valeur non nil")
end

function Matchers:toBeCloseTo(expected: number, epsilon: number?)
	local eps = epsilon or 1e-6
	self:_assert(
		type(self.actual) == "number" and math.abs(self.actual - expected) <= eps,
		("attendu %s ± %s, reçu %s"):format(show(expected), show(eps), show(self.actual)),
		("attendu un nombre éloigné de %s"):format(show(expected))
	)
end

function Matchers:toBeGreaterThan(limit: number)
	self:_assert(type(self.actual) == "number" and self.actual > limit, ("attendu > %s, reçu %s"):format(show(limit), show(self.actual)), ("attendu <= %s"):format(show(limit)))
end

function Matchers:toBeGreaterThanOrEqual(limit: number)
	self:_assert(type(self.actual) == "number" and self.actual >= limit, ("attendu >= %s, reçu %s"):format(show(limit), show(self.actual)), ("attendu < %s"):format(show(limit)))
end

function Matchers:toBeLessThan(limit: number)
	self:_assert(type(self.actual) == "number" and self.actual < limit, ("attendu < %s, reçu %s"):format(show(limit), show(self.actual)), ("attendu >= %s"):format(show(limit)))
end

function Matchers:toBeLessThanOrEqual(limit: number)
	self:_assert(type(self.actual) == "number" and self.actual <= limit, ("attendu <= %s, reçu %s"):format(show(limit), show(self.actual)), ("attendu > %s"):format(show(limit)))
end

function Matchers:toHaveLength(length: number)
	local actualLength = (type(self.actual) == "table" or type(self.actual) == "string") and #self.actual or nil
	self:_assert(actualLength == length, ("attendu une longueur de %d, reçu %s"):format(length, show(actualLength)), ("attendu une longueur différente de %d"):format(length))
end

-- Chaîne : sous-chaîne (recherche littérale). Tableau : élément présent.
function Matchers:toContain(item: any)
	local found = false
	if type(self.actual) == "string" then
		found = type(item) == "string" and string.find(self.actual, item, 1, true) ~= nil
	elseif type(self.actual) == "table" then
		found = table.find(self.actual, item) ~= nil
	end
	self:_assert(found, ("%s devrait contenir %s"):format(show(self.actual), show(item)), ("%s ne devrait pas contenir %s"):format(show(self.actual), show(item)))
end

-- La fonction doit lever une erreur (dont le message contient `substring` si fourni).
function Matchers:toThrow(substring: string?)
	local ok, err = pcall(self.actual)
	local text = tostring(if type(err) == "table" and err.message then err.message else err)
	local pass = not ok and (substring == nil or string.find(text, substring, 1, true) ~= nil)
	self:_assert(
		pass,
		if ok then "attendu une erreur, aucune levée" else ("l'erreur %s ne contient pas %s"):format(show(text), show(substring)),
		"attendu aucune erreur" .. (if ok then "" else (", reçu : " .. text))
	)
end

-- API publique `expect` : expect(x).toBe(y) ; expect(x).never.toBe(y)
function Framework.expect(actual: any)
	local expectation = newExpectation(actual, false)
	expectation.never = newExpectation(actual, true)
	return expectation
end

-- Exécution d'une suite -----------------------------------------------------------------------------------------
type Test = { name: string, fn: () -> (), skip: boolean }
type Group = {
	name: string,
	tests: { Test },
	groups: { Group },
	beforeEach: { () -> () },
	afterEach: { () -> () },
	parent: Group?,
}

local function newGroup(name: string, parent: Group?): Group
	return { name = name, tests = {}, groups = {}, beforeEach = {}, afterEach = {}, parent = parent }
end

-- Crée les globales d'une suite et retourne (globales, exécuteur).
function Framework.newSuite(suiteName: string)
	local root = newGroup("", nil)
	local current = root

	local api = {}

	function api.describe(name: string, body: () -> ())
		local group = newGroup(name, current)
		table.insert(current.groups, group)
		local previous = current
		current = group
		body()
		current = previous
	end

	function api.it(name: string, fn: () -> ())
		table.insert(current.tests, { name = name, fn = fn, skip = false })
	end

	function api.xit(name: string, _fn: () -> ())
		table.insert(current.tests, { name = name, fn = function() end, skip = true })
	end

	function api.beforeEach(fn: () -> ())
		table.insert(current.beforeEach, fn)
	end

	function api.afterEach(fn: () -> ())
		table.insert(current.afterEach, fn)
	end

	api.test = api.it
	api.expect = Framework.expect

	local function fullName(group: Group, testName: string): string
		local parts = { testName }
		local g: Group? = group
		while g and g.name ~= "" do
			table.insert(parts, 1, g.name)
			g = g.parent
		end
		return table.concat(parts, " › ")
	end

	local function run(group: Group, results: { Result }, filter: string?)
		local function chain(key: string): { () -> () }
			local list = {}
			local g: Group? = group
			while g do
				for _, hook in g[key] do
					if key == "beforeEach" then
						table.insert(list, 1, hook)
					else
						table.insert(list, hook)
					end
				end
				g = g.parent
			end
			return list
		end

		for _, test in group.tests do
			local name = fullName(group, test.name)
			if filter and not string.find(string.lower(suiteName .. " " .. name), string.lower(filter), 1, true) then
				continue
			end
			if test.skip then
				table.insert(results, { suite = suiteName, name = name .. " (ignoré)", ok = true, seconds = 0 })
				continue
			end
			local started = os.clock()
			local ok, err = pcall(function()
				for _, hook in chain("beforeEach") do
					hook()
				end
				test.fn()
			end)
			-- afterEach s'exécute même si le test a échoué.
			for _, hook in chain("afterEach") do
				local hookOk, hookErr = pcall(hook)
				if ok and not hookOk then
					ok, err = false, hookErr
				end
			end
			local message: string? = nil
			if not ok then
				message = if type(err) == "table" and err.__expectFailure then err.message else ("erreur : " .. tostring(err))
			end
			table.insert(results, { suite = suiteName, name = name, ok = ok, message = message, seconds = os.clock() - started })
		end
		for _, child in group.groups do
			run(child, results, filter)
		end
	end

	return api, function(filter: string?): { Result }
		local results = {}
		run(root, results, filter)
		return results
	end
end

return Framework
