-- ============================================================
-- WeaponMechanics  (ModuleScript)
-- Emplacement : ReplicatedStorage/WeaponSystem/WeaponMechanics
-- ============================================================
-- Mécaniques de mouvement COMMUNES (sprint + slide), actives uniquement
-- quand le joueur a AU MOINS une arme dans son inventaire (Backpack
-- ou équipée). Tout est configurable et désactivable.
--
-- Setup une seule fois par client depuis un LocalScript dans
-- StarterPlayerScripts :  require(WeaponMechanics).Setup(CONFIG)
--
-- Ce que ça gère :
--   • SPRINT  : vitesse ↑, anim bras (balancement gauche + arme en haut style CoD
--               + rebonds/pas), kick de FOV, effet de vitesse (vignette/speed lines).
--               PC = maintien Shift ; Mobile = bouton "lock" (toggle).
--   • SLIDE   : impulsion dans n'importe quelle direction, inclinaison caméra (roll)
--               vers le côté du slide, léger abaissement caméra.
--               PC = C ; Mobile = bouton.
--
-- Pont avec le WeaponController via WeaponSharedState :
--   - publie les poses de bras (consommées par la boucle Feel + le viewmodel)
--   - publie un offset de FOV (ajouté par la boucle Feel quand armé)
--   - publie le roll caméra (appliqué par la caméra TP de l'arme + ici en 1re pers)
-- ============================================================

local WeaponMechanics = {}

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local CollectionService= game:GetService("CollectionService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local WeaponSharedState = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponSharedState"))

local BodyAnim = require(game:GetService("ReplicatedStorage"):WaitForChild("BodyAnim"))

-- 🆕 MOUVEMENT PVP (double saut, élan, gravité, lignes de vitesse, caméra).
-- Module absent, erreur, ou interrupteur coupé = EXACTEMENT l'ancien comportement.
local Boost = nil
do
	local mod = ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("MovementBoost", 5)
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			Boost = res
		else
			warn("[WeaponMechanics] MovementBoost non chargé :", res)
		end
	end
end
if not Boost then
	Boost = {
		Start = function() end,
		Bonus = function() return 0 end,
		FOV = function() return 0 end,
		SlideRules = function() return nil end,
		SlideCurve = function() return 1 end,
		OnSlideStart = function() return 0 end,
		OnSlideEnd = function() end,
	}
end

-- ── Merge récursif des défauts ──────────────────────────────
local function deepDefault(dst, src)
	dst = dst or {}
	for k, v in pairs(src) do
		if type(v) == "table" then dst[k] = deepDefault(dst[k], v)
		elseif dst[k] == nil then dst[k] = v end
	end
	return dst
end

