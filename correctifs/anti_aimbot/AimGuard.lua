--[[
	🎯 AimGuard  (ModuleScript)  — NOUVEAU
	📍 ServerScriptService ▸ CombatSystem ▸ AimGuard   (à côté de HitValidator)

	Détecte l'AIMBOT sans rien changer au gameplay : il ne touche ni aux dégâts,
	ni aux tirs, ni à la visée. Il OBSERVE seulement ce que WeaponServer reçoit déjà :
	  • chaque tir (« Flash »)
	  • chaque touche VALIDÉE par HitValidator (zone touchée, distance, cible)
	et calcule, sur les dernières minutes de combat de chaque joueur :
	  • sa précision      = tirs qui touchent / tirs
	  • son % de headshots sur de VRAIS joueurs, à distance (≥ MinDistance)

	Un aimbot touche presque tout et presque toujours la tête. Un très bon joueur
	reste loin de ces chiffres sur 40+ tirs à distance (en général 30-60 % de
	précision, 20-45 % de headshots).

	Les armes sont jugées par CLASSE (une arme lente se vise mieux) :
	  auto  (AK, Scar, AutoPistol, Minigun)  précision ≥ 85 % ET headshots ≥ 60 %
	  semi  (Deagle, Magnum)                 précision ≥ 90 % ET headshots ≥ 70 %
	  sniper                                 précision ≥ 95 % ET headshots ≥ 80 %
	+ « head lock » : presque que des headshots à distance (85 / 90 / 92 %)
	+ plus de touches que de tirs (dégâts envoyés sans tirer) → triche réseau
	Toutes ces valeurs sont réglables dans CONFIG.Classes.

	Sanction : AntiExploit.HandleSuspiciousActivity (ton anti-cheat existant) :
	avertissement au joueur + infraction comptée → ban au seuil habituel.
	Chaque détection est aussi écrite dans l'Output avec les chiffres.
	Les développeurs sont ignorés par AntiExploit (comme pour le reste).
]]

local Players = game:GetService("Players")

local AG = {}

