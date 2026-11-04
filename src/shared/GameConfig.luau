--!strict
-- Valeurs de gameplay centralisées. Les valeurs marquées PROPOSITION n'ont pas été imposées par le cahier des
-- charges et devront être équilibrées pendant les tests.

local GameConfig = {}

GameConfig.Version = "0.1.0-phase0"

GameConfig.States = table.freeze({
	WAITING = "WAITING",
	READY = "READY",
	COUNTDOWN = "COUNTDOWN",
	PLAYING = "PLAYING",
	FINISHED = "FINISHED",
	RESETTING = "RESETTING",
})

GameConfig.Round = table.freeze({
	MinimumPlayers = 1, -- PROVISOIRE : partie rapide dès 1 joueur (à remonter à 2 plus tard)
	PrivateMinPlayers = 2, -- partie privée : l'hôte peut lancer dès 2 joueurs dans le groupe
	MaxBotDifficulty = 10, -- partie privée : niveau des bots de 1 (très facile) à 10 (très fort)
	DefaultBotDifficulty = 5,
	QuickCountdown = 6, -- secondes : compte à rebours de la partie rapide (aucun lobby, aucun « prêt »)
	MaximumPlayers = 8,
	ReadyCountdown = 10, -- secondes
	RoundDuration = 150, -- secondes
	ResultDuration = 8, -- secondes
	RematchCountdown = 3, -- secondes : compte à rebours court quand tous les joueurs cliquent REJOUER
	-- PROPOSITION : délai après lequel la manche démarre avec les seuls joueurs prêts (si assez nombreux),
	-- pour qu'un joueur inactif ne bloque pas le groupe.
	ReadyTimeout = 45, -- secondes
	MaxSoloBots = 3, -- mode solo : bots maximum (le cahier des charges prévoit 1 à 3)
	-- Uniquement dans Roblox Studio : permet de tester seul. Jamais actif en production.
	AllowSoloInStudio = true,
})

GameConfig.Bomb = table.freeze({
	FuseTime = 2.0, -- secondes
	ExplosionDuration = 0.5, -- secondes
	DefaultCapacity = 1,
	DefaultBlastRange = 2, -- cases
	MaxCapacity = 5,
	MaxBlastRange = 6, -- cases
})

GameConfig.Movement = table.freeze({
	-- PROPOSITION : à valider au playtest de la Phase 1.
	BaseWalkSpeed = 14, -- studs / seconde
	SpeedBonusPerPickup = 2,
	MaxSpeedPickups = 3,
	-- Tolérance serveur entre la position réelle et la position attendue sur le chemin.
	MaxPositionDeviationStuds = 6,
})

GameConfig.Powerups = table.freeze({
	-- PROPOSITION : probabilité qu'une caisse détruite laisse un bonus.
	DropChancePerCrate = 0.25,
	BombPlusAmount = 1,
	FirePlusAmount = 1,
	MaxShield = 1,
})

-- Limites anti-spam appliquées côté serveur, par joueur.
GameConfig.RemoteLimits = table.freeze({
	MoveRequestMinInterval = 0.1, -- secondes
	PlaceBombMinInterval = 0.25,
	ReadyToggleMinInterval = 0.5,
	ShopRequestMinInterval = 0.5,
	EmoteRequestMinInterval = 1.0,
	QuickChatMinInterval = 1.5,
})

-- PROPOSITION : récompenses en Bomb Coins, attribuées uniquement par le serveur.
GameConfig.Rewards = table.freeze({
	ParticipationCoins = 10,
	WinCoins = 50,
	DrawCoins = 20,
})

GameConfig.Data = table.freeze({
	DataVersion = 1,
	DataStoreName = "BombBattlePlayerData",
	AutosaveInterval = 120, -- secondes
	MaxSaveRetries = 3,
	MaxLoadRetries = 3,
	MaxCoins = 1000000000, -- plafond de sécurité du solde
})

return table.freeze(GameConfig)
