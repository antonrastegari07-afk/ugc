--════════════════════════════════════════════════════════════
-- 💬 FEEDBACK SYSTEM — SERVEUR
-- ServerScriptService > FeedbackSystem_Server (Script)
--
-- DataStore ultra-économe :
--   • ENVOI joueur      → 1 UpdateAsync (bucket du jour). +1 write le
--                         1er feedback d'un nouveau bucket (≈1×/jour).
--   • LECTURE admin     → 1 read meta (caché 20s) + 1 read par bucket
--                         affiché, uniquement quand TU ouvres l'onglet.
--   • Aucune boucle de fond, aucune écriture périodique.
--════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")
local TextService       = game:GetService("TextService")
local HttpService       = game:GetService("HttpService")

local ADMIN_IDS = { 3203521470, 11017023724, 8456613930, 8142402169, 10420404767 }

local CFG   = require(ReplicatedStorage:WaitForChild("FeedbackConfig"))
local STORE = DataStoreService:GetDataStore("Feedbacks_v1")

local JOB = (game.JobId ~= "" and game.JobId) or ("studio_" .. tostring(math.random(1e6)))

-- Lit les deux formats : nombre (legacy) ou reçu {s=, by=, t=}
local function readState(data)
	if type(data) == "number" then
		return math.clamp(math.floor(data), 0, 2), nil
	elseif type(data) == "table" then
		return math.clamp(math.floor(tonumber(data.s) or 0), 0, 2), data.by
	end
	return 0, nil
end

local META_KEY       = "meta"
local MAX_PER_BUCKET = 80    -- entrées max par bucket (reste très loin de 4MB)
local META_TTL       = 20    -- cache mémoire du meta (secondes)

