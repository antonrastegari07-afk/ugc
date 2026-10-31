--════════════════════════════════════════════════════════════════════════════
-- 📊 BLOC 15 — STATS   (v2 : REMPLACE le bloc 15 « INVITES & PUBS »)
--
--  📍 OÙ COLLER ? Dans « ADMIN PANEL — CLIENT », À LA PLACE de l'ancien bloc 15
--     (de sa ligne « 📨 BLOC 15 — INVITES & PUBS » jusqu'à son `end)()`),
--     donc toujours juste avant « 📜 BLOC 11 » (qui reste le DERNIER).
--  Bouton d'accueil : 📊 STATS. Données : script serveur « STATS » (v2).
--════════════════════════════════════════════════════════════════════════════
;(function()
	local BLUE   = Color3.fromRGB(110, 180, 255)
	local BLUE_D = Color3.fromRGB(40, 90, 150)
	local ORANGE = Color3.fromRGB(255, 170, 70)
	local GREEN  = Color3.fromRGB(90, 220, 140)
	local PINK   = Color3.fromRGB(255, 150, 220)
	local GOLD   = Color3.fromRGB(255, 205, 70)
	local SM = IS_MOBILE and 10 or 12

	local Cat
	pcall(function() Cat = require(ReplicatedStorage:WaitForChild("ProductCatalog", 15)) end)
	local function itemName(key)   -- "gp1891589121" / "dp3606598188"
		local id = tonumber(key:sub(3))
		local n = Cat and id and Cat.Name(id) or key
		return (key:sub(1, 2) == "gp" and "🎟️ " or "🛍️ ") .. n
	end

	local ST = { p = 7, cache = {}, token = 0 }
	local PERIODS = {
		{ id = 1, label = "Aujourd'hui" }, { id = 7, label = "7 jours" }, { id = 30, label = "30 jours" },
	}

	local function fetch(days, cb)
		local c = ST.cache[days]
		if c and os.clock() - c.at < 30 then cb(c.data) return end
		local fn = ReplicatedStorage:FindFirstChild("AdminEngage_Get")
		if not fn then cb(nil, "Le script serveur STATS n'est pas installé.") return end
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
	local function dur(sec)
		sec = math.floor(tonumber(sec) or 0)
		local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
		if h > 0 then return string.format("%d h %02d", h, m) end
		return string.format("%d min", m)
	end
	local function quant(list, q)
		if #list == 0 then return nil end
		local i = math.clamp(math.floor((#list - 1) * q + 1.5), 1, #list)
		return list[i]
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

	-- regroupe les compteurs « pr|source|objet », « by|source|objet », « rb|source »
	local function bySource(T)
		local S = {}
		local function get(src)
			local s = S[src]
			if not s then s = { src = src, pr = 0, by = 0, rb = 0, items = {} } S[src] = s end
			return s
		end
		for k, n in pairs(T) do
			local kind, src, item = k:match("^(%a%a)|(.-)|(%a%a%d+)$")
			if kind == "pr" or kind == "by" then
				local s = get(src)
				s[kind] += n
				local it = s.items[item]
				if not it then it = { pr = 0, by = 0 } s.items[item] = it end
				it[kind] += n
			else
				local src2 = k:match("^rb|(.+)$")
				if src2 then local g = get(src2) ; g.rb = g.rb + n end
			end
		end
		local list = {}
		for _, s in pairs(S) do table.insert(list, s) end
		table.sort(list, function(a, b)
			if a.rb ~= b.rb then return a.rb > b.rb end
			return a.pr > b.pr
		end)
		return list
	end

	local screenStats
	screenStats = function(fresh)
		currentScreen = "engage"
		ST.token += 1
		local tok = ST.token
		if fresh then ST.cache = {} end
		local body = buildScreen("📊 STATS", true, BLUE, nil, function() ST.cache = {} ; screenStats(false) end)
		local function alive() return ST.token == tok and currentScreen == "engage" and body.Parent ~= nil end
		acTabBar(body, 1, PERIODS, ST.p, BLUE_D, function(id) ST.p = id ; screenStats(false) end)
		local loading = note(body, 2, "⏳ Chargement…")

		fetch(ST.p, function(res, err)
			if not alive() then return end
			loading:Destroy()
			if not res then note(body, 2, "⚠️ " .. tostring(err), C.RED) return end

			local T, samples = {}, {}
			for _, d in ipairs(res.days) do
				for k, n in pairs(d.v) do
					if k == "ttu" then
						if type(n) == "table" then for _, s in ipairs(n) do table.insert(samples, s) end end
					elseif type(n) == "number" then
						T[k] = (T[k] or 0) + n
					end
				end
			end
			local nDays = math.max(1, #res.days)
			local players = T.players_u or 0
			local order = 3
			local function nextO() order += 1 return order end

			-- 👥 JOUEURS
			local _, r0 = statCard(body, nextO(), "👥 JOUEURS", C.TURQUOISE)
			statRow(r0, 1, "Joueurs uniques / jour (moyenne)", sep(players / nDays))
			statRow(r0, 2, "Arrivées (connexions)", sep(T.joins))
			statRow(r0, 3, "Jouent avec au moins 1 ami", pct(T.friend_u, players), BLUE)

			-- 💸 ACHATS PAR PROVENANCE
			local list = bySource(T)
			local _, r1 = statCard(body, nextO(), "💸 ACHATS — D'OÙ ILS VIENNENT", GREEN)
			statRow(r1, 1, "Fenêtres d'achat ouvertes", sep(T.pr_tot) .. "  (" .. sep(T.pr_u) .. " joueurs)")
			statRow(r1, 2, "Achats", sep(T.by_tot) .. "  (" .. sep(T.by_u) .. " acheteurs)", GREEN)
			statRow(r1, 3, "Conversion (achats / fenêtres)", pct(T.by_tot, T.pr_tot), GREEN)
			statRow(r1, 4, "Robux (prix affiché, avant la part Roblox)", sep(T.rb_tot) .. " R$", GOLD)
			statRow(r1, 5, "% des joueurs qui achètent", pct(T.by_u, players))
			local row = 10
			for _, s in ipairs(list) do
				row += 1
				statRow(r1, row, s.src, string.format("%s achat%s sur %s fenêtre%s (%s) · %s R$",
					sep(s.by), s.by == 1 and "" or "s", sep(s.pr), s.pr == 1 and "" or "s", pct(s.by, s.pr), sep(s.rb)),
					s.by > 0 and GREEN or C.TEXT_WHITE)
				local items = {}
				for key, it in pairs(s.items) do table.insert(items, { key = key, pr = it.pr, by = it.by }) end
				table.sort(items, function(a, b) if a.by ~= b.by then return a.by > b.by end return a.pr > b.pr end)
				for i = 1, math.min(#items, 6) do
					local it = items[i]
					row += 1
					statRow(r1, row, "      ↳ " .. itemName(it.key),
						string.format("%s achat%s sur %s fenêtre%s", sep(it.by), it.by == 1 and "" or "s",
							sep(it.pr), it.pr == 1 and "" or "s"), C.TEXT_GREY)
				end
			end
			if #list == 0 then statRow(r1, 11, "Aucune fenêtre d'achat sur cette période", "—", C.TEXT_DIM) end
			bars(body, nextO(), res.days, "rb_tot", "💸 Robux par jour (prix affiché)", GREEN)

			-- 🔔 POPUPS
			local _, r2 = statCard(body, nextO(), "🔔 POPUPS — VALENT-ILS LE COUP ?", PINK)
			local prow = 0
			local popIds = {}
			for id in pairs(res.popups or {}) do table.insert(popIds, id) end
			table.sort(popIds)
			for _, id in ipairs(popIds) do
				local p = res.popups[id]
				local shows, users = T["pop|" .. id] or 0, T["popu|" .. id] or 0
				local s
				for _, x in ipairs(list) do if x.src == p.src then s = x end end
				local buys, robux = s and s.by or 0, s and s.rb or 0
				prow += 1
				statRow(r2, prow, p.label, sep(shows) .. " affichages (" .. sep(users) .. " joueurs)", PINK)
				prow += 1
				statRow(r2, prow, "      ↳ achats via ce popup",
					string.format("%s (%s des affichages) · %s R$", sep(buys), pct(buys, shows), sep(robux)),
					buys > 0 and GREEN or C.TEXT_GREY)
				if id == "ad_button" then
					prow += 1
					statRow(r2, prow, "      ↳ pubs regardées", sep(T.ad_done) .. " (" .. pct(T.ad_done, shows) .. " des affichages)", ORANGE)
				end
			end
			prow += 1
			statRow(r2, prow, "Offres auto (coils, packs, morts, 20 min…)", "voir « D'où ils viennent »", C.TEXT_DIM)

			-- 🎽 1re UGC GRATUITE
			local _, r3 = statCard(body, nextO(), "🎽 1re UGC GRATUITE (joueurs 100 % gratuits)", GOLD)
			if #samples == 0 then
				statRow(r3, 1, "Pas encore de joueur mesuré sur cette période", "—", C.TEXT_DIM)
			else
				local pts, dcs, cds = {}, {}, {}
				local sumPt, sumDc = 0, 0
				for _, s in ipairs(samples) do
					table.insert(pts, tonumber(s.pt) or 0) ; table.insert(dcs, tonumber(s.dc) or 1)
					table.insert(cds, tonumber(s.cd) or 0)
					sumPt += tonumber(s.pt) or 0 ; sumDc += tonumber(s.dc) or 1
				end
				table.sort(pts) ; table.sort(dcs) ; table.sort(cds)
				statRow(r3, 1, "Joueurs mesurés", sep(#samples))
				statRow(r3, 2, "Temps de jeu — médiane", dur(quant(pts, 0.5)), GOLD)
				statRow(r3, 3, "Temps de jeu — moyenne", dur(sumPt / #samples))
				statRow(r3, 4, "Temps de jeu — 25 % / 75 % des joueurs", dur(quant(pts, 0.25)) .. "  →  " .. dur(quant(pts, 0.75)))
				statRow(r3, 5, "Jours de connexion — médiane", sep(quant(dcs, 0.5)) .. " j", GOLD)
				statRow(r3, 6, "Jours de connexion — moyenne", avg(sumDc, #samples) .. " j")
				statRow(r3, 7, "Jours calendaires depuis l'arrivée — médiane", sep(quant(cds, 0.5)) .. " j")
			end

			-- 📨 INVITES
			local _, r4 = statCard(body, nextO(), "📨 INVITES & AMIS", BLUE)
			statRow(r4, 1, "Fenêtres d'invitation ouvertes", sep(T.inv_open) .. "  (" .. sep(T.inv_open_u) .. " joueurs)")
			statRow(r4, 2, "% des joueurs qui invitent", pct(T.inv_open_u, players), BLUE)
			statRow(r4, 3, "Amis arrivés par une invitation", sep(T.inv_join), GREEN)
			statRow(r4, 4, "Arrivées par invitation / joueur qui invite", avg(T.inv_join, T.inv_open_u))
			statRow(r4, 5, "Points donnés (parrainage)", sep(T.ref_pts) .. " pts", ORANGE)
			statRow(r4, 6, "  ↳ parrains / filleuls payés", sep(T.ref_inviter) .. " / " .. sep(T.ref_invitee))

			-- 📺 PUBS
			local _, r5 = statCard(body, nextO(), "📺 PUBS", ORANGE)
			statRow(r5, 1, "Pubs lancées", sep(T.ad_show) .. "  (" .. sep(T.ad_show_u) .. " joueurs)")
			statRow(r5, 2, "Regardées jusqu'au bout", sep(T.ad_done) .. "  (" .. pct(T.ad_done, T.ad_show) .. ")", GREEN)
			statRow(r5, 3, "% des joueurs qui regardent", pct(T.ad_done_u, players), ORANGE)
			statRow(r5, 4, "Moyenne de pubs / joueur qui regarde", avg(T.ad_done, T.ad_done_u))
			statRow(r5, 5, "Points donnés (pubs)", sep(T.ad_pts) .. " pts", ORANGE)
			bars(body, nextO(), res.days, "ad_done", "📺 Pubs regardées par jour", ORANGE)

			note(body, nextO(), "Jours à l'heure de Montréal. « Achats / fenêtres » : une fenêtre = un prompt d'achat Roblox "
				.. "affiché (acheté ou annulé). Robux = prix affiché (Roblox en garde environ 30 %). "
				.. "1re UGC gratuite : seulement les joueurs arrivés après l'installation et qui n'ont jamais rien payé."
				.. (res.studio and "\n🧪 Studio : lecture seule, rien n'est compté ici." or ""), C.TEXT_DIM)
		end)
	end

	table.insert(ACTIONS, { id = "engage", name = "📊 STATS", color = BLUE })
	local previousOpenAction = openAction
	openAction = function(a)
		if a and a.id == "engage" then screenStats(true) return end
		if previousOpenAction then return previousOpenAction(a) end
	end

	print("✅ Bloc 15 chargé — 📊 STATS")
end)()

