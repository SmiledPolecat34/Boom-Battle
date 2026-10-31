--!strict
-- Entrées brutes : clic gauche (PC) ou toucher (mobile / tablette). Ne prend aucune décision de jeu.
-- Les clics captés par l'interface (gameProcessed) sont ignorés.

local UserInputService = game:GetService("UserInputService")

local InputController = {}

local connection: RBXScriptConnection? = nil

-- callback reçoit la position écran (espace de InputObject.Position).
function InputController.onPrimaryAction(callback: (position: Vector2) -> ())
	InputController.stop()
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

function InputController.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return InputController
