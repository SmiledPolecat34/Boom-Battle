--!strict
-- Chat personnalisé : habille le chat Roblox (TextChatService) aux couleurs du jeu et envoie des phrases rapides par
-- le VRAI chat (donc filtrées par Roblox). Aucun chat maison : on ne contourne jamais le filtrage.
-- Chaque réglage est appliqué sous pcall : une propriété absente d'une version de Roblox n'empêche pas les autres.

local TextChatService = game:GetService("TextChatService")

local ChatController = {}

local NAVY = Color3.fromRGB(21, 27, 49)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(170, 178, 205)
local VIOLET = Color3.fromRGB(107, 66, 237)

local function set(instance: Instance?, property: string, value: any)
	if not instance then
		return
	end
	local ok, err = pcall(function()
		(instance :: any)[property] = value
	end)
	if not ok then
		warn(("[ChatController] %s.%s non appliqué : %s"):format(instance.ClassName, property, tostring(err)))
	end
end

function ChatController.start()
	-- Fenêtre : petite, translucide, en haut à gauche (le bas de l'écran reste libre pour le HUD de jeu).
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	set(window, "BackgroundColor3", NAVY)
	set(window, "BackgroundTransparency", 0.3)
	set(window, "TextColor3", WHITE)
	set(window, "TextStrokeTransparency", 0.6)
	set(window, "FontFace", Font.fromEnum(Enum.Font.GothamMedium))
	set(window, "TextSize", 16)
	set(window, "WidthScale", 0.26)
	set(window, "HeightScale", 0.24)

	-- Barre de saisie.
	local input = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	set(input, "BackgroundColor3", NAVY)
	set(input, "BackgroundTransparency", 0.2)
	set(input, "TextColor3", WHITE)
	set(input, "PlaceholderColor3", MUTED)
	set(input, "FontFace", Font.fromEnum(Enum.Font.GothamMedium))
	set(input, "TextSize", 16)

	-- Bulles au-dessus des personnages : lisibles depuis la caméra de dessus.
	local bubble = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
	set(bubble, "BackgroundColor3", NAVY)
	set(bubble, "TextColor3", WHITE)
	set(bubble, "FontFace", Font.fromEnum(Enum.Font.GothamBold))
	set(bubble, "TextSize", 20)
	set(bubble, "BubbleDuration", 6)
	set(bubble, "BackgroundTransparency", 0.1)
	set(bubble, "TailVisible", true)
end

-- Phrase rapide : envoyée par le canal général du vrai chat. Retourne true si l'envoi a été demandé.
function ChatController.send(text: string): boolean
	if typeof(text) ~= "string" or #text == 0 or #text > 80 then
		return false
	end
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = if channels then channels:FindFirstChild("RBXGeneral") else nil
	if not general or not general:IsA("TextChannel") then
		return false
	end
	task.spawn(function()
		local ok, err = pcall(function()
			general:SendAsync(text)
		end)
		if not ok then
			warn("[ChatController] Envoi impossible : " .. tostring(err))
		end
	end)
	return true
end

ChatController.AccentColor = VIOLET

return ChatController
