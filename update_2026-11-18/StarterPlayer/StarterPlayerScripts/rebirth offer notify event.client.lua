--[[
	RebirthEventPrompt
	------------------
	À placer dans : StarterPlayer > StarterPlayerScripts  (LocalScript)

	NE MODIFIE AUCUN AUTRE SCRIPT.
	Il se contente d'ecouter le RemoteEvent "UseRebirthDaily" deja utilise
	par ton script de rebirth (plusieurs connexions OnClientEvent coexistent
	sans probleme).

	COMPORTEMENT :
	  Apres chaque rebirth REUSSI :
	    1. Trouve l'event en cours / a venir de l'experience.
	    2. Lit le statut RSVP du joueur (UserRsvpStatus / GetEventRsvpStatusAsync).
	    3. Si le joueur N'EST PAS inscrit -> ouvre la page RSVP de l'event.
	    4. S'il est deja inscrit -> ne fait rien.

	  Si le statut RSVP est indisponible (API desactivee, erreur reseau),
	  fallback automatique : une seule proposition par event et par session.
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Gate = require(ReplicatedStorage:WaitForChild("PopupGate"))   -- 🔔 admin ▸ POPUPS ▸ « Rappel d'event »
local SocialService     = game:GetService("SocialService")

------------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------------
local REBIRTH_REMOTE_NAME = "UseRebirthDaily"  -- ne pas changer
local EVENT_SYNC_NAME     = "EventSync"        -- optionnel (event epingle par l'admin)

local DELAY_AFTER_REBIRTH  = 2   -- laisse passer la teleportation / anim
local EVENT_CACHE_DURATION = 60    -- s, cache de la liste d'events
local MIN_GAP_BETWEEN_PROMPTS = 45 -- s, securite anti double-popup

-- 0 = illimite (tant que le joueur n'a pas RSVP, on lui repropose a chaque rebirth)
-- Mets 1 si tu veux ne proposer qu'une seule fois par event, meme s'il refuse.
local MAX_PROMPTS_PER_EVENT = 0

local DEBUG = true

------------------------------------------------------------------
local player = Players.LocalPlayer

local function log(...)
	if DEBUG then print("[RebirthEventPrompt]", ...) end
end

------------------------------------------------------------------
-- ÉTAT
------------------------------------------------------------------
local pinnedEventId   = nil   -- "auto" ou un id, pousse par EventSync (optionnel)
local cachedEvents    = nil
local cachedAt        = 0
local lastPromptAt    = 0
local promptCount     = {}    -- [eventId] = nombre de propositions cette session
local promptOpen      = false

------------------------------------------------------------------
-- EVENT SYNC (optionnel) : recupere l'event epingle par l'admin
------------------------------------------------------------------
task.spawn(function()
	local sync = ReplicatedStorage:WaitForChild(EVENT_SYNC_NAME, 10)
	if not sync then return end
	sync.OnClientEvent:Connect(function(data)
		if type(data) == "table" and data.eventId ~= nil then
			pinnedEventId = tostring(data.eventId)
		end
	end)
	sync:FireServer("RequestInitial")
end)

------------------------------------------------------------------
-- RECUPERATION DE L'EVENT COURANT
------------------------------------------------------------------
local function fetchUpcoming(force)
	local now = os.clock()
	if not force and cachedEvents and (now - cachedAt) < EVENT_CACHE_DURATION then
		return cachedEvents
	end
	local ok, res = pcall(function()
		return SocialService:GetUpcomingExperienceEventsAsync()
	end)
	if not ok then
		log("GetUpcomingExperienceEventsAsync a echoue :", tostring(res))
		return nil
	end
	if type(res) ~= "table" then return nil end
	cachedEvents = res
	cachedAt     = now
	return res
end

-- Retourne la table de l'event a promouvoir, ou nil
local function getCurrentEvent()
	-- 1) event epingle par l'admin
	if pinnedEventId and pinnedEventId ~= "" and pinnedEventId ~= "auto" then
		local ok, data = pcall(function()
			return SocialService:GetExperienceEventAsync(pinnedEventId)
		end)
		if ok and type(data) == "table" and data.HasEnded ~= true then
			return data, tostring(data.Id or pinnedEventId)
		end
		log("Event epingle indisponible, bascule en auto")
	end

	-- 2) prochain event de l'experience
	local list = fetchUpcoming(true)
	if not list then return nil end
	for _, ev in ipairs(list) do
		if ev.HasEnded ~= true and ev.Id then
			return ev, tostring(ev.Id)
		end
	end
	return nil
end

------------------------------------------------------------------
-- STATUT RSVP
--   true  = deja inscrit
--   false = pas inscrit
--   nil   = impossible de savoir
------------------------------------------------------------------
local function isRsvped(eventData, eventId)
	if eventData and eventData.UserRsvpStatus ~= nil then
		return eventData.UserRsvpStatus == Enum.RsvpStatus.Going
	end
	local ok, status = pcall(function()
		return SocialService:GetEventRsvpStatusAsync(eventId)
	end)
	if ok and typeof(status) == "EnumItem" then
		return status == Enum.RsvpStatus.Going
	end
	log("Statut RSVP indeterminable :", tostring(status))
	return nil
end

------------------------------------------------------------------
-- LOGIQUE PRINCIPALE
------------------------------------------------------------------
local function maybePromptRsvp()
	if promptOpen then return end
	if os.clock() - lastPromptAt < MIN_GAP_BETWEEN_PROMPTS then
		log("Prompt ignore (trop rapproche)")
		return
	end

	local eventData, eventId = getCurrentEvent()
	if not eventData or not eventId then
		log("Aucun event a promouvoir")
		return
	end

	local rsvped = isRsvped(eventData, eventId)

	if rsvped == true then
		log("Deja inscrit a l'event", eventId, "- rien a faire")
		return
	end

	-- Statut inconnu -> fallback : une seule proposition par event / session
	if rsvped == nil then
		if (promptCount[eventId] or 0) >= 1 then
			log("Statut inconnu et deja propose une fois pour", eventId)
			return
		end
		log("Statut inconnu -> proposition unique (fallback)")
	elseif MAX_PROMPTS_PER_EVENT > 0
		and (promptCount[eventId] or 0) >= MAX_PROMPTS_PER_EVENT then
		log("Limite de propositions atteinte pour", eventId)
		return
	end

	promptCount[eventId] = (promptCount[eventId] or 0) + 1
	lastPromptAt = os.clock()
	promptOpen   = true

	log("Ouverture de la page RSVP pour l'event", eventId,
		"(" .. tostring(eventData.Title) .. ")")

	Gate.Shown("event_rsvp")   -- 📊 stats
	local ok, err = pcall(function()
		SocialService:PromptRsvpToEventAsync(eventId)
	end)
	promptOpen = false

	if not ok then
		warn("[RebirthEventPrompt] PromptRsvpToEventAsync : " .. tostring(err))
		return
	end

	-- Re-lecture du statut apres fermeture de la page
	task.wait(1)
	cachedEvents = nil -- force un refresh la prochaine fois
	local after = isRsvped(nil, eventId)
	if after == true then
		log("Le joueur s'est inscrit a l'event", eventId)
		promptCount[eventId] = math.huge -- ne plus jamais reproposer
	end
end

------------------------------------------------------------------
-- HOOK SUR LE REBIRTH (lecture seule, aucun script modifie)
------------------------------------------------------------------
local useRebirthEvent = ReplicatedStorage:WaitForChild(REBIRTH_REMOTE_NAME, 30)
if not useRebirthEvent then
	warn("[RebirthEventPrompt] RemoteEvent '" .. REBIRTH_REMOTE_NAME .. "' introuvable")
	return
end

useRebirthEvent.OnClientEvent:Connect(function(success, ...)
	if success ~= true then return end -- rebirth refuse : on ne fait rien
	if not Gate.Enabled("event_rsvp") then return end -- désactivé dans l'admin
	log("Rebirth reussi -> verification RSVP dans " .. DELAY_AFTER_REBIRTH .. "s")
	task.delay(DELAY_AFTER_REBIRTH, function()
		local ok, err = pcall(maybePromptRsvp)
		if not ok then warn("[RebirthEventPrompt] " .. tostring(err)) end
	end)
end)

-- Prechauffe le cache au lancement (evite un lag au premier rebirth)
task.spawn(function()
	task.wait(5)
	fetchUpcoming(false)
end)

log("Actif pour " .. player.Name)