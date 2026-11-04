--!nocheck
-- Instances génériques simulées (Part, Folder, Humanoid, Animator, BillboardGui...) pour tester les services qui
-- construisent des objets du moteur. Ce n'est PAS le moteur : seules l'arborescence (Parent / enfants), les propriétés,
-- les attributs, quelques événements et les méthodes courantes sont simulés. Aucune physique, aucun rendu.
--
-- Fidélité volontairement limitée : une classe ou une méthode absente ne lève pas d'erreur de classe inconnue, mais les
-- tests doivent vérifier le résultat observable (enfants créés, propriétés posées, Parent) et jamais « ça ne plante
-- pas » seul.

local roblox = require("@lune/roblox")

local Instances = {}

local BASEPARTS = { Part = true, MeshPart = true, WedgePart = true, SpawnLocation = true }
local GUI_OBJECTS = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true }

local function guiDefaults(extra)
	return function()
		local props = { Visible = true, Active = false, ZIndex = 1, BackgroundTransparency = 0, AbsoluteSize = roblox.Vector2.new(0, 0), AbsolutePosition = roblox.Vector2.new(0, 0) }
		for key, value in extra or {} do
			props[key] = value
		end
		return props
	end
end

local DEFAULTS = {
	Frame = guiDefaults(),
	TextLabel = guiDefaults({ Text = "", TextSize = 14 }),
	TextButton = guiDefaults({ Text = "", TextSize = 14, AutoButtonColor = true }),
	ImageLabel = guiDefaults({ Image = "" }),
	ImageButton = guiDefaults({ Image = "" }),
	ScrollingFrame = guiDefaults({ CanvasSize = roblox.UDim2.new(0, 0, 0, 0) }),
	ScreenGui = function()
		return { Enabled = true }
	end,
	Camera = function()
		return { ViewportSize = roblox.Vector2.new(1280, 720), FieldOfView = 70, CFrame = roblox.CFrame.new(0, 0, 0) }
	end,
	Part = function()
		return { Size = roblox.Vector3.new(4, 1, 2), Anchored = false, CanCollide = true, Transparency = 0 }
	end,
	MeshPart = function()
		return {
			Size = roblox.Vector3.new(4, 1, 2),
			Anchored = false,
			CanCollide = true,
			CanQuery = true,
			CanTouch = true,
			CastShadow = true,
			Transparency = 0,
			PivotOffset = roblox.CFrame.new(0, 0, 0),
		}
	end,
	Humanoid = function()
		return { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50 }
	end,
	Animation = function()
		return { AnimationId = "" }
	end,
}

