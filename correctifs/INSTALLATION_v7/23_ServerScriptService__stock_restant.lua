-- ============================================
-- SCRIPT SERVEUR STOCK UGC - VERSION MULTI-SERVEUR
-- À placer dans ServerScriptService
-- ============================================

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")

-- ========================================
-- IMPORTER LA CONFIGURATION UGC (AVEC RETRY)
-- ========================================
print("⏳ [SERVEUR] Chargement de UGC_CONFIG...")
local UGC_CONFIG
local maxRetries = 10
for i = 1, maxRetries do
	local success, result = pcall(function()
		return require(ReplicatedStorage:WaitForChild("UGC_CONFIG", 5))
	end)

	if success and result and result.Items then
		UGC_CONFIG = result
		print("✅ [SERVEUR] UGC_CONFIG chargé avec succès (" .. #UGC_CONFIG.Items .. " items)")
		break
	else
		warn("⚠️ [SERVEUR] Tentative " .. i .. "/" .. maxRetries .. " - UGC_CONFIG non disponible")
		task.wait(1)
	end
end

if not UGC_CONFIG or not UGC_CONFIG.Items then
	error("❌ [SERVEUR] ERREUR CRITIQUE: UGC_CONFIG introuvable après " .. maxRetries .. " tentatives!")
end

-- DataStore
local UGCStockStore = DataStoreService:GetDataStore("UGCStockData_v3")
local DATA_KEY = "GlobalUGCStock"

-- 🆕 Topic MessagingService pour sync cross-serveurs
local SYNC_TOPIC = "UGCStockSync_v2"

local CurrentStocks = {}
local DataLoaded = false

-- ========================================
-- REMOTE EVENTS
-- ========================================
local UpdateStockEvent = Instance.new("RemoteEvent")
UpdateStockEvent.Name = "UpdateStockEvent"
UpdateStockEvent.Parent = ReplicatedStorage

local GetStockFunction = Instance.new("RemoteFunction")
GetStockFunction.Name = "GetStockFunction"
GetStockFunction.Parent = ReplicatedStorage

local ResetStockFunction = Instance.new("RemoteFunction")
ResetStockFunction.Name = "ResetStockFunction"
ResetStockFunction.Parent = ReplicatedStorage

local UpdateButtonStateEvent = Instance.new("RemoteEvent")
UpdateButtonStateEvent.Name = "UpdateButtonStateEvent"
UpdateButtonStateEvent.Parent = ReplicatedStorage

-- 🆕 RemoteFunction pour SetStock depuis un GUI admin
local SetStockFunction = Instance.new("RemoteFunction")
SetStockFunction.Name = "SetStockFunction"
SetStockFunction.Parent = ReplicatedStorage

-- ========================================
-- ADMINS
-- ========================================
local ADMIN_USER_IDS = {
	11017023724,
}

local function IsAdmin(player)
	for _, adminId in ipairs(ADMIN_USER_IDS) do
		if player.UserId == adminId then
			return true
		end
	end
	return false
end

-- ========================================
-- FONCTION: Mettre à jour l'état des boutons
-- ========================================
local function UpdateAllButtonStates()
	if not DataLoaded then
		warn("⚠️ [SERVEUR] Tentative de mise à jour UI avant chargement des données - IGNORÉ")
		return
	end

	local success, err = pcall(function()
		local buttonStates = {}
		for _, ugc in ipairs(UGC_CONFIG.Items) do
			local assetKey = tostring(ugc.AssetId)
			local currentStock = CurrentStocks[assetKey] or 0
			buttonStates[ugc.ButtonName] = {
				IsActive = currentStock > 0,
				Stock = currentStock
			}
		end
		UpdateButtonStateEvent:FireAllClients(buttonStates)
		print("📡 [SERVEUR] États des boutons envoyés à tous les clients")
	end)

	if not success then
		warn("❌ [SERVEUR] ERREUR UpdateAllButtonStates: " .. tostring(err))
	end
end

-- ========================================
-- 🆕 FONCTION: Broadcaster une mise à jour à tous les serveurs
-- ========================================
local function BroadcastStockUpdate(updatedStocks)
	local success, err = pcall(function()
		-- On envoie uniquement les clés/valeurs modifiées (ou tout le stock)
		local payload = {}
		for key, value in pairs(updatedStocks) do
			payload[key] = value
		end
		MessagingService:PublishAsync(SYNC_TOPIC, payload)
		print("📢 [SERVEUR] Broadcast stock envoyé à tous les serveurs")
	end)

	if not success then
		warn("⚠️ [SERVEUR] MessagingService broadcast échoué: " .. tostring(err))
		-- Pas critique : le DataStore fait foi au prochain chargement
	end
end

-- ========================================
-- FONCTION: Charger les données (AVEC RETRY ET VALIDATION)
-- ========================================
local function LoadStockData()
	print("📥 [SERVEUR] Chargement des stocks depuis DataStore...")
	local loadedData = {}
	local dataStoreSuccess = false

	for attempt = 1, 3 do
		local success, data = pcall(function()
			return UGCStockStore:GetAsync(DATA_KEY)
		end)

		if success then
			if data and type(data) == "table" then
				local hasValidData = false
				for key, value in pairs(data) do
					if type(value) == "number" and value >= 0 then
						loadedData[key] = value
						hasValidData = true
						print("  ✅ Chargé: " .. key .. " = " .. value)
					end
				end
				if hasValidData then
					print("✅ [SERVEUR] DONNÉES DATASTORE VALIDES (tentative " .. attempt .. ")")
					dataStoreSuccess = true
					break
				else
					warn("⚠️ [SERVEUR] DataStore vide, tentative " .. attempt .. "/3")
				end
			else
				warn("⚠️ [SERVEUR] DataStore nil/invalide, tentative " .. attempt .. "/3")
			end
		else
			warn("❌ [SERVEUR] Erreur GetAsync tentative " .. attempt .. "/3: " .. tostring(data))
		end

		if attempt < 3 then task.wait(2) end
	end

	if not dataStoreSuccess then
		warn("⚠️ [SERVEUR] AUCUNE DONNÉE DATASTORE - INITIALISATION COMPLÈTE")
	end

	local needsSave = false
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		local assetKey = tostring(ugc.AssetId)
		if loadedData[assetKey] == nil then
			loadedData[assetKey] = ugc.InitialStock
			needsSave = true
			print("  🆕 NOUVEAU UGC: " .. ugc.Name .. " = " .. ugc.InitialStock)
		else
			print("  ✅ Stock conservé: " .. ugc.Name .. " = " .. loadedData[assetKey])
		end
	end

	if needsSave then
		for saveAttempt = 1, 3 do
			local saveSuccess, saveErr = pcall(function()
				-- 🔒 N'ajoute QUE les nouveaux UGC. Avant : si la lecture avait raté
				--    3 fois, TOUS les stocks étaient remis à InitialStock (restock géant).
				local merged
				UGCStockStore:UpdateAsync(DATA_KEY, function(ds)
					ds = (type(ds) == "table") and ds or {}
					for k, v in pairs(loadedData) do
						if type(ds[k]) ~= "number" then ds[k] = v end
					end
					merged = ds
					return ds
				end)
				if merged then
					for k, v in pairs(merged) do
						if type(v) == "number" then loadedData[k] = v end
					end
				end
			end)
			if saveSuccess then
				print("✅ [SERVEUR] Sauvegarde initiale réussie (tentative " .. saveAttempt .. ")")
				break
			else
				warn("❌ [SERVEUR] Erreur sauvegarde tentative " .. saveAttempt .. "/3: " .. tostring(saveErr))
				if saveAttempt < 3 then task.wait(2) end
			end
		end
	end

	print("✅ [SERVEUR] STOCKS FINAUX CHARGÉS:")
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		local assetKey = tostring(ugc.AssetId)
		print("  - " .. ugc.Name .. ": " .. loadedData[assetKey])
	end

	return loadedData
end

-- ========================================
-- FONCTION: Sauvegarder dans le DataStore
-- ========================================
local PendingDec = {}   -- ventes faites pendant une panne DataStore, pas encore en base
local function SaveStockData(skipBroadcast, force)
	if not DataLoaded then
		warn("⚠️ [SERVEUR] Tentative de sauvegarde avant chargement complet - IGNORÉ")
		return
	end

	local success, err = pcall(function()
		local zeroCount = 0
		local isValid = true

		for _, ugc in ipairs(UGC_CONFIG.Items) do
			local assetKey = tostring(ugc.AssetId)
			local stock = CurrentStocks[assetKey]
			if not stock or type(stock) ~= "number" or stock < 0 then
				warn("❌ [SERVEUR] Données invalides pour " .. ugc.Name .. ": " .. tostring(stock))
				isValid = false
				break
			end
			if stock == 0 then zeroCount = zeroCount + 1 end
		end

		if zeroCount == #UGC_CONFIG.Items then
			warn("🚨 [SERVEUR] SAUVEGARDE BLOQUÉE: TOUS LES STOCKS SONT À 0!")
			return
		end

		if not isValid then
			warn("❌ [SERVEUR] Sauvegarde annulée: données corrompues!")
			return
		end

		-- 🔒 Plus de SetAsync de la table entière : un serveur au stock périmé
		--    écrasait les ventes des autres → stock qui REMONTE → oversell.
		--    La base gagne ; on n'ajoute que les UGC manquants et les ventes
		--    faites pendant une panne. force = écraser (reset / alignement admin).
		local pend = table.clone(PendingDec)
		local dataToSave
		UGCStockStore:UpdateAsync(DATA_KEY, function(ds)
			ds = (type(ds) == "table") and ds or {}
			for key, value in pairs(CurrentStocks) do
				if force or type(ds[key]) ~= "number" then
					ds[key] = value
				elseif pend[key] then
					ds[key] = math.max(0, ds[key] - pend[key])
				end
			end
			dataToSave = ds
			return ds
		end)
		for key, n in pairs(pend) do
			PendingDec[key] = math.max(0, (PendingDec[key] or 0) - n)
			if PendingDec[key] == 0 then PendingDec[key] = nil end
		end
		for key, value in pairs(dataToSave) do
			if type(value) == "number" then CurrentStocks[key] = value end
		end

		print("💾 [SERVEUR] STOCKS SAUVEGARDÉS:")
		for _, ugc in ipairs(UGC_CONFIG.Items) do
			local assetKey = tostring(ugc.AssetId)
			print("  - " .. ugc.Name .. ": " .. CurrentStocks[assetKey])
		end

		-- 🆕 Broadcast aux autres serveurs après sauvegarde (sauf si demandé de skip)
		if not skipBroadcast then
			BroadcastStockUpdate(dataToSave)
		end
	end)

	if not success then
		warn("❌ [SERVEUR] ERREUR SAUVEGARDE STOCK: " .. tostring(err))
	end
end

-- ========================================
-- FONCTION: Décrémenter le stock
-- ========================================
local function DecrementStock(assetId)
	local success, result = pcall(function()
		local assetKey = tostring(assetId)

		if not (CurrentStocks[assetKey] and CurrentStocks[assetKey] > 0) then
			return false
		end

		-- 🔒 DÉCRÉMENT ATOMIQUE multi-serveur via UpdateAsync.
		-- Avant : SetAsync de la table entière → 2 serveurs qui vendent en même
		-- temps = last-writer-wins = décréments perdus = OVERSELL d'items limités.
		local newValue = nil
		local ok = pcall(function()
			UGCStockStore:UpdateAsync(DATA_KEY, function(dsData)
				dsData = (type(dsData) == "table") and dsData or {}
				local cur = dsData[assetKey]
				if type(cur) ~= "number" then cur = CurrentStocks[assetKey] or 0 end
				dsData[assetKey] = math.max(0, cur - 1)
				newValue = dsData[assetKey]
				return dsData
			end)
		end)

		if ok and newValue ~= nil then
			CurrentStocks[assetKey] = newValue  -- resync avec la vérité globale
		else
			-- DataStore down : décrément local seulement (rattrapé au prochain sync)
			CurrentStocks[assetKey] = math.max(0, CurrentStocks[assetKey] - 1)
			PendingDec[assetKey] = (PendingDec[assetKey] or 0) + 1
			warn("⚠️ [SERVEUR] DecrementStock : UpdateAsync échoué, rattrapé à la prochaine sauvegarde")
		end

		local ugcData = UGC_CONFIG.GetByAssetId(assetId)
		if ugcData then
			print("📦 [SERVEUR] STOCK -1: " .. ugcData.Name .. " (reste: " .. CurrentStocks[assetKey] .. ")")
		end

		BroadcastStockUpdate({ [assetKey] = CurrentStocks[assetKey] })
		UpdateStockEvent:FireAllClients(CurrentStocks)
		UpdateAllButtonStates()
		return true
	end)

	if not success then
		warn("❌ [SERVEUR] ERREUR DecrementStock (AssetId: " .. tostring(assetId) .. "): " .. tostring(result))
		return false
	end
	return result
end

-- ========================================
-- 🆕 FONCTION CENTRALE: Définir un stock précis
-- Utilisée par /setstock ET SetStockFunction (GUI admin)
-- ========================================
local function SetStock(assetId, newAmount)
	-- Validation
	if type(newAmount) ~= "number" or newAmount < 0 or math.floor(newAmount) ~= newAmount then
		return false, "Quantité invalide (doit être un entier >= 0)"
	end

	local assetKey = tostring(assetId)
	local ugcData = UGC_CONFIG.GetByAssetId(assetId)

	if not ugcData then
		return false, "UGC introuvable pour AssetId: " .. tostring(assetId)
	end

	local oldStock = CurrentStocks[assetKey] or 0
	CurrentStocks[assetKey] = newAmount

	-- Sauvegarder dans le DataStore
	local saveOk = true
	local saveSuccess, saveErr = pcall(function()
		UGCStockStore:UpdateAsync(DATA_KEY, function(ds)
			ds = (type(ds) == "table") and ds or {}
			ds[assetKey] = newAmount            -- 🔒 on ne touche QUE cet UGC
			return ds
		end)
	end)
	if not saveSuccess then
		warn("❌ [SERVEUR] Erreur SetAsync dans SetStock: " .. tostring(saveErr))
		saveOk = false
	end

	-- Mettre à jour tous les clients de CE serveur
	UpdateStockEvent:FireAllClients(CurrentStocks)
	UpdateAllButtonStates()

	-- 🆕 Broadcaster aux AUTRES serveurs (seulement l'UGC modifié)
	BroadcastStockUpdate({ [assetKey] = newAmount })

	print(string.format(
		"✏️ [SERVEUR] SETSTOCK: %s | %d → %d | Sauvegarde: %s",
		ugcData.Name, oldStock, newAmount, saveOk and "OK" or "ÉCHEC"
		))

	return true, string.format("Stock de '%s' défini à %d (anciennement %d)", ugcData.Name, newAmount, oldStock)
end

-- ========================================
-- FONCTION: Gérer les achats UGC
-- ========================================
-- ⚠️ ANCIENNE LOGIQUE SUPPRIMÉE
-- Le stock n'est plus décrémenté automatiquement sur PromptPurchaseFinished.
-- Il est décrémenté UNIQUEMENT par le script principal quand il confirme
-- que l'achat est vraiment passé (succès Roblox OU détection bug OU timeout livré).
-- Voir _G.UGCStock_OnConfirmedPurchase ci-dessous.
local function OnPromptPurchaseFinished(player, assetId, isPurchased)
	-- Volontairement vide : la décrémentation se fait via _G.UGCStock_OnConfirmedPurchase
end

-- ============================================================
-- ✅ API EXPOSÉE : appelée par le script principal quand un achat
--    UGC est CONFIRMÉ (livraison réelle au joueur)
-- ============================================================
_G.UGCStock_OnConfirmedPurchase = function(assetId, playerName)
	if type(assetId) ~= "number" then return false end
	if not DataLoaded then
		warn("⚠️ [STOCK] Décrément refusé : données pas encore chargées")
		return false
	end

	local ugcData = UGC_CONFIG.GetByAssetId(assetId)
	if not ugcData then
		warn("⚠️ [STOCK] AssetId inconnu pour décrément: " .. tostring(assetId))
		return false
	end

	local ok = DecrementStock(assetId)
	if ok then
		print(string.format("✅ [STOCK] Décrément confirmé pour %s (joueur: %s)",
			ugcData.Name, playerName or "?"))
	else
		warn(string.format("⚠️ [STOCK] Stock déjà à 0 pour %s — pas de décrément",
			ugcData.Name))
	end
	return ok
end

-- ========================================
-- REMOTE FUNCTIONS
-- ========================================
GetStockFunction.OnServerInvoke = function(player, requestedAssetId)
	local maxWait = 10
	local waited = 0
	while not DataLoaded and waited < maxWait do
		task.wait(0.5)
		waited = waited + 0.5
	end

	if not DataLoaded then
		warn("⚠️ [SERVEUR] GetStockFunction appelé avant chargement complet!")
		return nil
	end

	local success, result = pcall(function()
		local ugcData = UGC_CONFIG.GetByAssetId(requestedAssetId)
		if ugcData then
			return {
				Config = ugcData,
				CurrentStock = CurrentStocks[tostring(requestedAssetId)] or 0
			}
		end
		warn("❌ [SERVEUR] UGC " .. tostring(requestedAssetId) .. " introuvable!")
		return nil
	end)

	if not success then
		warn("❌ [SERVEUR] ERREUR GetStockFunction: " .. tostring(result))
		return nil
	end
	return result
end

ResetStockFunction.OnServerInvoke = function(player, searchTerm)
	local success, result = pcall(function()
		if not IsAdmin(player) then
			warn("⛔ " .. player.Name .. " a tenté de reset le stock sans permission!")
			return {success = false, message = "Vous n'avez pas la permission!"}
		end

		local ugcData = nil
		for _, ugc in ipairs(UGC_CONFIG.Items) do
			if ugc.Name:lower():find(searchTerm:lower(), 1, true) or ugc.AssetId == tonumber(searchTerm) then
				ugcData = ugc
				break
			end
		end

		if not ugcData then
			return {success = false, message = "UGC introuvable!"}
		end

		local ok, msg = SetStock(ugcData.AssetId, ugcData.InitialStock)
		return {success = ok, message = msg}
	end)

	if not success then
		warn("❌ [SERVEUR] ERREUR ResetStockFunction: " .. tostring(result))
		return {success = false, message = "Erreur serveur!"}
	end
	return result
end

-- 🆕 RemoteFunction SetStock (pour GUI admin)
SetStockFunction.OnServerInvoke = function(player, searchTerm, newAmount)
	if not IsAdmin(player) then
		warn("⛔ " .. player.Name .. " a tenté de SetStock sans permission!")
		return {success = false, message = "Permission refusée!"}
	end

	local ugcData = nil
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		if ugc.Name:lower():find(tostring(searchTerm):lower(), 1, true) or ugc.AssetId == tonumber(searchTerm) then
			ugcData = ugc
			break
		end
	end

	if not ugcData then
		return {success = false, message = "UGC introuvable pour: " .. tostring(searchTerm)}
	end

	local ok, msg = SetStock(ugcData.AssetId, math.floor(tonumber(newAmount) or -1))
	return {success = ok, message = msg}
end

-- ========================================
-- COMMANDES DE CHAT POUR LES ADMINS
-- ========================================
game.Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		if not IsAdmin(player) then return end

		pcall(function()
			-- /resetstock [Nom ou AssetId]
			if message:match("^/resetstock%s+") then
				local searchTerm = message:match("^/resetstock%s+(.+)")
				if searchTerm then
					local ugcData = nil
					for _, ugc in ipairs(UGC_CONFIG.Items) do
						if ugc.Name:lower():find(searchTerm:lower(), 1, true) or ugc.AssetId == tonumber(searchTerm) then
							ugcData = ugc
							break
						end
					end
					if ugcData then
						local ok, msg = SetStock(ugcData.AssetId, ugcData.InitialStock)
						print(ok and ("✅ " .. msg) or ("❌ " .. msg))
					else
						warn("❌ UGC '" .. searchTerm .. "' introuvable!")
					end
				end

				-- 🆕 /setstock [Nom ou AssetId] [quantité]
			elseif message:match("^/setstock%s+") then
				-- Supporte noms avec espaces: /setstock Mon UGC Cool 42
				-- Le dernier token est la quantité
				local args = message:match("^/setstock%s+(.+)")
				if args then
					-- Séparer le dernier mot (quantité) du reste (nom/id)
					local searchTerm, amountStr = args:match("^(.+)%s+(%d+)$")
					if searchTerm and amountStr then
						local newAmount = tonumber(amountStr)
						local ugcData = nil
						for _, ugc in ipairs(UGC_CONFIG.Items) do
							if ugc.Name:lower():find(searchTerm:lower(), 1, true) or ugc.AssetId == tonumber(searchTerm) then
								ugcData = ugc
								break
							end
						end
						if ugcData then
							local ok, msg = SetStock(ugcData.AssetId, newAmount)
							print(ok and ("✅ " .. msg) or ("❌ " .. msg))
						else
							warn("❌ UGC '" .. searchTerm .. "' introuvable!")
						end
					else
						warn("❌ Usage: /setstock [Nom ou AssetId] [quantité]")
						warn("   Exemple: /setstock MonUGC 50")
					end
				end

				-- /resetallstocks
			elseif message:lower() == "/resetallstocks" then
				for _, ugc in ipairs(UGC_CONFIG.Items) do
					CurrentStocks[tostring(ugc.AssetId)] = ugc.InitialStock
				end
				SaveStockData(false, true)
				UpdateStockEvent:FireAllClients(CurrentStocks)
				UpdateAllButtonStates()
				print("✅ Tous les stocks ont été reset!")

				-- /stocks
			elseif message:lower() == "/stocks" then
				print("📊 STOCKS ACTUELS:")
				for _, ugc in ipairs(UGC_CONFIG.Items) do
					local current = CurrentStocks[tostring(ugc.AssetId)] or 0
					print("  - " .. ugc.Name .. ": " .. current .. "/" .. ugc.InitialStock)
				end
			end
		end)
	end)

	-- Envoyer l'état initial au joueur
	task.spawn(function()
		while not DataLoaded do task.wait(0.5) end
		task.wait(1)
		pcall(function()
			local buttonStates = {}
			for _, ugc in ipairs(UGC_CONFIG.Items) do
				local assetKey = tostring(ugc.AssetId)
				local currentStock = CurrentStocks[assetKey] or 0
				buttonStates[ugc.ButtonName] = {
					IsActive = currentStock > 0,
					Stock = currentStock
				}
			end
			UpdateButtonStateEvent:FireClient(player, buttonStates)
			print("📡 [SERVEUR] État initial envoyé à " .. player.Name)
		end)
	end)
end)

