--!strict
--==================================================================
-- 4) FlameArrows_SERVER  (VERSION MULTI-ZONES)
--    Emplacement : ServerScriptService  (Script normal)
--
--    Gère PLUSIEURS zones : toute Part dont le nom commence par
--    "arrowzone" (arrowzone1, arrowzone2, ...) est reconnue.
--
--    Le serveur ne fait PLUS bouger d'objet flèche (donc plus aucune
--    flèche répliquée = fin des pics de ping). Il garde seulement :
--       1. Décider QUAND tirer sur un joueur dans une zone.
--       2. La détection de touche en calcul mathématique (autoritaire).
--    Le VISUEL est géré côté client (5_FlameArrows_Client).
--==================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- ---------- CONFIG ----------
local ZONE_PREFIX = "arrowzone" -- toute Part nommée arrowzone... est une zone
local ARROW_SPEED = 70
local ARROW_INTERVAL = 0.5 -- une flèche toutes les 0.5s par joueur
local ARROW_LIFETIME = 1.5
local HIT_RADIUS = 2 -- rayon de touche (remplace le Touched des parts)
local HIT_RADIUS2 = HIT_RADIUS * HIT_RADIUS
local MAX_ARROWS = 120 -- sécurité anti-spam (plusieurs zones)
local FIRE_SCAN = 0.1 -- granularité de la boucle de tir
-- 🐢 VITESSE PAR ZONE (studs/s). Une zone absente d'ici garde ARROW_SPEED.
--    Tu peux aussi poser un attribut nombre « ArrowSpeed » sur la Part de la zone :
--    il est prioritaire et se règle en direct pendant le test.
local ZONE_SPEED: { [string]: number } = {
	arrowzone1 = 22, -- niveau 93 : flèches BEAUCOUP plus lentes (avant 70)
}

-- ---------- RemoteEvent ----------
local spawnEvent = ReplicatedStorage:FindFirstChild("SpawnFlameArrow")
if not spawnEvent then
	spawnEvent = Instance.new("RemoteEvent")
	spawnEvent.Name = "SpawnFlameArrow"
	spawnEvent.Parent = ReplicatedStorage
end

-- ---------- Zones (détection par nom) ----------
local zones: { [BasePart]: any } = {}

local function isZonePart(inst: Instance): boolean
	return inst:IsA("BasePart") and string.sub(inst.Name, 1, #ZONE_PREFIX):lower() == ZONE_PREFIX
end

local function addZone(part: Instance)
	if not isZonePart(part) or zones[part] then
		return
	end
	local bp = part :: BasePart
	zones[bp] = {
		pos = bp.Position,
		hx = bp.Size.X * 0.5,
		hy = bp.Size.Y * 0.5,
		hz = bp.Size.Z * 0.5,
		alternate = true,
		part = bp,
	}
end

local function speedOf(z): number
	local a = z.part:GetAttribute("ArrowSpeed")
	if type(a) == "number" and a > 0 then
		return math.clamp(a, 5, 300)
	end
	return ZONE_SPEED[z.part.Name] or ARROW_SPEED
end

for _, d in ipairs(Workspace:GetDescendants()) do
	addZone(d)
end
do
	local names = {}
	for bp in pairs(zones) do table.insert(names, bp.Name) end
	table.sort(names)
	print(string.format("🔥 [FlameArrows] %d zone(s) : %s", #names, table.concat(names, ", ")))
	if #names == 0 then warn("🔥 [FlameArrows] aucune Part « arrowzone… » trouvée dans le Workspace") end
end
-- Sur le serveur, pas de streaming : DescendantAdded ne fait pas de spam.
Workspace.DescendantAdded:Connect(addZone)
Workspace.DescendantRemoving:Connect(function(inst)
	if inst:IsA("BasePart") then
		zones[inst :: BasePart] = nil
	end
end)

local function inZone(z, p: Vector3): boolean
	return math.abs(p.X - z.pos.X) <= z.hx
		and math.abs(p.Y - z.pos.Y) <= z.hy
		and math.abs(p.Z - z.pos.Z) <= z.hz
end

-- ---------- Flèches actives : PURE DATA, aucun objet serveur ----------
local arrows = {}
local lastFire: { [number]: number } = {} -- [userId] = temps du dernier tir

local function fireAt(z, pos: Vector3)
	if #arrows >= MAX_ARROWS then
		return
	end

	local startZ, dirZ
	if z.alternate then
		startZ = z.pos.Z + z.hz
		dirZ = -1
	else
		startZ = z.pos.Z - z.hz
		dirZ = 1
	end
	z.alternate = not z.alternate

	local spawnTime = Workspace:GetServerTimeNow()
	local speed = speedOf(z)
	-- la flèche vit juste le temps de traverser la zone (au moins ARROW_LIFETIME)
	local life = math.max(ARROW_LIFETIME, (z.hz * 2) / speed + 0.2)
	arrows[#arrows + 1] = {
		speed = speed,
		life = life,
		x = pos.X,
		y = pos.Y,
		startZ = startZ,
		dirZ = dirZ,
		spawnTime = spawnTime,
		hit = {},
	}

	spawnEvent:FireAllClients(pos.X, pos.Y, startZ, dirZ, spawnTime, speed, life)
end

-- ---------- Boucle de TIR ----------
task.spawn(function()
	while true do
		task.wait(FIRE_SCAN)
		local now = Workspace:GetServerTimeNow()
		local players = Players:GetPlayers()
		for _, z in pairs(zones) do
			for _, plr in ipairs(players) do
				local char = plr.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChild("Humanoid")
				if hrp and hum and (hum :: Humanoid).Health > 0 and inZone(z, (hrp :: BasePart).Position) then
					local uid = plr.UserId
					if now - (lastFire[uid] or 0) >= ARROW_INTERVAL then
						lastFire[uid] = now
						fireAt(z, (hrp :: BasePart).Position)
					end
				end
			end
		end
	end
end)

-- ---------- Détection de TOUCHE + durée de vie (math pur) ----------
RunService.Heartbeat:Connect(function()
	local n = #arrows
	if n == 0 then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local players = Players:GetPlayers()

	for i = n, 1, -1 do
		local a = arrows[i]
		local elapsed = now - a.spawnTime
		if elapsed >= a.life then
			table.remove(arrows, i)
		else
			local posZ = a.startZ + a.dirZ * a.speed * elapsed
			local ax, ay = a.x, a.y
			for _, plr in ipairs(players) do
				local uid = plr.UserId
				if not a.hit[uid] then
					local char = plr.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					local hum = char and char:FindFirstChild("Humanoid")
					if hrp and hum and (hum :: Humanoid).Health > 0 then
						local p = (hrp :: BasePart).Position
						local dx, dy, dz = p.X - ax, p.Y - ay, p.Z - posZ
						if dx * dx + dy * dy + dz * dz <= HIT_RADIUS2 then
							a.hit[uid] = true
							(hum :: Humanoid).Health = 0
						end
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	lastFire[plr.UserId] = nil
end)