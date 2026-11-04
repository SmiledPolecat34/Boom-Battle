--!nocheck
-- Contrôleurs client : InputController, MovementController, CameraController, EffectsController, InviteController,
-- RoundController, TouchControls, MobileAssets, Components. Entrées simulées (UserInputService), temps simulé.
-- Aucun rendu : on vérifie ce qui est ENVOYÉ au serveur et l'état des objets construits.
local Theme = world.module("Theme")

local info
local function input(overrides)
	local base = { UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown, Position = Vector3.new(0, 0, 0) }
	for k, v in overrides or {} do
		base[k] = v
	end
	return base
end

local function UIS()
	return world.game:GetService("UserInputService")
end

-- Caméra de dessus simulée : le pixel (x, y) vise le sol en ((x - 640) / 10, (y - 360) / 10).
local function installTopDownCamera()
	local camera = world.env.workspace.CurrentCamera
	camera.ScreenPointToRay = function(_self, x, y)
		return { Origin = Vector3.new((x - 640) / 10, 50, (y - 360) / 10), Direction = Vector3.new(0, -1, 0) }
	end
	return camera
end

beforeEach(function()
	world.reset()
	info = { sizeId = "Medium", size = 16, cellSize = 4, origin = Vector3.new(-32, 0, -32), seed = 1 }
end)

