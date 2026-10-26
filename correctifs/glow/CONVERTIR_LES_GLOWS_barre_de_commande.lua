-- ============================================================
-- CONVERSION AUTOMATIQUE DES 27 SCRIPTS GLOW → GlowEngine
-- ============================================================
-- À COLLER DANS LA BARRE DE COMMANDE DE STUDIO (Affichage ▸ Barre de commande / View ▸ Command Bar)
-- puis Entrée. À faire UNE fois, après avoir mis le ModuleScript "GlowEngine" dans ReplicatedStorage.
--
-- Ce que ça fait, pour chaque LocalScript glow de StarterGui :
--   • garde EXACTEMENT ta configuration (couleurs, tailles, palette, vitesse, sparkles…)
--   • remplace les ~900 lignes du moteur par 1 ligne qui appelle GlowEngine
--   • sauvegarde l'ancienne version dans ServerStorage ▸ GlowBackup (n'est PAS envoyée aux joueurs)
-- Les scripts déjà convertis sont ignorés : tu peux le relancer sans risque.
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ScriptEditorService = game:GetService("ScriptEditorService")

if not ReplicatedStorage:FindFirstChild("GlowEngine") then
	error("Mets d'abord le ModuleScript 'GlowEngine' dans ReplicatedStorage")
end

local recording = nil
pcall(function() recording = ChangeHistoryService:TryBeginRecording("Convertir les glows") end)

local backup = ServerStorage:FindFirstChild("GlowBackup")
if not backup then
	backup = Instance.new("Folder")
	backup.Name = "GlowBackup"
	backup.Parent = ServerStorage
end

local function setSource(s, newSource)
	local ok = pcall(function()
		ScriptEditorService:UpdateSourceAsync(s, function() return newSource end)
	end)
	if not ok then s.Source = newSource end
end

local REQUIRE = 'require(game:GetService("ReplicatedStorage"):WaitForChild("GlowEngine"))'
local converted, skipped = 0, 0

for _, s in ipairs(StarterGui:GetDescendants()) do
	if s:IsA("LocalScript") then
		local src = s.Source
		local newSource

		if src:find("GlowEngine", 1, true) then
			-- déjà converti
		elseif src:find("IMAGE GLOW - VERSION POLISHED", 1, true) then
			-- Gros glow (LED rotatif) : on garde le bloc CONFIG tel quel
			local a = src:find("local CONFIG = {", 1, true)
			local b = a and src:find("\n}", a, true)
			if a and b then
				newSource = "-- GLOW (moteur optimisé : ReplicatedStorage.GlowEngine)\n"
					.. "-- Modifie la CONFIG comme avant, le rendu est identique.\n\n"
					.. src:sub(a, b + 1) .. "\n\n"
					.. REQUIRE .. ".ImageGlow(script.Parent, CONFIG)\n"
			else
				warn("[Glow] CONFIG introuvable, ignoré : " .. s:GetFullName())
				skipped += 1
			end
		elseif src:find("Script pour créer un effet glow autour d'un Frame", 1, true) then
			-- Petit glow (statique)
			local size = src:match("local glowSizeBase%s*=%s*([%d%.]+)")
			local color = src:match("local glowColor%s*=%s*(Color3%.fromRGB%b())")
			local intensity = src:match("local glowIntensity%s*=%s*([%d%.]+)")
			if size and color and intensity then
				newSource = "-- GLOW (moteur optimisé : ReplicatedStorage.GlowEngine)\n\n"
					.. REQUIRE .. ".FrameGlow(script.Parent, {\n"
					.. "\tglowSizeBase = " .. size .. ", -- Largeur du glow en pixels pour PC\n"
					.. "\tglowColor = " .. color .. ",\n"
					.. "\tglowIntensity = " .. intensity .. ",\n"
					.. "})\n"
			else
				warn("[Glow] paramètres introuvables, ignoré : " .. s:GetFullName())
				skipped += 1
			end
		end

		if newSource then
			local old = s:Clone()
			old.Disabled = true
			old.Name = s:GetFullName():gsub("^StarterGui%.", "")
			old.Parent = backup
			setSource(s, newSource)
			converted += 1
			print("[Glow] converti : " .. s:GetFullName())
		end
	end
end

if recording then
	pcall(function() ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end)
end
print(("[Glow] Terminé : %d convertis, %d ignorés. Ancien code sauvegardé dans ServerStorage.GlowBackup"):format(converted, skipped))
