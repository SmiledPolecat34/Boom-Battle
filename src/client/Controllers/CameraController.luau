--!strict
-- Caméra fixe vue de dessus, cadrée pour voir toute l'arène (anneau de murs inclus) quel que soit le ratio d'écran.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraController = {}

export type MapInfo = {
	sizeId: string,
	size: number,
	cellSize: number,
	origin: Vector3,
	seed: number,
}

local FRAMING_MARGIN = 1.04
local CAMERA_PITCH_DEG = 55 -- angle au-dessus de l'horizon (90 = vue de dessus pure)
local WALL_TOP = 4 -- hauteur approximative du sommet des murs, pour le cadrage
local connections: { RBXScriptConnection } = {}
-- Orientation de l'arène : lacet (multiple de 90°) de la caméra autour du centre. 0 = joueur côté +Z (bas de l'écran).
local currentYaw = 0
local targetYaw = 0
local yawInitialised = false
local yawConnection: RBXScriptConnection? = nil
local YAW_SPEED = 3 -- radians par seconde
local currentInfo: MapInfo? = nil

-- Caméra fixe alternative (décor du menu principal) : prioritaire sur le cadrage de l'arène tant qu'elle est active.
local override: CFrame? = nil
local overrideFov = 50
local DEFAULT_FOV = 50
local overrideConnection: RBXScriptConnection? = nil

local function frame()
	local info = currentInfo
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if override then
		camera.CameraType = Enum.CameraType.Scriptable
		-- L'interface est mise à l'échelle sur 1280 x 720 et centrée : on adapte le champ de vision pour que le décor 3D
		-- (personnage, pseudo) reste calé sur ce cadre, que l'écran soit large, carré ou en hauteur.
		local viewport = camera.ViewportSize
		local fit = math.min(viewport.X / 1280, viewport.Y / 720)
		local ratio = viewport.Y / math.max(720 * fit, 1)
		local tanHalf = math.tan(math.rad(overrideFov) / 2) * ratio
		camera.FieldOfView = math.clamp(math.deg(2 * math.atan(tanHalf)), 20, 110)
		camera.CFrame = override
		return
	end
	camera.FieldOfView = DEFAULT_FOV
	if not info then
		return
	end

	local half = (info.size + 2) * info.cellSize / 2
	local viewport = camera.ViewportSize
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local tanV = math.tan(math.rad(camera.FieldOfView) / 2) / FRAMING_MARGIN
	local tanH = tanV * aspect

	local center = info.origin + Vector3.new(info.size * info.cellSize / 2, 0, info.size * info.cellSize / 2)
	-- Caméra inclinée (style « 3/4 ») placée derrière le joueur (côté de son spawn), tournée par pas de 90° :
	-- le joueur est toujours en bas de l'écran. Le serveur et la grille ne changent pas (affichage seul).
	local pitch = math.rad(CAMERA_PITCH_DEG)
	local flat = math.cos(pitch)
	local toCamera = Vector3.new(math.sin(currentYaw) * flat, math.sin(pitch), math.cos(currentYaw) * flat)
	local look = -toCamera
	local right = look:Cross(Vector3.yAxis).Unit
	local up = right:Cross(look).Unit

	-- Distance minimale pour que tous les coins de l'arène (sol et sommet des murs) restent à l'écran.
	local distance = 0
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			for _, py in { 0, WALL_TOP } do
				local offset = Vector3.new(sx * half, py, sz * half)
				local depth = offset:Dot(look)
				distance = math.max(distance, math.abs(offset:Dot(right)) / tanH - depth)
				distance = math.max(distance, math.abs(offset:Dot(up)) / tanV - depth)
			end
		end
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(center + toCamera * distance, center, Vector3.yAxis)
end

local function stepYaw(dt: number)
	local diff = (targetYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi
	local step = YAW_SPEED * dt
	if math.abs(diff) <= step then
		currentYaw = targetYaw
		if yawConnection then
			yawConnection:Disconnect()
			yawConnection = nil
		end
	else
		currentYaw += math.sign(diff) * step
	end
	frame()
end

-- Oriente la caméra vers le côté du joueur (le plus proche, par pas de 90°). Anime la rotation.
local function setTargetYaw(yaw: number)
	targetYaw = yaw
	if not yawInitialised then
		yawInitialised = true
		currentYaw = yaw
		frame()
		return
	end
	if currentYaw ~= targetYaw and not yawConnection then
		yawConnection = RunService.RenderStepped:Connect(stepYaw)
	end
end

local function orientToCharacter()
	local info = currentInfo
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not info or not root or not root:IsA("BasePart") then
		return
	end
	local center = info.origin + Vector3.new(info.size * info.cellSize / 2, 0, info.size * info.cellSize / 2)
	local offset = root.Position - center
	if offset.X * offset.X + offset.Z * offset.Z < 1 then
		return
	end
	-- Petit biais : les spawns de coin sont à 45°, on tranche toujours dans le même sens (cohérent par symétrie).
	local angle = math.atan2(offset.X, offset.Z) + 0.05
	setTargetYaw(math.round(angle / (math.pi / 2)) * (math.pi / 2))
end

-- Convertit une direction d'écran (x vers la droite, y vers le bas) en direction de grille selon l'orientation.
function CameraController.screenToGrid(direction: Vector2): Vector2
	local c, s = math.cos(targetYaw), math.sin(targetYaw)
	return Vector2.new(math.round(direction.X * c + direction.Y * s), math.round(-direction.X * s + direction.Y * c))
end

-- Active (cframe, fov) ou désactive (nil) la caméra du décor de menu. Le cadrage de l'arène revient tout seul.
function CameraController.setOverride(cframe: CFrame?, fov: number?)
	override = cframe
	overrideFov = fov or 50
	frame()
	if cframe and not overrideConnection then
		local camera = workspace.CurrentCamera
		if camera then
			overrideConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				if override then
					frame()
				end
			end)
		end
	elseif not cframe and overrideConnection then
		overrideConnection:Disconnect()
		overrideConnection = nil
	end
end

-- Vrai tant que la caméra du décor de menu est active (les clics ne doivent alors rien déplacer).
function CameraController.isOverridden(): boolean
	return override ~= nil
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

	-- Le serveur place le personnage après sa création : on lit sa position un peu plus tard (puis on confirme).
	local function scheduleOrient()
		for _, delay in { 0.3, 1 } do
			task.delay(delay, orientToCharacter)
		end
	end
	table.insert(connections, Players.LocalPlayer.CharacterAdded:Connect(scheduleOrient))
	if Players.LocalPlayer.Character then
		scheduleOrient()
	end
end

function CameraController.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return CameraController
