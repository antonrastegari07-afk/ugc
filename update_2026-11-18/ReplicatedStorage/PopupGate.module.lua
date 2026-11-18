--════════════════════════════════════════════════════════════════════════════
-- 🚦 PopupGate — ModuleScript dans ReplicatedStorage   (NOUVEAU, côté CLIENT)
--
--  Chaque popup automatique lui demande la permission avant de s'afficher :
--    local Gate = require(ReplicatedStorage:WaitForChild("PopupGate"))
--    if Gate.WaitTurn("vip_offer") then ...afficher... ; Gate.Shown("vip_offer") end
--
--  Il applique les réglages de l'admin (ReplicatedStorage.PopupControl) :
--    • popup / interrupteur général activé ?
--    • mode « seulement si le joueur est inactif depuis X min »
--    • pause minimum entre deux popups automatiques
--  et compte l'affichage pour 📊 STATS (une seule fois par 20 s et par popup).
--
--  Perf : un seul module par joueur (require = mis en cache), 3 petites
--  connexions d'entrée qui ne font qu'écrire un nombre, aucune boucle permanente.
--════════════════════════════════════════════════════════════════════════════
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local CFG = require(ReplicatedStorage:WaitForChild("PopupControlConfig"))
local folder = ReplicatedStorage:WaitForChild("PopupControl", 30)

local Gate = {}

local lastInput = os.clock()
local lastAutoShown = -1e9
local lastReported = {}

-- 🕒 activité du joueur (clavier, souris, tactile, manette, déplacement)
UserInputService.InputBegan:Connect(function() lastInput = os.clock() end)
UserInputService.InputChanged:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch
		or t == Enum.UserInputType.MouseWheel or t.Name:find("Gamepad") then
		lastInput = os.clock()
	end
end)
UserInputService.TouchStarted:Connect(function() lastInput = os.clock() end)

function Gate.IdleSeconds() return os.clock() - lastInput end

-- valeur d'un réglage (défaut du module si l'attribut n'est pas encore arrivé)
function Gate.Get(id, key)
	if folder then
		local v = folder:GetAttribute(CFG.Attr(id, key))
		if v ~= nil then return v end
	end
	local f = CFG.FindField(id, key)
	return f and f.default
end

local function isAuto(p) return p.kind == "timer" or p.kind == "carousel" or p.kind == "deaths" end

-- activé ? (n'attend rien)
function Gate.Enabled(id)
	local p = CFG.ById[id]
	if not p or Gate.Get(id, "Enabled") ~= true then return false end
	if isAuto(p) and Gate.Get("_G", "Enabled") ~= true then return false end
	return true
end

-- autorisé MAINTENANT ? (activé + inactivité + pause mini)
function Gate.Allowed(id)
	if not Gate.Enabled(id) then return false end
	local p = CFG.ById[id]
	if not isAuto(p) then return true end
	if Gate.Get("_G", "IdleOnly") == true then
		local need = (tonumber(Gate.Get("_G", "IdleMinutes")) or 5) * 60
		if Gate.IdleSeconds() < need then return false end
	end
	if p.kind ~= "carousel" then   -- le carrousel défile en continu : pas concerné par la pause
		local gap = tonumber(Gate.Get("_G", "MinGapSeconds")) or 0
		if gap > 0 and os.clock() - lastAutoShown < gap then return false end
	end
	return true
end

-- Attend que le popup ait le droit de s'afficher.
-- Renvoie false tout de suite s'il est désactivé (ou s'il le devient pendant l'attente).
function Gate.WaitTurn(id)
	while true do
		if not Gate.Enabled(id) then return false end
		if Gate.Allowed(id) then return true end
		task.wait(2)
	end
end

-- Attente « minuteur » qui suit le réglage en direct : si l'admin change l'intervalle
-- pendant l'attente, on s'adapte sans attendre la fin de l'ancien délai.
function Gate.WaitMinutes(id, key)
	local t0 = os.clock()
	while true do
		local mins = tonumber(Gate.Get(id, key)) or 10
		if os.clock() - t0 >= mins * 60 then return end
		task.wait(5)
	end
end

-- Le popup vient de s'afficher : pause mini + stats
function Gate.Shown(id)
	local p = CFG.ById[id]
	if p and p.kind ~= "carousel" and isAuto(p) then lastAutoShown = os.clock() end
	local now = os.clock()
	if lastReported[id] and now - lastReported[id] < 20 then return end
	lastReported[id] = now
	local ev = ReplicatedStorage:FindFirstChild("EngageTrack")
	if ev and ev:IsA("RemoteEvent") then pcall(function() ev:FireServer("pop", id) end) end
end

return Gate
