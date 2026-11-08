--════════════════════════════════════════════════════════════════════════════
-- 📈 PLAYER UGC STATS — Script dans ServerScriptService   (NOUVEAU)
--
--  Répond aux questions :
--   • Combien de joueurs n'ont AUCUNE UGC ? Combien en ont 1, 2, 3… ?
--   • Pareil, séparé par type de joueur : sans pass · 👑 VIP · ⚡ boost permanent
--     (x2 / x5 / x10) · VIP + boost. Et combien ont VIP + x2.
--   • En moyenne, combien de TEMPS DE JEU pour avoir une UGC (1re, 2e, 3e…) ?
--   • Combien d'UGC ont les joueurs qui ont ARRÊTÉ de jouer (pas revenus depuis X jours) ?
--   • Dernière connexion de n'importe quel joueur (pour les entrées du panel).
--
--  Comment ça compte (aucune liste de joueurs à parcourir à chaque lecture) :
--   chaque joueur est rangé dans UNE case : (jour de sa dernière visite, type, nb d'UGC).
--   Quand il revient, il change de case ; quand il obtient une UGC, il change de case.
--   Le panel additionne les cases : « tous les joueurs », « ceux partis depuis 7 j »…
--
--  📥 RATTRAPAGE : au premier lancement, un seul serveur à la fois parcourt
--     les joueurs déjà connus (ceux vus par le script STATS) et les range dans
--     les cases, doucement (1 joueur / 1,5 s), sans gêner le jeu. Ça peut prendre
--     quelques heures ; le panel affiche l'avancement.
--
--  Écritures : regroupées toutes les 60 s (8 clés partagées, additions, jamais
--  d'écrasement). 1 lecture + 1 écriture par joueur et par session.
--  🧪 STUDIO : lecture seule (rien n'est compté ni écrit).
--════════════════════════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local DSS        = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local MPS        = game:GetService("MarketplaceService")

local Cat = require(RS:WaitForChild("ProductCatalog"))   -- jours à l'heure de Montréal

local ADMIN = {
	[3203521470] = true, [11017023724] = true, [8456613930] = true,
	[8142402169] = true, [10420404767] = true,
}

local READ_ONLY   = RunService:IsStudio()
local FLUSH_EVERY = 60
local SHARDS      = 8          -- ⚠️ ne jamais changer après l'installation
local MAX_U       = 10         -- 10 = « 10 UGC ou plus »
local MAX_ORD     = 5          -- temps pour la 1re, 2e… 5e UGC (5 = « 5e et + »)

local USERS   = DSS:GetDataStore("PlayerUgcStats_Users_v1")
local AGG     = DSS:GetDataStore("PlayerUgcStats_Agg_v1")
local ENGAGE  = DSS:GetDataStore("EngageUsers_v1")        -- LU seulement (script STATS)
local UGC_PLR = DSS:GetDataStore("UGCRedeemsPlayer_v1")   -- LU seulement (UGC REDEEM LOG)

-- mêmes IDs que PUBLIC_PROFILE / time
local VIP_PASS = 1891589121
local BOOST_PASSES = { [2] = 1891007119, [5] = 1893682680, [10] = 1891475116 }
local BIT = { vip = 1, [2] = 2, [5] = 4, [10] = 8 }

local JOB = (game.JobId ~= "" and game.JobId) or "studio"
local function shardOf(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 2147483647 end
	return h % SHARDS + 1
end
local MY_SHARD = shardOf(JOB)

local function today() return Cat.DayKey(os.time()) end
local function clampU(u) return math.clamp(math.floor(tonumber(u) or 0), 0, MAX_U) end

--════════════════════════════════════════════════════════════
-- 🧮 DELTAS EN MÉMOIRE (écrits toutes les 60 s)
--════════════════════════════════════════════════════════════
local pend = { last = {}, ttu = {} }

local function move(dk, f, u, n)
	if READ_ONLY or type(dk) ~= "string" or #dk ~= 8 then return end
	local cell = tostring(math.floor(tonumber(f) or 0)) .. "|" .. tostring(clampU(u))
	local d = pend.last[dk]
	if not d then d = {} ; pend.last[dk] = d end
	d[cell] = (d[cell] or 0) + n
	if d[cell] == 0 then d[cell] = nil end
end

local function sample(f, ord, pt, days)
	if READ_ONLY then return end
	local k = tostring(f) .. "|" .. tostring(math.clamp(ord, 1, MAX_ORD))
	local s = pend.ttu[k]
	if not s then s = { 0, 0, 0, 0 } ; pend.ttu[k] = s end
	s[1] += 1 ; s[2] += math.max(0, math.floor(pt))
	if days then s[3] += 1 ; s[4] += math.max(0, days) end
end

local function flush()
	if READ_ONLY then return end
	if next(pend.last) == nil and next(pend.ttu) == nil then return end
	local batch = pend
	pend = { last = {}, ttu = {} }
	local ok = pcall(function()
		AGG:UpdateAsync("s" .. MY_SHARD, function(old)
			old = type(old) == "table" and old or {}
			old.last = type(old.last) == "table" and old.last or {}
			old.ttu = type(old.ttu) == "table" and old.ttu or {}
			for dk, cells in pairs(batch.last) do
				local d = type(old.last[dk]) == "table" and old.last[dk] or {}
				for c, n in pairs(cells) do
					local v = (tonumber(d[c]) or 0) + n
					d[c] = (v ~= 0) and v or nil
				end
				old.last[dk] = next(d) and d or nil
			end
			for k, s in pairs(batch.ttu) do
				local o = type(old.ttu[k]) == "table" and old.ttu[k] or { 0, 0, 0, 0 }
				for i = 1, 4 do o[i] = (tonumber(o[i]) or 0) + s[i] end
				old.ttu[k] = o
			end
			return old
		end)
	end)
	if not ok then   -- on garde tout pour le prochain essai
		for dk, cells in pairs(batch.last) do
			for c, n in pairs(cells) do
				local d = pend.last[dk] or {}
				pend.last[dk] = d
				d[c] = (d[c] or 0) + n
			end
		end
		for k, s in pairs(batch.ttu) do
			local o = pend.ttu[k] or { 0, 0, 0, 0 }
			for i = 1, 4 do o[i] += s[i] end
			pend.ttu[k] = o
		end
	end
end
task.spawn(function() while true do task.wait(FLUSH_EVERY) flush() end end)

--════════════════════════════════════════════════════════════
-- 🏷️ TYPE DU JOUEUR (VIP / boosts permanents, achetés OU offerts)
--════════════════════════════════════════════════════════════
local function ownsPass(uid, id)
	for attempt = 1, 2 do
		local ok, r = pcall(function() return MPS:UserOwnsGamePassAsync(uid, id) end)
		if ok then return r == true end
		task.wait(1 * attempt)
	end
	return false
end

-- joueur en ligne : l'attribut publié par PUBLIC_PROFILE ("vip,2,5,10")
local function flagsFromAttr(p)
	local a = p:GetAttribute("ProfileBadges")
	if type(a) ~= "string" then return nil end
	local f = 0
	for w in string.gmatch(a, "[^,]+") do
		local b = BIT[w] or BIT[tonumber(w) or -1]
		if b then f = bit32.bor(f, b) end
	end
	return f
end

-- n'importe quel joueur (même hors ligne)
local function flagsOffline(uid)
	local f = 0
	local vip = false
	if _G.IsVIP then
		local ok, v = pcall(_G.IsVIP, uid)
		vip = ok and v == true
	end
	if not vip then vip = ownsPass(uid, VIP_PASS) end
	if vip then f = bit32.bor(f, BIT.vip) end
	local gifted = {}
	if _G.PermBoosts and _G.PermBoosts.peek then
		local ok, l = pcall(_G.PermBoosts.peek, uid)
		if ok and type(l) == "table" then for _, m in ipairs(l) do gifted[tonumber(m) or -1] = true end end
	end
	for m, id in pairs(BOOST_PASSES) do
		if gifted[m] or ownsPass(uid, id) then f = bit32.bor(f, BIT[m]) end
	end
	return f
end

--════════════════════════════════════════════════════════════
-- 👥 SESSIONS
--════════════════════════════════════════════════════════════
local sess = {}   -- [uid] = { lsd, f, u, pu, tu, fj, fpt }

local function playtime(uid)
	if _G.getCurrentPlaytime then
		local ok, v = pcall(_G.getCurrentPlaytime, uid)
		if ok and tonumber(v) then return tonumber(v) end
	end
	local p = Players:GetPlayerByUserId(uid)
	return tonumber(p and p:GetAttribute("PlaytimeSeconds")) or 0
end

local function ugcCount(uid)
	if _G.UGCRedeem_GetPlayer then
		for _ = 1, 3 do
			local ok, rec = pcall(_G.UGCRedeem_GetPlayer, uid, true)
			if ok and type(rec) == "table" then return clampU(rec.c) end
			task.wait(2)
		end
		return nil
	end
	local ok, rec = pcall(function() return UGC_PLR:GetAsync("u_" .. uid) end)
	if not ok then return nil end
	return clampU(type(rec) == "table" and rec.c or 0)
end

local function onJoin(p)
	local uid = p.UserId
	-- on attend que le jeu ait chargé ses données (temps de jeu)
	local t0 = os.clock()
	while p.Parent and p:GetAttribute("PlaytimeSeconds") == nil and os.clock() - t0 < 40 do task.wait(1) end
	if not p.Parent then return end
	local u = ugcCount(uid)
	if u == nil then return end   -- lecture ratée : on ne compte pas ce joueur (aucune donnée fausse)
	-- le type : attribut de PUBLIC_PROFILE (posé ~6 s après l'arrivée), sinon calculé
	local f
	local t1 = os.clock()
	while p.Parent and os.clock() - t1 < 12 do
		f = flagsFromAttr(p)
		if f then break end
		task.wait(1)
	end
	if not p.Parent then return end
	f = f or flagsOffline(uid)
	local now, dk, pt = os.time(), today(), playtime(uid)
	local prev, cur
	local ok = pcall(function()
		if READ_ONLY then
			prev = USERS:GetAsync("u_" .. uid)
			return
		end
		USERS:UpdateAsync("u_" .. uid, function(old)
			old = type(old) == "table" and old or nil
			prev = old
			cur = {
				fj = old and old.fj or now, fpt = old and old.fpt or pt,
				ls = now, lsd = dk, f = f, u = u,
				pu = old and old.pu or nil, tu = old and old.tu or nil,
				n = ((old and tonumber(old.n)) or 0) + 1, bf = old and old.bf or nil,
			}
			return cur
		end)
	end)
	if not ok then return end
	if not READ_ONLY then
		if prev and type(prev.lsd) == "string" then move(prev.lsd, prev.f, prev.u, -1) end
		move(dk, f, u, 1)
	end
	sess[uid] = {
		lsd = dk, f = f, u = u,
		pu = prev and prev.pu or nil, tu = prev and prev.tu or nil,
		fj = (prev and prev.fj) or now, fpt = (prev and prev.fpt) or pt,
	}
	-- type qui change en cours de partie (achat du VIP, boost offert…)
	p:GetAttributeChangedSignal("ProfileBadges"):Connect(function()
		local s = sess[uid]
		local nf = flagsFromAttr(p)
		if not s or not nf or nf == s.f then return end
		move(s.lsd, s.f, s.u, -1) ; move(s.lsd, nf, s.u, 1)
		s.f = nf
	end)
end

local function onLeave(p)
	local uid = p.UserId
	local s = sess[uid]
	sess[uid] = nil
	if not s or READ_ONLY then return end
	local dk, now = today(), os.time()
	if dk ~= s.lsd then   -- session à cheval sur deux jours : rangé au jour du départ
		move(s.lsd, s.f, s.u, -1) ; move(dk, s.f, s.u, 1)
	end
	local pt = playtime(uid)
	task.spawn(function()
		pcall(function()
			USERS:UpdateAsync("u_" .. uid, function(old)
				old = type(old) == "table" and old or {}
				old.ls, old.lsd, old.f, old.u, old.pt = now, dk, s.f, s.u, math.floor(pt)
				old.pu, old.tu = s.pu, s.tu
				old.fj = old.fj or s.fj ; old.fpt = old.fpt or s.fpt
				return old
			end)
		end)
	end)
end

Players.PlayerAdded:Connect(function(p) task.spawn(onJoin, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end
Players.PlayerRemoving:Connect(onLeave)
game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do pcall(onLeave, p) end
	task.wait(1)
	flush()
end)

--════════════════════════════════════════════════════════════
-- 🎽 UNE UGC OBTENUE (appelé par le UGC REDEEM LOG)
--════════════════════════════════════════════════════════════
local API = {}
_G.PlayerUgcStats = API

function API.OnRedeem(userId)
	userId = tonumber(userId)
	local s = userId and sess[userId]
	if not s then return end   -- hors ligne : corrigé tout seul à sa prochaine connexion
	local nu = clampU(s.u + 1)
	if nu ~= s.u then move(s.lsd, s.f, s.u, -1) ; move(s.lsd, s.f, nu, 1) end
	local ord = s.u + 1
	s.u = nu
	local pt, now = playtime(userId), os.time()
	-- temps de jeu depuis l'UGC précédente (la 1re : depuis le début)
	local base = (ord == 1) and 0 or s.pu
	if base and pt >= base then
		local days
		if ord == 1 then
			-- jours réels seulement pour un joueur suivi depuis son arrivée
			if (tonumber(s.fpt) or 1e9) < 300 then days = (now - (s.fj or now)) / 86400 end
		elseif s.tu then
			days = (now - s.tu) / 86400
		end
		sample(s.f, ord, pt - base, days)
	end
	s.pu, s.tu = math.floor(pt), now
	if READ_ONLY then return end
	task.spawn(function()
		pcall(function()
			USERS:UpdateAsync("u_" .. userId, function(old)
				old = type(old) == "table" and old or {}
				old.u, old.pu, old.tu = s.u, s.pu, s.tu
				return old
			end)
		end)
	end)
end

--════════════════════════════════════════════════════════════
-- 📥 RATTRAPAGE DES JOUEURS DÉJÀ CONNUS (un seul serveur à la fois)
--════════════════════════════════════════════════════════════
local BF = { running = false }
local function budget()
	local ok, b = pcall(function()
		return DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return ok and b or 0
end

local function takeLock(cursor, addN, finished)
	local got, state = false, nil
	pcall(function()
		AGG:UpdateAsync("bf", function(old)
			old = type(old) == "table" and old or { n = 0 }
			if old.done then state = old ; got = false ; return nil end
			local now = os.time()
			if old.owner and old.owner ~= JOB and (tonumber(old.exp) or 0) > now then
				state = old ; got = false ; return nil
			end
			old.owner, old.exp = JOB, now + 180
			if cursor ~= nil then old.cursor = cursor end
			old.n = (tonumber(old.n) or 0) + (addN or 0)
			if finished then old.done, old.owner, old.cursor = true, nil, nil end
			state, got = old, true
			return old
		end)
	end)
	return got, state
end

local function backfillOne(key)
	local uid = tonumber(key)
	if not uid or uid <= 0 then return false end
	if Players:GetPlayerByUserId(uid) then return false end   -- en ligne : compté par onJoin
	local okE, eng = pcall(function() return ENGAGE:GetAsync(key) end)
	if not okE or type(eng) ~= "table" or type(eng.players_u) ~= "string" then return false end
	local lsd = eng.players_u
	local okU, rec = pcall(function() return UGC_PLR:GetAsync("u_" .. uid) end)
	if not okU then return false end
	local u = clampU(type(rec) == "table" and rec.c or 0)
	local f = flagsOffline(uid)
	local created = false
	pcall(function()
		USERS:UpdateAsync("u_" .. uid, function(old)
			if old ~= nil then created = false ; return nil end   -- déjà rangé : on n'y touche pas
			created = true
			return { ls = Cat.DayNoon(lsd), lsd = lsd, f = f, u = u, bf = 1,
				fj = (type(eng.fj) == "string") and Cat.DayNoon(eng.fj) or nil }
		end)
	end)
	if created then move(lsd, f, u, 1) end
	return created
end

local function runBackfill()
	if READ_ONLY or BF.running then return end
	BF.running = true
	local got, st = takeLock(nil, 0, false)
	if not got then BF.running = false ; return end
	local cursor = st and st.cursor
	while true do
		local okP, pages = pcall(function() return ENGAGE:ListKeysAsync(nil, 50, cursor) end)
		if not okP or not pages then break end
		local okC, page = pcall(function() return pages:GetCurrentPage() end)
		if not okC then break end
		local added = 0
		for _, k in ipairs(page) do
			while budget() < 20 do task.wait(2) end
			if backfillOne(k.KeyName) then added += 1 end
			task.wait(1.5)
		end
		if pages.IsFinished then
			takeLock(nil, added, true)
			print("📈 [PlayerUgcStats] Rattrapage terminé")
			break
		end
		local okA = pcall(function() pages:AdvanceToNextPageAsync() end)
		if not okA then break end
		local nc = pages.Cursor
		if type(nc) ~= "string" or nc == "" or nc == cursor then break end
		cursor = nc
		local still = takeLock(cursor, added, false)
		if not still then break end
	end
	BF.running = false
end
task.spawn(function()
	task.wait(90)                         -- laisse démarrer le serveur
	while true do
		pcall(runBackfill)
		task.wait(600)                    -- un autre serveur a la main ou c'est fini : on revérifie plus tard
	end
end)

--════════════════════════════════════════════════════════════
-- 📊 LECTURE POUR L'ADMIN PANEL
--════════════════════════════════════════════════════════════
local function mk(name)
	local r = RS:FindFirstChild(name)
	if not r then r = Instance.new("RemoteFunction") ; r.Name = name ; r.Parent = RS end
	return r
end
local getStats = mk("AdminPlayerStats_Get")
local getLast  = mk("AdminLastSeen_Get")

local cache = { at = -1e9, data = nil }
local busy = {}
getStats.OnServerInvoke = function(player, fresh)
	if not ADMIN[player.UserId] then return { ok = false, err = "non admin" } end
	if busy[player.UserId] then return { ok = false, err = "déjà en cours" } end
	if cache.data and os.clock() - cache.at < ((fresh == true) and 10 or 60) then return cache.data end
	busy[player.UserId] = true
	local ok, res = pcall(function()
		local last, ttu = {}, {}
		local function addLast(src, sign)
			for dk, cells in pairs(type(src) == "table" and src or {}) do
				if type(cells) == "table" then
					local d = last[dk] or {}
					last[dk] = d
					for c, n in pairs(cells) do d[c] = (d[c] or 0) + (tonumber(n) or 0) * sign end
				end
			end
		end
		for i = 1, SHARDS do
			local okS, s = pcall(function() return AGG:GetAsync("s" .. i) end)
			if okS and type(s) == "table" then
				addLast(s.last, 1)
				for k, v in pairs(type(s.ttu) == "table" and s.ttu or {}) do
					local o = ttu[k] or { 0, 0, 0, 0 }
					for j = 1, 4 do o[j] += tonumber(v[j]) or 0 end
					ttu[k] = o
				end
			end
		end
		addLast(pend.last, 1)   -- ce serveur, pas encore écrit
		for k, s in pairs(pend.ttu) do
			local o = ttu[k] or { 0, 0, 0, 0 }
			for j = 1, 4 do o[j] += s[j] end
			ttu[k] = o
		end
		local okB, bf = pcall(function() return AGG:GetAsync("bf") end)
		bf = okB and type(bf) == "table" and bf or {}
		return { ok = true, last = last, ttu = ttu, today = today(), studio = READ_ONLY,
			bf = { done = bf.done == true, n = tonumber(bf.n) or 0, running = bf.owner ~= nil } }
	end)
	busy[player.UserId] = nil
	if not ok then return { ok = false, err = tostring(res) } end
	cache.data, cache.at = res, os.clock()
	return res
end

-- 🕒 Dernière connexion : { [userId] = { t = horodatage } | { d = "AAAAMMJJ" } | { on = true } }
local lastCache = {}
getLast.OnServerInvoke = function(player, ids)
	if not ADMIN[player.UserId] or type(ids) ~= "table" then return {} end
	local out, need = {}, {}
	for i = 1, math.min(#ids, 60) do
		local id = tonumber(ids[i])
		if id and id > 0 and out[tostring(id)] == nil then
			if Players:GetPlayerByUserId(id) then
				out[tostring(id)] = { on = true }
			else
				local c = lastCache[id]
				if c and os.clock() - c.at < 300 then out[tostring(id)] = c.v
				else table.insert(need, id) end
			end
		end
	end
	local idx, left = 0, #need
	local function worker()
		while true do
			idx += 1
			local id = need[idx]
			if not id then return end
			local v
			local okU, u = pcall(function() return USERS:GetAsync("u_" .. id) end)
			if okU and type(u) == "table" and tonumber(u.ls) and not u.bf then
				v = { t = tonumber(u.ls) }
			elseif okU and type(u) == "table" and type(u.lsd) == "string" then
				v = { d = u.lsd }   -- rangé par le rattrapage : on ne connaît que le jour
			else
				local okE, e = pcall(function() return ENGAGE:GetAsync(tostring(id)) end)
				if okE and type(e) == "table" and type(e.players_u) == "string" then v = { d = e.players_u }
				elseif okU and okE then v = { none = true } end
			end
			if v then
				lastCache[id] = { v = v, at = os.clock() }
				out[tostring(id)] = v
			end
			left -= 1
		end
	end
	for _ = 1, math.min(6, #need) do task.spawn(worker) end
	local t0 = os.clock()
	while left > 0 and os.clock() - t0 < 12 do task.wait(0.05) end
	return out
end
task.spawn(function()
	while true do
		task.wait(600)
		for id, c in pairs(lastCache) do if os.clock() - c.at > 600 then lastCache[id] = nil end end
	end
end)

print("✅ PLAYER UGC STATS chargé" .. (READ_ONLY and " (🧪 Studio : lecture seule)" or ""))
