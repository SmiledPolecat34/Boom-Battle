-- Boom Battle : verifie l'import Studio de B24 Cristal (GENERE par un script depuis B24_Cristal_Manifest.json, variante PC).
-- A lancer avec execute_luau, mode Edit, apres import de 05_EXPORTS_ROBLOX/BOMBES/PC/B24_Cristal.fbx.
-- APPLY = true : applique les couleurs de diagnostic (non transferees par le FBX), configure la bombe en mode visuel
-- (ancree, sans collision) et la pose sur la case (4, 0) de Workspace.BB_BombImportTest.
local APPLY = false
local TOL = 0.06
local ANCHOR = "BombCollar_Base"

local expected = {
	BombBody_Rock = { size = Vector3.new(2.99, 0.52, 3.147), rel = Vector3.new(-0.095, -2.511, -0.004), color = "#463070", mat = "SmoothPlastic" },
	BombBody_Deep = { size = Vector3.new(3.042, 2.525, 2.93), rel = Vector3.new(0.002, -1.242, -0.056), color = "#5E34C8", mat = "SmoothPlastic" },
	BombBody_Mid = { size = Vector3.new(3.033, 2.422, 2.932), rel = Vector3.new(-0.008, -1.19, -0.04), color = "#A06CFF", mat = "SmoothPlastic" },
	BombBody_Light = { size = Vector3.new(3.047, 2.553, 2.946), rel = Vector3.new(-0.001, -1.228, -0.048), color = "#CDB0FF", mat = "Neon" },
	BombCollar_Base = { size = Vector3.new(0.831, 0.635, 0.8), rel = Vector3.new(0.0, 0.0, 0.0), color = "#2E1C5E", mat = "SmoothPlastic" },
	BombFuse_Curved = { size = Vector3.new(1.453, 1.483, 0.86), rel = Vector3.new(-0.576, 0.9, 0.23), color = "#C8742E", mat = "SmoothPlastic" },
	BombFuse_Tip = { size = Vector3.new(0.489, 0.535, 0.543), rel = Vector3.new(-1.268, 1.49, 0.5), color = "#2A1C12", mat = "SmoothPlastic" },
}

local lines, allOk = {}, true
local function log(s: string) table.insert(lines, s) end

local function findModel(): Instance?
	for _, root in ipairs({ workspace, game:GetService("ReplicatedStorage") }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("MeshPart") and d.Name == ANCHOR and d.Parent and d.Parent:FindFirstChild("BombBody_Rock") then
				return d.Parent
			end
		end
	end
	return nil
end

local model = findModel()
if not model then
	log("AUCUNE bombe B24 importee trouvee (cherche un groupe contenant BombBody_Rock et BombCollar_Base).")
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
log(("Taille totale = (%.3f, %.3f, %.3f) (attendu ~ 3.112 , 4.529 , 3.147) | pivot=%s"):format(size.X, size.Y, size.Z, tostring(model:GetPivot().Position)))

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
		model.Name = "B24_Cristal"
		model.Parent = folder
		local cellX, cellZ = b.X + (4) * 4, b.Z + (0) * 4
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
		-- pied de la bombe = bas de la boite englobante ; centre X/Z = centre de la piece BombBody_Rock
		local bcf, bsz = model:GetBoundingBox()
		local band = model:FindFirstChild("BombBody_Rock") :: BasePart
		local shift = Vector3.new(cellX - band.Position.X, b.Y - (bcf.Position.Y - bsz.Y / 2), cellZ - band.Position.Z)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Position += shift end
		end
		log("Couleurs appliquees, bombe posee sur la case (4, 0).")
	end
end
log(allOk and "RESULTAT : TOUT OK" or "RESULTAT : DES ECARTS A ANALYSER")
return table.concat(lines, "\n")
