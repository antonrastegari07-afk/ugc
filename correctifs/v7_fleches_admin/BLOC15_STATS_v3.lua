--════════════════════════════════════════════════════════════════════════════
-- 📊 BLOC 15 — STATS   (v3 : REMPLACE le bloc 15 v2)
--
--  📍 OÙ COLLER ? Dans « ADMIN PANEL — CLIENT », À LA PLACE de l'ancien bloc 15
--     (de sa ligne « 📊 BLOC 15 — STATS » jusqu'à son `end)()`),
--     donc toujours juste avant « 📜 BLOC 11 » (qui reste le DERNIER).
--  Bouton d'accueil : 📊 STATS. Deux onglets :
--    🎽 Joueurs & UGC  → script serveur « PLAYER UGC STATS » (nouveau)
--    💸 Achats & pubs  → script serveur « STATS » (v2, inchangé)
--  Tout est en tuiles et en barres : le chiffre important en gros, le détail
--  derrière « ℹ️ Comment lire ».
--════════════════════════════════════════════════════════════════════════════
;(function()
	local BLUE   = Color3.fromRGB(110, 180, 255)
	local BLUE_D = Color3.fromRGB(40, 90, 150)
	local ORANGE = Color3.fromRGB(255, 170, 70)
	local GREEN  = Color3.fromRGB(90, 220, 140)
	local PINK   = Color3.fromRGB(255, 150, 220)
	local GOLD   = Color3.fromRGB(255, 205, 70)
	local VIOLET = Color3.fromRGB(180, 140, 255)
	local GREY   = Color3.fromRGB(150, 150, 165)
	local SM = IS_MOBILE and 10 or 12
	local BIG = IS_MOBILE and 18 or 24

	local Cat
	pcall(function() Cat = require(ReplicatedStorage:WaitForChild("ProductCatalog", 15)) end)
	local function itemName(key)   -- "gp1891589121" / "dp3606598188"
		local id = tonumber(key:sub(3))
		local n = Cat and id and Cat.Name(id) or key
		return (key:sub(1, 2) == "gp" and "🎟️ " or "🛍️ ") .. n
	end

	local ST = { tab = "ugc", p = 7, scope = "all", away = 7, cache = {}, token = 0, help = {} }
	local PERIODS = {
		{ id = 1, label = "Aujourd'hui" }, { id = 7, label = "7 jours" }, { id = 30, label = "30 jours" },
	}

	--════════════════════════════════════════════════════════
	-- 📞 LECTURES
	--════════════════════════════════════════════════════════
	local function fetchFrom(remoteName, arg, key, ttl, cb)
		local c = ST.cache[key]
		if c and os.clock() - c.at < ttl then cb(c.data) return end
		local fn = ReplicatedStorage:FindFirstChild(remoteName)
		if not fn then
			cb(nil, remoteName == "AdminPlayerStats_Get"
				and "Le script serveur PLAYER UGC STATS n'est pas installé."
				or "Le script serveur STATS n'est pas installé.")
			return
		end
		task.spawn(function()
			for attempt = 1, 5 do
				local ok, res = pcall(function() return fn:InvokeServer(arg) end)
				if ok and type(res) == "table" and res.ok then
					ST.cache[key] = { data = res, at = os.clock() }
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
		local v = a / b * 100
		if v > 0 and v < 1 then return "<1 %" end
		return string.format("%.0f %%", v)
	end
	local function avg1(a, b)
		a, b = tonumber(a) or 0, tonumber(b) or 0
		if b <= 0 then return "—" end
		return string.format("%.1f", a / b)
	end
	local function dur(sec)
		sec = math.floor(tonumber(sec) or 0)
		local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
		if d > 0 then return string.format("%d j %d h", d, h) end
		if h > 0 then return string.format("%d h %02d", h, m) end
		return string.format("%d min", math.max(m, sec > 0 and 1 or 0))
	end
	local function quant(list, q)
		if #list == 0 then return nil end
		local i = math.clamp(math.floor((#list - 1) * q + 1.5), 1, #list)
		return list[i]
	end

	--════════════════════════════════════════════════════════
	-- 🧱 BRIQUES VISUELLES
	--════════════════════════════════════════════════════════
	local function card(parent, order, title, color)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.BackgroundColor3 = C.BG_DARK
		f.BorderSizePixel = 0
		f.LayoutOrder = order
		f.ZIndex = 11
		f.Parent = parent
		corner(f, 12) ; stroke(f, color or C.BORDER_SUBTLE, 1)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 10)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
		pad.Parent = f
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, IS_MOBILE and 5 or 7)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = f
		if title then
			local t = label(f, { text = title, size = UDim2.new(1, 0, 0, IS_MOBILE and 16 or 20),
				xAlign = Enum.TextXAlignment.Left, color = color or C.TEXT_WHITE,
				textSize = IS_MOBILE and 12 or 15, truncate = true, zIndex = 12 })
			t.LayoutOrder = 0
		end
		return f
	end

	-- « ℹ️ Comment lire » : le texte d'explication reste caché tant qu'on ne le demande pas
	local function help(parent, order, id, text)
		local open = ST.help[id] == true
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 0, 0)
		b.AutomaticSize = Enum.AutomaticSize.Y
		b.BackgroundTransparency = 1
		b.Text = ""
		b.LayoutOrder = order
		b.ZIndex = 12
		b.Parent = parent
		local l = label(b, { text = open and ("ℹ️ " .. text) or "ℹ️ Comment lire",
			size = UDim2.new(1, 0, 0, 0), xAlign = Enum.TextXAlignment.Left,
			color = C.TEXT_DIM, textSize = SM, wrapped = true, zIndex = 13 })
		l.AutomaticSize = Enum.AutomaticSize.Y
		b.MouseButton1Click:Connect(function()
			ST.help[id] = not open
			open = not open
			l.Text = open and ("ℹ️ " .. text) or "ℹ️ Comment lire"
		end)
	end

	-- une rangée de 2 à 4 tuiles : gros chiffre + légende courte
	local function tiles(parent, order, items)
		local h = IS_MOBILE and 54 or 68
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, h)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.ZIndex = 12
		row.Parent = parent
		local n = math.max(1, #items)
		local gap = 6
		for i, it in ipairs(items) do
			local t = Instance.new("Frame")
			t.Size = UDim2.new(1 / n, -gap * (n - 1) / n, 1, 0)
			t.Position = UDim2.new((i - 1) / n, (i - 1) * gap / n, 0, 0)
			t.BackgroundColor3 = C.BG_ITEM
			t.BorderSizePixel = 0
			t.ZIndex = 12
			t.Parent = row
			corner(t, 10) ; stroke(t, it.color or C.BORDER_SUBTLE, 1, 0.4)
			label(t, { text = tostring(it.value), size = UDim2.new(1, -8, 0.58, 0), position = UDim2.new(0, 4, 0, 4),
				color = it.color or C.TEXT_WHITE, textSize = BIG, truncate = true, zIndex = 13 })
			local cap = label(t, { text = it.label, size = UDim2.new(1, -8, 0.4, -4), position = UDim2.new(0, 4, 0.58, 0),
				color = C.TEXT_GREY, textSize = IS_MOBILE and 9 or 11, wrapped = true, zIndex = 13 })
			cap.TextYAlignment = Enum.TextYAlignment.Top
		end
		return row
	end

	-- une barre horizontale : libellé · barre · valeur
	local function hbar(parent, order, text, frac, color, valueText)
		local h = IS_MOBILE and 20 or 24
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, h)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.ZIndex = 12
		row.Parent = parent
		label(row, { text = text, size = UDim2.new(0.34, -4, 1, 0), xAlign = Enum.TextXAlignment.Left,
			color = C.TEXT_WHITE, textSize = SM, truncate = true, zIndex = 13 })
		local track = Instance.new("Frame")
		track.Size = UDim2.new(0.42, -4, 0, IS_MOBILE and 10 or 12)
		track.Position = UDim2.new(0.34, 0, 0.5, 0)
		track.AnchorPoint = Vector2.new(0, 0.5)
		track.BackgroundColor3 = C.BG_ITEM
		track.BorderSizePixel = 0
		track.ZIndex = 13
		track.Parent = row
		corner(track, 6)
		frac = math.clamp(tonumber(frac) or 0, 0, 1)
		if frac > 0 then
			local fill = Instance.new("Frame")
			fill.Size = UDim2.new(math.max(frac, 0.02), 0, 1, 0)
			fill.BackgroundColor3 = color or BLUE
			fill.BorderSizePixel = 0
			fill.ZIndex = 14
			fill.Parent = track
			corner(fill, 6)
		end
		label(row, { text = valueText or "", size = UDim2.new(0.24, 0, 1, 0), position = UDim2.new(0.76, 0, 0, 0),
			xAlign = Enum.TextXAlignment.Right, color = color or C.TEXT_WHITE, textSize = SM, truncate = true, zIndex = 13 })
		return row
	end

	-- une barre empilée (répartition) + sa légende
	local function stack(parent, order, text, parts)
		local wrap = Instance.new("Frame")
		wrap.Size = UDim2.new(1, 0, 0, IS_MOBILE and 34 or 40)
		wrap.BackgroundTransparency = 1
		wrap.LayoutOrder = order
		wrap.ZIndex = 12
		wrap.Parent = parent
		label(wrap, { text = text, size = UDim2.new(1, 0, 0, IS_MOBILE and 13 or 15), xAlign = Enum.TextXAlignment.Left,
			color = C.TEXT_WHITE, textSize = SM, truncate = true, zIndex = 13 })
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 0, IS_MOBILE and 14 or 18)
		bar.Position = UDim2.new(0, 0, 1, 0)
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.BackgroundColor3 = C.BG_ITEM
		bar.BorderSizePixel = 0
		bar.ClipsDescendants = true
		bar.ZIndex = 13
		bar.Parent = wrap
		corner(bar, 6)
		local x = 0
		for _, p in ipairs(parts) do
			local w = math.clamp(tonumber(p.frac) or 0, 0, 1)
			if w > 0 then
				local s = Instance.new("Frame")
				s.Size = UDim2.new(w, 0, 1, 0)
				s.Position = UDim2.new(x, 0, 0, 0)
				s.BackgroundColor3 = p.color
				s.BorderSizePixel = 0
				s.ZIndex = 14
				s.Parent = bar
				if w >= 0.12 then
					label(s, { text = p.short or "", size = UDim2.fromScale(1, 1), color = Color3.new(0, 0, 0),
						textSize = IS_MOBILE and 8 or 10, truncate = true, zIndex = 15 })
				end
				x += w
			end
		end
		return wrap
	end

	local function legend(parent, order, parts)
		local t = {}
		for _, p in ipairs(parts) do
			table.insert(t, string.format('<font color="#%s">■</font> %s', p.color:ToHex(), p.label))
		end
		local l = label(parent, { text = table.concat(t, "   "), size = UDim2.new(1, 0, 0, 0), richText = true,
			xAlign = Enum.TextXAlignment.Left, color = C.TEXT_GREY, textSize = SM, wrapped = true, zIndex = 13 })
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.LayoutOrder = order
		return l
	end

	local function chips(parent, order, items, selected, color, onPick)
		return acTabBar(parent, order, items, selected, color, onPick)
	end

	local function statusNote(parent, order, text, color)
		local f = card(parent, order, nil, color)
		local l = label(f, { text = text, size = UDim2.new(1, 0, 0, 0), xAlign = Enum.TextXAlignment.Left,
			color = color or C.TEXT_GREY, textSize = SM, wrapped = true, zIndex = 12 })
		l.AutomaticSize = Enum.AutomaticSize.Y
		return f
	end

	-- histogramme par jour (onglet achats)
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

	--════════════════════════════════════════════════════════
	-- 🎽 ONGLET JOUEURS & UGC
	--════════════════════════════════════════════════════════
	local TYPES = {
		{ id = 0, label = "🆓 Sans pass",     color = GREY },
		{ id = 1, label = "👑 VIP",           color = GOLD },
		{ id = 2, label = "⚡ Boost perm.",   color = BLUE },
		{ id = 3, label = "👑⚡ VIP + boost", color = VIOLET },
	}
	local U_BUCKETS = {   -- ce qu'on montre : 0, 1, 2, 3, 4-5, 6-9, 10+
		{ lo = 0, hi = 0, label = "0 UGC" }, { lo = 1, hi = 1, label = "1 UGC" },
		{ lo = 2, hi = 2, label = "2 UGC" }, { lo = 3, hi = 3, label = "3 UGC" },
		{ lo = 4, hi = 5, label = "4 – 5" }, { lo = 6, hi = 9, label = "6 – 9" },
		{ lo = 10, hi = 10, label = "10 et +" },
	}
	local function typeOf(f) -- 0 sans pass · 1 VIP · 2 boost · 3 VIP + boost
		f = math.floor(tonumber(f) or 0)
		local vip = f % 2 == 1
		local boost = f >= 2
		return (vip and 1 or 0) + (boost and 2 or 0)
	end
	local function dayIndex(dk)
		local y, m, d = tonumber(dk:sub(1, 4)), tonumber(dk:sub(5, 6)), tonumber(dk:sub(7, 8))
		if not (y and m and d) then return nil end
		return math.floor(os.time({ year = y, month = m, day = d, hour = 12 }) / 86400)
	end

	-- additionne les cases selon le filtre : "all" · "active" (vus il y a < away j) · "gone" (≥ away j)
	local function crunch(res, scope, away)
		local T = { n = 0, ugc = 0, withU = 0, u = {}, types = {}, vipx2 = 0 }
		for i = 0, 3 do T.types[i] = { n = 0, ugc = 0, withU = 0, u = {} } end
		local t0 = dayIndex(res.today or "") or 0
		for dk, cells in pairs(res.last or {}) do
			local di = dayIndex(dk)
			local ago = di and (t0 - di) or 0
			local keep = (scope == "all") or (scope == "active" and ago < away) or (scope == "gone" and ago >= away)
			if keep then
				for c, n in pairs(cells) do
					n = tonumber(n) or 0
					local f, u = c:match("^(%d+)|(%d+)$")
					f, u = tonumber(f), tonumber(u)
					if f and u and n ~= 0 then
						local ty = T.types[typeOf(f)]
						T.n += n ; ty.n += n
						T.ugc += n * u ; ty.ugc += n * u
						T.u[u] = (T.u[u] or 0) + n ; ty.u[u] = (ty.u[u] or 0) + n
						if u > 0 then T.withU += n ; ty.withU += n end
						if f % 2 == 1 and math.floor(f / 2) % 2 == 1 then T.vipx2 += n end
					end
				end
			end
		end
		return T
	end
	local function inBucket(t, b)
		local n = 0
		for u = b.lo, b.hi do n += math.max(0, t.u[u] or 0) end
		return n
	end

	local function renderUGC(body, order0)
		local order = order0
		local function nextO() order += 1 return order end
		local loading = statusNote(body, nextO(), "⏳ Chargement…")
		fetchFrom("AdminPlayerStats_Get", false, "ugc", 60, function(res, err)
			if not loading.Parent then return end
			loading:Destroy()
			if not res then statusNote(body, nextO(), "⚠️ " .. tostring(err), C.RED) return end

			-- 🎚️ qui on regarde
			local awayLbl = "Partis (+" .. ST.away .. " j)"
			chips(body, nextO(), {
				{ id = "all", label = "👥 Tous" }, { id = "active", label = "🟢 Actifs" }, { id = "gone", label = "💤 " .. awayLbl },
			}, ST.scope, BLUE_D, function(id) ST.scope = id ; ST.redraw() end)
			chips(body, nextO(), {
				{ id = 3, label = "3 j" }, { id = 7, label = "7 j" }, { id = 14, label = "14 j" }, { id = 30, label = "30 j" },
			}, ST.away, C.BG_LIGHT, function(id) ST.away = id ; ST.redraw() end)

			local T = crunch(res, ST.scope, ST.away)
			if not res.bf or not res.bf.done then
				statusNote(body, nextO(), string.format("📥 Les anciens joueurs sont en train d'être ajoutés (%s déjà). "
					.. "Les chiffres se complètent tout seuls dans les prochaines heures.", sep(res.bf and res.bf.n or 0)), ORANGE)
			end
			if res.studio then statusNote(body, nextO(), "🧪 Studio : lecture seule, rien n'est compté ici.", C.TEXT_DIM) end
			if T.n <= 0 then
				statusNote(body, nextO(), "Pas encore de joueur dans ce filtre.", C.TEXT_DIM)
				return
			end

			-- ① L'ESSENTIEL
			local c1 = card(body, nextO(), ST.scope == "gone" and ("💤 Joueurs partis (pas revenus depuis " .. ST.away .. " j)")
				or (ST.scope == "active" and ("🟢 Joueurs actifs (venus ces " .. ST.away .. " derniers jours)") or "👥 Tous les joueurs"), BLUE)
			tiles(c1, 1, {
				{ value = sep(T.n), label = "joueurs", color = C.TEXT_WHITE },
				{ value = pct(T.n - T.withU, T.n), label = "n'ont AUCUNE UGC", color = C.RED },
				{ value = pct(T.withU, T.n), label = "ont au moins 1 UGC", color = GREEN },
				{ value = avg1(T.ugc, T.n), label = "UGC en moyenne", color = PINK },
			})

			-- ② COMBIEN D'UGC ?
			local c2 = card(body, nextO(), "🎽 Combien d'UGC ont-ils ?", PINK)
			for i, b in ipairs(U_BUCKETS) do
				local n = inBucket(T, b)
				hbar(c2, i, b.label, n / T.n, b.lo == 0 and C.RED or PINK, pct(n, T.n) .. "  ·  " .. sep(n))
			end

			-- ③ PAR TYPE DE JOUEUR
			local c3 = card(body, nextO(), "🏷️ Par type de joueur", GOLD)
			tiles(c3, 1, {
				{ value = pct(T.types[1].n + T.types[3].n, T.n), label = "ont le 👑 VIP", color = GOLD },
				{ value = pct(T.types[2].n + T.types[3].n, T.n), label = "ont un ⚡ boost permanent", color = BLUE },
				{ value = pct(T.vipx2, T.n), label = "ont 👑 VIP + ⚡ x2", color = VIOLET },
			})
			local row = 1
			for _, ty in ipairs(TYPES) do
				local t = T.types[ty.id]
				if t.n > 0 then
					row += 1
					hbar(c3, row, ty.label, t.withU / t.n, ty.color,
						"moy. " .. avg1(t.ugc, t.n) .. " UGC  ·  " .. sep(t.n) .. " joueurs")
				end
			end
			help(c3, 99, "types", "Barre = part des joueurs de ce type qui ont au moins 1 UGC. « moy. » = UGC par joueur. "
				.. "Boost permanent = x2, x5 ou x10 (acheté ou offert).")

			-- ④ AVANT DE PARTIR (seulement les joueurs partis)
			local G = (ST.scope == "gone") and T or crunch(res, "gone", ST.away)
			local c4 = card(body, nextO(), "💤 Combien d'UGC avant d'arrêter de jouer ?", ORANGE)
			local PARTS = {
				{ lo = 0, hi = 0, color = C.RED, label = "0", short = "0" },
				{ lo = 1, hi = 1, color = ORANGE, label = "1", short = "1" },
				{ lo = 2, hi = 2, color = GOLD, label = "2", short = "2" },
				{ lo = 3, hi = 5, color = GREEN, label = "3 – 5", short = "3-5" },
				{ lo = 6, hi = 10, color = BLUE, label = "6 et +", short = "6+" },
			}
			if G.n <= 0 then
				statusNote(c4, 1, "Personne n'est parti depuis " .. ST.away .. " j (ou pas encore assez de recul).", C.TEXT_DIM)
			else
				local function partsOf(t)
					local out = {}
					for _, p in ipairs(PARTS) do
						table.insert(out, { frac = inBucket(t, p) / math.max(1, t.n), color = p.color, short = p.short })
					end
					return out
				end
				stack(c4, 1, "👥 Tous  ·  " .. sep(G.n) .. " partis  ·  moy. " .. avg1(G.ugc, G.n) .. " UGC", partsOf(G))
				local r = 1
				for _, ty in ipairs(TYPES) do
					local t = G.types[ty.id]
					if t.n > 0 then
						r += 1
						stack(c4, r, ty.label .. "  ·  " .. sep(t.n) .. "  ·  moy. " .. avg1(t.ugc, t.n), partsOf(t))
					end
				end
				legend(c4, 90, (function()
					local l = {}
					for _, p in ipairs(PARTS) do table.insert(l, { color = p.color, label = p.label .. " UGC" }) end
					return l
				end)())
			end
			help(c4, 99, "gone", "Un joueur « parti » n'est pas revenu depuis le nombre de jours choisi en haut "
				.. "(3, 7, 14 ou 30). On regarde combien d'UGC il avait à sa dernière visite.")

			-- ⑤ TEMPS POUR AVOIR UNE UGC
			local c5 = card(body, nextO(), "⏱️ Temps de jeu pour avoir une UGC", GREEN)
			local ord = {}
			local byType1 = {}
			for k, v in pairs(res.ttu or {}) do
				local f, o = tostring(k):match("^(%d+)|(%d+)$")
				f, o = tonumber(f), tonumber(o)
				if f and o and type(v) == "table" then
					local x = ord[o] or { 0, 0, 0, 0 }
					for j = 1, 4 do x[j] += tonumber(v[j]) or 0 end
					ord[o] = x
					if o == 1 then
						local ty = typeOf(f)
						local y = byType1[ty] or { 0, 0 }
						y[1] += tonumber(v[1]) or 0 ; y[2] += tonumber(v[2]) or 0
						byType1[ty] = y
					end
				end
			end
			local maxT = 0
			for o = 1, 5 do
				local x = ord[o]
				if x and x[1] > 0 then maxT = math.max(maxT, x[2] / x[1]) end
			end
			if maxT <= 0 then
				statusNote(c5, 1, "Pas encore mesuré : il faut qu'un joueur obtienne une UGC après l'installation.", C.TEXT_DIM)
			else
				local names = { "1re UGC", "2e UGC", "3e UGC", "4e UGC", "5e et +" }
				for o = 1, 5 do
					local x = ord[o]
					if x and x[1] > 0 then
						local a = x[2] / x[1]
						hbar(c5, o, names[o], a / maxT, GREEN, dur(a) .. "  ·  " .. sep(x[1]))
					end
				end
				local d1 = ord[1]
				if d1 and d1[3] > 0 then
					tiles(c5, 20, {
						{ value = string.format("%.1f j", d1[4] / d1[3]), label = "jours réels avant la 1re UGC (nouveaux joueurs)", color = GREEN },
						{ value = sep(d1[3]), label = "nouveaux joueurs mesurés", color = C.TEXT_WHITE },
					})
				end
				local r = 30
				local maxTy = 0
				for _, y in pairs(byType1) do if y[1] > 0 then maxTy = math.max(maxTy, y[2] / y[1]) end end
				for _, ty in ipairs(TYPES) do
					local y = byType1[ty.id]
					if y and y[1] > 0 then
						r += 1
						hbar(c5, r, "1re · " .. ty.label, (y[2] / y[1]) / math.max(maxTy, 1), ty.color, dur(y[2] / y[1]))
					end
				end
			end
			help(c5, 99, "ttu", "Temps de JEU (pas les jours) entre deux UGC : 1re = depuis le tout début, "
				.. "2e = depuis la 1re, etc. Le petit nombre à droite = UGC mesurées. Compté depuis l'installation.")
		end)
	end

	--════════════════════════════════════════════════════════
	-- 💸 ONGLET ACHATS & PUBS (données du script STATS v2)
	--════════════════════════════════════════════════════════
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

	local function renderBuy(body, order0)
		local order = order0
		local function nextO() order += 1 return order end
		chips(body, nextO(), PERIODS, ST.p, BLUE_D, function(id) ST.p = id ; ST.redraw() end)
		local loading = statusNote(body, nextO(), "⏳ Chargement…")
		fetchFrom("AdminEngage_Get", ST.p, "buy" .. ST.p, 30, function(res, err)
			if not loading.Parent then return end
			loading:Destroy()
			if not res then statusNote(body, nextO(), "⚠️ " .. tostring(err), C.RED) return end

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

			-- 👥 + 💸 L'ESSENTIEL
			local c1 = card(body, nextO(), "💸 L'essentiel", GREEN)
			tiles(c1, 1, {
				{ value = sep(players / nDays), label = "joueurs / jour", color = C.TEXT_WHITE },
				{ value = sep(T.by_tot), label = "achats", color = GREEN },
				{ value = pct(T.by_u, players), label = "des joueurs achètent", color = GREEN },
				{ value = sep(T.rb_tot), label = "Robux (prix affiché)", color = GOLD },
			})
			tiles(c1, 2, {
				{ value = pct(T.by_tot, T.pr_tot), label = "fenêtres d'achat → achat", color = GREEN },
				{ value = pct(T.friend_u, players), label = "jouent avec un ami", color = BLUE },
			})
			bars(body, nextO(), res.days, "rb_tot", "💸 Robux par jour", GREEN)

			-- 🧭 D'OÙ VIENNENT LES ACHATS (Robux par provenance)
			local list = bySource(T)
			local c2 = card(body, nextO(), "🧭 D'où viennent les Robux", GOLD)
			local maxRb = 0
			for _, s in ipairs(list) do maxRb = math.max(maxRb, s.rb) end
			local shown = 0
			for _, s in ipairs(list) do
				if shown >= 10 then break end
				if s.rb > 0 or s.by > 0 then
					shown += 1
					hbar(c2, shown, s.src, maxRb > 0 and s.rb / maxRb or 0, GOLD,
						sep(s.rb) .. " R$  ·  " .. sep(s.by) .. " achat" .. (s.by == 1 and "" or "s"))
				end
			end
			if shown == 0 then statusNote(c2, 1, "Aucun achat sur cette période", C.TEXT_DIM) end
			-- le détail par objet, seulement si on le demande
			if shown > 0 then
				local open = ST.help.items == true
				local b = Instance.new("TextButton")
				b.Size = UDim2.new(1, 0, 0, IS_MOBILE and 22 or 26)
				b.BackgroundColor3 = C.BG_ITEM ; b.BorderSizePixel = 0 ; b.AutoButtonColor = false
				b.Font = FONT ; b.TextSize = SM ; b.TextColor3 = C.TEXT_GREY
				b.Text = open and "▲ Cacher le détail par objet" or "▼ Détail par objet"
				b.LayoutOrder = 50 ; b.ZIndex = 13 ; b.Parent = c2
				corner(b, 8)
				b.MouseButton1Click:Connect(function() ST.help.items = not open ; ST.redraw() end)
				if open then
					local r = 50
					for _, s in ipairs(list) do
						local items = {}
						for key, it in pairs(s.items) do if it.by > 0 then table.insert(items, { key = key, by = it.by, pr = it.pr }) end end
						table.sort(items, function(a, b2) return a.by > b2.by end)
						for i = 1, math.min(#items, 4) do
							r += 1
							local it = items[i]
							hbar(c2, r, "↳ " .. itemName(it.key), it.by / math.max(1, it.pr), C.TEXT_GREY,
								sep(it.by) .. "/" .. sep(it.pr) .. " fen.")
						end
					end
				end
			end
			help(c2, 99, "src", "Barre = Robux venus de cet endroit (prix affiché, Roblox en garde environ 30 %). "
				.. "Une « fenêtre » = la fenêtre d'achat Roblox affichée (achetée ou annulée).")

			-- 🔔 POPUPS
			local c3 = card(body, nextO(), "🔔 Popups : est-ce qu'ils rapportent ?", PINK)
			local popIds = {}
			for id in pairs(res.popups or {}) do table.insert(popIds, id) end
			table.sort(popIds)
			for i, id in ipairs(popIds) do
				local p = res.popups[id]
				local shows = T["pop|" .. id] or 0
				local s
				for _, x in ipairs(list) do if x.src == p.src then s = x end end
				local buys, robux = s and s.by or 0, s and s.rb or 0
				hbar(c3, i, p.label, shows > 0 and buys / shows or 0, buys > 0 and GREEN or PINK,
					sep(buys) .. " achats / " .. sep(shows) .. "  ·  " .. sep(robux) .. " R$")
			end
			help(c3, 99, "pop", "Barre = achats ÷ affichages du popup. Les offres automatiques (coils, packs…) "
				.. "sont dans « D'où viennent les Robux ».")

			-- 🎽 1re UGC GRATUITE
			local c4 = card(body, nextO(), "🎽 1re UGC gratuite (joueurs qui n'ont rien payé)", GOLD)
			if #samples == 0 then
				statusNote(c4, 1, "Pas encore de joueur mesuré sur cette période", C.TEXT_DIM)
			else
				local pts, dcs = {}, {}
				for _, s in ipairs(samples) do
					table.insert(pts, tonumber(s.pt) or 0) ; table.insert(dcs, tonumber(s.dc) or 1)
				end
				table.sort(pts) ; table.sort(dcs)
				tiles(c4, 1, {
					{ value = dur(quant(pts, 0.5)), label = "de jeu (joueur typique)", color = GOLD },
					{ value = sep(quant(dcs, 0.5)) .. " j", label = "jours de connexion", color = GOLD },
					{ value = sep(#samples), label = "joueurs mesurés", color = C.TEXT_WHITE },
				})
				help(c4, 99, "free", "« Joueur typique » = la médiane : la moitié des joueurs l'ont eue plus vite, "
					.. "l'autre moitié plus lentement. 25 % / 75 % : " .. dur(quant(pts, 0.25)) .. " → " .. dur(quant(pts, 0.75)) .. ".")
			end

			-- 📨 INVITES + 📺 PUBS
			local c5 = card(body, nextO(), "📨 Invites", BLUE)
			tiles(c5, 1, {
				{ value = pct(T.inv_open_u, players), label = "des joueurs invitent", color = BLUE },
				{ value = sep(T.inv_join), label = "amis arrivés par invitation", color = GREEN },
				{ value = sep(T.ref_pts), label = "points de parrainage donnés", color = ORANGE },
			})
			local c6 = card(body, nextO(), "📺 Pubs", ORANGE)
			tiles(c6, 1, {
				{ value = pct(T.ad_done_u, players), label = "des joueurs regardent", color = ORANGE },
				{ value = sep(T.ad_done), label = "pubs vues en entier", color = GREEN },
				{ value = pct(T.ad_done, T.ad_show), label = "vont jusqu'au bout", color = C.TEXT_WHITE },
			})
			bars(body, nextO(), res.days, "ad_done", "📺 Pubs regardées par jour", ORANGE)
			if res.studio then statusNote(body, nextO(), "🧪 Studio : lecture seule, rien n'est compté ici.", C.TEXT_DIM) end
		end)
	end

	--════════════════════════════════════════════════════════
	-- 🖥️ L'ÉCRAN
	--════════════════════════════════════════════════════════
	local screenStats
	screenStats = function(fresh)
		currentScreen = "engage"
		ST.token += 1
		local tok = ST.token
		if fresh then ST.cache = {} end
		local body = buildScreen("📊 STATS", true, BLUE, nil, function() ST.cache = {} ; screenStats(false) end)
		ST.redraw = function() if ST.token == tok and currentScreen == "engage" then screenStats(false) end end
		acTabBar(body, 1, {
			{ id = "ugc", label = "🎽 Joueurs & UGC" }, { id = "buy", label = "💸 Achats & pubs" },
		}, ST.tab, BLUE, function(id) ST.tab = id ; screenStats(false) end)
		if ST.tab == "ugc" then renderUGC(body, 10) else renderBuy(body, 10) end
	end

	table.insert(ACTIONS, { id = "engage", name = "📊 STATS", color = BLUE })
	local previousOpenAction = openAction
	openAction = function(a)
		if a and a.id == "engage" then screenStats(true) return end
		if previousOpenAction then return previousOpenAction(a) end
	end

	print("✅ Bloc 15 chargé — 📊 STATS (v3 : 🎽 Joueurs & UGC + 💸 Achats & pubs)")
end)()
