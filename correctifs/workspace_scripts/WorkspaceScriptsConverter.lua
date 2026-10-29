-- ============================================================
-- WORKSPACE SCRIPTS CONVERTER (ModuleScript) — ServerStorage, nom : WorkspaceScriptsConverter
-- ============================================================
-- S'utilise depuis la BARRE DE COMMANDE de Studio (Affichage ▸ Barre de commande) :
--
--   1) TEST (ne change rien, affiche ce qui serait fait) :
--        require(game.ServerStorage.WorkspaceScriptsConverter).Run()
--   2) CONVERSION :
--        require(game.ServerStorage.WorkspaceScriptsConverter).Run(true)
--   3) RETOUR EN ARRIÈRE (remet tous les scripts comme avant) :
--        require(game.ServerStorage.WorkspaceScriptsConverter).Restore()
--
-- Ce que fait la conversion, pour chaque Script du Workspace :
--   • compare son code au code d'origine d'une famille connue (commentaires et espaces
--     ignorés). S'il est différent, même d'un caractère : le script n'est PAS touché.
--   • recopie ses réglages (délai, dégâts, forces, ID de pass…) en attributs "WSM_<Famille>_<Réglage>"
--     sur la part
--   • pose un Tag sur la part (lu par WorkspaceScriptsManager / BlinkingLightsClient)
--   • déplace le script dans ServerStorage ▸ WorkspaceScriptsBackup (rien n'est supprimé)
-- Éteint aussi dans le fichier les particules de DonationEffect2 (tes scripts de dons les
-- éteignent déjà 5 s après le démarrage du serveur : même résultat, sans les 5 premières s).
-- Tout est annulable avec Ctrl+Z (ou Restore()).
-- ============================================================
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local M = {}
local BACKUP_NAME = "WorkspaceScriptsBackup"

-- ------------------------------------------------------------
-- Normalisation : sans commentaires, espaces regroupés
-- ------------------------------------------------------------
local function normalize(s)
	s = s:gsub("\r", "")
	s = s:gsub("%-%-%[(=*)%[.-%]%1%]", "")
	s = s:gsub("%-%-[^\n]*", "")
	s = s:gsub("%s+", " ")
	s = s:gsub("^ ", "")
	s = s:gsub(" $", "")
	return s
end

-- Remplace la valeur de "local NOM = valeur" par un repère, et renvoie la valeur lue
local function extract(text, name, kind)
	local key = "local " .. name .. " = "
	local a, b = text:find(key, 1, true)
	if not a then return nil, text end
	local rest = text:sub(b + 1)
	local raw, value
	if kind == "str" then
		raw = rest:match('^"[^"]*"')
		value = raw and raw:sub(2, -2)
	else
		raw = rest:match("^%-?[%d%.]+")
		value = raw and tonumber(raw)
	end
	if not raw or value == nil then return nil, text end
	return value, text:sub(1, b) .. "@" .. name .. "@" .. rest:sub(#raw + 1)
end

local function plainRemove(text, piece)
	local out = text
	while true do
		local a, b = out:find(piece, 1, true)
		if not a then break end
		out = out:sub(1, a - 1) .. out:sub(b + 1)
		out = out:gsub("  +", " ")
	end
	return out
end

-- ------------------------------------------------------------
-- Familles : code d'ORIGINE de chaque script (recopié tel quel)
-- ------------------------------------------------------------
local FAMILIES = {
	{
		id = "DropPart", tag = "WSM_DropPart", target = "parent", class = "BasePart",
		params = {{ "disappearDelay", "DisappearDelay", "num" }},
		fixed = {},
		strip = {},
		sources = {
			[====[local part = script.Parent
local TweenService = game:GetService("TweenService")

local disappearDelay = 0.05
local respawnDelay = 3
local busy = false

-- Objets optionnels
local light = part:FindFirstChildOfClass("PointLight")
local particles = part:FindFirstChildOfClass("ParticleEmitter")

-- Sauvegarde l’état original
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
		-- Pulse (agrandissement + couleur rouge)
		createTween(TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = part.Size * 1.1,
			Color = Color3.fromRGB(255, 70, 70)
		}):Play()

		-- Lumière rouge si présente
		if light then
			light.Color = Color3.fromRGB(255, 70, 70)
			light.Brightness = 5
		end

		-- Shake stylé (rotation, pas de déplacement)
		for i = 1, 4 do
			local angle = math.rad(5)
			local axis = Vector3.new(0, 1, 0)
			local rotation = CFrame.fromAxisAngle(axis, (i % 2 == 0 and -1 or 1) * angle)
			part.CFrame = part.CFrame * rotation
			task.wait(0.05)
		end

		-- Active particules
		if particles then
			particles:Emit(20)
		end

		-- Disparition
		createTween(TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Size = part.Size * 0.2,
			Transparency = 1
		}):Play()
		part.CanCollide = false

		-- Lumière s’éteint
		if light then
			light.Brightness = 0
		end

		task.wait(respawnDelay)

		-- Reset état
		part.Size = original.Size * 0.2
		part.Color = original.Color
		part.Transparency = 1

		-- Réapparition
		createTween(TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = original.Size,
			Transparency = original.Transparency
		}):Play()
		part.CanCollide = true

		-- Lumière revient
		if light then
			light.Color = original.Color
			light.Brightness = 2
		end

		busy = false
	end)
end)

]====],
		},
	},
	{
		id = "KillBrick", tag = "WSM_KillBrick", target = "parent", class = "BasePart",
		params = {},
		fixed = {},
		strip = {},
		sources = {
			[====[script.Parent.Touched:Connect(function(part) --i use part instead of hit
	if part.Parent:FindFirstChild("Humanoid") then
		part.Parent.Humanoid.Health = 0
	end
end)]====],
			[====[script.Parent.Touched:connect(function(Hit)
	if Hit and Hit.Parent and Hit.Parent:FindFirstChild("Humanoid")then
		Hit.Parent.Humanoid.Health = 0
	end
end)
]====],
		},
	},
	{
		id = "DamageBlock", tag = "WSM_DamageBlock", target = "parent", class = "BasePart",
		params = {{ "waitTime", "WaitTime", "num" }, { "damage", "Damage", "num" }},
		fixed = {},
		strip = {},
		sources = {
			[====[local kill = script.Parent
local debounce = false
local waitTime = 1
local damage = 10 -- Edit this to modify damage to player

function onTouched(hit)
	
	if not debounce then
		debounce = true
		if hit.Parent and hit.Parent:FindFirstChild("Humanoid") then
			hit.Parent.Humanoid.Health = hit.Parent.Humanoid.Health - damage
			--print(hit.Parent.Humanoid.Health)
		end
		wait(waitTime)
		debounce = false	
	end	
end

kill.Touched:connect(onTouched)

]====],
		},
	},
	{
		id = "FadePart", tag = "WSM_FadePart", target = "parent", class = "BasePart",
		params = {},
		fixed = {},
		strip = {},
		sources = {
			[====[local block = script.Parent
db = false

function onTouch()
	if db == false then
		db = true
		for i = 1, 20 do
			block.Transparency = i/20
			wait(0.05)
		end
		block.CanCollide = false
		wait(2)
		block.CanCollide = true
		block.Transparency = 0
		db = false
	end
end

block.Touched:connect(onTouch)
]====],
		},
	},
	{
		id = "TouchPass", tag = "WSM_TouchPass", target = "parent", class = "BasePart",
		params = {{ "GAMEPASS_ID", "GamepassId", "num" }, { "REMOTE_NAME", "RemoteName", "str" }},
		fixed = {Cooldown = 0.2, CreateRemote = true},
		strip = {[====[print(player.Name .. " est assez proche pour acheter le pass.")]====]},
		sources = {
			[====[-- Script à mettre dans la Part coilbaseSpeed
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local part = script.Parent
local GAMEPASS_ID = 1889975133
local REMOTE_NAME = "FenetreachatFUSIONCOIL"

-- Assure-toi que le RemoteEvent existe
local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end

local touchedPlayers = {}

local function onTouched(other)
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

	task.delay(0.2, function()
		touchedPlayers[player] = nil
	end)
end

part.Touched:Connect(onTouched)

]====],
		},
	},
	{
		id = "TouchPassX2", tag = "WSM_TouchPass", target = "parent", class = "BasePart",
		params = {{ "GAMEPASS_ID", "GamepassId", "num" }},
		fixed = {RemoteName = "x2cointouch", Cooldown = 0.1, CreateRemote = false},
		strip = {},
		sources = {
			[====[local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local part = script.Parent
local GAMEPASS_ID = 1891007119
local remote = ReplicatedStorage:WaitForChild("x2cointouch")

local touchedPlayers = {}

local function onTouched(other)
	local player = Players:GetPlayerFromCharacter(other.Parent)
	if not player then return end

	-- Cooldown pour éviter plusieurs déclenchements
	if touchedPlayers[player] then return end
	touchedPlayers[player] = true

	if player.Character and player.Character.PrimaryPart then
		local charPos = player.Character.PrimaryPart.Position
		local partPos = part.Position
		local distance = (Vector3.new(charPos.X, partPos.Y, charPos.Z) - partPos).Magnitude

		-- Tolérance de 5 studs autour du Part
		if distance <= 5 then
			remote:FireClient(player, GAMEPASS_ID)
		end
	end

	-- Retirer le cooldown après 2 secondes
	delay(0.1, function()
		touchedPlayers[player] = nil
	end)
end

part.Touched:Connect(onTouched)]====],
		},
	},
	{
		id = "ButtonSound", tag = "WSM_ButtonSound", target = "parent", class = nil,
		params = {},
		fixed = {},
		strip = {},
		sources = {
			[====[local boutonModel = script.Parent
local triggerPart = boutonModel:WaitForChild("Greenpart")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local playSoundEvent = ReplicatedStorage:WaitForChild("PlayButtonSound") -- RemoteEvent créé dans ReplicatedStorage

local debounce = {}

triggerPart.Touched:Connect(function(hit)
	local character = hit.Parent
	local player = game.Players:GetPlayerFromCharacter(character)
	if player and not debounce[player.UserId] then
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			local distance = (humanoidRootPart.Position - triggerPart.Position).Magnitude
			if distance <= 10 then
				debounce[player.UserId] = true

				-- Envoie l'événement au joueur pour jouer le son côté client
				playSoundEvent:FireClient(player)

				wait(10)
				debounce[player.UserId] = nil
			end
		end
	end
end)]====],
		},
	},
	{
		id = "Conveyor", tag = "WSM_Conveyor", target = "parent", class = "BasePart",
		params = {},
		fixed = {},
		strip = {},
		sources = {
			[====[


script.Parent.Velocity = script.Parent.CFrame.LookVector * 50
script:Remove()]====],
			[====[-- Write your infection Lua code here


script.Parent.Velocity = script.Parent.CFrame.LookVector * 50
script:Remove()]====],
		},
	},
	{
		id = "Portal", tag = "WSM_Portal", target = "parent", class = nil,
		params = {},
		fixed = {},
		strip = {},
		sources = {
			[====[-- Script optimisé de portail téléporteur
-- Placez ce script dans le dossier parent contenant Portail1 et Portail2

local parent = script.Parent
local portail1 = parent:WaitForChild("Portail1")
local portail2 = parent:WaitForChild("Portail2")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Utiliser le RemoteEvent existant ou en créer un seul
local teleportEvent = ReplicatedStorage:FindFirstChild("TeleportEvent")
if not teleportEvent then
	teleportEvent = Instance.new("RemoteEvent")
	teleportEvent.Name = "TeleportEvent"
	teleportEvent.Parent = ReplicatedStorage
end

-- Trouver la partie principale de chaque portail
local portail1Part = portail1:IsA("BasePart") and portail1 or portail1:FindFirstChildWhichIsA("BasePart")
local portail2Part = portail2:IsA("BasePart") and portail2 or portail2:FindFirstChildWhichIsA("BasePart")

-- Vérifier que les portails existent
if not portail1Part or not portail2Part then
	warn("Erreur: Impossible de trouver les parties des portails!")
	return
end

-- OPTIMISATION : Précalculer la position cible
local targetPos = portail2Part.Position + Vector3.new(0, 5, 0)
local targetCFrame = CFrame.new(targetPos)

-- Cooldown pour éviter les téléportations multiples
local cooldowns = {}
local COOLDOWN_TIME = 2

-- OPTIMISATION : Nettoyage automatique des cooldowns
task.spawn(function()
	while true do
		task.wait(10)
		local currentTime = tick()
		for userId, temps in pairs(cooldowns) do
			if currentTime - temps > COOLDOWN_TIME + 5 then
				cooldowns[userId] = nil
			end
		end
	end
end)

local function onTouch(hit)
	-- OPTIMISATION : Vérifications rapides d'abord
	if not hit or not hit.Parent then return end

	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")

	-- Vérifier si c'est un personnage valide et vivant
	if not humanoid or humanoid.Health <= 0 then return end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end

	local player = game.Players:GetPlayerFromCharacter(character)
	if not player then return end

	-- Vérifier le cooldown
	local currentTime = tick()
	if cooldowns[player.UserId] and currentTime - cooldowns[player.UserId] < COOLDOWN_TIME then
		return
	end

	-- Activer le cooldown AVANT la téléportation
	cooldowns[player.UserId] = currentTime

	-- OPTIMISATION : Téléporter avec CFrame précalculé
	humanoidRootPart.CFrame = targetCFrame

	-- OPTIMISATION : Réinitialiser vélocité pour éviter bugs
	if humanoidRootPart:IsA("BasePart") then
		humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		humanoidRootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end

	-- Envoyer un signal au client pour jouer le son
	teleportEvent:FireClient(player)
end

-- Connecter l'événement Touched
portail1Part.Touched:Connect(onTouch)

-- Nettoyer les cooldowns
game.Players.PlayerRemoving:Connect(function(player)
	cooldowns[player.UserId] = nil
end)]====],
		},
	},
	{
		id = "Projection", tag = "WSM_Projection", target = "parent", class = "BasePart",
		params = {{ "FORCE_AVANT", "ForceAvant", "num" }, { "FORCE_HAUT", "ForceHaut", "num" }, { "COOLDOWN", "Cooldown", "num" }},
		fixed = {},
		strip = {},
		sources = {
			[====[-- Script optimisé de bloc de projection pour Roblox
-- Placez ce script dans un bloc (Part) dans Workspace

local bloc = script.Parent

-- Paramètres de projection
local FORCE_AVANT = 0   -- Force vers l'avant
local FORCE_HAUT = 100  -- Force vers le haut
local COOLDOWN = 0.3     -- Temps entre chaque utilisation (secondes)

-- Table pour suivre les cooldowns par joueur
local debounce = {}

-- Cache de la direction du bloc (calculé une fois)
local direction = bloc.CFrame.LookVector

-- OPTIMISATION : Nettoyer les anciens debounces
task.spawn(function()
	while true do
		task.wait(5)
		local maintenant = tick()
		for racine, temps in pairs(debounce) do
			if maintenant - temps > COOLDOWN + 2 then
				debounce[racine] = nil
			end
		end
	end
end)

-- Fonction de projection optimisée
local function projeter(hit)
	-- OPTIMISATION : Vérifications rapides d'abord
	if not hit or not hit.Parent then return end

	-- Chercher le humanoid et la racine
	local character = hit.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local racine = character:FindFirstChild("HumanoidRootPart")

	-- Si pas trouvé, vérifier le parent (accessoires)
	if not humanoid and character.Parent then
		character = character.Parent
		humanoid = character:FindFirstChildOfClass("Humanoid")
		racine = character:FindFirstChild("HumanoidRootPart")
	end

	if not humanoid or not racine then return end

	-- Système de cooldown optimisé
	local maintenant = tick()
	if debounce[racine] and (maintenant - debounce[racine]) < COOLDOWN then
		return
	end
	debounce[racine] = maintenant

	-- OPTIMISATION : Calculer vélocité une seule fois
	local velocite = Vector3.new(
		direction.X * FORCE_AVANT,
		FORCE_HAUT,
		direction.Z * FORCE_AVANT
	)

	-- OPTIMISATION : Réutiliser attachment si existe déjà
	local attachment = racine:FindFirstChild("ProjectionAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "ProjectionAttachment"
		attachment.Parent = racine
	end

	-- Créer LinearVelocity
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = velocite
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = racine

	-- OPTIMISATION : Nettoyer sans bloquer le script
	task.delay(0.3, function()
		if linearVelocity and linearVelocity.Parent then
			linearVelocity:Destroy()
		end
		-- Ne pas détruire l'attachment, on le réutilise
	end)
end

-- Connecter l'événement
bloc.Touched:Connect(projeter)]====],
		},
	},
	{
		id = "DancingRig", tag = "WSM_DancingRig", target = "dancingrig", class = "Model",
		params = {},
		fixed = {},
		strip = {},
		sources = {
			[====[local humanoid = script.Parent:WaitForChild("Humanoid")
local animation = script:WaitForChild("Animation")

local emote = humanoid:LoadAnimation(animation)
emote.Priority = Enum.AnimationPriority.Action
emote.Looped = false -- on laisse sur false pour que l’Event "Stopped" se déclenche

-- Fonction pour relancer l'animation automatiquement
local function playEmote()
	if emote.IsPlaying then
		emote:Stop()
	end
	emote:Play()
end

-- Quand l'animation s'arrête, on la relance
emote.Stopped:Connect(function()
	task.wait(0.1)
	playEmote()
end)

-- Lancer la première fois
playEmote()]====],
		},
	},
	{
		id = "BlinkLight", tag = "WSM_BlinkLight", target = "spotlight", class = "Light",
		params = {},
		fixed = {},
		strip = {},
		sources = {
			[====[-- By Itswibee

local light = script.Parent.Parent.SpotLight

while wait() do
	for i=1,12 do
		light.Brightness = i
		wait(0.1)
	end
	for i=11,1,-1 do
		light.Brightness = i
		wait(0.1)
	end
end
]====],
		},
	},
}

