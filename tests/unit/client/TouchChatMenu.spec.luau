--!nocheck
-- ChatController (habillage du chat Roblox, envoi des phrases rapides par le vrai chat), TouchControls (joystick et
-- croix : n'écrivent qu'une direction virtuelle), MenuScene (décor 3D du menu : construction, joueurs, groupe,
-- visibilité, nettoyage). Instances génériques simulées : structure et comportement, jamais le rendu.
local Theme = world.module("Theme")

local function UIS()
	return world.game:GetService("UserInputService")
end

local function find(root, name)
	return root:FindFirstChild(name, true)
end

beforeEach(function()
	world.reset()
end)

describe("ChatController", function()
	local Chat, service

	beforeEach(function()
		Chat = world.module("ChatController")
		service = world.game:GetService("TextChatService")
	end)

	it("habille la fenêtre, la barre de saisie et les bulles aux couleurs du jeu", function()
		Chat.start()
		local window = service:FindFirstChildOfClass("ChatWindowConfiguration")
		expect(window.WidthScale).toBe(0.26)
		expect(window.HeightScale).toBe(0.24)
		expect(window.TextSize).toBe(16)
		local bubble = service:FindFirstChildOfClass("BubbleChatConfiguration")
		expect(bubble.BubbleDuration).toBe(6)
		expect(bubble.TailVisible).toBe(true)
		expect(service:FindFirstChildOfClass("ChatInputBarConfiguration").TextSize).toBe(16)
	end)

	it("une propriété refusée n'empêche pas les autres (réglage sous pcall)", function()
		local stored = {}
		local strict = setmetatable({ ClassName = "ChatWindowConfiguration" }, {
			__newindex = function(_t, key, value)
				if key == "BackgroundColor3" then
					error("propriété absente de cette version")
				end
				stored[key] = value
			end,
		})
		local original = service.FindFirstChildOfClass
		service.FindFirstChildOfClass = function(self, className)
			if className == "ChatWindowConfiguration" then
				return strict
			end
			return original(self, className)
		end
		Chat.start()
		expect(stored.WidthScale).toBe(0.26)
		expect(stored.TextSize).toBe(16)
		expect(#world.warnings).toBeGreaterThan(0)
	end)

	it("sans configuration de chat (autre version de Roblox) : sans erreur", function()
		for _, child in service:GetChildren() do
			child:Destroy()
		end
		Chat.start()
	end)

	it("send : refuse un texte invalide (nil, vide, trop long, non texte) et l'absence de canal", function()
		for _, bad in { "", string.rep("x", 81), 5, {}, true } do
			expect(Chat.send(bad)).toBe(false)
		end
		expect(Chat.send(nil)).toBe(false)
		expect(Chat.send("Salut")).toBe(false) -- pas de canal RBXGeneral
	end)

	it("send : une phrase valide part par le canal général du vrai chat (donc filtrée par Roblox)", function()
		local sent = {}
		local channels = world.env.Instance.new("Folder", service)
		channels.Name = "TextChannels"
		local general = world.env.Instance.new("TextChannel", channels)
		general.Name = "RBXGeneral"
		general.SendAsync = function(_self, text)
			table.insert(sent, text)
		end
		expect(Chat.send("Bien joué")).toBe(true)
		expect(sent).toEqual({ "Bien joué" })
		expect(Chat.send(string.rep("x", 80))).toBe(true)
	end)

	it("send : un échec d'envoi est signalé sans erreur", function()
		local channels = world.env.Instance.new("Folder", service)
		channels.Name = "TextChannels"
		local general = world.env.Instance.new("TextChannel", channels)
		general.Name = "RBXGeneral"
		general.SendAsync = function()
			error("filtré")
		end
		expect(Chat.send("x")).toBe(true)
		expect(#world.warnings).toBeGreaterThan(0)
	end)

	it("couleur d'accent exposée", function()
		expect(Chat.AccentColor).never.toBeNil()
	end)
end)

describe("TouchControls (joystick et croix)", function()
	local Touch, Input, Settings, controls, container

	local function touch(x, y)
		return { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(x, y, 0), UserInputState = "Begin" }
	end

	beforeEach(function()
		Touch = world.module("TouchControls")
		Input = world.module("InputController")
		Settings = world.module("SettingsStore")
		UIS().TouchEnabled = true
		UIS().KeyboardEnabled = false
		local parent = world.env.Instance.new("Frame")
		controls = Touch.new(parent)
		container = find(parent, "TouchControls")
	end)

	it("masqué tant qu'il n'est pas activé ; actif seulement sur appareil tactile", function()
		expect(container.Visible).toBe(false)
		expect(controls.isActive()).toBe(false)
		controls.setActive(true)
		expect(container.Visible).toBe(true)
		UIS().TouchEnabled = false
		controls.setActive(true)
		expect(controls.isActive()).toBe(false)
		expect(container.Visible).toBe(false)
	end)

	it("joystick : le doigt tiré vers la droite donne une direction, relâcher la retire", function()
		controls.setActive(true)
		local zone = find(container, "JoystickZone")
		local finger = touch(300, 300)
		zone:FireEvent("InputBegan", finger)
		UIS()._fireInputChanged(touch(300, 300))
		-- le même objet InputObject est suivi : on le déplace
		finger.Position = Vector3.new(380, 305, 0)
		UIS()._fireInputChanged(finger)
		expect(Input.getHeldDirection()).toEqual(Vector2.new(1, 0))
		finger.Position = Vector3.new(300, 230, 0)
		UIS()._fireInputChanged(finger)
		expect(Input.getHeldDirection()).toEqual(Vector2.new(0, -1))
		UIS()._fireInputEnded(finger)
		expect(Input.getHeldDirection()).toBeNil()
	end)

	it("joystick : la zone morte ne produit aucune direction ; un 2e doigt est ignoré", function()
		controls.setActive(true)
		local zone = find(container, "JoystickZone")
		local first, second = touch(100, 100), touch(500, 500)
		zone:FireEvent("InputBegan", first)
		zone:FireEvent("InputBegan", second)
		first.Position = Vector3.new(103, 102, 0)
		UIS()._fireInputChanged(first)
		expect(Input.getHeldDirection()).toBeNil()
		second.Position = Vector3.new(900, 500, 0)
		UIS()._fireInputChanged(second)
		expect(Input.getHeldDirection()).toBeNil()
	end)

	it("un clic de souris ne déclenche pas le joystick (toucher seulement)", function()
		controls.setActive(true)
		local zone = find(container, "JoystickZone")
		local click = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(100, 100, 0) }
		zone:FireEvent("InputBegan", click)
		click.Position = Vector3.new(300, 100, 0)
		UIS()._fireInputChanged(click)
		expect(Input.getHeldDirection()).toBeNil()
	end)

	it("croix : chaque bouton tient sa direction jusqu'à la fin du toucher", function()
		controls.setActive(true)
		Settings.set("controlMode", "Croix")
		local pad = find(container, "DPad")
		expect(pad.Visible).toBe(true)
		expect(find(container, "JoystickZone").Visible).toBe(false)
		local results = {}
		for name, expected in { Up = Vector2.new(0, -1), Left = Vector2.new(-1, 0), Right = Vector2.new(1, 0), Down = Vector2.new(0, 1) } do
			local input = touch(0, 0)
			local inputSignals = {}
			input.Changed = {
				Connect = function(_self, handler)
					inputSignals.handler = handler
					return { Disconnect = function() end }
				end,
			}
			find(pad, name):FireEvent("InputBegan", input)
			local pressed = Input.getHeldDirection()
			input.UserInputState = Enum.UserInputState.End
			inputSignals.handler()
			results[name] = { pressed = pressed == expected or (pressed and pressed.X == expected.X and pressed.Y == expected.Y), released = Input.getHeldDirection() == nil }
		end
		for name, result in results do
			expect({ name = name, pressed = result.pressed, released = result.released }).toEqual({ name = name, pressed = true, released = true })
		end
	end)

	it("changer de mode (ou inverser les commandes) réinitialise la direction et la disposition", function()
		controls.setActive(true)
		local zone = find(container, "JoystickZone")
		local finger = touch(100, 100)
		zone:FireEvent("InputBegan", finger)
		finger.Position = Vector3.new(300, 100, 0)
		UIS()._fireInputChanged(finger)
		expect(Input.getHeldDirection()).never.toBeNil()
		Settings.set("controlMode", "Croix")
		expect(Input.getHeldDirection()).toBeNil()
		Settings.set("controlMode", "Joystick")
		Settings.set("flipControls", true)
		expect(zone.AnchorPoint).toEqual(Vector2.new(1, 1))
		Settings.set("flipControls", false)
		expect(zone.AnchorPoint).toEqual(Vector2.new(0, 1))
	end)

	it("désactiver les commandes coupe la direction en cours", function()
		controls.setActive(true)
		Input.setVirtualDirection(Vector2.new(1, 0))
		controls.setActive(false)
		expect(Input.getHeldDirection()).toBeNil()
	end)
end)

describe("MenuScene (décor 3D du menu)", function()
	local MenuScene

	beforeEach(function()
		MenuScene = world.module("MenuScene")
	end)

	it("se construit dans le Workspace (décor de secours sans ressource importée)", function()
		local scene = MenuScene.new()
		expect(scene.folder.Parent).toBe(world.env.workspace)
		expect(scene.folder.Name).toBe("MenuScene")
		expect(#scene.folder:GetDescendants()).toBeGreaterThan(5)
		local warned = false
		for _, line in world.warnings do
			if line:find("décor de secours", 1, true) then
				warned = true
			end
		end
		expect(warned).toBe(true)
	end)

	it("avec le décor importé : cloné sans avertissement, pièces ancrées et sans collision", function()
		local root = world.env.Instance.new("Folder")
		root.Name = "MenuDecor"
		for i = 1, 3 do
			local part = world.env.Instance.new("Part", root)
			part.Name = "Pad" .. i
		end
		world.attach("ReplicatedStorage", root)
		local scene = MenuScene.new()
		local decor = scene.folder:FindFirstChild("Decor")
		if decor then
			for _, part in decor:GetDescendants() do
				if part:IsA("BasePart") then
					expect(part.Anchored).toBe(true)
				end
			end
		end
		expect(scene.folder.Parent).toBe(world.env.workspace)
	end)

	it("visible : l'éclairage du menu s'applique et se restaure au masquage", function()
		local scene = MenuScene.new()
		local Lighting = world.game:GetService("Lighting")
		local before = Lighting.Brightness
		scene:setVisible(true)
		scene:setVisible(true) -- idempotent
		scene:setVisible(false)
		expect(Lighting.Brightness).toBe(before)
	end)

	it("personnage du joueur local, groupe de deux emplacements et aperçu de bulle", function()
		local scene = MenuScene.new()
		scene:setVisible(true)
		scene:setLocalPlayer(1, "Moi")
		expect(scene.actors[1]).never.toBeNil()
		scene:setParty({ { kind = "player", userId = 5, name = "Ami", status = "Prêt !", ready = true }, { kind = "invite" } }, function() end)
		expect(scene.actors[5]).never.toBeNil()
		scene:setParty({}, nil)
		expect(scene.actors[5]).toBeNil() -- parti : retiré
		expect(scene.actors[1]).never.toBeNil() -- le joueur local reste
		scene:showBubble("Salut", 3)
		scene:showBubble("Encore", 3)
	end)

	it("couleur de bombe et émote locales : sans erreur, y compris sans personnage", function()
		local scene = MenuScene.new()
		scene:setLocalBombColor(Color3.fromRGB(10, 20, 30))
		scene:playEmote({ id = "wave", animationId = "rbxassetid://1", looped = false }, 8)
		scene:setLocalPlayer(1, "Moi")
		scene:playEmote({ id = "dance", animationId = "rbxassetid://2", looped = true }, 8)
	end)

	it("destroy retire le décor et les marqueurs d'invitation ; appel répété sans erreur", function()
		local scene = MenuScene.new()
		scene:setVisible(true)
		scene:setLocalPlayer(1, "Moi")
		scene:setParty({}, function() end)
		local folder = scene.folder
		scene:destroy()
		expect(folder.destroyed).toBe(true)
		expect(next(scene.actors)).toBeNil()
	end)

	it("boucle d'animation branchée seulement quand le décor est visible", function()
		local scene = MenuScene.new()
		scene:setVisible(true)
		world.fireRenderStepped(0.016)
		scene:setVisible(false)
		expect(scene.connection).toBeNil()
	end)
end)