-- ========================================
-- 🆕 ÉCOUTER LES MISES À JOUR DES AUTRES SERVEURS (MessagingService)
-- ========================================
local function SubscribeToStockUpdates()
	local success, err = pcall(function()
		MessagingService:SubscribeAsync(SYNC_TOPIC, function(message)
			pcall(function()
				local incomingStocks = message.Data
				if type(incomingStocks) ~= "table" then
					warn("⚠️ [SERVEUR] Message sync invalide reçu")
					return
				end

				print("🔄 [SERVEUR] Sync reçue depuis un autre serveur - mise à jour des stocks...")

				-- Mettre à jour uniquement les clés reçues
				for key, value in pairs(incomingStocks) do
					if type(value) == "number" and value >= 0 then
						CurrentStocks[key] = value
					end
				end

				-- Mettre à jour les clients de CE serveur
				UpdateStockEvent:FireAllClients(CurrentStocks)
				UpdateAllButtonStates()

				print("✅ [SERVEUR] Stocks synchronisés depuis un autre serveur")
			end)
		end)
		print("✅ [SERVEUR] Abonnement MessagingService actif (topic: " .. SYNC_TOPIC .. ")")
	end)

	if not success then
		warn("⚠️ [SERVEUR] MessagingService indisponible (test local?): " .. tostring(err))
		warn("   → La sync cross-serveurs ne fonctionnera pas en studio local")
	end
