--════════════════════════════════════════════════════════════════════════════
-- 🚀 INSTALLATION AUTOMATIQUE — mise à jour du 18/11/2026
--
--  À lancer depuis la BARRE DE COMMANDE de Studio (Affichage ▸ Barre de commande) :
--      require(workspace.UPDATE_2026_11_18_v26.INSTALL)()
--
--  v26 : contient TOUS les scripts → marche sur un jeu jamais mis à jour ET par-dessus
--       la v2 à v25 (les versions remplacées vont dans sa propre copie de secours).
--
--  Ce que ça fait, dans l'ordre :
--   1. Une copie de CHAQUE script remplacé est rangée dans
--      ServerStorage ▸ BACKUP_avant_maj_v26 (pour revenir en arrière).
--   2. Chaque script existant est ÉCHANGÉ contre sa nouvelle version : même nom,
--      même place, même état activé/désactivé, mêmes attributs / tags, et ses
--      objets enfants passent dans la nouvelle version. (On échange le script entier
--      au lieu de copier le code : Studio refuse de copier plus de 200 000 caractères,
--      et WeaponController, time et Admin client sont plus gros que ça.)
--   3. Les nouveaux scripts sont créés à leur place.
--   4. Le LocalScript « daily notification » est déplacé dans la copie de secours
--      (il n'est pas détruit).
--   5. Les 6 anciens panneaux + 5 anciennes cartes du shop UGC (remplacés depuis longtemps
--      par le générateur) sont déplacés dans la copie de secours.
--   6. Le dossier d'installation est supprimé du Workspace.
--  Tout se fait en une seule étape d'annulation : Ctrl+Z annule toute l'installation.
--  Rien n'est publié : vérifie, teste, puis publie toi-même.
--════════════════════════════════════════════════════════════════════════════
return function()
	print("🚀 Installateur v26 (échange des scripts entiers) — démarrage…")
	local BACKUP_NAME = "BACKUP_avant_maj_v26"
	local root = script.Parent
	local ServerStorage = game:GetService("ServerStorage")
	local CHS = game:GetService("ChangeHistoryService")

	-- l'install ne doit tourner qu'une fois (sinon la copie de secours contiendrait déjà les nouveaux scripts)
	local old = ServerStorage:FindFirstChild(BACKUP_NAME)
	if old then
		if old:GetAttribute("Complete") then
			warn("⚠️ v26 déjà installée (ServerStorage ▸ " .. BACKUP_NAME .. " existe). Rien n'a été fait.")
		else
			warn("⚠️ Une installation v26 s'est arrêtée en cours de route. Fais Ctrl+Z jusqu'à "
				.. "« Avant la mise à jour v26 » (ou supprime le dossier " .. BACKUP_NAME .. " s'il est vide), puis relance.")
		end
		return
	end

	pcall(function() CHS:SetWaypoint("Avant la mise à jour v26") end)

	local backup = Instance.new("Folder")
	backup.Name = BACKUP_NAME
	backup.Parent = ServerStorage   -- tout de suite : un ancien script n'est jamais « perdu » en cours de route

	local replaced, created, problems = {}, {}, {}

	local function setEnabled(s, on)
		if s:IsA("ModuleScript") then return end
		pcall(function() s.Enabled = on end)
		pcall(function() s.Disabled = not on end)
	end

	local CollectionService = game:GetService("CollectionService")
	local function isEnabled(s)
		local ok, v = pcall(function() return s.Enabled end)
		if ok and type(v) == "boolean" then return v end
		local ok2, d = pcall(function() return s.Disabled end)
		if ok2 and type(d) == "boolean" then return not d end
		return true
	end

	-- Échange : la nouvelle version prend la place exacte de l'ancienne,
	-- l'ancienne part (désactivée) dans la copie de secours.
	local function swap(old, newModel, path)
		local n = newModel:Clone()
		n.Name = old.Name
		if not old:IsA("ModuleScript") then
			setEnabled(n, isEnabled(old))
			pcall(function() n.RunContext = old.RunContext end)
		end
		for k, v in pairs(old:GetAttributes()) do n:SetAttribute(k, v) end
		for _, tag in ipairs(CollectionService:GetTags(old)) do CollectionService:AddTag(n, tag) end
		for _, c in ipairs(old:GetChildren()) do c.Parent = n end   -- ses objets enfants suivent
		local parent = old.Parent
		old.Name = path:gsub("/", " ▸ ")
		setEnabled(old, false)
		old.Parent = backup
		n.Parent = parent
	end

	local function walk(folder, target, path)
		for _, child in ipairs(folder:GetChildren()) do
			local childPath = path .. "/" .. child.Name
			if child:IsA("LuaSourceContainer") then
				local matches = {}
				for _, c in ipairs(target:GetChildren()) do
					if c.Name == child.Name and c.ClassName == child.ClassName then table.insert(matches, c) end
				end
				if #matches > 1 then
					table.insert(problems, childPath .. " : " .. #matches .. " scripts portent ce nom → pas touché, à faire à la main")
				elseif #matches == 1 then
					swap(matches[1], child, childPath)
					table.insert(replaced, childPath)
				else
					local n = child:Clone()
					setEnabled(n, true)
					n.Parent = target
					table.insert(created, childPath)
				end
			else
				local nextTarget = target:FindFirstChild(child.Name)
				if not nextTarget then
					table.insert(problems, childPath .. " : introuvable dans ton jeu → ce qu'il contient n'a pas été installé")
				else
					walk(child, nextTarget, childPath)
				end
			end
		end
	end

	for _, svcFolder in ipairs(root:GetChildren()) do
		if svcFolder:IsA("Folder") then
			local ok, svc = pcall(function() return game:GetService(svcFolder.Name) end)
			if ok and svc then walk(svcFolder, svc, svcFolder.Name)
			else table.insert(problems, svcFolder.Name .. " : service introuvable") end
		end
	end

	-- 🗑️ notif de récompense quotidienne : déplacée dans la copie de secours
	local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local dn = sps and sps:FindFirstChild("daily notification")
	if dn then
		dn.Name = "StarterPlayer ▸ StarterPlayerScripts ▸ daily notification (retiré)"
		setEnabled(dn, false)
		dn.Parent = backup
	end

	-- 🧹 anciens modèles du shop UGC (avant le générateur) : leurs vieux scripts démarraient
	--    avant d'être détruits par le générateur → erreurs « UGC ID … non trouvé » et appels
	--    inutiles au serveur. Déplacés dans la copie de secours (rien n'est détruit).
	--    On garde les 2 modèles dont le générateur se sert : MagicDominusButton et NoUGCSelected.
	local shop = game:GetService("StarterGui"):FindFirstChild("UGCshop")
	local sf = shop and shop:FindFirstChild("ShopFrame")
	local oldPanels = { "Korblox Dominus", "Cyber Raven Wings", "Korblox Sword", "Demon Sword", "Magic Dominus", "Fluffy Messy Boy Hair" }
	local oldCards  = { "CyberWingsButton", "KorbloxDominusButton", "KorbloxSwordButton", "DemonSwordButton", "FluffyHairButton" }
	local cleaned = 0
	local function stash(parent, name, label)
		local o = parent and parent:FindFirstChild(name)
		if o and o:IsA("GuiObject") then
			o.Name = label .. name .. " (ancien modèle retiré)"
			o.Parent = backup
			cleaned += 1
		end
	end
	for _, n in ipairs(oldPanels) do stash(sf and sf:FindFirstChild("Selected"), n, "UGCshop ▸ Selected ▸ ") end
	for _, n in ipairs(oldCards) do stash(sf and sf:FindFirstChild("ScrollingFrame"), n, "UGCshop ▸ ScrollingFrame ▸ ") end
	if cleaned > 0 then print(("🧹 %d ancien(s) modèle(s) du shop UGC rangé(s) dans la copie de secours"):format(cleaned)) end

	backup:SetAttribute("Complete", true)
	root.Parent = nil   -- le dossier d'installation n'a plus rien à faire dans le jeu
	pcall(function() CHS:SetWaypoint("Mise à jour v26 installée") end)

	print(("✅ INSTALLATION TERMINÉE : %d scripts remplacés, %d créés%s.")
		:format(#replaced, #created, dn and ", « daily notification » retiré" or ""))
	for _, p in ipairs(created) do print("   🆕 " .. p) end
	if #problems > 0 then
		warn("⚠️ À VÉRIFIER (" .. #problems .. ") :")
		for _, p in ipairs(problems) do warn("   • " .. p) end
	else
		print("   Aucun problème. Les versions remplacées sont dans ServerStorage ▸ " .. BACKUP_NAME .. ".")
	end
end
