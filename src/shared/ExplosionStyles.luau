--!strict
-- Styles visuels d'explosion (données PURES, cosmétiques) : palette + « recette » (combien de gerbes, de fumées, de débris et
-- d'étincelles par module). Le moteur visuel (client/Controllers/ExplosionFx) est le même pour tous les styles ; un style le décline.
-- Aucun style ne change les cases dangereuses : seul le serveur les décide.
--
-- Catalogue de référence : 32 explosions (E01..E32). Réalisées pour l'instant : E01 Classique, E02 Rouge, E03 Bleue, E04 Verte, E05 Jaune, E06 Glacée, E07 Électrique, E08 Feu. Les autres effets existants du
-- catalogue boutique (Glacée, Électrique, Feu) utilisent encore la recette classique TEINTÉE de leur
-- couleur (palette dérivée par `fromColor`) en attendant leur style propre.

export type Palette = {
	core: Color3, -- cœur très clair
	mid: Color3, -- corps de la flamme
	edge: Color3, -- pointe / bord, plus sombre et saturé
	smoke: Color3, -- fumée / poussière
	debris: Color3, -- éclats projetés
}

-- Nombre d'éléments par type de module (center, junction, segment, end, impact).
export type Recipe = {
	spikes: { [string]: number }, -- gerbes (fuseaux de flamme)
	smoke: { [string]: number }, -- volutes de fumée / poussière
	debris: { [string]: number }, -- éclats de roche ou de bois
	sparks: { [string]: number }, -- étincelles (émetteur de particules)
	ring: boolean, -- onde de choc au sol sur le centre
}

-- Variante du moteur « Blender » (ExplosionE01) : présente seulement pour les styles réalisés dans Blender (E01, E02...).
export type E01Variant = {
	colors: { [string]: Color3 }, -- surcharge de couleur par matériau (R, O, Y, W, CORE, GLOW, SPARK, SMOKE, SMOKE_EDGE, ROCK_A, ROCK_B)
	skip: { [string]: boolean }, -- matériaux non affichés (ex. fumée)
	meshScale: { [string]: number }, -- facteur de taille par matériau (ex. rochers agrandis)
	-- Explosion dotée de ses propres données/maillages (ex. E06) : module Shared.Explosions.<data>, dossier ReplicatedStorage.<meshes>, préfixe des MeshParts.
	data: string?,
	meshes: string?,
	prefix: string?,
	liteSkip: { string }?, -- appareil tactile : objets dont le nom contient l'un de ces mots ne sont pas affichés
	liteHalf: { string }?, -- appareil tactile : un objet sur deux (noms terminés par <mot><numéro>)
	-- Effet avec DESCENTE avant l'impact (ex. Météore) : nombre d'images (24 i/s) qui précèdent l'impact dans l'animation du centre. Le client lance
	-- la descente `lead` images avant l'explosion serveur prévue (instant de pose + durée de mèche) ; purement visuel.
	lead: number?,
	-- Avec `lead` : nombre d'images dont les briques de branche (segment / extrémité) démarrent avant leur retard de propagation (leur chute courte
	-- se termine alors presque au moment de leur impact) ; purement visuel, par défaut 0.
	pieceLead: number?,
}

export type Style = {
	id: string,
	name: string,
	palette: Palette,
	recipe: Recipe,
	e01: E01Variant?,
}

local ExplosionStyles = {}

local CLASSIC_RECIPE: Recipe = table.freeze({
	spikes = table.freeze({ center = 9, junction = 5, segment = 2, ["end"] = 3, impact = 3 }),
	smoke = table.freeze({ center = 5, junction = 2, segment = 1, ["end"] = 2, impact = 3 }),
	debris = table.freeze({ center = 4, junction = 0, segment = 0, ["end"] = 0, impact = 6 }),
	sparks = table.freeze({ center = 14, junction = 6, segment = 0, ["end"] = 6, impact = 4 }),
	ring = true,
})

