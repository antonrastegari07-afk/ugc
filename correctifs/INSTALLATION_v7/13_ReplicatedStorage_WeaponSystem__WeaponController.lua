-- ============================================================
-- WeaponController  (ModuleScript)
-- Emplacement : ReplicatedStorage/WeaponSystem/WeaponController
-- ============================================================
-- Cerveau client COMMUN à toutes les armes.
-- Chaque arme a une LocalScript "Client" dans son Tool qui fait :
--     require(WeaponController).Setup(script.Parent, CONFIG)
--
-- Tout l'état est encapsulé dans Setup() (closure par arme) → aucune
-- collision de variables entre armes quand on switch.
--
-- Sous-systèmes pilotés par le CONFIG :
--   • Caméra ThirdPersonLock (shift-lock) + FirstPersonAim
--   • Curseur / hit markers / texte reload
--   • Viewmodel 1re personne (bras + gun dans la caméra)
--   • ADS (viser) : aligne l'AimPoint de l'arme au centre de l'écran
--   • Feel procédural : recul + sway + punch caméra
--   • Reload : Simple | Keyframe | Shell (balle/balle)
--   • Autoshoot mobile : Simple | Delay (avec barre de charge)
--   • FX locaux : tracer / douille / lumière de bouche
--   • HUD AmmoHud + chips clavier
-- ============================================================
local WeaponController = {}
-- 🧪 accès pour l'Anim Studio (tir à blanc de l'onglet RECUL), une entrée par Tool
WeaponController.Tools = setmetatable({}, { __mode = "k" })
local Players          = game:GetService("Players")
local DebrisService    = game:GetService("Debris")
local SoundService     = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local PhysicsService   = game:GetService("PhysicsService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local AimPivotSettings = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("AimPivotSettings"))
local WeaponSharedState = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponSharedState"))
local RocketFX          = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("RocketFX"))
local WeaponVFX = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponVFX"))
-- 🆕 douilles qui rebondissent · éclair varié · anneau de rechargement · pièces
local FX2 = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponFX2"))
-- [Combat C1] réglages de combat (CombatSettings) + manette (CombatInput) — absents = ajouts coupés
local CS, CI
do
	local wsF = script.Parent
	local a, b
	for _ = 1, 50 do
		a, b = wsF:FindFirstChild("CombatSettings"), wsF:FindFirstChild("CombatInput")
		if a and b then break end
		task.wait(0.1)
	end
	CS = a and require(a) or { Enabled = false }
	CI = b and require(b) or { IsGamepad = function() return false end, AimSlowdownFactor = function() return 1 end }
	if not (a and b) then warn("[Combat] CombatSettings / CombatInput introuvables : ajouts de combat coupés") end
end
-- [Combat MK0] série de kills partagée entre toutes les armes : le son de kill classique se tait dès le 2e kill
WeaponController.Streak = { n = 0, last = 0 }
do
	local lp = Players.LocalPlayer
	local st = WeaponController.Streak
	if lp then
		lp.CharacterAdded:Connect(function() st.n = 0 end)
		lp:GetAttributeChangedSignal("InArena"):Connect(function()
			local MK = CS.MultiKill
			if lp:GetAttribute("InArena") ~= true and (not MK or MK.ResetOnLeaveArena ~= false) then st.n = 0 end
		end)
	end
end
-- Collision group viewmodel (une seule fois)
pcall(function() PhysicsService:RegisterCollisionGroup("Viewmodel") end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable("Viewmodel", "Default",   false)
	PhysicsService:CollisionGroupSetCollidable("Viewmodel", "Viewmodel", false)
end)
-- ── Merge récursif des défauts ──────────────────────────────
local function deepDefault(dst, src)
	dst = dst or {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = deepDefault(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end
local DEFAULTS = {
	LiveFeel = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponFeelConfig")),
	Damage = 20, FireRate = 1/10, Range = 1000,
	MinSpread = 0, MaxSpread = 0, AimInaccuracyStepAmount = 0,
	ClipSize = 30, SpareAmmo = 300,
	FireMode = "Auto", Pellets = 1, CritThreshold = 40,   -- (CritThreshold n'est plus utilisé pour la couleur)
	-- 🆕 semi-auto : maintenir le tir continue de tirer au rythme du FireRate.
	--    OFF par défaut : seules les armes qui mettent SemiHoldFire = true
	--    dans leur CONFIG en profitent (ex. le Magnum).
	SemiHoldFire = false,
	-- ════════ HEADSHOT ════════
	-- Le ROUGE des nombres de dégâts est maintenant RÉSERVÉ aux headshots
	-- (avant : tout dégât >= CritThreshold devenait rouge).
	Headshot = {
		Enabled = true,
		Multiplier = 2.0,           -- dégâts = Damage × Multiplier (arrondi)
		IncludeAccessories = true,  -- casque / cheveux soudés à la tête = headshot
		Color = Color3.fromRGB(255, 45, 45),   -- couleur du nombre de dégâts
		TextSize = 34,              -- taille du nombre (dégât normal = 24)
		Pop = 0.45,                 -- petit "pop" de taille du nombre (0 = off)
		Sound = "HeadshotSound",    -- Sound dans SoundService (retombe sur HitSound si absent)
		-- petit effet SATISFAISANT sur le curseur
		Marker = {
			Enabled = true,
			Color = Color3.fromRGB(255, 60, 60),
			Ring = true,            -- anneau qui s'ouvre autour du curseur
			RingSize = 46,          -- diamètre final (px)
			RingThickness = 3,
			SpikeLength = 14,       -- 4 pointes diagonales qui s'écartent
			SpikeThickness = 3,
			SpikeOffset = 16,
			Life = 0.35,            -- durée totale (s)
			CrosshairPunch = 1.35,  -- "pop" du crosshair (1 = off)
		},
	},
	CustomCursorID = "rbxassetid://11528834413",
	--CustomCursorID = "http://www.roblox.com/asset/?id=426730675",
	-- 🆕 CROSSHAIR SCRIPTÉ + INTERRUPTEUR GLOBAL DU BLOOM
	--   • Scripted = false → ton curseur image d'avant, précision exacte.
	--   • en jeu, sans redémarrer, pour TOUTES les armes :
	--       workspace:SetAttribute("WeaponDynamicSpread", false)   -- coupe TOUT
	--       workspace:SetAttribute("WeaponScriptedCrosshair", false) -- juste le viseur
	--     (les attributs, s'ils existent, l'emportent sur le config)
	Crosshair = {
		Scripted    = false,  -- ⛔ OFF : ton curseur image, comme avant
		FollowMouse = true,   -- en 1re personne il colle à la souris (sans retard)
		HideInScope = true,   -- caché quand la lunette est à l'œil
		-- 🆕 LISSAGE. La dispersion saute (un tir = un bond) ; l'écartement du
		-- viseur, lui, ne doit pas sauter. Il s'ouvre vite et se referme
		-- doucement — c'est ce que l'œil attend d'un viseur.
		OpenSpeed   = 26,     -- vitesse d'OUVERTURE (nerveuse : le tir se voit)
		CloseSpeed  = 9,      -- vitesse de FERMETURE (posée : la précision revient)
	},
	Cursor = {
		Color = Color3.fromRGB(255,255,255), Outline = Color3.fromRGB(0,0,0),
		LineLength = 8, LineThickness = 2, Gap = 3, DotSize = 2, PCScale = 2,
		HitColor = Color3.fromRGB(255,80,80), HitLength = 6, HitOffset = 10,
		HitThickness = 2,
		-- 🆕 HIT MARKERS : restent visibles puis s'effacent en fondu
		HitHold = 0.10,          -- temps où les marks restent PLEINS à l'écran (s)
		HitFade = 0.70,          -- durée du fondu (s) — plus long = disparition plus douce
		HitFadeStyle = "Sine",   -- courbe du fondu : "Sine" doux · "Quad" · "Linear"
		HitSpreadTime = 0.30,    -- durée du glissement vers la position finale (était 0.14)
		HitSpreadStyle = "Quad", -- 🆕 courbe du glissement : "Sine" régulier · "Quad" · "Quart" nerveux
		HitHeadTimeMult = 1.25,  -- headshot : maintien + fondu × ce nombre
		-- ÉCARTEMENT (× HitOffset). Départ → arrivée. Plus proche de 1 = reste collé au curseur.
		-- les marks partent un peu loin et se RAPPROCHENT du curseur
		HitStart      = 1.6,     -- départ d'un hit normal
		HitSpread     = 1.1,     -- arrivée d'un hit normal (proche du curseur)
		HitStartHead  = 1.9,     -- départ d'un headshot (de plus loin = plus intense)
		HitSpreadHead = 1.2,     -- arrivée d'un headshot
		-- 🆕 l'effet anneau + pointes joue AUSSI sur les hits normaux, en plus doux
		HitRingNormal = true,
		HitRingScale  = 0.7,     -- taille de l'effet normal (× celle du headshot)
		HitPunchScale = 0.5,     -- force du « pop » du viseur en hit normal (× headshot)
		HitHeadTimeMult = 1.25,  -- headshot : maintien + fondu × ce nombre
	},
	-- 🔻 NERF : rayon d'écran plus petit + traction ~2× plus faible
	-- 🔻 nerf LÉGER (mobile uniquement — le PC n'utilise jamais cette section)
	AimAssist = { Enabled = true, Radius = 85, Strength = 0.14,
		Deadzone = 4, TargetHeight = 1.5, MaxDistance = 600 },
	-- ── SNAP ASSIST : rayon ÉCRAN autour du curseur ──
	-- Le rayon est un % de la HAUTEUR d'écran → PROPORTIONNEL : il occupe la
	-- même fraction de l'écran sur toutes les résolutions/appareils (jamais
	-- plus gros ni plus petit). Rayon réglable séparément PC / mobile.
	-- Si un ennemi est dans ce rayon au moment du tir (ou de l'autoshoot),
	-- la balle est redirigée sur lui → touche même si le curseur n'est pas
	-- exactement dessus.
	SnapAssist = {
		Enabled = true,
		EnabledPC     = true,
		EnabledMobile = true,
		-- ═══ PC : buff LÉGER (rayon +40 %, portée utile ~+40 %) ═══
		RadiusScalePC    = 0.028,   -- était 0.020
		MaxDistance      = 1200,    -- était 1000
		MinDistance      = 0,
		Strength         = 1,
		MinRadiusScalePC = 0.0015,  -- était 0.0005
		MinStrength      = 1,
		ExcludeHead      = false,
		-- ═══ MOBILE : buff MODÉRÉ (reste au-dessus du PC) ═══
		RadiusScaleMobile    = 0.048,  -- était 0.030
		MinRadiusScaleMobile = 0.005,  -- était 0.0025
		ExcludeHeadMobile    = false,
		MaxDistanceMobile    = 1200,
		RequireLineOfSight = true,
		TargetParts = "All",
		TargetPriority = "Cursor",
		IncludeEgglons = true,
		-- ── Falloff PC : assist plein 2× plus loin, coupure 550 au lieu de 400 ──
		Falloff = {
			Enabled = true,
			FullUntil = 110,   -- était 60
			ZeroAt    = 550,   -- était 400
			Curve     = 1.35,  -- était 1.5 (décroissance plus douce)
		},
		-- ── Falloff MOBILE (buff modéré, écrase le Falloff PC sur mobile) ──
		FalloffMobile = {
			FullUntil = 150,
			ZeroAt    = 700,
			Curve     = 1.25,
		},
		-- ── Cercle simple (sans debug) ──
		ShowRadius = false,
		Ring = {
			Color = Color3.fromRGB(255, 255, 255),
			Thickness = 2,
			Transparency = 0.55,
		},
		-- ── Cercle du rayon PLANCHER (aimbot minimal) ──
		ShowMinRadius = false,
		MinRing = {
			Color = Color3.fromRGB(120, 200, 255),
			Thickness = 2,
			Transparency = 0.45,
		},
		-- ── DEBUG TEMPS RÉEL ──
		Debug = {
			Enabled = false,
			DynamicRing = true,
			ShowLine = true,
			ShowDot = true,
			ShowText = true,
			LockColor = Color3.fromRGB(255, 70, 70),
			LineThickness = 1,
			DotSize = 6,
		},
	},
	Feel = {
		RecoilKickBack = 0.30, RecoilKickUp = 0, RecoilRecover = 9,
		CamUp = 0, CamSide = 0,
		Sway = { Pos = 0.06, Rot = math.rad(3), Speed = 8 },
		-- 🆕 un joueur au doigt ne peut pas compenser un recul pensé pour une souris
		MobileRecoilScale = 0.55,   -- × tout le recul sur mobile (1 = identique au PC)
	},
	ADS = {
		Enabled = true, FOV = 65, HipFOV = 70, LerpSpeed = 12,
		AimPointName = "AimPoint",
		-- Pivot procédural : Attachment dans Handle, placé au centre du viseur.
		UseAimPivot = true,
		AimPivotName = "AimPivot",
		AimPivotOffset = nil,       -- CFrame local au Handle, prioritaire sur l'Attachment
		DisableAllAimMotion = false, -- true = aucun mouvement procédural de l'arme en ADS
		PivotMotionScale = 1,
		PivotTranslationScale = 0.6, -- radians par stud : translation convertie en rotation
		PivotMaxAngle = math.rad(4), -- limite par axe des réactions de déplacement

		AimDepth = 0.6,             -- distance du viseur devant l'œil (collé → on regarde dedans)
		AimXOffset = 0, AimYOffset = 0,  -- viseur pile au centre (ajuste si besoin)
		AimRot = nil,               -- rotation additionnelle en visée (méthode AimPoint), ex: CFrame.Angles(0,0,math.rad(2))
		VMOffset = CFrame.new(0, -0.9, -0.6),  -- repli sans AimPoint : arme relevée/centrée (position + rotation, à régler en live)
		SwayReduce = 0.7,
		AimSway = true,             -- garder les micro-mouvements (sway) en visée (false = arme stable)🆕🆕🆕🆕🆕🆕🆕🆕🆕🆕🆕
		SensitivityScale = 0.6,     -- sensibilité souris réduite en visée (1re pers)
		RecoilScale = 0,            -- part du recul qui DÉPLACE l'arme en visée (0 = aucun → flash fixe)
		FireFOVScale = 0.3,         -- atténuation du punch de FOV en visée
		-- Recul en visée : ARRIÈRE + LATÉRAL uniquement. Le flash reste centré.
		-- Side est monté (0.005 → 0.02) : c'est lui qui porte tout le recul
		-- maintenant que le vertical est coupé.
		-- Recul en visée : UNIQUEMENT vers l'ARRIÈRE, dans l'axe de visée.
		-- Ni vertical, ni latéral. Le canon recule vers toi puis revient.
		Recoil = { Back = 0.10, Side = 0, Up = 0, Decay = 15, Max = 0.25 },
		-- 🆕 verrouille X (côté) et Y (vertical) à 0, quoi que dise le config de l'arme
		RecoilAxisOnly = true,
		-- 🆕 zéro inclinaison due au déplacement, en visée seulement
		NoMoveTilt = false,                                                                  --🆕🆕🆕🆕🆕🆕🆕🆕🆕🆕🆕 
		Scope = false,              -- true = vraie lunette (cache gun+bras, overlay)
		ScopeFOV = 20,              -- FOV en lunette (sniper)
		ScopeSpeed = 26,            -- entrée/sortie de lunette ultra-responsive
		ScopeTint = Color3.fromRGB(0,0,0),
	},
	Viewmodel = { Enabled = true, Offset = CFrame.new(0, -1.5, 0), FirstPersonDist = 1.5,
		-- épaisseur des bras du viewmodel : X = largeur, Z = profondeur, Y = longueur.
		-- <1 = plus fins. Garde Y = 1 (sinon la main se décale du gun).
		ArmScale = Vector3.new(0.6, 1.15, 0.6),
	},
	-- Bob procédural au SAUT (montée → bras bas / apex → retour / chute → bras haut /
	-- atterrissage → coup vers le bas puis petits rebonds amortis). Studs / radians.
	JumpBob = {
		Enabled = true,
		AirFollow = 0.006,    -- combien les bras "lag" la vitesse verticale
		AirMax    = 0.25,     -- déplacement vertical max en l'air (studs)
		AirSmooth = 7,        -- ⬇️ 12 → 7 : la montée et l'apex arrivent en douceur
		--    au lieu de coller à la vitesse image par image
		TiltR     = 0.5,      -- inclinaison du bras droit selon l'offset (rad/stud)
		TiltL     = 0.35,     -- inclinaison du bras gauche
		LandImpulse   = 3.2,  -- ⬇️ 4.0 → 3.2 : le coup à l'atterrissage est moins sec
		LandStiffness = 95,   -- ⬇️ 180 → 95 : ressort plus lent, donc plus lisible
		LandDamping   = 17,   -- ⬆️ 13 → 17 : quasi critique — UNE descente propre,
		--    plus de petits rebonds qui font "cassé"
		LandBlend  = 9,       -- 🆕 vitesse à laquelle l'offset de vol se résorbe
		--    après l'atterrissage (au lieu de tomber à 0 net)
		AimScale  = 0.5,      -- × intensité en visée (0 = figé quand on vise)
	},
	-- ── IDLE : micro-respiration quand on ne bouge pas (hors visée) ──
	-- Amplitudes en STUDS : garde-les minuscules, c'est ce qui sépare
	-- "vivant" de "ivre". Ton AK a déjà ce bloc, il n'était jamais lu.
	Idle = {
		Enabled = true,
		Speed = 0.85,               -- cycles/s (rythme de respiration)
		BobY = 0.007,               -- haut/bas
		BobZ = 0.0035,              -- avant/arrière
		BobX = 0.0025,              -- latéral, déphasé → trajectoire en "8" très lente
		RotPitch = math.rad(0.35),
		RotRoll  = math.rad(0.22),
		RotYaw   = math.rad(0.18),
		Blend = 4,                  -- vitesse d'apparition / disparition
	},
	Equip = {
		Enabled = true,
		Time = 0.28,                 -- court & nerveux
		BlockFireDuring = false,      -- pas de tir pendant le draw (standard compétitif)
		-- pose de départ (offset C1, à régler au tuner comme ton ADS/sprint)
		FromR = CFrame.new(0.10, -0.60, 0.25) * CFrame.Angles(math.rad(35), math.rad(-12), math.rad(6)),
		FromL = CFrame.new(0.08, -0.70, 0.20) * CFrame.Angles(math.rad(32), math.rad(8), 0),
		-- 🆕 R3 : DÉPASSEMENT à la sortie d'arme. Une arme lourde qu'on lève
		-- dépasse un peu puis se pose. 0 = ancien comportement (arrêt net).
		Overshoot = 0.12,
		-- 🆕 ARMEMENT : la main gauche tire le levier après la sortie d'arme.
		-- Une arme qui déclare LeftGrab l'active automatiquement.
		Cock = {
			Enabled = true,
			Time = 0.45,
			OnlyFirstEquip = true,  -- une seule fois par vie (se réarme au respawn)
			-- 🆕 ARMEMENT APRÈS CHAQUE TIR (verrou de sniper, levier de carabine).
			-- Réutilise EXACTEMENT les mêmes poses que l'armement de sortie
			-- d'arme : tu règles l'animation une fois dans l'éditeur, elle sert
			-- aux deux.
			AfterShot = false,      -- true → l'arme se réarme après chaque coup
			AfterShotDelay = 0,  -- temps avant que la main parte au levier
			AfterShotTime = nil,    -- durée propre (sinon on reprend Time)
			Sound = nil,            -- Sound dans le HANDLE, joué au début du tirage
			SoundRelease = nil,     -- joué quand la culasse claque en avant
			LeftGrab    = nil,      -- main gauche sur le levier
			PullBack    = nil,      -- levier tiré à fond
			RightGuide  = nil,      -- léger cant de l'arme pendant le tirage
			RightSettle = nil,      -- pose de fin du bras droit
		},
	},
	-- 🆕 INSPECTION : l'animation « je regarde mon arme ». Touche V (PC) ou le
	-- petit bouton mobile. Elle se relance depuis le début si tu la respammes,
	-- et le tir ou le rechargement la coupent net.
	Inspect = {
		Enabled = false,
		Time = 2.2,
		Keyframes = nil,        -- rempli par l'Anim Studio (animation INSPECTION)
		SoundTrack = nil,
		GunTrack = nil,
		BlockFire = false,      -- true = pas de tir tant que l'inspection tourne
		FirstPersonOnly = false, -- 👁 false = l'inspection marche aussi en 3e personne
		CancelTime = 0.12,      -- 🩹 durée du retour en position de tir quand on
		--    coupe l'inspection (tir, rechargement…)
	},
	Reload = {
		Style = "Simple", Time = 2,
		Keyframes = nil,
		TimePerShell = 0.5,
		-- 🆕 à quel moment du geste la cartouche entre VRAIMENT dans l'arme
		-- (0 = au début, 1 = à la fin). C'est ce qui fait monter la jauge en
		-- même temps que ton animation.
		ShellAt = 0.5,
		-- 🆕 TIRER PENDANT UN RECHARGEMENT CARTOUCHE PAR CARTOUCHE.
		--   ShellCancelOnFire : le tir interrompt le rechargement ; le joueur
		--     garde les cartouches déjà entrées et tire immédiatement.
		--   ShellCancelEmpty  : est-ce qu'on peut aussi l'interrompre quand
		--     l'arme était VIDE ? Non par défaut : il faut chambrer, sinon
		--     l'arme resterait à vide, cartouches dedans, sans pouvoir tirer.
		--   EmptyShellSpeed   : pour compenser, un rechargement à vide joue les
		--     cartouches PLUS VITE (1.35 = 35 % plus rapide). Le pompage de
		--     chambrage final, lui, garde sa vitesse : c'est le geste qui donne
		--     le poids, on ne l'expédie pas.
		ShellCancelOnFire = true,
		ShellCancelEmpty  = false,
		EmptyShellSpeed   = 1.35,
		GunPose  = CFrame.new(-0.15, -0.08, 0.20) * CFrame.Angles(math.rad(-14), math.rad(12), 0),
		HandDown = CFrame.new(0.12, -0.85, 0.20) * CFrame.Angles(math.rad(40), 0, 0),
		HandPort = CFrame.new(0, -0.20, 0.05)   * CFrame.Angles(math.rad(10), 0, 0),
		Rack = 0.12,
		PumpAfterShot = nil,   -- table {Delay,Time,Grab,Back,Sound} → pompe après tir (shotgun)
	},
	-- ════════ LANCE-ROQUETTE (projectile) — Enabled=false pour les autres armes ════════
	Rocket = {
		Enabled = false,
		Speed = 200,                 -- studs/s
		Gravity = 0,                 -- 0 = ligne droite ; >0 = arc (chute)
		MaxLife = 6,                 -- durée de vie max (s)
		ArmTime = 0.05,              -- délai avant explosion (évite l'explosion au canon)
		MissileModelName = "Part",   -- Model dans le Tool qui contient Missile + Rocketlauncher
		MissileName = "Missile",     -- sous-Model qui part
		BoosterName = "Booster",     -- part d'où sortent les flammes
		MissileOrient = CFrame.Angles(80, math.rad(0), 0),-- correction d'orientation du missile en vol (à régler)
		Explosion = {
			Radius = 30,                       -- rayon des dégâts AoE
			MaxDamage = 120,                   -- au centre
			MinDamage = 60,                    -- au bord
			RequireLineOfSight = true,         -- les murs protègent
			SelfDamage = false,                -- l'explosion peut-elle te toucher
			Color = Color3.fromRGB(255,140,40),
			Size = 20,                         -- taille visuelle de l'explosion
			Sound = "Explosion",               -- Sound dans SoundService
			Shake = 1.0,
			Knockback = 150,                    -- force de propulsion de l'onde (0 = off)
			KnockUp = 1,                     -- part verticale ajoutée (rocket jump)
		},
		Booster = {
			Color1 = Color3.fromRGB(255,235,170), Color2 = Color3.fromRGB(255,120,30),
			Size = 1.6, LightColor = Color3.fromRGB(255,150,60),
			LightBrightness = 4, LightRange = 10,
		},
		-- prop de reload : une roquette apparaît dans la main gauche, puis GLISSE
		-- jusqu'à sa place d'origine (position + orientation exactes) pendant l'anim.
		ReloadProp = {
			Enabled = true,
			-- DÉPART : roquette tenue dans la main gauche (offset main→roquette).
			HandOffset = CFrame.new(0, -1.0, 0),
			-- ARRIVÉE : roquette "chargée", exprimée par rapport à la main gauche
			-- au moment où elle charge. À régler en live (voir tuner ci-dessous).
			SeatOffset = CFrame.new(0.6, 0.2, -1.2) * CFrame.Angles(0, math.rad(90), 0),
			SeatAt = 0.82,                        -- fraction du reload où elle est en place (0..1)
			Time = nil,                           -- nil = durée du reload ; sinon force (s)
		},
	},
	-- ════════ DISPERSION DYNAMIQUE ════════
	-- 🔴 GROS INTERRUPTEUR. Deux façons de tout couper :
	--    • ici : Enabled = false → retour EXACT à ton ancien système
	--    • en jeu, sans redémarrer, pour TOUTES les armes :
	--      workspace:SetAttribute("WeaponDynamicSpread", false)
	--      (l'attribut, s'il existe, l'emporte toujours sur le config)
	-- Les valeurs s'AJOUTENT à MinSpread : le cône du shotgun est conservé.
	-- 🔄 CE QU'ON VOIT PENDANT LE RECHARGEMENT
	ReloadHUD = {
		Gauge = true,     -- la jauge à droite du curseur (elle le suit)
		Loop  = false,    -- la petite boucle au centre du curseur
		Text  = true,    -- le mot « Reloading » à droite
	},
	DynamicSpread = {
		Enabled = false,   -- ⛔ OFF : précision exacte, comme avant
		Base      = 0.002,   -- debout, immobile, à la hanche
		Moving    = 0.012,
		Sprinting = 0.030,
		Airborne  = 0.045,   -- en l'air : gros malus (anti bunny-hop)
		ADS       = 0.000,   -- en visée : précision parfaite (valeur absolue)
		PerShot   = 0.004,   -- "bloom" ajouté par balle
		Max       = 0.060,
		Recover   = 0.09,    -- unités récupérées par seconde
		FirstShotDelay = 0.35,  -- après cette pause, la balle suivante est parfaite
		MobileScale = 0.7,
		CrosshairPx = 900,   -- écartement du crosshair par unité (0 = crosshair fixe)
	},
	Autoshoot = "Simple",
	AutoshootHoldTime = 0.15,        -- charge AVANT le premier tir auto
	AutoshootCooldown = 0,           -- plus de temps mort : remplacé par la décharge lente
	AutoshootBurstTime = 0.45,       -- (mode Simple) durée max d'une rafale auto (0 = illimité)
	AutoshootLoseTargetReset = false,-- ⛔ plus de reset brutal
	AutoshootDecayScale = 0.35,      -- 🆕 vidage = 35 % de la vitesse de charge
	AutoshootUseSnapRadius = true,   -- 🆕 déclenche aussi dans le rayon de snap assist
	AutoshootShowBar = true,         -- barre de charge visible AUSSI en mode "Simple"
	FX = {
		Tracer = { Color = Color3.fromRGB(255,213,0), Size = Vector3.new(0.15,0.15,1),
			Transparency = 0.15, Life = 0.05, LightColor = Color3.new(0.996979, 0.993988, 0.589746),
			LightBrightness = 0, LightRange = 0,
			Style = "Classic",                           -- "Rivals" | "Classic"|"Custom"
			-- ── réglages du style Rivals ──
			CoreColor = Color3.fromRGB(246, 203, 51),    -- cœur + tête de la comète
			TrailLength = 100,                           -- longueur de la traîne (studs)
			Speed = 2000,                                -- vitesse visuelle (studs/s)
			AdaptiveSpeed = false ,       -- true = + loin → + vite (plafonné à MaxTravelTime) ; false = vitesse constante
			MaxTravelTime = 0.05,       -- temps MAX pour atteindre la cible, peu importe la distance
			Width = 1.3,                                  -- largeur globale (1 = actuel)
			TailWidth = 0.10,        -- finesse de bout CÔTÉ CANON (× largeur tête). ↓ = plus mince
			TailTransparency = 0,  -- transparence du bout canon (0 = plein/opaque, 1 = invisible)
			SingleBullet = false,                       -- 1 seul tracer en vol (anti "petits points")
			-- 🆕 BALLES TRAÇANTES : 1 tir sur N laisse une traînée (comme en vrai).
			-- Le 1er tir d'une rafale est TOUJOURS tracé. Divise aussi par N le
			-- coût réseau et le rendu. 1 = comme avant.
			EveryN = 0,
			-- 🆕 les X dernières balles du chargeur passent toutes en traçantes
			-- d'une autre couleur (indicateur périphérique). 0 = désactivé.
			LowAmmoAt = 0,
			LowAmmoColor = Color3.fromRGB(255, 60, 40) },
		Shell = { Size = Vector3.new(0.12,0.12,0.32), Color = Color3.fromRGB(196,160,60),
			Material = Enum.Material.Metal, Life = 1.2 },
		-- 🆕 DOUILLES QUI REBONDISSENT ET RESTENT AU SOL.
		--   false = EXACTEMENT ton système d'avant (physique Roblox, la douille
		--   disparaît au bout de Shell.Life). C'est le défaut : tu as trouvé
		--   que ça chargeait trop la connexion, et c'est ton appel.
		ShellBounce = false,
		ShellRest = 6,       -- (si ShellBounce) secondes au sol avant l'effacement
		ShellMax  = 30,      -- (si ShellBounce) nombre à l'écran au maximum
		-- 🆕 ÉCLAIR DE BOUCHE. false = ton flash d'avant, seul et inchangé.
		-- ⛔ OFF : c'est TON effet de bouche qui tourne, inchangé.
		FlashVary = { Enabled = false, Scale = 1, ScaleFP = 0.5 },
		ShellsPerShot = 1,
		-- 🆕 sur une arme qui s'arme après le tir, la douille ne saute PAS au
		-- coup de feu : elle sort quand la culasse recule. C'est ce détail qui
		-- rend un verrou crédible.
		ShellOnCock = true,
		MuzzleLight = { Color = Color3.fromRGB(255,200,120), Brightness = 2.5, Range = 8, Life = 0.06 },
		ViewmodelFlash = { Color1 = Color3.fromRGB(255,235,170), Color2 = Color3.fromRGB(255,150,40),
			SmokeAfter = 0 },
		Impact = {
			Enabled = true, MaxPerVolley = 6, Sparks = true,
			Sound = "ImpactSound1",  -- Sound optionnel dans SoundService (sinon ignoré)
		},
		FireFOVKick = 0.5,  -- léger punch de FOV à chaque tir (feedback)
		KillMarker = {
			Image = "",      --rbxassetid://74046629539502                      -- ← TON IMAGE d'icône de kill (rbxassetid://...)
			Color = Color3.fromRGB(255, 45, 45),   -- couleur du slash/flash (matche le rouge de ton icône)
			Size = 70,                             -- taille de l'icône (px)
			BelowCursor = 0,                      -- décalage sous le curseur (px)
			Sound = "kill",                        -- Sound dans SoundService joué au kill (par nom)
			Hold = 1.2,                           -- temps d'affichage avant le fade
			TintImage = false,                     -- true = teinte ton image avec Color (si elle est blanche)
		},
		-- 🔊 SON DE HIT : entendu UNIQUEMENT par le tireur (joué en local, jamais relayé)
		-- Un seul son par tir, même si plusieurs plombs touchent (pompe).
		HitSound = {
			Enabled = true,
			Name = "HitSound",          -- Sound dans SoundService (par nom)
			HeadshotName = "HeadshotSound", -- son au headshot (si absent → Name)
			Volume = 0.6,
			PitchMin = 0.97, PitchMax = 1.03, -- petite variation à chaque hit
			HeadshotPitch = 1.08,       -- headshot un peu plus aigu (× le pitch)
			MinGap = 0.03,              -- écart minimum entre deux sons (anti empilement en auto)
		},
	},

	-- ── MARCHE (low ready façon CoD MW) : arme baissée + bob synchro pas + inertie ──
	Walk = {
		Enabled = true,
		BlendSpeed = 6,               -- vitesse d'ENTRÉE dans la marche
		ExitSpeed = 20,               -- vitesse de SORTIE (tir/reload/équipe) → retour rapide au ready
		Freq = 1.7,                   -- cadence du balancement (cycles/s ~ pas)
		-- pose "arme baissée"
		LowerPitch = math.rad(8),     -- LÉGER tilt du fusil vers le bas (avant/bras gauche plus bas en diagonale)
		LowerX = 0.13,                -- SURTOUT : décale l'arme sur le CÔTÉ (positif = droite)
		LowerY = -0.015,              -- abaissement quasi nul (ne descend presque plus)
		LowerZ = 0.02,                -- léger recul vers soi
		LowerYaw = math.rad(6),       -- oriente un peu plus l'arme sur le côté
		LowerRoll = math.rad(4),      -- léger cant
		-- amplitudes du bob (petites = militaire, le muzzle ne saute pas)
		SwayX = 0.03,                 -- balancement latéral
		BobY  = 0.018,                -- rebond vertical
		BobZ  = 0.010,                -- avance/recul
		Roll  = math.rad(1.6),        -- roulis par pas
		Yaw   = math.rad(1.2),        -- lacet par pas
		PitchBob = math.rad(0.8),     -- tangage (double fréquence)
		-- inertie : l'arme traîne les mouvements de visée puis rattrape
		InertiaAmount = 0.6,          -- retard TRÈS léger (0 = aucun → l'arme suit la vue direct)
		InertiaRoll = 0.8,            -- part de roulis dans l'inertie
		InertiaCatch = 18,            -- rattrapage rapide → plus de "délai" en tournant
		InertiaMax = math.rad(5),     -- limite du retard
	},

	-- 🆕 PIÈCES DE L'ARME.
	-- Une pièce citée ici peut être animée, décrochée, ou lâchée par terre.
	-- Une pièce ABSENTE du modèle est simplement ignorée : rien ne casse sur
	-- les armes qui sont encore d'un seul bloc. Tu remplis cette table au fur
	-- et à mesure que tes armes gagnent des meshes séparés.
	--
	--   Mag   = { Drop = true, DropAt = 0.28, Life = 8 }
	--           → le chargeur tombe à 28 % du rechargement, reste 8 s au sol
	--   Slide = { LockBack = CFrame.new(0, 0, 0.22) }
	--           → la culasse reste en arrière tant que le chargeur est vide,
	--             et revient d'un coup au rechargement
	Parts = {},
	-- ── MICRO-ANIMATIONS DE VISÉE : léger mouvement en ADS (sinon l'arme est figée) ──
	AimMotion = {
		Enabled = true,
		-- 🫁 RESPIRATION EN VISÉE. Coupée : quand on vise, l'arme doit être
		-- STABLE — c'est le moment où le joueur cherche la précision, et une
		-- oscillation permanente se voit énormément dans une lunette.
		-- Remets Breathing = true si tu veux la retrouver.
		Breathing = false,
		BreathSpeed = 1.1, BreathPos = 0.004, BreathRot = math.rad(0.25),
		-- déplacement gauche/droite (strafe)
		StrafePos = 0.010, StrafeRoll = math.rad(1.4), StrafeSmooth = 8,
		-- saut / chute
		JumpPos = 0.0009, JumpMax = 0.05, JumpSmooth = 10,
		-- tir : la secousse est UNIQUEMENT un recul arrière (axe Z).
		-- Aucune composante verticale (FireKick) ni latérale (FireYaw / FireSide).
		FireKick = 0,
		FireYaw  = 0,
		FireSide = 0,
		FirePos  = 0.010,   -- recul arrière par tir (studs) — le seul mouvement
		FireDecay = 0.07,
	},
	Sounds = { Fire = "FireSound", Reload = "Reload", Equip = "EquipSound" },
	UseRecoilAnim = true,
	-- Icônes des touches affichées dans le HUD (PC). Image SANS fond.
	-- Si l'ID est vide ("") ou "rbxassetid://0", on retombe sur la lettre.
	KeyIcons = {
		Fire = "rbxassetid://131314206833928",  -- ← ton icône de tir (sans fond)
		Aim  = "rbxassetid://123267286461302",               -- ← METS ton icône de visée ici (sans fond)
	},
}
-- ============================================================
function WeaponController.Setup(tool, userConfig)
	local cfg = deepDefault(userConfig, DEFAULTS)
	local TT = cfg.FX.Tracer
	local tracerStyle = {
		Color = TT.Color, Size = TT.Size, Transparency = TT.Transparency,
		LightColor = TT.LightColor, LightBrightness = TT.LightBrightness,
		LightRange = TT.LightRange, Life = TT.Life,
		Style = TT.Style, CoreColor = TT.CoreColor, TrailLength = TT.TrailLength,
		Speed = TT.Speed, Width = TT.Width, MaxTravelTime = TT.MaxTravelTime,
		FarWidthBoost = TT.FarWidthBoost,  AdaptiveSpeed = TT.AdaptiveSpeed, SingleBullet = TT.SingleBullet,
		TailWidth = TT.TailWidth, TailTransparency = TT.TailTransparency,
	}
	-- ID unique pour BindToRenderStep (GetDebugId nécessite la capability Plugin)
	local camRenderName = "WeaponCamera_" .. tool.Name .. "_" .. tostring(math.random(1, 1e9))
	local camRenderBound = false
	local camOwnerToken = {}   -- identité caméra de CETTE arme (WeaponSharedState.ClaimCamera)
	local Handle   = tool:WaitForChild("Handle")
	local Receiver = tool:WaitForChild("Receiver")
	local Flash    = tool:WaitForChild("Flash")
	local IconURL  = tool.TextureId
	local camera   = workspace.CurrentCamera
	local IsMobile = WeaponSharedState.IsMobile()
	-- FILET RESPAWN : au spawn (nouveau clone du tool), si la caméra est restée
	-- figée (Scriptable orpheline / subject mort), on la répare.
	task.defer(function()
		if WeaponSharedState.CameraOwner() ~= nil then return end
		local plr = Players.LocalPlayer
		local char = plr and plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		end
		camera.CameraSubject = hum
	end)
	-- FILET RESPAWN 2 : même réparation à CHAQUE respawn (utile si les tools
	-- survivent à la mort au lieu d'être re-clonés).
	-- ⚡ OPTIM : cette connexion vit sur le JOUEUR, pas sur l'arme. Sans la
	-- couper, chaque respawn (nouvelles armes) en ajoutait une de plus, et
	-- chacune gardait en mémoire TOUT l'état de son ancienne arme.
	local respawnConn
	respawnConn = Players.LocalPlayer.CharacterAdded:Connect(function(newChar)
		if not tool.Parent then respawnConn:Disconnect(); return end
		task.delay(0.2, function()
			if WeaponSharedState.CameraOwner() ~= nil then return end
			local hum = newChar:FindFirstChildOfClass("Humanoid") or newChar:WaitForChild("Humanoid", 5)
			if not hum then return end
			local cam = workspace.CurrentCamera or camera
			if cam.CameraType == Enum.CameraType.Scriptable then
				cam.CameraType = Enum.CameraType.Custom
			end
			cam.CameraSubject = hum
		end)
	end)
	tool.Destroying:Connect(function() respawnConn:Disconnect() end)
	-- ── State ───────────────────────────────────────────────
	local Spread = cfg.MinSpread
	local AmmoInClip = cfg.ClipSize
	local SpareAmmo  = cfg.SpareAmmo
	local LeftButtonDown, Reloading, IsShooting = false, false, false
	local NextAllowedShot = 0   -- 🆕 verrou de cadence, valable pour Semi ET Auto
	local Pumping, pumpToken = false, 0
	local DecreasedAimLastShot = false
	local LastSpreadUpdate = time()
	local AutoShooting = false
	local ConsecutiveShots = 0
	-- Autoshoot délai
	local AutoshootHoldElapsed = 0
	local AutoShootCooldownUntil = 0   -- temps mort entre 2 déclenchements auto
	local AutoShootStart = 0           -- début de la rafale auto en cours
	-- Player
	local MyPlayer, MyCharacter, MyHumanoid, MyMouse, WeaponGui, RecoilTrack
	-- Lecture d'un réglage joueur (attribut) avec valeur par défaut.
	-- Pilote l'arme en live depuis le menu Paramètres (section PVP).
	local function GetSetting(name, default)
		if not MyPlayer then return default end
		local v = MyPlayer:GetAttribute(name)
		if v == nil then return default end
		return v
	end
	-- 🆕 Sensibilité caméra "arme en main" (hors visée). Slider 0-100 %, 50 % = 1×.
	local function GetHipSensMult()
		local v = GetSetting("SettingHipSensitivity", 50)
		if type(v) ~= "number" then v = 50 end
		return math.clamp(0.3 + (v / 100) * 1.4, 0.2, 2)
	end
	-- Sensibilité souris "au repos" (pas en visée) pour MouseDeltaSensitivity.
	-- En ThirdPersonLock (caméra Scriptable) → 1, on multiplie PCMobileSensitivity à la place.
	local function RestingMouseDelta()
		if IsMobile then return 1 end
		if WeaponSharedState.IsThirdPersonLock() then return 1 end
		return GetHipSensMult()
	end
	-- Caméra
	local CameraYaw, CameraPitch = 0, 0
	local CameraDistance, CameraHeight = 11, 2
	local CameraSideOffset, CameraVerticalLift = 3.5, 3.5
	local PitchMin, PitchMax = math.rad(-70), math.rad(70)
	-- Feel
	local LeftArmWeld, RightArmWeld, LeftArmBaseC1, RightArmBaseC1
	local RecoilOffset, ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new(), CFrame.new()
	local EquipOffsetR, EquipOffsetL = CFrame.new(), CFrame.new()
	local Equipping = false
	local JumpOffsetR, JumpOffsetL = CFrame.new(), CFrame.new()
	local jumpVelSmooth, lastVY = 0, 0
	local landSpring, landSpringVel = 0, 0
	local wasAirborneFeel = false
	local CamRecoilPitch, CamRecoilYaw = 0, 0
	local BaseFOV = cfg.ADS.HipFOV
	local FireFOVOffset = 0
	local AimRecoil = Vector3.zero   -- recul en visée (translation caméra-espace : surtout arrière)
	local SwayOffset = CFrame.new()
	local Walk = { Root = CFrame.new(), alpha = 0, phase = 0, velYaw = 0, velPitch = 0, prevCF = nil }
	local Aim = { Motion = CFrame.new(), phase = 0, strafe = 0, jumpV = 0, fireImp = 0, fireSide = 1 }
	local FeelConnection
	-- ADS
	local Aiming, AimAlpha = false, 0
	-- Sensibilités
	local MainDragSensitivity, FireDragSensitivity, PCMobileSensitivity = 0.012, 0.009, 0.005
	local RightDragInput, RightDragLastPos, FireTouchInput, FireTouchLastPos
	-- Caméra sauvegarde
	local SavedCameraOffset, CameraRenderConnection, SavedMouseIconEnabled
	-- Connexions
	local DiedConnection, ModeChangedConnection
	local conns = {}  -- connexions input à couper au unequip
	-- UI mobile
	local MobileFireGui, MobileReloadGui, MobileViewGui, MobileCursorGui, MobileFireButton
	local ChargeBarGui, ChargeBarFill
	-- Effets ennemis (outline rouge + flash au hit + marqueur de kill)
	local EnemyHighlights = {}
	local KillEffectGui
	-- Damage popup
	local DamagePopupContainer, ActivePopups = nil, {}
	-- Viewmodel
	local viewmodel, vmRoot, vmRightWeld, vmLeftWeld, vmRightBaseC1, vmLeftBaseC1
	local vmFlash, vmRenderBound, vmAimPointLocal, vmFlashLocal = nil, false, nil, nil
	local vmBuiltWithGrip = false
	local rocketRelayData = nil   -- params visuels envoyés aux autres clients
	-- Scope (sniper)
	local ScopeGui, ScopeCanvas, ScopeScale
	local ScopeAlpha = 0
	-- Terrain helpers
	local WorldToCell = workspace.Terrain.WorldToCellPreferSolid
	local GetCell     = workspace.Terrain.GetCell
	-- Forward decls
	local FlashHitMarkers, SetReloadingTextVisible, ApplyCurrentMode, SetAiming
	local UpdateAmmo, UpdateCrosshair, OnFire, Reload
	local ControlsHidden, ToggleControls   -- 🆕 toggle affichage des contrôles (touche H)
	local FlashEnemyHit, ShowKillEffect, UpdateEnemyHighlights, ClearEnemyHighlights, IsEnemyPlayer
	local ShowDamagePopup, SetWholeCharacterHidden
	local HardResetVisualState
	local CleanupAllMobileUI
	local Extra -- état partagé avec les boutons mobiles et leur nettoyage
	-- Le Focus de la caméra native suit le sujet ET son CameraOffset. La tête
	-- animée peut être loin pendant un slide sans que le joueur ait dézoomé.
	local function CamToHeadDist()
		if not MyCharacter or not MyHumanoid then return math.huge end
		if WeaponSharedState.IsThirdPersonLock() then return math.huge end
		if camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == MyHumanoid then
			return (camera.CFrame.Position - camera.Focus.Position).Magnitude
		end
		-- Notre caméra mobile Scriptable est explicitement en mode FP.
		if IsMobile and camRenderBound and WeaponSharedState.IsFirstPersonAim() then return 0 end
		local head = MyCharacter:FindFirstChild("Head")
		local root = MyCharacter:FindFirstChild("HumanoidRootPart")
		if not head then return math.huge end
		local off = MyHumanoid.CameraOffset
		if root then off = root.CFrame:VectorToWorldSpace(off) end
		return (camera.CFrame.Position - off - head.Position).Magnitude
	end
	local function IsActuallyFirstPerson()
		if not MyCharacter then return false end
		return WeaponSharedState.IsFirstPersonAim()
			and CamToHeadDist() < cfg.Viewmodel.FirstPersonDist
	end
	-- ========================================================
	-- RAY
	-- ========================================================
	-- la part fait-elle partie d'un perso touchable (Humanoid ou Egglon au-dessus) ?
	local function partIsCharacter(hit)
		local model = hit:FindFirstAncestorWhichIsA("Model")
		while model do
			if model:FindFirstChildOfClass("Humanoid")
				or model:FindFirstChild("Egglon")
				or Players:GetPlayerFromCharacter(model) then   -- filet : perso de joueur même si le Humanoid tarde
				return true
			end
			model = model:FindFirstAncestorWhichIsA("Model")
		end
		return false
	end
	local function RayIgnoreCheck(hit, pos)
		if not hit then return false end
		if hit:IsDescendantOf(MyCharacter) then return true end
		-- 🔫 les balles TRAVERSENT les armes (le Tool tenu par un joueur ou un bot) : une balle qui
		-- touche le fusil d'un ennemi continue jusqu'à son corps, au lieu de s'arrêter « dans le vide »
		-- (avant : la pièce de l'arme comptait comme le perso ou comme un mur → tir perdu)
		if hit:FindFirstAncestorOfClass("Tool") then return true end
		-- FIX : une part d'un PERSO touchable n'est JAMAIS ignorée — même
		-- transparente (HumanoidRootPart) ou non-collidable (membres d'un perso
		-- fraîchement respawn, gérés par le Humanoid). Avant, ce check passait
		-- APRÈS Transparency/CanCollide → les balles traversaient après respawn.
		if partIsCharacter(hit) then return false end
		if hit.Transparency >= 1 or hit.Name == "Effect" or hit.Name == "Rocket"
			or hit.Name == "Bullet" or hit.Name == "Handle"
			or string.lower(hit.Name) == "water" then return true end
		if hit.CanCollide == false then return true end   -- déco / zones
		if hit:IsA("Terrain") and pos then
			local c = WorldToCell(workspace.Terrain, pos)
			if c and GetCell(workspace.Terrain, c.x, c.y, c.z) == Enum.CellMaterial.Water then
				return true
			end
		end
		return false
	end
	local function RayCast(startPos, vec, rayLength)
		local ignore = { Handle, Flash, MyCharacter }
		if viewmodel then table.insert(ignore, viewmodel) end
		local mesh = tool:FindFirstChildWhichIsA("MeshPart")
		if mesh then table.insert(ignore, mesh) end
		local hitObject, hitPos = workspace:FindPartOnRayWithIgnoreList(
			Ray.new(startPos + (vec * 0.01), vec * rayLength), ignore)
		if hitObject and hitPos then
			local d = rayLength - (hitPos - startPos).magnitude
			if RayIgnoreCheck(hitObject, hitPos) and d > 0 then
				return RayCast(hitPos, vec, d)
			end
		end
		return hitObject, hitPos
	end
	local function CreateBullet(p)
		return nil   -- ancien marqueur noir supprimé : plus de part sur les murs
	end
	-- ── HEADSHOT : la part touchée est-elle la tête ? ────────
	-- Gère R6 et R15 ("Head"), et optionnellement les accessoires soudés
	-- à la tête (casque, cheveux) pour éviter les headshots "avalés" par un chapeau.
	local function partIsHead(part)
		if not part then return false end
		if part.Name == "Head" then return true end
		if not cfg.Headshot.IncludeAccessories then return false end
		local acc = part:FindFirstAncestorWhichIsA("Accessory")
		if not acc then return false end
		local h = acc:FindFirstChild("Handle") or part
		for _, j in ipairs(h:GetChildren()) do
			if j:IsA("JointInstance") then
				if (j.Part0 and j.Part0.Name == "Head") or (j.Part1 and j.Part1.Name == "Head") then
					return true
				end
			end
		end
		-- filet : accessoire de tête typique (HatAttachment, HairAttachment, FaceFront...)
		local att = h:FindFirstChildWhichIsA("Attachment")
		if att then
			local n = att.Name:lower()
			if n:find("hat") or n:find("hair") or n:find("face") or n:find("head") then return true end
		end
		return false
	end
	-- ========================================================
	-- FX LOCAUX (chaque client les spawn selon le config)
	-- ========================================================
	local function SpawnLocalTracer(startPos, endPos, fromPart)
		if not WeaponVFX.TracersEnabled() then return end   -- interrupteur global
		-- fromPart = le bout du canon : la traînée reste ACCROCHÉE à l'arme (même en courant)
		WeaponVFX.Tracer(startPos, endPos, tracerStyle, tool, fromPart)   -- tracerStyle = params + style résolu
	end
	-- 🆕 o = les réglages de CETTE éjection (posés dans l'Anim Studio).
	-- Sans o, on retombe sur les valeurs d'avant : rien ne change.
	local function SpawnLocalShell(gunCFrame, o)
		if WeaponVFX.Potato("Shells") then return end   -- 🥔 mode potato : pas de douilles
		-- ⚡ mobile + arme auto : 1 douille sur 2
		if IsMobile and cfg.FireRate < 0.2 then
			Extra.shellSkip = not Extra.shellSkip
			if Extra.shellSkip then return end
		end
		local s = cfg.FX.Shell
		o = o or cfg.FX.ShellDefault or {}
		if o.chance and math.random() * 100 > o.chance then return end
		local sc = o.scale or 1
		-- 🆕 FENÊTRE D'ÉJECTION (« ShellPort »). Si l'arme porte un port — six
		-- attributs posés à la souris dans l'Anim Studio, EN COORDONNÉES DU
		-- HANDLE — la douille part de LÀ, et « vers où » n'est plus qu'une
		-- rotation du port. Le repère est le MÊME en 3e personne, en 1re et
		-- dans le panneau : c'est ce qui règle la douille qui sortait « super
		-- loin du gun » une fois publiée.
		local base, hasPort = gunCFrame, false
		local pxA = tool:GetAttribute("PortX")
		if pxA ~= nil then
			hasPort = true
			base = gunCFrame * (CFrame.new(pxA,
				tool:GetAttribute("PortY") or 0, tool:GetAttribute("PortZ") or 0)
					* CFrame.Angles(math.rad(tool:GetAttribute("PortRX") or 0),
						math.rad(tool:GetAttribute("PortRY") or 0),
						math.rad(tool:GetAttribute("PortRZ") or 0)))
		end
		local dfx = hasPort and 0 or 0.4
		local dfy = hasPort and 0 or 0.2
		local ejectCF = base * CFrame.new(o.ox or dfx, o.oy or dfy, o.oz or 0)
			* CFrame.Angles(math.random()*6.28, math.random()*6.28, math.random()*6.28)
		-- corps laiton (cylindre arrondi, léger reflet métallique)
		-- éjection vers la droite + haut, avec culbute
		-- La poussée est exprimée dans le repère de l'ARME : « droite » est la
		-- droite du fusil, pas celle de l'écran. L'éjection reste donc juste
		-- quelle que soit la façon dont l'animation tient l'arme.
		local vr = o.spread or 3
		local sp = o.spin or 28
		-- 🆕 LA DOUILLE EMPORTE LA VITESSE DU PERSONNAGE. Sans ça, dès que tu
		-- cours, l'étui reste sur place et il est déjà derrière toi avant
		-- d'avoir eu le temps de tomber : on ne le voit jamais.
		local carry = Vector3.zero
		do
			local root = MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
			local k = o.carry
			if k == nil then k = 1 end
			if root and k ~= 0 then carry = root.AssemblyLinearVelocity * k end
		end
		local vel = carry
			+ base.RightVector * ((o.vx or 8) + (math.random()-0.5)*vr)
			+ base.UpVector    * ((o.vy or 4) + (math.random()-0.5)*vr)
			+ base.LookVector  * ((o.vz or 0) + (math.random()-0.5)*vr)
		local L = math.max(s.Size.X, s.Size.Y, s.Size.Z) * sc
		local D = math.min(s.Size.X, s.Size.Y, s.Size.Z) * sc
		if cfg.FX.ShellBounce then
			-- 🆕 rebond et pose au sol, tout en local, sans physique Roblox.
			FX2.ShellIgnore({ MyCharacter, tool, viewmodel, workspace.CurrentCamera })
			FX2.Shell(ejectCF, vel,
				{ size = s.Size, color = s.Color, material = s.Material,
					scale = sc, spin = sp,
					life = o.rest or cfg.FX.ShellRest or 6,
					max = cfg.FX.ShellMax or 30 })
			return
		end
		-- ── L'ANCIEN SYSTÈME, intact : physique Roblox, la douille disparaît
		--    au bout de Shell.Life. C'est ce qui tourne par défaut.
		local shell = Instance.new("Part")
		shell.Name = "Shell"; shell.Shape = Enum.PartType.Cylinder
		shell.Size = Vector3.new(L, D, D)
		shell.Color = s.Color; shell.Material = s.Material
		shell.Reflectance = 0.18; shell.CanCollide = false
		shell.CFrame = ejectCF
		shell.Parent = workspace
		local cap = Instance.new("Part")
		cap.Name = "Cap"; cap.Shape = Enum.PartType.Cylinder
		cap.Size = Vector3.new(D * 0.35, D * 1.04, D * 1.04)
		cap.Color = s.Color:Lerp(Color3.new(0, 0, 0), 0.5)
		cap.Material = Enum.Material.Metal; cap.CanCollide = false; cap.Massless = true
		cap.CFrame = shell.CFrame * CFrame.new(-L/2 + D * 0.15, 0, 0)
		cap.Parent = shell
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = shell; weld.Part1 = cap; weld.Parent = shell
		shell.AssemblyLinearVelocity = vel
		shell.AssemblyAngularVelocity = Vector3.new(
			(math.random()-0.5)*2*sp, (math.random()-0.5)*2*sp, (math.random()-0.5)*2*sp)
		DebrisService:AddItem(shell, IsMobile and math.min(o.life or s.Life, 0.6) or (o.life or s.Life))   -- ⚡ mobile : vie courte
		if CI.KVPush then CI.KVPush("sho", { cf = ejectCF, v = vel, w = shell.AssemblyAngularVelocity, L = L, D = D, c = s.Color, m = s.Material, life = o.life or s.Life }) end   -- [Combat K4]
	end
	-- 🔦 LA LUMIÈRE DE BOUCHE SUIT L'ARME.
	-- Avant, elle naissait à une position du MONDE : quand tu tirais en te
	-- déplaçant, elle restait derrière pendant que l'arme avançait — c'est
	-- exactement ce que tu décris, « une partie de l'effet ne suit pas le gun ».
	-- Maintenant on la pose DANS le canon : elle bouge avec lui, forcément.
	-- (Passe une position plutôt qu'une part et on retombe sur l'ancien
	--  comportement : rien ne casse.)
	local function SpawnLocalMuzzleLight(host)
		if WeaponVFX.Potato("MuzzleLight") or WeaponVFX.Config.MuzzleLights == false then return end   -- 🥔 / 💡
		-- ⚡ mobile + arme auto : pas de lumière à chaque balle (le moteur recalcule l'éclairage à chaque lumière)
		if IsMobile and cfg.FireRate < 0.2 and WeaponVFX.Config.MobileAutoMuzzleLight == false then return end
		local m = cfg.FX.MuzzleLight
		if typeof(host) == "Instance" and host:IsA("BasePart") and host.Parent then
			local l = Instance.new("PointLight")
			l.Color = m.Color; l.Brightness = m.Brightness; l.Range = m.Range
			l.Parent = host
			DebrisService:AddItem(l, m.Life)
			return
		end
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.Transparency = 1
		p.Size = Vector3.new(0.2,0.2,0.2); p.CFrame = CFrame.new(host); p.Parent = workspace
		local l = Instance.new("PointLight")
		l.Color = m.Color; l.Brightness = m.Brightness; l.Range = m.Range; l.Parent = p
		DebrisService:AddItem(p, m.Life)
	end
	-- Impacts de balles : délégués à WeaponVFX (flash + onde + débris +
	-- poussière + étincelles + trou de balle). Config globale dans le module.
	local function SpawnImpact(pos, normal, material)
		WeaponVFX.Impact(pos, normal, material, cfg.FX.Impact)
	end
	-- ========================================================
	-- CURSEUR / HIT MARKERS
	-- ========================================================
	-- Table d'état du curseur ET du rechargement. Un seul local pour les deux :
	-- la limite Luau des 200 registres est atteinte dans cette fonction, et
	-- SetReloadingTextVisible (défini plus haut que Extra) a besoin d'un
	-- porteur d'état déjà en portée.
	local C = { rl = nil, rlDone = nil }
	for k, v in pairs(cfg.Cursor) do C[k] = v end
	-- 🆕 L'INTERRUPTEUR GLOBAL, en un seul endroit.
	--   bloomSwitch("bloom") → la dispersion dynamique est-elle active ?
	--   bloomSwitch("cross") → le viseur scripté est-il actif ?
	-- L'attribut workspace l'emporte toujours sur le config : tu peux tout
	-- couper en jeu, sans redémarrer, pour toutes les armes d'un coup.
	-- Par défaut le viseur suit le bloom : couper le bloom te rend ton curseur
	-- image et la précision exacte, exactement comme avant.
	local function bloomSwitch(kind)
		if kind == "cross" then
			local a = workspace:GetAttribute("WeaponScriptedCrosshair")
			if a ~= nil then return a == true end
			local CH = cfg.Crosshair
			if CH and CH.Scripted == false then return false end
			return bloomSwitch("bloom")
		end
		local b = workspace:GetAttribute("WeaponDynamicSpread")
		if b ~= nil then return b == true end
		local DS = cfg.DynamicSpread
		return (DS and DS.Enabled) == true
	end
	local function buildCursor(hitMarkersOnly)
		if not MyPlayer then return nil end
		local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return nil end
		local gui = Instance.new("ScreenGui")
		gui.Name = "MobileCursorGui"; gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		-- Même repère que WorldToViewportPoint / ViewportPointToRay, y compris mobile.
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
		-- 🆕 AU-DESSUS DE TOUT. À 8, le viseur passait derrière les interfaces
		-- du jeu et on ne savait plus où on cliquait.
		gui.DisplayOrder = 2147483647; gui.Parent = pg
		local container = Instance.new("Frame")
		container.Name = "Crosshair"
		local scale = IsMobile and 1 or C.PCScale
		local L, T, G = C.LineLength*scale, C.LineThickness*scale, C.Gap*scale
		local dotSize = C.DotSize*scale
		local hitL, hitT, hitOff = C.HitLength*scale, C.HitThickness*scale, C.HitOffset*scale
		local total = math.max((L+G)*2, (hitOff+hitL)*3) + 8
		container.Size = UDim2.new(0,total,0,total)
		container.AnchorPoint = Vector2.new(0.5,0.5)
		container.Position = UDim2.new(0.5,0,0.5,0)
		container.BackgroundTransparency = 1; container.Parent = gui
		if not hitMarkersOnly then
			-- 🎯 LE MÊME CURSEUR PARTOUT : ton image (CustomCursorID), en 1re personne, en mode
			--    lock, sur mobile et à la manette. Elle devient ROUGE sur un ennemi (SetReticleColor).
			--    (l'ancien viseur dessiné en lignes est retiré)
			local img = Instance.new("ImageLabel")
			img.Name = "CursorImage"
			img.BackgroundTransparency = 1
			img.Image = cfg.CustomCursorID
			img.ImageColor3 = C.Color
			img.ScaleType = Enum.ScaleType.Fit
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.new(0.5, 0, 0.5, 0)
			-- taille du curseur libre de Roblox (ton image affichée à sa taille normale : 64 px)
			--    → réglable : Cursor.ImageSize (tout le monde) · Cursor.ImageMobileScale (mobile)
			local isz = (C.ImageSize or 64) * (IsMobile and (C.ImageMobileScale or 1) or 1)
			img.Size = UDim2.fromOffset(isz, isz)
			img.ZIndex = 2
			img.Parent = container
		end
		-- hit markers : 4 traits diagonaux arrondis (offsets de base en attributs)
		local function hitMark(name, ox, oy, rotn)
			local m = Instance.new("Frame"); m.Name = name
			m.Size = UDim2.new(0,hitT,0,hitL); m.AnchorPoint = Vector2.new(0.5,0.5)
			m.Position = UDim2.new(0.5,ox,0.5,oy); m.Rotation = rotn
			m.BackgroundColor3 = C.HitColor; m.BorderSizePixel = 0
			m.BackgroundTransparency = 1
			m:SetAttribute("BX", ox); m:SetAttribute("BY", oy)
			m.Parent = container
			local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1,0); rc.Parent = m
			local st = Instance.new("UIStroke"); st.Color = C.Outline; st.Thickness = 1
			st.Transparency = 1; st.Parent = m
		end
		hitMark("HitMark_NW",-hitOff,-hitOff,-45); hitMark("HitMark_NE",hitOff,-hitOff,45)
		hitMark("HitMark_SW",-hitOff,hitOff,45);   hitMark("HitMark_SE",hitOff,hitOff,-45)
		-- 🔄 la boucle au centre (option) et la jauge à droite (défaut)
		FX2.RingBuild(container, scale)
		do
			local RH = cfg.ReloadHUD or {}
			if RH.Gauge ~= false then
				-- pompe → cartouches empilées ; tout le reste → barre verticale
				local mode = (cfg.Reload.Style == "Shell") and "shells" or "bar"
				FX2.GaugeBuild(container, scale, mode, cfg.ClipSize)
			end
		end
		local rt = Instance.new("TextLabel")
		-- 🔄 à DROITE du curseur, discret, et il le suit puisqu'il est dans le
		-- même conteneur que le viseur.
		rt.Name = "ReloadingText"; rt.Size = UDim2.new(0,110,0,16)
		rt.AnchorPoint = Vector2.new(0,0.5)
		rt.Position = UDim2.new(0.5,22*scale,0.5,0)
		rt.BackgroundTransparency = 1; rt.Text = "Reloading"
		rt.TextXAlignment = Enum.TextXAlignment.Left
		rt.TextColor3 = Color3.fromRGB(255,255,255); rt.TextStrokeColor3 = Color3.fromRGB(0,0,0)
		rt.TextStrokeTransparency = 0.35; rt.Font = Enum.Font.GothamMedium
		rt.TextTransparency = 0.15
		rt.TextSize = IsMobile and 12 or 13; rt.Visible = false
		rt.ZIndex = 30; rt.Parent = container
		return gui
	end
	local function SetMobileCursorColor(color)
		if not MobileCursorGui then return end
		local c = MobileCursorGui:FindFirstChild("Crosshair"); if not c then return end
		local img = c:FindFirstChild("CursorImage")
		if img then
			-- image rouge prête (Cursor.EnemyImage) : on change d'image, sinon on la teinte
			local enemyImg = C.EnemyImage
			if type(enemyImg) == "string" and enemyImg ~= "" then
				local isEnemy = (color == Color3.new(1, 0, 0))
				img.Image = isEnemy and enemyImg or cfg.CustomCursorID
				img.ImageColor3 = isEnemy and Color3.new(1, 1, 1) or color
			else
				img.ImageColor3 = color
			end
		end
	end
	-- position du curseur SANS dépendre de la table Snap (déclarée plus bas
	-- dans le fichier → invisible depuis ici en Lua)
	local function CursorPosLocal()
		local centered = WeaponSharedState.IsThirdPersonLock() or IsMobile or CI.IsGamepad()   -- [Combat C2]
			or Aiming
		if centered or not MyMouse then
			-- Projette le VRAI axe du tir : ViewportSize / 2 peut différer du centre
			-- optique avec les marges de l'appareil. Aucun décalage fixe en pixels.
			local cf = camera.CFrame
			local point = camera:WorldToViewportPoint(cf.Position + cf.LookVector * 1000)
			return Vector2.new(point.X, point.Y)
		end
		local inset = GuiService:GetGuiInset()
		return Vector2.new(MyMouse.X + inset.X, MyMouse.Y + inset.Y)
	end
	-- petit "pop" élastique du crosshair (feedback de headshot)
	local function PunchCrosshair(scale)
		if not MobileCursorGui or not scale or scale <= 1 then return end
		local c = MobileCursorGui:FindFirstChild("Crosshair"); if not c then return end
		local ui = c:FindFirstChildWhichIsA("UIScale")
		if not ui then ui = Instance.new("UIScale"); ui.Parent = c end
		ui.Scale = scale
		TweenService:Create(ui, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
	end
	-- 🔊 son de hit LOCAL : cloné dans SoundService côté client → seul le tireur l'entend
	C.hitSndAt = 0
	C.PlayHitSound = function(isHead)
		local HS = cfg.FX and cfg.FX.HitSound
		if not HS or HS.Enabled == false then return end
		local now = os.clock()
		if now - C.hitSndAt < (HS.MinGap or 0.03) then return end
		C.hitSndAt = now
		local tpl
		if isHead then
			local hn = HS.HeadshotName or (cfg.Headshot and cfg.Headshot.Sound)
			tpl = hn and SoundService:FindFirstChild(hn, true)
		end
		if not (tpl and tpl:IsA("Sound")) then tpl = SoundService:FindFirstChild(HS.Name or "HitSound", true) end
		if not (tpl and tpl:IsA("Sound")) then return end
		local s = tpl:Clone()
		local lo, hi = HS.PitchMin or 1, HS.PitchMax or 1
		s.PlaybackSpeed = (lo + math.random() * math.max(0, hi - lo)) * ((isHead and HS.HeadshotPitch) or 1)
		if HS.Volume then s.Volume = HS.Volume end
		s.Looped = false
		s.Parent = SoundService
		s:Play()
		DebrisService:AddItem(s, math.max(2, (s.TimeLength or 0) + 0.5))
	end
	-- isHead = true → marqueurs ROUGES plus larges + anneau/pointes + pop du crosshair
	function FlashHitMarkers(isHead)
		if not MobileCursorGui then return end
		if not GetSetting("SettingHitMarkers", true) then return end
		if CI.KVPush then CI.KVPush("h", { h = isHead == true }) end   -- [Combat K1] vue du tueur
		local c = MobileCursorGui:FindFirstChild("Crosshair"); if not c then return end
		local HM = cfg.Headshot.Marker
		local col    = isHead and HM.Color or C.HitColor
		local spread = isHead and (C.HitSpreadHead or 1.2) or (C.HitSpread or 1.1)
		local start  = isHead and (C.HitStartHead or 1.9) or (C.HitStart or 1.6)
		-- 🆕 maintien plein puis fondu (config : Cursor.HitHold / HitFade / HitFadeStyle)
		local tm     = isHead and (C.HitHeadTimeMult or 1.25) or 1
		local hold   = (C.HitHold or 0) * tm
		local fade   = math.max(0.01, (C.HitFade or 0.5) * tm)
		local okStyle, style = pcall(function() return Enum.EasingStyle[C.HitFadeStyle or "Sine"] end)
		if not okStyle or not style then style = Enum.EasingStyle.Sine end
		local okPop, popStyle = pcall(function() return Enum.EasingStyle[C.HitSpreadStyle or "Sine"] end)
		if not okPop or not popStyle then popStyle = Enum.EasingStyle.Sine end
		local tiPop  = TweenInfo.new(C.HitSpreadTime or 0.30, popStyle, Enum.EasingDirection.Out)
		local tiFade = TweenInfo.new(fade, style, Enum.EasingDirection.InOut, 0, false, hold)
		for _, ch in ipairs(c:GetChildren()) do
			if ch:IsA("Frame") and ch.Name:sub(1,8) == "HitMark_" then
				local bx, by = ch:GetAttribute("BX") or 0, ch:GetAttribute("BY") or 0
				ch.BackgroundColor3 = col
				-- partent du CENTRE… sauf si elles sont encore visibles (tir rapide) :
				-- dans ce cas elles repartent d'où elles sont, sans tressauter.
				if ch.BackgroundTransparency > 0.6 then
					ch.Position = UDim2.new(0.5, bx*start, 0.5, by*start)
				end
				ch.BackgroundTransparency = 0
				TweenService:Create(ch, tiPop, {
					Position = UDim2.new(0.5, bx*spread, 0.5, by*spread) }):Play()
				TweenService:Create(ch, tiFade, { BackgroundTransparency = 1 }):Play()
				local st = ch:FindFirstChildWhichIsA("UIStroke")
				if st then st.Transparency = 0.3; TweenService:Create(st, tiFade, {Transparency=1}):Play() end
			end
		end
		-- 🎯 anneau + pointes : COMPLET au headshot, version plus douce au hit normal
		if HM.Enabled ~= false and MyPlayer and (isHead or C.HitRingNormal ~= false) then
			local M = HM
			if not isHead then
				local k = C.HitRingScale or 0.7
				M = table.clone(HM)
				M.Color = C.HitColor
				M.RingSize = (HM.RingSize or 46) * k
				M.SpikeLength = (HM.SpikeLength or 14) * k
				M.SpikeOffset = (HM.SpikeOffset or 16) * k
				M.RingThickness = math.max(1, (HM.RingThickness or 3) - 1)
				M.Life = (HM.Life or 0.35) * 0.85
				M.CrosshairPunch = 1 + ((HM.CrosshairPunch or 1.35) - 1) * (C.HitPunchScale or 0.5)
			end
			local pg = MyPlayer:FindFirstChild("PlayerGui")
			if pg then WeaponVFX.HeadshotMarker(pg, CursorPosLocal(), M) end
			PunchCrosshair(M.CrosshairPunch)
		end
	end
	-- 🔄 v = on/off · dur = durée du rechargement · segs = nombre de crans
	-- (une cartouche = un cran, pour les armes qui rechargent une par une)
	function SetReloadingTextVisible(v, dur, segs)
		if v then
			C.rl = { t0 = os.clock(), dur = math.max(0.08, dur or 1.6), segs = segs,
				from = AmmoInClip }
		elseif C.rl then
			C.rl = nil
			C.rlDone = os.clock()
		end
		if not MobileCursorGui then return end
		local c = MobileCursorGui:FindFirstChild("Crosshair"); if not c then return end
		if C.rlDone and not v then
			local ring = c:FindFirstChild("ReloadRing")
			if ring and ring.Visible then FX2.RingDone(ring) end
			-- 🎉 la jauge respire une fois : c'est le signal « tu peux tirer »
			FX2.GaugePop(c:FindFirstChild("AmmoGauge"))
		end
		-- le mot reste, mais À DROITE du curseur et discret ; la boucle au
		-- centre dit l'avancement. Reload.ShowText = false pour n'avoir que la
		-- boucle.
		local t = c:FindFirstChild("ReloadingText")
		if t then t.Visible = (v and (cfg.ReloadHUD or {}).Text == true) or false end
	end
	-- ========================================================
	-- HUD
	-- ========================================================
	function UpdateCrosshair(value)
		if WeaponGui and WeaponGui:FindFirstChild("Crosshair") then
			local ay = 650
			WeaponGui.Crosshair:TweenSize(
				UDim2.new(0, value*ay*2+23, 0, value*ay*2+23),
				Enum.EasingDirection.Out, Enum.EasingStyle.Linear, 0.33)
		end
	end
	function UpdateAmmo(value)
		pcall(function() tool:SetAttribute("GunKitAmmo", value) end)   -- [GunKit P13]
		if not WeaponGui then return end
		local hud = WeaponGui:FindFirstChild("AmmoHud"); if not hud then return end
		local clip = hud:FindFirstChild("ClipAmmo")
		if clip then
			clip.Text = value.."/"..cfg.ClipSize
			clip.TextColor3 = (value==0) and Color3.fromRGB(255,60,60) or Color3.fromRGB(255,255,255)
		end
		local total = hud:FindFirstChild("TotalAmmo"); if total then total.Visible=false end
		local empty = hud:FindFirstChild("EmptyMagLabel"); if empty then empty.Visible=(value==0) end
	end
	local function styleAmmoHud(keys)
		local hud = WeaponGui and WeaponGui:FindFirstChild("AmmoHud")
		if not hud then return end
		for _, ch in pairs(hud:GetChildren()) do
			if ch:IsA("TextLabel") and ch.Name ~= "ClipAmmo"
				and ch.Name ~= "EmptyMagLabel" and ch.Name ~= "KeyInstructions" then
				ch.Visible = false
			end
		end
		hud.BackgroundColor3 = Color3.fromRGB(0,0,0); hud.BackgroundTransparency = 0.5; hud.BorderSizePixel = 0
		if not hud:FindFirstChildWhichIsA("UICorner") then
			local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=hud end
		if not hud:FindFirstChildWhichIsA("UIStroke") then
			local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(0,0,0); s.Thickness=2; s.Parent=hud end
		if not hud:FindFirstChildWhichIsA("UIPadding") then
			local p=Instance.new("UIPadding"); p.PaddingTop=UDim.new(0,6); p.PaddingBottom=UDim.new(0,6)
			p.PaddingLeft=UDim.new(0,12); p.PaddingRight=UDim.new(0,12); p.Parent=hud end
		local clip = hud:FindFirstChild("ClipAmmo")
		if clip then
			clip.Size=UDim2.new(1,0,1,0); clip.Position=UDim2.new(0,0,0,0); clip.AnchorPoint=Vector2.new(0,0)
			clip.BackgroundTransparency=1; clip.TextXAlignment=Enum.TextXAlignment.Center
			clip.TextYAlignment=Enum.TextYAlignment.Center; clip.TextScaled=true
			clip.Font=Enum.Font.GothamBold; clip.TextStrokeColor3=Color3.fromRGB(0,0,0)
			clip.TextStrokeTransparency=0.3; clip.Visible=true
		end
		if not hud:FindFirstChild("EmptyMagLabel") then
			local e=Instance.new("TextLabel"); e.Name="EmptyMagLabel"
			e.Size=UDim2.new(1,0,0,28); e.AnchorPoint=Vector2.new(0,1); e.Position=UDim2.new(0,0,0,-4)
			e.BackgroundTransparency=1; e.Text="RELOAD"; e.TextColor3=Color3.fromRGB(255,60,60)
			e.TextStrokeColor3=Color3.fromRGB(0,0,0); e.TextStrokeTransparency=0.2
			e.Font=Enum.Font.GothamBold; e.TextSize=24; e.TextXAlignment=Enum.TextXAlignment.Center
			e.Visible=false; e.Parent=hud
		end
		if not IsMobile and not hud:FindFirstChild("KeyInstructions") then
			local chip=22; local rowH=chip+4
			local list=Instance.new("Frame"); list.Name="KeyInstructions"
			list.Size=UDim2.new(1,0,0,#keys*rowH); list.AnchorPoint=Vector2.new(0,1)
			list.Position=UDim2.new(0,0,0,-36); list.BackgroundTransparency=1; list.Parent=hud
			for i, k in ipairs(keys) do
				local row=Instance.new("Frame"); row.Name="Row_"..k.key
				row.Size=UDim2.new(1,0,0,chip); row.Position=UDim2.new(0,0,0,(i-1)*rowH)
				row.BackgroundTransparency=1; row.Parent=list
				-- une touche peut s'afficher en IMAGE (sans fond) au lieu d'une lettre
				local useImg = k.image and k.image ~= "" and k.image ~= "rbxassetid://0"
				-- largeur du chip : carré pour 1 lettre, élargi selon le nb de caractères (ex: "Shift")
				local lw=80; local cw=useImg and chip or ((#k.key>1) and (chip + (#k.key-1)*9) or chip)
				local gw=cw+6+lw
				local group=Instance.new("Frame"); group.Size=UDim2.new(0,gw,1,0)
				group.AnchorPoint=Vector2.new(0.5,0.5); group.Position=UDim2.new(0.5,0,0.5,0)
				group.BackgroundTransparency=1; group.Parent=row
				if useImg then
					-- ICÔNE sans fond (ni boîte ni contour)
					local icon=Instance.new("ImageLabel"); icon.Name="KeyIcon"
					icon.Size=UDim2.new(0,cw,0,chip); icon.Position=UDim2.new(0,0,0.5,0)
					icon.AnchorPoint=Vector2.new(0,0.5); icon.BackgroundTransparency=1
					icon.Image=k.image; icon.ScaleType=Enum.ScaleType.Fit; icon.Parent=group
				else
					local box=Instance.new("Frame"); box.Name="Chip"
					box.Size=UDim2.new(0,cw,0,chip); box.Position=UDim2.new(0,0,0.5,0); box.AnchorPoint=Vector2.new(0,0.5)
					box.BackgroundColor3=Color3.fromRGB(0,0,0); box.BackgroundTransparency=0.4
					box.BorderSizePixel=0; box.Parent=group
					local bc=Instance.new("UICorner"); bc.CornerRadius=UDim.new(0,4); bc.Parent=box
					local bs=Instance.new("UIStroke"); bs.Color=Color3.fromRGB(0,0,0); bs.Thickness=1; bs.Parent=box
					local letter=Instance.new("TextLabel"); letter.Size=UDim2.new(1,0,1,0)
					letter.BackgroundTransparency=1; letter.Text=k.key; letter.TextColor3=Color3.fromRGB(255,255,255)
					letter.TextStrokeColor3=Color3.fromRGB(0,0,0); letter.TextStrokeTransparency=0.4
					letter.Font=Enum.Font.GothamBold; letter.TextSize=14
					letter.TextXAlignment=Enum.TextXAlignment.Center; letter.TextYAlignment=Enum.TextYAlignment.Center; letter.Parent=box
				end
				local desc=Instance.new("TextLabel"); desc.Name="Desc"; desc.Size=UDim2.new(0,lw,1,0)
				desc.Position=UDim2.new(0,cw+6,0,0); desc.BackgroundTransparency=1; desc.Text=k.action
				desc.TextColor3=Color3.fromRGB(220,220,220); desc.TextStrokeColor3=Color3.fromRGB(0,0,0)
				desc.TextStrokeTransparency=0.3; desc.Font=Enum.Font.GothamBold; desc.TextSize=13
				desc.TextXAlignment=Enum.TextXAlignment.Left; desc.TextYAlignment=Enum.TextYAlignment.Center; desc.Parent=group
			end
		end
	end
	-- 🆕 Touche H : cache / réaffiche les lignes de contrôles. La ligne "H" reste
	-- TOUJOURS visible ; son texte bascule "Cacher" ↔ "Afficher".
	ToggleControls = function()
		ControlsHidden = not ControlsHidden
		local hud = WeaponGui and WeaponGui:FindFirstChild("AmmoHud"); if not hud then return end
		local list = hud:FindFirstChild("KeyInstructions"); if not list then return end
		for _, row in ipairs(list:GetChildren()) do
			if row:IsA("Frame") then
				if row.Name == "Row_H" then
					local desc = row:FindFirstChild("Desc", true)
					if desc then desc.Text = ControlsHidden and "Reveal Controls" or "Hide Controls" end
				else
					row.Visible = not ControlsHidden
				end
			end
		end
	end
	-- ========================================================
	-- BARRE DE CHARGE (autoshoot Delay)
	-- ========================================================
	local function CreateChargeBar()
		-- 🆕 la barre s'affiche aussi en mode "Simple" si AutoshootShowBar = true
		if cfg.Autoshoot ~= "Delay" and not cfg.AutoshootShowBar then return end
		if not MyPlayer then return end
		local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return end
		if ChargeBarGui then ChargeBarGui:Destroy() end
		ChargeBarGui, ChargeBarFill = nil, nil
		local sg=Instance.new("ScreenGui"); sg.Name="ChargeBarGui"; sg.ResetOnSpawn=false
		sg.DisplayOrder=9; sg.IgnoreGuiInset=true; sg.Parent=pg
		local scale = IsMobile and 1 or C.PCScale
		local L, G = C.LineLength*scale, C.Gap*scale
		local barH=(L+G)*2
		local cont=Instance.new("Frame"); cont.Name="ChargeBarContainer"
		cont.Size=UDim2.new(0,4,0,barH); cont.AnchorPoint=Vector2.new(0,0.5)
		cont.Position=UDim2.new(0.5, G+L+8, 0.5, 0); cont.BackgroundColor3=Color3.fromRGB(60,60,60)
		cont.BackgroundTransparency=0.4; cont.BorderSizePixel=0; cont.Parent=sg
		local cc=Instance.new("UICorner"); cc.CornerRadius=UDim.new(0,2); cc.Parent=cont
		local fill=Instance.new("Frame"); fill.Name="Fill"; fill.Size=UDim2.new(1,0,0,0)
		fill.AnchorPoint=Vector2.new(0,0); fill.Position=UDim2.new(0,0,0,0)
		fill.BackgroundColor3=Color3.fromRGB(220,40,40); fill.BorderSizePixel=0; fill.Parent=cont
		local fc=Instance.new("UICorner"); fc.CornerRadius=UDim.new(0,2); fc.Parent=fill
		ChargeBarGui, ChargeBarFill = sg, fill
		sg.Enabled=false
	end
	local function UpdateChargeBar(p)
		if not ChargeBarFill or not ChargeBarGui then return end
		if p <= 0 then ChargeBarGui.Enabled=false; ChargeBarFill.Size=UDim2.new(1,0,0,0); return end
		ChargeBarGui.Enabled=true
		ChargeBarFill.BackgroundColor3 = (p>=1) and Color3.fromRGB(255,80,80) or Color3.fromRGB(220,40,40)
		ChargeBarFill.Size = UDim2.new(1,0,p,0)
	end
	-- ════════ SNAP ASSIST ════════ (tout dans UNE table → 1 seul local,
	-- évite la limite Luau de 200 locals dans Setup)
	local Snap = {}
	-- 🆕 renvoie la valeur MOBILE si on est sur mobile ET qu'elle est définie,
	-- sinon la valeur de base (= PC). Une clé *Mobile absente → comportement PC.
	function Snap.Pick(mobileValue, baseValue)
		if IsMobile and mobileValue ~= nil then return mobileValue end
		return baseValue
	end
	-- Rayon en PIXELS : % de la hauteur du viewport → proportionnel à l'écran.
	function Snap.RadiusPx()
		local SA = cfg.SnapAssist
		local scale = IsMobile and SA.RadiusScaleMobile or SA.RadiusScalePC
		return scale * camera.ViewportSize.Y * cfg.LiveFeel.Assist.SnapRadius
	end
	-- Rayon PLANCHER en pixels (aimbot minimal, proportionnel à l'écran)
	function Snap.MinRadiusPx()
		local SA = cfg.SnapAssist
		local scale = IsMobile and (SA.MinRadiusScaleMobile or 0) or (SA.MinRadiusScalePC or 0)
		return scale * camera.ViewportSize.Y * cfg.LiveFeel.Assist.SnapRadius
	end
	-- Position du curseur en coords viewport (centre en TP / mobile / lunette)
	function Snap.CursorPos()
		return CursorPosLocal()
	end
	-- Facteur d'assist selon la distance : 1 de près → 0 de loin (custom via Falloff)
	function Snap.Falloff(dist)
		local SA = cfg.SnapAssist
		local F  = SA.Falloff
		if not F or not F.Enabled then return 1 end
		-- 🆕 sur mobile, FalloffMobile écrase champ par champ (les champs absents
		-- retombent sur le Falloff PC)
		local FM = IsMobile and SA.FalloffMobile or nil
		local full  = (FM and FM.FullUntil) or F.FullUntil
		local zero  = (FM and FM.ZeroAt)    or F.ZeroAt
		local curve = (FM and FM.Curve)     or F.Curve or 1
		if dist <= full then return 1 end
		if dist >= zero then return 0 end
		local x = 1 - (dist - full) / (zero - full)
		return x ^ curve
	end
	-- Renvoie (positionMonde, facteurFinal 0..1, info) — ou nil.
	-- info = { screen=Vector2, dist=studs, falloff=0..1 brut } (pour le debug)
	function Snap.GetTarget()
		local SA = cfg.SnapAssist
		if not SA or not SA.Enabled or not MyPlayer or not MyCharacter then return nil end
		if IsMobile and not SA.EnabledMobile then return nil end
		if not IsMobile and not SA.EnabledPC then return nil end
		local radiusPx = Snap.RadiusPx()
		local minRadiusPx = Snap.MinRadiusPx()
		local cursor = Snap.CursorPos()
		-- 🆕 portée / force propres au mobile (PC = valeurs d'origine intactes)
		local maxDist  = Snap.Pick(SA.MaxDistanceMobile, SA.MaxDistance)
		local strength = Snap.Pick(SA.StrengthMobile,    SA.Strength or 1)
		local minStr   = Snap.Pick(SA.MinStrengthMobile, SA.MinStrength or 1)
		local camPos = camera.CFrame.Position
		local head = MyCharacter:FindFirstChild("Head")
		local shooterPos = head and head.Position or camPos
		local losParams = RaycastParams.new()
		losParams.FilterType = Enum.RaycastFilterType.Exclude
		local byNear = (SA.TargetPriority == "Near")
		local bestScore = byNear and math.huge or radiusPx
		local bestPos, bestFactor, bestInfo = nil, 0, nil
		-- liste des parts à tester : tout le corps ("All") ou la liste du config
		local function partsOf(char)
			local list = {}
			-- exclusion de la tête, réglable séparément PC / mobile
			local skipHead = SA.ExcludeHead == true
			if IsMobile and SA.ExcludeHeadMobile ~= nil then
				skipHead = SA.ExcludeHeadMobile == true
			end
			if SA.TargetParts == "All" then
				for _, p in ipairs(char:GetChildren()) do
					if p:IsA("BasePart") and not (skipHead and p.Name == "Head") then
						list[#list+1] = p
					end
				end
			else
				for _, nm in ipairs(SA.TargetParts) do
					if not (skipHead and nm == "Head") then
						local p = char:FindFirstChild(nm)
						if p and p:IsA("BasePart") then list[#list+1] = p end
					end
				end
			end
			return list
		end
		local function tryCharacter(char)
			if not char or not char.Parent then return end
			local hum = char:FindFirstChildOfClass("Humanoid")
			local isEgg = char:FindFirstChild("Egglon") ~= nil
			if not hum and not isEgg then return end
			if hum and hum.Health <= 0 then return end
			for _, part in ipairs(partsOf(char)) do
				local dist = (part.Position - shooterPos).Magnitude
				local fall = Snap.Falloff(dist)
				-- rayon effectif : falloff, mais JAMAIS sous le rayon plancher
				local headScale = part.Name == "Head" and cfg.LiveFeel.Assist.HeadRadius or 1
				local allowed = math.max(radiusPx * fall, minRadiusPx) * headScale
				if dist <= maxDist and dist >= (SA.MinDistance or 0) and allowed > 0.5 then
					local sp, on = camera:WorldToViewportPoint(part.Position)
					if on and sp.Z > 0 then
						local d = (Vector2.new(sp.X, sp.Y) - cursor).Magnitude
						local score = byNear and dist or d
						if d < allowed and score < bestScore then
							local visible = true
							if SA.RequireLineOfSight then
								losParams.FilterDescendantsInstances =
									{ MyCharacter, viewmodel, char, tool }
								visible = workspace:Raycast(
									camPos, part.Position - camPos, losParams) == nil
									and workspace:Raycast(
										shooterPos, part.Position - shooterPos, losParams) == nil
							end
							if visible then
								bestScore = score
								bestPos = part.Position
								-- force normale (falloff) ; si le curseur est dans le
								-- rayon PLANCHER → au moins MinStrength, peu importe la distance
								local f = math.clamp(fall * strength, 0, 1)
								if d < minRadiusPx * headScale then
									f = math.max(f, math.clamp(minStr, 0, 1))
								end
								bestFactor = f * cfg.LiveFeel.Assist.SnapStrength
									* (part.Name == "Head" and cfg.LiveFeel.Assist.HeadStrength or 1)
								bestInfo = { screen = Vector2.new(sp.X, sp.Y), dist = dist, falloff = fall }
							end
						end
					end
				end
			end
		end
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= MyPlayer and IsEnemyPlayer(pl) then
				tryCharacter(pl.Character)
			end
		end
		-- 🤖 bots d'arène (ArenaBots) : ciblés comme des joueurs ennemis
		for _, bot in ipairs(game:GetService("CollectionService"):GetTagged("ArenaBot")) do
			tryCharacter(bot)
		end
		if SA.IncludeEgglons then
			for _, m in ipairs(workspace:GetChildren()) do
				if m:IsA("Model") and m:FindFirstChild("Egglon") then
					tryCharacter(m)
				end
			end
		end
		return bestPos, bestFactor, bestInfo
	end
	function Snap.PreservesHit(origin, direction)
		if not cfg.LiveFeel.Assist.PreserveDirectHits then return false end
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { MyCharacter, camera, tool }
		local hit = workspace:Raycast(origin, direction * cfg.Range, rp)
		return hit ~= nil and partIsCharacter(hit.Instance)
	end
	-- ── Overlay : cercle + debug temps réel ──
	function Snap.DestroyRing()
		if Snap.ringGui then Snap.ringGui:Destroy() end
		Snap.ringGui, Snap.ringFrame, Snap.ringStroke = nil, nil, nil
		Snap.minRingFrame = nil
		Snap.lineFrame, Snap.dotFrame, Snap.infoLabel = nil, nil, nil
	end
	function Snap.UpdateRing()
		local SA = cfg.SnapAssist
		local DBG = SA.Debug
		local wantDbg = DBG and DBG.Enabled
		-- visible SEULEMENT si : arme ÉQUIPÉE (tool dans le perso) + vivant
		local show = SA and SA.Enabled and (SA.ShowRadius or SA.ShowMinRadius or wantDbg)
			and MyPlayer and MyHumanoid and MyHumanoid.Health > 0
			and MyCharacter and tool.Parent == MyCharacter
		if not show then
			-- mort / déséquipé → on DÉTRUIT (pas juste cacher) : rien ne traîne à l'écran
			if Snap.ringGui then Snap.DestroyRing() end
			return
		end
		if not Snap.ringGui or not Snap.ringGui.Parent then
			local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return end
			Snap.DestroyRing()
			-- purge les copies laissées par d'autres armes / une vie précédente
			for _, ch in ipairs(pg:GetChildren()) do
				if ch.Name == "SnapRadiusGui" then ch:Destroy() end
			end
			local sg = Instance.new("ScreenGui")
			sg.Name = "SnapRadiusGui"; sg.ResetOnSpawn = true   -- auto-détruit au respawn (filet de sécurité)
			sg.IgnoreGuiInset = true; sg.DisplayOrder = 7
			sg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
			sg.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None; sg.Parent = pg
			-- cercle
			local f = Instance.new("Frame")
			f.Name = "Ring"; f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.BackgroundTransparency = 1; f.BorderSizePixel = 0; f.Parent = sg
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = f
			local st = Instance.new("UIStroke")
			st.Color = SA.Ring.Color; st.Thickness = SA.Ring.Thickness
			st.Transparency = SA.Ring.Transparency
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = f
			-- petit cercle : rayon PLANCHER (aimbot minimal)
			local mf = Instance.new("Frame")
			mf.Name = "MinRing"; mf.AnchorPoint = Vector2.new(0.5, 0.5)
			mf.BackgroundTransparency = 1; mf.BorderSizePixel = 0; mf.Parent = sg
			local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(1, 0); mc.Parent = mf
			local mst = Instance.new("UIStroke")
			mst.Color = SA.MinRing.Color; mst.Thickness = SA.MinRing.Thickness
			mst.Transparency = SA.MinRing.Transparency
			mst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; mst.Parent = mf
			-- ligne curseur → cible
			local ln = Instance.new("Frame")
			ln.Name = "Line"; ln.AnchorPoint = Vector2.new(0.5, 0.5)
			ln.BackgroundColor3 = DBG.LockColor; ln.BorderSizePixel = 0
			ln.Visible = false; ln.Parent = sg
			-- point sur la cible
			local dot = Instance.new("Frame")
			dot.Name = "Dot"; dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.BackgroundColor3 = DBG.LockColor; dot.BorderSizePixel = 0
			dot.Size = UDim2.fromOffset(DBG.DotSize, DBG.DotSize); dot.Visible = false; dot.Parent = sg
			local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
			-- texte info
			local tl = Instance.new("TextLabel")
			tl.Name = "Info"; tl.AnchorPoint = Vector2.new(0.5, 0)
			tl.Size = UDim2.fromOffset(220, 18); tl.BackgroundTransparency = 1
			tl.Font = Enum.Font.GothamBold; tl.TextSize = 13
			tl.TextColor3 = Color3.fromRGB(255, 255, 255)
			tl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); tl.TextStrokeTransparency = 0.3
			tl.Visible = false; tl.Parent = sg
			Snap.ringGui, Snap.ringFrame, Snap.ringStroke = sg, f, st
			Snap.minRingFrame = mf
			Snap.lineFrame, Snap.dotFrame, Snap.infoLabel = ln, dot, tl
		end
		Snap.ringGui.Enabled = true
		local rBase = Snap.RadiusPx()
		local cur = Snap.CursorPos()
		-- cible live (calculée seulement en debug — coûte des raycasts)
		local pos, fct, info
		if wantDbg then pos, fct, info = Snap.GetTarget() end
		local locked = pos ~= nil and info ~= nil
		-- CERCLE : en debug + DynamicRing, il rétrécit au rayon EFFECTIF
		-- (rayon × falloff de la cible) → tu VOIS la zone réelle selon la distance
		local r = rBase
		if locked and wantDbg and DBG.DynamicRing then
			r = math.max(6, rBase * info.falloff, Snap.MinRadiusPx())
		end
		Snap.ringFrame.Size = UDim2.fromOffset(r * 2, r * 2)
		Snap.ringFrame.Position = UDim2.fromOffset(cur.X, cur.Y)
		-- grand cercle affiché seulement si demandé (debug ou ShowRadius)
		Snap.ringFrame.Visible = SA.ShowRadius or wantDbg
		-- petit cercle : rayon plancher, suit le curseur, taille exacte
		local mr = Snap.MinRadiusPx()
		if (SA.ShowMinRadius or wantDbg) and mr > 0 then
			Snap.minRingFrame.Visible = true
			Snap.minRingFrame.Size = UDim2.fromOffset(mr * 2, mr * 2)
			Snap.minRingFrame.Position = UDim2.fromOffset(cur.X, cur.Y)
		else
			Snap.minRingFrame.Visible = false
		end
		Snap.ringStroke.Color = (locked and wantDbg) and DBG.LockColor or SA.Ring.Color
		-- LIGNE + POINT + TEXTE
		if locked then
			if DBG.ShowLine then
				local delta = info.screen - cur
				local len = delta.Magnitude
				Snap.lineFrame.Visible = len > 2
				Snap.lineFrame.Size = UDim2.fromOffset(len, DBG.LineThickness)
				Snap.lineFrame.Position = UDim2.fromOffset((cur.X + info.screen.X)/2, (cur.Y + info.screen.Y)/2)
				Snap.lineFrame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			end
			if DBG.ShowDot then
				Snap.dotFrame.Visible = true
				Snap.dotFrame.Position = UDim2.fromOffset(info.screen.X, info.screen.Y)
			end
			if DBG.ShowText then
				Snap.infoLabel.Visible = true
				Snap.infoLabel.Position = UDim2.fromOffset(cur.X, cur.Y + rBase + 6)
				Snap.infoLabel.Text = string.format("%d studs  •  assist %d%%", info.dist, fct * 100)
			end
		else
			Snap.lineFrame.Visible = false
			Snap.dotFrame.Visible = false
			if wantDbg and DBG.ShowText then
				Snap.infoLabel.Visible = true
				Snap.infoLabel.Position = UDim2.fromOffset(cur.X, cur.Y + rBase + 6)
				Snap.infoLabel.Text = "aucune cible"
			else
				Snap.infoLabel.Visible = false
			end
		end
	end
	-- ========================================================
	-- DÉTECTION CIBLE (autoshoot Delay : rayons croix)
	-- ========================================================
	local function IsEnemyInCrosshair()
		if not MyPlayer or not MyCharacter then return false end
		if Snap.GetTarget() then return true end
		local scale = IsMobile and 1 or C.PCScale
		local rad = (C.LineLength + C.Gap) * scale
		local vp = camera.ViewportSize
		local radPerPixel = math.rad(camera.FieldOfView) / vp.Y
		local offsets = {
			Vector2.new(0,0), Vector2.new(rad,rad), Vector2.new(-rad,rad),
			Vector2.new(rad,-rad), Vector2.new(-rad,-rad),
			Vector2.new(rad,0), Vector2.new(-rad,0), Vector2.new(0,rad), Vector2.new(0,-rad),
		}
		local function checkRay(off)
			local camCF = camera.CFrame
			local rotated = camCF * CFrame.Angles(-off.Y*radPerPixel, -off.X*radPerPixel, 0)
			local rp = RaycastParams.new(); rp.FilterType=Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = {MyCharacter, viewmodel}
			local res = workspace:Raycast(camCF.Position, rotated.LookVector*cfg.Range, rp)
			if not res then return false end
			local par = res.Instance and res.Instance.Parent; if not par then return false end
			local hum = par:FindFirstChild("Humanoid")
			if hum and hum.Health > 0 then
				local pl = Players:GetPlayerFromCharacter(par)
				if pl then
					if MyPlayer.Neutral then return true end
					if pl.TeamColor ~= MyPlayer.TeamColor then return true end
				else return true end
			end
			if par:FindFirstChild("Egglon") then return true end
			return false
		end
		if WeaponSharedState.IsThirdPersonLock() or IsMobile then
			for _, o in ipairs(offsets) do if checkRay(o) then return true end end
		elseif MyMouse then
			local tgt = MyMouse.Target
			if not tgt or not tgt.Parent then return false end
			local hum = tgt.Parent:FindFirstChild("Humanoid")
			if hum and hum.Health > 0 then
				local pl = Players:GetPlayerFromCharacter(tgt.Parent)
				if pl then
					if MyPlayer.Neutral then return true end
					if pl.TeamColor ~= MyPlayer.TeamColor then return true end
				else return true end
			end
			if tgt.Parent:FindFirstChild("Egglon") then return true end
		end
		return false
	end
	-- ========================================================
	-- AIM ASSIST (mobile)
	-- ========================================================
	local function ApplyAimAssist(dt)
		local A = cfg.AimAssist
		if not A.Enabled or not IsMobile or not MyPlayer or not MyCharacter then return end
		if not GetSetting("SettingAimAssist", true) then return end   -- option joueur
		local vp = camera.ViewportSize
		local center = CursorPosLocal() -- même centre que le réticule et le tir
		local radius = math.max(0, A.Radius * cfg.LiveFeel.Assist.TrackingRadius)
		if radius <= 0 then return end
		local bestDist, bestPos = radius, nil
		local assistTargets = {}
		for _, op in ipairs(Players:GetPlayers()) do
			if op == MyPlayer then continue end
			local same = (not MyPlayer.Neutral) and (not op.Neutral) and (op.TeamColor==MyPlayer.TeamColor)
			if same then continue end
			if op.Character then assistTargets[#assistTargets+1] = op.Character end
		end
		-- 🤖 bots d'arène (ArenaBots)
		for _, bot in ipairs(game:GetService("CollectionService"):GetTagged("ArenaBot")) do
			assistTargets[#assistTargets+1] = bot
		end
		for _, ch in ipairs(assistTargets) do
			local hum = ch:FindFirstChild("Humanoid"); if not hum or hum.Health<=0 then continue end
			local rp = ch:FindFirstChild("HumanoidRootPart"); if not rp then continue end
			local torso = ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso") or rp
			local wp = cfg.LiveFeel.Assist.TrackTorso and torso.Position or (rp.Position + Vector3.new(0, A.TargetHeight, 0))
			if (wp - camera.CFrame.Position).Magnitude > A.MaxDistance then continue end
			local sp, on = camera:WorldToViewportPoint(wp)
			if not on or sp.Z<=0 then continue end
			local sp2 = Vector2.new(sp.X, sp.Y)
			local d = (sp2 - center).Magnitude
			if d >= bestDist then continue end
			local rpar = RaycastParams.new(); rpar.FilterType=Enum.RaycastFilterType.Exclude
			rpar.FilterDescendantsInstances = {MyCharacter, ch, viewmodel}
			if workspace:Raycast(camera.CFrame.Position, wp - camera.CFrame.Position, rpar) then continue end
			bestDist, bestPos = d, sp2
		end
		if not bestPos or bestDist < A.Deadzone then return end
		local delta = bestPos - center
		local radPerPixel = math.rad(camera.FieldOfView) / vp.Y
		local pull = math.min(1, A.Strength * cfg.LiveFeel.Assist.TrackingStrength * (1 - bestDist/radius) * dt * 60)
		CameraYaw   += (-delta.X * radPerPixel) * pull
		CameraPitch  = math.clamp(CameraPitch + (-delta.Y * radPerPixel) * pull, PitchMin, PitchMax)
	end
	-- ========================================================
	-- CAMÉRA ThirdPersonLock
	-- ========================================================
	local function SetupShiftLock(useShared, firstPerson)
		if not firstPerson and not WeaponSharedState.IsThirdPersonLock() then return end
		if not MyCharacter or not MyHumanoid then return end
		local root = MyCharacter:WaitForChild("HumanoidRootPart", 5); if not root then return end
		SavedCameraOffset = MyHumanoid.CameraOffset
		-- ════════════════════════════════════════════════════
		-- 📷 LE SAUT DE CAMÉRA AU CHANGEMENT D'ARME
		-- ════════════════════════════════════════════════════
		-- Deux défauts se cumulaient ici, et c'est ce qui faisait « flicker » :
		--
		--  1) Quand aucune valeur partagée n'était disponible, on reprenait le
		--     lacet depuis la caméra… mais on écrasait le TANGAGE à ZÉRO. Si tu
		--     regardais en l'air ou vers le sol, la vue se redressait d'un coup.
		--
		--  2) Quand une valeur partagée existait, on l'appliquait SANS VÉRIFIER
		--     qu'elle correspondait encore à ce que tu regardes. Après un
		--     changement d'arme un peu lent, la caméra était déjà revenue en
		--     mode normal et avait bougé : la vieille valeur la téléportait.
		--
		-- La règle est maintenant simple : on repart TOUJOURS de l'orientation
		-- réelle de la caméra à cet instant, et on n'accepte la valeur partagée
		-- que si elle dit à peu près la même chose (passage d'arme immédiat,
		-- là où elle sert vraiment à garder la visée au pixel près).
		local lv = camera.CFrame.LookVector
		local curYaw   = math.atan2(-lv.X, -lv.Z)
		local curPitch = math.asin(math.clamp(lv.Y, -1, 1))
		if useShared then
			local sy, sp = WeaponSharedState.GetCamera()
			if sy and sp then
				-- écart de lacet ramené dans [-π, π] : sinon 359° et 1° passent
				-- pour deux directions opposées alors qu'il y a 2° entre elles.
				local d = (sy - curYaw + math.pi) % (2 * math.pi) - math.pi
				if math.abs(d) < math.rad(25) and math.abs(sp - curPitch) < math.rad(25) then
					curYaw, curPitch = sy, sp
				end
			end
		end
		CameraYaw   = curYaw
		CameraPitch = math.clamp(curPitch, PitchMin, PitchMax)
		WeaponSharedState.SetCamera(CameraYaw, CameraPitch)
		camera.CameraType = Enum.CameraType.Scriptable
		MyHumanoid.AutoRotate = false
		local lastSentYaw
		local YAW_THRESH = math.rad(0.5)
		local deadCleanupDone = false
		WeaponSharedState.ClaimCamera(camOwnerToken, tool)
		if camRenderBound then RunService:UnbindFromRenderStep(camRenderName) end
		camRenderBound = true
		-- priorité Camera : la caméra bouge AVANT le viewmodel (Camera+2)
		-- → plus de bras/arme qui traînent d'une frame en 1re personne
		RunService:BindToRenderStep(camRenderName, Enum.RenderPriority.Camera.Value, function(dt)
			if not MyCharacter or not MyCharacter.Parent
				or not MyHumanoid or MyHumanoid.Health <= 0 then
				-- WATCHDOG : mort → nettoyage DIFFÉRÉ. On ne peut PAS débinder
				-- un render step depuis son propre callback : ça échouait et
				-- coupait le nettoyage à mi-chemin → caméra + viewmodel figés.
				if not deadCleanupDone then
					deadCleanupDone = true
					task.defer(function()
						HardResetVisualState()
						CleanupAllMobileUI()
					end)
				end
				return
			end
			local rp = MyCharacter:FindFirstChild("HumanoidRootPart"); if not rp then return end
			-- 🎥 [Lock] une cinématique / un spectate / l'écran de mort possède la caméra : on ne se bat pas
			if camera:GetAttribute("KeepScriptable") then return end
			-- 🔒 [Lock] un autre script a remis la caméra en Custom ou libéré la souris (fin de l'écran de
			--    mort, nettoyage d'une ancienne arme…) : on reprend tout de suite. Avant, la vue restait
			--    « collée » derrière le perso avec un curseur libre qui ne la faisait plus tourner.
			if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
			if not IsMobile and not firstPerson and not workspace:GetAttribute("AnimEditorFreeze") then
				if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
					UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				end
				if UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = false end
			end
			ApplyAimAssist(dt)
			CameraPitch = math.clamp(CameraPitch, PitchMin, PitchMax)
			local rot
			if firstPerson then
				-- FP mobile : PAS de recul caméra (identique à la 1re personne PC,
				-- où la caméra Custom ne reçoit jamais CamRecoil)
				rot = CFrame.Angles(0, CameraYaw, 0) * CFrame.Angles(CameraPitch, 0, 0)
			else
				rot = CFrame.Angles(0, CameraYaw + CamRecoilYaw, 0) * CFrame.Angles(CameraPitch + CamRecoilPitch, 0, 0)
			end
			if firstPerson then
				-- 1re personne : caméra à la tête, perso caché localement
				local headPos = rp.Position + Vector3.new(0, 1.5, 0)
					+ (MyHumanoid and MyHumanoid.CameraOffset or Vector3.zero)
				camera.CFrame = CFrame.new(headPos) * rot
					* CFrame.Angles(0, 0, WeaponSharedState.GetCameraRoll())
				SetWholeCharacterHidden(true)
			else
				local charPos = rp.Position + Vector3.new(0, CameraHeight, 0)
				local lookAt = charPos + rot.RightVector * CameraSideOffset
				local desired = lookAt - rot.LookVector * CameraDistance + Vector3.new(0, CameraVerticalLift, 0)
				-- ⚡ paramètres de rayon préparés une fois (avant : recréés à chaque image)
				local rpar = Extra.camRay
				if not rpar then
					rpar = RaycastParams.new(); rpar.FilterType = Enum.RaycastFilterType.Exclude
					Extra.camRay = rpar
				end
				if Extra.camRayChar ~= MyCharacter or Extra.camRayVM ~= viewmodel then
					Extra.camRayChar, Extra.camRayVM = MyCharacter, viewmodel
					rpar.FilterDescendantsInstances = { MyCharacter, viewmodel }
				end
				local res = workspace:Raycast(lookAt, desired - lookAt, rpar)
				local camPos = desired
				if res then camPos = res.Position + (lookAt - res.Position).Unit * 0.5 end
				camera.CFrame = CFrame.new(camPos, lookAt) * CFrame.Angles(0, 0, WeaponSharedState.GetCameraRoll())
			end
			-- pendant la tirolienne, c'est elle qui pilote le HRP → on ne réécrit pas
			if not (MyCharacter and MyCharacter:GetAttribute("Ziplining")) then
				-- 🧱 [Lock] collé à un mur, la physique pouvait faire tourner le perso : on compare aussi
				--    l'orientation RÉELLE du perso (pas seulement la dernière envoyée). Écrit seulement
				--    s'il y a un écart → aucun coût réseau quand tout va bien.
				local lv = rp.CFrame.LookVector
				local dYaw = (CameraYaw - math.atan2(-lv.X, -lv.Z) + math.pi) % (2 * math.pi) - math.pi
				if lastSentYaw == nil or math.abs(CameraYaw - lastSentYaw) > YAW_THRESH
					or math.abs(dYaw) > math.rad(2) then
					rp.CFrame = CFrame.new(rp.Position) * CFrame.Angles(0, CameraYaw, 0)
					rp.AssemblyAngularVelocity = Vector3.zero
					lastSentYaw = CameraYaw
				end
				if MyHumanoid.AutoRotate then MyHumanoid.AutoRotate = false end
			end
			WeaponSharedState.SetCamera(CameraYaw, CameraPitch)
		end)
	end
	local function RestoreShiftLock(deferRestore, preserveTouches)
		if CameraRenderConnection then CameraRenderConnection:Disconnect(); CameraRenderConnection=nil end
		if camRenderBound then RunService:UnbindFromRenderStep(camRenderName); camRenderBound=false end
		WeaponSharedState.ReleaseCamera(camOwnerToken)
		if deferRestore then
			-- Au unequip : on NE rend PAS la caméra tout de suite. Elle reste
			-- Scriptable (figée sur place, render détaché) pendant 0.1 s max :
			--  • si une AUTRE arme s'équipe pendant ce délai, elle reprend la
			--    caméra avec le yaw/pitch partagé → AUCUN saut, transition invisible ;
			--  • sinon (vrai holster), on restaure Custom en CONSERVANT
			--    l'orientation actuelle → plus de téléportation de vue.
			local hum, off = MyHumanoid, SavedCameraOffset
			task.delay(0.1, function()
				if WeaponSharedState.CameraOwner() ~= nil then return end   -- une arme a repris la caméra
				if not camera or camera.CameraType ~= Enum.CameraType.Scriptable then return end
				local keepCF = camera.CFrame   -- orientation à préserver
				camera.CameraType = Enum.CameraType.Custom
				if hum and hum.Parent then
					camera.CameraSubject = hum
					hum.AutoRotate = true
					if off then hum.CameraOffset = off end
				end
				-- ré-applique l'orientation après que la caméra par défaut a repris
				-- la main → elle s'initialise sur cette direction, pas sur l'ancienne
				task.defer(function()
					if camera and camera.CameraType == Enum.CameraType.Custom then
						camera.CFrame = keepCF
					end
				end)
			end)
		else
			-- ne touche à la caméra QUE si elle est réellement en Scriptable
			-- (sortie de 3e personne). En 1re personne (Custom), réécrire
			-- CameraType/CameraSubject à chaque équipe est inutile et risqué.
			if camera and camera.CameraType == Enum.CameraType.Scriptable then
				local keepRot = camera.CFrame.Rotation   -- [GunKit P21] direction où tu regardais en 3e personne
				camera.CameraType = Enum.CameraType.Custom
				if MyHumanoid and MyHumanoid.Parent then
					camera.CameraSubject = MyHumanoid
				end
				-- retour en 1re personne : la caméra par défaut repartait de son ANCIENNE direction (celle d'avant
				-- la 3e personne) au premier mouvement de souris -> flick. On lui redonne la direction actuelle
				-- juste après qu'elle a repris la main.
				local function keep()
					if camera and camera.CameraType == Enum.CameraType.Custom then
						camera.CFrame = CFrame.new(camera.CFrame.Position) * keepRot
					end
				end
				task.defer(keep)
				RunService.RenderStepped:Once(keep)
			end
			if MyHumanoid and MyHumanoid.Parent then
				MyHumanoid.AutoRotate = true
				if SavedCameraOffset then MyHumanoid.CameraOffset = SavedCameraOffset end
			end
		end
		SavedCameraOffset=nil
		-- Entrer/sortir d’ADS ne doit pas couper le doigt qui tire ou oriente la caméra.
		if not preserveTouches then
			RightDragInput=nil; RightDragLastPos=nil
			if FireTouchInput then WeaponSharedState.ReleaseTouch(FireTouchInput) end
			FireTouchInput=nil; FireTouchLastPos=nil
		end
	end
	-- ========================================================
	-- LUNETTE (scope) — sniper
	-- ========================================================
	local function CreateScope()
		if not cfg.ADS.Scope or not MyPlayer then return end
		local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return end
		if ScopeGui then ScopeGui:Destroy() end
		local sg = Instance.new("ScreenGui"); sg.Name="ScopeGui"; sg.ResetOnSpawn=false
		sg.IgnoreGuiInset=true; sg.DisplayOrder=7; sg.Enabled=false
		sg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		sg.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None; sg.Parent=pg
		local cg = Instance.new("CanvasGroup"); cg.Name="Canvas"; cg.Size=UDim2.new(1,0,1,0)
		cg.BackgroundTransparency=1; cg.GroupTransparency=1; cg.Parent=sg
		ScopeScale = Instance.new("UIScale"); ScopeScale.Scale = 1.12; ScopeScale.Parent = cg
		-- bandes noires (letterbox) → fenêtre carrée centrée
		local function bar(name) local f=Instance.new("Frame"); f.Name=name
			f.BackgroundColor3=cfg.ADS.ScopeTint; f.BorderSizePixel=0; f.Parent=cg; return f end
		bar("Top"); bar("Bottom"); bar("Left"); bar("Right")
		-- lentille : cercle transparent + gros contour noir (= bord de lunette,
		-- recouvre les coins de la fenêtre carrée → rendu rond propre, sans asset)
		local lens=Instance.new("Frame"); lens.Name="Lens"; lens.AnchorPoint=Vector2.new(0.5,0.5)
		lens.Position=UDim2.new(0.5,0,0.5,0); lens.BackgroundTransparency=1; lens.Parent=cg
		local lc=Instance.new("UICorner"); lc.CornerRadius=UDim.new(1,0); lc.Parent=lens
		local ring=Instance.new("UIStroke"); ring.Name="Ring"; ring.Color=cfg.ADS.ScopeTint
		ring.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; ring.Parent=lens
		local rim=Instance.new("Frame"); rim.Name="Rim"; rim.AnchorPoint=Vector2.new(0.5,0.5)
		rim.Position=UDim2.new(0.5,0,0.5,0); rim.BackgroundTransparency=1; rim.Parent=cg
		local rimc=Instance.new("UICorner"); rimc.CornerRadius=UDim.new(1,0); rimc.Parent=rim
		local rims=Instance.new("UIStroke"); rims.Color=Color3.fromRGB(15,15,15); rims.Thickness=3; rims.Parent=rim
		-- réticule
		local function xhair(name,sx,sy) local f=Instance.new("Frame"); f.Name=name
			f.AnchorPoint=Vector2.new(0.5,0.5); f.Position=UDim2.new(0.5,0,0.5,0)
			f.Size=UDim2.new(0,sx,0,sy); f.BackgroundColor3=Color3.fromRGB(10,10,10)
			f.BorderSizePixel=0; f.Parent=cg; return f end
		xhair("XV",2,4000); xhair("XH",4000,2)
		local dot=xhair("XDot",6,6); local dc=Instance.new("UICorner"); dc.CornerRadius=UDim.new(1,0); dc.Parent=dot
		ScopeGui, ScopeCanvas = sg, cg
	end
	local function LayoutScope()
		if not ScopeGui then return end
		local vp = camera.ViewportSize
		local D = math.min(vp.X, vp.Y) * 0.86
		local centre = CursorPosLocal()
		local cx, cy = centre.X, centre.Y
		local left, top = cx - D/2, cy - D/2
		local right, bottom = cx + D/2, cy + D/2
		local cg = ScopeCanvas
		local function set(n, sx, sy, px, py)
			local f=cg:FindFirstChild(n); if f then f.Size=UDim2.fromOffset(sx,sy); f.Position=UDim2.fromOffset(px,py) end
		end
		set("Top", vp.X, math.max(0, math.ceil(top)), 0, 0)
		set("Bottom", vp.X, math.max(0, math.ceil(vp.Y - bottom)), 0, math.floor(bottom))
		set("Left", math.max(0, math.ceil(left)), math.ceil(D), 0, math.floor(top))
		set("Right", math.max(0, math.ceil(vp.X - right)), math.ceil(D), math.floor(right), math.floor(top))
		for _, name in ipairs({"Lens", "Rim", "XV", "XH", "XDot"}) do
			local part = cg:FindFirstChild(name)
			if part then part.Position = UDim2.fromOffset(cx, cy) end
		end
		local lens=cg:FindFirstChild("Lens")
		if lens then lens.Size=UDim2.fromOffset(D, D)
			local ring=lens:FindFirstChild("Ring"); if ring then ring.Thickness = D * 0.25 end
		end
		local rim=cg:FindFirstChild("Rim"); if rim then rim.Size=UDim2.fromOffset(D, D) end
	end
	-- ========================================================
	-- MOBILE UI (boutons)
	-- ========================================================
	local function CreateMobileFireButton()
		if not MyPlayer then return nil end
		local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return nil end
		local gui=Instance.new("ScreenGui"); gui.Name="MobileFireGui"; gui.ResetOnSpawn=false
		gui.IgnoreGuiInset=true; gui.DisplayOrder=20; gui.Parent=pg
		local b=Instance.new("ImageButton"); b.Name="FireButton"; b.Size=UDim2.new(0,90,0,90)
		b.Position=UDim2.new(1,-120,1,-200); b.AnchorPoint=Vector2.new(0,0)
		b.BackgroundColor3=Color3.fromRGB(0,0,0); b.BackgroundTransparency=0.5; b.BorderSizePixel=0
		b.Image=""; b.AutoButtonColor=false; b.Active=true; b.Parent=gui
		local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=b
		local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(0,0,0); s.Thickness=2; s.Parent=b
		local ic=Instance.new("ImageLabel"); ic.Name="Icon"; ic.Size=UDim2.new(0.5,0,0.5,0)
		ic.AnchorPoint=Vector2.new(0.5,0.5); ic.Position=UDim2.new(0.5,0,0.5,0)
		ic.BackgroundTransparency=1; ic.Image="rbxassetid://134341605166667"; ic.ScaleType=Enum.ScaleType.Fit; ic.Parent=b
		b.InputBegan:Connect(function(input)
			if input.UserInputType==Enum.UserInputType.Touch and not FireTouchInput then
				-- 🔒 le doigt appartient au tir ; les autres boutons l'ignoreront
				if not WeaponSharedState.ClaimTouch(input) then return end
				FireTouchInput=input; FireTouchLastPos=Vector2.new(input.Position.X, input.Position.Y)
				LeftButtonDown=true; b.BackgroundTransparency=0.2
				task.spawn(function()
					while FireTouchInput==input and MyHumanoid and MyHumanoid.Health>0 do
						task.spawn(OnFire)
						repeat task.wait(0.033) until not IsShooting or FireTouchInput~=input
						if FireTouchInput~=input then break end
					end
				end)
			end
		end)
		MobileFireButton=b
		return gui
	end
	local function CreateMobileReloadButton()
		if not MyPlayer then return nil end
		local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return nil end
		local gui=Instance.new("ScreenGui"); gui.Name="MobileReloadGui"; gui.ResetOnSpawn=false
		gui.IgnoreGuiInset=true; gui.DisplayOrder=20; gui.Parent=pg
		local b=Instance.new("ImageButton"); b.Name="ReloadButton"; b.Size=UDim2.new(0,60,0,60)
		b.Position=UDim2.new(1,-185,1,-160); b.AnchorPoint=Vector2.new(0,0)
		b.BackgroundColor3=Color3.fromRGB(0,0,0); b.BackgroundTransparency=0.5; b.BorderSizePixel=0
		b.Image=""; b.AutoButtonColor=false; b.Active=true; b.Parent=gui
		local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=b
		local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(0,0,0); s.Thickness=2; s.Parent=b
		local ic=Instance.new("ImageLabel"); ic.Name="Icon"; ic.Size=UDim2.new(0.5,0,0.5,0)
		ic.AnchorPoint=Vector2.new(0.5,0.5); ic.Position=UDim2.new(0.5,0,0.5,0)
		ic.BackgroundTransparency=1; ic.Image="rbxassetid://125510361738754"; ic.ScaleType=Enum.ScaleType.Fit; ic.Parent=b
		local active={}; local maxTap=20
		b.InputBegan:Connect(function(input)
			if input.UserInputType==Enum.UserInputType.Touch then
				-- 🔒 ignore un doigt déjà pris ailleurs (ex: drag depuis le tir)
				if not WeaponSharedState.ClaimTouch(input) then return end
				active[input]=Vector2.new(input.Position.X, input.Position.Y); b.BackgroundTransparency=0.2
			elseif input.UserInputType==Enum.UserInputType.MouseButton1 then
				active[input]=Vector2.new(input.Position.X, input.Position.Y); b.BackgroundTransparency=0.2
			end
		end)
		b.InputEnded:Connect(function(input)
			local sp=active[input]
			if sp then active[input]=nil; b.BackgroundTransparency=0.5
				WeaponSharedState.ReleaseTouch(input)   -- 🔓 libère (seulement si on le possédait)
				if (Vector2.new(input.Position.X, input.Position.Y) - sp).Magnitude <= maxTap then task.spawn(Reload) end
			end
		end)
		b.MouseLeave:Connect(function() b.BackgroundTransparency=0.5 end)
		return gui
	end
	local function CreateMobileViewButton()
		if not MyPlayer then return nil end
		local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return nil end
		local gui=Instance.new("ScreenGui"); gui.Name="MobileViewGui"; gui.ResetOnSpawn=false
		gui.IgnoreGuiInset=true; gui.DisplayOrder=20; gui.Parent=pg
		local b=Instance.new("TextButton"); b.Name="ViewButton"; b.Size=UDim2.new(0,52,0,52)
		b.Position=UDim2.new(1,-215,1,-335); b.AnchorPoint=Vector2.new(0,0)
		b.BackgroundColor3=Color3.fromRGB(0,0,0); b.BackgroundTransparency=0.5; b.BorderSizePixel=0
		b.Text="VIEW"; b.TextColor3=Color3.fromRGB(255,255,255); b.Font=Enum.Font.FredokaOne
		b.TextSize=12; b.AutoButtonColor=false; b.Active=true; b.Parent=gui
		local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=b
		local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(0,0,0); s.Thickness=2
		s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=b
		local active={}; local maxTap=20
		b.InputBegan:Connect(function(input)
			if input.UserInputType==Enum.UserInputType.Touch then
				if not WeaponSharedState.ClaimTouch(input) then return end
				active[input]=Vector2.new(input.Position.X, input.Position.Y)
				b.BackgroundTransparency=0.2
			end
		end)
		b.InputEnded:Connect(function(input)
			local sp=active[input]
			if sp then
				active[input]=nil; b.BackgroundTransparency=0.5
				WeaponSharedState.ReleaseTouch(input)
				if (Vector2.new(input.Position.X, input.Position.Y) - sp).Magnitude <= maxTap then
					WeaponSharedState.ToggleMode()
				end
			end
		end)
		return gui
	end
	-- ========================================================
	-- APPLY MODE (PC)
	-- ========================================================
	ApplyCurrentMode = function(useShared)
		if not MyCharacter then return end
		local third = WeaponSharedState.IsThirdPersonLock()
		local wasScriptable = camera.CameraType == Enum.CameraType.Scriptable
		RestoreShiftLock(false, IsMobile)
		-- Préserve les doigts actifs lors du passage FP/TP sur mobile.
		if IsMobile then
			-- mobile : TP = caméra scriptable ; FP = caméra scriptable 1re personne
			SetWholeCharacterHidden(false)
			SetupShiftLock(useShared, not third)
			if MobileCursorGui then MobileCursorGui:Destroy() end
			MobileCursorGui = buildCursor(false)
			return
		end
		if SavedMouseIconEnabled == nil then SavedMouseIconEnabled = UserInputService.MouseIconEnabled end
		if third then
			SetupShiftLock(useShared)
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
			if MobileCursorGui then MobileCursorGui:Destroy() end
			MobileCursorGui = buildCursor(false)
		else
			-- ⚠ ne force Default QUE si on SORT du mode caméra scriptable (3e pers).
			-- En 1re personne, dé-locker/re-locker la souris pendant un switch
			-- d'arme crée un delta parasite → c'était ÇA le saut de caméra.
			if wasScriptable then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			-- 🎯 même curseur qu'en mode lock / mobile : ton image, qui suit la souris image par
			--    image (Extra.startCross) et peut devenir rouge. Le curseur système est caché
			--    (sinon on en verrait deux).
			UserInputService.MouseIconEnabled = false
			if MyMouse then MyMouse.Icon = cfg.CustomCursorID end
			if MobileCursorGui then MobileCursorGui:Destroy() end
			MobileCursorGui = buildCursor(false)
		end
	end
	CleanupAllMobileUI = function()
		if Extra and Extra.destroyMobileAim then Extra.destroyMobileAim() end
		if SavedMouseIconEnabled ~= nil then
			UserInputService.MouseIconEnabled = SavedMouseIconEnabled; SavedMouseIconEnabled = nil
		end
		-- même logique : pas de dé-lock souris en 1re personne (switch d'arme)
		if (WeaponSharedState.IsThirdPersonLock() or IsMobile)
			and not (Extra and Extra.otherOwnsCam and Extra.otherOwnsCam()) then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		for _, g in pairs({MobileFireGui, MobileReloadGui, MobileViewGui, MobileCursorGui, ChargeBarGui}) do
			if g then g:Destroy() end
		end
		MobileFireGui, MobileReloadGui, MobileViewGui, MobileCursorGui, ChargeBarGui, MobileFireButton, ChargeBarFill = nil,nil,nil,nil,nil,nil,nil
		if MyPlayer then
			local pg = MyPlayer:FindFirstChild("PlayerGui")
			if pg then
				for _, ch in ipairs(pg:GetChildren()) do
					if ch.Name=="MobileFireGui" or ch.Name=="MobileReloadGui" or ch.Name=="MobileViewGui"
						or ch.Name=="MobileCursorGui" or ch.Name=="ChargeBarGui"
						or ch.Name=="MobileAimGui" or ch.Name=="MobileInspectGui" then ch:Destroy() end
				end
			end
		end
		LeftButtonDown=false; AutoShooting=false; AutoshootHoldElapsed=0
		RightDragInput=nil; RightDragLastPos=nil
		if FireTouchInput then WeaponSharedState.ReleaseTouch(FireTouchInput) end
		FireTouchInput=nil; FireTouchLastPos=nil
	end
	-- ========================================================
	-- FEEL : recul / sway / ADS sur les welds
	-- ========================================================
	-- 🆕 TOUT le nouvel état dans UNE table (limite Luau des 200 locals).
	Extra = {
		-- nom du render step (rangé ici plutôt qu'en local : la limite Luau des
		-- 200 registres est atteinte dans cette fonction)
		vmName = "WeaponViewmodel_" .. tool.Name .. "_" .. tostring(math.random(1, 1e9)),
		tracerShots = 0,        -- compteur "1 traînée sur N"
		bloom = 0,              -- dispersion accumulée par les tirs
		lastShotAt = 0,         -- horodatage du dernier tir (1re balle parfaite)
		dynOn = false,          -- dispersion dynamique active cette frame
		crossPx = -1,           -- dernier écartement de crosshair appliqué
		idlePhase = 0,
		idleAlpha = 0,
		idleRoot = CFrame.new(),
		cocked = false,         -- l'arme a déjà été armée cette vie
	}
	-- L'intention (bouton maintenu) survit au reload ; la visée effective non.
	Extra.aimInput = { mouse = false, key = false, mobile = false, pad = false }   -- [Combat C3] pad = manette
	Extra.aimLead = function(duration)
		local value = tonumber(tool:GetAttribute("ReloadAimLead")) or cfg.LiveFeel.ReloadAimLead
		return math.clamp(value, 0, math.max(0, duration) * 0.5)
	end
	Extra.chamberDuration = function()
		if not Extra.wasEmpty then return 0 end
		local R, CK = cfg.Reload, cfg.Equip.Cock
		if (R.RackPump or R.PumpAfterShot) and R.RackOnEmpty ~= false then
			return (R.RackPump or R.PumpAfterShot).Time or 0.34
		elseif CK and CK.Enabled and CK.RackOnEmpty ~= false then
			return CK.AfterShotTime or CK.Time or 0.45
		end
		return 0
	end
	Extra.reloadWindow = function(duration)
		local chamber = Extra.chamberDuration()
		if Extra.reloadAimAt and os.clock() >= Extra.reloadAimAt then return end
		Extra.reloadAimAt = os.clock() + duration + chamber
		- Extra.aimLead(chamber > 0 and chamber or duration)
	end
	Extra.aimBusy = function()
		local now = os.clock()
		return Equipping or Extra.inspecting
			or (Reloading and now < (Extra.reloadAimAt or math.huge))
			or (Pumping and now < (Extra.chamberAimAt or math.huge))
			or (Extra.cocking and now < (Extra.chamberAimAt or math.huge))
	end
	Extra.updateAim = function()
		if not SetAiming then return end
		local held = Extra.aimInput
		-- Ne garde jamais une intention ADS tactile en troisième personne.
		if IsMobile and not IsActuallyFirstPerson() then held.mobile = false end
		-- Rattrape aussi un relâché perdu quand la fenêtre perd le focus.
		if held.mouse and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then held.mouse = false end
		if held.key and not UserInputService:IsKeyDown(Enum.KeyCode.Q) then held.key = false end
		if held.pad and not (CS.Gamepad and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, CS.Gamepad.Aim)) then held.pad = false end   -- [Combat C3b]
		local alive = MyCharacter and MyCharacter == Players.LocalPlayer.Character
			and tool.Parent == MyCharacter and MyHumanoid and MyHumanoid.Health > 0
		local busy = Extra.aimBusy()
		SetAiming((held.mouse or held.key or held.mobile or held.pad) and alive and not busy   -- [Combat C3c]
			and IsActuallyFirstPerson() and not WeaponSharedState.AreActionsBlocked() or false)
		if Extra.refreshMobileAim then Extra.refreshMobileAim() end
	end
	Extra.requestAim = function(source, on)
		Extra.aimInput[source] = on
		Extra.updateAim()
	end
	Extra.clearAimInput = function()
		if Extra.visualShots then table.clear(Extra.visualShots); Extra.shotSide = 0 end
		Extra.aimInput.mouse, Extra.aimInput.key, Extra.aimInput.mobile = false, false, false
		Extra.aimInput.pad = false   -- [Combat C3d]
		if SetAiming then SetAiming(false) end
		if Extra.refreshMobileAim then Extra.refreshMobileAim() end
	end
	-- ADS tactile à bascule : pas besoin de tenir un deuxième doigt pendant le tir.
	Extra.refreshMobileAim = function()
		local b = Extra.mobileAimButton
		if not b then return end
		b.Visible = IsActuallyFirstPerson() -- uniquement en FP, comme sur PC
		local state = Aiming and "active" or (Extra.aimInput.mobile and "pending" or "off")
		if Extra.mobileAimVisual == state then return end
		Extra.mobileAimVisual = state
		b.BackgroundTransparency = state == "active" and 0.2 or (state == "pending" and 0.35 or 0.5)
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = state ~= "off" and Color3.fromRGB(235,235,235) or Color3.fromRGB(0,0,0)
		end
	end
	Extra.toggleMobileAim = function()
		if not IsMobile or not cfg.ADS.Enabled then return end
		if not MyHumanoid or MyHumanoid.Health <= 0 or tool.Parent ~= MyCharacter then return end
		local settings = cfg.LiveFeel.MobileAim or {}
		if settings.Enabled == false then return end
		if not IsActuallyFirstPerson() then
			Extra.requestAim("mobile", false)
			return
		end
		Extra.requestAim("mobile", not Extra.aimInput.mobile)
	end
	Extra.destroyMobileAim = function()
		if Extra.mobileAimEnd then Extra.mobileAimEnd:Disconnect(); Extra.mobileAimEnd = nil end
		if Extra.mobileAimTouches then
			for input in pairs(Extra.mobileAimTouches) do WeaponSharedState.ReleaseTouch(input) end
		end
		Extra.mobileAimTouches = nil
		if Extra.mobileAimGui then Extra.mobileAimGui:Destroy() end
		Extra.mobileAimGui, Extra.mobileAimButton, Extra.mobileAimVisual = nil, nil, nil
	end
	Extra.createMobileAim = function()
		Extra.destroyMobileAim()
		local pg = MyPlayer and MyPlayer:FindFirstChild("PlayerGui")
		if not pg then return end
		-- Élimine aussi les anciens boutons persistants après une mort / mise à jour.
		for _, gui in ipairs(pg:GetChildren()) do
			if gui.Name == "MobileInspectGui" or gui.Name == "MobileAimGui" then gui:Destroy() end
		end
		local settings = cfg.LiveFeel.MobileAim or {}
		if not IsMobile or not cfg.ADS.Enabled or settings.Enabled == false then return end
		local reloadButton = MobileReloadGui and MobileReloadGui:FindFirstChild("ReloadButton")
		if not reloadButton then return end
		local size = math.max(32, tonumber(settings.Size) or 60)
		local x, y = tonumber(settings.OffsetX) or -185, tonumber(settings.OffsetY) or -160
		local gap = math.max(0, tonumber(settings.Gap) or 5)
		-- Clone le style du reload ; les connexions d'entrée ne sont pas clonées.
		local b = reloadButton:Clone()
		b.Name = "AimButton"; b.Size = UDim2.fromOffset(size, size)
		b.Position = UDim2.new(1, x, 1, y)
		reloadButton.Size = b.Size
		reloadButton.Position = UDim2.new(1, x - size - gap, 1, y)
		local gui = Instance.new("ScreenGui")
		gui.Name = "MobileAimGui"; gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true; gui.DisplayOrder = 20; gui.Parent = pg
		b.Parent = gui
		local icon = b:FindFirstChild("Icon")
		local asset = tostring(settings.Image or "")
		if icon then
			local scale = math.clamp(tonumber(settings.IconScale) or 0.5, 0.1, 1)
			icon.Size = UDim2.fromScale(scale, scale)
			icon.Image = asset; icon.Visible = asset ~= ""
		end
		if asset == "" then
			local label = Instance.new("TextLabel")
			label.Name = "AimLabel"; label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1,1); label.Text = "ADS"
			label.Font = Enum.Font.FredokaOne; label.TextSize = 14
			label.TextColor3 = Color3.fromRGB(255,255,255); label.Parent = b
		end
		Extra.mobileAimGui, Extra.mobileAimButton = gui, b
		local active = {}
		Extra.mobileAimTouches = active
		b.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			if next(active) or not WeaponSharedState.ClaimTouch(input) then return end
			active[input] = Vector2.new(input.Position.X, input.Position.Y)
		end)
		-- Écoute globale : libère le doigt même s'il finit en dehors du bouton.
		Extra.mobileAimEnd = UserInputService.InputEnded:Connect(function(input)
			local start = active[input]
			if not start then return end
			active[input] = nil
			WeaponSharedState.ReleaseTouch(input)
			if input.UserInputState == Enum.UserInputState.Cancel then return end
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local origin, bounds = b.AbsolutePosition, b.AbsoluteSize
			if (pos - start).Magnitude <= 20 and pos.X >= origin.X and pos.Y >= origin.Y
				and pos.X <= origin.X + bounds.X and pos.Y <= origin.Y + bounds.Y then
				Extra.toggleMobileAim()
			end
		end)
		Extra.refreshMobileAim()
	end

	-- Attribut booléen facultatif sur le Tool pour tester le gel en direct.
	Extra.freezeAim = function()
		if Extra.pivotSettings then return Extra.pivotSettings.freeze end
		local override = tool:GetAttribute("DisableAllAimMotion")
		if type(override) == "boolean" then return override end
		return cfg.ADS.DisableAllAimMotion == true
	end
	Extra.pivotSettings = AimPivotSettings.Read(tool)
	Extra.aimSway = function()
		return (Extra.pivotSettings and Extra.pivotSettings.enabled) or cfg.ADS.AimSway
	end
	Extra.noMoveTilt = function()
		if Extra.pivotSettings and Extra.pivotSettings.enabled then return false end
		return cfg.ADS.NoMoveTilt
	end
	Extra.pivotLocal = function()
		if not Extra.vmHandleRel then return nil end
		if Extra.pivotSettings then
			if not Extra.pivotSettings.enabled then return nil end
			return Extra.vmHandleRel * AimPivotSettings.Frame(Extra.pivotSettings)
		end
		if typeof(cfg.ADS.AimPivotOffset) == "CFrame" then
			return Extra.vmHandleRel * cfg.ADS.AimPivotOffset
		end
		-- Référence sur l'arme source : on peut déplacer cet Attachment en Play.
		local ap = Handle:FindFirstChild(cfg.ADS.AimPivotName)
		if ap and ap:IsA("Attachment") then return Extra.vmHandleRel * ap.CFrame end
		local sight = Extra.sightLocal(tool)
		return (sight and Extra.vmHandleRel * sight) or vmAimPointLocal
	end
	Extra.pivotActive = function()
		local enabled = Extra.pivotSettings and Extra.pivotSettings.enabled
		if Extra.pivotSettings == nil then enabled = cfg.ADS.UseAimPivot ~= false end
		return enabled and Extra.pivotLocal() ~= nil
	end
	-- Tirages fixes par coup : jamais math.random() à chaque image.
	Extra.visualShots = {}
	Extra.visualRng = Random.new()
	Extra.shotSide = 0
	Extra.recordVisualShot = function()
		if Extra.share then Extra.share:Shot() end
		local R = cfg.LiveFeel.Recoil
		if not Aiming or Extra.freezeAim() or not R.Enabled or not cfg.LiveFeel.Motion.Enabled then return end
		local now = os.clock()
		for i = #Extra.visualShots, 1, -1 do
			if now - Extra.visualShots[i].t > R.Lifetime then table.remove(Extra.visualShots, i) end
		end
		-- La prise conserve un peu d'inertie latérale entre deux coups.
		Extra.shotSide = Extra.shotSide * 0.30 + Extra.visualRng:NextNumber(-1,1) * 0.70
		Extra.visualShots[#Extra.visualShots+1] = {
			t=now, power=1+Extra.visualRng:NextNumber(-R.Variation,R.Variation), side=Extra.shotSide,
		}
		while #Extra.visualShots > math.max(1, R.MaxShots) do table.remove(Extra.visualShots,1) end
	end
	-- Pose de slide indépendante du plafond des micro-mouvements ADS.
	Extra.updateSlideLean = function(dt)
		local char = MyCharacter
		local enabled = char and char:GetAttribute("WeaponSlideLeanEnabled") == true
		local active = enabled and char:GetAttribute("WeaponSliding") == true
		Extra.slideLean = Extra.slideLean or {weight=0, velocity=0, angle=0}
		local s = Extra.slideLean
		local seconds = char and char:GetAttribute(active and "WeaponSlideLeanIn" or "WeaponSlideLeanOut")
		s.weight, s.velocity = AimPivotSettings.Smooth(s.weight, s.velocity, active and 1 or 0,
			tonumber(seconds) or (active and 0.12 or 0.18), math.clamp(dt,0,1))
		s.weight = math.clamp(s.weight,0,1)
		s.angle = math.rad(math.clamp(tonumber(char and char:GetAttribute("WeaponSlideLeanAngle")) or 30,-60,60))
	end
	Extra.applySlideLean = function()
		local s = Extra.slideLean
		if not s or s.weight < 1e-5 then return end
		local amount = s.weight
		-- L'option du panneau de gel ADS reste prioritaire. Hors ADS, le slide reste visible.
		if Extra.freezeAim() or not cfg.LiveFeel.Motion.Enabled then amount *= 1 - AimAlpha end
		local angle = s.angle * amount
		if math.abs(angle) < 1e-5 or not vmRoot then return end
		local pivot = Extra.pivotLocal() or Extra.vmHandleRel or CFrame.identity
		local gw = Extra.gunWeld
		if gw and gw.Parent and vmRightWeld and Extra.vmHandleRel then
			-- Point réel APRES les poses de bras/reload et leur compensation ADS.
			local actual = vmRightWeld.C0 * vmRightWeld.C1:Inverse() * gw.C0 * gw.C1:Inverse()
			pivot = actual * Extra.vmHandleRel:Inverse() * pivot
		end
		local point = (vmRoot.CFrame * pivot).Position
		local anchor = CFrame.new(point) * (camera.CFrame - camera.CFrame.Position)
		-- Rotation de toute la racine : les DEUX bras et le gun penchent ensemble.
		vmRoot.CFrame = anchor * CFrame.Angles(0,0,angle) * anchor:Inverse() * vmRoot.CFrame
	end
	Extra.liveAimMotion = function(dt)
		Extra.updateSlideLean(dt)
		local root = MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
		local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
		local direction = MyHumanoid and MyHumanoid.MoveDirection or Vector3.zero
		Extra.motionState = Extra.motionState or AimPivotSettings.NewMotionState()
		return AimPivotSettings.StepMotion(Extra.motionState, dt, {
			grounded=not MyHumanoid or MyHumanoid.FloorMaterial ~= Enum.Material.Air,
			vy=velocity.Y,
			-- La pose fixe du slide prend progressivement la place du strafe ADS.
			strafe=camera.CFrame:VectorToObjectSpace(direction).X * (1 - Extra.slideLean.weight),
			sliding=MyCharacter and MyCharacter:GetAttribute("WeaponSliding") == true,
		}, cfg.LiveFeel.Motion)
	end
	Extra.applyAimMotion = function(base)
		local pivot = Extra.pivotActive() and Extra.pivotLocal()
		if not pivot then return Extra.freezeAim() and base or base * Aim.Motion end
		-- Le point choisi devient le point au centre, même s'il est distinct du repère d'œil.
		local pc = camera.CFrame:PointToObjectSpace((base * pivot).Position)
		base = base + camera.CFrame:VectorToWorldSpace(Vector3.new(-pc.X, -pc.Y, 0)) * AimAlpha
		if Extra.freezeAim() or not cfg.LiveFeel.Motion.Enabled then return base end
		local d, F, R = Extra.pivotSettings, cfg.LiveFeel.Motion, cfg.LiveFeel.Recoil
		local back, shotRoll = AimPivotSettings.RecoilAt(Extra.visualShots, os.clock(), R)
		-- Nouvelle piste unique en repère caméra. L'ancien sway, les FireKick/Yaw
		-- et les translations latérales ne repassent plus par le pivot.
		-- On AJOUTE les composantes : multiplier un CFrame de profondeur après une
		-- rotation aurait réorienté le recul et créé un faux mouvement X/Y.
		local live = Extra.liveMotion or CFrame.identity
		local pitch, yaw, roll = live:ToEulerAnglesXYZ()
		local motion = CFrame.new(0, 0, (math.clamp(live.Position.Z, -F.MaxDepth, F.MaxDepth) + back) * AimAlpha)
			* CFrame.Angles(pitch * AimAlpha, yaw * AimAlpha, (roll + shotRoll) * AimAlpha)
		return base * AimPivotSettings.Transform(pivot, motion,
			d and d.scale or cfg.ADS.PivotMotionScale, d == nil or d.lockAxis,
			0, F.MaxAngle, base:ToObjectSpace(camera.CFrame), F.MaxDepth + R.MaxBack)
	end
	-- Le bras et la piste du gun peuvent encore animer le reload. On compense
	-- leur pose sur la racine du viewmodel pour maintenir le point du viseur.
	Extra.stabilizeAnimatedGrip = function()
		if AimAlpha <= 0.001 or not (Extra.pivotActive() or Extra.freezeAim()) then return end
		local gw = Extra.gunWeld
		if not (gw and gw.Parent and vmRightWeld and Extra.vmHandleRel) then return end
		local actual = vmRightWeld.C0 * vmRightWeld.C1:Inverse() * gw.C0 * gw.C1:Inverse()
		local correction = Extra.vmHandleRel * actual:Inverse()
		vmRoot.CFrame *= CFrame.identity:Lerp(correction, AimAlpha)
	end
	-- 🎯 REPÈRE D'ŒIL (« AimSight »). Six attributs posés par l'onglet VISÉE de
	-- l'Anim Studio, EN COORDONNÉES DU HANDLE. C'est toute la différence avec
	-- l'ancien réglage : le repère est une caractéristique de l'ARME, pas une
	-- position déduite du bras. Refais ta prise d'arme, change le weld, publie
	-- une nouvelle pose de repos : le repère ne bouge pas, donc la visée non
	-- plus.
	Extra.sightLocal = function(tl)
		if not tl or tl:GetAttribute("SightOn") ~= true then return nil end
		local sx = tl:GetAttribute("SightX"); local sy = tl:GetAttribute("SightY")
		local sz = tl:GetAttribute("SightZ"); local ax = tl:GetAttribute("SightRX")
		local ay = tl:GetAttribute("SightRY"); local az = tl:GetAttribute("SightRZ")
		if not (sx or sy or sz or ax or ay or az) then return nil end
		return CFrame.new(sx or 0, sy or 0, sz or 0)
			* CFrame.Angles(math.rad(ax or 0), math.rad(ay or 0), math.rad(az or 0))
	end
	-- écarte les 4 branches du crosshair selon la dispersion : le joueur VOIT
	-- sa précision baisser quand il court ou saute.
	-- 🆕 SAUT / STRAFE EN AXES DU MONDE.
	-- Extra.mvW est le déplacement voulu, exprimé en axes du MONDE. Ici on le
	-- ramène dans le repère de la pièce qui porte le weld (le Torse en 3e
	-- personne, la racine du viewmodel en 1re). Le résultat se multiplie EN
	-- DERNIER dans le C1 : il ne traverse donc aucune rotation d'animation, et
	-- « vers le haut » reste vers le haut même quand le bras est tourné à 90°
	-- par un rechargement.
	Extra.mvOf = function(ref, side)
		if not (Extra.mvW and ref and ref.Parent) then return CFrame.identity end
		return CFrame.new(ref.CFrame:VectorToObjectSpace(Extra.mvW))
			* CFrame.Angles((side == "R") and (Extra.mvR or 0) or (Extra.mvL or 0), 0, Extra.mvZ or 0)
	end
	-- 🆕 LE VISEUR SUIT LA SOURIS, SANS RETARD.
	-- Le décalage que tu vois sur certains appareils vient de ce que l'UI est
	-- écrite en Heartbeat : elle est posée APRÈS le rendu, donc elle affiche
	-- toujours la position de l'image d'avant. Ici on écrit en RenderStepped,
	-- juste après la caméra, avec la position souris de CETTE image : le viseur
	-- est dessiné au bon endroit dès la première frame, sur n'importe quel
	-- appareil.
	-- 🧩 la même action sur l'arme réelle ET sur celle du viewmodel : en 3e
	-- personne tu vois la première, en 1re la seconde, il faut les deux.
	Extra.partsDo = function(fn)
		if Extra.parts then fn(Extra.parts) end
		if Extra.vmParts then fn(Extra.vmParts) end
	end
	-- 🎯 …SAUF POUR CE QUI TOMBE PAR TERRE. Il n'y a qu'UN chargeur à lâcher :
	-- celui de l'arme que tu VOIS. En le lâchant sur les deux index, on créait
	-- deux objets — celui du viewmodel (dans ta main) et celui de l'arme réelle
	-- (restée à sa place sur le gun) : d'où le chargeur qui semblait « se
	-- téléporter à son endroit initial » avant de tomber.
	-- 🎯 ON LÂCHE DEPUIS L'EXEMPLAIRE QUI A QUITTÉ L'ARME, pas depuis celui
	-- qu'on suppose visible. Choisir « celui que le joueur voit » ne suffisait
	-- pas : si l'un des deux n'avait pas suivi la main (viewmodel reconstruit
	-- entre-temps, bras introuvable sur ce rig, index pas encore prêt), on
	-- lâchait celui resté soudé au gun — et le chargeur tombait de sa place
	-- d'origine. On regarde donc l'ÉTAT RÉEL, pas la vue.
	-- ════════════════════════════════════════════════════════
	-- ⚡ MODE PERFORMANCE — la décoration de l'arme s'éteint
	-- ════════════════════════════════════════════════════════
	-- Règle : on ne SUPPRIME jamais rien et on n'AJOUTE jamais rien. On note la
	-- valeur d'origine au moment où on éteint, et on la rend telle quelle quand
	-- le joueur ressort du mode. Une arme jamais passée en mode performance
	-- n'est donc jamais touchée du tout.
	-- Ce qui s'éteint : particules, traînées, rayons, fumée, feu, étincelles et
	-- lumières PORTÉES PAR L'ARME. Jamais les sons, les soudures, l'interface,
	-- ni quoi que ce soit dont l'arme a besoin pour fonctionner.
	Extra.perfSaved = Extra.perfSaved or {}
	Extra.perfOff = function(root)
		if not root then return end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")
				or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles")
				or d:IsA("Light") then
				if Extra.perfSaved[d] == nil then Extra.perfSaved[d] = d.Enabled end
				pcall(function() d.Enabled = false end)
			end
		end
	end
	-- 🥔 si le panneau Settings coupe déjà les particules (SettingPerfParticles
	-- = false, ce que fait le Performance Mode), c'est LUI qui gère les
	-- émetteurs : deux systèmes qui éteignent la même chose se volent la
	-- valeur d'origine, et un émetteur pouvait rester éteint pour de bon.
	Extra.perfOwnsFX = function()
		return not (MyPlayer and MyPlayer:GetAttribute("SettingPerfParticles") == false)
	end
	Extra.perfApply = function(on)
		if on then
			Extra.perfOn = true
			if Extra.perfOwnsFX() then
				Extra.perfOff(tool)
				Extra.perfOff(viewmodel)
			end
		else
			Extra.perfOn = false
			for d, was in pairs(Extra.perfSaved) do
				if d and d.Parent then pcall(function() d.Enabled = was end) end
			end
			Extra.perfSaved = {}
			-- le viewmodel a été cloné pendant le mode perf (émetteurs éteints) :
			-- on le reconstruit depuis l'arme, qui a retrouvé ses valeurs.
			Extra.vmRebuild = true
		end
		-- les effets que NOUS créons (éclair de bouche, douilles) suivent aussi
		FX2.PerfMode = on and true or false
	end
	Extra.perfWanted = function()
		return MyPlayer and MyPlayer:GetAttribute("SettingPerfMode") == true
	end

	Extra.partsDrop = function(name, fn)
		-- 🚫 la pièce lâchée ne doit jamais se « poser » sur le joueur, son
		-- arme ou le viewmodel : elle resterait suspendue en l'air dès qu'il
		-- s'éloigne. Le viewmodel est reconstruit en cours de partie, donc on
		-- réarme le filtre ici, pas seulement au premier tir.
		-- ⚠️ la CAMÉRA aussi : le viewmodel y est rangé, et il est juste devant
		-- l'objectif. Sans lui dans la liste, la pièce lâchée se « posait »
		-- dessus et restait suspendue en l'air. La variable `viewmodel` peut
		-- être nulle à cet instant — la caméra, elle, est toujours là.
		FX2.ShellIgnore({ MyCharacter, tool, viewmodel, workspace.CurrentCamera })
		local a, b = Extra.parts, Extra.vmParts
		local seen = (b and viewmodel and IsActuallyFirstPerson()) and b or a
		local pick = nil
		if seen and FX2.PartFree(seen, name) then pick = seen
		elseif a and FX2.PartFree(a, name) then pick = a
		elseif b and FX2.PartFree(b, name) then pick = b
		else pick = seen end
		if not pick then return end
		fn(pick)
		-- tout autre exemplaire est simplement éteint : sinon il réapparaîtrait
		-- sur l'arme au prochain changement de vue.
		if a and a ~= pick then FX2.PartHide(a, name, true) end
		if b and b ~= pick then FX2.PartHide(b, name, true) end
	end
	-- 🔓 CULASSE OUVERTE À VIDE. Tant qu'il n'y a plus de cartouche, la pièce
	-- reste reculée ; elle revient d'un coup au rechargement. On n'écrit que
	-- sur le CHANGEMENT : zéro coût le reste du temps.
	Extra.slideTick = function()
		local P = cfg.Parts
		if not P then return end
		for name, d in pairs(P) do
			if d.LockBack then
				local want = (AmmoInClip <= 0) and not Reloading
				Extra.slideState = Extra.slideState or {}
				if Extra.slideState[name] ~= want then
					Extra.slideState[name] = want
					Extra.partsDo(function(idx)
						FX2.PartSet(idx, name, want and d.LockBack or nil)
					end)
				end
			end
		end
	end
	-- 🧲 LE CHARGEUR TOMBE. Purement local : la pièce est masquée chez toi et
	-- une copie tombe par terre avec la vitesse de ton personnage. Les autres
	-- joueurs voient l'arme normale — rien ne part sur le réseau.
	Extra.magDrop = function(name, d, expectedReloadTok, expectedCutTok)

		-- 🎟️ Le chargeur appartient à un reload précis.
		if expectedReloadTok and Extra.reloadTok ~= expectedReloadTok then
			return
		end

		if expectedCutTok and (Extra.cutTok or 0) ~= expectedCutTok then
			return
		end

		if not MyHumanoid or MyHumanoid.Health <= 0 then
			return
		end

		if not MyCharacter or not MyCharacter.Parent then
			return
		end

		if not Reloading then
			return
		end

		Extra.magState = {
			a = "throw",
			tok = Extra.magTok or 0
		}

		local root = MyCharacter:FindFirstChild("HumanoidRootPart")
		local carry = root and root.AssemblyLinearVelocity or Vector3.zero

		Extra.partsDrop(name, function(idx)

			-- 🧯 deuxième vérification juste avant le clone
			if expectedReloadTok and Extra.reloadTok ~= expectedReloadTok then
				return
			end

			if expectedCutTok and (Extra.cutTok or 0) ~= expectedCutTok then
				return
			end

			if not MyHumanoid or MyHumanoid.Health <= 0 then
				return
			end

			if not MyCharacter or not MyCharacter.Parent then
				return
			end

			if not Reloading then
				return
			end

			local e = idx[name]
			if not e or e.dropped then
				return
			end

			local cf = FX2.PartWorld(idx, name)

			FX2.PartDrop(
				idx,
				name,
				carry
					+ cf.UpVector * (d.DropUp or -1.5)
					+ cf.RightVector * ((math.random()-0.5) * 2),
				{
					life = d.Life or 8,
					spin = d.Spin or 7
				}
			)
		end)
	end
	Extra.magBack = function(name)
		Extra.magState = nil
		Extra.partsDo(function(idx) FX2.PartRestore(idx, name) end)
	end
	-- 🧩 LA PISTE DES PIÈCES. Chaque keyframe porte la pose de chaque morceau
	-- animé ; on interpole, image par image, exactement comme les bras. Une
	-- pièce absente d'une keyframe revient à sa place : elle n'est jamais
	-- laissée dans un état bâtard.
	Extra.playPartTrack = function(keys, dur)
		if type(keys) ~= "table" or #keys < 2 then return false end
		dur = math.max(0.03, dur or 0.4)
		local t0 = tick()
		Extra.partTok = (Extra.partTok or 0) + 1
		local tok = Extra.partTok
		local cut = Extra.cutTok or 0
		if Extra.gkSync then Extra.gkSync("start", keys, dur) end   -- [GunKit P19b]
		-- les pièces que CETTE piste anime : ce sont les seules qu'elle remettra
		-- en place à la fin. Une piste ne touche pas aux pièces des autres.
		local mine = {}
		for _, k in ipairs(keys) do
			if type(k.pt) == "table" then for nm in pairs(k.pt) do mine[nm] = true end end
		end
		while true do
			-- une autre piste a pris la main : elle écrira ses propres poses
			if tok ~= Extra.partTok then break end
			if (Extra.cutTok or 0) ~= cut then break end   -- 🎟 geste interrompu
			if not MyHumanoid or MyHumanoid.Health <= 0 then break end
			local p = math.clamp((tick() - t0) / dur, 0, 1)
			local from, to = keys[1], keys[#keys]
			for i = 1, #keys - 1 do
				if p >= (keys[i].t or 0) and p <= (keys[i+1].t or 1) then
					from, to = keys[i], keys[i+1]; break
				end
			end
			local seg = (to.t or 1) - (from.t or 0)
			local x = seg > 0 and math.clamp((p - (from.t or 0)) / seg, 0, 1) or 1
			if to.ease == "in" then x = x * x
			elseif to.ease == "out" then x = 1 - (1-x)*(1-x)
			elseif to.ease ~= "linear" then x = x * x * (3 - 2*x) end
			Extra.partsDo(function(idx)
				for nm in pairs(idx) do
					local a = from.pt and from.pt[nm]
					local b = to.pt and to.pt[nm]
					if a or b then
						FX2.PartSet(idx, nm, (a or CFrame.new()):Lerp(b or CFrame.new(), x))
					end
				end
			end)
			if p >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		-- 🧹 FIN DE PISTE : CHAQUE PIÈCE REVIENT À SA PLACE, TOUJOURS.
		-- Rien ne la remettait en place à la fin : la pièce gardait la dernière
		-- valeur écrite — donc la pose de la dernière keyframe qui la
		-- mentionnait, pas sa place d'origine. C'est ça qui laissait le
		-- chargeur ET la culasse décalés après l'animation.
		-- On ne touche pas à une pièce tenue par une main ou déjà lâchée :
		-- celle-là a sa propre vie (la piste du chargeur s'en occupe).
		Extra.partsDo(function(idx)
			for nm in pairs(mine) do
				local e = idx[nm]
				if e and not e.free and not e.dropped then FX2.PartSet(idx, nm, nil) end
			end
		end)
		-- la culasse ouverte à vide doit se réafficher : on force sa réévaluation
		Extra.slideState = nil
		if Extra.gkSync then Extra.gkSync("end", keys, dur) end   -- [GunKit P19c]
		return true
	end
	-- 🧲 LA PISTE DU CHARGEUR : chaque événement part à son instant.
	Extra.playMagTrack = function(list, dur)
		if type(list) ~= "table" or #list == 0 then return false end
		local mg = Extra.magName
		if type(mg) ~= "string" or mg == "" then return false end
		dur = math.max(0.03, dur or 0.4)
		-- 🧹 ON REPART TOUJOURS D'UNE PLACE PROPRE. Si le rechargement précédent
		-- a été coupé (tir, changement d'arme, mort) le filet de fin n'a pas
		-- forcément joué : le chargeur restait décroché, et le rechargement
		-- suivant partait d'un état bâtard. Une remise en place ne coûte rien.
		Extra.magState = nil
		Extra.partsDo(function(idx) FX2.PartRestore(idx, mg) end)
		-- 🎟 UN JETON PAR RECHARGEMENT. Sans lui, les événements et le filet de
		-- fin du rechargement PRÉCÉDENT continuaient de tomber au milieu du
		-- suivant : le chargeur repartait dans la main, ou revenait trop tôt.
		-- Deux rechargements rapprochés suffisaient à tout désynchroniser.
		Extra.magTok = (Extra.magTok or 0) + 1
		local tok = Extra.magTok
		local cut = Extra.cutTok or 0
		for _, e in ipairs(list) do
			task.delay(math.max(0, e.t or 0) * dur, function()
				if tok ~= Extra.magTok or (Extra.cutTok or 0) ~= cut then return end
				if not MyHumanoid or MyHumanoid.Health <= 0 then return end
				if tool.Parent ~= MyCharacter then return end
				Extra.magEvent(mg, e)
			end)
		end
		-- filet : quoi qu'il arrive, le chargeur revient à sa place à la fin.
		-- ⚠️ PLUS DE CONDITION « l'arme est en main ». Avant, si l'arme était
		-- rangée pile à cet instant (changement d'arme, sprint, mort), le filet
		-- passait son tour ET effaçait l'état : le chargeur restait soudé à son
		-- ancre, donc SUSPENDU EN L'AIR, et plus rien ne pouvait le récupérer.
		-- Remettre une pièce en place sur une arme rangée ne coûte rien et ne
		-- se voit pas — c'est l'inverse qui coûtait cher.
		task.delay(dur + 0.05, function()
			if tok ~= Extra.magTok then return end
			Extra.magState = nil
			Extra.partsDo(function(idx) FX2.PartRestore(idx, mg) end)
		end)
		-- 🧯 SECOND FILET, 2 s plus tard. Si le premier est tombé au mauvais
		-- moment (viewmodel en pleine reconstruction, index remplacé entre
		-- deux images), le chargeur ne doit pas rester en l'air pour autant.
		-- Le jeton garantit qu'on ne dérange aucun geste ultérieur : si une
		-- autre piste de chargeur a démarré, celle-ci a déjà rendu la main.
		task.delay(dur + 2, function()
			if tok ~= Extra.magTok then return end
			Extra.magState = nil
			Extra.partsDo(function(idx) FX2.PartRestore(idx, mg) end)
		end)
		return true
	end
	-- 🔁 Le viewmodel est DÉTRUIT ET RECONSTRUIT en cours de route (changement de
	-- pose publiée, mort, dézoom…). Sans mémoire, son chargeur repartait soudé
	-- au gun alors que le vrai était dans la main : le lancer suivant tombait
	-- de la place d'origine. On garde donc l'état et on le rejoue à la
	-- reconstruction, pour que les deux armes soient toujours d'accord.
	Extra.vmSync = function()
		local st, mg = Extra.magState, Extra.magName
		if not (st and Extra.vmParts and type(mg) == "string" and mg ~= "") then return end
		-- 🎟 UN ÉTAT PÉRIMÉ NE REJOUE PLUS RIEN. L'état porte le jeton de la
		-- piste qui l'a posé : si cette piste est terminée ou coupée, le
		-- viewmodel reconstruit ne doit surtout pas re-décrocher le chargeur —
		-- c'est comme ça qu'il finissait accroché en l'air, tout seul.
		if st.tok and st.tok ~= (Extra.magTok or 0) then Extra.magState = nil; return end
		if st.a == "hand" or st.a == "new" then
			local vp, gv = FX2.HandPart(viewmodel, st.right)
			if vp then FX2.PartAttach(Extra.vmParts, mg, vp, gv * (st.user or CFrame.new())) end
		elseif st.a == "throw" or st.a == "fall" then
			FX2.PartHide(Extra.vmParts, mg, true)
		elseif st.a == "detach" then
			FX2.PartDetach(Extra.vmParts, mg, false)
		end
	end
	Extra.magEvent = function(mg, e)
		local a = e.a or "detach"
		local g = function(k, dv)
			local v = e.s and e.s[k]
			return (type(v) == "number") and v or dv
		end
		if a == "back" then
			Extra.magState = nil
			Extra.partsDo(function(idx) FX2.PartRestore(idx, mg) end); return
		end
		if a == "detach" then
			local fall = g("fall", 0) >= 0.5
			Extra.magState = { a = fall and "fall" or "detach", tok = Extra.magTok or 0 }
			if fall then
				Extra.partsDrop(mg, function(idx) FX2.PartDetach(idx, mg, true) end)
			else
				Extra.partsDo(function(idx) FX2.PartDetach(idx, mg, false) end)
			end
			return
		end
		if a == "hand" or a == "new" then
			-- 🐞 IL DISPARAISSAIT : soudé au CENTRE du bras, il finissait caché
			-- DANS le membre — et sur un perso R15, « Left Arm » n'existe pas,
			-- donc l'événement ne faisait rien. FX2.HandPart trouve la main quel
			-- que soit le squelette et rend le décalage qui la pose DANS la main.
			local right = g("h", 0) >= 0.5
			local user = CFrame.new(g("x",0), g("y",0), g("z",0))
				* CFrame.Angles(math.rad(g("rx",0)), math.rad(g("ry",0)), math.rad(g("rz",0)))
			Extra.magState = { a = a, right = right, user = user, tok = Extra.magTok or 0 }
			-- 🔑 la main RÉELLE en 3e personne, celle du VIEWMODEL en 1re : la
			-- pièce doit suivre le bras que le joueur voit, sinon elle flotte.
			if Extra.parts then
				local rp, gr = FX2.HandPart(MyCharacter, right)
				if a == "new" then FX2.PartRestore(Extra.parts, mg) end
				if rp then FX2.PartAttach(Extra.parts, mg, rp, gr * user) end
			end
			if Extra.vmParts and viewmodel then
				local vp, gv = FX2.HandPart(viewmodel, right)
				if a == "new" then FX2.PartRestore(Extra.vmParts, mg) end
				if vp then FX2.PartAttach(Extra.vmParts, mg, vp, gv * user) end
			end
			return
		end
		if a == "throw" then
			-- 🎯 l'élan MESURÉ de la pièce (le bras qui lance), pas seulement
			-- la vitesse du personnage. C'est ce qui rend le lancer crédible.
			local var = g("var", 1)
			local mul = g("carry", 1)
			Extra.magState = { a = "throw", tok = Extra.magTok or 0 }
			Extra.partsDrop(mg, function(idx)
				local en = idx[mg]; if not en or en.dropped then return end
				local carry = FX2.PartVel(idx, mg)
				if carry.Magnitude < 0.05 then
					local root = MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
					carry = root and root.AssemblyLinearVelocity or Vector3.zero
				end
				carry = carry * mul
				local cf = FX2.PartWorld(idx, mg)
				FX2.PartDrop(idx, mg,
					carry
						+ cf.RightVector * (g("vx",0) + (math.random()-0.5)*var)
						+ cf.UpVector    * (g("vy",-2) + (math.random()-0.5)*var)
						+ cf.LookVector  * (g("vz",0) + (math.random()-0.5)*var),
					{ life = g("life", 8), spin = g("spin", 8) })
			end)
			return
		end
	end
	Extra.startCross = function()
		if Extra.crossBound then return end
		Extra.crossBound = Extra.vmName .. "_cross"
		RunService:BindToRenderStep(Extra.crossBound,
			Enum.RenderPriority.Camera.Value + 3, function()
				local g = MobileCursorGui
				local ct = g and g:FindFirstChild("Crosshair")
				if not ct then return end
				-- 🆕 DOUBLE CURSEUR. D'autres scripts d'interface rallument le
				-- curseur système ; avec le viseur scripté par-dessus, on en voyait
				-- deux l'un sur l'autre. On impose donc l'extinction tant que le
				-- viseur scripté est actif — sauf pendant que l'Anim Studio est
				-- ouvert, où il faut évidemment pouvoir cliquer.
				-- 🔄 la boucle (option) et la jauge, une fois par image
				do
					local RH = cfg.ReloadHUD or {}
					local rl = C.rl
					local ring = ct:FindFirstChild("ReloadRing")
					if ring then
						if rl and RH.Loop == true then
							FX2.RingSet(ring, true, (os.clock() - rl.t0) / rl.dur,
								rl.segs, os.clock())
						elseif ring.Visible and (os.clock() - (C.rlDone or 0)) > 0.2 then
							ring.Visible = false
						end
					end
					local g = ct:FindFirstChild("AmmoGauge")
					if g then
						-- Ce qu'on AFFICHE :
						--   • au repos et cartouche par cartouche → les munitions
						--     réelles (elles montent d'une à chaque cartouche : la
						--     jauge se remplit toute seule, une case à la fois) ;
						--   • pendant un rechargement au chargeur → l'avancement du
						--     geste, sinon la barre resterait vide puis sauterait à
						--     plein d'un coup à la dernière image.
						local clip = math.max(1, cfg.ClipSize)
						local frac, cnt = AmmoInClip / clip, AmmoInClip
						if rl and not rl.segs then
							local a = math.clamp((os.clock() - rl.t0) / rl.dur, 0, 1)
							local from = (rl.from or AmmoInClip) / clip
							frac = from + (1 - from) * a
							cnt = nil
						end
						FX2.GaugeSet(g, frac, cnt, 1/60)
					end
				end
				local editing = workspace:GetAttribute("AnimEditorFreeze") == true
				local scripted = not IsMobile   -- 🎯 notre image remplace toujours le curseur système
				if scripted and not editing then
					if UserInputService.MouseIconEnabled then
						UserInputService.MouseIconEnabled = false
					end
				end
				if g.Enabled == false and not editing then g.Enabled = true end
				local CH = cfg.Crosshair
				if CH and CH.HideInScope and cfg.ADS.Scope then
					ct.Visible = not (Aiming or ScopeAlpha > 0.02)
				end
				-- 🐞 LE SUIVI NE DÉPENDAIT QUE DU VISEUR SCRIPTÉ.
				-- Bloom coupé → on centrait le conteneur… et la jauge de munitions,
				-- qui vit dedans, restait au milieu de l'écran pendant que ton
				-- curseur image était ailleurs. Le suivi est maintenant décidé par
				-- la VUE, pas par le viseur : en 1re personne ça suit la souris,
				-- que le viseur soit dessiné ou non.
				-- Même position dans les DEUX boucles : aucune alternance Scale/Offset.
				local pos = CursorPosLocal()
				ct.Position = UDim2.fromOffset(pos.X, pos.Y)
			end)
	end
	Extra.stopCross = function()
		if Extra.crossBound then
			RunService:UnbindFromRenderStep(Extra.crossBound)
			Extra.crossBound = nil
		end
	end
	Extra.SetCrosshair = function(px, dt)
		if not MobileCursorGui then return end
		-- 🆕 ON TEND VERS la valeur voulue au lieu de s'y téléporter.
		-- Deux vitesses : l'ouverture est nerveuse (on doit voir le tir partir),
		-- la fermeture est posée (on doit sentir la précision revenir).
		local CH = cfg.Crosshair or {}
		local now = os.clock()
		if not dt then dt = math.clamp(now - (Extra.crossT or now), 0, 0.12) end
		Extra.crossT = now
		local cur = Extra.crossPx
		if cur < 0 then cur = px; Extra.crossDrawn = nil end   -- reset : pas d'animation
		local sp = (px > cur) and (CH.OpenSpeed or 26) or (CH.CloseSpeed or 9)
		local v = cur + (px - cur) * math.clamp(dt * sp, 0, 1)
		if math.abs(v - px) < 0.15 then v = px end
		-- l'état avance TOUJOURS (sinon la fin de la course se figerait) ;
		-- seule l'écriture des quatre Frames est évitée quand rien ne bouge
		-- d'un demi-pixel à l'écran.
		Extra.crossPx = v
		local drawn = math.floor(v * 2 + 0.5) / 2
		if Extra.crossDrawn and math.abs(drawn - Extra.crossDrawn) < 0.4 then return end
		Extra.crossDrawn = drawn
		px = drawn
		local c = MobileCursorGui:FindFirstChild("Crosshair"); if not c then return end
		for _, nm in ipairs({ "Top", "Bottom", "Left", "Right" }) do
			local f = c:FindFirstChild(nm)
			if f then
				local bx = f:GetAttribute("BX") or 0
				local by = f:GetAttribute("BY") or 0
				local ox = (bx > 0 and px) or (bx < 0 and -px) or 0
				local oy = (by > 0 and px) or (by < 0 and -px) or 0
				f.Position = UDim2.new(0.5, bx + ox, 0.5, by + oy)
			end
		end
	end
	-- [Combat K0] vue du tueur : ce que TU vois (viseur, lunette, munitions) — lu par DeathCam seulement
	-- quand un joueur que tu as tué regarde ta vue
	if CI.KVBind then
		CI.KVBind(tool, cfg, IsMobile, function()
			local gui = MobileCursorGui
			local ct = gui and gui:FindFirstChild("Crosshair")
			local top = ct and ct:FindFirstChild("Top")
			local vp = camera.ViewportSize
			local pos = ct and CursorPosLocal() or vp / 2
			local rl = C.rl
			return {
				on = gui ~= nil and gui.Enabled and ct ~= nil and ct.Visible,
				lines = top ~= nil and top.Visible,
				px = math.max(0, Extra.crossPx or 0),
				x = pos.X / math.max(vp.X, 1), y = pos.Y / math.max(vp.Y, 1),
				col = top and top.BackgroundColor3 or nil,
				scope = ScopeAlpha or 0,
				ammo = AmmoInClip,
				rl = rl and math.clamp((os.clock() - rl.t0) / rl.dur, 0, 1) or nil,
				segs = rl and rl.segs or nil,
				rlFrom = rl and rl.from or nil,
			}
		end)
	end
	-- V8 : référence UNIQUE de troisième personne, évaluée à chaque Heartbeat.
	-- Aucun regard caméra, root de viewmodel, scale FPS ou recul inventé.
	Extra.thirdGrip = function(state, r, l, off, follow, base, c1)
		local rightWant=base*off
		if follow<=0.001 then state.grab=nil; return rightWant end
		-- La prise est mémorisée dans le repère du JOINT, pas celui du Handle.
		-- C1 n'est appliqué qu'une fois, lors de la résolution du Handle.
		if not state.grab then state.grab=l:Inverse()*r*base end
		local leftWant=r:Inverse()*l*state.grab*off
		return rightWant:Lerp(leftWant,follow)
	end
	Extra.thirdUpdate = function(sway, sprint, ml, mr, aim)
		if not Extra.thirdEnabled or workspace:GetAttribute("WeaponAnimationSharing")==false then Extra.third=nil; return end
		if workspace:GetAttribute("AnimEditorFreeze") then return end
		local torso=MyCharacter and MyCharacter:FindFirstChild("Torso")
		local ra=MyCharacter and MyCharacter:FindFirstChild("Right Arm")
		local grip=ra and ra:FindFirstChild("RightGrip")
		if not (torso and grip and RightArmWeld and LeftArmWeld and RightArmBaseC1 and LeftArmBaseC1) then return end
		local s=Extra.third
		if not s or s.grip~=grip then
			s={grip=grip,base=(Extra.gripWeld==grip and Extra.gripBase) or grip.C0,filtered={}}
			Extra.third=s
		end
		if s.track~=Extra.gunTrack or s.trackStart~=Extra.gunT0 then
			s.grab=nil; s.filtered={}; s.track=Extra.gunTrack; s.trackStart=Extra.gunT0
		end
		s.torso=torso; s.sway=sway; s.sprint=sprint; s.ml=ml; s.mr=mr; s.aim=aim
		s.r=RightArmWeld.C0*RightArmWeld.C1:Inverse()
		s.l=LeftArmWeld.C0*LeftArmWeld.C1:Inverse()
		s.off,s.follow=Extra.gunNow(); s.off=s.off or CFrame.identity; s.follow=math.clamp(s.follow or 0,0,1)
		s.c0=Extra.thirdGrip(s,s.r,s.l,s.off,s.follow,s.base,grip.C1)
		s.handle=s.r*s.c0*grip.C1:Inverse()
	end
	Extra.shareCapture = function(on)
		if tool.Parent~=MyCharacter or not MyHumanoid or MyHumanoid.Health<=0
			or workspace:GetAttribute("AnimEditorFreeze") then return nil end
		local s=Extra.third
		if not s or not s.grip.Parent or not s.torso.Parent then return nil end
		local id=CFrame.identity
		local category=Extra.shareEquipCock and "Cock" or Extra.cocking and "Cock"
			or Pumping and "Pump" or Reloading and "Reload" or Extra.inspecting and "Inspect"
			or Equipping and "Equip" or Extra.shareLastCategory
		if not (Reloading or Pumping or Extra.cocking or Extra.inspecting or Equipping)
			and ReloadOffsetR==id and ReloadOffsetL==id then category=nil end
		Extra.shareLastCategory=category
		local gesture=(not category or on[category]) and (not Reloading or on.Reload)
		local equipOn=Extra.shareEquipCock and on.Cock or (not Extra.shareEquipCock and on.Equip)
		local r,l,handle=s.r,s.l,s.handle
		-- Tous les gestes actifs : copie des VRAIS welds, aucune recomposition.
		-- Recomposition uniquement pour soustraire une animation désactivée.
		if not (gesture and equipOn and on.Movement and on.Recoil and on.Sprint) then
			local function arm(base,weld,side,pose)
				local reload=(side=="R") and ReloadOffsetR or ReloadOffsetL
				local equip=(side=="R") and EquipOffsetR or EquipOffsetL
				local c1=base*s.aim*(on.Movement and s.sway or id)
					*(gesture and reload or id)*(equipOn and equip or id)*Extra.gkArm(side, weld, not equipOn)*(on.Recoil and RecoilOffset or id)   -- [GunKit P16f] [GunKit P18e]
					*(on.Movement and Extra.mvOf(weld.Part0,side) or id)
				if on.Sprint and s.sprint>0.001 then c1=c1:Lerp(pose,s.sprint) end
				return weld.C0*c1:Inverse()
			end
			r=arm(RightArmBaseC1,RightArmWeld,"R",s.mr)
			l=arm(LeftArmBaseC1,LeftArmWeld,"L",s.ml)
			local c0
			if gesture then
				-- La prise originale reste la référence même avec un filtre réseau.
				s.filtered.grab=s.grab
				c0=Extra.thirdGrip(s.filtered,r,l,s.off,s.follow,s.base,s.grip.C1)
			else c0=s.base end
			handle=r*c0*s.grip.C1:Inverse()
		end
		-- V8 : bras, Handle ET pièces dans le MÊME repère du Torso.
		-- Interpoler un Handle relatif à un bras lui-même en rotation créait des arcs parasites.
		local out={r=r,l=l,g=handle,parts={},catalog={}}
		local names={}
		for name in pairs(Extra.parts or {}) do table.insert(names,name) end
		if tool:GetAttribute("GunKitNetParts") then table.clear(names) end   -- [GunKit P19d]
		table.sort(names)
		local mag=Extra.magName
		if mag then local at=table.find(names,mag); if at then table.remove(names,at); table.insert(names,1,mag) end end
		if cfg.Rocket.Enabled then
			local model=tool:FindFirstChild(cfg.Rocket.MissileModelName)
			model=model and model:FindFirstChild(cfg.Rocket.MissileName)
			local primary=model and model:IsA("Model") and model.PrimaryPart
			if primary and Extra.shareConfig.Network.MaxAnimatedParts>0 then
				if Extra.shareRocketSource~=primary then
					Extra.shareRocketSource=primary; Extra.shareRocketHome=Handle.CFrame:ToObjectSpace(primary.CFrame)
				end
				local cf=handle*Extra.shareRocketHome; local hidden=false
				if on.RocketReload and on.Reload then
					hidden=AmmoInClip<=0
					local prop=Extra.shareRocketProp
					local w=prop and prop.Parent and prop.PrimaryPart and prop.PrimaryPart:FindFirstChild("ReloadRocketWeld")
					if Reloading and w then cf=l*w.C0*w.C1:Inverse(); hidden=false end
				end
				out.catalog[1]={part=primary,mag=false,group=model}; out.parts[1]={cf=cf,hidden=hidden}
			end
		end
		for _,name in ipairs(names) do
			local e=Extra.parts[name] -- exclusivement les pièces du Tool RÉEL
			if #out.parts>=math.clamp(Extra.shareConfig.Network.MaxAnimatedParts,0,12) then break end
			if not e.part or not e.part:IsDescendantOf(tool) or e.part==Extra.shareRocketSource then continue end
			local isMag=name==mag
			local allowed=gesture and ((isMag and on.Magazine) or (not isMag and on.Parts))
			local cf=handle*e.c0; local hidden=false
			if allowed and e.weld and e.weld.Part0 then
				local w=e.weld; local parent=w.Part0; local home=handle
				if parent==LeftArmWeld.Part1 then home=l
				elseif parent==RightArmWeld.Part1 then home=r
				elseif parent~=Handle then home=s.torso.CFrame:ToObjectSpace(parent.CFrame) end
				cf=home*w.C0*w.C1:Inverse()
				hidden=e.dropped==true or e.hid~=nil
			end
			-- 🩹 hors de la boîte du codec (±12 studs du Torso) → sinon TOUT le paquet est rejeté
			if cf.Position.Magnitude>11 then cf=handle*e.c0; hidden=true end
			out.catalog[#out.catalog+1]={part=e.part,mag=isMag}
			out.parts[#out.parts+1]={cf=cf,hidden=hidden}
		end
		return out
	end
	Extra.shareConfig=require(ReplicatedStorage.WeaponSystem:WaitForChild("WeaponAnimationSharingConfig"))
	Extra.thirdEnabled=false
	if Extra.shareConfig.Enabled then
		for _,enabled in pairs(Extra.shareConfig.Animations) do if enabled then Extra.thirdEnabled=true; break end end
	end
	Extra.share=require(ReplicatedStorage.WeaponSystem:WaitForChild("WeaponAnimationPublisher")).New(tool,Extra.shareCapture)

	local function CacheArmWelds()
		LeftArmWeld, RightArmWeld = nil, nil
		if not MyCharacter then return end
		local torso = MyCharacter:FindFirstChild("Torso"); if not torso then return end
		RightArmWeld = torso:WaitForChild("RightArmWeld", 2)
		LeftArmWeld  = torso:WaitForChild("LeftArmWeld", 2)
		-- base PROPRE depuis l'attribut publié par le weld ; sinon 1re lecture du C1
		RightArmBaseC1 = tool:GetAttribute("WeldRightBaseC1") or (RightArmWeld and RightArmWeld.C1)
		LeftArmBaseC1  = tool:GetAttribute("WeldLeftBaseC1")  or (LeftArmWeld  and LeftArmWeld.C1)
	end
	-- [GunKit P16] bras de la sortie d'arme du GunKit : un décalage par bras, calculé d'après l'heure (aucun état),
	-- multiplié UNE fois dans tes formules de bras (vrais bras, viewmodel, partage) -> jamais appliqué deux fois.
	Extra.gkArm = function(side, weld, noEquip)   -- [GunKit P18]
		local A = Extra.gkAdapter
		if A == nil then
			A = false
			pcall(function()
				local G = game:GetService("ReplicatedStorage"):FindFirstChild("GunKit")
				G = G and G:FindFirstChild("Guns")
				G = G and G:FindFirstChild(tool:GetAttribute("Gun") or tool.Name)
				local ms = G and G:FindFirstChild("WeaponControllerAdapter")
				if ms then A = require(ms) end
			end)
			Extra.gkAdapter = A
		end
		if A and A.EquipArm then return A.EquipArm(tool, side, weld, noEquip) end   -- [GunKit P18b]
		return CFrame.identity
	end
	-- [GunKit P17] pose de sprint de ton système, bras droit tourné sur son axe (degrés, attribut GunKitSprintRoll
	-- posé par l'arme) : avec la prise de l'arme, le canon reste à l'endroit et du bon côté
	Extra.gkSprint = function(pose)
		local r = tool:GetAttribute("GunKitSprintRoll")
		if typeof(pose) ~= "CFrame" or type(r) ~= "number" or r == 0 then return pose end
		return CFrame.Angles(0, math.rad(r), 0) * pose
	end
	-- [GunKit P19] armes GunKit : chaque piste de pièces jouée ici est annoncée au GunKit (clip + durée), qui la fait
	-- rejouer à l'identique chez les autres joueurs (pièces, speedloader, chambres, flash) ; ton partage garde les bras
	Extra.gkSync = function(kind, keys, dur)
		if not tool:GetAttribute("GunKitNetParts") then return end
		if Extra.gkAdapter == nil and Extra.gkArm then Extra.gkArm("R") end
		local A = Extra.gkAdapter
		if A and A.SyncPartTrack then pcall(A.SyncPartTrack, tool, kind, keys, dur) end
	end
	-- tireur qui porte une arme GunKit partagée : son flash est joué par le GunKit chez toi (pas le flash par défaut)
	Extra.gkNetShooter = function(plr)
		local ch = typeof(plr) == "Instance" and plr:IsA("Player") and plr.Character
		local t = ch and ch:FindFirstChildOfClass("Tool")
		return t ~= nil and t:GetAttribute("GunKitNetParts") == true
	end
	-- [Combat C6] 🧱 ARME CONTRE UN MUR : un rayon caméra → bout du canon ; si un mur est plus proche
	-- que le canon, l'arme se relève et recule (et le tir est bloqué). Réglages : CombatSettings.WallPose
	Extra.wallA = 0
	Extra.wallParams = RaycastParams.new()
	Extra.wallParams.FilterType = Enum.RaycastFilterType.Exclude
	Extra.wallParams.RespectCanCollide = true
	Extra.wallPose = function(cf)
		local W = CS.WallPose
		local now = os.clock()
		local dt = math.clamp(now - (Extra.wallClock or now), 0, 0.1)
		Extra.wallClock = now
		if CS.Enabled == false or not W or W.Enabled == false or not viewmodel or not vmFlash or not vmRoot then
			Extra.wallA, Extra.wallBlocked = 0, false
			return cf
		end
		-- position du canon par rapport à la racine du viewmodel (mesurée quand l'arme n'est pas relevée)
		if Extra.wallA < 0.02 or not Extra.wallRel or Extra.wallRelVM ~= viewmodel then
			Extra.wallRel = vmRoot.CFrame:ToObjectSpace(vmFlash.CFrame)
			Extra.wallRelVM = viewmodel
		end
		local camCF = camera.CFrame
		local tip = (cf * Extra.wallRel).Position
		local len = -camCF:PointToObjectSpace(tip).Z + (W.Margin or 0.35)
		local target = 0
		if len > 0.3 then
			Extra.wallParams.FilterDescendantsInstances = { MyCharacter, viewmodel, camera }
			local res = workspace:Raycast(camCF.Position, camCF.LookVector * len, Extra.wallParams)
			if res and res.Instance and res.Instance.CanCollide and res.Instance.Transparency < 0.9 then
				local m = res.Instance:FindFirstAncestorOfClass("Model")
				local isChar = m and m:FindFirstChildOfClass("Humanoid") ~= nil
				local inTool = res.Instance:FindFirstAncestorOfClass("Tool") or res.Instance:FindFirstAncestorOfClass("Accessory")
				if not isChar and not inTool then
					target = math.clamp((len - res.Distance) / (len * 0.55), 0, 1)
				end
			end
		end
		Extra.wallA += (target - Extra.wallA) * math.clamp(dt * (W.Speed or 14), 0, 1)
		Extra.wallBlocked = (W.BlockFire ~= false) and Extra.wallA > 0.45
		if Extra.wallA < 0.002 then return cf end
		local a = Extra.wallA
		local e = a * a * (3 - 2 * a)
		local rot = camCF.Rotation
		local off = rot * CFrame.new(0, -(W.Down or 0.08) * e, (W.Back or 0.3) * e)
			* CFrame.Angles(math.rad((W.Raise or 38) * e), 0, math.rad((W.Roll or 8) * e)) * rot:Inverse()
		return CFrame.new(cf.Position) * off * (cf - cf.Position)
	end
	-- une AUTRE arme possède la caméra (nouvelle vie, changement d'arme) : on ne lui reprend rien
	Extra.otherOwnsCam = function()
		local o = WeaponSharedState.CameraOwner()
		return o ~= nil and o ~= camOwnerToken
	end
	Extra.wallStop = function()
		return Extra.wallBlocked == true and viewmodel ~= nil and viewmodel.Parent == camera
	end
	-- 🧱 [Murs] Le CANON est-il passé de l'autre côté d'un mur ? (3e personne)
	Extra.muzzleBlocked = function(muzzlePos)
		local root = MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		local body = root.Position + Vector3.new(0, 1.5, 0)
		local seg = muzzlePos - body
		if seg.Magnitude < 0.5 then return nil end
		return RayCast(body, seg.Unit, seg.Magnitude)
	end
	--  impact (trou, étincelles) sur le MUR réellement touché, pas derrière
	Extra.wallRay = function(muzzlePos, rp)
		local root = MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		local body = root.Position + Vector3.new(0, 1.5, 0)
		local seg = muzzlePos - body
		if seg.Magnitude < 0.5 then return nil end
		return workspace:Raycast(body, seg.Unit * (seg.Magnitude + 0.5), rp)
	end
	-- 🧱 [Murs] face du mur traversé CÔTÉ CANON : rayon qui revient vers le joueur depuis
	--    un peu au-delà du canon, et qui ne peut toucher QUE ce mur-là
	Extra.wallFarParams = RaycastParams.new()
	Extra.wallFarParams.FilterType = Enum.RaycastFilterType.Include
	Extra.wallFar = function(wall, muzzlePos, nearPos)
		if partIsCharacter(wall) then return nil end
		local root = MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		local u = muzzlePos - (root.Position + Vector3.new(0, 1.5, 0))
		if u.Magnitude < 0.5 then return nil end
		u = u.Unit
		Extra.wallFarParams.FilterDescendantsInstances = { wall }
		local from = muzzlePos + u * 3
		local back = 3 + (nearPos and (muzzlePos - nearPos).Magnitude or 0) + 0.1
		return workspace:Raycast(from, -u * back, Extra.wallFarParams)
	end
	-- 🧱 [Murs] 3e PERSONNE : l'arme se relève contre un mur (que des rayons, aucun CanCollide).
	--    ⚡ Rayon 20×/s (10×/s en mode performance), lissage à chaque image,
	--    paramètres de rayon préparés une seule fois par personnage.
	Extra.wall3A, Extra.wall3T, Extra.wall3Next = 0, 0, 0
	Extra.wall3Params = RaycastParams.new()
	Extra.wall3Params.FilterType = Enum.RaycastFilterType.Exclude
	Extra.wall3Params.RespectCanCollide = true
	Extra.wallThird = function(dt)
		local W = CS.WallPose
		if CS.Enabled == false or not W or W.Enabled == false or W.Third == false or not MyCharacter
			or tool.Parent ~= MyCharacter or not Flash or not Flash.Parent
			or (viewmodel and viewmodel.Parent == camera) then
			Extra.wall3A, Extra.wall3T, Extra.wall3Rel = 0, 0, nil
			return 0
		end
		local root = MyCharacter:FindFirstChild("HumanoidRootPart")
		if not root then return 0 end
		local now = os.clock()
		if now >= Extra.wall3Next then
			-- 20 Hz (10 Hz en mode performance) : largement assez pour un mur
			Extra.wall3Next = now + ((Extra.perfOn and 0.1) or 0.05)
			if Extra.wall3Char ~= MyCharacter then   -- filtre préparé une fois par personnage
				Extra.wall3Char = MyCharacter
				Extra.wall3Params.FilterDescendantsInstances = { MyCharacter, camera }
			end
			local chest = root.Position + Vector3.new(0, 1.5, 0)
			if Extra.wall3A < 0.02 or not Extra.wall3Rel then   -- direction de l'arme, bras baissés
				local v = Flash.Position - chest
				if v.Magnitude > 0.5 and v.Magnitude < 10 then Extra.wall3Rel = root.CFrame:VectorToObjectSpace(v) end
			end
			local target = 0
			if Extra.wall3Rel then
				local v = root.CFrame:VectorToWorldSpace(Extra.wall3Rel)
				local len = v.Magnitude + (W.Margin or 0.35)
				local res = workspace:Raycast(chest, v.Unit * len, Extra.wall3Params)
				local inst = res and res.Instance
				if inst and inst.Transparency < 0.9
					and not inst:FindFirstAncestorOfClass("Tool") and not inst:FindFirstAncestorOfClass("Accessory") then
					local m = inst:FindFirstAncestorOfClass("Model")
					if not (m and m:FindFirstChildOfClass("Humanoid")) then
						target = math.clamp((len - res.Distance) / (len * 0.55), 0, 1)
					end
				end
			end
			Extra.wall3T = target
		end
		-- lissage à chaque image (fluide même avec un rayon 20×/s)
		local a = Extra.wall3A
		if a == 0 and Extra.wall3T == 0 then return 0 end   -- rien à faire : bras au repos, pas de mur
		a += (Extra.wall3T - a) * math.clamp((dt or 0.016) * (W.Speed or 14), 0, 1)
		if a < 0.002 then a = 0 end
		Extra.wall3A = a
		return a
	end
	-- 👻 [Murs] bras + arme TRAVERSENT les murs (local : ton perso est simulé chez toi)
	Extra.ghostSaved = {}
	Extra.ghostPart = function(d)
		if d:IsA("BasePart") and d.CanCollide then
			Extra.ghostSaved[d] = true
			d.CanCollide = false
		end
	end
	Extra.ghostOn = function()
		for _, d in ipairs(tool:GetDescendants()) do Extra.ghostPart(d) end
	end
	Extra.ghostOff = function()
		for d in pairs(Extra.ghostSaved) do
			if d.Parent then d.CanCollide = true end
		end
		Extra.ghostSaved = {}
	end
	Extra.ghostArms = function()
		if not MyCharacter then return end
		local r, l = MyCharacter:FindFirstChild("Right Arm"), MyCharacter:FindFirstChild("Left Arm")
		if r and r.CanCollide then r.CanCollide = false end
		if l and l.CanCollide then l.CanCollide = false end
	end
	-- lève UN bras autour de son épaule, sans créer de table
	Extra.wallArm = function(wl, rw)
		if wl and wl.Part0 then
			local jr = (wl.Part0.CFrame * wl.C0).Rotation
			wl.C1 = wl.C1 * (jr:Inverse() * rw * jr):Inverse()
		end
	end
	local function AddRecoilKick()
		if Aiming and Extra.freezeAim() then return end
		-- 🆕 au doigt on ne compense pas : tout le recul est mis à l'échelle
		local rs = IsMobile and (cfg.Feel.MobileRecoilScale or 1) or 1
		-- [GunKit P10] animation de tir de l'arme : on enregistre le coup, la boucle Feel joue la courbe
		if type(cfg.FireAnim) == "table" and cfg.FireAnim.Keys and tool:GetAttribute("GunKitFireAnim") ~= false then
			Extra.gkShots = Extra.gkShots or {}
			local v = cfg.FireAnim.Variation or 0.35
			table.insert(Extra.gkShots, { t0 = os.clock(), k = rs * (1 + (math.random() - 0.5) * v * 0.5),
				side = (math.random() < 0.5 and -1 or 1) * (1 - v + math.random() * v * 2) })
			CamRecoilPitch += math.rad(cfg.Feel.CamUp * rs)
			CamRecoilYaw   += math.rad((math.random() - 0.5) * 2 * cfg.Feel.CamSide * rs)
			return
		end
		RecoilOffset = RecoilOffset
			* CFrame.new(0, 0, -cfg.Feel.RecoilKickBack * rs)
			* CFrame.Angles(math.rad(-cfg.Feel.RecoilKickUp * rs), 0, 0)
		CamRecoilPitch += math.rad(cfg.Feel.CamUp * rs)
		CamRecoilYaw   += math.rad((math.random() - 0.5) * 2 * cfg.Feel.CamSide * rs)
	end
	local function StartFeelLoop()
		if FeelConnection then return end
		local SW = cfg.Feel.Sway
		FeelConnection = RunService.Heartbeat:Connect(function(dt)
			Extra.pivotSettings = AimPivotSettings.Read(tool)
			Extra.updateAim()
			-- self-heal des welds (on récupère la référence du weld, PAS la base)
			if MyCharacter then
				local torso = MyCharacter:FindFirstChild("Torso")
				if torso then
					if not RightArmWeld or RightArmWeld.Parent ~= torso then
						RightArmWeld = torso:FindFirstChild("RightArmWeld")
					end
					if not LeftArmWeld or LeftArmWeld.Parent ~= torso then
						LeftArmWeld = torso:FindFirstChild("LeftArmWeld")
					end
				end
			end
			-- base PROPRE : toujours l'attribut publié par le weld (jamais le C1 vivant,
			-- que cette boucle réécrit). Fallback : 1re lecture seulement si pas encore de base.
			local arAttr = tool:GetAttribute("WeldRightBaseC1")
			local alAttr = tool:GetAttribute("WeldLeftBaseC1")
			if arAttr then RightArmBaseC1 = arAttr elseif not RightArmBaseC1 and RightArmWeld then RightArmBaseC1 = RightArmWeld.C1 end
			if alAttr then LeftArmBaseC1  = alAttr elseif not LeftArmBaseC1  and LeftArmWeld  then LeftArmBaseC1  = LeftArmWeld.C1  end
			-- override base via tuner C1 (optionnel)
			local tr = tool:GetAttribute("TuneRightC1"); if tr then RightArmBaseC1 = tr end
			local tl = tool:GetAttribute("TuneLeftC1");  if tl then LeftArmBaseC1  = tl  end
			local a = math.clamp(dt * cfg.Feel.RecoilRecover, 0, 1)
			RecoilOffset   = RecoilOffset:Lerp(CFrame.new(), a)
			-- [GunKit P10b] courbe de tir de l'arme : somme des coups en cours, saturée en douceur
			if Extra.gkShots and #Extra.gkShots > 0 then
				local FA = cfg.FireAnim
				if type(FA) ~= "table" or not FA.Keys then
					Extra.gkShots = {}
				else
					local now, ks = os.clock(), FA.Keys
					local n = #ks
					local P, A = Vector3.zero, Vector3.zero
					for i = #Extra.gkShots, 1, -1 do
						local s = Extra.gkShots[i]
						local u = (now - s.t0) / math.max(FA.Time, 1e-3)
						if u >= 1 then
							table.remove(Extra.gkShots, i)
						else
							local x = u * (n - 1) + 1
							local i0 = math.floor(x)
							local k0, k1 = ks[i0], ks[math.min(i0 + 1, n)]
							local fr = x - i0
							local p, r = k0.p:Lerp(k1.p, fr), k0.a:Lerp(k1.a, fr)
							P += p * s.k
							A += Vector3.new(r.X * s.k, r.Y * s.k * s.side, r.Z * s.k * s.side)
						end
					end
					local function sat(v, m)
						local L = v.Magnitude
						if not m or m <= 0 or L < 1e-7 then return v end
						return v.Unit * m * math.tanh(L / m)
					end
					P, A = sat(P, FA.SatPos), sat(A, FA.SatRot)
					local ang = A.Magnitude
					RecoilOffset = CFrame.new(P) * (ang > 1e-7 and CFrame.fromAxisAngle(A.Unit, ang) or CFrame.new())
				end
			end
			CamRecoilPitch = CamRecoilPitch * (1 - a)
			CamRecoilYaw   = CamRecoilYaw   * (1 - a)
			-- ADS lerp + zoom FOV (+ léger punch au tir)
			-- 🆕 TuneADSForce : l'Anim Studio tient l'arme en position de visée
			-- pendant que tu la règles. Sans cet attribut, comportement inchangé.
			local wantAim = Aiming or (not Extra.aimBusy() and tool:GetAttribute("TuneADSForce") == true)
			AimAlpha += ((wantAim and 1 or 0) - AimAlpha) * math.clamp(dt * cfg.ADS.LerpSpeed, 0, 1)
			if math.abs(AimAlpha - (wantAim and 1 or 0)) < 0.001 then AimAlpha = wantAim and 1 or 0 end
			if Extra.aimAttr ~= AimAlpha then Extra.aimAttr = AimAlpha; tool:SetAttribute("AimAlpha", AimAlpha) end
			if Extra.freezeAim() then
				table.clear(Extra.visualShots)
				local fade = 1 - AimAlpha
				AimRecoil = AimRecoil * fade
				CamRecoilPitch *= fade; CamRecoilYaw *= fade; FireFOVOffset *= fade
			end
			if cfg.ADS.Enabled then
				local scope = cfg.ADS.Scope
				local aimFOV = scope and cfg.ADS.ScopeFOV or (tool:GetAttribute("AdsFOV") or cfg.ADS.FOV)
				local fovSpeed = scope and cfg.ADS.ScopeSpeed or cfg.ADS.LerpSpeed
				local targetFOV = Aiming and aimFOV or cfg.ADS.HipFOV
				BaseFOV += (targetFOV - BaseFOV) * math.clamp(dt * fovSpeed, 0, 1)
			else
				BaseFOV += (cfg.ADS.HipFOV - BaseFOV) * math.clamp(dt * 10, 0, 1)
			end
			FireFOVOffset = FireFOVOffset * (1 - math.clamp(dt * 10, 0, 1))
			local zipFOV = MyPlayer and MyPlayer:GetAttribute("ZiplineFOVAdd") or 0
			-- 🩹 n'écrit le FOV que si CETTE arme est tenue par le perso actuel, vivant
			--    (sinon une arme « fantôme » d'une vie précédente se bat avec la nouvelle)
			local holder = tool.Parent
			local holderHum = holder and holder:FindFirstChildOfClass("Humanoid")
			if holder == Players.LocalPlayer.Character and holderHum and holderHum.Health > 0 then
				camera.FieldOfView = BaseFOV + FireFOVOffset + WeaponSharedState.GetMoveFOV() + (zipFOV or 0)
			end
			-- décroissance du recul de visée (retour vers l'avant)
			AimRecoil = AimRecoil:Lerp(Vector3.zero, math.clamp(dt * cfg.ADS.Recoil.Decay, 0, 1))
			-- lunette : entrée/sortie ultra-responsive (réaliste mais sans délai)
			if cfg.ADS.Scope then
				local target = Aiming and 1 or 0
				ScopeAlpha += (target - ScopeAlpha) * math.clamp(dt * cfg.ADS.ScopeSpeed, 0, 1)
				if math.abs(ScopeAlpha - target) < 0.01 then ScopeAlpha = target end
				if ScopeGui then
					ScopeGui.Enabled = (ScopeAlpha > 0.001)
					if ScopeCanvas then ScopeCanvas.GroupTransparency = 1 - ScopeAlpha end
					if ScopeScale then ScopeScale.Scale = 1 + (1 - ScopeAlpha) * 0.12 end  -- "pose à l'œil"
				end
			end
			-- les vrais bras (3e personne) ne reçoivent pas de pose ADS dédiée
			local aimCF = CFrame.new()
			-- sway de déplacement (réduit en visée)
			local target = CFrame.new()
			if MyHumanoid and MyCharacter then
				local hrp = MyCharacter:FindFirstChild("HumanoidRootPart") or MyCharacter:FindFirstChild("Torso")
				if hrp then
					local rel = hrp.CFrame:VectorToObjectSpace(MyHumanoid.MoveDirection)
					target = CFrame.new(-rel.X*SW.Pos, 0, -rel.Z*SW.Pos)
						* CFrame.Angles(-rel.Z*SW.Rot, -rel.X*SW.Rot, rel.X*SW.Rot)
				end
			end
			SwayOffset = SwayOffset:Lerp(target, math.clamp(dt * SW.Speed, 0, 1))
			-- ── MARCHE (low ready) : pose baissée + bob synchro pas + inertie ──
			local WK = cfg.Walk
			if WK.Enabled then
				local moving   = MyHumanoid and MyHumanoid.MoveDirection.Magnitude > 0.1
				local grounded = MyHumanoid and MyHumanoid.FloorMaterial ~= Enum.Material.Air
				local sprintA  = WeaponSharedState.GetSprintAlpha()
				-- actif seulement en marche au sol, coupé au sprint et en visée
				local want = (moving and grounded) and 1 or 0
				want = want * (1 - sprintA) * (1 - AimAlpha)
				-- coupe la marche si une AUTRE anim est en cours (reload, équipe, pompe, tir)
				local otherAnim = Reloading or Equipping or Pumping or IsShooting
					or Extra.cocking or Extra.inspecting
				if otherAnim then want = 0 end
				-- sortie RAPIDE quand on tire/reload/équipe → le gun revient vite au ready
				local blend = otherAnim and WK.ExitSpeed or WK.BlendSpeed
				Walk.alpha += (want - Walk.alpha) * math.clamp(dt * blend, 0, 1)
				-- phase des pas (sinus → boucle sans couture ; 1 cycle = 2 pas)
				-- 🆕 R4 : la cadence suit la VRAIE vitesse du perso (sprint, zones,
				-- boosts) → les pas de l'anim et ceux du personnage restent synchro.
				local wsp = (MyHumanoid and MyHumanoid.WalkSpeed) or (WK.SpeedRef or 16)
				local freqW = WK.Freq * math.clamp(wsp / (WK.SpeedRef or 16), 0.5, 2)
				Walk.phase += dt * freqW * 2 * math.pi
				local s1 = math.sin(Walk.phase)       -- gauche/droite
				local s2 = math.sin(Walk.phase * 2)   -- rebond par pied (double fréquence)
				-- INERTIE : accumule la rotation caméra image par image, puis rattrape
				local curCF = camera.CFrame
				if Walk.prevCF then
					local d = Walk.prevCF:ToObjectSpace(curCF)
					local rx, ry = d:ToEulerAnglesYXZ()
					Walk.velPitch += rx
					Walk.velYaw   += ry
				end
				Walk.prevCF = curCF
				local kc = math.clamp(dt * WK.InertiaCatch, 0, 1)
				Walk.velPitch *= (1 - kc)
				Walk.velYaw   *= (1 - kc)
				local lagP = math.clamp(-Walk.velPitch * WK.InertiaAmount, -WK.InertiaMax, WK.InertiaMax)
				local lagY = math.clamp(-Walk.velYaw   * WK.InertiaAmount, -WK.InertiaMax, WK.InertiaMax)
				-- offset complet dans le repère de l'arme
				local full = CFrame.new(
					WK.LowerX + s1 * WK.SwayX,
					WK.LowerY + s2 * WK.BobY,
					WK.LowerZ + s2 * WK.BobZ)
					* CFrame.Angles(
						-WK.LowerPitch + s2 * WK.PitchBob + lagP,   -- négatif = canon vers le BAS
						WK.LowerYaw + s1 * WK.Yaw + lagY,
						WK.LowerRoll + s1 * WK.Roll + lagY * WK.InertiaRoll)
				Walk.Root = CFrame.identity:Lerp(full, Walk.alpha)
			else
				Walk.Root = CFrame.new()
			end
			-- ── IDLE : respiration à l'arrêt (hors visée, au sol, sans sprint) ──
			local ID = cfg.Idle
			if ID and ID.Enabled then
				local movingI = MyHumanoid and MyHumanoid.MoveDirection.Magnitude > 0.1
				local airI    = MyHumanoid and MyHumanoid.FloorMaterial == Enum.Material.Air
				local wantI   = (not movingI and not airI) and 1 or 0
				wantI = wantI * (1 - AimAlpha) * (1 - WeaponSharedState.GetSprintAlpha())
				Extra.idleAlpha += (wantI - Extra.idleAlpha) * math.clamp(dt * (ID.Blend or 4), 0, 1)
				Extra.idlePhase += dt * (ID.Speed or 0.85) * 2 * math.pi
				local i1 = math.sin(Extra.idlePhase)
				local i2 = math.sin(Extra.idlePhase * 0.5)   -- déphasé → trajectoire en "8"
				local fullI = CFrame.new(
					i2 * (ID.BobX or 0),
					i1 * (ID.BobY or 0),
					i1 * 0.5 * (ID.BobZ or 0))
					* CFrame.Angles(
						i1 * (ID.RotPitch or 0),
						i2 * (ID.RotYaw or 0),
						i2 * (ID.RotRoll or 0))
				Extra.idleRoot = CFrame.identity:Lerp(fullI, Extra.idleAlpha)
			else
				Extra.idleRoot = CFrame.new()
			end
			-- ── DISPERSION DYNAMIQUE ──
			local DS = cfg.DynamicSpread
			local dynOn = bloomSwitch("bloom")
			Extra.dynOn = dynOn
			if dynOn then
				local pen = DS.Base or 0
				if MyHumanoid then
					if MyHumanoid.FloorMaterial == Enum.Material.Air then
						pen = DS.Airborne or pen
					elseif WeaponSharedState.IsSprinting() then
						pen = DS.Sprinting or pen
					elseif MyHumanoid.MoveDirection.Magnitude > 0.1 then
						pen = DS.Moving or pen
					end
				end
				-- 1re balle après une pause : parfaite (bloom effacé net)
				if os.clock() - Extra.lastShotAt > (DS.FirstShotDelay or 0.35) then
					Extra.bloom = 0
				else
					Extra.bloom = math.max(0, Extra.bloom - dt * (DS.Recover or 0.09))
				end
				local total = pen + Extra.bloom
				if AimAlpha > 0.001 then
					total = total * (1 - AimAlpha) + (DS.ADS or 0) * AimAlpha
				end
				if IsMobile then total = total * (DS.MobileScale or 1) end
				-- le cône PROPRE de l'arme (shotgun) reste le plancher
				local floorS = cfg.MinSpread or 0
				Spread = math.clamp(floorS + total, floorS,
					math.max(DS.Max or 0.06, cfg.MaxSpread or 0))
				if (DS.CrosshairPx or 0) > 0 then
					Extra.SetCrosshair((Spread - floorS) * DS.CrosshairPx, dt)
				end
			else
				-- 🆕 interrupteur coupé : précision EXACTE (le cône propre de
				-- l'arme reste, rien d'autre) et le viseur se referme au lieu de
				-- rester bloqué sur son dernier écartement.
				-- ⛔ INTERRUPTEUR COUPÉ = STRICTEMENT L'ANCIEN COMPORTEMENT.
				-- On ne TOUCHE PAS à Spread : c'est l'ancien système
				-- (AimInaccuracyStepAmount + UpdateCrosshair, au tir et à la
				-- récupération) qui le pilote, exactement comme avant. Le
				-- réécrire ici, c'était ça qui ne rendait pas « exactement le
				-- fonctionnement d'avant ».
				Extra.bloom = 0
				-- une seule remise à zéro, à la BASCULE, pour que le viseur ne
				-- reste pas ouvert sur son dernier écartement.
				if Extra.bloomWas ~= false then Extra.SetCrosshair(0, 1) end
			end
			Extra.bloomWas = dynOn
			Extra.slideTick()   -- 🔓 culasse ouverte à vide
			-- 🆕 l'interrupteur peut changer EN JEU : on rebâtit le curseur
			-- quand il bascule, sinon il faudrait rééquiper l'arme pour voir
			-- l'effet.
			do
				local cx = bloomSwitch("cross")
				if Extra.crossWas == nil then Extra.crossWas = cx
				elseif Extra.crossWas ~= cx then
					Extra.crossWas = cx
					if ApplyCurrentMode then ApplyCurrentMode(true) end
				end
			end
			-- ── MICRO-ANIMATIONS DE VISÉE (sinon l'arme est figée en ADS) ──
			local AM = cfg.AimMotion
			if AM.Enabled and not Extra.freezeAim() and AimAlpha > 0.001 then
				-- 🫁 la respiration ne tourne que si elle est demandée : sinon on
				-- garde les réactions (strafe, saut, tir) et l'arme reste posée.
				local bs, bs2 = 0, 0
				if AM.Breathing ~= false then
					Aim.phase += dt * AM.BreathSpeed * 2 * math.pi
					bs  = math.sin(Aim.phase)
					bs2 = math.sin(Aim.phase * 0.5)
				end
				-- strafe gauche/droite (composante latérale du déplacement)
				local strafeTarget = 0
				if MyHumanoid then
					local rel = camera.CFrame:VectorToObjectSpace(MyHumanoid.MoveDirection)
					strafeTarget = math.clamp(rel.X, -1, 1)
				end
				Aim.strafe += (strafeTarget - Aim.strafe) * math.clamp(dt * AM.StrafeSmooth, 0, 1)
				-- saut / chute (vitesse verticale lissée)
				local vy = 0
				if MyCharacter then
					local hrp = MyCharacter:FindFirstChild("HumanoidRootPart")
					if hrp then vy = hrp.AssemblyLinearVelocity.Y end
				end
				Aim.jumpV += (vy - Aim.jumpV) * math.clamp(dt * AM.JumpSmooth, 0, 1)
				local jumpOff = math.clamp(Aim.jumpV * AM.JumpPos, -AM.JumpMax, AM.JumpMax)
				-- tir (impulsion qui décroît → petite secousse rythmée en auto)
				Aim.fireImp = math.max(0, Aim.fireImp - dt / AM.FireDecay)
				local kick = Aim.fireImp
				-- 🆕 NoMoveTilt : plus AUCUNE inclinaison liée au déplacement en visée
				local tilt = Extra.noMoveTilt() and 0 or 1
				-- 🆕 le kick de tir est HORIZONTAL : yaw + décalage latéral, côté tiré au sort
				local side = Aim.fireSide or 1
				local full = CFrame.new(
					bs2 * AM.BreathPos + Aim.strafe * AM.StrafePos + kick * (AM.FireSide or 0) * side,
					bs  * AM.BreathPos - jumpOff,
					kick * AM.FirePos)
					* CFrame.Angles(
						bs * AM.BreathRot + kick * (AM.FireKick or 0),   -- FireKick = 0 → zéro vertical
						bs2 * AM.BreathRot * 0.5 + kick * (AM.FireYaw or 0) * side,
						-Aim.strafe * AM.StrafeRoll * tilt)              -- roulis de strafe coupé
				Aim.Motion = CFrame.identity:Lerp(full, AimAlpha)
			else
				Aim.Motion = CFrame.new()
			end
			-- ── JUMP / FALL / LAND : bob procédural des bras (saut réaliste) ──
			local JB = cfg.JumpBob
			if JB.Enabled and MyCharacter and MyHumanoid then
				local hrp = MyCharacter:FindFirstChild("HumanoidRootPart")
				if hrp then
					local vy = hrp.AssemblyLinearVelocity.Y
					local airborne = MyHumanoid.FloorMaterial == Enum.Material.Air
					jumpVelSmooth += (vy - jumpVelSmooth) * math.clamp(dt * JB.AirSmooth, 0, 1)
					-- atterrissage détecté → coup vers le bas (impulsion du ressort)
					if wasAirborneFeel and not airborne then
						-- une petite chute donne un petit coup : le plancher à 0.15
						-- donnait la même secousse en descendant une marche qu'en
						-- tombant d'un toit. Et la racine adoucit le haut de l'échelle.
						local impact = math.sqrt(math.clamp(-lastVY / 60, 0, 1))
						landSpringVel += impact * JB.LandImpulse
					end
					wasAirborneFeel = airborne
					lastVY = vy
					-- 🩹 RESSORT STABLE À TOUT FRAMERATE.
					-- Il était intégré en un seul pas d'Euler : à 25 fps (dt≈0.04)
					-- un ressort raide dépasse sa cible et repart dans l'autre sens
					-- — c'est ça, le « saccadé ». On borne le pas et on sous-divise :
					-- le mouvement devient identique à 30 comme à 144 fps.
					local sdt = math.min(dt, 0.05)
					local steps = math.max(1, math.ceil(sdt / 0.008))
					local h = sdt / steps
					for _ = 1, steps do
						landSpringVel += (-JB.LandStiffness * landSpring
							- JB.LandDamping * landSpringVel) * h
						landSpring    += landSpringVel * h
					end
					if math.abs(landSpring) < 1e-4 and math.abs(landSpringVel) < 1e-4 then
						landSpring, landSpringVel = 0, 0
					end
					-- en l'air : montée (vy>0) → bras BAS ; chute (vy<0) → bras HAUT.
					-- à l'apex (vy≈0) → retour à zéro. Tout est lissé → smooth.
					-- 🩹 LA CASSURE À L'ATTERRISSAGE.
					-- L'offset de vol passait de sa valeur à ZÉRO à l'image même du
					-- contact : un saut discontinu, en plein dans le moment le plus
					-- visible du mouvement. On le laisse maintenant se RÉSORBER, et
					-- le ressort d'impact prend le relais par-dessus.
					if airborne then
						Extra.airDrop = math.clamp(jumpVelSmooth * JB.AirFollow, -JB.AirMax, JB.AirMax)
					else
						jumpVelSmooth = jumpVelSmooth * (1 - math.clamp(dt * 10, 0, 1))
						Extra.airDrop = (Extra.airDrop or 0)
							* (1 - math.clamp(dt * (JB.LandBlend or 9), 0, 1))
						if math.abs(Extra.airDrop) < 1e-5 then Extra.airDrop = 0 end
					end
					local airDrop = Extra.airDrop or 0
					-- AimSway=false → arme stable en visée : le jump bob s'annule avec AimAlpha.
					-- AimSway=true  → on garde une part du mouvement (AimScale) en visée.
					local jumpAimMult = Extra.aimSway() and (1 - (1 - JB.AimScale) * AimAlpha) or (1 - AimAlpha)
					-- 🆕 MinScale : garde une part du mouvement même en visée.
					jumpAimMult = math.max(jumpAimMult, JB.MinScale or 0)
					if Extra.freezeAim() then jumpAimMult *= (1 - AimAlpha) end
					local totalY = (airDrop + landSpring) * jumpAimMult * (JB.Invert and -1 or 1)
					-- 🆕 STRAFE : la part latérale du déplacement, dans le repère
					-- de la CAMÉRA. Ça marchait déjà, mais seulement en visée
					-- (cfg.AimMotion) — maintenant c'est valable partout, y
					-- compris pendant un rechargement ou une inspection.
					local sTgt = 0
					local mvd = MyHumanoid.MoveDirection
					if mvd.Magnitude > 0.05 then
						sTgt = math.clamp(camera.CFrame.RightVector:Dot(mvd), -1, 1)
					end
					Extra.mvS = (Extra.mvS or 0) + (sTgt - (Extra.mvS or 0))
						* math.clamp(dt * (JB.StrafeSmooth or 9), 0, 1)
					-- 🆕 LE VECTEUR EST EN AXES DU MONDE, pas en axes du bras.
					-- C'est tout l'intérêt : Extra.mvOf() le convertira au tout
					-- dernier moment, après les animations.
					Extra.mvW = Vector3.new(0, totalY, 0)
						+ camera.CFrame.RightVector * (Extra.mvS * (JB.StrafePos or 0.05) * jumpAimMult)
					Extra.mvR = totalY * (JB.TiltR or 0.5)
					Extra.mvL = totalY * (JB.TiltL or 0.35)
					Extra.mvZ = Extra.mvS * (JB.StrafeRoll or 0.038) * jumpAimMult
					JumpOffsetR, JumpOffsetL = CFrame.new(), CFrame.new()
				end
			else
				JumpOffsetR, JumpOffsetL = CFrame.new(), CFrame.new()
				Extra.mvW = nil
			end
			-- sway en visée : AimSway=true → on garde des micro-mouvements (SwayReduce) ;
			-- AimSway=false → arme stable (sway annulé en visée)
			local swReduce = (not Extra.freezeAim() and Extra.aimSway()) and cfg.ADS.SwayReduce or 1
			local swayUse = CFrame.new():Lerp(SwayOffset, 1 - swReduce * AimAlpha)
			-- 🆕 en visée : on garde la translation du sway, on SUPPRIME sa rotation
			-- (c'est elle qui penchait l'arme quand on bougeait en visant)
			if Extra.noMoveTilt() and AimAlpha > 0.001 then
				local sp = swayUse.Position
				swayUse = CFrame.new(sp) * CFrame.identity:Lerp(swayUse - sp, 1 - AimAlpha)
			end
			local mAlpha = WeaponSharedState.GetSprintAlpha()
			-- 🆕 PRIORITÉ AUX ANIMATIONS D'ARME. Pendant un rechargement, un
			-- armement, une pompe ou une sortie d'arme, la pose de sprint
			-- s'efface (en 0.12 s, pas d'un coup) au lieu d'écraser le geste.
			-- Le joueur continue de courir : c'est seulement l'affichage des
			-- bras qui donne la priorité à l'animation.
			local busy = Reloading or Equipping or Pumping or Extra.cocking or Extra.inspecting
			Extra.animPrio = math.clamp((Extra.animPrio or 0) + (busy and 1 or -1) * dt * 8, 0, 1)
			mAlpha = mAlpha * (1 - Extra.animPrio)
			local mPoseL, mPoseR = WeaponSharedState.GetWeaponPose()
			mPoseR = Extra.gkSprint(mPoseR)   -- [GunKit P17b]
			Extra.liveMotion = Extra.liveAimMotion(dt)
			if RightArmWeld and RightArmBaseC1 then
				local gunR = RightArmBaseC1 * aimCF * swayUse * ReloadOffsetR * EquipOffsetR * Extra.gkArm("R", RightArmWeld) * RecoilOffset   -- [GunKit P16b] [GunKit P18c]
					* Extra.mvOf(RightArmWeld.Part0, "R")
				RightArmWeld.C1 = (mAlpha > 0.001) and gunR:Lerp(mPoseR, mAlpha) or gunR
			end
			if LeftArmWeld and LeftArmBaseC1 then
				local gunL = LeftArmBaseC1 * aimCF * swayUse * ReloadOffsetL * EquipOffsetL * Extra.gkArm("L", LeftArmWeld) * RecoilOffset   -- [GunKit P16c] [GunKit P18d]
					* Extra.mvOf(LeftArmWeld.Part0, "L")
				LeftArmWeld.C1 = (mAlpha > 0.001) and gunL:Lerp(mPoseL, mAlpha) or gunL
			end
			-- 🧱 [Murs] 3e personne : bras (et arme) relevés aux épaules contre un mur
			do
				Extra.ghostArms()   -- 👻 bras à travers les murs
				local a3 = Extra.wallThird(dt)
				local root3 = a3 > 0 and RightArmWeld and RightArmBaseC1 and LeftArmWeld and LeftArmBaseC1
					and MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
				if root3 then
					local e3 = a3 * a3 * (3 - 2 * a3)
					local rw = CFrame.fromAxisAngle(root3.CFrame.RightVector, math.rad((CS.WallPose.RaiseThird or 70) * e3))
					Extra.wallArm(RightArmWeld, rw)
					Extra.wallArm(LeftArmWeld, rw)
				end
			end
			Extra.thirdUpdate(swayUse, mAlpha, mPoseL, mPoseR, aimCF)
			-- 🔫 PISTE DE L'ARME
			-- L'éditeur d'animation, quand il est ouvert, pilote ces welds
			-- lui-même : on lui laisse la main, sinon on écraserait son aperçu.
			if not workspace:GetAttribute("AnimEditorFreeze") then
				-- Le weld actif dépend de la vue :
				--   1re personne → le weld du viewmodel (bras clonés)
				--   3e personne  → le RightGrip du vrai personnage
				-- On applique la MÊME formule aux deux : les deux vues montrent
				-- donc exactement la même chose.
				local gw2, gBase
				if viewmodel and viewmodel.Parent == camera and Extra.gunWeld
					and Extra.gunWeld.Parent then
					gw2, gBase = Extra.gunWeld, Extra.gunBaseC0
				else
					local ra0 = MyCharacter and MyCharacter:FindFirstChild("Right Arm")
					local rg = ra0 and ra0:FindFirstChild("RightGrip")
					if rg then
						-- la base du RightGrip, c'est le Grip du Tool : on la
						-- relit à chaque fois qu'il change (ré-équipe, respawn)
						if Extra.gripWeld ~= rg then
							Extra.gripWeld, Extra.gripBase = rg, rg.C0
						end
						gw2, gBase = rg, Extra.gripBase
					end
				end
				if gw2 and gBase and Extra.shareConfig.Enabled and Extra.third and gw2==Extra.third.grip then
					-- Le personnage réel et les observateurs utilisent la même prise.
					gw2.C0=Extra.third.c0
				elseif gw2 and gBase then
					local gOff, gFol = Extra.gunNow()
					-- pose voulue tant que le bras DROIT tient l'arme
					local rightWant = gBase * (gOff or CFrame.new())
					gFol = math.clamp(gFol or 0, 0, 1)
					if gFol <= 0.001 then
						Extra.gunGrabL = nil       -- l'arme est revenue au bras droit
						gw2.C0 = rightWant
					else
						local ra = gw2.Part0
						local la = ra and ra.Parent and ra.Parent:FindFirstChild("Left Arm")
						if ra and la and la.Parent then
							-- 🤝 TENUE PAR LA MAIN GAUCHE — déterministe :
							-- l'arme prend, par rapport au bras GAUCHE, la même
							-- prise qu'elle a dans le bras droit. Le décalage
							-- animé (gOff) s'applique par-dessus, donc il
							-- continue de marcher dans les deux mains.
							-- 🤝 LA PRISE. Au moment où la main gauche prend
							-- l'arme, on note où l'arme se trouve PAR RAPPORT au
							-- bras gauche — sans le décalage, pour que celui-ci
							-- reste un vrai réglage que TU pilotes. L'arme ne se
							-- téléporte donc pas sur le bras : elle continue
							-- exactement d'où elle était, et c'est le bras gauche
							-- qui la porte à partir de là.
							if not Extra.gunGrabL then
								Extra.gunGrabL = la.CFrame:Inverse() * (ra.CFrame * gBase)
							end
							local wantWorld = la.CFrame * Extra.gunGrabL * (gOff or CFrame.new())
							local leftWant = ra.CFrame:Inverse() * wantWorld * gw2.C1
							gw2.C0 = rightWant:Lerp(leftWant, gFol)
						else
							gw2.C0 = rightWant
						end
					end
				end
			end
			Extra.share:Step()
		end)
	end
	-- ========================================================
	-- RELOAD (engine)
	-- ========================================================
	-- 🆕 courbe optionnelle (6e argument) — nil = smooth, comme avant
	local function lerpReload(dur, fromR, toR, fromL, toL, ease)
		local t = 0
		-- 🎟 LE JETON D'INTERRUPTION, pris À L'ENTRÉE du geste. Avant, un
		-- drapeau `shellStop` restait vrai APRÈS l'annulation : tous les gestes
		-- suivants (pompe, armement, sortie d'arme…) se coupaient aussitôt.
		-- Un jeton ne peut pas rester coincé : il n'arrête que ce qui tournait
		-- au moment de l'interruption.
		local seq = Extra.cutTok or 0
		while t < dur do
			if (Extra.cutTok or 0) ~= seq then return end
			t += RunService.Heartbeat:Wait()
			local x = math.clamp(t/dur, 0, 1)
			if ease == "in" then x = x*x
			elseif ease == "out" then x = 1-(1-x)*(1-x)
			elseif ease == "linear" then -- rien
			else x = x*x*(3-2*x) end
			ReloadOffsetR = fromR:Lerp(toR, x); ReloadOffsetL = fromL:Lerp(toL, x)
		end
		ReloadOffsetR, ReloadOffsetL = toR, toL
	end
	-- 🆕 R1 : chaque keyframe peut choisir SA courbe d'arrivée via `ease`.
	-- C'est l'unique changement qui donne de la vie à une anim : un geste humain
	-- n'est jamais symétrique. Une main qui va CHERCHER freine en arrivant ("out"),
	-- un chargeur qu'on CLAQUE accélère jusqu'à l'impact ("in").
	--   "out"    → freine en arrivant (approche, retour au repos)
	--   "in"     → accélère (insertion, claquement, impact)
	--   "snap"   → très sec, quasi instantané (culasse qui part en avant)
	--   "linear" → vitesse constante (mouvement mécanique)
	--   nil      → smooth (l'ancien comportement, doux des deux côtés)
	local function playKeyframeReload(keyframes, totalTime)
		Extra.playGunTrack(keyframes, totalTime)   -- 🔫 les keyframes portent g / gf
		local id = CFrame.new()
		local function curve(x, ease)
			x = math.clamp(x, 0, 1)
			if ease == "in" then return x * x
			elseif ease == "out" then return 1 - (1 - x) * (1 - x)
			elseif ease == "snap" then local u = 1 - x; return 1 - u*u*u*u
			elseif ease == "linear" then return x
			else return x * x * (3 - 2 * x) end
		end
		local start = tick()
		while true do
			local p = math.clamp((tick()-start)/totalTime, 0, 1)
			local from, to = keyframes[1], keyframes[#keyframes]
			for i=1,#keyframes-1 do
				if p >= keyframes[i].t and p <= keyframes[i+1].t then from, to = keyframes[i], keyframes[i+1]; break end
			end
			local seg = to.t - from.t
			-- la courbe est celle du keyframe d'ARRIVÉE : elle décrit comment on y entre
			local st = seg>0 and curve((p-from.t)/seg, to.ease) or 1
			ReloadOffsetR = from.r:Lerp(to.r, st)
			ReloadOffsetL = from.l:Lerp(to.l, st)
			if p >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		ReloadOffsetR, ReloadOffsetL = id, id
	end
	-- RPG : la roquette est tenue par la MAIN GAUCHE (qui bouge avec les keyframes
	-- de reload). Elle part d'une pose "dans la main" et glisse jusqu'à la pose
	-- "chargée dans le tube", les DEUX exprimées par rapport à la main gauche
	-- → un seul repère, aucun saut. Réglable en live via attributs.
	-- RPG : la roquette est tenue par la MAIN GAUCHE (qui bouge avec les keyframes
	-- de reload). Part de "dans la main" → glisse jusqu'à "chargée dans le tube".
	-- Toutes les parts du Missile sont soudées à la PrimaryPart pour rester solidaires.
	local function SpawnReloadRocket()
		local pm = tool:FindFirstChild(cfg.Rocket.MissileModelName)
		local src = pm and pm:FindFirstChild(cfg.Rocket.MissileName)
		if not src then return nil end
		local inVM = viewmodel and viewmodel.Parent == camera
		local leftArm = inVM and viewmodel:FindFirstChild("Left Arm")
			or (MyCharacter and MyCharacter:FindFirstChild("Left Arm"))
		if not leftArm then return nil end
		local parentModel = inVM and viewmodel or camera
		local prop = src:Clone()
		prop.Name = "ReloadRocketProp"
		for _, d in ipairs(prop:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("RemoteEvent") then d:Destroy() end
		end
		-- PrimaryPart = celle du clone (même nom que l'original)
		local primary = prop.PrimaryPart
		if not primary or not primary:IsDescendantOf(prop) then
			primary = prop:FindFirstChildWhichIsA("BasePart", true)
		end
		if not primary then prop:Destroy(); return nil end
		prop.PrimaryPart = primary
		-- ── SOLIDARISE TOUT le missile à la PrimaryPart ──
		-- On capture les positions relatives AVANT de toucher aux parts, puis on
		-- soude chaque part (sauf la primary) à la primary à sa position d'origine.
		-- Comme ça, peu importe l'état des welds clonés (cassés/non-remappés), tout
		-- reste assemblé exactement comme le Missile d'origine.
		local pInv = primary.CFrame:Inverse()
		local rel = {}
		for _, d in ipairs(prop:GetDescendants()) do
			if d:IsA("BasePart") and d ~= primary then
				rel[d] = pInv * d.CFrame
			end
		end
		-- on vire les welds clonés (potentiellement cassés) pour repartir propre
		for _, d in ipairs(prop:GetDescendants()) do
			if d:IsA("JointInstance") then d:Destroy() end
		end
		for _, d in ipairs(prop:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored=false; d.CanCollide=false; d.CanQuery=false; d.Massless=true; d.CastShadow=false
			end
		end
		for part, c0 in pairs(rel) do
			local jw = Instance.new("Weld")
			jw.Name = "RocketPartWeld"
			jw.Part0 = primary; jw.Part1 = part
			jw.C0 = c0; jw.C1 = CFrame.new()
			jw.Parent = primary
		end
		-- weld piloté à la MAIN GAUCHE
		local w = Instance.new("Weld"); w.Name="ReloadRocketWeld"
		w.Part0 = leftArm; w.Part1 = primary; w.Parent = primary
		prop.Parent = parentModel
		local RP = cfg.Rocket.ReloadProp
		local startC1 = RP.HandOffset or CFrame.new(0, -1.0, 0)
		local seatC1  = RP.SeatOffset or (CFrame.new(0.6, 0.2, -1.2) * CFrame.Angles(0, math.rad(90), 0))
		w.C1 = startC1
		local dur  = RP.Time or cfg.Reload.Time
		local seat = RP.SeatAt or 0.82
		task.spawn(function()
			local t0 = tick()
			while prop.Parent and w.Parent do
				local sx,sy,sz = tool:GetAttribute("TuneRocketStartX"), tool:GetAttribute("TuneRocketStartY"), tool:GetAttribute("TuneRocketStartZ")
				local srx,sry,srz = tool:GetAttribute("TuneRocketStartRX"), tool:GetAttribute("TuneRocketStartRY"), tool:GetAttribute("TuneRocketStartRZ")
				local liveStart = startC1
				if sx or sy or sz or srx or sry or srz then
					liveStart = CFrame.new(sx or 0, sy or 0, sz or 0)
						* CFrame.Angles(math.rad(srx or 0), math.rad(sry or 0), math.rad(srz or 0))
				end
				local ex,ey,ez = tool:GetAttribute("TuneRocketSeatX"), tool:GetAttribute("TuneRocketSeatY"), tool:GetAttribute("TuneRocketSeatZ")
				local erx,ery,erz = tool:GetAttribute("TuneRocketSeatRX"), tool:GetAttribute("TuneRocketSeatRY"), tool:GetAttribute("TuneRocketSeatRZ")
				local liveSeat = seatC1
				if ex or ey or ez or erx or ery or erz then
					liveSeat = CFrame.new(ex or 0, ey or 0, ez or 0)
						* CFrame.Angles(math.rad(erx or 0), math.rad(ery or 0), math.rad(erz or 0))
				end
				-- 🆕 l'Anim Studio TIENT la roquette : c'est lui qui décide où en
				-- est le geste, et le prop ne disparaît pas au bout de 3 secondes.
				local held = tool:GetAttribute("TuneRocketHold") == true
				local p = held
					and math.clamp(tool:GetAttribute("TuneRocketPhase") or 0, 0, 1)
					or math.clamp((tick()-t0) / (dur*seat), 0, 1)
				local x = p*p*(3-2*p)
				w.C1 = liveStart:Lerp(liveSeat, x)
				if p >= 1 and not held then w.C1 = liveSeat; break end
				RunService.Heartbeat:Wait()
			end
		end)
		Extra.shareRocketProp = prop
		return prop
	end
	Reload = function()
		if Reloading then return end
		local reloadCharacter = Players.LocalPlayer.Character
		local reloadHumanoid = reloadCharacter and reloadCharacter:FindFirstChildOfClass("Humanoid")
		if not reloadHumanoid or reloadHumanoid.Health <= 0 or tool.Parent ~= reloadCharacter then return end
		if AmmoInClip == cfg.ClipSize or SpareAmmo <= 0 then return end
		Reloading = true
		Extra.reloadAimAt, Extra.chamberAimAt = nil, nil
		SetAiming(false) -- garde Extra.aimInput pour reprendre après le geste

		-- 🎟️ IDENTIFIANT UNIQUE DE CE RELOAD.
		-- Toute tâche différée appartenant à un ancien reload sera ignorée.
		Extra.reloadTok = (Extra.reloadTok or 0) + 1
		local reloadTok = Extra.reloadTok
		local function reloadAlive()
			return Extra.reloadTok == reloadTok and Players.LocalPlayer.Character == reloadCharacter
				and reloadHumanoid.Parent ~= nil and reloadHumanoid.Health > 0
		end

		-- Jeton d'interruption de ce reload précis
		local dropSeq = Extra.cutTok or 0

		-- 🆕 LE TUBE / CHARGEUR ÉTAIT-IL VIDE ?Toute la suite en dépend :
		-- s'il restait une cartouche, elle est déjà en chambre et il ne faut
		-- SURTOUT pas pomper (on l'éjecterait pour rien) ; s'il était vide, il
		-- faut chambrer à la fin. C'est la seule différence entre les deux
		-- rechargements, et elle tient dans ce booléen.
		Extra.wasEmpty = (AmmoInClip <= 0)
		pumpToken += 1   -- annule une pompe éventuellement en attente
		if RecoilTrack then RecoilTrack:Stop() end
		local R = cfg.Reload
		if Extra.wasEmpty and R.Empty then R = R.Empty end
		-- [GunKit P8] variantes de rechargement (jamais deux fois la même d'affilée)
		if type(R.Variants) == "table" and #R.Variants > 0 then
			local n = #R.Variants
			local i = math.random(n)
			if n > 1 and i == Extra.lastReloadVariant then i = i % n + 1 end
			Extra.lastReloadVariant = i
			R = R.Variants[i]
		end
		if R.Style ~= "Shell" then Extra.reloadWindow(R.Time or 1.8) end
		if R.Style == "Shell" then
			local toReload = math.min(cfg.ClipSize - AmmoInClip, SpareAmmo)
			-- 🔄 UN CRAN PAR CARTOUCHE : l'anneau avance d'un bloc entier à
			-- chaque cartouche qui entre. Ça se lit d'un coup d'œil, bien mieux
			-- qu'une barre qui glisse.
			-- 🆕 à vide, chaque cartouche va plus vite : le rechargement complet
			-- reste supportable sans qu'on ait touché au rechargement normal.
			local perShell = (R.TimePerShell or 0.5)
			if Extra.wasEmpty then
				perShell = perShell / math.max(0.2, R.EmptyShellSpeed or 1)
			end
			local introT = (type(R.Intro) == "table" and R.Intro.Keyframes and R.Intro.Time) or 0.22   -- [GunKit P14]
			Extra.reloadWindow(introT + toReload * perShell + (R.Settle or 0.18))
			local run = Extra.cutTok or 0
			SetReloadingTextVisible(true, introT + toReload * perShell, toReload)
			if type(R.Intro) == "table" and R.Intro.Keyframes then
				-- ouverture animée (revolver : loquet, barillet sorti, éjection)
				Extra.playSoundTrack(R.Intro.SoundTrack, introT)
				task.spawn(Extra.playPartTrack, R.Intro.PartKeys, introT)
				Extra.playPose(R.Intro.Keyframes, introT, true)
			else
				lerpReload(0.22, CFrame.new(), R.GunPose, CFrame.new(), CFrame.new())  -- intro
			end
			for i = 1, toReload do
				Extra.reloadWindow((toReload - i + 1) * perShell + (R.Settle or 0.18))
				if not reloadAlive() then return end
				-- 🆕 un tir a demandé l'arrêt : on s'arrête NET, l'arme revient
				-- au repos, et le joueur garde ce qu'il a chargé.
				if (Extra.cutTok or 0) ~= run then break end
				local ch = Players.LocalPlayer.Character
				local hm = ch and ch:FindFirstChildOfClass("Humanoid")
				if not hm or hm.Health <= 0 then   -- seule la MORT annule
					ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new()
					Reloading=false; SetReloadingTextVisible(false); return
				end
				-- 🆕 UNE VRAIE CARTOUCHE ENTRE DANS L'ARME, À CHAQUE GESTE.
				-- Avant, les munitions étaient ajoutées EN BLOC à la fin : la
				-- jauge ne pouvait pas monter cartouche par cartouche, et un
				-- rechargement interrompu ne laissait rien. Maintenant elle
				-- entre au milieu du geste — là où ton animation la met.
				local seq = Extra.cutTok or 0
				task.delay((R.ShellAt or 0.5) * perShell, function()
					if not reloadAlive() then return end
					-- annulée par un tir : cette cartouche n'entre pas
					if (Extra.cutTok or 0) ~= seq then return end
					if not Reloading then return end
					if AmmoInClip >= cfg.ClipSize or SpareAmmo <= 0 then return end
					AmmoInClip += 1; SpareAmmo -= 1
					UpdateAmmo(AmmoInClip)
				end)
				if tool.Parent == ch then
					-- 🆕 ANIMATION DE L'ANIM STUDIO : les DEUX bras sur toutes les
					-- étapes, plus tes sons et tes douilles, à chaque cartouche.
					if type(R.ShellKeyframes) == "table" and #R.ShellKeyframes >= 2 then
						Extra.playSoundTrack(R.SoundTrack, perShell)
						Extra.playShellTrack(R.ShellTrack, perShell)
						Extra.playGunTrack(R.GunTrack, perShell)
						task.spawn(Extra.playPartTrack, R.ShellPartKeys, perShell)
						task.spawn(Extra.playMagTrack, R.ShellMagTrack, perShell)
						Extra.playPose(R.ShellKeyframes, perShell, true)
					else
						-- équipée : anim + sons normaux, balle par balle
						Receiver:FireServer("PlaySound", cfg.Sounds.Reload)
						local d = perShell/3
						lerpReload(d, R.GunPose, R.GunPose, CFrame.new(), R.HandDown)
						lerpReload(d, R.GunPose, R.GunPose, R.HandDown, R.HandPort)
						lerpReload(perShell-2*d, R.GunPose, R.GunPose, R.HandPort, CFrame.new())
					end
				else
					-- ARRIÈRE-PLAN (backpack) : même durée, sans anim ni son
					task.wait(perShell)
				end
			end
			if not reloadAlive() then return end
			if tool.Parent == Players.LocalPlayer.Character then
				-- 🆕 Ici on se contente de REPOSER l'arme. Le pompage, quand il
				-- a lieu, est joué plus bas avec TON animation de chambrage —
				-- plus ce rack bricolé qui partait à chaque rechargement.
				-- interrompu par un tir : on repose l'arme deux fois plus vite,
				-- sinon le tir semblerait « coller »
				Extra.reloadWindow((R.Settle or 0.18) * (((Extra.cutTok or 0) ~= run) and 0.45 or 1))
				if type(R.Outro) == "table" and R.Outro.Keyframes then   -- [GunKit P14b] fermeture animée
					local k = ((Extra.cutTok or 0) ~= run) and 0.6 or 1
					Extra.playSoundTrack(R.Outro.SoundTrack, R.Outro.Time * k)
					task.spawn(Extra.playPartTrack, R.Outro.PartKeys, R.Outro.Time * k)
					Extra.playPose(R.Outro.Keyframes, R.Outro.Time * k, true)
				else
					lerpReload((R.Settle or 0.18)
						* (((Extra.cutTok or 0) ~= run) and 0.45 or 1),
						R.GunPose, CFrame.new(), CFrame.new(), CFrame.new())
				end
			end
			ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new()
			-- (les cartouches ont été comptées UNE PAR UNE pendant la boucle ;
			--  il n'y a plus rien à ajouter ici. Ce filet rattrape seulement un
			--  geste dont la cartouche n'aurait pas eu le temps d'entrer.)
			if not reloadAlive() then return end
			local missing = math.min(toReload, cfg.ClipSize - AmmoInClip, SpareAmmo)
			if missing > 0 and (R.ShellAt or 0.5) >= 1 then
				AmmoInClip += missing; SpareAmmo -= missing
			end
		else
			SetReloadingTextVisible(true, R.Time or 1.8)
			local dropSeq = Extra.cutTok or 0   -- 🎟 jeton de CE rechargement précis
			-- 🧲 LE CHARGEUR TOMBE, au moment du geste que tu choisis.
			-- Rien ne se passe si l'arme n'a pas la pièce nommée : les armes
			-- encore d'un seul bloc sont ignorées en silence.
			for nm, d in pairs(cfg.Parts or {}) do
				if d.Drop then
					local at = math.clamp(d.DropAt or 0.28, 0, 0.95) * (R.Time or 1.8)

					task.delay(at, function()

						-- 🧯 Ce callback appartient à CE reload uniquement.
						-- Si on est mort, si le reload a été interrompu,
						-- ou si un nouveau reload a commencé, on ne fait RIEN.
						if Extra.reloadTok ~= reloadTok then return end
						if (Extra.cutTok or 0) ~= dropSeq then return end
						if not Reloading then return end

						local ch = Players.LocalPlayer.Character
						local hm = ch and ch:FindFirstChildOfClass("Humanoid")
						if not hm or hm.Health <= 0 then return end

						-- Le Tool doit toujours appartenir au personnage correspondant.
						if tool.Parent ~= ch then return end

						Extra.magDrop(nm, d, reloadTok, dropSeq)
					end)
				end
			end
			-- 🆕 R2 : plusieurs bruits placés dans le temps au lieu d'un seul au début.
			-- L'œil voit 4 gestes, l'oreille doit entendre 4 bruits — c'est ça qui
			-- fait "fini". Les Sounds vont dans le HANDLE de l'arme.
			if R.SoundTrack and #R.SoundTrack > 0 then
				for _, ev in ipairs(R.SoundTrack) do
					task.delay(R.Time * (ev.t or 0), function()
						if not reloadAlive() then return end
						if not Reloading then return end          -- annulé (mort) → pas de son fantôme
						if tool.Parent ~= Players.LocalPlayer.Character then return end
						Receiver:FireServer("PlaySound", ev.name)
					end)
				end
			else
				Receiver:FireServer("PlaySound", cfg.Sounds.Reload)
			end
			-- RPG : fait apparaître une roquette dans la main gauche pendant l'anim
			local reloadProp = nil
			if cfg.Rocket.Enabled and cfg.Rocket.ReloadProp then
				reloadProp = SpawnReloadRocket()
			end
			-- 🧩🧲 les pièces et le chargeur, en parallèle des bras
			task.spawn(Extra.playPartTrack, R.PartKeys, R.Time)
			task.spawn(Extra.playMagTrack, R.MagTrack, R.Time)
			if R.Style == "Keyframe" and R.Keyframes then
				task.spawn(playKeyframeReload, R.Keyframes, R.Time)
			end
			Extra.playShellTrack(R.ShellTrack, R.Time)   -- 💥 tes éjections
			task.wait(R.Time)
			if reloadProp then reloadProp:Destroy(); reloadProp = nil end
			if not reloadAlive() then return end
			-- ARRIÈRE-PLAN : arme déséquipée pendant la recharge → on termine quand
			-- même. Seule la MORT annule (on teste le perso VIVANT du joueur, pas
			-- MyHumanoid qui est nil après le déséquipe).
			do
				local ch = Players.LocalPlayer.Character
				local hm = ch and ch:FindFirstChildOfClass("Humanoid")
				if not hm or hm.Health <= 0 then
					Reloading=false; SetReloadingTextVisible(false); return
				end
			end
			local toUse = math.min(cfg.ClipSize - AmmoInClip, SpareAmmo)
			AmmoInClip += toUse; SpareAmmo -= toUse
		end
		if not reloadAlive() then return end
		UpdateAmmo(AmmoInClip)
		SetReloadingTextVisible(false)
		Reloading = false
		for nm, d in pairs(cfg.Parts or {}) do
			if d.Drop then Extra.magBack(nm) end
		end
		-- 🆕 CHAMBRAGE APRÈS UN RECHARGEMENT FAIT À SEC.
		-- Fusil à pompe → ton animation « POMPAGE DE CHAMBRAGE ».
		-- Verrou (sniper) → ton animation d'armement.
		-- Dans les deux cas SANS douille : il n'y a pas d'étui à éjecter, on
		-- met une cartouche neuve en chambre. (Sauf si une douille était restée
		-- en attente — voir Extra.shellDue plus bas.)
		if Extra.wasEmpty then
			Extra.wasEmpty = false
			if (cfg.Reload.RackPump or cfg.Reload.PumpAfterShot) and cfg.Reload.RackOnEmpty ~= false then
				task.spawn(Extra.playPump, true, true)
			elseif cfg.Equip.Cock and cfg.Equip.Cock.Enabled
				and cfg.Equip.Cock.RackOnEmpty ~= false then
				task.spawn(Extra.playBolt, true, true)
			end
		end
	end
	-- ── Pompe après tir (shotgun) : la main GAUCHE racke la pompe ──
	-- force   = chambrage (joue même juste après un rechargement) ET utilise
	--           l'animation RackPump si elle existe
	-- noShell = ne pas éjecter de douille (on chambre, il n'y a rien à sortir)
	function Extra.playPump(force, noShell)
		local P = (force and (cfg.Reload.RackPump or cfg.Reload.PumpAfterShot)) or cfg.Reload.PumpAfterShot
		if not P or Pumping or IsShooting then return end
		if Reloading and not force then return end
		if not MyHumanoid or MyHumanoid.Health <= 0 then return end
		Pumping = true
		Extra.chamberAimAt = force and math.min(Extra.reloadAimAt or math.huge, os.clock() + (P.Time or 0.34) - Extra.aimLead(P.Time or 0.34)) or nil
		if P.Sound then Receiver:FireServer("PlaySound", P.Sound) end
		local idR = CFrame.new()
		local grab = P.Grab or (CFrame.new(0.10, -0.45, 0.35) * CFrame.Angles(math.rad(28), 0, 0))
		local back = P.Back or 0.28
		local t = P.Time or 0.34
		Extra.playGunTrack(P.GunTrack, t)   -- 🔫 piste de l'arme
		-- 🆕 ANIMATION DE L'ANIM STUDIO : les DEUX bras, tes douilles, tes sons.
		if type(P.Keyframes) == "table" and #P.Keyframes >= 2 then
			Extra.playSoundTrack(P.SoundTrack, t)
			if not noShell or Extra.shellDue then
				Extra.shellDue = false
				Extra.playShellTrack(P.ShellTrack, t)
			end
			task.spawn(Extra.playPartTrack, P.PartKeys, t)
			task.spawn(Extra.playMagTrack, P.MagTrack, t)
			Extra.playPose(P.Keyframes, t, force)
			ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new()
			Pumping = false
			return
		end
		-- 🆕 R5 : rythme ASYMÉTRIQUE 35/15/15/35 au lieu de 25/25/25/25.
		-- Une pompe réelle : main qui descend (lent) → arrière SEC → avant SEC →
		-- main qui remonte (lent). C'est ce qui fait le "chick-chick" net.
		local d1, d2, d3 = t*0.35, t*0.15, t*0.15
		local d4 = t - d1 - d2 - d3
		lerpReload(d1, idR, idR, CFrame.new(), grab, "out")                      -- descend et se pose
		if P.Sound then Receiver:FireServer("PlaySound", P.Sound) end
		lerpReload(d2, idR, idR, grab, grab * CFrame.new(0,0,back), "in")        -- CHICK arrière
		-- 🆕 LA DOUILLE SORT ICI, sur la course arrière — pas au coup de feu.
		-- C'est ce qui fait une pompe : tu tires, l'étui reste dedans ; tu
		-- pompes, il saute. Extra.shellDue rattrape le cas où le joueur a
		-- rechargé avant que la pompe du dernier tir ait eu lieu.
		if (not noShell or Extra.shellDue) and cfg.FX.ShellOnPump ~= false then
			Extra.shellDue = false
			for _ = 1, (cfg.FX.ShellsPerPump or cfg.FX.ShellsPerShot or 1) do
				SpawnLocalShell(((viewmodel and viewmodel:FindFirstChild("Handle")) or Handle).CFrame)
			end
		end
		if P.SoundForward then Receiver:FireServer("PlaySound", P.SoundForward) end
		lerpReload(d3, idR, idR, grab * CFrame.new(0,0,back), grab, "in")        -- CHICK avant
		lerpReload(d4, idR, idR, grab, CFrame.new(), "out")                      -- remonte
		ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new()
		Pumping = false
	end
	-- ========================================================
	-- 🆕 INSPECTION
	-- ========================================================
	-- Jouée sur les offsets de RECHARGEMENT, comme la pompe et le verrou.
	-- Le jeton permet de la relancer proprement : un nouvel appui coupe la
	-- lecture en cours et repart de zéro.
	function Extra.playInspect()
		local I = cfg.Inspect
		if not I or I.Enabled == false then return end
		local K = I.Keyframes
		if type(K) ~= "table" or #K < 2 then return end
		if Reloading or IsShooting or Pumping or Extra.cocking or Equipping then return end
		-- 🔁 V PENDANT UNE INSPECTION : on repart du DÉBUT.
		-- J'avais ajouté « or Extra.inspecting » dans la ligne au-dessus en
		-- corrigeant le gel des bras : ça bloquait le relancement, alors que
		-- respammer V doit relancer l'animation. On coupe donc l'inspection en
		-- cours — instantanément, sans le retour doux, sinon il écraserait la
		-- nouvelle pose pendant sa première fraction de seconde.
		if Extra.inspecting then Extra.stopInspect(true) end
		if not MyHumanoid or MyHumanoid.Health <= 0 then return end
		-- 👁 L'INSPECTION MARCHE AUSSI EN 3e PERSONNE.
		-- Elle était refusée hors 1re personne — mais les bras et l'arme sont
		-- animés dans les deux vues, donc il n'y a aucune raison de la bloquer.
		-- Mets Inspect.FirstPersonOnly = true si tu veux l'ancien comportement.
		if I.FirstPersonOnly == true and not IsActuallyFirstPerson() then return end
		-- 🩹 les pistes ne partaient qu'APRÈS ces refus dans l'ordre d'écriture,
		-- mais elles étaient lancées AVANT : le chargeur et les pièces
		-- s'animaient même quand l'inspection était refusée. Elles partent
		-- maintenant une fois l'inspection réellement acceptée.
		task.spawn(Extra.playPartTrack, I.PartKeys, I.Time)
		task.spawn(Extra.playMagTrack, I.MagTrack, I.Time)
		Extra.inspToken = (Extra.inspToken or 0) + 1
		local my = Extra.inspToken
		Extra.inspecting = true
		local dur = I.Time or 2.2
		if I.SoundTrack then
			for _, ev in ipairs(I.SoundTrack) do
				task.delay(dur * (ev.t or 0), function()
					if my ~= Extra.inspToken or not Extra.inspecting then return end
					if tool.Parent ~= MyCharacter then return end
					Receiver:FireServer("PlaySound", ev.name)
				end)
			end
		end
		Extra.playGunTrack(I.GunTrack or K, dur)
		Extra.playShellTrack(I.ShellTrack, dur)   -- 💥
		local function curve(x, ease)
			x = math.clamp(x, 0, 1)
			if ease == "in" then return x * x
			elseif ease == "out" then return 1 - (1 - x) * (1 - x)
			elseif ease == "snap" then local u = 1 - x; return 1 - u*u*u*u
			elseif ease == "linear" then return x
			else return x * x * (3 - 2 * x) end
		end
		local start = tick()
		while true do
			-- coupée par : un nouvel appui, un tir, un reload, la mort, le holster
			if my ~= Extra.inspToken or Reloading or IsShooting
				or not MyHumanoid or MyHumanoid.Health <= 0
				or tool.Parent ~= MyCharacter then
				break
			end
			local p = math.clamp((tick() - start) / dur, 0, 1)
			local from, to = K[1], K[#K]
			for i = 1, #K - 1 do
				if p >= K[i].t and p <= K[i+1].t then from, to = K[i], K[i+1]; break end
			end
			local seg = to.t - from.t
			local st = seg > 0 and curve((p - from.t) / seg, to.ease) or 1
			ReloadOffsetR = from.r:Lerp(to.r, st)
			ReloadOffsetL = from.l:Lerp(to.l, st)
			if p >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		if my == Extra.inspToken then
			Extra.inspecting = false
			-- on ne remet à zéro que si personne d'autre n'anime les bras
			if not (Reloading or Pumping or Extra.cocking or Equipping) then
				ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new()
			end
		end
	end
	-- 🩹 L'INSPECTION QUI RESTE FIGÉE.
	-- stopInspect avançait le jeton, donc la boucle sortait — mais la remise à
	-- zéro des bras, à la fin de playInspect, était gardée par
	-- « if my == Extra.inspToken », qui venait justement de devenir FAUX. Les
	-- bras restaient donc bloqués sur la dernière pose de l'inspection jusqu'à
	-- ce qu'une autre animation les reprenne. C'est exactement ce que tu voyais.
	-- Maintenant c'est stopInspect qui rend les bras, et il le fait en DOUCEUR :
	-- l'arme revient à sa position de tir au lieu de sauter.
	function Extra.stopInspect(instant)
		if not Extra.inspecting then return end
		Extra.inspToken = (Extra.inspToken or 0) + 1
		Extra.inspecting = false
		if Reloading or Pumping or Extra.cocking or Equipping then return end
		if instant then
			ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new()
			return
		end
		local my = Extra.inspToken
		task.spawn(function()
			local t, dur = 0, (cfg.Inspect and cfg.Inspect.CancelTime) or 0.12
			local r0, l0 = ReloadOffsetR, ReloadOffsetL
			while t < dur do
				-- une autre animation a repris les bras : on lui laisse la main
				if my ~= Extra.inspToken or Reloading or Pumping
					or Extra.cocking or Equipping then return end
				t += RunService.Heartbeat:Wait()
				local x = math.clamp(t / dur, 0, 1)
				x = 1 - (1 - x) * (1 - x)          -- sortie douce
				ReloadOffsetR = r0:Lerp(CFrame.new(), x)
				ReloadOffsetL = l0:Lerp(CFrame.new(), x)
			end
			if my == Extra.inspToken then
				ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new()
			end
		end)
	end
	-- ========================================================
	-- 🔫 PISTE DE L'ARME
	-- ========================================================
	-- Une piste = { { t = 0..1, g = CFrame, f = 0..1 }, ... }
	--   g = décalage libre de l'arme
	--   f = 0 → l'arme suit le bras DROIT (comportement d'origine)
	--       1 → l'arme suit le bras GAUCHE (la main gauche la tient, et le bras
	--           droit part manœuvrer le levier sans l'emmener avec lui)
	-- Pas de piste, ou piste toute à zéro = exactement comme avant.
	-- 🆕 LECTEUR GÉNÉRIQUE D'ANIMATION « POSES ».
	-- L'Anim Studio publie la pompe, l'armement, le chambrage et la recharge
	-- cartouche AUSSI sous forme de keyframes : c'est la seule forme qui porte
	-- les DEUX bras sur toutes les étapes. Quand elle existe, on la joue telle
	-- quelle ; sinon on garde l'ancien découpage codé en dur.
	function Extra.playPose(keys, dur, force)
		if type(keys) ~= "table" or #keys < 2 then return false end
		dur = math.max(0.03, dur or 0.4)
		local t0 = tick()
		local seq = Extra.cutTok or 0        -- 🎟 même règle que lerpReload
		while true do
			if not force and Reloading then break end
			if (Extra.cutTok or 0) ~= seq then break end
			if not MyHumanoid or MyHumanoid.Health <= 0 then break end
			local p = math.clamp((tick() - t0) / dur, 0, 1)
			local from, to = keys[1], keys[#keys]
			for i = 1, #keys - 1 do
				if p >= (keys[i].t or 0) and p <= (keys[i+1].t or 1) then
					from, to = keys[i], keys[i+1]; break
				end
			end
			local seg = (to.t or 1) - (from.t or 0)
			local x = seg > 0 and math.clamp((p - (from.t or 0)) / seg, 0, 1) or 1
			if to.ease == "in" then x = x * x
			elseif to.ease == "out" then x = 1 - (1-x)*(1-x)
			elseif to.ease == "snap" then local u = 1 - x; x = 1 - u*u*u*u
			elseif to.ease ~= "linear" then x = x * x * (3 - 2*x) end
			ReloadOffsetR = (from.r or CFrame.new()):Lerp(to.r or CFrame.new(), x)
			ReloadOffsetL = (from.l or CFrame.new()):Lerp(to.l or CFrame.new(), x)
			if p >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		return true
	end
	-- 🆕 LES DOUILLES POSÉES DANS L'ANIMATION.
	-- Chaque entrée est { t = 0..1, ...réglages } : on les programme toutes
	-- d'un coup, chacune part à son instant.
	function Extra.playShellTrack(list, dur)
		if type(list) ~= "table" then return false end
		-- 🎟 idem pour les douilles : une éjection d'un geste annulé sortait
		-- toute seule, après le tir.
		local cut = Extra.cutTok or 0
		for _, e in ipairs(list) do
			task.delay(math.max(0, (e.t or 0)) * math.max(0.03, dur or 0.4), function()
				if (Extra.cutTok or 0) ~= cut then return end
				if not MyHumanoid or MyHumanoid.Health <= 0 then return end
				if tool.Parent ~= MyCharacter then return end
				local h = (viewmodel and viewmodel:FindFirstChild("Handle")) or Handle
				for _ = 1, math.max(1, math.floor(e.count or 1)) do
					SpawnLocalShell(h.CFrame, e)
				end
			end)
		end
		return #list > 0
	end
	-- 🆕 la bande son d'une animation « poses » (l'Anim Studio en pose plusieurs)
	function Extra.playSoundTrack(list, dur)
		if type(list) ~= "table" then return false end
		-- 🎟 les sons d'un geste ANNULÉ ne doivent plus tomber après coup :
		-- on entendait le « clac » du rechargement une fois le tir parti.
		local cut = Extra.cutTok or 0
		for _, e in ipairs(list) do
			if e.name then
				task.delay(math.max(0, (e.t or 0)) * math.max(0.03, dur or 0.4), function()
					if (Extra.cutTok or 0) ~= cut then return end
					if tool.Parent ~= MyCharacter then return end
					Receiver:FireServer("PlaySound", e.name)
				end)
			end
		end
		return #list > 0
	end
	function Extra.playGunTrack(list, dur)
		if type(list) ~= "table" or #list == 0 or not dur or dur <= 0 then
			Extra.gunTrack = nil; return
		end
		Extra.gunTrack = list
		Extra.gunT0 = tick()
		Extra.gunDur = dur
	end
	function Extra.gunNow()
		local L = Extra.gunTrack
		if not L then return nil, 0 end
		local p = (tick() - (Extra.gunT0 or 0)) / math.max(0.02, Extra.gunDur or 1)
		if p >= 1 then Extra.gunTrack = nil; return nil, 0 end
		p = math.clamp(p, 0, 1)
		local from, to = L[1], L[#L]
		for i = 1, #L - 1 do
			if p >= (L[i].t or 0) and p <= (L[i+1].t or 1) then from, to = L[i], L[i+1]; break end
		end
		local seg = (to.t or 1) - (from.t or 0)
		local x = seg > 0 and ((p - (from.t or 0)) / seg) or 1
		x = x * x * (3 - 2 * x)                       -- lissage
		local gA = from.g or CFrame.new()
		local gB = to.g or CFrame.new()
		local fA = from.f or from.gf or 0
		local fB = to.f or to.gf or 0
		return gA:Lerp(gB, x), fA + (fB - fA) * x
	end
	function Extra.schedulePump()
		local P = cfg.Reload.PumpAfterShot
		if not P then return end
		pumpToken += 1
		local my = pumpToken
		task.delay(P.Delay or 0.7, function()
			if my ~= pumpToken then return end          -- un nouveau tir a relancé le timer
			if Reloading or IsShooting then return end
			-- 🆕 on pompe AUSSI quand le tube est vide : c'est le geste qui
			-- éjecte le dernier étui. Mets OnLastShot = false pour l'ancien
			-- comportement.
			if AmmoInClip <= 0 and P.OnLastShot == false then return end
			if not MyHumanoid or MyHumanoid.Health <= 0 then return end
			task.spawn(Extra.playPump)
		end)
	end
	-- ========================================================
	-- 🆕 ARMEMENT APRÈS TIR (verrou / levier)
	-- ========================================================
	-- Même poses que Equip.Cock, jouées sur les offsets de RECHARGEMENT (comme
	-- la pompe) pour ne pas se battre avec la sortie d'arme.
	function Extra.playBolt(force, noShell)
		local CK = cfg.Equip.Cock
		if not CK then return end
		-- 🆕 « force » = chambrage après un chargeur vidé : le verrou se
		-- manœuvre même sur une arme qui n'a pas AfterShot.
		if not force and not CK.AfterShot then return end
		if Extra.cocking or IsShooting or Pumping then return end
		if Reloading and not force then return end
		if not MyHumanoid or MyHumanoid.Health <= 0 then return end
		Extra.cocking = true
		Extra.chamberAimAt = nil
		local id     = CFrame.new()
		local grab   = CK.LeftGrab    or (CFrame.new(0.20, -0.10, 0.32) * CFrame.Angles(math.rad(14), math.rad(-10), math.rad(-18)))
		local back   = CK.PullBack    or (grab * CFrame.new(0, 0, 0.30))
		local guide  = CK.RightGuide  or id
		local settle = CK.RightSettle or id
		local T = CK.AfterShotTime or CK.Time or 0.45
		Extra.chamberAimAt = force and math.min(Extra.reloadAimAt or math.huge, os.clock() + T - Extra.aimLead(T)) or nil
		-- un segment qui s'interrompt proprement si le joueur lance un reload
		local function seg(d, fr, tr, fl, tl)
			if Reloading then return false end
			lerpReload(d, fr, tr, fl, tl)
			return not Reloading
		end
		Extra.playGunTrack(CK.GunTrack, T)   -- 🔫
		-- 🆕 ANIMATION DE L'ANIM STUDIO (les deux bras + tes douilles)
		if type(CK.Keyframes) == "table" and #CK.Keyframes >= 2 then
			Extra.playSoundTrack(CK.SoundTrack, T)
			if not noShell or Extra.shellDue then
				Extra.shellDue = false
				Extra.playShellTrack(CK.ShellTrack, T)
			end
			task.spawn(Extra.playPartTrack, CK.PartKeys, T)
			task.spawn(Extra.playMagTrack, CK.MagTrack, T)
			Extra.playPose(CK.Keyframes, T, force)
			if not Reloading then ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new() end
			Extra.cocking = false
			return
		end
		if CK.Sound then Receiver:FireServer("PlaySound", CK.Sound) end
		if seg(T * 0.28, id, guide, id, grab)                        -- la main monte au levier
			and seg(T * 0.22, guide, guide, grab, back) then         -- on tire : la culasse recule
			-- 🆕 LA DOUILLE SORT ICI, pas au coup de feu
			if (not noShell or Extra.shellDue) and cfg.FX.ShellOnCock ~= false then
				Extra.shellDue = false
				local vmH = viewmodel and viewmodel:FindFirstChild("Handle")
				for _ = 1, cfg.FX.ShellsPerShot do
					SpawnLocalShell((vmH and vmH.CFrame) or Handle.CFrame)
				end
			end
			if CK.SoundRelease then Receiver:FireServer("PlaySound", CK.SoundRelease) end
			if seg(T * 0.12, guide, guide, back, grab) then           -- ça claque en avant
				if seg(T * 0.24, guide, settle, grab, id) then        -- la main redescend
					seg(T * 0.14, settle, id, id, id)                 -- le bras droit se repose
				end
			end
		end
		if not Reloading then ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new() end
		Extra.cocking = false
	end
	function Extra.scheduleBolt()
		local CK = cfg.Equip.Cock
		if not CK or not CK.AfterShot then return end
		Extra.boltToken = (Extra.boltToken or 0) + 1
		local my = Extra.boltToken
		task.delay(CK.AfterShotDelay or 0.16, function()
			if my ~= Extra.boltToken then return end   -- un nouveau tir a relancé le timer
			if Reloading or IsShooting or AmmoInClip <= 0 then return end
			if not MyHumanoid or MyHumanoid.Health <= 0 then return end
			task.spawn(Extra.playBolt)
		end)
	end
	-- ========================================================
	-- VIEWMODEL
	-- ========================================================
	local function SetupVMFlash(flash)
		-- échelle réduite en 1re personne (confort) — réglable dans WeaponVFX.Config
		WeaponVFX.SetupMuzzle(flash, WeaponVFX.Config.MuzzleFPScale, cfg.FX.ViewmodelFlash)
	end
	local function EmitViewmodelFlash(withSmoke)
		if not vmFlash then return end
		WeaponVFX.EmitMuzzle(vmFlash, withSmoke and WeaponVFX.Config.MuzzleFPSmoke)
	end
	local function DestroyModel()
		if viewmodel then viewmodel:Destroy(); viewmodel=nil end
		Extra.vmParts = nil
		Extra.vmHandleRel = nil
		vmRoot,vmRightWeld,vmLeftWeld,vmFlash,vmAimPointLocal,vmFlashLocal = nil,nil,nil,nil,nil,nil
	end
	local function BuildModel()
		if not MyCharacter or not RightArmBaseC1 or not LeftArmBaseC1 then return end
		local realRight = MyCharacter:FindFirstChild("Right Arm")
		local realLeft  = MyCharacter:FindFirstChild("Left Arm")
		if not realRight or not realLeft then return end
		local grip = realRight:FindFirstChild("RightGrip")
		-- l'arme doit être réellement en main (sinon position de référence erronée)
		if (Handle.Position - realRight.Position).Magnitude > 8 then return end
		DestroyModel()
		viewmodel = Instance.new("Model"); viewmodel.Name = "WeaponViewmodel"
		vmRoot = Instance.new("Part"); vmRoot.Name="Root"; vmRoot.Size=Vector3.new(2,2,1)
		vmRoot.Transparency=1; vmRoot.CanCollide=false; vmRoot.CanQuery=false
		vmRoot.Anchored=true; vmRoot.Massless=true; vmRoot.Parent=viewmodel
		viewmodel.PrimaryPart=vmRoot
		local function cloneArm(real, baseC1, nm)
			local arm = real:Clone(); arm.Name = nm
			for _, d in ipairs(arm:GetDescendants()) do if d:IsA("JointInstance") then d:Destroy() end end
			arm.Anchored=false; arm.CanCollide=false; arm.CanQuery=false
			arm.Massless=true; arm.CastShadow=false
			local as = cfg.Viewmodel.ArmScale
			if as then arm.Size = Vector3.new(
				math.max(0.05, arm.Size.X * as.X), arm.Size.Y * as.Y, math.max(0.05, arm.Size.Z * as.Z)) end
			arm.Parent=viewmodel
			local w=Instance.new("Weld"); w.Part0=vmRoot; w.Part1=arm; w.C1=baseC1; w.Parent=vmRoot
			return arm, w
		end
		local rightArm; rightArm, vmRightWeld = cloneArm(realRight, RightArmBaseC1, "Right Arm")
		local _;        _,        vmLeftWeld  = cloneArm(realLeft,  LeftArmBaseC1,  "Left Arm")
		vmRightBaseC1, vmLeftBaseC1 = RightArmBaseC1, LeftArmBaseC1
		-- 🩹 on retient la base AVEC LAQUELLE ce viewmodel a été construit : la
		-- prise de l'arme est un instantané, et AnimLive change la pose de repos
		-- 0.1 s après l'équipe. Sans ça, la 1re personne garde l'ancienne prise
		-- pendant que la 3e suit la nouvelle.
		Extra.vmBuiltR, Extra.vmBuiltL = RightArmBaseC1, LeftArmBaseC1
		-- On clone le TOOL ENTIER d'un coup (pas part par part). Raison : certaines
		-- armes (autopistol) ont des welds qui relient leurs parts ENTRE ELLES, pas
		-- seulement au Handle. En clonant part par part, ces welds gardent une réf vers
		-- les ORIGINAUX → la passe finale les coupe → l'arme tombe en morceaux en 1re
		-- personne. En clonant tout le Tool, Roblox remappe Part0/Part1 vers les clones
		-- → tout reste solidaire.
		local toolClone = tool:Clone()
		local handleClone = toolClone:FindFirstChild("Handle")
		if not handleClone then toolClone:Destroy(); DestroyModel(); return end
		-- vire scripts / remotes / UI clonés ; GARDE la géométrie + les welds
		for _, d in ipairs(toolClone:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("RemoteEvent")
				or d:IsA("RemoteFunction") or d:IsA("ScreenGui") then d:Destroy() end
		end
		for _, d in ipairs(toolClone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored=false; d.CanCollide=false; d.CanQuery=false; d.Massless=true; d.CastShadow=false
			end
		end
		handleClone.Anchored=false; handleClone.CanCollide=false; handleClone.CanQuery=false; handleClone.Massless=true
		-- reparent géométrie + welds clonés dans le viewmodel (welds conservés → parts
		-- reliées). Les welds "en vrac" enfants directs du Tool sont rattachés au Handle.
		for _, child in ipairs(toolClone:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
				child.Parent = viewmodel
			elseif child:IsA("JointInstance") then
				child.Parent = handleClone
			end
		end
		if handleClone.Parent ~= viewmodel then handleClone.Parent = viewmodel end
		toolClone:Destroy()
		-- weld Handle cloné → bras droit (snapshot live de la position réelle en main)
		local gw=Instance.new("Weld"); gw.Part0=rightArm; gw.Part1=handleClone
		local gwC0 = realRight.CFrame:ToObjectSpace(Handle.CFrame)
		-- 🆕 LES BRAS DU VIEWMODEL SONT MIS À L'ÉCHELLE (Viewmodel.ArmScale).
		-- La prise est exprimée depuis le CENTRE du bras : sur un bras plus fin
		-- et plus long, un décalage brut ne tombe plus au même endroit du bras.
		-- On met donc la POSITION de la prise à la même échelle que le bras, ce
		-- qui conserve sa position RELATIVE : si en 3e personne l'arme est aux
		-- 3/4 du bras, elle y est aussi sur le viewmodel.
		-- La rotation, elle, ne se met pas à l'échelle : on la garde telle quelle.
		do
			local asc = cfg.Viewmodel.ArmScale
			if asc then
				local p = gwC0.Position
				gwC0 = CFrame.new(p.X * asc.X, p.Y * asc.Y, p.Z * asc.Z) * (gwC0 - p)
			end
		end
		local gwC1 = CFrame.new()
		gw.C0 = gwC0; gw.C1 = gwC1
		gw.Parent=rightArm
		-- 🔫 on garde de quoi animer l'arme elle-même (piste ARME de l'éditeur)
		Extra.gunWeld = gw; Extra.gunBaseC0 = gwC0; Extra.gunGrabL = nil
		vmBuiltWithGrip = (grip ~= nil)
		-- filet de sécurité : une part SANS aucun weld la reliant à l'assemblage
		-- (ex. part jadis ancrée) → on la soude au Handle pour qu'elle ne tombe pas.
		-- Les parts déjà tenues par leurs welds (et les bras/root) sont laissées telles quelles.
		do
			local jointed = {}
			for _, d in ipairs(viewmodel:GetDescendants()) do
				if d:IsA("JointInstance") then
					if d.Part0 then jointed[d.Part0] = true end
					if d.Part1 then jointed[d.Part1] = true end
				end
			end
			local hInv = handleClone.CFrame:Inverse()
			for _, p in ipairs(viewmodel:GetDescendants()) do
				if p:IsA("BasePart") and p ~= handleClone and not jointed[p] then
					local ow=Instance.new("Weld"); ow.Part0=handleClone; ow.Part1=p
					ow.C0 = hInv * p.CFrame   -- conserve la position actuelle (clone-time)
					ow.Parent = handleClone
				end
			end
		end
		-- retrouve le Flash cloné (FX viewmodel)
		vmFlash = viewmodel:FindFirstChild("Flash")
		if vmFlash then SetupVMFlash(vmFlash) end
		-- Offset root → Flash (et AimPoint) via les welds de base, pour amener
		-- le haut du fusil (Flash) au centre de l'écran lors de la visée.
		if cfg.ADS.Enabled then
			local handleRelRoot = RightArmBaseC1:Inverse() * gwC0 * gwC1:Inverse()
			-- 🎯 on garde le passage « repère du Handle → repère du viewmodel » :
			-- c'est lui qui permet de placer l'arme pour que le repère d'œil
			-- tombe pile sur la caméra.
			Extra.vmHandleRel = handleRelRoot
			vmFlashLocal = handleRelRoot * (Handle.CFrame:Inverse() * Flash.CFrame)
			local ap = handleClone:FindFirstChild(cfg.ADS.AimPointName)
			if ap and ap:IsA("Attachment") then
				vmAimPointLocal = handleRelRoot * ap.CFrame  -- prioritaire si présent
			end
		end
		-- 🧩 les mêmes pièces, mais sur l'arme que TU vois en 1re personne
		if next(cfg.Parts or {}) ~= nil then
			-- 📐 les décalages viennent de l'index de l'ARME RÉELLE, mesuré une
			-- fois à l'équipement, quand tout était à sa place. Le viewmodel est
			-- reconstruit à n'importe quel moment — y compris en plein
			-- rechargement, chargeur dans la main : mesurer sur ce clone-là
			-- mémorisait une place fausse, et « rendre » posait le chargeur en
			-- l'air à côté de l'arme.
			Extra.vmParts = FX2.PartsIndex(viewmodel, handleClone, cfg.Parts, Extra.parts)
			Extra.vmSync()      -- le chargeur reprend l'état qu'il avait déjà
			if Extra.perfOn and Extra.perfOwnsFX() then Extra.perfOff(viewmodel) end
		end
		local hum=Instance.new("Humanoid"); hum.EvaluateStateMachine=false; hum.Parent=viewmodel
		local shirt = MyCharacter:FindFirstChildOfClass("Shirt"); if shirt then shirt:Clone().Parent=viewmodel end
		for _, d in ipairs(viewmodel:GetDescendants()) do
			if d:IsA("JointInstance") then
				local p0in = d.Part0 and d.Part0:IsDescendantOf(viewmodel)
				local p1in = d.Part1 and d.Part1:IsDescendantOf(viewmodel)
				if not (p0in and p1in) then
					d:Destroy()   -- un seul côté (ou aucun) est dans le viewmodel → lien externe → on coupe
				end
			end
		end
		viewmodel.Parent = camera
	end
	-- cache/réaffiche TOUT le perso localement (FP mobile scriptable).
	-- On gère nous-mêmes la transparence → plus de corps invisible au retour en TP.
	local charHiddenLocal = false
	SetWholeCharacterHidden = function(hidden)
		if charHiddenLocal == hidden and hidden then return end
		charHiddenLocal = hidden
		if not MyCharacter then return end
		local t = hidden and 1 or 0
		for _, d in ipairs(MyCharacter:GetDescendants()) do
			if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = t
			end
		end
	end
	local savedEmitterTransparency = {}
	local function setRealMuzzleHidden(hidden)
		-- masque les particules de bouche du VRAI Flash pour le tireur en 1re personne
		-- (sinon il les verrait au mauvais endroit ; les autres joueurs les voient toujours)
		for _, nm in ipairs({"MFlash","MSparks","MSmoke","BarrelSmoke","MRing","MEmber"}) do
			local e = Flash:FindFirstChild(nm)
			if e and e:IsA("ParticleEmitter") then
				if hidden then
					if savedEmitterTransparency[e] == nil then savedEmitterTransparency[e] = e.Transparency end
					e.Transparency = NumberSequence.new(1)
				elseif savedEmitterTransparency[e] ~= nil then
					e.Transparency = savedEmitterTransparency[e]; savedEmitterTransparency[e] = nil
				end
			end
		end
	end
	-- ⚡ OPTIM : appelée À CHAQUE IMAGE. Avant, elle refaisait
	-- tool:GetDescendants() (une nouvelle table par image) et recréait six
	-- NumberSequence, y compris en 3e personne où rien ne change.
	--  • la liste des parts de l'arme est gardée en cache (vidée si l'arme change)
	--  • en 3e personne, on n'écrit qu'au moment où on sort de la 1re
	--  • les particules de bouche ne sont touchées qu'au changement d'état
	local function SetRealLocalHidden(hidden)
		local t = hidden and 1 or 0
		for _, nm in ipairs({"Right Arm","Left Arm"}) do
			local p = MyCharacter and MyCharacter:FindFirstChild(nm)
			if p then p.LocalTransparencyModifier = t end
		end
		if not Extra.toolParts then
			Extra.toolParts = {}
			for _, d in ipairs(tool:GetDescendants()) do
				if d:IsA("BasePart") then table.insert(Extra.toolParts, d) end
			end
		end
		if hidden or Extra.realHiddenWas ~= false then
			for _, d in ipairs(Extra.toolParts) do d.LocalTransparencyModifier = t end
		end
		Extra.realHiddenWas = hidden
		if Extra.muzzleHiddenWas ~= hidden then
			Extra.muzzleHiddenWas = hidden
			setRealMuzzleHidden(hidden)
		end
		-- RPG : le missile "chargé" disparaît quand la roquette est partie (ammo=0),
		-- réapparaît au reload. Local (LTM) → n'affecte pas les autres clients.
		if cfg.Rocket.Enabled and AmmoInClip <= 0 then
			local pm = tool:FindFirstChild(cfg.Rocket.MissileModelName)
			local rm = pm and pm:FindFirstChild(cfg.Rocket.MissileName)
			if rm then for _, d in ipairs(rm:GetDescendants()) do
					if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end end
			end
		end
	end
	tool.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then Extra.toolParts = nil; Extra.realHiddenWas = nil end
		if MyCharacter and tool.Parent == MyCharacter then Extra.ghostPart(d) end   -- 👻
	end)
	tool.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") then Extra.toolParts = nil end
	end)
	local function StartViewmodelLoop()
		if vmRenderBound then return end
		vmRenderBound = true
		RunService:BindToRenderStep(Extra.vmName, Enum.RenderPriority.Camera.Value + 2, function()
			if not MyCharacter or not MyCharacter.Parent
				or not MyHumanoid or MyHumanoid.Health <= 0 then
				if viewmodel then DestroyModel(); SetRealLocalHidden(false) end
				return
			end
			local head = MyCharacter:FindFirstChild("Head")
			local fp = head and CamToHeadDist() < cfg.Viewmodel.FirstPersonDist
			-- la visée n'existe qu'en vraie 1re personne : on l'annule si on dézoom
			if Aiming and not fp then SetAiming(false) end
			-- 🩹 la base a changé depuis la construction (pose de repos publiée,
			-- réglage du weld, republication en direct) → on reconstruit.
			if Extra.vmRebuild then
				Extra.vmRebuild = false
				if viewmodel then DestroyModel() end
			end
			if viewmodel and RightArmBaseC1 and LeftArmBaseC1
				and (Extra.vmBuiltR ~= RightArmBaseC1 or Extra.vmBuiltL ~= LeftArmBaseC1) then
				DestroyModel()
			end
			if fp and not viewmodel and RightArmBaseC1 and LeftArmBaseC1 then BuildModel() end
			local scoping = cfg.ADS.Scope and (Aiming or ScopeAlpha > 0.02)
			if fp and viewmodel and not scoping then
				if viewmodel.Parent ~= camera then viewmodel.Parent = camera end
				SetRealLocalHidden(true)
				-- RPG : missile du viewmodel masqué quand la roquette est partie
				if cfg.Rocket.Enabled then
					local vmM = viewmodel:FindFirstChild(cfg.Rocket.MissileName, true)
					if vmM then local tv = (AmmoInClip <= 0) and 1 or 0
						for _, d in ipairs(vmM:GetDescendants()) do
							if d:IsA("BasePart") then d.LocalTransparencyModifier = tv end end
					end
				end
				-- offset de PORT (hanche) — réglable en live via TuneHipX/Y/Z + TuneHipRX/RY/RZ
				local hipOff = cfg.Viewmodel.Offset
				local hx, hy, hz = tool:GetAttribute("TuneHipX"), tool:GetAttribute("TuneHipY"), tool:GetAttribute("TuneHipZ")
				local hrx, hry, hrz = tool:GetAttribute("TuneHipRX"), tool:GetAttribute("TuneHipRY"), tool:GetAttribute("TuneHipRZ")
				if hx or hy or hz or hrx or hry or hrz then
					hipOff = CFrame.new(hx or 0, hy or 0, hz or 0)
						* CFrame.Angles(math.rad(hrx or 0), math.rad(hry or 0), math.rad(hrz or 0))
				end
				-- 🆕 Idle.Root : respiration à l'arrêt (nulle dès qu'on marche ou vise)
				local hipCF = camera.CFrame * hipOff
					* CFrame.identity:Lerp(Walk.Root * (Extra.idleRoot or CFrame.new()), 1 - AimAlpha)
				if cfg.ADS.Enabled and AimAlpha > 0.001 then
					local desired
					-- tuner live : attributs de position ET de rotation sur le Tool
					local tx, ty, tz = tool:GetAttribute("TuneADSX"), tool:GetAttribute("TuneADSY"), tool:GetAttribute("TuneADSZ")
					local rx, ry, rz = tool:GetAttribute("TuneADSRX"), tool:GetAttribute("TuneADSRY"), tool:GetAttribute("TuneADSRZ")
					-- 🆕 LE PLACEMENT NORMAL D'ABORD, TOUJOURS.
					-- Avant, le moindre réglage faisait abandonner l'alignement
					-- du viseur et téléportait l'arme sur l'origine de la caméra.
					-- Maintenant le réglage est un ÉCART posé par-dessus : zéro
					-- partout = comportement identique à aujourd'hui.
					-- 🎯 REPÈRE D'ŒIL — le chemin prioritaire.
					-- On place l'arme pour que son repère tombe EXACTEMENT sur
					-- la caméra, orientation comprise. Le viseur est donc centré
					-- sur le curseur ET aligné sur l'axe de tir : la balle part
					-- pile où le viseur pointe.
					-- L'ancienne méthode ne recalait que la POSITION et gardait
					-- la rotation de la pose de hanche — laquelle dépend du weld.
					-- D'où la visée cassée dès qu'on touchait à la prise d'arme.
					local sightLoc = Extra.sightLocal(tool)
					if sightLoc and Extra.vmHandleRel then
						local back = tool:GetAttribute("SightBack")
						desired = camera.CFrame
							* CFrame.new(0, 0, -(back or 0.25))
							* (Extra.vmHandleRel * sightLoc):Inverse()
					elseif vmAimPointLocal then
						local aimAtHip = hipCF * vmAimPointLocal
						local targetPos = (camera.CFrame * CFrame.new(cfg.ADS.AimXOffset, cfg.ADS.AimYOffset, -cfg.ADS.AimDepth)).Position
						desired = hipCF + (targetPos - aimAtHip.Position)
						if cfg.ADS.AimRot then
							desired = desired * cfg.ADS.AimRot
						end
					else
						desired = camera.CFrame * cfg.ADS.VMOffset
					end
					-- déplacement : en repère CAMÉRA (droite / haut / profondeur
					-- de l'écran), donc les flèches de l'éditeur font ce qu'elles
					-- annoncent quelle que soit l'orientation de l'arme.
					if tx or ty or tz then
						desired = desired + camera.CFrame:VectorToWorldSpace(
							Vector3.new(tx or 0, ty or 0, tz or 0))
					end
					-- rotation : AUTOUR DU VISEUR. L'arme pivote sur place au
					-- lieu de partir hors de l'écran dès 2 degrés.
					if rx or ry or rz then
						local piv = (sightLoc and Extra.vmHandleRel
							and (Extra.vmHandleRel * sightLoc))
							or vmAimPointLocal or CFrame.new()
						desired = desired * piv
							* CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
							* piv:Inverse()
					end
					vmRoot.CFrame = hipCF:Lerp(desired, AimAlpha)
				else
					vmRoot.CFrame = hipCF
				end
				-- micro-animations de visée (respiration/strafe/saut/tir) — nulles hors ADS
				vmRoot.CFrame = Extra.applyAimMotion(vmRoot.CFrame)
				-- Recul de visée : translation caméra-espace (surtout arrière). Comme c'est
				-- le long de l'axe de visée, le flash reste centré à l'écran.
				if not Extra.freezeAim() and not Extra.pivotActive() and AimAlpha > 0.01 and (math.abs(AimRecoil.X)+math.abs(AimRecoil.Y)+math.abs(AimRecoil.Z)) > 1e-4 then
					local worldOff = camera.CFrame:VectorToWorldSpace(AimRecoil) * AimAlpha
					vmRoot.CFrame = vmRoot.CFrame + worldOff
				end
				vmRoot.CFrame = Extra.wallPose(vmRoot.CFrame)   -- [Combat C6b] arme contre un mur
				-- pas de pose de bras additionnelle (l'arme est positionnée directement)
				local aimCF = CFrame.new()
				local lockedMotion = Extra.freezeAim() or Extra.pivotActive()
				local swReduce2 = (not lockedMotion and Extra.aimSway()) and cfg.ADS.SwayReduce or 1
				local swayUse = CFrame.new():Lerp(SwayOffset, 1 - swReduce2 * AimAlpha)
				-- 🆕 zéro inclinaison en visée (même correctif que la boucle Feel)
				if Extra.noMoveTilt() and AimAlpha > 0.001 then
					local sp2 = swayUse.Position
					swayUse = CFrame.new(sp2) * CFrame.identity:Lerp(swayUse - sp2, 1 - AimAlpha)
				end
				-- en visée, on retire le recul qui déplacerait l'arme (RecoilScale=0 → identité)
				local recoilFactor = 1 - AimAlpha * (1 - (lockedMotion and 0 or cfg.ADS.RecoilScale))
				local recoilUse = CFrame.new():Lerp(RecoilOffset, recoilFactor)
				local mAlpha2 = WeaponSharedState.GetSprintAlpha()
				-- 🆕 MÊME PRIORITÉ QU'EN 3e PERSONNE. Extra.animPrio monte pendant
				-- un rechargement / armement / pompe / inspection / sortie d'arme,
				-- et la pose de sprint s'efface dans les deux vues au lieu d'une.
				mAlpha2 = mAlpha2 * (1 - (Extra.animPrio or 0)) * (1 - AimAlpha)
				local mPoseL2, mPoseR2 = WeaponSharedState.GetWeaponPose()
				mPoseR2 = Extra.gkSprint(mPoseR2)   -- [GunKit P17c]
				-- 🆕 en visée, les offsets de bras (saut / sortie d'arme) sont fondus :
				-- ils décalaient le VISEUR du centre alors que la balle part du centre.
				local armFade = 1 - AimAlpha
				local jumpR2  = CFrame.identity:Lerp(JumpOffsetR, armFade)
				local jumpL2  = CFrame.identity:Lerp(JumpOffsetL, armFade)
				local equipR2 = CFrame.identity:Lerp(EquipOffsetR, armFade)
				local equipL2 = CFrame.identity:Lerp(EquipOffsetL, armFade)
				if vmRightWeld then
					local gunR = vmRightBaseC1 * aimCF * swayUse * ReloadOffsetR * equipR2 * Extra.gkArm("R") * recoilUse   -- [GunKit P16d]
						* CFrame.identity:Lerp(Extra.mvOf(vmRightWeld.Part0, "R"), lockedMotion and armFade or 1)
					vmRightWeld.C1 = (mAlpha2 > 0.001) and gunR:Lerp(mPoseR2, mAlpha2) or gunR
				end
				if vmLeftWeld then
					local gunL = vmLeftBaseC1 * aimCF * swayUse * ReloadOffsetL * equipL2 * Extra.gkArm("L") * recoilUse   -- [GunKit P16e]
						* CFrame.identity:Lerp(Extra.mvOf(vmLeftWeld.Part0, "L"), lockedMotion and armFade or 1)
					vmLeftWeld.C1 = (mAlpha2 > 0.001) and gunL:Lerp(mPoseL2, mAlpha2) or gunL
				end
				-- [GunKit P9] pose de glissade de l'arme (attributs SlidePoseR*/L* du Tool), fondue en entrée/sortie
				do
					local now = os.clock()
					local dtp = math.clamp(now - (Extra.slidePoseClock or now), 0, 0.1)
					Extra.slidePoseClock = now
					local want = (MyCharacter and MyCharacter:GetAttribute("WeaponSliding") == true
						and tool:GetAttribute("SlidePoseRX") ~= nil) and 1 or 0
					Extra.slidePoseW = (Extra.slidePoseW or 0) + (want - (Extra.slidePoseW or 0)) * math.clamp(dtp * 12, 0, 1)
					local w = Extra.slidePoseW * (1 - AimAlpha) * (1 - (Extra.animPrio or 0))
					if w > 0.001 then
						local function pose(p)
							return CFrame.new(tool:GetAttribute(p .. "X") or 0, tool:GetAttribute(p .. "Y") or 0,
								tool:GetAttribute(p .. "Z") or 0) * CFrame.Angles(math.rad(tool:GetAttribute(p .. "RX") or 0),
								math.rad(tool:GetAttribute(p .. "RY") or 0), math.rad(tool:GetAttribute(p .. "RZ") or 0))
						end
						if vmRightWeld then vmRightWeld.C1 = vmRightWeld.C1:Lerp(pose("SlidePoseR"), w) end
						if vmLeftWeld then vmLeftWeld.C1 = vmLeftWeld.C1:Lerp(pose("SlidePoseL"), w) end
					end
				end
				Extra.stabilizeAnimatedGrip()
				Extra.applySlideLean()
			elseif scoping then
				-- lunette : on cache le gun + les bras, l'overlay scope prend le relais
				SetRealLocalHidden(true)
				if viewmodel and viewmodel.Parent ~= nil then viewmodel.Parent = nil end
			else
				SetRealLocalHidden(false)
				if viewmodel and viewmodel.Parent ~= nil then viewmodel.Parent = nil end
			end
		end)
	end
	local function StopViewmodel()
		if vmRenderBound then RunService:UnbindFromRenderStep(Extra.vmName); vmRenderBound=false end
		DestroyModel(); SetRealLocalHidden(false)
	end
	-- ========================================================
	-- ADS
	-- ========================================================
	SetAiming = function(on)
		if on and Extra.aimBusy() then return end
		if on and (not MyHumanoid or MyHumanoid.Health <= 0 or tool.Parent ~= MyCharacter) then return end
		if not cfg.ADS.Enabled then return end
		-- no-op si déjà dans l'état demandé : évite que le RELÂCHÉ de clic droit en
		-- shift-lock (où l'entrée en visée a été bloquée → Aiming jamais passé à true)
		-- exécute la branche scope et délock le curseur. Aiming==false → on sort.
		if on == Aiming then return end
		-- La visée n'existe qu'en VRAIE première personne (caméra proche de la tête)
		if on and not IsActuallyFirstPerson() then return end
		-- jamais de visée en mode shift-lock (ThirdPersonLock) : la caméra ne suivrait
		-- pas, et le scope est conçu pour la 1re personne uniquement.
		if on and WeaponSharedState.IsThirdPersonLock() then return end
		if on and WeaponSharedState.AreActionsBlocked() then return end
		WeaponSharedState.SetAiming(on)   -- pause le sprint pendant la visée, reprise au relâché
		Aiming = on
		Extra.refreshMobileAim()
		if not IsMobile then
			if cfg.ADS.Scope then
				-- lunette : on regarde dedans → souris au centre, curseur masqué
				if on then
					UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
					UserInputService.MouseIconEnabled = false
				else
					UserInputService.MouseIconEnabled = true
					-- en VRAIE 1re personne l'engine maintient LockCenter de toute
					-- façon : forcer Default 1 frame → re-lock → delta parasite →
					-- saut. On ne repasse en Default que HORS 1re personne réelle.
					if not IsActuallyFirstPerson() then
						UserInputService.MouseBehavior = Enum.MouseBehavior.Default
					end
				end
			end
			-- (hors lunette : on GARDE le curseur, aucun verrouillage)
			-- sensibilité de visée : option joueur (%) sinon valeur de l'arme
			local aimSens = GetSetting("SettingAimSensitivity", nil)
			local sensScale = aimSens and math.clamp(aimSens/100, 0.1, 1) or cfg.ADS.SensitivityScale
			UserInputService.MouseDeltaSensitivity = on and sensScale or RestingMouseDelta()
		end
		if cfg.ADS.Scope and on then
			if not ScopeGui then CreateScope() end
			LayoutScope()
		end
	end
	-- ========================================================
	-- CIBLE DE TIR
	-- ========================================================
	local function getFireTarget()
		-- centre de l'écran en TP, mobile, ou lunette ; sinon on suit le curseur
		local centered = WeaponSharedState.IsThirdPersonLock() or IsMobile or CI.IsGamepad()   -- [Combat C2b]
			or Aiming
		if centered or not MyMouse then
			local cf = camera.CFrame
			local rp = RaycastParams.new(); rp.FilterType=Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances={MyCharacter, viewmodel}
			local res = workspace:Raycast(cf.Position, cf.LookVector*cfg.Range, rp)
			return res and res.Position or (cf.Position + cf.LookVector*cfg.Range)
		end
		return MyMouse.Hit.p
	end
	-- ========================================================
	-- TIR
	-- ========================================================
	-- origine + direction depuis le VISEUR (pas le canon) → anti-parallaxe
	local function getAimRay()
		local centered = WeaponSharedState.IsThirdPersonLock() or IsMobile or CI.IsGamepad()   -- [Combat C2c]
			or Aiming
		if centered or not MyMouse then
			local cf = camera.CFrame
			return cf.Position, cf.LookVector
		end
		local ur = camera:ScreenPointToRay(MyMouse.X, MyMouse.Y)
		return ur.Origin, ur.Direction.Unit
	end
	-- ════════════════════════════════════════════════════════
	-- LANCE-ROQUETTE (projectile + explosion + dégâts de zone)
	-- ════════════════════════════════════════════════════════
	local function buildRocketRelay()
		local R = cfg.Rocket
		return {
			Speed=R.Speed, Gravity=R.Gravity, MaxLife=R.MaxLife, Range=cfg.Range, ArmTime=R.ArmTime,
			Orient=R.MissileOrient or CFrame.new(),
			MissileModelName=R.MissileModelName, MissileName=R.MissileName, BoosterName=R.BoosterName,
			BC1=R.Booster.Color1, BC2=R.Booster.Color2, BSize=R.Booster.Size,
			BLC=R.Booster.LightColor, BLB=R.Booster.LightBrightness, BLR=R.Booster.LightRange,
			EColor=R.Explosion.Color, ESize=R.Explosion.Size, ESound=R.Explosion.Sound,
			EShake=R.Explosion.Shake, ERadius=R.Explosion.Radius,
		}
	end
	local function getRocketTemplate()
		local pm = tool:FindFirstChild(cfg.Rocket.MissileModelName)
		return pm and pm:FindFirstChild(cfg.Rocket.MissileName)
	end
	-- dégâts de zone à l'impact (authoritative = tireur uniquement)
	local function applyRocketAoE(center)
		local E = cfg.Rocket.Explosion
		if not MyPlayer then return end
		local DEBUG = true   -- ⬅ mets false une fois que ça marche
		-- cibles : joueurs + bots d'arène
		local targets = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then targets[#targets+1] = { char = pl.Character, pl = pl } end
		end
		for _, bot in ipairs(game:GetService("CollectionService"):GetTagged("ArenaBot")) do
			targets[#targets+1] = { char = bot }
		end
		local ignore = { camera, tool }
		if viewmodel then table.insert(ignore, viewmodel) end
		for _, t in ipairs(targets) do table.insert(ignore, t.char) end
		local los = RaycastParams.new()
		los.FilterType = Enum.RaycastFilterType.Exclude
		los.FilterDescendantsInstances = ignore
		los.RespectCanCollide = true   -- missile / boule d'explosion / FX ne bloquent plus
		-- visible si AU MOINS une partie du corps est à découvert
		local function seen(char)
			if not E.RequireLineOfSight then return true end
			local blocker
			for _, nm in ipairs({ "HumanoidRootPart", "Head", "UpperTorso", "Torso" }) do
				local p = char:FindFirstChild(nm)
				if p and p:IsA("BasePart") then
					local d = p.Position - center
					if d.Magnitude < 0.6 then return true end
					local o = center + d.Unit * 0.5   -- décolle l'origine de la surface d'impact
					local hit = workspace:Raycast(o, p.Position - o, los)
					if not hit or hit.Instance.Transparency >= 1 then return true end
					blocker = hit.Instance
				end
			end
			if DEBUG then warn("[RPG] " .. char.Name .. " bloqué par", blocker and blocker:GetFullName()) end
			return false
		end
		for _, t in ipairs(targets) do
			local char, pl = t.char, t.pl
			local hum = char:FindFirstChildOfClass("Humanoid")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hum.Health > 0 then
				local isSelf = (pl == MyPlayer)
				local d = (hrp.Position - center).Magnitude
				if d <= E.Radius and seen(char) then
					local f = 1 - (d / E.Radius)
					if (not isSelf) or E.SelfDamage then
						local enemy = isSelf or not pl or MyPlayer.Neutral or pl.Neutral
							or pl.TeamColor ~= MyPlayer.TeamColor
						if enemy then
							local dmg = math.floor(E.MinDamage + (E.MaxDamage - E.MinDamage) * f + 0.5)
							if dmg > 0 then
								Receiver:FireServer("Damage", hum, dmg, MyPlayer)
								if DEBUG then print("[RPG] Damage envoyé →", char.Name, dmg) end
								if not char:GetAttribute("SpawnShielded") then
									ShowDamagePopup(hrp, dmg)
								end
							end
						end
					end
					if E.Knockback and E.Knockback > 0 then
						local dirAway = hrp.Position - center
						if dirAway.Magnitude < 0.1 then dirAway = Vector3.new(0,1,0) end
						local push = (dirAway.Unit + Vector3.new(0, E.KnockUp or 0, 0)).Unit
						local power = E.Knockback * (0.4 + 0.6*f)
						if isSelf then
							hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + push * power
						else
							Receiver:FireServer("Knockback", hrp, push * power)
						end
					end
				elseif DEBUG and d <= E.Radius * 2 and not isSelf then
					warn(("[RPG] %s hors rayon : %.1f studs (rayon %d)"):format(char.Name, d, E.Radius))
				end
			end
		end
	end
	local function spawnRocket(startCF, dir, authoritative)
		local R = cfg.Rocket
		local template = getRocketTemplate(); if not template then return end
		RocketFX.Fire({
			template=template, startCF=startCF, dir=dir,
			speed=R.Speed, gravity=R.Gravity, maxLife=R.MaxLife, maxRange=cfg.Range, armTime=R.ArmTime,
			boosterName=R.BoosterName, orient=R.MissileOrient or CFrame.new(),
			booster=R.Booster, explosion=R.Explosion,
			ignore={ MyCharacter, viewmodel, tool },
			onImpact = authoritative and function(pos) applyRocketAoE(pos) end or nil,
		})
	end
	local function fireRocketVolley()
		ConsecutiveShots += 1
		Receiver:FireServer("PlaySound", cfg.Sounds.Fire)
		Receiver:FireServer("Flash", true, ConsecutiveShots)   -- gros flash de bouche (autres joueurs)
		AddRecoilKick()
		Extra.recordVisualShot()
		if Aiming and not Extra.freezeAim() then
			local r = cfg.ADS.Recoil
			AimRecoil = AimRecoil + Vector3.new((math.random()-0.5)*2*r.Side, r.Up, r.Back)
			AimRecoil = Vector3.new(
				math.clamp(AimRecoil.X,-r.Max,r.Max), math.clamp(AimRecoil.Y,-r.Max,r.Max), math.clamp(AimRecoil.Z,-r.Max,r.Max))
			FireFOVOffset = math.min(3, FireFOVOffset + (cfg.FX.FireFOVKick or 0)*cfg.ADS.FireFOVScale)
		elseif not Aiming then
			FireFOVOffset = math.min(3, FireFOVOffset + (cfg.FX.FireFOVKick or 0))
		end
		EmitViewmodelFlash(true)
		local fpNow = viewmodel and viewmodel.Parent == camera and vmFlash
		local shooterMuzzle = fpNow and vmFlash.Position or Flash.Position
		local relayMuzzle   = Flash.Position
		-- 🧱 [Murs] lance-roquette rentré dans un mur : la roquette part DU MUR (côté joueur)
		do
			local wHit, wPos = Extra.muzzleBlocked(Flash.Position)
			if wHit and wPos then
				local root = MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
				local back = root and (root.Position + Vector3.new(0, 1.5, 0) - wPos) or Vector3.zero
				local p = (back.Magnitude > 1e-3) and (wPos + back.Unit * 0.4) or wPos
				if not fpNow then shooterMuzzle = p end
				relayMuzzle = p
			end
		end
		-- 🔦 la part, pas la position : la lumière et l'étoile restent sur le
		-- canon quand le lance-roquette bouge.
		SpawnLocalMuzzleLight(fpNow or Flash)
		WeaponVFX.StarFlash(fpNow or Flash, cfg.FX.ViewmodelFlash, 1)
		do
			local FV = cfg.FX.FlashVary
			-- ⚠ ici shooterMuzzle est une POSITION (Vector3), pas une part :
			-- l'éclair a besoin de la part pour rester accroché à l'arme.
			if FV and FV.Enabled then
				local vf = cfg.FX.ViewmodelFlash or {}
				FX2.Flash(fpNow or Flash, vf.Color1, vf.Color2, FV.Scale or 1)
			end
		end
		local origin, dir = getAimRay()
		local aimTarget = getFireTarget()   -- point sous le viseur → la roquette converge dessus
		local snapPos, snapF
		if not Snap.PreservesHit(origin, dir) then snapPos, snapF = Snap.GetTarget() end
		if snapPos and snapF and snapF > 0 then
			aimTarget = aimTarget:Lerp(snapPos, snapF)
		end
		local function dirFrom(p)
			local d = (aimTarget - p)
			return (d.Magnitude > 1e-3) and d.Unit or dir
		end
		local sDir = dirFrom(shooterMuzzle)
		local rDir = dirFrom(relayMuzzle)
		spawnRocket(CFrame.lookAt(shooterMuzzle, shooterMuzzle + sDir), sDir, true)   -- locale (dégâts)
		if rocketRelayData then
			Receiver:FireServer("Rocket", CFrame.lookAt(relayMuzzle, relayMuzzle + rDir), rDir, rocketRelayData)
		end
		AmmoInClip -= 1; UpdateAmmo(AmmoInClip)
		AutoshootHoldElapsed = 0
	end
	local function fireOneVolley()
		if cfg.Rocket.Enabled then fireRocketVolley(); return end
		ConsecutiveShots += 1
		Extra.volleyId = (Extra.volleyId or 0) + 1   -- [Combat C5] n° de rafale
		-- 🆕 style de tracer : "Custom" → choix du joueur ; sinon forcé par l'arme
		if TT.Style == "Custom" then
			tracerStyle.Style = GetSetting("SettingTracerRivals", false) and "Rivals" or "Classic"
		else
			tracerStyle.Style = TT.Style
		end
		local smokeOn = (cfg.FX.ViewmodelFlash.SmokeAfter > 0) and (ConsecutiveShots >= cfg.FX.ViewmodelFlash.SmokeAfter)
		-- dispersion : nouveau système (bloom) OU ancien (alternance), selon l'interrupteur
		if Extra.dynOn then
			local DS = cfg.DynamicSpread
			Extra.bloom = math.min(DS.Max or 0.06, Extra.bloom + (DS.PerShot or 0))
			Extra.lastShotAt = os.clock()
		elseif Spread and not DecreasedAimLastShot then
			Spread = math.min(cfg.MaxSpread, Spread + cfg.AimInaccuracyStepAmount); UpdateCrosshair(Spread)
		end
		DecreasedAimLastShot = not DecreasedAimLastShot
		Receiver:FireServer("PlaySound", cfg.Sounds.Fire)
		Receiver:FireServer("Flash", true, ConsecutiveShots)
		AddRecoilKick()
		Extra.recordVisualShot()
		if Aiming and not Extra.freezeAim() then
			Aim.fireImp = 1   -- déclenche le recul arrière de l'anim (FirePos)
			-- recul de visée : UNIQUEMENT dans l'axe de visée
			local r = cfg.ADS.Recoil
			local axial = cfg.ADS.RecoilAxisOnly
			AimRecoil = AimRecoil + Vector3.new(
				axial and 0 or (math.random()-0.5)*2*r.Side,
				axial and 0 or r.Up,
				r.Back * (IsMobile and (cfg.Feel.MobileRecoilScale or 1) or 1))                          -- +Z = vers l'arrière (vers toi)
			AimRecoil = Vector3.new(
				axial and 0 or math.clamp(AimRecoil.X, -r.Max, r.Max),
				axial and 0 or math.clamp(AimRecoil.Y, -r.Max, r.Max),
				math.clamp(AimRecoil.Z, -r.Max, r.Max))
		end
		-- [GunKit P11] flash de l'arme (Blender) si GunKitMuzzle, sinon ton flash habituel
		local gkMuzzle = tool:GetAttribute("GunKitMuzzle") == true
		-- [Combat M1] flash Blender de la M4A1 (MuzzleFX) sur toutes les armes : remplace ton flash par défaut
		if Extra.mz == nil then
			local mzm = script.Parent:FindFirstChild("MuzzleFX")
			local okR, vR = false, nil
			if mzm then okR, vR = pcall(require, mzm) end
			Extra.mz = (okR and type(vR) == "table") and vR or false
		end
		local mzOn = Extra.mz and Extra.mz.On() and Extra.mz.ClassOf(tool, cfg) ~= "None"
		if not gkMuzzle and not mzOn then EmitViewmodelFlash(smokeOn) end
		-- Muzzle VISUEL local = le Flash du VIEWMODEL en 1re personne (donc les
		-- balles/douilles/lumière sortent de l'arme que tu vois et SUIVENT sa
		-- position), sinon le vrai Flash (3e personne sur sa propre arme).
		local fpNow = viewmodel and viewmodel.Parent == camera and vmFlash
		local visualMuzzlePos = fpNow and vmFlash.Position or Flash.Position
		local visualMuzzleCF  = fpNow and vmFlash.CFrame  or Handle.CFrame
		-- douilles : en 1re personne, on éjecte depuis le HANDLE du viewmodel (même
		-- orientation que le vrai gun) → sortie côté DROIT, comme en 3e personne
		local vmHandle = fpNow and viewmodel and viewmodel:FindFirstChild("Handle")
		local shellCF = (vmHandle and vmHandle.CFrame) or Handle.CFrame
		-- 🆕 sur une arme à pompe OU à verrou, la douille n'attend pas le tir :
		-- elle attend le geste qui ouvre la culasse. On note qu'elle est DUE,
		-- et c'est la pompe (ou le verrou) qui la sortira.
		local ckNow = cfg.Equip.Cock
		if (ckNow and ckNow.AfterShot and cfg.FX.ShellOnCock ~= false)
			or (cfg.Reload.PumpAfterShot and cfg.FX.ShellOnPump ~= false) then
			Extra.shellDue = true
		else
			for _ = 1, cfg.FX.ShellsPerShot do SpawnLocalShell(shellCF) end
		end
		SpawnLocalMuzzleLight(fpNow or Flash)
		-- [GunKit P11b] flash de l'arme : module MuzzleFlash du GunKit (repli : ton StarFlash)
		local gkDone = false
		if gkMuzzle then
			-- [GunKit P12] flash GunKit : en cas d'erreur, message dans l'Output (une fois) puis ton flash
			local okF, errF = pcall(function()
				if not Extra.gkMuzzleMod then
					local gk = game:GetService("ReplicatedStorage"):FindFirstChild("GunKit")
					local g = gk and gk.Guns:FindFirstChild(tool:GetAttribute("Gun") or tool.Name)
					Extra.gkMuzzleMod = require(g:FindFirstChild("MuzzleFlash") or gk.Core.MuzzleFlash)
				end
				Extra.gkMuzzleMod.Emit(fpNow or Flash, fpNow and true or false, smokeOn, cfg)
			end)
			gkDone = okF
			if not okF and not Extra.gkMuzzleWarned then
				Extra.gkMuzzleWarned = true
				warn("[GunKit] muzzle flash : " .. tostring(errF))
			end
		end
		-- [Combat M2] MuzzleFX : le flash de la M4A1 (arme GunKit : rien, son flash est joué par le GunKit)
		if mzOn then
			local okM, errM = pcall(Extra.mz.Shot, tool, fpNow or Flash, fpNow and true or false, cfg, MyPlayer)
			if okM and not gkMuzzle then gkDone = true end
			if not okM and not Extra.mzWarned then Extra.mzWarned = true; warn("[MuzzleFX] " .. tostring(errM)) end
		end
		if not gkDone then
			WeaponVFX.StarFlash(fpNow or Flash, cfg.FX.ViewmodelFlash, fpNow and WeaponVFX.Config.MuzzleFPScale or 1)
		end
		-- 🆕 ÉCLAIR VARIÉ. Des pointes tirées au hasard — nombre, angles,
		-- longueurs, épaisseurs — par-dessus ton flash habituel. Au troisième
		-- coup, l'œil ne reconnaît plus le même dessin.
		do
			-- [GunKit P12b] pas d'éclairs par-dessus le flash de l'arme
			local FV = (not gkDone) and cfg.FX.FlashVary or nil
			if FV and FV.Enabled then
				-- on passe la PART, pas un CFrame : l'éclair reste accroché au
				-- canon et suit l'arme image par image.
				local vf = cfg.FX.ViewmodelFlash or {}
				FX2.Flash(fpNow or Flash, vf.Color1, vf.Color2,
					(fpNow and (FV.ScaleFP or 0.5) or (FV.Scale or 1)))
			end
		end
		local detectOrigin, detectDir = getAimRay()
		-- SNAP ASSIST : correction PARTIELLE selon la distance (facteur 0..1).
		-- À 1 → balle pile sur l'ennemi ; à 0.5 → à mi-chemin ; de loin → rien.
		local snapPos, snapF
		if not Snap.PreservesHit(detectOrigin, detectDir) then snapPos, snapF = Snap.GetTarget() end
		if snapPos and snapF and snapF > 0 then
			local sd = snapPos - detectOrigin
			if sd.Magnitude > 1e-3 then
				detectDir = (detectDir * (1 - snapF) + sd.Unit * snapF).Unit
			end
		end
		-- (le Spread par pellet s'applique toujours APRÈS → shotgun reste cohérent)
		local damaged = false
		local headshotThisVolley = false   -- 🆕
		local impactBudget = (cfg.FX.Impact and cfg.FX.Impact.MaxPerVolley) or 0
		local tracerEnds = {}   -- on collecte les bouts pour UN seul relais réseau
	
		-- 🆕 BALLES TRAÇANTES : 1 tir sur N. Décidé une fois par TIR (les 12 pellets
		-- d'un shotgun sont donc tracés ensemble, ou pas du tout).
		Extra.tracerShots += 1
		-- 🔁 UNE TRAÎNÉE PAR TIR, comme avant.
		-- (Pour revenir un jour au 1-sur-N, remets :
		--   local everyN = math.max(1, TT.EveryN or 1)
		--   local showTracer = ((Extra.tracerShots - 1) % everyN) == 0 )
		local showTracer = true
		if (TT.LowAmmoAt or 0) > 0 and AmmoInClip <= TT.LowAmmoAt then
			showTracer = true
			tracerStyle.Color = TT.LowAmmoColor or TT.Color
			tracerStyle.CoreColor = TT.LowAmmoColor or TT.CoreColor
		else
			tracerStyle.Color = TT.Color
			tracerStyle.CoreColor = TT.CoreColor
		end
		for _ = 1, cfg.Pellets do
			local dir = detectDir
			if Spread and Spread > 0 then
				dir = CFrame.Angles(
					(0.5-math.random())*2*Spread, (0.5-math.random())*2*Spread, (0.5-math.random())*2*Spread) * dir
			end
			-- ── TIR EN 2 ÉTAPES (anti tir à travers les murs) ──
			-- 1) rayon CAMÉRA/CURSEUR : trouve le point visé à l'écran
			local camHit, camHitPos = RayCast(detectOrigin, dir, cfg.Range)
			local targetPoint = camHitPos or (detectOrigin + dir * cfg.Range)
			-- 2) rayon CANON (Flash) → point visé : un mur entre le gun et le
			-- point ARRÊTE la balle dessus (le tracer s'arrête aussi sur le mur)
			local muzzlePos = Flash.Position
			local toTarget = targetPoint - muzzlePos
			local toDir = (toTarget.Magnitude > 1e-3) and toTarget.Unit or dir
			local hitObject, bulletPos
			-- 3) 🧱 canon passé à travers un mur : la balle s'arrête sur CE mur, mais sur sa face
			--    CÔTÉ CANON (traînée + effets là où est le canon, jamais derrière le mur)
			local wallHit, wallPos = Extra.muzzleBlocked(muzzlePos)
			local wallRes = wallHit and Extra.wallFar(wallHit, muzzlePos, wallPos)
			if wallHit then
				hitObject, bulletPos = wallHit, (wallRes and wallRes.Position) or wallPos
			elseif toTarget.Magnitude > 0.5 then
				hitObject, bulletPos = RayCast(muzzlePos, toDir, toTarget.Magnitude + 2)
			else
				hitObject, bulletPos = camHit, camHitPos
			end
			local endPos = bulletPos or targetPoint
			if showTracer then   -- la traînée part TOUJOURS du canon
				SpawnLocalTracer(visualMuzzlePos, endPos, fpNow or Flash)   -- visuel depuis l'arme vue, accroché au canon
				tracerEnds[#tracerEnds+1] = endPos                 -- relais batché après la boucle
			end
			local bullet = hitObject and CreateBullet(bulletPos)
			local hitHumanoidOrEgg = false
			if hitObject then
				local model = hitObject:FindFirstAncestorWhichIsA("Model")  -- touche aussi via accessoires
				local hum = model and model:FindFirstChildOfClass("Humanoid")
				if hum then
					hitHumanoidOrEgg = true
					local hp = Players:GetPlayerFromCharacter(hum.Parent)
					if MyPlayer.Neutral or (hp and hp.TeamColor ~= MyPlayer.TeamColor) or not hp then
						-- 🎯 HEADSHOT : la part réellement touchée décide
						local isHead = cfg.Headshot.Enabled and partIsHead(hitObject) or false
						local dmg = isHead
							and math.floor(cfg.Damage * cfg.Headshot.Multiplier + 0.5)
							or cfg.Damage
						-- [Combat C5b] le serveur revérifie le tir (compensation du ping) et calcule la zone
						Receiver:FireServer("Damage", hum, dmg, MyPlayer, tracerStyle, isHead, {
							p = hitObject, pos = bulletPos or camHitPos or endPos, o = muzzlePos,
							t = workspace:GetServerTimeNow(), b = cfg.Damage, v = Extra.volleyId,
						})
						if bullet then bullet:Destroy(); bullet=nil end
						local HVs = CS.HitValidation
						-- tout s'affiche TOUT DE SUITE ; si le serveur refuse le tir, seuls les dégâts ne sont pas infligés
						local waitConfirm = CS.Enabled ~= false and HVs and HVs.Enabled ~= false and HVs.WaitServerConfirm == true
						if not waitConfirm and CI.DisplayDamage then
							dmg = CI.DisplayDamage(cfg.Damage, hitObject, isHead, cfg.Headshot.Multiplier, tool, cfg.ZoneDamage)   -- chiffre par zone
						end
						-- 🛡 cible protégée : pas de hit marker / popup / son (l'effet
						-- de bulle arrive via le serveur) — la balle s'arrête quand même
						if not hum.Parent:GetAttribute("SpawnShielded") and not waitConfirm then
							damaged = true   -- 🔊 son de hit joué UNE fois après le tir (C.PlayHitSound)
							if isHead then headshotThisVolley = true end
							FlashEnemyHit(hum.Parent)
							local rp2 = hum.Parent:FindFirstChild("HumanoidRootPart")
							if rp2 then ShowDamagePopup(rp2, dmg, isHead) end
						end
					end
				end
				local egg = model and model:FindFirstChild("Egglon")
				if egg then
					hitHumanoidOrEgg = true
					Receiver:FireServer("Damage", egg, cfg.Damage, MyPlayer)
					if bullet then bullet:Destroy(); bullet=nil end
					damaged = true
					local rp2 = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
					if rp2 then ShowDamagePopup(rp2, cfg.Damage) end
				end
			end
			if hitObject and not hitHumanoidOrEgg and impactBudget > 0
				and not WeaponVFX.Potato("Impacts") then   -- 🥔 zéro rayon (impacts = local seulement)
				impactBudget -= 1
				local rp = RaycastParams.new(); rp.FilterType=Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances={MyCharacter, viewmodel, Handle, Flash}
				-- 🧱 canon dans un mur : l'effet se pose sur la face du mur CÔTÉ CANON
				local nres = wallRes or (wallHit and Extra.wallRay(muzzlePos, rp))
					or workspace:Raycast(muzzlePos, toDir * (toTarget.Magnitude + 2), rp)
				-- impact SEULEMENT si une vraie surface est confirmée — sinon
				-- l'effet (trou de balle inclus) apparaissait EN L'AIR au bout du rayon
				if nres then
					SpawnImpact(nres.Position, nres.Normal, nres.Material)   -- impact visible par TOI seulement (plus envoyé)
				end
			end
		end
		if WeaponVFX.TracersEnabled() and #tracerEnds > 0 then
			-- ⚡ RÉSEAU : le style (≈20 champs, couleurs comprises) n'est envoyé que
			-- s'il change, et rappelé toutes les 5 s pour les nouveaux arrivants.
			-- Les autres clients le gardent en mémoire par tireur.
			local sig = tostring(tracerStyle.Style) .. tostring(tracerStyle.Color)
				.. tostring(tracerStyle.CoreColor)
			local sendStyle = nil
			if sig ~= Extra.tracerSig or os.clock() - (Extra.tracerSigAt or 0) > 5 then
				Extra.tracerSig, Extra.tracerSigAt = sig, os.clock()
				sendStyle = tracerStyle
			end
			Receiver:FireServer("Tracer", Flash.Position, tracerEnds, sendStyle)
		end
		if damaged then
			C.PlayHitSound(headshotThisVolley)   -- 🔊 local : seul le tireur l'entend
			task.spawn(FlashHitMarkers, headshotThisVolley)
		end
		if cfg.FirePartKeys then
			task.spawn(Extra.playPartTrack, cfg.FirePartKeys, math.min(cfg.FirePartTime or 0.1, cfg.FireRate))
		end
		AmmoInClip -= 1; UpdateAmmo(AmmoInClip)
		AutoshootHoldElapsed = 0
		Extra.scheduleBolt()   -- 🆕 verrou / levier après le coup
	end
	-- 🆕 le tir continue-t-il tant qu'on maintient ?
	Extra.holdFire = function()
		if cfg.FireMode == "Auto" then return true end
		if cfg.SemiHoldFire == false then return false end
		-- pompe / verrou : le geste doit se jouer ENTRE deux coups, on garde 1 clic = 1 coup
		if cfg.Reload.PumpAfterShot then return false end
		local CK = cfg.Equip.Cock
		if CK and CK.AfterShot then return false end
		return true
	end
	OnFire = function()
		if IsShooting then return end
		if os.clock() < NextAllowedShot then return end   -- 🆕 cadence pas encore écoulée
		if Extra.cocking then return end   -- 🆕 la culasse est en train de bouger
		-- 🔫 pompe en cours (shotgun) : pas de tir tant que le geste n'est pas fini (vrai temps de recharge)
		if Pumping and cfg.Reload.PumpBlocksFire ~= false then return end
		if Extra.wallStop() then return end   -- [Combat C6c] arme relevée contre un mur
		if Extra.inspecting then           -- 🆕 tirer coupe l'inspection
			if cfg.Inspect and cfg.Inspect.BlockFire then return end
			-- l'arme revient à sa position de tir, en douceur, et le coup part
			Extra.stopInspect()
		end
		-- 🆕 pas de tir pendant la sortie d'arme (le config le promettait déjà)
		if cfg.Equip.BlockFireDuring and Equipping then return end
		if WeaponSharedState.AreActionsBlocked() then return end   -- ← ajout (si BlocksActions=true)
		WeaponSharedState.RequestCancelSprint()                    -- ← ajout (coupe le sprint)
		if not MyHumanoid or MyHumanoid.Health <= 0 then return end
		if AmmoInClip <= 0 or Reloading then
			-- 🆕 TIRER INTERROMPT LE RECHARGEMENT CARTOUCHE PAR CARTOUCHE,
			-- ET LE TIR PART SUR CE CLIC-LÀ.
			-- La cartouche en cours de chargement est ABANDONNÉE (elle n'entre
			-- pas), le geste est coupé net, les bras reviennent au repos, et on
			-- enchaîne sur le tir dans le même appel. C'est ça qui rend le
			-- fusil à pompe réactif : on n'attend jamais le geste en cours.
			if Reloading and AmmoInClip > 0 and cfg.Reload.Style == "Shell"
				and cfg.Reload.ShellCancelOnFire ~= false
				and (cfg.Reload.ShellCancelEmpty == true or not Extra.wasEmpty) then
				-- 🎟 un seul geste : on avance le jeton. Tout ce qui tournait
				-- (poses, sons en attente, douilles, chargeur, cartouche en
				-- vol) s'arrête ; rien ne reste bloqué pour la suite.
				Extra.cutTok = (Extra.cutTok or 0) + 1
				Extra.reloadTok = (Extra.reloadTok or 0) + 1
				Reloading = false
				SetReloadingTextVisible(false)
				ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new()
				-- …et on NE sort PAS : la suite de OnFire tire.
			else
				if AmmoInClip == 0 and not Reloading then task.spawn(Reload) end
				return
			end
		end
		IsShooting = true
		WeaponSharedState.SetFiring(true)   -- pause le sprint (mobile inclus) pendant la rafale
		pumpToken += 1   -- annule toute pompe en attente pendant qu'on tire
		Extra.boltToken = (Extra.boltToken or 0) + 1   -- 🆕 idem pour l'armement
		if cfg.UseRecoilAnim and RecoilTrack then RecoilTrack:Play() end
		-- 🆕 cadence à l'HORLOGE, pas au task.wait : le rythme reste exact et
		-- constant quel que soit le framerate (task.wait arrondit à la frame).
		local nextShot = os.clock()
		-- 🩹 doit-on arrêter la rafale ? Vérifié AVANT et APRÈS l'attente :
		-- avant, un clic court tirait 2 fois (le bouton était relâché pendant
		-- l'attente, mais le 2e coup partait sans revérifier).
		local function stopBurst()
			return not Extra.holdFire()
				or not (LeftButtonDown or AutoShooting)
				or AmmoInClip <= 0 or Reloading or Extra.wallStop()   -- [Combat C6d]
				or not MyHumanoid or MyHumanoid.Health <= 0
		end
		repeat
			fireOneVolley()
			NextAllowedShot = os.clock() + cfg.FireRate   -- 🆕 verrouille jusqu'au prochain tir autorisé
			if stopBurst() then break end
			nextShot += cfg.FireRate
			if nextShot < os.clock() - cfg.FireRate then nextShot = os.clock() end
			-- on sort de l'attente dès que le bouton est relâché
			repeat RunService.Heartbeat:Wait()
			until os.clock() >= nextShot or not (LeftButtonDown or AutoShooting)
			if stopBurst() then break end   -- 🩹 relâché pendant l'attente → pas de 2e coup
		until false
		Receiver:FireServer("Flash", false, ConsecutiveShots)
		ConsecutiveShots = 0
		IsShooting = false
		WeaponSharedState.SetFiring(false)
		if RecoilTrack then RecoilTrack:Stop() end
		if AmmoInClip == 0 then
			task.spawn(Reload)
		else
			Extra.schedulePump()   -- "chick-chick" ~0.7s après si des balles restent (shotgun)
		end
	end
	-- ========================================================
	-- DAMAGE POPUP
	-- ========================================================
	-- ⚡ UNE seule boucle pour tous les chiffres de dégâts (avant : une connexion RenderStepped PAR chiffre)
	--    + plafond : au-delà, le plus ancien disparaît (mobile 6, PC 14)
	ShowDamagePopup = function(rootPart, damage, isHead)
		if not rootPart or not rootPart.Parent or not MyPlayer then return end
		if not MyHumanoid or MyHumanoid.Health <= 0 then return end
		if not GetSetting("SettingDamageNumbers", true) then return end   -- option joueur
		if CI.KVPush then CI.KVPush("d", { p = rootPart, n = damage, h = isHead == true }) end   -- [Combat K2] vue du tueur
		local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return end
		if not DamagePopupContainer or not DamagePopupContainer.Parent then
			DamagePopupContainer = Instance.new("ScreenGui")
			DamagePopupContainer.Name="DamagePopupContainer"; DamagePopupContainer.ResetOnSpawn=true
			DamagePopupContainer.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; DamagePopupContainer.DisplayOrder=10
			DamagePopupContainer.Parent=pg
		end
		local cap = IsMobile and 6 or 14
		while #ActivePopups >= cap do
			local old = table.remove(ActivePopups, 1)
			if old.label then old.label:Destroy() end
		end
		local HS = cfg.Headshot
		local label=Instance.new("TextLabel"); label.Size=UDim2.new(0,160,0,70); label.AnchorPoint=Vector2.new(0.5,0.5)
		label.BackgroundTransparency=1; label.Font=Enum.Font.FredokaOne
		-- 🎯 ROUGE = HEADSHOT (et lui seul). Les gros dégâts restent blancs.
		local baseSize = isHead and HS.TextSize or 24
		label.TextSize = baseSize; label.Text = tostring(damage)
		label.TextColor3 = isHead and HS.Color or Color3.fromRGB(255,255,255)
		label.TextStrokeTransparency=0.2; label.TextStrokeColor3=Color3.fromRGB(0,0,0); label.Parent=DamagePopupContainer
		table.insert(ActivePopups, { label = label, root = rootPart, start = tick(),
			ox = math.random(-30, 30), oy = math.random(-10, 10), head = isHead, base = baseSize })
		if Extra.popConn then return end
		Extra.popConn = RunService.RenderStepped:Connect(function()
			local alive = MyHumanoid and MyHumanoid.Health > 0
			local vp = camera.ViewportSize
			local now = tick()
			for i = #ActivePopups, 1, -1 do
				local e = ActivePopups[i]
				local lbl, rp = e.label, e.root
				local el = now - e.start
				if not alive or el >= 1.2 or not lbl.Parent or not rp or not rp.Parent then
					lbl:Destroy(); table.remove(ActivePopups, i)
				else
					local t = el / 1.2
					local sp, on = camera:WorldToViewportPoint(rp.Position + Vector3.new(0, 3.5, 0))
					if on then
						lbl.Visible = true
						lbl.Position = UDim2.new(0, math.clamp(sp.X + e.ox, 50, vp.X - 50),
							0, math.clamp(sp.Y - 80 - t * 60 + e.oy, 50, vp.Y - 100))
					else
						lbl.Visible = false
					end
					local f = math.clamp(t * 1.5 - 0.2, 0, 1)
					lbl.TextTransparency = f
					lbl.TextStrokeTransparency = 0.2 + math.min(f, 0.8)
					-- petit "pop" de taille au headshot (0.12 s)
					if e.head and (HS.Pop or 0) > 0 then
						local k = 1 - math.clamp(el / 0.12, 0, 1)
						lbl.TextSize = math.floor(e.base * (1 + HS.Pop * k))
					end
				end
			end
			if #ActivePopups == 0 and Extra.popConn then Extra.popConn:Disconnect(); Extra.popConn = nil end
		end)
	end
	local function CleanupAllDamagePopups()
		if Extra.popConn then Extra.popConn:Disconnect(); Extra.popConn = nil end
		for _, p in ipairs(ActivePopups) do
			if p.label and p.label.Parent then p.label:Destroy() end
		end
		ActivePopups = {}
		if DamagePopupContainer then DamagePopupContainer:Destroy(); DamagePopupContainer=nil end
	end
	-- ========================================================
	-- RETICLE COLOR
	-- ========================================================
	local Friendly, Enemy, Neutral = Color3.new(0,1,0), Color3.new(1,0,0), Color3.new(1,1,1)
	local function SetReticleColor(color)
		if Extra.retColor == color and Extra.retGui == MobileCursorGui then return end
		Extra.retColor, Extra.retGui = color, MobileCursorGui
		if WeaponGui then
			local c = WeaponGui:FindFirstChild("Crosshair")
			if c then for _, l in pairs(c:GetChildren()) do if l:IsA("Frame") then l.BorderColor3 = color end end end
		end
		if MobileCursorGui then SetMobileCursorColor(color) end
	end
	-- ========================================================
	-- ENNEMIS : outline rouge + flash au hit + marqueur de kill
	-- ========================================================
	IsEnemyPlayer = function(pl)
		if not pl or not MyPlayer or pl == MyPlayer then return false end
		if MyPlayer.Neutral or pl.Neutral then return true end
		return pl.TeamColor ~= MyPlayer.TeamColor
	end
	UpdateEnemyHighlights = function()
		if not MyPlayer then return end
		if not GetSetting("SettingEnemyOutlines", true) then ClearEnemyHighlights(); return end
		local seen = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= MyPlayer then
				seen[pl] = true
				local char = pl.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local alive = hum and hum.Health > 0
				if char and char.Parent and alive and IsEnemyPlayer(pl) then
					local hl = EnemyHighlights[pl]
					-- SELF-HEAL : recrée si détruit, orphelin, ou perso respawn
					if not hl or not hl.Parent or hl.Adornee ~= char then
						if hl then pcall(function() hl:Destroy() end) end
						hl = Instance.new("Highlight")
						hl.Name = "EnemyOutline"
						hl.FillTransparency = 1
						hl.FillColor = Color3.fromRGB(255, 0, 0)
						hl.OutlineColor = Color3.fromRGB(255, 45, 45)
						hl.OutlineTransparency = 0
						hl.DepthMode = Enum.HighlightDepthMode.Occluded
						hl.Adornee = char
						hl.Parent = char   -- vit DANS le perso ennemi → immunisé aux
						-- resets caméra ; auto-détruit au respawn
						-- puis recréé ici au tick suivant
						EnemyHighlights[pl] = hl
					end
					if not hl.Enabled then hl.Enabled = true end
				else
					-- mort / allié / pas de perso → on ÉTEINT sans détruire
					local hl = EnemyHighlights[pl]
					if hl then hl.Enabled = false end
				end
			end
		end
		-- purge des joueurs qui ont quitté
		for pl, hl in pairs(EnemyHighlights) do
			if not seen[pl] then
				if hl then pcall(function() hl:Destroy() end) end
				EnemyHighlights[pl] = nil
			end
		end
	end
	ClearEnemyHighlights = function()
		for k, hl in pairs(EnemyHighlights) do
			if hl then pcall(function() hl:Destroy() end) end
			EnemyHighlights[k] = nil
		end
		-- purge l'ancien dossier caméra (reliquat des versions précédentes)
		local cam = workspace.CurrentCamera
		local f = cam and cam:FindFirstChild("EnemyOutlines")
		if f then f:Destroy() end
	end
	FlashEnemyHit = function(char)
		local pl = char and Players:GetPlayerFromCharacter(char)
		if not pl then return end
		local hl = char:FindFirstChild("ArenaOutline_" .. pl.UserId)
		if not hl or not hl:IsA("Highlight") or not hl.Enabled then return end
		hl.FillColor = Color3.fromRGB(255, 248, 236)
		hl.FillTransparency = 0.25
		if CI.KVPush then CI.KVPush("f", { c = char }) end   -- [Combat K3] vue du tueur
		TweenService:Create(hl, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FillTransparency = 1 }):Play()
	end
	-- petit ✕ rouge satisfaisant, juste en dessous du curseur, quand on tue
	ShowKillEffect = function()
		local KM = cfg.FX.KillMarker
		-- [Combat MK1] série de kills : au 2e kill et plus, le MultiKill prend le relais (texte + son)
		local MK = CS.Enabled ~= false and CS.MultiKill
		local mkOn = MK and MK.Enabled ~= false
		local st = WeaponController.Streak
		local now = os.clock()
		if mkOn and MK.ResetOnDeath == false and now - st.last > (MK.Window or 4) then st.n = 0 end
		st.n += 1; st.last = now
		local multi = mkOn and st.n >= 2
		-- [Combat KC1] confirmation de kill simple (LocalScript KillConfirm)
		if WeaponController.OnKill then task.spawn(WeaponController.OnKill, multi) end
		local snd = not (multi and tostring(MK.Sound or "") ~= "") and KM.Sound and SoundService:FindFirstChild(KM.Sound)
		if snd and snd:IsA("Sound") then
			local s = snd:Clone(); s.Parent = SoundService; s:Play()
			DebrisService:AddItem(s, 3)
		end
		if not MyPlayer then return end
		local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return end
		-- version fluide (onde + pop élastique), au curseur exact
		WeaponVFX.KillMarker(pg, Snap.CursorPos(), KM)
	end
	-- ========================================================
	-- EQUIP / UNEQUIP
	-- ========================================================
	local function PlayEquip()
		if not cfg.Equip.Enabled and type(cfg.GunKitEquip) ~= "table" then return end   -- [GunKit P15b]
		-- 🚫 pas d'animation de sortie pour les armes normales : seulement les armes GunKit (M4A1, Magnum44)
		if Extra.gkAdapter == nil then Extra.gkArm("R") end
		if not Extra.gkAdapter then
			Equipping = false
			EquipOffsetR, EquipOffsetL = CFrame.new(), CFrame.new()
			return
		end
		Equipping = true
		EquipOffsetR, EquipOffsetL = cfg.Equip.FromR, cfg.Equip.FromL
		if cfg.EquipPartKeys then
			task.spawn(Extra.playPartTrack, cfg.EquipPartKeys, cfg.EquipPartTime or cfg.Equip.Time)
			Extra.playSoundTrack(cfg.EquipSoundTrack, cfg.EquipPartTime or cfg.Equip.Time)
		end
		-- [GunKit P7] sortie d'arme animée : les bras jouent les keyframes de l'arme
		local GKE = (type(cfg.GunKitEquip) == "table" and type(cfg.GunKitEquip.Keyframes) == "table"
			and #cfg.GunKitEquip.Keyframes >= 2) and cfg.GunKitEquip or nil   -- [GunKit P15] piste des bras de l'arme
		local EQK = GKE and GKE.Keyframes or cfg.Equip.Keyframes
		local EQT = GKE and GKE.KeyTime or cfg.Equip.KeyTime
		if type(EQK) == "table" and #EQK >= 2 and not Reloading then
			EquipOffsetR, EquipOffsetL = CFrame.new(), CFrame.new()
			task.spawn(function()
				Extra.playPose(EQK, EQT or 0.9, true)
				if not Reloading then ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new() end
				Equipping = false
			end)
			return
		end
		task.spawn(function()
			-- interpolation d'un segment, courbe au choix :
			-- "out" = démarre franc puis freine (un geste qui se pose)
			-- "in"  = démarre lent puis accélère (un geste qui percute)
			local function seg(dur2, fromL, toL, fromR, toR, ease)
				local tt = 0
				while tt < dur2 and tool.Parent and MyCharacter
					and MyHumanoid and MyHumanoid.Health > 0 do
					tt += RunService.Heartbeat:Wait()
					local x = math.clamp(tt / dur2, 0, 1)
					if ease == "in" then x = x * x
					elseif ease == "out" then x = 1 - (1 - x) * (1 - x)
					else x = x * x * (3 - 2 * x) end
					EquipOffsetL = fromL:Lerp(toL, x)
					EquipOffsetR = fromR:Lerp(toR, x)
				end
				EquipOffsetL, EquipOffsetR = toL, toR
			end
			-- 🆕 R6 : on re-équipe EN PLEIN rechargement (il continue en arrière-plan)
			-- → draw écourté et PAS d'armement : on ne réarme pas au milieu d'un reload.
			local midReload = Reloading
			local dur = cfg.Equip.Time * (midReload and 0.45 or 1)
			-- 1) SORTIE D'ARME — 🆕 R3 : easeOutBack (dépasse un peu puis se pose)
			local ov = cfg.Equip.Overshoot or 0
			local s  = ov * 14      -- 0.12 → ≈1.7 (easeOutBack standard)
			local t = 0
			while t < dur and tool.Parent and MyCharacter do
				t += RunService.Heartbeat:Wait()
				local x = math.clamp(t/dur, 0, 1)
				if s > 0 then
					local u = x - 1
					x = 1 + (s + 1) * u*u*u + s * u*u          -- easeOutBack
				else
					x = 1 - (1-x)*(1-x)*(1-x)                  -- easeOutCubic (comme avant)
				end
				EquipOffsetR = cfg.Equip.FromR:Lerp(CFrame.new(), x)
				EquipOffsetL = cfg.Equip.FromL:Lerp(CFrame.new(), x)
			end
			EquipOffsetR, EquipOffsetL = CFrame.new(), CFrame.new()
			-- 2) 🆕 ARMEMENT : la main gauche tire le levier de culasse
			local CK = cfg.Equip.Cock
			local doCock = (not midReload) and CK and CK.LeftGrab and (CK.Enabled ~= false)
				and (CK.Time or 0) > 0 and tool.Parent == MyCharacter
			if doCock and CK.OnlyFirstEquip ~= false and Extra.cocked then doCock = false end
			if doCock then
				Extra.shareEquipCock = true
				Extra.cocked = true
				local id     = CFrame.new()
				local grab   = CK.LeftGrab
				local back   = CK.PullBack or grab
				local guide  = CK.RightGuide or id
				local settle = CK.RightSettle or id
				local T = CK.Time
				Extra.playGunTrack(CK.GunTrack, T)   -- 🔫
				seg(T * 0.26, id,   grab, id,    guide, "out")   -- la main monte sur le levier
				if CK.Sound then Receiver:FireServer("PlaySound", CK.Sound) end
				seg(T * 0.20, grab, back, guide, guide, "out")   -- tirage vers l'arrière
				seg(T * 0.10, back, grab, guide, guide, "in")    -- RELÂCHE : ça claque (sec)
				if CK.SoundRelease then Receiver:FireServer("PlaySound", CK.SoundRelease) end
				seg(T * 0.26, grab, id,   guide, settle, "out")  -- la main redescend
				seg(T * 0.18, id,   id,   settle, id,    "out")  -- le bras droit se repose
			end
			Extra.shareEquipCock = false
			EquipOffsetR, EquipOffsetL = CFrame.new(), CFrame.new()
			Equipping = false
		end)
	end
	local function OnEquipped(mouse)
		MyCharacter = tool.Parent
		MyPlayer    = Players:GetPlayerFromCharacter(MyCharacter)
		MyHumanoid  = MyCharacter:FindFirstChild("Humanoid")
		MyMouse     = mouse
		if MyPlayer then MyPlayer:SetAttribute("WeaponTracerCustom", TT.Style == "Custom") end  -- 🆕
		Extra.ghostOn()   -- 👻 l'arme traverse les murs
		-- purge un viewmodel orphelin laissé par une mort précédente
		for _, m in ipairs(camera:GetChildren()) do
			if m.Name == "WeaponViewmodel" then m:Destroy() end
		end
		-- purge une LUNETTE orpheline (script de l'ancienne arme mort avant son cleanup)
		do
			local pg = MyPlayer and MyPlayer:FindFirstChild("PlayerGui")
			if pg then
				for _, g in ipairs(pg:GetChildren()) do
					if g.Name == "ScopeGui" then g:Destroy() end
				end
			end
		end
		-- filet de sécurité : nettoyage AVANT la destruction du perso
		-- (CharacterRemoving tire pendant que ce script est encore vivant)
		table.insert(conns, Players.LocalPlayer.CharacterRemoving:Connect(function()
			HardResetVisualState()
			CleanupAllMobileUI()
		end))
		Receiver:FireServer("PlaySound", cfg.Sounds.Equip)
		WeaponSharedState.RegisterWeaponEquipped(tool)
		table.insert(conns, Receiver.OnClientEvent:Connect(function(action, ...)
			local d = {...}
			if action == "ShowDamage" then
				if d[3] ~= MyPlayer then ShowDamagePopup(d[1], d[2], d[4]) end   -- d[4] = headshot
			elseif action == "HitConfirm" then
				-- [Combat C5c] touche confirmée par le serveur (d = rootPart, dégâts, headshot, n° de rafale, perso)
				local rp, dmgC, headC, vid, chC = d[1], d[2], d[3] == true, d[4], d[5]
				if chC then FlashEnemyHit(chC) end
				if rp then ShowDamagePopup(rp, dmgC, headC) end
				local cv = Extra.confirmVolley
				if not cv or cv.id ~= vid then cv = { id = vid }; Extra.confirmVolley = cv end
				if not cv.sound or (headC and not cv.head) then
					cv.sound = true
					cv.head = cv.head or headC
					C.PlayHitSound(headC)
					task.spawn(FlashHitMarkers, headC)
				end
			elseif action == "Killed" then
				ShowKillEffect()
			elseif action == "MuzzleFX" then
				-- douilles + lumière des AUTRES joueurs (d[1]=handleCF, d[2]=flashPos, d[3]=shooter)
				if d[3] ~= MyPlayer and not Extra.gkNetShooter(d[3]) then   -- [GunKit P20]
					SpawnLocalShell(d[1]); SpawnLocalMuzzleLight(d[2])
					WeaponVFX.StarFlash(d[2], cfg.FX.ViewmodelFlash, 1)
				end
			elseif action == "ApplyKnockback" then
				local hrp, impulse = d[1], d[2]
				if hrp and hrp:IsA("BasePart") then
					hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + impulse
				end	
			elseif action == "ImpactFX" then
				SpawnImpact(d[1], d[2], d[3])
			end
		end))
		if cfg.Rocket.Enabled then
			rocketRelayData = buildRocketRelay()
			-- 🚀 On PUBLIE les valeurs du config dans les attributs : l'Anim
			-- Studio part donc de ta roquette telle qu'elle est aujourd'hui, et
			-- non de zéro (sinon elle se téléporterait au premier appui).
			do
				local RP0 = cfg.Rocket.ReloadProp
				local function pub(pfx, c)
					if not c then return end
					if tool:GetAttribute(pfx .. "X") ~= nil then return end
					local pp = c.Position
					local ax, ay, az = (c - pp):ToEulerAnglesXYZ()
					tool:SetAttribute(pfx.."X", pp.X); tool:SetAttribute(pfx.."Y", pp.Y)
					tool:SetAttribute(pfx.."Z", pp.Z)
					tool:SetAttribute(pfx.."RX", math.deg(ax)); tool:SetAttribute(pfx.."RY", math.deg(ay))
					tool:SetAttribute(pfx.."RZ", math.deg(az))
				end
				if RP0 then
					pub("TuneRocketStart", RP0.HandOffset)
					pub("TuneRocketSeat",  RP0.SeatOffset)
				end
			end
			-- 🚀 tant que l'éditeur demande à TENIR la roquette, on la garde en
			-- main hors rechargement pour pouvoir la placer tranquillement.
			task.spawn(function()
				while tool.Parent and tool.Parent == MyCharacter do
					task.wait(0.3)
					local want = tool:GetAttribute("TuneRocketHold") == true
					if want and not (Extra.rocketProp and Extra.rocketProp.Parent) then
						Extra.rocketProp = SpawnReloadRocket()
					elseif not want and Extra.rocketProp then
						Extra.rocketProp:Destroy(); Extra.rocketProp = nil
					end
				end
				if Extra.rocketProp then Extra.rocketProp:Destroy(); Extra.rocketProp = nil end
			end)
		end
		local hud = tool:FindFirstChild("WeaponHud")
		if hud and MyPlayer then
			WeaponGui = hud:Clone(); WeaponGui.Parent = MyPlayer.PlayerGui
			local cross = WeaponGui:FindFirstChild("Crosshair"); if cross then cross.Visible=false end
			local oldRL = WeaponGui:FindFirstChild("ReloadingLabel"); if oldRL then oldRL.Visible=false end
			local keys = { {key="M",action="Fire", image=cfg.KeyIcons.Fire}, {key="R",action="Reload"} }
			if cfg.ADS.Enabled then table.insert(keys, {key="Q",action="Aim", image=cfg.KeyIcons.Aim}) end
			table.insert(keys, {key="Shift",action="Sprint"})
			table.insert(keys, {key="C",action="Slide"})
			table.insert(keys, {key="B",action="Views"})
			table.insert(keys, {key="H",action="Hide Controls"})   -- 🆕 toujours en bas
			styleAmmoHud(keys)
			UpdateAmmo(AmmoInClip)
		end
		local recoilAnim = tool:FindFirstChild("Recoil")
		if cfg.UseRecoilAnim and recoilAnim and MyHumanoid then RecoilTrack = MyHumanoid:LoadAnimation(recoilAnim) end
		if MyHumanoid then
			DiedConnection = MyHumanoid.Died:Connect(function()
				-- À la mort, Roblox n'appelle PAS Unequipped → on nettoie nous-mêmes
				-- TOUT le visuel (viewmodel figé, caméra bloquée, curseur, FOV…).
				HardResetVisualState()
				CleanupAllMobileUI()
				-- on remet le CameraOffset du perso mort à zéro (slide/abaissement)
				if MyHumanoid then pcall(function() MyHumanoid.CameraOffset = Vector3.new() end) end
			end)
		end
		if MyMouse then
			MyMouse.Icon = cfg.CustomCursorID
			table.insert(conns, MyMouse.KeyDown:Connect(function(k) if k:lower()=="r" then Reload() end end))
		end
		-- 🖱 TIR : plus AUCUN tir sur un simple clic écran.
		--  • Mouse.Button1Down est ABANDONNÉ : il tirait même quand le clic
		--    atterrissait sur une UI, et il se déclenchait aussi sur un TAP mobile.
		--  • On passe par UserInputService avec le garde `gp` (gameProcessedEvent)
		--    + un test des GuiButton sous le curseur → clic sur un bouton = pas de tir.
		--  • Sur MOBILE : rien n'est branché ici → SEUL le bouton de tir tire
		--    (appui = tir, maintien = tir continu, géré par CreateMobileFireButton).
		local function PointerOverGui(x, y)
			if not MyPlayer then return false end
			-- souris verrouillée au centre (shift-lock / lunette) → pas de test UI
			if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then return false end
			local pg = MyPlayer:FindFirstChild("PlayerGui"); if not pg then return false end
			local ok, objs = pcall(function() return pg:GetGuiObjectsAtPosition(x, y) end)
			if not ok or not objs then return false end
			for _, o in ipairs(objs) do
				if o:IsA("GuiButton") or o:IsA("TextBox") then return true end
			end
			return false
		end
		if not IsMobile then
			table.insert(conns, UserInputService.InputBegan:Connect(function(input, gp)
				if gp then return end   -- input consommé par une UI / le chat → ignoré
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					if PointerOverGui(input.Position.X, input.Position.Y) then return end
					LeftButtonDown = true
					task.spawn(OnFire)
				elseif cfg.ADS.Enabled and input.UserInputType == Enum.UserInputType.MouseButton2 then
					if PointerOverGui(input.Position.X, input.Position.Y) then return end
					Extra.requestAim("mouse", true)
				end
			end))
			table.insert(conns, UserInputService.InputEnded:Connect(function(input)
				-- le RELÂCHÉ n'est jamais filtré (sinon on resterait "bouton enfoncé")
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					LeftButtonDown = false
				elseif cfg.ADS.Enabled and input.UserInputType == Enum.UserInputType.MouseButton2 then
					Extra.requestAim("mouse", false)
				end
			end))
		end
		-- [Combat C4] 🎮 MANETTE (boutons réglables dans CombatSettings.Gamepad)
		do
			local GP = CS.Gamepad
			if CS.Enabled ~= false and GP and GP.Enabled ~= false and not IsMobile then
				local GuiService = game:GetService("GuiService")
				local function uiBusy()
					return UserInputService:GetFocusedTextBox() ~= nil or GuiService.SelectedObject ~= nil
						or GuiService.MenuIsOpen
				end
				table.insert(conns, UserInputService.InputBegan:Connect(function(input)
					local k = input.KeyCode
					if k == Enum.KeyCode.Unknown or uiBusy() then return end
					if k == GP.Fire then
						LeftButtonDown = true
						task.spawn(OnFire)
					elseif k == GP.Aim and cfg.ADS.Enabled then
						Extra.requestAim("pad", true)
					elseif k == GP.Reload then
						task.spawn(Reload)
					elseif k == GP.ToggleView then
						if not IsActuallyFirstPerson() then WeaponSharedState.ToggleMode() end
					end
				end))
				table.insert(conns, UserInputService.InputEnded:Connect(function(input)
					local k = input.KeyCode
					if k == GP.Fire then
						LeftButtonDown = false
					elseif k == GP.Aim then
						Extra.requestAim("pad", false)
					end
				end))
				-- stick droit : ta caméra épaule (vue B) est scriptée → on la fait tourner nous-mêmes
				table.insert(conns, UserInputService.InputChanged:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Thumbstick2 then Extra.padStick = input.Position end
				end))
				table.insert(conns, RunService.RenderStepped:Connect(function(dt)
					local st = Extra.padStick
					if not st or not MyCharacter or not WeaponSharedState.IsThirdPersonLock() then return end
					local x, y = st.X, st.Y
					local dz = GP.StickDeadzone or 0.15
					local m = math.sqrt(x * x + y * y)
					if m <= dz then return end
					local k = (math.clamp((m - dz) / (1 - dz), 0, 1) ^ (GP.StickCurve or 1.7)) / m
					local slow = CI.AimSlowdownFactor(Aiming)
					local mult = GetHipSensMult() * slow
					CameraYaw -= x * k * (GP.StickYawSpeed or 3.2) * dt * mult
					CameraPitch = math.clamp(CameraPitch + y * k * (GP.StickPitchSpeed or 2.2) * dt * mult, PitchMin, PitchMax)
				end))
			end
		end
		MobileCursorGui = buildCursor(false)
		if Reloading then SetReloadingTextVisible(true) end   -- recharge d'arrière-plan en cours
		task.spawn(CacheArmWelds)
		StartFeelLoop()
		-- 🧩 PIÈCES DE L'ARME. On n'indexe QUE celles citées dans cfg.Parts :
		-- une arme d'un seul bloc n'est jamais touchée.
		-- 🧩 les pièces cochées dans l'Anim Studio arrivent par attribut
		-- (« A,B,C »). Elles s'ajoutent à celles du config : tu peux donc en
		-- déclarer à la main ET en cocher dans le panneau.
		do
			local pl = tool:GetAttribute("PartsList")
			if type(pl) == "string" and pl ~= "" then
				for nm in string.gmatch(pl, "[^,]+") do
					if cfg.Parts[nm] == nil then cfg.Parts[nm] = {} end
				end
			end
			Extra.magName = tool:GetAttribute("MagPart")
		end
		if next(cfg.Parts or {}) ~= nil then
			-- on rend d'abord ce qu'un index précédent tenait encore : sortir et
			-- ressortir l'arme très vite ne doit pas laisser une pièce masquée.
			if Extra.parts then FX2.PartsClear(Extra.parts) end
			Extra.parts = FX2.PartsIndex(tool, Handle, cfg.Parts)
		end
		-- ⚡ le mode performance s'applique à l'arme qu'on vient de sortir, et
		-- réagit ensuite à chaque bascule du réglage.
		Extra.perfApply(Extra.perfWanted())
		-- 🩹 la connexion est coupée à chaque rangement : on la refait si besoin
		-- (avant, le mode perf ne réagissait plus après le 1er rangement)
		if MyPlayer and not (Extra.perfConn and Extra.perfConn.Connected) then
			Extra.perfConn = MyPlayer:GetAttributeChangedSignal("SettingPerfMode")
				:Connect(function()
					-- après le panneau Settings, qui règle les sous-options en même temps
					task.delay(0.1, function() Extra.perfApply(Extra.perfWanted()) end)
				end)
			table.insert(conns, Extra.perfConn)
		end
		Extra.startCross()   -- 🎯 le viseur scripté suit la souris
		table.insert(conns, tool:GetAttributeChangedSignal("Optic"):Connect(function() Extra.vmRebuild = true end))
		if cfg.Viewmodel.Enabled then StartViewmodelLoop() end
		PlayEquip()
		if IsMobile then
			ApplyCurrentMode(true)
			MobileFireGui = CreateMobileFireButton()
			MobileReloadGui = CreateMobileReloadButton()
			MobileViewGui = CreateMobileViewButton()
			Extra.createMobileAim()
		else
			ApplyCurrentMode(true)
		end
		CreateChargeBar()
		-- cercles snap + crosshair/hit markers qui SUIVENT le curseur (chaque frame)
		-- ⚡ OPTIM : le viseur est déjà placé chaque image par Extra.startCross
		-- (même calcul, même position) : on ne le refait plus une 2e fois ici.
		table.insert(conns, RunService.RenderStepped:Connect(function()
			Snap.UpdateRing()
		end))
		-- 🆕 sensibilité "arme en main" appliquée dès l'équipe (1re personne)
		if not IsMobile and not Aiming then
			UserInputService.MouseDeltaSensitivity = RestingMouseDelta()
		end
		if MyPlayer then
			table.insert(conns, MyPlayer:GetAttributeChangedSignal("SettingHipSensitivity"):Connect(function()
				if not IsMobile and not Aiming then
					UserInputService.MouseDeltaSensitivity = RestingMouseDelta()
				end
			end))
		end
		if cfg.ADS.Scope then
			CreateScope()
			table.insert(conns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(LayoutScope))
		end
		ModeChangedConnection = WeaponSharedState.ModeChanged:Connect(function()
			-- la visée n'existe qu'en 1re personne → on l'annule si on passe en TP
			if not WeaponSharedState.IsFirstPersonAim() then
				Extra.aimInput.mobile = false
				SetAiming(false)
				Extra.refreshMobileAim()
			end
			ApplyCurrentMode(false); CreateChargeBar()
			if not IsMobile and not Aiming then   -- 🆕
				UserInputService.MouseDeltaSensitivity = RestingMouseDelta()
			end
		end)
		table.insert(conns, UserInputService.InputBegan:Connect(function(input, gp)
			if gp then return end
			if input.KeyCode==Enum.KeyCode.R or input.KeyCode==Enum.KeyCode.ButtonX then Reload() end
			if cfg.ADS.Enabled and input.KeyCode==Enum.KeyCode.Q then Extra.requestAim("key", true) end
			if not IsMobile and input.KeyCode==Enum.KeyCode.H then ToggleControls() end
			-- 🆕 V = INSPECTION (spammable : chaque appui repart du début)
			-- (inspection retirée : la touche V ne fait plus rien)
			-- le changement de mode passe sur B (V est pris par l'inspection)
			if not IsMobile and input.KeyCode==Enum.KeyCode.B then
				-- en VRAIE 1re personne (viewmodel actif), on n'autorise pas le changement de mode
				if not IsActuallyFirstPerson() then
					WeaponSharedState.ToggleMode()
				end
			end
		end))
		table.insert(conns, UserInputService.InputEnded:Connect(function(input)
			if cfg.ADS.Enabled and input.KeyCode==Enum.KeyCode.Q then Extra.requestAim("key", false) end
		end))
		table.insert(conns, UserInputService.WindowFocusReleased:Connect(Extra.clearAimInput))
		-- ── input touch caméra mobile / trackpad PC thirdperson ──
		table.insert(conns, UserInputService.InputBegan:Connect(function(input)
			if not IsMobile or not MyPlayer or not MyCharacter then return end
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			if RightDragInput or FireTouchInput == input then return end
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			-- [Combat C7] tout l'écran tourne la vue (côté gauche compris), SAUF le joystick et les boutons
			local anywhere = CS.Enabled ~= false and CS.MobileLookAnywhere ~= false
			if not anywhere and pos.X < camera.ViewportSize.X * 0.5 then return end
			local pg = MyPlayer:FindFirstChild("PlayerGui")
			if pg then for _, o in ipairs(pg:GetGuiObjectsAtPosition(pos.X, pos.Y)) do
					if o:IsA("GuiButton") or o:IsA("TextBox") then return end
					if anywhere and (o.Name:find("Thumbstick") or (o:FindFirstAncestor("TouchGui") and o.Name ~= "TouchControlFrame")) then return end
				end end
			-- joystick de Roblox pas encore là : le bas-gauche reste au déplacement
			if anywhere and not (pg and pg:FindFirstChild("TouchGui"))
				and pos.X < camera.ViewportSize.X * 0.4 and pos.Y > camera.ViewportSize.Y * 0.35 then return end
			RightDragInput = input; RightDragLastPos = pos
		end))
		table.insert(conns, UserInputService.InputChanged:Connect(function(input)
			local hipMult = GetHipSensMult()   -- 🆕 réglage "sensibilité arme en main"
			if not IsMobile and WeaponSharedState.IsThirdPersonLock() and MyCharacter then
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					CameraYaw -= input.Delta.X * PCMobileSensitivity * hipMult
					CameraPitch = math.clamp(CameraPitch - input.Delta.Y * PCMobileSensitivity * hipMult, PitchMin, PitchMax)
				end
				return
			end
			if not IsMobile or not MyCharacter then return end
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			if Aiming then
				local aimSens = GetSetting("SettingAimSensitivity", nil)
				hipMult *= aimSens and math.clamp(aimSens / 100, 0.1, 1) or cfg.ADS.SensitivityScale
			end
			if input == RightDragInput and RightDragLastPos then
				local np = Vector2.new(input.Position.X, input.Position.Y)
				local d = np - RightDragLastPos; RightDragLastPos = np
				CameraYaw -= d.X * MainDragSensitivity * hipMult
				CameraPitch = math.clamp(CameraPitch - d.Y * MainDragSensitivity * hipMult, PitchMin, PitchMax)
			elseif input == FireTouchInput and FireTouchLastPos then
				local np = Vector2.new(input.Position.X, input.Position.Y)
				local d = np - FireTouchLastPos; FireTouchLastPos = np
				CameraYaw -= d.X * FireDragSensitivity * hipMult
				CameraPitch = math.clamp(CameraPitch - d.Y * FireDragSensitivity * hipMult, PitchMin, PitchMax)
			end
		end))
		table.insert(conns, UserInputService.InputEnded:Connect(function(input)
			if not IsMobile or not MyCharacter then return end
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			if input == RightDragInput then RightDragInput=nil; RightDragLastPos=nil end
			if input == FireTouchInput then
				LeftButtonDown=false; FireTouchInput=nil; FireTouchLastPos=nil
				WeaponSharedState.ReleaseTouch(input)   -- 🔓 doigt libéré
				if MobileFireButton then MobileFireButton.BackgroundTransparency=0.5 end
			end
		end))
	end
	-- Nettoyage VISUEL complet (viewmodel, caméra, curseur, FOV, états feel).
	-- Utilisé à la mort SANS toucher au compteur d'armes ni couper les connexions
	-- (l'arme reste "équipée" tant qu'on ne la déséquipe pas vraiment).
	HardResetVisualState = function()
		Extra.share:Stop()
		Extra.shareEquipCock, Extra.shareGrip, Extra.shareGrab, Extra.shareLastCategory = nil,nil,nil,nil
		Extra.third=nil
		Extra.clearAimInput()
		-- CAMÉRA + VIEWMODEL D'ABORD (le plus critique), sous pcall :
		-- même si un truc échoue ensuite, l'écran est déjà rendu au joueur.
		pcall(function()
			if CameraRenderConnection then CameraRenderConnection:Disconnect(); CameraRenderConnection=nil end
			if camRenderBound then RunService:UnbindFromRenderStep(camRenderName); camRenderBound=false end
			WeaponSharedState.ReleaseCamera(camOwnerToken)
			if camera and not Extra.otherOwnsCam() then camera.CameraType = Enum.CameraType.Custom end
		end)
		pcall(StopViewmodel)
		LeftButtonDown=false; AutoShooting=false; Reloading=false
		Aiming=false; AimAlpha=0; AutoshootHoldElapsed=0
		Pumping=false; IsShooting=false; Equipping=false
		Extra.cutTok = (Extra.cutTok or 0) + 1   -- 🎟 coupe tout geste en attente
		Extra.reloadTok = (Extra.reloadTok or 0) + 1
		-- FOV + sensibilité souris
		BaseFOV = cfg.ADS.HipFOV; FireFOVOffset = 0
		if not Extra.otherOwnsCam() then   -- 🔒 l'arme de la nouvelle vie a déjà la main : on n'y touche pas
			if camera and cfg.ADS.Enabled then camera.FieldOfView = cfg.ADS.HipFOV end
			UserInputService.MouseDeltaSensitivity = 1
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
		-- état partagé (sinon le sprint reste "en visée", curseur caché, etc.)
		WeaponSharedState.SetAiming(false)
		WeaponSharedState.SetFiring(false)
		if IsMobile then SetWholeCharacterHidden(false) end
		-- CAMÉRA : on force le retour en Custom, peu importe le mode (shift-lock inclus).
		if CameraRenderConnection then CameraRenderConnection:Disconnect(); CameraRenderConnection=nil end
		if camRenderBound then RunService:UnbindFromRenderStep(camRenderName); camRenderBound=false end
		Extra.stopCross()
		-- 🧩 on range les pièces : rien ne doit rester décroché entre deux armes
		Extra.partTok = (Extra.partTok or 0) + 1
		-- 🎟 ET ON COUPE LA PISTE DU CHARGEUR. Sans ça, l'état « décroché »
		-- survivait au rangement : au ré-équipement, vmSync le rejouait sur le
		-- viewmodel tout neuf — chargeur soudé à une ancre, EN L'AIR, sans
		-- aucune piste en cours pour venir le rechercher.
		Extra.magTok = (Extra.magTok or 0) + 1
		Extra.magState = nil
		if Extra.magName then
			Extra.partsDo(function(idx) FX2.PartRestore(idx, Extra.magName) end)
		end
		FX2.PartsClear(Extra.parts)
		FX2.PartsClear(Extra.vmParts)
		-- 🧹 MORT / RESPAWN :
		-- supprimer les copies de chargeurs déjà lancées pendant le reload.
		FX2.DroppedClear()
		WeaponSharedState.ReleaseCamera(camOwnerToken)
		if camera and not Extra.otherOwnsCam() then camera.CameraType = Enum.CameraType.Custom end
		SavedCameraOffset = nil
		-- scope + curseur mobile + popups + highlights + kill marker
		if ScopeGui then ScopeGui:Destroy(); ScopeGui=nil; ScopeCanvas=nil; ScopeScale=nil end
		ScopeAlpha = 0
		CleanupAllDamagePopups()
		ClearEnemyHighlights()
		Snap.DestroyRing()
		if KillEffectGui then KillEffectGui:Destroy(); KillEffectGui=nil end
		-- VIEWMODEL : on détruit le modèle cloné + on réaffiche les vrais bras/arme.
		StopViewmodel()
		-- offsets feel remis à zéro (sinon les bras restent figés au respawn)
		RecoilOffset, ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new(), CFrame.new()
		EquipOffsetR, EquipOffsetL = CFrame.new(), CFrame.new()
		JumpOffsetR, JumpOffsetL = CFrame.new(), CFrame.new()
		jumpVelSmooth, lastVY, landSpring, landSpringVel = 0, 0, 0, 0
		wasAirborneFeel = false
		Aim.Motion = CFrame.identity
		Aim.phase, Aim.strafe, Aim.jumpV, Aim.fireImp = 0, 0, 0, 0
		Extra.airDrop, Extra.mvS, Extra.mvR, Extra.mvL, Extra.mvZ = 0, 0, 0, 0, 0
		Extra.mvW = nil
		CamRecoilPitch, CamRecoilYaw = 0, 0
		SwayOffset = CFrame.new(); AimRecoil = Vector3.zero; ConsecutiveShots = 0
		Walk.alpha = 0; Walk.phase = 0; Walk.velYaw = 0; Walk.velPitch = 0
		Walk.prevCF = nil; Walk.Root = CFrame.new()
		Extra.adsWalk, Extra.adsSlide, Extra.adsPhase = 0, 0, 0
		Extra.liveMotion = CFrame.identity
		Extra.motionState = nil
		Extra.slideLean = nil
		if Extra.visualShots then table.clear(Extra.visualShots); Extra.shotSide = 0 end
		Extra.reloadAimAt, Extra.chamberAimAt = nil, nil
		-- 🆕 nouvel état
		Extra.bloom = 0; Extra.lastShotAt = 0; Extra.crossPx = -1
		Extra.idleAlpha = 0; Extra.idleRoot = CFrame.new()
		Extra.cocked = false   -- on réarme l'arme à la prochaine vie
		Extra.cocking = false; Extra.animPrio = 0; Extra.boltToken = (Extra.boltToken or 0) + 1
		Extra.gunTrack = nil; Extra.gunGrabL = nil   -- 🔫
		NextAllowedShot = 0   -- 🆕
	end
	local function OnUnequipped()
		Extra.ghostOff()   -- 👻 l'arme rangée / lâchée retrouve ses collisions
		Extra.share:Stop()
		Extra.shareEquipCock, Extra.shareGrip, Extra.shareGrab, Extra.shareLastCategory = nil,nil,nil,nil
		Extra.third=nil
		Extra.clearAimInput()
		Extra.motionState = nil
		Extra.slideLean = nil
		Extra.liveMotion = CFrame.identity
		LeftButtonDown=false; AutoShooting=false; Aiming=false; AimAlpha=0; AutoshootHoldElapsed=0
		-- Reloading N'EST PLUS annulé ici : une recharge en cours CONTINUE en
		-- ARRIÈRE-PLAN pendant que l'arme est au backpack (fini de recharger
		-- après son temps normal → chargeur plein au re-équipe)
		if camera and cfg.ADS.Enabled then camera.FieldOfView = cfg.ADS.HipFOV end
		BaseFOV = cfg.ADS.HipFOV; FireFOVOffset = 0
		UserInputService.MouseDeltaSensitivity = 1
		WeaponSharedState.SetAiming(false)   -- ← coupe le flag visée partagé (sinon curseur reste caché)
		WeaponSharedState.SetFiring(false)
		if IsMobile then SetWholeCharacterHidden(false) end
		UserInputService.MouseIconEnabled = true
		-- délock UNIQUEMENT si la lunette était RÉELLEMENT active (ScopeAlpha > 0).
		-- Avant : forcé à CHAQUE déséquipe du sniper, même non scopé → en vraie
		-- 1re personne (souris LockCenter tenue par l'engine), ce Default d'une
		-- frame suivi du re-lock créait un DELTA PARASITE géant → saut de caméra.
		if cfg.ADS.Scope and ScopeAlpha > 0.02 then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		WeaponSharedState.RegisterWeaponUnequipped(tool)
		for _, c in ipairs(conns) do c:Disconnect() end; conns = {}
		if ModeChangedConnection then ModeChangedConnection:Disconnect(); ModeChangedConnection=nil end
		if DiedConnection then DiedConnection:Disconnect(); DiedConnection=nil end
		CleanupAllDamagePopups(); RestoreShiftLock(true); CleanupAllMobileUI()
		ClearEnemyHighlights()
		Snap.DestroyRing()
		if KillEffectGui then KillEffectGui:Destroy(); KillEffectGui=nil end
		if ScopeGui then ScopeGui:Destroy(); ScopeGui=nil; ScopeCanvas=nil; ScopeScale=nil; ScopeAlpha=0 end
		if FeelConnection then FeelConnection:Disconnect(); FeelConnection=nil end
		RecoilOffset, ReloadOffsetR, ReloadOffsetL = CFrame.new(), CFrame.new(), CFrame.new()
		CamRecoilPitch, CamRecoilYaw = 0, 0; SwayOffset = CFrame.new(); ConsecutiveShots = 0
		AimRecoil = Vector3.zero
		JumpOffsetR, JumpOffsetL = CFrame.new(), CFrame.new()
		jumpVelSmooth, lastVY, landSpring, landSpringVel = 0, 0, 0, 0
		wasAirborneFeel = false
		Aim.Motion = CFrame.identity
		Aim.phase, Aim.strafe, Aim.jumpV, Aim.fireImp = 0, 0, 0, 0
		Extra.airDrop, Extra.mvS, Extra.mvR, Extra.mvL, Extra.mvZ = 0, 0, 0, 0, 0
		Extra.mvW = nil
		StopViewmodel()
		if MyHumanoid then pcall(function() MyHumanoid.CameraOffset = Vector3.new() end) end
		MyCharacter,MyHumanoid,MyPlayer,MyMouse = nil,nil,nil,nil
		if WeaponGui then WeaponGui:Destroy(); WeaponGui=nil end
		if RecoilTrack then RecoilTrack:Stop(); RecoilTrack=nil end
	end
	-- 🧪 TIR À BLANC pour l'onglet RECUL de l'Anim Studio : recul, éclair et son,
	-- sans balle, sans munition, rien sur le réseau. Mêmes formules que le vrai tir.
	WeaponController.Tools[tool] = {
		shot = function(ads)
			if not (MyHumanoid and MyHumanoid.Health > 0 and tool.Parent == MyCharacter) then
				return false
			end
			AddRecoilKick()
			if ads then
				local was = Aiming
				Aiming = true
				Extra.recordVisualShot()
				Aiming = was
				if not Extra.freezeAim() then
					Aim.fireImp = 1
					local r = cfg.ADS.Recoil
					local axial = cfg.ADS.RecoilAxisOnly
					AimRecoil = AimRecoil + Vector3.new(
						axial and 0 or (math.random() - 0.5) * 2 * r.Side,
						axial and 0 or r.Up,
						r.Back * (IsMobile and (cfg.Feel.MobileRecoilScale or 1) or 1))
					AimRecoil = Vector3.new(
						axial and 0 or math.clamp(AimRecoil.X, -r.Max, r.Max),
						axial and 0 or math.clamp(AimRecoil.Y, -r.Max, r.Max),
						math.clamp(AimRecoil.Z, -r.Max, r.Max))
				end
			end
			if cfg.Rocket.Enabled then
				local ks = ads and cfg.ADS.FireFOVScale or 1
				FireFOVOffset = math.min(3, FireFOVOffset + (cfg.FX.FireFOVKick or 0) * ks)
			end
			EmitViewmodelFlash(false)
			local fp = viewmodel and viewmodel.Parent == camera and vmFlash
			SpawnLocalMuzzleLight(fp or Flash)
			local snd = Handle:FindFirstChild(tostring(cfg.Sounds.Fire or ""))
			if snd and snd:IsA("Sound") then
				local c = snd:Clone(); c.Parent = Handle; c:Play()
				DebrisService:AddItem(c, math.max(1, c.TimeLength + 0.2))
			end
			return true
		end,
		burst = function(on)
			if not (RecoilTrack and cfg.UseRecoilAnim) then return end
			if on then RecoilTrack:Play() else RecoilTrack:Stop() end
		end,
	}
	tool.Destroying:Connect(function()
		HardResetVisualState()
		CleanupAllMobileUI()
	end)
	tool.Equipped:Connect(OnEquipped)
	tool.Unequipped:Connect(OnUnequipped)
	-- ========================================================
	-- BOUCLE PRINCIPALE (reticle + autoshoot + spread decay)
	-- ========================================================
	task.spawn(function()
		while tool.Parent do
			local dt = task.wait(0.033)
			-- ⚡ OPTIM : chaque arme du sac avait sa propre boucle à 30 Hz, même
			-- rangée. Une arme pas en main attend tranquillement.
			if not (MyCharacter and tool.Parent == MyCharacter) then
				task.wait(0.3)
				continue
			end
			-- 🆕 publie SI cette arme est réellement équipée (et seulement si ça change)
			if Players.LocalPlayer:GetAttribute("WeaponTracerCustom") ~= (TT.Style == "Custom") then
				Players.LocalPlayer:SetAttribute("WeaponTracerCustom", TT.Style == "Custom")
			end
			-- UpdateEnemyHighlights()  -- désactivé : géré par ArenaHighlights (client)
			if WeaponGui then
				local want = Neutral   -- 🎯 couleur choisie puis écrite UNE fois (rouge = ennemi)
				local onEnemy = false
				if WeaponSharedState.IsThirdPersonLock() or IsMobile or CI.IsGamepad() then   -- [Combat C2d]
					local cf = camera.CFrame
					local rp = Extra.retRay   -- ⚡ préparé une fois (avant : recréé 30×/s)
					if not rp then rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; Extra.retRay = rp end
					if Extra.retRayChar ~= MyCharacter or Extra.retRayVM ~= viewmodel then
						Extra.retRayChar, Extra.retRayVM = MyCharacter, viewmodel
						rp.FilterDescendantsInstances = { MyCharacter, viewmodel }
					end
					local res = workspace:Raycast(cf.Position, cf.LookVector*cfg.Range, rp)
					if res and res.Instance and res.Instance.Parent then
						local hum = res.Instance.Parent:FindFirstChild("Humanoid")
						if hum and hum.Health>0 then
							local pl = Players:GetPlayerFromCharacter(res.Instance.Parent)
							if MyPlayer then
								if pl then
									if MyPlayer.Neutral or pl.TeamColor~=MyPlayer.TeamColor then want = Enemy; onEnemy=true
									else want = Friendly end
								else want = Enemy; onEnemy=true end
							end
						end
						if res.Instance.Parent:FindFirstChild("Egglon") then want = Enemy; onEnemy=true end
					end
				elseif MyMouse then
					local tgt = MyMouse.Target
					if tgt and tgt.Parent then
						local tm = tgt:FindFirstAncestorWhichIsA("Model")
						local pl = Players:GetPlayerFromCharacter(tgt.Parent) or (tm and Players:GetPlayerFromCharacter(tm))
						if pl and pl ~= MyPlayer and pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
							and pl.Character:FindFirstChildOfClass("Humanoid").Health <= 0 then pl = nil end
						if pl == MyPlayer then pl = nil end
						if pl and MyPlayer then
							if MyPlayer.Neutral or pl.TeamColor~=MyPlayer.TeamColor then want = Enemy
							else want = Friendly end
						elseif MyPlayer then
							-- 🤖 bot d'arène (même si on vise un accessoire)
							local m = tgt:FindFirstAncestorWhichIsA("Model")
							if m and m:GetAttribute("ArenaBot") then
								local bh = m:FindFirstChildOfClass("Humanoid")
								if bh and bh.Health > 0 then want = Enemy end
							end
						end
					end
				end
				SetReticleColor(want)
				-- AUTOSHOOT (mobile) — la charge se REMPLIT sur la cible et se VIDE
				-- lentement quand on la perd : on reprend où on en était, pas de reset.
				if IsMobile and cfg.Autoshoot and GetSetting("SettingAutoFire", true) then
					local nowA = os.clock()
					local canAuto = not Reloading and AmmoInClip > 0
						and MyHumanoid and MyHumanoid.Health > 0
						and nowA >= AutoShootCooldownUntil
					-- Bonus commun ajouté AUSSI aux délais propres aux Tools.
					local hold = math.max(0.01, cfg.AutoshootHoldTime
						+ math.max(0, cfg.LiveFeel.Assist.AutoshootExtraDelay or 0))
					-- vidage lent (cible perdue, recharge, plus de balles)
					local function drainCharge()
						AutoshootHoldElapsed = math.max(0,
							AutoshootHoldElapsed - dt * (cfg.AutoshootDecayScale or 0.35))
						UpdateChargeBar(math.clamp(AutoshootHoldElapsed / hold, 0, 1))
					end
					if cfg.Autoshoot == "Delay" then
						if canAuto and not IsShooting and IsEnemyInCrosshair() then
							AutoshootHoldElapsed += dt
							UpdateChargeBar(math.clamp(AutoshootHoldElapsed / hold, 0, 1))
							if AutoshootHoldElapsed >= hold then
								AutoShootCooldownUntil = nowA + cfg.AutoshootCooldown
								task.spawn(OnFire)
							end
						else
							drainCharge()
						end
					else -- Simple
						-- cible = sous la croix OU dans le rayon de snap assist
						local hasTarget = onEnemy
						if not hasTarget and cfg.AutoshootUseSnapRadius then
							hasTarget = Snap.GetTarget() ~= nil
						end
						-- fin de rafale
						if AutoShooting and (cfg.AutoshootBurstTime or 0) > 0
							and nowA - AutoShootStart >= cfg.AutoshootBurstTime then
							AutoShooting = false
							AutoShootCooldownUntil = nowA + cfg.AutoshootCooldown
							AutoshootHoldElapsed = 0
						end
						if hasTarget and canAuto then
							if AutoShooting then
								UpdateChargeBar(1)   -- rafale en cours
							else
								AutoshootHoldElapsed += dt
								UpdateChargeBar(math.clamp(AutoshootHoldElapsed / hold, 0, 1))
								if AutoshootHoldElapsed >= hold then
									AutoShooting = true
									AutoShootStart = nowA
									if not IsShooting then task.spawn(OnFire) end
								end
							end
						else
							if AutoShooting then AutoShootCooldownUntil = nowA + cfg.AutoshootCooldown end
							AutoShooting = false
							drainCharge()   -- 🆕 au lieu de AutoshootHoldElapsed = 0
						end
					end
				elseif IsMobile and cfg.Autoshoot then
					-- auto-fire désactivé par le joueur : on coupe proprement
					AutoShooting = false; AutoshootHoldElapsed = 0; UpdateChargeBar(0)
				end
			end
			-- ancienne décroissance : uniquement si la dispersion dynamique est COUPÉE
			if not Extra.dynOn and Spread and not IsShooting then
				if time() - LastSpreadUpdate > cfg.FireRate * 2 then
					LastSpreadUpdate = time()
					Spread = math.max(cfg.MinSpread, Spread - cfg.AimInaccuracyStepAmount); UpdateCrosshair(Spread)
				end
			end
		end
	end)
end
return WeaponController