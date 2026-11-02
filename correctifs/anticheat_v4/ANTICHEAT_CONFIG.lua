--════════════════════════════════════════════════════════════════════════════
-- ⚙️ ANTICHEAT_CONFIG — TOUS LES RÉGLAGES DE L'ANTI-CHEAT, AU MÊME ENDROIT
--
--  📍 ServerScriptService ▸ ANTICHEAT_CONFIG   (ModuleScript, nom EXACT)
--
--  C'est le SEUL fichier à ouvrir pour régler l'anti-cheat.
--  Les scripts « anti fly/tp server » et « AntiCheat_UGCRestrict » lisent ici :
--  tu n'as plus rien à régler dans leur code.
--
--  ┌──────────────────────────────────────────────────────────────────────┐
--  │ 🔁 FICHIER  ↔  PANEL : LA RÈGLE (une seule, à retenir)                │
--  │                                                                      │
--  │  Les sections ① à ⑦ (marquées 🖥️) se règlent AUSSI dans le panel     │
--  │  admin (⚙️ Réglages), avec effet immédiat sur tous les serveurs.      │
--  │                                                                      │
--  │  • Tu changes dans le PANEL → c'est appliqué tout de suite, et ça     │
--  │    reste comme ça.                                                   │
--  │  • Tu changes dans CE FICHIER → monte VERSION de 1 (ex : 1 → 2) puis  │
--  │    publie : au démarrage, le fichier ÉCRASE ce que le panel avait     │
--  │    enregistré. Sans changer VERSION, tes modifs des sections ① à ⑦   │
--  │    ne sont PAS prises (le panel garde la main).                       │
--  │                                                                      │
--  │  Les sections ⑧ à ⑩ (marquées 📄) ne sont QUE dans ce fichier :       │
--  │  il suffit de publier, pas besoin de toucher à VERSION.              │
--  └──────────────────────────────────────────────────────────────────────┘
--════════════════════════════════════════════════════════════════════════════
local C = {}

C.VERSION = 1   -- ⬆️ +1 pour que les sections ① à ⑦ de ce fichier écrasent le panel


--════════════════════════════════════════════════════════════════════════════
-- ① 🖥️ ACTIVATION
--════════════════════════════════════════════════════════════════════════════
C.Activation = {
	--  "ugc" = privation d'UGC (réversible, le joueur garde ses points)
	--  "ban" = ban classique (voir section ⑤)
	Mode = "ugc",

	--  true = MODE TEST : tout est mesuré, RIEN n'est appliqué (aucune
	--  sanction). Le panel montre ce qui SERAIT arrivé. false = sanctions réelles.
	ModeTest = false,

	--  true = les admins sont mesurés comme tout le monde (conseillé : c'est
	--  ton meilleur test de faux positifs). false = admins ignorés.
	AnalyserLesAdmins = true,
}


--════════════════════════════════════════════════════════════════════════════
-- ② 🖥️ SANCTION — MODE PRIVATION D'UGC
--════════════════════════════════════════════════════════════════════════════
C.Sanction = {
	--  Nombre de warnings avant la privation (1 à 20).
	--  Rappel : 3 détections retenues et rapprochées = 1 warning.
	WarningsAvantSanction = 1,

	--  Durée de la privation en HEURES. 0 = jusqu'à ce que tu la lèves.
	DureeHeures = 0,

	--  Afficher le message « UGC désactivées » au moment de la sanction
	--  (une seule fois ; s'il n'était pas en jeu, à sa connexion suivante).
	MessageALaSanction = true,

	--  Ré-afficher ce message à CHAQUE connexion. Laisse false si tu veux
	--  qu'il ne le revoie qu'en essayant d'acheter (section ③).
	RappelAChaqueConnexion = false,

	--  Le kicker une fois au moment de la sanction (il peut revenir).
	KickALaSanction = false,

	--  Bloquer aussi les dons d'UGC et le rebirth pour un joueur restreint.
	BloquerDons    = true,
	BloquerRebirth = false,
}


