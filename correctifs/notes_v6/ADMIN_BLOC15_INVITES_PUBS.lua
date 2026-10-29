--════════════════════════════════════════════════════════════════════════════
-- 📨 BLOC 15 — INVITES & PUBS   (dans l'admin panel)
--
--  📍 OÙ COLLER ? Dans ton LocalScript « ADMIN PANEL — CLIENT », JUSTE AVANT
--     le bloc « 📜 BLOC 11 — CONSERVER LA POSITION DE DÉFILEMENT »
--     (donc juste après le `end)()` qui termine le BLOC 14 — REVENUS).
--     Le bloc 11 doit rester le DERNIER.
--  Ajoute un bouton 📨 INVITES & PUBS à l'accueil.
--  Les chiffres viennent du script serveur « ENGAGEMENT STATS ».
--════════════════════════════════════════════════════════════════════════════
;(function()
	local BLUE   = Color3.fromRGB(110, 180, 255)
	local BLUE_D = Color3.fromRGB(40, 90, 150)
	local ORANGE = Color3.fromRGB(255, 170, 70)
	local GREEN  = Color3.fromRGB(90, 220, 140)
	local SM = IS_MOBILE and 10 or 12

	local ST = { p = 7, cache = {}, token = 0 }
	local PERIODS = {
		{ id = 1, label = "Aujourd'hui" }, { id = 7, label = "7 jours" }, { id = 30, label = "30 jours" },
	}

	local function fetch(days, cb)
		local c = ST.cache[days]
		if c and os.clock() - c.at < 30 then cb(c.data) return end
		local fn = ReplicatedStorage:FindFirstChild("AdminEngage_Get")
		if not fn then cb(nil, "Le script serveur ENGAGEMENT STATS n'est pas installé.") return end
		task.spawn(function()
			for attempt = 1, 5 do
				local ok, res = pcall(function() return fn:InvokeServer(days) end)
				if ok and type(res) == "table" and res.ok then
					ST.cache[days] = { data = res, at = os.clock() }
					cb(res) return
				end
				if ok and type(res) == "table" and res.err == "non admin" then cb(nil, res.err) return end
				task.wait(0.5 * attempt)
			end
			cb(nil, "Serveur occupé, appuie sur 🔄.")
		end)
	end

	local function sep(n)
		n = math.floor((tonumber(n) or 0) + 0.5)
		local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1 "):reverse()
		return (n < 0 and "-" or "") .. s:gsub("^%s+", "")
	end
	local function pct(a, b)
		a, b = tonumber(a) or 0, tonumber(b) or 0
		if b <= 0 then return "—" end
		return string.format("%.0f %%", a / b * 100)
	end
	local function avg(a, b)
		a, b = tonumber(a) or 0, tonumber(b) or 0
		if b <= 0 then return "—" end
		return string.format("%.1f", a / b)
	end

	local function note(parent, order, text, color)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.BackgroundColor3 = C.BG_ITEM
		f.BorderSizePixel = 0
		f.LayoutOrder = order
		f.ZIndex = 11
		f.Parent = parent
		corner(f, 8) ; stroke(f, color or C.BORDER_SUBTLE, 1)
		local p = Instance.new("UIPadding")
		p.PaddingTop, p.PaddingBottom = UDim.new(0, 7), UDim.new(0, 7)
		p.PaddingLeft, p.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
		p.Parent = f
		local l = label(f, { text = text, size = UDim2.new(1, 0, 0, 0), color = color or C.TEXT_GREY,
			textSize = SM, wrapped = true, xAlign = Enum.TextXAlignment.Left, zIndex = 12 })
		l.AutomaticSize = Enum.AutomaticSize.Y
		return f
	end

	-- Petit graphique en barres, une barre par jour
	local function bars(parent, order, days, key, title, color)
		local H = IS_MOBILE and 110 or 140
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, H)
		f.BackgroundColor3 = C.BG_DARK
		f.BorderSizePixel = 0
		f.LayoutOrder = order
		f.ZIndex = 11
		f.Parent = parent
		corner(f, 12) ; stroke(f, C.BORDER_SUBTLE, 1)
		label(f, { text = title, size = UDim2.new(1, -24, 0, 16), position = UDim2.new(0, 12, 0, 6),
			xAlign = Enum.TextXAlignment.Left, color = C.TEXT_GREY, textSize = SM, truncate = true, zIndex = 12 })
		local max = 0
		for _, d in ipairs(days) do max = math.max(max, tonumber(d.v[key]) or 0) end
		if max <= 0 then
			label(f, { text = "Rien sur cette période", size = UDim2.fromScale(1, 1), color = C.TEXT_DIM,
				textSize = IS_MOBILE and 12 or 15, zIndex = 12 })
			return
		end
		local plot = Instance.new("Frame")
		plot.BackgroundTransparency = 1
		plot.Position = UDim2.new(0, 8, 0, 26)
		plot.Size = UDim2.new(1, -16, 1, -44)
		plot.ZIndex = 12
		plot.Parent = f
		local n = #days
		local every = math.max(1, math.ceil(n / (IS_MOBILE and 7 or 12)))
		for i, d in ipairs(days) do
			local v = tonumber(d.v[key]) or 0
			local col = Instance.new("Frame")
			col.BackgroundTransparency = 1
			col.Size = UDim2.new(1 / n, 0, 1, 0)
			col.Position = UDim2.new((i - 1) / n, 0, 0, 0)
			col.ZIndex = 12
			col.Parent = plot
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0.5, 1)
			bar.Position = UDim2.new(0.5, 0, 1, 0)
			bar.Size = UDim2.new(0.66, 0, v / max, v > 0 and 0 or 1)
			bar.BackgroundColor3 = color
			bar.BorderSizePixel = 0
			bar.ZIndex = 13
			bar.Parent = col
			if n <= 14 and v > 0 then
				label(col, { text = sep(v), size = UDim2.new(1, 12, 0, 12), position = UDim2.new(0.5, 0, 1 - v / max, -2),
					anchor = Vector2.new(0.5, 1), color = C.TEXT_GREY, textSize = IS_MOBILE and 8 or 10, zIndex = 15 })
			end
			if i % every == 0 or i == 1 or i == n then
				label(col, { text = d.l, size = UDim2.new(1, 16, 0, 12), position = UDim2.new(0.5, 0, 1, 3),
					anchor = Vector2.new(0.5, 0), color = C.TEXT_DIM, textSize = IS_MOBILE and 8 or 9, zIndex = 15 })
			end
		end
	end

	local screenEngage
	screenEngage = function(fresh)
		currentScreen = "engage"
		ST.token += 1
		local tok = ST.token
		if fresh then ST.cache = {} end
		local body = buildScreen("📨 INVITES & PUBS", true, BLUE, nil, function() ST.cache = {} ; screenEngage(false) end)
		local function alive() return ST.token == tok and currentScreen == "engage" and body.Parent ~= nil end
		acTabBar(body, 1, PERIODS, ST.p, BLUE_D, function(id) ST.p = id ; screenEngage(false) end)
		local loading = note(body, 2, "⏳ Chargement…")

		fetch(ST.p, function(res, err)
			if not alive() then return end
			loading:Destroy()
			if not res then note(body, 2, "⚠️ " .. tostring(err), C.RED) return end

			-- totaux de la période
			local T = {}
			for _, d in ipairs(res.days) do
				for k, n in pairs(d.v) do T[k] = (T[k] or 0) + (tonumber(n) or 0) end
			end
			local nDays = math.max(1, #res.days)
			local players = T.players_u or 0

			-- 👥
			local _, r0 = statCard(body, 3, "👥 JOUEURS", C.TURQUOISE)
			statRow(r0, 1, "Joueurs uniques / jour (moyenne)", sep(players / nDays))
			statRow(r0, 2, "Arrivées (connexions)", sep(T.joins))

			-- 📨
			local _, r1 = statCard(body, 4, "📨 INVITES", BLUE)
			statRow(r1, 1, "Prompts d'invite ouverts", sep(T.inv_open) .. "  (" .. sep(T.inv_open_u) .. " joueurs)")
			statRow(r1, 2, "% des joueurs qui ouvrent l'invite", pct(T.inv_open_u, players), BLUE)
			statRow(r1, 3, "Invitations envoyées (amis)", sep(T.inv_sent), GREEN)
			statRow(r1, 4, "Joueurs qui ont envoyé", sep(T.inv_sent_u))
			statRow(r1, 5, "Moyenne d'amis invités / joueur", avg(T.inv_sent, T.inv_sent_u))
			statRow(r1, 6, "Prompts avec au moins 1 ami", pct(T.inv_ok, T.inv_open))
			statRow(r1, 7, "Amis arrivés par invitation", sep(T.inv_join), GREEN)
			statRow(r1, 8, "Arrivés / invitations envoyées", pct(T.inv_join, T.inv_sent))
			statRow(r1, 9, "Points donnés (referral)", sep(T.ref_pts) .. " pts", ORANGE)
			statRow(r1, 10, "  ↳ parrains / filleuls payés", sep(T.ref_inviter) .. " / " .. sep(T.ref_invitee))
			bars(body, 5, res.days, "inv_sent", "📨 Invitations envoyées par jour", BLUE)

			-- 📺
			local _, r2 = statCard(body, 6, "📺 PUBS", ORANGE)
			statRow(r2, 1, "Pubs lancées", sep(T.ad_show) .. "  (" .. sep(T.ad_show_u) .. " joueurs)")
			statRow(r2, 2, "Regardées jusqu'au bout", sep(T.ad_done) .. "  (" .. pct(T.ad_done, T.ad_show) .. ")", GREEN)
			statRow(r2, 3, "Interrompues / erreurs", sep(T.ad_fail), C.TEXT_GREY)
			statRow(r2, 4, "Refusées (quota, pas prêt…)", sep(T.ad_deny), C.TEXT_GREY)
			statRow(r2, 5, "% des joueurs qui regardent", pct(T.ad_done_u, players), ORANGE)
			statRow(r2, 6, "Moyenne de pubs / joueur", avg(T.ad_done, T.ad_done_u))
			statRow(r2, 7, "Récompenses données", sep(T.ad_rew) .. "  (" .. sep(T.ad_rew_u) .. " joueurs)")
			statRow(r2, 8, "Points donnés (pubs)", sep(T.ad_pts) .. " pts", ORANGE)
			bars(body, 7, res.days, "ad_done", "📺 Pubs regardées par jour", ORANGE)

			note(body, 8, "Jours à l'heure de Montréal. Les joueurs uniques sont comptés une fois par jour : "
				.. "sur plusieurs jours, un joueur qui revient compte une fois par jour."
				.. (res.studio and "\n🧪 Studio : lecture seule, rien n'est compté ici." or ""), C.TEXT_DIM)
		end)
	end

	table.insert(ACTIONS, { id = "engage", name = "📨 INVITES & PUBS", color = BLUE })
	local previousOpenAction = openAction
	openAction = function(a)
		if a and a.id == "engage" then screenEngage(true) return end
		if previousOpenAction then return previousOpenAction(a) end
	end

	print("✅ Bloc 15 chargé — 📨 INVITES & PUBS")
end)()

