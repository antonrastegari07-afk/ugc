--[[
	SettingsConfig  (ModuleScript)
	Emplacement : ReplicatedStorage > SettingsConfig

	Tout le panneau Settings se règle ici : catégories, textes, préréglages
	performance, taille, couleurs. Le LocalScript « SettingsUI » construit
	l'interface à partir de cette table.
]]

local C = {}

C.Enabled = true

-- 🎮 Touche manette pour ouvrir / fermer le panneau
--    ButtonSelect = View (Xbox) / Share-Create (PlayStation).
--    ⚠️ Elle remplace l'action par défaut de Roblox sur cette touche.
C.GamepadToggleKey = Enum.KeyCode.ButtonSelect

-- 📐 Taille de design du panneau (au centre de l'écran). Il est mis à
--    l'échelle pour tenir sous la barre Roblox, sans dépasser MaxScale.
C.Design = {
	PC     = { W = 460, H = 640 },
	Mobile = { W = 400, H = 420 },
}
C.MaxScreenWidth = 0.9
C.MaxScale       = 1.1

-- 🎨 Couleurs (sobre : noir, gris, bleu). Dark / White / Sub / police sont repris de
--    WeaponSystem/CombatSettings.Style quand UseCombatStyle = true.
C.UseCombatStyle = true
C.Theme = {
	Dark       = Color3.fromRGB(14, 16, 22),
	PanelT     = 0.3,                              -- transparence du fond noir (0 = opaque)
	White      = Color3.fromRGB(240, 242, 247),
	Sub        = Color3.fromRGB(150, 156, 170),
	Accent     = Color3.fromRGB(70, 150, 245),     -- sélection, interrupteurs ON
	Off        = Color3.fromRGB(62, 66, 80),       -- interrupteurs OFF
	FontFamily = "rbxasset://fonts/families/BuilderSans.json",
}

-- 🎯 Objectifs des quêtes : DOIVENT être identiques au script des points
C.CheckpointGoal = 120   -- CHECKPOINT_QUEST_REQUIRED
C.KillGoal       = 30    -- KILL_QUEST_REQUIRED

-- Attribut posé par le serveur quand ta sauvegarde est appliquée
C.LoadedAttribute = "SettingsLoaded"

-- ============================================================
-- ⚡ PRÉRÉGLAGES PERFORMANCE
--    id 3 = « Custom » (le joueur a touché aux réglages avancés)
-- ============================================================
C.PerfPresets = {
	[0] = {
		name = "High",
		desc = "Full graphics. Looks the best, uses the most power.",
		values = {
			SettingPerfShadows = true,  SettingPerfPostFX = true,  SettingPerfParticles = true,
			SettingPerfTerrain = true,  SettingPerfLowTex = false, SettingPerfQuality = 0,
			SettingRenderDistance = 100, SettingHideAccessories = false, SettingPerfMode = false,
		},
	},
	[1] = {
		name = "Medium",
		desc = "No shadows, glow effects or grass/water detail. Good balance between looks and FPS.",
		values = {
			SettingPerfShadows = false, SettingPerfPostFX = false, SettingPerfParticles = true,
			SettingPerfTerrain = false, SettingPerfLowTex = false, SettingPerfQuality = 0,
			SettingRenderDistance = 100, SettingHideAccessories = false, SettingPerfMode = false,
		},
	},
	[2] = {
		name = "Low",
		desc = "Maximum FPS: all effects off, simple textures, lower graphics, far players and hats hidden.",
		values = {
			SettingPerfShadows = false, SettingPerfPostFX = false, SettingPerfParticles = false,
			SettingPerfTerrain = false, SettingPerfLowTex = true,  SettingPerfQuality = 10,
			SettingRenderDistance = 60, SettingHideAccessories = true, SettingPerfMode = true,
		},
	},
}
C.PerfPresetOrder = { 2, 1, 0 }   -- affichage : Low · Medium · High
C.PerfCustomDesc  = "Custom: you changed the advanced settings below."

local presetOptions = {}
for _, id in ipairs(C.PerfPresetOrder) do
	local p = C.PerfPresets[id]
	table.insert(presetOptions, { value = id, name = p.name, desc = p.desc })
end

-- ============================================================
-- 📋 CATÉGORIES (onglets de gauche à droite, sections de haut en bas)
--    hideLabel = true : pas de titre ni de texte au-dessus des boutons du réglage
--    type : header · toggle · stepper · choice · advanced
--    group = "advanced" → caché sous « Advanced settings »
-- ============================================================
C.Categories = {
	{
		id = "combat", name = "Combat",
		items = {
			{ type = "header", text = "SENSITIVITY" },
			{ type = "stepper", key = "SettingHipSensitivity", label = "Camera Sensitivity",
				min = 1, max = 100, step = 1, default = 50 },
			{ type = "stepper", key = "SettingAimSensRel", label = "Aim Sensitivity",
				min = 25, max = 100, step = 5, default = 60, suffix = "%" },

			{ type = "header", text = "AIM HELP" },
			{ type = "toggle", key = "SettingAimAssist", label = "Aim Assist", default = true },
			{ type = "toggle", key = "SettingAutoFire", label = "Auto-Fire (Mobile)", default = true },

			{ type = "header", text = "HIT FEEDBACK" },
			{ type = "toggle", key = "SettingDamageNumbers", label = "Damage Numbers", default = true },
			{ type = "toggle", key = "SettingHitMarkers", label = "Hit Markers", default = true },
			{ type = "toggle", key = "SettingEnemyOutlines", label = "Enemy Outlines", default = true },
			{ type = "toggle", key = "SettingTracerRivals", label = "Comet Tracers", default = false,
				visibleAttr = "WeaponTracerCustom",
				visibleIf = function(p) return p:GetAttribute("WeaponTracerCustom") == true end },
		},
	},
	{
		id = "audio", name = "Audio",
		items = {
			{ type = "toggle", key = "SettingMusicEnabled", label = "Music", default = true },
			{ type = "stepper", key = "SettingMusicVolume", label = "Music Volume",
				min = 0, max = 100, step = 5, default = 10, suffix = "%" },
		},
	},
	{
		id = "display", name = "Display",
		items = {
			{ type = "choice", key = "SettingNight", label = "Time of Day", default = false,
				options = {
					{ value = false, name = "Day" },
					{ value = true,  name = "Night" },
				} },
			{ type = "toggle", key = "SettingExtraBillboards", label = "Head Tags", default = true },
			{ type = "choice", key = "SettingPointStyle", label = "Points Style", default = 0,
				watchAttrs = { "IsVIP", "NoobStyle2" },
				options = {
					{ value = 0, name = "Classic" },
					{ value = 1, name = "VIP Gold",
						locked = "Requires the VIP gamepass.",
						owned = function(p) return p:GetAttribute("IsVIP") == true end },
					{ value = 2, name = "Noob's Friend",
						locked = "Help the noob finish his quests to unlock it.",
						owned = function(p) return p:GetAttribute("NoobStyle2") == true end },
				} },
		},
	},
	{
		id = "perf", name = "Performance",
		items = {
			{ type = "choice", key = "SettingPerfPreset", label = "Preset", hideLabel = true,
				default = 0, preset = true, options = presetOptions },
			{ type = "toggle", key = "SettingAutoPerf", label = "Auto Performance", default = false },
			{ type = "toggle", key = "SettingPerfStats", label = "Show FPS & Ping", default = false },

			{ type = "advanced", label = "Advanced settings" },
			{ type = "toggle", group = "advanced", key = "SettingPerfShadows", label = "Shadows", default = true },
			{ type = "toggle", group = "advanced", key = "SettingPerfPostFX", label = "Glow Effects", default = true },
			{ type = "toggle", group = "advanced", key = "SettingPerfParticles", label = "Particles", default = true },
			{ type = "toggle", group = "advanced", key = "SettingPerfTerrain", label = "Grass & Water", default = true },
			{ type = "toggle", group = "advanced", key = "SettingPerfLowTex", label = "Simple Textures", default = false },
			{ type = "stepper", group = "advanced", key = "SettingPerfQuality", label = "Graphics Level",
				min = 0, max = 100, step = 10, default = 0, suffix = "%" },
			{ type = "stepper", group = "advanced", key = "SettingRenderDistance", label = "Player Render Distance",
				min = 10, max = 100, step = 10, default = 100, suffix = "%" },
			{ type = "toggle", group = "advanced", key = "SettingHideAccessories", label = "Hide Other Players' Hats",
				default = false },
		},
	},
}

-- Boutons du bas : ce ne sont PAS des réglages, ils ouvrent leur propre page
C.Info = {
	stats    = { name = "STATS & UGCS",    title = "Stats & UGCs" },
	feedback = { name = "FEEDBACK", title = "Feedback" },
}

-- ============================================================
-- 🎯 SENSIBILITÉ — à utiliser dans le WeaponController
--    Retourne le multiplicateur caméra (1 = sensibilité 50 hors visée).
--    En visée : relatif à la sensi caméra ET compensé selon le zoom,
--    pour que 100 % donne le même ressenti qu'hors visée.
-- ============================================================
function C.GetSensitivity(player, aiming, currentFov, baseFov)
	local hip = (tonumber(player:GetAttribute("SettingHipSensitivity")) or 50) / 50
	if not aiming then return hip end
	local rel = (tonumber(player:GetAttribute("SettingAimSensRel")) or 100) / 100
	local zoom = 1
	if currentFov and baseFov and baseFov > 0 and currentFov > 0 then
		zoom = math.tan(math.rad(currentFov) / 2) / math.tan(math.rad(baseFov) / 2)
	end
	return hip * rel * zoom
end

return C