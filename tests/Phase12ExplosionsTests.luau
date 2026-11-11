--!nocheck
-- Tests de la Phase 5 (explosions) : moteur visuel modulaire (ExplosionFx) et système de manche réel.
-- À EXÉCUTER DANS ROBLOX STUDIO, côté CLIENT d'une session Play (barre de commande). Le moteur est testé directement (copie du module
-- chargée par la barre de commande : ses compteurs sont ceux de CETTE copie, pas ceux du jeu) ; la section « vraie manche » observe
-- le jeu réel par ses effets (dossier Workspace.BBExplosionFx, dalles « Flame »).
-- Préparation de la vraie manche : en mode Edit, workspace:SetAttribute("DevStartCoins", 10000) n'est pas nécessaire ; lancer Play.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local ExplosionFx = require(Players.LocalPlayer.PlayerScripts.Client.Controllers.ExplosionFx)

local lines, passed, failed = {}, 0, 0
local function check(name, condition, detail)
	if condition then passed += 1 else failed += 1 end
	table.insert(lines, ("[%s] %s%s"):format(condition and "OK" or "ÉCHEC", name, detail ~= nil and (" : " .. tostring(detail)) or ""))
end
local function live()
	local folder = workspace:FindFirstChild("BBExplosionFx")
	return folder and #folder:GetChildren() or 0
end
local function cross(cx, cy, range)
	local cells = { { x = cx, y = cy } }
	for s = 1, range do
		table.insert(cells, { x = cx + s, y = cy }); table.insert(cells, { x = cx - s, y = cy })
		table.insert(cells, { x = cx, y = cy + s }); table.insert(cells, { x = cx, y = cy - s })
	end
	return cells
end

local info = { origin = Vector3.new(880, 0, 880), cellSize = 4 }
local payload = { cells = cross(6, 6, 2), origins = { { x = 6, y = 6 } }, crates = { { x = 8, y = 6 } }, style = "effect_classic", color = Color3.fromRGB(255, 150, 30), duration = 0.5 }

check("départ propre : aucun élément", ExplosionFx.activeCount() == 0 and live() == 0)
ExplosionFx.play(info, payload)
task.wait(0.05)
local n1 = live()
check("portée 2 (9 cases) : décor modulaire posé (> 40 pièces)", n1 > 40 and ExplosionFx.activeCount() == n1, n1)
task.wait(1.1)
check("tout est nettoyé 1,15 s après : 0 pièce, 0 élément", live() == 0 and ExplosionFx.activeCount() == 0)
local pooled = 0
for _, v in ExplosionFx.poolSizes() do pooled += v end
check("les pièces retournent dans les pools", pooled >= n1 - 4, pooled)
ExplosionFx.play(info, payload)
task.wait(0.05)
local poolAfter = 0
for _, v in ExplosionFx.poolSizes() do poolAfter += v end
check("2e explosion : pièces reprises dans le pool (rien de plus créé)", poolAfter + live() <= pooled + 4)
task.wait(1.2)
for _, bad in { "x", 5, {}, { cells = "x" }, { cells = { { x = "a", y = 1 }, 7 } }, { cells = { { x = 1, y = 1 } }, duration = 9999, style = 12, color = "rouge" } } do
	ExplosionFx.play(info, bad)
end
task.wait(2.5)
check("charges invalides et durée absurde (bornée à 2 s) : aucune erreur, tout nettoyé", ExplosionFx.activeCount() == 0 and live() == 0)
local big, seen = {}, {}
local origins = { { x = 5, y = 5 }, { x = 11, y = 5 }, { x = 5, y = 11 }, { x = 11, y = 11 } }
for _, c in origins do
	for _, cell in cross(c.x, c.y, 5) do
		local k = cell.x .. ":" .. cell.y
		if not seen[k] then seen[k] = true; table.insert(big, cell) end
	end
end
local t0 = os.clock()
ExplosionFx.play(info, { cells = big, origins = origins, crates = {}, style = "effect_classic", duration = 0.5 })
local buildMs = (os.clock() - t0) * 1000
task.wait(0.1)
check(("chaîne de 4 bombes portée 5 (%d cases) : construction < 30 ms, <= 700 éléments"):format(#big), buildMs < 30 and ExplosionFx.activeCount() <= 700, ("%.1f ms, %d éléments"):format(buildMs, ExplosionFx.activeCount()))
task.wait(1.3)
check("chaîne terminée : tout nettoyé", ExplosionFx.activeCount() == 0 and live() == 0)

-- Vraie manche : le serveur envoie cases + origines + caisses + style ; une dalle par case ; décor en plus (observé par ses effets).
local ok, err = pcall(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local state, received = "?", nil
	remotes.RoundState.OnClientEvent:Connect(function(s) if typeof(s) == "table" then state = tostring(s.state) end end)
	remotes.Explosion.OnClientEvent:Connect(function(p) received = p end)
	remotes.SetQueued:FireServer(true)
	task.wait(0.8)
	remotes.SetReady:FireServer(true)
	local t = os.clock()
	while state ~= "PLAYING" and os.clock() - t < 30 do task.wait(0.25) end
	if state ~= "PLAYING" then check("manche démarrée", false, state) return end
	task.wait(3)
	remotes.RequestPlaceBomb:FireServer()
	local maxPieces, sawTiles = 0, 0
	t = os.clock()
	while os.clock() - t < 4.5 do
		maxPieces = math.max(maxPieces, live())
		local tiles = 0
		for _, c in workspace:GetChildren() do if c.Name == "Flame" then tiles += 1 end end
		sawTiles = math.max(sawTiles, tiles)
		task.wait(0.02)
	end
	check("charge utile réelle : cases, origines, caisses, style effect_classic, durée 0,5, couleur", received ~= nil and typeof(received.origins) == "table" and typeof(received.crates) == "table" and received.style == "effect_classic" and received.duration == 0.5 and typeof(received.color) == "Color3")
	check("dalles de danger : exactement une par case décidée par le serveur", received ~= nil and sawTiles == #received.cells, received and (sawTiles .. " / " .. #received.cells))
	check("décor modulaire posé en plus des dalles", maxPieces > 20, maxPieces)
end)
if not ok then check("vraie manche", false, err) end

local errors = 0
for _, h in LogService:GetLogHistory() do
	if h.messageType == Enum.MessageType.MessageError then errors += 1 end
end
table.insert(lines, ("journal client : %d erreur(s)"):format(errors))
table.insert(lines, ("RÉSULTAT : %d contrôles réussis, %d échecs"):format(passed, failed))
return table.concat(lines, "\n")
