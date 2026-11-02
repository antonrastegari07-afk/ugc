-- ════════════════════════════════════════════════════════════════
-- 👀 TOUTES LES FAUX (effets chez moi pour chaque joueur)
--    Faux des AUTRES : les effets sont posés quand
--      • ses pièces sont TOUTES arrivées par le réseau (avant : posés trop tôt → abandon, aucun effet)
--      • et qu'elle est PROCHE de ma caméra (retirés quand elle s'éloigne : aucun coût de loin)
-- ════════════════════════════════════════════════════════════════
local NEAR = Config.OthersFXDistance or 120          -- studs : effets visibles en dessous
local FAR = NEAR * 1.2                               -- studs : effets retirés au-dessus (pas de clignotement)
local others = {}                                    -- [tool] = { char, conns, lastAdd, addedAt, on, dirty }

local function structural(d)
	if d.Name:sub(1, 3) == "FX_" then return false end   -- nos propres effets ne comptent pas
	return d:IsA("BasePart") or d:IsA("Attachment") or d:IsA("JointInstance")
		or d:IsA("SurfaceAppearance") or d:IsA("SurfaceGui")
end
local function partsOk(t)
	return t:FindFirstChild("Handle") and t:FindFirstChild("Head") and t:FindFirstChild("Blade") and true or false
end

local function forgetOther(t)
	local o = others[t]
	if not o then return end
	others[t] = nil
	for _, c in ipairs(o.conns) do c:Disconnect() end
	if o.on then FX.Detach(t) end
end

local function trackOther(t, char)
	if others[t] then return end
	local now = os.clock()
	local o = { char = char, conns = {}, lastAdd = now, addedAt = now, on = false, dirty = false }
	others[t] = o
	-- une pièce arrive en retard : on attend qu'il n'en arrive plus, puis on repose les effets
	table.insert(o.conns, t.DescendantAdded:Connect(function(d)
		if not structural(d) then return end
		o.lastAdd = os.clock()
		if o.on then o.dirty = true end
	end))
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then return end
	acc = 0
	local cam = workspace.CurrentCamera
	local from = cam and cam.CFrame.Position
	local now = os.clock()
	for t, o in pairs(others) do
		if t.Parent ~= o.char or not o.char.Parent then
			forgetOther(t)
		else
			local handle = t:FindFirstChild("Handle")
			local ok = partsOk(t)
			local dist = (from and handle) and (handle.Position - from).Magnitude or math.huge
			if o.on and (o.dirty or not ok or dist > FAR) then
				FX.Detach(t)
				o.on, o.dirty = false, false
			end
			if not o.on and ok and dist <= NEAR and now - o.lastAdd > 0.4 then
				if FX.Attach(t, false) then
					o.on = true
					-- elle vient d'être sortie : petite apparition, comme avant
					if now - o.addedAt < 2.5 then FX.Equip(t, false) end
				end
			end
		end
	end
end)

local function watchCharacter(plr, char)
	local mine = (plr == player)
	char.ChildAdded:Connect(function(t)
		if not isScythe(t) then return end
		if mine then
			FX.Attach(t, true)
			task.spawn(equip, t, char)
		else
			trackOther(t, char)
		end
	end)
	char.ChildRemoved:Connect(function(t)
		if not isScythe(t) then return end
		if mine then
			FX.Detach(t)
			if cur.tool == t then unequip() end
		else
			forgetOther(t)
		end
	end)
	for _, t in ipairs(char:GetChildren()) do
		if isScythe(t) then
			if mine then
				FX.Attach(t, true)
				task.spawn(equip, t, char)
			else
				trackOther(t, char)
				others[t].addedAt = -99      -- déjà en main avant mon arrivée : pas d'animation de sortie
			end
		end
	end
	if mine then
		-- nouveau personnage : l'ancienne faux (et le bouton DASH mobile) ne restent jamais branchés
		if cur.tool and cur.tool.Parent ~= char then unequip() end
		-- précharge les animations dès l'apparition (la 1re sortie est instantanée aussi)
		task.spawn(function()
			if char.Parent and not trackCache[char] then tracksFor(char) end
		end)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			-- mort : la faux tombe avec le personnage (Roblox ne signale pas toujours qu'elle a été rangée)
			hum.Died:Connect(function()
				if cur.tool and cur.tool:IsDescendantOf(char) then unequip() end
			end)
			hum.StateChanged:Connect(function(_, new)
				if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then airLeft = D.AirDashes or 1 end
			end)
		end
	end
end

local function watchPlayer(plr)
	plr.CharacterAdded:Connect(function(c) watchCharacter(plr, c) end)
	if plr.Character then watchCharacter(plr, plr.Character) end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(watchPlayer, p) end

-- effets du dash des autres joueurs (le serveur relaie seulement un « il a dashé ») : seulement si elle est proche
remote.OnClientEvent:Connect(function(kind, who, dir)
	if kind == "FX" and typeof(who) == "Instance" and who:IsA("Player") and who ~= player then
		local c = who.Character
		if not c then return end
		for _, t in ipairs(c:GetChildren()) do
			if isScythe(t) then
				if FX.Get(t) then FX.Dash(t, c, dir, false) end
				break
			end
		end
	end
end)