-- Modèles normalisés (calculés une fois)
for _, fam in ipairs(FAMILIES) do
	fam.templates = {}
	for _, source in ipairs(fam.sources) do
		local t = normalize(source)
		for _, piece in ipairs(fam.strip) do t = plainRemove(t, piece) end
		for _, p in ipairs(fam.params) do
			local _, replaced = extract(t, p[1], p[3])
			t = replaced
		end
		table.insert(fam.templates, t)
	end
end

-- Renvoie la famille et les réglages du script, ou nil
local function match(source)
	local base = normalize(source)
	for _, fam in ipairs(FAMILIES) do
		local t = base
		for _, piece in ipairs(fam.strip) do t = plainRemove(t, piece) end
		local values, ok = {}, true
		for _, p in ipairs(fam.params) do
			local v, replaced = extract(t, p[1], p[3])
			if v == nil then ok = false break end
			values[p[2]] = v
			t = replaced
		end
		if ok then
			for _, tpl in ipairs(fam.templates) do
				if t == tpl then return fam, values end
			end
		end
	end
	return nil
end
M._match = match       -- (utilisé pour les tests)
M._normalize = normalize

-- Objet qui recevra le Tag (là où l'ancien script agissait)
local function resolveTarget(fam, s)
	local parent = s.Parent
	if fam.target == "spotlight" then
		local holder = parent and parent.Parent
		local light = holder and holder:FindFirstChild("SpotLight")
		return light
	elseif fam.target == "dancingrig" then
		return parent
	end
	return parent
end

local function getBackup(create)
	local f = ServerStorage:FindFirstChild(BACKUP_NAME)
	if not f and create then
		f = Instance.new("Folder")
		f.Name = BACKUP_NAME
		f.Parent = ServerStorage
	end
	return f
end

function M.Run(apply)
	local recording
	if apply then
		pcall(function() recording = ChangeHistoryService:TryBeginRecording("Conversion scripts Workspace") end)
	end
	local counts, skipped, total = {}, {}, 0
	local backup = apply and getBackup(true)

	for _, s in ipairs(workspace:GetDescendants()) do
		if s.ClassName == "Script" and s.Enabled and s.RunContext ~= Enum.RunContext.Client then
			local okSrc, source = pcall(function() return s.Source end)
			local fam, values = nil, nil
			if okSrc and source then fam, values = match(source) end
			if fam then
				local target = resolveTarget(fam, s)
				local reason
				if not target then
					reason = "cible introuvable"
				elseif fam.class and not target:IsA(fam.class) then
					reason = "la cible n'est pas un " .. fam.class
				elseif target:HasTag(fam.tag) then
					reason = "cible déjà convertie (2 scripts identiques sur la même part)"
				elseif fam.id == "DancingRig" and not s:FindFirstChild("Animation") then
					reason = "Animation introuvable dans le script"
				end
				if reason then
					table.insert(skipped, s:GetFullName() .. "  →  " .. reason)
				else
					counts[fam.id] = (counts[fam.id] or 0) + 1
					total += 1
					if apply then
						for name, v in pairs(values) do target:SetAttribute(fam.tag .. "_" .. name, v) end
						for name, v in pairs(fam.fixed) do target:SetAttribute(fam.tag .. "_" .. name, v) end
						if fam.id == "DancingRig" and not target:FindFirstChild("WSM_DanceAnimation") then
							local anim = s:FindFirstChild("Animation"):Clone()
							anim.Name = "WSM_DanceAnimation"
							anim.Parent = target
						end
						target:AddTag(fam.tag)
						local link = Instance.new("ObjectValue")
						link.Name = "WSM_OriginalParent"
						link.Value = s.Parent
						link.Parent = s
						s:SetAttribute("WSM_Family", fam.id)
						s:SetAttribute("WSM_Tag", fam.tag)
						s:SetAttribute("WSM_OriginalPath", s:GetFullName())
						s.Parent = backup
					end
				end
			end
		end
	end

	-- Particules de DonationEffect2 : enregistrées éteintes (comme après le démarrage du serveur)
	local fx = workspace:FindFirstChild("DonationEffect2")
	local fxCount = 0
	if fx then
		for _, e in ipairs(fx:GetChildren()) do
			if e:IsA("ParticleEmitter") and e.Enabled then
				fxCount += 1
				if apply then
					e:SetAttribute("WSM_WasEnabled", true)
					e.Enabled = false
				end
			end
		end
	end

	if recording then
		pcall(function() ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end)
	end

	print(("===== WorkspaceScriptsConverter : %s ====="):format(apply and "CONVERSION FAITE" or "TEST (rien n'a été changé)"))
	local ids = {}
	for id in pairs(counts) do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ipairs(ids) do print(("  %-12s %4d scripts"):format(id, counts[id])) end
	print(("  TOTAL        %4d scripts %s"):format(total, apply and "convertis (rangés dans ServerStorage ▸ " .. BACKUP_NAME .. ")" or "seraient convertis"))
	print(("  DonationEffect2 : %d émetteurs de particules %s"):format(fxCount, apply and "enregistrés éteints" or "seraient enregistrés éteints"))
	if #skipped > 0 then
		print(("  %d scripts reconnus mais LAISSÉS tels quels :"):format(#skipped))
		for i = 1, math.min(#skipped, 40) do print("     " .. skipped[i]) end
	end
	if not apply then
		print("  → Pour convertir : require(game.ServerStorage.WorkspaceScriptsConverter).Run(true)")
	end
end

function M.Restore()
	local recording
	pcall(function() recording = ChangeHistoryService:TryBeginRecording("Restauration scripts Workspace") end)
	local backup = getBackup(false)
	local restored = 0
	if backup then
		for _, s in ipairs(backup:GetChildren()) do
			local link = s:FindFirstChild("WSM_OriginalParent")
			local parent = link and link.Value
			if parent and parent:IsDescendantOf(game) then
				local tag = s:GetAttribute("WSM_Tag")
				local target = parent
				if s:GetAttribute("WSM_Family") == "BlinkLight" then
					target = parent.Parent and parent.Parent:FindFirstChild("SpotLight")
				end
				if target and tag then
					target:RemoveTag(tag)
					local prefix = tag .. "_"
					for name in pairs(target:GetAttributes()) do
						if name:sub(1, #prefix) == prefix then target:SetAttribute(name, nil) end
					end
					local anim = target:FindFirstChild("WSM_DanceAnimation")
					if anim then anim:Destroy() end
				end
				link:Destroy()
				s:SetAttribute("WSM_Family", nil)
				s:SetAttribute("WSM_Tag", nil)
				s:SetAttribute("WSM_OriginalPath", nil)
				s.Parent = parent
				restored += 1
			end
		end
	end
	local fx = workspace:FindFirstChild("DonationEffect2")
	if fx then
		for _, e in ipairs(fx:GetChildren()) do
			if e:IsA("ParticleEmitter") and e:GetAttribute("WSM_WasEnabled") then
				e.Enabled = true
				e:SetAttribute("WSM_WasEnabled", nil)
			end
		end
	end
	if recording then
		pcall(function() ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end)
	end
	print(("[WorkspaceScriptsConverter] %d scripts remis à leur place d'origine."):format(restored))
end

return M
