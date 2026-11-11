-- Boom Battle : verifie l'import Studio de B09 Cosmique (GENERE par un script depuis B09_Cosmique_Manifest.json, variante PC).
-- A lancer avec execute_luau, mode Edit, apres import de 05_EXPORTS_ROBLOX/BOMBES/PC/B09_Cosmique.fbx.
-- APPLY = true : applique les couleurs de diagnostic (non transferees par le FBX), configure la bombe en mode visuel
-- (ancree, sans collision) et la pose sur la case (3, 0) de Workspace.BB_BombImportTest.
local APPLY = false
local TOL = 0.06
local ANCHOR = "BombCollar_Base"

local expected = {
	BombShell_Glass = { size = Vector3.new(3.0, 3.0, 3.0), rel = Vector3.new(-0.005, -1.41, 0.0), color = "#8A5CE0", mat = "Glass", transp = 0.7 },
	BombShell_Frame = { size = Vector3.new(2.075, 2.298, 2.075), rel = Vector3.new(-0.005, -1.41, 0.0), color = "#2A1060", mat = "Metal" },
	BombGalaxy_Core = { size = Vector3.new(0.571, 0.6, 0.6), rel = Vector3.new(-0.005, -1.51, 0.0), color = "#FFF0FB", mat = "Neon" },
	BombGalaxy_Halo = { size = Vector3.new(1.046, 0.783, 0.955), rel = Vector3.new(-0.005, -1.51, 0.0), color = "#FF4FE0", mat = "Neon", transp = 0.55 },
	BombGalaxy_ArmsInner = { size = Vector3.new(1.083, 0.529, 1.082), rel = Vector3.new(0.042, -1.511, 0.02), color = "#FF5BE6", mat = "Neon" },
	BombGalaxy_ArmsMid = { size = Vector3.new(1.573, 0.763, 1.546), rel = Vector3.new(-0.01, -1.466, 0.037), color = "#D62FD1", mat = "Neon" },
	BombGalaxy_ArmsOuter = { size = Vector3.new(2.132, 1.195, 1.934), rel = Vector3.new(0.012, -1.577, 0.076), color = "#8F4BFF", mat = "Neon" },
	BombGalaxy_NebulaViolet = { size = Vector3.new(1.909, 0.697, 1.056), rel = Vector3.new(-0.038, -1.511, -0.031), color = "#6A2BD6", mat = "Neon", transp = 0.55 },
	BombGalaxy_NebulaMagenta = { size = Vector3.new(1.26, 1.197, 1.775), rel = Vector3.new(0.279, -1.535, 0.11), color = "#C32FD6", mat = "Neon", transp = 0.55 },
	BombGalaxy_Stars = { size = Vector3.new(1.876, 1.858, 1.987), rel = Vector3.new(-0.003, -1.336, 0.033), color = "#FFFFFF", mat = "Neon" },
	BombCollar_Base = { size = Vector3.new(1.113, 0.73, 1.082), rel = Vector3.new(0.0, 0.0, 0.0), color = "#3A1F7A", mat = "Metal" },
	BombCollar_Rim = { size = Vector3.new(1.085, 0.476, 1.102), rel = Vector3.new(-0.026, 0.14, 0.0), color = "#FF7AF0", mat = "Neon" },
	BombFuse_Curved = { size = Vector3.new(0.962, 0.839, 0.609), rel = Vector3.new(-0.343, 0.491, 0.132), color = "#B8803C", mat = "SmoothPlastic" },
	BombFuse_Tip = { size = Vector3.new(0.308, 0.357, 0.364), rel = Vector3.new(-0.75, 0.832, 0.308), color = "#3A2410", mat = "SmoothPlastic" },
	BombSpark_Star = { size = Vector3.new(0.428, 0.503, 0.563), rel = Vector3.new(-0.784, 0.891, 0.312), color = "#FFD6FA", mat = "Neon" },
}

