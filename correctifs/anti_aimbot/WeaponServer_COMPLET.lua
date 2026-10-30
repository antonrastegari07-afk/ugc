-- ============================================================
-- WeaponServer  (ModuleScript)
-- Emplacement : ReplicatedStorage/WeaponSystem/WeaponServer
-- ============================================================
-- Cerveau SERVEUR commun. Chaque arme a un Script "Server" dans son
-- Tool qui fait : require(WeaponServer).Setup(script.Parent, SERVER_CONFIG)
--
-- Protocole (le client envoie via Receiver:FireServer) :
--   "PlaySound"(name)
--   "Flash"(on:bool, shotCount:number?)
--   "Tracer"(startPos, endPos)
--   "Damage"(humanoid, dmg, attacker)
--
-- Le serveur :
--   • joue les sons sur le Handle
--   • émet le flash de bouche (particules, visible par tous)
--   • gère la fumée (None | Barrel)
--   • relaie les traçantes aux joueurs qui peuvent les voir (impacts : plus relayés, locaux au tireur)
--   • applique les dégâts (vérif équipe)
--   • notifie le TUEUR ("Killed") quand sa balle tue la cible
-- ============================================================

local WeaponServer = {}

local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- event FX partagé (créé une fois) : relaie les tracers à TOUS les clients
local WeaponFX = ReplicatedStorage:FindFirstChild("WeaponFX")

if not WeaponFX then
	WeaponFX = Instance.new("RemoteEvent")
	WeaponFX.Name = "WeaponFX"
	WeaponFX.Parent = ReplicatedStorage
end

local WeaponVFX = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponVFX"))

-- 📡 TRACERS : envoyés seulement aux joueurs qui peuvent les voir (le style, une fois par destinataire)
local TRACER_RELAY_DIST = 600   -- = TracerMaxDistance du WeaponFXRelayClient
local TRACER_NEAR_LINE  = 30    -- balle qui passe à moins de 30 studs de toi → envoyée (sifflement)
local tracerStyleOf = {}        -- [tireur] = { s = style, v = version }
local tracerSeen    = {}        -- [destinataire] = { [tireur] = version reçue }
Players.PlayerRemoving:Connect(function(p)
	tracerStyleOf[p] = nil; tracerSeen[p] = nil
	for _, t in pairs(tracerSeen) do t[p] = nil end
end)
local function segDist(p, a, b)
	local ab = b - a
	local l2 = ab:Dot(ab)
	if l2 < 1e-6 then return (p - a).Magnitude end
	local t = math.clamp((p - a):Dot(ab) / l2, 0, 1)
	return (a + ab * t - p).Magnitude
