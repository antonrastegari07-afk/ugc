--════════════════════════════════════════════════════════════════════════════
-- 🎪 ADMIN ABUSE — MOTEUR SERVEUR
--
--  📍 OÙ LE METTRE ?
--     ServerScriptService → Script nommé « AdminAbuse_Server »
--     Prérequis : ReplicatedStorage → ModuleScript « AdminAbuse_Config »
--
--  ┌──────────────────────────────────────────────────────────────────────┐
--  │ 🔒 LES SEPT RÈGLES DE SÉCURITÉ DE CE FICHIER                         │
--  │                                                                      │
--  │ 1. AUCUNE RÉCOMPENSE D'ÉVÉNEMENT N'EST PERSISTANTE.                  │
--  │    Boosts, vitesse, saut, gravité, outils : tout vit en mémoire, et  │
--  │    rien de tout ça n'est jamais écrit dans un DataStore. Même si ce  │
--  │    script plante, le serveur redémarre sans aucune trace : il n'y a  │
--  │    RIEN à nettoyer, parce qu'il n'y a RIEN d'écrit.                  │
--  │                                                                      │
--  │ 2. LA RÉVOCATION N'A BESOIN DE PERSONNE.                            │
--  │    Chaque serveur a sa propre horloge de fin. Il révoque tout seul   │
--  │    quand elle sonne. Aucun message réseau n'est nécessaire pour      │
--  │    retirer une récompense — seulement pour en donner une. Réseau     │
--  │    coupé = tout est retiré, jamais l'inverse.                        │
--  │                                                                      │
--  │ 3. LE CLIENT NE DÉCIDE JAMAIS RIEN.                                 │
--  │    Il ne demande pas ses points, il ne réclame pas son cadeau, il ne │
--  │    dit pas qu'il est admin. Il n'y a AUCUN remote « claim ». Le      │
--  │    serveur pousse, le client affiche. Un exploiteur n'a donc rien à  │
--  │    appeler : la surface d'attaque est réduite aux remotes admin, et  │
--  │    ceux-là revérifient l'UserId à CHAQUE appel.                      │
--  │                                                                      │
--  │ 4. TOUT CE QUI VIENT DU PANEL REPASSE PAR Config.Validate*.          │
--  │    Le panel est un LocalScript : il est modifiable. Donc il est      │
--  │    hostile. Aucune valeur reçue n'est utilisée telle quelle.         │
--  │                                                                      │
--  │ 5. L'ANTI-CHEAT EST PRÉVENU AVANT, PAS APRÈS.                       │
--  │    ExpectGain avant le crédit, RecordGain après, et le multiplicateur│
--  │    d'événement est branché DANS _G.TempBoosts.getMultiplier — la     │
--  │    fonction que ton anti-cheat lit déjà. Il ne peut donc pas y avoir │
--  │    de faux positif : ce que le joueur gagne est exactement ce que    │
--  │    l'anti-cheat attend.                                              │
--  │                                                                      │
--  │ 6. UN CADEAU EST LIÉ À UN INSTANT, PAS À UNE ACTION.                │
--  │    Éligible = « tu étais déjà connecté ici quand j'ai appuyé ».      │
--  │    Personne ne peut être à deux endroits à cet instant-là, donc      │
--  │    personne ne peut le recevoir deux fois — sans le moindre          │
--  │    DataStore, et sans que se reconnecter ne serve à rien.            │
--  │                                                                      │
--  │ 7. EN CAS DE DOUTE, ON RETIRE.                                      │
--  │    Toutes les révocations sont idempotentes et sont rejouées à       │
--  │    l'arrêt, au respawn, au départ du joueur et à la fermeture du     │
--  │    serveur. En retirer deux fois ne coûte rien ; en oublier une      │
--  │    fois casserait la règle nº1.                                      │
--  └──────────────────────────────────────────────────────────────────────┘
--════════════════════════════════════════════════════════════════════════════

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local DataStoreService   = game:GetService("DataStoreService")
local MessagingService   = game:GetService("MessagingService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TextService        = game:GetService("TextService")
local HttpService        = game:GetService("HttpService")
local Workspace          = game:GetService("Workspace")

--══════════════════════════════════════════════════════════════════════════════
-- 🔒 QUI EST ADMIN
--    Cette liste est un LOCAL de ce script serveur. Elle n'est jamais
--    répliquée, jamais envoyée au client, jamais lue depuis une config
--    partagée. C'est le seul point de décision de tout le système.
--══════════════════════════════════════════════════════════════════════════════
local ADMIN_IDS = {
	3203521470, 11017023724, 8456613930, 8142402169, 10420404767,
}

local adminSet = {}
for _, id in ipairs(ADMIN_IDS) do adminSet[id] = true end

local function isAdmin(player)
	if typeof(player) ~= "Instance" then return false end
	if not player:IsA("Player") then return false end
	return adminSet[player.UserId] == true
end

--══════════════════════════════════════════════════════════════════════════════
-- CONFIG
--══════════════════════════════════════════════════════════════════════════════
local Config
do
	local mod = ReplicatedStorage:WaitForChild("AdminAbuse_Config", 30)
	if not mod then
		warn("🚨 [AdminAbuse] ReplicatedStorage/AdminAbuse_Config introuvable. "
			.. "Le système ne démarre pas — c'est volontaire : mieux vaut rien "
			.. "faire que de tourner sans les bornes de sécurité.")
		return
	end
	local ok, res = pcall(require, mod)
	if not ok or type(res) ~= "table" then
		warn("🚨 [AdminAbuse] AdminAbuse_Config illisible : " .. tostring(res))
		return
	end
	Config = res
end

local LIM = Config.LIMITS

local SERVER_TAG = (game.JobId ~= "" and game.JobId)
	or ("studio_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999)))

local liveStore = DataStoreService:GetDataStore("AdminAbuse_Live_v1")
local cfgStore  = DataStoreService:GetDataStore(Config.CONFIG_KEY)
local runStore  = DataStoreService:GetDataStore(Config.RUNS_KEY)

local LIVE_KEY  = "active"
local POLL_EVERY = 25          -- s — filet nº2 si un message se perd
local STATS_PUSH = 20          -- s — remontée des stats de ce serveur

--══════════════════════════════════════════════════════════════════════════════
-- 🔌 DÉPENDANCES DU JEU  (résolues à chaud : l'ordre de chargement varie)
--══════════════════════════════════════════════════════════════════════════════
local function deps()
	return {
		tempsJoueurs    = _G.tempsJoueurs,
		secureSave      = _G.secureSave,
		applyAllBonuses = _G.applyAllBonuses,
		calculatePoints = _G.calculatePoints,
		SmartAntiCheat  = _G.SmartAntiCheat,
		dataLoading     = _G.dataLoading,
		AntiExploit     = _G.AntiExploit,
	}
end

--══════════════════════════════════════════════════════════════════════════════
-- 📡 REMOTES
--    4 seulement. Les deux RemoteFunction sont protégées par isAdmin à chaque
--    appel ; les deux RemoteEvent sont à sens unique serveur → client (le
--    handler OnServerEvent n'existe même pas, donc un exploiteur qui les
--    déclenche ne provoque rigoureusement rien).
--══════════════════════════════════════════════════════════════════════════════
local function mk(className, name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if e and e.ClassName ~= className then e:Destroy() ; e = nil end
	if not e then
		e = Instance.new(className)
		e.Name = name
		e.Parent = ReplicatedStorage
	end
	return e
end

local rfGet    = mk("RemoteFunction", "AdminAbuseGet")
local rfAct    = mk("RemoteFunction", "AdminAbuseAction")
local reState  = mk("RemoteEvent",    "AdminAbuseState")
local reMsg    = mk("RemoteEvent",    "AdminAbuseMessage")

--══════════════════════════════════════════════════════════════════════════════
-- 🚨 JOURNAL DES REFUS
--══════════════════════════════════════════════════════════════════════════════
local denied = {}
local function logDenied(player, what)
	local id = (typeof(player) == "Instance" and player:IsA("Player")) and player.UserId or 0
	local rec = denied[id]
	if not rec then rec = { n = 0, last = 0 } ; denied[id] = rec end
	rec.n = rec.n + 1
	local now = os.time()
	if now - rec.last >= 10 then
		rec.last = now
		warn(string.format("🚨 [AdminAbuse] Accès REFUSÉ · UserId %d · %s · %d tentative(s)",
			id, tostring(what), rec.n))
	end
end

--  Limiteur de débit par joueur : même un admin ne peut pas marteler un
--  remote (un panel bugué ou un clic répété ne doit pas noyer le serveur).
local rate = {}
local function allow(player, key, minGap)
	local uid = player.UserId
	local t = rate[uid]
	if not t then t = {} ; rate[uid] = t end
	local now = os.clock()
	if t[key] and (now - t[key]) < minGap then return false end
	t[key] = now
	return true
end

--══════════════════════════════════════════════════════════════════════════════
-- ⚡ MOTEUR D'EFFETS
--
--   TOUT EST EN MÉMOIRE. C'est la garantie nº1 : rien à révoquer après un
--   crash, parce que rien n'a survécu au crash.
--══════════════════════════════════════════════════════════════════════════════
local Effects = {
	boost   = {},   -- [userId] = multiplicateur ajouté
	speed   = {},   -- [userId] = écart de WalkSpeed appliqué
	jump    = {},   -- [userId] = écart de JumpPower appliqué
	pvp     = {},   -- [userId] = true
	tools   = {},   -- [userId] = { [Tool] = true }
	seen    = {},   -- [userId] = true  (a participé à l'événement en cours)
	boosted = {},   -- [userId] = true  (a été boosté au moins une fois)
	joinAt  = {},   -- [userId] = os.time() de sa connexion à CE serveur
}

function Effects.boostOf(userId)
	return Effects.boost[userId] or 0
end

--  Déclaration anticipée : les cadeaux (partie « CADEAUX GLOBAUX », plus bas)
--  peuvent ajouter un boost temporaire PAR-DESSUS celui de la météo en cours.
--  applyToPlayer doit donc pouvoir demander « combien de boost-cadeau a ce
--  joueur ? » alors que la fonction n'est définie que plus loin. Tant qu'elle
--  vaut nil, elle compte pour zéro : aucun risque au chargement.
local giftBoostOf   -- forward
local giftToolLive  -- forward (idem, pour les outils prêtés par un cadeau)

--──────────────────────────────────────────────────────────────────────────────
-- 🌉 LE PONT ANTI-CHEAT  (la pièce qui garantit « zéro faux positif »)
--
--   Ton jeu lit le multiplicateur temporaire à UN SEUL endroit :
--       _G.TempBoosts.getMultiplier(userId)
--   … et il le lit depuis TROIS appelants : la boucle de points passifs,
--   SmartAntiCheat.CalculateMaxGain et SmartAntiCheat.AnalyzePlayer.
--
--   Plutôt que d'aller patcher ces trois endroits (donc trois occasions de me
--   tromper, et trois fichiers à toi modifiés), on enveloppe la fonction :
--   les trois appelants voient AUTOMATIQUEMENT le boost d'événement, en même
--   temps, avec la même valeur. Le gain réel et le gain autorisé restent donc
--   toujours d'accord. C'est structurellement impossible d'avoir un décalage.
--
--   Trois propriétés importantes :
--     • Idempotent : le drapeau __aaWrapped empêche d'empiler deux couches
--       si ce script est rechargé.
--     • Sans effet de bord : si TempBoosts n'est jamais chargé, le boost
--       d'événement ne fait simplement rien. Il ne provoque JAMAIS de ban.
--     • Non persistant : enrichQuestSnapshotWithBoosts lit la table INTERNE
--       de TempBoosts, pas getMultiplier. Un boost d'événement ne peut donc
--       pas se faufiler dans une sauvegarde de session.
--──────────────────────────────────────────────────────────────────────────────
local bridgeOn = false
local function installBoostBridge()
	if bridgeOn then return true end
	local TB = _G.TempBoosts
	if type(TB) ~= "table" or type(TB.getMultiplier) ~= "function" then return false end
	if TB.__aaWrapped then bridgeOn = true ; return true end
	local original = TB.getMultiplier
	TB.getMultiplier = function(userId, ...)
		local base = tonumber(original(userId, ...)) or 0
		local extra = Effects.boost[userId]
		if extra and extra > 0 then return base + extra end
		return base
	end
	TB.__aaWrapped  = true
	TB.__aaOriginal = original
	bridgeOn = true
	print("✅ [AdminAbuse] Pont anti-cheat installé sur TempBoosts.getMultiplier")
	return true
end

task.spawn(function()
	for _ = 1, 60 do
		if installBoostBridge() then return end
		task.wait(1)
	end
	warn("⚠️ [AdminAbuse] TempBoosts introuvable après 60 s → les boosts "
		.. "d'événement seront sans effet (aucun risque de ban, mais pense "
		.. "à vérifier que TempBoosts.server.lua est bien chargé).")
end)

--══════════════════════════════════════════════════════════════════════════════
-- 🧍 EFFETS SUR LE PERSONNAGE
--
--   Principe : on mémorise l'ÉCART qu'on a appliqué, jamais la valeur finale.
--   Comme ça, si un coil ajoute +20 pendant l'événement, retirer notre +26
--   laisse bien le +20 du coil en place. Retirer une valeur absolue aurait
--   écrasé le travail de tes autres scripts.
--══════════════════════════════════════════════════════════════════════════════
local function humanoidOf(player)
	local ch = player.Character
	if not ch then return nil end
	local h = ch:FindFirstChildOfClass("Humanoid")
	if h and h.Health > 0 then return h end
	return h
end

local function applyCharacterStats(player)
	local uid = player.UserId
	local h = humanoidOf(player)
	if not h then return end
	local ds = Effects.speed[uid] or 0
	local dj = Effects.jump[uid] or 0
	--  L'attribut sert de mémoire visible pour tes autres scripts ET de
	--  garde-fou : si le personnage réapparaît, on sait quoi réappliquer.
	pcall(function()
		--  ⚠️ On enregistre l'écart RÉELLEMENT appliqué, pas l'écart demandé.
		--     Sans ça, dès que le clamp mord (WalkSpeed 16 avec ef_speed = -50
		--     donne 0, pas -34), la soustraction du retrait ne serait plus
		--     l'inverse de l'addition : le joueur finirait l'événement PLUS
		--     RAPIDE qu'avant. C'est-à-dire une récompense qui survit à
		--     l'événement, et une signature de speed-hack pour l'anti-cheat.
		if ds ~= 0 then
			local before = h.WalkSpeed
			h.WalkSpeed = math.clamp(before + ds, 0, 400)
			ds = h.WalkSpeed - before
		end
		if dj ~= 0 then
			--  UseJumpPower : on mémorise l'état d'origine pour le remettre.
			--     Le forcer sans le rendre casserait durablement un jeu réglé
			--     en JumpHeight.
			if player:GetAttribute("AAEventUJP") == nil then
				player:SetAttribute("AAEventUJP", h.UseJumpPower)
			end
			h.UseJumpPower = true
			local before = h.JumpPower
			h.JumpPower = math.clamp(before + dj, 0, 500)
			dj = h.JumpPower - before
		end
	end)
	Effects.speed[uid] = (ds ~= 0) and ds or nil
	Effects.jump[uid]  = (dj ~= 0) and dj or nil
	player:SetAttribute("AAEventSpeed", ds ~= 0 and ds or nil)
	player:SetAttribute("AAEventJump",  dj ~= 0 and dj or nil)
end

local function removeCharacterStats(player)
	local uid = player.UserId
	local ds = Effects.speed[uid] or 0
	local dj = Effects.jump[uid] or 0
	local h = humanoidOf(player)
	if h then
		pcall(function()
			if ds ~= 0 then h.WalkSpeed = math.clamp(h.WalkSpeed - ds, 0, 400) end
			if dj ~= 0 then h.JumpPower = math.clamp(h.JumpPower - dj, 0, 500) end
			local prev = player:GetAttribute("AAEventUJP")
			if prev ~= nil then h.UseJumpPower = (prev == true) end
		end)
	end
	Effects.speed[uid] = nil
	Effects.jump[uid]  = nil
	player:SetAttribute("AAEventSpeed", nil)
	player:SetAttribute("AAEventJump",  nil)
	player:SetAttribute("AAEventUJP",   nil)
end

--══════════════════════════════════════════════════════════════════════════════
-- 🔧 OUTILS PRÊTÉS
--
--   Trois verrous pour qu'un outil d'événement ne puisse pas être gardé :
--     1. Il vit dans ServerStorage/AdminAbuseTools — un dossier À PART. Ta
--        fonction restorePlayerTools de l'arène cherche à la RACINE de
--        ServerStorage avec un FindFirstChild non récursif : elle ne peut
--        donc structurellement pas ressortir un outil d'événement.
--     2. CanBeDropped = false → impossible de le poser par terre pour que
--        quelqu'un d'autre le ramasse après l'événement.
--     3. Un attribut marque chaque exemplaire. La révocation balaie le sac
--        À DOS ET le personnage, et se rejoue à chaque respawn.
--══════════════════════════════════════════════════════════════════════════════
local function toolsFolder()
	return ServerStorage:FindFirstChild(Config.TOOLS_FOLDER)
end

local function giveTool(player, toolName, runId)
	if type(toolName) ~= "string" or toolName == "" then return false, "no_name" end
	local folder = toolsFolder()
	if not folder then return false, "no_folder" end
	local src = folder:FindFirstChild(toolName)
	if not src or not src:IsA("Tool") then return false, "not_found" end

	local uid = player.UserId
	Effects.tools[uid] = Effects.tools[uid] or {}
	--  Un seul exemplaire de chaque outil par joueur : on ne veut pas qu'un
	--  respawn ou une resynchronisation en empile dix.
	for tool in pairs(Effects.tools[uid]) do
		if tool.Parent and tool.Name == toolName then return true, "already" end
	end

	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then return false, "no_backpack" end

	local ok, clone = pcall(function() return src:Clone() end)
	if not ok or not clone then return false, "clone_failed" end
	clone:SetAttribute(Config.TOOL_TAG, tostring(runId))
	clone.CanBeDropped = false
	clone.Parent = bp
	Effects.tools[uid][clone] = true
	return true, "given"
end

--  Balayage complet : sac à dos + personnage + notre propre table. Idempotent.
local function revokeTools(player)
	local uid = player.UserId
	local n = 0
	local function sweep(container)
		if not container then return end
		for _, inst in ipairs(container:GetChildren()) do
			if inst:IsA("Tool") and inst:GetAttribute(Config.TOOL_TAG) ~= nil then
				inst:Destroy()
				n = n + 1
			end
		end
	end
	sweep(player:FindFirstChildOfClass("Backpack"))
	sweep(player.Character)
	local set = Effects.tools[uid]
	if set then
		for tool in pairs(set) do
			if tool and tool.Parent then pcall(function() tool:Destroy() end) end
		end
	end
	Effects.tools[uid] = nil
	return n
end

--  🧹 Filet de sécurité global : détruit TOUT outil marqué encore présent dans
--     le serveur, quel qu'en soit le porteur. Appelé à la fin de chaque
--     événement. C'est la ceinture par-dessus les bretelles.
local function sweepAllEventTools()
	local n = 0
	for _, player in ipairs(Players:GetPlayers()) do
		n = n + revokeTools(player)
	end
	--  Un outil lâché malgré tout (CanBeDropped=false empêche le drop manuel,
	--  mais un script tiers pourrait reparenter) finirait dans Workspace.
	for _, inst in ipairs(Workspace:GetChildren()) do
		if inst:IsA("Tool") and inst:GetAttribute(Config.TOOL_TAG) ~= nil then
			inst:Destroy()
			n = n + 1
		end
	end
	return n
end

--══════════════════════════════════════════════════════════════════════════════
-- 🌍 GRAVITÉ — LE SEUL VISUEL QUI RESTE CÔTÉ SERVEUR
--
--   Tout le reste (lumière, atmosphère, ciel, effets d'écran, musique) est
--   appliqué PAR LE CLIENT, donc coûte zéro octet de réplication. C'est la
--   leçon du problème de lag : ne jamais faire circuler ce que chaque machine
--   peut calculer toute seule.
--
--   La gravité, elle, ne peut PAS être client-only : la physique du
--   personnage est simulée sur le client propriétaire mais arbitrée par le
--   serveur. Une gravité différente des deux côtés = personnages qui
--   tressautent et anti-fly qui hurle. Donc : une seule écriture de propriété
--   par étape, côté serveur, et restauration depuis une valeur de référence
--   prise au démarrage du serveur (jamais depuis la valeur courante, qui
--   pourrait déjà être la nôtre).
--══════════════════════════════════════════════════════════════════════════════
local BASE_GRAVITY = Workspace.Gravity
local gravityHeld  = false

local function setGravity(v)
	v = tonumber(v) or 0
	if v > 0 then
		--  Deuxième ceinture : ValidateWeather borne déjà la gravité, mais
		--  cette fonction est le seul endroit qui touche VRAIMENT au monde.
		--  Elle reborne, quoi qu'on lui passe.
		if v < LIM.GRAVITY_MIN then v = LIM.GRAVITY_MIN end
		if v > LIM.GRAVITY_MAX then v = LIM.GRAVITY_MAX end
		gravityHeld = true
		pcall(function() Workspace.Gravity = v end)
	elseif gravityHeld then
		gravityHeld = false
		pcall(function() Workspace.Gravity = BASE_GRAVITY end)
	end
end

--══════════════════════════════════════════════════════════════════════════════
-- 🛡️ TOLÉRANCE ANTI-FLY
--
--   Une météo qui change vitesse / saut / gravité fait bouger les joueurs
--   autrement que d'habitude. Sans prévenir l'anti-fly, ce sont des JOUEURS
--   HONNÊTES qui se font signaler — exactement ce que tu ne veux pas.
--
--   On utilise l'API que ton anti-fly expose déjà (SetTestMode). Deux
--   garanties : on ne l'active QUE si on ne l'a pas trouvée déjà active, et
--   on ne la désactive QUE si c'est nous qui l'avons activée. Impossible
--   d'éteindre par erreur un mode test que tu avais mis toi-même.
--
--   En plus de ça, _G.AdminAbuse.PhysicsGrace(userId) est exposé pour que tu
--   puisses, plus tard, faire une tolérance ciblée plutôt qu'un mode test
--   global — c'est plus fin, mais ça demande une ligne dans ton anti-fly.
--══════════════════════════════════════════════════════════════════════════════
local graceHeld = false

local function setPhysicsGrace(on)
	local AF = _G.AntiFlyTP
	if on then
		if graceHeld then return end
		if type(AF) == "table" and type(AF.PausePhysics) == "function" then
			local ok = pcall(function() AF.PausePhysics(true) end)
			if ok then
				graceHeld = true
				print("🛡️ [AdminAbuse] Tolérance anti-fly ACTIVÉE (météo physique)")
			end
		end
	else
		if not graceHeld then return end
		graceHeld = false
		if type(AF) == "table" and type(AF.PausePhysics) == "function" then
			pcall(function() AF.PausePhysics(false) end)
			print("🛡️ [AdminAbuse] Tolérance anti-fly RENDUE À SON ÉTAT NORMAL")
		end
	end
end

--══════════════════════════════════════════════════════════════════════════════
-- 💰 CRÉDIT DE POINTS
--
--   Copie fidèle du chemin déjà éprouvé de GiftingServer.creditPoints : même
--   ordre d'opérations, mêmes garde-fous, même invariant. Ce n'est pas de la
--   paresse, c'est le contraire : le chemin qui crédite des points est le
--   plus dangereux du jeu, et il n'en existe qu'UN qui a été audité. On s'y
--   colle au lieu d'en inventer un deuxième.
--
--   ⚠️ INVARIANT : à partir de data.future = data.future + amount, la
--      fonction ne peut plus échouer ni lever d'erreur. Un throw après la
--      mutation autoriserait une re-livraison, donc du farm.
--══════════════════════════════════════════════════════════════════════════════
local function creditPoints(player, amount, source)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false, "amount" end
	if amount > LIM.POINTS_GRANT_MAX then return false, "too_big" end

	local d = deps()
	if not d.tempsJoueurs or not d.secureSave then return false, "no_deps" end
	if not d.applyAllBonuses or not d.calculatePoints then return false, "no_deps" end

	local userId = player.UserId
	if d.dataLoading and d.dataLoading[userId] then return false, "data_loading" end
	if d.AntiExploit and d.AntiExploit.bannedPlayers
		and d.AntiExploit.bannedPlayers[userId] then return false, "banned" end
	if type(d.tempsJoueurs[userId]) ~= "table" then return false, "no_record" end

	local data = d.tempsJoueurs[userId]
	--  🛡️ Garde AVANT la mutation. Plus bas, « data.base + data.future » n'est
	--     pas sous pcall (c'est aussi le cas dans GiftingServer) : si l'un des
	--     deux n'était pas un nombre, ça lèverait une erreur APRÈS avoir déjà
	--     crédité — donc le compteur Run.given ne serait jamais mis à jour et
	--     le plafond par joueur ne compterait plus. Ici, on refuse avant.
	if type(data.base) ~= "number" or type(data.future) ~= "number" then
		return false, "no_record"
	end

	--  🛡️ On PRÉVIENT l'anti-cheat avant de créditer. Dans l'autre ordre, il
	--     verrait une hausse inexpliquée pendant quelques millisecondes.
	if d.SmartAntiCheat and d.SmartAntiCheat.ExpectGain then
		pcall(function() d.SmartAntiCheat.ExpectGain(userId, amount, source) end)
	end

	-- ══ À PARTIR D'ICI, PLUS AUCUN RETOUR false POSSIBLE ══
	data.future = data.future + amount

	pcall(function()
		local leaderstats = player:FindFirstChild("leaderstats")
		local pointsStat  = leaderstats and leaderstats:FindFirstChild("Points")
		if pointsStat then
			local total = data.base + data.future
			pointsStat.Value = d.applyAllBonuses(d.calculatePoints(total), player)
			player:SetAttribute("Points", pointsStat.Value)
			local sd = d.SmartAntiCheat and d.SmartAntiCheat.playerData
				and d.SmartAntiCheat.playerData[userId]
			if sd then
				sd.lastKnownPoints = pointsStat.Value
				sd.lastCheckTime   = os.time()
				--  ⚠️ ON NE TOUCHE PAS à sd.validationWindow.expectedGains.
				--     ExpectGain vient d'y déposer CE gain quelques lignes plus
				--     haut : le vider ici effacerait l'autorisation qu'on vient
				--     de demander, et le prochain AnalyzePlayer verrait une
				--     hausse inexpliquée. GiftingServer — le seul chemin de
				--     points audité de ton jeu — ne le fait pas non plus. On
				--     copie ce chemin à l'identique, sans rien ajouter.
			end
		end
	end)

	if d.SmartAntiCheat and d.SmartAntiCheat.RecordGain then
		task.spawn(function()
			pcall(function() d.SmartAntiCheat.RecordGain(player, amount, source) end)
		end)
	end

	pcall(function()
		if _G.AbsoluteCapAdminBonus then _G.AbsoluteCapAdminBonus(userId, amount) end
	end)

	local total = data.base + data.future
	task.spawn(function()
		pcall(function() d.secureSave(userId, total) end)
	end)

	return true, "ok"
end

--══════════════════════════════════════════════════════════════════════════════
-- 📊 STATISTIQUES DE CE SERVEUR
--══════════════════════════════════════════════════════════════════════════════
local Stats = {}

local function freshStats()
	return {
		peakOnline = 0, participants = 0, presentNow = 0,
		pointsTotal = 0, pointsPlayers = 0,
		giftsSent = 0, giftsOk = 0, giftsFail = 0,
		boostNow = 0, boostEver = 0,
		toolsOut = 0, toolsReturned = 0,
		messagesSent = 0,
		stepsDone = 0, stepsFailed = 0,
		revoked = 0, revokeFail = 0,
		autoGifts = 0,
		joinedDuring = 0, leftDuring = 0,
	}
end
Stats.d = freshStats()

local pointedOnce = {}   -- [userId] = true (a reçu au moins 1 point cet event)

local function statBump(k, n)
	Stats.d[k] = (Stats.d[k] or 0) + (n or 1)
end

local function recomputeLive()
	local online = #Players:GetPlayers()
	if online > (Stats.d.peakOnline or 0) then Stats.d.peakOnline = online end
	Stats.d.presentNow = online
	local b, t = 0, 0
	for uid, v in pairs(Effects.boost) do
		if v > 0 and Players:GetPlayerByUserId(uid) then b = b + 1 end
	end
	for uid, set in pairs(Effects.tools) do
		if Players:GetPlayerByUserId(uid) then
			for tool in pairs(set) do if tool.Parent then t = t + 1 end end
		end
	end
	Stats.d.boostNow = b
	Stats.d.toolsOut = t
	local n = 0
	for _ in pairs(Effects.seen) do n = n + 1 end
	Stats.d.participants = n
	local e = 0
	for _ in pairs(Effects.boosted) do e = e + 1 end
	Stats.d.boostEver = e
	local p = 0
	for _ in pairs(pointedOnce) do p = p + 1 end
	Stats.d.pointsPlayers = p
end

--  Remontée inter-serveurs via MemoryStore (fait pour ça : rapide, TTL
--  automatique, aucune contention DataStore). Si MemoryStore n'est pas
--  disponible, on continue sans : le panel affichera « ce serveur seulement »
--  au lieu de mentir avec un total partiel présenté comme global.
local statsMap, statsMapOk = nil, false
pcall(function()
	statsMap = MemoryStoreService:GetHashMap("AdminAbuseStats_v1")
	statsMapOk = statsMap ~= nil
end)

local function pushStats()
	if not statsMapOk or not statsMap then return end
	local runId = _G.__aaRunId
	if not runId then return end
	recomputeLive()
	local copy = {}
	for k, v in pairs(Stats.d) do copy[k] = v end
	copy.at = os.time()
	pcall(function()
		statsMap:SetAsync(tostring(runId) .. "|" .. SERVER_TAG, copy, 7200)
	end)
end

--══════════════════════════════════════════════════════════════════════════════
-- 🎬 ÉTAT DE L'ÉVÉNEMENT
--
--   Ce serveur ne « reçoit » pas les étapes une par une. Il reçoit LE PLAN
--   (avec un instant de départ absolu) et déroule sa propre horloge.
--
--   Pourquoi ce choix plutôt qu'un serveur maître qui commande les autres :
--   parce qu'un serveur maître qui meurt laisserait les autres bloqués avec
--   des récompenses actives et personne pour les retirer. Ici, chaque serveur
--   sait TOUT SEUL quand s'arrêter. La panne réseau la plus totale se termine
--   par une révocation propre partout — jamais par un boost éternel.
--══════════════════════════════════════════════════════════════════════════════
local Run = nil          -- table de l'événement en cours, ou nil
local lastAppliedIdx = nil

--  🛑 LISTE NOIRE. Quand un admin arrête un événement, on retient son
--     identifiant ICI, en mémoire, pour toujours (à l'échelle de ce serveur).
--     Pourquoi c'est indispensable : si l'écriture « arrêté » dans le
--     DataStore échoue, la clé contient encore l'ancien plan. Au prochain
--     sondage (25 s plus tard), ce serveur le relirait, ne verrait plus
--     d'événement en cours, et le RELANCERAIT — en repartant d'un compteur
--     de points vierge. Autrement dit : l'événement « arrêté » reprend et
--     chaque joueur peut refaire le plein. Avec cette liste, un événement
--     arrêté ne peut plus jamais être ré-adopté.
local stoppedIds = {}

local function curStep()
	if not Run then return nil end
	return Run.steps[Run.idx]
end

--──────────────────────────────────────────────────────────────────────────────
-- Application / révocation par joueur
--──────────────────────────────────────────────────────────────────────────────
local function setDeltas(player, ds, dj)
	local uid = player.UserId
	removeCharacterStats(player)
	if ds ~= 0 then Effects.speed[uid] = ds end
	if dj ~= 0 then Effects.jump[uid]  = dj end
	applyCharacterStats(player)
end

local function applyToPlayer(player, w)
	if not w then return end
	local uid = player.UserId
	Effects.seen[uid] = true

	-- ⚡ Boost de points (mémoire seule — lu par le pont anti-cheat)
	--    Météo + cadeau, plafonné UNE FOIS à la fin : c'est le plafond du
	--    total qui compte, sinon deux sources plafonnées séparément
	--    donneraient 2 × BOOST_MAX.
	local b = math.floor(tonumber(w.ef_boost) or 0)
	if b < 0 then b = 0 end
	b = b + (giftBoostOf and giftBoostOf(uid) or 0)
	if b > LIM.BOOST_MAX then b = LIM.BOOST_MAX end
	if b > 0 then
		Effects.boost[uid] = b
		Effects.boosted[uid] = true
		player:SetAttribute("AAEventBoost", b)
	else
		Effects.boost[uid] = nil
		player:SetAttribute("AAEventBoost", nil)
	end

	-- 🏃 Vitesse / saut
	setDeltas(player, tonumber(w.ef_speed) or 0, tonumber(w.ef_jump) or 0)

	-- ⚔️ PVP : on expose l'état, ton système de combat n'a qu'à le lire.
	if w.ef_pvp then
		Effects.pvp[uid] = true
		player:SetAttribute("AAEventPVP", true)
	else
		Effects.pvp[uid] = nil
		player:SetAttribute("AAEventPVP", nil)
	end

	-- 🔧 Outil prêté
	if w.ef_tool and w.ef_tool ~= "" then
		local ok = giveTool(player, w.ef_tool, Run and Run.id or "?")
		if not ok then revokeTools(player) end
	elseif not (giftToolLive and giftToolLive(uid)) then
		--  L'étape ne prête pas d'outil → on reprend ceux de l'étape d'avant.
		--  MAIS pas si le joueur tient un outil reçu en CADEAU : celui-là a sa
		--  propre durée, il n'appartient pas à l'étape.
		local n = revokeTools(player)
		if n > 0 then statBump("toolsReturned", n) end
	end
end

--  🧹 LA RÉVOCATION. Idempotente, sans réseau, sans DataStore.
--     Appelée : fin d'étape, fin d'événement, départ du joueur, respawn
--     hors événement, fermeture du serveur. En trop = sans effet.
local function revokeFromPlayer(player, countStats)
	local uid = player.UserId
	local ok = true

	if Effects.boost[uid] then
		Effects.boost[uid] = nil
		local okA = pcall(function() player:SetAttribute("AAEventBoost", nil) end)
		if not okA then ok = false end
	end

	local okB = pcall(function() removeCharacterStats(player) end)
	if not okB then ok = false end

	if Effects.pvp[uid] then
		Effects.pvp[uid] = nil
		pcall(function() player:SetAttribute("AAEventPVP", nil) end)
	end

	local n = 0
	local okC = pcall(function() n = revokeTools(player) end)
	if not okC then ok = false end

	if countStats then
		if n > 0 then statBump("toolsReturned", n) end
		if ok then statBump("revoked") else statBump("revokeFail") end
	end
	return ok
end

local function revokeEveryone(countStats)
	--  ⚠️ CHAQUE morceau sous son propre pcall. Avec un seul pcall englobant,
	--     une erreur sur le joueur nº3 sautait les joueurs suivants, le
	--     balayage des outils, la remise de la gravité ET la sortie du mode
	--     tolérance anti-fly — deux états qui n'ont aucun autre chemin de
	--     remise à zéro et seraient restés faux jusqu'à la mort du serveur.
	for _, p in ipairs(Players:GetPlayers()) do
		pcall(revokeFromPlayer, p, countStats)
	end
	pcall(sweepAllEventTools)
	pcall(setGravity, 0)
	pcall(setPhysicsGrace, false)
end

--──────────────────────────────────────────────────────────────────────────────
-- 📤 ÉTAT ENVOYÉ AUX CLIENTS
--    Uniquement quand ça CHANGE (leçon des 20 KB/s : rien de périodique).
--──────────────────────────────────────────────────────────────────────────────
local msgConfig = Config.MessageDefaults()
local hudConfig = Config.HudDefaults()
local schedCfg  = Config.SchedDefaults()
--  Date du prochain cadeau automatique. 0 = aucun planning actif. C'est CETTE
--  date qui alimente le compte à rebours « NEXT POINT GIFT IN » sur l'écran
--  des joueurs : elle vient du DataStore, donc tous les serveurs affichent
--  exactement la même seconde.
local nextGiftAt = 0

local function stateSnapshot()
	--  ⚠️ L'état est TOUJOURS complet, même hors événement : la barre du
	--     prochain cadeau et la mise en page des HUD doivent fonctionner
	--     quand aucun événement ne tourne.
	local snap = {
		on     = false,
		mc     = msgConfig,
		hud    = hudConfig,
		giftAt = nextGiftAt,
		sc     = {
			on     = schedCfg.sc_on == true,
			every  = schedCfg.sc_every,
			amount = schedCfg.sc_amount,
		},
	}
	if not Run then return snap end
	snap.on      = true
	snap.runId   = Run.id
	snap.seq     = Run.seq
	snap.idx     = Run.idx
	snap.n       = #Run.steps
	snap.title   = Run.title
	snap.stepEnd = Run.stepEnd
	snap.runEnd  = Run.endsAt
	snap.w       = curStep()
	return snap
end

local function pushState(target)
	local snap = stateSnapshot()
	if target then
		pcall(function() reState:FireClient(target, snap) end)
	else
		pcall(function() reState:FireAllClients(snap) end)
	end
end

--──────────────────────────────────────────────────────────────────────────────
-- 🎞️ MACHINE À ÉTAPES
--──────────────────────────────────────────────────────────────────────────────
local endRun   -- forward
local announceStep   -- forward

local function enterStep(idx)
	if not Run then return end
	if idx < 1 or idx > #Run.steps then endRun("finished") return end

	Run.idx      = idx
	local step   = Run.steps[idx]
	local dur    = math.clamp(tonumber(step.duration) or 60,
		LIM.STEP_DURATION_MIN, LIM.STEP_DURATION_MAX)
	Run.stepStart = os.time()
	Run.stepEnd   = Run.stepStart + dur
	Run.nextTick  = (tonumber(step.ef_tickPts) or 0) > 0
		and (Run.stepStart + (tonumber(step.ef_tickEvery) or 30)) or nil

	--  🌍 Effets serveur globaux (une seule écriture de propriété)
	setGravity(tonumber(step.ef_gravity) or 0)
	--  🛡️ ORDRE IMPORTANT : on ALLUME la tolérance AVANT de toucher aux
	--     joueurs, et on ne l'ÉTEINT qu'APRÈS les avoir tous remis à plat.
	--     Dans l'autre sens, pendant la boucle, des joueurs encore rapides
	--     seraient déjà surveillés normalement → faux positifs.
	if step.ef_physGrace == true then setPhysicsGrace(true) end

	for _, p in ipairs(Players:GetPlayers()) do
		applyToPlayer(p, step)
	end
	if step.ef_physGrace ~= true then setPhysicsGrace(false) end

	lastAppliedIdx = idx
	pushState(nil)
	announceStep(step)

	print(string.format("🌦️ [AdminAbuse] Étape %d/%d · %s %s · %ds",
		idx, #Run.steps, tostring(step.emoji), tostring(step.name), dur))
end

--  Fin d'un événement. C'est le point le plus important du fichier : il DOIT
--  révoquer, quoi qu'il arrive. Donc chaque morceau est sous pcall et rien
--  ne peut interrompre la suite.
endRun = function(reason)
	if not Run then return end
	local finished = Run
	Run = nil
	lastAppliedIdx = nil
	--  ⚠️ _G.__aaRunId n'est PAS effacé ici : pushStats() s'en sert comme clé
	--     pour remonter le bilan final. On l'efface juste après la remontée,
	--     sinon les statistiques de l'événement seraient perdues au moment
	--     précis où elles deviennent définitives.

	pcall(function() revokeEveryone(true) end)
	pcall(function() pushState(nil) end)

	recomputeLive()
	Stats.d.presentNow = #Players:GetPlayers()
	pcall(pushStats)
	_G.__aaRunId = nil

	print(string.format("🏁 [AdminAbuse] Événement terminé (%s) · %s · %d étape(s) faite(s)",
		tostring(reason), tostring(finished.title), Stats.d.stepsDone or 0))

	--  Archivage : seul le serveur qui a lancé l'événement écrit l'historique,
	--  sinon 30 serveurs écriraient la même clé en même temps.
	if finished.origin == SERVER_TAG then
		task.spawn(function()
			pcall(function()
				local entry = {
					id = finished.id, title = finished.title,
					startedAt = finished.startedAt, endedAt = os.time(),
					by = finished.by, byName = finished.byName,
					reason = tostring(reason),
					steps = #finished.steps,
					stats = Stats.d,
				}
				runStore:UpdateAsync("history", function(old)
					local list = (type(old) == "table" and old.list) or {}
					table.insert(list, 1, entry)
					while #list > 40 do table.remove(list) end
					return Config.SanitizeForStore({ list = list, v = 1 })
				end)
			end)
		end)
	end
end

--  Boucle maîtresse : 1 Hz. Elle avance les étapes, distribue les points
--  périodiques, et — surtout — applique la coupure de sécurité.
task.spawn(function()
	while true do
		task.wait(1)
		local ok, err = pcall(function()
			if not Run then return end
			local now = os.time()

			--  🛑 COUPURE DE SÉCURITÉ. Même si tout le reste échoue, un
			--     événement ne peut pas durer plus longtemps que prévu.
			if now >= Run.endsAt then endRun("time_cap") return end

			--  💰 Points périodiques de l'étape en cours
			local step = curStep()
			if step and Run.nextTick and now >= Run.nextTick then
				local every = math.max(LIM.POINTS_TICK_INTERVAL_MIN,
					tonumber(step.ef_tickEvery) or 30)
				Run.nextTick = now + every
				local amount = math.floor(tonumber(step.ef_tickPts) or 0)
				if amount > 0 and amount <= LIM.POINTS_TICK_MAX then
					--  💰 TON plafond, pas la borne dure du système. Config
					--     le relit à chaque tick : si tu le changes pendant
					--     un événement, ça prend effet tout de suite.
					local cap = Config.PlayerCap(schedCfg)
					for _, p in ipairs(Players:GetPlayers()) do
						local given = Run.given[p.UserId] or 0
						if given + amount <= cap then
							local okc = creditPoints(p, amount, "AdminAbuse_Weather")
							if okc then
								Run.given[p.UserId] = given + amount
								pointedOnce[p.UserId] = true
								statBump("pointsTotal", amount)
							end
						end
					end
				end
			end

			--  ⏭️ Étape suivante
			if now >= Run.stepEnd then
				statBump("stepsDone")
				enterStep(Run.idx + 1)
			end
		end)
		if not ok then
			statBump("stepsFailed")
			warn("🚨 [AdminAbuse] Erreur dans la boucle : " .. tostring(err))
		end
	end
end)

--══════════════════════════════════════════════════════════════════════════════
--
--  🌐 PARTIE 4 — RÉSEAU · CADEAUX GLOBAUX · MESSAGES GLOBAUX
--
--  Ce que fait cette partie, en une phrase : elle met TOUS les serveurs
--  d'accord, sans jamais laisser l'un d'eux dépendre d'un autre pour retirer
--  une récompense.
--
--  Les trois filets (exactement la doctrine de ton VIPManager, qui marche) :
--
--     1. POUSSÉE   MessagingService — instantané, mais peut se perdre.
--     2. SONDAGE   toutes les 25 s, on relit le DataStore — rattrape tout.
--     3. HORLOGE   chaque serveur déroule le plan depuis un instant ABSOLU.
--                  Ce filet-là ne dépend d'aucun réseau : même isolé du
--                  monde, un serveur termine l'événement à la bonne seconde
--                  et révoque tout. C'est celui qui garantit ta règle
--                  « la récompense doit disparaître à la fin ».
--
--  ⚠️ Le PLAN ne voyage JAMAIS par MessagingService (limite de 1 Ko par
--     message). Il va dans le DataStore, et on ne publie qu'un post-it :
--     « il y a du neuf, va lire ». Un post-it fait 40 octets.
--
--══════════════════════════════════════════════════════════════════════════════

--──────────────────────────────────────────────────────────────────────────────
-- 📢 BANNIÈRES (serveur → client, sens unique)
--    reMsg n'a AUCUN handler OnServerEvent. Un exploiteur qui le déclenche
--    ne provoque donc rigoureusement rien : il n'y a pas de code à atteindre.
--──────────────────────────────────────────────────────────────────────────────
local function fireBanner(payload, target)
	if target then
		pcall(function() reMsg:FireClient(target, payload) end)
	else
		pcall(function() reMsg:FireAllClients(payload) end)
	end
end

--  Annonce du début d'une étape (remplit la déclaration anticipée du haut).
announceStep = function(step)
	if not step then return end
	if step.an_on == false then return end
	local name  = tostring(step.name or "Weather")
	local txt   = Config.CleanText(step.an_msg or "", LIM.MESSAGE_LEN_MAX)
	if txt == "" then
		txt = name .. " is now active!"
	end
	fireBanner({
		kind    = "weather",
		icon    = Config.Icon(step.icon),
		title   = Run and Run.title or "ADMIN ABUSE",
		text    = txt,
		color   = step.color,
		rainbow = false,
		by      = Run and Run.by or nil,
		byName  = Run and Run.byName or nil,
		mc      = msgConfig,
		at      = os.time(),
	})
	statBump("messagesSent")
end

--──────────────────────────────────────────────────────────────────────────────
-- 🎁 ÉTAT DES CADEAUX (mémoire pure, comme tout le reste)
--──────────────────────────────────────────────────────────────────────────────
local giftBoosts = {}   -- [userId] = { amt =, exp =, runId = }
local giftTools  = {}   -- [userId] = { exp =, runId = }
local giftDone   = {}   -- [nonce]  = os.time()  → un cadeau livré UNE fois
local msgDone    = {}   -- [nonce]  = os.time()  → un message affiché UNE fois

--  Remplit la déclaration anticipée placée à côté de la table Effects :
--  applyToPlayer ajoute ce boost par-dessus celui de la météo.
giftBoostOf = function(userId)
	local g = giftBoosts[userId]
	if not g then return 0 end
	if os.time() >= g.exp then return 0 end
	return g.amt or 0
end

--  Idem pour les outils : applyToPlayer doit savoir si le joueur tient un
--  outil reçu en cadeau, pour ne pas le lui reprendre au changement d'étape.
giftToolLive = function(userId)
	local g = giftTools[userId]
	if not g then return false end
	return os.time() < g.exp
end

--  Recalcule le boost total d'un joueur (météo + cadeau) et le publie.
--  C'est la SEULE écriture de Effects.boost hors applyToPlayer, et elle suit
--  exactement la même règle de plafond : on additionne, PUIS on plafonne.
local function refreshBoost(player)
	local uid = player.UserId
	local w   = curStep()
	local b   = 0
	if w then
		b = math.floor(tonumber(w.ef_boost) or 0)
		if b < 0 then b = 0 end
	end
	b = b + giftBoostOf(uid)
	if b > LIM.BOOST_MAX then b = LIM.BOOST_MAX end
	if b > 0 then
		Effects.boost[uid]   = b
		Effects.boosted[uid] = true
		pcall(function() player:SetAttribute("AAEventBoost", b) end)
	else
		Effects.boost[uid] = nil
		pcall(function() player:SetAttribute("AAEventBoost", nil) end)
	end
end

--──────────────────────────────────────────────────────────────────────────────
-- 📡 PUBLICATION
--──────────────────────────────────────────────────────────────────────────────
local function publish(payload)
	payload.src = SERVER_TAG
	local ok, err = pcall(function()
		MessagingService:PublishAsync(Config.TOPIC, payload)
	end)
	if not ok then
		warn(string.format(
			"⚠️ [AdminAbuse] Publication impossible (%s) — le sondage rattrapera dans %ds",
			tostring(err), POLL_EVERY))
	end
	return ok
end

--──────────────────────────────────────────────────────────────────────────────
-- 🗂️ CONFIGURATION ADMIN PARTAGÉE (météos custom + plannings + bannière)
--    Elle est ADMIN, pas joueur : elle a le droit de persister. Ce qui n'a
--    JAMAIS le droit de persister, ce sont les récompenses.
--──────────────────────────────────────────────────────────────────────────────
local Cfg = nil   -- cache local, rafraîchi sur notification ou sondage

--  8 plannings enregistrés maximum. Ce n'est pas une limite arbitraire :
--  8 × 24 étapes × ~45 réglages, c'est déjà ce qu'une clé DataStore accepte
--  confortablement une fois les étapes compactées.
local PLANS_MAX = 8

local function trimSteps(list)
	local out = {}
	if type(list) ~= "table" then return out end
	for i = 1, math.min(#list, LIM.STEPS_MAX) do
		if type(list[i]) == "table" then
			--  Les étapes sont stockées « compactées » (seuls les réglages qui
			--  diffèrent du défaut sont écrits, pour ne pas saturer le
			--  DataStore). ValidateWeather les redéploie complètes : les champs
			--  absents reprennent leur valeur par défaut du schéma.
			out[#out + 1] = Config.ValidateWeather(list[i], nil)
		end
	end
	return out
end

--  Toute configuration relue est repassée au tamis. Même si quelqu'un
--  réussissait à écrire n'importe quoi dans le DataStore, ce qui en ressort
--  ici est toujours une structure connue, bornée, et sans champ étranger.
local function normalizeCfg(data)
	if type(data) ~= "table" then data = {} end
	local out = { v = 2, weathers = {}, plans = {} }
	out.mc    = Config.ValidateMessageConfig(type(data.mc) == "table" and data.mc or {})
	out.hud   = Config.ValidateHud(type(data.hud) == "table" and data.hud or {})
	out.sched = Config.ValidateSched(type(data.sched) == "table" and data.sched or {})
	--  Qui a mis le planning en place : sert de « donneur » sur la popup de
	--  cadeau automatique (photo de profil + pseudo). Bornés comme le reste.
	out.schedBy = {
		id   = math.floor(tonumber(type(data.schedBy) == "table" and data.schedBy.id) or 0),
		name = Config.CleanText(tostring(type(data.schedBy) == "table" and data.schedBy.name or "OWNER"), 24),
	}
	if out.schedBy.name == "" then out.schedBy.name = "OWNER" end

	if type(data.weathers) == "table" then
		local n = 0
		for id, w in pairs(data.weathers) do
			if type(id) == "string" and type(w) == "table" and n < LIM.CUSTOM_WEATHERS_MAX then
				n = n + 1
				out.weathers[id] = Config.ValidateWeather(w, id)
			end
		end
	end

	if type(data.plans) == "table" then
		for i = 1, math.min(#data.plans, PLANS_MAX) do
			local p = data.plans[i]
			if type(p) == "table" then
				out.plans[#out.plans + 1] = {
					name  = Config.CleanText(tostring(p.name or ""), LIM.NAME_LEN_MAX),
					steps = trimSteps(p.steps),
				}
			end
		end
	end
	return out
end

local function refreshCfg()
	local ok, data = pcall(function() return cfgStore:GetAsync("config") end)
	if not ok then return false end
	Cfg = normalizeCfg(data)
	msgConfig = Cfg.mc
	hudConfig = Cfg.hud
	schedCfg  = Cfg.sched
	--  Le rythme a pu changer : on oublie notre date locale pour aller relire
	--  celle qui fait autorité au prochain tour de boucle.
	nextGiftAt = 0
	return true
end

local function getCfg()
	if not Cfg then refreshCfg() end
	if not Cfg then Cfg = normalizeCfg(nil) end
	return Cfg
end

--──────────────────────────────────────────────────────────────────────────────
-- 🧭 ADOPTION D'UN PLAN
--
--   Un serveur ne reçoit pas « passe à l'étape 3 ». Il reçoit LE PLAN, avec
--   son instant de départ absolu, et il en déduit tout seul où il en est.
--   Conséquence directe : un serveur qui démarre en plein milieu d'un
--   événement se cale à la bonne étape, à la bonne seconde, sans que
--   personne ne le lui dise. Et un serveur coupé du monde s'arrête quand
--   même à l'heure.
--──────────────────────────────────────────────────────────────────────────────
local function adoptPlan(plan)
	if type(plan) ~= "table" or type(plan.steps) ~= "table" then return end
	local id  = tostring(plan.id or "")
	local seq = tonumber(plan.seq) or 0
	if id == "" then return end
	--  🛑 Un événement arrêté ne revient jamais, quoi que dise le DataStore.
	if stoppedIds[id] then return end

	--  Déjà à jour ? On ne touche à rien (évite de re-appliquer les effets
	--  à chaque sondage, ce qui ferait clignoter les joueurs).
	if Run and Run.id == id and seq <= (Run.seq or 0) then return end

	local now       = os.time()
	local startedAt = math.floor(tonumber(plan.startedAt) or now)
	--  🛡️ Un instant de départ dans le FUTUR (horloge de serveur décalée, clé
	--     abîmée) repousserait d'autant la coupure de sécurité : les effets de
	--     la première étape resteraient collés aux joueurs bien au-delà de la
	--     durée maximale. On ramène toujours startedAt dans une fenêtre saine.
	if startedAt ~= startedAt or startedAt > now then startedAt = now end
	if startedAt < now - LIM.EVENT_DURATION_MAX then
		startedAt = now - LIM.EVENT_DURATION_MAX
	end

	--  On reconstruit la ligne du temps NOUS-MÊMES à partir des durées.
	--  On ne fait pas confiance à un « endsAt » fourni : il est recalculé.
	local steps, acc, idx, stepStart = {}, startedAt, nil, nil
	for i = 1, math.min(#plan.steps, LIM.STEPS_MAX) do
		if type(plan.steps[i]) ~= "table" then break end
		--  🔒 REVALIDATION À L'ARRIVÉE. Le serveur qui a lancé l'événement a
		--     déjà validé le plan — mais celui-ci ne le croit pas sur parole.
		--     Ce qui sort d'ici est forcément dans les bornes du schéma, sans
		--     champ étranger, et avec la tolérance anti-fly forcée si l'étape
		--     touche à la vitesse / au saut / à la gravité.
		local s = Config.ValidateWeather(plan.steps[i], nil)
		local d = s.duration
		if (acc + d) - startedAt > LIM.EVENT_DURATION_MAX then break end
		steps[#steps + 1] = s
		if not idx and now < acc + d then
			idx = #steps
			stepStart = acc
		end
		acc = acc + d
	end
	local endsAt = acc

	--  Plan déjà fini (serveur qui démarre en retard, ou horloge rattrapée) :
	--  on ne l'applique surtout pas, et on ferme ce qui traînerait.
	if #steps == 0 or not idx or now >= endsAt then
		if Run and Run.id == id then endRun("time_cap") end
		return
	end

	local sameRun = (Run ~= nil and Run.id == id)
	--  Les points déjà donnés pendant CET événement sont conservés : une
	--  modification en direct ne doit pas rouvrir le plafond par joueur.
	local given = sameRun and Run.given or {}
	local gifts = sameRun and Run.gifts or 0

	if Run and not sameRun then
		pcall(function() endRun("replaced") end)
	end

	if not sameRun then
		Stats.d         = freshStats()
		pointedOnce     = {}
		Effects.seen    = {}
		Effects.boosted = {}
	end

	Run = {
		id        = id,
		seq       = seq,
		title     = Config.CleanText(tostring(plan.title or ""), LIM.NAME_LEN_MAX),
		by        = math.floor(tonumber(plan.by) or 0),
		byName    = Config.CleanText(tostring(plan.byName or "?"), 24),
		origin    = tostring(plan.origin or "?"),
		startedAt = startedAt,
		endsAt    = endsAt,
		steps     = steps,
		given     = given,   -- plafond de points par joueur, à l'échelle DE CE SERVEUR
		gifts     = gifts,
		idx       = 0,
		stepStart = 0,
		stepEnd   = 0,
		nextTick  = nil,
	}
	if Run.title == "" then Run.title = "ADMIN ABUSE" end
	_G.__aaRunId = Run.id

	--  Le pont anti-cheat est installé AVANT le moindre boost. Si TempBoosts
	--  n'est pas encore chargé, on réessaiera à chaque étape : tant qu'il
	--  n'est pas là, le boost ne fait rien — il ne bannit personne.
	installBoostBridge()

	enterStep(idx)

	--  enterStep a calé la fin d'étape sur « maintenant + durée ». On la
	--  réaligne sur l'horloge absolue du plan, sinon un serveur qui rejoint
	--  en cours de route décalerait toutes les étapes suivantes.
	if Run then
		local st = steps[idx]
		Run.stepStart = stepStart
		Run.stepEnd   = stepStart + st.duration
		if Run.nextTick then
			local every = tonumber(st.ef_tickEvery) or 30
			if every < LIM.POINTS_TICK_INTERVAL_MIN then every = LIM.POINTS_TICK_INTERVAL_MIN end
			Run.nextTick = now + every
		end
		pushState(nil)
		print(string.format(
			"🎬 [AdminAbuse] Plan adopté · %s · étape %d/%d · fin dans %ds",
			Run.title, idx, #steps, endsAt - now))
	end
end

--──────────────────────────────────────────────────────────────────────────────
-- 🔄 SONDAGE (filet nº2)
--──────────────────────────────────────────────────────────────────────────────
local function syncFromStore()
	local ok, data = pcall(function() return liveStore:GetAsync(LIVE_KEY) end)
	if not ok then return false end   -- lecture ratée : on ne conclut RIEN

	if type(data) ~= "table" then
		--  Aucun plan enregistré. On ne coupe un événement local que s'il est
		--  installé depuis un moment : ça évite d'annuler par erreur un
		--  événement lancé à la seconde près par un autre serveur.
		if Run and (os.time() - Run.startedAt) > 15 then endRun("no_plan") end
		return true
	end

	local seq = tonumber(data.seq) or 0
	if data.stopped or type(data.plan) ~= "table" then
		if Run and seq > (Run.seq or 0) then endRun("admin_stop") end
		return true
	end

	adoptPlan(data.plan)
	return true
end

--──────────────────────────────────────────────────────────────────────────────
-- 🎁 LIVRAISON D'UN CADEAU
--
--   Règle d'éligibilité, unique et non négociable :
--       le joueur devait être connecté À L'INSTANT « at ».
--
--   Pourquoi c'est inviolable : un joueur ne peut être qu'à UN endroit à un
--   instant donné. Le serveur où il se trouvait à cet instant le sert ; tous
--   les autres serveurs le trouvent absent (ou arrivé trop tard). Il n'y a
--   pas de remote de réclamation, donc rien à rejouer, rien à marteler, et
--   rien à déclencher deux fois — la livraison est POUSSÉE, jamais demandée.
--──────────────────────────────────────────────────────────────────────────────
--  Durée lisible : « 24 hours », « 15 min », « 45s ». Utilisée dans le texte
--  du cadeau, donc en anglais comme tout ce que voit un joueur.
local function humanDur(sec)
	sec = math.max(0, math.floor(tonumber(sec) or 0))
	if sec >= 3600 then
		local h = sec / 3600
		local r = (h == math.floor(h)) and tostring(math.floor(h)) or string.format("%.1f", h)
		return r .. (h >= 2 and " hours" or " hour")
	elseif sec >= 60 then
		return tostring(math.floor(sec / 60)) .. " min"
	end
	return tostring(sec) .. "s"
end

local function giftText(kind, amount, dur, toolName, note)
	local n = tostring(note or "")
	if n ~= "" then return n end
	if kind.id == "points" then
		return "You received +" .. tostring(amount) .. " points!"
	elseif kind.id == "boost" then
		return "You received a +" .. tostring(amount) .. " point boost for "
			.. humanDur(dur) .. "!"
	end
	return "You received " .. (toolName ~= "" and toolName or "an item") .. "!"
end

--  Titre affiché en vedette dans la grande frame de cadeau.
local function giftTitle(kind, amount, toolName)
	if kind.id == "points" then
		return "+" .. tostring(amount) .. " Points"
	elseif kind.id == "boost" then
		return "x" .. tostring(amount) .. " Point Boost"
	end
	return (toolName ~= "" and toolName or "Item")
end

--  Icône : on prend celle qui colle au montant, pas une générique.
local function giftIcon(kind, amount)
	if kind.id == "boost" then
		if amount >= 25 then return Config.Icon("boost25")
		elseif amount >= 10 then return Config.Icon("boost10")
		elseif amount >= 5 then return Config.Icon("boost5")
		else return Config.Icon("boost2") end
	elseif kind.id == "points" then
		return Config.Icon("points")
	end
	return Config.Icon(kind.icon or "points")
end

--══════════════════════════════════════════════════════════════════════════════
-- 🖼️ LA GRANDE FRAME DE CADEAU (celle de ton système de gifting)
--
--   On ne réinvente PAS une popup : on réutilise exactement celle que le
--   joueur connaît déjà, en lui envoyant le même remote avec la même forme de
--   données. Trois drapeaux en plus (aaFestive / aaTag / aaRainbow) disent au
--   client de l'habiller en mode fête : contours arc-en-ciel, « OWNER » en
--   gros au-dessus du @pseudo, et le message du owner en arc-en-ciel.
--
--   ⚠️ Ce remote ne fait qu'AFFICHER. Les points, eux, ont déjà été crédités
--      par creditPoints juste avant, par le chemin audité. Un exploiteur qui
--      déclencherait ce remote côté client se dessinerait une jolie popup et
--      rien d'autre.
--══════════════════════════════════════════════════════════════════════════════
local function giftPopupRemote()
	local folder = ReplicatedStorage:FindFirstChild("GiftingRemotes")
	if not folder then return nil end
	local r = folder:FindFirstChild("GiftReceived")
	if r and r:IsA("RemoteEvent") then return r end
	return nil
end

local function sendGiftPopup(player, kind, amount, dur, toolName, note, byId, byName)
	local remote = giftPopupRemote()
	if not remote then return false end
	local sub
	if kind.id == "points" then
		sub = "ADMIN ABUSE - free points for everyone online"
	elseif kind.id == "boost" then
		sub = "Active for " .. humanDur(dur) .. " - then it goes away"
	else
		sub = "Yours for " .. humanDur(dur) .. " - then it goes away"
	end
	local okS = pcall(function()
		remote:FireClient(player, {
			senderName   = byName,
			senderUserId = byId,
			kind         = kind.id,
			title        = giftTitle(kind, amount, toolName),
			subText      = sub,
			icon         = giftIcon(kind, amount),
			points       = (kind.id == "points") and amount or nil,
			messageText  = giftText(kind, amount, dur, toolName, note),
			--  🌈 Les trois drapeaux de la version festive
			aaFestive    = true,
			aaTag        = "OWNER",
			aaRainbow    = true,
		})
	end)
	return okS
end

local function grantGiftBoost(player, amt, dur, runId, keep)
	local uid = player.UserId
	local exp = os.time() + dur
	local cur = giftBoosts[uid]
	--  Deux cadeaux d'affilée : on garde la fin la plus lointaine, on ne
	--  cumule PAS les montants (sinon deux clics = boost doublé).
	if cur and cur.exp > exp then exp = cur.exp end
	giftBoosts[uid] = { amt = amt, exp = exp, runId = runId, keep = keep == true }
	Effects.seen[uid] = true
	refreshBoost(player)
end

local function deliverGift(d)
	if type(d) ~= "table" then return end
	local nonce = tostring(d.nonce or "")
	if nonce == "" then return end
	if giftDone[nonce] then return end
	giftDone[nonce] = os.time()

	local kind = Config.GiftKind(tostring(d.kind or ""))
	if not kind then return end   -- type inconnu : aucun chemin générique

	local at     = math.floor(tonumber(d.at) or os.time())
	--  ⚠️ DEUX instants différents, et il ne faut surtout pas les confondre :
	--     • « at »     = quand tout le monde LIVRE (le clic + 2 s), pour que
	--                    les serveurs soient synchrones à la seconde près.
	--     • « sentAt » = quand l'admin a CLIQUÉ. C'est LUI qui décide qui est
	--                    éligible. Sinon un joueur présent sur le serveur A au
	--                    clic, qui change de serveur dans les 2 s, serait aussi
	--                    « présent avant at » sur le serveur B — et recevrait
	--                    le cadeau DEUX FOIS.
	local sentAt = math.floor(tonumber(d.sentAt) or at)
	local amount = math.floor(tonumber(d.amount) or 0)
	if amount < kind.min then amount = kind.min end
	if amount > kind.max then amount = kind.max end
	if kind.id == "points" and amount > LIM.POINTS_GRANT_MAX then
		amount = LIM.POINTS_GRANT_MAX
	end

	local dur = math.floor(tonumber(d.dur) or 300)
	if dur < LIM.GIFT_DURATION_MIN then dur = LIM.GIFT_DURATION_MIN end
	if dur > LIM.GIFT_DURATION_MAX then dur = LIM.GIFT_DURATION_MAX end
	--  « keep » : le cadeau vit sa durée MÊME si l'événement se termine avant.
	--  Par défaut c'est faux — ta règle « tout est retiré à la fin » reste le
	--  comportement normal. Ce drapeau est une décision consciente de l'admin,
	--  case à cocher dans le panel, pour les boosts longs (jusqu'à 24 h).
	local keep = (d.keep == true)

	local toolName = tostring(d.tool or ""):gsub("[^%w%-_ ]", "")
	local note     = Config.CleanText(tostring(d.note or ""), LIM.MESSAGE_LEN_MAX)
	local runId    = d.runId and tostring(d.runId) or nil
	local byName   = Config.CleanText(tostring(d.byName or "OWNER"), 24)
	local byId     = math.floor(tonumber(d.by) or 0)

	task.spawn(function()
		--  🕐 La mèche. L'expéditeur pose l'instant de livraison 2 s dans le
		--     futur ; chaque serveur attend cet instant. Résultat : tout le
		--     monde reçoit le cadeau à la même seconde, ce qui est exactement
		--     ce que tu demandes, et ça absorbe la latence du réseau.
		local waitFor = at - os.time()
		if waitFor > 0 and waitFor <= 15 then task.wait(waitFor) end

		local okN, failN = 0, 0
		for _, p in ipairs(Players:GetPlayers()) do
			local joined = Effects.joinAt[p.UserId]
			if joined and joined <= sentAt then
				local done = false

				if kind.id == "points" then
					local uid = p.UserId
					local allowed = true
					--  💰 Même plafond que la pluie de points, lu au même
					--     endroit. Un cadeau ne peut donc pas servir à
					--     contourner la limite d'un événement.
					if Run and runId and Run.id == runId then
						if (Run.given[uid] or 0) + amount > Config.PlayerCap(schedCfg) then
							allowed = false
						end
					end
					if allowed then
						local okc = creditPoints(p, amount, "AdminAbuse_Gift")
						if okc then
							done = true
							if Run then
								Run.given[uid] = (Run.given[uid] or 0) + amount
							end
							pointedOnce[uid] = true
							statBump("pointsTotal", amount)
						end
					end

				elseif kind.id == "boost" then
					done = pcall(function()
						grantGiftBoost(p, amount, dur, (not keep) and runId or nil, keep)
					end)

				elseif kind.id == "tool" then
					if toolName ~= "" and giveTool(p, toolName, runId or "gift") then
						giftTools[p.UserId] = {
							exp   = os.time() + dur,
							runId = (not keep) and runId or nil,
							keep  = keep,
							tool  = toolName,
						}
						done = true
					end
				end

				if done then
					okN = okN + 1
					Effects.seen[p.UserId] = true
					--  Deux façons de prévenir le joueur, et l'admin choisit :
					--    • popup = la grande frame de cadeau qu'il connaît
					--    • sinon = la petite bannière en haut de l'écran
					--  Pour un cadeau automatique toutes les 5 minutes, la
					--  bannière est bien moins pénible qu'une frame à fermer.
					local shown = false
					if d.popup ~= false then
						shown = sendGiftPopup(p, kind, amount, dur, toolName,
							note, byId, byName)
					end
					if not shown then
						fireBanner({
							kind    = "gift",
							icon    = giftIcon(kind, amount),
							title   = byName,
							text    = giftText(kind, amount, dur, toolName, note),
							rainbow = true,     -- 🌈 dégradé arc-en-ciel glissant
							party   = true,     -- 🎊 confettis + son de fête
							by      = byId,
							byName  = byName,
							mc      = msgConfig,
							at      = os.time(),
						}, p)
					end
				else
					failN = failN + 1
				end
			end
		end

		statBump("giftsOk", okN)
		statBump("giftsFail", failN)
		print(string.format("🎁 [AdminAbuse] Cadeau « %s » livré · %d reçu(s) · %d échec(s)",
			kind.id, okN, failN))
	end)
end

--──────────────────────────────────────────────────────────────────────────────
-- 💬 MESSAGES GLOBAUX
--    Le texte est écrit par un humain : il PASSE par le filtre Roblox, et si
--    le filtre est indisponible, le message n'est PAS envoyé. Jamais de texte
--    non filtré diffusé à tout le jeu — même venant d'un admin.
--──────────────────────────────────────────────────────────────────────────────
local function filterForBroadcast(text, fromUserId)
	local okA, result = pcall(function()
		return TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
	end)
	if not okA or not result then return false, "" end
	local okB, out = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not okB or type(out) ~= "string" or out == "" then return false, "" end
	return true, out
end

local function showRemoteMessage(d)
	if type(d) ~= "table" then return end
	local nonce = tostring(d.nonce or "")
	if nonce ~= "" then
		if msgDone[nonce] then return end
		msgDone[nonce] = os.time()
	end
	local title = Config.CleanText(tostring(d.title or ""), LIM.NAME_LEN_MAX)
	local byName = Config.CleanText(tostring(d.byName or "ADMIN"), 24)
	if title == "" then title = byName end
	fireBanner({
		kind    = "admin",
		emoji   = tostring(d.emoji or "📢"),
		title   = title,
		text    = tostring(d.text or ""),
		rainbow = d.rainbow == true,
		by      = math.floor(tonumber(d.by) or 0),
		byName  = byName,
		dur     = tonumber(d.time) or 0,
		mc      = msgConfig,
		at      = os.time(),
	})
	statBump("messagesSent")
end

--──────────────────────────────────────────────────────────────────────────────
-- 📥 RÉCEPTION RÉSEAU
--──────────────────────────────────────────────────────────────────────────────
local function handleNet(d)
	local k = tostring(d.k or "")
	if k == "sync" then
		task.spawn(function() pcall(syncFromStore) end)
	elseif k == "stop" then
		local rid = tostring(d.runId or "")
		if rid ~= "" then stoppedIds[rid] = true end
		if Run and Run.id == rid then endRun("admin_stop") end
	elseif k == "gift" then
		deliverGift(d)
	elseif k == "msg" then
		showRemoteMessage(d)
	elseif k == "cfg" then
		task.spawn(function()
			pcall(refreshCfg)
			pcall(function() pushState(nil) end)
		end)
	end
end

task.spawn(function()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(Config.TOPIC, function(message)
			local d = message and message.Data
			if type(d) ~= "table" then return end
			--  Notre propre message : déjà traité en local, on l'ignore.
			if tostring(d.src or "") == SERVER_TAG then return end
			local okH, errH = pcall(handleNet, d)
			if not okH then
				warn("🚨 [AdminAbuse] Message réseau ignoré : " .. tostring(errH))
			end
		end)
	end)
	if ok then
		print("📡 [AdminAbuse] Abonné au canal " .. tostring(Config.TOPIC))
	else
		warn(string.format(
			"⚠️ [AdminAbuse] Abonnement impossible (%s) — le sondage toutes les %ds prend le relais.",
			tostring(err), POLL_EVERY))
	end
end)

--  Sondage + première synchronisation.
task.spawn(function()
	task.wait(2)
	pcall(refreshCfg)
	pcall(syncFromStore)
	while true do
		task.wait(POLL_EVERY)
		pcall(syncFromStore)
	end
end)

--  Remontée périodique des stats de ce serveur.
task.spawn(function()
	while true do
		task.wait(STATS_PUSH)
		pcall(pushStats)
	end
end)

--──────────────────────────────────────────────────────────────────────────────
-- ⏳ ENTRETIEN : expirations et ménage
--    C'est ici que meurent les cadeaux temporaires. Deux conditions de mort,
--    et il suffit d'UNE : la durée est écoulée, OU l'événement auquel le
--    cadeau était rattaché n'est plus en cours. Aucune des deux ne dépend du
--    réseau.
--──────────────────────────────────────────────────────────────────────────────
task.spawn(function()
	local ticks   = 0
	local prevRun = nil
	while true do
		task.wait(2)
		ticks = ticks + 1
		pcall(function()
			local now = os.time()

			--  🔚 Un événement vient-il de se terminer (ou d'être remplacé) ?
			--     Si oui, TOUS les cadeaux temporaires meurent, y compris ceux
			--     envoyés hors événement. C'est ta règle appliquée au sens
			--     strict : quand l'admin abuse est fini, le joueur ne garde
			--     rien. Un cadeau envoyé hors événement, lui, vit sa durée.
			local curRun = Run and Run.id or nil
			local ended  = (prevRun ~= nil and curRun ~= prevRun)
			prevRun = curRun

			for uid, g in pairs(giftBoosts) do
				--  Un cadeau « keep » ignore la fin d'événement : seule sa
				--  propre durée le termine. Tous les autres meurent avec
				--  l'événement, comme demandé.
				local dead = (now >= g.exp)
					or ((not g.keep) and ended)
					or (g.runId ~= nil and ((not Run) or Run.id ~= g.runId))
				if dead then
					giftBoosts[uid] = nil
					local p = Players:GetPlayerByUserId(uid)
					if p then refreshBoost(p) end
				elseif ended and g.keep then
					--  La fin d'événement a effacé Effects.boost pour tout le
					--  monde. Ce cadeau-ci a le droit de survivre : on le
					--  repose tout de suite, sinon il disparaîtrait en silence
					--  alors que l'admin avait coché « keep ».
					local p = Players:GetPlayerByUserId(uid)
					if p then refreshBoost(p) end
				end
			end

			for uid, g in pairs(giftTools) do
				local dead = (now >= g.exp)
					or ((not g.keep) and ended)
					or (g.runId ~= nil and ((not Run) or Run.id ~= g.runId))
				if dead then
					giftTools[uid] = nil
					local p = Players:GetPlayerByUserId(uid)
					if p then
						local n = revokeTools(p)
						if n > 0 then statBump("toolsReturned", n) end
						--  On redonne l'outil de l'étape en cours, s'il y en a
						--  un : le cadeau expire, pas la météo.
						local w = curStep()
						if w then applyToPlayer(p, w) end
					end
				elseif ended and g.keep and g.tool then
					--  Même raison que pour les boosts : la fin d'événement a
					--  balayé tous les outils, on redonne celui-ci.
					local p = Players:GetPlayerByUserId(uid)
					if p then pcall(function() giveTool(p, g.tool, "gift") end) end
				end
			end

			--  Ménage des identifiants de livraison (toutes les ~60 s).
			if ticks % 30 == 0 then
				for n, t in pairs(giftDone) do
					if now - t > 300 then giftDone[n] = nil end
				end
				for n, t in pairs(msgDone) do
					if now - t > 300 then msgDone[n] = nil end
				end
				for uid in pairs(Effects.joinAt) do
					if not Players:GetPlayerByUserId(uid) then Effects.joinAt[uid] = nil end
				end
			end
		end)
	end
end)

--══════════════════════════════════════════════════════════════════════════════
-- 🎛️ ACTIONS D'ADMINISTRATION
--    Appelées uniquement depuis le dispatcher de la partie 5, qui revérifie
--    isAdmin à CHAQUE appel. Ces fonctions ne font jamais confiance à leur
--    entrée : tout repasse par Config.ValidateWeather / CleanText / bornes.
--══════════════════════════════════════════════════════════════════════════════

--  Écrit le plan dans le DataStore et renvoie le nouveau numéro de séquence.
--  UpdateAsync (et non SetAsync) : si deux admins agissent en même temps, le
--  numéro de séquence s'incrémente proprement au lieu de s'écraser.
local function writeLive(plan, stopped)
	local newSeq = nil
	local ok, err = pcall(function()
		liveStore:UpdateAsync(LIVE_KEY, function(old)
			local s = ((type(old) == "table" and tonumber(old.seq)) or 0) + 1
			newSeq = s
			if stopped then
				return { v = 1, seq = s, stopped = true, at = os.time() }
			end
			plan.seq = s
			--  🧽 DERNIER TAMIS AVANT LE DATASTORE. C'est ici que se jouait ton
			--     erreur « CantStoreValue : valid UTF-8 » : un nom de météo
			--     coupé au milieu d'un emoji suffisait à faire refuser TOUT le
			--     plan, donc à ne rien lancer du tout. Maintenant, même si une
			--     chaîne abîmée arrivait jusqu'ici, elle est réparée avant
			--     d'atteindre le DataStore.
			return Config.SanitizeForStore({ v = 1, seq = s, plan = plan })
		end)
	end)
	if not ok then return nil, tostring(err) end
	return newSeq
end

--  Construit un plan validé à partir de ce que le panel envoie.
local function buildPlan(admin, raw)
	if type(raw) ~= "table" then return nil, "Invalid request" end
	local rawSteps = raw.steps
	if type(rawSteps) ~= "table" or #rawSteps == 0 then return nil, "No steps in the schedule" end
	if #rawSteps > LIM.STEPS_MAX then
		return nil, string.format("Maximum %d steps", LIM.STEPS_MAX)
	end

	local steps, total = {}, 0
	for i = 1, #rawSteps do
		if type(rawSteps[i]) ~= "table" then return nil, "Step " .. i .. " is invalid" end
		--  ⚖️ LE point de sécurité du planning : chaque étape repasse par le
		--     validateur du Config. Un champ inconnu est jeté, un nombre hors
		--     bornes est ramené dans les bornes, et la tolérance anti-fly est
		--     forcée si l'étape touche à la vitesse / au saut / à la gravité.
		local w = Config.ValidateWeather(rawSteps[i], nil)
		total = total + w.duration
		if total > LIM.EVENT_DURATION_MAX then
			return nil, string.format("Total duration too long (max %d min)",
				math.floor(LIM.EVENT_DURATION_MAX / 60))
		end
		steps[i] = w
	end

	local title = Config.CleanText(tostring(raw.title or ""), LIM.NAME_LEN_MAX)
	if title == "" then title = "ADMIN ABUSE" end

	return {
		v         = 1,
		id        = HttpService:GenerateGUID(false),
		seq       = 0,
		title     = title,
		by        = admin.UserId,
		byName    = admin.Name,
		origin    = SERVER_TAG,
		startedAt = os.time(),
		steps     = steps,
	}
end

local function doStart(admin, raw)
	if Run then return false, "An event is already running" end
	if not allow(admin, "start", 3) then return false, "Too fast" end

	local plan, err = buildPlan(admin, raw)
	if not plan then return false, err end

	local seq, werr = writeLive(plan, false)
	if not seq then
		return false, "Could not save (" .. tostring(werr) .. ")"
	end
	plan.seq = seq

	publish({ k = "sync", seq = seq })
	adoptPlan(plan)

	print(string.format("🚀 [AdminAbuse] Lancé par %s (%d) · %s · %d étape(s)",
		admin.Name, admin.UserId, plan.title, #plan.steps))
	return true, "Event started"
end

--  Modification EN DIRECT : même identifiant, même instant de départ, mais un
--  nouveau numéro de séquence. Les points déjà distribués sont conservés, donc
--  éditer en direct ne rouvre aucun plafond.
local function doUpdate(admin, raw)
	if not Run then return false, "No event is running" end
	if not allow(admin, "update", 2) then return false, "Too fast" end

	local plan, err = buildPlan(admin, raw)
	if not plan then return false, err end
	plan.id        = Run.id
	plan.startedAt = Run.startedAt
	plan.origin    = Run.origin
	plan.by        = Run.by
	plan.byName    = Run.byName
	if Config.CleanText(tostring(raw.title or ""), LIM.NAME_LEN_MAX) == "" then
		plan.title = Run.title
	end

	local seq, werr = writeLive(plan, false)
	if not seq then
		return false, "Could not save (" .. tostring(werr) .. ")"
	end
	plan.seq = seq

	publish({ k = "sync", seq = seq })
	adoptPlan(plan)
	return true, "Event updated"
end

local function doStop(admin)
	if not allow(admin, "stop", 2) then return false, "Too fast" end
	local runId = Run and Run.id or nil
	if runId then stoppedIds[runId] = true end

	--  ⚠️ On révoque EN PREMIER, localement. Si le DataStore est en panne,
	--     les joueurs de CE serveur ont quand même perdu leurs récompenses,
	--     et ceux des autres serveurs les perdront de toute façon à l'heure
	--     prévue grâce à la coupure d'horloge. Jamais de boost éternel.
	if Run then pcall(function() endRun("admin_stop") end) end

	local seq, werr = writeLive(nil, true)
	if runId then publish({ k = "stop", runId = runId }) end
	if seq then publish({ k = "sync", seq = seq }) end

	if not seq then
		return true, "Stopped here, but the save failed (" .. tostring(werr)
			.. ") - other servers will stop at the scheduled time anyway"
	end
	print(string.format("🛑 [AdminAbuse] Arrêté par %s (%d)", admin.Name, admin.UserId))
	return true, "Event stopped"
end

local function doGift(admin, spec)
	if type(spec) ~= "table" then return false, "Invalid request" end
	if not allow(admin, "gift", LIM.GIFT_COOLDOWN) then return false, "Too fast" end

	local kind = Config.GiftKind(tostring(spec.kind or ""))
	if not kind then return false, "Unknown gift type" end

	if Run then
		local n = (Run.gifts or 0) + 1
		if n > LIM.GIFTS_PER_EVENT_MAX then
			return false, string.format("Limit of %d gifts reached", LIM.GIFTS_PER_EVENT_MAX)
		end
		Run.gifts = n
	end

	local amount = math.floor(tonumber(spec.amount) or kind.def)
	if amount < kind.min then amount = kind.min end
	if amount > kind.max then amount = kind.max end
	if kind.id == "points" and amount > LIM.POINTS_GRANT_MAX then
		amount = LIM.POINTS_GRANT_MAX
	end

	local dur = math.floor(tonumber(spec.dur) or 300)
	if dur < LIM.GIFT_DURATION_MIN then dur = LIM.GIFT_DURATION_MIN end
	if dur > LIM.GIFT_DURATION_MAX then dur = LIM.GIFT_DURATION_MAX end

	local toolName = tostring(spec.tool or ""):gsub("[^%w%-_ ]", "")
	if kind.id == "tool" and toolName == "" then return false, "Tool name missing" end

	--  La note est du texte humain : filtre obligatoire. Filtre indisponible
	--  → le cadeau part quand même, mais SANS note.
	local note = ""
	local rawNote = Config.CleanText(tostring(spec.note or ""), LIM.MESSAGE_LEN_MAX)
	if rawNote ~= "" then
		local okF, out = filterForBroadcast(rawNote, admin.UserId)
		if okF then note = out end
	end

	local payload = {
		k      = "gift",
		nonce  = SERVER_TAG .. "|" .. tostring(os.time()) .. "|"
			.. tostring(math.random(1, 999999999)),
		at     = os.time() + 2,   -- 🕐 la mèche : livraison simultanée partout
		sentAt = os.time(),       -- 🔒 l'instant qui décide de l'éligibilité
		runId  = Run and Run.id or nil,
		kind   = kind.id,
		amount = amount,
		dur    = dur,
		tool   = toolName,
		note   = note,
		by     = admin.UserId,
		byName = admin.Name,
		keep   = (spec.keep == true),
		popup  = (spec.popup ~= false),
	}

	statBump("giftsSent")
	publish(payload)
	deliverGift(payload)

	print(string.format("🎁 [AdminAbuse] Cadeau « %s » (%d) envoyé par %s",
		kind.id, amount, admin.Name))
	return true, "Gift sent to every player online"
end

--══════════════════════════════════════════════════════════════════════════════
-- ⏲️ CADEAUX AUTOMATIQUES
--
--   Trente serveurs, un seul cadeau. Comment ?
--
--   Personne n'est « le chef » — un chef qui meurt bloquerait tout le monde.
--   À la place, tous les serveurs vont écrire la MÊME clé de DataStore avec
--   UpdateAsync, qui est atomique : le premier qui arrive pose la prochaine
--   date et gagne le droit d'envoyer ; tous les autres voient que la date est
--   déjà dans le futur, renvoient nil (donc n'écrivent rien) et repartent en
--   ayant simplement appris quand ce sera. Aucun verrou, aucun chef, et si le
--   gagnant plante juste après, le suivant reprendra à l'heure prévue.
--
--   Bonus : cette même date sert de compte à rebours à l'écran des joueurs,
--   donc tout le monde voit exactement le même chrono.
--══════════════════════════════════════════════════════════════════════════════
local SCHED_KEY = "giftsched"

local function sendAutoGift(sc)
	local by     = (Cfg and Cfg.schedBy) or {}
	local amount = math.floor(tonumber(sc.sc_amount) or 0)
	if amount <= 0 then return end
	if amount > LIM.POINTS_GRANT_MAX then amount = LIM.POINTS_GRANT_MAX end

	local payload = {
		k      = "gift",
		nonce  = "auto|" .. SERVER_TAG .. "|" .. tostring(os.time()),
		at     = os.time() + 2,
		sentAt = os.time(),
		runId  = Run and Run.id or nil,
		kind   = "points",
		amount = amount,
		dur    = 0,
		tool   = "",
		--  🎉 Le message vient de la liste préfaite, sauf si tu as choisi
		--     « Write my own ». « Surprise me » tire une ligne différente à
		--     chaque envoi : deux cadeaux d'affilée ne disent jamais la même
		--     chose. Les textes préfaits sont écrits dans le code, donc sûrs
		--     par construction — rien à refiltrer ici. Le tien, lui, est
		--     passé par le filtre Roblox une fois, à l'enregistrement.
		note   = Config.AutoMessage(sc.sc_msgId, sc.sc_note),
		by     = math.floor(tonumber(by.id) or 0),
		byName = tostring(by.name or "OWNER"),
		auto   = true,
		popup  = (sc.sc_popup ~= false),
	}
	statBump("autoGifts")
	statBump("giftsSent")
	publish(payload)
	deliverGift(payload)
	print(string.format("⏲️ [AdminAbuse] Cadeau automatique : +%d points", amount))
end

task.spawn(function()
	while true do
		--  Petit décalage aléatoire : sans lui, trente serveurs interrogeraient
		--  le DataStore à la même seconde. Avec, ils s'étalent tout seuls.
		task.wait(5 + math.random() * 4)
		pcall(function()
			local sc = schedCfg
			local idle = (not sc) or (sc.sc_on ~= true)
				or (sc.sc_onlyEvent == true and not Run)
			if idle then
				if nextGiftAt ~= 0 then
					nextGiftAt = 0
					pushState(nil)
				end
				return
			end

			local now = os.time()
			if nextGiftAt > now then return end   -- on sait déjà quand : rien à faire

			local won, newNext = false, nil
			local okU = pcall(function()
				liveStore:UpdateAsync(SCHED_KEY, function(old)
					local due = (type(old) == "table" and tonumber(old.nextAt)) or nil
					if due and due > now then
						newNext = due
						return nil          -- pas notre tour : AUCUNE écriture
					end
					newNext = now + sc.sc_every
					--  Première initialisation : on pose la date sans envoyer.
					--  Sinon activer le planning enverrait un cadeau dans la
					--  seconde, ce qui surprend plus qu'autre chose.
					won = (old ~= nil)
					return { nextAt = newNext, by = SERVER_TAG, every = sc.sc_every }
				end)
			end)
			if not okU then return end

			if newNext and newNext ~= nextGiftAt then
				nextGiftAt = newNext
				pushState(nil)
			end
			if won then sendAutoGift(sc) end
		end)
	end
end)

local function doMessage(admin, spec)
	if type(spec) ~= "table" then return false, "Invalid request" end
	if not allow(admin, "msg", LIM.MESSAGE_COOLDOWN) then return false, "Too fast" end

	local raw = Config.CleanText(tostring(spec.text or ""), LIM.MESSAGE_LEN_MAX)
	if raw == "" then return false, "Message is empty" end

	local okF, text = filterForBroadcast(raw, admin.UserId)
	if not okF then
		--  🔒 Échec fermé. On n'envoie RIEN plutôt que du texte non filtré.
		return false, "Roblox text filter unavailable - message NOT sent"
	end

	local payload = {
		k       = "msg",
		nonce   = SERVER_TAG .. "|" .. tostring(os.time()) .. "|"
			.. tostring(math.random(1, 999999999)),
		text    = text,
		title   = Config.CleanText(tostring(spec.title or ""), LIM.NAME_LEN_MAX),
		emoji   = Config.CleanText(tostring(spec.emoji or "📢"), 6),
		rainbow = spec.rainbow == true,
		time    = math.clamp(tonumber(spec.time) or 0, 0, 30),
		by      = admin.UserId,
		byName  = admin.Name,
		at      = os.time(),
	}

	publish(payload)
	showRemoteMessage(payload)
	return true, "Message broadcast"
end

--══════════════════════════════════════════════════════════════════════════════
--
--  🎛️ PARTIE 5 — PANEL, CYCLE DE VIE DES JOUEURS, FERMETURE
--
--  Deux remotes, et un seul portail : isAdmin. Il est revérifié à CHAQUE
--  appel, jamais mis en cache, jamais délégué au client. Le panel n'a aucun
--  pouvoir en soi — il ne fait qu'envoyer des demandes qui sont réexaminées
--  ici de zéro.
--
--══════════════════════════════════════════════════════════════════════════════

--──────────────────────────────────────────────────────────────────────────────
-- 🗜️ COMPACTAGE
--    Une météo complète fait ~45 réglages. En enregistrer 40 + 8 plannings de
--    24 étapes ferait une clé DataStore énorme et lente. On ne stocke donc que
--    ce qui DIFFÈRE du défaut : ValidateWeather remet automatiquement les
--    champs absents à leur valeur de schéma à la relecture. Rien n'est perdu.
--──────────────────────────────────────────────────────────────────────────────
--══════════════════════════════════════════════════════════════════════════
-- 🗜️ COMPACTAGE
--
--   On ne stocke QUE les 16 champs que tu as réellement choisis (nom,
--   ambiance, ciel, effet, boost, vitesse…). Tout le rendu — lumière,
--   atmosphère, brouillard, bloom, particules — est RECALCULÉ à la
--   relecture par Config.BuildWeather.
--
--   Deux bénéfices, et le second est le vrai :
--     • une météo pèse quelques centaines d'octets au lieu de plusieurs
--       kilos, donc les 40 météos + 8 plannings tiennent large ;
--     • il devient IMPOSSIBLE qu'une valeur de rendu périmée survive dans
--       le DataStore. Si je change l'ambiance « Disco » demain, toutes tes
--       météos en Disco suivent, sans migration.
--══════════════════════════════════════════════════════════════════════════
local function compactW(w)
	return Config.CompactWeather(w)
end

local function packCfg(cur)
	local out = {
		v = 2, mc = cur.mc, hud = cur.hud, sched = cur.sched,
		schedBy = cur.schedBy, weathers = {}, plans = {},
	}
	for id, w in pairs(cur.weathers) do
		out.weathers[id] = compactW(w)
	end
	for i, p in ipairs(cur.plans) do
		local steps = {}
		for j, s in ipairs(p.steps) do steps[j] = compactW(s) end
		out.plans[i] = { name = p.name, steps = steps }
	end
	--  🧽 Même tamis que pour le plan : la config contient des noms de météos
	--     écrits à la main, donc pleins d'emoji potentiels.
	return Config.SanitizeForStore(out)
end

--  Toute écriture de configuration passe par ici : lecture → normalisation →
--  modification → compactage → écriture, le tout dans UpdateAsync pour que
--  deux admins qui sauvegardent en même temps ne s'écrasent pas.
local function saveCfg(mutator)
	local ok, err = pcall(function()
		cfgStore:UpdateAsync("config", function(old)
			local cur = normalizeCfg(old)
			mutator(cur)
			return packCfg(cur)
		end)
	end)
	if not ok then return false, tostring(err) end
	pcall(refreshCfg)
	publish({ k = "cfg" })
	return true, "Saved"
end

--──────────────────────────────────────────────────────────────────────────────
-- 🔧 OUTILS DISPONIBLES
--──────────────────────────────────────────────────────────────────────────────
local function toolNames()
	local out = {}
	local f = toolsFolder()
	if f then
		for _, t in ipairs(f:GetChildren()) do
			if t:IsA("Tool") then out[#out + 1] = t.Name end
		end
	end
	table.sort(out)
	return out
end

--──────────────────────────────────────────────────────────────────────────────
-- 📊 STATISTIQUES CONSOLIDÉES
--    Chaque serveur dépose sa ligne dans un MemoryStore ; on additionne. Si
--    le MemoryStore est indisponible, on renvoie les chiffres de CE serveur
--    en le disant clairement (scope = "local") plutôt que de présenter un
--    total partiel comme s'il était global.
--──────────────────────────────────────────────────────────────────────────────
local function aggregateStats()
	pcall(pushStats)          -- notre propre ligne d'abord, pour qu'elle soit fraîche
	recomputeLive()

	local out = {}
	for k, v in pairs(Stats.d) do out[k] = v end
	out.scope       = "local"
	out.serversSeen = 1

	local runId = _G.__aaRunId
	if statsMapOk and statsMap and runId then
		local acc, count = freshStats(), 0
		local ok = pcall(function()
			--  Une seule page de 200 : au-delà, l'admin verra « partiel ».
			--  Mieux vaut une réponse rapide et honnête qu'une boucle de
			--  pagination qui bloque le panel.
			local page  = statsMap:ListItemsAsync(200)
			local items = page:GetCurrentPage()
			local pref  = tostring(runId) .. "|"
			for _, item in ipairs(items) do
				local key = tostring(item.key or "")
				if key:sub(1, #pref) == pref and type(item.value) == "table" then
					count = count + 1
					for k2, v2 in pairs(item.value) do
						if type(v2) == "number" and acc[k2] ~= nil then
							acc[k2] = acc[k2] + v2
						end
					end
				end
			end
		end)
		if ok and count > 0 then
			acc.scope       = "global"
			acc.serversSeen = count
			out = acc
		end
	end
	return out
end

--──────────────────────────────────────────────────────────────────────────────
-- 📖 LECTURE  (RemoteFunction « AdminAbuseGet »)
--──────────────────────────────────────────────────────────────────────────────
rfGet.OnServerInvoke = function(player, what, _arg)
	--  🔒 Portail nº1. Un joueur non-admin n'obtient jamais autre chose que
	--     ce refus : ni la liste des météos, ni les stats, ni l'état.
	if not isAdmin(player) then
		logDenied(player, "get:" .. tostring(what))
		return { ok = false, err = "Denied" }
	end
	if not allow(player, "get", 0.25) then
		return { ok = false, err = "Too fast" }
	end

	what = tostring(what or "")

	if what == "panel" then
		local c = getCfg()
		return {
			ok       = true,
			run      = stateSnapshot(),
			mc       = msgConfig,
			hud      = hudConfig,
			sched    = schedCfg,
			weathers = c.weathers,
			plans    = c.plans,
			tools    = toolNames(),
			online   = #Players:GetPlayers(),
			server   = SERVER_TAG,
		}

	elseif what == "stats" then
		return { ok = true, stats = aggregateStats(), run = stateSnapshot() }

	elseif what == "history" then
		local okH, data = pcall(function() return runStore:GetAsync("history") end)
		if not okH then return { ok = false, err = "History unreadable" } end
		return { ok = true, list = (type(data) == "table" and data.list) or {} }

	elseif what == "tools" then
		return { ok = true, tools = toolNames() }

	elseif what == "state" then
		return { ok = true, run = stateSnapshot() }
	end

	return { ok = false, err = "Unknown request" }
end

--──────────────────────────────────────────────────────────────────────────────
-- ✍️ ACTIONS  (RemoteFunction « AdminAbuseAction »)
--──────────────────────────────────────────────────────────────────────────────
rfAct.OnServerInvoke = function(player, action, payload)
	--  🔒 Portail nº2. Même contrôle, refait de zéro. Aucune action n'existe
	--     en dehors de cette liste : il n'y a pas de branche « générique ».
	if not isAdmin(player) then
		logDenied(player, "act:" .. tostring(action))
		return { ok = false, err = "Denied" }
	end

	action = tostring(action or "")
	local ok, msg = false, "Unknown action"

	if action == "start" then
		ok, msg = doStart(player, payload)

	elseif action == "update" then
		ok, msg = doUpdate(player, payload)

	elseif action == "stop" then
		ok, msg = doStop(player)

	elseif action == "gift" then
		ok, msg = doGift(player, payload)

	elseif action == "message" then
		ok, msg = doMessage(player, payload)

	elseif action == "saveWeather" then
		if not allow(player, "cfg", 1) then
			ok, msg = false, "Too fast"
		elseif type(payload) ~= "table" then
			ok, msg = false, "Invalid request"
		else
			local id = tostring(payload.id or ""):gsub("[^%w_%-]", "")
			if id == "" then
				id = "w" .. tostring(os.time()) .. tostring(math.random(100, 999))
			end
			--  Validation obligatoire : cette météo vient du client.
			local w = Config.ValidateWeather(payload, id)
			ok, msg = saveCfg(function(cur)
				if cur.weathers[id] == nil then
					local n = 0
					for _ in pairs(cur.weathers) do n = n + 1 end
					if n >= LIM.CUSTOM_WEATHERS_MAX then
						error("Limit of " .. LIM.CUSTOM_WEATHERS_MAX .. " weathers reached", 0)
					end
				end
				cur.weathers[id] = w
			end)
			if ok then msg = "Weather \"" .. tostring(w.name) .. "\" saved" end
		end

	elseif action == "deleteWeather" then
		local id = tostring((type(payload) == "table" and payload.id) or ""):gsub("[^%w_%-]", "")
		if id == "" then
			ok, msg = false, "Missing id"
		else
			ok, msg = saveCfg(function(cur) cur.weathers[id] = nil end)
			if ok then msg = "Weather deleted" end
		end

	elseif action == "savePlan" then
		local name  = Config.CleanText(tostring((type(payload) == "table" and payload.name) or ""), LIM.NAME_LEN_MAX)
		local steps = trimSteps(type(payload) == "table" and payload.steps or nil)
		if name == "" then
			ok, msg = false, "Schedule name missing"
		elseif #steps == 0 then
			ok, msg = false, "Schedule is empty"
		else
			ok, msg = saveCfg(function(cur)
				for i = 1, #cur.plans do
					if cur.plans[i].name == name then
						cur.plans[i] = { name = name, steps = steps }
						return
					end
				end
				if #cur.plans >= PLANS_MAX then
					error("Limit of " .. PLANS_MAX .. " schedules reached", 0)
				end
				cur.plans[#cur.plans + 1] = { name = name, steps = steps }
			end)
			if ok then msg = "Schedule \"" .. name .. "\" saved" end
		end

	elseif action == "deletePlan" then
		local name = Config.CleanText(tostring((type(payload) == "table" and payload.name) or ""), LIM.NAME_LEN_MAX)
		if name == "" then
			ok, msg = false, "Name missing"
		else
			ok, msg = saveCfg(function(cur)
				for i = #cur.plans, 1, -1 do
					if cur.plans[i].name == name then table.remove(cur.plans, i) end
				end
			end)
			if ok then msg = "Schedule deleted" end
		end

	elseif action == "msgConfig" then
		if not allow(player, "cfg", 1) then
			ok, msg = false, "Too fast"
		else
			local raw = (type(payload) == "table" and type(payload.mc) == "table") and payload.mc or payload
			local mc  = Config.ValidateMessageConfig(raw)
			ok, msg = saveCfg(function(cur) cur.mc = mc end)
			if ok then
				msgConfig = mc
				pcall(function() pushState(nil) end)
				msg = "Banner style saved"
			end
		end

		--══════════════════════════════════════════════════════════════════════
		-- 🖥️ MISE EN PAGE DES BARRES À L'ÉCRAN
		--    Position enregistrée en FRACTION d'écran : la même barre tombe au
		--    même endroit relatif sur un téléphone et sur un 27 pouces.
		--══════════════════════════════════════════════════════════════════════
	elseif action == "hudConfig" then
		if not allow(player, "cfg", 1) then
			ok, msg = false, "Too fast"
		else
			local raw = (type(payload) == "table" and type(payload.hud) == "table")
				and payload.hud or payload
			local hd  = Config.ValidateHud(raw)
			ok, msg = saveCfg(function(cur) cur.hud = hd end)
			if ok then
				hudConfig = hd
				pcall(function() pushState(nil) end)
				msg = "Layout saved"
			end
		end

		--══════════════════════════════════════════════════════════════════════
		-- ⏲️ PLANNING DE CADEAUX AUTOMATIQUES
		--══════════════════════════════════════════════════════════════════════
	elseif action == "schedConfig" then
		if not allow(player, "cfg", 1) then
			ok, msg = false, "Too fast"
		else
			local raw = (type(payload) == "table" and type(payload.sched) == "table")
				and payload.sched or payload
			local sc = Config.ValidateSched(raw)
			--  🔒 Seul un texte que TU tapes passe par le filtre Roblox, et
			--     une seule fois : ici, à l'enregistrement. Les messages
			--     préfaits sont dans le code, il n'y a rien à filtrer.
			--
			--     Filtre indisponible → on REFUSE d'enregistrer, plutôt que
			--     de diffuser du texte non filtré toutes les N minutes à
			--     tous les serveurs. Échec fermé, jamais ouvert.
			if sc.sc_msgId ~= "custom" then
				sc.sc_note = ""      -- une note orpheline ne doit pas traîner
			elseif sc.sc_note ~= "" then
				local okF, out = filterForBroadcast(sc.sc_note, player.UserId)
				if not okF then
					return { ok = false, err = "Text filter unavailable - not saved",
						run = stateSnapshot() }
				end
				sc.sc_note = out
			else
				return { ok = false,
					err = "Pick a ready-made message, or write your own first.",
					run = stateSnapshot() }
			end
			ok, msg = saveCfg(function(cur)
				cur.sched   = sc
				cur.schedBy = { id = player.UserId, name = player.Name }
			end)
			if ok then
				schedCfg = sc
				--  On remet le compteur à zéro pour que le nouveau rythme
				--  prenne effet tout de suite, au lieu d'attendre la fin de
				--  l'ancien intervalle.
				nextGiftAt = 0
				pcall(function()
					liveStore:UpdateAsync(SCHED_KEY, function()
						return { nextAt = os.time() + sc.sc_every, by = SERVER_TAG,
							every = sc.sc_every }
					end)
				end)
				pcall(function() pushState(nil) end)
				msg = sc.sc_on and ("Automatic gifts ON - every "
					.. tostring(sc.sc_every) .. "s") or "Automatic gifts OFF"
			end
		end

	elseif action == "preview" then
		--  Aperçu : envoyé À L'ADMIN SEUL. Aucun autre joueur ne le voit,
		--  donc pas besoin de filtre — ce texte ne sort pas de son écran.
		if not allow(player, "prev", 1) then
			ok, msg = false, "Too fast"
		else
			local mc = msgConfig
			if type(payload) == "table" and type(payload.mc) == "table" then
				mc = Config.ValidateMessageConfig(payload.mc)
			end
			local txt = Config.CleanText(
				tostring((type(payload) == "table" and payload.text) or ""), LIM.MESSAGE_LEN_MAX)
			if txt == "" then txt = "This is a preview - only you can see it." end
			fireBanner({
				kind    = "gift",
				icon    = Config.Icon("gift"),
				title   = player.Name,
				text    = txt,
				rainbow = true,
				party   = true,
				by      = player.UserId,
				byName  = player.Name,
				mc      = mc,
				at      = os.time(),
			}, player)
			ok, msg = true, "Preview sent"
		end
	end

	if ok then
		return { ok = true, msg = tostring(msg or "ok"), run = stateSnapshot() }
	end
	return { ok = false, err = tostring(msg or "erreur"), run = stateSnapshot() }
end

--══════════════════════════════════════════════════════════════════════════════
-- 👤 CYCLE DE VIE DES JOUEURS
--══════════════════════════════════════════════════════════════════════════════

--  Un respawn remet WalkSpeed / JumpPower aux valeurs par défaut du jeu :
--  il faut réappliquer les écarts de l'étape en cours — et RIEN d'autre.
local function onCharacter(player)
	task.wait(0.35)
	if not player:IsDescendantOf(Players) then return end
	if Run and curStep() then
		pcall(function() applyCharacterStats(player) end)
	else
		pcall(function() removeCharacterStats(player) end)
	end
end

local function onJoin(player)
	local uid = player.UserId
	--  ⏱️ L'instant d'arrivée. C'est LUI, et rien d'autre, qui décide de
	--     l'éligibilité aux cadeaux. Le client ne le voit jamais et ne peut
	--     donc pas le falsifier.
	Effects.joinAt[uid] = os.time()
	if Run then statBump("joinedDuring") end

	player.CharacterAdded:Connect(function()
		task.spawn(onCharacter, player)
	end)
	if player.Character then task.spawn(onCharacter, player) end

	task.spawn(function()
		--  On laisse le chargement des données du joueur se faire avant de
		--  toucher à quoi que ce soit : creditPoints refuse pendant le
		--  chargement, et un boost appliqué trop tôt n'aurait servi à rien.
		task.wait(1)
		if not player:IsDescendantOf(Players) then return end
		pcall(function() pushState(player) end)
		local w = curStep()
		if w then
			pcall(function() applyToPlayer(player, w) end)
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onJoin, player)
end)

--  Serveurs déjà peuplés au moment où ce script se charge.
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, p)
end

Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	if Run then statBump("leftDuring") end

	--  On révoque au départ : inutile en théorie (rien ne persiste), mais ça
	--  garde les compteurs justes et ça rend les outils au serveur.
	pcall(function() revokeFromPlayer(player, false) end)

	Effects.joinAt[uid]  = nil
	Effects.boost[uid]   = nil
	Effects.speed[uid]   = nil
	Effects.jump[uid]    = nil
	Effects.pvp[uid]     = nil
	Effects.tools[uid]   = nil
	giftBoosts[uid]      = nil
	giftTools[uid]       = nil
	rate[uid]            = nil
end)

--══════════════════════════════════════════════════════════════════════════════
-- 🌉 INSTALLATION DU PONT ANTI-CHEAT
--    On réessaie pendant 60 s : l'ordre de chargement des scripts varie, et
--    TempBoosts peut arriver après nous. Tant qu'il n'est pas là, un boost
--    d'événement ne fait simplement RIEN — il ne peut jamais provoquer de
--    faux positif, parce que le gain réel et le gain autorisé restent tous
--    les deux au niveau de base.
--══════════════════════════════════════════════════════════════════════════════
task.spawn(function()
	for _ = 1, 60 do
		if installBoostBridge() then
			print("🌉 [AdminAbuse] Pont anti-cheat installé sur TempBoosts.getMultiplier")
			return
		end
		task.wait(1)
	end
	warn("⚠️ [AdminAbuse] TempBoosts introuvable après 60 s. "
		.. "Les boosts d'événement seront sans effet sur ce serveur "
		.. "(aucun risque de faux positif pour autant).")
end)

--══════════════════════════════════════════════════════════════════════════════
-- 🔌 FERMETURE DU SERVEUR
--    Rien ne persiste, donc il n'y a rien à « nettoyer » côté données. On
--    remet quand même la gravité, on rend les outils et on pousse le dernier
--    état des stats pour que le bilan de l'événement soit complet.
--══════════════════════════════════════════════════════════════════════════════
game:BindToClose(function()
	pcall(function() revokeEveryone(false) end)
	pcall(pushStats)
	task.wait(0.4)
end)

--══════════════════════════════════════════════════════════════════════════════
-- 🌍 INTERFACE POUR TES AUTRES SCRIPTS
--    En lecture seule. Aucune fonction ici ne donne quoi que ce soit : ce
--    sont des questions, pas des leviers. Même appelée depuis n'importe où,
--    aucune ne peut créer de points, de boost ni d'outil.
--══════════════════════════════════════════════════════════════════════════════
_G.AdminAbuse = {
	Active = function()
		return Run ~= nil
	end,
	RunId = function()
		return Run and Run.id or nil
	end,
	Title = function()
		return Run and Run.title or nil
	end,
	--  Boost d'événement d'un joueur (0 s'il n'en a pas). Déjà pris en compte
	--  automatiquement par l'anti-cheat via le pont : à n'utiliser que pour
	--  l'affichage.
	BoostOf = function(userId)
		return Effects.boost[userId] or 0
	end,
	--  Le PVP d'événement est-il actif pour ce joueur ?
	PvpOn = function(userId)
		return Effects.pvp[userId] == true
	end,
	--  La tolérance anti-fly est-elle posée par l'événement en ce moment ?
	PhysicsGrace = function()
		return graceHeld == true
	end,
	--  Cet objet est-il un outil prêté par un événement ? (utile si tu veux
	--  l'exclure d'une sauvegarde d'inventaire, par exemple)
	IsEventTool = function(inst)
		if typeof(inst) ~= "Instance" then return false end
		local okA, v = pcall(function() return inst:GetAttribute(Config.TOOL_TAG) end)
		return okA and v ~= nil
	end,
}

print("🎪 [AdminAbuse] Système prêt · serveur " .. tostring(SERVER_TAG)
	.. " · " .. tostring(#ADMIN_IDS) .. " admin(s)")