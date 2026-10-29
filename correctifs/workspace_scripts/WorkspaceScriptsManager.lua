-- ============================================================
-- WORKSPACE SCRIPTS MANAGER (Script serveur) — ServerScriptService
-- ============================================================
-- Remplace ≈ 1 100 scripts copiés-collés du Workspace (drop parts, kill bricks, blocs de
-- dégâts, projection, fondu, achats au toucher, son de bouton, portails, danseurs,
-- tapis roulants) par UN seul script.
--
-- Le comportement est le MÊME : le code de chaque famille est recopié de ton script
-- d'origine (mêmes délais, mêmes tweens, mêmes cooldowns, mêmes RemoteEvents). Les
-- réglages qui changeaient d'un script à l'autre (délai, dégâts, forces, ID de pass…) sont
-- lus dans les attributs "WSM_<Famille>_<Réglage>" que le convertisseur a posés sur chaque part.
--
-- Les parts concernées portent un Tag (CollectionService) posé par le convertisseur.
-- Une part clonée plus tard dans le Workspace garde son Tag : elle marche aussi, comme
-- l'ancien script qui était cloné avec elle.
-- ============================================================
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- réglage posé par le convertisseur : attribut "<Tag>_<Nom>" (ex. WSM_Projection_Cooldown)
local function attr(obj, tag, name, default)
	local v = obj:GetAttribute(tag .. "_" .. name)
	if v == nil then return default end
	return v
end

local HANDLERS = {}

-- ------------------------------------------------------------
-- DROP PART (« drop part », 4 délais) — copie de l'ancien script
-- ------------------------------------------------------------
HANDLERS.WSM_DropPart = function(part)
	if not part:IsA("BasePart") then return end
	local disappearDelay = attr(part, "WSM_DropPart", "DisappearDelay", 0.05)
	local respawnDelay = 3
	local busy = false

	local light = part:FindFirstChildOfClass("PointLight")
	local particles = part:FindFirstChildOfClass("ParticleEmitter")

	local original = {
		Size = part.Size,
		Color = part.Color,
		Transparency = part.Transparency,
		CanCollide = part.CanCollide
	}

	local function createTween(info, props)
		return TweenService:Create(part, info, props)
	end

	part.Touched:Connect(function(hit)
		local hum = hit.Parent and hit.Parent:FindFirstChildWhichIsA("Humanoid")
		if not hum or busy then return end
		busy = true

		task.delay(disappearDelay, function()
			createTween(TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = part.Size * 1.1,
				Color = Color3.fromRGB(255, 70, 70)
			}):Play()

			if light then
				light.Color = Color3.fromRGB(255, 70, 70)
				light.Brightness = 5
			end

			for i = 1, 4 do
				local angle = math.rad(5)
				local axis = Vector3.new(0, 1, 0)
				local rotation = CFrame.fromAxisAngle(axis, (i % 2 == 0 and -1 or 1) * angle)
				part.CFrame = part.CFrame * rotation
				task.wait(0.05)
			end

			if particles then
				particles:Emit(20)
			end

			createTween(TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Size = part.Size * 0.2,
				Transparency = 1
			}):Play()
			part.CanCollide = false

			if light then
				light.Brightness = 0
			end

			task.wait(respawnDelay)

			part.Size = original.Size * 0.2
			part.Color = original.Color
			part.Transparency = 1

			createTween(TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = original.Size,
				Transparency = original.Transparency
			}):Play()
			part.CanCollide = true

			if light then
				light.Color = original.Color
				light.Brightness = 2
			end

			busy = false
		end)
	end)
end

-- ------------------------------------------------------------
-- KILL BRICK (« Undermapkill », « Part9 ») — tue au toucher
-- ------------------------------------------------------------
HANDLERS.WSM_KillBrick = function(part)
	if not part:IsA("BasePart") then return end
	part.Touched:Connect(function(hit)
		if hit and hit.Parent and hit.Parent:FindFirstChild("Humanoid") then
			hit.Parent.Humanoid.Health = 0
		end
	end)
end

-- ------------------------------------------------------------
-- DAMAGE BLOCK (« Damage Block.damage ») — dégâts + attente variables
-- ------------------------------------------------------------
HANDLERS.WSM_DamageBlock = function(kill)
	if not kill:IsA("BasePart") then return end
	local debounce = false
	local waitTime = attr(kill, "WSM_DamageBlock", "WaitTime", 1)
	local damage = attr(kill, "WSM_DamageBlock", "Damage", 10)

	kill.Touched:Connect(function(hit)
		if not debounce then
			debounce = true
			if hit.Parent and hit.Parent:FindFirstChild("Humanoid") then
				hit.Parent.Humanoid.Health = hit.Parent.Humanoid.Health - damage
			end
			task.wait(waitTime)
			debounce = false
		end
	end)
end

