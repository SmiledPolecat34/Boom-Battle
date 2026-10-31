--!strict
-- Invitation d'amis via la fenêtre officielle de Roblox (SocialService:PromptGameInvite).
-- Disponible seulement dans l'expérience publiée : dans Studio, CanSendGameInviteAsync répond non et on l'indique
-- au joueur au lieu d'échouer en silence.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local PartySlots = require(script.Parent.Parent.UI.PartySlots)

local InviteController = {}

local MAX_PROMPTS = 2
local WINDOW_SECONDS = 60

local limiter = PartySlots.newLimiter(MAX_PROMPTS, WINDOW_SECONDS)
local busy = false

-- toast : fonction d'affichage d'un message court (fournie par UIController).
function InviteController.request(toast: (text: string) -> ())
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local okCheck, canSend = pcall(function()
			return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
		end)
		if not okCheck or not canSend then
			toast("Invitations indisponibles ici (jeu publié requis)")
			busy = false
			return
		end

		local allowed, wait = PartySlots.tryAcquire(limiter, os.clock())
		if not allowed then
			toast(("Limite de %d invitations atteinte. Réessaie dans %d s."):format(MAX_PROMPTS, math.ceil(wait)))
			busy = false
			return
		end

		local okPrompt, err = pcall(function()
			SocialService:PromptGameInvite(Players.LocalPlayer)
		end)
		if not okPrompt then
			warn("[InviteController] PromptGameInvite a échoué : " .. tostring(err))
			toast("Impossible d'ouvrir les invitations")
		end
		busy = false
	end)
end

return InviteController
