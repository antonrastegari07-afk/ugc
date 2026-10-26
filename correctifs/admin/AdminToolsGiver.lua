-- ============================================================
-- ADMIN TOOLS GIVER (Script serveur) — à mettre dans ServerScriptService
-- ============================================================
-- Avant : les LocalScripts admin étaient dans StarterPlayerScripts → TOUS les joueurs
-- téléchargeaient ~1,3 Mo de code admin (Admin client 857 Ko + WEAPON ANIM STUDIO 453 Ko…)
-- puis le script s'arrêtait tout seul ("if not isAdmin() then return end").
--
-- Maintenant : ces LocalScripts sont rangés dans ServerStorage (jamais envoyé aux joueurs)
-- et ce script les clone uniquement dans le PlayerGui des admins.
--
-- INSTALLATION :
--   1. Glisse dans ServerStorage (directement, ou dans n'importe quel dossier de ServerStorage) :
--        • Admin client
--        • WEAPON ANIM STUDIO
--        • admin panel points
--      (ils doivent ne PLUS être dans StarterPlayerScripts)
--   2. Mets ce Script dans ServerScriptService. C'est tout.
--   Le script retrouve les LocalScripts par leur NOM, peu importe le dossier.
--   Regarde l'Output au lancement : il écrit ce qu'il a trouvé et à qui il le donne.
--   ⚠️ Ne mets PAS GiftingClient : le gift est pour tout le monde.
-- ============================================================
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

-- Mêmes IDs que dans tes scripts admin actuels
local ADMIN_IDS = { 3203521470, 11017023724, 8456613930, 8142402169, 10420404767 }

-- Les LocalScripts à donner aux admins (noms tels qu'ils sont dans l'Explorer)
local ADMIN_SCRIPTS = {
	["Admin client"] = { ids = ADMIN_IDS },
	["admin panel points"] = { ids = ADMIN_IDS },
	-- WEAPON ANIM STUDIO avait sa propre liste (4 IDs) + tout le monde en Studio
	["WEAPON ANIM STUDIO"] = {
		ids = { 3203521470, 11017023724, 8456613930, 8142402169 },
		everyoneInStudio = true,
	},
}

-- Nom "normalisé" : minuscules, sans espaces → "Admin client " = "admin client" = "AdminClient"
local function norm(name)
	return (name:lower():gsub("%s+", ""))
end

local wanted = {}
for name, rule in pairs(ADMIN_SCRIPTS) do
	wanted[norm(name)] = { name = name, rule = rule }
end

-- Cherche les LocalScripts admin partout dans ServerStorage et ServerScriptService
local found = {} -- { {script = LocalScript, rule = rule} }
local function scan()
	table.clear(found)
	local seen = {}
	for _, root in ipairs({ ServerStorage, ServerScriptService }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("LocalScript") then
				local entry = wanted[norm(d.Name)]
				if entry and not seen[entry.name] then
					seen[entry.name] = true
					table.insert(found, { script = d, rule = entry.rule })
				end
			end
		end
	end
	for name in pairs(ADMIN_SCRIPTS) do
		if not seen[name] then
			warn(("[AdminTools] LocalScript '%s' introuvable dans ServerStorage — vérifie qu'il y est bien (et plus dans StarterPlayerScripts)"):format(name))
		end
	end
	for _, f in ipairs(found) do
		print("[AdminTools] trouvé : " .. f.script:GetFullName())
	end
end
scan()

local function isInList(list, userId)
	for _, id in ipairs(list) do
		if id == userId then return true end
	end
	return false
end

local function canReceive(player, rule)
	if rule.everyoneInStudio and RunService:IsStudio() then return true end
	return isInList(rule.ids, player.UserId)
end

local function giveTools(player)
	local toGive = {}
	for _, f in ipairs(found) do
		if canReceive(player, f.rule) then
			table.insert(toGive, f.script)
		end
	end
	if #toGive == 0 then
		if RunService:IsStudio() then
			print(("[AdminTools] %s (UserId %d) n'est pas admin → rien donné"):format(player.Name, player.UserId))
		end
		return
	end

	local playerGui = player:WaitForChild("PlayerGui", 30)
	if not playerGui or not player.Parent then return end
	if playerGui:FindFirstChild("AdminTools") then return end

	-- ScreenGui conteneur avec ResetOnSpawn = false : les scripts ne redémarrent pas à chaque mort
	-- (même comportement qu'avant dans StarterPlayerScripts)
	local holder = Instance.new("ScreenGui")
	holder.Name = "AdminTools"
	holder.ResetOnSpawn = false
	local names = {}
	for _, s in ipairs(toGive) do
		local copy = s:Clone()
		copy.Enabled = true
		copy.Parent = holder
		table.insert(names, s.Name)
	end
	holder.Parent = playerGui
	print(("[AdminTools] donné à %s : %s"):format(player.Name, table.concat(names, ", ")))
end

Players.PlayerAdded:Connect(giveTools)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(giveTools, player)
end
