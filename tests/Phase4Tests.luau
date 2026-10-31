--!nocheck
-- Tests de la Phase 4 : choix de l'écran (UIController.selectScreen) et réglages (SettingsStore).
-- À EXÉCUTER DANS ROBLOX STUDIO : coller dans la barre de commande (mode Edit) après synchronisation Rojo.
-- Ces tests ne créent aucune interface : ils vérifient la logique pure.

local Controllers = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers
local SettingsStore = require(Controllers.SettingsStore)

local passed, failed = 0, 0
local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		warn(("ÉCHEC : %s %s"):format(name, detail or ""))
	end
end

-- Réglages -----------------------------------------------------------------------------------------------
check("réglage : valeur par défaut du bouton bombe", SettingsStore.get("bombButtonSize") == "Moyen")
check("réglage : valeur valide acceptée", SettingsStore.set("bombButtonSize", "Grand") and SettingsStore.bombButtonPixels() == 150)
check("réglage : valeur inconnue refusée", not SettingsStore.set("bombButtonSize", "Gigantesque") and SettingsStore.get("bombButtonSize") == "Grand")
check("réglage : clé inconnue refusée", not SettingsStore.set("n_importe_quoi" :: any, "x"))
check("réglage : type invalide refusé", not SettingsStore.set("showMoveMarker", "oui"))
check("réglage : échelle d'interface", SettingsStore.set("uiScale", "Petit") and math.abs(SettingsStore.uiScaleMultiplier() - 0.85) < 1e-6)
SettingsStore.set("bombButtonSize", "Moyen")
SettingsStore.set("uiScale", "Normal")

-- Choix de l'écran ---------------------------------------------------------------------------------------
-- selectScreen est une fonction pure exposée par UIController ; on charge le module sans le démarrer.
local ok, UIController = pcall(require, Controllers.UIController)
check("UIController se charge", ok, tostring(UIController))
if ok then
	local select = UIController.selectScreen
	local function snap(state) return { state = state, players = {} } end
	local menuPlayer = { queued = false, participant = false, alive = false, ready = false }
	local queuedPlayer = { queued = true, participant = false, alive = false, ready = false }
	local playing = { queued = true, participant = true, alive = true, ready = true }
	local dead = { queued = true, participant = true, alive = false, ready = true }

	check("écran : au menu en attente => MainMenu", select(snap("WAITING"), menuPlayer) == "MainMenu")
	check("écran : PLAY cliqué => Lobby", select(snap("READY"), queuedPlayer) == "Lobby")
	check("écran : retour au lobby (RESETTING) => Lobby", select(snap("RESETTING"), queuedPlayer) == "Lobby")
	check("écran : compte à rebours participant => GameHUD", select(snap("COUNTDOWN"), playing) == "GameHUD")
	check("écran : manche participant vivant => GameHUD", select(snap("PLAYING"), playing) == "GameHUD")
	check("écran : éliminé => GameHUD (spectateur)", select(snap("PLAYING"), dead) == "GameHUD")
	check("écran : inscrit non participant en manche => GameHUD (spectateur)", select(snap("PLAYING"), queuedPlayer) == "GameHUD")
	check("écran : au menu pendant une manche => MainMenu", select(snap("PLAYING"), menuPlayer) == "MainMenu")
	check("écran : fin de manche participant => Results", select(snap("FINISHED"), playing) == "Results")
	check("écran : fin de manche au menu => MainMenu", select(snap("FINISHED"), menuPlayer) == "MainMenu")
	check("écran : joueur inconnu => MainMenu (jamais vide)", select(snap("PLAYING"), nil) == "MainMenu")
end

print(("[Phase4Tests] %d réussis, %d échecs"):format(passed, failed))
