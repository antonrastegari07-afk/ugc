--[[
	CombatSettings  (ModuleScript)
	Emplacement : ReplicatedStorage > WeaponSystem > CombatSettings

	TOUS les réglages des ajouts de combat sont ICI, au même endroit.
	Chaque système a son interrupteur « Enabled » : mets false pour le couper,
	sans toucher à aucun autre script.

	Systèmes :
	  • Gamepad          manette (PS / Xbox) : boutons, aide à la visée légère, icônes
	  • ZoneDamage       dégâts par zone (tête / torse / bras / jambes)
	  • HitValidation    le serveur revérifie chaque tir (compensation du ping)
	  • Death            mort en arène : vue du tueur 5 s + bande d'infos + respawn
	  • Respawn          respawn géré par le système (garde ton temps de respawn normal)
	  • Ragdoll          le corps tombe en ragdoll à la mort
	  • Vignette         bords rouges discrets quand tu es blessé
	  • Leaderboard      classement des kills de l'arène (haut à droite)
	  • Killfeed         3 lignes de kills sous le classement
	  • MultiKill        DOUBLE KILL / TRIPLE KILL… (série tant que tu ne meurs pas)
	  • RoundWinner      🏆 gagnant de la manche (le plus de kills) + wins dans le profil + écran de vote
	  • HandlingSounds   sons de manipulation (visée, sprint)
	  • WallPose         arme relevée contre un mur (et tir bloqué)
]]

local S = {}

-- 🔌 interrupteur général : false = tous les ajouts de combat coupés d'un coup
S.Enabled = true

