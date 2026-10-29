-- EngageTrack — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (NOUVEAU)
-- Prévient le serveur à CHAQUE fermeture d'un prompt d'invitation Roblox, quelle que
-- soit la façon dont il a été ouvert (bouton Invite, carrousel d'offres, PNJ…),
-- avec le nombre d'amis invités. Sert uniquement aux stats (📨 dans l'admin panel).
local Players       = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local RS            = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local track = RS:WaitForChild("EngageTrack", 60)
if not track then return end

SocialService.GameInvitePromptClosed:Connect(function(plr, recipientIds)
	if plr ~= player then return end
	local n = type(recipientIds) == "table" and #recipientIds or 0
	pcall(function() track:FireServer("invite", n) end)
end)
