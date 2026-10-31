--════════════════════════════════════════════════════════════════════════════
-- 📊 STATS — Script dans ServerScriptService   (v2 : REMPLACE « ENGAGEMENT STATS »)
--   Mêmes DataStores que la v1 : les compteurs déjà enregistrés sont gardés.
--
--  Compte, PAR JOUR (heure de Montréal, comme 💸 REVENUS) :
--   💸 ACHATS PAR PROVENANCE : chaque fenêtre d'achat Roblox ouverte (achetée ou
--      annulée) et chaque achat, avec D'OÙ il vient (bouton, popup, offre auto…)
--      → combien de prompts, d'achats, % de conversion, Robux, par objet.
--   🔔 POPUPS : affichages (popup VIP, bouton pub, popup de départ) → achats.
--   🎽 1re UGC GRATUITE : pour les nouveaux joueurs qui n'ont JAMAIS payé,
--      temps de jeu et jours de connexion avant leur 1re UGC.
--   📨 INVITES / 👥 AMIS / 📺 PUBS / 👥 JOUEURS.
--
--  D'où vient un achat (dans cet ordre) :
--   1. le script qui a ouvert la fenêtre (via MarketplaceServiceFX) ;
--   2. le dernier bouton cliqué par le joueur avant la fenêtre (ex. RAW scripts) ;
--   3. le dernier popup affiché (30 s) ;
--   4. sinon l'objet proposé (ex. coil touché sur la map, pack, offre auto) ;
--   5. sinon « ⚙️ Auto / serveur ».
--  Les fenêtres sont comptées par Roblox lui-même (PromptGamePassPurchaseFinished /
--  PromptProductPurchaseFinished côté serveur) : AUCUNE n'est oubliée, quel que
--  soit le script qui l'ouvre. Les achats de produits sont comptés au reçu
--  (ECONOMY STATS ▸ RecordReceipt), les gamepass quand Roblox confirme l'achat.
--
--  Écritures : compteurs en mémoire, écrits toutes les 60 s (additions, jamais
--  d'écrasement entre serveurs). 🧪 STUDIO : lecture seule.
--════════════════════════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local DSS        = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local MPS        = game:GetService("MarketplaceService")

local Cat = require(RS:WaitForChild("ProductCatalog"))   -- DayKey / AddDays / Name / prix

local ADMIN = {
	[3203521470] = true, [11017023724] = true, [8456613930] = true,
	[8142402169] = true, [10420404767] = true,
}

local READ_ONLY   = RunService:IsStudio()
local FLUSH_EVERY = 60
local DAYS_STORE  = DSS:GetDataStore("EngageStats_v1")
local USERS_STORE = DSS:GetDataStore("EngageUsers_v1")
local AD_PRODUCT  = 3606598159   -- pub récompensée : pas un achat

local function todayDk() return Cat.DayKey(os.time()) end

--════════════════════════════════════════════════════════════
-- 🏷️ NOMS DES PROVENANCES (premier mot trouvé dans le chemin du script / bouton)
--   Une provenance inconnue s'affiche quand même (son nom brut) : rien n'est perdu.
--════════════════════════════════════════════════════════════
local SOURCES = {
	{ "VIP offer",            "🔔 Popup VIP (toutes les 13 min)" },
	{ "Reward_ads",           "📺 Bouton pub" },
	{ "offers_on_screen",     "🎠 Carrousel d'offres" },
	{ "Offers",               "🎠 Carrousel d'offres" },
	{ "10 died",              "💀 Offre après des morts" },
	{ "script_proposer",      "⏰ Offre auto (toutes les 20 min)" },
	{ "PointsShop",           "🛒 Shop de points" },
	{ "ShopGuns",             "🛒 Shop ▸ Armes" },
	{ "ShopTools",            "🛒 Shop ▸ Outils / packs / VIP" },
	{ "ShopCrates",           "🛒 Shop ▸ Crates" },
	{ "Shop.",                "🛒 Shop" },
	{ "Rebirth",              "🔁 Fenêtre Rebirth" },
	{ "Skip Obby",            "⏭️ Bouton Skip Obby" },
	{ "Skip_Obby",            "⏭️ Bouton Skip Obby" },
	{ "Skip Level",           "⏭️ Bouton Skip Level" },
	{ "Skip_Level",           "⏭️ Bouton Skip Level" },
	{ "system_navigation",    "⏭️ Navigation des niveaux" },
	{ "speedcoil",            "🌀 Coil touché sur la map" },
	{ "fusion_coil",          "🌀 Coil touché sur la map" },
	{ "gravity_coil",         "🌀 Coil touché sur la map" },
	{ "x2coin",               "🪙 x2 coin touché sur la map" },
	{ "dailyspin",            "🎡 Roue / spins" },
	{ "DailySpin",            "🎡 Roue / spins" },
	{ "streak",               "🔥 Streak (recover)" },
	{ "Streak",               "🔥 Streak (recover)" },
	{ "donation",             "💚 Board de dons" },
	{ "Donation",             "💚 Board de dons" },
	{ "Gift",                 "🎁 Gifting" },
	{ "GIFT",                 "🎁 Gifting" },
	{ "Halloween",            "🎃 Halloween" },
	{ "NoDeath",              "🏃 Quête No Death (VIP)" },
	{ "Stage",                "⚔️ Kills journaliers (VIP)" },
	{ "1v1",                  "⚔️ Arène / 1v1" },
	{ "Arena",                "⚔️ Arène / 1v1" },
	{ "UGCshop",              "🎽 Shop UGC" },
	{ "PlayerProfile",        "👤 Fiche profil" },
	{ "Settings",             "⚙️ Settings" },
	{ "leave",                "🚪 Popup de départ" },
}
-- objet proposé SANS clic ni script connu (offres lancées par le serveur)
local AUTO_BY_ITEM = {
	gp1890659135 = "🌀 Coil touché sur la map", gp1889975133 = "🌀 Coil touché sur la map",
	gp1890875059 = "🌀 Coil touché sur la map", gp1890143127 = "🧲 Objet touché sur la map (Jetpack)",
	gp1889735131 = "🧲 Objet touché sur la map (Slap Hand)",
	gp1894006285 = "⏰ Offre auto (toutes les 20 min)",
	gp1889633102 = "🎒 Pack proposé (serveur)", gp1890203086 = "🎒 Pack proposé (serveur)",
	dp3606598763 = "💀 Offre après des morts", dp3606598188 = "💀 Offre après des morts",
}
local POPUPS = {   -- id envoyé par le client → nom + provenance liée (pour les achats)
	vip_offer   = { label = "🔔 Popup VIP (toutes les 13 min)", src = "🔔 Popup VIP (toutes les 13 min)" },
	ad_button   = { label = "📺 Bouton pub (pub dispo)",         src = "📺 Bouton pub" },
	leave_popup = { label = "🚪 Popup de départ",                src = "🚪 Popup de départ" },
}

local labelCache = {}
local function labelOf(raw)
	raw = tostring(raw or "")
	local c = labelCache[raw]
	if c then return c end
	-- chemin sans « Players.<pseudo>.PlayerGui » (jamais de pseudo dans les stats)
	local clean = raw:gsub("^Players%.[^%.]+%.PlayerGui%.", ""):gsub("^Players%.[^%.]+%.PlayerScripts%.", "")
		:gsub("^Players%.[^%.]+%.Backpack%.", ""):gsub("^StarterPlayer%.StarterPlayerScripts%.", "")
		:gsub("^ServerScriptService%.", ""):gsub("^ReplicatedStorage%.", "")
	local out
	for _, s in ipairs(SOURCES) do
		if string.find(clean, s[1], 1, true) then out = s[2] break end
	end
	if not out then
		local a, b = clean:match("^([^%.]+)%.?([^%.]*)")
		out = "❔ " .. (a or "?") .. ((b and b ~= "") and (" ▸ " .. b) or "")
	end
	out = out:sub(1, 60)
	labelCache[raw] = out
	return out
end

--════════════════════════════════════════════════════════════
-- 🧮 COMPTEURS EN MÉMOIRE (deltas pas encore écrits)
--════════════════════════════════════════════════════════════
local pending = {}   -- [dk] = { [compteur] = n, ttu = { échantillons } }

local function add(key, n, dk)
	n = tonumber(n) or 1
	if n ~= n or n == 0 then return end
	dk = dk or todayDk()
	local d = pending[dk]
	if not d then d = {} ; pending[dk] = d end
	d[key] = (d[key] or 0) + n
end

local function addSample(sample)
	local dk = todayDk()
	local d = pending[dk]
	if not d then d = {} ; pending[dk] = d end
	d.ttu = d.ttu or {}
	table.insert(d.ttu, sample)
end

-- 👥 Joueur unique : une seule fois par joueur / jour / compteur, tous serveurs confondus
local seen = {}
local function unique(userId, key, onNew)
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
					if onNew then onNew(old) end
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
local MAX_SAMPLES_DAY = 400
local function flush()
	if READ_ONLY then return end
	local batch = pending
	pending = {}
	for dk, deltas in pairs(batch) do
		local ok = pcall(function()
			DAYS_STORE:UpdateAsync("d_" .. dk, function(old)
				old = type(old) == "table" and old or {}
				for k, n in pairs(deltas) do
					if k == "ttu" then
						old.ttu = type(old.ttu) == "table" and old.ttu or {}
						for _, s in ipairs(n) do
							if #old.ttu < MAX_SAMPLES_DAY then table.insert(old.ttu, s) end
						end
					else
						old[k] = (tonumber(old[k]) or 0) + n
					end
				end
				return old
			end)
		end)
		if not ok then
			for k, n in pairs(deltas) do
				if k == "ttu" then for _, s in ipairs(n) do addSample(s) end else add(k, n, dk) end
			end
		end
	end
end
task.spawn(function()
	while true do task.wait(FLUSH_EVERY) flush() end
end)
game:BindToClose(function() flush() end)

--════════════════════════════════════════════════════════════
-- 💸 PROVENANCE DES ACHATS
--════════════════════════════════════════════════════════════
local ctx = {}   -- [uid] = { items = {[itemKey]={src,t}}, click = {src,t}, popup = {src,t}, resolved = {[itemKey]={src,t}} }
local function ctxOf(uid)
	local c = ctx[uid]
	if not c then c = { items = {}, resolved = {} } ctx[uid] = c end
	return c
end

local function itemKey(kind, id) return kind .. tostring(id) end   -- "gp1891589121" / "dp3606598188"

local function resolve(uid, key, window)
	local c = ctxOf(uid)
	local now = os.clock()
	local r = c.resolved[key]
	if r and now - r.t <= 900 then return r.src end
	local e = c.items[key]
	if e and now - e.t <= 60 then return e.src end
	if c.click and now - c.click.t <= (window or 120) then return c.click.src end
	if c.popup and now - c.popup.t <= 30 then return c.popup.src end
	return AUTO_BY_ITEM[key] or "⚙️ Auto / serveur"
end

local priceCache = {}
local function priceOf(kind, id)
	local m = kind == "gp" and Cat.Passes[id] or Cat.Products[id]
	if m and tonumber(m.p) then return tonumber(m.p) end
	if priceCache[kind .. id] then return priceCache[kind .. id] end
	local ok, info = pcall(function()
		return MPS:GetProductInfo(id, kind == "gp" and Enum.InfoType.GamePass or Enum.InfoType.Product)
	end)
	local p = ok and type(info) == "table" and tonumber(info.PriceInRobux) or 0
	priceCache[kind .. id] = p
	return p
end

local function countPrompt(uid, kind, id)
	local key = itemKey(kind, id)
	local src = resolve(uid, key)
	ctxOf(uid).resolved[key] = { src = src, t = os.clock() }
	add("pr|" .. src .. "|" .. key) ; add("pr_tot")
	unique(uid, "pr_u")
	return src
end

local function countBuy(uid, kind, id, robux)
	local key = itemKey(kind, id)
	local src = resolve(uid, key, 900)
	robux = math.max(0, math.floor(tonumber(robux) or priceOf(kind, id)))
	add("by|" .. src .. "|" .. key) ; add("rb|" .. src, robux)
	add("by_tot") ; add("rb_tot", robux)
	unique(uid, "by_u")
end

-- fenêtres d'achat (toutes, quel que soit le script qui les ouvre)
MPS.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	passId = tonumber(passId)
	if not passId then return end
	-- 2 s d'attente : le client envoie le bouton cliqué au moment où la fenêtre se ferme
	task.delay(2, function()
		countPrompt(player.UserId, "gp", passId)
		-- achat compté seulement si Roblox confirme que le joueur possède le pass
		-- (ce signal peut être envoyé par un client tricheur : on ne le croit pas sur parole)
		if purchased == true then
			local ok, owns = pcall(function() return MPS:UserOwnsGamePassAsync(player.UserId, passId) end)
			if ok and owns then countBuy(player.UserId, "gp", passId) end
		end
	end)
end)
pcall(function()
	MPS.PromptProductPurchaseFinished:Connect(function(userId, productId, _purchased)
		productId = tonumber(productId)
		if not productId or productId == AD_PRODUCT then return end
		task.delay(2, function() countPrompt(tonumber(userId), "dp", productId) end)
	end)
end)