-- ── Remotes ─────────────────────────────────────────────────
local function mkRemote(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local submitFn      = mkRemote("FeedbackSubmit",      "RemoteFunction")
local adminGetFn    = mkRemote("AdminGetFeedbacks",   "RemoteFunction")
local adminActEvent = mkRemote("AdminFeedbackAction", "RemoteEvent")

local function isAdmin(userId)
	for _, id in ipairs(ADMIN_IDS) do
		if id == userId then return true end
	end
	return false
end

-- ── État mémoire ────────────────────────────────────────────
local lastSubmit   = {}   -- [userId] = os.time()
local sessionCount = {}   -- [userId] = n
local busy         = {}   -- [userId] = true pendant un envoi
local registered   = {}   -- [bucketKey] = true (déjà inscrit dans meta)
local lastTry = {}   -- [userId] = os.clock() — anti-spam, tous résultats confondus
local metaCache, metaCacheAt = nil, 0

-- ── Meta (liste des buckets, ordre chronologique) ────────────
local function readMeta(force)
	local now = os.time()
	if not force and metaCache and (now - metaCacheAt) < META_TTL then
		return metaCache
	end
	local ok, data = pcall(function() return STORE:GetAsync(META_KEY) end)
	if not ok then return metaCache end
	if type(data) ~= "table" or type(data.buckets) ~= "table" then
		data = { buckets = {} }
	end
	metaCache, metaCacheAt = data, now
	for _, b in ipairs(data.buckets) do registered[b] = true end
	return data
end

local function registerBucket(bucketKey)
	if registered[bucketKey] then return end
	local ok = pcall(function()
		STORE:UpdateAsync(META_KEY, function(old)
			if type(old) ~= "table" or type(old.buckets) ~= "table" then
				old = { buckets = {} }
			end
			for _, b in ipairs(old.buckets) do
				if b == bucketKey then return nil end -- déjà là → annule l'écriture
			end
			table.insert(old.buckets, bucketKey)
			return old
		end)
	end)
	if ok then
		registered[bucketKey] = true
		metaCacheAt = 0 -- force un refresh du cache à la prochaine lecture
	end
end

local function todayBase()
	local t = os.date("!*t", os.time())
	return string.format("b_%04d%02d%02d", t.year, t.month, t.day)
end

local function writeEntry(entry)
	local base = todayBase()
	for suffix = 1, 25 do
		local key  = base .. "_" .. suffix
		local full, created = false, false
		local ok = pcall(function()
			STORE:UpdateAsync(key, function(old)
				if type(old) ~= "table" or type(old.entries) ~= "table" then
					old = { entries = {} }
					created = true
				end
				if #old.entries >= MAX_PER_BUCKET then
					full = true
					return nil -- annule, on essaiera le bucket suivant
				end
				table.insert(old.entries, entry)
				return old
			end)
		end)
		if not ok then return false end
		if not full then
			--  bucket (re)créé, par ex. après « Supprimer tous les feedbacks » :
			--  on le réinscrit toujours, sinon le feedback serait invisible
			if created then registered[key] = nil end
			registerBucket(key)
			return true
		end
	end
	return false
end

-- ── Nettoyage du message ────────────────────────────────────
local function sanitize(msg)
	msg = tostring(msg or "")
	msg = msg:gsub("\r\n", "\n"):gsub("\r", "\n")
	msg = msg:gsub("[%z\1-\8\11\12\14-\31]", "")   -- garde \n, vire le reste
	msg = msg:gsub("\n\n\n+", "\n\n")
	msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
	return CFG.clip(msg, CFG.MAX_MESSAGE)
end

-- ════════════════════════════════════════════════════════════
-- 🧠 CONTRÔLE QUALITÉ (anti-charabia)
-- Ne rejette QUE le charabia indiscutable. Multilingue : les tests
-- liés à l'alphabet latin sont ignorés si le message ne l'est pas.
-- Retourne : nil si OK, sinon reason(string), messageJoueur(string)
-- ════════════════════════════════════════════════════════════
local KEYBOARD_RUNS = {
	"qwertyuiop", "azertyuiop", "asdfghjklm", "qsdfghjklm",
	"zxcvbnm", "wxcvbn", "poiuytrewq", "mlkjhgfdsa", "mnbvcxz",
	"qazwsx", "wsxedc",
}

local VOWELS = {}
for _, cp in ipairs({
	97,101,105,111,117,121,                                  -- a e i o u y
	224,225,226,227,228,229,230,                             -- à á â ã ä å æ
	232,233,234,235, 236,237,238,239,                        -- è é ê ë ì í î ï
	242,243,244,245,246,248, 249,250,251,252, 253,255, 339,  -- ò ó ô õ ö ø ù ú û ü ý ÿ œ
	}) do VOWELS[cp] = true end

-- isLetter(cp) -> estLettre, estLatine
local function isLetter(cp)
	if (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) then return true, true end
	if cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7 then return true, true end
	if cp >= 0x370  and cp <  0x2000 then return true, false end  -- grec, cyrillique, hébreu, arabe, thaï…
	if cp >= 0x3040 and cp <= 0x9FFF then return true, false end  -- kana + CJK
	if cp >= 0xAC00 and cp <= 0xD7AF then return true, false end  -- hangul
	return false, false
end

-- ════════════════════════════════════════════════════════════
-- 🧪 COUCHE 2 : score de plausibilité linguistique
-- Chaque signal est faible pris seul → on n'agit que sur le cumul.
-- Ne s'applique qu'au texte majoritairement latin et ≥ 12 lettres.
-- ════════════════════════════════════════════════════════════
local HOME = {}   -- rangée de repos QWERTY + AZERTY réunies
for c in ("aqsdfghjklm"):gmatch(".") do HOME[c] = true end

local function isPeriodic(w)
	local n = #w
	if n < 6 then return false end
	for p = 2, math.floor(n / 2) do
		if n % p == 0 then
			local unit, same = w:sub(1, p), true
			for i = 1, n, p do
				if w:sub(i, i + p - 1) ~= unit then same = false break end
			end
			if same then return true end
		end
	end
	return false
end

local function plausibilityScore(msg, letters, latin, vowels)
	if letters < 12 then return 0 end
	if (latin / letters) < 0.6 then return 0 end     -- autre alphabet → pas jugé

	local words = {}
	for w in msg:lower():gmatch("[%a]+") do
		if #w >= 2 then table.insert(words, w) end
	end
	if #words == 0 then return 0 end

	local score = 0
	local seen, distinct, home, total = {}, 0, 0, 0
	for _, w in ipairs(words) do
		for c in w:gmatch(".") do
			if not seen[c] then seen[c] = true; distinct += 1 end
			total += 1
			if HOME[c] then home += 1 end
		end
	end

	-- S1 (2 pts) — alphabet trop pauvre pour la longueur
	local minDistinct = math.min(11, math.ceil(2 + total * 0.24))
	if total >= 12 and distinct < minDistinct then score += 2 end

	-- S2 (2 pts) — martèlement de la rangée de repos (0.82 : marge testée)
	if total >= 16 and (home / total) >= 0.82 then score += 2 end

	-- S3 (1 pt) — motifs répétés
	local tri, triTotal, triDistinct = {}, 0, 0
	for _, w in ipairs(words) do
		for i = 1, #w - 2 do
			local t = w:sub(i, i + 2)
			triTotal += 1
			if not tri[t] then tri[t] = true; triDistinct += 1 end
		end
	end
	if triTotal >= 10 and (triDistinct / triTotal) < 0.72 then score += 1 end

	-- S4 (1 pt) — très peu de voyelles
	if latin >= 12 and (vowels / latin) < 0.15 then score += 1 end

	-- S5 (1 pt) — mots LONGS sans voyelle (pls/thx/btw exclus)
	local longW, noVowel = 0, 0
	for _, w in ipairs(words) do
		if #w >= 5 then
			longW += 1
			if not w:find("[aeiouy]") then noVowel += 1 end
		end
	end
	if longW >= 2 and (noVowel / longW) >= 0.40 then score += 1 end

	-- S6 (1 pt) — mots imprononçables (4 consonnes d'affilée)
	local clust = 0
	for _, w in ipairs(words) do
		if w:find("[^aeiouy][^aeiouy][^aeiouy][^aeiouy]") then clust += 1 end
	end
	if #words >= 3 and (clust / #words) >= 0.40 then score += 1 end

	-- S7 (2 pts) — mots cycliques ("azeazeaze", "lkjlkjlkj")
	local per, big = 0, 0
	for _, w in ipairs(words) do
		if #w >= 6 then
			big += 1
			if isPeriodic(w) then per += 1 end
		end
	end
	if per >= 2 and big > 0 and (per / big) >= 0.50 then score += 2 end

	return score
end
local function qualityCheck(msg)
	local lower = msg:lower()
	local letters, latin, vowels, nonSpace = 0, 0, 0, 0
	local distinct, distinctCount, hasSpace = {}, 0, false

	local longestWord, curWord = 0, 0
	local okIter = pcall(function()
		for _, cp in utf8.codes(msg) do
			local isL, isLat = isLetter(cp)
			if isL then
				nonSpace += 1
				letters  += 1
				curWord  += 1
				if curWord > longestWord then longestWord = curWord end
				local key = cp
				if isLat then
					latin += 1
					if cp >= 65 and cp <= 90 then key = cp + 32 end
					if VOWELS[key] then vowels += 1 end
				end
				if not distinct[key] then distinct[key] = true; distinctCount += 1 end
			else
				curWord = 0                                  -- . - _ chiffres = séparateurs
				if cp == 32 or cp == 9 or cp == 10 then
					hasSpace = true
				else
					nonSpace += 1
				end
			end
		end
	end)
	if not okIter then return nil end   -- UTF-8 exotique → on laisse passer

	-- 1) pas assez de lettres (emoji-spam, "123456", "......")
	if letters < 8 then
		return "letters", "Your feedback needs actual words — a short sentence is enough."
	end

	-- 2) noyé dans les symboles / chiffres
	if nonSpace > 0 and (letters / nonSpace) < 0.35 then
		return "symbols", "Too many symbols or numbers — describe it with words."
	end

	-- 3) trop peu de lettres différentes ("aaaa", "abababab")
	if letters >= 10 and distinctCount < 5 then
		return "variety", "Your message repeats the same few letters."
	end

	-- 4) caractère martelé ("aaaaaaaaaa", "!!!!!!!!!")
	local runTotal, maxRun = 0, 0
	do
		local prev, run = nil, 0
		local function flush()
			if run >= 6 then runTotal += run end
			if run > maxRun then maxRun = run end
		end
		for _, cp in utf8.codes(msg) do
			if cp == prev then run += 1 else flush(); run = 1; prev = cp end
		end
		flush()
	end
	if maxRun >= 8 and nonSpace > 0 and (runTotal / nonSpace) > 0.45 then
		return "repeat", "Too many repeated characters in a row."
	end

	-- 5) suite de touches du clavier ("qwerty", "asdfgh")
	for _, run in ipairs(KEYBOARD_RUNS) do
		for i = 1, #run - 4 do
			if lower:find(run:sub(i, i + 4), 1, true) then
				return "keyboard", "That looks like random keyboard input."
			end
		end
	end

	-- 6) quasi aucune voyelle → mash ("dhjskfhs kjdfhs")  [latin uniquement]
	if letters >= 10 and (latin / letters) >= 0.6 and (vowels / math.max(1, latin)) < 0.12 then
		return "gibberish", "That doesn't look like real words."
	end

	-- 7) un seul bloc collé sans espace  [latin uniquement]
	if longestWord >= 25 and (latin / letters) >= 0.6 then
		return "oneblock", "Write it as a few words instead of one long block."
	end

	-- 8) le même mot recopié ("test test test test")
	do
		local seen, distinctW, total = {}, 0, 0
		for w in lower:gmatch("[%a\128-\255]+") do
			if #w >= 2 then
				total += 1
				if not seen[w] then seen[w] = true; distinctW += 1 end
			end
		end
		if (distinctW == 1 and total >= 3) or (distinctW <= 2 and total >= 6) then
			return "wordrepeat", "Your message just repeats the same word."
		end
	end

	-- ── COUCHE 2 : rejet uniquement si plusieurs signaux se cumulent ──
	if plausibilityScore(msg, letters, latin, vowels) >= 3 then
		return "implausible", "That doesn't read like a real message."
	end

	return nil