end

-- ========================================
-- INITIALISATION SÉCURISÉE
-- ========================================
print("🚀 [SERVEUR] CHARGEMENT DU SYSTÈME DE STOCK UGC...")
print("⏳ [SERVEUR] Attente de 3 secondes pour stabiliser le serveur...")
task.wait(3)

-- S'abonner aux updates des autres serveurs EN PREMIER
SubscribeToStockUpdates()

-- Charger les données
CurrentStocks = LoadStockData()

local allZero = true
for _, ugc in ipairs(UGC_CONFIG.Items) do
	local assetKey = tostring(ugc.AssetId)
	if not CurrentStocks[assetKey] then
		warn("⚠️ [SERVEUR] Stock manquant pour " .. ugc.Name .. ", ajout...")
		CurrentStocks[assetKey] = ugc.InitialStock
	end
	if CurrentStocks[assetKey] > 0 then
		allZero = false
	end
end

if allZero then
	warn("ℹ️ [SERVEUR] Tous les stocks sont à 0 - stocks épuisés")
end

DataLoaded = true
print("✅ [SERVEUR] DONNÉES CHARGÉES - DataLoaded = true")

print("📡 [SERVEUR] Envoi de l'état initial des boutons...")
task.wait(0.5)
UpdateAllButtonStates()

MarketplaceService.PromptPurchaseFinished:Connect(OnPromptPurchaseFinished)

print("✅ [SERVEUR] SYSTÈME DE STOCK UGC OPÉRATIONNEL!")
print("📋 [SERVEUR] Commandes admin disponibles:")
print("   /setstock [Nom ou AssetId] [quantité]  → Définir un stock précis")
print("   /resetstock [Nom ou AssetId]            → Reset au stock initial")
print("   /resetallstocks                         → Reset tous les stocks")
print("   /stocks                                 → Afficher les stocks actuels")



