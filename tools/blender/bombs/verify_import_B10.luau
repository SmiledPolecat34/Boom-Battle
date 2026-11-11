-- Boom Battle : verifie l'import Studio de B10 ArcEnCiel (GENERE par un script depuis B10_ArcEnCiel_Manifest.json, variante PC).
-- A lancer avec execute_luau, mode Edit, apres import de 05_EXPORTS_ROBLOX/BOMBES/PC/B10_ArcEnCiel.fbx.
-- APPLY = true : applique les couleurs de diagnostic (non transferees par le FBX), configure la bombe en mode visuel
-- (ancree, sans collision) et la pose sur la case (1, 1) de Workspace.BB_BombImportTest.
local APPLY = false
local TOL = 0.06
local ANCHOR = "BombCollar_Base"

local expected = {
	BombBody_Band1 = { size = Vector3.new(2.121, 0.426, 2.121), rel = Vector3.new(-0.006, -2.631, 0.0), color = "#8E24AA", mat = "SmoothPlastic" },
	BombBody_Band2 = { size = Vector3.new(2.772, 0.472, 2.772), rel = Vector3.new(-0.006, -2.182, 0.0), color = "#1E88E5", mat = "SmoothPlastic" },
	BombBody_Band3 = { size = Vector3.new(3.0, 0.557, 3.0), rel = Vector3.new(-0.006, -1.667, 0.0), color = "#43A047", mat = "SmoothPlastic" },
	BombBody_Band4 = { size = Vector3.new(3.0, 0.557, 3.0), rel = Vector3.new(-0.006, -1.11, 0.0), color = "#FDD835", mat = "SmoothPlastic" },
	BombBody_Band5 = { size = Vector3.new(2.772, 0.472, 2.772), rel = Vector3.new(-0.006, -0.596, 0.0), color = "#FB8C00", mat = "SmoothPlastic" },
	BombBody_Band6 = { size = Vector3.new(2.121, 0.426, 2.121), rel = Vector3.new(-0.006, -0.147, 0.0), color = "#E53935", mat = "SmoothPlastic" },
	BombCollar_Base = { size = Vector3.new(1.357, 0.891, 1.32), rel = Vector3.new(0.0, 0.0, 0.0), color = "#D81B8A", mat = "SmoothPlastic" },
	BombFuse_Curved = { size = Vector3.new(1.452, 1.476, 0.87), rel = Vector3.new(-0.569, 0.814, 0.225), color = "#C8742E", mat = "SmoothPlastic" },
	BombFuse_Tip = { size = Vector3.new(0.475, 0.515, 0.537), rel = Vector3.new(-1.263, 1.408, 0.501), color = "#2A1C12", mat = "SmoothPlastic" },
}

local lines, allOk = {}, true
local function log(s: string) table.insert(lines, s) end

local function findModel(): Instance?
	for _, root in ipairs({ workspace, game:GetService("ReplicatedStorage") }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("MeshPart") and d.Name == ANCHOR and d.Parent and d.Parent:FindFirstChild("BombBody_Band1") then
				return d.Parent
			end
		end
	end
	return nil
end

local model = findModel()
if not model then
	log("AUCUNE bombe B10 importee trouvee (cherche un groupe contenant BombBody_Band1 et BombCollar_Base).")
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
log(("Taille totale = (%.3f, %.3f, %.3f) (attendu ~ 3.000 , 4.509 , 3.000) | pivot=%s"):format(size.X, size.Y, size.Z, tostring(model:GetPivot().Position)))

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
		model.Name = "B10_ArcEnCiel"
		model.Parent = folder
		local cellX, cellZ = b.X + (1) * 4, b.Z + (1) * 4
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
		-- pied de la bombe = bas de la boite englobante ; centre X/Z = centre de la piece BombBody_Band1
		local bcf, bsz = model:GetBoundingBox()
		local band = model:FindFirstChild("BombBody_Band1") :: BasePart
		local shift = Vector3.new(cellX - band.Position.X, b.Y - (bcf.Position.Y - bsz.Y / 2), cellZ - band.Position.Z)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Position += shift end
		end
		log("Couleurs appliquees, bombe posee sur la case (1, 1).")
	end
end
log(allOk and "RESULTAT : TOUT OK" or "RESULTAT : DES ECARTS A ANALYSER")
return table.concat(lines, "\n")
