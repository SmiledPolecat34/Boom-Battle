--!strict
-- Vie des bombes 3D, côté CLIENT : particules (mèche qui crépite + effet propre au thème), couleurs animées (pulsation, cycle
-- arc-en-ciel), clignotement avant l'explosion et animation de pose (rebond à l'arrivée, balancement qui s'accélère avec la
-- mèche, tremblement final). Purement visuel et local : le serveur ne sait rien de tout cela, le gameplay n'en dépend pas.
-- Les données viennent de BombEffectsConfig ; le temps vient du serveur (attribut BBPlacedAt) : tous les joueurs voient la
-- même mèche au même rythme. Les parties transparentes / de galaxie ne sont jamais teintées (CosmicFX gère la Cosmique).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombEffectsConfig = require(ReplicatedStorage.Shared.BombEffectsConfig)

local WHITE = Color3.new(1, 1, 1)
local TAU = math.pi * 2
local DROP_TIME = 0.3 -- chute de la pose (secondes)
local BOUNCE_TIME = 0.2 -- petit rebond qui suit
local FLASH_START = 0.65 -- part de la mèche après laquelle la bombe clignote et tremble
local FLASH_MAX = 0.65 -- intensité maximale du blanc au clignotement
local LITE_RATE = 0.5 -- réduction des débits de particules sur appareil tactile

export type Runtime = {
	update: (elapsed: number, fraction: number, now: number) -> (),
	emitterCount: () -> number,
}

local BombFx = {}

-- Décalage de pose (autour du sol de la bombe) : rebond à l'arrivée, respiration, balancement et tremblement final.
function BombFx.poseOffset(elapsed: number, fraction: number): CFrame
	local drop = 0
	if elapsed < DROP_TIME then
		local k = 1 - elapsed / DROP_TIME
		drop = 1.5 * k * k
	elseif elapsed < DROP_TIME + BOUNCE_TIME then
		drop = 0.25 * math.sin(math.pi * (elapsed - DROP_TIME) / BOUNCE_TIME)
	end
	local hz = 1.2 + 4.5 * fraction -- plus la mèche est courte, plus ça s'agite
	local bob = 0.05 * math.sin(TAU * hz * elapsed)
	local tiltZ = math.rad(1.8 + 2.5 * fraction) * math.sin(TAU * hz * 0.5 * elapsed)
	local tiltX = math.rad(1.2) * math.sin(TAU * hz * 0.37 * elapsed + 1)
	local shakeX, shakeZ = 0, 0
	if fraction > FLASH_START then
		local amplitude = 0.07 * (fraction - FLASH_START) / (1 - FLASH_START)
		shakeX = amplitude * math.noise(elapsed * 40, 1, 0) * 2
		shakeZ = amplitude * math.noise(elapsed * 40, 2, 0) * 2
	end
	return CFrame.new(shakeX, drop + bob, shakeZ) * CFrame.Angles(tiltX, 0, tiltZ)
end

-- Intensité du blanc au clignotement : 0 avant FLASH_START, puis de plus en plus rapide.
function BombFx.flashLevel(elapsed: number, fraction: number): number
	if fraction <= FLASH_START then
		return 0
	end
	local hz = 5 + 9 * (fraction - FLASH_START) / (1 - FLASH_START)
	return (0.5 + 0.5 * math.sin(TAU * hz * elapsed)) * FLASH_MAX
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function makeEmitter(parent: BasePart, name: string, preset: BombEffectsConfig.Preset, lite: boolean): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BBFx_" .. name
	emitter.Rate = preset.rate * (if lite then LITE_RATE else 1)
	emitter.Lifetime = NumberRange.new(preset.lifetime[1], preset.lifetime[2])
	emitter.Speed = NumberRange.new(preset.speed[1], preset.speed[2])
	emitter.SpreadAngle = Vector2.new(preset.spread, preset.spread)
	emitter.Acceleration = Vector3.new(preset.accel[1], preset.accel[2], preset.accel[3])
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.LightEmission = preset.light
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new(preset.size[1], preset.size[2])
	emitter.Transparency = NumberSequence.new(preset.transparency[1], preset.transparency[2])
	emitter.Color = ColorSequence.new(rgb(preset.color[1]), rgb(preset.color[2]))
	emitter.Parent = parent
	return emitter
end

local function partNamed(model: Model, name: string): BasePart?
	local part = model:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function tintable(part: BasePart): boolean
	local name = part.Name
	return part.Transparency == 0
		and not name:find("^BombGalaxy")
		and not name:find("^BombSpark")
		and not name:find("^BombShell")
		and name ~= "BombFuse_Tip" -- le bout rougeoie : sa couleur est gérée par BombFlame
