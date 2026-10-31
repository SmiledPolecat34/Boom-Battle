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
}

return AssetIds