local CLASSIC: Style = table.freeze({
	id = "E01",
	name = "Classique",
	palette = table.freeze({
		core = Color3.fromRGB(255, 226, 120),
		mid = Color3.fromRGB(255, 112, 14),
		edge = Color3.fromRGB(222, 40, 8),
		smoke = Color3.fromRGB(228, 204, 170),
		debris = Color3.fromRGB(96, 62, 42),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({ colors = table.freeze({}), skip = table.freeze({}), meshScale = table.freeze({}) }),
})

-- E02 Rouge (Blender : tools/blender/explosions/e02_rouge.py) : même gerbe qu'E01, palette rouge sang, pas de fumée, gros rochers sombres.
local function hex(h: number): Color3
	return Color3.fromRGB(bit32.rshift(h, 16) % 256, bit32.rshift(h, 8) % 256, h % 256)
end
local RED: Style = table.freeze({
	id = "E02",
	name = "Rouge",
	palette = table.freeze({
		core = hex(0xFFF1D0),
		mid = hex(0xF01E10),
		edge = hex(0xB0101C),
		smoke = hex(0x5A3036),
		debris = hex(0x2A1A20),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({
			R = hex(0xB0101C),
			O = hex(0xF01E10),
			Y = hex(0xFF7A16),
			W = hex(0xFFD9A0),
			CORE = hex(0xFFF1D0),
			GLOW = hex(0xE0200E),
			SPARK = hex(0xFF5A28),
			ROCK_A = hex(0x5A3036),
			ROCK_B = hex(0x2A1A20),
		}),
		skip = table.freeze({ SMOKE = true, SMOKE_EDGE = true }),
		meshScale = table.freeze({ ROCK_A = 2.4, ROCK_B = 2.4 }),
	}),
})

-- E03 Bleue (Blender : tools/blender/explosions/e03_bleue.py) : même gerbe qu'E01, palette bleu électrique, pas de fumée, cristaux clairs au pied.
local BLUE: Style = table.freeze({
	id = "E03",
	name = "Bleue",
	palette = table.freeze({
		core = hex(0xFFFFFF),
		mid = hex(0x1E78FF),
		edge = hex(0x1030C8),
		smoke = hex(0xA8DCFF),
		debris = hex(0x3C78C8),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({
			R = hex(0x1030C8),
			O = hex(0x1E78FF),
			Y = hex(0x4CC8FF),
			W = hex(0xD8F6FF),
			CORE = hex(0xFFFFFF),
			GLOW = hex(0x2A8CFF),
			SPARK = hex(0x8FE4FF),
			ROCK_A = hex(0xA8DCFF),
			ROCK_B = hex(0x3C78C8),
		}),
		skip = table.freeze({ SMOKE = true, SMOKE_EDGE = true }),
		meshScale = table.freeze({ ROCK_A = 2.0, ROCK_B = 2.0 }),
	}),
})

-- E04 Verte (Blender : tools/blender/explosions/e04_verte.py) : même gerbe qu'E01, palette vert toxique, pas de fumée, rochers verts au pied.
local GREEN: Style = table.freeze({
	id = "E04",
	name = "Verte",
	palette = table.freeze({
		core = hex(0xF4FFD8),
		mid = hex(0x2FD02A),
		edge = hex(0x0E7A1A),
		smoke = hex(0x5FD04A),
		debris = hex(0x1C7A2E),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({
			R = hex(0x0E7A1A),
			O = hex(0x2FD02A),
			Y = hex(0x8CFF2A),
			W = hex(0xE6FFC0),
			CORE = hex(0xF4FFD8),
			GLOW = hex(0x3CE030),
			SPARK = hex(0xB8FF3C),
			ROCK_A = hex(0x5FD04A),
			ROCK_B = hex(0x1C7A2E),
		}),
		skip = table.freeze({ SMOKE = true, SMOKE_EDGE = true }),
		meshScale = table.freeze({ ROCK_A = 2.0, ROCK_B = 2.0 }),
	}),
})

-- E05 Jaune (Blender : tools/blender/explosions/e05_jaune.py) : même gerbe qu'E01, palette dorée, pas de fumée, rochers dorés au pied.
local YELLOW: Style = table.freeze({
	id = "E05",
	name = "Jaune",
	palette = table.freeze({
		core = hex(0xFFFFFF),
		mid = hex(0xFFB800),
		edge = hex(0xE08A00),
		smoke = hex(0xE8C050),
		debris = hex(0x8A6A20),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({
			R = hex(0xE08A00),
			O = hex(0xFFB800),
			Y = hex(0xFFE040),
			W = hex(0xFFF8C8),
			CORE = hex(0xFFFFFF),
			GLOW = hex(0xFFD030),
			SPARK = hex(0xFFF070),
			ROCK_A = hex(0xE8C050),
			ROCK_B = hex(0x8A6A20),
		}),
		skip = table.freeze({ SMOKE = true, SMOKE_EDGE = true }),
		meshScale = table.freeze({ ROCK_A = 2.0, ROCK_B = 2.0 }),
	}),
})

-- E06 Glacée (Blender : tools/blender/explosions/e06_glacee.py, V3 validée) : souffle glacial en croix, onde, givre, brume, poudreuse, lames et éclats de glace.
-- Données générées (Shared.Explosions.E06Data) et maillages propres (ReplicatedStorage.E06Meshes, FBX E06_Meshes.fbx). Couleurs lues dans les données.
local ICE: Style = table.freeze({
	id = "E06",
	name = "Glacée",
	palette = table.freeze({
		core = hex(0xEAF8FF),
		mid = hex(0x8FD3FF),
		edge = hex(0x3FA9FF),
		smoke = hex(0xDDF1FF),
		debris = hex(0xCFEFFF),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E06Data",
		meshes = "E06Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Snow", "Mist" }),
		liteHalf = table.freeze({ "Frag" }),
	}),
})

