--[[
	DeathCam  (LocalScript)
	Emplacement : StarterPlayer > StarterPlayerScripts > DeathCam

	Quand tu meurs en arène tué par un joueur, tu vois EXACTEMENT ce que voit ton tueur pendant 5 s :
	  • sa caméra, ses bras et son arme 1re personne image par image : TOUTES les pièces qui bougent
	    (barillet, chien, culasse, speedloader, cartouches, chargeur…) et celles qu'il voit cachées / visibles
	  • son flash de bouche sur SON arme 1re personne, ses douilles, ses traçantes, ses lumières
	  • son viseur (écartement, couleur), ses hitmarkers, ses chiffres de dégâts, sa lunette, ses munitions
	  • les sons que lui seul entend (touche, kill, manipulation…) ; les autres sons sont déjà au bon endroit
	  • une bande en bas : grande photo, nom, @, l'arme du kill en grand, PV restants, distance, headshot (doré si VIP)
	  • gros bouton vert RESPAWN : Espace, A / Croix à la manette, ou clic / toucher sur le bouton (après 0,4 s)
	Côté TUEUR, ce même script enregistre et envoie sa vue tant que quelqu'un la regarde (rien sinon).
	Souris : jamais bloquée au centre sans raison (arme en main / 1re personne / Maj-lock) — voir 🖱️ plus bas.
	Réglages : ReplicatedStorage/WeaponSystem/CombatSettings (sections Death / Style)
	  Death.MouseGuard = false → surveillance de la souris seulement pendant / juste après l'écran de mort
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WS = ReplicatedStorage:WaitForChild("WeaponSystem")
local S  = require(WS:WaitForChild("CombatSettings"))
local CI = require(WS:WaitForChild("CombatInput"))
if S.Enabled == false or not S.Death or S.Death.Enabled == false then return end
local Codec = require(WS:WaitForChild("SpectateCodec"))
local D, ST = S.Death, S.Style
local FR = D.Frame or {}

local remotes       = ReplicatedStorage:WaitForChild("CombatRemotes")
local CombatEvent   = remotes:WaitForChild("CombatEvent")
local CombatRequest = remotes:WaitForChild("CombatRequest")
local Stream        = remotes:WaitForChild("SpectateStream")

local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function tryRequire(parent, name, timeout)
	local m = parent and parent:WaitForChild(name, timeout or 5)
	if not m then return nil end
	local ok, r = pcall(require, m)
	return ok and type(r) == "table" and r or nil
end
local VFX = tryRequire(WS, "WeaponVFX")
local FX2 = tryRequire(WS, "WeaponFX2")
local MZ = tryRequire(WS, "MuzzleFX")   -- flash Blender de la M4A1 sur toutes les armes

local KV = CI.KV
local state = nil          -- (victime) vue du tueur en cours
local replaying = false    -- (victime) on rejoue un effet du tueur : rien n'est filtré ni enregistré

---------------------------------------------------------------------
-- 🧰 outils
---------------------------------------------------------------------
local PLAIN = {
	boolean = true, Color3 = true, Vector3 = true, Vector2 = true, UDim2 = true, UDim = true, CFrame = true,
	EnumItem = true, NumberSequence = true, ColorSequence = true, NumberRange = true, Font = true,
}
-- copie envoyable par le réseau (pas de fonctions, pas de clés mélangées)
local function sanitize(v, lvl)
	local tv = typeof(v)
	if tv == "number" then return (v == v) and v or nil end
	if tv == "string" then return (#v <= 300) and v or nil end
	if PLAIN[tv] then return v end
	if tv == "Instance" then return v end
	if tv == "table" and (lvl or 0) < 5 then
		local out, n = {}, 0
		local isArray = #v > 0
		for k, x in pairs(v) do
			n += 1
			if n > 80 then break end
			if (isArray and type(k) == "number") or (not isArray and type(k) == "string") then
				local s = sanitize(x, (lvl or 0) + 1)
				if s ~= nil then out[k] = s end
			end
		end
		return out
	end
	return nil
end

local function frac(pos)
	local vp = workspace.CurrentCamera.ViewportSize
	if typeof(pos) ~= "Vector2" and typeof(pos) ~= "Vector3" then return nil end
	return { x = pos.X / math.max(vp.X, 1), y = pos.Y / math.max(vp.Y, 1) }
end

---------------------------------------------------------------------
-- 📼 CÔTÉ TUEUR : enregistrement de sa vue (seulement pendant qu'une victime la regarde)
---------------------------------------------------------------------
local rec = { map = {}, vparts = {}, rest = {}, mid = 0, setups = setmetatable({}, { __mode = "k" }), light = 0 }

local function ref(a)
	local ta = typeof(a)
	if ta == "Vector3" then return { p = a } end
	if ta == "Instance" then
		local i = rec.map[a]
		if i then return { v = i, m = rec.mid } end
		return { i = a }
	end
	return nil
end
local function push(kind, data) CI.KVPush(kind, data) end
-- l'effet est-il sur TON arme (1re personne ou ton perso) ? (pas celui d'un autre joueur que tu vois)
local function ownAnchor(a)
	if typeof(a) ~= "Instance" then return false end
	if rec.map[a] then return true end
	local ch = player.Character
	local cam = workspace.CurrentCamera
	return (ch ~= nil and a:IsDescendantOf(ch)) or (cam ~= nil and a:IsDescendantOf(cam))
end

-- (victime) l'effet vient-il du VRAI perso du tueur (3e personne) pendant qu'on est dans sa tête ?
-- → on le cache : on voit à la place celui de son arme 1re personne, comme lui.
local function killerOwned(x)
	local st = state
	if replaying or not st or not st.hidden then return false end
	local kc = st.killer.Character
	local tx = typeof(x)
	local arms = st.hideMode == "arms"   -- 3e personne : seuls ses bras + son arme sont remplacés
	if tx == "Instance" then
		if x == st.killer then return true end
		if st.sharedModel ~= nil and x:IsDescendantOf(st.sharedModel) then return true end
		if not kc then return false end
		if arms then
			local tool = kc:FindFirstChildOfClass("Tool")
			local ra, la = kc:FindFirstChild("Right Arm"), kc:FindFirstChild("Left Arm")
			return (tool ~= nil and (x == tool or x:IsDescendantOf(tool))) or (ra ~= nil and (x == ra or x:IsDescendantOf(ra)))
				or (la ~= nil and (x == la or x:IsDescendantOf(la)))
		end
		return x:IsDescendantOf(kc)
	elseif (tx == "Vector3" or tx == "CFrame") and kc then
		local ref = arms and (kc:FindFirstChild("Right Arm")) or kc:FindFirstChild("Head")
		local p = (tx == "CFrame") and x.Position or x
		return ref ~= nil and (ref.Position - p).Magnitude < (arms and 4 or 5)
	end
	return false
end

-- (tueur) le flash est-il remplacé par celui du GunKit (son enveloppe l'avale) ?
local function gkSwallow(a)
	local own = VFX and VFX.__GunKitOwner
	if type(own) ~= "function" or typeof(a) ~= "Instance" then return false end
	local ok, mod, _, t = pcall(own, a)
	return ok and mod ~= nil and typeof(t) == "Instance" and t:GetAttribute("GunKitMuzzle") ~= false
end

-- Enveloppes des effets : E = { sup = (victime) cacher l'effet ?, rec = (tueur) l'enregistrer, g = famille }.
-- Si l'effet passe par plusieurs enveloppes (la tienne + celle du GunKit + la nôtre), il est enregistré UNE
-- fois, au plus près de l'effet réellement joué (l'enveloppe intérieure a priorité).
local mine = setmetatable({}, { __mode = "k" })
-- profondeur d'appel + « déjà enregistré à l'intérieur », par fil d'exécution (un effet qui attend ne mélange rien)
local threads = setmetatable({}, { __mode = "k" })
local function wrap(tbl, key, E)
	if type(tbl) ~= "table" then return end
	local cur = rawget(tbl, key)
	if type(cur) ~= "function" or mine[cur] then return end
	local w = function(...)
		if replaying then return cur(...) end
		local co = coroutine.running()
		local T = threads[co]
		if not T then T = { depth = 0, hit = {} }; threads[co] = T end
		if T.depth == 0 then
			if E.sup then
				local ok, skip = pcall(E.sup, ...)
				if ok and skip then return nil end
			end
			T.hit[E.g] = false
			T.depth = 1
			local r = table.pack(pcall(cur, ...))
			T.depth = 0
			if KV.rec and not T.hit[E.g] then pcall(E.rec, ...) end
			T.hit[E.g] = false
			if not r[1] then error(r[2], 0) end
			return table.unpack(r, 2, r.n)
		end
		if KV.rec then
			local ok, did = pcall(E.rec, ...)
			if ok and did then T.hit[E.g] = true end
		end
		T.depth += 1
		local r = table.pack(pcall(cur, ...))
		T.depth -= 1
		if not r[1] then error(r[2], 0) end
		return table.unpack(r, 2, r.n)
	end
	mine[w] = true
	tbl[key] = w
end

local H = {}
H.SetupMuzzle = { g = "setup",
	-- toujours retenu (le viewmodel est préparé AVANT qu'on regarde le tueur)
	sup = function(flash, scale, palette)
		if typeof(flash) == "Instance" then rec.setups[flash] = { s = scale, p = sanitize(palette) } end
		return false
	end,
	rec = function(flash, scale, palette)
		if rec.map[flash] then push("su", { a = ref(flash), s = scale, p = sanitize(palette) }) end
		return true
	end }
H.EmitMuzzle = { g = "muzzle", sup = function(flash) return killerOwned(flash) end, rec = function(flash, withSmoke)
	if not ownAnchor(flash) or gkSwallow(flash) then return false end
	push("em", { a = ref(flash), sm = withSmoke and true or false })
	return true
end }
H.StarFlash = { g = "star", sup = function(anchor) return killerOwned(anchor) end, rec = function(anchor, palette, scale)
	if not ownAnchor(anchor) or gkSwallow(anchor) then return false end
	push("sf", { a = ref(anchor), p = sanitize(palette), s = scale })
	return true
end }
H.Tracer = { g = "tracer", sup = function(a, _, _, key) return killerOwned(key) or (key == nil and killerOwned(a)) end,
rec = function(a, b, T, key)
	if typeof(key) ~= "Instance" or not key:IsA("Tool") or key.Parent ~= player.Character then return false end
	push("tr", { a = a, b = b, T = sanitize(T) })
	return true
end }
H.HeadshotMarker = { g = "hm", rec = function(_, pos, M) push("hm", { pos = frac(pos), M = sanitize(M) }); return true end }
H.KillMarker = { g = "km", rec = function(_, pos, KM) push("km", { pos = frac(pos), M = sanitize(KM) }); return true end }
local H2 = {}
H2.Flash = { g = "bolt", sup = function(host) return killerOwned(host) end, rec = function(host, c1, c2, scale)
	if not ownAnchor(host) or gkSwallow(host) then return false end
	push("fl", { a = ref(host), c1 = c1, c2 = c2, s = scale })
	return true
end }
H2.Shell = { g = "shell", sup = function(cf) return killerOwned(cf) end, rec = function(cf, vel, o)
	-- seulement TES douilles (celles des autres joueurs naissent à leur arme)
	local cam = workspace.CurrentCamera
	if typeof(cf) ~= "CFrame" or not cam then return false end
	local refPos = (rec.mode == "third" and rec.vh and rec.vh.Parent) and rec.vh.Position or cam.CFrame.Position
	if (cf.Position - refPos).Magnitude > 8 then return false end
	push("sh", { cf = cf, v = vel, o = sanitize(o) })
	return true
end }
H2.Drop = { g = "drop", rec = function(src, cf, vel, o)
	if not ownAnchor(src) then return false end
	push("dr", { a = ref(src), cf = cf, v = vel, o = sanitize(o) })
	return true
end }

-- flash MuzzleFX : enregistré chez le tueur (son arme), rejoué chez toi sur sa copie
H.MZShot = { g = "mz", sup = function(_, host) return killerOwned(host) end,
rec = function(tool, host, fp, cfg, _, opts)
	if (type(opts) == "table" and opts.remote) or not ownAnchor(host) then return false end
	if MZ and MZ.ClassOf(tool, cfg) == "None" then return false end
	-- arme GunKit : son flash passe par l'événement « gk »
	if typeof(tool) == "Instance" and tool:GetAttribute("GunKitMuzzle") == true then return false end
	push("mz", { a = ref(host), fp = fp and true or false })
	return true
end }

local gkMods = {}   -- [nom de l'arme GunKit] = module MuzzleFlash
local function installWrappers()
	if VFX then
		for k, E in pairs(H) do wrap(VFX, k, E) end
		-- le GunKit garde tes fonctions d'origine : on enveloppe aussi celles-là (effet réellement joué)
		local O = rawget(VFX, "__GunKitOrig")
		if type(O) == "table" then
			wrap(O, "Emit", H.EmitMuzzle); wrap(O, "Star", H.StarFlash); wrap(O, "Tracer", H.Tracer)
			wrap(O, "FX2", H2.Flash)
		end
	end
	if FX2 then for k, E in pairs(H2) do wrap(FX2, k, E) end end
	if type(MZ) == "table" then wrap(MZ, "Shot", H.MZShot) end
	local gk = ReplicatedStorage:FindFirstChild("GunKit")
	local guns = gk and gk:FindFirstChild("Guns")
	if guns then
		for _, g in ipairs(guns:GetChildren()) do
			local mf = g:FindFirstChild("MuzzleFlash")
			if mf and mf:IsA("ModuleScript") and gkMods[g.Name] == nil then
				local ok, MF = pcall(require, mf)
				gkMods[g.Name] = (ok and type(MF) == "table") and MF or false
			end
			local MF = gkMods[g.Name]
			if MF then
				local name = g.Name
				-- flash GunKit = famille « star » : remplace ton StarFlash sur ton arme GunKit
				wrap(MF, "Emit", { g = "star", sup = function(host) return killerOwned(host) end,
				rec = function(host, fp, smoke)
					if MF._remote or not ownAnchor(host) then return false end   -- flash d'un autre joueur
					push("gk", { a = ref(host), fp = fp and true or false, sm = smoke and true or false, g = name })
					return true
				end })
			end
		end
	end
end
task.spawn(function()
	while true do
		pcall(installWrappers)
		task.wait(1)
	end
end)

-- 🔊 sons que le tueur est seul à entendre (joués chez lui : touche, kill, manipulation…)
local soundConns = setmetatable({}, { __mode = "k" })
local function watchSound(s)
	if not s:IsA("Sound") or soundConns[s] then return end
	soundConns[s] = s.Played:Connect(function()
		if not KV.rec or D.KillerSounds == false or s.Looped then return end
		if s.TimeLength > 12 then return end   -- musique / ambiance
		push("snd", { id = s.SoundId, v = s.Volume, sp = s.PlaybackSpeed, tp = s.TimePosition })
	end)
end
local function watchTree(root)
	for _, d in ipairs(root:GetDescendants()) do watchSound(d) end
	root.DescendantAdded:Connect(watchSound)
end
watchTree(SoundService)
local watchedCam
local function watchCam()
	local cam = workspace.CurrentCamera
	if cam and cam ~= watchedCam then watchedCam = cam; watchTree(cam) end
end
watchCam()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCam)

-- ── viewmodel du tueur ↔ pièces de son vrai Tool (même arbre : le viewmodel est un clone du Tool)
local function mapViewmodel(vm, tool)
	local out = {}
	local function walk(vParent, tParent, top)
		local byName = {}
		for _, c in ipairs(tParent:GetChildren()) do
			local l = byName[c.Name]
			if not l then l = {}; byName[c.Name] = l end
			table.insert(l, c)
		end
		local count = {}
		for _, c in ipairs(vParent:GetChildren()) do
			if #out >= Codec.MaxParts then return end
			local list = byName[c.Name]
			if list then
				local k = (count[c.Name] or 0) + 1
				count[c.Name] = k
				local t = list[k]
				if t and t.ClassName == c.ClassName then
					if c:IsA("BasePart") then table.insert(out, { c, t }) end
					walk(c, t, false)
				end
			end
		end
	end
	walk(vm, tool, true)
	return out
end

local function differs(a, b)
	return (a.Position - b.Position).Magnitude > 0.004 or a.LookVector:Dot(b.LookVector) < 0.99999
		or a.UpVector:Dot(b.UpVector) < 0.99999
end

local function hudCfg(tool)
	local e = KV.tools[tool]
	if not e or type(e.cfg) ~= "table" then return nil end
	local cfg = e.cfg
	return sanitize({
		cursor = cfg.Cursor, head = cfg.Headshot, cross = cfg.Crosshair, rhud = cfg.ReloadHUD,
		clip = cfg.ClipSize, style = cfg.Reload and cfg.Reload.Style,
		scope = cfg.ADS and cfg.ADS.Scope and true or false, tint = cfg.ADS and cfg.ADS.ScopeTint,
		mobile = e.mobile, optic = tool:GetAttribute("Optic"), gun = tool:GetAttribute("Gun"),
	})
end

local lightConn
-- mode « vm » : arme 1re personne (viewmodel dans la caméra) ; mode « third » : sa vraie arme + ses vrais bras
-- en 3e personne (ce que SON écran montre, bras et pièces posés chez lui, pas la version réseau)
local function sendManifest(mode, src, tool, ch)
	rec.mid = (rec.mid % 60000) + 1
	rec.mode, rec.vm, rec.tool, rec.optic = mode, src, tool, tool:GetAttribute("Optic")
	if mode == "vm" then
		rec.armR, rec.armL, rec.vh = src:FindFirstChild("Right Arm"), src:FindFirstChild("Left Arm"), src:FindFirstChild("Handle")
	else
		rec.armR, rec.armL, rec.vh = ch:FindFirstChild("Right Arm"), ch:FindFirstChild("Left Arm"), tool:FindFirstChild("Handle")
	end
	table.clear(rec.map); table.clear(rec.vparts); table.clear(rec.rest)
	local th = tool:FindFirstChild("Handle")
	local pairsList
	if mode == "vm" then
		pairsList = mapViewmodel(src, tool)
	else
		pairsList = {}
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") and #pairsList < Codec.MaxParts then table.insert(pairsList, { d, d }) end
		end
	end
	local list, setups = {}, {}
	for i, pr in ipairs(pairsList) do
		local c, t = pr[1], pr[2]
		rec.map[c] = i
		rec.vparts[i] = c
		local rest = (th and rec.vh) and th.CFrame:ToObjectSpace(t.CFrame) or CFrame.identity
		rec.rest[i] = rest
		local bt = (c.Transparency < 0.98 and c.Transparency) or (t.Transparency < 0.98 and t.Transparency) or 0
		list[i] = { p = t, r = rest, b = bt }
		local su = rec.setups[c]
		if su then table.insert(setups, { i = i, s = su.s, p = su.p }) end
	end
	rec.handleIdx = rec.vh and rec.map[rec.vh] or nil
	-- lumières posées sur l'arme (lumière de bouche…)
	if lightConn then lightConn:Disconnect() end
	lightConn = src.DescendantAdded:Connect(function(d)
		if not KV.rec or not d:IsA("Light") or not rec.map[d.Parent] then return end
		rec.light += 1
		local id = rec.light
		push("lt", { a = ref(d.Parent), id = id, cls = d.ClassName, c = d.Color, b = d.Brightness, r = d.Range,
			sh = d.Shadows })
		d.AncestryChanged:Connect(function(_, parent)
			if not parent and KV.rec then push("ltx", { id = id }) end
		end)
	end)
	CombatRequest:FireServer("KVM", {
		id = rec.mid, tool = tool, list = list, h = rec.handleIdx, third = mode == "third",
		rs = rec.armR and rec.armR.Size, ls = rec.armL and rec.armL.Size,
		rt = rec.armR and rec.armR.Transparency or 0, lt = rec.armL and rec.armL.Transparency or 0,
		setups = setups, hud = (D.KillerHUD ~= false) and hudCfg(tool) or nil,
	})
end

local function visible(p)
	return p.Parent ~= nil and p.Transparency < 0.98 and p.LocalTransparencyModifier < 0.98
end

local rot = 0
local function makePacket()
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local camCF = cam.CFrame
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	-- caméra attachée à SON perso : chez la victime elle suit le perso qu'elle voit (aucun décalage)
	-- position relative à son perso, rotation du monde : quand il tourne sur lui-même la caméra ne bouge pas
	local pk = { t = workspace:GetServerTimeNow(),
		cam = root and (CFrame.new(camCF.Position - root.Position) * camCF.Rotation) or camCF,
		camRel = root ~= nil, fov = cam.FieldOfView, mid = rec.mid }
	local tool = ch and ch:FindFirstChildOfClass("Tool")
	local vm = D.ShowKillerViewmodel ~= false and cam:FindFirstChild("WeaponViewmodel")
	local mode, src = nil, nil
	if vm and tool then
		mode, src = "vm", vm
	elseif tool and root and tool:FindFirstChild("Handle") and ch:FindFirstChild("Right Arm") and ch:FindFirstChild("Left Arm") then
		mode, src = "third", tool
	end
	if mode then
		if mode ~= rec.mode or src ~= rec.vm or tool ~= rec.tool or tool:GetAttribute("Optic") ~= rec.optic then
			sendManifest(mode, src, tool, ch)
		end
		pk.mid = rec.mid
		local r, l, h = rec.armR, rec.armL, rec.vh
		if r and l and h and r.Parent and l.Parent and h.Parent then
			pk.vm = true
			pk.third = mode == "third"
			local base = (mode == "third") and root.CFrame or camCF
			pk.r, pk.l, pk.h = base:ToObjectSpace(r.CFrame), base:ToObjectSpace(l.CFrame), base:ToObjectSpace(h.CFrame)
			local hcf = h.CFrame
			local n = #rec.vparts
			local vis, moved = table.create(n + 2, false), {}
			for i, c in ipairs(rec.vparts) do
				local on = visible(c)
				if on then
					local rel = hcf:ToObjectSpace(c.CFrame)
					if rel.Position.Magnitude > Codec.PartRange - 0.5 then
						on = false
					elseif differs(rel, rec.rest[i]) then
						table.insert(moved, { i, rel })
					end
				end
				vis[i] = on
			end
			vis[n + 1], vis[n + 2] = visible(r), visible(l)
			-- trop de pièces en mouvement : on envoie une fenêtre tournante (les autres gardent leur place)
			if #moved > Codec.MaxMoved then
				local disp = {}
				for _, e in ipairs(moved) do disp[e[1]] = true end
				pk.disp = disp
				local w = {}
				for k = 1, Codec.MaxMoved do w[k] = moved[((rot + k - 1) % #moved) + 1] end
				rot = (rot + Codec.MaxMoved) % #moved
				moved = w
				pk.partial = true
			end
			pk.n, pk.vis, pk.moved = n, vis, moved
		end
	end
	local e = tool and KV.tools[tool]
	if e and D.KillerHUD ~= false then
		local ok, hs = pcall(e.get)
		if ok and type(hs) == "table" then
			local a = tool:GetAttribute("AimAlpha")
			hs.aim = typeof(a) == "number" and a or 0
			pk.hud = hs
		end
	end
	return pk
end

local streaming, streamUntil, streamAcc = false, 0, 0
local function setStreaming(on)
	streaming = on
	KV.rec = on
	table.clear(KV.events)
	rec.vm, rec.mode = nil, nil   -- manifeste renvoyé au début de chaque vue
	if not on and lightConn then lightConn:Disconnect(); lightConn = nil end
end

CombatEvent.OnClientEvent:Connect(function(kind)
	if kind == "StreamStart" then
		setStreaming(true)
		streamUntil = os.clock() + (D.SpectateTime or 5) + 1.5
	elseif kind == "StreamStop" then
		setStreaming(false)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not streaming then return end
	local myHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if os.clock() > streamUntil or not myHum or myHum.Health <= 0 then   -- fin / mort pendant l'envoi
		setStreaming(false)
		return
	end
	streamAcc += dt
	if streamAcc >= 1 / math.clamp(D.StreamRate or 30, 5, 60) then
		streamAcc = 0
		local ok, pk = pcall(makePacket)
		if ok and pk then
			local ok2, b = pcall(Codec.Encode, pk)
			if ok2 then Stream:FireServer(b) end
		end
	end
	-- effets du tour (après le manifeste éventuel : même canal fiable, donc dans l'ordre)
	if #KV.events > 0 then
		local ev = KV.events
		KV.events = {}
		CombatRequest:FireServer("KVE", ev)
	end
end)

---------------------------------------------------------------------
-- 🎨 outils UI
---------------------------------------------------------------------
-- tous les textes de l'écran de mort : Fredoka One
local FREDOKA = Font.fromEnum(Enum.Font.FredokaOne)
local F = {
	Heavy  = FREDOKA,
	Bold   = FREDOKA,
	Medium = FREDOKA,
}
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function tween(o, t, props, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function label(parent, text, font, color, size, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, FontFace = font, Text = text, TextColor3 = color,
		TextSize = size, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end

---------------------------------------------------------------------
-- 🖥️ ÉCRAN (fondu noir + bande)
---------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "DeathCamUI", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 60, Enabled = true,
}, playerGui)
-- le fondu / la bande vont jusqu'aux bords de l'écran (pas coupés par la zone sûre du téléphone)
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)

local black = new("Frame", {
	Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50, Visible = false,
}, gui)

-- 📐 échelle : tout est dessiné pour un écran 1080p puis mis à l'échelle
local uiScaleHolder = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)


local function viewportScale()
	local cam = workspace.CurrentCamera
	local y = cam and cam.ViewportSize.Y or 1080
	return math.clamp(y / 1080, IS_TOUCH and 0.55 or 0.7, 1.25)
end

---------------------------------------------------------------------
-- 🔫 arme 3D (fixe, de profil)
---------------------------------------------------------------------
local STRIP = {
	Script = true, LocalScript = true, ModuleScript = true, Sound = true, ParticleEmitter = true,
	Light = true, PointLight = true, SpotLight = true, SurfaceLight = true, Beam = true, Trail = true,
	BillboardGui = true, SurfaceGui = true, ProximityPrompt = true, Fire = true, Smoke = true, Sparkles = true,
	RemoteEvent = true, RemoteFunction = true, BindableEvent = true, UnreliableRemoteEvent = true,
}
local function cleanClone(src)
	local ok, c = pcall(function() return src:Clone() end)
	if not ok or not c then return nil end
	for _, d in ipairs(c:GetDescendants()) do
		if STRIP[d.ClassName] then d:Destroy() end
	end
	return c
end

local function buildGunViewport(vp, killerChar, toolName)
	local tool = killerChar and ((toolName ~= "" and killerChar:FindFirstChild(toolName)) or killerChar:FindFirstChildOfClass("Tool"))
	if not tool or not tool:IsA("Tool") then return false end
	local c = cleanClone(tool)
	if not c then return false end
	local model = Instance.new("Model")
	for _, ch in ipairs(c:GetChildren()) do ch.Parent = model end
	c:Destroy()
	local handle = model:FindFirstChild("Handle")
	if not handle then model:Destroy() return false end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
	end
	model.PrimaryPart = handle
	model.Parent = vp

	local bcf, size = model:GetBoundingBox()
	-- axes : le plus long = canon, le plus fin = épaisseur (on regarde de profil), le reste = haut
	local axes = {
		{ v = bcf.RightVector, s = size.X }, { v = bcf.UpVector, s = size.Y }, { v = bcf.LookVector, s = size.Z },
	}
	table.sort(axes, function(a, b) return a.s > b.s end)
	local barrel, up, thick = axes[1], axes[2], axes[3]
	local center = bcf.Position
	local flash = model:FindFirstChild("Flash", true)
	local bdir = barrel.v
	if flash and flash:IsA("BasePart") then
		if (flash.Position - center):Dot(bdir) < 0 then bdir = -bdir end
	elseif (center - handle.Position):Dot(bdir) < 0 then
		bdir = -bdir
	end
	local udir = up.v
	local ref = (flash and flash:IsA("BasePart")) and flash.Position or center
	if (ref - handle.Position):Dot(udir) < 0 then udir = -udir end
	if FR.GunFacesRight == false then bdir = -bdir end

	local cam = Instance.new("Camera")
	cam.FieldOfView = 22
	vp.CurrentCamera = cam
	cam.Parent = vp
	local function frame()
		local abs = vp.AbsoluteSize
		local aspect = (abs.Y > 0) and (abs.X / abs.Y) or 2.4
		local half = math.tan(math.rad(cam.FieldOfView) / 2)
		local dw = (barrel.s * 0.5) / (half * aspect)
		local dh = (up.s * 0.5) / half
		local dist = math.max(dw, dh) * 1.12 + thick.s * 0.5
		local z = bdir:Cross(udir)
		cam.CFrame = CFrame.fromMatrix(center + z * dist, bdir, udir)
		vp.LightDirection = (-z * 0.6 - udir * 0.9 + bdir * 0.2).Unit
	end
	frame()
	vp:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame)
	return true
end

---------------------------------------------------------------------
-- 🎛️ BANDE DU BAS
---------------------------------------------------------------------
local function promptKind()
	if IS_TOUCH then return "touch" end
	if CI.IsGamepad() then return "pad" end
	return "key"
end

local GREEN      = Color3.fromRGB(40, 200, 95)
local GREEN_DARK = Color3.fromRGB(22, 120, 58)
-- même style que tes UI (Shop, Current Stage, Daily Rewarded Kills) et que l'ArenaHUD :
-- panneaux bleus brillants, liseré clair, bord épais foncé, textes blancs à gros contour
local BLUE_HI, BLUE_LO   = Color3.fromRGB(92, 196, 255), Color3.fromRGB(30, 108, 236)
local BLUE_EDGE, BLUE_RIM = Color3.fromRGB(16, 58, 150), Color3.fromRGB(190, 236, 255)
local GOLD_HI, GOLD_LO    = Color3.fromRGB(255, 232, 120), Color3.fromRGB(240, 165, 25)
local GOLD_EDGE           = Color3.fromRGB(150, 90, 0)
local OUTLINE             = Color3.fromRGB(10, 30, 80)
local function textStroke(l, sc, t)
	-- (t gardé pour compatibilité : le contour est maintenant plein, comme sur tes UI)
	new("UIStroke", { Color = OUTLINE, Thickness = math.max(1.5, 2.6 * sc), Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round }, l)
end
-- panneau de jeu : dessus en dégradé brillant + reflet, liseré clair, bord épais foncé dessous
local function gamePanel(parent, props, radius, depth, hi, lo, edgeCol, z)
	z = z or 1
	local holder = new("Frame", { BackgroundTransparency = 1, ZIndex = z }, parent)
	for k, v in pairs(props) do holder[k] = v end
	local edgeF = new("Frame", { Name = "Edge", Size = UDim2.fromScale(1, 1), BackgroundColor3 = edgeCol or BLUE_EDGE,
		BorderSizePixel = 0, ZIndex = z }, holder)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, edgeF)
	new("UIStroke", { Color = OUTLINE, Thickness = math.max(1.5, depth * 0.45), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, edgeF)
	local face = new("Frame", { Name = "Face", Size = UDim2.new(1, 0, 1, -depth), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = z }, holder)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, face)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(hi or BLUE_HI, lo or BLUE_LO) }, face)
	local inset = math.max(2, math.floor(depth * 0.5))
	local gloss = new("Frame", { Position = UDim2.fromOffset(inset, inset), Size = UDim2.new(1, -2 * inset, 0.42, 0),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = z }, face)
	new("UICorner", { CornerRadius = UDim.new(0, math.max(2, radius - inset)) }, gloss)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.62), NumberSequenceKeypoint.new(1, 0.95) }) }, gloss)
	local rim = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -inset, 1, -inset), BackgroundTransparency = 1, ZIndex = z }, face)
	new("UICorner", { CornerRadius = UDim.new(0, math.max(2, radius - 1)) }, rim)
	new("UIStroke", { Color = BLUE_RIM, Thickness = math.max(1, depth * 0.3), Transparency = 0.25,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, rim)
	return holder, face
end

local function buildBand(info, onSkip)
	local killer = info.killer
	local sc = viewportScale()
	-- mobile : mise en page compacte sur UNE rangée en bas (photo | bouton | arme) → le perso regardé reste visible
	local MOB = IS_TOUCH
	local u = MOB and math.clamp(workspace.CurrentCamera.ViewportSize.Y / 390, 0.9, 1.7) or sc
	local function P(pc, mob)
		if MOB then return math.floor((mob or pc * 0.5) * u) end
		return math.floor(pc * sc)
	end
	local H = P(340, 150)
	local band = new("CanvasGroup", {
		Name = "Band", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, H), BackgroundTransparency = 1, GroupTransparency = 1,
	}, uiScaleHolder)

	-- fond : dégradé vers le haut (sombre en bas → transparent en haut)
	local bg = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = ST.Dark, BorderSizePixel = 0,
	}, band)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.6), NumberSequenceKeypoint.new(1, 0.1),
		}),
	}, bg)

	local vip = info.vip == true and FR.VipTheme ~= false
	local vipFx = nil
	if vip then
		-- teinte dorée (comme ta fiche VIP) : noir à gauche → or sombre à droite
		local washGroup = new("CanvasGroup", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 0,
		}, band)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.72), NumberSequenceKeypoint.new(1, 0.38),
			}),
		}, washGroup)
		local wash = new("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		}, washGroup)
		new("UIGradient", {
			Rotation = 0,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(12, 9, 3)),
				ColorSequenceKeypoint.new(0.45, Color3.fromRGB(24, 18, 5)),
				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(78, 57, 12)),
			}),
		}, wash)
		local line = new("Frame", {
			Position = UDim2.fromScale(0, 0.3), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = ST.Gold, BorderSizePixel = 0,
		}, band)
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1),
			}),
		}, line)
		local sheen = new("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 246, 214), BorderSizePixel = 0, ZIndex = 8,
		}, band)
		local sg = new("UIGradient", {
			Rotation = 14, Offset = Vector2.new(1, 0),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.00, 1), NumberSequenceKeypoint.new(0.30, 1),
				NumberSequenceKeypoint.new(0.45, 0.93), NumberSequenceKeypoint.new(0.50, 0.88),
				NumberSequenceKeypoint.new(0.55, 0.93), NumberSequenceKeypoint.new(0.70, 1),
				NumberSequenceKeypoint.new(1.00, 1),
			}),
		}, sheen)
		vipFx = { sheen = sg, sparks = {} }
	end

	local content = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, band)
	new("UIPadding", {
		PaddingLeft = UDim.new(MOB and 0.065 or 0.04, 0), PaddingRight = UDim.new(MOB and 0.065 or 0.04, 0),
		PaddingBottom = UDim.new(0, P(22, 10)),
	}, content)

	-- ▸ gauche : GRANDE photo + nom
	local blockH = P(172, 78)   -- même hauteur pour la photo et l'arme
	local left = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(MOB and 0.34 or 0.42, 0, 0, blockH), BackgroundTransparency = 1,
	}, content)
	local avSize = P(160, 70)
	local x0 = 0
	if FR.ShowAvatar ~= false and killer then
		-- anneau brillant (bleu, doré en VIP) + contour foncé, la photo au centre
		local ringW = math.max(4, P(9, 5))
		local ring = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(avSize, avSize), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		}, left)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(vip and GOLD_HI or BLUE_HI, vip and GOLD_LO or BLUE_LO) }, ring)
		new("UIStroke", { Color = OUTLINE, Thickness = math.max(2, 3 * sc), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
		local av = new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -2 * ringW, 1, -2 * ringW), BackgroundColor3 = Color3.fromRGB(26, 31, 42),
			Image = "rbxthumb://type=AvatarHeadShot&id=" .. killer.UserId .. "&w=420&h=420",
		}, ring)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, av)
		new("UIStroke", { Color = OUTLINE, Thickness = math.max(1.5, 2 * sc), Transparency = 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, av)
		x0 = avSize + P(22)
	end
	local col = new("Frame", {
		Position = UDim2.new(0, x0, 0, 0), Size = UDim2.new(1, -x0, 1, 0), BackgroundTransparency = 1,
	}, left)
	local t1 = label(col, FR.Title or "KILLED BY", F.Bold, ST.Sub, P(23, 12), {
		Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0.18, 0),
	})
	textStroke(t1, sc, 0.6)
	local name = label(col, killer and killer.DisplayName or "?", F.Heavy, ST.White, P(54, 26), {
		Position = UDim2.new(0, 0, 0.17, 0), Size = UDim2.new(1, 0, 0.38, 0),
	})
	local user = label(col, killer and ("@" .. killer.Name) or "", F.Medium, ST.Sub, P(25, 13), {
		Position = UDim2.new(0, 0, 0.55, 0), Size = UDim2.new(1, 0, 0.2, 0),
	})
	textStroke(user, sc, 0.6)
	local parts = {}
	if FR.ShowHealth ~= false and info.hp then
		table.insert(parts, ('<font color="#FFFFFF">%d</font> HP left'):format(info.hp))
	end
	if FR.ShowDistance ~= false and info.dist then
		table.insert(parts, ("%d %s"):format(info.dist, FR.Units or "m"))
	end
	if FR.ShowHeadshot ~= false and info.head then
		local c = ST.Head
		table.insert(parts, ('<font color="#%02X%02X%02X">Headshot</font>'):format(
			math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255)))
	end
	local infoL = label(col, table.concat(parts, "  ·  "), F.Medium, ST.Sub, P(24, 12), {
		Position = UDim2.new(0, 0, 0.77, 0), Size = UDim2.new(1, 0, 0.23, 0), RichText = true,
	})
	textStroke(infoL, sc, 0.6)

	if vip then
		name.TextColor3 = Color3.new(1, 1, 1)
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 252, 170)),
				ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 220, 70)),
				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(235, 175, 30)),
			}),
		}, name)
		new("UIStroke", { Color = Color3.fromRGB(90, 55, 0), Thickness = math.max(1, 2 * sc), Transparency = 0.2 }, name)
		local crown = new("ImageLabel", {
			BackgroundTransparency = 1, Image = ST.Crown, ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(P(40), P(34)),
		}, col)
		local function placeCrown()
			local w = math.min(name.TextBounds.X, name.AbsoluteSize.X)
			crown.Position = UDim2.new(0, w + P(12), 0.17 + 0.19, 0)
		end
		name:GetPropertyChangedSignal("TextBounds"):Connect(placeCrown)
		task.defer(placeCrown)
		for i = 1, 3 do
			local d = new("Frame", {
				Size = UDim2.fromOffset(4, 4), AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = ST.GoldSoft, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 9,
			}, col)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
			vipFx.sparks[i] = { f = d, x = 0.12 + (i - 1) * 0.22, phase = (i - 1) / 3 }
		end
	else
		textStroke(name, sc, 0.35)
	end

	-- ▸ droite : l'arme du kill, EN GRAND, sur un socle, nom en dessous
	local right = new("Frame", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(MOB and 0.28 or 0.38, 0, 0, blockH), BackgroundTransparency = 1,
	}, content)
	new("UISizeConstraint", { MaxSize = Vector2.new(720 * sc, math.huge) }, right)
	-- plus de grand panneau : l'arme flotte sur une ombre douce (elle ressort sur tous les décors sans cacher
	-- l'écran), posée sur une petite plaque brillante au style de tes UI qui porte son nom
	local plate = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, right)

	local vp = new("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.0), Size = UDim2.fromScale(0.94, 0.76),
		BackgroundTransparency = 1, Ambient = Color3.fromRGB(165, 165, 175), LightColor = Color3.fromRGB(255, 250, 240), ZIndex = 2,
	}, plate)
	local okGun = buildGunViewport(vp, killer and killer.Character, info.tool or "")
	-- plaque du nom (petit panneau brillant, bleu ou doré en VIP)
	local tagH = P(46, 24)
	local tagHolder = gamePanel(plate, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.62, 0, 0, tagH),
	}, P(12, 8), math.max(3, P(6, 4)), vip and GOLD_HI or BLUE_HI, vip and GOLD_LO or BLUE_LO, vip and GOLD_EDGE or BLUE_EDGE, 3)
	new("UISizeConstraint", { MaxSize = Vector2.new(P(360, 160), math.huge) }, tagHolder)
	local tagFace = tagHolder:FindFirstChild("Face")
	local wname = label(tagFace, string.upper(info.weapon or ""), F.Heavy, ST.White, P(30, 14), {
		Size = UDim2.fromScale(1, 1), ZIndex = 4, TextXAlignment = Enum.TextXAlignment.Center,
	})
	textStroke(wname, sc, 0.35)
	if not okGun then tagHolder.Position = UDim2.fromScale(0.5, 0.75) end

	-- ▸ GROS bouton vert RESPAWN (centre, en haut de la bande) : bouton de jeu plein, bord foncé en dessous,
	-- s'enfonce quand on clique ; le temps restant est la fine barre sous le bouton
	local btnW, btnH = P(330, 172), P(74, 44)
	local edge = math.max(4, P(7))
	local holder = new("Frame", {
		Name = "RespawnHolder",
		-- PC : en haut de la bande ; mobile : en bas, sur la rangée photo / arme (ne cache plus le perso)
		AnchorPoint = MOB and Vector2.new(0.5, 1) or Vector2.new(0.5, 0),
		Position = MOB and UDim2.new(0.5, 0, 1, -P(22, 8)) or UDim2.new(0.5, 0, 0, P(48)),
		Size = UDim2.fromOffset(btnW, btnH + edge), BackgroundTransparency = 1, ZIndex = 20,
	}, band)
	local base = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(btnW, btnH),
		BackgroundColor3 = GREEN_DARK, BorderSizePixel = 0, ZIndex = 20,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(0, P(14)) }, base)
	new("UIStroke", { Color = OUTLINE, Thickness = math.max(1.5, 2.4 * sc), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, base)
	-- (pas de Modal = true : le moteur gérait alors lui-même le verrou de la souris et le réappliquait
	--  à la disparition du bouton → souris coincée. La souris est gérée par la garde 🖱️ plus bas.)
	local btn = new("TextButton", {
		Name = "Respawn", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(btnW, btnH),
		BackgroundColor3 = GREEN, AutoButtonColor = false, Text = "", ZIndex = 21,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(0, P(14)) }, btn)
	local row = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 22 }, btn)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, P(12)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local keyHolder = new("Frame", {
		Size = UDim2.fromOffset(0, P(40)), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 22,
	}, row)
	local text = label(row, FR.RespawnText or "Respawn", F.Heavy, ST.White, P(36, 20), {
		Size = UDim2.fromOffset(0, P(44)), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2,
		TextTruncate = Enum.TextTruncate.None, ZIndex = 22,
	})
	new("UIStroke", { Color = GREEN_DARK, Thickness = math.max(1.5, 2.5 * sc), Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, text)
	-- temps restant : fine barre sous le bouton
	local barBg = new("Frame", {
		AnchorPoint = MOB and Vector2.new(0.5, 1) or Vector2.new(0.5, 0),
		Position = MOB and UDim2.new(0.5, 0, 0, -P(8, 6)) or UDim2.new(0.5, 0, 1, P(8)),
		Size = UDim2.new(0.86, 0, 0, math.max(3, P(5))), BackgroundColor3 = OUTLINE,
		BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 20,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, barBg)
	new("UIStroke", { Color = OUTLINE, Thickness = 1, Transparency = 0.2 }, barBg)
	local bar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 21 }, barBg)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
	local function setPrompt()
		for _, c in ipairs(keyHolder:GetChildren()) do c:Destroy() end
		local kind = promptKind()
		keyHolder.Visible = kind ~= "touch"
		text.Text = string.upper((kind == "touch") and (FR.TapText or "Tap to respawn") or (FR.RespawnText or "Respawn"))
		if kind == "pad" then
			new("ImageLabel", {
				BackgroundTransparency = 1, Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA),
				ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(P(40), P(40)), ZIndex = 22,
			}, keyHolder)
		elseif kind == "key" then
			local cap = new("TextLabel", {
				BackgroundColor3 = GREEN_DARK, BackgroundTransparency = 0, FontFace = F.Heavy,
				Text = "SPACE", TextColor3 = ST.White, TextSize = P(22),
				Size = UDim2.fromOffset(P(96), P(38)), ZIndex = 23,
			}, keyHolder)
			new("UICorner", { CornerRadius = UDim.new(0, P(8)) }, cap)
		end
	end
	setPrompt()
	local promptConn = CI.Changed.Event:Connect(setPrompt)
	local GREEN_HI = GREEN:Lerp(Color3.new(1, 1, 1), 0.12)
	btn.MouseEnter:Connect(function() btn.BackgroundColor3 = GREEN_HI end)
	btn.MouseLeave:Connect(function() btn.BackgroundColor3 = GREEN; btn.Position = UDim2.fromOffset(0, 0) end)
	btn.MouseButton1Down:Connect(function() btn.Position = UDim2.fromOffset(0, edge) end)
	btn.MouseButton1Up:Connect(function() btn.Position = UDim2.fromOffset(0, 0) end)
	btn.Activated:Connect(function()
		btn.Position = UDim2.fromOffset(0, edge)
		if onSkip then onSkip() end
	end)

	return {
		band = band, bar = bar, vipFx = vipFx, promptConn = promptConn, button = btn,
	}