local DEFAULTS = {
	Enabled = true,

	-- ── Détection "arme" : un Tool compte comme arme s'il a un enfant nommé
	--    WeaponDetectChild OU le tag CollectionService WeaponTag. Mets "" pour ignorer.
	WeaponDetectChild = "Receiver",
	WeaponTag = "Weapon",

	BaseWalkSpeed = nil,   -- nil = capture auto à l'apparition (sinon force la valeur)

	-- ════════════════════════════════════════════════════════
	-- SPRINT
	-- ════════════════════════════════════════════════════════
	Sprint = {
		Enabled = true,
		Key        = Enum.KeyCode.LeftShift,  -- ⚠ libère Shift dans le WeaponController (voir notes)
		GamepadKey = Enum.KeyCode.ButtonL3,
		GamepadToggle = true,        -- 🎮 manette : 1 appui = sprint activé pour de bon, 2e appui = arrêté
		WalkSpeedMult = 1.30,        -- vitesse sprint = base * mult
		RequireMoving = true,        -- sprint seulement si on se déplace
		ForwardOnly   = false,       -- true = sprint seulement vers l'avant (style CoD)
		BlendIn  = 12,               -- vitesse d'entrée de l'anim
		BlendOut = 16,               -- vitesse de sortie
		RecoverTime = 0.22,          -- pause du sprint après un TIR (sprint-out)
		BlocksActions = false,       -- false = tir/ADS annulent le sprint ; true = tir/ADS interdits en sprint

		-- Pause du sprint PENDANT la visée (tient TANT qu'on vise, reprend au relâché).
		-- Détection directe de l'input de visée → marche même si le patch WeaponController
		-- n'est pas branché. Mets false si ton ADS est en "toggle" (clic) plutôt qu'en maintien.
		PauseOnAimInput = false,
		AimInputButton  = Enum.UserInputType.MouseButton2,  -- bouton de visée (maintien)
		HideCursorWhileAiming = true,  -- cache le cursor pendant la visée (restauré au relâché)

		-- Pause du sprint PENDANT le tir. Maintien (auto) = pause tant qu'on tire,
		-- puis petit cooldown (RecoverTime) au relâché pour que la reprise soit smooth.
		PauseOnFireInput = true,
		FireInputButton  = Enum.UserInputType.MouseButton1,

		FOVKick = 8,                 -- + de FOV au sprint plein
		HipFOV  = 70,                -- FOV de référence quand AUCUNE arme n'est équipée

		-- Anim bras de SPRINT — poses C1 ABSOLUES (le WeaponController lerp la pose
		-- "arme en main" → ces poses selon sprintAlpha). Calées au tuner sur ton rig.
		-- Bras DROIT : RELEVÉ, tient l'arme en port haut (l'arme suit la main via le Grip).
		RightArmSprintC1 = CFrame.new(-1.450, 0.150, -1.550) * CFrame.Angles(math.rad(-160.0), math.rad(0.0), math.rad(-8.0)),
		RightSwingAngle  = math.rad(10),  -- léger contre-balancement du bras porteur
		-- Bras GAUCHE : QUITTE l'arme, pend À GAUCHE le long du corps et se balance (sprinter).
		LeftArmSprintC1  = CFrame.new(1.650, 0.300, -0.050) * CFrame.Angles(math.rad(-9.0), math.rad(-5.0), math.rad(0.0)),
		LeftSwingAngle   = math.rad(50),  -- amplitude avant/arrière du bras libre

		StepsPerSecond = 4.2,        -- cadence des pas (fréquence des rebonds)
		BobY     = 0.05,             -- rebond vertical
		BobPitch = math.rad(3),      -- rebond en tangage
		BobRoll  = math.rad(2),      -- rebond en roulis

		-- Effet de vitesse OPTIONNEL : juste un slot image plein écran. AUCUNE vignette.
		-- Désactivé par défaut. Mets une image ET Enabled=true si tu en veux une.
		SpeedLines = {
			Enabled = false,
			Image = "",                                  -- ← TON IMAGE speed-lines plein écran, sans fond (rbxassetid://...)
			MaxIntensity = 0.85,                          -- opacité au sprint plein (0..1)
		},
	},

	-- ════════════════════════════════════════════════════════
	-- SLIDE
	-- ════════════════════════════════════════════════════════
	Slide = {
		Enabled = true,
		-- Inclinaison du viewmodel, par rapport à la caméra : degrés positifs = gauche.
		WeaponLean = { Enabled = true, Angle = 30, InTime = 0.12, OutTime = 0.18 },
		Key        = Enum.KeyCode.C,
		GamepadKey = Enum.KeyCode.ButtonR3,
		Speed    = 40,               -- vitesse du slide (constante, PAS de décélération)
		Duration = 0.50,             -- court & nerveux (compétitif)
		Cooldown = 0.5,             -- temps mort entre deux slides
		RequireGrounded = true,      -- interdit le slide en l'air
		BufferTime = 0.6,            -- input de slide en l'air mémorisé → slide à l'atterrissage (fenêtre en s)
		SteerRate = math.rad(220),   -- redirection : braquage max pendant le slide (deg/s)
		ExitToSprint = true,         -- à la fin : enchaîne en sprint si Shift tenu (zéro ralentissement)

		CancelOnJump = true,         -- sauter annule le slide (l'élan est conservé)
		ReverseBrake = 0.29,          -- frein quand on pousse à l'opposé du slide
		MinSpeedMult = 0.20,         -- vitesse min du slide quand on freine à fond (× Speed)

		-- Animation de slide. Par défaut on joue AnimationId (anim Roblox classique) :
		-- elle est RÉPLIQUÉE → les autres joueurs ET toi la voyez. En 1re personne tes
		-- vrais bras sont cachés (viewmodel), donc l'anim n'influence PAS la position de tes bras.
		-- Mets ProceduralAnim=true pour la pose maison locale (couché/jambe pliée) à la place.
		ProceduralAnim = false,
		MaskArmsFirstPerson = false,  -- en 1re pers, annule l'influence de l'anim sur TES bras
		-- (local → les autres voient toujours l'anim complète, bras en l'air)
		PoseBlend    = 100,           -- (pose procédurale) réactivité d'entrée/sortie
		FrontLeg     = "Right",      -- (pose procédurale) jambe pliée : "Right" ou "Left"
		RootPose     = CFrame.new(0, -0.4, 0) * CFrame.Angles(math.rad(-48), 0, 0),
		FrontLegPose = CFrame.Angles(math.rad(72), 0, math.rad(-8)),
		BackLegPose  = CFrame.Angles(math.rad(-16), 0, math.rad(6)),
		AnimationId   = "rbxassetid://118625574462160",  -- ton anim de slide (répliquée)
		AnimationFade = 0.08,        -- fondu d'entrée/sortie de l'anim

		MaxRoll = math.rad(9),       -- inclinaison caméra max vers le côté du slide
		RollSpeed = 12,              -- réactivité de l'inclinaison
		CameraLower = 1.2,           -- abaissement caméra (studs) — 1re pers. 0 = off
		-- ── Viser PENDANT le slide : on amortit roll + abaissement pour un aim propre ──
		AimRollMult  = 0.25,         -- × MaxRoll quand on vise en slide (0 = zéro inclinaison)
		AimLowerMult = 0.35,         -- × CameraLower quand on vise en slide (0 = pas d'abaissement)
		-- ── VFX de glissade : poussière projetée derrière le joueur ──
		Dust = {
			Enabled = true,
			Color = Color3.fromRGB(216, 206, 190),
			Rate = 55,          -- densité pendant le slide
			Size = 1.3,         -- taille des bouffées
		},
	},

	-- ════════════════════════════════════════════════════════
	-- UI MOBILE  (boutons : mets une image SANS FOND dans Image)
	-- ════════════════════════════════════════════════════════
	Mobile = {
		HideWhenNoWeapon = true,
		KeepSprintOnRespawn = true,   -- 🆕 true = le sprint activé reste activé après la mort · false = il faut recliquer
		SprintButton = {
			Image = "",                                  -- ← TON IMAGE sprint ici
			Size = UDim2.new(0,84,0,84),
			Position = UDim2.new(1,-130, 1,-330),        -- au-dessus du bouton de tir
		},
		SlideButton = {
			Image = "",                                  -- ← TON IMAGE slide ici
			Size = UDim2.new(0,72,0,72),
			Position = UDim2.new(1,-225, 1,-275),
		},
	},
}

-- ============================================================
function WeaponMechanics.Setup(userConfig)
	local cfg = deepDefault(userConfig, DEFAULTS)
	if not cfg.Enabled then return end
	Boost.Start()   -- 🆕 mouvement PVP (ne fait rien si coupé)

	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local IsMobile = WeaponSharedState.IsMobile()

	-- ── Refs perso ──────────────────────────────────────────
	local character, humanoid, root
	local baseWalkSpeed = cfg.BaseWalkSpeed or 16
	local lastAppliedSpeed = nil   -- dernière vitesse écrite par CE script

	-- ── État sprint ─────────────────────────────────────────
	-- 🆕 MOBILE : l'état du bouton sprint est rangé sur le PLAYER (attribut), qui
	-- survit à la mort. Même si le script est relancé au respawn, on le relit ici.
	local SPRINT_LOCK_ATTR = "MobileSprintLock"
	local sprintHeld   = (IsMobile and cfg.Mobile.KeepSprintOnRespawn
		and player:GetAttribute(SPRINT_LOCK_ATTR) == true) or false   -- maintien PC OU lock mobile
	local sprinting    = false
	local sprintAlpha  = 0
	local mechFOVActive = false   -- 🩹 ce script pilote le FOV (sprint / vitesse) en ce moment
	local bobPhase     = 0
	local suppressedUntil = 0       -- pause sprint après tir
	local aimInputHeld = false      -- bouton de visée maintenu → pause le sprint
	local fireInputHeld = false     -- bouton de tir maintenu → pause le sprint (auto)
	local fireSuppressUntil = 0     -- mini cooldown sprint après le dernier tir
	local prevFiring = false        -- suivi du tir publié par l'arme (mobile inclus)
	local cursorHidden = false      -- cursor masqué pendant la visée

	-- ── État slide ──────────────────────────────────────────
	local sliding   = false
	local slideStart= 0
	local slideDir  = Vector3.zero
	local slideRollTarget = 0
	local slideCooldownUntil = 0
	local slideBufferUntil = 0      -- slide pressé en l'air → déclenche à l'atterrissage
	local slideExtra, slideLastSpeed = 0, 0   -- 🆕 élan ajouté au slide / dernière vitesse du slide
	local slideDur, slideT = 0.5, 0            -- 🆕 durée de CE slide / avancement 0..1
	local slideKeyHeld, slideTouch = false, nil -- 🆕 touche / bouton slide MAINTENU
	local wasAirborne = false       -- suivi sol/air pour détecter l'atterrissage
	local currentRoll = 0
	local camLowerApplied = false
	local slideAnimTrack = nil      -- AnimationTrack de corps (si AnimationId fourni)
	-- pose de slide PROCÉDURALE (locale) — pose couché/torse relevé/jambe pliée
	local slidePoseAlpha = 0
	local rootJoint, frontHip, backHip = nil, nil, nil
	local rightShoulder, leftShoulder = nil, nil   -- épaules R6 (pour masquer les bras de l'anim de slide)
	local posedCleared = true

	-- ── UI ──────────────────────────────────────────────────
	local mechGui, sprintBtn, slideBtn
	local speedGui, speedCanvas

	-- ── Détection arme ──────────────────────────────────────
	local function isWeaponTool(t)
		if not t or not t:IsA("Tool") then return false end
		if cfg.WeaponTag ~= "" and CollectionService:HasTag(t, cfg.WeaponTag) then return true end
		if cfg.WeaponDetectChild ~= "" and t:FindFirstChild(cfg.WeaponDetectChild) then return true end
		return false
	end
	local function hasWeapon()
		local char = player.Character
		if char then
			for _, t in ipairs(char:GetChildren()) do if isWeaponTool(t) then return true end end
		end
		local bp = player:FindFirstChildOfClass("Backpack")
		if bp then
			for _, t in ipairs(bp:GetChildren()) do if isWeaponTool(t) then return true end end
		end
		return false
	end
	-- arme ÉQUIPÉE (dans le perso) — sert au tuner pour lire/écrire les attributs
	local function equippedWeaponTool()
		local char = player.Character
		if not char then return nil end
		for _, t in ipairs(char:GetChildren()) do if isWeaponTool(t) then return t end end
		return nil
	end

	-- Vitesse selon l'état. COMPATIBLE avec les scripts externes (boost, slow,
	-- zones...) : si la WalkSpeed actuelle n'est pas celle qu'ON a écrite au
	-- dernier tick, c'est qu'un AUTRE script l'a changée → on adopte cette
	-- valeur comme nouvelle BASE. Le sprint devient un simple multiplicateur
	-- par-dessus (base × mult), et le slide une pause (0), sans jamais
	-- écraser définitivement la vitesse des autres systèmes.
	local function applyWalkSpeed()
		if not humanoid then return end
		if lastAppliedSpeed == nil
			or math.abs(humanoid.WalkSpeed - lastAppliedSpeed) > 0.001 then
			baseWalkSpeed = humanoid.WalkSpeed   -- changement externe détecté
		end
		local target
		if sliding then target = 0
		elseif sprinting then target = baseWalkSpeed * cfg.Sprint.WalkSpeedMult + Boost.Bonus()
		else target = baseWalkSpeed + Boost.Bonus() end
		humanoid.WalkSpeed = target
		lastAppliedSpeed = target
	end

	-- ════════════════════════════════════════════════════════
	-- SPEED LINES / VIGNETTE
	-- ════════════════════════════════════════════════════════
	local function buildSpeedLines()
		if not cfg.Sprint.SpeedLines.Enabled then return end
		if not player then return end
		local pg = player:FindFirstChildOfClass("PlayerGui"); if not pg then return end
		if speedGui then speedGui:Destroy() end
		local SL = cfg.Sprint.SpeedLines

		local sg = Instance.new("ScreenGui")
		sg.Name="SprintSpeedLines"; sg.ResetOnSpawn=false; sg.IgnoreGuiInset=true
		sg.DisplayOrder=4; sg.Parent=pg

		-- CanvasGroup → fade uniforme via GroupTransparency
		local cg = Instance.new("CanvasGroup")
		cg.Size=UDim2.new(1,0,1,0); cg.BackgroundTransparency=1; cg.GroupTransparency=1; cg.Parent=sg

		-- UNIQUEMENT ton image plein écran (aucune vignette générée). Rien si pas d'image.
		if SL.Image ~= "" then
			local img=Instance.new("ImageLabel"); img.Name="Lines"; img.Size=UDim2.new(1,0,1,0)
			img.BackgroundTransparency=1; img.Image=SL.Image; img.ScaleType=Enum.ScaleType.Stretch
			img.Parent=cg
		end

		speedGui, speedCanvas = sg, cg
	end

	local function updateSpeedLines(alpha)
		if not speedCanvas then return end
		local maxI = cfg.Sprint.SpeedLines.MaxIntensity
		speedCanvas.GroupTransparency = 1 - alpha * maxI
	end

	-- ════════════════════════════════════════════════════════
	-- UI MOBILE
	-- ════════════════════════════════════════════════════════
	local function setSprintBtnVisual(on)
		if not sprintBtn then return end
		sprintBtn.BackgroundTransparency = on and 0.15 or 0.5
		local stroke = sprintBtn:FindFirstChildWhichIsA("UIStroke")
		if stroke then stroke.Color = on and Color3.fromRGB(120,220,255) or Color3.fromRGB(0,0,0) end
	end

	local function toggleSprintLock()
		sprintHeld = not sprintHeld
		setSprintBtnVisual(sprintHeld)
		-- 🆕 mémorisé sur le joueur : relu après la mort
		if cfg.Mobile.KeepSprintOnRespawn then player:SetAttribute(SPRINT_LOCK_ATTR, sprintHeld) end
	end

	local function buildMobileUI()
		if not IsMobile or not player then return end
		local pg = player:FindFirstChildOfClass("PlayerGui"); if not pg then return end
		if mechGui then mechGui:Destroy() end

		local gui=Instance.new("ScreenGui"); gui.Name="MechanicsGui"; gui.ResetOnSpawn=false
		gui.IgnoreGuiInset=true; gui.DisplayOrder=6; gui.Parent=pg

		local function makeBtn(conf, name)
			local b=Instance.new("ImageButton"); b.Name=name; b.Size=conf.Size; b.Position=conf.Position
			b.AnchorPoint=Vector2.new(0,0); b.BackgroundColor3=Color3.fromRGB(0,0,0)
			b.BackgroundTransparency=0.5; b.BorderSizePixel=0; b.AutoButtonColor=false; b.Active=true
			b.Image=""; b.Parent=gui
			local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=b
			local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(0,0,0); s.Thickness=2; s.Parent=b
			local ic=Instance.new("ImageLabel"); ic.Name="Icon"; ic.Size=UDim2.new(0.55,0,0.55,0)
			ic.AnchorPoint=Vector2.new(0.5,0.5); ic.Position=UDim2.new(0.5,0,0.5,0)
			ic.BackgroundTransparency=1; ic.Image=conf.Image; ic.ScaleType=Enum.ScaleType.Fit; ic.Parent=b
			return b
		end

		if cfg.Sprint.Enabled then
			sprintBtn = makeBtn(cfg.Mobile.SprintButton, "SprintButton")
			sprintBtn.Activated:Connect(toggleSprintLock)
			setSprintBtnVisual(sprintHeld)
		end
		if cfg.Slide.Enabled then
			slideBtn = makeBtn(cfg.Mobile.SlideButton, "SlideButton")
			slideBtn.Activated:Connect(function() WeaponMechanics._tryStartSlide() end)
			-- 🆕 bouton maintenu : slide automatique à l'atterrissage
			slideBtn.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1 then
					slideTouch = input; slideKeyHeld = true
				end
			end)
		end

		mechGui = gui
	end

	-- ════════════════════════════════════════════════════════
	-- SLIDE
	-- ════════════════════════════════════════════════════════
	local function startSlideAnim()
		if cfg.Slide.ProceduralAnim then return end   -- pose procédurale gérée au rendu
		if cfg.Slide.AnimationId == "" or not humanoid then return end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator"); animator.Parent = humanoid
		end
		if not slideAnimTrack then
			local a = Instance.new("Animation"); a.AnimationId = cfg.Slide.AnimationId
			local ok, track = pcall(function() return animator:LoadAnimation(a) end)
			if not ok then return end
			slideAnimTrack = track
			slideAnimTrack.Priority = Enum.AnimationPriority.Action4  -- au-dessus de la marche
			slideAnimTrack.Looped = true
		end
		slideAnimTrack:Play(cfg.Slide.AnimationFade)
	end
	local function stopSlideAnim()
		if cfg.Slide.ProceduralAnim then return end
		if slideAnimTrack then slideAnimTrack:Stop(cfg.Slide.AnimationFade) end
	end

	-- poussière de slide (émetteur créé une fois, activé pendant la glissade)
	local slideDustAtt = nil
	local function setSlideDust(on)
		local D = cfg.Slide.Dust
		if not D or not D.Enabled then return end
		if on then
			if not root then return end
			if not slideDustAtt or slideDustAtt.Parent ~= root then
				if slideDustAtt then slideDustAtt:Destroy() end
				slideDustAtt = Instance.new("Attachment")
				slideDustAtt.Position = Vector3.new(0, -2.6, 0)   -- aux pieds
				slideDustAtt.Parent = root
				local d = Instance.new("ParticleEmitter"); d.Name = "SlideDust"
				d.Texture = "rbxasset://textures/particles/smoke_main.dds"
				d.Color = ColorSequence.new(D.Color)
				d.LightInfluence = 1
				d.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1)})
				d.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, D.Size*0.5), NumberSequenceKeypoint.new(1, D.Size*1.7)})
				d.Lifetime = NumberRange.new(0.35, 0.7)
				d.Speed = NumberRange.new(2, 5)
				d.SpreadAngle = Vector2.new(35, 35)
				d.Acceleration = Vector3.new(0, 3, 0)
				d.Rotation = NumberRange.new(0, 360); d.RotSpeed = NumberRange.new(-40, 40)
				d.EmissionDirection = Enum.NormalId.Back   -- projetée DERRIÈRE la glissade
				d.Rate = D.Rate; d.Enabled = false
				d.Parent = slideDustAtt
				-- petits graviers qui giclent
				local g = Instance.new("ParticleEmitter"); g.Name = "SlideGrit"
				g.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				g.Color = ColorSequence.new(D.Color)
				g.LightInfluence = 1
				g.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
				g.Size = NumberSequence.new(0.12)
				g.Lifetime = NumberRange.new(0.25, 0.45)
				g.Speed = NumberRange.new(6, 11)
				g.SpreadAngle = Vector2.new(25, 25)
				g.Acceleration = Vector3.new(0, -40, 0)
				g.EmissionDirection = Enum.NormalId.Back
				g.Rate = math.floor(D.Rate * 0.4); g.Enabled = false
				g.Parent = slideDustAtt
			end
			slideDustAtt.SlideDust.Enabled = true
			slideDustAtt.SlideGrit.Enabled = true
		elseif slideDustAtt then
			local d = slideDustAtt:FindFirstChild("SlideDust")
			local g = slideDustAtt:FindFirstChild("SlideGrit")
			if d then d.Enabled = false end
			if g then g.Enabled = false end
		end
	end

	-- fin de slide PROPRE : aucun freinage, on garde l'élan. Utilisé par la durée ET le saut.
	local function endSlide(reason)
		if not sliding then return end
		sliding = false
		-- 🆕 mini relève (au lieu du cooldown) + élan gardé à la sortie
		do
			local R = Boost.SlideRules()
			if R then
				local cancel = (reason == "jump")
				local wait = cancel and (R.JumpRecover or 0) or (R.Recover or 0.15)
				-- 🆕 cooldown optionnel, ajouté APRÈS le slide (0 = aucun)
				if (R.Cooldown or 0) > 0 and (not cancel or R.CooldownOnCancel ~= false) then
					wait += R.Cooldown
				end
				slideCooldownUntil = os.clock() + wait
			end
			local normal = baseWalkSpeed
				* ((cfg.Sprint.Enabled and sprintHeld) and cfg.Sprint.WalkSpeedMult or 1)
			Boost.OnSlideEnd(reason or "end", slideLastSpeed - normal, slideT)
		end
		if character then character:SetAttribute("WeaponSliding", false) end
		BodyAnim.Stop("SLIDE")   -- 🧍 le corps reprend l'animation Roblox
		stopSlideAnim()
		setSlideDust(false)
		if humanoid then humanoid.CameraOffset = Vector3.zero end
		camLowerApplied = false
		if cfg.Slide.ExitToSprint and sprintHeld and humanoid then
			sprinting = true   -- la vitesse haute du sprint prend le relais → pas de chute
		end
		applyWalkSpeed()
	end

	function WeaponMechanics._tryStartSlide()
		local rules = Boost.SlideRules()   -- 🆕 nil = ancien slide
		if not cfg.Slide.Enabled then return end
		if sliding then
			-- 🆕 pendant un slide il faut attendre sa fin (sauf BufferWhileSliding > 0)
			if rules and (rules.BufferWhileSliding or 0) > 0 then
				slideBufferUntil = os.clock() + rules.BufferWhileSliding
			end
			return
		end
		if not hasWeapon() or not humanoid or not root then return end
		local now = os.clock()
		if now < slideCooldownUntil then
			-- 🆕 appui pendant la relève : il part dès qu'elle est finie
			-- (seulement s'il reste moins que RecoverBuffer : un long cooldown ne garde pas l'appui)
			if rules and (slideCooldownUntil - now) <= (rules.RecoverBuffer or 0.2) then
				slideBufferUntil = math.max(slideBufferUntil, slideCooldownUntil + (rules.RecoverBuffer or 0.2))
			end
			return
		end
		if cfg.Slide.RequireGrounded and humanoid.FloorMaterial == Enum.Material.Air then
			-- en l'air → on mémorise l'intention ; elle se déclenchera à l'atterrissage
			slideBufferUntil = now + ((rules and rules.LandBuffer) or cfg.Slide.BufferTime)
			return
		end

		local md = humanoid.MoveDirection
		local dir = (md.Magnitude > 0.1) and md or root.CFrame.LookVector
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude < 0.01 then
			local lv = root.CFrame.LookVector; dir = Vector3.new(lv.X, 0, lv.Z)
		end
		if dir.Magnitude < 0.01 then return end
		slideDir = dir.Unit
		sliding = true
		if character then character:SetAttribute("WeaponSliding", true) end
		slideStart = now
		slideDur = (rules and rules.Duration) or cfg.Slide.Duration   -- 🆕 durée PVP si réglée
		slideT = 0
		-- 🧍 animation de corps du SLIDE (Anim Studio → animation SLIDE)
		if type(cfg.Slide.Keyframes) == "table" and #cfg.Slide.Keyframes >= 2 then
			BodyAnim.Play("SLIDE", cfg.Slide.Keyframes, {
				time = cfg.Slide.AnimTime or slideDur or 0.75,
				loop = false,
				override = cfg.Slide.Override ~= false,
			})
		end
		if rules then
			-- 🆕 plus de temps mort : la relève est posée à la FIN du slide (endSlide)
			slideCooldownUntil = now + slideDur
		else
			slideCooldownUntil = now + cfg.Slide.Cooldown + cfg.Slide.Duration
		end
		slideExtra = Boost.OnSlideStart()
		slideLastSpeed = cfg.Slide.Speed + slideExtra

		-- inclinaison : positif vers la droite, négatif vers la gauche, selon la composante latérale
		local rel = camera.CFrame:VectorToObjectSpace(slideDir)
		slideRollTarget = math.clamp(-rel.X, -1, 1) * cfg.Slide.MaxRoll

		sprinting = false   -- le slide prend le dessus sur l'anim sprint
		applyWalkSpeed()
		startSlideAnim()
		setSlideDust(true)
	end

	local function updateSlide(dt)
		-- roll : easing vers la cible (ou 0). En visée → on AMORTIT pour un aim propre.
		local targetRoll = sliding and slideRollTarget or 0
		if sliding and WeaponSharedState.IsAiming() then
			targetRoll = targetRoll * cfg.Slide.AimRollMult
		end
		currentRoll += (targetRoll - currentRoll) * math.clamp(dt * cfg.Slide.RollSpeed, 0, 1)
		if math.abs(currentRoll) < 1e-4 then currentRoll = 0 end

		if not sliding then
			if camLowerApplied and humanoid then
				humanoid.CameraOffset = Vector3.zero; camLowerApplied = false
			end
			return
		end

		local now = os.clock()
		local t = (now - slideStart) / slideDur
		slideT = math.clamp(t, 0, 1)
		if t >= 1 or not root or not humanoid or humanoid.Health <= 0 then
			endSlide()
			return
		end

		-- ── REDIRECTION + FREINAGE selon l'input ──
		local md = humanoid.MoveDirection
		local want = Vector3.new(md.X, 0, md.Z)
		local speedMult = 1
		if want.Magnitude > 0.05 then
			want = want.Unit
			local dot = math.clamp(slideDir:Dot(want), -1, 1)
			if dot > -0.25 then
				-- input vers l'avant/le côté → on braque slideDir (vitesse de braquage limitée)
				local angle = math.acos(dot)
				local maxStep = cfg.Slide.SteerRate * dt
				if angle > 1e-3 then
					local a = math.min(maxStep, angle) / angle
					slideDir = slideDir:Lerp(want, a)
					if slideDir.Magnitude > 1e-4 then slideDir = slideDir.Unit end
					local rel = camera.CFrame:VectorToObjectSpace(slideDir)
					slideRollTarget = math.clamp(-rel.X, -1, 1) * cfg.Slide.MaxRoll
				end
			else
				-- input à CONTRE-SENS → on RALENTIT le slide (sans le couper, sans braquer)
				speedMult = math.max(cfg.Slide.MinSpeedMult, 1 + dot * cfg.Slide.ReverseBrake)
			end
		end

		-- vitesse constante × frein éventuel
		local speed = (cfg.Slide.Speed + slideExtra) * speedMult * Boost.SlideCurve(t)   -- 🆕 élan + fin de slide
		slideLastSpeed = speed
		local yv = root.AssemblyLinearVelocity.Y
		root.AssemblyLinearVelocity = Vector3.new(slideDir.X * speed, yv, slideDir.Z * speed)

		-- abaissement caméra (1re pers ; courbe in→out). Amorti en visée → aim propre.
		if not WeaponSharedState.IsThirdPersonLock() then
			local lowerAmt = cfg.Slide.CameraLower
			if WeaponSharedState.IsAiming() then lowerAmt = lowerAmt * cfg.Slide.AimLowerMult end
			if lowerAmt > 0 then
				local e = math.sin(math.clamp(t,0,1) * math.pi)
				humanoid.CameraOffset = Vector3.new(0, -lowerAmt * e, 0)
				camLowerApplied = true
			elseif camLowerApplied then
				humanoid.CameraOffset = Vector3.zero; camLowerApplied = false
			end
		end
	end

	-- ════════════════════════════════════════════════════════
	-- SPRINT — calcul des poses de bras (C1 ABSOLUES)
	-- Le WeaponController lerp "pose arme en main" → ces poses selon sprintAlpha.
	-- ════════════════════════════════════════════════════════
	-- lecture live du tuner : si l'arme équipée porte des attributs TuneSprint*,
	-- ils remplacent les C1 du config (pour caler en jeu sans redémarrer).
	local function tunedC1(side, fallback)
		local tool = equippedWeaponTool()
		if not tool then return fallback end
		local p = "TuneSprint"..side
		local x = tool:GetAttribute(p.."X"); if x == nil then return fallback end
		return CFrame.new(
			x,
			tool:GetAttribute(p.."Y") or 0,
			tool:GetAttribute(p.."Z") or 0
		) * CFrame.Angles(
			math.rad(tool:GetAttribute(p.."RX") or 0),
			math.rad(tool:GetAttribute(p.."RY") or 0),
			math.rad(tool:GetAttribute(p.."RZ") or 0)
		)
	end

	local function computeArmPoses(dt, alpha)
		if alpha <= 0.001 then
			-- rien à appliquer : on publie l'identité (le Controller gardera la pose arme)
			WeaponSharedState.PublishWeaponPose(CFrame.new(), CFrame.new())
			return
		end
		local S = cfg.Sprint
		bobPhase += dt * S.StepsPerSecond * 2 * math.pi

		-- 🧍 CYCLE DE SPRINT ANIMÉ À LA MAIN (Anim Studio → animation SPRINT).
		-- Les poses des BRAS sont absolues et remplacent le balancement
		-- procédural ; le torse, les jambes et la tête passent par BodyAnim.
		if type(S.Keyframes) == "table" and #S.Keyframes >= 2 then
			if not BodyAnim.IsPlaying("SPRINT") then
				BodyAnim.Play("SPRINT", S.Keyframes, {
					loop = true, time = 2 / math.max(0.1, S.StepsPerSecond),
					override = S.Override ~= false,
				})
			end
			local p = (bobPhase / (4 * math.pi)) % 1
			local from, to = S.Keyframes[1], S.Keyframes[#S.Keyframes]
			for i = 1, #S.Keyframes - 1 do
				if p >= (S.Keyframes[i].t or 0) and p <= (S.Keyframes[i+1].t or 1) then
					from, to = S.Keyframes[i], S.Keyframes[i+1]; break
				end
			end
			local seg = (to.t or 1) - (from.t or 0)
			local x = seg > 0 and ((p - (from.t or 0)) / seg) or 1
			if to.ease == "in" then x = x * x
			elseif to.ease == "out" then x = 1 - (1 - x) * (1 - x)
			elseif to.ease == "linear" then -- rien
			else x = x * x * (3 - 2 * x) end
			WeaponSharedState.PublishWeaponPose(
				(from.l or CFrame.new()):Lerp(to.l or CFrame.new(), x),
				(from.r or CFrame.new()):Lerp(to.r or CFrame.new(), x))
			return
		end
		BodyAnim.Stop("SPRINT")

		-- 🆕 CYCLE DE SPRINT ANIMÉ À LA MAIN (Anim Studio → animation SPRINT).
		-- Les poses sont ABSOLUES et remplacent le balancement procédural.
		-- Une foulée = 2 pas = 4π de phase : le cycle reste donc calé sur les
		-- pas, même si tu changes StepsPerSecond.
		if type(S.Keyframes) == "table" and #S.Keyframes >= 2 then
			local p = (bobPhase / (4 * math.pi)) % 1
			local from, to = S.Keyframes[1], S.Keyframes[#S.Keyframes]
			for i = 1, #S.Keyframes - 1 do
				if p >= (S.Keyframes[i].t or 0) and p <= (S.Keyframes[i+1].t or 1) then
					from, to = S.Keyframes[i], S.Keyframes[i+1]; break
				end
			end
			local seg = (to.t or 1) - (from.t or 0)
			local x = seg > 0 and ((p - (from.t or 0)) / seg) or 1
			if to.ease == "in" then x = x * x
			elseif to.ease == "out" then x = 1 - (1 - x) * (1 - x)
			elseif to.ease == "linear" then -- rien
			else x = x * x * (3 - 2 * x) end
			WeaponSharedState.PublishWeaponPose(
				(from.l or CFrame.new()):Lerp(to.l or CFrame.new(), x),
				(from.r or CFrame.new()):Lerp(to.r or CFrame.new(), x))
			return
		end

		-- rebond commun (pas)
		local b = math.sin(bobPhase)
		local bob = CFrame.new(0, b * S.BobY * 0.5, 0)
			* CFrame.Angles(b * S.BobPitch, 0, b * S.BobRoll)

		-- balancement de sprinter : un cycle par foulée (2 pas)
		local swingL = CFrame.Angles(math.sin(bobPhase * 0.5) * S.LeftSwingAngle, 0, 0)
		local swingR = CFrame.Angles(-math.sin(bobPhase * 0.5) * S.RightSwingAngle, 0, 0)

		-- bases (config OU tuner live)
		local rightBase = tunedC1("R", S.RightArmSprintC1)
		local leftBase  = tunedC1("L", S.LeftArmSprintC1)

		-- poses ABSOLUES (le bras gauche est plein détaché de l'arme)
		local poseR = rightBase * swingR * bob
		local poseL = leftBase  * swingL * bob
		WeaponSharedState.PublishWeaponPose(poseL, poseR)
	end

	local function hideCursorWhileAiming()
		-- exception PAR ARME : un Tool avec l'attribut KeepCursorWhileAiming=true
		-- garde TOUJOURS le curseur en visée (ex: minigun), peu importe le réglage joueur.
		local tool = equippedWeaponTool()
		if tool and tool:GetAttribute("KeepCursorWhileAiming") == true then
			return false
		end
		local v = player:GetAttribute("SettingHideCursorAiming")
		if v == nil then return cfg.Sprint.HideCursorWhileAiming end
		return v and true or false
	end

	-- ════════════════════════════════════════════════════════
	-- BOUCLE PRINCIPALE
	-- ════════════════════════════════════════════════════════
	RunService.Heartbeat:Connect(function(dt)
		-- self-heal refs
		if not character or not character.Parent then
			character = player.Character
			humanoid = character and character:FindFirstChildOfClass("Humanoid")
			root = character and character:FindFirstChild("HumanoidRootPart")
		end

		local weaponOK = hasWeapon()

		-- cursor caché pendant la visée. En SORTANT de visée on remet TOUJOURS le cursor
		-- visible (évite qu'il reste caché après la lunette du sniper, où le scope le cache aussi).
		if hideCursorWhileAiming() then
			local aimingNow = weaponOK and (aimInputHeld or WeaponSharedState.IsAiming())
			if aimingNow and not cursorHidden then
				UserInputService.MouseIconEnabled = false
				cursorHidden = true
			elseif (not aimingNow) and cursorHidden then
				UserInputService.MouseIconEnabled = true
				cursorHidden = false
			end
		elseif cursorHidden then
			-- option désactivée en cours de partie → on restaure le curseur immédiatement
			UserInputService.MouseIconEnabled = true
			cursorHidden = false
		end

		-- bascule visibilité boutons mobile
		if mechGui and cfg.Mobile.HideWhenNoWeapon then
			mechGui.Enabled = weaponOK
		end

		if not weaponOK or not humanoid or humanoid.Health <= 0 then
			-- pas d'arme → on coupe tout proprement (avec ease-out)
			sprinting = false
			sliding = false
			if character then character:SetAttribute("WeaponSliding", false) end
			sprintAlpha += (0 - sprintAlpha) * math.clamp(dt * cfg.Sprint.BlendOut, 0, 1)
			currentRoll += (0 - currentRoll) * math.clamp(dt * cfg.Slide.RollSpeed, 0, 1)
			WeaponSharedState.SetSprinting(false)
			WeaponSharedState.SetSprintAlpha(sprintAlpha)
			WeaponSharedState.SetActionsBlocked(false)
			WeaponSharedState.PublishMoveFOV(sprintAlpha * cfg.Sprint.FOVKick)
			if mechFOVActive then mechFOVActive = false; player:SetAttribute("MechanicsFOVActive", nil) end
			WeaponSharedState.PublishCameraRoll(currentRoll)
			computeArmPoses(dt, sprintAlpha)
			updateSpeedLines(sprintAlpha)
			if humanoid then applyWalkSpeed() end
			return
		end

		local now = os.clock()

		-- ── ATTERRISSAGE : un slide bufferisé en l'air se déclenche en touchant le sol ──
		local airborne = humanoid.FloorMaterial == Enum.Material.Air
		if wasAirborne and not airborne and now < slideBufferUntil then
			slideBufferUntil = 0
			WeaponMechanics._tryStartSlide()
		elseif wasAirborne and not airborne and slideKeyHeld and not sliding then
			-- 🆕 touche slide MAINTENUE en l'air : slide dès l'atterrissage
			local R = Boost.SlideRules()
			if R and R.HoldToSlideOnLanding ~= false then WeaponMechanics._tryStartSlide() end
		end
		wasAirborne = airborne
		-- 🆕 slide mémorisé (pendant la relève) : il part dès que c'est permis
		if slideBufferUntil > 0 and now < slideBufferUntil and not sliding and not airborne
			and now >= slideCooldownUntil and Boost.SlideRules() then
			slideBufferUntil = 0
			WeaponMechanics._tryStartSlide()
		end

		-- ── état SPRINT ──
		local wantSprint = cfg.Sprint.Enabled and sprintHeld and not sliding
		if wantSprint and now < suppressedUntil then wantSprint = false end   -- pause courte après un tir
		if wantSprint and (WeaponSharedState.IsAiming() or aimInputHeld) then wantSprint = false end  -- pause TANT qu'on vise (reprise au relâché)
		local firingNow = fireInputHeld or WeaponSharedState.IsFiring()
		if prevFiring and not firingNow then
			fireSuppressUntil = now + cfg.Sprint.RecoverTime   -- reprise smooth après la rafale
		end
		prevFiring = firingNow
		if wantSprint and (firingNow or now < fireSuppressUntil) then wantSprint = false end
		if wantSprint and cfg.Sprint.RequireMoving then
			local md = humanoid.MoveDirection
			if md.Magnitude < 0.1 then
				wantSprint = false
			elseif cfg.Sprint.ForwardOnly and root then
				local fwd = root.CFrame.LookVector
				fwd = Vector3.new(fwd.X, 0, fwd.Z)
				if fwd.Magnitude > 0.01 and md.Unit:Dot(fwd.Unit) < 0.5 then wantSprint = false end
			end
		end
		sprinting = wantSprint
		WeaponSharedState.SetSprinting(sprinting)
		WeaponSharedState.SetActionsBlocked(cfg.Sprint.BlocksActions and sprinting)

		-- alpha d'anim
		local targetA = sprinting and 1 or 0
		local spd = sprinting and cfg.Sprint.BlendIn or cfg.Sprint.BlendOut
		sprintAlpha += (targetA - sprintAlpha) * math.clamp(dt * spd, 0, 1)
		WeaponSharedState.SetSprintAlpha(sprintAlpha)

		applyWalkSpeed()
		computeArmPoses(dt, sprintAlpha)
		updateSpeedLines(sprintAlpha)

		-- FOV : publié si armé (la boucle Feel l'ajoute), sinon appliqué ici
		local fovKick = sprintAlpha * cfg.Sprint.FOVKick + Boost.FOV()   -- 🆕 FOV de vitesse
		if WeaponSharedState.AnyEquipped() then
			WeaponSharedState.PublishMoveFOV(fovKick)
		else
			WeaponSharedState.PublishMoveFOV(0)
			-- 🩹 + FOV de la zipline (comme le WeaponController) : les deux visent la même valeur
			local target = cfg.Sprint.HipFOV + fovKick + (player:GetAttribute("ZiplineFOVAdd") or 0)
			-- 🩹 On n'écrit le FOV que pendant NOTRE effet (sprint / vitesse) et le temps de revenir.
			--    Avant : ramené à 70 à CHAQUE image dès qu'une arme était dans le sac → ça se battait
			--    avec le zoom d'achat, le boost du jetpack et la zipline (zoom / dézoom).
			--    Jetpack en main : c'est lui qui pilote le FOV.
			local cam = (character and character:GetAttribute("JetpackFOV")) and nil or workspace.CurrentCamera
			if cam and (fovKick > 0.01 or mechFOVActive) then
				cam.FieldOfView += (target - cam.FieldOfView) * math.clamp(dt * 10, 0, 1)
				local still = fovKick > 0.01 or math.abs(target - cam.FieldOfView) > 0.05
				if not still then cam.FieldOfView = target end
				if still ~= mechFOVActive then
					mechFOVActive = still
					player:SetAttribute("MechanicsFOVActive", still or nil)
				end
			end
		end

		-- SLIDE + roll
		updateSlide(dt)
		WeaponSharedState.PublishCameraRoll(currentRoll)
	end)

	-- ════════════════════════════════════════════════════════
	-- ROLL CAMÉRA (1re pers / sans arme équipée)
	-- En 3e pers avec arme : c'est la caméra du WeaponController qui applique le roll.
	-- Priorité Camera+1 → le viewmodel (déplacé en Camera+2) suit l'inclinaison.
	-- ════════════════════════════════════════════════════════
	RunService:BindToRenderStep("WeaponMechRoll", Enum.RenderPriority.Camera.Value + 1, function()
		if math.abs(currentRoll) < 1e-4 then return end
		if WeaponSharedState.AnyEquipped() and WeaponSharedState.IsThirdPersonLock() then return end
		camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, currentRoll)
	end)

	-- ════════════════════════════════════════════════════════
	-- POSE DE SLIDE PROCÉDURALE (locale) — couché, torse relevé, jambe pliée.
	-- On écrit Transform APRÈS l'animator (RenderStep) → ça l'emporte sur la marche.
	-- ════════════════════════════════════════════════════════
	RunService:BindToRenderStep("WeaponMechSlidePose", Enum.RenderPriority.Character.Value + 1, function(dt)
		if not cfg.Slide.ProceduralAnim then return end
		local goal = sliding and 1 or 0
		slidePoseAlpha += (goal - slidePoseAlpha) * math.clamp(dt * cfg.Slide.PoseBlend, 0, 1)

		if slidePoseAlpha < 1e-3 then
			-- pose finie : on rend la main à l'animator (une seule remise à zéro)
			if not posedCleared and rootJoint and frontHip and backHip then
				rootJoint.Transform = CFrame.identity
				frontHip.Transform  = CFrame.identity
				backHip.Transform   = CFrame.identity
				posedCleared = true
			end
			return
		end
		posedCleared = false
		if not (rootJoint and frontHip and backHip) then return end
		rootJoint.Transform = CFrame.identity:Lerp(cfg.Slide.RootPose,     slidePoseAlpha)
		frontHip.Transform  = CFrame.identity:Lerp(cfg.Slide.FrontLegPose, slidePoseAlpha)
		backHip.Transform   = CFrame.identity:Lerp(cfg.Slide.BackLegPose,  slidePoseAlpha)
	end)

	-- ════════════════════════════════════════════════════════
	-- MASQUE BRAS (anim de slide, 1re personne, LOCAL) — annule l'influence de l'anim
	-- sur tes bras quand tu es en 1re pers, pour que tes bras restent au bon endroit.
	-- Écrit Transform=identité APRÈS l'animator → local uniquement, les autres voient l'anim.
	-- ════════════════════════════════════════════════════════
	RunService:BindToRenderStep("WeaponMechSlideArms", Enum.RenderPriority.Character.Value + 2, function()
		if cfg.Slide.ProceduralAnim or not cfg.Slide.MaskArmsFirstPerson then return end
		if not (sliding and slideAnimTrack and slideAnimTrack.IsPlaying) then return end
		local head = character and character:FindFirstChild("Head")
		if not head then return end
		local fp = false
		if WeaponSharedState.IsFirstPersonAim() then
			if camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid then
				fp = (camera.CFrame.Position - camera.Focus.Position).Magnitude < 2
			elseif IsMobile and WeaponSharedState.AnyEquipped() then
				fp = true
			else
				local off = humanoid and humanoid.CameraOffset or Vector3.zero
				if root then off = root.CFrame:VectorToWorldSpace(off) end
				fp = (camera.CFrame.Position - off - head.Position).Magnitude < 2
			end
		end
		if not fp then return end
		if rightShoulder then rightShoulder.Transform = CFrame.identity end
		if leftShoulder  then leftShoulder.Transform  = CFrame.identity end
	end)

	-- ════════════════════════════════════════════════════════
	-- INPUT
	-- ════════════════════════════════════════════════════════
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if cfg.Sprint.Enabled and not IsMobile then
			if input.KeyCode == cfg.Sprint.GamepadKey and cfg.Sprint.GamepadToggle ~= false then
				sprintHeld = not sprintHeld   -- 🎮 bascule : reste activé jusqu'au prochain appui
			elseif input.KeyCode == cfg.Sprint.Key or input.KeyCode == cfg.Sprint.GamepadKey then
				sprintHeld = true
			end
		end
		if cfg.Sprint.PauseOnAimInput and input.UserInputType == cfg.Sprint.AimInputButton then
			aimInputHeld = true   -- visée maintenue → le sprint se met en pause
		end
		if cfg.Sprint.PauseOnFireInput and input.UserInputType == cfg.Sprint.FireInputButton then
			fireInputHeld = true  -- tir maintenu → le sprint se met en pause
		end
		if cfg.Slide.Enabled then
			if input.KeyCode == cfg.Slide.Key or input.KeyCode == cfg.Slide.GamepadKey then
				slideKeyHeld = true   -- 🆕
				WeaponMechanics._tryStartSlide()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		-- 🆕 touche / bouton slide relâché
		if input.KeyCode == cfg.Slide.Key or input.KeyCode == cfg.Slide.GamepadKey
			or (slideTouch and input == slideTouch) then
			slideKeyHeld = false; slideTouch = nil
		end
		if cfg.Sprint.Enabled and not IsMobile then
			if input.KeyCode == cfg.Sprint.Key
				or (input.KeyCode == cfg.Sprint.GamepadKey and cfg.Sprint.GamepadToggle == false) then
				sprintHeld = false
			end
		end
		if input.UserInputType == cfg.Sprint.AimInputButton then
			aimInputHeld = false   -- visée relâchée → reprise du sprint si Shift tenu
		end
		if input.UserInputType == cfg.Sprint.FireInputButton then
			if fireInputHeld then fireSuppressUntil = os.clock() + cfg.Sprint.RecoverTime end
			fireInputHeld = false  -- tir relâché → reprise après le mini cooldown
		end
	end)

	-- Saut → annule le slide (PC, mobile et manette ; l'élan est conservé)
	UserInputService.JumpRequest:Connect(function()
		if sliding and cfg.Slide.CancelOnJump then endSlide("jump") end
	end)

	-- Tir / ADS → pause (ou rien si BlocksActions, géré côté arme)
	WeaponSharedState.CancelSprintRequested:Connect(function()
		if cfg.Sprint.BlocksActions then return end
		suppressedUntil = os.clock() + cfg.Sprint.RecoverTime
		sprinting = false
		-- on garde sprintHeld (le lock mobile reste) → reprise après la pause
	end)

	-- ════════════════════════════════════════════════════════
	-- CYCLE DE VIE PERSO
	-- ════════════════════════════════════════════════════════
	local function onCharacter(char)
		character = char
		-- Pont local MechanicsClient -> contrôleurs d'armes ; republié à chaque vie.
		local lean = cfg.Slide.WeaponLean
		character:SetAttribute("WeaponSlideLeanEnabled", lean.Enabled ~= false)
		character:SetAttribute("WeaponSlideLeanAngle", math.clamp(lean.Angle, -60, 60))
		character:SetAttribute("WeaponSlideLeanIn", math.clamp(lean.InTime, 0.03, 1))
		character:SetAttribute("WeaponSlideLeanOut", math.clamp(lean.OutTime, 0.03, 1))
		humanoid = char:WaitForChild("Humanoid")
		root = char:WaitForChild("HumanoidRootPart")
		baseWalkSpeed = cfg.BaseWalkSpeed or humanoid.WalkSpeed
		lastAppliedSpeed = nil   -- repart propre : adopte la vitesse actuelle à la 1re frame
		-- joints R6 pour la pose de slide procédurale (nil-safe si rig différent)
		local torso = char:FindFirstChild("Torso")
		rootJoint = root:FindFirstChild("RootJoint")
		local fl = (cfg.Slide.FrontLeg == "Left") and "Left" or "Right"
		frontHip = torso and torso:FindFirstChild(fl.." Hip")
		backHip  = torso and torso:FindFirstChild(((fl == "Right") and "Left" or "Right").." Hip")
		rightShoulder = torso and torso:FindFirstChild("Right Shoulder")
		leftShoulder  = torso and torso:FindFirstChild("Left Shoulder")
		slidePoseAlpha = 0; posedCleared = true
		-- reset état
		character:SetAttribute("WeaponSliding", false)
		sprinting=false; sliding=false; sprintAlpha=0; currentRoll=0; bobPhase=0
		camLowerApplied=false; slideAnimTrack=nil; aimInputHeld=false; fireInputHeld=false; fireSuppressUntil=0
		slideBufferUntil=0; wasAirborne=false
		slideDustAtt = nil   -- nouveau corps → l'émetteur sera recréé
		if cursorHidden then UserInputService.MouseIconEnabled = true end
		cursorHidden=false
		-- 🆕 MOBILE : le sprint verrouillé survit à la mort (plus besoin de recliquer)
		if IsMobile then
			if cfg.Mobile.KeepSprintOnRespawn then
				sprintHeld = player:GetAttribute(SPRINT_LOCK_ATTR) == true   -- 🆕 relu après la mort
			else
				sprintHeld = false
			end
			setSprintBtnVisual(sprintHeld)
		end
		WeaponSharedState.PublishWeaponPose(CFrame.new(), CFrame.new())
		WeaponSharedState.PublishMoveFOV(0)
		WeaponSharedState.PublishCameraRoll(0)
		WeaponSharedState.SetSprinting(false)
		WeaponSharedState.SetActionsBlocked(false)
		WeaponSharedState.SetAiming(false)
		if IsMobile then buildMobileUI() end
		buildSpeedLines()
	end

	if player.Character then onCharacter(player.Character) end
	player.CharacterAdded:Connect(onCharacter)
end

return WeaponMechanics