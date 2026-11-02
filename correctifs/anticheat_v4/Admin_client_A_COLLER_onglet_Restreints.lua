	--════════════════════════════════════════════════════════════════
	-- 🚫 ONGLET « RESTREINTS »  (V4)
	--    Tous les joueurs privés d'UGC, avec la RAISON EXACTE de la
	--    sanction. Ils sortent des classements et arrivent ici.
	--    Recherche : pseudo, UserId, admin, ou mot de la raison.
	--════════════════════════════════════════════════════════════════
	local TYPE_FR_R = { FLY_STATE = "vol", FLY_HOVER = "vol stationnaire",
		FLY_ASCENT = "montée sans appui", FLY_UPSPEED = "montée trop rapide",
		TELEPORT = "téléportation", SPEED = "vitesse anormale" }

	local function reasonOf(r)
		if type(r.reasonText) == "string" and r.reasonText ~= "" then return r.reasonText end
		local d = tostring(r.details or "")
		if d == "" then d = tostring(r.reason or "?") end
		return d
	end

	local function restrictedCard(holder, order, rec)
		local uid = rec.userId
		local col = rec.auto and RED or PURPLE
		local name = rec.name or nameOf(uid) or ("UserId " .. tostring(uid))
		local _, rows = card(holder, order, (rec.auto and "🤖 " or "👮 ") .. esc(name), col)

		statLine(rows, 1, "🆔 UserId", tostring(uid), C.TEXT_GREY)
		statLine(rows, 2, "📅 Restreint",
			os.date("!%d/%m/%Y %H:%M", rec.at or 0) .. " UTC · " .. fmtAgo(rec.at or 0), C.TEXT_WHITE)
		statLine(rows, 3, "👮 Par", rec.auto and "anti-cheat (auto)" or tostring(rec.by or "?"), C.TEXT_GREY)
		if rec.confidence then
			statLine(rows, 4, "🎯 Certitude", tostring(rec.confidence) .. " %", confColor(rec.confidence))
		end
		statLine(rows, 5, "📊 Au moment T", string.format("%d warning(s) · %d détection(s)",
			rec.warnings or 0, rec.detections or 0), C.TEXT_GREY)
		if (rec.attempts or 0) > 0 then
			statLine(rows, 6, "🔁 Achats bloqués", tostring(rec.attempts), ORANGE)
		end
		if rec.until_ then
			statLine(rows, 7, "⏳ Fin", os.date("!%d/%m/%Y %H:%M", rec.until_) .. " UTC", GOLD)
		end
		statLine(rows, 8, "👁️ Panneau vu par le joueur", rec.noticeShown and "oui" or "pas encore",
			rec.noticeShown and GREEN or C.TEXT_GREY)
		if (rec.leaks or 0) > 0 then
			statLine(rows, 9, "🚨 UGC reçue(s) malgré la sanction", tostring(rec.leaks), RED)
		end

		note(rows, 10, "📝 RAISON\n" .. reasonOf(rec), col)

		if type(rec.signals) == "table" and #rec.signals > 0 then
			local lines = {}
			for _, sg in ipairs(rec.signals) do
				if type(sg) == "table" then
					table.insert(lines, string.format("• %s · %s — %s (%s %%)",
						sg.t and os.date("!%d/%m %H:%M", sg.t) or "?",
						TYPE_FR_R[sg.type] or tostring(sg.type or "?"),
						tostring(sg.details or ""), tostring(sg.conf or "?")))
				end
			end
			note(rows, 11, "🧾 Derniers signaux retenus\n" .. table.concat(lines, "\n"), C.TEXT_GREY)
		end

		local acts = Instance.new("Frame")
		acts.Size = UDim2.new(1, 0, 0, IS_MOBILE and 32 or 36)
		acts.BackgroundTransparency = 1
		acts.LayoutOrder = 12; acts.ZIndex = 13; acts.Parent = rows
		local g = Instance.new("UIGridLayout")
		g.CellSize = UDim2.new(0.5, -4, 1, 0)
		g.CellPadding = UDim2.new(0, 8, 0, 0)
		g.SortOrder = Enum.SortOrder.LayoutOrder
		g.Parent = acts

		local c1 = Instance.new("Frame")
		c1.LayoutOrder = 1; c1.BackgroundTransparency = 1; c1.ZIndex = 13; c1.Parent = acts
		local b1 = actionButton(c1, { color = CYAN, strokeColor = Color3.fromRGB(30, 100, 150),
			text = "🔍 Dossier", textSize = IS_MOBILE and 10 or 12, radius = 8, zIndex = 13 })
		b1.MouseButton1Click:Connect(function()
			ST.tab = "card" ; ST.cardFor = uid ; ST.cardData = nil
			screenACBoards_new()
		end)

		local c2 = Instance.new("Frame")
		c2.LayoutOrder = 2; c2.BackgroundTransparency = 1; c2.ZIndex = 13; c2.Parent = acts
		local b2, l2 = actionButton(c2, { color = GREEN, strokeColor = Color3.fromRGB(28, 122, 62),
			text = "✅ Lever", textColor = C.BG_BLACK, textSize = IS_MOBILE and 10 or 12,
			radius = 8, zIndex = 13 })
		local armed = false
		b2.MouseButton1Click:Connect(function()
			if not armed then
				armed = true
				if l2 then l2.Text = "⚠️ Confirmer" end
				task.delay(3, function()
					armed = false
					if l2 and l2.Parent then l2.Text = "✅ Lever" end
				end)
				return
			end
			armed = false
			callAC("remove", { userId = uid }, function(res)
				if res and res.msg then toast(res.msg, res.ok == true) end
				ST.restrList = nil ; CACHE.board = {} ; CACHE.restr[uid] = nil
				screenACBoards_new()
			end)
		end)
	end

	local function renderRestricted(body)
		local gr = acRemote("AdminGetUGCRestrict")
		if not gr then
			note(body, 0, "❌ AntiCheat_UGCRestrict manquant côté serveur.", RED)
			return
		end

		local status = Instance.new("Frame")
		status.Size = UDim2.new(1, 0, 0, 40)
		status.BackgroundTransparency = 1
		status.LayoutOrder = 0; status.ZIndex = 11; status.Parent = body
		local stl = label(status, { text = "Lecture de la liste...", size = UDim2.fromScale(1, 1),
			color = C.TEXT_GREY, textSize = IS_MOBILE and 12 or 15, zIndex = 11 })

		local function paint(entries)
			if not status.Parent then return end
			status:Destroy()
			local auto, manual = 0, 0
			for _, r in ipairs(entries) do
				if r.auto then auto = auto + 1 else manual = manual + 1 end
			end
			note(body, 1, string.format(
				"🚫 %d joueur(s) privé(s) d'UGC  ·  🤖 %d par l'anti-cheat  ·  👮 %d à la main\n\n"
					.. "Ils ne sont plus dans les classements : ils sont ici. Chaque fiche "
					.. "donne la raison exacte (type, mesure, position, outil en main, "
					.. "certitude) et les derniers signaux retenus.", #entries, auto, manual), PURPLE)

			local sw = Instance.new("Frame")
			sw.Size = UDim2.new(1, 0, 0, IS_MOBILE and 32 or 38)
			sw.BackgroundTransparency = 1
			sw.LayoutOrder = 2; sw.ZIndex = 11; sw.Parent = body
			local sb = Instance.new("TextBox")
			sb.Size = UDim2.new(1, 0, 1, 0)
			sb.BackgroundColor3 = C.BG_DARK
			sb.BorderSizePixel = 0
			sb.Font = FONT
			sb.PlaceholderText = "🔍 Pseudo, UserID, admin, ou mot de la raison (vol, téléport…)"
			sb.PlaceholderColor3 = C.TEXT_DIM
			sb.Text = ST.restrSearch or ""
			sb.TextColor3 = C.TEXT_WHITE
			sb.TextSize = IS_MOBILE and 11 or 14
			sb.TextXAlignment = Enum.TextXAlignment.Left
			sb.ClearTextOnFocus = false
			sb.ZIndex = 12
			sb.Parent = sw
			corner(sb, 8); stroke(sb, PURPLE, 1)
			local sp = Instance.new("UIPadding"); sp.PaddingLeft = UDim.new(0, 10); sp.Parent = sb

			local holder = Instance.new("Frame")
			holder.Size = UDim2.new(1, 0, 0, 0)
			holder.AutomaticSize = Enum.AutomaticSize.Y
			holder.BackgroundTransparency = 1
			holder.LayoutOrder = 3; holder.ZIndex = 11; holder.Parent = body
			local hl = Instance.new("UIListLayout")
			hl.Padding = UDim.new(0, IS_MOBILE and 6 or 9)
			hl.SortOrder = Enum.SortOrder.LayoutOrder
			hl.Parent = holder

			local function draw()
				for _, ch in ipairs(holder:GetChildren()) do
					if not ch:IsA("UIListLayout") then ch:Destroy() end
				end
				local q = tostring(ST.restrSearch or ""):lower()
				local list = {}
				for _, r in ipairs(entries) do
					local ok = true
					if #q > 0 then
						local hay = table.concat({
							tostring(r.name or ""), tostring(nameOf(r.userId) or ""),
							tostring(r.userId), tostring(r.by or ""),
							reasonOf(r), tostring(r.details or ""),
						}, " "):lower()
						ok = hay:find(q, 1, true) ~= nil
					end
					if ok then table.insert(list, r) end
				end
				table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
				if #list == 0 then
					label(holder, { text = (#entries == 0)
						and "✅ Personne n'est privé d'UGC pour l'instant."
						or "Rien ne correspond à cette recherche.",
						size = UDim2.new(1, 0, 0, 60), wrapped = true,
						color = C.TEXT_GREY, textSize = IS_MOBILE and 11 or 14, zIndex = 11 })
					return
				end
				--  On n'affiche que les 40 premiers : la recherche sert pour le reste.
				for i = 1, math.min(#list, 40) do restrictedCard(holder, i, list[i]) end
				if #list > 40 then
					label(holder, { text = string.format("… et %d autre(s). Affine la recherche.", #list - 40),
						size = UDim2.new(1, 0, 0, 30), color = C.TEXT_DIM,
						textSize = IS_MOBILE and 10 or 12, zIndex = 11 }).LayoutOrder = 9999
				end
			end
			sb:GetPropertyChangedSignal("Text"):Connect(function()
				ST.restrSearch = sb.Text ; draw()
			end)
			draw()
		end

		if ST.restrList and (os.clock() - (ST.restrAt or 0)) < 30 then
			paint(ST.restrList)
			return
		end
		task.spawn(function()
			local ok, res = pcall(function() return gr:InvokeServer(true, false) end)
			if not status.Parent then return end
			if not (ok and type(res) == "table" and res.ok) then
				stl.Text = "Lecture impossible. Appuie sur 🔄."
				return
			end
			ST.restrList = res.entries or {}
			ST.restrAt = os.clock()
			paint(ST.restrList)
		end)
	end

