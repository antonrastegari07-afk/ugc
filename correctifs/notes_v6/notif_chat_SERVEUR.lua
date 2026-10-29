-- ========================================
-- CHAT NOTIF SERVER
-- Script (serveur) → ServerScriptService
-- ========================================
-- Gère les notifications dans le chat pour :
--   ✅ Les achats normaux de Developer Products (_G.NotifyPurchase)
--   ✅ Les gifts de POINTS entre joueurs          (_G.NotifyGift)
--   ✅ Les gifts d'OBJETS entre joueurs           (_G.NotifyGiftItem)  ⟵ NOUVEAU
--   ✅ Les UGC récupérés                          (_G.NotifyUGC)
--   ✅ Les donations                              (_G.NotifyDonation)
--
-- Communication cross-server via MessagingService pour les gros montants.
--
-- ⟦ v3 : ANNONCES FIABLES ⟧
--   • Une annonce globale s'affiche TOUT DE SUITE sur le serveur d'origine,
--     sans attendre le retour de MessagingService (avant : si ce retour se
--     perdait, même les joueurs du serveur ne voyaient rien — c'était le cas
--     des UGC, qui passaient UNIQUEMENT par MessagingService). Le retour
--     (écho) est ensuite ignoré : jamais affiché deux fois.
--   • PublishAsync réessaie 3 fois ; SubscribeAsync réessaie jusqu'à réussir
--     (avant : un échec au démarrage = ce serveur ne recevait plus AUCUNE
--     annonce globale jusqu'à sa fermeture).
--   • _G.NotifyUGC est appelé par le UGC REDEEM LOG pour TOUS les redeems
--     confirmés (achat direct, vérifié, tardif, au retour…), avec un
--     anti-doublon de 5 min par joueur + UGC.
--
-- ⟦ CE QUI A CHANGÉ ⟧
--   • Ajout de _G.NotifyGiftItem : VIP, boosts, armes et spins sont enfin
--     annoncés dans le chat. Ils passent par le MÊME topic que les gifts de
--     points (GlobalGiftNotif) — pas de second canal à maintenir, pas de
--     second abonnement, et les deux types d'annonces se ressemblent.
--   • Nettoyage : sendDonationToPlayers était défini deux fois à l'identique,
--     et le print final était dupliqué.
-- ========================================

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")

-- ========================================
-- CONFIG: ACHATS DEV PRODUCTS
-- ========================================
local PRODUCTS = {
	[3606598188] = { name = "1,000 Points",     points = 1000,    price = 2,   global = false },
	[3606598763] = { name = "2,500 Points",     points = 2500,    price = 4,   global = false },
	[3606598849] = { name = "100,000 Points",   points = 100000,  price = 29,  global = false },
	[3606598712] = { name = "500,000 Points",   points = 500000,  price = 149, global = true  },
	[3606598746] = { name = "2,000,000 Points", points = 2000000, price = 499, global = true  },
}

-- Seuil au-dessus duquel un gift de POINTS est annoncé en GLOBAL (cross-server)
local GIFT_GLOBAL_THRESHOLD = 500000

-- Seuil au-dessus duquel une donation est annoncée en GLOBAL (cross-server)
local DONATION_GLOBAL_THRESHOLD = 10   -- 🔧 en Robux

-- ========================================
-- REMOTE EVENT
-- ========================================
local chatNotifEvent = ReplicatedStorage:FindFirstChild("ChatNotifPurchase")
if not chatNotifEvent then
	chatNotifEvent = Instance.new("RemoteEvent")
	chatNotifEvent.Name = "ChatNotifPurchase"
	chatNotifEvent.Parent = ReplicatedStorage
end

-- Remote des donations (déjà écouté par ton LocalScript donation)
local chatNotifDonationEvent = ReplicatedStorage:FindFirstChild("ChatNotifDonation")
if not chatNotifDonationEvent then
	chatNotifDonationEvent = Instance.new("RemoteEvent")
	chatNotifDonationEvent.Name = "ChatNotifDonation"
	chatNotifDonationEvent.Parent = ReplicatedStorage
end

-- SÉCURITÉ : on ne connecte JAMAIS OnServerEvent (le client est lecture seule)

-- ========================================
-- HELPERS
-- ========================================
local function formatNumber(num)
	local formatted = tostring(num)
	while true do
		local newFormatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = newFormatted
		if k == 0 then break end
	end
	return formatted
end

--  Nettoie un morceau de texte avant de l'envoyer dans le chat.
--
--  Les libellés viennent de GIFT_CONFIG côté serveur et les pseudos de
--  Roblox : rien de tout ça n'est écrit par un joueur. Ce nettoyage n'est
--  donc pas une protection contre un exploit, c'est un garde-fou contre une
--  faute de frappe dans la config — un retour à la ligne ou un libellé de
--  200 caractères casserait l'affichage du chat pour tout le monde.
local function cleanText(s, maxLen, fallback)
	if type(s) ~= "string" then return fallback end
	s = s:gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if #s == 0 then return fallback end
	if #s > (maxLen or 48) then s = s:sub(1, maxLen or 48) end
	return s
end

local function sendMessageToPlayers(message, isGlobal)
	local prefix = isGlobal and "[GLOBAL]" or "[SERVER]"
	local fullMessage = prefix .. " " .. message

	for _, plr in ipairs(Players:GetPlayers()) do
		pcall(function()
			chatNotifEvent:FireClient(plr, fullMessage)
		end)
	end
end

-- Donations : le message arrive DÉJÀ complet, aucun préfixe ajouté
local function sendDonationToPlayers(fullMessage)
	for _, plr in ipairs(Players:GetPlayers()) do
		pcall(function()
			chatNotifDonationEvent:FireClient(plr, fullMessage)
		end)
	end
end

-- Envoi brut sur le chat "purchase" (pour les UGC, préfixe déjà inclus)
local function sendRawToPlayers(fullMessage)
	for _, plr in ipairs(Players:GetPlayers()) do
		pcall(function()
			chatNotifEvent:FireClient(plr, fullMessage)
		end)
	end
end

-- ========================================
-- GLOBAL FIABLE : affichage local immédiat + publication avec réessais
-- ========================================
local sentHere = {} -- [topic .. "|" .. message] = os.clock() : annonces déjà affichées ICI

local function isOwnEcho(topic, message)
	local k = topic .. "|" .. message
	local t = sentHere[k]
	if t and os.clock() - t < 120 then
		sentHere[k] = nil
		return true
	end
	return false
end

-- deliverLocal = la fonction qui affiche sur CE serveur (même rendu que l'écho)
local function publishGlobal(topic, message, deliverLocal)
	sentHere[topic .. "|" .. message] = os.clock()
	deliverLocal(message)
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				MessagingService:PublishAsync(topic, message)
			end)
			if ok then return end
			warn(string.format("[ChatNotif] PublishAsync %s échoué (%d/3) : %s", topic, attempt, tostring(err)))
			task.wait(2 * attempt)
		end
	end)
