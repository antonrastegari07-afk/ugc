--════════════════════════════════════════════════════════════════════════════
-- 🛡️ ANTI-FLY / ANTI-TP / ANTI-SPEED — VERSION 4
--
--  🆕 V4 (audit complet du jeu, voir LISEZMOI.md du dossier anticheat_v4) :
--    • DISCRET : le joueur ne voit JAMAIS ses détections ni ses warnings
--      (aucune carte, aucun retour en arrière, aucun kick d'avertissement).
--    • Chaque warning EXPIRE tout seul, X jours après avoir été reçu.
--    • Téléportations faites par un script serveur reconnues automatiquement
--      (portails, checkpoints, arène, cachette, admin, fin d'obby…).
--    • Tapis roulants / plateformes mobiles : la vitesse du sol est ajoutée.
--    • Gravité basse (Admin Abuse) : le vol stationnaire tient compte de la gravité.
--    • Tyrolienne : l'exemption ne vaut que près d'une corde (anti-abus).
--    • Météo Admin Abuse : PausePhysics(true) met l'analyse en pause (15 min max).
--    • Raison de sanction lisible et précise, enregistrée dans la fiche.
--
--  📍 OÙ ? ServerScriptService (remplace intégralement ton ancien script).
--  🤝 COMPAGNONS OBLIGATOIRES
--       • AntiCheat_UGCRestrict.server.lua  (ServerScriptService)
--       • AntiFlyTP_Client.lua              (StarterPlayerScripts)
--
--  ⚠️ CE SCRIPT NE DÉCIDE PLUS S'IL DOIT PUNIR.
--     Le mode (ban / ugc) et la case shadow vivent dans AntiCheat_UGCRestrict,
--     persistés et synchronisés sur tous tes serveurs. Ici on ne fait que
--     détecter, puis demander à cette config ce qu'il faut faire. Un seul
--     endroit décide → plus jamais deux scripts qui se contredisent.
--
--  CE QUI A CHANGÉ, ET POURQUOI TES JOUEURS HONNÊTES ÉTAIENT FLAGGÉS
--     Chaque correction est marquée « 🩹 FIX n ». Le détail complet est dans
--     ANALYSE_FAUX_POSITIFS.md. En résumé :
--       1. La détection de téléport comparait un déplacement à une vitesse
--          mesurée 0,25 s plus tôt. À l'atterrissage d'une longue chute,
--          l'écart dépassait le seuil : tout obby produisait des faux TP.
--       2. Le vol stationnaire s'accumulait pendant un simple arc de saut.
--          Un launcher un peu puissant suffisait à déclencher.
--       3. Le ragdoll de ta gant-claque et les BodyVelocity de propulsion
--          n'avaient que 2 s de grâce, alors que le vol dure bien plus.
--       4. Le gravity coil était reconnu par son NOM. Un coil renommé, ou
--          la force résiduelle de ton bug, et le joueur volait « sans coil ».
--          On regarde maintenant la PHYSIQUE, pas le nom.
--       5. La whitelist admin était commentée : tes admins étaient analysés
--          comme n'importe qui, y compris quand ils se téléportaient.
--       6. Les strikes ne redescendaient jamais tout seuls : un joueur
--          honnête les accumulait sur des heures jusqu'au warning.
--════════════════════════════════════════════════════════════════════════════

local Players            = game:GetService("Players")
local DataStoreService   = game:GetService("DataStoreService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")

--════════════════════════════════════════════════════════════════════════════
-- ⚙️ CONFIGURATION
--   ⚠️ NE RÈGLE RIEN ICI : tout se règle dans ServerScriptService ▸
--      ANTICHEAT_CONFIG (sections ⑧ à ⑩). Les valeurs ci-dessous ne servent
--      que de secours si ce fichier est absent.
--════════════════════════════════════════════════════════════════════════════
local CONFIG = {
	-- ────────────────────────────────────────────────────────────────
	-- 🎚️ PERMISSIVITÉ — le seul réglage à toucher dans 90 % des cas
	--   "lenient" = très permissif · "balanced" = recommandé · "strict" = agressif
	--   "custom"  = ignore le preset, garde les valeurs détaillées ci-dessous
	-- ────────────────────────────────────────────────────────────────
	Preset = "balanced",

	-- Interrupteur maître de l'ANALYSE. À false, plus rien n'est mesuré.
	-- (Ce n'est PAS l'interrupteur des sanctions : ça, c'est la case shadow
	--  du panel, qui vit dans AntiCheat_UGCRestrict.)
	Enabled     = true,
	VerboseLogs = true,

	-- ────────────────────────────────────────────────────────────────
	-- 🤍 WHITELIST — jamais analysés, jamais logués
	--   🩹 FIX 5 : les admins du panel sont ajoutés AUTOMATIQUEMENT au
	--   démarrage (via _G.AC_ADMIN_IDS). Tu n'as plus à les recopier ici,
	--   et surtout tu ne peux plus oublier de les décommenter.
	-- ────────────────────────────────────────────────────────────────
	Whitelist = { UserIds = {} },

	Sampling = {
		Interval = 0.25,
		-- 🩹 FIX 6 : si l'écart entre deux mesures dépasse ça, le serveur a
		-- laggé et toute extrapolation est du bruit. On resynchronise sans
		-- juger, au lieu de compter un téléport imaginaire.
		MaxUsableDelta = 0.85,
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🕊️ VOL
	-- ────────────────────────────────────────────────────────────────
	Fly = {
		Enabled       = true,
		DetectHover   = true,   -- vol stationnaire
		DetectAscent  = false,  -- longue montée (bruyant en obby, laissé off)
		DetectUpSpeed = false,  -- haute vitesse verticale (idem)

		MaxHoverTime  = 2.5,

		-- 🩹 FIX 2 — LE correctif du faux positif de vol.
		--   Avant : « vitesse verticale au-dessus de -4 » — donc TOUTE la
		--   montée d'un saut comptait, et un arc de launcher de 3 s
		--   déclenchait. Maintenant on exige que le joueur soit VRAIMENT
		--   immobile en l'air : |vitesse verticale| sous HoverBandY.
		--   Un joueur en saut traverse cette bande en ~0,2 s au sommet.
		--   Un joueur qui vole y reste indéfiniment.
		HoverBandY     = 6,
		-- Et qu'il soit réellement en hauteur : à 3 studs du sol, un pas sur
		-- une marche suffit à passer une frame « en l'air ».
		HoverMinHeight = 11,

		AscentMultiplier     = 2.0,
		AscentFlatBonus      = 8,
		MaxUpSpeedMultiplier = 1.6,
		MaxUpSpeedFlat       = 15,
		UpSpeedSamples       = 4,

		TreatClimbingAsGround = true,
		TreatSwimmingAsGround = true,
		GroundRayDistance     = 6.5,
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🚀 TÉLÉPORTATION
	-- ────────────────────────────────────────────────────────────────
	Teleport = {
		Enabled = true,

		-- 🩹 FIX 1 — seuils SÉPARÉS horizontal / vertical.
		--   Le vertical est le seul à souffrir de la gravité et des
		--   atterrissages, et c'est de là que venaient presque tous les faux
		--   TP. On lui donne sa propre tolérance, calculée en plus à chaque
		--   mesure en fonction de la vitesse de chute réelle.
		MaxPredictionError  = 65,   -- horizontal
		MaxVerticalError    = 90,   -- vertical (base, encore élargie en vol)

		-- On ne regarde même pas les petits sauts de position : en dessous,
		-- c'est du jitter réseau, jamais un téléport utile à un tricheur.
		MinTeleportDistance = 28,

		IgnoreIfVelocityConsistent = true,
		VelocityConsistencyRatio   = 0.55,

		SafeDestinationRadius = 22,
		SafePartNames = {
			"FirstSpawn",
			"TpRebirth",
			"Portail2",
		},
		SafePartPatterns = {},
		SafeIncludeSpawnLocations = true,

		CheckpointDestinations = "limited",
		MaxCheckpointTeleportsPerMinute = 6,
		CheckpointPattern = "^[Cc]heckpoint%d+$",
	},

	-- ────────────────────────────────────────────────────────────────
	-- 💨 VITESSE HORIZONTALE
	-- ────────────────────────────────────────────────────────────────
	Speed = {
		Enabled              = true,
		Tolerance            = 1.7,
		FlatBonus            = 10,
		-- 🩹 FIX 3 : ces mesures doivent être CONSÉCUTIVES. Avant, le
		-- compteur ne redescendait que de 1 par mesure propre : un joueur
		-- propulsé plusieurs fois dans une même minute finissait par
		-- atteindre 8 sans jamais avoir été rapide deux secondes d'affilée.
		SustainedSamples     = 8,
		MinBaselineWalkSpeed = 16,
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🧰 OUTILS LÉGITIMES
	-- ────────────────────────────────────────────────────────────────
	LegitTools = {
		FlyTools = { ["Jetpack"] = { MaxSpeed = 200 } },
		FlyToolMarkers = { "tube", "tube2" },
		FlyToolDefaultProfile = { MaxSpeed = 200 },

		GravityTools = {
			["Gravity Coil"] = true,
			["GravityCoil"]  = true,
			["Grav Coil"]    = true,
		},
		GravityProfile = { MaxHoverTime = 8, AscentFlat = 110, MaxUpSpeed = 130 },

		SpeedTools = { ["Speed Coil"] = 60, ["SpeedCoil"] = 60 },

		FusionTools = {
			["FusionCoil"] = {
				Speed = 60,
				GravityProfile = { MaxHoverTime = 8, AscentFlat = 130, MaxUpSpeed = 140 },
			},
		},

		ToolTrailingGrace = 4,

		-- 🩹 FIX 4 — DÉTECTION PHYSIQUE DE L'ANTI-GRAVITÉ.
		--   On ne se fie plus au nom du Tool. Dès qu'une force qui pousse
		--   vers le haut existe sur le personnage (BodyForce, VectorForce…),
		--   on applique le profil gravité. Ça couvre :
		--     • un coil renommé,
		--     • un coil donné par un admin,
		--     • et surtout la force RÉSIDUELLE de ton bug de coil, qui
		--       faisait tomber le joueur au ralenti et le faisait flagger.
		--   Le vrai correctif du coil est dans GravityCoil_Fixed.lua ; celui-ci
		--   garantit qu'aucun joueur n'est puni même si un coil buggé traîne.
		DetectAntiGravityForce = true,
		AntiGravityGrace       = 5,
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🏷️ ATTRIBUTS LÉGITIMES
	-- ────────────────────────────────────────────────────────────────
	LegitAttributes = {
		FullBypass = { "Ziplining", "JustRebirthed", "AdminFly" },
		WatchForTrailing = { "Ziplining", "JustRebirthed", "AdminFly", "InArena" },
		TrailingGrace = 6,
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🎯 PROPULSIONS (launchers, claques, explosions…)
	-- ────────────────────────────────────────────────────────────────
	Launchers = {
		AutoGraceOnMover = true,
		-- 🩹 FIX 3 : 2 s ne couvraient pas un vol de propulsion. Ta gant-claque
		-- détruit son BodyVelocity au bout de 0,05 s, mais la victime continue
		-- de voler 4 à 6 s : elle était flaggée en SPEED puis en FLY_HOVER.
		MoverGrace       = 6,
		MoverClasses = {
			"LinearVelocity", "BodyVelocity", "BodyThrust", "VectorForce",
			"BodyForce", "AlignPosition", "BodyPosition", "AngularVelocity",
			"BodyAngularVelocity", "AlignOrientation",
		},

		-- 🩹 FIX 7 — DÉTECTION DE PROPULSION SANS MOVER.
		--   Beaucoup de launchers d'obby écrivent directement
		--   hrp.AssemblyLinearVelocity : aucun objet n'apparaît sur le
		--   personnage, donc aucune grâce n'était accordée. On regarde
		--   maintenant la vitesse brute : au-delà de ce seuil, on considère
		--   que le joueur SUBIT quelque chose et on relâche vol + téléport
		--   (mais PAS la vitesse : un speed-hack reste détecté).
		VelocitySpikeThreshold = 130,
		VelocitySpikeGrace     = 4,
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🤸 RAGDOLL / PLATFORMSTAND
	--   🩹 FIX 8 : pendant un ragdoll, le Humanoid n'a plus la main sur le
	--   personnage. Toute mesure est du bruit physique. Ta gant-claque
	--   ragdollise pendant 1 s puis la victime plane : ça produisait du
	--   TELEPORT, du SPEED et du FLY_HOVER sur des joueurs qui subissaient.
	-- ────────────────────────────────────────────────────────────────
	Ragdoll = {
		SkipWhileRagdolled = true,
		GraceAfter         = 4,   -- s après la reprise de contrôle
		States = {
			[Enum.HumanoidStateType.Physics]     = true,
			[Enum.HumanoidStateType.FallingDown] = true,
			[Enum.HumanoidStateType.Ragdoll]     = true,
			[Enum.HumanoidStateType.GettingUp]   = true,
		},
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🥊 ARÈNE 1v1
	-- ────────────────────────────────────────────────────────────────
	Arena = {
		SkipTeleport = true,
		SkipSpeed    = true,
		FlyMode      = "relaxed",
		RelaxedHoverTime  = 6,
		RelaxedAscentFlat = 80,
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🏃 MOUVEMENT PVP (MovementBoost : gravité, slide, élan, double saut)
	--   L'anti-cheat lit MovementBoostConfig et élargit ses limites
	--   UNIQUEMENT quand le système est actif pour le joueur (décidé par
	--   le serveur : InArena + attribut workspace, infalsifiables).
	-- ────────────────────────────────────────────────────────────────
	MovementBoost = {
		Enabled     = true,
		SlideSpeed  = 40,   -- Slide.Speed de ton MechanicsClient
		SpeedMargin = 6,    -- marge en studs/s ajoutée à la vitesse max calculée
		SwitchGrace = 4,    -- grâce (s) quand l'attribut workspace MovementBoost change
	},

	-- ────────────────────────────────────────────────────────────────
	-- ⏳ GRÂCES
	-- ────────────────────────────────────────────────────────────────
	Grace = {
		SpawnSeconds           = 12,
		DeathSeconds           = 5,
		ProductPurchaseSeconds = 8,
		AdminActionSeconds     = 10,
		RemoteHookSeconds      = 5,
		MinDelayBetweenRemoteGraces = 8,
		-- 🩹 FIX 9 : après un atterrissage, le personnage se stabilise
		-- (rebond, glissade sur pente). On laisse passer ce court instant.
		LandingSeconds         = 0.8,
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🎯 CERTITUDE — LE FILTRE QUI TUE LES FAUX POSITIFS
	--
	--  Une détection n'est plus un verdict. C'est un signal, auquel on attribue
	--  un pourcentage de certitude entre 0 et 99. Rien n'est jamais à 100 :
	--  prétendre à la certitude absolue sur une mesure physique bruitée serait
	--  malhonnête, et c'est exactement ce qui produit des bans injustes.
	--
	--  Le score part d'une base propre au type de signal, puis monte ou descend
	--  selon une douzaine de facteurs de contexte. En dessous du seuil « à
	--  compter », la détection est enregistrée pour que tu puisses la lire dans
	--  le panel, mais elle ne coûte AUCUN strike au joueur.
	--
	--  Concrètement : un joueur qui se fait claquer, qui rebondit sur un
	--  launcher ou qui subit un pic de lag produit des signaux à 20-40 % — ils
	--  n'atteignent jamais le seuil. Un joueur qui vole en ligne droite pendant
	--  dix secondes, sans force sur lui, sans grâce, avec deux types de signaux
	--  différents, monte à 90 %+ en quelques secondes.
	-- ────────────────────────────────────────────────────────────────
	Confidence = {
		Enabled = true,

		--  Fiabilité intrinsèque de chaque signal, avant tout contexte.
		--  Un HumanoidState « Flying » ne s'obtient quasiment pas par accident.
		--  Une vitesse horizontale, en revanche, est le signal le plus bruité
		--  d'un obby : pentes, glissades, propulsions.
		Base = {
			FLY_STATE   = 72,
			FLY_HOVER   = 52,
			TELEPORT    = 46,
			FLY_UPSPEED = 46,
			FLY_ASCENT  = 40,
			SPEED       = 38,
		},

		--  Bonus : de combien le joueur dépasse le seuil. Frôler la limite ne
		--  prouve rien ; la doubler est difficile à faire par accident.
		MarginMax        = 25,   -- atteint à 2× le seuil
		--  Bonus : combien de temps le comportement a duré (vol stationnaire).
		DurationMax      = 15,
		--  Bonus : contexte totalement propre (rien qui pourrait expliquer).
		CleanContext     = 15,
		--  Bonus : répétition du même signal dans la dernière minute.
		RepeatPer        = 5,
		RepeatMax        = 20,
		--  Bonus : plusieurs types de signaux différents en 5 minutes.
		--  Un bug produit toujours le même symptôme ; un tricheur en produit
		--  plusieurs, parce qu'il fait plusieurs choses anormales à la fois.
		DiversityPer     = 9,
		DiversityMax     = 18,
		--  Bonus : warnings déjà persistés sur le compte.
		HistoryBonus     = 10,
		--  Bonus : pas de contact avec le sol depuis longtemps (vol).
		NoGroundSeconds  = 15,
		NoGroundBonus    = 10,

		--  Pénalités : tout ce qui pourrait expliquer la mesure autrement.
		PenaltyLongDt      = 15,   -- mesure prise sur un intervalle anormal
		PenaltyRecentGrace = 25,   -- une grâce vient tout juste d'expirer
		PenaltyRecentSpawn = 15,   -- le joueur vient d'apparaître
		PenaltyRecentForce = 20,   -- une force a été vue sur lui récemment
		PenaltyRecentLaunch= 25,   -- il a été propulsé récemment
		PenaltyRecentRagdoll = 25, -- il sortait d'un ragdoll
		PenaltyFirstEver   = 10,   -- toute première détection de sa session
		--  Fenêtres pendant lesquelles ces pénalités s'appliquent (secondes).
		RecentWindow       = 12,

		--  Plafond absolu. On ne dépasse jamais.
		Ceiling = 99,
	},

	-- ────────────────────────────────────────────────────────────────
	-- ⚖️ SANCTIONS
	-- ────────────────────────────────────────────────────────────────
	Punishment = {
		RubberBand        = true,
		NudgeOnDetection  = true,
		StrikesPerWarning = 3,
		StrikeDecaySeconds = 120,
		EscalationCooldown = 4,

		-- 🩹 FIX 10 : les strikes redescendent maintenant TOUT SEULS, sans
		-- attendre une nouvelle détection. Avant, un joueur à 2 strikes les
		-- gardait des heures et le moindre incident déclenchait un warning.
		PassiveDecay = true,

		StrikeWeights = {
			FLY_HOVER = 1, FLY_ASCENT = 1, FLY_UPSPEED = 1,
			FLY_STATE = 2, TELEPORT = 1, SPEED = 1,
		},

		-- Mode "ban" uniquement.
		WarningActions = { [1] = "notify", [2] = "notify", [3] = "kick", [4] = "kick" },
		BanAtWarning   = 5,

		WarningExpiryDays = 7,
		WarningExpiryMode = "sliding",
		UseRobloxBanAPI   = false,
	},

	-- ────────────────────────────────────────────────────────────────
	-- 🆕 V4 — SOURCES DE MOUVEMENT LÉGITIMES DÉTECTÉES AUTOMATIQUEMENT
	-- ────────────────────────────────────────────────────────────────
	--  Toute téléportation faite par un SCRIPT SERVEUR (portail, checkpoint,
	--  arène, cachette, commande admin, fin d'obby…) est reconnue toute seule :
	--  le serveur voit qu'il a écrit lui-même la position. Le client, lui, ne
	--  peut pas déclencher ce signal (ses déplacements arrivent par la physique).
	ServerMoves = { Enabled = true },

	--  Tapis roulants (« Hard obby part », 50 studs/s) et plateformes mobiles :
	--  la vitesse de la pièce sous les pieds est ajoutée à la vitesse permise,
	--  et gardée en mémoire un court instant après l'avoir quittée.
	Floor = { Enabled = true, Memory = 1.5 },

	--  Tyrolienne : l'attribut « Ziplining » n'exempte que si le joueur est
	--  réellement près d'une corde. Sinon, un tricheur qui accroche une
	--  tyrolienne puis n'envoie jamais « Stop » volait librement.
	Zipline = { Prefix = "Tirolienne", Rope = "Corde", MaxDist = 18 },

	--  Gravité réduite (météo Admin Abuse, jusqu'à 5) : un saut normal reste
	--  plus longtemps en l'air. La limite de vol stationnaire est agrandie
	--  d'autant (196.2 / gravité actuelle).
	ScaleHoverWithGravity = true,

	--  Pause globale demandée par la météo Admin Abuse (PausePhysics), puis
	--  quelques secondes de grâce après la fin.
	GlobalToleranceTrail = 6,

	DataStores = {
		Warnings = "AntiFlyTP_Warnings_v1",
		Bans     = "BannedPlayers",
	},

	Hooks = {
		HookAdminAction      = true,
		HookProductPurchases = true,
		RemoteGraceNames = {},
	},

	Messages = {
		NudgeTitle = "⚠️ Abnormal movement detected",
		NudgeBody  = "Fly / teleport behaviour was detected and reverted.\n"
			.. "Please stop — repeated detections lead to official warnings.",

		WarningTitle = "🚨 WARNING %d/%d — Fly / Teleport",
		WarningBody  = "Cheating (fly or teleport) was detected on your account.\n"
			.. "If you continue, your account will be sanctioned.\n\n"
			.. "⚠️ If you were NOT flying or teleporting, this may be a false "
			.. "detection — please contact our support team so we can fix it.",

		KickMessage = "🚨 WARNING %d/%d — Fly/Teleport detected repeatedly.\n\n"
			.. "You have been kicked as a final caution. You can rejoin, "
			.. "but the next warning will lead to a PERMANENT BAN.\n\n"
			.. "If you were NOT flying and you think this is an error, "
			.. "please contact our support team.",

		BanMessage = "🚫 PERMANENT BAN — Fly/Teleport exploiting (after %d warnings).\n\n"
			.. "You were warned and informed at every step.\n"
			.. "If you believe this is a mistake, please contact our support team.",
	},

	-- ────────────────────────────────────────────────────────────────
	-- 💾 STATISTIQUES PERSISTANTES (lues par le panel admin)
	--   ⚡ Aucune requête DataStore sur le chemin de détection : tout est
	--   accumulé en RAM et écrit en lots. Zéro latence ajoutée au jeu.
	-- ────────────────────────────────────────────────────────────────
	Stats = {
		Enabled         = true,
		MaxEvents       = 1500,
		FlushInterval   = 120,
		PerRequestDelay = 0.2,
		MaxRankFetch    = 50,
		StatsStore    = "AntiFlyTP_Stats_v1",
		RankDetStore  = "AntiFlyTP_RankDet_v1",
		RankWarnStore = "AntiFlyTP_RankWarn_v1",
		RankKickStore = "AntiFlyTP_RankKick_v1",
		RankBanStore  = "AntiFlyTP_RankBan_v1",
		RealWarnStore = "AntiFlyTP_RealWarn_v1",
		RealBanStore  = "AntiFlyTP_RealBan_v1",
	},
}

--════════════════════════════════════════════════════════════════════════════
-- 📄 LECTURE DE ANTICHEAT_CONFIG (ServerScriptService)
--    Chaque clé écrite dans le fichier remplace la valeur de secours
--    ci-dessus. La sévérité (Severite) s'applique ensuite, sauf "custom".
--════════════════════════════════════════════════════════════════════════════
do
	local SSS = game:GetService("ServerScriptService")
	local m = SSS:FindFirstChild("ANTICHEAT_CONFIG") or SSS:WaitForChild("ANTICHEAT_CONFIG", 10)
	local F
	if m and m:IsA("ModuleScript") then
		local ok, r = pcall(require, m)
		if ok and type(r) == "table" then F = r
		else warn("🛡️ [AntiFlyTP] ANTICHEAT_CONFIG illisible : " .. tostring(r)) end
	else
		warn("🛡️ [AntiFlyTP] ANTICHEAT_CONFIG introuvable dans ServerScriptService → valeurs de secours")
	end
	if F then
		local function copyInto(section, src)
			if type(src) ~= "table" then return end
			CONFIG[section] = CONFIG[section] or {}
			for k, v in pairs(src) do CONFIG[section][k] = v end
		end
		local D = (type(F.Detection) == "table") and F.Detection or {}
		local M = (type(F.MouvementsLegitimes) == "table") and F.MouvementsLegitimes or {}
		if D.AnalyseActive ~= nil then CONFIG.Enabled = (D.AnalyseActive == true) end
		if D.LogsDetailles ~= nil then CONFIG.VerboseLogs = (D.LogsDetailles == true) end
		if type(D.Severite) == "string" then CONFIG.Preset = D.Severite end
		for _, k in ipairs({ "Sampling", "Fly", "Teleport", "Speed", "Punishment", "Confidence" }) do
			copyInto(k, D[k])
		end
		for _, k in ipairs({ "LegitTools", "LegitAttributes", "Launchers", "Ragdoll", "Arena",
			"MovementBoost", "Grace", "Hooks", "ServerMoves", "Floor", "Zipline" }) do
			copyInto(k, M[k])
		end
		if M.ScaleHoverWithGravity ~= nil then CONFIG.ScaleHoverWithGravity = (M.ScaleHoverWithGravity == true) end
		if tonumber(M.GlobalToleranceTrail) then CONFIG.GlobalToleranceTrail = tonumber(M.GlobalToleranceTrail) end
		if type(F.JamaisAnalyses) == "table" then CONFIG.Whitelist.UserIds = F.JamaisAnalyses end
		print("🛡️ [AntiFlyTP] Réglages lus dans ANTICHEAT_CONFIG")
	end
end

--════════════════════════════════════════════════════════════════════════════
-- 🔌 LIEN AVEC LA CONFIG PARTAGÉE (mode + shadow)
--════════════════════════════════════════════════════════════════════════════
local function acShadow()
	if _G.ACConfig then
		local ok, v = pcall(_G.ACConfig.Shadow)
		if ok then return v == true end
	end
	--  Module absent ou pas encore chargé : on n'applique RIEN.
	--  Ne jamais punir sur une config qu'on n'a pas lue.
	return true
end

local function acShadowCorrect()
	if _G.ACConfig then
		local ok, v = pcall(_G.ACConfig.ShadowCorrect)
		if ok then return v == true end
	end
	return false
end

local function acMode()
	if _G.ACConfig then
		local ok, v = pcall(_G.ACConfig.Mode)
		if ok and (v == "ban" or v == "ugc") then return v end
	end
	return "ugc"
end

local function acWarningsToRestrict()
	if _G.ACConfig then
		local ok, v = pcall(_G.ACConfig.WarningsToRestrict)
		if ok and type(v) == "number" then return v end
	end
	return 2
end

--  👮 Les admins sont-ils analysés comme tout le monde ?
--     Par défaut OUI : c'est le seul réglage qui te dise honnêtement si ton
--     anti-cheat produit des faux positifs, puisque tu es le seul joueur dont
--     tu SAIS qu'il ne triche pas.
local function acAnalyzeAdmins()
	if _G.ACConfig and _G.ACConfig.AnalyzeAdmins then
		local ok, v = pcall(_G.ACConfig.AnalyzeAdmins)
		if ok then return v == true end
	end
	return true
end

local function acConf(which, fallback)
	if _G.ACConfig and _G.ACConfig[which] then
		local ok, v = pcall(_G.ACConfig[which])
		if ok and type(v) == "number" then return v end
	end
	return fallback
end

--════════════════════════════════════════════════════════════════════════════
-- ⚙️ FICHE DU MODE ACTIF
--    `acModeCfg()`        → la fiche du mode courant (ban ou ugc)
--    `acModeCfg("test")`  → la fiche du shadow
--
--    Retourne TOUJOURS une table. Si le module de config n'est pas encore
--    chargé, on renvoie une fiche vide : les appelants utilisent alors leurs
--    valeurs de repli, qui sont les plus douces.
--════════════════════════════════════════════════════════════════════════════
local EMPTY_MODE = {}
local function acModeCfg(which)
	if _G.ACConfig and _G.ACConfig.ModeCfg then
		local ok, v = pcall(_G.ACConfig.ModeCfg, which)
		if ok and type(v) == "table" then return v end
	end
	return EMPTY_MODE
end

--  Combien de warnings avant la sanction, pour le mode actif.
local function acWarningsToPunish()
	if _G.ACConfig and _G.ACConfig.WarningsToPunish then
		local ok, v = pcall(_G.ACConfig.WarningsToPunish)
		if ok and type(v) == "number" and v >= 1 then return math.floor(v) end
	end
	return acWarningsToRestrict()
end

--════════════════════════════════════════════════════════════════════════════
-- 💬 MESSAGES CONFIGURABLES
--    `acMsg("warnBody", vars)` rend le gabarit choisi dans le panel avec les
--    valeurs réelles. Si le module n'est pas chargé, on retombe sur les
--    textes en dur de CONFIG.Messages : le joueur voit toujours quelque
--    chose de sensé, jamais une chaîne vide.
--════════════════════════════════════════════════════════════════════════════
local function acMsg(key, vars, fallback)
	if _G.ACConfig and _G.ACConfig.Msg then
		local ok, v = pcall(_G.ACConfig.Msg, key, vars)
		if ok and type(v) == "string" and v:gsub("%s", "") ~= "" then return v end
	end
	return fallback or ""
end

--  Drapeaux de la section messages (activation, cadence, secret).
local function acMsgFlag(key, fallback)
	if _G.ACConfig and _G.ACConfig.MsgFlag then
		local ok, v = pcall(_G.ACConfig.MsgFlag, key)
		if ok and v ~= nil then return v end
	end
	return fallback
end

--  🤫 Discrétion : le joueur ne voit rien (ni carte, ni retour en arrière,
--     ni kick d'avertissement). Réglé dans le panel (⚙️ → 🤫 Discrétion).
--     Par défaut OUI, même si la config n'est pas encore lue.
local function acSilent()
	if _G.ACConfig and _G.ACConfig.Silent then
		local ok, v = pcall(_G.ACConfig.Silent)
		if ok and type(v) == "boolean" then return v end
	end
	return true
end

--  ⏳ Durée de vie d'un warning, en jours (0 = ne disparaît jamais).
--  🕛 Les warnings reçus AVANT cette date sont ignorés (0 = aucun).
--     Posé par « Activer les sanctions → ignorer les anciens warnings » ou
--     « Réinitialiser les warnings de tout le monde » dans le panel.
local function acCountFrom()
	if _G.ACConfig and _G.ACConfig.CountFrom then
		local ok, v = pcall(_G.ACConfig.CountFrom)
		if ok and type(v) == "number" then return v end
	end
	return 0
end

local function acWarnExpiryDays()
	if _G.ACConfig and _G.ACConfig.WarningExpiryDays then
		local ok, v = pcall(_G.ACConfig.WarningExpiryDays)
		if ok and type(v) == "number" and v >= 0 then return v end
	end
	return 30
end

--  Compat panel : « mode test » de l'ancien panneau = case shadow.
local function testActive() return acShadow() end

local function log(...)
	if CONFIG.VerboseLogs then print("🛡️ [AntiFlyTP]", ...) end
end

--════════════════════════════════════════════════════════════════════════════
-- 🎚️ PRESETS
--════════════════════════════════════════════════════════════════════════════
local PRESETS = {
	lenient = {
		Fly        = { MaxHoverTime = 4.0, HoverBandY = 8, HoverMinHeight = 14,
			AscentFlatBonus = 14, MaxUpSpeedFlat = 22, UpSpeedSamples = 6 },
		Teleport   = { MaxPredictionError = 95, MaxVerticalError = 130, MinTeleportDistance = 40 },
		Speed      = { Tolerance = 2.0, FlatBonus = 16, SustainedSamples = 12 },
		Punishment = {
			StrikesPerWarning = 5, EscalationCooldown = 6, StrikeDecaySeconds = 90,
			WarningActions = { [1]="notify",[2]="notify",[3]="notify",[4]="kick",[5]="kick",[6]="kick" },
			BanAtWarning = 7,
		},
	},
	balanced = {
		Fly        = { MaxHoverTime = 2.5, HoverBandY = 6, HoverMinHeight = 11,
			AscentFlatBonus = 8, MaxUpSpeedFlat = 15, UpSpeedSamples = 4 },
		Teleport   = { MaxPredictionError = 65, MaxVerticalError = 90, MinTeleportDistance = 28 },
		Speed      = { Tolerance = 1.7, FlatBonus = 10, SustainedSamples = 8 },
		Punishment = {
			StrikesPerWarning = 3, EscalationCooldown = 4, StrikeDecaySeconds = 120,
			WarningActions = { [1]="notify",[2]="notify",[3]="kick",[4]="kick" },
			BanAtWarning = 5,
		},
	},
	strict = {
		Fly        = { MaxHoverTime = 1.8, HoverBandY = 4, HoverMinHeight = 9,
			AscentFlatBonus = 5, MaxUpSpeedFlat = 10, UpSpeedSamples = 3 },
		Teleport   = { MaxPredictionError = 45, MaxVerticalError = 70, MinTeleportDistance = 22 },
		Speed      = { Tolerance = 1.4, FlatBonus = 6, SustainedSamples = 5 },
		Punishment = {
			StrikesPerWarning = 2, EscalationCooldown = 3, StrikeDecaySeconds = 150,
			WarningActions = { [1]="notify",[2]="kick",[3]="kick" },
			BanAtWarning = 4,
		},
	},
}

local function applyPreset()
	local name = CONFIG.Preset
	if name == "custom" then
		print("🛡️ [AntiFlyTP] Preset custom → valeurs du fichier telles quelles")
		return
	end
	local preset = PRESETS[name]
	if not preset then
		warn("🛡️ [AntiFlyTP] Preset inconnu '" .. tostring(name) .. "' → 'balanced'")
		name, preset = "balanced", PRESETS.balanced
	end
	for section, values in pairs(preset) do
		if type(CONFIG[section]) == "table" then
			for key, val in pairs(values) do CONFIG[section][key] = val end
		end
	end
	print("🛡️ [AntiFlyTP] Preset appliqué : " .. string.upper(name))
end
--  📸 Copie des réglages « fichier » (avant la sévérité) : sert de base quand
--     le panel change un réglage avancé (voir applyAdvanced plus bas).
local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = deepCopy(v) end
	return o
end
local PRISTINE = deepCopy(CONFIG)
applyPreset()

--════════════════════════════════════════════════════════════════════════════
-- 💾 TAMPONS DE PERSISTANCE (RAM → lots)
--════════════════════════════════════════════════════════════════════════════
local function persistOn() return CONFIG.Stats.Enabled == true end

local function freshPending()
	return {
		detTotal = 0, detByType = {}, warnEvents = 0, kickEvents = 0, wouldBan = false,
		detIgnored = 0, confSum = 0, confCount = 0, confMax = 0,
	}
end

local DIRTY = {}
local GPENDING = { detTotal = 0, detByType = {}, warnEvents = 0, kickEvents = 0, wouldBanPlayers = 0 }

--════════════════════════════════════════════════════════════════════════════
-- 📓 JOURNAL EN MÉMOIRE (lu par le panel admin)
--════════════════════════════════════════════════════════════════════════════
local TestLog = {}
do
	TestLog.startedAt = os.time()
	TestLog.events    = {}
	TestLog.warnings  = {}
	TestLog.players   = {}
	TestLog.totals    = { detections = 0, byType = {}, simWarnings = 0, wouldKicks = 0, wouldBans = 0 }

	local function fmtDuration(sec)
		sec = math.floor(math.max(0, sec))
		local h = math.floor(sec / 3600)
		local m = math.floor((sec % 3600) / 60)
		local s = sec % 60
		if h > 0 then return string.format("%dh%02dm%02ds", h, m, s) end
		if m > 0 then return string.format("%dm%02ds", m, s) end
		return string.format("%ds", s)
	end
	local function clockTime(t) return os.date("%H:%M:%S", t) end

	local function fiche(player)
		local id = player.UserId
		local r = TestLog.players[id]
		if not r then
			r = {
				userId = id, name = player.Name,
				detections = {}, total = 0,
				simWarnings = 0, wouldKick = 0, wouldBan = false, wouldBanAt = nil,
				firstSeen = os.time(), lastSeen = os.time(), lastType = nil,
				confMax = 0, confSum = 0, confCount = 0, counted = 0, ignored = 0,
				pending = freshPending(),
			}
			TestLog.players[id] = r
		end
		r.name = player.Name
		r.lastSeen = os.time()
		return r
	end

	local function push(ev)
		table.insert(TestLog.events, ev)
		local max = CONFIG.Stats.MaxEvents
		while #TestLog.events > max do table.remove(TestLog.events, 1) end
	end

	function TestLog.recordDetection(player, vType, details, conf, factors, counted)
		local r = fiche(player)
		r.detections[vType] = (r.detections[vType] or 0) + 1
		r.total = r.total + 1
		r.lastType = vType

		-- 🎯 Suivi de la certitude. On garde la moyenne des détections
		-- RETENUES (celles qui ont compté) et le maximum atteint : c'est ce
		-- couple qui te dit si un joueur est un cas limite ou un dossier solide.
		conf = tonumber(conf) or 0
		r.confMax = math.max(r.confMax or 0, conf)
		if counted then
			r.confSum   = (r.confSum or 0) + conf
			r.confCount = (r.confCount or 0) + 1
			r.counted   = (r.counted or 0) + 1
		else
			r.ignored = (r.ignored or 0) + 1
		end

		TestLog.totals.detections = TestLog.totals.detections + 1
		TestLog.totals.byType[vType] = (TestLog.totals.byType[vType] or 0) + 1
		if not counted then
			TestLog.totals.ignored = (TestLog.totals.ignored or 0) + 1
		end

		push({ t = os.time(), kind = "detection", userId = player.UserId,
			name = player.Name, vType = vType, details = details,
			conf = conf, factors = factors, counted = counted == true })

		if persistOn() then
			if counted then
				r.pending.detTotal = r.pending.detTotal + 1
				r.pending.detByType[vType] = (r.pending.detByType[vType] or 0) + 1
				GPENDING.detTotal = GPENDING.detTotal + 1
				GPENDING.detByType[vType] = (GPENDING.detByType[vType] or 0) + 1
				r.pending.confSum   = (r.pending.confSum or 0) + conf
				r.pending.confCount = (r.pending.confCount or 0) + 1
			else
				--  Les signaux écartés sont comptés à part. Ce chiffre est
				--  précieux : s'il explose alors que les retenus restent à zéro,
				--  c'est que ton obby produit du bruit quelque part — et le
				--  filtre fait exactement son travail.
				r.pending.detIgnored = (r.pending.detIgnored or 0) + 1
				GPENDING.detIgnored  = (GPENDING.detIgnored or 0) + 1
			end
			r.pending.confMax = math.max(r.pending.confMax or 0, conf)
			--  📡 Alimente le fil « qui a été flaggé récemment » du panel.
			--  Aucune écriture ici : juste un horodatage en RAM.
			if counted and _G.UGCRestrict and _G.UGCRestrict.NoteDetection then
				pcall(_G.UGCRestrict.NoteDetection, r.userId)
			end
			DIRTY[r.userId] = true
		end
	end

	function TestLog.recordWarning(player, count, action, vType, details)
		local r = fiche(player)
		local wasBanned = r.wouldBan
		r.simWarnings = count
		if action == "kick" then
			r.wouldKick = r.wouldKick + 1
			TestLog.totals.wouldKicks = TestLog.totals.wouldKicks + 1
		elseif action == "ban" or action == "restrict" then
			if not r.wouldBan then TestLog.totals.wouldBans = TestLog.totals.wouldBans + 1 end
			r.wouldBan = true
			r.wouldBanAt = os.time()
		end
		TestLog.totals.simWarnings = TestLog.totals.simWarnings + 1

		if persistOn() then
			r.pending.warnEvents = r.pending.warnEvents + 1
			GPENDING.warnEvents = GPENDING.warnEvents + 1
			if action == "kick" then
				r.pending.kickEvents = r.pending.kickEvents + 1
				GPENDING.kickEvents = GPENDING.kickEvents + 1
			elseif action == "ban" or action == "restrict" then
				r.pending.wouldBan = true
				if not wasBanned then GPENDING.wouldBanPlayers = GPENDING.wouldBanPlayers + 1 end
			end
			DIRTY[r.userId] = true
		end

		local w = { t = os.time(), userId = player.UserId, name = player.Name,
			count = count, action = action, vType = vType, details = details }
		table.insert(TestLog.warnings, w)
		while #TestLog.warnings > CONFIG.Stats.MaxEvents do table.remove(TestLog.warnings, 1) end
		push({ t = os.time(), kind = "warning", userId = player.UserId, name = player.Name,
			count = count, action = action, vType = vType, details = details })
	end

	function TestLog.reset()
		TestLog.startedAt = os.time()
		TestLog.events, TestLog.warnings, TestLog.players = {}, {}, {}
		TestLog.totals = { detections = 0, byType = {}, simWarnings = 0, wouldKicks = 0, wouldBans = 0 }
		print("🧪 [TEST] Journal réinitialisé.")
	end

	local function playersArray()
		local arr = {}
		for _, r in pairs(TestLog.players) do table.insert(arr, r) end
		return arr
	end
	local function detBreakdown(r)
		local parts = {}
		for t, c in pairs(r.detections) do table.insert(parts, t .. "=" .. c) end
		table.sort(parts)
		return table.concat(parts, ", ")
	end
	local function tag(r)
		if r.wouldBan then return " 🚫SANCTION" end
		if r.wouldKick > 0 then return " ⚠️KICK" end
		return ""
	end

	function TestLog.report()
		local up = os.time() - TestLog.startedAt
		local T = TestLog.totals
		local nPlayers = 0
		for _ in pairs(TestLog.players) do nPlayers = nPlayers + 1 end
		print("╔══════════════════════════════════════════════════════════╗")
		print("║ 🛡️ RAPPORT ANTI-FLY / ANTI-TP                             ║")
		print("╚══════════════════════════════════════════════════════════╝")
		print(string.format("  Mode                : %s", acMode()))
		print(string.format("  Shadow              : %s", acShadow()
			and "OUI — personne n'est puni" or "non — les sanctions s'appliquent"))
		print(string.format("  Durée d'observation : %s", fmtDuration(up)))
		print(string.format("  Joueurs flaggés     : %d", nPlayers))
		print(string.format("  Signaux totaux      : %d", T.detections))
		print(string.format("  ⚪ Écartés (trop peu sûrs) : %d", T.ignored or 0))
		print(string.format("  ✅ Retenus          : %d", T.detections - (T.ignored or 0)))
		print(string.format("  Warnings            : %d", T.simWarnings))
		print(string.format("  ⚠️  Kicks            : %d", T.wouldKicks))
		print(string.format("  🚫 Sanctions finales : %d joueur(s)", T.wouldBans))
		print("  ── Détections par type ──")
		local types = {}
		for k, v in pairs(T.byType) do table.insert(types, { k = k, v = v }) end
		table.sort(types, function(a, b) return a.v > b.v end)
		if #types == 0 then print("     (aucune)") end
		for _, e in ipairs(types) do print(string.format("     %-12s : %d", e.k, e.v)) end
		print("  ── Top 5 ──")
		local arr = playersArray()
		table.sort(arr, function(a, b) return a.total > b.total end)
		if #arr == 0 then print("     (aucun)") end
		for i = 1, math.min(5, #arr) do
			local r = arr[i]
			print(string.format("     %d. %s (%d) — %d détections, %d warn%s",
				i, r.name, r.userId, r.total, r.simWarnings, tag(r)))
		end
	end

	function TestLog.topExploiters(n)
		n = n or 10
		local arr = playersArray()
		table.sort(arr, function(a, b) return a.total > b.total end)
		print(string.format("🛡️ TOP %d (par détections)", n))
		if #arr == 0 then print("  (aucun joueur flaggé 🎉)") return end
		for i = 1, math.min(n, #arr) do
			local r = arr[i]
			print(string.format("  %2d. %-20s (%d) | total=%d | warn=%d%s | %s",
				i, r.name, r.userId, r.total, r.simWarnings, tag(r), detBreakdown(r)))
		end
	end

	function TestLog.wouldBeBanned()
		local arr = {}
		for _, r in pairs(TestLog.players) do if r.wouldBan then table.insert(arr, r) end end
		table.sort(arr, function(a, b) return (a.wouldBanAt or 0) < (b.wouldBanAt or 0) end)
		print(string.format("🛡️ SANCTION FINALE : %d joueur(s)", #arr))
		if #arr == 0 then print("  (personne 🎉)") return end
		for i, r in ipairs(arr) do
			print(string.format("  %2d. %-20s (%d) | %d warnings | à %s | %s",
				i, r.name, r.userId, r.simWarnings, clockTime(r.wouldBanAt or 0), detBreakdown(r)))
		end
	end

	function TestLog.wouldBeKicked()
		local arr = {}
		for _, r in pairs(TestLog.players) do if r.wouldKick > 0 then table.insert(arr, r) end end
		table.sort(arr, function(a, b) return a.wouldKick > b.wouldKick end)
		print(string.format("🛡️ KICKS : %d joueur(s)", #arr))
		if #arr == 0 then print("  (personne)") return end
		for i, r in ipairs(arr) do
			print(string.format("  %2d. %-20s (%d) | %d kick(s) | %d warnings%s",
				i, r.name, r.userId, r.wouldKick, r.simWarnings, r.wouldBan and " 🚫" or ""))
		end
	end

	function TestLog.topWarnings(n)
		n = n or 10
		local arr = playersArray()
		table.sort(arr, function(a, b) return a.simWarnings > b.simWarnings end)
		print(string.format("🛡️ TOP %d WARNINGS", n))
		local shown = 0
		for i = 1, #arr do
			local r = arr[i]
			if r.simWarnings > 0 then
				shown = shown + 1
				print(string.format("  %2d. %-20s (%d) | %d warnings%s | %s",
					shown, r.name, r.userId, r.simWarnings, tag(r), detBreakdown(r)))
				if shown >= n then break end
			end
		end
		if shown == 0 then print("  (aucun warning)") end
	end

	function TestLog.recentWarnings(n)
		n = n or 15
		print(string.format("🛡️ %d DERNIERS WARNINGS", n))
		local w = TestLog.warnings
		if #w == 0 then print("  (aucun)") return end
		for i = math.max(1, #w - n + 1), #w do
			local e = w[i]
			print(string.format("  [%s] %-18s (%d) → %s | W%d | %s | %s",
				clockTime(e.t), e.name, e.userId, string.upper(e.action), e.count,
				e.vType, e.details or ""))
		end
	end

	function TestLog.recentDetections(n)
		n = n or 20
		print(string.format("🛡️ %d DERNIÈRES DÉTECTIONS", n))
		local dets = {}
		for _, e in ipairs(TestLog.events) do
			if e.kind == "detection" then table.insert(dets, e) end
		end
		if #dets == 0 then print("  (aucune)") return end
		for i = math.max(1, #dets - n + 1), #dets do
			local e = dets[i]
			print(string.format("  [%s] %-18s (%d) | %-11s | %s",
				clockTime(e.t), e.name, e.userId, e.vType, e.details or ""))
		end
	end

	function TestLog.playerDetail(userId)
		local r = TestLog.players[userId]
		if not r then print(string.format("🛡️ Aucun log pour %d", userId)) return end
		print(string.format("🛡️ DÉTAIL — %s (%d)", r.name, r.userId))
		print(string.format("  Détections : %d  (%d retenues, %d écartées)",
			r.total, r.counted or 0, r.ignored or 0))
		print(string.format("  Certitude  : %d%% en moyenne, %d%% au maximum",
			((r.confCount or 0) > 0) and math.floor(r.confSum / r.confCount) or 0,
			r.confMax or 0))
		local types = {}
		for t, c in pairs(r.detections) do table.insert(types, { k = t, v = c }) end
		table.sort(types, function(a, b) return a.v > b.v end)
		for _, e in ipairs(types) do print(string.format("     %-12s : %d", e.k, e.v)) end
		print(string.format("  Warnings   : %d", r.simWarnings))
		print(string.format("  Kicks      : %d", r.wouldKick))
		print(string.format("  Sanction   : %s", r.wouldBan
			and ("OUI (" .. clockTime(r.wouldBanAt or 0) .. ")") or "non"))
		print(string.format("  Vu de %s à %s", clockTime(r.firstSeen), clockTime(r.lastSeen)))
	end
end

--════════════════════════════════════════════════════════════════════════════
-- 💾 STATS PERSISTANTES — écriture EN LOTS, jamais sur le chemin de détection
--════════════════════════════════════════════════════════════════════════════
local StatsStore = {}
do
	local DSS = DataStoreService
	local stores = nil
	local function cfg() return CONFIG.Stats end

	local GEN_STORE_NAME = "AntiFlyTP_Gen_v1"
	local genStore, genCache = nil, { test = nil, real = nil, t = 0 }
	local GEN_TTL = 20

	local function getGenStore()
		if genStore then return genStore end
		local ok, res = pcall(function() return DSS:GetDataStore(GEN_STORE_NAME) end)
		if ok then genStore = res end
		return genStore
	end

	local function readGen(kind)
		local now = os.time()
		if genCache[kind] ~= nil and (now - genCache.t) < GEN_TTL then return genCache[kind] end
		local g = 0
		local gs = getGenStore()
		if gs then
			local ok, v = pcall(function() return gs:GetAsync(kind) end)
			if ok and tonumber(v) then g = math.floor(tonumber(v)) end
		end
		genCache[kind] = g ; genCache.t = now
		return g
	end

	local function bumpGen(kind)
		local gs = getGenStore()
		if not gs then return nil end
		local newv
		local ok = pcall(function()
			newv = gs:UpdateAsync(kind, function(old) return (tonumber(old) or 0) + 1 end)
		end)
		genCache[kind] = nil ; genCache.t = 0 ; stores = nil
		return ok and newv or nil
	end
	function StatsStore.bumpRealGen() return bumpGen("real") end

	local storesGen = { test = -1, real = -1 }
	local function ensureStores()
		local tg, rg = readGen("test"), readGen("real")
		if stores and storesGen.test == tg and storesGen.real == rg then return stores end
		local c = cfg()
		local ts, rs = "_g" .. tg, "_g" .. rg
		local ok, res = pcall(function()
			return {
				data     = DSS:GetDataStore(c.StatsStore),
				det      = DSS:GetOrderedDataStore(c.RankDetStore .. ts),
				warn     = DSS:GetOrderedDataStore(c.RankWarnStore .. ts),
				kick     = DSS:GetOrderedDataStore(c.RankKickStore .. ts),
				ban      = DSS:GetOrderedDataStore(c.RankBanStore .. ts),
				realwarn = DSS:GetOrderedDataStore(c.RealWarnStore .. rs),
				realban  = DSS:GetOrderedDataStore(c.RealBanStore .. rs),
			}
		end)
		if ok then stores = res ; storesGen.test = tg ; storesGen.real = rg end
		return stores
	end

	local function clockTime(t) return os.date("%Y-%m-%d %H:%M", t) end
	local function pendingEmpty(pd)
		return pd.detTotal == 0 and pd.warnEvents == 0 and pd.kickEvents == 0
			and (pd.detIgnored or 0) == 0 and not pd.wouldBan
	end
	local function mergePendingBack(r, pd)
		local d = r.pending
		d.detTotal = d.detTotal + pd.detTotal
		for t, c in pairs(pd.detByType) do d.detByType[t] = (d.detByType[t] or 0) + c end
		d.warnEvents = d.warnEvents + pd.warnEvents
		d.kickEvents = d.kickEvents + pd.kickEvents
		d.detIgnored = (d.detIgnored or 0) + (pd.detIgnored or 0)
		d.confSum    = (d.confSum or 0) + (pd.confSum or 0)
		d.confCount  = (d.confCount or 0) + (pd.confCount or 0)
		d.confMax    = math.max(d.confMax or 0, pd.confMax or 0)
		if pd.wouldBan then d.wouldBan = true end
		DIRTY[r.userId] = true
	end

	local function flushPlayer(userId)
		local s = ensureStores()
		if not s then return false end
		local r = TestLog.players[userId]
		DIRTY[userId] = nil
		if not r then return true end
		local pd = r.pending
		if pendingEmpty(pd) then return true end
		r.pending = freshPending()

		local ok, updated = pcall(function()
			return s.data:UpdateAsync("player_" .. userId, function(old)
				old = (type(old) == "table") and old or {}
				old.userId = userId ; old.name = r.name
				old.total = (old.total or 0) + pd.detTotal
				old.detByType = old.detByType or {}
				for t, c in pairs(pd.detByType) do
					old.detByType[t] = (old.detByType[t] or 0) + c
				end
				old.warnEvents = (old.warnEvents or 0) + pd.warnEvents
				old.kickEvents = (old.kickEvents or 0) + pd.kickEvents
				old.detIgnored = (old.detIgnored or 0) + (pd.detIgnored or 0)
				--  🎯 Certitude cumulée : on garde la somme et le nombre pour
				--  pouvoir recalculer une vraie moyenne, plutôt qu'une moyenne
				--  de moyennes qui donnerait un chiffre faux.
				old.confSum   = (old.confSum or 0) + (pd.confSum or 0)
				old.confCount = (old.confCount or 0) + (pd.confCount or 0)
				old.confMax   = math.max(old.confMax or 0, pd.confMax or 0)
				if pd.wouldBan then
					old.wouldBan = true
					old.wouldBanAt = old.wouldBanAt or os.time()
				end
				old.firstSeen = old.firstSeen or os.time()
				old.lastSeen  = os.time()
				--  🆕 Dernier signal retenu, en clair (pour le panel)
				if r.lastAt then
					old.lastAt     = r.lastAt
					old.lastType   = r.lastType
					old.lastDetail = r.lastDetail
					old.lastCtx    = r.lastCtx
				end
				if r.warnActive ~= nil then old.warnActive = r.warnActive end
				return old
			end)
		end)

		if not ok then
			mergePendingBack(r, pd)
			warn("🛡️💾 Flush joueur échoué (" .. userId .. "), réessai au prochain cycle")
			return false
		end

		if updated then
			if pd.detTotal   > 0 then pcall(function() s.det:SetAsync(tostring(userId), math.floor(updated.total or 0)) end) end
			if pd.warnEvents > 0 then pcall(function() s.warn:SetAsync(tostring(userId), math.floor(updated.warnEvents or 0)) end) end
			if pd.kickEvents > 0 then pcall(function() s.kick:SetAsync(tostring(userId), math.floor(updated.kickEvents or 0)) end) end
			if pd.wouldBan       then pcall(function() s.ban:SetAsync(tostring(userId), math.floor(updated.wouldBanAt or os.time())) end) end
		end
		return true
	end

	local function flushGlobal()
		local s = ensureStores()
		if not s then return end
		if GPENDING.detTotal == 0 and GPENDING.warnEvents == 0
			and GPENDING.kickEvents == 0 and GPENDING.wouldBanPlayers == 0
			and (GPENDING.detIgnored or 0) == 0 then
			return
		end
		local gp = GPENDING
		GPENDING = { detTotal = 0, detByType = {}, warnEvents = 0, kickEvents = 0,
			wouldBanPlayers = 0, detIgnored = 0 }
		local ok = pcall(function()
			s.data:UpdateAsync("global", function(old)
				old = (type(old) == "table") and old or {}
				old.detTotal = (old.detTotal or 0) + gp.detTotal
				old.detByType = old.detByType or {}
				for t, c in pairs(gp.detByType) do old.detByType[t] = (old.detByType[t] or 0) + c end
				old.warnEvents = (old.warnEvents or 0) + gp.warnEvents
				old.kickEvents = (old.kickEvents or 0) + gp.kickEvents
				old.detIgnored = (old.detIgnored or 0) + (gp.detIgnored or 0)
				old.wouldBanPlayers = (old.wouldBanPlayers or 0) + gp.wouldBanPlayers
				old.firstSeen = old.firstSeen or os.time()
				old.lastFlush = os.time()
				old.flushes = (old.flushes or 0) + 1
				return old
			end)
		end)
		if not ok then
			GPENDING.detTotal = GPENDING.detTotal + gp.detTotal
			for t, c in pairs(gp.detByType) do GPENDING.detByType[t] = (GPENDING.detByType[t] or 0) + c end
			GPENDING.warnEvents = GPENDING.warnEvents + gp.warnEvents
			GPENDING.kickEvents = GPENDING.kickEvents + gp.kickEvents
			GPENDING.detIgnored = (GPENDING.detIgnored or 0) + (gp.detIgnored or 0)
			GPENDING.wouldBanPlayers = GPENDING.wouldBanPlayers + gp.wouldBanPlayers
			warn("🛡️💾 Flush global échoué, réessai au prochain cycle")
		end
	end

	function StatsStore.flushAll(closing)
		if not persistOn() then return end
		local ids = {}
		for id in pairs(DIRTY) do table.insert(ids, id) end
		local delay = cfg().PerRequestDelay or 0.2
		for _, id in ipairs(ids) do
			flushPlayer(id)
			if not closing then task.wait(delay) end
		end
		flushGlobal()
	end

	local nameCache = {}
	local function nameOf(s, key)
		if nameCache[key] then return nameCache[key] end
		local ok, rec = pcall(function() return s.data:GetAsync("player_" .. key) end)
		local nm = (ok and type(rec) == "table" and rec.name) or ("UserId " .. key)
		nameCache[key] = nm
		return nm
	end
	local function clampN(n)
		n = tonumber(n) or 10
		return math.clamp(math.floor(n), 1, cfg().MaxRankFetch or 50)
	end

	function StatsStore.reportGlobal()
		local s = ensureStores()
		if not s then print("🛡️💾 Stores indisponibles (Studio : active l'accès API DataStore)") return end
		local ok, g = pcall(function() return s.data:GetAsync("global") end)
		if not ok or type(g) ~= "table" then
			print("🛡️💾 Aucune donnée globale persistée pour l'instant.")
			return
		end
		print("╔══════════════════════════════════════════════════════════╗")
		print("║ 💾 STATS PERSISTANTES (cumul TOUS serveurs)               ║")
		print("╚══════════════════════════════════════════════════════════╝")
		print(string.format("  Depuis           : %s", clockTime(g.firstSeen or os.time())))
		print(string.format("  Dernier flush    : %s (%d flushs)", clockTime(g.lastFlush or 0), g.flushes or 0))
		print(string.format("  Détections       : %d", g.detTotal or 0))
		print(string.format("  Warnings         : %d", g.warnEvents or 0))
		print(string.format("  Kicks            : %d", g.kickEvents or 0))
		print(string.format("  Sanctions finales: %d", g.wouldBanPlayers or 0))
		local types = {}
		for k, v in pairs(g.detByType or {}) do table.insert(types, { k = k, v = v }) end
		table.sort(types, function(a, b) return a.v > b.v end)
		for _, e in ipairs(types) do print(string.format("     %-12s : %d", e.k, e.v)) end
	end

	local function printRank(title, store, n, valueLabel, asDate)
		local s = ensureStores()
		if not s then print("🛡️💾 Stores indisponibles") return end
		nameCache = {}
		local ok, pages = pcall(function() return store:GetSortedAsync(false, clampN(n)) end)
		if not ok then print("🛡️💾 Lecture du classement impossible (budget/API).") return end
		local page = pages:GetCurrentPage()
		print(string.format("💾 %s", title))
		if #page == 0 then print("  (aucune donnée)") return end
		for rank, entry in ipairs(page) do
			local val = asDate and clockTime(entry.value) or tostring(entry.value)
			print(string.format("  %2d. %-20s (%s) | %s: %s",
				rank, nameOf(s, entry.key), entry.key, valueLabel, val))
		end
	end

	function StatsStore.rankExploiters(n)
		local s = ensureStores() ; if not s then return end
		printRank("TOP (détections cumulées)", s.det, n, "détections", false)
	end
	function StatsStore.rankWarnings(n)
		local s = ensureStores() ; if not s then return end
		printRank("TOP WARNINGS", s.warn, n, "warnings", false)
	end
	function StatsStore.rankBanned(n)
		local s = ensureStores() ; if not s then return end
		printRank("SANCTIONS FINALES", s.ban, n, "flaggé le", true)
	end

	function StatsStore.getPlayer(userId)
		local s = ensureStores() ; if not s then return nil end
		local ok, r = pcall(function() return s.data:GetAsync("player_" .. userId) end)
		if ok and type(r) == "table" then return r end
		return nil
	end

	function StatsStore.playerDetail(userId)
		local r = StatsStore.getPlayer(userId)
		if not r then print(string.format("💾 Aucune donnée pour %d", userId)) return end
		print(string.format("💾 DÉTAIL PERSISTÉ — %s (%d)", r.name or "?", userId))
		print(string.format("  Détections : %d", r.total or 0))
		local types = {}
		for t, c in pairs(r.detByType or {}) do table.insert(types, { k = t, v = c }) end
		table.sort(types, function(a, b) return a.v > b.v end)
		for _, e in ipairs(types) do print(string.format("     %-12s : %d", e.k, e.v)) end
		print(string.format("  Warnings   : %d", r.warnEvents or 0))
		print(string.format("  Kicks      : %d", r.kickEvents or 0))
		print(string.format("  Sanction   : %s", r.wouldBan
			and ("OUI (" .. clockTime(r.wouldBanAt or 0) .. ")") or "non"))
	end

	function StatsStore.wipe(token)
		if token ~= "OUI" then
			print("🛡️💾 Sécurité : passe \"OUI\" pour confirmer.")
			return
		end
		task.spawn(function()
			local s = ensureStores() ; if not s then return end
			pcall(function() s.data:RemoveAsync("global") end)
			DIRTY = {}
			GPENDING = { detTotal = 0, detByType = {}, warnEvents = 0, kickEvents = 0, wouldBanPlayers = 0 }
			print("🛡️💾 Clé 'global' effacée.")
		end)
	end

	function StatsStore.clearPlayer(userId)
		task.spawn(function()
			local s = ensureStores() ; if not s then return end
			pcall(function() s.data:RemoveAsync("player_" .. userId) end)
			pcall(function() s.det:RemoveAsync(tostring(userId)) end)
			pcall(function() s.warn:RemoveAsync(tostring(userId)) end)
			pcall(function() s.kick:RemoveAsync(tostring(userId)) end)
			pcall(function() s.ban:RemoveAsync(tostring(userId)) end)
		end)
	end

	local function fetchTopN(store, n)
		n = math.clamp(tonumber(n) or 50, 1, 200)
		local out = {}
		local ok, pages = pcall(function() return store:GetSortedAsync(false, math.min(n, 100)) end)
		if not ok then return out end
		local guard = 0
		while true do
			guard = guard + 1
			for _, e in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(e.key)
				if uid then out[#out + 1] = { userId = uid, value = e.value } end
				if #out >= n then break end
			end
			if #out >= n or pages.IsFinished or guard >= 3 then break end
			if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
		end
		return out
	end

	function StatsStore.getRank(kind, n)
		local s = ensureStores() ; if not s then return {} end
		local store = (kind == "warnings" and s.warn)
			or (kind == "kicks" and s.kick)
			or (kind == "bans" and s.ban)
			or s.det
		return fetchTopN(store, n)
	end

	function StatsStore.indexRealWarning(userId, count)
		task.spawn(function()
			local s = ensureStores() ; if not s then return end
			if (tonumber(count) or 0) > 0 then
				pcall(function() s.realwarn:SetAsync(tostring(userId), math.floor(count)) end)
			else
				pcall(function() s.realwarn:RemoveAsync(tostring(userId)) end)
			end
		end)
	end

	local function listOrdered(store, maxPages)
		local ids = {}
		local ok, pages = pcall(function() return store:GetSortedAsync(false, 100) end)
		if not ok then return ids end
		local guard = 0
		while true do
			guard = guard + 1
			for _, e in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(e.key)
				if uid then ids[uid] = true end
			end
			if pages.IsFinished or guard >= (maxPages or 10) then break end
			if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
		end
		return ids
	end

	function StatsStore.wipeTestAll(token)
		if token ~= "OUI" then print("🛡️💾 [WIPE] Sécurité : token \"OUI\" requis.") return false end
		task.spawn(function()
			local s = ensureStores() ; if not s then return end
			local ids = {}
			for _, store in ipairs({ s.det, s.warn, s.kick, s.ban }) do
				for uid in pairs(listOrdered(store, 10)) do ids[uid] = true end
			end
			local delay = cfg().PerRequestDelay or 0.2
			local n = 0
			for uid in pairs(ids) do
				n = n + 1
				pcall(function() s.data:RemoveAsync("player_" .. uid) end)
				task.wait(delay)
			end
			pcall(function() s.data:RemoveAsync("global") end)
			TestLog.reset()
			DIRTY = {}
			GPENDING = { detTotal = 0, detByType = {}, warnEvents = 0, kickEvents = 0, wouldBanPlayers = 0 }
			local g = bumpGen("test")
			print(string.format("🗑️ Stats effacées (%d fiche(s)) + classements réinitialisés (gen=%s).",
				n, tostring(g)))
		end)
		return true
	end

	function StatsStore.listRealWarned()
		local s = ensureStores() ; if not s then return {} end
		return listOrdered(s.realwarn, 10)
	end
	function StatsStore.clearRealWarnIndex(userId)
		local s = ensureStores() ; if not s then return end
		pcall(function() s.realwarn:RemoveAsync(tostring(userId)) end)
	end
	function StatsStore.getRealRank(kind, n)
		local s = ensureStores() ; if not s then return {} end
		return fetchTopN((kind == "bans" and s.realban) or s.realwarn, n)
	end
	function StatsStore.indexRealBan(userId, ts)
		task.spawn(function()
			local s = ensureStores() ; if not s then return end
			pcall(function() s.realban:SetAsync(tostring(userId), math.floor(ts or os.time())) end)
		end)
	end
	function StatsStore.clearRealBanIndex(userId)
		local s = ensureStores() ; if not s then return end
		pcall(function() s.realban:RemoveAsync(tostring(userId)) end)
	end
end

task.spawn(function()
	while true do
		task.wait(CONFIG.Stats.FlushInterval)
		if persistOn() then
			local ok, err = pcall(StatsStore.flushAll, false)
			if not ok then warn("🛡️💾 Erreur de flush : " .. tostring(err)) end
		end
	end
end)

game:BindToClose(function()
	if persistOn() then
		pcall(StatsStore.flushAll, true)
		task.wait(1)
	end
end)

--════════════════════════════════════════════════════════════════════════════
-- 📰 JOURNAL PARTAGÉ DES DÉTECTIONS (fil « récent » du panel, tous serveurs)
--    Chaque détection RETENUE, chaque warning et chaque sanction y sont écrits
--    avec une explication en clair (ce qu'il a fait, où, avec quoi, pourquoi
--    la machine y croit). Écrit par lots toutes les 30 s : zéro latence en jeu.
--    On garde les 300 derniers événements.
--════════════════════════════════════════════════════════════════════════════
local FeedLog = {}
do
	local store
	local pendingEv = {}
	local cacheList, cacheAt = {}, -1000
	local KEEP = 300
	local function getStore()
		if store then return store end
		local ok, st = pcall(function() return DataStoreService:GetDataStore("AntiCheat_FeedLog_v1") end)
		if ok then store = st end
		return store
	end
	function FeedLog.push(ev)
		if type(ev) ~= "table" then return end
		ev.t = ev.t or os.time()
		ev.server = ev.server or string.sub(game.JobId ~= "" and game.JobId or "studio", 1, 8)
		table.insert(pendingEv, ev)
		table.insert(cacheList, 1, ev)
		while #cacheList > KEEP do table.remove(cacheList) end
	end
	local function flush()
		if #pendingEv == 0 then return end
		local s = getStore() ; if not s then return end
		local batch = pendingEv
		pendingEv = {}
		local ok, res = pcall(function()
			return s:UpdateAsync("recent", function(old)
				old = (type(old) == "table") and old or {}
				for _, ev in ipairs(batch) do table.insert(old, ev) end
				table.sort(old, function(a, b) return (a.t or 0) > (b.t or 0) end)
				while #old > KEEP do table.remove(old) end
				return old
			end)
		end)
		if ok and type(res) == "table" then
			cacheList, cacheAt = res, os.clock()
		else
			for _, ev in ipairs(batch) do table.insert(pendingEv, ev) end
		end
	end
	function FeedLog.get(n)
		n = math.clamp(tonumber(n) or 100, 1, KEEP)
		if os.clock() - cacheAt > 15 then
			local s = getStore()
			if s then
				local ok, res = pcall(function() return s:GetAsync("recent") end)
				if ok then
					local list = (type(res) == "table") and res or {}
					--  ce serveur ajoute ce qu'il n'a pas encore écrit
					for _, ev in ipairs(pendingEv) do table.insert(list, ev) end
					table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
					cacheList, cacheAt = list, os.clock()
				end
			end
		end
		local out = {}
		for i = 1, math.min(n, #cacheList) do out[i] = cacheList[i] end
		return out
	end
	task.spawn(function()
		while true do
			task.wait(30)
			pcall(flush)
		end
	end)
	game:BindToClose(function() pcall(flush) end)
end

--════════════════════════════════════════════════════════════════════════════
-- 📡 REMOTE DE NOTIFICATION
--════════════════════════════════════════════════════════════════════════════
local notifyRemote = ReplicatedStorage:FindFirstChild("AntiFlyTP_Notify")
if not notifyRemote then
	notifyRemote = Instance.new("RemoteEvent")
	notifyRemote.Name = "AntiFlyTP_Notify"
	notifyRemote.Parent = ReplicatedStorage
end

local warningsStore = DataStoreService:GetDataStore(CONFIG.DataStores.Warnings)
local banStore      = DataStoreService:GetDataStore(CONFIG.DataStores.Bans)

--  Nom de l'expérience, disponible dans les gabarits de message via {game}.
--  Lu une seule fois : `MarketplaceService:GetProductInfo` est un appel web,
--  hors de question de le faire à chaque message.
local GAME_NAME = "this experience"
task.spawn(function()
	local ok, info = pcall(function()
		return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
	end)
	if ok and type(info) == "table" and type(info.Name) == "string" then
		GAME_NAME = info.Name
	end
end)

--════════════════════════════════════════════════════════════════════════════
-- ⏳ BANS TEMPORAIRES (modes.ban.banDays > 0)
--    On stocke la date de fin DANS l'enregistrement. Ce contrôle-ci laisse
--    rentrer le joueur une fois la date passée, et efface l'entrée pour que
--    le panel n'affiche plus un ban qui n'existe plus.
--    ⚠️ Si tu utilises aussi l'API de ban Roblox (UseRobloxBanAPI), c'est
--       Roblox qui gère l'expiration de son côté — les deux durées sont
--       posées avec la même valeur, donc elles tombent ensemble.
--════════════════════════════════════════════════════════════════════════════
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local ok, data = pcall(function()
			return banStore:GetAsync(tostring(player.UserId))
		end)
		if not ok or type(data) ~= "table" then return end
		local exp = tonumber(data.expiresAt) or 0
		if exp > 0 and os.time() >= exp then
			pcall(function() banStore:RemoveAsync(tostring(player.UserId)) end)
			warn(string.format("🛡️⏳ Ban expiré pour %s (%d) → levé automatiquement",
				player.Name, player.UserId))
			return
		end

		--════════════════════════════════════════════════════════════
		-- 🚪 PORTE D'ENTRÉE
		--    Le ban est encore actif : on éjecte à la connexion.
		--
		--    Sans ce contrôle, `banPlayer` ne faisait qu'un kick unique et
		--    le joueur revenait librement à la connexion suivante — le ban
		--    n'existait que dans le DataStore. C'est le cas si tu as laissé
		--    `UseRobloxBanAPI = false` (le défaut), puisque Roblox n'a alors
		--    aucune trace du ban de son côté.
		--
		--    ⚠️ On ne fait RIEN en shadow : observer, c'est ne rien appliquer,
		--       y compris les bans posés avant que tu ne rallumes le shadow.
		--════════════════════════════════════════════════════════════
		if acShadow() then
			warn(string.format("🧪 [SHADOW] %s (%d) est banni en base mais entre quand même",
				player.Name, player.UserId))
			return
		end
		if not player.Parent then return end

		local days = tonumber(data.days) or 0
		local msg  = "🔨 Account banned by our anti-cheat system.\n\n"
			.. tostring(data.details or "")
		if exp > 0 then
			local hoursLeft = math.max(math.ceil((exp - os.time()) / 3600), 1)
			msg = msg .. string.format("\n\nTime remaining: about %d hour(s).", hoursLeft)
		end
		msg = msg .. "\n\nContact support with evidence if you believe this is a mistake."
		player:Kick(msg)
	end)
end)

--════════════════════════════════════════════════════════════════════════════
-- 🤍 WHITELIST
--   🩹 FIX 5 : les admins du panel sont injectés automatiquement.
--════════════════════════════════════════════════════════════════════════════
--  Deux ensembles distincts, et c'est important :
--    • whitelistSet — les exemptions que TU as écrites dans CONFIG. Elles
--      s'appliquent toujours (un compte de test, un bot, un NPC piloté).
--    • adminSet — tes admins. Ils ne sont exemptés QUE si tu as désactivé
--      « analyser les admins » dans le panel.
local whitelistSet = {}
for _, id in ipairs(CONFIG.Whitelist.UserIds) do whitelistSet[id] = true end

local adminSet = {}

task.spawn(function()
	for _ = 1, 60 do
		if type(_G.AC_ADMIN_IDS) == "table" then
			local n = 0
			for _, id in ipairs(_G.AC_ADMIN_IDS) do
				if not adminSet[id] then adminSet[id] = true ; n = n + 1 end
			end
			log(string.format("Liste admin synchronisée (%d) — analysés : %s",
				n, tostring(acAnalyzeAdmins())))
			return
		end
		task.wait(1)
	end
	warn("🛡️ [AntiFlyTP] _G.AC_ADMIN_IDS introuvable — la case « privilège admin » "
		.. "du panel n'aura aucun effet. Vérifie que AntiCheat_UGCRestrict.server.lua "
		.. "est bien dans ServerScriptService.")
end)

local function isAdminId(userId) return adminSet[userId] == true end

local function isWhitelisted(userId)
	if whitelistSet[userId] then return true end
	if adminSet[userId] and not acAnalyzeAdmins() then return true end
	return false
end

--════════════════════════════════════════════════════════════════════════════
-- 🧠 ÉTAT PAR JOUEUR
--════════════════════════════════════════════════════════════════════════════
local S = {}

local function newState()
	return {
		lastPos = nil, lastVel = Vector3.zero, lastT = os.clock(),
		hoverTime = 0, upCount = 0, speedCount = 0,
		airStartY = nil,
		groundPosA = nil, groundPosB = nil, groundMemT = 0,
		wasOnGround = true, lastGroundT = os.clock(),

		strikes = 0, lastStrikeT = 0, lastCountedT = 0, lastDecayT = os.clock(),

		graceUntil = 0, graceReason = "",
		launchUntil = 0,       -- 🩹 FIX 3/7 : propulsion en cours
		ragdollUntil = 0,      -- 🩹 FIX 8
		landingUntil = 0,      -- 🩹 FIX 9
		suspendSamples = 0,

		forces = {},           -- 🩹 FIX 4 : movers vivants sur le personnage
		antiGravUntil = 0,

		lastFlyToolT = -1000, lastGravityToolT = -1000, lastGravityProfile = nil,
		lastSpeedToolT = -1000, lastSpeedToolValue = 0,

		warnings = 0, warningsLoaded = false,
		lastNudgeT = 0, lastRemoteGraceT = 0,
		cpTpTimes = {},

		-- 🎯 Éléments du score de certitude
		spawnT       = os.clock(),
		detHistory   = {},    -- { {t, vType, conf}, … } sur 5 minutes glissantes
		batchConf    = {},    -- certitudes du lot de strikes en cours
		everDetected = false,
		--  Détections COMPTÉES de la session : c'est ce compteur qui pilote
		--  « afficher la carte orange après N détections ». Les détections
		--  écartées pour certitude insuffisante ne l'incrémentent pas.
		countedDet   = 0,
	}
end

local function resetAir(st, y)
	st.airStartY = y
	st.hoverTime = 0
	st.upCount = 0
end

--════════════════════════════════════════════════════════════════════════════
-- ⏳ GRÂCES
--════════════════════════════════════════════════════════════════════════════
local function giveGrace(target, seconds, reason)
	local userId = (typeof(target) == "Instance") and target.UserId or tonumber(target)
	if not userId then return end
	local st = S[userId]
	if not st then return end
	local untilT = os.clock() + (seconds or 5)
	if untilT > st.graceUntil then
		st.graceUntil = untilT
		st.graceReason = reason or "?"
	end
end

--════════════════════════════════════════════════════════════════════════════
-- 🔗 ÉTATS EXTERNES
--════════════════════════════════════════════════════════════════════════════
local function externallyBusy(userId)
	if _G.recentReloads and _G.recentReloads[userId] then return true end
	if _G.dataLoading and _G.dataLoading[userId] then return true end
	return false
end

local function isInArena(player)
	if _G.PlayersInArena and _G.PlayersInArena[player.UserId] then return true end
	if player:GetAttribute("InArena") then return true end
	return false
end

--════════════════════════════════════════════════════════════════════════════
-- 🏃 PONT MOVEMENTBOOST — l'anti-cheat connaît les règles du mouvement PVP
--════════════════════════════════════════════════════════════════════════════
local MB_CFG = nil
task.spawn(function()
	local ws  = ReplicatedStorage:WaitForChild("WeaponSystem", 30)
	local mod = ws and ws:WaitForChild("MovementBoostConfig", 30)
	if not mod then
		warn("🛡️ [AntiFlyTP] MovementBoostConfig introuvable → limites PVP normales")
		return
	end
	local ok, res = pcall(require, mod)
	if ok and type(res) == "table" then
		MB_CFG = res
		log("MovementBoostConfig lu : limites adaptées au mouvement PVP")
	end
end)

--  Même règle que le client (MovementBoost.Active). Renvoie nil si le
--  système n'est pas actif pour ce joueur → limites normales.
local function moveBoostFor(player)
	local MBc, C = CONFIG.MovementBoost, MB_CFG
	if not (MBc and MBc.Enabled and C) then return nil end
	local a = workspace:GetAttribute("MovementBoost")
	local on
	if a ~= nil then on = (a == true) else on = (C.Enabled == true) end
	if not on then return nil end
	if C.OnlyInArena and not isInArena(player) then return nil end

	local G  = (type(C.Gravity) == "table" and C.Gravity.Enabled ~= false) and C.Gravity or nil
	local Mo = (type(C.Momentum) == "table" and C.Momentum.Enabled ~= false) and C.Momentum or {}
	local D  = (type(C.DoubleJump) == "table" and C.DoubleJump.Enabled ~= false) and C.DoubleJump or nil

	local momentum = tonumber(Mo.Max) or 0
	local hopAir   = tonumber(Mo.SlideHopAirMax) or 0
	local forward  = D and (tonumber(D.ForwardBoost) or 0) or 0
	return {
		gravMult    = G and math.clamp(tonumber(G.Multiplier) or 1, 0.05, 1) or 1,
		extraHeight = D and (tonumber(D.Height) or 0) * (tonumber(D.Count) or 1) or 0,
		maxSpeed    = math.max((MBc.SlideSpeed or 40) + momentum, 16 * 1.3 + momentum + hopAir)
			+ forward + (MBc.SpeedMargin or 0),
	}
end

--  🧵 Cordes de tyrolienne : relevées une fois, puis tenues à jour quand une
--     map est chargée (aucun parcours complet du workspace pendant le jeu).
local ropes, ropesReady = {}, false
local function isRope(inst)
	local Z = CONFIG.Zipline
	return inst:IsA("BasePart") and inst.Name == Z.Rope and inst.Parent
		and inst.Parent:IsA("Model") and inst.Parent.Name:sub(1, #Z.Prefix) == Z.Prefix
end
task.spawn(function()
	for i, d in ipairs(workspace:GetDescendants()) do
		if isRope(d) then ropes[d] = true end
		if i % 2000 == 0 then task.wait() end
	end
	ropesReady = true
end)
workspace.DescendantAdded:Connect(function(d)
	if isRope(d) then ropes[d] = true end
end)
local function nearZipline(pos)
	local Z = CONFIG.Zipline
	if not ropesReady then return true end   -- tout début de serveur : on ne juge pas
	for c in pairs(ropes) do
		if not c.Parent then ropes[c] = nil
		else
			--  distance au SEGMENT de la corde (pas à son centre)
			local sz = c.Size
			local axis, half
			if sz.X >= sz.Y and sz.X >= sz.Z then axis, half = Vector3.xAxis, sz.X / 2
			elseif sz.Y >= sz.Z then axis, half = Vector3.yAxis, sz.Y / 2
			else axis, half = Vector3.zAxis, sz.Z / 2 end
			local w = c.CFrame:VectorToWorldSpace(axis)
			local A, B = c.Position - w * half, c.Position + w * half
			local ab = B - A
			local t = math.clamp((pos - A):Dot(ab) / math.max(ab:Dot(ab), 1e-3), 0, 1)
			if ((A + ab * t) - pos).Magnitude <= Z.MaxDist then return true end
		end
	end
	return false
end

local function anyFullBypassAttribute(player, char)
	for _, name in ipairs(CONFIG.LegitAttributes.FullBypass) do
		if player:GetAttribute(name) or (char and char:GetAttribute(name)) then
			if name == "Ziplining" then
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp and nearZipline(hrp.Position) then return true end
			else
				return true
			end
		end
	end
	return false
end

--  ⛅ Pause globale (météo Admin Abuse via PausePhysics).
local globalToleranceOn, globalToleranceUntil = false, 0
local function globalTolerance()
	return globalToleranceOn or os.clock() < globalToleranceUntil
end

--════════════════════════════════════════════════════════════════════════════
-- 🎯 DESTINATIONS SÛRES
--════════════════════════════════════════════════════════════════════════════
local safeParts, checkpointParts = {}, {}

local function classifySafeCandidate(inst)
	if not inst:IsA("BasePart") then return end
	local name = inst.Name
	if CONFIG.Teleport.SafeIncludeSpawnLocations and inst:IsA("SpawnLocation") then
		safeParts[inst] = true ; return
	end
	for _, n in ipairs(CONFIG.Teleport.SafePartNames) do
		if name == n or (inst.Parent and inst.Parent.Name == n) then
			safeParts[inst] = true ; return
		end
	end
	for _, pat in ipairs(CONFIG.Teleport.SafePartPatterns) do
		if string.match(name, pat) then safeParts[inst] = true ; return end
	end
	if string.match(name, CONFIG.Teleport.CheckpointPattern) then
		checkpointParts[inst] = true
	end
end

task.spawn(function()
	local desc = workspace:GetDescendants()
	local nSafe, nCp = 0, 0
	for i, inst in ipairs(desc) do
		classifySafeCandidate(inst)
		if i % 800 == 0 then task.wait() end
	end
	for _ in pairs(safeParts) do nSafe = nSafe + 1 end
	for _ in pairs(checkpointParts) do nCp = nCp + 1 end
	log(string.format("Destinations sûres : %d parts + %d checkpoints", nSafe, nCp))
end)

workspace.DescendantAdded:Connect(function(inst) pcall(classifySafeCandidate, inst) end)
workspace.DescendantRemoving:Connect(function(inst)
	safeParts[inst] = nil ; checkpointParts[inst] = nil
end)

local function nearAnyPart(set, pos, radius)
	for part in pairs(set) do
		if part.Parent then
			if (part.Position - pos).Magnitude <= radius + part.Size.Magnitude * 0.5 then
				return true
			end
		else
			set[part] = nil
		end
	end
	return false
end

local function isNearAlwaysSafe(pos)
	return nearAnyPart(safeParts, pos, CONFIG.Teleport.SafeDestinationRadius)
end
local function isNearCheckpoint(pos)
	return nearAnyPart(checkpointParts, pos, CONFIG.Teleport.SafeDestinationRadius)
end

local function checkpointTpAllowed(st, now)
	local mode = CONFIG.Teleport.CheckpointDestinations
	if mode == "always" then return true end
	if mode == "never" then return false end
	local fresh = {}
	for _, t in ipairs(st.cpTpTimes) do
		if now - t < 60 then table.insert(fresh, t) end
	end
	st.cpTpTimes = fresh
	if #fresh >= CONFIG.Teleport.MaxCheckpointTeleportsPerMinute then return false end
	table.insert(st.cpTpTimes, now)
	return true
end

--════════════════════════════════════════════════════════════════════════════
-- 🧰 OUTILS ÉQUIPÉS
--════════════════════════════════════════════════════════════════════════════
local function classifyTools(char, st, now)
	local res = { flyProfile = nil, gravity = false, gravityProfile = nil, speedBonus = 0 }

	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			local name = child.Name
			local flyProf = CONFIG.LegitTools.FlyTools[name]
			if not flyProf then
				for _, marker in ipairs(CONFIG.LegitTools.FlyToolMarkers) do
					if child:FindFirstChild(marker) then
						flyProf = CONFIG.LegitTools.FlyToolDefaultProfile ; break
					end
				end
			end
			if flyProf then res.flyProfile = flyProf ; st.lastFlyToolT = now end

			if CONFIG.LegitTools.GravityTools[name] then
				res.gravity = true
				res.gravityProfile = CONFIG.LegitTools.GravityProfile
				st.lastGravityToolT = now
				st.lastGravityProfile = res.gravityProfile
			end

			local sp = CONFIG.LegitTools.SpeedTools[name]
			if sp then
				res.speedBonus = math.max(res.speedBonus, sp)
				st.lastSpeedToolT = now ; st.lastSpeedToolValue = sp
			end

			local fusion = CONFIG.LegitTools.FusionTools and CONFIG.LegitTools.FusionTools[name]
			if fusion then
				res.gravity = true
				res.gravityProfile = fusion.GravityProfile or CONFIG.LegitTools.GravityProfile
				st.lastGravityToolT = now ; st.lastGravityProfile = res.gravityProfile
				if fusion.Speed then
					res.speedBonus = math.max(res.speedBonus, fusion.Speed)
					st.lastSpeedToolT = now ; st.lastSpeedToolValue = fusion.Speed
				end
			end
		end
	end

	-- 🩹 FIX 4 : anti-gravité détectée par la PHYSIQUE, pas par un nom.
	if CONFIG.LegitTools.DetectAntiGravityForce then
		for inst in pairs(st.forces) do
			if inst.Parent then
				local up = false
				if inst:IsA("BodyForce") or inst:IsA("VectorForce") then
					up = inst.Force.Y > 0
				elseif inst:IsA("BodyPosition") or inst:IsA("AlignPosition") then
					up = true   -- maintient en position = contre la gravité
				end
				if up then
					st.antiGravUntil = now + CONFIG.LegitTools.AntiGravityGrace
					break
				end
			else
				st.forces[inst] = nil
			end
		end
	end
	if now < st.antiGravUntil then
		res.gravity = true
		res.gravityProfile = res.gravityProfile
			or st.lastGravityProfile
			or CONFIG.LegitTools.GravityProfile
		st.lastGravityToolT = now
	end

	local trail = CONFIG.LegitTools.ToolTrailingGrace
	res.flyActive = (res.flyProfile ~= nil) or ((now - st.lastFlyToolT) < trail)
	if res.flyActive and not res.flyProfile then
		res.flyProfile = CONFIG.LegitTools.FlyToolDefaultProfile
	end
	res.gravityActive = res.gravity or ((now - st.lastGravityToolT) < trail)
	if res.gravityActive and not res.gravityProfile then
		res.gravityProfile = st.lastGravityProfile or CONFIG.LegitTools.GravityProfile
	end
	if res.speedBonus == 0 and (now - st.lastSpeedToolT) < trail then
		res.speedBonus = st.lastSpeedToolValue or 0
	end
	return res
end

--════════════════════════════════════════════════════════════════════════════
-- ⚛️ PHYSIQUE
--════════════════════════════════════════════════════════════════════════════
local function getJumpStats(hum, mb)
	local g = math.max(workspace.Gravity, 1)
	local extra = 0
	if mb then   -- 🏃 gravité du mouvement PVP + hauteur du double saut
		g = math.max(g * mb.gravMult, 1)
		extra = mb.extraHeight or 0
	end
	if hum.UseJumpPower then
		local jp = math.max(hum.JumpPower, 0)
		local h = (jp * jp) / (2 * g) + extra
		return h, math.max(jp, math.sqrt(2 * g * math.max(h, 0.1)))
	end
	local h = math.max(hum.JumpHeight, 0) + extra
	return h, math.sqrt(2 * g * math.max(h, 0.1))
end

local function allowedHorizontalSpeed(hum, tools, floorSpeed)
	local base = math.max(hum.WalkSpeed, CONFIG.Speed.MinBaselineWalkSpeed, tools.speedBonus)
	--  🆕 V4 : un tapis roulant ou une plateforme mobile ajoute SA vitesse.
	local allowed = base * CONFIG.Speed.Tolerance + CONFIG.Speed.FlatBonus + (floorSpeed or 0)
	if tools.flyActive and tools.flyProfile then
		allowed = math.max(allowed, tools.flyProfile.MaxSpeed)
	end
	return allowed
end

local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude

--  🩹 FIX 2 : un SEUL raycast qui sert aux deux usages — savoir si on est au
--  sol, et savoir à quelle hauteur on est (indispensable au nouveau hover).
local function probeGround(char, pos, maxDist)
	groundRayParams.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(pos, Vector3.new(0, -maxDist, 0), groundRayParams)
	if hit then return hit.Distance, hit end
	return math.huge, nil
end

--  🆕 V4 : vitesse de la pièce sous les pieds (tapis roulant, plateforme).
local function floorSpeedOf(hit)
	if not hit or not hit.Instance then return 0 end
	local ok, v = pcall(function() return hit.Instance:GetVelocityAtPosition(hit.Position) end)
	if ok and typeof(v) == "Vector3" then
		return Vector3.new(v.X, 0, v.Z).Magnitude
	end
	return 0
end

--════════════════════════════════════════════════════════════════════════════
-- 📨 NOTIFICATIONS + RUBBER-BAND
--════════════════════════════════════════════════════════════════════════════
local function notifyClient(player, payload)
	pcall(function() notifyRemote:FireClient(player, payload) end)
end

local function rubberBand(player, st)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or hrp.Anchored then return end
	local target = st.groundPosB or st.groundPosA
	if not target then return end
	pcall(function()
		char:PivotTo(CFrame.new(target + Vector3.new(0, 3.5, 0)))
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end)
end

--════════════════════════════════════════════════════════════════════════════
-- 📝 WARNINGS PERSISTÉS
--════════════════════════════════════════════════════════════════════════════
--  ⏳ Chaque warning a SA PROPRE date d'expiration : il disparaît X jours
--     après avoir été reçu (réglage panel « durée de vie d'un warning »).
--     Avant, tous les warnings s'effaçaient d'un coup si le DERNIER avait
--     plus de 7 jours — un joueur qui en recevait un par semaine les gardait
--     à vie. Maintenant, un faux positif isolé s'efface tout seul, toujours.
local function activeHistory(data, nowT)
	local out = {}
	if type(data) ~= "table" then return out end
	local days = acWarnExpiryDays()
	local limit = (days > 0) and (nowT - days * 86400) or -math.huge
	limit = math.max(limit, acCountFrom())
	if type(data.history) == "table" and #data.history > 0 then
		for _, h in ipairs(data.history) do
			if type(h) == "table" and (tonumber(h.t) or 0) >= limit then
				table.insert(out, h)
			end
		end
		return out
	end
	--  Ancienne fiche sans historique : on se fie au dernier warning.
	local n = tonumber(data.count) or 0
	local last = tonumber(data.lastWarningAt) or 0
	if n > 0 and last >= limit then
		for _ = 1, n do table.insert(out, { t = last, type = "?", details = "ancien warning" }) end
	end
	return out
end

local function activeWarningCount(data, nowT)
	return #activeHistory(data, nowT)
end

local function persistWarning(userId, vType, details)
	local newCount = nil
	local ok, err = pcall(function()
		warningsStore:UpdateAsync("aft_" .. userId, function(old)
			local data = (type(old) == "table") and old or {}
			local now = os.time()
			local hist = activeHistory(data, now)       -- les expirés tombent ici
			table.insert(hist, { t = now, type = vType, details = details })
			--  Assez de place pour un seuil élevé (jusqu'à 1000 warnings).
			while #hist > 1000 do table.remove(hist, 1) end
			data.history = hist
			data.count = #hist
			data.firstWarningAt = hist[1] and hist[1].t or now
			data.lastWarningAt = now
			newCount = data.count
			return data
		end)
	end)
	if not ok then
		warn("🛡️❌ Échec persistance warning pour " .. userId .. " : " .. tostring(err))
	end
	if ok and newCount then StatsStore.indexRealWarning(userId, newCount) end
	return ok, newCount
end

--════════════════════════════════════════════════════════════════════════════
-- 🔨 BAN (mode "ban" uniquement)
--════════════════════════════════════════════════════════════════════════════
local function banPlayer(player, count, vType, details)
	if acShadow() then
		TestLog.recordWarning(player, count, "ban", vType, details)
		warn(string.format("🧪 [SHADOW] %s (%d) SERAIT BANNI | %s | %s | après %d warnings",
			player.Name, player.UserId, vType, details or "", count))
		return
	end

	local userId = player.UserId

	--════════════════════════════════════════════════════════════════
	-- ⚙️ FICHE DU MODE BAN (panel → ⚙️ Modes → 🔨 Ban)
	--    banDays          : 0 = définitif, sinon durée en jours
	--    alsoRestrictUGC  : priver aussi d'UGC (utile si le ban expire)
	--    wipePoints       : remettre les points à 0  ⚠️ irréversible
	--    notifyBeforeKick : laisser le panneau s'afficher avant d'éjecter
	--════════════════════════════════════════════════════════════════
	local banCfg  = acModeCfg("ban")
	local banDays = math.max(math.floor(tonumber(banCfg.banDays) or 0), 0)
	local expires = (banDays > 0) and (os.time() + banDays * 86400) or 0

	local ok = pcall(function()
		banStore:SetAsync(tostring(userId), {
			reason = "ANTI_FLY_TP",
			details = string.format("%s | %s | %d warnings", vType, details or "", count),
			timestamp = os.time(),
			playerName = player.Name,
			--  Date de fin figée au moment du ban : changer `banDays` plus
			--  tard n'allonge pas rétroactivement les bans déjà posés.
			expiresAt = expires,
			days      = banDays,
		})
	end)
	if not ok then
		warn("🛡️❌ Écriture du ban échouée pour " .. userId .. " (retry dans 5s)")
		task.delay(5, function()
			pcall(function()
				banStore:SetAsync(tostring(userId), {
					reason = "ANTI_FLY_TP",
					details = string.format("%s | %d warnings", vType, count),
					timestamp = os.time(), playerName = player.Name,
				})
			end)
		end)
	end

	if CONFIG.Punishment.UseRobloxBanAPI then
		pcall(function()
			Players:BanAsync({
				UserIds = { userId },
				--  -1 = permanent. Sinon Roblox attend des SECONDES.
				Duration = (banDays > 0) and (banDays * 86400) or -1,
				DisplayReason = "Fly/Teleport exploiting after repeated warnings. "
					.. "Contact support if this is a mistake.",
				PrivateReason = string.format("AntiFlyTP: %s | %s", vType, details or ""),
				ExcludeAltAccounts = false, ApplyToUniverse = true,
			})
		end)
	end

	StatsStore.indexRealBan(userId, os.time())
	warn(string.format("🛡️🚫 BAN : %s (%d) | %s | après %d warnings",
		player.Name, userId, vType, count))
	--  ⚙️ Priver aussi d'UGC : le ban peut expirer, la privation non.
	--     Le joueur qui revient ne convertit pas ses points en UGC.
	if banCfg.alsoRestrictUGC == true and _G.UGCRestrict then
		pcall(function()
			_G.UGCRestrict.Add(userId, {
				by = "AntiFlyTP (ban)", auto = true,
				reason = "anticheat_ban", name = player.Name,
				details = string.format("%s — ban après %d warnings", vType, count),
				warnings = count,
			})
		end)
	end

	--  ⚙️ Remise à zéro des points. ⚠️ IRRÉVERSIBLE : décoché par défaut,
	--     et je te déconseille de le cocher tant que tu n'as pas tourné
	--     plusieurs semaines sans un seul faux positif. Si tu te trompes,
	--     tu peux lever un ban ; tu ne peux pas rendre des points.
	if banCfg.wipePoints == true then
		pcall(function()
			if _G.AdminSetPoints then
				_G.AdminSetPoints(userId, 0, "anticheat_ban")
			else
				local ls = player:FindFirstChild("leaderstats")
				local pts = ls and ls:FindFirstChild("Points")
				if pts then pts.Value = 0 end
				player:SetAttribute("Points", 0)
			end
		end)
		warn(string.format("🛡️💸 Points remis à 0 pour %s (wipePoints actif)", player.Name))
	end

	if player.Parent then
		--  💬 Texte du ban configurable dans le panel (section MESSAGES).
		local vars = {
			player = player.Name, type = vType,
			warnings = count, max = count, game = GAME_NAME,
		}
		local body = acMsg("banBody", vars, string.format(CONFIG.Messages.BanMessage, count))
		if banDays > 0 then
			body = body .. string.format("\n\nDuration: %d day(s).", banDays)
		end
		local full = acMsg("banTitle", vars, "Account banned") .. "\n\n" .. body

		--  Laisser le panneau s'afficher avant d'éjecter : le joueur lit la
		--  raison à l'écran, pas seulement dans la boîte de kick.
		if banCfg.notifyBeforeKick == true then
			notifyClient(player, { kind = "warning",
				title = acMsg("banTitle", vars, "Account banned"), body = body })
			task.delay(4, function()
				if player.Parent then player:Kick(full) end
			end)
		else
			player:Kick(full)
		end
	end
end

--════════════════════════════════════════════════════════════════════════════
-- ⚠️ ÉMISSION D'UN WARNING
--   C'est ICI que les trois modes divergent, et nulle part ailleurs.
--════════════════════════════════════════════════════════════════════════════
--  📝 La raison EXACTE, en clair, telle qu'elle s'affiche dans le panel.
local TYPE_LABEL = {
	FLY_STATE   = "🕊️ Vol (état « Flying »)",
	FLY_HOVER   = "🕊️ Vol stationnaire",
	FLY_ASCENT  = "🕊️ Montée sans appui",
	FLY_UPSPEED = "🕊️ Montée trop rapide",
	TELEPORT    = "🌀 Téléportation",
	SPEED       = "💨 Vitesse anormale",
}
local function buildReason(player, st, vType, details, confidence)
	local parts = { (TYPE_LABEL[vType] or vType) .. " — " .. tostring(details or "") }
	--  Ce qui s'est passé dans les 5 dernières minutes, par type.
	local byT, n = {}, 0
	for _, e in ipairs(st.detHistory or {}) do
		byT[e.vType] = (byT[e.vType] or 0) + 1
		n = n + 1
	end
	if n > 0 then
		local bits = {}
		for t, c in pairs(byT) do table.insert(bits, string.format("%d× %s", c, TYPE_LABEL[t] or t)) end
		table.sort(bits)
		table.insert(parts, "Signaux sur 5 min : " .. table.concat(bits, ", "))
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local p = hrp.Position
		table.insert(parts, string.format("Position : %.0f, %.0f, %.0f", p.X, p.Y, p.Z))
	end
	local tools = {}
	if char then
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") then table.insert(tools, c.Name) end
		end
	end
	table.insert(parts, "Outil en main : " .. (#tools > 0 and table.concat(tools, ", ") or "aucun"))
	table.insert(parts, string.format("Certitude : %d %%", math.floor(tonumber(confidence) or 0)))
	return table.concat(parts, "\n")
end

--  Les dernières détections RETENUES du joueur (pour la fiche admin).
local function recentSignals(userId, max)
	local out = {}
	for i = #TestLog.events, 1, -1 do
		local e = TestLog.events[i]
		if e.userId == userId and e.kind == "detection" and e.counted then
			table.insert(out, { t = e.t, type = e.vType, details = e.details, conf = e.conf })
			if #out >= (max or 6) then break end
		end
	end
	return out
end

--  🔎 Tous les « + / − » de la certitude, en version courte pour le journal
local function compactFactors(factors)
	local out = {}
	for _, f in ipairs(factors or {}) do
		if #out >= 16 then break end
		table.insert(out, { d = math.floor(tonumber(f.delta) or 0), l = string.sub(tostring(f.label or "?"), 1, 90) })
	end
	return out
end
local function whyOf(factors)
	local why = {}
	for _, f in ipairs(factors or {}) do
		if #why >= 5 then break end
		table.insert(why, string.format("%+d %s", tonumber(f.delta) or 0, tostring(f.label)))
	end
	return why
end
local function thresholdsNow()
	return { c = acConf("MinConfidenceCount", 55), w = acConf("MinConfidenceWarn", 70),
		sp = CONFIG.Punishment.StrikesPerWarning }
end

local function issueWarning(player, st, vType, details, confidence, factors, extra)
	local userId = player.UserId
	extra = type(extra) == "table" and extra or {}
	local function journal(kind, count, max)
		--  🔎 mêmes infos qu'une détection : où, avec quoi, tous les + / −,
		--     et les certitudes du lot de détections qui a donné ce warning
		FeedLog.push({ kind = kind, uid = userId, name = player.Name, type = vType,
			details = details, conf = math.floor(tonumber(confidence) or 0),
			warnings = count, max = max, shadow = acShadow() or nil,
			ctx = extra.ctx, why = whyOf(factors), fac = compactFactors(factors),
			batch = extra.batch, last = extra.conf, need = thresholdsNow() })
		local fi = TestLog.players[userId]
		if fi then fi.warnActive = count end
	end
	local shadow = acShadow()
	local mode   = acMode()
	confidence = tonumber(confidence) or 0
	details = string.format("%s (certitude %d%%)", details or "", confidence)

	----------------------------------------------------------------
	-- 🧪 SHADOW : on simule, on n'écrit rien de définitif.
	----------------------------------------------------------------
	if shadow then
		st.warnings = (st.warnings or 0) + 1
		local count = st.warnings
		local action

		if mode == "ugc" then
			action = (count >= acWarningsToRestrict()) and "restrict" or "notify"
		else
			action = (count >= CONFIG.Punishment.BanAtWarning) and "ban"
				or (CONFIG.Punishment.WarningActions[count] or "notify")
		end

		TestLog.recordWarning(player, count, action, vType, details)
		journal(action == "restrict" and "sanction" or "warning", count,
			(mode == "ugc") and acWarningsToRestrict() or CONFIG.Punishment.BanAtWarning)
		warn(string.format("🧪 [SHADOW] SERAIT-%s | WARNING %d | %s (%d) | %s | %s",
			string.upper(action), count, player.Name, userId, vType, details or ""))
		return
	end

	----------------------------------------------------------------
	-- ⚖️ RÉEL
	----------------------------------------------------------------
	local ok, newCount = persistWarning(userId, vType, details)
	st.warnings = (ok and newCount) or ((st.warnings or 0) + 1)
	local count = st.warnings

	if mode == "ugc" then
		----------------------------------------------------------------
		-- 🚫 MODE PRIVATION D'UGC — jamais de kick, jamais de ban.
		----------------------------------------------------------------
		--  ⚙️ Le seuil vient de la FICHE DU MODE UGC (panel → ⚙️ Modes).
		--     Un seul endroit le définit, donc le chiffre affiché au joueur
		--     dans « Warning 2/3 » est forcément celui qui déclenche vraiment.
		local threshold = acWarningsToPunish()
		warn(string.format("🛡️⚠️ WARNING %d/%d (mode UGC) | %s (%d) | %s | %s",
			count, threshold, player.Name, userId, vType, details or ""))

		if count >= threshold and _G.UGCRestrict then
			local fiche = TestLog.players[userId]
			--  Certitude du DOSSIER, pas de la dernière détection : moyenne de
			--  tout ce qui a été retenu contre ce joueur depuis le début de sa
			--  session. C'est ce chiffre qui doit franchir le seuil de sanction.
			local caseConf = confidence
			if fiche and (fiche.confCount or 0) > 0 then
				caseConf = math.floor(fiche.confSum / fiche.confCount)
			end
			local okR = _G.UGCRestrict.AutoRestrict(player, {
				details    = string.format("%s — %s", vType, details or ""),
				reasonText = buildReason(player, st, vType, details, caseConf),
				signals    = recentSignals(userId, 6),
				warnings   = count,
				detections = fiche and fiche.total or 0,
				byType     = fiche and fiche.detections or {},
				confidence = caseConf,
				factors    = factors,
			})
			TestLog.recordWarning(player, count, "restrict", vType, details)
			journal(okR and "sanction" or "warning", count, threshold)
			if okR then
				log(string.format("Privation d'UGC appliquée à %s après %d warnings",
					player.Name, count))
			end
		else
			TestLog.recordWarning(player, count, "notify", vType, details)
			journal("warning", count, threshold)
			--  💬 Carte rouge « warning officiel », texte pris dans le panel.
			--     `warnEnabled = false` la coupe complètement : le warning est
			--     toujours compté et persisté, le joueur n'en est simplement
			--     pas informé. 🤫 Mode discret : jamais affichée.
			if acMsgFlag("warnEnabled", true) == true and not acSilent() then
				local vars = {
					player = player.Name, type = vType,
					warnings = count, max = threshold,
					confidence = confidence, game = GAME_NAME,
				}
				notifyClient(player, {
					kind  = "warning",
					title = acMsg("warnTitle", vars,
						string.format(CONFIG.Messages.WarningTitle, count, threshold)),
					body  = acMsg("warnBody", vars, CONFIG.Messages.WarningBody),
					count = count, max = threshold,
				})
			end
		end
		return
	end

	----------------------------------------------------------------
	-- 🔨 MODE BAN — échelle classique
	----------------------------------------------------------------
	--  ⚙️ Seuil et options du MODE BAN, pris dans sa fiche (panel → ⚙️ Modes).
	local banCfg = acModeCfg("ban")
	local banAt  = tonumber(banCfg.warningsToPunish) or CONFIG.Punishment.BanAtWarning
	warn(string.format("🛡️⚠️ WARNING %d/%d | %s (%d) | %s | %s",
		count, banAt, player.Name, userId, vType, details or ""))

	local action = (count >= banAt) and "ban"
		or (CONFIG.Punishment.WarningActions[count] or "notify")

	--  ⚙️ « Kick d'avertissement » : au warning juste avant le dernier, on
	--     éjecte une fois pour marquer le coup. Le joueur peut revenir —
	--     c'est un signal, pas une sanction. Décochable dans la fiche.
	if action ~= "ban" and banCfg.kickBeforeBan == true and count == (banAt - 1) then
		action = "kick"
	elseif action == "kick" and banCfg.kickBeforeBan == false then
		action = "notify"
	end
	--  🤫 Discret : aucun kick d'avertissement (il dirait au joueur qu'il est vu).
	if action == "kick" and acSilent() then action = "notify" end

	--  🎯 Un ban permanent est irréversible dans les faits : le joueur ne
	--  revient pas t'expliquer. On exige donc le seuil de certitude le plus
	--  haut. En dessous, on rétrograde en kick et le dossier reste ouvert
	--  dans le panel pour que TU tranches.
	if action == "ban" then
		local minSanction = acConf("MinConfidenceSanction", 85)
		if confidence < minSanction then
			warn(string.format(
				"🎯 Ban refusé pour %s : certitude %d%% < %d%% requis → kick à la place. "
					.. "Le dossier t'attend dans le panel.",
				player.Name, confidence, minSanction))
			action = "kick"
		end
	end

	TestLog.recordWarning(player, count, action, vType, details)
	journal(action == "ban" and "sanction" or "warning", count, banAt)

	if action == "ban" then
		banPlayer(player, count, vType, details)
	elseif action == "kick" then
		if player.Parent then
			local vars = {
				player = player.Name, type = vType,
				warnings = count, max = banAt,
				confidence = confidence, game = GAME_NAME,
			}
			player:Kick(acMsg("warnTitle", vars, "Warning")
				.. "\n\n"
				.. acMsg("warnBody", vars,
					string.format(CONFIG.Messages.KickMessage, count, banAt)))
		end
	else
		if acMsgFlag("warnEnabled", true) == true and not acSilent() then
			local vars = {
				player = player.Name, type = vType,
				warnings = count, max = banAt,
				confidence = confidence, game = GAME_NAME,
			}
			notifyClient(player, {
				kind  = "warning",
				title = acMsg("warnTitle", vars,
					string.format(CONFIG.Messages.WarningTitle, count, banAt)),
				body  = acMsg("warnBody", vars, CONFIG.Messages.WarningBody),
				count = count, max = banAt,
			})
		end
	end
end

--════════════════════════════════════════════════════════════════════════════
-- 🚨 ENREGISTREMENT D'UNE VIOLATION
--════════════════════════════════════════════════════════════════════════════
--════════════════════════════════════════════════════════════════════════════
-- 🎯 NOTATION D'UNE DÉTECTION
--
--  Rend un pourcentage de certitude et la LISTE DES FACTEURS qui l'ont
--  produit. C'est cette liste qui compte autant que le chiffre : quand un
--  joueur fait appel, tu ne lis pas « l'anti-cheat a décidé », tu lis ce que
--  la machine a réellement observé, ligne par ligne.
--
--  Le principe est simple à énoncer : tout ce qui pourrait expliquer la
--  mesure autrement qu'un triche FAIT BAISSER le score. On ne cherche pas
--  à prouver que le joueur triche — on cherche à éliminer tout le reste.
--════════════════════════════════════════════════════════════════════════════
local function scoreDetection(player, st, vType, ctx)
	local CF = CONFIG.Confidence
	if not CF.Enabled then
		return 100, { { label = "Notation désactivée dans la config", delta = 0 } }
	end

	ctx = ctx or {}
	local now = os.clock()
	local factors = {}
	local function add(label, delta)
		if delta == 0 then return end
		table.insert(factors, { label = label, delta = delta })
	end

	--  Historique glissant sur 5 minutes.
	local fresh = {}
	for _, e in ipairs(st.detHistory) do
		if now - e.t < 300 then table.insert(fresh, e) end
	end
	st.detHistory = fresh

	----------------------------------------------------------------
	-- Base : à quel point ce type de signal est fiable en lui-même
	----------------------------------------------------------------
	local score = CF.Base[vType] or 45
	add("Signal « " .. vType .. " »", score)

	----------------------------------------------------------------
	-- Bonus de marge : frôler un seuil ne prouve rien, le doubler si
	----------------------------------------------------------------
	local ratio = tonumber(ctx.ratio)
	if ratio and ratio > 1 then
		local b = math.floor(math.clamp(ratio - 1, 0, 1) * CF.MarginMax)
		add(string.format("Dépasse le seuil de %d %%", math.floor((ratio - 1) * 100)), b)
		score = score + b
	end

	local durRatio = tonumber(ctx.durationRatio)
	if durRatio and durRatio > 1 then
		local b = math.floor(math.clamp(durRatio - 1, 0, 1) * CF.DurationMax)
		add("Comportement tenu bien au-delà de la durée limite", b)
		score = score + b
	end

	----------------------------------------------------------------
	-- Pénalités : tout ce qui pourrait expliquer la mesure autrement
	----------------------------------------------------------------
	local W = CF.RecentWindow
	local clean = true

	--  `since` rend le temps écoulé DEPUIS l'expiration d'une fenêtre.
	--  Négatif = la fenêtre est encore ouverte (mais alors on n'aurait pas
	--  détecté). Entre 0 et W = elle vient de se fermer, donc le joueur est
	--  peut-être encore sur sa lancée.
	local function since(untilT)
		if not untilT or untilT <= 0 then return math.huge end
		return now - untilT
	end

	local g = since(st.graceUntil)
	if g >= 0 and g < W then
		add(string.format("Une grâce « %s » vient d'expirer (il y a %d s)",
			st.graceReason ~= "" and st.graceReason or "?", math.floor(g)),
			-CF.PenaltyRecentGrace)
		score = score - CF.PenaltyRecentGrace ; clean = false
	end

	local l = since(st.launchUntil)
	if l >= 0 and l < W then
		add(string.format("Propulsé il y a %d s — il est peut-être encore sur son élan",
			math.floor(l)), -CF.PenaltyRecentLaunch)
		score = score - CF.PenaltyRecentLaunch ; clean = false
	end

	local r = since(st.ragdollUntil)
	if r >= 0 and r < W then
		add(string.format("Sortie de ragdoll il y a %d s", math.floor(r)),
			-CF.PenaltyRecentRagdoll)
		score = score - CF.PenaltyRecentRagdoll ; clean = false
	end

	local f = since(st.antiGravUntil)
	if f >= 0 and f < W then
		add(string.format("Force anti-gravité vue sur lui il y a %d s", math.floor(f)),
			-CF.PenaltyRecentForce)
		score = score - CF.PenaltyRecentForce ; clean = false
	end

	local age = now - (st.spawnT or now)
	if age < 25 then
		add(string.format("Apparu il y a seulement %d s", math.floor(age)),
			-CF.PenaltyRecentSpawn)
		score = score - CF.PenaltyRecentSpawn ; clean = false
	end

	local dt = tonumber(ctx.dt) or CONFIG.Sampling.Interval
	if dt > CONFIG.Sampling.Interval * 2 then
		add(string.format("Mesure prise sur %.2f s au lieu de %.2f s (serveur chargé)",
			dt, CONFIG.Sampling.Interval), -CF.PenaltyLongDt)
		score = score - CF.PenaltyLongDt ; clean = false
	end

	if not st.everDetected then
		add("Toute première détection de sa session", -CF.PenaltyFirstEver)
		score = score - CF.PenaltyFirstEver
	end

	if clean then
		add("Aucune grâce, aucune force, aucune propulsion : rien n'explique la mesure",
			CF.CleanContext)
		score = score + CF.CleanContext
	end

	----------------------------------------------------------------
	-- Bonus de faisceau : c'est là que la certitude se construit
	----------------------------------------------------------------
	local sameType, types = 0, {}
	for _, e in ipairs(st.detHistory) do
		types[e.vType] = true
		if e.vType == vType and (now - e.t) < 60 then sameType = sameType + 1 end
	end

	if sameType > 0 then
		local b = math.min(sameType * CF.RepeatPer, CF.RepeatMax)
		add(string.format("%d signal identique dans la dernière minute", sameType), b)
		score = score + b
	end

	types[vType] = true
	local nTypes = 0
	for _ in pairs(types) do nTypes = nTypes + 1 end
	if nTypes > 1 then
		--  Un bug produit toujours le même symptôme. Un tricheur en produit
		--  plusieurs, parce qu'il fait plusieurs choses anormales à la fois.
		local b = math.min((nTypes - 1) * CF.DiversityPer, CF.DiversityMax)
		add(string.format("%d types de signaux différents en 5 min", nTypes), b)
		score = score + b
	end

	if (st.warnings or 0) > 0 then
		add(string.format("%d warning déjà au dossier", st.warnings), CF.HistoryBonus)
		score = score + CF.HistoryBonus
	end

	local airTime = now - (st.lastGroundT or now)
	if airTime > CF.NoGroundSeconds and vType ~= "SPEED" then
		add(string.format("Aucun contact avec le sol depuis %d s", math.floor(airTime)),
			CF.NoGroundBonus)
		score = score + CF.NoGroundBonus
	end

	score = math.clamp(math.floor(score), 0, CF.Ceiling)
	return score, factors
end

--════════════════════════════════════════════════════════════════════════════
-- 🚨 ENREGISTREMENT D'UNE VIOLATION
--════════════════════════════════════════════════════════════════════════════
--  📍 Le CONTEXTE d'une détection, en clair : où, avec quoi, dans quel état.
local function contextOf(player, st)
	local now = os.clock()
	local c = {}
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local p = hrp.Position
		c.pos = string.format("%.0f, %.0f, %.0f", p.X, p.Y, p.Z)
		local v = hrp.AssemblyLinearVelocity
		c.speed = math.floor(Vector3.new(v.X, 0, v.Z).Magnitude + 0.5)
		c.vy = math.floor(v.Y + 0.5)
	end
	local tools = {}
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") then table.insert(tools, t.Name) end
		end
	end
	c.tool = (#tools > 0) and table.concat(tools, ", ") or "aucun"
	c.arena = isInArena(player) == true
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then c.walk = math.floor(hum.WalkSpeed + 0.5) end
	local notes = {}
	if now < (st.launchUntil or 0) + 3 then table.insert(notes, "propulsé juste avant") end
	if now < (st.ragdollUntil or 0) + 3 then table.insert(notes, "sortait d'un ragdoll") end
	if now < (st.graceUntil or 0) + 3 then table.insert(notes, "tolérance « " .. tostring(st.graceReason) .. " » à peine finie") end
	if (st.floorSpeed or 0) > 1 then table.insert(notes, "sur un sol qui bouge") end
	if player:GetAttribute("Ziplining") or (char and char:GetAttribute("Ziplining")) then
		table.insert(notes, "attribut tyrolienne loin d'une corde")
	end
	c.notes = (#notes > 0) and table.concat(notes, " · ") or nil
	return c
end

local function registerViolation(player, st, vType, details, ctx)
	local now = os.clock()
	local shadow = acShadow()

	local conf, factors = scoreDetection(player, st, vType, ctx)
	local minCount = acConf("MinConfidenceCount", 55)
	local counted  = conf >= minCount

	--  Resynchronisation dans TOUS les cas, même quand on écarte le signal :
	--  sinon la mesure suivante compare une position à une ancienne et
	--  fabrique un second faux positif dans la foulée.
	st.lastPos = nil
	st.lastVel = Vector3.zero
	resetAir(st, nil)

	table.insert(st.detHistory, { t = now, vType = vType, conf = conf })
	st.everDetected = true

	TestLog.recordDetection(player, vType, details, conf, factors, counted)

	--  📰 Journal partagé + dernier signal du dossier (détections RETENUES seulement)
	if counted then
		local cx = contextOf(player, st)
		FeedLog.push({
			kind = "detection", uid = player.UserId, name = player.Name,
			type = vType, details = details, conf = conf, ctx = cx, why = whyOf(factors),
			fac = compactFactors(factors), need = thresholdsNow(),
			warnings = st.warnings or 0, strikes = st.strikes or 0, shadow = shadow or nil,
		})
		local fi = TestLog.players[player.UserId]
		if fi then
			fi.lastAt, fi.lastType, fi.lastDetail = os.time(), vType, details
			fi.lastCtx = string.format("pos %s · outil : %s%s%s", cx.pos or "?", cx.tool,
				cx.arena and " · arène" or "", cx.notes and (" · " .. cx.notes) or "")
			fi.warnActive = st.warnings or 0
		end
	end

	----------------------------------------------------------------
	-- 🎯 SIGNAL ÉCARTÉ
	--    On ne corrige RIEN et on ne compte RIEN. C'est le point clé : un
	--    joueur honnête ne doit même pas sentir qu'il a été mesuré. Le
	--    rubber-band d'un faux positif en plein run d'obby est ce qui fait
	--    le plus de dégâts, bien plus qu'un warning qu'il ne verra jamais.
	----------------------------------------------------------------
	if not counted then
		log(string.format("Signal écarté — %s sur %s : %d%% < %d%% (%s)",
			vType, player.Name, conf, minCount, details or ""))
		return
	end

	warn(string.format("%s Détection %s (%d%% de certitude) | %s (%d) | %s",
		shadow and "🧪🚨 [SHADOW]" or "🛡️🚨",
		vType, conf, player.Name, player.UserId, details or ""))

	--  Correction visible : en mode réel, et en shadow seulement si tu as
	--  coché « corriger sans punir » dans la fiche du mode TEST.
	local testCfg = acModeCfg("test")
	local shadowCorrects = (testCfg.correctPosition ~= nil)
		and (testCfg.correctPosition == true)
		or ((testCfg.correctPosition == nil) and acShadowCorrect())
	local correct = (not shadow) or shadowCorrects

	--  💬 Le joueur voit-il quelque chose ? En shadow, la fiche TEST peut
	--     couper complètement l'affichage : observation silencieuse.
	local mayNotify = ((not shadow) or (testCfg.notifyPlayer == true)) and not acSilent()

	--════════════════════════════════════════════════════════════════
	-- ⚠️ CARTE ORANGE « APRÈS PLUSIEURS DÉTECTIONS »
	--
	--  ⚠️ Ce bloc est VOLONTAIREMENT hors du `if correct then`. Les deux
	--     réglages du mode test sont indépendants : « corriger la position »
	--     et « le joueur voit les cartes ». Les imbriquer rendait la seconde
	--     case sans effet dès que la première était décochée — or décochée
	--     est justement son réglage recommandé.
	--════════════════════════════════════════════════════════════════
	do
		--    Trois réglages, tous dans la section MESSAGES du panel :
		--      • nudgeEnabled         → l'afficher ou pas du tout
		--      • nudgeAfterDetections → à partir de combien de détections
		--                               COMPTÉES dans cette session
		--      • nudgeCooldown        → délai minimum entre deux cartes
		--
		--    On compte les détections comptées, pas les détections brutes :
		--    une mesure écartée pour cause de certitude trop faible ne
		--    rapproche personne d'une carte à l'écran.
		--════════════════════════════════════════════════════════════
		st.countedDet = (st.countedDet or 0) + 1

		local nudgeOn     = acMsgFlag("nudgeEnabled", CONFIG.Punishment.NudgeOnDetection) == true
		local nudgeAfter  = tonumber(acMsgFlag("nudgeAfterDetections", 1)) or 1
		local nudgeGap    = tonumber(acMsgFlag("nudgeCooldown", 5)) or 5

		if nudgeOn and mayNotify
			and st.countedDet >= nudgeAfter
			and (now - st.lastNudgeT) > nudgeGap then
			st.lastNudgeT = now
			local vars = {
				player = player.Name, type = vType,
				warnings = st.warnings or 0, confidence = conf,
				game = GAME_NAME,
			}
			notifyClient(player, {
				kind  = "nudge",
				title = acMsg("nudgeTitle", vars, CONFIG.Messages.NudgeTitle),
				body  = acMsg("nudgeBody",  vars, CONFIG.Messages.NudgeBody),
			})
		end

	end

	--  Correction de position : celle-ci, oui, dépend de `correct`.
	--  🤫 En mode discret, on ne ramène JAMAIS le joueur en arrière : un
	--     retour en arrière lui dirait qu'il a été détecté.
	if correct then
		if CONFIG.Punishment.RubberBand and not acSilent() then rubberBand(player, st) end
		st.suspendSamples = 2
	end

	--  Anti-cascade : une même glissade ne compte qu'une fois.
	if (now - st.lastCountedT) < CONFIG.Punishment.EscalationCooldown then return end
	st.lastCountedT = now
	st.lastStrikeT  = now

	table.insert(st.batchConf, conf)
	st.strikes = st.strikes + (CONFIG.Punishment.StrikeWeights[vType] or 1)
	log(string.format("Strike %d/%d pour %s (%s, %d%%)%s",
		st.strikes, CONFIG.Punishment.StrikesPerWarning, player.Name, vType, conf,
		shadow and " [SHADOW]" or ""))

	if st.strikes >= CONFIG.Punishment.StrikesPerWarning then
		st.strikes = 0

		--  Moyenne du lot : un warning n'est pas déclenché par la détection la
		--  plus forte, mais par la QUALITÉ MOYENNE du faisceau. Trois signaux
		--  à 58 % ne valent pas un dossier.
		local sum = 0
		for _, c in ipairs(st.batchConf) do sum = sum + c end
		local avg = (#st.batchConf > 0) and (sum / #st.batchConf) or conf
		local batch = st.batchConf
		st.batchConf = {}

		local minWarn = acConf("MinConfidenceWarn", 70)
		if avg < minWarn then
			log(string.format(
				"Lot de strikes écarté pour %s : moyenne %d%% < %d%% requis (%d signaux)",
				player.Name, math.floor(avg), minWarn, #batch))
			return
		end

		issueWarning(player, st, vType, details, math.floor(avg), factors,
			{ ctx = contextOf(player, st), batch = batch, conf = conf })
	end
end

--════════════════════════════════════════════════════════════════════════════
-- 🔬 ANALYSE D'UN JOUEUR — LE CŒUR
--════════════════════════════════════════════════════════════════════════════
local function samplePlayer(player)
	local userId = player.UserId
	local st = S[userId]
	if not st then return end

	local now = os.clock()
	local dt = now - st.lastT
	st.lastT = now

	-- 🩹 FIX 10 : décroissance passive des strikes.
	if CONFIG.Punishment.PassiveDecay and st.strikes > 0 then
		if (now - st.lastStrikeT) > CONFIG.Punishment.StrikeDecaySeconds then
			st.strikes = math.max(0, st.strikes - 1)
			st.lastStrikeT = now
			log(string.format("Strike retiré à %s (calme prolongé) → %d",
				player.Name, st.strikes))
		end
	end

	-- 🩹 FIX 6 : lag serveur → on resynchronise sans juger.
	if dt <= 0 or dt > CONFIG.Sampling.MaxUsableDelta then
		st.lastPos = nil ; st.lastVel = Vector3.zero
		return
	end

	local char = player.Character
	if not char then st.lastPos = nil return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then st.lastPos = nil return end

	local pos = hrp.Position

	if st.suspendSamples > 0 then
		st.suspendSamples = st.suspendSamples - 1
		st.lastPos = pos ; st.lastVel = Vector3.zero
		return
	end

	----------------------------------------------------------------
	-- 🚪 SORTIES IMMÉDIATES
	----------------------------------------------------------------
	local humState = hum:GetState()

	-- 🩹 FIX 8 : ragdoll / PlatformStand → le Humanoid n'a plus la main.
	if CONFIG.Ragdoll.SkipWhileRagdolled then
		if hum.PlatformStand or CONFIG.Ragdoll.States[humState] then
			st.ragdollUntil = now + CONFIG.Ragdoll.GraceAfter
		end
	end

	if isWhitelisted(userId)
		or globalTolerance()
		or player.GameplayPaused
		or externallyBusy(userId)
		or hrp.Anchored
		or hum.SeatPart ~= nil
		or now < st.ragdollUntil
		or anyFullBypassAttribute(player, char) then
		st.lastPos = pos ; st.lastVel = Vector3.zero
		resetAir(st, pos.Y)
		st.speedCount = 0
		return
	end

	if not st.lastPos then
		st.lastPos = pos ; st.lastVel = Vector3.zero
		resetAir(st, pos.Y)
		return
	end

	----------------------------------------------------------------
	-- 📐 MESURES
	----------------------------------------------------------------
	local delta = pos - st.lastPos
	local mVel  = delta / dt
	local realVel = hrp.AssemblyLinearVelocity

	-- 🩹 FIX 7 : propulsion sans mover (launcher qui écrit la vélocité).
	if realVel.Magnitude > CONFIG.Launchers.VelocitySpikeThreshold then
		st.launchUntil = math.max(st.launchUntil,
			now + CONFIG.Launchers.VelocitySpikeGrace)
	end

	local graced   = now < st.graceUntil
	local launched = now < st.launchUntil
	local inArena  = isInArena(player)
	local tools    = classifyTools(char, st, now)
	local mb       = moveBoostFor(player)   -- 🏃 mouvement PVP actif pour ce joueur ?
	if mb then
		tools.speedBonus = math.max(tools.speedBonus,
			math.ceil((mb.maxSpeed - CONFIG.Speed.FlatBonus) / CONFIG.Speed.Tolerance))
	end

	----------------------------------------------------------------
	-- 🌍 SOL / AIR  (calculé AVANT le téléport : on en a besoin)
	----------------------------------------------------------------
	local probeDist = math.max(CONFIG.Fly.GroundRayDistance, CONFIG.Fly.HoverMinHeight + 2)
	local groundDist, groundHit = probeGround(char, pos, probeDist)

	--  🆕 V4 : vitesse du sol, gardée en mémoire un court instant.
	if CONFIG.Floor.Enabled then
		local fs = (groundDist <= CONFIG.Fly.GroundRayDistance) and floorSpeedOf(groundHit) or 0
		if fs > 0.5 then
			st.floorSpeed = math.max(fs, (now - (st.floorT or 0)) < CONFIG.Floor.Memory and (st.floorSpeed or 0) or 0)
			st.floorT = now
		elseif (now - (st.floorT or 0)) >= CONFIG.Floor.Memory then
			st.floorSpeed = 0
		end
	end

	local onGround = (hum.FloorMaterial ~= Enum.Material.Air)
		or (groundDist <= CONFIG.Fly.GroundRayDistance)

	if CONFIG.Fly.TreatClimbingAsGround and humState == Enum.HumanoidStateType.Climbing then
		onGround = true
	end
	if CONFIG.Fly.TreatSwimmingAsGround and humState == Enum.HumanoidStateType.Swimming then
		onGround = true
	end

	-- 🩹 FIX 9 : l'atterrissage est LE moment où la prédiction se casse.
	if onGround and not st.wasOnGround then
		st.landingUntil = now + CONFIG.Grace.LandingSeconds
	end
	local landing = now < st.landingUntil

	if onGround then
		if (now - st.groundMemT) >= 2 then
			st.groundPosB = st.groundPosA or pos
			st.groundMemT = now
		end
		st.groundPosA = pos
		st.lastGroundT = now
	end

	----------------------------------------------------------------
	-- 🚀 1) TÉLÉPORTATION
	----------------------------------------------------------------
	if CONFIG.Teleport.Enabled and not (inArena and CONFIG.Arena.SkipTeleport) then
		-- 🩹 FIX 1 : on ne compare plus une seule erreur globale à un seuil fixe.
		local err   = delta - (st.lastVel * dt)
		local errH  = Vector3.new(err.X, 0, err.Z).Magnitude
		local errV  = math.abs(err.Y)

		--  Tolérance verticale calculée à CHAQUE mesure : la chute libre
		--  ajoute mécaniquement 0.5·g·dt², et un atterrissage annule d'un coup
		--  toute la vitesse de chute. C'est exactement ça qui produisait des
		--  « sauts de 80 studs » dans un obby avec de longues chutes.
		local gravDrop = 0.5 * workspace.Gravity * dt * dt
		local vTol = CONFIG.Teleport.MaxVerticalError
			+ gravDrop
			+ math.abs(st.lastVel.Y) * dt * 0.9
		local hTol = CONFIG.Teleport.MaxPredictionError

		local suspicious = (delta.Magnitude >= CONFIG.Teleport.MinTeleportDistance)
			and (errH > hTol or errV > vTol)

		if suspicious then
			local legit = false

			if graced or launched or landing then
				legit = true
			elseif CONFIG.Teleport.IgnoreIfVelocityConsistent then
				--  On accepte que le déplacement soit expliqué par la vitesse
				--  d'AVANT ou celle d'APRÈS : pendant une accélération brutale
				--  (propulsion), seule l'une des deux est représentative.
				local ratio = CONFIG.Teleport.VelocityConsistencyRatio
				local need  = delta.Magnitude * ratio
				if (realVel.Magnitude * dt) >= need
					or (st.lastVel.Magnitude * dt) >= need then
					legit = true
				end
			end

			if not legit and isNearAlwaysSafe(pos) then legit = true end
			if not legit and isNearCheckpoint(pos) and checkpointTpAllowed(st, now) then
				legit = true
			end

			if legit then
				st.lastPos = pos ; st.lastVel = mVel
				resetAir(st, pos.Y)
				st.wasOnGround = onGround
				return
			end

			registerViolation(player, st, "TELEPORT", string.format(
				"saut de %.0f studs (écart H %.0f / V %.0f, dt %.2fs)",
				delta.Magnitude, errH, errV, dt),
				{ dt = dt, ratio = math.max(errH / hTol, errV / vTol) })
			return
		end
	end

	----------------------------------------------------------------
	-- 🕊️ 2) VOL
	----------------------------------------------------------------
	local flyMode = inArena and CONFIG.Arena.FlyMode or "normal"

	if CONFIG.Fly.Enabled and flyMode ~= "off" then
		if graced or launched or landing or tools.flyActive or onGround then
			resetAir(st, pos.Y)
		else
			if not st.airStartY then st.airStartY = pos.Y end

			if humState == Enum.HumanoidStateType.Flying then
				registerViolation(player, st, "FLY_STATE",
					"HumanoidState = Flying sans jetpack", { dt = dt })
				return
			end

			local jumpH, jumpV = getJumpStats(hum, mb)
			local maxHover    = CONFIG.Fly.MaxHoverTime / ((mb and mb.gravMult) or 1)   -- 🏃 gravité faible = plus longtemps en l'air
			--  🆕 V4 : gravité du monde réduite (météo Admin Abuse) → même logique.
			if CONFIG.ScaleHoverWithGravity then
				maxHover = maxHover * math.max(1, 196.2 / math.max(workspace.Gravity, 1))
			end
			local ascentAllow = jumpH * CONFIG.Fly.AscentMultiplier + CONFIG.Fly.AscentFlatBonus
			local upAllow     = jumpV * CONFIG.Fly.MaxUpSpeedMultiplier + CONFIG.Fly.MaxUpSpeedFlat

			if tools.gravityActive then
				local gp = tools.gravityProfile or CONFIG.LegitTools.GravityProfile
				maxHover    = math.max(maxHover, gp.MaxHoverTime)
				ascentAllow = math.max(ascentAllow, jumpH * CONFIG.Fly.AscentMultiplier + gp.AscentFlat)
				upAllow     = math.max(upAllow, gp.MaxUpSpeed)
			end
			if flyMode == "relaxed" then
				maxHover    = math.max(maxHover, CONFIG.Arena.RelaxedHoverTime)
				ascentAllow = math.max(ascentAllow, CONFIG.Arena.RelaxedAscentFlat)
			end

			-- 🩹 FIX 2 : vrai vol stationnaire = immobile ET en hauteur.
			if CONFIG.Fly.DetectHover then
				local reallyHovering =
					(math.abs(mVel.Y) <= CONFIG.Fly.HoverBandY)
					and (groundDist > CONFIG.Fly.HoverMinHeight)

				if reallyHovering then
					st.hoverTime = st.hoverTime + dt
				else
					--  Reset franc : un joueur qui monte ou qui tombe n'est
					--  pas « un peu en train de voler ». C'est tout ou rien.
					st.hoverTime = 0
				end

				if st.hoverTime > maxHover then
					local held = st.hoverTime
					st.hoverTime = 0
					registerViolation(player, st, "FLY_HOVER", string.format(
						"immobile en l'air %.1fs (limite %.1fs) à %.0f studs du sol",
						held, maxHover, groundDist),
						{ dt = dt, durationRatio = held / math.max(maxHover, 0.1),
							ratio = groundDist / math.max(CONFIG.Fly.HoverMinHeight, 1) })
					return
				end
			end

			if CONFIG.Fly.DetectAscent then
				local ascent = pos.Y - st.airStartY
				if ascent > ascentAllow then
					registerViolation(player, st, "FLY_ASCENT", string.format(
						"+%.0f studs en l'air (max %.0f)", ascent, ascentAllow),
						{ dt = dt, ratio = ascent / math.max(ascentAllow, 1) })
					return
				end
			end

			if CONFIG.Fly.DetectUpSpeed then
				if mVel.Y > upAllow then
					st.upCount = st.upCount + 1
					if st.upCount >= CONFIG.Fly.UpSpeedSamples then
						st.upCount = 0
						registerViolation(player, st, "FLY_UPSPEED", string.format(
							"%.0f studs/s vertical soutenu (max %.0f)", mVel.Y, upAllow),
							{ dt = dt, ratio = mVel.Y / math.max(upAllow, 1) })
						return
					end
				else
					st.upCount = 0
				end
			end
		end
	end

	----------------------------------------------------------------
	-- 💨 3) VITESSE HORIZONTALE
	----------------------------------------------------------------
	if CONFIG.Speed.Enabled and not (inArena and CONFIG.Arena.SkipSpeed) then
		if graced or launched then
			st.speedCount = 0
		else
			local hSpeed = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
			local allowed = allowedHorizontalSpeed(hum, tools, st.floorSpeed)

			if hSpeed > allowed then
				st.speedCount = st.speedCount + 1
				if st.speedCount >= CONFIG.Speed.SustainedSamples then
					st.speedCount = 0
					registerViolation(player, st, "SPEED", string.format(
						"%.0f studs/s pendant %.1fs (max %.0f)",
						hSpeed, CONFIG.Speed.SustainedSamples * CONFIG.Sampling.Interval, allowed),
						{ dt = dt, ratio = hSpeed / math.max(allowed, 1) })
					return
				end
			else
				-- 🩹 FIX 3 : reset franc. On veut du soutenu, pas du cumulé.
				st.speedCount = 0
			end
		end
	end

	st.lastPos = pos
	st.lastVel = mVel
	st.wasOnGround = onGround
end

--════════════════════════════════════════════════════════════════════════════
-- 🔄 BOUCLE PRINCIPALE
--════════════════════════════════════════════════════════════════════════════
task.spawn(function()
	while true do
		task.wait(CONFIG.Sampling.Interval)
		if CONFIG.Enabled then
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(samplePlayer, player)
				if not ok then
					warn("🛡️❌ Erreur d'analyse pour " .. player.Name .. " : " .. tostring(err))
				end
			end
		end
	end
end)

--════════════════════════════════════════════════════════════════════════════
-- 👤 CYCLE DE VIE
--════════════════════════════════════════════════════════════════════════════
local MOVER_SET = {}
for _, cn in ipairs(CONFIG.Launchers.MoverClasses) do MOVER_SET[cn] = true end

local function trackForce(st, inst)
	if inst:IsA("BodyForce") or inst:IsA("VectorForce")
		or inst:IsA("BodyPosition") or inst:IsA("AlignPosition") then
		st.forces[inst] = true
	end
end

local function onCharacter(player, char)
	local st = S[player.UserId]
	if not st then return end

	st.lastPos = nil
	resetAir(st, nil)
	st.groundPosA, st.groundPosB = nil, nil
	st.forces = {}
	st.antiGravUntil = 0
	st.ragdollUntil = 0
	st.launchUntil = 0
	st.speedCount = 0
	st.wasOnGround = true
	st.spawnT = os.clock()
	st.batchConf = {}

	giveGrace(player, CONFIG.Grace.SpawnSeconds, "spawn")

	--  Un coil peut déjà être équipé au moment du spawn.
	for _, d in ipairs(char:GetDescendants()) do trackForce(st, d) end

	for _, attrName in ipairs(CONFIG.LegitAttributes.WatchForTrailing) do
		char:GetAttributeChangedSignal(attrName):Connect(function()
			giveGrace(player, CONFIG.LegitAttributes.TrailingGrace, attrName .. "_change")
		end)
	end

	--  🆕 V4 : TÉLÉPORTATION FAITE PAR LE SERVEUR.
	--     Côté serveur, le signal CFrame de la racine ne se déclenche QUE
	--     quand un script serveur écrit la position (PivotTo, CFrame =, MoveTo).
	--     Les mouvements du joueur arrivent par la physique et ne le
	--     déclenchent jamais : un tricheur ne peut donc pas s'en servir.
	if CONFIG.ServerMoves.Enabled then
		task.spawn(function()
			local hrp = char:WaitForChild("HumanoidRootPart", 10)
			if not hrp then return end
			hrp:GetPropertyChangedSignal("CFrame"):Connect(function()
				local s2 = S[player.UserId]
				if not s2 then return end
				--  On repart de la NOUVELLE position : le saut n'est pas compté
				--  comme une téléportation. Volontairement, on ne donne PAS de
				--  grâce générale : le vol et la vitesse restent mesurés juste
				--  après (une téléportation serveur n'autorise pas à voler).
				s2.lastPos = nil
				s2.lastVel = Vector3.zero
				s2.speedCount = 0
				s2.serverMoveT = os.clock()
				resetAir(s2, nil)
			end)
		end)
	end

	char.DescendantAdded:Connect(function(inst)
		trackForce(st, inst)
		if CONFIG.Launchers.AutoGraceOnMover and MOVER_SET[inst.ClassName] then
			st.launchUntil = math.max(st.launchUntil,
				os.clock() + CONFIG.Launchers.MoverGrace)
		end
	end)

	char.DescendantRemoving:Connect(function(inst)
		if st.forces[inst] then
			st.forces[inst] = nil
			-- 🩹 FIX 4 : une force qui disparaît laisse le joueur sur sa lancée.
			-- On prolonge un peu la grâce pour couvrir la retombée.
			st.antiGravUntil = math.max(st.antiGravUntil,
				os.clock() + CONFIG.LegitTools.AntiGravityGrace)
		end
	end)

	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	if hum then
		hum.Died:Connect(function()
			giveGrace(player, CONFIG.Grace.DeathSeconds, "death")
			local st2 = S[player.UserId]
			if st2 then st2.lastPos = nil end
		end)
		-- 🩹 FIX 8 : on suit l'état pour couvrir tout ragdoll, quel qu'il soit.
		hum.StateChanged:Connect(function(_, new)
			if CONFIG.Ragdoll.States[new] then
				st.ragdollUntil = math.max(st.ragdollUntil,
					os.clock() + CONFIG.Ragdoll.GraceAfter)
			end
		end)
		hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
			if hum.PlatformStand then
				st.ragdollUntil = math.max(st.ragdollUntil,
					os.clock() + CONFIG.Ragdoll.GraceAfter)
			end
		end)
	end
end

local function initPlayer(player)
	local userId = player.UserId
	if S[userId] then return end
	S[userId] = newState()

	for _, attrName in ipairs(CONFIG.LegitAttributes.WatchForTrailing) do
		player:GetAttributeChangedSignal(attrName):Connect(function()
			giveGrace(player, CONFIG.LegitAttributes.TrailingGrace, attrName .. "_change")
		end)
	end

	if player.Character then onCharacter(player, player.Character) end
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)

	task.spawn(function()
		local ok, data
		for attempt = 1, 2 do
			ok, data = pcall(function() return warningsStore:GetAsync("aft_" .. userId) end)
			if ok then break end
			task.wait(1 * attempt)
		end
		local st = S[userId]
		if not st then return end
		st.warningsLoaded = true
		if ok and type(data) == "table" then
			st.warnings = activeWarningCount(data, os.time())
			if st.warnings > 0 then
				log(string.format("%s arrive avec %d warning(s) actifs", player.Name, st.warnings))
			end
			--  Le classement des warnings suit : un warning expiré n'y compte plus.
			if st.warnings ~= (tonumber(data.count) or 0) then
				StatsStore.indexRealWarning(userId, st.warnings)
			end
		end
	end)
end

Players.PlayerAdded:Connect(initPlayer)
for _, player in ipairs(Players:GetPlayers()) do initPlayer(player) end

-- 🏃 mouvement PVP coupé/rallumé en jeu → gravité et vitesses changent d'un coup
workspace:GetAttributeChangedSignal("MovementBoost"):Connect(function()
	for _, p in ipairs(Players:GetPlayers()) do
		giveGrace(p, CONFIG.MovementBoost.SwitchGrace or 4, "movementboost_switch")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if persistOn() and DIRTY[player.UserId] then
		pcall(StatsStore.flushAll, false)
	end
	S[player.UserId] = nil
end)

--════════════════════════════════════════════════════════════════════════════
-- 🔗 HOOKS EXTERNES
--════════════════════════════════════════════════════════════════════════════
if CONFIG.Hooks.HookProductPurchases then
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if purchased then
			giveGrace(userId, CONFIG.Grace.ProductPurchaseSeconds, "product_" .. tostring(productId))
		end
	end)
end

if CONFIG.Hooks.HookAdminAction then
	task.spawn(function()
		local remote
		for _ = 1, 30 do
			remote = ReplicatedStorage:FindFirstChild("AdminAction")
			if remote then break end
			task.wait(2)
		end
		if remote and remote:IsA("RemoteEvent") then
			remote.OnServerEvent:Connect(function(adminPlayer, action, targetName)
				--  ⚠️ On teste l'appartenance à la liste admin, PAS l'exemption
				--  d'analyse. La grâce doit continuer de fonctionner même quand
				--  les admins sont analysés : téléporter quelqu'un depuis le
				--  panel est un déplacement légitime, exactement comme un
				--  checkpoint. Ce n'est pas un privilège de sanction — c'est
				--  une mesure qu'on sait expliquer, donc qu'on n'a pas à
				--  compter contre qui que ce soit.
				if not (isAdminId(adminPlayer.UserId) or isWhitelisted(adminPlayer.UserId)) then
					return
				end

				-- 🩹 FIX 11 : « bring » et « reset » manquaient, et surtout la
				-- grâce n'était donnée qu'à la CIBLE. « GO TO » déplace l'ADMIN :
				-- il se flaggait lui-même à chaque téléportation.
				local moves = {
					teleport = true, tpcheckpoint = true, fly = true,
					bring = true, reset = true,
				}
				if not moves[action] then return end

				giveGrace(adminPlayer, CONFIG.Grace.AdminActionSeconds, "admin_self_" .. action)

				if type(targetName) == "string" then
					for _, p in ipairs(Players:GetPlayers()) do
						if p.Name:lower() == targetName:lower() then
							giveGrace(p, CONFIG.Grace.AdminActionSeconds, "admin_" .. action)
							break
						end
					end
				end
			end)
			log("Hook AdminAction actif (grâce sur l'admin ET sur la cible)")
		end
	end)
end

task.spawn(function()
	for _, remoteName in ipairs(CONFIG.Hooks.RemoteGraceNames) do
		task.spawn(function()
			local remote
			for _ = 1, 30 do
				remote = ReplicatedStorage:FindFirstChild(remoteName)
				if remote then break end
				task.wait(2)
			end
			if remote and remote:IsA("RemoteEvent") then
				remote.OnServerEvent:Connect(function(sender)
					local st = S[sender.UserId]
					if not st then return end
					local now = os.clock()
					if (now - st.lastRemoteGraceT) >= CONFIG.Grace.MinDelayBetweenRemoteGraces then
						st.lastRemoteGraceT = now
						giveGrace(sender, CONFIG.Grace.RemoteHookSeconds, "remote_" .. remoteName)
					end
				end)
				log("Hook remote actif : " .. remoteName)
			end
		end)
	end
end)

--════════════════════════════════════════════════════════════════════════════
-- ⚙️ RÉGLAGES AVANCÉS MODIFIÉS DEPUIS LE PANEL
--    Le panel envoie une table plate { ["Fly.MaxHoverTime"] = 3, … }.
--    On repart TOUJOURS des valeurs du fichier (PRISTINE), on applique les
--    changements du panel, puis la sévérité (sauf "custom").
--════════════════════════════════════════════════════════════════════════════
local function getPath(t, key)
	for part in string.gmatch(key, "[^%.]+") do
		if type(t) ~= "table" then return nil end
		t = t[part]
	end
	return t
end
local function setPath(t, key, v)
	local parts = {}
	for part in string.gmatch(key, "[^%.]+") do table.insert(parts, part) end
	for i = 1, #parts - 1 do
		if type(t[parts[i]]) ~= "table" then t[parts[i]] = {} end
		t = t[parts[i]]
	end
	t[parts[#parts]] = v
end
local function namesOf(map)
	local out = {}
	for k in pairs(map or {}) do table.insert(out, tostring(k)) end
	table.sort(out)
	return out
end
local function fusionProfile(src)
	for _, p in pairs((src.LegitTools or {}).FusionTools or {}) do
		local gp = p.GravityProfile or {}
		return { Speed = p.Speed or 60, MaxHoverTime = gp.MaxHoverTime or 8,
			AscentFlat = gp.AscentFlat or 130, MaxUpSpeed = gp.MaxUpSpeed or 140 }
	end
	return { Speed = 60, MaxHoverTime = 8, AscentFlat = 130, MaxUpSpeed = 140 }
end

--  Valeur « fichier » d'une clé avancée (affichée comme défaut dans le panel).
local function advancedDefault(key)
	local P = PRISTINE
	if key == "LegitTools.FlyTools" then return namesOf(P.LegitTools.FlyTools) end
	if key == "LegitTools.GravityTools" then return namesOf(P.LegitTools.GravityTools) end
	if key == "LegitTools.FusionTools" then return namesOf(P.LegitTools.FusionTools) end
	if key:sub(1, 7) == "Fusion." then return fusionProfile(P)[key:sub(8)] end
	return deepCopy(getPath(P, key))
end

local function applyAdvanced(adv)
	for k, v in pairs(PRISTINE) do CONFIG[k] = deepCopy(v) end
	local fusion = fusionProfile(PRISTINE)
	local fusionNames
	if type(adv) == "table" then
		for key, val in pairs(adv) do
			if key == "LegitTools.FlyTools" or key == "LegitTools.GravityTools"
				or key == "LegitTools.FusionTools" then
				-- traité plus bas (listes de noms)
			elseif key:sub(1, 7) == "Fusion." then
				fusion[key:sub(8)] = val
			else
				setPath(CONFIG, key, deepCopy(val))
			end
		end
		local LT = CONFIG.LegitTools
		if type(adv["LegitTools.FlyTools"]) == "table" then
			LT.FlyTools = {}
			for _, n in ipairs(adv["LegitTools.FlyTools"]) do
				LT.FlyTools[n] = { MaxSpeed = (LT.FlyToolDefaultProfile or {}).MaxSpeed or 200 }
			end
		end
		if type(adv["LegitTools.GravityTools"]) == "table" then
			LT.GravityTools = {}
			for _, n in ipairs(adv["LegitTools.GravityTools"]) do LT.GravityTools[n] = true end
		end
		fusionNames = adv["LegitTools.FusionTools"]
	end
	if type(fusionNames) ~= "table" then fusionNames = namesOf(PRISTINE.LegitTools.FusionTools) end
	CONFIG.LegitTools.FusionTools = {}
	for _, n in ipairs(fusionNames) do
		CONFIG.LegitTools.FusionTools[n] = { Speed = fusion.Speed, GravityProfile = {
			MaxHoverTime = fusion.MaxHoverTime, AscentFlat = fusion.AscentFlat,
			MaxUpSpeed = fusion.MaxUpSpeed } }
	end
	applyPreset()
	--  ce qui est calculé une seule fois au démarrage est recalculé
	MOVER_SET = {}
	for _, cn in ipairs(CONFIG.Launchers.MoverClasses or {}) do MOVER_SET[cn] = true end
	whitelistSet = {}
	for _, id in ipairs(CONFIG.Whitelist.UserIds or {}) do
		local n = tonumber(id)
		if n then whitelistSet[n] = true end
	end
end

local fileCache = {}   -- fiches du panel (voir playerFile plus bas)

--  Rechargement à chaud quand tu changes un réglage depuis le panel.
task.spawn(function()
	local ev = ServerStorage:WaitForChild("ACConfigChanged", 60)
	if ev then
		local lastCountFrom = nil
		ev.Event:Connect(function(c)
			--  🕛 « Ignorer les anciens warnings » : tout le monde repart de zéro,
			--     y compris les détections en cours de comptage sur ce serveur.
			local cf = (type(c) == "table" and tonumber(c.countFrom)) or 0
			if lastCountFrom ~= nil and cf > lastCountFrom then
				for _, st in pairs(S) do
					st.warnings, st.strikes, st.batchConf = 0, 0, {}
				end
				fileCache = {}
				log("🕛 Warnings remis à zéro pour tout le monde (comptés à partir de maintenant)")
			end
			lastCountFrom = cf
			local ok, err = pcall(applyAdvanced, type(c) == "table" and c.advanced or nil)
			if not ok then warn("🛡️ Réglages avancés non appliqués : " .. tostring(err)) end
			log(string.format("Config rechargée → mode=%s | test=%s",
				tostring(c and c.mode), tostring(c and c.shadow)))
		end)
	end
	--  La config a pu être lue AVANT qu'on écoute : on l'applique une fois.
	for _ = 1, 30 do
		if _G.ACConfig and _G.ACConfig.Get then
			local ok, c = pcall(_G.ACConfig.Get)
			if ok and type(c) == "table" and c._loaded then
				pcall(applyAdvanced, c.advanced)
				return
			end
		end
		task.wait(1)
	end
end)

--  🗂️ Fiche complète d'un joueur pour le panel (cache 45 s par joueur).
local function playerFile(userId)
	userId = tonumber(userId)
	if not userId then return nil end
	local c = fileCache[userId]
	if c and os.clock() - c.at < 45 then return c.data end
	local stats = StatsStore.getPlayer(userId)
	local okW, wd = pcall(function() return warningsStore:GetAsync("aft_" .. userId) end)
	local hist = (okW and type(wd) == "table") and activeHistory(wd, os.time()) or {}
	local data = {
		stats = stats,
		warnings = #hist,
		warnHistory = hist,
		warnReadFail = not okW,
	}
	--  lecture ratée (DataStore saturé) : gardée 5 s seulement, puis on relit
	fileCache[userId] = { at = okW and os.clock() or (os.clock() - 40), data = data }
	return data
end

--════════════════════════════════════════════════════════════════════════════
-- 🧰 API PUBLIQUE  (surface identique à l'ancienne version : ton panel marche)
--════════════════════════════════════════════════════════════════════════════
_G.AntiFlyTP = {
	--  📰 Journal partagé + fiche + candidats (panel anti-cheat)
	FeedPush      = function(ev) FeedLog.push(ev) end,
	GetFeedLog    = function(n) return FeedLog.get(n) end,
	GetPlayerFile = function(userId) return playerFile(userId) end,
	ForgetFile    = function(userId) fileCache[tonumber(userId) or 0] = nil end,
	--  Vide le classement des warnings réels (il repart de zéro).
	ResetRealRanks = function() return StatsStore.bumpRealGen() end,
	GetCandidates = function(n)
		return {
			det  = StatsStore.getRank("detections", n),
			warn = StatsStore.getRealRank("warnings", n),
			warnShadow = StatsStore.getRank("warnings", n),
		}
	end,
	AdvancedDefault = function(key) return advancedDefault(key) end,
	AddGrace      = function(t, s, r) giveGrace(t, s, r) end,
	MarkTeleport  = function(t, s) giveGrace(t, s or 5, "MarkTeleport") end,
	RegisterSafePart = function(part)
		if typeof(part) == "Instance" and part:IsA("BasePart") then safeParts[part] = true end
	end,

	SetEnabled = function(on)
		CONFIG.Enabled = (on == true)
		print("🛡️ Analyse =", CONFIG.Enabled)
	end,
	SetPreset = function(name) CONFIG.Preset = name ; applyPreset() end,
	SetFlyCheck = function(which, on)
		which = tostring(which):lower() ; on = (on == true)
		if which == "hover" then CONFIG.Fly.DetectHover = on
		elseif which == "ascent" or which == "montee" then CONFIG.Fly.DetectAscent = on
		elseif which == "upspeed" or which == "vertical" then CONFIG.Fly.DetectUpSpeed = on
		else warn("🛡️ SetFlyCheck : type inconnu '" .. which .. "'") return end
		print(string.format("🛡️ Détection '%s' = %s", which, tostring(on)))
	end,
	SetWarningExpiry = function()
		print("🛡️ La durée de vie des warnings se règle dans le panel (⚙️ → 🤫 Discrétion).")
	end,

	Status = function(userId)
		local st = S[userId]
		if not st then print("🛡️ Aucun état pour", userId) return end
		local now = os.clock()
		print(string.format(
			"🛡️ %d | warnings=%d | strikes=%d | grâce=%s (%.1fs) | launch=%.1fs | ragdoll=%.1fs | hover=%.2fs",
			userId, st.warnings, st.strikes, st.graceReason,
			math.max(0, st.graceUntil - now),
			math.max(0, st.launchUntil - now),
			math.max(0, st.ragdollUntil - now), st.hoverTime))
	end,

	ResetWarnings = function(userId)
		local st = S[userId]
		if st then st.warnings = 0 ; st.strikes = 0 end
		task.spawn(function() pcall(function() warningsStore:RemoveAsync("aft_" .. userId) end) end)
		StatsStore.clearRealWarnIndex(userId)
		print("🛡️ Warnings remis à zéro pour", userId)
	end,

	Unban = function(userId)
		task.spawn(function()
			pcall(function() banStore:RemoveAsync(tostring(userId)) end)
			if CONFIG.Punishment.UseRobloxBanAPI then
				pcall(function() Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true }) end)
			end
		end)
		StatsStore.clearRealBanIndex(userId)
		print("🛡️ Unban demandé pour", userId)
	end,

	AddWhitelist    = function(userId) whitelistSet[userId] = true ; print("🛡️ Whitelist +", userId) end,
	RemoveWhitelist = function(userId) whitelistSet[userId] = nil ; print("🛡️ Whitelist -", userId) end,
	GetConfig       = function() return CONFIG end,

	-- ── Compat panel : « mode test » = case shadow de la config partagée ──
	IsTestMode = function() return acShadow() end,
	IsSilent   = function() return not acShadowCorrect() end,
	--  ⛅ PAUSE MÉTÉO (Admin Abuse) : pendant une météo physique (vitesse,
	--     saut, gravité), l'analyse est en PAUSE pour tout le monde, puis
	--     reprend après quelques secondes. Coupée d'office après 15 min
	--     (filet si la fin de météo n'arrive jamais).
	PausePhysics = function(on)
		if on == true then
			globalToleranceOn = true
			globalToleranceUntil = os.clock() + 900
			print("⛅ [AntiFlyTP] Analyse en pause (météo Admin Abuse)")
			task.delay(900, function()
				if globalToleranceOn and os.clock() >= globalToleranceUntil - 1 then
					globalToleranceOn = false
					print("⛅ [AntiFlyTP] Pause météo coupée automatiquement (15 min)")
				end
			end)
		else
			globalToleranceOn = false
			globalToleranceUntil = os.clock() + (CONFIG.GlobalToleranceTrail or 6)
			print("⛅ [AntiFlyTP] Analyse reprise (fin de la météo)")
		end
	end,
	--  Ancien bouton « mode test » : il ne fait rien ici (le shadow se règle
	--  dans le panel ⚙️, c'est le seul chemin qui persiste et synchronise).
	SetTestMode = function()
		print("🛡️ Utilise le panel admin (⚙️ Réglages → Mode test) pour le shadow.")
	end,
	IsPaused = function() return globalTolerance() end,
	GetActiveWarnings = function(userId)
		local st = S[tonumber(userId) or 0]
		return st and st.warnings or nil
	end,
	SetTestSilent = function() print("🛡️ Réglage déplacé dans le panel admin (⚙️ Réglages)") end,

	TestReport           = function()       TestLog.report() end,
	TestTopExploiters    = function(n)      TestLog.topExploiters(n) end,
	TestTop              = function(n)      TestLog.topExploiters(n) end,
	TestWouldBeBanned    = function()       TestLog.wouldBeBanned() end,
	TestWouldBeKicked    = function()       TestLog.wouldBeKicked() end,
	TestTopWarnings      = function(n)      TestLog.topWarnings(n) end,
	TestRecentWarnings   = function(n)      TestLog.recentWarnings(n) end,
	TestRecentDetections = function(n)      TestLog.recentDetections(n) end,
	TestPlayer           = function(userId) TestLog.playerDetail(userId) end,
	TestReset            = function()       TestLog.reset() end,

	--  🎯 LE RAPPORT DÉTAILLÉ. Pour chaque détection récente d'un joueur, la
	--  liste des facteurs qui ont fait monter ou descendre la certitude.
	--  C'est ce que tu lis quand quelqu'un te dit « je n'ai rien fait ».
	TestConfidence = function(userId)
		local r = TestLog.players[userId]
		if not r then print("🎯 Aucun dossier pour " .. tostring(userId)) return end
		local avg = ((r.confCount or 0) > 0) and math.floor(r.confSum / r.confCount) or 0
		print("╔══════════════════════════════════════════════════════════╗")
		print(string.format("║ 🎯 DOSSIER — %s (%d)", r.name, r.userId))
		print("╚══════════════════════════════════════════════════════════╝")
		print(string.format("  Certitude du dossier : %d%%   (max atteint : %d%%)",
			avg, r.confMax or 0))
		print(string.format("  Signaux retenus      : %d", r.counted or 0))
		print(string.format("  Signaux écartés      : %d  ← le filtre à l'œuvre", r.ignored or 0))
		print(string.format("  Seuils actuels       : %d%% compter · %d%% avertir · %d%% sanctionner",
			acConf("MinConfidenceCount", 55), acConf("MinConfidenceWarn", 70),
			acConf("MinConfidenceSanction", 85)))
		print("  ── Détections récentes, du plus récent au plus ancien ──")
		local shown = 0
		for i = #TestLog.events, 1, -1 do
			local e = TestLog.events[i]
			if e.userId == userId and e.kind == "detection" then
				shown = shown + 1
				if shown > 8 then break end
				print(string.format("\n  [%s] %s — %d%% %s",
					os.date("%H:%M:%S", e.t), e.vType, e.conf or 0,
					e.counted and "✅ RETENU" or "⚪ écarté"))
				print(string.format("     %s", e.details or ""))
				for _, f in ipairs(e.factors or {}) do
					print(string.format("       %+4d  %s", f.delta, f.label))
				end
			end
		end
		if shown == 0 then print("     (aucune détection)") end
	end,
	TestData             = function()       return TestLog end,

	GetTestPlayer = function(userId)
		local r = TestLog.players[userId]
		if not r then return nil end
		local recent = {}
		for i = #TestLog.events, 1, -1 do
			local e = TestLog.events[i]
			if e.userId == userId then
				recent[#recent + 1] = { t = e.t, kind = e.kind, vType = e.vType,
					details = e.details, count = e.count, action = e.action,
					conf = e.conf, counted = e.counted, factors = e.factors }
				if #recent >= 40 then break end
			end
		end
		--  🎯 Certitude du dossier : moyenne des signaux RETENUS. Un joueur
		--  avec 40 signaux écartés et zéro retenu a une certitude nulle —
		--  c'est exactement ce qu'on veut lire pour un obby bruyant.
		local avg = ((r.confCount or 0) > 0)
			and math.floor(r.confSum / r.confCount) or 0
		return {
			userId = r.userId, name = r.name, total = r.total, detections = r.detections,
			simWarnings = r.simWarnings, wouldKick = r.wouldKick,
			wouldBan = r.wouldBan, wouldBanAt = r.wouldBanAt,
			lastType = r.lastType, firstSeen = r.firstSeen, lastSeen = r.lastSeen,
			confidence = avg, confMax = r.confMax or 0,
			counted = r.counted or 0, ignored = r.ignored or 0,
			recent = recent,
		}
	end,
	GetTestPlayerPersisted = function(userId) return StatsStore.getPlayer(userId) end,
	ClearTestPlayer = function(userId)
		TestLog.players[userId] = nil
		DIRTY[userId] = nil
		StatsStore.clearPlayer(userId)
		print("🛡️ Fiche stats effacée pour", userId)
	end,

	GetShadowRank = function(kind, n) return StatsStore.getRank(kind, n) end,
	GetRealRank   = function(kind, n) return StatsStore.getRealRank(kind, n) end,
	WipeTestAll   = function(token) return StatsStore.wipeTestAll(token) end,

	WipeRealWarnings = function(token)
		if token ~= "OUI" then print("🛡️ WipeRealWarnings : passe \"OUI\".") return false end
		task.spawn(function()
			local ids = StatsStore.listRealWarned()
			local n = 0
			for uid in pairs(ids) do
				n = n + 1
				pcall(function() warningsStore:RemoveAsync("aft_" .. uid) end)
				local st = S[uid]
				if st then st.warnings = 0 ; st.strikes = 0 end
				task.wait(0.2)
			end
			local g = StatsStore.bumpRealGen()
			print(string.format("🗑️ Warnings réels effacés pour %d joueur(s) (gen=%s).",
				n, tostring(g)))
		end)
		return true
	end,

	TestReportGlobal   = function()       StatsStore.reportGlobal() end,
	TestRankExploiters = function(n)      StatsStore.rankExploiters(n) end,
	TestRankWarnings   = function(n)      StatsStore.rankWarnings(n) end,
	TestRankBanned     = function(n)      StatsStore.rankBanned(n) end,
	TestPlayerDS       = function(userId) StatsStore.playerDetail(userId) end,
	TestFlush          = function()
		task.spawn(function()
			StatsStore.flushAll(false) ; print("💾 Flush manuel terminé.")
		end)
	end,
	TestWipePersisted  = function(token) StatsStore.wipe(token) end,
	SetPersist         = function(on)
		CONFIG.Stats.Enabled = (on == true)
		print("💾 Persistance stats =", CONFIG.Stats.Enabled)
	end,
}

--════════════════════════════════════════════════════════════════════════════
print("✅ 🛡️ ANTI-FLY / ANTI-TP / ANTI-SPEED v4 CHARGÉ")
task.spawn(function()
	task.wait(4)   -- laisse la config partagée arriver
	print("🛡️ ────────────────────────────────────────────────────────────")
	print(string.format("🛡️ Mode   : %s", acMode() == "ugc"
		and "PRIVATION D'UGC (aucun ban, aucun kick)"
		or  "BAN (échelle warnings → kick → ban)"))
	print(string.format("🛡️ Shadow : %s", acShadow()
		and "OUI — rien n'est appliqué, tout est observé"
		or  "NON — les sanctions sont réelles"))
	print(string.format("🤫 Discret : %s · warnings effacés après %s", acSilent()
		and "OUI — le joueur ne voit rien" or "non — cartes et corrections visibles",
		acWarnExpiryDays() > 0 and (acWarnExpiryDays() .. " jour(s)") or "jamais"))
	print(string.format("🛡️ Admins : %s", acAnalyzeAdmins()
		and "ANALYSÉS comme tout le monde (aucun privilège)"
		or  "exemptés"))
	print(string.format("🎯 Certitude requise : %d%% pour compter · %d%% pour avertir · %d%% pour sanctionner",
		acConf("MinConfidenceCount", 55), acConf("MinConfidenceWarn", 70),
		acConf("MinConfidenceSanction", 85)))
	print("🛡️ Le mode se change dans le panel admin → 🚫 UGC BAN → ⚙️ Réglages")
	print("🛡️ Console : _G.AntiFlyTP.TestReport() | .TestTopExploiters(10)")
	print("🎯           _G.AntiFlyTP.TestConfidence(userId)  ← le rapport détaillé")
	print("🛡️           _G.AntiFlyTP.Status(userId) | .TestRecentDetections(20)")
	print("🛡️ ────────────────────────────────────────────────────────────")
end)