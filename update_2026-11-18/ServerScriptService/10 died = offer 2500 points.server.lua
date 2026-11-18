-- ════════════════════════════════════════════════════════════════════════
-- 💀 OFFRE APRÈS DES MORTS — Script dans ServerScriptService (remplace tout le script)
--
--  Réglages : ADMIN PANEL ▸ 🔔 POPUPS ▸ « 💀 Offre après des morts »
--    • Activé · petit pack toutes les X morts · gros pack toutes les Y morts
--    • compter (ou non) les morts en arène PvP
--  Défauts = comportement d'avant (10 morts → petit pack, 20 morts → gros pack).
--
--  🩹 Corrigé : avant, le script attendait 10 s AVANT d'écouter le personnage :
--     les morts de la toute première vie n'étaient jamais comptées.
--  🔔 Mode « seulement si inactif » : un joueur qui meurt n'est pas inactif,
--     donc pas d'offre de mort dans ce mode.
-- ════════════════════════════════════════════════════════════════════════
local MarketplaceService = require(game.ReplicatedStorage.MarketplaceServiceFX)
local Players = game:GetService("Players")

local PRODUCT_SMALL = 3606598763   -- petit pack (avant : « 5 morts »)
local PRODUCT_BIG   = 3606598188   -- gros pack  (avant : « 10 morts »)
local POPUP_ID = "death_offer"

local playerDeaths = {}

local function setting(key, default)
	local pc = _G.PopupControl
	if pc and pc.Get then
		local v = pc.Get(POPUP_ID, key)
		if v ~= nil then return v end
	end
	return default
end

local function offerAllowed()
	local pc = _G.PopupControl
	if not (pc and pc.IsOn) then return true end            -- système absent : comportement d'avant
	if not pc.IsOn(POPUP_ID) then return false end
	if pc.Get("_G", "IdleOnly") == true then return false end -- il meurt → il n'est pas inactif
	return true
end

local function inArena(player)
	return (_G.PlayersInArena and _G.PlayersInArena[player.UserId]) or player:GetAttribute("InArena") == true
end

local function onDied(player)
	if not player.Parent then return end
	if setting("CountArena", true) ~= true and inArena(player) then return end
	local deaths = (playerDeaths[player.UserId] or 0) + 1
	playerDeaths[player.UserId] = deaths

	local every = math.max(1, math.floor(tonumber(setting("EveryDeaths", 10)) or 10))
	local big   = math.max(1, math.floor(tonumber(setting("BigEveryDeaths", 20)) or 20))
	local productId
	if deaths % big == 0 then
		productId = PRODUCT_BIG
	elseif deaths % every == 0 then
		productId = PRODUCT_SMALL
	end
	if not productId or not offerAllowed() then return end

	task.wait(2)
	if not player.Parent then return end
	local es = _G.EngageStats
	if es and es.PopupShown then pcall(es.PopupShown, player, POPUP_ID) end
	pcall(function() MarketplaceService:PromptProductPurchase(player, productId) end)
end

local function onCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	humanoid.Died:Once(function() task.spawn(onDied, player) end)
end

local function onPlayer(player)
	playerDeaths[player.UserId] = 0
	player.CharacterAdded:Connect(function(c) onCharacter(player, c) end)
	if player.Character then task.spawn(onCharacter, player, player.Character) end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end

Players.PlayerRemoving:Connect(function(player)
	playerDeaths[player.UserId] = nil
end)
