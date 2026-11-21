--════════════════════════════════════════════════════════════════════════════
-- 🏷️ UGCTypeTagger — Script dans ServerScriptService   (NOUVEAU)
--
--  Étiquette chaque UGC du shop avec sa catégorie (Hat, Hair, Head…) UNE SEULE FOIS,
--  et la garde en mémoire (DataStore) : le filtre TYPE du shop apparaît alors
--  INSTANTANÉMENT pour les joueurs, au lieu que chaque joueur redemande à Roblox
--  le type de chaque UGC.
--
--  • Démarrage d'un serveur : 1 seule lecture DataStore → toutes les catégories connues
--    sont publiées tout de suite (attributs de ReplicatedStorage ▸ UGCTypes).
--  • UGC ajouté (même en cours de partie) : demandé à Roblox UNE fois, puis enregistré.
--  • Catégorie forcée : dans UGC_CONFIG, ajoute  Type = "Head"  à l'UGC.
--  • Sécurité : seul le serveur écrit ; les joueurs ne font que lire. 1 lecture DataStore
--    par serveur + 1 écriture seulement quand un nouvel UGC est étiqueté.
--  ↩️ Pour revenir à avant : supprime ce script (le shop refait alors le travail lui-même).
--════════════════════════════════════════════════════════════════════════════
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local UGC_CONFIG = require(ReplicatedStorage:WaitForChild("UGC_CONFIG"))
local TypeInfo   = require(ReplicatedStorage:WaitForChild("UGCTypeInfo"))

local STORE_NAME, KEY = "UGCTypeCache", "types_v1"
local RECHECK = 120   -- s : vérifie s'il y a de nouveaux UGC à étiqueter

local tags = ReplicatedStorage:FindFirstChild("UGCTypes")
if not tags then
	tags = Instance.new("Configuration")
	tags.Name = "UGCTypes"
	tags.Parent = ReplicatedStorage
end
local function attrName(id) return "T_" .. tostring(id) end
local function publish(id, cat)
	if tags:GetAttribute(attrName(id)) ~= cat then tags:SetAttribute(attrName(id), cat) end
end

-- 1) mémoire : lue UNE fois
local store
pcall(function() store = DataStoreService:GetDataStore(STORE_NAME) end)
local cache = {}
if store then
	local ok, data = pcall(function() return store:GetAsync(KEY) end)
	if ok and type(data) == "table" then
		for k, v in pairs(data) do
			if type(k) == "string" and type(v) == "string" then cache[k] = v end
		end
	elseif not ok then
		warn("[UGCTypeTagger] mémoire illisible (" .. tostring(data) .. ") → étiquetage sans mémoire")
	end
end

-- 2) publie tout ce qu'on sait déjà (instantané)
local function publishKnown()
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		local id = tonumber(ugc.AssetId)
		if id and id > 0 then
			local cat = TypeInfo.forced(ugc) or cache[tostring(id)]
			if cat then publish(id, cat) end
		end
	end
end
publishKnown()
tags:SetAttribute("Ready", true)   -- le shop sait que le serveur s'en occupe

-- 3) étiquette les UGC encore inconnus (4 à la fois), puis enregistre UNE fois
local busy = false
local function tagMissing()
	if busy then return end
	busy = true
	local todo = {}
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		local id = tonumber(ugc.AssetId)
		if id and id > 0 and not TypeInfo.forced(ugc) and not cache[tostring(id)] then table.insert(todo, id) end
	end
	if #todo > 0 then
		local added, idx, running = {}, 0, 0
		for _ = 1, math.min(4, #todo) do
			running += 1
			task.spawn(function()
				while true do
					idx += 1
					local id = todo[idx]
					if not id then break end
					local cat, why = TypeInfo.lookup(id)
					if cat then
						cache[tostring(id)] = cat
						added[tostring(id)] = cat
						publish(id, cat)
					else
						warn(string.format("[UGCTypeTagger] catégorie introuvable pour %d (%s) → réessai plus tard", id, tostring(why)))
					end
				end
				running -= 1
			end)
		end
		while running > 0 do task.wait(0.2) end
		if store and next(added) then
			pcall(function()
				store:UpdateAsync(KEY, function(old)
					local t = type(old) == "table" and old or {}
					for k, v in pairs(added) do t[k] = v end
					return t
				end)
			end)
			local n = 0
			for _ in pairs(added) do n += 1 end
			print(string.format("[UGCTypeTagger] %d nouvel(s) UGC étiqueté(s) et enregistré(s)", n))
		end
	end
	busy = false
end

task.spawn(tagMissing)
while true do
	task.wait(RECHECK)
	publishKnown()   -- catégorie forcée ajoutée / changée dans UGC_CONFIG
	tagMissing()
end
