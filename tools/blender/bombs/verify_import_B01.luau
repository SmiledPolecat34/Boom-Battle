-- Boom Battle : verifie l'import Studio de B01 Classique (a lancer avec execute_luau, mode Edit).
-- Valeurs attendues = 05_EXPORTS_ROBLOX/BOMBES/B01_Classique_Manifest.json (variante PC).
-- PLACE = true : pose une copie sur une case de 4x4 studs (dossier Workspace.BB_BombImportTest, supprimable).
local PLACE = false
local TOL = 0.06

local expected = {
	BombBody_Base   = { size = Vector3.new(3, 2.91, 3),         rel = Vector3.new(0, 0, 0) },
	BombCollar_Base = { size = Vector3.new(1.357, 0.891, 1.32), rel = Vector3.new(0.006, 1.389, 0) },
	BombFuse_Curved = { size = Vector3.new(1.452, 1.476, 0.87), rel = Vector3.new(-0.563, 2.203, 0.225) },
	BombFuse_Tip    = { size = Vector3.new(0.475, 0.515, 0.537), rel = Vector3.new(-1.257, 2.796, 0.501) },
}

local function findPart(root: Instance, key: string): BasePart?
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("MeshPart") and string.find(d.Name, key, 1, true) then
			return d
		end
	end
	return nil
end

local lines, allOk = {}, true
local function log(s: string) table.insert(lines, s) end

local found: { [string]: BasePart } = {}
for _, root in ipairs({ workspace, game:GetService("ReplicatedStorage") }) do
	local body = findPart(root, "BombBody_Base")
	if body and body.Parent and not string.find(body.Parent:GetFullName(), "BoomBattle_BOMBS", 1, true) then
		for key in pairs(expected) do
			found[key] = findPart(body.Parent, key) :: BasePart
		end
		log("Modele trouve : " .. body.Parent:GetFullName() .. " (" .. body.Parent.ClassName .. ")")
		break
	end
end

if not found.BombBody_Base then
	log("AUCUNE bombe importee trouvee (cherche des MeshPart nommes BombBody_Base hors BoomBattle_BOMBS).")
	return table.concat(lines, "\n")
end

local body = found.BombBody_Base
for key, exp in pairs(expected) do
	local p = found[key]
	if not p then
		log(("[ECHEC] %s : piece absente"):format(key)); allOk = false
	else
		local rel = body.CFrame:VectorToObjectSpace(p.Position - body.Position)
		local dSize = (p.Size - exp.size).Magnitude
		local dRel = (rel - exp.rel).Magnitude
		local ok = dSize < TOL and dRel < TOL
		allOk = allOk and ok
		log(("[%s] %-16s Size=(%.3f, %.3f, %.3f) ecart=%.3f | rel=(%.3f, %.3f, %.3f) ecart=%.3f | Anchored=%s CanCollide=%s Material=%s TextureID=%s"):format(
			ok and "OK" or "ECHEC", key, p.Size.X, p.Size.Y, p.Size.Z, dSize, rel.X, rel.Y, rel.Z, dRel,
			tostring(p.Anchored), tostring(p.CanCollide), p.Material.Name, p.TextureID ~= "" and "oui" or "non"))
	end
end
log(("Rotation du corps (0,0,0 attendu) : %s"):format(tostring(body.Orientation)))

if PLACE and allOk then
	local old = workspace:FindFirstChild("BB_BombImportTest")
	if old then old:Destroy() end
	local folder = Instance.new("Folder"); folder.Name = "BB_BombImportTest"
	for gx = -1, 1 do
		for gz = -1, 1 do
			local plate = Instance.new("Part")
			plate.Anchored = true; plate.Size = Vector3.new(4, 0.2, 4)
			plate.Position = Vector3.new(gx * 4, 0.1, gz * 4)
			plate.Color = ((gx + gz) % 2 == 0) and Color3.fromRGB(140, 147, 158) or Color3.fromRGB(122, 129, 140)
			plate.Name = "Cell"; plate.Parent = folder
		end
	end
	local copy = body.Parent:Clone()
	copy.Parent = folder
	local cbody = findPart(copy, "BombBody_Base") :: BasePart
	local bottom = cbody.Position.Y - cbody.Size.Y / 2
	local shift = Vector3.new(-cbody.Position.X, 0.2 - bottom, -cbody.Position.Z)
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") then d.Position += shift; d.Anchored = true end
	end
	folder.Parent = workspace
	log("Bombe posee sur la case centrale (BB_BombImportTest).")
end

log(allOk and "RESULTAT : TOUT OK" or "RESULTAT : DES ECARTS A ANALYSER")
return table.concat(lines, "\n")
