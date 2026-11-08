-- ============================================================
-- WeaponVFX  (ModuleScript)
-- Emplacement : ReplicatedStorage/WeaponSystem/WeaponVFX
-- ============================================================
-- Tous les gros effets visuels des armes, centralisés :
--   • Impacts de balles riches (flash, onde, débris, poussière,
--     étincelles, trou de balle qui s'estompe)
--   • Flash de bouche amélioré (cœur + onde + étincelles + braises),
--     avec échelle réduite en 1re personne (confort)
--   • Marqueur de KILL fluide (onde + icône avec pop élastique)
--   • Interrupteur GLOBAL des tracers (toutes armes d'un coup)
-- Requis par WeaponController (client) ET WeaponServer (serveur).
-- Un seul local ajouté côté controller → limite des 200 respectée.
-- ============================================================
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")


local VFX = {}

-- ════════ CONFIG GLOBALE (édite ICI pour toutes les armes) ════════
VFX.Config = {
	Tracers = true,        -- ⬅ INTERRUPTEUR GLOBAL des tracers (false = aucune arme)
	-- ── IMPACTS (performance) ──
	ImpactsEnabled = true, -- ⬅ INTERRUPTEUR GLOBAL des impacts (false = aucun, perf max)
	ImpactScale = 1,       -- taille globale des impacts de balles
	BulletHoles = true,    -- trous de balle sur les surfaces
	BulletHoleImage = "rbxassetid://119573050092063",  -- ← TON image d'impact SANS fond (rbxassetid://...)
	BulletHoleSize = 0.6,  -- taille de l'impact (studs, × ImpactScale)
	BulletHoleLife = 6,    -- durée avant fondu (s)
	BulletHoleCoolTime = 1.5,                            -- vitesse du refroidissement (chaud → normal)
	BulletHoleHotColor  = Color3.fromRGB(255, 54, 21),  -- teinte CHAUDE au départ
	BulletHoleCoolColor = Color3.fromRGB(255, 255, 255), -- teinte finale (255,255,255 = image normale)
	MuzzleFPScale = 0.55,  -- × taille du flash de bouche en 1re PERSONNE (confort)
	MuzzleFPSmoke = false, -- fumée de bouche en 1re personne (false = jamais)
	StarFlash = true,      -- ⬅ éclat en ÉTOILE néon (style Rivals). false = ancien flash particules
	StarFlashScale = 1,    -- ⬅ taille GLOBALE du flare (baisse à 0.7 / 0.5 si trop gros)
	-- 💡 LUMIÈRES
	MuzzleLights = true,   -- au CANON de TES tirs (lumière de bouche + éclat étoile) : vue par TOI seulement
	ImpactLights = false,  -- à l'ARRIVÉE de la balle (flash d'impact + lueur du trou) : personne
	TracerLights = false,  -- au BOUT de la balle en vol (tête du tracer) : personne
	MobileAutoMuzzleLight = false, -- 📱 armes AUTO sur mobile : pas de lumière de bouche (true = la garder)

	-- 🥔 MODE POTATO : actif quand le joueur a SettingPerfMode = true.
	-- Coupe tout ce qui est lourd sur les armes, pour le CPU ET le réseau.
	-- Chez les autres joueurs (sans perf mode), rien ne change.
	--   Enabled = false → le mode performance ne touche plus aux effets d'arme.
	--   Keep.X = true   → on GARDE cet effet même en potato.
	Potato = {
		Enabled = true,
		Keep = {
			Shells = false,          -- douilles (les tiennes et celles des autres)
			MuzzleLight = false,     -- lumière de bouche
			MuzzleParticles = false, -- particules de bouche (feu, étincelles, fumée)
			StarFlash = false,       -- éclat néon en étoile au canon
			Impacts = false,         -- impacts de balles (poussière, débris, trou, étincelles)
			SendImpacts = false,     -- tu n'envoies plus tes impacts au serveur (moins de réseau)
			OthersImpacts = false,   -- le serveur ne t'envoie plus les impacts des autres
			OthersTracers = false,   -- traînées des balles des AUTRES joueurs
			RivalsTracers = false,   -- ta traînée passe en « Classic » (1 part, sans lumière)
		},
	},
}
-- 🥔 le joueur plr est-il en potato pour cet effet ? (utilisable côté serveur)
function VFX.PotatoFor(plr, key)
	local P = VFX.Config.Potato
	if not P or P.Enabled == false then return false end
	if not (plr and plr:GetAttribute("SettingPerfMode") == true) then return false end
	if key == nil then return true end
	return not (P.Keep and P.Keep[key] == true)
end
-- 🥔 côté client : le joueur LOCAL est-il en potato pour cet effet ?
function VFX.Potato(key)
	if not RunService:IsClient() then return false end
	return VFX.PotatoFor(Players.LocalPlayer, key)
end
-- Toggle LIVE possible sans éditer : workspace:SetAttribute("WeaponTracers", false)
function VFX.TracersEnabled()
	local a = workspace:GetAttribute("WeaponTracers")
	if a ~= nil then return a == true end
	return VFX.Config.Tracers
end
-- 📱 client mobile (écran tactile sans clavier)
local UIS = game:GetService("UserInputService")
function VFX.IsMobile()
	return RunService:IsClient() and UIS.TouchEnabled and not UIS.KeyboardEnabled
end

-- ════════ IMPACTS DE BALLES ════════
local IMPACT_TINT = {
	[Enum.Material.Concrete]=Color3.fromRGB(150,148,143),[Enum.Material.Brick]=Color3.fromRGB(150,95,72),
	[Enum.Material.Cobblestone]=Color3.fromRGB(140,135,128),[Enum.Material.Rock]=Color3.fromRGB(125,122,118),
	[Enum.Material.Slate]=Color3.fromRGB(105,108,112),[Enum.Material.Wood]=Color3.fromRGB(135,95,55),
	[Enum.Material.WoodPlanks]=Color3.fromRGB(150,110,68),[Enum.Material.Metal]=Color3.fromRGB(180,182,190),
	[Enum.Material.DiamondPlate]=Color3.fromRGB(170,172,180),[Enum.Material.CorrodedMetal]=Color3.fromRGB(150,120,95),
	[Enum.Material.Grass]=Color3.fromRGB(95,128,58),[Enum.Material.LeafyGrass]=Color3.fromRGB(90,120,55),
	[Enum.Material.Ground]=Color3.fromRGB(120,98,70),[Enum.Material.Mud]=Color3.fromRGB(95,75,55),
	[Enum.Material.Sand]=Color3.fromRGB(205,190,148),[Enum.Material.Sandstone]=Color3.fromRGB(200,178,135),
	[Enum.Material.Snow]=Color3.fromRGB(235,240,248),[Enum.Material.Glass]=Color3.fromRGB(200,225,235),
}
local METALLIC = {
	[Enum.Material.Metal]=true,[Enum.Material.DiamondPlate]=true,
	[Enum.Material.CorrodedMetal]=true,[Enum.Material.Foil]=true,
}

-- trou de balle (image collée sur la surface)
--   full = true  (PC)     : teinte chaude → normale, 2 faces, lueur (si ImpactLights), puis fondu
--   full = false (mobile) : 16 trous RÉUTILISÉS (aucune part créée par balle), image normale, AUCUN fondu :
--                           visible 3 s puis disparaît d'un coup (ou quand son emplacement est réutilisé)
local function bulletHole(pos, normal, K, full)
	if not VFX.Config.BulletHoles then return end
	local img = VFX.Config.BulletHoleImage
	if not img or img == "" then return end
	local sz = (VFX.Config.BulletHoleSize or 0.6) * K
	if not full then
		local P = VFX._holes or { i = 0 }
		VFX._holes = P
		P.i = P.i % 16 + 1
		local h = P[P.i]
		if not (h and h.part.Parent) then
			local part = Instance.new("Part")
			part.Name = "BulletHole"; part.Anchored = true; part.CanCollide = false; part.CanQuery = false
			part.CanTouch = false; part.CastShadow = false; part.Transparency = 1
			local d = Instance.new("Decal"); d.Face = Enum.NormalId.Front; d.Parent = part
			part.Parent = workspace
			h = { part = part, decal = d }
			P[P.i] = h
		end
		h.tok = (h.tok or 0) + 1
		local tok = h.tok
		h.part.Size = Vector3.new(sz, sz, 0.05)
		h.part.CFrame = CFrame.lookAt(pos + normal*0.02, pos + normal*2) * CFrame.Angles(0, 0, math.random()*6.283)
		h.decal.Texture = img
		h.decal.Color3 = VFX.Config.BulletHoleCoolColor or Color3.new(1, 1, 1)   -- pas de teinte rouge sur mobile
		h.decal.Transparency = 0
		task.delay(math.min(VFX.Config.BulletHoleLife or 6, 3), function()
			if h.tok == tok and h.decal.Parent then h.decal.Transparency = 1 end   -- pas de fondu sur mobile
		end)
		return
	end
	local host = Instance.new("Part")
	host.Anchored=true; host.CanCollide=false; host.CanQuery=false; host.CanTouch=false
	host.CastShadow=false; host.Transparency=1
	host.Size = Vector3.new(sz, sz, 0.05)
	host.CFrame = CFrame.lookAt(pos + normal*0.02, pos + normal*2)
		* CFrame.Angles(0, 0, math.random()*6.283)
	host.Parent = workspace
	local hotCol  = VFX.Config.BulletHoleHotColor  or Color3.fromRGB(255, 130, 60)
	local coolCol = VFX.Config.BulletHoleCoolColor or Color3.new(1, 1, 1)
	local coolT = VFX.Config.BulletHoleCoolTime or 0.6
	local life = VFX.Config.BulletHoleLife or 6
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local d = Instance.new("Decal")
		d.Texture = img; d.Face = face; d.Color3 = hotCol; d.Parent = host
		-- refroidissement : la TEINTE de l'image passe de chaud → normal
		TweenService:Create(d, TweenInfo.new(coolT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Color3 = coolCol }):Play()
		-- fondu lent (reste net puis s'estompe)
		TweenService:Create(d, TweenInfo.new(life*0.4, Enum.EasingStyle.Quad,
			Enum.EasingDirection.In, 0, false, life*0.6), { Transparency = 1 }):Play()
	end
	if VFX.Config.ImpactLights ~= false then
		-- lueur chaude BRÈVE : juste de la lumière (aucune part/rond visible)
		local hotLight = Instance.new("PointLight")
		hotLight.Color = Color3.fromRGB(255, 110, 40)
		hotLight.Brightness = 3; hotLight.Range = 5*K; hotLight.Parent = host
		TweenService:Create(hotLight, TweenInfo.new(0.6), { Brightness = 0 }):Play()
	end
	Debris:AddItem(host, life + 0.1)
end

-- pos, normal, material, cfgImpact = table cfg.FX.Impact de l'arme
-- Appelé seulement pour TES balles (les impacts ne sont plus relayés aux autres joueurs).
-- 📱 MOBILE : seulement l'image d'impact (pas de flash, onde, poussière, débris, étincelles, lumière ni son)
function VFX.Impact(pos, normal, material, cfgImpact)
	if not VFX.Config.ImpactsEnabled then return end   -- interrupteur global (perf)
	if VFX.Potato("Impacts") then return end            -- 🥔
	if not cfgImpact or not cfgImpact.Enabled or not pos then return end
	local K = VFX.Config.ImpactScale
	normal = (normal and normal.Magnitude > 0.01) and normal.Unit or Vector3.yAxis
	if VFX.IsMobile() then
		bulletHole(pos, normal, K, false)
		return
	end
	local dust = IMPACT_TINT[material] or Color3.fromRGB(150,148,143)
	local metal = METALLIC[material]
	-- repère : +Y = hors de la surface
	local ref = (math.abs(normal.Z) < 0.99) and Vector3.zAxis or Vector3.xAxis
	local right = normal:Cross(ref).Unit
	local look = right:Cross(normal).Unit
	local cf = CFrame.fromMatrix(pos, right, normal, -look)

	-- host particules
	local host = Instance.new("Part")
	host.Anchored=true; host.CanCollide=false; host.CanQuery=false; host.CanTouch=false
	host.Transparency=1; host.Size=Vector3.new(0.1,0.1,0.1); host.CFrame=cf; host.Parent=workspace
	local att = Instance.new("Attachment"); att.Parent=host

	-- 1) FLASH d'impact (cœur lumineux bref → l'impact SE VOIT)
	local fl = Instance.new("ParticleEmitter"); fl.Parent=att
	fl.Texture="rbxasset://textures/particles/fire_main.dds"; fl.LightEmission=1; fl.LightInfluence=0
	fl.Color=ColorSequence.new(Color3.fromRGB(255,240,200), Color3.fromRGB(255,170,80))
	fl.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.05), NumberSequenceKeypoint.new(1,1)})
	fl.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.7*K), NumberSequenceKeypoint.new(1,0.1)})
	fl.Lifetime=NumberRange.new(0.05,0.09); fl.Speed=NumberRange.new(0,1)
	fl.EmissionDirection=Enum.NormalId.Top; fl.Rate=0; fl:Emit(2)

	-- 2) ONDE DE CHOC : disque néon plaqué sur la surface qui s'étale
	local ring = Instance.new("Part")
	ring.Shape=Enum.PartType.Cylinder; ring.Material=Enum.Material.Neon
	ring.Color=Color3.fromRGB(255,235,190):Lerp(dust, 0.35)
	ring.Transparency=0.35
	ring.Anchored=true; ring.CanCollide=false; ring.CanQuery=false; ring.CanTouch=false
	ring.Size=Vector3.new(0.05, 0.25*K, 0.25*K)
	ring.CFrame = CFrame.new(pos + normal*0.03, pos + normal) * CFrame.Angles(0, math.rad(90), 0)
	ring.Parent=workspace
	TweenService:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size=Vector3.new(0.05, 2.1*K, 2.1*K), Transparency=1 }):Play()
	Debris:AddItem(ring, 0.25)

	-- 3) POUSSIÈRE dense (bien visible)
	local d = Instance.new("ParticleEmitter"); d.Parent=att
	d.Texture="rbxasset://textures/particles/smoke_main.dds"; d.LightInfluence=1
	d.Color=ColorSequence.new(dust)
	d.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.25), NumberSequenceKeypoint.new(1,1)})
	d.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.35*K), NumberSequenceKeypoint.new(1,1.4*K)})
	d.Lifetime=NumberRange.new(0.35,0.6); d.Speed=NumberRange.new(4,9)
	d.SpreadAngle=Vector2.new(40,40); d.Acceleration=Vector3.new(0,-3,0)
	d.Rotation=NumberRange.new(0,360); d.RotSpeed=NumberRange.new(-70,70)
	d.EmissionDirection=Enum.NormalId.Top; d.Rate=0; d:Emit(6)

	-- 4) DÉBRIS PHYSIQUES : petits morceaux qui giclent (le "travaillé")
	for _ = 1, 4 do
		local deb = Instance.new("Part")
		local s = (0.1 + math.random()*0.12)*K
		deb.Size = Vector3.new(s, s, s*1.6)
		deb.Color = dust:Lerp(Color3.new(0,0,0), 0.15)
		deb.Material = Enum.Material.SmoothPlastic
		deb.CanCollide=false; deb.CanQuery=false; deb.CanTouch=false; deb.CastShadow=false
		deb.CFrame = CFrame.new(pos + normal*0.1) * CFrame.Angles(math.random()*6, math.random()*6, 0)
		local tang = right*(math.random()-0.5) + look*(math.random()-0.5)
		deb.AssemblyLinearVelocity = (normal*(10+math.random()*12) + tang*10)
		deb.AssemblyAngularVelocity = Vector3.new(math.random(-25,25), math.random(-25,25), math.random(-25,25))
		deb.Parent=workspace
		TweenService:Create(deb, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency=1 }):Play()
		Debris:AddItem(deb, 0.5)
	end

	-- 5) ÉTINCELLES (généreuses sur métal)
	local n = metal and math.random(8,12) or math.random(3,5)
	local sp = Instance.new("ParticleEmitter"); sp.Parent=att
	sp.Texture="rbxasset://textures/particles/sparkles_main.dds"; sp.LightEmission=1; sp.LightInfluence=0
	sp.Color=ColorSequence.new(Color3.fromRGB(255,230,150), Color3.fromRGB(255,140,40))
	sp.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1)})
	sp.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.16*K), NumberSequenceKeypoint.new(1,0.02)})
	sp.Lifetime=NumberRange.new(0.15,0.4); sp.Speed=NumberRange.new(16,30)
	sp.SpreadAngle=Vector2.new(45,45); sp.Acceleration=Vector3.new(0,-80,0)
	sp.EmissionDirection=Enum.NormalId.Top; sp.Rate=0; sp:Emit(n)

	-- lumière d'impact
	if VFX.Config.ImpactLights ~= false then
		local li = Instance.new("PointLight")
		li.Color=Color3.fromRGB(255,205,130); li.Brightness=3; li.Range=6*K; li.Parent=host
		Debris:AddItem(li, 0.07)
	end

	-- 6) IMPACT : image collée sur le mur (teinte chaude puis refroidie)
	bulletHole(pos, normal, K, true)

	-- son d'impact (optionnel)
	local template = cfgImpact.Sound and SoundService:FindFirstChild(cfgImpact.Sound)
	if template and template:IsA("Sound") then
		local s=template:Clone(); s.PlaybackSpeed=0.9+math.random()*0.2; s.Parent=host; s:Play()
	end
	Debris:AddItem(host, 0.8)
