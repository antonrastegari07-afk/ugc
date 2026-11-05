-- LocalScript : StarterPlayer > StarterPlayerScripts > WeaponAnimationSharingClient
-- UNE boucle de rendu pour tous les joueurs. Aucune copie pour le joueur local.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local me=Players.LocalPlayer
-- Contours locaux : aucun envoi réseau, aucune modification des poses.
local Outline={arms={},suppressed={}}
local OUTLINE_BUDGET=28   -- contours max en même temps (Roblox : 31 ; on garde de la marge)
function Outline.mode()
	if me:GetAttribute("SettingEnemyOutlines")==false then return "Aucun" end
	if MODE_CONTOUR=="Aucun" or MODE_CONTOUR=="Corps" then return MODE_CONTOUR end
	return "Complet"
end
function Outline.restore(h)
	local record=Outline.suppressed[h]
	if not record then return end
	record.connection:Disconnect(); Outline.suppressed[h]=nil
	if h.Parent and h.OutlineTransparency==1 then h.OutlineTransparency=record.value end
end
function Outline.suppress(h)
	local record=Outline.suppressed[h]
	if not record then
		record={value=h.OutlineTransparency}; Outline.suppressed[h]=record
		record.connection=h:GetPropertyChangedSignal("OutlineTransparency"):Connect(function()
			-- ArenaHighlights peut réécrire sa valeur : le mode Aucun reste prioritaire.
			if h.OutlineTransparency~=1 then
				record.value=h.OutlineTransparency
				if Outline.mode()=="Aucun" then h.OutlineTransparency=1 end
			end
		end)
	end
	if h.OutlineTransparency~=1 then h.OutlineTransparency=1 end