-- E07 Électrique (Blender : tools/blender/explosions/e07_electrique.py) : décharge bleu électrique instable (éclairs organiques ramifiés qui changent de forme et d'intensité
-- à chaque image, flash central irrégulier, arcs au point d'impact, étincelles blanches). Données Shared.Explosions.E07Data, maillages ReplicatedStorage.E07Meshes.
local ELECTRIC: Style = table.freeze({
	id = "E07",
	name = "Électrique",
	palette = table.freeze({
		core = hex(0xFFFFFF),
		mid = hex(0x35B4FF),
		edge = hex(0x1E64FF),
		smoke = hex(0xA5E6FF),
		debris = hex(0x5CC8FF),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		-- « Glow » (halo plat au sol d'E01) : sans transparence dans les données exportées il s'affichait en dalle cyan opaque -> non affiché
		skip = table.freeze({ Glow = true }),
		meshScale = table.freeze({}),
		data = "E07Data",
		meshes = "E07Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Spark", "Ember", "Glow" }),
		liteHalf = table.freeze({ "Arc", "Impact" }),
	}),
})

-- E08 Feu (Blender : tools/blender/explosions/e08_feu.py, V2 validée) : brasier — langues de feu courbes à 3 couches (rouge / orange / jaune, cœur blanc-jaune au centre) qui vacillent,
-- flash jaune-blanc, rangée de flammes basses reliant les cases, langues et braises projetées, petits rochers sombres, légère fumée à la dissipation.
-- Données Shared.Explosions.E08Data, maillages ReplicatedStorage.E08Meshes.
local FIRE: Style = table.freeze({
	id = "E08",
	name = "Feu",
	palette = table.freeze({
		core = hex(0xFFF6C8),
		mid = hex(0xFF8A1E),
		edge = hex(0xFF3A08),
		smoke = hex(0x2E2724),
		debris = hex(0x3A2C26),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E08Data",
		meshes = "E08Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Smoke", "Lick" }),
		liteHalf = table.freeze({ "Ember" }),
	}),
})

-- E09 Arc-en-ciel (Blender : tools/blender/explosions/e09_arcenciel.py, V3) : flash blanc, éclats de couleurs, onde de choc, gerbe de pics courbes aux 7 couleurs,
-- rubans ondulants qui relient les cases, étoiles / étincelles / confettis. Purement cosmétique. Données Shared.Explosions.E09Data, maillages ReplicatedStorage.E09Meshes.
-- Pas encore de ligne dans le catalogue boutique : l'identifiant "effect_rainbow" est réservé (la boutique n'est pas modifiée).
local RAINBOW: Style = table.freeze({
	id = "E09",
	name = "Arc-en-ciel",
	palette = table.freeze({
		core = hex(0xFFFFFF),
		mid = hex(0xFFE53B),
		edge = hex(0xA64DFF),
		smoke = hex(0xFF6FD8),
		debris = hex(0x2FC8FF),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E09Data",
		meshes = "E09Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Star", "Glint", "Puff" }),
		liteHalf = table.freeze({ "Confetti", "Spark" }),
	}),
})