-- ------------------------------------------------------------
-- FADE PART (« Part.Script ») — devient transparente, disparaît 2 s
-- ------------------------------------------------------------
HANDLERS.WSM_FadePart = function(block)
	if not block:IsA("BasePart") then return end
	local db = false
	block.Touched:Connect(function()
		if db == false then
			db = true
			for i = 1, 20 do
				block.Transparency = i / 20
				task.wait(0.05)
			end
			block.CanCollide = false
			task.wait(2)
			block.CanCollide = true
			block.Transparency = 0
			db = false
		end
	end)
end

-- ------------------------------------------------------------
-- ACHAT AU TOUCHER (coils, x2 coins) — même RemoteEvent, même ID de pass
-- ------------------------------------------------------------
HANDLERS.WSM_TouchPass = function(part)
	if not part:IsA("BasePart") then return end
	local GAMEPASS_ID = attr(part, "WSM_TouchPass", "GamepassId", 0)
	local REMOTE_NAME = attr(part, "WSM_TouchPass", "RemoteName", "")
	local COOLDOWN = attr(part, "WSM_TouchPass", "Cooldown", 0.2)
	local createRemote = attr(part, "WSM_TouchPass", "CreateRemote", true)

	local remote
	if createRemote then
		remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = REMOTE_NAME
			remote.Parent = ReplicatedStorage
		end
	else
		remote = ReplicatedStorage:WaitForChild(REMOTE_NAME)
	end

	local touchedPlayers = {}
	part.Touched:Connect(function(other)
		local player = Players:GetPlayerFromCharacter(other.Parent)
		if not player then return end

		if touchedPlayers[player] then return end
		touchedPlayers[player] = true

		if player.Character and player.Character.PrimaryPart then
			local charPos = player.Character.PrimaryPart.Position
			local partPos = part.Position
			local distance = (Vector3.new(charPos.X, partPos.Y, charPos.Z) - partPos).Magnitude
			if distance <= 5 then
				remote:FireClient(player, GAMEPASS_ID)
			end
		end

		task.delay(COOLDOWN, function()
			touchedPlayers[player] = nil
		end)
	end)
end

-- ------------------------------------------------------------
-- SON DE BOUTON (« bouton son ») — son côté client, 10 s par joueur
-- ------------------------------------------------------------
HANDLERS.WSM_ButtonSound = function(boutonModel)
	local triggerPart = boutonModel:WaitForChild("Greenpart")
	local playSoundEvent = ReplicatedStorage:WaitForChild("PlayButtonSound")
	local debounce = {}

	triggerPart.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)
		if player and not debounce[player.UserId] then
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			if humanoidRootPart then
				local distance = (humanoidRootPart.Position - triggerPart.Position).Magnitude
				if distance <= 10 then
					debounce[player.UserId] = true
					playSoundEvent:FireClient(player)
					task.wait(10)
					debounce[player.UserId] = nil
				end
			end
		end
	end)
end

-- ------------------------------------------------------------
-- TAPIS ROULANT (« Hard obby part ») — vitesse donnée une fois au démarrage
-- ------------------------------------------------------------
HANDLERS.WSM_Conveyor = function(part)
	if not part:IsA("BasePart") then return end
	part.Velocity = part.CFrame.LookVector * 50
end

-- ------------------------------------------------------------
-- PORTAIL (« Boutonplate17.Script ») — Portail1 → au-dessus de Portail2
-- ------------------------------------------------------------
local portalCooldownTables = {}
local PORTAL_COOLDOWN_TIME = 2
local teleportEvent

HANDLERS.WSM_Portal = function(parent)
	local portail1 = parent:WaitForChild("Portail1")
	local portail2 = parent:WaitForChild("Portail2")

	if not teleportEvent then
		teleportEvent = ReplicatedStorage:FindFirstChild("TeleportEvent")
		if not teleportEvent then
			teleportEvent = Instance.new("RemoteEvent")
			teleportEvent.Name = "TeleportEvent"
			teleportEvent.Parent = ReplicatedStorage
		end
	end

	local portail1Part = portail1:IsA("BasePart") and portail1 or portail1:FindFirstChildWhichIsA("BasePart")
	local portail2Part = portail2:IsA("BasePart") and portail2 or portail2:FindFirstChildWhichIsA("BasePart")
	if not portail1Part or not portail2Part then
		warn("Erreur: Impossible de trouver les parties des portails!")
		return
	end

	local targetPos = portail2Part.Position + Vector3.new(0, 5, 0)
	local targetCFrame = CFrame.new(targetPos)
	local cooldowns = {}
	table.insert(portalCooldownTables, cooldowns)

	portail1Part.Touched:Connect(function(hit)
		if not hit or not hit.Parent then return end
		local character = hit.Parent
		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		local currentTime = tick()
		if cooldowns[player.UserId] and currentTime - cooldowns[player.UserId] < PORTAL_COOLDOWN_TIME then
			return
		end
		cooldowns[player.UserId] = currentTime

		humanoidRootPart.CFrame = targetCFrame
		if humanoidRootPart:IsA("BasePart") then
			humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			humanoidRootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		end
		teleportEvent:FireClient(player)
	end)
end

