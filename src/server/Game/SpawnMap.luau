local SpawnMap = {}
local Maps = require(script.Parent:WaitForChild("Maps"))
local Config = require(game:GetService("ReplicatedStorage").Modules.MapConfig)
local spawnedMaps: {[Instance]: boolean} = {}
local activeMap: Instance? = nil
local placements = {}
local changeVersion = 0
local lastRemovalAt = -math.huge
local fallbackMapNames = {
	["Cargo Port"] = true,
	["Grids"] = true,
	["Tropical Island"] = true,
	["Classic ROBLOX"] = true,
}
local mapNames = {}
local recentSpawns = setmetatable({}, {__mode = "k"})
function SpawnMap.ScoreSpawn(distance, visible, recent)
	return math.min(distance, 250) - (visible and 100 or 0) - (recent and 40 or 0)
end
for _, info in pairs(Maps) do mapNames[info.MapFolder.Name] = true end
for name in pairs(fallbackMapNames) do mapNames[name] = true end

local function isGameplayMap(instance: Instance): boolean
	return instance.Name ~= "IntermissionMap" and not instance:FindFirstChildOfClass("Humanoid")
		and (instance:IsA("Model") or instance:IsA("Folder"))
		and (mapNames[instance.Name] == true or instance:GetAttribute("RoundMap") == true)
end

local function liveMaps()
	local found, seen = {}, {}
	local function add(instance)
		if not seen[instance] then seen[instance] = true; table.insert(found, instance) end
	end
	-- Include pre-existing Studio copies and duplicate siblings, not just clones
	-- recorded by this module. Never sweep arbitrary Workspace objects/the lobby.
	for _, instance in ipairs(workspace:GetChildren()) do
		if isGameplayMap(instance) then add(instance) end
		if instance.Name == "Maps" and instance:IsA("Folder") then
			for _, nested in ipairs(instance:GetChildren()) do if isGameplayMap(nested) then add(nested) end end
		end
	end
	for instance in pairs(spawnedMaps) do add(instance) end
	return found
end

local function removeExcept(keep: Instance?)
	local removed = false
	if activeMap ~= keep then
		for player, record in pairs(placements) do
			if record.root and record.root.Parent then record.root.Anchored = record.anchored end
			placements[player] = nil
		end
	end
	for _, instance in ipairs(liveMaps()) do
		if instance ~= keep then
			instance:Destroy(); spawnedMaps[instance] = nil
			removed = true
		end
	end
	if removed then lastRemovalAt = os.clock() end
	if activeMap ~= keep then activeMap = nil end
end

local function getMap(MapName: string)
	local info = Maps[MapName]
	return info and activeMap and activeMap.Parent == workspace and activeMap.Name == info.MapFolder.Name
		and activeMap:GetAttribute("LobbyPreview") ~= true and activeMap or nil
end

