--!nocheck
-- Tests du mode solo : cerveau des bots (BotBrain, logique pure), acteur et registre.
-- À EXÉCUTER DANS ROBLOX STUDIO côté SERVEUR d'une session Play.

local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

local GridService = require(Services.GridService)
local BotBrain = require(Services.BotBrain)
local BotActor = require(Services.BotActor)
local ActorRegistry = require(Services.ActorRegistry)

local passed, failed = 0, 0
local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		warn(("ÉCHEC : %s %s"):format(name, detail or ""))
	end
end

-- Grille 9 x 9 vide ; chaque test personnalise ses cases.
local function makeGrid()
	local cells = {}
	for y = 1, 9 do
		cells[y] = {}
		for x = 1, 9 do
			cells[y][x] = "EMPTY"
		end
	end
	return GridService.new({ seed = 1, sizeId = "T", size = 9, theme = "Classic", cells = cells, spawns = {} }, 4, Vector3.zero), cells
end

local function ctx(cell, overrides)
	local c = { cell = cell, range = 2, canPlaceBomb = true, danger = {}, enemies = {}, rng = nil }
	for k, v in overrides or {} do
		c[k] = v
	end
	return c
end

-- Acteur et registre ------------------------------------------------------------------------------------------
local bot = BotActor.new(1)
check("bot : identifiant négatif éloigné des joueurs", bot.UserId < -999999)
check("bot : deux bots, deux identifiants", BotActor.new(1).UserId ~= BotActor.new(2).UserId)
check("bot : attributs", (function() bot:SetAttribute("Alive", true) return bot:GetAttribute("Alive") == true end)())
check("bot : reconnu comme bot", ActorRegistry.isBot(bot) and not ActorRegistry.isBot({}) and not ActorRegistry.isBot(workspace))
ActorRegistry.addBot(bot)
check("registre : all() contient le bot", table.find(ActorRegistry.all(), bot) ~= nil)
ActorRegistry.clearBots()
check("registre : clearBots vide la liste", #ActorRegistry.getBots() == 0)

-- Zone d'explosion ---------------------------------------------------------------------------------------------
do
	local g, c = makeGrid()
	c[5][7] = "PILLAR"
	c[3][5] = "CRATE"
	local keys = BotBrain.blastKeys(g, { x = 5, y = 5 }, 3)
	local function has(x, y) return keys[g:key(x, y)] == true end
	check("zone : centre et croix", has(5, 5) and has(6, 5) and has(4, 5) and has(5, 6))
	check("zone : pilier arrête la propagation", has(6, 5) and not has(7, 5) and not has(8, 5))
	check("zone : caisse touchée puis arrêt", has(5, 3) and not has(5, 2))
end

-- Fuite ------------------------------------------------------------------------------------------------------
do
	local g = makeGrid()
	-- bombe en (5,5) portée 2 : le bot en (5,4) est dans la zone
	local danger = BotBrain.blastKeys(g, { x = 5, y = 5 }, 2)
	local action = BotBrain.decide(g, ctx({ x = 5, y = 4 }, { danger = danger }))
	check("fuite : un bot menacé bouge", action.kind == "move" and action.cell ~= nil)
	check("fuite : la cible est hors de la zone", action.cell ~= nil and not danger[g:key(action.cell.x, action.cell.y)])
	local blocked = BotBrain.decide(g, ctx({ x = 5, y = 4 }, { danger = danger, canPlaceBomb = true }))
	check("fuite : priorité absolue sur la pose", blocked.kind == "move")
end

-- Pose de bombe -----------------------------------------------------------------------------------------------
do
	local g, c = makeGrid()
	c[5][6] = "CRATE" -- caisse à droite de (5,5)
	local action = BotBrain.decide(g, ctx({ x = 5, y = 5 }))
	check("bombe : pose à côté d'une caisse", action.kind == "bomb")
	local noCapacity = BotBrain.decide(g, ctx({ x = 5, y = 5 }, { canPlaceBomb = false }))
	check("bombe : jamais sans capacité", noCapacity.kind ~= "bomb")
end

-- Pas de suicide : cul-de-sac sans issue ---------------------------------------------------------------------
do
	local g, c = makeGrid()
	-- couloir fermé : le bot en (1,1) n'a que (2,1) ; tout est mur autour
	for x = 1, 9 do for y = 1, 9 do c[y][x] = "PILLAR" end end
	c[1][1] = "EMPTY" c[1][2] = "EMPTY" c[1][3] = "CRATE" -- couloir (1,1)-(2,1) puis caisse
	local action = BotBrain.decide(g, ctx({ x = 1, y = 1 }, { range = 3 }))
	check("sécurité : ne pose pas une bombe sans issue", action.kind ~= "bomb", action.kind)
	check("sécurité : hasEscape faux dans un cul-de-sac", not BotBrain.hasEscape(g, { x = 2, y = 1 }, 3, {}))
end

-- Issue sûre ---------------------------------------------------------------------------------------------------
do
	local g, c = makeGrid()
	check("issue : espace ouvert => issue sûre", BotBrain.hasEscape(g, { x = 5, y = 5 }, 2, {}))
end

-- Ennemis : approche et tir ---------------------------------------------------------------------------------
do
	local g = makeGrid()
	local shoot = BotBrain.decide(g, ctx({ x = 5, y = 5 }, { enemies = { { x = 7, y = 5 } } }))
	check("ennemi : bombe quand un ennemi est dans la ligne de tir", shoot.kind == "bomb")
	local far = BotBrain.decide(g, ctx({ x = 1, y = 1 }, { enemies = { { x = 9, y = 9 } }, range = 2 }))
	check("ennemi : s'approche d'un ennemi lointain", far.kind == "move" and far.cell ~= nil)
	local none = BotBrain.decide(g, ctx({ x = 5, y = 5 }))
	check("sans cible ni caisse : attend", none.kind == "wait")
end

-- Cases occupées ---------------------------------------------------------------------------------------------
do
	local g = makeGrid()
	g:setBomb(5, 4, true)
	local danger = BotBrain.blastKeys(g, { x = 5, y = 4 }, 2)
	local action = BotBrain.decide(g, ctx({ x = 5, y = 5 }, { danger = danger }))
	check("bombe posée : le bot ne marche jamais sur une case avec bombe", action.kind ~= "move" or not (action.cell.x == 5 and action.cell.y == 4))
end

-- Déterminisme et hésitation ---------------------------------------------------------------------------------
do
	local g, c = makeGrid()
	c[5][6] = "CRATE"
	local first = BotBrain.decide(g, ctx({ x = 5, y = 5 }))
	local second = BotBrain.decide(g, ctx({ x = 5, y = 5 }))
	check("sans hasard : décision déterministe", first.kind == second.kind)
	local waits, total = 0, 400
	local rng = Random.new(1)
	for _ = 1, total do
		if BotBrain.decide(g, ctx({ x = 5, y = 5 }, { rng = rng })).kind == "wait" then
			waits += 1
		end
	end
	check("hésitation : rare (moins de 15 %) mais présente", waits > 0 and waits < total * 0.15, tostring(waits))
end

print(("[Phase9Tests] %d réussis, %d échecs"):format(passed, failed))