describe("InputController", function()
	it("clic gauche et toucher appellent le rappel avec la position écran ; le reste est ignoré", function()
		local Input = world.module("InputController")
		local positions = {}
		Input.onPrimaryAction(function(position)
			table.insert(positions, position)
		end)
		UIS()._fireInputBegan(input({ Position = Vector3.new(100, 200, 0) }), false)
		UIS()._fireInputBegan(input({ UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(5, 6, 0) }), false)
		UIS()._fireInputBegan(input({ UserInputType = Enum.UserInputType.Keyboard }), false)
		UIS()._fireInputBegan(input({ UserInputType = Enum.UserInputType.MouseButton2 }), false)
		expect(#positions).toBe(2)
		expect(positions[1]).toEqual(Vector2.new(100, 200))
		expect(positions[2]).toEqual(Vector2.new(5, 6))
	end)

	it("un clic capté par l'interface (gameProcessed) est ignoré", function()
		local Input = world.module("InputController")
		local count = 0
		Input.onPrimaryAction(function()
			count += 1
		end)
		UIS()._fireInputBegan(input(), true)
		expect(count).toBe(0)
	end)

	it("un nouveau rappel remplace l'ancien (pas de double déclenchement) ; stop désactive", function()
		local Input = world.module("InputController")
		local a, b = 0, 0
		Input.onPrimaryAction(function() a += 1 end)
		Input.onPrimaryAction(function() b += 1 end)
		UIS()._fireInputBegan(input(), false)
		expect(a).toBe(0)
		expect(b).toBe(1)
		Input.stop()
		UIS()._fireInputBegan(input(), false)
		expect(b).toBe(1)
	end)

	it("Espace pose la bombe même si le saut l'a « consommé », sauf pendant une saisie de texte", function()
		local Input = world.module("InputController")
		local bombs = 0
		Input.onBombKey(function() bombs += 1 end)
		UIS()._fireInputBegan(input({ KeyCode = Enum.KeyCode.Space, UserInputType = Enum.UserInputType.Keyboard }), true)
		expect(bombs).toBe(1)
		UIS().focusedTextBox = {}
		UIS()._fireInputBegan(input({ KeyCode = Enum.KeyCode.Space, UserInputType = Enum.UserInputType.Keyboard }), false)
		expect(bombs).toBe(1)
		UIS().focusedTextBox = nil
		UIS()._fireInputBegan(input({ KeyCode = Enum.KeyCode.E, UserInputType = Enum.UserInputType.Keyboard }), false)
		expect(bombs).toBe(1)
	end)

	it("stop du déplacement ne coupe pas le raccourci Espace du HUD", function()
		local Input = world.module("InputController")
		local bombs = 0
		Input.onBombKey(function() bombs += 1 end)
		Input.stop()
		UIS()._fireInputBegan(input({ KeyCode = Enum.KeyCode.Space, UserInputType = Enum.UserInputType.Keyboard }), false)
		expect(bombs).toBe(1)
	end)

	it("direction tenue : WASD et flèches ; rien => nil ; saisie de texte => nil", function()
		local Input = world.module("InputController")
		expect(Input.getHeldDirection()).toBeNil()
		for key, expected in { W = Vector2.new(0, -1), A = Vector2.new(-1, 0), S = Vector2.new(0, 1), D = Vector2.new(1, 0), Up = Vector2.new(0, -1), Left = Vector2.new(-1, 0) } do
			UIS().heldKeys = { [Enum.KeyCode[key]] = true }
			expect(Input.getHeldDirection()).toEqual(expected)
		end
		UIS().focusedTextBox = {}
		expect(Input.getHeldDirection()).toBeNil()
	end)

	it("direction virtuelle (joystick) utilisée quand aucune touche n'est tenue ; relâcher la retire", function()
		local Input = world.module("InputController")
		Input.setVirtualDirection(Vector2.new(1, 0))
		expect(Input.getHeldDirection()).toEqual(Vector2.new(1, 0))
		UIS().heldKeys = { [Enum.KeyCode.W] = true }
		expect(Input.getHeldDirection()).toEqual(Vector2.new(0, -1)) -- le clavier prime
		UIS().heldKeys = {}
		Input.setVirtualDirection(nil)
		expect(Input.getHeldDirection()).toBeNil()
	end)
end)

describe("MovementController", function()
	local remotes, Movement, Camera
	local function localCharacterAt(cellX, cellY)
		local player = world.game:GetService("Players").LocalPlayer
		player.Character = Fixtures.instanceCharacter(Vector3.new(-32 + (cellX - 0.5) * 4, 3, -32 + (cellY - 0.5) * 4))
		return player
	end
	local function markers()
		local list = {}
		for _, child in world.env.workspace:GetChildren() do
			if child.Name == "MoveMarker" then
				table.insert(list, child)
			end
		end
		return list
	end

	beforeEach(function()
		installTopDownCamera()
		remotes = Fixtures.fakeRemotes({ "RequestMove", "MoveRejected" })
		Movement = world.module("MovementController")
		Camera = world.module("CameraController")
		Movement.start(info, remotes)
		localCharacterAt(9, 9)
	end)

	it("un clic sur l'arène envoie UNIQUEMENT la case visée", function()
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		expect(#remotes.RequestMove.sentToServer).toBe(1)
		expect(remotes.RequestMove.sentToServer[1][1]).toEqual({ x = 9, y = 9 })
		expect(remotes.RequestMove.sentToServer[1].n).toBe(1)
	end)

	it("un clic hors de l'arène, sans personnage, ou avec la caméra du menu : rien n'est envoyé", function()
		UIS()._fireInputBegan(input({ Position = Vector3.new(5000, 360, 0) }), false)
		UIS()._fireInputBegan(input({ Position = Vector3.new(-5000, 360, 0) }), false)
		world.game:GetService("Players").LocalPlayer.Character = nil
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		localCharacterAt(9, 9)
		Camera.setOverride(CFrame.new(0, 10, 0), 50)
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		expect(#remotes.RequestMove.sentToServer).toBe(0)
		Camera.setOverride(nil)
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		expect(#remotes.RequestMove.sentToServer).toBe(1)
	end)

	it("rayon horizontal ou dirigé vers le haut : aucune case", function()
		local camera = world.env.workspace.CurrentCamera
		camera.ScreenPointToRay = function()
			return { Origin = Vector3.new(0, 50, 0), Direction = Vector3.new(1, 0, 0) }
		end
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		camera.ScreenPointToRay = function()
			return { Origin = Vector3.new(0, 50, 0), Direction = Vector3.new(0, 1, 0) }
		end
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		expect(#remotes.RequestMove.sentToServer).toBe(0)
	end)

	it("repère visuel : blanc à l'envoi, rouge au refus du serveur, supprimé après sa durée ; désactivable", function()
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		expect(#markers()).toBe(1)
		expect(markers()[1].Color).toEqual(Color3.new(1, 1, 1))
		remotes.MoveRejected:fireClient({ x = 3, y = 3 })
		expect(#markers()).toBe(1) -- l'ancien repère est remplacé
		expect(markers()[1].Color).toEqual(Color3.fromRGB(235, 64, 52))
		world.advance(1)
		expect(#markers()).toBe(0)
		world.module("SettingsStore").set("showMoveMarker", false)
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		expect(#markers()).toBe(0)
	end)

	it("refus malformé du serveur (texte, case incomplète, nil) : ignoré sans erreur", function()
		for _, bad in { "x", 5, { x = "1", y = 2 }, { x = 1 }, {} } do
			remotes.MoveRejected:fireClient(bad)
		end
		remotes.MoveRejected:fireClient(nil)
		expect(#markers()).toBe(0)
	end)

	it("clavier : la direction tenue demande la case voisine, limité en cadence, jamais hors grille", function()
		UIS().heldKeys = { [Enum.KeyCode.W] = true }
		world.fireHeartbeat(0.016)
		expect(remotes.RequestMove.sentToServer[1][1]).toEqual({ x = 9, y = 8 })
		world.fireHeartbeat(0.016) -- trop tôt : même instant
		expect(#remotes.RequestMove.sentToServer).toBe(1)
		world.advance(0.2)
		world.fireHeartbeat(0.016)
		expect(#remotes.RequestMove.sentToServer).toBe(2)
		localCharacterAt(9, 1)
		world.advance(0.2)
		world.fireHeartbeat(0.016) -- vers le haut depuis la ligne 1 : hors grille
		expect(#remotes.RequestMove.sentToServer).toBe(2)
	end)

	it("clavier : pas de demande pendant une saisie de texte, avec la caméra du menu, ou sans touche", function()
		world.fireHeartbeat(0.016)
		UIS().heldKeys = { [Enum.KeyCode.D] = true }
		UIS().focusedTextBox = {}
		world.fireHeartbeat(0.016)
		UIS().focusedTextBox = nil
		Camera.setOverride(CFrame.new(0, 10, 0), 50)
		world.fireHeartbeat(0.016)
		expect(#remotes.RequestMove.sentToServer).toBe(0)
	end)

	it("stop : plus aucune demande ni repère", function()
		Movement.stop()
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		UIS().heldKeys = { [Enum.KeyCode.W] = true }
		world.fireHeartbeat(0.016)
		expect(#remotes.RequestMove.sentToServer).toBe(0)
		expect(#markers()).toBe(0)
	end)

	it("redémarrer ne double pas les demandes", function()
		Movement.start(info, remotes)
		UIS()._fireInputBegan(input({ Position = Vector3.new(640, 360, 0) }), false)
		expect(#remotes.RequestMove.sentToServer).toBe(1)
	end)
end)

describe("CameraController", function()
	local Camera, camera

	local function corners()
		local half = (info.size + 2) * info.cellSize / 2
		local center = info.origin + Vector3.new(info.size * info.cellSize / 2, 0, info.size * info.cellSize / 2)
		local list = {}
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				for _, y in { 0, 4 } do
					table.insert(list, center + Vector3.new(sx * half, y, sz * half))
				end
			end
		end
		return list
	end

	-- Vrai si le point est dans le champ de la caméra. La caméra vise le centre de l'arène : on recalcule la base
	-- (avant, droite, haut) depuis sa POSITION (la rotation de CFrame.lookAt de Lune diffère de celle de Roblox).
	local function visible(point, viewport)
		local center = info.origin + Vector3.new(info.size * info.cellSize / 2, 0, info.size * info.cellSize / 2)
		local position = camera.CFrame.Position
		local look = (center - position).Unit
		local right = look:Cross(Vector3.new(0, 1, 0)).Unit
		local up = right:Cross(look).Unit
		local offset = point - position
		local depth, x, y = offset:Dot(look), offset:Dot(right), offset:Dot(up)
		if depth <= 0 then
			return false
		end
		local tanV = math.tan(math.rad(camera.FieldOfView) / 2)
		local tanH = tanV * viewport.X / viewport.Y
		return math.abs(x) <= depth * tanH + 1e-6 and math.abs(y) <= depth * tanV + 1e-6
	end

	beforeEach(function()
		Camera = world.module("CameraController")
		camera = world.env.workspace.CurrentCamera
	end)

	it("caméra fixe (Scriptable) cadrée au-dessus de l'arène", function()
		Camera.apply(info)
		expect(camera.CameraType).toBe(Enum.CameraType.Scriptable)
		expect(camera.CFrame.Position.Y).toBeGreaterThan(10)
	end)

	for label, viewport in { ["écran large 16:9"] = Vector2.new(1280, 720), ["téléphone en hauteur"] = Vector2.new(390, 844), ["carré"] = Vector2.new(800, 800) } do
		it("les 8 coins de l'arène (murs compris) restent à l'écran : " .. label, function()
			camera.ViewportSize = viewport
			Camera.apply(info)
			camera.ViewportSize = viewport -- redéclenche le cadrage
			for _, point in corners() do
				expect(visible(point, viewport)).toBe(true)
			end
		end)
	end

	it("le cadrage suit le changement de taille de l'écran", function()
		Camera.apply(info)
		local before = camera.CFrame.Position
		camera.ViewportSize = Vector2.new(390, 844)
		expect(camera.CFrame.Position).never.toEqual(before)
	end)

	it("orientation : le joueur est toujours en bas de l'écran (lacet par pas de 90°)", function()
		local player = world.game:GetService("Players").LocalPlayer
		local center = info.origin + Vector3.new(32, 0, 32)
		local cases = {
			{ Vector3.new(0, 3, 20), Vector2.new(0, -1), Vector2.new(0, -1) }, -- spawn côté +Z : écran = grille
			{ Vector3.new(0, 3, -20), Vector2.new(0, -1), Vector2.new(0, 1) }, -- côté -Z : inversé
			{ Vector3.new(20, 3, 0), Vector2.new(1, 0), Vector2.new(0, -1) }, -- côté +X : tourné
		}
		for _, case in cases do
			world.reset()
			Camera = world.module("CameraController")
			player = world.game:GetService("Players").LocalPlayer
			camera = world.env.workspace.CurrentCamera
			player.Character = Fixtures.instanceCharacter(center + case[1])
			Camera.apply(info)
			world.advance(1.5)
			local mapped = Camera.screenToGrid(case[2])
			expect(mapped).toEqual(case[3])
		end
	end)

	it("screenToGrid : sans orientation, l'identité ; toujours une direction unitaire d'axe", function()
		local identity = Camera.screenToGrid(Vector2.new(1, 0))
		expect(identity).toEqual(Vector2.new(1, 0))
		for _, d in { Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(0, -1) } do
			local g = Camera.screenToGrid(d)
			expect(math.abs(g.X) + math.abs(g.Y)).toBe(1)
		end
	end)

	it("caméra du décor de menu : prioritaire, champ de vision borné, retour au cadrage de l'arène", function()
		Camera.apply(info)
		local arena = camera.CFrame
		local menuView = CFrame.new(5, 6, 7)
		Camera.setOverride(menuView, 50)
		expect(Camera.isOverridden()).toBe(true)
		expect(camera.CFrame).toEqual(menuView)
		expect(camera.FieldOfView).toBeGreaterThanOrEqual(20)
		expect(camera.FieldOfView).toBeLessThanOrEqual(110)
		Camera.setOverride(nil)
		expect(Camera.isOverridden()).toBe(false)
		expect(camera.CFrame).toEqual(arena)
	end)

	it("champ de vision borné même pour un écran extrême", function()
		for _, viewport in { Vector2.new(100, 3000), Vector2.new(4000, 100) } do
			camera.ViewportSize = viewport
			Camera.setOverride(CFrame.new(0, 0, 0), 50)
			expect(camera.FieldOfView).toBeGreaterThanOrEqual(20)
			expect(camera.FieldOfView).toBeLessThanOrEqual(110)
		end
	end)

	it("stop déconnecte les écouteurs ; reappliquer ne les multiplie pas", function()
		Camera.apply(info)
		Camera.apply(info)
		Camera.stop()
		local before = camera.CFrame
		camera.ViewportSize = Vector2.new(390, 844)
		expect(camera.CFrame).toEqual(before)
	end)

	it("Roblox qui repasse la caméra en mode Custom : on la remet en fixe", function()
		Camera.apply(info)
		camera.CameraType = Enum.CameraType.Custom
		expect(camera.CameraType).toBe(Enum.CameraType.Scriptable)
	end)
end)

describe("EffectsController", function()
	local Effects, remotes
	local function flames()
		local list = {}
		for _, child in world.env.workspace:GetChildren() do
			if child.Name == "Flame" then
				table.insert(list, child)
			end
		end
		return list
	end

	beforeEach(function()
		Effects = world.module("EffectsController")
		remotes = Fixtures.fakeRemotes({ "Explosion" })
		Effects.start(info, remotes)
	end)

	it("une flamme par case touchée, centrée sur la case, pendant la durée annoncée", function()
		remotes.Explosion:fireClient({ cells = { { x = 1, y = 1 }, { x = 2, y = 1 } }, duration = 0.5 })
		local list = flames()
		expect(#list).toBe(2)
		expect(list[1].Position).toEqual(info.origin + Vector3.new(2, 0.25, 2))
		world.advance(0.4)
		expect(#flames()).toBe(2)
		world.advance(0.3)
		expect(#flames()).toBe(0)
	end)

	it("les flammes sont recyclées (pool) : mêmes objets à l'explosion suivante", function()
		remotes.Explosion:fireClient({ cells = { { x = 1, y = 1 } }, duration = 0.2 })
		local first = flames()[1]
		world.advance(0.3)
		remotes.Explosion:fireClient({ cells = { { x = 3, y = 3 } }, duration = 0.2 })
		expect(flames()[1]).toBe(first)
	end)

	it("charges malformées ignorées : pas de cases, mauvaises cases, durée absurde bornée", function()
		for _, bad in { "x", 5, {}, { cells = "x" } } do
			remotes.Explosion:fireClient(bad)
		end
		remotes.Explosion:fireClient({ cells = { { x = "1", y = 2 }, { x = 1 }, 7, "a" } })
		expect(#flames()).toBe(0)
		remotes.Explosion:fireClient({ cells = { { x = 1, y = 1 } }, duration = 9999 })
		world.advance(2.1)
		expect(#flames()).toBe(0) -- bornée à 2 s
	end)

	it("la couleur du serveur est appliquée si c'est une couleur, sinon la couleur par défaut", function()
		remotes.Explosion:fireClient({ cells = { { x = 1, y = 1 } }, color = Color3.fromRGB(10, 20, 30) })
		expect(flames()[1].Color).toEqual(Color3.fromRGB(10, 20, 30))
		world.advance(1)
		remotes.Explosion:fireClient({ cells = { { x = 1, y = 1 } }, color = "rouge" })
		expect(flames()[1].Color).toEqual(Color3.fromRGB(255, 150, 30))
	end)

	it("le pool est plafonné (160) : les flammes en trop sont détruites", function()
		local cells = {}
		for i = 1, 200 do
			table.insert(cells, { x = (i % 16) + 1, y = (i // 16) + 1 })
		end
		remotes.Explosion:fireClient({ cells = cells, duration = 0.2 })
		expect(#flames()).toBe(200)
		world.advance(0.3)
		expect(#flames()).toBe(0)
		remotes.Explosion:fireClient({ cells = cells, duration = 0.2 })
		expect(#flames()).toBe(200) -- 160 recyclées + 40 recréées
	end)

	it("stop : plus aucune flamme ; redémarrer ne double pas les flammes", function()
		Effects.stop()
		remotes.Explosion:fireClient({ cells = { { x = 1, y = 1 } } })
		expect(#flames()).toBe(0)
		Effects.start(info, remotes)
		Effects.start(info, remotes)
		remotes.Explosion:fireClient({ cells = { { x = 1, y = 1 } } })
		expect(#flames()).toBe(1)
	end)
end)

describe("InviteController", function()
	local Invite, toasts
	local function toast(text)
		table.insert(toasts, text)
	end
	beforeEach(function()
		toasts = {}
		Invite = world.module("InviteController")
	end)

	it("ouvre la fenêtre d'invitation officielle après vérification", function()
		Invite.request(toast)
		expect(toasts[1]).toBe("Ouverture des invitations...")
		expect(world.invitePrompts()).toBe(1)
	end)

	it("limite de 2 ouvertures par minute, puis de nouveau possible", function()
		Invite.request(toast)
		Invite.request(toast)
		Invite.request(toast)
		expect(world.invitePrompts()).toBe(2)
		expect(toasts[#toasts]).toContain("Limite de 2 invitations")
		world.advance(61)
		Invite.request(toast)
		expect(world.invitePrompts()).toBe(3)
	end)

	it("invitations indisponibles (Studio) : message clair, bouton libéré", function()
		world.game:GetService("SocialService").CanSendGameInviteAsync = function()
			return false
		end
		Invite.request(toast)
		expect(toasts[#toasts]).toContain("indisponibles")
		expect(world.invitePrompts()).toBe(0)
		Invite.request(toast) -- pas bloqué
		expect(toasts[#toasts]).toContain("indisponibles")
	end)

	it("vérification qui plante : même message, aucune erreur", function()
		world.game:GetService("SocialService").CanSendGameInviteAsync = function()
			error("réseau")
		end
		Invite.request(toast)
		expect(toasts[#toasts]).toContain("indisponibles")
	end)

	it("vérification lente : une 2e demande est refusée, puis le garde-fou libère le bouton", function()
		world.game:GetService("SocialService").CanSendGameInviteAsync = function()
			task.wait(30)
			return true
		end
		Invite.request(toast)
		Invite.request(toast)
		expect(toasts[#toasts]).toContain("Vérification des invitations en cours")
		world.advance(6.5)
		expect(toasts[#toasts]).toContain("ne répondent pas")
		world.game:GetService("SocialService").CanSendGameInviteAsync = function()
			return true
		end
		Invite.request(toast)
		expect(world.invitePrompts()).toBe(1)
		world.advance(40) -- la vieille vérification répond enfin : ignorée
		expect(world.invitePrompts()).toBe(1)
	end)

	it("l'ouverture de la fenêtre qui échoue est signalée", function()
		world.game:GetService("SocialService").PromptGameInvite = function()
			error("refusé")
		end
		Invite.request(toast)
		expect(toasts[#toasts]).toContain("Impossible d'ouvrir")
	end)
end)

describe("RoundController (relais réseau)", function()
	local Round, remotes, received
	beforeEach(function()
		received = {}
		local recorder = {}
		for _, name in { "onSnapshot", "onRoundEnded", "onStats", "onProfile", "onShopResult", "showToast" } do
			recorder[name] = function(payload)
				table.insert(received, { name = name, payload = payload })
			end
		end
		world.mock("UIController", recorder)
		remotes = Fixtures.fakeRemotes({ "RoundState", "RoundEnded", "StatsChanged", "ProfileUpdated", "ShopResult", "Notice" })
		Round = world.module("RoundController")
		Round.start(remotes)
	end)

	it("un instantané valide est relayé ; les autres formes sont ignorées", function()
		remotes.RoundState:fireClient({ state = "WAITING", players = {} })
		for _, bad in { "x", 5, {}, { state = 5, players = {} }, { state = "WAITING" } } do
			remotes.RoundState:fireClient(bad)
		end
		expect(#received).toBe(1)
		expect(received[1].name).toBe("onSnapshot")
	end)

	it("résultats : exigent result et names", function()
		remotes.RoundEnded:fireClient({ result = {}, names = {} })
		remotes.RoundEnded:fireClient({ result = {} })
		remotes.RoundEnded:fireClient("x")
		expect(#received).toBe(1)
		expect(received[1].name).toBe("onRoundEnded")
	end)

	it("profil : coins numérique et owned table exigés", function()
		remotes.ProfileUpdated:fireClient({ coins = 5, owned = {} })
		remotes.ProfileUpdated:fireClient({ coins = "5", owned = {} })
		remotes.ProfileUpdated:fireClient({ coins = 5 })
		remotes.ProfileUpdated:fireClient(nil)
		expect(#received).toBe(1)
	end)

	it("statistiques : table seulement", function()
		remotes.StatsChanged:fireClient({ bombCapacity = 2 })
		remotes.StatsChanged:fireClient("x")
		expect(#received).toBe(1)
		expect(received[1].name).toBe("onStats")
	end)

	it("messages du serveur : texte non vide de 120 caractères au plus", function()
		remotes.Notice:fireClient("Une manche est en cours")
		for _, bad in { "", string.rep("x", 121), 5, {}, true } do
			remotes.Notice:fireClient(bad)
		end
		remotes.Notice:fireClient(nil)
		expect(#received).toBe(1)
		expect(received[1].name).toBe("showToast")
		remotes.Notice:fireClient(string.rep("x", 120))
		expect(#received).toBe(2)
	end)

	it("stop coupe le relais ; redémarrer ne double pas les messages", function()
		Round.stop()
		remotes.RoundState:fireClient({ state = "WAITING", players = {} })
		expect(#received).toBe(0)
		Round.start(remotes)
		Round.start(remotes)
		remotes.RoundState:fireClient({ state = "WAITING", players = {} })
		expect(#received).toBe(1)
	end)
end)

describe("TouchControls (pur)", function()
	local Touch
	beforeEach(function()
		Touch = world.module("TouchControls")
	end)

	it("directionFromOffset : zone morte, axe dominant, signes", function()
		expect(Touch.directionFromOffset(Vector2.new(2, 2), 50)).toBeNil()
		expect(Touch.directionFromOffset(Vector2.new(0, 0), 50)).toBeNil()
		expect(Touch.directionFromOffset(Vector2.new(40, 5), 50)).toEqual(Vector2.new(1, 0))
		expect(Touch.directionFromOffset(Vector2.new(-40, 5), 50)).toEqual(Vector2.new(-1, 0))
		expect(Touch.directionFromOffset(Vector2.new(5, 40), 50)).toEqual(Vector2.new(0, 1))
		expect(Touch.directionFromOffset(Vector2.new(5, -40), 50)).toEqual(Vector2.new(0, -1))
	end)

	it("égalité parfaite : l'axe horizontal l'emporte (comportement stable)", function()
		expect(Touch.directionFromOffset(Vector2.new(30, 30), 50)).toEqual(Vector2.new(1, 0))
	end)

	it("détection d'appareil tactile selon UserInputService", function()
		expect(Touch.isTouchDevice()).toBe(false)
		UIS().TouchEnabled = true
		expect(Touch.isTouchDevice()).toBe(true)
	end)
end)

describe("MobileAssets (modèles allégés)", function()
	local Mobile, arena

	local function addLiteTemplate(name)
		local Instance = world.env.Instance
		local root = Instance.new("Folder")
		root.Name = "MapAssetsMobile"
		local mesh = Instance.new("MeshPart", root)
		mesh.Name = name
		world.attach("ReplicatedStorage", root)
	end

	local function serverPart(name, assetName)
		local part = world.env.Instance.new("MeshPart", arena)
		part.Name = name
		part:SetAttribute("BBAsset", assetName)
		return part
	end

	beforeEach(function()
		Mobile = world.module("MobileAssets")
		arena = world.env.Instance.new("Folder", world.env.workspace)
		arena.Name = "Arena"
	end)

	it("sur PC, rien n'est remplacé", function()
		addLiteTemplate("BB_WALL")
		local part = serverPart("Pillar_1_1", "BB_WALL")
		Mobile.start()
		expect(part:GetAttribute("BBLite")).toBeNil()
		expect(arena:FindFirstChild("Pillar_1_1_Lite")).toBeNil()
	end)

	it("forcé : la pièce du serveur est masquée localement et remplacée par sa version allégée", function()
		addLiteTemplate("BB_WALL")
		local part = serverPart("Pillar_1_1", "BB_WALL")
		Mobile.startForced()
		local lite = arena:FindFirstChild("Pillar_1_1_Lite")
		expect(lite).never.toBeNil()
		expect(lite.Anchored).toBe(true)
		expect(lite:GetAttribute("BBLite")).toBe(true)
		expect(part.LocalTransparencyModifier).toBe(1)
		expect(part.CanCollide).toBe(false)
		expect(part:GetAttribute("BBLite")).toBe(true)
	end)

	it("l'original reste côté serveur : sa destruction fait disparaître la version allégée", function()
		addLiteTemplate("BB_WALL")
		local part = serverPart("Crate_2_2", "BB_WALL")
		Mobile.startForced()
		local lite = arena:FindFirstChild("Crate_2_2_Lite")
		part:Destroy()
		expect(lite.destroyed).toBe(true)
	end)

	it("pièce sans modèle allégé correspondant, ou déjà allégée : pas de remplacement", function()
		addLiteTemplate("BB_WALL")
		Mobile.startForced()
		local unknown = serverPart("Crate_9_9", "BB_AUTRE")
		expect(Mobile.swap(unknown)).toBeNil()
		local first = serverPart("Pillar_3_3", "BB_WALL")
		expect(Mobile.swap(first)).never.toBeNil()
		expect(Mobile.swap(first)).toBeNil()
		local plain = world.env.Instance.new("MeshPart", arena)
		expect(Mobile.swap(plain)).toBeNil()
	end)

	it("dossier de modèles allégés absent : modèles PC conservés avec un avertissement", function()
		local part = serverPart("Pillar_1_1", "BB_WALL")
		Mobile.startForced()
		expect(part:GetAttribute("BBLite")).toBeNil()
		local warned = false
		for _, line in world.warnings do
			if line:find("MapAssetsMobile", 1, true) then
				warned = true
			end
		end
		expect(warned).toBe(true)
	end)

	it("une arène ajoutée plus tard est traitée aussi", function()
		addLiteTemplate("BB_WALL")
		Mobile.startForced()
		local later = world.env.Instance.new("Folder")
		later.Name = "Arena"
		later.Parent = world.env.workspace
		local part = world.env.Instance.new("MeshPart")
		part.Name = "Pillar_5_5"
		part:SetAttribute("BBAsset", "BB_WALL")
		part.Parent = later
		expect(later:FindFirstChild("Pillar_5_5_Lite")).never.toBeNil()
	end)

	it("détection automatique : écran tactile sans clavier => version allégée", function()
		addLiteTemplate("BB_WALL")
		UIS().TouchEnabled = true
		UIS().KeyboardEnabled = false
		serverPart("Pillar_1_1", "BB_WALL")
		Mobile.start()
		expect(arena:FindFirstChild("Pillar_1_1_Lite")).never.toBeNil()
	end)
end)

describe("Components", function()
	local Components
	beforeEach(function()
		Components = world.module("Components")
	end)

	it("screen : plein cadre, masqué par défaut, absorbe les clics seulement si demandé", function()
		local parent = world.env.Instance.new("Frame")
		local sink = Components.screen(parent, "A", true)
		local open = Components.screen(parent, "B", false)
		expect(sink.Visible).toBe(false)
		expect(sink.Active).toBe(true)
		expect(open.Active).toBe(false)
		expect(sink.Parent).toBe(parent)
	end)

	it("panel : taille donnée, coins arrondis et contour", function()
		local panel = Components.panel(world.env.Instance.new("Frame"), "P", UDim2.fromOffset(300, 200))
		expect(panel.Size).toEqual(UDim2.fromOffset(300, 200))
		expect(panel:FindFirstChildOfClass("UICorner")).never.toBeNil()
		expect(panel:FindFirstChildOfClass("UIStroke")).never.toBeNil()
	end)

	it("label : texte, taille et couleur par défaut blanche", function()
		local label = Components.label(world.env.Instance.new("Frame"), "L", "Bonjour", 20)
		expect(label.Text).toBe("Bonjour")
		expect(label.TextSize).toBe(20)
		expect(label.TextColor3).toEqual(Theme.white)
		local coloured = Components.label(world.env.Instance.new("Frame"), "L2", "x", 20, Theme.yellow)
		expect(coloured.TextColor3).toEqual(Theme.yellow)
	end)

	it("button : texte, couleur, taille, survol branché", function()
		local button = Components.button(world.env.Instance.new("Frame"), "B", "OK", Theme.green, UDim2.fromOffset(100, 40))
		expect(button.Text).toBe("OK")
		expect(button.BackgroundColor3).toEqual(Theme.green)
		expect(button.Size).toEqual(UDim2.fromOffset(100, 40))
		expect(button:FindFirstChild("HoverScale")).never.toBeNil()
	end)

	it("survol : agrandit puis revient ; la pression rétrécit ; le voile ne bloque pas le clic", function()
		local button = Components.button(world.env.Instance.new("Frame"), "B", "OK", Theme.green, UDim2.fromOffset(100, 40))
		local scale = button:FindFirstChild("HoverScale")
		local glow = button:FindFirstChild("HoverGlow")
		expect(glow.Active).toBe(false)
		button:FireEvent("MouseEnter")
		expect(scale.Scale).toBeCloseTo(1.05)
		button:FireEvent("MouseButton1Down")
		expect(scale.Scale).toBeCloseTo(0.95)
		button:FireEvent("MouseButton1Up")
		expect(scale.Scale).toBeCloseTo(1.05) -- toujours survolé
		button:FireEvent("MouseLeave")
		expect(scale.Scale).toBe(1)
		expect(glow.BackgroundTransparency).toBe(1)
	end)

	it("addHover sans voile (glow = false) : pas de calque ajouté", function()
		local button = world.env.Instance.new("TextButton")
		Components.addHover(button, { glow = false })
		expect(button:FindFirstChild("HoverGlow")).toBeNil()
		expect(button:FindFirstChild("HoverScale")).never.toBeNil()
	end)

	it("arcadeText : zone en fractions du parent contenant le texte superposé", function()
		local area = Components.arcadeText(world.env.Instance.new("Frame"), "T", "PLAY", { x = 0.27, y = 0.17, width = 0.44, height = 0.62 })
		expect(area).never.toBeNil()
		local texts = 0
		for _, descendant in area:GetDescendants() do
			if descendant:IsA("TextLabel") then
				texts += 1
				expect(descendant.Text).toBe("PLAY")
			end
		end
		expect(texts).toBeGreaterThanOrEqual(3)
	end)
end)