-- nettoyage des cooldowns des portails (une seule boucle pour tous, comme avant toutes les 10 s)
task.spawn(function()
	while true do
		task.wait(10)
		local currentTime = tick()
		for _, cooldowns in ipairs(portalCooldownTables) do
			for userId, temps in pairs(cooldowns) do
				if currentTime - temps > PORTAL_COOLDOWN_TIME + 5 then
					cooldowns[userId] = nil
				end
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	for _, cooldowns in ipairs(portalCooldownTables) do
		cooldowns[player.UserId] = nil
	end
end)

-- ------------------------------------------------------------
-- PROJECTION (« projection bloc », « BouncePad.LaunchScript »…) — forces variables
-- ------------------------------------------------------------
local projectionDebounceTables = {}

HANDLERS.WSM_Projection = function(bloc)
	if not bloc:IsA("BasePart") then return end
	local FORCE_AVANT = attr(bloc, "WSM_Projection", "ForceAvant", 0)
	local FORCE_HAUT = attr(bloc, "WSM_Projection", "ForceHaut", 100)
	local COOLDOWN = attr(bloc, "WSM_Projection", "Cooldown", 0.3)

	local debounce = {}
	table.insert(projectionDebounceTables, { debounce, COOLDOWN })
	local direction = bloc.CFrame.LookVector

	bloc.Touched:Connect(function(hit)
		if not hit or not hit.Parent then return end

		local character = hit.Parent
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local racine = character:FindFirstChild("HumanoidRootPart")

		if not humanoid and character.Parent then
			character = character.Parent
			humanoid = character:FindFirstChildOfClass("Humanoid")
			racine = character:FindFirstChild("HumanoidRootPart")
		end

		if not humanoid or not racine then return end

		local maintenant = tick()
		if debounce[racine] and (maintenant - debounce[racine]) < COOLDOWN then
			return
		end
		debounce[racine] = maintenant

		local velocite = Vector3.new(
			direction.X * FORCE_AVANT,
			FORCE_HAUT,
			direction.Z * FORCE_AVANT
		)

		local attachment = racine:FindFirstChild("ProjectionAttachment")
		if not attachment then
			attachment = Instance.new("Attachment")
			attachment.Name = "ProjectionAttachment"
			attachment.Parent = racine
		end

		local linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Attachment0 = attachment
		linearVelocity.MaxForce = math.huge
		linearVelocity.VectorVelocity = velocite
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.Parent = racine

		task.delay(0.3, function()
			if linearVelocity and linearVelocity.Parent then
				linearVelocity:Destroy()
			end
		end)
	end)
end

-- nettoyage des anciens debounces (une seule boucle pour tous, comme avant toutes les 5 s)
task.spawn(function()
	while true do
		task.wait(5)
		local maintenant = tick()
		for _, entry in ipairs(projectionDebounceTables) do
			local debounce, cooldown = entry[1], entry[2]
			for racine, temps in pairs(debounce) do
				if maintenant - temps > cooldown + 2 then
					debounce[racine] = nil
				end
			end
		end
	end
end)

-- ------------------------------------------------------------
-- DANSEUR (« dancing rig with message ») — rejoue la danse en boucle
-- ------------------------------------------------------------
HANDLERS.WSM_DancingRig = function(rig)
	local humanoid = rig:WaitForChild("Humanoid")
	local animation = rig:WaitForChild("WSM_DanceAnimation")

	local emote = humanoid:LoadAnimation(animation)
	emote.Priority = Enum.AnimationPriority.Action
	emote.Looped = false

	local function playEmote()
		if emote.IsPlaying then
			emote:Stop()
		end
		emote:Play()
	end

	emote.Stopped:Connect(function()
		task.wait(0.1)
		playEmote()
	end)

	playEmote()
end

-- ============================================================
-- DÉMARRAGE : une fois par objet taggé, seulement dans le Workspace
-- (l'ancien script ne tournait que dans le Workspace)
-- ============================================================
local started = setmetatable({}, { __mode = "k" })

local function setup(tag, obj)
	if started[obj] and started[obj][tag] then return end
	if not obj:IsDescendantOf(workspace) then
		-- objet taggé hors du Workspace : on attend qu'il y arrive
		local conn
		conn = obj.AncestryChanged:Connect(function()
			if obj:IsDescendantOf(workspace) then
				conn:Disconnect()
				setup(tag, obj)
			elseif not obj.Parent then
				conn:Disconnect()
			end
		end)
		return
	end
	started[obj] = started[obj] or {}
	started[obj][tag] = true
	task.spawn(function()
		local ok, err = pcall(HANDLERS[tag], obj)
		if not ok then
			warn(("[WorkspaceScriptsManager] %s sur %s : %s"):format(tag, obj:GetFullName(), tostring(err)))
		end
	end)
end

for tag in pairs(HANDLERS) do
	for _, obj in ipairs(CollectionService:GetTagged(tag)) do
		setup(tag, obj)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(obj)
		setup(tag, obj)
	end)
end