local lines, allOk = {}, true
local function log(s: string) table.insert(lines, s) end

local function findModel(): Instance?
	for _, root in ipairs({ workspace, game:GetService("ReplicatedStorage") }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("MeshPart") and d.Name == ANCHOR and d.Parent and d.Parent:FindFirstChild("BombGalaxy_Stars") then
				return d.Parent
			end
		end
	end
	return nil
end

local model = findModel()
if not model then
	log("AUCUNE bombe B09 importee trouvee (cherche un groupe contenant BombGalaxy_Stars et BombCollar_Base).")
	return table.concat(lines, "\n")
end
log("Modele trouve : " .. model:GetFullName() .. " (" .. model.ClassName .. ")")

local anchor = model:FindFirstChild(ANCHOR) :: BasePart
for name, exp in pairs(expected) do
	local p = model:FindFirstChild(name) :: BasePart?
	if not p then
		log(("[ECHEC] %s : piece absente"):format(name)); allOk = false
	else
		local rel = anchor.CFrame:VectorToObjectSpace(p.Position - anchor.Position)
		local dSize, dRel = (p.Size - exp.size).Magnitude, (rel - exp.rel).Magnitude
		local ok = dSize < TOL and dRel < TOL
		allOk = allOk and ok
		log(("[%s] %-15s Size=(%.3f, %.3f, %.3f) ecart=%.3f | rel=(%.3f, %.3f, %.3f) ecart=%.3f"):format(
			ok and "OK" or "ECHEC", name, p.Size.X, p.Size.Y, p.Size.Z, dSize, rel.X, rel.Y, rel.Z, dRel))
	end
end
local cf, size = model:GetBoundingBox()
log(("Taille totale = (%.3f, %.3f, %.3f) (attendu ~ 3.000 , 4.052 , 3.000) | pivot=%s"):format(size.X, size.Y, size.Z, tostring(model:GetPivot().Position)))

if APPLY and allOk then
	for name, exp in pairs(expected) do
		local p = model:FindFirstChild(name) :: BasePart
		p.Color = Color3.fromHex(exp.color); p.Material = Enum.Material[exp.mat or "SmoothPlastic"]; p.Transparency = exp.transp or 0
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	end
	local ref = workspace:FindFirstChild("B01_Classique")
	local folder = workspace:FindFirstChild("BB_BombImportTest")
	if ref and folder then
		local b = ref:GetPivot().Position
		model.Name = "B09_Cosmique"
		model.Parent = folder
		local cellX, cellZ = b.X + (3) * 4, b.Z + (0) * 4
		local hasPlate = false
		for _, c in ipairs(folder:GetChildren()) do
			if c.Name == "Cell_4x4" and math.abs(c.Position.X - cellX) < 0.5 and math.abs(c.Position.Z - cellZ) < 0.5 then hasPlate = true break end
		end
		if not hasPlate then
			local plate = Instance.new("Part")
			plate.Name = "Cell_4x4"; plate.Anchored = true; plate.CanCollide = false
			plate.Size = Vector3.new(4, 0.2, 4); plate.Position = Vector3.new(cellX, b.Y - 0.1, cellZ)
			plate.Color = Color3.fromRGB(122, 129, 140); plate.Parent = folder
		end
		-- pied de la bombe = bas de la boite englobante ; centre X/Z = centre de la piece BombShell_Glass
		local bcf, bsz = model:GetBoundingBox()
		local band = model:FindFirstChild("BombShell_Glass") :: BasePart
		local shift = Vector3.new(cellX - band.Position.X, b.Y - (bcf.Position.Y - bsz.Y / 2), cellZ - band.Position.Z)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Position += shift end
		end
		log("Couleurs appliquees, bombe posee sur la case (3, 0).")
	end
end
log(allOk and "RESULTAT : TOUT OK" or "RESULTAT : DES ECARTS A ANALYSER")
return table.concat(lines, "\n")