end

-- ════════ FLASH DE BOUCHE ════════
-- Monte les émetteurs sur une part Flash (client viewmodel OU serveur).
-- scale : 1 = plein (3e pers / autres joueurs) ; MuzzleFPScale = 1re pers.
function VFX.SetupMuzzle(flash, scale, palette)
	if flash:FindFirstChild("MFlash") then return end
	scale = scale or 1
	local c1 = (palette and palette.Color1) or Color3.fromRGB(255,235,170)
	local c2 = (palette and palette.Color2) or Color3.fromRGB(255,150,40)
	-- cœur : flamme brillante, courte
	local f=Instance.new("ParticleEmitter"); f.Name="MFlash"
	f.Texture="rbxasset://textures/particles/fire_main.dds"; f.LightEmission=1; f.LightInfluence=0
	f.Color=ColorSequence.new(c1, c2)
	f.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.05), NumberSequenceKeypoint.new(1,1)})
	f.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.35*scale), NumberSequenceKeypoint.new(0.4,0.7*scale), NumberSequenceKeypoint.new(1,0.1)})
	f.Lifetime=NumberRange.new(0.03,0.07); f.Speed=NumberRange.new(2,5)
	f.SpreadAngle=Vector2.new(14,14); f.Rotation=NumberRange.new(0,360)
	f.Rate=0; f.Enabled=false; f.Parent=flash
	-- onde : bouffée ronde très brève → donne du "punch"
	local r=Instance.new("ParticleEmitter"); r.Name="MRing"
	r.Texture="rbxasset://textures/particles/smoke_main.dds"; r.LightEmission=0.85; r.LightInfluence=0
	r.Color=ColorSequence.new(c1)
	r.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.45), NumberSequenceKeypoint.new(1,1)})
	r.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.35*scale), NumberSequenceKeypoint.new(1,1.7*scale)})
	r.Lifetime=NumberRange.new(0.08,0.12); r.Speed=NumberRange.new(0,1)
	r.Rotation=NumberRange.new(0,360); r.RotSpeed=NumberRange.new(-40,40)
	r.Rate=0; r.Enabled=false; r.Parent=flash
	-- étincelles : traits rapides vers l'avant
	local s=Instance.new("ParticleEmitter"); s.Name="MSparks"
	s.Texture="rbxasset://textures/particles/sparkles_main.dds"; s.LightEmission=1; s.LightInfluence=0
	s.Color=ColorSequence.new(Color3.fromRGB(255,225,140), c2)
	s.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.1), NumberSequenceKeypoint.new(1,1)})
	s.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.16*scale), NumberSequenceKeypoint.new(1,0.02)})
	s.Lifetime=NumberRange.new(0.08,0.18); s.Speed=NumberRange.new(14,26)
	s.SpreadAngle=Vector2.new(9,9); s.Acceleration=Vector3.new(0,-30,0)
	s.Rate=0; s.Enabled=false; s.Parent=flash
	-- braises : 1-2 points chauds qui retombent
	local e=Instance.new("ParticleEmitter"); e.Name="MEmber"
	e.Texture="rbxasset://textures/particles/sparkles_main.dds"; e.LightEmission=1; e.LightInfluence=0
	e.Color=ColorSequence.new(c2)
	e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.2), NumberSequenceKeypoint.new(1,1)})
	e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.09*scale), NumberSequenceKeypoint.new(1,0.01)})
	e.Lifetime=NumberRange.new(0.3,0.55); e.Speed=NumberRange.new(3,7)
	e.SpreadAngle=Vector2.new(30,30); e.Acceleration=Vector3.new(0,-40,0)
	e.Rate=0; e.Enabled=false; e.Parent=flash
	-- fumée fine
	local sm=Instance.new("ParticleEmitter"); sm.Name="MSmoke"
	sm.Texture="rbxasset://textures/particles/smoke_main.dds"; sm.LightInfluence=1
	sm.Color=ColorSequence.new(Color3.fromRGB(160,160,160), Color3.fromRGB(110,110,110))
	sm.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.55), NumberSequenceKeypoint.new(1,1)})
	sm.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.3*scale), NumberSequenceKeypoint.new(1,1.2*scale)})
	sm.Lifetime=NumberRange.new(0.4,0.8); sm.Speed=NumberRange.new(1,2)
	sm.SpreadAngle=Vector2.new(10,10); sm.Acceleration=Vector3.new(0,2,0)
	sm.Rotation=NumberRange.new(0,360); sm.RotSpeed=NumberRange.new(-25,25)
	sm.Rate=0; sm.Enabled=false; sm.Parent=flash