end


---------------------------------------------------------------------
-- 👁️ VUE DU TUEUR (côté victime)
---------------------------------------------------------------------
-- cacher le tueur quand on est dans sa tête : son corps, son arme 3e personne, la copie de partage
-- d'animations, ses contours et les effets accrochés à son vrai perso (on voit ceux de son arme 1re personne)
local hiddenParts, hiddenFx, hideConns = {}, {}, {}
local FX_CLASSES = { ParticleEmitter = true, PointLight = true, SpotLight = true, SurfaceLight = true,
	Beam = true, Trail = true, Fire = true, Smoke = true, Sparkles = true, Highlight = true }
local function hideOne(d)
	if (d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture")) and hiddenParts[d] == nil then
		hiddenParts[d] = d.LocalTransparencyModifier
		d.LocalTransparencyModifier = 1
	elseif FX_CLASSES[d.ClassName] and hiddenFx[d] == nil then
		hiddenFx[d] = d.Enabled
		d.Enabled = false
	end
end
local function hideTree(root)
	if not root then return end
	hideOne(root)
	for _, d in ipairs(root:GetDescendants()) do hideOne(d) end
	table.insert(hideConns, root.DescendantAdded:Connect(function(d)
		task.defer(function()
			local st = state
			if st and st.hidden and d.Parent then hideOne(d) end
		end)
	end))
end
local function unhideAll(st)
	for _, c in ipairs(hideConns) do c:Disconnect() end
	table.clear(hideConns)
	-- remise à l'état normal : 0, sauf le vrai Tool + les vrais bras que ta copie de partage cache elle-même
	local kc = st and st.killer and st.killer.Character
	local f = workspace:FindFirstChild("SharedWeaponVisuals")
	local shared = kc and f and f:FindFirstChild("SharedWeapon_" .. st.killer.UserId)
	local tool = kc and kc:FindFirstChildOfClass("Tool")
	for d in pairs(hiddenParts) do
		if d.Parent then
			local keep = shared ~= nil and kc ~= nil and ((tool ~= nil and d:IsDescendantOf(tool))
				or ((d.Name == "Right Arm" or d.Name == "Left Arm") and d.Parent == kc))
			d.LocalTransparencyModifier = keep and 1 or 0
		end
	end
	for d, v in pairs(hiddenFx) do if d.Parent then pcall(function() d.Enabled = v end) end end
	table.clear(hiddenParts); table.clear(hiddenFx)
end
-- chaque image : d'autres scripts (contours d'arène, partage d'animations) peuvent rallumer
local function keepHidden(st)
	for d in pairs(hiddenParts) do
		if d.Parent and d.LocalTransparencyModifier ~= 1 then d.LocalTransparencyModifier = 1 end
	end
	for d in pairs(hiddenFx) do
		if d.Parent and d.Enabled then pcall(function() d.Enabled = false end) end
	end
	-- copie locale des bras + de l'arme du tueur (WeaponAnimationSharingClient)
	local f = workspace:FindFirstChild("SharedWeaponVisuals")
	local m = f and f:FindFirstChild("SharedWeapon_" .. st.killer.UserId)
	if m ~= st.sharedModel then
		st.sharedModel = m
		if m then hideTree(m) end
	end
end

-- copie visuelle d'une pièce (géométrie + textures seulement)
local KEEP = { "DataModelMesh", "Decal", "Texture", "SurfaceAppearance", "Attachment" }
local function visualClone(src)
	if typeof(src) ~= "Instance" or not src:IsA("BasePart") or not src.Parent then return nil end
	local arch = src.Archivable
	if not arch then pcall(function() src.Archivable = true end) end
	local ok, c = pcall(src.Clone, src)
	if not arch then pcall(function() src.Archivable = false end) end
	if not ok or not c then return nil end
	for _, d in ipairs(c:GetDescendants()) do
		local keep = false
		for _, cls in ipairs(KEEP) do if d:IsA(cls) then keep = true; break end end
		if not keep then
			d:Destroy()
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.LocalTransparencyModifier = 0
		end
	end
	c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false, false
	c.Massless = true
	c.LocalTransparencyModifier = 0
	return c
end

local destroyHud   -- (défini plus bas)

-- 🪆 TON corps pendant la vue du tueur
local SKIP_SELF = { HumanoidRootPart = true, RagdollCollider = true }
local BODY_PARTS = { Head = true, Torso = true, ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true,
	["Right Leg"] = true, UpperTorso = true, LowerTorso = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true, LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true }
local function buildSelfMirror(st)
	-- ton corps mort : envoyé par le serveur (le bon modèle même si ton perso a changé de référence)
	local ch = (typeof(st.info.body) == "Instance" and st.info.body.Parent and st.info.body) or player.Character
	if not ch then return end
	local model = Instance.new("Model")
	model.Name = "DeathCamMyBody"
	local list = {}
	for _, d in ipairs(ch:GetDescendants()) do
		local body = BODY_PARTS[d.Name] and d.Parent == ch
		if d:IsA("BasePart") and not SKIP_SELF[d.Name] and (body or d.Transparency < 0.99)
			and not d:FindFirstAncestorOfClass("Tool") then
			local c = visualClone(d)
			if c then
				if body and c.Transparency > 0.5 then c.Transparency = 0 end   -- rendu caché localement : on le remontre
				c.Name = d.Name
				c.Parent = model
				table.insert(list, { d, c })
			end
		end
	end
	for _, d in ipairs(ch:GetChildren()) do
		if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") then d:Clone().Parent = model end
	end
	local hum = Instance.new("Humanoid")
	hum.EvaluateStateMachine = false
	hum.RequiresNeck = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = model
	if #list == 0 then model:Destroy(); return end
	model.Parent = workspace
	st.self = { model = model, list = list, char = ch }
	if RunService:IsStudio() then
		print(("[DeathCam] ton corps : %d pièces copiées (%s)"):format(#list, ch:GetFullName()))
	end
end
local function updateSelfMirror(st)
	if not st.self then
		-- réessaie quelques fois (le corps peut arriver une image plus tard)
		st.selfTries = (st.selfTries or 0) + 1
		if st.selfTries > 120 or st.selfTries % 10 ~= 1 then return end
		buildSelfMirror(st)
		if not st.self then return end
	end
	local S = st.self
	if not S.model.Parent then return end
	local parts, cfs = {}, {}
	for _, e in ipairs(S.list) do
		local real, c = e[1], e[2]
		if real.Parent then
			table.insert(parts, c)
			table.insert(cfs, real.CFrame)
			if real.LocalTransparencyModifier ~= 1 then
				if e[3] == nil then e[3] = real.LocalTransparencyModifier end   -- valeur d'origine (rendue à la fin)
				real.LocalTransparencyModifier = 1   -- pas de double affichage
			end
		elseif c.Parent then
			c.Parent = nil
		end
	end
	if #parts > 0 then workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
end
local function destroySelfMirror(st)
	if st.self then
		-- ton vrai corps redevient visible (il restait invisible si l'écran de mort finissait avant le respawn)
		for _, e in ipairs(st.self.list) do
			local real = e[1]
			if real.Parent then real.LocalTransparencyModifier = e[3] or 0 end
		end
		st.self.model:Destroy()
		st.self = nil
	end
end
local function destroyClone(st)
	local cl = st.clone
	if not cl then return end
	st.clone = nil
	if cl.lights then for _, l in pairs(cl.lights) do pcall(function() l:Destroy() end) end end
	cl.model:Destroy()
end

local buildHud
local function buildClone(st, m)
	destroyClone(st)
	if destroyHud then destroyHud(st) end
	local kc = st.killer.Character
	local model = Instance.new("Model")
	model.Name = "DeathCamKillerView"
	local cl = { model = model, id = m.id, parts = {}, rest = {}, baseT = {}, n = #m.list, lights = {} }
	local function arm(name, size, t)
		local real = kc and kc:FindFirstChild(name)
		local a = visualClone(real)
		if not a then return nil end
		if typeof(size) == "Vector3" then a.Size = size end
		a.Transparency = tonumber(t) or 0
		a.Name = name
		a.Parent = model
		return a
	end
	cl.armR = arm("Right Arm", m.rs, m.rt)
	cl.armL = arm("Left Arm", m.ls, m.lt)
	cl.armRT, cl.armLT = tonumber(m.rt) or 0, tonumber(m.lt) or 0
	if kc then
		for _, d in ipairs(kc:GetChildren()) do
			if d:IsA("Shirt") or d:IsA("BodyColors") then d:Clone().Parent = model end
		end
	end
	local hum = Instance.new("Humanoid")
	hum.EvaluateStateMachine = false
	hum.RequiresNeck = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = model
	for i, e in ipairs(m.list) do
		cl.rest[i] = typeof(e.r) == "CFrame" and e.r or CFrame.identity
		cl.baseT[i] = tonumber(e.b) or 0
		local c = visualClone(e.p)
		if c then
			c.Transparency = 1
			c.Parent = model
			cl.parts[i] = c
		end
	end
	st.clone = cl
	-- flash de bouche préparé comme chez lui (palette + échelle 1re personne)
	if VFX and type(m.setups) == "table" then
		for _, su in ipairs(m.setups) do
			local host = cl.parts[su.i]
			if host then
				replaying = true
				pcall(VFX.SetupMuzzle, host, su.s, su.p)
				replaying = false
			end
		end
	end
	-- (au cas où sa préparation n'a pas été vue) flash de ton système préparé avec l'échelle 1re personne
	if VFX and VFX.SetupMuzzle and not (m.hud and m.hud.gun) then
		for i, part in pairs(cl.parts) do
			if part.Name == "Flash" and not part:FindFirstChild("MFlash") then
				replaying = true
				pcall(VFX.SetupMuzzle, part, VFX.Config and VFX.Config.MuzzleFPScale or 0.5, nil)
				replaying = false
			end
		end
	end
	if buildHud then buildHud(st, m.hud) end
end

---------------------------------------------------------------------
-- 🎯 SON VISEUR / SES HITMARKERS / SA LUNETTE / SES MUNITIONS (mêmes réglages que son arme)
---------------------------------------------------------------------
local function hudFrame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props) do f[k] = v end
	f.Parent = parent
	return f
end

buildHud = function(st, Hc)
	if not Hc or D.KillerHUD == false then return end
	local C = type(Hc.cursor) == "table" and Hc.cursor or {}
	local HS = type(Hc.head) == "table" and Hc.head or {}
	local HM = type(HS.Marker) == "table" and HS.Marker or {}
	local scale = Hc.mobile and 1 or (C.PCScale or 1)
	local color, outline = C.Color or Color3.new(1, 1, 1), C.Outline or Color3.new(0, 0, 0)
	local L, T, G = (C.LineLength or 8) * scale, (C.LineThickness or 2) * scale, (C.Gap or 6) * scale
	local dotSize = (C.DotSize or 0) * scale
	local hitL, hitT, hitOff = (C.HitLength or 10) * scale, (C.HitThickness or 2) * scale, (C.HitOffset or 8) * scale
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathCamKillerCursor"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	end)
	gui.DisplayOrder = 58
	gui.Enabled = false
	gui.Parent = playerGui
	local total = math.max((L + G) * 2, (hitOff + hitL) * 3) + 8
	local ct = hudFrame(gui, { Name = "Crosshair", Size = UDim2.fromOffset(total, total), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1 })
	local lines = {}
	do
		local halo = hudFrame(ct, { Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset((L + G) * 2.4, (L + G) * 2.4), BackgroundTransparency = 1 })
		Instance.new("UICorner", halo).CornerRadius = UDim.new(1, 0)
		local hst = Instance.new("UIStroke"); hst.Color = color; hst.Thickness = 1; hst.Transparency = 0.82; hst.Parent = halo
		--  🚫 pas de rond autour du viseur dans la vue du tueur (comme en jeu : il
		--     ressemblait au cercle de l'aim assist). Gardé caché, jamais réaffiché.
		halo.Visible = false
		local function line(name, sx, sy, px, py, ax, ay, rotn, fadeOutFirst)
			local f = hudFrame(ct, { Name = name, Size = UDim2.fromOffset(sx, sy), AnchorPoint = Vector2.new(ax, ay),
				Position = UDim2.new(0.5, px, 0.5, py), BackgroundColor3 = color })
			Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
			local s2 = Instance.new("UIStroke"); s2.Color = outline; s2.Thickness = 1; s2.Transparency = 0.35; s2.Parent = f
			local gr = Instance.new("UIGradient"); gr.Rotation = rotn
			local a, b = fadeOutFirst and 0.75 or 0, fadeOutFirst and 0 or 0.75
			gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
			gr.Parent = f
			f:SetAttribute("BX", px); f:SetAttribute("BY", py)
			table.insert(lines, f)
		end
		line("Top", T, L, 0, -G, 0.5, 1, 90, true)
		line("Bottom", T, L, 0, G, 0.5, 0, 90, false)
		line("Left", L, T, -G, 0, 1, 0.5, 0, true)
		line("Right", L, T, G, 0, 0, 0.5, 0, false)
		if dotSize > 0 then
			local dot = hudFrame(ct, { Name = "Dot", Size = UDim2.fromOffset(dotSize, dotSize), AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = color })
			Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
			local ds = Instance.new("UIStroke"); ds.Color = color; ds.Thickness = 2; ds.Transparency = 0.6; ds.Parent = dot
			table.insert(lines, dot)
		end
	end
	local marks = {}
	local function hitMark(name, ox, oy, rotn)
		local mk = hudFrame(ct, { Name = name, Size = UDim2.fromOffset(hitT, hitL), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, ox, 0.5, oy), Rotation = rotn, BackgroundColor3 = C.HitColor or Color3.new(1, 1, 1),
			BackgroundTransparency = 1 })
		mk:SetAttribute("BX", ox); mk:SetAttribute("BY", oy)
		Instance.new("UICorner", mk).CornerRadius = UDim.new(1, 0)
		local s2 = Instance.new("UIStroke"); s2.Color = outline; s2.Thickness = 1; s2.Transparency = 1; s2.Parent = mk
		table.insert(marks, mk)
	end
	hitMark("HitMark_NW", -hitOff, -hitOff, -45); hitMark("HitMark_NE", hitOff, -hitOff, 45)
	hitMark("HitMark_SW", -hitOff, hitOff, 45); hitMark("HitMark_SE", hitOff, hitOff, -45)
	local RH = type(Hc.rhud) == "table" and Hc.rhud or {}
	if FX2 then
		pcall(FX2.RingBuild, ct, scale)
		if RH.Gauge ~= false then
			pcall(FX2.GaugeBuild, ct, scale, (Hc.style == "Shell") and "shells" or "bar", Hc.clip or 30)
		end
	end
	local rt = Instance.new("TextLabel")
	rt.Name = "ReloadingText"; rt.Size = UDim2.fromOffset(110, 16); rt.AnchorPoint = Vector2.new(0, 0.5)
	rt.Position = UDim2.new(0.5, 22 * scale, 0.5, 0); rt.BackgroundTransparency = 1; rt.Text = "Reloading"
	rt.TextXAlignment = Enum.TextXAlignment.Left; rt.TextColor3 = Color3.new(1, 1, 1)
	rt.TextStrokeColor3 = Color3.new(0, 0, 0); rt.TextStrokeTransparency = 0.35; rt.Font = Enum.Font.GothamMedium
	rt.TextTransparency = 0.15; rt.TextSize = Hc.mobile and 12 or 13; rt.Visible = false; rt.ZIndex = 30; rt.Parent = ct

	local U = { gui = gui, ct = ct, lines = lines, marks = marks, C = C, HS = HS, HM = HM, RH = RH, Hc = Hc,
		rt = rt, col = color, linesOn = true }

	-- lunette (sniper) de ton système
	if Hc.scope then
		local tint = Hc.tint or Color3.new(0, 0, 0)
		local sg = Instance.new("ScreenGui"); sg.Name = "DeathCamKillerScope"; sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true; sg.DisplayOrder = 57; sg.Enabled = false
		pcall(function()
			sg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
			sg.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
		end)
		sg.Parent = playerGui
		local cg = Instance.new("CanvasGroup"); cg.Name = "Canvas"; cg.Size = UDim2.fromScale(1, 1)
		cg.BackgroundTransparency = 1; cg.GroupTransparency = 1; cg.Parent = sg
		local usc = Instance.new("UIScale"); usc.Scale = 1.12; usc.Parent = cg
		for _, n in ipairs({ "Top", "Bottom", "Left", "Right" }) do hudFrame(cg, { Name = n, BackgroundColor3 = tint }) end
		local lens = hudFrame(cg, { Name = "Lens", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1 })
		Instance.new("UICorner", lens).CornerRadius = UDim.new(1, 0)
		local ring = Instance.new("UIStroke"); ring.Name = "Ring"; ring.Color = tint
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ring.Parent = lens
		local rim = hudFrame(cg, { Name = "Rim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1 })
		Instance.new("UICorner", rim).CornerRadius = UDim.new(1, 0)
		local rims = Instance.new("UIStroke"); rims.Color = Color3.fromRGB(15, 15, 15); rims.Thickness = 3; rims.Parent = rim
		local function xhair(name, sx, sy)
			return hudFrame(cg, { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(sx, sy), BackgroundColor3 = Color3.fromRGB(10, 10, 10) })
		end
		xhair("XV", 2, 4000); xhair("XH", 4000, 2)
		local dot = xhair("XDot", 6, 6); Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		U.scope = { gui = sg, cg = cg, scale = usc }
	end

	-- lunette / point rouge GunKit
	if type(Hc.gun) == "string" and type(Hc.optic) == "string" and st.clone then
		local gk = ReplicatedStorage:FindFirstChild("GunKit")
		local g = gk and gk:FindFirstChild("Guns") and gk.Guns:FindFirstChild(Hc.gun)
		local so = g and g:FindFirstChild("ScopeOverlay")
		if so then
			local ok, Overlay = pcall(require, so)
			if ok and type(Overlay) == "table" and Overlay.new then
				local ok2, ov = pcall(Overlay.new, st.clone.model)
				if ok2 then U.gkScope = ov end
			end
		end
	end
	st.hud = U
end

destroyHud = function(st)
	local U = st.hud
	if not U then return end
	st.hud = nil
	U.gui:Destroy()
	if U.scope then U.scope.gui:Destroy() end
	if U.gkScope then pcall(function() U.gkScope:Destroy() end) end
end

local function updateHud(st, h, dt)
	local U = st.hud
	if not U then return end
	if not h then
		U.gui.Enabled = false
		if U.scope then U.scope.gui.Enabled = false end
		return
	end
	local cam = workspace.CurrentCamera
	local vp = cam.ViewportSize
	U.gui.Enabled = true
	U.ct.Visible = h.on
	local pos = Vector2.new(h.x * vp.X, h.y * vp.Y)
	U.ct.Position = UDim2.fromOffset(pos.X, pos.Y)
	if U.linesOn ~= h.lines then
		U.linesOn = h.lines
		for _, f in ipairs(U.lines) do f.Visible = h.lines end
	end
	-- écartement (dispersion) : même calcul que son viseur
	if U.px ~= h.px then
		U.px = h.px
		for _, f in ipairs(U.lines) do
			local bx, by = f:GetAttribute("BX"), f:GetAttribute("BY")
			if bx then
				local ox = (bx > 0 and h.px) or (bx < 0 and -h.px) or 0
				local oy = (by > 0 and h.px) or (by < 0 and -h.px) or 0
				f.Position = UDim2.new(0.5, bx + ox, 0.5, by + oy)
			end
		end
	end
	if h.col and h.col ~= U.col then
		U.col = h.col
		for _, f in ipairs(U.lines) do f.BackgroundColor3 = h.col end
	end
	-- munitions / rechargement
	local RH = U.RH
	if FX2 then
		local ring = U.ct:FindFirstChild("ReloadRing")
		if ring then
			if h.rl and RH.Loop == true then
				pcall(FX2.RingSet, ring, true, h.rl, h.segs, os.clock())
			elseif ring.Visible and (os.clock() - (U.rlDone or 0)) > 0.2 then
				ring.Visible = false
			end
		end
		local g = U.ct:FindFirstChild("AmmoGauge")
		if g then
			local clip = math.max(1, U.Hc.clip or 30)
			local f, cnt = h.ammo / clip, h.ammo
			if h.rl and not h.segs then
				local from = (h.rlFrom or h.ammo) / clip
				f = from + (1 - from) * h.rl
				cnt = nil
			end
			pcall(FX2.GaugeSet, g, f, cnt, dt)
		end
		if U.wasRl and not h.rl then
			U.rlDone = os.clock()
			if ring and ring.Visible then pcall(FX2.RingDone, ring) end
			if g then pcall(FX2.GaugePop, g) end
		end
	end
	U.wasRl = h.rl ~= nil
	U.rt.Visible = h.rl ~= nil and RH.Text == true
	-- lunette de ton système
	local SC = U.scope
	if SC then
		local a = h.scope or 0
		SC.gui.Enabled = a > 0.001
		SC.cg.GroupTransparency = 1 - a
		SC.scale.Scale = 1 + (1 - a) * 0.12
		if a > 0.001 then
			local Dm = math.min(vp.X, vp.Y) * 0.86
			local cx, cy = pos.X, pos.Y
			local left, top, right, bottom = cx - Dm / 2, cy - Dm / 2, cx + Dm / 2, cy + Dm / 2
			local cg = SC.cg
			local function set(n, sx, sy, px, py)
				local f = cg:FindFirstChild(n)
				if f then f.Size = UDim2.fromOffset(sx, sy); f.Position = UDim2.fromOffset(px, py) end
			end
			set("Top", vp.X, math.max(0, math.ceil(top)), 0, 0)
			set("Bottom", vp.X, math.max(0, math.ceil(vp.Y - bottom)), 0, math.floor(bottom))
			set("Left", math.max(0, math.ceil(left)), math.ceil(Dm), 0, math.floor(top))
			set("Right", math.max(0, math.ceil(vp.X - right)), math.ceil(Dm), math.floor(right), math.floor(top))
			for _, n in ipairs({ "Lens", "Rim", "XV", "XH", "XDot" }) do
				local p2 = cg:FindFirstChild(n)
				if p2 then p2.Position = UDim2.fromOffset(cx, cy) end
			end
			local lens = cg:FindFirstChild("Lens")
			if lens then
				lens.Size = UDim2.fromOffset(Dm, Dm)
				local ring2 = lens:FindFirstChild("Ring"); if ring2 then ring2.Thickness = Dm * 0.25 end
			end
			local rim = cg:FindFirstChild("Rim"); if rim then rim.Size = UDim2.fromOffset(Dm, Dm) end
		end
	end
	if U.gkScope then pcall(U.gkScope.Update, U.gkScope, h.aim or 0, U.Hc.optic, dt) end
end

-- ses hitmarkers (même animation que les siens)
local function hitMarkers(st, isHead)
	local U = st.hud
	if not U then return end
	local C, HM = U.C, U.HM
	local col = isHead and (HM.Color or Color3.fromRGB(255, 60, 60)) or (C.HitColor or Color3.new(1, 1, 1))
	local spread = isHead and (C.HitSpreadHead or 1.2) or (C.HitSpread or 1.1)
	local start = isHead and (C.HitStartHead or 1.9) or (C.HitStart or 1.6)
	local tm = isHead and (C.HitHeadTimeMult or 1.25) or 1
	local hold = (C.HitHold or 0) * tm
	local fade = math.max(0.01, (C.HitFade or 0.5) * tm)
	local okS, style = pcall(function() return Enum.EasingStyle[C.HitFadeStyle or "Sine"] end)
	if not okS or not style then style = Enum.EasingStyle.Sine end
	local okP, popStyle = pcall(function() return Enum.EasingStyle[C.HitSpreadStyle or "Sine"] end)
	if not okP or not popStyle then popStyle = Enum.EasingStyle.Sine end
	local tiPop = TweenInfo.new(C.HitSpreadTime or 0.30, popStyle, Enum.EasingDirection.Out)
	local tiFade = TweenInfo.new(fade, style, Enum.EasingDirection.InOut, 0, false, hold)
	for _, mk in ipairs(U.marks) do
		local bx, by = mk:GetAttribute("BX") or 0, mk:GetAttribute("BY") or 0
		mk.BackgroundColor3 = col
		if mk.BackgroundTransparency > 0.6 then mk.Position = UDim2.new(0.5, bx * start, 0.5, by * start) end
		mk.BackgroundTransparency = 0
		TweenService:Create(mk, tiPop, { Position = UDim2.new(0.5, bx * spread, 0.5, by * spread) }):Play()
		TweenService:Create(mk, tiFade, { BackgroundTransparency = 1 }):Play()
		local s2 = mk:FindFirstChildWhichIsA("UIStroke")
		if s2 then s2.Transparency = 0.3; TweenService:Create(s2, tiFade, { Transparency = 1 }):Play() end
	end
	-- petit « pop » du viseur (l'anneau, lui, arrive par l'enregistrement de ses effets)
	if HM.Enabled ~= false and (isHead or C.HitRingNormal ~= false) then
		local punch = HM.CrosshairPunch or 1.35
		if not isHead then punch = 1 + (punch - 1) * (C.HitPunchScale or 0.5) end
		if punch > 1 then
			local ui = U.ct:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", U.ct)
			ui.Scale = punch
			TweenService:Create(ui, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
end

-- ses chiffres de dégâts
local popupGui
local function damagePopup(st, rootPart, damage, isHead)
	if typeof(rootPart) ~= "Instance" or not rootPart.Parent then return end
	if not popupGui or not popupGui.Parent then
		popupGui = Instance.new("ScreenGui")
		popupGui.Name = "DeathCamKillerPopups"; popupGui.ResetOnSpawn = false
		popupGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; popupGui.DisplayOrder = 10
		popupGui.Parent = playerGui
	end
	local HS = (st.hud and st.hud.HS) or {}
	local lb = Instance.new("TextLabel")
	lb.Size = UDim2.fromOffset(160, 70); lb.AnchorPoint = Vector2.new(0.5, 0.5)
	lb.BackgroundTransparency = 1; lb.Font = Enum.Font.FredokaOne
	local baseSize = isHead and (HS.TextSize or 30) or 24
	lb.TextSize = baseSize; lb.Text = tostring(damage)
	lb.TextColor3 = isHead and (HS.Color or Color3.fromRGB(255, 60, 60)) or Color3.new(1, 1, 1)
	lb.TextStrokeTransparency = 0.2; lb.TextStrokeColor3 = Color3.new(0, 0, 0); lb.Parent = popupGui
	local ox, oy = math.random(-30, 30), math.random(-10, 10)
	local t0, dur = os.clock(), 1.2
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local e = os.clock() - t0
		if e >= dur or not lb.Parent or not rootPart.Parent or not state then
			conn:Disconnect(); lb:Destroy(); return
		end
		local t = e / dur
		local cam = workspace.CurrentCamera
		local sp, on = cam:WorldToViewportPoint(rootPart.Position + Vector3.new(0, 3.5, 0))
		if on then
			lb.Visible = true
			local vp = cam.ViewportSize
			lb.Position = UDim2.fromOffset(math.clamp(sp.X + ox, 50, vp.X - 50), math.clamp(sp.Y - 80 - t * 60 + oy, 50, vp.Y - 100))
		else
			lb.Visible = false
		end
		lb.TextTransparency = math.clamp(t * 1.5 - 0.2, 0, 1)
		lb.TextStrokeTransparency = 0.2 + math.clamp(t * 1.5 - 0.2, 0, 0.8)
		if isHead and (HS.Pop or 0) > 0 then
			local k = 1 - math.clamp(e / 0.12, 0, 1)
			lb.TextSize = math.floor(baseSize * (1 + HS.Pop * k))
		end
	end)
end

-- flash blanc sur sa cible
local function enemyFlash(char)
	local pl = typeof(char) == "Instance" and Players:GetPlayerFromCharacter(char)
	if not pl then return end
	local hl = char:FindFirstChild("ArenaOutline_" .. pl.UserId)
	if not hl or not hl:IsA("Highlight") or not hl.Enabled then return end
	hl.FillColor = Color3.fromRGB(255, 248, 236)
	hl.FillTransparency = 0.25
	TweenService:Create(hl, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1 }):Play()
end

-- ses douilles (ancien système physique)
local function oldShell(e)
	if typeof(e.cf) ~= "CFrame" or type(e.L) ~= "number" or type(e.D) ~= "number" then return end
	local shell = Instance.new("Part")
	shell.Name = "Shell"; shell.Shape = Enum.PartType.Cylinder
	shell.Size = Vector3.new(e.L, e.D, e.D)
	shell.Color = e.c or Color3.fromRGB(200, 160, 60); shell.Material = e.m or Enum.Material.Metal
	shell.Reflectance = 0.18; shell.CanCollide = false; shell.CanQuery = false; shell.CanTouch = false
	shell.CFrame = e.cf
	shell.Parent = workspace
	local cap = Instance.new("Part")
	cap.Name = "Cap"; cap.Shape = Enum.PartType.Cylinder
	cap.Size = Vector3.new(e.D * 0.35, e.D * 1.04, e.D * 1.04)
	cap.Color = shell.Color:Lerp(Color3.new(0, 0, 0), 0.5)
	cap.Material = Enum.Material.Metal; cap.CanCollide = false; cap.Massless = true
	cap.CFrame = shell.CFrame * CFrame.new(-e.L / 2 + e.D * 0.15, 0, 0)
	cap.Parent = shell
	local w = Instance.new("WeldConstraint"); w.Part0 = shell; w.Part1 = cap; w.Parent = shell
	if typeof(e.v) == "Vector3" then shell.AssemblyLinearVelocity = e.v end
	if typeof(e.w) == "Vector3" then shell.AssemblyAngularVelocity = e.w end
	Debris:AddItem(shell, tonumber(e.life) or 3)
end

-- rejoue UN effet du tueur
local function resolve(st, a)
	if type(a) ~= "table" then return nil end
	if a.v then
		local cl = st.clone
		if not cl or (a.m and a.m ~= cl.id) then return nil end
		return cl.parts[a.v]
	end
	if a.i ~= nil then return typeof(a.i) == "Instance" and a.i.Parent and a.i or nil end
	return a.p
end
local function vpPos(p)
	local vp = workspace.CurrentCamera.ViewportSize
	return (type(p) == "table" and p.x) and Vector2.new(p.x * vp.X, p.y * vp.Y) or vp / 2
end
local function replay(st, e)
	local k = e.k
	local fxOn = D.KillerFX ~= false
	if k == "snd" then
		if D.KillerSounds == false or type(e.id) ~= "string" or e.id == "" then return end
		local s = Instance.new("Sound")
		s.SoundId = e.id; s.Volume = tonumber(e.v) or 0.5; s.PlaybackSpeed = tonumber(e.sp) or 1
		s.Parent = SoundService
		s.TimePosition = tonumber(e.tp) or 0
		s:Play()
		Debris:AddItem(s, 10)
	elseif k == "h" then
		hitMarkers(st, e.h == true)
	elseif k == "d" then
		if D.KillerPopups ~= false then damagePopup(st, e.p, e.n, e.h == true) end
	elseif k == "f" then
		if D.KillerPopups ~= false then enemyFlash(e.c) end
	elseif k == "hm" then
		if VFX and VFX.HeadshotMarker and type(e.M) == "table" then VFX.HeadshotMarker(playerGui, vpPos(e.pos), e.M) end
	elseif k == "km" then
		if VFX and VFX.KillMarker and type(e.M) == "table" then VFX.KillMarker(playerGui, vpPos(e.pos), e.M) end
	elseif not fxOn then
		return
	elseif k == "su" then
		local host = resolve(st, e.a)
		if VFX and host then VFX.SetupMuzzle(host, e.s, e.p) end
	elseif k == "em" then
		local host = resolve(st, e.a)
		if VFX and typeof(host) == "Instance" then VFX.EmitMuzzle(host, e.sm) end
	elseif k == "sf" then
		local host = resolve(st, e.a)
		if VFX and host then VFX.StarFlash(host, e.p, e.s) end
	elseif k == "fl" then
		local host = resolve(st, e.a)
		if FX2 and host then FX2.Flash(host, e.c1, e.c2, e.s) end
	elseif k == "gk" then
		local host = resolve(st, e.a)
		local MF = gkMods[e.g]
		if MF and typeof(host) == "Instance" then
			MF._remote = true
			pcall(MF.Emit, host, e.fp, e.sm)
			MF._remote = nil
		end
	elseif k == "mz" then
		local host = resolve(st, e.a)
		if type(MZ) == "table" and typeof(host) == "Instance" then
			MZ.Shot(nil, host, e.fp == true, nil, st.killer)
		end
	elseif k == "tr" then
		if VFX and typeof(e.a) == "Vector3" and typeof(e.b) == "Vector3" then VFX.Tracer(e.a, e.b, e.T, nil) end
	elseif k == "sh" then
		if FX2 and typeof(e.cf) == "CFrame" then
			local cam = workspace.CurrentCamera
			local ign = { cam }
			if st.clone then table.insert(ign, st.clone.model) end
			if st.killer.Character then table.insert(ign, st.killer.Character) end
			pcall(FX2.ShellIgnore, ign)
			FX2.Shell(e.cf, e.v, e.o)
		end
	elseif k == "sho" then
		oldShell(e)
	elseif k == "dr" then
		local host = resolve(st, e.a)
		if FX2 and typeof(host) == "Instance" then FX2.Drop(host, e.cf, e.v, e.o) end
	elseif k == "lt" then
		local host = resolve(st, e.a)
		local cl = st.clone
		if typeof(host) == "Instance" and cl and (e.cls == "PointLight" or e.cls == "SpotLight" or e.cls == "SurfaceLight") then
			local l = Instance.new(e.cls)
			if e.c then l.Color = e.c end
			if e.b then l.Brightness = e.b end
			if e.r then l.Range = e.r end
			l.Shadows = e.sh == true
			l.Parent = host
			cl.lights[e.id] = l
			Debris:AddItem(l, 3)
		end
	elseif k == "ltx" then
		local cl = st.clone
		local l = cl and cl.lights[e.id]
		if l then l:Destroy(); cl.lights[e.id] = nil end
	end
end

local function runEvents(st, renderT)
	local q = st.events
	while #q > 0 and q[1].t <= renderT do
		local e = table.remove(q, 1)
		replaying = true
		local ok, err = pcall(replay, st, e)
		replaying = false
		if not ok and not st.warnedFx then
			st.warnedFx = true
			warn("[DeathCam] effet " .. tostring(e.k) .. " : " .. tostring(err))
		end
	end
end

local function lerpCF(a, b, t)
	if not a then return b end
	if not b then return a end
	return a:Lerp(b, t)
end

local function renderSpectate(dt)
	local st = state
	if not st or not st.viewing then return end
	local buf = st.buf
	if #buf == 0 then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	if st.spectateCamera ~= cam then
		if st.spectateCamera then st.spectateCamera:SetAttribute("KeepScriptable", nil) end
		st.spectateCamera = cam
		cam:SetAttribute("KeepScriptable", true)
	end
	local renderT = workspace:GetServerTimeNow() - (st.lat or 0.1) - (D.ViewDelay or 0.12)
	local a, b = buf[1], buf[1]
	for i = 1, #buf do
		if buf[i].t <= renderT then a = buf[i]; b = buf[i + 1] or buf[i] else b = buf[i]; break end
	end
	local alpha = 0
	if b ~= a and b.t > a.t then alpha = math.clamp((renderT - a.t) / (b.t - a.t), 0, 1) end
	-- caméra ATTACHÉE à son perso (tel que tu le vois) : plus de retard / décalage, en 1re comme en 3e personne
	local kc = st.killer.Character
	local kroot = kc and kc:FindFirstChild("HumanoidRootPart")
	local relCam = lerpCF(a.cam, (b.camRel == a.camRel) and b.cam or a.cam, alpha)
	local camCF
	if a.camRel then
		camCF = kroot and (CFrame.new(kroot.Position) * relCam) or st.lastCam or cam.CFrame
	else
		camCF = relCam
	end
	st.lastCam = camCF
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
	cam.CFrame = camCF
	cam.FieldOfView = a.fov + (b.fov - a.fov) * alpha

	-- ton corps (ragdoll) : une copie visuelle qui suit ton vrai corps pièce par pièce, toujours visible
	-- (ton arme / la caméra Roblox cachaient ton perso localement)
	updateSelfMirror(st)

	-- bras + arme pièce par pièce (1re personne : son viewmodel ; 3e personne : ses vrais bras + sa vraie arme)
	local cl = st.clone
	local third = a.third == true
	local showVm = cl ~= nil and a.vm and a.mid == cl.id and D.ShowKillerViewmodel ~= false
		and (not third or kroot ~= nil)

	-- ce qu'on cache du tueur : tout (dans sa tête) / seulement ses bras + son arme (3e personne, remplacés)
	local head = kc and kc:FindFirstChild("Head")
	local nearHead = head ~= nil and (head.Position - camCF.Position).Magnitude < ((st.hideMode == "full") and 6 or 2.5)
	local mode = nil
	if not kc then
		mode = nil
	elseif showVm then
		mode = (third and not nearHead) and "arms" or "full"
	elseif (a.vm and not third) or nearHead then
		mode = "full"
	end
	if mode ~= st.hideMode then
		st.hideMode = mode
		st.hidden = mode ~= nil
		unhideAll(st)
		st.sharedModel = nil
		st.hiddenTool = nil
		if mode == "full" then
			hideTree(kc)
		elseif mode == "arms" then
			hideTree(kc:FindFirstChild("Right Arm"))
			hideTree(kc:FindFirstChild("Left Arm"))
			st.hiddenTool = kc:FindFirstChildOfClass("Tool")
			hideTree(st.hiddenTool)
		end
	end
	-- 3e personne : il a changé d'arme → la nouvelle vraie arme est cachée aussi (notre copie la remplace)
	if st.hideMode == "arms" then
		local t = kc:FindFirstChildOfClass("Tool")
		if t ~= st.hiddenTool then st.hiddenTool = t; hideTree(t) end
	end
	if st.hidden then keepHidden(st) end

	if showVm then
		if cl.model.Parent ~= workspace then cl.model.Parent = workspace end
		local bvm = b.vm and b.mid == cl.id and b.third == a.third
		local vb = bvm and b or a
		local visA = a.vis
		local visNow = (alpha >= 0.5 and bvm) and b.vis or a.vis
		local base = third and kroot.CFrame or camCF
		local parts, cfs = {}, {}
		local n = cl.n
		if cl.armR then
			table.insert(parts, cl.armR); table.insert(cfs, base * lerpCF(a.r, vb.r, alpha))
			local tr = visNow[n + 1] and cl.armRT or 1
			if cl.armR.Transparency ~= tr then cl.armR.Transparency = tr end
		end
		if cl.armL then
			table.insert(parts, cl.armL); table.insert(cfs, base * lerpCF(a.l, vb.l, alpha))
			local tl = visNow[n + 2] and cl.armLT or 1
			if cl.armL.Transparency ~= tl then cl.armL.Transparency = tl end
		end
		local hcf = base * lerpCF(a.h, vb.h, alpha)
		local ma, mb = a.moved or {}, vb.moved or {}
		for i, part in pairs(cl.parts) do
			local ra = ma[i] or cl.rest[i]
			local rb = mb[i] or cl.rest[i]
			local rel
			if not (visA[i] and vb.vis[i]) or (ra.Position - rb.Position).Magnitude > 1.5 then
				rel = (alpha >= 0.5) and rb or ra      -- apparition / saut : pas de glissade à travers l'écran
			else
				rel = ra:Lerp(rb, alpha)
			end
			table.insert(parts, part)
			table.insert(cfs, hcf * rel)
			local tp = visNow[i] and cl.baseT[i] or 1
			if part.Transparency ~= tp then part.Transparency = tp end
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	elseif cl and cl.model.Parent ~= nil then
		cl.model.Parent = nil
	end

	-- son viseur / sa lunette
	local h = (alpha >= 0.5 and b.hud) or a.hud
	updateHud(st, h, dt)

	-- ses effets, au même instant que l'image
	runEvents(st, renderT)
end

-- Rendre la caméra au personnage courant, même si son Humanoid arrive plus tard.
-- Cette liaison est temporaire : elle ne force jamais la souris pendant le jeu.
local restoreOnRespawn = nil
local function restorePlayerCamera(st, character)
	RunService:UnbindFromRenderStep("DeathCamRestore")
	local deadline = os.clock() + 10
	local function restore()
		if state or player.Character ~= character then return true end
		local cam = workspace.CurrentCamera
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not cam or not hum then return os.clock() >= deadline end
		cam:SetAttribute("KeepScriptable", nil)
		cam.CameraSubject = hum
		cam.CameraType = Enum.CameraType.Custom
		if st.fov then cam.FieldOfView = st.fov end
		return true
	end
	if restore() then return end
	RunService:BindToRenderStep("DeathCamRestore", Enum.RenderPriority.Camera.Value - 1, function()
		if restore() then RunService:UnbindFromRenderStep("DeathCamRestore") end
	end)
end

---------------------------------------------------------------------
-- 🖱️ SOURIS : jamais bloquée au centre sans raison
---------------------------------------------------------------------
-- Une SEULE garde, toujours active (PC) :
--   • pendant l'écran de mort : souris libre à chaque image (le bouton RESPAWN reste cliquable)
--   • sinon : un verrou est accepté seulement s'il est justifié (arme en main, 1re personne, Maj-lock,
--     clic droit maintenu…). Un verrou « coincé » (ton arme est morte avec ton ancien perso, mort par un
--     bot sans écran de mort, etc.) est libéré à CHAQUE image, après tous les autres scripts
--     (dernière priorité de rendu + Heartbeat) → un script qui re-verrouille en boucle ne gagne plus.
local DEBUG_MOUSE = false   -- true = affiche dans la console QUI change MouseBehavior et quand (pour diagnostiquer)

local MB = Enum.MouseBehavior
local GUARD_STEP = "DeathCamMouseGuard"
local GUARD_PRIORITY = Enum.RenderPriority.Last.Value + 50   -- après les scripts liés à « Last »
local MOUSE_GUARD = D.MouseGuard ~= false
local UGS = nil
pcall(function() UGS = UserSettings():GetService("UserGameSettings") end)
local lastStopAt = nil

local function freeMouse(withIcon)
	if IS_TOUCH then return end
	if UserInputService.MouseBehavior ~= MB.Default then UserInputService.MouseBehavior = MB.Default end
	if withIcon and not UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = true end
end

if DEBUG_MOUSE then
	UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
		print(("[DeathCam] MouseBehavior = %s | écran de mort : %s | t = %.2f\n%s"):format(
			tostring(UserInputService.MouseBehavior), tostring(state ~= nil), os.clock(), debug.traceback("", 2)))
	end)
end

local function mouseButtonDown()
	return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
end

-- Un verrou de souris est-il justifié en ce moment ?
local function lockIsLegit()
	local mb = UserInputService.MouseBehavior
	if mb == MB.Default then return true end
	if state then return false end
	-- rotation caméra au clic (droit) : légitime seulement si un bouton est réellement enfoncé
	if mb == MB.LockCurrentPosition then return mouseButtonDown() end
	-- LockCenter
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	if ch:FindFirstChildOfClass("Tool") then return true end
	local cam, head = workspace.CurrentCamera, ch:FindFirstChild("Head")
	if cam and head and (cam.CFrame.Position - head.Position).Magnitude < 2.5 then return true end
	-- Maj-lock (shift lock) activé par le joueur
	if player.DevEnableMouseLock and UGS then
		local ok, rt = pcall(function() return UGS.RotationType end)
		if ok and rt == Enum.RotationType.CameraRelative then return true end
	end
	return false
end

local badSince, iconFixed = nil, false
local function mouseGuard()
	if state then freeMouse(true) return end
	local now = os.clock()
	-- juste après un écran de mort : aucun délai de tolérance
	local recent = lastStopAt ~= nil and now - lastStopAt < 15
	if not MOUSE_GUARD and not recent then badSince = nil return end
	if lockIsLegit() then badSince, iconFixed = nil, false return end
	badSince = badSince or now
	-- (hors écran de mort : 0,25 s de tolérance, le temps qu'un script d'arme lâche la souris normalement)
	if recent or now - badSince >= 0.25 then
		if DEBUG_MOUSE and not iconFixed then
			print("[DeathCam] souris verrouillée sans raison (" .. tostring(UserInputService.MouseBehavior) .. ") → libérée")
		end
		freeMouse(not iconFixed)   -- l'icône est rendue une fois (pas de bataille avec un curseur perso)
		iconFixed = true
	end
end
if not IS_TOUCH then
	RunService:BindToRenderStep(GUARD_STEP, GUARD_PRIORITY, mouseGuard)
	RunService.Heartbeat:Connect(mouseGuard)
end

-- Fin de l'écran de mort : souris rendue tout de suite, puis 15 s de surveillance sans tolérance.
local function releaseMouse()
	freeMouse(true)
	lastStopAt = os.clock()
	badSince, iconFixed = nil, false
end

-- Le perso réapparaît un peu après la fin de l'écran de mort : la fenêtre de surveillance repart à ce moment-là.
player.CharacterAdded:Connect(function()
	if lastStopAt and os.clock() - lastStopAt < 30 then
		lastStopAt = os.clock()
		freeMouse(true)
	end
end)

local function stopSpectate()
	local st = state
	if not st then return end
	state = nil
	RunService:UnbindFromRenderStep("DeathCamView")
	if st.inputConn then st.inputConn:Disconnect() end
	if st.ui and st.ui.promptConn then st.ui.promptConn:Disconnect() end

	-- Souris : rendue tout de suite ; la garde 🖱️ s'occupe de la suite.
	releaseMouse()
	local cam = workspace.CurrentCamera
	if cam then
		cam:SetAttribute("KeepScriptable", nil)
		cam.CameraType = Enum.CameraType.Custom
	end
	if st.spectateCamera and st.spectateCamera ~= cam then
		st.spectateCamera:SetAttribute("KeepScriptable", nil)
	end
	-- Conserver la restauration si le délai de sécurité finit AVANT le respawn.
	restoreOnRespawn = player.Character == st.character and st or nil
	restorePlayerCamera(st, player.Character)

	-- Un problème de nettoyage visuel ne doit pas empêcher de rendre les contrôles.
	local function clean(fn)
		local ok, err = pcall(fn, st)
		if not ok then warn("[DeathCam] nettoyage : " .. tostring(err)) end
	end
	clean(destroyHud)
	clean(destroyClone)
	clean(destroySelfMirror)
	clean(unhideAll)
	if popupGui then popupGui:Destroy(); popupGui = nil end
	if st.ui then
		local band = st.ui.band
		tween(band, 0.18, { GroupTransparency = 1 }).Completed:Connect(function() band:Destroy() end)
	end
	if black.Visible then
		tween(black, 0.25, { BackgroundTransparency = 1 }).Completed:Connect(function()
			if not state then black.Visible = false end
		end)
	end
end

local function skip()
	local st = state
	if not st or st.skipping then return end
	if os.clock() < st.skipAt then return end
	st.skipping = true
	CombatRequest:FireServer("Respawn")
	black.Visible = true
	black.BackgroundTransparency = 1
	tween(black, 0.1, { BackgroundTransparency = 0 })
	if st.ui then tween(st.ui.band, 0.12, { GroupTransparency = 1 }) end
end

-- respawn : Espace (clavier), A / Croix (manette), un clic sur le bouton vert ;
-- sur mobile : toucher n'importe où. Sur PC, un clic ailleurs sur l'écran ne fait rien.
local SKIP_KEYS = { [Enum.KeyCode.Space] = true, [Enum.KeyCode.ButtonA] = true }

local function startSpectate(info)
	stopSpectate()
	local killer = info.killer
	if typeof(killer) ~= "Instance" or not killer:IsA("Player") then return end
	RunService:UnbindFromRenderStep("DeathCamRestore")
	restoreOnRespawn = nil
	local now = os.clock()
	local st = {
		info = info, killer = killer, buf = {}, events = {}, viewing = false, t0 = now,
		skipAt = now + (D.SkipDelay or 0.4), dur = info.time or D.SpectateTime or 5,
		-- 🩹 au respawn on remet le FOV NORMAL, pas celui du moment de la mort (visée, sprint…)
		fov = workspace.CurrentCamera and (workspace.CurrentCamera:GetAttribute("UIFocusNormalFOV") or 70),
		character = player.Character,
	}
	state = st
	freeMouse(true)   -- tout de suite (la garde 🖱️ la garde libre ensuite à chaque image)
	st.ui = buildBand(info, skip)
	tween(st.ui.band, 0.22, { GroupTransparency = 0 })
	st.inputConn = UserInputService.InputBegan:Connect(function(input)
		-- mobile : toucher N'IMPORTE OÙ fait respawn (PC : seulement Espace / A / le bouton)
		if IS_TOUCH and input.UserInputType == Enum.UserInputType.Touch then skip() return end
		if not SKIP_KEYS[input.KeyCode] then return end
		if UserInputService:GetFocusedTextBox() then return end
		skip()
	end)
	RunService:BindToRenderStep("DeathCamView", Enum.RenderPriority.Camera.Value + 10, function(dt)
		local s2 = state
		if not s2 then return end
		local el = os.clock() - s2.t0
		if el > s2.dur + 4 then stopSpectate() return end   -- sécurité : jamais coincé
		if s2.ui then
			s2.ui.bar.Size = UDim2.fromScale(math.clamp(1 - el / s2.dur, 0, 1), 1)
			local fx = s2.ui.vipFx
			if fx then
				local c = os.clock() % 9
				fx.sheen.Offset = (c < 2.6) and Vector2.new(-1 + (c / 2.6) * 2, 0) or Vector2.new(1, 0)
				for _, sp in ipairs(fx.sparks) do
					local f = ((os.clock() * 0.35) + sp.phase) % 1
					sp.f.Position = UDim2.fromScale(sp.x, 0.2 - f * 0.18)
					sp.f.BackgroundTransparency = 0.15 + 0.85 * (f ^ 1.5)
				end
			end
		end
		local ok, err = pcall(renderSpectate, dt)
		if not ok and not s2.warned then
			s2.warned = true
			warn("[DeathCam] " .. tostring(err))
		end
	end)
end

-- images de sa vue (non fiables, ~30 / s)
Stream.OnClientEvent:Connect(function(killer, b)
	local st = state
	if not st or killer ~= st.killer then return end
	local ok, pk = pcall(Codec.Decode, b)
	if not ok or not pk then return end
	local buf = st.buf
	local last = buf[#buf]
	if last and pk.t <= last.t then return end   -- image arrivée dans le désordre
	-- image partielle (trop de pièces en mouvement) : les autres gardent leur dernière place
	if pk.partial and last and last.mid == pk.mid and last.moved and pk.moved and pk.disp then
		for i, cf in pairs(last.moved) do
			if pk.moved[i] == nil and pk.disp[i] then pk.moved[i] = cf end
		end
	end
	-- manifeste manquant (perdu / limité) : on le redemande
	if pk.vm and (not st.clone or st.clone.id ~= pk.mid) then
		st.missSince = st.missSince or os.clock()
		if os.clock() - st.missSince > 0.4 and os.clock() - (st.askedAt or 0) > 1 then
			st.askedAt = os.clock()
			CombatRequest:FireServer("KVReq", killer)
		end
	else
		st.missSince = nil
	end
	local lat = workspace:GetServerTimeNow() - pk.t
	if lat > -0.5 and lat < 2 then st.lat = st.lat and (st.lat + (lat - st.lat) * 0.2) or lat end
	table.insert(buf, pk)
	if #buf > 60 then table.remove(buf, 1) end
	if not st.viewing then
		st.viewing = true
		local cam = workspace.CurrentCamera
		if cam then
			st.spectateCamera = cam
			cam:SetAttribute("KeepScriptable", true)   -- ton WeaponDeathWatchdog laisse la caméra tranquille
			cam.CameraType = Enum.CameraType.Scriptable
		end
	end
end)

CombatEvent.OnClientEvent:Connect(function(kind, a, b)
	if kind == "Spectate" and type(a) == "table" then
		startSpectate(a)
	elseif kind == "KVM" then
		-- manifeste : les pièces de son arme 1re personne (fiable)
		local st = state
		if st and a == st.killer and type(b) == "table" and type(b.list) == "table"
			and not (st.clone and st.clone.id == b.id) then
			local ok, err = pcall(buildClone, st, b)
			if not ok then warn("[DeathCam] arme du tueur : " .. tostring(err)) end
		end
	elseif kind == "KVE" then
		-- ses effets (fiables, dans l'ordre)
		local st = state
		if st and a == st.killer and type(b) == "table" then
			for _, e in ipairs(b) do
				if type(e) == "table" and type(e.k) == "string" and type(e.t) == "number" then
					table.insert(st.events, e)
				end
			end
			while #st.events > 300 do table.remove(st.events, 1) end
		end
	end
end)

player.CharacterAdded:Connect(function(character)
	local st = state or restoreOnRespawn
	if not st then return end
	if state then stopSpectate() end
	restoreOnRespawn = nil
	restorePlayerCamera(st, character)
end)

print("✅ DeathCam prêt")