--════════════════════════════════════════════════════════════════════════════
-- 🌐 SOURCE DU STOCK — « Compteur maison » ⇄ « Stock Roblox »
--
--  📍 OÙ COLLER ?
--     À la toute fin de ton SCRIPT SERVEUR STOCK UGC, juste AVANT le bloc :
--         -- ========================================
--         -- SAUVEGARDE AUTOMATIQUE (5 MINUTES)
--
--     Rien à supprimer. Ce bloc ne modifie aucune de tes fonctions : il
--     s'ajoute par-dessus et reprend la main sur les deux remotes d'affichage.
--
--  ── LES DEUX MODES ──────────────────────────────────────────────────────
--
--     📦 COMPTEUR MAISON  (mode "internal", celui que tu as aujourd'hui)
--        Le stock est un nombre que TU possèdes, dans ton DataStore. Il
--        descend d'un cran à chaque achat confirmé, et tu peux le corriger à
--        la main depuis le panel. C'est fiable et instantané — mais si un
--        exploit passe entre les mailles, le compteur ne bouge pas et tu dois
--        rattraper toi-même.
--
--     🌐 STOCK ROBLOX  (mode "live")
--        Le stock affiché est celui que Roblox connaît vraiment
--        (`unitsAvailableForConsumption` du catalogue). Impossible à
--        désynchroniser : c'est la source de vérité. En contrepartie il
--        dépend d'un appel HTTP, et il ne se rafraîchit que toutes les N
--        secondes.
--
--  ── LE REPLI (ce que tu as demandé) ─────────────────────────────────────
--
--     Tant que le mode live fonctionne, CHAQUE lecture réussie est recopiée
--     dans le compteur maison (« miroir »). Le compteur maison est donc en
--     permanence égal au dernier stock réel connu.
--
--     Si l'API devient injoignable, on repasse automatiquement sur le
--     compteur maison — qui contient donc exactement le dernier stock connu,
--     et qui continue de descendre à chaque achat. Les joueurs ne voient
--     rien, toi tu vois un badge « ⚠️ repli » dans le panel.
--
--  ── ⚠️ IL TE FAUT UN PROXY ──────────────────────────────────────────────
--
--     Roblox interdit à HttpService d'appeler ses propres domaines. Il faut
--     passer par un relais. Deux options, détaillées dans INSTALL_STOCK.md :
--        • RoProxy (gratuit, 0 installation)  → proxyHost = "roproxy.com"
--        • Ton propre Cloudflare Worker (5 min, plus fiable, quota à toi)
--
--     Le bouton « 🧪 Tester la connexion » du panel te dit en une phrase si
--     ça marche, et pourquoi si ça ne marche pas.
--════════════════════════════════════════════════════════════════════════════

local HttpService = game:GetService("HttpService")
local ProxyCache = require(game:GetService("ServerScriptService"):WaitForChild("ProxyCache"))
local CACHE_CHECK_SECONDS = 30 -- lecture partagée ; le TTL HTTP reste pollSeconds
local PURCHASE_SYNC = {
	RetryDelays = { 10, 60 }, -- 2 relectures ciblées seulement (avant 4 : elles provoquaient des 429) ;
	                          -- le décrément reste protégé 5 min de toute façon
	ProtectionSeconds = 300, -- protège le décrément pendant le retard de l'API
}
local PURCHASE_TOPIC = "UGCConfirmedStock_v1"
local PendingPurchases = {}
local PurchaseWorkers = {}
local purchaseSequence = 0
-- ⚠️ Ton script de stock n'a pas de `local Players` : il écrit `game.Players`
--    directement. On récupère donc le service ici, sinon le diagnostic plante.
local StockPlayers = game:GetService("Players")

-- 🔎 Marqueur de version : si tu ne vois PAS cette ligne dans l'Output du
--    serveur, c'est que ce bloc n'a pas été atteint — soit il n'est pas collé,
--    soit une erreur plus haut dans le script de stock a tout arrêté.
print("🔧 [STOCK] Bloc « source du stock » v1.3 vérification après achat — démarrage…")
_G.UGCStock_Loaded = true

local MODE_STORE = DataStoreService:GetDataStore("UGCStockMode_v1")
local MODE_KEY   = "config"
local MODE_TOPIC = "UGCStockModeSync_v1"

-- Au-delà de (pollSeconds × ce facteur) sans lecture réussie, on considère la
-- donnée live périmée et on bascule sur le compteur maison.
local STALE_FACTOR = 3

local StockCfg = {
	mode        = "internal",   -- "internal" (compteur maison) | "live" (stock Roblox)
	proxyHost   = "",           -- "" = appel direct | "roproxy.com" | ton worker
	pollSeconds = 120,          -- intervalle entre deux sondages
	mirror      = true,         -- recopier le stock live dans le compteur maison
}

-- [assetKey] = { rem = restant, total = total, at = timestamp, name = "..." }
local Live = {}

local LiveState = {
	lastTry = 0, lastOk = 0, ok = false, err = nil,
	fetching = false, okCount = 0, failCount = 0, lastMs = 0,
}

--════════════════════════════════════════════════════════════
-- REMOTES ADMIN
--════════════════════════════════════════════════════════════
local panelFn = Instance.new("RemoteFunction")
panelFn.Name = "AdminGetStockPanel"
panelFn.Parent = ReplicatedStorage

local modeFn = Instance.new("RemoteFunction")
modeFn.Name = "AdminSetStockMode"
modeFn.Parent = ReplicatedStorage

local stockActionFn = Instance.new("RemoteFunction")
stockActionFn.Name = "AdminStockAction"
stockActionFn.Parent = ReplicatedStorage

--════════════════════════════════════════════════════════════
-- 🔐 QUI A LE DROIT D'OUVRIR CES RÉGLAGES ?
--
--   ⚠️ Ton script de stock n'a QU'UN SEUL id dans ADMIN_USER_IDS, alors que
--      ton panel admin en connaît cinq. Se contenter de `IsAdmin` ferait
--      répondre « not admin » à quatre de tes cinq admins, et le panel
--      afficherait « impossible de charger » sans dire pourquoi.
--      On accepte donc les deux listes.
--════════════════════════════════════════════════════════════
local PANEL_ADMIN_IDS = {
	3203521470, 11017023724, 8456613930, 8142402169, 10420404767,
}

local function stockAdmin(player)
	if IsAdmin(player) then return true end
	for _, id in ipairs(PANEL_ADMIN_IDS) do
		if player.UserId == id then return true end
	end
	return false
end

local function denied(player)
	return {
		ok = false,
		msg = string.format(
			"⛔ Ton UserID (%d) n'est dans aucune des deux listes admin. "
				.. "Ajoute-le dans ADMIN_USER_IDS de ton script de stock, "
				.. "ou dans PANEL_ADMIN_IDS de ce bloc.",
			player.UserId),
	}
end

--════════════════════════════════════════════════════════════
-- CONFIGURATION : lecture, écriture, synchronisation
--════════════════════════════════════════════════════════════
local function sanitizeStockCfg(raw)
	local c = { mode = "internal", proxyHost = "", pollSeconds = 120, mirror = true }
	if type(raw) ~= "table" then return c end

	if raw.mode == "live" then c.mode = "live" end

	-- On n'accepte qu'un nom de domaine nu : pas de schéma, pas de chemin,
	-- pas d'espace. Ça empêche de transformer ce champ en n'importe quoi.
	if type(raw.proxyHost) == "string" then
		local h = raw.proxyHost
		h = h:gsub("%s", ""):lower()
		h = h:gsub("^https?://", "")
		h = h:gsub("/.*$", "")
		h = h:gsub("^catalog%.", "")          -- il collera peut-être l'URL complète
		if h == "" or (#h <= 80 and h:match("^[%w%-%.]+%.%a%a+$")) then
			c.proxyHost = h
		end
	end

	local p = tonumber(raw.pollSeconds)
	if p and p == p then c.pollSeconds = math.clamp(math.floor(p), 30, 900) end

	if type(raw.mirror) == "boolean" then c.mirror = raw.mirror end
	return c
end

local function applyStockCfg(c)
	for k, v in pairs(c) do StockCfg[k] = v end
end

local function loadStockCfg()
	for attempt = 1, 3 do
		local ok, data = pcall(function() return MODE_STORE:GetAsync(MODE_KEY) end)
		if ok then
			applyStockCfg(sanitizeStockCfg(data))
			print(string.format("⚙️ [STOCK] Mode = %s | proxy = %s | sondage = %d s",
				StockCfg.mode,
				StockCfg.proxyHost ~= "" and StockCfg.proxyHost or "(direct)",
				StockCfg.pollSeconds))
			return true
		end
		task.wait(1.2 * attempt)
	end
	warn("⚠️ [STOCK] Réglages illisibles → 📦 Compteur maison par défaut")
	return false
end

local function saveStockCfg(raw, byName)
	local clean = sanitizeStockCfg(raw)
	local ok = pcall(function() MODE_STORE:SetAsync(MODE_KEY, clean) end)
	if not ok then return false, "DataStore indisponible, réessaie." end

	applyStockCfg(clean)
	pcall(function()
		MessagingService:PublishAsync(MODE_TOPIC, { cfg = clean, by = byName or "?" })
	end)

	print(string.format("⚙️ [STOCK] Réglages modifiés par %s | mode=%s proxy=%s sondage=%ds miroir=%s",
		tostring(byName), clean.mode,
		clean.proxyHost ~= "" and clean.proxyHost or "(direct)",
		clean.pollSeconds, tostring(clean.mirror)))
	return true, "Réglages appliqués sur tous les serveurs."
end

task.spawn(function()
	pcall(function()
		MessagingService:SubscribeAsync(MODE_TOPIC, function(msg)
			local d = msg and msg.Data
			if type(d) == "table" and type(d.cfg) == "table" then
				applyStockCfg(sanitizeStockCfg(d.cfg))
				print("🔄 [STOCK] Réglages synchronisés depuis un autre serveur ("
					.. tostring(d.by) .. ")")
			end
		end)
	end)
end)

--════════════════════════════════════════════════════════════
-- 🌐 LECTURE DU STOCK RÉEL
--
--   On utilise le point d'entrée GET du catalogue, un item à la fois :
--     https://catalog.<host>/v1/catalog/items/<assetId>/details?itemType=Asset
--
--   Pourquoi un par un plutôt que le lot ? Le lot passe par un POST qui
--   réclame un jeton CSRF selon les proxys, et un seul item en erreur fait
--   tomber toute la requête. Un par un : aucun jeton, et un item qui échoue
--   n'empêche pas les dix autres de se mettre à jour.
--════════════════════════════════════════════════════════════
-- Deux façons d'écrire l'adresse selon le relais utilisé. On essaie la
-- première ; si elle ne répond pas du tout, on bascule sur l'autre et on
-- retient laquelle a marché. Tu n'as donc rien à choisir dans le panel.
--
--   "sub"  → https://catalog.<host>/v1/catalog/items/...
--            RoProxy, et tout Worker posé sur ton propre domaine
--   "path" → https://<host>/catalog/v1/catalog/items/...
--            Cloudflare Worker en .workers.dev (pas de sous-domaine possible)
local proxyForm = "sub"
local detectedHost = nil
local routeProbeAfter = 0

local function catalogUrl(assetId, hostOverride, formOverride)
	local tail = "/v1/catalog/items/" .. tostring(assetId) .. "/details?itemType=Asset"
	local host = hostOverride or StockCfg.proxyHost
	local form = formOverride or proxyForm

	if host == "" then
		return "https://catalog.roblox.com" .. tail
	end
	if form == "path" then
		return "https://" .. host .. "/catalog" .. tail
	end
	return "https://catalog." .. host .. tail
end

-- Retourne : ok, restant, total, message
local function fetchOneAt(url)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = { ["Accept"] = "application/json" },
		})
	end)

	if not ok then
		local m = tostring(res)
		if m:find("not allowed to access ROBLOX resources", 1, true) then
			m = "Roblox refuse l'appel direct → configure un proxy"
		elseif m:find("Http requests are not enabled", 1, true) then
			m = "HttpService désactivé → Game Settings ▸ Security ▸ Allow HTTP Requests"
		end
		return false, nil, nil, m
	end

	if not res.Success then
		if res.StatusCode == 429 then
			local retryAfter = 120
			for k, v in pairs(res.Headers or {}) do
				if tostring(k):lower() == "retry-after" then retryAfter = math.max(retryAfter, tonumber(v) or 0) end
			end
			return false, nil, nil, "429 — trop de requêtes, pause partagée", 429, retryAfter
		end
		return false, nil, nil, string.format("HTTP %d %s",
			res.StatusCode, tostring(res.StatusMessage)), res.StatusCode
	end

	local okJ, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
	if not okJ or type(data) ~= "table" then
		return false, nil, nil, "réponse illisible (le proxy renvoie-t-il du JSON ?)"
	end

	-- Roblox a plusieurs noms selon l'époque et le type d'item.
	local rem = tonumber(data.unitsAvailableForConsumption)
	local tot = tonumber(data.totalQuantity)
		or tonumber(data.assetStock)
		or tonumber(data.unitsAvailable)

	if rem == nil or rem ~= rem or rem == math.huge or rem == -math.huge then
		-- Pas un limité, ou plus en vente : Roblox ne publie pas de compteur.
		return false, nil, nil, "pas de stock publié (item non limité ou hors vente)"
	end

	if tot and (tot ~= tot or math.abs(tot) == math.huge) then tot = nil end
	return true, math.max(0, math.floor(rem)),
		tot and math.max(0, math.floor(tot)) or nil,
		tostring(data.name or "")