end
function VFX.EmitMuzzle(flash, withSmoke)
	if VFX.Potato("MuzzleParticles") then return end    -- 🥔
	-- en mode étoile, l'éclat de bouche est fait par VFX.StarFlash (néon net) :
	-- on ne joue plus les particules de FEU (MFlash/MRing), on garde étincelles/braises/fumée
	if not VFX.Config.StarFlash then
		local f=flash:FindFirstChild("MFlash"); if f then f:Emit(4) end
		local r=flash:FindFirstChild("MRing");  if r then r:Emit(1) end
	end
	local s=flash:FindFirstChild("MSparks");if s then s:Emit(math.random(4,7)) end
	local e=flash:FindFirstChild("MEmber"); if e then e:Emit(2) end
	if withSmoke then
		local sm=flash:FindFirstChild("MSmoke"); if sm then sm:Emit(2) end
	end
end

-- ════════ MUZZLE STAR FLASH (flare néon, collé au canon, face caméra) ════════
-- anchor = le PART Flash (suit le canon, aucun décalage) OU un Vector3 (statique,
-- pour les autres joueurs). palette = {Color1=cœur, Color2=orange}. scale = taille.
function VFX.StarFlash(anchor, palette, scale)
	if not VFX.Config.StarFlash or not anchor then return end
	if VFX.Potato("StarFlash") then return end          -- 🥔
	local isPart = typeof(anchor) == "Instance" and anchor:IsA("BasePart")
	if not isPart and typeof(anchor) ~= "Vector3" then return end
	scale = (scale or 1) * (VFX.Config.StarFlashScale or 1)
	local cam = workspace.CurrentCamera
	local coreCol  = (palette and palette.Color1) or Color3.fromRGB(255, 246, 176)  -- #FFF6B0
	local outerCol = (palette and palette.Color2) or Color3.fromRGB(255, 122, 0)    -- #FF7A00
	local rollAngle = math.random() * math.pi * 2

	local star = Instance.new("Model"); star.Name = "MuzzleStar"; star.Parent = workspace
	local specs = {}
	local corePart

	local function element(sizeVec, off, color, baseT)
		local p = Instance.new("Part")
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false
		p.Material=Enum.Material.Neon; p.Color=color; p.Size=Vector3.one; p.Transparency=baseT; p.Parent=star
		local m = Instance.new("SpecialMesh"); m.MeshType=Enum.MeshType.Sphere; m.Parent=p
		specs[#specs+1] = { p=p, m=m, base=sizeVec, off=off, baseT=baseT }
		return p
	end

	-- glow doux + cœur brillant (PETITS)
	element(Vector3.one * 0.95 * scale, CFrame.new(), outerCol, 0.6)
	corePart = element(Vector3.one * 0.34 * scale, CFrame.new(), coreCol, 0)
	-- rayons FINS et effilés (croix nette + diagonales discrètes)
	element(Vector3.new(1.35*scale, 0.075*scale, 0.05*scale), CFrame.Angles(0,0,0),             coreCol,  0.05)
	element(Vector3.new(1.10*scale, 0.075*scale, 0.05*scale), CFrame.Angles(0,0,math.rad(90)),  coreCol,  0.05)
	element(Vector3.new(0.70*scale, 0.05*scale,  0.04*scale), CFrame.Angles(0,0,math.rad(45)),  outerCol, 0.35)
	element(Vector3.new(0.70*scale, 0.05*scale,  0.04*scale), CFrame.Angles(0,0,math.rad(135)), outerCol, 0.35)

	-- HALO particulaire doux (sprite étoile) → la vraie douceur d'un flare, billboard auto
	local att = Instance.new("Attachment"); att.Parent = corePart
	local halo = Instance.new("ParticleEmitter")
	halo.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	halo.LightEmission = 1; halo.LightInfluence = 0
	halo.Color = ColorSequence.new(coreCol, outerCol)
	halo.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	halo.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4*scale), NumberSequenceKeypoint.new(1, 0.5*scale) })
	halo.Lifetime = NumberRange.new(0.07, 0.09); halo.Rate = 0
	halo.Speed = NumberRange.new(0); halo.Rotation = NumberRange.new(0, 360)
	halo.Parent = att; halo:Emit(1)

	local light = nil
	if VFX.Config.MuzzleLights ~= false then
		light = Instance.new("PointLight")
		light.Color = outerCol; light.Range = 7 * scale; light.Brightness = 5; light.Parent = corePart
	end

	local dur = 0.07
	local t0 = os.clock()
	local name = "MuzzleStar_" .. tostring(math.random(1, 1e9))
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 3, function()
		local t = (os.clock() - t0) / dur
		local pos
		if isPart then
			if not anchor.Parent then RunService:UnbindFromRenderStep(name); star:Destroy(); return end
			pos = anchor.Position
		else pos = anchor end
		local camPos = (cam and cam.CFrame.Position) or (pos + Vector3.new(0,0,1))
		local base = CFrame.lookAt(pos, camPos) * CFrame.Angles(0, 0, rollAngle)
		local pop  = math.clamp(t / 0.25, 0, 1); pop = 1 - (1 - pop) * (1 - pop)
		local fade = math.clamp((t - 0.2) / 0.8, 0, 1)
		for _, s in ipairs(specs) do
			s.p.CFrame = base * s.off
			s.m.Scale  = s.base * (0.3 + 0.7 * pop)
			s.p.Transparency = s.baseT + (1 - s.baseT) * fade
		end
		if light then light.Brightness = 5 * (1 - fade) end
		if t >= 1 then RunService:UnbindFromRenderStep(name); star:Destroy() end
	end)
	Debris:AddItem(star, 0.25)
