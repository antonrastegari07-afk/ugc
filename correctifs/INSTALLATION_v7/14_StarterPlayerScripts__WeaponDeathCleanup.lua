-- ============================================================
-- WeaponDeathCleanup  (LocalScript)
-- Emplacement : StarterPlayer/StarterPlayerScripts
-- ============================================================
-- Filet de sécurité PERSISTANT (ne meurt jamais avec les tools) :
-- si une arme est détruite dans la même frame que la mort, son script
-- meurt AVANT son cleanup → lunette (ScopeGui) / cercles orphelins,
-- souris lockée, FOV zoomé. Ce script purge tout ça à chaque respawn.
-- ============================================================
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local ORPHAN_GUIS = { "ScopeGui", "SnapRadiusGui" }

local function purge()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if pg then
		for _, ch in ipairs(pg:GetChildren()) do
			for _, nm in ipairs(ORPHAN_GUIS) do
				if ch.Name == nm then ch:Destroy(); break end
			end
		end
	end
	-- 🔒 arme déjà rééquipée (mode lock PvP) : la souris lui appartient, on n'y touche pas.
	--    Avant, ce nettoyage libérait la souris 0,2 s après le respawn → vue bloquée + curseur libre.
	local char = LocalPlayer.Character
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and t:FindFirstChild("Receiver") then return end
		end
	end
	-- souris rendue au joueur (la lunette la lockait au centre)
	UserInputService.MouseIconEnabled = true
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	UserInputService.MouseDeltaSensitivity = 1
	-- dé-zoom si le FOV lunette est resté (l'arme rééquipée reprendra la main)
	local cam = workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Custom and cam.FieldOfView < 55 then
		cam.FieldOfView = 70
	end
end

LocalPlayer.CharacterAdded:Connect(function()
	task.delay(0.2, purge)   -- après que le respawn est posé, avant le ré-équipe
end)
if LocalPlayer.Character then task.defer(purge) end