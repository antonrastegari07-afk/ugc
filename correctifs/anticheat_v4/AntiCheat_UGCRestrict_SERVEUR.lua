--════════════════════════════════════════════════════════════════════════════
-- 🚫 ANTI-CHEAT — CONFIG PARTAGÉE + PRIVATION D'UGC
--
--  📍 OÙ ? ServerScriptService, comme un script normal.
--     Nom conseillé : AntiCheat_UGCRestrict
--
--  CE QUE CE SCRIPT FAIT
--    1. Il détient LE mode de l'anti-cheat (ban / ugc) et la case shadow,
--       persistés en DataStore et synchronisés sur tous tes serveurs.
--       L'anti-fly les lit ici : un seul endroit à changer, jamais deux.
--    2. Il tient le registre des joueurs privés d'UGC, avec qui les a
--       privés, quand, pourquoi, et leurs stats de détection au moment T.
--    3. Il BLOQUE réellement leurs achats, côté serveur, avant la moindre
--       déduction de points — et il le fait de trois façons indépendantes
--       pour qu'aucun chemin ne passe à travers.
--
--  POURQUOI LE BLOCAGE EST FIABLE
--    • La décision est prise SERVEUR. Le client ne fait qu'envoyer un clic.
--    • Si le registre n'a pas pu être lu, on REFUSE l'achat au lieu de
--       l'autoriser. Un exploiteur ne peut donc pas gagner en faisant
--       tomber la lecture — au pire il fait patienter tout le monde
--       quelques secondes, ce qui se voit tout de suite dans tes logs.
--    • Le blocage est posé à trois endroits : le handler d'achat du script
--       de points, la fonction CanBuy de l'escrow, et un dernier filet sur
--       PromptPurchaseFinished qui trace toute UGC arrivée malgré tout.
--
--  ⚠️ IL RESTE UN PATCH DE 8 LIGNES À COLLER dans ton script de points
--     (voir INSTALLATION.md, section « patch achat UGC »). Les deux autres
--     filets se posent tout seuls.
--
--  🆕 V4
--    • 🤫 Discrétion : le joueur ne voit ni ses détections ni ses warnings.
--    • La sanction tombe après N warnings (1 par défaut).
--    • Chaque warning disparaît tout seul X jours après (30 par défaut).
--    • Le panneau « UGC désactivées » s'affiche UNE fois (à la sanction, ou
--      à la connexion suivante s'il n'était pas là), puis seulement quand il
--      essaie d'acheter une UGC qu'il pourrait normalement se payer.
--    • Fiche de sanction avec la RAISON EXACTE (en clair) et les derniers
--      signaux ; les joueurs restreints sortent des classements anti-cheat.
--    • TOUS les réglages sont dans ServerScriptService ▸ ANTICHEAT_CONFIG.
--════════════════════════════════════════════════════════════════════════════

local Players            = game:GetService("Players")
local DataStoreService   = game:GetService("DataStoreService")
local MessagingService   = game:GetService("MessagingService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")

--════════════════════════════════════════════════════════════════════════════
-- ⚙️ VALEURS DE SECOURS
--   ⚠️ NE RÈGLE RIEN ICI : tout se règle dans ServerScriptService ▸
--      ANTICHEAT_CONFIG (ou dans le panel). Les valeurs ci-dessous ne servent
--      que si ce fichier est absent ; elles sont alors les plus douces
--      possibles côté sanction tant que la config n'est pas lue.
--════════════════════════════════════════════════════════════════════════════
local ACFILE = nil
do
	local SSS = game:GetService("ServerScriptService")
	local m = SSS:FindFirstChild("ANTICHEAT_CONFIG") or SSS:WaitForChild("ANTICHEAT_CONFIG", 10)
	if m and m:IsA("ModuleScript") then
		local ok, r = pcall(require, m)
		if ok and type(r) == "table" then ACFILE = r
		else warn("🚫 [UGCRestrict] ANTICHEAT_CONFIG illisible : " .. tostring(r)) end
	else
		warn("🚫 [UGCRestrict] ANTICHEAT_CONFIG introuvable dans ServerScriptService → valeurs de secours")
	end
end
--  VERSION du fichier : quand elle change, le fichier écrase le panel.
local FILE_VERSION = (ACFILE and tonumber(ACFILE.VERSION)) or 0