end

-- Tous les points d'entrée (sondage, test admin, refresh) passent par ce cache.
-- La clé inclut le proxy pour qu'un changement d'hôte teste bien le nouvel hôte.
local function fetchOne(assetId, force)
	local host = StockCfg.proxyHost
	local key = "stock:" .. (host ~= "" and host or "direct") .. ":" .. tostring(assetId)
	local data, at, cacheErr, version = ProxyCache.Get(key, StockCfg.pollSeconds, function()
		if detectedHost ~= host then
			detectedHost = host
			proxyForm = host:match("%.workers%.dev$") and "path" or "sub"
			routeProbeAfter = 0
		end
		local initialForm = proxyForm
		local ok, rem, tot, msg, code, retryAfter = fetchOneAt(catalogUrl(assetId, host, initialForm))
		-- Ne jamais doubler un appel à cause d'un 429, 403 ou 5xx.
		-- Pour un domaine personnalisé inconnu, un seul essai d'autre route / 10 min.
		if not ok and host ~= "" and not host:match("%.workers%.dev$")
			and (code == 404 or code == nil) and os.clock() >= routeProbeAfter
			and not tostring(msg):find("pas de stock publié", 1, true)
			and not tostring(msg):find("réponse illisible", 1, true) then
			routeProbeAfter = os.clock() + 600
			local otherForm = initialForm == "sub" and "path" or "sub"
			local ok2, rem2, tot2, msg2, code2, retry2 = fetchOneAt(catalogUrl(assetId, host, otherForm))
			if ok2 then
				ok, rem, tot, msg = ok2, rem2, tot2, msg2
				if detectedHost == host then proxyForm = otherForm end
			else
				retryAfter = retry2 or retryAfter
			end
		end
		if not ok then return nil, msg, retryAfter end
		return { rem = rem, total = tot, name = msg }
	end, force == true)
	if type(data) ~= "table" or not at then
		return false, nil, nil, cacheErr or "chargement partagé en cours"
	end
	-- Une ancienne réponse ne devient jamais fraîche parce qu'on la relit.
	if os.time() - at > StockCfg.pollSeconds * STALE_FACTOR then
		return false, nil, nil, cacheErr or "stock partagé périmé"
	end
	return true, data.rem, data.total, data.name, at, version
end

local pushStocks  -- déclarée plus bas, utilisée ici

-- Une confirmation constitue une information plus récente qu'un ancien relevé.
-- Le compteur brut reste accessible pour le diagnostic, sans être présenté
-- comme une sous-estimation certaine pendant la propagation de l'achat.
local function pendingFor(key)
	local pending = PendingPurchases[key]
	if pending and os.time() >= pending.untilAt then
		PendingPurchases[key] = nil
		return nil
	end
	return pending
end

local function protectConfirmedStock(assetId, remaining)
	local key = tostring(assetId)
	local previous = pendingFor(key)
	local l = Live[key]
	purchaseSequence = purchaseSequence + 1
	local expected = math.max(0, math.floor(remaining))
	if previous then expected = math.min(expected, previous.expected) end
	PendingPurchases[key] = {
		expected = expected, sequence = purchaseSequence,
		baseVersion = l and l.version,
		untilAt = os.time() + PURCHASE_SYNC.ProtectionSeconds,
	}
	if l then l.rem = math.min(l.rem, expected) end
	if CurrentStocks[key] then CurrentStocks[key] = math.min(CurrentStocks[key], expected) end
end

local applyRead
local function readAndApplyOne(assetId, force)
	local key = tostring(assetId)
	local before = pendingFor(key)
	local sequence = before and before.sequence
	local requestHost, requestMode = StockCfg.proxyHost, StockCfg.mode
	local ok, rem, tot, msg, at, version = fetchOne(assetId, force)
	if not ok then return false, msg end
	if StockCfg.proxyHost ~= requestHost or StockCfg.mode ~= requestMode then
		return false, "configuration modifiée pendant la lecture"
	end
	return applyRead(key, sequence, rem, tot, msg, at, version)
end

applyRead = function(key, sequence, rem, tot, msg, at, version)
	local pending = pendingFor(key)
	-- Un achat arrivé pendant la requête rend sa réponse trop ancienne pour
	-- confirmer cet achat. Une passe ciblée suivante la remplacera.
	if pending and pending.sequence ~= sequence then return false, "achat survenu pendant la lecture" end
	local adjusted = rem
	if pending then
		if version ~= pending.baseVersion and rem <= pending.expected then
			PendingPurchases[key] = nil
			pending = nil
		else
			adjusted = math.min(rem, pending.expected)
		end
	end
	local old = Live[key]
	-- Conserve aussi le décrément sur une simple relecture de la même version.
	if old and old.version == version then adjusted = math.min(adjusted, old.rem) end
	Live[key] = {
		rem = adjusted, total = tot, at = at, version = version,
		name = msg, rawRem = rem, pendingPurchase = pending ~= nil,
	}
	if StockCfg.mirror and DataLoaded and CurrentStocks[key] ~= adjusted then
		CurrentStocks[key] = adjusted
	end
	return true
end

