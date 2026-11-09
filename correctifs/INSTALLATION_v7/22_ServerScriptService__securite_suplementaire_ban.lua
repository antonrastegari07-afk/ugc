-- ========================================
-- AbsoluteCapProtection V5.2 - SERVER-ONLY SÉCURISÉ
-- À placer dans ServerScriptService
-- ========================================

local Players            = game:GetService("Players")
local DataStoreService   = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

-- ✅ NOUVEAU : Liaison avec le script de points
local CapBridge = require(script.Parent.CapBridge)
local CapFirstJoinBridge = require(script.Parent.CapFirstJoinBridge)

local capData      = {}
local initialized  = {}
local multiplierCache = {}
local sessionBanLog = {}
local capRestricted = {}   -- [userId] = privation d'UGC déjà demandée cette session

local function waitForGlobal(name, timeout)
	local t = 0
	while _G[name] == nil and t < (timeout or 30) do
		task.wait(0.1)
		t = t + 0.1
	end
	return _G[name]
end

task.spawn(function()
	local AntiExploit = waitForGlobal("AntiExploit", 30)
	local dataLoading = waitForGlobal("dataLoading",  30)

	if not AntiExploit then
		warn("❌ AbsoluteCapProtection V5.2: script principal pas chargé")
		return
	end

	local banStore    = DataStoreService:GetDataStore("BannedPlayers")
	local capStore    = DataStoreService:GetDataStore("PlayerCapData_v5")
	local banLogStore = DataStoreService:GetDataStore("CapBanLog_v3")
	local BAN_LOG_KEY = "ban_log"

	local GAMEPASS_MULTIPLIERS = {
		[1891589121] = 2,
		[1891007119] = 2,
		[1893682680] = 5,
		[1891475116] = 10,
	}

	local CAP_CONFIG = {
		BASE_PTS_PER_SEC = 1,
		
		-- ✅ Gains légitimes connus du jeu
		GAME_UNIQUE_QUEST_CAP = 310000,  -- One-time (EggHunt + marge)
		GAME_DAILY_QUEST_CAP  = 200000,  -- Gains journaliers max répétables (Quest10K ×3/8h + Kill + Checkpoint + Playtime + Daily + Streak)


		-- ✅ MODIFIÉ : Les paliers servent maintenant à lisser la courbe
		-- au-delà de 15 jours le cap continue de croître linéairement
		TIME_LAYERS = {
			{ days = 1  },
			{ days = 2  },
			{ days = 3  },
			{ days = 5  },
			{ days = 7  },
			{ days = 10 },
			{ days = 15 },
			-- Au-delà : croissance linéaire (1 jour réel = 1 jour de cap)
		},

		BUFFER = 2,

		DEV_PRODUCT_CAP_BONUS = {
			[3606598188] = 1000,
			[3606598763] = 2500,
			[3606598849] = 100000,
			[3606598712] = 500000,
			[3606598746] = 2000000,
		},

		CHECK_INTERVAL = 30,
	}

	-- ────────────────────────────────────────────
	-- CALCUL DU MULTIPLICATEUR (retourne la valeur)
	-- ────────────────────────────────────────────
	local function computeMultiplier(player)
		local userId = player.UserId
		local total  = 1
		local hasVipPass = false
		for passId, bonus in pairs(GAMEPASS_MULTIPLIERS) do
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
			end)
			if ok and owns then
				total = total + bonus
				if passId == 1891589121 then hasVipPass = true end
			end
		end
		-- 👑 VIP offert par un admin : le cap DOIT connaître le même x2 que le
		--    script de points, sinon le joueur dépasse son plafond et se fait
		--    bannir alors qu'il gagne légitimement.
		if not hasVipPass and _G.IsVIP and _G.IsVIP(userId) then
			total = total + (GAMEPASS_MULTIPLIERS[1891589121] or 2)
		end
		-- ✨ Boosts permanents offerts : le cap DOIT connaître le même bonus
		--    que le script de points, sinon le joueur dépasse son plafond et
		--    se fait bannir alors qu'il gagne légitimement.
		--    getMultiplier renvoie 0 tant que PermBoosts n'a pas chargé —
		--    même valeur que côté points, donc les deux restent cohérents.
		total = total + ((_G.PermBoosts and _G.PermBoosts.getMultiplier(userId)) or 0)
		multiplierCache[userId] = total
		return total  -- ✅ Retourne la valeur pour usage immédiat
	end
	local function getPlayerMultiplier(userId)
		return multiplierCache[userId] or 1
	end
	-- 🔄 VIP admin donné / retiré → le cap se recale immédiatement
	task.spawn(function()
		local ev = game:GetService("ServerStorage"):WaitForChild("VIPStatusChanged", 60)
		if not ev then return end
		ev.Event:Connect(function(userId)
			local p = Players:GetPlayerByUserId(userId)
			if p then computeMultiplier(p) end
		end)
	end)

	-- ✨ Boost permanent accordé / retiré / chargé → même recalage.
	--    L'événement part AUSSI à la fin du chargement : sans ça le cap
	--    resterait sur la valeur d'avant et bannirait un joueur légitime.
	task.spawn(function()
		local ev = game:GetService("ServerStorage"):WaitForChild("PermBoostChanged", 60)
		if not ev then return end
		ev.Event:Connect(function(userId)
			local p = Players:GetPlayerByUserId(userId)
			if p then computeMultiplier(p) end
		end)
	end)

	-- ────────────────────────────────────────────
	-- ✅ NOUVEAU : CALCUL DU CAP ILLIMITÉ DANS LE TEMPS
	-- Logique :
	--   - Avant 15 jours : paliers progressifs (comportement original)
	--   - Après 15 jours : croissance linéaire continue (playtime réel en jours)
	--   - Les dépenses UGC/DevProduct s'ajoutent toujours par-dessus
	-- ────────────────────────────────────────────
	local function getMaxPoints(userId)
		local data = capData[userId]
		if not data then
			-- FIX V5.3: Retourner nil au lieu d'un cap minimal pour faire SKIP le check
			return nil
		end

		local playtime   = os.time() - data.firstJoin
		local playtimeDays = playtime / 86400

		-- FIX V5.3: Si firstJoin dans le futur, skip
		if playtime < 0 then
			warn(string.format("⚠️ getMaxPoints: firstJoin dans le futur pour UserID %d, skip", userId))
			return nil
		end

		local multiplier = getPlayerMultiplier(userId)

		local cappedDays
		if playtimeDays >= 15 then
			cappedDays = playtimeDays
		else
			cappedDays = 15
			for _, layer in ipairs(CAP_CONFIG.TIME_LAYERS) do
				if playtimeDays <= layer.days then
					cappedDays = layer.days
					break
				end
			end
		end

		local baseCap = math.floor(
			CAP_CONFIG.BASE_PTS_PER_SEC * 86400 * cappedDays * multiplier * CAP_CONFIG.BUFFER
		)

		local gameQuestCap = CAP_CONFIG.GAME_UNIQUE_QUEST_CAP
			+ math.floor(CAP_CONFIG.GAME_DAILY_QUEST_CAP * cappedDays)

		baseCap = baseCap + gameQuestCap

		local spent = CapBridge.getTotalSpent(userId)
		local gains = CapBridge.getTotalGains(userId)

		local bonus = data.devProductBonus
		if type(bonus) ~= "number" or bonus < 0 then bonus = 0 end

		return baseCap + bonus - spent + gains
	end
	-- ────────────────────────────────────────────
	-- CHARGEMENT DATASTORE
	-- ────────────────────────────────────────────
	local function loadCapData(player)
		local userId = player.UserId
		local key    = "cap_" .. userId
		local now    = os.time()
		local storedData = nil

		-- FIX V5.3: Capturer l'état actuel AVANT GetAsync
		-- Si tryRestoreP2FromSnapshot a déjà rempli capData, on le garde
		local preExisting = capData[userId]

		local getOk, existing = pcall(function()
			return capStore:GetAsync(key)
		end)

		if getOk
			and existing
			and type(existing) == "table"
			and type(existing.firstJoin) == "number"
			and existing.firstJoin > 0
			and existing.firstJoin <= now
		then
			storedData = {
				firstJoin       = existing.firstJoin,
				devProductBonus = type(existing.devProductBonus) == "number"
					and math.max(0, existing.devProductBonus) or 0,
				totalSpent      = type(existing.totalSpent) == "number"
					and math.max(0, existing.totalSpent) or 0,
				totalGains      = type(existing.totalGains) == "number"
					and math.max(0, existing.totalGains) or 0,
			}
			print(string.format("✅ CapData trouvé: %s | firstJoin=%.2fj | bonus=%d",
				player.Name, (now - storedData.firstJoin) / 86400, storedData.devProductBonus))

		elseif not getOk then
			warn(string.format("⚠️ loadCapData: GetAsync échoué pour %s (%s), retry dans 5s",
				player.Name, tostring(existing)))

			-- FIX V5.3: Si preExisting (snapshot) est là, on le garde
			if preExisting and preExisting.firstJoin and preExisting.firstJoin > 0 then
				print(string.format("ℹ️ loadCapData: preExisting conservé (snapshot) pour %s", player.Name))
				initialized[userId] = true
				CapFirstJoinBridge.set(userId, preExisting.firstJoin)
				task.spawn(function()
					if player.Parent then computeMultiplier(player) end
				end)
			end

			task.spawn(function()
				task.wait(5)
				if player.Parent then
					loadCapData(player)
				end
			end)
			return

		else
			-- existing == nil : DataStore a répondu "pas de données"
			-- FIX V5.3: MAIS si preExisting (snapshot) est là, NE PAS écraser avec os.time()
			if preExisting and preExisting.firstJoin and preExisting.firstJoin > 0 and preExisting.firstJoin < now then
				print(string.format(
					"ℹ️ loadCapData: DataStore vide mais snapshot actif pour %s, conservation (firstJoin=%.2fj)",
					player.Name, (now - preExisting.firstJoin) / 86400
					))
				storedData = {
					firstJoin       = preExisting.firstJoin,
					devProductBonus = preExisting.devProductBonus or 0,
					totalSpent      = CapBridge.getTotalSpent(userId) or 0,
					totalGains      = CapBridge.getTotalGains(userId) or 0,
				}
				-- Persister pour le prochain join
				pcall(function()
					capStore:SetAsync(key, storedData)
				end)
			else
				-- Vraiment nouveau joueur
				-- 🛡️ FIX FAUX-BAN : un code / cadeau / achat a pu monter son cap AVANT la fin du
				--    chargement (bonus en mémoire). Avant, on l'écrasait par 0 → cap trop bas → ban.
				local earlyBonus = (preExisting and type(preExisting.devProductBonus) == "number")
					and math.max(0, preExisting.devProductBonus) or 0
				storedData = { 
					firstJoin = now, 
					devProductBonus = earlyBonus, 
					totalSpent = 0, 
					totalGains = 0 
				}
				pcall(function()
					capStore:UpdateAsync(key, function(existing)
						if type(existing) == "table" and type(existing.firstJoin) == "number" then
							-- écrit entre-temps par un bonus : on garde la plus grande valeur
							existing.devProductBonus = math.max(tonumber(existing.devProductBonus) or 0, earlyBonus)
							return existing
						end
						return storedData
					end)
				end)
				print(string.format("🆕 Nouveau joueur CapData: %s", player.Name))
			end
		end

		local fj = storedData.firstJoin
		if type(fj) ~= "number" or fj <= 0 or fj > now then
			fj = now
		end

		-- FIX V5.3: Si preExisting a une firstJoin plus ancienne, la garder (favorable au joueur)
		if preExisting and preExisting.firstJoin and preExisting.firstJoin < fj then
			print(string.format(
				"ℹ️ loadCapData: snapshot firstJoin plus ancien pour %s (%.2fj vs %.2fj), on garde snapshot",
				player.Name,
				(now - preExisting.firstJoin) / 86400,
				(now - fj) / 86400
				))
			fj = preExisting.firstJoin
		end

		local bonus = storedData.devProductBonus
		if type(bonus) ~= "number" or bonus < 0 then bonus = 0 end
		-- 🛡️ FIX FAUX-BAN : bonus ajouté en mémoire pendant le chargement (pas encore relu)
		local live = capData[userId]
		if live and type(live.devProductBonus) == "number" and live.devProductBonus > bonus then
			bonus = live.devProductBonus
		end

		capData[userId] = {
			firstJoin       = fj,
			devProductBonus = bonus,
		}

		CapBridge.setTotalSpent(userId, storedData.totalSpent or 0)
		CapBridge.setTotalGains(userId, storedData.totalGains or 0)

		initialized[userId] = true

		CapFirstJoinBridge.set(userId, fj)

		local now2 = os.time()
		print(string.format("📦 CapData chargé pour %s | firstJoin=%.2fj | bonus=%d | spent=%d | gains=%d",
			player.Name, (now2 - fj) / 86400, bonus, storedData.totalSpent or 0, storedData.totalGains or 0))

		task.spawn(function()
			if player.Parent then
				local mult = computeMultiplier(player)
				print(string.format("✅ Cap final: %s | mult=x%d | cap=%s",
					player.Name, mult, tostring(getMaxPoints(userId))))
			end
		end)
	end

	-- ────────────────────────────────────────────
	-- SAUVEGARDE (inclut totalSpent)
	-- ────────────────────────────────────────────
	local function saveCapData(userId)
		local data = capData[userId]
		if not data then return end
		task.spawn(function()
			pcall(function()
				capStore:UpdateAsync("cap_" .. userId, function(existing)
					if not existing or type(existing) ~= "table" then return data end
					existing.devProductBonus = data.devProductBonus
					existing.totalSpent = CapBridge.getTotalSpent(userId)
					-- ✅ NOUVEAU
					existing.totalGains = CapBridge.getTotalGains(userId)
					return existing
				end)
			end)
		end)
	end

	local function saveCapDataSync(userId)
		local data = capData[userId]
		if not data then return end
		pcall(function()
			capStore:UpdateAsync("cap_" .. userId, function(existing)
				if not existing or type(existing) ~= "table" then return data end
				existing.devProductBonus = data.devProductBonus
				existing.totalSpent = CapBridge.getTotalSpent(userId)
				-- ✅ NOUVEAU
				existing.totalGains = CapBridge.getTotalGains(userId)
				return existing
			end)
		end)
	end

	-- ────────────────────────────────────────────
	-- ✅ ABONNEMENT CapBridge : sauvegarder quand le joueur dépense
	-- ────────────────────────────────────────────
	CapBridge.onSpend(function(userId, amount, total)
		-- Sauvegarde async du nouveau totalSpent dans le cap DataStore
		local data = capData[userId]
		if not data then return end
		task.spawn(function()
			pcall(function()
				capStore:UpdateAsync("cap_" .. userId, function(existing)
					if not existing or type(existing) ~= "table" then return end
					existing.totalSpent = total
					return existing
				end)
			end)
		end)
		print(string.format("💾 CapBridge: totalSpent mis à jour pour UserID %d → %d", userId, total))
	end)
	
	-- ✅ NOUVEAU : Sauvegarder quand le joueur reçoit des points via une box
	CapBridge.onGain(function(userId, amount, total)
		local data = capData[userId]
		if not data then return end
		task.spawn(function()
			pcall(function()
				capStore:UpdateAsync("cap_" .. userId, function(existing)
					if not existing or type(existing) ~= "table" then return end
					existing.totalGains = total
					return existing
				end)
			end)
		end)
		print(string.format("💾 CapBridge: totalGains mis à jour pour UserID %d → %d", userId, total))
	end)

	-- ────────────────────────────────────────────
	-- BAN PERMANENT (inchangé)
	-- ────────────────────────────────────────────
	local function absoluteBan(player, reason, details)
		local userId = player.UserId
		local now    = os.time()

		-- 🛡️ le MODE choisi dans le panel (🚫 UGC BAN ▸ ⚙️ Réglages) décide : en « privation
		--    d'UGC » ou en shadow, aucun ban (avant, ce script bannissait en ignorant le mode).
		local AC = _G.ACConfig
		if AC then
			local okM, mode = pcall(function() return AC.Mode and AC.Mode() end)
			local okP, punish = pcall(function() return AC.ShouldPunish == nil or AC.ShouldPunish() end)
			if (okM and mode ~= nil and mode ~= "ban") or (okP and punish == false) then
				warn(string.format("🛡️ CAP : pas de ban pour %s (mode %s) | %s | %s",
					player.Name, tostring(mode), reason, details))
				local UR = _G.UGCRestrict
				if UR and UR.NoteDetection then pcall(UR.NoteDetection, userId) end
				-- mode « privation d'UGC » : la sanction du mode, mais JAMAIS pour un joueur de moins
				-- de 3 jours (son cap est petit, un gros gain légitime peut le dépasser)
				local data = capData[userId]
				local age = data and data.firstJoin and (now - data.firstJoin) or 0
				if okM and mode == "ugc" and not (okP and punish == false) and age >= 3 * 86400
					and UR and UR.Add and not capRestricted[userId] then
					capRestricted[userId] = true   -- une seule tentative par session (Add refuse les doublons)
					task.spawn(pcall, UR.Add, userId, {
						by = "AbsoluteCap", auto = true, reason = "anticheat_points",
						details = reason .. " | " .. details, name = player.Name,
					})
				end
				return
			end
		end

		warn(string.format("🚫 CAP BAN | %s (ID: %d) | %s | %s",
			player.Name, userId, reason, details))

		AntiExploit.bannedPlayers[userId] = true

		table.insert(sessionBanLog, 1, {
			userId     = userId,
			playerName = player.Name,
			reason     = reason,
			details    = details,
			timestamp  = now,
		})

		task.spawn(function()
			pcall(function()
				banStore:SetAsync(tostring(userId), {
					reason     = reason,
					details    = details,
					timestamp  = now,
					playerName = player.Name,
				})
			end)

			pcall(function()
				banLogStore:UpdateAsync(BAN_LOG_KEY, function(existing)
					local log = (type(existing) == "table") and existing or {}
					table.insert(log, 1, {
						userId     = userId,
						playerName = player.Name,
						reason     = reason,
						details    = details,
						timestamp  = now,
					})
					while #log > 100 do table.remove(log, #log) end
					return log
				end)
			end)
		end)

		if player.Parent then
			player:Kick(string.format(
				"🚫 PERMANENT BAN\nExploitation détectée.\nRaison: %s\n%s\nUserID: %d",
				reason, details, userId
				))
		end
	end

	-- ────────────────────────────────────────────
	-- ✅ FIX RACE CONDITION : checkPlayer attend le vrai multiplicateur
	-- ────────────────────────────────────────────
	local function checkPlayer(player)
		if not player or not player.Parent then return end
		local userId = player.UserId

		if not initialized[userId]           then return end
		if not multiplierCache[userId]       then return end
		if dataLoading[userId]               then return end
		if AntiExploit.bannedPlayers[userId] then return end

		-- FIX V5.3: Skip pendant 30s après un reload AFK (stabilisation)
		if _G.recentReloads and _G.recentReloads[userId] then
			local reloadAge = os.time() - _G.recentReloads[userId]
			if reloadAge < 30 then
				return
			end
		end

		local data = capData[userId]
		if not data then
			warn(string.format("⚠️ checkPlayer: capData absent pour %s, skip", player.Name))
			return
		end

		-- FIX V5.3: Détecter un firstJoin suspect (reset à os.time() par erreur)
		local playtime = os.time() - data.firstJoin
		if playtime < 60 then
			local leaderstats = player:FindFirstChild("leaderstats")
			local pointsStat  = leaderstats and leaderstats:FindFirstChild("Points")
			local currentPoints = pointsStat and pointsStat.Value or 0

			-- Un vrai nouveau joueur a au max ~303800 pts au jour 1
			-- Si firstJoin=now MAIS pts > 400000 → corruption, recharger
			if currentPoints > 150000 then
				warn(string.format(
					"🛑 checkPlayer: capData suspect pour %s (firstJoin=now mais %d pts). Rechargement.",
					player.Name, currentPoints
					))

				task.spawn(function()
					task.wait(2)
					if player.Parent then
						initialized[userId] = nil
						loadCapData(player)
					end
				end)

				return
			end
		end

		local multiplier = computeMultiplier(player)

		if multiplierCache[userId] ~= multiplier then
			warn(string.format("⚠️ Cache incohérent pour %s, skip ce cycle", player.Name))
			return
		end

		local leaderstats = player:FindFirstChild("leaderstats")
		local pointsStat  = leaderstats and leaderstats:FindFirstChild("Points")
		if not pointsStat then return end

		local currentPoints = pointsStat.Value
		if type(currentPoints) ~= "number" or currentPoints < 0 then return end

		local maxAllowed = getMaxPoints(userId)

		-- FIX V5.3: Si getMaxPoints retourne nil, NE PAS bannir
		if maxAllowed == nil then
			warn(string.format("⚠️ checkPlayer: maxAllowed indisponible pour %s, skip", player.Name))
			return
		end

		local playtimeDays = (os.time() - data.firstJoin) / 86400
		local spent        = CapBridge.getTotalSpent(userId)
		local gains        = CapBridge.getTotalGains(userId)

		if currentPoints > maxAllowed * 0.8 then
			print(string.format("⚠️ %s proche du cap: %d / %d (%.0f%%) | mult=x%d",
				player.Name, currentPoints, maxAllowed,
				currentPoints / maxAllowed * 100, multiplier))
		end

		if currentPoints > maxAllowed then
			-- FIX V5.3: Tolérance de 2% pour absorber les micro-race conditions
			local tolerance = maxAllowed * 0.02
			if currentPoints <= maxAllowed + tolerance then
				warn(string.format(
					"⚠️ Dépassement léger toléré pour %s : %d > %d (marge 2%%)",
					player.Name, currentPoints, maxAllowed
					))
				return
			end

			-- FIX V5.3: Second check avec multiplier forcé fresh
			-- Un gamepass fraîchement acheté peut ne pas être dans le cache
			multiplierCache[userId] = nil
			local freshMult = computeMultiplier(player)
			local freshMax  = getMaxPoints(userId)

			if freshMax and currentPoints <= freshMax then
				print(string.format(
					"✅ Ban évité grâce au recalcul multiplier pour %s (mult: x%d → x%d, cap: %d → %d)",
					player.Name, multiplier, freshMult, maxAllowed, freshMax
					))
				return
			end

			absoluteBan(player, "CAP_EXCEEDED",
				string.format(
					"%d pts > cap %d | playtime=%.2fj | mult=x%d | bonus=%d | spent=%d | gains=%d",
					currentPoints, (freshMax or maxAllowed), playtimeDays, freshMult,
					data.devProductBonus, spent, gains
				)
			)
		end
	end

	-- ────────────────────────────────────────────
	-- HOOKS (inchangés sauf ajout spent dans logs)
	-- ────────────────────────────────────────────
	_G.AbsoluteCapOnDevProduct = function(userId, productId)
		local capBonus = CAP_CONFIG.DEV_PRODUCT_CAP_BONUS[productId]
		if not capBonus then return end
		if type(userId) ~= "number" or userId <= 0 then return end

		if not capData[userId] then
			capData[userId] = { firstJoin = os.time(), devProductBonus = 0 }
		end

		capData[userId].devProductBonus = capData[userId].devProductBonus + capBonus

		-- ✅ FIX #2 : retry sur la persistance (sinon un hoquet DataStore = bonus perdu
		-- au prochain vrai relog → joueur payant banni pour CAP_EXCEEDED)
		task.spawn(function()
			for attempt = 1, 5 do
				local ok = pcall(function()
					capStore:UpdateAsync("cap_" .. userId, function(existing)
						if not existing or type(existing) ~= "table" then
							return capData[userId]
						end
						existing.devProductBonus = capData[userId].devProductBonus
						return existing
					end)
				end)
				if ok then
					print(string.format("💳 DevProduct cap-bonus persisté: UserID %d | +%d | total: %d",
						userId, capBonus, capData[userId].devProductBonus))
					return
				end
				warn(string.format("⚠️ devProductBonus save tentative %d/5 échouée pour %d", attempt, userId))
				task.wait(2 * attempt)
			end
			warn(string.format("🚨 CRITIQUE: devProductBonus PAS persisté pour %d après 5 essais", userId))
		end)
	end

	_G.AbsoluteCapAdminBonus = function(userId, bonusPoints)
		if type(userId) ~= "number" or userId <= 0 then return end
		if type(bonusPoints) ~= "number" or bonusPoints <= 0 then return end

		if not capData[userId] then
			capData[userId] = { firstJoin = os.time(), devProductBonus = 0 }
		end

		capData[userId].devProductBonus = capData[userId].devProductBonus + bonusPoints

		pcall(function()
			capStore:UpdateAsync("cap_" .. userId, function(existing)
				if not existing or type(existing) ~= "table" then return capData[userId] end
				existing.devProductBonus = capData[userId].devProductBonus
				return existing
			end)
		end)

		print(string.format("🎁 AdminBonus: UserID %d | +%d | nouveau bonus: %d",
			userId, bonusPoints, capData[userId].devProductBonus))
	end

	_G.enrichQuestSnapshotWithP2 = function(userId, snapshot)
		local data = capData[userId]
		if data then
			snapshot.capFirstJoin       = data.firstJoin
			snapshot.capDevProductBonus = data.devProductBonus
			snapshot.capTotalSpent      = CapBridge.getTotalSpent(userId)
			snapshot.capTotalGains      = CapBridge.getTotalGains(userId)  -- ✅ FIX: était absent, causait gains=0 après reload
		end
		return snapshot
	end

	_G.tryRestoreP2FromSnapshot = function(player, snapshot)
		if not snapshot then return end
		local userId = player.UserId
		local now    = os.time()
		local fj     = snapshot.capFirstJoin
		local bonus  = snapshot.capDevProductBonus

		if type(fj) == "number" and fj > 0 and fj <= now then
			capData[userId] = {
				firstJoin       = fj,
				devProductBonus = type(bonus) == "number" and math.max(0, bonus) or 0,
			}

			-- FIX V5.3: Initialiser aussi le CapFirstJoinBridge
			CapFirstJoinBridge.set(userId, fj)

			if type(snapshot.capTotalSpent) == "number" then
				CapBridge.setTotalSpent(userId, snapshot.capTotalSpent)
			end
			if type(snapshot.capTotalGains) == "number" then
				CapBridge.setTotalGains(userId, snapshot.capTotalGains)
			end

			-- FIX V5.3: Pré-remplir le cache multiplier avec x1 par défaut
			-- pour que checkPlayer puisse tourner tout de suite.
			-- computeMultiplier mettra à jour la vraie valeur (async réseau).
			if not multiplierCache[userId] then
				multiplierCache[userId] = 1
			end

			-- FIX V5.3: Poser initialized=true pour éviter la fenêtre aveugle
			-- où checkPlayer skip. loadCapData écrasera ces valeurs si besoin.
			initialized[userId] = true

			task.spawn(function()
				if player.Parent then computeMultiplier(player) end
			end)

			print(string.format("✅ CapProtection restauré depuis snapshot: %.2fj | bonus=%d | spent=%d | gains=%d",
				(now - fj) / 86400,
				capData[userId].devProductBonus,
				CapBridge.getTotalSpent(userId),
				CapBridge.getTotalGains(userId)))
		end
	end
	
	_G.setP2Baseline = function(player, totalPoints) end

	-- ────────────────────────────────────────────
	-- EVENTS JOUEUR
	-- ────────────────────────────────────────────
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local waited = 0
			while dataLoading[player.UserId] and waited < 150 do
				task.wait(0.1)
				waited = waited + 1
			end

			if initialized[player.UserId] then return end
			if player.Parent then loadCapData(player) end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		if capData[userId] then
			saveCapDataSync(userId)
		end

		-- FIX V5.3: Capturer la firstJoin au moment du départ
		-- pour détecter une reconnexion vs nouvelle session
		local leavingFirstJoin = capData[userId] and capData[userId].firstJoin or nil

		initialized[userId]     = nil
		CapFirstJoinBridge.cleanup(userId)
		multiplierCache[userId] = nil

		task.delay(30, function()
			-- FIX V5.3 CRITIQUE: Ne PAS cleaner si le joueur est revenu (reload AFK)
			-- Sinon on vide les données de la session active → FAUX BAN

			local currentPlayer = Players:GetPlayerByUserId(userId)
			if currentPlayer and currentPlayer.Parent then
				print(string.format("🛡️ Cleanup cap ANNULÉ pour UserID %d (reconnexion détectée)", userId))
				return
			end

			-- Si capData[userId] existe toujours mais avec une firstJoin différente,
			-- c'est qu'une nouvelle session l'a rempli entre temps
			local currentData = capData[userId]
			if currentData and leavingFirstJoin and currentData.firstJoin ~= leavingFirstJoin then
				print(string.format("🛡️ Cleanup cap ANNULÉ pour UserID %d (nouvelle session détectée)", userId))
				return
			end

			-- Vraie déconnexion → cleanup OK
			capData[userId] = nil
			CapBridge.cleanup(userId)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function() loadCapData(player) end)
	end

	-- ────────────────────────────────────────────
	-- BOUCLE DE VÉRIFICATION
	-- ────────────────────────────────────────────
	task.spawn(function()
		print("🛡️ AbsoluteCap V5.2: boucle démarrée")
		while true do
			task.wait(CAP_CONFIG.CHECK_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				if player and player.Parent then
					task.spawn(function()
						local ok, err = pcall(checkPlayer, player)
						if not ok then
							warn("❌ AbsoluteCap check erreur:", tostring(err))
						end
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId
			if capData[userId] then saveCapDataSync(userId) end
		end
		task.wait(2)
	end)

	-- ────────────────────────────────────────────
	-- COMMANDES DEBUG (mises à jour)
	-- ────────────────────────────────────────────
	_G.DebugCap = function(userId)
		local player = Players:GetPlayerByUserId(userId)
		local data   = capData[userId]
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print("🛡️ CAP DEBUG:", player and player.Name or ("UserID " .. userId))

		if data then
			local now          = os.time()
			local playtime     = now - data.firstJoin
			local playtimeDays = playtime / 86400
			local multiplier   = getPlayerMultiplier(userId)
			local maxPts       = getMaxPoints(userId)
			local spent        = CapBridge.getTotalSpent(userId)

			local palier
			if playtimeDays >= 15 then
				palier = string.format("%.1fj (croissance linéaire)", playtimeDays)
			else
				palier = "< 15j (paliers)"
				for _, layer in ipairs(CAP_CONFIG.TIME_LAYERS) do
					if playtimeDays <= layer.days then
						palier = "< " .. layer.days .. "j"
						break
					end
				end
			end

			print(string.format("   firstJoin:    il y a %.2fj", playtimeDays))
			print(string.format("   Palier:       %s", palier))
			print(string.format("   Multiplicateur: x%d", multiplier))
			print(string.format("   Bonus DevProduct: +%d pts", data.devProductBonus))
			local gains = CapBridge.getTotalGains(userId)
			print(string.format("   Points dépensés (UGC):  -%d pts", spent))
			print(string.format("   Points gagnés (boxes):  +%d pts", gains))
			print(string.format("   CAP TOTAL:    %d pts", maxPts))
			print(string.format("     = baseCap + bonus(%d) - spent(%d) + gains(%d)",
				data.devProductBonus, spent, gains))

			if player then
				local ls  = player:FindFirstChild("leaderstats")
				local ps  = ls and ls:FindFirstChild("Points")
				local pts = ps and ps.Value or 0
				print(string.format("   Pts actuels:  %d (%.1f%% du cap)",
					pts, maxPts > 0 and (pts / maxPts * 100) or 0))
			end
		else
			print("   (pas de données en mémoire)")
		end

		print(string.format("   Initialisé: %s", tostring(initialized[userId] == true)))
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	end
	
	-- Reset le totalSpent d'un joueur (ex: erreur de comptage UGC)
	_G.ResetSpent = function(userId)
		if type(userId) ~= "number" or userId <= 0 then
			warn("❌ ResetSpent: userId invalide")
			return
		end

		local player = Players:GetPlayerByUserId(userId)
		local oldSpent = CapBridge.getTotalSpent(userId)

		-- Reset en mémoire
		CapBridge.setTotalSpent(userId, 0)

		-- Persist dans le DataStore
		pcall(function()
			capStore:UpdateAsync("cap_" .. userId, function(existing)
				if not existing or type(existing) ~= "table" then return end
				existing.totalSpent = 0
				return existing
			end)
		end)

		print(string.format("🔄 ResetSpent: UserID %d | ancien spent: %d → 0 | cap recalculé: %d",
			userId, oldSpent, getMaxPoints(userId)))

		if player then
			print(string.format("   Joueur en ligne: %s", player.Name))
		else
			print("   (joueur hors ligne — DataStore mis à jour quand même)")
		end
	end

	-- Reset le bonus DevProduct d'un joueur (ex: achat remboursé)
	_G.ResetDevProductBonus = function(userId)
		if type(userId) ~= "number" or userId <= 0 then
			warn("❌ ResetDevProductBonus: userId invalide")
			return
		end

		local player = Players:GetPlayerByUserId(userId)
		local data = capData[userId]
		local oldBonus = data and data.devProductBonus or 0

		-- Reset en mémoire (si le joueur est en ligne)
		if data then
			data.devProductBonus = 0
		end

		-- Persist dans le DataStore
		pcall(function()
			capStore:UpdateAsync("cap_" .. userId, function(existing)
				if not existing or type(existing) ~= "table" then return end
				existing.devProductBonus = 0
				return existing
			end)
		end)

		print(string.format("🔄 ResetDevProductBonus: UserID %d | ancien bonus: %d → 0 | cap recalculé: %d",
			userId, oldBonus, getMaxPoints(userId)))

		if player then
			print(string.format("   Joueur en ligne: %s", player.Name))
		else
			print("   (joueur hors ligne — DataStore mis à jour quand même)")
		end
	end
	
	_G.ShowCapTable = function()
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print("📊 TABLEAU DES CAPS V5.2 (buffer x2 | sans bonus DevProduct ni spent)")
		print("   Croissance linéaire après 15j — valeurs affichées jusqu'à 60j")
		print(string.format("   %-12s | %-10s | %-10s | %-10s | %-10s | %-10s | %-10s",
			"Durée", "x1 (base)", "x3", "x8", "x12", "x19", "x20 (max)"))
		print("   " .. string.rep("-", 82))
		
		

		local durations = {1, 2, 3, 5, 7, 10, 15, 20, 30, 60}
		local mults     = {1, 3, 8, 12, 19, 20}

		local function fmtPts(n)
			if n >= 1000000 then
				return string.format("%.1fM", n / 1000000)
			elseif n >= 1000 then
				return string.format("%.0fK", n / 1000)
			else
				return tostring(n)
			end
		end

		for _, days in ipairs(durations) do
			local cappedDays
			local playtimeSecs = days * 86400
			if days >= 15 then
				cappedDays = days
			else
				cappedDays = 15
				for _, layer in ipairs(CAP_CONFIG.TIME_LAYERS) do
					if days <= layer.days then
						cappedDays = layer.days
						break
					end
				end
			end

			local label = days >= 15
				and string.format("%dj (lin.)", days)
				or  string.format("%dj (pal.)", days)

			local row = string.format("   %-14s |", label)
			for _, mult in ipairs(mults) do
				local cap = math.floor(CAP_CONFIG.BASE_PTS_PER_SEC * 86400 * cappedDays * mult * CAP_CONFIG.BUFFER)
				row = row .. string.format(" %-10s |", fmtPts(cap))
			end
			print(row)
		end
		
		print("   📐 COMPARAISON : cap système vs max légitime réel (sans gamepass, sans DevProduct)")
		print(string.format("   %-14s | %-14s | %-14s | %-6s",
			"Durée", "Cap système", "Max légitime", "Marge"))
		print("   " .. string.rep("-", 58))

		for _, days in ipairs({1, 2, 3, 5, 7, 10, 15, 30}) do
			local cappedDays2
			if days >= 15 then
				cappedDays2 = days
			else
				cappedDays2 = 15
				for _, layer in ipairs(CAP_CONFIG.TIME_LAYERS) do
					if days <= layer.days then
						cappedDays2 = layer.days
						break
					end
				end
			end

			local capSys  = math.floor(CAP_CONFIG.BASE_PTS_PER_SEC * 86400 * cappedDays2 * 1 * CAP_CONFIG.BUFFER)
				+ CAP_CONFIG.GAME_UNIQUE_QUEST_CAP
				+ math.floor(CAP_CONFIG.GAME_DAILY_QUEST_CAP * cappedDays2)
			local legitim = CAP_CONFIG.GAME_UNIQUE_QUEST_CAP + CAP_CONFIG.GAME_DAILY_QUEST_CAP * days
			local marge   = capSys - legitim

			print(string.format("   %-14s | %-14s | %-14s | +%s",
				days .. "j",
				fmtPts(capSys),
				fmtPts(legitim),
				fmtPts(marge)))
		end

		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print("   GamePasses (additifs depuis x1) : +2 | +2 | +5 | +10")
		print("   Combos : x1+2=x3 | x1+2+5=x8 | x1+5+10=x16 | x1+2+2+5+10=x20")
		print("   ⚠️  spent (UGC) et bonus DevProduct s'ajoutent PAR-DESSUS ces caps")
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	end

	_G.DebugCapAll = function()
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId
			local data   = capData[userId]
			if data then
				local playtimeDays = (os.time() - data.firstJoin) / 86400
				local multiplier   = getPlayerMultiplier(userId)
				local maxPts       = getMaxPoints(userId)
				local spent        = CapBridge.getTotalSpent(userId)
				local ls           = player:FindFirstChild("leaderstats")
				local ps           = ls and ls:FindFirstChild("Points")
				local pts          = ps and ps.Value or 0
				print(string.format("   %-20s | %.1fj | x%-2d | cap: %d (spent:+%d) | pts: %d (%.0f%%)",
					player.Name, playtimeDays, multiplier, maxPts, spent, pts,
					maxPts > 0 and (pts / maxPts * 100) or 0))
			end
		end
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("✅ ABSOLUTE CAP V5.2 CHARGÉ")
	print("   Cap illimité dans le temps (croissance linéaire après 15j)")
	print("   Cap conscient des dépenses UGC (via CapBridge)")
	print("   Fix race condition multiplicateur")
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	
	task.delay(2, function()
		if _G.ShowCapTable then _G.ShowCapTable() end
	end)
end)