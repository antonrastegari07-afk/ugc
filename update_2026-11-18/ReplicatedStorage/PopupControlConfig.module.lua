--════════════════════════════════════════════════════════════════════════════
-- 🔔 PopupControlConfig — ModuleScript dans ReplicatedStorage   (NOUVEAU)
--
--  La LISTE des popups automatiques du jeu + leurs réglages PAR DÉFAUT.
--  ⚠️ Les vraies valeurs se changent dans l'ADMIN PANEL ▸ 🔔 POPUPS
--     (sauvegardées et appliquées à tous les serveurs en quelques secondes).
--     Ici, ce ne sont que les valeurs utilisées la toute première fois.
--
--  Les défauts reproduisent EXACTEMENT le comportement d'avant :
--  rien ne change dans le jeu tant que tu ne touches pas aux réglages.
--
--  Lu par : PopupControl_Server (serveur), PopupGate (clients), Admin client.
--════════════════════════════════════════════════════════════════════════════
local M = {}

-- Réglages généraux (s'appliquent aux popups AUTOMATIQUES : minuteurs, carrousel, morts)
M.Global = {
	{ key = "Enabled",       label = "Popups automatiques activés", type = "bool",   default = true,
		help = "Interrupteur général. OFF = aucun popup automatique (les boutons des shops marchent toujours)." },
	{ key = "IdleOnly",      label = "Seulement si le joueur est inactif", type = "bool", default = false,
		help = "ON = un popup automatique attend que le joueur n'ait rien touché pendant X minutes (sauf le carrousel d'offres, toujours visible s'il est activé)." },
	{ key = "IdleMinutes",   label = "Minutes d'inactivité",       type = "number", default = 5, min = 1, max = 30, step = 1,
		help = "Utilisé seulement si « Seulement si inactif » est ON." },
	{ key = "MinGapSeconds", label = "Pause mini entre 2 popups (s)", type = "number", default = 0, min = 0, max = 1800, step = 30,
		help = "Temps minimum entre deux popups automatiques chez un même joueur. 0 = pas de limite." },
}

-- kind :
--   "timer"    → revient tout seul toutes les X minutes
--   "carousel" → petites offres qui défilent à l'écran
--   "deaths"   → après X morts
--   "action"   → suit une action du joueur (cliquer, toucher un pad…) : pas concerné par
--                « seulement si inactif » ni par la pause mini
--   "favorite" → demande de favori (logique intelligente, voir ask favorite game)
M.Popups = {
	{ id = "vip_offer", label = "👑 Popup VIP", kind = "timer",
		desc = "La fenêtre du VIP s'ouvre toute seule (seulement si le joueur n'a pas le VIP).",
		fields = {
			{ key = "Enabled", label = "Activé", type = "bool", default = true },
			{ key = "IntervalMin", label = "Toutes les (min)", type = "number", default = 13, min = 3, max = 120, step = 1 },
		} },
	{ id = "skip_obby_auto", label = "⏭️ Pass Skip Obby (fenêtre Roblox)", kind = "timer",
		desc = "Ouvre directement la fenêtre d'achat Roblox du pass Skip Obby (si pas déjà acheté).",
		fields = {
			{ key = "Enabled", label = "Activé", type = "bool", default = true },
			{ key = "IntervalMin", label = "Toutes les (min)", type = "number", default = 20, min = 5, max = 180, step = 5 },
		} },
	{ id = "offers_carousel", label = "🎠 Carrousel d'offres", kind = "carousel",
		desc = "Les petites offres qui défilent sur le côté de l'écran.",
		fields = {
			{ key = "Enabled", label = "Activé", type = "bool", default = true },
			{ key = "FirstDelaySec", label = "1re offre après (s)", type = "number", default = 5, min = 0, max = 600, step = 5 },
			{ key = "DisplaySec", label = "Durée d'une offre (s)", type = "number", default = 12, min = 4, max = 60, step = 1 },
		} },
	{ id = "death_offer", label = "💀 Offre après des morts", kind = "deaths",
		desc = "Fenêtre d'achat de points après plusieurs morts (petit pack, puis gros pack).",
		fields = {
			{ key = "Enabled", label = "Activé", type = "bool", default = true },
			{ key = "EveryDeaths", label = "Petit pack toutes les (morts)", type = "number", default = 10, min = 3, max = 100, step = 1 },
			{ key = "BigEveryDeaths", label = "Gros pack toutes les (morts)", type = "number", default = 20, min = 3, max = 200, step = 1 },
			{ key = "CountArena", label = "Compter les morts en arène PvP", type = "bool", default = true },
		} },
	{ id = "missing_points", label = "🎽 Points manquants pour une UGC", kind = "action",
		desc = "Le joueur clique sur une UGC sans assez de points → Roblox lui propose le pack de points adapté.",
		fields = {
			{ key = "Enabled", label = "Activé", type = "bool", default = true },
		} },
	{ id = "touch_pads", label = "🌀 Pads d'achat sur la map", kind = "action",
		desc = "Toucher un coil / x2 posé sur la map ouvre sa fenêtre d'achat.",
		fields = {
			{ key = "Enabled", label = "Activé", type = "bool", default = true },
		} },
	{ id = "event_rsvp", label = "📅 Rappel d'event après un rebirth", kind = "action",
		desc = "Après un rebirth, Roblox propose de s'inscrire au prochain event du jeu.",
		fields = {
			{ key = "Enabled", label = "Activé", type = "bool", default = true },
		} },
	{ id = "favorite", label = "⭐ Demande de favori", kind = "favorite",
		desc = "1re demande au checkpoint choisi. Si refus : redemandée plus tard, à un bon moment, de plus en plus espacée.",
		fields = {
			{ key = "Enabled", label = "Activé", type = "bool", default = true },
			{ key = "Checkpoint", label = "1re demande au checkpoint n°", type = "number", default = 4, min = 1, max = 200, step = 1 },
			{ key = "RetryDays", label = "Redemander après (jours)", type = "number", default = 2, min = 1, max = 60, step = 1,
				help = "Délai avant la 2e demande. Il double ensuite à chaque refus (2 j → 4 j → 8 j…)." },
			{ key = "MaxAsks", label = "Nombre max de demandes", type = "number", default = 4, min = 1, max = 20, step = 1 },
			{ key = "MinSessionMinutes", label = "Redemander après (min de jeu)", type = "number", default = 10, min = 1, max = 120, step = 1,
				help = "Une nouvelle demande arrive seulement quand le joueur joue déjà depuis ce temps (joueur « chaud »)." },
		} },
}

M.ById = {}
for _, p in ipairs(M.Popups) do M.ById[p.id] = p end

-- Nom d'attribut sur ReplicatedStorage.PopupControl
function M.Attr(id, key) return (id == "_G" and "G_" or (id .. "__")) .. key end

-- Valide / borne une valeur venant du panel. Retourne nil si refusée.
function M.Sanitize(field, value)
	if field.type == "bool" then
		if type(value) ~= "boolean" then return nil end
		return value
	elseif field.type == "number" then
		value = tonumber(value)
		if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
		local step = field.step or 1
		value = math.floor(value / step + 0.5) * step
		return math.clamp(value, field.min or 0, field.max or 1e6)
	end
	return nil
end

function M.FindField(id, key)
	local list = (id == "_G") and M.Global or (M.ById[id] and M.ById[id].fields)
	if not list then return nil end
	for _, f in ipairs(list) do if f.key == key then return f end end
	return nil
end

return M