-- E10 Néon (Blender : tools/blender/explosions/e10_neon.py, V2) : noyau magenta qui pulse, impulsions d'anneau, rayons et lignes néon qui clignotent le long des bras
-- (avec halo translucide à rémanence courte), éclats cristallins roses / violets, losanges projetés. Purement cosmétique. Données Shared.Explosions.E10Data, maillages ReplicatedStorage.E10Meshes.
local NEON: Style = table.freeze({
	id = "E10",
	name = "Néon",
	palette = table.freeze({
		core = hex(0xFFF0FF),
		mid = hex(0xFF2BD6),
		edge = hex(0xB03BFF),
		smoke = hex(0x7A1F8F),
		debris = hex(0x7A1F8F),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E10Data",
		meshes = "E10Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Rubble", "Glint" }),
		liteHalf = table.freeze({ "Spark", "Beam" }),
	}),
})

-- E11 Météore (Blender : tools/blender/explosions/e11_meteore.py, V4 validée) : un météore de roche sombre à fissures de lave tombe du ciel (descente de
-- 6 images, traînée de feu), s'écrase sur la case centrale (flash, ondes de choc, poussière), projette des roches et des fragments de lave dans les 4
-- directions de la croix, laisse des fissures de lave qui refroidissent (jaune -> orange -> rouge sombre) puis s'effacent. Purement cosmétique.
-- Données Shared.Explosions.E11Data, maillages ReplicatedStorage.E11Meshes. `lead` : la descente démarre 6 images avant l'explosion serveur (ExplosionPrelude).
local METEOR: Style = table.freeze({
	id = "E11",
	name = "Météore",
	palette = table.freeze({
		core = hex(0xFFE27A),
		mid = hex(0xFF7A18),
		edge = hex(0x3B2B26),
		smoke = hex(0x4A423D),
		debris = hex(0x3B2B26),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E11Data",
		meshes = "E11Meshes",
		prefix = "M_",
		lead = 6,
		liteSkip = table.freeze({ "Smoke", "Dust", "Late", "TEmber", "Heat" }),
		liteHalf = table.freeze({ "Trail", "Frag", "Lava", "Ember" }),
	}),
})

-- E12 Cristal (Blender : tools/blender/explosions/e12_cristal.py, V2 en test) : de grands cristaux violets, roses et bleus jaillissent du sol au centre
-- (flash, halo, onde de choc cristalline fine, fissures irrégulières, liserés brillants), des cristaux secondaires et des gravats sombres sur les branches de la croix, des éclats de gemme projetés, puis
-- l'ensemble éclate et se dissipe. Purement cosmétique. Données Shared.Explosions.E12Data, maillages ReplicatedStorage.E12Meshes.
local CRYSTAL: Style = table.freeze({
	id = "E12",
	name = "Cristal",
	palette = table.freeze({
		core = hex(0xF2E2FF),
		mid = hex(0xB04DFF),
		edge = hex(0x5B45FF),
		smoke = hex(0x2A1850),
		debris = hex(0x2A1850),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E12Data",
		meshes = "E12Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Rubble", "Glint", "Halo", "Facet", "CrackD", "Spark" }),
		liteHalf = table.freeze({ "Shard", "Burst" }),
	}),
})

-- E13 Cœur (Blender : tools/blender/explosions/e13_coeur.py, V3) : un grand cœur rose bombé et brillant surgit au centre (flash et impulsion rose, battements),
-- puis éclate en petits cœurs 3D projetés le long des 4 branches de la croix, avec des cœurs plats légers au sol, des nuages roses, des paillettes
-- et des étoiles blanches ; tout rétrécit en s'élevant. Purement cosmétique. Données Shared.Explosions.E13Data, maillages ReplicatedStorage.E13Meshes.
local HEART: Style = table.freeze({
	id = "E13",
	name = "Cœur",
	palette = table.freeze({
		core = hex(0xFFE6F3),
		mid = hex(0xFF6FBC),
		edge = hex(0xFF4FA8),
		smoke = hex(0xFF8EC4),
		debris = hex(0x5A0F3E),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E13Data",
		meshes = "E13Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Glitter", "Rubble", "Puff", "Impulse", "Spike" }),
		liteHalf = table.freeze({ "Mini", "Burst", "Glint", "Trace" }),
	}),
})