--════════════════════════════════════════════════════════════
-- 📦 LECTURE GROUPÉE : UNE requête pour TOUS les UGC (au lieu d'une par UGC)
--   POST /v1/catalog/items/details (jusqu'à 100 items par requête, jeton CSRF géré).
--   Avant : 81 requêtes à chaque sondage → l'API répondait 429 « trop de requêtes », les UGC
--   non relus retombaient sur le compteur maison (souvent 0) → faux « out of stock ».
--   Le résultat est partagé entre TOUS les serveurs (ProxyCache) : 1 seul appel par sondage.
--   Si ton relais refuse le POST, on repasse tout seul sur l'ancienne lecture un par un.
--════════════════════════════════════════════════════════════
local BatchState = { csrf = nil, unsupportedUntil = 0, lastErr = nil }

local function batchUrl(host, form)
	local tail = "/v1/catalog/items/details"
	if host == "" then return "https://catalog.roblox.com" .. tail end
	if form == "path" then return "https://" .. host .. "/catalog" .. tail end
	return "https://catalog." .. host .. tail
end

local function postBatch(url, ids)
	local list = {}
	for _, id in ipairs(ids) do list[#list + 1] = { itemType = "Asset", id = id } end
	local body = HttpService:JSONEncode({ items = list })
	for attempt = 1, 2 do
		local headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }
		if BatchState.csrf then headers["X-CSRF-TOKEN"] = BatchState.csrf end
		local ok, res = pcall(function()
			return HttpService:RequestAsync({ Url = url, Method = "POST", Headers = headers, Body = body })
		end)
		if not ok then return nil, tostring(res) end
		if res.Success then
			local okJ, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
			if not okJ or type(data) ~= "table" or type(data.data) ~= "table" then
				return nil, "réponse illisible (le relais renvoie-t-il du JSON ?)"
			end
			return data.data
		end
		local token, retryAfter = nil, 120
		for k, v in pairs(res.Headers or {}) do
			local lk = tostring(k):lower()
			if lk == "x-csrf-token" then token = v end
			if lk == "retry-after" then retryAfter = math.max(retryAfter, tonumber(v) or 0) end
		end
		if res.StatusCode == 403 and token and attempt == 1 then
			BatchState.csrf = token   -- Roblox demande un jeton : on renvoie avec
		elseif res.StatusCode == 429 then
			return nil, "429 — trop de requêtes, pause partagée", 429, retryAfter
		else
			return nil, string.format("HTTP %d %s", res.StatusCode, tostring(res.StatusMessage)), res.StatusCode
		end
	end
	return nil, "jeton CSRF refusé par le relais", 403
end

-- Retourne : data { [assetId] = {rem,total,name} }, at, err, version  (data peut être ancienne)
local function fetchBatch()
	local host = StockCfg.proxyHost
	local key = "stockbatch:" .. (host ~= "" and host or "direct")
	return ProxyCache.Get(key, StockCfg.pollSeconds, function()
		local ids = {}
		for _, ugc in ipairs(UGC_CONFIG.Items) do
			if tonumber(ugc.AssetId) and ugc.AssetId > 0 then ids[#ids + 1] = ugc.AssetId end
		end
		local form = host:match("%.workers%.dev$") and "path" or "sub"
		local out, got, lastErr, lastCode, lastRetry = {}, 0, nil, nil, nil
		for i = 1, #ids, 100 do
			local chunk = {}
			for j = i, math.min(i + 99, #ids) do chunk[#chunk + 1] = ids[j] end
			local rows, err, code, retry = postBatch(batchUrl(host, form), chunk)
			if not rows then
				lastErr, lastCode, lastRetry = err, code, retry
				if code == 429 then break end
			else
				for _, d in ipairs(rows) do
					local rem = tonumber(d.unitsAvailableForConsumption)
					local tot = tonumber(d.totalQuantity) or tonumber(d.assetStock) or tonumber(d.unitsAvailable)
					if rem and rem == rem and math.abs(rem) ~= math.huge and tonumber(d.id) then
						if tot and (tot ~= tot or math.abs(tot) == math.huge) then tot = nil end
						out[tostring(d.id)] = {
							rem = math.max(0, math.floor(rem)),
							total = tot and math.max(0, math.floor(tot)) or nil,
							name = tostring(d.name or ""),
						}
						got = got + 1
					end
				end
			end
		end
		if got == 0 then
			-- relais qui ne gère pas le POST : on revient à la lecture un par un pendant 1 h
			if lastCode == nil or lastCode == 400 or lastCode == 403 or lastCode == 404
				or lastCode == 405 or lastCode == 501 or lastCode == 502 then
				BatchState.unsupportedUntil = os.clock() + 3600
			end
			return nil, lastErr or "aucun stock publié", lastRetry
		end
		return out
	end, false)
end

--════════════════════════════════════════════════════════════
-- 🏠 LECTURE PAR LE MOTEUR ROBLOX (MarketplaceService:GetProductInfo)
--   Aucun appel HTTP, aucun relais : Roblox ne peut pas renvoyer « 429 » à cause de l'adresse
--   Cloudflare partagée avec d'autres jeux (c'était la vraie cause : même UNE requête était
--   refusée). Un seul serveur relit les 81 UGC toutes les « pollSeconds », étalé sur ~1 min
--   (limite Roblox ≈ 100 appels / min / serveur), résultat partagé avec tous les serveurs.
--   Si le moteur ne publie pas le stock d'un UGC, on garde la lecture HTTP en secours.
--════════════════════════════════════════════════════════════
local EngineState = { unsupportedUntil = 0 }

local function engineRead(assetId)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
	end)
	if not ok or type(info) ~= "table" then return nil, tostring(info) end
	local cd = type(info.CollectiblesItemDetails) == "table" and info.CollectiblesItemDetails or {}
	local rem = tonumber(info.Remaining) or tonumber(cd.UnitsAvailableForConsumption)
		or tonumber(cd.UnitsAvailable) or tonumber(info.UnitsAvailableForConsumption)
	local tot = tonumber(cd.TotalQuantity) or tonumber(info.TotalQuantity) or tonumber(info.AssetStock)
	if rem == nil or rem ~= rem or math.abs(rem) == math.huge then return nil, "pas de stock publié" end
	if tot and (tot ~= tot or math.abs(tot) == math.huge) then tot = nil end
	return { rem = math.max(0, math.floor(rem)), total = tot and math.max(0, math.floor(tot)) or nil,
		name = tostring(info.Name or "") }
end

local function fetchEngine()
	return ProxyCache.Get("stockengine:v1", StockCfg.pollSeconds, function()
		local out, got, lastErr = {}, 0, nil
		for _, ugc in ipairs(UGC_CONFIG.Items) do
			if tonumber(ugc.AssetId) and ugc.AssetId > 0 then
				local d, err = engineRead(ugc.AssetId)
				if d then out[tostring(ugc.AssetId)] = d; got = got + 1 else lastErr = err end
				task.wait(0.7)   -- ≈ 85 appels / min max : sous la limite Roblox
			end
		end
		if got == 0 then
			EngineState.unsupportedUntil = os.clock() + 3600
			return nil, "moteur : " .. tostring(lastErr or "aucun stock publié")
		end
		return out
	end, false)
end

-- Diagnostic : _G.UGCStock_TestEngine()  → ce que le moteur renvoie pour le 1er UGC
_G.UGCStock_TestEngine = function(assetId)
	assetId = assetId or (UGC_CONFIG.Items[1] and UGC_CONFIG.Items[1].AssetId)
	local ok, info = pcall(function() return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset) end)
	print("🔎 GetProductInfo", assetId, ok)
	if ok and type(info) == "table" then
		print("   Name =", info.Name, "| IsLimited =", info.IsLimited, "| Remaining =", info.Remaining)
		if type(info.CollectiblesItemDetails) == "table" then
			for k, v in pairs(info.CollectiblesItemDetails) do print("   CollectiblesItemDetails." .. tostring(k), "=", v) end
		end
	end
	print("   → lu :", engineRead(assetId))
end

-- Ancienne méthode, gardée en secours : un UGC à la fois (lente, sujette aux 429)
local function fetchAllOneByOne()
	local okN, total, lastErr = 0, 0, nil
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		total = total + 1
		local ok, msg = readAndApplyOne(ugc.AssetId, false)
		if ok then okN = okN + 1 else lastErr = msg end
		task.wait(0.3)
	end
	return okN, total, lastErr
end

-- Consulte les UGC via le cache partagé. Retourne : nbOk, nbTotal, dernierMessage
local function fetchAll(reason)
	if LiveState.fetching then return 0, 0, "sondage déjà en cours" end
	LiveState.fetching = true
	LiveState.lastTry  = os.time()

	local started = os.clock()
	local okN, total, lastErr = 0, 0, nil

	local passOK, passErr = pcall(function()
		if os.clock() < BatchState.unsupportedUntil and os.clock() < EngineState.unsupportedUntil then
			okN, total, lastErr = fetchAllOneByOne()
			return
		end
		local seqs = {}
		for _, ugc in ipairs(UGC_CONFIG.Items) do
			local p = pendingFor(tostring(ugc.AssetId))
			seqs[tostring(ugc.AssetId)] = p and p.sequence
		end
		local requestHost, requestMode = StockCfg.proxyHost, StockCfg.mode
		local data, at, err, version
		if os.clock() >= EngineState.unsupportedUntil then
			data, at, err, version = fetchEngine()
			local fresh = type(data) == "table" and at and (os.time() - at) <= StockCfg.pollSeconds * STALE_FACTOR
			if not fresh and os.clock() < EngineState.unsupportedUntil then
				data, at, err, version = fetchBatch()   -- le moteur ne publie pas ces stocks : HTTP
			elseif not fresh and type(data) ~= "table" then
				data, at, err, version = nil, nil, err, nil   -- 1re lecture en cours : on attend
			end
		else
			data, at, err, version = fetchBatch()
		end
		if StockCfg.proxyHost ~= requestHost or StockCfg.mode ~= requestMode then
			lastErr = "configuration modifiée pendant la lecture"
			return
		end
		-- un AUTRE serveur a constaté que le relais refuse le POST (erreur partagée) : pareil ici
		if type(data) ~= "table" and type(err) == "string" and (err:match("^HTTP 40[0345]")
			or err:match("^HTTP 50[12]") or err:find("illisible", 1, true) or err:find("CSRF", 1, true)) then
			BatchState.unsupportedUntil = os.clock() + 3600
		end
		if type(data) ~= "table" and os.clock() < BatchState.unsupportedUntil
			and os.clock() < EngineState.unsupportedUntil then
			-- le relais vient de refuser la lecture groupée : secours immédiat
			okN, total, lastErr = fetchAllOneByOne()
			return
		end
		lastErr = err
		local fresh = type(data) == "table" and at and (os.time() - at) <= StockCfg.pollSeconds * STALE_FACTOR
		for _, ugc in ipairs(UGC_CONFIG.Items) do
			total = total + 1
			local key = tostring(ugc.AssetId)
			local d = type(data) == "table" and data[key] or nil
			if d and fresh then
				local ok, msg = applyRead(key, seqs[key], d.rem, d.total, d.name, at, version)
				if ok then okN = okN + 1 else lastErr = msg end
			elseif d and not Live[key] then
				-- 🛡️ donnée ancienne mais RÉELLE : sert de repli au lieu du compteur maison
				Live[key] = { rem = d.rem, total = d.total, at = at, version = version,
					name = d.name, rawRem = d.rem, pendingPurchase = false }
			end
		end
	end)
	if not passOK then lastErr = tostring(passErr) end
	LiveState.fetching = false
	LiveState.lastMs   = math.floor((os.clock() - started) * 1000)

	if okN > 0 then
		LiveState.lastOk   = os.time()
		LiveState.ok       = true
		LiveState.err      = (okN < total) and lastErr or nil
		LiveState.okCount  = LiveState.okCount + 1
	else
		LiveState.ok        = false
		LiveState.err       = lastErr or "aucune réponse"
		LiveState.failCount = LiveState.failCount + 1
		warn(string.format("⚠️ [STOCK] Sondage live échoué (%s) : %s",
			tostring(reason), tostring(LiveState.err)))
	end

	return okN, total, lastErr
end

--════════════════════════════════════════════════════════════
-- 📊 LE STOCK EFFECTIF  (le cœur de la bascule)
--
--   Retourne : restant, total, source
--     source = "live"     → valeur fraîche venue de Roblox
--              "degraded" → mode live actif mais API muette : compteur maison,
--                           qui vaut le dernier stock réel connu
--              "internal" → mode compteur maison assumé
--════════════════════════════════════════════════════════════
local function liveIsFresh(entry)
	if not entry then return false end
	return (os.time() - (entry.at or 0)) <= (StockCfg.pollSeconds * STALE_FACTOR)
end

local function stockOf(assetId)
	local key = tostring(assetId)
	local ugc = UGC_CONFIG.GetByAssetId(assetId)
	local fallbackTotal = (ugc and ugc.InitialStock) or 0
	local pending = pendingFor(key)
	local function protected(value)
		return pending and math.min(value, pending.expected) or value
	end

	if StockCfg.mode == "live" then
		local l = Live[key]
		if liveIsFresh(l) then
			return protected(l.rem), l.total or fallbackTotal, "live"
		end
		-- 🛡️ Repli : le dernier stock RÉEL connu (relevé Roblox, même un peu ancien, diminué
		--    des achats confirmés depuis). Le compteur maison seulement si on n'a jamais rien lu :
		--    il peut valoir 0 alors que l'UGC est en stock (le faux « out of stock »).
		if l and type(l.rem) == "number" then
			return protected(l.rem), l.total or fallbackTotal, "degraded"
		end
		return protected(CurrentStocks[key] or 0),
			(l and l.total) or fallbackTotal,
			"degraded"
	end

	return CurrentStocks[key] or 0, fallbackTotal, "internal"
end

_G.UGCStock_Get = stockOf   -- utile pour d'autres scripts

--════════════════════════════════════════════════════════════
-- 📡 ENVOI AUX CLIENTS
--
--   On reprend la main sur les deux remotes d'affichage : sinon, en mode
--   live, tes fonctions existantes enverraient le compteur maison brut et le
--   joueur verrait un chiffre différent de celui du catalogue Roblox.
--════════════════════════════════════════════════════════════
pushStocks = function()
	if not DataLoaded then return end

	local stocks, totals, states = {}, {}, {}
	local degraded = false

	for _, ugc in ipairs(UGC_CONFIG.Items) do
		local key = tostring(ugc.AssetId)
		local cur, tot, src = stockOf(ugc.AssetId)
		stocks[key] = cur
		totals[key] = tot
		if src == "degraded" then degraded = true end
		states[ugc.ButtonName] = { IsActive = cur > 0, Stock = cur }
	end

	local meta = {
		mode     = StockCfg.mode,
		totals   = totals,
		degraded = degraded,
		at       = os.time(),
	}

	pcall(function()
		UpdateStockEvent:FireAllClients(stocks, meta)
		UpdateButtonStateEvent:FireAllClients(states)
	end)
end

_G.UGCStock_Push = pushStocks

--════════════════════════════════════════════════════════════
-- 🔌 ON REPREND LES REMOTES EXISTANTS
--════════════════════════════════════════════════════════════
GetStockFunction.OnServerInvoke = function(player, requestedAssetId)
	local waited = 0
	while not DataLoaded and waited < 10 do
		task.wait(0.5)
		waited = waited + 0.5
	end
	if not DataLoaded then return nil end

	local ugcData = UGC_CONFIG.GetByAssetId(requestedAssetId)
	if not ugcData then return nil end

	local cur, tot, src = stockOf(requestedAssetId)
	return {
		Config       = ugcData,
		CurrentStock = cur,
		Total        = tot,
		Source       = src,
		Mode         = StockCfg.mode,
	}
end

-- Une seule tâche ciblée par UGC. Les achats rapprochés rejoignent la tâche
-- existante ; chaque changement confirmé redemande une vérification récente.
local function schedulePurchaseRefresh(assetId)
	local key = tostring(assetId)
	if PurchaseWorkers[key] then return end
	PurchaseWorkers[key] = true
	task.spawn(function()
		local ok, err = pcall(function()
			local attempt, lastSequence, nextDue = 1, nil, os.clock()
			while StockCfg.mode == "live" do
				local pending = pendingFor(key)
				if not pending then break end
				if pending.sequence ~= lastSequence then
					lastSequence, attempt, nextDue = pending.sequence, 1, os.clock()
				end
				if PURCHASE_SYNC.RetryDelays[attempt] == nil then break end
				if os.clock() < nextDue then
					-- Une nouvelle confirmation peut interrompre ce délai rapidement.
					task.wait(math.min(0.25, nextDue - os.clock()))
				else
					readAndApplyOne(assetId, true) -- ignore le TTL normal de succès
					pushStocks()
					attempt = attempt + 1
					nextDue = os.clock() + (PURCHASE_SYNC.RetryDelays[attempt] or 0)
				end
			end
		end)
		PurchaseWorkers[key] = nil
		if not ok then warn("[STOCK] Vérification après achat : " .. tostring(err)) end
	end)
end

local originalOnConfirmed = _G.UGCStock_OnConfirmedPurchase
_G.UGCStock_OnConfirmedPurchase = function(assetId, playerName)
	-- Capture avant le décrément qui peut céder la main au DataStore.
	local key = tostring(assetId)
	local before = Live[key]
	local expected = before and math.max(0, before.rem - 1)
	local result = false
	if type(originalOnConfirmed) == "function" then
		local ok, res = pcall(originalOnConfirmed, assetId, playerName)
		result = ok and res or false
	end
	if StockCfg.mode == "live" and DataLoaded and type(assetId) == "number"
		and UGC_CONFIG.GetByAssetId(assetId) then
		-- Ce hook signifie déjà livraison confirmée, même si le compteur maison
		-- n'a pas pu être décrémenté (par exemple il était déjà à zéro).
		expected = math.min(expected or CurrentStocks[key] or 0, CurrentStocks[key] or expected or 0)
		protectConfirmedStock(assetId, expected)
		pushStocks()
		-- Lance la vérification ciblée dès la confirmation, sans attendre la boucle.
		schedulePurchaseRefresh(assetId)
		local notice = {
			assetId = assetId, remaining = expected,
			id = HttpService:GenerateGUID(false), origin = game.JobId,
			at = os.time(),
		}
		task.spawn(function()
			pcall(function() MessagingService:PublishAsync(PURCHASE_TOPIC, notice) end)
		end)
	else
		pushStocks()
	end
	return result
end

-- Les autres serveurs protègent aussi leur affichage, sans refaire la requête
-- HTTP après chaque notification. L'origine se charge de la lecture immédiate.
local seenPurchases = {}
task.spawn(function()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(PURCHASE_TOPIC, function(message)
			local d = message.Data
			if type(d) ~= "table" or d.origin == game.JobId or type(d.id) ~= "string"
				or type(d.assetId) ~= "number" or type(d.remaining) ~= "number"
				or d.remaining ~= d.remaining or d.remaining < 0 or d.remaining == math.huge
				or not UGC_CONFIG.GetByAssetId(d.assetId) or type(d.at) ~= "number" then return end
			local now = os.time()
			if now - d.at > PURCHASE_SYNC.ProtectionSeconds or d.at > now + 30 then return end
			for id, at in pairs(seenPurchases) do
				if now - at > PURCHASE_SYNC.ProtectionSeconds then seenPurchases[id] = nil end
			end
			if seenPurchases[d.id] then return end
			seenPurchases[d.id] = now
			if StockCfg.mode ~= "live" then return end
			protectConfirmedStock(d.assetId, d.remaining)
			local host = StockCfg.proxyHost
			ProxyCache.InvalidateLocal("stock:" .. (host ~= "" and host or "direct") .. ":" .. tostring(d.assetId))
			pushStocks()
		end)
	end)
	if not ok then warn("[STOCK] Notifications après achat indisponibles : " .. tostring(err)) end
end)

