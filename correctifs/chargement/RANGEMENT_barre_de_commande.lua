-- ============================================================
-- RANGEMENT AUTOMATIQUE POUR UN CHARGEMENT PLUS LÉGER
-- ============================================================
-- À COLLER DANS LA BARRE DE COMMANDE DE STUDIO (Affichage ▸ Barre de commande), puis Entrée.
-- Fais une copie de ton jeu avant. Tout est annulable avec Ctrl+Z.
--
-- Ce que ça fait (rien n'est supprimé, tout est DÉPLACÉ dans ServerStorage) :
--   1. Déplace 20 LocalScripts lourds mais pas urgents de StarterPlayerScripts vers
--      ServerStorage ▸ LateClientScripts (envoyés APRÈS le chargement par LateClientScripts).
--   2. Déplace le code mort qui était quand même téléchargé par chaque joueur vers
--      ServerStorage ▸ RangementBackup :
--        • StarterGui ▸ Shopold (ancienne boutique, 228 objets, plus utilisée nulle part)
--        • ReplicatedStorage ▸ WeaponSystem ▸ WeaponController_OLD (298 Ko, plus utilisé)
--        • les scripts DÉSACTIVÉS côté joueur (environ 600 Ko : GIFT local, ROOKIE GUIDE…)
--          SAUF ceux dont le nom apparaît dans un autre script (ils peuvent être réactivés
--          par du code : on ne les touche pas).
-- Relancer le script ne refait rien deux fois.
-- ============================================================
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local recording
pcall(function() recording = ChangeHistoryService:TryBeginRecording("Rangement chargement") end)

local function folderIn(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end
local lateFolder = folderIn(ServerStorage, "LateClientScripts")
local backup = folderIn(ServerStorage, "RangementBackup")

local function norm(name) return (name:lower():gsub("%s+", "")) end

local function moveTo(obj, dest)
	obj:SetAttribute("OriginalPath", obj:GetFullName())
	obj.Parent = dest
	print("[Rangement] " .. obj:GetAttribute("OriginalPath") .. "  →  " .. dest:GetFullName())
end

-- 1) Scripts envoyés après le chargement --------------------------------------------
local LATE = {
	"NpcDialog_Client", "HalloweenEvent_Client", "HalloweenGhosts", "BAT FLY animation",
	"DeathCam", "headbillboardclient (leaderboards", "PointsBillboardClient",
	"ADMIN ABUSE — CLIENT", "ADMIN ABUSE — DÉGRADÉ SUR LE BOOST DU BILLBOARD",
	"PVPmapvoting", "Gestion 2 frame  + affichage donation board", "UGCLiveFeedClient",
	"1v1 cross server local", "1v1 Display client", "ArenaHUD", "arena highlights",
	"animation points", "JackScythe_Client", "leave popup", "UGCRestrictNotify",
}
local lateSet = {}
for _, n in ipairs(LATE) do lateSet[norm(n)] = true end
local playerScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
local movedLate = 0
if playerScripts then
	for _, s in ipairs(playerScripts:GetChildren()) do
		if s:IsA("LocalScript") and lateSet[norm(s.Name)] then
			moveTo(s, lateFolder)
			movedLate += 1
		end
	end
end

-- 2) Code mort --------------------------------------------------------------------
local movedDead = 0
local shopold = StarterGui:FindFirstChild("Shopold")
if shopold then moveTo(shopold, backup); movedDead += 1 end
local ws = ReplicatedStorage:FindFirstChild("WeaponSystem")
local old = ws and ws:FindFirstChild("WeaponController_OLD")
if old then moveTo(old, backup); movedDead += 1 end

-- Tout le code du jeu, pour savoir si un script désactivé est cité ailleurs
local sources = {}
for _, d in ipairs(game:GetDescendants()) do
	local ok, isScript = pcall(function() return d:IsA("LuaSourceContainer") end)
	if ok and isScript and not d:IsDescendantOf(backup) then
		local okSrc, src = pcall(function() return d.Source end)
		if okSrc and src then table.insert(sources, { d, src }) end
	end
end
local function citedElsewhere(s)
	for _, entry in ipairs(sources) do
		if entry[1] ~= s and entry[2]:find(s.Name, 1, true) then return true end
	end
	return false
end

local clientRoots = { StarterGui, StarterPlayer, ReplicatedStorage, ReplicatedFirst }
local kept = {}
for _, root in ipairs(clientRoots) do
	for _, s in ipairs(root:GetDescendants()) do
		if (s:IsA("LocalScript") or (s:IsA("Script") and s.RunContext == Enum.RunContext.Client))
			and not s.Enabled and s.Parent then
			if citedElsewhere(s) then
				table.insert(kept, s:GetFullName())
			else
				moveTo(s, backup)
				movedDead += 1
			end
		end
	end
end

if recording then
	pcall(function() ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end)
end
print(("[Rangement] Terminé : %d scripts → LateClientScripts, %d éléments morts → RangementBackup"):format(movedLate, movedDead))
if #kept > 0 then
	print("[Rangement] Scripts désactivés GARDÉS (leur nom est cité dans un autre script) :")
	for _, p in ipairs(kept) do print("   " .. p) end
end
