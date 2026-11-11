-- Boom Battle : verifie l'import Studio de B16 Ninja (GENERE par un script depuis B16_Ninja_Manifest.json, variante PC).
-- A lancer avec execute_luau, mode Edit, apres import de 05_EXPORTS_ROBLOX/BOMBES/PC/B16_Ninja.fbx.
-- APPLY = true : applique les couleurs de diagnostic (non transferees par le FBX), configure la bombe en mode visuel
-- (ancree, sans collision) et la pose sur la case (2, 0) de Workspace.BB_BombImportTest.
local APPLY = false
local TOL = 0.06
local ANCHOR = "BombCollar_Base"

local expected = {
	BombBody_Black = { size = Vector3.new(3.157, 3.007, 1.0), rel = Vector3.new(-0.006, -0.689, 0.0), color = "#2B2F3B", mat = "SmoothPlastic" },
	BombBody_Edge = { size = Vector3.new(3.359, 3.199, 1.32), rel = Vector3.new(-0.006, -0.684, -0.0), color = "#D4D9E3", mat = "Metal" },
	BombBody_Plateau = { size = Vector3.new(2.351, 2.239, 1.0), rel = Vector3.new(-0.006, -0.708, 0.0), color = "#D8262A", mat = "SmoothPlastic" },
	BombCollar_Base = { size = Vector3.new(1.357, 0.891, 1.32), rel = Vector3.new(0.0, 0.0, 0.0), color = "#3A3F4A", mat = "SmoothPlastic" },
	BombFuse_Curved = { size = Vector3.new(1.452, 1.476, 0.87), rel = Vector3.new(-0.569, 0.814, 0.225), color = "#C8742E", mat = "SmoothPlastic" },
	BombFuse_Tip = { size = Vector3.new(0.475, 0.515, 0.537), rel = Vector3.new(-1.263, 1.408, 0.501), color = "#2A1C12", mat = "SmoothPlastic" },
}

local lines, allOk = {}, true
local function log(s: string) table.insert(lines, s) end

local function findModel(): Instance?
	for _, root in ipairs({ workspace, game:GetService("ReplicatedStorage") }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("MeshPart") and d.Name == ANCHOR and d.Parent and d.Parent:FindFirstChild("BombBody_Plateau") then
				return d.Parent
			end
		end
	end
	return nil
end

local model = findModel()
if not model then
	log("AUCUNE bombe B16 importee trouvee (cherche un groupe contenant BombBody_Plateau et BombCollar_Base).")
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
log(("Taille totale = (%.3f, %.3f, %.3f) (attendu ~ 3.359 , 3.948 , 1.429) | pivot=%s"):format(size.X, size.Y, size.Z, tostring(model:GetPivot().Position)))

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
		model.Name = "B16_Ninja"
		model.Parent = folder
		local cellX, cellZ = b.X + (2) * 4, b.Z + (0) * 4
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
		-- pied de la bombe = bas de la boite englobante ; centre X/Z = centre de la piece BombBody_Edge
		local bcf, bsz = model:GetBoundingBox()
		local band = model:FindFirstChild("BombBody_Edge") :: BasePart
		local shift = Vector3.new(cellX - band.Position.X, b.Y - (bcf.Position.Y - bsz.Y / 2), cellZ - band.Position.Z)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Position += shift end
		end
		log("Couleurs appliquees, bombe posee sur la case (2, 0).")
	end
end
log(allOk and "RESULTAT : TOUT OK" or "RESULTAT : DES ECARTS A ANALYSER")
return table.concat(lines, "\n")
