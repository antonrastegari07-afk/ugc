--!strict
--[[
	MarketplaceServiceFX
	-------------------------------------------------------------------
	ModuleScript  ->  ReplicatedStorage.MarketplaceServiceFX

	Proxy transparent de MarketplaceService.
	Tu remplaces UNE ligne en haut de tes scripts de boutique :

		-- avant
		local MarketplaceService = game:GetService("MarketplaceService")
		-- apres
		local MarketplaceService = require(game.ReplicatedStorage.MarketplaceServiceFX)

	...et c'est tout. Le reste de ton code ne change pas d'un caractere :
	chaque Prompt*Purchase declenche automatiquement l'effet arc-en-ciel.

	AUTONOME : ce module suffit.
	  - Cote SERVEUR il cree lui-meme le RemoteEvent des son chargement
	    (donc bien avant qu'un joueur puisse acheter : pas de course).
	  - Cote CLIENT il demarre lui-meme RobuxPromptFX (ecoute du RemoteEvent
	    + events de fermeture du prompt).
	RobuxPromptFX_Init / _Server / _Boot restent utiles mais ne sont plus
	indispensables.

	Tout le reste (GetProductInfo, UserOwnsGamePassAsync, ProcessReceipt,
	PromptGamePassPurchaseFinished, ...) est transmis tel quel.
--]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local IS_SERVER = RunService:IsServer()

local REMOTE_NAME = "RobuxPromptFX_Show"
local FX_MODULE_NAME = "RobuxPromptFX"

-- Methodes qui ouvrent une fenetre d'achat -> declenchent l'effet
local TRIGGERS: { [string]: boolean } = {
	PromptPurchase = true,
	PromptGamePassPurchase = true,
	PromptProductPurchase = true,
	PromptBundlePurchase = true,
	PromptSubscriptionPurchase = true,
	PromptPremiumPurchase = true,
	PromptRobloxPurchase = true,
}

-- Proprietes de type callback : JAMAIS enveloppees (sinon ProcessReceipt casse)
local RAW_PROPERTIES: { [string]: boolean } = {
	ProcessReceipt = true,
	ProcessSubscriptionPurchase = true,
}

--=====================================================================
-- SERVEUR : creation immediate du RemoteEvent
--
-- Fait au CHARGEMENT du module (donc au demarrage du serveur), pas au
-- moment de l'achat. Si on le creait au moment de l'achat, le premier
-- FireClient partirait avant que le client ait eu le temps de recevoir
-- l'instance et de s'y connecter -> effet perdu sur le 1er achat.
--=====================================================================
local showRemote: RemoteEvent? = nil

if IS_SERVER then
	local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		showRemote = existing
	else
		local r = Instance.new("RemoteEvent")
		r.Name = REMOTE_NAME
		r.Parent = ReplicatedStorage
		showRemote = r
	end
end

--=====================================================================
-- CLIENT : demarrage de l'effet
--
-- On lance RobuxPromptFX.Init() des le chargement du proxy. C'est lui qui
-- ecoute le RemoteEvent (prompts ouverts par le SERVEUR, ex: gifting) et
-- les events de fermeture. Sans ca, un prompt serveur n'afficherait rien.
--=====================================================================
if not IS_SERVER then
	task.spawn(function()
		local mod = ReplicatedStorage:WaitForChild(FX_MODULE_NAME, 30)
		if not mod or not mod:IsA("ModuleScript") then
			warn(
				"[MarketplaceServiceFX] ReplicatedStorage."
					.. FX_MODULE_NAME
					.. " introuvable : aucun effet ne sera affiche."
			)
			return
		end
		local ok, api = pcall(require, mod)
		if not ok or type(api) ~= "table" then
			warn("[MarketplaceServiceFX] echec du require de " .. FX_MODULE_NAME .. " :", api)
			return
		end
		if type(api.Init) == "function" then
			local okInit, err = pcall(api.Init)
			if not okInit then
				warn("[MarketplaceServiceFX] echec de Init() :", err)
			end
		end
	end)
end

--=====================================================================
-- Declenchement de l'effet (jamais bloquant)
--=====================================================================
local warnedMissing = false

local function doTrigger(target: any)
	if IS_SERVER then
		if typeof(target) ~= "Instance" or not target:IsA("Player") then
			return
		end
		if showRemote then
			showRemote:FireClient(target, true)
		elseif not warnedMissing then
			warnedMissing = true
			warn("[MarketplaceServiceFX] RemoteEvent " .. REMOTE_NAME .. " absent cote serveur")
		end
	else
		-- Cote client MarketplaceService ne vise que le joueur local,
		-- mais on verifie quand meme si un Player a ete passe.
		if typeof(target) == "Instance" and target ~= Players.LocalPlayer then
			return
		end
		local mod = ReplicatedStorage:FindFirstChild(FX_MODULE_NAME)
		if mod and mod:IsA("ModuleScript") then
			local ok, api = pcall(require, mod)
			if ok and type(api) == "table" then
				api.Play()
			end
		elseif not warnedMissing then
			warnedMissing = true
			warn("[MarketplaceServiceFX] ReplicatedStorage." .. FX_MODULE_NAME .. " introuvable")
		end
	end
end

local function trigger(target: any)
	-- spawn + pcall : une erreur d'effet ne doit JAMAIS empecher l'achat
	task.spawn(function()
		local ok, err = pcall(doTrigger, target)
		if not ok then
			warn("[MarketplaceServiceFX] effet non lance:", err)
		end
	end)
end

--=====================================================================
-- 📊 STATS : quel script ouvre la fenêtre d'achat (pour « d'où viennent les achats »)
-- Jamais bloquant, n'influence pas l'achat. debug.info(3) = le script qui a appelé
-- MarketplaceService:Prompt...(…) via ce proxy.
--=====================================================================
local function noteSource(method: string, target: any, itemId: any)
	local okS, src = pcall(debug.info, 3, "s")
	if not okS or type(src) ~= "string" then return end
	task.spawn(function()
		pcall(function()
			if IS_SERVER then
				local es = (_G :: any).EngageStats
				if es and es.NoteSource then es.NoteSource(target, src, method, itemId) end
			else
				local ev = ReplicatedStorage:FindFirstChild("EngageTrack")
				if ev and ev:IsA("RemoteEvent") then ev:FireServer("src", src, method, itemId) end
			end
		end)
	end)
end

--=====================================================================
-- Proxy
--=====================================================================
local proxy = {}
local wrapperCache: { [string]: any } = {}

setmetatable(proxy, {
	__index = function(_, key: string): any
		local ms: any = MarketplaceService

		if RAW_PROPERTIES[key] then
			return ms[key]
		end

		local cached = wrapperCache[key]
		if cached ~= nil then
			return cached
		end

		local value = ms[key]
		if type(value) ~= "function" then
			-- events / proprietes normales : renvoyes directement, non caches
			return value
		end

		local isTrigger = TRIGGERS[key] == true
		local fn = function(self: any, ...)
			-- Supporte l'appel avec ':' (self = proxy) ET avec '.' (self = 1er arg)
			if self == proxy then
				if isTrigger then
					trigger((...))
					noteSource(key, (...), (select(2, ...)))
				end
				return value(MarketplaceService, ...)
			else
				if isTrigger then
					trigger(self)
					noteSource(key, self, (...))
				end
				return value(MarketplaceService, self, ...)
			end
		end

		wrapperCache[key] = fn
		return fn
	end,

	__newindex = function(_, key: string, value: any)
		local ms: any = MarketplaceService
		ms[key] = value
	end,

	__tostring = function()
		return "MarketplaceServiceFX (proxy de MarketplaceService)"
	end,
})

return proxy