--════════════════════════════════════════════════════════════════════════════
-- ③ 🖥️ DISCRÉTION ET DURÉE DES WARNINGS
--════════════════════════════════════════════════════════════════════════════
C.Discretion = {
	--  true = le joueur ne voit RIEN de ses détections ni de ses warnings :
	--  aucune carte, aucun retour en arrière, aucun kick d'avertissement.
	JoueurNeVoitRien = true,

	--  Chaque warning s'efface tout seul ce nombre de JOURS après avoir été
	--  reçu. 0 = jamais. Long exprès : ça efface un faux warning isolé.
	WarningDisparaitApresJours = 30,

	--  true = après le message de sanction, il ne le revoit QUE s'il essaie
	--  d'acheter une UGC qu'il pourrait se payer. Sans assez de points : le
	--  message normal « Not enough points », sans proposition de Robux.
	MontrerSanctionSeulementALAchat = true,
}


--════════════════════════════════════════════════════════════════════════════
-- ④ 🖥️ NIVEAU DE PREUVE (en %, tous les modes)
--    Chaque détection reçoit une certitude de 0 à 99 %.
--════════════════════════════════════════════════════════════════════════════
C.Preuve = {
	CompterAPartirDe     = 55,   -- en dessous : noté dans le journal, ne compte pas
	AvertirAPartirDe     = 70,   -- moyenne minimale pour donner un warning
	SanctionnerAPartirDe = 85,   -- certitude du dossier requise pour la sanction auto
}


--════════════════════════════════════════════════════════════════════════════
-- ⑤ 🖥️ MODE BAN (seulement si Activation.Mode = "ban")
--════════════════════════════════════════════════════════════════════════════
C.ModeBan = {
	WarningsAvantBan   = 3,
	DureeJours         = 0,      -- 0 = définitif
	KickAvantBan       = true,   -- kick au warning juste avant le ban (ignoré si discret)
	PriverAussiUGC     = true,
	PanneauAvantKick   = true,   -- le joueur lit la raison 4 s avant d'être éjecté
	RemettrePointsAZero = false, -- ⚠️ IRRÉVERSIBLE
}


--════════════════════════════════════════════════════════════════════════════
-- ⑥ 🖥️ MODE TEST (seulement quand Activation.ModeTest = true)
--════════════════════════════════════════════════════════════════════════════
C.ModeTest = {
	CorrigerPosition   = false,  -- ramener quand même le joueur en arrière
	JoueurVoitCartes   = false,  -- montrer les cartes d'avertissement
	LogConsole         = true,   -- chaque décision dans la console serveur
	StockageSepare     = true,   -- warnings de test séparés des vrais
	RappelApresJours   = 5,      -- rappel « tu peux couper le mode test »
}


--════════════════════════════════════════════════════════════════════════════
-- ⑦ 🖥️ MESSAGES AFFICHÉS AUX JOUEURS
--    Variables : {player} {type} {typefr} {warnings} {max} {left}
--                {confidence} {game}      \n = retour à la ligne
--════════════════════════════════════════════════════════════════════════════

--  Texte du message de privation (utilisé si restrictBody est vide).
C.MessageSanction =
	"Our anti-cheat system has flagged your account for abnormal movement "
	.. "(fly, teleport or speed).\n\n"
	.. "As a result, UGC redemptions are disabled on your account. "
	.. "Your points are untouched and you can keep playing normally.\n\n"
	.. "If you believe this is a mistake, please contact our support team "
	.. "and include evidence — a short video of your gameplay is best. "
	.. "We review every appeal by hand."

