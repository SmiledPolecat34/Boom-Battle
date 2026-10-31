--!strict
-- Un bot : un « acteur » qui a l'interface minimale d'un Player pour les services de jeu (UserId, Name, DisplayName,
-- Character, GetAttribute / SetAttribute). Ce n'est PAS un Player Roblox : aucune donnée sauvegardée, aucun client,
-- aucune récompense. IsBot permet de le reconnaître (ActorRegistry.isBot).

local BOT_ID_BASE = -1000000 -- identifiants négatifs très éloignés de ceux des joueurs de test de Studio (-1, -2...)

local BotActor = {}
BotActor.__index = BotActor

export type BotActor = typeof(setmetatable(
	{} :: {
		UserId: number,
		Name: string,
		DisplayName: string,
		Character: Model?,
		IsBot: boolean,
		attributes: { [string]: any },
	},
	BotActor
))

function BotActor.new(index: number): BotActor
	return setmetatable({
		UserId = BOT_ID_BASE - index,
		Name = "Bot" .. index,
		DisplayName = "Bot " .. index,
		Character = nil,
		IsBot = true,
		attributes = {},
	}, BotActor)
end

function BotActor.GetAttribute(self: BotActor, name: string): any
	return self.attributes[name]
end

function BotActor.SetAttribute(self: BotActor, name: string, value: any)
	self.attributes[name] = value
end

return BotActor