end

-- ════════ MARQUEUR DE KILL (fluide) ════════
-- pg = PlayerGui ; pos = Vector2 (coords viewport) ; KM = cfg.FX.KillMarker
function VFX.KillMarker(pg, pos, KM)
	local gui = pg:FindFirstChild("KillFXGui")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name="KillFXGui"; gui.ResetOnSpawn=true
		gui.IgnoreGuiInset=true; gui.DisplayOrder=9; gui.Parent=pg
	end
	local S, col = KM.Size, KM.Color
	local root = Instance.new("Frame")
	root.BackgroundTransparency=1; root.AnchorPoint=Vector2.new(0.5,0.5)
	root.Position=UDim2.fromOffset(pos.X, pos.Y + (KM.BelowCursor or 0))
	root.Size=UDim2.fromOffset(S, S); root.Parent=gui

	local function circle(size, strokeCol, strokeT, thick)
		local fr=Instance.new("Frame"); fr.AnchorPoint=Vector2.new(0.5,0.5)
		fr.Position=UDim2.new(0.5,0,0.5,0); fr.Size=UDim2.fromOffset(size,size)
		fr.BackgroundTransparency=1; fr.Parent=root
		local cc=Instance.new("UICorner"); cc.CornerRadius=UDim.new(1,0); cc.Parent=fr
		local st=Instance.new("UIStroke"); st.Color=strokeCol; st.Thickness=thick
		st.Transparency=strokeT; st.Parent=fr
		return fr, st
	end
	-- 1) lueur douce qui s'étale
	local glow=Instance.new("Frame"); glow.AnchorPoint=Vector2.new(0.5,0.5)
	glow.Position=UDim2.new(0.5,0,0.5,0); glow.Size=UDim2.fromOffset(S*0.5,S*0.5)
	glow.BackgroundColor3=col; glow.BackgroundTransparency=0.45; glow.BorderSizePixel=0; glow.Parent=root
	local gc=Instance.new("UICorner"); gc.CornerRadius=UDim.new(1,0); gc.Parent=glow
	TweenService:Create(glow, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size=UDim2.fromOffset(S*2.2,S*2.2), BackgroundTransparency=1 }):Play()
	-- 2) double onde
	local r1, s1 = circle(S*0.8, col, 0.1, 3)
	TweenService:Create(r1, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size=UDim2.fromOffset(S*2.6,S*2.6) }):Play()
	TweenService:Create(s1, TweenInfo.new(0.35), { Transparency=1 }):Play()
	task.delay(0.07, function()
		local r2, s2 = circle(S*0.55, Color3.new(1,1,1), 0.25, 2)
		TweenService:Create(r2, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size=UDim2.fromOffset(S*1.9,S*1.9) }):Play()
		TweenService:Create(s2, TweenInfo.new(0.3), { Transparency=1 }):Play()
	end)
	-- 3) icône : pop élastique + rotation qui se pose (aucun jitter)
	local icon=Instance.new("ImageLabel"); icon.Name="KillIcon"
	icon.AnchorPoint=Vector2.new(0.5,0.5); icon.Position=UDim2.new(0.5,0,0.5,0)
	icon.Size=UDim2.fromOffset(0,0); icon.Rotation=-14
	icon.BackgroundTransparency=1; icon.Image=KM.Image; icon.ScaleType=Enum.ScaleType.Fit
	icon.ImageColor3 = KM.TintImage and col or Color3.new(1,1,1)
	icon.ImageTransparency=0.15; icon.Parent=root
	TweenService:Create(icon, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size=UDim2.fromOffset(S,S), Rotation=0, ImageTransparency=0 }):Play()
	-- 4) hold → sortie douce (fondu + légère montée)
	task.delay(KM.Hold or 1, function()
		if not icon.Parent then return end
		TweenService:Create(icon, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ ImageTransparency=1, Position=UDim2.new(0.5,0,0.5,-10),
				Size=UDim2.fromOffset(S*1.05,S*1.05) }):Play()
	end)
	Debris:AddItem(root, (KM.Hold or 1) + 0.4)
