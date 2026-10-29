-- ========================================
-- CHAT NOTIF CLIENT
-- LocalScript → StarterPlayerScripts
-- ========================================
-- Affiche les notifications de :
--   ✅ Achats normaux (couleurs selon montant)
--   ✅ Gifts (couleur gold dédiée, détection par mot-clé "gifted")
-- ========================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")
local TextChatService   = game:GetService("TextChatService")

local chatNotifEvent = ReplicatedStorage:WaitForChild("ChatNotifPurchase", 10)
if not chatNotifEvent then
	warn("❌ RemoteEvent 'ChatNotifPurchase' introuvable!")
	return
end

-- ========================================
-- COULEURS
-- ========================================
local GIFT_COLOR = Color3.fromRGB(240, 153, 215) -- gold pour gifts
local UGC_COLOR  = Color3.fromRGB(185, 120, 255) -- violet pour les UGC

local PURCHASE_COLORS = {
	["SERVER"] = {
		["1,000"]   = Color3.fromRGB(255, 255, 255),
		["2,500"]   = Color3.fromRGB(255, 255, 255),
		["100,000"] = Color3.fromRGB(122, 237, 246),
	},
	["GLOBAL"] = {
		["500,000"]   = Color3.fromRGB(255, 120, 120),
		["2,000,000"] = Color3.fromRGB(255, 215, 0),
	},
}

-- ========================================
-- DÉTECTION COULEUR
-- ========================================
local function getColorForMessage(message)
	-- ✅ UGC = violet (détection prioritaire)
	if string.find(message, "UGC REDEEM", 1, true) then
		return UGC_COLOR
	end

	-- ✅ Gift = couleur gold dédiée
	if string.find(message, "gifted", 1, true) then
		return GIFT_COLOR
	end

	-- Sinon, achat normal : détection par montant
	local isGlobal = string.find(message, "%[GLOBAL%]")
	local typeKey = isGlobal and "GLOBAL" or "SERVER"
	local colorTable = PURCHASE_COLORS[typeKey]

	for amount, color in pairs(colorTable) do
		if string.find(message, amount, 1, true) then
			return color
		end
	end

	return Color3.fromRGB(255, 255, 255)
end

-- ========================================
-- AFFICHAGE
-- ========================================
-- 🩹 Un nom d'UGC ou de joueur avec & < > " ' cassait le texte enrichi : le message
--    ne s'affichait pas. On les échappe avant de mettre la couleur.
local function escapeRich(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		:gsub("\"", "&quot;"):gsub("'", "&apos;"))
end

local function displayChatMessage(message)
	if type(message) ~= "string" then return end
	local color = getColorForMessage(message)

	-- Méthode 1: TextChatService (nouveau système)
	-- 🩹 10 s au lieu de 2 : juste après l'arrivée, le canal n'existe pas encore
	--    et l'annonce était perdue.
	local success = pcall(function()
		local textChannels = TextChatService:WaitForChild("TextChannels", 10)
		if not textChannels then error("no TextChannels") end

		local generalChannel = textChannels:WaitForChild("RBXGeneral", 10)
		if not generalChannel then error("no RBXGeneral") end

		local r = math.floor(color.R * 255)
		local g = math.floor(color.G * 255)
		local b = math.floor(color.B * 255)

		local formatted = string.format(
			"<font face='FredokaOne' color='rgb(%d,%d,%d)'>%s</font>",
			r, g, b, escapeRich(message)
		)
		generalChannel:DisplaySystemMessage(formatted)
	end)

	-- Méthode 2: ancien système (legacy chat)
	if not success then
		task.wait(1)
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text     = message,
				Color    = color,
				Font     = Enum.Font.FredokaOne,
				FontSize = Enum.FontSize.Size18,
			})
		end)
	end
end

-- ========================================
-- ÉCOUTE
-- ========================================
chatNotifEvent.OnClientEvent:Connect(function(message)
	task.spawn(displayChatMessage, message) -- chaque annonce indépendante (une attente ne bloque pas les autres)
end)

print("✅ CHAT NOTIF CLIENT chargé (purchases + gifts)")