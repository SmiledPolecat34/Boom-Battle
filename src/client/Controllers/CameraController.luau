--!strict
-- Caméra fixe vue de dessus, cadrée pour voir toute l'arène (anneau de murs inclus) quel que soit le ratio d'écran.

local CameraController = {}

export type MapInfo = {
	sizeId: string,
	size: number,
	cellSize: number,
	origin: Vector3,
	seed: number,
}

local FRAMING_MARGIN = 1.08
local connections: { RBXScriptConnection } = {}
local currentInfo: MapInfo? = nil

local function frame()
	local info = currentInfo
	local camera = workspace.CurrentCamera
	if not info or not camera then
		return
	end

	local arenaWidth = (info.size + 2) * info.cellSize
	local viewport = camera.ViewportSize
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local tanHalfFov = math.tan(math.rad(camera.FieldOfView) / 2)
	-- FieldOfView est vertical : la contrainte horizontale se déduit du ratio d'écran.
	local heightForVertical = (arenaWidth / 2) / tanHalfFov
	local heightForHorizontal = (arenaWidth / 2) / (tanHalfFov * aspect)
	local height = math.max(heightForVertical, heightForHorizontal) * FRAMING_MARGIN

	local center = info.origin + Vector3.new(info.size * info.cellSize / 2, 0, info.size * info.cellSize / 2)
	camera.CameraType = Enum.CameraType.Scriptable
	-- Vecteur « haut » = -Z : l'axe X de la grille va vers la droite, l'axe Y (Z monde) vers le bas de l'écran.
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, height, 0), center, Vector3.new(0, 0, -1))
end

function CameraController.getCamera(): Camera?
	return workspace.CurrentCamera
end

function CameraController.apply(info: MapInfo)
	currentInfo = info
	CameraController.stop()

	local camera = workspace.CurrentCamera
	if camera then
		table.insert(connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(frame))
		-- Roblox peut réinitialiser le type de caméra à l'apparition du personnage : on le force à rester fixe.
		table.insert(
			connections,
			camera:GetPropertyChangedSignal("CameraType"):Connect(function()
				if camera.CameraType ~= Enum.CameraType.Scriptable then
					frame()
				end
			end)
		)
	end
	frame()
end

function CameraController.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return CameraController