-- E14 Étoiles (Blender : tools/blender/explosions/e14_etoiles.py, V3) : flash blanc-jaune très bref, une grande étoile dorée 3D au centre et des étoiles
-- secondaires de tailles différentes lancées le long des 4 branches de la croix (rotation légère, taille variable, courtes traînées dorées), onde en étoile
-- au sol, fragments dorés, poussières lumineuses, étincelles et paillettes qui s'éteignent. Purement cosmétique. Données Shared.Explosions.E14Data,
-- maillages ReplicatedStorage.E14Meshes.
local STARS: Style = table.freeze({
	id = "E14",
	name = "Étoiles",
	palette = table.freeze({
		core = hex(0xFFF3A0),
		mid = hex(0xFFC21A),
		edge = hex(0xFF9A1A),
		smoke = hex(0xFFE890),
		debris = hex(0xFFC21A),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E14Data",
		meshes = "E14Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Mote", "Glitter", "Flash0", "Halo" }),
		liteHalf = table.freeze({ "Frag", "Glint", "Mini", "Spike" }),
	}),
})

-- E15 Fumée (Blender : tools/blender/explosions/e15_fumee.py, V4) : flash sec et onde de choc très brève (4 arcs fins sur les seuls axes des bras, jamais sur les
-- diagonales), coeur sombre qui gonfle (opaque au pic puis translucide), nuages gris translucides qui se propagent en croix, se déforment, s'étirent et se
-- dissipent ; suie et poussière plutôt que rochers. Purement cosmétique. Données Shared.Explosions.E15Data, maillages ReplicatedStorage.E15Meshes.
local SMOKE: Style = table.freeze({
	id = "E15",
	name = "Fumée",
	palette = table.freeze({
		core = hex(0xF4F5FB),
		mid = hex(0x9AA1BA),
		edge = hex(0x555B75),
		smoke = hex(0xD3D6E3),
		debris = hex(0x30344A),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E15Data",
		meshes = "E15Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Arc", "Roll", "Dust", "Soot", "Rubble", "Chip", "CloudTop" }),
		liteHalf = table.freeze({ "CloudOut", "Wave" }),
	}),
})

-- E16 Aura (Blender : tools/blender/explosions/e16_aura.py, V3) : énergie pure (aucun solide) : noyau blanc-violet pulsant dans une aura magenta et noire, impulsion en
-- dôme à 4 lobes, vagues d'énergie ondulantes en croix (alternance de 2 formes/matériaux par image), volutes fines, particules orbitales, éclairs subtils,
-- impulsion et rémanence aux extrémités. Purement cosmétique. Données Shared.Explosions.E16Data, maillages ReplicatedStorage.E16Meshes.
local AURA: Style = table.freeze({
	id = "E16",
	name = "Aura",
	palette = table.freeze({
		core = hex(0xF0E4FF),
		mid = hex(0xE040FF),
		edge = hex(0x5A22C8),
		smoke = hex(0x1A0838),
		debris = hex(0x8E3CFF),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E16Data",
		meshes = "E16Meshes",
		prefix = "M_",
		liteSkip = table.freeze({ "Mote", "Bolt", "Wisp", "WaveC", "WaveD", "Halo" }),
		liteHalf = table.freeze({}),
	}),
})

-- E17 Eau (Blender : tools/blender/explosions/e17_eau.py, V6) : des gouttes d'eau géantes tombent du ciel sur chaque case de la croix et éclatent. Une grosse goutte
-- centrale (descente de 6 images avant l'impact, calée sur l'explosion serveur comme Météore) puis des gouttes plus petites sur les branches (chute de 2 images,
-- démarrage 1 image avant leur retard de propagation : pieceLead). Chaque impact : couronne d'eau irrégulière, onde, écume, gouttelettes projetées, traces d'eau.
-- Purement cosmétique. Données Shared.Explosions.E17Data, maillages ReplicatedStorage.E17Meshes.
local WATER: Style = table.freeze({
	id = "E17",
	name = "Eau",
	palette = table.freeze({
		core = hex(0xDDF4FF),
		mid = hex(0x3FB8FF),
		edge = hex(0x1E6BE8),
		smoke = hex(0x9FD8FF),
		debris = hex(0x4FB8FF),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E17Data",
		meshes = "E17Meshes",
		prefix = "M_",
		lead = 6,
		pieceLead = 1,
		liteSkip = table.freeze({ "_Hi", "Foam", "Film", "Sheet", "DropC" }),
		liteHalf = table.freeze({ "Spl" }),
	}),
})