local function collectSpawnParts(spawnFolder: Instance)
	local parts = {}
	for _, part in ipairs(spawnFolder:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

local function shuffleParts(parts)
	for i = #parts, 2, -1 do
		local j = math.random(i)
		parts[i], parts[j] = parts[j], parts[i]
	end
end

local function teleportPlayerToSpawn(player: Player, spawnPart: BasePart?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not spawnPart or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return false end
	local destination = spawnPart.CFrame * CFrame.new(0, Config.SpawnHeight, 0)
	root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	character:PivotTo(destination)
	root.CFrame = destination -- preserve the intended root position even with an unusual model pivot
	player:SetAttribute("ServerTeleportPosition", root.Position)
	player:SetAttribute("ServerTeleportVersion", (player:GetAttribute("ServerTeleportVersion") or 0) + 1)
	return (root.Position - destination.Position).Magnitude <= Config.PlacementTolerance
end

function SpawnMap.RespawnPlayer(player: Player, MapName: string)
	local mapInfo = Maps[MapName]
	if not mapInfo then
		return false
	end

	local map = getMap(MapName)
	local spawnFolder = map and map:FindFirstChild("Spawns", true)
	if not spawnFolder then
		return false
	end

	local spawnParts = collectSpawnParts(spawnFolder)
	if #spawnParts == 0 then
		return false
	end

	local selected = spawnParts[math.random(1, #spawnParts)]
	local scoring = Config.SpawnScoring
	if scoring and scoring.Enabled then
		shuffleParts(spawnParts)
		local enemies = {}
		for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
			local root = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			local hum = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 and other:GetAttribute("InRound") == true then
				table.insert(enemies, root); if #enemies >= scoring.MaxEnemies then break end
			end
		end
		local best = -math.huge
		for index = 1, math.min(scoring.MaxCandidates, #spawnParts) do
			local candidate = spawnParts[index]
			local nearest, distance = nil, scoring.DistanceCap
			for _, root in ipairs(enemies) do
				local value = (root.Position - candidate.Position).Magnitude
				if value < distance then nearest, distance = root, value end
			end
			local visible = false
			if nearest then
				local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = {spawnFolder, nearest.Parent, player.Character}
				local origin = candidate.Position + Vector3.new(0, Config.SpawnHeight, 0)
				visible = workspace:Raycast(origin, nearest.Position - origin, params) == nil
			end
			local score = SpawnMap.ScoreSpawn(distance, visible, recentSpawns[candidate] and os.clock() - recentSpawns[candidate] < scoring.ReuseSeconds)
			if score > best then best, selected = score, candidate end
		end
	end
	local placed = teleportPlayerToSpawn(player, selected)
	if placed then recentSpawns[selected] = os.clock() end
	return placed
end

function SpawnMap.Spawn(MapName: string, lobbyPreview: boolean?)
	if not MapName then
		return false
	end

	local mapInfo = Maps[MapName]
	if not mapInfo then
		warn("MODULE SPAWNMAP. Error is: invalid map name : ", MapName)
		return false
	end

	local folderName = mapInfo.MapFolder.Name

	local original = mapInfo.MapFolder
	if not original or not (original:IsA("Model") or original:IsA("Folder")) then
		warn("MODULE SPAWNMAP. Couldn't find map for : ", folderName)
		return false
	end

	local clone = original:Clone()
	if not clone then warn("SpawnMap: map template must be Archivable:", folderName); return false end
	local spawnFolder = clone:FindFirstChild("Spawns", true)
	if not spawnFolder then
		warn("MODULE SPAWNMAP. No Spawns folder for map : ", folderName)
		clone:Destroy()
		return false
	end

	local spawnParts = collectSpawnParts(spawnFolder)
	if #spawnParts == 0 then
		warn("MODULE SPAWNMAP. No spawn parts found in Spawns folder for map : ", folderName)
		clone:Destroy()
		return false
	end

	shuffleParts(spawnParts)
	-- Spawn markers are destinations for our controller, never automatic Roblox
	-- respawn targets. Lobby/FFA placement owns character movement explicitly.
	for _, item in ipairs(clone:GetDescendants()) do
		if item:IsA("SpawnLocation") then item.Enabled = false end
	end
	if lobbyPreview then
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BaseScript") then descendant.Enabled = false end
			if descendant:IsA("SpawnLocation") then descendant.Enabled = false end
		end
		local offset = Config.LobbyOffset
		if offset.X ~= 0 or offset.Y ~= 0 or offset.Z ~= 0 then
			local translation = Vector3.new(offset.X, offset.Y, offset.Z)
			for _, descendant in ipairs(clone:GetDescendants()) do
				if descendant:IsA("BasePart") then descendant.CFrame += translation end
			end
		end
	end
	-- Validate/prepare the clone off Workspace before removing the old map.
	-- A generation guards the deliberate gap: a later replacement or cleanup
	-- cancels this pending publication, rather than allowing duplicate maps.
	changeVersion += 1
	local version = changeVersion
	local seconds = Config.MapSwitchDelaySeconds
	if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds == math.huge then seconds = 1 end
	while true do
		if version ~= changeVersion then clone:Destroy(); return false end
		removeExcept(nil)
		local remaining = seconds - (os.clock() - lastRemovalAt)
		if remaining <= 0 then break end
		task.wait(remaining)
		-- Recheck after yielding. If a stray map appeared during the gap, its
		-- removal starts a fresh settling interval before this clone publishes.
	end
	clone:SetAttribute("RoundMap", true)
	clone:SetAttribute("LobbyPreview", lobbyPreview == true)
	activeMap, spawnedMaps[clone] = clone, true
	clone.Parent = workspace
	return true
end

function SpawnMap.ShowLobbyMap(): boolean
	if activeMap and activeMap.Parent == workspace and activeMap:GetAttribute("LobbyPreview") == true then
		changeVersion += 1
		removeExcept(activeMap)
		return true
	end
	return SpawnMap.Spawn(Config.LobbyMap, true)
end

function SpawnMap.ReleasePlacements()
	for player, record in pairs(placements) do
		if record.root and record.root.Parent then record.root.Anchored = record.anchored end
		placements[player] = nil
	end
end

local function placePlayers(MapName: string, players: {Player}, reuse: boolean): (number, {[number]: Model})
	local mapInfo = Maps[MapName]
	if not mapInfo then
		warn("SpawnMap: invalid map for placement:", MapName)
		return 0
	end

	local map = getMap(MapName)
	local spawnFolder = map and map:FindFirstChild("Spawns", true)
	if not spawnFolder then
		warn("SpawnMap: no Spawns folder for placement:", MapName)
		return 0
	end

	local spawnParts = collectSpawnParts(spawnFolder)
	if #spawnParts == 0 then
		warn("SpawnMap: no spawn parts for placement:", MapName)
		return 0
	end
	if not reuse then SpawnMap.ReleasePlacements(); shuffleParts(spawnParts) end
	local pending, remaining = {}, 0
	for index, player in ipairs(players) do
		if player.Parent == game.Players then
			local previous = reuse and placements[player]
			pending[player] = previous and previous.map == map and previous
				or {map = map, spawn = spawnParts[((index - 1) % #spawnParts) + 1]}
			remaining += 1
		end
	end
	local placed, placedCharacters = 0, {}
	local deadline = os.clock() + Config.PlacementTimeoutSeconds
	while remaining > 0 and activeMap == map and map.Parent == workspace do
		for player, record in pairs(pending) do
			if player.Parent ~= game.Players or player:GetAttribute("DataReady") ~= true then
				pending[player] = nil; remaining -= 1
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then continue end
			local destination = record.spawn.CFrame * CFrame.new(0, Config.SpawnHeight, 0)
			local sameCharacter = record.character == character and record.root == root
			if sameCharacter and record.confirmAt and os.clock() >= record.confirmAt and record.streamReady
				and (root.Position - destination.Position).Magnitude <= Config.PlacementTolerance then
				placed += 1; placedCharacters[player.UserId] = character
				pending[player] = nil; remaining -= 1
				continue
			end
			if not sameCharacter then
				if record.root and record.root.Parent then record.root.Anchored = record.anchored end
				record.character, record.root, record.anchored = character, root, root.Anchored == true
				record.streamReady = not workspace.StreamingEnabled
				if workspace.StreamingEnabled then
					local streamedCharacter = character
					task.spawn(function()
						local ok, err = pcall(function() player:RequestStreamAroundAsync(destination.Position, Config.StreamingTimeoutSeconds) end)
						if not ok then warn("SpawnMap: streaming request failed for", player.Name, err) end
						if record.character == streamedCharacter then record.streamReady = ok end
					end)
				end
			end
			placements[player] = record
			root.Anchored = true -- prevent client physics from undoing the countdown teleport
			if not record.confirmAt or not sameCharacter or (root.Position - destination.Position).Magnitude > Config.PlacementTolerance then
				teleportPlayerToSpawn(player, record.spawn)
				record.confirmAt = os.clock() + Config.PlacementRetrySeconds
			end
		end
		if remaining == 0 or os.clock() >= deadline then break end
		task.wait(Config.PlacementRetrySeconds)
	end
	for player in pairs(pending) do warn("SpawnMap: placement timed out for:", player.Name, MapName) end
	return placed, placedCharacters
end

function SpawnMap.PlacePlayers(MapName: string, players: {Player})
	return placePlayers(MapName, players, false)
end
function SpawnMap.VerifyPlayers(MapName: string, players: {Player})
	return placePlayers(MapName, players, true)
end

function SpawnMap.RemoveAllMaps()
	changeVersion += 1
	removeExcept(nil)
end

function SpawnMap.RemoveOtherMapsThen(MapName: string)
	local mapInfo = Maps[MapName]
	if not mapInfo then
		warn("SpawnMap: Error: invalid map name : ", MapName)
		return
	end

	changeVersion += 1
	removeExcept(getMap(MapName))
end

-- Clean Studio leftovers during startup as well as at round transitions.
SpawnMap.RemoveAllMaps()
local tutorial = script.Parent.Parent:FindFirstChild("Tutorial")
if not tutorial or not require(tutorial.TutorialRole).IsTutorial() then SpawnMap.ShowLobbyMap() end

return SpawnMap