--════════════════════════════════════════════════════════════
-- 🔌 API serveur
--════════════════════════════════════════════════════════════
local API = {}
_G.EngageStats = API

function API.Hit(key, userId, n)
	if type(key) ~= "string" or #key > 24 then return end
	add(key, n or 1)
end

-- MarketplaceServiceFX (serveur) : quel script ouvre la fenêtre
function API.NoteSource(player, rawSrc, method, itemId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local kind = (method == "PromptGamePassPurchase" and "gp") or (method == "PromptProductPurchase" and "dp") or nil
	itemId = tonumber(itemId)
	if not kind or not itemId then return end
	ctxOf(player.UserId).items[itemKey(kind, itemId)] = { src = labelOf(rawSrc), t = os.clock() }
end

-- ECONOMY STATS ▸ RecordReceipt : un produit VRAIMENT payé (reçu accordé)
function API.Purchase(userId, productId, robux)
	userId, productId = tonumber(userId), tonumber(productId)
	if not userId or not productId or productId == AD_PRODUCT then return end
	task.delay(2, function() countBuy(userId, "dp", productId, robux) end)
end

-- 📺 pubs
local AD_SILENT = { Cooldown = true, Mutex = true }
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
function API.AdShown(userId) add("ad_show") ; unique(userId, "ad_show_u") end
function API.AdReward(userId, points)
	add("ad_rew") ; add("ad_pts", tonumber(points) or 0) ; unique(userId, "ad_rew_u")
end

-- 🎁 referral
function API.Referral(userId, points, source)
	add("ref_pts", tonumber(points) or 0)
	if source == "Referral_Inviter" then add("ref_inviter") end
	if source == "Referral_Invitee" then add("ref_invitee") end
end

-- 🎽 1re UGC GRATUITE (appelé par le UGC REDEEM LOG pour chaque redeem confirmé)
local function robuxSpent(uid)
	if not (_G.EconStats and _G.EconStats.GetPlayer) then return nil end
	local ok, d = pcall(_G.EconStats.GetPlayer, uid)
	if not ok or type(d) ~= "table" then return nil end
	return tonumber(d.total) or 0
end
function API.UGCRedeemed(userId)
	userId = tonumber(userId)
	if not userId then return end
	task.delay(4, function()          -- laisse le log écrire la fiche avant de la relire
		local player = Players:GetPlayerByUserId(userId)
		if not player then return end
		if not (_G.UGCRedeem_GetPlayer) then return end
		local ok, rec = pcall(_G.UGCRedeem_GetPlayer, userId, true)
		if not ok or type(rec) ~= "table" or tonumber(rec.c) ~= 1 then return end   -- seulement la 1re
		local spent = robuxSpent(userId)
		if spent == nil or spent > 0 or player:GetAttribute("IsVIP") == true then return end   -- 100 % gratuit
		local okU, u = pcall(function() return USERS_STORE:GetAsync(tostring(userId)) end)
		if not okU or type(u) ~= "table" or not u.nw then return end    -- nouveau joueur suivi depuis son arrivée
		local pt = tonumber(player:GetAttribute("PlaytimeSeconds")) or 0
		local dc = tonumber(u.dc) or 1
		local cd = 0
		if type(u.fj) == "string" then
			local d = u.fj
			while d < todayDk() and cd < 400 do d = Cat.AddDays(d, 1) ; cd += 1 end
		end
		addSample({ pt = math.floor(pt), dc = dc, cd = cd })
		add("ttu_n")
	end)
end

--════════════════════════════════════════════════════════════
-- 👥 JOUEURS (+ jours de connexion, nouveaux joueurs) · 📨 ARRIVÉES PAR INVITATION · AMIS
--════════════════════════════════════════════════════════════
local function onPlayerAdded(player)
	add("joins")
	task.spawn(function()
		-- le temps de jeu arrive avec les données du joueur : on l'attend (30 s max)
		local t0 = os.clock()
		while player.Parent and player:GetAttribute("PlaytimeSeconds") == nil and os.clock() - t0 < 30 do
			task.wait(1)
		end
		if not player.Parent then return end
		local pt0 = tonumber(player:GetAttribute("PlaytimeSeconds"))
		unique(player.UserId, "players_u", function(rec)
			rec.dc = (tonumber(rec.dc) or 0) + 1             -- jours de connexion (comptés depuis l'installation)
			if not rec.fj then
				rec.fj = todayDk()
				-- « nouveau joueur » = très peu de temps de jeu à sa 1re visite suivie
				rec.nw = (pt0 ~= nil and pt0 < 300) or nil
			end
		end)
	end)
	local ok, jd = pcall(function() return player:GetJoinData() end)
	local ref = ok and type(jd) == "table" and tonumber(jd.ReferredByPlayerId)
	if ref and ref > 0 and ref ~= player.UserId then
		add("inv_join") ; unique(player.UserId, "inv_join_u")
	end
	-- joue avec au moins 1 ami (attribut FriendCount du jeu) : vérifié après 60 s puis toutes les 5 min
	task.spawn(function()
		task.wait(60)
		while player.Parent do
			if (tonumber(player:GetAttribute("FriendCount")) or 0) > 0 then
				unique(player.UserId, "friend_u")
				break
			end
			task.wait(300)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
Players.PlayerRemoving:Connect(function(p)
	local id = p.UserId
	task.delay(120, function()
		if not Players:GetPlayerByUserId(id) then seen[id] = nil ; ctx[id] = nil end
	end)
end)

--════════════════════════════════════════════════════════════
-- 📡 RAPPORTS DU CLIENT (EngageTrack) — anti-spam, valeurs bornées
--════════════════════════════════════════════════════════════
local track = RS:FindFirstChild("EngageTrack")
if not track then
	track = Instance.new("RemoteEvent")
	track.Name = "EngageTrack"
	track.Parent = RS
end
local budget = {}
local function allow(uid, n)
	local now = os.clock()
	local b = budget[uid]
	if not b or now - b.t > 60 then b = { t = now, n = 0 } budget[uid] = b end
	b.n += 1
	return b.n <= (n or 30)
end
track.OnServerEvent:Connect(function(player, kind, a, b, c)
	local uid = player.UserId
	if type(kind) ~= "string" or not allow(uid, 40) then return end
	if kind == "invite" then
		add("inv_open") ; unique(uid, "inv_open_u")
	elseif kind == "src" then                       -- MarketplaceServiceFX côté client
		if type(a) ~= "string" or #a > 300 then return end
		API.NoteSource(player, a, b, c)
	elseif kind == "click" then                     -- dernier bouton cliqué avant une fenêtre d'achat
		if type(a) ~= "string" or #a > 300 then return end
		ctxOf(uid).click = { src = labelOf(a), t = os.clock() }
	elseif kind == "pop" then                       -- popup affiché
		local p = type(a) == "string" and POPUPS[a]
		if not p then return end
		add("pop|" .. a) ; unique(uid, "popu|" .. a)
		ctxOf(uid).popup = { src = p.src, t = os.clock() }
	end
end)
Players.PlayerRemoving:Connect(function(p) budget[p.UserId] = nil end)

--════════════════════════════════════════════════════════════
-- 📊 LECTURE POUR L'ADMIN PANEL
--════════════════════════════════════════════════════════════
local fn = RS:FindFirstChild("AdminEngage_Get")
if not fn then
	fn = Instance.new("RemoteFunction")
	fn.Name = "AdminEngage_Get"
	fn.Parent = RS
end

local dayCache = {}
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
			for k, n in pairs(pending[dk] or {}) do
				if k == "ttu" then
					d.ttu = table.clone(type(d.ttu) == "table" and d.ttu or {})
					for _, s in ipairs(n) do table.insert(d.ttu, s) end
				else
					d[k] = (tonumber(d[k]) or 0) + n
				end
			end
			table.insert(out, { dk = dk, l = dk:sub(7, 8) .. "/" .. dk:sub(5, 6), v = d })
		end
		local popups = {}
		for id, p in pairs(POPUPS) do popups[id] = { label = p.label, src = p.src } end
		return { ok = true, days = out, popups = popups, studio = READ_ONLY }
	end)
	busy[player.UserId] = nil
	if not ok then return { ok = false, err = tostring(res) } end
	return res
end
Players.PlayerRemoving:Connect(function(p) busy[p.UserId] = nil end)

print("✅ STATS v2 chargé (achats par provenance, popups, 1re UGC gratuite, invites, pubs)"
	.. (READ_ONLY and " — Studio : lecture seule" or ""))
