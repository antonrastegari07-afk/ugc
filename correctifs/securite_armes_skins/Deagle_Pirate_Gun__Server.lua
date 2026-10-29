local Tool = script.Parent
local Handle = Tool:WaitForChild("Handle")
local Receiver = Tool:WaitForChild("Receiver")
local Flash = Tool:WaitForChild("Flash")
local Spur = Flash:WaitForChild("Image")
local Smoke = Flash:WaitForChild("ImageTwo")
local Players = game:GetService("Players")
local DebrisService = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local IconURL = Tool.TextureId

local function TagHumanoid(humanoid, player)
	while humanoid:FindFirstChild('creator') do
		humanoid:FindFirstChild('creator'):Destroy()
	end
	local creatorTag = Instance.new("ObjectValue")
	creatorTag.Value = player
	creatorTag.Name = "creator"
	creatorTag.Parent = humanoid
	DebrisService:AddItem(creatorTag, 3)
	local weaponIconTag = Instance.new("StringValue")
	weaponIconTag.Value = IconURL
	weaponIconTag.Name = "icon"
	weaponIconTag.Parent = creatorTag
end

local function CreateBulletTracer(startPos, endPos)
	local distance = (endPos - startPos).magnitude
	local tracer = Instance.new("Part")
	tracer.Name = "BulletTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 213, 0)
	tracer.Size = Vector3.new(0.15, 0.15, distance)
	tracer.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance/2)
	tracer.Transparency = 0.3
	tracer.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.new(1, 1, 0)
	light.Brightness = 5
	light.Range = 10
	light.Parent = tracer
	DebrisService:AddItem(tracer, 0.08)
end

-- ════════════════════════════════════════════════════════════
-- 🛡️ SÉCURITÉ — même fonctionnement pour un vrai joueur
-- Avant : n'importe quel client pouvait envoyer "Damage" avec n'importe quelle cible,
-- n'importe quels dégâts (énormes ou négatifs) et n'importe quel « attaquant »,
-- même sur l'arme d'un AUTRE joueur → tuer ou soigner tout le monde à distance.
-- Il pouvait aussi spammer "CreateTracer" (des milliers de parts → lag du serveur).
-- Maintenant (mêmes règles que WeaponServer, utilisé par les armes de base) :
--   • l'arme doit appartenir à CE joueur (dans son perso ou son sac) ;
--   • les dégâts et l'attaquant sont décidés par le SERVEUR, jamais par le client ;
--   • la cible doit être à portée de l'arme ;
--   • nombre d'appels par seconde limité à la cadence de l'arme (+50 % de marge réseau).
-- ════════════════════════════════════════════════════════════
local MAX_DAMAGE  = 54        -- = Damage du script client de cette arme
local FIRE_RATE   = 1 / 4   -- = FireRate du script client
local PELLETS     = 1        -- balles par tir (12 pour le fusil à pompe)
local RANGE       = 1000      -- = Range du script client
local MAX_PER_SEC = math.max(10, math.ceil((1 / math.max(FIRE_RATE, 0.05)) * PELLETS * 1.5))

local budgets = {}
local function budgetOk(key, maxPerSec)
	local now = os.clock()
	local e = budgets[key]
	if not e or now - e.t >= 1 then
		e = { t = now, n = 0 }
		budgets[key] = e
	end
	e.n += 1
	return e.n <= maxPerSec
end

Receiver.OnServerEvent:Connect(function(player, action, ...)
	-- 🔒 l'arme doit appartenir à CE joueur (perso OU sac)
	local char = player.Character
	local bp = player:FindFirstChildOfClass("Backpack")
	if Tool.Parent ~= char and Tool.Parent ~= bp then return end

	local data = {...}
	if action == "PlaySound" then
		if not budgetOk("snd", MAX_PER_SEC + 10) then return end
		if type(data[1]) ~= "string" then return end
		local sound = Handle:FindFirstChild(data[1])
		if sound and sound:IsA("Sound") then
			sound:Play()
		end
	elseif action == "Flash" then
		if not budgetOk("fx", MAX_PER_SEC + 10) then return end
		if type(data[1]) ~= "boolean" then return end
		local flashPart = Handle:FindFirstChild("Flash")
		if flashPart then
			flashPart.Enabled = data[1]
		end
		local embers = Flash:FindFirstChild("Embers")
		if embers then
			embers.Enabled = data[1]
		end
		local spurFlash = Spur:FindFirstChild("Flash")
		local smokeFlash = Smoke:FindFirstChild("Flash")
		if spurFlash then
			spurFlash.Rotation = math.random(0, 360)
		end
		if smokeFlash then
			smokeFlash.Rotation = math.random(0, 360)
		end
		Spur.Enabled = data[1]
		if type(data[2]) == "boolean" then
			Smoke.Enabled = data[2]
		end
	elseif action == "CreateTracer" then
		if not budgetOk("tracer", MAX_PER_SEC + 10) then return end
		local startPos, endPos = data[1], data[2]
		if typeof(startPos) ~= "Vector3" or typeof(endPos) ~= "Vector3" then return end
		local length = (endPos - startPos).Magnitude
		if length ~= length or length > RANGE + 10 then return end           -- NaN ou trop long
		if (startPos - Handle.Position).Magnitude > 100 then return end      -- doit partir de l'arme
		CreateBulletTracer(startPos, endPos)
	elseif action == "Damage" then
		local targetHumanoid = data[1]
		if typeof(targetHumanoid) ~= "Instance" or not targetHumanoid:IsA("Humanoid") then return end
		if type(data[2]) ~= "number" then return end
		if not targetHumanoid:IsDescendantOf(workspace) then return end
		if not budgetOk("dmg", MAX_PER_SEC) then return end
		local attacker = player        -- 🔒 jamais la valeur envoyée par le client
		local damage = MAX_DAMAGE      -- 🔒 jamais la valeur envoyée par le client
		-- 🔒 cible à portée de l'arme
		local myRoot = char and char:FindFirstChild("HumanoidRootPart")
		local model = targetHumanoid.Parent
		local targetRoot = targetHumanoid.RootPart or (model and model:FindFirstChildWhichIsA("BasePart", true))
		if not myRoot or not targetRoot then return end
		if (targetRoot.Position - myRoot.Position).Magnitude > RANGE + 50 then return end
		local targetPlayer = Players:GetPlayerFromCharacter(model)
		if targetPlayer == attacker then return end
		if not attacker.Neutral and targetPlayer and
			targetPlayer.TeamColor == attacker.TeamColor then
			return
		end
		TagHumanoid(targetHumanoid, attacker)
		targetHumanoid:TakeDamage(damage)
		-- popup de dégâts (comme avant)
		local rootPart = model and model:FindFirstChild("HumanoidRootPart")
		if rootPart then
			Receiver:FireAllClients("ShowDamage", rootPart, damage)
		end
	end
end)