-- Palette vert forêt/émeraude/lumineux ; lianes vivantes (surgissement, ouverture, fermeture, traction sous terre).
local NATURE: Style = table.freeze({
	id = "E18",
	name = "Nature",
	palette = table.freeze({
		core = hex(0xE8FFB0),
		mid = hex(0x58C838),
		edge = hex(0x237A38),
		smoke = hex(0x9BE44F),
		debris = hex(0x6B4A32),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E18Data",
		meshes = "E18Meshes",
		prefix = "M_",
		lead = 4,
		pieceLead = 1,
		liteSkip = table.freeze({ "Thin", "Speck", "Dirt", "Orbit" }),
		liteHalf = table.freeze({ "Fly", "Swirl", "VLeaf" }),
	}),
})

-- Palette sable beige/doré/ocre ; vagues déferlantes en croix, montagne centrale qui surgit puis s'effondre, grains qui glissent.
local SAND: Style = table.freeze({
	id = "E19",
	name = "Sable",
	palette = table.freeze({
		core = hex(0xFFF1C4),
		mid = hex(0xE3B86B),
		edge = hex(0xB07A3A),
		smoke = hex(0xD9A85A),
		debris = hex(0x8A5E34),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E19Data",
		meshes = "E19Meshes",
		prefix = "M_",
		lead = 2,
		pieceLead = 1,
		liteSkip = table.freeze({ "Dirt", "Puff", "Fall" }),
		liteHalf = table.freeze({ "Grain", "Slide" }),
	}),
})

-- Palette vert acide/vert foncé/jaune fluorescent ; tête de mort toxique au centre, coulées d'acide en croix, bulles chimiques.
local TOXIC: Style = table.freeze({
	id = "E20",
	name = "Toxic",
	palette = table.freeze({
		core = hex(0xF4FF3A),
		mid = hex(0x7CE02E),
		edge = hex(0x2C8A2A),
		smoke = hex(0x8FE04A),
		debris = hex(0x2E7F2A),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E20Data",
		meshes = "E20Meshes",
		prefix = "M_",
		lead = 3,
		pieceLead = 1,
		liteSkip = table.freeze({ "Vapor", "Melt", "Drop", "Shard", "EyeHalo", "Rim" }),
		liteHalf = table.freeze({ "Bub", "Jet" }),
	}),
})

-- Palette cosmique rose/cyan/or/violet ; archipel de galaxies aspirées par le noyau, projetées en croix, qui se fragmentent en poussière d'étoiles.
local COSMIC: Style = table.freeze({
	id = "E21",
	name = "Cosmique",
	palette = table.freeze({
		core = hex(0xFFF2FF),
		mid = hex(0xB45CFF),
		edge = hex(0x3A2A9A),
		smoke = hex(0x8C6CFF),
		debris = hex(0x4B2A8A),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E21Data",
		meshes = "E21Meshes",
		prefix = "M_",
		lead = 3,
		pieceLead = 1,
		liteSkip = table.freeze({ "Gath", "Birth", "Streak", "Imp", "esc", "tailW", "silbody", "CloudD", "CloudC", "CloudB", "NebCyan", "NebMag", "NebFar", "CStC", "Rock", "MBodyB", "MArmB", "MHiB", "MStarsP", "Flare", "trail" }),
		liteHalf = table.freeze({ "Dust", "Glint", "frag" }),
	}),
})

