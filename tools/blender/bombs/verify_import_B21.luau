-- Boom Battle : verifie l'import Studio de B21 Robot (GENERE par un script depuis B21_Robot_Manifest.json, variante PC).
-- A lancer avec execute_luau, mode Edit, apres import de 05_EXPORTS_ROBLOX/BOMBES/PC/B21_Robot.fbx.
-- APPLY = true : applique les couleurs de diagnostic (non transferees par le FBX), configure la bombe en mode visuel
-- (ancree, sans collision) et la pose sur la case (-3, 1) de Workspace.BB_BombImportTest.
local APPLY = false
local TOL = 0.06
local ANCHOR = "BombCollar_Base"

local expected = {
	BombBody_Shell = { size = Vector3.new(2.969, 1.823, 3.0), rel = Vector3.new(-0.006, -0.854, 0.0), color = "#EDF2F6", mat = "SmoothPlastic" },
	BombBody_Shell2 = { size = Vector3.new(2.868, 0.267, 2.898), rel = Vector3.new(-0.006, -1.899, -0.0), color = "#D4DDE7", mat = "SmoothPlastic" },
	BombBody_Dark = { size = Vector3.new(2.654, 2.893, 2.673), rel = Vector3.new(-0.006, -1.389, 0.0), color = "#16203A", mat = "SmoothPlastic" },
	BombSkin_Dark = { size = Vector3.new(3.16, 1.223, 2.105), rel = Vector3.new(-0.006, -1.389, 0.537), color = "#1A2744", mat = "SmoothPlastic" },
	BombSkin_Glow = { size = Vector3.new(3.2, 1.775, 2.778), rel = Vector3.new(-0.006, -0.959, 0.183), color = "#2FE6FF", mat = "Neon" },
	BombSkin_Shine = { size = Vector3.new(3.23, 0.248, 1.825), rel = Vector3.new(-0.006, -1.29, 0.7), color = "#A8F3FF", mat = "Neon" },
	BombCollar_Base = { size = Vector3.new(1.357, 0.891, 1.32), rel = Vector3.new(0.0, 0.0, 0.0), color = "#243049", mat = "Metal" },
	BombFuse_Curved = { size = Vector3.new(1.403, 1.443, 0.839), rel = Vector3.new(-0.544, 0.798, 0.21), color = "#C8742E", mat = "SmoothPlastic" },
	BombFuse_Tip = { size = Vector3.new(0.51, 0.527, 0.549), rel = Vector3.new(-1.245, 1.402, 0.495), color = "#2A1C12", mat = "SmoothPlastic" },
}

local lines, allOk = {}, true
local function log(s: string) table.insert(lines, s) end

local function findModel(): Instance?
	for _, root in ipairs({ workspace, game:GetService("ReplicatedStorage") }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("MeshPart") and d.Name == ANCHOR and d.Parent and d.Parent:FindFirstChild("BombSkin_Glow") then
				return d.Parent
			end
		end
	end
	return nil
end

local model = findModel()
if not model then
	log("AUCUNE bombe B21 importee trouvee (cherche un groupe contenant BombSkin_Glow et BombCollar_Base).")
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
log(("Taille totale = (%.3f, %.3f, %.3f) (attendu ~ 3.230 , 4.500 , 3.112) | pivot=%s"):format(size.X, size.Y, size.Z, tostring(model:GetPivot().Position)))

if APPLY and allOk then
	for name, exp in pairs(expected) do
		local p = model:FindFirstChild(name) :: BasePart
		p.Color = Color3.fromHex(exp.color); p.Material = Enum.Material[exp.mat or "SmoothPlastic"]
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	end
	local ref = workspace:FindFirstChild("B01_Classique")
	local folder = workspace:FindFirstChild("BB_BombImportTest")
	if ref and folder then
		local b = ref:GetPivot().Position
		model.Name = "B21_Robot"
		model.Parent = folder
		local cellX, cellZ = b.X + (-3) * 4, b.Z + (1) * 4
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
		-- pied de la bombe = bas de la boite englobante ; centre X/Z = centre de la piece BombBody_Shell
		local bcf, bsz = model:GetBoundingBox()
		local band = model:FindFirstChild("BombBody_Shell") :: BasePart
		local shift = Vector3.new(cellX - band.Position.X, b.Y - (bcf.Position.Y - bsz.Y / 2), cellZ - band.Position.Z)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Position += shift end
		end
		log("Couleurs appliquees, bombe posee sur la case (-3, 1).")
	end
end
log(allOk and "RESULTAT : TOUT OK" or "RESULTAT : DES ECARTS A ANALYSER")
return table.concat(lines, "\n")
