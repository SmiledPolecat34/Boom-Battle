--!strict
-- Entrées brutes : clic gauche (PC) ou toucher (mobile / tablette). Ne prend aucune décision de jeu.
-- Les clics captés par l'interface (gameProcessed) sont ignorés.

local UserInputService = game:GetService("UserInputService")

local InputController = {}

local connection: RBXScriptConnection? = nil
local keyConnection: RBXScriptConnection? = nil

-- callback reçoit la position écran (espace de InputObject.Position).
function InputController.onPrimaryAction(callback: (position: Vector2) -> ())
	if connection then
		connection:Disconnect()
	end
	connection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			callback(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
end

-- Raccourci clavier facultatif (barre d'espace) : jamais indispensable, le bouton à l'écran fait la même chose.
function InputController.onBombKey(callback: () -> ())
	if keyConnection then
		keyConnection:Disconnect()
	end
	keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		-- Le saut par défaut de Roblox « consomme » Espace (gameProcessed vrai) : on ne l'ignore que pendant une saisie de texte.
		if input.KeyCode == Enum.KeyCode.Space and not UserInputService:GetFocusedTextBox() then
			callback()
		end
	end)
end

local DIRECTION_KEYS: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
	[Enum.KeyCode.Up] = Vector2.new(0, -1),
	[Enum.KeyCode.Down] = Vector2.new(0, 1),
	[Enum.KeyCode.A] = Vector2.new(-1, 0),
	[Enum.KeyCode.D] = Vector2.new(1, 0),
	[Enum.KeyCode.W] = Vector2.new(0, -1),
	[Enum.KeyCode.S] = Vector2.new(0, 1),
}

-- Direction tenue au clavier (flèches ou WASD) : vecteur de grille (x vers la droite, y vers le bas de l'écran),
-- ou nil si aucune touche n'est enfoncée ou si une saisie de texte est en cours.
function InputController.getHeldDirection(): Vector2?
	if UserInputService:GetFocusedTextBox() then
		return nil
	end
	for keyCode, direction in DIRECTION_KEYS do
		if UserInputService:IsKeyDown(keyCode) then
			return direction
		end
	end
	return nil
end

function InputController.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	-- Le raccourci Espace appartient au HUD (qui le remplace lui-même) : l'arrêt du déplacement ne doit pas le couper.
end

return InputController