end

-- ════════ MARQUEUR DE HEADSHOT (curseur) ════════
-- pg = PlayerGui ; pos = Vector2 (coords viewport) ; M = cfg.Headshot.Marker
function VFX.HeadshotMarker(pg, pos, M)
	if not M or M.Enabled == false or not pg or not pos then return end
	local gui = pg:FindFirstChild("HeadshotFXGui")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "HeadshotFXGui"; gui.ResetOnSpawn = true
		gui.IgnoreGuiInset = true; gui.DisplayOrder = 9; gui.Parent = pg
	end
	local col  = M.Color or Color3.fromRGB(255, 60, 60)
	local life = M.Life or 0.35

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1; root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromOffset(pos.X, pos.Y)
	root.Size = UDim2.fromOffset(4, 4); root.Parent = gui

	-- 1) anneau net qui s'ouvre puis s'efface
	if M.Ring ~= false then
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0.5, 0.5); r.Position = UDim2.new(0.5, 0, 0.5, 0)
		r.Size = UDim2.fromOffset(6, 6); r.BackgroundTransparency = 1; r.Parent = root
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = r
		local rs = Instance.new("UIStroke")
		rs.Color = col; rs.Thickness = M.RingThickness or 3; rs.Transparency = 0; rs.Parent = r
		local D = M.RingSize or 46
		TweenService:Create(r, TweenInfo.new(life, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(D, D) }):Play()
		TweenService:Create(rs, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1, Thickness = 0.5 }):Play()
	end

	-- 2) 4 pointes diagonales qui giclent vers l'extérieur
	local L   = M.SpikeLength or 14
	local TH  = M.SpikeThickness or 3
	local off = M.SpikeOffset or 16
	for _, a in ipairs({ -45, 45, 135, -135 }) do
		local rad = math.rad(a)
		local dx, dy = math.cos(rad), math.sin(rad)
		local s = Instance.new("Frame")
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Size = UDim2.fromOffset(TH, L); s.Rotation = a + 90
		s.BackgroundColor3 = col; s.BorderSizePixel = 0
		s.Position = UDim2.new(0.5, dx * off * 0.5, 0.5, dy * off * 0.5); s.Parent = root
		local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(1, 0); sc.Parent = s
		TweenService:Create(s, TweenInfo.new(life, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, dx * off * 1.9, 0.5, dy * off * 1.9),
				BackgroundTransparency = 1 }):Play()
	end

	-- 3) flash central très bref (le "clac" visuel)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.Position = UDim2.new(0.5, 0, 0.5, 0)
	dot.Size = UDim2.fromOffset(10, 10); dot.BackgroundColor3 = col
	dot.BackgroundTransparency = 0.15; dot.BorderSizePixel = 0; dot.Parent = root
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
	TweenService:Create(dot, TweenInfo.new(life * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 }):Play()

	Debris:AddItem(root, life + 0.1)
