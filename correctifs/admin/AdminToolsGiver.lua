-- ============================================================
-- ADMIN TOOLS GIVER (Script serveur) — à mettre dans ServerScriptService
-- ============================================================
-- Avant : les LocalScripts admin étaient dans StarterPlayerScripts → TOUS les joueurs
-- téléchargeaient ~1,3 Mo de code admin (Admin client 857 Ko + WEAPON ANIM STUDIO 453 Ko…)
-- puis le script s'arrêtait tout seul ("if not isAdmin() then return end").
--
-- Maintenant : ces LocalScripts sont rangés dans ServerStorage ▸ AdminClientScripts
-- (ServerStorage n'est JAMAIS envoyé aux joueurs) et ce script les clone uniquement
-- dans le PlayerGui des admins. Les autres joueurs ne les reçoivent plus du tout.
--
-- INSTALLATION :
--   1. Crée un Folder "AdminClientScripts" dans ServerStorage
--   2. Glisse dedans (depuis StarterPlayer ▸ StarterPlayerScripts) :
--        • Admin client
--        • WEAPON ANIM STUDIO
--        • admin panel points
--   3. Mets ce Script dans ServerScriptService. C'est tout.
--   ⚠️ Ne mets PAS GiftingClient dedans : le gift est pour tout le monde.
-- ============================================================
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- Mêmes IDs que dans tes scripts admin actuels
local ADMIN_IDS = { 3203521470, 11017023724, 8456613930, 8142402169, 10420404767 }

-- Qui reçoit quel script (nom du LocalScript dans ServerStorage.AdminClientScripts).
-- Un script absent de cette liste est donné à tous les ADMIN_IDS.
local SCRIPT_RULES = {
	-- WEAPON ANIM STUDIO avait sa propre liste (4 IDs) + tout le monde en Studio
	["WEAPON ANIM STUDIO"] = {
		ids = { 3203521470, 11017023724, 8456613930, 8142402169 },
		everyoneInStudio = true,
	},
}

local folder = ServerStorage:WaitForChild("AdminClientScripts", 10)
if not folder then
	warn("[AdminTools] Crée le dossier ServerStorage ▸ AdminClientScripts et mets-y les LocalScripts admin")
	return
end

local function isInList(list, userId)
	for _, id in ipairs(list) do
		if id == userId then return true end
	end
	return false
end

local function canReceive(player, scriptName)
	local rule = SCRIPT_RULES[scriptName]
	if rule then
		if rule.everyoneInStudio and RunService:IsStudio() then return true end
		return isInList(rule.ids, player.UserId)
	end
	return isInList(ADMIN_IDS, player.UserId)
end

local function giveTools(player)
	local toGive = {}
	for _, s in ipairs(folder:GetChildren()) do
		if s:IsA("LocalScript") and canReceive(player, s.Name) then
			table.insert(toGive, s)
		end
	end
	if #toGive == 0 then return end -- joueur normal : il ne reçoit rien

	local playerGui = player:WaitForChild("PlayerGui", 30)
	if not playerGui or not player.Parent then return end
	if playerGui:FindFirstChild("AdminTools") then return end

	-- ScreenGui conteneur avec ResetOnSpawn = false : les scripts ne redémarrent pas à chaque mort
	-- (même comportement qu'avant dans StarterPlayerScripts)
	local holder = Instance.new("ScreenGui")
	holder.Name = "AdminTools"
	holder.ResetOnSpawn = false
	for _, s in ipairs(toGive) do
		local copy = s:Clone()
		copy.Enabled = true
		copy.Parent = holder
	end
	holder.Parent = playerGui
end

Players.PlayerAdded:Connect(giveTools)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(giveTools, player)
end
