--════════════════════════════════════════════════════════════════════════════
-- 🧰 SessionToolCarry — Script dans ServerScriptService   (NOUVEAU)
--
--  RESET SERVEUR (mise à jour, « Shut down servers », crash du serveur) :
--  les joueurs gardent les outils qu'ils avaient, AVEC leur type :
--    • « session » (gardé à la mort : Daily, Fusion Coil du popup de départ, coils…)
--      → revient dans StarterGear + sac
--    • « simple » (dans le sac seulement, perdu à la mort) → revient dans le sac
--    • « prêt admin » (5 min → 1 h) → revient avec la MÊME heure de fin, puis retiré
--  Les outils permanents (gamepass, sauvegardés, Scythe…) sont redonnés par leurs propres
--  systèmes : on ne crée JAMAIS de doublon (un outil déjà présent n'est pas redonné).
--
--  🔒 Sécurité : la liste vient UNIQUEMENT du serveur (sac / StarterGear vus par le serveur),
--     jamais du client. Elle n'est utilisable qu'UNE fois, et seulement dans les
--     CARRY_WINDOW secondes après le reset (un départ normal ne garde rien).
--  💾 Coût : 1 écriture par joueur au reset, 1 lecture + 1 suppression à l'arrivée.
--════════════════════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local ServerStorage    = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService       = game:GetService("RunService")

-- ⚙️ RÉGLAGES
local CARRY_WINDOW   = 900    -- s : le joueur doit revenir dans les 15 min après le reset
local RESTORE_DELAY  = 8      -- s après l'apparition : les autres systèmes donnent d'abord leurs outils
local SNAPSHOT_EVERY = 20     -- s : photo régulière des outils (filet si le joueur est retiré avant la fermeture)
-- outils jamais copiés :
--   JackScythe   → la faux a son propre système (numéro de série)
--   AAEventTool  → armes de l'event Admin Abuse : liées à l'event en cours sur CE serveur
local SKIP_ATTRIBUTES = { "JackScythe", "AAEventTool" }
-- dossiers de ServerStorage dont les outils ne sont jamais recopiés
local SKIP_FOLDERS = { AdminAbuseTools = true, JackScythe = true }

local STORE = DataStoreService:GetDataStore("SessionToolCarry_v1")
local READ_ONLY = RunService:IsStudio()

-- index des outils de ServerStorage (dossiers compris, pas les outils rangés dans un outil)
--   1) d'abord les outils posés directement dans ServerStorage (ex. « Jetpack » normal,
--      et pas celui de l'Admin Abuse qui porte le même nom), 2) puis ceux des dossiers.
local toolIndex, indexAt = {}, -math.huge
local function findTemplate(name)
	if os.clock() - indexAt > 30 then
		toolIndex, indexAt = {}, os.clock()
		for _, d in ipairs(ServerStorage:GetChildren()) do
			if d:IsA("Tool") and not toolIndex[d.Name] then toolIndex[d.Name] = d end
		end
		for _, d in ipairs(ServerStorage:GetDescendants()) do
			if d:IsA("Tool") and not toolIndex[d.Name] then
				local p, ok = d.Parent, true
				while p and p ~= ServerStorage do
					if p:IsA("Tool") or (p.Parent == ServerStorage and SKIP_FOLDERS[p.Name]) then ok = false break end
					p = p.Parent
				end
				if ok then toolIndex[d.Name] = d end
			end
		end
	end
	return toolIndex[name]
end

local function skipped(tool)
	for _, a in ipairs(SKIP_ATTRIBUTES) do
		if tool:GetAttribute(a) ~= nil then return true end
	end
	return false
end

