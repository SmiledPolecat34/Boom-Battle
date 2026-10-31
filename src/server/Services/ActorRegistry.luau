--!strict
-- Registre des « acteurs » d'une manche : joueurs Roblox ET bots. Les services qui doivent considérer tout le monde
-- (dégâts d'explosion, ramassage des bonus) parcourent all() au lieu de Players:GetPlayers().
-- Module sans dépendance (évite les cycles) : seuls BotService et RoundService écrivent dans la liste des bots.

local Players = game:GetService("Players")

local ActorRegistry = {}

local bots: { any } = {}

function ActorRegistry.addBot(bot: any)
	table.insert(bots, bot)
end

function ActorRegistry.clearBots()
	table.clear(bots)
end

function ActorRegistry.getBots(): { any }
	return table.clone(bots)
end

function ActorRegistry.isBot(actor: any): boolean
	return typeof(actor) == "table" and actor.IsBot == true
end

-- Joueurs puis bots, dans une nouvelle table (le parcours reste valide même si la liste change pendant ce temps).
function ActorRegistry.all(): { any }
	local list: { any } = Players:GetPlayers()
	for _, bot in bots do
		table.insert(list, bot)
	end
	return list
end

return ActorRegistry
