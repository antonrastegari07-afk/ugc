--[[
	WeaponHandlingSounds  (LocalScript)
	Emplacement : StarterPlayer > StarterPlayerScripts > WeaponHandlingSounds

	Sons de manipulation (entendus par toi seulement) quand tu tiens une arme :
	épauler / baisser l'arme, début / fin de sprint.
	(Saut, atterrissage et slide : tu as déjà tes propres sons, rien n'est joué ici.)
	Les sons se règlent dans CombatSettings.HandlingSounds (vide = silencieux).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local player = Players.LocalPlayer
local WS = ReplicatedStorage:WaitForChild("WeaponSystem")
local S  = require(WS:WaitForChild("CombatSettings"))
local CI = require(WS:WaitForChild("CombatInput"))
local H = S.HandlingSounds
if S.Enabled == false or not H or H.Enabled == false then return end
local Shared = require(WS:WaitForChild("WeaponSharedState"))

local holder = Instance.new("Folder")
holder.Name = "WeaponHandlingSounds"
holder.Parent = SoundService

local templates = {}
-- 🔊 un Sound posé dans SoundService avec le nom de la clé (AimIn, AimOut, SprintStart,
--    SprintStop) est prioritaire : son SoundId, son Volume et son PlaybackSpeed sont utilisés.
--    Sinon on retombe sur l'ID écrit dans CombatSettings.HandlingSounds.
local function fromSoundService(key)
	local s = SoundService:FindFirstChild(key)
	if s and s:IsA("Sound") and s.SoundId ~= "" then return s end
	return nil
end
local function play(key, volMult)
	local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	local per = tool and H.PerWeapon and H.PerWeapon[CI.BaseWeaponName(tool)]
	local perId = per and per[key]
	local t, vol, speed
	if type(perId) ~= "string" or perId == "" then
		local ss = fromSoundService(key)
		if ss then t, vol, speed = ss, ss.Volume, ss.PlaybackSpeed end
	end
	if not t then
		local id = perId or (H.Sounds and H.Sounds[key])
		if type(id) ~= "string" or id == "" then return end
		if id:match("^%d+$") then id = "rbxassetid://" .. id end   -- ID sans préfixe accepté
		t = templates[id]
		if not t then
			t = Instance.new("Sound")
			t.SoundId = id
			templates[id] = t
		end
		vol, speed = H.Volume or 0.5, 1
	end
	-- un clone par lecture : deux sons rapprochés se chevauchent au lieu de se couper
	local s = t:Clone()
	local j = H.PitchJitter or 0.06
	s.PlaybackSpeed = speed * (1 + (math.random() * 2 - 1) * j)
	s.Volume = vol * (volMult or 1)
	s.Looped = false
	s.Parent = holder
	s:Play()
	Debris:AddItem(s, math.max(2, (s.TimeLength > 0 and s.TimeLength / s.PlaybackSpeed or 2) + 0.5))
end

local function weaponInHand()
	local ch = player.Character
	local t = ch and ch:FindFirstChildOfClass("Tool")
	return t ~= nil and t:FindFirstChild("Receiver") ~= nil
end

local wasAim, wasSprint = false, false

RunService.Heartbeat:Connect(function()
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		wasAim, wasSprint = false, false
		return
	end
	local armed = weaponInHand()
	local aim = armed and Shared.IsAiming()
	if aim ~= wasAim then play(aim and "AimIn" or "AimOut") end
	wasAim = aim
	local sprint = armed and Shared.IsSprinting()
	if sprint ~= wasSprint then play(sprint and "SprintStart" or "SprintStop") end
	wasSprint = sprint
end)
