# 🎰 Roulette : « Loading... » infini

## Serveur — ServerScriptService ▸ dailyspin server
Cherche :
```lua
getSpinDataFunc.OnServerInvoke = function(player)
	if not player or not player.Parent then return nil end
	waitForLoad(player.UserId)
	return buildClientState(player.UserId)
end
```
Remplace par :
```lua
getSpinDataFunc.OnServerInvoke = function(player)
	if not player or not player.Parent then return nil end
	local userId = player.UserId
	-- 🔁 lecture ratée à l'arrivée : on la relance ici (avant : « Loading... » pour toujours)
	if not spinDataLoaded[userId] then loadPlayerData(userId) end
	waitForLoad(userId)
	return buildClientState(userId)
end
```

## Client — StarterPlayerScripts ▸ dailyspin local
Cherche :
```lua
local function refreshState()
	local revision = stateRevision
	local ok, state = pcall(function() return getSpinDataFunc:InvokeServer() end)
	if revision ~= stateRevision then return currentState.loading ~= true end
	if ok then return applyServerState(state) end
	return false
end
```
Remplace par :
```lua
local function refreshState()
	local revision = stateRevision
	local ok, state = pcall(function() return getSpinDataFunc:InvokeServer() end)
	if revision ~= stateRevision then return currentState.loading ~= true end
	if ok then return applyServerState(state) end
	return false
end

-- 🔁 Jamais bloqué sur « Loading... » : tant que la roue attend le serveur, on redemande
--    (toutes les 3 s roue ouverte, 15 s fermée). Le serveur reste le seul à décider.
local refreshBusy, refreshAt = false, 0
task.spawn(function()
	local last = 0
	while true do
		task.wait(1)
		local every = gui.Enabled and 3 or 15
		if currentState.loading == true and not requestPending and not isSpinning
			and os.clock() - last >= every and (not refreshBusy or os.clock() - refreshAt > 15) then
			last = os.clock()
			refreshBusy, refreshAt = true, os.clock()
			task.spawn(function()
				pcall(refreshState)
				refreshBusy = false
			end)
		end
	end
end)
```