end

-- ════════ TRACERS (2 styles, choix PAR ARME via cfg.FX.Tracer.Style) ════════
-- "Classic" : l'original — barre néon pleine longueur.
-- "Rivals"  : comète — tête ronde lumineuse + traîne effilée (large côté balle).
-- key (optionnel) = le Tool → mode "UNE SEULE BALLE" : le tracer du tir
-- précédent disparaît dès que le nouveau part (fini la pluie de points en auto).
local activeTracers = setmetatable({}, { __mode = "k" })   -- [tool] = {t=, items={}}
function VFX.Tracer(startPos, endPos, T, key, fromPart)
	-- 🥔 potato : la comète (beams + lumière) devient une simple barre
	if T and T.Style ~= "Classic" and VFX.Potato("RivalsTracers") then
		local c = {}
		for k, v in pairs(T) do c[k] = v end
		c.Style = "Classic"
		c.Color = c.Color or Color3.fromRGB(255, 213, 0)
		c.Size = c.Size or Vector3.new(0.12, 0.12, 1)
		c.Transparency = c.Transparency or 0.15
		c.Life = c.Life or 0.05
		c._noLight = true
		T = c
	end
	local style = (T and T.Style) or "Rivals"
	local dist = (endPos - startPos).Magnitude
	if dist < 0.5 then return end

	if style == "Classic" and typeof(fromPart) == "Instance" and fromPart:IsA("BasePart") then
		-- 🏃 TRAIT ACCROCHÉ AU CANON : un Beam entre un point SUR le canon et le
		--    point d'impact. Roblox le redessine tout seul à chaque image (aucun
		--    code par image) : il ne se décale plus quand on court.
		local a0 = Instance.new("Attachment")
		a0.Name = "TracerStart"; a0.Parent = fromPart          -- suit l'arme
		local a1 = Instance.new("Attachment")
		a1.Name = "TracerEnd"; a1.WorldPosition = endPos; a1.Parent = workspace.Terrain
		local b = Instance.new("Beam")
		b.Attachment0 = a0; b.Attachment1 = a1
		b.FaceCamera = true; b.Segments = 1
		b.Width0 = T.Size.X; b.Width1 = T.Size.X
		b.Color = ColorSequence.new(T.Color)
		b.Transparency = NumberSequence.new(T.Transparency or 0)
		b.LightEmission = 1; b.LightInfluence = 0
		b.Parent = a1
		if not T._noLight and VFX.Config.TracerLights ~= false then   -- 💡 même lumière qu'avant
			local l = Instance.new("PointLight"); l.Color = T.LightColor
			l.Brightness = T.LightBrightness; l.Range = T.LightRange; l.Parent = a1
		end
		Debris:AddItem(a0, T.Life)
		Debris:AddItem(a1, T.Life)   -- le Beam et la lumière partent avec
		return
	end

	if style == "Classic" then
		local p = Instance.new("Part")
		p.Name="BulletTracer"; p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false
		p.Material=Enum.Material.Neon; p.Color=T.Color
		p.Size=Vector3.new(T.Size.X, T.Size.Y, dist)
		p.CFrame=CFrame.lookAt(startPos, endPos)*CFrame.new(0,0,-dist/2)
		p.Transparency=T.Transparency; p.Parent=workspace
		if not T._noLight and VFX.Config.TracerLights ~= false then   -- 💡 traçante classique
			local l=Instance.new("PointLight"); l.Color=T.LightColor
			l.Brightness=T.LightBrightness; l.Range=T.LightRange; l.Parent=p
		end
		Debris:AddItem(p, T.Life)
		return
	end

	-- ══ style "Rivals" : COMÈTE ══
	-- Tête RONDE et lumineuse côté balle + traîne effilée : LARGE au bout
	-- (près de la balle), fine et évanescente côté canon. Tout le trait
	-- VOYAGE réellement du canon jusqu'à l'impact (relié à la balle), puis
	-- la traîne se résorbe dans le point d'impact.
	local haloColor = T.Color                                    -- couleur de la traîne (config)
	local coreColor = T.CoreColor or Color3.fromRGB(255,255,245) -- cœur/tête (config)
	local trailLen = math.min(dist, T.TrailLength or 14)         -- longueur de la comète
	local speed = T.Speed or 900                                 -- vitesse visuelle (studs/s)
	local W = T.Width or 1                                       -- ⬅ LARGEUR globale du tracer
	-- ── réglages du BOUT côté CANON (queue de la comète) ──
	local tailWidth        = T.TailWidth        or 0.13  -- largeur au canon = × largeur tête (↓ = plus mince près du canon)
	local tailTransparency = T.TailTransparency or 0.9   -- transparence au canon (0 = opaque, 1 = invisible)
	-- COMPENSATION DE DISTANCE : sans ça, un tir lointain paraît tout fin
	-- (perspective). La largeur monte progressivement jusqu'à ×FarWidthBoost
	-- à 300+ studs → le tracer garde sa présence à l'écran peu importe la distance.
	W = W * (1 + math.min(dist, 300) / 300 * ((T.FarWidthBoost or 2.5) - 1))
	-- VITESSE ADAPTATIVE (AdaptiveSpeed, défaut ON) : la balle ne met jamais
	-- plus de MaxTravelTime à arriver → plus le tir est LOIN, plus le tracer
	-- voyage VITE (le dégât est déjà appliqué au moment du tir).
	-- AdaptiveSpeed = false → vitesse CONSTANTE (Speed), peu importe la distance.
	local travel
	if T.AdaptiveSpeed ~= false then
		travel = math.clamp(dist / speed, 0.03, T.MaxTravelTime or 0.12)
	else
		travel = math.max(dist / speed, 0.03)
	end
	local speedEff = dist / travel                               -- vitesse réelle utilisée
	local tailDelay = trailLen / speedEff

	-- ── mode "UNE SEULE BALLE" (SingleBullet, défaut OFF) ──
	-- Chaque tracer TERMINE toujours sa course (jamais coupé net par le tir
	-- suivant). Si SingleBullet = true : le tracer précédent fait un FONDU
	-- express (60 ms) quand le nouveau part — transition douce, pas d'effacement
	-- sec. Grâce à la vitesse adaptative, il y a de toute façon rarement plus
	-- d'une balle en vol. Les pellets d'un même tir (shotgun) restent groupés.
	local reg = nil
	if key and (T.SingleBullet == true) then
		local now = os.clock()
		local prev = activeTracers[key]
		if prev and now - prev.t > 0.03 then
			for _, it in ipairs(prev.items) do
				if it.Parent then
					-- fondu doux au lieu d'un Destroy sec
					for _, d in ipairs(it:GetDescendants()) do
						if d:IsA("Beam") then
							TweenService:Create(d, TweenInfo.new(0.06),
								{ Width0 = 0, Width1 = 0 }):Play()
						end
					end
					if it:IsA("BasePart") and it.Transparency < 1 then
						TweenService:Create(it, TweenInfo.new(0.06),
							{ Transparency = 1 }):Play()
					end
					Debris:AddItem(it, 0.08)
				end
			end
			prev = nil
		end
		if not prev then
			prev = { t = now, items = {} }
			activeTracers[key] = prev
		end
		reg = prev.items
	end

	local holder = Instance.new("Part")
	holder.Anchored=true; holder.CanCollide=false; holder.CanQuery=false; holder.CanTouch=false
	holder.Transparency=1; holder.Size=Vector3.one*0.1
	holder.CFrame=CFrame.lookAt(startPos, endPos)   -- -Z pointe PILE vers la cible
	holder.Parent=workspace
	-- attachments en ESPACE LOCAL du holder → alignement exact sur la trajectoire
	local tail=Instance.new("Attachment"); tail.Position=Vector3.zero; tail.Parent=holder
	local headA=Instance.new("Attachment"); headA.Position=Vector3.zero; headA.Parent=holder

	-- traîne HALO : fine au canon → LARGE près de la balle
	local glowHeadW = 0.38*W                                    -- largeur côté BALLE
	local glow=Instance.new("Beam")
	glow.Attachment0=tail; glow.Attachment1=headA
	glow.FaceCamera=true; glow.LightEmission=1; glow.LightInfluence=0
	glow.Color=ColorSequence.new(haloColor)
	glow.Transparency=NumberSequence.new({
		NumberSequenceKeypoint.new(0, tailTransparency),                          -- bout CANON (réglable)
		NumberSequenceKeypoint.new(0.6, tailTransparency + (0.15 - tailTransparency)*0.6),
		NumberSequenceKeypoint.new(1, 0.15)})                                     -- dense près de la balle
	glow.Width0=glowHeadW*tailWidth; glow.Width1=glowHeadW
	glow.Parent=holder

	-- traîne CŒUR : claire, même dégradé, plus fine
	local coreHeadW = 0.15*W
	local coreTail  = math.min(1, tailTransparency + 0.05)     -- cœur un poil + transparent que le halo
	local core=Instance.new("Beam")
	core.Attachment0=tail; core.Attachment1=headA
	core.FaceCamera=true; core.LightEmission=1; core.LightInfluence=0
	core.Color=ColorSequence.new(coreColor)
	core.Transparency=NumberSequence.new({
		NumberSequenceKeypoint.new(0, coreTail),
		NumberSequenceKeypoint.new(0.6, coreTail + (0.02 - coreTail)*0.63),
		NumberSequenceKeypoint.new(1, 0.02)})
	core.Width0=coreHeadW*tailWidth; core.Width1=coreHeadW
	core.Parent=holder

	-- TÊTE : boule néon qui ARRONDIT le bout large de la traîne
	local head=Instance.new("Part")
	head.Shape=Enum.PartType.Ball; head.Material=Enum.Material.Neon
	head.Color=coreColor
	head.Size=Vector3.one*0.34*W
	head.Anchored=true; head.CanCollide=false; head.CanQuery=false; head.CanTouch=false
	head.CastShadow=false; head.CFrame=CFrame.new(startPos); head.Parent=workspace
	if not T._noLight and VFX.Config.TracerLights ~= false then   -- 💡 tête du tracer
		local hl=Instance.new("PointLight")
		hl.Color=haloColor; hl.Brightness=(T.LightBrightness or 5)*0.8
		hl.Range=(T.LightRange or 10)*0.8; hl.Parent=head
	end
	-- enregistre pour le mode "une seule balle"
	if reg then table.insert(reg, holder); table.insert(reg, head) end

	-- VOYAGE : la tête file vers l'impact ; la queue suit avec un retard
	-- (traîne de longueur constante) puis se résorbe dans l'impact.
	TweenService:Create(headA, TweenInfo.new(travel, Enum.EasingStyle.Linear),
		{ Position = Vector3.new(0, 0, -dist) }):Play()
	TweenService:Create(head, TweenInfo.new(travel, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.new(endPos) }):Play()
	TweenService:Create(tail,
		TweenInfo.new(travel, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, tailDelay),
		{ Position = Vector3.new(0, 0, -dist) }):Play()
	-- micro-flash rond quand la balle arrive
	task.delay(travel, function()
		if head.Parent then
			TweenService:Create(head, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.one*0.6*W, Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(head, travel + 0.12)
	Debris:AddItem(holder, travel + tailDelay + 0.1)
end

return VFX