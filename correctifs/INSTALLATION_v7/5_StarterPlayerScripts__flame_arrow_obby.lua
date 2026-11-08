--!strict
--==================================================================
-- 5) FlameArrows_CLIENT
--    Emplacement : StarterPlayer > StarterPlayerScripts  (LocalScript)
--
--    Affiche les flèches en LOCAL (elles ne sont jamais répliquées) et
--    joue le son. Le mouvement est calculé avec le temps serveur
--    (spawnTime) -> la flèche est au bon endroit même avec du ping,
--    et cohérente avec la détection de touche côté serveur.
--==================================================================

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local ARROW_SPEED = 70
local ARROW_LIFETIME = 1.5

local arrowModel = ReplicatedStorage:WaitForChild("flamearrow", 30)
if not arrowModel then
	warn("🔥 [FlameArrows] « flamearrow » introuvable dans ReplicatedStorage : les flèches ne s'afficheront pas")
	arrowModel = ReplicatedStorage:WaitForChild("flamearrow")
end
local spawnEvent = ReplicatedStorage:WaitForChild("SpawnFlameArrow")

-- Son optionnel : mets un objet Sound nommé "ArrowSound" dans
-- ReplicatedStorage si tu veux un son à chaque flèche.
local soundTemplate = ReplicatedStorage:FindFirstChild("ArrowSound")

-- Dossier LOCAL (créé sur le client => non répliqué)
-- 🔥 KeepFX : la flèche n'est faite QUE d'effets (Beams + particules). Le mode
--    performance (Settings ▸ particules) ne doit jamais les couper : flèche invisible = mort injuste.
local folder: Folder? = nil
local function getFolder(): Folder
	if not folder or folder.Parent ~= Workspace then
		folder = Instance.new("Folder")
		folder.Name = "LocalArrows"
		folder:SetAttribute("KeepFX", true)
		folder.Parent = Workspace
	end
	return folder :: Folder
end
getFolder()

local active: { [Model]: any } = {}

spawnEvent.OnClientEvent:Connect(function(x, y, startZ, dirZ, spawnTime, speed, life)
	local arrow = arrowModel:Clone()
	local spawnPos = Vector3.new(x, y, startZ)
	local dir = Vector3.new(0, 0, dirZ)
	local rot = CFrame.lookAt(Vector3.zero, dir) -- orientation seule

	arrow:PivotTo(CFrame.new(spawnPos) * rot)
	arrow.Parent = getFolder()
	-- au cas où un effet aurait été désactivé dans le modèle source
	for _, d in ipairs(arrow:GetDescendants()) do
		if d:IsA("Beam") or d:IsA("ParticleEmitter") then d.Enabled = true end
	end

	active[arrow] = {
		x = x,
		y = y,
		startZ = startZ,
		dirZ = dirZ,
		spawnTime = spawnTime,
		rot = rot,
		-- 🐢 vitesse et durée envoyées par le serveur (zone par zone)
		speed = (type(speed) == "number" and speed > 0) and speed or ARROW_SPEED,
		life = (type(life) == "number" and life > 0) and life or ARROW_LIFETIME,
	}

	if soundTemplate and soundTemplate:IsA("Sound") then
		local part = arrow.PrimaryPart or arrow:FindFirstChildWhichIsA("BasePart")
		if part then
			local s = soundTemplate:Clone()
			s.Parent = part
			s:Play()
			Debris:AddItem(s, 3)
		end
	end
end)

RunService.Heartbeat:Connect(function()
	local now = Workspace:GetServerTimeNow()
	for arrow, a in pairs(active) do
		if arrow.Parent then
			local elapsed = now - a.spawnTime
			if elapsed >= a.life then
				arrow:Destroy()
				active[arrow] = nil
			else
				local posZ = a.startZ + a.dirZ * a.speed * elapsed
				arrow:PivotTo(CFrame.new(a.x, a.y, posZ) * a.rot)
			end
		else
			active[arrow] = nil
		end
	end
end)