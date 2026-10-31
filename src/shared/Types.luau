--!strict
-- Types partagés client / serveur. Aucune logique ici : uniquement des déclarations de types.

export type GameState = "WAITING" | "READY" | "COUNTDOWN" | "PLAYING" | "FINISHED" | "RESETTING"

export type RoundOutcome = "WIN" | "DRAW"

-- Coordonnées de grille 1-indexées, relatives à la zone jouable (hors anneau de murs extérieurs).
export type Cell = {
	x: number,
	y: number,
}

export type CellKind = "EMPTY" | "PILLAR" | "CRATE" | "BORDER"

export type PowerupId = "BombPlus" | "FirePlus" | "SpeedPlus" | "Shield"

export type PlayerStats = {
	bombCapacity: number,
	blastRange: number,
	speedPickups: number,
	hasShield: boolean,
}

export type MapLayout = {
	seed: number,
	sizeId: string,
	size: number,
	theme: string,
	-- cells[y][x] ; index 1..size
	cells: { { CellKind } },
	spawns: { Cell },
}

export type RoundResult = {
	outcome: RoundOutcome,
	winnerUserId: number?,
	-- Ordre de classement, du meilleur au moins bon.
	ranking: { number },
	durationSeconds: number,
}

return {}