end

-- ════════════════════════════════════════════════════════════
-- 💬 MESSAGES JOUEUR
-- Les 8 tests sont regroupés en 2 familles volontairement floues :
-- le joueur comprend la direction à prendre sans deviner la règle.
-- Le diagnostic exact reste dans les logs serveur.
-- ════════════════════════════════════════════════════════════
local QUALITY_BUCKET = {
	short      = "thin",       letters   = "thin",
	symbols    = "thin",       oneblock  = "thin",
	variety    = "unreadable", ["repeat"] = "unreadable",
	keyboard   = "unreadable", gibberish = "unreadable",
	wordrepeat = "unreadable", implausible = "unreadable",
}

local QUALITY_MSG = {
	thin = {
		"Tell us a bit more — one clear sentence is enough.",
		"That's a little thin. What exactly would you change?",
		"Give us something to work with, in your own words.",
	},
	unreadable = {
		"We couldn't read that as a real message.",
		"That doesn't come through as feedback yet.",
		"Hmm — say it in your own words so we can understand.",
	},
}

local QUALITY_TIP = {
	thin       = "What happened, where in the game, and what you'd like instead? Your text is kept.",
	unreadable = "Explain it like you'd tell a friend. Your text is kept, just edit it.",
}

local function qualityReject(reason)
	local bucket = QUALITY_BUCKET[reason] or "unreadable"
	local pool   = QUALITY_MSG[bucket]
	return {
		ok      = false,
		quality = true,
		msg     = pool[math.random(1, #pool)],
		tip     = QUALITY_TIP[bucket],
	}
end

-- Filtrage Roblox obligatoire (texte affiché à d'autres utilisateurs = toi)
local function filterFor(msg, userId)
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(msg, userId, Enum.TextFilterContext.PrivateChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(res) == "string" and #res > 0 then return res end
	return nil
end

-- ── ENVOI (joueur) ──────────────────────────────────────────
submitFn.OnServerInvoke = function(player, categoryId, message)
	local userId = player.UserId

	-- 🛡️ rate limit sur TOUTES les tentatives (même refusées) : empêche de
	-- marteler le serveur et de brute-forcer le filtre qualité.
	-- 1,5 s : invisible pour un humain qui corrige son message.
	local tryNow = os.clock()
	if lastTry[userId] and (tryNow - lastTry[userId]) < 1.5 then
		return { ok = false, quality = true, msg = "Slow down a second, then send again." }
	end
	lastTry[userId] = tryNow

	if busy[userId] then
		return { ok = false, msg = "Please wait a second..." }
	end
	if type(categoryId) ~= "string" or not CFG.isValid(categoryId) then
		return { ok = false, msg = "Pick a category first." }
	end

	local clean = sanitize(message)

	-- 🧠 anti-charabia : refus AVANT tout (aucun cooldown consommé,
	-- aucune écriture DataStore, le joueur corrige et renvoie aussitôt)
	local qReason
	if #clean < CFG.MIN_MESSAGE then
		qReason = "short"
	else
		qReason = qualityCheck(clean)
	end
	if qReason then
		-- diagnostic PRÉCIS ici seulement — le joueur ne le voit jamais
		print(("🧪 Feedback refusé [%s] | %s (%d) | %s")
			:format(qReason, player.Name, userId, clean:sub(1, 60)))
		return qualityReject(qReason)
	end

	local now  = os.time()
	local last = lastSubmit[userId] or 0
	if now - last < CFG.COOLDOWN then
		local left = CFG.COOLDOWN - (now - last)
		return { ok = false, msg = string.format("Please wait %ds before sending again.", left), cooldown = left }
	end
	if (sessionCount[userId] or 0) >= CFG.MAX_PER_JOIN then
		return { ok = false, msg = "You've sent enough feedback for this session. Thanks! 💙" }
	end

	busy[userId] = true

	local filtered = filterFor(clean, userId)
	if not filtered then
		busy[userId] = nil
		return { ok = false, msg = "Couldn't send right now, please try again." }
	end

	-- 🚫 Le filtre Roblox a mis des # → on refuse et on montre le résultat
	-- au joueur pour qu'il reformule. Le cooldown n'est PAS consommé.
	local function hashes(s)
		local n = 0
		for _ in s:gmatch("#") do n = n + 1 end
		return n
	end
	if filtered ~= clean and hashes(filtered) > hashes(clean) then
		busy[userId] = nil
		return {
			ok      = false,
			censored = true,
			preview = filtered,
			msg     = "Roblox filtered part of your message. Please rephrase it.",
		}
	end

	local pts = player:GetAttribute("Points")
	local entry = {
		id   = HttpService:GenerateGUID(false),
		u    = userId,
		n    = player.Name,
		d    = player.DisplayName,
		c    = categoryId,
		m    = filtered,
		t    = now,
		pts  = (type(pts) == "number") and math.floor(pts) or nil,
		read = false,
	}

	local written = writeEntry(entry)
	busy[userId] = nil

	if not written then
		return { ok = false, msg = "Server busy, try again in a minute." }
	end

	lastSubmit[userId]   = now
	sessionCount[userId] = (sessionCount[userId] or 0) + 1

	print(string.format("💬 FEEDBACK | %s (%d) | %s | %s",
		player.Name, userId, categoryId, filtered:sub(1, 80)))

	-- 🎁 débloque la quête feedback (récompense unique)
	if type(_G.FeedbackQuest_OnSubmitted) == "function" then
		task.spawn(function() _G.FeedbackQuest_OnSubmitted(userId) end)
	end

	return { ok = true, msg = "Thanks! Your feedback has been sent. 💙", cooldown = CFG.COOLDOWN }
end

-- ── LECTURE (admin) ─────────────────────────────────────────
-- cursor = index dans meta.buckets où continuer (nil = depuis le plus récent)
adminGetFn.OnServerInvoke = function(player, cursor, wanted)
	if not isAdmin(player.UserId) then return { entries = {} } end
	wanted = math.clamp(tonumber(wanted) or 25, 5, 60)

	local meta = readMeta(cursor == nil)
	if not meta then return { entries = {}, error = "DataStore unavailable" } end

	local buckets = meta.buckets or {}
	local i       = tonumber(cursor) or #buckets
	local out     = {}
	local reads   = 0

	while i >= 1 and #out < wanted and reads < 6 do
		local key = buckets[i]
		reads = reads + 1
		local ok, data = pcall(function() return STORE:GetAsync(key) end)
		if ok and type(data) == "table" and type(data.entries) == "table" then
			for j = #data.entries, 1, -1 do   -- du plus récent au plus ancien
				local e = data.entries[j]
				if type(e) == "table" then
					e.bucket = key
					table.insert(out, e)
				end
			end
		end
		i = i - 1
	end

	return { entries = out, cursor = i, hasMore = i >= 1 }
end

-- ── ACTIONS (admin) : read / unread / delete ────────────────
adminActEvent.OnServerEvent:Connect(function(player, act, bucketKey, id)
	if not isAdmin(player.UserId) then return end
	if type(bucketKey) ~= "string" or type(id) ~= "string" then return end
	if act ~= "delete" and act ~= "read" and act ~= "unread" then return end

	task.spawn(function()
		pcall(function()
			STORE:UpdateAsync(bucketKey, function(old)
				if type(old) ~= "table" or type(old.entries) ~= "table" then return nil end
				for k, e in ipairs(old.entries) do
					if type(e) == "table" and e.id == id then
						if act == "delete" then
							table.remove(old.entries, k)
						else
							e.read = (act == "read")
						end
						return old
					end
				end
				return nil -- rien trouvé → aucune écriture
			end)
		end)
	end)
end)

-- ── 🗑️ SUPPRIMER TOUS LES FEEDBACKS (admin, avec confirmation) ─────────
--    Le panel envoie le mot « SUPPRIMER ». Chaque jour de feedbacks est
--    effacé, puis retiré de la liste. Un feedback envoyé PENDANT la
--    suppression est gardé (son jour reste dans la liste).
local clearFn = mkRemote("AdminFeedbackClearAll", "RemoteFunction")
local clearing = false
local MessagingService = game:GetService("MessagingService")
local TOPIC_CLEAR = "FeedbackClearedAll"
local function resetCaches()
	registered = {}
	metaCache, metaCacheAt = nil, 0
end
pcall(function()
	MessagingService:SubscribeAsync(TOPIC_CLEAR, function() resetCaches() end)
end)
clearFn.OnServerInvoke = function(player, confirmWord)
	if not isAdmin(player.UserId) then return { ok = false, msg = "Accès refusé" } end
	if confirmWord ~= "SUPPRIMER" then return { ok = false, msg = "Confirmation manquante" } end
	if clearing then return { ok = false, msg = "Une suppression est déjà en cours" } end
	clearing = true
	local meta = readMeta(true)
	if not meta then clearing = false return { ok = false, msg = "DataStore indisponible, réessaie" } end
	local done, failed, entries = {}, 0, 0
	for _, key in ipairs(meta.buckets or {}) do
		local ok, old = pcall(function() return STORE:GetAsync(key) end)
		if ok and type(old) == "table" and type(old.entries) == "table" then entries = entries + #old.entries end
		local okR = pcall(function() STORE:RemoveAsync(key) end)
		if okR then done[key] = true else failed = failed + 1 end
		task.wait(0.15)
	end
	pcall(function()
		STORE:UpdateAsync(META_KEY, function(old)
			if type(old) ~= "table" or type(old.buckets) ~= "table" then return { buckets = {} } end
			local keep = {}
			for _, b in ipairs(old.buckets) do if not done[b] then table.insert(keep, b) end end
			old.buckets = keep
			return old
		end)
	end)
	resetCaches()
	pcall(function() MessagingService:PublishAsync(TOPIC_CLEAR, os.time()) end)
	clearing = false
	print(string.format("🗑️ [Feedback] %s a supprimé tous les feedbacks (%d message(s), %d jour(s), %d échec(s))",
		player.Name, entries, (function() local n = 0 for _ in pairs(done) do n = n + 1 end return n end)(), failed))
	if failed > 0 then
		return { ok = false, msg = string.format("%d feedback(s) supprimé(s), mais %d jour(s) n'ont pas pu l'être : réessaie", entries, failed) }
	end
	return { ok = true, msg = string.format("🗑️ %d feedback(s) supprimé(s)", entries), count = entries }
end

Players.PlayerRemoving:Connect(function(p)
	lastSubmit[p.UserId]   = nil
	sessionCount[p.UserId] = nil
	busy[p.UserId]         = nil
	lastTry[p.UserId]      = nil
end)

print("✅ FEEDBACK SYSTEM chargé (write on send / read on demand)")