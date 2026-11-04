--════════════════════════════════════════════════════════════════════════════
-- 🎟️ GamepassTools — TOUS les outils de gamepass, dans UN seul script
--
--  📍 ServerScriptService ▸ GamepassTools (Script)
--
--  Remplace ces 7 scripts (à DÉSACTIVER, coche « Disabled ») :
--    Coil pack give · Gravity coil give · speed coil give · Fusion coil give
--    Jetpack Give · Slap Hand Give · slap hand vip give
--
--  Pourquoi : ces 7 scripts se marchaient dessus.
--    • Quand un admin RETIRAIT le VIP, « slap hand vip give » retirait aussi la
--      Slap Hand d'un joueur qui avait ACHETÉ le gamepass Slap Hand, et
--      « Gravity / speed coil give » retiraient le coil d'un joueur qui avait
--      le Coil Pack.
--    • Ils ne regardaient pas l'outil EN MAIN : un coil tenu pouvait être donné
--      une deuxième fois.
--    • 5 s après chaque réapparition, ils redonnaient les outils même en pleine
--      arène PvP (maintenant : jamais en arène, l'arène les rend à la sortie).
--  Ici, un outil n'est retiré que si le joueur n'y a plus droit par AUCUNE source.
--════════════════════════════════════════════════════════════════════════════
local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage      = game:GetService("ServerStorage")

-- ⚙️ RÉGLAGES : outil → gamepass qui le donnent ("VIP" = VIP acheté OU offert)
local VIP_PASS = 1891589121
local TOOLS = {
	["Gravity Coil"] = { 1894006285, 1890875059, "VIP" },   -- Coil Pack, Gravity Coil, VIP
	["SpeedCoil"]    = { 1894006285, 1890659135, "VIP" },   -- Coil Pack, Speed Coil, VIP
	["FusionCoil"]   = { 1889975133 },                      -- Fusion Coil
	["Jetpack"]      = { 1890143127 },                      -- Jetpack
	["Slap Hand"]    = { 1889735131, "VIP" },               -- Slap Hand, VIP
}
local RESPAWN_DELAY = 3   -- s après la réapparition (laisse Roblox recopier StarterGear)

-- 💾 cache des gamepass (5 min)
local passCache = {}
local function owns(player, passId)
	local uid = player.UserId
	local c = passCache[uid]
	if not c or os.clock() - c.t > 300 then c = { t = os.clock() } passCache[uid] = c end
	if c[passId] == nil then
		local ok, r = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(uid, passId) end)
		if not ok then return nil end   -- lecture ratée : on ne décide rien
		c[passId] = r == true
	end
	return c[passId]
end

--  true = a droit · false = n'a pas droit · nil = impossible de vérifier
local function eligible(player, sources)
	local unknown = false
	for _, src in ipairs(sources) do
		if src == "VIP" then
			if _G.IsVIP and _G.IsVIP(player.UserId) then return true end
			local o = owns(player, VIP_PASS)
			if o == true then return true elseif o == nil then unknown = true end
		else
			local o = owns(player, src)
			if o == true then return true elseif o == nil then unknown = true end
		end
	end
	if unknown then return nil end
	return false
end

local function inArena(player)
	if player:GetAttribute("InArena") == true then return true end
	local pa = _G.PlayersInArena
	return type(pa) == "table" and pa[player.UserId] ~= nil and pa[player.UserId] ~= false
end

local function holders(player, withGear)
	local out = { player:FindFirstChildOfClass("Backpack"), player.Character }
	if withGear then table.insert(out, player:FindFirstChild("StarterGear")) end
	return out
end
local function has(container, name)
	if not container then return false end
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("Tool") and c.Name == name then return true end
	end
	return false
end

local function giveOne(player, name)
	local tpl = ServerStorage:FindFirstChild(name)
	if not (tpl and tpl:IsA("Tool")) then warn("⚠️ [GamepassTools] Outil introuvable dans ServerStorage : " .. name) return end
	--  StarterGear : revient à chaque réapparition
	local sg = player:FindFirstChild("StarterGear")
	if sg and not has(sg, name) then tpl:Clone().Parent = sg end
	--  Sac : tout de suite (sauf s'il l'a déjà dans le sac OU en main, ou s'il est en arène)
	if inArena(player) then return end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp and not has(bp, name) and not has(player.Character, name) then tpl:Clone().Parent = bp end
end

local function removeOne(player, name)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and has(char, name) then pcall(function() hum:UnequipTools() end) end   -- l'effet du coil s'arrête
	for _, h in ipairs(holders(player, true)) do
		if h then
			for _, c in ipairs(h:GetChildren()) do
				--  on ne touche pas aux copies prêtées par un admin ou un événement
				if c:IsA("Tool") and c.Name == name and c:GetAttribute("AdminLoanId") == nil
					and c:GetAttribute("AAEventTool") == nil then
					c:Destroy()
				end
			end
		end
	end
end

local busy = {}
local function sync(player, allowRemove)
	if busy[player] then return end
	busy[player] = true
	for name, sources in pairs(TOOLS) do
		local e = eligible(player, sources)
		if e == true then
			giveOne(player, name)
		elseif e == false and allowRemove then
			removeOne(player, name)
		end
	end
	busy[player] = nil
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(RESPAWN_DELAY)
		if player.Parent then sync(player, false) end
	end)
	if player.Character then task.delay(RESPAWN_DELAY, function() if player.Parent then sync(player, false) end end) end
end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(sync, p, false) end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	if not bought then return end
	local c = passCache[player.UserId]
	if c then c[passId] = true end
	sync(player, false)
end)

--  👑 VIP donné / retiré par un admin : on donne, ou on retire SEULEMENT ce à
--     quoi il n'a plus droit par aucune autre source (son Coil Pack reste).
task.spawn(function()
	local ev = ServerStorage:WaitForChild("VIPStatusChanged", 60)
	if not ev then return end
	ev.Event:Connect(function(userId)
		local p = Players:GetPlayerByUserId(userId)
		if not p then return end
		local c = passCache[userId]
		if c then c[VIP_PASS] = nil end
		sync(p, true)
	end)
end)

Players.PlayerRemoving:Connect(function(p)
	passCache[p.UserId] = nil
	busy[p] = nil
end)

print("✅ GamepassTools chargé (outils de gamepass, un seul script)")
