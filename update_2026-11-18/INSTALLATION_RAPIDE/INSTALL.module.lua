--════════════════════════════════════════════════════════════════════════════
-- 🚀 INSTALLATION AUTOMATIQUE — mise à jour du 18/11/2026
--
--  À lancer depuis la BARRE DE COMMANDE de Studio (Affichage ▸ Barre de commande) :
--      require(workspace.UPDATE_2026_11_18.INSTALL)()
--
--  Ce que ça fait, dans l'ordre :
--   1. Une copie de CHAQUE script remplacé est rangée dans
--      ServerStorage ▸ BACKUP_avant_maj_2026_11_18 (pour revenir en arrière).
--   2. Le code des scripts existants est remplacé (même nom, même place,
--      même état activé/désactivé : rien d'autre ne bouge).
--   3. Les 6 nouveaux scripts sont créés à leur place.
--   4. Le LocalScript « daily notification » est déplacé dans la copie de secours
--      (il n'est pas détruit).
--   5. Le dossier d'installation est supprimé du Workspace.
--  Tout se fait en une seule étape d'annulation : Ctrl+Z annule toute l'installation.
--  Rien n'est publié : vérifie, teste, puis publie toi-même.
--════════════════════════════════════════════════════════════════════════════
return function()
	local root = script.Parent
	local ServerStorage = game:GetService("ServerStorage")
	local CHS = game:GetService("ChangeHistoryService")

	-- l'install ne doit tourner qu'une fois (sinon la copie de secours contiendrait déjà les nouveaux scripts)
	if ServerStorage:FindFirstChild("BACKUP_avant_maj_2026_11_18") then
		warn("⚠️ Déjà installé (ServerStorage ▸ BACKUP_avant_maj_2026_11_18 existe). Rien n'a été fait.")
		return
	end

	pcall(function() CHS:SetWaypoint("Avant la mise à jour du 18/11") end)

	local backup = Instance.new("Folder")
	backup.Name = "BACKUP_avant_maj_2026_11_18"

	local replaced, created, problems = {}, {}, {}

	local function setEnabled(s, on)
		if s:IsA("ModuleScript") then return end
		pcall(function() s.Enabled = on end)
		pcall(function() s.Disabled = not on end)
	end

	local function backupOf(target, path)
		local b = target:Clone()
		b.Name = path:gsub("/", " ▸ ")
		for _, d in ipairs(b:GetDescendants()) do if d:IsA("Script") or d:IsA("LocalScript") then setEnabled(d, false) end end
		setEnabled(b, false)   -- en ServerStorage rien ne tourne, mais on coupe quand même
		b.Parent = backup
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
					local t = matches[1]
					backupOf(t, childPath)
					t.Source = child.Source
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

	backup.Parent = ServerStorage
	root.Parent = nil   -- le dossier d'installation n'a plus rien à faire dans le jeu
	pcall(function() CHS:SetWaypoint("Mise à jour du 18/11 installée") end)

	print(("✅ INSTALLATION TERMINÉE : %d scripts remplacés, %d créés%s.")
		:format(#replaced, #created, dn and ", « daily notification » retiré" or ""))
	for _, p in ipairs(created) do print("   🆕 " .. p) end
	if #problems > 0 then
		warn("⚠️ À VÉRIFIER (" .. #problems .. ") :")
		for _, p in ipairs(problems) do warn("   • " .. p) end
	else
		print("   Aucun problème. Les anciennes versions sont dans ServerStorage ▸ BACKUP_avant_maj_2026_11_18.")
	end
end