local CONFIG = {
	Enabled       = true,
	Window        = 180,    -- s : on regarde les 3 dernières minutes de tirs
	MinShots      = 40,     -- tirs minimum dans la fenêtre avant de juger
	MinLongHits   = 15,     -- touches sur de VRAIS joueurs à distance, minimum
	MinDistance   = 25,     -- studs : de près, tout le monde touche → ignoré pour les %
	-- seuils par classe d'arme (classe d'après la cadence de tir de l'arme)
	Classes = {
		auto   = { Accuracy = 0.85, HeadRate = 0.60, HeadLock = 0.85, HeadLockHits = 25 },  -- FireRate < 0.25 s
		semi   = { Accuracy = 0.90, HeadRate = 0.70, HeadLock = 0.90, HeadLockHits = 25 },  -- 0.25 à 0.6 s
		sniper = { Accuracy = 0.95, HeadRate = 0.80, HeadLock = 0.92, HeadLockHits = 30 },  -- ≥ 0.6 s
	},
	PhantomMargin = 1.25,   -- règle C : touches > tirs × 1.25 + 3
	Cooldown      = 150,    -- s entre deux détections du même joueur (jamais 2 sanctions pour les mêmes tirs)
	Action        = "flag", -- "flag" = anti-cheat (avertit + compte une infraction) | "log" = Output seulement
	-- armes ignorées (plusieurs plombs par tir ou explosifs : la précision n'y veut rien dire)
	IgnoreWeapons = { "ShotGun", "RPG", "Bazooka" },
}
AG.CONFIG = CONFIG

local data = {}   -- [userId] = { shots = {t}, hits = {t, long, head}, keys = {[key]=t}, lastFlag = t }

local function ignored(weaponName, cfg)
	if type(cfg) == "table" and (tonumber(cfg.Pellets) or 1) > 1 then return true end
	if type(weaponName) ~= "string" then return false end
	local base = (weaponName:match("^([^_]+)_") or weaponName):lower()
	for _, n in ipairs(CONFIG.IgnoreWeapons) do
		if n:lower() == base then return true end
	end
	return false
end

local function classOf(cfg)
	local rate = type(cfg) == "table" and tonumber(cfg.FireRate) or 0.1
	if rate >= 0.6 then return "sniper" end
	if rate >= 0.25 then return "semi" end
	return "auto"
end

-- une fiche par joueur ET par classe d'arme (les chiffres ne se mélangent pas)
local function rec(player, class)
	local byClass = data[player.UserId]
	if not byClass then byClass = { lastFlag = -math.huge } data[player.UserId] = byClass end
	local d = byClass[class]
	if not d then
		d = { shots = {}, hits = {}, keys = {}, class = class, owner = byClass }
		byClass[class] = d
	end
	return d
end

local function prune(d, now)
	local limit = now - CONFIG.Window
	if d.shots[1] and d.shots[1] < limit then
		local keep = {}
		for _, t in ipairs(d.shots) do if t >= limit then table.insert(keep, t) end end
		d.shots = keep
	end
	if d.hits[1] and d.hits[1].t < limit then
		local keep = {}
		for _, h in ipairs(d.hits) do if h.t >= limit then table.insert(keep, h) end end
		d.hits = keep
	end
	for key, t in pairs(d.keys) do if t < limit then d.keys[key] = nil end end
end

local function stats(d)
	local shots, hitShots, longHits, longHeads = #d.shots, #d.hits, 0, 0
	for _, h in ipairs(d.hits) do
		if h.long then
			longHits += 1
			if h.head then longHeads = longHeads + 1 end
		end
	end
	return shots, hitShots, longHits, longHeads
end

local function judge(player, d, now)
	if now - d.owner.lastFlag < CONFIG.Cooldown then return end
	local C = CONFIG.Classes[d.class] or CONFIG.Classes.auto
	local shots, hitShots, longHits, longHeads = stats(d)
	local acc = shots > 0 and hitShots / shots or 0
	local head = longHits > 0 and longHeads / longHits or 0

	local kind
	if shots >= CONFIG.MinShots and longHits >= CONFIG.MinLongHits
		and acc >= C.Accuracy and head >= C.HeadRate then
		kind = "AIMBOT"
	elseif longHits >= C.HeadLockHits and head >= C.HeadLock then
		kind = "AIMBOT_HEADLOCK"
	elseif hitShots >= 10 and hitShots > shots * CONFIG.PhantomMargin + 3 then
		kind = "DAMAGE_WITHOUT_FIRING"
	end
	if not kind then return end

	d.owner.lastFlag = now
	local details = string.format("[%s] %d tirs, %d touchent (%.0f %%), %d/%d headshots à ≥%d studs (%.0f %%) sur %ds",
		d.class, shots, hitShots, acc * 100, longHeads, longHits, CONFIG.MinDistance, head * 100, CONFIG.Window)
	warn(("🎯 [AimGuard] %s — %s : %s"):format(kind, player.Name, details))

	-- on repart de zéro : la prochaine détection portera sur de NOUVEAUX tirs
	table.clear(d.shots) ; table.clear(d.hits) ; table.clear(d.keys)

	if CONFIG.Action == "flag" and _G.AntiExploit and _G.AntiExploit.HandleSuspiciousActivity then
		pcall(_G.AntiExploit.HandleSuspiciousActivity, player, kind, details)
	end
end

-- 🔫 un tir (WeaponServer, action « Flash » avec on = true)
function AG.Shot(player, weaponName, cfg)
	if not CONFIG.Enabled or ignored(weaponName, cfg) then return end
	local d = rec(player, classOf(cfg))
	local now = os.clock()
	prune(d, now)
	table.insert(d.shots, now)
	if #d.shots > 600 then table.remove(d.shots, 1) end
end

-- 🎯 une touche VALIDÉE (WeaponServer, action « Damage », après HitValidator)
--    une seule par tir : les touches d'un même tir (même n° de rafale) comptent une fois
function AG.Hit(player, weaponName, cfg, info, zone, targetIsPlayer, distance)
	if not CONFIG.Enabled or ignored(weaponName, cfg) then return end
	local d = rec(player, classOf(cfg))
	local now = os.clock()
	prune(d, now)
	local key = tostring(weaponName) .. ":" .. tostring(type(info) == "table" and (info.v or info.t) or now)
	if d.keys[key] then return end
	d.keys[key] = now
	table.insert(d.hits, {
		t = now,
		long = targetIsPlayer == true and (tonumber(distance) or 0) >= CONFIG.MinDistance,
		head = zone == "head",
	})
	if #d.hits > 600 then table.remove(d.hits, 1) end
	judge(player, d, now)
end

-- 🔎 Console serveur : _G.AimStats("pseudo") → chiffres actuels d'un joueur
_G.AimStats = function(name)
	for _, p in ipairs(Players:GetPlayers()) do
		if not name or p.Name:lower():find(tostring(name):lower(), 1, true) then
			for class, d in pairs(data[p.UserId] or {}) do
				if type(d) == "table" and d.shots then
					prune(d, os.clock())
					local shots, hitShots, longHits, longHeads = stats(d)
					print(string.format("🎯 %s [%s] : %d tirs, %d touchent (%.0f %%), headshots à distance %d/%d (%.0f %%)",
						p.Name, class, shots, hitShots, shots > 0 and hitShots / shots * 100 or 0,
						longHeads, longHits, longHits > 0 and longHeads / longHits * 100 or 0))
				end
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(p) data[p.UserId] = nil end)

return AG