end
local function tracerVisibleFor(other, start, ends)
	local ch = other.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return true end   -- pas de perso (mort / chargement) : on envoie
	local pos = root.Position
	if (pos - start).Magnitude <= TRACER_RELAY_DIST then return true end
	for i = 1, math.min(#ends, 12) do
		local e = ends[i]
		if typeof(e) == "Vector3" and segDist(pos, start, e) <= TRACER_NEAR_LINE then return true end
	end
	return false
end

-- [Combat] dégâts par zone + validation des tirs par le serveur (CombatSettings)
local CombatSettings
do
	local m = ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("CombatSettings", 5)
	CombatSettings = m and require(m) or { Enabled = false }
	if not m then warn("[CombatSystem] CombatSettings introuvable : dégâts par zone / validation coupés") end
end
local HitValidator = nil
do
	local folder = game:GetService("ServerScriptService"):WaitForChild("CombatSystem", 10)
	local mod = folder and folder:FindFirstChild("HitValidator")
	if mod then
		local ok, r = pcall(require, mod)
		if ok then HitValidator = r else warn("[CombatSystem] HitValidator : " .. tostring(r)) end
	else
		warn("[CombatSystem] ServerScriptService/CombatSystem/HitValidator introuvable : tirs non revérifiés")
	end
end
-- 🎯 AimGuard : détection d'aimbot (OBSERVE seulement : ne change rien aux tirs ni aux dégâts)
local AimGuard = nil
do
	local folder = game:GetService("ServerScriptService"):FindFirstChild("CombatSystem")
	local mod = folder and folder:FindFirstChild("AimGuard")
	if mod then
		local ok, r = pcall(require, mod)
		if ok then AimGuard = r else warn("[CombatSystem] AimGuard : " .. tostring(r)) end
	end
end
local function combatOn(section)
	local t = CombatSettings[section]
	return CombatSettings.Enabled ~= false and type(t) == "table" and t.Enabled ~= false
end
local function weaponBaseName(tool)
	local dn = tool:GetAttribute("DisplayName")
	if type(dn) == "string" and dn ~= "" then return dn end
	return tool.Name:match("^([^_]+)_") or tool.Name
end
local function listHas(list, name)
	if type(list) ~= "table" then return false end
	local base = (name:match("^([^_]+)_") or name):lower()
	for _, n in ipairs(list) do
		if type(n) == "string" and (n:lower() == base or n:lower() == name:lower()) then return true end
	end
	return false
end
local warnedNoInfo = {}

local SERVER_DEFAULTS = {
	Flash = {
		Color1 = Color3.fromRGB(255,235,170), Color2 = Color3.fromRGB(255,150,40),
		Size = 1.5, SpreadAngle = 18,
	},
	Smoke = "None",   -- "None" | "Barrel"
	-- ⚡ RÉSEAU : « MuzzleFX » n'est écouté QUE par le script de l'arme… chez son
	-- propriétaire, qui l'ignore (il a déjà ses propres effets). C'était un
	-- paquet envoyé à tout le serveur à chaque tir, pour rien. Remets true
	-- dans le SERVER_CONFIG d'une arme si un autre script l'utilise.
	RelayMuzzle = false,

	-- 🔒 LIMITES SERVEUR — À SURCHARGER PAR ARME dans le Script "Server" du Tool
	-- (copie les valeurs du CONFIG client de la même arme)
	MaxDamage    = 20,     -- = Damage client (RPG : mets Explosion.MaxDamage = 120)
	HeadshotMultiplier = 2, -- 🆕 = Headshot.Multiplier du CONFIG client (0/1 = pas de headshot)
	FireRate     = 1/10,   -- = FireRate client (secondes entre 2 tirs)
	Pellets      = 1,      -- = Pellets client (shotgun : 8, etc.)
	Range        = 1000,   -- = Range client
	MaxKnockback = 220,    -- ≥ Explosion.Knockback du RPG (150) avec marge
}

local function deepDefault(dst, src)
	dst = dst or {}
	for k, v in pairs(src) do
		if type(v) == "table" then dst[k] = deepDefault(dst[k], v)
		elseif dst[k] == nil then dst[k] = v end
	end
	return dst
end

function WeaponServer.Setup(tool, userConfig)
	local cfg = deepDefault(userConfig, SERVER_DEFAULTS)
	local Handle   = tool:WaitForChild("Handle")
	local Receiver = tool:WaitForChild("Receiver")
	local Flash    = tool:WaitForChild("Flash")
	local IconURL  = tool.TextureId
	-- [Combat] infos de l'arme pour les dégâts par zone / la validation
	local weaponName = weaponBaseName(tool)
	local isExplosive = listHas(CombatSettings.HitValidation and CombatSettings.HitValidation.ExplosiveWeapons, tool.Name)
	-- [Combat M] type de l'arme pour MuzzleFX (flash / fumée vus par les autres joueurs) ; un attribut
	-- MuzzleClass déjà posé sur le Tool (par toi dans Studio) est gardé
	if tool:GetAttribute("MuzzleClass") == nil then
		local mzm = ReplicatedStorage:WaitForChild("WeaponSystem"):FindFirstChild("MuzzleFX")
		local okM, MZ = false, nil
		if mzm then okM, MZ = pcall(require, mzm) end
		if okM and type(MZ) == "table" and MZ.Classify then
			tool:SetAttribute("MuzzleClass", MZ.Classify({ fireRate = cfg.FireRate, pellets = cfg.Pellets,
				damage = cfg.MaxDamage, rocket = isExplosive or type(cfg.Explosion) == "table" or type(cfg.Rocket) == "table" }))
		end
	end
	local function zonesOff()
		local Z = CombatSettings.ZoneDamage
		return not combatOn("ZoneDamage") or cfg.ZoneDamage == false or tool:GetAttribute("ZoneDamage") == false
			or listHas(Z and Z.DisabledWeapons, tool.Name)
	end

	-- ── particules de bouche (montées une fois) ─────────────
	local function setupMuzzleParticles()
		WeaponVFX.SetupMuzzle(Flash, 1, cfg.Flash)   -- pleine taille (vu par les autres)
	end

	local function setupBarrelSmoke()
		if Flash:FindFirstChild("BarrelSmoke") then return end
		local sm = Instance.new("ParticleEmitter"); sm.Name="BarrelSmoke"
		sm.Texture="rbxasset://textures/particles/smoke_main.dds"; sm.LightEmission=0; sm.LightInfluence=1
		sm.Color=ColorSequence.new(Color3.fromRGB(205,205,205), Color3.fromRGB(150,150,150))
		sm.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.45), NumberSequenceKeypoint.new(0.2,0.2), NumberSequenceKeypoint.new(0.7,0.35), NumberSequenceKeypoint.new(1,1)})
		sm.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.12), NumberSequenceKeypoint.new(1,0.45)})
		sm.Lifetime=NumberRange.new(1.0,1.6); sm.Rate=40; sm.Speed=NumberRange.new(0.15,0.35)
		sm.SpreadAngle=Vector2.new(1.5,1.5); sm.Acceleration=Vector3.new(0,3,0); sm.Drag=2.5
		sm.Rotation=NumberRange.new(0,360); sm.RotSpeed=NumberRange.new(-15,15)
		sm.EmissionDirection=Enum.NormalId.Top; sm.Enabled=false; sm.Parent=Flash
	end

	local function emitMuzzleFlash()
		setupMuzzleParticles()
		WeaponVFX.EmitMuzzle(Flash, true)
	end

	local barrelToken = 0
	local function emitBarrelSmoke()
		if cfg.Smoke ~= "Barrel" then return end
		setupBarrelSmoke()
		local s = Flash:FindFirstChild("BarrelSmoke"); if not s then return end
		barrelToken += 1; local my = barrelToken; s.Enabled = true
		task.delay(0.6, function() if my == barrelToken then s.Enabled = false end end)
	end

	-- ── tag + dégâts ────────────────────────────────────────
	local function tagHumanoid(hum, player)
		while hum:FindFirstChild("creator") do hum.creator:Destroy() end
		local tag = Instance.new("ObjectValue"); tag.Name="creator"; tag.Value=player; tag.Parent=hum
		Debris:AddItem(tag, 3)
		local icon = Instance.new("StringValue"); icon.Name="icon"; icon.Value=IconURL; icon.Parent=tag
	end

	-- Crée les émetteurs dès le départ (pour que le tireur puisse les masquer
	-- localement en 1re personne sans laisser passer le 1er tir au mauvais endroit).
	setupMuzzleParticles()
	if cfg.Smoke == "Barrel" then setupBarrelSmoke() end

	-- ════════════════════════════════════════════════════════
	-- 🔒 ANTI-EXPLOIT : budget d'appels par joueur / par seconde
	-- ════════════════════════════════════════════════════════
	local budgets = {}
	local function budgetOk(userId, key, maxPerSec)
		local now = os.clock()
		local b = budgets[userId]
		if not b then b = {} budgets[userId] = b end
		local e = b[key]
		if not e or now - e.t >= 1 then
			e = { t = now, n = 0 }
			b[key] = e
		end
		e.n += 1
		return e.n <= maxPerSec
	end

	-- Cadence max théorique de CETTE arme (+50% de marge réseau/lag)
	local maxHitsPerSec = math.max(10,
		math.ceil((1 / math.max(cfg.FireRate, 0.05)) * math.max(cfg.Pellets, 1) * 1.5))

	Receiver.OnServerEvent:Connect(function(player, action, ...)
		-- 🔒 L'arme doit appartenir à CE joueur (Character OU Backpack)
		-- → bloque un exploiteur qui fire le Receiver du Tool d'un AUTRE joueur
		local char = player.Character
		local bp = player:FindFirstChildOfClass("Backpack")
		if tool.Parent ~= char and tool.Parent ~= bp then return end

		local data = {...}
		if action == "PlaySound" then
			if not budgetOk(player.UserId, "snd", maxHitsPerSec + 10) then return end
			local s = Handle:FindFirstChild(data[1]); if s then s:Play() end

		elseif action == "Flash" then
			if not budgetOk(player.UserId, "fx", maxHitsPerSec + 10) then return end
			if data[1] then
				if AimGuard then pcall(AimGuard.Shot, player, weaponName, cfg) end   -- 🎯 un tir
				emitMuzzleFlash()  -- visible par les AUTRES ; le tireur les masque localement
				-- [Combat M] un tir : les autres joueurs jouent le flash + la fumée MuzzleFX sur l'arme qu'ils voient
				if CombatSettings.Enabled ~= false and type(CombatSettings.MuzzleFX) == "table" and CombatSettings.MuzzleFX.Enabled ~= false then
					tool:SetAttribute("MzShot", ((tool:GetAttribute("MzShot") or 0) + 1) % 1000000)
				end
				if cfg.RelayMuzzle then Receiver:FireAllClients("MuzzleFX", Handle.CFrame, Flash.Position, player) end
			else
				emitBarrelSmoke()
			end

		elseif action == "Tracer" then
			if not budgetOk(player.UserId, "fx", maxHitsPerSec + 10) then return end
			local start, ends = data[1], data[2]
			if typeof(start) ~= "Vector3" or type(ends) ~= "table" or #ends > 12 then return end
			-- style : le client ne l'envoie que quand il change → le serveur le garde
			local st = tracerStyleOf[player]
			if type(data[3]) == "table" then
				st = { s = data[3], v = ((st and st.v) or 0) + 1 }
				tracerStyleOf[player] = st
			end
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player and tracerVisibleFor(other, start, ends) then
					-- style envoyé une fois par destinataire (même s'il était hors de portée au changement)
					local seen = tracerSeen[other]
					if not seen then seen = {}; tracerSeen[other] = seen end
					local style = nil
					if st and seen[player] ~= st.v then style = st.s; seen[player] = st.v end
					WeaponFX:FireClient(other, "TracerV2", player, start, ends, style)
				end
			end

		elseif action == "Impact" then
			-- impacts : visibles par le TIREUR seulement → plus aucun relais (ancien client ignoré)
			return

		elseif action == "Rocket" then
			if not budgetOk(player.UserId, "rkt", 4) then return end
			if data[1] and data[2] and data[3] then
				WeaponFX:FireAllClients("Rocket", player, data[1], data[2], data[3])
			end

		elseif action == "Knockback" then
			local hrp, impulse = data[1], data[2]
			if hrp and hrp:IsA("BasePart") and typeof(impulse) == "Vector3" then
				if not budgetOk(player.UserId, "kb", 8) then return end
				-- 🛡 pas de knockback sur un joueur protégé (anti-fling au spawn)
				if hrp.Parent and hrp.Parent:GetAttribute("SpawnShielded") then return end
				-- 🔒 Clamp de la force (anti-fling du serveur entier)
				if impulse.Magnitude ~= impulse.Magnitude then return end  -- NaN check
				if impulse.Magnitude > cfg.MaxKnockback then
					impulse = impulse.Unit * cfg.MaxKnockback
				end
				-- 🔒 Portée : la cible doit être à portée du tireur
				local aRoot = char and char:FindFirstChild("HumanoidRootPart")
				if aRoot and (aRoot.Position - hrp.Position).Magnitude > cfg.Range + 100 then return end
				local owner = Players:GetPlayerFromCharacter(hrp.Parent)
				if owner then
					Receiver:FireClient(owner, "ApplyKnockback", hrp, impulse)
				end
			end

		elseif action == "Damage" then
			local hum, dmg = data[1], data[2]
			local attacker = player   -- joueur authentifié (jamais la valeur client)
			if not (hum and hum:IsA("Humanoid") and type(dmg) == "number" and attacker and attacker:IsA("Player")) then return end
			-- 🎯 headshot annoncé par le client (le clamp ci-dessous empêche l'abus)
			local isHead = (data[5] == true)
			-- 🔒 NaN / négatif / clamp au dégât max de CETTE arme (× multiplicateur si headshot)
			if dmg ~= dmg or dmg <= 0 then return end
			local cap = cfg.MaxDamage * (isHead and math.max(cfg.HeadshotMultiplier or 1, 1) or 1)
			dmg = math.min(math.floor(dmg), math.ceil(cap))
			-- 🔒 Cadence : pas plus de hits/sec que l'arme ne peut physiquement en produire
			if not budgetOk(attacker.UserId, "dmg", maxHitsPerSec) then return end
			-- 🔒 Portée : la cible doit être à portée de l'arme
			local aRoot = char and char:FindFirstChild("HumanoidRootPart")
			local tRoot = hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart")
			if aRoot and tRoot and (aRoot.Position - tRoot.Position).Magnitude > cfg.Range + 50 then return end

			-- [Combat] 🛡️ VALIDATION SERVEUR + 🎯 DÉGÂTS PAR ZONE
			-- info = { p = partie touchée, pos = point, o = canon, t = heure du tir, b = dégât de base, v = n° de rafale }
			local info = (type(data[6]) == "table") and data[6] or nil
			local zone = isHead and "head" or "torso"
			local serverDamage = false
			if combatOn("HitValidation") and HitValidator and not isExplosive and hum.Parent then
				if not info then
					if CombatSettings.HitValidation.RequireHitInfo ~= false then
						if not warnedNoInfo[weaponName] then
							warnedNoInfo[weaponName] = true
							warn(("[CombatSystem] %s : dégâts sans infos de tir refusés — WeaponController pas à jour ?"):format(weaponName))
						end
						return
					end
				else
					local ok, z = HitValidator.Validate(attacker, hum.Parent, info, cfg.Range)
					if not ok then return end
					zone = z or zone
					serverDamage = true
				end
			elseif info and typeof(info.p) == "Instance" and HitValidator and HitValidator.ZoneOf(info.p.Name) then
				zone = HitValidator.ZoneOf(info.p.Name)       -- validation coupée : zone d'après la partie touchée
				serverDamage = true
			end
			isHead = (zone == "head")
			if serverDamage then
				-- le SERVEUR calcule les dégâts : dégât de base (≤ MaxDamage) × zone
				local base = cfg.MaxDamage
				if info and type(info.b) == "number" and info.b == info.b and info.b > 0 then
					base = math.min(info.b, cfg.MaxDamage)
				end
				local mult = 1
				if isHead then
					mult = math.max(cfg.HeadshotMultiplier or 1, 1)
				elseif not zonesOff() then
					local Z = CombatSettings.ZoneDamage
					mult = (zone == "arm" and Z.Arm) or (zone == "leg" and Z.Leg) or Z.Torso or 1
				end
				dmg = math.max(1, math.floor(base * mult + 0.5))
			end

			local targetPlayer = Players:GetPlayerFromCharacter(hum.Parent)
			if targetPlayer == attacker then return end
			if not attacker.Neutral and targetPlayer and targetPlayer.TeamColor == attacker.TeamColor then return end
			-- 🛡 BOUCLIER DE SPAWN : aucun dégât ; on relaie l'impact → effet sur la bulle
			if hum.Parent:GetAttribute("SpawnShielded") then
				WeaponFX:FireAllClients("ShieldHit", hum.Parent, aRoot and aRoot.Position, attacker)
				return
			end
			-- 🎯 AimGuard : une touche VALIDÉE (stats anti-aimbot ; ne change rien aux dégâts)
			if AimGuard and serverDamage and not isExplosive then
				pcall(AimGuard.Hit, attacker, weaponName, cfg, info, zone, targetPlayer ~= nil,
					(aRoot and tRoot) and (aRoot.Position - tRoot.Position).Magnitude or 0)
			end
			local wasAlive = hum.Health > 0
			tagHumanoid(hum, attacker)
			-- [Combat] dernière touche (lue à la mort : écran de mort, killfeed, ragdoll)
			hum:SetAttribute("CombatLastHitBy", attacker.UserId)
			hum:SetAttribute("CombatLastWeapon", weaponName)
			hum:SetAttribute("CombatLastTool", tool.Name)
			hum:SetAttribute("CombatLastHead", isHead)
			hum:SetAttribute("CombatLastDist", (aRoot and tRoot) and (aRoot.Position - tRoot.Position).Magnitude or 0)
			hum:SetAttribute("CombatLastAt", os.clock())
			hum:TakeDamage(dmg)
			local rp = hum.Parent:FindFirstChild("HumanoidRootPart")
			-- (⚡ plus de "ShowDamage" envoyé à TOUS les joueurs à chaque balle : personne ne l'écoutait)
			-- [Combat] confirmation au tireur (seulement si WaitServerConfirm = true : sinon le tireur a
			-- déjà tout affiché au moment du tir)
			if info and not isExplosive and combatOn("HitValidation") and CombatSettings.HitValidation.WaitServerConfirm == true then
				Receiver:FireClient(attacker, "HitConfirm", rp, dmg, isHead, info and info.v or nil, hum.Parent, zone)
			end
			-- 🎯 feedback VICTIME : tracer garanti + indicateur directionnel (anti "phantom hit")
			if targetPlayer and rp then
				local style = (type(data[4]) == "table") and data[4] or nil
				WeaponFX:FireClient(targetPlayer, "IncomingShot", attacker, Flash.Position, rp.Position, style)
			end
			-- kill confirmé par le serveur → on prévient le tueur (marqueur de kill)
			if wasAlive and hum.Health <= 0 then
				Receiver:FireClient(attacker, "Killed")
			end
		end
	end)
end

return WeaponServer