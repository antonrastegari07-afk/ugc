--════════════════════════════════════════════════════════════════════════════
-- 📨 ENGAGEMENT STATS — Script dans ServerScriptService   (NOUVEAU)
--
--  Compte, PAR JOUR (heure de Montréal, comme 💸 REVENUS) :
--   📨 INVITES
--     • prompts d'invitation ouverts (bouton Invite, carrousel d'offres, PNJ… tous)
--     • invitations envoyées (nombre d'amis cochés) et joueurs qui en ont envoyé
--     • amis arrivés grâce à une invitation (lien d'invite → ReferredByPlayerId)
--     • points donnés par le referral (parrain + filleul)
--   📺 PUBS (rewarded ads)
--     • pubs lancées, regardées jusqu'au bout, interrompues, refusées (quota…)
--     • récompenses données et points donnés
--   👥 Joueurs uniques du jour (pour les % : combien de joueurs utilisent l'invite / les pubs)
--
--  Les compteurs sont gardés en mémoire et écrits toutes les 60 s (UpdateAsync,
--  additions : plusieurs serveurs ne s'écrasent jamais). Aucun DataStore par clic.
--  Les « joueurs uniques » sont vérifiés une fois par joueur, par jour et par
--  compteur (un joueur qui change de serveur n'est pas compté deux fois).
--
--  🧪 STUDIO : lit les vraies données, n'écrit JAMAIS rien.
--  🔒 Le client ne peut qu'ANNONCER une invitation (nombre plafonné, anti-spam) :
--     ce sont des stats, aucun point n'est donné ici.
--════════════════════════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local DSS        = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Cat = require(RS:WaitForChild("ProductCatalog"))   -- DayKey / AddDays (jours de Montréal)

local ADMIN = {
	[3203521470] = true, [11017023724] = true, [8456613930] = true,
	[8142402169] = true, [10420404767] = true,
}

local READ_ONLY   = RunService:IsStudio()
local FLUSH_EVERY = 60
local DAYS_STORE  = DSS:GetDataStore("EngageStats_v1")
local USERS_STORE = DSS:GetDataStore("EngageUsers_v1")

local function todayDk() return Cat.DayKey(os.time()) end

--════════════════════════════════════════════════════════════
-- 🧮 COMPTEURS EN MÉMOIRE (deltas pas encore écrits)
--════════════════════════════════════════════════════════════
local pending = {}   -- [dk] = { [compteur] = n }

local function add(key, n, dk)
	n = tonumber(n) or 1
	if n ~= n or n == 0 then return end
	dk = dk or todayDk()
	local d = pending[dk]
	if not d then d = {} ; pending[dk] = d end
	d[key] = (d[key] or 0) + n
end

-- 👥 Joueur unique : une seule fois par joueur / jour / compteur, tous serveurs confondus
local seen = {}      -- [userId] = { [compteur] = dk } (cache de CE serveur)
local function unique(userId, key)
	userId = tonumber(userId)
	if not userId or userId <= 0 then return end
	local dk = todayDk()
	seen[userId] = seen[userId] or {}
	if seen[userId][key] == dk then return end
	seen[userId][key] = dk
	if READ_ONLY then add(key, 1, dk) return end
	task.spawn(function()
		local isNew = false
		for attempt = 1, 3 do
			local ok = pcall(function()
				USERS_STORE:UpdateAsync(tostring(userId), function(old)
					old = type(old) == "table" and old or {}
					if old[key] == dk then isNew = false return nil end
					isNew = true
					old[key] = dk
					return old
				end)
			end)
			if ok then break end
			isNew = false
			task.wait(2 * attempt)
		end
		if isNew then add(key, 1, dk) end
	end)
end

--════════════════════════════════════════════════════════════
-- 💾 ÉCRITURE (toutes les 60 s + à la fermeture)
--════════════════════════════════════════════════════════════
local function flush()
	if READ_ONLY then return end
	local batch = pending
	pending = {}
	for dk, deltas in pairs(batch) do
		local ok = pcall(function()
			DAYS_STORE:UpdateAsync("d_" .. dk, function(old)
				old = type(old) == "table" and old or {}
				for k, n in pairs(deltas) do old[k] = (tonumber(old[k]) or 0) + n end
				return old
			end)
		end)
		if not ok then
			-- on remet les deltas de côté : rien n'est perdu, on réessaie au prochain tour
			for k, n in pairs(deltas) do add(k, n, dk) end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(FLUSH_EVERY)
		flush()
	end
end)
game:BindToClose(function() flush() end)

--════════════════════════════════════════════════════════════
-- 🔌 API serveur (appelée par les autres scripts)
--════════════════════════════════════════════════════════════
local API = {}
_G.EngageStats = API

-- compteur libre (ex. API.Hit("ref_pts", userId, 3000))
function API.Hit(key, userId, n)
	if type(key) ~= "string" or #key > 24 then return end
	add(key, n or 1)
end

-- 📺 résultat d'une demande de pub (sendResult du script des pubs)
local AD_SILENT = { Cooldown = true, Mutex = true }   -- re-clics, pas de vraies demandes
function API.AdResult(userId, success, reason)
	reason = tostring(reason or "?")
	if success then
		add("ad_done") ; unique(userId, "ad_done_u")
	elseif reason == "ShowInterrupted" or reason == "PlayerIneligible" or reason == "AdNotReady"
		or reason == "InternalError" or reason == "UnknownResult" or reason == "Error" or reason == "Timeout"
		or reason == "AdAlreadyShowing" or reason == "InsufficientMemory" then
		add("ad_fail")
	elseif not AD_SILENT[reason] then
		add("ad_deny")
	end
end

-- 📺 une pub est vraiment lancée
function API.AdShown(userId)
	add("ad_show") ; unique(userId, "ad_show_u")
end

-- 📺 récompense donnée
function API.AdReward(userId, points)
	add("ad_rew") ; add("ad_pts", tonumber(points) or 0) ; unique(userId, "ad_rew_u")
end

-- 🎁 points donnés par le referral
function API.Referral(userId, points, source)
	add("ref_pts", tonumber(points) or 0)
	if source == "Referral_Inviter" then add("ref_inviter") end
	if source == "Referral_Invitee" then add("ref_invitee") end
end

--════════════════════════════════════════════════════════════
-- 👥 JOUEURS + 📨 ARRIVÉES PAR INVITATION
--════════════════════════════════════════════════════════════
local function onPlayerAdded(player)
	add("joins") ; unique(player.UserId, "players_u")
	local ok, jd = pcall(function() return player:GetJoinData() end)
	local ref = ok and type(jd) == "table" and tonumber(jd.ReferredByPlayerId)
	if ref and ref > 0 and ref ~= player.UserId then
		add("inv_join") ; unique(player.UserId, "inv_join_u")
	end
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
Players.PlayerRemoving:Connect(function(p)
	local id = p.UserId
	task.delay(120, function() if not Players:GetPlayerByUserId(id) then seen[id] = nil end end)
end)

--════════════════════════════════════════════════════════════
-- 📨 RAPPORTS DU CLIENT (fermeture du prompt d'invitation)
--════════════════════════════════════════════════════════════
local track = RS:FindFirstChild("EngageTrack")
if not track then
	track = Instance.new("RemoteEvent")
	track.Name = "EngageTrack"
	track.Parent = RS
end
local lastReport, perMin = {}, {}
track.OnServerEvent:Connect(function(player, kind, n)
	if kind ~= "invite" then return end
	local uid, now = player.UserId, os.clock()
	if lastReport[uid] and now - lastReport[uid] < 1.5 then return end   -- anti-spam
	local m = perMin[uid]
	if not m or now - m.t > 60 then m = { t = now, n = 0 } ; perMin[uid] = m end
	if m.n >= 10 then return end                                          -- 10 prompts / min max
	m.n += 1
	lastReport[uid] = now
	n = tonumber(n) or 0
	if n ~= n then n = 0 end
	n = math.clamp(math.floor(n), 0, 50)
	add("inv_open") ; unique(uid, "inv_open_u")
	if n > 0 then
		add("inv_sent", n) ; add("inv_ok") ; unique(uid, "inv_sent_u")
	end
end)
Players.PlayerRemoving:Connect(function(p) lastReport[p.UserId] = nil ; perMin[p.UserId] = nil end)

--════════════════════════════════════════════════════════════
-- 📊 LECTURE POUR L'ADMIN PANEL
--════════════════════════════════════════════════════════════
local fn = RS:FindFirstChild("AdminEngage_Get")
if not fn then
	fn = Instance.new("RemoteFunction")
	fn.Name = "AdminEngage_Get"
	fn.Parent = RS
end

local dayCache = {}  -- [dk] = { data, at }
local function readDay(dk, isToday)
	local c = dayCache[dk]
	if c and os.clock() - c.at < (isToday and 30 or 600) then return c.data end
	local ok, d = pcall(function() return DAYS_STORE:GetAsync("d_" .. dk) end)
	if not ok then return c and c.data or {} end
	d = type(d) == "table" and d or {}
	dayCache[dk] = { data = d, at = os.clock() }
	return d
end

local busy = {}
fn.OnServerInvoke = function(player, days)
	if not ADMIN[player.UserId] then return { ok = false, err = "non admin" } end
	days = math.clamp(math.floor(tonumber(days) or 7), 1, 60)
	if busy[player.UserId] then return { ok = false, err = "déjà en cours" } end
	busy[player.UserId] = true
	local ok, res = pcall(function()
		local today = todayDk()
		local out = {}
		for i = days - 1, 0, -1 do
			local dk = Cat.AddDays(today, -i)
			local d = table.clone(readDay(dk, i == 0))
			-- + ce que CE serveur n'a pas encore écrit
			for k, n in pairs(pending[dk] or {}) do d[k] = (tonumber(d[k]) or 0) + n end
			table.insert(out, { dk = dk, l = dk:sub(7, 8) .. "/" .. dk:sub(5, 6), v = d })
		end
		return { ok = true, days = out, studio = READ_ONLY }
	end)
	busy[player.UserId] = nil
	if not ok then return { ok = false, err = tostring(res) } end
	return res
end
Players.PlayerRemoving:Connect(function(p) busy[p.UserId] = nil end)

print("✅ ENGAGEMENT STATS chargé (invites + pubs)" .. (READ_ONLY and " — Studio : lecture seule" or ""))
