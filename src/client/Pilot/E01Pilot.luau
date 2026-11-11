--!nocheck
-- PILOTE Phase 5 (TEMPORAIRE, non branché sur le jeu) : rejoue E01 v2 conçue dans Blender, avec les VRAIS maillages importés (FBX)
-- rangés dans ReplicatedStorage.E01Meshes (51 MeshParts, importés à l'échelle ×100 : on les remet à l'échelle 0,01).
-- L'animation est celle de Blender échantillonnée à 24 i/s (Shared.Pilot.E01PilotData, généré par tools/blender/explosions/e01_export_luau.py).
-- Purement visuel : ne décide d'aucune case dangereuse.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Data = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Pilot"):WaitForChild("E01PilotData"))
local E01Pilot = {}

local CELL = 4
local IMPORT_SCALE = 0.01 -- FBX importé en centimètres : 1 stud Blender = 100 studs importés
local function c3(r, g, b) return Color3.fromRGB(r, g, b) end
local MAT = {
	R = { c3(255, 59, 10), Enum.Material.Neon, 0 },
	O = { c3(255, 138, 0), Enum.Material.Neon, 0 },
	Y = { c3(255, 209, 26), Enum.Material.Neon, 0 },
	W = { c3(255, 243, 184), Enum.Material.Neon, 0 },
	CORE = { c3(255, 255, 255), Enum.Material.Neon, 0 },
	GLOW = { c3(255, 176, 32), Enum.Material.Neon, 0.45 },
	SMOKE = { c3(228, 207, 176), Enum.Material.SmoothPlastic, 0 },
	SMOKE_EDGE = { c3(226, 86, 27), Enum.Material.Neon, 0 },
	SPARK = { c3(255, 200, 58), Enum.Material.Neon, 0 },
	ROCK_A = { c3(205, 187, 160), Enum.Material.SmoothPlastic, 0 },
	ROCK_B = { c3(91, 70, 55), Enum.Material.SmoothPlastic, 0 },
}

E01Pilot.stats = { parts = 0, lastBuildMs = 0, missing = 0 }

local templates = {}
local function getTemplate(meshName)
	local t = templates[meshName]
	if t == nil then
		local key = meshName:gsub("^SEGMENT_E_", "SEG1_E_")
		local src = ReplicatedStorage:WaitForChild("E01Meshes"):FindFirstChild("M_E01_" .. key)
		if src then
			t = { part = src, size = src.Size * IMPORT_SCALE, off = -src.PivotOffset.Position * IMPORT_SCALE } -- off : centre de la boîte par rapport à l'origine Blender (rotation du pivot = identité)
		else
			t = false
			E01Pilot.stats.missing += 1
			warn("[E01Pilot] maillage introuvable : " .. key)
		end
		templates[meshName] = t
	end
	return t
end

local function instantiate(folder, pieceName, pieceCF, delay, out)
	for _, o in Data.pieces[pieceName].objs do
		local tpl = getTemplate(o.mesh)
		if tpl then
			local m = MAT[o.mat]
			local p = tpl.part:Clone()
			p.Color, p.Material = m[1], m[2]
			p.Transparency = 1
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			p.Name = o.name
			p.Parent = folder
			E01Pilot.stats.parts += 1
			table.insert(out, { part = p, tpl = tpl, f = o.f, cf = pieceCF, delay = delay, baseT = m[3], hidden = true })
		end
	end
end

local function setHidden(e, hide)
	if e.hidden ~= hide then
		e.hidden = hide
		e.part.Transparency = hide and 1 or e.baseT
	end
end

local function sampleCF(f, i)
	local b = (i - 1) * 8
	return CFrame.new(f[b + 1], f[b + 2], f[b + 3], f[b + 5], f[b + 6], f[b + 7], f[b + 8]), f[b + 4]
end

local function apply(e, lf)
	local n = Data.frames
	if lf < 1 or lf > n then
		setHidden(e, true)
		return
	end
	local i0 = math.floor(lf)
	local a = lf - i0
	local i1 = math.min(i0 + 1, n)
	local cf0, s0 = sampleCF(e.f, i0)
	local cf1, s1 = sampleCF(e.f, i1)
	local s = s0 + (s1 - s0) * a
	if s < 0.02 then
		setHidden(e, true)
		return
	end
	local originCF = e.cf * cf0:Lerp(cf1, a) -- position/rotation de l'ORIGINE du maillage (= repère de l'objet dans Blender)
	local part = e.part
	part.Size = (e.tpl.size * s):Max(Vector3.new(0.002, 0.002, 0.002))
	part.CFrame = originCF * CFrame.new(e.tpl.off * s) -- le MeshPart est positionné par le centre de sa boîte, pas par l'origine
	setHidden(e, false)
end

local DIRS = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }

local function buildCross(centerPos, range)
	local t0 = os.clock()
	local folder = Instance.new("Folder")
	folder.Name = "BBE01Pilot"
	local elems = {}
	instantiate(folder, "CENTER", CFrame.new(centerPos), 0, elems)
	for _, dir in DIRS do
		for k = 1, range do
			local cellPos = centerPos + dir * CELL * k
			local cf = CFrame.fromMatrix(cellPos, -dir, Vector3.yAxis)
			instantiate(folder, k < range and "SEGMENT" or "END", cf, k, elems)
		end
	end
	folder.Parent = workspace
	E01Pilot.stats.lastBuildMs = (os.clock() - t0) * 1000
	return folder, elems
end

local active = {}
local conn = nil

local function step()
	local now = os.clock()
	for i = #active, 1, -1 do
		local fx = active[i]
		local gf = (now - fx.start) * Data.fps * fx.speed + 1
		if gf > Data.frames + fx.maxDelay + 1 then
			fx.folder:Destroy()
			table.remove(active, i)
		else
			for _, e in fx.elems do
				apply(e, gf - e.delay)
			end
		end
	end
	if #active == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

-- Joue l'animation (temps réel ; speed < 1 = ralenti de contrôle).
function E01Pilot.play(centerPos, range, speed)
	local folder, elems = buildCross(centerPos, range or 2)
	table.insert(active, { folder = folder, elems = elems, start = os.clock(), speed = speed or 1, maxDelay = range or 2 })
	if not conn then
		conn = RunService.Heartbeat:Connect(step)
	end
	return folder
end

-- Image figée (captures reproductibles) : frame = image globale de Blender (1..15), délai de propagation inclus.
function E01Pilot.showFrame(centerPos, range, frame)
	local folder, elems = buildCross(centerPos, range or 2)
	for _, e in elems do
		apply(e, frame - e.delay)
	end
	return folder
end

function E01Pilot.clear()
	for _, fx in active do
		fx.folder:Destroy()
	end
	table.clear(active)
	if conn then
		conn:Disconnect()
		conn = nil
	end
	local f = workspace:FindFirstChild("BBE01Pilot")
	while f do
		f:Destroy()
		f = workspace:FindFirstChild("BBE01Pilot")
	end
end

_G.E01Pilot = E01Pilot
return E01Pilot
