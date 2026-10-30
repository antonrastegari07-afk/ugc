--════════════════════════════════════════════════════════════
-- 💬 FEEDBACK PROMPT — SERVEUR   (NOUVEAU Script, ServerScriptService)
--
-- Le bouton « WRITE MY FEEDBACK » des Settings ouvre la fenêtre OFFICIELLE
-- de Roblox (SocialService:PromptFeedbackSubmissionAsync). Le feedback part
-- directement dans ton Creator Dashboard ▸ Audience ▸ Feedback.
--
-- ⚠️ Roblox ne dit PAS si le joueur a vraiment écrit quelque chose : on ne
--    peut savoir que « il a ouvert la fenêtre ». La quête « Send Feedback »
--    se débloque donc à l'ouverture. Elle reste sûre là où ça compte :
--    1000 pts UNE seule fois par compte, garanti par le DataStore atomique de
--    la quête (0 → 1 → 2), même en spammant le bouton ou depuis 2 serveurs.
--
-- Anti-spam : 1 demande / 10 s / joueur. Il faut être en jeu depuis 30 s
-- (évite qu'un script de triche le fasse dès l'arrivée de 100 comptes).
--════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MIN_TIME_IN_GAME = 30

local ev = ReplicatedStorage:FindFirstChild("FeedbackPrompted")
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = "FeedbackPrompted"
	ev.Parent = ReplicatedStorage
end

local joinedAt, last = {}, {}
Players.PlayerAdded:Connect(function(p) joinedAt[p.UserId] = os.clock() end)
for _, p in ipairs(Players:GetPlayers()) do joinedAt[p.UserId] = joinedAt[p.UserId] or os.clock() end
Players.PlayerRemoving:Connect(function(p) joinedAt[p.UserId], last[p.UserId] = nil, nil end)

ev.OnServerEvent:Connect(function(player)
	local uid, now = player.UserId, os.clock()
	if last[uid] and now - last[uid] < 10 then return end
	last[uid] = now
	if now - (joinedAt[uid] or now) < MIN_TIME_IN_GAME then return end
	-- statistiques (si ENGAGEMENT STATS est installé)
	if _G.EngageStats and _G.EngageStats.Hit then pcall(_G.EngageStats.Hit, "fb_prompt", uid, 1) end
	-- quête « Send Feedback » : passe à « Claim! » (une seule fois, géré par la quête)
	if type(_G.FeedbackQuest_OnSubmitted) == "function" then
		task.spawn(pcall, _G.FeedbackQuest_OnSubmitted, uid)
	end
end)

print("✅ FEEDBACK PROMPT (Roblox) chargé")