-- 📸 photo des outils d'un joueur (côté serveur uniquement)
local function snapshot(player)
	local out, seen = {}, {}
	local function add(tool, kind)
		if not tool:IsA("Tool") or skipped(tool) then return end
		local key = kind .. "|" .. tool.Name
		if seen[key] then return end
		seen[key] = true
		local exp = tonumber(tool:GetAttribute("AdminLoanExpiresAt")) or tonumber(tool:GetAttribute("CarryExpiresAt"))
		table.insert(out, { n = tool.Name, k = kind, x = exp })
	end
	local gear = player:FindFirstChild("StarterGear")
	local gearNames = {}
	if gear then
		for _, t in ipairs(gear:GetChildren()) do
			if t:IsA("Tool") then gearNames[t.Name] = true add(t, "gear") end
		end
	end
	if player:GetAttribute("InArena") == true then
		-- en arène : le sac contient les armes PvP ; les outils de l'obby sont gardés par l'arène
		local saved = type(_G.GetArenaSavedTools) == "function" and _G.GetArenaSavedTools(player.UserId)
		for _, name in ipairs(type(saved) == "table" and saved or {}) do
			if type(name) == "string" and not gearNames[name] and not seen["bp|" .. name] then
				seen["bp|" .. name] = true
				table.insert(out, { n = name, k = "bp" })
			end
		end
	else
		for _, c in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
			if c then
				for _, t in ipairs(c:GetChildren()) do
					if t:IsA("Tool") and not gearNames[t.Name] then add(t, "bp") end
				end
			end
		end
	end
	-- pendant le tutoriel, ses outils sont mis de côté par le script du tutoriel
	local tuto = type(_G.GetTutorialSavedTools) == "function" and _G.GetTutorialSavedTools(player)
	for _, t in ipairs(type(tuto) == "table" and tuto or {}) do
		if typeof(t) == "Instance" and t:IsA("Tool") and not gearNames[t.Name] then add(t, "bp") end
	end
	return out
end

-- photos (en mémoire). Une nouvelle photo s'AJOUTE à l'ancienne : si un autre script a
-- déjà vidé le StarterGear pendant la fermeture, les outils de la photo précédente restent.
local last = {}     -- [userId] = { tools = {…}, t = os.time() }
local leftAt = {}   -- [userId] = os.clock() du départ
local function take(p)
	local ok, s = pcall(snapshot, p)
	if not ok then return end
	local old = last[p.UserId]
	if old and os.time() - old.t <= SNAPSHOT_EVERY * 2 then
		local seen = {}
		for _, e in ipairs(s) do seen[e.k .. "|" .. e.n] = true end
		for _, e in ipairs(old.tools) do
			if not seen[e.k .. "|" .. e.n] then table.insert(s, e) end
		end
	end
	-- un outil « session » (StarterGear) n'est pas aussi noté « sac » : il garderait le mauvais type
	local gearN = {}
	for _, e in ipairs(s) do if e.k == "gear" then gearN[e.n] = true end end
	local clean = {}
	for _, e in ipairs(s) do
		if e.k == "gear" or not gearN[e.n] then table.insert(clean, e) end
	end
	last[p.UserId] = { tools = clean, t = os.time() }
end
task.spawn(function()
	while true do
		task.wait(SNAPSHOT_EVERY)
		for _, p in ipairs(Players:GetPlayers()) do take(p) end
		-- départs normaux : leur photo est oubliée après 1 min (rien n'est gardé)
		for uid, t in pairs(leftAt) do
			if os.clock() - t > 60 then leftAt[uid], last[uid] = nil, nil end
		end
	end
end)
Players.PlayerRemoving:Connect(function(p)
	take(p)                       -- dernière photo avant le départ
	leftAt[p.UserId] = os.clock()
end)

-- 💾 RESET : on enregistre les outils de chaque joueur
game:BindToClose(function()
	if READ_ONLY then return end
	-- photo immédiate des joueurs encore là (aucune attente avant)
	for _, p in ipairs(Players:GetPlayers()) do take(p) end
	local pending = 0
	for uid, snap in pairs(last) do
		-- joueurs encore là, ou retirés par la fermeture elle-même (il y a moins de 15 s)
		local gone = leftAt[uid]
		if #snap.tools > 0 and (not gone or os.clock() - gone < 15) then
			pending += 1
			task.spawn(function()
				pcall(function()
					STORE:SetAsync("u_" .. uid, { t = os.time(), tools = snap.tools })
				end)
				pending -= 1
			end)
		end
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
end)

-- ♻️ ARRIVÉE : on rend les outils (une seule fois)
local function has(player, name)
	for _, c in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character, player:FindFirstChild("StarterGear") }) do
		if c then
			local t = c:FindFirstChild(name)
			if t and t:IsA("Tool") then return true end
		end
	end
	return false