C.Messages = {

	--  ⚠️ APRÈS PLUSIEURS DÉTECTIONS (carte orange, pas encore un warning)
	nudgeEnabled = false,
	--  Combien de détections COMPTÉES avant d'afficher la carte.
	--  1 = à la première. 3 = seulement si ça se répète vraiment.
	nudgeAfterDetections = 2,
	--  Secondes minimum entre deux cartes orange (anti-spam visuel).
	nudgeCooldown = 10,
	nudgeTitle = "⚠️ Mouvement anormal",
	nudgeBody =
		"Our system detected an abnormal movement ({typefr}).\n"
		.. "Your position has been corrected. This is NOT a warning yet.\n\n"
		.. "If this keeps happening while you play normally, please tell us — "
		.. "it means we have a bug to fix.",

	--  🚨 APRÈS UN WARNING OFFICIEL (carte rouge)
	warnEnabled = false,
	warnTitle = "🚨 Warning {warnings}/{max}",
	warnBody =
		"Our anti-cheat flagged abnormal movement on your account ({typefr}).\n\n"
		.. "You have {left} warning(s) left before UGC redemptions are "
		.. "disabled on your account.\n\n"
		.. "If you believe this is a mistake, contact support with a short "
		.. "video of your gameplay. We review every appeal by hand.",

	--  🚫 AU MOMENT DE LA PRIVATION D'UGC
	restrictTitle = "🚫 UGC access disabled",
	--  Vide = on réutilise `supportMessage` (rétro-compatibilité).
	restrictBody = "",

	--  🛒 QUAND IL CLIQUE SUR ACHETER ALORS QU'IL EST RESTREINT
	shopBlockedTitle = "🚫 Purchase refused",
	shopBlockedBody =
		"Our anti-cheat system believes this account has used movement "
		.. "exploits, so UGC redemptions are disabled.\n\n"
		.. "Your points are safe and you can keep playing.\n\n"
		.. "Think we got it wrong? Contact support with evidence — a short "
		.. "video works best. Every appeal is reviewed by a human.",

	--  ⏳ QUAND LA VÉRIFICATION EST IMPOSSIBLE (DataStore muet)
	--     On refuse par sécurité : mieux vaut un achat retardé qu'une UGC
	--     donnée à un tricheur.
	shopUnverifiedTitle = "⏳ Please try again",
	shopUnverifiedBody =
		"We could not verify your account right now. Your purchase was not "
		.. "made and no points were taken.\n\nPlease try again in a moment.",

	--  🔨 AU MOMENT DU BAN (mode ban uniquement)
	banTitle = "🔨 Account banned",
	banBody =
		"Your account has been banned for repeated use of movement exploits "
		.. "({typefr}).\n\nIf you believe this is a mistake, contact support "
		.. "with evidence.",

	--  🔐 SÉCURITÉ : afficher la certitude en % au joueur ?
	--     ⚠️ Fortement déconseillé. Un tricheur qui voit « 62 % » sait
	--        exactement de combien il doit ralentir pour passer sous le
	--        seuil. Tu lui offres un banc d'essai.
	--        Toi, tu la vois toujours dans le panel.
	showConfidenceToPlayer = false,
}


--════════════════════════════════════════════════════════════════════════════
-- ⑧ 📄 ADMINS ET EXCEPTIONS
--════════════════════════════════════════════════════════════════════════════
--  Qui peut utiliser le panel anti-cheat (UserId). Ajoute ici tout nouvel admin.
C.Admins = {
	3203521470, 11017023724, 8456613930, 8142402169, 10420404767,
}

--  Comptes JAMAIS analysés (compte de test, bot…). Les admins n'ont pas besoin
--  d'être ici (voir Activation.AnalyserLesAdmins).
C.JamaisAnalyses = {}


