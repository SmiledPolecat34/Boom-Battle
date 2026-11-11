--!strict
-- Effets et animations de couleur des 24 bombes 3D (données pures, côté client : aucun effet sur le gameplay).
-- Chaque bombe reçoit TOUJOURS : une mèche qui crépite (étincelles + fumée), l'animation de pose / balancement qui
-- s'accélère avec la mèche, et le clignotement + tremblement des derniers instants (BombFx). Cette config ajoute l'effet
-- PROPRE à chaque thème : émetteurs de particules, pulsation de couleur (glow) et cycle de couleurs (cycle).
-- Les particules utilisent la texture par défaut du moteur (aucun identifiant d'asset) ; couleurs et formes font le thème.
-- Budget : au plus 3 émetteurs thématiques par bombe (la mèche en ajoute 2) ; sur appareil tactile les débits sont réduits.
--
-- Préréglage : rate (particules/s), lifetime/speed {min, max}, size / transparency {début, fin}, color {{r,g,b},{r,g,b}}
-- (début, fin), spread (degrés, 0 à 180), accel {x, y, z}, light (0 à 1 : émission de lumière).
-- glow : { pieces, a, b, hz } couleur qui pulse de a à b ; cycle : { pieces, hz } les couleurs des pièces tournent d'un cran.

export type Preset = {
	rate: number,
	lifetime: { number },
	speed: { number },
	size: { number },
	transparency: { number },
	color: { { number } },
	spread: number,
	accel: { number },
	light: number,
}
export type Glow = { pieces: { string }, a: { number }, b: { number }, hz: number }
export type Cycle = { pieces: { string }, hz: number }
export type Emitter = { preset: string, piece: string }
-- Effet d'AMBIANCE autour de la bombe (BombAura), en géométrie néon animée (visible aussi dans les ViewportFrame).
--   mode  : "orbit" (tourne autour), "fall" (tombe : neige, feuilles), "rise" (monte : braises, cœurs, volutes),
--           "bolts" (éclairs qui circulent autour du corps), "glint" (scintillement sur le corps)
--   shape : "sparkle" (étoile fine), "ball", "heart", "leaf", "rock"
--   count : nombre de pièces (2 à 8) ; colors : une couleur par pièce, en boucle ; size : taille en studs ; speed : cycles/s
--   radius : rayon d'orbite en multiples du rayon du corps ; y0 / y1 : départ / arrivée en studs au-dessus du centre du corps
--   alpha : transparence de base (volutes translucides)
export type Aura = {
	mode: string,
	shape: string,
	count: number,
	colors: { { number } },
	size: number,
	speed: number,
	radius: number?,
	y0: number?,
	y1: number?,
	alpha: number?,
}
export type FlameColors = { core: { number }, mid: { number }, tip: { number } }
export type ModelFx = {
	fuse: boolean?, -- false : pas d'étincelle de mèche générique (la bombe a la sienne)
	fusePiece: string?, -- pièce qui porte l'étincelle (défaut : BombFuse_Tip)
	flamePiece: string?, -- pièce au-dessus de laquelle brûle la flamme (défaut : fusePiece ou BombFuse_Tip)
	flame: FlameColors?, -- couleurs de la flamme (défaut : DefaultFlame)
	star: boolean?, -- false : pas d'étoile d'étincelle autour de la flamme (la bombe a la sienne : Cosmique)
	aura: Aura?, -- effet d'ambiance autour de la bombe (voir Aura)
	emitters: { Emitter }?,
	glow: { Glow }?,
	cycle: Cycle?,
}

local BombEffectsConfig = {}

BombEffectsConfig.DefaultFusePiece = "BombFuse_Tip"

-- Flamme de la mèche (BombFlame) : cœur (blanc chaud), milieu, pointe (rouge). Géométrie néon, pas de particules : elle doit
-- aussi s'afficher dans les ViewportFrame (boutique, inventaire, HUD), où les particules ne sont pas rendues.
BombEffectsConfig.DefaultFlame = table.freeze({
	core = table.freeze({ 255, 232, 130 }),
	mid = table.freeze({ 255, 120, 20 }),
	tip = table.freeze({ 255, 45, 10 }),
})

BombEffectsConfig.Presets = table.freeze({
	fuse_spark = { rate = 22, lifetime = { 0.25, 0.5 }, speed = { 4, 8 }, size = { 0.28, 0 }, transparency = { 0, 1 }, color = { { 255, 255, 255 }, { 255, 170, 40 } }, spread = 180, accel = { 0, 3, 0 }, light = 1 },
	fuse_smoke = { rate = 7, lifetime = { 0.7, 1.2 }, speed = { 0.8, 1.6 }, size = { 0.3, 1.1 }, transparency = { 0.35, 1 }, color = { { 110, 110, 120 }, { 70, 70, 80 } }, spread = 25, accel = { 0, 1.5, 0 }, light = 0 },
	embers = { rate = 9, lifetime = { 0.8, 1.5 }, speed = { 1.5, 3 }, size = { 0.25, 0 }, transparency = { 0, 1 }, color = { { 255, 200, 80 }, { 255, 70, 10 } }, spread = 40, accel = { 0, 2.5, 0 }, light = 1 },
	frost = { rate = 7, lifetime = { 1, 1.8 }, speed = { 0.4, 1 }, size = { 0.35, 0.05 }, transparency = { 0.2, 1 }, color = { { 235, 252, 255 }, { 150, 225, 255 } }, spread = 180, accel = { 0, -0.8, 0 }, light = 0.6 },
	arcs = { rate = 16, lifetime = { 0.12, 0.25 }, speed = { 5, 10 }, size = { 0.35, 0 }, transparency = { 0, 0.8 }, color = { { 255, 255, 255 }, { 80, 150, 255 } }, spread = 180, accel = { 0, 0, 0 }, light = 1 },
	ghost = { rate = 5, lifetime = { 1, 1.6 }, speed = { 0.8, 1.4 }, size = { 0.4, 1 }, transparency = { 0.4, 1 }, color = { { 170, 255, 190 }, { 60, 200, 120 } }, spread = 20, accel = { 0, 1.2, 0 }, light = 0.8 },
	love = { rate = 5, lifetime = { 1, 1.6 }, speed = { 1, 2 }, size = { 0.35, 0.1 }, transparency = { 0.1, 1 }, color = { { 255, 170, 200 }, { 255, 60, 120 } }, spread = 60, accel = { 0, 1.5, 0 }, light = 0.8 },
	twinkle = { rate = 7, lifetime = { 0.6, 1.1 }, speed = { 0.3, 0.8 }, size = { 0.45, 0 }, transparency = { 0, 1 }, color = { { 255, 255, 255 }, { 255, 215, 90 } }, spread = 180, accel = { 0, 0, 0 }, light = 1 },
	leaves = { rate = 4, lifetime = { 1.4, 2.2 }, speed = { 0.5, 1.2 }, size = { 0.3, 0.2 }, transparency = { 0, 0.8 }, color = { { 120, 220, 80 }, { 60, 170, 60 } }, spread = 180, accel = { 0, -1.2, 0 }, light = 0 },
	glint = { rate = 5, lifetime = { 0.3, 0.6 }, speed = { 0, 0.4 }, size = { 0.4, 0 }, transparency = { 0, 1 }, color = { { 255, 255, 255 }, { 200, 220, 255 } }, spread = 180, accel = { 0, 0, 0 }, light = 1 },
	dust = { rate = 6, lifetime = { 0.8, 1.4 }, speed = { 0.5, 1.2 }, size = { 0.3, 0.9 }, transparency = { 0.5, 1 }, color = { { 60, 50, 45 }, { 30, 25, 25 } }, spread = 30, accel = { 0, 1, 0 }, light = 0 },
	crystal = { rate = 5, lifetime = { 0.4, 0.8 }, speed = { 0, 0.5 }, size = { 0.4, 0 }, transparency = { 0, 1 }, color = { { 255, 255, 255 }, { 190, 150, 255 } }, spread = 180, accel = { 0, 0, 0 }, light = 1 },
})

-- Une entrée par modèle (B01..B24) : les bombes sans effet propre (couleurs, balles, tonneau, militaire...) gardent la
-- mèche et les animations génériques. Les noms de pièces doivent exister dans BombSkinConfig (vérifié par les tests).
local models: { [string]: ModelFx } = {
	B01_Classique = { aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 } }, size = 0.7, speed = 0.4 } },
	B02_Rouge = { aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 } }, size = 0.7, speed = 0.4 } },
	B03_Bleue = { aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 } }, size = 0.7, speed = 0.4 } },
	B04_Verte = { aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 } }, size = 0.7, speed = 0.4 } },
	B05_Jaune = { aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 } }, size = 0.7, speed = 0.4 } },
	B06_Glacee = {
		emitters = { { preset = "frost", piece = "BombBody_Mid" } },
		-- flocons de neige et particules glacées qui flottent doucement autour de la bombe
		aura = { mode = "fall", shape = "sparkle", count = 8, colors = { { 235, 252, 255 }, { 150, 225, 255 }, { 255, 255, 255 } }, size = 0.5, speed = 0.2, radius = 1.15, y0 = 2.4, y1 = -1.3 },
	},
	B07_Lave = {
		emitters = { { preset = "embers", piece = "BombBody_Base" } },
		-- braises et étincelles qui montent (le corps pulse déjà comme de la chaleur)
		aura = { mode = "rise", shape = "ball", count = 7, colors = { { 255, 130, 20 }, { 255, 205, 70 }, { 255, 70, 15 } }, size = 0.3, speed = 0.28, radius = 0.9, y0 = 0.6, y1 = 3.2 },
		glow = {
			{ pieces = { "BombBody_Base" }, a = { 255, 154, 31 }, b = { 255, 215, 100 }, hz = 1.2 },
			{ pieces = { "BombSkin_PlateEdge" }, a = { 255, 74, 18 }, b = { 255, 160, 50 }, hz = 1.7 },
		},
	},
	B08_Electrique = {
		emitters = { { preset = "arcs", piece = "BombBody_CrackGlow" } },
		-- petits éclairs bleus et arcs qui apparaissent et CIRCULENT autour de la bombe
		aura = { mode = "bolts", shape = "ball", count = 4, colors = { { 90, 175, 255 } }, size = 0.12, speed = 1, radius = 1.08 },
		glow = { { pieces = { "BombBody_CrackGlow" }, a = { 42, 107, 255 }, b = { 150, 205, 255 }, hz = 6 } },
		flame = { core = { 235, 248, 255 }, mid = { 90, 170, 255 }, tip = { 40, 90, 255 } }, -- flamme électrique
	},
	-- galaxie, lumières et étincelle gérées par CosmicFX ; la flamme brûle au-dessus de l'étoile-étincelle
	B09_Cosmique = {
		fuse = false,
		star = false,
		-- particules violettes et roses en orbite : légère aura énergétique
		aura = { mode = "orbit", shape = "sparkle", count = 6, colors = { { 255, 130, 240 }, { 170, 120, 255 }, { 255, 255, 255 } }, size = 0.55, speed = 0.1, radius = 1.3 },
		flamePiece = "BombSpark_Star",
		flame = { core = { 255, 240, 251 }, mid = { 255, 106, 240 }, tip = { 150, 90, 255 } },
	},
	B10_ArcEnCiel = {
		-- billes multicolores en orbite, léger scintillement
		aura = { mode = "orbit", shape = "ball", count = 6, colors = { { 229, 57, 53 }, { 251, 140, 0 }, { 253, 216, 53 }, { 67, 160, 71 }, { 30, 136, 229 }, { 142, 36, 170 } }, size = 0.38, speed = 0.14, radius = 1.25 },
		cycle = { pieces = { "BombBody_Band1", "BombBody_Band2", "BombBody_Band3", "BombBody_Band4", "BombBody_Band5", "BombBody_Band6" }, hz = 1.5 },
	},
	B11_Crane = {
		emitters = { { preset = "ghost", piece = "BombBody_Cavity" } },
		-- volutes d'esprit vert qui montent
		aura = { mode = "rise", shape = "ball", count = 4, colors = { { 150, 255, 180 }, { 90, 230, 140 } }, size = 0.5, speed = 0.2, radius = 0.8, y0 = 0.5, y1 = 3.0, alpha = 0.35 },
	},
	B12_Citrouille = {
		emitters = { { preset = "embers", piece = "BombSkin_Face" } },
		aura = { mode = "rise", shape = "ball", count = 5, colors = { { 255, 160, 30 }, { 170, 100, 255 }, { 255, 215, 90 } }, size = 0.32, speed = 0.25, radius = 0.85, y0 = 0.7, y1 = 3.0 },
		glow = { { pieces = { "BombSkin_Face" }, a = { 255, 211, 74 }, b = { 255, 140, 40 }, hz = 3.5 } },
	},
	B13_Football = { aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 } }, size = 0.7, speed = 0.4 } },
	B14_Basketball = { aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 } }, size = 0.7, speed = 0.4 } },
	B15_Epineuse = {
		emitters = { { preset = "glint", piece = "BombSkin_Spikes" } },
		aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 }, { 210, 225, 255 } }, size = 0.8, speed = 0.5 },
	},
	B16_Ninja = {
		emitters = { { preset = "dust", piece = "BombBody_Black" } },
		-- volutes de fumée sombre
		aura = { mode = "rise", shape = "ball", count = 4, colors = { { 70, 50, 110 }, { 40, 40, 55 } }, size = 0.46, speed = 0.2, radius = 0.9, y0 = 0.4, y1 = 2.8, alpha = 0.3 },
	},
	B17_Coeur = {
		emitters = { { preset = "love", piece = "BombBody_Heart" } },
		-- petits cœurs qui montent
		aura = { mode = "rise", shape = "heart", count = 4, colors = { { 255, 90, 150 }, { 255, 170, 205 } }, size = 0.75, speed = 0.17, radius = 0.85, y0 = 0.4, y1 = 3.0 },
		glow = { { pieces = { "BombBody_Inner" }, a = { 255, 143, 177 }, b = { 255, 235, 242 }, hz = 2 } },
	},
	B18_Etoiles = {
		emitters = { { preset = "twinkle", piece = "BombBody_Star" } },
		-- petites étoiles lumineuses qui scintillent et tournent autour
		aura = { mode = "orbit", shape = "sparkle", count = 5, colors = { { 255, 215, 90 }, { 255, 245, 190 } }, size = 0.6, speed = 0.12, radius = 1.3 },
	},
	B19_Militaire = { aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 } }, size = 0.7, speed = 0.4 } },
	B20_Tonneau = { aura = { mode = "glint", shape = "sparkle", count = 2, colors = { { 255, 255, 255 } }, size = 0.7, speed = 0.4 } },
	B21_Robot = {
		emitters = { { preset = "arcs", piece = "BombSkin_Glow" } },
		-- petites impulsions lumineuses qui filent autour du corps
		aura = { mode = "orbit", shape = "ball", count = 4, colors = { { 90, 235, 255 }, { 200, 250, 255 } }, size = 0.3, speed = 0.4, radius = 1.2 },
		glow = { { pieces = { "BombSkin_Glow", "BombSkin_Shine" }, a = { 47, 230, 255 }, b = { 168, 243, 255 }, hz = 0.9 } },
	},
	B22_Nature = {
		emitters = { { preset = "leaves", piece = "BombSkin_LeafA" } },
		-- feuilles qui tombent doucement
		aura = { mode = "fall", shape = "leaf", count = 5, colors = { { 100, 205, 75 }, { 60, 170, 60 }, { 245, 240, 225 } }, size = 0.6, speed = 0.17, radius = 1.15, y0 = 2.4, y1 = -1.2 },
	},
	B23_Meteore = {
		emitters = { { preset = "dust", piece = "BombSkin_Rocks" }, { preset = "embers", piece = "BombSkin_Rocks" } },
		-- braises et particules incandescentes
		aura = { mode = "rise", shape = "ball", count = 6, colors = { { 255, 140, 30 }, { 255, 90, 20 }, { 255, 215, 100 } }, size = 0.32, speed = 0.26, radius = 0.95, y0 = 0.5, y1 = 3.0 },
	},
	B24_Cristal = {
		emitters = { { preset = "crystal", piece = "BombBody_Edge" } },
		-- éclats lumineux et reflets scintillants en orbite
		aura = { mode = "orbit", shape = "sparkle", count = 5, colors = { { 205, 150, 255 }, { 255, 255, 255 } }, size = 0.6, speed = 0.1, radius = 1.3 },
	},
}

function BombEffectsConfig.get(modelName: any): ModelFx?
	if typeof(modelName) ~= "string" then
		return nil
	end
	return models[modelName]
end

function BombEffectsConfig.modelNames(): { string }
	local names: { string } = {}
	for name in models do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return table.freeze(BombEffectsConfig)