local DEFAULTS = {

	--  🤫 DISCRÉTION — le joueur ne voit RIEN de ses détections ni de ses
	--     warnings : aucune carte, aucun retour en arrière, aucun kick
	--     d'avertissement. Il ne l'apprend qu'au moment de la sanction.
	silent = true,

	--  ⏳ Durée de vie d'un warning, en jours. Chaque warning disparaît tout
	--     seul ce nombre de jours après avoir été reçu. 0 = jamais.
	--     Long exprès : ça sert à effacer un faux warning isolé, pas à
	--     pardonner un tricheur qui recommence.
	warningExpiryDays = 30,

	--  🕛 Les warnings reçus AVANT cette date (os.time) sont ignorés. 0 = aucun.
	--     Posé depuis le panel (activation des sanctions / remise à zéro générale).
	countFrom = 0,

	--  "ban" = l'échelle classique : warnings → kick → ban permanent.
	--  "ugc" = personne n'est jamais banni ni kické par l'anti-fly ; au bout
	--          de N warnings le joueur perd l'accès aux UGC, définitivement,
	--          jusqu'à ce qu'un admin lève la sanction.
	mode = "ugc",

	--  Case transverse. À true, RIEN n'est appliqué : ni ban, ni kick, ni
	--  privation. Tout est détecté et enregistré comme d'habitude, et le
	--  panel te montre ce qui SERAIT arrivé. C'est le mode d'observation.
	shadow = true,

	--  À true, on corrige quand même la position (rubber-band) et on prévient
	--  le joueur, sans jamais sanctionner. À false pendant un shadow, le
	--  joueur ne voit strictement rien.
	shadowCorrect = false,

	--  Combien de WARNINGS officiels avant la privation d'UGC.
	--  Rappel de l'échelle : 3 détections rapprochées = 1 strike lot = 1 warning.
	--  2 warnings, c'est donc déjà un comportement répété sur plusieurs minutes.
	warningsToRestrict = 1,

	--  👮 LES ADMINS SONT-ILS ANALYSÉS COMME TOUT LE MONDE ?
	--    true  = aucun privilège. Ils sont mesurés, ils accumulent des warnings,
	--            ils peuvent être privés d'UGC exactement comme un joueur.
	--            C'est le réglage honnête, et le seul qui te dise vraiment si
	--            ton anti-cheat produit des faux positifs — parce que TU es le
	--            joueur dont tu sais avec certitude qu'il ne triche pas.
	--    false = ils sont ignorés (l'ancien comportement).
	analyzeAdmins = true,

	--  🎯 SEUILS DE CERTITUDE (voir AntiFlyTP : chaque détection est notée)
	--    Une détection sous `minConfidenceCount` est enregistrée pour que tu
	--    puisses la lire, mais elle ne compte AUCUN strike. C'est le filtre
	--    qui élimine les faux positifs : on ne compte que ce qu'on sait
	--    expliquer.
	minConfidenceCount    = 55,   -- en dessous : journalisé, non compté
	minConfidenceWarn     = 70,   -- moyenne requise pour émettre un warning
	minConfidenceSanction = 85,   -- moyenne requise pour priver d'UGC

	--  Prévenir le joueur par un panneau quand la privation tombe.
	notifyOnRestrict = true,

	--  Kicker une fois au moment où la privation tombe (il peut revenir).
	--  Laissé à false : la privation se suffit à elle-même.
	kickOnRestrict = false,

	--  Le message affiché au joueur restreint. Tu peux le réécrire depuis le
	--  panel sans toucher au code.
	supportMessage =
		"Our anti-cheat system has flagged your account for abnormal movement "
		.. "(fly, teleport or speed).\n\n"
		.. "As a result, UGC redemptions are disabled on your account. "
		.. "Your points are untouched and you can keep playing normally.\n\n"
		.. "If you believe this is a mistake, please contact our support team "
		.. "and include evidence — a short video of your gameplay is best. "
		.. "We review every appeal by hand.",

	--════════════════════════════════════════════════════════════════════
	-- ⚙️ PARAMÈTRES PAR MODE — chaque mode a sa propre fiche
	--
	--    `mode` choisit LEQUEL est actif. Les trois fiches existent toujours
	--    en mémoire, donc tu peux régler le mode ban pendant que tu tournes
	--    en mode ugc, et basculer plus tard sans rien reconfigurer.
	--
	--    ⚠️ Le mode « test » n'est pas une valeur de `mode` : c'est le
	--       drapeau `shadow`, qui se superpose au mode choisi. Sa fiche
	--       décrit donc ce qui se passe PENDANT une observation.
	--════════════════════════════════════════════════════════════════════
	modes = {

		--  🔨 MODE BAN — l'échelle classique
		ban = {
			--  Combien de warnings officiels avant la sanction finale.
			warningsToPunish = 3,
			--  Kick d'avertissement au warning juste avant le dernier.
			--  Le joueur revient : c'est un signal, pas une sanction.
			kickBeforeBan    = true,
			--  0 = ban définitif. Sinon, durée en jours.
			--  ⚠️ Roblox n'a pas de « déban automatique » côté DataStore :
			--     c'est nous qui stockons la date de fin et laissons rentrer
			--     le joueur une fois passée.
			banDays          = 0,
			--  Priver aussi d'UGC. Utile surtout si le ban est temporaire :
			--  le joueur revient, mais ne peut pas convertir sa triche.
			alsoRestrictUGC  = true,
			--  Remettre les points à 0 au moment du ban.
			--  ⚠️ IRRÉVERSIBLE. Laissé à false — si tu te trompes, tu ne peux
			--     pas rendre les points.
			wipePoints       = false,
			--  Prévenir le joueur avant de l'éjecter (il voit la raison).
			notifyBeforeKick = true,
		},

		--  🚫 MODE UGC — le mode par défaut, et le plus sûr
		ugc = {
			--  Combien de warnings officiels avant la privation.
			warningsToPunish = 1,
			--  0 = jusqu'à ce qu'un admin lève la sanction.
			--  Sinon, durée en heures (la levée est alors automatique).
			durationHours    = 0,
			--  Kicker une fois au moment où la privation tombe.
			kickOnPunish     = false,
			--  Afficher le panneau explicatif au moment de la privation.
			notifyOnPunish   = true,
			--  Re-afficher le panneau à chaque connexion tant que la
			--  privation dure. Coupé : il ne le revoit qu'en essayant
			--  d'acheter (voir revealOnlyWhenAffordable).
			remindOnJoin     = false,
			--  Le panneau ne se ré-affiche QUE s'il essaie d'acheter une UGC
			--  qu'il pourrait normalement se payer. Sans assez de points, il
			--  voit le message normal « pas assez de points » (et on ne lui
			--  propose PAS d'acheter des points en Robux : il ne pourrait
			--  pas s'en servir).
			revealOnlyWhenAffordable = true,
			--  Bloquer aussi les dons d'UGC entre joueurs, si ton jeu en a.
			--  (Le script de dons doit appeler _G.UGCRestrict.CheckPurchase.)
			blockGifts       = true,
			--  Bloquer aussi le rebirth (certains l'utilisent pour blanchir
			--  des points obtenus en trichant). Laissé à false par défaut.
			blockRebirth     = false,
		},

		--  🧪 MODE TEST / SHADOW — l'observation
		--     Actif quand `shadow = true`, quel que soit le mode choisi.
		test = {
			--  Corriger quand même la position (rubber-band) ?
			--  false = le tricheur ne sait pas qu'il est mesuré, tu récoltes
			--  des données propres. true = tu gênes déjà, mais tu te trahis.
			correctPosition  = false,
			--  Le joueur voit-il les cartes d'avertissement ?
			--  false = observation totalement silencieuse.
			notifyPlayer     = false,
			--  Écrire chaque décision dans la console serveur.
			logToConsole     = true,
			--  Écrire dans des DataStores séparés (warnings de test), pour
			--  ne jamais polluer les compteurs réels.
			separateStore    = true,
			--  Après combien de jours d'observation le panel t'affiche un
			--  rappel « tu peux couper le shadow ». Purement informatif.
			suggestAfterDays = 5,
		},
	},

	--════════════════════════════════════════════════════════════════════
	-- 💬 MESSAGES AFFICHÉS AUX JOUEURS
	--
	--    Variables disponibles dans tous les textes :
	--      {player}      nom du joueur
	--      {type}        type de détection (FLY_STATE, TELEPORT, SPEED…)
	--      {typefr}      le même, traduit en français lisible
	--      {warnings}    nombre de warnings actuels
	--      {max}         nombre de warnings avant sanction
	--      {left}        warnings restants avant sanction
	--      {confidence}  certitude en % de la dernière décision
	--      {game}        nom de l'expérience
	--
	--    \n fait un retour à la ligne. Les accolades inconnues sont
	--    laissées telles quelles (pas de crash).
	--════════════════════════════════════════════════════════════════════
	messages = {

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
	},
}

--════════════════════════════════════════════════════════════════════════════
-- 📄 LES RÉGLAGES DE ANTICHEAT_CONFIG (sections ① à ⑦) DEVIENNENT LES DÉFAUTS
--════════════════════════════════════════════════════════════════════════════
if ACFILE then
	local F = ACFILE
	local function tbl(x) return (type(x) == "table") and x or {} end
	local A, S, D, P, B, T = tbl(F.Activation), tbl(F.Sanction), tbl(F.Discretion),
		tbl(F.Preuve), tbl(F.ModeBan), tbl(F.ModeTest)
	local function set(t, k, v)
		if v ~= nil and (t[k] == nil or type(v) == type(t[k])) then t[k] = v end
	end
	set(DEFAULTS, "mode", A.Mode)
	set(DEFAULTS, "shadow", A.ModeTest)
	set(DEFAULTS, "analyzeAdmins", A.AnalyserLesAdmins)
	set(DEFAULTS, "warningsToRestrict", S.WarningsAvantSanction)
	set(DEFAULTS, "notifyOnRestrict", S.MessageALaSanction)
	set(DEFAULTS, "kickOnRestrict", S.KickALaSanction)
	local u = DEFAULTS.modes.ugc
	set(u, "warningsToPunish", S.WarningsAvantSanction)
	set(u, "durationHours", S.DureeHeures)
	set(u, "notifyOnPunish", S.MessageALaSanction)
	set(u, "remindOnJoin", S.RappelAChaqueConnexion)
	set(u, "kickOnPunish", S.KickALaSanction)
	set(u, "blockGifts", S.BloquerDons)
	set(u, "blockRebirth", S.BloquerRebirth)
	set(u, "revealOnlyWhenAffordable", D.MontrerSanctionSeulementALAchat)
	set(DEFAULTS, "silent", D.JoueurNeVoitRien)
	set(DEFAULTS, "warningExpiryDays", D.WarningDisparaitApresJours)
	set(DEFAULTS, "minConfidenceCount", P.CompterAPartirDe)
	set(DEFAULTS, "minConfidenceWarn", P.AvertirAPartirDe)
	set(DEFAULTS, "minConfidenceSanction", P.SanctionnerAPartirDe)
	local b = DEFAULTS.modes.ban
	set(b, "warningsToPunish", B.WarningsAvantBan)
	set(b, "banDays", B.DureeJours)
	set(b, "kickBeforeBan", B.KickAvantBan)
	set(b, "alsoRestrictUGC", B.PriverAussiUGC)
	set(b, "notifyBeforeKick", B.PanneauAvantKick)
	set(b, "wipePoints", B.RemettrePointsAZero)
	local t = DEFAULTS.modes.test
	set(t, "correctPosition", T.CorrigerPosition)
	set(t, "notifyPlayer", T.JoueurVoitCartes)
	set(t, "logToConsole", T.LogConsole)
	set(t, "separateStore", T.StockageSepare)
	set(t, "suggestAfterDays", T.RappelApresJours)
	set(DEFAULTS, "supportMessage", F.MessageSanction)
	for k, v in pairs(tbl(F.Messages)) do set(DEFAULTS.messages, k, v) end
end

--════════════════════════════════════════════════════════════════════════════
-- 💾 STORES
--════════════════════════════════════════════════════════════════════════════
local CONFIG_STORE  = DataStoreService:GetDataStore("AntiCheat_Config_v1")
local RESTRICT_STORE = DataStoreService:GetDataStore("AntiCheat_UGCRestrict_v1")
local RESTRICT_INDEX = DataStoreService:GetOrderedDataStore("AntiCheat_UGCRestrictIdx_v1")
local ATTEMPT_INDEX  = DataStoreService:GetOrderedDataStore("AntiCheat_UGCRestrictTry_v1")

local TOPIC_CONFIG   = "AC_ConfigSync"
local TOPIC_RESTRICT = "AC_RestrictSync"

--════════════════════════════════════════════════════════════════════════════
-- 🧠 ÉTAT MÉMOIRE
--════════════════════════════════════════════════════════════════════════════
local cfg          = {}          -- config courante
local cfgLoaded    = false
local cache        = {}          -- [userId] = record | false  (false = vérifié, pas restreint)
local cacheAt      = {}          -- [userId] = os.clock() de la mise en cache
local pendingTries = {}          -- [userId] = nb de tentatives d'achat non encore écrites
local CACHE_TTL    = 120         -- s : au-delà, on relit (un autre serveur a pu lever la sanction)

for k, v in pairs(DEFAULTS) do cfg[k] = v end
--  Tant que la config n'est pas lue (DataStore muet), personne n'est sanctionné.
cfg.shadow = true

--════════════════════════════════════════════════════════════════════════════
-- 💬 RENDU DES GABARITS DE MESSAGE
--
--    Remplace {player}, {warnings}, {max}, {left}, {type}, {typefr},
--    {confidence}, {game} par les valeurs fournies.
--
--    Trois garde-fous :
--      • une accolade inconnue est laissée telle quelle (jamais de crash,
--        jamais de "nil" affiché au joueur) ;
--      • {confidence} est effacé si `showConfidenceToPlayer` est faux —
--        même si tu l'as laissé dans ton texte. Le réglage gagne toujours
--        contre l'oubli, parce que révéler le seuil aide le tricheur ;
--      • le résultat est coupé à 1400 caractères.
--════════════════════════════════════════════════════════════════════════════
local TYPE_FR = {
	FLY_STATE   = "vol",
	FLY_HOVER   = "vol stationnaire",
	FLY_ASCENT  = "montée sans support",
	FLY_UPSPEED = "montée trop rapide",
	TELEPORT    = "téléportation",
	SPEED       = "vitesse anormale",
}

--  Le type DOMINANT d'un dossier. `byType` est une table de compteurs
--  ({ FLY_STATE = 3, SPEED = 1 }) : la donner telle quelle à un gabarit
--  afficherait « table: 0x… » au joueur. On en extrait le signal le plus
--  fréquent, qui est aussi le plus parlant dans un message.
local function topType(byType)
	if type(byType) ~= "table" then
		return (type(byType) == "string" and byType ~= "") and byType or nil
	end
	local best, bestN = nil, -1
	for k, v in pairs(byType) do
		local n = tonumber(v) or 0
		if n > bestN then best, bestN = k, n end
	end
	return best
end

local function renderTemplate(tpl, vars)
	if type(tpl) ~= "string" then return "" end
	vars = vars or {}

	local M = (type(cfg.messages) == "table") and cfg.messages or DEFAULTS.messages
	local showConf = M.showConfidenceToPlayer == true

	local vType = tostring(vars.type or vars.vType or "")
	local warnings = tonumber(vars.warnings) or 0
	local maxW = tonumber(vars.max)
	if not maxW then
		local m = (type(cfg.modes) == "table") and cfg.modes[cfg.mode or "ugc"] or nil
		maxW = (m and m.warningsToPunish) or cfg.warningsToRestrict or 2
	end

	--  🔐 Si tu as choisi de NE PAS montrer la certitude au joueur, on ne se
	--     contente pas de vider la variable : on supprime la LIGNE ENTIÈRE
	--     qui la contient, avant toute substitution.
	--
	--     Pourquoi la ligne entière plutôt qu'un nettoyage cosmétique : un
	--     remplacement par du vide laisse « Certitude :  % », et deviner où
	--     couper demanderait de reconnaître la phrase — donc de deviner ta
	--     langue et ta formulation. Supprimer la ligne est le seul
	--     comportement prévisible quoi que tu écrives.
	--
	--     👉 Conséquence pratique : mets {confidence} sur sa PROPRE LIGNE.
	--        Le panel te l'affiche en aperçu, tu vois le résultat exact.
	if not showConf and tpl:find("{confidence}", 1, true) then
		local kept = {}
		for line in (tpl .. "\n"):gmatch("([^\n]*)\n") do
			if not line:find("{confidence}", 1, true) then
				table.insert(kept, line)
			end
		end
		tpl = table.concat(kept, "\n")
		--  On évite de laisser deux lignes vides à la place de la ligne ôtée.
		tpl = tpl:gsub("\n\n\n+", "\n\n"):gsub("^%s*\n", "")
	end

	local map = {
		player     = tostring(vars.player or "player"),
		type       = vType ~= "" and vType or "movement",
		typefr     = TYPE_FR[vType] or (vType ~= "" and vType or "mouvement anormal"),
		warnings   = tostring(warnings),
		max        = tostring(maxW),
		left       = tostring(math.max(maxW - warnings, 0)),
		game       = tostring(vars.game or "this experience"),
		--  Les lignes contenant {confidence} ont déjà été retirées plus haut
		--  quand l'affichage est coupé ; ce repli ne sert que de ceinture.
		confidence = showConf and tostring(math.floor(tonumber(vars.confidence) or 0)) or "",
	}

	local out = tpl:gsub("{(%w+)}", function(k)
		local v = map[k]
		if v == nil then return "{" .. k .. "}" end   -- inconnu : on n'y touche pas
		return v
	end)

	return (out:gsub("\\n", "\n")):sub(1, 1400)
end


local function log(...)
	print("🚫 [UGCRestrict]", ...)
end

--════════════════════════════════════════════════════════════════════════════
-- 📡 REMOTES
--════════════════════════════════════════════════════════════════════════════
local function remote(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local notifyRemote  = remote("UGCRestrictNotify", "RemoteEvent")        -- serveur → client
local adminGet      = remote("AdminGetUGCRestrict", "RemoteFunction")   -- panel → serveur
local adminAction   = remote("AdminUGCRestrictAction", "RemoteFunction")

--  Signal interne : l'anti-fly l'écoute pour recharger sa config à chaud.
local cfgChanged = ServerStorage:FindFirstChild("ACConfigChanged")
if not cfgChanged then
	cfgChanged = Instance.new("BindableEvent")
	cfgChanged.Name = "ACConfigChanged"
	cfgChanged.Parent = ServerStorage
end

--════════════════════════════════════════════════════════════════════════════
-- 👮 ADMINS
--    ⚠️ La MÊME liste que ton panel admin. Si tu ajoutes un admin, mets-le
--    ici AUSSI, sinon le serveur refusera toutes ses actions (comportement
--    voulu : le client ne décide jamais qui est admin).
--════════════════════════════════════════════════════════════════════════════
local ADMIN_IDS = (ACFILE and type(ACFILE.Admins) == "table" and #ACFILE.Admins > 0)
	and ACFILE.Admins
	or { 3203521470, 11017023724, 8456613930, 8142402169, 10420404767 }
local adminSet = {}
for _, id in ipairs(ADMIN_IDS) do adminSet[id] = true end

local function isAdmin(userId) return adminSet[userId] == true end

--  L'anti-fly s'en sert pour ne JAMAIS analyser un admin (c'était l'une des
--  causes de vos avertissements : la whitelist du script anti-fly était
--  commentée, donc les admins étaient analysés comme tout le monde).
_G.AC_ADMIN_IDS = ADMIN_IDS

--════════════════════════════════════════════════════════════════════════════
-- ⚙️ CHARGEMENT / SAUVEGARDE DE LA CONFIG
--════════════════════════════════════════════════════════════════════════════
--════════════════════════════════════════════════════════════════════════════
-- 🗂️ LISTE DE TOUS LES RÉGLAGES (affichée dans le panel ⚙️, par sections)
--    Chaque réglage : où il est rangé, son type, ses limites, son explication.
--    Le panel n'invente rien : il affiche cette liste, et le serveur refuse
--    toute valeur hors limites.
--    t = "bool" | "number" | "choice" | "text" | "list" | "numlist" | "map"
--    adv = réglage de détection (appliqué en direct par l'anti-fly)
--    sev = valeur choisie par la Sévérité tant qu'elle n'est pas « custom »
--════════════════════════════════════════════════════════════════════════════
local SCHEMA = {
	{ id = "essentiel", title = "⭐ L'ESSENTIEL", open = true,
		intro = "Les 5 réglages qui comptent vraiment. Tout le reste peut rester tel quel.",
		fields = {
			{ id = "ugc.warn", path = { "modes", "ugc", "warningsToPunish" }, t = "number", min = 1, max = 1000, step = 1,
				label = "🚨 Warnings avant la restriction",
				desc = "Combien de warnings un joueur doit recevoir avant d'être privé d'UGC. Tape n'importe quel nombre de 1 à 1000. Rappel : 1 warning = plusieurs détections sûres et rapprochées (voir « Strikes »)." },
			{ id = "shadow", path = { "shadow" }, t = "bool",
				label = "🧪 Mode test (personne n'est sanctionné)",
				desc = "ACTIVÉ : tout est mesuré et noté, mais AUCUNE sanction n'est appliquée. Le panel montre ce qui SERAIT arrivé. COUPÉ : les sanctions sont réelles." },
			{ id = "mode", path = { "mode" }, t = "choice",
				options = { { v = "ugc", l = "🚫 Privation d'UGC" }, { v = "ban", l = "🔨 Ban" } },
				label = "Type de sanction",
				desc = "Privation d'UGC : le joueur garde ses points et continue de jouer, mais ne peut plus obtenir d'UGC (réversible en un clic). Ban : il est éjecté du jeu." },
			{ id = "silent", path = { "silent" }, t = "bool",
				label = "🤫 Le joueur ne voit rien de ses warnings",
				desc = "Aucune carte, aucun retour en arrière, aucun kick d'avertissement. Il ne l'apprend qu'au moment de la sanction." },
			{ id = "expiry", path = { "warningExpiryDays" }, t = "number", min = 0, max = 3650, step = 5,
				label = "⏳ Un warning disparaît après (jours)",
				desc = "Chaque warning s'efface tout seul ce nombre de jours après avoir été reçu. 0 = jamais. Sert à effacer un faux warning isolé." },
		} },

	{ id = "ugc", title = "🚫 SANCTION : PRIVATION D'UGC",
		intro = "Ce qui se passe quand un joueur atteint le nombre de warnings (si le type de sanction est « Privation d'UGC »).",
		fields = {
			{ id = "ugc.hours", path = { "modes", "ugc", "durationHours" }, t = "number", min = 0, max = 8760, step = 12,
				label = "Durée de la privation (heures)", desc = "0 = jusqu'à ce qu'un admin la lève. Sinon, levée automatique après ce nombre d'heures." },
			{ id = "ugc.notify", path = { "modes", "ugc", "notifyOnPunish" }, t = "bool",
				label = "Message « UGC désactivées » à la sanction", desc = "Affiché UNE fois au joueur (à sa prochaine connexion s'il n'était pas en jeu)." },
			{ id = "ugc.reveal", path = { "modes", "ugc", "revealOnlyWhenAffordable" }, t = "bool",
				label = "Remontrer la sanction seulement à l'achat", desc = "Ensuite, il ne revoit le message QUE s'il essaie d'acheter une UGC qu'il pourrait se payer. Sans assez de points : « Not enough points », sans proposition Robux." },
			{ id = "ugc.remind", path = { "modes", "ugc", "remindOnJoin" }, t = "bool",
				label = "Rappeler à chaque connexion", desc = "Remontre le message à chaque connexion. Laisse coupé pour qu'il ne le voie qu'à l'achat." },
			{ id = "ugc.kick", path = { "modes", "ugc", "kickOnPunish" }, t = "bool",
				label = "Kicker une fois à la sanction", desc = "Il peut revenir tout de suite. Coupé conseillé." },
			{ id = "ugc.gifts", path = { "modes", "ugc", "blockGifts" }, t = "bool",
				label = "Bloquer les dons d'UGC", desc = "Empêche un complice de lui offrir une UGC." },
			{ id = "ugc.rebirth", path = { "modes", "ugc", "blockRebirth" }, t = "bool",
				label = "Bloquer le rebirth", desc = "Empêche un joueur restreint de faire un rebirth." },
		} },

	{ id = "preuve", title = "🎯 NIVEAU DE PREUVE",
		intro = "Chaque détection reçoit une certitude de 0 à 99 %. Ces seuils décident ce qui compte.",
		fields = {
			{ id = "conf.count", path = { "minConfidenceCount" }, t = "number", min = 0, max = 99, step = 5,
				label = "Compter une détection à partir de (%)", desc = "En dessous : notée dans le journal du serveur, mais ne compte pas." },
			{ id = "conf.warn", path = { "minConfidenceWarn" }, t = "number", min = 0, max = 99, step = 5,
				label = "Donner un warning à partir de (%)", desc = "Moyenne minimale des détections qui forment un warning." },
			{ id = "conf.sanction", path = { "minConfidenceSanction" }, t = "number", min = 0, max = 99, step = 5,
				label = "Sanctionner à partir de (%)", desc = "Certitude du dossier requise pour la sanction automatique. Ne descends pas sous 80." },
			{ id = "admins", path = { "analyzeAdmins" }, t = "bool",
				label = "Analyser les admins comme tout le monde", desc = "Conseillé : c'est ton meilleur test de faux positifs." },
		} },

	{ id = "ban", title = "🔨 MODE BAN",
		intro = "Utilisé seulement si le type de sanction est « Ban ».",
		fields = {
			{ id = "ban.warn", path = { "modes", "ban", "warningsToPunish" }, t = "number", min = 1, max = 1000, step = 1,
				label = "Warnings avant le ban", desc = "De 1 à 1000." },
			{ id = "ban.days", path = { "modes", "ban", "banDays" }, t = "number", min = 0, max = 3650, step = 1,
				label = "Durée du ban (jours)", desc = "0 = définitif." },
			{ id = "ban.kick", path = { "modes", "ban", "kickBeforeBan" }, t = "bool",
				label = "Kick d'avertissement avant le ban", desc = "Ignoré tant que « le joueur ne voit rien » est actif." },
			{ id = "ban.ugc", path = { "modes", "ban", "alsoRestrictUGC" }, t = "bool",
				label = "Priver aussi d'UGC", desc = "Utile si le ban est temporaire." },
			{ id = "ban.notify", path = { "modes", "ban", "notifyBeforeKick" }, t = "bool",
				label = "Afficher la raison avant d'éjecter", desc = "Le joueur lit la raison 4 s avant le kick." },
			{ id = "ban.wipe", path = { "modes", "ban", "wipePoints" }, t = "bool", danger = true,
				label = "⚠️ Remettre les points à 0", desc = "IRRÉVERSIBLE. Laisse coupé." },
		} },

	{ id = "test", title = "🧪 MODE TEST",
		intro = "Ce qui se passe pendant le mode test (quand il est activé).",
		fields = {
			{ id = "test.correct", path = { "modes", "test", "correctPosition" }, t = "bool",
				label = "Ramener quand même le joueur en arrière", desc = "Coupé : le tricheur ne sait pas qu'il est mesuré." },
			{ id = "test.cards", path = { "modes", "test", "notifyPlayer" }, t = "bool",
				label = "Montrer les cartes d'avertissement", desc = "Coupé : observation totalement silencieuse." },
			{ id = "test.log", path = { "modes", "test", "logToConsole" }, t = "bool",
				label = "Écrire chaque décision dans la console", desc = "Les lignes 🧪 [SHADOW] dans la console serveur (F9)." },
			{ id = "test.store", path = { "modes", "test", "separateStore" }, t = "bool",
				label = "Warnings de test séparés des vrais", desc = "À garder actif." },
			{ id = "test.days", path = { "modes", "test", "suggestAfterDays" }, t = "number", min = 1, max = 90, step = 1,
				label = "Rappel « tu peux couper le mode test » après (jours)", desc = "Purement informatif." },
		} },

	{ id = "messages", title = "💬 MESSAGES AUX JOUEURS",
		intro = "Variables utilisables : {player} {typefr} {type} {warnings} {max} {left} {confidence} {game}. \\n = retour à la ligne.",
		fields = {
			{ id = "msg.restrictTitle", path = { "messages", "restrictTitle" }, t = "text", max = 120, label = "Titre du message de privation" },
			{ id = "msg.support", path = { "supportMessage" }, t = "text", max = 1200, label = "Texte du message de privation" },
			{ id = "msg.shopBlockedTitle", path = { "messages", "shopBlockedTitle" }, t = "text", max = 120, label = "Achat refusé : titre" },
			{ id = "msg.shopBlockedBody", path = { "messages", "shopBlockedBody" }, t = "text", max = 1200, label = "Achat refusé : texte" },
			{ id = "msg.shopUnverifiedTitle", path = { "messages", "shopUnverifiedTitle" }, t = "text", max = 120, label = "Vérification impossible : titre" },
			{ id = "msg.shopUnverifiedBody", path = { "messages", "shopUnverifiedBody" }, t = "text", max = 1200, label = "Vérification impossible : texte" },
			{ id = "msg.banTitle", path = { "messages", "banTitle" }, t = "text", max = 120, label = "Ban : titre" },
			{ id = "msg.banBody", path = { "messages", "banBody" }, t = "text", max = 1200, label = "Ban : texte" },
			{ id = "msg.warnEnabled", path = { "messages", "warnEnabled" }, t = "bool", label = "Carte rouge à chaque warning", desc = "Sans effet tant que « le joueur ne voit rien » est actif." },
			{ id = "msg.warnTitle", path = { "messages", "warnTitle" }, t = "text", max = 120, label = "Carte rouge : titre" },
			{ id = "msg.warnBody", path = { "messages", "warnBody" }, t = "text", max = 1200, label = "Carte rouge : texte" },
			{ id = "msg.nudgeEnabled", path = { "messages", "nudgeEnabled" }, t = "bool", label = "Carte orange à chaque détection", desc = "Sans effet tant que « le joueur ne voit rien » est actif." },
			{ id = "msg.nudgeAfter", path = { "messages", "nudgeAfterDetections" }, t = "number", min = 1, max = 20, step = 1, label = "Carte orange après N détections" },
			{ id = "msg.nudgeCooldown", path = { "messages", "nudgeCooldown" }, t = "number", min = 0, max = 300, step = 5, label = "Secondes entre deux cartes orange" },
			{ id = "msg.nudgeTitle", path = { "messages", "nudgeTitle" }, t = "text", max = 120, label = "Carte orange : titre" },
			{ id = "msg.nudgeBody", path = { "messages", "nudgeBody" }, t = "text", max = 1200, label = "Carte orange : texte" },
			{ id = "msg.showConf", path = { "messages", "showConfidenceToPlayer" }, t = "bool", label = "Montrer la certitude (%) au joueur", desc = "Déconseillé : un tricheur saurait de combien ralentir." },
		} },

	{ id = "severite", title = "🎚️ SÉVÉRITÉ DE LA DÉTECTION",
		intro = "« lenient » = très tolérant · « balanced » = conseillé · « strict » = sévère · « custom » = tes propres valeurs. Tant que ce n'est pas « custom », les réglages marqués ◆ sont choisis par la sévérité.",
		fields = {
			{ adv = "Preset", t = "choice", options = { { v = "lenient", l = "Tolérant" }, { v = "balanced", l = "Conseillé" }, { v = "strict", l = "Sévère" }, { v = "custom", l = "Custom" } },
				label = "Sévérité" },
			{ adv = "Enabled", t = "bool", label = "Analyse active", desc = "Coupé : plus rien n'est mesuré." },
			{ adv = "VerboseLogs", t = "bool", label = "Messages détaillés dans la console" },
			{ adv = "Sampling.Interval", t = "number", min = 0.1, max = 1, step = 0.05, label = "Fréquence de mesure (s)" },
			{ adv = "Sampling.MaxUsableDelta", t = "number", min = 0.3, max = 3, step = 0.05, label = "Écart max entre deux mesures (s)", desc = "Au-delà, on considère que le serveur a laggé et on ne juge pas." },
		} },

	{ id = "vol", title = "🕊️ DÉTECTION DU VOL",
		fields = {
			{ adv = "Fly.Enabled", t = "bool", label = "Détecter le vol" },
			{ adv = "Fly.DetectHover", t = "bool", label = "Vol stationnaire (immobile en l'air)" },
			{ adv = "Fly.DetectAscent", t = "bool", label = "Longue montée sans appui", desc = "Bruyant dans un obby : coupé conseillé." },
			{ adv = "Fly.DetectUpSpeed", t = "bool", label = "Montée trop rapide", desc = "Bruyant dans un obby : coupé conseillé." },
			{ adv = "Fly.MaxHoverTime", t = "number", min = 0.5, max = 30, step = 0.5, sev = true, label = "Temps max immobile en l'air (s)" },
			{ adv = "Fly.HoverBandY", t = "number", min = 1, max = 30, step = 1, sev = true, label = "Vitesse verticale max pour « immobile »" },
			{ adv = "Fly.HoverMinHeight", t = "number", min = 2, max = 100, step = 1, sev = true, label = "Hauteur min au-dessus du sol (studs)" },
			{ adv = "Fly.AscentMultiplier", t = "number", min = 1, max = 10, step = 0.1, label = "Montée : × hauteur de saut" },
			{ adv = "Fly.AscentFlatBonus", t = "number", min = 0, max = 200, step = 1, sev = true, label = "Montée : marge (studs)" },
			{ adv = "Fly.MaxUpSpeedMultiplier", t = "number", min = 1, max = 10, step = 0.1, label = "Montée rapide : × vitesse de saut" },
			{ adv = "Fly.MaxUpSpeedFlat", t = "number", min = 0, max = 200, step = 1, sev = true, label = "Montée rapide : marge (studs/s)" },
			{ adv = "Fly.UpSpeedSamples", t = "number", min = 1, max = 40, step = 1, sev = true, label = "Montée rapide : mesures d'affilée" },
			{ adv = "Fly.TreatClimbingAsGround", t = "bool", label = "Grimper (échelles) = au sol" },
			{ adv = "Fly.TreatSwimmingAsGround", t = "bool", label = "Nager = au sol" },
			{ adv = "Fly.GroundRayDistance", t = "number", min = 1, max = 30, step = 0.5, label = "Distance de détection du sol (studs)" },
		} },

	{ id = "tp", title = "🌀 DÉTECTION DE TÉLÉPORTATION",
		fields = {
			{ adv = "Teleport.Enabled", t = "bool", label = "Détecter les téléportations" },
			{ adv = "Teleport.MaxPredictionError", t = "number", min = 10, max = 500, step = 5, sev = true, label = "Écart horizontal toléré (studs)" },
			{ adv = "Teleport.MaxVerticalError", t = "number", min = 10, max = 500, step = 5, sev = true, label = "Écart vertical toléré (studs)" },
			{ adv = "Teleport.MinTeleportDistance", t = "number", min = 5, max = 300, step = 1, sev = true, label = "Distance min d'un saut suspect (studs)" },
			{ adv = "Teleport.IgnoreIfVelocityConsistent", t = "bool", label = "Ignorer si la vitesse explique le déplacement" },
			{ adv = "Teleport.VelocityConsistencyRatio", t = "number", min = 0.1, max = 1, step = 0.05, label = "Part du déplacement à expliquer par la vitesse" },
			{ adv = "Teleport.SafeDestinationRadius", t = "number", min = 0, max = 200, step = 1, label = "Rayon autour des destinations autorisées (studs)" },
			{ adv = "Teleport.SafePartNames", t = "list", label = "Destinations toujours autorisées (noms de parts)", desc = "Séparées par des virgules. Ex : FirstSpawn, TpRebirth, Portail2" },
			{ adv = "Teleport.SafePartPatterns", t = "list", label = "Destinations autorisées (motifs Lua)" },
			{ adv = "Teleport.SafeIncludeSpawnLocations", t = "bool", label = "Les SpawnLocation sont autorisées" },
			{ adv = "Teleport.CheckpointDestinations", t = "choice", options = { { v = "always", l = "Toujours" }, { v = "limited", l = "Limité" }, { v = "never", l = "Jamais" } }, label = "Arrivée près d'un checkpoint" },
			{ adv = "Teleport.MaxCheckpointTeleportsPerMinute", t = "number", min = 0, max = 60, step = 1, label = "Checkpoints max par minute (si « Limité »)" },
			{ adv = "Teleport.CheckpointPattern", t = "text", max = 80, label = "Nom des checkpoints (motif Lua)" },
		} },

	{ id = "vitesse", title = "💨 DÉTECTION DE VITESSE",
		fields = {
			{ adv = "Speed.Enabled", t = "bool", label = "Détecter la vitesse anormale" },
			{ adv = "Speed.Tolerance", t = "number", min = 1, max = 10, step = 0.1, sev = true, label = "Tolérance (× vitesse de marche)" },
			{ adv = "Speed.FlatBonus", t = "number", min = 0, max = 200, step = 1, sev = true, label = "Marge (studs/s)" },
			{ adv = "Speed.SustainedSamples", t = "number", min = 1, max = 80, step = 1, sev = true, label = "Mesures d'affilée (× 0,25 s)" },
			{ adv = "Speed.MinBaselineWalkSpeed", t = "number", min = 1, max = 100, step = 1, label = "Vitesse de marche de référence min" },
		} },

	{ id = "strikes", title = "⚖️ DÉTECTIONS → WARNING",
		intro = "Combien de détections retenues font UN warning.",
		fields = {
			{ adv = "Punishment.StrikesPerWarning", t = "number", min = 1, max = 100, step = 1, sev = true, label = "Détections pour 1 warning" },
			{ adv = "Punishment.StrikeDecaySeconds", t = "number", min = 10, max = 3600, step = 10, sev = true, label = "Une détection s'oublie après (s de calme)" },
			{ adv = "Punishment.EscalationCooldown", t = "number", min = 0, max = 60, step = 1, sev = true, label = "Écart min entre deux détections comptées (s)" },
			{ adv = "Punishment.PassiveDecay", t = "bool", label = "Les détections s'oublient toutes seules" },
			{ adv = "Punishment.StrikeWeights.FLY_HOVER", t = "number", min = 0, max = 10, step = 1, label = "Poids : vol stationnaire" },
			{ adv = "Punishment.StrikeWeights.FLY_STATE", t = "number", min = 0, max = 10, step = 1, label = "Poids : état « Flying »" },
			{ adv = "Punishment.StrikeWeights.FLY_ASCENT", t = "number", min = 0, max = 10, step = 1, label = "Poids : montée sans appui" },
			{ adv = "Punishment.StrikeWeights.FLY_UPSPEED", t = "number", min = 0, max = 10, step = 1, label = "Poids : montée rapide" },
			{ adv = "Punishment.StrikeWeights.TELEPORT", t = "number", min = 0, max = 10, step = 1, label = "Poids : téléportation" },
			{ adv = "Punishment.StrikeWeights.SPEED", t = "number", min = 0, max = 10, step = 1, label = "Poids : vitesse" },
			{ adv = "Punishment.UseRobloxBanAPI", t = "bool", label = "Mode ban : utiliser le ban officiel Roblox" },
		} },

	{ id = "certitude", title = "🧮 CALCUL DE LA CERTITUDE (expert)",
		intro = "Combien chaque indice fait monter ou descendre la certitude. Ne touche pas sans raison.",
		fields = {
			{ adv = "Confidence.Enabled", t = "bool", label = "Calculer une certitude", desc = "Coupé : toute détection vaut 100 %. Déconseillé." },
			{ adv = "Confidence.Base.FLY_STATE", t = "number", min = 0, max = 99, step = 1, label = "Base : état « Flying »" },
			{ adv = "Confidence.Base.FLY_HOVER", t = "number", min = 0, max = 99, step = 1, label = "Base : vol stationnaire" },
			{ adv = "Confidence.Base.TELEPORT", t = "number", min = 0, max = 99, step = 1, label = "Base : téléportation" },
			{ adv = "Confidence.Base.FLY_UPSPEED", t = "number", min = 0, max = 99, step = 1, label = "Base : montée rapide" },
			{ adv = "Confidence.Base.FLY_ASCENT", t = "number", min = 0, max = 99, step = 1, label = "Base : montée sans appui" },
			{ adv = "Confidence.Base.SPEED", t = "number", min = 0, max = 99, step = 1, label = "Base : vitesse" },
			{ adv = "Confidence.MarginMax", t = "number", min = 0, max = 50, step = 1, label = "Bonus max : dépasse largement le seuil" },
			{ adv = "Confidence.DurationMax", t = "number", min = 0, max = 50, step = 1, label = "Bonus max : dure longtemps" },
			{ adv = "Confidence.CleanContext", t = "number", min = 0, max = 50, step = 1, label = "Bonus : rien n'explique la mesure" },
			{ adv = "Confidence.RepeatPer", t = "number", min = 0, max = 30, step = 1, label = "Bonus par répétition (1 min)" },
			{ adv = "Confidence.RepeatMax", t = "number", min = 0, max = 60, step = 1, label = "Bonus max de répétition" },
			{ adv = "Confidence.DiversityPer", t = "number", min = 0, max = 30, step = 1, label = "Bonus par type différent (5 min)" },
			{ adv = "Confidence.DiversityMax", t = "number", min = 0, max = 60, step = 1, label = "Bonus max de diversité" },
			{ adv = "Confidence.HistoryBonus", t = "number", min = 0, max = 50, step = 1, label = "Bonus : warnings déjà au dossier" },
			{ adv = "Confidence.NoGroundSeconds", t = "number", min = 1, max = 120, step = 1, label = "Sans toucher le sol depuis (s)…" },
			{ adv = "Confidence.NoGroundBonus", t = "number", min = 0, max = 50, step = 1, label = "…bonus" },
			{ adv = "Confidence.PenaltyLongDt", t = "number", min = 0, max = 60, step = 1, label = "Pénalité : serveur qui lag" },
			{ adv = "Confidence.PenaltyRecentGrace", t = "number", min = 0, max = 60, step = 1, label = "Pénalité : tolérance à peine finie" },
			{ adv = "Confidence.PenaltyRecentSpawn", t = "number", min = 0, max = 60, step = 1, label = "Pénalité : vient d'apparaître" },
			{ adv = "Confidence.PenaltyRecentForce", t = "number", min = 0, max = 60, step = 1, label = "Pénalité : force anti-gravité récente" },
			{ adv = "Confidence.PenaltyRecentLaunch", t = "number", min = 0, max = 60, step = 1, label = "Pénalité : propulsé récemment" },
			{ adv = "Confidence.PenaltyRecentRagdoll", t = "number", min = 0, max = 60, step = 1, label = "Pénalité : sortait d'un ragdoll" },
			{ adv = "Confidence.PenaltyFirstEver", t = "number", min = 0, max = 60, step = 1, label = "Pénalité : 1ʳᵉ détection de la session" },
			{ adv = "Confidence.RecentWindow", t = "number", min = 1, max = 120, step = 1, label = "« Récent » = moins de (s)" },
			{ adv = "Confidence.Ceiling", t = "number", min = 50, max = 99, step = 1, label = "Plafond de certitude (%)" },
		} },

	{ id = "outils", title = "🧰 OUTILS AUTORISÉS",
		intro = "Noms EXACTS des outils (séparés par des virgules). À compléter si tu ajoutes un outil qui fait voler ou accélère.",
		fields = {
			{ adv = "LegitTools.FlyTools", t = "list", label = "Outils qui font voler", desc = "Ex : Jetpack" },
			{ adv = "LegitTools.FlyToolMarkers", t = "list", label = "…ou outils qui contiennent ces pièces" },
			{ adv = "LegitTools.FlyToolDefaultProfile.MaxSpeed", t = "number", min = 10, max = 1000, step = 10, label = "Vitesse max avec un outil de vol" },
			{ adv = "LegitTools.GravityTools", t = "list", label = "Coils de gravité" },
			{ adv = "LegitTools.GravityProfile.MaxHoverTime", t = "number", min = 1, max = 60, step = 1, label = "Gravité : temps max en l'air (s)" },
			{ adv = "LegitTools.GravityProfile.AscentFlat", t = "number", min = 0, max = 500, step = 5, label = "Gravité : montée permise (studs)" },
			{ adv = "LegitTools.GravityProfile.MaxUpSpeed", t = "number", min = 0, max = 500, step = 5, label = "Gravité : vitesse de montée permise" },
			{ adv = "LegitTools.SpeedTools", t = "map", label = "Coils de vitesse (Nom=vitesse)", desc = "Ex : SpeedCoil=60, Speed Coil=60" },
			{ adv = "LegitTools.FusionTools", t = "list", label = "Coils fusion (vitesse + gravité)" },
			{ adv = "Fusion.Speed", t = "number", min = 0, max = 500, step = 5, label = "Fusion : vitesse" },
			{ adv = "Fusion.MaxHoverTime", t = "number", min = 1, max = 60, step = 1, label = "Fusion : temps max en l'air (s)" },
			{ adv = "Fusion.AscentFlat", t = "number", min = 0, max = 500, step = 5, label = "Fusion : montée permise (studs)" },
			{ adv = "Fusion.MaxUpSpeed", t = "number", min = 0, max = 500, step = 5, label = "Fusion : vitesse de montée permise" },
			{ adv = "LegitTools.ToolTrailingGrace", t = "number", min = 0, max = 30, step = 1, label = "Tolérance après avoir rangé l'outil (s)" },
			{ adv = "LegitTools.DetectAntiGravityForce", t = "bool", label = "Reconnaître un coil à sa force (même renommé)" },
			{ adv = "LegitTools.AntiGravityGrace", t = "number", min = 0, max = 30, step = 1, label = "Tolérance après la force anti-gravité (s)" },
		} },

	{ id = "systemes", title = "🌍 SYSTÈMES DU JEU",
		intro = "Ce que tes scripts font aux joueurs et qui ne doit JAMAIS être détecté.",
		fields = {
			{ adv = "LegitAttributes.FullBypass", t = "list", label = "Attributs qui suspendent l'analyse", desc = "Posés par tes scripts sur le joueur ou le personnage." },
			{ adv = "LegitAttributes.WatchForTrailing", t = "list", label = "Attributs qui donnent une tolérance quand ils changent" },
			{ adv = "LegitAttributes.TrailingGrace", t = "number", min = 0, max = 60, step = 1, label = "Tolérance quand un attribut change (s)" },
			{ adv = "Launchers.AutoGraceOnMover", t = "bool", label = "Tolérance quand un launcher pousse le joueur" },
			{ adv = "Launchers.MoverGrace", t = "number", min = 0, max = 60, step = 1, label = "Tolérance après une propulsion (s)" },
			{ adv = "Launchers.MoverClasses", t = "list", label = "Objets de propulsion reconnus" },
			{ adv = "Launchers.VelocitySpikeThreshold", t = "number", min = 20, max = 2000, step = 10, label = "Vitesse qui signale une propulsion (studs/s)" },
			{ adv = "Launchers.VelocitySpikeGrace", t = "number", min = 0, max = 60, step = 1, label = "Tolérance après cette vitesse (s)" },
			{ adv = "Ragdoll.SkipWhileRagdolled", t = "bool", label = "Ne pas mesurer pendant un ragdoll" },
			{ adv = "Ragdoll.GraceAfter", t = "number", min = 0, max = 60, step = 1, label = "Tolérance après un ragdoll (s)" },
			{ adv = "Arena.SkipTeleport", t = "bool", label = "Arène : ignorer les téléportations" },
			{ adv = "Arena.SkipSpeed", t = "bool", label = "Arène : ignorer la vitesse" },
			{ adv = "Arena.FlyMode", t = "choice", options = { { v = "normal", l = "Normal" }, { v = "relaxed", l = "Tolérant" }, { v = "off", l = "Coupé" } }, label = "Arène : détection du vol" },
			{ adv = "Arena.RelaxedHoverTime", t = "number", min = 1, max = 60, step = 1, label = "Arène tolérante : temps max en l'air (s)" },
			{ adv = "Arena.RelaxedAscentFlat", t = "number", min = 0, max = 500, step = 5, label = "Arène tolérante : montée permise (studs)" },
			{ adv = "MovementBoost.Enabled", t = "bool", label = "PvP : tenir compte du slide / double saut" },
			{ adv = "MovementBoost.SlideSpeed", t = "number", min = 0, max = 300, step = 1, label = "PvP : vitesse du slide" },
			{ adv = "MovementBoost.SpeedMargin", t = "number", min = 0, max = 100, step = 1, label = "PvP : marge de vitesse" },
			{ adv = "MovementBoost.SwitchGrace", t = "number", min = 0, max = 60, step = 1, label = "PvP : tolérance au changement (s)" },
			{ adv = "ServerMoves.Enabled", t = "bool", label = "Reconnaître les téléportations faites par le serveur" },
			{ adv = "Floor.Enabled", t = "bool", label = "Tapis roulants / plateformes : vitesse du sol ajoutée" },
			{ adv = "Floor.Memory", t = "number", min = 0, max = 10, step = 0.5, label = "Mémoire de la vitesse du sol (s)" },
			{ adv = "Zipline.Prefix", t = "text", max = 40, label = "Tyrolienne : début du nom du modèle" },
			{ adv = "Zipline.Rope", t = "text", max = 40, label = "Tyrolienne : nom de la corde" },
			{ adv = "Zipline.MaxDist", t = "number", min = 2, max = 100, step = 1, label = "Tyrolienne : distance max à la corde (studs)" },
			{ adv = "ScaleHoverWithGravity", t = "bool", label = "Gravité basse (Admin Abuse) : plus de temps en l'air" },
			{ adv = "GlobalToleranceTrail", t = "number", min = 0, max = 60, step = 1, label = "Tolérance après une météo Admin Abuse (s)" },
		} },

	{ id = "tolerances", title = "⏳ TOLÉRANCES",
		intro = "Secondes pendant lesquelles on ne mesure pas après un événement normal.",
		fields = {
			{ adv = "Grace.SpawnSeconds", t = "number", min = 0, max = 120, step = 1, label = "Après l'apparition" },
			{ adv = "Grace.DeathSeconds", t = "number", min = 0, max = 60, step = 1, label = "Après une mort" },
			{ adv = "Grace.ProductPurchaseSeconds", t = "number", min = 0, max = 60, step = 1, label = "Après un achat Robux" },
			{ adv = "Grace.AdminActionSeconds", t = "number", min = 0, max = 60, step = 1, label = "Après une action admin (GO TO, BRING…)" },
			{ adv = "Grace.RemoteHookSeconds", t = "number", min = 0, max = 60, step = 1, label = "Après un remote listé ci-dessous" },
			{ adv = "Grace.MinDelayBetweenRemoteGraces", t = "number", min = 0, max = 120, step = 1, label = "Écart min entre deux tolérances de remote" },
			{ adv = "Grace.LandingSeconds", t = "number", min = 0, max = 10, step = 0.1, label = "Après un atterrissage" },
			{ adv = "Hooks.HookAdminAction", t = "bool", label = "Tolérance sur les actions du panel admin" },
			{ adv = "Hooks.HookProductPurchases", t = "bool", label = "Tolérance sur les achats Robux" },
			{ adv = "Hooks.RemoteGraceNames", t = "list", label = "Remotes qui donnent une tolérance (noms)" },
		} },

	{ id = "exceptions", title = "👮 EXCEPTIONS",
		intro = "La liste des admins du panel anti-cheat reste dans le fichier ANTICHEAT_CONFIG (sécurité : un admin ne peut pas en ajouter un autre depuis le jeu).",
		fields = {
			{ adv = "Whitelist.UserIds", t = "numlist", label = "Comptes JAMAIS analysés (UserId)", desc = "Séparés par des virgules. Ex : un compte de test." },
		} },
}

--  Index des réglages + nettoyage d'une valeur selon son type.
local FIELDS = {}
for _, sec in ipairs(SCHEMA) do
	for _, fld in ipairs(sec.fields) do
		if fld.adv then fld.id = "adv:" .. fld.adv end
		FIELDS[fld.id] = fld
	end
end

local function splitList(v)
	if type(v) == "table" then return v end
	if type(v) ~= "string" then return nil end
	local out = {}
	for part in string.gmatch(v, "[^,\n]+") do
		local p = part:gsub("^%s+", ""):gsub("%s+$", "")
		if p ~= "" then table.insert(out, p) end
	end
	return out
end

local function cleanValue(fld, v)
	local t = fld.t
	if t == "bool" then
		return (type(v) == "boolean") and v or nil
	elseif t == "number" then
		v = tonumber(v)
		if not v or v ~= v then return nil end
		v = math.clamp(v, fld.min or -1e9, fld.max or 1e9)
		local step = fld.step or 1
		if step >= 1 and step == math.floor(step) then v = math.floor(v + 0.5)
		else v = math.floor(v * 100 + 0.5) / 100 end
		return v
	elseif t == "choice" then
		for _, o in ipairs(fld.options or {}) do if o.v == v then return v end end
		return nil
	elseif t == "text" then
		if type(v) ~= "string" then return nil end
		return (v:gsub("[<>]", "")):sub(1, fld.max or 200)
	elseif t == "list" or t == "numlist" then
		local l = splitList(v)
		if type(l) ~= "table" then return nil end
		local out = {}
		for _, x in ipairs(l) do
			if #out >= 60 then break end
			if t == "numlist" then
				local n = tonumber(x)
				if n then table.insert(out, math.floor(n)) end
			elseif type(x) == "string" or type(x) == "number" then
				table.insert(out, tostring(x):sub(1, 60))
			end
		end
		return out
	elseif t == "map" then
		local out = {}
		if type(v) == "string" then
			for part in string.gmatch(v, "[^,\n]+") do
				local k, n = part:match("^%s*(.-)%s*=%s*([%d%.]+)%s*$")
				if k and k ~= "" and tonumber(n) then out[k:sub(1, 60)] = tonumber(n) end
			end
		elseif type(v) == "table" then
			for k, n in pairs(v) do
				if type(k) == "string" and tonumber(n) then out[k:sub(1, 60)] = tonumber(n) end
			end
		else
			return nil
		end
		return out
	end
	return nil
end

local function getAt(t, path)
	for _, k in ipairs(path) do
		if type(t) ~= "table" then return nil end
		t = t[k]
	end
	return t
end
local function setAt(t, path, v)
	for i = 1, #path - 1 do
		if type(t[path[i]]) ~= "table" then t[path[i]] = {} end
		t = t[path[i]]
	end
	t[path[#path]] = v
end
local function deepCopyU(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = deepCopyU(v) end
	return o
end

local function sanitizeConfig(raw)
	local out = {}
	for k, v in pairs(DEFAULTS) do out[k] = v end
	--  Aucune config enregistrée (1er lancement) : on passe quand même par la
	--  migration V4 plus bas, pour démarrer avec les bons réglages.
	if type(raw) ~= "table" then raw = {} end

	if raw.mode == "ban" or raw.mode == "ugc" then out.mode = raw.mode end
	if type(raw.shadow)          == "boolean" then out.shadow = raw.shadow end
	if type(raw.shadowCorrect)   == "boolean" then out.shadowCorrect = raw.shadowCorrect end
	if type(raw.notifyOnRestrict) == "boolean" then out.notifyOnRestrict = raw.notifyOnRestrict end
	if type(raw.kickOnRestrict)  == "boolean" then out.kickOnRestrict = raw.kickOnRestrict end
	if type(raw.warningsToRestrict) == "number" then
		out.warningsToRestrict = math.clamp(math.floor(raw.warningsToRestrict), 1, 1000)
	end
	if type(raw.analyzeAdmins) == "boolean" then out.analyzeAdmins = raw.analyzeAdmins end
	if type(raw.silent) == "boolean" then out.silent = raw.silent end
	if type(raw.warningExpiryDays) == "number" and raw.warningExpiryDays == raw.warningExpiryDays then
		out.warningExpiryDays = math.clamp(math.floor(raw.warningExpiryDays), 0, 3650)
	end
	if type(raw.countFrom) == "number" and raw.countFrom == raw.countFrom then
		out.countFrom = math.clamp(math.floor(raw.countFrom), 0, os.time() + 60)
	end

	--  Les seuils restent ordonnés : compter ≤ avertir ≤ sanctionner.
	--  Sans ça, une config incohérente pourrait sanctionner sur des détections
	--  qu'on a par ailleurs décidé de ne pas compter.
	for _, k in ipairs({ "minConfidenceCount", "minConfidenceWarn", "minConfidenceSanction" }) do
		if type(raw[k]) == "number" then
			out[k] = math.clamp(math.floor(raw[k]), 0, 99)
		end
	end
	out.minConfidenceWarn     = math.max(out.minConfidenceWarn, out.minConfidenceCount)
	out.minConfidenceSanction = math.max(out.minConfidenceSanction, out.minConfidenceWarn)
	if type(raw.supportMessage) == "string" and #raw.supportMessage > 0 then
		out.supportMessage = raw.supportMessage:sub(1, 1200)
	end

	--════════════════════════════════════════════════════════════════════
	-- ⚙️ FICHES DE MODE
	--    On repart TOUJOURS d'une copie profonde des valeurs par défaut,
	--    puis on n'écrase que les champs présents ET du bon type. Une
	--    config corrompue, tronquée ou fabriquée par un exploiteur ne peut
	--    donc produire qu'une config valide et douce, jamais un état
	--    bizarre qui bannirait tout le monde.
	--════════════════════════════════════════════════════════════════════
	out.modes = {}
	for modeName, def in pairs(DEFAULTS.modes) do
		local dst = {}
		for k, v in pairs(def) do dst[k] = v end
		local src = (type(raw.modes) == "table") and raw.modes[modeName] or nil
		if type(src) == "table" then
			for k, defVal in pairs(def) do
				local v = src[k]
				if type(defVal) == "boolean" and type(v) == "boolean" then
					dst[k] = v
				elseif type(defVal) == "number" and type(v) == "number" and v == v then
					dst[k] = math.floor(v)
				end
			end
		end
		out.modes[modeName] = dst
	end

	--  Bornes dures. Un « 0 warning avant sanction » sanctionnerait à la
	--  première détection comptée : c'est exactement le faux positif qu'on
	--  passe le reste du script à éviter. Le minimum est donc 1.
	local B = {
		ban = { warningsToPunish = { 1, 1000 }, banDays = { 0, 3650 } },
		ugc = { warningsToPunish = { 1, 1000 }, durationHours = { 0, 8760 } },
		test = { suggestAfterDays = { 1, 90 } },
	}
	for modeName, fields in pairs(B) do
		for field, range in pairs(fields) do
			local v = out.modes[modeName][field]
			out.modes[modeName][field] = math.clamp(math.floor(tonumber(v) or range[1]), range[1], range[2])
		end
	end

	--  🔗 Compat : `warningsToRestrict` reste la source de vérité historique
	--     pour tout le code déjà écrit. On la garde synchronisée avec la
	--     fiche du mode actif, dans les deux sens, pour qu'aucun ancien
	--     appel ne lise une valeur périmée.
	if type(raw.modes) == "table" and type(raw.modes.ugc) == "table"
		and type(raw.modes.ugc.warningsToPunish) == "number" then
		out.warningsToRestrict = out.modes.ugc.warningsToPunish
	else
		out.modes.ugc.warningsToPunish = out.warningsToRestrict
	end

	--════════════════════════════════════════════════════════════════════
	-- 💬 MESSAGES
	--    Les textes sont bornés en longueur et débarrassés de tout ce qui
	--    pourrait servir d'attaque : on ne fait jamais d'interprétation de
	--    balises RichText, et on coupe à 1200 caractères.
	--════════════════════════════════════════════════════════════════════
	out.messages = {}
	for k, v in pairs(DEFAULTS.messages) do out.messages[k] = v end
	if type(raw.messages) == "table" then
		for k, defVal in pairs(DEFAULTS.messages) do
			local v = raw.messages[k]
			if type(defVal) == "string" and type(v) == "string" then
				--  RichText est désactivé côté client, mais on retire quand
				--  même les chevrons : un titre contenant du balisage
				--  s'afficherait bizarrement et n'apporte rien.
				out.messages[k] = (v:gsub("[<>]", "")):sub(1, 1200)
			elseif type(defVal) == "boolean" and type(v) == "boolean" then
				out.messages[k] = v
			elseif type(defVal) == "number" and type(v) == "number" and v == v then
				out.messages[k] = math.floor(v)
			end
		end
	end
	out.messages.nudgeAfterDetections = math.clamp(
		math.floor(tonumber(out.messages.nudgeAfterDetections) or 2), 1, 20)
	out.messages.nudgeCooldown = math.clamp(
		math.floor(tonumber(out.messages.nudgeCooldown) or 10), 0, 300)

	--  Version du fichier ANTICHEAT_CONFIG d'où vient cette config.
	out.fileVersion = tonumber(raw.fileVersion)

	--  ⚙️ Réglages de détection modifiés depuis le panel (seulement ceux de
	--     la liste, chacun vérifié selon son type et ses limites).
	out.advanced = {}
	if type(raw.advanced) == "table" then
		for key, v in pairs(raw.advanced) do
			local fld = FIELDS["adv:" .. tostring(key)]
			if fld then
				local cv = cleanValue(fld, v)
				if cv ~= nil then out.advanced[key] = cv end
			end
		end
	end

	--  Un titre vide casserait l'affichage : on retombe sur le défaut.
	for _, k in ipairs({ "nudgeTitle", "warnTitle", "restrictTitle",
		"shopBlockedTitle", "shopUnverifiedTitle", "banTitle" }) do
		if type(out.messages[k]) ~= "string" or out.messages[k]:gsub("%s", "") == "" then
			out.messages[k] = DEFAULTS.messages[k]
		end
	end

	return out
end

local function loadConfig()
	for attempt = 1, 3 do
		local ok, data = pcall(function() return CONFIG_STORE:GetAsync("config") end)
		if ok then
			local stored = (type(data) == "table") and tonumber(data.fileVersion) or nil
			if ACFILE and stored ~= FILE_VERSION then
				--  📄 Nouvelle VERSION de ANTICHEAT_CONFIG (ou 1er lancement) :
				--     le FICHIER écrase ce que le panel avait enregistré.
				cfg = sanitizeConfig(nil)
				cfg.fileVersion = FILE_VERSION
				pcall(function()
					CONFIG_STORE:UpdateAsync("config", function(old)
						--  Un autre serveur l'a déjà fait : on garde la sienne.
						if type(old) == "table" and tonumber(old.fileVersion) == FILE_VERSION then
							return nil
						end
						return cfg
					end)
				end)
				log(string.format("Réglages pris dans ANTICHEAT_CONFIG (VERSION %d)", FILE_VERSION))
			else
				cfg = sanitizeConfig(data)
			end
			cfgLoaded = true
			log(string.format("Config chargée — mode=%s | shadow=%s | seuil=%d warning(s)",
				cfg.mode, tostring(cfg.shadow), cfg.warningsToRestrict))
			cfgChanged:Fire(cfg)
			return true
		end
		task.wait(0.6 * attempt)
	end
	--  Lecture impossible : on garde les valeurs par défaut, qui sont
	--  volontairement les plus douces (shadow = true, personne n'est puni).
	warn("🚫 [UGCRestrict] Config illisible → valeurs par défaut (shadow actif, aucune sanction)")
	cfgLoaded = false
	return false
end

local function saveConfig(newCfg, byName)
	local clean = sanitizeConfig(newCfg)
	clean.fileVersion = FILE_VERSION
	local ok = pcall(function()
		CONFIG_STORE:SetAsync("config", clean)
	end)
	if not ok then return false, "Écriture DataStore impossible" end

	cfg = clean
	cfgLoaded = true
	cfgChanged:Fire(cfg)

	pcall(function()
		MessagingService:PublishAsync(TOPIC_CONFIG, { cfg = clean, by = byName or "?" })
	end)
	log(string.format("Config enregistrée par %s — mode=%s | shadow=%s",
		tostring(byName), clean.mode, tostring(clean.shadow)))
	return true
end

pcall(function()
	MessagingService:SubscribeAsync(TOPIC_CONFIG, function(msg)
		local d = msg and msg.Data
		if type(d) == "table" and type(d.cfg) == "table" then
			cfg = sanitizeConfig(d.cfg)
			cfgLoaded = true
			cfgChanged:Fire(cfg)
			log("Config synchronisée depuis un autre serveur")
		end
	end)
end)

task.spawn(loadConfig)

--  Relecture périodique : filet si un message de sync se perd.
task.spawn(function()
	while true do
		task.wait(180)
		if not cfgLoaded then loadConfig() end
	end
end)

--════════════════════════════════════════════════════════════════════════════
-- 📖 LECTURE D'UNE FICHE
--════════════════════════════════════════════════════════════════════════════
--  Retourne : record (table) si restreint, false si vérifié non restreint,
--             nil si la lecture a ÉCHOUÉ (cas fail-closed).
local function readRecord(userId, forceFresh)
	local now = os.clock()
	if not forceFresh and cache[userId] ~= nil and (now - (cacheAt[userId] or 0)) < CACHE_TTL then
		return cache[userId]
	end

	for attempt = 1, 3 do
		local ok, data = pcall(function()
			return RESTRICT_STORE:GetAsync("r_" .. userId)
		end)
		if ok then
			local rec = (type(data) == "table" and data.active == true) and data or false

			--  ⏳ PRIVATION TEMPORAIRE (modes.ugc.durationHours > 0)
			--     La date de fin est stockée DANS l'enregistrement au moment
			--     de la sanction, pas relue de la config : si tu changes la
			--     durée plus tard, les sanctions déjà posées gardent la durée
			--     qu'elles avaient — sinon tu prolongerais rétroactivement
			--     des joueurs sans le vouloir.
			if rec and type(rec.until_) == "number" and rec.until_ > 0
				and os.time() >= rec.until_ then
				log(string.format("Privation expirée pour %d → levée automatique", userId))
				rec = false
				--  Écriture au fil de l'eau, sans bloquer la lecture.
				task.spawn(function()
					pcall(function()
						RESTRICT_STORE:UpdateAsync("r_" .. userId, function(old)
							if type(old) ~= "table" then return nil end
							if type(old.until_) ~= "number" or os.time() < old.until_ then
								return nil   -- prolongée entre-temps : on ne touche pas
							end
							old.active     = false
							old.expiredAt  = os.time()
							old.liftedBy   = "auto (durée écoulée)"
							return old
						end)
					end)
					pcall(function() RESTRICT_INDEX:RemoveAsync(tostring(userId)) end)
				end)
			end

			cache[userId]   = rec
			cacheAt[userId] = now
			return rec
		end
		task.wait(0.35 * attempt)
	end

	warn(string.format("🚫 [UGCRestrict] Lecture impossible pour %d (3 tentatives)", userId))
	return nil
end

--════════════════════════════════════════════════════════════════════════════
-- ✍️ ÉCRITURE
--════════════════════════════════════════════════════════════════════════════
local restrictedSetAt = 0
local function applyLocally(userId, rec)
	cache[userId]   = rec or false
	cacheAt[userId] = os.clock()
	--  🤫 Plus d'attribut « UGCRestricted » sur le joueur : il était visible
	--     côté client et grisait le bouton Buy, ce qui révélait la sanction.
	local pl = Players:GetPlayerByUserId(userId)
	if pl and pl:GetAttribute("UGCRestricted") ~= nil then
		pl:SetAttribute("UGCRestricted", nil)
	end
	restrictedSetAt = 0   -- la liste « restreints » des classements est relue
end

local function broadcast(action, userId, rec)
	pcall(function()
		MessagingService:PublishAsync(TOPIC_RESTRICT, {
			action = action, userId = userId, rec = rec,
		})
	end)
end

pcall(function()
	MessagingService:SubscribeAsync(TOPIC_RESTRICT, function(msg)
		local d = msg and msg.Data
		if type(d) ~= "table" or type(d.userId) ~= "number" then return end
		if d.action == "remove" then
			applyLocally(d.userId, false)
		elseif d.action == "add" and type(d.rec) == "table" then
			applyLocally(d.userId, d.rec)
		end
	end)
end)

--════════════════════════════════════════════════════════════════════════════
-- 🚫 API PUBLIQUE
--════════════════════════════════════════════════════════════════════════════
local UGCRestrict = {}

--  ✅ LA fonction que tout le reste du jeu doit appeler.
--     Retourne : blocked (bool), reason (string), record (table|nil)
--     • blocked = true, reason = "restricted"  → sanction en cours
--     • blocked = true, reason = "unverified"  → registre illisible, on refuse
--                                                par sécurité (fail-closed)
--     • blocked = false                        → le joueur peut acheter
function UGCRestrict.CheckPurchase(player)
	if not player then return true, "unverified" end
	local userId = player.UserId

	--  👮 Un admin n'est exempté QUE si tu as désactivé « analyser les admins ».
	--     Quand le réglage est actif (défaut), un admin restreint est bloqué
	--     exactement comme un joueur — sinon la sanction serait décorative.
	if isAdmin(userId) and not cfg.analyzeAdmins then return false end

	local rec = readRecord(userId, false)

	if rec == nil then
		--  🔒 FAIL-CLOSED. On préfère faire patienter un joueur honnête
		--     quelques secondes plutôt que laisser passer une UGC.
		return true, "unverified"
	end

	if rec then
		--  On compte la tentative (écrite en lot plus tard, zéro coût ici).
		pendingTries[userId] = (pendingTries[userId] or 0) + 1
		return true, "restricted", rec
	end

	return false
end

--════════════════════════════════════════════════════════════════════════════
-- 🎁 DONS ET 🔁 REBIRTH
--
--    Deux portes dérobées évidentes du mode « privation d'UGC » :
--      • le tricheur restreint fait acheter l'UGC par un complice et se la
--        fait offrir ;
--      • il fait un rebirth pour blanchir des points obtenus en trichant.
--
--    Ces deux fonctions rendent les interrupteurs `blockGifts` et
--    `blockRebirth` réels au lieu de décoratifs. À toi de les appeler dans
--    ton script de dons et ton script de rebirth :
--
--        if _G.UGCRestrict and _G.UGCRestrict.CheckGift(player) then
--            -- refuser, prévenir, return
--        end
--
--    Elles rendent `true` = BLOQUÉ, comme CheckPurchase, pour que tu n'aies
--    jamais à te demander dans quel sens lire le booléen.
--════════════════════════════════════════════════════════════════════════════
function UGCRestrict.CheckGift(player)
	if not player then return true, "unverified" end
	local m = (type(cfg.modes) == "table") and cfg.modes.ugc or nil
	--  Interrupteur coupé : on ne bloque rien, même un joueur restreint.
	if not (m and m.blockGifts == true) then return false end
	return UGCRestrict.CheckPurchase(player)
end

function UGCRestrict.CheckRebirth(player)
	if not player then return true, "unverified" end
	local m = (type(cfg.modes) == "table") and cfg.modes.ugc or nil
	if not (m and m.blockRebirth == true) then return false end
	return UGCRestrict.CheckPurchase(player)
end

--  Version booléenne simple, pour un affichage.
function UGCRestrict.IsRestricted(userId)
	if isAdmin(userId) and not cfg.analyzeAdmins then return false end
	local rec = readRecord(userId, false)
	return rec ~= nil and rec ~= false
end

function UGCRestrict.Get(userId, fresh)
	local rec = readRecord(userId, fresh == true)
	if rec == nil or rec == false then return nil end
	return rec
end

--  Le joueur a vu le panneau : on le note dans sa fiche (une seule fois).
local function markNoticeShown(userId)
	task.spawn(function()
		pcall(function()
			RESTRICT_STORE:UpdateAsync("r_" .. userId, function(old)
				if type(old) ~= "table" or old.noticeShown == true then return nil end
				old.noticeShown = true
				old.noticeAt = os.time()
				return old
			end)
		end)
		local c = cache[userId]
		if type(c) == "table" then c.noticeShown = true end
	end)
end

--  Envoie le panneau explicatif au joueur.
function UGCRestrict.Notify(player, rec)
	if not player or not player.Parent then return end

	--  💬 Le titre et le corps viennent de la section MESSAGES de la config,
	--     rendus ICI avec les vraies valeurs. Si tu as laissé `restrictBody`
	--     vide dans le panel, on retombe sur `supportMessage` — c'est ce qui
	--     rend la mise à jour indolore pour une config déjà en place.
	local M = (type(cfg.messages) == "table") and cfg.messages or DEFAULTS.messages
	local body = M.restrictBody
	if type(body) ~= "string" or body:gsub("%s", "") == "" then
		body = cfg.supportMessage
	end

	local vars = {
		player     = player.Name,
		--  Type DOMINANT, pas la table de compteurs : sinon un gabarit
		--  contenant {type} afficherait « table: 0x… » au joueur.
		type       = topType(rec and rec.byType or nil),
		warnings   = rec and rec.warnings or nil,
		confidence = rec and rec.confidence or nil,
	}

	pcall(function()
		notifyRemote:FireClient(player, {
			title     = renderTemplate(M.restrictTitle, vars),
			message   = renderTemplate(body, vars),
			at        = rec and rec.at or os.time(),
			reference = player.UserId,
			auto      = rec and rec.auto or false,
			--  Durée restante, si tu as choisi une privation temporaire.
			until_    = rec and rec.until_ or nil,
		})
	end)
end

--  opts = { by, reason, details, warnings, detections, byType, auto }
function UGCRestrict.Add(userId, opts)
	userId = tonumber(userId)
	if not userId then return false, "UserID invalide" end
	if isAdmin(userId) and not cfg.analyzeAdmins then
		return false, "Les admins sont exemptés — décoche « privilège admin » pour les inclure"
	end

	opts = opts or {}
	local existing = readRecord(userId, true)
	if existing then
		return false, "Ce joueur est déjà privé d'UGC"
	end

	local pl = Players:GetPlayerByUserId(userId)
	local name = opts.name
	if not name then
		if pl then
			name = pl.Name
		else
			local okN, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
			name = (okN and n) or ("UserId " .. userId)
		end
	end

	local rec = {
		active     = true,
		userId     = userId,
		name       = name,
		at         = os.time(),
		by         = opts.by or "system",
		auto       = opts.auto == true,
		reason     = opts.reason or "anticheat",
		details    = tostring(opts.details or ""),
		--  Photo des compteurs au moment de la sanction : c'est ce que tu
		--  regardes pour juger un appel. On ne les met plus à jour ensuite,
		--  pour que la fiche reste le reflet exact de ce qui a déclenché.
		warnings   = tonumber(opts.warnings) or 0,
		detections = tonumber(opts.detections) or 0,
		byType     = (type(opts.byType) == "table") and opts.byType or {},
		--  🎯 Le niveau de certitude au moment de la sanction, et les facteurs
		--  qui l'ont produit. C'est ce que tu relis quand un joueur fait appel :
		--  tu sais exactement ce que la machine a « vu », pas seulement qu'elle
		--  a décidé quelque chose.
		confidence = tonumber(opts.confidence) or nil,
		factors    = (type(opts.factors) == "table") and opts.factors or nil,
		--  📝 La raison EXACTE, en clair (type, mesure, position, outil en
		--     main, certitude) et les derniers signaux retenus.
		reasonText = (type(opts.reasonText) == "string" and opts.reasonText ~= "")
			and opts.reasonText:sub(1, 900) or nil,
		signals    = (type(opts.signals) == "table") and opts.signals or nil,
		--  Le joueur a-t-il déjà vu le panneau ? (affiché UNE fois)
		noticeShown = false,
		attempts   = 0,
		lastTryAt  = 0,
	}

	--  ⏳ Durée, prise dans la fiche du mode UGC au moment de la sanction.
	--     0 = définitive jusqu'à levée admin (le défaut).
	--     `opts.hours` permet à un admin de forcer une durée depuis le panel
	--     pour ce joueur-là, sans changer le réglage global.
	do
		local mUgc = (type(cfg.modes) == "table") and cfg.modes.ugc or nil
		local hours = tonumber(opts.hours)
		if hours == nil then hours = (mUgc and mUgc.durationHours) or 0 end
		hours = math.clamp(math.floor(hours), 0, 8760)
		if hours > 0 then
			rec.hours  = hours
			rec.until_ = os.time() + hours * 3600
		end
	end

	local ok = pcall(function()
		RESTRICT_STORE:SetAsync("r_" .. userId, rec)
	end)
	if not ok then return false, "Écriture DataStore impossible, réessaie" end

	pcall(function() RESTRICT_INDEX:SetAsync(tostring(userId), rec.at) end)

	applyLocally(userId, rec)
	broadcast("add", userId, rec)

	warn(string.format("🚫 [UGCRestrict] %s (%d) privé d'UGC — %s | par %s",
		name, userId, rec.details ~= "" and rec.details or rec.reason, rec.by))

	local mUgcN = (type(cfg.modes) == "table") and cfg.modes.ugc or nil
	local notifyNow = (mUgcN ~= nil) and (mUgcN.notifyOnPunish == true) or (cfg.notifyOnRestrict == true)
	if pl and pl.Parent and notifyNow then
		UGCRestrict.Notify(pl, rec)
		markNoticeShown(userId)
	end
	return true, "Privation d'UGC appliquée"
end

function UGCRestrict.Remove(userId, byName)
	userId = tonumber(userId)
	if not userId then return false, "UserID invalide" end

	local ok = pcall(function() RESTRICT_STORE:RemoveAsync("r_" .. userId) end)
	if not ok then return false, "Écriture DataStore impossible, réessaie" end

	pcall(function() RESTRICT_INDEX:RemoveAsync(tostring(userId)) end)
	pcall(function() ATTEMPT_INDEX:RemoveAsync(tostring(userId)) end)

	pendingTries[userId] = nil
	applyLocally(userId, false)
	broadcast("remove", userId, nil)

	log(string.format("Privation levée pour %d par %s", userId, tostring(byName)))
	return true, "Accès UGC rétabli"
end

--  Appelée par l'anti-fly quand un joueur atteint le seuil de warnings.
--  Elle ne fait rien en shadow : c'est ici que la case transverse agit.
function UGCRestrict.AutoRestrict(player, info)
	if not player then return false end
	if cfg.shadow then
		--  On journalise ce qui SERAIT arrivé, sans rien appliquer.
		warn(string.format("🧪 [SHADOW] %s (%d) SERAIT privé d'UGC — %s",
			player.Name, player.UserId, tostring(info and info.details or "")))
		return false, "shadow"
	end
	if cfg.mode ~= "ugc" then return false, "mode" end

	--  🎯 Double sécurité sur la certitude. L'anti-fly a déjà vérifié, mais
	--  une sanction automatique est le pire endroit où faire confiance à un
	--  seul contrôle. Un dossier faible ne peut pas passer par ici.
	local conf = tonumber(info and info.confidence) or 0
	local need = cfg.minConfidenceSanction or 85
	if conf < need then
		warn(string.format(
			"🎯 [UGCRestrict] Sanction refusée pour %s : certitude %d%% < %d%% requis. "
				.. "Le dossier reste visible dans le panel.",
			player.Name, math.floor(conf), need))
		return false, "confidence"
	end

	local ok, msg = UGCRestrict.Add(player.UserId, {
		by         = "AntiFlyTP",
		auto       = true,
		reason     = "anticheat_movement",
		details    = info and info.details or "",
		reasonText = info and info.reasonText or nil,
		signals    = info and info.signals or nil,
		warnings   = info and info.warnings or 0,
		detections = info and info.detections or 0,
		byType     = info and info.byType or {},
		confidence = math.floor(conf),
		factors    = info and info.factors or nil,
		name       = player.Name,
	})

	--  ⚙️ La fiche du mode UGC décide du kick, pas l'ancien réglage global.
	--     `kickOnRestrict` reste accepté comme repli pour ne pas casser une
	--     config déjà enregistrée avant cette mise à jour.
	local mUgc = (type(cfg.modes) == "table") and cfg.modes.ugc or nil
	local doKick = (mUgc and mUgc.kickOnPunish) or (mUgc == nil and cfg.kickOnRestrict)

	if ok and doKick and player.Parent then
		task.delay(6, function()
			if player.Parent then
				--  💬 Texte pris dans la section MESSAGES, rendu avec les
				--     valeurs réelles de ce joueur.
				local M = (type(cfg.messages) == "table") and cfg.messages or DEFAULTS.messages
				local body = M.restrictBody
				if type(body) ~= "string" or body:gsub("%s", "") == "" then
					body = cfg.supportMessage
				end
				player:Kick(renderTemplate(M.restrictTitle, { player = player.Name })
					.. "\n\n"
					.. renderTemplate(body, {
						player     = player.Name,
						warnings   = info and info.warnings or nil,
						confidence = conf,
						type       = topType(info and info.byType or nil),
					}))
			end
		end)
	end
	return ok, msg
end

function UGCRestrict.GetConfig()
	local copy = {}
	for k, v in pairs(cfg) do copy[k] = v end
	copy._loaded = cfgLoaded
	return copy
end

--  Liste paginée pour le panel : les plus récemment restreints d'abord.
function UGCRestrict.List(limit)
	limit = math.clamp(tonumber(limit) or 60, 1, 300)
	local ids = {}
	local ok, pages = pcall(function()
		return RESTRICT_INDEX:GetSortedAsync(false, math.min(limit, 100))
	end)
	if not ok then return nil end

	local guard = 0
	while true do
		guard = guard + 1
		for _, e in ipairs(pages:GetCurrentPage()) do
			local uid = tonumber(e.key)
			if uid then ids[#ids + 1] = uid end
			if #ids >= limit then break end
		end
		if #ids >= limit or pages.IsFinished or guard >= 4 then break end
		if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
	end

	local out = {}
	for _, uid in ipairs(ids) do
		local rec = readRecord(uid, false)
		if rec then out[#out + 1] = rec end
		task.wait(0.03)   -- lissage : on ne martèle pas le DataStore
	end
	return out
end

--  🚫 Ensemble des UserId restreints (index trié, 1 à 4 lectures, mis en
--     cache 20 s). Sert à SORTIR les restreints des classements anti-cheat :
--     un joueur déjà sanctionné n'a plus rien à faire dans la liste des
--     suspects, il est dans l'onglet « 🚫 Restreints ».
local restrictedSet = {}
function UGCRestrict.RestrictedIdSet()
	if os.clock() - restrictedSetAt < 20 then return restrictedSet end
	local set = {}
	local ok, pages = pcall(function() return RESTRICT_INDEX:GetSortedAsync(false, 100) end)
	if ok then
		local guard = 0
		while true do
			guard = guard + 1
			for _, e in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(e.key)
				if uid then set[uid] = true end
			end
			if pages.IsFinished or guard >= 4 then break end
			if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
		end
		--  Ce serveur sait aussi qui il vient de restreindre / libérer.
		for uid, rec in pairs(cache) do
			if rec then set[uid] = true elseif rec == false then set[uid] = nil end
		end
		restrictedSet = set
		restrictedSetAt = os.clock()
	end
	return restrictedSet
end

--  🏷️ Marque chaque entrée d'une liste { {userId=…}, … } : restricted = true/false.
--     Source : le registre des sanctions (index + ce que ce serveur vient de
--     faire), jamais une supposition. Renvoie la liste et le nombre de restreints.
function UGCRestrict.Annotate(entries)
	if type(entries) ~= "table" then return entries, 0 end
	local set = UGCRestrict.RestrictedIdSet()
	local n = 0
	for _, e in ipairs(entries) do
		if type(e) == "table" then
			local uid = tonumber(e.userId)
			local r = (uid ~= nil) and (set[uid] == true)
			--  Une privation temporaire déjà terminée n'est plus « restreint ».
			local c = uid and cache[uid]
			if r and c == false then r = false end
			if r and type(c) == "table" and type(c.until_) == "number" and c.until_ > 0
				and os.time() >= c.until_ then r = false end
			e.restricted = r
			if r then n = n + 1 end
		end
	end
	return entries, n
end

--  Retire les restreints d'une liste { {userId=…}, … }.
function UGCRestrict.FilterOutRestricted(entries)
	if type(entries) ~= "table" then return entries end
	local set = UGCRestrict.RestrictedIdSet()
	local out = {}
	for _, e in ipairs(entries) do
		local uid = type(e) == "table" and tonumber(e.userId) or nil
		if not (uid and set[uid]) then table.insert(out, e) end
	end
	return out
end

--════════════════════════════════════════════════════════════════════════════
-- 📡 FIL DES DÉTECTIONS RÉCENTES
--    Un OrderedDataStore : clé = userId, valeur = horodatage de sa dernière
--    détection retenue. Une seule lecture triée donne « qui a hack
--    récemment », tous serveurs confondus, en une fraction de seconde.
--
--    ⚠️ L'écriture n'a JAMAIS lieu au moment d'une détection. L'anti-fly
--    appelle NoteDetection, qui se contente d'incrémenter un compteur en RAM ;
--    l'écriture part avec le flush groupé, toutes les 90 s.
--════════════════════════════════════════════════════════════════════════════
local feedStore = nil
function ensureFeedStore()
	if feedStore then return feedStore end
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore("AntiCheat_Feed_v1")
	end)
	if ok then feedStore = s end
	return feedStore
end

local pendingFeed = {}   -- [userId] = timestamp

function UGCRestrict.NoteDetection(userId)
	userId = tonumber(userId)
	if not userId then return end
	pendingFeed[userId] = os.time()
end

task.spawn(function()
	while true do
		task.wait(90)
		local s = ensureFeedStore()
		if s then
			for userId, ts in pairs(pendingFeed) do
				pendingFeed[userId] = nil
				pcall(function() s:SetAsync(tostring(userId), ts) end)
				task.wait(0.2)
			end
		end
	end
end)

--════════════════════════════════════════════════════════════════════════════
-- 🏷️ RÉSOLUTION EN LOT — LE CORRECTIF DE LA LENTEUR
--
--  Avant, afficher un classement de 50 joueurs déclenchait :
--    • jusqu'à 50 GetNameFromUserIdAsync, l'un APRÈS l'autre,
--    • puis 50 GetAsync de points + 50 GetAsync de ban, avec une pause de
--      0,05 s entre chaque.
--  Soit plus de 150 allers-retours en file indienne. Dix à trente secondes
--  d'attente, pendant lesquelles l'écran restait vide.
--
--  Ici tout part en parallèle, par vagues de 12, avec un cache qui survit à
--  la fermeture du panel. Le premier affichage tombe en une seconde ou deux,
--  les suivants sont instantanés.
--════════════════════════════════════════════════════════════════════════════
local nameCache   = {}   -- [userId] = name
local pointsCache = {}   -- [userId] = { points, banned, t }
local POINTS_TTL  = 300

local PLAYER_DATA = DataStoreService:GetDataStore("PlayerData_v2")
local BAN_STORE   = DataStoreService:GetDataStore("BannedPlayers")

function UGCRestrict.ResolveBatch(ids)
	local wanted, seen = {}, {}
	for _, raw in ipairs(ids) do
		local id = tonumber(raw)
		if id and not seen[id] then
			seen[id] = true
			wanted[#wanted + 1] = id
		end
		if #wanted >= 60 then break end
	end

	local out = {}
	local now = os.time()
	local todo = {}

	--  Ce qu'on a déjà : on répond tout de suite, sans toucher au réseau.
	for _, id in ipairs(wanted) do
		local entry = { name = nameCache[id] }
		local pl = Players:GetPlayerByUserId(id)
		if pl then
			--  Joueur en ligne : nom et points sont dans la mémoire du serveur.
			--  Zéro requête, et la valeur est plus fraîche que le DataStore.
			entry.name   = pl.Name
			entry.online = true
			entry.banned = false
			local live = pl:GetAttribute("Points")
			if type(live) == "number" then entry.points = live end
			nameCache[id] = pl.Name
		else
			local c = pointsCache[id]
			if c and (now - c.t) < POINTS_TTL then
				entry.points = c.points
				entry.banned = c.banned
			end
		end
		--  Le statut de privation vient du cache déjà tenu par ce module.
		local rec = cache[id]
		if rec ~= nil then entry.restricted = (rec ~= false) end

		out[tostring(id)] = entry
		if not entry.name or (entry.points == nil and not entry.online) then
			todo[#todo + 1] = id
		end
	end

	--  Ce qu'il manque : par vagues de 12, toutes les requêtes d'une vague
	--  partant en même temps.
	local i = 1
	while i <= #todo do
		local batch = {}
		for _ = 1, 12 do
			if i > #todo then break end
			batch[#batch + 1] = todo[i]
			i = i + 1
		end

		local pending = #batch * 2
		for _, id in ipairs(batch) do
			local key = tostring(id)

			task.spawn(function()
				if not nameCache[id] then
					local ok, nm = pcall(function()
						return Players:GetNameFromUserIdAsync(id)
					end)
					if ok and nm then nameCache[id] = nm end
				end
				out[key].name = nameCache[id] or ("UserId " .. id)
				pending = pending - 1
			end)

			task.spawn(function()
				if out[key].points == nil then
					local okP, data = pcall(function() return PLAYER_DATA:GetAsync("p_" .. id) end)
					local pts = (okP and type(data) == "table" and tonumber(data.points)) or nil
					local okB, banInfo = pcall(function() return BAN_STORE:GetAsync(key) end)
					local banned = (okB and banInfo ~= nil) or false
					if pts then
						pointsCache[id] = { points = pts, banned = banned, t = os.time() }
						out[key].points = pts
					end
					out[key].banned = banned
				end
				pending = pending - 1
			end)
		end

		--  On attend la vague avant de lancer la suivante : ça garde la
		--  charge DataStore bornée sans jamais repasser en file indienne.
		local waited = 0
		while pending > 0 and waited < 60 do
			task.wait(0.1)
			waited = waited + 1
		end
	end

	return out
end

_G.UGCRestrict = UGCRestrict
_G.ACConfig = {
	Get = UGCRestrict.GetConfig,
	--  L'anti-fly appelle ça pour savoir s'il doit punir.
	--  Un seul endroit décide, donc aucun risque de désaccord entre scripts.
	ShouldPunish = function() return cfgLoaded and cfg.shadow ~= true end,
	Mode         = function() return cfg.mode end,
	Shadow       = function() return cfg.shadow == true end,
	ShadowCorrect = function() return cfg.shadowCorrect == true end,
	WarningsToRestrict = function() return cfg.warningsToRestrict end,

	--  🤫 Le joueur ne voit rien de ses détections / warnings.
	Silent = function() return cfg.silent ~= false end,
	--  ⏳ Durée de vie d'un warning (jours, 0 = jamais).
	WarningExpiryDays = function() return tonumber(cfg.warningExpiryDays) or 30 end,
	CountFrom = function() return tonumber(cfg.countFrom) or 0 end,
	--  🛒 Le panneau ne réapparaît que s'il pourrait se payer l'UGC.
	RevealOnlyWhenAffordable = function()
		local m = (type(cfg.modes) == "table") and cfg.modes.ugc or nil
		if m == nil or m.revealOnlyWhenAffordable == nil then return true end
		return m.revealOnlyWhenAffordable == true
	end,

	--  👮 true = les admins sont analysés comme n'importe qui.
	AnalyzeAdmins = function() return cfg.analyzeAdmins == true end,
	IsAdmin       = function(userId) return isAdmin(userId) end,

	--  🎯 Seuils de certitude lus par l'anti-fly à chaque détection.
	MinConfidenceCount    = function() return cfg.minConfidenceCount or 55 end,
	MinConfidenceWarn     = function() return cfg.minConfidenceWarn or 70 end,
	MinConfidenceSanction = function() return cfg.minConfidenceSanction or 85 end,

	--════════════════════════════════════════════════════════════════════
	-- ⚙️ FICHE DU MODE
	--    ModeCfg()          → la fiche du mode ACTIF (ban ou ugc)
	--    ModeCfg("test")    → la fiche du shadow
	--    ModeCfg("ban")     → la fiche du mode ban, même s'il n'est pas actif
	--
	--    Toujours une table valide, jamais nil : les appelants n'ont pas à
	--    se protéger.
	--════════════════════════════════════════════════════════════════════
	ModeCfg = function(which)
		local name = which or cfg.mode or "ugc"
		local m = (type(cfg.modes) == "table") and cfg.modes[name] or nil
		if type(m) ~= "table" then m = DEFAULTS.modes[name] or DEFAULTS.modes.ugc end
		return m
	end,

	--  Combien de warnings avant la sanction, pour le mode actif.
	--  Un seul endroit décide, donc le panel, l'anti-fly et le shop
	--  affichent forcément le même chiffre.
	WarningsToPunish = function()
		local m = (type(cfg.modes) == "table") and cfg.modes[cfg.mode or "ugc"] or nil
		return (m and m.warningsToPunish)
			or cfg.warningsToRestrict
			or DEFAULTS.warningsToRestrict
	end,

	--════════════════════════════════════════════════════════════════════
	-- 💬 MOTEUR DE MESSAGES
	--
	--    Msg("warnTitle", { warnings = 2, max = 3, type = "FLY_STATE" })
	--      → "🚨 Warning 2/3"
	--
	--    Toute la substitution est faite ICI, côté serveur, à partir de
	--    valeurs que le serveur possède déjà. Le client ne reçoit qu'un
	--    texte fini : il n'y a aucun gabarit à interpréter côté joueur,
	--    donc aucune surface d'injection.
	--════════════════════════════════════════════════════════════════════
	Msg = function(key, vars)
		local M = (type(cfg.messages) == "table") and cfg.messages or DEFAULTS.messages
		local tpl = M[key]
		if type(tpl) ~= "string" or tpl == "" then
			tpl = DEFAULTS.messages[key] or ""
		end
		return renderTemplate(tpl, vars)
	end,

	--  Les drapeaux de la section messages (activation, cadence, secret).
	MsgFlag = function(key)
		local M = (type(cfg.messages) == "table") and cfg.messages or DEFAULTS.messages
		local v = M[key]
		if v == nil then v = DEFAULTS.messages[key] end
		return v
	end,
}

--════════════════════════════════════════════════════════════════════════════
-- 🔁 FLUSH DES TENTATIVES D'ACHAT
--    Compté en RAM à chaque clic bloqué, écrit toutes les 90 s. Zéro requête
--    DataStore sur le chemin d'un achat : le joueur ne sent aucune latence.
--════════════════════════════════════════════════════════════════════════════
task.spawn(function()
	while true do
		task.wait(90)
		for userId, n in pairs(pendingTries) do
			if n > 0 then
				pendingTries[userId] = nil
				task.spawn(function()
					local newTotal
					pcall(function()
						newTotal = RESTRICT_STORE:UpdateAsync("r_" .. userId, function(old)
							if type(old) ~= "table" then return nil end
							old.attempts  = (old.attempts or 0) + n
							old.lastTryAt = os.time()
							return old
						end)
					end)
					if newTotal then
						cache[userId] = newTotal
						pcall(function()
							ATTEMPT_INDEX:SetAsync(tostring(userId), math.floor(newTotal.attempts or 0))
						end)
					end
				end)
				task.wait(0.25)
			end
		end
	end
end)

--════════════════════════════════════════════════════════════════════════════
-- 👤 CYCLE DE VIE JOUEUR
--════════════════════════════════════════════════════════════════════════════
Players.PlayerAdded:Connect(function(player)
	local userId = player.UserId
	task.spawn(function()
		--  On lit AVANT que le shop puisse être ouvert. Si la lecture rate,
		--  cache reste nil → CheckPurchase refusera, ce qui est le bon défaut.
		local rec = readRecord(userId, true)
		if not player.Parent then return end
		if not (rec and rec ~= false) then return end

		local mUgc = (type(cfg.modes) == "table") and cfg.modes.ugc or nil
		local remind = (mUgc ~= nil) and (mUgc.remindOnJoin == true)
		local notifyOn = (mUgc == nil) or (mUgc.notifyOnPunish == true)
		--  Panneau affiché UNE fois : s'il n'était pas en jeu au moment de la
		--  sanction (sanction manuelle hors ligne, déconnexion juste avant),
		--  il le voit à sa prochaine connexion, puis plus jamais au join.
		local firstTime = notifyOn and rec.noticeShown ~= true
		if remind or firstTime then
			task.wait(6)
			if player.Parent then
				UGCRestrict.Notify(player, rec)
				if firstTime then markNoticeShown(userId) end
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	--  On garde le cache un moment : reconnexion rapide = pas de relecture.
	task.delay(180, function()
		if not Players:GetPlayerByUserId(userId) then
			cache[userId]   = nil
			cacheAt[userId] = nil
		end
	end)
end)

--════════════════════════════════════════════════════════════════════════════
-- 🔒 FILET 2 — L'ESCROW UGC
--    On enveloppe _G.UGCEscrow.CanBuy dès qu'il apparaît. Aucun fichier à
--    modifier de ton côté : si l'escrow est là, il refuse aussi.
--════════════════════════════════════════════════════════════════════════════
task.spawn(function()
	for _ = 1, 60 do
		if _G.UGCEscrow and type(_G.UGCEscrow.CanBuy) == "function"
			and not _G.UGCEscrow.__ugcRestrictWrapped then

			local originalCanBuy = _G.UGCEscrow.CanBuy
			_G.UGCEscrow.CanBuy = function(player, assetId, ...)
				local blocked, why = UGCRestrict.CheckPurchase(player)
				if blocked then
					return false, (why == "restricted") and "ugc_restricted" or "ugc_unverified"
				end
				return originalCanBuy(player, assetId, ...)
			end
			_G.UGCEscrow.__ugcRestrictWrapped = true
			log("Filet posé sur UGCEscrow.CanBuy")
			return
		end
		task.wait(1)
	end
	log("UGCEscrow pas trouvé — le blocage repose sur le patch du script de points")
end)

--════════════════════════════════════════════════════════════════════════════
-- 🔒 FILET 3 — DERNIER RECOURS
--    Si une UGC arrive quand même sur un compte restreint, on ne peut plus
--    l'empêcher (Roblox l'a déjà livrée) mais on le TRACE en gros, avec le
--    nom du joueur, pour que tu le voies immédiatement dans tes logs.
--════════════════════════════════════════════════════════════════════════════
game:GetService("MarketplaceService").PromptPurchaseFinished:Connect(function(player, assetId, bought)
	if not bought or not player then return end
	task.spawn(function()
		local rec = readRecord(player.UserId, false)
		if rec then
			warn(string.format(
				"🚨🚨 [UGCRestrict] FUITE — %s (%d) a reçu l'asset %d ALORS QU'IL EST RESTREINT.\n"
					.. "    Un chemin d'achat n'est pas protégé. Vérifie que le patch du script "
					.. "de points est bien collé.",
				player.Name, player.UserId, assetId))
			pcall(function()
				RESTRICT_STORE:UpdateAsync("r_" .. player.UserId, function(old)
					if type(old) ~= "table" then return nil end
					old.leaks = (old.leaks or 0) + 1
					old.lastLeakAsset = assetId
					old.lastLeakAt = os.time()
					return old
				end)
			end)
		end
	end)
end)

--════════════════════════════════════════════════════════════════════════════
-- 🖥️ REMOTES ADMIN
--════════════════════════════════════════════════════════════════════════════
--  🩹 LE BUG DU « TU VAS TROP VITE ».
--
--     Avant, un SEUL compteur servait pour toutes les actions. Quand tu
--     changeais un réglage, le panel enregistrait (action 1) puis relisait
--     l'état dans la foulée (action 2) — et la relecture tombait dans le
--     cooldown de l'enregistrement. Le panel affichait un échec, se marquait
--     « en panne » et ne réessayait plus : il fallait quitter et revenir.
--
--     Trois corrections :
--       1. Un compteur PAR TYPE d'action. Enregistrer ne bloque plus lire.
--       2. La liste est mise en cache 12 s côté serveur, donc relire juste
--          après une écriture ne coûte rien et n'a plus besoin d'être bridée.
--       3. Quand une limite s'applique quand même, on répond `throttled`
--          au lieu de `ok = false` — le panel sait alors que ce n'est pas
--          une panne et réessaie tout seul.
local rateLimit = {}
local function rateOk(userId, bucket, seconds)
	local key = tostring(userId) .. "|" .. bucket
	local now = os.clock()
	local last = rateLimit[key] or 0
	if now - last < (seconds or 1) then return false end
	rateLimit[key] = now
	return true
end

local listCache = { entries = nil, at = 0, err = nil }
local LIST_TTL  = 12

local function getListCached(force)
	local now = os.clock()
	if not force and listCache.entries and (now - listCache.at) < LIST_TTL then
		return listCache.entries, listCache.err
	end
	local list = UGCRestrict.List(300)
	listCache.at = now
	if list == nil then
		--  On garde l'ancienne liste plutôt que de vider l'écran : une lecture
		--  ratée ne doit pas faire croire à l'admin que le registre est vide.
		listCache.err = "Registre momentanément illisible — affichage de la dernière liste connue"
		listCache.entries = listCache.entries or {}
	else
		listCache.entries = list
		listCache.err = nil
	end
	return listCache.entries, listCache.err
end

--  Invalidation immédiate après toute écriture, pour que le panel voie son
--  changement tout de suite au lieu d'attendre l'expiration du cache.
local function invalidateList() listCache.at = 0 end

adminGet.OnServerInvoke = function(player, wantList, forceFresh)
	if not isAdmin(player.UserId) then return { ok = false, msg = "Accès refusé" } end

	local res = {
		ok     = true,
		config = UGCRestrict.GetConfig(),
		admins = {},
		mode   = cfg.mode,
	}
	for _, id in ipairs(ADMIN_IDS) do
		table.insert(res.admins, { userId = id })
	end

	if wantList ~= false then
		--  Le rafraîchissement forcé (bouton 🔄) est le seul chemin bridé, et
		--  seulement pour éviter de marteler le DataStore en maintenant le
		--  doigt appuyé. Une lecture normale passe toujours.
		local force = forceFresh == true
		if force and not rateOk(player.UserId, "listforce", 3) then
			force = false
		end
		local entries, err = getListCached(force)
		res.entries   = entries or {}
		res.listError = err
	else
		res.entries = {}
	end
	return res
end


--════════════════════════════════════════════════════════════════════════════
-- 🛡️ ÉCRAN ANTI-CHEAT DU PANEL : accueil, fil, joueurs, fiches, réglages
--════════════════════════════════════════════════════════════════════════════
local AC_ACTIONS = {}

local function AF() return _G.AntiFlyTP end
local function threshold()
	local m = (type(cfg.modes) == "table") and cfg.modes[cfg.mode or "ugc"] or nil
	return (m and m.warningsToPunish) or cfg.warningsToRestrict or 1
end
local function shallow(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end

--  Événements du journal, copiés et marqués (restreint / en ligne).
local function feedEvents(n)
	local af = AF()
	local list = (af and af.GetFeedLog) and af.GetFeedLog(n or 300) or {}
	local set = UGCRestrict.RestrictedIdSet()
	local out = {}
	for _, ev in ipairs(list) do
		if type(ev) == "table" then
			local e = shallow(ev)
			e.restricted = set[tonumber(e.uid) or 0] == true
			e.online = Players:GetPlayerByUserId(tonumber(e.uid) or 0) ~= nil
			table.insert(out, e)
		end
	end
	return out
end

--  Réglages + valeurs actuelles + valeurs du fichier, section par section.
AC_ACTIONS.schema = function()
	local af = AF()
	local adv = (type(cfg.advanced) == "table") and cfg.advanced or {}
	local out = {}
	for _, sec in ipairs(SCHEMA) do
		local s2 = { id = sec.id, title = sec.title, intro = sec.intro, open = sec.open, fields = {} }
		for _, fld in ipairs(sec.fields) do
			local f2 = shallow(fld)
			if fld.adv then
				local def = (af and af.AdvancedDefault) and af.AdvancedDefault(fld.adv) or nil
				f2.default = def
				if adv[fld.adv] ~= nil then f2.value = adv[fld.adv] else f2.value = def end
			else
				f2.default = getAt(DEFAULTS, fld.path)
				f2.value = getAt(cfg, fld.path)
				if f2.value == nil then f2.value = f2.default end
			end
			table.insert(s2.fields, f2)
		end
		table.insert(out, s2)
	end
	return { ok = true, sections = out, preset = adv.Preset or (af and af.AdvancedDefault and af.AdvancedDefault("Preset")),
		fileVersion = FILE_VERSION, loaded = cfgLoaded }
end

--  Enregistre des réglages : { values = { [id] = valeur }, reset = { id, … } }
AC_ACTIONS.setvalues = function(player, payload)
	local newCfg = deepCopyU(cfg)
	newCfg.advanced = (type(newCfg.advanced) == "table") and newCfg.advanced or {}
	local n, bad = 0, {}
	for id, v in pairs(type(payload.values) == "table" and payload.values or {}) do
		local fld = FIELDS[id]
		local cv = fld and cleanValue(fld, v)
		if cv ~= nil then
			if fld.adv then newCfg.advanced[fld.adv] = cv else setAt(newCfg, fld.path, cv) end
			if id == "ugc.warn" then newCfg.warningsToRestrict = cv end
			n = n + 1
		else
			table.insert(bad, tostring(fld and fld.label or id))
		end
	end
	for _, id in ipairs(type(payload.reset) == "table" and payload.reset or {}) do
		local fld = FIELDS[id]
		if fld then
			if fld.adv then newCfg.advanced[fld.adv] = nil
			else setAt(newCfg, fld.path, deepCopyU(getAt(DEFAULTS, fld.path))) end
			if id == "ugc.warn" then newCfg.warningsToRestrict = getAt(DEFAULTS, fld.path) end
			n = n + 1
		end
	end
	--  🕛 « Ignorer les anciens warnings » (à l'activation des sanctions)
	if payload.countFromNow == true then
		newCfg.countFrom = os.time()
		n = n + 1
		local af = AF()
		if af and af.ResetRealRanks then task.spawn(function() pcall(af.ResetRealRanks) end) end
	end
	if n == 0 then
		return { ok = false, msg = (#bad > 0) and ("Valeur refusée : " .. table.concat(bad, ", ")) or "Rien à enregistrer" }
	end
	local ok, msg = saveConfig(newCfg, player.Name)
	return { ok = ok, msg = ok and string.format("✅ %d réglage(s) enregistré(s) sur tous les serveurs", n) or msg,
		refused = bad }
end

--  Page d'accueil : l'essentiel en un coup d'œil.
AC_ACTIONS.home = function()
	local now = os.time()
	local evs = feedEvents(300)
	local det, warns, sanc, players = 0, 0, 0, {}
	for _, e in ipairs(evs) do
		if (e.t or 0) >= now - 86400 then
			if e.kind == "detection" then det = det + 1 ; players[e.uid] = true
			elseif e.kind == "warning" then warns = warns + 1
			elseif e.kind == "sanction" then sanc = sanc + 1 end
		end
	end
	local nP = 0 for _ in pairs(players) do nP = nP + 1 end
	local nR = 0 for _ in pairs(UGCRestrict.RestrictedIdSet()) do nR = nR + 1 end
	local recent = {}
	--  assez d'événements pour regrouper les 5 derniers joueurs côté panel
	for i = 1, math.min(80, #evs) do recent[i] = evs[i] end
	local m = (type(cfg.modes) == "table") and cfg.modes.ugc or {}
	return { ok = true, recent = recent,
		stats = { det24 = det, players24 = nP, warn24 = warns, sanc24 = sanc, restricted = nR },
		state = { mode = cfg.mode, shadow = cfg.shadow == true, silent = cfg.silent ~= false,
			countFrom = tonumber(cfg.countFrom) or 0,
			threshold = threshold(), expiry = cfg.warningExpiryDays, reveal = m.revealOnlyWhenAffordable ~= false,
			loaded = cfgLoaded, fileVersion = FILE_VERSION } }
end

--  Fil récent (tout le journal, le panel filtre).
AC_ACTIONS.feedlog = function(_, payload)
	return { ok = true, events = feedEvents(tonumber(payload.limit) or 300), threshold = threshold() }
end

--  Liste des joueurs à surveiller : classements + journal, fusionnés.
AC_ACTIONS.candidates = function(_, payload)
	local n = math.clamp(tonumber(payload.limit) or 100, 10, 200)
	local af = AF()
	local map, now = {}, os.time()
	local function get(uid)
		uid = tonumber(uid)
		if not uid then return nil end
		map[uid] = map[uid] or { userId = uid, det = 0, warn = 0, det24 = 0 }
		return map[uid]
	end
	if af and af.GetCandidates then
		local ok, c = pcall(af.GetCandidates, n)
		if ok and type(c) == "table" then
			for _, e in ipairs(c.det or {}) do local m = get(e.userId) ; if m then m.det = tonumber(e.value) or 0 end end
			local wl = cfg.shadow and c.warnShadow or c.warn
			for _, e in ipairs(wl or {}) do local m = get(e.userId) ; if m then m.warn = tonumber(e.value) or 0 end end
		end
	end
	for _, e in ipairs(feedEvents(300)) do
		local m = get(e.uid)
		if m then
			m.name = m.name or e.name
			if (e.t or 0) > (m.lastAt or 0) and e.kind == "detection" then
				m.lastAt, m.lastType, m.lastDetail = e.t, e.type, e.details
			end
			if e.kind == "detection" and (e.t or 0) >= now - 86400 then m.det24 = m.det24 + 1 end
		end
	end
	local list = {}
	for _, m in pairs(map) do table.insert(list, m) end
	UGCRestrict.Annotate(list)
	for _, m in ipairs(list) do m.online = Players:GetPlayerByUserId(m.userId) ~= nil end
	return { ok = true, entries = list, threshold = threshold() }
end

--  Détail de plusieurs joueurs (par paquets de 12) : warnings exacts,
--  certitude, dernier signal, points, raison de la sanction.
AC_ACTIONS.file = function(_, payload)
	local ids = {}
	for _, v in ipairs(type(payload.ids) == "table" and payload.ids or {}) do
		local n = tonumber(v)
		if n and #ids < 12 then table.insert(ids, n) end
	end
	local af = AF()
	local res = UGCRestrict.ResolveBatch(ids)
	local set = UGCRestrict.RestrictedIdSet()
	local out = {}
	for _, uid in ipairs(ids) do
		local r = res[tostring(uid)] or {}
		local e = { userId = uid, name = r.name, points = r.points, online = r.online == true,
			restricted = set[uid] == true }
		local okF, fl = false, nil
		if af and af.GetPlayerFile then okF, fl = pcall(af.GetPlayerFile, uid) end
		if okF and type(fl) == "table" then
			e.warnings = fl.warnings
			local hist = {}
			for i = #(fl.warnHistory or {}), math.max(1, #(fl.warnHistory or {}) - 4), -1 do
				local h = fl.warnHistory[i]
				if h then table.insert(hist, { t = h.t, type = h.type, details = h.details }) end
			end
			e.warnHistory = hist
			local st = fl.stats
			if type(st) == "table" then
				e.total, e.ignored = st.total or 0, st.detIgnored or 0
				e.confAvg = ((st.confCount or 0) > 0) and math.floor(st.confSum / st.confCount) or 0
				e.confMax = st.confMax or 0
				e.detByType = st.detByType
				e.lastAt, e.lastType, e.lastDetail, e.lastCtx = st.lastAt, st.lastType, st.lastDetail, st.lastCtx
				e.firstSeen = st.firstSeen
			end
		end
		if e.restricted then
			local rec = readRecord(uid, false)
			if type(rec) == "table" then
				local why = rec.reasonText or rec.details or rec.reason or ""
				e.restrictWhy = tostring(why):match("^[^\n]*") or tostring(why)
				e.restrictAt, e.restrictBy, e.restrictAuto = rec.at, rec.by, rec.auto == true
			end
		end
		table.insert(out, e)
	end
	return { ok = true, files = out, threshold = threshold() }
end

adminAction.OnServerInvoke = function(player, action, payload)
	if not isAdmin(player.UserId) then return { ok = false, msg = "Accès refusé" } end
	if type(action) ~= "string" then return { ok = false, msg = "Requête invalide" } end

	--  Un compteur par action. Régler un interrupteur puis relire l'état ne
	--  se gêne plus. Et quand une limite s'applique, on renvoie `throttled` :
	--  le panel réessaie tout seul au lieu de se croire cassé.
	local COOLDOWN = {
		lookup = 0.5, add = 0.8, remove = 0.8,
		clearstats = 0.8, setconfig = 0.35, reload = 2,
		schema = 0.4, setvalues = 0.8, home = 0.8, feedlog = 0.8,
		candidates = 1, file = 0.15,
	}
	if not rateOk(player.UserId, action, COOLDOWN[action] or 0.5) then
		return { throttled = true, msg = nil }
	end

	payload = (type(payload) == "table") and payload or {}
	local byName = player.Name

	if AC_ACTIONS[action] then
		local ok, res = pcall(AC_ACTIONS[action], player, payload)
		if ok then return res end
		warn("🚫 [UGCRestrict] action " .. action .. " : " .. tostring(res))
		return { ok = false, msg = "Erreur serveur (" .. action .. ")" }
	end

	----------------------------------------------------------------
	if action == "lookup" then
		local target = payload.target
		local userId
		if type(target) == "number" then
			userId = target
		elseif type(target) == "string" then
			userId = tonumber(target)
			if not userId then
				local pl = Players:FindFirstChild(target)
				if pl then
					userId = pl.UserId
				else
					local ok, id = pcall(function()
						return Players:GetUserIdFromNameAsync(target)
					end)
					if ok then userId = id end
				end
			end
		end
		if not userId then return { ok = false, msg = "Joueur introuvable" } end

		local pl = Players:GetPlayerByUserId(userId)
		local name = pl and pl.Name
		if not name then
			local okN, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
			name = (okN and n) or ("UserId " .. userId)
		end

		local rec = readRecord(userId, true)
		return {
			ok       = true,
			userId   = userId,
			name     = name,
			online   = pl ~= nil,
			isAdmin  = isAdmin(userId),
			record   = (rec and rec ~= false) and rec or nil,
			readFail = (rec == nil),
			--  Compteurs LIVE de l'anti-fly sur CE serveur, pour juger avant
			--  de restreindre à la main.
			live     = (_G.AntiFlyTP and _G.AntiFlyTP.GetTestPlayer)
				and select(2, pcall(function() return _G.AntiFlyTP.GetTestPlayer(userId) end))
				or nil,
			--  Cumul tous serveurs. Une seule lecture, et seulement quand tu
			--  ouvres une fiche — jamais pour remplir une liste.
			persisted = (payload.deep ~= false and _G.AntiFlyTP and _G.AntiFlyTP.GetTestPlayerPersisted)
				and select(2, pcall(function()
					return _G.AntiFlyTP.GetTestPlayerPersisted(userId)
				end))
				or nil,
			--  🆕 Warnings actifs exacts + son historique dans le journal partagé
			file = (_G.AntiFlyTP and _G.AntiFlyTP.GetPlayerFile)
				and select(2, pcall(_G.AntiFlyTP.GetPlayerFile, userId)) or nil,
			events = (function()
				local out = {}
				for _, e in ipairs(feedEvents(300)) do
					if tonumber(e.uid) == userId then
						table.insert(out, e)
						if #out >= 30 then break end
					end
				end
				return out
			end)(),
			threshold = threshold(),
		}

		----------------------------------------------------------------
	elseif action == "add" then
		local userId = tonumber(payload.userId)
		if not userId then return { ok = false, msg = "UserID invalide" } end
		local ok, msg = UGCRestrict.Add(userId, {
			by      = byName,
			auto    = false,
			reason  = "admin",
			details = tostring(payload.note or "Privation manuelle depuis le panel"),
		})
		if ok then
			invalidateList()
			if AF() and AF().FeedPush then
				local nm = nil
				pcall(function() nm = Players:GetNameFromUserIdAsync(userId) end)
				AF().FeedPush({ kind = "manual", uid = userId, name = nm, by = byName,
					details = "Restreint à la main par " .. byName .. " — " .. tostring(payload.note or "") })
			end
		end
		return { ok = ok, msg = msg }

		----------------------------------------------------------------
	elseif action == "remove" then
		local userId = tonumber(payload.userId)
		if not userId then return { ok = false, msg = "UserID invalide" } end
		local ok, msg = UGCRestrict.Remove(userId, byName)
		if ok then
			invalidateList()
			if AF() and AF().FeedPush then
				local nm = nil
				pcall(function() nm = Players:GetNameFromUserIdAsync(userId) end)
				AF().FeedPush({ kind = "lift", uid = userId, name = nm, by = byName,
					details = "Sanction levée par " .. byName })
			end
		end
		return { ok = ok, msg = msg }

		----------------------------------------------------------------
	elseif action == "clearstats" then
		--  Remet à zéro les compteurs de détection de l'anti-fly pour ce
		--  joueur, sans toucher à la privation elle-même.
		local userId = tonumber(payload.userId)
		if not userId then return { ok = false, msg = "UserID invalide" } end
		if _G.AntiFlyTP then
			pcall(function()
				if _G.AntiFlyTP.ClearTestPlayer then _G.AntiFlyTP.ClearTestPlayer(userId) end
				if _G.AntiFlyTP.ResetWarnings  then _G.AntiFlyTP.ResetWarnings(userId) end
				if _G.AntiFlyTP.ForgetFile     then _G.AntiFlyTP.ForgetFile(userId) end
			end)
		end
		return { ok = true, msg = "Stats anti-cheat remises à zéro" }

		----------------------------------------------------------------
	elseif action == "setconfig" then
		local ok, msg = saveConfig(payload.config, byName)
		return { ok = ok, msg = ok and "Réglages enregistrés ✅" or msg,
			config = UGCRestrict.GetConfig() }

		----------------------------------------------------------------
	elseif action == "reload" then
		loadConfig()
		cache = {} ; cacheAt = {}
		invalidateList()
		return { ok = true, msg = "Config et registre rechargés",
			config = UGCRestrict.GetConfig() }

		----------------------------------------------------------------
		-- 📡 FIL DES DÉTECTIONS RÉCENTES
		--    Qui a été flaggé récemment, tous serveurs confondus. Une seule
		--    lecture d'OrderedDataStore : c'est instantané, contrairement à
		--    une liste de fiches.
	elseif action == "feed" then
		local n = math.clamp(tonumber(payload.limit) or 40, 1, 100)
		local hide = payload.hideRestricted == true
		local out = {}
		local s = ensureFeedStore()
		if s then
			--  Masquer les restreints : on lit plus large pour combler les trous.
			local want = hide and 100 or n
			local ok, pages = pcall(function() return s:GetSortedAsync(false, want) end)
			if ok then
				for _, e in ipairs(pages:GetCurrentPage()) do
					local uid = tonumber(e.key)
					if uid then out[#out + 1] = { userId = uid, at = e.value } end
				end
			end
		end
		local hidden = 0
		out, hidden = UGCRestrict.Annotate(out)
		if hide then
			out = UGCRestrict.FilterOutRestricted(out)
		end
		while #out > n do table.remove(out) end
		return { ok = true, entries = out, restrictedCount = hidden, hidden = hide }

		----------------------------------------------------------------
		-- 🏷️ RÉSOLUTION EN LOT — noms + points + statut, EN PARALLÈLE
		--    C'est ce qui rendait tes classements interminables : l'ancien
		--    chemin faisait jusqu'à 120 requêtes l'une après l'autre, avec une
		--    pause entre chaque. Ici tout part en même temps, par vagues.
	elseif action == "resolve" then
		local ids = payload.ids
		if type(ids) ~= "table" then return { ok = false, msg = "Liste invalide" } end
		return { ok = true, data = UGCRestrict.ResolveBatch(ids) }
	end

	return { ok = false, msg = "Action inconnue" }
end

--════════════════════════════════════════════════════════════════════════════
-- 🧰 COMMANDES CONSOLE
--════════════════════════════════════════════════════════════════════════════
_G.UGCRestrict_Diag = function()
	print("╔══════════════════════════════════════════════════════════╗")
	print("║ 🚫 DIAGNOSTIC — PRIVATION D'UGC                           ║")
	print("╚══════════════════════════════════════════════════════════╝")
	print(string.format("  Config lue        : %s", tostring(cfgLoaded)))
	print(string.format("  Mode              : %s", cfg.mode))
	print(string.format("  Shadow            : %s%s", tostring(cfg.shadow),
		cfg.shadow and "  (AUCUNE sanction n'est appliquée)" or ""))
	print(string.format("  Seuil             : %d warning(s)", cfg.warningsToRestrict))
	print(string.format("  Admins analysés   : %s", cfg.analyzeAdmins
		and "OUI — aucun privilège" or "non — ils sont ignorés"))
	print(string.format("  Certitude requise : %d%% pour compter · %d%% pour avertir · %d%% pour sanctionner",
		cfg.minConfidenceCount, cfg.minConfidenceWarn, cfg.minConfidenceSanction))
	print(string.format("  Escrow enveloppé  : %s",
		tostring(_G.UGCEscrow and _G.UGCEscrow.__ugcRestrictWrapped == true)))
	local n = 0
	for _, v in pairs(cache) do if v then n = n + 1 end end
	print(string.format("  Restreints en cache : %d", n))
	print("  .UGCRestrict_List()      -- liste persistée")
	print("  .UGCRestrict_Add(userId) -- privation manuelle")
	print("  .UGCRestrict_Free(userId)-- lever")
end

_G.UGCRestrict_List = function()
	task.spawn(function()
		local l = UGCRestrict.List(60)
		if not l then print("🚫 Registre illisible") return end
		print(string.format("🚫 %d joueur(s) privé(s) d'UGC :", #l))
		for i, r in ipairs(l) do
			print(string.format("  %2d. %-20s (%d) | %s | par %s | %d tentative(s)",
				i, r.name or "?", r.userId,
				os.date("!%d/%m/%Y", r.at or 0), r.by or "?", r.attempts or 0))
		end
	end)
end

_G.UGCRestrict_Add = function(userId, note)
	task.spawn(function()
		local ok, msg = UGCRestrict.Add(userId, {
			by = "console", reason = "admin", details = note or "Console",
		})
		print((ok and "✅ " or "❌ ") .. tostring(msg))
	end)
end

_G.UGCRestrict_Free = function(userId)
	task.spawn(function()
		local ok, msg = UGCRestrict.Remove(userId, "console")
		print((ok and "✅ " or "❌ ") .. tostring(msg))
	end)
end

print("✅ 🚫 PRIVATION D'UGC + CONFIG ANTI-CHEAT CHARGÉES")
print("   _G.UGCRestrict_Diag() pour l'état complet")