--════════════════════════════════════════════════════════════════════════════
-- 🔔 PopupControl_Server — Script dans ServerScriptService   (NOUVEAU)
--
--  Garde les réglages des popups automatiques (admin panel ▸ 🔔 POPUPS) :
--   • lus au démarrage depuis le DataStore « PopupControl_v1 » (1 lecture / serveur) ;
--   • publiés en ATTRIBUTS sur ReplicatedStorage.PopupControl : Roblox les
--     réplique tout seul à tous les joueurs (aucun remote, aucune boucle) ;
--   • modifiés par un admin → écrits (1 UpdateAsync) puis envoyés aux autres
--     serveurs par MessagingService.
--
--  🔐 Sécurité : seul un admin peut écrire, chaque valeur est vérifiée et
--     bornée (PopupControlConfig.Sanitize), 1 modification / 0,25 s max.
--  API serveur : _G.PopupControl.Get(id, key) · _G.PopupControl.IsOn(id)
--════════════════════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local DSS              = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local RunService       = game:GetService("RunService")

local CFG = require(RS:WaitForChild("PopupControlConfig"))

local IS_STUDIO = RunService:IsStudio()
local STORE     = DSS:GetDataStore("PopupControl_v1")
local KEY       = "cfg"
local TOPIC     = "PopupControl_v1"

local ADMIN = {
	[3203521470] = true, [11017023724] = true, [8456613930] = true,
	[8142402169] = true, [10420404767] = true,
}
local function isAdmin(uid)
	if ADMIN[uid] then return true end
	local list = _G.AC_ADMIN_IDS
	if type(list) == "table" then
		for _, id in ipairs(list) do if id == uid then return true end end
	end
	return false
end

-- 📦 dossier répliqué (les clients lisent ses attributs)
local folder = RS:FindFirstChild("PopupControl")
if not folder then
	folder = Instance.new("Configuration")
	folder.Name = "PopupControl"
	folder.Parent = RS
end

-- valeurs actuelles : values[id][key]
local values = {}
local function eachField(fn)
	for _, f in ipairs(CFG.Global) do fn("_G", f) end
	for _, p in ipairs(CFG.Popups) do
		for _, f in ipairs(p.fields) do fn(p.id, f) end
	end
end
eachField(function(id, f)
	values[id] = values[id] or {}
	values[id][f.key] = f.default
end)

local function publishAll()
	eachField(function(id, f)
		local v = values[id][f.key]
		if folder:GetAttribute(CFG.Attr(id, f.key)) ~= v then
			folder:SetAttribute(CFG.Attr(id, f.key), v)
		end
	end)
end

-- applique une table sauvegardée { [id] = { [key] = v } } (valeurs re-vérifiées)
local function applyStored(stored)
	if type(stored) ~= "table" then return end
	eachField(function(id, f)
		local t = stored[id]
		if type(t) == "table" and t[f.key] ~= nil then
			local v = CFG.Sanitize(f, t[f.key])
			if v ~= nil then values[id][f.key] = v end
		end
	end)
	publishAll()
end

publishAll()   -- défauts tout de suite (les clients ne restent jamais sans valeur)

local loaded = false
task.spawn(function()
	for attempt = 1, 5 do
		local ok, data = pcall(function() return STORE:GetAsync(KEY) end)
		if ok then
			applyStored(data)
			loaded = true
			folder:SetAttribute("Loaded", true)
			return
		end
		task.wait(2 * attempt)
	end
	warn("🔔 [PopupControl] Réglages non lus : valeurs par défaut utilisées (réessai à la prochaine modification)")
end)

-- 🌍 autres serveurs : quand un admin change un réglage, on relit la valeur envoyée
task.spawn(function()
	if IS_STUDIO then return end
	for attempt = 1, 10 do
		local ok = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(msg)
				local d = type(msg) == "table" and msg.Data
				if type(d) ~= "table" or d.j == game.JobId then return end
				-- message minuscule (limite MessagingService 1 Ko) : on relit la sauvegarde
				task.delay(math.random() * 3, function()   -- étalé : pas tous les serveurs à la même seconde
					local ok, data = pcall(function() return STORE:GetAsync(KEY) end)
					if ok then applyStored(data) end
				end)
			end)
		end)
		if ok then return end
		task.wait(math.min(60, 5 * attempt))
	end
end)

--════════════════════════════════════════════════════════════
-- 🔌 API serveur
--════════════════════════════════════════════════════════════
local API = {}
function API.Get(id, key)
	local t = values[id]
	return t and t[key]
end
-- popup activé (interrupteur général compris pour les popups automatiques)
function API.IsOn(id)
	local p = CFG.ById[id]
	if not p or values[id].Enabled ~= true then return false end
	if p.kind ~= "action" and p.kind ~= "favorite" and values._G.Enabled ~= true then return false end
	return true
end
_G.PopupControl = API

--════════════════════════════════════════════════════════════
-- 🛠️ ADMIN PANEL
--════════════════════════════════════════════════════════════
local remote = RS:FindFirstChild("PopupControl_Admin")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "PopupControl_Admin"
	remote.Parent = RS
end

local lastCall = {}
local saveQueued = false
local function queueSave()
	if saveQueued or IS_STUDIO then return end
	saveQueued = true
	task.delay(2, function()   -- regroupe plusieurs clics en UNE écriture
		saveQueued = false
		local snapshot = table.clone(values)
		for id, t in pairs(snapshot) do snapshot[id] = table.clone(t) end
		local ok = false
		for attempt = 1, 3 do
			ok = pcall(function()
				STORE:UpdateAsync(KEY, function() return snapshot end)
			end)
			if ok then break end
			task.wait(attempt)
		end
		if not ok then warn("🔔 [PopupControl] Sauvegarde échouée") return end
		pcall(function() MessagingService:PublishAsync(TOPIC, { j = game.JobId }) end)
	end)
end

remote.OnServerInvoke = function(player, action, id, key, value)
	if not isAdmin(player.UserId) then return { ok = false, err = "non admin" } end
	local now = os.clock()
	if lastCall[player.UserId] and now - lastCall[player.UserId] < 0.25 then
		return { ok = false, err = "trop rapide" }
	end
	lastCall[player.UserId] = now

	if action == "get" then
		return { ok = true, values = values, loaded = loaded, studio = IS_STUDIO }
	elseif action == "set" then
		if type(id) ~= "string" or type(key) ~= "string" then return { ok = false, err = "requête invalide" } end
		local f = CFG.FindField(id, key)
		if not f then return { ok = false, err = "réglage inconnu" } end
		local v = CFG.Sanitize(f, value)
		if v == nil then return { ok = false, err = "valeur refusée" } end
		values[id][key] = v
		publishAll()
		queueSave()
		print(string.format("🔔 [PopupControl] %s : %s.%s = %s", player.Name, id, key, tostring(v)))
		return { ok = true, value = v }
	elseif action == "reset" then
		eachField(function(pid, f) values[pid][f.key] = f.default end)
		publishAll()
		queueSave()
		return { ok = true, values = values }
	end
	return { ok = false, err = "action inconnue" }
end

Players.PlayerRemoving:Connect(function(p) lastCall[p.UserId] = nil end)

print("✅ PopupControl chargé")