--════════════════════════════════════════════════════════════════════════════
-- ⑨ 📄 DÉTECTION (avancé)
--════════════════════════════════════════════════════════════════════════════
C.Detection = {
	--  Interrupteur général de l'ANALYSE (false = plus rien n'est mesuré).
	AnalyseActive = true,
	--  Messages détaillés dans la console serveur.
	LogsDetailles = true,

	--  🎚️ SÉVÉRITÉ — le réglage le plus utile de cette section :
	--    "lenient" = très tolérant · "balanced" = conseillé · "strict" = sévère
	--    "custom"  = utilise TES valeurs marquées ◆ ci-dessous
	--  ⚠️ Tant que ce n'est pas "custom", les valeurs marquées ◆ sont choisies
	--     par la sévérité (ce que tu écris pour elles est ignoré). Toutes les
	--     autres valeurs de cette section sont toujours prises.
	Severite = "balanced",

	--  Fréquence de mesure (s) et écart max entre deux mesures avant de
	--  considérer que le serveur a laggé.
	Sampling = { Interval = 0.25, MaxUsableDelta = 0.85 },

	--  🕊️ VOL (valeurs "balanced")
	Fly = {
		Enabled        = true,
		DetectHover    = true,    -- vol stationnaire
		DetectAscent   = false,   -- longue montée (bruyant en obby)
		DetectUpSpeed  = false,   -- montée trop rapide (bruyant en obby)
		MaxHoverTime   = 2.5,     -- ◆ s immobile en l'air avant détection
		HoverBandY     = 6,       -- ◆ vitesse verticale max pour « immobile »
		HoverMinHeight = 11,      -- ◆ hauteur min au-dessus du sol (studs)
		AscentMultiplier = 2.0, AscentFlatBonus = 8,              -- ◆ AscentFlatBonus
		MaxUpSpeedMultiplier = 1.6, MaxUpSpeedFlat = 15, UpSpeedSamples = 4,  -- ◆ les 2 derniers
		TreatClimbingAsGround = true, TreatSwimmingAsGround = true,
		GroundRayDistance = 6.5,
	},

	--  🌀 TÉLÉPORTATION (valeurs "balanced")
	Teleport = {
		Enabled = true,
		MaxPredictionError  = 65,   -- ◆ écart horizontal toléré (studs)
		MaxVerticalError    = 90,   -- ◆ écart vertical toléré (studs)
		MinTeleportDistance = 28,   -- ◆ en dessous : jamais une téléportation
		IgnoreIfVelocityConsistent = true, VelocityConsistencyRatio = 0.55,
		--  Destinations toujours autorisées (rayon en studs autour d'elles)
		SafeDestinationRadius = 22,
		SafePartNames = { "FirstSpawn", "TpRebirth", "Portail2" },
		SafePartPatterns = {},
		SafeIncludeSpawnLocations = true,
		--  Arrivée près d'un checkpoint : "always" / "limited" / "never"
		CheckpointDestinations = "limited",
		MaxCheckpointTeleportsPerMinute = 6,
		CheckpointPattern = "^[Cc]heckpoint%d+$",
	},

	--  💨 VITESSE (valeurs "balanced")
	Speed = {
		Enabled = true,
		Tolerance = 1.7,           -- ◆ × la vitesse de marche
		FlatBonus = 10,            -- ◆ + studs/s
		SustainedSamples = 8,      -- ◆ mesures d'affilée (8 × 0,25 s = 2 s)
		MinBaselineWalkSpeed = 16,
	},

	--  ⚖️ STRIKES → WARNING (valeurs "balanced")
	Punishment = {
		StrikesPerWarning  = 3,    -- ◆ détections retenues pour 1 warning
		StrikeDecaySeconds = 120,  -- ◆ un strike s'efface après ce calme
		EscalationCooldown = 4,    -- ◆ une même glissade ne compte qu'une fois
		PassiveDecay = true,
		StrikeWeights = { FLY_HOVER = 1, FLY_ASCENT = 1, FLY_UPSPEED = 1,
			FLY_STATE = 2, TELEPORT = 1, SPEED = 1 },
		--  ◆ (mode ban) action à chaque warning, ◆ warning du ban
		WarningActions = { [1] = "notify", [2] = "notify", [3] = "kick", [4] = "kick" },
		BanAtWarning = 5,
		UseRobloxBanAPI = false,
	},

	--  🎯 CALCUL DE LA CERTITUDE (ne touche pas sans raison)
	Confidence = {
		Enabled = true,
		Base = { FLY_STATE = 72, FLY_HOVER = 52, TELEPORT = 46,
			FLY_UPSPEED = 46, FLY_ASCENT = 40, SPEED = 38 },
		MarginMax = 25, DurationMax = 15, CleanContext = 15,
		RepeatPer = 5, RepeatMax = 20, DiversityPer = 9, DiversityMax = 18,
		HistoryBonus = 10, NoGroundSeconds = 15, NoGroundBonus = 10,
		PenaltyLongDt = 15, PenaltyRecentGrace = 25, PenaltyRecentSpawn = 15,
		PenaltyRecentForce = 20, PenaltyRecentLaunch = 25, PenaltyRecentRagdoll = 25,
		PenaltyFirstEver = 10, RecentWindow = 12, Ceiling = 99,
	},
}