end

-- Crée les émetteurs du modèle et renvoie son animateur. `lite` : appareil tactile (débits réduits, pas de fumée).
-- Ne touche à aucune pièce absente : une pièce manquante est simplement ignorée.
function BombFx.attach(model: Model, modelName: string, lite: boolean): Runtime
	local cfg: BombEffectsConfig.ModelFx = BombEffectsConfig.get(modelName) or {}
	local emitters: { ParticleEmitter } = {}
	local presets = BombEffectsConfig.Presets :: { [string]: BombEffectsConfig.Preset }

	-- Mèche qui crépite (sauf bombes qui ont leur propre étincelle).
	if cfg.fuse ~= false then
		local tip = partNamed(model, cfg.fusePiece or BombEffectsConfig.DefaultFusePiece)
		if tip then
			table.insert(emitters, makeEmitter(tip, "FuseSpark", presets.fuse_spark, lite))
			if not lite then
				table.insert(emitters, makeEmitter(tip, "FuseSmoke", presets.fuse_smoke, lite))
			end
		end
	end
	-- Effet propre au thème.
	for index, entry in cfg.emitters or {} do
		local part = partNamed(model, entry.piece)
		local preset = presets[entry.preset]
		if part and preset then
			table.insert(emitters, makeEmitter(part, "Theme" .. index, preset, lite))
		end
	end

	-- Couleurs : base de chaque pièce teintable + pulsations + cycle.
	local tint: { { part: BasePart, base: Color3 } } = {}
	local baseOf: { [BasePart]: Color3 } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and tintable(descendant) then
			table.insert(tint, { part = descendant, base = descendant.Color })
			baseOf[descendant] = descendant.Color
		end
	end
	local glows: { { parts: { BasePart }, a: Color3, b: Color3, hz: number, phase: number } } = {}
	for index, glow in cfg.glow or {} do
		local parts: { BasePart } = {}
		for _, pieceName in glow.pieces do
			local part = partNamed(model, pieceName)
			if part and baseOf[part] then
				table.insert(parts, part)
			end
		end
		if #parts > 0 then
			table.insert(glows, { parts = parts, a = rgb(glow.a), b = rgb(glow.b), hz = glow.hz, phase = index * 1.3 })
		end
	end
	local cycleParts: { BasePart } = {}
	local cyclePalette: { Color3 } = {}
	local cycleHz = 0
	if cfg.cycle then
		cycleHz = cfg.cycle.hz
		for _, pieceName in cfg.cycle.pieces do
			local part = partNamed(model, pieceName)
			if part and baseOf[part] then
				table.insert(cycleParts, part)
				table.insert(cyclePalette, baseOf[part])
			end
		end
	end
	local animated: { [BasePart]: boolean } = {} -- pièces dont la couleur bouge en permanence
	for _, glow in glows do
		for _, part in glow.parts do
			animated[part] = true
		end
	end
	for _, part in cycleParts do
		animated[part] = true
	end

	local wasFlashing = false
	local runtime: Runtime = {
		emitterCount = function()
			return #emitters
		end,
		update = function(elapsed: number, fraction: number, now: number)
			local flash = BombFx.flashLevel(elapsed, fraction)
			if next(animated) == nil and flash == 0 and not wasFlashing then
				return -- rien à recolorer (bombe sans pulsation, hors clignotement)
			end
			-- couleur animée de chaque pièce (base, pulsation ou cycle)
			local color: { [BasePart]: Color3 } = {}
			for _, glow in glows do
				local k = 0.5 + 0.5 * math.sin(TAU * glow.hz * now + glow.phase)
				local value = glow.a:Lerp(glow.b, k)
				for _, part in glow.parts do
					color[part] = value
				end
			end
			local n = #cycleParts
			if n > 0 then
				local shift = math.floor(now * cycleHz) % n
				for index, part in cycleParts do
					color[part] = cyclePalette[(index - 1 + shift) % n + 1]
				end
			end
			if flash > 0 or wasFlashing then
				-- pendant le clignotement (et une dernière fois après) toutes les pièces teintables sont réécrites
				for _, entry in tint do
					local value = color[entry.part] or entry.base
					entry.part.Color = if flash > 0 then value:Lerp(WHITE, flash) else value
				end
				wasFlashing = flash > 0
			else
				for part, value in color do
					part.Color = value
				end
			end
		end,
	}
	return runtime
end

return BombFx