-- RÉSERVE : variante V11 de Cosmique (validée avant la V12), non branchée au catalogue. Pour revenir à la V11 : importer
-- assets/3D/BOOM_BATTLE_ART/03_VFX/EXPLOSIONS/E21_Cosmic/FBX_export/E21V11_Meshes.fbx comme E21V11Meshes (ReplicatedStorage), puis mettre
-- effect_cosmic = COSMIC_V11 dans byEffectId. Palette cosmique rose/cyan/or/violet ; archipel de galaxies aspirées par le noyau, projetées en croix, qui se fragmentent en poussière d'étoiles.
local COSMIC_V11: Style = table.freeze({
	id = "E21",
	name = "Cosmique V11",
	palette = table.freeze({
		core = hex(0xFFF2FF),
		mid = hex(0xB45CFF),
		edge = hex(0x3A2A9A),
		smoke = hex(0x8C6CFF),
		debris = hex(0x4B2A8A),
	}),
	recipe = CLASSIC_RECIPE,
	e01 = table.freeze({
		colors = table.freeze({}),
		skip = table.freeze({}),
		meshScale = table.freeze({}),
		data = "E21V11Data",
		meshes = "E21V11Meshes",
		prefix = "M_",
		lead = 3,
		pieceLead = 1,
		liteSkip = table.freeze({ "Gath", "Birth", "Streak", "Imp", "esc", "tailW", "silbody", "CloudD", "CloudC", "CloudB", "NebCyan", "NebMag", "NebFar", "CStC", "Rock", "MBodyB", "MArmB", "MHiB", "MStarsP", "Flare", "trail" }),
		liteHalf = table.freeze({ "Dust", "Glint", "frag" }),
	}),
})

-- Styles réalisés, par identifiant d'effet du catalogue boutique.
local byEffectId: { [string]: Style } = {
	effect_classic = CLASSIC,
	effect_red = RED,
	effect_blue = BLUE,
	effect_green = GREEN,
	effect_yellow = YELLOW,
	effect_ice = ICE,
	effect_electric = ELECTRIC,
	effect_fire = FIRE,
	effect_rainbow = RAINBOW,
	effect_neon = NEON,
	effect_meteor = METEOR,
	effect_crystal = CRYSTAL,
	effect_heart = HEART,
	effect_stars = STARS,
	effect_smoke = SMOKE,
	effect_aura = AURA,
	effect_water = WATER,
	effect_nature = NATURE,
	effect_sand = SAND,
	effect_toxic = TOXIC,
	effect_cosmic = COSMIC,
}

-- Recette classique teintée d'une couleur (effets pas encore réalisés).
function ExplosionStyles.fromColor(color: Color3): Style
	local white = Color3.new(1, 1, 1)
	return table.freeze({
		id = "TINTED",
		name = "Classique teinté",
		palette = table.freeze({
			core = color:Lerp(white, 0.72),
			mid = color,
			edge = color:Lerp(Color3.new(0, 0, 0), 0.35),
			smoke = color:Lerp(Color3.fromRGB(215, 205, 195), 0.7),
			debris = Color3.fromRGB(86, 60, 46),
		}),
		recipe = CLASSIC_RECIPE,
	})
end

-- Style d'un effet : celui du catalogue s'il est réalisé, sinon la recette classique teintée de `color` (ou orange par défaut).
function ExplosionStyles.get(effectId: any, color: any): Style
	if typeof(effectId) == "string" and byEffectId[effectId] then
		return byEffectId[effectId]
	end
	if typeof(color) == "Color3" then
		return ExplosionStyles.fromColor(color)
	end
	return CLASSIC
end

-- Identifiants d'effet pour lesquels un style propre existe (tests).
function ExplosionStyles.realizedEffectIds(): { string }
	local ids: { string } = {}
	for id in byEffectId do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

ExplosionStyles.Classic = CLASSIC
ExplosionStyles.Red = RED
ExplosionStyles.Blue = BLUE
ExplosionStyles.Green = GREEN
ExplosionStyles.Yellow = YELLOW
ExplosionStyles.Ice = ICE
ExplosionStyles.Electric = ELECTRIC
ExplosionStyles.Fire = FIRE
ExplosionStyles.Rainbow = RAINBOW
ExplosionStyles.Neon = NEON
ExplosionStyles.Meteor = METEOR
ExplosionStyles.Crystal = CRYSTAL
ExplosionStyles.Heart = HEART
ExplosionStyles.Stars = STARS
ExplosionStyles.Smoke = SMOKE
ExplosionStyles.Aura = AURA
ExplosionStyles.Water = WATER
ExplosionStyles.Nature = NATURE
ExplosionStyles.Sand = SAND
ExplosionStyles.Toxic = TOXIC
ExplosionStyles.Cosmic = COSMIC
ExplosionStyles.CosmicV11 = COSMIC_V11

return table.freeze(ExplosionStyles)
