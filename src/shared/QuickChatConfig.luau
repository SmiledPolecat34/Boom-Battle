--!strict
-- Chat rapide : phrases PRÉFAITES. Le joueur clique sur une bulle ; seul l'identifiant part au serveur, qui affiche la
-- phrase de ce catalogue au-dessus du personnage. Aucun texte libre n'est transmis : rien à filtrer, rien à détourner.

export type Phrase = {
	id: string,
	text: string,
}

local QuickChatConfig = {}

QuickChatConfig.BubbleSeconds = 3.5 -- durée d'affichage de la bulle
QuickChatConfig.MaxRecents = 5
QuickChatConfig.MaxFavorites = 8

QuickChatConfig.Phrases = table.freeze({
	table.freeze({ id = "gg", text = "GG !" }),
	table.freeze({ id = "nice", text = "Bien joué !" }),
	table.freeze({ id = "rematch", text = "Revanche !" }),
	table.freeze({ id = "bye", text = "À plus !" }),
	table.freeze({ id = "hello", text = "Salut !" }),
	table.freeze({ id = "please", text = "Oh, allez !" }),
	table.freeze({ id = "ohno", text = "Oh non !" }),
	table.freeze({ id = "careful", text = "Attention !" }),
	table.freeze({ id = "thanks", text = "Merci !" }),
	table.freeze({ id = "ready", text = "Prêt ?" }),
	table.freeze({ id = "oops", text = "Oups !" }),
	table.freeze({ id = "haha", text = "Haha !" }),
}) :: { Phrase }

-- Favoris proposés au départ (le joueur peut en ajouter ou en retirer).
QuickChatConfig.DefaultFavorites = table.freeze({ "gg", "rematch", "bye", "hello", "please" })

local byId: { [string]: Phrase } = {}
for _, phrase in QuickChatConfig.Phrases do
	byId[phrase.id] = phrase
end

function QuickChatConfig.get(id: any): Phrase?
	if typeof(id) ~= "string" then
		return nil
	end
	return byId[id]
end

return table.freeze(QuickChatConfig)