end

-- Ménage des échos jamais revenus
task.spawn(function()
	while true do
		task.wait(60)
		local now = os.clock()
		for k, t in pairs(sentHere) do
			if now - t > 120 then sentHere[k] = nil end
		end
	end
end)

-- ========================================
-- ABONNEMENTS CROSS-SERVER (réessaie jusqu'à réussir)
-- ========================================
local function subscribe(topic, handler)
	task.spawn(function()
		local attempt = 0
		while true do
			attempt += 1
			local ok, err = pcall(function()
				MessagingService:SubscribeAsync(topic, function(data)
					local msg = data and data.Data
					if type(msg) ~= "string" or isOwnEcho(topic, msg) then return end
					handler(msg)
				end)
			end)
			if ok then return end
			warn(string.format("[ChatNotif] SubscribeAsync %s échoué (essai %d) : %s", topic, attempt, tostring(err)))
			task.wait(math.min(60, 5 * attempt))
		end
	end)
end

local function sendGlobalToPlayers(message) sendMessageToPlayers(message, true) end

subscribe("GlobalPurchaseNotif", sendGlobalToPlayers)   -- achats globaux
subscribe("GlobalGiftNotif", sendGlobalToPlayers)       -- gifts globaux (points ET objets)
subscribe("GlobalUGCNotif", sendRawToPlayers)           -- UGC récupérés (toujours global)
subscribe("GlobalDonationNotif", sendDonationToPlayers) -- donations globales

-- ========================================
-- API : ACHAT
-- ========================================
_G.NotifyPurchase = function(userId, productName, points)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end

	local productData
	for _, data in pairs(PRODUCTS) do
		if data.name == productName then
			productData = data
			break
		end
	end
	if not productData then return end

	local pointsFmt = formatNumber(points)
	local priceFmt  = formatNumber(productData.price)

	local message = string.format(
		"%s bought %s Points for %s Robux!",
		player.Name,
		pointsFmt,
		priceFmt
	)

	if productData.global then
		publishGlobal("GlobalPurchaseNotif", message, sendGlobalToPlayers)
	else
		sendMessageToPlayers(message, false)
	end
end

-- ========================================
-- API : GIFT DE POINTS
-- ========================================
_G.NotifyGift = function(senderId, senderName, receiverId, receiverName, points)
	if type(points) ~= "number" or points <= 0 then return end

	senderName   = cleanText(senderName,   30, "Someone")
	receiverName = cleanText(receiverName, 30, "Someone")

	local pointsFmt = formatNumber(points)

	local message = string.format(
		"%s gifted %s Points to %s!",
		senderName,
		pointsFmt,
		receiverName
	)

	if points >= GIFT_GLOBAL_THRESHOLD then
		-- GLOBAL : tous les serveurs (affiché ici tout de suite, l'écho est ignoré)
		publishGlobal("GlobalGiftNotif", message, sendGlobalToPlayers)
	else
		-- SERVER : seulement ce serveur
		sendMessageToPlayers(message, false)
	end
end

-- ========================================
-- API : GIFT D'OBJET  (VIP, boosts, armes, spins)   ⟵ NOUVEAU
-- ========================================
--  Appelée par GiftingServer avec :
--     senderId, senderName, receiverId, receiverName, label, isGlobal
--
--  `label` est le nom lisible de ce qui a été offert, tel que le calcule
--  GIFT_CONFIG : « x10 Forever », « AK47 », « 3 Spins », « VIP »,
--  « x25 — 30 min »…
--
--  `isGlobal` n'est PAS décidé ici : GiftingServer le déduit du champ
--  `announce` de l'item (VIP et boosts permanents = "global", le reste =
--  "server"). Ce script se contente d'obéir. Si tu veux changer quel cadeau
--  est crié sur tous les serveurs, c'est dans GIFT_CONFIG que ça se règle,
--  à un seul endroit.
--
--  ⚠️ Fail-safe volontaire : un `isGlobal` absent ou bizarre est traité
--     comme "serveur uniquement". Une annonce ratée est un détail ; une
--     annonce globale envoyée par erreur spamme tous les serveurs du jeu.
-- ========================================
_G.NotifyGiftItem = function(senderId, senderName, receiverId, receiverName, label, isGlobal)
	label = cleanText(label, 48, nil)
	if not label then return end   -- rien à annoncer : on se tait

	senderName   = cleanText(senderName,   30, "Someone")
	receiverName = cleanText(receiverName, 30, "Someone")

	-- Auto-gift : on n'annonce pas « X gifted VIP to X », ça n'a aucun sens
	-- pour ceux qui lisent le chat.
	if senderId and receiverId and senderId == receiverId then return end

	local message = string.format(
		"%s gifted %s to %s!",
		senderName,
		label,
		receiverName
	)

	if isGlobal == true then
		publishGlobal("GlobalGiftNotif", message, sendGlobalToPlayers)
	else
		sendMessageToPlayers(message, false)
	end
end

-- ========================================
-- API : UGC RÉCUPÉRÉ (toujours GLOBAL)
-- ========================================
local ugcAnnounced = {} -- [userId|nom] = os.time() : anti-doublon (log + achat direct)
_G.NotifyUGC = function(userId, playerName, ugcName, price)
	ugcName = cleanText(ugcName, 48, "a UGC")
	local key = tostring(userId) .. "|" .. ugcName:lower()
	local now = os.time()
	if ugcAnnounced[key] and now - ugcAnnounced[key] < 300 then return end
	ugcAnnounced[key] = now

	local name = cleanText(playerName, 30, "Someone")
	local plr = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if plr then name = plr.Name end

	local message = string.format(
		"[UGC REDEEM] %s redeemed %s!",
		name,
		ugcName
	)

	publishGlobal("GlobalUGCNotif", message, sendRawToPlayers)
end

-- ========================================
-- API : DONATION
-- ========================================
_G.NotifyDonation = function(playerName, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return end

	local name = playerName or "Someone"

	if amount >= DONATION_GLOBAL_THRESHOLD then
		-- GLOBAL : tous les serveurs (affiché ici tout de suite, l'écho est ignoré)
		local message = string.format("[GLOBAL DONATION] %s donated %s R$! 💚",
			name, formatNumber(amount))
		publishGlobal("GlobalDonationNotif", message, sendDonationToPlayers)
	else
		-- SERVER : seulement ce serveur
		local message = string.format("[SERVER DONATION] %s donated %s R$! 💚",
			name, formatNumber(amount))
		sendDonationToPlayers(message)
	end
end

print("✅ CHAT NOTIF SERVER chargé (purchases + gifts points + gifts objets + UGC + donations)")