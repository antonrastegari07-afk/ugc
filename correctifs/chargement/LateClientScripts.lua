-- ============================================================
-- LATE CLIENT SCRIPTS (Script serveur) — à mettre dans ServerScriptService
-- ============================================================
-- Chargement en 2 temps :
--   1. Au démarrage, le joueur ne reçoit que l'essentiel → l'écran de chargement finit plus vite
--      et le pic de mémoire / CPU est beaucoup plus bas (iPad, téléphones).
--   2. Dès que l'écran de chargement est terminé (le loader envoie LoaderFocusDone),
--      le serveur envoie les LocalScripts "lourds mais pas urgents" un par un.
--
-- Les LocalScripts rangés dans ServerStorage ▸ LateClientScripts ne sont PAS téléchargés au
-- démarrage (ServerStorage n'est jamais envoyé aux joueurs). Ils sont clonés dans le PlayerGui
-- du joueur (dans un ScreenGui "LateClientScripts", ResetOnSpawn = false) : ils tournent
-- exactement comme dans StarterPlayerScripts (une seule fois, pas relancés à chaque mort).
--
-- Les RemoteEvents envoyés par le serveur AVANT qu'un script soit arrivé ne sont pas perdus :
-- Roblox les garde en file d'attente jusqu'à ce qu'un script s'y connecte.
--
-- INSTALLATION :
--   1. Crée un Folder "LateClientScripts" dans ServerStorage.
--   2. Glisse dedans (depuis StarterPlayer ▸ StarterPlayerScripts) les scripts de la liste du
--      LISEZMOI (NpcDialog_Client, HalloweenEvent_Client, DeathCam, ...).
--   3. Mets ce Script dans ServerScriptService.
--   Ordre d'envoi : attribut numérique "Order" sur un LocalScript (plus petit = plus tôt),
--   sinon ordre alphabétique.
-- ============================================================
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DELAY_BETWEEN = 0.25   -- secondes entre deux scripts (étale le travail du client)
local FALLBACK_AFTER = 60    -- si le loader ne prévient jamais : envoi quand même après 60 s

local folder = ServerStorage:WaitForChild("LateClientScripts", 10)
if not folder then
	warn("[LateClientScripts] Crée le dossier ServerStorage ▸ LateClientScripts")
	return
end

local doneEvent = ReplicatedStorage:FindFirstChild("LoaderFocusDone")
if not doneEvent then
	doneEvent = Instance.new("RemoteEvent")
	doneEvent.Name = "LoaderFocusDone"
	doneEvent.Parent = ReplicatedStorage
end

local function orderedScripts()
	local list = {}
	for _, s in ipairs(folder:GetDescendants()) do
		if s:IsA("LocalScript") then table.insert(list, s) end
	end
	table.sort(list, function(a, b)
		local oa, ob = a:GetAttribute("Order"), b:GetAttribute("Order")
		if type(oa) == "number" and type(ob) == "number" and oa ~= ob then return oa < ob end
		if type(oa) == "number" ~= (type(ob) == "number") then return type(oa) == "number" end
		return a.Name < b.Name
	end)
	return list
end

local given = {} -- [player] = true

local function give(player)
	if given[player] or not player.Parent then return end
	given[player] = true
	local playerGui = player:WaitForChild("PlayerGui", 30)
	if not playerGui or not player.Parent then return end
	if playerGui:FindFirstChild("LateClientScripts") then return end

	local holder = Instance.new("ScreenGui")
	holder.Name = "LateClientScripts"
	holder.ResetOnSpawn = false
	holder.Parent = playerGui

	for _, s in ipairs(orderedScripts()) do
		if not player.Parent or not holder.Parent then return end
		local copy = s:Clone()
		copy.Enabled = true
		copy.Parent = holder
		task.wait(DELAY_BETWEEN)
	end
end

-- Le loader prévient à la toute fin (écran déjà révélé). Une seule fois par joueur.
doneEvent.OnServerEvent:Connect(function(player)
	task.spawn(give, player)
end)

local function onPlayer(player)
	task.delay(FALLBACK_AFTER, function()
		if player.Parent then give(player) end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerRemoving:Connect(function(player) given[player] = nil end)