--════════════════════════════════════════════════════════════
-- 🔁 BOUCLE DE SONDAGE
--
--   Chaque serveur consulte le cache partagé. Une réservation par item
--   autorise un seul serveur à appeler le proxy lorsque le TTL expire.
--════════════════════════════════════════════════════════════
task.spawn(function()
	while not DataLoaded do task.wait(0.5) end
	loadStockCfg()

	task.wait(2 + math.random() * 8)

	if StockCfg.mode == "live" then
		fetchAll("démarrage")
		pushStocks()
	end

	while true do
		local step = math.min(CACHE_CHECK_SECONDS, StockCfg.pollSeconds)
		task.wait(step + math.random(0, 5))

		if StockCfg.mode == "live" then
			fetchAll("périodique")
		end
		-- Même en mode maison : ça corrige un affichage qu'une commande admin
		-- aurait envoyé sans passer par ici. C'est une petite table, aucun coût.
		pushStocks()
	end
end)

-- Relecture périodique des réglages : un changement fait sur un autre serveur
-- pendant que MessagingService avait un hoquet finit quand même par arriver.
task.spawn(function()
	while true do
		task.wait(300)
		local ok, data = pcall(function() return MODE_STORE:GetAsync(MODE_KEY) end)
		if ok and type(data) == "table" then applyStockCfg(sanitizeStockCfg(data)) end
	end
end)

--════════════════════════════════════════════════════════════
-- 🛠️ REMOTES DU PANEL ADMIN
--════════════════════════════════════════════════════════════
panelFn.OnServerInvoke = function(player)
	if not stockAdmin(player) then return denied(player) end

	local items = {}
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		local key = tostring(ugc.AssetId)
		local l   = Live[key]
		local cur, tot, src = stockOf(ugc.AssetId)

		table.insert(items, {
			assetId   = ugc.AssetId,
			imageId   = ugc.ImageId or ugc.AssetId,
			name      = ugc.Name,
			buttonName = ugc.ButtonName,
			initial   = ugc.InitialStock,
			internal  = CurrentStocks[key] or 0,
			liveRem   = l and l.rem or nil,
			proxyRawRem = l and l.rawRem or nil,
			purchasePending = pendingFor(key) ~= nil,
			liveTotal = l and l.total or nil,
			liveAt    = l and l.at or nil,
			liveFresh = liveIsFresh(l),
			shown     = cur,
			shownTotal = tot,
			source    = src,
		})
	end

	return {
		ok  = true,
		cfg = {
			mode        = StockCfg.mode,
			proxyHost   = StockCfg.proxyHost,
			pollSeconds = StockCfg.pollSeconds,
			mirror      = StockCfg.mirror,
		},
		state = {
			lastTry   = LiveState.lastTry,
			lastOk    = LiveState.lastOk,
			ok        = LiveState.ok,
			err       = LiveState.err,
			okCount   = LiveState.okCount,
			failCount = LiveState.failCount,
			lastMs    = LiveState.lastMs,
			fetching  = LiveState.fetching,
			staleAfter = StockCfg.pollSeconds * STALE_FACTOR,
		},
		items = items,
	}
end

