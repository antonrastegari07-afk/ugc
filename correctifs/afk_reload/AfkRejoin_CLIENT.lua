--════════════════════════════════════════════════════════════════════════════
-- 💤 Afk rejoin — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (v2, remplace tout)
--
--  Roblox déconnecte un joueur inactif après 20 min. Ce script le recharge AVANT :
--   • l'inactivité est mesurée comme Roblox la mesure (signal Player.Idled), avec en
--     secours nos propres entrées (clavier, souris qui bouge, manette, tactile, déplacement) ;
--   • à 14 min d'inactivité, on demande au serveur de sauvegarder puis de recharger le joueur ;
--   • si le serveur refuse (achat en cours, sauvegarde pas prête…), on RÉESSAIE toutes les 65 s
--     (avant : on attendait 15 min de plus → le joueur était déconnecté à 20 min) ;
--   • c'est le SERVEUR qui fait la téléportation, avec plusieurs essais.
--  Rien en Studio (la téléportation n'y marche pas).
--════════════════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if RunService:IsStudio() then return end

local player = Players.LocalPlayer

-- ⚙️ RÉGLAGES
local RELOAD_AT   = 840     -- s d'inactivité avant le rechargement (Roblox déconnecte à 1200)
local RETRY_EVERY = 65      -- s entre deux demandes si le serveur refuse (son anti-spam = 60 s)
local ACK_TIMEOUT = 25      -- s max pour la réponse du serveur

local notifyReloadEvent = ReplicatedStorage:WaitForChild("NotifyReload", 30)
local reloadConfirmedEvent = ReplicatedStorage:WaitForChild("ReloadConfirmed", 30)
if not notifyReloadEvent or not reloadConfirmedEvent then
	warn("❌ [AFK] NotifyReload / ReloadConfirmed introuvables")
	return
end

-- 🕒 inactivité
local lastInput = os.clock()
local robloxIdleSince = nil         -- début de l'inactivité selon Roblox (signal Idled)
local function active()
	lastInput = os.clock()
	robloxIdleSince = nil
end
UserInputService.InputBegan:Connect(active)
UserInputService.InputChanged:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseWheel
		or t == Enum.UserInputType.Touch or t.Name:find("Gamepad") then
		active()
	end
end)
player.Idled:Connect(function(seconds)
	-- Roblox nous dit depuis combien de temps il considère le joueur inactif
	robloxIdleSince = os.clock() - (tonumber(seconds) or 0)
end)
RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.MoveDirection.Magnitude > 0 then lastInput = os.clock() end
end)

local function idleTime()
	-- on prend la mesure de Roblox si elle existe (c'est elle qui décide de la déconnexion)
	local since = robloxIdleSince or lastInput
	return os.clock() - since
end

-- 📨 demande au serveur
local answer = nil
reloadConfirmedEvent.OnClientEvent:Connect(function(ok) answer = ok end)

local waitingTeleport = false
local nextTry = 0

local function tryReload()
	answer = nil
	local sent = pcall(function() notifyReloadEvent:FireServer("afk_reload") end)
	if not sent then return false end
	local t0 = os.clock()
	while answer == nil and os.clock() - t0 < ACK_TIMEOUT do task.wait(0.1) end
	return answer == true
end

while true do
	task.wait(5)
	if not waitingTeleport and idleTime() >= RELOAD_AT and os.clock() >= nextTry then
		if tryReload() then
			-- le serveur a sauvegardé et téléporte le joueur ; on ne redemande plus
			waitingTeleport = true
		else
			warn("💤 [AFK] Rechargement refusé ou sans réponse, nouvel essai dans " .. RETRY_EVERY .. " s")
			nextTry = os.clock() + RETRY_EVERY
		end
	end
end