end
function Outline.sources(char,player)
	local found={}
	for _,h in ipairs(char:GetChildren()) do
		if h:IsA("Highlight") and (h.Name=="ArenaOutline_"..player.UserId or h.Name=="EnemyOutline"
			or h.Adornee==char or (h.Adornee==nil and h.Parent==char)) then
			found[#found+1]=h
		end
	end
	return found
end
function Outline.detach(s)
	local pair=Outline.arms[s]
	if not pair then return end
	for _,h in ipairs(pair) do h:Destroy() end
	Outline.arms[s]=nil
end
function Outline.attach(s)
	Outline.detach(s)
	local pair={}
	for _,arm in ipairs({s.visual.right,s.visual.left}) do
		local h=Instance.new("Highlight")
		h.Name="SharedArmOutline"; h.Enabled=false
		h.FillTransparency=1; h.OutlineColor=Color3.fromRGB(255,45,45)
		h.OutlineTransparency=0; h.DepthMode=Enum.HighlightDepthMode.Occluded
		h.Adornee=arm; h.Parent=arm -- uniquement ce bras : pas le gun / le chargeur
		pair[#pair+1]=h
	end
	Outline.arms[s]=pair
end
function Outline.step()
	local mode=Outline.mode()
	local sources,seen={},{}
	-- Seulement les Highlights directement portés par les personnages (ArenaHighlights).
	-- Pas de parcours de Workspace ni des pièces d'armes à chaque image.
	for _,player in ipairs(Players:GetPlayers()) do
		local char=player.Character
		if player~=me and char then
			for _,h in ipairs(Outline.sources(char,player)) do
				seen[h]=true
				if mode=="Aucun" then Outline.suppress(h) else Outline.restore(h) end
				if h.Enabled and h.OutlineTransparency<1 then
					if not sources[player] or h.Name=="ArenaOutline_"..player.UserId then sources[player]=h end
				end
			end
		end
	end
	for h in pairs(Outline.suppressed) do if not seen[h] then Outline.restore(h) end end
	-- 🔴 LIMITE ROBLOX : 31 contours (Highlight) affichés à la fois, au-delà
	-- certains disparaissent AU HASARD. Corps (ArenaHighlights) + 2 bras par
	-- ennemi armé dépassaient vite la limite → des ennemis sans contour.
	-- Les corps passent en PRIORITÉ ; les bras seulement pour les ennemis les
	-- plus proches, tant qu'on reste sous la limite.
	local bodies=0
	for _ in pairs(sources) do bodies+=1 end
	local armSlots=math.max(0,math.floor((OUTLINE_BUDGET-bodies)/2))
	local myRoot=me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	local cands={}
	for s in pairs(Outline.arms) do
		if mode=="Complet" and sources[s.player]~=nil and s.model and s.model.Parent then
			local ch=s.player and s.player.Character
			local r=ch and ch:FindFirstChild("HumanoidRootPart")
			cands[#cands+1]={s=s,d=(myRoot and r) and (r.Position-myRoot.Position).Magnitude or math.huge}
		end
	end
	table.sort(cands,function(a,b) return a.d<b.d end)
	local allowArms={}
	for i,c in ipairs(cands) do if i<=armSlots then allowArms[c.s]=true end end
	for s,pair in pairs(Outline.arms) do
		local source=sources[s.player]
		local show=allowArms[s]==true and source~=nil
		for _,h in ipairs(pair) do
			if show then
				if h.OutlineColor~=source.OutlineColor then h.OutlineColor=source.OutlineColor end
				if h.OutlineTransparency~=source.OutlineTransparency then h.OutlineTransparency=source.OutlineTransparency end
				if h.DepthMode~=source.DepthMode then h.DepthMode=source.DepthMode end
			end
			local enabled=show and true or false
			if h.Enabled~=enabled then h.Enabled=enabled end
		end
	end
end
local outlineElapsed=0
local outlineConnection=RunService.Heartbeat:Connect(function(dt)
	outlineElapsed+=dt
	if outlineElapsed<0.1 then return end
	outlineElapsed=0; Outline.step()
end)
script.Destroying:Connect(function()
	outlineConnection:Disconnect()
	for s in pairs(Outline.arms) do Outline.detach(s) end
	for h in pairs(Outline.suppressed) do Outline.restore(h) end
end)

local system=RS:WaitForChild("WeaponSystem")
local C=require(system:WaitForChild("WeaponAnimationSharingConfig"))
if not C.Enabled then return end
local Codec=require(system:WaitForChild("WeaponAnimationSharingCodec"))
local network=RS:WaitForChild("WeaponAnimationNetwork",15)
if not network then warn("Partage des animations : ajoute WeaponAnimationSharingServer dans ServerScriptService."); return end
local control=network:WaitForChild("Control")
local stream=network:WaitForChild("Poses")
local states={}
local container
local renderConnection
local function canSee()
	return network:GetAttribute("Enabled")==true
		and not (C.Visual.RespectPerformanceMode and me:GetAttribute("SettingPerfMode")==true)
end
local function cleanup(s)
	Outline.detach(s)
	if s.gk and s.tool then s.gk.FlashHost[s.tool]=nil end; s.gk=nil   -- [Combat S4]
	if s.added then s.added:Disconnect(); s.added=nil end
	if s.removing then s.removing:Disconnect(); s.removing=nil end
	for p,old in pairs(s.hidden or {}) do if p.Parent then p.LocalTransparencyModifier=old end end
	s.hidden={}
	if s.model then s.model:Destroy(); s.model=nil end
	if s.drop then s.drop.part:Destroy(); s.drop=nil end
	s.visual=nil; s.oldMag=nil; s.kick=0
end
local function remove(p)
	local s=states[p]
	if s then cleanup(s); states[p]=nil end
end
-- [Combat S1] armes GunKit : pièces animées, visibilité, flash et recul fournis par GunKit.NetClient
local gkNet=nil
local function GKNet()
	if gkNet~=nil then return gkNet or nil end
	local gk=RS:FindFirstChild("GunKit")
	local m=gk and gk:FindFirstChild("NetClient")
	if not m then return nil end
	local ok,r=pcall(require,m)
	gkNet=(ok and type(r)=="table" and r.RelOf) and r or false
	return gkNet or nil
end
local function visualPart(src)
	if not src.Archivable then return nil end
	local p=src:Clone()
	-- Liste blanche : aucun script, joint, son, émetteur, interaction ou sous-part.
	for _,d in ipairs(p:GetDescendants()) do
		if not (d:IsA("DataModelMesh") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance")) then d:Destroy() end
	end
	p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false
	p.Massless=true; p.LocalTransparencyModifier=0
	return p
end
local function findPath(tool,path)
	local p=tool
	for _,name in ipairs(path or {}) do p=p and p:FindFirstChild(name) end
	return p
end
local function weaponBindings(tool,handle,catalog)
	-- Graphe enraciné : Handle et pièces animées sont des racines DISTINCTES.
	-- Un weld inversé ne doit pas faire dépendre tout le gun du chargeur masqué.
	local adjacency,bindings,queue={},{},{}
	local function edge(a,b,cf)
		adjacency[a]=adjacency[a] or {}; table.insert(adjacency[a],{part=b,cf=cf})
	end
	for _,j in ipairs(tool:GetDescendants()) do
		if (j:IsA("JointInstance") or j:IsA("WeldConstraint")) and j.Part0 and j.Part1
			and j.Part0:IsDescendantOf(tool) and j.Part1:IsDescendantOf(tool) then
			local rel
			if j:IsA("JointInstance") then rel=j.C0*j.C1:Inverse()
			else rel=j.Part0.CFrame:ToObjectSpace(j.Part1.CFrame) end
			edge(j.Part0,j.Part1,rel); edge(j.Part1,j.Part0,rel:Inverse())
		end
	end
	bindings[handle]={rel=CFrame.identity}; queue[1]=handle
	for i,v in ipairs(catalog) do
		bindings[v.part]={index=i,rel=CFrame.identity}; queue[#queue+1]=v.part
	end
	local at=1
	while at<=#queue do
		local part=queue[at]; at+=1
		local b=bindings[part]
		for _,e in ipairs(adjacency[part] or {}) do
			if not bindings[e.part] then
				bindings[e.part]={index=b.index,rel=b.rel*e.cf}; queue[#queue+1]=e.part
			end
		end
	end
	return bindings
end
local function build(s)
	local char=s.player.Character
	local torso=char and char:FindFirstChild("Torso")
	local ra=char and char:FindFirstChild("Right Arm")
	local la=char and char:FindFirstChild("Left Arm")
	local tool=s.tool
	if not tool or tool.Parent~=char then
		tool=nil
		for _,child in ipairs(char and char:GetChildren() or {}) do
			if child:IsA("Tool") and child:GetAttribute("WeaponAnimationSession")==s.id then tool=child; break end
		end
	end
	local handle=tool and tool:FindFirstChild("Handle")
	if not (torso and ra and la and tool and handle) then return false end
	for _,v in ipairs(s.catalog) do
		if not v.part or not v.part:IsDescendantOf(tool) then v.part=findPath(tool,v.path) end
		if not v.part or not v.part:IsA("BasePart") then return false end
		if v.groupPath then v.group=findPath(tool,v.groupPath); if not v.group then return false end end
	end
	local originals={}
	for _,d in ipairs(tool:GetDescendants()) do if d:IsA("BasePart") then table.insert(originals,d) end end
	if #originals>math.clamp(C.Visual.MaxWeaponParts,1,300) then return false end
	local model=Instance.new("Model"); model.Name="SharedWeapon_"..s.player.UserId
	local right,left=visualPart(ra),visualPart(la)
	if not right or not left then model:Destroy(); if right then right:Destroy() end; if left then left:Destroy() end; return false end
	right.Parent=model; left.Parent=model
	-- Conserve les vêtements classiques R6 sur les bras de la copie locale.
	local body=visualPart(torso)
	if body then body.Transparency=1; body.Parent=model end
	local head=char:FindFirstChild("Head")
	local headCopy=head and visualPart(head)
	if headCopy then headCopy.Transparency=1; headCopy.Parent=model end
	for _,d in ipairs(char:GetChildren()) do
		if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("BodyColors") then d:Clone().Parent=model end
	end
	local hum=Instance.new("Humanoid"); hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType=Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.EvaluateStateMachine=false; hum.RequiresNeck=false; hum.Parent=model
	local visual={right=right,left=left,body=body,head=headCopy,parts={},map={},moveParts={right,left},moveFrames={}}
	if body then table.insert(visual.moveParts,body) end
	if headCopy then table.insert(visual.moveParts,headCopy) end
	visual.armCount=#visual.moveParts
	local bindings=weaponBindings(tool,handle,s.catalog)
	for _,src in ipairs(originals) do
		local clone=visualPart(src)
		if not clone then model:Destroy(); return false end -- aucune arme à moitié masquée
		clone.Parent=model
		local binding=bindings[src]
		if not binding then
			local anchor=handle; local index
			for i,record in ipairs(s.catalog) do
				if (record.group and src:IsDescendantOf(record.group)) or src:IsDescendantOf(record.part) then
					anchor=record.part; index=i; break
				end
			end
			binding={index=index,rel=anchor.CFrame:ToObjectSpace(src.CFrame)}
		end
		local v={part=clone,source=src,index=binding.index,rel=binding.rel,t=src.Transparency}
		visual.parts[#visual.parts+1]=v; visual.map[src]=v
		table.insert(visual.moveParts,clone)
	end
	if not container then container=Instance.new("Folder"); container.Name="SharedWeaponVisuals"; container.Parent=workspace end
	s.torso=torso; s.char=char; s.tool=tool; s.visual=visual; s.model=model; s.hidden={}
	-- [Combat S2] arme GunKit : NetClient pose les pièces, la copie les recopie (flash sur l'arme qu'on voit)
	s.gk=(tool:GetAttribute("GunKitNetParts")==true) and GKNet() or nil
	if s.gk then
		for _,v in ipairs(visual.parts) do
			if v.source.Name=="Flash" then s.gk.FlashHost[tool]=v.part end
		end
	end
	-- [Combat S6] flash + fumée MuzzleFX des tirs de ce joueur : sur l'arme qu'on VOIT (la copie)
	do
		local wsf=RS:FindFirstChild("WeaponSystem")
		local mzm=wsf and wsf:FindFirstChild("MuzzleFX")
		local okM,MZ=false,nil
		if mzm then okM,MZ=pcall(require,mzm) end
		if okM and type(MZ)=="table" and MZ.Hosts then
			for _,v in ipairs(visual.parts) do
				if v.source.Name=="Flash" then MZ.Hosts[tool]=v.part end
			end
		end
	end
	s.dirty=false
	s.added=tool.DescendantAdded:Connect(function(d) if d:IsA("BasePart") then s.dirty=true end end)
	s.removing=tool.DescendantRemoving:Connect(function(d) if d:IsA("BasePart") then s.dirty=true end end)
	-- On ne déplace ni les vrais bras, ni les vraies pièces, ni les hitboxes.
	-- [Combat S5] valeur normale = 0 (une autre vue, comme celle du tueur, peut les avoir cachées un instant)
	for _,src in ipairs(originals) do s.hidden[src]=0; src.LocalTransparencyModifier=1 end
	for _,src in ipairs({ra,la}) do s.hidden[src]=0; src.LocalTransparencyModifier=1 end
	model.Parent=container
	Outline.attach(s); Outline.step()
	return true
end
local function dropMagazine(s,record)
	if not C.Visual.MagazineDrops or not C.Animations.Magazine then return end
	local v=s.visual.map[record.part]
	if not v then return end
	if s.drop then s.drop.part:Destroy() end
	local clone=visualPart(v.part)
	if not clone then return end
	clone.Transparency=v.t; clone.CFrame=v.part.CFrame; clone.Parent=container
	local ignore={container,workspace.CurrentCamera}
	for _,p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignore,p.Character) end end
	local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances=ignore
	local root=s.char:FindFirstChild("HumanoidRootPart")
	local carry=root and root.AssemblyLinearVelocity or Vector3.zero
	local life=math.clamp(C.Visual.MagazineLife,0.5,8)
	s.drop={part=clone,velocity=carry+Vector3.new(0,-2,0),born=os.clock(),life=life,params=params,settled=false}
	Debris:AddItem(clone,life+0.1) -- filet indépendant du lecteur et de la mort de l'arme
end
local function updateDrop(s,dt)
	local d=s.drop
	if not d then return end
	local age=os.clock()-d.born
	if not d.part.Parent or age>=d.life then d.part:Destroy(); s.drop=nil; return end
	if not d.settled then
		local h=math.min(dt,0.05)
		d.velocity+=Vector3.new(0,-workspace.Gravity*h,0)
		local move=d.velocity*h
		local hit=workspace:Raycast(d.part.Position,move,d.params)
		if hit then
			d.part.CFrame=CFrame.new(hit.Position+hit.Normal*0.06)*(d.part.CFrame-d.part.Position)
			if hit.Normal.Y>0.5 then
				d.settled=true
			else
				-- Un mur ne doit pas devenir un support invisible : on rebondit,
				-- puis la gravité continue jusqu'au sol ou à l'expiration.
				local normalSpeed=d.velocity:Dot(hit.Normal)
				if normalSpeed<0 then d.velocity-=hit.Normal*(normalSpeed*1.25) end
			end
		else d.part.CFrame=(d.part.CFrame+move)*CFrame.Angles(h*3,h*2,0) end
	end
	if age>d.life-0.5 then d.part.Transparency=math.clamp((age-d.life+0.5)/0.5,0,1) end
end
local function accept(s,time,b)
	local p=Codec.Decode(b,#s.catalog)
	if not p or p.seq<=s.seq then return end
	s.seq=p.seq; p.time=time; s.received=os.clock()
	-- [Combat S7] l'heure posée par le serveur est celle de l'ARRIVÉE : avec la gigue du réseau et les paquets
	-- groupés, deux poses peuvent arriver presque ensemble puis plus rien -> l'interpolation accélère, s'arrête,
	-- saute (« framy »). Les poses partent pourtant à cadence fixe : on reconstruit cette cadence à partir du
	-- n° de paquet, et on ne suit l'heure d'arrivée que lentement (ou d'un coup après une pause).
	do
		local ck=s.ck
		local step0=1/math.clamp(C.Network.SendRate,5,20)
		if ck and p.seq>ck.seq then
			local n=p.seq-ck.seq
			local guess=ck.t+n*ck.step
			local err=time-guess
			if err>-0.15 and err<0.15 then
				p.time=guess+err*0.12
				ck.step=math.clamp(ck.step+(err/n)*0.08,1/30,0.5)
			end
		end
		s.ck={seq=p.seq,t=p.time,step=(ck and ck.step) or step0}
		time=p.time
	end
	local q=s.queue
	-- 🩹 reprise après une pause (pose immobile = 1 envoi / 0.5 s) : on « tient »
	-- l'ancienne pose jusqu'à juste avant la nouvelle, au lieu d'interpoler sur
	-- 0.5 s et de sauter d'un coup à 80 % du trajet.
	local last=q[#q]
	local step=1/math.clamp(C.Network.SendRate,5,20)
	if last and time-last.time>step*1.5 then
		local hold=table.clone(last); hold.time=time-step
		q[#q+1]=hold
	end
	q[#q+1]=p
	while #q>12 do table.remove(q,1) end
end
local function draw(s,dt,now)
	local q=s.queue
	if #q==0 then return end
	local stamp=now-math.clamp(C.Network.Interpolation,0.03,0.25)
	while #q>2 and q[2].time<=stamp do table.remove(q,1) end
	local a,b=q[1],q[2] or q[1]
	local x=b.time>a.time and math.clamp((stamp-a.time)/(b.time-a.time),0,1) or 1
	local pose=Codec.Blend(a,b,x)
	-- [Combat S8] lissage final : entre deux poses reçues le trajet est en ligne droite, avec un « coin » à chaque
	-- paquet. Un suivi amorti (~45 ms) arrondit ces coins ; un grand saut (téléport, nouvelle arme) passe direct.
	do
		local sm=s.smooth
		if sm then
			local k=1-math.exp(-dt*(C.Network.Smoothing or 22))
			local function f(old,new)
				if (old.Position-new.Position).Magnitude>1.5 then return new end
				return old:Lerp(new,k)
			end
			pose.r=f(sm.r,pose.r); pose.l=f(sm.l,pose.l); pose.g=f(sm.g,pose.g)
			for i,v in ipairs(pose.parts) do
				local o=sm.parts[i]
				if o and o.hidden==v.hidden then v.cf=f(o.cf,v.cf) end
			end
		end
		s.smooth=pose
	end
	-- Le recul est déjà dans les welds 3P transmis : ne rien ajouter ici.
	local base=s.torso.CFrame
	local right,left=base*pose.r,base*pose.l
	local handle=base*pose.g
	local frames=s.visual.moveFrames
	frames[1]=right; frames[2]=left
	local armIndex=2
	if s.visual.body then armIndex+=1; frames[armIndex]=s.torso.CFrame end
	if s.visual.head then armIndex+=1; frames[armIndex]=s.torso.CFrame*CFrame.new(0,1.5,0) end
	for i,entry in ipairs(s.catalog) do
		if entry.mag then
			local hidden=pose.parts[i].hidden
			if s.oldMag==false and hidden then dropMagazine(s,entry) end
			s.oldMag=hidden
		end
	end
	-- [Combat S3] arme GunKit : chaque pièce à la place où NetClient l'a posée (barillet, chien, speedloader…),
	-- avec sa visibilité (le recul de l'arme est déjà dans les bras / le Handle transmis)
	local gk=s.gk
	for i,v in ipairs(s.visual.parts) do
		local dyn=v.index and pose.parts[v.index]
		local rel=v.rel
		local transparency=(dyn and dyn.hidden) and 1 or v.t
		if gk and not dyn then
			local r=gk.RelOf(s.tool,v.source)
			if r then rel=r end
			transparency=v.source.Transparency
		end
		frames[s.visual.armCount+i]=(dyn and base*dyn.cf or handle)*rel
		if v.part.Transparency~=transparency then v.part.Transparency=transparency end
	end
	workspace:BulkMoveTo(s.visual.moveParts,frames,Enum.BulkMoveMode.FireCFrameChanged)
	updateDrop(s,dt)
end
local function ensureLoop()
	if renderConnection then return end
	renderConnection=RunService.RenderStepped:Connect(function(dt)
		local now=os.clock(); local time=workspace:GetServerTimeNow(); local allowed=canSee()
		local myChar=me.Character; local myRoot=myChar and myChar:FindFirstChild("HumanoidRootPart")
		for player,s in pairs(states) do
			local char=player.Character
			local h=char and char:FindFirstChildOfClass("Humanoid")
			local root=char and char:FindFirstChild("HumanoidRootPart")
			if (h and h.Health<=0) or (char and s.char and s.char~=char)
				or (s.tool and s.tool.Parent and s.tool.Parent~=char) then remove(player); continue end
			if not (char and h and root) then cleanup(s); continue end
			if s.tool and not s.tool.Parent then cleanup(s); s.tool=nil end
			local close=myRoot and root and (myRoot.Position-root.Position).Magnitude<=C.Network.MaxDistance
			if not allowed or not close or now-s.received>math.max(1,C.Network.Timeout) then
				if s.model then cleanup(s) end
				continue
			end
			if #s.queue==0 then continue end
			if s.dirty and s.model then cleanup(s) end
			if not s.model then
				if now<(s.retry or 0) then continue end
				s.retry=now+0.3
				if not build(s) then continue end
			end
			-- Streaming : une référence détruite ne laisse jamais un original caché.
			if not s.torso.Parent or not s.tool:IsDescendantOf(workspace) then cleanup(s); continue end
			draw(s,math.min(dt,0.1),time)
		end
		if next(states)==nil then
			renderConnection:Disconnect(); renderConnection=nil
			if container then container:Destroy(); container=nil end
		end
	end)
end
control.OnClientEvent:Connect(function(kind,p,tool,id,catalog,last,time)
	if kind=="Begin" then
		if p==me or typeof(p)~="Instance" or not p:IsA("Player") then return end
		remove(p)
		local s={player=p,tool=tool,id=id,catalog=catalog,queue={},seq=-1,received=os.clock(),hidden={}}
		states[p]=s
		if last then accept(s,time,last) end
		ensureLoop()
	elseif kind=="End" then
		-- Pour End, le troisième argument est l'identifiant de session.
		if states[p] and states[p].id==tool then remove(p) end
	end
end)
stream.OnClientEvent:Connect(function(p,id,time,b)
	local s=states[p]
	if s and s.id==id then accept(s,time,b) end
end)
Players.PlayerRemoving:Connect(remove)
network:GetAttributeChangedSignal("Enabled"):Connect(function()
	if not canSee() then for _,s in pairs(states) do cleanup(s) end end
end)
script.Destroying:Connect(function()
	for _,s in pairs(states) do cleanup(s) end
	if renderConnection then renderConnection:Disconnect() end
	if container then container:Destroy() end
end)