--- Crée une instance de la classe `className`. `deps.newSignal` : fabrique de signaux du chargeur.
function Instances.new(className: string, parent: any?, deps: any)
	local state = {
		className = className,
		parent = nil,
		children = {},
		attributes = {},
		props = { Name = className },
		signals = {},
		destroyed = false,
	}
	for key, value in (if DEFAULTS[className] then DEFAULTS[className]() else {}) do
		state.props[key] = value
	end
	if BASEPARTS[className] then
		state.props.CFrame = roblox.CFrame.new(0, 0, 0)
	end

	local self = {}
	rawset(self, "_isInstance", true)
	rawset(self, "_state", state)

	local function signalOf(name: string)
		local entry = state.signals[name]
		if not entry then
			local signal, fire = deps.newSignal()
			entry = { signal = signal, fire = fire }
			state.signals[name] = entry
		end
		return entry
	end

	local function removeFromParent()
		local old = state.parent
		if old then
			local siblings = rawget(old, "_state").children
			local index = table.find(siblings, self)
			if index then
				table.remove(siblings, index)
			end
			state.parent = nil
			signalOf("AncestryChanged").fire(self, nil)
			rawget(old, "_state").signals.ChildRemoved = rawget(old, "_state").signals.ChildRemoved
			local removed = rawget(old, "_state").signals.ChildRemoved
			if removed then
				removed.fire(self)
			end
		end
	end

	local function setParent(newParent: any)
		if state.parent == newParent then
			return
		end
		removeFromParent()
		if newParent ~= nil then
			local parentState = rawget(newParent, "_state")
			table.insert(parentState.children, self)
			state.parent = newParent
			signalOf("AncestryChanged").fire(self, newParent)
			local added = parentState.signals.ChildAdded
			if added then
				added.fire(self)
			end
			-- DescendantAdded : propagé à tous les ancêtres.
			local ancestor = newParent
			while ancestor do
				local ancestorState = rawget(ancestor, "_state")
				local descendantAdded = ancestorState.signals.DescendantAdded
				if descendantAdded then
					descendantAdded.fire(self)
				end
				ancestor = ancestorState.parent
			end
		end
	end

	local methods = {}

	function methods.IsA(_self, name: string)
		if name == className or name == "Instance" then
			return true
		end
		if name == "BasePart" then
			return BASEPARTS[className] == true
		end
		if name == "PVInstance" then
			return BASEPARTS[className] == true or className == "Model"
		end
		if name == "GuiObject" then
			return GUI_OBJECTS[className] == true
		end
		return false
	end

	function methods.FindFirstChild(_self, name: string, recursive: boolean?)
		for _, child in state.children do
			if rawget(child, "_state").props.Name == name then
				return child
			end
		end
		if recursive then
			for _, child in state.children do
				local found = child:FindFirstChild(name, true)
				if found then
					return found
				end
			end
		end
		return nil
	end

	function methods.WaitForChild(_self, name: string)
		return methods.FindFirstChild(self, name)
	end

	function methods.FindFirstChildOfClass(_self, name: string)
		for _, child in state.children do
			if rawget(child, "_state").className == name then
				return child
			end
		end
		return nil
	end

	function methods.FindFirstChildWhichIsA(_self, name: string)
		for _, child in state.children do
			if child:IsA(name) then
				return child
			end
		end
		return nil
	end

	function methods.GetChildren(_self)
		return table.clone(state.children)
	end

	function methods.GetDescendants(_self)
		local list = {}
		local function walk(node)
			for _, child in rawget(node, "_state").children do
				table.insert(list, child)
				walk(child)
			end
		end
		walk(self)
		return list
	end

	function methods.IsDescendantOf(_self, ancestor)
		local node = state.parent
		while node do
			if node == ancestor then
				return true
			end
			node = rawget(node, "_state").parent
		end
		return false
	end

	function methods.ClearAllChildren(_self)
		for _, child in table.clone(state.children) do
			child:Destroy()
		end
	end

	function methods.Destroy(_self)
		if state.destroyed then
			return
		end
		state.destroyed = true
		for _, child in table.clone(state.children) do
			child:Destroy()
		end
		removeFromParent()
		local destroying = state.signals.Destroying
		if destroying then
			destroying.fire()
		end
	end

	function methods.SetAttribute(_self, name: string, value: any)
		state.attributes[name] = value
	end

	function methods.GetAttribute(_self, name: string)
		return state.attributes[name]
	end

	function methods.GetAttributes(_self)
		return table.clone(state.attributes)
	end

	function methods.PivotTo(_self, cframe)
		state.props.Pivot = cframe
		if BASEPARTS[className] then
			state.props.CFrame = cframe
		end
	end

	function methods.GetPivot(_self)
		return state.props.Pivot or state.props.CFrame or roblox.CFrame.new(0, 0, 0)
	end

	function methods.Clone(_self)
		local copy = Instances.new(className, nil, deps)
		local copyState = rawget(copy, "_state")
		for key, value in state.props do
			copyState.props[key] = value
		end
		for key, value in state.attributes do
			copyState.attributes[key] = value
		end
		for _, child in state.children do
			child:Clone().Parent = copy
		end
		return copy
	end

	function methods.GetPropertyChangedSignal(_self, name: string)
		return signalOf("prop:" .. name).signal
	end

	-- Test uniquement : déclenche l'événement `name` (ex. Running, Touched) avec les arguments donnés.
	function methods.FireEvent(_self, name: string, ...)
		signalOf(name).fire(...)
	end

	-- Humanoid
	function methods.MoveTo(_self, target)
		state.props.MoveTarget = target
	end

	-- Animator / Humanoid : chargement d'animation simulé (pistes mémorisées pour les tests).
	function methods.LoadAnimation(_self, animation)
		local track = { AnimationId = animation.AnimationId, IsPlaying = false, Looped = false, plays = 0, stops = 0 }
		function track:Play()
			self.IsPlaying = true
			self.plays += 1
		end
		function track:Stop()
			self.IsPlaying = false
			self.stops += 1
		end
		state.tracks = state.tracks or {}
		table.insert(state.tracks, track)
		return track
	end

	local EVENTS = {
		Running = true, Died = true, Touched = true, ChildAdded = true, ChildRemoved = true, Destroying = true,
		AncestryChanged = true, Changed = true, DescendantAdded = true, CharacterAdded = true,
		Activated = true, MouseEnter = true, MouseLeave = true, MouseButton1Click = true, MouseButton1Down = true,
		MouseButton1Up = true, InputBegan = true, InputEnded = true, InputChanged = true, FocusLost = true,
		Focused = true, TextChanged = true, MouseMoved = true, ChildAddedToParent = true,
	}

	setmetatable(self, {
		__index = function(_t, key)
			if key == "Parent" then
				return state.parent
			elseif key == "ClassName" then
				return className
			elseif key == "Position" and BASEPARTS[className] then
				return state.props.CFrame.Position
			elseif key == "tracks" then
				return state.tracks or {}
			elseif key == "destroyed" then
				return state.destroyed
			end
			-- Une propriété posée par un test (ex. remplacer LoadAnimation par une panne) prime sur la méthode simulée.
			local prop = state.props[key]
			if prop ~= nil then
				return prop
			end
			local method = methods[key]
			if method ~= nil then
				return method
			end
			if EVENTS[key] then
				return signalOf(key).signal
			end
			return methods.FindFirstChild(self, key)
		end,
		__newindex = function(_t, key, value)
			if key == "Parent" then
				setParent(value)
			elseif key == "Position" and BASEPARTS[className] then
				state.props.CFrame = roblox.CFrame.new(value)
			elseif key == "CFrame" and BASEPARTS[className] then
				state.props.CFrame = value
			else
				state.props[key] = value
				local watcher = state.signals["prop:" .. tostring(key)]
				if watcher then
					watcher.fire()
				end
			end
		end,
	})

	if parent ~= nil then
		setParent(parent)
	end
	return self
end

return Instances
