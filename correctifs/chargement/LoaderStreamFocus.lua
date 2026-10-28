-- LoaderStreamFocus (Script serveur) — ServerScriptService. REMPLACE l'ancien LoaderStreamFocus.
-- Garde le décor autour de la CameraPart chargé pendant l'écran de chargement.
-- NOUVEAU : le focus n'est ajouté QUE si le client le demande (LoaderWantFocus).
--   • PC / console : le loader le demande → vue de l'île comme avant.
--   • Téléphone / tablette (mode léger du loader) : pas de demande → le serveur ne charge
--     PAS cette 2e zone en plus du spawn → moins de mémoire pendant le chargement.
-- Le focus est retiré quand le loader a fini (LoaderFocusDone), ou au bout de 120 s au pire.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FALLBACK_TIMEOUT = 120 -- sécurité si le client ne prévient jamais

local function remote(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = ReplicatedStorage
	end
	return ev
end
local wantEvent = remote("LoaderWantFocus")
local doneEvent = remote("LoaderFocusDone")

local camModel = workspace:WaitForChild("CameraPartModel", 30)
local camPart = camModel and camModel:WaitForChild("CameraPart", 10)
if not (camPart and camPart:IsA("BasePart")) then
	warn("[LoaderFocus] CameraPart introuvable — focus désactivé")
	return
end

local focused  = {} -- [player] = true tant que le focus est actif
local finished = {} -- [player] = true si le loader a déjà fini (ou focus déjà demandé une fois)
local asked    = {} -- [player] = true : une seule demande acceptée par joueur

local function removeFocus(player)
	if not focused[player] then return end
	focused[player] = nil
	pcall(function() player:RemoveReplicationFocus(camPart) end)
end

local function addFocus(player)
	if focused[player] or finished[player] or asked[player] then return end -- jamais empilé
	asked[player] = true
	local ok, err = pcall(function() player:AddReplicationFocus(camPart) end)
	if not ok then
		warn("[LoaderFocus] AddReplicationFocus a échoué : " .. tostring(err))
		return
	end
	focused[player] = true
	task.delay(FALLBACK_TIMEOUT, function() removeFocus(player) end)
end

-- Le client peut demander le focus UNE fois, et seulement avant la fin de son loader.
wantEvent.OnServerEvent:Connect(addFocus)
doneEvent.OnServerEvent:Connect(function(player)
	finished[player] = true
	removeFocus(player)
end)

Players.PlayerRemoving:Connect(function(player)
	removeFocus(player)
	focused[player], finished[player], asked[player] = nil, nil, nil
end)
