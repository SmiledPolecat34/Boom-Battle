-- Boom Battle : verifie l'import Studio de B22 Nature (GENERE par un script depuis B22_Nature_Manifest.json, variante PC).
-- A lancer avec execute_luau, mode Edit, apres import de 05_EXPORTS_ROBLOX/BOMBES/PC/B22_Nature.fbx.
-- APPLY = true : applique les couleurs de diagnostic (non transferees par le FBX), configure la bombe en mode visuel
-- (ancree, sans collision) et la pose sur la case (-3, -1) de Workspace.BB_BombImportTest.
local APPLY = false
local TOL = 0.06
local ANCHOR = "BombCollar_Base"

local expected = {
	BombBody_Wood = { size = Vector3.new(3.0, 2.91, 2.981), rel = Vector3.new(0.025, -1.479, -0.009), color = "#8A5530", mat = "Wood" },
	BombBody_Groove = { size = Vector3.new(2.985, 1.894, 2.961), rel = Vector3.new(0.03, -1.603, 0.015), color = "#47281A", mat = "SmoothPlastic" },
	BombBody_Wood2 = { size = Vector3.new(2.955, 1.763, 2.95), rel = Vector3.new(0.03, -1.61, 0.025), color = "#74462A", mat = "Wood" },
	BombSkin_LeafA = { size = Vector3.new(3.195, 2.791, 3.029), rel = Vector3.new(0.045, -1.372, 0.093), color = "#58C24D", mat = "SmoothPlastic" },
	BombSkin_LeafB = { size = Vector3.new(3.195, 2.764, 3.029), rel = Vector3.new(0.045, -1.384, 0.093), color = "#2FA043", mat = "SmoothPlastic" },
	BombSkin_Petals = { size = Vector3.new(2.169, 1.952, 3.072), rel = Vector3.new(-0.407, -1.712, -0.041), color = "#FBF8EE", mat = "SmoothPlastic" },
	BombSkin_Core = { size = Vector3.new(1.768, 1.416, 2.926), rel = Vector3.new(-0.528, -1.766, -0.118), color = "#F59A1B", mat = "SmoothPlastic" },
	BombCollar_Base = { size = Vector3.new(1.538, 1.092, 1.44), rel = Vector3.new(0.0, 0.0, 0.0), color = "#DDAB5E", mat = "Wood" },
	BombFuse_Curved = { size = Vector3.new(1.403, 1.443, 0.839), rel = Vector3.new(-0.513, 0.708, 0.21), color = "#B98A4C", mat = "SmoothPlastic" },
	BombFuse_Tip = { size = Vector3.new(0.51, 0.527, 0.549), rel = Vector3.new(-1.214, 1.311, 0.495), color = "#2A1C12", mat = "SmoothPlastic" },
}

local lines, allOk = {}, true
local function log(s: string) table.insert(lines, s) end

local function findModel(): Instance?
	for _, root in ipairs({ workspace, game:GetService("ReplicatedStorage") }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("MeshPart") and d.Name == ANCHOR and d.Parent and d.Parent:FindFirstChild("BombSkin_Core") then
				return d.Parent
			end
		end
	end
	return nil
end

local model = findModel()
if not model then
	log("AUCUNE bombe B22 importee trouvee (cherche un groupe contenant BombSkin_Core et BombCollar_Base).")
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
log(("Taille totale = (%.3f, %.3f, %.3f) (attendu ~ 3.195 , 4.509 , 3.189) | pivot=%s"):format(size.X, size.Y, size.Z, tostring(model:GetPivot().Position)))

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
		model.Name = "B22_Nature"
		model.Parent = folder
		local cellX, cellZ = b.X + (-3) * 4, b.Z + (-1) * 4
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
		-- pied de la bombe = bas de la boite englobante ; centre X/Z = centre de la piece BombBody_Wood
		local bcf, bsz = model:GetBoundingBox()
		local band = model:FindFirstChild("BombBody_Wood") :: BasePart
		local shift = Vector3.new(cellX - band.Position.X, b.Y - (bcf.Position.Y - bsz.Y / 2), cellZ - band.Position.Z)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Position += shift end
		end
		log("Couleurs appliquees, bombe posee sur la case (-3, -1).")
	end
end
log(allOk and "RESULTAT : TOUT OK" or "RESULTAT : DES ECARTS A ANALYSER")
return table.concat(lines, "\n")
