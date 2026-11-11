--!nocheck
-- Tests de la Phase 11 : catalogue de 24 bombes 3D, boutique, inventaire, achat avec équipement automatique, affichage en jeu.
-- À EXÉCUTER DANS ROBLOX STUDIO, côté CLIENT d'une session Play (barre de commande, sélecteur « Client »). Ces vérifications
-- exigent le moteur (modèles, ViewportFrame, ContentProvider, remotes réels) : elles complètent les suites Lune (tests/unit),
-- qui couvrent la logique pure (catalogue, ShopLogic, ShopService, BombSkinConfig, repli de BombVisuals).
--
-- Préparation :
--   1. ReplicatedStorage.BombModels doit contenir les 24 modèles importés (B01_Classique ... B24_Cristal), voir assets/3D/.../Guide_Import_Studio.md
--   2. Pour la section « achat de bout en bout » : en mode Edit, workspace:SetAttribute("DevStartCoins", 10000) (Studio uniquement,
--      profil temporaire : rien n'est sauvegardé), puis lancer Play. RETIRER l'attribut ensuite (workspace:SetAttribute("DevStartCoins", nil)).
-- Ne bloque jamais (aucune attente d'événement) ; renvoie un résumé. Dernier résultat connu : voir docs/TEST_PLAN.md.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")

local lines, passed, failed = {}, 0, 0
local function check(name: string, condition: boolean, detail: any?)
	if condition then
		passed += 1
	else
		failed += 1
	end
	table.insert(lines, ("[%s] %s%s"):format(condition and "OK" or "ÉCHEC", name, detail ~= nil and (" : " .. tostring(detail)) or ""))
end
local function section(name: string, fn: () -> ())
	table.insert(lines, "== " .. name)
	local ok, err = pcall(fn)
	if not ok then
		failed += 1
		table.insert(lines, "[ERREUR] " .. tostring(err))
	end
end

local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client")
local BombVisuals = require(client.Controllers.BombVisuals)
local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local BombSkinConfig = require(ReplicatedStorage.Shared.BombSkinConfig)
local bombIds = CosmeticConfig.idsOfKind("bomb")

section("Modèles : construction, style, pose (24 bombes)", function()
	check("catalogue : 24 bombes", #bombIds == 24, #bombIds)
	local built, styled, worst = 0, 0, 0
	for _, id in bombIds do
		local cosmetic = CosmeticConfig.get(id)
		local result = BombVisuals.build(cosmetic)
		if result then
			built += 1
			local ok = true
			for _, d in result.model:GetDescendants() do
				if d:IsA("BasePart") then
					local piece = BombSkinConfig.get(cosmetic.model).pieces[d.Name]
					if not piece or d.Material.Name ~= piece[4] or d.CanCollide or not d.Anchored then
						ok = false
					end
				end
			end
			if ok then
				styled += 1
			end
			BombVisuals.place(result, Vector3.new(10, 0, 20), 0)
			local cf, size = result.model:GetBoundingBox()
			worst = math.max(worst, math.abs(cf.Position.Y - size.Y / 2), math.abs(result.model.BombCollar_Base.Position.X - 10))
			result.model:Destroy()
		end
	end
	check("24 modèles construits", built == 24, built)
	check("style conforme à BombSkinConfig pour les 24", styled == 24, styled)
	check("pose : sol à y = 0, col sur le point demandé (écart < 0.01)", worst < 0.01, worst)
end)

section("BombSkinController : 24 fausses bombes posées dans l'arène (locales)", function()
	local arena = workspace:FindFirstChild("Arena")
	local created = false
	if not arena then
		arena = Instance.new("Folder")
		arena.Name = "Arena"
		arena.Parent = workspace
		created = true
	end
	local parts = {}
	for i, id in bombIds do
		local part = Instance.new("Part")
		part.Name, part.Shape, part.Size, part.Anchored, part.CanCollide = "Bomb", Enum.PartType.Ball, Vector3.new(3, 3, 3), true, false
		part.Position = Vector3.new(200 + (i - 1) * 6, 1.6, 300)
		part:SetAttribute("BBBombSkin", id)
		part:SetAttribute("BBGroundY", 0)
		part.Parent = arena
		parts[id] = part
	end
	task.wait(1.5)
	local attached, hidden = 0, 0
	for id, part in parts do
		for _, child in arena:GetChildren() do
			if child:IsA("Model") and child.Name == CosmeticConfig.get(id).model and math.abs(child.BombCollar_Base.Position.X - part.Position.X) < 0.05 then
				attached += 1
			end
		end
		if part.LocalTransparencyModifier == 1 then
			hidden += 1
		end
	end
	check("24 modèles accrochés aux 24 bombes", attached == 24, attached)
	check("sphère de repli masquée en local seulement APRÈS confirmation du chargement", hidden == 24, hidden)
	for _, part in parts do
		part:Destroy()
	end
	task.wait(0.5)
	local left = 0
	for _, child in arena:GetChildren() do
		if child:IsA("Model") then
			left += 1
		end
	end
	check("bombes détruites => modèles détruits", left == 0, left)
	if created then
		arena:Destroy()
	end
end)

section("Repli : échec de chargement (Decal invalide ajouté à la copie CLIENT du modèle Jaune)", function()
	local arena = workspace:FindFirstChild("Arena") or workspace
	local yellow = ReplicatedStorage.BombModels.B05_Jaune
	local bad = Instance.new("Decal")
	bad.Texture = "rbxassetid://1"
	bad.Parent = yellow.BombBody_Base
	local part = Instance.new("Part")
	part.Name, part.Shape, part.Size, part.Anchored, part.CanCollide = "Bomb", Enum.PartType.Ball, Vector3.new(3, 3, 3), true, false
	part.Position = Vector3.new(520, 1.6, 500)
	part:SetAttribute("BBBombSkin", "bomb_yellow")
	part:SetAttribute("BBGroundY", 0)
	part.Parent = arena
	task.wait(4)
	local modelLeft = false
	for _, child in arena:GetChildren() do
		if child:IsA("Model") and child.Name == "B05_Jaune" and math.abs(child.BombCollar_Base.Position.X - 520) < 0.5 then
			modelLeft = true
		end
	end
	check("modèle retiré et sphère de repli TOUJOURS visible", not modelLeft and part.LocalTransparencyModifier == 0)
	part:Destroy()
	bad:Destroy()
end)

section("Effets et animations des bombes (BombFx)", function()
	local BombFx = require(client.Controllers.BombFx)
	local BombEffectsConfig = require(ReplicatedStorage.Shared.BombEffectsConfig)
	check("poseOffset : rebond à l'arrivée (1.5 stud), calme à t = 1 s", BombFx.poseOffset(0, 0).Position.Y > 1.4 and math.abs(BombFx.poseOffset(1, 0.5).Position.Y) < 0.12)
	check("flashLevel : nul avant 65 % de la mèche", BombFx.flashLevel(1, 0.5) == 0)
	local arena = workspace:FindFirstChild("Arena")
	local created = false
	if not arena then
		arena = Instance.new("Folder")
		arena.Name = "Arena"
		arena.Parent = workspace
		created = true
	end
	-- bombes NEUVES (instant de pose = maintenant) : les fausses bombes n'explosent jamais, donc au-delà de 2 s elles clignotent
	local parts = {}
	for i, id in bombIds do
		local part = Instance.new("Part")
		part.Name, part.Shape, part.Size, part.Anchored, part.CanCollide = "Bomb", Enum.PartType.Ball, Vector3.new(3, 3, 3), true, false
		part.Position = Vector3.new(700 + (i - 1) * 6, 1.6, 700)
		part:SetAttribute("BBBombSkin", id)
		part:SetAttribute("BBGroundY", 0)
		part:SetAttribute("BBPlacedAt", workspace:GetServerTimeNow() - 0.02)
		part.Parent = arena
		parts[id] = part
	end
	task.wait(0.15)
	local function modelOf(id: string): Model?
		for _, c in arena:GetChildren() do
			if c:IsA("Model") and c.Name == CosmeticConfig.get(id).model and math.abs(c.BombCollar_Base.Position.X - parts[id].Position.X) < 1 then
				return c
			end
		end
		return nil
	end
	local bad = {}
	for _, id in bombIds do
		local cfg = BombEffectsConfig.get(CosmeticConfig.get(id).model)
		local expected = (cfg.fuse ~= false and 2 or 0) + #(cfg.emitters or {})
		local got = 0
		for _, d in modelOf(id):GetDescendants() do
			if d:IsA("ParticleEmitter") and d.Name:find("^BBFx_") then
				got += 1
			end
		end
		if got ~= expected then
			table.insert(bad, id)
		end
	end
	check("émetteurs de chaque bombe conformes à BombEffectsConfig (24)", #bad == 0, table.concat(bad, ","))
	local movers = { bomb_lava = "BombBody_Base", bomb_rainbow = "BombBody_Band1", bomb_electric = "BombBody_CrackGlow", bomb_robot = "BombSkin_Glow", bomb_heart = "BombBody_Inner", bomb_pumpkin = "BombSkin_Face" }
	local seen = {}
	local t0 = os.clock()
	while os.clock() - t0 < 0.85 do -- reste sous 65 % de la mèche : aucun clignotement
		for id, pieceName in movers do
			seen[id] = seen[id] or {}
			seen[id][modelOf(id)[pieceName].Color:ToHex()] = true
		end
		seen.bomb_red = seen.bomb_red or {}
		seen.bomb_red[modelOf("bomb_red").BombBody_Base.Color:ToHex()] = true
		task.wait(0.03)
	end
	local function distinct(set: { [string]: boolean }): number
		local n = 0
		for _ in set do
			n += 1
		end
		return n
	end
	local animatedOk = true
	for id in movers do
		if distinct(seen[id]) < 2 then
			animatedOk = false
		end
	end
	check("couleurs animées (lave, arc-en-ciel, électrique, robot, cœur, citrouille)", animatedOk)
	check("bombe sans effet de couleur : couleur de base inchangée", distinct(seen.bomb_red) == 1)
	-- clignotement final : bombe posée il y a 1.5 s (75 % de la mèche)
	local late = Instance.new("Part")
	late.Name, late.Shape, late.Size, late.Anchored, late.CanCollide = "Bomb", Enum.PartType.Ball, Vector3.new(3, 3, 3), true, false
	late.Position = Vector3.new(900, 1.6, 900)
	late:SetAttribute("BBBombSkin", "bomb_blue")
	late:SetAttribute("BBGroundY", 0)
	late:SetAttribute("BBPlacedAt", workspace:GetServerTimeNow() - 1.5)
	late.Parent = arena
	task.wait(0.1)
	local lateModel
	for _, c in arena:GetChildren() do
		if c:IsA("Model") and c.Name == "B03_Bleue" and math.abs(c.BombCollar_Base.Position.X - 900) < 1 then
			lateModel = c
		end
	end
	local lighter = 0
	for _ = 1, 30 do
		if lateModel.BombBody_Base.Color.R > 0x28 / 255 + 0.05 then
			lighter += 1
		end
		task.wait(0.01)
	end
	check("clignotement : le corps vire au blanc par intermittence en fin de mèche", lighter >= 3, lighter)
	late:Destroy()
	for _, part in parts do
		part:Destroy()
	end
	task.wait(0.3)
	if created then
		arena:Destroy()
	end
end)

section("Mèche allumée : flamme néon (BombFlame) dans la boutique, le HUD, le menu et en jeu", function()
	-- Les particules ne s'affichent pas dans un ViewportFrame : la flamme est faite de pièces néon animées.
	local CosmeticBrowser = require(client.UI.Screens.CosmeticBrowser)
	local function flameParts(root: Instance): { BasePart }
		local list = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.Name:find("^BBFlame_") then
				table.insert(list, d)
			end
		end
		return list
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "__test_flame"
	gui.Parent = Players.LocalPlayer.PlayerGui
	local ctx = { closeOverlay = function() end, purchase = function() end, equip = function() end }
	local profile = { coins = 5000, wins = 0, matches = 0, owned = { bomb_classic = true, bomb_cosmic = true, effect_classic = true }, equipped = { bomb = "bomb_classic", effect = "effect_classic" }, quests = {}, persisted = false }
	local shop = CosmeticBrowser.new(gui, ctx, "shop")
	shop.setProfile(profile)
	task.wait(0.1)
	local detail = shop.frame.Panel.Detail.Preview
	check("aperçu détaillé : flamme complète (goutte 8 + 3, étoile 7, étincelles 6 = 24 pièces) + effet d'ambiance de la bombe sélectionnée", #flameParts(detail) >= 24, #flameParts(detail))
	local model = detail.Preview3D:FindFirstChildOfClass("Model")
	local puff = model.BBFlame_Outer1
	local size0 = puff.Size.X
	task.wait(0.55)
	check("allumage : la flamme grandit après l'affichage", puff.Size.X > size0 * 2, ("%.3f -> %.3f"):format(size0, puff.Size.X))
	local farthest = 0
	for _ = 1, 30 do
		farthest = math.max(farthest, (puff.Position - model.BombFuse_Tip.Position).Magnitude)
		task.wait(0.03)
	end
	check("la flamme reste collée au bout de la mèche pendant la rotation (< 0.5)", farthest < 0.5, farthest)
	local lightCards = 0
	for _, c in shop.frame.Panel.Grid:GetChildren() do
		local holder = c:IsA("TextButton") and c:FindFirstChild("Preview3DHolder")
		local viewport = holder and holder:FindFirstChild("Preview3D")
		if viewport and #flameParts(viewport) == 10 then
			lightCards += 1
		end
	end
	check("miniatures : flamme FIGÉE (5 + 2 + 3 = 10 pièces) sur les cartes visibles (8 à 20)", lightCards >= 8 and lightCards <= 20, lightCards)
	-- GRILLE STATIQUE : aucune pièce de flamme des miniatures ne bouge ; l'aperçu de droite, si.
	local function snapshot(root: Instance)
		local t = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and (d.Name:find("^BBFlame_") or d.Name:find("^BBAura_")) then
				t[d] = { d.CFrame, d.Size, d.Transparency }
			end
		end
		return t
	end
	local function movedCount(before: { [BasePart]: { any } }): number
		local n = 0
		for part, state in before do
			if part.Parent and (part.CFrame ~= state[1] or part.Size ~= state[2] or part.Transparency ~= state[3]) then
				n += 1
			end
		end
		return n
	end
	local gridBefore, detailBefore = snapshot(shop.frame.Panel.Grid), snapshot(detail)
	task.wait(1)
	check("GRILLE STATIQUE : 0 pièce des miniatures ne bouge en 1 s", movedCount(gridBefore) == 0, movedCount(gridBefore))
	check("aperçu de droite : toutes ses pièces bougent", movedCount(detailBefore) > 20, movedCount(detailBefore))
	local previous = detail:FindFirstChildWhichIsA("ViewportFrame", true)
	shop.select("bomb_ice")
	task.wait(0.4)
	check("changement de bombe : l'ancien aperçu est détruit et le nouveau s'anime", previous.Parent == nil and #detail:GetDescendants() > 0)
	shop.frame.Visible = false
	task.wait(0.3)
	local hiddenBefore = snapshot(detail)
	task.wait(0.8)
	check("écran caché : plus aucune pièce ne bouge (animation suspendue)", movedCount(hiddenBefore) == 0, movedCount(hiddenBefore))
	shop.frame.Visible = true
	local before = #flameParts(gui)
	shop.frame:Destroy()
	task.wait(0.3)
	check("écran fermé : toutes les pièces de flamme détruites", before > 0 and #flameParts(gui) == 0, ("%d -> %d"):format(before, #flameParts(gui)))
	gui:Destroy()
	local scene = workspace:FindFirstChild("MenuScene")
	if scene then
		local held
		for _, d in scene:GetDescendants() do
			if d.Name == "HeldBomb" then
				held = d.Parent:FindFirstChildWhichIsA("Model") and d
			end
		end
		check("menu : flamme complète sur la bombe tenue en main (si le menu est affiché)", held == nil or #flameParts(held.Parent) >= 6, held and #flameParts(held.Parent))
	end
end)

section("Boutique et inventaire (vrai module d'interface)", function()
	local CosmeticBrowser = require(client.UI.Screens.CosmeticBrowser)
	local gui = Instance.new("ScreenGui")
	gui.Name = "__test_shop"
	gui.Parent = Players.LocalPlayer.PlayerGui
	local ctx = { closeOverlay = function() end, purchase = function() end, equip = function() end }
	local profile = { coins = 5000, wins = 0, matches = 0, owned = { bomb_classic = true, bomb_cosmic = true, effect_classic = true }, equipped = { bomb = "bomb_classic", effect = "effect_classic" }, quests = {}, persisted = false }
	local function count(root: Instance, name: string): number
		local n = 0
		for _, d in root:GetDescendants() do
			if d:IsA("ViewportFrame") and d.Name == name then
				n += 1
			end
		end
		return n
	end
	local shop = CosmeticBrowser.new(gui, ctx, "shop")
	shop.setProfile(profile)
	task.wait(0.5)
	local grid = shop.frame.Panel.Grid
	local cards = 0
	for _, c in grid:GetChildren() do
		if c:IsA("TextButton") then
			cards += 1
		end
	end
	check("boutique : 24 cartes de bombes", cards == 24, cards)
	check("miniatures 3D seulement pour les cartes visibles (8 à 20)", count(grid, "Preview3D") >= 8 and count(grid, "Preview3D") <= 20, count(grid, "Preview3D"))
	check("aperçu 3D rotatif dans le détail", count(shop.frame.Panel.Detail.Preview, "Preview3D") == 1)
	grid.CanvasPosition = Vector2.new(0, 2000)
	task.wait(0.3)
	check("défilement : miniature du bas créée, du haut retirée", grid.Card_bomb_cosmic.Preview3DHolder:FindFirstChild("Preview3D") ~= nil and grid.Card_bomb_classic.Preview3DHolder:FindFirstChild("Preview3D") == nil)
	local inventory = CosmeticBrowser.new(gui, ctx, "inventory")
	inventory.setProfile(profile)
	local owned = 0
	for _, c in inventory.frame.Panel.Grid:GetChildren() do
		if c:IsA("TextButton") then
			owned += 1
		end
	end
	check("inventaire : seulement les bombes possédées (2)", owned == 2, owned)
	gui:Destroy()
end)

section("Achat de bout en bout (vrais remotes ; exige DevStartCoins)", function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local lastResult, lastProfile, nResults = nil, nil, 0
	remotes.ShopResult.OnClientEvent:Connect(function(r)
		lastResult, nResults = r, nResults + 1
	end)
	remotes.ProfileUpdated.OnClientEvent:Connect(function(p)
		lastProfile = p
	end)
	local function request(kind: string, id: string)
		local before = nResults
		lastResult = nil
		remotes[kind == "purchase" and "RequestPurchase" or "RequestEquip"]:FireServer(id)
		local t = os.clock()
		while nResults == before and os.clock() - t < 2 do
			task.wait(0.05)
		end
		task.wait(0.8) -- cadence serveur : 0,5 s
		return lastResult
	end
	local r = request("purchase", "bomb_cosmic")
	if not (r and r.ok) then
		table.insert(lines, "(section ignorée : achat refusé, profil sans pièces ? DevStartCoins non posé avant le Play)")
		return
	end
	check("achat Cosmique : accepté ET équipé automatiquement", r.equipped == true and lastProfile.equipped.bomb == "bomb_cosmic")
	r = request("purchase", "bomb_cosmic")
	check("doublon refusé (owned)", r.ok == false and r.error == "owned")
	r = request("purchase", "bomb_lava")
	check("2e bombe : équipée à la place, la 1re reste possédée", r.equipped == true and lastProfile.equipped.bomb == "bomb_lava" and lastProfile.owned.bomb_cosmic == true)
	r = request("equip", "bomb_cosmic")
	check("inventaire : rééquiper la Cosmique", r.ok and lastProfile.equipped.bomb == "bomb_cosmic")
	r = request("equip", "bomb_robot")
	check("bombe non possédée : refusée", r.ok == false and r.error == "not_owned")
	r = request("purchase", "effect_red")
	check("effet acheté : PAS équipé automatiquement", r.ok and r.equipped == false and lastProfile.equipped.effect == "effect_classic")
end)

local history = LogService:GetLogHistory()
local errors = 0
for _, h in history do
	if h.messageType == Enum.MessageType.MessageError then
		errors += 1
	end
end
table.insert(lines, ("journal client : %d erreur(s)"):format(errors))
table.insert(lines, ("RÉSULTAT : %d contrôles réussis, %d échecs"):format(passed, failed))
return table.concat(lines, "\n")