---------------------------------------------------------------------
-- 🎮 MANETTE
---------------------------------------------------------------------
S.Gamepad = {
	Enabled = true,

	-- boutons (style Fortnite) — noms Roblox : ButtonR2 = R2 / RT, ButtonX = Carré / X …
	Fire       = Enum.KeyCode.ButtonR2,   -- R2 / RT       tirer
	Aim        = Enum.KeyCode.ButtonL2,   -- L2 / LT       viser (maintenir)
	Reload     = Enum.KeyCode.ButtonX,    -- Carré / X     recharger
	NextWeapon = Enum.KeyCode.ButtonR1,   -- R1 / RB       arme suivante
	PrevWeapon = Enum.KeyCode.ButtonL1,   -- L1 / LB       arme précédente
	Slide      = Enum.KeyCode.ButtonB,    -- Rond / B      slide (R3 marche toujours aussi)
	Inspect    = Enum.KeyCode.DPadUp,     -- Croix ↑       inspecter
	ToggleView = Enum.KeyCode.DPadLeft,   -- Croix ←       changer de vue (→ = quitter l'arène)
	-- (Sprint = L3 et Slide = R3 restent réglés dans ton WeaponMechanics)

	-- changement d'arme R1 / L1 :
	--   "Auto"   = seulement si le sac à dos Roblox est désactivé (sinon Roblox le fait déjà)
	--   "Always" = toujours géré ici      "Off" = jamais
	WeaponSwitch = "Auto",

	-- caméra 3e personne épaule (vue B) au stick droit
	StickYawSpeed   = 3.2,    -- radians / seconde à fond
	StickPitchSpeed = 2.2,
	StickDeadzone   = 0.15,
	StickCurve      = 1.7,    -- > 1 = plus précis au centre du stick

	-- 🎯 aide à la visée LÉGÈRE : seulement un ralentissement quand le viseur
	--    passe sur un ennemi (aucune attraction, rien ne bouge tout seul)
	AimSlowdown = {
		Enabled     = true,
		Strength    = 0.45,   -- 0.45 = la caméra tourne 45 % moins vite pile sur la cible
		AimStrength = 0.55,   -- pareil mais en visée (L2)
		RadiusPx    = 70,     -- rayon autour du viseur où ça agit (pixels, écran 1080p)
		MaxDistance = 350,    -- studs
	},

	-- icônes PlayStation / Xbox à la place des touches clavier dans ta liste de contrôles
	ShowButtonIcons = true,
}

---------------------------------------------------------------------
-- 📱 VUE MOBILE
---------------------------------------------------------------------
-- glisser n'importe où (côté gauche compris) tourne la vue, sauf sur le joystick et les boutons
S.MobileLookAnywhere = true
-- (l'aim assist mobile se règle dans TON WeaponFeelConfig > Assist : TrackingRadius / TrackingStrength)

---------------------------------------------------------------------
-- 🎯 DÉGÂTS PAR ZONE
---------------------------------------------------------------------
S.ZoneDamage = {
	Enabled = false,   -- plus de réduction par zone : bras, jambes, torse = mêmes dégâts
	-- la tête garde TON multiplicateur de headshot (HeadshotMultiplier de chaque arme)
	Torso = 1.0,
	Arm   = 1.0,
	Leg   = 0.75,
	-- armes SANS dégâts par zone (le headshot reste) — nom du Tool, skins compris (Sniper_xxx)
	DisabledWeapons = { "Sniper" },
	-- (tu peux aussi mettre l'attribut ZoneDamage = false directement sur un Tool)
}

---------------------------------------------------------------------
-- 🛡️ VALIDATION DES TIRS PAR LE SERVEUR (compensation du ping)
---------------------------------------------------------------------
S.HitValidation = {
	Enabled = true,
	-- le serveur « remonte le temps » de 400 ms max pour voir ce que le tireur voyait.
	-- Jusqu'à ~300 ms de ping c'est parfaitement juste ; au-delà le laggeur doit viser un peu plus juste,
	-- et un tir sur quelqu'un déjà à couvert depuis plus de 400 ms est refusé.
	MaxRewind      = 0.40,
	InterpDelay    = 0.10,   -- retard d'affichage des autres joueurs chez Roblox (≈ 0.1 s)
	Tolerance      = 1.25,   -- marge autour du corps (studs)
	SpeedTolerance = 0.04,   -- marge en plus selon la vitesse de la cible (studs par stud/s)
	MuzzleMaxDistance = 12,  -- le canon annoncé doit être près du tireur (studs)
	CheckWalls     = true,   -- refuse un tir qui traverse un mur
	-- false = hitmarker / son de touche / dégâts / flash s'affichent TOUT DE SUITE au toucher
	-- (si le serveur refuse le tir, seuls les dégâts ne sont pas infligés).
	-- true = tout attend la confirmation du serveur.
	WaitServerConfirm = false,
	-- armes à explosion : pas de validation de balle (le RPG garde son système)
	ExplosiveWeapons = { "RPG" },
	-- refuse les dégâts d'une arme à balles qui n'envoie pas les infos du tir
	-- (= WeaponController pas à jour). Mets false si tu as une vieille arme spéciale.
	RequireHitInfo = true,
	Debug = false,           -- true = raison de chaque tir refusé dans l'Output (Studio)
}

---------------------------------------------------------------------
-- 💀 MORT : VUE DU TUEUR + BANDE D'INFOS
---------------------------------------------------------------------
S.Death = {
	Enabled      = true,
	OnlyInArena  = true,     -- seulement quand tu meurs en arène (attribut InArena)
	SpectateTime = 5,        -- secondes de vue du tueur avant le respawn automatique
	SkipDelay    = 0.4,      -- délai avant de pouvoir skip (évite un skip avec le clic de tir)
	StreamRate   = 30,       -- images / seconde envoyées par le tueur (sa caméra + bras + arme + pièces)
	ViewDelay    = 0.12,     -- petit tampon pour une vue fluide
	ShowKillerViewmodel = true,
	-- ce que tu vois du tueur, EXACTEMENT comme lui :
	KillerHUD    = true,     -- son viseur, ses hitmarkers, sa lunette, ses munitions / rechargement
	KillerFX     = true,     -- son flash de bouche (sur SON arme 1re personne), douilles, traçantes, lumières
	KillerSounds = true,     -- les sons que lui seul entend (touche, kill, manipulation…)
	KillerPopups = true,     -- ses chiffres de dégâts et le flash blanc sur ses cibles

	Frame = {
		Title        = "KILLED BY",
		RespawnText  = "Respawn",
		TapText      = "Tap to respawn",   -- mobile
		ShowAvatar   = true,
		ShowHealth   = true,               -- PV qui restaient au tueur
		ShowDistance = true,
		ShowHeadshot = true,
		Units        = "m",                -- texte après la distance (1 stud affiché = 1 m)
		VipTheme     = true,               -- thème doré si le TUEUR est VIP
		VipPassId    = 1891589121,
		GunFacesRight = true,              -- canon de l'arme 3D vers la droite
	},
}

---------------------------------------------------------------------
-- ♻️ RESPAWN
---------------------------------------------------------------------
S.Respawn = {
	-- true = le système gère le respawn (nécessaire pour la vue du tueur + skip) :
	-- toutes les autres morts gardent EXACTEMENT ton temps de respawn actuel.
	Manage = true,
	NormalTime = nil,   -- nil = le Players.RespawnTime réglé dans ton jeu
}

---------------------------------------------------------------------
-- 🪆 RAGDOLL
---------------------------------------------------------------------
S.Ragdoll = {
	Enabled     = true,
	OnlyInArena = false,     -- true = ragdoll seulement en arène
	Impulse     = 38,        -- poussée de la balle (vitesse en studs/s)
	HeadshotImpulse = 52,
	UpImpulse   = 10,
}

---------------------------------------------------------------------
-- 🩸 VIGNETTE ROUGE (discrète)
---------------------------------------------------------------------
S.Vignette = {
	Enabled       = true,
	Color         = Color3.fromRGB(170, 18, 18),
	FlashOnDamage = true,
	FlashStrength = 0.32,    -- 0..1 (intensité max d'un flash)
	FlashTime     = 0.45,
	LowHealthAt   = 0.30,    -- sous 30 % des PV max
	LowHealthStrength = 0.42,
	PulseSpeed    = 1.3,     -- battements / seconde
	Thickness     = 0.16,    -- épaisseur des bords (fraction de l'écran)
}

---------------------------------------------------------------------
-- 🏆 CLASSEMENT + KILLFEED (haut à droite, seulement en arène)
---------------------------------------------------------------------
S.Leaderboard = {
	Enabled = false,         -- classement TOP KILLS désactivé (pas de place à l'écran)
	Top     = 3,
	ShowMe  = true,          -- ta ligne en plus si tu n'es pas dans le top
	Title   = "TOP KILLS",
}
S.Killfeed = {
	Enabled  = true,
	MaxLines = 3,
	LineTime = 4,
}

---------------------------------------------------------------------
-- 🖥️ INTERFACE PVP (script ArenaHUD)
---------------------------------------------------------------------
S.ArenaHUD = {
	Enabled = true,
	-- haut de l'écran : REWARDED KILLS | NEXT MAP, puis les photos des joueurs + leurs kills sur la manche
	MaxPlayers = 8,              -- photos max (toi toujours dedans)
	VipPassId  = 1891589121,     -- bouton + de la case Rewarded Kills
	FallbackMax = 100,           -- limite affichée tant que l'attribut MaxKills n'est pas arrivé
	HideOldRewardedKills = true, -- cache ta case « Daily Rewarded Kills » d'origine (# Stage > Frame2)
	HideOldNextMap = true,       -- cache ta pastille « Next Map in » d'origine
	AvoidGuis = {},              -- noms d'autres UI du haut à ne jamais recouvrir (streak / spin déjà gérés)
	-- notifications de kill sous le bouton Exit Arena
	KillNotifs = {
		Enabled  = true,
		Max      = 4,
		HoldTime = 4,            -- secondes
		KillerSide = "Left",     -- "Left" : tueur à gauche (vert), arme → mort à droite (rouge) | "Right" : inversé
		Opacity  = 0.45,         -- opacité du fond et des dégradés (1 = plein, 0.45 = discret)
	},
}

---------------------------------------------------------------------
-- 💥 FLASH DE BOUCHE (module MuzzleFX) — le flash Blender de la M4A1 sur toutes les armes
---------------------------------------------------------------------
S.MuzzleFX = {
	Enabled = true,
	ReplaceOld = true,          -- retire les anciennes particules de bouche (MFlash, MSmoke…) : pas de doublon
	RemoteLight = true,         -- petite lumière au flash des autres joueurs (PC ; jamais sur mobile)
	-- mêmes valeurs que le flash de la M4A1 (GunKit) :
	Scale = 1.7, Thickness = 1.6, Duration = 0.06, FPScale = 1.0, Brightness = 1.0,
	Glow = true, RollJitter = 6, AdsScale = 0.45, AdsBrightness = 0.55,
	-- armes SANS ce flash (elles gardent le leur) : ex. RPG = false   (le lance-roquette est déjà exclu)
	Weapons = {
		-- RPG = false,
	},
}

---------------------------------------------------------------------
-- 🔥 MULTI-KILLS — la série continue TANT QUE TU NE MEURS PAS (plus aucun délai)
---------------------------------------------------------------------
S.MultiKill = {
	Enabled  = true,
	ResetOnDeath      = true,   -- true = série jusqu'à ta mort | false = ancien système (Window secondes)
	ResetOnLeaveArena = true,   -- sortir de l'arène remet la série à 0
	Window   = 4,               -- (seulement si ResetOnDeath = false)
	ShowTime = 1.5,             -- secondes d'affichage du texte
	Names = {
		[2] = "DOUBLE KILL", [3] = "TRIPLE KILL", [4] = "QUADRA KILL", [5] = "PENTA KILL",
		[6] = "RAMPAGE", [7] = "UNSTOPPABLE", [8] = "GODLIKE",
	},
	More  = "%d KILL STREAK",   -- au-delà
	Sound     = "7968069420",          -- rbxassetid du son (vide = pas de son)
	Volume    = 0.35,
	PitchStep = 0.06,        -- le son monte d'un cran à chaque kill de la série
	MaxPitch  = 1.45,
}

---------------------------------------------------------------------
-- ✅ CONFIRMATION DE KILL — un kill simple affiche un texte sous le viseur
--    (même style que DOUBLE KILL, en plus sobre ; au 2e kill de la série, le MultiKill prend le relais)
---------------------------------------------------------------------
S.KillConfirm = {
	Enabled     = true,          -- false = complètement coupé
	OnlyInArena = true,
	Text        = "ELIMINATED",
	TextSize    = 22,            -- (DOUBLE KILL = 30) ; mobile = × 0.85
	Color       = Color3.fromRGB(235, 235, 235),
	Punch       = 1.12,          -- grossissement de départ (DOUBLE KILL = 1.3)
	Underline   = true,          -- petit trait sous le texte, plus court et plus fin
	ShowTime    = 0.9,           -- secondes à l'écran (DOUBLE KILL = 1.5)
}

---------------------------------------------------------------------
-- 🏆 GAGNANT DE LA MANCHE (map) — le plus de kills quand le compte à rebours de la map se termine
--    • +1 win dans son profil (DataStore « ArenaWins_v1 », lu aussi par les fiches hors ligne)
--    • au vote de la map suivante : son perso en pose de conquérant, l'arme avec laquelle il a fait le plus
--      de kills levée au ciel, caméra cinématique, stats de la manche en grand
--    (les kills de la manche repartent à 0 au début de chaque manche)
---------------------------------------------------------------------
S.RoundWinner = {
	Enabled   = true,
	MinKills  = 1,                            -- en dessous : aucun gagnant pour cette manche
	ShowInVote = true,                         -- colonne du gagnant dans l'écran de vote
	HoldWeapon = true,                         -- son arme favorite de la manche dans les mains
	WinsStore = "ArenaWins_v1",                -- OrderedDataStore des wins (ne change plus après la sortie)
	TrophyIcon = "",                           -- rbxassetid de ton icône de win ("" = 🏆)
}

---------------------------------------------------------------------
-- 🔊 SONS DE MANIPULATION (entendus par toi seulement)
---------------------------------------------------------------------
S.HandlingSounds = {
	Enabled = true,
	Volume  = 0.3,
	-- mets un rbxassetid://… ; vide = silencieux
	-- (saut, atterrissage et slide : tu as déjà tes propres sons, ils ne sont pas joués ici)
	Sounds = {
		AimIn       = "8169250164",   -- tissu + petit clic quand tu épaules
		AimOut      = "8169248194",   -- tissu plus léger quand tu baisses l'arme
		SprintStart = "",   -- l'arme qui bouge / sangle
		SprintStop  = "",
	},
	PitchJitter  = 0.06,
	-- sons propres à une arme : PerWeapon = { Magnum44 = { AimIn = "rbxassetid://…" } }
	PerWeapon = {},
}

---------------------------------------------------------------------
-- 🧱 ARME CONTRE UN MUR
---------------------------------------------------------------------
S.WallPose = {
	Enabled   = true,
	Third     = false,       -- false = bras PAS levés en 3e personne · true = levés
	BlockFire = false,        -- pas de tir tant que l'arme est relevée
	Margin    = 0.35,        -- distance en plus devant le canon (studs)
	Raise     = 38,          -- degrés : le canon se relève
	Back      = 0.30,        -- studs : l'arme recule vers toi
	Down      = 0.08,
	Roll      = 8,
	Speed     = 14,          -- vitesse d'entrée / sortie
}

---------------------------------------------------------------------
-- 🎨 STYLE COMMUN (bande de mort + classement + killfeed)
---------------------------------------------------------------------
S.Style = {
	FontFamily = "rbxasset://fonts/families/BuilderSans.json",
	White = Color3.fromRGB(255, 255, 255),
	Sub   = Color3.fromRGB(165, 175, 192),
	Dark  = Color3.fromRGB(9, 11, 16),
	Me    = Color3.fromRGB(255, 214, 92),    -- ta ligne / tes kills
	Head  = Color3.fromRGB(255, 92, 92),     -- headshot
	Gold      = Color3.fromRGB(255, 210, 60),
	GoldSoft  = Color3.fromRGB(255, 236, 160),
	GoldDeep  = Color3.fromRGB(190, 130, 15),
	Crown     = "rbxassetid://93460778559039",
}

return S