--════════════════════════════════════════════════════════════════════════════
-- ⑩ 📄 MOUVEMENTS NORMAUX DU JEU (ce qui ne doit JAMAIS être détecté)
--    À compléter si tu ajoutes un outil, un attribut ou un système qui
--    fait voler / téléporte / accélère les joueurs.
--════════════════════════════════════════════════════════════════════════════
C.MouvementsLegitimes = {
	--  🧰 Outils (par NOM de l'outil)
	LegitTools = {
		FlyTools = { ["Jetpack"] = { MaxSpeed = 200 } },    -- outils qui font voler
		FlyToolMarkers = { "tube", "tube2" },               -- ou qui contiennent ces pièces
		FlyToolDefaultProfile = { MaxSpeed = 200 },
		GravityTools = { ["Gravity Coil"] = true, ["GravityCoil"] = true, ["Grav Coil"] = true },
		GravityProfile = { MaxHoverTime = 8, AscentFlat = 110, MaxUpSpeed = 130 },
		SpeedTools = { ["Speed Coil"] = 60, ["SpeedCoil"] = 60 },
		FusionTools = { ["FusionCoil"] = { Speed = 60,
			GravityProfile = { MaxHoverTime = 8, AscentFlat = 130, MaxUpSpeed = 140 } } },
		ToolTrailingGrace = 4,          -- s de tolérance après avoir rangé l'outil
		DetectAntiGravityForce = true,  -- reconnaît un coil à sa force, même renommé
		AntiGravityGrace = 5,
	},

	--  🏷️ Attributs posés par tes scripts (sur le joueur ou le personnage)
	LegitAttributes = {
		FullBypass = { "Ziplining", "JustRebirthed", "AdminFly" },        -- analyse suspendue
		WatchForTrailing = { "Ziplining", "JustRebirthed", "AdminFly", "InArena" },
		TrailingGrace = 6,              -- s de tolérance quand l'attribut change
	},

	--  🚀 Propulsions (launchers, jump pads, gifle, explosions…)
	Launchers = {
		AutoGraceOnMover = true, MoverGrace = 6,
		MoverClasses = { "LinearVelocity", "BodyVelocity", "BodyThrust", "VectorForce",
			"BodyForce", "AlignPosition", "BodyPosition", "AngularVelocity",
			"BodyAngularVelocity", "AlignOrientation" },
		VelocitySpikeThreshold = 130, VelocitySpikeGrace = 4,
	},

	--  🤸 Ragdoll (gifle, PvP)
	Ragdoll = {
		SkipWhileRagdolled = true, GraceAfter = 4,
		States = {
			[Enum.HumanoidStateType.Physics]     = true,
			[Enum.HumanoidStateType.FallingDown] = true,
			[Enum.HumanoidStateType.Ragdoll]     = true,
			[Enum.HumanoidStateType.GettingUp]   = true,
		},
	},

	--  🥊 Arène 1v1
	Arena = { SkipTeleport = true, SkipSpeed = true, FlyMode = "relaxed",
		RelaxedHoverTime = 6, RelaxedAscentFlat = 80 },

	--  🏃 Mouvement PvP (slide, double saut, gravité de MovementBoost)
	MovementBoost = { Enabled = true, SlideSpeed = 40, SpeedMargin = 6, SwitchGrace = 4 },

	--  ⏳ Tolérances (secondes)
	Grace = {
		SpawnSeconds = 12, DeathSeconds = 5, ProductPurchaseSeconds = 8,
		AdminActionSeconds = 10, RemoteHookSeconds = 5,
		MinDelayBetweenRemoteGraces = 8, LandingSeconds = 0.8,
	},

	--  Remotes dont l'envoi donne une tolérance (noms dans ReplicatedStorage)
	Hooks = { HookAdminAction = true, HookProductPurchases = true, RemoteGraceNames = {} },

	--  Téléportations faites par un script serveur : reconnues automatiquement
	ServerMoves = { Enabled = true },
	--  Tapis roulants / plateformes mobiles : vitesse du sol ajoutée
	Floor = { Enabled = true, Memory = 1.5 },
	--  Tyrolienne : exemption seulement près d'une corde
	Zipline = { Prefix = "Tirolienne", Rope = "Corde", MaxDist = 18 },
	--  Gravité basse (Admin Abuse) : plus de temps permis en l'air
	ScaleHoverWithGravity = true,
	--  Fin de météo Admin Abuse : secondes de tolérance après
	GlobalToleranceTrail = 6,
}

return C