end

local function scheduleExpiry(player, name, exp)
	task.delay(math.max(0, exp - os.time()), function()
		if not player.Parent then return end
		for _, c in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character, player:FindFirstChild("StarterGear") }) do
			if c then
				for _, t in ipairs(c:GetChildren()) do
					if t:IsA("Tool") and t.Name == name and t:GetAttribute("CarryExpiresAt") == exp then t:Destroy() end
				end
			end
		end
	end)
end

local function restore(player)
	if READ_ONLY then return end
	local uid = player.UserId
	local data
	for attempt = 1, 3 do
		local ok, v = pcall(function() return STORE:GetAsync("u_" .. uid) end)
		if ok then data = v break end
		task.wait(2 * attempt)
	end
	if type(data) ~= "table" or type(data.tools) ~= "table" then return end
	-- utilisable une seule fois
	pcall(function() STORE:RemoveAsync("u_" .. uid) end)
	if os.time() - (tonumber(data.t) or 0) > CARRY_WINDOW then return end

	-- attend que le joueur soit apparu (sans bloquer s'il repart)
	local t0 = os.clock()
	while player.Parent and not player.Character and os.clock() - t0 < 120 do task.wait(0.5) end
	task.wait(RESTORE_DELAY)
	-- pas d'outils de l'obby en pleine arène : on attend qu'il en sorte (10 min max)
	t0 = os.clock()
	while player.Parent and player:GetAttribute("InArena") == true and os.clock() - t0 < 600 do task.wait(2) end
	if not player.Parent or player:GetAttribute("InArena") == true then return end
	local gear = player:FindFirstChild("StarterGear")
	local bp = player:FindFirstChildOfClass("Backpack")
	local given = {}
	-- les outils « session » d'abord : c'est leur type qui compte si un nom apparaît 2 fois
	local ordered = {}
	for _, e in ipairs(data.tools) do if type(e) == "table" and e.k == "gear" then table.insert(ordered, e) end end
	for _, e in ipairs(data.tools) do if type(e) == "table" and e.k ~= "gear" then table.insert(ordered, e) end end
	for _, e in ipairs(ordered) do
		local name, kind, exp = e.n, e.k, tonumber(e.x)
		if type(name) == "string" and not given[name] and not (exp and exp <= os.time()) and not has(player, name) then
			local tpl = findTemplate(name)
			if tpl then
				given[name] = true
				local function copy()
					local c = tpl:Clone()
					if exp then
						c:SetAttribute("CarryExpiresAt", exp)
						pcall(function() c.CanBeDropped = false end)
					end
					return c
				end
				if kind == "gear" and gear then copy().Parent = gear end
				if bp then copy().Parent = bp end
				if exp then scheduleExpiry(player, name, exp) end
			end
		end
	end
	if next(given) then
		local names = {}
		for n in pairs(given) do table.insert(names, n) end
		print("🧰 SessionToolCarry : outils rendus à " .. player.Name .. " après le reset : " .. table.concat(names, ", "))
	end
end

Players.PlayerAdded:Connect(function(p) task.spawn(restore, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(restore, p) end

print("✅ SessionToolCarry chargé (outils gardés pendant un reset serveur)")