modeFn.OnServerInvoke = function(player, raw)
	if not stockAdmin(player) then return denied(player) end
	if type(raw) ~= "table" then return { ok = false, msg = "payload invalide" } end

	local wasMode = StockCfg.mode
	local ok, msg = saveStockCfg(raw, player.Name)
	if not ok then return { ok = false, msg = msg } end

	-- On passe en live : on sonde tout de suite, sinon l'admin voit un écran
	-- vide pendant deux minutes et croit que ça ne marche pas.
	if StockCfg.mode == "live" and wasMode ~= "live" then
		task.spawn(function()
			fetchAll("bascule en live")
			pushStocks()
		end)
	else
		pushStocks()
	end

	return {
		ok = true,
		msg = msg,
		cfg = {
			mode        = StockCfg.mode,
			proxyHost   = StockCfg.proxyHost,
			pollSeconds = StockCfg.pollSeconds,
			mirror      = StockCfg.mirror,
		},
	}
end

stockActionFn.OnServerInvoke = function(player, action, payload)
	if not stockAdmin(player) then return denied(player) end
	payload = (type(payload) == "table") and payload or {}

	--── 🧪 Test de connexion : un seul item, message parlant ──
	if action == "test" then
		local first = UGC_CONFIG.Items[1]
		if not first then return { ok = false, msg = "Aucun UGC dans la config." } end

		local t0 = os.clock()
		if os.clock() >= EngineState.unsupportedUntil or os.clock() >= BatchState.unsupportedUntil then
			local viaEngine = os.clock() >= EngineState.unsupportedUntil
			local data, at, err
			if viaEngine then data, at, err = fetchEngine() else data, at, err = fetchBatch() end
			local ms = math.floor((os.clock() - t0) * 1000)
			if type(data) == "table" and at then
				local n = 0
				for _ in pairs(data) do n = n + 1 end
				local age = os.time() - at
				local fresh = age <= StockCfg.pollSeconds * STALE_FACTOR
				return {
					ok = fresh,
					msg = string.format("%s %s : %d UGC lus, il y a %d s (%d ms)%s",
						fresh and "✅" or "⚠️", viaEngine and "Lecture moteur Roblox (sans relais)" or "Lecture groupée",
						n, age, ms,
						err and (" — dernier souci : " .. tostring(err)) or ""),
				}
			end
			if os.clock() < BatchState.unsupportedUntil then
				-- relais sans POST : on teste l'ancienne lecture ci-dessous
			else
				return { ok = false, msg = string.format("❌ Échec en %d ms — %s", ms, tostring(err)) }
			end
		end
		local ok, rem, tot, msg = fetchOne(first.AssetId)
		local ms = math.floor((os.clock() - t0) * 1000)

		if ok then
			return {
				ok = true,
				msg = string.format("✅ Donnée disponible (cache ou HTTP) en %d ms — %s : %d/%s restant(s)",
					ms, first.Name, rem, tot and tostring(tot) or "?"),
			}
		end
		return {
			ok = false,
			msg = string.format("❌ Échec en %d ms — %s", ms, tostring(msg)),
		}
	end

	--── 🔄 Sondage immédiat ──
	if action == "refresh" then
		if StockCfg.mode ~= "live" then
			return { ok = false, msg = "Le mode live n'est pas actif." }
		end
		local okN, total, err = fetchAll("manuel")
		pushStocks()
		if okN == 0 then
			return { ok = false, msg = "❌ Aucun item lu — " .. tostring(err) }
		end
		return {
			ok = true,
			msg = string.format("✅ %d/%d item(s) mis à jour%s", okN, total,
				(okN < total) and (" — dernier souci : " .. tostring(err)) or ""),
		}
	end

	--── ✏️ Fixer un stock à la main (compteur maison) ──
	if action == "setstock" then
		local aid = tonumber(payload.assetId)
		local amt = tonumber(payload.amount)
		if not aid then return { ok = false, msg = "assetId manquant" } end
		if not amt or amt < 0 or math.floor(amt) ~= amt or amt > 1000000 then
			return { ok = false, msg = "Quantité invalide (entier entre 0 et 1 000 000)" }
		end

		local ok, msg = SetStock(aid, math.floor(amt))
		pushStocks()

		if ok and StockCfg.mode == "live" then
			msg = (msg or "") .. "  ⚠️ Tu es en mode 🌐 Stock Roblox : cette valeur "
				.. "ne s'affiche pas tant que l'API répond. Elle servira de repli."
		end
		return { ok = ok, msg = msg }
	end

	--── ♻️ Remettre un UGC à son stock de départ ──
	if action == "resetstock" then
		local aid = tonumber(payload.assetId)
		local ugc = aid and UGC_CONFIG.GetByAssetId(aid)
		if not ugc then return { ok = false, msg = "UGC introuvable" } end
		local ok, msg = SetStock(aid, ugc.InitialStock)
		pushStocks()
		return { ok = ok, msg = msg }
	end

	--── 🪞 Recopier tout le stock Roblox dans le compteur maison ──
	if action == "syncfromlive" then
		local n, skipped = 0, 0
		for _, ugc in ipairs(UGC_CONFIG.Items) do
			local key = tostring(ugc.AssetId)
			local l = Live[key]
			if l and l.rem ~= nil then
				CurrentStocks[key] = l.rem
				n = n + 1
			else
				skipped = skipped + 1
			end
			task.wait(0.05)
		end

		if n == 0 then
			return { ok = false, msg = "Aucune donnée live disponible — fais d'abord 🔄 Sonder." }
		end

		SaveStockData(false, true)
		pushStocks()
		return {
			ok = true,
			msg = string.format("✅ %d compteur(s) alignés sur Roblox%s", n,
				skipped > 0 and (" — " .. skipped .. " sans donnée live") or ""),
		}
	end

	return { ok = false, msg = "action inconnue : " .. tostring(action) }
end

--════════════════════════════════════════════════════════════
-- 🩺 AUTO-DIAGNOSTIC
--   Tape `_G.UGCStock_Diag()` dans la barre de commande de Studio (en mode
--   serveur) pour savoir en une seconde ce qui bloque.
--════════════════════════════════════════════════════════════
_G.UGCStock_Diag = function()
	-- ⚠️ Chaque ligne est protégée : sur un RemoteFunction, `OnServerInvoke` ne
	--    peut être QU'ÉCRIT, jamais lu — le lire coupait tout le diagnostic.
	local function line(k, fn)
		local ok, v = pcall(fn)
		print(string.format("%-28s: %s", k, ok and tostring(v) or ("⚠️ " .. tostring(v))))
	end

	print("──────── 🩺 DIAGNOSTIC SOURCE DU STOCK ────────")
	line("Bloc chargé",            function() return true end)
	line("Remote AdminGetStockPanel", function()
		return ReplicatedStorage:FindFirstChild("AdminGetStockPanel") ~= nil
	end)
	line("DataLoaded",             function() return DataLoaded end)
	line("Mode",                   function() return StockCfg.mode end)
	line("Relais",                 function()
		return StockCfg.proxyHost ~= "" and StockCfg.proxyHost or "(aucun)"
	end)
	line("UGC au catalogue",       function() return #UGC_CONFIG.Items end)
	line("HttpService autorisé", function() return HttpService.HttpEnabled end)
	line("Chargements proxy (ce serveur)", function() return ProxyCache.GetStats().loads end)
	line("Lectures cache (ce serveur)", function() return ProxyCache.GetStats().cacheHits end)
	line("Erreurs MemoryStore", function() return ProxyCache.GetStats().memoryErrors end)

	print("── Droits admin ──")
	local players = StockPlayers:GetPlayers()
	if #players == 0 then
		print("  (aucun joueur connecté — lance Play, pas Run)")
	end
	for _, pl in ipairs(players) do
		local ok, allowed = pcall(stockAdmin, pl)
		print(string.format("  %s (%d) → %s", pl.Name, pl.UserId,
			ok and (allowed and "✅ AUTORISÉ" or "⛔ REFUSÉ — ajoute cet ID dans PANEL_ADMIN_IDS")
				or ("⚠️ erreur : " .. tostring(allowed))))
	end

	print("── Simulation de l'appel du panel ──")
	for _, pl in ipairs(players) do
		local ok, res = pcall(function()
			if not stockAdmin(pl) then return denied(pl) end
			local items = {}
			for _, ugc in ipairs(UGC_CONFIG.Items) do
				local cur, tot, src = stockOf(ugc.AssetId)
				table.insert(items, { cur, tot, src })
			end
			return { ok = true, n = #items }
		end)
		if ok and type(res) == "table" and res.ok then
			print(string.format("  %s → ✅ le panel recevrait %d UGC", pl.Name, res.n))
		elseif ok then
			print(string.format("  %s → ⛔ %s", pl.Name,
				tostring(type(res) == "table" and res.msg or res)))
		else
			print(string.format("  %s → 💥 ERREUR SERVEUR : %s", pl.Name, tostring(res)))
		end
	end
	print("───────────────────────────────────────────────")
end

print("✅ [STOCK] Système de source du stock chargé (📦 Compteur maison ⇄ 🌐 Stock Roblox)")
print("   🩺 En cas de souci : tape  _G.UGCStock_Diag()  dans la barre de commande.")

-- ========================================
-- SAUVEGARDE AUTOMATIQUE (5 MINUTES)
-- ========================================
task.spawn(function()
	while true do
		task.wait(300)
		SaveStockData()
	end
end)

-- ========================================
-- SAUVEGARDE À LA FERMETURE
-- ========================================
game:BindToClose(function()
	print("🛑 [SERVEUR] FERMETURE - SAUVEGARDE FINALE DES STOCKS...")
	SaveStockData(true) -- skip broadcast à la fermeture
	task.wait(2)
end)