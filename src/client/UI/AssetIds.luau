--!strict
-- Identifiants des images de l'interface, renvoyés par l'import Roblox (voir docs/ASSETS.md et assets/manifest.json).
-- nil = image pas encore importée : l'interface utilise son rendu de secours (texte et formes). Ne JAMAIS inventer
-- un identifiant : seul celui renvoyé par l'import Roblox est valable.

local AssetIds = {
	-- Logo « BOMB BATTLE » (1416 x 786).
	Logo = "rbxassetid://115523406234858" :: string?,
	LogoAspectRatio = 1416 / 786,
	-- Icônes carrées (887 x 858 et 920 x 913, environ 1:1).
	HelpIcon = "rbxassetid://78179054044113" :: string?,
	SettingsIcon = "rbxassetid://109788821205687" :: string?,
	-- Icône de quêtes (presse-papiers), 1092 x 1164.
	QuestsIcon = "rbxassetid://121477183604134" :: string?,
	-- Bouton PLAY vide (triangle à gauche, rectangle vert central, bombe à droite), 1655 x 544.
	-- Le texte « PLAY » est dessiné par le code dans la zone centrale ; PlayTextArea donne cette zone en fractions
	-- de l'image (mesurée sur les pixels : rectangle vert de 26 % à 71 % de la largeur, centré à 48 % en hauteur).
	PlayButton = "rbxassetid://78978566535693" :: string?,
	PlayButtonAspectRatio = 1655 / 544,
	PlayTextArea = { x = 0.27, y = 0.17, width = 0.44, height = 0.62 },
}

return AssetIds
