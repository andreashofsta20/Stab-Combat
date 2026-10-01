local SpawnMap = {}
local Maps = require(script.Parent:WaitForChild("Maps"))
local spawnedMaps: {[Instance]: boolean} = {}
local activeMap: Instance? = nil
local mapNames = {}
for _, info in pairs(Maps) do mapNames[info.MapFolder.Name] = true end

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
	for _, instance in ipairs(liveMaps()) do
		if instance ~= keep then instance:Destroy(); spawnedMaps[instance] = nil end
	end
	if activeMap ~= keep then activeMap = nil end
end

local function getMap(MapName: string)
	local info = Maps[MapName]
	return info and activeMap and activeMap.Parent == workspace and activeMap.Name == info.MapFolder.Name and activeMap or nil
end

local function collectSpawnParts(spawnFolder: Instance)
	local parts = {}
	for _, part in ipairs(spawnFolder:GetDescendants()) do
		if part:IsA("BasePart") and part.CanQuery then
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
	if not spawnPart then
	
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end

	hrp.CFrame = spawnPart.CFrame * CFrame.new(0, 10, 0)
	return true
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

	return teleportPlayerToSpawn(player, spawnParts[math.random(1, #spawnParts)])
end

function SpawnMap.Spawn(MapName: string)
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
	-- Validate before replacing the old map. There are no yields between cleanup
	-- and publication, so another spawn cannot leave two active map instances.
	removeExcept(nil)
	clone:SetAttribute("RoundMap", true)
	activeMap, spawnedMaps[clone] = clone, true
	clone.Parent = workspace
	return true
end

function SpawnMap.PlacePlayers(MapName: string, players: {Player}): number
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
	shuffleParts(spawnParts)

	local placed = 0
	for index, player in ipairs(players) do
		if player.Parent == game.Players then
			local spawnPart = spawnParts[((index - 1) % #spawnParts) + 1]
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root and character then
				root = character:WaitForChild("HumanoidRootPart", 5)
			end
			if character and root then
				character:PivotTo(spawnPart.CFrame * CFrame.new(0, 4, 0))
				placed += 1
			else
				warn("SpawnMap: player has no character to place:", player.Name)
			end
		end
	end

	return placed
end

function SpawnMap.RemoveAllMaps()
	removeExcept(nil)
end

function SpawnMap.RemoveOtherMapsThen(MapName: string)
	local mapInfo = Maps[MapName]
	if not mapInfo then
		warn("SpawnMap: Error: invalid map name : ", MapName)
		return
	end

	removeExcept(getMap(MapName))
end

-- Clean Studio leftovers during startup as well as at round transitions.
SpawnMap.RemoveAllMaps()

return SpawnMap
