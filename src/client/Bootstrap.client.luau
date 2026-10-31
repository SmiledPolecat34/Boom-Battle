--!strict
-- Point d'entrée client (Phase 1) : attend les informations d'arène, cadre la caméra et active le clic pour se déplacer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Parent.Controllers
local CameraController = require(Controllers.CameraController)
local EffectsController = require(Controllers.EffectsController)
local MovementController = require(Controllers.MovementController)
local RoundController = require(Controllers.RoundController)
local UIController = require(Controllers.UIController)

local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
local mapReady = remotes:WaitForChild("MapReady") :: RemoteEvent
local clientReady = remotes:WaitForChild("ClientReady") :: RemoteEvent

-- Les contrôles par défaut (clavier / joystick Roblox) sont inutiles : le déplacement se fait par clic ou toucher.
task.spawn(function()
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	local playerModule = playerScripts:WaitForChild("PlayerModule", 10)
	if not playerModule then
		return
	end
	local ok, err = pcall(function()
		local controls = require(playerModule):GetControls()
		controls:Disable()
	end)
	if not ok then
		warn("[BOM BATTLE] Impossible de désactiver les contrôles par défaut : " .. tostring(err))
	end
end)

-- Les écrans de manche d'abord, pour ne manquer aucun état envoyé en réponse à ClientReady.
UIController.start(remotes)
RoundController.start(remotes)

-- MapReady arrive à chaque nouvelle arène (lobby, manche) : caméra, clics et effets sont réinitialisés.
mapReady.OnClientEvent:Connect(function(info: CameraController.MapInfo)
	if typeof(info) ~= "table" or typeof(info.size) ~= "number" or typeof(info.cellSize) ~= "number" then
		warn("[BOM BATTLE] MapReady invalide")
		return
	end
	CameraController.apply(info)
	MovementController.start(info, remotes)
	EffectsController.start(info, remotes)
end)

clientReady:FireServer()
